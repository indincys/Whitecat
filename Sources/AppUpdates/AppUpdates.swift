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
    case unsafeFeedURL
    case unsafeDownloadURL
    case malformedAppcast

    public var errorDescription: String? {
        switch self {
        case .invalidFeedURL:
            "更新源地址无效。"
        case .unsafeFeedURL:
            "更新源地址必须使用 HTTPS。"
        case .unsafeDownloadURL:
            "更新包地址必须使用 HTTPS。"
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

    public func check(
        currentBuildVersion: String,
        currentShortVersion: String,
        feedURLString: String
    ) async throws -> UpdateCheckResult {
        let feedURL = try UpdateURLValidator.validatedFeedURL(from: feedURLString)

        let (data, _) = try await session.data(from: feedURL)
        let items = try parser.parse(data: data)
        guard let latest = items.max(by: { $0.comparableVersion < $1.comparableVersion }) else {
            throw UpdateCheckerError.malformedAppcast
        }
        let downloadURL = try UpdateURLValidator.validatedDownloadURL(latest.url)

        let installedVersion = AppcastVersion(
            shortVersion: currentShortVersion,
            buildVersion: currentBuildVersion
        )
        if latest.comparableVersion > installedVersion {
            return .updateAvailable(
                UpdateRelease(
                    version: SemanticVersion(latest.version),
                    shortVersion: latest.shortVersion,
                    downloadURL: downloadURL,
                    edSignature: latest.edSignature,
                    notesURL: latest.notesURL,
                    publicationDate: latest.publicationDate
                )
            )
        }

        return .noUpdate
    }
}

public enum UpdateURLValidator {
    public static func validatedFeedURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            throw UpdateCheckerError.invalidFeedURL
        }
        guard isTrustedHTTPSURL(url) else {
            throw UpdateCheckerError.unsafeFeedURL
        }
        return url
    }

    public static func validatedDownloadURL(_ url: URL) throws -> URL {
        guard isTrustedHTTPSURL(url) else {
            throw UpdateCheckerError.unsafeDownloadURL
        }
        return url
    }

    public static func sanitizedBrowserURL(from rawValue: String) -> URL? {
        guard let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              isTrustedHTTPSURL(url)
        else {
            return nil
        }
        return url
    }

    private static func isTrustedHTTPSURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        guard let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            return false
        }
        return true
    }
}

private final class AppcastXMLDelegate: NSObject, XMLParserDelegate {
    private enum Node {
        case none
        case version
        case shortVersion
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
            if let version = attributeDict["sparkle:version"] ?? attributeDict["version"] {
                draftVersion = version
            }
            if let shortVersion = attributeDict["sparkle:shortVersionString"] ?? attributeDict["shortVersionString"] {
                draftShortVersion = shortVersion
            }
            draftEdSignature = attributeDict["sparkle:edSignature"] ?? attributeDict["edSignature"]
            if let urlValue = attributeDict["url"] {
                draftURL = URL(string: urlValue)
            }
        } else if elementName == "sparkle:version" || elementName == "version" {
            currentNode = .version
        } else if elementName == "sparkle:shortVersionString" || elementName == "shortVersionString" {
            currentNode = .shortVersion
        } else if elementName == "pubDate" {
            currentNode = .pubDate
        } else if elementName == "sparkle:releaseNotesLink"
            || elementName == "releaseNotesLink"
            || elementName == "sparkle:fullReleaseNotesLink"
            || elementName == "fullReleaseNotesLink"
        {
            currentNode = .releaseNotesLink
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName _: String?) {
        let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch currentNode {
        case .version where !trimmed.isEmpty:
            draftVersion = trimmed
        case .shortVersion where !trimmed.isEmpty:
            draftShortVersion = trimmed
        case .pubDate where !trimmed.isEmpty:
            draftPublicationDate = Self.dateFormatter.date(from: trimmed)
        case .releaseNotesLink where !trimmed.isEmpty:
            draftNotesURL = URL(string: trimmed)
        default:
            break
        }

        let resolvedVersion = draftVersion ?? draftShortVersion
        let resolvedShortVersion = draftShortVersion ?? draftVersion

        if elementName == "item",
           let resolvedVersion,
           let resolvedShortVersion,
           let draftURL {
            items.append(
                AppcastItem(
                    version: resolvedVersion,
                    shortVersion: resolvedShortVersion,
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

private struct AppcastVersion: Comparable, Sendable {
    let shortVersion: SemanticVersion
    let buildVersion: SemanticVersion

    init(shortVersion: String, buildVersion: String) {
        self.shortVersion = SemanticVersion(shortVersion)
        self.buildVersion = SemanticVersion(buildVersion)
    }

    static func < (lhs: AppcastVersion, rhs: AppcastVersion) -> Bool {
        if lhs.shortVersion != rhs.shortVersion {
            return lhs.shortVersion < rhs.shortVersion
        }
        return lhs.buildVersion < rhs.buildVersion
    }
}

private extension AppcastItem {
    var comparableVersion: AppcastVersion {
        AppcastVersion(shortVersion: shortVersion, buildVersion: version)
    }
}
