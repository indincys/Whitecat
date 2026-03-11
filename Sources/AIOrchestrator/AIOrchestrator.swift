import Foundation
import NotesCore
import Security

public struct OrganizationRequest: Equatable, Sendable {
    public var noteBody: String
    public var existingFolders: [String]
    public var existingTags: [String]

    public init(noteBody: String, existingFolders: [String], existingTags: [String]) {
        self.noteBody = noteBody
        self.existingFolders = existingFolders
        self.existingTags = existingTags
    }
}

public protocol SecretStoring: Sendable {
    func storeSecret(_ secret: String, account: String) throws
    func secret(account: String) throws -> String?
    func deleteSecret(account: String) throws
}

public protocol LLMProviderAdapter: Sendable {
    func buildURLRequest(
        for request: OrganizationRequest,
        profile: AIProfileRecord,
        apiKey: String
    ) throws -> URLRequest

    func parseResponse(data: Data, response: URLResponse) throws -> OrganizationPayload
}

public enum NoteOrganizerError: LocalizedError, Sendable {
    case missingAPIKey
    case invalidBaseURL
    case invalidResponse
    case providerFailure(String)
    case malformedPayload

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "当前激活模型缺少 API Key。"
        case .invalidBaseURL:
            "模型 Base URL 无效。"
        case .invalidResponse:
            "模型返回结果无法解析。"
        case let .providerFailure(message):
            message
        case .malformedPayload:
            "模型没有返回符合要求的标题、分类、标签和文件夹。"
        }
    }
}

public struct KeychainSecretStore: SecretStoring {
    private let service: String

    public init(service: String = "com.indincys.whitecat") {
        self.service = service
    }

    public func storeSecret(_ secret: String, account: String) throws {
        let encoded = Data(secret.utf8)
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as CFDictionary

        SecItemDelete(query)

        let createQuery = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: encoded
        ] as CFDictionary

        let status = SecItemAdd(createQuery, nil)
        guard status == errSecSuccess else {
            throw NoteOrganizerError.providerFailure("无法写入 Keychain（\(status)）。")
        }
    }

    public func secret(account: String) throws -> String? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: kCFBooleanTrue as Any,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = item as? Data,
              let secret = String(data: data, encoding: .utf8)
        else {
            throw NoteOrganizerError.providerFailure("无法读取 Keychain。")
        }
        return secret
    }

    public func deleteSecret(account: String) throws {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as CFDictionary
        let status = SecItemDelete(query)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NoteOrganizerError.providerFailure("无法删除 Keychain 凭据。")
        }
    }
}

public struct InMemorySecretStore: SecretStoring {
    private let storage: LockedBox<[String: String]>

    public init(initialSecrets: [String: String] = [:]) {
        storage = LockedBox(initialSecrets)
    }

    public func storeSecret(_ secret: String, account: String) throws {
        storage.withLock { $0[account] = secret }
    }

    public func secret(account: String) throws -> String? {
        storage.withLock { $0[account] }
    }

    public func deleteSecret(account: String) throws {
        let _ = storage.withLock { $0.removeValue(forKey: account) }
    }
}

