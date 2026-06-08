import Foundation
import Combine

// Lists and runs macOS Shortcuts via the `/usr/bin/shortcuts` CLI (macOS 12+).
// No entitlements needed — the CLI handles permission prompts itself.

final class ShortcutsStore: ObservableObject {
    static let shared = ShortcutsStore()

    @Published private(set) var shortcuts: [String] = []
    @Published private(set) var loading = false
    @Published private(set) var available = true
    @Published private(set) var running: Set<String> = []

    private let cliPath = "/usr/bin/shortcuts"

    private init() {}

    func refresh() {
        guard FileManager.default.isExecutableFile(atPath: cliPath) else {
            DispatchQueue.main.async { self.available = false }
            return
        }
        DispatchQueue.main.async { self.loading = true }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let output = self.run(args: ["list"]) ?? ""
            let names = output
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            DispatchQueue.main.async {
                self.shortcuts = names
                self.loading = false
                self.available = true
            }
        }
    }

    func runShortcut(_ name: String) {
        DispatchQueue.main.async { self.running.insert(name) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            _ = self.run(args: ["run", name])
            DispatchQueue.main.async { self.running.remove(name) }
        }
    }

    @discardableResult
    private func run(args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cliPath)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            NSLog("shortcuts CLI failed: \(error)")
            return nil
        }
    }
}
