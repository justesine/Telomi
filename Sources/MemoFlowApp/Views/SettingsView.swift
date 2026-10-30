import SwiftUI
import UniformTypeIdentifiers
#if canImport(MemoFlowCore)
import MemoFlowCore
#endif

// MARK: - Structured Provider & Model Catalogs (Selection-First, No Raw Fill-in-the-Blank)

public enum ASRProviderOption: String, CaseIterable, Identifiable {
    case siliconFlow = "siliconflow"
    case appleLocal = "apple_local"
    case whisperLocal = "whisper_local"
    case groq = "groq"
    case openAI = "openai"
    case custom = "custom"

    public var id: String { rawValue }

    public static var availableCases: [ASRProviderOption] {
        #if os(macOS)
        return allCases
        #else
        return allCases.filter { $0 != .whisperLocal }
        #endif
    }

    public var title: String {
        switch self {
        case .siliconFlow: return "硅基流动"
        case .appleLocal: return "Apple 语音识别"
        case .whisperLocal: return "Whisper 本地"
        case .groq: return "Groq 极速转写"
        case .openAI: return "OpenAI"
        case .custom: return "自定义 ASR"
        }
    }

    public var badge: String {
        switch self {
        case .siliconFlow: return "推荐 · 免费 SenseVoice"
        case .appleLocal: return "系统自带 · 免 Key"
        case .whisperLocal: return "Mac 本机 · 离线"
        case .groq: return "毫秒级 · 需 API Key"
        case .openAI: return "Whisper-1 · 需 Key"
        case .custom: return "高级"
        }
    }

    public var iconName: String {
        switch self {
        case .siliconFlow: return "bolt.shield.fill"
        case .appleLocal: return "apple.logo"
        case .whisperLocal: return "macmini.fill"
        case .groq: return "bolt.horizontal.fill"
        case .openAI: return "sparkles"
        case .custom: return "slider.horizontal.2.square"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .siliconFlow: return "https://api.siliconflow.cn/v1"
        case .appleLocal: return ""
        case .whisperLocal: return ""
        case .groq: return "https://api.groq.com/openai/v1"
        case .openAI: return "https://api.openai.com/v1"
        case .custom: return ""
        }
    }

    public var defaultModelName: String {
        switch self {
        case .siliconFlow: return "FunAudioLLM/SenseVoiceSmall"
        case .appleLocal: return "apple-speech"
        case .whisperLocal: return "ggml-large-v3-turbo-q5_0.bin"
        case .groq: return "whisper-large-v3-turbo"
        case .openAI: return "gpt-4o-transcribe"
        case .custom: return ""
        }
    }

    public var presetModels: [(id: String, label: String)] {
        switch self {
        case .siliconFlow:
            return [
                ("FunAudioLLM/SenseVoiceSmall", "SenseVoiceSmall（阿里开源 · 中英混杂极快 · 官方稳定在架）")
            ]
        case .appleLocal:
            return [("apple-speech", "系统内置 SFSpeechRecognizer（中文/多语种）")]
        case .whisperLocal:
            return [("ggml-large-v3-turbo-q5_0.bin", "Whisper Large v3 Turbo（本机模型，需回听校对）")]
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
        self != .appleLocal && self != .whisperLocal
    }
}

public enum LLMProviderOption: String, CaseIterable, Identifiable {
    case siliconFlow = "siliconflow"
    case deepSeek = "deepseek"
    case qwen, doubao, glm, kimi, minimax, qianfan
    case openAI = "openai"
    case localRules = "local_rules"
    case custom = "custom"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .siliconFlow: return "硅基流动"
        case .deepSeek: return "DeepSeek"
        case .qwen: return "通义千问 Qwen"
        case .doubao: return "豆包 · 火山方舟"
        case .glm: return "智谱 GLM"
        case .kimi: return "Kimi · 月之暗面"
        case .minimax: return "MiniMax"
        case .qianfan: return "百度千帆"
        case .openAI: return "OpenAI"
        case .localRules: return "本地规则引擎"
        case .custom: return "自定义接口"
        }
    }

    public var badge: String {
        switch self {
        case .siliconFlow: return "可与语音共用 Key · 推荐"
        case .deepSeek: return "V4.1 Flash / V4 Pro"
        case .qwen, .glm, .kimi, .minimax, .qianfan: return "文本整理 · 需 API Key"
        case .doubao: return "填写模型或接入点 ID"
        case .openAI: return "GPT-4.1 / o4 系列"
        case .localRules: return "免 Key · 离线"
        case .custom: return "高级"
        }
    }

    public var iconName: String {
        switch self {
        case .siliconFlow: return "bolt.shield.fill"
        case .deepSeek: return "brain.head.profile"
        case .qwen: return "cloud.sun.rain.fill"
        case .doubao: return "waveform.circle.fill"
        case .glm: return "atom"
        case .kimi: return "moon.stars.fill"
        case .minimax: return "circle.hexagongrid.fill"
        case .qianfan: return "leaf.fill"
        case .openAI: return "sparkles"
        case .localRules: return "cpu"
        case .custom: return "slider.horizontal.2.square"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .siliconFlow: return "https://api.siliconflow.cn/v1"
        case .deepSeek: return "https://api.deepseek.com/v1"
        case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .doubao: return "https://ark.cn-beijing.volces.com/api/v3"
        case .glm: return "https://open.bigmodel.cn/api/paas/v4"
        case .kimi: return "https://api.moonshot.cn/v1"
        case .minimax: return "https://api.minimax.chat/v1"
        case .qianfan: return "https://qianfan.baidubce.com/v2"
        case .openAI: return "https://api.openai.com/v1"
        case .localRules: return ""
        case .custom: return ""
        }
    }

    public var defaultModelName: String {
        switch self {
        case .siliconFlow: return "Qwen/Qwen2.5-7B-Instruct"
        case .deepSeek: return "deepseek-chat"
        case .qwen: return "qwen-turbo"
        case .doubao: return "doubao-pro-32k"
        case .glm: return "glm-4-flash"
        case .kimi: return "moonshot-v1-8k"
        case .minimax: return "abab6.5s-chat"
        case .qianfan: return "ernie-speed-128k"
        case .openAI: return "gpt-4.1-mini"
        case .localRules: return "local-heuristic"
        case .custom: return ""
        }
    }

    public var presetModels: [(id: String, label: String)] {
        switch self {
        case .siliconFlow:
            return [
                ("Qwen/Qwen2.5-7B-Instruct", "通义千问 Qwen2.5-7B-Instruct（推荐 · 极速 9 秒出结果 · 免费）"),
                ("deepseek-ai/DeepSeek-V4.1-Flash", "DeepSeek-V4.1 Flash（进阶推理，硅基流动）"),
                ("deepseek-ai/DeepSeek-V4-Pro", "DeepSeek-V4 Pro（长文思考旗舰，硅基流动）"),
                ("Qwen/Qwen2.5-72B-Instruct", "通义千问 Qwen2.5-72B-Instruct（高智商旗舰）"),
                ("Qwen/Qwen2.5-32B-Instruct", "通义千问 Qwen2.5-32B-Instruct（高速均衡）")
            ]
        case .deepSeek:
            return [
                ("deepseek-chat", "DeepSeek-V3（极速强劲日常整理）"),
                ("deepseek-reasoner", "DeepSeek-R1（深度思考与行动推导）")
            ]
        case .qwen:
            return [
                ("qwen-turbo", "通义千问 Turbo（极速高性价比）"),
                ("qwen-plus", "通义千问 Plus（长篇会议与访谈推荐）"),
                ("qwen-max", "通义千问 Max（百炼旗舰复杂规划）")
            ]
        case .doubao:
            return [
                ("doubao-pro-32k", "豆包 Pro 32k（字节火山旗舰）"),
                ("doubao-lite-32k", "豆包 Lite 32k（轻量高速）")
            ]
        case .glm:
            return [
                ("glm-4-flash", "GLM-4 Flash（智谱极速免费版）"),
                ("glm-4-air", "GLM-4 Air（高性价比）"),
                ("glm-4-plus", "GLM-4 Plus（旗舰智力）")
            ]
        case .kimi:
            return [
                ("moonshot-v1-8k", "Moonshot v1 8k（月之暗面高准度）"),
                ("moonshot-v1-32k", "Moonshot v1 32k（长文本深度理解）")
            ]
        case .minimax:
            return [
                ("abab6.5s-chat", "MiniMax abab 6.5s（全能高速模型）")
            ]
        case .qianfan:
            return [
                ("ernie-speed-128k", "文心 Ernie Speed 128k（超长上下文免费版）"),
                ("ernie-4.0-8k-latest", "文心 Ernie 4.0 8k（百度旗舰）")
            ]
        case .openAI:
            return [
                ("gpt-4.1-mini", "GPT-4.1 Mini（高智商极速）"),
                ("gpt-4.1", "GPT-4.1（最新旗舰推理）"),
                ("gpt-4o", "GPT-4o（经典多模态）")
            ]
        case .localRules:
            return [
                ("local-heuristic", "内置规则提取引擎（离线免 Key，适合隐私与断网）")
            ]
        case .custom:
            return []
        }
    }

    public var requiresAPIKey: Bool {
        self != .localRules
    }
}

