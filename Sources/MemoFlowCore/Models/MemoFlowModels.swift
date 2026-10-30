import Foundation

// MARK: - Enums & Statuses (PRD 04 & 08.3)

/// 录音处理状态（PRD 4.1: 录音中、已安全保存·待转写、上传中、转写中、整理中、整理完成、处理失败）
public enum RecordingProcessingStatus: String, Codable, CaseIterable, Sendable {
    case recording = "recording"
    case savedPendingTranscription = "saved_pending_transcription"
    case uploading = "uploading"
    case transcribing = "transcribing"
    case transcriptNeedsReview = "transcript_needs_review"
    case organizing = "organizing"
    case completed = "completed"
    case failed = "failed"

    public var displayTitle: String {
        switch self {
        case .recording: return "录音中"
        case .savedPendingTranscription: return "已安全保存·待转写"
        case .uploading: return "上传中"
        case .transcribing: return "转写中"
        case .transcriptNeedsReview: return "逐字稿待校对"
        case .organizing: return "整理中"
        case .completed: return "整理完成"
        case .failed: return "处理失败"
        }
    }
}

/// 整理模式（PRD 1.3 & 6.1: 随手记 / 会议记）
public enum NoteMode: String, Codable, CaseIterable, Sendable {
    case quickNote = "quick_note"
    case meetingNote = "meeting_note"

    public var displayTitle: String {
        switch self {
        case .quickNote: return "随手记"
        case .meetingNote: return "会议记"
        }
    }

    public var subtitle: String {
        switch self {
        case .quickNote: return "保留原意的短笔记，不强行扩写观点与待办"
        case .meetingNote: return "提炼背景、关键观点、决策与有证据的行动候选"
        }
    }
}

/// 笔记版本来源（PRD 8.3: AI / 用户编辑）
public enum RevisionOrigin: String, Codable, Sendable {
    case ai = "ai"
    case userEdited = "user_edited"
}

/// 行动类别（PRD 8.3: 任务 / 日程）
public enum ActionKind: String, Codable, CaseIterable, Sendable {
    case task = "task"
    case event = "event"

    public var displayTitle: String {
        switch self {
        case .task: return "待办任务"
        case .event: return "日程活动"
        }
    }
}

/// 行动归属（PRD 8.3 & 4.6: 本人 / 他人 / 不确定）
public enum ActionOwnership: String, Codable, CaseIterable, Sendable {
    case selfOwner = "self"
    case other = "other"
    case uncertain = "uncertain"

    public var displayTitle: String {
        switch self {
        case .selfOwner: return "本人负责"
        case .other: return "他人负责（仅上下文）"
        case .uncertain: return "负责人未明确"
        }
    }
}

/// 日期精度（PRD 4.6 & R22: 明确时刻 / 仅日期 / 无日期 / 模糊待确认）
public enum DatePrecision: String, Codable, CaseIterable, Sendable {
    case exactTime = "exact_time"
    case dateOnly = "date_only"
    case none = "none"
    case ambiguous = "ambiguous"

    public var displayTitle: String {
        switch self {
        case .exactTime: return "精确时间"
        case .dateOnly: return "仅日期（无具体时刻）"
        case .none: return "无日期"
        case .ambiguous: return "时间模糊需确认"
        }
    }
}

/// 任务/行动主要管理位置（PRD R25 & 4.7: 本地 / Apple 日历 / Apple 提醒事项 / Markdown）
public enum PrimaryDestination: String, Codable, CaseIterable, Sendable {
    case local = "local"
    case calendar = "calendar"
    case reminders = "reminders"
    case markdown = "markdown"

    public var displayTitle: String {
        switch self {
        case .local: return "MemoFlow 本地"
        case .calendar: return "Apple 日历"
        case .reminders: return "Apple 提醒事项"
        case .markdown: return "Markdown / Obsidian"
        }
    }
}

/// 行动执行与确认状态（PRD 4.1: 待确认、需补充信息、本地保留、已交给外部工具、已导出 Markdown、已忽略、执行失败、执行结果待核查）
public enum ActionExecutionStatus: String, Codable, CaseIterable, Sendable {
    case pendingConfirm = "pending_confirm"
    case needsInfo = "needs_info"
    case keptLocal = "kept_local"
    case handedToExternal = "handed_to_external"
    case exportedMarkdown = "exported_markdown"
    case ignored = "ignored"
    case executionFailed = "execution_failed"
    case pendingVerification = "pending_verification"

    public var displayTitle: String {
        switch self {
        case .pendingConfirm: return "待确认"
        case .needsInfo: return "需补充信息"
        case .keptLocal: return "本地保留"
        case .handedToExternal: return "已交给外部工具"
        case .exportedMarkdown: return "已导出 Markdown"
        case .ignored: return "已忽略"
        case .executionFailed: return "执行失败"
        case .pendingVerification: return "执行结果待核查"
        }
    }
}

/// 候选草稿审核状态
public enum DraftReviewStatus: String, Codable, Sendable {
    case pending = "pending"
    case needsInfo = "needs_info"
    case confirmed = "confirmed"
    case ignored = "ignored"
    case hasDiffWithConfirmed = "has_diff_with_confirmed"
}

/// 云处理授权模式（PRD R12 & 8.3: 记住授权 / 逐次确认）
public enum ConsentMode: String, Codable, CaseIterable, Sendable {
    case remembered = "remembered"
    case askEveryTime = "ask_every_time"

    public var displayTitle: String {
        switch self {
        case .remembered: return "记住授权（自动处理新录音）"
        case .askEveryTime: return "逐次确认（每次上传前询问）"
        }
    }
}

/// 电影角色昵称主题（PRD V1.2 AI-003）
public enum SpeakerNicknameTheme: String, Codable, CaseIterable, Sendable {
    case strangerThings = "stranger_things"
    case interstellar = "interstellar"

