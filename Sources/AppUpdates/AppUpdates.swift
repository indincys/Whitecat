import Foundation

public struct UpdateRelease: Equatable, Hashable, Sendable {
    public var version: SemanticVersion
    public var shortVersion: String
    public var downloadURL: URL
    public var edSignature: String?
    public var notesURL: URL?
    public var publicationDate: Date?

    public init(
        version: SemanticVersion,
        shortVersion: String,
        downloadURL: URL,
        edSignature: String? = nil,
        notesURL: URL? = nil,
        publicationDate: Date? = nil
    ) {
        self.version = version
        self.shortVersion = shortVersion
        self.downloadURL = downloadURL
        self.edSignature = edSignature
        self.notesURL = notesURL
        self.publicationDate = publicationDate
    }
}

public enum UpdateCheckResult: Equatable, Sendable {
    case noUpdate
    case updateAvailable(UpdateRelease)
}

public enum UpdateCheckerError: LocalizedError, Sendable {
    case invalidFeedURL
    case malformedAppcast

    public var errorDescription: String? {
        switch self {
        case .invalidFeedURL:
            "更新源地址无效。"
        case .malformedAppcast:
            "无法解析更新源。"
        }
    }
}

public struct SemanticVersion: Comparable, Hashable, Codable, Sendable {
    public var components: [Int]

    public init(_ rawValue: String) {
        self.components = rawValue
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        for index in 0 ..< maxCount {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

public struct AppcastItem: Equatable, Sendable {
    public var version: String
    public var shortVersion: String
    public var url: URL
    public var edSignature: String?
    public var notesURL: URL?
    public var publicationDate: Date?

    public init(
        version: String,
        shortVersion: String,
        url: URL,
        edSignature: String? = nil,
        notesURL: URL? = nil,
        publicationDate: Date? = nil
    ) {
        self.version = version
        self.shortVersion = shortVersion
        self.url = url
        self.edSignature = edSignature
        self.notesURL = notesURL
        self.publicationDate = publicationDate
    }
}

public struct AppcastParser: Sendable {
    public init() {}

    public func parse(data: Data) throws -> [AppcastItem] {
        let delegate = AppcastXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw UpdateCheckerError.malformedAppcast
        }
        return delegate.items
    }
}

public struct ManualUpdateChecker: Sendable {
    private let session: URLSession
    private let parser: AppcastParser

    public init(session: URLSession = .shared, parser: AppcastParser = AppcastParser()) {
        self.session = session
        self.parser = parser
    }

    public func check(currentVersion: String, feedURLString: String) async throws -> UpdateCheckResult {
        guard let feedURL = URL(string: feedURLString), !feedURLString.isEmpty else {
            throw UpdateCheckerError.invalidFeedURL
        }

        let (data, _) = try await session.data(from: feedURL)
        let items = try parser.parse(data: data)
        guard let latest = items.max(by: { SemanticVersion($0.version) < SemanticVersion($1.version) }) else {
            throw UpdateCheckerError.malformedAppcast
        }

        let installedVersion = SemanticVersion(currentVersion)
        let latestVersion = SemanticVersion(latest.version)
        if latestVersion > installedVersion {
            return .updateAvailable(
                UpdateRelease(
                    version: latestVersion,
                    shortVersion: latest.shortVersion,
                    downloadURL: latest.url,
                    edSignature: latest.edSignature,
                    notesURL: latest.notesURL,
                    publicationDate: latest.publicationDate
                )
            )
        }

        return .noUpdate
    }
}

private final class AppcastXMLDelegate: NSObject, XMLParserDelegate {
    private enum Node {
        case none
        case pubDate
        case releaseNotesLink
    }

    private var currentNode: Node = .none
    private var textBuffer: String = ""
    private var draftVersion: String?
    private var draftShortVersion: String?
    private var draftURL: URL?
    private var draftEdSignature: String?
    private var draftNotesURL: URL?
    private var draftPublicationDate: Date?

    fileprivate private(set) var items: [AppcastItem] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
        currentNode = .none
        textBuffer = ""

        if elementName == "item" {
            draftVersion = nil
            draftShortVersion = nil
            draftURL = nil
            draftEdSignature = nil
            draftNotesURL = nil
            draftPublicationDate = nil
        } else if elementName == "enclosure" {
            draftVersion = attributeDict["sparkle:version"] ?? attributeDict["version"]
            draftShortVersion = attributeDict["sparkle:shortVersionString"] ?? attributeDict["shortVersionString"]
            draftEdSignature = attributeDict["sparkle:edSignature"] ?? attributeDict["edSignature"]
            if let urlValue = attributeDict["url"] {
                draftURL = URL(string: urlValue)
            }
        } else if elementName == "pubDate" {
            currentNode = .pubDate
        } else if elementName == "sparkle:releaseNotesLink" || elementName == "releaseNotesLink" {
            currentNode = .releaseNotesLink
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName _: String?) {
        let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch currentNode {
        case .pubDate where !trimmed.isEmpty:
            draftPublicationDate = Self.dateFormatter.date(from: trimmed)
        case .releaseNotesLink where !trimmed.isEmpty:
            draftNotesURL = URL(string: trimmed)
        default:
            break
        }

        if elementName == "item",
           let draftVersion,
           let draftShortVersion,
           let draftURL {
            items.append(
                AppcastItem(
                    version: draftVersion,
                    shortVersion: draftShortVersion,
                    url: draftURL,
                    edSignature: draftEdSignature,
                    notesURL: draftNotesURL,
                    publicationDate: draftPublicationDate
                )
            )
        }

        currentNode = .none
        textBuffer = ""
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "E, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()
}