// MARK: - Settings Destination Enum (3 Groups, 10 Items)

public enum SettingsDestination: String, CaseIterable, Identifiable, Hashable {
    case asr = "asr"
    case llm = "llm"
    case liveStreaming = "live_streaming"
    case speaker = "speaker"
    case obsidian = "obsidian"
    case memory = "memory"
    case calendar = "calendar"
    case appearance = "appearance"
    case language = "language"
    case privacy = "privacy"

    public var id: String { rawValue }

    public func localizedTitle(isEnglish: Bool) -> String {
        switch self {
        case .asr: return L10n.speechToText(isEnglish)
        case .llm: return L10n.aiNotes(isEnglish)
        case .liveStreaming: return L10n.liveStreaming(isEnglish)
        case .speaker: return L10n.speakerAndNicknames(isEnglish)
        case .obsidian: return "Obsidian"
        case .memory: return L10n.personalMemory(isEnglish)
        case .calendar: return L10n.calendarAndReminders(isEnglish)
        case .appearance: return L10n.appearance(isEnglish)
        case .language: return L10n.language(isEnglish)
        case .privacy: return L10n.privacyAndData(isEnglish)
        }
    }

    public var title: String {
        localizedTitle(isEnglish: false)
    }

    public var iconName: String {
        switch self {
        case .asr: return "waveform.badge.mic"
        case .llm: return "sparkles"
        case .liveStreaming: return "waveform.badge.magnifyingglass"
        case .speaker: return "person.2.wave.2"
        case .obsidian: return "book.pages"
        case .memory: return "brain.head.profile"
        case .calendar: return "calendar.badge.clock"
        case .appearance: return "moon"
        case .language: return "globe"
        case .privacy: return "hand.raised.fill"
        }
    }

    public func localizedGroupName(isEnglish: Bool) -> String {
        switch self {
        case .asr, .llm, .liveStreaming, .speaker:
            return L10n.recordingAndNotesGroup(isEnglish)
        case .obsidian, .memory, .calendar:
            return L10n.knowledgeAndSyncGroup(isEnglish)
        case .appearance, .language, .privacy:
            return L10n.preferencesGroup(isEnglish)
        }
    }

    public var groupName: String {
        localizedGroupName(isEnglish: false)
    }

    public var iconColor: Color {
        switch self {
        case .asr: return MFTheme.iceCyan
        case .llm: return MFTheme.warmAmber
        case .liveStreaming: return MFTheme.iceCyan
        case .speaker: return MFTheme.softViolet
        case .obsidian: return MFTheme.warmAmber
        case .memory: return MFTheme.softViolet
        case .calendar: return MFTheme.mintGreen
        case .appearance: return MFTheme.iceCyan
        case .language: return MFTheme.mintGreen
        case .privacy: return MFTheme.coralRed
        }
    }
}

// MARK: - Main Settings View (ChatGPT-Style Grouped Navigation)

public struct SettingsView: View {
    @ObservedObject var store: MemoFlowStore
    @Environment(\.dismiss) private var dismiss
    @State private var choosingVault = false

    @State private var selectedDestination: SettingsDestination = .asr

    @State private var selectedASRProvider: ASRProviderOption = .siliconFlow
    @State private var selectedLLMProvider: LLMProviderOption = .deepSeek
    @State private var shareSiliconFlowKey: Bool = true

    @State private var asrAPIKeyInput: String = ""
    @State private var llmAPIKeyInput: String = ""
    @State private var showASRKeyPlain: Bool = false
    @State private var showLLMKeyPlain: Bool = false
    @State private var savedToastVisible: Bool = false

    // 动态模型同步与手动新增状态
    @State private var showingASRModelSheet: Bool = false
    @State private var showingLLMModelSheet: Bool = false
    @State private var isSyncingASRModels: Bool = false
    @State private var isSyncingLLMModels: Bool = false
    @State private var asrSyncStatusMessage: String?
    @State private var llmSyncStatusMessage: String?
    @State private var newASRModelIdInput: String = ""
    @State private var newLLMModelIdInput: String = ""
    @State private var showingAddASRModelField: Bool = false
    @State private var showingAddLLMModelField: Bool = false

    // 接口连通性测试状态
    @State private var isTestingASR: Bool = false
    @State private var asrTestResult: (success: Bool, message: String)? = nil
    @State private var isTestingLLM: Bool = false
    @State private var llmTestResult: (success: Bool, message: String)? = nil

    @State private var writableCalendars: [WritableContainerInfo] = []
    @State private var writableReminderLists: [WritableContainerInfo] = []
    @State private var showingResetConfirmation: Bool = false

    // P1-5 检索范围与个人记忆审阅管理状态
    @State private var customIncludedFolderInput: String = ""
    @State private var newMemoryCategory: PersonalMemoryCategory = .term
    @State private var newMemoryKeyInput: String = ""
    @State private var newMemoryValueInput: String = ""
    @State private var editingMemoryId: UUID? = nil
    @State private var editingMemoryCategory: PersonalMemoryCategory = .term
    @State private var editingMemoryKey: String = ""
    @State private var editingMemoryValue: String = ""

    public init(store: MemoFlowStore) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            MFTheme.sheetBg.ignoresSafeArea()
            MFTheme.ambientTopGlow.ignoresSafeArea()

