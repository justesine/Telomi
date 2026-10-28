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

/// P03 处理状态页 + P04 笔记详情页（核心页面，PRD 05.P03 & P04）
public struct RecordingDetailView: View {
    @ObservedObject var store: MemoFlowStore
    @ObservedObject private var audioService: AudioRecorderAndPlayerService
    let recordingId: UUID
    let initialJumpMs: Int?

    @State private var selectedTab: DetailTab = .aiNote
    @State private var isEditingNote: Bool = false
    @State private var draftTitle: String = ""
    @State private var draftSummaryOrShortNote: String = ""
    @State private var draftProjectName: String = ""
    @State private var showingMarkdownSheet: Bool = false
    @State private var showingUnifiedReview: Bool = false
    @State private var editingSpeakerId: String? = nil
    @State private var newSpeakerNameInput: String = ""

    public enum DetailTab: String, CaseIterable {
        case aiNote = "AI 笔记与行动"
        case transcript = "逐字稿"
    }

    public init(store: MemoFlowStore, recordingId: UUID, initialJumpMs: Int? = nil) {
        self.store = store
        self.audioService = store.audioService
        self.recordingId = recordingId
        self.initialJumpMs = initialJumpMs
    }

    private var recording: Recording? {
        store.recordings.first(where: { $0.id == recordingId })
    }

    private var note: Note? {
        store.notesByRecording[recordingId]
    }

    private var currentRevision: NoteRevision? {
        store.currentRevision(for: recordingId)
    }

    private var segments: [TranscriptSegment] {
        store.segmentsByRecording[recordingId] ?? []
    }

    private var drafts: [ActionDraft] {
        store.actionDraftsByRecording[recordingId] ?? []
    }

    private var confirmedActions: [ConfirmedAction] {
        store.confirmedActionsByRecording[recordingId] ?? []
    }

