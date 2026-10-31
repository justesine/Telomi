import SwiftUI
#if canImport(MemoFlowCore)
import MemoFlowCore
#endif

/// CHAT-001: AI 记忆助手与 Obsidian 智能归档（PRD V1.4）
/// 支持跨日期全局检索、人工勾选录音来源、结构化整理、Markdown 预览与实时编辑、经用户确认后新建 Obsidian 项目笔记
public struct AIMemoryChatSheetView: View {
    @ObservedObject var store: MemoFlowStore
    @Environment(\.dismiss) private var dismiss

    @State private var queryText: String = ""
    @State private var candidates: [ProjectCandidateRecording] = []
    @State private var hasSearched: Bool = false
    @State private var isGenerating: Bool = false
    @State private var generatedDraft: ProjectNoteDraft?
    @State private var editableMarkdown: String = ""
    @State private var isPreviewMode: Bool = true
    @State private var isExporting: Bool = false
    @State private var exportOutcome: (fileURL: URL, relativePath: String, obsidianOpenURL: URL?)?
    @State private var errorMessage: String?
    @State private var copiedToastVisible: Bool = false

    private var isEnglish: Bool {
        store.preferences.appLanguage.isEnglish
    }

    public init(store: MemoFlowStore, initialQuery: String = "") {
        self.store = store
        _queryText = State(initialValue: initialQuery)
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(Color.white.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let err = errorMessage {
                        errorBanner(err)
                    }

                    if let outcome = exportOutcome {
                        exportSuccessCard(outcome)
                    } else if generatedDraft != nil {
                        draftPreviewAndEditView
                    } else {
                        searchAndCandidatesView
                    }
                }
                .padding(20)
            }
        }
        .background(MFTheme.sheetBg)
        .presentationCornerRadius(28)
        .preferredColorScheme(store.preferences.appearanceTheme.colorScheme)
        .onAppear {
            performCandidateSearch()
        }
        .onChange(of: queryText) { _, newQuery in
            candidates = store.findProjectNoteCandidates(query: newQuery)
        }
    }

    // MARK: - 1. Top Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(MFTheme.iceBlue.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MFTheme.iceCyan)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.memoryChatTitle(isEnglish))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(MFTheme.textPrimary)
                Text(isEnglish ? "Cross-recording retrieval, synthesis & Obsidian archiving" : "跨历史录音全局检索与脉络归纳，预览确认后新建 Obsidian 项目笔记")
                    .font(.system(size: 11))
                    .foregroundStyle(MFTheme.textSecondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MFTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - 2. Step 1: Search & Candidates View

    private var searchAndCandidatesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Prompt input section
            VStack(alignment: .leading, spacing: 10) {
                Text(isEnglish ? "What would you like to synthesize?" : "你想整理什么主题或项目？")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(MFTheme.textPrimary)

                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundStyle(MFTheme.textSecondary)

                        TextField(
                            L10n.askMemoryPlaceholder(isEnglish),
                            text: $queryText
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onSubmit {
                            performCandidateSearch()
                        }

                        if !queryText.isEmpty {
                            Button {
                                queryText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(MFTheme.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(MFTheme.recessedBg)
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MFTheme.paperBorder, lineWidth: 0.8))
                    )

                    Button {
                        performCandidateSearch()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkle.magnifyingglass")
                            Text(isEnglish ? "Find Notes" : "检索录音")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(MFTheme.iceCyan)
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Quick chips
                quickPromptChips
            }
            .mfGlassCard(cornerRadius: 14, padding: 14)

            // Candidates list
            if hasSearched {
                candidateListSection
            } else {
                initialHelperCard
            }
        }
    }

    private var quickPromptChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let chips = isEnglish
                    ? ["Research Program", "Product Roadmap & Actions", "Meeting Decisions Summary", "All Historical Recordings"]
                    : ["科研栏目讨论整理", "近期产品规划与待办", "会议决策与开放问题", "全部历史录音汇总"]

                ForEach(chips, id: \.self) { chip in
                    Button {
                        queryText = (chip == (isEnglish ? "All Historical Recordings" : "全部历史录音汇总")) ? "" : chip
                        performCandidateSearch()
                    } label: {
                        Text(chip)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MFTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(Capsule().strokeBorder(MFTheme.paperBorder, lineWidth: 0.6))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
    }

    private var initialHelperCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(MFTheme.warmAmber)
                Text(isEnglish ? "How it works" : "整理流程与安全保证")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(MFTheme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 6) {
                helperBullet(isEnglish ? "1. Global search across all historical recordings (independent of current date filter)." : "1. 跨全部历史日期检索相关录音，不受首页选中单日与热力图限制。")
                helperBullet(isEnglish ? "2. Manually check or uncheck recordings to curate sources." : "2. 手动勾选或取消候选录音，确保来源完全符合你的意图。")
                helperBullet(isEnglish ? "3. Synthesizes a structured project note with timeline, decisions and evidence quotes." : "3. 归纳提炼项目背景、讨论时间线、决策与待办，绝不捏造未发生的事实。")
                helperBullet(isEnglish ? "4. Preview & edit in Markdown before saving." : "4. 提供完整 Markdown 预览与实时编辑，支持手动调整文本。")
                helperBullet(isEnglish ? "5. Creates a brand new note in Obsidian only when you explicitly confirm; never overwrites." : "5. 必须经你明确点击确认后才新建笔记，遇同名自动添加序号保护，绝不覆盖已有笔记。")
            }
        }
        .mfGlassCard(cornerRadius: 14, padding: 14, tint: MFTheme.warmAmber)
    }

    private func helperBullet(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(MFTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var candidateListSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isEnglish ? "Candidate Recordings (\(selectedCandidateCount)/\(candidates.count) selected)" : "候选录音（已勾选 \(selectedCandidateCount)/\(candidates.count) 条）")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(MFTheme.textPrimary)

                Spacer()

                Button {
                    let allSelected = candidates.allSatisfy(\.isSelected)
                    for i in candidates.indices {
                        candidates[i].isSelected = !allSelected
                    }
                } label: {
                    Text(candidates.allSatisfy(\.isSelected) ? (isEnglish ? "Deselect All" : "取消全选") : (isEnglish ? "Select All" : "全选"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MFTheme.iceCyan)
                }
                .buttonStyle(.plain)
            }

            if candidates.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundStyle(MFTheme.textMuted)
                    Text(isEnglish ? "No matching recordings found" : "未找到匹配的录音")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MFTheme.textSecondary)
                    Text(isEnglish ? "Try another topic or leave blank to browse all recordings." : "请尝试更换关键词，或清空输入框浏览全部历史录音。")
                        .font(.system(size: 11))
                        .foregroundStyle(MFTheme.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .mfGlassCard(cornerRadius: 12, padding: 16)
            } else {
                VStack(spacing: 10) {
                    ForEach($candidates) { $cand in
                        candidateCard(candidate: $cand)
                    }
                }

                // Generate button
                Button {
                    generateProjectDraft()
                } label: {
                    HStack(spacing: 8) {
                        if isGenerating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isGenerating ? (isEnglish ? "Generating…" : "正在生成…") : L10n.generateProjectNote(isEnglish))
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MFTheme.textPrimary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(MFTheme.recessedBg)
                            .overlay(Capsule().strokeBorder(MFTheme.paperBorder, lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .disabled(selectedCandidateCount == 0 || isGenerating)
                .padding(.top, 6)
            }
        }
    }

    private var selectedCandidateCount: Int {
        candidates.filter(\.isSelected).count
    }

    private func candidateCard(candidate: Binding<ProjectCandidateRecording>) -> some View {
        let rec = candidate.wrappedValue.recording
        let isSelected = candidate.wrappedValue.isSelected
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateStr = dateFormatter.string(from: rec.createdAt)

        return HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button {
                candidate.wrappedValue.isSelected.toggle()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? MFTheme.iceCyan : Color.white.opacity(0.06))
                        .frame(width: 22, height: 22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(isSelected ? MFTheme.iceCyan : MFTheme.paperBorder, lineWidth: 1)
                        )
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.black)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(rec.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(MFTheme.textPrimary)

                    if rec.deviceSource == .appleWatch {
                        HStack(spacing: 3) {
                            Image(systemName: "applewatch")
                            Text("Apple Watch")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MFTheme.softViolet)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(MFTheme.softViolet.opacity(0.14), in: Capsule())
                    }

                    Spacer()

                    Text(TimeFormatting.formatDuration(rec.duration))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MFTheme.textMuted)
                }

                HStack(spacing: 8) {
                    Text(dateStr)
                        .font(.system(size: 11))
                        .foregroundStyle(MFTheme.textSecondary)

                    Text("·")
                        .foregroundStyle(MFTheme.textMuted)

                    Text(candidate.wrappedValue.matchReason)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MFTheme.warmAmber)
                }

                if let warning = candidate.wrappedValue.transcriptWarning {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text(warning)
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.35))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.95, green: 0.45, blue: 0.35).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }

                if !candidate.wrappedValue.matchingSnippets.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(candidate.wrappedValue.matchingSnippets, id: \.self) { snip in
                            Text(snip)
                                .font(.system(size: 11))
                                .foregroundStyle(MFTheme.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(MFTheme.recessedBg.opacity(0.8))
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? MFTheme.cardBgTop : MFTheme.cardBgTop.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? MFTheme.iceCyan.opacity(0.4) : MFTheme.paperBorder, lineWidth: 0.8)
                )
        )
    }

    // MARK: - 3. Step 2: Markdown Preview & Live Edit (CHAT-001D)

    private var draftPreviewAndEditView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Top action bar
            HStack {
                Button {
                    generatedDraft = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(isEnglish ? "Adjust Sources" : "调整来源录音")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MFTheme.iceCyan)
                }
                .buttonStyle(.plain)

                Spacer()

                if editableMarkdown.contains("generator: MemoFlow Local Rule Engine") {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.horizontal.circle")
                        Text(isEnglish ? "Local Offline Rule" : "本地离线整理")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MFTheme.warmAmber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(MFTheme.warmAmber.opacity(0.12), in: Capsule())
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text(isEnglish ? "AI Synthesized" : "AI 深度提炼")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MFTheme.iceCyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(MFTheme.iceCyan.opacity(0.12), in: Capsule())
                }

                // Mode toggle
                Picker("", selection: $isPreviewMode) {
                    Text(isEnglish ? "Preview" : "格式预览").tag(true)
                    Text(isEnglish ? "Edit Markdown" : "编辑 Markdown").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            // Main display: Preview or Editor
            if isPreviewMode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(editableMarkdown)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(MFTheme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                }
                .frame(minHeight: 280, maxHeight: 420)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(MFTheme.recessedBg)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MFTheme.paperBorder, lineWidth: 0.8))
                )
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isEnglish ? "You can directly edit the Markdown below:" : "您可以直接在下方编辑与修正 Markdown 文本：")
                        .font(.system(size: 11))
                        .foregroundStyle(MFTheme.textSecondary)

                    TextEditor(text: $editableMarkdown)
                        .font(.system(size: 13, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 280, maxHeight: 420)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(MFTheme.recessedBg)
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MFTheme.iceCyan.opacity(0.5), lineWidth: 0.8))
                        )
                }
            }

            // Safety notice & Action buttons
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(MFTheme.mintGreen)
                    Text(isEnglish ? "Non-destructive guarantee: A new note is created only upon your confirmation; never overwrites existing files." : "安全写入保证：只有在您明确点击下方确认后才会新建 Obsidian 笔记；同名自动添加序号保护，绝不覆盖已有笔记。")
                        .font(.system(size: 11))
                        .foregroundStyle(MFTheme.textSecondary)
                }

                HStack(spacing: 12) {
                    // Copy button
                    Button {
                        copyToClipboard(editableMarkdown)
                        copiedToastVisible = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copiedToastVisible = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: copiedToastVisible ? "checkmark" : "doc.on.doc")
                            Text(copiedToastVisible ? (isEnglish ? "Copied!" : "已复制！") : L10n.copyMarkdown(isEnglish))
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MFTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .overlay(Capsule().strokeBorder(MFTheme.paperBorder, lineWidth: 0.8))
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Confirm export button
                    Button {
                        confirmExportToObsidian()
                    } label: {
                        HStack(spacing: 6) {
                            if isExporting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "square.and.arrow.down.fill")
                            }
                            Text(isExporting ? (isEnglish ? "Writing…" : "写入中…") : L10n.confirmWriteObsidian(isEnglish))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(MFTheme.iceCyan)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isExporting || editableMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .mfGlassCard(cornerRadius: 14, padding: 14)
        }
    }

    // MARK: - 4. Step 3: Success Card (CHAT-001E)

    private func exportSuccessCard(_ outcome: (fileURL: URL, relativePath: String, obsidianOpenURL: URL?)) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(MFTheme.mintGreen.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(MFTheme.mintGreen)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isEnglish ? "Successfully Created Obsidian Note!" : "已成功新建 Obsidian 项目笔记！")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(MFTheme.textPrimary)
                    Text(isEnglish ? "The note has been safely created in your authorized vault without overwriting any existing files." : "笔记已安全写入已授权的知识库中，未覆盖任何既有文件。")
                        .font(.system(size: 11))
                        .foregroundStyle(MFTheme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(isEnglish ? "Target Path:" : "保存相对路径：")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MFTheme.textMuted)
                Text(outcome.relativePath)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MFTheme.iceCyan)
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(MFTheme.recessedBg)
            )

            HStack(spacing: 12) {
                if let openURL = outcome.obsidianOpenURL {
                    Button {
                        #if os(macOS)
                        NSWorkspace.shared.open(openURL)
                        #elseif os(iOS)
                        UIApplication.shared.open(openURL)
                        #endif
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "books.vertical.fill")
                            Text(isEnglish ? "Open in Obsidian" : "在 Obsidian 中打开")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MFTheme.softViolet)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(MFTheme.softViolet.opacity(0.18))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text(isEnglish ? "Done" : "完成")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(MFTheme.iceCyan))
                }
                .buttonStyle(.plain)
            }
        }
        .mfGlassCard(cornerRadius: 16, padding: 18, tint: MFTheme.mintGreen)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.28))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(MFTheme.textPrimary)
            Spacer()
            Button {
                errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundStyle(MFTheme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .mfGlassCard(cornerRadius: 12, padding: 12, tint: Color(red: 0.95, green: 0.35, blue: 0.28))
    }

    // MARK: - Actions

    private func performCandidateSearch() {
        errorMessage = nil
        candidates = store.findProjectNoteCandidates(query: queryText)
        hasSearched = true
    }

    private func generateProjectDraft() {
        let selectedIds = candidates.filter(\.isSelected).map(\.id)
        guard !selectedIds.isEmpty else { return }

        errorMessage = nil
        isGenerating = true

        let topic = queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (isEnglish ? "Project Discussion Synthesis" : "项目讨论整理")
            : queryText.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let markdown = try await store.synthesizeProjectNote(topic: topic, selectedRecordingIds: selectedIds)
                await MainActor.run {
                    self.generatedDraft = ProjectNoteDraft(
                        topic: topic,
                        title: "\(topic)｜项目讨论整理",
                        selectedRecordingIds: selectedIds,
                        markdownContent: markdown
                    )
                    self.editableMarkdown = markdown
                    self.isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = isEnglish ? "Failed to synthesize note: \(error.localizedDescription)" : "生成笔记失败：\(error.localizedDescription)"
                    self.isGenerating = false
                }
            }
        }
    }

    private func confirmExportToObsidian() {
        guard let draft = generatedDraft else { return }
        errorMessage = nil
        isExporting = true

        do {
            let result = try store.exportProjectNoteToObsidian(
                title: draft.title,
                markdown: editableMarkdown,
                sourceRecordingIds: draft.selectedRecordingIds,
                existingRelativePath: draft.obsidianRelativePath
            )
            self.generatedDraft?.obsidianRelativePath = result.relativePath
            self.generatedDraft?.exportedAt = Date()
            exportOutcome = result
            isExporting = false
        } catch {
            isExporting = false
            if let syncErr = error as? ObsidianSyncError, syncErr == .vaultNotConfigured {
                errorMessage = isEnglish
                    ? "Obsidian Vault is not configured. Please authorize a vault in Settings -> Obsidian."
                    : "尚未配置 Obsidian 笔记库。请先在「设置 -> Obsidian 笔记库联动」中授权选择笔记库文件夹。"
            } else {
                errorMessage = isEnglish
                    ? "Failed to save Obsidian note: \(error.localizedDescription)"
                    : "写入 Obsidian 失败：\(error.localizedDescription)"
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
}