    public var displayTitle: String {
        switch self {
        case .strangerThings: return "《怪奇物语》Stranger Things"
        case .interstellar: return "《星际穿越》Interstellar"
        }
    }

    public var defaultNicknames: [String] {
        switch self {
        case .strangerThings:
            return ["Dustin", "Max", "Lucas", "Will", "Mike", "Eleven", "Steve", "Robin", "Nancy", "Jonathan"]
        case .interstellar:
            return ["Cooper", "Murph", "Brand", "TARS", "CASE", "Romilly", "Doyle", "Mann", "Tom"]
        }
    }
}

/// 个人声纹档案（PRD V1.2 AI-001）
public struct UserVoiceProfile: Codable, Equatable, Sendable {
    public var id: UUID
    public var enrolledAt: Date
    public var sampleDuration: TimeInterval
    public var featureDescription: String
    public var sampleAudioFileName: String?

    public init(
        id: UUID = UUID(),
        enrolledAt: Date = Date(),
        sampleDuration: TimeInterval = 6.0,
        featureDescription: String = "已录入个人声纹特征档案",
        sampleAudioFileName: String? = nil
    ) {
        self.id = id
        self.enrolledAt = enrolledAt
        self.sampleDuration = sampleDuration
        self.featureDescription = featureDescription
        self.sampleAudioFileName = sampleAudioFileName
    }
}

/// 苹果日历同步模式（PRD V1.2 CAL-003）
public enum CalendarCreationMode: String, Codable, CaseIterable, Sendable {
    case reviewFirst = "review_first"
    case autoCreate = "auto_create"

    public var displayTitle: String {
        switch self {
        case .reviewFirst: return "审核后创建（默认）"
        case .autoCreate: return "智能自动创建（高确定性日程直接写入）"
        }
    }

    public var subtitle: String {
        switch self {
        case .reviewFirst: return "AI 识别后进入待确认区，用户确认后才写入 Apple 日历"
        case .autoCreate: return "对于时间地点明确且属于本人的日程，转写完成后自动创建日历事件"
        }
    }
}

// MARK: - 11 Core Data Objects (PRD 8.3)

/// 1. Recording（录音记录）
public struct Recording: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var recordedTimeZoneIdentifier: String
    public var duration: TimeInterval
    public var localAudioFileName: String
    public var language: String
    public var processingStatus: RecordingProcessingStatus
    public var failureReason: String?
    public var audioInterruptionNote: String?
    public var transcriptSource: TranscriptSource?
    public var marks: [RecordingMark]?
    /// 逐字稿是否已由用户人工听校确认（nil 或 false 均视为尚未人工审核的机器稿/历史稿，P1-4）
    public var isTranscriptReviewed: Bool?

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        recordedTimeZoneIdentifier: String = TimeZone.current.identifier,
        duration: TimeInterval = 0,
        localAudioFileName: String,
        language: String = "zh-CN",
        processingStatus: RecordingProcessingStatus = .savedPendingTranscription,
        failureReason: String? = nil,
        audioInterruptionNote: String? = nil,
        isTranscriptReviewed: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.recordedTimeZoneIdentifier = recordedTimeZoneIdentifier
        self.duration = duration
        self.localAudioFileName = localAudioFileName
        self.language = language
        self.processingStatus = processingStatus
        self.failureReason = failureReason
        self.audioInterruptionNote = audioInterruptionNote
        self.isTranscriptReviewed = isTranscriptReviewed
    }

    public var recordedTimeZone: TimeZone {
        TimeZone(identifier: recordedTimeZoneIdentifier) ?? .current
    }

    public var transcriptReviewStatusCode: String {
        if isTranscriptReviewed == true {
            return "reviewed"
        }
        if processingStatus == .transcriptNeedsReview {
            return "machine_needs_review"
        }
        if transcriptSource == nil {
            return "legacy_unverified"
        }
        return "machine_unreviewed"
    }

    public var transcriptReviewDisplayTitle: String {
        switch transcriptReviewStatusCode {
        case "reviewed":
            return "已人工校对"
        case "machine_needs_review":
            return "机器稿待校对（尚未人工听校）"
        case "legacy_unverified":
            return "历史稿未核验音频来源"
        default:
            return "机器初稿（尚未人工校对）"
        }
    }
}

/// 2. TranscriptSegment（逐字稿分段，PRD 8.3 & V1.2 AI-002 / AI-003）
public struct TranscriptSegment: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var recordingId: UUID
    public var startMs: Int
    public var endMs: Int
    public var text: String
    public var speakerId: String?
    /// 说话人名称或电影角色昵称（如 "我"、"Dustin"、"Cooper" 或用户自定义姓名）
    public var speakerName: String?
    public var timingIsEstimated: Bool?

    public init(
        id: String = UUID().uuidString,
        recordingId: UUID,
        startMs: Int,
        endMs: Int,
        text: String,
        speakerId: String? = nil,
        speakerName: String? = nil,
        timingIsEstimated: Bool? = nil
    ) {
        self.id = id
        self.recordingId = recordingId
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.speakerId = speakerId
        self.speakerName = speakerName
        self.timingIsEstimated = timingIsEstimated
    }

    public var effectiveSpeakerDisplay: String {
        if let name = speakerName, !name.isEmpty {
            return name
        }
        if let id = speakerId, !id.isEmpty {
            return id
        }
        return "说话人"
    }

    public var formattedStartTime: String {
        TimeFormatting.formatMilliseconds(startMs)
    }

    public var formattedTimeRange: String {
        "\(TimeFormatting.formatMilliseconds(startMs)) - \(TimeFormatting.formatMilliseconds(endMs))"
    }
}