    public var body: some View {
        ZStack {
            MFTheme.canvasBg.ignoresSafeArea()
            MFTheme.ambientTopGlow.ignoresSafeArea()

            if let rec = recording {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerMetadataSection(rec: rec)
                        audioPlayerCard(rec: rec)
                        processingStatusCard(rec: rec)
                        detailTabSwitcher

                        if selectedTab == .aiNote {
                            aiNoteAndActionsSection(rec: rec)
                        } else {
                            transcriptSection(rec: rec)
                        }
                    }
                    .padding(18)
                }
                .navigationTitle(rec.title)
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Menu {
                            Button {
                                let mode = note?.mode ?? store.preferences.defaultNoteMode
                                Task {
                                    await store.runProcessingPipeline(for: rec.id, mode: mode, forceRetranscribe: true)
                                }
                            } label: {
                                Label("重新转写逐字稿与AI整理", systemImage: "waveform.badge.magnifyingglass")
                            }

                            Button {
                                showingMarkdownSheet = true
                            } label: {
                                Label("导出 Markdown", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .sheet(isPresented: $showingMarkdownSheet) {
                    if let note = note, let rev = currentRevision {
                        MarkdownExportPreviewSheet(
                            store: store,
                            recording: rec,
                            note: note,
                            revision: rev,
                            confirmedActions: confirmedActions,
                            segments: segments,
                            pendingDrafts: drafts
                        )
                    }
                }
                .sheet(isPresented: $showingUnifiedReview) {
                    NavigationStack {
                        UnifiedReviewView(store: store)
                    }
                }
                .alert("修改说话人名称", isPresented: Binding(
                    get: { editingSpeakerId != nil },
                    set: { if !$0 { editingSpeakerId = nil } }
                )) {
                    TextField("输入真实姓名或自定义昵称", text: $newSpeakerNameInput)
                    Button("确认修改") {
                        if let spkId = editingSpeakerId {
                            store.updateSpeakerName(recordingId: recordingId, speakerId: spkId, newName: newSpeakerNameInput)
                        }
                        editingSpeakerId = nil
                        newSpeakerNameInput = ""
                    }
                    Button("取消", role: .cancel) {
                        editingSpeakerId = nil
                        newSpeakerNameInput = ""
                    }
                } message: {
                    Text("将统一更新该说话人在本录音所有发言片段中的昵称，并同步更新关联的待办负责人。")
                }
                .onAppear {
                    if let jumpMs = initialJumpMs {
                        selectedTab = .transcript
                        audioService.play(recording: rec, startMs: jumpMs)
                    }
                }
            } else {
                Text("该录音记录已不存在")
                    .foregroundStyle(MFTheme.textSecondary)
            }
        }
        .focusEffectDisabled()
        .preferredColorScheme(store.preferences.appearanceTheme.colorScheme)
    }

    private var detailTabSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                let isSel = (selectedTab == tab)
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab == .aiNote ? "sparkles.rectangle.stack.fill" : "text.quote")
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(isSel ? MFTheme.textPrimary : MFTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(isSel ? MFTheme.cardBgTop : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(isSel ? MFTheme.paperBorder : Color.clear, lineWidth: 1)
                            )
                            .shadow(color: isSel ? Color.black.opacity(0.04) : Color.clear, radius: 4, x: 0, y: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MFTheme.recessedBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                )
        )
    }

    // MARK: - 1. Header Metadata & Mode Switcher (PRD R13 & A21)

    @ViewBuilder
    private func headerMetadataSection(rec: Recording) -> some View {
        let currentMode = note?.mode ?? store.preferences.defaultNoteMode

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(
                    rec.createdAt.formatted(date: .numeric, time: .shortened),
                    systemImage: "clock"
                )
                Text("· \(rec.recordedTimeZoneIdentifier)")
                if let rev = currentRevision {
                    MFBadgePill(
                        rev.origin == .userEdited ? "用户已编辑版本" : "AI 初稿",
                        color: rev.origin == .userEdited ? MFTheme.iceCyan : MFTheme.textSecondary
                    )
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(MFTheme.textSecondary)

            HStack(spacing: 8) {
                Text("整理模式")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MFTheme.textSecondary)

                ForEach(NoteMode.allCases, id: \.self) { mode in
                    let isCur = (currentMode == mode)
                    Button {
                        if !isCur {
                            store.switchNoteMode(for: rec.id, to: mode)
                        }
                    } label: {
                        Text(mode.displayTitle)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(isCur ? MFTheme.iceBlue.opacity(0.28) : Color.white.opacity(0.06))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(isCur ? MFTheme.iceBlue.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 0.8)
                                    )
                            )
                            .foregroundStyle(isCur ? MFTheme.iceCyan : MFTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Menu {
                    Button("不关联项目（留空）") {
                        updateProjectAssociation(for: rec, projectName: nil)
                    }
                    Divider()
                    ForEach(store.preferences.knownProjectNames, id: \.self) { proj in
                        Button(proj) {
                            updateProjectAssociation(for: rec, projectName: proj)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                        Text(note?.projectName ?? "关联项目（可选）")
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.07), in: Capsule())
                    .foregroundStyle(MFTheme.textPrimary)
                }
            }

            HStack(spacing: 10) {
                MFLuminousActionButton("预览并导出到 Obsidian (.md)", icon: "doc.badge.arrow.up", tint: MFTheme.softViolet) {
                    showingMarkdownSheet = true
                }

                if let vaultPath = store.preferences.obsidianVaultRootPath, !vaultPath.isEmpty {
                    Button {
                        if let res = try? store.saveNoteDirectlyToObsidian(for: rec.id),
                           let obsURL = res.obsidianOpenURL {
                            #if os(macOS)
                            NSWorkspace.shared.open(obsURL)
                            #elseif os(iOS)
                            UIApplication.shared.open(obsURL)
                            #endif
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "bolt.horizontal.fill")
                            Text("一键直写并在 Obsidian 打开")
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(MFTheme.softViolet.opacity(0.16))
                                .overlay(Capsule().strokeBorder(MFTheme.softViolet.opacity(0.42), lineWidth: 0.8))
                        )
                        .foregroundStyle(MFTheme.softViolet)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 14)
    }

    private func updateProjectAssociation(for rec: Recording, projectName: String?) {
        guard let rev = currentRevision else { return }
        store.saveUserEditedNote(
            for: rec.id,
            newTitle: rec.title,
            newContent: rev.content,
            projectName: projectName
        )
    }

    // MARK: - 2. Sticky Audio Player Card (PRD P04 & R06 & R23)

    @ViewBuilder
    private func audioPlayerCard(rec: Recording) -> some View {
        let isThisPlaying = (audioService.playingRecordingId == rec.id)
        let currentMs = isThisPlaying ? audioService.currentPlaybackTimeMs : 0
        let totalMs = max(Int(rec.duration * 1000), isThisPlaying ? audioService.totalPlaybackDurationMs : Int(rec.duration * 1000))

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Button {
                    audioService.togglePlayPause(for: rec)
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [MFTheme.iceCyan, MFTheme.iceBlue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                            .shadow(color: MFTheme.iceBlue.opacity(0.35), radius: 8, x: 0, y: 2)
                        Image(systemName: (isThisPlaying && audioService.isPlaying) ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(red: 0.05, green: 0.08, blue: 0.14))
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { Double(currentMs) },
                            set: { newMs in
                                audioService.seek(for: rec, toMs: Int(newMs))
                            }
                        ),
                        in: 0...Double(max(1000, totalMs))
                    )
                    .tint(MFTheme.iceCyan)

                    HStack {
                        Text(TimeFormatting.formatMilliseconds(currentMs))
                        Spacer()
                        if isThisPlaying, let evidenceEnd = audioService.activeEvidenceEndMs {
                            Text("🎧 正在回听原话证据区间（至 \(TimeFormatting.formatMilliseconds(evidenceEnd)) 自动暂停）")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(MFTheme.warmAmber)
                        }
                        Spacer()
                        Text(TimeFormatting.formatMilliseconds(totalMs))
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(MFTheme.textSecondary)
                }
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 14, tint: isThisPlaying ? MFTheme.iceBlue : nil)
    }

    // MARK: - 3. P03 Processing Status Card (PRD P03 & R05 & A04)

    @ViewBuilder
    private func processingStatusCard(rec: Recording) -> some View {
        if rec.processingStatus != .completed {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(rec.processingStatus.displayTitle, systemImage: "waveform.badge.exclamationmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MFTheme.warmAmber)
                    Spacer()
                    MFLuminousActionButton("立即重试转写与整理", icon: "arrow.clockwise") {
                        let mode = note?.mode ?? store.preferences.defaultNoteMode
                        Task {
                            await store.runProcessingPipeline(for: rec.id, mode: mode, forceRetranscribe: true)
                        }
                    }
                }

                if let reason = rec.failureReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(MFTheme.textSecondary)
                } else {
                    Text("本地原始音频已安全保存，你可以随时先回听音频或离开本页。")
                        .font(.caption)
                        .foregroundStyle(MFTheme.textSecondary)
                }
            }
            .mfGlassCard(cornerRadius: 14, padding: 14, tint: MFTheme.warmAmber)
        }
    }

    // MARK: - 4. AI Note & Actions Tab (PRD P04 & 06)

    @ViewBuilder
    private func aiNoteAndActionsSection(rec: Recording) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            noteContentCard(rec: rec)

            if !confirmedActions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("已确认行动")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(MFTheme.textPrimary)
                        MFBadgePill("稳定保留 · 重生成不覆盖", color: MFTheme.mintGreen, icon: "lock.fill")
                    }

                    ForEach(confirmedActions) { confirmed in
                        ConfirmedActionRowCard(
                            store: store,
                            recording: rec,
                            confirmed: confirmed
                        )
                    }
                }
            }

            let pendingDrafts = drafts.filter { $0.reviewStatus == .pending || $0.reviewStatus == .needsInfo }
            if !pendingDrafts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(spacing: 8) {
                            Text("待确认行动候选")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(MFTheme.textPrimary)
                            MFBadgePill("\(pendingDrafts.count) 项", color: MFTheme.warmAmber)
                        }
                        Spacer()
                        Button {
                            showingUnifiedReview = true
                        } label: {
                            Text("进入统一待确认台 →")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MFTheme.iceCyan)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(pendingDrafts) { draft in
                        ActionDraftReviewCard(
                            store: store,
                            recording: rec,
                            draft: draft
                        )
                    }
                }
            } else if note?.mode == .meetingNote && confirmedActions.isEmpty {
                Text("本次录音未发现明确的待办或日程承诺。")
                    .font(.caption)
                    .foregroundStyle(MFTheme.textMuted)
                    .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private func noteContentCard(rec: Recording) -> some View {
        if let rev = currentRevision {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 7) {
                        Image(systemName: rev.mode == .quickNote ? "bolt.Horizontal.circle.fill" : "list.bullet.clipboard.fill")
                            .foregroundStyle(MFTheme.iceCyan)
                        Text(rev.mode == .quickNote ? "随手记正文" : "会议记结构化纪要")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(MFTheme.textPrimary)
                    }
                    Spacer()

                    Button(isEditingNote ? "保存修改" : "编辑笔记") {
                        if isEditingNote {
                            var updatedContent = rev.content
                            updatedContent.summaryOrShortNote = draftSummaryOrShortNote
                            store.saveUserEditedNote(
                                for: rec.id,
                                newTitle: draftTitle.isEmpty ? rec.title : draftTitle,
                                newContent: updatedContent,
                                projectName: draftProjectName
                            )
                            isEditingNote = false
                        } else {
                            draftTitle = rec.title
                            draftSummaryOrShortNote = rev.content.summaryOrShortNote
                            draftProjectName = note?.projectName ?? ""
                            isEditingNote = true
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MFTheme.iceCyan)
                    .buttonStyle(.plain)
                }

                if isEditingNote {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("标题", text: $draftTitle)
                            .textFieldStyle(.roundedBorder)
                        TextField("关联项目名（可留空）", text: $draftProjectName)
                            .textFieldStyle(.roundedBorder)
                        TextEditor(text: $draftSummaryOrShortNote)
                            .frame(minHeight: 100)
                            .padding(6)
                            .background(MFTheme.recessedBg, in: RoundedRectangle(cornerRadius: 8))
                    }
                } else {
                    if rev.mode == .quickNote {
                        Text(rev.content.summaryOrShortNote)
                            .font(.body)
                            .foregroundStyle(MFTheme.textPrimary)
                    } else {
                        if !rev.content.summaryOrShortNote.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("核心总结")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(MFTheme.iceCyan)
                                Text(rev.content.summaryOrShortNote)
                                    .font(.body)
                                    .foregroundStyle(MFTheme.textPrimary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(MFTheme.iceBlue.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(MFTheme.iceBlue.opacity(0.22), lineWidth: 0.8)
                                    )
                            )
                        }

                        if !rev.content.backgroundPoints.isEmpty {
                            bulletSection(title: "必要背景", items: rev.content.backgroundPoints)
                        }
                        if !rev.content.keyPoints.isEmpty {
                            bulletSection(title: "关键观点", items: rev.content.keyPoints)
                        }
                        if !rev.content.decisions.isEmpty {
                            bulletSection(title: "已确认结论", items: rev.content.decisions)
                        }
                    }

                    if !rev.content.knowledgeReferences.isEmpty {
                        DisclosureGroup("提供给 AI 的知识库背景（\(rev.content.knowledgeReferences.count) 篇）") {
                            Text("历史背景不代表本次录音的新承诺。以下为发送时的片段快照。")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(rev.content.knowledgeReferences.enumerated()), id: \.offset) { _, reference in
                                Text(reference.path).font(.caption.bold())
                                Text(reference.excerpt).font(.caption).textSelection(.enabled)
                            }
                        }
                    }
                    let chapters = rev.content.chapters.isEmpty
                        ? ASRAndLLMService.shared.buildChaptersFromSegments(segments)
                        : rev.content.chapters
                    if !chapters.isEmpty {
                        Divider().overlay(Color.white.opacity(0.08))
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "bookmark.fill")
                                    .font(.caption2)
                                    .foregroundStyle(MFTheme.iceCyan)
                                Text("录音章节（点击任意章节跳转回听）")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(MFTheme.textSecondary)
                            }

                            ForEach(Array(chapters.enumerated()), id: \.element.id) { idx, chapter in
                                Button {
                                    audioService.play(recording: rec, startMs: chapter.startMs, endMs: chapter.endMs)
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(spacing: 8) {
                                            Text(String(format: "%02d", idx + 1))
                                                .font(.caption2.monospacedDigit().weight(.bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(MFTheme.iceBlue.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                                                .foregroundStyle(MFTheme.iceCyan)

                                            Text(chapter.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(MFTheme.textPrimary)

                                            Spacer()

                                            Label(chapter.formattedTimeRange, systemImage: "play.circle.fill")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(MFTheme.iceCyan)
                                        }

                                        Text(chapter.summary)
                                            .font(.caption)
                                            .foregroundStyle(MFTheme.textSecondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(11)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(MFTheme.recessedBg.opacity(0.75))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.8)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .mfGlassCard(cornerRadius: 16, padding: 16)
        }
    }

    @ViewBuilder
    private func bulletSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MFTheme.textSecondary)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 7) {
                    Text("•")
                        .foregroundStyle(MFTheme.iceCyan)
                    Text(item)
                        .foregroundStyle(MFTheme.textPrimary)
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - 5. Transcript Tab (PRD R06 & A05 & V1.2 AI-002: 多人说话人区分与点击回听)

    @ViewBuilder
    private func transcriptSection(rec: Recording) -> some View {
        let isPlayingThis = (audioService.playingRecordingId == rec.id)
        let playMs = audioService.currentPlaybackTimeMs

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("点击段落时间戳即可跳到对应录音位置回听 · 点击说话人可重命名")
                    .font(.caption)
                    .foregroundStyle(MFTheme.textSecondary)
                Spacer()
                Button {
                    let mode = note?.mode ?? store.preferences.defaultNoteMode
                    Task {
                        await store.runProcessingPipeline(for: rec.id, mode: mode, forceRetranscribe: true)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("重新转写逐字稿")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MFTheme.warmAmber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(MFTheme.warmAmber.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            ForEach(segments) { seg in
                let isCurrentSegment = isPlayingThis && playMs >= seg.startMs && playMs <= seg.endMs
                let speakerDisplayName = seg.speakerName ?? seg.speakerId ?? "发言人"
                let isMe = (speakerDisplayName == "我")

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        // 说话人昵称标签（点击可人工纠偏，AI-002）
                        Button {
                            editingSpeakerId = seg.speakerId ?? speakerDisplayName
                            newSpeakerNameInput = speakerDisplayName
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isMe ? "person.fill" : "person.bubble.fill")
                                    .font(.system(size: 9))
                                Text(speakerDisplayName)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                Image(systemName: "pencil")
                                    .font(.system(size: 8))
                                    .opacity(0.6)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(isMe ? MFTheme.mintGreen.opacity(0.18) : MFTheme.softViolet.opacity(0.2))
                                    .overlay(
                                        Capsule().strokeBorder(isMe ? MFTheme.mintGreen.opacity(0.4) : MFTheme.softViolet.opacity(0.4), lineWidth: 0.8)
                                    )
                            )
                            .foregroundStyle(isMe ? MFTheme.mintGreen : MFTheme.softViolet)
                        }
                        .buttonStyle(.plain)

                        // 时间戳播放按钮
                        Button {
                            audioService.play(recording: rec, startMs: seg.startMs, endMs: nil)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 9))
                                Text(seg.formattedStartTime)
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isCurrentSegment ? MFTheme.iceBlue : MFTheme.iceBlue.opacity(0.12))
                            )
                            .foregroundStyle(isCurrentSegment ? Color.white : MFTheme.iceCyan)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }

                    // 段落正文（点击从头播放该句）
                    Button {
                        audioService.play(recording: rec, startMs: seg.startMs, endMs: nil)
                    } label: {
                        Text(seg.text)
                            .font(.subheadline)
                            .foregroundStyle(MFTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                .mfGlassCard(
                    cornerRadius: 12,
                    padding: 12,
                    tint: isCurrentSegment ? MFTheme.iceCyan : nil
                )
            }
        }
    }
}

