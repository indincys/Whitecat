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
