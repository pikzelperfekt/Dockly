import Foundation
import Sparkle

// Thin wrapper around Sparkle's standard updater. Auto-checks in the background
// and powers the "Check for Updates…" menu item. The feed URL + public key live
// in Info.plist (SUFeedURL / SUPublicEDKey).
final class Updater {
    static let shared = Updater()
    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
