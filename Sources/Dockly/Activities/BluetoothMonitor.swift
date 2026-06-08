import Foundation
import IOBluetooth
import Combine

// Emits a transient event when a Bluetooth device connects or disconnects,
// using IOBluetooth's global connect notification + per-device disconnect hooks.
final class BluetoothMonitor: NSObject, ObservableObject {
    static let shared = BluetoothMonitor()

    struct Event: Equatable { let name: String; let connected: Bool; let icon: String }
    @Published private(set) var event: Event?

    private var started = false
    private var startedAt = Date()
    // Audio devices we've already announced as connected (by address), so we
    // don't re-announce ones that were already connected or churn in the bg.
    private var knownAudio = Set<String>()
    private let graceWindow: TimeInterval = 6   // ignore launch-time replays

    private override init() { super.init() }

    func start() {
        guard !started else { return }
        // IOBluetooth triggers a TCC privacy check that hard-crashes the process
        // if the app has no NSBluetoothAlwaysUsageDescription. Only activate when
        // running from a bundle that declares it (i.e. the built .app).
        guard Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") != nil
        else {
            NSLog("BluetoothMonitor: no usage description in bundle — skipping.")
            return
        }
        started = true
        startedAt = Date()
        IOBluetoothDevice.register(forConnectNotifications: self,
                                   selector: #selector(deviceConnected(_:device:)))
    }

    private func isAudio(_ device: IOBluetoothDevice) -> Bool {
        // Only headphones / speakers / AirPods — never Macs, phones, mice, etc.
        device.deviceClassMajor == kBluetoothDeviceClassMajorAudio
    }

    private func key(for device: IOBluetoothDevice) -> String {
        device.addressString ?? device.name ?? "?"
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // Always hook disconnect so our known-set stays accurate.
        device.register(forDisconnectNotification: self,
                        selector: #selector(deviceDisconnected(_:device:)))

        guard isAudio(device) else { return }          // skip Mac/phone/keyboard/etc.
        let k = key(for: device)

        // During the launch grace window, devices that fire are already
        // connected — record them silently so we don't pop "AirPods connected".
        if Date().timeIntervalSince(startedAt) < graceWindow {
            knownAudio.insert(k); return
        }
        guard !knownAudio.contains(k) else { return }  // already announced
        knownAudio.insert(k)
        emit(name: device.name ?? "Headphones", connected: true)
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        note.unregister()
        guard isAudio(device) else { return }
        let k = key(for: device)
        let wasKnown = knownAudio.remove(k) != nil
        // Only announce a disconnect for a device we actually announced/connected,
        // and never during the launch grace window.
        guard wasKnown, Date().timeIntervalSince(startedAt) >= graceWindow else { return }
        emit(name: device.name ?? "Headphones", connected: false)
    }

    private func emit(name: String, connected: Bool) {
        DispatchQueue.main.async {
            self.event = Event(name: name, connected: connected, icon: Self.icon(for: name))
        }
    }

    static func icon(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpods.max" }
        if n.contains("airpods pro") { return "airpods.pro" }
        if n.contains("airpod")      { return "airpods" }
        if n.contains("beats") || n.contains("headphone") || n.contains("studio") {
            return "headphones"
        }
        if n.contains("keyboard")    { return "keyboard" }
        if n.contains("mouse") || n.contains("magic mouse") { return "magicmouse" }
        if n.contains("trackpad")    { return "trackpad" }
        if n.contains("speaker") || n.contains("homepod") || n.contains("sound") {
            return "hifispeaker.fill"
        }
        if n.contains("mac") || n.contains("iphone") || n.contains("ipad") {
            return "laptopcomputer"
        }
        return "dot.radiowaves.left.and.right"
    }
}
