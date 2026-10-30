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
}
