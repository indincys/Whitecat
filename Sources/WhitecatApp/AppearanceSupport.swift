import AppKit
import NotesCore
import SwiftUI

enum WhitecatTheme {
    static let accentColor = Color(red: 0.26, green: 0.42, blue: 0.36)

    static let workspaceBackground = Color(
        nsColor: dynamicColor(
            light: NSColor(calibratedRed: 0.962, green: 0.956, blue: 0.936, alpha: 1),
            dark: NSColor(calibratedRed: 0.118, green: 0.129, blue: 0.122, alpha: 1)
        )
    )

    static let detailGradientTop = Color(
        nsColor: dynamicColor(
            light: NSColor(calibratedRed: 0.992, green: 0.988, blue: 0.974, alpha: 1),
            dark: NSColor(calibratedRed: 0.176, green: 0.192, blue: 0.184, alpha: 1)
        )
    )

    static let detailGradientBottom = Color(
        nsColor: dynamicColor(
            light: NSColor.white,
            dark: NSColor(calibratedRed: 0.110, green: 0.122, blue: 0.118, alpha: 1)
        )
    )

    static func detailPaneBackground() -> LinearGradient {
        LinearGradient(
            colors: [detailGradientTop, detailGradientBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return dark
            }
            return light
        }
    }
}

extension AppAppearancePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }

    var displayName: String {
        switch self {
        case .system:
            "跟随系统"
        case .light:
            "浅色"
        case .dark:
            "深色"
        }
    }

    var detailDescription: String {
        switch self {
        case .system:
            "使用 macOS 原生外观，跟随系统浅色和暗黑模式自动切换。"
        case .light:
            "仅对白猫使用 macOS 原生浅色外观。"
        case .dark:
            "仅对白猫使用 macOS 原生暗黑外观。"
        }
    }
}
