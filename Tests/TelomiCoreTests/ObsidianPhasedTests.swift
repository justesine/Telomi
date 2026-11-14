import XCTest
@testable import TelomiCore

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

        // 1) 验证原话、章节、高亮、书签均带可点击 telomi:// (或兼容 memoflow://) 时间戳链接
        XCTAssertTrue(md.contains("://recording/\(rec.id.uuidString)?startMs="))
        XCTAssertTrue(md.contains("://recording/\(rec.id.uuidString)?startMs=5000"))

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
        XCTAssertTrue(estimatedBadge.contains("[约 00:00:15 - 00:00:20](") && estimatedBadge.contains("://recording/\(rec.id.uuidString)?startMs=15000&endMs=20000&estimated=1)"))

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
        XCTAssertTrue(mdUnreviewed.contains("://recording/\(rec.id.uuidString)?startMs=8000"))

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

    // MARK: - P2-6: 有限字段的双向同步（个人补充、手动标签、项目关联、批注书签 + 重命名/移动 + 防循环 + 冲突 + 删笔记保原音频）

    @MainActor
    func testP2_6_BidirectionalScopedSyncRenameMoveAntiLoopAndConflictResolution() throws {
        let (rootDir, vaultDir, store) = try makeIsolatedEnvironment()
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let rec = try XCTUnwrap(store.recordings.first)
        let rev = try XCTUnwrap(store.currentRevision(for: rec.id))

        // 初始准备四个受控字段并首次导出
        store.saveUserEditedNote(
            for: rec.id,
            newTitle: rec.title,
            newContent: rev.content,
            projectName: "科研栏目首期",
            userSupplement: "MemoFlow 初始手记补充。",
            manualTags: ["采访"]
        )
        store.addBookmarkMark(
            recordingId: rec.id,
            atMs: 5000,
            quote: "首期围绕真实研究过程展开",
            note: "初始批注",
            kind: "highlight"
        )
        let exported = try store.saveNoteDirectlyToObsidian(for: rec.id)

        // 1. Obsidian -> MemoFlow 拉取（修改个人补充、新增标签、改关联项目、改批注并手写新增一条书签）
        var diskMarkdown = try String(contentsOf: exported.fileURL, encoding: .utf8)
        diskMarkdown = diskMarkdown.replacingOccurrences(
            of: "MemoFlow 初始手记补充。",
            with: "Obsidian 中补充的磁带机校准细节。"
        )
        diskMarkdown = diskMarkdown.replacingOccurrences(
            of: ", 采访]",
            with: ", 采访, 模拟器材]"
        )
        diskMarkdown = diskMarkdown.replacingOccurrences(
            of: "\"[[科研栏目首期]]\"",
            with: "\"[[磁带修复项目]]\""
        )
        diskMarkdown = diskMarkdown.replacingOccurrences(
            of: "  - 批注：初始批注",
            with: "  - 批注：Obsidian 更新后的批注\n- [00:12] 手写新增方位角书签\n  - 批注：需用示波器复核"
        )
        try Data(diskMarkdown.utf8).write(to: exported.fileURL, options: .atomic)
        let shaBeforePull = ObsidianNoteSyncService.sha256Hex(of: try Data(contentsOf: exported.fileURL))

        let pullOutcome = try XCTUnwrap(try store.syncScopedFieldsWithObsidian(for: rec.id))
        XCTAssertTrue(pullOutcome.didPullToMemoFlow)
        XCTAssertFalse(pullOutcome.didWriteToDisk, "仅从 Obsidian 拉取变更时不应重写磁盘，防止文件监听死循环")

        let shaAfterPull = ObsidianNoteSyncService.sha256Hex(of: try Data(contentsOf: exported.fileURL))
        XCTAssertEqual(shaBeforePull, shaAfterPull, "拉取后磁盘文件 SHA-256 必须保持不变")

        let pulledNote = try XCTUnwrap(store.notesByRecording[rec.id])
        XCTAssertEqual(pulledNote.userSupplement, "Obsidian 中补充的磁带机校准细节。")
        XCTAssertEqual(Set(pulledNote.manualTags), Set(["采访", "模拟器材"]))
        XCTAssertEqual(pulledNote.projectName, "磁带修复项目")

        let pulledMarks = try XCTUnwrap(store.recordings.first(where: { $0.id == rec.id })?.marks)
        XCTAssertEqual(pulledMarks.count, 2)
        XCTAssertTrue(pulledMarks.contains(where: { $0.note == "Obsidian 更新后的批注" }))
        XCTAssertTrue(pulledMarks.contains(where: { $0.startMs == 12_000 && $0.quote.contains("手写新增方位角书签") && $0.note == "需用示波器复核" }))

        // 2. 防循环水位线幂等性验证：连续再次同步不产生任何读写
        let noop1 = try XCTUnwrap(try store.syncScopedFieldsWithObsidian(for: rec.id))
        let noop2 = try XCTUnwrap(try store.syncScopedFieldsWithObsidian(for: rec.id))
        XCTAssertFalse(noop1.didPullToMemoFlow)
        XCTAssertFalse(noop1.didWriteToDisk)
        XCTAssertFalse(noop2.didPullToMemoFlow)
        XCTAssertFalse(noop2.didWriteToDisk)

        // 3. 在 Obsidian 重命名并跨目录移动笔记 + 在 MemoFlow 修改四个字段 -> 推送回移动后的同一篇笔记
        let movedDir = vaultDir.appendingPathComponent("归档复盘", isDirectory: true)
        try FileManager.default.createDirectory(at: movedDir, withIntermediateDirectories: true)
        let movedURL = movedDir.appendingPathComponent("重命名后的双向同步笔记.md")
        try FileManager.default.moveItem(at: exported.fileURL, to: movedURL)

        let latestRev = try XCTUnwrap(store.currentRevision(for: rec.id))
        store.saveUserEditedNote(
            for: rec.id,
            newTitle: rec.title,
            newContent: latestRev.content,
            projectName: "模拟器材志",
            userSupplement: "MemoFlow 端跟进补充的新段落。",
            manualTags: ["模拟器材", "终审"]
        )
        store.addBookmarkMark(
            recordingId: rec.id,
            atMs: 25_000,
            quote: "新增第三条书签",
            note: "MemoFlow 新增标记",
            kind: "bookmark"
        )

        let pushOutcome = try XCTUnwrap(try store.syncScopedFieldsWithObsidian(for: rec.id))
        XCTAssertNotNil(pushOutcome.relocatedFromOldPath)
        XCTAssertEqual(pushOutcome.binding.vaultRelativePath, "归档复盘/重命名后的双向同步笔记.md")
        XCTAssertTrue(pushOutcome.didWriteToDisk)

        let pushedText = try String(contentsOf: movedURL, encoding: .utf8)
        XCTAssertTrue(pushedText.contains("MemoFlow 端跟进补充的新段落。"))
        XCTAssertTrue(pushedText.contains("终审"))
        XCTAssertFalse(pushedText.contains("采访"), "在 MemoFlow 移除的手动标签应同步在 Obsidian 移除")
        XCTAssertTrue(pushedText.contains("[[模拟器材志]]"))
        XCTAssertTrue(pushedText.contains("MemoFlow 新增标记"))

        // 4. 双方同时修改同一受控字段（userSupplement） -> 检测冲突保留双方快照 -> 合并解决冲突
        let revBeforeConflict = try XCTUnwrap(store.currentRevision(for: rec.id))
        store.saveUserEditedNote(
            for: rec.id,
            newTitle: rec.title,
            newContent: revBeforeConflict.content,
            projectName: "模拟器材志",
            userSupplement: "MemoFlow 并发修改的补充版本"
        )
        let concurrentDisk = pushedText.replacingOccurrences(
            of: "MemoFlow 端跟进补充的新段落。",
            with: "Obsidian 并发修改的补充版本"
        )
        try Data(concurrentDisk.utf8).write(to: movedURL, options: .atomic)

        let conflictOutcome = try XCTUnwrap(try store.syncScopedFieldsWithObsidian(for: rec.id))
        XCTAssertEqual(conflictOutcome.binding.status, .hasConflict)
        XCTAssertTrue(conflictOutcome.binding.scopedFieldConflicts.contains(where: { $0.field == .userSupplement }))

        try store.resolveScopedFieldConflict(
            for: rec.id,
            field: .userSupplement,
            choice: .keepBothMerged
        )
        let resolvedBinding = try XCTUnwrap(store.obsidianBindingsByRecording[rec.id])
        XCTAssertTrue(resolvedBinding.scopedFieldConflicts.isEmpty)
        XCTAssertEqual(resolvedBinding.status, .synced)

        let mergedNote = try XCTUnwrap(store.notesByRecording[rec.id])
        XCTAssertTrue(mergedNote.userSupplement.contains("Obsidian 并发修改的补充版本"))
        XCTAssertTrue(mergedNote.userSupplement.contains("MemoFlow 并发修改的补充版本"))

        let mergedDiskText = try String(contentsOf: movedURL, encoding: .utf8)
        XCTAssertTrue(mergedDiskText.contains("Obsidian 并发修改的补充版本"))
        XCTAssertTrue(mergedDiskText.contains("MemoFlow 并发修改的补充版本"))
    }

    @MainActor
    func testP2_6_DeletingObsidianNoteMarksMissingAndNeverDeletesOriginalAudio() throws {
        let (rootDir, _, store) = try makeIsolatedEnvironment()
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let customId = UUID()
        let customFileName = "rec_\(customId.uuidString).wav"
        let audioURL = store.audioService.ensurePlayableDemoAudioFile(named: customFileName, durationSeconds: 8)
        let originalAudioData = try Data(contentsOf: audioURL)

        store.handleFinishedRecording(
            id: customId,
            fileName: customFileName,
            createdAt: Date(),
            duration: 8,
            selectedMode: .quickNote,
            isNetworkAvailable: false
        )
        let segs = [TranscriptSegment(id: "s1", recordingId: customId, startMs: 0, endMs: 8000, text: "删除笔记绝不能影响原音频。")]
        store.segmentsByRecording[customId] = segs
        let revId = UUID()
        let out = ASRAndLLMService.shared.organizeLocallyWithHeuristics(
            recording: try XCTUnwrap(store.recordings.first(where: { $0.id == customId })),
            segments: segs,
            requestedMode: .quickNote,
            revisionId: revId,
            preferences: store.preferences
        )
        store.applyOrganizationOutput(out, for: customId, requestedMode: .quickNote, revisionId: revId)

        let exported = try store.saveNoteDirectlyToObsidian(for: customId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.fileURL.path))

        // 用户在 Obsidian 中删除了这篇 .md 笔记
        try FileManager.default.removeItem(at: exported.fileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exported.fileURL.path))

        let outcome = try XCTUnwrap(try store.syncScopedFieldsWithObsidian(for: customId))
        XCTAssertTrue(outcome.noteWasDeletedInVault)
        XCTAssertEqual(outcome.binding.status, .missingInVault)

        // 验收：本地录音条目、笔记结构与磁盘原音频 100% 完好无损
        XCTAssertTrue(store.recordings.contains(where: { $0.id == customId }))
        XCTAssertNotNil(store.notesByRecording[customId])
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertEqual(try Data(contentsOf: audioURL), originalAudioData)
    }

    // MARK: - P2-7: iPhone 与 Mac 跨设备音频可用性（区分笔记已同步与音频已同步、杜绝绝对路径、未同步提示与附件回听）

    @MainActor
    func testP2_7_CrossDeviceAudioAvailabilityRelativeAttachmentAndMissingAudioHandling() throws {
        let fm = FileManager.default
        let rootDir = fm.temporaryDirectory.appendingPathComponent("MemoFlowCrossDeviceTest-\(UUID().uuidString)", isDirectory: true)
        let sharedVaultDir = rootDir.appendingPathComponent("SharedICloudVault", isDirectory: true)
        let macDir = rootDir.appendingPathComponent("MacDevice", isDirectory: true)
        let iphoneDir = rootDir.appendingPathComponent("iPhoneDevice", isDirectory: true)
        try fm.createDirectory(at: sharedVaultDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: macDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: iphoneDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: rootDir) }

        let macStore = MemoFlowStore(customStorageURL: macDir.appendingPathComponent("mac_state.json"))
        macStore.bindObsidianVault(sharedVaultDir)

        let iphoneStore = MemoFlowStore(customStorageURL: iphoneDir.appendingPathComponent("iphone_state.json"))
        // 清空 iPhone 侧默认演示种子，模拟一台尚未收到此录音的独立设备
        iphoneStore.recordings.removeAll()
        iphoneStore.notesByRecording.removeAll()
        iphoneStore.revisionsByNote.removeAll()
        iphoneStore.segmentsByRecording.removeAll()
        iphoneStore.bindObsidianVault(sharedVaultDir)

        // 在 Mac 侧创建一条真实本地音频记录（非 demo_ 前缀）
        let recId = UUID()
        let localFileName = "rec_\(recId.uuidString).wav"
        let macAudioURL = macStore.audioService.ensurePlayableDemoAudioFile(named: localFileName, durationSeconds: 10)
        XCTAssertTrue(fm.fileExists(atPath: macAudioURL.path))

        macStore.handleFinishedRecording(
            id: recId,
            fileName: localFileName,
            createdAt: Date(),
            duration: 10,
            selectedMode: .quickNote,
            isNetworkAvailable: false
        )
        let segs = [
            TranscriptSegment(id: "seg_1", recordingId: recId, startMs: 0, endMs: 5000, text: "第一段跨端音频验证。", speakerName: "我"),
            TranscriptSegment(id: "seg_2", recordingId: recId, startMs: 5000, endMs: 10000, text: "第二段跨端定位回听。", speakerName: "我")
        ]
        macStore.segmentsByRecording[recId] = segs
        let revId = UUID()
        let org = ASRAndLLMService.shared.organizeLocallyWithHeuristics(
            recording: try XCTUnwrap(macStore.recordings.first(where: { $0.id == recId })),
            segments: segs,
            requestedMode: .quickNote,
            revisionId: revId,
            preferences: macStore.preferences
        )
        macStore.applyOrganizationOutput(org, for: recId, requestedMode: .quickNote, revisionId: revId)

        // 场景 A：默认 localOnly 导出笔记 -> 笔记已同步，但音频未同步到 iPhone
        macStore.preferences.audioSyncMode = .localOnly
        let exportedLocalOnly = try macStore.saveNoteDirectlyToObsidian(for: recId)
        let mdLocalOnly = try String(contentsOf: exportedLocalOnly.fileURL, encoding: .utf8)
        XCTAssertTrue(mdLocalOnly.contains("audio_sync_status: \"local_only\""))
        XCTAssertFalse(mdLocalOnly.contains("/Users/"), "导出的笔记严禁包含仅在 Mac 有效的绝对路径")
        XCTAssertFalse(mdLocalOnly.contains(rootDir.path), "导出的笔记严禁包含宿主机临时目录绝对路径")

        let hydratedCount = try iphoneStore.hydrateMissingRecordingsFromVault()
        XCTAssertEqual(hydratedCount, 1)
        let iphoneRecBeforeAudio = try XCTUnwrap(iphoneStore.recordings.first(where: { $0.id == recId }))
        let overviewBefore = iphoneStore.syncOverview(for: iphoneRecBeforeAudio)
        XCTAssertTrue(overviewBefore.isNoteSynced, "应识别为「笔记已同步」")
        XCTAssertEqual(overviewBefore.noteBadgeTitle, "笔记已同步")
        XCTAssertFalse(overviewBefore.audioState.isPlayableNow, "音频尚未到达时不能误报为可播")
        XCTAssertFalse(overviewBefore.audioState.isAudioSyncedAcrossDevices, "应明确区分笔记已同步与音频未同步")
        XCTAssertEqual(overviewBefore.audioState.badgeTitle, "音频未到达当前设备")

        let deepLinkURL = try XCTUnwrap(MemoFlowDeepLink.recordingURL(recordingId: recId, startMs: 5000, endMs: 9000))
        let missingAudioOutcome = iphoneStore.handleIncomingURL(deepLinkURL)
        if case .audioMissingOnDevice(let id, _, let message) = missingAudioOutcome {
            XCTAssertEqual(id, recId)
            XCTAssertTrue(message.contains("笔记已同步"), "音频未到达时必须明确告知笔记已同步而原音频未到达")
        } else {
            XCTFail("Expected .audioMissingOnDevice when audio has not synced to iPhone, got \(missingAudioOutcome)")
        }

        // 场景 B：在 Mac 侧同步音频副本到笔记库相对附件目录
        let relAudioPath = try macStore.syncAudioAttachmentToVault(for: recId)
        XCTAssertEqual(relAudioPath, "MemoFlow笔记/Attachments/rec_\(recId.uuidString).wav")
        XCTAssertFalse(relAudioPath.hasPrefix("/"))

        let mdWithAttachment = try String(contentsOf: exportedLocalOnly.fileURL, encoding: .utf8)
        XCTAssertTrue(mdWithAttachment.contains("audio_sync_status: \"synced_in_vault\""))
        XCTAssertTrue(mdWithAttachment.contains("audio_attachment: \"\(relAudioPath)\""))
        XCTAssertTrue(mdWithAttachment.contains("![[\(relAudioPath)]]"))
        XCTAssertFalse(mdWithAttachment.contains("/Users/"), "同步附件后仍严禁写入任何 Mac 绝对路径")

        // 模拟 iPhone 上笔记已更新，但音频附件在 iCloud 尚未下载完成
        _ = try iphoneStore.syncScopedFieldsWithObsidian(for: recId)
        iphoneStore.obsidianSyncService.simulatedUndownloadedRelativePaths.insert(relAudioPath)
        let iphoneRecPendingCloud = try XCTUnwrap(iphoneStore.recordings.first(where: { $0.id == recId }))
        let overviewCloudPending = iphoneStore.syncOverview(for: iphoneRecPendingCloud)
        XCTAssertEqual(overviewCloudPending.audioState, .cloudNotDownloaded(relativePath: relAudioPath))
        XCTAssertFalse(iphoneStore.playRecording(iphoneRecPendingCloud, startMs: 5000))

        // 模拟 iCloud 音频附件下载完成 -> iPhone 直接通过相对附件回听并定位，且可一键缓存到本机录音目录
        iphoneStore.obsidianSyncService.simulatedUndownloadedRelativePaths.removeAll()
        let overviewSynced = iphoneStore.syncOverview(for: iphoneRecPendingCloud)
        XCTAssertTrue(overviewSynced.isNoteSynced)
        XCTAssertTrue(overviewSynced.audioState.isAudioSyncedAcrossDevices)
        XCTAssertTrue(overviewSynced.audioState.isPlayableNow)

        let playOutcome = iphoneStore.handleIncomingURL(deepLinkURL)
        XCTAssertEqual(playOutcome, .opened(recordingId: recId, targetMs: 5000, isEstimated: false))
        XCTAssertEqual(iphoneStore.audioService.playingRecordingId, recId)
        iphoneStore.audioService.stopPlayback()

        let cachedLocalURL = try iphoneStore.cacheVaultAudioToLocal(for: recId)
        XCTAssertTrue(fm.fileExists(atPath: cachedLocalURL.path))
        let iphoneRecCached = try XCTUnwrap(iphoneStore.recordings.first(where: { $0.id == recId }))
        XCTAssertEqual(
            iphoneStore.audioAvailability(for: iphoneRecCached),
            .availableLocal(fileURL: cachedLocalURL, alsoSyncedInVault: true)
        )
    }
}
