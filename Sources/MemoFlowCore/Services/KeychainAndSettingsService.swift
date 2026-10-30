import Foundation
import Security

/// ASR 转写引擎模式（支持 OpenAI 兼容接口 如硅基流动 SenseVoice / Groq / OpenAI，以及 Apple 本地识别）
public enum ASREngineMode: String, Codable, CaseIterable, Sendable {
    case openAICompatible = "openai_compatible"
    case appleOnDevice = "apple_on_device"
    case localWhisper = "local_whisper"

    public var displayTitle: String {
        switch self {
        case .openAICompatible: return "OpenAI 兼容语音 API（硅基流动 / Groq / OpenAI）"
        case .appleOnDevice: return "Apple 端侧语音识别（SFSpeechRecognizer）"
        case .localWhisper: return "本机 Whisper（长录音候选稿，需校对）"
        }
    }

    public var sendsAudioToCloud: Bool { self == .openAICompatible }
}

/// 界面视觉主题（PRD V1.3 VIS-001：Readwise 极简暖纸 / 暖炭夜读 / 跟随系统）
public enum AppearanceTheme: String, Codable, CaseIterable, Sendable {
    case warmPaper = "warm_paper"      // Readwise 极简暖纸风格（默认）
    case darkNight = "dark_night"      // 暖炭夜读模式
    case system = "system"            // 跟随系统自动切换

    public var displayTitle: String {
        switch self {
        case .warmPaper: return "极简暖纸 (Readwise)"
        case .darkNight: return "深邃夜读 (Warm Charcoal)"
        case .system: return "跟随系统"
        }
    }
}

/// P2-7：跨设备（iPhone <-> Mac）录音音频可用性与同步策略
public enum AudioSyncMode: String, Codable, CaseIterable, Sendable {
    case localOnly = "local_only"
    case vaultAttachmentCopy = "vault_attachment_copy"

    public var displayTitle: String {
        switch self {
        case .localOnly:
            return "仅保留在录制设备本地（不同步音频副本）"
        case .vaultAttachmentCopy:
            return "同步音频副本到笔记库附件目录（支持 iPhone 与 Mac 跨端回听）"
        }
    }

    public var subtitle: String {
        switch self {
        case .localOnly:
            return "笔记通过 Obsidian 同步，原音频仅保存在录制设备上；另一端打开时会明确提示「笔记已同步、音频未到达」。"
        case .vaultAttachmentCopy:
            return "导出笔记时自动将音频副本存入笔记库相对附件目录，iPhone 与 Mac 两端均可通过同一笔记库直接定位回听。"
        }
    }
}

/// 用户偏好与模型配置（PRD P06 & 13）
public struct MemoFlowPreferences: Codable, Equatable, Sendable {
    public var obsidianVaultBookmark: Data? = nil
    public var knowledgeContextEnabled: Bool = false
    public var knowledgeExcludedFolders: String = "日记\n私人"
    /// 可选白名单：非空时仅索引与检索这些相对子目录；为空时检索所有未被排除的目录（P1-5）
    public var knowledgeIncludedFolders: [String] = []
    /// 是否允许将本地检索到的历史笔记片段与已确认个人记忆发送至云端 LLM（P1-5 独立授权开关，默认关闭）
    public var allowSendingKnowledgeToCloudLLM: Bool = false
    /// P2-7：跨设备音频副本同步方式（默认仅保存在本机，可选同步到笔记库附件目录）
    public var audioSyncMode: AudioSyncMode = .localOnly
    /// P2-7：笔记库内保存跨端音频副本的相对附件子目录（严禁使用仅 Mac 有效的绝对路径）
    public var obsidianAudioAttachmentSubfolder: String = "MemoFlow笔记/Attachments"
    public var defaultNoteMode: NoteMode
    public var asrEngineMode: ASREngineMode
    public var asrBaseURL: String
    public var asrModelName: String
    public var llmBaseURL: String
    public var llmModelName: String
    /// 只有开始时间无结束时间时的默认事件时长（分钟，PRD 4.6 初始建议 30 分钟）
    public var defaultEventDurationMinutes: Int
    /// 任务默认建议主要去向（PRD P06）
    public var defaultTaskDestination: PrimaryDestination
    /// 选定的默认日历 Identifier
    public var preferredCalendarIdentifier: String?
    /// 选定的默认提醒事项列表 Identifier
    public var preferredReminderListIdentifier: String?
    /// 历史用过的项目名列表（供笔记详情页快速关联，不扫描整个 Obsidian 库，PRD R13）
    public var knownProjectNames: [String]
    /// Obsidian 笔记库根目录路径（PRD R15：授权选择笔记库路径后直接保存 Markdown）
    public var obsidianVaultRootPath: String?
    /// Obsidian 库内的目标子目录（如 MemoFlow 或 Inbox）
    public var obsidianTargetSubfolder: String
    /// 是否在 AI 整理完成后自动将笔记写入 Obsidian 指定目录
    public var autoExportToObsidianOnComplete: Bool
    /// 电影角色昵称主题（PRD V1.2 AI-003: 《怪奇物语》/《星际穿越》）
    public var speakerNicknameTheme: SpeakerNicknameTheme
    /// 苹果日历同步模式（PRD V1.2 CAL-003: 审核后创建 / 智能自动创建）
    public var calendarCreationMode: CalendarCreationMode
    /// 个人声纹档案（PRD V1.2 AI-001: 识别我的声音）
    public var userVoiceProfile: UserVoiceProfile?
    /// 用户通过 /v1/models 拉取或手动添加的额外 ASR 模型 ID 列表（持久化保存，解决模型更新问题）
    public var customASRModels: [String]
    /// 用户通过 /v1/models 拉取或手动添加的额外 LLM 模型 ID 列表（持久化保存，解决模型更新问题）
    public var customLLMModels: [String]
    /// 界面视觉主题风格（PRD V1.3 VIS-001）
    public var appearanceTheme: AppearanceTheme

