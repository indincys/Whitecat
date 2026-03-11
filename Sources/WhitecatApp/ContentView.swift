import NotesCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var quickCaptureController: QuickCaptureController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @State private var editorFocusToken = 0

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } content: {
            noteList
                .navigationSplitViewColumnWidth(min: 300, ideal: 360)
        } detail: {
            detailPane
                .navigationSplitViewColumnWidth(min: 560, ideal: 760)
        }
        .tint(WhitecatTheme.accentColor)
        .background(WhitecatTheme.workspaceBackground)
        .task {
            await model.bootstrap()
            editorFocusToken += 1
        }
        .onChange(of: model.selectedNoteID) { _, _ in
            editorFocusToken += 1
        }
        .onChange(of: model.searchText) { _, _ in
            model.handleSearchChange()
        }
        .onChange(of: scenePhase) { _, newValue in
            switch newValue {
            case .active:
                Task {
                    await model.handleSceneActivation()
                }
            case .background, .inactive:
                model.handleSceneDeactivation()
            @unknown default:
                break
            }
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                sidebarSection("视图") {
                    sidebarRow("全部笔记", systemImage: "note.text", scope: .all)
                    sidebarRow("待整理", systemImage: "wand.and.stars.inverse", scope: .pending)
                    sidebarRow("最近", systemImage: "clock", scope: .recent)
                }

                sidebarSection("文件夹") {
                    if model.snapshot.folders.isEmpty {
                        emptySidebarText("还没有文件夹")
                    } else {
                        ForEach(model.snapshot.folders) { folder in
                            sidebarRow(folder.name, systemImage: "folder", scope: .folder(folder.id))
                        }
                    }
                }

                sidebarSection("标签") {
                    if model.snapshot.tags.isEmpty {
                        emptySidebarText("还没有标签")
                    } else {
                        ForEach(model.snapshot.tags) { tag in
                            sidebarRow(tag.name, systemImage: "tag", scope: .tag(tag.id))
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(WhitecatTheme.workspaceBackground)
    }

    private var noteList: some View {
        VStack(spacing: 0) {
            noteListHeader
            Divider()
            List(selection: Binding(
                get: { model.selectedNoteID },
                set: { model.changeSelection(to: $0) }
            )) {
                ForEach(model.filteredNotes) { note in
                    noteListRow(note)
                        .tag(note.id as UUID?)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.changeSelection(to: note.id)
                        }
                        .onTapGesture(count: 2) {
                            model.changeSelection(to: note.id)
                            openWindow(id: WhitecatApp.detachedNoteWindowID, value: note.id)
                        }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .background(WhitecatTheme.workspaceBackground)
    }

    private var noteListHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索标题、正文、标签或文件夹", text: $model.searchText)
                        .textFieldStyle(.plain)
                    if !model.searchText.isEmpty {
                        Button {
                            model.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                SettingsLink {
                    Label("设置", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                Button {
                    model.createNote()
                } label: {
                    Label("新建笔记", systemImage: "square.and.pencil")
                }

                Button {
                    quickCaptureController.show()
                } label: {
                    Label("快速收集", systemImage: "bolt.badge.clock")
                }
                .help(
                    "快速收集（\(QuickCaptureController.shortcutDisplay)），置顶打开（\(QuickCaptureController.pinnedShortcutDisplay)）"
                )

                Button {
                    model.deleteSelectedNote()
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(model.selectedNote == nil)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var detailPane: some View {
        Group {
            if let note = model.selectedNote {
                NoteEditorView(noteID: note.id, focusToken: editorFocusToken)
                .background(WhitecatTheme.detailPaneBackground())
            } else {
                ContentUnavailableView("没有选中的笔记", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(WhitecatTheme.detailPaneBackground())
            }
        }
    }

    private func sidebarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            VStack(spacing: 4) {
                content()
            }
        }
    }

    private func sidebarRow(_ title: String, systemImage: String, scope: LibrarySidebarScope) -> some View {
        Button {
            model.changeScope(scope)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(isSelected(scope) ? WhitecatTheme.accentColor : .secondary)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected(scope) ? WhitecatTheme.accentColor.opacity(0.14) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emptySidebarText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }

    private func isSelected(_ scope: LibrarySidebarScope) -> Bool {
        model.selectedScope == scope
    }

    private func capsule(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func noteListRow(_ note: NoteRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(note.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(note.bodyPreview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                capsule(note.organizationStatus.rawValue, color: note.organizationStatus == .organized ? .green : .orange)
                capsule(model.folderName(for: note), color: .gray)
                if let category = note.category, !category.isEmpty {
                    capsule(category, color: .blue)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct NoteEditorView: View {
    @EnvironmentObject private var model: AppModel
    let noteID: UUID
    var focusToken: Int

    var body: some View {
        Group {
            if model.note(id: noteID) != nil {
                VStack(spacing: 0) {
                    NoteHeaderView(noteID: noteID)
                        .environmentObject(model)
                    Divider()
                    MarkdownTextView(
                        text: Binding(
                            get: { model.note(id: noteID)?.bodyMarkdown ?? "" },
                            set: { model.updateBody(for: noteID, body: $0) }
                        ),
                        focusToken: focusToken
                    )
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
            } else {
                ContentUnavailableView("笔记不存在", systemImage: "note.text.badge.minus")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct NoteHeaderView: View {
    @EnvironmentObject private var model: AppModel
    let noteID: UUID

    var body: some View {
        Group {
            if let note = model.note(id: noteID) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField(
                                "AI 会在整理后自动生成标题",
                                text: Binding(
                                    get: { model.note(id: noteID)?.title ?? "" },
                                    set: { model.updateTitle(for: noteID, title: $0) }
                                )
                            )
                            .textFieldStyle(.plain)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))

                            Text("创建于 \(note.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if note.organizationStatus == .processing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("重新整理") {
                            model.retryOrganization(noteID: noteID)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    HStack(spacing: 16) {
                        metadataField(
                            title: "主分类",
                            value: Binding(
                                get: { model.note(id: noteID)?.category ?? "" },
                                set: { model.updateCategory(for: noteID, category: $0) }
                            ),
                            badge: model.sourceBadge(note.categorySource)
                        )
                        metadataField(
                            title: "文件夹",
                            value: Binding(
                                get: { model.folderName(for: noteID) },
                                set: { model.updateFolder(for: noteID, folderName: $0) }
                            ),
                            badge: model.sourceBadge(note.folderSource)
                        )
                        metadataField(
                            title: "标签",
                            value: Binding(
                                get: { model.tagNames(for: noteID) },
                                set: { model.updateTags(for: noteID, tagText: $0) }
                            ),
                            badge: model.sourceBadge(note.tagsSource)
                        )
                    }

                    if note.organizationStatus == .processing {
                        Label("AI 正在整理标题、分类、标签和文件夹。", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let message = note.lastErrorMessage, note.organizationStatus == .failed {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if let message = model.lastOperationMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
        }
    }

    private func metadataField(title: String, value: Binding<String>, badge: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(badge)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
            TextField(title, text: value)
                .textFieldStyle(.roundedBorder)
        }
    }
}
