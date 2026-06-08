import Foundation
import IOKit.ps
import Combine

struct BatteryState: Equatable {
    let percent: Int
    let isCharging: Bool
    let isPluggedIn: Bool
    let timeToFull: Int?     // minutes, if known
}

// Polls IOKit power sources and emits transient "charging started / unplugged /
// low battery" events that ActivityManager surfaces as a Dynamic-Island pill.
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    @Published private(set) var state: BatteryState?
    /// Fires a short-lived event the UI can show, then auto-clears.
    @Published private(set) var event: BatteryEvent?

    enum BatteryEvent: Equatable {
        case pluggedIn(Int)
        case unplugged(Int)
        case low(Int)
        case full
    }

    private var timer: Timer?
    private var runLoopSource: CFRunLoopSource?
    private var lastCharging: Bool?
    private var lastLowFired = false

    private init() {}

    func start() {
        poll()
        // Instant: IOKit fires this the moment a power source changes (plug/unplug).
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { me.poll() }
        }, ctx)?.takeRetainedValue() {
            runLoopSource = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        // Slow backup poll for the gradual % drift + low-battery checks.
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        guard let snapshot = readPowerSource() else { return }
        let prev = state
        state = snapshot

        // Charging transitions
        if let was = lastCharging, was != snapshot.isPluggedIn {
            fire(snapshot.isPluggedIn ? .pluggedIn(snapshot.percent)
                                      : .unplugged(snapshot.percent))
        }
        lastCharging = snapshot.isPluggedIn

        // Full
        if snapshot.isPluggedIn && snapshot.percent >= 100 && prev?.percent ?? 0 < 100 {
            fire(.full)
        }

        // Low battery (once until re-charged)
        if !snapshot.isPluggedIn && snapshot.percent <= 20 && !lastLowFired {
            lastLowFired = true
            fire(.low(snapshot.percent))
        }
        if snapshot.percent > 25 || snapshot.isPluggedIn { lastLowFired = false }
    }

    private func fire(_ e: BatteryEvent) {
        event = e
        // Auto-clear after a few seconds so it's a transient activity.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.event == e { self?.event = nil }
        }
    }

    private func readPowerSource() -> BatteryState? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any]
            else { continue }
            let cur = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let pct = max > 0 ? Int(round(Double(cur) / Double(max) * 100)) : cur
            let state = desc[kIOPSPowerSourceStateKey] as? String
            let plugged = (state == kIOPSACPowerValue)
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let ttf = desc[kIOPSTimeToFullChargeKey] as? Int
            return BatteryState(percent: pct,
                                isCharging: charging,
                                isPluggedIn: plugged,
                                timeToFull: (ttf ?? -1) > 0 ? ttf : nil)
        }
        return nil
    }
}