public struct TranscriptSource: Codable, Equatable, Sendable {
    public var fileName: String
    public var sha256: String
    public var audioDuration: TimeInterval
    public var engine: String
    public var completedAt: Date
}

public struct RecordingMark: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var startMs: Int
    public var endMs: Int?
    public var quote: String
    public var note: String
    public var kind: String
    public var createdAt: Date = Date()

    public init(startMs: Int, endMs: Int? = nil, quote: String = "", note: String = "", kind: String = "bookmark") {
        self.startMs = startMs
        self.endMs = endMs
        self.quote = quote
        self.note = note
        self.kind = kind
    }
}

/// 3. Note（笔记主对象，PRD 8.3）
public struct Note: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var recordingId: UUID
    public var mode: NoteMode
    public var suggestedMode: NoteMode?
    public var projectName: String?
    public var projectReference: String?
    public var userSupplement: String
    public var manualTags: [String]
    public var editedAt: Date
    public var currentRevisionId: UUID

    public init(
        id: UUID = UUID(),
        recordingId: UUID,
        mode: NoteMode,
        suggestedMode: NoteMode? = nil,
        projectName: String? = nil,
        projectReference: String? = nil,
        userSupplement: String = "",
        manualTags: [String] = [],
        editedAt: Date = Date(),
        currentRevisionId: UUID
    ) {
        self.id = id
        self.recordingId = recordingId
        self.mode = mode
        self.suggestedMode = suggestedMode
        self.projectName = projectName
        self.projectReference = projectReference
        self.userSupplement = userSupplement
        self.manualTags = manualTags
        self.editedAt = editedAt
        self.currentRevisionId = currentRevisionId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.recordingId = try c.decode(UUID.self, forKey: .recordingId)
        self.mode = try c.decode(NoteMode.self, forKey: .mode)
        self.suggestedMode = try c.decodeIfPresent(NoteMode.self, forKey: .suggestedMode)
        self.projectName = try c.decodeIfPresent(String.self, forKey: .projectName)
        self.projectReference = try c.decodeIfPresent(String.self, forKey: .projectReference)
        self.userSupplement = try c.decodeIfPresent(String.self, forKey: .userSupplement) ?? ""
        self.manualTags = try c.decodeIfPresent([String].self, forKey: .manualTags) ?? []
        self.editedAt = try c.decode(Date.self, forKey: .editedAt)
        self.currentRevisionId = try c.decode(UUID.self, forKey: .currentRevisionId)
    }
}

/// 录音章节（用于结构化导航与导出 Obsidian 章节，包含起止时间、章节小标题与章节要点）
public struct NoteChapter: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var startMs: Int
    public var endMs: Int
    public var summary: String

    public init(
        id: UUID = UUID(),
        title: String,
        startMs: Int,
        endMs: Int,
        summary: String
    ) {
        self.id = id
        self.title = title
        self.startMs = startMs
        self.endMs = endMs
        self.summary = summary
    }

    public var formattedTimeRange: String {
        "\(TimeFormatting.formatMilliseconds(startMs)) - \(TimeFormatting.formatMilliseconds(endMs))"
    }
}

/// 结构化笔记内容（对应随手记 / 会议记两种结构，包含总结、章节与要点，PRD 6.1）
public struct StructuredNoteContent: Codable, Equatable, Sendable {
    public var knowledgeReferences: [KnowledgeReference] = []
    /// 简短标题建议
    public var suggestedTitle: String
    /// 随手记：保留原意的短笔记；会议记：核心总结
    public var summaryOrShortNote: String
    /// 会议记：必要背景（可为空，不强行凑数）
    public var backgroundPoints: [String]
    /// 会议记：关键观点（可为空，不凑满 3-6 条）
    public var keyPoints: [String]
    /// 会议记：已确认结论 / 决策（可为空）
    public var decisions: [String]
    /// 按时间轴划分的录音章节（导出 Obsidian 时形成清晰的「每个录音的章节」）
    public var chapters: [NoteChapter]
    /// P1-5：从历史笔记检索到的关联背景要点（严格区分于本次录音事实，绝不自动转为本次新承诺）
    public var historicalContextNotes: [String] = []
    /// P1-5：AI 延伸推测或建议（严格区分于原话事实与确认结论）
    public var aiInferences: [String] = []

    public init(
        suggestedTitle: String,
        summaryOrShortNote: String,
        backgroundPoints: [String] = [],
        keyPoints: [String] = [],
        decisions: [String] = [],
        chapters: [NoteChapter] = [],
        historicalContextNotes: [String] = [],
        aiInferences: [String] = []
    ) {
        self.suggestedTitle = suggestedTitle
        self.summaryOrShortNote = summaryOrShortNote
        self.backgroundPoints = backgroundPoints
        self.keyPoints = keyPoints
        self.decisions = decisions
        self.chapters = chapters
        self.historicalContextNotes = historicalContextNotes
        self.aiInferences = aiInferences
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.suggestedTitle = try c.decodeIfPresent(String.self, forKey: .suggestedTitle) ?? ""
        self.knowledgeReferences = try c.decodeIfPresent([KnowledgeReference].self, forKey: .knowledgeReferences) ?? []
        self.summaryOrShortNote = try c.decodeIfPresent(String.self, forKey: .summaryOrShortNote) ?? ""
        self.backgroundPoints = try c.decodeIfPresent([String].self, forKey: .backgroundPoints) ?? []
        self.keyPoints = try c.decodeIfPresent([String].self, forKey: .keyPoints) ?? []
        self.decisions = try c.decodeIfPresent([String].self, forKey: .decisions) ?? []
        self.chapters = try c.decodeIfPresent([NoteChapter].self, forKey: .chapters) ?? []
        self.historicalContextNotes = try c.decodeIfPresent([String].self, forKey: .historicalContextNotes) ?? []
        self.aiInferences = try c.decodeIfPresent([String].self, forKey: .aiInferences) ?? []
    }
}

