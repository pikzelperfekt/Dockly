import Foundation
import AppKit

struct TrayItem: Codable, Identifiable, Equatable {
    let id: String
    let originalName: String
    let storedPath: String
    let addedAt: Date
    let sizeBytes: Int64

    var url: URL { URL(fileURLWithPath: storedPath) }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: storedPath) }

    var humanSize: String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: sizeBytes)
    }
}

final class TrayStore: ObservableObject {
    static let shared = TrayStore()

    @Published private(set) var items: [TrayItem] = []

    private let storageDir: URL
    private let manifestURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        storageDir = appSupport
            .appendingPathComponent("Dockly", isDirectory: true)
            .appendingPathComponent("Tray", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDir,
                                                 withIntermediateDirectories: true)
        manifestURL = storageDir.appendingPathComponent(".manifest.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([TrayItem].self, from: data) else { return }
        // Drop entries whose files vanished
        items = decoded.filter { FileManager.default.fileExists(atPath: $0.storedPath) }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    @discardableResult
    func add(url: URL) -> TrayItem? {
        let id = UUID().uuidString.prefix(8).lowercased()
        let safeName = url.lastPathComponent
        let dest = storageDir.appendingPathComponent("\(id)-\(safeName)")
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
            let size = (attrs[.size] as? Int64) ?? 0
            let item = TrayItem(id: String(id), originalName: safeName,
                                storedPath: dest.path,
                                addedAt: Date(), sizeBytes: size)
            items.insert(item, at: 0)
            persist()
            return item
        } catch {
            NSLog("Tray copy failed for \(url.path): \(error)")
            return nil
        }
    }

    func remove(_ item: TrayItem) {
        try? FileManager.default.removeItem(at: item.url)
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        for item in items { try? FileManager.default.removeItem(at: item.url) }
        items.removeAll()
        persist()
    }

    func revealInFinder(_ item: TrayItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func airdrop(_ item: TrayItem) {
        let svc = NSSharingService(named: .sendViaAirDrop)
        svc?.perform(withItems: [item.url])
    }
}
