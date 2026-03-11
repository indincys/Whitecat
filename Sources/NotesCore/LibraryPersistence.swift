import Foundation

public enum StorageBackend: String, Equatable, Sendable {
    case iCloud
    case local
}

public struct StorageLocationStatus: Equatable, Sendable {
    public var backend: StorageBackend
    public var activeRootURL: URL
    public var localRootURL: URL
    public var iCloudRootURL: URL?
    public var isICloudAvailable: Bool

    public init(
        backend: StorageBackend,
        activeRootURL: URL,
        localRootURL: URL,
        iCloudRootURL: URL?,
        isICloudAvailable: Bool
    ) {
        self.backend = backend
        self.activeRootURL = activeRootURL
        self.localRootURL = localRootURL
        self.iCloudRootURL = iCloudRootURL
        self.isICloudAvailable = isICloudAvailable
    }
}

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
            if let iCloudBaseDirectoryURL {
                if !Self.sameDirectory(lhs: selected.baseDirectoryURL, rhs: iCloudBaseDirectoryURL) {
                    try persist(selected.snapshot, at: iCloudBaseDirectoryURL)
                }
                resolvedBaseDirectoryURL = iCloudBaseDirectoryURL
            } else {
                resolvedBaseDirectoryURL = selected.baseDirectoryURL
            }
            return selected.snapshot
        }

        let preferredDirectory = try preferredBaseDirectoryURL()
        resolvedBaseDirectoryURL = preferredDirectory
        return .empty
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        let status = try storageStatus()
        try persist(snapshot, at: status.activeRootURL)

        if status.backend == .iCloud {
            try persist(snapshot, at: status.localRootURL)
        }
    }

    public func storageRootURL() throws -> URL {
        if let resolvedBaseDirectoryURL {
            return resolvedBaseDirectoryURL
        }
        let preferredDirectory = try preferredBaseDirectoryURL()
        resolvedBaseDirectoryURL = preferredDirectory
        return preferredDirectory
    }

    public func storageStatus() throws -> StorageLocationStatus {
        let localRootURL = try applicationSupportBaseDirectoryURL()
        let activeRootURL = try storageRootURL()
        let iCloudRootURL = iCloudBaseDirectoryURL
        let backend: StorageBackend = if let iCloudRootURL,
                                         Self.sameDirectory(lhs: activeRootURL, rhs: iCloudRootURL) {
            .iCloud
        } else {
            .local
        }

        return StorageLocationStatus(
            backend: backend,
            activeRootURL: activeRootURL,
            localRootURL: localRootURL,
            iCloudRootURL: iCloudRootURL,
            isICloudAvailable: iCloudRootURL != nil
        )
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
                try? fileManager.startDownloadingUbiquitousItem(at: candidateURL)
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

    private func persist(_ snapshot: LibrarySnapshot, at baseDirectoryURL: URL) throws {
        let fileURL = metadataFileURL(in: baseDirectoryURL)
        let backupURL = backupFileURL(in: baseDirectoryURL)
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        try data.write(to: backupURL, options: .atomic)
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

    private static func sameDirectory(lhs: URL, rhs: URL) -> Bool {
        lhs.standardizedFileURL.path(percentEncoded: false) == rhs.standardizedFileURL.path(percentEncoded: false)
    }
}

private struct LoadedSnapshotCandidate {
    let snapshot: LibrarySnapshot
    let baseDirectoryURL: URL
    let fileURL: URL
    let modifiedAt: Date
    let isBackup: Bool
}