/// 4. NoteRevision（笔记版本，支持 AI 生成与用户编辑隔离，PRD 8.3 & P1-4 版本溯源）
public struct NoteRevision: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var noteId: UUID
    public var mode: NoteMode
    public var generatedAt: Date
    public var content: StructuredNoteContent
    public var origin: RevisionOrigin
    public var previousRevisionId: UUID?
    /// 生成本版摘要时所依据的逐字稿指纹（用于识别重新转写后摘要是否仍基于旧稿，P1-4）
    public var sourceTranscriptDigest: String?
    /// 生成本版摘要时逐字稿是否已人工校对
    public var basedOnTranscriptReviewed: Bool?

    public init(
        id: UUID = UUID(),
        noteId: UUID,
        mode: NoteMode,
        generatedAt: Date = Date(),
        content: StructuredNoteContent,
        origin: RevisionOrigin,
        previousRevisionId: UUID? = nil,
        sourceTranscriptDigest: String? = nil,
        basedOnTranscriptReviewed: Bool? = nil
    ) {
        self.id = id
        self.noteId = noteId
        self.mode = mode
        self.generatedAt = generatedAt
        self.content = content
        self.origin = origin
        self.previousRevisionId = previousRevisionId
        self.sourceTranscriptDigest = sourceTranscriptDigest
        self.basedOnTranscriptReviewed = basedOnTranscriptReviewed
    }
}

/// 5. ActionDraft（AI 提取的行动候选草稿，带证据链，PRD 8.3 & 4.4）
public struct ActionDraft: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var recordingId: UUID
    public var revisionId: UUID
    public var kind: ActionKind
    public var description: String
    public var location: String?
    public var owner: String?
    public var ownership: ActionOwnership
    public var originalDateText: String?
    public var dueDate: Date?
    public var startAt: Date?
    public var endAt: Date?
    public var isDefaultDurationApplied: Bool
    public var appliedDefaultDurationMinutes: Int?
    public var datePrecision: DatePrecision
    public var timeZoneIdentifier: String
    public var sourceSegmentIds: [String]
    public var evidenceQuote: String
    public var evidenceStartMs: Int?
    public var evidenceEndMs: Int?
    public var isManualCreation: Bool
    public var isEvidenceVerifiedByUser: Bool
    public var proposedDestination: PrimaryDestination
    public var needsConfirmation: Bool
    public var confirmationReasons: [String]
    public var reviewStatus: DraftReviewStatus
    public var confirmedActionId: UUID?

    public init(
        id: UUID = UUID(),
        recordingId: UUID,
        revisionId: UUID,
        kind: ActionKind,
        description: String,
        location: String? = nil,
        owner: String? = nil,
        ownership: ActionOwnership = .selfOwner,
        originalDateText: String? = nil,
        dueDate: Date? = nil,
        startAt: Date? = nil,
        endAt: Date? = nil,
        isDefaultDurationApplied: Bool = false,
        appliedDefaultDurationMinutes: Int? = nil,
        datePrecision: DatePrecision = .none,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        sourceSegmentIds: [String] = [],
        evidenceQuote: String = "",
        evidenceStartMs: Int? = nil,
        evidenceEndMs: Int? = nil,
        isManualCreation: Bool = false,
        isEvidenceVerifiedByUser: Bool = false,
        proposedDestination: PrimaryDestination,
        needsConfirmation: Bool = false,
        confirmationReasons: [String] = [],
        reviewStatus: DraftReviewStatus = .pending,
        confirmedActionId: UUID? = nil
    ) {
        self.id = id
        self.recordingId = recordingId
        self.revisionId = revisionId
        self.kind = kind
        self.description = description
        self.location = location
        self.owner = owner
        self.ownership = ownership
        self.originalDateText = originalDateText
        self.dueDate = dueDate
        self.startAt = startAt
        self.endAt = endAt
        self.isDefaultDurationApplied = isDefaultDurationApplied
        self.appliedDefaultDurationMinutes = appliedDefaultDurationMinutes
        self.datePrecision = datePrecision
        self.timeZoneIdentifier = timeZoneIdentifier
        self.sourceSegmentIds = sourceSegmentIds
        self.evidenceQuote = evidenceQuote
        self.evidenceStartMs = evidenceStartMs
        self.evidenceEndMs = evidenceEndMs
        self.isManualCreation = isManualCreation
        self.isEvidenceVerifiedByUser = isEvidenceVerifiedByUser
        self.proposedDestination = proposedDestination
        self.needsConfirmation = needsConfirmation
        self.confirmationReasons = confirmationReasons
        self.reviewStatus = reviewStatus
        self.confirmedActionId = confirmedActionId
    }

    /// 是否有有效的原话证据与时间定位（PRD R23 & A22）
    public var hasValidEvidence: Bool {
        if isManualCreation || isEvidenceVerifiedByUser {
            return true
        }
        return !sourceSegmentIds.isEmpty
            && !evidenceQuote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && evidenceStartMs != nil
            && evidenceEndMs != nil
    }

    /// 是否允许直接参与批量一键执行（PRD P05 & A31）
    /// 缺失信息、证据未核实、他人负责且未转本人跟进、时间模糊的日历事件均禁止混入一键批量执行
    public var isEligibleForBatchExecution: Bool {
        guard hasValidEvidence else { return false }
        guard ownership == .selfOwner else { return false }
        guard !needsConfirmation else { return false }
        if kind == .event {
            guard datePrecision == .exactTime, startAt != nil, endAt != nil else { return false }
        }
        return reviewStatus == .pending
    }

    public var formattedEvidenceTimeRange: String? {
        guard let start = evidenceStartMs, let end = evidenceEndMs else { return nil }
        return "\(TimeFormatting.formatMilliseconds(start)) - \(TimeFormatting.formatMilliseconds(end))"
    }
}

