import SwiftUI
import EventKit
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(MemoFlowCore)
import MemoFlowCore
#endif

// MARK: - Structured Provider & Model Catalogs (Selection-First, No Raw Fill-in-the-Blank)

public enum ASRProviderOption: String, CaseIterable, Identifiable {
    case appleLocal = "apple_local"
    case siliconFlow = "siliconflow"
    case groq = "groq"
    case openAI = "openai"
    case custom = "custom"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appleLocal: return "Apple 端侧识别"
        case .siliconFlow: return "硅基流动"
        case .groq: return "Groq 极速"
        case .openAI: return "OpenAI"
        case .custom: return "自定义接口"
        }
    }

    public var badge: String {
        switch self {
        case .appleLocal: return "免 Key · 本地"
        case .siliconFlow: return "中文首选 · 免费额度"
        case .groq: return "超快 Whisper"
        case .openAI: return "官方标准"
        case .custom: return "高级"
        }
    }

    public var iconName: String {
        switch self {
        case .appleLocal: return "iphone.gen3"
        case .siliconFlow: return "sparkles"
        case .groq: return "bolt.fill"
        case .openAI: return "waveform.circle.fill"
        case .custom: return "slider.horizontal.3"
        }
    }

    public var baseURL: String {
        switch self {
        case .appleLocal: return ""
        case .siliconFlow: return "https://api.siliconflow.cn/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .openAI: return "https://api.openai.com/v1"
        case .custom: return ""
        }
    }

    public var presetModels: [(id: String, label: String)] {
        switch self {
        case .appleLocal:
            return [("apple-speech", "系统内置 SFSpeechRecognizer（中文/多语种）")]
        case .siliconFlow:
            return [
                ("FunAudioLLM/SenseVoiceSmall", "SenseVoiceSmall（阿里开源 · 中英混杂极快）"),
                ("TeleAI/TeleSpeechASR", "TeleSpeechASR（中文会议与方言优化）")
            ]
        case .groq:
            return [
                ("whisper-large-v3-turbo", "Whisper Large v3 Turbo（极速带时间戳）"),
                ("whisper-large-v3", "Whisper Large v3（高精度完整版）")
            ]
        case .openAI:
            return [
                ("gpt-4o-transcribe", "GPT-4o Transcribe（最新一代高准度语音转写）"),
                ("gpt-4o-mini-transcribe", "GPT-4o Mini Transcribe（高性价比极速版）"),
                ("whisper-1", "Whisper-1（经典带分段时间戳）")
            ]
        case .custom:
            return []
        }
    }

    public var requiresAPIKey: Bool {
        self != .appleLocal
    }
}

public enum LLMProviderOption: String, CaseIterable, Identifiable {
    case deepSeek = "deepseek"
    case siliconFlow = "siliconflow"
    case openAI = "openai"
    case localRules = "local_rules"
    case custom = "custom"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .deepSeek: return "DeepSeek"
        case .siliconFlow: return "硅基流动"
        case .openAI: return "OpenAI"
        case .localRules: return "本地规则引擎"
        case .custom: return "自定义接口"
        }
    }

    public var badge: String {
        switch self {
        case .deepSeek: return "中文推理极佳"
        case .siliconFlow: return "可与语音共用 Key"
        case .openAI: return "GPT-4.1 / o4 系列"
        case .localRules: return "免 Key · 离线"
        case .custom: return "高级"
        }
    }

    public var iconName: String {
        switch self {
        case .deepSeek: return "brain.head.profile"
        case .siliconFlow: return "cpu.fill"
        case .openAI: return "sparkle.magnifyingglass"
        case .localRules: return "internaldrive.fill"
        case .custom: return "slider.horizontal.3"
        }
    }

    public var baseURL: String {
        switch self {
        case .deepSeek: return "https://api.deepseek.com/v1"
        case .siliconFlow: return "https://api.siliconflow.cn/v1"
        case .openAI: return "https://api.openai.com/v1"
        case .localRules: return ""
        case .custom: return ""
        }
    }

    public var presetModels: [(id: String, label: String)] {
        switch self {
        case .deepSeek:
            return [
                ("deepseek-chat", "DeepSeek-V3 最新版（官方自动指向最新 V3 权重）"),
                ("deepseek-reasoner", "DeepSeek-R1 最新版（官方自动指向最新 R1 深度推理）")
            ]
        case .siliconFlow:
            return [
                ("deepseek-ai/DeepSeek-V3", "DeepSeek-V3（硅基流动标准通道）"),
                ("Pro/deepseek-ai/DeepSeek-V3", "Pro/DeepSeek-V3（硅基流动高速 Pro 通道）"),
                ("deepseek-ai/DeepSeek-R1", "DeepSeek-R1（深度思考推理）"),
                ("Qwen/Qwen3-235B-A22B", "通义千问 Qwen3-235B-A22B（最新旗舰 MoE）"),
                ("Qwen/Qwen3-32B", "通义千问 Qwen3-32B（高速均衡）"),
                ("Qwen/Qwen2.5-72B-Instruct", "通义千问 Qwen2.5-72B-Instruct")
            ]
        case .openAI:
            return [
                ("gpt-4.1-mini", "GPT-4.1 mini（最新一代快速结构化提取推荐）"),
                ("gpt-4.1", "GPT-4.1（最新旗舰长上下文模型）"),
                ("o4-mini", "o4-mini（高性价比推理模型）"),
                ("gpt-4o", "GPT-4o（经典多模态旗舰）")
            ]
        case .localRules:
            return [("local-heuristic", "内置离线规则提取（免网络 / 免 Key）")]
        case .custom:
            return []
        }
    }

    public var requiresAPIKey: Bool {
        self != .localRules
    }
}

