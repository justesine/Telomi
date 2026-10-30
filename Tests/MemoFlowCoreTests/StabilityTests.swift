import XCTest
@testable import MemoFlowCore

final class StabilityTests: XCTestCase {
    func testLongRecordingChunkCoverageIncludesShortTail() throws {
        for duration in [0.25, 45.0, 45.1, 2949.676] {
            let ranges = try ASRAndLLMService.chunkRanges(duration: duration)
            XCTAssertEqual(ranges.first?.lowerBound, 0)
            XCTAssertEqual(ranges.last?.upperBound, duration)
            for (index, range) in ranges.enumerated() {
                XCTAssertGreaterThan(range.upperBound - range.lowerBound, 0)
                XCTAssertLessThanOrEqual(range.upperBound - range.lowerBound, 45)
                if index > 0 { XCTAssertEqual(ranges[index - 1].upperBound, range.lowerBound) }
            }
        }
        XCTAssertEqual(try ASRAndLLMService.chunkRanges(duration: 2949.676).count, 66)
        XCTAssertThrowsError(try ASRAndLLMService.chunkRanges(duration: .infinity))
    }

    func testAppleSpeechRetryRangesCoverEverySecond() throws {
        let ranges = try ASRAndLLMService.appleSpeechRetryRanges(duration: 45)
        XCTAssertEqual(ranges, [0..<15, 15..<30, 30..<45])
        let tail = try ASRAndLLMService.appleSpeechRetryRanges(duration: 14.676)
        XCTAssertEqual(tail, [0..<14.676])
        XCTAssertThrowsError(try ASRAndLLMService.appleSpeechRetryRanges(duration: 46))
    }

    func testSparseLongTranscriptCannotBeMarkedComplete() throws {
        let recording = Recording(title: "长录音", duration: 2949.676, localAudioFileName: "source.m4a")
        let first = TranscriptSegment(recordingId: recording.id, startMs: 64000, endMs: 70000, text: "录音开始")
        let last = TranscriptSegment(recordingId: recording.id, startMs: 2800000, endMs: 2805000, text: "录音结束")
        XCTAssertThrowsError(try AudioSourceValidation.validateSegments([first, last], recording: recording))
        let middle = TranscriptSegment(recordingId: recording.id, startMs: 1400000, endMs: 1405000,
            text: String(repeating: "会议内容。", count: 100))
        XCTAssertNoThrow(try AudioSourceValidation.validateSegments([first, middle, last], recording: recording))
    }

