import Foundation

public struct KnowledgeReference: Codable, Equatable, Sendable {
    public var path: String
    public var excerpt: String
}

public enum VaultAccess {
    public static func bookmark(for url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        return try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    public static func resolve(_ preferences: MemoFlowPreferences) throws -> URL {
        guard let data = preferences.obsidianVaultBookmark else {
            throw NSError(domain: "MemoFlowVault", code: 1, userInfo: [NSLocalizedDescriptionKey: "请在设置中重新选择 Obsidian 知识库文件夹以授权访问。"])
        }
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
        #else
        let options: URL.BookmarkResolutionOptions = [.withoutUI]
        #endif
        let url = try URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale else {
            throw NSError(domain: "MemoFlowVault", code: 2, userInfo: [NSLocalizedDescriptionKey: "知识库授权已过期，请重新选择文件夹。"])
        }
        return url
    }
}

/// 设备内的有界关键词索引；不调用网络模型，也不上传整个库。
/// 每次刷新替换完整快照，删除、改名、排除的文件不会留在检索结果中。
public actor ObsidianKnowledgeService {
    public struct ScanResult: Sendable {
        public var count: Int
        public var skipped: Int
        public var references: [KnowledgeReference]
    }
    private struct Entry {
        var modified: Date?
        var size: Int
        var chunks: [String]
    }
    private var entries: [String: Entry] = [:]
    private var configuration: MemoFlowPreferences?

    public init() {}

    public func clear() {
        entries.removeAll()
        configuration = nil
    }

    public static func isExcluded(_ path: String, folders: [String]) -> Bool {
        let parts = path.split(separator: "/")
        if parts.contains(where: { $0.hasPrefix(".") }) { return true }
        return folders.contains { folder in
            let clean = folder.trimmingCharacters(in: CharacterSet(charactersIn: " /\n\r"))
            return !clean.isEmpty && (path == clean || path.hasPrefix(clean + "/"))
        }
    }

    public static func terms(_ text: String) -> Set<String> {
        let lower = text.lowercased()
        var terms = Set(lower.components(separatedBy: .alphanumerics.inverted).filter { $0.count >= 2 })
        let chars = Array(lower)
        if chars.count > 1 {
            for i in 0..<(chars.count - 1) {
                if chars[i].unicodeScalars.allSatisfy({ (0x3400...0x9FFF).contains($0.value) }),
                   chars[i + 1].unicodeScalars.allSatisfy({ (0x3400...0x9FFF).contains($0.value) }) {
                    terms.insert(String(chars[i...i + 1]))
                }
            }
        }
        return terms.subtracting(["我们", "这个", "那个", "可以", "就是", "然后", "需要", "一个", "the", "and", "that", "with"])
    }

    public static func retrieve(query: String, candidates: [KnowledgeReference]) -> [KnowledgeReference] {
        let queryTerms = terms(String(query.prefix(30000)))
        guard !queryTerms.isEmpty else { return [] }
        let ranked = candidates.compactMap { item -> (KnowledgeReference, Int)? in
            let bodyScore = terms(item.excerpt).intersection(queryTerms).count
            let titleScore = terms(item.path).intersection(queryTerms).count
            let score = bodyScore + 3 * titleScore
            return score >= 2 ? (item, score) : nil
        }.sorted { $0.1 == $1.1 ? $0.0.path < $1.0.path : $0.1 > $1.1 }
        var seen = Set<String>()
        return Array(ranked.compactMap { item in
            seen.insert(item.0.path).inserted ? item.0 : nil
        }.prefix(4))
    }

    public func refresh(preferences: MemoFlowPreferences, query: String = "") throws -> ScanResult {
        guard preferences.knowledgeContextEnabled else { clear(); return ScanResult(count: 0, skipped: 0, references: []) }
        if configuration != preferences { entries.removeAll(); configuration = preferences }
        let root = try VaultAccess.resolve(preferences)
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .ubiquitousItemDownloadingStatusKey]
        var next: [String: Entry] = [:]
        var skipped = 0
        var bytes = 0
        var coordinationError: NSError?
        var readError: Error?
        let excluded = preferences.knowledgeExcludedFolders.components(separatedBy: .newlines) + [preferences.obsidianTargetSubfolder]
        NSFileCoordinator().coordinate(readingItemAt: root, options: [], error: &coordinationError) { directory in
            guard fm.isReadableFile(atPath: directory.path),
                  let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in skipped += 1; return true }) else {
                readError = NSError(domain: "MemoFlowVault", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法读取知识库，请检查 iCloud 下载状态或重新授权。"])
                return
            }
            for case let file as URL in enumerator {
                let path = String(file.path.dropFirst(directory.path.count + 1))
                guard let values = try? file.resourceValues(forKeys: keys) else { skipped += 1; continue }
                if Self.isExcluded(path, folders: excluded) || values.isSymbolicLink == true {
                    if values.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }
                guard file.pathExtension.lowercased() == "md", values.isRegularFile == true else { continue }
                if next.count >= 2000 || bytes >= 16_000_000 { skipped += 1; continue }
                if values.ubiquitousItemDownloadingStatus == .notDownloaded {
                    try? fm.startDownloadingUbiquitousItem(at: file)
                    skipped += 1
                    continue
                }
                guard let size = values.fileSize, size <= 262144, bytes + size <= 16_000_000 else { skipped += 1; continue }
                if let old = entries[path], old.modified != nil, old.modified == values.contentModificationDate, old.size == size {
                    next[path] = old; bytes += size; continue
                }
                var fileError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &fileError) { coordinatedFile in
                    guard let data = try? Data(contentsOf: coordinatedFile), data.count <= 262144,
                          let text = String(data: data, encoding: .utf8) else { skipped += 1; return }
                    let chars = Array(text)
                    let chunks = stride(from: 0, to: chars.count, by: 700).map {
                        String(chars[$0..<min($0 + 900, chars.count)])
                    }
                    next[path] = Entry(modified: values.contentModificationDate, size: size, chunks: chunks)
                    bytes += data.count
                }
                if fileError != nil { skipped += 1 }
            }
        }
        if let error = coordinationError ?? readError as NSError? { entries.removeAll(); throw error }
        entries = next
        let candidates = next.flatMap { path, entry in entry.chunks.map { KnowledgeReference(path: path, excerpt: $0) } }
        return ScanResult(count: next.count, skipped: skipped, references: Self.retrieve(query: query, candidates: candidates))
    }
}
