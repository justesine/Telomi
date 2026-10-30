import Foundation
import Combine
import AVFoundation

/// 搜索命中结果（PRD R09 & A08：按标题及逐字稿关键词检索历史记录，能看到匹配内容片段）
public struct RecordingSearchResult: Identifiable, Equatable, Sendable {
    public var id: UUID { recording.id }
    public let recording: Recording
    public let matchedSegmentSnippet: String?
    public let matchedSegmentStartMs: Int?
}

@MainActor
public final class MemoFlowStore: ObservableObject {

    // MARK: - 11 Core Collections (PRD 8.3)
    @Published public var recordings: [Recording] = []
    @Published public var segmentsByRecording: [UUID: [TranscriptSegment]] = [:]
    @Published public var notesByRecording: [UUID: Note] = [:]
    @Published public var revisionsByNote: [UUID: [NoteRevision]] = [:]
    @Published public var actionDraftsByRecording: [UUID: [ActionDraft]] = [:]
    @Published public var confirmedActionsByRecording: [UUID: [ConfirmedAction]] = [:]
    @Published public var externalLinksByConfirmedAction: [UUID: ExternalActionLink] = [:]
    @Published public var operationLogs: [ActionOperationLog] = []
    @Published public var markdownExportsByRecording: [UUID: [MarkdownExport]] = [:]
    @Published public var obsidianBindingsByRecording: [UUID: ObsidianNoteBinding] = [:]
    @Published public var personalMemories: [PersonalMemoryItem] = []
    @Published public var processingConsent: ProcessingConsent = ProcessingConsent()
    @Published public var processingJobsByRecording: [UUID: ProcessingJob] = [:]
    @Published public var preferences: MemoFlowPreferences = MemoFlowPreferences()

    // MARK: - UI State
    @Published public var pendingConsentRecordingId: UUID?
    @Published public var pendingConsentMode: NoteMode = .quickNote
    private var pendingConsentRetranscribe = false
    @Published public var lastBannerFeedback: String?
    @Published public var activeDeepLinkRequest: DeepLinkNavigationRequest?
    @Published public var activeDeepLinkAlert: String?
    @Published public var availableVaultTopFolders: [String] = []
    @Published public var knowledgeStatus: String = "选择知识库并开启背景辅助后，将在本机建立索引。"
    @Published public var isRefreshingKnowledge = false
    private let knowledgeService = ObsidianKnowledgeService()
    public let obsidianSyncService = ObsidianNoteSyncService()
    private var activePipelineRecordingIds = Set<UUID>()

    // MARK: - 边录边整理（实时流式转写与增量草稿）状态
    @Published public private(set) var liveStreamingProgress: LiveStreamingProgress?
    @Published public private(set) var liveDraftNote: Note?
    @Published public private(set) var liveDraftRevision: NoteRevision?
    public var liveChunkQueue: [LiveAudioChunkJournalItem] = []
    public var liveChunkAudioURLs: [UUID: URL] = [:]
    private var isDrainingLiveChunkQueue: Bool = false
    private var lastLiveSummaryUpdateMs: Int = 0

    public var obsidianBackupsDirectoryURL: URL {
        persistenceURL.deletingLastPathComponent().appendingPathComponent("MemoFlowVaultBackups", isDirectory: true)
    }

    public func bindObsidianVault(_ url: URL) {
        do {
            let bookmark = try VaultAccess.bookmark(for: url)
            preferences.obsidianVaultBookmark = bookmark
            preferences.obsidianVaultRootPath = url.path
            availableVaultTopFolders = (try? ObsidianKnowledgeService.listTopLevelFolders(preferences: preferences)) ?? []
            saveToDisk()
            knowledgeStatus = "知识库已连接。开启背景辅助后刷新。"
            Task { await refreshKnowledge() }
        } catch { knowledgeStatus = "连接失败：\(error.localizedDescription)" }
    }

    public func disconnectObsidianVault() {
        preferences.knowledgeContextEnabled = false
        preferences.allowSendingKnowledgeToCloudLLM = false
        preferences.obsidianVaultBookmark = nil
        preferences.obsidianVaultRootPath = nil
        preferences.autoExportToObsidianOnComplete = false
        availableVaultTopFolders = []
        saveToDisk()
        knowledgeStatus = "已断开连接并撤销知识库读取与云端发送授权；历史笔记中的参考记录仍保留。"
        Task { await knowledgeService.clear() }
    }

    public func refreshKnowledge() async {
        if preferences.obsidianVaultBookmark != nil {
            availableVaultTopFolders = (try? ObsidianKnowledgeService.listTopLevelFolders(preferences: preferences)) ?? []
        }
        guard !isRefreshingKnowledge else { return }
        _ = await knowledgeContext(query: "")
    }

    private func knowledgeContext(query: String) async -> [KnowledgeReference] {
        let captured = preferences
        guard captured.knowledgeContextEnabled else {
            await knowledgeService.clear()
            knowledgeStatus = "知识库背景辅助已关闭。"
            return []
        }
        isRefreshingKnowledge = true
        defer { isRefreshingKnowledge = false }
        do {
            let result = try await knowledgeService.refresh(preferences: captured, query: query)
            guard captured == preferences else { return [] }
            knowledgeStatus = "本机已索引 \(result.count) 篇笔记。" + (result.skipped > 0 ? "\(result.skipped) 项待下载、不可读或超过容量限制，请下载后刷新。" : "")
            return result.references
        } catch {
            guard captured == preferences else { return [] }
            knowledgeStatus = "知识库暂不可用：\(error.localizedDescription)"
            lastBannerFeedback = "本次仅根据录音整理。\(knowledgeStatus)"
            return []
        }
    }

    public let audioService: AudioRecorderAndPlayerService
    private let persistenceURL: URL

    public init(
        audioService: AudioRecorderAndPlayerService? = nil,
        customStorageURL: URL? = nil
    ) {
        let isolatedDirectory = customStorageURL.map {
            $0.deletingPathExtension().appendingPathExtension("recordings")
        }
        let resolvedAudio = audioService ?? AudioRecorderAndPlayerService(recordingsDirectory: isolatedDirectory)
        self.audioService = resolvedAudio

        let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.persistenceURL = customStorageURL ?? baseDir.appendingPathComponent("MemoFlowState_v1_1.json")

        if FileManager.default.fileExists(atPath: persistenceURL.path) {
            _ = loadFromDisk()
        } else {
            seedPRDDefaultScenarios()
            saveToDisk()
        }
        if customStorageURL == nil {
            KeychainService.shared.migrateLegacyKey(for: .asrAPIKey, endpoint: preferences.asrBaseURL)
            KeychainService.shared.migrateLegacyKey(for: .llmAPIKey, endpoint: preferences.llmBaseURL)
        }
        if let (journal, duration) = resolvedAudio.recoverInterruptedRecording() {
            // 检查是否存在边录边整理未完成切片日记，恢复已转写进度（PRD 边录边整理 异常退出恢复）
            let liveChunks = resolvedAudio.loadLiveChunksJournal(for: journal.id)
            if !liveChunks.isEmpty {
                var recoveredSegments: [TranscriptSegment] = []
                for chunk in liveChunks where chunk.status == .transcribed {
                    if let text = chunk.transcriptText, !text.isEmpty {
                        recoveredSegments.append(TranscriptSegment(
                            id: chunk.id.uuidString,
                            recordingId: journal.id,
                            startMs: chunk.startMs,
                            endMs: chunk.endMs,
                            text: text
                        ))
                    }
                }
                if !recoveredSegments.isEmpty {
                    self.segmentsByRecording[journal.id] = recoveredSegments
                }
            }

            if !recordings.contains(where: { $0.id == journal.id }) {
                var recovered = Recording(id: journal.id, title: "已恢复的中断录音", createdAt: journal.createdAt,
                    duration: duration, localAudioFileName: journal.fileName,
                    audioInterruptionNote: "上次录音未正常结束，已恢复可读取的音频。请回听核查。")
                recovered.marks = journal.marks
                recordings.insert(recovered, at: 0)
            }
            if saveToDisk() { resolvedAudio.acknowledgeSavedRecording(id: journal.id) }
            lastBannerFeedback = "已恢复上次中断的录音，等待你回听与处理。"
        }

        self.audioService.onLiveChunkAvailable = { [weak self] item, url in
            Task { @MainActor [weak self] in
                self?.enqueueLiveChunk(item, url: url)
            }
        }
    }

    // MARK: - Cross-Recording Unified Review Queue Queries (PRD R24 & P05)

    /// 所有跨录音未处理的行动草稿
    public var allPendingActionDrafts: [ActionDraft] {
        recordings.flatMap { rec in
            (actionDraftsByRecording[rec.id] ?? []).filter { draft in
                draft.reviewStatus == .pending || draft.reviewStatus == .needsInfo
            }
        }
    }

    /// 可直接审核执行的候选项（信息明确、证据有效、非他人负责）
    public var readyToReviewDrafts: [ActionDraft] {
        allPendingActionDrafts.filter { draft in
            draft.hasValidEvidence && !draft.needsConfirmation && draft.ownership == .selfOwner
        }
    }

    /// 需补充信息或人工核实的候选项（时间模糊、负责人未明确、他人负责、缺来源证据）
    public var needsInfoDrafts: [ActionDraft] {
        allPendingActionDrafts.filter { draft in
            !draft.hasValidEvidence || draft.needsConfirmation || draft.ownership != .selfOwner
        }
    }

    /// 所有已确认的行动（跨录音）
    public var allConfirmedActions: [ConfirmedAction] {
        recordings.flatMap { confirmedActionsByRecording[$0.id] ?? [] }
    }

    public func pendingCounts(for recordingId: UUID) -> (tasks: Int, events: Int) {
        let pending = (actionDraftsByRecording[recordingId] ?? []).filter {
            $0.reviewStatus == .pending || $0.reviewStatus == .needsInfo
        }
        let tasks = pending.filter { $0.kind == .task }.count
        let events = pending.filter { $0.kind == .event }.count
        return (tasks, events)
    }

    // MARK: - Search & Date Filtering (PRD V1.2 UI-001, UI-002, UI-003)

