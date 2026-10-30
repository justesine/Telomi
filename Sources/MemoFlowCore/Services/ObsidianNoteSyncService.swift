import Foundation
import CryptoKit

public enum ObsidianSyncError: LocalizedError, Equatable {
    case vaultNotConfigured
    case authorizationExpired(String)
    case cloudFileNotDownloaded(relativePath: String)
    case legacyNoteConfirmationRequired(candidateRelativePaths: [String])
    case concurrentModificationDetected(relativePath: String)
    case backupNotFound
    case invalidRelativePath
    case fileOperationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .vaultNotConfigured:
            return "尚未选择 Obsidian 笔记库文件夹，请先在设置中绑定目录。"
        case .authorizationExpired(let detail):
            return detail
        case .cloudFileNotDownloaded(let relPath):
            return "iCloud 笔记文件「\(relPath)」尚未下载到本机，已请求系统下载，请下载完成后重试，避免覆盖云端内容。"
        case .legacyNoteConfirmationRequired(let candidates):
            let joined = candidates.joined(separator: "、")
            return "发现缺少录音 ID 的同名历史笔记（\(joined)）。为避免凭标题误覆盖，请先确认关联该笔记或另建独立笔记。"
        case .concurrentModificationDetected(let relPath):
            return "检测到「\(relPath)」在写入期间被外部并发修改，已中止覆盖并保留原文件，请重试。"
        case .backupNotFound:
            return "未找到可恢复的历史写入前备份文件。"
        case .invalidRelativePath:
            return "目标子目录或笔记相对路径不合法。"
        case .fileOperationFailed(let msg):
            return "Obsidian 笔记读写失败：\(msg)"
        }
    }
}

public struct ObsidianExportOutcome: Sendable {
    public let fileURL: URL
    public let obsidianOpenURL: URL?
    public let binding: ObsidianNoteBinding
    public let wasCreatedNew: Bool
    public let relocatedFromOldPath: String?
}

/// 负责录音与单篇 Obsidian 笔记的稳定绑定、重命名/移动重定位、手写内容无损保留、双向修改冲突检测与写入前可恢复备份（P0 核心服务）
public final class ObsidianNoteSyncService {

    public static let shared = ObsidianNoteSyncService()

    /// 仅供隔离测试模拟 iCloud 未下载文件状态（生产环境为空）
    public var simulatedUndownloadedRelativePaths: Set<String> = []
    /// 仅供隔离测试模拟非协调外部进程在合并间隙并发改写文件（生产环境为 nil）
    public var onBeforeAtomicWriteHook: ((URL) -> Void)?

    public init() {}

    // MARK: - Digest & Identity Helpers

    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func normalizedText(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizedBlockDigest(_ text: String) -> String {
        sha256Hex(of: Data(normalizedText(text).utf8))
    }

    /// 从 Markdown 文本（YAML Frontmatter 或隐藏锚点注释）提取稳定 `recording_id`
    public static func extractRecordingId(from markdown: String) -> UUID? {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")

        // 1. 检查 YAML Frontmatter 中的 recording_id
        if normalized.hasPrefix("---\n") {
            let afterStart = normalized.dropFirst(4)
            if let endRange = afterStart.range(of: "\n---") {
                let yamlBlock = String(afterStart[..<endRange.lowerBound])
                if let regex = try? NSRegularExpression(
                    pattern: #"(?m)^recording_id\s*:\s*["']?([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})["']?\s*$"#
                ) {
                    let nsRange = NSRange(yamlBlock.startIndex..<yamlBlock.endIndex, in: yamlBlock)
                    if let match = regex.firstMatch(in: yamlBlock, range: nsRange),
                       let idRange = Range(match.range(at: 1), in: yamlBlock),
                       let uuid = UUID(uuidString: String(yamlBlock[idRange])) {
                        return uuid
                    }
                }
            }
        }

        // 2. 回退检查 HTML 锚点注释 <!-- memoflow:recording_id=... -->
        if let anchorRegex = try? NSRegularExpression(
            pattern: #"<!--\s*memoflow:recording_id=([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\s*-->"#
        ) {
            let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            if let match = anchorRegex.firstMatch(in: normalized, range: nsRange),
               let idRange = Range(match.range(at: 1), in: normalized),
               let uuid = UUID(uuidString: String(normalized[idRange])) {
                return uuid
            }
        }

        return nil
    }

    // MARK: - Vault Authorization & iCloud Check

    public static func resolveAuthorizedVaultURL(preferences: MemoFlowPreferences) throws -> URL {
        guard let rootPath = preferences.obsidianVaultRootPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rootPath.isEmpty || preferences.obsidianVaultBookmark != nil else {
            throw ObsidianSyncError.vaultNotConfigured
        }
        do {
            return try VaultAccess.resolve(preferences)
        } catch let nsErr as NSError {
            throw ObsidianSyncError.authorizationExpired(nsErr.localizedDescription)
        }
    }

    public func verifyCloudDownloaded(fileURL: URL, relativePath: String) throws {
        let normalizedRel = Self.normalizeRelativePath(relativePath)
        if simulatedUndownloadedRelativePaths.contains(normalizedRel) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
            throw ObsidianSyncError.cloudFileNotDownloaded(relativePath: normalizedRel)
        }
        if let values = try? fileURL.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
           values.isUbiquitousItem == true,
           values.ubiquitousItemDownloadingStatus == .notDownloaded {
            try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
            throw ObsidianSyncError.cloudFileNotDownloaded(relativePath: normalizedRel)
        }
    }

