import XCTest
@testable import MemoFlowCore

@MainActor
final class V14IncrementalTests: XCTestCase {

    // MARK: - WATCH-001 Tests

    func testWATCH001_DeviceSourceBackwardCompatibility() throws {
        // 1. 验证旧版无 deviceSource 字段的 JSON 能够无损兼容解码
        let legacyJSON = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "title": "旧版随手记",
            "createdAt": 1730000000,
            "recordedTimeZoneIdentifier": "Asia/Shanghai",
            "duration": 45.0,
            "localAudioFileName": "rec_legacy.m4a",
            "language": "zh-CN",
            "processingStatus": "completed"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(Recording.self, from: legacyJSON)

        XCTAssertEqual(decoded.title, "旧版随手记")
        XCTAssertFalse(decoded.isFromAppleWatch)

        // 2. 验证新版 .appleWatch 字段正常编码与解码
        var watchRec = decoded
        watchRec.deviceSource = .appleWatch
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let encoded = try encoder.encode(watchRec)

        let reDecoded = try decoder.decode(Recording.self, from: encoded)
        XCTAssertEqual(reDecoded.deviceSource, .appleWatch)
        XCTAssertTrue(reDecoded.isFromAppleWatch)
    }

    func testWATCH001_WatchRecordingImport() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = MemoFlowStore(customStorageURL: tempDir)

        // 模拟 Watch 传输的临时音频文件
        let tempAudioURL = tempDir.appendingPathComponent("watch_temp.m4a")
        try "dummy_audio_bytes".data(using: .utf8)!.write(to: tempAudioURL)

        let recId = UUID()
        let metadata: [String: Any] = [
            "recordingId": recId.uuidString,
            "title": "Watch 晨跑灵感",
            "speakerNicknameTheme": "interstellar",
            "duration": 60.0,
            "createdAt": Date().timeIntervalSince1970
        ]

        let imported = try await store.importWatchRecording(audioFileURL: tempAudioURL, metadata: metadata)

        XCTAssertEqual(imported.id, recId)
        XCTAssertEqual(imported.title, "Watch 晨跑灵感")
        XCTAssertEqual(imported.deviceSource, .appleWatch)
        XCTAssertTrue(imported.isFromAppleWatch)
        XCTAssertEqual(imported.duration, 60.0)
        XCTAssertEqual(imported.speakerNicknameTheme, .interstellar)
        store.preferences.speakerNicknameTheme = .strangerThings
        XCTAssertEqual(store.recordings.first(where: { $0.id == recId })?.speakerNicknameTheme, .interstellar)

