import CryptoKit
import Foundation

public enum UnsignedUpdateInstallerError: LocalizedError, Sendable {
    case missingPublicKey
    case missingArchiveSignature
    case invalidPublicKey
    case invalidArchiveSignature
    case invalidArchiveResponse
    case extractionFailed(String)
    case stagedAppNotFound
    case installerLaunchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingPublicKey:
            "当前应用缺少内置更新公钥，无法校验更新包。"
        case .missingArchiveSignature:
            "更新源缺少安装包签名，无法校验更新包。"
        case .invalidPublicKey:
            "当前应用内置的更新公钥无效。"
        case .invalidArchiveSignature:
            "更新包签名校验失败。"
        case .invalidArchiveResponse:
            "更新包下载失败。"
        case let .extractionFailed(message):
            "更新包解压失败：\(message)"
        case .stagedAppNotFound:
            "下载后的更新包里没有找到可安装的应用。"
        case let .installerLaunchFailed(message):
            "无法启动更新安装器：\(message)"
        }
    }
}

public final class UnsignedUpdateInstaller: @unchecked Sendable {
    private let session: URLSession
    private let fileManager: FileManager

    public init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    public func install(
        release: UpdateRelease,
        bundle: Bundle = .main,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) async throws {
        guard let publicKey = bundle.infoDictionary?["SUPublicEDKey"] as? String,
              !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw UnsignedUpdateInstallerError.missingPublicKey
        }

        guard let edSignature = release.edSignature,
              !edSignature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw UnsignedUpdateInstallerError.missingArchiveSignature
        }

        let (temporaryArchiveURL, response) = try await session.download(from: release.downloadURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ..< 300).contains(httpResponse.statusCode) {
            throw UnsignedUpdateInstallerError.invalidArchiveResponse
        }

        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("whitecat-update-\(UUID().uuidString)", isDirectory: true)
        let archiveURL = stagingRoot.appendingPathComponent("update.zip")
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        try fileManager.moveItem(at: temporaryArchiveURL, to: archiveURL)

        let archiveData = try Data(contentsOf: archiveURL)
        try SparkleEdSignatureVerifier.verify(data: archiveData, publicKey: publicKey, signature: edSignature)

        let extractedRoot = stagingRoot.appendingPathComponent("expanded", isDirectory: true)
        try fileManager.createDirectory(at: extractedRoot, withIntermediateDirectories: true)
        try Self.runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", archiveURL.path, extractedRoot.path]
        )

        guard let stagedAppURL = try Self.findAppBundle(in: extractedRoot, fileManager: fileManager) else {
            throw UnsignedUpdateInstallerError.stagedAppNotFound
        }

        let targetAppURL = bundle.bundleURL.standardizedFileURL
        let installerURL = try Self.writeInstallerScript(
            stagingRoot: stagingRoot,
            fileManager: fileManager
        )

        let installerArguments = [installerURL.path, targetAppURL.path, stagedAppURL.path, String(processID), stagingRoot.path]
        if fileManager.isWritableFile(atPath: targetAppURL.deletingLastPathComponent().path) {
            try Self.launchInstallerProcess(arguments: installerArguments)
        } else {
            try Self.launchInstallerProcessWithAuthorization(arguments: installerArguments)
        }
    }

}

enum SparkleEdSignatureVerifier {
    static func verify(data: Data, publicKey: String, signature: String) throws {
        guard let keyData = Data(base64Encoded: publicKey) else {
            throw UnsignedUpdateInstallerError.invalidPublicKey
        }
        guard let signatureData = Data(base64Encoded: signature) else {
            throw UnsignedUpdateInstallerError.invalidArchiveSignature
        }

        let verifyingKey: Curve25519.Signing.PublicKey
        do {
            verifyingKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        } catch {
            throw UnsignedUpdateInstallerError.invalidPublicKey
        }

        guard verifyingKey.isValidSignature(signatureData, for: data) else {
            throw UnsignedUpdateInstallerError.invalidArchiveSignature
        }
    }
}

extension UnsignedUpdateInstaller {
    private static func findAppBundle(in root: URL, fileManager: FileManager) throws -> URL? {
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let candidate = enumerator?.nextObject() as? URL {
            if candidate.pathExtension == "app" {
                return candidate
            }
        }

        return nil
    }

    private static func writeInstallerScript(
        stagingRoot: URL,
        fileManager: FileManager
    ) throws -> URL {
        let scriptURL = stagingRoot.appendingPathComponent("install-update.sh")
        let script = """
        #!/bin/zsh
        set -euo pipefail

        TARGET_APP="$1"
        STAGED_APP="$2"
        APP_PID="$3"
        STAGING_ROOT="$4"
        BACKUP_APP="${TARGET_APP}.backup-$$"

        cleanup() {
          rm -rf "$STAGING_ROOT"
          rm -f "$0"
        }

        trap cleanup EXIT

        for _ in {1..90}; do
          if ! kill -0 "$APP_PID" 2>/dev/null; then
            break
          fi
          sleep 1
        done

        if kill -0 "$APP_PID" 2>/dev/null; then
          echo "Timed out waiting for app to quit." >&2
          exit 1
        fi

        if [[ -e "$BACKUP_APP" ]]; then
          rm -rf "$BACKUP_APP"
        fi

        mv "$TARGET_APP" "$BACKUP_APP"
        if ditto "$STAGED_APP" "$TARGET_APP"; then
          rm -rf "$BACKUP_APP"
          open "$TARGET_APP"
        else
          rm -rf "$TARGET_APP"
          mv "$BACKUP_APP" "$TARGET_APP"
          exit 1
        fi
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private static func launchInstallerProcess(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            throw UnsignedUpdateInstallerError.installerLaunchFailed(error.localizedDescription)
        }
    }

    private static func launchInstallerProcessWithAuthorization(arguments: [String]) throws {
        let command = arguments.map(Self.singleQuotedShellArgument).joined(separator: " ")
        let appleScript = "do shell script \(appleScriptString(command)) with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]

        do {
            try process.run()
        } catch {
            throw UnsignedUpdateInstallerError.installerLaunchFailed(error.localizedDescription)
        }
    }

    private static func runProcess(executableURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            throw UnsignedUpdateInstallerError.extractionFailed(message)
        }
    }

    private static func singleQuotedShellArgument(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
