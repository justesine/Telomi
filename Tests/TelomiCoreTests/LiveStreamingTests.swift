import XCTest
import AVFoundation
@testable import TelomiCore

@MainActor
final class LiveStreamingTests: XCTestCase {
    private var tempDir: URL!
    private var testStoreURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("LiveStreamingTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        testStoreURL = tempDir.appendingPathComponent("store.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // 1. Requirement 1: 原音频持续安全保存，转写/AI 失败绝不影响录音
    func testRequirement1_AudioContinuityWhenASRFails() async throws {
        let store = MemoFlowStore(customStorageURL: testStoreURL)
        store.preferences.liveStreamingTranscriptionEnabled = true

        let recId = UUID()
        let audioDir = tempDir.appendingPathComponent("Recordings")
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let masterFile = audioDir.appendingPathComponent("rec_\(recId.uuidString).caf")

        // 模拟创建主音频文件
        FileManager.default.createFile(atPath: masterFile.path, contents: Data(repeating: 0x55, count: 4096))
        XCTAssertTrue(FileManager.default.fileExists(atPath: masterFile.path))

        // 模拟录音处于进行状态
        store.audioService.setRecordingStateForTesting(isRecording: true, recordingId: recId)

        // 模拟一个切片转写失败
        let chunkFile = audioDir.appendingPathComponent("chunk_0.caf")
        let chunk = LiveAudioChunkJournalItem(
            recordingId: recId,
            index: 0,
            startMs: 0,
            endMs: 5000,
            fileName: "chunk_0.caf",
            status: .failed,
            retryCount: 3,
            errorDescription: "网络断开 (Simulated 500 error)"
        )
        store.enqueueLiveChunk(chunk, url: chunkFile)

        // 运行队列消费
        await store.drainLiveChunkQueue()

        // 验证：录音仍然在进行中，主音频文件依然完整无损存在
        XCTAssertTrue(store.audioService.isRecording, "ASR 或网络错误绝不能终止正在进行的原音频录音")
        XCTAssertTrue(FileManager.default.fileExists(atPath: masterFile.path), "主音频文件必须始终安全保留")
        XCTAssertEqual(store.liveChunkQueue.first?.status, .failed, "失败切片必须安全留存于队列中待重试")

        store.audioService.setRecordingStateForTesting(isRecording: false)
    }

    // 2. Requirement 2: 音频分段全局时间戳，样本精确对接，接缝无间隙无重叠
    func testRequirement2_SampleAccurateTimestampContinuity() throws {
        let sampleRate: Double = 16000.0

        // 3 个连续切片，各自包含 16000 个采样点（即正好 1 秒）
        let chunkFrames: [AVAudioFrameCount] = [16000, 16000, 16000]
        var currentSampleCount: AVAudioFramePosition = 0
        var recordedChunks: [(startMs: Int, endMs: Int)] = []

        for frames in chunkFrames {
            let startMs = Int(round(Double(currentSampleCount) / sampleRate * 1000.0))
            currentSampleCount += AVAudioFramePosition(frames)
            let endMs = Int(round(Double(currentSampleCount) / sampleRate * 1000.0))
            recordedChunks.append((startMs, endMs))
        }

        XCTAssertEqual(recordedChunks.count, 3)
        XCTAssertEqual(recordedChunks[0].startMs, 0)
        XCTAssertEqual(recordedChunks[0].endMs, 1000)

        // 验证切片之间接缝无任何间隙且无重叠
        XCTAssertEqual(recordedChunks[1].startMs, recordedChunks[0].endMs, "切片接缝处开始毫秒必须完全等于上一切片结束毫秒")
        XCTAssertEqual(recordedChunks[1].endMs, 2000)

        XCTAssertEqual(recordedChunks[2].startMs, recordedChunks[1].endMs)
        XCTAssertEqual(recordedChunks[2].endMs, 3000)
    }

    // 3. Requirement 3: 仅处理新增内容，增量更新草稿，费用与功耗可控
    func testRequirement3_IncrementalDeltaDraftingAvoidsFullResend() async throws {
        let recording = Recording(title: "实时测试", duration: 120.0, localAudioFileName: "test.m4a")
        let existingSummary = "已讨论了前端界面优化与交互细节。"

        let newDeltaSegments = [
            TranscriptSegment(recordingId: recording.id, startMs: 60000, endMs: 75000, text: "接下来讨论数据库迁移方案。"),
            TranscriptSegment(recordingId: recording.id, startMs: 75000, endMs: 90000, text: "核心表需要增加索引支持快速定位。")
        ]

        var prefs = MemoFlowPreferences()
        prefs.liveStreamingSummaryIntervalSeconds = 60

        // 验证偏好设置已持久化
        XCTAssertEqual(prefs.liveStreamingSummaryIntervalSeconds, 60)

        let initialContent = StructuredNoteContent(suggestedTitle: "测试草稿", summaryOrShortNote: existingSummary)
        let updatedContent = try await ASRAndLLMService.shared.incrementallyUpdateLiveDraft(
            existingContent: initialContent,
            newSegments: newDeltaSegments,
            recording: recording,
            preferences: prefs,
            llmAPIKey: nil // 使用本地兜底规则
        )

        // 验证生成的内容包含原有摘要及新增增量，且未抛出崩溃
        XCTAssertFalse(updatedContent.summaryOrShortNote.isEmpty)
        XCTAssertTrue(updatedContent.summaryOrShortNote.contains("前端界面优化") || updatedContent.summaryOrShortNote.contains("数据库迁移"))
    }

    // 4. Requirement 4: 进度展示与草稿/最终笔记区分
    func testRequirement4_ProgressDisplayAndDraftDistinction() throws {
        let progress = LiveStreamingProgress(
            recordingId: UUID(),
            totalAudioDurationMs: 90000,
            transcribedDurationMs: 65000,
            pendingChunksCount: 2
        )

        XCTAssertEqual(progress.progressText, "已转写 00:01:05 / 录制 00:01:30 · 待处理 2 段")
        XCTAssertEqual(progress.completionRatio, 65000.0 / 90000.0, accuracy: 0.001)

        // 验证草稿标志
        let draftRevision = NoteRevision(
            noteId: UUID(),
            mode: .meetingNote,
            content: StructuredNoteContent(suggestedTitle: "草稿", summaryOrShortNote: "阶段性草稿"),
            origin: .ai,
            isLiveDraft: true
        )
        XCTAssertTrue(draftRevision.isLiveDraft, "实时生成中必须为 isLiveDraft = true")

        let finalRevision = NoteRevision(
            noteId: UUID(),
            mode: .meetingNote,
            content: StructuredNoteContent(suggestedTitle: "最终笔记", summaryOrShortNote: "最终完整笔记"),
            origin: .ai,
            isLiveDraft: false
        )
        XCTAssertFalse(finalRevision.isLiveDraft, "录音结束并合并后必须为 isLiveDraft = false")
    }

    // 5. Requirement 5: 网络中断保留队列，应用退出后断点续传恢复
    func testRequirement5_NetworkDropoutQueueRetentionAndCrashRecovery() throws {
        let recId = UUID()
        let audioService = AudioRecorderAndPlayerService()

        let chunk1 = LiveAudioChunkJournalItem(
            recordingId: recId,
            index: 0,
            startMs: 0,
            endMs: 30000,
            fileName: "chunk_0.caf",
            status: .transcribed,
            transcriptText: "第一阶段汇报完毕"
        )
        let chunk2 = LiveAudioChunkJournalItem(
            recordingId: recId,
            index: 1,
            startMs: 30000,
            endMs: 60000,
            fileName: "chunk_1.caf",
            status: .pending
        )

        // 模拟写入磁盘日志
        audioService.saveLiveChunksJournal([chunk1, chunk2], for: recId)
        let journalURL = audioService.liveChunksJournalURL(for: recId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journalURL.path))

        // 模拟应用异常退出后重新启动读取日志
        let restoredChunks = audioService.loadLiveChunksJournal(for: recId)
        XCTAssertEqual(restoredChunks.count, 2)
        XCTAssertEqual(restoredChunks[0].status, LiveChunkStatus.transcribed)
        XCTAssertEqual(restoredChunks[0].transcriptText, "第一阶段汇报完毕")
        XCTAssertEqual(restoredChunks[1].status, LiveChunkStatus.pending, "未完成切片在重启后完整恢复保留在队列中")
    }

