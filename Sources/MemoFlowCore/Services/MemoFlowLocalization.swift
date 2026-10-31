import Foundation

/// MemoFlow 中英文多语言本地化支持（跟随系统 / 简体中文 / English）
public enum L10n {
    @inlinable
    public static func tr(_ isEnglish: Bool, _ zh: String, _ en: String) -> String {
        isEnglish ? en : zh
    }

    // MARK: - Navigation & Headers
    public static func settings(_ isEnglish: Bool) -> String { tr(isEnglish, "设置", "Settings") }
    public static func serviceAndSettings(_ isEnglish: Bool) -> String { tr(isEnglish, "服务与设置", "Settings") }
    public static func settingsCenterSubtitle(_ isEnglish: Bool) -> String { tr(isEnglish, "Telomi 设置中心", "Telomi Settings") }
    public static func settingsHeaderNote(_ isEnglish: Bool) -> String {
        tr(isEnglish, "按功能模块独立管理 · 密钥安全保存在 Keychain", "Manage features independently · Keys secured in Keychain")
    }
    public static func saved(_ isEnglish: Bool) -> String { tr(isEnglish, "已保存", "Saved") }
    public static func closeSettings(_ isEnglish: Bool) -> String { tr(isEnglish, "关闭设置", "Close Settings") }

    // MARK: - Settings Groups
    public static func recordingAndNotesGroup(_ isEnglish: Bool) -> String { tr(isEnglish, "录音与整理", "Recording & Notes") }
    public static func knowledgeAndSyncGroup(_ isEnglish: Bool) -> String { tr(isEnglish, "知识与联动", "Knowledge & Integrations") }
    public static func preferencesGroup(_ isEnglish: Bool) -> String { tr(isEnglish, "偏好与管理", "Preferences") }

    // MARK: - Settings Destinations
    public static func speechToText(_ isEnglish: Bool) -> String { tr(isEnglish, "语音转写", "Speech-to-Text") }
    public static func aiNotes(_ isEnglish: Bool) -> String { tr(isEnglish, "AI 笔记", "AI Notes") }
    public static func liveStreaming(_ isEnglish: Bool) -> String { tr(isEnglish, "边录边整理", "Live Streaming") }
    public static func speakerAndNicknames(_ isEnglish: Bool) -> String { tr(isEnglish, "说话人与昵称", "Speakers & Nicknames") }
    public static func obsidian(_ isEnglish: Bool) -> String { "Obsidian" }
    public static func personalMemory(_ isEnglish: Bool) -> String { tr(isEnglish, "个人记忆", "Personal Memory") }
    public static func calendarAndReminders(_ isEnglish: Bool) -> String { tr(isEnglish, "日历与提醒事项", "Calendar & Reminders") }
    public static func appearance(_ isEnglish: Bool) -> String { tr(isEnglish, "外观", "Appearance") }
    public static func language(_ isEnglish: Bool) -> String { tr(isEnglish, "语言", "Language") }
    public static func privacyAndData(_ isEnglish: Bool) -> String { tr(isEnglish, "隐私与数据", "Privacy & Data") }

    // MARK: - Appearance & Language Options
    public static func systemTheme(_ isEnglish: Bool) -> String { tr(isEnglish, "系统", "System") }
    public static func lightTheme(_ isEnglish: Bool) -> String { tr(isEnglish, "浅色", "Light") }
    public static func darkTheme(_ isEnglish: Bool) -> String { tr(isEnglish, "深色", "Dark") }

    public static func languageOptionTitle(_ lang: AppLanguage, isEnglish: Bool) -> String {
        switch lang {
        case .system: return tr(isEnglish, "跟随系统", "System")
        case .chinese: return tr(isEnglish, "简体中文", "Simplified Chinese")
        case .english: return "English"
        }
    }

    public static func languageShortLabel(_ lang: AppLanguage, isEnglish: Bool) -> String {
        switch lang {
        case .system: return tr(isEnglish, "系统", "System")
        case .chinese: return "中文"
        case .english: return "EN"
        }
    }

    // MARK: - Status Summaries
    public static func liveStreamingEnabled(_ isEnglish: Bool) -> String { tr(isEnglish, "已开启", "Enabled") }
    public static func liveStreamingDisabled(_ isEnglish: Bool) -> String { tr(isEnglish, "停止后统一处理", "Batch on Stop") }
    public static func notConnected(_ isEnglish: Bool) -> String { tr(isEnglish, "未连接", "Not Connected") }
    public static func connected(_ isEnglish: Bool, name: String) -> String { tr(isEnglish, "已连接 \(name)", "Connected: \(name)") }
    public static func pendingMemories(_ isEnglish: Bool, count: Int) -> String { tr(isEnglish, "\(count) 项待审阅", "\(count) pending review") }
    public static func activeMemories(_ isEnglish: Bool, count: Int) -> String { tr(isEnglish, "\(count) 条已生效", "\(count) active") }
    public static func memoryDisabled(_ isEnglish: Bool) -> String { tr(isEnglish, "未启用记忆", "Disabled") }
    public static func calendarAutoCreate(_ isEnglish: Bool) -> String { tr(isEnglish, "智能自动创建", "Auto-create") }
    public static func calendarReviewFirst(_ isEnglish: Bool) -> String { tr(isEnglish, "审核后创建", "Review First") }
    public static func cloudAuthorized(_ isEnglish: Bool) -> String { tr(isEnglish, "已授权云端处理", "Cloud Authorized") }
    public static func onDeviceOnly(_ isEnglish: Bool) -> String { tr(isEnglish, "仅端侧本地", "On-Device Only") }

