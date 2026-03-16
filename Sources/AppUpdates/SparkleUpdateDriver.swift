#if canImport(Sparkle)
import Combine
import Foundation
import Sparkle
import SwiftUI

@MainActor
public final class SparkleUpdateDriver: NSObject {
    private let delegateProxy = DelegateProxy()
    let controller: SPUStandardUpdaterController

    public override init() {
        controller = SPUStandardUpdaterController(updaterDelegate: delegateProxy, userDriverDelegate: nil)
        super.init()
    }

    public func configure(feedURLString: String, automaticallyChecks: Bool) {
        delegateProxy.feedURLString = feedURLString
        controller.updater.automaticallyChecksForUpdates = automaticallyChecks
    }

    public func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    private final class DelegateProxy: NSObject, SPUUpdaterDelegate {
        var feedURLString: String = ""

        func feedURLString(for updater: SPUUpdater) -> String? {
            feedURLString.isEmpty ? nil : feedURLString
        }
    }
}

public final class CheckForUpdatesViewModel: ObservableObject {
    @Published public var canCheckForUpdates = false

    public init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

public struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    public init(driver: SparkleUpdateDriver) {
        let updater = driver.controller.updater
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    public var body: some View {
        Button("检查更新…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}
#else
import Foundation
import SwiftUI

@MainActor
public final class SparkleUpdateDriver {
    public init() {}

    public func configure(feedURLString: String, automaticallyChecks _: Bool) {
        _ = feedURLString
    }

    public func checkForUpdates() {}
}

public struct CheckForUpdatesView: View {
    public init(driver: SparkleUpdateDriver) {}

    public var body: some View {
        Button("检查更新…") {}
            .disabled(true)
    }
}
#endif
