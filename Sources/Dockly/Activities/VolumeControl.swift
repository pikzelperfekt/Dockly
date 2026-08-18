import Foundation
import CoreAudio
import AudioToolbox

// Sets the default output device's volume — the target of the scroll-over-the-
// pill gesture. It does NOT report changes back: macOS draws its own volume HUD
// and a second indicator in the notch was redundant, so there is nothing here
// to observe.
//
// The one thing worth tracking is WHICH device is the default, since that moves
// under us whenever headphones go in or out.
final class VolumeControl {
    static let shared = VolumeControl()

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        deviceID = defaultOutputDevice()
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main
        ) { [weak self] _, _ in
            guard let self else { return }
            self.deviceID = self.defaultOutputDevice()
        }
    }

    /// Nudge the system output volume by a delta in percent (e.g. +4 / -4).
    func adjust(byPercent delta: Int) {
        guard deviceID != kAudioObjectUnknown else { return }
        setPercent(currentPercent() + delta)
    }

    func setPercent(_ pct: Int) {
        guard deviceID != kAudioObjectUnknown else { return }
        let clamped = max(0, min(100, pct))
        var vol = Float32(clamped) / 100
        AudioObjectSetPropertyData(deviceID, &volumeAddr, 0, nil,
                                   UInt32(MemoryLayout<Float32>.size), &vol)
        // Turning it up should also take it off mute — otherwise the gesture
        // looks like it did nothing.
        if clamped > 0 {
            var m: UInt32 = 0
            AudioObjectSetPropertyData(deviceID, &muteAddr, 0, nil,
                                       UInt32(MemoryLayout<UInt32>.size), &m)
        }
    }

    private func currentPercent() -> Int {
        guard deviceID != kAudioObjectUnknown else { return 0 }
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &volumeAddr, 0, nil, &size, &vol)
        guard status == noErr else { return 0 }
        return Int((vol * 100).rounded())
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
}