    public init(
        defaultNoteMode: NoteMode = .quickNote,
        asrEngineMode: ASREngineMode = .openAICompatible,
        asrBaseURL: String = "https://api.siliconflow.cn/v1",
        asrModelName: String = "FunAudioLLM/SenseVoiceSmall",
        llmBaseURL: String = "https://api.deepseek.com/v1",
        llmModelName: String = "deepseek-flash",
        defaultEventDurationMinutes: Int = 30,
        defaultTaskDestination: PrimaryDestination = .reminders,
        preferredCalendarIdentifier: String? = nil,
        preferredReminderListIdentifier: String? = nil,
        knownProjectNames: [String] = [
            "小红书数码账号｜iPhone + AI",
            "日本旅行视频企划",
            "科研栏目首期"
        ],
        obsidianVaultRootPath: String? = nil,
        obsidianTargetSubfolder: String = "MemoFlow笔记",
        autoExportToObsidianOnComplete: Bool = false,
        speakerNicknameTheme: SpeakerNicknameTheme = .strangerThings,
        calendarCreationMode: CalendarCreationMode = .reviewFirst,
        userVoiceProfile: UserVoiceProfile? = nil,
        customASRModels: [String] = [],
        customLLMModels: [String] = [],
        appearanceTheme: AppearanceTheme = .warmPaper
    ) {
        self.defaultNoteMode = defaultNoteMode
        self.asrEngineMode = asrEngineMode
        self.asrBaseURL = asrBaseURL
        self.asrModelName = asrModelName
        self.llmBaseURL = llmBaseURL
        self.llmModelName = llmModelName
        self.defaultEventDurationMinutes = defaultEventDurationMinutes
        self.defaultTaskDestination = defaultTaskDestination
        self.preferredCalendarIdentifier = preferredCalendarIdentifier
        self.preferredReminderListIdentifier = preferredReminderListIdentifier
        self.knownProjectNames = knownProjectNames
        self.obsidianVaultRootPath = obsidianVaultRootPath
        self.obsidianTargetSubfolder = obsidianTargetSubfolder
        self.autoExportToObsidianOnComplete = autoExportToObsidianOnComplete
        self.speakerNicknameTheme = speakerNicknameTheme
        self.calendarCreationMode = calendarCreationMode
        self.userVoiceProfile = userVoiceProfile
        self.customASRModels = customASRModels
        self.customLLMModels = customLLMModels
        self.appearanceTheme = appearanceTheme
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.obsidianVaultBookmark = try c.decodeIfPresent(Data.self, forKey: .obsidianVaultBookmark)
        self.knowledgeContextEnabled = try c.decodeIfPresent(Bool.self, forKey: .knowledgeContextEnabled) ?? false
        self.knowledgeExcludedFolders = try c.decodeIfPresent(String.self, forKey: .knowledgeExcludedFolders) ?? "日记\n私人"
        self.knowledgeIncludedFolders = try c.decodeIfPresent([String].self, forKey: .knowledgeIncludedFolders) ?? []
        self.allowSendingKnowledgeToCloudLLM = try c.decodeIfPresent(Bool.self, forKey: .allowSendingKnowledgeToCloudLLM) ?? false
        self.audioSyncMode = try c.decodeIfPresent(AudioSyncMode.self, forKey: .audioSyncMode) ?? .localOnly
        self.obsidianAudioAttachmentSubfolder = try c.decodeIfPresent(String.self, forKey: .obsidianAudioAttachmentSubfolder) ?? "MemoFlow笔记/Attachments"
        self.defaultNoteMode = try c.decodeIfPresent(NoteMode.self, forKey: .defaultNoteMode) ?? .quickNote
        self.asrEngineMode = try c.decodeIfPresent(ASREngineMode.self, forKey: .asrEngineMode) ?? .openAICompatible
        self.asrBaseURL = try c.decodeIfPresent(String.self, forKey: .asrBaseURL) ?? "https://api.siliconflow.cn/v1"
        self.asrModelName = try c.decodeIfPresent(String.self, forKey: .asrModelName) ?? "FunAudioLLM/SenseVoiceSmall"
        self.llmBaseURL = try c.decodeIfPresent(String.self, forKey: .llmBaseURL) ?? "https://api.deepseek.com/v1"
        let savedLLMModel = try c.decodeIfPresent(String.self, forKey: .llmModelName) ?? "deepseek-flash"
        // Upgrade only legacy names on the official DeepSeek endpoint. Custom
        // gateways and explicitly selected modern models keep their own IDs.
        if self.llmBaseURL == "https://api.deepseek.com/v1" || self.llmBaseURL == "https://api.deepseek.com" {
            switch savedLLMModel {
            case "deepseek-chat": self.llmModelName = "deepseek-flash"
            case "deepseek-reasoner": self.llmModelName = "deepseek-v4-pro"
            default: self.llmModelName = savedLLMModel
            }
        } else if self.llmBaseURL == "https://api.siliconflow.cn/v1",
                  savedLLMModel == "deepseek-ai/DeepSeek-V3" {
            self.llmModelName = "deepseek-ai/DeepSeek-V4.1-Flash"
        } else {
            self.llmModelName = savedLLMModel
        }
        self.defaultEventDurationMinutes = try c.decodeIfPresent(Int.self, forKey: .defaultEventDurationMinutes) ?? 30
        self.defaultTaskDestination = try c.decodeIfPresent(PrimaryDestination.self, forKey: .defaultTaskDestination) ?? .reminders
        self.preferredCalendarIdentifier = try c.decodeIfPresent(String.self, forKey: .preferredCalendarIdentifier)
        self.preferredReminderListIdentifier = try c.decodeIfPresent(String.self, forKey: .preferredReminderListIdentifier)
        self.knownProjectNames = try c.decodeIfPresent([String].self, forKey: .knownProjectNames) ?? [
            "小红书数码账号｜iPhone + AI",
            "日本旅行视频企划",
            "科研栏目首期"
        ]
        self.obsidianVaultRootPath = try c.decodeIfPresent(String.self, forKey: .obsidianVaultRootPath)
        self.obsidianTargetSubfolder = try c.decodeIfPresent(String.self, forKey: .obsidianTargetSubfolder) ?? "MemoFlow笔记"
        self.autoExportToObsidianOnComplete = try c.decodeIfPresent(Bool.self, forKey: .autoExportToObsidianOnComplete) ?? false
        self.speakerNicknameTheme = try c.decodeIfPresent(SpeakerNicknameTheme.self, forKey: .speakerNicknameTheme) ?? .strangerThings
        self.calendarCreationMode = try c.decodeIfPresent(CalendarCreationMode.self, forKey: .calendarCreationMode) ?? .reviewFirst
        self.userVoiceProfile = try c.decodeIfPresent(UserVoiceProfile.self, forKey: .userVoiceProfile)
        self.customASRModels = try c.decodeIfPresent([String].self, forKey: .customASRModels) ?? []
        self.customLLMModels = try c.decodeIfPresent([String].self, forKey: .customLLMModels) ?? []
        self.appearanceTheme = try c.decodeIfPresent(AppearanceTheme.self, forKey: .appearanceTheme) ?? .warmPaper
    }
}

