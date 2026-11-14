import XCTest
import FluidAudio
@testable import TelomiCore

final class StabilityTests: XCTestCase {
    func testRealtimeFinalIdentityUsesReliableOverlapAndRejectsEstimatedTiming() {
        let recordingId = UUID()
        let turns = [
            TimedSpeakerSegment(speakerId: "speaker_0", embedding: [1, 0], startTimeSeconds: 0, endTimeSeconds: 5, qualityScore: 1),
            TimedSpeakerSegment(speakerId: "speaker_1", embedding: [0, 1], startTimeSeconds: 5, endTimeSeconds: 10, qualityScore: 1)
        ]
        let segments = [
            TranscriptSegment(recordingId: recordingId, startMs: 0, endMs: 4000, text: "mine"),
            TranscriptSegment(recordingId: recordingId, startMs: 5000, endMs: 9000, text: "other"),
            TranscriptSegment(recordingId: recordingId, startMs: 0, endMs: 4000, text: "estimated", timingIsEstimated: true)
        ]
        let identified = VoiceIdentityService.identify(segments: segments, turns: turns, reference: [1, 0])
        XCTAssertEqual(identified[0].speakerId, "me")
        XCTAssertEqual(identified[1].speakerId, "local:speaker_1")
        XCTAssertNil(identified[2].speakerId)
    }

    @MainActor
    func testRetranscriptionNameResolutionSurvivesThemeChangeAndStoreRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("state.json")
        let store = MemoFlowStore(customStorageURL: storage)
        var recording = Recording(title: "retranscribe", localAudioFileName: "audio.m4a")
        recording.speakerNicknameTheme = .interstellar
        recording.manualSpeakerNames = ["provider:7": "Alice"]
        store.recordings = [recording]
        XCTAssertTrue(store.saveToDisk())

