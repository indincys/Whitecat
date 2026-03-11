import AIOrchestrator
import AppKit
import AppUpdates
import Combine
import Foundation
import NotesCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: LibrarySnapshot = .empty
    @Published var selectedScope: LibrarySidebarScope = .all
    @Published var selectedNoteID: UUID?
    @Published var searchText: String = ""
    @Published var updateState: UpdateState = .idle
    @Published var storageLocationDescription: String = "正在读取..."
    @Published var storageStatusDescription: String = "正在检测 iCloud 状态..."
    @Published private(set) var isUsingICloudStorage: Bool = false
    @Published var lastOperationMessage: String?

    enum UpdateState: Equatable {
        case idle
        case checking
        case installing(String)
        case upToDate
        case available(UpdateRelease)
        case failed(String)
    }

    private let persistence: LibraryPersistence
    private let organizer: NoteOrganizer
    private let secretStore: SecretStoring
    private let updateChecker: ManualUpdateChecker
    private let sparkleUpdateDriver: SparkleUpdateDriver?
    private let unsignedUpdateInstaller: UnsignedUpdateInstaller
    private let updateInstallationMode: UpdateInstallationMode
    private var autosaveTask: Task<Void, Never>?
    private var organizationTasks: [UUID: Task<Void, Never>] = [:]
    private var queuedOrganizationRequests: [UUID: Bool] = [:]
    private var scheduledOrganizationTasks: [UUID: Task<Void, Never>] = [:]
    private var retryTasks: [UUID: Task<Void, Never>] = [:]
    private var storageRootURL: URL?

    private let automaticOrganizationGraceInterval: TimeInterval = 1.6
    private let manualOrganizationGraceInterval: TimeInterval = 0.9
    private let softRetryDelays: [TimeInterval] = [4, 10, 25]

    init(
        persistence: LibraryPersistence = LibraryPersistence(),
        organizer: NoteOrganizer,
        secretStore: SecretStoring,
        updateChecker: ManualUpdateChecker = ManualUpdateChecker(),
        sparkleUpdateDriver: SparkleUpdateDriver? = nil,
        unsignedUpdateInstaller: UnsignedUpdateInstaller = UnsignedUpdateInstaller(),
        updateInstallationMode: UpdateInstallationMode = UpdateInstallationInspector.current()
    ) {
        self.persistence = persistence
        self.organizer = organizer
        self.secretStore = secretStore
        self.updateChecker = updateChecker
        self.sparkleUpdateDriver = sparkleUpdateDriver
        self.unsignedUpdateInstaller = unsignedUpdateInstaller
        self.updateInstallationMode = updateInstallationMode
    }

    var filteredNotes: [NoteRecord] {
        snapshot.filteredNotes(searchText: searchText, scope: selectedScope)
    }

    var selectedNote: NoteRecord? {
        snapshot.note(id: selectedNoteID)
    }

    func note(id: UUID) -> NoteRecord? {
        snapshot.note(id: id)
    }

    var selectedNoteTagsText: String {
        guard let selectedNote else { return "" }
        return snapshot.tags(for: selectedNote).map(\.name).joined(separator: ", ")
    }

    var selectedNoteFolderName: String {
        guard let selectedNote else { return "" }
        return snapshot.folder(id: selectedNote.folderID)?.name ?? ""
    }

    var activeProfile: AIProfileRecord? {
        snapshot.activeProfile()
    }

    var supportsInAppUpdateInstallation: Bool {
        updateInstallationMode.supportsInAppInstallation
    }

    var updateInstallationMessage: String? {
        switch updateInstallationMode {
        case let .selfManaged(reason), let .downloadOnly(reason):
            return reason
        case .sparkle:
            return nil
        }
    }

    var appearancePreference: AppAppearancePreference {
        snapshot.preferences.appearance
    }

    var preferredColorScheme: ColorScheme? {
        appearancePreference.colorScheme
    }

    func bootstrap() async {
        do {
            var loadedSnapshot = try await persistence.load()
            if loadedSnapshot.profiles.isEmpty {
                loadedSnapshot = .empty
            }
            if loadedSnapshot.preferences.appcastURL.isEmpty {
                loadedSnapshot.preferences.appcastURL = AppPreferenceRecord.defaultAppcastURL
            }
            if loadedSnapshot.preferences.releasePageURL.isEmpty {
                loadedSnapshot.preferences.releasePageURL = AppPreferenceRecord.defaultReleasePageURL
            }
            restoreSnapshot(loadedSnapshot)
        } catch {
            snapshot = .empty
            lastOperationMessage = "初始化存储失败：\(error.localizedDescription)"
        }

        applyAppearancePreference()
        configureSparkleUpdater()
        if snapshot.notes.isEmpty {
            createNote()
        }
        await refreshStorageStatus()
    }

    func createNote() {
        let id = snapshot.insertDraftNote()
        selectedNoteID = id
        scheduleAutosave(immediate: true)
    }

    func saveQuickCaptureNote(body: String) async {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return }

        let noteID = snapshot.insertDraftNote()
        snapshot.updateNote(id: noteID) {
            $0.updateBody(trimmedBody)
        }
        scheduleAutosave(immediate: true)
        queueOrganization(
            noteID: noteID,
            overwriteManualMetadata: false,
            delay: automaticOrganizationGraceInterval
        )
    }

    func deleteSelectedNote() {
        guard let selectedNoteID else { return }
        snapshot.deleteNote(id: selectedNoteID)
        syncSelectionWithVisibleNotes()
        scheduleAutosave(immediate: true)
    }

    func changeScope(_ scope: LibrarySidebarScope) {
        selectedScope = scope
        syncSelectionWithVisibleNotes()
    }

    func changeSelection(to noteID: UUID?) {
        let previous = selectedNoteID
        selectedNoteID = noteID
        if let previous, previous != noteID {
            scheduleAutosave(immediate: true)
            queueOrganization(
                noteID: previous,
                overwriteManualMetadata: false,
                delay: automaticOrganizationGraceInterval
            )
        }
    }

    func handleSearchChange() {
        syncSelectionWithVisibleNotes()
    }

    func handleSceneDeactivation() {
        scheduleAutosave(immediate: true)
        if let selectedNoteID {
            queueOrganization(
                noteID: selectedNoteID,
                overwriteManualMetadata: false,
                delay: automaticOrganizationGraceInterval
            )
        }
    }

    func handleSceneActivation() async {
        await reloadLibraryFromDisk(showMessage: false)
    }

    func updateBody(for noteID: UUID, body: String) {
        snapshot.updateNote(id: noteID) {
            $0.updateBody(body)
        }
        scheduleAutosave()
    }

    func updateTitle(for noteID: UUID, title: String) {
        snapshot.updateNote(id: noteID) {
            $0.applyManualTitle(title)
        }
        scheduleAutosave()
    }

    func updateCategory(for noteID: UUID, category: String) {
        snapshot.updateNote(id: noteID) {
            $0.applyManualCategory(category)
        }
        scheduleAutosave()
    }

    func updateFolder(for noteID: UUID, folderName: String) {
        let folder = snapshot.upsertFolder(named: folderName.isEmpty ? "未分类" : folderName)
        snapshot.updateNote(id: noteID) {
            $0.applyManualFolder(id: folder.id)
        }
        scheduleAutosave()
    }

    func updateTags(for noteID: UUID, tagText: String) {
        let names = tagText
            .split(separator: ",")
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let tags = snapshot.upsertTags(named: names)
        snapshot.updateNote(id: noteID) {
            $0.applyManualTags(ids: tags.map(\.id))
        }
        scheduleAutosave()
    }

    func folderName(for note: NoteRecord) -> String {
        snapshot.folder(id: note.folderID)?.name ?? "待整理"
    }

    func folderName(for noteID: UUID) -> String {
        guard let note = snapshot.note(id: noteID) else { return "" }
        return folderName(for: note)
    }

    func tagNames(for note: NoteRecord) -> String {
        snapshot.tags(for: note).map(\.name).joined(separator: ", ")
    }

    func tagNames(for noteID: UUID) -> String {
        guard let note = snapshot.note(id: noteID) else { return "" }
        return tagNames(for: note)
    }

    func sourceBadge(_ source: MetadataSource?) -> String {
        switch source {
        case .ai:
            "AI"
        case .manual:
            "手动"
        case nil:
            "未设"
        }
    }

    func addProfile() {
        let profile = AIProfileRecord(
            displayName: "Custom",
            providerKind: .custom,
            baseURL: ProviderKind.custom.defaultBaseURL,
            model: ProviderKind.custom.defaultModel,
            isActive: snapshot.profiles.isEmpty
        )
        snapshot.upsertProfile(profile)
        scheduleAutosave(immediate: true)
    }

    func updateProfile(_ profile: AIProfileRecord) {
        snapshot.upsertProfile(profile)
        scheduleAutosave(immediate: true)
    }

    func activateProfile(id: UUID) {
        snapshot.activateProfile(id: id)
        scheduleAutosave(immediate: true)
    }

    func removeProfile(id: UUID) {
        snapshot.removeProfile(id: id)
        scheduleAutosave(immediate: true)
    }

    func apiKey(for profile: AIProfileRecord) -> String {
        (try? secretStore.secret(account: profile.keychainAccount)) ?? ""
    }

    func saveAPIKey(_ secret: String, for profile: AIProfileRecord) {
        do {
            if secret.isEmpty {
                try secretStore.deleteSecret(account: profile.keychainAccount)
            } else {
                try secretStore.storeSecret(secret, account: profile.keychainAccount)
            }
            lastOperationMessage = "已更新 \(profile.displayName) 的 API Key。"
        } catch {
            lastOperationMessage = error.localizedDescription
        }
    }

    func openStorageLocation() {
        guard let url = storageRootURL else { return }
        NSWorkspace.shared.open(url)
    }

    func reloadLibraryFromDisk(showMessage: Bool) async {
        do {
            let loadedSnapshot = try await persistence.load()
            let didChange = loadedSnapshot != snapshot
            if didChange {
                restoreSnapshot(loadedSnapshot)
            }
            await refreshStorageStatus()
            if showMessage {
                lastOperationMessage = didChange ? "已从磁盘重新载入笔记库。" : "磁盘里的笔记库已经是最新。"
            }
        } catch {
            if showMessage {
                lastOperationMessage = "重新载入失败：\(error.localizedDescription)"
            }
        }
    }

    func syncLibraryNow() async {
        do {
            try await persistence.save(snapshot)
            await refreshStorageStatus()
            lastOperationMessage = isUsingICloudStorage ? "已同步到 iCloud，并保留本地镜像。" : "已同步到本地存储。"
        } catch {
            lastOperationMessage = "同步失败：\(error.localizedDescription)"
        }
    }

    func checkForUpdates() async {
        let feedURL = snapshot.preferences.appcastURL
        let checker = updateChecker
        let currentVersion = currentVersionString
        updateState = .checking

        if updateInstallationMode.usesSparkle,
           let sparkleUpdateDriver,
           !feedURL.isEmpty {
            sparkleUpdateDriver.configure(
                feedURLString: feedURL,
                automaticallyChecks: snapshot.preferences.checksForUpdatesAutomatically
            )
            sparkleUpdateDriver.checkForUpdates()
            lastOperationMessage = "已发起 Sparkle 更新检查。"
            updateState = .idle
            return
        }

        do {
            let result = try await checker.check(
                currentBuildVersion: currentBuildVersion,
                currentShortVersion: currentVersion,
                feedURLString: feedURL
            )
            switch result {
            case .noUpdate:
                updateState = .upToDate
                if let updateInstallationMessage {
                    lastOperationMessage = updateInstallationMessage
                }
            case let .updateAvailable(release):
                updateState = .available(release)
                if let updateInstallationMessage {
                    lastOperationMessage = updateInstallationMessage
                }
            }
        } catch {
            updateState = .failed(error.localizedDescription)
        }
    }

    func openUpdateDownload(_ release: UpdateRelease) {
        NSWorkspace.shared.open(release.downloadURL)
    }

    func installUpdate(_ release: UpdateRelease) async {
        switch updateInstallationMode {
        case .sparkle:
            updateState = .checking
            if let sparkleUpdateDriver {
                sparkleUpdateDriver.configure(
                    feedURLString: snapshot.preferences.appcastURL,
                    automaticallyChecks: snapshot.preferences.checksForUpdatesAutomatically
                )
                sparkleUpdateDriver.checkForUpdates()
                lastOperationMessage = "已发起 Sparkle 安装更新。"
                updateState = .idle
            } else {
                updateState = .failed("当前构建缺少 Sparkle 更新驱动。")
            }

        case .selfManaged:
            updateState = .installing("正在下载并校验更新...")
            do {
                try await unsignedUpdateInstaller.install(release: release)
                lastOperationMessage = "更新包已准备完成，应用即将退出并安装新版本。"
                updateState = .installing("正在安装更新...")
                NSApp.terminate(nil)
            } catch {
                updateState = .failed(error.localizedDescription)
            }

        case .downloadOnly:
            openUpdateDownload(release)
            updateState = .idle
        }
    }

    func openReleasePage() {
        guard let url = URL(string: snapshot.preferences.releasePageURL), !snapshot.preferences.releasePageURL.isEmpty else { return }
        NSWorkspace.shared.open(url)
    }

    func updateAppearance(_ appearance: AppAppearancePreference) {
        guard snapshot.preferences.appearance != appearance else { return }
        snapshot.updatePreferences {
            $0.appearance = appearance
        }
        applyAppearancePreference()
        scheduleAutosave(immediate: true)
    }

    func updatePreferences(appcastURL: String, releasePageURL: String, checksForUpdatesAutomatically: Bool) {
        snapshot.updatePreferences {
            $0.appcastURL = appcastURL
            $0.releasePageURL = releasePageURL
            $0.checksForUpdatesAutomatically = checksForUpdatesAutomatically
        }
        configureSparkleUpdater()
        scheduleAutosave(immediate: true)
    }

    func retryOrganizationForSelectedNote() {
        guard let selectedNoteID else { return }
        retryOrganization(noteID: selectedNoteID)
    }

    func retryOrganization(noteID: UUID) {
        queueOrganization(
            noteID: noteID,
            overwriteManualMetadata: true,
            delay: manualOrganizationGraceInterval
        )
    }

    private func scheduleAutosave(immediate: Bool = false) {
        autosaveTask?.cancel()
        autosaveTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            guard !Task.isCancelled else { return }
            try? await persistence.save(snapshot)
        }
    }

    private func scheduleRetry(for noteID: UUID, attemptCount: Int, overwriteManualMetadata: Bool) {
        let nextRetry = RetryPlanner.nextRetryDate(afterAttempt: attemptCount)
        scheduleRetry(for: noteID, nextRetryAt: nextRetry, overwriteManualMetadata: overwriteManualMetadata)
    }

    private func scheduleRetry(for noteID: UUID, nextRetryAt: Date, overwriteManualMetadata: Bool) {
        retryTasks[noteID]?.cancel()
        queuedOrganizationRequests[noteID] = (queuedOrganizationRequests[noteID] ?? false) || overwriteManualMetadata
        let delay = max(1, nextRetryAt.timeIntervalSinceNow)

        retryTasks[noteID] = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.startQueuedOrganization(noteID: noteID)
        }
    }

    private func currentProfileForOrganization() -> AIProfileRecord? {
        snapshot.activeProfile()
    }

    private var currentVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var currentBuildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? currentVersionString
    }

    private func configureSparkleUpdater() {
        sparkleUpdateDriver?.configure(
            feedURLString: snapshot.preferences.appcastURL,
            automaticallyChecks: snapshot.preferences.checksForUpdatesAutomatically
        )
    }

    private func applyAppearancePreference() {
        NSApp.appearance = appearancePreference.nsAppearance
    }

    private func restoreSnapshot(_ loadedSnapshot: LibrarySnapshot) {
        let previousSelection = selectedNoteID
        snapshot = loadedSnapshot

        if let previousSelection, snapshot.note(id: previousSelection) != nil {
            selectedNoteID = previousSelection
        } else {
            selectedNoteID = snapshot.notes.first?.id
        }

        syncSelectionWithVisibleNotes()
    }

    private func refreshStorageStatus() async {
        do {
            let status = try await persistence.storageStatus()
            storageRootURL = status.activeRootURL
            storageLocationDescription = status.activeRootURL.path(percentEncoded: false)
            storageStatusDescription = storageStatusMessage(for: status)
            isUsingICloudStorage = status.backend == .iCloud
        } catch {
            storageStatusDescription = "无法读取存储状态：\(error.localizedDescription)"
            storageLocationDescription = "无法读取存储目录"
            isUsingICloudStorage = false
        }
    }

    private func storageStatusMessage(for status: StorageLocationStatus) -> String {
        switch status.backend {
        case .iCloud:
            return "当前使用 iCloud 存储，自动保留本地镜像备份。"
        case .local:
            if status.isICloudAvailable {
                return "已检测到 iCloud，但当前仍在使用本地存储。"
            }
            return "当前未连上 iCloud，正在使用本地存储。"
        }
    }

    private func queueOrganization(noteID: UUID, overwriteManualMetadata: Bool, delay: TimeInterval) {
        guard snapshot.note(id: noteID) != nil else { return }

        retryTasks[noteID]?.cancel()
        retryTasks[noteID] = nil
        queuedOrganizationRequests[noteID] = (queuedOrganizationRequests[noteID] ?? false) || overwriteManualMetadata

        if organizationTasks[noteID] != nil {
            if overwriteManualMetadata {
                lastOperationMessage = "AI 正在整理当前笔记，已自动排队再次整理。"
            }
            return
        }

        scheduledOrganizationTasks[noteID]?.cancel()
        scheduledOrganizationTasks[noteID] = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            self?.startQueuedOrganization(noteID: noteID)
        }
    }

    private func startQueuedOrganization(noteID: UUID) {
        scheduledOrganizationTasks[noteID] = nil
        retryTasks[noteID] = nil
        guard organizationTasks[noteID] == nil else { return }

        let overwriteManualMetadata = queuedOrganizationRequests.removeValue(forKey: noteID) ?? false
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.organizeIfNeeded(noteID: noteID, overwriteManualMetadata: overwriteManualMetadata)
        }
        organizationTasks[noteID] = task
    }

    private func organizeIfNeeded(noteID: UUID, overwriteManualMetadata: Bool) async {
        defer {
            organizationTasks[noteID] = nil
            if let queuedOverwrite = queuedOrganizationRequests.removeValue(forKey: noteID) {
                queueOrganization(
                    noteID: noteID,
                    overwriteManualMetadata: queuedOverwrite,
                    delay: manualOrganizationGraceInterval
                )
            }
        }

        guard let note = snapshot.note(id: noteID) else { return }
        guard note.needsOrganization || overwriteManualMetadata else { return }
        guard let profile = currentProfileForOrganization() else {
            lastOperationMessage = "没有可用的模型配置。"
            return
        }

        snapshot.markProcessing(noteID: noteID)
        scheduleAutosave(immediate: true)

        do {
            let payload = try await organizer.organize(note: note, library: snapshot, profile: profile)
            snapshot.applyOrganizationPayload(payload, to: noteID, allowOverwritingManual: overwriteManualMetadata)
            scheduledOrganizationTasks[noteID]?.cancel()
            scheduledOrganizationTasks[noteID] = nil
            retryTasks[noteID]?.cancel()
            retryTasks[noteID] = nil
            lastOperationMessage = "已完成《\(snapshot.note(id: noteID)?.displayTitle ?? "笔记")》的 AI 整理。"
        } catch {
            handleOrganizationFailure(
                error,
                noteID: noteID,
                overwriteManualMetadata: overwriteManualMetadata
            )
        }

        scheduleAutosave(immediate: true)
    }

    private func handleOrganizationFailure(_ error: Error, noteID: UUID, overwriteManualMetadata: Bool) {
        let nextAttempt = (snapshot.jobs.first(where: { $0.noteID == noteID })?.attemptCount ?? 0) + 1

        if let softRetryDelay = softRetryDelay(for: error, attemptCount: nextAttempt) {
            let nextRetryAt = Date().addingTimeInterval(softRetryDelay)
            snapshot.markDeferredRetry(noteID: noteID, nextRetryAt: nextRetryAt)
            scheduleRetry(
                for: noteID,
                nextRetryAt: nextRetryAt,
                overwriteManualMetadata: overwriteManualMetadata
            )
            lastOperationMessage = "AI 还在整理《\(snapshot.note(id: noteID)?.displayTitle ?? "笔记")》，已自动稍后重试。"
            return
        }

        snapshot.markFailure(noteID: noteID, message: error.localizedDescription)
        if shouldScheduleStandardRetry(for: error) {
            let attemptCount = snapshot.jobs.first(where: { $0.noteID == noteID })?.attemptCount ?? 1
            scheduleRetry(
                for: noteID,
                attemptCount: attemptCount,
                overwriteManualMetadata: overwriteManualMetadata
            )
        } else {
            retryTasks[noteID]?.cancel()
            retryTasks[noteID] = nil
        }
        lastOperationMessage = error.localizedDescription
    }

    private func softRetryDelay(for error: Error, attemptCount: Int) -> TimeInterval? {
        if let organizerError = error as? NoteOrganizerError {
            switch organizerError {
            case .invalidResponse, .malformedPayload:
                let index = min(max(attemptCount - 1, 0), softRetryDelays.count - 1)
                return softRetryDelays[index]
            case .missingAPIKey, .invalidBaseURL, .providerFailure:
                return nil
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                let index = min(max(attemptCount - 1, 0), softRetryDelays.count - 1)
                return softRetryDelays[index]
            default:
                return nil
            }
        }

        return nil
    }

    private func shouldScheduleStandardRetry(for error: Error) -> Bool {
        if let organizerError = error as? NoteOrganizerError {
            switch organizerError {
            case .missingAPIKey, .invalidBaseURL:
                return false
            case .invalidResponse, .providerFailure, .malformedPayload:
                return true
            }
        }

        return true
    }

    private func syncSelectionWithVisibleNotes() {
        if let selectedNoteID, filteredNotes.contains(where: { $0.id == selectedNoteID }) {
            return
        }

        selectedNoteID = filteredNotes.first?.id
    }
}
