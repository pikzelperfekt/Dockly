import Foundation
import ServiceManagement

// Wraps SMAppService for login-item registration (macOS 13+).
// Only works when running from a proper .app bundle.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static var isAvailable: Bool {
        // SMAppService.mainApp only behaves correctly from a bundled app.
        Bundle.main.bundleIdentifier != nil &&
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("LaunchAtLogin toggle failed: \(error)")
            return false
        }
    }
}
