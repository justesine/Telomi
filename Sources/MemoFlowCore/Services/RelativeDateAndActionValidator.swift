import Foundation

/// 负责将 AI 提取的原始候选（或本地规则解析结果）按 PRD 4.4 / 4.5 / 4.6 / 6.2 规范进行校验、时间锚定与证据对齐
public enum RelativeDateAndActionValidator {

    /// 根据录音发生时刻（recordingCreatedAt）和录音时区（recordingTimeZone）校准并校验 ActionDraft
    public static func validateAndNormalize(
        draft: ActionDraft,
        segments: [TranscriptSegment],
        recordingCreatedAt: Date,
        recordingTimeZone: TimeZone,
        preferences: MemoFlowPreferences
    ) -> ActionDraft {
        var result = draft
        result.timeZoneIdentifier = recordingTimeZone.identifier

        // 1. 证据区间查表对齐（PRD 4.4 & R23：不让大模型瞎猜毫秒数，根据 sourceSegmentIds 从真实分段查表）
        let matchedSegments = segments.filter { result.sourceSegmentIds.contains($0.id) }
        if !matchedSegments.isEmpty {
            result.evidenceStartMs = matchedSegments.map(\.startMs).min()
            result.evidenceEndMs = matchedSegments.map(\.endMs).max()
            if result.evidenceQuote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.evidenceQuote = matchedSegments.map(\.text).joined(separator: " ")
            }
        } else if !result.isManualCreation {
            // 若无匹配的来源段落，清空不可信的时间戳并要求人工核实（PRD A22）
            result.evidenceStartMs = nil
            result.evidenceEndMs = nil
            result.needsConfirmation = true
            appendReason("缺少有效原话时间定位，须人工核实后才能执行", to: &result.confirmationReasons)
        }

        // 2. 结合录音发生时刻与时区解析相对日期表达（PRD 4.5 & A12 & A32）
        if let rawDateText = result.originalDateText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawDateText.isEmpty {
            let parsed = parseChineseRelativeDate(
                text: rawDateText,
                anchorDate: recordingCreatedAt,
                timeZone: recordingTimeZone
            )

            switch parsed {
            case .ambiguous(let reason):
                result.datePrecision = .ambiguous
                result.startAt = nil
                result.endAt = nil
                result.dueDate = nil
                result.needsConfirmation = true
                result.reviewStatus = .needsInfo
                appendReason(reason, to: &result.confirmationReasons)

            case .dateOnly(let resolvedDate):
                result.datePrecision = .dateOnly
                result.dueDate = resolvedDate
                result.startAt = nil
                result.endAt = nil
                // PRD 4.6 & A14：只有日期/截止日期的任务，不默认转为全天日历事件
                if result.kind == .event {
                    result.kind = .task
                }
                if result.proposedDestination == .calendar {
                    result.proposedDestination = preferences.defaultTaskDestination
                }

            case .exactTimeRange(let start, let end):
                result.datePrecision = .exactTime
                result.startAt = start
                if let end {
                    result.endAt = end
                    result.isDefaultDurationApplied = false
                    result.appliedDefaultDurationMinutes = nil
                } else {
                    // PRD 4.6：只有开始时间、没有结束时间 -> 应用默认时长并明确标记为默认值
                    let defaultMinutes = max(5, preferences.defaultEventDurationMinutes)
                    result.endAt = start.addingTimeInterval(TimeInterval(defaultMinutes * 60))
                    result.isDefaultDurationApplied = true
                    result.appliedDefaultDurationMinutes = defaultMinutes
                    appendReason("未提及结束时间，已按默认时长（\(defaultMinutes) 分钟）补齐，请核对", to: &result.confirmationReasons)
                }

            case .unrecognized:
                // 保持模型已解析出的 ISO 时间（若有），但检查合法性
                break
            }
        }

        // 3. 若模型直接给出了 startAt 但没有 endAt（且未走相对日期分支），同样补齐默认时长（PRD 4.6）
        if result.kind == .event,
           let start = result.startAt,
           result.endAt == nil {
            let defaultMinutes = max(5, preferences.defaultEventDurationMinutes)
            result.endAt = start.addingTimeInterval(TimeInterval(defaultMinutes * 60))
            result.isDefaultDurationApplied = true
            result.appliedDefaultDurationMinutes = defaultMinutes
            appendReason("未提及结束时间，已按默认时长（\(defaultMinutes) 分钟）补齐，请核对", to: &result.confirmationReasons)
        }

