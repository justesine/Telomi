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
    @Published public var processingConsent: ProcessingConsent = ProcessingConsent()
    @Published public var processingJobsByRecording: [UUID: ProcessingJob] = [:]
    @Published public var preferences: MemoFlowPreferences = MemoFlowPreferences()

    // MARK: - UI State
    @Published public var pendingConsentRecordingId: UUID?
    @Published public var pendingConsentMode: NoteMode = .quickNote
    private var pendingConsentRetranscribe = false
    @Published public var lastBannerFeedback: String?
    @Published public var knowledgeStatus: String = "选择知识库并开启背景辅助后，将在本机建立索引。"
    @Published public var isRefreshingKnowledge = false
    private let knowledgeService = ObsidianKnowledgeService()
    private var activePipelineRecordingIds = Set<UUID>()

    public func bindObsidianVault(_ url: URL) {
        do {
            let bookmark = try VaultAccess.bookmark(for: url)
            preferences.obsidianVaultBookmark = bookmark
            preferences.obsidianVaultRootPath = url.path
            saveToDisk()
            knowledgeStatus = "知识库已连接。开启背景辅助后刷新。"
            Task { await refreshKnowledge() }
        } catch { knowledgeStatus = "连接失败：\(error.localizedDescription)" }
    }

    public func disconnectObsidianVault() {
        preferences.knowledgeContextEnabled = false
        preferences.obsidianVaultBookmark = nil
        preferences.obsidianVaultRootPath = nil
        preferences.autoExportToObsidianOnComplete = false
        saveToDisk()
        knowledgeStatus = "已断开连接；历史笔记中的参考记录仍保留。"
        Task { await knowledgeService.clear() }
    }

    public func refreshKnowledge() async {
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

        // 检查云处理授权偏好（PRD R12 & A28）
        if preferences.asrEngineMode == .appleOnDevice && (KeychainService.shared.readKey(for: .llmAPIKey, endpoint: preferences.llmBaseURL) ?? "").isEmpty {
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

    public func runProcessingPipeline(
        for recordingId: UUID,
        mode: NoteMode,
        forceRetranscribe: Bool = false,
        cloudConsentGranted: Bool = false
    ) async {
        guard let idx = recordings.firstIndex(where: { $0.id == recordingId }) else { return }
        var recording = recordings[idx]
        let needsCloud = preferences.asrEngineMode != .appleOnDevice ||
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
                recordings[currentIndex].transcriptSource = TranscriptSource(fileName: recording.localAudioFileName,
                    sha256: fingerprint, audioDuration: duration,
                    engine: preferences.asrEngineMode == .appleOnDevice ? "Apple Speech · on-device" : preferences.asrModelName,
                    completedAt: Date())
                saveToDisk()
            }

            // 阶段 ④：AI 整理与有证据的行动提取
            guard pipelinePreferences == preferences, consentAtStart == processingConsent,
                  recordings.contains(where: { $0.id == recordingId }) else {
                throw ProcessingPipelineError.audioProcessingFailed("设置、授权或记录已变化，处理已停止。请重新开始")
            }
            updateRecordingStatus(recordingId, status: .organizing, failureReason: nil)
            let revisionId = UUID()
            let llmKey = KeychainService.shared.readKey(for: .llmAPIKey, endpoint: preferences.llmBaseURL)
            let knowledgePreferences = preferences
            let references = (llmKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? [] : await knowledgeContext(query: segments.map(\.text).joined(separator: "\n"))
            let permittedReferences = knowledgePreferences == preferences && preferences.knowledgeContextEnabled ? references : []
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
                knowledgeReferences: permittedReferences
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

        let newRevision = NoteRevision(
            id: revisionId,
            noteId: noteId,
            mode: requestedMode,
            generatedAt: Date(),
            content: output.noteContent,
            origin: .ai,
            previousRevisionId: prevRevId
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
        projectName: String?
    ) {
        if let idx = recordings.firstIndex(where: { $0.id == recordingId }) {
            recordings[idx].title = newTitle
        }
        guard var note = notesByRecording[recordingId] else { return }
        let newRev = NoteRevision(
            noteId: note.id,
            mode: note.mode,
            generatedAt: Date(),
            content: newContent,
            origin: .userEdited,
            previousRevisionId: note.currentRevisionId
        )
        var revs = revisionsByNote[note.id] ?? []
        revs.append(newRev)
        revisionsByNote[note.id] = revs

        note.currentRevisionId = newRev.id
        note.editedAt = Date()
        let trimmedProject = projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
        note.projectName = (trimmedProject?.isEmpty == true) ? nil : trimmedProject
        if let validProj = note.projectName, !preferences.knownProjectNames.contains(validProj) {
            preferences.knownProjectNames.append(validProj)
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
        destinationPath: String? = nil
    ) {
        let confirmedIds = (confirmedActionsByRecording[recordingId] ?? []).map(\.id)
        let exportRecord = MarkdownExport(
            recordingId: recordingId,
            confirmedActionIds: confirmedIds,
            createdAt: Date(),
            shareResult: result,
            destinationPath: destinationPath
        )
        var list = markdownExportsByRecording[recordingId] ?? []
        list.append(exportRecord)
        markdownExportsByRecording[recordingId] = list
        saveToDisk()
    }

    public func hasCompletedMarkdownExport(for recordingId: UUID) -> Bool {
        (markdownExportsByRecording[recordingId] ?? []).contains(where: { $0.shareResult == .completed })
    }

    /// 一键将当前录音的整理结果写入已授权的 Obsidian 笔记库（PRD R15）
    @discardableResult
    public func saveNoteDirectlyToObsidian(for recordingId: UUID) throws -> (fileURL: URL, obsidianOpenURL: URL?) {
        guard let rec = recordings.first(where: { $0.id == recordingId }),
              let note = notesByRecording[recordingId],
              let rev = currentRevision(for: recordingId) else {
            throw NSError(domain: "MemoFlowObsidian", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到可导出的笔记版本，请先完成转写整理。"])
        }
        guard let vaultRoot = preferences.obsidianVaultRootPath, !vaultRoot.isEmpty else {
            throw NSError(domain: "MemoFlowObsidian", code: 400, userInfo: [NSLocalizedDescriptionKey: "尚未选择 Obsidian 笔记库文件夹，请先在设置或弹窗中选择目录。"])
        }

        let confirmed = confirmedActionsByRecording[recordingId] ?? []
        let segs = segmentsByRecording[recordingId] ?? []
        let pending = actionDraftsByRecording[recordingId] ?? []
        let md = MarkdownExporterService.generateMarkdown(
            recording: rec,
            note: note,
            revision: rev,
            confirmedActions: confirmed,
            segments: segs,
            pendingDrafts: pending
        )

        let root = try VaultAccess.resolve(preferences)
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        let res = try MarkdownExporterService.writeDirectlyToObsidianVault(
            recording: rec,
            markdownContent: md,
            vaultRootPath: root.path,
            subfolder: preferences.obsidianTargetSubfolder,
            title: MarkdownExporterService.exportTitle(recording: rec, revision: rev)
        )
        recordMarkdownExportResult(for: recordingId, result: .completed, destinationPath: res.fileURL.path)
        lastBannerFeedback = "已写入 Obsidian：\(res.fileURL.lastPathComponent)"
        return res
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
            self.processingConsent = snap.processingConsent
            self.processingJobsByRecording = snap.processingJobsByRecording
            self.preferences = snap.preferences
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
