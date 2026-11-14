import SwiftUI
#if canImport(TelomiCore)
import TelomiCore
#endif

/// P05 统一待确认页（跨录音汇总未处理行动、分类审核、原话回听与安全批量执行，PRD 05.P05 & R24 & A22 & A31）
public struct UnifiedReviewView: View {
    @ObservedObject var store: MemoFlowStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFilter: KindFilter = .all
    @State private var showingProcessedHistory: Bool = false
    /// 默认不全选（PRD P05：默认不全选，缺失信息或证据未核实项不得混入一键批量写入）
    @State private var selectedBatchDraftIds: Set<UUID> = []
    @State private var batchExecutionSummary: String?
    @State private var isBatchRunning: Bool = false

    public enum KindFilter: String, CaseIterable {
        case all = "all"
        case tasksOnly = "tasks_only"
        case eventsOnly = "events_only"

        public func localizedTitle(isEnglish: Bool) -> String {
            switch self {
            case .all: return isEnglish ? "All" : "全部"
            case .tasksOnly: return isEnglish ? "Tasks Only" : "仅待办任务"
            case .eventsOnly: return isEnglish ? "Events Only" : "仅日程活动"
            }
        }

        public var iconName: String {
            switch self {
            case .all: return "line.3.horizontal.decrease"
            case .tasksOnly: return "checkmark.circle"
            case .eventsOnly: return "calendar"
            }
        }
    }

    public init(store: MemoFlowStore) {
        self.store = store
    }

    private var isEnglish: Bool {
        store.preferences.appLanguage.isEnglish
    }

    private var filteredReadyDrafts: [ActionDraft] {
        store.readyToReviewDrafts.filter { matchesFilter($0.kind) }
    }

    private var filteredNeedsInfoDrafts: [ActionDraft] {
        store.needsInfoDrafts.filter { matchesFilter($0.kind) }
    }

    private func matchesFilter(_ kind: ActionKind) -> Bool {
        switch selectedFilter {
        case .all: return true
        case .tasksOnly: return kind == .task
        case .eventsOnly: return kind == .event
        }
    }