    // MARK: - Common Buttons & Actions
    public static func configureAPIKey(_ isEnglish: Bool) -> String { tr(isEnglish, "配置 API Key", "Configure API Key") }
    public static func regenerate(_ isEnglish: Bool) -> String { tr(isEnglish, "重新整理", "Regenerate") }
    public static func retryWithAppleSpeech(_ isEnglish: Bool) -> String { tr(isEnglish, "改用 Apple 本地识别重试", "Retry with Apple Speech") }
    public static func copyMarkdown(_ isEnglish: Bool) -> String { tr(isEnglish, "复制 Markdown", "Copy Markdown") }
    public static func exportToObsidian(_ isEnglish: Bool) -> String { tr(isEnglish, "导出至 Obsidian", "Export to Obsidian") }
    public static func startRecording(_ isEnglish: Bool) -> String { tr(isEnglish, "开始录音", "Start Recording") }
    public static func stopRecording(_ isEnglish: Bool) -> String { tr(isEnglish, "结束录音", "Stop Recording") }
    public static func searchMemoriesPlaceholder(_ isEnglish: Bool) -> String { tr(isEnglish, "搜索你的记忆…", "Search memories…") }
    public static func memoriesCount(_ isEnglish: Bool, count: Int) -> String { tr(isEnglish, "\(count) 条记忆", "\(count) memories") }
    public static func noRecordingsTitle(_ isEnglish: Bool) -> String { tr(isEnglish, "暂无录音记忆", "No memories yet") }
    public static func noRecordingsSubtitle(_ isEnglish: Bool) -> String { tr(isEnglish, "点击下方按钮开始一段新思考", "Tap below to start recording") }
    public static func allPendingReview(_ isEnglish: Bool) -> String { tr(isEnglish, "全部待确认", "Review Pending") }
    public static func obsidianSyncTooltip(_ isEnglish: Bool) -> String { tr(isEnglish, "Obsidian 双向同步", "Obsidian Sync") }
    public static func groundedQATooltip(_ isEnglish: Bool) -> String { tr(isEnglish, "跨笔记问答", "Cross-Note Q&A") }
    public static func cancel(_ isEnglish: Bool) -> String { tr(isEnglish, "取消", "Cancel") }
    public static func save(_ isEnglish: Bool) -> String { tr(isEnglish, "保存", "Save") }
    public static func delete(_ isEnglish: Bool) -> String { tr(isEnglish, "删除", "Delete") }
    public static func edit(_ isEnglish: Bool) -> String { tr(isEnglish, "编辑", "Edit") }

    // MARK: - CHAT-001 & WATCH-001
    public static func aiMemoryAssistant(_ isEnglish: Bool) -> String { tr(isEnglish, "AI 记忆助手", "AI Memory Assistant") }
    public static func askMemoryPlaceholder(_ isEnglish: Bool) -> String { tr(isEnglish, "想从记忆里找些什么？", "What would you like to find in your memories?") }
    public static func askMemory(_ isEnglish: Bool) -> String { tr(isEnglish, "问记忆", "Ask Memory") }
    public static func memoryChatTitle(_ isEnglish: Bool) -> String { tr(isEnglish, "聊聊你的记忆", "Talk about your memories") }
    public static func brandSlogan(_ isEnglish: Bool) -> String { tr(isEnglish, "让每一段记忆都更懂你。", "Let every memory understand you better.") }
    public static func generateProjectNote(_ isEnglish: Bool) -> String { tr(isEnglish, "生成项目笔记", "Generate Project Note") }
    public static func confirmWriteObsidian(_ isEnglish: Bool) -> String { tr(isEnglish, "确认写入 Obsidian", "Confirm Write to Obsidian") }
    public static func appleWatch(_ isEnglish: Bool) -> String { "Apple Watch" }
    public static func appleWatchSync(_ isEnglish: Bool) -> String { tr(isEnglish, "Apple Watch 同步", "Apple Watch Sync") }
    public static func aboutGroup(_ isEnglish: Bool) -> String { tr(isEnglish, "关于", "About") }
    public static func aboutMemoFlow(_ isEnglish: Bool) -> String { tr(isEnglish, "关于 Telomi", "About Telomi") }
}
