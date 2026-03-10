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

    var body: some Scene {
        WindowGroup("Whitecat") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1180, minHeight: 720)
        }
        .defaultSize(width: 1320, height: 820)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
