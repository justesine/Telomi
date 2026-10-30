import Foundation

extension MarkdownExporterService {
    public static func renderTranscript(recording: Recording, segments: [TranscriptSegment]) -> String {
        var lines = [
            "# \(recording.title)",
            "",
            "录音 ID：\(recording.id.uuidString)",
            "录音时间：\(formatISOTimestamp(recording.createdAt, timeZone: recording.recordedTimeZone))（\(recording.recordedTimeZoneIdentifier)）",
            "时长：\(TimeFormatting.formatDuration(recording.duration))",
            "逐字稿审核状态：\(recording.transcriptReviewDisplayTitle)",
            "音频文件：\(recording.localAudioFileName)",
            ""
        ]
        if let source = recording.transcriptSource {
            lines += ["音频 SHA-256：\(source.sha256)", "转写引擎：\(source.engine)", ""]
        } else { lines += ["历史逐字稿未校验音频来源，请回听核查。", ""] }
        lines += ["## 书签与批注", ""]
        for mark in recording.marks ?? [] {
            let link = formatVerifiableTimestampLink(
                recording: recording,
                startMs: mark.startMs,
                endMs: mark.endMs,
                isEstimated: false,
                rangeDisplay: false
            )
            lines.append("- \(link) \(mark.quote)")
            if !mark.note.isEmpty { lines.append("  批注：\(mark.note)") }
        }
        lines += ["", "## 逐字稿", ""]
        for segment in segments {
            let link = formatVerifiableTimestampLink(
                recording: recording,
                startMs: segment.startMs,
                endMs: segment.endMs,
                isEstimated: segment.timingIsEstimated == true,
                rangeDisplay: true
            )
            lines += ["\(link) \(segment.effectiveSpeakerDisplay)：\(segment.text)", ""]
        }
        return lines.joined(separator: "\n")
    }
}

/// 负责生成结构清晰、层次分明的 Obsidian 兼容 Markdown（包含总结、待办与日程、书签批注、录音章节、逐字稿，且严格遵守 PRD 第 07 节与 R25 规范）
public enum MarkdownExporterService {

    public static let systemManagedTags: Set<String> = ["录音笔记", "随手记", "会议", "会议记"]

    /// 导出标题优先采用用户修改后的录音标题或整理出的主题；旧笔记没有主题时，从摘要或大纲提取。
    public static func exportTitle(recording: Recording, revision: NoteRevision) -> String {
        let trimmedRecordingTitle = singleLine(recording.title)
        let isRecordingTitlePlaceholder = trimmedRecordingTitle.range(
            of: #"^(随手记|会议记)\s+\d{2}-\d{2}\s+\d{2}:\d{2}$"#,
            options: .regularExpression
        ) != nil
        if !trimmedRecordingTitle.isEmpty && !isRecordingTitlePlaceholder {
            return String(trimmedRecordingTitle.prefix(60))
        }

        let content = revision.content
        let suggested = singleLine(content.suggestedTitle)
        let isSuggestedPlaceholder = suggested.range(
            of: #"^(随手记|会议记)\s+\d{2}-\d{2}\s+\d{2}:\d{2}$"#,
            options: .regularExpression
        ) != nil
        if !suggested.isEmpty && !isSuggestedPlaceholder {
            return String(suggested.prefix(60))
        }
        let candidates = [content.summaryOrShortNote] + content.chapters.map(\.title) + content.keyPoints
        for candidate in candidates {
            let text = singleLine(candidate)
                .components(separatedBy: CharacterSet(charactersIn: "。！？；!?;"))
                .first ?? ""
            if !text.isEmpty { return String(text.prefix(30)) }
        }
        return trimmedRecordingTitle.isEmpty ? "录音笔记" : String(trimmedRecordingTitle.prefix(60))
    }

    public static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static func safeFileTitle(_ title: String) -> String {
        let cleaned = singleLine(title)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|[]#^").union(.controlCharacters))
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return cleaned.isEmpty ? "录音笔记" : String(cleaned.prefix(60))
    }