        // 验证文件已安全落盘至本地 recordings 目录
        let savedAudioURL = store.audioService.recordingsDirectoryURL.appendingPathComponent(imported.localAudioFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedAudioURL.path))
    }

    // MARK: - CHAT-001 Tests

    func testCHAT001B_CrossDateCandidateSearch() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = MemoFlowStore(customStorageURL: tempDir)

        // 创建三个跨日期的历史录音：今天、15天前、30天前
        let cal = Calendar.current
        let now = Date()
        let date1 = now
        let date2 = cal.date(byAdding: .day, value: -15, to: now)!
        let date3 = cal.date(byAdding: .day, value: -30, to: now)!

        let rec1 = Recording(id: UUID(), title: "科研栏目首期选题研讨", createdAt: date1, duration: 300, localAudioFileName: "r1.m4a")
        let rec2 = Recording(id: UUID(), title: "设计团队周会", createdAt: date2, duration: 600, localAudioFileName: "r2.m4a")
        let rec3 = Recording(id: UUID(), title: "科研栏目预算与排期确认", createdAt: date3, duration: 900, localAudioFileName: "r3.m4a")

        store.recordings = [rec1, rec2, rec3]

        // 逐字稿命中
        store.segmentsByRecording[rec2.id] = [
            TranscriptSegment(id: "s1", recordingId: rec2.id, startMs: 30000, endMs: 35000, text: "我们在科研栏目的视觉包装上需要保持纸质极简风")
        ]

        // 跨日期检索测试：不受当前日期或热力图限制
        let candidates = store.findProjectNoteCandidates(query: "把关于科研栏目的录音整理成项目笔记")

        // rec1（标题包含科研栏目）、rec2（逐字稿提及科研栏目）、rec3（标题包含科研栏目）均应被成功检索
        XCTAssertEqual(candidates.count, 3)
        let candidateTitles = Set(candidates.map(\.recording.title))
        XCTAssertTrue(candidateTitles.contains("科研栏目首期选题研讨"))
        XCTAssertTrue(candidateTitles.contains("设计团队周会"))
        XCTAssertTrue(candidateTitles.contains("科研栏目预算与排期确认"))
    }

    func testCHAT001CD_ProjectNoteSynthesisConformsToSection47Template() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = MemoFlowStore(customStorageURL: tempDir)

        let cal = Calendar.current
        let dateA = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10, minute: 0))!
        let dateB = cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 14, minute: 30))!

        let recA = Recording(id: UUID(), title: "科研栏目前期规划", createdAt: dateA, duration: 600, localAudioFileName: "recA.m4a")
        let recB = Recording(id: UUID(), title: "科研栏目决策会", createdAt: dateB, duration: 1200, localAudioFileName: "recB.m4a")

        store.recordings = [recB, recA] // 逆序插入验证时间线排序

        // 为 recA 提供章节与逐字稿
        store.segmentsByRecording[recA.id] = [
            TranscriptSegment(id: "sA1", recordingId: recA.id, startMs: 192000, endMs: 200000, text: "我们计划先做三期播客原型")
        ]
        let noteAId = UUID()
        let revAId = UUID()
        let noteA = Note(id: noteAId, recordingId: recA.id, mode: .meetingNote, currentRevisionId: revAId)
        let noteRevA = NoteRevision(
            id: revAId,
            noteId: noteAId,
            mode: .meetingNote,
            content: StructuredNoteContent(
                suggestedTitle: "科研栏目前期规划",
                summaryOrShortNote: "讨论科研栏目初步设想与原型制作",
                backgroundPoints: ["聚焦前沿科技口述历史记录"],
                keyPoints: ["首期计划通过播客原型验证用户反馈"],
                decisions: ["首期栏目确定采用纸质极简视觉设计"],
                chapters: [
                    NoteChapter(title: "播客原型讨论", startMs: 192000, endMs: 200000, summary: "规划前三期内容")
                ],
                historicalContextNotes: [],
                aiInferences: []
            ),
            origin: .ai
        )
        store.notesByRecording[recA.id] = noteA
        store.revisionsByNote[noteAId] = [noteRevA]

        // 为 recB 提供待办与决议
        store.segmentsByRecording[recB.id] = [
            TranscriptSegment(id: "sB1", recordingId: recB.id, startMs: 756000, endMs: 760000, text: "预算上限三十万已批准")
        ]
        store.actionDraftsByRecording[recB.id] = [
            ActionDraft(
                id: UUID(),
                recordingId: recB.id,
                revisionId: UUID(),
                kind: .task,
                description: "提交第一期播客分镜脚本",
                owner: "李老师",
                ownership: .other,
                originalDateText: "下周三前",
                proposedDestination: .reminders
            )
        ]

        let markdown = try await store.synthesizeProjectNote(topic: "科研栏目", selectedRecordingIds: [recA.id, recB.id])

        // 验证 Section 4.7 模板结构
        XCTAssertTrue(markdown.contains("---"), "必须包含 Frontmatter")
        XCTAssertTrue(markdown.contains("source: MemoFlow"), "Frontmatter 包含 source")
        XCTAssertTrue(markdown.contains("# 科研栏目｜项目讨论整理"), "包含一级标题")
        XCTAssertTrue(markdown.contains("## 一、项目背景"), "包含项目背景")
        XCTAssertTrue(markdown.contains("## 二、讨论时间线"), "包含讨论时间线")
        XCTAssertTrue(markdown.contains("## 三、关键决定"), "包含关键决定")
        XCTAssertTrue(markdown.contains("## 四、待办事项"), "包含待办事项")
        XCTAssertTrue(markdown.contains("## 五、待确认问题"), "包含待确认问题")
        XCTAssertTrue(markdown.contains("## 六、来源录音"), "包含来源录音")

        // 验证来源与时间戳可查性（来源：录音名，MM:SS）
        XCTAssertTrue(markdown.contains("（来源：科研栏目"), "必须包含可溯源时间戳引用")
        XCTAssertTrue(markdown.contains("提交第一期播客分镜脚本"), "必须包含提取的真实待办")
        XCTAssertTrue(markdown.contains("李老师"), "保留负责人")
    }

    func testCHAT001E_NonDestructiveObsidianExportAndDisambiguation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vaultDir = tempDir.appendingPathComponent("TestVault")
        try FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = MemoFlowStore(customStorageURL: tempDir)
        store.bindObsidianVault(vaultDir)
        store.preferences.obsidianTargetSubfolder = "MemoFlow笔记"

        let title = "科研栏目｜项目讨论整理"
        let markdown1 = "# 版本 1 笔记内容"

        // 1. 首次导出：创建 <title>.md
        let (fileURL1, _, _) = try store.exportProjectNoteToObsidian(
            title: title,
            markdown: markdown1,
            sourceRecordingIds: []
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL1.path))
        XCTAssertEqual(fileURL1.lastPathComponent, "科研栏目｜项目讨论整理.md")

        // 2. 第二次导出同名笔记：CHAT-001E 必须绝不覆盖原有笔记，自动采用 _1.md 序号保护
        let markdown2 = "# 版本 2 新建项目笔记"
        let (fileURL2, _, _) = try store.exportProjectNoteToObsidian(
            title: title,
            markdown: markdown2,
            sourceRecordingIds: []
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL2.path))
        XCTAssertEqual(fileURL2.lastPathComponent, "科研栏目｜项目讨论整理_1.md")
        XCTAssertNotEqual(fileURL1.path, fileURL2.path)

        // 3. 验证原笔记内容完好无损，未被覆盖！
        let originalText = try String(contentsOf: fileURL1, encoding: .utf8)
        XCTAssertEqual(originalText, markdown1)

        let newText = try String(contentsOf: fileURL2, encoding: .utf8)
        XCTAssertEqual(newText, markdown2)
    }

    func testCHAT001B_RelativeDateFiltering() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = MemoFlowStore(customStorageURL: tempDir)

        let cal = Calendar.current
        let referenceNow = cal.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12, minute: 0))!

        let recToday = Recording(id: UUID(), title: "今天讨论架构", createdAt: referenceNow, duration: 300, localAudioFileName: "today.m4a")
        let rec10DaysAgo = Recording(id: UUID(), title: "十天前选题", createdAt: cal.date(byAdding: .day, value: -10, to: referenceNow)!, duration: 400, localAudioFileName: "10d.m4a")
        let rec45DaysAgo = Recording(id: UUID(), title: "上月老讨论", createdAt: cal.date(byAdding: .day, value: -45, to: referenceNow)!, duration: 500, localAudioFileName: "45d.m4a")

        store.recordings = [recToday, rec10DaysAgo, rec45DaysAgo]

        // 1. 查询“最近一个月”：应命中今天与10天前，排除45天前的录音
        let monthCandidates = store.findProjectNoteCandidates(query: "整理最近一个月的录音", referenceDate: referenceNow)
        let monthIds = Set(monthCandidates.map(\.recording.id))
        XCTAssertTrue(monthIds.contains(recToday.id))
        XCTAssertTrue(monthIds.contains(rec10DaysAgo.id))
        XCTAssertFalse(monthIds.contains(rec45DaysAgo.id))

        // 2. 查询“最近一周关于架构”：应仅命中今天的录音
        let weekCandidates = store.findProjectNoteCandidates(query: "把最近一周关于架构的录音整理成项目笔记", referenceDate: referenceNow)
        XCTAssertEqual(weekCandidates.count, 1)
        XCTAssertEqual(weekCandidates.first?.recording.title, "今天讨论架构")
    }

    func testCHAT001E_IdempotentExportWithExistingPath() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vaultDir = tempDir.appendingPathComponent("TestVault")
        try FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = MemoFlowStore(customStorageURL: tempDir)
        store.bindObsidianVault(vaultDir)

        let title = "科研栏目讨论整理"
        let initialMarkdown = "# 草稿 1"

        // 首次导出
        let (fileURL1, relPath1, _) = try store.exportProjectNoteToObsidian(
            title: title,
            markdown: initialMarkdown,
            sourceRecordingIds: []
        )
        XCTAssertEqual(fileURL1.lastPathComponent, "科研栏目讨论整理.md")

        // 再次保存相同草稿（传入已存在的 relativePath）：幂等更新同一文件，不生成 _1.md
        let updatedMarkdown = "# 草稿 1（已人工修正补充）"
        let (fileURL2, relPath2, _) = try store.exportProjectNoteToObsidian(
            title: title,
            markdown: updatedMarkdown,
            sourceRecordingIds: [],
            existingRelativePath: relPath1
        )
        XCTAssertEqual(fileURL1.path, fileURL2.path)
        XCTAssertEqual(relPath1, relPath2)

        let savedContent = try String(contentsOf: fileURL2, encoding: .utf8)
        XCTAssertEqual(savedContent, updatedMarkdown)
    }

    func testCHAT001_OfflineFallbackNoticeAndDecisionTimestampMapping() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = MemoFlowStore(customStorageURL: tempDir)

        let rec = Recording(id: UUID(), title: "选题会", createdAt: Date(), duration: 600, localAudioFileName: "x.m4a")
        store.recordings = [rec]

        // 包含在 03:20 发生的决策逐字稿
        store.segmentsByRecording[rec.id] = [
            TranscriptSegment(id: "s1", recordingId: rec.id, startMs: 0, endMs: 5000, text: "大家早"),
            TranscriptSegment(id: "s2", recordingId: rec.id, startMs: 200000, endMs: 205000, text: "关于经费，确定采用三十万预算方案")
        ]

        let noteId = UUID()
        let revId = UUID()
        let note = Note(id: noteId, recordingId: rec.id, mode: .meetingNote, currentRevisionId: revId)
        let rev = NoteRevision(
            id: revId,
            noteId: noteId,
            mode: .meetingNote,
            content: StructuredNoteContent(
                suggestedTitle: "选题会",
                summaryOrShortNote: "讨论选题与预算",
                backgroundPoints: [],
                keyPoints: [],
                decisions: ["确定采用三十万预算方案"],
                chapters: [],
                historicalContextNotes: [],
                aiInferences: []
            ),
            origin: .ai
        )
        store.notesByRecording[rec.id] = note
        store.revisionsByNote[noteId] = [rev]

        // 未配置 LLM 密钥，应平滑降级到离线规则并包含警示标识
        let markdown = try await store.synthesizeProjectNote(topic: "选题", selectedRecordingIds: [rec.id])

        XCTAssertTrue(markdown.contains("本地离线规则整理"), "未配置 LLM 时必须明确标注离线降级")
        XCTAssertTrue(markdown.contains("03:20"), "决策必须精准关联到发生时刻的时间戳，而不是总是 00:00")
    }

    func testCHAT001_VerifiableDeepLinksAndCanonicalSourceList() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = MemoFlowStore(customStorageURL: tempDir)

        let idA = UUID()
        let idB = UUID()
        var recA = Recording(id: idA, title: "需求评审会", createdAt: Date(), duration: 600, localAudioFileName: "a.m4a")
        recA.isTranscriptReviewed = true // 已校对

        var recB = Recording(id: idB, title: "设计对齐会", createdAt: Date(), duration: 1200, localAudioFileName: "b.m4a")
        recB.isTranscriptReviewed = false // 未校对初稿

        store.recordings = [recA, recB]
        store.segmentsByRecording[idA] = [
            TranscriptSegment(id: "sa1", recordingId: idA, startMs: 120000, endMs: 125000, text: "UI 确认采用暖纸极简设计")
        ]
        store.segmentsByRecording[idB] = [
            TranscriptSegment(id: "sb1", recordingId: idB, startMs: 300000, endMs: 305000, text: "底栏采用圆形悬浮菜单")
        ]

        let noteAId = UUID()
        let noteA = Note(id: noteAId, recordingId: idA, mode: .meetingNote, currentRevisionId: UUID())
        let revA = NoteRevision(
            id: noteA.currentRevisionId,
            noteId: noteAId,
            mode: .meetingNote,
            content: StructuredNoteContent(
                suggestedTitle: "需求评审会",
                summaryOrShortNote: "讨论 UI",
                backgroundPoints: [],
                keyPoints: [],
                decisions: ["UI 确认采用暖纸极简设计"],
                chapters: [],
                historicalContextNotes: [],
                aiInferences: []
            ),
            origin: .ai
        )
        store.notesByRecording[idA] = noteA
        store.revisionsByNote[noteAId] = [revA]

        let markdown = try await store.synthesizeProjectNote(topic: "界面设计", selectedRecordingIds: [idA, idB])

        // 1. 验证关键决定引用带可回听的深链 [MM:SS](memoflow://recording/ID?startMs=...)
        XCTAssertTrue(markdown.contains("memoflow://recording/\(idA.uuidString)?startMs=120000"), "引用必须带可直接回听对应秒数的深链")

        // 2. 验证「六、来源录音」包含可点击录音深链与人工校对状态
        XCTAssertTrue(markdown.contains("[需求评审会](memoflow://recording/\(idA.uuidString)?startMs=0)"))
        XCTAssertTrue(markdown.contains("状态: 已人工校对"))
        XCTAssertTrue(markdown.contains("[设计对齐会](memoflow://recording/\(idB.uuidString)?startMs=0)"))
        XCTAssertTrue(markdown.contains("状态: 机器初稿（未校对）"))
    }

    func testCHAT001_PathSandboxAndDirectoryTraversalPrevention() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vaultDir = tempDir.appendingPathComponent("TestVault")
        try FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = MemoFlowStore(customStorageURL: tempDir)
        store.bindObsidianVault(vaultDir)

        // 尝试通过相对路径遍历逃逸出 Vault 目录
        store.preferences.obsidianTargetSubfolder = "../../SecretDirectory"

        XCTAssertThrowsError(
            try store.exportProjectNoteToObsidian(
                title: "越界测试",
                markdown: "malicious content",
                sourceRecordingIds: []
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("超出已授权笔记库范围"))
        }
    }

    func testCHAT001_ExclusionOfDeselectedRecordingAndCancelDraft() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vaultDir = tempDir.appendingPathComponent("TestVault")
        try FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = MemoFlowStore(customStorageURL: tempDir)
        store.bindObsidianVault(vaultDir)

        let recA = Recording(id: UUID(), title: "录音A", createdAt: Date(), duration: 100, localAudioFileName: "a.m4a")
        let recB = Recording(id: UUID(), title: "录音B", createdAt: Date(), duration: 200, localAudioFileName: "b.m4a")
        let recC = Recording(id: UUID(), title: "绝密未勾选录音C", createdAt: Date(), duration: 300, localAudioFileName: "c.m4a")

        store.recordings = [recA, recB, recC]
        store.segmentsByRecording[recC.id] = [
            TranscriptSegment(id: "sc", recordingId: recC.id, startMs: 0, endMs: 5000, text: "这里是绝密专有代码X99999")
        ]

        // 仅勾选 A 和 B，排除 C
        let markdown = try await store.synthesizeProjectNote(topic: "测试", selectedRecordingIds: [recA.id, recB.id])

        // 1. 验证 C 的任何独有内容和 ID 完全不出现在生成的笔记中
        XCTAssertFalse(markdown.contains("绝密专有代码X99999"))
        XCTAssertFalse(markdown.contains(recC.id.uuidString.prefix(8)))

        // 2. 如果用户仅生成草稿预览、随后取消并未确认写入：Vault 目录中应有 0 个文件
        let filesBeforeConfirm = try FileManager.default.contentsOfDirectory(atPath: vaultDir.path)
        XCTAssertEqual(filesBeforeConfirm.count, 0, "未确认导出前绝对不向 Vault 写入任何文件")
    }
}
