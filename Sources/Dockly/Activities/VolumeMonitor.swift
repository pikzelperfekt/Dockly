import Foundation
import CoreAudio
import AudioToolbox
import Combine

// Watches the default output device's volume + mute via CoreAudio property
// listeners and emits a transient event the pill shows as a volume HUD.
final class VolumeMonitor: ObservableObject {
    static let shared = VolumeMonitor()

    struct Event: Equatable { let percent: Int; let muted: Bool }
    @Published private(set) var event: Event?

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var started = false
    private var lastPercent = -1
    private var lastMuted = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        deviceID = defaultOutputDevice()
        addListeners()
        // Listen for default-device changes (e.g. plugging headphones).
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main) { [weak self] _, _ in
            guard let self else { return }
            self.removeListeners()
            self.deviceID = self.defaultOutputDevice()
            self.addListeners()
        }
        // Seed baseline so the very first change is what fires the HUD.
        lastPercent = currentPercent()
        lastMuted = currentMuted()
    }

    private func defaultOutputDevice() -> AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    private var volumeAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private var muteAddr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private func addListeners() {
        guard deviceID != kAudioObjectUnknown else { return }
        AudioObjectAddPropertyListenerBlock(deviceID, &volumeAddr, DispatchQueue.main) { [weak self] _, _ in
            self?.fire()
        }
        AudioObjectAddPropertyListenerBlock(deviceID, &muteAddr, DispatchQueue.main) { [weak self] _, _ in
            self?.fire()
        }
    }

    private func removeListeners() {
        guard deviceID != kAudioObjectUnknown else { return }
        AudioObjectRemovePropertyListenerBlock(deviceID, &volumeAddr, DispatchQueue.main) { _, _ in }
        AudioObjectRemovePropertyListenerBlock(deviceID, &muteAddr, DispatchQueue.main) { _, _ in }
    }

    private func fire() {
        let pct = currentPercent()
        let muted = currentMuted()
        guard pct != lastPercent || muted != lastMuted else { return }
        lastPercent = pct; lastMuted = muted
        event = Event(percent: pct, muted: muted)
    }

    /// Nudge the system output volume by a delta in percent (e.g. +5 / -5).
    func adjust(byPercent delta: Int) {
        guard deviceID != kAudioObjectUnknown else { return }
        let cur = currentPercent()
        setPercent(max(0, min(100, cur + delta)))
    }

    func setPercent(_ pct: Int) {
        guard deviceID != kAudioObjectUnknown else { return }
        var vol = Float32(max(0, min(100, pct))) / 100
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(deviceID, &volumeAddr, 0, nil, size, &vol)
        // Unmute if the user is raising volume.
        if pct > 0 { var m: UInt32 = 0; let s = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectSetPropertyData(deviceID, &muteAddr, 0, nil, s, &m) }
        fire()
    }

    private func currentPercent() -> Int {
        guard deviceID != kAudioObjectUnknown else { return 0 }
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &volumeAddr, 0, nil, &size, &vol)
        guard status == noErr else { return lastPercent < 0 ? 0 : lastPercent }
        return Int((vol * 100).rounded())
    }

    private func currentMuted() -> Bool {
        guard deviceID != kAudioObjectUnknown else { return false }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &size, &muted)
        guard status == noErr else { return false }
        return muted != 0
    }
}
