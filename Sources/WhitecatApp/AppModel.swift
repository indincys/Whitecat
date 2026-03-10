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
    @Published var lastOperationMessage: String?

    enum UpdateState: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateRelease)
        case failed(String)
    }

    private let persistence: LibraryPersistence
    private let organizer: NoteOrganizer
    private let secretStore: SecretStoring
    private let updateChecker: ManualUpdateChecker
    private let sparkleUpdateDriver: SparkleUpdateDriver?
    private var autosaveTask: Task<Void, Never>?
    private var retryTasks: [UUID: Task<Void, Never>] = [:]
    private var storageRootURL: URL?

    init(
        persistence: LibraryPersistence = LibraryPersistence(),
        organizer: NoteOrganizer,
        secretStore: SecretStoring,
        updateChecker: ManualUpdateChecker = ManualUpdateChecker(),
        sparkleUpdateDriver: SparkleUpdateDriver? = nil
    ) {
        self.persistence = persistence
        self.organizer = organizer
        self.secretStore = secretStore
        self.updateChecker = updateChecker
        self.sparkleUpdateDriver = sparkleUpdateDriver
    }

    var filteredNotes: [NoteRecord] {
        snapshot.filteredNotes(searchText: searchText, scope: selectedScope)
    }

    var selectedNote: NoteRecord? {
        snapshot.note(id: selectedNoteID)
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
            snapshot = loadedSnapshot

            if let firstNote = filteredNotes.first {
                selectedNoteID = firstNote.id
            }
            if snapshot.notes.isEmpty {
                createNote()
            }
            if let url = try? await persistence.storageRootURL() {
                storageRootURL = url
                storageLocationDescription = url.path()
            }
        } catch {
            snapshot = .empty
            lastOperationMessage = "初始化存储失败：\(error.localizedDescription)"
        }
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
        await organizeIfNeeded(noteID: noteID, overwriteManualMetadata: false)
    }

    func deleteSelectedNote() {
        guard let selectedNoteID else { return }
        snapshot.deleteNote(id: selectedNoteID)
        self.selectedNoteID = filteredNotes.first?.id
        scheduleAutosave(immediate: true)
    }

    func changeScope(_ scope: LibrarySidebarScope) {
        selectedScope = scope
        if let selectedNoteID, filteredNotes.contains(where: { $0.id == selectedNoteID }) {
            return
        }
        self.selectedNoteID = filteredNotes.first?.id
    }

    func changeSelection(to noteID: UUID?) {
        let previous = selectedNoteID
        selectedNoteID = noteID
        if let previous, previous != noteID {
            Task {
                await self.organizeIfNeeded(noteID: previous, overwriteManualMetadata: false)
            }
        }
    }

    func handleSceneDeactivation() {
        if let selectedNoteID {
            Task {
                await self.organizeIfNeeded(noteID: selectedNoteID, overwriteManualMetadata: false)
            }
        }
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

    func tagNames(for note: NoteRecord) -> String {
        snapshot.tags(for: note).map(\.name).joined(separator: ", ")
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

    func checkForUpdates() async {
        let feedURL = snapshot.preferences.appcastURL
        let checker = updateChecker
        let currentVersion = currentVersionString
        updateState = .checking

        if let sparkleUpdateDriver, !feedURL.isEmpty {
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
            let result = try await checker.check(currentVersion: currentVersion, feedURLString: feedURL)
            switch result {
            case .noUpdate:
                updateState = .upToDate
            case let .updateAvailable(release):
                updateState = .available(release)
            }
        } catch {
            updateState = .failed(error.localizedDescription)
        }
    }

    func openUpdateDownload(_ release: UpdateRelease) {
        NSWorkspace.shared.open(release.downloadURL)
    }

    func openReleasePage() {
        guard let url = URL(string: snapshot.preferences.releasePageURL), !snapshot.preferences.releasePageURL.isEmpty else { return }
        NSWorkspace.shared.open(url)
    }

    func updatePreferences(appcastURL: String, releasePageURL: String, checksForUpdatesAutomatically: Bool) {
        snapshot.updatePreferences {
            $0.appcastURL = appcastURL
            $0.releasePageURL = releasePageURL
            $0.checksForUpdatesAutomatically = checksForUpdatesAutomatically
        }
        scheduleAutosave(immediate: true)
    }

    func retryOrganizationForSelectedNote() {
        guard let selectedNoteID else { return }
        Task {
            await self.organizeIfNeeded(noteID: selectedNoteID, overwriteManualMetadata: true)
        }
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

    private func scheduleRetry(for noteID: UUID, attemptCount: Int) {
        retryTasks[noteID]?.cancel()
        let nextRetry = RetryPlanner.nextRetryDate(afterAttempt: attemptCount)
        let delay = max(1, nextRetry.timeIntervalSinceNow)

        retryTasks[noteID] = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.organizeIfNeeded(noteID: noteID, overwriteManualMetadata: false)
        }
    }

    private func currentProfileForOrganization() -> AIProfileRecord? {
        snapshot.activeProfile()
    }

    private var currentVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    func organizeIfNeeded(noteID: UUID, overwriteManualMetadata: Bool) async {
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
            retryTasks[noteID]?.cancel()
            retryTasks[noteID] = nil
            lastOperationMessage = "已完成《\(snapshot.note(id: noteID)?.displayTitle ?? "笔记")》的 AI 整理。"
        } catch {
            snapshot.markFailure(noteID: noteID, message: error.localizedDescription)
            let attemptCount = snapshot.jobs.first(where: { $0.noteID == noteID })?.attemptCount ?? 1
            scheduleRetry(for: noteID, attemptCount: attemptCount)
            lastOperationMessage = error.localizedDescription
        }

        scheduleAutosave(immediate: true)
    }
}
