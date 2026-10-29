import SwiftUI
#if canImport(MemoFlowCore)
import MemoFlowCore
#endif

/// P02 录音室级录音弹窗（PRD 05.P02 & R01-R04 & R26）
public struct RecorderSheetView: View {
    @ObservedObject var store: MemoFlowStore
    @ObservedObject private var audioService: AudioRecorderAndPlayerService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMode: NoteMode
    @State private var simulateOfflineSave: Bool = false
    @State private var showingStopConfirmation: Bool = false
    @State private var errorMessage: String?

    public init(store: MemoFlowStore) {
        self.store = store
        self.audioService = store.audioService
        _selectedMode = State(initialValue: store.preferences.defaultNoteMode)
    }

    public var body: some View {
        ZStack {
            MFTheme.sheetBg.ignoresSafeArea()
            MFTheme.ambientTopGlow.ignoresSafeArea()

            VStack(spacing: 22) {
                topStatusBar
                modeSelectorCard
                Spacer(minLength: 10)
                studioWaveformStage
                alertSection
                if audioService.isRecording {
                    Button {
                        audioService.addRecordingBookmark()
                    } label: {
                        Label("记下这一刻 · \(audioService.recordingBookmarks.count)", systemImage: "bookmark")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("在当前录音位置保存时间戳书签")
                }
                Spacer(minLength: 10)
                offlineSimToggle
                controlButtons
            }
            .padding(24)
        }
        .focusEffectDisabled()
        .preferredColorScheme(store.preferences.appearanceTheme.colorScheme)
        .onAppear {
            if !audioService.isRecording {
                Task {
                    await beginRecordingNow()
                }
            }
        }
        .confirmationDialog(
            "确认结束并保存当前录音？",
            isPresented: $showingStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("结束并安全保存") {
                completeAndSaveRecording()
            }
            Button("继续录音", role: .cancel) {}
        } message: {
            Text("音频将首先保存在本地设备，随后根据你的授权偏好进行转写与整理。")
        }
    }

    private var topStatusBar: some View {
        let dotColor: Color = !audioService.isRecording
            ? MFTheme.textMuted
            : (audioService.isPaused ? MFTheme.warmAmber : MFTheme.coralRed)

        return HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 9, height: 9)
                    .shadow(color: dotColor.opacity(0.75), radius: 6)
                Text(statusTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(MFTheme.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
            )

            Spacer()

            if !audioService.isRecording {
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MFTheme.textSecondary)
            }
        }
    }

    private var modeSelectorCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(NoteMode.allCases, id: \.self) { mode in
                    let isSelected = (selectedMode == mode)
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                            selectedMode = mode
                        }
                    } label: {
                        Text(mode.displayTitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(isSelected ? Color.white : MFTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? MFTheme.iceBlue.opacity(0.24) : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(isSelected ? MFTheme.iceBlue.opacity(0.55) : Color.clear, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(MFTheme.recessedBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                    )
            )

            Text(selectedMode.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(MFTheme.textMuted)
        }
    }

    private var studioWaveformStage: some View {
        let barGradient = LinearGradient(
            colors: audioService.isPaused
                ? [MFTheme.warmAmber, MFTheme.warmAmber.opacity(0.55)]
                : [MFTheme.iceCyan, MFTheme.iceBlue],
            startPoint: .top,
            endPoint: .bottom
        )

        return VStack(spacing: 20) {
            Text(TimeFormatting.formatDuration(audioService.currentRecordingDuration))
                .font(.system(size: 52, weight: .bold, design: .monospaced))
                .foregroundStyle(MFTheme.textPrimary)
                .shadow(color: MFTheme.iceBlue.opacity(0.22), radius: 12)

            HStack(alignment: .center, spacing: 5) {
                ForEach(Array(audioService.waveformSamples.enumerated()), id: \.offset) { _, sample in
                    Capsule()
                        .fill(barGradient)
                        .frame(width: 5, height: max(8, CGFloat(sample) * 74))
                }
            }
            .frame(height: 82)
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .mfGlassCard(cornerRadius: 20, padding: 22, tint: MFTheme.iceBlue)
    }

    @ViewBuilder
    private var alertSection: some View {
        if let interruptMsg = audioService.interruptionAlertMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(MFTheme.warmAmber)
                Text(interruptMsg)
                    .font(.caption)
                    .foregroundStyle(MFTheme.textPrimary)
            }
            .mfGlassCard(cornerRadius: 12, padding: 10, tint: MFTheme.warmAmber)
        }

        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(MFTheme.coralRed)
                .multilineTextAlignment(.center)
        }
    }

    private var offlineSimToggle: some View {
        Toggle("模拟弱网/离线环境（验证「先安全保存·待联网转写」）", isOn: $simulateOfflineSave)
            .font(.system(size: 11))
            .foregroundStyle(MFTheme.textSecondary)
    }

    private var statusTitle: String {
        if !audioService.isRecording {
            return "准备就绪"
        }
        return audioService.isPaused ? "已暂停（暂停段不计入音频）" : "正在录音 · 实时声学采集中"
    }

    @ViewBuilder
    private var controlButtons: some View {
        if audioService.isRecording {
            HStack(spacing: 36) {
                Button {
                    if audioService.isPaused {
                        audioService.resumeRecording()
                    } else {
                        audioService.pauseRecording()
                    }
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                                )
                            Image(systemName: audioService.isPaused ? "play.fill" : "pause.fill")
                                .font(.title2)
                                .foregroundStyle(MFTheme.textPrimary)
                        }
                        Text(audioService.isPaused ? "继续录音" : "暂停")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MFTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    if audioService.currentRecordingDuration >= 5.0 {
                        showingStopConfirmation = true
                    } else {
                        completeAndSaveRecording()
                    }
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [MFTheme.coralRed, Color(red: 0.85, green: 0.22, blue: 0.28)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 68, height: 68)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.2)
                                )
                                .shadow(color: MFTheme.coralRed.opacity(0.45), radius: 14, x: 0, y: 4)

                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white)
                                .frame(width: 22, height: 22)
                        }
                        Text("完成保存")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MFTheme.coralRed)
                    }
                }
                .buttonStyle(.plain)
            }
        } else {
            MFLuminousActionButton("启动麦克风录音", icon: "mic.fill") {
                Task {
                    await beginRecordingNow()
                }
            }
        }
    }

    private func beginRecordingNow() async {
        do {
            errorMessage = nil
            _ = try await audioService.startRecording()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func completeAndSaveRecording() {
        guard let result = audioService.finishRecording() else {
            dismiss()
            return
        }
        store.handleFinishedRecording(
            id: result.id,
            fileName: result.fileName,
            createdAt: result.createdAt,
            duration: result.duration,
            selectedMode: selectedMode,
            isNetworkAvailable: !simulateOfflineSave,
            marks: audioService.recordingBookmarks
        )
        dismiss()
    }
}

/// R12 云处理首次授权与逐次确认弹窗（PRD R12 & 9.2 & A28）
public struct CloudConsentSheetView: View {
    @ObservedObject var store: MemoFlowStore
    @Environment(\.dismiss) private var dismiss
    @State private var rememberChoice: Bool = true

    public init(store: MemoFlowStore) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            MFTheme.sheetBg.ignoresSafeArea()
            MFTheme.ambientTopGlow.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.title2)
                        .foregroundStyle(MFTheme.iceCyan)
                    Text("云端语音转写与 AI 整理授权说明")
                        .font(.headline)
                        .foregroundStyle(MFTheme.textPrimary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("你的录音已在本地设备安全保存。")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MFTheme.mintGreen)

                    Text("• 音频转写：\(store.preferences.asrEngineMode == .appleOnDevice ? "仅本机 Apple Speech" : store.preferences.asrBaseURL)\n• 文字整理：\(store.preferences.llmBaseURL.isEmpty ? "本地规则" : store.preferences.llmBaseURL)\n• 用途：转写录音、整理笔记与行动候选。云服务的数据保留和训练政策以各服务商条款为准；日历写入遵循你设置的审核模式。")
                        .font(.footnote)
                        .foregroundStyle(MFTheme.textSecondary)
                }
                .mfGlassCard(cornerRadius: 14, padding: 14, tint: MFTheme.mintGreen)

                Toggle("记住我的授权偏好（后续录音自动开始转写，可在设置中随时撤回）", isOn: $rememberChoice)
                    .font(.footnote)
                    .foregroundStyle(MFTheme.textSecondary)

                HStack(spacing: 12) {
                    Button {
                        store.pendingConsentRecordingId = nil
                        dismiss()
                    } label: {
                        Text("仅保留本地录音")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(MFTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.grantCloudProcessingConsent(rememberPreference: rememberChoice)
                        dismiss()
                    } label: {
                        Text("同意并开始转写整理")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(MFTheme.iceBlue, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .focusEffectDisabled()
        .preferredColorScheme(store.preferences.appearanceTheme.colorScheme)
        .presentationDetents([.medium])
    }
}
