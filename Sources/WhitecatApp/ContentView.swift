import NotesCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var quickCaptureController: QuickCaptureController
    @Environment(\.scenePhase) private var scenePhase
    @State private var editorShouldFocus = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } content: {
            noteList
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            detailPane
                .navigationSplitViewColumnWidth(min: 560, ideal: 760)
        }
        .tint(WhitecatTheme.accentColor)
        .background(WhitecatTheme.workspaceBackground)
        .task {
            await model.bootstrap()
            editorShouldFocus = true
        }
        .onChange(of: model.selectedNoteID) { _, _ in
            editorShouldFocus = true
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue != .active {
                model.handleSceneDeactivation()
            }
        }
    }

    private var sidebar: some View {
        List(selection: Binding(
            get: { Optional.some(model.selectedScope) },
            set: {
                guard let value = $0 else { return }
                model.changeScope(value)
            }
        )) {
            Section("视图") {
                Label("全部笔记", systemImage: "note.text")
                    .tag(Optional.some(LibrarySidebarScope.all))
                Label("待整理", systemImage: "wand.and.stars.inverse")
                    .tag(Optional.some(LibrarySidebarScope.pending))
                Label("最近", systemImage: "clock")
                    .tag(Optional.some(LibrarySidebarScope.recent))
            }

            Section("文件夹") {
                ForEach(model.snapshot.folders) { folder in
                    Label(folder.name, systemImage: "folder")
                        .tag(Optional.some(LibrarySidebarScope.folder(folder.id)))
                }
            }

            Section("标签") {
                ForEach(model.snapshot.tags) { tag in
                    Label(tag.name, systemImage: "tag")
                        .tag(Optional.some(LibrarySidebarScope.tag(tag.id)))
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private var noteList: some View {
        List(selection: Binding(
            get: { model.selectedNoteID },
            set: { model.changeSelection(to: $0) }
        )) {
            ForEach(model.filteredNotes) { note in
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
                .tag(Optional.some(note.id))
            }
        }
        .listStyle(.inset)
        .searchable(text: $model.searchText, prompt: "搜索标题、正文、标签或文件夹")
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItemGroup {
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

                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }
        }
    }

    private var detailPane: some View {
        Group {
            if let note = model.selectedNote {
                VStack(spacing: 0) {
                    NoteHeaderView(note: note)
                        .environmentObject(model)
                    Divider()
                    MarkdownTextView(
                        text: Binding(
                            get: { model.selectedNote?.bodyMarkdown ?? "" },
                            set: { model.updateBody(for: note.id, body: $0) }
                        ),
                        isFocused: editorShouldFocus
                    )
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                .background(WhitecatTheme.detailPaneBackground())
            } else {
                ContentUnavailableView("没有选中的笔记", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(WhitecatTheme.detailPaneBackground())
            }
        }
    }

    private func capsule(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct NoteHeaderView: View {
    @EnvironmentObject private var model: AppModel
    let note: NoteRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(
                        "AI 会在整理后自动生成标题",
                        text: Binding(
                            get: { model.selectedNote?.title ?? "" },
                            set: { model.updateTitle(for: note.id, title: $0) }
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
                    model.retryOrganizationForSelectedNote()
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 16) {
                metadataField(
                    title: "主分类",
                    value: Binding(
                        get: { model.selectedNote?.category ?? "" },
                        set: { model.updateCategory(for: note.id, category: $0) }
                    ),
                    badge: model.sourceBadge(note.categorySource)
                )
                metadataField(
                    title: "文件夹",
                    value: Binding(
                        get: { model.selectedNoteFolderName },
                        set: { model.updateFolder(for: note.id, folderName: $0) }
                    ),
                    badge: model.sourceBadge(note.folderSource)
                )
                metadataField(
                    title: "标签",
                    value: Binding(
                        get: { model.selectedNoteTagsText },
                        set: { model.updateTags(for: note.id, tagText: $0) }
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
