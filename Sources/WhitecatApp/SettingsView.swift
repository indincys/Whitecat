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
        TabView {
            modelSettingsTab
                .tabItem { Label("模型", systemImage: "sparkles") }
            captureSettingsTab
                .tabItem { Label("快速收集", systemImage: "keyboard") }
            updateSettingsTab
                .tabItem { Label("更新", systemImage: "arrow.down.app") }
        }
        .frame(minWidth: 820, minHeight: 520)
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

    private var modelSettingsTab: some View {
        HStack(spacing: 0) {
            List(selection: $selectedProfileID) {
                ForEach(model.snapshot.profiles) { profile in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.displayName)
                        Text(profile.providerKind.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(Optional.some(profile.id))
                }
            }
            .frame(minWidth: 240)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("新增配置") {
                        model.addProfile()
                        selectedProfileID = model.snapshot.profiles.last?.id
                        loadKeyDraft()
                    }
                    Button("删除") {
                        guard let selectedProfile = selectedProfile else { return }
                        model.removeProfile(id: selectedProfile.id)
                        selectedProfileID = model.snapshot.activeProfile()?.id ?? model.snapshot.profiles.first?.id
                        loadKeyDraft()
                    }
                    .disabled(model.snapshot.profiles.count <= 1 || selectedProfile == nil)
                    Spacer()
                }
                .padding()
                .background(.bar)
            }

            Divider()

            if let selectedProfile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("模型配置")
                            .font(.title2.weight(.semibold))

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

                            Text("这里写你希望模型遵守的整理规则，例如标题风格、分类方式、标签数量和文件夹偏好。")
                                .font(.caption)
                                .foregroundStyle(.secondary)

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
                    }
                    .padding(28)
                }
            } else {
                ContentUnavailableView("暂无模型配置", systemImage: "tray")
            }
        }
    }

    private var captureSettingsTab: some View {
        Form {
            Section("快捷键") {
                Text("全局快捷键：\(QuickCaptureController.shortcutDisplay)")
                Text("应用运行时可用。触发后只弹出一个正文输入小窗，不会打开主窗口。")
                    .foregroundStyle(.secondary)
                Button("打开快速收集窗口") {
                    quickCaptureController.show()
                }
            }

            Section("使用方式") {
                Text("小窗口里只保留正文输入。")
                Text("按 Command-Enter 立即保存为新笔记。")
                Text("按 Esc 直接关闭，不保存空内容。")
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }

    private var updateSettingsTab: some View {
        Form {
            Section("更新源") {
                TextField("Appcast URL", text: $appcastURLDraft)
                TextField("GitHub Releases 页面", text: $releasePageURLDraft)
                Toggle("自动后台检查更新（V1 默认关闭）", isOn: $autoCheckDraft)
                Button("保存更新配置") {
                    model.updatePreferences(
                        appcastURL: appcastURLDraft,
                        releasePageURL: releasePageURLDraft,
                        checksForUpdatesAutomatically: autoCheckDraft
                    )
                }
            }

            Section("检查更新") {
                if let message = model.updateInstallationMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                HStack {
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

                switch model.updateState {
                case .idle:
                    Text("尚未检查更新。")
                        .foregroundStyle(.secondary)
                case .checking:
                    ProgressView("正在读取更新源...")
                case .upToDate:
                    Label("当前已是最新版本。", systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                case let .available(release):
                    VStack(alignment: .leading, spacing: 10) {
                        Label("发现新版本 \(release.shortVersion)", systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(.orange)
                        if !model.supportsInAppUpdateInstallation {
                            Text("当前构建只支持跳转下载，不支持应用内直接安装。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("下载更新") {
                            model.openUpdateDownload(release)
                        }
                    }
                case let .failed(message):
                    Text(message)
                        .foregroundStyle(.red)
                }
            }

            Section("存储") {
                Text(model.storageLocationDescription)
                    .textSelection(.enabled)
                Button("打开存储目录") {
                    model.openStorageLocation()
                }
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }

    private var selectedProfile: AIProfileRecord? {
        model.snapshot.profiles.first(where: { $0.id == selectedProfileID }) ?? model.activeProfile
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
