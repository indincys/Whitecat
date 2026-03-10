import CryptoKit
import Foundation

public enum MetadataSource: String, Codable, CaseIterable, Sendable {
    case ai
    case manual
}

public enum OrganizationStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case processing
    case organized
    case failed
}

public enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI = "openai"
    case deepSeek = "deepseek"
    case qwen = "qwen"
    case kimi = "kimi"
    case zAI = "z.ai"
    case doubao = "doubao"
    case custom = "custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .deepSeek:
            "DeepSeek"
        case .qwen:
            "Qwen"
        case .kimi:
            "Kimi"
        case .zAI:
            "Z.ai"
        case .doubao:
            "Doubao"
        case .custom:
            "Custom"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .openAI:
            "https://api.openai.com/v1"
        case .deepSeek:
            "https://api.deepseek.com/v1"
        case .qwen:
            "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .kimi:
            "https://api.moonshot.cn/v1"
        case .zAI:
            "https://api.z.ai/api/paas/v4"
        case .doubao:
            "https://ark.cn-beijing.volces.com/api/v3"
        case .custom:
            "https://example.com/v1"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openAI:
            "gpt-4.1-mini"
        case .deepSeek:
            "deepseek-chat"
        case .qwen:
            "qwen-plus"
        case .kimi:
            "moonshot-v1-8k"
        case .zAI:
            "glm-4.5-air"
        case .doubao:
            "doubao-seed-1-6-thinking"
        case .custom:
            "your-model"
        }
    }
}

public struct OrganizationPayload: Codable, Equatable, Sendable {
    public var title: String
    public var category: String
    public var tags: [String]
    public var folderName: String

    public init(title: String, category: String, tags: [String], folderName: String) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tags = tags
        self.folderName = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct FolderRecord: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var normalizedName: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, createdAt: Date = .now, updatedAt: Date = .now) {
        let normalized = Self.normalizeName(name)
        self.id = id
        self.name = normalized.display
        self.normalizedName = normalized.key
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func normalizeName(_ value: String) -> (display: String, key: String) {
        let collapsed = value.collapsedWhitespace().trimmingCharacters(in: .whitespacesAndNewlines)
        let display = collapsed.isEmpty ? "未分类" : collapsed
        return (display, display.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current))
    }
}

public struct TagRecord: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var normalizedName: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, createdAt: Date = .now, updatedAt: Date = .now) {
        let normalized = Self.normalizeName(name)
        self.id = id
        self.name = normalized.display
        self.normalizedName = normalized.key
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func normalizeName(_ value: String) -> (display: String, key: String) {
        FolderRecord.normalizeName(value)
    }
}

public struct AIProfileRecord: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var displayName: String
    public var providerKind: ProviderKind
    public var baseURL: String
    public var model: String
    public var requestPath: String
    public var isActive: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        providerKind: ProviderKind,
        baseURL: String,
        model: String,
        requestPath: String = "/chat/completions",
        isActive: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.providerKind = providerKind
        self.baseURL = baseURL
        self.model = model
        self.requestPath = requestPath
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var keychainAccount: String {
        "profile-\(id.uuidString)"
    }

    public var trimmedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedRequestPath: String {
        let trimmed = requestPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "/chat/completions" : trimmed
    }
}

public struct OrganizationJobRecord: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var noteID: UUID
    public var attemptCount: Int
    public var nextRetryAt: Date?
    public var lastErrorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        noteID: UUID,
        attemptCount: Int = 0,
        nextRetryAt: Date? = nil,
        lastErrorMessage: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.noteID = noteID
        self.attemptCount = attemptCount
        self.nextRetryAt = nextRetryAt
        self.lastErrorMessage = lastErrorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct AppPreferenceRecord: Codable, Equatable, Hashable, Sendable {
    public static let defaultAppcastURL = "https://indincys.github.io/Whitecat/appcast.xml"
    public static let defaultReleasePageURL = "https://github.com/indincys/Whitecat/releases"

    public var appcastURL: String
    public var releasePageURL: String
    public var checksForUpdatesAutomatically: Bool
    public var updatedAt: Date

    public init(
        appcastURL: String = AppPreferenceRecord.defaultAppcastURL,
        releasePageURL: String = AppPreferenceRecord.defaultReleasePageURL,
        checksForUpdatesAutomatically: Bool = false,
        updatedAt: Date = .now
    ) {
        self.appcastURL = appcastURL
        self.releasePageURL = releasePageURL
        self.checksForUpdatesAutomatically = checksForUpdatesAutomatically
        self.updatedAt = updatedAt
    }
}