/// 确认时的行动内容快照（PRD 8.3: confirmedSnapshot）
public struct ActionSnapshot: Codable, Equatable, Sendable {
    public var kind: ActionKind
    public var description: String
    public var location: String?
    public var owner: String?
    public var ownership: ActionOwnership
    public var originalDateText: String?
    public var dueDate: Date?
    public var startAt: Date?
    public var endAt: Date?
    public var datePrecision: DatePrecision
    public var timeZoneIdentifier: String
    public var evidenceQuote: String
    public var evidenceStartMs: Int?
    public var evidenceEndMs: Int?

    public init(from draft: ActionDraft) {
        self.kind = draft.kind
        self.description = draft.description
        self.location = draft.location
        self.owner = draft.owner
        self.ownership = draft.ownership
        self.originalDateText = draft.originalDateText
        self.dueDate = draft.dueDate
        self.startAt = draft.startAt
        self.endAt = draft.endAt
        self.datePrecision = draft.datePrecision
        self.timeZoneIdentifier = draft.timeZoneIdentifier
        self.evidenceQuote = draft.evidenceQuote
        self.evidenceStartMs = draft.evidenceStartMs
        self.evidenceEndMs = draft.evidenceEndMs
    }
}

/// 6. ConfirmedAction（用户确认后的独立行动，稳定 ID，重新整理不覆盖，PRD 8.3 & R08 & R19）
public struct ConfirmedAction: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var recordingId: UUID
    public var sourceDraftId: UUID
    public var confirmedSnapshot: ActionSnapshot
    public var confirmedAt: Date
    public var primaryDestination: PrimaryDestination
    /// 仅当 primaryDestination == .local 时有效；外部管理位置不维护第二份完成状态（PRD R25 & 8.3）
    public var localCompletion: Bool?
    public var executionStatus: ActionExecutionStatus
    /// 当重新生成笔记产生差异时，记录待用户核对的新草稿（PRD 6.2 & A25）
    public var pendingDiffDraft: ActionDraft?

    public init(
        id: UUID = UUID(),
        recordingId: UUID,
        sourceDraftId: UUID,
        confirmedSnapshot: ActionSnapshot,
        confirmedAt: Date = Date(),
        primaryDestination: PrimaryDestination,
        localCompletion: Bool? = nil,
        executionStatus: ActionExecutionStatus,
        pendingDiffDraft: ActionDraft? = nil
    ) {
        self.id = id
        self.recordingId = recordingId
        self.sourceDraftId = sourceDraftId
        self.confirmedSnapshot = confirmedSnapshot
        self.confirmedAt = confirmedAt
        self.primaryDestination = primaryDestination
        // 强制遵循 PRD R25：只有主要位置在本地时才保留 localCompletion
        self.localCompletion = (primaryDestination == .local) ? (localCompletion ?? false) : nil
        self.executionStatus = executionStatus
        self.pendingDiffDraft = pendingDiffDraft
    }

    /// 是否允许在 MemoFlow 内显示完成勾选框（PRD R25 & A23 & A30）
    public var allowsLocalCompletionToggle: Bool {
        primaryDestination == .local
    }
}

/// 7. ExternalActionLink（外部工具写入回执与关联，不代表实时完成状态，PRD 8.3）
public struct ExternalActionLink: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var confirmedActionId: UUID
    public var targetType: PrimaryDestination // .calendar or .reminders
    public var externalIdentifier: String?
    public var targetContainerIdentifier: String?
    public var targetContainerTitle: String?
    public var createdAt: Date
    public var lastConfirmedSnapshot: ActionSnapshot
    public var lastError: String?

    public init(
        id: UUID = UUID(),
        confirmedActionId: UUID,
        targetType: PrimaryDestination,
        externalIdentifier: String? = nil,
        targetContainerIdentifier: String? = nil,
        targetContainerTitle: String? = nil,
        createdAt: Date = Date(),
        lastConfirmedSnapshot: ActionSnapshot,
        lastError: String? = nil
    ) {
        self.id = id
        self.confirmedActionId = confirmedActionId
        self.targetType = targetType
        self.externalIdentifier = externalIdentifier
        self.targetContainerIdentifier = targetContainerIdentifier
        self.targetContainerTitle = targetContainerTitle
        self.createdAt = createdAt
        self.lastConfirmedSnapshot = lastConfirmedSnapshot
        self.lastError = lastError
    }
}

/// 8. ActionOperationLog（外部执行操作审计日志，PRD 8.3 & R19）
public struct ActionOperationLog: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var confirmedActionId: UUID
    public var operation: String
    public var requestedBy: String
    public var timestamp: Date
    public var status: ActionExecutionStatus
    public var errorCode: String?
    public var receipt: String?

    public init(
        id: UUID = UUID(),
        confirmedActionId: UUID,
        operation: String,
        requestedBy: String = "user",
        timestamp: Date = Date(),
        status: ActionExecutionStatus,
        errorCode: String? = nil,
        receipt: String? = nil
    ) {
        self.id = id
        self.confirmedActionId = confirmedActionId
        self.operation = operation
        self.requestedBy = requestedBy
        self.timestamp = timestamp
        self.status = status
        self.errorCode = errorCode
        self.receipt = receipt
    }
}

/// 分享导出结果
public enum ShareExportResult: String, Codable, Sendable {
    case completed = "completed"
    case cancelled = "cancelled"
    case failed = "failed"
}

