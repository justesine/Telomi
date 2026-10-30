import Foundation
import AVFoundation

/// 负责第②阶段（可靠本地 m4a 录音、暂停/继续、音频中断保护）与第①/④阶段（逐字稿跳转播放 + 行动证据区间切片回听）
@MainActor
public final class AudioRecorderAndPlayerService: NSObject, ObservableObject {

    // MARK: - Published Recording State (PRD R01-R03)
    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var currentRecordingDuration: TimeInterval = 0
    @Published public private(set) var waveformSamples: [Float] = Array(repeating: 0.08, count: 28)
    @Published public var interruptionAlertMessage: String?
    @Published public private(set) var recordingBookmarks: [RecordingMark] = []

    // MARK: - Published Playback State (PRD R06 & R23)
    @Published public private(set) var playingRecordingId: UUID?
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var currentPlaybackTimeMs: Int = 0
    @Published public private(set) var totalPlaybackDurationMs: Int = 0
    @Published public private(set) var activeEvidenceEndMs: Int?

    private var audioRecorder: AVAudioRecorder?
    private var activeRecordingId: UUID?
    private var activeRecordingFileName: String?
    private var activeRecordingCreatedAt: Date?

    private var audioPlayer: AVAudioPlayer?
    private var meterTimer: Timer?
    private var playbackTimer: Timer?
    private var interruptionObservers: [NSObjectProtocol] = []
    private var mediaServicesWereReset = false
    private var shouldResumeAfterInterruption = false

    public struct RecordingJournal: Codable {
        public let id: UUID
        public let fileName: String
        public let createdAt: Date
        public var marks: [RecordingMark]?
    }
    private var journalURL: URL { recordingsDirectoryURL.appendingPathComponent("active-recording.json") }

    public func addRecordingBookmark() {
        guard isRecording, let recorder = audioRecorder,
              let data = try? Data(contentsOf: journalURL),
              var journal = try? JSONDecoder().decode(RecordingJournal.self, from: data) else { return }
        let mark = RecordingMark(startMs: Int(max(0, recorder.currentTime) * 1000))
        journal.marks = recordingBookmarks + [mark]
        do {
            try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
            recordingBookmarks.append(mark)
        } catch { interruptionAlertMessage = "书签保存失败：\(error.localizedDescription)" }
    }

    /// A journal survives process termination; audio is never deleted during recovery.
    public func recoverInterruptedRecording() -> (RecordingJournal, TimeInterval)? {
        guard !isRecording, let data = try? Data(contentsOf: journalURL),
              let journal = try? JSONDecoder().decode(RecordingJournal.self, from: data) else { return nil }
        let url = audioFileURL(for: journal.fileName)
        guard journal.fileName == "rec_\(journal.id.uuidString).m4a",
              let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 else {
            interruptionAlertMessage = "发现未完成录音，原文件已保留，但暂时无法读取。请保留文件以便恢复。"
            return nil
        }
        return (journal, player.duration)
    }

    public func acknowledgeSavedRecording(id: UUID) {
        guard let data = try? Data(contentsOf: journalURL),
              let journal = try? JSONDecoder().decode(RecordingJournal.self, from: data), journal.id == id else { return }
        try? FileManager.default.removeItem(at: journalURL)
    }

    public let recordingsDirectoryURL: URL

    public init(recordingsDirectory: URL? = nil) {
        let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = recordingsDirectory ?? baseDir.appendingPathComponent("MemoFlowRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.recordingsDirectoryURL = dir
        super.init()
        setupAudioInterruptionObservers()
    }

    public func audioFileURL(for fileName: String) -> URL {
        recordingsDirectoryURL.appendingPathComponent(fileName)
    }

    // MARK: - Microphone Permission & Recording Lifecycle (PRD R01-R04, A01-A03, A11)

    public func requestMicrophonePermission() async -> Bool {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        #else
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .authorized { return true }
        return await AVCaptureDevice.requestAccess(for: .audio)
        #endif
    }

    public func startRecording() async throws -> (id: UUID, fileName: String, createdAt: Date) {
        guard !isRecording, !FileManager.default.fileExists(atPath: journalURL.path) else {
            throw NSError(domain: "MemoFlowAudio", code: 409,
                userInfo: [NSLocalizedDescriptionKey: "请先保存或恢复上一段录音，再开始新录音。"])
        }
        let hasPermission = await requestMicrophonePermission()
        guard hasPermission else {
            throw NSError(
                domain: "MemoFlowAudio",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "未获得麦克风权限，请在系统设置中允许 MemoFlow 访问麦克风。"]
            )
        }

        stopPlayback()

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // 支持锁屏与切后台持续录音（PRD R03 & A02，需配合 Info.plist UIBackgroundModes: audio）
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        #endif

        let id = UUID()
        let createdAt = Date()
        let fileName = "rec_\(id.uuidString).m4a"
        let fileURL = audioFileURL(for: fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord() else {
            throw NSError(domain: "MemoFlowAudio", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法创建录音文件"])
        }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: fileURL.path)
        #endif
        let journal = RecordingJournal(id: id, fileName: fileName, createdAt: createdAt)
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: journalURL.path)
        #endif

        guard recorder.record() else {
            // No recording session started. Clear only this attempt's journal so
            // a failed microphone activation cannot block every future take.
            try? FileManager.default.removeItem(at: journalURL)
            #if os(iOS)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            #endif
            throw NSError(
                domain: "MemoFlowAudio",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "无法启动系统音频录制会话，请检查是否有其他应用独占麦克风。"]
            )
        }

