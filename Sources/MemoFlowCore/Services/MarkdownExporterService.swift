import Foundation

/// 负责生成结构清晰、层次分明的 Obsidian 兼容 Markdown（包含总结、待办与日程、录音章节、逐字稿，且严格遵守 PRD 第 07 节与 R25 规范）
public enum MarkdownExporterService {

    /// 导出标题优先采用整理出的主题；旧笔记没有主题时，从摘要或大纲提取。
    public static func exportTitle(recording: Recording, revision: NoteRevision) -> String {
        let content = revision.content
        let suggested = singleLine(content.suggestedTitle)
        let isPlaceholder = suggested.range(
            of: #"^(随手记|会议记)\s+\d{2}-\d{2}\s+\d{2}:\d{2}$"#,
            options: .regularExpression
        ) != nil
        if !suggested.isEmpty && !isPlaceholder {
            return String(suggested.prefix(60))
        }
        let candidates = [content.summaryOrShortNote] + content.chapters.map(\.title) + content.keyPoints
        for candidate in candidates {
            let text = singleLine(candidate)
                .components(separatedBy: CharacterSet(charactersIn: "。！？；!?;"))
                .first ?? ""
            if !text.isEmpty { return String(text.prefix(30)) }
        }
        let original = singleLine(recording.title)
        return original.isEmpty ? "录音笔记" : String(original.prefix(60))
    }

    private static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func safeFileTitle(_ title: String) -> String {
        let cleaned = singleLine(title)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|[]#^").union(.controlCharacters))
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return cleaned.isEmpty ? "录音笔记" : String(cleaned.prefix(60))
    }

    public static func generateMarkdown(
        recording: Recording,
        note: Note,
        revision: NoteRevision,
        confirmedActions: [ConfirmedAction],
        segments: [TranscriptSegment],
        pendingDrafts: [ActionDraft] = []
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.timeZone = recording.recordedTimeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let dateStr = dateFormatter.string(from: recording.createdAt)
        let durationStr = TimeFormatting.formatDuration(recording.duration)
        let modeTag = (revision.mode == .quickNote) ? "随手记" : "会议"

        let title = exportTitle(recording: recording, revision: revision)
        var lines: [String] = []
        lines.append("---")
        lines.append("title: \(escapeYAML(title))")
        lines.append("date: \(dateStr)")
        lines.append("source: MemoFlow")
        lines.append("mode: \(modeTag)")
        lines.append("duration: \"\(durationStr)\"")
        if let project = note.projectName, !project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("project: \"[[\(project)]]\"")
        }
        lines.append("tags: [录音笔记, \(modeTag)]")
        lines.append("---")
        lines.append("")
        lines.append("# \(title)")
        lines.append("")

        let content = revision.content

        if !content.knowledgeReferences.isEmpty {
            lines.append("## 提供给 AI 的知识库背景")
            lines.append("以下笔记片段用于辅助理解，不代表本次录音的新承诺。")
            for reference in content.knowledgeReferences {
                lines.append("- \(reference.path)")
            }
            lines.append("")
        }

        // 1. 总结区块（核心总结 / 随手记精简总结）
        if revision.mode == .quickNote {
            // 随手记（PRD 6.1 & A20）：展示核心总结，不凑空的「关键观点」「已确认结论」章节
            if !content.summaryOrShortNote.isEmpty {
                lines.append("## 核心总结")
                lines.append(content.summaryOrShortNote)
                lines.append("")
            }
        } else {
            // 会议记（PRD 6.1 & 7.2）
            if !content.summaryOrShortNote.isEmpty {
                lines.append("## 一句话摘要")
                lines.append(content.summaryOrShortNote)
                lines.append("")
            }

            if !content.backgroundPoints.isEmpty {
                lines.append("## 必要背景")
                for item in content.backgroundPoints {
                    lines.append("- \(item)")
                }
                lines.append("")
            }

            if !content.keyPoints.isEmpty {
                lines.append("## 关键观点")
                for item in content.keyPoints {
                    lines.append("- \(item)")
                }
                lines.append("")
            }

            if !content.decisions.isEmpty {
                lines.append("## 已确认结论")
                for item in content.decisions {
                    lines.append("- \(item)")
                }
                lines.append("")
            }
        }

        // 2. 待办与行动记录区块（包含已确认行动 + 尚未确认的待办/日程草稿，确保直接导入 Obsidian 也不漏待办）
        let visibleConfirmed = confirmedActions.filter { $0.executionStatus != .ignored }
        let confirmedDraftIds = Set(visibleConfirmed.map(\.sourceDraftId))
        let unconfirmedActiveDrafts = pendingDrafts.filter {
            ($0.reviewStatus == .pending || $0.reviewStatus == .needsInfo) && !confirmedDraftIds.contains($0.id)
        }

