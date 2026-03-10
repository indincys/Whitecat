// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Whitecat",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "WhitecatApp", targets: ["WhitecatApp"]),
        .library(name: "NotesCore", targets: ["NotesCore"]),
        .library(name: "AIOrchestrator", targets: ["AIOrchestrator"]),
        .library(name: "AppUpdates", targets: ["AppUpdates"])
    ],
    targets: [
        .binaryTarget(
            name: "Sparkle",
            path: "Vendor/Sparkle.xcframework"
        ),
        .target(
            name: "NotesCore",
            path: "Sources/NotesCore"
        ),
        .target(
            name: "AIOrchestrator",
            dependencies: ["NotesCore"],
            path: "Sources/AIOrchestrator"
        ),
        .target(
            name: "AppUpdates",
            dependencies: ["Sparkle"],
            path: "Sources/AppUpdates"
        ),
        .executableTarget(
            name: "WhitecatApp",
            dependencies: ["NotesCore", "AIOrchestrator", "AppUpdates"],
            path: "Sources/WhitecatApp"
        ),
        .testTarget(
            name: "NotesCoreTests",
            dependencies: ["NotesCore"],
            path: "Tests/NotesCoreTests"
        ),
        .testTarget(
            name: "AIOrchestratorTests",
            dependencies: ["AIOrchestrator", "NotesCore"],
            path: "Tests/AIOrchestratorTests"
        ),
        .testTarget(
            name: "AppUpdatesTests",
            dependencies: ["AppUpdates"],
            path: "Tests/AppUpdatesTests"
        )
    ]
)
