import Foundation
import Testing
@testable import AppUpdates

@Test("Sparkle appcast 可以解析 enclosure 属性版本")
func appcastParserReadsAttributeBasedItem() throws {
    let xml = """
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <item>
          <pubDate>Tue, 10 Mar 2026 12:00:00 +0000</pubDate>
          <sparkle:releaseNotesLink>https://example.com/release-notes</sparkle:releaseNotesLink>
          <enclosure url="https://example.com/Whitecat-1.0.0.zip" sparkle:version="100" sparkle:shortVersionString="1.0.0" sparkle:edSignature="abc123" />
        </item>
      </channel>
    </rss>
    """

    let parser = AppcastParser()
    let items = try parser.parse(data: Data(xml.utf8))

    #expect(items.count == 1)
    #expect(items[0].version == "100")
    #expect(items[0].shortVersion == "1.0.0")
    #expect(items[0].url.absoluteString == "https://example.com/Whitecat-1.0.0.zip")
    #expect(items[0].edSignature == "abc123")
}

@Test("Sparkle appcast 可以解析 generate_appcast 的标准输出")
func appcastParserReadsElementBasedItem() throws {
    let xml = """
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <item>
          <title>0.1.4</title>
          <pubDate>Wed, 11 Mar 2026 03:56:29 +0800</pubDate>
          <sparkle:version>5</sparkle:version>
          <sparkle:shortVersionString>0.1.4</sparkle:shortVersionString>
          <sparkle:fullReleaseNotesLink>https://github.com/example/Whitecat/releases/tag/v0.1.4</sparkle:fullReleaseNotesLink>
          <enclosure url="https://github.com/example/Whitecat/releases/download/v0.1.4/Whitecat-0.1.4.zip" sparkle:edSignature="abc123" />
        </item>
      </channel>
    </rss>
    """

    let parser = AppcastParser()
    let items = try parser.parse(data: Data(xml.utf8))

    #expect(items.count == 1)
    #expect(items[0].version == "5")
    #expect(items[0].shortVersion == "0.1.4")
    #expect(items[0].notesURL?.absoluteString == "https://github.com/example/Whitecat/releases/tag/v0.1.4")
    #expect(items[0].url.absoluteString == "https://github.com/example/Whitecat/releases/download/v0.1.4/Whitecat-0.1.4.zip")
}

@Test("语义版本比较按分段大小")
func semanticVersionComparisonWorks() {
    #expect(SemanticVersion("1.0.10") > SemanticVersion("1.0.2"))
    #expect(SemanticVersion("2.0") > SemanticVersion("1.9.9"))
}

@Test("手动检查更新时优先比较 short version，再比较 build version")
func manualUpdateCheckerPrefersShortVersionThenBuildVersion() async throws {
    let xml = """
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <item>
          <sparkle:version>9</sparkle:version>
          <sparkle:shortVersionString>0.1.3</sparkle:shortVersionString>
          <enclosure url="https://example.com/Whitecat-0.1.3.zip" sparkle:edSignature="old" />
        </item>
        <item>
          <sparkle:version>5</sparkle:version>
          <sparkle:shortVersionString>0.1.4</sparkle:shortVersionString>
          <enclosure url="https://example.com/Whitecat-0.1.4.zip" sparkle:edSignature="new" />
        </item>
      </channel>
    </rss>
    """

    MockURLProtocol.responseData = Data(xml.utf8)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let checker = ManualUpdateChecker(session: session)

    let result = try await checker.check(
        currentBuildVersion: "5",
        currentShortVersion: "0.1.4",
        feedURLString: "https://example.com/appcast.xml"
    )

    #expect(result == .noUpdate)
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseData = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.absoluteString == "https://example.com/appcast.xml"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com/appcast.xml")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
