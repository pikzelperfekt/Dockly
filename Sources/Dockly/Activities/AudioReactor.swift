import Foundation
import Combine
#if !DOCKLY_VENTURA
import Accelerate
import CoreAudio
import AudioToolbox
#endif

// Taps the system audio mixdown via Core Audio process taps (macOS 14.4+) — no
// Screen Recording permission required. Publishes live overall + bass/mid/treble
// levels so the bars and border can react to the music.
//
// The DOCKLY_VENTURA build flag compiles out the tap entirely (it references the
// macOS-14.4 CATapDescription class, whose strong ObjC symbol prevents the app
// from launching on macOS 13). The Ventura build just ships an inert stub.
final class AudioReactor: ObservableObject {
    static let shared = AudioReactor()

    @Published private(set) var level: Float = 0     // overall 0…1 (smoothed)
    @Published private(set) var bass: Float = 0
    @Published private(set) var mid: Float = 0
    @Published private(set) var treble: Float = 0
    @Published private(set) var running = false
    @Published private(set) var unavailable = false

#if DOCKLY_VENTURA
    private init() {}
    func start() { unavailable = true }   // DJ mode needs macOS 14.4+
    func stop() {}
#else

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "com.josi.dockly.audiotap")

    // FFT
    private let log2n: vDSP_Length = 10
    private let n = 1024
    private var fftSetup: FFTSetup?
    private var window = [Float]()

    private init() {
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
    }

    func start() {
        guard !running else { return }
        guard #available(macOS 14.4, *) else { unavailable = true; return }
        ioQueue.async { [weak self] in self?.setupTap() }
    }

    func stop() {
        ioQueue.async { [weak self] in self?.teardownTap() }
        DispatchQueue.main.async {
            self.running = false
            self.level = 0; self.bass = 0; self.mid = 0; self.treble = 0
        }
    }

    @available(macOS 14.4, *)
    private func setupTap() {
        // 1) Global system-audio tap (exclude no processes = whole mixdown).
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(desc, &tap) == noErr else { fail(); return }
        tapID = tap

        // 2) Private aggregate device wrapping the tap.
        let aggUID = "com.josi.dockly.aggregate.\(desc.uuid.uuidString)"
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Dockly Audio Tap",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: desc.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(dict as CFDictionary, &agg) == noErr else { fail(); return }
        aggregateID = agg

        // 3) IO block — analyze the tapped audio.
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, agg, ioQueue) {
            [weak self] _, inInputData, _, _, _ in
            guard let self else { return }
            let abl = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: inInputData))
            guard let buf = abl.first, let mData = buf.mData else { return }
            let count = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { return }
            let samples = mData.bindMemory(to: Float.self, capacity: count)
            self.analyze(samples, count: count)
        }
        guard status == noErr, let proc else { fail(); return }
        ioProcID = proc
        guard AudioDeviceStart(agg, proc) == noErr else { fail(); return }
        DispatchQueue.main.async { self.running = true; self.unavailable = false }
    }

    private func fail() {
        teardownTap()
        DispatchQueue.main.async { self.running = false; self.unavailable = true }
    }

    private func teardownTap() {
        if aggregateID != kAudioObjectUnknown, let proc = ioProcID {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.4, *) { AudioHardwareDestroyProcessTap(tapID) }
            tapID = kAudioObjectUnknown
        }
    }

    private func analyze(_ samples: UnsafePointer<Float>, count: Int) {
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(count))
        let lvl = min(1, sqrt(rms) * 3.0)

        var b: Float = 0, m: Float = 0, t: Float = 0
        if count >= n, let setup = fftSetup {
            var windowed = [Float](repeating: 0, count: n)
            vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(n))
            var real = [Float](repeating: 0, count: n/2)
            var imag = [Float](repeating: 0, count: n/2)
            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    windowed.withUnsafeBufferPointer { wp in
                        wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n/2) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n/2))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    var mags = [Float](repeating: 0, count: n/2)
                    vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n/2))
                    let binHz = 44_100.0 / Double(n)
                    func band(_ lo: Double, _ hi: Double) -> Float {
                        let a = max(1, Int(lo/binHz)), z = min(n/2-1, Int(hi/binHz))
                        guard z > a else { return 0 }
                        var sum: Float = 0
                        for i in a...z { sum += mags[i] }
                        return min(1, sqrt(sum / Float(z-a+1)) * 0.06)
                    }
                    b = band(30, 250); m = band(250, 2000); t = band(2000, 8000)
                }
            }
        }

        DispatchQueue.main.async {
            func sm(_ old: Float, _ new: Float) -> Float {
                new > old ? old + (new - old) * 0.6 : old + (new - old) * 0.2
            }
            self.level  = sm(self.level, lvl)
            self.bass   = sm(self.bass, b)
            self.mid    = sm(self.mid, m)
            self.treble = sm(self.treble, t)
        }
    }

    deinit { if let f = fftSetup { vDSP_destroy_fftsetup(f) } }
#endif
}
