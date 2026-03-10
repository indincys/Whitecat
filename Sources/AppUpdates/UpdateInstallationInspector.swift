import Foundation
import Security

public enum UpdateInstallationMode: Equatable, Sendable {
    case sparkle
    case selfManaged(reason: String)
    case downloadOnly(reason: String)

    public var supportsInAppInstallation: Bool {
        switch self {
        case .sparkle, .selfManaged:
            true
        case .downloadOnly:
            false
        }
    }

    public var usesSparkle: Bool {
        if case .sparkle = self {
            return true
        }
        return false
    }

    static func from(teamIdentifier: String?) -> UpdateInstallationMode {
        if let teamIdentifier, !teamIdentifier.isEmpty {
            return .sparkle
        }

        return .selfManaged(
            reason: "当前 Whitecat 没有使用 Developer ID 正式签名。更新将改用内置安装器下载、校验并替换应用，不再走 Sparkle 的签名链。"
        )
    }
}

public enum UpdateInstallationInspector {
    public static func current(bundle: Bundle = .main) -> UpdateInstallationMode {
        guard let bundleURL = bundle.bundleURL as CFURL? else {
            return .downloadOnly(reason: "无法读取当前应用包路径，已关闭应用内自动安装更新。")
        }

        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL, SecCSFlags(), &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return .downloadOnly(reason: "无法读取当前应用的代码签名信息，已关闭应用内自动安装更新。")
        }

        var signingInfo: CFDictionary?
        let copyStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInfo
        )
        guard copyStatus == errSecSuccess,
              let info = signingInfo as? [String: Any]
        else {
            return .downloadOnly(reason: "无法读取当前应用的签名详情，已关闭应用内自动安装更新。")
        }

        let teamIdentifier = info[kSecCodeInfoTeamIdentifier as String] as? String
        return UpdateInstallationMode.from(teamIdentifier: teamIdentifier)
    }
}