    public static func preferredFileName(recording: Recording, title: String) -> String {
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.timeZone = recording.recordedTimeZone
        dateFmt.dateFormat = "yyyy-MM-dd"
        let datePrefix = dateFmt.string(from: recording.createdAt)
        let safeTitle = safeFileTitle(title)
        return "\(datePrefix)-\(safeTitle.isEmpty ? "录音笔记" : safeTitle).md"
    }

    /// 生成跨端（macOS + iOS）通用的 Obsidian 打开链接（优先使用 vault + file 相对路径，避免仅 Mac 有效的绝对路径）
    public static func obsidianOpenURL(
        vaultRootURL: URL,
        relativePath: String
    ) -> URL? {
        let vaultName = vaultRootURL.lastPathComponent
        let cleanRel = relativePath
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fileParam: String
        if cleanRel.lowercased().hasSuffix(".md") {
            fileParam = String(cleanRel.dropLast(3))
        } else {
            fileParam = cleanRel
        }
        var comps = URLComponents(string: "obsidian://open")
        if !vaultName.isEmpty && !fileParam.isEmpty {
            comps?.queryItems = [
                URLQueryItem(name: "vault", value: vaultName),
                URLQueryItem(name: "file", value: fileParam)
            ]
        } else {
            let fullURL = vaultRootURL.appendingPathComponent(cleanRel)
            comps?.queryItems = [URLQueryItem(name: "path", value: fullURL.path)]
        }
        return comps?.url
    }

    public static func managedBlockStartMarker(_ kind: ObsidianManagedBlockKind) -> String {
        "<!-- memoflow:block:\(kind.rawValue):start -->"
    }

    public static func managedBlockEndMarker(_ kind: ObsidianManagedBlockKind) -> String {
        "<!-- memoflow:block:\(kind.rawValue):end -->"
    }

    public static let userSupplementStartMarker = "<!-- memoflow:user:supplement:start -->"
    public static let userSupplementEndMarker = "<!-- memoflow:user:supplement:end -->"

    public static func recordingAnchorComment(for recordingId: UUID) -> String {
        "<!-- memoflow:recording_id=\(recordingId.uuidString) -->"
    }

