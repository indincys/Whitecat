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

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case normalizedName
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedName = try container.decode(String.self, forKey: .name)
        let normalized = Self.normalizeName(decodedName)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = normalized.display
        normalizedName = normalized.key
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(normalizedName, forKey: .normalizedName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
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

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case normalizedName
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedName = try container.decode(String.self, forKey: .name)
        let normalized = Self.normalizeName(decodedName)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = normalized.display
        normalizedName = normalized.key
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(normalizedName, forKey: .normalizedName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public struct AIProfileRecord: Identifiable, Codable, Equatable, Hashable, Sendable {
    public static let defaultOrganizationPrompt = """
    按照 Whitecat 的整理方式处理这条笔记：
    1. 优先概括正文真实主题，不要套模板。
    2. 标题简洁、明确，适合在列表里快速扫读。
    3. category 只保留一个最核心的大类。
    4. tags 只保留高价值关键词，避免泛标签和重复标签。
    5. folderName 表示最适合收纳这条笔记的单层文件夹，尽量复用已有文件夹。
    6. 如果正文是临时想法、待办、记录，请按内容语义整理，不要一律归到同一个文件夹。
    """

    public var id: UUID
    public var displayName: String
    public var providerKind: ProviderKind
    public var baseURL: String
    public var model: String
    public var requestPath: String
    public var organizationPrompt: String
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
        organizationPrompt: String = AIProfileRecord.defaultOrganizationPrompt,
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
        self.organizationPrompt = organizationPrompt
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

    public var trimmedOrganizationPrompt: String {
        let trimmed = organizationPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultOrganizationPrompt : trimmed
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case providerKind
        case baseURL
        case model
        case requestPath
        case organizationPrompt
        case isActive
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        providerKind = try container.decode(ProviderKind.self, forKey: .providerKind)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        model = try container.decode(String.self, forKey: .model)
        requestPath = try container.decodeIfPresent(String.self, forKey: .requestPath) ?? "/chat/completions"
        organizationPrompt = try container.decodeIfPresent(String.self, forKey: .organizationPrompt) ?? Self.defaultOrganizationPrompt
        isActive = try container.decode(Bool.self, forKey: .isActive)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(providerKind, forKey: .providerKind)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(model, forKey: .model)
        try container.encode(requestPath, forKey: .requestPath)
        try container.encode(trimmedOrganizationPrompt, forKey: .organizationPrompt)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
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

    enum CodingKeys: String, CodingKey {
        case id
        case noteID
        case attemptCount
        case nextRetryAt
        case lastErrorMessage
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        noteID = try container.decode(UUID.self, forKey: .noteID)
        attemptCount = try container.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
        nextRetryAt = try container.decodeIfPresent(Date.self, forKey: .nextRetryAt)
        lastErrorMessage = try container.decodeIfPresent(String.self, forKey: .lastErrorMessage)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(noteID, forKey: .noteID)
        try container.encode(attemptCount, forKey: .attemptCount)
        try container.encode(nextRetryAt, forKey: .nextRetryAt)
        try container.encode(lastErrorMessage, forKey: .lastErrorMessage)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public enum AppAppearancePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }
}

public struct AppPreferenceRecord: Codable, Equatable, Hashable, Sendable {
    public static let defaultAppcastURL = "https://indincys.github.io/Whitecat/appcast.xml"
    public static let defaultReleasePageURL = "https://github.com/indincys/Whitecat/releases"

    public var appcastURL: String
    public var releasePageURL: String
    public var checksForUpdatesAutomatically: Bool
    public var appearance: AppAppearancePreference
    public var updatedAt: Date

    public init(
        appcastURL: String = AppPreferenceRecord.defaultAppcastURL,
        releasePageURL: String = AppPreferenceRecord.defaultReleasePageURL,
        checksForUpdatesAutomatically: Bool = false,
        appearance: AppAppearancePreference = .system,
        updatedAt: Date = .now
    ) {
        self.appcastURL = appcastURL
        self.releasePageURL = releasePageURL
        self.checksForUpdatesAutomatically = checksForUpdatesAutomatically
        self.appearance = appearance
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case appcastURL
        case releasePageURL
        case checksForUpdatesAutomatically
        case appearance
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appcastURL = try container.decodeIfPresent(String.self, forKey: .appcastURL) ?? Self.defaultAppcastURL
        releasePageURL = try container.decodeIfPresent(String.self, forKey: .releasePageURL) ?? Self.defaultReleasePageURL
        checksForUpdatesAutomatically = try container.decodeIfPresent(Bool.self, forKey: .checksForUpdatesAutomatically) ?? false
        appearance = try container.decodeIfPresent(AppAppearancePreference.self, forKey: .appearance) ?? .system
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appcastURL, forKey: .appcastURL)
        try container.encode(releasePageURL, forKey: .releasePageURL)
        try container.encode(checksForUpdatesAutomatically, forKey: .checksForUpdatesAutomatically)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(updatedAt, forKey: .updatedAt)
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

    enum CodingKeys: String, CodingKey {
        case id
        case bodyMarkdown
        case title
        case titleSource
        case category
        case categorySource
        case folderID
        case folderSource
        case tagIDs
        case tagsSource
        case organizationStatus
        case contentHash
        case lastOrganizedContentHash
        case createdAt
        case updatedAt
        case lastOrganizedAt
        case lastFailedAt
        case lastErrorMessage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedBody = try container.decodeIfPresent(String.self, forKey: .bodyMarkdown) ?? ""
        let decodedContentHash = try container.decodeIfPresent(String.self, forKey: .contentHash) ?? Self.hash(for: decodedBody)
        let decodedCreatedAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        let decodedStatus = try container.decodeIfPresent(OrganizationStatus.self, forKey: .organizationStatus) ?? .pending

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bodyMarkdown = decodedBody
        title = try container.decodeIfPresent(String.self, forKey: .title)
        titleSource = try container.decodeIfPresent(MetadataSource.self, forKey: .titleSource)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        categorySource = try container.decodeIfPresent(MetadataSource.self, forKey: .categorySource)
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        folderSource = try container.decodeIfPresent(MetadataSource.self, forKey: .folderSource)
        tagIDs = try container.decodeIfPresent([UUID].self, forKey: .tagIDs) ?? []
        tagsSource = try container.decodeIfPresent(MetadataSource.self, forKey: .tagsSource)
        organizationStatus = decodedStatus == .processing ? .pending : decodedStatus
        contentHash = decodedContentHash
        createdAt = decodedCreatedAt
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? decodedCreatedAt
        lastOrganizedAt = try container.decodeIfPresent(Date.self, forKey: .lastOrganizedAt)
        lastFailedAt = try container.decodeIfPresent(Date.self, forKey: .lastFailedAt)
        lastErrorMessage = try container.decodeIfPresent(String.self, forKey: .lastErrorMessage)

        if let storedLastHash = try container.decodeIfPresent(String.self, forKey: .lastOrganizedContentHash) {
            lastOrganizedContentHash = storedLastHash
        } else if organizationStatus == .organized, !decodedBody.isBlank {
            lastOrganizedContentHash = decodedContentHash
        } else {
            lastOrganizedContentHash = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(bodyMarkdown, forKey: .bodyMarkdown)
        try container.encode(title, forKey: .title)
        try container.encode(titleSource, forKey: .titleSource)
        try container.encode(category, forKey: .category)
        try container.encode(categorySource, forKey: .categorySource)
        try container.encode(folderID, forKey: .folderID)
        try container.encode(folderSource, forKey: .folderSource)
        try container.encode(tagIDs, forKey: .tagIDs)
        try container.encode(tagsSource, forKey: .tagsSource)
        try container.encode(organizationStatus, forKey: .organizationStatus)
        try container.encode(contentHash, forKey: .contentHash)
        try container.encode(lastOrganizedContentHash, forKey: .lastOrganizedContentHash)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(lastOrganizedAt, forKey: .lastOrganizedAt)
        try container.encode(lastFailedAt, forKey: .lastFailedAt)
        try container.encode(lastErrorMessage, forKey: .lastErrorMessage)
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
        lastErrorMessage = nil
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

    public mutating func markPendingRetry(message: String? = nil, at date: Date = .now) {
        organizationStatus = .pending
        updatedAt = date
        lastErrorMessage = message?.nonEmptyTrimmed
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

    enum CodingKeys: String, CodingKey {
        case notes
        case folders
        case tags
        case profiles
        case jobs
        case preferences
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notes = try container.decodeIfPresent([NoteRecord].self, forKey: .notes) ?? []
        folders = try container.decodeIfPresent([FolderRecord].self, forKey: .folders) ?? []
        tags = try container.decodeIfPresent([TagRecord].self, forKey: .tags) ?? []
        profiles = try container.decodeIfPresent([AIProfileRecord].self, forKey: .profiles) ?? LibrarySnapshot.empty.profiles
        jobs = try container.decodeIfPresent([OrganizationJobRecord].self, forKey: .jobs) ?? []
        preferences = try container.decodeIfPresent(AppPreferenceRecord.self, forKey: .preferences) ?? AppPreferenceRecord()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(notes, forKey: .notes)
        try container.encode(folders, forKey: .folders)
        try container.encode(tags, forKey: .tags)
        try container.encode(profiles, forKey: .profiles)
        try container.encode(jobs, forKey: .jobs)
        try container.encode(preferences, forKey: .preferences)
    }

    public static let empty = LibrarySnapshot()

    public func hydratedForRuntime() -> LibrarySnapshot {
        var snapshot = self

        if snapshot.profiles.isEmpty {
            snapshot.profiles = LibrarySnapshot.empty.profiles
        }
        if snapshot.preferences.appcastURL.nonEmptyTrimmed == nil {
            snapshot.preferences.appcastURL = AppPreferenceRecord.defaultAppcastURL
        }
        if snapshot.preferences.releasePageURL.nonEmptyTrimmed == nil {
            snapshot.preferences.releasePageURL = AppPreferenceRecord.defaultReleasePageURL
        }

        return snapshot
    }

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

    public mutating func markDeferredRetry(
        noteID: UUID,
        nextRetryAt: Date,
        message: String? = nil,
        at date: Date = .now
    ) {
        updateNote(id: noteID) {
            $0.markPendingRetry(message: message, at: date)
        }

        if let index = jobs.firstIndex(where: { $0.noteID == noteID }) {
            jobs[index].attemptCount += 1
            jobs[index].lastErrorMessage = message
            jobs[index].nextRetryAt = nextRetryAt
            jobs[index].updatedAt = date
        } else {
            jobs.append(
                OrganizationJobRecord(
                    noteID: noteID,
                    attemptCount: 1,
                    nextRetryAt: nextRetryAt,
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

    func splitTaxonomyTerms() -> [String] {
        components(separatedBy: CharacterSet(charactersIn: ",，;；\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