// MARK: - Reusable Action Cards (Evidence Quote + Slice Playback + Primary Destination)

public struct ActionDraftReviewCard: View {
    @ObservedObject var store: MemoFlowStore
    let recording: Recording
    let draft: ActionDraft

    @State private var selectedDestination: PrimaryDestination
    @State private var editedDescription: String
    @State private var isExecuting: Bool = false

    public init(store: MemoFlowStore, recording: Recording, draft: ActionDraft) {
        self.store = store
        self.recording = recording
        self.draft = draft
        _selectedDestination = State(initialValue: draft.proposedDestination)
        _editedDescription = State(initialValue: draft.description)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            topBadgesRow
            descriptionInputRow
            dateMetadataRow
            evidenceQuoteBlock
            reasonsSection
            bottomActionRow
        }
        .mfGlassCard(
            cornerRadius: 15,
            padding: 14,
            tint: draft.reviewStatus == .needsInfo ? MFTheme.warmAmber : MFTheme.iceBlue
        )
    }

    private var topBadgesRow: some View {
        HStack(spacing: 6) {
            MFBadgePill(
                draft.kind.displayTitle,
                color: draft.kind == .event ? MFTheme.softViolet : MFTheme.iceCyan,
                icon: draft.kind == .event ? "calendar" : "checkmark.circle"
            )

            MFBadgePill(
                draft.ownership.displayTitle,
                color: draft.ownership == .selfOwner ? MFTheme.mintGreen : MFTheme.warmAmber
            )

            Text(draft.datePrecision.displayTitle)
                .font(.caption2)
                .foregroundStyle(MFTheme.textSecondary)

            if draft.isDefaultDurationApplied, let mins = draft.appliedDefaultDurationMinutes {
                MFBadgePill("默认 \(mins) 分钟", color: MFTheme.warmAmber)
            }

            Spacer()
        }
    }

    private var descriptionInputRow: some View {
        TextField("事项描述", text: $editedDescription)
            .font(.subheadline.weight(.semibold))
            .textFieldStyle(.plain)
            .foregroundStyle(MFTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(MFTheme.recessedBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.8)
                    )
            )
    }

    @ViewBuilder
    private var dateMetadataRow: some View {
        if let rawDate = draft.originalDateText, !rawDate.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(MFTheme.iceCyan)
                Text("原话时间：「\(rawDate)」")
                if let start = draft.startAt {
                    Text("→ \(start.formatted(date: .abbreviated, time: .shortened))")
                        .fontWeight(.medium)
                        .foregroundStyle(MFTheme.textPrimary)
                } else if let due = draft.dueDate {
                    Text("→ \(due.formatted(date: .abbreviated, time: .omitted))（仅日期）")
                        .fontWeight(.medium)
                        .foregroundStyle(MFTheme.textPrimary)
                }
            }
            .font(.caption)
            .foregroundStyle(MFTheme.textSecondary)
        }
    }

    private var evidenceQuoteBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "quote.opening")
                    .font(.caption2)
                    .foregroundStyle(MFTheme.iceCyan)
                Text(draft.evidenceQuote.isEmpty ? "（未提取到原话引用，需人工核实）" : "「\(draft.evidenceQuote)」")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(MFTheme.textPrimary)
            }

            if let startMs = draft.evidenceStartMs, let endMs = draft.evidenceEndMs {
                Button {
                    store.audioService.play(recording: recording, startMs: startMs, endMs: endMs)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "headphones")
                        Text("回听原话证据区间 (\(TimeFormatting.formatMilliseconds(startMs)) - \(TimeFormatting.formatMilliseconds(endMs)))")
                    }
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(MFTheme.iceBlue.opacity(0.18), in: Capsule())
                    .foregroundStyle(MFTheme.iceCyan)
                }
                .buttonStyle(.plain)
            } else if !draft.isEvidenceVerifiedByUser {
                Button {
                    var copy = draft
                    copy.isEvidenceVerifiedByUser = true
                    store.updateDraft(copy)
                } label: {
                    Label("缺少时间定位 · 点击确认已人工核实原话", systemImage: "exclamationmark.shield")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MFTheme.warmAmber)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(MFTheme.recessedBg.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(MFTheme.iceBlue.opacity(0.22), lineWidth: 0.8)
                )
        )
    }

    @ViewBuilder
    private var reasonsSection: some View {
        if !draft.confirmationReasons.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(draft.confirmationReasons, id: \.self) { reason in
                    Label(reason, systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(MFTheme.warmAmber)
                }
            }
        }
    }

    private var bottomActionRow: some View {
        HStack(spacing: 10) {
            Picker("主要去向", selection: $selectedDestination) {
                if draft.kind == .event && draft.datePrecision == .exactTime {
                    Text("Apple 日历").tag(PrimaryDestination.calendar)
                }
                Text("Apple 提醒事项").tag(PrimaryDestination.reminders)
                Text("Markdown 待办").tag(PrimaryDestination.markdown)
                Text("仅本地保留").tag(PrimaryDestination.local)
            }
            .pickerStyle(.menu)
            .font(.caption)

            Spacer()

            Button("忽略") {
                store.ignoreDraft(draft)
            }
            .font(.caption)
            .foregroundStyle(MFTheme.textSecondary)
            .buttonStyle(.plain)

            MFLuminousActionButton(
                isExecuting ? "执行中…" : "确认并分流",
                icon: "checkmark.circle.fill",
                tint: draft.hasValidEvidence ? MFTheme.iceBlue : MFTheme.textMuted
            ) {
                guard draft.hasValidEvidence && !isExecuting else { return }
                Task {
                    isExecuting = true
                    var updated = draft
                    updated.description = editedDescription
                    if updated.ownership == .other {
                        updated.ownership = .selfOwner
                    }
                    _ = await store.confirmAndExecuteDraft(updated, chosenDestination: selectedDestination)
                    isExecuting = false
                }
            }
        }
    }
}

