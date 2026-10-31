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
            "duration": 60.0,
            "createdAt": Date().timeIntervalSince1970
        ]

        let imported = try await store.importWatchRecording(audioFileURL: tempAudioURL, metadata: metadata)

        XCTAssertEqual(imported.id, recId)
        XCTAssertEqual(imported.title, "Watch 晨跑灵感")
        XCTAssertEqual(imported.deviceSource, .appleWatch)
        XCTAssertTrue(imported.isFromAppleWatch)
        XCTAssertEqual(imported.duration, 60.0)

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
}