/// 9. MarkdownExport（Markdown 导出记录，PRD 8.3 & A29）
public struct MarkdownExport: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var recordingId: UUID
    public var confirmedActionIds: [UUID]
    public var createdAt: Date
    public var shareResult: ShareExportResult
    public var destinationPath: String?
    public var vaultRelativePath: String?

    public init(
        id: UUID = UUID(),
        recordingId: UUID,
        confirmedActionIds: [UUID],
        createdAt: Date = Date(),
        shareResult: ShareExportResult,
        destinationPath: String? = nil,
        vaultRelativePath: String? = nil
    ) {
        self.id = id
        self.recordingId = recordingId
        self.confirmedActionIds = confirmedActionIds
        self.createdAt = createdAt
        self.shareResult = shareResult
        self.destinationPath = destinationPath
        self.vaultRelativePath = vaultRelativePath
    }
}

// MARK: - Obsidian Stable Binding, Managed Regions & Conflict Models (P0)

/// MemoFlow 受控生成区块标识（区块外与「个人补充」区始终归属用户手写内容）
public enum ObsidianManagedBlockKind: String, Codable, CaseIterable, Sendable {
    case header = "header"
    case summary = "summary"
    case actions = "actions"
    case marks = "marks"
    case chapters = "chapters"
    case transcript = "transcript"

    public var displayTitle: String {
        switch self {
        case .header: return "标题与元信息"
        case .summary: return "AI 笔记摘要与要点"
        case .actions: return "待办与日程"
        case .marks: return "高亮、批注与书签"
        case .chapters: return "录音章节"
        case .transcript: return "原话逐字稿"
        }
    }
}

/// 当用户在 Obsidian 修改了 AI 受控区块，同时 MemoFlow 重新整理生成了新内容时的双向版本冲突记录
public struct ObsidianBlockConflict: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var blockKind: ObsidianManagedBlockKind
    public var detectedAt: Date
    public var userEditedContent: String
    public var memoFlowGeneratedContent: String
    public var baseExportedDigest: String

    public init(
        id: UUID = UUID(),
        blockKind: ObsidianManagedBlockKind,
        detectedAt: Date = Date(),
        userEditedContent: String,
        memoFlowGeneratedContent: String,
        baseExportedDigest: String
    ) {
        self.id = id
        self.blockKind = blockKind
        self.detectedAt = detectedAt
        self.userEditedContent = userEditedContent
        self.memoFlowGeneratedContent = memoFlowGeneratedContent
        self.baseExportedDigest = baseExportedDigest
    }
}

/// 冲突解决选项
public enum ObsidianConflictResolutionChoice: String, Codable, CaseIterable, Sendable {
    case keepObsidianUserVersion = "keep_user"
    case adoptMemoFlowVersion = "adopt_memoflow"
    case keepBothMerged = "keep_both"

    public var displayTitle: String {
        switch self {
        case .keepObsidianUserVersion: return "保留 Obsidian 手改版"
        case .adoptMemoFlowVersion: return "采用 MemoFlow 新版"
        case .keepBothMerged: return "合并保留双方版本"
        }
    }
}

/// 历史无 ID 同名笔记的处理策略
public enum ObsidianLegacyResolution: Equatable, Sendable {
    case requireUserConfirmation
    case associateExisting(relativePath: String)
    case createSeparateNote
}

/// 录音与固定 Obsidian 笔记的关联状态
public enum ObsidianNoteBindingStatus: String, Codable, Equatable, Sendable {
    case synced = "synced"
    case needsLegacyConfirmation = "needs_legacy_confirmation"
    case hasConflict = "has_conflict"
    case missingInVault = "missing_in_vault"
    case cloudNotDownloaded = "cloud_not_downloaded"
    case authorizationExpired = "authorization_expired"

    public var displayTitle: String {
        switch self {
        case .synced: return "笔记已关联同步"
        case .needsLegacyConfirmation: return "发现同名历史笔记待确认"
        case .hasConflict: return "存在手改冲突待选择"
        case .missingInVault: return "库内笔记已移除"
        case .cloudNotDownloaded: return "iCloud 笔记未下载"
        case .authorizationExpired: return "目录授权失效"
        }
    }
}

/// 录音与单篇 Obsidian 笔记的稳定绑定记录（基于 recording_id + 相对路径）
public struct ObsidianNoteBinding: Codable, Equatable, Sendable {
    public var recordingId: UUID
    public var vaultRelativePath: String
    public var lastKnownFileName: String
    public var lastExportedRevisionId: UUID?
    public var lastExportedAt: Date?
    public var lastSyncedFileSHA256: String?
    public var lastSyncedModificationDate: Date?
    public var managedBlockDigests: [String: String]
    public var managedBlockSnapshots: [String: String]
    public var status: ObsidianNoteBindingStatus
    public var pendingLegacyCandidatePaths: [String]
    public var conflicts: [ObsidianBlockConflict]
    public var lastBackupFilePath: String?
    public var lastErrorMessage: String?

    public init(
        recordingId: UUID,
        vaultRelativePath: String,
        lastKnownFileName: String,
        lastExportedRevisionId: UUID? = nil,
        lastExportedAt: Date? = nil,
        lastSyncedFileSHA256: String? = nil,
        lastSyncedModificationDate: Date? = nil,
        managedBlockDigests: [String: String] = [:],
        managedBlockSnapshots: [String: String] = [:],
        status: ObsidianNoteBindingStatus = .synced,
        pendingLegacyCandidatePaths: [String] = [],
        conflicts: [ObsidianBlockConflict] = [],
        lastBackupFilePath: String? = nil,
        lastErrorMessage: String? = nil
    ) {
        self.recordingId = recordingId
        self.vaultRelativePath = vaultRelativePath
        self.lastKnownFileName = lastKnownFileName
        self.lastExportedRevisionId = lastExportedRevisionId
        self.lastExportedAt = lastExportedAt
        self.lastSyncedFileSHA256 = lastSyncedFileSHA256
        self.lastSyncedModificationDate = lastSyncedModificationDate
        self.managedBlockDigests = managedBlockDigests
        self.managedBlockSnapshots = managedBlockSnapshots
        self.status = status
        self.pendingLegacyCandidatePaths = pendingLegacyCandidatePaths
        self.conflicts = conflicts
        self.lastBackupFilePath = lastBackupFilePath
        self.lastErrorMessage = lastErrorMessage
    }
}

