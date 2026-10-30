import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(MemoFlowCore)
import MemoFlowCore
#endif

/// P01 首页 / 录音列表（黑曜石磨砂玻璃 + 冰蓝内发光视觉语言，PRD 05.P01 & V1.2）
public struct HomeView: View {
    @ObservedObject var store: MemoFlowStore
    @State private var searchText: String = ""
    @State private var selectedDate: Date? = Date()
    @State private var selectedWeekOffset: Int = 0
    @State private var selectedHourFilter: Int? = nil
    @State private var showingRecorderSheet: Bool = false
    @State private var showingUnifiedReview: Bool = false
    @State private var showingSettings: Bool = false
    @State private var showingGroundedQA: Bool = false
    @State private var recordingPendingDeletion: Recording?

    public init(store: MemoFlowStore) {
        self.store = store
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                        // 1. 顶部品牌栏与 API/设置胶囊入口
                        topBrandHeader

                        // 2. Auday 风格首页日期条与横向周切换（非搜索状态下展示）
                        if !isSearching {
                            audayDateHeaderView

                            // 3. 24 小时录音活动热力图（PRD V1.2 UI-003）
                            hourlyActivityHeatmapCard
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
                            Text("\(searchResults.count) 条记忆")
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
                    .padding(.bottom, 110)
                }

                // 底部悬浮暗色玻璃底座 + 冰蓝内发光胶囊按钮
                bottomStartRecordingBar
            }
            .focusEffectDisabled()
            .preferredColorScheme(store.preferences.appearanceTheme.colorScheme)
            .onAppear {
                MFTheme.activeTheme = store.preferences.appearanceTheme
            }
            .onChange(of: store.preferences.appearanceTheme) { _, newTheme in
                MFTheme.activeTheme = newTheme
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

    // MARK: - 1. Top Brand Header

    private var topBrandHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            MemoFlowWaveformBrandIcon(size: 38)
                .shadow(color: Color.black.opacity(0.4), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text("MemoFlow")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(MFTheme.textPrimary)

                HStack(spacing: 5) {
                    Circle()
                        .fill(MFTheme.mintGreen)
                        .frame(width: 6, height: 6)
                    Text(store.preferences.asrEngineMode == .appleOnDevice
                         ? "Apple 端侧语音引擎"
                         : (store.preferences.asrEngineMode == .localWhisper
                            ? "Whisper 本机识别"
                            : store.preferences.asrModelName.components(separatedBy: "/").last ?? store.preferences.asrModelName))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MFTheme.textSecondary)
                }
            }

            Spacer()