        let reopened = MemoFlowStore(customStorageURL: storage)
        reopened.preferences.speakerNicknameTheme = .strangerThings
        let freshSegments = [
            TranscriptSegment(recordingId: recording.id, startMs: 0, endMs: 1000, text: "manual", speakerId: "provider:7"),
            TranscriptSegment(recordingId: recording.id, startMs: 1000, endMs: 2000, text: "theme", speakerId: "provider:8")
        ]
        let resolved = reopened.resolveSpeakerNames(freshSegments, recording: try XCTUnwrap(reopened.recordings.first))
        XCTAssertEqual(resolved.map(\.speakerName), ["Alice", "Cooper"])
    }
    func testRealVoiceProfileVectorRoundTripAndInvalidSimilarity() throws {
        var profile = UserVoiceProfile(sampleDuration: 12, sampleAudioFileName: "VoiceProfile/sample.m4a")
        profile.embedding = [0.6, 0.8]
        profile.embeddingModel = VoiceIdentityService.modelID
        let restored = try JSONDecoder().decode(UserVoiceProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(restored, profile)
        XCTAssertEqual(VoiceIdentityService.similarity([0.6, 0.8], [0.6, 0.8]), 1, accuracy: 0.001)
        XCTAssertLessThan(VoiceIdentityService.similarity([0, 0], [0, 0]), 0)
        XCTAssertLessThan(VoiceIdentityService.similarity([1], [1, 0]), 0)
    }

    @MainActor
    func testDeleteVoiceProfilePersistsAndRemovesOnlyProfileSample() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MemoFlowStore(customStorageURL: root.appendingPathComponent("state.json"))
        let sampleURL = store.audioService.audioFileURL(for: "VoiceProfile/sample.m4a")
        try FileManager.default.createDirectory(at: sampleURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("sample".utf8).write(to: sampleURL)
        var profile = UserVoiceProfile(sampleDuration: 12, sampleAudioFileName: "VoiceProfile/sample.m4a")
        profile.embedding = [1, 0]
        profile.embeddingModel = VoiceIdentityService.modelID
        store.preferences.userVoiceProfile = profile
        XCTAssertTrue(store.saveToDisk())
        store.deleteVoiceProfile()
        XCTAssertNil(store.preferences.userVoiceProfile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sampleURL.path))
        XCTAssertNil(MemoFlowStore(customStorageURL: root.appendingPathComponent("state.json")).preferences.userVoiceProfile)
    }

    @MainActor
    func testRecoveredRecordingRetainsCapturedTheme() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("state.json")
        let store = MemoFlowStore(customStorageURL: storage)
        store.preferences.speakerNicknameTheme = .strangerThings
        XCTAssertTrue(store.saveToDisk())
        let id = UUID()
        _ = store.audioService.ensurePlayableDemoAudioFile(named: "demo_recovered.wav", durationSeconds: 6)
        let journal = AudioRecorderAndPlayerService.RecordingJournal(id: id, fileName: "demo_recovered.wav", createdAt: Date(), speakerNicknameTheme: .interstellar)
        try JSONEncoder().encode(journal).write(to: store.audioService.recordingsDirectoryURL.appendingPathComponent("active-recording.json"))
        let restored = MemoFlowStore(customStorageURL: storage)
        XCTAssertEqual(restored.recordings.first(where: { $0.id == id })?.speakerNicknameTheme, .interstellar)
        let reopened = MemoFlowStore(customStorageURL: storage)
        XCTAssertEqual(reopened.recordings.first(where: { $0.id == id })?.speakerNicknameTheme, .interstellar)
    }
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

    func testLegacyDeepSeekModelMigrationPreservesCustomGateway() throws {
        let official = MemoFlowPreferences(llmModelName: "deepseek-chat")
        let upgraded = try JSONDecoder().decode(MemoFlowPreferences.self, from: JSONEncoder().encode(official))
        XCTAssertEqual(upgraded.llmModelName, "deepseek-flash")
        let reasoning = MemoFlowPreferences(llmModelName: "deepseek-reasoner")
        let upgradedReasoning = try JSONDecoder().decode(MemoFlowPreferences.self, from: JSONEncoder().encode(reasoning))
        XCTAssertEqual(upgradedReasoning.llmModelName, "deepseek-v4-pro")
        let gateway = MemoFlowPreferences(llmBaseURL: "https://example.com/v1", llmModelName: "deepseek-chat")
        let preserved = try JSONDecoder().decode(MemoFlowPreferences.self, from: JSONEncoder().encode(gateway))
        XCTAssertEqual(preserved.llmModelName, "deepseek-chat")
        let siliconFlow = MemoFlowPreferences(llmBaseURL: "https://api.siliconflow.cn/v1", llmModelName: "deepseek-ai/DeepSeek-V3")
        let upgradedSiliconFlow = try JSONDecoder().decode(MemoFlowPreferences.self, from: JSONEncoder().encode(siliconFlow))
        XCTAssertEqual(upgradedSiliconFlow.llmModelName, "deepseek-ai/DeepSeek-V4.1-Flash")
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

    func testSpeakerNamesFollowFirstUtteranceAndReserveManualNames() {
        let recordingId = UUID()
        let segments = [
            TranscriptSegment(recordingId: recordingId, startMs: 2000, endMs: 3000, text: "later", speakerId: "b"),
            TranscriptSegment(recordingId: recordingId, startMs: 0, endMs: 1000, text: "first", speakerId: "a", speakerName: "Speaker 1"),
            TranscriptSegment(recordingId: recordingId, startMs: 3000, endMs: 4000, text: "again", speakerId: "a"),
            TranscriptSegment(recordingId: recordingId, startMs: 4000, endMs: 5000, text: "manual", speakerId: "c", speakerName: "Dustin")
        ]
        let result = ASRAndLLMService.shared.applySpeakerDiarizationAndNicknames(
            segments: segments, theme: .strangerThings, userVoiceProfile: nil)
        XCTAssertEqual(result.map(\.speakerName), ["Lucas", "Max", "Max", "Dustin"])
        XCTAssertEqual(result.map(\.id), segments.map(\.id))
    }

    func testRecordingThemeSurvivesPersistenceAndPreferenceChanges() throws {
        var recording = Recording(title: "theme", localAudioFileName: "test.m4a")
        recording.speakerNicknameTheme = .interstellar
        let data = try JSONEncoder().encode(recording)
        let restored = try JSONDecoder().decode(Recording.self, from: data)
        var preferences = MemoFlowPreferences()
        preferences.speakerNicknameTheme = .strangerThings
        XCTAssertEqual(restored.speakerNicknameTheme, .interstellar)
        let segment = TranscriptSegment(recordingId: restored.id, startMs: 0, endMs: 1000, text: "hello", speakerId: "provider:0")
        let mapped = ASRAndLLMService.shared.applySpeakerDiarizationAndNicknames(
            segments: [segment], theme: try XCTUnwrap(restored.speakerNicknameTheme), userVoiceProfile: nil)
        XCTAssertEqual(mapped.first?.speakerName, "Cooper")
    }

    func testProviderSpeakerLabelsReachNicknameMappingWithoutClaimingSelf() throws {
        let data = Data(#"{"segments":[{"start":0,"end":1,"text":"hello","speaker":"me"}]}"#.utf8)
        let parsed = try ASRAndLLMService.shared.parseASRResponseData(data, recordingId: UUID(), totalDuration: 2)
        XCTAssertEqual(parsed.first?.speakerId, "provider:me")
        let mapped = ASRAndLLMService.shared.applySpeakerDiarizationAndNicknames(
            segments: parsed, theme: .interstellar, userVoiceProfile: nil)
        XCTAssertEqual(mapped.first?.speakerName, "Cooper")
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