        // 4. 类别与去向边界护栏（PRD 4.6）
        if result.kind == .task {
            // 截止日期任务禁止默认写成日历事件
            if result.proposedDestination == .calendar {
                result.proposedDestination = preferences.defaultTaskDestination
            }
            if result.datePrecision == .ambiguous {
                result.needsConfirmation = true
                result.reviewStatus = .needsInfo
                appendReason("时间表达模糊，需补充具体时间或确认作为无日期任务", to: &result.confirmationReasons)
            }
        } else if result.kind == .event {
            if result.datePrecision != .exactTime || result.startAt == nil {
                result.needsConfirmation = true
                result.reviewStatus = .needsInfo
                appendReason("日程缺少明确开始时间，补充时间前不可写入日历", to: &result.confirmationReasons)
            } else {
                result.proposedDestination = .calendar
            }
        }

        // 5. 结合说话人识别结果校验待办归属（PRD V1.2 CAL-004）
        if let primarySpeaker = matchedSegments.first?.speakerName, !primarySpeaker.isEmpty {
            if primarySpeaker == "我" {
                if result.ownership != .other {
                    result.ownership = .selfOwner
                    result.owner = "我"
                }
            } else if result.ownership == .uncertain {
                result.ownership = .other
                result.owner = primarySpeaker
                result.needsConfirmation = true
                appendReason("由参会人「\(primarySpeaker)」提及或负责，需核对是否转为本人待办", to: &result.confirmationReasons)
            }
        }

        // 6. 归属人边界（PRD 4.6 & A06 & A26）
        switch result.ownership {
        case .other:
            // 他人负责事项仅作为上下文保留，不默认创建为用户自己的外部任务
            result.proposedDestination = .local
            result.needsConfirmation = true
            appendReason("由他人（\(result.owner ?? "其他参会人")）负责，仅保留为上下文；如需跟进请手动转为本人任务", to: &result.confirmationReasons)
        case .uncertain:
            if (result.owner ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.owner = "未明确"
            }
            result.needsConfirmation = true
            appendReason("负责人未明确，请核对是否由本人跟进", to: &result.confirmationReasons)
        case .selfOwner:
            break
        }

        if !result.hasValidEvidence {
            result.reviewStatus = .needsInfo
        }