// MARK: - P06 美化版卡片式设置页（选择优先 + 支持 /v1/models 实时拉取新模型）

public struct SettingsView: View {
    @ObservedObject var store: MemoFlowStore
    @Environment(\.dismiss) private var dismiss
    @State private var choosingVault = false

    @State private var selectedASRProvider: ASRProviderOption = .siliconFlow
    @State private var selectedLLMProvider: LLMProviderOption = .deepSeek
    @State private var shareSiliconFlowKey: Bool = true

    @State private var asrAPIKeyInput: String = ""
    @State private var llmAPIKeyInput: String = ""
    @State private var showASRKeyPlain: Bool = false
    @State private var showLLMKeyPlain: Bool = false
    @State private var savedToastVisible: Bool = false

    // 动态模型同步与手动新增状态
    @State private var isSyncingASRModels: Bool = false
    @State private var isSyncingLLMModels: Bool = false
    @State private var asrSyncStatusMessage: String?
    @State private var llmSyncStatusMessage: String?
    @State private var newASRModelIdInput: String = ""
    @State private var newLLMModelIdInput: String = ""
    @State private var showingAddASRModelField: Bool = false
    @State private var showingAddLLMModelField: Bool = false

    @State private var writableCalendars: [WritableContainerInfo] = []
    @State private var writableReminderLists: [WritableContainerInfo] = []
    @State private var showingResetConfirmation: Bool = false

    public init(store: MemoFlowStore) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            MFTheme.sheetBg.ignoresSafeArea()
            MFTheme.ambientTopGlow.ignoresSafeArea()