        if !visibleConfirmed.isEmpty || !unconfirmedActiveDrafts.isEmpty {
            lines.append("## 行动记录")
            for action in visibleConfirmed {
                lines.append(formatActionLine(action, recordingTimeZone: recording.recordedTimeZone))
            }
            for draft in unconfirmedActiveDrafts {
                lines.append(formatPendingDraftLine(draft, recordingTimeZone: recording.recordedTimeZone))
            }
            lines.append("")
        }

        // 3. 录音章节区块（按时间轴划分每个录音的章节小标题与要点，让长短录音在 Obsidian 中结构清晰）
        let resolvedChapters: [NoteChapter] = {
            if !content.chapters.isEmpty {
                return content.chapters
            }
            return ASRAndLLMService.shared.buildChaptersFromSegments(segments)
        }()

        if !resolvedChapters.isEmpty {
            lines.append("## 录音章节")
            for (index, chapter) in resolvedChapters.enumerated() {
                let numStr = String(format: "%02d", index + 1)
                lines.append("### \(numStr). [\(chapter.formattedTimeRange)] \(chapter.title)")
                lines.append(chapter.summary)
                lines.append("")
            }
        }

        // 4. 完整逐字稿区块（PRD 7.2 & V1.2 说话人识别）
        if !segments.isEmpty {
            lines.append("## 逐字稿")
            for seg in segments {
                let speakerPrefix = (seg.speakerName?.isEmpty == false) ? "**\(seg.speakerName!)**: " : ""
                lines.append("- [\(seg.formattedStartTime)] \(speakerPrefix)\(seg.text)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// 遵循 PRD R25 & 7.2 & 7.3：
    /// - 仅主要位置为 Markdown 的任务使用 `- [ ]`
    /// - 已交给 Apple 提醒事项 / 日历 / 本地管理的事项仅作为普通列表引用，不生成第二份 checkbox
    public static func formatActionLine(
        _ action: ConfirmedAction,
        recordingTimeZone: TimeZone
    ) -> String {
        let snap = action.confirmedSnapshot
        let ownerText = (snap.owner?.isEmpty == false) ? snap.owner! : "未明确"
        let sourceTimeText = snap.evidenceStartMs.map { TimeFormatting.formatMilliseconds($0) } ?? "手动添加"

        let dateSummary = formatActionDateSummary(snapshot: snap, timeZone: recordingTimeZone)

        switch action.primaryDestination {
        case .markdown:
            return "- [ ] \(snap.description)（主要管理位置：Markdown；负责人：\(ownerText)；截止时间：\(dateSummary)；来源：\(sourceTimeText)）"

        case .reminders:
            let resultLabel = (action.executionStatus == .handedToExternal) ? "已创建" : action.executionStatus.displayTitle
            return "- \(snap.description)（主要管理位置：Apple 提醒事项；创建结果：\(resultLabel)；完成状态：以提醒事项为准；来源：\(sourceTimeText)）"

        case .calendar:
            let resultLabel = (action.executionStatus == .handedToExternal) ? "已创建" : action.executionStatus.displayTitle
            return "- \(snap.description)（主要管理位置：Apple 日历；时间：\(dateSummary)；创建结果：\(resultLabel)；来源：\(sourceTimeText)）"

        case .local:
            let stateText = (action.localCompletion == true) ? "已完成" : "未完成"
            return "- \(snap.description)（主要管理位置：MemoFlow 本地；当前状态：\(stateText)；来源：\(sourceTimeText)）"
        }
    }

    /// 针对尚未在 App 内点确认、但直接导出到 Obsidian 的待审核候选，按类别清晰输出
    public static func formatPendingDraftLine(
        _ draft: ActionDraft,
        recordingTimeZone: TimeZone
    ) -> String {
        let snap = ActionSnapshot(from: draft)
        let ownerText = (draft.owner?.isEmpty == false) ? draft.owner! : "未明确"
        let sourceTimeText = draft.evidenceStartMs.map { TimeFormatting.formatMilliseconds($0) } ?? "未定位"
        let dateSummary = formatActionDateSummary(snapshot: snap, timeZone: recordingTimeZone)

        if draft.ownership == .other {
            return "- [他人负责 · \(ownerText)] \(draft.description)（时间：\(dateSummary)；来源：\(sourceTimeText)）"
        }
        if draft.kind == .event {
            return "- [日程待确认] \(draft.description)（时间：\(dateSummary)；建议去向：Apple 日历；来源：\(sourceTimeText)）"
        }
        return "- [ ] \(draft.description)（待确认待办；负责人：\(ownerText)；截止时间：\(dateSummary)；来源：\(sourceTimeText)）"
    }

    private static func formatActionDateSummary(snapshot: ActionSnapshot, timeZone: TimeZone) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.timeZone = timeZone

        switch snapshot.datePrecision {
        case .exactTime:
            fmt.dateFormat = "yyyy-MM-dd HH:mm"
            if let start = snapshot.startAt, let end = snapshot.endAt {
                let endFmt = DateFormatter()
                endFmt.timeZone = timeZone
                endFmt.dateFormat = "HH:mm"
                return "\(fmt.string(from: start))-\(endFmt.string(from: end))"
            } else if let start = snapshot.startAt {
                return fmt.string(from: start)
            }
            return snapshot.originalDateText ?? "未明确"
        case .dateOnly:
            fmt.dateFormat = "yyyy-MM-dd"
            if let due = snapshot.dueDate {
                return fmt.string(from: due)
            }
            return snapshot.originalDateText ?? "未明确"
        case .none, .ambiguous:
            return snapshot.originalDateText ?? "未明确"
        }
    }

    public static func writeTemporaryMarkdownFile(
        recording: Recording,
        markdownContent: String,
        title: String? = nil
    ) throws -> URL {
        let safeTitle = safeFileTitle(title ?? recording.title)
        let fileName = "\(safeTitle.isEmpty ? "MemoFlow笔记" : safeTitle).md"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try markdownContent.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    /// 直接写入用户授权选定的 Obsidian 笔记库目录（PRD R15）
    public static func writeDirectlyToObsidianVault(
        recording: Recording,
        markdownContent: String,
        vaultRootPath: String,
        subfolder: String,
        title: String? = nil
    ) throws -> (fileURL: URL, obsidianOpenURL: URL?) {
        let root = URL(fileURLWithPath: vaultRootPath, isDirectory: true)
        var coordinatedError: NSError?
        var result: Result<(fileURL: URL, obsidianOpenURL: URL?), Error>?
        NSFileCoordinator().coordinate(writingItemAt: root, options: .forMerging, error: &coordinatedError) { url in
            result = Result { try writeVaultFile(recording: recording, markdownContent: markdownContent, vaultRootPath: url.path, subfolder: subfolder, title: title) }
        }
        if let error = coordinatedError { throw error }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }

    private static func writeVaultFile(
        recording: Recording,
        markdownContent: String,
        vaultRootPath: String,
        subfolder: String,
        title: String?
    ) throws -> (fileURL: URL, obsidianOpenURL: URL?) {
        let rootURL = URL(fileURLWithPath: vaultRootPath, isDirectory: true)
        let cleanSub = subfolder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSub.hasPrefix("/"), !cleanSub.split(separator: "/").contains("..") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let targetDirURL = cleanSub.isEmpty ? rootURL : rootURL.appendingPathComponent(cleanSub, isDirectory: true)

        try FileManager.default.createDirectory(at: targetDirURL, withIntermediateDirectories: true)

        let dateFmt = DateFormatter()
        dateFmt.timeZone = recording.recordedTimeZone
        dateFmt.dateFormat = "yyyy-MM-dd"
        let datePrefix = dateFmt.string(from: recording.createdAt)

        let safeTitle = safeFileTitle(title ?? recording.title)
        let fileName = "\(datePrefix)-\(safeTitle.isEmpty ? "录音笔记" : safeTitle).md"
        let fileURL = uniqueFileURL(
            preferredURL: targetDirURL.appendingPathComponent(fileName),
            fileManager: .default
        )

        try markdownContent.write(to: fileURL, atomically: true, encoding: .utf8)

        var comps = URLComponents(string: "obsidian://open")
        comps?.queryItems = [URLQueryItem(name: "path", value: fileURL.path)]
        return (fileURL, comps?.url)
    }

    /// 避免重复导出覆盖用户已经在 Obsidian 中编辑过的笔记。
    /// 首次导出使用稳定文件名；同名文件存在时追加序号。
    private static func uniqueFileURL(preferredURL: URL, fileManager: FileManager) -> URL {
        guard fileManager.fileExists(atPath: preferredURL.path) else { return preferredURL }

        let base = preferredURL.deletingPathExtension().lastPathComponent
        let ext = preferredURL.pathExtension
        var index = 2
        while true {
            let candidateName = "\(base)-\(index).\(ext)"
            let candidate = preferredURL.deletingLastPathComponent().appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private static func escapeYAML(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
