import Foundation
import Testing
@testable import AppUpdates

@Test("Sparkle appcast 可以解析最新版本")
func appcastParserReadsLatestItem() throws {
    let xml = """
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <item>
          <pubDate>Tue, 10 Mar 2026 12:00:00 +0000</pubDate>
          <sparkle:releaseNotesLink>https://example.com/release-notes</sparkle:releaseNotesLink>
          <enclosure url="https://example.com/Whitecat-1.0.0.zip" sparkle:version="100" sparkle:shortVersionString="1.0.0" />
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
}

@Test("语义版本比较按分段大小")
func semanticVersionComparisonWorks() {
    #expect(SemanticVersion("1.0.10") > SemanticVersion("1.0.2"))
    #expect(SemanticVersion("2.0") > SemanticVersion("1.9.9"))
}
