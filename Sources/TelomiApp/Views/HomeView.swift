import SwiftUI
import EventKit
import Combine
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(TelomiCore)
import TelomiCore
#endif

/// P01 首页 / 录音列表（黑曜石磨砂玻璃 + 冰蓝内发光视觉语言，PRD 05.P01 & V1.2）
public struct HomeView: View {
    @ObservedObject var store: MemoFlowStore
    @ObservedObject private var audioService: AudioRecorderAndPlayerService
    @State private var startingRecording = false
    @State private var searchText: String = ""
    @State private var selectedDate: Date? = Date()
    @State private var selectedWeekOffset: Int = 0
    @State private var selectedHourFilter: Int? = nil
    @State private var showingRecorderSheet: Bool = false
    @State private var showingUnifiedReview: Bool = false
    @State private var showingSettings: Bool = false
    @State private var showingGroundedQA: Bool = false
    @State private var showingAIMemoryChat: Bool = false
    @State private var recordingPendingDeletion: Recording?

    // CAL-002: Apple 日历与提醒事项统一呈现
    enum CalendarFilterTab: String, CaseIterable, Identifiable {
        case all = "全部"
        case events = "日程"
        case tasks = "待办"

        var id: String { rawValue }

        func localizedTitle(isEnglish: Bool) -> String {
            switch self {
            case .all: return isEnglish ? "All" : "全部"
            case .events: return isEnglish ? "Events" : "日程"
            case .tasks: return isEnglish ? "Tasks" : "待办"
            }
        }
    }

