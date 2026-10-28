import Foundation
@testable import MemoFlowCore

@main
struct PRDTestRunner {
    private static func assert(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #file, line: Int = #line) {
        if !condition() {
            fputs("❌ FAILED: \(message) (\(file):\(line))\n", stderr)
            exit(1)
        }
    }

    @MainActor
    static func main() async {
        do { try await testKnowledgeIntegration() }
        catch { fputs("知识库测试失败：\(error)\n", stderr); exit(1) }
        print("▶ 开始执行 MemoFlow PRD v1.1 核心验收测试 (A01 - A32)...")

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoFlowTest_\(UUID().uuidString).json")
        let store = MemoFlowStore(customStorageURL: tempURL)

        // 1. A01 & A27：无网络录制并结束 -> 本地存在可播放音频，状态为「已安全保存·待转写」
        let recId = UUID()
        let fileName = "offline_test.wav"
        _ = store.audioService.ensurePlayableDemoAudioFile(named: fileName, durationSeconds: 10)
        store.handleFinishedRecording(
            id: recId,
            fileName: fileName,
            createdAt: Date(),
            duration: 10,
            selectedMode: .quickNote,
            isNetworkAvailable: false
        )
        let savedOffline = store.recordings.first(where: { $0.id == recId })
        assert(savedOffline?.processingStatus == .savedPendingTranscription, "A01: 离线录音状态应为待转写")
        assert(FileManager.default.fileExists(atPath: store.audioService.audioFileURL(for: fileName).path), "A01: 离线音频文件必须落盘")
        print("  ✓ [A01 / A27] 无网安全保存与离开处理页保护通过")

        // 2. A12 & A32 & 4.6：相对日期必须锚定「录音发生日期与录音时区」，无结束时间补齐默认 30 分钟并标记
        let tz = TimeZone(identifier: "Asia/Shanghai")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let recordingDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 10, minute: 0))!
        let seg = TranscriptSegment(id: "seg_01", recordingId: UUID(), startMs: 5000, endMs: 12000, text: "明天 15:00 到 16:00 开分镜评审会")
        let prefs = MemoFlowPreferences(defaultEventDurationMinutes: 30)

        let exactDraft = RelativeDateAndActionValidator.validateAndNormalize(
            draft: ActionDraft(
                recordingId: seg.recordingId,
                revisionId: UUID(),
                kind: .event,
                description: "开分镜评审会",
                ownership: .selfOwner,
                originalDateText: "明天 15:00 到 16:00",
                sourceSegmentIds: ["seg_01"],
                evidenceQuote: seg.text,
                proposedDestination: .calendar
            ),
            segments: [seg],
            recordingCreatedAt: recordingDate,
            recordingTimeZone: tz,
            preferences: prefs
        )
        let startComps = cal.dateComponents([.year, .month, .day, .hour], from: exactDraft.startAt!)
        assert(startComps.day == 20 && startComps.hour == 15, "A12 / A32: 相对日期必须锚定录音当天而非转写当天")
        assert(exactDraft.evidenceStartMs == 5000 && exactDraft.evidenceEndMs == 12000, "R23 / A22: 行动证据毫秒区间必须由分段 ID 精确查表对齐")

        let startOnlyDraft = RelativeDateAndActionValidator.validateAndNormalize(
            draft: ActionDraft(
                recordingId: seg.recordingId,
                revisionId: UUID(),
                kind: .event,
                description: "沟通脚本",
                ownership: .selfOwner,
                originalDateText: "明天下午 3 点",
                sourceSegmentIds: ["seg_01"],
                evidenceQuote: "明天下午 3 点沟通脚本",
                proposedDestination: .calendar
            ),
            segments: [seg],
            recordingCreatedAt: recordingDate,
            recordingTimeZone: tz,
            preferences: prefs
        )
        assert(startOnlyDraft.isDefaultDurationApplied && startOnlyDraft.appliedDefaultDurationMinutes == 30, "4.6: 仅开始时间事件必须标注默认时长")
        print("  ✓ [A12 / A22 / A32 / 4.6] 录音时间锚定、证据区间对齐与默认时长标注通过")

        // 3. A13 / A14 / A26 / A31：模糊时间、截止日期任务、他人负责任务的边界护栏与批量执行过滤
        let ambiguousDraft = RelativeDateAndActionValidator.validateAndNormalize(
            draft: ActionDraft(
                recordingId: seg.recordingId,
                revisionId: UUID(),
                kind: .event,
                description: "沟通方案",
                ownership: .selfOwner,
                originalDateText: "下周找时间沟通",
                sourceSegmentIds: ["seg_01"],
                evidenceQuote: "下周找时间沟通",
                proposedDestination: .calendar
            ),
            segments: [seg],
            recordingCreatedAt: recordingDate,
            recordingTimeZone: tz,
            preferences: prefs
        )
        assert(ambiguousDraft.datePrecision == .ambiguous && !ambiguousDraft.isEligibleForBatchExecution, "A13 / A31: 时间模糊事项禁止静默写入日历或混入批量执行")

        let deadlineDraft = RelativeDateAndActionValidator.validateAndNormalize(
            draft: ActionDraft(
                recordingId: seg.recordingId,
                revisionId: UUID(),
                kind: .event,
                description: "交报告",
                ownership: .selfOwner,
                originalDateText: "周五前",
                sourceSegmentIds: ["seg_01"],
                evidenceQuote: "周五前交报告",
                proposedDestination: .calendar
            ),
            segments: [seg],
            recordingCreatedAt: recordingDate,
            recordingTimeZone: tz,
            preferences: prefs
        )
        assert(deadlineDraft.kind == .task && deadlineDraft.datePrecision == .dateOnly && deadlineDraft.proposedDestination != .calendar, "A14: 截止日期任务不默认变成全天日历事件")

        let otherOwnerDraft = RelativeDateAndActionValidator.validateAndNormalize(
            draft: ActionDraft(
                recordingId: seg.recordingId,
                revisionId: UUID(),
                kind: .task,
                description: "交初稿",
                owner: "小王",
                ownership: .other,
                originalDateText: "周五",
                sourceSegmentIds: ["seg_01"],
                evidenceQuote: "小王周五交初稿",
                proposedDestination: .reminders
            ),
            segments: [seg],
            recordingCreatedAt: recordingDate,
            recordingTimeZone: tz,
            preferences: prefs
        )
        assert(otherOwnerDraft.ownership == .other && otherOwnerDraft.proposedDestination == .local && !otherOwnerDraft.isEligibleForBatchExecution, "A26: 他人负责事项仅保留为上下文")
        print("  ✓ [A13 / A14 / A26 / A31] 模糊时间、截止日期精度、他人任务隔离与批量执行安全过滤通过")

        // 4. A09 / A20 / A23 / A30：随手记不扩写空章节；单一主要管理位置与 Markdown 导出 checkbox 规则
        store.seedPRDDefaultScenarios()
        let recA = store.recordings.last!
        let noteA = store.notesByRecording[recA.id]!
        let revA = store.currentRevision(for: recA.id)!
        let mdA = MarkdownExporterService.generateMarkdown(
            recording: recA,
            note: noteA,
            revision: revA,
            confirmedActions: [],
            segments: store.segmentsByRecording[recA.id] ?? []
        )
        assert(!mdA.contains("## 关键观点") && !mdA.contains("## 已确认结论"), "A20: 随手记不凑空的观点与结论章节")

        let recB = store.recordings.first!
        let noteB = store.notesByRecording[recB.id]!
        let revB = store.currentRevision(for: recB.id)!
        let draftsB = store.actionDraftsByRecording[recB.id]!

        let confirmedMarkdown = await store.confirmAndExecuteDraft(draftsB[1], chosenDestination: .markdown)
        assert(confirmedMarkdown.localCompletion == nil && !confirmedMarkdown.allowsLocalCompletionToggle, "R25 / A30: Markdown 主要位置不在 App 内维护第二份完成状态")

        let reminderConfirmed = ConfirmedAction(
            recordingId: recB.id,
            sourceDraftId: UUID(),
            confirmedSnapshot: ActionSnapshot(from: draftsB[1]),
            primaryDestination: .reminders,
            localCompletion: true,
            executionStatus: .handedToExternal
        )
        assert(reminderConfirmed.localCompletion == nil && !reminderConfirmed.allowsLocalCompletionToggle, "R25 / A23: 提醒事项任务不显示独立完成勾选")

        let mdB = MarkdownExporterService.generateMarkdown(
            recording: recB,
            note: noteB,
            revision: revB,
            confirmedActions: [confirmedMarkdown, reminderConfirmed],
            segments: store.segmentsByRecording[recB.id] ?? []
        )
        assert(mdB.contains("- [ ] 提交分镜初稿（主要管理位置：Markdown"), "A09: 主要位置为 Markdown 的任务带 checkbox")
        assert(mdB.contains("- 提交分镜初稿（主要管理位置：Apple 提醒事项；创建结果：已创建；完成状态：以提醒事项为准"), "A09: 提醒事项任务在 Markdown 中仅留普通列表引用，不复制 checkbox")
        print("  ✓ [A09 / A20 / A23 / A30] 随手记精简结构、单一主要管理位置与 Markdown 导出规范通过")

        // 5. A07 / A08 / A21 / A25 / A28 / A29：全文搜索、模式切换不覆盖确认项、授权撤回、取消分享不记已导出
        let hits = store.searchRecordings(query: "北海道温泉")
        assert(hits.count == 1 && hits.first?.matchedSegmentSnippet != nil, "A08: 逐字稿关键词搜索命中并返回片段")

        store.switchNoteMode(for: recB.id, to: .quickNote)
        let afterSwitchConfirmed = store.confirmedActionsByRecording[recB.id] ?? []
        assert(afterSwitchConfirmed.contains(where: { $0.id == confirmedMarkdown.id }), "A21 / A25: 切换模式或重新生成笔记不得覆盖已确认行动")

        store.grantCloudProcessingConsent(rememberPreference: true)
        assert(store.processingConsent.canAutoProcessWithoutPrompt, "A28: 记住云处理授权生效")
        store.revokeCloudProcessingConsent()
        assert(!store.processingConsent.canAutoProcessWithoutPrompt, "A28: 撤回云处理授权后不再自动上传")

        store.recordMarkdownExportResult(for: recB.id, result: .cancelled)
        assert(!store.hasCompletedMarkdownExport(for: recB.id), "A29: 取消分享不标为已导出")
        store.recordMarkdownExportResult(for: recB.id, result: .completed)
        assert(store.hasCompletedMarkdownExport(for: recB.id), "A29: 完成导出记录状态")
        print("  ✓ [A07 / A08 / A21 / A25 / A28 / A29] 搜索、版本隔离、授权撤回与导出边界全部通过")

        print("🎉 全部 PRD v1.1 核心验收测试通过！")

        await testV13BugsAndFeatures()
    }

    @MainActor
    static func testV13BugsAndFeatures() async {
        print("▶ 开始执行 MemoFlow V1.3 核心验收测试 (BUG-001, BUG-002, UX-001, VIS-001)...")

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoFlowV13Test_\(UUID().uuidString).json")
        let store = MemoFlowStore(customStorageURL: tempURL)

        // 1. UX-001：跨日期的全局记忆搜索验收
        let cal = Calendar.current
        let today = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let threeMonthsAgo = cal.date(byAdding: .day, value: -90, to: today)!

        let recToday = Recording(id: UUID(), title: "今天拍摄发光面膜", createdAt: today, duration: 30, localAudioFileName: "today.m4a")
        let recYesterday = Recording(id: UUID(), title: "昨天讨论特斯拉TV脚本", createdAt: yesterday, duration: 60, localAudioFileName: "yesterday.m4a")
        let recOld = Recording(id: UUID(), title: "三个月前的日本旅行灵感", createdAt: threeMonthsAgo, duration: 45, localAudioFileName: "old.m4a")

        store.recordings = [recToday, recYesterday, recOld]
        store.segmentsByRecording[recOld.id] = [
            TranscriptSegment(id: "seg_01", recordingId: recOld.id, startMs: 1000, endMs: 8000, text: "北海道温泉与手冲咖啡镜头转场", speakerName: "Dustin")
        ]

        // 1.1 当未输入关键词时，按指定日期筛选（只返回今天的录音）
        let emptyQueryTodayResults = store.searchRecordings(query: "", on: today)
        assert(emptyQueryTodayResults.count == 1 && emptyQueryTodayResults.first?.recording.id == recToday.id, "UX-001: 无搜索词时按所选日期筛选")

        // 1.2 当输入关键词时，全局搜索跨所有日期（即使传入 nil 也能搜到三个月前的录音）
        let globalSearchResults = store.searchRecordings(query: "北海道", on: nil)
        assert(globalSearchResults.count == 1 && globalSearchResults.first?.recording.id == recOld.id, "UX-001: 全局搜索必须命中几个月前的历史逐字稿")
        assert(globalSearchResults.first?.matchedSegmentStartMs == 1000, "UX-001: 全局搜索返回匹配原话的起始毫秒时间戳")

        let globalTitleResults = store.searchRecordings(query: "特斯拉", on: nil)
        assert(globalTitleResults.count == 1 && globalTitleResults.first?.recording.id == recYesterday.id, "UX-001: 全局搜索必须命中历史日期的录音标题")
        print("  ✓ [UX-001] 跨日期全局记忆搜索与逐字稿原话毫秒级匹配验证通过")

        // 2. BUG-002：长音频切片与分段真实时间戳保护验收
        let chunkDuration: TimeInterval = 90.0
        let chunkOffsetMs = 90000 // 第二个切片起始 90s
        let sampleText = "鬼面积影响其实穿插穿插一个季度一起穿插三个为什么"

        let proportionalSegments = ASRAndLLMService.shared.splitTextIntoProportionalSegments(
            fullText: sampleText,
            recordingId: recToday.id,
            totalDuration: chunkDuration,
            baseOffsetMs: chunkOffsetMs
        )
        assert(!proportionalSegments.isEmpty, "BUG-002: 切片分段成功生成")
        let firstSeg = proportionalSegments.first!
        assert(firstSeg.startMs == chunkOffsetMs, "BUG-002: 分段起始时间必须基于切片偏移量 (90000ms)")
        assert(firstSeg.endMs <= chunkOffsetMs + Int(chunkDuration * 1000), "BUG-002: 单句分段绝不能被拉伸到 49 分钟（2950000ms）")
        assert(firstSeg.endMs < 200000, "BUG-002: 时间戳严格限制在切片窗口内")
        print("  ✓ [BUG-002] 长音频切片时间戳隔离与防单句拉伸验证通过")

        // 3. VIS-001：极简纸质化主题与设置状态持久化验收
        assert(store.preferences.appearanceTheme == .warmPaper, "VIS-001: 默认主题为极简暖纸 (warmPaper)")
        store.preferences.appearanceTheme = .darkNight
        store.saveToDisk()
        let reloadedStore = MemoFlowStore(customStorageURL: tempURL)
        assert(reloadedStore.preferences.appearanceTheme == .darkNight, "VIS-001: 主题偏好持久化生效")
        print("  ✓ [VIS-001] Readwise 极简纸质化视觉主题与持久化验证通过")

        print("🎉 全部 MemoFlow V1.3 核心验收测试通过！")
    }

    static func testKnowledgeIntegration() async throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("MemoFlowKnowledgeTest-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let project = directory.appendingPathComponent("科研栏目.md")
        try "科研栏目项目：分镜评审采用真实研究案例。旧计划曾在周五提交。".write(to: project, atomically: true, encoding: .utf8)
        let privateDirectory = directory.appendingPathComponent("日记")
        try fm.createDirectory(at: privateDirectory, withIntermediateDirectories: true)
        try "科研栏目私人记录".write(to: privateDirectory.appendingPathComponent("秘密.md"), atomically: true, encoding: .utf8)
        var preferences = MemoFlowPreferences()
        preferences.obsidianVaultBookmark = try VaultAccess.bookmark(for: directory)
        preferences.knowledgeContextEnabled = true
        let service = ObsidianKnowledgeService()
        let first = try await service.refresh(preferences: preferences, query: "科研栏目分镜评审")
        assert(first.count == 1 && first.references.first?.path == "科研栏目.md", "检索相关中文笔记并排除私人目录")
        assert(ObsidianKnowledgeService.retrieve(query: "橡树园艺", candidates: first.references).isEmpty, "无关内容不发送")
        try "科研栏目已改名为实验观察节目，新安排是下月启动。".write(to: project, atomically: true, encoding: .utf8)
        let changed = try await service.refresh(preferences: preferences, query: "实验观察节目")
        assert(changed.references.first?.excerpt.contains("下月启动") == true, "修改内容会更新索引")
        try fm.removeItem(at: project)
        let removed = try await service.refresh(preferences: preferences, query: "科研栏目")
        assert(removed.count == 0 && removed.references.isEmpty, "已删除笔记不残留")
        preferences.knowledgeContextEnabled = false
        let disabled = try await service.refresh(preferences: preferences, query: "科研栏目")
        assert(disabled.references.isEmpty, "关闭辅助时不提供知识库片段")

        let recording = Recording(title: "测试", localAudioFileName: "test.m4a")
        let segment = TranscriptSegment(id: "seg_01", recordingId: recording.id, startMs: 0, endMs: 1000, text: "今天只讨论科研栏目背景。")
        let json = #"{"actionDrafts":[{"description":"周五提交","ownership":"self","sourceSegmentIds":["seg_01"],"evidenceQuote":"旧计划曾在周五提交。"}]}"#.data(using: .utf8)!
        let output = try ASRAndLLMService.shared.decodeAndValidateOrganizationJSON(jsonData: json, recording: recording, segments: [segment], requestedMode: .meetingNote, revisionId: UUID(), preferences: preferences)
        assert(output.actionDrafts.first?.hasValidEvidence == false, "历史待办不能通过本次原话验证")
        assert(output.actionDrafts.first?.isEligibleForBatchExecution == false, "无本次证据的待办禁止批量执行")
        let oldContent = try JSONDecoder().decode(StructuredNoteContent.self, from: Data(#"{"suggestedTitle":"旧笔记","summaryOrShortNote":"旧内容"}"#.utf8))
        assert(oldContent.knowledgeReferences.isEmpty, "旧版本笔记可兼容读取")
        let file1 = try MarkdownExporterService.writeDirectlyToObsidianVault(recording: recording, markdownContent: "one", vaultRootPath: directory.path, subfolder: "export")
        let file2 = try MarkdownExporterService.writeDirectlyToObsidianVault(recording: recording, markdownContent: "two", vaultRootPath: directory.path, subfolder: "export")
        assert(file1.fileURL != file2.fileURL, "协调写入仍保护同名旧笔记")
        print("✓ 知识库检索、隐私排除、更新/删除、关闭辅助、旧数据兼容、原话验证与协调导出通过")
    }
}