/// Keychain 安全存储服务（PRD 9.2: 设备内敏感凭据放 Keychain，不将商业 API Key 明文内置在 App）
public final class KeychainService: Sendable {
    public static let shared = KeychainService()
    private let serviceName = "com.esine.MemoFlow.credentials"

    public enum AccountKey: String, Sendable {
        case asrAPIKey = "asr_api_key"
        case llmAPIKey = "llm_api_key"
    }

    public init() {}

    @discardableResult
    public func saveKey(_ value: String, for account: AccountKey, endpoint: String? = nil) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return deleteKey(for: account, endpoint: endpoint)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: credentialAccount(account, endpoint: endpoint)
        ]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    public func readKey(for account: AccountKey, endpoint: String? = nil) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: credentialAccount(account, endpoint: endpoint),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    @discardableResult
    public func deleteKey(for account: AccountKey, endpoint: String? = nil) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: credentialAccount(account, endpoint: endpoint)
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func credentialAccount(_ account: AccountKey, endpoint: String?) -> String {
        guard let endpoint else { return account.rawValue }
        let normalized = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        return "\(account.rawValue):\(normalized)"
    }

    /// Bind an old unscoped key only once, to the endpoint already saved by the user.
    public func migrateLegacyKey(for account: AccountKey, endpoint: String) {
        let marker = "legacy-migration-completed"
        guard readKey(for: account, endpoint: marker) == nil else { return }
        if let key = readKey(for: account), readKey(for: account, endpoint: endpoint) == nil {
            guard saveKey(key, for: account, endpoint: endpoint) else { return }
        }
        _ = saveKey("done", for: account, endpoint: marker)
    }
}