        return result
    }

    // MARK: - Relative Date Parser (Anchored to Recording CreatedAt & TimeZone)

    public enum RelativeDateParseResult: Equatable, Sendable {
        case exactTimeRange(start: Date, end: Date?)
        case dateOnly(Date)
        case ambiguous(reason: String)
        case unrecognized
    }

    /// 解析中文口语相对时间（基于录音当时的日期与时区，PRD 4.5 & A12 & A13 & A14 & A32）
    public static func parseChineseRelativeDate(
        text: String,
        anchorDate: Date,
        timeZone: TimeZone
    ) -> RelativeDateParseResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2 // 周一作为一周起点

        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. 识别典型模糊时间表达（PRD 4.6 & A13：「下周找时间聊」「改天沟通」「待定」）
        let ambiguousKeywords = ["找时间", "看情况", "改天", "抽空", "待定", "回头聊", "再约"]
        if ambiguousKeywords.contains(where: { normalized.contains($0) }) {
            return .ambiguous(reason: "原话时间表达模糊（「\(normalized)」），需补充明确时间")
        }
        if normalized == "下周" || normalized == "这周" || normalized == "本周" || normalized == "近期" {
            return .ambiguous(reason: "原话仅提及「\(normalized)」，未指定具体日期或时刻")
        }

        // 2. 计算相对于 anchorDate 的基准天偏移
        var targetDayDate: Date?
        let startOfAnchorDay = calendar.startOfDay(for: anchorDate)

        if normalized.contains("大后天") {
            targetDayDate = calendar.date(byAdding: .day, value: 3, to: startOfAnchorDay)
        } else if normalized.contains("后天") {
            targetDayDate = calendar.date(byAdding: .day, value: 2, to: startOfAnchorDay)
        } else if normalized.contains("明天") || normalized.contains("明日") {
            targetDayDate = calendar.date(byAdding: .day, value: 1, to: startOfAnchorDay)
        } else if normalized.contains("今天") || normalized.contains("今日") || normalized.contains("今晚") {
            targetDayDate = startOfAnchorDay
        } else if let weekdayTarget = extractWeekdayOffset(from: normalized, calendar: calendar, anchorDay: startOfAnchorDay) {
            targetDayDate = weekdayTarget
        }

        guard let baseDay = targetDayDate else {
            return .unrecognized
        }

        // 3. 提取具体时刻（如「15:00 到 16:00」「下午 3 点」「15:00」）
        let timeMatches = extractClockTimes(from: normalized)
        if let firstTime = timeMatches.first {
            var startComponents = calendar.dateComponents([.year, .month, .day], from: baseDay)
            startComponents.hour = firstTime.hour
            startComponents.minute = firstTime.minute
            startComponents.second = 0

            guard let startDate = calendar.date(from: startComponents) else {
                return .dateOnly(baseDay)
            }

            var endDate: Date?
            if timeMatches.count >= 2 {
                let secondTime = timeMatches[1]
                var endComponents = calendar.dateComponents([.year, .month, .day], from: baseDay)
                endComponents.hour = secondTime.hour
                endComponents.minute = secondTime.minute
                endComponents.second = 0
                if let candidateEnd = calendar.date(from: endComponents), candidateEnd > startDate {
                    endDate = candidateEnd
                }
            }
            return .exactTimeRange(start: startDate, end: endDate)
        }

        // 4. 只有日期、没有具体时刻（如「周五前」「本周五之前」）
        return .dateOnly(baseDay)
    }

    // MARK: - Helpers

    private static func appendReason(_ reason: String, to reasons: inout [String]) {
        if !reasons.contains(reason) {
            reasons.append(reason)
        }
    }

    private static func extractWeekdayOffset(
        from text: String,
        calendar: Calendar,
        anchorDay: Date
    ) -> Date? {
        let weekdayMap: [(tokens: [String], isoDay: Int)] = [
            (["周一", "星期一", "礼拜一"], 1),
            (["周二", "星期二", "礼拜二"], 2),
            (["周三", "星期三", "礼拜三"], 3),
            (["周四", "星期四", "礼拜四"], 4),
            (["周五", "星期五", "礼拜五"], 5),
            (["周六", "星期六", "礼拜六"], 6),
            (["周日", "周天", "星期日", "星期天", "礼拜天"], 7)
        ]

        guard let matched = weekdayMap.first(where: { entry in
            entry.tokens.contains(where: { text.contains($0) })
        }) else {
            return nil
        }

        // Apple Calendar weekday: Sunday = 1, Monday = 2 ... Saturday = 7
        let appleWeekday = calendar.component(.weekday, from: anchorDay)
        let currentIsoDay = (appleWeekday == 1) ? 7 : (appleWeekday - 1)
        let isNextWeek = text.contains("下周") || text.contains("下星期") || text.contains("下礼拜")

        var deltaDays = matched.isoDay - currentIsoDay
        if isNextWeek {
            deltaDays += 7
        } else if deltaDays < 0 {
            // 口语中在同一周内说某个周几，若已过去则顺延到下一个该周几
            deltaDays += 7
        }

        return calendar.date(byAdding: .day, value: deltaDays, to: anchorDay)
    }

    private struct ClockTime {
        let hour: Int
        let minute: Int
    }

    private static func extractClockTimes(from text: String) -> [ClockTime] {
        var results: [ClockTime] = []
        let isPMContext = text.contains("下午") || text.contains("晚上") || text.contains("今晚") || text.contains("傍晚")

        // 匹配 HH:mm 格式（例如 15:00、9:30）
        if let colonRegex = try? NSRegularExpression(pattern: #"(\d{1,2})[:：](\d{2})"#) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = colonRegex.matches(in: text, range: nsRange)
            for match in matches {
                if let hRange = Range(match.range(at: 1), in: text),
                   let mRange = Range(match.range(at: 2), in: text),
                   var hour = Int(text[hRange]),
                   let minute = Int(text[mRange]) {
                    if isPMContext && hour < 12 {
                        hour += 12
                    }
                    results.append(ClockTime(hour: min(23, hour), minute: min(59, minute)))
                }
            }
        }

        if !results.isEmpty {
            return results
        }

        // 匹配「3点半」「下午3点」「15点」格式
        let chineseNumberMap: [String: Int] = [
            "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5,
            "六": 6, "七": 7, "八": 8, "九": 9, "十": 10, "十一": 11, "十二": 12
        ]
        if let pointRegex = try? NSRegularExpression(pattern: #"(上午|中午|下午|晚上|今晚)?\s*(\d{1,2}|十一|十二|十|[一二两三四五六七八九])\s*点(半|(\d{1,2})分?)?"#) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = pointRegex.matches(in: text, range: nsRange)
            for match in matches {
                let periodText = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? ""
                guard let hourRange = Range(match.range(at: 2), in: text) else { continue }
                let rawHourStr = String(text[hourRange])
                guard var hour = Int(rawHourStr) ?? chineseNumberMap[rawHourStr] else { continue }

                let localPM = isPMContext || periodText == "下午" || periodText == "晚上" || periodText == "今晚" || (periodText == "中午" && hour < 11)
                if localPM && hour < 12 {
                    hour += 12
                }

                var minute = 0
                if let suffixRange = Range(match.range(at: 3), in: text) {
                    let suffix = String(text[suffixRange])
                    if suffix == "半" {
                        minute = 30
                    } else if let minRange = Range(match.range(at: 4), in: text),
                              let m = Int(text[minRange]) {
                        minute = m
                    }
                }
                results.append(ClockTime(hour: min(23, hour), minute: min(59, minute)))
            }
        }

        return results
    }
}