            VStack(spacing: 0) {
                topHeaderBar

                Divider().overlay(Color.white.opacity(0.08))

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        appearanceThemeCard
                        asrSelectionCard
                        llmSelectionCard
                        speakerAndVoiceProfileCard
                        calendarSyncModeCard
                        obsidianIntegrationCard
                        routingAndTimePreferencesCard
                        privacyAndPermissionsCard
                        storageAndResetCard
                    }
                    .padding(20)
                }
            }
        }
        .focusEffectDisabled()
        .preferredColorScheme(store.preferences.appearanceTheme.colorScheme)
        .onAppear {
            loadCurrentSelectionState()
        }
        .fileImporter(isPresented: $choosingVault, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): store.bindObsidianVault(url)
            case .failure(let error): store.knowledgeStatus = "选择文件夹失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - Top Header

    private var topHeaderBar: some View {
        HStack(spacing: 12) {
            MemoFlowWaveformBrandIcon(size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("服务配置与偏好设置")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(MFTheme.textPrimary)
                Text("点选服务商与模型即可切换，密钥安全加密保存在系统 Keychain")
                    .font(.caption2)
                    .foregroundStyle(MFTheme.textSecondary)
            }

            Spacer()

            if savedToastVisible {
                MFBadgePill("已自动保存", color: MFTheme.mintGreen, icon: "checkmark.circle.fill")
                    .transition(.opacity)
            }

            MFLuminousActionButton("完成保存", icon: "checkmark") {
                saveAllAndDismiss()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(MFTheme.recessedBg.opacity(0.85))
    }

    // MARK: - 0. Appearance Theme Card (PRD V1.3 VIS-001)

    private var appearanceThemeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("视觉主题与阅读质感（VIS-001）", systemImage: "paintbrush.pointed.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MFTheme.iceBlue)

            Text("启发自 Readwise 极简暖纸阅读体验。为长篇逐字稿阅读提供温暖、克制、安静的书籍质感。")
                .font(.caption2)
                .foregroundStyle(MFTheme.textSecondary)

            Picker("视觉主题", selection: Binding(
                get: { store.preferences.appearanceTheme },
                set: {
                    store.preferences.appearanceTheme = $0
                    store.saveToDisk()
                }
            )) {
                ForEach(AppearanceTheme.allCases, id: \.self) { theme in
                    Text(theme.displayTitle).tag(theme)
                }
            }
            .pickerStyle(.segmented)
        }
        .mfGlassCard(cornerRadius: 14, padding: 14)
    }

    // MARK: - 1. ASR Selection Card

    private var asrSelectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("第一步：选择语音转写服务 (ASR)", systemImage: "waveform.badge.mic")
                    .font(.subheadline.weight(.bold))
                Spacer()
                statusPill(
                    isReady: !selectedASRProvider.requiresAPIKey || !asrAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    readyText: selectedASRProvider == .appleLocal ? "端侧免 Key 已就绪" : "已配置密钥",
                    emptyText: "待粘贴 API Key"
                )
            }

            // 服务商网格点选卡片
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 10)], spacing: 10) {
                ForEach(ASRProviderOption.allCases) { option in
                    providerOptionTile(
                        title: option.title,
                        badge: option.badge,
                        icon: option.iconName,
                        isSelected: selectedASRProvider == option
                    ) {
                        selectASRProvider(option)
                    }
                }
            }

            // 预置模型 + 动态拉取/自定义模型选择（支持一键从 /v1/models 拉取最新模型，或手动添加新模型）
            if selectedASRProvider != .custom {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("选择识别模型")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(MFTheme.textSecondary)

                        Spacer()

                        if selectedASRProvider.requiresAPIKey {
                            Button {
                                Task { await syncRemoteASRModels() }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isSyncingASRModels ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise")
                                    Text(isSyncingASRModels ? "正在拉取…" : "从服务端拉取最新模型")
                                }
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(MFTheme.iceCyan)
                            }
                            .buttonStyle(.plain)
                            .disabled(isSyncingASRModels)

                            Text("·").foregroundStyle(MFTheme.textMuted)

                            Button {
                                withAnimation { showingAddASRModelField.toggle() }
                            } label: {
                                Text(showingAddASRModelField ? "收起" : "+ 手动添加新模型")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(MFTheme.iceCyan)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let msg = asrSyncStatusMessage {
                        Text(msg)
                            .font(.caption2)
                            .foregroundStyle(MFTheme.mintGreen)
                    }

                    if showingAddASRModelField {
                        HStack(spacing: 8) {
                            TextField("输入新发布的语音模型 ID（如 FunAudioLLM/SenseVoiceLarge）", text: $newASRModelIdInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption.monospaced())
                            Button("添加并选中") {
                                addCustomASRModel()
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    ForEach(combinedASRModels, id: \.id) { model in
                        modelRadioRow(
                            title: model.label,
                            subtitle: model.id,
                            isSelected: store.preferences.asrModelName == model.id || selectedASRProvider == .appleLocal
                        ) {
                            store.preferences.asrModelName = model.id
                            autoSaveKeys()
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("自定义 Base URL（如 https://api.example.com/v1）", text: $store.preferences.asrBaseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("自定义语音模型名", text: $store.preferences.asrModelName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // 仅当所选服务需要 API Key 时显示粘贴框
            if selectedASRProvider.requiresAPIKey {
                apiKeyInputRow(
                    title: "\(selectedASRProvider.title) API Key",
                    placeholder: "点击右侧「粘贴」直接填入 \(selectedASRProvider.title) 密钥",
                    text: $asrAPIKeyInput,
                    isPlainVisible: $showASRKeyPlain
                )
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 16)
    }

    // MARK: - 2. LLM Selection Card

    private var llmSelectionCard: some View {
        let isSharingKey = (selectedASRProvider == .siliconFlow && selectedLLMProvider == .siliconFlow && shareSiliconFlowKey)
        let effectiveLLMKey = isSharingKey ? asrAPIKeyInput : llmAPIKeyInput

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("第二步：选择 AI 笔记与行动提取服务 (LLM)", systemImage: "sparkles.rectangle.stack.fill")
                    .font(.subheadline.weight(.bold))
                Spacer()
                statusPill(
                    isReady: !selectedLLMProvider.requiresAPIKey || !effectiveLLMKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    readyText: selectedLLMProvider == .localRules ? "本地规则已就绪" : "已配置密钥",
                    emptyText: "待粘贴 API Key"
                )
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 10)], spacing: 10) {
                ForEach(LLMProviderOption.allCases) { option in
                    providerOptionTile(
                        title: option.title,
                        badge: option.badge,
                        icon: option.iconName,
                        isSelected: selectedLLMProvider == option
                    ) {
                        selectLLMProvider(option)
                    }
                }
            }

            // 预置模型 + 动态拉取/自定义模型单选列表
            if selectedLLMProvider != .custom {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("选择整理模型")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(MFTheme.textSecondary)

                        Spacer()

                        if selectedLLMProvider.requiresAPIKey {
                            Button {
                                Task { await syncRemoteLLMModels(effectiveKey: effectiveLLMKey) }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isSyncingLLMModels ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise")
                                    Text(isSyncingLLMModels ? "正在拉取…" : "从服务端拉取最新模型")
                                }
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(MFTheme.iceCyan)
                            }
                            .buttonStyle(.plain)
                            .disabled(isSyncingLLMModels)

                            Text("·").foregroundStyle(MFTheme.textMuted)

                            Button {
                                withAnimation { showingAddLLMModelField.toggle() }
                            } label: {
                                Text(showingAddLLMModelField ? "收起" : "+ 手动添加新模型")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(MFTheme.iceCyan)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let msg = llmSyncStatusMessage {
                        Text(msg)
                            .font(.caption2)
                            .foregroundStyle(MFTheme.mintGreen)
                    }

                    if showingAddLLMModelField {
                        HStack(spacing: 8) {
                            TextField("输入新发布的模型 ID（如 deepseek-v4 或 gpt-5）", text: $newLLMModelIdInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption.monospaced())
                            Button("添加并选中") {
                                addCustomLLMModel()
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    ForEach(combinedLLMModels, id: \.id) { model in
                        modelRadioRow(
                            title: model.label,
                            subtitle: model.id,
                            isSelected: store.preferences.llmModelName == model.id || selectedLLMProvider == .localRules
                        ) {
                            store.preferences.llmModelName = model.id
                            autoSaveKeys()
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("自定义 LLM Base URL", text: $store.preferences.llmBaseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("自定义 LLM 模型名", text: $store.preferences.llmModelName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // 如果语音和 LLM 都选了硅基流动，提供「一键共用同一个 Key」开关，免填第二次！
            if selectedASRProvider == .siliconFlow && selectedLLMProvider == .siliconFlow {
                Toggle("直接复用上方「硅基流动」API Key（无需重复填写）", isOn: $shareSiliconFlowKey)
                    .font(.caption.weight(.medium))
                    .padding(10)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            if selectedLLMProvider.requiresAPIKey && !isSharingKey {
                apiKeyInputRow(
                    title: "\(selectedLLMProvider.title) API Key",
                    placeholder: "点击右侧「粘贴」直接填入 \(selectedLLMProvider.title) 密钥",
                    text: $llmAPIKeyInput,
                    isPlainVisible: $showLLMKeyPlain
                )
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 16)
    }

    // MARK: - 3. Speaker & Movie Character Nickname Theme (PRD V1.2 AI-001 & AI-003)

    private var speakerAndVoiceProfileCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("说话人识别与电影角色昵称", systemImage: "person.2.wave.2.fill")
                    .font(.subheadline.weight(.bold))
                Spacer()
                MFBadgePill(store.preferences.speakerNicknameTheme.displayTitle, color: MFTheme.softViolet)
            }

            // 昵称主题切换
            VStack(alignment: .leading, spacing: 6) {
                Text("电影/剧集匿名昵称主题（会议录音自动按发言顺序分配，不猜测真实姓名）")
                    .font(.caption)
                    .foregroundStyle(MFTheme.textSecondary)

                HStack(spacing: 8) {
                    ForEach(SpeakerNicknameTheme.allCases, id: \.self) { theme in
                        let isSelected = (store.preferences.speakerNicknameTheme == theme)
                        Button {
                            store.preferences.speakerNicknameTheme = theme
                            store.saveToDisk()
                        } label: {
                            Text(theme.displayTitle)
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    isSelected
                                        ? MFTheme.softViolet.opacity(0.3)
                                        : Color.white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(isSelected ? MFTheme.softViolet.opacity(0.6) : Color.clear, lineWidth: 1)
                                )
                                .foregroundStyle(isSelected ? Color.white : MFTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("候选角色库：\(store.preferences.speakerNicknameTheme.defaultNicknames.joined(separator: "、"))")
                    .font(.caption2)
                    .foregroundStyle(MFTheme.textMuted)
            }

            Divider().overlay(Color.white.opacity(0.08))

            // 个人声纹档案（AI-001：识别我的声音）
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("识别我的声音（个人声纹档案）", systemImage: "waveform.badge.mic")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MFTheme.textPrimary)
                    Spacer()
                    if store.preferences.userVoiceProfile != nil {
                        MFBadgePill("已录入声纹档案", color: MFTheme.mintGreen, icon: "checkmark.circle.fill")
                    } else {
                        MFBadgePill("未录入声纹", color: MFTheme.warmAmber)
                    }
                }

                if let profile = store.preferences.userVoiceProfile {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.featureDescription)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(MFTheme.textPrimary)
                            Text("录入时间：\(profile.enrolledAt.formatted(date: .numeric, time: .shortened)) · 录音中将自动标记「我」的发言")
                                .font(.caption2)
                                .foregroundStyle(MFTheme.textSecondary)
                        }
                        Spacer()
                        Button("重新录入") {
                            store.enrollVoiceProfile(sampleDuration: 6.0, description: "已更新个人声纹特征档案")
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MFTheme.iceCyan)
                        .buttonStyle(.plain)

                        Button("删除档案") {
                            store.deleteVoiceProfile()
                        }
                        .font(.caption2)
                        .foregroundStyle(MFTheme.coralRed)
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    HStack {
                        Text("录入 6 秒语音样本建立声纹档案，新录音将自动识别并在逐字稿中标记为「我」。")
                            .font(.caption2)
                            .foregroundStyle(MFTheme.textSecondary)
                        Spacer()
                        MFLuminousActionButton("录入我的声音", icon: "mic.fill", tint: MFTheme.mintGreen) {
                            store.enrollVoiceProfile(sampleDuration: 6.0, description: "已录入个人声纹特征档案（高置信度）")
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 16)
    }

    // MARK: - 4. Calendar Sync Mode Card (PRD V1.2 CAL-003)

    private var calendarSyncModeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("苹果日历智能同步偏好", systemImage: "calendar.badge.clock")
                    .font(.subheadline.weight(.bold))
                Spacer()
                MFBadgePill(store.preferences.calendarCreationMode.displayTitle, color: MFTheme.iceCyan)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(CalendarCreationMode.allCases, id: \.self) { mode in
                    let isSelected = (store.preferences.calendarCreationMode == mode)
                    Button {
                        store.preferences.calendarCreationMode = mode
                        store.saveToDisk()
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(isSelected ? MFTheme.iceCyan : MFTheme.textMuted)
                                .font(.subheadline)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.displayTitle)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(isSelected ? Color.white : MFTheme.textPrimary)
                                Text(mode.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(MFTheme.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? MFTheme.iceBlue.opacity(0.12) : Color.white.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(isSelected ? MFTheme.iceBlue.opacity(0.35) : Color.clear, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 16)
    }

    // MARK: - 5. Obsidian Integration Card (PRD R15)

    private var obsidianIntegrationCard: some View {
        let boundVault = store.preferences.obsidianVaultRootPath ?? ""

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Obsidian 笔记库联动（一键直写 / 自动归档）", systemImage: "books.vertical.fill")
                    .font(.subheadline.weight(.bold))
                Spacer()
                statusPill(
                    isReady: !boundVault.isEmpty,
                    readyText: "已绑定笔记库",
                    emptyText: "未选择目录"
                )
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前绑定笔记库路径")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(boundVault.isEmpty ? "尚未选择（点右侧按钮选择你的 Obsidian 库目录）" : boundVault)
                        .font(.caption2.monospaced())
                        .foregroundStyle(boundVault.isEmpty ? .secondary : .primary)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    choosingVault = true
                } label: {
                    Label("选择文件夹…", systemImage: "folder.badge.plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.purple.opacity(0.15), in: Capsule())
                        .foregroundStyle(.purple)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            Toggle("使用知识库背景辅助 AI 整理", isOn: $store.preferences.knowledgeContextEnabled)
                .onChange(of: store.preferences.knowledgeContextEnabled) { _, _ in
                    store.saveToDisk()
                    Task { await store.refreshKnowledge() }
                }
            Text("开启后，会把最多 4 篇相关笔记的片段（每篇最多 900 字符）发送至当前 AI 服务：\(store.preferences.llmBaseURL)。本机索引最多 2000 篇、16 MB；单篇不超过 256 KB。打开应用、回到前台或整理录音时刷新。")
                .font(.caption).foregroundStyle(.secondary)
            Text("不读取的文件夹（相对知识库路径，每行一个）")
                .font(.caption)
            TextEditor(text: $store.preferences.knowledgeExcludedFolders)
                .frame(height: 65)
                .onChange(of: store.preferences.knowledgeExcludedFolders) { _, _ in store.saveToDisk() }
            Text("自动排除隐藏目录和 MemoFlow 导出目录，避免重复引用自己的整理结果。")
                .font(.caption2).foregroundStyle(.secondary)
            Text(store.knowledgeStatus).font(.caption)
            HStack {
                Button(store.isRefreshingKnowledge ? "正在刷新…" : "刷新知识库") {
                    Task { await store.refreshKnowledge() }
                }.disabled(store.isRefreshingKnowledge)
                Button("断开知识库", role: .destructive) { store.disconnectObsidianVault() }
            }

            // 存放子目录点选或自定义
            VStack(alignment: .leading, spacing: 6) {
                Text("存入库内的目标子文件夹（不存在时会自动创建）")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(["MemoFlow笔记", "00_Inbox", "justesine"], id: \.self) { folder in
                        Button {
                            store.preferences.obsidianTargetSubfolder = folder
                            store.saveToDisk()
                        } label: {
                            Text(folder)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    store.preferences.obsidianTargetSubfolder == folder
                                        ? Color.purple
                                        : Color.secondary.opacity(0.12),
                                    in: Capsule()
                                )
                                .foregroundStyle(store.preferences.obsidianTargetSubfolder == folder ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Toggle("录音转写并完成 AI 整理后，自动生成 .md 写入上述 Obsidian 目录", isOn: $store.preferences.autoExportToObsidianOnComplete)
                .font(.caption.weight(.medium))
                .onChange(of: store.preferences.autoExportToObsidianOnComplete) { _, _ in
                    store.saveToDisk()
                }
        }
        .mfGlassCard(cornerRadius: 16, padding: 16)
    }

    // MARK: - 4. Routing & Time Preferences Card

    private var routingAndTimePreferencesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("默认整理与分流偏好", systemImage: "arrow.triangle.branch")
                .font(.subheadline.weight(.bold))

            // 默认整理模式分段选择
            VStack(alignment: .leading, spacing: 6) {
                Text("新录音默认整理模式")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("新录音默认整理模式", selection: $store.preferences.defaultNoteMode) {
                    ForEach(NoteMode.allCases, id: \.self) { mode in
                        Text(mode.displayTitle).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            // 待办默认主要去向点选胶囊
            VStack(alignment: .leading, spacing: 6) {
                Text("待办任务默认主要去向（单一主要管理位置，避免重复维护状态）")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach([PrimaryDestination.reminders, .markdown, .local], id: \.self) { dest in
                        Button {
                            store.preferences.defaultTaskDestination = dest
                            store.saveToDisk()
                        } label: {
                            Text(dest.displayTitle)
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    store.preferences.defaultTaskDestination == dest
                                        ? Color.accentColor
                                        : Color.secondary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .foregroundStyle(store.preferences.defaultTaskDestination == dest ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // 无结束时间日程默认时长点选（不让用户按步进器慢慢点）
            VStack(alignment: .leading, spacing: 6) {
                Text("只有开始时间、未提结束时间的日程默认时长（审核卡片中会明确标注「默认值」）")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach([15, 30, 45, 60, 90], id: \.self) { mins in
                        Button {
                            store.preferences.defaultEventDurationMinutes = mins
                            store.saveToDisk()
                        } label: {
                            Text("\(mins) 分钟")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    store.preferences.defaultEventDurationMinutes == mins
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.secondary.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .foregroundStyle(store.preferences.defaultEventDurationMinutes == mins ? Color.accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 16)
    }

    // MARK: - 4. Privacy & System Permissions Card

    private var privacyAndPermissionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("云处理授权与系统日历 / 提醒事项权限", systemImage: "lock.shield")
                .font(.subheadline.weight(.bold))

            HStack(spacing: 8) {
                ForEach(ConsentMode.allCases, id: \.self) { mode in
                    Button {
                        store.processingConsent.mode = mode
                        if mode == .remembered {
                            store.processingConsent.grantedAt = Date()
                            store.processingConsent.revokedAt = nil
                        }
                        store.saveToDisk()
                    } label: {
                        Text(mode.displayTitle)
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                store.processingConsent.mode == mode
                                    ? Color.blue.opacity(0.16)
                                    : Color.secondary.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .foregroundStyle(store.processingConsent.mode == mode ? Color.blue : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        _ = await EventKitIntegrationService.shared.requestCalendarAccess()
                        refreshContainers()
                    }
                } label: {
                    Label("授权并刷新 Apple 日历 (\(writableCalendars.count))", systemImage: "calendar.badge.plus")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        _ = await EventKitIntegrationService.shared.requestRemindersAccess()
                        refreshContainers()
                    }
                } label: {
                    Label("授权并刷新提醒事项 (\(writableReminderLists.count))", systemImage: "checklist")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 16)
    }

    // MARK: - 5. Storage & Demo Reset Card

    private var storageAndResetCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("本地录音与测试数据")
                    .font(.caption.weight(.bold))
                Text("已存录音 \(store.recordings.count) 条 · 审计日志 \(store.operationLogs.count) 条")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showingResetConfirmation = true
            } label: {
                Label("重置 PRD 演示样本", systemImage: "arrow.counterclockwise")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                "确定重置为演示样本吗？",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("确认重置（将清除当前列表）", role: .destructive) {
                    store.seedPRDDefaultScenarios()
                    store.saveToDisk()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作将把录音列表恢复为 PRD 标准测试场景，现有录音将从列表移除（本地音频文件仍保留在 Documents 文件夹）。")
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 16)
    }

    // MARK: - Reusable UI Components

    private func providerOptionTile(
        title: String,
        badge: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                }

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(badge)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .lineLimit(1)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func modelRadioRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }

    private func apiKeyInputRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        isPlainVisible: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                if !text.wrappedValue.isEmpty {
                    Button("清空") {
                        text.wrappedValue = ""
                        autoSaveKeys()
                    }
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                Group {
                    if isPlainVisible.wrappedValue {
                        TextField(placeholder, text: text)
                    } else {
                        SecureField(placeholder, text: text)
                    }
                }
                .textFieldStyle(.plain)
                .font(.caption.monospaced())
                .onChange(of: text.wrappedValue) { _, _ in
                    autoSaveKeys()
                }

                Button {
                    isPlainVisible.wrappedValue.toggle()
                } label: {
                    Image(systemName: isPlainVisible.wrappedValue ? "eye.slash" : "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    if let clip = readClipboardString(), !clip.isEmpty {
                        text.wrappedValue = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                        autoSaveKeys()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                        Text("粘贴")
                    }
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func statusPill(isReady: Bool, readyText: String, emptyText: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isReady ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(isReady ? readyText : emptyText)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((isReady ? Color.green : Color.orange).opacity(0.14), in: Capsule())
        .foregroundStyle(isReady ? Color.green : Color.orange)
    }

    // MARK: - Selection Logic & Persistence

    private func selectASRProvider(_ option: ASRProviderOption) {
        selectedASRProvider = option
        if option == .appleLocal {
            store.preferences.asrEngineMode = .appleOnDevice
        } else {
            store.preferences.asrEngineMode = .openAICompatible
            if !option.baseURL.isEmpty {
                store.preferences.asrBaseURL = option.baseURL
            }
            if let firstModel = option.presetModels.first?.id {
                store.preferences.asrModelName = firstModel
            }
        }
        autoSaveKeys()
    }

    private func selectLLMProvider(_ option: LLMProviderOption) {
        selectedLLMProvider = option
        if option == .localRules {
            llmAPIKeyInput = ""
            KeychainService.shared.deleteKey(for: .llmAPIKey)
        } else {
            if !option.baseURL.isEmpty {
                store.preferences.llmBaseURL = option.baseURL
            }
            if let firstModel = option.presetModels.first?.id {
                store.preferences.llmModelName = firstModel
            }
        }
        autoSaveKeys()
    }

    private func loadCurrentSelectionState() {
        asrAPIKeyInput = KeychainService.shared.readKey(for: .asrAPIKey) ?? ""
        llmAPIKeyInput = KeychainService.shared.readKey(for: .llmAPIKey) ?? ""

        if store.preferences.asrEngineMode == .appleOnDevice {
            selectedASRProvider = .appleLocal
        } else if store.preferences.asrBaseURL.contains("siliconflow") {
            selectedASRProvider = .siliconFlow
        } else if store.preferences.asrBaseURL.contains("groq") {
            selectedASRProvider = .groq
        } else if store.preferences.asrBaseURL.contains("openai.com") {
            selectedASRProvider = .openAI
        } else {
            selectedASRProvider = .custom
        }

        if store.preferences.llmBaseURL.contains("deepseek.com") {
            selectedLLMProvider = .deepSeek
        } else if store.preferences.llmBaseURL.contains("siliconflow") {
            selectedLLMProvider = .siliconFlow
        } else if store.preferences.llmBaseURL.contains("openai.com") {
            selectedLLMProvider = .openAI
        } else {
            selectedLLMProvider = .deepSeek
        }

        refreshContainers()
    }

    private func autoSaveKeys() {
        KeychainService.shared.saveKey(asrAPIKeyInput, for: .asrAPIKey)
        if selectedASRProvider == .siliconFlow && selectedLLMProvider == .siliconFlow && shareSiliconFlowKey {
            KeychainService.shared.saveKey(asrAPIKeyInput, for: .llmAPIKey)
        } else if selectedLLMProvider == .localRules {
            KeychainService.shared.deleteKey(for: .llmAPIKey)
        } else {
            KeychainService.shared.saveKey(llmAPIKeyInput, for: .llmAPIKey)
        }
        store.saveToDisk()
        withAnimation {
            savedToastVisible = true
        }
    }

    private func saveAllAndDismiss() {
        autoSaveKeys()
        dismiss()
    }

    private func readClipboardString() -> String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }

    private func refreshContainers() {
        writableCalendars = EventKitIntegrationService.shared.writableCalendars()
        writableReminderLists = EventKitIntegrationService.shared.writableReminderLists()
    }

    // MARK: - Dynamic Model List Merging & /v1/models Live Sync

    private var combinedASRModels: [(id: String, label: String)] {
        var result = selectedASRProvider.presetModels
        let existingIds = Set(result.map(\.id))
        for customId in store.preferences.customASRModels where !existingIds.contains(customId) {
            result.append((id: customId, label: "\(customId)（已同步/自定义模型）"))
        }
        return result
    }

    private var combinedLLMModels: [(id: String, label: String)] {
        var result = selectedLLMProvider.presetModels
        let existingIds = Set(result.map(\.id))
        for customId in store.preferences.customLLMModels where !existingIds.contains(customId) {
            result.append((id: customId, label: "\(customId)（已同步/自定义模型）"))
        }
        return result
    }

    private func addCustomASRModel() {
        let trimmed = newASRModelIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !store.preferences.customASRModels.contains(trimmed) {
            store.preferences.customASRModels.insert(trimmed, at: 0)
        }
        store.preferences.asrModelName = trimmed
        newASRModelIdInput = ""
        showingAddASRModelField = false
        autoSaveKeys()
    }

    private func addCustomLLMModel() {
        let trimmed = newLLMModelIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !store.preferences.customLLMModels.contains(trimmed) {
            store.preferences.customLLMModels.insert(trimmed, at: 0)
        }
        store.preferences.llmModelName = trimmed
        newLLMModelIdInput = ""
        showingAddLLMModelField = false
        autoSaveKeys()
    }

    @MainActor
    private func syncRemoteASRModels() async {
        isSyncingASRModels = true
        asrSyncStatusMessage = nil
        defer { isSyncingASRModels = false }

        do {
            let fetched = try await ASRAndLLMService.shared.fetchRemoteModels(
                baseURL: store.preferences.asrBaseURL,
                apiKey: asrAPIKeyInput,
                category: .asr
            )
            let presetIds = Set(selectedASRProvider.presetModels.map(\.id))
            var addedCount = 0
            for id in fetched where !presetIds.contains(id) && !store.preferences.customASRModels.contains(id) {
                store.preferences.customASRModels.append(id)
                addedCount += 1
            }
            store.saveToDisk()
            asrSyncStatusMessage = addedCount > 0
                ? "已从服务端拉取并新增 \(addedCount) 个语音模型，直接点击下方单选框即可切换。"
                : "已与服务端同步（共检测到 \(fetched.count) 个语音模型，当前列表已是最新）。"
        } catch {
            asrSyncStatusMessage = "拉取失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func syncRemoteLLMModels(effectiveKey: String) async {
        isSyncingLLMModels = true
        llmSyncStatusMessage = nil
        defer { isSyncingLLMModels = false }

        do {
            let fetched = try await ASRAndLLMService.shared.fetchRemoteModels(
                baseURL: store.preferences.llmBaseURL,
                apiKey: effectiveKey,
                category: .llm
            )
            let presetIds = Set(selectedLLMProvider.presetModels.map(\.id))
            var addedCount = 0
            for id in fetched where !presetIds.contains(id) && !store.preferences.customLLMModels.contains(id) {
                store.preferences.customLLMModels.append(id)
                addedCount += 1
            }
            store.saveToDisk()
            llmSyncStatusMessage = addedCount > 0
                ? "已从服务端拉取并新增 \(addedCount) 个模型，直接点击下方单选框即可切换。"
                : "已与服务端同步（共检测到 \(fetched.count) 个可用模型，当前列表已是最新）。"
        } catch {
            llmSyncStatusMessage = "拉取失败：\(error.localizedDescription)"
        }
    }
}