            #if os(macOS)
            macTwoPaneLayout
            #else
            iosNavigationStack
            #endif
        }
        .focusEffectDisabled()
        .preferredColorScheme(store.preferences.appearanceTheme.colorScheme)
        .onAppear {
            loadCurrentSelectionState()
        }
        .onChange(of: store.preferences.llmBaseURL) { _, endpoint in
            llmAPIKeyInput = KeychainService.shared.readKey(for: .llmAPIKey, endpoint: endpoint) ?? ""
            store.revokeCloudProcessingConsent()
        }
        .onChange(of: store.preferences.asrBaseURL) { _, endpoint in
            asrAPIKeyInput = KeychainService.shared.readKey(for: .asrAPIKey, endpoint: endpoint) ?? ""
            store.revokeCloudProcessingConsent()
        }
        .fileImporter(isPresented: $choosingVault, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): store.bindObsidianVault(url)
            case .failure(let error): store.knowledgeStatus = "选择文件夹失败：\(error.localizedDescription)"
            }
        }
        .alert("恢复预置演示数据？", isPresented: $showingResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重置并清空当前记录", role: .destructive) {
                store.seedPRDDefaultScenarios()
                dismiss()
            }
        } message: {
            Text("将删除当前所有录音记录与生成笔记，恢复为初始测试场景数据。此操作不可撤销。")
        }
    }

    // MARK: - iOS Navigation Stack

    #if os(iOS)
    private var iosNavigationStack: some View {
        NavigationStack {
            iosHomeListView
                .navigationDestination(for: SettingsDestination.self) { dest in
                    destinationView(for: dest)
                }
        }
    }
    #endif

    // MARK: - Mac Two-Pane Layout

    #if os(macOS)
    private var macTwoPaneLayout: some View {
        HStack(spacing: 0) {
            macSidebarView
                .frame(width: 220)

            Divider().overlay(Color.white.opacity(0.08))

            destinationView(for: selectedDestination)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var isEnglish: Bool {
        store.preferences.appLanguage.isEnglish
    }

    private var macSidebarView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                MemoFlowWaveformBrandIcon(size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.serviceAndSettings(isEnglish))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(MFTheme.textPrimary)
                    Text(L10n.settingsCenterSubtitle(isEnglish))
                        .font(.system(size: 10))
                        .foregroundStyle(MFTheme.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(MFTheme.recessedBg.opacity(0.6))

            Divider().overlay(Color.white.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    macSidebarGroup(title: L10n.recordingAndNotesGroup(isEnglish), destinations: [.asr, .llm, .liveStreaming, .speaker])
                    macSidebarGroup(title: L10n.knowledgeAndSyncGroup(isEnglish), destinations: [.obsidian, .memory, .calendar])
                    macSidebarGroup(title: L10n.preferencesGroup(isEnglish), destinations: [.appearance, .language, .privacy])
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
        }
        .background(MFTheme.recessedBg.opacity(0.35))
    }

    private func macSidebarGroup(title: String, destinations: [SettingsDestination]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(MFTheme.textMuted)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)

            ForEach(destinations) { dest in
                if dest == .appearance {
                    macAppearanceSidebarRow
                } else if dest == .language {
                    macLanguageSidebarRow
                } else {
                    let isSelected = selectedDestination == dest
                    Button {
                        selectedDestination = dest
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: dest.iconName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(isSelected ? MFTheme.iceCyan : dest.iconColor)
                                .frame(width: 18)

                            Text(dest.localizedTitle(isEnglish: isEnglish))
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? MFTheme.textPrimary : MFTheme.textSecondary)

                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? MFTheme.iceCyan.opacity(0.12) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var macAppearanceSidebarRow: some View {
        Menu {
            Button {
                store.preferences.appearanceTheme = .system
                store.saveToDisk()
                showSavedFeedback()
            } label: {
                if store.preferences.appearanceTheme == .system {
                    Label(L10n.systemTheme(isEnglish), systemImage: "checkmark")
                } else {
                    Text(L10n.systemTheme(isEnglish))
                }
            }

            Button {
                store.preferences.appearanceTheme = .warmPaper
                store.saveToDisk()
                showSavedFeedback()
            } label: {
                if store.preferences.appearanceTheme == .warmPaper {
                    Label(L10n.lightTheme(isEnglish), systemImage: "checkmark")
                } else {
                    Text(L10n.lightTheme(isEnglish))
                }
            }

            Button {
                store.preferences.appearanceTheme = .darkNight
                store.saveToDisk()
                showSavedFeedback()
            } label: {
                if store.preferences.appearanceTheme == .darkNight {
                    Label(L10n.darkTheme(isEnglish), systemImage: "checkmark")
                } else {
                    Text(L10n.darkTheme(isEnglish))
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "moon")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MFTheme.iceCyan)
                    .frame(width: 18)

                Text(L10n.appearance(isEnglish))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(MFTheme.textSecondary)

                Spacer()

                Text(appearanceShortLabel(store.preferences.appearanceTheme))
                    .font(.system(size: 11))
                    .foregroundStyle(MFTheme.textMuted)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MFTheme.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
    }

    private var macLanguageSidebarRow: some View {
        Menu {
            Button {
                store.preferences.appLanguage = .system
                store.saveToDisk()
                showSavedFeedback()
            } label: {
                if store.preferences.appLanguage == .system {
                    Label(L10n.languageOptionTitle(.system, isEnglish: isEnglish), systemImage: "checkmark")
                } else {
                    Text(L10n.languageOptionTitle(.system, isEnglish: isEnglish))
                }
            }

            Button {
                store.preferences.appLanguage = .chinese
                store.saveToDisk()
                showSavedFeedback()
            } label: {
                if store.preferences.appLanguage == .chinese {
                    Label("简体中文", systemImage: "checkmark")
                } else {
                    Text("简体中文")
                }
            }

            Button {
                store.preferences.appLanguage = .english
                store.saveToDisk()
                showSavedFeedback()
            } label: {
                if store.preferences.appLanguage == .english {
                    Label("English", systemImage: "checkmark")
                } else {
                    Text("English")
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MFTheme.mintGreen)
                    .frame(width: 18)

                Text(L10n.language(isEnglish))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(MFTheme.textSecondary)

                Spacer()

                Text(L10n.languageShortLabel(store.preferences.appLanguage, isEnglish: isEnglish))
                    .font(.system(size: 11))
                    .foregroundStyle(MFTheme.textMuted)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MFTheme.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
    }
    #endif

    // MARK: - iOS Grouped Home List (ChatGPT Style)

    private var iosHomeListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header notice
                HStack(spacing: 12) {
                    MemoFlowWaveformBrandIcon(size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.serviceAndSettings(isEnglish))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(MFTheme.textPrimary)
                        Text(L10n.settingsHeaderNote(isEnglish))
                            .font(.caption2)
                            .foregroundStyle(MFTheme.textSecondary)
                    }
                    Spacer()
                    if savedToastVisible {
                        MFBadgePill(L10n.saved(isEnglish), color: MFTheme.mintGreen, icon: "checkmark.circle.fill")
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)

                // 1. 录音与整理
                iosGroupCard(title: L10n.recordingAndNotesGroup(isEnglish), destinations: [.asr, .llm, .liveStreaming, .speaker])

                // 2. 知识与联动
                iosGroupCard(title: L10n.knowledgeAndSyncGroup(isEnglish), destinations: [.obsidian, .memory, .calendar])

                // 3. 偏好与管理
                iosGroupCard(title: L10n.preferencesGroup(isEnglish), destinations: [.appearance, .language, .privacy])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(MFTheme.sheetBg)
        .navigationTitle(L10n.settings(isEnglish))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                closeButton
            }
        }
    }

    private func iosGroupCard(title: String, destinations: [SettingsDestination]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(MFTheme.textSecondary)
                .padding(.leading, 8)

            VStack(spacing: 0) {
                ForEach(Array(destinations.enumerated()), id: \.element) { index, dest in
                    if dest == .appearance {
                        iosAppearanceRow
                    } else if dest == .language {
                        iosLanguageRow
                    } else {
                        #if os(iOS)
                        NavigationLink(value: dest) {
                            iosRowContent(dest: dest)
                        }
                        .buttonStyle(.plain)
                        #else
                        Button {
                            selectedDestination = dest
                        } label: {
                            iosRowContent(dest: dest)
                        }
                        .buttonStyle(.plain)
                        #endif
                    }

                    if index < destinations.count - 1 {
                        Divider()
                            .padding(.leading, 50)
                            .opacity(0.25)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(MFTheme.resolveColor(
                        light: Color.white,
                        dark: Color.white.opacity(0.06)
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                MFTheme.resolveColor(
                                    light: Color.black.opacity(0.06),
                                    dark: Color.white.opacity(0.08)
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
    }

    private var iosAppearanceRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(MFTheme.iceCyan)
                .frame(width: 24, height: 24)

            Text(L10n.appearance(isEnglish))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(MFTheme.textPrimary)

            Spacer()

            Menu {
                Button {
                    store.preferences.appearanceTheme = .system
                    store.saveToDisk()
                    showSavedFeedback()
                } label: {
                    if store.preferences.appearanceTheme == .system {
                        Label(L10n.systemTheme(isEnglish), systemImage: "checkmark")
                    } else {
                        Text(L10n.systemTheme(isEnglish))
                    }
                }

                Button {
                    store.preferences.appearanceTheme = .warmPaper
                    store.saveToDisk()
                    showSavedFeedback()
                } label: {
                    if store.preferences.appearanceTheme == .warmPaper {
                        Label(L10n.lightTheme(isEnglish), systemImage: "checkmark")
                    } else {
                        Text(L10n.lightTheme(isEnglish))
                    }
                }

                Button {
                    store.preferences.appearanceTheme = .darkNight
                    store.saveToDisk()
                    showSavedFeedback()
                } label: {
                    if store.preferences.appearanceTheme == .darkNight {
                        Label(L10n.darkTheme(isEnglish), systemImage: "checkmark")
                    } else {
                        Text(L10n.darkTheme(isEnglish))
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(appearanceShortLabel(store.preferences.appearanceTheme))
                        .font(.system(size: 14))
                        .foregroundStyle(MFTheme.textSecondary)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MFTheme.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var iosLanguageRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(MFTheme.mintGreen)
                .frame(width: 24, height: 24)

            Text(L10n.language(isEnglish))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(MFTheme.textPrimary)

            Spacer()

            Menu {
                Button {
                    store.preferences.appLanguage = .system
                    store.saveToDisk()
                    showSavedFeedback()
                } label: {
                    if store.preferences.appLanguage == .system {
                        Label(L10n.languageOptionTitle(.system, isEnglish: isEnglish), systemImage: "checkmark")
                    } else {
                        Text(L10n.languageOptionTitle(.system, isEnglish: isEnglish))
                    }
                }

                Button {
                    store.preferences.appLanguage = .chinese
                    store.saveToDisk()
                    showSavedFeedback()
                } label: {
                    if store.preferences.appLanguage == .chinese {
                        Label("简体中文", systemImage: "checkmark")
                    } else {
                        Text("简体中文")
                    }
                }

                Button {
                    store.preferences.appLanguage = .english
                    store.saveToDisk()
                    showSavedFeedback()
                } label: {
                    if store.preferences.appLanguage == .english {
                        Label("English", systemImage: "checkmark")
                    } else {
                        Text("English")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(L10n.languageOptionTitle(store.preferences.appLanguage, isEnglish: isEnglish))
                        .font(.system(size: 14))
                        .foregroundStyle(MFTheme.textSecondary)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MFTheme.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func appearanceShortLabel(_ theme: AppearanceTheme) -> String {
        switch theme {
        case .system: return L10n.systemTheme(isEnglish)
        case .warmPaper: return L10n.lightTheme(isEnglish)
        case .darkNight: return L10n.darkTheme(isEnglish)
        }
    }

    private func iosRowContent(dest: SettingsDestination) -> some View {
        HStack(spacing: 12) {
            Image(systemName: dest.iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(dest.iconColor)
                .frame(width: 24, height: 24)

            Text(dest.localizedTitle(isEnglish: isEnglish))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(MFTheme.textPrimary)

            Spacer()

            Text(statusSummary(for: dest))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(MFTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 160, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MFTheme.textMuted.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var closeButton: some View {
        Button {
            saveAllAndDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MFTheme.textPrimary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(MFTheme.resolveColor(
                            light: Color.black.opacity(0.06),
                            dark: Color.white.opacity(0.14)
                        ))
                )
        }
        .buttonStyle(.plain)
        .help(L10n.closeSettings(isEnglish))
    }

    // MARK: - Status Summaries for Home Rows

    private func statusSummary(for dest: SettingsDestination) -> String {
        switch dest {
        case .asr:
            switch selectedASRProvider {
            case .appleLocal: return isEnglish ? "Apple Local Speech" : "Apple 本地识别"
            case .whisperLocal: return isEnglish ? "Whisper Local" : "Whisper 本机模型"
            case .siliconFlow:
                let short = store.preferences.asrModelName.components(separatedBy: "/").last ?? store.preferences.asrModelName
                return "硅基流动 · \(short.isEmpty ? "SenseVoice" : short)"
            case .groq: return "Groq · \(store.preferences.asrModelName)"
            case .openAI: return "OpenAI · \(store.preferences.asrModelName)"
            case .custom: return isEnglish ? "Custom ASR" : "自定义 ASR"
            }
        case .llm:
            switch selectedLLMProvider {
            case .localRules: return isEnglish ? "Local Rules" : "本地规则引擎"
            case .siliconFlow:
                let short = store.preferences.llmModelName.components(separatedBy: "/").last ?? store.preferences.llmModelName
                return "硅基流动 · \(short.isEmpty ? "Qwen2.5-7B" : short)"
            case .deepSeek:
                let short = store.preferences.llmModelName.components(separatedBy: "/").last ?? store.preferences.llmModelName
                return "DeepSeek · \(short)"
            case .qwen: return "通义千问 · \(store.preferences.llmModelName)"
            case .doubao: return "豆包 · \(store.preferences.llmModelName)"
            case .glm: return "智谱 GLM · \(store.preferences.llmModelName)"
            case .kimi: return "Kimi · \(store.preferences.llmModelName)"
            case .minimax: return "MiniMax · \(store.preferences.llmModelName)"
            case .qianfan: return "百度千帆 · \(store.preferences.llmModelName)"
            case .openAI: return "OpenAI · \(store.preferences.llmModelName)"
            case .custom: return isEnglish ? "Custom LLM" : "自定义 LLM"
            }
        case .liveStreaming:
            return store.preferences.liveStreamingTranscriptionEnabled ? L10n.liveStreamingEnabled(isEnglish) : L10n.liveStreamingDisabled(isEnglish)
        case .speaker:
            return store.preferences.speakerNicknameTheme.displayTitle
        case .obsidian:
            if let path = store.preferences.obsidianVaultRootPath, !path.isEmpty {
                let name = URL(fileURLWithPath: path).lastPathComponent
                return L10n.connected(isEnglish, name: name.isEmpty ? "Vault" : name)
            }
            return L10n.notConnected(isEnglish)
        case .memory:
            let pending = store.personalMemories.filter { $0.status == .pendingReview }.count
            let confirmed = store.personalMemories.filter { $0.status == .confirmed }.count
            if pending > 0 { return L10n.pendingMemories(isEnglish, count: pending) }
            if confirmed > 0 { return L10n.activeMemories(isEnglish, count: confirmed) }
            return L10n.memoryDisabled(isEnglish)
        case .calendar:
            switch store.preferences.calendarCreationMode {
            case .autoCreate: return L10n.calendarAutoCreate(isEnglish)
            case .reviewFirst: return L10n.calendarReviewFirst(isEnglish)
            }
        case .appearance:
            switch store.preferences.appearanceTheme {
            case .warmPaper: return isEnglish ? "Warm Paper (Light)" : "暖纸 (Light)"
            case .darkNight: return isEnglish ? "Dark Night (Dark)" : "夜读 (Dark)"
            case .system: return isEnglish ? "System" : "跟随系统"
            }
        case .language:
            return L10n.languageOptionTitle(store.preferences.appLanguage, isEnglish: isEnglish)
        case .privacy:
            let isConsented = store.processingConsent.grantedAt != nil && store.processingConsent.revokedAt == nil
            return isConsented ? L10n.cloudAuthorized(isEnglish) : L10n.onDeviceOnly(isEnglish)
        }
    }

    // MARK: - Subpage Destination View Router

    @ViewBuilder
    private func destinationView(for dest: SettingsDestination) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                #if os(macOS)
                macSubpageHeader(dest: dest)
                #endif

                switch dest {
                case .asr: asrSubpageContent
                case .llm: llmSubpageContent
                case .liveStreaming: liveStreamingSubpageContent
                case .speaker: speakerSubpageContent
                case .obsidian: obsidianSubpageContent
                case .memory: memorySubpageContent
                case .calendar: calendarSubpageContent
                case .appearance: appearanceSubpageContent
                case .language: languageSubpageContent
                case .privacy: privacySubpageContent
                }
            }
            .padding(18)
        }
        .background(MFTheme.sheetBg)
        .navigationTitle(dest.localizedTitle(isEnglish: isEnglish))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    #if os(macOS)
    private func macSubpageHeader(dest: SettingsDestination) -> some View {
        HStack(spacing: 12) {
            Image(systemName: dest.iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(dest.iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(dest.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(MFTheme.textPrimary)
                Text("\(dest.groupName) · 设置项")
                    .font(.caption2)
                    .foregroundStyle(MFTheme.textSecondary)
            }

            Spacer()

            if savedToastVisible {
                MFBadgePill("已保存", color: MFTheme.mintGreen, icon: "checkmark.circle.fill")
                    .transition(.opacity)
            }

            closeButton
        }
        .padding(.bottom, 6)
    }
    #endif

    // MARK: - 1. ASR Subpage Content

    private var asrSubpageContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Status bar
            HStack {
                Text("服务状态")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MFTheme.textSecondary)
                Spacer()
                statusPill(
                    isReady: selectedASRProvider == .whisperLocal ? localWhisperReady :
                        (!selectedASRProvider.requiresAPIKey || !asrAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                    readyText: selectedASRProvider == .appleLocal ? "端侧免 Key" :
                        (selectedASRProvider == .whisperLocal ? "本机模型就绪" : "已配置密钥"),
                    emptyText: selectedASRProvider == .whisperLocal ? "需安装本机模型" : "待配置 API Key"
                )
            }

            // Provider selection
            Text("选择服务商")
                .font(.caption.weight(.bold))
                .foregroundStyle(MFTheme.textSecondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                ForEach(ASRProviderOption.availableCases) { option in
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

            Link("注册硅基流动账号（免费获取 API Key）↗", destination: URL(string: "https://cloud.siliconflow.cn/i/vZfzXQCz")!)
                .font(.caption)
                .foregroundStyle(MFTheme.iceCyan)

            // Model selector
            if selectedASRProvider != .custom {
                modelSelectorCardRow(
                    title: "选用语音识别模型",
                    modelLabel: currentASRModelLabel,
                    modelId: store.preferences.asrModelName,
                    icon: "waveform",
                    isOffline: selectedASRProvider == .appleLocal
                ) {
                    showingASRModelSheet = true
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("自定义 Base URL（如 https://api.example.com/v1）", text: $store.preferences.asrBaseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("自定义语音模型名", text: $store.preferences.asrModelName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // API Key input
            if selectedASRProvider.requiresAPIKey {
                apiKeyInputRow(
                    title: "\(selectedASRProvider.title) API Key",
                    placeholder: "点击右侧「粘贴」直接填入密钥",
                    text: $asrAPIKeyInput,
                    isPlainVisible: $showASRKeyPlain
                )

                // Connection Test Button
                HStack(spacing: 10) {
                    Button {
                        testASRConnection()
                    } label: {
                        HStack(spacing: 6) {
                            if isTestingASR {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "network")
                            }
                            Text(isTestingASR ? "正在测试连通性…" : "测试 ASR 接口连通性")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MFTheme.iceCyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(isTestingASR)

                    if let res = asrTestResult {
                        Text(res.message)
                            .font(.caption2)
                            .foregroundStyle(res.success ? MFTheme.mintGreen : MFTheme.coralRed)
                            .lineLimit(2)
                    }
                }
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 16)
        .sheet(isPresented: $showingASRModelSheet) {
            ModelPickerModalView(
                title: "选择语音转写模型 (ASR)",
                subtitle: "点击切换，设置即刻生效",
                iconName: "waveform",
                currentSelectedId: store.preferences.asrModelName,
                models: combinedASRModels,
                presetIds: Set(selectedASRProvider.presetModels.map(\.id)),
                isSyncing: isSyncingASRModels,
                syncStatusMessage: asrSyncStatusMessage,
                allowsSync: selectedASRProvider.requiresAPIKey,
                onSelectModel: { id in
                    store.preferences.asrModelName = id
                    autoSaveKeys()
                },
                onSyncRemote: {
                    Task { await syncRemoteASRModels() }
                },
                onAddCustomModel: { id in
                    newASRModelIdInput = id
                    addCustomASRModel()
                },
                onDismiss: {
                    showingASRModelSheet = false
                }
            )
        }
    }

    // MARK: - 2. LLM Subpage Content

    private var llmSubpageContent: some View {
        let isSharingKey = (selectedASRProvider == .siliconFlow && selectedLLMProvider == .siliconFlow && shareSiliconFlowKey)
        let effectiveLLMKey = isSharingKey ? asrAPIKeyInput : llmAPIKeyInput

        return VStack(alignment: .leading, spacing: 14) {
            // Status bar
            HStack {
                Text("服务状态")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MFTheme.textSecondary)
                Spacer()
                statusPill(
                    isReady: !selectedLLMProvider.requiresAPIKey || !effectiveLLMKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    readyText: selectedLLMProvider == .localRules ? "本地规则就绪" : "已配置密钥",
                    emptyText: "待配置 API Key"
                )
            }

            // Provider selection
            Text("选择服务商")
                .font(.caption.weight(.bold))
                .foregroundStyle(MFTheme.textSecondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
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

            Link("注册硅基流动账号（免费获取 API Key）↗", destination: URL(string: "https://cloud.siliconflow.cn/i/vZfzXQCz")!)
                .font(.caption)
                .foregroundStyle(MFTheme.warmAmber)

            // Model selector
            if selectedLLMProvider != .custom {
                modelSelectorCardRow(
                    title: "选用 AI 整理模型",
                    modelLabel: currentLLMModelLabel,
                    modelId: store.preferences.llmModelName,
                    icon: "sparkles",
                    isOffline: selectedLLMProvider == .localRules
                ) {
                    showingLLMModelSheet = true
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("自定义 LLM Base URL", text: $store.preferences.llmBaseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("自定义 LLM 模型名", text: $store.preferences.llmModelName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // SiliconFlow key reuse toggle
            if selectedASRProvider == .siliconFlow && selectedLLMProvider == .siliconFlow {
                Toggle("直接复用上方「硅基流动」API Key（免填第二次）", isOn: $shareSiliconFlowKey)
                    .font(.caption.weight(.medium))
                    .padding(10)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            // API Key input
            if selectedLLMProvider.requiresAPIKey && !isSharingKey {
                apiKeyInputRow(
                    title: "\(selectedLLMProvider.title) API Key",
                    placeholder: "点击右侧「粘贴」直接填入密钥",
                    text: $llmAPIKeyInput,
                    isPlainVisible: $showLLMKeyPlain
                )
            }

            // Default Note Mode Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("默认整理模式（录音完成后默认生成的笔记形态）")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MFTheme.textSecondary)

                Picker("默认整理模式", selection: Binding(
                    get: { store.preferences.defaultNoteMode },
                    set: {
                        store.preferences.defaultNoteMode = $0
                        store.saveToDisk()
                        showSavedFeedback()
                    }
                )) {
                    ForEach(NoteMode.allCases, id: \.self) { mode in
                        Text(mode.displayTitle).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Connection Test Button
            if selectedLLMProvider.requiresAPIKey {
                HStack(spacing: 10) {
                    Button {
                        testLLMConnection()
                    } label: {
                        HStack(spacing: 6) {
                            if isTestingLLM {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "network")
                            }
                            Text(isTestingLLM ? "正在测试连通性…" : "测试 LLM 接口连通性")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MFTheme.warmAmber)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(isTestingLLM)

                    if let res = llmTestResult {
                        Text(res.message)
                            .font(.caption2)
                            .foregroundStyle(res.success ? MFTheme.mintGreen : MFTheme.coralRed)
                            .lineLimit(2)
                    }
                }
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 16)
        .sheet(isPresented: $showingLLMModelSheet) {
            ModelPickerModalView(
                title: "选择 AI 整理模型 (LLM)",
                subtitle: "点击切换，设置即刻生效",
                iconName: "brain.head.profile",
                currentSelectedId: store.preferences.llmModelName,
                models: combinedLLMModels,
                presetIds: Set(selectedLLMProvider.presetModels.map(\.id)),
                isSyncing: isSyncingLLMModels,
                syncStatusMessage: llmSyncStatusMessage,
                allowsSync: selectedLLMProvider.requiresAPIKey,
                onSelectModel: { id in
                    store.preferences.llmModelName = id
                    autoSaveKeys()
                },
                onSyncRemote: {
                    Task { await syncRemoteLLMModels(effectiveKey: effectiveLLMKey) }
                },
                onAddCustomModel: { id in
                    newLLMModelIdInput = id
                    addCustomLLMModel()
                },
                onDismiss: {
                    showingLLMModelSheet = false
                }
            )
        }
    }

    // MARK: - 3. Live Streaming Subpage Content

    private var liveStreamingSubpageContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("开启边录边整理模式", isOn: Binding(
                get: { store.preferences.liveStreamingTranscriptionEnabled },
                set: {
                    store.preferences.liveStreamingTranscriptionEnabled = $0
                    store.saveToDisk()
                    showSavedFeedback()
                }
            ))
            .font(.subheadline.weight(.semibold))
            .toggleStyle(SwitchToggleStyle(tint: MFTheme.iceCyan))

            Text("录音过程中持续增量分段转写并生成可查看的笔记草稿；停止后复用已完成结果，只处理剩余片段。原音频始终完整安全保存在本地。")
                .font(.caption)
                .foregroundStyle(MFTheme.textSecondary)
                .lineSpacing(3)
        }
        .mfGlassCard(cornerRadius: 16, padding: 16)
    }

    // MARK: - 4. Speaker & Nickname Subpage Content

    private var speakerSubpageContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("角色昵称主题")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MFTheme.textSecondary)

                Picker("主题", selection: Binding(
                    get: { store.preferences.speakerNicknameTheme },
                    set: {
                        store.preferences.speakerNicknameTheme = $0
                        store.saveToDisk()
                        showSavedFeedback()
                    }
                )) {
                    ForEach(SpeakerNicknameTheme.allCases, id: \.self) { theme in
                        Text(theme.displayTitle).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("个人声纹档案")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MFTheme.textSecondary)

                if let profile = store.preferences.userVoiceProfile {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.featureDescription)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MFTheme.textPrimary)
                            Text("已录入（\(Int(profile.sampleDuration)) 秒）· 录音整理时自动标记为本人发言")
                                .font(.caption2)
                                .foregroundStyle(MFTheme.textSecondary)
                        }
                        Spacer()
                        Button("清除档案") {
                            store.deleteVoiceProfile()
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    HStack {
                        Text("暂未录入声纹档案")
                            .font(.caption2)
                            .foregroundStyle(MFTheme.textMuted)
                        Spacer()
                        Button("录入声纹档案") {
                            store.enrollVoiceProfile(sampleDuration: 6.0)
                        }
                        .font(.caption2.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Text("提示：在单篇笔记的逐字稿中点击发言人，可随时手动修改姓名并级联同步。")
                .font(.caption2)
                .foregroundStyle(MFTheme.textMuted)
        }
        .mfGlassCard(cornerRadius: 16, padding: 16)
    }

    // MARK: - 5. Obsidian Subpage Content

    private var obsidianSubpageContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("当前绑定的笔记库根目录")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MFTheme.textSecondary)
                    Text(store.preferences.obsidianVaultRootPath ?? "尚未选择 Obsidian 库目录")
                        .font(.caption.monospaced())
                        .foregroundStyle(MFTheme.textPrimary)
                        .lineLimit(1)
                }
                Spacer()
                Button(store.preferences.obsidianVaultRootPath == nil ? "选择文件夹…" : "更换文件夹…") {
                    choosingVault = true
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
            }

            Toggle("AI 整理完成后自动写入 Obsidian 库", isOn: Binding(
                get: { store.preferences.autoExportToObsidianOnComplete },
                set: {
                    store.preferences.autoExportToObsidianOnComplete = $0
                    store.saveToDisk()
                    showSavedFeedback()
                }
            ))
            .font(.caption)

            Toggle("跨设备同步音频副本至笔记库附件目录 (P2-7)", isOn: Binding(
                get: { store.preferences.audioSyncMode == .vaultAttachmentCopy },
                set: {
                    store.preferences.audioSyncMode = $0 ? .vaultAttachmentCopy : .localOnly
                    store.saveToDisk()
                    showSavedFeedback()
                }
            ))
            .font(.caption)

            if store.preferences.audioSyncMode == .vaultAttachmentCopy {
                VStack(alignment: .leading, spacing: 4) {
                    Text("附件相对存放路径")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(MFTheme.textSecondary)
                    TextField("例如：MemoFlow笔记/Attachments", text: Binding(
                        get: { store.preferences.obsidianAudioAttachmentSubfolder },
                        set: {
                            store.preferences.obsidianAudioAttachmentSubfolder = $0
                            store.saveToDisk()
                            showSavedFeedback()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Obsidian 目标存放子目录")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(MFTheme.textSecondary)
                TextField("如：MemoFlow笔记", text: Binding(
                    get: { store.preferences.obsidianTargetSubfolder },
                    set: {
                        store.preferences.obsidianTargetSubfolder = $0
                        store.saveToDisk()
                        showSavedFeedback()
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 16)
    }

    // MARK: - 6. Personal Memory Subpage Content

    private var memorySubpageContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("个人记忆管理 (P1-5)", systemImage: "brain.head.profile")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(MFTheme.softViolet)
                Text("记录您独特的专有名词、业务术语、人际关系与项目代号。AI 在整理时会参考已确认记忆，输出更懂您的笔记。")
                    .font(.caption2)
                    .foregroundStyle(MFTheme.textSecondary)
            }

            memoryPendingSection
            memoryConfirmedSection
            memoryManualAddSection
        }
        .mfGlassCard(cornerRadius: 16, padding: 16)
    }

    @ViewBuilder
    private var memoryPendingSection: some View {
        let pending = store.personalMemories.filter { $0.status == .pendingReview }
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("待确认候选记忆 (\(pending.count))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MFTheme.warmAmber)
                    Spacer()
                    Button("一键采纳全部") {
                        for item in pending {
                            store.confirmPersonalMemory(item.id)
                        }
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(MFTheme.iceCyan)
                }

                ForEach(pending) { item in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(item.category.displayTitle) · \(item.key)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MFTheme.textPrimary)
                            Text(item.value)
                                .font(.caption2)
                                .foregroundStyle(MFTheme.textSecondary)
                        }
                        Spacer()
                        Button("采纳") {
                            store.confirmPersonalMemory(item.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)

                        Button("忽略") {
                            store.deletePersonalMemory(item.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    private var memoryConfirmedSection: some View {
        let confirmed = store.personalMemories.filter { $0.status == .confirmed }
        VStack(alignment: .leading, spacing: 8) {
            Text("已确认生效的记忆 (\(confirmed.count))")
                .font(.caption.weight(.bold))
                .foregroundStyle(MFTheme.textSecondary)

            if confirmed.isEmpty {
                Text("暂无生效记忆，可在下方手动添加或由录音整理时自动发现。")
                    .font(.caption2)
                    .foregroundStyle(MFTheme.textMuted)
            } else {
                ForEach(confirmed) { item in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(item.category.displayTitle) · \(item.key)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MFTheme.textPrimary)
                            Text(item.value)
                                .font(.caption2)
                                .foregroundStyle(MFTheme.textSecondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            store.deletePersonalMemory(item.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(MFTheme.coralRed)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var memoryManualAddSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("+ 手动添加一条记忆")
                .font(.caption.weight(.bold))
                .foregroundStyle(MFTheme.iceCyan)

            HStack(spacing: 6) {
                Picker("", selection: $newMemoryCategory) {
                    ForEach(PersonalMemoryCategory.allCases, id: \.self) { c in
                        Text(c.displayTitle).tag(c)
                    }
                }
                .frame(width: 90)

                TextField("条目/术语名", text: $newMemoryKeyInput)
                    .textFieldStyle(.roundedBorder)

                TextField("释义/说明", text: $newMemoryValueInput)
                    .textFieldStyle(.roundedBorder)

                Button("保存") {
                    let k = newMemoryKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    let v = newMemoryValueInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !k.isEmpty, !v.isEmpty else { return }
                    store.addPersonalMemory(category: newMemoryCategory, key: k, value: v, status: .confirmed)
                    newMemoryKeyInput = ""
                    newMemoryValueInput = ""
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    // MARK: - 7. Calendar Subpage Content

    private var calendarSubpageContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("日程创建模式")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MFTheme.textSecondary)

                Picker("创建模式", selection: Binding(
                    get: { store.preferences.calendarCreationMode },
                    set: {
                        store.preferences.calendarCreationMode = $0
                        store.saveToDisk()
                        showSavedFeedback()
                    }
                )) {
                    Text("需手动确认").tag(CalendarCreationMode.reviewFirst)
                    Text("智能自动创建").tag(CalendarCreationMode.autoCreate)
                }
                .pickerStyle(.segmented)
            }

            if !writableCalendars.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("目标系统日历：")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(MFTheme.textSecondary)
                    Picker("目标日历", selection: Binding(
                        get: { store.preferences.preferredCalendarIdentifier ?? writableCalendars.first?.id ?? "" },
                        set: {
                            store.preferences.preferredCalendarIdentifier = $0
                            store.saveToDisk()
                            showSavedFeedback()
                        }
                    )) {
                        ForEach(writableCalendars) { cal in
                            Text(cal.title).tag(cal.id)
                        }
                    }
                }
            }

            if !writableReminderLists.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("目标系统提醒事项列表：")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(MFTheme.textSecondary)
                    Picker("目标提醒事项", selection: Binding(
                        get: { store.preferences.preferredReminderListIdentifier ?? writableReminderLists.first?.id ?? "" },
                        set: {
                            store.preferences.preferredReminderListIdentifier = $0
                            store.saveToDisk()
                            showSavedFeedback()
                        }
                    )) {
                        ForEach(writableReminderLists) { rem in
                            Text(rem.title).tag(rem.id)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("默认日程时长")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MFTheme.textSecondary)

                Picker("时长", selection: Binding(
                    get: { store.preferences.defaultEventDurationMinutes },
                    set: {
                        store.preferences.defaultEventDurationMinutes = $0
                        store.saveToDisk()
                        showSavedFeedback()
                    }
                )) {
                    Text("15 分钟").tag(15)
                    Text("30 分钟").tag(30)
                    Text("60 分钟").tag(60)
                }
                .pickerStyle(.segmented)
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 16)
        .onAppear {
            refreshContainers()
        }
    }

    // MARK: - 8. Appearance Subpage Content

    private var appearanceSubpageContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.appearance(isEnglish))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MFTheme.textPrimary)
                Spacer()
                Picker(L10n.appearance(isEnglish), selection: Binding(
                    get: { store.preferences.appearanceTheme },
                    set: {
                        store.preferences.appearanceTheme = $0
                        store.saveToDisk()
                        showSavedFeedback()
                    }
                )) {
                    Text(L10n.systemTheme(isEnglish)).tag(AppearanceTheme.system)
                    Text(L10n.lightTheme(isEnglish)).tag(AppearanceTheme.warmPaper)
                    Text(L10n.darkTheme(isEnglish)).tag(AppearanceTheme.darkNight)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 16)
    }

    // MARK: - 9. Language Subpage Content

    private var languageSubpageContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.language(isEnglish))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MFTheme.textPrimary)
                Spacer()
                Picker(L10n.language(isEnglish), selection: Binding(
                    get: { store.preferences.appLanguage },
                    set: {
                        store.preferences.appLanguage = $0
                        store.saveToDisk()
                        showSavedFeedback()
                    }
                )) {
                    Text(L10n.languageOptionTitle(.system, isEnglish: isEnglish)).tag(AppLanguage.system)
                    Text("简体中文").tag(AppLanguage.chinese)
                    Text("English").tag(AppLanguage.english)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 16)
    }

    // MARK: - 10. Privacy & Data Subpage Content

    private var privacySubpageContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Cloud Processing Consent
            let isConsented = store.processingConsent.grantedAt != nil && store.processingConsent.revokedAt == nil
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("云端处理授权")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MFTheme.textPrimary)
                    Text(isConsented ? "已授权：录音可使用云端 API" : "未授权：仅允许在端侧离线运行")
                        .font(.caption2)
                        .foregroundStyle(MFTheme.textSecondary)
                }
                Spacer()
                if isConsented {
                    Button("撤回授权") {
                        store.revokeCloudProcessingConsent()
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                } else {
                    Button("授予授权") {
                        store.grantCloudProcessingConsent(rememberPreference: true)
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                }
            }

            Toggle("允许向云端大模型发送本地检索上下文与个人记忆 (P1-5)", isOn: Binding(
                get: { store.preferences.allowSendingKnowledgeToCloudLLM },
                set: {
                    store.preferences.allowSendingKnowledgeToCloudLLM = $0
                    store.saveToDisk()
                    showSavedFeedback()
                }
            ))
            .font(.caption)

            Divider().opacity(0.1)

            // Local storage info
            VStack(alignment: .leading, spacing: 4) {
                Text("本地存储位置：")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(MFTheme.textSecondary)
                Text(store.persistenceURL.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(MFTheme.textPrimary)
                    .lineLimit(2)
            }

            Divider().opacity(0.1)

            // Reset demo data
            Button(role: .destructive) {
                showingResetConfirmation = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                    Text("恢复出厂预置演示场景数据…")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(MFTheme.coralRed)
            }
            .buttonStyle(.plain)
        }
        .mfGlassCard(cornerRadius: 16, padding: 16)
    }

    // MARK: - Helper Methods & Actions

    private func showSavedFeedback() {
        withAnimation { savedToastVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { self.savedToastVisible = false }
        }
    }

    private func saveAllAndDismiss() {
        autoSaveKeys()
        store.saveToDisk()
        dismiss()
    }

    private func autoSaveKeys() {
        let asrSaved = KeychainService.shared.saveKey(asrAPIKeyInput, for: .asrAPIKey, endpoint: store.preferences.asrBaseURL)
        let llmSaved: Bool
        if selectedASRProvider == .siliconFlow && selectedLLMProvider == .siliconFlow && shareSiliconFlowKey {
            llmSaved = KeychainService.shared.saveKey(asrAPIKeyInput, for: .llmAPIKey, endpoint: store.preferences.llmBaseURL)
        } else {
            llmSaved = KeychainService.shared.saveKey(llmAPIKeyInput, for: .llmAPIKey, endpoint: store.preferences.llmBaseURL)
        }
        if asrSaved || llmSaved {
            showSavedFeedback()
        }
        store.saveToDisk()
    }

    private func loadCurrentSelectionState() {
        // Match ASR provider
        if store.preferences.asrEngineMode == .appleOnDevice {
            selectedASRProvider = .appleLocal
        } else if store.preferences.asrEngineMode == .localWhisper {
            selectedASRProvider = .whisperLocal
        } else if store.preferences.asrBaseURL.contains("siliconflow") {
            selectedASRProvider = .siliconFlow
        } else if store.preferences.asrBaseURL.contains("groq") {
            selectedASRProvider = .groq
        } else if store.preferences.asrBaseURL.contains("openai") {
            selectedASRProvider = .openAI
        } else {
            selectedASRProvider = .custom
        }

        // Match LLM provider
        if store.preferences.llmBaseURL.isEmpty || store.preferences.llmModelName == "local-heuristic" {
            selectedLLMProvider = .localRules
        } else if store.preferences.llmBaseURL.contains("siliconflow") {
            selectedLLMProvider = .siliconFlow
        } else if store.preferences.llmBaseURL.contains("deepseek") {
            selectedLLMProvider = .deepSeek
        } else if store.preferences.llmBaseURL.contains("aliyuncs") || store.preferences.llmBaseURL.contains("dashscope") {
            selectedLLMProvider = .qwen
        } else if store.preferences.llmBaseURL.contains("volces") {
            selectedLLMProvider = .doubao
        } else if store.preferences.llmBaseURL.contains("bigmodel") {
            selectedLLMProvider = .glm
        } else if store.preferences.llmBaseURL.contains("moonshot") {
            selectedLLMProvider = .kimi
        } else if store.preferences.llmBaseURL.contains("minimax") {
            selectedLLMProvider = .minimax
        } else if store.preferences.llmBaseURL.contains("baidubce") || store.preferences.llmBaseURL.contains("qianfan") {
            selectedLLMProvider = .qianfan
        } else if store.preferences.llmBaseURL.contains("openai") {
            selectedLLMProvider = .openAI
        } else {
            selectedLLMProvider = .custom
        }

        asrAPIKeyInput = KeychainService.shared.readKey(for: .asrAPIKey, endpoint: store.preferences.asrBaseURL) ?? ""
        llmAPIKeyInput = KeychainService.shared.readKey(for: .llmAPIKey, endpoint: store.preferences.llmBaseURL) ?? ""
        refreshContainers()
    }

    private func selectASRProvider(_ option: ASRProviderOption) {
        selectedASRProvider = option
        switch option {
        case .appleLocal:
            store.preferences.asrEngineMode = .appleOnDevice
            store.preferences.asrModelName = "apple-speech"
        case .whisperLocal:
            store.preferences.asrEngineMode = .localWhisper
            store.preferences.asrModelName = "ggml-large-v3-turbo-q5_0.bin"
        case .siliconFlow, .groq, .openAI:
            store.preferences.asrEngineMode = .openAICompatible
            store.preferences.asrBaseURL = option.defaultBaseURL
            store.preferences.asrModelName = option.defaultModelName
        case .custom:
            store.preferences.asrEngineMode = .openAICompatible
        }
        asrAPIKeyInput = KeychainService.shared.readKey(for: .asrAPIKey, endpoint: store.preferences.asrBaseURL) ?? ""
        autoSaveKeys()
    }

    private func selectLLMProvider(_ option: LLMProviderOption) {
        selectedLLMProvider = option
        if option != .custom {
            store.preferences.llmBaseURL = option.defaultBaseURL
            store.preferences.llmModelName = option.defaultModelName
        }
        llmAPIKeyInput = KeychainService.shared.readKey(for: .llmAPIKey, endpoint: store.preferences.llmBaseURL) ?? ""
        autoSaveKeys()
    }

    private func testASRConnection() {
        if selectedASRProvider == .appleLocal {
            asrTestResult = (true, "Apple 语音识别：端侧系统组件已就绪，免网络连接")
            return
        }
        if selectedASRProvider == .whisperLocal {
            asrTestResult = localWhisperReady
                ? (true, "Whisper 本机模型已就绪")
                : (false, "本地 Whisper 模型未检测到，请先下载模型文件")
            return
        }
        let key = asrAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            asrTestResult = (false, "请先填入或粘贴 API Key")
            return
        }
        isTestingASR = true
        asrTestResult = nil
        Task {
            do {
                guard let url = URL(string: store.preferences.asrBaseURL)?
                    .appendingPathComponent("models") else {
                    await MainActor.run {
                        self.isTestingASR = false
                        self.asrTestResult = (false, "无效的 Base URL")
                    }
                    return
                }
                var req = URLRequest(url: url)
                req.httpMethod = "GET"
                req.timeoutInterval = 10
                req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: req)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                await MainActor.run {
                    self.isTestingASR = false
                    if (200..<300).contains(code) {
                        self.asrTestResult = (true, "ASR 接口校验通过，连接正常！")
                    } else {
                        let errStr = String(data: data, encoding: .utf8) ?? ""
                        self.asrTestResult = (false, "返回异常 (HTTP \(code))：\(errStr.prefix(80))")
                    }
                }
            } catch {
                await MainActor.run {
                    self.isTestingASR = false
                    self.asrTestResult = (false, "网络连接失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func testLLMConnection() {
        if selectedLLMProvider == .localRules {
            llmTestResult = (true, "本地规则引擎：内置离线规则已就绪，免网络")
            return
        }
        let effectiveKey = (selectedASRProvider == .siliconFlow && selectedLLMProvider == .siliconFlow && shareSiliconFlowKey)
            ? asrAPIKeyInput : llmAPIKeyInput
        let key = effectiveKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            llmTestResult = (false, "请先填入或粘贴 API Key")
            return
        }
        isTestingLLM = true
        llmTestResult = nil
        Task {
            do {
                guard let url = URL(string: store.preferences.llmBaseURL)?
                    .appendingPathComponent("models") else {
                    await MainActor.run {
                        self.isTestingLLM = false
                        self.llmTestResult = (false, "无效的 Base URL")
                    }
                    return
                }
                var req = URLRequest(url: url)
                req.httpMethod = "GET"
                req.timeoutInterval = 10
                req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: req)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                await MainActor.run {
                    self.isTestingLLM = false
                    if (200..<300).contains(code) {
                        self.llmTestResult = (true, "LLM 接口校验通过，模型服务正常！")
                    } else {
                        let errStr = String(data: data, encoding: .utf8) ?? ""
                        self.llmTestResult = (false, "返回异常 (HTTP \(code))：\(errStr.prefix(80))")
                    }
                }
            } catch {
                await MainActor.run {
                    self.isTestingLLM = false
                    self.llmTestResult = (false, "网络连接失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private var localWhisperReady: Bool {
        #if os(macOS)
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MemoFlow/models")
        let modelPath = directory.appendingPathComponent("ggml-large-v3-turbo-q5_0.bin").path
        return FileManager.default.fileExists(atPath: modelPath)
        #else
        return false
        #endif
    }

    private func refreshContainers() {
        writableCalendars = EventKitIntegrationService.shared.writableCalendars()
        writableReminderLists = EventKitIntegrationService.shared.writableReminderLists()
    }

    // MARK: - Dynamic Model Lists & Sync

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

    private var currentASRModelLabel: String {
        if let match = combinedASRModels.first(where: { $0.id == store.preferences.asrModelName }) {
            return match.label
        }
        return store.preferences.asrModelName.isEmpty ? "未选择识别模型" : store.preferences.asrModelName
    }

    private var currentLLMModelLabel: String {
        if let match = combinedLLMModels.first(where: { $0.id == store.preferences.llmModelName }) {
            return match.label
        }
        return store.preferences.llmModelName.isEmpty ? "未选择整理模型" : store.preferences.llmModelName
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
                ? "已从服务端拉取并新增 \(addedCount) 个语音模型。"
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
                ? "已从服务端拉取并新增 \(addedCount) 个模型。"
                : "已与服务端同步（共检测到 \(fetched.count) 个可用模型，当前列表已是最新）。"
        } catch {
            llmSyncStatusMessage = "拉取失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Reusable UI Components

    private func statusPill(isReady: Bool, readyText: String, emptyText: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isReady ? MFTheme.mintGreen : MFTheme.warmAmber)
                .frame(width: 6, height: 6)
            Text(isReady ? readyText : emptyText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isReady ? MFTheme.mintGreen : MFTheme.warmAmber)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isReady ? MFTheme.mintGreen.opacity(0.12) : MFTheme.warmAmber.opacity(0.12))
        )
    }

    private func providerOptionTile(
        title: String,
        badge: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? MFTheme.iceCyan : MFTheme.textSecondary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(MFTheme.iceCyan)
                    }
                }
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MFTheme.textPrimary)
                Text(badge)
                    .font(.system(size: 9))
                    .foregroundStyle(MFTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? MFTheme.iceCyan.opacity(0.12) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSelected ? MFTheme.iceCyan : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func modelSelectorCardRow(
        title: String,
        modelLabel: String,
        modelId: String,
        icon: String,
        isOffline: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [MFTheme.iceCyan, MFTheme.iceBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(MFTheme.textSecondary)

                        if isOffline {
                            Text("端侧免密钥")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(MFTheme.mintGreen.opacity(0.18), in: Capsule())
                                .foregroundStyle(MFTheme.mintGreen)
                        }
                    }

                    Text(modelLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MFTheme.textPrimary)
                        .lineLimit(1)

                    Text(modelId)
                        .font(.caption2.monospaced())
                        .foregroundStyle(MFTheme.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("选择模型")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MFTheme.iceCyan)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MFTheme.iceCyan)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(MFTheme.iceCyan.opacity(0.12), in: Capsule())
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
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
                    .foregroundStyle(MFTheme.textSecondary)
                Spacer()
                if !text.wrappedValue.isEmpty {
                    Button("清空") {
                        text.wrappedValue = ""
                        autoSaveKeys()
                    }
                    .font(.caption2)
                    .foregroundStyle(MFTheme.textMuted)
                }
            }

            HStack(spacing: 8) {
                if isPlainVisible.wrappedValue {
                    TextField(placeholder, text: text)
                        .textFieldStyle(.plain)
                        .font(.caption.monospaced())
                } else {
                    SecureField(placeholder, text: text)
                        .textFieldStyle(.plain)
                        .font(.caption.monospaced())
                }

                Button {
                    isPlainVisible.wrappedValue.toggle()
                } label: {
                    Image(systemName: isPlainVisible.wrappedValue ? "eye.slash.fill" : "eye.fill")
                        .font(.caption)
                        .foregroundStyle(MFTheme.textMuted)
                }
                .buttonStyle(.plain)

                Button {
                    if let clip = getClipboardString() {
                        text.wrappedValue = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                        autoSaveKeys()
                    }
                } label: {
                    Text("粘贴")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MFTheme.iceCyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(MFTheme.iceCyan.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            )
            .onChange(of: text.wrappedValue) { _, _ in
                autoSaveKeys()
            }
        }
    }

    private func getClipboardString() -> String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }
}

// MARK: - Model Picker Modal Sheet

private struct ModelPickerModalView: View {
    let title: String
    let subtitle: String
    let iconName: String
    let currentSelectedId: String
    let models: [(id: String, label: String)]
    let presetIds: Set<String>
    let isSyncing: Bool
    let syncStatusMessage: String?
    let allowsSync: Bool
    let onSelectModel: (String) -> Void
    let onSyncRemote: () -> Void
    let onAddCustomModel: (String) -> Void
    let onDismiss: () -> Void

    @State private var searchText: String = ""
    @State private var showingAddCustomInput: Bool = false
    @State private var customModelInput: String = ""

    private var filteredModels: [(id: String, label: String)] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return models }
        return models.filter {
            $0.id.lowercased().contains(q) || $0.label.lowercased().contains(q)
        }
    }

    private var presetFiltered: [(id: String, label: String)] {
        filteredModels.filter { presetIds.contains($0.id) }
    }

    private var customFiltered: [(id: String, label: String)] {
        filteredModels.filter { !presetIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MFTheme.sheetBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    if models.count > 2 {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(MFTheme.textMuted)
                            TextField("搜索模型（如 qwen、deepseek、sensevoice）", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.subheadline)
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(MFTheme.textMuted)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if let msg = syncStatusMessage {
                                Text(msg)
                                    .font(.caption2)
                                    .foregroundStyle(MFTheme.mintGreen)
                                    .padding(.horizontal, 16)
                            }

                            if !presetFiltered.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("官方推荐及预置模型")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(MFTheme.textSecondary)
                                        Spacer()
                                        Text("\(presetFiltered.count) 个可用")
                                            .font(.caption2)
                                            .foregroundStyle(MFTheme.textMuted)
                                    }
                                    .padding(.horizontal, 16)

                                    ForEach(presetFiltered, id: \.id) { model in
                                        pickerRow(
                                            title: model.label,
                                            modelId: model.id,
                                            isSelected: currentSelectedId == model.id
                                        ) {
                                            onSelectModel(model.id)
                                            onDismiss()
                                        }
                                    }
                                }
                            }

                            if !customFiltered.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("云端已同步 / 自定义模型")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(MFTheme.textSecondary)
                                        Spacer()
                                        Text("\(customFiltered.count) 个可用")
                                            .font(.caption2)
                                            .foregroundStyle(MFTheme.textMuted)
                                    }
                                    .padding(.horizontal, 16)

                                    ForEach(customFiltered, id: \.id) { model in
                                        pickerRow(
                                            title: model.label,
                                            modelId: model.id,
                                            isSelected: currentSelectedId == model.id
                                        ) {
                                            onSelectModel(model.id)
                                            onDismiss()
                                        }
                                    }
                                }
                            }

                            if filteredModels.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.largeTitle)
                                        .foregroundStyle(MFTheme.textMuted)
                                    Text("未找到与「\(searchText)」匹配的模型")
                                        .font(.caption)
                                        .foregroundStyle(MFTheme.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 36)
                            }

                            if allowsSync {
                                VStack(alignment: .leading, spacing: 10) {
                                    Divider().background(Color.white.opacity(0.1))

                                    HStack {
                                        Button {
                                            onSyncRemote()
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: isSyncing ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise")
                                                Text(isSyncing ? "正在拉取最新模型…" : "从服务端拉取最新模型")
                                            }
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(MFTheme.iceCyan)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(isSyncing)

                                        Spacer()

                                        Button {
                                            withAnimation { showingAddCustomInput.toggle() }
                                        } label: {
                                            Text(showingAddCustomInput ? "收起" : "+ 手动添加模型 ID")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(MFTheme.iceCyan)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 16)

                                    if showingAddCustomInput {
                                        HStack(spacing: 8) {
                                            TextField("输入模型 ID（如 Qwen/Qwen2.5-7B-Instruct）", text: $customModelInput)
                                                .textFieldStyle(.roundedBorder)
                                                .font(.caption.monospaced())
                                            Button("添加并选中") {
                                                let trimmed = customModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                                guard !trimmed.isEmpty else { return }
                                                onAddCustomModel(trimmed)
                                                customModelInput = ""
                                                showingAddCustomInput = false
                                                onDismiss()
                                            }
                                            .font(.caption.weight(.semibold))
                                            .buttonStyle(.borderedProminent)
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                }
                                .padding(.top, 6)
                            }
                        }
                        .padding(.vertical, 14)
                    }
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onDismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .frame(minWidth: 460, idealWidth: 500, minHeight: 460, idealHeight: 520)
    }

    private func pickerRow(
        title: String,
        modelId: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? MFTheme.iceCyan : MFTheme.textMuted)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MFTheme.textPrimary)
                    Text(modelId)
                        .font(.caption2.monospaced())
                        .foregroundStyle(MFTheme.textSecondary)
                }

                Spacer()

                if isSelected {
                    Text("当前使用")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(MFTheme.iceCyan.opacity(0.18), in: Capsule())
                        .foregroundStyle(MFTheme.iceCyan)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? MFTheme.iceCyan.opacity(0.08) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSelected ? MFTheme.iceCyan.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}
