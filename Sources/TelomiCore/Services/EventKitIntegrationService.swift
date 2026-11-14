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

/// 呈现给用户的 Apple 日历事件视图模型（CAL-002）
public struct CalendarEventItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let calendarTitle: String
    public let calendarColorHex: String?
    public let location: String?
    public let notes: String?

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarTitle: String,
        calendarColorHex: String? = nil,
        location: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.calendarColorHex = calendarColorHex
        self.location = location
        self.notes = notes
    }
}

/// 呈现给用户的 Apple 提醒事项视图模型（CAL-002）
public struct ReminderTaskItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let dueDate: Date?
    public var isCompleted: Bool
    public let completionDate: Date?
    public let priority: Int
    public let listTitle: String
    public let listColorHex: String?
    public let isOverdue: Bool

    public init(
        id: String,
        title: String,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        completionDate: Date? = nil,
        priority: Int = 0,
        listTitle: String = "提醒事项",
        listColorHex: String? = nil,
        isOverdue: Bool = false
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.priority = priority
        self.listTitle = listTitle
        self.listColorHex = listColorHex
        self.isOverdue = isOverdue
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

    // MARK: - Reading Apple Calendar & Reminders (CAL-002)

    public var hasCalendarReadAccess: Bool {
        let status = calendarAuthorizationStatus()
        return status == .fullAccess || status == .authorized
    }

    public var hasRemindersReadAccess: Bool {
        let status = remindersAuthorizationStatus()
        return status == .fullAccess || status == .authorized
    }

    /// 读取指定日期的 Apple 日历日程事件（CAL-002）
    public func fetchEvents(on date: Date, calendar: Calendar = .current) -> [CalendarEventItem] {
        guard hasCalendarReadAccess else { return [] }
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = eventStore.events(matching: predicate)
        return events.map { ev in
            let hex = ev.calendar.cgColor.flatMap { Self.cgColorToHex($0) }
            return CalendarEventItem(
                id: ev.eventIdentifier ?? UUID().uuidString,
                title: ev.title ?? "无标题日程",
                startDate: ev.startDate,
                endDate: ev.endDate,
                isAllDay: ev.isAllDay,
                calendarTitle: ev.calendar?.title ?? "日历",
                calendarColorHex: hex,
                location: ev.location,
                notes: ev.notes
            )
        }.sorted(by: { $0.startDate < $1.startDate })
    }

    /// 读取指定日期的 Apple 提醒事项（包含排期到该日、逾期未完成、无日期待办与该日完成项）（CAL-002）
    public func fetchReminders(on date: Date, calendar: Calendar = .current) async -> (scheduled: [ReminderTaskItem], undated: [ReminderTaskItem], completed: [ReminderTaskItem]) {
        guard hasRemindersReadAccess else { return ([], [], []) }
        let predicate = eventStore.predicateForReminders(in: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { list in
                continuation.resume(returning: list ?? [])
            }
        }

        let startOfDay = calendar.startOfDay(for: date)

        var scheduled: [ReminderTaskItem] = []
        var undated: [ReminderTaskItem] = []
        var completed: [ReminderTaskItem] = []

        for r in reminders {
            let hex = r.calendar.cgColor.flatMap { Self.cgColorToHex($0) }
            let dueDate = r.dueDateComponents?.date
            let isOverdue = !r.isCompleted && (dueDate.map { $0 < startOfDay } ?? false)
            let item = ReminderTaskItem(
                id: r.calendarItemIdentifier,
                title: r.title ?? "无标题任务",
                dueDate: dueDate,
                isCompleted: r.isCompleted,
                completionDate: r.completionDate,
                priority: r.priority,
                listTitle: r.calendar?.title ?? "提醒事项",
                listColorHex: hex,
                isOverdue: isOverdue
            )

            if r.isCompleted {
                if let compDate = r.completionDate, calendar.isDate(compDate, inSameDayAs: date) {
                    completed.append(item)
                } else if dueDate != nil && calendar.isDate(dueDate!, inSameDayAs: date) {
                    completed.append(item)
                }
            } else if let due = dueDate {
                if calendar.isDate(due, inSameDayAs: date) || isOverdue {
                    scheduled.append(item)
                }
            } else {
                undated.append(item)
            }
        }

        scheduled.sort { (a, b) in
            if a.isOverdue != b.isOverdue { return a.isOverdue && !b.isOverdue }
            return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
        }
        return (scheduled, undated, completed)
    }

    /// 切换 Apple 提醒事项完成状态（CAL-002）
    public func toggleReminderCompletion(identifier: String) async -> Bool {
        guard hasRemindersReadAccess else { return false }
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            return false
        }
        reminder.isCompleted = !reminder.isCompleted
        reminder.completionDate = reminder.isCompleted ? Date() : nil
        do {
            try eventStore.save(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }

    public static func cgColorToHex(_ cgColor: CGColor) -> String? {
        guard let components = cgColor.components else { return nil }
        if components.count >= 3 {
            let r = max(0, min(255, Int(components[0] * 255.0)))
            let g = max(0, min(255, Int(components[1] * 255.0)))
            let b = max(0, min(255, Int(components[2] * 255.0)))
            return String(format: "#%02X%02X%02X", r, g, b)
        } else if components.count >= 1 {
            let val = max(0, min(255, Int(components[0] * 255.0)))
            return String(format: "#%02X%02X%02X", val, val, val)
        }
        return nil
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