    @State private var calendarFilterTab: CalendarFilterTab = .all
    @State private var dayEvents: [CalendarEventItem] = []
    @State private var dayScheduledTasks: [ReminderTaskItem] = []
    @State private var dayUndatedTasks: [ReminderTaskItem] = []
    @State private var dayCompletedTasks: [ReminderTaskItem] = []
    @State private var isShowingCompletedAndUndated: Bool = false
    @State private var hasCalendarAccess: Bool = false
    @State private var hasRemindersAccess: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    public init(store: MemoFlowStore) {
        self.store = store
        self.audioService = store.audioService
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isEnglish: Bool {
        store.preferences.appLanguage.isEnglish
    }

    private var searchResults: [RecordingSearchResult] {
        if isSearching {
            // UX-001: 跨日期的全局记忆搜索，不受选定单日或小时筛选限制
            return store.searchRecordings(query: searchText, on: nil)
        } else {
            let results = store.searchRecordings(query: "", on: selectedDate)
            if let hour = selectedHourFilter {
                return results.filter {
                    Calendar.current.component(.hour, from: $0.recording.createdAt) == hour
                }
            }
            return results
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 全局深邃黑曜石画布 + 顶部氛围柔光
                MFTheme.canvasBg.ignoresSafeArea()
                MFTheme.ambientTopGlow.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        // 1. 顶部品牌栏（BRAND-002: Logo + Telomi 全屏独立居中，两侧功能入口）
                        topBrandHeader

                        // 2. 日期条与横向周切换（非搜索状态下展示）
                        if !isSearching {
                            audayDateHeaderView

                            // 3. Apple 日历与提醒事项统一呈现视图（CAL-002，取代旧热力图 HOME-001）
                            appleCalendarAndRemindersView
                        } else {
                            globalSearchNoticeBanner
                        }

                        // 4. 顶部反馈横幅（若有）
                        if let banner = store.lastBannerFeedback {
                            feedbackBanner(text: banner)
                        }

                        // 5. 统一待确认区 Bento 主卡片（PRD R24 & P01）
                        unifiedReviewEntryCard

                        // 6. 内凹磨砂玻璃搜索栏（PRD V1.2 UI-001: 搜索你的记忆…）
                        glassSearchBar

                        // 7. 录音列表分组标题与卡片流
                        HStack {
                            Text(listSectionTitle)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(MFTheme.textSecondary)
                            Spacer()
                            Text(L10n.memoriesCount(isEnglish, count: searchResults.count))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(MFTheme.textMuted)
                        }
                        .padding(.horizontal, 4)

                        if searchResults.isEmpty {
                            emptyStateView
                        } else {
                            VStack(spacing: 12) {
                                ForEach(searchResults) { item in
                                    NavigationLink {
                                        RecordingDetailView(
                                            store: store,
                                            recordingId: item.recording.id,
                                            initialJumpMs: item.matchedSegmentStartMs
                                        )
                                    } label: {
                                        RecordingRowCard(
                                            store: store,
                                            result: item,
                                            onOpenSettings: {
                                                showingSettings = true
                                            },
                                            onDeleteRequest: {
                                                recordingPendingDeletion = item.recording
                                            }
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                }

                // 底部悬浮暗色玻璃底座 + 冰蓝内发光胶囊按钮
            }
            .safeAreaInset(edge: .bottom) { bottomStartRecordingBar }
            .focusEffectDisabled()
            .preferredColorScheme(store.preferences.appearanceTheme.colorScheme)
            .onAppear {
                MFTheme.activeTheme = store.preferences.appearanceTheme
                Task {
                    await reloadCalendarAndReminders()
                }
            }
            .onChange(of: store.preferences.appearanceTheme) { _, newTheme in
                MFTheme.activeTheme = newTheme
            }
            .onChange(of: selectedDate) { _, _ in
                Task {
                    await reloadCalendarAndReminders()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        await reloadCalendarAndReminders()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                Task {
                    await reloadCalendarAndReminders()
                }
            }
            .sheet(isPresented: $showingRecorderSheet) {
                RecorderSheetView(store: store)
                    #if os(macOS)
                    .frame(minWidth: 440, idealWidth: 460, minHeight: 520, idealHeight: 560)
                    #endif
            }
            .sheet(isPresented: $showingUnifiedReview) {
                NavigationStack {
                    UnifiedReviewView(store: store)
                }
                #if os(macOS)
                .frame(minWidth: 500, idealWidth: 540, minHeight: 660, idealHeight: 720)
                #endif
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(store: store)
                    #if os(macOS)
                    .frame(minWidth: 720, idealWidth: 800, minHeight: 580, idealHeight: 660)
                    #endif
            }
            .sheet(isPresented: $showingGroundedQA) {
                NavigationStack {
                    VaultGroundedQASheetView(store: store)
                }
                #if os(macOS)
                .frame(minWidth: 520, idealWidth: 560, minHeight: 620, idealHeight: 680)
                #endif
            }
            .sheet(isPresented: $showingAIMemoryChat) {
                AIMemoryChatSheetView(store: store)
                #if os(macOS)
                .frame(minWidth: 560, idealWidth: 640, minHeight: 580, idealHeight: 680)
                #endif
            }
            .navigationDestination(item: $store.activeDeepLinkRequest) { req in
                RecordingDetailView(
                    store: store,
                    recordingId: req.recordingId,
                    initialJumpMs: req.targetStartMs,
                    initialEndMs: req.targetEndMs
                )
            }
            .alert(
                "录音定位提示",
                isPresented: Binding(
                    get: { store.activeDeepLinkAlert != nil },
                    set: { if !$0 { store.activeDeepLinkAlert = nil } }
                ),
                presenting: store.activeDeepLinkAlert
            ) { _ in
                Button("知道了", role: .cancel) {
                    store.activeDeepLinkAlert = nil
                }
            } message: { msg in
                Text(msg)
            }
            .sheet(
                isPresented: Binding(
                    get: { store.pendingConsentRecordingId != nil },
                    set: { if !$0 { store.pendingConsentRecordingId = nil } }
                )
            ) {
                CloudConsentSheetView(store: store)
                    #if os(macOS)
                    .frame(minWidth: 440, minHeight: 340)
                    #endif
            }
            .alert(
                "确认删除该录音？",
                isPresented: Binding(
                    get: { recordingPendingDeletion != nil },
                    set: { if !$0 { recordingPendingDeletion = nil } }
                ),
                presenting: recordingPendingDeletion
            ) { rec in
                Button("删除本地录音与笔记", role: .destructive) {
                    store.deleteRecording(rec.id)
                    recordingPendingDeletion = nil
                }
                Button("取消", role: .cancel) {
                    recordingPendingDeletion = nil
                }
            } message: { rec in
                Text("将删除「\(rec.title)」的本地音频、逐字稿与笔记草稿。此前已写入 Apple 日历或提醒事项的记录不会被删除，但将无法再回听原话音频证据。")
            }
        }
    }

    // MARK: - 1. Top Brand Header (BRAND-002: Left: Settings, Center: Logo + Telomi, Right: Sync & QA)

    private var topBrandHeader: some View {
        ZStack {
            // 中间：全屏独立居中 Logo + Telomi 品牌字标（BRAND-002 V1.1）
            HStack(spacing: 8) {
                MemoFlowWaveformBrandIcon(size: 22)
                Text("Telomi")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(MFTheme.textPrimary)
            }

            // 两侧：左侧设置，右侧双向同步与跨笔记问答
            HStack(alignment: .center) {
                // 左边：设置图标
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(MFTheme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(MFTheme.cardSurfaceGradient)
                                .overlay(
                                    Circle().strokeBorder(MFTheme.paperBorder, lineWidth: 0.8)
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.serviceAndSettings(isEnglish))
                .help(L10n.serviceAndSettings(isEnglish))

                Spacer()

                // 右边：双向同步与跨笔记问答
                HStack(spacing: 8) {
                    if let vaultPath = store.preferences.obsidianVaultRootPath, !vaultPath.isEmpty {
                        Button {
                            _ = store.syncAllBoundObsidianNotes(hydrateNewFromVault: true)
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(MFTheme.mintGreen)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(MFTheme.cardSurfaceGradient)
                                        .overlay(
                                            Circle().strokeBorder(MFTheme.paperBorder, lineWidth: 0.8)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.obsidianSyncTooltip(isEnglish))
                        .help(L10n.obsidianSyncTooltip(isEnglish))
                    }

                    Button {
                        showingAIMemoryChat = true
                    } label: {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(MFTheme.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(MFTheme.cardSurfaceGradient)
                                    .overlay(
                                        Circle().strokeBorder(MFTheme.paperBorder, lineWidth: 0.8)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isEnglish ? "AI Memory Assistant" : "AI 记忆助手 · 跨录音整理")
                    .help(isEnglish ? "AI Memory & Project Note Assistant" : "AI 记忆助手 · 跨录音整理")
                }
            }
        }
    }

    private var topBarEngineModelName: String {
        if store.preferences.asrEngineMode == .appleOnDevice {
            return isEnglish ? "Apple Local" : "Apple 本地"
        } else if store.preferences.asrEngineMode == .localWhisper {
            return isEnglish ? "Whisper Local" : "Whisper 本机"
        } else {
            let short = store.preferences.asrModelName.components(separatedBy: "/").last ?? store.preferences.asrModelName
            return short.isEmpty ? "SenseVoice" : short
        }
    }

    private var globalSearchNoticeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(MFTheme.warmAmber)
            VStack(alignment: .leading, spacing: 2) {
                Text("全局记忆搜索中")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(MFTheme.textPrimary)
                Text("检索所有日期的录音、逐字稿、笔记与批注")
                    .font(.system(size: 11))
                    .foregroundStyle(MFTheme.textSecondary)
            }
            Spacer()
            Button("清空检索") {
                searchText = ""
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MFTheme.iceBlue)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08), in: Capsule())
            .buttonStyle(.plain)
        }
        .mfGlassCard(cornerRadius: 14, padding: 14, tint: MFTheme.warmAmber)
    }

    // MARK: - 2. Auday-Style Date Strip (PRD V1.2 UI-002)

    private var listSectionTitle: String {
        if isSearching {
            return isEnglish ? "Search Results" : "全局记忆检索结果"
        }
        if let hour = selectedHourFilter {
            return isEnglish ? String(format: "%02d:00 Activity", hour) : "\(String(format: "%02d:00", hour)) 时段记忆"
        }
        if let date = selectedDate {
            if Calendar.current.isDateInToday(date) {
                return isEnglish ? "Today's Memories" : "今日记忆"
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: isEnglish ? "en_US" : "zh_CN")
            formatter.dateFormat = isEnglish ? "MMM d Memories" : "MM月dd日 记忆"
            return formatter.string(from: date)
        }
        return isEnglish ? "All Memories" : "全部记忆"
    }

    private var currentWeekDays: [Date] {
        let calendar = Calendar.current
        let today = Date()
        let startOfWeek = calendar.date(byAdding: .day, value: selectedWeekOffset * 7, to: today) ?? today
        let weekday = calendar.component(.weekday, from: startOfWeek)
        let daysToMonday = (weekday == 1 ? -6 : 2 - weekday)
        let monday = calendar.date(byAdding: .day, value: daysToMonday, to: startOfWeek) ?? startOfWeek
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private var audayDateHeaderView: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headerYearMonthString)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MFTheme.textMuted)

                    Text(headerSelectedDateString)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(MFTheme.textPrimary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        withAnimation { selectedWeekOffset -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MFTheme.textSecondary)
                            .padding(7)
                            .background(MFTheme.recessedBg, in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button(isEnglish ? "Today" : "今天") {
                        withAnimation {
                            selectedWeekOffset = 0
                            selectedDate = Date()
                            selectedHourFilter = nil
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selectedDate != nil && Calendar.current.isDateInToday(selectedDate!) ? MFTheme.iceCyan : MFTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(MFTheme.recessedBg, in: Capsule())
                    .buttonStyle(.plain)

                    Button {
                        withAnimation { selectedWeekOffset += 1 }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MFTheme.textSecondary)
                            .padding(7)
                            .background(MFTheme.recessedBg, in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button(selectedDate == nil ? (isEnglish ? "All" : "全部记忆") : (isEnglish ? "View All" : "查看全部")) {
                        withAnimation {
                            if selectedDate == nil {
                                selectedDate = Date()
                            } else {
                                selectedDate = nil
                                selectedHourFilter = nil
                            }
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selectedDate == nil ? Color.white : MFTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(selectedDate == nil ? MFTheme.iceBlue : MFTheme.recessedBg, in: Capsule())
                    .buttonStyle(.plain)
                }
            }

            // 横向一周日期胶囊
            HStack(spacing: 6) {
                ForEach(currentWeekDays, id: \.self) { day in
                    let isSelected = selectedDate != nil && Calendar.current.isDate(day, inSameDayAs: selectedDate!)
                    let isToday = Calendar.current.isDateInToday(day)
                    let dayRecordingsCount = store.recordings.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: day) }.count

                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedDate = day
                            selectedHourFilter = nil
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Text(weekdayShortString(for: day))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(isSelected ? (MFTheme.activeTheme == .warmPaper ? Color.white : MFTheme.iceCyan) : MFTheme.textMuted)

                            Text(dayNumberString(for: day))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(isSelected ? Color.white : MFTheme.textPrimary)

                            Circle()
                                .fill(dayRecordingsCount > 0 ? (isSelected ? Color.white : MFTheme.iceCyan) : Color.clear)
                                .frame(width: 4, height: 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSelected ? MFTheme.iceBlue : MFTheme.recessedBg.opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(isSelected ? MFTheme.iceBlue : (isToday ? MFTheme.warmAmber.opacity(0.4) : MFTheme.paperBorder), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 14)
    }

    // MARK: - 3. Apple 日历与提醒事项统一呈现 (CAL-002, 替换旧热力图 HOME-001)

    private var eventTimeFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df
    }

    private func reloadCalendarAndReminders() async {
        let service = EventKitIntegrationService.shared
        hasCalendarAccess = service.hasCalendarReadAccess
        hasRemindersAccess = service.hasRemindersReadAccess

        let target = selectedDate ?? Date()
        if hasCalendarAccess {
            dayEvents = service.fetchEvents(on: target)
        } else {
            dayEvents = []
        }

        if hasRemindersAccess {
            let (scheduled, undated, completed) = await service.fetchReminders(on: target)
            dayScheduledTasks = scheduled
            dayUndatedTasks = undated
            dayCompletedTasks = completed
        } else {
            dayScheduledTasks = []
            dayUndatedTasks = []
            dayCompletedTasks = []
        }
    }

    private var appleCalendarAndRemindersView: some View {
        VStack(alignment: .leading, spacing: 12) {
            calendarHeaderBar

            if !hasCalendarAccess && !hasRemindersAccess {
                calendarAuthBanner
            } else {
                let showEvents = (calendarFilterTab == .all || calendarFilterTab == .events)
                let showTasks = (calendarFilterTab == .all || calendarFilterTab == .tasks)
                let visibleEvents = showEvents ? dayEvents : []
                let visibleTasks = showTasks ? dayScheduledTasks.filter { !$0.isCompleted } : []

                if visibleEvents.isEmpty && visibleTasks.isEmpty {
                    HStack {
                        Spacer()
                        Text(isEnglish ? "No schedule or pending tasks for this day" : "当日暂无日程或待办事项")
                            .font(.system(size: 12))
                            .foregroundStyle(MFTheme.textMuted)
                            .padding(.vertical, 10)
                        Spacer()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        calendarEventsList(events: visibleEvents)
                        calendarTasksList(tasks: visibleTasks)
                    }
                }

                calendarCompletedAndUndatedSection
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 14)
    }

    private var uncompletedTasksCount: Int {
        dayScheduledTasks.filter { !$0.isCompleted }.count
    }

    private var calendarHeaderBar: some View {
        HStack(alignment: .center) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(MFTheme.warmAmber)

                Text(isEnglish ? "Today's Schedule" : "今日安排")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(MFTheme.textPrimary)

                if uncompletedTasksCount > 0 {
                    Text(isEnglish ? "\(uncompletedTasksCount) pending" : "\(uncompletedTasksCount) 项未完成")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MFTheme.warmAmber)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(MFTheme.warmAmber.opacity(0.12), in: Capsule())
                }
            }

            Spacer()

            calendarFilterPicker
        }
    }

    private var calendarFilterPicker: some View {
        HStack(spacing: 3) {
            ForEach(CalendarFilterTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        calendarFilterTab = tab
                    }
                } label: {
                    let isSelected = (calendarFilterTab == tab)
                    Text(tab.localizedTitle(isEnglish: isEnglish))
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? MFTheme.textPrimary : MFTheme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            isSelected ? MFTheme.paperSurface : Color.clear,
                            in: Capsule()
                        )
                        .overlay(
                            isSelected ? Capsule().strokeBorder(MFTheme.paperBorder, lineWidth: 0.8) : nil
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(MFTheme.recessedBg, in: Capsule())
    }

    private var calendarAuthBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isEnglish ? "Connect Apple Calendar & Reminders" : "连接 Apple 系统日历与提醒事项")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MFTheme.textPrimary)
            Text(isEnglish ? "Directly view today's schedule and to-dos in Telomi, synced with system changes." : "在 Telomi 首页直接浏览今日安排与待办，并随时随系统同步更新。")
                .font(.system(size: 11))
                .foregroundStyle(MFTheme.textSecondary)

            Button {
                Task {
                    _ = await EventKitIntegrationService.shared.requestCalendarAccess()
                    _ = await EventKitIntegrationService.shared.requestRemindersAccess()
                    await reloadCalendarAndReminders()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 12, weight: .semibold))
                    Text(isEnglish ? "Authorize Access" : "开启系统访问权限")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(MFTheme.inkPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(MFTheme.paperSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(MFTheme.paperBorder, lineWidth: 0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func calendarEventsList(events: [CalendarEventItem]) -> some View {
        ForEach(events) { ev in
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .trailing, spacing: 1) {
                    if ev.isAllDay {
                        Text(isEnglish ? "All Day" : "全天")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MFTheme.textMuted)
                    } else {
                        Text(eventTimeFormatter.string(from: ev.startDate))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(MFTheme.textPrimary)
                        Text(eventTimeFormatter.string(from: ev.endDate))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(MFTheme.textMuted)
                    }
                }
                .frame(width: 44, alignment: .trailing)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: ev.calendarColorHex) ?? MFTheme.iceCyan)
                    .frame(width: 3, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ev.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MFTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(ev.calendarTitle)
                            .font(.system(size: 10))
                            .foregroundStyle(MFTheme.textMuted)

                        if let loc = ev.location, !loc.isEmpty {
                            Text("· " + loc)
                                .font(.system(size: 10))
                                .foregroundStyle(MFTheme.textMuted)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
            }
            .padding(.vertical, 3)
        }
    }

    @ViewBuilder
    private func calendarTasksList(tasks: [ReminderTaskItem]) -> some View {
        ForEach(tasks) { task in
            HStack(alignment: .center, spacing: 10) {
                Button {
                    Task {
                        _ = await EventKitIntegrationService.shared.toggleReminderCompletion(identifier: task.id)
                        await reloadCalendarAndReminders()
                    }
                } label: {
                    Image(systemName: "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(MFTheme.textSecondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MFTheme.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if task.isOverdue {
                            Text(isEnglish ? "Overdue" : "逾期未完成")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(MFTheme.coralRed)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(MFTheme.coralRed.opacity(0.12), in: Capsule())
                        } else if let due = task.dueDate {
                            Text(eventTimeFormatter.string(from: due))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(MFTheme.textSecondary)
                        }

                        Text(task.listTitle)
                            .font(.system(size: 10))
                            .foregroundStyle(MFTheme.textMuted)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 3)
        }
    }

    @ViewBuilder
    private var calendarCompletedAndUndatedSection: some View {
        let otherCount = dayCompletedTasks.count + dayUndatedTasks.count
        if otherCount > 0 {
            Divider().overlay(MFTheme.paperBorder)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isShowingCompletedAndUndated.toggle()
                }
            } label: {
                HStack {
                    Text(isEnglish ? "Completed & Undated (\(otherCount))" : "已完成 / 无日期待办 (\(otherCount))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MFTheme.textMuted)
                    Spacer()
                    Image(systemName: isShowingCompletedAndUndated ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MFTheme.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isShowingCompletedAndUndated {
                VStack(alignment: .leading, spacing: 6) {
                    if !dayCompletedTasks.isEmpty {
                        Text(isEnglish ? "Completed" : "已完成")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MFTheme.textMuted)

                        ForEach(dayCompletedTasks) { task in
                            HStack(alignment: .center, spacing: 10) {
                                Button {
                                    Task {
                                        _ = await EventKitIntegrationService.shared.toggleReminderCompletion(identifier: task.id)
                                        await reloadCalendarAndReminders()
                                    }
                                } label: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(MFTheme.mintGreen)
                                }
                                .buttonStyle(.plain)

                                Text(task.title)
                                    .font(.system(size: 12))
                                    .strikethrough()
                                    .foregroundStyle(MFTheme.textMuted)
                                Spacer()
                            }
                        }
                    }

                    if !dayUndatedTasks.isEmpty {
                        Text(isEnglish ? "Undated" : "未安排具体日期")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MFTheme.textMuted)
                            .padding(.top, 4)

                        ForEach(dayUndatedTasks) { task in
                            HStack(alignment: .center, spacing: 10) {
                                Button {
                                    Task {
                                        _ = await EventKitIntegrationService.shared.toggleReminderCompletion(identifier: task.id)
                                        await reloadCalendarAndReminders()
                                    }
                                } label: {
                                    Image(systemName: "circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(MFTheme.textSecondary)
                                }
                                .buttonStyle(.plain)

                                Text(task.title)
                                    .font(.system(size: 12))
                                    .foregroundStyle(MFTheme.textPrimary)
                                Spacer()
                                Text(task.listTitle)
                                    .font(.system(size: 9))
                                    .foregroundStyle(MFTheme.textMuted)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var headerYearMonthString: String {
        let date = selectedDate ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isEnglish ? "en_US" : "zh_CN")
        formatter.dateFormat = isEnglish ? "MMMM yyyy" : "yyyy年MM月"
        return formatter.string(from: date)
    }

    private var headerSelectedDateString: String {
        if let date = selectedDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: isEnglish ? "en_US" : "zh_CN")
            formatter.dateFormat = isEnglish ? "EEE, MMM d" : "MM月dd日 EEEE"
            return formatter.string(from: date)
        } else {
            return isEnglish ? "All Memories" : "全部历史记忆"
        }
    }

    private func weekdayShortString(for date: Date) -> String {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        if isEnglish {
            let map = [1: "S", 2: "M", 3: "T", 4: "W", 5: "T", 6: "F", 7: "S"]
            return map[weekday] ?? ""
        } else {
            let map = [1: "日", 2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六"]
            return map[weekday] ?? ""
        }
    }

    private func dayNumberString(for date: Date) -> String {
        let calendar = Calendar.current
        return String(calendar.component(.day, from: date))
    }

    private func feedbackBanner(text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(MFTheme.mintGreen)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MFTheme.textPrimary)
            Spacer()
            Button {
                store.lastBannerFeedback = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MFTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .mfGlassCard(cornerRadius: 12, padding: 12, tint: MFTheme.mintGreen)
    }

    // MARK: - 3. Unified Review Bento Card

    private var unifiedReviewEntryCard: some View {
        let totalPending = store.allPendingActionDrafts.count
        let readyCount = store.readyToReviewDrafts.count
        let needsInfoCount = store.needsInfoDrafts.count

        return Button {
            showingUnifiedReview = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        MFTheme.warmAmber.opacity(0.26),
                                        MFTheme.iceBlue.opacity(0.14)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 42, height: 42)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(MFTheme.warmAmber.opacity(0.35), lineWidth: 0.8)
                            )

                        Image(systemName: totalPending > 0 ? "sparkles.rectangle.stack.fill" : "checkmark.shield.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(totalPending > 0 ? MFTheme.warmAmber : MFTheme.mintGreen)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(isEnglish ? "Unified Review Inbox" : "统一待确认区")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(MFTheme.textPrimary)

                            if totalPending > 0 {
                                MFBadgePill(isEnglish ? "\(totalPending) pending" : "\(totalPending) 项待处理", color: MFTheme.warmAmber)
                            }
                        }

                        Text(isEnglish ? "Review AI extracted tasks & events · Tap to verify audio evidence" : "审核 AI 提取的日程与待办 · 点按可回听原话音频证据")
                            .font(.system(size: 11))
                            .foregroundStyle(MFTheme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MFTheme.textSecondary)
                        .padding(8)
                        .background(Color.white.opacity(0.06), in: Circle())
                }

                if totalPending > 0 {
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Circle().fill(MFTheme.mintGreen).frame(width: 6, height: 6)
                            Text(isEnglish ? "\(readyCount) Ready to create" : "\(readyCount) 项要素齐全可直接分流")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MFTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.05), in: Capsule())

                        HStack(spacing: 5) {
                            Circle().fill(MFTheme.warmAmber).frame(width: 6, height: 6)
                            Text(isEnglish ? "\(needsInfoCount) Need review" : "\(needsInfoCount) 项需核对时间或归属")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MFTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.04), in: Capsule())
                    }
                }
            }
            .mfGlassCard(cornerRadius: 18, padding: 15, tint: totalPending > 0 ? MFTheme.warmAmber : nil)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. Recessed Glass Search Bar

    private var glassSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MFTheme.textMuted)

            TextField(isEnglish ? "Search your memories…" : "搜索你的记忆…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(MFTheme.textPrimary)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MFTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MFTheme.recessedBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(MFTheme.paperBorder, lineWidth: 0.8)
                )
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 36))
                .foregroundStyle(MFTheme.iceBlue.opacity(0.7))
            Text(searchText.isEmpty ? (isEnglish ? "No memories recorded yet" : "还没有录音记录") : (isEnglish ? "No matching memories found" : "未在全部记忆中找到匹配内容"))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(MFTheme.textPrimary)
            Text(searchText.isEmpty ? (isEnglish ? "Tap the microphone below to start a quick note or meeting recording." : "点击下方麦克风开始第一段随手记或会议录音，离线也可安全保存。") : (isEnglish ? "No recording title, transcript, or AI notes match \"\(searchText)\"." : "未检索到包含「\(searchText)」的录音标题、逐字稿原话或 AI 总结，请尝试更换关键词。"))
                .font(.system(size: 12))
                .foregroundStyle(MFTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .mfGlassCard(cornerRadius: 16, padding: 20)
    }

    // MARK: - Floating Dock & Luminous Start Button

    private var bottomStartRecordingBar: some View {
        HStack(spacing: 10) {
            dockModeSelector
            aiMemoryAssistantCapsuleButton
            luminousStartButton
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: 560)
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }

    private var aiMemoryAssistantCapsuleButton: some View {
        Button {
            showingAIMemoryChat = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MFTheme.iceCyan)
                Text(L10n.askMemory(isEnglish))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MFTheme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 56)
            .background(
                Capsule()
                    .fill(MFTheme.cardSurfaceGradient)
                    .overlay(
                        Capsule().strokeBorder(MFTheme.paperBorder, lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .help(L10n.aiMemoryAssistant(isEnglish))
        .shadow(color: .black.opacity(0.09), radius: 10, y: 4)
    }

    private var dockModeSelector: some View {
        Menu {
            ForEach(NoteMode.allCases, id: \.self) { mode in
                let isSelected = (store.preferences.defaultNoteMode == mode)
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        store.preferences.defaultNoteMode = mode
                        store.saveToDisk()
                    }
                } label: {
                    Text(mode.localizedTitle(isEnglish: isEnglish))
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? MFTheme.textPrimary : MFTheme.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(isSelected ? MFTheme.paperBorder.opacity(0.8) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        } label: {
            Text(store.preferences.defaultNoteMode == .quickNote ? (isEnglish ? "Quick" : "随记") : (isEnglish ? "Meeting" : "会议"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MFTheme.textPrimary)
                .frame(width: 56, height: 56)
                .background(MFTheme.cardSurfaceGradient, in: Circle())
                .overlay(Circle().strokeBorder(MFTheme.paperBorder, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(isEnglish ? "Recording mode" : "录音模式")
        .disabled(audioService.isRecording || startingRecording)
        .shadow(color: .black.opacity(0.09), radius: 10, y: 4)
    }

    private var luminousStartButton: some View {
        Button {
            showingRecorderSheet = true
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                MFTheme.textPrimary,
                                MFTheme.textSecondary
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)

                VStack(spacing: 2) {
                    Image(systemName: audioService.isRecording ? (audioService.isPaused ? "pause.fill" : "waveform") : "mic.fill")
                        .font(.system(size: 19, weight: .semibold))
                    if audioService.isRecording {
                        Text(TimeFormatting.formatDuration(audioService.currentRecordingDuration))
                            .font(.system(size: 9, design: .monospaced))
                    }
                }
                .foregroundStyle(Color.white)
            }
            .padding(2)
            .background(
                Circle()
                    .fill(MFTheme.cardBgTop)
                    .overlay(
                        Circle().strokeBorder(MFTheme.paperBorder, lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(audioService.isRecording ? (isEnglish ? "Recording controls" : "录音中，打开暂停与保存控制") : L10n.startRecording(isEnglish))
        .help(audioService.isRecording ? (isEnglish ? "Recording controls" : "录音中 · 点击暂停或保存") : L10n.startRecording(isEnglish))
    }

    private var luminousPillInnerBackground: some View {
        let baseGradient = LinearGradient(
            colors: [
                MFTheme.iceBlue,
                MFTheme.warmAmber
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        return ZStack {
            Capsule().fill(baseGradient)
            Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1.0)
        }
    }

    private var luminousPillOuterBezel: some View {
        Capsule()
            .fill(MFTheme.cardBgTop)
            .overlay(
                Capsule()
                    .strokeBorder(MFTheme.paperBorder, lineWidth: 0.8)
            )
    }

    private var dockContainerBackground: some View {
        Capsule()
            .fill(MFTheme.sheetBg)
            .overlay(Capsule().strokeBorder(MFTheme.paperBorder, lineWidth: 1))
            .shadow(color: Color.black.opacity(MFTheme.activeTheme == .warmPaper ? 0.08 : 0.4), radius: 16, x: 0, y: 6)
    }
}

// MARK: - Recording Row Bento Card

private struct RecordingRowCard: View {
    @ObservedObject var store: MemoFlowStore
    let result: RecordingSearchResult
    let onOpenSettings: () -> Void
    let onDeleteRequest: () -> Void

    private var isEnglish: Bool {
        store.preferences.appLanguage.isEnglish
    }

    var body: some View {
        let rec = result.recording
        let note = store.notesByRecording[rec.id]
        let rev = store.currentRevision(for: rec.id)
        let counts = store.pendingCounts(for: rec.id)

        VStack(alignment: .leading, spacing: 11) {
            // 第一行：整理模式胶囊 + 设备来源 + 项目标签 + 处理状态胶囊
            HStack(spacing: 8) {
                if let mode = note?.mode {
                    MFBadgePill(
                        mode.localizedTitle(isEnglish: isEnglish),
                        color: mode == .quickNote ? MFTheme.iceBlue : MFTheme.softViolet,
                        icon: mode == .quickNote ? "bolt.fill" : "person.2.wave.2.fill"
                    )
                }

                if rec.deviceSource == .appleWatch {
                    MFBadgePill(
                        "Apple Watch",
                        color: MFTheme.softViolet,
                        icon: "applewatch"
                    )
                }

                if let project = note?.projectName, !project.isEmpty {
                    Text("#\(project)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(MFTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.05), in: Capsule())
                }

                Spacer()

                if rev?.isLiveDraft == true {
                    MFBadgePill(isEnglish ? "Live Draft" : "实时草稿", color: MFTheme.warmAmber, icon: "pencil.and.outline")
                }

                statusBadge(for: rec.processingStatus)
            }

            // 第二行：主标题与一句话摘要预览
            VStack(alignment: .leading, spacing: 4) {
                Text(rec.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(MFTheme.textPrimary)
                    .lineLimit(1)

                if let summary = rev?.content.summaryOrShortNote, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(MFTheme.textSecondary)
                        .lineLimit(2)
                }

                // 参会说话人角色标签（PRD V1.2 AI-002 & AI-003）
                let segs = store.segmentsByRecording[rec.id] ?? []
                let uniqueSpeakers = Array(NSOrderedSet(array: segs.compactMap(\.speakerName))).compactMap { $0 as? String }
                if !uniqueSpeakers.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "person.2.wave.2")
                            .font(.system(size: 9))
                        Text(uniqueSpeakers.joined(separator: " · "))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(MFTheme.softViolet.opacity(0.16), in: Capsule())
                    .foregroundStyle(MFTheme.softViolet)
                }
            }

            // P2-7：明确区分「笔记已同步」与「音频已同步 / 待到达」状态胶囊（已绑定笔记或跨端音频缺失时展示）
            let syncInfo = store.syncOverview(for: rec)
            if store.obsidianBindingsByRecording[rec.id] != nil || !syncInfo.audioState.isPlayableNow {
                HStack(spacing: 6) {
                    MFBadgePill(
                        syncInfo.noteBadgeTitle,
                        color: syncInfo.isNoteSynced ? MFTheme.softViolet : MFTheme.textSecondary,
                        icon: "doc.text.fill"
                    )
                    MFBadgePill(
                        syncInfo.audioState.badgeTitle,
                        color: syncInfo.audioState.isPlayableNow
                            ? (syncInfo.audioState.isAudioSyncedAcrossDevices ? MFTheme.mintGreen : MFTheme.iceCyan)
                            : MFTheme.warmAmber,
                        icon: syncInfo.audioState.isPlayableNow ? "waveform" : "icloud.and.arrow.down"
                    )
                    Spacer()
                }
            }

            // 第三行：元数据与待确认角标
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text(rec.createdAt.formatted(date: .abbreviated, time: .shortened))
                }

                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                    Text(TimeFormatting.formatDuration(rec.duration))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }

                if counts.tasks > 0 || counts.events > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(MFTheme.warmAmber).frame(width: 5, height: 5)
                        Text(isEnglish ? "\(counts.tasks) Tasks · \(counts.events) Events" : "\(counts.tasks) 待办 · \(counts.events) 日程")
                            .fontWeight(.semibold)
                            .foregroundStyle(MFTheme.warmAmber)
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    onDeleteRequest()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(MFTheme.textMuted)
                        .padding(6)
                        .background(Color.white.opacity(0.04), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 11))
            .foregroundStyle(MFTheme.textMuted)

            // 搜索命中逐字稿片段展示（PRD R09 & A08）
            if let snippet = result.matchedSegmentSnippet {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(MFTheme.iceBlue)
                        .frame(width: 3, height: 22)
                    Text(isEnglish ? "Matched transcript: \(snippet)" : "匹配原话：\(snippet)")
                        .font(.system(size: 11))
                        .foregroundStyle(MFTheme.iceCyan)
                        .lineLimit(2)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MFTheme.iceBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            // 失败或未配置 API Key 时的柔和修复操作条
            if let err = rec.failureReason, rec.processingStatus == .failed || rec.processingStatus == .savedPendingTranscription {
                VStack(alignment: .leading, spacing: 8) {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(MFTheme.coralRed)

                    HStack(spacing: 8) {
                        MFLuminousActionButton(L10n.configureAPIKey(isEnglish), icon: "key.fill", tint: MFTheme.iceBlue) {
                            onOpenSettings()
                        }

                        let hasSegments = !(store.segmentsByRecording[rec.id]?.isEmpty ?? true)
                        if hasSegments {
                            Button {
                                let mode = note?.mode ?? store.preferences.defaultNoteMode
                                Task {
                                    await store.runProcessingPipeline(for: rec.id, mode: mode, forceRetranscribe: false)
                                }
                            } label: {
                                Label(L10n.regenerate(isEnglish), systemImage: "sparkles")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(MFTheme.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.white.opacity(0.08), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                store.preferences.asrEngineMode = .appleOnDevice
                                store.saveToDisk()
                                let mode = note?.mode ?? store.preferences.defaultNoteMode
                                Task {
                                    await store.runProcessingPipeline(for: rec.id, mode: mode, forceRetranscribe: true)
                                }
                            } label: {
                                Label(L10n.retryWithAppleSpeech(isEnglish), systemImage: "waveform.badge.mic")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(MFTheme.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.white.opacity(0.08), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 15)
    }

    @ViewBuilder
    private func statusBadge(for status: RecordingProcessingStatus) -> some View {
        let color: Color = {
            switch status {
            case .completed: return MFTheme.mintGreen
            case .failed: return MFTheme.coralRed
            case .savedPendingTranscription: return MFTheme.warmAmber
            case .transcriptNeedsReview: return MFTheme.warmAmber
            case .liveStreaming: return MFTheme.warmAmber
            default: return MFTheme.iceBlue
            }
        }()
        MFBadgePill(status.localizedTitle(isEnglish: isEnglish), color: color)
    }
}

// MARK: - P1-5 Cross-Note Grounded Retrieval & Q&A Sheet

public struct VaultGroundedQASheetView: View {
    @ObservedObject var store: MemoFlowStore
    @Environment(\.dismiss) private var dismiss
    @State private var questionInput: String = ""
    @State private var isQuerying: Bool = false
    @State private var qaResult: GroundedQAResult?

    public init(store: MemoFlowStore) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            MFTheme.sheetBg.ignoresSafeArea()
            MFTheme.ambientTopGlow.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("跨笔记与录音有据问答")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(MFTheme.textPrimary)
                        Text("回答严格引用已授权文件夹内的笔记与录音时间戳，不把历史事项当作新承诺")
                            .font(.caption2)
                            .foregroundStyle(MFTheme.textSecondary)
                    }
                    Spacer()
                    Button("关闭") { dismiss() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                }

                HStack(spacing: 8) {
                    TextField("输入项目、术语或历史讨论问题（如：科研栏目首期方向）", text: $questionInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            runQuery()
                        }

                    MFLuminousActionButton(isQuerying ? "检索中…" : "检索并回答", icon: "magnifyingglass") {
                        runQuery()
                    }
                    .disabled(isQuerying)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let res = qaResult {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("检索能力边界说明", systemImage: "info.circle.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(MFTheme.iceCyan)
                                Text(res.capabilityDisclosure)
                                    .font(.caption2)
                                    .foregroundStyle(MFTheme.textSecondary)
                            }
                            .mfGlassCard(cornerRadius: 12, padding: 12, tint: MFTheme.iceBlue)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("检索回答")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(MFTheme.textPrimary)
                                Text(res.answer)
                                    .font(.callout)
                                    .foregroundStyle(MFTheme.textPrimary)
                                    .textSelection(.enabled)
                            }
                            .mfGlassCard(cornerRadius: 12, padding: 14)

                            if !res.citations.isEmpty {
                                Text("可核验来源引用（点击打开笔记或跳转录音时间戳）")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(MFTheme.textSecondary)

                                ForEach(res.citations) { cite in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(cite.noteTitle)
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(MFTheme.textPrimary)
                                            if let rel = cite.noteRelativePath {
                                                Text(rel)
                                                    .font(.caption2.monospaced())
                                                    .foregroundStyle(MFTheme.textSecondary)
                                            }
                                            Spacer()
                                        }

                                        Text(cite.excerpt)
                                            .font(.caption)
                                            .foregroundStyle(MFTheme.textSecondary)
                                            .lineLimit(3)

                                        HStack(spacing: 10) {
                                            if let rel = cite.noteRelativePath,
                                               let obsURL = store.obsidianOpenURL(forRelativePath: rel) {
                                                Button {
                                                    #if os(macOS)
                                                    NSWorkspace.shared.open(obsURL)
                                                    #elseif os(iOS)
                                                    UIApplication.shared.open(obsURL)
                                                    #endif
                                                } label: {
                                                    Label("在 Obsidian 打开笔记", systemImage: "books.vertical.fill")
                                                        .font(.caption2.weight(.semibold))
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 5)
                                                        .background(MFTheme.softViolet.opacity(0.18), in: Capsule())
                                                        .foregroundStyle(MFTheme.softViolet)
                                                }
                                                .buttonStyle(.plain)
                                            }

                                            if let recId = cite.recordingId {
                                                let estPrefix = cite.isEstimated ? "约 " : ""
                                                let timeStr = cite.startMs.map { "\(estPrefix)\(TimeFormatting.formatMilliseconds($0))" } ?? "开头"
                                                Button {
                                                    if let deepURL = MemoFlowDeepLink.recordingURL(
                                                        recordingId: recId,
                                                        startMs: cite.startMs,
                                                        endMs: cite.endMs,
                                                        isEstimated: cite.isEstimated
                                                    ) {
                                                        dismiss()
                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                                            _ = store.handleIncomingURL(deepURL)
                                                        }
                                                    }
                                                } label: {
                                                    Label("定位录音 (\(timeStr))", systemImage: "headphones")
                                                        .font(.caption2.weight(.semibold))
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 5)
                                                        .background(MFTheme.iceBlue.opacity(0.18), in: Capsule())
                                                        .foregroundStyle(MFTheme.iceCyan)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                    .mfGlassCard(cornerRadius: 12, padding: 12)
                                }
                            }
                        } else {
                            Text("输入关键词进行跨笔记与历史录音检索。当前检索范围遵循「设置 -> Obsidian 笔记库联动」中勾选的允许文件夹与排除目录。")
                                .font(.caption)
                                .foregroundStyle(MFTheme.textSecondary)
                                .padding(.top, 12)
                        }
                    }
                }
            }
            .padding(18)
        }
        .preferredColorScheme(store.preferences.appearanceTheme.colorScheme)
    }

    private func runQuery() {
        let q = questionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isQuerying = true
        Task {
            let res = await store.askGroundedQuestion(q)
            qaResult = res
            isQuerying = false
        }
    }
}