    /// 规范化关联项目为 Obsidian 内部双链格式 `[[项目名]]`
    public static func formatProjectWikiLink(_ rawProject: String?) -> String? {
        guard let raw = rawProject?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("[[") && raw.hasSuffix("]]") {
            let inner = String(raw.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            return inner.isEmpty ? nil : "[[\(inner)]]"
        }
        return "[[\(raw)]]"
    }

    /// 从 `[[项目名]]` 或普通文本还原纯项目名称
    public static func unwrapProjectWikiLink(_ rawValue: String?) -> String? {
        guard var raw = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if (raw.hasPrefix("\"") && raw.hasSuffix("\"")) || (raw.hasPrefix("'") && raw.hasSuffix("'")) {
            raw = String(raw.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if raw.hasPrefix("[[") && raw.hasSuffix("]]") {
            raw = String(raw.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return raw.isEmpty ? nil : raw
    }

    public static func formatISOTimestamp(_ date: Date, timeZone: TimeZone) -> String {
        let iso = ISO8601DateFormatter()
        iso.timeZone = timeZone
        iso.formatOptions = [.withInternetDateTime]
        return iso.string(from: date)
    }

    /// 生成可点击的 `memoflow://` 时间戳深链：
    /// - 估算时间戳明确标注「约」并附带 `estimated=1`
    /// - 当音频来源不可核验（如缺少音频文件名、负值、超出录音总时长）时绝不伪造精确定位链接，如实标记为 `[来源待核验]`
    public static func formatVerifiableTimestampLink(
        recording: Recording,
        startMs: Int?,
        endMs: Int? = nil,
        isEstimated: Bool = false,
        rangeDisplay: Bool = false,
        kindPrefix: String? = nil
    ) -> String {
        let hasAudioSource = !recording.localAudioFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let maxAllowedMs = Int(ceil(max(0, recording.duration) * 1000)) + 1000
        guard hasAudioSource,
              let start = startMs,
              start >= 0,
              (recording.duration <= 0 || start <= maxAllowedMs) else {
            if let kindPrefix, !kindPrefix.isEmpty {
                return "[\(kindPrefix) · 来源待核验]"
            }
            return "[来源待核验]"
        }

        let validEnd: Int?
        if let end = endMs, end > start {
            validEnd = (recording.duration > 0) ? min(end, maxAllowedMs) : end
        } else {
            validEnd = nil
        }

        let estPrefix = isEstimated ? "约 " : ""
        let timeText: String
        if rangeDisplay, let end = validEnd {
            timeText = "\(estPrefix)\(TimeFormatting.formatMilliseconds(start)) - \(TimeFormatting.formatMilliseconds(end))"
        } else {
            timeText = "\(estPrefix)\(TimeFormatting.formatMilliseconds(start))"
        }

        let label: String
        if let kindPrefix, !kindPrefix.isEmpty {
            label = "\(kindPrefix) · \(timeText)"
        } else {
            label = timeText
        }

        if let deepURL = MemoFlowDeepLink.recordingURL(
            recordingId: recording.id,
            startMs: start,
            endMs: validEnd,
            isEstimated: isEstimated
        ) {
            return "[\(label)](\(deepURL.absoluteString))"
        }
        return "[\(label)]"
    }

    /// 生成 YAML Frontmatter 行（支持合并保留用户在 Obsidian 中自定义的标签与额外属性）
    public static func renderFrontmatterLines(
        recording: Recording,
        note: Note,
        revision: NoteRevision,
        segments: [TranscriptSegment] = [],
        preservedUserTags: [String] = [],
        preservedCustomKeyBlocks: [[String]] = [],
        fallbackProjectRawValue: String? = nil
    ) -> [String] {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = recording.recordedTimeZone
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let dateStr = dateFormatter.string(from: recording.createdAt)
        let isoRecordedAt = formatISOTimestamp(recording.createdAt, timeZone: recording.recordedTimeZone)
        let durationStr = TimeFormatting.formatDuration(recording.duration)
        let modeTag = (revision.mode == .quickNote) ? "随手记" : "会议"
        let title = exportTitle(recording: recording, revision: revision)
        let provenance = NoteVersionProvenance.evaluate(recording: recording, revision: revision, segments: segments)

        var mergedTags: [String] = ["录音笔记", modeTag]
        for tag in note.manualTags + preservedUserTags {
            let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            if !cleaned.isEmpty && !systemManagedTags.contains(cleaned) && !mergedTags.contains(cleaned) {
                mergedTags.append(cleaned)
            }
        }

        var lines: [String] = []
        lines.append("---")
        lines.append("title: \(escapeYAML(title))")
        lines.append("recording_id: \(escapeYAML(recording.id.uuidString))")
        lines.append("recorded_at: \(escapeYAML(isoRecordedAt))")
        lines.append("date: \(escapeYAML(dateStr))")
        lines.append("timezone: \(escapeYAML(recording.recordedTimeZoneIdentifier))")
        lines.append("source: MemoFlow")
        lines.append("mode: \(modeTag)")
        lines.append("duration: \(escapeYAML(durationStr))")
        lines.append("duration_seconds: \(Int(recording.duration.rounded()))")
        lines.append("processing_status: \(escapeYAML(recording.processingStatus.rawValue))")
        lines.append("transcript_review_status: \(escapeYAML(provenance.transcriptReviewStatusCode))")
        lines.append("summary_alignment_status: \(escapeYAML(provenance.summaryAlignmentCode))")
        lines.append("note_revision_id: \(escapeYAML(revision.id.uuidString))")
        lines.append("note_origin: \(escapeYAML(revision.origin.rawValue))")
        if let projLink = formatProjectWikiLink(note.projectName) {
            lines.append("project: \(escapeYAML(projLink))")
        } else if let fallback = fallbackProjectRawValue, !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("project: \(fallback)")
        }
        let formattedTags = mergedTags.map { tag in
            tag.contains(" ") || tag.contains(":") ? escapeYAML(tag) : tag
        }.joined(separator: ", ")
        lines.append("tags: [\(formattedTags)]")

        for customBlock in preservedCustomKeyBlocks where !customBlock.isEmpty {
            lines.append(contentsOf: customBlock)
        }
        lines.append("---")
        return lines
    }

    /// 分区块生成 MemoFlow 受控区域文本（不含外层 start/end 注释标记）
    public static func renderManagedBlocks(
        recording: Recording,
        note: Note,
        revision: NoteRevision,
        confirmedActions: [ConfirmedAction],
        segments: [TranscriptSegment],
        pendingDrafts: [ActionDraft] = []
    ) -> [ObsidianManagedBlockKind: String] {
        var blocks: [ObsidianManagedBlockKind: String] = [:]
        let title = exportTitle(recording: recording, revision: revision)
        let content = revision.content
        let provenance = NoteVersionProvenance.evaluate(recording: recording, revision: revision, segments: segments)
        let isoRecordedAt = formatISOTimestamp(recording.createdAt, timeZone: recording.recordedTimeZone)

        // 1. Header 区块（完整导出录音 ID、时间与时区、时长、关联项目双链、逐字稿审核状态与版本对齐说明）
        var headerLines: [String] = ["# \(title)", ""]
        var metaParts: [String] = [
            "录音 ID：`\(recording.id.uuidString)`",
            "时间：\(isoRecordedAt)（\(recording.recordedTimeZoneIdentifier)）",
            "时长：\(TimeFormatting.formatDuration(recording.duration))",
            "逐字稿：\(provenance.transcriptReviewDisplayTitle)"
        ]
        if let projLink = formatProjectWikiLink(note.projectName) {
            metaParts.insert("关联项目：\(projLink)", at: 1)
        }
        if !recording.localAudioFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let openRecURL = MemoFlowDeepLink.recordingURL(recordingId: recording.id) {
            metaParts.append("[在 MemoFlow 打开录音](\(openRecURL.absoluteString))")
        }
        headerLines.append("> " + metaParts.joined(separator: " · "))

        if provenance.isSummaryBasedOnOlderTranscript {
            headerLines.append("")
            headerLines.append("> [!WARNING] 摘要与逐字稿版本未对齐：\(provenance.summaryAlignmentDisplayTitle)。当前逐字稿审核状态为「\(provenance.transcriptReviewDisplayTitle)」，请先回听校对并重新整理，勿直接将旧版摘要当作最终结论。")
        } else if recording.isTranscriptReviewed != true {
            headerLines.append("")
            headerLines.append("> [!NOTE] 审核状态说明：当前逐字稿为「\(provenance.transcriptReviewDisplayTitle)」，摘要状态为「\(provenance.summaryAlignmentDisplayTitle)」。")
        } else {
            headerLines.append("")
            headerLines.append("> [!TIP] 已审核确认：本篇逐字稿已完成人工校对，摘要版本与当前逐字稿一致。")
        }
        blocks[.header] = headerLines.joined(separator: "\n")

        // 2. Summary 区块（严格区分：本次录音内容 / 历史笔记关联背景 / AI 推断建议）
        var summaryLines: [String] = []
        if revision.mode == .quickNote {
            if !content.summaryOrShortNote.isEmpty {
                summaryLines.append("## 核心总结（本次录音）")
                summaryLines.append(content.summaryOrShortNote)
                summaryLines.append("")
            }
        } else {
            if !content.summaryOrShortNote.isEmpty {
                summaryLines.append("## 一句话摘要（本次录音）")
                summaryLines.append(content.summaryOrShortNote)
                summaryLines.append("")
            }
            if !content.backgroundPoints.isEmpty {
                summaryLines.append("## 必要背景（本次录音）")
                for item in content.backgroundPoints {
                    summaryLines.append("- \(item)")
                }
                summaryLines.append("")
            }
            if !content.keyPoints.isEmpty {
                summaryLines.append("## 关键观点")
                for item in content.keyPoints {
                    summaryLines.append("- \(item)")
                }
                summaryLines.append("")
            }
            if !content.decisions.isEmpty {
                summaryLines.append("## 已确认结论")
                for item in content.decisions {
                    summaryLines.append("- \(item)")
                }
                summaryLines.append("")
            }
        }

        if !content.historicalContextNotes.isEmpty || !content.knowledgeReferences.isEmpty {
            summaryLines.append("## 历史笔记关联背景（非本次录音新承诺）")
            summaryLines.append("> 以下内容来自 Obsidian 历史笔记检索，仅作术语与项目背景参考，不自动生成本次待办或承诺。")
            for hist in content.historicalContextNotes {
                summaryLines.append("- [历史笔记背景] \(hist)")
            }
            for reference in content.knowledgeReferences {
                let wikiTarget = reference.path.lowercased().hasSuffix(".md")
                    ? String(reference.path.dropLast(3))
                    : reference.path
                if let recId = reference.recordingId,
                   let ts = reference.timestampMs,
                   let jumpURL = MemoFlowDeepLink.recordingURL(recordingId: recId, startMs: ts) {
                    summaryLines.append("- 来源笔记：[[\(wikiTarget)]] · 关联录音：[\(TimeFormatting.formatMilliseconds(ts))](\(jumpURL.absoluteString))")
                } else {
                    summaryLines.append("- 来源笔记：[[\(wikiTarget)]]")
                }
            }
            summaryLines.append("")
        }

        if !content.aiInferences.isEmpty {
            summaryLines.append("## AI 延伸推测与建议（非录音原话事实）")
            for inf in content.aiInferences {
                summaryLines.append("- [AI 推测] \(inf)")
            }
            summaryLines.append("")
        }

        blocks[.summary] = summaryLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        // 3. Actions 区块
        let visibleConfirmed = confirmedActions.filter { $0.executionStatus != .ignored }
        let confirmedDraftIds = Set(visibleConfirmed.map(\.sourceDraftId))
        let unconfirmedActiveDrafts = pendingDrafts.filter {
            ($0.reviewStatus == .pending || $0.reviewStatus == .needsInfo) && !confirmedDraftIds.contains($0.id)
        }
        if !visibleConfirmed.isEmpty || !unconfirmedActiveDrafts.isEmpty {
            var actionLines: [String] = ["## 行动记录"]
            for action in visibleConfirmed {
                actionLines.append(formatActionLine(action, recording: recording, segments: segments))
            }
            for draft in unconfirmedActiveDrafts {
                actionLines.append(formatPendingDraftLine(draft, recording: recording, segments: segments))
            }
            blocks[.actions] = actionLines.joined(separator: "\n")
        } else {
            blocks[.actions] = ""
        }

        // 4. Marks 区块（手动高亮、批注与录制书签，带可点击深链与稳定标记 ID）
        let marks = recording.marks ?? []
        if !marks.isEmpty {
            var markLines: [String] = ["## 书签与高亮批注"]
            for mark in marks {
                let kindLabel: String
                switch mark.kind {
                case "highlight": kindLabel = "高亮"
                case "note": kindLabel = "批注"
                default: kindLabel = "书签"
                }
                let isEst = segments.first(where: { $0.startMs == mark.startMs })?.timingIsEstimated == true
                let linkPart = formatVerifiableTimestampLink(
                    recording: recording,
                    startMs: mark.startMs,
                    endMs: mark.endMs,
                    isEstimated: isEst,
                    rangeDisplay: (mark.endMs ?? 0) > mark.startMs,
                    kindPrefix: kindLabel
                )
                let quotePart = mark.quote.isEmpty ? "" : " \(mark.quote)"
                let endMeta = mark.endMs.map { ";end_ms=\($0)" } ?? ""
                let metaComment = " <!-- memoflow:mark_id=\(mark.id.uuidString);kind=\(mark.kind);start_ms=\(mark.startMs)\(endMeta) -->"
                markLines.append("- \(linkPart)\(quotePart)\(metaComment)")
                if !mark.note.isEmpty {
                    markLines.append("  - 批注：\(mark.note)")
                }
            }
            blocks[.marks] = markLines.joined(separator: "\n")
        } else {
            blocks[.marks] = ""
        }

        // 5. Chapters 区块（带可点击时间戳区间深链）
        let resolvedChapters: [NoteChapter] = {
            if !content.chapters.isEmpty {
                return content.chapters
            }
            return ASRAndLLMService.shared.buildChaptersFromSegments(segments)
        }()
        if !resolvedChapters.isEmpty {
            var chapterLines: [String] = ["## 录音章节"]
            for (index, chapter) in resolvedChapters.enumerated() {
                let numStr = String(format: "%02d", index + 1)
                let overlappingSegs = segments.filter { $0.startMs < chapter.endMs && $0.endMs > chapter.startMs }
                let chapterIsEstimated = !overlappingSegs.isEmpty && overlappingSegs.allSatisfy { $0.timingIsEstimated == true }
                let chapterLink = formatVerifiableTimestampLink(
                    recording: recording,
                    startMs: chapter.startMs,
                    endMs: chapter.endMs,
                    isEstimated: chapterIsEstimated,
                    rangeDisplay: true
                )
                chapterLines.append("### \(numStr). \(chapterLink) \(chapter.title)")
                chapterLines.append(chapter.summary)
                if index < resolvedChapters.count - 1 {
                    chapterLines.append("")
                }
            }
            blocks[.chapters] = chapterLines.joined(separator: "\n")
        } else {
            blocks[.chapters] = ""
        }

        // 6. Transcript 区块（逐句可点击定位回听，估算时间标「约」，不可核验不伪造链接）
        if !segments.isEmpty {
            var transcriptLines: [String] = ["## 逐字稿"]
            for seg in segments {
                let speakerPrefix = (seg.speakerName?.isEmpty == false) ? "**\(seg.speakerName!)**: " : ""
                let segLink = formatVerifiableTimestampLink(
                    recording: recording,
                    startMs: seg.startMs,
                    endMs: seg.endMs,
                    isEstimated: seg.timingIsEstimated == true,
                    rangeDisplay: false
                )
                transcriptLines.append("- \(segLink) \(speakerPrefix)\(seg.text)")
            }
            blocks[.transcript] = transcriptLines.joined(separator: "\n")
        } else {
            blocks[.transcript] = ""
        }

        return blocks
    }

    public static func generateMarkdown(
        recording: Recording,
        note: Note,
        revision: NoteRevision,
        confirmedActions: [ConfirmedAction],
        segments: [TranscriptSegment],
        pendingDrafts: [ActionDraft] = []
    ) -> String {
        let frontmatter = renderFrontmatterLines(
            recording: recording,
            note: note,
            revision: revision,
            segments: segments
        )
        let blocks = renderManagedBlocks(
            recording: recording,
            note: note,
            revision: revision,
            confirmedActions: confirmedActions,
            segments: segments,
            pendingDrafts: pendingDrafts
        )

        var lines: [String] = frontmatter
        lines.append(recordingAnchorComment(for: recording.id))
        lines.append("")

        func appendManaged(_ kind: ObsidianManagedBlockKind) {
            let inner = blocks[kind] ?? ""
            lines.append(managedBlockStartMarker(kind))
            if !inner.isEmpty {
                lines.append(inner)
            }
            lines.append(managedBlockEndMarker(kind))
            lines.append("")
        }

        appendManaged(.header)

        // 用户手写补充专区（始终受保护，重新整理绝不覆盖）
        lines.append("## 个人补充")
        lines.append(userSupplementStartMarker)
        let trimmedSupplement = note.userSupplement.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSupplement.isEmpty {
            lines.append(trimmedSupplement)
        }
        lines.append(userSupplementEndMarker)
        lines.append("")

        appendManaged(.summary)
        appendManaged(.actions)
        appendManaged(.marks)
        appendManaged(.chapters)
        appendManaged(.transcript)

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
        let fallbackRec = Recording(
            id: action.recordingId,
            title: "",
            recordedTimeZoneIdentifier: recordingTimeZone.identifier,
            duration: Double((snap.evidenceEndMs ?? snap.evidenceStartMs ?? 0) + 10_000) / 1000.0,
            localAudioFileName: snap.evidenceStartMs != nil ? "linked.m4a" : ""
        )
        return formatActionLine(action, recording: fallbackRec, segments: [])
    }

    public static func formatActionLine(
        _ action: ConfirmedAction,
        recording: Recording,
        segments: [TranscriptSegment]
    ) -> String {
        let snap = action.confirmedSnapshot
        let ownerText = (snap.owner?.isEmpty == false) ? snap.owner! : "未明确"
        let sourceTimeText: String
        if let startMs = snap.evidenceStartMs {
            let isEst = segments.first(where: { $0.startMs == startMs })?.timingIsEstimated == true
            sourceTimeText = formatVerifiableTimestampLink(
                recording: recording,
                startMs: startMs,
                endMs: snap.evidenceEndMs,
                isEstimated: isEst,
                rangeDisplay: false
            )
        } else if snap.evidenceQuote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sourceTimeText = "手动添加"
        } else {
            sourceTimeText = "[来源待核验]"
        }

        let dateSummary = formatActionDateSummary(snapshot: snap, timeZone: recording.recordedTimeZone)

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
        let fallbackRec = Recording(
            id: draft.recordingId,
            title: "",
            recordedTimeZoneIdentifier: recordingTimeZone.identifier,
            duration: Double((draft.evidenceEndMs ?? draft.evidenceStartMs ?? 0) + 10_000) / 1000.0,
            localAudioFileName: draft.evidenceStartMs != nil ? "linked.m4a" : ""
        )
        return formatPendingDraftLine(draft, recording: fallbackRec, segments: [])
    }

    public static func formatPendingDraftLine(
        _ draft: ActionDraft,
        recording: Recording,
        segments: [TranscriptSegment]
    ) -> String {
        let snap = ActionSnapshot(from: draft)
        let ownerText = (draft.owner?.isEmpty == false) ? draft.owner! : "未明确"
        let sourceTimeText: String
        if let startMs = draft.evidenceStartMs {
            let isEst = segments.first(where: { draft.sourceSegmentIds.contains($0.id) || $0.startMs == startMs })?.timingIsEstimated == true
            sourceTimeText = formatVerifiableTimestampLink(
                recording: recording,
                startMs: startMs,
                endMs: draft.evidenceEndMs,
                isEstimated: isEst,
                rangeDisplay: false
            )
        } else {
            sourceTimeText = "[来源待核验]"
        }
        let dateSummary = formatActionDateSummary(snapshot: snap, timeZone: recording.recordedTimeZone)

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

    /// 底层协调写入接口（针对无 recording_id 的纯文本写入保持同名防覆盖保护；带 recording_id 的单篇持久同步请走 ObsidianNoteSyncService）
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

        let fileName = preferredFileName(recording: recording, title: title ?? recording.title)
        let fileURL = uniqueFileURL(
            preferredURL: targetDirURL.appendingPathComponent(fileName),
            fileManager: .default
        )

        try markdownContent.write(to: fileURL, atomically: true, encoding: .utf8)

        let relPath = cleanSub.isEmpty ? fileURL.lastPathComponent : "\(cleanSub)/\(fileURL.lastPathComponent)"
        return (fileURL, obsidianOpenURL(vaultRootURL: rootURL, relativePath: relPath))
    }

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

    public static func escapeYAML(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