public struct OpenAICompatibleAdapter: LLMProviderAdapter {
    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            var role: String
            var content: String
        }

        var model: String
        var temperature: Double
        var responseFormat: ResponseFormat?
        var messages: [Message]

        enum CodingKeys: String, CodingKey {
            case model
            case temperature
            case responseFormat = "response_format"
            case messages
        }
    }

    private struct ResponseFormat: Encodable {
        var type: String
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                var content: String?
            }

            var message: Message
        }

        var choices: [Choice]
        var error: ProviderError?
    }

    private struct ProviderError: Decodable {
        var message: String
    }

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(encoder: JSONEncoder = JSONEncoder(), decoder: JSONDecoder = JSONDecoder()) {
        self.encoder = encoder
        self.decoder = decoder
    }

    public func buildURLRequest(
        for request: OrganizationRequest,
        profile: AIProfileRecord,
        apiKey: String
    ) throws -> URLRequest {
        let baseURL = try ProviderEndpointValidator.validatedBaseURL(from: profile.trimmedBaseURL)

        var endpoint = profile.trimmedRequestPath
        if !endpoint.hasPrefix("/") {
            endpoint = "/" + endpoint
        }

        let url = baseURL.appending(path: endpoint)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 45
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let systemPrompt = """
        你是 Whitecat 笔记整理模型。你必须只输出 JSON，不要解释，不要 Markdown，不要多余文本。
        输出字段必须是:
        {
          "title": "20字以内的中文标题",
          "category": "一个主分类",
          "tags": ["不超过5个标签"],
          "folderName": "一个单层文件夹名"
        }
        基础规则:
        1. 标题简洁，能概括正文。
        2. category 是单个主分类。
        3. tags 只保留高价值标签。
        4. folderName 必须是单层目录名，不允许斜杠。
        5. 如果已有文件夹适合，优先复用已有文件夹。
        6. 所有输出使用中文，除非正文内容明显要求保留英文名词。

        用户自定义整理要求:
        \(profile.trimmedOrganizationPrompt)
        """

        let existingFolders = request.existingFolders
            .deduplicatedTaxonomyNames()
            .prefix(40)
            .joined(separator: "、")
        let existingTags = request.existingTags
            .deduplicatedTaxonomyNames()
            .prefix(40)
            .joined(separator: "、")

        let prompt = """
        请根据这条笔记生成结构化整理结果。
        已有文件夹: \(existingFolders)
        已有标签: \(existingTags)

        正文:
        \(request.noteBody)
        """

        let chatRequest = ChatRequest(
            model: profile.model,
            temperature: 0.2,
            responseFormat: ResponseFormat(type: "json_object"),
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: prompt)
            ]
        )
        urlRequest.httpBody = try encoder.encode(chatRequest)
        return urlRequest
    }

    public func parseResponse(data: Data, response: URLResponse) throws -> OrganizationPayload {
        if let httpResponse = response as? HTTPURLResponse, !(200 ..< 300).contains(httpResponse.statusCode) {
            if let chatResponse = try? decoder.decode(ChatResponse.self, from: data),
               let providerError = chatResponse.error?.message {
                throw NoteOrganizerError.providerFailure(providerError)
            }
            throw NoteOrganizerError.providerFailure("模型服务返回状态码 \(httpResponse.statusCode)。")
        }

        let responsePayload = try decoder.decode(ChatResponse.self, from: data)
        guard let content = responsePayload.choices.first?.message.content else {
            throw NoteOrganizerError.invalidResponse
        }
        return try Self.parseContentString(content)
    }

    public static func parseContentString(_ content: String) throws -> OrganizationPayload {
        let raw = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString = extractJSON(from: raw)

        guard let data = jsonString.data(using: .utf8) else {
            throw NoteOrganizerError.invalidResponse
        }

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let object else {
            throw NoteOrganizerError.invalidResponse
        }

        let tags = normalizedTags(from: object["tags"])
        let payload = OrganizationPayload(
            title: object["title"] as? String ?? "",
            category: object["category"] as? String ?? "",
            tags: Array(tags.prefix(5)),
            folderName: ((object["folderName"] as? String) ?? "").replacingOccurrences(of: "/", with: " ")
        )

        guard payload.title.nonEmptyTrimmed != nil,
              payload.category.nonEmptyTrimmed != nil,
              payload.folderName.nonEmptyTrimmed != nil
        else {
            throw NoteOrganizerError.malformedPayload
        }

        return payload
    }

    public static func extractJSON(from content: String) -> String {
        if let extracted = firstJSONObject(in: content) {
            return extracted
        }
        return content
    }

    private static func normalizedTags(from value: Any?) -> [String] {
        if let tags = value as? [String] {
            return tags.deduplicatedTaxonomyNames()
        }
        if let tags = value as? [Any] {
            let strings = tags.compactMap { tag -> String? in
                switch tag {
                case let text as String:
                    return text
                case let number as NSNumber:
                    return number.stringValue
                default:
                    return nil
                }
            }
            return strings.deduplicatedTaxonomyNames()
        }
        if let tagString = value as? String {
            return tagString.splitTaxonomyTerms().deduplicatedTaxonomyNames()
        }
        return []
    }

    private static func firstJSONObject(in content: String) -> String? {
        var objectStart: String.Index?
        var nestingDepth = 0
        var isInsideString = false
        var isEscaping = false

        for index in content.indices {
            let character = content[index]

            if isEscaping {
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = isInsideString
                continue
            }

            if character == "\"" {
                isInsideString.toggle()
                continue
            }

            guard !isInsideString else { continue }

            if character == "{" {
                if nestingDepth == 0 {
                    objectStart = index
                }
                nestingDepth += 1
                continue
            }

            if character == "}" {
                guard nestingDepth > 0 else { continue }
                nestingDepth -= 1
                if nestingDepth == 0, let objectStart {
                    return String(content[objectStart ... index])
                }
            }
        }

        return nil
    }
}

public actor NoteOrganizer {
    private let secretStore: SecretStoring
    private let adapter: LLMProviderAdapter
    private let session: URLSession

    public init(
        secretStore: SecretStoring,
        adapter: LLMProviderAdapter = OpenAICompatibleAdapter(),
        session: URLSession = .shared
    ) {
        self.secretStore = secretStore
        self.adapter = adapter
        self.session = session
    }

    public func organize(note: NoteRecord, library: LibrarySnapshot, profile: AIProfileRecord) async throws -> OrganizationPayload {
        guard let apiKey = try secretStore.secret(account: profile.keychainAccount), !apiKey.isEmpty else {
            throw NoteOrganizerError.missingAPIKey
        }

        let request = OrganizationRequest(
            noteBody: note.bodyMarkdown,
            existingFolders: library.folders.map(\.name),
            existingTags: library.tags.map(\.name)
        )
        let urlRequest = try adapter.buildURLRequest(for: request, profile: profile, apiKey: apiKey)
        let (data, response) = try await session.data(for: urlRequest)
        return try adapter.parseResponse(data: data, response: response)
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

private enum ProviderEndpointValidator {
    static func validatedBaseURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            throw NoteOrganizerError.invalidBaseURL
        }

        switch scheme {
        case "https":
            return url
        case "http" where isLoopbackHost(url.host):
            return url
        default:
            throw NoteOrganizerError.invalidBaseURL
        }
    }

    private static func isLoopbackHost(_ host: String?) -> Bool {
        guard let normalizedHost = host?.lowercased() else { return false }
        return normalizedHost == "localhost"
            || normalizedHost == "127.0.0.1"
            || normalizedHost == "::1"
    }
}
