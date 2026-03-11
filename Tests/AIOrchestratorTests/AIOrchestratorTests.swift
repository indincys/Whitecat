import Foundation
import Testing
@testable import AIOrchestrator
@testable import NotesCore

@Test("OpenAI 兼容请求会带上模型和正文")
func adapterBuildsExpectedRequest() throws {
    let adapter = OpenAICompatibleAdapter()
    let profile = AIProfileRecord(
        displayName: "OpenAI",
        providerKind: .openAI,
        baseURL: "https://api.example.com/v1",
        model: "gpt-test",
        requestPath: "/chat/completions",
        isActive: true
    )
    let request = try adapter.buildURLRequest(
        for: OrganizationRequest(noteBody: "整理这段正文", existingFolders: ["工作"], existingTags: ["AI"]),
        profile: profile,
        apiKey: "secret"
    )

    #expect(request.url?.absoluteString == "https://api.example.com/v1/chat/completions")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")

    let payload = try #require(request.httpBody)
    let bodyString = try #require(String(data: payload, encoding: .utf8))
    #expect(bodyString.contains("\"model\":\"gpt-test\""))
    #expect(bodyString.contains("整理这段正文"))
}

@Test("自定义提示词会进入模型请求")
func adapterIncludesCustomOrganizationPrompt() throws {
    let adapter = OpenAICompatibleAdapter()
    let profile = AIProfileRecord(
        displayName: "OpenAI",
        providerKind: .openAI,
        baseURL: "https://api.example.com/v1",
        model: "gpt-test",
        requestPath: "/chat/completions",
        organizationPrompt: "标题要更像行动摘要，标签最多 3 个。",
        isActive: true
    )
    let request = try adapter.buildURLRequest(
        for: OrganizationRequest(noteBody: "周四和设计团队讨论 Whitecat 快速记录窗口。", existingFolders: ["产品"], existingTags: ["会议"]),
        profile: profile,
        apiKey: "secret"
    )

    let payload = try #require(request.httpBody)
    let bodyString = try #require(String(data: payload, encoding: .utf8))
    #expect(bodyString.contains("标题要更像行动摘要"))
    #expect(bodyString.contains("标签最多 3 个"))
}

@Test("模型返回 fenced json 也能解析")
func adapterParsesFencedJSON() throws {
    let content = """
    ```json
    {
      "title": "开发日记",
      "category": "工作",
      "tags": ["Swift", "AI"],
      "folderName": "项目"
    }
    ```
    """
    let payload = try OpenAICompatibleAdapter.parseContentString(content)
    #expect(payload.title == "开发日记")
    #expect(payload.tags == ["Swift", "AI"])
    #expect(payload.folderName == "项目")
}

@Test("模型返回夹带说明文本时也能提取 JSON")
func adapterExtractsJSONObjectFromMixedContent() throws {
    let content = """
    下面是整理结果：
    {
      "title": "开发日记",
      "category": "工作",
      "tags": "Swift，AI；复盘",
      "folderName": "项目/Whitecat"
    }
    已结束。
    """

    let payload = try OpenAICompatibleAdapter.parseContentString(content)
    #expect(payload.title == "开发日记")
    #expect(payload.tags == ["Swift", "AI", "复盘"])
    #expect(payload.folderName == "项目 Whitecat")
}

@Test("远程模型地址必须使用 HTTPS，本机服务允许 HTTP")
func adapterRejectsUnsafeRemoteBaseURL() throws {
    let adapter = OpenAICompatibleAdapter()
    let remoteProfile = AIProfileRecord(
        displayName: "Unsafe",
        providerKind: .custom,
        baseURL: "http://example.com/v1",
        model: "test-model",
        isActive: true
    )

    #expect(throws: NoteOrganizerError.self) {
        _ = try adapter.buildURLRequest(
            for: OrganizationRequest(noteBody: "正文", existingFolders: [], existingTags: []),
            profile: remoteProfile,
            apiKey: "secret"
        )
    }

    let localProfile = AIProfileRecord(
        displayName: "Local",
        providerKind: .custom,
        baseURL: "http://localhost:11434/v1",
        model: "test-model",
        isActive: true
    )
    let request = try adapter.buildURLRequest(
        for: OrganizationRequest(noteBody: "正文", existingFolders: [], existingTags: []),
        profile: localProfile,
        apiKey: "secret"
    )
    #expect(request.url?.absoluteString == "http://localhost:11434/v1/chat/completions")
}

@Test("缺少 API key 时会失败")
func organizerFailsWithoutAPIKey() async {
    let organizer = NoteOrganizer(secretStore: InMemorySecretStore())
    let note = NoteRecord(bodyMarkdown: "这是一段正文")
    let library = LibrarySnapshot()
    let profile = try! #require(library.activeProfile())

    await #expect(throws: NoteOrganizerError.self) {
        _ = try await organizer.organize(note: note, library: library, profile: profile)
    }
}