    func testLocalWhisperParserRejectsZeroLengthAndClampsTail() throws {
        let recording = Recording(title: "识别", duration: 2, localAudioFileName: "source.wav")
        let data = Data(#"{"transcription":[{"offsets":{"from":0,"to":0},"text":"伪句"},{"offsets":{"from":500,"to":2500},"text":"实际语音"}]}"#.utf8)
        let segments = try ASRAndLLMService.parseWhisperTranscriptData(data, recording: recording)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].startMs, 500)
        XCTAssertEqual(segments[0].endMs, 2000)
        XCTAssertEqual(segments[0].text, "实际语音")
        XCTAssertThrowsError(try ASRAndLLMService.parseWhisperTranscriptData(Data("{}".utf8), recording: recording))
        XCTAssertFalse(ASREngineMode.localWhisper.sendsAudioToCloud)
        XCTAssertTrue(ASREngineMode.openAICompatible.sendsAudioToCloud)
    }

    func testEndpointAndCredentialIsolation() throws {
        let keys = KeychainService()
        XCTAssertNotEqual(keys.credentialAccount(.llmAPIKey, endpoint: "https://api.deepseek.com/v1"),
                          keys.credentialAccount(.llmAPIKey, endpoint: "https://api.moonshot.cn/v1"))
        XCTAssertNotEqual(keys.credentialAccount(.asrAPIKey, endpoint: "https://example.com/v1"),
                          keys.credentialAccount(.llmAPIKey, endpoint: "https://example.com/v1"))
        XCTAssertEqual(keys.credentialAccount(.llmAPIKey, endpoint: "https://example.com/v1/"),
                       keys.credentialAccount(.llmAPIKey, endpoint: "https://example.com/v1"))
        XCTAssertThrowsError(try ASRAndLLMService.endpoint(baseURL: "http://example.com", path: "models"))
        XCTAssertThrowsError(try ASRAndLLMService.endpoint(baseURL: "https://example.com?key=secret", path: "models"))
        XCTAssertEqual(try ASRAndLLMService.endpoint(baseURL: "https://example.com/v1/", path: "chat/completions").path, "/v1/chat/completions")
    }

    @MainActor
    func testRecoveryPreservesAudioAndBookmarksWithoutCloudProcessing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = AudioRecorderAndPlayerService(recordingsDirectory: root.appendingPathComponent("audio"))
        let id = UUID()
        let name = "rec_\(id.uuidString).m4a"
        let url = audio.ensurePlayableDemoAudioFile(named: name, durationSeconds: 2)
        let before = try AudioSourceValidation.fingerprint(url)
        let mark = RecordingMark(startMs: 1000)
        let journal = AudioRecorderAndPlayerService.RecordingJournal(id: id, fileName: name, createdAt: Date(), marks: [mark])
        let journalURL = audio.recordingsDirectoryURL.appendingPathComponent("active-recording.json")
        try JSONEncoder().encode(journal).write(to: journalURL)
        let store = MemoFlowStore(audioService: audio, customStorageURL: root.appendingPathComponent("state.json"))
        let recovered = try XCTUnwrap(store.recordings.first { $0.id == id })
        XCTAssertEqual(recovered.marks, [mark])
        XCTAssertEqual(recovered.processingStatus, .savedPendingTranscription)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
        XCTAssertEqual(before, try AudioSourceValidation.fingerprint(url))
    }

    @MainActor
    func testHighlightPersistenceSearchAndTranscriptExport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("state.json")
        let store = MemoFlowStore(customStorageURL: storage)
        let recording = Recording(title: "标记测试", duration: 60, localAudioFileName: "fixture.wav")
        let segment = TranscriptSegment(recordingId: recording.id, startMs: 12000, endMs: 15000, text: "来源原话")
        store.recordings = [recording]
        store.setHighlight(recordingId: recording.id, segment: segment, note: "手动批注关键词")
        let reloaded = MemoFlowStore(customStorageURL: storage)
        XCTAssertEqual(reloaded.recordings.first?.marks?.count, 1)
        XCTAssertEqual(reloaded.searchRecordings(query: "批注关键词", on: .distantPast).count, 1)
        let exported = MarkdownExporterService.renderTranscript(recording: reloaded.recordings[0], segments: [segment])
        XCTAssertTrue(exported.contains("手动批注关键词"))
        XCTAssertTrue(exported.contains("00:12"))
        reloaded.setHighlight(recordingId: recording.id, segment: segment, note: nil)
        XCTAssertEqual(reloaded.recordings[0].marks?.count, 0)
    }
    func testConcurrentTerminalCallbacksResolveExactlyOnce() async throws {
        for _ in 0..<100 {
            let completion = SpeechRequestCompletion<Int>()
            let value: Int = try await withCheckedThrowingContinuation { continuation in
                XCTAssertTrue(completion.install(continuation))
                DispatchQueue.concurrentPerform(iterations: 20) { index in
                    completion.resolve(.success(index))
                }
            }
            XCTAssertTrue((0..<20).contains(value))
        }
    }

    func testCancellationBeforeInstallationAndReentrantCleanup() async {
        let completion = SpeechRequestCompletion<Int>()
        completion.resolve(.failure(CancellationError()))
        // Speech can synchronously call back while cancel() is being called.
        completion.onFinish { completion.resolve(.success(99)) }
        do {
            let _: Int = try await withCheckedThrowingContinuation { continuation in
                XCTAssertFalse(completion.install(continuation))
            }
            XCTFail("Cancellation must not become an empty successful transcript")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testSuccessThenErrorKeepsFirstTerminalResult() async throws {
        let completion = SpeechRequestCompletion<Int>()
        let value: Int = try await withCheckedThrowingContinuation { continuation in
            _ = completion.install(continuation)
            completion.onFinish { completion.resolve(.failure(CancellationError())) }
            completion.resolve(.success(42))
            completion.resolve(.failure(ProcessingPipelineError.emptyTranscription))
        }
        XCTAssertEqual(value, 42)
    }

    func testUnrecognizedSpeakerDoesNotInventPeopleOrMe() {
        let segment = TranscriptSegment(recordingId: UUID(), startMs: 0, endMs: 1000, text: "原话")
        let result = ASRAndLLMService.shared.applySpeakerDiarizationAndNicknames(
            segments: [segment, segment, segment], theme: .strangerThings, userVoiceProfile: UserVoiceProfile())
        XCTAssertTrue(result.allSatisfy { $0.speakerId == nil && $0.speakerName == nil })
    }

    func testMappingAndTimestampsRejectWrongRecordingAndOutOfBounds() throws {
        let recording = Recording(title: "测试", duration: 2949.676, localAudioFileName: "import.m4a")
        let valid = TranscriptSegment(id: "last", recordingId: recording.id, startMs: 2940000, endMs: 2949676, text: "最后一段")
        XCTAssertNoThrow(try AudioSourceValidation.validateSegments([valid], recording: recording))
        var wrong = valid
        wrong.recordingId = UUID()
        XCTAssertThrowsError(try AudioSourceValidation.validateSegments([wrong], recording: recording))
        wrong = valid; wrong.endMs = 3000000
        XCTAssertThrowsError(try AudioSourceValidation.validateSegments([wrong], recording: recording))
        XCTAssertThrowsError(try AudioSourceValidation.validateSegments([valid, valid], recording: recording))
        var badMapping = recording
        badMapping.localAudioFileName = "rec_\(UUID().uuidString).m4a"
        XCTAssertThrowsError(try AudioSourceValidation.validateMapping(
            fileURL: URL(fileURLWithPath: "/tmp/\(badMapping.localAudioFileName)"), recording: badMapping))
    }

    func testTextOnlyTimestampsAreEstimatedAndBoundedByChunk() throws {
        let data = Data(#"{"text":"第一句。第二句。第三句。第四句。"}"#.utf8)
        let segments = try ASRAndLLMService.shared.parseASRResponseData(data, recordingId: UUID(), totalDuration: 1.5)
        XCTAssertEqual(segments.count, 4)
        XCTAssertTrue(segments.allSatisfy { $0.timingIsEstimated == true && $0.startMs < $0.endMs && $0.endMs <= 1500 })
        let invalid = Data(#"{"segments":[{"start":-5,"end":2,"text":"无效"}]}"#.utf8)
        XCTAssertThrowsError(try ASRAndLLMService.shared.parseASRResponseData(invalid, recordingId: UUID(), totalDuration: 45))
    }

    @MainActor
    func testSearchIgnoresSelectedDateAndIncludesCurrentNoteFields() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoFlowStore(customStorageURL: root.appendingPathComponent("state.json"))
        XCTAssertTrue(store.audioService.recordingsDirectoryURL.path.hasPrefix(root.path))
        let recording = Recording(title: "旧录音", createdAt: Date(timeIntervalSince1970: 0), duration: 10, localAudioFileName: "old.m4a")
        let noteID = UUID()
        let revision = NoteRevision(noteId: noteID, mode: .quickNote,
            content: StructuredNoteContent(suggestedTitle: "笔记", summaryOrShortNote: "正文", keyPoints: ["只出现在要点里的关键词"]), origin: .userEdited)
        store.recordings = [recording]
        store.notesByRecording[recording.id] = Note(id: noteID, recordingId: recording.id, mode: .quickNote, currentRevisionId: revision.id)
        store.revisionsByNote[noteID] = [revision]
        XCTAssertEqual(store.searchRecordings(query: "关键词", on: Date()).first?.id, recording.id)
        XCTAssertTrue(store.searchRecordings(query: " ", on: Date()).isEmpty)
        XCTAssertTrue(store.saveToDisk())
        let reloaded = MemoFlowStore(customStorageURL: root.appendingPathComponent("state.json"))
        XCTAssertEqual(reloaded.recordings, store.recordings)
    }
}