/// 10. ProcessingConsent（云处理授权偏好记录，PRD R12 & 8.3 & A28）
public struct ProcessingConsent: Codable, Equatable, Sendable {
    public var provider: String
    public var purpose: String
    public var policyVersion: String
    public var grantedAt: Date?
    public var mode: ConsentMode
    public var revokedAt: Date?

    public init(
        provider: String = "OpenAI 兼容接口 (ASR + LLM)",
        purpose: String = "将本地录音上传进行语音转写，并提取结构化笔记与待办日程草稿（不用于模型训练）",
        policyVersion: String = "1.1",
        grantedAt: Date? = nil,
        mode: ConsentMode = .askEveryTime,
        revokedAt: Date? = nil
    ) {
        self.provider = provider
        self.purpose = purpose
        self.policyVersion = policyVersion
        self.grantedAt = grantedAt
        self.mode = mode
        self.revokedAt = revokedAt
    }

    /// 是否允许在不弹窗询问的情况下直接自动上传处理新录音
    public var canAutoProcessWithoutPrompt: Bool {
        guard grantedAt != nil, revokedAt == nil else { return false }
        return mode == .remembered
    }
}

/// 11. ProcessingJob（后台/异步处理任务状态，PRD 8.3）
public struct ProcessingJob: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var recordingId: UUID
    public var stage: RecordingProcessingStatus
    public var status: String
    public var errorCode: String?
    public var attempts: Int
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        recordingId: UUID,
        stage: RecordingProcessingStatus,
        status: String,
        errorCode: String? = nil,
        attempts: Int = 1,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.recordingId = recordingId
        self.stage = stage
        self.status = status
        self.errorCode = errorCode
        self.attempts = attempts
        self.updatedAt = updatedAt
    }
}

// MARK: - P1 Deep Links, Version Provenance, Personal Memory & Grounded QA Models

/// P1-4：评估当前逐字稿审核状态与 AI 摘要的版本对齐关系
public struct NoteVersionProvenance: Equatable, Sendable {
    public let transcriptReviewStatusCode: String
    public let transcriptReviewDisplayTitle: String
    public let isSummaryBasedOnOlderTranscript: Bool
    public let summaryAlignmentCode: String
    public let summaryAlignmentDisplayTitle: String

    public static func transcriptDigest(for segments: [TranscriptSegment]) -> String {
        let joined = segments.map { "\($0.startMs)-\($0.endMs):\($0.text)" }.joined(separator: "\n")
        var hash: UInt64 = 14695981039346656037
        for byte in joined.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }

    public static func evaluate(
        recording: Recording,
        revision: NoteRevision,
        segments: [TranscriptSegment]
    ) -> NoteVersionProvenance {
        let currentDigest = transcriptDigest(for: segments)
        var stale = false
        if recording.processingStatus == .transcriptNeedsReview {
            stale = true
        } else if let revDigest = revision.sourceTranscriptDigest,
                  !revDigest.isEmpty,
                  !segments.isEmpty,
                  revDigest != currentDigest {
            stale = true
        } else if let completedAt = recording.transcriptSource?.completedAt,
                  revision.generatedAt.addingTimeInterval(1.0) < completedAt {
            stale = true
        }

        let alignmentCode: String
        let alignmentTitle: String
        if stale {
            alignmentCode = "stale_against_newer_transcript"
            alignmentTitle = "摘要仍基于旧版逐字稿（逐字稿已更新或待校对）"
        } else if recording.isTranscriptReviewed == true {
            alignmentCode = "aligned_with_reviewed_transcript"
            alignmentTitle = "摘要基于已校对逐字稿"
        } else {
            alignmentCode = "aligned_with_unreviewed_machine_draft"
            alignmentTitle = "摘要基于未人工校对的机器稿"
        }

        return NoteVersionProvenance(
            transcriptReviewStatusCode: recording.transcriptReviewStatusCode,
            transcriptReviewDisplayTitle: recording.transcriptReviewDisplayTitle,
            isSummaryBasedOnOlderTranscript: stale,
            summaryAlignmentCode: alignmentCode,
            summaryAlignmentDisplayTitle: alignmentTitle
        )
    }
}

/// P1-3：MemoFlow 应用内双向深链解析与构造（`memoflow://recording/<UUID>?startMs=...&endMs=...&estimated=1`）
public struct MemoFlowDeepLink: Equatable, Sendable {
    public let recordingId: UUID
    public let startMs: Int?
    public let endMs: Int?
    public let isEstimated: Bool

    public init(recordingId: UUID, startMs: Int? = nil, endMs: Int? = nil, isEstimated: Bool = false) {
        self.recordingId = recordingId
        self.startMs = startMs
        self.endMs = endMs
        self.isEstimated = isEstimated
    }

    public static func recordingURL(
        recordingId: UUID,
        startMs: Int? = nil,
        endMs: Int? = nil,
        isEstimated: Bool = false
    ) -> URL? {
        var comps = URLComponents()
        comps.scheme = "memoflow"
        comps.host = "recording"
        comps.path = "/\(recordingId.uuidString)"
        var items: [URLQueryItem] = []
        if let startMs {
            items.append(URLQueryItem(name: "startMs", value: String(startMs)))
        }
        if let endMs {
            items.append(URLQueryItem(name: "endMs", value: String(endMs)))
        }
        if isEstimated {
            items.append(URLQueryItem(name: "estimated", value: "1"))
        }
        if !items.isEmpty {
            comps.queryItems = items
        }
        return comps.url
    }

