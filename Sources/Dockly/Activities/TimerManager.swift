import Foundation
import AppKit
import Combine

// A Dockly-native countdown timer. Drives a live activity in the pill and
// chimes + flashes when done — no dependency on the (unscriptable) Clock app.
final class TimerManager: ObservableObject {
    static let shared = TimerManager()

    enum State: Equatable { case idle, running, paused, finished }

    @Published private(set) var state: State = .idle
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0

    private var ticker: Timer?
    private var endDate: Date?

    private init() {}

    var isActive: Bool { state == .running || state == .paused || state == .finished }
    var progress: Double { total > 0 ? max(0, min(1, 1 - remaining / total)) : 0 }

    func start(_ duration: TimeInterval) {
        total = duration
        remaining = duration
        endDate = Date().addingTimeInterval(duration)
        state = .running
        startTicker()
    }

    func pause() {
        guard state == .running else { return }
        ticker?.invalidate(); ticker = nil
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        endDate = Date().addingTimeInterval(remaining)
        state = .running
        startTicker()
    }

    func togglePause() { state == .running ? pause() : resume() }

    func cancel() {
        ticker?.invalidate(); ticker = nil
        endDate = nil
        state = .idle
        remaining = 0; total = 0
    }

    func addMinute() {
        guard isActive else { return }
        total += 60
        remaining += 60
        if state == .running { endDate = Date().addingTimeInterval(remaining) }
        if state == .finished { state = .running; startTicker() }
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 { finish() }
    }

    private func finish() {
        ticker?.invalidate(); ticker = nil
        remaining = 0
        state = .finished
        NSSound(named: "Glass")?.play()
        // Auto-reset to idle a few seconds after the chime.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.state == .finished { self?.cancel() }
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }
}