    public var body: some View {
        ZStack {
            MFTheme.canvasBg.ignoresSafeArea()
            MFTheme.ambientTopGlow.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    topFilterControlBar

                    if let summary = batchExecutionSummary {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(MFTheme.mintGreen)
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(MFTheme.textPrimary)
                            Spacer()
                        }
                        .mfGlassCard(cornerRadius: 12, padding: 12, tint: MFTheme.mintGreen)
                    }

                    readyDraftsSection
                    needsInfoDraftsSection

                    if showingProcessedHistory {
                        processedHistorySection
                    }
                }
                .padding(18)
            }
        }
        .focusEffectDisabled()
        .preferredColorScheme(store.preferences.appearanceTheme.colorScheme)
        .navigationTitle(isEnglish ? "Unified Review" : "统一待确认区")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(isEnglish ? "Done" : "完成") {
                    dismiss()
                }
            }
        }
    }

    private var topFilterControlBar: some View {
        HStack(spacing: 12) {
            Menu {
                Picker(selection: $selectedFilter) {
                    ForEach(KindFilter.allCases, id: \.self) { f in
                        Label(f.localizedTitle(isEnglish: isEnglish), systemImage: f.iconName)
                            .tag(f)
                    }
                } label: {
                    EmptyView()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: selectedFilter.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedFilter == .all ? MFTheme.textSecondary : MFTheme.iceCyan)

                    Text(selectedFilter.localizedTitle(isEnglish: isEnglish))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(MFTheme.textPrimary)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MFTheme.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            Toggle(isEnglish ? "Processed History" : "已处理历史", isOn: $showingProcessedHistory)
                .font(.caption)
                .foregroundStyle(MFTheme.textSecondary)
                .fixedSize()
        }
        .mfGlassCard(cornerRadius: 14, padding: 12)
    }

    private var readyDraftsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Text(isEnglish ? "Ready for Execution" : "可直接确认执行")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(MFTheme.textPrimary)
                    MFBadgePill(isEnglish ? "\(filteredReadyDrafts.count) items" : "\(filteredReadyDrafts.count) 项", color: MFTheme.iceCyan, icon: "checkmark.circle")
                }

                Spacer()

                if !filteredReadyDrafts.isEmpty {
                    MFLuminousActionButton(
                        isBatchRunning ? (isEnglish ? "Executing…" : "批量执行中…") : (isEnglish ? "Batch Execute (\(selectedBatchDraftIds.count))" : "批量执行已勾选 (\(selectedBatchDraftIds.count))"),
                        icon: "bolt.fill",
                        tint: selectedBatchDraftIds.isEmpty ? MFTheme.textMuted : MFTheme.iceBlue
                    ) {
                        guard !selectedBatchDraftIds.isEmpty && !isBatchRunning else { return }
                        Task {
                            isBatchRunning = true
                            let res = await store.batchConfirmAndExecute(draftIds: selectedBatchDraftIds)
                            selectedBatchDraftIds.removeAll()
                            batchExecutionSummary = isEnglish
                                ? "Batch execution complete: \(res.succeeded) succeeded, \(res.skippedOrFailed) skipped or failed."
                                : "批量执行完成：成功 \(res.succeeded) 项，跳过或失败 \(res.skippedOrFailed) 项。"
                            isBatchRunning = false
                        }
                    }
                }
            }

            if filteredReadyDrafts.isEmpty {
                Text(isEnglish ? "No actionable candidates ready for one-tap execution" : "暂无可直接一键执行的候选项")
                    .font(.caption)
                    .foregroundStyle(MFTheme.textMuted)
                    .padding(.vertical, 6)
            } else {
                ForEach(filteredReadyDrafts) { draft in
                    if let rec = store.recordings.first(where: { $0.id == draft.recordingId }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Button {
                                    if selectedBatchDraftIds.contains(draft.id) {
                                        selectedBatchDraftIds.remove(draft.id)
                                    } else {
                                        selectedBatchDraftIds.insert(draft.id)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: selectedBatchDraftIds.contains(draft.id) ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(MFTheme.iceCyan)
                                        Text(isEnglish ? "Include in batch (Target: \(draft.proposedDestination.localizedTitle(isEnglish: isEnglish)))" : "加入批量确认（目标：\(draft.proposedDestination.localizedTitle(isEnglish: false))）")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(MFTheme.textPrimary)
                                    }
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                NavigationLink {
                                    RecordingDetailView(
                                        store: store,
                                        recordingId: rec.id,
                                        initialJumpMs: draft.evidenceStartMs
                                    )
                                } label: {
                                    Text(isEnglish ? "Source: \(rec.title) →" : "源录音：\(rec.title) →")
                                        .font(.caption2)
                                        .foregroundStyle(MFTheme.iceCyan)
                                }
                                .buttonStyle(.plain)
                            }

                            ActionDraftReviewCard(store: store, recording: rec, draft: draft)
                        }
                    }
                }
            }
        }
    }

    private var needsInfoDraftsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Text(isEnglish ? "Needs Info / Ownership Check" : "需补充信息 / 核对归属")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(MFTheme.textPrimary)
                    MFBadgePill(isEnglish ? "\(filteredNeedsInfoDrafts.count) items" : "\(filteredNeedsInfoDrafts.count) 项", color: MFTheme.warmAmber, icon: "exclamationmark.triangle.fill")
                }
                Spacer()
                Text(isEnglish ? "Cannot be batch written" : "不可混入批量一键写入")
                    .font(.caption2)
                    .foregroundStyle(MFTheme.warmAmber)
            }

            if filteredNeedsInfoDrafts.isEmpty {
                Text(isEnglish ? "No ambiguous items requiring additional information" : "没有需要补充信息的模糊事项")
                    .font(.caption)
                    .foregroundStyle(MFTheme.textMuted)
            } else {
                ForEach(filteredNeedsInfoDrafts) { draft in
                    if let rec = store.recordings.first(where: { $0.id == draft.recordingId }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(isEnglish ? "Verify manually or clarify time" : "需单独核实或补充时间", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(MFTheme.warmAmber)
                                Spacer()
                                NavigationLink {
                                    RecordingDetailView(
                                        store: store,
                                        recordingId: rec.id,
                                        initialJumpMs: draft.evidenceStartMs
                                    )
                                } label: {
                                    Text(isEnglish ? "Source: \(rec.title) →" : "源录音：\(rec.title) →")
                                        .font(.caption2)
                                        .foregroundStyle(MFTheme.iceCyan)
                                }
                                .buttonStyle(.plain)
                            }

                            ActionDraftReviewCard(store: store, recording: rec, draft: draft)
                        }
                    }
                }
            }
        }
    }

    private var processedHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(isEnglish ? "Processed Action History" : "已处理行动记录")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(MFTheme.textPrimary)
                MFBadgePill(isEnglish ? "\(store.allConfirmedActions.count) items" : "\(store.allConfirmedActions.count) 项", color: MFTheme.mintGreen)
            }

            ForEach(store.allConfirmedActions) { confirmed in
                if let rec = store.recordings.first(where: { $0.id == confirmed.recordingId }) {
                    ConfirmedActionRowCard(store: store, recording: rec, confirmed: confirmed)
                }
            }
        }
    }
}