    public static func parse(_ url: URL) -> MemoFlowDeepLink? {
        guard url.scheme?.lowercased() == "memoflow" else { return nil }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        let host = comps.host?.lowercased() ?? ""
        let trimmedPath = comps.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let resolvedUUID: UUID?
        if host == "recording", let id = UUID(uuidString: trimmedPath) {
            resolvedUUID = id
        } else if let hostUUID = UUID(uuidString: host) {
            resolvedUUID = hostUUID
        } else if let queryId = comps.queryItems?.first(where: { $0.name == "recordingId" || $0.name == "id" })?.value,
                  let id = UUID(uuidString: queryId) {
            resolvedUUID = id
        } else {
            resolvedUUID = nil
        }

        guard let recordingId = resolvedUUID else { return nil }

        let startVal = comps.queryItems?.first(where: { $0.name == "startMs" || $0.name == "t" })?.value.flatMap(Int.init)
        let endVal = comps.queryItems?.first(where: { $0.name == "endMs" })?.value.flatMap(Int.init)
        let estRaw = comps.queryItems?.first(where: { $0.name == "estimated" })?.value?.lowercased()
        let isEstimated = (estRaw == "1" || estRaw == "true")

        return MemoFlowDeepLink(
            recordingId: recordingId,
            startMs: startVal,
            endMs: endVal,
            isEstimated: isEstimated
        )
    }
}

public struct DeepLinkNavigationRequest: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let recordingId: UUID
    public let targetStartMs: Int?
    public let targetEndMs: Int?
    public let isEstimated: Bool

    public init(
        id: UUID = UUID(),
        recordingId: UUID,
        targetStartMs: Int?,
        targetEndMs: Int? = nil,
        isEstimated: Bool = false
    ) {
        self.id = id
        self.recordingId = recordingId
        self.targetStartMs = targetStartMs
        self.targetEndMs = targetEndMs
        self.isEstimated = isEstimated
    }
}

public enum DeepLinkOutcome: Equatable, Sendable {
    case opened(recordingId: UUID, targetMs: Int?, isEstimated: Bool)
    case clampedOutOfBounds(recordingId: UUID, requestedMs: Int, clampedMs: Int)
    case audioMissingOnDevice(recordingId: UUID, targetMs: Int?, message: String)
    case recordingNotFound(recordingId: UUID)
    case invalidURL(String)
}

/// P1-5：可审阅、确认、编辑和删除的个人记忆条目
public enum PersonalMemoryCategory: String, Codable, CaseIterable, Sendable {
    case project = "project"
    case term = "term"
    case person = "person"
    case preference = "preference"

    public var displayTitle: String {
        switch self {
        case .project: return "项目背景"
        case .term: return "领域术语"
        case .person: return "协作角色"
        case .preference: return "个人习惯"
        }
    }
}

public enum PersonalMemoryStatus: String, Codable, CaseIterable, Sendable {
    case pendingReview = "pending_review"
    case confirmed = "confirmed"

    public var displayTitle: String {
        switch self {
        case .pendingReview: return "待审阅"
        case .confirmed: return "已确认生效"
        }
    }
}

public struct PersonalMemoryItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var category: PersonalMemoryCategory
    public var key: String
    public var value: String
    public var sourceRecordingId: UUID?
    public var sourceNotePath: String?
    public var status: PersonalMemoryStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        category: PersonalMemoryCategory,
        key: String,
        value: String,
        sourceRecordingId: UUID? = nil,
        sourceNotePath: String? = nil,
        status: PersonalMemoryStatus = .pendingReview,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.key = key
        self.value = value
        self.sourceRecordingId = sourceRecordingId
        self.sourceNotePath = sourceNotePath
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// P1-5：跨笔记检索与问答的实际来源引用（关联笔记路径 + 相关录音时间戳）
public struct GroundedCitation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var noteRelativePath: String?
    public var noteTitle: String
    public var recordingId: UUID?
    public var startMs: Int?
    public var endMs: Int?
    public var isEstimated: Bool
    public var excerpt: String

    public init(
        id: UUID = UUID(),
        noteRelativePath: String? = nil,
        noteTitle: String,
        recordingId: UUID? = nil,
        startMs: Int? = nil,
        endMs: Int? = nil,
        isEstimated: Bool = false,
        excerpt: String
    ) {
        self.id = id
        self.noteRelativePath = noteRelativePath
        self.noteTitle = noteTitle
        self.recordingId = recordingId
        self.startMs = startMs
        self.endMs = endMs
        self.isEstimated = isEstimated
        self.excerpt = excerpt
    }
}

public struct GroundedQAResult: Equatable, Sendable {
    public var question: String
    public var answer: String
    public var citations: [GroundedCitation]
    public var capabilityDisclosure: String
    public var usedCloudLLM: Bool

    public init(
        question: String,
        answer: String,
        citations: [GroundedCitation],
        capabilityDisclosure: String,
        usedCloudLLM: Bool = false
    ) {
        self.question = question
        self.answer = answer
        self.citations = citations
        self.capabilityDisclosure = capabilityDisclosure
        self.usedCloudLLM = usedCloudLLM
    }
}

// MARK: - Formatting Helpers

public enum TimeFormatting {
    public static func formatMilliseconds(_ ms: Int) -> String {
        let totalSeconds = max(0, ms / 1000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    public static func formatDuration(_ duration: TimeInterval) -> String {
        formatMilliseconds(Int(duration * 1000))
    }
}