    public static func normalizeRelativePath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: " /"))
    }

    public static func validateSafeRelativePath(_ relPath: String) throws -> String {
        let clean = normalizeRelativePath(relPath)
        guard !clean.isEmpty else { throw ObsidianSyncError.invalidRelativePath }
        let parts = clean.split(separator: "/")
        guard !parts.contains(".."), !parts.contains(".") else {
            throw ObsidianSyncError.invalidRelativePath
        }
        return clean
    }

    public static func relativePath(of fileURL: URL, inside vaultRootURL: URL) -> String {
        let rootStandard = vaultRootURL.standardizedFileURL.resolvingSymlinksInPath().path
        let fileStandard = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        if fileStandard.hasPrefix(rootStandard + "/") {
            return String(fileStandard.dropFirst(rootStandard.count + 1))
        }
        let rawRoot = vaultRootURL.standardizedFileURL.path
        let rawFile = fileURL.standardizedFileURL.path
        if rawFile.hasPrefix(rawRoot + "/") {
            return String(rawFile.dropFirst(rawRoot.count + 1))
        }
        return fileURL.lastPathComponent
    }

    // MARK: - Core Export / In-Place Merge Entry Point

    public func exportOrUpdateNote(
        recording: Recording,
        note: Note,
        revision: NoteRevision,
        confirmedActions: [ConfirmedAction],
        segments: [TranscriptSegment],
        pendingDrafts: [ActionDraft],
        vaultRootURL: URL,
        targetSubfolder: String,
        existingBinding: ObsidianNoteBinding?,
        backupsRootURL: URL,
        legacyResolution: ObsidianLegacyResolution = .requireUserConfirmation
    ) throws -> ObsidianExportOutcome {
        let fm = FileManager.default
        let cleanSubfolder = targetSubfolder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSubfolder.isEmpty {
            _ = try Self.validateSafeRelativePath(cleanSubfolder)
        }

        let exportTitle = MarkdownExporterService.exportTitle(recording: recording, revision: revision)
        let preferredName = MarkdownExporterService.preferredFileName(recording: recording, title: exportTitle)
        let preferredRelPath = cleanSubfolder.isEmpty ? preferredName : "\(cleanSubfolder)/\(preferredName)"

        // Step 1: 定位是否已有绑定或同 recording_id 的笔记（支持修改标题、Obsidian 内重命名与跨目录移动）
        var resolvedTargetURL: URL?
        var resolvedRelativePath: String?
        var relocatedFrom: String?
        var isAssociatingLegacy = false

        if let boundRel = existingBinding?.vaultRelativePath,
           !boundRel.isEmpty,
           let validRel = try? Self.validateSafeRelativePath(boundRel) {
            let candidateURL = vaultRootURL.appendingPathComponent(validRel)
            try verifyCloudDownloaded(fileURL: candidateURL, relativePath: validRel)
            if fm.fileExists(atPath: candidateURL.path) {
                if let text = try? Self.readCoordinatedUTF8(at: candidateURL) {
                    let foundId = Self.extractRecordingId(from: text)
                    if foundId == recording.id {
                        resolvedTargetURL = candidateURL
                        resolvedRelativePath = validRel
                    }
                }
            }
        }

        // Step 2: 若原路径不存在或已移动/重命名，按 recording_id 扫描整个 Vault 重定位
        if resolvedTargetURL == nil {
            if let relocated = try findNoteByRecordingId(
                recordingId: recording.id,
                vaultRootURL: vaultRootURL,
                preferredSubfolder: cleanSubfolder
            ) {
                if let prevRel = existingBinding?.vaultRelativePath, !prevRel.isEmpty, prevRel != relocated.relativePath {
                    relocatedFrom = prevRel
                }
                resolvedTargetURL = relocated.fileURL
                resolvedRelativePath = relocated.relativePath
            }
        }

        // Step 3: 若库内尚无该 recording_id 的笔记，处理首次创建或无 ID 同名历史笔记保护
        if resolvedTargetURL == nil {
            switch legacyResolution {
            case .associateExisting(let candidateRel):
                let safeRel = try Self.validateSafeRelativePath(candidateRel)
                let candidateURL = vaultRootURL.appendingPathComponent(safeRel)
                try verifyCloudDownloaded(fileURL: candidateURL, relativePath: safeRel)
                guard fm.fileExists(atPath: candidateURL.path) else {
                    throw ObsidianSyncError.fileOperationFailed("待关联的历史笔记不存在：\(safeRel)")
                }
                if let existingText = try? Self.readCoordinatedUTF8(at: candidateURL),
                   let otherId = Self.extractRecordingId(from: existingText),
                   otherId != recording.id {
                    throw ObsidianSyncError.fileOperationFailed("该笔记已绑定其他录音 ID（\(otherId.uuidString)），不能重复关联。")
                }
                resolvedTargetURL = candidateURL
                resolvedRelativePath = safeRel
                isAssociatingLegacy = true

            case .createSeparateNote:
                let disambiguated = try makeDisambiguatedNewNoteURL(
                    recordingId: recording.id,
                    vaultRootURL: vaultRootURL,
                    subfolder: cleanSubfolder,
                    preferredFileName: preferredName,
                    forceShortIdSuffix: true
                )
                resolvedTargetURL = disambiguated.fileURL
                resolvedRelativePath = disambiguated.relativePath

            case .requireUserConfirmation:
                let legacyCandidates = try findLegacyCandidatesWithoutRecordingId(
                    recording: recording,
                    exportTitle: exportTitle,
                    vaultRootURL: vaultRootURL,
                    subfolder: cleanSubfolder,
                    preferredRelPath: preferredRelPath
                )
                if !legacyCandidates.isEmpty {
                    throw ObsidianSyncError.legacyNoteConfirmationRequired(candidateRelativePaths: legacyCandidates)
                }
                let disambiguated = try makeDisambiguatedNewNoteURL(
                    recordingId: recording.id,
                    vaultRootURL: vaultRootURL,
                    subfolder: cleanSubfolder,
                    preferredFileName: preferredName,
                    forceShortIdSuffix: false
                )
                resolvedTargetURL = disambiguated.fileURL
                resolvedRelativePath = disambiguated.relativePath
            }
        }

        guard let targetURL = resolvedTargetURL, let targetRelPath = resolvedRelativePath else {
            throw ObsidianSyncError.fileOperationFailed("无法解析导出目标路径")
        }

        try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Step 4: 生成本次 MemoFlow 受控区块内容
        let newBlocks = MarkdownExporterService.renderManagedBlocks(
            recording: recording,
            note: note,
            revision: revision,
            confirmedActions: confirmedActions,
            segments: segments,
            pendingDrafts: pendingDrafts
        )

        // Step 5: 通过 NSFileCoordinator(.forMerging) 协调读取、写入前备份、三路合并及并发修改保护
        var coordError: NSError?
        var mergeResult: Result<(ObsidianNoteBinding, Bool), Error>?

        NSFileCoordinator().coordinate(writingItemAt: targetURL, options: .forMerging, error: &coordError) { coordinatedURL in
            mergeResult = Result {
                try verifyCloudDownloaded(fileURL: coordinatedURL, relativePath: targetRelPath)
                let fileExists = fm.fileExists(atPath: coordinatedURL.path)

                if !fileExists {
                    // 全新创建笔记
                    let fullMarkdown = MarkdownExporterService.generateMarkdown(
                        recording: recording,
                        note: note,
                        revision: revision,
                        confirmedActions: confirmedActions,
                        segments: segments,
                        pendingDrafts: pendingDrafts
                    )
                    let outData = Data(fullMarkdown.utf8)
                    try outData.write(to: coordinatedURL, options: .atomic)
                    let modDate = (try? coordinatedURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

                    var digests: [String: String] = [:]
                    var snapshots: [String: String] = [:]
                    for kind in ObsidianManagedBlockKind.allCases {
                        let content = newBlocks[kind] ?? ""
                        digests[kind.rawValue] = Self.normalizedBlockDigest(content)
                        snapshots[kind.rawValue] = content
                    }

                    let binding = ObsidianNoteBinding(
                        recordingId: recording.id,
                        vaultRelativePath: targetRelPath,
                        lastKnownFileName: coordinatedURL.lastPathComponent,
                        lastExportedRevisionId: revision.id,
                        lastExportedAt: Date(),
                        lastSyncedFileSHA256: Self.sha256Hex(of: outData),
                        lastSyncedModificationDate: modDate,
                        managedBlockDigests: digests,
                        managedBlockSnapshots: snapshots,
                        status: .synced,
                        pendingLegacyCandidatePaths: [],
                        conflicts: [],
                        lastScopedSnapshot: ObsidianScopedSyncSnapshot.from(recording: recording, note: note),
                        scopedFieldConflicts: [],
                        lastBackupFilePath: existingBinding?.lastBackupFilePath,
                        lastErrorMessage: nil
                    )
                    return (binding, true)
                }

                // 已有文件原位受控更新（最多允许 1 次因并发外部写入触发的重读合并，第 2 次仍冲突则安全中止）
                var attempt = 0
                while true {
                    attempt += 1
                    let initialData = try Data(contentsOf: coordinatedURL)
                    let initialSHA = Self.sha256Hex(of: initialData)
                    guard let existingText = String(data: initialData, encoding: .utf8) else {
                        throw ObsidianSyncError.fileOperationFailed("笔记文件不是有效的 UTF-8 文本编码")
                    }

                    // 写入前保存可恢复版本快照到独立备份目录
                    let backupURL = try Self.savePreWriteBackup(
                        originalData: initialData,
                        recordingId: recording.id,
                        fileName: coordinatedURL.lastPathComponent,
                        backupsRootURL: backupsRootURL
                    )

                    let merged = Self.mergeExistingMarkdown(
                        existingMarkdown: existingText,
                        recording: recording,
                        note: note,
                        revision: revision,
                        segments: segments,
                        newBlocks: newBlocks,
                        existingBinding: existingBinding,
                        isAssociatingLegacy: isAssociatingLegacy
                    )

                    // 测试钩子（模拟合并完成到原子落盘瞬间发生非协调并发写入）
                    if attempt == 1, let hook = onBeforeAtomicWriteHook {
                        hook(coordinatedURL)
                    }

                    // 并发修改校验：落盘前复核文件指纹是否被外部同时改动
                    let currentDiskData = try Data(contentsOf: coordinatedURL)
                    let currentDiskSHA = Self.sha256Hex(of: currentDiskData)
                    if currentDiskSHA != initialSHA {
                        if attempt < 2 {
                            continue
                        } else {
                            throw ObsidianSyncError.concurrentModificationDetected(relativePath: targetRelPath)
                        }
                    }

                    let outData = Data(merged.markdown.utf8)
                    try outData.write(to: coordinatedURL, options: .atomic)
                    let modDate = (try? coordinatedURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

                    let postMergeScoped = Self.extractScopedSnapshot(
                        from: merged.markdown,
                        recordingId: recording.id
                    )
                    let activeScopedConflicts = existingBinding?.scopedFieldConflicts ?? []
                    let hasAnyConflict = !merged.conflicts.isEmpty || !activeScopedConflicts.isEmpty
                    let binding = ObsidianNoteBinding(
                        recordingId: recording.id,
                        vaultRelativePath: targetRelPath,
                        lastKnownFileName: coordinatedURL.lastPathComponent,
                        lastExportedRevisionId: revision.id,
                        lastExportedAt: Date(),
                        lastSyncedFileSHA256: Self.sha256Hex(of: outData),
                        lastSyncedModificationDate: modDate,
                        managedBlockDigests: merged.updatedDigests,
                        managedBlockSnapshots: merged.updatedSnapshots,
                        status: hasAnyConflict ? .hasConflict : .synced,
                        pendingLegacyCandidatePaths: [],
                        conflicts: merged.conflicts,
                        lastScopedSnapshot: activeScopedConflicts.isEmpty ? postMergeScoped : (existingBinding?.lastScopedSnapshot ?? postMergeScoped),
                        scopedFieldConflicts: activeScopedConflicts,
                        lastBackupFilePath: backupURL.path,
                        lastErrorMessage: nil
                    )
                    return (binding, false)
                }
            }
        }

        if let coordError {
            if coordError.domain == NSCocoaErrorDomain &&
                (coordError.code == NSFileReadNoPermissionError || coordError.code == NSFileWriteNoPermissionError) {
                throw ObsidianSyncError.authorizationExpired("Obsidian 目录读写权限已失效，请重新授权。")
            }
            throw ObsidianSyncError.fileOperationFailed(coordError.localizedDescription)
        }

        guard let mergeResult else {
            throw ObsidianSyncError.fileOperationFailed("协调写入未返回结果")
        }

        let (updatedBinding, wasCreatedNew) = try mergeResult.get()
        let openURL = MarkdownExporterService.obsidianOpenURL(
            vaultRootURL: vaultRootURL,
            relativePath: updatedBinding.vaultRelativePath
        )
        return ObsidianExportOutcome(
            fileURL: targetURL,
            obsidianOpenURL: openURL,
            binding: updatedBinding,
            wasCreatedNew: wasCreatedNew,
            relocatedFromOldPath: relocatedFrom
        )
    }

    // MARK: - Conflict Resolution & Backup Restore

    public func resolveConflict(
        vaultRootURL: URL,
        binding: ObsidianNoteBinding,
        blockKind: ObsidianManagedBlockKind,
        choice: ObsidianConflictResolutionChoice,
        backupsRootURL: URL
    ) throws -> ObsidianNoteBinding {
        let safeRel = try Self.validateSafeRelativePath(binding.vaultRelativePath)
        let targetURL = vaultRootURL.appendingPathComponent(safeRel)
        try verifyCloudDownloaded(fileURL: targetURL, relativePath: safeRel)

        guard let conflict = binding.conflicts.first(where: { $0.blockKind == blockKind }) else {
            return binding
        }

        let chosenContent: String
        switch choice {
        case .keepObsidianUserVersion:
            chosenContent = conflict.userEditedContent
        case .adoptMemoFlowVersion:
            chosenContent = conflict.memoFlowGeneratedContent
        case .keepBothMerged:
            let u = conflict.userEditedContent.trimmingCharacters(in: .whitespacesAndNewlines)
            let m = conflict.memoFlowGeneratedContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if u.isEmpty {
                chosenContent = m
            } else if m.isEmpty {
                chosenContent = u
            } else {
                chosenContent = "\(u)\n\n---\n\n\(m)"
            }
        }

        var coordError: NSError?
        var outcome: Result<ObsidianNoteBinding, Error>?

        NSFileCoordinator().coordinate(writingItemAt: targetURL, options: .forMerging, error: &coordError) { coordinatedURL in
            outcome = Result {
                let rawData = try Data(contentsOf: coordinatedURL)
                guard let text = String(data: rawData, encoding: .utf8) else {
                    throw ObsidianSyncError.fileOperationFailed("无法解码笔记文本")
                }

                let backupURL = try Self.savePreWriteBackup(
                    originalData: rawData,
                    recordingId: binding.recordingId,
                    fileName: coordinatedURL.lastPathComponent,
                    backupsRootURL: backupsRootURL
                )

                let updatedText = Self.replaceManagedBlockContent(
                    in: text,
                    kind: blockKind,
                    newInnerContent: chosenContent
                )
                let outData = Data(updatedText.utf8)
                try outData.write(to: coordinatedURL, options: .atomic)
                let modDate = (try? coordinatedURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

                var nextBinding = binding
                nextBinding.conflicts.removeAll { $0.blockKind == blockKind }
                nextBinding.managedBlockDigests[blockKind.rawValue] = Self.normalizedBlockDigest(chosenContent)
                nextBinding.managedBlockSnapshots[blockKind.rawValue] = chosenContent
                nextBinding.lastSyncedFileSHA256 = Self.sha256Hex(of: outData)
                nextBinding.lastSyncedModificationDate = modDate
                nextBinding.lastBackupFilePath = backupURL.path
                nextBinding.status = nextBinding.conflicts.isEmpty ? .synced : .hasConflict
                nextBinding.lastErrorMessage = nil
                return nextBinding
            }
        }

        if let coordError {
            throw ObsidianSyncError.fileOperationFailed(coordError.localizedDescription)
        }
        guard let outcome else {
            throw ObsidianSyncError.fileOperationFailed("冲突处理未完成")
        }
        return try outcome.get()
    }

    public func restoreFromBackup(
        vaultRootURL: URL,
        binding: ObsidianNoteBinding
    ) throws -> ObsidianNoteBinding {
        guard let backupPath = binding.lastBackupFilePath,
              FileManager.default.fileExists(atPath: backupPath) else {
            throw ObsidianSyncError.backupNotFound
        }
        let safeRel = try Self.validateSafeRelativePath(binding.vaultRelativePath)
        let targetURL = vaultRootURL.appendingPathComponent(safeRel)
        let backupData = try Data(contentsOf: URL(fileURLWithPath: backupPath))

        var coordError: NSError?
        var writeErr: Error?
        NSFileCoordinator().coordinate(writingItemAt: targetURL, options: .forReplacing, error: &coordError) { coordinatedURL in
            do {
                try FileManager.default.createDirectory(
                    at: coordinatedURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try backupData.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeErr = error
            }
        }
        if let err = coordError ?? writeErr {
            throw ObsidianSyncError.fileOperationFailed(err.localizedDescription)
        }

        let modDate = (try? targetURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        var nextBinding = binding
        nextBinding.lastSyncedFileSHA256 = Self.sha256Hex(of: backupData)
        nextBinding.lastSyncedModificationDate = modDate
        nextBinding.conflicts.removeAll()
        nextBinding.status = .synced
        nextBinding.lastErrorMessage = nil

        if let restoredText = String(data: backupData, encoding: .utf8) {
            let parsed = Self.parseBodyTokens(Self.splitFrontmatterAndBody(restoredText).body)
            for token in parsed {
                if case .managed(let kind, let inner) = token {
                    let cleanInner = Self.unwrapConflictUserContentIfPresent(inner, kind: kind) ?? inner
                    nextBinding.managedBlockDigests[kind.rawValue] = Self.normalizedBlockDigest(cleanInner)
                    nextBinding.managedBlockSnapshots[kind.rawValue] = cleanInner
                }
            }
        }
        return nextBinding
    }

    // MARK: - Vault Scanning & Relocation by recording_id

    public func findNoteByRecordingId(
        recordingId: UUID,
        vaultRootURL: URL,
        preferredSubfolder: String
    ) throws -> (fileURL: URL, relativePath: String)? {
        let fm = FileManager.default
        let cleanSub = preferredSubfolder.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. 优先扫描目标子文件夹
        if !cleanSub.isEmpty {
            let subURL = vaultRootURL.appendingPathComponent(cleanSub, isDirectory: true)
            if fm.fileExists(atPath: subURL.path),
               let found = try scanDirectoryForRecordingId(
                directoryURL: subURL,
                vaultRootURL: vaultRootURL,
                recordingId: recordingId,
                skipSubtreePath: nil
               ) {
                return found
            }
        }

        // 2. 扫描整个知识库（跳过隐藏目录如 .obsidian/.trash/.git 及刚扫描过的子目录）
        let skipPath = cleanSub.isEmpty ? nil : vaultRootURL.appendingPathComponent(cleanSub, isDirectory: true).standardizedFileURL.path
        return try scanDirectoryForRecordingId(
            directoryURL: vaultRootURL,
            vaultRootURL: vaultRootURL,
            recordingId: recordingId,
            skipSubtreePath: skipPath
        )
    }

    private func scanDirectoryForRecordingId(
        directoryURL: URL,
        vaultRootURL: URL,
        recordingId: UUID,
        skipSubtreePath: String?
    ) throws -> (fileURL: URL, relativePath: String)? {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .ubiquitousItemDownloadingStatusKey,
            .isUbiquitousItemKey
        ]
        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            let stdPath = fileURL.standardizedFileURL.path
            if let skip = skipSubtreePath, stdPath == skip || stdPath.hasPrefix(skip + "/") {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? fileURL.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            let relPath = Self.relativePath(of: fileURL, inside: vaultRootURL)
            if relPath.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard fileURL.pathExtension.lowercased() == "md", values.isRegularFile == true else { continue }

            if simulatedUndownloadedRelativePaths.contains(Self.normalizeRelativePath(relPath)) ||
                (values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded) {
                try? fm.startDownloadingUbiquitousItem(at: fileURL)
                continue
            }
            if let size = values.fileSize, size > 2_000_000 { continue }

            // 只读取文件头部即可快速识别 Frontmatter / Anchor，兼顾大文件性能
            if let prefixText = Self.readUTF8Prefix(at: fileURL, maxBytes: 16_384),
               Self.extractRecordingId(from: prefixText) == recordingId {
                return (fileURL, relPath)
            }
        }
        return nil
    }

    private func findLegacyCandidatesWithoutRecordingId(
        recording: Recording,
        exportTitle: String,
        vaultRootURL: URL,
        subfolder: String,
        preferredRelPath: String
    ) throws -> [String] {
        let fm = FileManager.default
        var candidateRelPaths: [String] = []
        let cleanTitle = MarkdownExporterService.safeFileTitle(exportTitle)
        let titleOnlyRel = subfolder.isEmpty ? "\(cleanTitle).md" : "\(subfolder)/\(cleanTitle).md"

        let potentialPaths = Array(NSOrderedSet(array: [preferredRelPath, titleOnlyRel])).compactMap { $0 as? String }
        for rel in potentialPaths {
            let url = vaultRootURL.appendingPathComponent(rel)
            try verifyCloudDownloaded(fileURL: url, relativePath: rel)
            guard fm.fileExists(atPath: url.path) else { continue }
            if let text = try? Self.readCoordinatedUTF8(at: url) {
                if Self.extractRecordingId(from: text) == nil {
                    candidateRelPaths.append(rel)
                }
            }
        }
        return candidateRelPaths
    }

    private func makeDisambiguatedNewNoteURL(
        recordingId: UUID,
        vaultRootURL: URL,
        subfolder: String,
        preferredFileName: String,
        forceShortIdSuffix: Bool
    ) throws -> (fileURL: URL, relativePath: String) {
        let fm = FileManager.default
        let dirURL = subfolder.isEmpty ? vaultRootURL : vaultRootURL.appendingPathComponent(subfolder, isDirectory: true)
        let baseName = (preferredFileName as NSString).deletingPathExtension
        let ext = (preferredFileName as NSString).pathExtension.isEmpty ? "md" : (preferredFileName as NSString).pathExtension

        if !forceShortIdSuffix {
            let firstURL = dirURL.appendingPathComponent(preferredFileName)
            let firstRel = subfolder.isEmpty ? preferredFileName : "\(subfolder)/\(preferredFileName)"
            try verifyCloudDownloaded(fileURL: firstURL, relativePath: firstRel)
            if !fm.fileExists(atPath: firstURL.path) {
                return (firstURL, firstRel)
            }
        }

        let shortId = String(recordingId.uuidString.prefix(6)).lowercased()
        let withIdName = "\(baseName)-\(shortId).\(ext)"
        let withIdURL = dirURL.appendingPathComponent(withIdName)
        let withIdRel = subfolder.isEmpty ? withIdName : "\(subfolder)/\(withIdName)"
        if !fm.fileExists(atPath: withIdURL.path) {
            return (withIdURL, withIdRel)
        }

        var index = 2
        while true {
            let nextName = "\(baseName)-\(shortId)-\(index).\(ext)"
            let nextURL = dirURL.appendingPathComponent(nextName)
            let nextRel = subfolder.isEmpty ? nextName : "\(subfolder)/\(nextName)"
            if !fm.fileExists(atPath: nextURL.path) {
                return (nextURL, nextRel)
            }
            index += 1
        }
    }

    // MARK: - Pre-Write Backup Management

    public static func savePreWriteBackup(
        originalData: Data,
        recordingId: UUID,
        fileName: String,
        backupsRootURL: URL
    ) throws -> URL {
        let fm = FileManager.default
        let recDir = backupsRootURL.appendingPathComponent(recordingId.uuidString, isDirectory: true)
        try fm.createDirectory(at: recDir, withIntermediateDirectories: true)

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let stamp = fmt.string(from: Date())

        let safeName = fileName.replacingOccurrences(of: "/", with: "-")
        let backupURL = recDir.appendingPathComponent("\(stamp)-\(safeName)")
        try originalData.write(to: backupURL, options: .atomic)

        // 保留最近 20 份快照，自动清理更早的快照
        if let files = try? fm.contentsOfDirectory(at: recDir, includingPropertiesForKeys: [.creationDateKey]) {
            let sorted = files.sorted { $0.lastPathComponent > $1.lastPathComponent }
            if sorted.count > 20 {
                for old in sorted.dropFirst(20) {
                    try? fm.removeItem(at: old)
                }
            }
        }
        return backupURL
    }

    // MARK: - Lossless Frontmatter & Body 3-Way Merger

    public struct MergeOutput {
        public let markdown: String
        public let updatedDigests: [String: String]
        public let updatedSnapshots: [String: String]
        public let conflicts: [ObsidianBlockConflict]
    }

    public enum BodyToken {
        case unmanaged(String)
        case managed(ObsidianManagedBlockKind, String)
    }

    private static let managedFrontmatterKeys: Set<String> = [
        "title", "recording_id", "recorded_at", "date", "timezone", "source", "mode",
        "duration", "duration_seconds", "processing_status", "review_status",
        "transcript_status", "transcript_review_status", "summary_alignment_status",
        "note_revision_id", "note_origin", "transcript_sha256", "audio_status",
        "audio_sync_status", "audio_attachment", "project", "tags"
    ]

    public static func splitFrontmatterAndBody(_ markdown: String) -> (frontmatterLines: [String]?, body: String) {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else {
            return (nil, normalized)
        }
        let lines = normalized.components(separatedBy: "\n")
        if let closingIdx = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            let yamlLines = Array(lines[1..<closingIdx])
            let bodyLines = Array(lines[(closingIdx + 1)...])
            return (yamlLines, bodyLines.joined(separator: "\n"))
        }
        return (nil, normalized)
    }

    public static func extractFrontmatterPreservedFields(
        from frontmatterLines: [String]?
    ) -> (userTags: [String], customKeyBlocks: [[String]], rawProjectValue: String?) {
        guard let lines = frontmatterLines, !lines.isEmpty else {
            return ([], [], nil)
        }

        // 将 YAML 行按顶层 key 分组
        var groups: [(key: String, lines: [String])] = []
        let topKeyRegex = try? NSRegularExpression(pattern: #"^([A-Za-z0-9_\-\u4e00-\u9fa5]+)\s*:(.*)$"#)

        for line in lines {
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            if !line.hasPrefix(" ") && !line.hasPrefix("\t"),
               let match = topKeyRegex?.firstMatch(in: line, range: nsRange),
               let keyRange = Range(match.range(at: 1), in: line) {
                let key = String(line[keyRange])
                groups.append((key: key, lines: [line]))
            } else if !groups.isEmpty {
                groups[groups.count - 1].lines.append(line)
            } else {
                groups.append((key: "_raw", lines: [line]))
            }
        }

        var userTags: [String] = []
        var customBlocks: [[String]] = []
        var rawProjectValue: String?

        for group in groups {
            let lowerKey = group.key.lowercased()
            if lowerKey == "tags" {
                let parsed = parseYAMLTags(from: group.lines)
                for tag in parsed where !MarkdownExporterService.systemManagedTags.contains(tag) && !userTags.contains(tag) {
                    userTags.append(tag)
                }
            } else if lowerKey == "project" {
                if let first = group.lines.first, let colonIdx = first.firstIndex(of: ":") {
                    let val = String(first[first.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                    if !val.isEmpty {
                        rawProjectValue = val
                    }
                }
            } else if !managedFrontmatterKeys.contains(lowerKey) {
                customBlocks.append(group.lines)
            }
        }

        return (userTags, customBlocks, rawProjectValue)
    }

    public static func parseYAMLTags(from tagBlockLines: [String]) -> [String] {
        guard let first = tagBlockLines.first else { return [] }
        var result: [String] = []

        if let colonIdx = first.firstIndex(of: ":") {
            let inlinePart = String(first[first.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            if inlinePart.hasPrefix("[") && inlinePart.hasSuffix("]") {
                let inner = String(inlinePart.dropFirst().dropLast())
                for item in inner.components(separatedBy: ",") {
                    let cleaned = cleanTagToken(item)
                    if !cleaned.isEmpty && !result.contains(cleaned) {
                        result.append(cleaned)
                    }
                }
            } else if !inlinePart.isEmpty {
                let cleaned = cleanTagToken(inlinePart)
                if !cleaned.isEmpty {
                    result.append(cleaned)
                }
            }
        }

        for line in tagBlockLines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("-") {
                let raw = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                let cleaned = cleanTagToken(raw)
                if !cleaned.isEmpty && !result.contains(cleaned) {
                    result.append(cleaned)
                }
            }
        }
        return result
    }

    private static func cleanTagToken(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            s = String(s.dropFirst().dropLast())
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("#") {
            s.removeFirst()
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func parseBodyTokens(_ body: String) -> [BodyToken] {
        var tokens: [BodyToken] = []
        var cursor = body.startIndex

        // 查找最早出现的受控区块起点
        while cursor < body.endIndex {
            var earliestMatch: (kind: ObsidianManagedBlockKind, startRange: Range<String.Index>, endRange: Range<String.Index>)?

            for kind in ObsidianManagedBlockKind.allCases {
                let startMarker = MarkdownExporterService.managedBlockStartMarker(kind)
                let endMarker = MarkdownExporterService.managedBlockEndMarker(kind)
                if let sRange = body.range(of: startMarker, range: cursor..<body.endIndex),
                   let eRange = body.range(of: endMarker, range: sRange.upperBound..<body.endIndex) {
                    if earliestMatch == nil || sRange.lowerBound < earliestMatch!.startRange.lowerBound {
                        earliestMatch = (kind, sRange, eRange)
                    }
                }
            }

            guard let match = earliestMatch else {
                let tail = String(body[cursor..<body.endIndex])
                if !tail.isEmpty {
                    tokens.append(.unmanaged(tail))
                }
                break
            }

            if cursor < match.startRange.lowerBound {
                tokens.append(.unmanaged(String(body[cursor..<match.startRange.lowerBound])))
            }

            var inner = String(body[match.startRange.upperBound..<match.endRange.lowerBound])
            if inner.hasPrefix("\n") { inner.removeFirst() }
            if inner.hasSuffix("\n") { inner.removeLast() }
            tokens.append(.managed(match.kind, inner))

            cursor = match.endRange.upperBound
        }

        return tokens
    }

    public static func conflictUserStartMarker(_ kind: ObsidianManagedBlockKind) -> String {
        "<!-- memoflow:conflict:\(kind.rawValue):user:start -->"
    }

    public static func conflictUserEndMarker(_ kind: ObsidianManagedBlockKind) -> String {
        "<!-- memoflow:conflict:\(kind.rawValue):user:end -->"
    }

    public static func conflictMemoFlowStartMarker(_ kind: ObsidianManagedBlockKind) -> String {
        "<!-- memoflow:conflict:\(kind.rawValue):memoflow:start -->"
    }

    public static func conflictMemoFlowEndMarker(_ kind: ObsidianManagedBlockKind) -> String {
        "<!-- memoflow:conflict:\(kind.rawValue):memoflow:end -->"
    }

    public static func renderConflictBlock(
        kind: ObsidianManagedBlockKind,
        userVersion: String,
        memoFlowVersion: String
    ) -> String {
        var lines: [String] = []
        lines.append("> [!WARNING] 检测到「\(kind.displayTitle)」存在双方修改冲突（已同时保留双方内容，可在 MemoFlow 详情页一键选择保留版本或从备份恢复）")
        lines.append("")
        lines.append("### Obsidian 中的手改版本")
        lines.append(conflictUserStartMarker(kind))
        lines.append(userVersion.trimmingCharacters(in: .whitespacesAndNewlines))
        lines.append(conflictUserEndMarker(kind))
        lines.append("")
        lines.append("### MemoFlow 最新整理版本")
        lines.append(conflictMemoFlowStartMarker(kind))
        lines.append(memoFlowVersion.trimmingCharacters(in: .whitespacesAndNewlines))
        lines.append(conflictMemoFlowEndMarker(kind))
        return lines.joined(separator: "\n")
    }

    public static func unwrapConflictUserContentIfPresent(
        _ inner: String,
        kind: ObsidianManagedBlockKind
    ) -> String? {
        let uStart = conflictUserStartMarker(kind)
        let uEnd = conflictUserEndMarker(kind)
        guard let sRange = inner.range(of: uStart),
              let eRange = inner.range(of: uEnd, range: sRange.upperBound..<inner.endIndex) else {
            return nil
        }
        return String(inner[sRange.upperBound..<eRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func mergeExistingMarkdown(
        existingMarkdown: String,
        recording: Recording,
        note: Note,
        revision: NoteRevision,
        segments: [TranscriptSegment] = [],
        newBlocks: [ObsidianManagedBlockKind: String],
        existingBinding: ObsidianNoteBinding?,
        isAssociatingLegacy: Bool,
        overrideExactUserTags: [String]? = nil,
        useExactNoteProject: Bool = false,
        overrideUserSupplement: String? = nil
    ) -> MergeOutput {
        let (existingFrontmatter, rawExistingBody) = splitFrontmatterAndBody(existingMarkdown)
        let preserved = extractFrontmatterPreservedFields(from: existingFrontmatter)

        // 若调用方显式指定了个人补充推送值，或 MemoFlow 侧个人补充已更新且磁盘侧未改动，则同步更新个人补充区
        var existingBody = rawExistingBody
        if let explicitSupp = overrideUserSupplement {
            existingBody = MarkdownExporterService.replaceUserSupplementRegion(in: existingBody, newSupplement: explicitSupp)
        } else if let baseSnap = existingBinding?.lastScopedSnapshot {
            let diskSupp = extractUserSupplement(from: rawExistingBody)
            let localSupp = ObsidianScopedSyncSnapshot.normalizeSupplement(note.userSupplement)
            if diskSupp == baseSnap.userSupplement && localSupp != baseSnap.userSupplement {
                existingBody = MarkdownExporterService.replaceUserSupplementRegion(in: existingBody, newSupplement: note.userSupplement)
            }
        }

        let frontmatterLines = MarkdownExporterService.renderFrontmatterLines(
            recording: recording,
            note: note,
            revision: revision,
            segments: segments,
            preservedUserTags: preserved.userTags,
            preservedCustomKeyBlocks: preserved.customKeyBlocks,
            fallbackProjectRawValue: preserved.rawProjectValue,
            overrideExactUserTags: overrideExactUserTags,
            useExactNoteProject: useExactNoteProject
        )

        let bodyTokens = parseBodyTokens(existingBody)
        let hasAnyManagedBlocks = bodyTokens.contains {
            if case .managed = $0 { return true }
            return false
        }

        var nextDigests = existingBinding?.managedBlockDigests ?? [:]
        var nextSnapshots = existingBinding?.managedBlockSnapshots ?? [:]
        var detectedConflicts: [ObsidianBlockConflict] = []

        // 情况 A：用户确认关联了一篇不含受控区块的历史手写笔记 -> 100% 保留原文至「个人补充」，并附加受控区块
        if !hasAnyManagedBlocks || isAssociatingLegacy && !hasAnyManagedBlocks {
            var lines: [String] = frontmatterLines
            lines.append(MarkdownExporterService.recordingAnchorComment(for: recording.id))
            lines.append("")

            func appendFreshBlock(_ kind: ObsidianManagedBlockKind) {
                let content = newBlocks[kind] ?? ""
                lines.append(MarkdownExporterService.managedBlockStartMarker(kind))
                if !content.isEmpty {
                    lines.append(content)
                }
                lines.append(MarkdownExporterService.managedBlockEndMarker(kind))
                lines.append("")
                nextDigests[kind.rawValue] = normalizedBlockDigest(content)
                nextSnapshots[kind.rawValue] = content
            }

            appendFreshBlock(.header)

            lines.append("## 个人补充")
            lines.append(MarkdownExporterService.userSupplementStartMarker)
            let legacyBodyTrimmed = existingBody.trimmingCharacters(in: .whitespacesAndNewlines)
            if !legacyBodyTrimmed.isEmpty {
                lines.append(legacyBodyTrimmed)
            } else if !note.userSupplement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(note.userSupplement.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            lines.append(MarkdownExporterService.userSupplementEndMarker)
            lines.append("")

            for kind in ObsidianManagedBlockKind.allCases where kind != .header {
                appendFreshBlock(kind)
            }

            return MergeOutput(
                markdown: lines.joined(separator: "\n"),
                updatedDigests: nextDigests,
                updatedSnapshots: nextSnapshots,
                conflicts: []
            )
        }

        // 情况 B：标准三路受控合并（原位保留所有受控区块外的手写段落、标签与双链）
        var seenManagedKinds = Set<ObsidianManagedBlockKind>()
        var rebuiltBodyParts: [String] = []

        func mergeSingleBlock(kind: ObsidianManagedBlockKind, diskRawInner: String) -> String {
            let newContent = newBlocks[kind] ?? ""
            let effectiveUserInner = unwrapConflictUserContentIfPresent(diskRawInner, kind: kind) ?? diskRawInner
            let wasAlreadyInConflict = unwrapConflictUserContentIfPresent(diskRawInner, kind: kind) != nil

            let diskDigest = normalizedBlockDigest(effectiveUserInner)
            let newDigest = normalizedBlockDigest(newContent)
            let baseDigest = existingBinding?.managedBlockDigests[kind.rawValue]

            let finalInner: String
            if diskDigest == newDigest && !wasAlreadyInConflict {
                finalInner = newContent
                nextDigests[kind.rawValue] = newDigest
                nextSnapshots[kind.rawValue] = newContent
            } else if let base = baseDigest {
                if diskDigest == base && !wasAlreadyInConflict {
                    // 用户未在 Obsidian 改动此 AI 区块 -> 安全更新为最新整理版本
                    finalInner = newContent
                    nextDigests[kind.rawValue] = newDigest
                    nextSnapshots[kind.rawValue] = newContent
                } else if newDigest == base && !wasAlreadyInConflict {
                    // 用户在 Obsidian 修改了此区块，而 MemoFlow 侧此区块未变 -> 保留用户修改
                    finalInner = effectiveUserInner
                    // 保持 baseDigest 为上次导出值，以便未来 AI 重新生成不同内容时仍能检测冲突
                } else if diskDigest == newDigest {
                    finalInner = newContent
                    nextDigests[kind.rawValue] = newDigest
                    nextSnapshots[kind.rawValue] = newContent
                } else {
                    // 双方同时修改了同一受控区域 -> 记录冲突并在笔记中保留双方版本
                    let conflict = ObsidianBlockConflict(
                        blockKind: kind,
                        userEditedContent: effectiveUserInner,
                        memoFlowGeneratedContent: newContent,
                        baseExportedDigest: base
                    )
                    detectedConflicts.append(conflict)
                    finalInner = renderConflictBlock(
                        kind: kind,
                        userVersion: effectiveUserInner,
                        memoFlowVersion: newContent
                    )
                }
            } else {
                // 本地缺少历史基准指纹（如状态重建后重连已有笔记）
                if kind == .header || effectiveUserInner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    finalInner = newContent
                    nextDigests[kind.rawValue] = newDigest
                    nextSnapshots[kind.rawValue] = newContent
                } else {
                    let conflict = ObsidianBlockConflict(
                        blockKind: kind,
                        userEditedContent: effectiveUserInner,
                        memoFlowGeneratedContent: newContent,
                        baseExportedDigest: ""
                    )
                    detectedConflicts.append(conflict)
                    finalInner = renderConflictBlock(
                        kind: kind,
                        userVersion: effectiveUserInner,
                        memoFlowVersion: newContent
                    )
                }
            }

            if finalInner.isEmpty {
                return "\(MarkdownExporterService.managedBlockStartMarker(kind))\n\(MarkdownExporterService.managedBlockEndMarker(kind))"
            } else {
                return "\(MarkdownExporterService.managedBlockStartMarker(kind))\n\(finalInner)\n\(MarkdownExporterService.managedBlockEndMarker(kind))"
            }
        }

        for token in bodyTokens {
            switch token {
            case .unmanaged(let rawText):
                rebuiltBodyParts.append(rawText)
            case .managed(let kind, let inner):
                seenManagedKinds.insert(kind)
                rebuiltBodyParts.append(mergeSingleBlock(kind: kind, diskRawInner: inner))
            }
        }

        // 若存在新增的受控区块类型（旧版笔记未包含对应锚点），追加在末尾而不破坏前文手写结构
        for kind in ObsidianManagedBlockKind.allCases where !seenManagedKinds.contains(kind) {
            let content = newBlocks[kind] ?? ""
            nextDigests[kind.rawValue] = normalizedBlockDigest(content)
            nextSnapshots[kind.rawValue] = content
            if content.isEmpty {
                rebuiltBodyParts.append("\n\(MarkdownExporterService.managedBlockStartMarker(kind))\n\(MarkdownExporterService.managedBlockEndMarker(kind))\n")
            } else {
                rebuiltBodyParts.append("\n\(MarkdownExporterService.managedBlockStartMarker(kind))\n\(content)\n\(MarkdownExporterService.managedBlockEndMarker(kind))\n")
            }
        }

        var mergedBody = rebuiltBodyParts.joined()
        let anchor = MarkdownExporterService.recordingAnchorComment(for: recording.id)
        if !mergedBody.contains("memoflow:recording_id=") {
            mergedBody = "\n\(anchor)\n" + mergedBody
        }
        if !mergedBody.hasPrefix("\n") {
            mergedBody = "\n" + mergedBody
        }

        let fullMarkdown = frontmatterLines.joined(separator: "\n") + mergedBody
        return MergeOutput(
            markdown: fullMarkdown,
            updatedDigests: nextDigests,
            updatedSnapshots: nextSnapshots,
            conflicts: detectedConflicts
        )
    }

    public static func replaceManagedBlockContent(
        in markdown: String,
        kind: ObsidianManagedBlockKind,
        newInnerContent: String
    ) -> String {
        let startMarker = MarkdownExporterService.managedBlockStartMarker(kind)
        let endMarker = MarkdownExporterService.managedBlockEndMarker(kind)
        guard let sRange = markdown.range(of: startMarker),
              let eRange = markdown.range(of: endMarker, range: sRange.upperBound..<markdown.endIndex) else {
            return markdown
        }
        let replacement: String
        let trimmed = newInnerContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            replacement = "\(startMarker)\n\(endMarker)"
        } else {
            replacement = "\(startMarker)\n\(trimmed)\n\(endMarker)"
        }
        var updated = markdown
        updated.replaceSubrange(sRange.lowerBound..<eRange.upperBound, with: replacement)
        return updated
    }

    // MARK: - Low-Level Coordinated Read Helpers

    public static func readCoordinatedUTF8(at url: URL) throws -> String {
        var coordError: NSError?
        var readResult: Result<String, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { coordinatedURL in
            readResult = Result {
                let data = try Data(contentsOf: coordinatedURL)
                guard let str = String(data: data, encoding: .utf8) else {
                    throw ObsidianSyncError.fileOperationFailed("UTF-8 解码失败")
                }
                return str
            }
        }
        if let coordError { throw coordError }
        guard let readResult else { throw ObsidianSyncError.fileOperationFailed("读取未返回内容") }
        return try readResult.get()
    }

    private static func readUTF8Prefix(at url: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes), !data.isEmpty else { return nil }
        if let exact = String(data: data, encoding: .utf8) {
            return exact
        }
        // 处理截断在多字节 UTF-8 字符中间的边界
        for trim in 1...min(4, data.count) {
            if let str = String(data: data.dropLast(trim), encoding: .utf8) {
                return str
            }
        }
        return nil
    }

    // MARK: - P2-6 Scoped Bidirectional Sync (userSupplement, manualTags, projectName, marks)

    public struct ScopedReconcileOutcome: Sendable {
        public var updatedUserSupplement: String?
        public var updatedManualTags: [String]?
        public var shouldUpdateProjectName: Bool
        public var updatedProjectName: String?
        public var updatedMarks: [RecordingMark]?
        public var updatedVaultAudioRelativePath: String? = nil
        public var binding: ObsidianNoteBinding
        public var didWriteToDisk: Bool
        public var didPullToMemoFlow: Bool
        public var noteWasDeletedInVault: Bool
        public var relocatedFromOldPath: String?
    }

    public static func extractUserSupplement(from bodyOrMarkdown: String) -> String {
        let normalized = bodyOrMarkdown.replacingOccurrences(of: "\r\n", with: "\n")
        guard let sRange = normalized.range(of: MarkdownExporterService.userSupplementStartMarker),
              let eRange = normalized.range(of: MarkdownExporterService.userSupplementEndMarker, range: sRange.upperBound..<normalized.endIndex) else {
            return ""
        }
        return ObsidianScopedSyncSnapshot.normalizeSupplement(
            String(normalized[sRange.upperBound..<eRange.lowerBound])
        )
    }

    /// 从 Obsidian `.md` 文本解析四个有限同步字段快照
    public static func extractScopedSnapshot(
        from markdown: String,
        recordingId: UUID
    ) -> ObsidianScopedSyncSnapshot {
        let (frontmatterLines, body) = splitFrontmatterAndBody(markdown)
        let preserved = extractFrontmatterPreservedFields(from: frontmatterLines)
        let supplement = extractUserSupplement(from: body)
        let unwrappedProject = ObsidianScopedSyncSnapshot.normalizeProject(preserved.rawProjectValue)
        let parsedMarks = extractMarksFromBody(body, recordingId: recordingId)

        return ObsidianScopedSyncSnapshot(
            userSupplement: supplement,
            manualTags: preserved.userTags,
            projectName: unwrappedProject,
            marks: parsedMarks
        )
    }

    /// 解析 `marks` 受控区块内的书签、高亮与批注（同时兼容带 `memoflow:mark_id` 注释的标准行与用户在 Obsidian 手写新增的带时间戳条目）
    public static func extractMarksFromBody(_ body: String, recordingId: UUID) -> [RecordingMark] {
        let tokens = parseBodyTokens(body)
        guard let marksInner = tokens.compactMap({ token -> String? in
            if case .managed(.marks, let inner) = token { return inner }
            return nil
        }).first else {
            return []
        }

        let effectiveInner = unwrapConflictUserContentIfPresent(marksInner, kind: .marks) ?? marksInner
        let lines = effectiveInner.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var parsed: [RecordingMark] = []
        let commentRegex = try? NSRegularExpression(
            pattern: #"<!--\s*memoflow:mark_id=([0-9A-Fa-f\-]+);kind=([A-Za-z_]+);start_ms=(\d+)(?:;end_ms=(\d+))?\s*-->"#
        )
        let linkPrefixRegex = try? NSRegularExpression(
            pattern: #"^-\s*\[([^\]]+)\](?:\([^)]*\))?\s*"#
        )

        var idx = 0
        while idx < lines.count {
            let line = lines[idx]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- "), !line.hasPrefix("  ") && !line.hasPrefix("\t") else {
                idx += 1
                continue
            }

            var markId: UUID?
            var kind: String = "bookmark"
            var startMs: Int?
            var endMs: Int?
            var workingLine = trimmed

            if let regex = commentRegex,
               let match = regex.firstMatch(in: workingLine, range: NSRange(workingLine.startIndex..<workingLine.endIndex, in: workingLine)) {
                if let r1 = Range(match.range(at: 1), in: workingLine) {
                    markId = UUID(uuidString: String(workingLine[r1]))
                }
                if let r2 = Range(match.range(at: 2), in: workingLine) {
                    kind = String(workingLine[r2])
                }
                if let r3 = Range(match.range(at: 3), in: workingLine) {
                    startMs = Int(workingLine[r3])
                }
                if match.range(at: 4).location != NSNotFound,
                   let r4 = Range(match.range(at: 4), in: workingLine) {
                    endMs = Int(workingLine[r4])
                }
                if let fullCommentRange = Range(match.range(at: 0), in: workingLine) {
                    workingLine.removeSubrange(fullCommentRange)
                }
            }

            var bracketLabel = ""
            if let lRegex = linkPrefixRegex,
               let m = lRegex.firstMatch(in: workingLine, range: NSRange(workingLine.startIndex..<workingLine.endIndex, in: workingLine)),
               let fullRange = Range(m.range(at: 0), in: workingLine) {
                if let labelRange = Range(m.range(at: 1), in: workingLine) {
                    bracketLabel = String(workingLine[labelRange])
                }
                workingLine.removeSubrange(fullRange)
            } else if workingLine.hasPrefix("- ") {
                workingLine = String(workingLine.dropFirst(2))
            }

            let quote = workingLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if startMs == nil {
                if let parsedMs = parseTimestampMs(fromLabel: bracketLabel) ?? parseTimestampMs(fromLabel: trimmed) {
                    startMs = parsedMs
                } else {
                    startMs = 0
                }
                if bracketLabel.contains("高亮") {
                    kind = "highlight"
                } else if bracketLabel.contains("批注") {
                    kind = "note"
                } else {
                    kind = "bookmark"
                }
            }

            // 读取紧随其后的缩进批注行（如 `  - 批注：xxx` 或 `  批注：xxx`）
            var noteLines: [String] = []
            var nextIdx = idx + 1
            while nextIdx < lines.count {
                let subRaw = lines[nextIdx]
                guard subRaw.hasPrefix("  ") || subRaw.hasPrefix("\t") else { break }
                var subTrimmed = subRaw.trimmingCharacters(in: .whitespaces)
                if subTrimmed.hasPrefix("- ") {
                    subTrimmed = String(subTrimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                }
                if subTrimmed.hasPrefix("批注：") {
                    subTrimmed = String(subTrimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                } else if subTrimmed.hasPrefix("批注:") {
                    subTrimmed = String(subTrimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                if !subTrimmed.isEmpty {
                    noteLines.append(subTrimmed)
                }
                nextIdx += 1
            }

            let finalStartMs = max(0, startMs ?? 0)
            let finalNote = noteLines.joined(separator: "\n")
            let finalId = markId ?? deterministicMarkUUID(recordingId: recordingId, startMs: finalStartMs, quote: quote)

            parsed.append(
                RecordingMark(
                    id: finalId,
                    startMs: finalStartMs,
                    endMs: endMs,
                    quote: quote,
                    note: finalNote,
                    kind: kind
                )
            )
            idx = nextIdx
        }

        return ObsidianScopedSyncSnapshot.normalizeMarks(parsed)
    }

    private static func parseTimestampMs(fromLabel text: String) -> Int? {
        if let regex = try? NSRegularExpression(pattern: #"(\d{2}):(\d{2}):(\d{2})"#),
           let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
           let rH = Range(m.range(at: 1), in: text),
           let rM = Range(m.range(at: 2), in: text),
           let rS = Range(m.range(at: 3), in: text),
           let hh = Int(text[rH]),
           let mm = Int(text[rM]),
           let ss = Int(text[rS]) {
            return ((hh * 3600) + (mm * 60) + ss) * 1000
        }
        if let regex = try? NSRegularExpression(pattern: #"(?<!\d)(\d{2}):(\d{2})(?!\d)"#),
           let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
           let rM = Range(m.range(at: 1), in: text),
           let rS = Range(m.range(at: 2), in: text),
           let mm = Int(text[rM]),
           let ss = Int(text[rS]) {
            return ((mm * 60) + ss) * 1000
        }
        return nil
    }

    private static func deterministicMarkUUID(recordingId: UUID, startMs: Int, quote: String) -> UUID {
        let seed = "memoflow-mark:\(recordingId.uuidString):\(startMs):\(quote)"
        let digest = Array(SHA256.hash(data: Data(seed.utf8)))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuidTuple: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuidTuple)
    }

    private static func summarizeScopedField(_ field: ObsidianScopedField, in snap: ObsidianScopedSyncSnapshot) -> String {
        switch field {
        case .userSupplement:
            return snap.userSupplement.isEmpty ? "（空）" : String(snap.userSupplement.prefix(80))
        case .manualTags:
            return snap.manualTags.isEmpty ? "（无手动标签）" : snap.manualTags.map { "#\($0)" }.joined(separator: " ")
        case .projectName:
            return snap.projectName.map { "[[\($0)]]" } ?? "（未关联项目）"
        case .marks:
            return snap.marks.isEmpty ? "（0 条标记）" : "共 \(snap.marks.count) 条书签/高亮批注"
        }
    }

    /// 执行四个受控字段的双向三路对账同步（含重命名/移动重定位、删除笔记不删原音频保护、冲突检测与防循环写入水位线）
    public func reconcileScopedFields(
        recording: Recording,
        note: Note,
        revision: NoteRevision,
        confirmedActions: [ConfirmedAction],
        segments: [TranscriptSegment],
        pendingDrafts: [ActionDraft],
        vaultRootURL: URL,
        targetSubfolder: String,
        existingBinding: ObsidianNoteBinding,
        backupsRootURL: URL
    ) throws -> ScopedReconcileOutcome {
        let fm = FileManager.default
        let cleanSubfolder = targetSubfolder.trimmingCharacters(in: .whitespacesAndNewlines)

        // Step 1: 定位笔记（支持重命名与跨目录移动）
        var resolvedURL: URL?
        var resolvedRelPath: String?
        var relocatedFrom: String?

        if !existingBinding.vaultRelativePath.isEmpty,
           let validRel = try? Self.validateSafeRelativePath(existingBinding.vaultRelativePath) {
            let candidate = vaultRootURL.appendingPathComponent(validRel)
            try verifyCloudDownloaded(fileURL: candidate, relativePath: validRel)
            if fm.fileExists(atPath: candidate.path),
               let text = try? Self.readCoordinatedUTF8(at: candidate),
               Self.extractRecordingId(from: text) == recording.id {
                resolvedURL = candidate
                resolvedRelPath = validRel
            }
        }

        if resolvedURL == nil {
            if let relocated = try findNoteByRecordingId(
                recordingId: recording.id,
                vaultRootURL: vaultRootURL,
                preferredSubfolder: cleanSubfolder
            ) {
                if !existingBinding.vaultRelativePath.isEmpty && existingBinding.vaultRelativePath != relocated.relativePath {
                    relocatedFrom = existingBinding.vaultRelativePath
                }
                resolvedURL = relocated.fileURL
                resolvedRelPath = relocated.relativePath
            }
        }

        // Step 2: 若笔记已在 Obsidian 被删除 -> 仅更新关联状态为 missingInVault，绝不删除原音频或本地记录
        guard let targetURL = resolvedURL, let targetRelPath = resolvedRelPath else {
            var missingBinding = existingBinding
            missingBinding.status = .missingInVault
            missingBinding.lastErrorMessage = "Obsidian 中的对应笔记已被移除。本地录音与原音频完好保留，可随时重新导出生成笔记。"
            return ScopedReconcileOutcome(
                updatedUserSupplement: nil,
                updatedManualTags: nil,
                shouldUpdateProjectName: false,
                updatedProjectName: nil,
                updatedMarks: nil,
                binding: missingBinding,
                didWriteToDisk: false,
                didPullToMemoFlow: false,
                noteWasDeletedInVault: true,
                relocatedFromOldPath: nil
            )
        }

        // Step 3: 读取当前磁盘内容，检查防循环水位线（SHA-256 + ScopedSnapshot 双重短路）
        try verifyCloudDownloaded(fileURL: targetURL, relativePath: targetRelPath)
        let diskData = try Data(contentsOf: targetURL)
        let diskSHA = Self.sha256Hex(of: diskData)
        guard let diskText = String(data: diskData, encoding: .utf8) else {
            throw ObsidianSyncError.fileOperationFailed("笔记文件不是有效的 UTF-8 编码")
        }

        let localSnap = ObsidianScopedSyncSnapshot.from(recording: recording, note: note)
        if let baseSnap = existingBinding.lastScopedSnapshot,
           existingBinding.lastSyncedFileSHA256 == diskSHA,
           localSnap == baseSnap,
           existingBinding.scopedFieldConflicts.isEmpty {
            var updatedBinding = existingBinding
            updatedBinding.vaultRelativePath = targetRelPath
            updatedBinding.lastKnownFileName = targetURL.lastPathComponent
            if updatedBinding.status == .missingInVault {
                updatedBinding.status = updatedBinding.conflicts.isEmpty ? .synced : .hasConflict
            }
            return ScopedReconcileOutcome(
                updatedUserSupplement: nil,
                updatedManualTags: nil,
                shouldUpdateProjectName: false,
                updatedProjectName: nil,
                updatedMarks: nil,
                binding: updatedBinding,
                didWriteToDisk: false,
                didPullToMemoFlow: false,
                noteWasDeletedInVault: false,
                relocatedFromOldPath: relocatedFrom
            )
        }

        // Step 4: 逐字段执行三路比较（Base vs MemoFlow Local vs Obsidian Disk）
        let (diskYamlLines, _) = Self.splitFrontmatterAndBody(diskText)
        let diskYamlMap = Self.parseSimpleYAMLKeyValues(from: diskYamlLines ?? [])
        let diskRelAudio = MarkdownExporterService.sanitizedVaultRelativeAudioPath(diskYamlMap["audio_attachment"])
        let pulledAudioRelPath: String? = (diskRelAudio != nil && diskRelAudio != recording.vaultAudioRelativePath) ? diskRelAudio : nil

        let diskSnap = Self.extractScopedSnapshot(from: diskText, recordingId: recording.id)
        let baseSnap = existingBinding.lastScopedSnapshot ?? diskSnap

        var pullSupplement: String?
        var pullTags: [String]?
        var shouldPullProject = false
        var pullProjectValue: String?
        var pullMarks: [RecordingMark]?

        var pushSupplementToDisk: String?
        var pushTagsToDisk: [String]?
        var pushProjectToDisk = false
        var pushMarksToDisk = false

        var resolvedSnap = baseSnap
        var newScopedConflicts: [ObsidianScopedFieldConflict] = []

        // 4a. userSupplement
        if diskSnap.userSupplement == localSnap.userSupplement {
            resolvedSnap.userSupplement = localSnap.userSupplement
        } else if diskSnap.userSupplement != baseSnap.userSupplement && localSnap.userSupplement == baseSnap.userSupplement {
            pullSupplement = diskSnap.userSupplement
            resolvedSnap.userSupplement = diskSnap.userSupplement
        } else if localSnap.userSupplement != baseSnap.userSupplement && diskSnap.userSupplement == baseSnap.userSupplement {
            pushSupplementToDisk = localSnap.userSupplement
            resolvedSnap.userSupplement = localSnap.userSupplement
        } else {
            newScopedConflicts.append(
                ObsidianScopedFieldConflict(
                    field: .userSupplement,
                    memoFlowSummary: Self.summarizeScopedField(.userSupplement, in: localSnap),
                    obsidianSummary: Self.summarizeScopedField(.userSupplement, in: diskSnap),
                    memoFlowSnapshot: localSnap,
                    obsidianSnapshot: diskSnap
                )
            )
        }

        // 4b. manualTags
        if diskSnap.manualTags == localSnap.manualTags {
            resolvedSnap.manualTags = localSnap.manualTags
        } else if diskSnap.manualTags != baseSnap.manualTags && localSnap.manualTags == baseSnap.manualTags {
            pullTags = diskSnap.manualTags
            resolvedSnap.manualTags = diskSnap.manualTags
        } else if localSnap.manualTags != baseSnap.manualTags && diskSnap.manualTags == baseSnap.manualTags {
            pushTagsToDisk = localSnap.manualTags
            resolvedSnap.manualTags = localSnap.manualTags
        } else {
            newScopedConflicts.append(
                ObsidianScopedFieldConflict(
                    field: .manualTags,
                    memoFlowSummary: Self.summarizeScopedField(.manualTags, in: localSnap),
                    obsidianSummary: Self.summarizeScopedField(.manualTags, in: diskSnap),
                    memoFlowSnapshot: localSnap,
                    obsidianSnapshot: diskSnap
                )
            )
        }

        // 4c. projectName
        if diskSnap.projectName == localSnap.projectName {
            resolvedSnap.projectName = localSnap.projectName
        } else if diskSnap.projectName != baseSnap.projectName && localSnap.projectName == baseSnap.projectName {
            shouldPullProject = true
            pullProjectValue = diskSnap.projectName
            resolvedSnap.projectName = diskSnap.projectName
        } else if localSnap.projectName != baseSnap.projectName && diskSnap.projectName == baseSnap.projectName {
            pushProjectToDisk = true
            resolvedSnap.projectName = localSnap.projectName
        } else {
            newScopedConflicts.append(
                ObsidianScopedFieldConflict(
                    field: .projectName,
                    memoFlowSummary: Self.summarizeScopedField(.projectName, in: localSnap),
                    obsidianSummary: Self.summarizeScopedField(.projectName, in: diskSnap),
                    memoFlowSnapshot: localSnap,
                    obsidianSnapshot: diskSnap
                )
            )
        }

        // 4d. marks
        if diskSnap.marks == localSnap.marks {
            resolvedSnap.marks = localSnap.marks
        } else if diskSnap.marks != baseSnap.marks && localSnap.marks == baseSnap.marks {
            pullMarks = diskSnap.marks
            resolvedSnap.marks = diskSnap.marks
        } else if localSnap.marks != baseSnap.marks && diskSnap.marks == baseSnap.marks {
            pushMarksToDisk = true
            resolvedSnap.marks = localSnap.marks
        } else {
            newScopedConflicts.append(
                ObsidianScopedFieldConflict(
                    field: .marks,
                    memoFlowSummary: Self.summarizeScopedField(.marks, in: localSnap),
                    obsidianSummary: Self.summarizeScopedField(.marks, in: diskSnap),
                    memoFlowSnapshot: localSnap,
                    obsidianSnapshot: diskSnap
                )
            )
        }

        let didPull = (pullSupplement != nil || pullTags != nil || shouldPullProject || pullMarks != nil || pulledAudioRelPath != nil)
        let needsDiskWrite = (pushSupplementToDisk != nil || pushTagsToDisk != nil || pushProjectToDisk || pushMarksToDisk)

        // Step 5: 若无需向 Obsidian 推送字段（例如仅从 Obsidian 拉取回 MemoFlow，或双方实质相等），绝不重写磁盘文件，彻底杜绝循环触发文件监听！
        if !needsDiskWrite {
            var nextBinding = existingBinding
            nextBinding.vaultRelativePath = targetRelPath
            nextBinding.lastKnownFileName = targetURL.lastPathComponent
            nextBinding.scopedFieldConflicts = newScopedConflicts
            if newScopedConflicts.isEmpty {
                nextBinding.lastScopedSnapshot = resolvedSnap
                nextBinding.lastSyncedFileSHA256 = diskSHA
                // 若从 Obsidian 拉取了 marks 更新，同步刷新 marks 受控区块基准摘要以免后续误判冲突
                if pullMarks != nil {
                    let tokens = Self.parseBodyTokens(Self.splitFrontmatterAndBody(diskText).body)
                    for tok in tokens {
                        if case .managed(.marks, let inner) = tok {
                            nextBinding.managedBlockDigests[ObsidianManagedBlockKind.marks.rawValue] = Self.normalizedBlockDigest(inner)
                            nextBinding.managedBlockSnapshots[ObsidianManagedBlockKind.marks.rawValue] = inner
                        }
                    }
                }
            }
            nextBinding.status = (!nextBinding.conflicts.isEmpty || !newScopedConflicts.isEmpty) ? .hasConflict : .synced
            nextBinding.lastErrorMessage = nil

            return ScopedReconcileOutcome(
                updatedUserSupplement: pullSupplement,
                updatedManualTags: pullTags,
                shouldUpdateProjectName: shouldPullProject,
                updatedProjectName: pullProjectValue,
                updatedMarks: pullMarks,
                updatedVaultAudioRelativePath: pulledAudioRelPath,
                binding: nextBinding,
                didWriteToDisk: false,
                didPullToMemoFlow: didPull,
                noteWasDeletedInVault: false,
                relocatedFromOldPath: relocatedFrom
            )
        }

        // Step 6: 构造已合并非冲突拉取项的记录与笔记副本，将 MemoFlow 变更安全推送回 Obsidian（若有单字段冲突，保留磁盘侧冲突字段原状！）
        var effectiveRec = recording
        let marksConflictExists = newScopedConflicts.contains { $0.field == .marks }
        if marksConflictExists {
            effectiveRec.marks = diskSnap.marks
        } else {
            effectiveRec.marks = resolvedSnap.marks
        }

        var effectiveNote = note
        let suppConflictExists = newScopedConflicts.contains { $0.field == .userSupplement }
        let tagsConflictExists = newScopedConflicts.contains { $0.field == .manualTags }
        let projConflictExists = newScopedConflicts.contains { $0.field == .projectName }

        effectiveNote.userSupplement = suppConflictExists ? diskSnap.userSupplement : resolvedSnap.userSupplement
        effectiveNote.manualTags = tagsConflictExists ? diskSnap.manualTags : resolvedSnap.manualTags
        effectiveNote.projectName = projConflictExists ? diskSnap.projectName : resolvedSnap.projectName

        var prePushBinding = existingBinding
        if pushMarksToDisk && !marksConflictExists {
            // MemoFlow 侧主动更新了 marks 且磁盘未改，对齐基准摘要以便原位更新 marks 区块
            let tokens = Self.parseBodyTokens(Self.splitFrontmatterAndBody(diskText).body)
            for tok in tokens {
                if case .managed(.marks, let inner) = tok {
                    prePushBinding.managedBlockDigests[ObsidianManagedBlockKind.marks.rawValue] = Self.normalizedBlockDigest(inner)
                }
            }
        }
        if pushProjectToDisk && !projConflictExists {
            let tokens = Self.parseBodyTokens(Self.splitFrontmatterAndBody(diskText).body)
            for tok in tokens {
                if case .managed(.header, let inner) = tok {
                    prePushBinding.managedBlockDigests[ObsidianManagedBlockKind.header.rawValue] = Self.normalizedBlockDigest(inner)
                }
            }
        }

        let newBlocks = MarkdownExporterService.renderManagedBlocks(
            recording: effectiveRec,
            note: effectiveNote,
            revision: revision,
            confirmedActions: confirmedActions,
            segments: segments,
            pendingDrafts: pendingDrafts
        )

        var coordError: NSError?
        var writeResult: Result<ObsidianNoteBinding, Error>?

        NSFileCoordinator().coordinate(writingItemAt: targetURL, options: .forMerging, error: &coordError) { coordinatedURL in
            writeResult = Result {
                let rawData = try Data(contentsOf: coordinatedURL)
                guard let currentText = String(data: rawData, encoding: .utf8) else {
                    throw ObsidianSyncError.fileOperationFailed("UTF-8 解码失败")
                }

                let backupURL = try Self.savePreWriteBackup(
                    originalData: rawData,
                    recordingId: recording.id,
                    fileName: coordinatedURL.lastPathComponent,
                    backupsRootURL: backupsRootURL
                )

                let merged = Self.mergeExistingMarkdown(
                    existingMarkdown: currentText,
                    recording: effectiveRec,
                    note: effectiveNote,
                    revision: revision,
                    segments: segments,
                    newBlocks: newBlocks,
                    existingBinding: prePushBinding,
                    isAssociatingLegacy: false,
                    overrideExactUserTags: tagsConflictExists ? diskSnap.manualTags : resolvedSnap.manualTags,
                    useExactNoteProject: !projConflictExists,
                    overrideUserSupplement: suppConflictExists ? nil : resolvedSnap.userSupplement
                )

                let outData = Data(merged.markdown.utf8)
                try outData.write(to: coordinatedURL, options: .atomic)
                let modDate = (try? coordinatedURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

                let hasConflict = !merged.conflicts.isEmpty || !newScopedConflicts.isEmpty
                return ObsidianNoteBinding(
                    recordingId: recording.id,
                    vaultRelativePath: targetRelPath,
                    lastKnownFileName: coordinatedURL.lastPathComponent,
                    lastExportedRevisionId: revision.id,
                    lastExportedAt: Date(),
                    lastSyncedFileSHA256: Self.sha256Hex(of: outData),
                    lastSyncedModificationDate: modDate,
                    managedBlockDigests: merged.updatedDigests,
                    managedBlockSnapshots: merged.updatedSnapshots,
                    status: hasConflict ? .hasConflict : .synced,
                    pendingLegacyCandidatePaths: [],
                    conflicts: merged.conflicts,
                    lastScopedSnapshot: newScopedConflicts.isEmpty ? resolvedSnap : baseSnap,
                    scopedFieldConflicts: newScopedConflicts,
                    lastBackupFilePath: backupURL.path,
                    lastErrorMessage: nil
                )
            }
        }

        if let coordError {
            throw ObsidianSyncError.fileOperationFailed(coordError.localizedDescription)
        }
        guard let writeResult else {
            throw ObsidianSyncError.fileOperationFailed("双向字段写入未完成")
        }

        let updatedBinding = try writeResult.get()
        return ScopedReconcileOutcome(
            updatedUserSupplement: pullSupplement,
            updatedManualTags: pullTags,
            shouldUpdateProjectName: shouldPullProject,
            updatedProjectName: pullProjectValue,
            updatedMarks: pullMarks,
            updatedVaultAudioRelativePath: pulledAudioRelPath,
            binding: updatedBinding,
            didWriteToDisk: true,
            didPullToMemoFlow: didPull,
            noteWasDeletedInVault: false,
            relocatedFromOldPath: relocatedFrom
        )
    }

    /// 解决单个受控字段的双向同步冲突（保留 Obsidian 版本 / 采用 MemoFlow 版本 / 合并双方）
    public func resolveScopedFieldConflict(
        field: ObsidianScopedField,
        choice: ObsidianConflictResolutionChoice,
        recording: Recording,
        note: Note,
        revision: NoteRevision,
        confirmedActions: [ConfirmedAction],
        segments: [TranscriptSegment],
        pendingDrafts: [ActionDraft],
        vaultRootURL: URL,
        binding: ObsidianNoteBinding,
        backupsRootURL: URL
    ) throws -> (resolvedSnapshot: ObsidianScopedSyncSnapshot, binding: ObsidianNoteBinding) {
        guard let conflict = binding.scopedFieldConflicts.first(where: { $0.field == field }) else {
            return (ObsidianScopedSyncSnapshot.from(recording: recording, note: note), binding)
        }

        let safeRel = try Self.validateSafeRelativePath(binding.vaultRelativePath)
        let targetURL = vaultRootURL.appendingPathComponent(safeRel)
        try verifyCloudDownloaded(fileURL: targetURL, relativePath: safeRel)

        var nextSnap = ObsidianScopedSyncSnapshot.from(recording: recording, note: note)
        let mSnap = conflict.memoFlowSnapshot
        let oSnap = conflict.obsidianSnapshot

        switch field {
        case .userSupplement:
            switch choice {
            case .keepObsidianUserVersion:
                nextSnap.userSupplement = oSnap.userSupplement
            case .adoptMemoFlowVersion:
                nextSnap.userSupplement = mSnap.userSupplement
            case .keepBothMerged:
                let parts = [oSnap.userSupplement, mSnap.userSupplement].filter { !$0.isEmpty }
                nextSnap.userSupplement = parts.joined(separator: "\n\n")
            }

        case .manualTags:
            switch choice {
            case .keepObsidianUserVersion:
                nextSnap.manualTags = oSnap.manualTags
            case .adoptMemoFlowVersion:
                nextSnap.manualTags = mSnap.manualTags
            case .keepBothMerged:
                nextSnap.manualTags = ObsidianScopedSyncSnapshot.normalizeTags(oSnap.manualTags + mSnap.manualTags)
            }

        case .projectName:
            switch choice {
            case .keepObsidianUserVersion:
                nextSnap.projectName = oSnap.projectName
            case .adoptMemoFlowVersion, .keepBothMerged:
                nextSnap.projectName = mSnap.projectName ?? oSnap.projectName
            }

        case .marks:
            switch choice {
            case .keepObsidianUserVersion:
                nextSnap.marks = oSnap.marks
            case .adoptMemoFlowVersion:
                nextSnap.marks = mSnap.marks
            case .keepBothMerged:
                var byId: [UUID: RecordingMark] = [:]
                for m in oSnap.marks { byId[m.id] = m }
                for m in mSnap.marks where byId[m.id] == nil { byId[m.id] = m }
                nextSnap.marks = ObsidianScopedSyncSnapshot.normalizeMarks(Array(byId.values))
            }
        }

        var updatedRec = recording
        updatedRec.marks = nextSnap.marks

        var updatedNote = note
        updatedNote.userSupplement = nextSnap.userSupplement
        updatedNote.manualTags = nextSnap.manualTags
        updatedNote.projectName = nextSnap.projectName

        let newBlocks = MarkdownExporterService.renderManagedBlocks(
            recording: updatedRec,
            note: updatedNote,
            revision: revision,
            confirmedActions: confirmedActions,
            segments: segments,
            pendingDrafts: pendingDrafts
        )

        var coordError: NSError?
        var writeResult: Result<ObsidianNoteBinding, Error>?

        NSFileCoordinator().coordinate(writingItemAt: targetURL, options: .forMerging, error: &coordError) { coordinatedURL in
            writeResult = Result {
                let rawData = try Data(contentsOf: coordinatedURL)
                guard let currentText = String(data: rawData, encoding: .utf8) else {
                    throw ObsidianSyncError.fileOperationFailed("UTF-8 解码失败")
                }

                let backupURL = try Self.savePreWriteBackup(
                    originalData: rawData,
                    recordingId: recording.id,
                    fileName: coordinatedURL.lastPathComponent,
                    backupsRootURL: backupsRootURL
                )

                var alignedBinding = binding
                let tokens = Self.parseBodyTokens(Self.splitFrontmatterAndBody(currentText).body)
                for tok in tokens {
                    if case .managed(let k, let inner) = tok, (k == .marks || k == .header) {
                        alignedBinding.managedBlockDigests[k.rawValue] = Self.normalizedBlockDigest(inner)
                    }
                }

                let merged = Self.mergeExistingMarkdown(
                    existingMarkdown: currentText,
                    recording: updatedRec,
                    note: updatedNote,
                    revision: revision,
                    segments: segments,
                    newBlocks: newBlocks,
                    existingBinding: alignedBinding,
                    isAssociatingLegacy: false,
                    overrideExactUserTags: nextSnap.manualTags,
                    useExactNoteProject: true,
                    overrideUserSupplement: nextSnap.userSupplement
                )

                let outData = Data(merged.markdown.utf8)
                try outData.write(to: coordinatedURL, options: .atomic)
                let modDate = (try? coordinatedURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

                var remainingScoped = binding.scopedFieldConflicts
                remainingScoped.removeAll { $0.field == field }
                let hasAnyConflict = !merged.conflicts.isEmpty || !remainingScoped.isEmpty

                return ObsidianNoteBinding(
                    recordingId: recording.id,
                    vaultRelativePath: safeRel,
                    lastKnownFileName: coordinatedURL.lastPathComponent,
                    lastExportedRevisionId: revision.id,
                    lastExportedAt: Date(),
                    lastSyncedFileSHA256: Self.sha256Hex(of: outData),
                    lastSyncedModificationDate: modDate,
                    managedBlockDigests: merged.updatedDigests,
                    managedBlockSnapshots: merged.updatedSnapshots,
                    status: hasAnyConflict ? .hasConflict : .synced,
                    pendingLegacyCandidatePaths: [],
                    conflicts: merged.conflicts,
                    lastScopedSnapshot: remainingScoped.isEmpty ? nextSnap : binding.lastScopedSnapshot,
                    scopedFieldConflicts: remainingScoped,
                    lastBackupFilePath: backupURL.path,
                    lastErrorMessage: nil
                )
            }
        }

        if let coordError {
            throw ObsidianSyncError.fileOperationFailed(coordError.localizedDescription)
        }
        guard let writeResult else {
            throw ObsidianSyncError.fileOperationFailed("字段冲突解决未完成")
        }

        return (nextSnap, try writeResult.get())
    }

    // MARK: - P2-7 Cross-Device Audio Attachment & Vault Hydration (iPhone <-> Mac)

    public struct HydratedVaultRecord: Sendable {
        public let recording: Recording
        public let note: Note
        public let revision: NoteRevision
        public let segments: [TranscriptSegment]
        public let binding: ObsidianNoteBinding
    }

    /// 将当前设备原音频作为相对路径附件同步到 Obsidian 笔记库附件目录（避免使用仅 Mac 有效的绝对路径）
    public func syncAudioAttachmentToVault(
        localAudioURL: URL,
        recordingId: UUID,
        vaultRootURL: URL,
        attachmentSubfolder: String
    ) throws -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: localAudioURL.path) else {
            throw ObsidianSyncError.fileOperationFailed("当前设备不存在本地原音频文件（\(localAudioURL.lastPathComponent)），无法同步到笔记库。")
        }

        let safeSub = try Self.validateSafeRelativePath(attachmentSubfolder)
        let ext = localAudioURL.pathExtension.isEmpty ? "m4a" : localAudioURL.pathExtension.lowercased()
        let attachmentFileName = "rec_\(recordingId.uuidString).\(ext)"
        let relativeAttachmentPath = "\(safeSub)/\(attachmentFileName)"
        let destinationURL = vaultRootURL.appendingPathComponent(relativeAttachmentPath)

        try fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let sourceData = try Data(contentsOf: localAudioURL)
        if fm.fileExists(atPath: destinationURL.path),
           let existingData = try? Data(contentsOf: destinationURL),
           existingData == sourceData {
            return relativeAttachmentPath
        }

        var coordError: NSError?
        var writeErr: Error?
        NSFileCoordinator().coordinate(writingItemAt: destinationURL, options: .forReplacing, error: &coordError) { coordinatedURL in
            do {
                try sourceData.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeErr = error
            }
        }
        if let err = coordError ?? writeErr {
            throw ObsidianSyncError.fileOperationFailed(err.localizedDescription)
        }
        return relativeAttachmentPath
    }

    /// 检查笔记库附件目录中的跨端音频是否已到达当前设备并完成 iCloud 下载
    public func inspectVaultAudioAttachment(
        recording: Recording,
        vaultRootURL: URL,
        attachmentSubfolder: String
    ) -> AudioAvailabilityState? {
        let fm = FileManager.default
        var candidateRelPaths: [String] = []
        if let explicitRel = MarkdownExporterService.sanitizedVaultRelativeAudioPath(recording.vaultAudioRelativePath) {
            candidateRelPaths.append(explicitRel)
        }
        if let cleanSub = try? Self.validateSafeRelativePath(attachmentSubfolder) {
            if !recording.localAudioFileName.isEmpty {
                let byLocalName = "\(cleanSub)/\(recording.localAudioFileName)"
                if !candidateRelPaths.contains(byLocalName) {
                    candidateRelPaths.append(byLocalName)
                }
            }
            for ext in ["m4a", "wav"] {
                let byId = "\(cleanSub)/rec_\(recording.id.uuidString).\(ext)"
                if !candidateRelPaths.contains(byId) {
                    candidateRelPaths.append(byId)
                }
            }
        }

        for rel in candidateRelPaths {
            let url = vaultRootURL.appendingPathComponent(rel)
            let normalizedRel = Self.normalizeRelativePath(rel)
            if simulatedUndownloadedRelativePaths.contains(normalizedRel) {
                try? fm.startDownloadingUbiquitousItem(at: url)
                return .cloudNotDownloaded(relativePath: normalizedRel)
            }
            if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
               values.isUbiquitousItem == true,
               values.ubiquitousItemDownloadingStatus == .notDownloaded {
                try? fm.startDownloadingUbiquitousItem(at: url)
                return .cloudNotDownloaded(relativePath: normalizedRel)
            }
            if fm.fileExists(atPath: url.path) {
                return .availableInVaultAttachment(fileURL: url, relativePath: normalizedRel)
            }
        }
        return nil
    }

    /// 从笔记库扫描另一端（iPhone 或 Mac）已导出的带 `recording_id` 笔记，在本机尚无该录音记录时自动载入跨端记录与相对附件关联
    public func hydrateMissingRecordingsFromVault(
        vaultRootURL: URL,
        preferredSubfolder: String,
        existingRecordingIds: Set<UUID>
    ) throws -> [HydratedVaultRecord] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
            .fileSizeKey, .ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey,
            .contentModificationDateKey
        ]
        guard let enumerator = fm.enumerator(
            at: vaultRootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var hydrated: [HydratedVaultRecord] = []
        var seenIds = existingRecordingIds

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            let relPath = Self.relativePath(of: fileURL, inside: vaultRootURL)
            if relPath.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard fileURL.pathExtension.lowercased() == "md", values.isRegularFile == true else { continue }

            let normalizedRel = Self.normalizeRelativePath(relPath)
            if simulatedUndownloadedRelativePaths.contains(normalizedRel) ||
                (values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded) {
                try? fm.startDownloadingUbiquitousItem(at: fileURL)
                continue
            }

            guard let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data, encoding: .utf8),
                  let recId = Self.extractRecordingId(from: text),
                  !seenIds.contains(recId) else {
                continue
            }
            seenIds.insert(recId)

            let record = Self.parseHydratedRecord(
                from: text,
                rawData: data,
                recordingId: recId,
                relativePath: normalizedRel,
                fileName: fileURL.lastPathComponent,
                modificationDate: values.contentModificationDate
            )
            hydrated.append(record)
        }

        return hydrated
    }

    private static func parseHydratedRecord(
        from markdown: String,
        rawData: Data,
        recordingId: UUID,
        relativePath: String,
        fileName: String,
        modificationDate: Date?
    ) -> HydratedVaultRecord {
        let (frontmatterLines, body) = splitFrontmatterAndBody(markdown)
        let yamlMap = parseSimpleYAMLKeyValues(from: frontmatterLines ?? [])
        let scoped = extractScopedSnapshot(from: markdown, recordingId: recordingId)

        let title = yamlMap["title"]?.isEmpty == false ? yamlMap["title"]! : (fileName as NSString).deletingPathExtension
        let tzId = yamlMap["timezone"] ?? TimeZone.current.identifier
        let durationSeconds = Double(yamlMap["duration_seconds"] ?? "") ?? 0
        let createdAt: Date = {
            if let isoStr = yamlMap["recorded_at"],
               let d = ISO8601DateFormatter().date(from: isoStr) {
                return d
            }
            return modificationDate ?? Date()
        }()
        let isReviewed = (yamlMap["transcript_review_status"] == "reviewed")
        let relAudio = MarkdownExporterService.sanitizedVaultRelativeAudioPath(yamlMap["audio_attachment"])
        let ext = (relAudio as NSString?)?.pathExtension
        let localFileName = "rec_\(recordingId.uuidString).\(ext?.isEmpty == false ? ext! : "m4a")"
        let mode: NoteMode = (yamlMap["mode"] == "会议") ? .meetingNote : .quickNote

        let tokens = parseBodyTokens(body)
        var blockMap: [ObsidianManagedBlockKind: String] = [:]
        var digests: [String: String] = [:]
        for tok in tokens {
            if case .managed(let kind, let inner) = tok {
                blockMap[kind] = inner
                digests[kind.rawValue] = normalizedBlockDigest(inner)
            }
        }

        let summaryRaw = blockMap[.summary] ?? ""
        let cleanedSummary = summaryRaw
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("## ") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let segments = parseHydratedSegments(from: blockMap[.transcript] ?? "", recordingId: recordingId, fallbackDurationMs: Int(durationSeconds * 1000))

        var rec = Recording(
            id: recordingId,
            title: title,
            createdAt: createdAt,
            recordedTimeZoneIdentifier: tzId,
            duration: durationSeconds,
            localAudioFileName: localFileName,
            processingStatus: .completed,
            isTranscriptReviewed: isReviewed,
            vaultAudioRelativePath: relAudio
        )
        rec.marks = scoped.marks

        let revId = UUID()
        let noteId = UUID()
        let note = Note(
            id: noteId,
            recordingId: recordingId,
            mode: mode,
            projectName: scoped.projectName,
            userSupplement: scoped.userSupplement,
            manualTags: scoped.manualTags,
            editedAt: createdAt,
            currentRevisionId: revId
        )

        let structured = StructuredNoteContent(
            suggestedTitle: title,
            summaryOrShortNote: cleanedSummary.isEmpty ? title : cleanedSummary
        )
        let revision = NoteRevision(
            id: revId,
            noteId: noteId,
            mode: mode,
            generatedAt: createdAt,
            content: structured,
            origin: .ai,
            sourceTranscriptDigest: NoteVersionProvenance.transcriptDigest(for: segments),
            basedOnTranscriptReviewed: isReviewed
        )

        let snapshotsByKey = Dictionary(uniqueKeysWithValues: blockMap.map { ($0.key.rawValue, $0.value) })
        let binding = ObsidianNoteBinding(
            recordingId: recordingId,
            vaultRelativePath: relativePath,
            lastKnownFileName: fileName,
            lastExportedRevisionId: revId,
            lastExportedAt: modificationDate ?? Date(),
            lastSyncedFileSHA256: sha256Hex(of: rawData),
            lastSyncedModificationDate: modificationDate,
            managedBlockDigests: digests,
            managedBlockSnapshots: snapshotsByKey,
            status: .synced,
            lastScopedSnapshot: scoped,
            scopedFieldConflicts: []
        )

        return HydratedVaultRecord(
            recording: rec,
            note: note,
            revision: revision,
            segments: segments,
            binding: binding
        )
    }

    private static func parseSimpleYAMLKeyValues(from lines: [String]) -> [String: String] {
        var map: [String: String] = [:]
        for line in lines {
            guard !line.hasPrefix(" "), !line.hasPrefix("\t"), let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            var val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                val = String(val.dropFirst().dropLast())
            }
            map[key] = val
        }
        return map
    }

    private static func parseHydratedSegments(
        from transcriptBlock: String,
        recordingId: UUID,
        fallbackDurationMs: Int
    ) -> [TranscriptSegment] {
        let lines = transcriptBlock.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var segments: [TranscriptSegment] = []
        let lineRegex = try? NSRegularExpression(
            pattern: #"^-\s*\[([^\]]+)\](?:\([^)]*\))?\s*(?:\*\*([^*]+)\*\*:\s*)?(.*)$"#
        )

        for (index, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { continue }
            guard let regex = lineRegex,
                  let m = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)),
                  let labelRange = Range(m.range(at: 1), in: trimmed),
                  let textRange = Range(m.range(at: 3), in: trimmed) else {
                continue
            }
            let label = String(trimmed[labelRange])
            let speaker: String? = (m.range(at: 2).location != NSNotFound)
                ? Range(m.range(at: 2), in: trimmed).map { String(trimmed[$0]) }
                : nil
            let text = String(trimmed[textRange]).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            let startMs = parseTimestampMs(fromLabel: label) ?? (index * 5000)
            let endMs = max(startMs + 2000, min(max(startMs + 5000, fallbackDurationMs), startMs + 5000))
            let isEst = label.contains("约")

            segments.append(
                TranscriptSegment(
                    id: "hydrated_\(recordingId.uuidString)_\(index)",
                    recordingId: recordingId,
                    startMs: startMs,
                    endMs: endMs,
                    text: text,
                    speakerName: speaker,
                    timingIsEstimated: isEst ? true : nil
                )
            )
        }
        return segments
    }
}
