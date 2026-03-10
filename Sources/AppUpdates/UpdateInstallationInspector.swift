import Foundation
import Security

public enum UpdateInstallationMode: Equatable, Sendable {
    case sparkle
    case downloadOnly(reason: String)

    public var supportsInAppInstallation: Bool {
        if case .sparkle = self {
            return true
        }
        return false
    }

    static func from(teamIdentifier: String?) -> UpdateInstallationMode {
        if let teamIdentifier, !teamIdentifier.isEmpty {
            return .sparkle
        }

        return .downloadOnly(
            reason: "当前 Whitecat 是未使用 Developer ID 正式签名的构建。Sparkle 无法安全安装更新；你仍可在应用内检查新版本并跳转到 GitHub 下载。"
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
