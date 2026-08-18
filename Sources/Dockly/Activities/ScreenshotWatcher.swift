import Foundation
import AppKit
import CoreServices
import Combine

// Watches wherever macOS drops screenshots and announces each new one so the
// notch can offer it up: drag it straight into another app, copy it, stash it
// in the Tray, or bin it — without the round trip to the Desktop.
//
// The save location is whatever the user set in Screenshot.app (⇧⌘5 ▸ Options),
// read from com.apple.screencapture; unset means the Desktop.
final class ScreenshotWatcher: ObservableObject {
    static let shared = ScreenshotWatcher()

    struct Shot: Equatable {
        let url: URL
        let thumbnail: Data?
        var name: String { url.lastPathComponent }
    }

    @Published private(set) var latest: Shot?

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var watchedDir: URL?
    private var seen: Set<String> = []
    private var started = false
    private var settingsSink: AnyCancellable?
    private var locationTimer: Timer?

    /// Files younger than this when the directory changes are candidates. Long
    /// enough to survive Spotlight lag, short enough that opening the folder
    /// later never re-announces an old shot.
    private let freshnessWindow: TimeInterval = 8

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        rebind()
        settingsSink = AppSettings.shared.$screenshotShelf
            .dropFirst()
            .sink { [weak self] on in
                DispatchQueue.main.async {
                    if on { self?.rebind() } else { self?.unwatch(); self?.latest = nil }
                }
            }
        // Repointing the folder in ⇧⌘5 ▸ Options posts no notification we can
        // subscribe to, so poll the preference occasionally and re-bind if it
        // moved. Cheap, and it saves a restart.
        locationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, AppSettings.shared.screenshotShelf else { return }
            if self.watchedDir?.standardizedFileURL != Self.saveLocation().standardizedFileURL {
                self.rebind()
            }
        }
    }

    /// Where Screenshot.app is currently configured to save. Unset (the common
    /// case) means the Desktop.
    static func saveLocation() -> URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
        guard let raw = CFPreferencesCopyAppValue("location" as CFString,
                                                  "com.apple.screencapture" as CFString) as? String,
              !raw.isEmpty else { return desktop }
        let expanded = (raw as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue
        else { return desktop }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    /// The format macOS saves interactive (⇧⌘3/4/5) captures in. Unset = PNG.
    /// Worth surfacing because a stray `heic` here silently produces files that
    /// most upload forms reject, with nothing in System Settings to explain it.
    static func captureFormat() -> String {
        let raw = CFPreferencesCopyAppValue("type" as CFString,
                                            "com.apple.screencapture" as CFString) as? String
        let fmt = (raw ?? "png").lowercased()
        return fmt.isEmpty ? "png" : fmt
    }

    static func setCaptureFormat(_ format: String) {
        CFPreferencesSetAppValue("type" as CFString, format as CFString,
                                 "com.apple.screencapture" as CFString)
        CFPreferencesAppSynchronize("com.apple.screencapture" as CFString)
        // The capture UI reads this once at launch; SystemUIServer comes straight
        // back on its own, so a restart is the supported way to apply it.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["SystemUIServer"]
        try? p.run()
    }

    // MARK: - Directory watching

    private func rebind() {
        unwatch()
        guard AppSettings.shared.screenshotShelf else { return }
        let dir = Self.saveLocation()
        watchedDir = dir
        // Everything already sitting there is old news.
        seen = Set(currentFilenames(in: dir))

        fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { watchedDir = nil; return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = self.source?.data ?? []
            if flags.contains(.delete) || flags.contains(.rename) {
                // The folder itself moved out from under us — re-open it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.rebind() }
                return
            }
            self.scan(dir)
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd) }
            self?.fd = -1
        }
        source = src
        src.resume()
    }

    private func unwatch() {
        source?.cancel()
        source = nil
        watchedDir = nil
    }

    private func currentFilenames(in dir: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    }

    // MARK: - Detection

    private func scan(_ dir: URL) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        let fresh = names.filter { !seen.contains($0) }
        seen = Set(names)
        guard !fresh.isEmpty else { return }

        let cutoff = Date().addingTimeInterval(-freshnessWindow)
        let candidates = fresh
            .map { dir.appendingPathComponent($0) }
            .filter { Self.isImage($0) }
            .compactMap { url -> (URL, Date)? in
                guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                      let created = (attrs[.creationDate] as? Date) ?? (attrs[.modificationDate] as? Date),
                      created > cutoff else { return nil }
                return (url, created)
            }
            .sorted { $0.1 > $1.1 }

        guard let newest = candidates.first?.0 else { return }
        // Spotlight tags real screen captures, but the index lags the write by a
        // beat, so give it a couple of tries before deciding.
        confirmScreenshot(newest, attempt: 0)
    }

    private func confirmScreenshot(_ url: URL, attempt: Int) {
        switch Self.screenCaptureFlag(url) {
        case .some(true):
            announce(url)
        case .some(false):
            ActivityManager.debug("Shelf: \(url.lastPathComponent) is not a screen capture — ignoring")
        case .none:
            // Spotlight has nothing yet. Retry, then fall back: a dedicated
            // screenshot folder holds nothing but screenshots, so anything new
            // there counts. The shared Desktop gets no such benefit of the doubt.
            guard attempt < 3 else {
                if !Self.savesToDesktop() { announce(url) }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.confirmScreenshot(url, attempt: attempt + 1)
            }
        }
    }

    private func announce(_ url: URL) {
        guard AppSettings.shared.screenshotShelf,
              FileManager.default.fileExists(atPath: url.path) else { return }
        ActivityManager.debug("Shelf: announcing \(url.lastPathComponent)")
        let shot = Shot(url: url, thumbnail: Self.thumbnail(url))
        latest = shot
        if AppSettings.shared.screenshotAutoTray {
            TrayStore.shared.add(url: url)
        }
    }

    /// nil = Spotlight hasn't indexed the file yet (not "no").
    private static func screenCaptureFlag(_ url: URL) -> Bool? {
        guard let item = MDItemCreate(nil, url.path as CFString),
              let value = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString)
        else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private static func savesToDesktop() -> Bool {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        return saveLocation().standardizedFileURL == desktop?.standardizedFileURL
    }

    private static func isImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "heic", "tiff", "gif"].contains(url.pathExtension.lowercased())
    }

    /// A small PNG for the pill. Screenshots are retina-sized, and handing the
    /// full thing to SwiftUI on every frame of the pill animation is wasteful.
    private static func thumbnail(_ url: URL, maxEdge: CGFloat = 240) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Actions

    func copyToPasteboard(_ shot: Shot) {
        guard let image = NSImage(contentsOf: shot.url) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    func addToTray(_ shot: Shot) {
        TrayStore.shared.add(url: shot.url)
    }

    func reveal(_ shot: Shot) {
        NSWorkspace.shared.activateFileViewerSelecting([shot.url])
    }

    /// macOS can be set to capture HEIC (`defaults write com.apple.screencapture
    /// type heic`), and a lot of the web won't take a .heic upload. Rewrite the
    /// shot as a PNG next to the original, then bin the original so the Desktop
    /// isn't left with two copies of the same picture.
    func convertToPNG(_ shot: Shot) {
        guard !Self.isPNG(shot.url) else { return }
        let dest = uniquePNGURL(basedOn: shot.url)
        guard let src = CGImageSourceCreateWithURL(shot.url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        else { return }
        do { try png.write(to: dest, options: .atomic) } catch { return }
        // Only bin the original once the replacement is on disk for real.
        guard FileManager.default.fileExists(atPath: dest.path) else { return }
        try? FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)
        seen.insert(dest.lastPathComponent)   // our own write is not a new capture
        latest = Shot(url: dest, thumbnail: Self.thumbnail(dest))
    }

    static func isPNG(_ url: URL) -> Bool { url.pathExtension.lowercased() == "png" }

    private func uniquePNGURL(basedOn url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent(base).appendingPathExtension("png")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension("png")
            n += 1
        }
        return candidate
    }

    /// Bin it — to the Trash, never an outright unlink, so a misfire is undoable.
    func trash(_ shot: Shot) {
        try? FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)
        if latest == shot { latest = nil }
    }

    func dismiss() { latest = nil }
}