public struct ConfirmedActionRowCard: View {
    @ObservedObject var store: MemoFlowStore
    let recording: Recording
    let confirmed: ConfirmedAction

    public var body: some View {
        let snap = confirmed.confirmedSnapshot
        let link = store.externalLinksByConfirmedAction[confirmed.id]

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                if confirmed.allowsLocalCompletionToggle {
                    Button {
                        store.toggleLocalActionCompletion(recordingId: recording.id, confirmedActionId: confirmed.id)
                    } label: {
                        Image(systemName: (confirmed.localCompletion == true) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle((confirmed.localCompletion == true) ? MFTheme.mintGreen : MFTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "arrow.up.forward.app.fill")
                        .foregroundStyle(MFTheme.iceCyan)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(snap.description)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MFTheme.textPrimary)
                        .strikethrough(confirmed.allowsLocalCompletionToggle && confirmed.localCompletion == true)

                    HStack(spacing: 8) {
                        Text("主要管理位置：\(confirmed.primaryDestination.displayTitle)")
                        Text("· 状态：\(confirmed.executionStatus.displayTitle)")
                        if let container = link?.targetContainerTitle {
                            Text("(\(container))")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(MFTheme.textSecondary)
                }

                Spacer()

                if let startMs = snap.evidenceStartMs, let endMs = snap.evidenceEndMs {
                    Button {
                        store.audioService.play(recording: recording, startMs: startMs, endMs: endMs)
                    } label: {
                        Label(TimeFormatting.formatMilliseconds(startMs), systemImage: "headphones")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(MFTheme.iceBlue.opacity(0.18), in: Capsule())
                            .foregroundStyle(MFTheme.iceCyan)
                    }
                    .buttonStyle(.plain)
                }

                Menu {
                    Button("切换为 MemoFlow 本地管理") {
                        store.switchPrimaryDestination(recordingId: recording.id, confirmedActionId: confirmed.id, newDestination: .local)
                    }
                    Button("切换为 Markdown 待办管理") {
                        store.switchPrimaryDestination(recordingId: recording.id, confirmedActionId: confirmed.id, newDestination: .markdown)
                    }
                    if confirmed.executionStatus == .executionFailed {
                        Button("重试写入 \(confirmed.primaryDestination.displayTitle)") {
                            Task {
                                let retryDraft = ActionDraft(
                                    id: confirmed.sourceDraftId,
                                    recordingId: recording.id,
                                    revisionId: UUID(),
                                    kind: snap.kind,
                                    description: snap.description,
                                    location: snap.location,
                                    owner: snap.owner,
                                    ownership: snap.ownership,
                                    originalDateText: snap.originalDateText,
                                    dueDate: snap.dueDate,
                                    startAt: snap.startAt,
                                    endAt: snap.endAt,
                                    datePrecision: snap.datePrecision,
                                    timeZoneIdentifier: snap.timeZoneIdentifier,
                                    sourceSegmentIds: ["retry"],
                                    evidenceQuote: snap.evidenceQuote,
                                    evidenceStartMs: snap.evidenceStartMs,
                                    evidenceEndMs: snap.evidenceEndMs,
                                    isEvidenceVerifiedByUser: true,
                                    proposedDestination: confirmed.primaryDestination,
                                    confirmedActionId: confirmed.id
                                )
                                _ = await store.confirmAndExecuteDraft(retryDraft, chosenDestination: confirmed.primaryDestination)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(MFTheme.textSecondary)
                }
            }

            if let err = link?.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(MFTheme.coralRed)
            }

            if let diff = confirmed.pendingDiffDraft {
                Text("AI 重新整理建议了新描述：「\(diff.description)」（已保护原确认记录未自动覆盖）")
                    .font(.caption2)
                    .foregroundStyle(MFTheme.warmAmber)
            }
        }
        .mfGlassCard(cornerRadius: 12, padding: 12, tint: MFTheme.mintGreen)
    }
}

// MARK: - Markdown Export & Share Preview Sheet (PRD 07 & R10 & A09 & A29)

public struct MarkdownExportPreviewSheet: View {
    @ObservedObject var store: MemoFlowStore
    let recording: Recording
    let note: Note
    let revision: NoteRevision
    let confirmedActions: [ConfirmedAction]
    let segments: [TranscriptSegment]
    var pendingDrafts: [ActionDraft] = []
    @Environment(\.dismiss) private var dismiss

    @State private var copiedFeedback: Bool = false

    private var markdownText: String {
        MarkdownExporterService.generateMarkdown(
            recording: recording,
            note: note,
            revision: revision,
            confirmedActions: confirmedActions,
            segments: segments,
            pendingDrafts: pendingDrafts
        )
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                MFTheme.sheetBg.ignoresSafeArea()
                MFTheme.ambientTopGlow.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    if store.hasCompletedMarkdownExport(for: recording.id) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(MFTheme.warmAmber)
                            Text("该笔记此前已导出过 Markdown。重新导出不会自动覆盖或删除你在 Obsidian 等外部工具中的旧副本，请注意去重。")
                                .font(.caption)
                                .foregroundStyle(MFTheme.textPrimary)
                        }
                        .mfGlassCard(cornerRadius: 12, padding: 10, tint: MFTheme.warmAmber)
                    }

                    Text("结构化排版：核心总结 → 待办与日程 → 录音章节 → 逐字稿。主要位置为「Apple 提醒事项」的任务仅作为列表引用，不生成重复的 - [ ] 复选框（PRD R25）。")
                        .font(.caption)
                        .foregroundStyle(MFTheme.textSecondary)

                    ScrollView {
                        Text(markdownText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(MFTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .background(MFTheme.recessedBg, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                    )

                    obsidianQuickWriteBox
                    exportActionButtonsRow
                }
                .padding(18)
            }
            .preferredColorScheme(store.preferences.appearanceTheme.colorScheme)
            .navigationTitle("导出结构化 Markdown")
        }
    }

    private var obsidianQuickWriteBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundStyle(MFTheme.softViolet)
                if let vaultPath = store.preferences.obsidianVaultRootPath, !vaultPath.isEmpty {
                    Text("目标 Obsidian 库：\(URL(fileURLWithPath: vaultPath).lastPathComponent) / \(store.preferences.obsidianTargetSubfolder)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MFTheme.textPrimary)
                } else {
                    Text("尚未绑定 Obsidian 笔记库目录（可在设置中绑定或点击右侧直接选文件夹）")
                        .font(.caption)
                        .foregroundStyle(MFTheme.textSecondary)
                }
                Spacer()

                #if os(macOS)
                Button("选择 Obsidian 库目录…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.prompt = "选定此 Obsidian 库"
                    if panel.runModal() == .OK, let url = panel.url {
                        store.bindObsidianVault(url)
                    }
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.bordered)
                #endif
            }

            if let vaultPath = store.preferences.obsidianVaultRootPath, !vaultPath.isEmpty {
                Button {
                    if let res = try? store.saveNoteDirectlyToObsidian(for: recording.id) {
                        if let obsURL = res.obsidianOpenURL {
                            #if os(macOS)
                            NSWorkspace.shared.open(obsURL)
                            #elseif os(iOS)
                            UIApplication.shared.open(obsURL)
                            #endif
                        }
                        dismiss()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.doc.fill")
                        Text("直接写入 Obsidian 并在 Obsidian 中打开")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(MFTheme.softViolet, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .mfGlassCard(cornerRadius: 12, padding: 12, tint: MFTheme.softViolet)
    }

    private var exportActionButtonsRow: some View {
        HStack(spacing: 12) {
            Button {
                store.recordMarkdownExportResult(for: recording.id, result: .cancelled)
                dismiss()
            } label: {
                Text("取消（不记为已导出）")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MFTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            if let fileURL = try? MarkdownExporterService.writeTemporaryMarkdownFile(
                recording: recording,
                markdownContent: markdownText,
                title: MarkdownExporterService.exportTitle(recording: recording, revision: revision)
            ) {
                ShareLink(item: fileURL) {
                    Label("系统分享 .md 文件", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(MFTheme.iceBlue.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(MFTheme.iceCyan)
                }
            }

            Button {
                #if os(iOS)
                UIPasteboard.general.string = markdownText
                #elseif os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(markdownText, forType: .string)
                #endif
                store.recordMarkdownExportResult(for: recording.id, result: .completed)
                copiedFeedback = true
                store.lastBannerFeedback = "已导出 Markdown（注意：分享/复制完成不代表已自动存入指定 Obsidian 库）"
                dismiss()
            } label: {
                Text(copiedFeedback ? "已复制" : "复制并记为已导出")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(MFTheme.iceBlue, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }
}
