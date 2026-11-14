import XCTest
@testable import TelomiCore

final class MemoFlowPRDAcceptanceTests: XCTestCase {

    @MainActor private func makeIsolatedStore() -> MemoFlowStore {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MemoFlowTest_\(UUID().uuidString).json")
        return MemoFlowStore(customStorageURL: tempURL)
    }

    /// A01 & A27：无网络录制并结束 -> 本地存在音频，状态为「已安全保存·待转写」
    @MainActor
    func testA01_OfflineRecordingSavedSafelyPendingTranscription() {
        let store = makeIsolatedStore()
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

        guard let saved = store.recordings.first(where: { $0.id == recId }) else {
            XCTFail("录音未保存")
            return
        }
        XCTAssertEqual(saved.processingStatus, .savedPendingTranscription)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.audioService.audioFileURL(for: fileName).path))
    }

    /// A12 & A32 & 4.6：相对日期必须锚定「录音发生日期与录音时区」而非转写当天；无结束时间自动补默认时长并标记
    func testA12_A32_RelativeDateAnchoredToRecordingTimestampAndDefaultDuration() {
        let tz = TimeZone(identifier: "Asia/Shanghai")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz

        // 假设是一周前（2026-10-19 周一 10:00）录制的旧录音，今天才转写（A32）
        let recordingDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 10, minute: 0))!
        let seg = TranscriptSegment(
            id: "seg_01",
            recordingId: UUID(),
            startMs: 5000,
            endMs: 12000,
            text: "明天 15:00 到 16:00 开分镜评审会"
        )

        let rawDraft = ActionDraft(
            recordingId: seg.recordingId,
            revisionId: UUID(),
            kind: .event,
            description: "开分镜评审会",
            ownership: .selfOwner,
            originalDateText: "明天 15:00 到 16:00",
            sourceSegmentIds: ["seg_01"],
            evidenceQuote: seg.text,
            proposedDestination: .calendar
        )

        let prefs = MemoFlowPreferences(defaultEventDurationMinutes: 30)
        let validated = RelativeDateAndActionValidator.validateAndNormalize(
            draft: rawDraft,
            segments: [seg],
            recordingCreatedAt: recordingDate,
            recordingTimeZone: tz,
            preferences: prefs
        )

        XCTAssertEqual(validated.datePrecision, .exactTime)
        XCTAssertEqual(validated.evidenceStartMs, 5000)
        XCTAssertEqual(validated.evidenceEndMs, 12000)

        let startComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: validated.startAt!)
        let endComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: validated.endAt!)
        // 必须是录音次日 2026-10-20 15:00 - 16:00
        XCTAssertEqual(startComps.day, 20)
        XCTAssertEqual(startComps.hour, 15)
        XCTAssertEqual(endComps.hour, 16)
        XCTAssertFalse(validated.isDefaultDurationApplied)

        // 测试只有开始时间、无结束时间（「明天下午 3 点沟通脚本」）-> 自动补 30 分钟默认时长并标记
        let startOnlyDraft = ActionDraft(
            recordingId: seg.recordingId,
            revisionId: UUID(),
            kind: .event,
            description: "沟通脚本",
            ownership: .selfOwner,
            originalDateText: "明天下午 3 点",
            sourceSegmentIds: ["seg_01"],
            evidenceQuote: "明天下午 3 点沟通脚本",
            proposedDestination: .calendar
        )
        let validatedStartOnly = RelativeDateAndActionValidator.validateAndNormalize(
            draft: startOnlyDraft,
            segments: [seg],
            recordingCreatedAt: recordingDate,
            recordingTimeZone: tz,
            preferences: prefs
        )
        XCTAssertTrue(validatedStartOnly.isDefaultDurationApplied)
        XCTAssertEqual(validatedStartOnly.appliedDefaultDurationMinutes, 30)
        XCTAssertEqual(validatedStartOnly.endAt!.timeIntervalSince(validatedStartOnly.startAt!), 1800)
    }

    /// A13 & A14 & A26 & A31：模糊时间、截止日期任务、他人负责任务的边界护栏与批量执行过滤
    func testA13_A14_A26_A31_ActionBoundariesAndBatchEligibility() {
        let tz = TimeZone(identifier: "Asia/Shanghai")!
        let recDate = Date()
        let seg = TranscriptSegment(id: "seg_01", recordingId: UUID(), startMs: 1000, endMs: 6000, text: "测试段落")
        let prefs = MemoFlowPreferences()

        // A13：录音说「下周找时间沟通」-> 保持待确认，禁止混入一键批量写入
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
            recordingCreatedAt: recDate,
            recordingTimeZone: tz,
            preferences: prefs
        )
        XCTAssertEqual(ambiguousDraft.datePrecision, .ambiguous)
        XCTAssertTrue(ambiguousDraft.needsConfirmation)
        XCTAssertFalse(ambiguousDraft.isEligibleForBatchExecution)

        // A14：录音说「周五前交报告」-> 仅日期精度，建议进入提醒事项，不默认创建全天日历事件
        let deadlineDraft = RelativeDateAndActionValidator.validateAndNormalize(
            draft: ActionDraft(
                recordingId: seg.recordingId,
                revisionId: UUID(),
                kind: .event, // 即使模型误标为 event，只有日期时也必须纠正为 task 且不进 calendar
                description: "交报告",
                ownership: .selfOwner,
                originalDateText: "周五前",
                sourceSegmentIds: ["seg_01"],
                evidenceQuote: "周五前交报告",
                proposedDestination: .calendar
            ),
            segments: [seg],
            recordingCreatedAt: recDate,
            recordingTimeZone: tz,
            preferences: prefs
        )
        XCTAssertEqual(deadlineDraft.kind, .task)
        XCTAssertEqual(deadlineDraft.datePrecision, .dateOnly)
        XCTAssertNotEqual(deadlineDraft.proposedDestination, .calendar)
        XCTAssertNil(deadlineDraft.startAt)
        XCTAssertNotNil(deadlineDraft.dueDate)

        // A26：录音说「小王周五交初稿」-> 标注他人负责，仅保留上下文，禁止直接批量创建为本人任务
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
            recordingCreatedAt: recDate,
            recordingTimeZone: tz,
            preferences: prefs
        )
        XCTAssertEqual(otherOwnerDraft.ownership, .other)
        XCTAssertEqual(otherOwnerDraft.proposedDestination, .local)
        XCTAssertFalse(otherOwnerDraft.isEligibleForBatchExecution)
    }

    /// A09 & A20 & A23 & A30：随手记不扩写空章节；Markdown 导出仅对主要位置为 Markdown 的任务生成 checkbox，提醒事项任务只留引用
    @MainActor
    func testA09_A20_A23_A30_MarkdownExportAndSinglePrimaryDestination() async {
        let store = makeIsolatedStore()

        // 1. 验证场景 A（随手记 A20）：不强行生成「关键观点」「已确认结论」空章节
        guard let recA = store.recordings.last,
              let noteA = store.notesByRecording[recA.id],
              let revA = store.currentRevision(for: recA.id) else {
            XCTFail("缺少预设场景 A")
            return
        }
        let mdA = MarkdownExporterService.generateMarkdown(
            recording: recA,
            note: noteA,
            revision: revA,
            confirmedActions: [],
            segments: store.segmentsByRecording[recA.id] ?? []
        )
        XCTAssertFalse(mdA.contains("## 关键观点"))
        XCTAssertFalse(mdA.contains("## 已确认结论"))
        XCTAssertTrue(mdA.contains("咖啡杯上升的蒸汽"))

        // 2. 验证场景 B（会议记 A09, A23, A30）：区分 Markdown 待办（带 - [ ]）与提醒事项任务（普通列表引用，无 checkbox）
        guard let recB = store.recordings.first,
              let noteB = store.notesByRecording[recB.id],
              let revB = store.currentRevision(for: recB.id),
              let draftsB = store.actionDraftsByRecording[recB.id] else {
            XCTFail("缺少预设场景 B")
            return
        }

        // 将第一条任务确认为 Markdown 主要位置
        let taskDraft1 = draftsB[1]
        let confirmedMarkdown = await store.confirmAndExecuteDraft(taskDraft1, chosenDestination: .markdown)
        XCTAssertNil(confirmedMarkdown.localCompletion)
        XCTAssertFalse(confirmedMarkdown.allowsLocalCompletionToggle)

        // 模拟一条已交给 Apple 提醒事项的 ConfirmedAction
        let reminderConfirmed = ConfirmedAction(
            recordingId: recB.id,
            sourceDraftId: UUID(),
            confirmedSnapshot: ActionSnapshot(from: taskDraft1),
            primaryDestination: .reminders,
            localCompletion: true, // 即使传入 true，初始化器也必须强制置为 nil（PRD R25）
            executionStatus: .handedToExternal
        )
        XCTAssertNil(reminderConfirmed.localCompletion)
        XCTAssertFalse(reminderConfirmed.allowsLocalCompletionToggle)

        let mdB = MarkdownExporterService.generateMarkdown(
            recording: recB,
            note: noteB,
            revision: revB,
            confirmedActions: [confirmedMarkdown, reminderConfirmed],
            segments: store.segmentsByRecording[recB.id] ?? []
        )

        XCTAssertTrue(mdB.contains("- [ ] 提交分镜初稿（主要管理位置：Markdown"))
        XCTAssertTrue(mdB.contains("- 提交分镜初稿（主要管理位置：Apple 提醒事项；创建结果：已创建；完成状态：以提醒事项为准"))
    }

    /// A07 & A08 & A21 & A25 & A28 & A29：编辑保留、全文搜索、切换模式不覆盖已确认行动、授权撤回、取消分享不记已导出
    @MainActor
    func testA07_A08_A21_A25_A28_A29_StoreInvariants() async {
        let store = makeIsolatedStore()
        guard let recB = store.recordings.first,
              let draftsB = store.actionDraftsByRecording[recB.id],
              let firstDraft = draftsB.first else {
            XCTFail("缺少预设数据")
            return
        }

        // A08：搜索逐字稿中的关键词「北海道温泉」
        let searchHits = store.searchRecordings(query: "北海道温泉")
        XCTAssertEqual(searchHits.count, 1)
        XCTAssertNotNil(searchHits.first?.matchedSegmentSnippet)

        // 先确认一条行动到本地管理
        let confirmed = await store.confirmAndExecuteDraft(firstDraft, chosenDestination: .local)
        XCTAssertTrue(confirmed.allowsLocalCompletionToggle)

        // A21 & A25：切换整理模式（会议记 -> 随手记），已确认行动 ID 与状态必须保持不变，不被覆盖
        store.switchNoteMode(for: recB.id, to: .quickNote)
        let afterSwitchConfirmed = store.confirmedActionsByRecording[recB.id] ?? []
        XCTAssertEqual(afterSwitchConfirmed.count, 1)
        XCTAssertEqual(afterSwitchConfirmed.first?.id, confirmed.id)

        // A28：记住云处理授权 -> 撤回授权
        store.grantCloudProcessingConsent(rememberPreference: true)
        XCTAssertTrue(store.processingConsent.canAutoProcessWithoutPrompt)
        store.revokeCloudProcessingConsent()
        XCTAssertFalse(store.processingConsent.canAutoProcessWithoutPrompt)

        // A29：取消 Markdown 分享不标为已导出
        store.recordMarkdownExportResult(for: recB.id, result: .cancelled)
        XCTAssertFalse(store.hasCompletedMarkdownExport(for: recB.id))
        store.recordMarkdownExportResult(for: recB.id, result: .completed)
        XCTAssertTrue(store.hasCompletedMarkdownExport(for: recB.id))
    }
}
