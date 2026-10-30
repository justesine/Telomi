import XCTest
@testable import MemoFlowCore

final class ObsidianPhasedTests: XCTestCase {

    @MainActor
    private func makeIsolatedEnvironment() throws -> (rootDir: URL, vaultDir: URL, store: MemoFlowStore) {
        let fm = FileManager.default
        let rootDir = fm.temporaryDirectory.appendingPathComponent("MemoFlowObsidianTest-\(UUID().uuidString)", isDirectory: true)
        let vaultDir = rootDir.appendingPathComponent("IsolatedVault", isDirectory: true)
        try fm.createDirectory(at: vaultDir, withIntermediateDirectories: true)

        let stateURL = rootDir.appendingPathComponent("state.json")
        let store = MemoFlowStore(customStorageURL: stateURL)
        store.bindObsidianVault(vaultDir)
        store.preferences.obsidianTargetSubfolder = "MemoFlow笔记"
        store.saveToDisk()
        return (rootDir, vaultDir, store)
    }

    private func listMarkdownFiles(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
            files.append(url)
        }
        return files
    }

    // MARK: - P0-1: 同一录音始终对应同一篇笔记

    @MainActor
    func testP0_1_ConsecutiveExportsAndTitleChangeUpdateSameSingleNote() throws {
        let (rootDir, vaultDir, store) = try makeIsolatedEnvironment()
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let rec = try XCTUnwrap(store.recordings.first)

        // 连续导出三次 -> 始终对应同一篇 .md 文件，不产生 -2、-3 副本
        let export1 = try store.saveNoteDirectlyToObsidian(for: rec.id)
        let export2 = try store.saveNoteDirectlyToObsidian(for: rec.id)
        let export3 = try store.saveNoteDirectlyToObsidian(for: rec.id)

        XCTAssertEqual(export1.fileURL.standardizedFileURL, export2.fileURL.standardizedFileURL)
        XCTAssertEqual(export2.fileURL.standardizedFileURL, export3.fileURL.standardizedFileURL)
        XCTAssertEqual(listMarkdownFiles(in: vaultDir).count, 1)

        // 修改标题后再次导出 -> 仍更新同一篇笔记，总文件数仍为 1
        let rev = try XCTUnwrap(store.currentRevision(for: rec.id))
        store.saveUserEditedNote(
            for: rec.id,
            newTitle: "全新重命名后的会议纪要标题",
            newContent: rev.content,
            projectName: "科研栏目"
        )
        let export4 = try store.saveNoteDirectlyToObsidian(for: rec.id)
        XCTAssertEqual(export4.fileURL.standardizedFileURL, export1.fileURL.standardizedFileURL)
        XCTAssertEqual(listMarkdownFiles(in: vaultDir).count, 1)

        let text = try String(contentsOf: export4.fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains("# 全新重命名后的会议纪要标题"))
        XCTAssertTrue(text.contains("recording_id: \"\(rec.id.uuidString)\""))
        XCTAssertTrue(text.contains("project: \"[[科研栏目]]\""))
    }

    @MainActor
    func testP0_1_ObsidianRenameAndFolderMoveRelocatesByRecordingId() throws {
        let (rootDir, vaultDir, store) = try makeIsolatedEnvironment()
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let rec = try XCTUnwrap(store.recordings.first)
        let export1 = try store.saveNoteDirectlyToObsidian(for: rec.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: export1.fileURL.path))

        // 模拟用户在 Obsidian 中将该笔记跨文件夹移动并重命名
        let archiveFolder = vaultDir.appendingPathComponent("work/深度归档", isDirectory: true)
        try FileManager.default.createDirectory(at: archiveFolder, withIntermediateDirectories: true)
        let movedURL = archiveFolder.appendingPathComponent("用户手改文件名.md")
        try FileManager.default.moveItem(at: export1.fileURL, to: movedURL)

        // 在 MemoFlow 更新总结后再次导出 -> 通过 recording_id 重新定位到新路径，不重建新文件
        var updatedContent = try XCTUnwrap(store.currentRevision(for: rec.id)).content
        updatedContent.summaryOrShortNote = "移动重命名后更新的新总结"
        store.saveUserEditedNote(
            for: rec.id,
            newTitle: rec.title,
            newContent: updatedContent,
            projectName: nil
        )

        let export2 = try store.saveNoteDirectlyToObsidian(for: rec.id)
        XCTAssertEqual(export2.fileURL.standardizedFileURL.resolvingSymlinksInPath(), movedURL.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(store.obsidianBindingsByRecording[rec.id]?.vaultRelativePath, "work/深度归档/用户手改文件名.md")
        XCTAssertEqual(listMarkdownFiles(in: vaultDir).count, 1)

        let updatedText = try String(contentsOf: movedURL, encoding: .utf8)
        XCTAssertTrue(updatedText.contains("移动重命名后更新的新总结"))
    }

    @MainActor
    func testP0_1_LegacyUnidentifiedNoteRequiresReviewAndSupportsAssociateOrSeparate() throws {
        // 场景 A：审阅后确认关联旧笔记（保留旧手写内容并写入 recording_id）
        do {
            let (rootDir, vaultDir, store) = try makeIsolatedEnvironment()
            defer { try? FileManager.default.removeItem(at: rootDir) }

            let rec = try XCTUnwrap(store.recordings.first)
            let rev = try XCTUnwrap(store.currentRevision(for: rec.id))
            let title = MarkdownExporterService.exportTitle(recording: rec, revision: rev)
            let legacyName = MarkdownExporterService.preferredFileName(recording: rec, title: title)

            let targetFolder = vaultDir.appendingPathComponent("MemoFlow笔记", isDirectory: true)
            try FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)
            let legacyURL = targetFolder.appendingPathComponent(legacyName)
            let legacyOriginalText = "# 历史手写笔记\n\n这里有我之前手写的宝贵段落与 [[重要双链]]。"
            try legacyOriginalText.write(to: legacyURL, atomically: true, encoding: .utf8)

            // 首次直接导出必须拒绝静默覆盖，并进入待确认状态
            XCTAssertThrowsError(try store.saveNoteDirectlyToObsidian(for: rec.id)) { error in
                guard case ObsidianSyncError.legacyNoteConfirmationRequired(let candidates) = error else {
                    XCTFail("Expected legacyNoteConfirmationRequired, got \(error)")
                    return
                }
                XCTAssertEqual(candidates, ["MemoFlow笔记/\(legacyName)"])
            }
            XCTAssertEqual(try String(contentsOf: legacyURL, encoding: .utf8), legacyOriginalText)
            XCTAssertEqual(store.obsidianBindingsByRecording[rec.id]?.status, .needsLegacyConfirmation)

            // 用户选择关联该历史笔记 -> 原有手写内容完整保留，且附加上 recording_id
            let associated = try store.associateLegacyObsidianNote(
                for: rec.id,
                relativePath: "MemoFlow笔记/\(legacyName)"
            )
            XCTAssertEqual(associated.fileURL.standardizedFileURL, legacyURL.standardizedFileURL)
            let mergedText = try String(contentsOf: legacyURL, encoding: .utf8)
            XCTAssertTrue(mergedText.contains("这里有我之前手写的宝贵段落与 [[重要双链]]。"))
            XCTAssertTrue(mergedText.contains("recording_id: \"\(rec.id.uuidString)\""))
            XCTAssertNotNil(store.obsidianBindingsByRecording[rec.id]?.lastBackupFilePath)
        }

        // 场景 B：审阅后选择另建独立笔记 -> 旧笔记丝毫不改，新笔记带短 ID 独立绑定
        do {
            let (rootDir, vaultDir, store) = try makeIsolatedEnvironment()
            defer { try? FileManager.default.removeItem(at: rootDir) }

            let rec = try XCTUnwrap(store.recordings.first)
            let rev = try XCTUnwrap(store.currentRevision(for: rec.id))
            let title = MarkdownExporterService.exportTitle(recording: rec, revision: rev)
            let legacyName = MarkdownExporterService.preferredFileName(recording: rec, title: title)

            let targetFolder = vaultDir.appendingPathComponent("MemoFlow笔记", isDirectory: true)
            try FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)
            let legacyURL = targetFolder.appendingPathComponent(legacyName)
            let legacyOriginalText = "完全独立的手写旧笔记"
            try legacyOriginalText.write(to: legacyURL, atomically: true, encoding: .utf8)

            XCTAssertThrowsError(try store.saveNoteDirectlyToObsidian(for: rec.id))
            let separate = try store.createSeparateObsidianNote(for: rec.id)
            XCTAssertNotEqual(separate.fileURL.standardizedFileURL, legacyURL.standardizedFileURL)
            XCTAssertEqual(try String(contentsOf: legacyURL, encoding: .utf8), legacyOriginalText)

            // 再次导出仍固定更新新建的那篇独立笔记
            let secondSeparateExport = try store.saveNoteDirectlyToObsidian(for: rec.id)
            XCTAssertEqual(secondSeparateExport.fileURL.standardizedFileURL, separate.fileURL.standardizedFileURL)
            XCTAssertEqual(listMarkdownFiles(in: vaultDir).count, 2)
        }
    }

    // MARK: - P0-2: 保护 Obsidian 中的手写内容、冲突检测与恢复

    @MainActor
    func testP0_2_PreservesUserHandwrittenSectionsTagsLinksAndCustomYAML() throws {
        let (rootDir, _, store) = try makeIsolatedEnvironment()
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let rec = try XCTUnwrap(store.recordings.first)
        let export1 = try store.saveNoteDirectlyToObsidian(for: rec.id)
        var textOnDisk = try String(contentsOf: export1.fileURL, encoding: .utf8)

        // 模拟用户在 Obsidian 中补充：
        // 1) 自定义 YAML 属性与自定义标签
        textOnDisk = textOnDisk.replacingOccurrences(
            of: "tags: [录音笔记, 会议]",
            with: "tags:\n  - 录音笔记\n  - 会议\n  - 深度复盘\n  - 模拟音频灵感\naliases: [周会复盘]\ncustom_rating: 5"
        )
        // 2) 在「个人补充」区写入手写段落、#标签与 [[Wiki 链接]]
        textOnDisk = textOnDisk.replacingOccurrences(
            of: "\(MarkdownExporterService.userSupplementStartMarker)\n\(MarkdownExporterService.userSupplementEndMarker)",
            with: """
            \(MarkdownExporterService.userSupplementStartMarker)
            会后补充：这段关于磁带机仪式感的讨论需要关联 [[Denon DR-F2 笔记]] #analog-audio
            第二段手写心得：保持克制，不堆砌功能。
            \(MarkdownExporterService.userSupplementEndMarker)
            """
        )
        // 3) 在文末额外手写一整节自由笔记
        textOnDisk += "\n## 我的会后自由手记\n这段完全在受控区块之外，引用 [[JBL L52 听感]]。\n"
        try textOnDisk.write(to: export1.fileURL, atomically: true, encoding: .utf8)

        // MemoFlow 重新整理生成全新摘要与要点，再次导出
        var newStructured = try XCTUnwrap(store.currentRevision(for: rec.id)).content
        newStructured.summaryOrShortNote = "第二轮重新整理后的全新核心摘要"
        newStructured.keyPoints = ["新增要点一", "新增要点二"]
        store.saveUserEditedNote(
            for: rec.id,
            newTitle: rec.title,
            newContent: newStructured,
            projectName: store.notesByRecording[rec.id]?.projectName
        )

        let export2 = try store.saveNoteDirectlyToObsidian(for: rec.id)
        let merged = try String(contentsOf: export2.fileURL, encoding: .utf8)

        // 验证 AI 摘要已更新，同时所有手写段落、标签、双链、自定义 YAML 均毫发无损
        XCTAssertTrue(merged.contains("第二轮重新整理后的全新核心摘要"))
        XCTAssertTrue(merged.contains("新增要点一"))
        XCTAssertTrue(merged.contains("深度复盘"))
        XCTAssertTrue(merged.contains("模拟音频灵感"))
        XCTAssertTrue(merged.contains("aliases: [周会复盘]"))
        XCTAssertTrue(merged.contains("custom_rating: 5"))
        XCTAssertTrue(merged.contains("[[Denon DR-F2 笔记]] #analog-audio"))
        XCTAssertTrue(merged.contains("第二段手写心得：保持克制，不堆砌功能。"))
        XCTAssertTrue(merged.contains("## 我的会后自由手记"))
        XCTAssertTrue(merged.contains("[[JBL L52 听感]]"))
        XCTAssertEqual(store.obsidianBindingsByRecording[rec.id]?.status, .synced)
    }

    @MainActor
    func testP0_2_DetectsTwoSidedConflictPreservesBothVersionsAndSupportsResolutionAndBackupRestore() throws {
        let (rootDir, _, store) = try makeIsolatedEnvironment()
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let rec = try XCTUnwrap(store.recordings.first)
        let export1 = try store.saveNoteDirectlyToObsidian(for: rec.id)

        // 用户直接在 Obsidian 修改了 AI 生成的 summary 受控区块内部文字
        let originalDisk = try String(contentsOf: export1.fileURL, encoding: .utf8)
        let userEditedDisk = ObsidianNoteSyncService.replaceManagedBlockContent(
            in: originalDisk,
            kind: .summary,
            newInnerContent: "## 一句话摘要\n这是用户在 Obsidian 直接手改润色后的摘要版本。"
        )
        try userEditedDisk.write(to: export1.fileURL, atomically: true, encoding: .utf8)

        // 1) 若 MemoFlow 未改动摘要而直接再次导出 -> 保留用户手改版，不误覆盖
        _ = try store.saveNoteDirectlyToObsidian(for: rec.id)
        let afterUnchangedExport = try String(contentsOf: export1.fileURL, encoding: .utf8)
        XCTAssertTrue(afterUnchangedExport.contains("这是用户在 Obsidian 直接手改润色后的摘要版本。"))
        XCTAssertEqual(store.obsidianBindingsByRecording[rec.id]?.conflicts.count, 0)

        // 2) MemoFlow 重新整理产生了新的 AI 摘要 -> 双方修改同一区域，触发冲突检测并同时保留双方版本
        var newContent = try XCTUnwrap(store.currentRevision(for: rec.id)).content
        newContent.summaryOrShortNote = "这是 MemoFlow 重新整理生成的第二版摘要。"
        store.saveUserEditedNote(
            for: rec.id,
            newTitle: rec.title,
            newContent: newContent,
            projectName: store.notesByRecording[rec.id]?.projectName
        )

        _ = try store.saveNoteDirectlyToObsidian(for: rec.id)
        let bindingWithConflict = try XCTUnwrap(store.obsidianBindingsByRecording[rec.id])
        XCTAssertEqual(bindingWithConflict.status, .hasConflict)
        XCTAssertEqual(bindingWithConflict.conflicts.map(\.blockKind), [.summary])
        XCTAssertNotNil(bindingWithConflict.lastBackupFilePath)

        let conflictMarkdown = try String(contentsOf: export1.fileURL, encoding: .utf8)
        XCTAssertTrue(conflictMarkdown.contains("这是用户在 Obsidian 直接手改润色后的摘要版本。"))
        XCTAssertTrue(conflictMarkdown.contains("这是 MemoFlow 重新整理生成的第二版摘要。"))

        // 3) 测试从写入前备份一键恢复 -> 恢复到冲突写入前的干净手改文件
        try store.restoreObsidianNoteFromBackup(for: rec.id)
        let restoredMarkdown = try String(contentsOf: export1.fileURL, encoding: .utf8)
        XCTAssertEqual(restoredMarkdown, userEditedDisk)
        XCTAssertEqual(store.obsidianBindingsByRecording[rec.id]?.status, .synced)

        // 4) 再次触发同区域冲突并测试用户选择「合并保留双方版本」
        // 先把基线恢复为初始版本指纹以模拟重新整理冲突
        var resetBinding = try XCTUnwrap(store.obsidianBindingsByRecording[rec.id])
        resetBinding.managedBlockDigests[ObsidianManagedBlockKind.summary.rawValue] = "stale_base_digest"
        store.obsidianBindingsByRecording[rec.id] = resetBinding

        _ = try store.saveNoteDirectlyToObsidian(for: rec.id)
        XCTAssertEqual(store.obsidianBindingsByRecording[rec.id]?.status, .hasConflict)

        try store.resolveObsidianConflict(for: rec.id, blockKind: .summary, choice: .keepBothMerged)
        XCTAssertEqual(store.obsidianBindingsByRecording[rec.id]?.status, .synced)
        XCTAssertTrue(store.obsidianBindingsByRecording[rec.id]?.conflicts.isEmpty == true)
        let resolvedText = try String(contentsOf: export1.fileURL, encoding: .utf8)
        XCTAssertFalse(resolvedText.contains("memoflow:conflict:summary"))
        XCTAssertTrue(resolvedText.contains("这是用户在 Obsidian 直接手改润色后的摘要版本。"))
        XCTAssertTrue(resolvedText.contains("这是 MemoFlow 重新整理生成的第二版摘要。"))
    }

    @MainActor
    func testP0_2_HandlesCloudNotDownloadedAuthExpiryAndConcurrentModification() throws {
        let (rootDir, _, store) = try makeIsolatedEnvironment()
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let rec = try XCTUnwrap(store.recordings.first)
        let export1 = try store.saveNoteDirectlyToObsidian(for: rec.id)
        let relPath = try XCTUnwrap(store.obsidianBindingsByRecording[rec.id]?.vaultRelativePath)

        // 1) 模拟 iCloud 文件尚未下载到本机 -> 拒绝盲目覆盖并标记 cloudNotDownloaded
        store.obsidianSyncService.simulatedUndownloadedRelativePaths.insert(relPath)
        XCTAssertThrowsError(try store.saveNoteDirectlyToObsidian(for: rec.id)) { err in
            XCTAssertEqual(err as? ObsidianSyncError, .cloudFileNotDownloaded(relativePath: relPath))
        }
        XCTAssertEqual(store.obsidianBindingsByRecording[rec.id]?.status, .cloudNotDownloaded)
        store.obsidianSyncService.simulatedUndownloadedRelativePaths.removeAll()

        // 2) 模拟合并过程中发生单次外部并发追加手写内容 -> 自动重读合并，外部追加内容不丢失
        store.obsidianSyncService.onBeforeAtomicWriteHook = { fileURL in
            if var current = try? String(contentsOf: fileURL, encoding: .utf8) {
                current += "\n并发时刻用户在外部编辑器刚写下的一句话。\n"
                try? current.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
        _ = try store.saveNoteDirectlyToObsidian(for: rec.id)
        store.obsidianSyncService.onBeforeAtomicWriteHook = nil
        let afterConcurrent = try String(contentsOf: export1.fileURL, encoding: .utf8)
        XCTAssertTrue(afterConcurrent.contains("并发时刻用户在外部编辑器刚写下的一句话。"))

        // 3) 模拟书签授权失效 -> 明确捕获 authorizationExpired 状态
        let validBookmark = store.preferences.obsidianVaultBookmark
        store.preferences.obsidianVaultBookmark = Data("corrupted-bookmark".utf8)
        XCTAssertThrowsError(try store.saveNoteDirectlyToObsidian(for: rec.id))
        XCTAssertEqual(store.obsidianBindingsByRecording[rec.id]?.status, .authorizationExpired)
        store.preferences.obsidianVaultBookmark = validBookmark
    }

    // MARK: - P1-3: 双向打开笔记与录音、时间戳跳转与异常边界

    @MainActor
    func testP1_3_BidirectionalNavigationClickableTimestampsAndEdgeCases() throws {
        let (rootDir, vaultDir, store) = try makeIsolatedEnvironment()
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let rec = try XCTUnwrap(store.recordings.first)
        let segs = try XCTUnwrap(store.segmentsByRecording[rec.id])
        XCTAssertFalse(segs.isEmpty)

        // 添加书签与高亮批注后导出到 Obsidian
        store.addBookmarkMark(recordingId: rec.id, atMs: 5000, quote: "关键书签原话", note: "跟进硬件调试", kind: "bookmark")
        store.setHighlight(recordingId: rec.id, segment: segs[0], note: "重点高亮核对")

        let exported = try store.saveNoteDirectlyToObsidian(for: rec.id)
        let md = try String(contentsOf: exported.fileURL, encoding: .utf8)

        // 1) 验证原话、章节、高亮、书签均带可点击 memoflow:// 时间戳链接
        XCTAssertTrue(md.contains("memoflow://recording/\(rec.id.uuidString)?startMs="))
        XCTAssertTrue(md.contains("memoflow://recording/\(rec.id.uuidString)?startMs=5000"))

        // 2) 点击一条原话深链 -> 打开对应录音并精确定位
        let targetJumpURL = try XCTUnwrap(
            MemoFlowDeepLink.recordingURL(recordingId: rec.id, startMs: 6000, endMs: 12000)
        )
        let jumpOutcome = store.handleIncomingURL(targetJumpURL)
        XCTAssertEqual(jumpOutcome, .opened(recordingId: rec.id, targetMs: 6000, isEstimated: false))
        XCTAssertEqual(store.activeDeepLinkRequest?.recordingId, rec.id)
        XCTAssertEqual(store.activeDeepLinkRequest?.targetStartMs, 6000)
        XCTAssertEqual(store.activeDeepLinkRequest?.targetEndMs, 12000)
        store.audioService.stopPlayback()

        // 3) 从 MemoFlow 打开固定 Obsidian 笔记（含笔记被重命名/移动后的重定位）
        let movedDir = vaultDir.appendingPathComponent("Archive/2026", isDirectory: true)
        try FileManager.default.createDirectory(at: movedDir, withIntermediateDirectories: true)
        let movedFile = movedDir.appendingPathComponent("双向跳转重命名测试.md")
        try FileManager.default.moveItem(at: exported.fileURL, to: movedFile)

        let obsOpenURL = try store.openBoundObsidianNoteURL(for: rec.id)
        XCTAssertEqual(obsOpenURL.scheme, "obsidian")
        XCTAssertTrue(obsOpenURL.absoluteString.contains("Archive%2F2026%2F") || obsOpenURL.absoluteString.contains("Archive/2026/"))
        XCTAssertEqual(store.obsidianBindingsByRecording[rec.id]?.vaultRelativePath, "Archive/2026/双向跳转重命名测试.md")

        // 4) 异常边界：录音缺失、时间越界、真实音频缺失
        let missingId = UUID()
        let missingURL = try XCTUnwrap(MemoFlowDeepLink.recordingURL(recordingId: missingId, startMs: 1000))
        XCTAssertEqual(store.handleIncomingURL(missingURL), .recordingNotFound(recordingId: missingId))
        XCTAssertNotNil(store.activeDeepLinkAlert)

        let outOfBoundsURL = try XCTUnwrap(MemoFlowDeepLink.recordingURL(recordingId: rec.id, startMs: 99_999_000))
        let clampedOutcome = store.handleIncomingURL(outOfBoundsURL)
        if case .clampedOutOfBounds(let rId, let reqMs, let clampedMs) = clampedOutcome {
            XCTAssertEqual(rId, rec.id)
            XCTAssertEqual(reqMs, 99_999_000)
            XCTAssertLessThanOrEqual(clampedMs, Int(rec.duration * 1000))
        } else {
            XCTFail("Expected clampedOutOfBounds, got \(clampedOutcome)")
        }
        store.audioService.stopPlayback()

        // 模拟非 demo 真实录音缺失本地音频文件 -> 不伪造假音频，明确提示缺失
        let missingAudioRecId = UUID()
        let missingAudioRec = Recording(
            id: missingAudioRecId,
            title: "缺失本地音频的录音",
            duration: 30,
            localAudioFileName: "nonexistent_real_audio_\(missingAudioRecId.uuidString).m4a"
        )
        store.recordings.insert(missingAudioRec, at: 0)
        let missingAudioURL = try XCTUnwrap(MemoFlowDeepLink.recordingURL(recordingId: missingAudioRecId, startMs: 3000))
        let audioMissingOutcome = store.handleIncomingURL(missingAudioURL)
        if case .audioMissingOnDevice(let rId, let tMs, _) = audioMissingOutcome {
            XCTAssertEqual(rId, missingAudioRecId)
            XCTAssertEqual(tMs, 3000)
        } else {
            XCTFail("Expected audioMissingOnDevice, got \(audioMissingOutcome)")
        }

        // 5) 估算时间戳标明「约」，不可核验来源绝不伪造深链
        let estimatedBadge = MarkdownExporterService.formatVerifiableTimestampLink(
            recording: rec,
            startMs: 15000,
            endMs: 20000,
            isEstimated: true,
            rangeDisplay: true
        )
        XCTAssertTrue(estimatedBadge.contains("[约 00:00:15 - 00:00:20](memoflow://recording/\(rec.id.uuidString)?startMs=15000&endMs=20000&estimated=1)"))

        let unverifiableRec = Recording(title: "无音频源", duration: 10, localAudioFileName: "")
        let unverifiableBadge = MarkdownExporterService.formatVerifiableTimestampLink(
            recording: unverifiableRec,
            startMs: 5000,
            isEstimated: false,
            rangeDisplay: false
        )
        XCTAssertTrue(unverifiableBadge.contains("来源待核验"))
        XCTAssertFalse(unverifiableBadge.contains("memoflow://"))
    }

    // MARK: - P1-4: 完善导出内容与版本标识

    @MainActor
    func testP1_4_ExportedProvenanceReviewStatusProjectWikiLinkAndMarks() throws {
        let (rootDir, _, store) = try makeIsolatedEnvironment()
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let rec = try XCTUnwrap(store.recordings.first)
        let segs = try XCTUnwrap(store.segmentsByRecording[rec.id])

        // 关联项目并添加手动高亮批注 + 录制书签
        let rev0 = try XCTUnwrap(store.currentRevision(for: rec.id))
        store.saveUserEditedNote(
            for: rec.id,
            newTitle: rec.title,
            newContent: rev0.content,
            projectName: "[[模拟器材调校]]"
        )
        store.setHighlight(recordingId: rec.id, segment: segs[0], note: "此处需要核对偏磁参数")
        store.addBookmarkMark(recordingId: rec.id, atMs: 8000, quote: "中频密度表现", note: "录制时打点书签", kind: "bookmark")

        // 1) 默认未校对状态导出：包含完整元数据、双链项目、书签批注来源时间戳与机器稿提示
        let export1 = try store.saveNoteDirectlyToObsidian(for: rec.id)
        let mdUnreviewed = try String(contentsOf: export1.fileURL, encoding: .utf8)
        XCTAssertTrue(mdUnreviewed.contains("recording_id: \"\(rec.id.uuidString)\""))
        XCTAssertTrue(mdUnreviewed.contains("timezone: \"\(rec.recordedTimeZoneIdentifier)\""))
        XCTAssertTrue(mdUnreviewed.contains("duration: \"\(TimeFormatting.formatDuration(rec.duration))\""))
        XCTAssertTrue(mdUnreviewed.contains("project: \"[[模拟器材调校]]\""))
        XCTAssertTrue(
            mdUnreviewed.contains("transcript_review_status: \"legacy_unverified\"") ||
            mdUnreviewed.contains("transcript_review_status: \"machine_unreviewed\"")
        )
        XCTAssertTrue(mdUnreviewed.contains("此处需要核对偏磁参数"))
        XCTAssertTrue(mdUnreviewed.contains("录制时打点书签"))
        XCTAssertTrue(mdUnreviewed.contains("memoflow://recording/\(rec.id.uuidString)?startMs=8000"))

        // 2) 用户纠正关联项目并标记逐字稿已人工校对
        store.setTranscriptReviewed(recordingId: rec.id, reviewed: true)
        let rev1 = try XCTUnwrap(store.currentRevision(for: rec.id))
        store.saveUserEditedNote(
            for: rec.id,
            newTitle: rec.title,
            newContent: rev1.content,
            projectName: "黑胶与磁带归档"
        )
        let export2 = try store.saveNoteDirectlyToObsidian(for: rec.id)
        let mdReviewed = try String(contentsOf: export2.fileURL, encoding: .utf8)
        XCTAssertTrue(mdReviewed.contains("project: \"[[黑胶与磁带归档]]\""))
        XCTAssertTrue(mdReviewed.contains("transcript_review_status: \"reviewed\""))
        XCTAssertTrue(mdReviewed.contains("逐字稿：已人工校对"))
        XCTAssertTrue(mdReviewed.contains("本篇逐字稿已完成人工校对"))

        // 3) 模拟逐字稿重新生成后尚未重新生成 AI 摘要 -> 明确标识「摘要仍基于旧版逐字稿」
        var staleSegs = segs
        staleSegs[0].text = "重新转写后的全新逐字稿首句内容"
        store.segmentsByRecording[rec.id] = staleSegs
        store.setTranscriptReviewed(recordingId: rec.id, reviewed: false)

        let export3 = try store.saveNoteDirectlyToObsidian(for: rec.id)
        let mdStale = try String(contentsOf: export3.fileURL, encoding: .utf8)
        XCTAssertTrue(mdStale.contains("summary_alignment_status: \"stale_against_newer_transcript\""))
        XCTAssertTrue(mdStale.contains("摘要仍基于旧版逐字稿"))
    }

    // MARK: - P1-5: 增强历史笔记检索、来源引用、三方事实隔离与个人记忆审阅授权

    @MainActor
    func testP1_5_SelectableFoldersHistoricalBoundaryGroundedQAAndPersonalMemoryConsent() async throws {
        let (rootDir, vaultDir, store) = try makeIsolatedEnvironment()
        defer { try? FileManager.default.removeItem(at: rootDir) }

        // 准备两个不同子文件夹的历史笔记
        let projectsDir = vaultDir.appendingPathComponent("Projects", isDirectory: true)
        let personalDir = vaultDir.appendingPathComponent("PersonalDiary", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: personalDir, withIntermediateDirectories: true)

        let historicalRecId = UUID()
        let projectNote = """
        ---
        recording_id: "\(historicalRecId.uuidString)"
        ---
        # Denon 卡座维护记录
        上次校准了磁头方位角，计划下周三采购新压带轮。
        **[00:01:20]** 测量走带抖晃率在正常范围。
        """
        try projectNote.write(to: projectsDir.appendingPathComponent("Denon卡座维护.md"), atomically: true, encoding: .utf8)

        let diaryNote = """
        # 私人随笔
        私密日记专属词条不应被限定目录外的检索读取。
        """
        try diaryNote.write(to: personalDir.appendingPathComponent("私人随笔.md"), atomically: true, encoding: .utf8)

        // 1) 限定只检索 Projects 文件夹
        store.preferences.knowledgeContextEnabled = true
        store.preferences.knowledgeIncludedFolders = ["Projects"]
        store.saveToDisk()
        await store.refreshKnowledge()

        let isolatedKnowledgeService = ObsidianKnowledgeService()
        let projectHits = try await isolatedKnowledgeService.refresh(
            preferences: store.preferences,
            query: "Denon 压带轮 抖晃率"
        ).references
        XCTAssertEqual(projectHits.count, 1)
        XCTAssertEqual(projectHits.first?.path, "Projects/Denon卡座维护.md")
        XCTAssertEqual(projectHits.first?.recordingId, historicalRecId)
        XCTAssertEqual(projectHits.first?.timestampMs, 80_000)

        let diaryHits = try await isolatedKnowledgeService.refresh(
            preferences: store.preferences,
            query: "私密日记专属词条"
        ).references
        XCTAssertTrue(diaryHits.isEmpty, "未选入检索范围的文件夹不得被索引")

        // 2) 验证历史笔记中的计划不会变成当前录音的新承诺/待办，且三类信息严格区分
        let newRecId = UUID()
        let newRec = Recording(
            id: newRecId,
            title: "Denon 听感记录",
            duration: 10,
            localAudioFileName: "demo_denon_test.wav"
        )
        let currentSegments = [
            TranscriptSegment(
                id: "seg_curr_1",
                recordingId: newRecId,
                startMs: 0,
                endMs: 6000,
                text: "今天只记录一下 Denon 卡座播放磁带的听感很温润，没有任何新采购任务。",
                speakerName: "我"
            )
        ]
        var localPrefs = store.preferences
        localPrefs.llmBaseURL = ""
        localPrefs.llmModelName = "local-heuristic"
        let organized = try await ASRAndLLMService.shared.organizeTranscript(
            recording: newRec,
            segments: currentSegments,
            requestedMode: .meetingNote,
            revisionId: UUID(),
            preferences: localPrefs,
            llmAPIKey: nil,
            knowledgeReferences: projectHits,
            confirmedMemories: []
        )
        XCTAssertTrue(
            organized.actionDrafts.allSatisfy { !$0.description.contains("采购新压带轮") },
            "历史笔记中的事项绝不能自动变成当前录音的新待办"
        )
        XCTAssertFalse(organized.noteContent.historicalContextNotes.isEmpty)

        // 3) 跨笔记检索问答：必须引用实际笔记路径与录音时间戳，并如实说明关键词检索能力范围
        let qa = await store.askGroundedQuestion("Denon 卡座抖晃率")
        XCTAssertFalse(qa.citations.isEmpty)
        XCTAssertEqual(qa.citations.first?.noteRelativePath, "Projects/Denon卡座维护.md")
        XCTAssertEqual(qa.citations.first?.recordingId, historicalRecId)
        XCTAssertEqual(qa.citations.first?.startMs, 80_000)
        XCTAssertTrue(qa.capabilityDisclosure.contains("关键词"))

        // 4) 个人记忆：审阅、确认、编辑、删除 + 云端发送独立授权控制
        let addedPending = try XCTUnwrap(
            store.addPersonalMemory(
                category: .term,
                key: "DR-F2",
                value: "Denon 三磁头卡座",
                sourceRecordingId: newRecId,
                status: .pendingReview
            )
        )
        XCTAssertEqual(addedPending.status, .pendingReview)
        store.confirmPersonalMemory(addedPending.id)
        XCTAssertEqual(store.personalMemories.first(where: { $0.id == addedPending.id })?.status, .confirmed)

        store.updatePersonalMemory(
            id: addedPending.id,
            category: .term,
            key: "Denon DR-F2",
            value: "主力水平进带磁带卡座"
        )
        XCTAssertEqual(store.personalMemories.first(where: { $0.id == addedPending.id })?.key, "Denon DR-F2")

        store.deletePersonalMemory(addedPending.id)
        XCTAssertFalse(store.personalMemories.contains(where: { $0.id == addedPending.id }))

        // 验证默认关闭云端发送授权，且断开知识库时自动撤销本地读取与云端发送授权
        store.preferences.allowSendingKnowledgeToCloudLLM = true
        store.disconnectObsidianVault()
        XCTAssertFalse(store.preferences.knowledgeContextEnabled)
        XCTAssertFalse(store.preferences.allowSendingKnowledgeToCloudLLM)
    }
}
