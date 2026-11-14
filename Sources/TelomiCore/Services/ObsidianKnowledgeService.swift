import Foundation

public struct KnowledgeReference: Codable, Equatable, Sendable {
    public var path: String
    public var excerpt: String
    public var title: String?
    public var recordingId: UUID?
    public var timestampMs: Int?

    public init(
        path: String,
        excerpt: String,
        title: String? = nil,
        recordingId: UUID? = nil,
        timestampMs: Int? = nil
    ) {
        self.path = path
        self.excerpt = excerpt
        self.title = title
        self.recordingId = recordingId
        self.timestampMs = timestampMs
    }
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
    private struct ChunkItem: Sendable {
        var text: String
        var timestampMs: Int?
    }
    private struct Entry: Sendable {
        var modified: Date?
        var size: Int
        var title: String
        var recordingId: UUID?
        var chunks: [ChunkItem]
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

    /// P1-5：结合「允许检索的子目录白名单」与「隐私排除目录黑名单」判断路径是否在授权检索范围内
    public static func isWithinScope(
        _ path: String,
        includedFolders: [String],
        excludedFolders: [String],
        isDirectory: Bool = false
    ) -> Bool {
        if isExcluded(path, folders: excludedFolders) {
            return false
        }
        let cleanIncluded = includedFolders
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " /\n\r")) }
            .filter { !$0.isEmpty }
        guard !cleanIncluded.isEmpty else {
            return true
        }
        return cleanIncluded.contains { folder in
            if path == folder || path.hasPrefix(folder + "/") {
                return true
            }
            // 若当前枚举到的是父级目录（如 "Projects"），而白名单包含其子目录（如 "Projects/AI"），允许继续向下遍历
            if isDirectory && folder.hasPrefix(path + "/") {
                return true
            }
            return false
        }
    }

    /// 列出知识库顶层可选文件夹（跳过隐藏目录），供用户在设置页勾选检索范围
    public static func listTopLevelFolders(preferences: MemoFlowPreferences) throws -> [String] {
        let root = try VaultAccess.resolve(preferences)
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        let items = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        return items.compactMap { url -> String? in
            guard let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  vals.isDirectory == true,
                  vals.isSymbolicLink != true else { return nil }
            let name = url.lastPathComponent
            return name.hasPrefix(".") ? nil : name
        }.sorted()
    }

    public static func extractFirstTimestampMs(from text: String) -> Int? {
        if let regex = try? NSRegularExpression(pattern: #"startMs=(\d+)"#),
           let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
           let r = Range(m.range(at: 1), in: text),
           let ms = Int(text[r]) {
            return ms
        }
        if let regex = try? NSRegularExpression(pattern: #"\[(?:[^\]]*?)(\d{2}):(\d{2}):(\d{2})"#),
           let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
           let hRange = Range(m.range(at: 1), in: text),
           let mRange = Range(m.range(at: 2), in: text),
           let sRange = Range(m.range(at: 3), in: text),
           let hh = Int(text[hRange]),
           let mm = Int(text[mRange]),
           let ss = Int(text[sRange]) {
            return ((hh * 3600) + (mm * 60) + ss) * 1000
        }
        return nil
    }

    private static func extractNoteTitle(from text: String, fallbackPath: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        for line in lines.prefix(30) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("title:") {
                let raw = String(trimmed.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                if !raw.isEmpty { return raw }
            }
            if trimmed.hasPrefix("# ") {
                let raw = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !raw.isEmpty { return raw }
            }
        }
        return (fallbackPath as NSString).deletingPathExtension.components(separatedBy: "/").last ?? fallbackPath
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
        return terms.subtracting(["我们", "这个", "那个", "可以", "就是", "然后", "需要", "一个", "什么", "哪些", "怎么", "请问", "the", "and", "that", "with"])
    }

    public static func retrieve(query: String, candidates: [KnowledgeReference]) -> [KnowledgeReference] {
        let queryTerms = terms(String(query.prefix(30000)))
        guard !queryTerms.isEmpty else { return [] }

        // 计算逆文档频率权重（IDF 近似），提升专有名词与项目术语区分度
        let totalDocs = max(1, candidates.count)
        var docFreq: [String: Int] = [:]
        for qt in queryTerms {
            docFreq[qt] = candidates.reduce(0) { acc, item in
                (terms(item.excerpt).contains(qt) || terms(item.path).contains(qt)) ? acc + 1 : acc
            }
        }

        let ranked = candidates.compactMap { item -> (KnowledgeReference, Double, Int)? in
            let bodySet = terms(item.excerpt)
            let titleSet = terms(item.path).union(terms(item.title ?? ""))
            let bodyMatched = bodySet.intersection(queryTerms)
            let titleMatched = titleSet.intersection(queryTerms)
            let rawHitCount = bodyMatched.count + 3 * titleMatched.count
            guard rawHitCount >= 2 else { return nil }

            var idfWeighted = 0.0
            for t in bodyMatched {
                let df = Double(max(1, docFreq[t] ?? 1))
                idfWeighted += 1.0 + log(Double(totalDocs + 1) / df)
            }
            for t in titleMatched {
                let df = Double(max(1, docFreq[t] ?? 1))
                idfWeighted += 2.5 * (1.0 + log(Double(totalDocs + 1) / df))
            }
            return (item, idfWeighted, rawHitCount)
        }.sorted {
            if abs($0.1 - $1.1) > 0.001 { return $0.1 > $1.1 }
            return $0.0.path < $1.0.path
        }
        var seen = Set<String>()
        return Array(ranked.compactMap { item in
            seen.insert(item.0.path).inserted ? item.0 : nil
        }.prefix(4))
    }

    public func refresh(preferences: MemoFlowPreferences, query: String = "", includeExportedSubfolder: Bool = false) throws -> ScanResult {
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
        var excluded = preferences.knowledgeExcludedFolders.components(separatedBy: .newlines)
        if !includeExportedSubfolder {
            excluded.append(preferences.obsidianTargetSubfolder)
        }
        let included = preferences.knowledgeIncludedFolders
        NSFileCoordinator().coordinate(readingItemAt: root, options: [], error: &coordinationError) { directory in
            guard fm.isReadableFile(atPath: directory.path),
                  let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in skipped += 1; return true }) else {
                readError = NSError(domain: "MemoFlowVault", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法读取知识库，请检查 iCloud 下载状态或重新授权。"])
                return
            }
            for case let file as URL in enumerator {
                let path = ObsidianNoteSyncService.relativePath(of: file, inside: directory)
                guard let values = try? file.resourceValues(forKeys: keys) else { skipped += 1; continue }
                let isDir = (values.isDirectory == true)
                if !Self.isWithinScope(path, includedFolders: included, excludedFolders: excluded, isDirectory: isDir) || values.isSymbolicLink == true {
                    if isDir { enumerator.skipDescendants() }
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
                    let recId = ObsidianNoteSyncService.extractRecordingId(from: text)
                    let title = Self.extractNoteTitle(from: text, fallbackPath: path)
                    let chars = Array(text)
                    let chunks: [ChunkItem] = stride(from: 0, to: chars.count, by: 700).map { startIdx in
                        let snippet = String(chars[startIdx..<min(startIdx + 900, chars.count)])
                        return ChunkItem(text: snippet, timestampMs: Self.extractFirstTimestampMs(from: snippet))
                    }
                    next[path] = Entry(modified: values.contentModificationDate, size: size, title: title, recordingId: recId, chunks: chunks)
                    bytes += data.count
                }
                if fileError != nil { skipped += 1 }
            }
        }
        if let error = coordinationError ?? readError as NSError? { entries.removeAll(); throw error }
        entries = next
        let candidates = next.flatMap { path, entry in
            entry.chunks.map { chunk in
                KnowledgeReference(
                    path: path,
                    excerpt: chunk.text,
                    title: entry.title,
                    recordingId: entry.recordingId,
                    timestampMs: chunk.timestampMs
                )
            }
        }
        return ScanResult(count: next.count, skipped: skipped, references: Self.retrieve(query: query, candidates: candidates))
    }

    /// P1-5：跨笔记与跨录音有据问答（回答必须引用实际笔记路径及关联录音时间戳，并如实说明当前检索能力边界）
    public func answerGroundedQuestion(
        question: String,
        preferences: MemoFlowPreferences,
        recordings: [Recording],
        segmentsByRecording: [UUID: [TranscriptSegment]],
        notesByRecording: [UUID: Note],
        bindingsByRecording: [UUID: ObsidianNoteBinding]
    ) throws -> GroundedQAResult {
        let trimmedQ = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let disclosure = "检索能力说明：当前使用设备端 TF-IDF 词频加权 + 中文双字切分关键词检索（未启用向量语义 Embedding 模型；若提问未包含笔记或原话中的字面词根，可能无法召回同义表达）。以下回答严格基于命中的实际笔记与录音原话生成。"

        guard !trimmedQ.isEmpty else {
            return GroundedQAResult(
                question: question,
                answer: "请输入需要检索的跨笔记或录音问题。",
                citations: [],
                capabilityDisclosure: disclosure,
                usedCloudLLM: false
            )
        }

        var vaultRefs: [KnowledgeReference] = []
        if preferences.knowledgeContextEnabled, preferences.obsidianVaultBookmark != nil {
            if let scan = try? refresh(preferences: preferences, query: trimmedQ, includeExportedSubfolder: true) {
                vaultRefs = scan.references
            }
        }

        // 同时检索本地录音逐字稿片段（携带真实录音 ID 与毫秒时间戳，并关联已绑定的 Obsidian 笔记路径）
        let qTerms = Self.terms(trimmedQ)
        var transcriptCitations: [(GroundedCitation, Int)] = []
        for rec in recordings {
            let segs = segmentsByRecording[rec.id] ?? []
            let boundPath = bindingsByRecording[rec.id]?.vaultRelativePath
            let proj = notesByRecording[rec.id]?.projectName ?? ""
            for seg in segs {
                let combined = "\(rec.title) \(proj) \(seg.text)"
                let hits = Self.terms(combined).intersection(qTerms).count
                if hits >= 1 && (!qTerms.isEmpty && (hits >= 2 || qTerms.count == 1)) {
                    let hasVerifiableAudio = !rec.localAudioFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let citation = GroundedCitation(
                        noteRelativePath: (boundPath?.isEmpty == false) ? boundPath : nil,
                        noteTitle: rec.title,
                        recordingId: hasVerifiableAudio ? rec.id : nil,
                        startMs: hasVerifiableAudio ? seg.startMs : nil,
                        endMs: hasVerifiableAudio ? seg.endMs : nil,
                        isEstimated: seg.timingIsEstimated == true,
                        excerpt: seg.text
                    )
                    transcriptCitations.append((citation, hits))
                }
            }
        }
        transcriptCitations.sort { $0.1 > $1.1 }

        var mergedCitations: [GroundedCitation] = []
        for ref in vaultRefs {
            let cleanExcerpt = ref.excerpt
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("---") && !$0.hasPrefix("<!--") }
                .prefix(4)
                .joined(separator: " ")
            mergedCitations.append(
                GroundedCitation(
                    noteRelativePath: ref.path,
                    noteTitle: ref.title ?? ref.path,
                    recordingId: ref.recordingId,
                    startMs: ref.timestampMs,
                    endMs: nil,
                    isEstimated: false,
                    excerpt: String(cleanExcerpt.prefix(220))
                )
            )
        }

        for (tc, _) in transcriptCitations.prefix(4) {
            let isDup = mergedCitations.contains {
                $0.recordingId != nil && $0.recordingId == tc.recordingId && $0.startMs == tc.startMs
            }
            if !isDup {
                mergedCitations.append(tc)
            }
        }

        let topCitations = Array(mergedCitations.prefix(5))
        guard !topCitations.isEmpty else {
            return GroundedQAResult(
                question: trimmedQ,
                answer: "在当前允许检索的笔记文件夹与录音逐字稿中，未找到与「\(trimmedQ)」字面匹配的历史依据。你可以检查设置中的「检索文件夹范围」，或换用更具体的项目名/术语关键词。",
                citations: [],
                capabilityDisclosure: disclosure,
                usedCloudLLM: false
            )
        }

        var answerLines: [String] = ["根据已授权范围内的 \(topCitations.count) 条实际记录整理如下："]
        for (idx, cite) in topCitations.enumerated() {
            var sourceTagParts: [String] = []
            if let notePath = cite.noteRelativePath {
                sourceTagParts.append("笔记 `\(notePath)`")
            } else {
                sourceTagParts.append("录音《\(cite.noteTitle)》")
            }
            if let startMs = cite.startMs {
                let est = cite.isEstimated ? "约 " : ""
                sourceTagParts.append("时间戳 \(est)\(TimeFormatting.formatMilliseconds(startMs))")
            }
            answerLines.append("\(idx + 1). \(cite.excerpt)（来源：\(sourceTagParts.joined(separator: " · "))）")
        }

        return GroundedQAResult(
            question: trimmedQ,
            answer: answerLines.joined(separator: "\n"),
            citations: topCitations,
            capabilityDisclosure: disclosure,
            usedCloudLLM: false
        )
    }
}
