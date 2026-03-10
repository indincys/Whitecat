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