    public func searchRecordings(query: String, on date: Date? = nil) -> [RecordingSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseList: [Recording]
        if trimmed.isEmpty, let targetDate = date {
            baseList = recordings.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: targetDate) }
        } else {
            baseList = recordings
        }

        guard !trimmed.isEmpty else {
            return baseList.map { RecordingSearchResult(recording: $0, matchedSegmentSnippet: nil, matchedSegmentStartMs: nil) }
        }

        return baseList.compactMap { rec -> RecordingSearchResult? in
            let titleMatch = rec.title.localizedCaseInsensitiveContains(trimmed)
            let segs = segmentsByRecording[rec.id] ?? []
            let matchedSeg = segs.first { seg in
                seg.text.localizedCaseInsensitiveContains(trimmed) ||
                (seg.speakerName?.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
            let note = notesByRecording[rec.id]
            let rev = currentRevision(for: rec.id)
            let content = rev?.content
            var fields: [String] = [note?.projectName ?? ""]
            fields += (rec.marks ?? []).map { "\($0.quote) \($0.note)" }
            if let content {
                fields += [content.suggestedTitle, content.summaryOrShortNote]
                fields += content.backgroundPoints + content.keyPoints + content.decisions
                fields += content.chapters.map { "\($0.title) \($0.summary)" }
            }
            let noteText = fields.joined(separator: "\n")
            let summaryMatch = noteText.localizedCaseInsensitiveContains(trimmed)

            if titleMatch || matchedSeg != nil || summaryMatch {
                let snippet = matchedSeg.map {
                    let spk = $0.speakerName.map { "\($0): " } ?? ""
                    return "[\($0.formattedStartTime)] \(spk)\($0.text)"
                } ?? (summaryMatch ? "笔记：\(noteText.components(separatedBy: "\n").first(where: { $0.localizedCaseInsensitiveContains(trimmed) }) ?? "")" : nil)
                return RecordingSearchResult(
                    recording: rec,
                    matchedSegmentSnippet: snippet,
                    matchedSegmentStartMs: matchedSeg?.startMs
                )
            }
            return nil
        }
    }

    /// 统计指定日期 00:00 - 24:00 各小时区间的录音活动（秒数与次数，用于 24 小时热力图）
    public func hourlyActivity(for date: Date) -> [Int: (durationSeconds: Int, count: Int)] {
        var result: [Int: (durationSeconds: Int, count: Int)] = [:]
        for hour in 0..<24 {
            result[hour] = (0, 0)
        }

        let calendar = Calendar.current
        let dayRecordings = recordings.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }

        for rec in dayRecordings {
            let hour = calendar.component(.hour, from: rec.createdAt)
            let current = result[hour] ?? (0, 0)
            result[hour] = (current.durationSeconds + Int(rec.duration), current.count + 1)
        }

        return result
    }

    // MARK: - Speaker Management & Voice Profile (PRD V1.2 AI-001 & AI-002)

    /// 用户手动纠正某条录音中的说话人归属/自定义昵称
    public func updateSpeakerName(recordingId: UUID, speakerId: String, newName: String) {
        guard var segs = segmentsByRecording[recordingId] else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        for i in 0..<segs.count {
            if segs[i].speakerId == speakerId || "segment:\(segs[i].id)" == speakerId {
                segs[i].speakerName = trimmed
                if segs[i].speakerId == nil { segs[i].speakerId = speakerId }
            }
        }
        segmentsByRecording[recordingId] = segs

        // 同步更新 ActionDraft 中对应的归属人
        if var drafts = actionDraftsByRecording[recordingId] {
            for i in 0..<drafts.count {
                if drafts[i].owner == speakerId || drafts[i].owner == segs.first?.speakerName {
                    drafts[i].owner = trimmed
                    if trimmed == "我" {
                        drafts[i].ownership = .selfOwner
                    }
                }
            }
            actionDraftsByRecording[recordingId] = drafts
        }

        saveToDisk()
    }

    /// 录入或更新用户个人声纹档案（AI-001）
    public func enrollVoiceProfile(sampleDuration: TimeInterval, description: String = "已录入个人声纹特征档案") {
        preferences.userVoiceProfile = UserVoiceProfile(
            enrolledAt: Date(),
            sampleDuration: sampleDuration,
            featureDescription: description
        )
        saveToDisk()
        lastBannerFeedback = "档案信息已保存；当前版本尚未接入自动语音身份识别，请人工确认说话人。"
    }

    /// 删除个人声纹档案（AI-001）
    public func deleteVoiceProfile() {
        preferences.userVoiceProfile = nil
        saveToDisk()
        lastBannerFeedback = "已删除个人声纹档案。"
    }

    // MARK: - Recording & "Save First, Process Later" Pipeline (PRD R26, R12, A27, A28)

    public func handleFinishedRecording(
        id: UUID,
        fileName: String,
        createdAt: Date,
        duration: TimeInterval,
        selectedMode: NoteMode,
        isNetworkAvailable: Bool = true,
        marks: [RecordingMark] = []
    ) {
        guard !recordings.contains(where: { $0.id == id }) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        let defaultTitle = "\(selectedMode.displayTitle) \(formatter.string(from: createdAt))"

        var newRecording = Recording(
            id: id,
            title: defaultTitle,
            createdAt: createdAt,
            recordedTimeZoneIdentifier: TimeZone.current.identifier,
            duration: duration,
            localAudioFileName: fileName,
            language: "zh-CN",
            processingStatus: .savedPendingTranscription
        )

        newRecording.marks = marks
        recordings.insert(newRecording, at: 0)
        preferences.defaultNoteMode = selectedMode
        lastBannerFeedback = "已安全保存本地音频（\(TimeFormatting.formatDuration(duration))）"
        guard saveToDisk() else { return }
        audioService.acknowledgeSavedRecording(id: id)

        guard isNetworkAvailable else {
            // PRD 4.2 & A01：无网时保留待转写状态，不丢音频
            updateRecordingStatus(id, status: .savedPendingTranscription, failureReason: "当前无网络连接，音频已安全保存，待联网后转写")
            return
        }

        if preferences.liveStreamingTranscriptionEnabled {
            // 边录边整理模式：录音停止后复用已完成分段，只处理剩余片段并做最终合并（PRD 边录边整理）
            Task {
                await finalizeLiveStreamingRecording(for: id, selectedMode: selectedMode)
            }
        } else if !preferences.asrEngineMode.sendsAudioToCloud && (KeychainService.shared.readKey(for: .llmAPIKey, endpoint: preferences.llmBaseURL) ?? "").isEmpty {
            // 纯本地模式无需上传云端
            Task {
                await runProcessingPipeline(for: id, mode: selectedMode)
            }
        } else if processingConsent.canAutoProcessWithoutPrompt {
            Task {
                await runProcessingPipeline(for: id, mode: selectedMode)
            }
        } else {
            // 需要弹出云处理授权确认
            pendingConsentRecordingId = id
            pendingConsentMode = selectedMode
        }
    }

    // MARK: - 边录边整理（分段转写队列、增量草稿生成与最终合并）

    public func enqueueLiveChunk(_ item: LiveAudioChunkJournalItem, url: URL) {
        liveChunkAudioURLs[item.id] = url
        if let idx = liveChunkQueue.firstIndex(where: { $0.id == item.id || $0.index == item.index }) {
            liveChunkQueue[idx] = item
        } else {
            liveChunkQueue.append(item)
        }
        audioService.appendLiveChunkToJournal(item, for: item.recordingId)

        let pendingCount = liveChunkQueue.filter { $0.status == .pending || $0.status == .transcribing }.count
        let processedCount = liveChunkQueue.filter { $0.status == .transcribed }.count
        let failedCount = liveChunkQueue.filter { $0.status == .failed }.count
        let transcribedMs = liveChunkQueue.filter { $0.status == .transcribed }.map(\.endMs).max() ?? 0

        self.liveStreamingProgress = LiveStreamingProgress(
            recordingId: item.recordingId,
            totalAudioDurationMs: Int(audioService.currentRecordingDuration * 1000),
            transcribedDurationMs: transcribedMs,
            pendingChunksCount: pendingCount,
            processedChunksCount: processedCount,
            failedChunksCount: failedCount,
            isLiveDraft: true,
            lastSummaryUpdateMs: lastLiveSummaryUpdateMs,
            statusMessage: failedCount > 0 ? "⚠️ \(failedCount) 个分段处理受阻，已保留待重试" : "实时分段转写中"
        )

        Task { @MainActor [weak self] in
            await self?.drainLiveChunkQueue()
        }
    }

    public func drainLiveChunkQueue() async {
        guard !isDrainingLiveChunkQueue else { return }
        isDrainingLiveChunkQueue = true
        defer { isDrainingLiveChunkQueue = false }

        while let nextIndex = liveChunkQueue.firstIndex(where: { $0.status == .pending || ($0.status == .failed && $0.retryCount < 3) }) {
            var chunk = liveChunkQueue[nextIndex]
            chunk.status = .transcribing
            liveChunkQueue[nextIndex] = chunk
            audioService.appendLiveChunkToJournal(chunk, for: chunk.recordingId)

            let candidateURL = liveChunkAudioURLs[chunk.id] ?? {
                let candidate = audioService.recordingsDirectoryURL.appendingPathComponent("live_chunks_\(chunk.recordingId.uuidString)/\(chunk.fileName)")
                return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
            }()

            guard let url = candidateURL else {
                chunk.status = .failed
                chunk.errorDescription = "切片音频文件丢失"
                liveChunkQueue[nextIndex] = chunk
                audioService.appendLiveChunkToJournal(chunk, for: chunk.recordingId)
                continue
            }

            let asrKey = KeychainService.shared.readKey(for: .asrAPIKey, endpoint: preferences.asrBaseURL)
            do {
                let segments = try await ASRAndLLMService.shared.transcribeSingleChunk(
                    fileURL: url,
                    chunk: chunk,
                    preferences: preferences,
                    apiKey: asrKey
                )
                chunk.status = .transcribed
                chunk.transcriptText = segments.map(\.text).joined(separator: " ")
                chunk.completedAt = Date()
                liveChunkQueue[nextIndex] = chunk
                audioService.appendLiveChunkToJournal(chunk, for: chunk.recordingId)

                var existingSegments = segmentsByRecording[chunk.recordingId] ?? []
                existingSegments.append(contentsOf: segments)
                existingSegments.sort { $0.startMs < $1.startMs }
                segmentsByRecording[chunk.recordingId] = existingSegments

                let transcribedMs = liveChunkQueue.filter { $0.status == .transcribed }.map(\.endMs).max() ?? 0
                let pendingCount = liveChunkQueue.filter { $0.status == .pending || $0.status == .transcribing }.count
                let processedCount = liveChunkQueue.filter { $0.status == .transcribed }.count
                let failedCount = liveChunkQueue.filter { $0.status == .failed }.count

                self.liveStreamingProgress = LiveStreamingProgress(
                    recordingId: chunk.recordingId,
                    totalAudioDurationMs: Int(audioService.currentRecordingDuration * 1000),
                    transcribedDurationMs: transcribedMs,
                    pendingChunksCount: pendingCount,
                    processedChunksCount: processedCount,
                    failedChunksCount: failedCount,
                    isLiveDraft: true,
                    lastSummaryUpdateMs: lastLiveSummaryUpdateMs,
                    statusMessage: "实时分段转写完成 · 第 \(chunk.index + 1) 段"
                )

                // 按分钟或内容量增量生成草稿（控制费用与电量，PRD 边录边整理要求 3）
                let intervalMs = preferences.liveStreamingSummaryIntervalSeconds * 1000
                if (chunk.endMs - lastLiveSummaryUpdateMs) >= intervalMs || lastLiveSummaryUpdateMs == 0 {
                    await updateLiveDraftNote(for: chunk.recordingId, newSegments: segments)
                    lastLiveSummaryUpdateMs = chunk.endMs
                }
            } catch {
                chunk.status = .failed
                chunk.retryCount += 1
                chunk.errorDescription = error.localizedDescription
                liveChunkQueue[nextIndex] = chunk
                audioService.appendLiveChunkToJournal(chunk, for: chunk.recordingId)
            }
        }
    }

    private func updateLiveDraftNote(for recordingId: UUID, newSegments: [TranscriptSegment]) async {
        guard let recIdx = recordings.firstIndex(where: { $0.id == recordingId }) else { return }
        let recording = recordings[recIdx]
        let currentNote = notesByRecording[recordingId]
        let currentRevision = currentNote.flatMap { revisionsByNote[$0.id]?.last }
        let llmKey = KeychainService.shared.readKey(for: .llmAPIKey, endpoint: preferences.llmBaseURL)

        do {
            let updatedContent = try await ASRAndLLMService.shared.incrementallyUpdateLiveDraft(
                existingContent: currentRevision?.content,
                newSegments: newSegments,
                recording: recording,
                preferences: preferences,
                llmAPIKey: llmKey
            )

            let noteId = currentNote?.id ?? UUID()
            let revId = UUID()
            let newRevision = NoteRevision(
                id: revId,
                noteId: noteId,
                mode: currentNote?.mode ?? preferences.defaultNoteMode,
                generatedAt: Date(),
                content: updatedContent,
                origin: .ai,
                previousRevisionId: currentRevision?.id,
                sourceTranscriptDigest: NoteVersionProvenance.transcriptDigest(for: segmentsByRecording[recordingId] ?? []),
                basedOnTranscriptReviewed: false,
                isLiveDraft: true
            )

            let note = Note(
                id: noteId,
                recordingId: recordingId,
                mode: currentNote?.mode ?? preferences.defaultNoteMode,
                editedAt: Date(),
                currentRevisionId: revId
            )

            self.notesByRecording[recordingId] = note
            var revs = self.revisionsByNote[noteId] ?? []
            revs.append(newRevision)
            self.revisionsByNote[noteId] = revs
            self.liveDraftNote = note
            self.liveDraftRevision = newRevision
        } catch {
            // Incremental fallback handled in ASRAndLLMService
        }
    }

    public func finalizeLiveStreamingRecording(for recordingId: UUID, selectedMode: NoteMode = .meetingNote) async {
        guard let recIdx = recordings.firstIndex(where: { $0.id == recordingId }) else { return }
        updateRecordingStatus(recordingId, status: .organizing, failureReason: nil)

        // 1. 排空剩余切片队列
        await drainLiveChunkQueue()

        let pendingOrFailed = liveChunkQueue.filter { $0.status != .transcribed }
        let hasUnfinishedChunks = !pendingOrFailed.isEmpty

        // 确保所有已完成切片均完整归入逐字稿分段（PRD 边录边整理 需求 1 & 2 & 7）
        var allSegments = segmentsByRecording[recordingId] ?? []
        let existingIds = Set(allSegments.map(\.id))
        for chunk in liveChunkQueue where chunk.status == .transcribed {
            if let text = chunk.transcriptText, !text.isEmpty, !existingIds.contains(chunk.id.uuidString) {
                allSegments.append(TranscriptSegment(
                    id: chunk.id.uuidString,
                    recordingId: recordingId,
                    startMs: chunk.startMs,
                    endMs: chunk.endMs,
                    text: text
                ))
            }
        }
        allSegments.sort { $0.startMs < $1.startMs }
        segmentsByRecording[recordingId] = allSegments

        // 2. 最终整合并去重
        let llmKey = KeychainService.shared.readKey(for: .llmAPIKey, endpoint: preferences.llmBaseURL)

        do {
            var output = try await ASRAndLLMService.shared.organizeTranscript(
                recording: recordings[recIdx],
                segments: allSegments,
                requestedMode: selectedMode,
                revisionId: UUID(),
                preferences: preferences,
                llmAPIKey: llmKey
            )

            // 3. 若存在未完成片段，严格依据要求 7 明确提示，绝不能把部分结果标记为完整
            if hasUnfinishedChunks {
                let warningPrefix = "⚠️ 注意：本次录音尚有 \(pendingOrFailed.count) 个切片片段未能完成转写，当前内容为阶段草稿，未标记为完整笔记。"
                if output.noteContent.summaryOrShortNote.isEmpty || output.noteContent.summaryOrShortNote == "（暂无识别文字）" {
                    output.noteContent.summaryOrShortNote = warningPrefix
                } else {
                    output.noteContent.summaryOrShortNote = warningPrefix + "\n" + output.noteContent.summaryOrShortNote
                }
                output.noteContent.backgroundPoints.insert(
                    "⚠️ 注意：本次录音尚有 \(pendingOrFailed.count) 个切片片段未能完成转写，当前笔记为基于已转写内容的阶段草稿，原音频完整保留可随时回听。",
                    at: 0
                )
            }

            let noteId = notesByRecording[recordingId]?.id ?? UUID()
            let finalRevId = UUID()
            let finalRevision = NoteRevision(
                id: finalRevId,
                noteId: noteId,
                mode: selectedMode,
                generatedAt: Date(),
                content: output.noteContent,
                origin: .ai,
                previousRevisionId: revisionsByNote[noteId]?.last?.id,
                sourceTranscriptDigest: NoteVersionProvenance.transcriptDigest(for: allSegments),
                basedOnTranscriptReviewed: false,
                isLiveDraft: hasUnfinishedChunks
            )

            let note = Note(
                id: noteId,
                recordingId: recordingId,
                mode: selectedMode,
                editedAt: Date(),
                currentRevisionId: finalRevId
            )

            self.notesByRecording[recordingId] = note
            var revs = self.revisionsByNote[noteId] ?? []
            revs.append(finalRevision)
            self.revisionsByNote[noteId] = revs
            self.actionDraftsByRecording[recordingId] = output.actionDrafts

            if hasUnfinishedChunks {
                updateRecordingStatus(
                    recordingId,
                    status: .transcriptNeedsReview,
                    failureReason: "尚有 \(pendingOrFailed.count) 个音频切片转写未完成，已生成阶段笔记草稿"
                )
            } else {
                updateRecordingStatus(recordingId, status: .completed, failureReason: nil)
                recordings[recIdx].transcriptSource = TranscriptSource(
                    fileName: recordings[recIdx].localAudioFileName,
                    sha256: (try? AudioSourceValidation.fingerprint(audioService.audioFileURL(for: recordings[recIdx].localAudioFileName))) ?? "",
                    audioDuration: recordings[recIdx].duration,
                    engine: preferences.asrModelName + " · live",
                    completedAt: Date()
                )
            }

            if !hasUnfinishedChunks {
                audioService.acknowledgeLiveChunks(for: recordingId)
            }
            self.liveStreamingProgress = nil
            self.liveChunkQueue.removeAll()
            self.liveChunkAudioURLs.removeAll()
            saveToDisk()

            if preferences.autoExportToObsidianOnComplete, !hasUnfinishedChunks {
                _ = try? saveNoteDirectlyToObsidian(for: recordingId)
            }
        } catch {
            updateRecordingStatus(recordingId, status: .failed, failureReason: error.localizedDescription)
        }
    }

    public func grantCloudProcessingConsent(rememberPreference: Bool) {
        processingConsent.grantedAt = Date()
        processingConsent.revokedAt = nil
        processingConsent.mode = rememberPreference ? .remembered : .askEveryTime
        saveToDisk()

        if let pendingId = pendingConsentRecordingId {
            let mode = pendingConsentMode
            let retranscribe = pendingConsentRetranscribe
            pendingConsentRecordingId = nil
            Task {
                await runProcessingPipeline(for: pendingId, mode: mode, forceRetranscribe: retranscribe, cloudConsentGranted: true)
            }
        }
    }

    public func revokeCloudProcessingConsent() {
        processingConsent.revokedAt = Date()
        processingConsent.mode = .askEveryTime
        saveToDisk()
    }

    /// 边录边整理录音前检查是否需要弹窗获取云端处理授权（PRD 边录边整理 需求 6）
    public func requiresCloudConsentForLiveRecording() -> Bool {
        let isLive = preferences.liveStreamingTranscriptionEnabled
        let needsCloud = preferences.asrEngineMode.sendsAudioToCloud ||
            !(KeychainService.shared.readKey(for: .llmAPIKey, endpoint: preferences.llmBaseURL) ?? "").isEmpty
        return isLive && needsCloud && !processingConsent.canAutoProcessWithoutPrompt
    }

    public func runProcessingPipeline(
        for recordingId: UUID,
        mode: NoteMode,
        forceRetranscribe: Bool = false,
        cloudConsentGranted: Bool = false
    ) async {
        guard let idx = recordings.firstIndex(where: { $0.id == recordingId }) else { return }
        var recording = recordings[idx]
        let needsCloud = preferences.asrEngineMode.sendsAudioToCloud ||
            !(KeychainService.shared.readKey(for: .llmAPIKey, endpoint: preferences.llmBaseURL) ?? "").isEmpty
        if needsCloud && !cloudConsentGranted && !processingConsent.canAutoProcessWithoutPrompt {
            pendingConsentRecordingId = recordingId
            pendingConsentMode = mode
            pendingConsentRetranscribe = forceRetranscribe
            return
        }

        // 避免快速多次点击触发重复竞争任务
        if activePipelineRecordingIds.contains(recordingId) {
            return
        }
        activePipelineRecordingIds.insert(recordingId)
        let pipelinePreferences = preferences
        let consentAtStart = processingConsent
        defer {
            activePipelineRecordingIds.remove(recordingId)
        }

        let previousAttempts = processingJobsByRecording[recordingId]?.attempts ?? 0
        processingJobsByRecording[recordingId] = ProcessingJob(
            recordingId: recordingId,
            stage: .uploading,
            status: "running",
            attempts: previousAttempts + 1
        )

        updateRecordingStatus(recordingId, status: .uploading, failureReason: nil)

        do {
            // 阶段 ③：转写（若已有逐字稿且未指定强制重新转写，则跳过重传音频）
            var segments = forceRetranscribe ? [] : (segmentsByRecording[recordingId] ?? [])
            if !segments.isEmpty {
                guard let source = recording.transcriptSource,
                      source.fileName == recording.localAudioFileName,
                      try AudioSourceValidation.fingerprint(audioService.audioFileURL(for: source.fileName)) == source.sha256 else {
                    throw ProcessingPipelineError.audioProcessingFailed("现有逐字稿缺少可核验的音频来源，或原文件已变化。请使用「重新转写逐字稿」")
                }
            }
            if segments.isEmpty {
                updateRecordingStatus(recordingId, status: .transcribing, failureReason: nil)
                let fileURL = audioService.audioFileURL(for: recording.localAudioFileName)
                try AudioSourceValidation.validateMapping(fileURL: fileURL, recording: recording)
                guard recordings.filter({ $0.localAudioFileName == recording.localAudioFileName }).count == 1 else {
                    throw ProcessingPipelineError.audioProcessingFailed("多条记录共用同一音频文件，请先核查映射")
                }
                let fingerprint = try AudioSourceValidation.fingerprint(fileURL)
                let duration = try await AVURLAsset(url: fileURL).load(.duration).seconds
                guard duration.isFinite, duration > 0 else { throw ProcessingPipelineError.audioProcessingFailed("原音频时长无效") }
                recording.duration = duration
                let asrKey = KeychainService.shared.readKey(for: .asrAPIKey, endpoint: preferences.asrBaseURL)
                var rawSegments = try await ASRAndLLMService.shared.transcribeAudio(
                    fileURL: fileURL,
                    recording: recording,
                    preferences: pipelinePreferences,
                    apiKey: asrKey
                )
                // 赋予说话人分离标签与电影角色昵称主题（PRD V1.2 AI-001, AI-002, AI-003）
                rawSegments = ASRAndLLMService.shared.applySpeakerDiarizationAndNicknames(
                    segments: rawSegments,
                    theme: preferences.speakerNicknameTheme,
                    userVoiceProfile: preferences.userVoiceProfile
                )
                try Task.checkCancellation()
                guard pipelinePreferences == preferences,
                      let currentIndex = recordings.firstIndex(where: { $0.id == recordingId }),
                      recordings[currentIndex].localAudioFileName == recording.localAudioFileName,
                      try AudioSourceValidation.fingerprint(fileURL) == fingerprint else {
                    throw ProcessingPipelineError.audioProcessingFailed("原音频或记录在处理期间发生变化，未替换原稿")
                }
                try AudioSourceValidation.validateSegments(rawSegments, recording: recording)
                if let previous = segmentsByRecording[recordingId], !previous.isEmpty {
                    let directory = persistenceURL.deletingLastPathComponent().appendingPathComponent("MemoFlowTranscriptHistory")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let archive = directory.appendingPathComponent("\(recordingId)-\(UUID().uuidString).json")
                    try JSONEncoder().encode(previous).write(to: archive, options: .atomic)
                }
                segments = rawSegments
                segmentsByRecording[recordingId] = segments
                recordings[currentIndex].duration = duration
                let engine: String
                switch pipelinePreferences.asrEngineMode {
                case .appleOnDevice: engine = "Apple Speech · on-device"
                case .localWhisper: engine = "Whisper large-v3-turbo · local · needs review"
                case .openAICompatible: engine = pipelinePreferences.asrModelName
                }
                recordings[currentIndex].transcriptSource = TranscriptSource(fileName: recording.localAudioFileName,
                    sha256: fingerprint, audioDuration: duration, engine: engine, completedAt: Date())
                recordings[currentIndex].isTranscriptReviewed = false
                saveToDisk()
                if pipelinePreferences.asrEngineMode == .localWhisper {
                    let message = "本机 Whisper 已生成机器逐字稿，需回听校对；现有 AI 笔记仍基于旧稿。"
                    updateRecordingStatus(recordingId, status: .transcriptNeedsReview, failureReason: message)
                    processingJobsByRecording[recordingId] = ProcessingJob(recordingId: recordingId,
                        stage: .transcriptNeedsReview, status: "needs_review", attempts: previousAttempts + 1)
                    saveToDisk()
                    return
                }
            }

            // 阶段 ④：AI 整理与有证据的行动提取
            guard pipelinePreferences == preferences, consentAtStart == processingConsent,
                  recordings.contains(where: { $0.id == recordingId }) else {
                throw ProcessingPipelineError.audioProcessingFailed("设置、授权或记录已变化，处理已停止。请重新开始")
            }
            updateRecordingStatus(recordingId, status: .organizing, failureReason: nil)
            let revisionId = UUID()
            let llmKey = KeychainService.shared.readKey(for: .llmAPIKey, endpoint: preferences.llmBaseURL)
            let isUsingCloudLLM = !(llmKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let knowledgePreferences = preferences
            let localReferences = preferences.knowledgeContextEnabled
                ? await knowledgeContext(query: segments.map(\.text).joined(separator: "\n"))
                : []
            let canUseKnowledgeForCurrentOrganizer: Bool = {
                guard knowledgePreferences == preferences, preferences.knowledgeContextEnabled else { return false }
                if isUsingCloudLLM {
                    // P1-5：严格分离「本机读取知识库」与「发送片段/个人记忆至云端 LLM」的独立授权
                    return preferences.allowSendingKnowledgeToCloudLLM
                }
                return true
            }()
            let permittedReferences = canUseKnowledgeForCurrentOrganizer ? localReferences : []
            let permittedMemories: [PersonalMemoryItem] = {
                let confirmed = personalMemories.filter { $0.status == .confirmed }
                if isUsingCloudLLM {
                    return preferences.allowSendingKnowledgeToCloudLLM ? confirmed : []
                }
                return confirmed
            }()
            guard pipelinePreferences == preferences, consentAtStart == processingConsent else {
                throw ProcessingPipelineError.audioProcessingFailed("服务配置或授权已变化，未发送逐字稿")
            }
            let output = try await ASRAndLLMService.shared.organizeTranscript(
                recording: recording,
                segments: segments,
                requestedMode: mode,
                revisionId: revisionId,
                preferences: pipelinePreferences,
                llmAPIKey: llmKey,
                knowledgeReferences: permittedReferences,
                confirmedMemories: permittedMemories
            )

            guard pipelinePreferences == preferences, consentAtStart == processingConsent,
                  recordings.contains(where: { $0.id == recordingId }) else {
                throw ProcessingPipelineError.audioProcessingFailed("设置、授权或记录已变化，未应用 AI 结果")
            }

            applyOrganizationOutput(
                output,
                for: recordingId,
                requestedMode: mode,
                revisionId: revisionId
            )

            updateRecordingStatus(recordingId, status: .completed, failureReason: nil)
            let counts = pendingCounts(for: recordingId)

            // PRD V1.2 CAL-003 模式 B：智能自动创建日程模式
            var autoCreatedEventsCount = 0
            if preferences.calendarCreationMode == .autoCreate {
                let autoEligible = (actionDraftsByRecording[recordingId] ?? []).filter { draft in
                    draft.kind == .event &&
                    draft.datePrecision == .exactTime &&
                    draft.ownership == .selfOwner &&
                    draft.startAt != nil &&
                    draft.hasValidEvidence &&
                    !draft.needsConfirmation
                }
                for draft in autoEligible {
                    let confirmed = await confirmAndExecuteDraft(draft, chosenDestination: .calendar)
                    if confirmed.executionStatus == .handedToExternal || confirmed.executionStatus == .keptLocal {
                        autoCreatedEventsCount += 1
                    }
                }
            }

            if autoCreatedEventsCount > 0 {
                lastBannerFeedback = "已整理并自动创建 \(autoCreatedEventsCount) 个 Apple 日历日程（智能自动创建模式）"
            } else if counts.tasks > 0 || counts.events > 0 {
                lastBannerFeedback = "已整理：\(counts.tasks) 条待办、\(counts.events) 个日程待确认"
            } else {
                lastBannerFeedback = "已整理完成（无待确认行动项）"
            }

            // 如果用户在设置中开启了「整理完成后自动写入 Obsidian 库」且已授权目录（PRD R15）
            if preferences.autoExportToObsidianOnComplete,
               let vaultPath = preferences.obsidianVaultRootPath,
               !vaultPath.isEmpty {
                do {
                    _ = try saveNoteDirectlyToObsidian(for: recordingId)
                } catch {
                    lastBannerFeedback = "自动写入 Obsidian 失败：\(error.localizedDescription)"
                }
            }

            saveToDisk()
        } catch {
            // PRD 9.1 & A04：转写/整理失败绝不删除音频
            updateRecordingStatus(recordingId, status: .failed, failureReason: error.localizedDescription)
            processingJobsByRecording[recordingId]?.stage = .failed
            processingJobsByRecording[recordingId]?.status = "failed"
            processingJobsByRecording[recordingId]?.errorCode = error.localizedDescription
            saveToDisk()
        }
    }

    // MARK: - Note Mode Switching, User Editing & Version Isolation (PRD R08, R13, A07, A21, A25)

    /// 将 AI 整理结果应用到 NoteRevision 与 ActionDraft，严格保护用户已确认行动不被覆盖（PRD R08 & A21 & A25）
    public func applyOrganizationOutput(
        _ output: ASRAndLLMService.OrganizationOutput,
        for recordingId: UUID,
        requestedMode: NoteMode,
        revisionId: UUID
    ) {
        let existingNote = notesByRecording[recordingId]
        let noteId = existingNote?.id ?? UUID()
        let prevRevId = existingNote?.currentRevisionId
        let currentSegments = segmentsByRecording[recordingId] ?? []
        let currentRec = recordings.first(where: { $0.id == recordingId })

        let newRevision = NoteRevision(
            id: revisionId,
            noteId: noteId,
            mode: requestedMode,
            generatedAt: Date(),
            content: output.noteContent,
            origin: .ai,
            previousRevisionId: prevRevId,
            sourceTranscriptDigest: NoteVersionProvenance.transcriptDigest(for: currentSegments),
            basedOnTranscriptReviewed: currentRec?.isTranscriptReviewed == true
        )

        var revisions = revisionsByNote[noteId] ?? []
        revisions.append(newRevision)
        revisionsByNote[noteId] = revisions

        let updatedNote = Note(
            id: noteId,
            recordingId: recordingId,
            mode: requestedMode,
            suggestedMode: output.suggestedMode,
            projectName: existingNote?.projectName ?? output.suggestedProjectName,
            projectReference: existingNote?.projectReference,
            userSupplement: existingNote?.userSupplement ?? "",
            manualTags: existingNote?.manualTags ?? [],
            editedAt: Date(),
            currentRevisionId: revisionId
        )
        notesByRecording[recordingId] = updatedNote

        // 如果录音标题还是默认占位标题，且未被用户手改过，则采纳简短标题
        if let recIdx = recordings.firstIndex(where: { $0.id == recordingId }),
           !output.noteContent.suggestedTitle.isEmpty,
           existingNote == nil {
            recordings[recIdx].title = output.noteContent.suggestedTitle
        }

        // PRD R08, R19, A16, A25：已确认行动保持稳定 ID、去向与回执不变；新草稿若有差异仅标记待核对，不覆盖已确认项
        var confirmedList = confirmedActionsByRecording[recordingId] ?? []
        var newDrafts: [ActionDraft] = []

        for var draft in output.actionDrafts {
            if let matchedConfirmedIdx = confirmedList.firstIndex(where: { confirmed in
                confirmed.sourceDraftId == draft.id ||
                confirmed.confirmedSnapshot.evidenceQuote == draft.evidenceQuote ||
                confirmed.confirmedSnapshot.description == draft.description
            }) {
                let existingConfirmed = confirmedList[matchedConfirmedIdx]
                draft.confirmedActionId = existingConfirmed.id
                if existingConfirmed.confirmedSnapshot.description != draft.description ||
                    existingConfirmed.confirmedSnapshot.originalDateText != draft.originalDateText {
                    draft.reviewStatus = .hasDiffWithConfirmed
                    confirmedList[matchedConfirmedIdx].pendingDiffDraft = draft
                } else {
                    draft.reviewStatus = .confirmed
                }
            }
            newDrafts.append(draft)
        }

        confirmedActionsByRecording[recordingId] = confirmedList
        actionDraftsByRecording[recordingId] = newDrafts
    }

    /// 用户手动切换整理模式（随手记 <-> 会议记，PRD R13 & A21：切换只产生新草稿，不覆盖原文、用户编辑稿和已确认行动）
    public func switchNoteMode(for recordingId: UUID, to newMode: NoteMode) {
        guard let rec = recordings.first(where: { $0.id == recordingId }) else { return }
        let segments = segmentsByRecording[recordingId] ?? []
        let revisionId = UUID()
        let output = ASRAndLLMService.shared.organizeLocallyWithHeuristics(
            recording: rec,
            segments: segments,
            requestedMode: newMode,
            revisionId: revisionId,
            preferences: preferences
        )
        applyOrganizationOutput(output, for: recordingId, requestedMode: newMode, revisionId: revisionId)
        saveToDisk()
    }

    /// 用户手动保存标题与笔记修改（PRD R08 & A07：生成 userEdited 版本，重开仍存在）
    public func saveUserEditedNote(
        for recordingId: UUID,
        newTitle: String,
        newContent: StructuredNoteContent,
        projectName: String?,
        userSupplement: String? = nil,
        manualTags: [String]? = nil
    ) {
        if let idx = recordings.firstIndex(where: { $0.id == recordingId }) {
            recordings[idx].title = newTitle
        }
        guard var note = notesByRecording[recordingId] else { return }
        var updatedStructured = newContent
        if !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updatedStructured.suggestedTitle = newTitle
        }
        let prevRev = currentRevision(for: recordingId)
        let currentSegments = segmentsByRecording[recordingId] ?? []
        let currentRec = recordings.first(where: { $0.id == recordingId })
        let newRev = NoteRevision(
            noteId: note.id,
            mode: note.mode,
            generatedAt: Date(),
            content: updatedStructured,
            origin: .userEdited,
            previousRevisionId: note.currentRevisionId,
            sourceTranscriptDigest: prevRev?.sourceTranscriptDigest ?? NoteVersionProvenance.transcriptDigest(for: currentSegments),
            basedOnTranscriptReviewed: currentRec?.isTranscriptReviewed == true
        )
        var revs = revisionsByNote[note.id] ?? []
        revs.append(newRev)
        revisionsByNote[note.id] = revs

        note.currentRevisionId = newRev.id
        note.editedAt = Date()
        let trimmedProject = MarkdownExporterService.unwrapProjectWikiLink(projectName)
        note.projectName = trimmedProject
        if let validProj = note.projectName, !preferences.knownProjectNames.contains(validProj) {
            preferences.knownProjectNames.append(validProj)
        }
        if let supplement = userSupplement {
            note.userSupplement = supplement
        }
        if let tags = manualTags {
            note.manualTags = tags
        }
        notesByRecording[recordingId] = note
        saveToDisk()
    }

    public func currentRevision(for recordingId: UUID) -> NoteRevision? {
        guard let note = notesByRecording[recordingId],
              let revs = revisionsByNote[note.id] else { return nil }
        return revs.first(where: { $0.id == note.currentRevisionId }) ?? revs.last
    }

    // MARK: - Action Review, Confirmation & External Execution (PRD 4.5, 4.7, R17-R25)

    public func updateDraft(_ updatedDraft: ActionDraft) {
        guard var list = actionDraftsByRecording[updatedDraft.recordingId],
              let idx = list.firstIndex(where: { $0.id == updatedDraft.id }) else { return }
        list[idx] = updatedDraft
        actionDraftsByRecording[updatedDraft.recordingId] = list
        saveToDisk()
    }

    public func ignoreDraft(_ draft: ActionDraft) {
        var copy = draft
        copy.reviewStatus = .ignored
        updateDraft(copy)
    }

    /// 确认单条行动候选并按主要去向执行（PRD 4.5 & 4.7 & R18 & R22 & R25）
    @discardableResult
    public func confirmAndExecuteDraft(
        _ draft: ActionDraft,
        chosenDestination: PrimaryDestination
    ) async -> ConfirmedAction {
        var mutableDraft = draft
        mutableDraft.proposedDestination = chosenDestination

        let recTitle = recordings.first(where: { $0.id == draft.recordingId })?.title ?? "MemoFlow 录音"
        var confirmedList = confirmedActionsByRecording[draft.recordingId] ?? []

        // 检查是否已有对应的 ConfirmedAction（稳定 ID 复用，PRD R19 & A16）
        let existingIndex = confirmedList.firstIndex(where: {
            $0.id == draft.confirmedActionId || $0.sourceDraftId == draft.id
        })

        var confirmed: ConfirmedAction
        if let idx = existingIndex {
            confirmed = confirmedList[idx]
            confirmed.confirmedSnapshot = ActionSnapshot(from: mutableDraft)
            confirmed.primaryDestination = chosenDestination
            confirmed.localCompletion = (chosenDestination == .local) ? (confirmed.localCompletion ?? false) : nil
        } else {
            confirmed = ConfirmedAction(
                recordingId: draft.recordingId,
                sourceDraftId: draft.id,
                confirmedSnapshot: ActionSnapshot(from: mutableDraft),
                primaryDestination: chosenDestination,
                localCompletion: chosenDestination == .local ? false : nil,
                executionStatus: .pendingConfirm
            )
        }

        // 根据主要管理位置执行
        switch chosenDestination {
        case .local:
            confirmed.executionStatus = .keptLocal
            confirmed.localCompletion = confirmed.localCompletion ?? false
            mutableDraft.reviewStatus = .confirmed
            logOperation(actionId: confirmed.id, operation: "confirm_local", status: .keptLocal, receipt: "local_only")

        case .markdown:
            // 主要位置为 Markdown（后续在导出 .md 时渲染为 - [ ] checkbox，App 内不再维护独立勾选，PRD R25 & A30）
            confirmed.executionStatus = .exportedMarkdown
            confirmed.localCompletion = nil
            mutableDraft.reviewStatus = .confirmed
            logOperation(actionId: confirmed.id, operation: "assign_markdown", status: .exportedMarkdown, receipt: "markdown_primary")

        case .calendar:
            let existingLink = externalLinksByConfirmedAction[confirmed.id]
            let result = await EventKitIntegrationService.shared.createCalendarEvent(
                for: confirmed,
                recordingTitle: recTitle,
                existingLink: existingLink,
                preferredCalendarId: preferences.preferredCalendarIdentifier
            )
            applyExternalExecutionResult(
                result,
                to: &confirmed,
                draft: &mutableDraft,
                targetType: .calendar
            )

        case .reminders:
            let existingLink = externalLinksByConfirmedAction[confirmed.id]
            let result = await EventKitIntegrationService.shared.createReminderItem(
                for: confirmed,
                recordingTitle: recTitle,
                existingLink: existingLink,
                preferredListId: preferences.preferredReminderListIdentifier
            )
            applyExternalExecutionResult(
                result,
                to: &confirmed,
                draft: &mutableDraft,
                targetType: .reminders
            )
        }

        mutableDraft.confirmedActionId = confirmed.id
        if let idx = existingIndex {
            confirmedList[idx] = confirmed
        } else {
            confirmedList.append(confirmed)
        }
        confirmedActionsByRecording[draft.recordingId] = confirmedList
        updateDraft(mutableDraft)
        saveToDisk()
        return confirmed
    }

    /// 批量确认执行（PRD P05 & A31：仅执行用户明确选中且通过校验的项，缺失信息或缺有效来源项绝不混入一键写入）
    public func batchConfirmAndExecute(draftIds: Set<UUID>) async -> (succeeded: Int, skippedOrFailed: Int) {
        var succeeded = 0
        var skippedOrFailed = 0

        for draft in allPendingActionDrafts where draftIds.contains(draft.id) {
            guard draft.isEligibleForBatchExecution else {
                skippedOrFailed += 1
                continue
            }
            let confirmed = await confirmAndExecuteDraft(draft, chosenDestination: draft.proposedDestination)
            if confirmed.executionStatus == .handedToExternal ||
                confirmed.executionStatus == .keptLocal ||
                confirmed.executionStatus == .exportedMarkdown {
                succeeded += 1
            } else {
                skippedOrFailed += 1
            }
        }
        return (succeeded, skippedOrFailed)
    }

    /// 切换本地任务的完成勾选状态（PRD R25 & A30：仅 primaryDestination == .local 时有效）
    public func toggleLocalActionCompletion(recordingId: UUID, confirmedActionId: UUID) {
        guard var list = confirmedActionsByRecording[recordingId],
              let idx = list.firstIndex(where: { $0.id == confirmedActionId }),
              list[idx].primaryDestination == .local else { return }
        list[idx].localCompletion = !(list[idx].localCompletion ?? false)
        confirmedActionsByRecording[recordingId] = list
        saveToDisk()
    }

    /// 切换已确认任务的主要管理位置（PRD 4.7 & 7.3 & A30：提示可能存在旧副本，清除不应存在的本地完成状态）
    public func switchPrimaryDestination(
        recordingId: UUID,
        confirmedActionId: UUID,
        newDestination: PrimaryDestination
    ) {
        guard var list = confirmedActionsByRecording[recordingId],
              let idx = list.firstIndex(where: { $0.id == confirmedActionId }) else { return }

        list[idx].primaryDestination = newDestination
        list[idx].localCompletion = (newDestination == .local) ? false : nil
        if newDestination == .markdown {
            list[idx].executionStatus = .exportedMarkdown
        } else if newDestination == .local {
            list[idx].executionStatus = .keptLocal
        }
        confirmedActionsByRecording[recordingId] = list
        lastBannerFeedback = "已切换主要管理位置为「\(newDestination.displayTitle)」。请注意：若此前已导出或写入其他工具，旧副本需手动处理。"
        saveToDisk()
    }

    // MARK: - Markdown Export Recording (PRD 7.1, 7.3, A29)

    public func recordMarkdownExportResult(
        for recordingId: UUID,
        result: ShareExportResult,
        destinationPath: String? = nil,
        vaultRelativePath: String? = nil
    ) {
        let confirmedIds = (confirmedActionsByRecording[recordingId] ?? []).map(\.id)
        let exportRecord = MarkdownExport(
            recordingId: recordingId,
            confirmedActionIds: confirmedIds,
            createdAt: Date(),
            shareResult: result,
            destinationPath: destinationPath,
            vaultRelativePath: vaultRelativePath
        )
        var list = markdownExportsByRecording[recordingId] ?? []
        list.append(exportRecord)
        markdownExportsByRecording[recordingId] = list
        saveToDisk()
    }

    public func hasCompletedMarkdownExport(for recordingId: UUID) -> Bool {
        (markdownExportsByRecording[recordingId] ?? []).contains(where: { $0.shareResult == .completed })
    }

    /// 将当前录音的整理结果稳定写入或原位受控更新同一篇 Obsidian 笔记（P0：稳定 recording_id 绑定 + 手写保护 + 冲突检测 + 写入前备份）
    @discardableResult
    public func saveNoteDirectlyToObsidian(
        for recordingId: UUID,
        legacyResolution: ObsidianLegacyResolution = .requireUserConfirmation
    ) throws -> (fileURL: URL, obsidianOpenURL: URL?) {
        guard let recIdx = recordings.firstIndex(where: { $0.id == recordingId }),
              let note = notesByRecording[recordingId],
              let rev = currentRevision(for: recordingId) else {
            throw NSError(domain: "MemoFlowObsidian", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到可导出的笔记版本，请先完成转写整理。"])
        }

        let confirmed = confirmedActionsByRecording[recordingId] ?? []
        let segs = segmentsByRecording[recordingId] ?? []
        let pending = actionDraftsByRecording[recordingId] ?? []
        let currentBinding = obsidianBindingsByRecording[recordingId]

        do {
            let root = try ObsidianNoteSyncService.resolveAuthorizedVaultURL(preferences: preferences)
            let accessed = root.startAccessingSecurityScopedResource()
            defer { if accessed { root.stopAccessingSecurityScopedResource() } }

            // P2-7：若开启「同步音频副本到笔记库附件目录」且本机存在原音频，先同步相对路径附件（严禁导出仅本机有效的绝对路径）
            if preferences.audioSyncMode == .vaultAttachmentCopy {
                let candidateRec = recordings[recIdx]
                let localAudioURL: URL? = {
                    if candidateRec.localAudioFileName.hasPrefix("demo_") {
                        return audioService.ensurePlayableDemoAudioFile(
                            named: candidateRec.localAudioFileName,
                            durationSeconds: max(5.0, candidateRec.duration)
                        )
                    }
                    guard !candidateRec.localAudioFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return nil
                    }
                    let u = audioService.audioFileURL(for: candidateRec.localAudioFileName)
                    return FileManager.default.fileExists(atPath: u.path) ? u : nil
                }()
                if let localAudioURL,
                   let relAudioPath = try? obsidianSyncService.syncAudioAttachmentToVault(
                       localAudioURL: localAudioURL,
                       recordingId: recordingId,
                       vaultRootURL: root,
                       attachmentSubfolder: preferences.obsidianAudioAttachmentSubfolder
                   ) {
                    recordings[recIdx].vaultAudioRelativePath = relAudioPath
                }
            }

            let rec = recordings[recIdx]
            let outcome = try obsidianSyncService.exportOrUpdateNote(
                recording: rec,
                note: note,
                revision: rev,
                confirmedActions: confirmed,
                segments: segs,
                pendingDrafts: pending,
                vaultRootURL: root,
                targetSubfolder: preferences.obsidianTargetSubfolder,
                existingBinding: currentBinding,
                backupsRootURL: obsidianBackupsDirectoryURL,
                legacyResolution: legacyResolution
            )

            obsidianBindingsByRecording[recordingId] = outcome.binding
            recordMarkdownExportResult(
                for: recordingId,
                result: .completed,
                destinationPath: outcome.binding.vaultRelativePath,
                vaultRelativePath: outcome.binding.vaultRelativePath
            )

            if !outcome.binding.conflicts.isEmpty {
                lastBannerFeedback = "已更新「\(outcome.fileURL.lastPathComponent)」，发现 \(outcome.binding.conflicts.count) 处双方修改冲突，已在笔记内同时保留双方版本待你选择。"
            } else if let oldRel = outcome.relocatedFromOldPath {
                lastBannerFeedback = "已按录音 ID 重新定位移动/重命名后的笔记（\(oldRel) → \(outcome.binding.vaultRelativePath)）并原位更新。"
            } else if outcome.wasCreatedNew {
                lastBannerFeedback = "已在 Obsidian 创建绑定笔记：\(outcome.binding.vaultRelativePath)"
            } else {
                lastBannerFeedback = "已原位更新固定 Obsidian 笔记：\(outcome.binding.vaultRelativePath)（手写内容与标签已保留）"
            }
            return (outcome.fileURL, outcome.obsidianOpenURL)
        } catch let syncErr as ObsidianSyncError {
            var updated = currentBinding ?? ObsidianNoteBinding(
                recordingId: recordingId,
                vaultRelativePath: "",
                lastKnownFileName: ""
            )
            switch syncErr {
            case .legacyNoteConfirmationRequired(let candidates):
                updated.status = .needsLegacyConfirmation
                updated.pendingLegacyCandidatePaths = candidates
                updated.lastErrorMessage = syncErr.errorDescription
                obsidianBindingsByRecording[recordingId] = updated
            case .cloudFileNotDownloaded(let relPath):
                if updated.vaultRelativePath.isEmpty { updated.vaultRelativePath = relPath }
                updated.status = .cloudNotDownloaded
                updated.lastErrorMessage = syncErr.errorDescription
                obsidianBindingsByRecording[recordingId] = updated
            case .authorizationExpired(let msg):
                updated.status = .authorizationExpired
                updated.lastErrorMessage = msg
                obsidianBindingsByRecording[recordingId] = updated
            default:
                updated.lastErrorMessage = syncErr.errorDescription
                if currentBinding != nil {
                    obsidianBindingsByRecording[recordingId] = updated
                }
            }
            lastBannerFeedback = syncErr.localizedDescription
            saveToDisk()
            throw syncErr
        } catch {
            lastBannerFeedback = error.localizedDescription
            throw error
        }
    }

    /// 用户审阅后确认关联缺少录音 ID 的同名历史笔记（保留历史笔记手写正文并绑定当前录音 ID）
    @discardableResult
    public func associateLegacyObsidianNote(
        for recordingId: UUID,
        relativePath: String
    ) throws -> (fileURL: URL, obsidianOpenURL: URL?) {
        try saveNoteDirectlyToObsidian(
            for: recordingId,
            legacyResolution: .associateExisting(relativePath: relativePath)
        )
    }

    /// 用户审阅后选择不覆盖历史同名笔记，而是创建带录音短 ID 的独立固定笔记
    @discardableResult
    public func createSeparateObsidianNote(
        for recordingId: UUID
    ) throws -> (fileURL: URL, obsidianOpenURL: URL?) {
        try saveNoteDirectlyToObsidian(
            for: recordingId,
            legacyResolution: .createSeparateNote
        )
    }

    /// 解决受控区块的双方修改冲突（保留 Obsidian 手改版 / 采用 MemoFlow 新版 / 合并保留双方）
    public func resolveObsidianConflict(
        for recordingId: UUID,
        blockKind: ObsidianManagedBlockKind,
        choice: ObsidianConflictResolutionChoice
    ) throws {
        guard let binding = obsidianBindingsByRecording[recordingId] else { return }
        let root = try ObsidianNoteSyncService.resolveAuthorizedVaultURL(preferences: preferences)
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }

        let nextBinding = try obsidianSyncService.resolveConflict(
            vaultRootURL: root,
            binding: binding,
            blockKind: blockKind,
            choice: choice,
            backupsRootURL: obsidianBackupsDirectoryURL
        )
        obsidianBindingsByRecording[recordingId] = nextBinding
        lastBannerFeedback = "已处理「\(blockKind.displayTitle)」冲突（\(choice.displayTitle)）。"
        saveToDisk()
    }

    /// 从最近一次写入前快照恢复 Obsidian 笔记
    public func restoreObsidianNoteFromBackup(for recordingId: UUID) throws {
        guard let binding = obsidianBindingsByRecording[recordingId] else {
            throw ObsidianSyncError.backupNotFound
        }
        let root = try ObsidianNoteSyncService.resolveAuthorizedVaultURL(preferences: preferences)
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }

        let nextBinding = try obsidianSyncService.restoreFromBackup(
            vaultRootURL: root,
            binding: binding
        )
        obsidianBindingsByRecording[recordingId] = nextBinding
        lastBannerFeedback = "已从写入前备份恢复 Obsidian 笔记：\(nextBinding.vaultRelativePath)"
        saveToDisk()
    }

    // MARK: - Delete Recording (PRD R04, 4.7, A10, A18)

    public func setHighlight(recordingId: UUID, segment: TranscriptSegment, note: String?) {
        guard segment.recordingId == recordingId,
              let index = recordings.firstIndex(where: { $0.id == recordingId }) else { return }
        var marks = recordings[index].marks ?? []
        marks.removeAll { $0.kind == "highlight" && $0.startMs == segment.startMs && $0.quote == segment.text }
        if let note {
            marks.append(RecordingMark(startMs: segment.startMs, endMs: segment.endMs, quote: segment.text, note: note, kind: "highlight"))
        }
        recordings[index].marks = marks
        saveToDisk()
    }

    public func removeMark(recordingId: UUID, markId: UUID) {
        guard let index = recordings.firstIndex(where: { $0.id == recordingId }) else { return }
        recordings[index].marks?.removeAll { $0.id == markId }
        saveToDisk()
    }

    /// P1-4：在录音完成后随时添加带来源时间戳的书签或批注
    public func addBookmarkMark(
        recordingId: UUID,
        atMs: Int,
        endMs: Int? = nil,
        quote: String = "",
        note: String = "",
        kind: String = "bookmark"
    ) {
        guard let index = recordings.firstIndex(where: { $0.id == recordingId }) else { return }
        let safeMs = max(0, atMs)
        var marks = recordings[index].marks ?? []
        marks.append(RecordingMark(startMs: safeMs, endMs: endMs, quote: quote, note: note, kind: kind))
        marks.sort { $0.startMs < $1.startMs }
        recordings[index].marks = marks
        saveToDisk()
    }

    /// P1-4：切换逐字稿人工审核状态（区分已人工校对 vs 机器初稿）
    public func setTranscriptReviewed(recordingId: UUID, reviewed: Bool) {
        guard let index = recordings.firstIndex(where: { $0.id == recordingId }) else { return }
        recordings[index].isTranscriptReviewed = reviewed
        if reviewed, recordings[index].processingStatus == .transcriptNeedsReview {
            recordings[index].processingStatus = .completed
            recordings[index].failureReason = nil
        }
        saveToDisk()
    }

    // MARK: - P1-3 Bidirectional Navigation (Obsidian <-> MemoFlow Deep Links)

    /// 生成指向知识库内任意笔记相对路径的 `obsidian://open` 链接（用于打开历史引用笔记）
    public func obsidianOpenURL(forRelativePath relativePath: String) -> URL? {
        if let root = try? ObsidianNoteSyncService.resolveAuthorizedVaultURL(preferences: preferences) {
            return MarkdownExporterService.obsidianOpenURL(vaultRootURL: root, relativePath: relativePath)
        }
        if let rawPath = preferences.obsidianVaultRootPath, !rawPath.isEmpty {
            return MarkdownExporterService.obsidianOpenURL(vaultRootURL: URL(fileURLWithPath: rawPath), relativePath: relativePath)
        }
        return nil
    }

    /// 打开某条录音绑定的固定 Obsidian 笔记；若笔记在 Obsidian 中被重命名或移动，自动按 `recording_id` 重定位后再打开
    public func openBoundObsidianNoteURL(for recordingId: UUID) throws -> URL {
        let root = try ObsidianNoteSyncService.resolveAuthorizedVaultURL(preferences: preferences)
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        if let binding = obsidianBindingsByRecording[recordingId], !binding.vaultRelativePath.isEmpty {
            let safeRel = try ObsidianNoteSyncService.validateSafeRelativePath(binding.vaultRelativePath)
            let directURL = root.appendingPathComponent(safeRel)
            try obsidianSyncService.verifyCloudDownloaded(fileURL: directURL, relativePath: safeRel)
            if fm.fileExists(atPath: directURL.path),
               let text = try? ObsidianNoteSyncService.readCoordinatedUTF8(at: directURL),
               ObsidianNoteSyncService.extractRecordingId(from: text) == recordingId,
               let openURL = MarkdownExporterService.obsidianOpenURL(vaultRootURL: root, relativePath: safeRel) {
                return openURL
            }
        }

        if let relocated = try obsidianSyncService.findNoteByRecordingId(
            recordingId: recordingId,
            vaultRootURL: root,
            preferredSubfolder: preferences.obsidianTargetSubfolder
        ) {
            var updated = obsidianBindingsByRecording[recordingId] ?? ObsidianNoteBinding(
                recordingId: recordingId,
                vaultRelativePath: relocated.relativePath,
                lastKnownFileName: relocated.fileURL.lastPathComponent
            )
            updated.vaultRelativePath = relocated.relativePath
            updated.lastKnownFileName = relocated.fileURL.lastPathComponent
            updated.status = .synced
            obsidianBindingsByRecording[recordingId] = updated
            saveToDisk()

            if let openURL = MarkdownExporterService.obsidianOpenURL(vaultRootURL: root, relativePath: relocated.relativePath) {
                return openURL
            }
        }

        if var existing = obsidianBindingsByRecording[recordingId] {
            existing.status = .missingInVault
            existing.lastErrorMessage = "未在 Obsidian 库中找到该录音对应的笔记文件（原音频仍安全保留）。"
            obsidianBindingsByRecording[recordingId] = existing
            saveToDisk()
        }
        throw ObsidianSyncError.fileOperationFailed("未在 Obsidian 库中找到该录音对应的笔记，请先点击导出创建或重新写入。")
    }

    /// 处理从 Obsidian 点击 `memoflow://recording/<UUID>?startMs=...` 打开应用或前台跳转（覆盖跨端自动载入、缺失录音、时间越界夹逼与冷启动导航）
    @discardableResult
    public func handleIncomingURL(_ url: URL) -> DeepLinkOutcome {
        guard let link = MemoFlowDeepLink.parse(url) else {
            let msg = "无法解析 MemoFlow 链接：\(url.absoluteString)"
            activeDeepLinkAlert = msg
            lastBannerFeedback = msg
            return .invalidURL(url.absoluteString)
        }

        if recordings.first(where: { $0.id == link.recordingId }) == nil {
            _ = try? hydrateMissingRecordingsFromVault()
        }

        guard let recording = recordings.first(where: { $0.id == link.recordingId }) else {
            let msg = "未在当前设备找到对应的录音记录（ID: \(link.recordingId.uuidString)）。可能尚未同步或已被删除。"
            activeDeepLinkAlert = msg
            lastBannerFeedback = msg
            return .recordingNotFound(recordingId: link.recordingId)
        }

        let totalMs = max(0, Int((recording.duration * 1000).rounded()))
        var targetStartMs = link.startMs
        var wasClamped = false

        if let requested = link.startMs {
            if requested < 0 {
                targetStartMs = 0
                wasClamped = true
            } else if totalMs > 0 && requested > totalMs {
                targetStartMs = max(0, totalMs - min(500, totalMs))
                wasClamped = true
            }
        }

        var targetEndMs = link.endMs
        if let start = targetStartMs, let end = targetEndMs {
            if end <= start {
                targetEndMs = nil
            } else if totalMs > 0 && end > totalMs {
                targetEndMs = totalMs
            }
        }

        activeDeepLinkRequest = DeepLinkNavigationRequest(
            recordingId: recording.id,
            targetStartMs: targetStartMs,
            targetEndMs: targetEndMs,
            isEstimated: link.isEstimated
        )

        let played = playRecording(
            recording,
            startMs: targetStartMs ?? 0,
            endMs: targetEndMs
        )

        if !played {
            let errMsg = audioService.lastPlaybackError ?? "当前设备尚未获取到该录音的音频文件。"
            activeDeepLinkAlert = errMsg
            lastBannerFeedback = errMsg
            return .audioMissingOnDevice(recordingId: recording.id, targetMs: targetStartMs, message: errMsg)
        }

        if wasClamped, let req = link.startMs, let clamped = targetStartMs {
            let msg = "链接时间（\(TimeFormatting.formatMilliseconds(max(0, req)))）超出录音长度，已定位到有效边界 \(TimeFormatting.formatMilliseconds(clamped))。"
            lastBannerFeedback = msg
            return .clampedOutOfBounds(recordingId: recording.id, requestedMs: req, clampedMs: clamped)
        }

        if let targetStartMs {
            let estPrefix = link.isEstimated ? "约 " : ""
            lastBannerFeedback = "已定位至录音 \(estPrefix)\(TimeFormatting.formatMilliseconds(targetStartMs)) 回听"
        } else {
            lastBannerFeedback = "已打开录音《\(recording.title)》"
        }
        return .opened(recordingId: recording.id, targetMs: targetStartMs, isEstimated: link.isEstimated)
    }

    // MARK: - P2-6 Bidirectional Scoped Sync (userSupplement, manualTags, projectName, marks)

    public func updateManualTags(for recordingId: UUID, tags: [String]) {
        guard var note = notesByRecording[recordingId] else { return }
        note.manualTags = ObsidianScopedSyncSnapshot.normalizeTags(tags)
        note.editedAt = Date()
        notesByRecording[recordingId] = note
        saveToDisk()
    }

    @discardableResult
    public func syncScopedFieldsWithObsidian(for recordingId: UUID) throws -> ObsidianNoteSyncService.ScopedReconcileOutcome? {
        guard let recIdx = recordings.firstIndex(where: { $0.id == recordingId }),
              let note = notesByRecording[recordingId],
              let rev = currentRevision(for: recordingId),
              let existingBinding = obsidianBindingsByRecording[recordingId] else {
            return nil
        }

        let root = try ObsidianNoteSyncService.resolveAuthorizedVaultURL(preferences: preferences)
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }

        let confirmed = confirmedActionsByRecording[recordingId] ?? []
        let segs = segmentsByRecording[recordingId] ?? []
        let pending = actionDraftsByRecording[recordingId] ?? []

        let outcome = try obsidianSyncService.reconcileScopedFields(
            recording: recordings[recIdx],
            note: note,
            revision: rev,
            confirmedActions: confirmed,
            segments: segs,
            pendingDrafts: pending,
            vaultRootURL: root,
            targetSubfolder: preferences.obsidianTargetSubfolder,
            existingBinding: existingBinding,
            backupsRootURL: obsidianBackupsDirectoryURL
        )

        var updatedNote = note
        var noteMutated = false
        if let supp = outcome.updatedUserSupplement {
            updatedNote.userSupplement = supp
            noteMutated = true
        }
        if let tags = outcome.updatedManualTags {
            updatedNote.manualTags = tags
            noteMutated = true
        }
        if outcome.shouldUpdateProjectName {
            updatedNote.projectName = outcome.updatedProjectName
            if let validProj = outcome.updatedProjectName, !preferences.knownProjectNames.contains(validProj) {
                preferences.knownProjectNames.append(validProj)
            }
            noteMutated = true
        }
        if noteMutated {
            updatedNote.editedAt = Date()
            notesByRecording[recordingId] = updatedNote
        }

        if let pulledMarks = outcome.updatedMarks,
           let latestIdx = recordings.firstIndex(where: { $0.id == recordingId }) {
            let existingById = Dictionary(uniqueKeysWithValues: (recordings[latestIdx].marks ?? []).map { ($0.id, $0) })
            recordings[latestIdx].marks = pulledMarks.map { m in
                RecordingMark(
                    id: m.id,
                    startMs: m.startMs,
                    endMs: m.endMs,
                    quote: m.quote,
                    note: m.note,
                    kind: m.kind,
                    createdAt: existingById[m.id]?.createdAt ?? Date()
                )
            }
        }

        if let pulledAudioRel = outcome.updatedVaultAudioRelativePath,
           let latestIdx = recordings.firstIndex(where: { $0.id == recordingId }) {
            recordings[latestIdx].vaultAudioRelativePath = pulledAudioRel
        }

        let bindingChanged = (obsidianBindingsByRecording[recordingId] != outcome.binding)
        obsidianBindingsByRecording[recordingId] = outcome.binding

        if outcome.noteWasDeletedInVault {
            lastBannerFeedback = "Obsidian 中的对应笔记已被移除；原音频与本地记录完好保留，可随时重新导出。"
        } else if !outcome.binding.scopedFieldConflicts.isEmpty {
            lastBannerFeedback = "检测到 \(outcome.binding.scopedFieldConflicts.count) 项字段双方同时修改冲突，请在详情页选择保留版本。"
        } else if let oldRel = outcome.relocatedFromOldPath {
            lastBannerFeedback = "已跟随重命名/移动重定位笔记（\(oldRel) → \(outcome.binding.vaultRelativePath)）并完成双向同步。"
        } else if outcome.didPullToMemoFlow && outcome.didWriteToDisk {
            lastBannerFeedback = "已完成双向字段同步（Obsidian ⇄ MemoFlow）。"
        } else if outcome.didPullToMemoFlow {
            lastBannerFeedback = "已将 Obsidian 中的修改同步回 MemoFlow。"
        } else if outcome.didWriteToDisk {
            lastBannerFeedback = "已将 MemoFlow 字段修改同步至 Obsidian 笔记。"
        }

        if noteMutated || outcome.updatedMarks != nil || outcome.updatedVaultAudioRelativePath != nil || bindingChanged || outcome.didWriteToDisk {
            saveToDisk()
        }
        return outcome
    }

    public func resolveScopedFieldConflict(
        for recordingId: UUID,
        field: ObsidianScopedField,
        choice: ObsidianConflictResolutionChoice
    ) throws {
        guard let recIdx = recordings.firstIndex(where: { $0.id == recordingId }),
              var note = notesByRecording[recordingId],
              let rev = currentRevision(for: recordingId),
              let binding = obsidianBindingsByRecording[recordingId] else {
            return
        }

        let root = try ObsidianNoteSyncService.resolveAuthorizedVaultURL(preferences: preferences)
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }

        let confirmed = confirmedActionsByRecording[recordingId] ?? []
        let segs = segmentsByRecording[recordingId] ?? []
        let pending = actionDraftsByRecording[recordingId] ?? []

        let result = try obsidianSyncService.resolveScopedFieldConflict(
            field: field,
            choice: choice,
            recording: recordings[recIdx],
            note: note,
            revision: rev,
            confirmedActions: confirmed,
            segments: segs,
            pendingDrafts: pending,
            vaultRootURL: root,
            binding: binding,
            backupsRootURL: obsidianBackupsDirectoryURL
        )

        note.userSupplement = result.resolvedSnapshot.userSupplement
        note.manualTags = result.resolvedSnapshot.manualTags
        note.projectName = result.resolvedSnapshot.projectName
        if let validProj = note.projectName, !preferences.knownProjectNames.contains(validProj) {
            preferences.knownProjectNames.append(validProj)
        }
        note.editedAt = Date()
        notesByRecording[recordingId] = note

        let existingById = Dictionary(uniqueKeysWithValues: (recordings[recIdx].marks ?? []).map { ($0.id, $0) })
        recordings[recIdx].marks = result.resolvedSnapshot.marks.map { m in
            RecordingMark(
                id: m.id,
                startMs: m.startMs,
                endMs: m.endMs,
                quote: m.quote,
                note: m.note,
                kind: m.kind,
                createdAt: existingById[m.id]?.createdAt ?? Date()
            )
        }

        obsidianBindingsByRecording[recordingId] = result.binding
        lastBannerFeedback = "已处理「\(field.displayTitle)」双向同步冲突（\(choice.displayTitle)）。"
        saveToDisk()
    }

    @discardableResult
    public func syncAllBoundObsidianNotes(hydrateNewFromVault: Bool = true) -> Int {
        guard (try? ObsidianNoteSyncService.resolveAuthorizedVaultURL(preferences: preferences)) != nil else {
            return 0
        }
        var touchedCount = 0
        if hydrateNewFromVault, let hydrated = try? hydrateMissingRecordingsFromVault() {
            touchedCount += hydrated
        }
        let boundIds = Array(obsidianBindingsByRecording.keys)
        for recId in boundIds {
            guard let b = obsidianBindingsByRecording[recId],
                  !b.vaultRelativePath.isEmpty,
                  b.status != .missingInVault else {
                continue
            }
            if let outcome = try? syncScopedFieldsWithObsidian(for: recId),
               (outcome.didPullToMemoFlow || outcome.didWriteToDisk || outcome.noteWasDeletedInVault || outcome.relocatedFromOldPath != nil || !outcome.binding.scopedFieldConflicts.isEmpty) {
                touchedCount += 1
            }
        }
        if touchedCount == 0 && hydrateNewFromVault {
            lastBannerFeedback = "Obsidian 笔记库双向对账完成，所有绑定字段均已是最新状态。"
        }
        return touchedCount
    }

    // MARK: - P2-7 Cross-Device Audio Availability (iPhone <-> Mac)

    private func inspectVaultAttachmentStateIfAuthorized(for recording: Recording) -> AudioAvailabilityState? {
        guard let root = try? ObsidianNoteSyncService.resolveAuthorizedVaultURL(preferences: preferences) else {
            return nil
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        return obsidianSyncService.inspectVaultAudioAttachment(
            recording: recording,
            vaultRootURL: root,
            attachmentSubfolder: preferences.obsidianAudioAttachmentSubfolder
        )
    }

    /// 评估当前设备上某条录音的音频可用性与跨端同步状态（严格区分「笔记已同步」与「音频已同步」）
    public func audioAvailability(for recording: Recording) -> AudioAvailabilityState {
        let vaultState = inspectVaultAttachmentStateIfAuthorized(for: recording)
        let alsoSyncedInVault = vaultState?.isAudioSyncedAcrossDevices ?? (MarkdownExporterService.sanitizedVaultRelativeAudioPath(recording.vaultAudioRelativePath) != nil)

        if recording.localAudioFileName.hasPrefix("demo_") {
            let demoURL = audioService.ensurePlayableDemoAudioFile(
                named: recording.localAudioFileName,
                durationSeconds: max(5.0, recording.duration)
            )
            return .availableLocal(fileURL: demoURL, alsoSyncedInVault: alsoSyncedInVault)
        }

        let trimmedLocal = recording.localAudioFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLocal.isEmpty {
            let localURL = audioService.audioFileURL(for: trimmedLocal)
            if FileManager.default.fileExists(atPath: localURL.path) {
                return .availableLocal(fileURL: localURL, alsoSyncedInVault: alsoSyncedInVault)
            }
        }

        if let vaultState {
            return vaultState
        }

        let binding = obsidianBindingsByRecording[recording.id]
        let isNoteSynced = binding != nil && binding?.status != .missingInVault && !(binding?.vaultRelativePath.isEmpty ?? true)
        if isNoteSynced {
            return .missingOnCurrentDevice(
                reason: "笔记已同步到当前设备，但原音频尚未到达（原录制设备未同步音频附件，或附件尚未完成同步）。可在原设备点击「同步音频副本到笔记库」，或在本机手动选择音频文件绑定。"
            )
        } else {
            return .missingOnCurrentDevice(
                reason: "当前设备未找到原音频文件（\(recording.localAudioFileName)）。"
            )
        }
    }

    public func syncOverview(for recording: Recording) -> NoteAndAudioSyncOverview {
        let binding = obsidianBindingsByRecording[recording.id]
        let isNoteSynced = binding != nil && binding?.status != .missingInVault && !(binding?.vaultRelativePath.isEmpty ?? true)
        let noteBadge: String
        if let binding {
            noteBadge = (binding.status == .synced) ? "笔记已同步" : binding.status.displayTitle
        } else {
            noteBadge = "笔记未同步"
        }
        return NoteAndAudioSyncOverview(
            isNoteSynced: isNoteSynced,
            noteBadgeTitle: noteBadge,
            audioState: audioAvailability(for: recording)
        )
    }

    @discardableResult
    public func playRecording(_ recording: Recording, startMs: Int = 0, endMs: Int? = nil) -> Bool {
        switch audioAvailability(for: recording) {
        case .availableLocal(let fileURL, _):
            return audioService.play(recording: recording, startMs: startMs, endMs: endMs, overrideFileURL: fileURL)

        case .availableInVaultAttachment(let fileURL, let relPath):
            if let idx = recordings.firstIndex(where: { $0.id == recording.id }),
               recordings[idx].vaultAudioRelativePath != relPath {
                recordings[idx].vaultAudioRelativePath = relPath
                saveToDisk()
            }
            return audioService.play(recording: recording, startMs: startMs, endMs: endMs, overrideFileURL: fileURL)

        case .cloudNotDownloaded(let relPath):
            requestCloudAudioDownload(for: recording.id)
            let msg = "笔记已同步，音频附件（\(relPath)）正在等待 iCloud 下载，下载完成后即可回听。"
            audioService.lastPlaybackError = msg
            lastBannerFeedback = msg
            return false

        case .missingOnCurrentDevice(let reason):
            audioService.lastPlaybackError = reason
            lastBannerFeedback = reason
            return false
        }
    }

    public func togglePlayPauseRecording(_ recording: Recording) {
        if audioService.playingRecordingId == recording.id {
            audioService.togglePlayPause(for: recording)
        } else {
            _ = playRecording(recording, startMs: 0, endMs: nil)
        }
    }

    public func seekRecording(_ recording: Recording, toMs: Int) {
        if audioService.playingRecordingId == recording.id {
            audioService.seek(for: recording, toMs: toMs)
        } else {
            _ = playRecording(recording, startMs: toMs, endMs: nil)
        }
    }

    /// 将当前设备上的原音频复制一份到 Obsidian 笔记库相对附件目录，并刷新绑定笔记中的相对引用
    @discardableResult
    public func syncAudioAttachmentToVault(for recordingId: UUID, refreshBoundNote: Bool = true) throws -> String {
        guard let idx = recordings.firstIndex(where: { $0.id == recordingId }) else {
            throw ObsidianSyncError.fileOperationFailed("未找到对应录音记录。")
        }
        let rec = recordings[idx]
        let localAudioURL: URL
        if rec.localAudioFileName.hasPrefix("demo_") {
            localAudioURL = audioService.ensurePlayableDemoAudioFile(
                named: rec.localAudioFileName,
                durationSeconds: max(5.0, rec.duration)
            )
        } else {
            localAudioURL = audioService.audioFileURL(for: rec.localAudioFileName)
        }

        let root = try ObsidianNoteSyncService.resolveAuthorizedVaultURL(preferences: preferences)
        let accessed = root.startAccessingSecurityScopedResource()
        let relPath: String
        do {
            relPath = try obsidianSyncService.syncAudioAttachmentToVault(
                localAudioURL: localAudioURL,
                recordingId: recordingId,
                vaultRootURL: root,
                attachmentSubfolder: preferences.obsidianAudioAttachmentSubfolder
            )
            if accessed { root.stopAccessingSecurityScopedResource() }
        } catch {
            if accessed { root.stopAccessingSecurityScopedResource() }
            throw error
        }

        recordings[idx].vaultAudioRelativePath = relPath
        saveToDisk()

        if refreshBoundNote,
           obsidianBindingsByRecording[recordingId] != nil,
           notesByRecording[recordingId] != nil {
            _ = try? saveNoteDirectlyToObsidian(for: recordingId)
        }
        lastBannerFeedback = "已同步音频副本到笔记库附件（\(relPath)），另一端同步后即可直接回听。"
        return relPath
    }

    /// 在另一台设备上将笔记库中的音频附件缓存到本机录音目录，支持本机离线回听与重新转写
    @discardableResult
    public func cacheVaultAudioToLocal(for recordingId: UUID) throws -> URL {
        guard let idx = recordings.firstIndex(where: { $0.id == recordingId }) else {
            throw ObsidianSyncError.fileOperationFailed("未找到对应录音记录。")
        }
        let rec = recordings[idx]
        switch audioAvailability(for: rec) {
        case .availableLocal(let fileURL, _):
            return fileURL
        case .availableInVaultAttachment(let vaultFileURL, let relPath):
            let ext = vaultFileURL.pathExtension.isEmpty ? "m4a" : vaultFileURL.pathExtension.lowercased()
            let targetFileName = "rec_\(recordingId.uuidString).\(ext)"
            let localDest = audioService.audioFileURL(for: targetFileName)
            let data = try Data(contentsOf: vaultFileURL)
            try data.write(to: localDest, options: .atomic)
            recordings[idx].localAudioFileName = targetFileName
            recordings[idx].vaultAudioRelativePath = relPath
            saveToDisk()
            lastBannerFeedback = "已将跨端音频缓存至本机录音目录（\(targetFileName)）。"
            return localDest
        case .cloudNotDownloaded(let relPath):
            requestCloudAudioDownload(for: recordingId)
            throw ObsidianSyncError.cloudFileNotDownloaded(relativePath: relPath)
        case .missingOnCurrentDevice(let reason):
            throw ObsidianSyncError.fileOperationFailed(reason)
        }
    }

    public func requestCloudAudioDownload(for recordingId: UUID) {
        guard let root = try? ObsidianNoteSyncService.resolveAuthorizedVaultURL(preferences: preferences),
              let rec = recordings.first(where: { $0.id == recordingId }) else {
            return
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }

        if let rel = MarkdownExporterService.sanitizedVaultRelativeAudioPath(rec.vaultAudioRelativePath) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: root.appendingPathComponent(rel))
        } else if let cleanSub = try? ObsidianNoteSyncService.validateSafeRelativePath(preferences.obsidianAudioAttachmentSubfolder) {
            for ext in ["m4a", "wav"] {
                let candidate = root.appendingPathComponent("\(cleanSub)/rec_\(rec.id.uuidString).\(ext)")
                try? FileManager.default.startDownloadingUbiquitousItem(at: candidate)
            }
        }
        lastBannerFeedback = "已向 iCloud 请求下载跨端音频附件，请稍候重试回听。"
    }

    /// 当音频未通过笔记库同步时，允许用户在当前设备手动选择音频文件绑定恢复回听
    public func importLocalAudioCopy(for recordingId: UUID, from sourceURL: URL) throws {
        guard let idx = recordings.firstIndex(where: { $0.id == recordingId }) else {
            throw ObsidianSyncError.fileOperationFailed("未找到对应录音记录。")
        }
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension.lowercased()
        let targetFileName = "rec_\(recordingId.uuidString).\(ext)"
        let localDest = audioService.audioFileURL(for: targetFileName)
        let data = try Data(contentsOf: sourceURL)
        try data.write(to: localDest, options: .atomic)

        recordings[idx].localAudioFileName = targetFileName
        saveToDisk()
        lastBannerFeedback = "已导入并绑定本机音频文件，现在可以直接回听。"
    }

    /// 从 Obsidian 笔记库扫描另一端导出的带 `recording_id` 笔记，在本机尚无该录音记录时自动载入笔记与相对音频关联
    @discardableResult
    public func hydrateMissingRecordingsFromVault() throws -> Int {
        let root = try ObsidianNoteSyncService.resolveAuthorizedVaultURL(preferences: preferences)
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }

        let existingIds = Set(recordings.map(\.id))
        let hydratedList = try obsidianSyncService.hydrateMissingRecordingsFromVault(
            vaultRootURL: root,
            preferredSubfolder: preferences.obsidianTargetSubfolder,
            existingRecordingIds: existingIds
        )
        guard !hydratedList.isEmpty else { return 0 }

        for item in hydratedList {
            recordings.append(item.recording)
            notesByRecording[item.recording.id] = item.note
            revisionsByNote[item.note.id] = [item.revision]
            segmentsByRecording[item.recording.id] = item.segments
            obsidianBindingsByRecording[item.recording.id] = item.binding
            if let proj = item.note.projectName, !preferences.knownProjectNames.contains(proj) {
                preferences.knownProjectNames.append(proj)
            }
        }
        recordings.sort { $0.createdAt > $1.createdAt }
        saveToDisk()
        lastBannerFeedback = "已从 Obsidian 笔记库同步载入 \(hydratedList.count) 条跨端录音笔记。"
        return hydratedList.count
    }

    // MARK: - P1-5 Personal Memory Review CRUD & Grounded Q&A

    @discardableResult
    public func extractCandidateMemories(for recordingId: UUID) -> [PersonalMemoryItem] {
        guard let rec = recordings.first(where: { $0.id == recordingId }) else { return [] }
        let note = notesByRecording[recordingId]
        let segs = segmentsByRecording[recordingId] ?? []
        let boundPath = obsidianBindingsByRecording[recordingId]?.vaultRelativePath
        var added: [PersonalMemoryItem] = []

        if let proj = note?.projectName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !proj.isEmpty,
           !personalMemories.contains(where: { $0.category == .project && $0.key == proj }) {
            let item = PersonalMemoryItem(
                category: .project,
                key: proj,
                value: "来自录音《\(rec.title)》关联的项目背景",
                sourceRecordingId: recordingId,
                sourceNotePath: boundPath,
                status: .pendingReview
            )
            personalMemories.insert(item, at: 0)
            added.append(item)
        }

        let speakers = Set(segs.compactMap(\.speakerName)).subtracting(["我", "说话人", "发言人"])
        for spk in speakers where !spk.isEmpty {
            if !personalMemories.contains(where: { $0.category == .person && $0.key == spk }) {
                let item = PersonalMemoryItem(
                    category: .person,
                    key: spk,
                    value: "在《\(rec.title)》中参与讨论的协作者",
                    sourceRecordingId: recordingId,
                    sourceNotePath: boundPath,
                    status: .pendingReview
                )
                personalMemories.insert(item, at: 0)
                added.append(item)
            }
        }

        for tag in note?.manualTags ?? [] {
            let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty, !personalMemories.contains(where: { $0.category == .term && $0.key == cleaned }) {
                let item = PersonalMemoryItem(
                    category: .term,
                    key: cleaned,
                    value: "录音标签术语（来自《\(rec.title)》）",
                    sourceRecordingId: recordingId,
                    sourceNotePath: boundPath,
                    status: .pendingReview
                )
                personalMemories.insert(item, at: 0)
                added.append(item)
            }
        }

        if !added.isEmpty {
            saveToDisk()
            lastBannerFeedback = "已提取 \(added.count) 条个人记忆候选（待你在设置页审阅确认后才会生效）。"
        } else {
            lastBannerFeedback = "暂无新的待审阅个人记忆项。"
        }
        return added
    }

    @discardableResult
    public func addPersonalMemory(
        category: PersonalMemoryCategory,
        key: String,
        value: String,
        sourceRecordingId: UUID? = nil,
        sourceNotePath: String? = nil,
        status: PersonalMemoryStatus = .pendingReview
    ) -> PersonalMemoryItem? {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return nil }
        let item = PersonalMemoryItem(
            category: category,
            key: k,
            value: v,
            sourceRecordingId: sourceRecordingId,
            sourceNotePath: sourceNotePath,
            status: status
        )
        personalMemories.insert(item, at: 0)
        saveToDisk()
        return item
    }

    public func confirmPersonalMemory(_ id: UUID) {
        guard let idx = personalMemories.firstIndex(where: { $0.id == id }) else { return }
        personalMemories[idx].status = .confirmed
        personalMemories[idx].updatedAt = Date()
        if personalMemories[idx].category == .project,
           !preferences.knownProjectNames.contains(personalMemories[idx].key) {
            preferences.knownProjectNames.append(personalMemories[idx].key)
        }
        saveToDisk()
    }

    public func updatePersonalMemory(
        id: UUID,
        category: PersonalMemoryCategory? = nil,
        key: String,
        value: String,
        status: PersonalMemoryStatus? = nil
    ) {
        guard let idx = personalMemories.firstIndex(where: { $0.id == id }) else { return }
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        if let category { personalMemories[idx].category = category }
        personalMemories[idx].key = trimmedKey
        personalMemories[idx].value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let status { personalMemories[idx].status = status }
        personalMemories[idx].updatedAt = Date()
        saveToDisk()
    }

    public func deletePersonalMemory(_ id: UUID) {
        personalMemories.removeAll { $0.id == id }
        saveToDisk()
    }

    public func askGroundedQuestion(_ question: String) async -> GroundedQAResult {
        do {
            return try await knowledgeService.answerGroundedQuestion(
                question: question,
                preferences: preferences,
                recordings: recordings,
                segmentsByRecording: segmentsByRecording,
                notesByRecording: notesByRecording,
                bindingsByRecording: obsidianBindingsByRecording
            )
        } catch {
            return GroundedQAResult(
                question: question,
                answer: "跨笔记检索失败：\(error.localizedDescription)",
                citations: [],
                capabilityDisclosure: "当前使用本地关键词检索，请检查知识库目录授权状态。",
                usedCloudLLM: false
            )
        }
    }

    /// 删除录音及本地关联数据，但不默认删除已创建的外部日历事件或提醒事项（PRD 4.7 & A18）
    public func deleteRecording(_ recordingId: UUID) {
        if audioService.playingRecordingId == recordingId {
            audioService.stopPlayback()
        }
        if let rec = recordings.first(where: { $0.id == recordingId }) {
            let fileURL = audioService.audioFileURL(for: rec.localAudioFileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
        if let note = notesByRecording[recordingId] {
            revisionsByNote.removeValue(forKey: note.id)
        }
        let removedActionIds = Set(
            (confirmedActionsByRecording[recordingId] ?? []).map(\.id)
        )

        recordings.removeAll { $0.id == recordingId }
        segmentsByRecording.removeValue(forKey: recordingId)
        notesByRecording.removeValue(forKey: recordingId)
        actionDraftsByRecording.removeValue(forKey: recordingId)
        confirmedActionsByRecording.removeValue(forKey: recordingId)
        markdownExportsByRecording.removeValue(forKey: recordingId)
        obsidianBindingsByRecording.removeValue(forKey: recordingId)
        processingJobsByRecording.removeValue(forKey: recordingId)
        externalLinksByConfirmedAction = externalLinksByConfirmedAction.filter {
            !removedActionIds.contains($0.key)
        }
        operationLogs.removeAll { removedActionIds.contains($0.confirmedActionId) }
        saveToDisk()
    }

    // MARK: - Private Helpers

    private func applyExternalExecutionResult(
        _ result: ExternalWriteExecutionResult,
        to confirmed: inout ConfirmedAction,
        draft: inout ActionDraft,
        targetType: PrimaryDestination
    ) {
        switch result {
        case .created(let extId, let containerId, let containerTitle):
            confirmed.executionStatus = .handedToExternal
            confirmed.localCompletion = nil
            draft.reviewStatus = .confirmed
            externalLinksByConfirmedAction[confirmed.id] = ExternalActionLink(
                confirmedActionId: confirmed.id,
                targetType: targetType,
                externalIdentifier: extId,
                targetContainerIdentifier: containerId,
                targetContainerTitle: containerTitle,
                lastConfirmedSnapshot: confirmed.confirmedSnapshot
            )
            logOperation(actionId: confirmed.id, operation: "create_\(targetType.rawValue)", status: .handedToExternal, receipt: extId)
            lastBannerFeedback = "已写入 \(targetType.displayTitle)（\(containerTitle)）"

        case .skippedAlreadyCreated(let extId):
            confirmed.executionStatus = .handedToExternal
            confirmed.localCompletion = nil
            draft.reviewStatus = .confirmed
            logOperation(actionId: confirmed.id, operation: "dedup_skip_\(targetType.rawValue)", status: .handedToExternal, receipt: extId)
            lastBannerFeedback = "该事项已创建过（回执 \(extId.prefix(8))），已自动跳过避免重复写入"

        case .blockedPendingVerification(let reason):
            confirmed.executionStatus = .pendingVerification
            lastBannerFeedback = reason

        case .permissionDenied(let message):
            confirmed.executionStatus = .executionFailed
            externalLinksByConfirmedAction[confirmed.id] = ExternalActionLink(
                confirmedActionId: confirmed.id,
                targetType: targetType,
                lastConfirmedSnapshot: confirmed.confirmedSnapshot,
                lastError: message
            )
            logOperation(actionId: confirmed.id, operation: "create_\(targetType.rawValue)", status: .executionFailed, errorCode: "PERMISSION_DENIED")
            lastBannerFeedback = message

        case .failed(let code, let message, let isUncertain):
            let status: ActionExecutionStatus = isUncertain ? .pendingVerification : .executionFailed
            confirmed.executionStatus = status
            externalLinksByConfirmedAction[confirmed.id] = ExternalActionLink(
                confirmedActionId: confirmed.id,
                targetType: targetType,
                lastConfirmedSnapshot: confirmed.confirmedSnapshot,
                lastError: message
            )
            logOperation(actionId: confirmed.id, operation: "create_\(targetType.rawValue)", status: status, errorCode: code)
            lastBannerFeedback = message
        }
    }

    private func logOperation(
        actionId: UUID,
        operation: String,
        status: ActionExecutionStatus,
        errorCode: String? = nil,
        receipt: String? = nil
    ) {
        let log = ActionOperationLog(
            confirmedActionId: actionId,
            operation: operation,
            status: status,
            errorCode: errorCode,
            receipt: receipt
        )
        operationLogs.insert(log, at: 0)
    }

    private func updateRecordingStatus(
        _ id: UUID,
        status: RecordingProcessingStatus,
        failureReason: String?
    ) {
        guard let idx = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[idx].processingStatus = status
        recordings[idx].failureReason = failureReason
    }

    // MARK: - Persistence & PRD Seed Data (PRD 1.4, 4.6, 7.2)

    private struct PersistedSnapshot: Codable {
        var recordings: [Recording]
        var segmentsByRecording: [UUID: [TranscriptSegment]]
        var notesByRecording: [UUID: Note]
        var revisionsByNote: [UUID: [NoteRevision]]
        var actionDraftsByRecording: [UUID: [ActionDraft]]
        var confirmedActionsByRecording: [UUID: [ConfirmedAction]]
        var externalLinksByConfirmedAction: [UUID: ExternalActionLink]
        var operationLogs: [ActionOperationLog]
        var markdownExportsByRecording: [UUID: [MarkdownExport]]
        var obsidianBindingsByRecording: [UUID: ObsidianNoteBinding]
        var personalMemories: [PersonalMemoryItem]
        var processingConsent: ProcessingConsent
        var processingJobsByRecording: [UUID: ProcessingJob]
        var preferences: MemoFlowPreferences

        init(
            recordings: [Recording],
            segmentsByRecording: [UUID: [TranscriptSegment]],
            notesByRecording: [UUID: Note],
            revisionsByNote: [UUID: [NoteRevision]],
            actionDraftsByRecording: [UUID: [ActionDraft]],
            confirmedActionsByRecording: [UUID: [ConfirmedAction]],
            externalLinksByConfirmedAction: [UUID: ExternalActionLink],
            operationLogs: [ActionOperationLog],
            markdownExportsByRecording: [UUID: [MarkdownExport]],
            obsidianBindingsByRecording: [UUID: ObsidianNoteBinding] = [:],
            personalMemories: [PersonalMemoryItem] = [],
            processingConsent: ProcessingConsent,
            processingJobsByRecording: [UUID: ProcessingJob],
            preferences: MemoFlowPreferences
        ) {
            self.recordings = recordings
            self.segmentsByRecording = segmentsByRecording
            self.notesByRecording = notesByRecording
            self.revisionsByNote = revisionsByNote
            self.actionDraftsByRecording = actionDraftsByRecording
            self.confirmedActionsByRecording = confirmedActionsByRecording
            self.externalLinksByConfirmedAction = externalLinksByConfirmedAction
            self.operationLogs = operationLogs
            self.markdownExportsByRecording = markdownExportsByRecording
            self.obsidianBindingsByRecording = obsidianBindingsByRecording
            self.personalMemories = personalMemories
            self.processingConsent = processingConsent
            self.processingJobsByRecording = processingJobsByRecording
            self.preferences = preferences
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.recordings = try c.decodeIfPresent([Recording].self, forKey: .recordings) ?? []
            self.segmentsByRecording = try c.decodeIfPresent([UUID: [TranscriptSegment]].self, forKey: .segmentsByRecording) ?? [:]
            self.notesByRecording = try c.decodeIfPresent([UUID: Note].self, forKey: .notesByRecording) ?? [:]
            self.revisionsByNote = try c.decodeIfPresent([UUID: [NoteRevision]].self, forKey: .revisionsByNote) ?? [:]
            self.actionDraftsByRecording = try c.decodeIfPresent([UUID: [ActionDraft]].self, forKey: .actionDraftsByRecording) ?? [:]
            self.confirmedActionsByRecording = try c.decodeIfPresent([UUID: [ConfirmedAction]].self, forKey: .confirmedActionsByRecording) ?? [:]
            self.externalLinksByConfirmedAction = try c.decodeIfPresent([UUID: ExternalActionLink].self, forKey: .externalLinksByConfirmedAction) ?? [:]
            self.operationLogs = try c.decodeIfPresent([ActionOperationLog].self, forKey: .operationLogs) ?? []
            self.markdownExportsByRecording = try c.decodeIfPresent([UUID: [MarkdownExport]].self, forKey: .markdownExportsByRecording) ?? [:]
            self.obsidianBindingsByRecording = try c.decodeIfPresent([UUID: ObsidianNoteBinding].self, forKey: .obsidianBindingsByRecording) ?? [:]
            self.personalMemories = try c.decodeIfPresent([PersonalMemoryItem].self, forKey: .personalMemories) ?? []
            self.processingConsent = try c.decodeIfPresent(ProcessingConsent.self, forKey: .processingConsent) ?? ProcessingConsent()
            self.processingJobsByRecording = try c.decodeIfPresent([UUID: ProcessingJob].self, forKey: .processingJobsByRecording) ?? [:]
            self.preferences = try c.decodeIfPresent(MemoFlowPreferences.self, forKey: .preferences) ?? MemoFlowPreferences()
        }
    }

    @discardableResult
    public func saveToDisk() -> Bool {
        let snap = PersistedSnapshot(
            recordings: recordings,
            segmentsByRecording: segmentsByRecording,
            notesByRecording: notesByRecording,
            revisionsByNote: revisionsByNote,
            actionDraftsByRecording: actionDraftsByRecording,
            confirmedActionsByRecording: confirmedActionsByRecording,
            externalLinksByConfirmedAction: externalLinksByConfirmedAction,
            operationLogs: operationLogs,
            markdownExportsByRecording: markdownExportsByRecording,
            obsidianBindingsByRecording: obsidianBindingsByRecording,
            personalMemories: personalMemories,
            processingConsent: processingConsent,
            processingJobsByRecording: processingJobsByRecording,
            preferences: preferences
        )
        do {
            let data = try JSONEncoder().encode(snap)
            try data.write(to: persistenceURL, options: .atomic)
            return true
        } catch {
            lastBannerFeedback = "保存记录失败：\(error.localizedDescription)。原音频保留，请释放空间后重试。"
            return false
        }
    }

    private func loadFromDisk() -> Bool {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else {
            return false
        }
        guard let data = try? Data(contentsOf: persistenceURL) else {
            return false
        }
        do {
            let snap = try JSONDecoder().decode(PersistedSnapshot.self, from: data)
            self.recordings = snap.recordings
            self.segmentsByRecording = snap.segmentsByRecording
            self.notesByRecording = snap.notesByRecording
            self.revisionsByNote = snap.revisionsByNote
            self.actionDraftsByRecording = snap.actionDraftsByRecording
            self.confirmedActionsByRecording = snap.confirmedActionsByRecording
            self.externalLinksByConfirmedAction = snap.externalLinksByConfirmedAction
            self.operationLogs = snap.operationLogs
            self.markdownExportsByRecording = snap.markdownExportsByRecording
            self.obsidianBindingsByRecording = snap.obsidianBindingsByRecording
            self.personalMemories = snap.personalMemories
            self.processingConsent = snap.processingConsent
            self.processingJobsByRecording = snap.processingJobsByRecording
            self.preferences = snap.preferences
            if self.preferences.llmModelName.contains("Qwen3-235B") || self.preferences.llmModelName.contains("Qwen3-32B") {
                self.preferences.llmModelName = "Qwen/Qwen2.5-72B-Instruct"
            }
            return true
        } catch {
            print("MemoFlowStore loadFromDisk decode error: \(error)")
            let backupCorrupt = persistenceURL.deletingLastPathComponent().appendingPathComponent("MemoFlowState_corrupt_\(Int(Date().timeIntervalSince1970)).json")
            try? data.write(to: backupCorrupt)
            return false
        }
    }

    /// 一键重置并加载 PRD 1.4 / 4.6 的典型场景数据（场景 A 随手记 + 场景 B 会议记）
    public func seedPRDDefaultScenarios() {
        recordings.removeAll()
        segmentsByRecording.removeAll()
        notesByRecording.removeAll()
        revisionsByNote.removeAll()
        actionDraftsByRecording.removeAll()
        confirmedActionsByRecording.removeAll()
        externalLinksByConfirmedAction.removeAll()
        operationLogs.removeAll()
        markdownExportsByRecording.removeAll()
        obsidianBindingsByRecording.removeAll()

        let tz = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let now = Date()

        // 1. 场景 A｜随手留住灵感（PRD 1.4 & A20）
        let recAId = UUID()
        let recAFileName = "demo_inspiration.wav"
        _ = audioService.ensurePlayableDemoAudioFile(named: recAFileName, durationSeconds: 18)

        let recA = Recording(
            id: recAId,
            title: "日本旅行视频开头转场灵感",
            createdAt: now.addingTimeInterval(-3600 * 3),
            recordedTimeZoneIdentifier: tz.identifier,
            duration: 18,
            localAudioFileName: recAFileName,
            language: "zh-CN",
            processingStatus: .completed
        )

        let segsA: [TranscriptSegment] = [
            TranscriptSegment(
                id: "seg_01",
                recordingId: recAId,
                startMs: 0,
                endMs: 9200,
                text: "早上手冲咖啡的时候看了一下镜头，咖啡杯往上冒的蒸汽其实可以直接无缝接北海道温泉的镜头。",
                speakerId: "me",
                speakerName: "我"
            ),
            TranscriptSegment(
                id: "seg_02",
                recordingId: recAId,
                startMs: 9200,
                endMs: 18000,
                text: "这个转场放在日本旅行视频的开头前五秒应该很有代入感，先记一下。",
                speakerId: "me",
                speakerName: "我"
            )
        ]

        let noteAId = UUID()
        let revAId = UUID()
        let revA = NoteRevision(
            id: revAId,
            noteId: noteAId,
            mode: .quickNote,
            generatedAt: now.addingTimeInterval(-3600 * 3 + 10),
            content: StructuredNoteContent(
                suggestedTitle: "日本旅行视频开头转场灵感",
                summaryOrShortNote: "咖啡杯上升的蒸汽可无缝衔接北海道温泉镜头，放在日本旅行视频开头前 5 秒增强代入感。",
                backgroundPoints: [],
                keyPoints: [],
                decisions: [],
                chapters: [
                    NoteChapter(
                        title: "手冲咖啡蒸汽与北海道温泉镜头衔接",
                        startMs: 0,
                        endMs: 9200,
                        summary: "观察到手冲咖啡杯冒起的蒸汽形态，可与北海道温泉升腾热气做同构无缝转场。"
                    ),
                    NoteChapter(
                        title: "开场黄金前 5 秒位置编排",
                        startMs: 9200,
                        endMs: 18000,
                        summary: "将该蒸汽转场放在日本旅行视频正片开头前 5 秒，快速建立视觉代入感。"
                    )
                ]
            ),
            origin: .ai
        )
        let noteA = Note(
            id: noteAId,
            recordingId: recAId,
            mode: .quickNote,
            suggestedMode: .quickNote,
            projectName: "日本旅行视频企划",
            editedAt: now.addingTimeInterval(-3600 * 3 + 10),
            currentRevisionId: revAId
        )

        // 2. 场景 B｜会后整理个人下一步（PRD 1.4, 4.6, 7.2, A12-A14, A22-A26）
        let recBId = UUID()
        let recBFileName = "demo_meeting.wav"
        _ = audioService.ensurePlayableDemoAudioFile(named: recBFileName, durationSeconds: 36)

        let recBCreatedAt = now.addingTimeInterval(-1800)
        let recB = Recording(
            id: recBId,
            title: "科研栏目选题与分镜推进会",
            createdAt: recBCreatedAt,
            recordedTimeZoneIdentifier: tz.identifier,
            duration: 36,
            localAudioFileName: recBFileName,
            language: "zh-CN",
            processingStatus: .completed
        )

        let segsB: [TranscriptSegment] = [
            TranscriptSegment(
                id: "seg_01",
                recordingId: recBId,
                startMs: 0,
                endMs: 7000,
                text: "我们先定一下科研栏目首期的方向，今天大家一致确认首期围绕真实研究过程展开，优先上线。",
                speakerId: "spk_0",
                speakerName: "Dustin"
            ),
            TranscriptSegment(
                id: "seg_02",
                recordingId: recBId,
                startMs: 7000,
                endMs: 14000,
                text: "那明天 15:00 到 16:00 我们开个分镜评审会，把镜头节奏过一遍。",
                speakerId: "spk_0",
                speakerName: "Dustin"
            ),
            TranscriptSegment(
                id: "seg_03",
                recordingId: recBId,
                startMs: 14000,
                endMs: 21000,
                text: "好的，我这边本周五之前提交分镜初稿。",
                speakerId: "me",
                speakerName: "我"
            ),
            TranscriptSegment(
                id: "seg_04",
                recordingId: recBId,
                startMs: 21000,
                endMs: 28000,
                text: "另外还需要把过往科研案例参考片整理一下。至于配乐方案，我们下周找时间再细聊。",
                speakerId: "spk_1",
                speakerName: "Max"
            ),
            TranscriptSegment(
                id: "seg_05",
                recordingId: recBId,
                startMs: 28000,
                endMs: 36000,
                text: "封面和视觉包装这块，小王周五交初稿就行。",
                speakerId: "spk_2",
                speakerName: "Lucas"
            )
        ]

        let noteBId = UUID()
        let revBId = UUID()
        let revB = NoteRevision(
            id: revBId,
            noteId: noteBId,
            mode: .meetingNote,
            generatedAt: now.addingTimeInterval(-1700),
            content: StructuredNoteContent(
                suggestedTitle: "科研栏目选题与分镜推进会",
                summaryOrShortNote: "讨论科研栏目首期方向与分镜推进分工。",
                backgroundPoints: ["围绕个人创作者科研科普栏目规划首期内容"],
                keyPoints: ["科研栏目优先上线", "视觉与配乐分阶段跟进"],
                decisions: ["首期围绕真实研究过程展开"],
                chapters: [
                    NoteChapter(
                        title: "确认科研栏目首期选题方向",
                        startMs: 0,
                        endMs: 7000,
                        summary: "全员一致确认首期围绕真实研究过程展开，并作为优先上线项目推进。"
                    ),
                    NoteChapter(
                        title: "分镜评审会议排期与初稿节点",
                        startMs: 7000,
                        endMs: 21000,
                        summary: "约定次日 15:00-16:00 召开分镜评审会过镜头节奏，并明确本周五前提交分镜初稿。"
                    ),
                    NoteChapter(
                        title: "参考片整理、配乐与视觉包装分工",
                        startMs: 21000,
                        endMs: 36000,
                        summary: "安排整理过往科研案例参考片；配乐方案留待下周细聊；封面与视觉包装由小王周五交初稿。"
                    )
                ]
            ),
            origin: .ai
        )
        let noteB = Note(
            id: noteBId,
            recordingId: recBId,
            mode: .meetingNote,
            suggestedMode: .meetingNote,
            projectName: "科研栏目首期",
            editedAt: now.addingTimeInterval(-1700),
            currentRevisionId: revBId
        )

        // 构建覆盖 PRD 4.6 全部典型规则的 ActionDrafts
        let rawDraftsB: [ActionDraft] = [
            // 1) 明确起止时间的会议 -> Apple 日历（A12）
            ActionDraft(
                recordingId: recBId,
                revisionId: revBId,
                kind: .event,
                description: "分镜评审会",
                owner: "本人",
                ownership: .selfOwner,
                originalDateText: "明天 15:00 到 16:00",
                datePrecision: .exactTime,
                timeZoneIdentifier: tz.identifier,
                sourceSegmentIds: ["seg_02"],
                evidenceQuote: "那明天 15:00 到 16:00 我们开个分镜评审会，把镜头节奏过一遍。",
                proposedDestination: .calendar
            ),
            // 2) 只有截止日期的任务 -> Apple 提醒事项，保留日期精度不造具体时刻（A14, A23）
            ActionDraft(
                recordingId: recBId,
                revisionId: revBId,
                kind: .task,
                description: "提交分镜初稿",
                owner: "本人",
                ownership: .selfOwner,
                originalDateText: "本周五之前",
                datePrecision: .dateOnly,
                timeZoneIdentifier: tz.identifier,
                sourceSegmentIds: ["seg_03"],
                evidenceQuote: "好的，我这边本周五之前提交分镜初稿。",
                proposedDestination: .reminders
            ),
            // 3) 无明确负责人与无截止日期的任务 -> 提示负责人未明确，建议 Markdown（A06, A30）
            ActionDraft(
                recordingId: recBId,
                revisionId: revBId,
                kind: .task,
                description: "整理过往科研案例参考片",
                owner: "未明确",
                ownership: .uncertain,
                originalDateText: nil,
                datePrecision: .none,
                timeZoneIdentifier: tz.identifier,
                sourceSegmentIds: ["seg_04"],
                evidenceQuote: "另外还需要把过往科研案例参考片整理一下。",
                proposedDestination: .markdown,
                needsConfirmation: true,
                confirmationReasons: ["未听到明确负责人，请核对是否由本人执行"]
            ),
            // 4) 时间模糊事项 -> 保留待确认，禁止静默写入日历（A13）
            ActionDraft(
                recordingId: recBId,
                revisionId: revBId,
                kind: .event,
                description: "沟通配乐方案",
                owner: "本人",
                ownership: .selfOwner,
                originalDateText: "下周找时间",
                datePrecision: .ambiguous,
                timeZoneIdentifier: tz.identifier,
                sourceSegmentIds: ["seg_04"],
                evidenceQuote: "至于配乐方案，我们下周找时间再细聊。",
                proposedDestination: .calendar,
                needsConfirmation: true
            ),
            // 5) 明确由他人负责 -> 仅作为上下文保留，不默认创建本人任务（A26）
            ActionDraft(
                recordingId: recBId,
                revisionId: revBId,
                kind: .task,
                description: "交封面和视觉包装初稿",
                owner: "小王",
                ownership: .other,
                originalDateText: "周五",
                datePrecision: .dateOnly,
                timeZoneIdentifier: tz.identifier,
                sourceSegmentIds: ["seg_05"],
                evidenceQuote: "封面和视觉包装这块，小王周五交初稿就行。",
                proposedDestination: .local,
                needsConfirmation: true
            )
        ]

        let validatedDraftsB = rawDraftsB.map { draft in
            RelativeDateAndActionValidator.validateAndNormalize(
                draft: draft,
                segments: segsB,
                recordingCreatedAt: recBCreatedAt,
                recordingTimeZone: tz,
                preferences: preferences
            )
        }

        recordings = [recB, recA]
        segmentsByRecording[recAId] = segsA
        segmentsByRecording[recBId] = segsB
        notesByRecording[recAId] = noteA
        notesByRecording[recBId] = noteB
        revisionsByNote[noteAId] = [revA]
        revisionsByNote[noteBId] = [revB]
        actionDraftsByRecording[recAId] = []
        actionDraftsByRecording[recBId] = validatedDraftsB
    }
}
