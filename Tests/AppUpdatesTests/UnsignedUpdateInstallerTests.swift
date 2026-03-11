import CryptoKit
import Foundation
import Testing
@testable import AppUpdates

@Test("EdDSA 校验器接受正确签名")
func sparkleSignatureVerifierAcceptsValidSignature() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let payload = Data("whitecat update archive".utf8)
    let signature = try privateKey.signature(for: payload)

    try SparkleEdSignatureVerifier.verify(
        data: payload,
        publicKey: privateKey.publicKey.rawRepresentation.base64EncodedString(),
        signature: signature.base64EncodedString()
    )
}

@Test("EdDSA 校验器拒绝错误签名")
func sparkleSignatureVerifierRejectsInvalidSignature() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let payload = Data("whitecat update archive".utf8)

    #expect(throws: UnsignedUpdateInstallerError.self) {
        try SparkleEdSignatureVerifier.verify(
            data: payload,
            publicKey: privateKey.publicKey.rawRepresentation.base64EncodedString(),
            signature: Data(repeating: 1, count: 64).base64EncodedString()
        )
    }
}

@Test("更新安装器会校验暂存应用的 bundle identifier")
func unsignedInstallerValidatesBundleIdentifier() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("whitecat-installer-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }

    let currentAppURL = root.appendingPathComponent("Whitecat.app", isDirectory: true)
    let stagedAppURL = root.appendingPathComponent("Whitecat-Staged.app", isDirectory: true)
    let mismatchedAppURL = root.appendingPathComponent("Whitecat-Other.app", isDirectory: true)
    try makeBundle(at: currentAppURL, identifier: "com.indincys.whitecat")
    try makeBundle(at: stagedAppURL, identifier: "com.indincys.whitecat")

    try UnsignedUpdateInstaller.validateStagedAppBundle(
        at: stagedAppURL,
        matches: try #require(Bundle(url: currentAppURL))
    )

    try makeBundle(at: mismatchedAppURL, identifier: "com.indincys.other")
    #expect(throws: UnsignedUpdateInstallerError.self) {
        try UnsignedUpdateInstaller.validateStagedAppBundle(
            at: mismatchedAppURL,
            matches: try #require(Bundle(url: currentAppURL))
        )
    }
}

private func makeBundle(at bundleURL: URL, identifier: String) throws {
    try? FileManager.default.removeItem(at: bundleURL)
    let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
    let plistURL = contentsURL.appendingPathComponent("Info.plist")
    try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

    let info: [String: Any] = [
        "CFBundleIdentifier": identifier,
        "CFBundleName": "Whitecat"
    ]
    let plistData = try PropertyListSerialization.data(
        fromPropertyList: info,
        format: .xml,
        options: 0
    )
    try plistData.write(to: plistURL, options: .atomic)
}
