#if canImport(Sparkle)
import Foundation
import Sparkle

@MainActor
public final class SparkleUpdateDriver: NSObject {
    private let delegateProxy = DelegateProxy()
    private let controller: SPUStandardUpdaterController

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
#else
import Foundation

@MainActor
public final class SparkleUpdateDriver {
    public init() {}

    public func configure(feedURLString: String, automaticallyChecks _: Bool) {
        _ = feedURLString
    }

    public func checkForUpdates() {}
}
#endif
