import Foundation
import EventKit

public struct WritableContainerInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let sourceTitle: String

    public init(id: String, title: String, sourceTitle: String) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
    }
}

public enum ExternalWriteExecutionResult: Equatable, Sendable {
    case created(externalIdentifier: String, containerIdentifier: String, containerTitle: String)
    case skippedAlreadyCreated(externalIdentifier: String)
    case blockedPendingVerification(reason: String)
    case permissionDenied(String)
    case failed(errorCode: String, message: String, isUncertainReceipt: Bool)
}

/// 负责 Apple 日历与 Apple 提醒事项的权限申请、容器列表读取、防重创建与操作审计（PRD R18, R19, R22, 4.7, 8.1）
public final class EventKitIntegrationService: @unchecked Sendable {
    public static let shared = EventKitIntegrationService()
    private let eventStore = EKEventStore()

    public init() {}

    // MARK: - Permission Status & Request (PRD 8.1 & 9.2: 日历与提醒事项分别申请权限)

    public func calendarAuthorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    public func remindersAuthorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    public func requestCalendarAccess() async -> Bool {
        do {
            if #available(iOS 17.0, macOS 14.0, *) {
                return try await eventStore.requestFullAccessToEvents()
            } else {
                return try await eventStore.requestAccess(to: .event)
            }
        } catch {
            return false
        }
    }

    public func requestRemindersAccess() async -> Bool {
        do {
            if #available(iOS 17.0, macOS 14.0, *) {
                return try await eventStore.requestFullAccessToReminders()
            } else {
                return try await eventStore.requestAccess(to: .reminder)
            }
        } catch {
            return false
        }
    }

    public func writableCalendars() -> [WritableContainerInfo] {
        let status = calendarAuthorizationStatus()
        guard status == .fullAccess || status == .authorized else { return [] }
        return eventStore.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map { WritableContainerInfo(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source.title) }
    }

    public func writableReminderLists() -> [WritableContainerInfo] {
        let status = remindersAuthorizationStatus()
        guard status == .fullAccess || status == .authorized else { return [] }
        return eventStore.calendars(for: .reminder)
            .filter { $0.allowsContentModifications }
            .map { WritableContainerInfo(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source.title) }
    }

    // MARK: - Calendar Event Creation (PRD R18 & A12 & A15 & A16 & A19)

    public func createCalendarEvent(
        for action: ConfirmedAction,
        recordingTitle: String,
        existingLink: ExternalActionLink?,
        preferredCalendarId: String?
    ) async -> ExternalWriteExecutionResult {
        // 1. 去重与不确定状态检查（PRD R19 & A16）
        if action.executionStatus == .pendingVerification {
            return .blockedPendingVerification(reason: "上次写入回执状态不确定，请先在 Apple 日历中核查是否已存在该日程，避免重复创建。")
        }
        if let link = existingLink,
           let extId = link.externalIdentifier,
           !extId.isEmpty,
           action.executionStatus == .handedToExternal {
            return .skippedAlreadyCreated(externalIdentifier: extId)
        }

        let snap = action.confirmedSnapshot
        guard snap.datePrecision == .exactTime,
              let startAt = snap.startAt,
              let endAt = snap.endAt else {
            return .failed(
                errorCode: "INVALID_EVENT_TIME",
                message: "日程缺少明确的开始或结束时刻，不能静默创建为全天事件，请先补充具体时间。",
                isUncertainReceipt: false
            )
        }

        // 2. 检查与申请日历权限（PRD A15）
        let granted = await requestCalendarAccess()
        guard granted else {
            return .permissionDenied("未获得 Apple 日历写入权限。该日程候选已保留在本地，你也可以改为导出 Markdown。")
        }

        // 3. 选择目标可写日历（PRD A19）
        let calendars = eventStore.calendars(for: .event).filter { $0.allowsContentModifications }
        let targetCalendar = calendars.first(where: { $0.calendarIdentifier == preferredCalendarId })
            ?? eventStore.defaultCalendarForNewEvents
            ?? calendars.first

        guard let calendar = targetCalendar, calendar.allowsContentModifications else {
            return .failed(
                errorCode: "NO_WRITABLE_CALENDAR",
                message: "未找到可写入的 Apple 日历账户，请检查系统日历设置后重试。",
                isUncertainReceipt: false
            )
        }

        // 4. 组装并写入 EKEvent
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = snap.description
        event.location = snap.location
        event.startDate = startAt
        event.endDate = endAt
        event.timeZone = TimeZone(identifier: snap.timeZoneIdentifier) ?? .current

        let timeRangeStr = snap.evidenceStartMs.map { TimeFormatting.formatMilliseconds($0) } ?? "手动添加"
        event.notes = """
        来源录音：\(recordingTitle) [\(timeRangeStr)]
        原话证据：「\(snap.evidenceQuote)」
        由 MemoFlow 审核后创建
        """

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            guard let identifier = event.eventIdentifier, !identifier.isEmpty else {
                // 极少见的调用未抛错但未拿到回执 ID 的情形 -> 标记为待核查（PRD R19 & A19）
                return .failed(
                    errorCode: "UNCERTAIN_EVENT_RECEIPT",
                    message: "系统日历已响应但未返回事件回执 ID，请先打开日历核查是否已创建。",
                    isUncertainReceipt: true
                )
            }
            return .created(
                externalIdentifier: identifier,
                containerIdentifier: calendar.calendarIdentifier,
                containerTitle: calendar.title
            )
        } catch {
            return .failed(
                errorCode: "EVENTKIT_SAVE_ERROR",
                message: "写入 Apple 日历失败：\(error.localizedDescription)",
                isUncertainReceipt: false
            )
        }
    }

    // MARK: - Apple Reminders Creation (PRD R22 & A14 & A23 & A24)

    public func createReminderItem(
        for action: ConfirmedAction,
        recordingTitle: String,
        existingLink: ExternalActionLink?,
        preferredListId: String?
    ) async -> ExternalWriteExecutionResult {
        // 1. 去重与待核查保护（PRD R19 & A16）
        if action.executionStatus == .pendingVerification {
            return .blockedPendingVerification(reason: "上次写入提醒事项回执不确定，请先打开「提醒事项」核查是否已存在，避免重复创建。")
        }
        if let link = existingLink,
           let extId = link.externalIdentifier,
           !extId.isEmpty,
           action.executionStatus == .handedToExternal {
            return .skippedAlreadyCreated(externalIdentifier: extId)
        }

        // 2. 单独检查与申请提醒事项权限（PRD 8.1 & A24：提醒事项权限不可沿用日历权限）
        let granted = await requestRemindersAccess()
        guard granted else {
            return .permissionDenied("未获得 Apple 提醒事项权限。该待办仍保留在本地，可随时切换为本地管理或导出 Markdown。")
        }

        // 3. 选择目标提醒事项列表
        let lists = eventStore.calendars(for: .reminder).filter { $0.allowsContentModifications }
        let targetList = lists.first(where: { $0.calendarIdentifier == preferredListId })
            ?? eventStore.defaultCalendarForNewReminders()
            ?? lists.first

        guard let reminderList = targetList, reminderList.allowsContentModifications else {
            return .failed(
                errorCode: "NO_WRITABLE_REMINDER_LIST",
                message: "未找到可写入的 Apple 提醒事项列表，请检查系统设置。",
                isUncertainReceipt: false
            )
        }

        let snap = action.confirmedSnapshot
        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = reminderList
        reminder.title = snap.description

        // 4. 严格保留日期精度（PRD R22 & A14 & A23：仅有日期时不臆造具体时刻；无日期时不补造截止时间）
        var cal = Calendar(identifier: .gregorian)
        let tz = TimeZone(identifier: snap.timeZoneIdentifier) ?? .current
        cal.timeZone = tz

        switch snap.datePrecision {
        case .dateOnly:
            if let due = snap.dueDate {
                // 只设置年、月、日，绝不设置 hour / minute（PRD R22）
                reminder.dueDateComponents = cal.dateComponents([.year, .month, .day], from: due)
            }
        case .exactTime:
            if let exactDate = snap.dueDate ?? snap.startAt {
                var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: exactDate)
                comps.timeZone = tz
                reminder.dueDateComponents = comps
            }
        case .none, .ambiguous:
            reminder.dueDateComponents = nil
        }

        let timeRangeStr = snap.evidenceStartMs.map { TimeFormatting.formatMilliseconds($0) } ?? "手动添加"
        reminder.notes = """
        来源录音：\(recordingTitle) [\(timeRangeStr)]
        原话证据：「\(snap.evidenceQuote)」
        由 MemoFlow 审核后创建
        """

        do {
            try eventStore.save(reminder, commit: true)
            let identifier = reminder.calendarItemIdentifier
            guard !identifier.isEmpty else {
                return .failed(
                    errorCode: "UNCERTAIN_REMINDER_RECEIPT",
                    message: "提醒事项已响应但未返回有效 ID，请先核查是否已创建。",
                    isUncertainReceipt: true
                )
            }
            return .created(
                externalIdentifier: identifier,
                containerIdentifier: reminderList.calendarIdentifier,
                containerTitle: reminderList.title
            )
        } catch {
            return .failed(
                errorCode: "REMINDER_SAVE_ERROR",
                message: "写入 Apple 提醒事项失败：\(error.localizedDescription)",
                isUncertainReceipt: false
            )
        }
    }
}