public struct NoteRecord: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var bodyMarkdown: String
    public var title: String?
    public var titleSource: MetadataSource?
    public var category: String?
    public var categorySource: MetadataSource?
    public var folderID: UUID?
    public var folderSource: MetadataSource?
    public var tagIDs: [UUID]
    public var tagsSource: MetadataSource?
    public var organizationStatus: OrganizationStatus
    public var contentHash: String
    public var lastOrganizedContentHash: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var lastOrganizedAt: Date?
    public var lastFailedAt: Date?
    public var lastErrorMessage: String?

    public init(
        id: UUID = UUID(),
        bodyMarkdown: String = "",
        title: String? = nil,
        titleSource: MetadataSource? = nil,
        category: String? = nil,
        categorySource: MetadataSource? = nil,
        folderID: UUID? = nil,
        folderSource: MetadataSource? = nil,
        tagIDs: [UUID] = [],
        tagsSource: MetadataSource? = nil,
        organizationStatus: OrganizationStatus = .pending,
        contentHash: String? = nil,
        lastOrganizedContentHash: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastOrganizedAt: Date? = nil,
        lastFailedAt: Date? = nil,
        lastErrorMessage: String? = nil
    ) {
        self.id = id
        self.bodyMarkdown = bodyMarkdown
        self.title = title
        self.titleSource = titleSource
        self.category = category
        self.categorySource = categorySource
        self.folderID = folderID
        self.folderSource = folderSource
        self.tagIDs = tagIDs
        self.tagsSource = tagsSource
        self.organizationStatus = organizationStatus
        self.contentHash = contentHash ?? Self.hash(for: bodyMarkdown)
        self.lastOrganizedContentHash = lastOrganizedContentHash
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOrganizedAt = lastOrganizedAt
        self.lastFailedAt = lastFailedAt
        self.lastErrorMessage = lastErrorMessage
    }

    public static func draft(now: Date = .now) -> NoteRecord {
        NoteRecord(createdAt: now, updatedAt: now)
    }

    public static func hash(for body: String) -> String {
        SHA256.hash(data: Data(body.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }

    public var isEmptyDraft: Bool {
        title?.isBlank != false && bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var bodyPreview: String {
        bodyMarkdown
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "空白笔记"
    }

    public var displayTitle: String {
        if let title, !title.isBlank {
            return title
        }
        return bodyPreview
    }

    public var needsOrganization: Bool {
        let trimmedBody = bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedBody.isEmpty && contentHash != lastOrganizedContentHash
    }

    public var manualTitleLocked: Bool {
        titleSource == .manual
    }

    public var manualCategoryLocked: Bool {
        categorySource == .manual
    }

    public var manualFolderLocked: Bool {
        folderSource == .manual
    }

    public var manualTagsLocked: Bool {
        tagsSource == .manual
    }

    public mutating func updateBody(_ value: String, at date: Date = .now) {
        bodyMarkdown = value
        updatedAt = date
        contentHash = Self.hash(for: value)
        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, organizationStatus == .organized {
            organizationStatus = .pending
        }
    }

    public mutating func markProcessing(at date: Date = .now) {
        organizationStatus = .processing
        updatedAt = date
    }

    public mutating func markOrganized(at date: Date = .now) {
        organizationStatus = .organized
        updatedAt = date
        lastOrganizedAt = date
        lastErrorMessage = nil
        lastOrganizedContentHash = contentHash
    }

    public mutating func markFailed(message: String, at date: Date = .now) {
        organizationStatus = .failed
        updatedAt = date
        lastFailedAt = date
        lastErrorMessage = message
    }

    public mutating func applyManualTitle(_ value: String, at date: Date = .now) {
        title = value.nonEmptyTrimmed
        titleSource = .manual
        updatedAt = date
    }

    public mutating func applyManualCategory(_ value: String, at date: Date = .now) {
        category = value.nonEmptyTrimmed
        categorySource = .manual
        updatedAt = date
    }

    public mutating func applyManualFolder(id: UUID?, at date: Date = .now) {
        folderID = id
        folderSource = .manual
        updatedAt = date
    }

    public mutating func applyManualTags(ids: [UUID], at date: Date = .now) {
        tagIDs = ids
        tagsSource = .manual
        updatedAt = date
    }
}

public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public var notes: [NoteRecord]
    public var folders: [FolderRecord]
    public var tags: [TagRecord]
    public var profiles: [AIProfileRecord]
    public var jobs: [OrganizationJobRecord]
    public var preferences: AppPreferenceRecord

    public init(
        notes: [NoteRecord] = [],
        folders: [FolderRecord] = [],
        tags: [TagRecord] = [],
        profiles: [AIProfileRecord] = ProviderKind.allCases.enumerated().map { index, provider in
            AIProfileRecord(
                displayName: provider.displayName,
                providerKind: provider,
                baseURL: provider.defaultBaseURL,
                model: provider.defaultModel,
                isActive: index == 0
            )
        },
        jobs: [OrganizationJobRecord] = [],
        preferences: AppPreferenceRecord = AppPreferenceRecord()
    ) {
        self.notes = notes
        self.folders = folders
        self.tags = tags
        self.profiles = profiles
        self.jobs = jobs
        self.preferences = preferences
    }

    public static let empty = LibrarySnapshot()

    public func note(id: UUID?) -> NoteRecord? {
        guard let id else { return nil }
        return notes.first(where: { $0.id == id })
    }

    public func folder(id: UUID?) -> FolderRecord? {
        guard let id else { return nil }
        return folders.first(where: { $0.id == id })
    }

    public func tag(id: UUID) -> TagRecord? {
        tags.first(where: { $0.id == id })
    }

    public func activeProfile() -> AIProfileRecord? {
        profiles.first(where: \.isActive) ?? profiles.first
    }

    public func tags(for note: NoteRecord) -> [TagRecord] {
        note.tagIDs.compactMap(tag(id:))
    }

    public func folderName(for note: NoteRecord) -> String {
        folder(id: note.folderID)?.name ?? "待整理"
    }

    public func filteredNotes(searchText: String = "", scope: LibrarySidebarScope) -> [NoteRecord] {
        let query = searchText.collapsedWhitespace().lowercased()

        return notes
            .filter { note in
                switch scope {
                case .all:
                    true
                case .pending:
                    note.organizationStatus != .organized
                case .recent:
                    Calendar.current.isDate(note.updatedAt, equalTo: .now, toGranularity: .month)
                case let .folder(folderID):
                    note.folderID == folderID
                case let .tag(tagID):
                    note.tagIDs.contains(tagID)
                }
            }
            .filter { note in
                guard !query.isEmpty else { return true }
                let tagNames = tags(for: note).map(\.name).joined(separator: " ")
                let haystack = [
                    note.displayTitle,
                    note.bodyMarkdown,
                    note.category ?? "",
                    folderName(for: note),
                    tagNames
                ]
                .joined(separator: "\n")
                .lowercased()
                return haystack.contains(query)
            }
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
    }

    public func nextRetryJob(now: Date = .now) -> OrganizationJobRecord? {
        jobs
            .filter { ($0.nextRetryAt ?? .distantPast) <= now }
            .sorted { lhs, rhs in
                (lhs.nextRetryAt ?? .distantPast) < (rhs.nextRetryAt ?? .distantPast)
            }
            .first
    }

    public mutating func insertDraftNote(now: Date = .now) -> UUID {
        let note = NoteRecord.draft(now: now)
        notes.insert(note, at: 0)
        return note.id
    }

    public mutating func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
        jobs.removeAll { $0.noteID == id }
    }

    public mutating func updateNote(id: UUID, _ mutate: (inout NoteRecord) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        mutate(&notes[index])
    }

    public mutating func activateProfile(id: UUID) {
        for index in profiles.indices {
            profiles[index].isActive = profiles[index].id == id
            profiles[index].updatedAt = .now
        }
    }

    public mutating func upsertProfile(_ profile: AIProfileRecord) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        if profile.isActive {
            activateProfile(id: profile.id)
        }
    }

    public mutating func removeProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        if profiles.allSatisfy({ !$0.isActive }), let first = profiles.first {
            activateProfile(id: first.id)
        }
    }

    public mutating func applyOrganizationPayload(
        _ payload: OrganizationPayload,
        to noteID: UUID,
        allowOverwritingManual: Bool,
        at date: Date = .now
    ) {
        guard let noteIndex = notes.firstIndex(where: { $0.id == noteID }) else { return }

        let folder = upsertFolder(named: payload.folderName.isEmpty ? "未分类" : payload.folderName, at: date)
        let tagRecords = upsertTags(named: payload.tags, at: date)
        let tagIDs = tagRecords.map(\.id)

        if allowOverwritingManual || !notes[noteIndex].manualTitleLocked {
            notes[noteIndex].title = payload.title.nonEmptyTrimmed ?? notes[noteIndex].title
            notes[noteIndex].titleSource = payload.title.nonEmptyTrimmed == nil ? notes[noteIndex].titleSource : .ai
        }

        if allowOverwritingManual || !notes[noteIndex].manualCategoryLocked {
            notes[noteIndex].category = payload.category.nonEmptyTrimmed ?? notes[noteIndex].category
            notes[noteIndex].categorySource = payload.category.nonEmptyTrimmed == nil ? notes[noteIndex].categorySource : .ai
        }

        if allowOverwritingManual || !notes[noteIndex].manualFolderLocked {
            notes[noteIndex].folderID = folder.id
            notes[noteIndex].folderSource = .ai
        }

        if allowOverwritingManual || !notes[noteIndex].manualTagsLocked {
            notes[noteIndex].tagIDs = tagIDs
            notes[noteIndex].tagsSource = .ai
        }

        notes[noteIndex].markOrganized(at: date)
        jobs.removeAll { $0.noteID == noteID }
    }

    public mutating func markProcessing(noteID: UUID, at date: Date = .now) {
        updateNote(id: noteID) {
            $0.markProcessing(at: date)
        }

        if let index = jobs.firstIndex(where: { $0.noteID == noteID }) {
            jobs[index].updatedAt = date
        } else {
            jobs.append(OrganizationJobRecord(noteID: noteID, updatedAt: date))
        }
    }

    public mutating func markFailure(noteID: UUID, message: String, at date: Date = .now) {
        updateNote(id: noteID) {
            $0.markFailed(message: message, at: date)
        }

        if let index = jobs.firstIndex(where: { $0.noteID == noteID }) {
            jobs[index].attemptCount += 1
            jobs[index].lastErrorMessage = message
            jobs[index].nextRetryAt = RetryPlanner.nextRetryDate(afterAttempt: jobs[index].attemptCount, now: date)
            jobs[index].updatedAt = date
        } else {
            jobs.append(
                OrganizationJobRecord(
                    noteID: noteID,
                    attemptCount: 1,
                    nextRetryAt: RetryPlanner.nextRetryDate(afterAttempt: 1, now: date),
                    lastErrorMessage: message,
                    createdAt: date,
                    updatedAt: date
                )
            )
        }
    }

    public mutating func resetJob(noteID: UUID) {
        jobs.removeAll { $0.noteID == noteID }
    }

    public mutating func updatePreferences(_ mutate: (inout AppPreferenceRecord) -> Void) {
        mutate(&preferences)
        preferences.updatedAt = .now
    }

    @discardableResult
    public mutating func upsertFolder(named name: String, at date: Date = .now) -> FolderRecord {
        let normalized = FolderRecord.normalizeName(name)
        if let index = folders.firstIndex(where: { $0.normalizedName == normalized.key }) {
            folders[index].name = normalized.display
            folders[index].updatedAt = date
            return folders[index]
        }

        let folder = FolderRecord(name: normalized.display, createdAt: date, updatedAt: date)
        folders.append(folder)
        folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return folder
    }

    @discardableResult
    public mutating func upsertTag(named name: String, at date: Date = .now) -> TagRecord? {
        let normalized = TagRecord.normalizeName(name)
        guard !normalized.display.isEmpty else { return nil }

        if let index = tags.firstIndex(where: { $0.normalizedName == normalized.key }) {
            tags[index].name = normalized.display
            tags[index].updatedAt = date
            return tags[index]
        }

        let tag = TagRecord(name: normalized.display, createdAt: date, updatedAt: date)
        tags.append(tag)
        tags.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return tag
    }

    public mutating func upsertTags(named names: [String], at date: Date = .now) -> [TagRecord] {
        names
            .deduplicatedTaxonomyNames()
            .compactMap { upsertTag(named: $0, at: date) }
    }
}

public enum LibrarySidebarScope: Hashable, Sendable {
    case all
    case pending
    case recent
    case folder(UUID)
    case tag(UUID)
}

public enum RetryPlanner {
    public static func nextRetryDate(afterAttempt attempt: Int, now: Date = .now) -> Date {
        let clampedAttempt = max(1, attempt)
        let delay = min(pow(2.0, Double(clampedAttempt - 1)) * 60.0, 60.0 * 60.0)
        return now.addingTimeInterval(delay)
    }
}

public extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func collapsedWhitespace() -> String {
        replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public extension Array where Element == String {
    func deduplicatedTaxonomyNames() -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for value in self {
            guard let trimmed = value.nonEmptyTrimmed else { continue }
            let normalized = FolderRecord.normalizeName(trimmed)
            if seen.insert(normalized.key).inserted {
                ordered.append(normalized.display)
            }
        }

        return ordered
    }
}
