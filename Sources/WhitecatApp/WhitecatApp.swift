import AIOrchestrator
import AppUpdates
import SwiftUI

@main
struct WhitecatApp: App {
    @StateObject private var model = AppModel(
        organizer: NoteOrganizer(secretStore: KeychainSecretStore()),
        secretStore: KeychainSecretStore(),
        updateChecker: ManualUpdateChecker(),
        sparkleUpdateDriver: SparkleUpdateDriver()
    )
    @StateObject private var quickCaptureController = QuickCaptureController()

    var body: some Scene {
        WindowGroup("Whitecat") {
            ContentView()
                .environmentObject(model)
                .environmentObject(quickCaptureController)
                .preferredColorScheme(model.preferredColorScheme)
                .frame(minWidth: 1180, minHeight: 720)
                .task {
                    quickCaptureController.configure(model: model)
                }
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            CommandMenu("Capture") {
                Button("快速收集") {
                    quickCaptureController.show()
                }
                .keyboardShortcut("n", modifiers: [.command, .option])

                Button("快速收集并置顶") {
                    quickCaptureController.showPinned()
                }
                .keyboardShortcut("n", modifiers: [.command, .option, .control])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(quickCaptureController)
                .preferredColorScheme(model.preferredColorScheme)
        }
    }
}
