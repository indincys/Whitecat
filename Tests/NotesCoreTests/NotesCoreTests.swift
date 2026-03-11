import Foundation
import Testing
@testable import NotesCore

@Test("新建笔记默认没有标题并回退正文首行")
func displayTitleFallsBackToBodyPreview() {
    let note = NoteRecord(bodyMarkdown: "\n\n今天要写 Whitecat 的 AI 自动分类")
    #expect(note.title == nil)
    #expect(note.displayTitle == "今天要写 Whitecat 的 AI 自动分类")
}

@Test("标签去重和空白清理")
func taxonomyDeduplicatesAndCollapsesWhitespace() {
    let tags = [" Swift ", "swift", "AI   Agent", "", "AI Agent"].deduplicatedTaxonomyNames()
    #expect(tags == ["Swift", "AI Agent"])
}

@Test("标签输入支持中英文分隔符")
func taxonomySplitSupportsLocalizedSeparators() {
    let tags = "Swift，AI Agent; 产品\n复盘".splitTaxonomyTerms()
    #expect(tags == ["Swift", "AI Agent", "产品", "复盘"])
}

@Test("AI 整理会复用现有文件夹并落库标签")
func organizationPayloadReusesFoldersAndTags() {
    var snapshot = LibrarySnapshot(
        folders: [FolderRecord(name: "项目")],
        tags: [TagRecord(name: "AI")]
    )
    let noteID = snapshot.insertDraftNote()

    snapshot.applyOrganizationPayload(
        OrganizationPayload(title: "白猫实现", category: "开发", tags: ["AI", "Swift"], folderName: "项目"),
        to: noteID,
        allowOverwritingManual: false
    )

    let note = try! #require(snapshot.note(id: noteID))
    #expect(snapshot.folders.count == 1)
    #expect(snapshot.tags.map(\.name).sorted() == ["AI", "Swift"])
    #expect(note.displayTitle == "白猫实现")
    #expect(note.organizationStatus == .organized)
}

@Test("手动锁定的标题不会被自动整理覆盖")
func manualMetadataStaysLocked() {
    var snapshot = LibrarySnapshot()
    let noteID = snapshot.insertDraftNote()
    snapshot.updateNote(id: noteID) {
        $0.applyManualTitle("手动标题")
    }

    snapshot.applyOrganizationPayload(
        OrganizationPayload(title: "AI 标题", category: "工作", tags: ["规划"], folderName: "收件箱"),
        to: noteID,
        allowOverwritingManual: false
    )

    let note = try! #require(snapshot.note(id: noteID))
    #expect(note.title == "手动标题")
    #expect(note.category == "工作")
}

@Test("失败重试采用指数退避")
func retryPlannerUsesExponentialBackoff() {
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(RetryPlanner.nextRetryDate(afterAttempt: 1, now: now).timeIntervalSince(now) == 60)
    #expect(RetryPlanner.nextRetryDate(afterAttempt: 2, now: now).timeIntervalSince(now) == 120)
    #expect(RetryPlanner.nextRetryDate(afterAttempt: 10, now: now).timeIntervalSince(now) == 3600)
}

@Test("旧配置缺少提示词字段时会回填默认提示词")
func profileDecodingBackfillsDefaultPrompt() throws {
    let json = """
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "displayName": "OpenAI",
      "providerKind": "openai",
      "baseURL": "https://api.openai.com/v1",
      "model": "gpt-4.1-mini",
      "requestPath": "/chat/completions",
      "isActive": true,
      "createdAt": "2026-03-10T00:00:00Z",
      "updatedAt": "2026-03-10T00:00:00Z"
    }
    """

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let profile = try decoder.decode(AIProfileRecord.self, from: Data(json.utf8))

    #expect(profile.trimmedOrganizationPrompt == AIProfileRecord.defaultOrganizationPrompt)
}

@Test("运行时补默认配置不会覆盖已有笔记")
func snapshotHydrationPreservesExistingNotes() {
    let note = NoteRecord(bodyMarkdown: "保留这条笔记")
    let snapshot = LibrarySnapshot(
        notes: [note],
        profiles: [],
        preferences: AppPreferenceRecord(appcastURL: " ", releasePageURL: "")
    ).hydratedForRuntime()

    #expect(snapshot.notes == [note])
    #expect(!snapshot.profiles.isEmpty)
    #expect(snapshot.preferences.appcastURL == AppPreferenceRecord.defaultAppcastURL)
    #expect(snapshot.preferences.releasePageURL == AppPreferenceRecord.defaultReleasePageURL)
}

@Test("旧偏好配置缺少外观字段时默认跟随系统")
func preferencesDecodingBackfillsSystemAppearance() throws {
    let json = """
    {
      "appcastURL": "https://example.com/appcast.xml",
      "releasePageURL": "https://example.com/releases",
      "checksForUpdatesAutomatically": true,
      "updatedAt": "2026-03-10T00:00:00Z"
    }
    """

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let preferences = try decoder.decode(AppPreferenceRecord.self, from: Data(json.utf8))

    #expect(preferences.appearance == .system)
}

@Test("旧笔记缺少新版状态字段时也能恢复")
func noteDecodingBackfillsNewFields() throws {
    let json = """
    {
      "id": "00000000-0000-0000-0000-000000000002",
      "bodyMarkdown": "旧笔记正文",
      "organizationStatus": "organized",
      "createdAt": "2026-03-10T00:00:00Z",
      "updatedAt": "2026-03-10T00:00:00Z"
    }
    """

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let note = try decoder.decode(NoteRecord.self, from: Data(json.utf8))

    #expect(note.contentHash == NoteRecord.hash(for: "旧笔记正文"))
    #expect(note.lastOrganizedContentHash == note.contentHash)
    #expect(note.organizationStatus == .organized)
}

@Test("主库损坏时会回退到备份文件")
func persistenceFallsBackToBackup() async throws {
    let fileManager = FileManager.default
    let persistence = LibraryPersistence(
        configuration: .init(
            appDirectoryName: "WhitecatTests-\(UUID().uuidString)",
            metadataFilename: "library.json",
            preferICloud: false
        )
    )

    var snapshot = LibrarySnapshot()
    let noteID = snapshot.insertDraftNote()
    snapshot.updateNote(id: noteID) {
        $0.updateBody("备份里的正文")
    }
    try await persistence.save(snapshot)

    let storageRoot = try await persistence.storageRootURL()
    defer {
        try? fileManager.removeItem(at: storageRoot)
    }

    let primaryURL = storageRoot.appending(path: "library.json")
    let backupURL = storageRoot.appending(path: "library-backup.json")
    #expect(fileManager.fileExists(atPath: backupURL.path(percentEncoded: false)))
    let backupContents = try String(contentsOf: backupURL, encoding: .utf8)
    #expect(backupContents.contains("备份里的正文"))
    try Data("not-json".utf8).write(to: primaryURL, options: .atomic)

    let recoveredSnapshot = try await persistence.load()
    #expect(recoveredSnapshot.note(id: noteID)?.bodyMarkdown == "备份里的正文")
}
