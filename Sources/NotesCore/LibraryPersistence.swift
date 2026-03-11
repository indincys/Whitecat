import Foundation

public actor LibraryPersistence {
    public struct Configuration: Sendable {
        public var appDirectoryName: String
        public var metadataFilename: String
        public var preferICloud: Bool

        public init(
            appDirectoryName: String = "Whitecat",
            metadataFilename: String = "library.json",
            preferICloud: Bool = true
        ) {
            self.appDirectoryName = appDirectoryName
            self.metadataFilename = metadataFilename
            self.preferICloud = preferICloud
        }
    }

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let configuration: Configuration
    private var resolvedBaseDirectoryURL: URL?

    public init(fileManager: FileManager = .default, configuration: Configuration = Configuration()) {
        self.fileManager = fileManager
        self.configuration = configuration

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() throws -> LibrarySnapshot {
        let candidates = try loadCandidates()
        if let selected = candidates.sorted(by: Self.candidateSort).first {
            resolvedBaseDirectoryURL = selected.baseDirectoryURL
            return selected.snapshot
        }

        let preferredDirectory = try preferredBaseDirectoryURL()
        resolvedBaseDirectoryURL = preferredDirectory
        return .empty
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        let fileURL = try metadataFileURL()
        let backupURL = try backupFileURL()
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        try data.write(to: backupURL, options: .atomic)
    }

    public func storageRootURL() throws -> URL {
        if let resolvedBaseDirectoryURL {
            return resolvedBaseDirectoryURL
        }
        let preferredDirectory = try preferredBaseDirectoryURL()
        resolvedBaseDirectoryURL = preferredDirectory
        return preferredDirectory
    }

    private func metadataFileURL() throws -> URL {
        try storageRootURL().appending(component: configuration.metadataFilename, directoryHint: .notDirectory)
    }

    private func backupFileURL() throws -> URL {
        try storageRootURL().appending(component: backupFilename, directoryHint: .notDirectory)
    }

    private var backupFilename: String {
        let metadataPath = URL(filePath: configuration.metadataFilename)
        let stem = metadataPath.deletingPathExtension().lastPathComponent
        let ext = metadataPath.pathExtension
        if ext.isEmpty {
            return "\(stem)-backup"
        }
        return "\(stem)-backup.\(ext)"
    }

    private func preferredBaseDirectoryURL() throws -> URL {
        if configuration.preferICloud, let iCloudBaseDirectoryURL {
            return iCloudBaseDirectoryURL
        }
        return try applicationSupportBaseDirectoryURL()
    }

    private var iCloudBaseDirectoryURL: URL? {
        guard let ubiquitousRoot = fileManager.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return ubiquitousRoot
            .appending(component: "Documents", directoryHint: .isDirectory)
            .appending(component: configuration.appDirectoryName, directoryHint: .isDirectory)
    }

    private func applicationSupportBaseDirectoryURL() throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport.appending(component: configuration.appDirectoryName, directoryHint: .isDirectory)
    }

    private func candidateBaseDirectoryURLs() throws -> [URL] {
        var orderedCandidates: [URL] = []
        if let resolvedBaseDirectoryURL {
            orderedCandidates.append(resolvedBaseDirectoryURL)
        }
        if let iCloudBaseDirectoryURL {
            orderedCandidates.append(iCloudBaseDirectoryURL)
        }
        orderedCandidates.append(try applicationSupportBaseDirectoryURL())

        var seen = Set<String>()
        return orderedCandidates.filter { seen.insert($0.standardizedFileURL.path(percentEncoded: false)).inserted }
    }

    private func metadataFileURL(in baseDirectoryURL: URL) -> URL {
        baseDirectoryURL.appending(component: configuration.metadataFilename, directoryHint: .notDirectory)
    }

    private func backupFileURL(in baseDirectoryURL: URL) -> URL {
        baseDirectoryURL.appending(component: backupFilename, directoryHint: .notDirectory)
    }

    private func loadCandidates() throws -> [LoadedSnapshotCandidate] {
        var loaded: [LoadedSnapshotCandidate] = []
        var sawExistingFile = false
        var lastError: Error?

        for baseDirectoryURL in try candidateBaseDirectoryURLs() {
            for candidateURL in [metadataFileURL(in: baseDirectoryURL), backupFileURL(in: baseDirectoryURL)] {
                guard fileManager.fileExists(atPath: candidateURL.path(percentEncoded: false)) else { continue }
                sawExistingFile = true

                do {
                    let data = try Data(contentsOf: candidateURL)
                    let snapshot = try decoder.decode(LibrarySnapshot.self, from: data)
                    loaded.append(
                        LoadedSnapshotCandidate(
                            snapshot: snapshot,
                            baseDirectoryURL: baseDirectoryURL,
                            fileURL: candidateURL,
                            modifiedAt: modificationDate(for: candidateURL),
                            isBackup: candidateURL.lastPathComponent == backupFileURL(in: baseDirectoryURL).lastPathComponent
                        )
                    )
                } catch {
                    lastError = error
                }
            }
        }

        if loaded.isEmpty, sawExistingFile, let lastError {
            throw lastError
        }

        return loaded
    }

    private func modificationDate(for fileURL: URL) -> Date {
        let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path(percentEncoded: false))
        return attributes?[.modificationDate] as? Date ?? .distantPast
    }

    private static func candidateSort(lhs: LoadedSnapshotCandidate, rhs: LoadedSnapshotCandidate) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt {
            return lhs.modifiedAt > rhs.modifiedAt
        }
        if lhs.isBackup != rhs.isBackup {
            return !lhs.isBackup
        }
        return lhs.fileURL.path(percentEncoded: false) < rhs.fileURL.path(percentEncoded: false)
    }
}

private struct LoadedSnapshotCandidate {
    let snapshot: LibrarySnapshot
    let baseDirectoryURL: URL
    let fileURL: URL
    let modifiedAt: Date
    let isBackup: Bool
}