            if let vaultPath = store.preferences.obsidianVaultRootPath, !vaultPath.isEmpty {
                Button {
                    _ = store.syncAllBoundObsidianNotes(hydrateNewFromVault: true)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MFTheme.mintGreen)
                        Text("双向同步")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(MFTheme.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(MFTheme.cardSurfaceGradient)
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                showingGroundedQA = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "books.vertical.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MFTheme.softViolet)
                    Text("跨笔记问答")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(MFTheme.textPrimary)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(MFTheme.cardSurfaceGradient)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                        )
                )
            }
            .buttonStyle(.plain)

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MFTheme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(MFTheme.cardSurfaceGradient)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                            )
                    )
            }
            .buttonStyle(.plain)
            .help("服务与设置")
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
            return "全局记忆检索结果"
        }
        if let hour = selectedHourFilter {
            return "\(String(format: "%02d:00", hour)) 时段记忆"
        }
        if let date = selectedDate {
            if Calendar.current.isDateInToday(date) {
                return "今日记忆"
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "MM月dd日 记忆"
            return formatter.string(from: date)
        }
        return "全部记忆"
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

                    Button("今天") {
                        withAnimation {
                            selectedWeekOffset = 0
                            selectedDate = Date()
                            selectedHourFilter = nil
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selectedDate != nil && Calendar.current.isDateInToday(selectedDate!) ? MFTheme.iceCyan : MFTheme.textSecondary)
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

                    Button(selectedDate == nil ? "全部记忆" : "查看全部") {
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

    // MARK: - 3. 24-Hour Recording Activity Heatmap (PRD V1.2 UI-003)

    private var hourlyActivityHeatmapCard: some View {
        let targetDate = selectedDate ?? Date()
        let distribution = store.hourlyActivity(for: targetDate)
        let totalSeconds = distribution.values.reduce(0) { $0 + $1.durationSeconds }
        let totalCount = distribution.values.reduce(0) { $0 + $1.count }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MFTheme.iceCyan)
                    Text("24 小时活动热力分布")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(MFTheme.textPrimary)
                }

                Spacer()

                if let hour = selectedHourFilter {
                    Button("取消时段筛选 (\(String(format: "%02d:00", hour)))") {
                        withAnimation { selectedHourFilter = nil }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MFTheme.warmAmber)
                    .buttonStyle(.plain)
                } else {
                    Text(totalCount > 0 ? "当日 \(totalCount) 段录音 · 共 \(totalSeconds) 秒" : "当日暂无录音活动")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(MFTheme.textSecondary)
                }
            }

            // 24 柱直方条
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { hour in
                    let activity = distribution[hour] ?? (0, 0)
                    let hasActivity = activity.count > 0
                    let isFiltered = (selectedHourFilter == hour)
                    let barHeight = hasActivity ? max(14, min(36, CGFloat(activity.durationSeconds) * 0.8)) : 5

                    Button {
                        withAnimation {
                            if selectedHourFilter == hour {
                                selectedHourFilter = nil
                            } else if hasActivity {
                                selectedHourFilter = hour
                            }
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Capsule()
                                .fill(
                                    hasActivity
                                        ? (isFiltered ? LinearGradient(colors: [MFTheme.warmAmber, MFTheme.iceCyan], startPoint: .top, endPoint: .bottom)
                                                      : LinearGradient(colors: [MFTheme.iceCyan, MFTheme.iceBlue], startPoint: .top, endPoint: .bottom))
                                        : LinearGradient(colors: [MFTheme.paperBorder, MFTheme.recessedBg], startPoint: .top, endPoint: .bottom)
                                )
                                .frame(height: barHeight)
                                .shadow(color: hasActivity ? MFTheme.iceBlue.opacity(0.4) : Color.clear, radius: 4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 38, alignment: .bottom)

            // 时间轴刻度
            HStack {
                Text("00:00")
                Spacer()
                Text("06:00")
                Spacer()
                Text("12:00")
                Spacer()
                Text("18:00")
                Spacer()
                Text("24:00")
            }
            .font(.system(size: 9, weight: .regular, design: .monospaced))
            .foregroundStyle(MFTheme.textMuted)
        }
        .mfGlassCard(cornerRadius: 14, padding: 12)
    }

    private var headerYearMonthString: String {
        let date = selectedDate ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年MM月"
        return formatter.string(from: date)
    }

    private var headerSelectedDateString: String {
        if let date = selectedDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "MM月dd日 EEEE"
            return formatter.string(from: date)
        } else {
            return "全部历史记忆"
        }
    }

    private func weekdayShortString(for date: Date) -> String {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let map = [1: "日", 2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六"]
        return map[weekday] ?? ""
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
                            Text("统一待确认区")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(MFTheme.textPrimary)

                            if totalPending > 0 {
                                MFBadgePill("\(totalPending) 项待处理", color: MFTheme.warmAmber)
                            }
                        }

                        Text("审核 AI 提取的日程与待办 · 点按可回听原话音频证据")
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
                            Text("\(readyCount) 项要素齐全可直接分流")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MFTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.05), in: Capsule())

                        HStack(spacing: 5) {
                            Circle().fill(MFTheme.warmAmber).frame(width: 6, height: 6)
                            Text("\(needsInfoCount) 项需核对时间或归属")
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

            TextField("搜索你的记忆…", text: $searchText)
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
            Text(searchText.isEmpty ? "还没有录音记录" : "未在全部记忆中找到匹配内容")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(MFTheme.textPrimary)
            Text(searchText.isEmpty ? "点击下方按钮开始第一段随手记或会议录音，离线也可安全保存。" : "未检索到包含「\(searchText)」的录音标题、逐字稿原话或 AI 总结，请尝试更换关键词。")
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
        HStack(spacing: 14) {
            dockModeSelector
            luminousStartButton
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(dockContainerBackground)
        .padding(.bottom, 16)
    }

    private var dockModeSelector: some View {
        HStack(spacing: 4) {
            ForEach(NoteMode.allCases, id: \.self) { mode in
                let isSelected = (store.preferences.defaultNoteMode == mode)
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        store.preferences.defaultNoteMode = mode
                        store.saveToDisk()
                    }
                } label: {
                    Text(mode.displayTitle)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? MFTheme.textPrimary : MFTheme.textSecondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(isSelected ? MFTheme.paperBorder.opacity(0.8) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(MFTheme.recessedBg)
                .overlay(
                    Capsule()
                        .strokeBorder(MFTheme.paperBorder, lineWidth: 0.8)
                )
        )
    }

    private var luminousStartButton: some View {
        Button {
            showingRecorderSheet = true
        } label: {
            HStack(spacing: 10) {
                Text("开始录音")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .tracking(0.3)
                    .foregroundStyle(Color.white)

                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(luminousPillInnerBackground)
            .padding(3)
            .background(luminousPillOuterBezel)
            .shadow(color: MFTheme.iceBlue.opacity(0.32), radius: 10, x: 0, y: 3)
        }
        .buttonStyle(.plain)
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

    var body: some View {
        let rec = result.recording
        let note = store.notesByRecording[rec.id]
        let rev = store.currentRevision(for: rec.id)
        let counts = store.pendingCounts(for: rec.id)

        VStack(alignment: .leading, spacing: 11) {
            // 第一行：整理模式胶囊 + 项目标签 + 处理状态胶囊
            HStack(spacing: 8) {
                if let mode = note?.mode {
                    MFBadgePill(
                        mode.displayTitle,
                        color: mode == .quickNote ? MFTheme.iceBlue : MFTheme.softViolet,
                        icon: mode == .quickNote ? "bolt.fill" : "person.2.wave.2.fill"
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
                    MFBadgePill("实时草稿", color: MFTheme.warmAmber, icon: "pencil.and.outline")
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
                        Text("\(counts.tasks) 待办 · \(counts.events) 日程")
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
                    Text("匹配原话：\(snippet)")
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
                        MFLuminousActionButton("配置 API Key", icon: "key.fill", tint: MFTheme.iceBlue) {
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
                                Label("重新整理", systemImage: "sparkles")
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
                                Label("改用 Apple 本地识别重试", systemImage: "waveform.badge.mic")
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
        MFBadgePill(status.displayTitle, color: color)
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
