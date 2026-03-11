import AIOrchestrator
import AppUpdates
import NotesCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var quickCaptureController: QuickCaptureController
    @State private var selectedProfileID: UUID?
    @State private var apiKeyDraft: String = ""
    @State private var appcastURLDraft: String = ""
    @State private var releasePageURLDraft: String = ""
    @State private var autoCheckDraft: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsSection("模型") {
                    modelSettingsSection
                }

                settingsSection("快速收集") {
                    captureSettingsSection
                }

                settingsSection("外观") {
                    appearanceSettingsSection
                }

                settingsSection("更新") {
                    updateSettingsSection
                }

                settingsSection("存储与同步") {
                    storageSettingsSection
                }
            }
            .padding(28)
        }
        .frame(minWidth: 920, minHeight: 680)
        .onAppear {
            hydratePreferenceDrafts()
            if selectedProfileID == nil {
                selectedProfileID = model.activeProfile?.id ?? model.snapshot.profiles.first?.id
            }
            loadKeyDraft()
        }
        .onChange(of: selectedProfileID) { _, _ in
            loadKeyDraft()
        }
    }

    private var modelSettingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Picker("当前配置", selection: $selectedProfileID) {
                    ForEach(model.snapshot.profiles) { profile in
                        Text(profile.displayName).tag(Optional.some(profile.id))
                    }
                }
                .frame(maxWidth: 260)

                Button("新增配置") {
                    model.addProfile()
                    selectedProfileID = model.snapshot.profiles.last?.id
                    loadKeyDraft()
                }

                Button("删除配置") {
                    guard let selectedProfile else { return }
                    model.removeProfile(id: selectedProfile.id)
                    selectedProfileID = model.snapshot.activeProfile()?.id ?? model.snapshot.profiles.first?.id
                    loadKeyDraft()
                }
                .disabled(model.snapshot.profiles.count <= 1 || selectedProfile == nil)
            }

            if let selectedProfile {
                TextField(
                    "显示名称",
                    text: binding(for: selectedProfile, keyPath: \.displayName, defaultValue: selectedProfile.displayName)
                )

                Picker(
                    "平台",
                    selection: binding(for: selectedProfile, keyPath: \.providerKind, defaultValue: selectedProfile.providerKind)
                ) {
                    ForEach(ProviderKind.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: selectedProfile.providerKind) { _, provider in
                    var draft = selectedProfile
                    draft.displayName = provider.displayName
                    draft.baseURL = provider.defaultBaseURL
                    draft.model = provider.defaultModel
                    model.updateProfile(draft)
                }

                TextField(
                    "Base URL",
                    text: binding(for: selectedProfile, keyPath: \.baseURL, defaultValue: selectedProfile.baseURL)
                )
                TextField(
                    "模型名称",
                    text: binding(for: selectedProfile, keyPath: \.model, defaultValue: selectedProfile.model)
                )
                TextField(
                    "请求路径",
                    text: binding(for: selectedProfile, keyPath: \.requestPath, defaultValue: selectedProfile.requestPath)
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("整理提示词")
                            .font(.headline)
                        Spacer()
                        Button("恢复默认提示词") {
                            var draft = selectedProfile
                            draft.organizationPrompt = AIProfileRecord.defaultOrganizationPrompt
                            draft.updatedAt = .now
                            model.updateProfile(draft)
                        }
                    }

                    TextEditor(
                        text: binding(
                            for: selectedProfile,
                            keyPath: \.organizationPrompt,
                            defaultValue: selectedProfile.organizationPrompt
                        )
                    )
                    .font(.system(size: 13))
                    .frame(minHeight: 180)
                    .padding(10)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                SecureField("API Key", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)

                Toggle("设为当前整理模型", isOn: Binding(
                    get: { selectedProfile.isActive },
                    set: { isActive in
                        if isActive {
                            model.activateProfile(id: selectedProfile.id)
                        }
                    }
                ))

                HStack {
                    Button("保存 API Key") {
                        model.saveAPIKey(apiKeyDraft, for: selectedProfile)
                    }
                    Spacer()
                    if selectedProfile.isActive {
                        Label("当前生效", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            } else {
                ContentUnavailableView("暂无模型配置", systemImage: "tray")
            }
        }
    }

    private var captureSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("全局快捷键：\(QuickCaptureController.shortcutDisplay)")
            Text("置顶快捷键：\(QuickCaptureController.pinnedShortcutDisplay)")
            Text("应用运行时可用。触发后只弹出一个正文输入小窗，不会打开主窗口。")
                .foregroundStyle(.secondary)

            HStack {
                Button("打开快速收集窗口") {
                    quickCaptureController.show()
                }
                Button("打开并置顶") {
                    quickCaptureController.showPinned()
                }
            }

            Divider()

            Text("小窗口里只保留正文输入。")
            Text("按 Command-Enter 立即保存为新笔记。")
            Text("按 Esc 直接关闭，不保存空内容。")
        }
    }

    private var appearanceSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("主题", selection: appearanceBinding) {
                ForEach(AppAppearancePreference.allCases) { appearance in
                    Text(appearance.displayName)
                        .tag(appearance)
                }
            }
            .pickerStyle(.segmented)

            Text(model.snapshot.preferences.appearance.detailDescription)
                .foregroundStyle(.secondary)
        }
    }

    private var updateSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Appcast URL", text: $appcastURLDraft)
            TextField("GitHub Releases 页面", text: $releasePageURLDraft)
            Toggle("自动后台检查更新", isOn: $autoCheckDraft)

            HStack {
                Button("保存更新配置") {
                    model.updatePreferences(
                        appcastURL: appcastURLDraft,
                        releasePageURL: releasePageURLDraft,
                        checksForUpdatesAutomatically: autoCheckDraft
                    )
                }
                Button("检查更新") {
                    Task {
                        await model.checkForUpdates()
                    }
                }
                Button("打开 Releases 页面") {
                    model.openReleasePage()
                }
                .disabled(releasePageURLDraft.isEmpty)
            }

            if let message = model.updateInstallationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            switch model.updateState {
            case .idle:
                Text("尚未检查更新。")
                    .foregroundStyle(.secondary)
            case .checking:
                ProgressView("正在读取更新源...")
            case let .installing(message):
                ProgressView(message)
            case .upToDate:
                Label("当前已是最新版本。", systemImage: "checkmark.seal")
                    .foregroundStyle(.green)
            case let .available(release):
                VStack(alignment: .leading, spacing: 10) {
                    Label("发现新版本 \(release.shortVersion)", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(.orange)
                    if !model.supportsInAppUpdateInstallation {
                        Text("当前构建只支持跳转下载。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(model.supportsInAppUpdateInstallation ? "下载并安装更新" : "下载更新") {
                        Task {
                            if model.supportsInAppUpdateInstallation {
                                await model.installUpdate(release)
                            } else {
                                model.openUpdateDownload(release)
                            }
                        }
                    }
                }
            case let .failed(message):
                Text(message)
                    .foregroundStyle(.red)
            }
        }
    }

    private var storageSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.storageStatusDescription, systemImage: model.isUsingICloudStorage ? "icloud.fill" : "externaldrive.fill")
                .foregroundStyle(model.isUsingICloudStorage ? .green : .orange)

            Text(model.storageLocationDescription)
                .textSelection(.enabled)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("立即同步") {
                    Task {
                        await model.syncLibraryNow()
                    }
                }
                Button("重新载入") {
                    Task {
                        await model.reloadLibraryFromDisk(showMessage: true)
                    }
                }
                Button("打开存储目录") {
                    model.openStorageLocation()
                }
            }
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var selectedProfile: AIProfileRecord? {
        model.snapshot.profiles.first(where: { $0.id == selectedProfileID }) ?? model.activeProfile
    }

    private var appearanceBinding: Binding<AppAppearancePreference> {
        Binding(
            get: { model.snapshot.preferences.appearance },
            set: { model.updateAppearance($0) }
        )
    }

    private func hydratePreferenceDrafts() {
        appcastURLDraft = model.snapshot.preferences.appcastURL
        releasePageURLDraft = model.snapshot.preferences.releasePageURL
        autoCheckDraft = model.snapshot.preferences.checksForUpdatesAutomatically
    }

    private func loadKeyDraft() {
        guard let selectedProfile else {
            apiKeyDraft = ""
            return
        }
        apiKeyDraft = model.apiKey(for: selectedProfile)
    }

    private func binding<Value>(
        for profile: AIProfileRecord,
        keyPath: WritableKeyPath<AIProfileRecord, Value>,
        defaultValue: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                model.snapshot.profiles.first(where: { $0.id == profile.id })?[keyPath: keyPath] ?? defaultValue
            },
            set: { newValue in
                guard var draft = model.snapshot.profiles.first(where: { $0.id == profile.id }) else { return }
                draft[keyPath: keyPath] = newValue
                draft.updatedAt = .now
                model.updateProfile(draft)
            }
        )
    }
}
