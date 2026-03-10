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
        let fileURL = try metadataFileURL()
        guard fileManager.fileExists(atPath: fileURL.path()) else {
            return .empty
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(LibrarySnapshot.self, from: data)
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        let fileURL = try metadataFileURL()
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    public func storageRootURL() throws -> URL {
        try baseDirectoryURL()
    }

    private func metadataFileURL() throws -> URL {
        try baseDirectoryURL().appending(component: configuration.metadataFilename, directoryHint: .notDirectory)
    }

    private func baseDirectoryURL() throws -> URL {
        if configuration.preferICloud,
           let ubiquitousRoot = fileManager.url(forUbiquityContainerIdentifier: nil) {
            return ubiquitousRoot
                .appending(component: "Documents", directoryHint: .isDirectory)
                .appending(component: configuration.appDirectoryName, directoryHint: .isDirectory)
        }

        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport.appending(component: configuration.appDirectoryName, directoryHint: .isDirectory)
    }
}