        self.audioRecorder = recorder
        self.activeRecordingId = id
        self.activeRecordingFileName = fileName
        self.activeRecordingCreatedAt = createdAt
        self.isRecording = true
        self.isPaused = false
        self.currentRecordingDuration = 0
        self.interruptionAlertMessage = nil
        self.mediaServicesWereReset = false
        self.shouldResumeAfterInterruption = false
        self.recordingBookmarks = []

        startMeterTimer()
        return (id, fileName, createdAt)
    }

    /// 暂停录音（PRD R02 & A03：暂停段不计入有效音频）
    public func pauseRecording() {
        guard isRecording, !isPaused, let recorder = audioRecorder else { return }
        shouldResumeAfterInterruption = false
        recorder.pause()
        currentRecordingDuration = recorder.currentTime
        isPaused = true
    }

    /// 继续录音（PRD R02 & A03）
    public func resumeRecording() {
        guard isRecording, isPaused, let recorder = audioRecorder else { return }
        guard !mediaServicesWereReset else {
            interruptionAlertMessage = "系统音频服务已重置，请先完成保存，再开始新录音。"
            return
        }
        do {
        #if os(iOS)
        try AVAudioSession.sharedInstance().setActive(true)
        #endif
        guard recorder.record() else {
            interruptionAlertMessage = "无法恢复麦克风，录音仍暂停。请重试或保存已有片段。"
            return
        }
        isPaused = false
        interruptionAlertMessage = nil
        } catch {
            interruptionAlertMessage = "恢复录音失败：\(error.localizedDescription)。已录片段保留。"
        }
    }

    /// 完成并保存本地录音（PRD R02, R04, R26：先落盘保存并返回真实时长）
    public func finishRecording() -> (id: UUID, fileName: String, createdAt: Date, duration: TimeInterval)? {
        guard let recorder = audioRecorder,
              let id = activeRecordingId,
              let fileName = activeRecordingFileName,
              let createdAt = activeRecordingCreatedAt else {
            return nil
        }

        let measuredDuration = max(currentRecordingDuration, recorder.currentTime)
        recorder.stop()
        let finalDuration = (try? AVAudioPlayer(contentsOf: recorder.url).duration) ?? measuredDuration
        stopMeterTimer()

        self.audioRecorder = nil
        self.activeRecordingId = nil
        self.activeRecordingFileName = nil
        self.activeRecordingCreatedAt = nil
        self.isRecording = false
        self.isPaused = false
        self.shouldResumeAfterInterruption = false
        self.currentRecordingDuration = 0
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        return (id, fileName, createdAt, finalDuration)
    }

    /// 为测试或演示生成一段真实可播放的本地静音/轻提示音音频文件（便于无麦克风环境下验证播放器与导出）
    public func ensurePlayableDemoAudioFile(named fileName: String, durationSeconds: Double = 15.0) -> URL {
        let url = audioFileURL(for: fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        // 生成标准单声道 16-bit PCM WAV 数据（AVAudioPlayer 原生支持直接播放与毫秒级跳转）
        let sampleRate = 16000
        let totalSamples = Int(Double(sampleRate) * max(2.0, durationSeconds))
        var pcmSamples = [Int16](repeating: 0, count: totalSamples)
        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            // 柔和的 440Hz 泛音脉冲，方便回听时感知到正在播放及时间轴位置
            let envelope = sin(t * 2.0 * .pi * 0.5) * 0.15
            let wave = sin(t * 2.0 * .pi * 440.0) * envelope
            pcmSamples[i] = Int16(max(-1.0, min(1.0, wave)) * 6000)
        }

        let dataSize = totalSamples * 2
        var wavData = Data()
        wavData.append("RIFF".data(using: .ascii)!)
        var chunkSize = UInt32(36 + dataSize).littleEndian
        wavData.append(Data(bytes: &chunkSize, count: 4))
        wavData.append("WAVEfmt ".data(using: .ascii)!)
        var subchunk1Size = UInt32(16).littleEndian
        var audioFormat = UInt16(1).littleEndian
        var numChannels = UInt16(1).littleEndian
        var sampleRateLE = UInt32(sampleRate).littleEndian
        var byteRate = UInt32(sampleRate * 2).littleEndian
        var blockAlign = UInt16(2).littleEndian
        var bitsPerSample = UInt16(16).littleEndian
        wavData.append(Data(bytes: &subchunk1Size, count: 4))
        wavData.append(Data(bytes: &audioFormat, count: 2))
        wavData.append(Data(bytes: &numChannels, count: 2))
        wavData.append(Data(bytes: &sampleRateLE, count: 4))
        wavData.append(Data(bytes: &byteRate, count: 4))
        wavData.append(Data(bytes: &blockAlign, count: 2))
        wavData.append(Data(bytes: &bitsPerSample, count: 2))
        wavData.append("data".data(using: .ascii)!)
        var subchunk2Size = UInt32(dataSize).littleEndian
        wavData.append(Data(bytes: &subchunk2Size, count: 4))
        pcmSamples.withUnsafeBufferPointer { ptr in
            wavData.append(UnsafeBufferPointer(
                start: UnsafeRawPointer(ptr.baseAddress)?.assumingMemoryBound(to: UInt8.self),
                count: dataSize
            ))
        }

        try? wavData.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Playback & Evidence Slice Playback (PRD R06, R23, A05, A22)

    /// 从指定毫秒位置开始播放（若传入 endMs，则播放到 endMs 自动暂停，实现「原话证据区间回听」）
    /// 仅对内置演示样本（demo_*.wav）按需生成演示波形，真实录音缺失时如实报告错误而不伪造音频文件。
    @Published public var lastPlaybackError: String?

    @discardableResult
    public func play(
        recording: Recording,
        startMs: Int = 0,
        endMs: Int? = nil,
        overrideFileURL: URL? = nil
    ) -> Bool {
        let url: URL
        if let overrideFileURL {
            url = overrideFileURL
        } else if recording.localAudioFileName.hasPrefix("demo_") {
            url = ensurePlayableDemoAudioFile(
                named: recording.localAudioFileName,
                durationSeconds: max(5.0, recording.duration)
            )
        } else {
            url = audioFileURL(for: recording.localAudioFileName)
        }

        guard !recording.localAudioFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              FileManager.default.fileExists(atPath: url.path) else {
            self.isPlaying = false
            self.lastPlaybackError = "当前设备未找到原音频文件（\(recording.localAudioFileName)），无法播放。"
            return false
        }

        do {
            if playingRecordingId != recording.id || audioPlayer == nil || audioPlayer?.url != url {
                audioPlayer?.stop()
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                self.audioPlayer = player
                self.playingRecordingId = recording.id
                self.totalPlaybackDurationMs = Int(max(recording.duration, player.duration) * 1000)
            }

            guard let player = audioPlayer else { return false }
            let safeMaxSeconds = max(0, player.duration - 0.05)
            let targetSeconds = max(0, min(safeMaxSeconds, Double(max(0, startMs)) / 1000.0))
            player.currentTime = targetSeconds
            self.currentPlaybackTimeMs = Int((targetSeconds * 1000).rounded())
            if let endMs, endMs > self.currentPlaybackTimeMs {
                self.activeEvidenceEndMs = min(Int((player.duration * 1000).rounded()), endMs)
            } else {
                self.activeEvidenceEndMs = nil
            }
            self.lastPlaybackError = nil
            player.play()
            self.isPlaying = true
            startPlaybackTimer()
            return true
        } catch {
            self.isPlaying = false
            self.lastPlaybackError = "音频播放失败：\(error.localizedDescription)"
            return false
        }
    }

    public func togglePlayPause(for recording: Recording) {
        if playingRecordingId == recording.id, let player = audioPlayer {
            if player.isPlaying {
                player.pause()
                isPlaying = false
                stopPlaybackTimer()
            } else {
                activeEvidenceEndMs = nil
                player.play()
                isPlaying = true
                startPlaybackTimer()
            }
        } else {
            play(recording: recording, startMs: 0, endMs: nil)
        }
    }

    public func seek(for recording: Recording, toMs: Int) {
        if playingRecordingId != recording.id || audioPlayer == nil {
            play(recording: recording, startMs: toMs, endMs: nil)
            return
        }
        guard let player = audioPlayer else { return }
        let targetSeconds = max(0, min(player.duration, Double(toMs) / 1000.0))
        player.currentTime = targetSeconds
        currentPlaybackTimeMs = toMs
        activeEvidenceEndMs = nil
    }

    public func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playingRecordingId = nil
        currentPlaybackTimeMs = 0
        activeEvidenceEndMs = nil
        stopPlaybackTimer()
    }

    // MARK: - Timers & Interruption Handling (PRD 4.3 & A11)

    private func startMeterTimer() {
        stopMeterTimer()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.audioRecorder, self.isRecording, !self.isPaused else { return }
                guard recorder.isRecording else {
                    self.isPaused = true
                    self.interruptionAlertMessage = "录音已停止接收声音，请继续录音或保存已有片段。"
                    return
                }
                recorder.updateMeters()
                self.currentRecordingDuration = recorder.currentTime
                let power = recorder.averagePower(forChannel: 0) // -160 ... 0 dB
                let normalized = max(0.06, min(1.0, (power + 55.0) / 55.0))
                var nextSamples = self.waveformSamples
                if !nextSamples.isEmpty {
                    nextSamples.removeFirst()
                }
                nextSamples.append(normalized)
                self.waveformSamples = nextSamples
            }
        }
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.audioPlayer else { return }
                self.currentPlaybackTimeMs = Int(player.currentTime * 1000)

                // 如果正在回听某条行动的原话证据区间，到达 endMs 时自动暂停（PRD R23）
                if let endLimit = self.activeEvidenceEndMs,
                   self.currentPlaybackTimeMs >= endLimit {
                    player.pause()
                    self.isPlaying = false
                    self.activeEvidenceEndMs = nil
                    self.stopPlaybackTimer()
                    return
                }

                if !player.isPlaying {
                    self.isPlaying = false
                    self.stopPlaybackTimer()
                }
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    /// The system can stop an audio recorder while the UI timer is suspended.
    /// Reconcile on foreground so a stopped session is never shown as recording.
    public func reconcileRecordingOnForeground() {
        guard isRecording, !isPaused, let recorder = audioRecorder, !recorder.isRecording else { return }
        currentRecordingDuration = max(currentRecordingDuration, recorder.currentTime)
        isPaused = true
        shouldResumeAfterInterruption = false
        interruptionAlertMessage = "录音已停止接收声音；已录片段仍保留。请点「继续录音」或完成保存。"
    }

    private func setupAudioInterruptionObservers() {
        #if os(iOS)
        interruptionObservers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                switch type {
                case .began:
                    let wasActivelyRecording = !self.isPaused
                    self.pauseRecording()
                    self.shouldResumeAfterInterruption = wasActivelyRecording
                    self.interruptionAlertMessage = "录音被系统音频/来电打断，已自动暂停并保护已录片段。你可以选择继续录音或直接保存。"
                case .ended:
                    let shouldResume = self.shouldResumeAfterInterruption
                    self.shouldResumeAfterInterruption = false
                    if shouldResume {
                        self.resumeRecording()
                        if !self.isPaused {
                            self.interruptionAlertMessage = "音频中断已结束，录音已自动继续。"
                        }
                    } else {
                        self.interruptionAlertMessage = "音频中断已结束；已录片段保留，可继续录音或完成保存。"
                    }
                @unknown default:
                    break
                }
            }
        })
        interruptionObservers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.shouldResumeAfterInterruption = false
                self.pauseRecording()
                self.interruptionAlertMessage = "麦克风或耳机已断开，录音已暂停。确认输入设备后可继续。"
            }
        })
        interruptionObservers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.mediaServicesWereReset = true
                self.shouldResumeAfterInterruption = false
                self.pauseRecording()
                self.interruptionAlertMessage = "系统音频服务已重置，请先保存已有录音，再开始新录音。"
            }
        })
        #endif
    }

    deinit {
        interruptionObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

extension AudioRecorderAndPlayerService: AVAudioRecorderDelegate {
    nonisolated public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.isRecording, self.audioRecorder === recorder else { return }
            self.isPaused = true
            self.interruptionAlertMessage = "录音会话已结束，请保存已有片段。"
        }
    }

    nonisolated public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.isRecording, self.audioRecorder === recorder else { return }
            self.pauseRecording()
            self.interruptionAlertMessage = "录音写入中断，原文件保留：\(error?.localizedDescription ?? "未知音频错误")"
        }
    }
}
