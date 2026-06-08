import Foundation
import Combine

// Best-effort macOS Focus / Do Not Disturb detection. Apple exposes no public
// API for this, so we read the assertions DB and watch it for changes. If the
// file layout differs on this OS version, we simply never fire (no crash).
final class FocusMonitor: ObservableObject {
    static let shared = FocusMonitor()

    struct Event: Equatable { let on: Bool; let name: String }
    @Published private(set) var event: Event?

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var lastOn: Bool?
    private var started = false

    private var dbURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
    }

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        evaluate()
        watch()
    }

    private func watch() {
        let path = dbURL.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .main)
        src.setEventHandler { [weak self] in
            self?.evaluate()
            // On delete/rename the descriptor is stale — rebind shortly after.
            if let self, self.source?.isCancelled == false {
                let flags = self.source?.data ?? []
                if flags.contains(.delete) || flags.contains(.rename) {
                    self.rebind()
                }
            }
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd) }
            self?.fd = -1
        }
        source = src
        src.resume()
    }

    private func rebind() {
        source?.cancel(); source = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.watch() }
    }

    private func evaluate() {
        let on = currentlyFocused()
        guard on != lastOn else { return }
        let wasNil = lastOn == nil
        lastOn = on
        // Don't fire an event for the very first read (just sync baseline).
        guard !wasNil else { return }
        event = Event(on: on, name: on ? "Focus On" : "Focus Off")
    }

    private func currentlyFocused() -> Bool {
        guard let data = try? Data(contentsOf: dbURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        // The assertions array is non-empty while a Focus is active.
        if let assertions = json["data"] as? [[String: Any]] {
            for entry in assertions {
                if let records = entry["storeAssertionRecords"] as? [[String: Any]], !records.isEmpty {
                    return true
                }
            }
        }
        return false
    }
}