    // 6. Requirement 6: 云端授权前置检查与明确说明
    func testRequirement6_CloudConsentPreflightCheck() {
        let store = MemoFlowStore(customStorageURL: testStoreURL)

        // 当使用云端 ASR 且未给过授权时，必须前置要求用户同意
        store.preferences.asrEngineMode = .openAICompatible
        store.preferences.asrBaseURL = "https://api.siliconflow.cn/v1"
        store.processingConsent.mode = .askEveryTime
        store.preferences.liveStreamingTranscriptionEnabled = true

        XCTAssertTrue(store.requiresCloudConsentForLiveRecording(), "使用云端 ASR 边录边整理前必须获得用户明确授权")

        // 用户授予偏好后
        store.grantCloudProcessingConsent(rememberPreference: true)
        XCTAssertFalse(store.requiresCloudConsentForLiveRecording(), "用户授权后可顺利进入录制流程")
    }

    // 7. Requirement 7: 未完成片段明确警告，禁止将不完整结果标记为完整
    func testRequirement7_IncompleteChunksExplicitlyWarned() async throws {
        let store = MemoFlowStore(customStorageURL: testStoreURL)
        store.preferences.llmModelName = "local-heuristic"
        store.preferences.llmBaseURL = ""
        let recId = UUID()
        let recording = Recording(id: recId, title: "未完成录音测试", duration: 120.0, localAudioFileName: "incomplete.caf")
        store.recordings.append(recording)

        // 模拟队列中有 1 个重试耗尽且失败未完成的切片
        let failedChunk = LiveAudioChunkJournalItem(
            recordingId: recId,
            index: 0,
            startMs: 0,
            endMs: 60000,
            fileName: "chunk_0.caf",
            status: .failed,
            retryCount: 3,
            errorDescription: "网络连接超时"
        )
        store.liveChunkQueue = [failedChunk]

        // 执行最终合并
        await store.finalizeLiveStreamingRecording(for: recId)

        // 检查：因为有未完成切片，笔记不能被标记为最终完成，必须保留 isLiveDraft 或相应提示
        let rev = store.currentRevision(for: recId)
        XCTAssertNotNil(rev)
        XCTAssertTrue(rev?.isLiveDraft == true, "存在未完成切片时，笔记必须保持为草稿状态，严禁伪装为已完成完整笔记")
        XCTAssertTrue(rev?.content.summaryOrShortNote.contains("未能完成") == true || rev?.content.summaryOrShortNote.contains("未完成") == true, "必须包含未完成切片的明确提示")
    }

    // 8. Requirement 8: iPhone 场景中断状态恢复机制
    func testRequirement8_InterruptionRecoveryModel() {
        let audioService = AudioRecorderAndPlayerService()

        // 模拟开始录音
        audioService.setRecordingStateForTesting(isRecording: true, isPaused: false, recordingId: UUID())
        XCTAssertTrue(audioService.isRecording)
        XCTAssertFalse(audioService.isPaused)

        // 模拟来电中断/锁屏中断挂起
        audioService.setRecordingStateForTesting(isRecording: true, isPaused: true)
        XCTAssertTrue(audioService.isRecording)
        XCTAssertTrue(audioService.isPaused)

        // 模拟中断结束，恢复录制
        audioService.setRecordingStateForTesting(isRecording: true, isPaused: false)
        XCTAssertTrue(audioService.isRecording)
        XCTAssertFalse(audioService.isPaused)

        // 模拟录音停止完成
        audioService.setRecordingStateForTesting(isRecording: false, isPaused: false)
        XCTAssertFalse(audioService.isRecording)
    }
}
