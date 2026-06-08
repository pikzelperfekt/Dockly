import Foundation
import EventKit
import AppKit
import SwiftUI
import Combine

enum LiveActivity: Equatable {
    case clock
    case music(title: String, artist: String, isPlaying: Bool, bundleId: String?, artwork: Data?)
    case upcomingEvent(title: String, calendarColor: CGColor, minutesUntil: Int, timeString: String)
    case battery(BatteryMonitor.BatteryEvent, percent: Int)
    case volume(Int, muted: Bool)
    case bluetooth(name: String, connected: Bool, icon: String)
    case focus(on: Bool)
    case timer(state: TimerManager.State)

    static func == (lhs: LiveActivity, rhs: LiveActivity) -> Bool {
        switch (lhs, rhs) {
        case (.clock, .clock): return true
        case let (.music(t1,a1,p1,b1,_), .music(t2,a2,p2,b2,_)):
            return t1==t2 && a1==a2 && p1==p2 && b1==b2
        case let (.upcomingEvent(t1,_,m1,_), .upcomingEvent(t2,_,m2,_)):
            return t1==t2 && m1==m2
        case let (.battery(e1,p1), .battery(e2,p2)):
            return e1==e2 && p1==p2
        case let (.volume(v1,m1), .volume(v2,m2)):
            return v1==v2 && m1==m2
        case let (.bluetooth(n1,c1,_), .bluetooth(n2,c2,_)):
            return n1==n2 && c1==c2
        case let (.focus(o1), .focus(o2)):
            return o1==o2
        case let (.timer(s1), .timer(s2)):
            return s1==s2
        default: return false
        }
    }
}

enum MusicApp {
    static func icon(forBundle id: String?) -> NSImage? {
        guard let id, !id.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func accentColor(forBundle id: String?) -> (Color, Color) {
        switch id ?? "" {
        case "com.spotify.client":
            return (Color(red: 0.11, green: 0.73, blue: 0.33),
                    Color(red: 0.05, green: 0.45, blue: 0.20))
        case "com.apple.Music":
            return (Color(red: 1.00, green: 0.28, blue: 0.45),
                    Color(red: 0.65, green: 0.10, blue: 0.30))
        case "com.apple.podcasts":
            return (Color(red: 0.62, green: 0.30, blue: 0.92),
                    Color(red: 0.36, green: 0.12, blue: 0.62))
        case "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser":
            return (Color(red: 0.30, green: 0.55, blue: 0.95),
                    Color(red: 0.14, green: 0.30, blue: 0.65))
        default:
            return (Color(red: 0.55, green: 0.35, blue: 0.85),
                    Color(red: 0.30, green: 0.18, blue: 0.55))
        }
    }
}

struct PlaybackProgress: Equatable {
    var elapsed: Double      // seconds, sampled at `sampledAt`
    var duration: Double
    var rate: Double
    var sampledAt: Date

    /// Live elapsed time, extrapolated from the sample.
    func current(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        let e = elapsed + (rate > 0 ? now.timeIntervalSince(sampledAt) * rate : 0)
        return min(max(0, e), duration)
    }
}

final class ActivityManager: ObservableObject {
    static let shared = ActivityManager()

    @Published private(set) var current: LiveActivity = .clock
    @Published private(set) var playback: PlaybackProgress?
    @Published private(set) var mediaIsVideo = false
    /// Accent color pulled from the current artwork (nil = no art / not music).
    @Published private(set) var accentColor: NSColor?
    /// Several vivid colors from the artwork, for the animated border.
    @Published private(set) var accentPalette: [NSColor] = []

    /// SwiftUI accent — album color when available, else the system accent.
    var accent: Color { accentColor.map { Color(nsColor: $0) } ?? Color.accentColor }

    private let ek = EKEventStore()
    private let mr = MediaRemoteBridge.shared
    private var eventTimer: Timer?
    private var mediaPollTimer: Timer?
    private var lastSnapshot: NowPlayingSnapshot?
    private var spotifyArtworkCache: [String: Data] = [:]
    private var spotifyFetchTrackId: String?
    // Source-agnostic artwork cache keyed by "title|artist" + retry tracking,
    // so brief MediaRemote gaps (common right after a track change) don't blank
    // the art, and missing art is re-fetched a couple times until it lands.
    private var artworkCache: [String: Data] = [:]
    private var artworkRetryKey: String?
    private var artworkRetryCount = 0
    private var batterySink: AnyCancellable?
    private var volumeSink: AnyCancellable?
    private var bluetoothSink: AnyCancellable?
    private var focusSink: AnyCancellable?
    private var timerSink: AnyCancellable?
    private var timerActive = false
    private var calendarSelectionSink: AnyCancellable?
    private var audioReactiveSink: AnyCancellable?
    private var transientActive = false
    private var transientClearWork: DispatchWorkItem?

    /// Briefly take over the pill with a transient activity (volume, battery,
    /// bluetooth…), then restore whatever was showing.
    private func showTransient(_ activity: LiveActivity, seconds: Double = 3) {
        transientActive = true
        current = activity
        transientClearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.transientActive = false
            // Restore whatever should own the pill: timer > media > event/clock.
            if self.timerActive {
                self.current = .timer(state: TimerManager.shared.state)
            } else {
                self.refreshMedia()
                self.refreshEvents()
            }
        }
        transientClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - Lifecycle

    func start() {
        checkCalendarAccess()
        startMediaListening()
        startBatteryMonitoring()
        refreshMedia()
        refreshEvents()
        // Instant calendar refresh when events change or the calendar DB updates.
        NotificationCenter.default.addObserver(
            self, selector: #selector(eventsChanged),
            name: .EKEventStoreChanged, object: ek)
        // React instantly when the user changes which calendars are selected.
        calendarSelectionSink = AppSettings.shared.$selectedCalendarIDs
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshEvents() }
            }
        // Lower-frequency tick keeps the "in X min" countdown current.
        eventTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.refreshEvents()
        }
        // Start/stop the audio reactor when DJ mode is toggled.
        audioReactiveSink = AppSettings.shared.$audioReactive.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateAudioReactor() }
        }
    }

    private var isMusicPlaying: Bool {
        if case .music(_, _, true, _, _) = current { return true }
        return false
    }

    /// Run the live audio analyzer only while DJ mode is on AND music plays.
    private func updateAudioReactor() {
        if AppSettings.shared.audioReactive && isMusicPlaying {
            AudioReactor.shared.start()
        } else {
            AudioReactor.shared.stop()
        }
    }

    @objc private func eventsChanged() {
        DispatchQueue.main.async { [weak self] in self?.refreshEvents() }
    }

    private func startBatteryMonitoring() {
        BatteryMonitor.shared.start()
        batterySink = BatteryMonitor.shared.$event.sink { [weak self] event in
            guard let self, let event else { return }
            let pct = BatteryMonitor.shared.state?.percent ?? 0
            self.showTransient(.battery(event, percent: pct), seconds: 4)
        }

        // Bluetooth connect / disconnect → brief device pill.
        BluetoothMonitor.shared.start()
        bluetoothSink = BluetoothMonitor.shared.$event.sink { [weak self] e in
            guard let self, let e else { return }
            self.showTransient(.bluetooth(name: e.name, connected: e.connected, icon: e.icon),
                               seconds: 3)
        }

        // Focus / Do Not Disturb on / off → brief pill (best-effort detection).
        FocusMonitor.shared.start()
        focusSink = FocusMonitor.shared.$event.sink { [weak self] e in
            guard let self, let e else { return }
            self.showTransient(.focus(on: e.on), seconds: 2.5)
        }

        // Native timer — while active it owns the pill (above music/event/clock).
        timerSink = TimerManager.shared.$state.sink { [weak self] st in
            guard let self else { return }
            if st == .idle {
                self.timerActive = false
                self.refreshMedia(); self.refreshEvents()
            } else {
                self.timerActive = true
                self.current = .timer(state: st)
            }
        }
    }

    private func startMediaListening() {
        // MediaRemote: register for system-wide now-playing notifications
        mr.registerForChanges()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(mediaChanged),
                       name: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
                       object: nil)
        nc.addObserver(self, selector: #selector(mediaChanged),
                       name: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"),
                       object: nil)
        nc.addObserver(self, selector: #selector(mediaChanged),
                       name: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
                       object: nil)

        // AppleScript fallback notifications (some apps post these directly)
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(mediaChanged),
                        name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
                        object: nil)
        dnc.addObserver(self, selector: #selector(mediaChanged),
                        name: NSNotification.Name("com.apple.Music.playerInfo"),
                        object: nil)

        // App launch / quit — covers the case where MediaRemote keeps serving
        // stale info after the source app exits. Spotify quit? Music quit?
        // YouTube tab closed? We re-check immediately.
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(mediaChanged),
                         name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(mediaChanged),
                         name: NSWorkspace.didLaunchApplicationNotification, object: nil)

        // Faster safety-net poll (3s) so any missed notification is recovered quickly
        mediaPollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshMedia()
        }
    }

    @objc private func mediaChanged() { refreshMedia() }

    // MARK: - Media query

    private func refreshMedia() {
        if timerActive { return }   // timer owns the pill while active
        if mr.isAvailable {
            mr.fetch { [weak self] snap in
                guard let self else { return }
                if let snap, !snap.title.isEmpty {
                    self.applyMusic(snap)
                } else {
                    self.fetchAppleScriptFallback()
                }
            }
        } else {
            fetchAppleScriptFallback()
        }
    }

    // Diagnostics → /tmp/dockly-np.log. Enabled when DOCKLY_DEBUG is set OR the
    // flag file /tmp/dockly-debug-on exists (so it works under `open` too).
    static func debug(_ msg: String) {
        let on = ProcessInfo.processInfo.environment["DOCKLY_DEBUG"] != nil
            || FileManager.default.fileExists(atPath: "/tmp/dockly-debug-on")
        guard on else { return }
        let line = "[\(Date())] \(msg)\n"
        if let data = line.data(using: .utf8) {
            let url = URL(fileURLWithPath: "/tmp/dockly-np.log")
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    private func applyMusic(_ snap: NowPlayingSnapshot) {
        lastSnapshot = snap
        guard !transientActive, !timerActive else { return }  // timer/transient own the pill

        // Validate the source app is still alive — MediaRemote can serve stale
        // info for a long time after an app quits. If we know which app owns
        // this snapshot and it's not running, treat it as no music.
        if let bundleId = snap.bundleId, !isAppRunning(bundleId: bundleId) {
            clearMusic()
            return
        }
        if transientActive { Self.debug("applyMusic skipped — transient active") }

        // Show the track whether playing OR paused (frozen UI when paused).
        // We only stop showing music when the source app is gone (handled above).
        mediaIsVideo = snap.isVideo
        let key = "\(snap.title)|\(snap.artist)"
        // Cache fresh art; reuse cached art when this snapshot has none.
        var art = snap.artwork
        if let a = art, !a.isEmpty {
            artworkCache[key] = a
        } else {
            art = artworkCache[key]
        }
        current = .music(title: snap.title, artist: snap.artist,
                         isPlaying: snap.isPlaying, bundleId: snap.bundleId, artwork: art)
        updateAccent(from: art)
        updateAudioReactor()
        playback = snap.duration > 0
            ? PlaybackProgress(elapsed: snap.elapsed, duration: snap.duration,
                               rate: snap.rate, sampledAt: snap.timestamp)
            : nil

        if snap.bundleId == "com.spotify.client" {
            enrichSpotifyArtwork(title: snap.title, artist: snap.artist)
        } else if snap.bundleId == "com.apple.Music", art == nil {
            enrichAppleMusicArtwork(title: snap.title, artist: snap.artist)
        }
        // No art yet? Retry a couple times — it usually lands within a second.
        if art == nil {
            scheduleArtworkRetry(for: key)
        } else {
            artworkRetryKey = nil; artworkRetryCount = 0
        }
    }

    private func scheduleArtworkRetry(for key: String) {
        if artworkRetryKey != key { artworkRetryKey = key; artworkRetryCount = 0 }
        guard artworkRetryCount < 4 else { return }
        artworkRetryCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.artworkRetryKey == key else { return }
            self.refreshMedia()
        }
    }

    /// Seek the current track (MediaRemote). seconds is absolute.
    func seek(to seconds: Double) {
        guard mr.canSeek else { return }
        mr.seek(to: seconds)
        if var p = playback {
            p.elapsed = seconds
            p.sampledAt = Date()
            playback = p
        }
        // Re-pull shortly after so we reflect the app's accepted position.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshMedia()
        }
    }

    private func isAppRunning(bundleId: String) -> Bool {
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        if running.contains(bundleId) { return true }
        // Browser video (YouTube etc.) is owned by a helper/renderer process —
        // e.g. "com.google.Chrome.helper". Match it back to the parent app so we
        // don't wrongly reject it as stale.
        return running.contains { bundleId.hasPrefix($0) || $0.hasPrefix(bundleId) }
    }

    private func enrichSpotifyArtwork(title: String, artist: String) {
        let src = """
        tell application "Spotify"
            if it is running then
                return (id of current track) & "|||" & (artwork url of current track)
            end if
            return ""
        end tell
        """
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let script = NSAppleScript(source: src)
            var err: NSDictionary?
            let result = script?.executeAndReturnError(&err)
            guard err == nil,
                  let str = result?.stringValue,
                  !str.isEmpty,
                  let self else { return }
            let parts = str.components(separatedBy: "|||")
            guard parts.count >= 2 else { return }
            let trackId = parts[0].trimmingCharacters(in: .whitespaces)
            let urlStr = parts[1].trimmingCharacters(in: .whitespaces)
            guard !trackId.isEmpty, let url = URL(string: urlStr) else { return }

            // De-dupe in-flight fetches and serve from cache
            DispatchQueue.main.async {
                if let cached = self.spotifyArtworkCache[trackId] {
                    self.replaceArtwork(with: cached, title: title, artist: artist)
                    return
                }
                guard self.spotifyFetchTrackId != trackId else { return }
                self.spotifyFetchTrackId = trackId

                URLSession.shared.dataTask(with: url) { data, _, _ in
                    DispatchQueue.main.async {
                        self.spotifyFetchTrackId = nil
                        guard let data, !data.isEmpty else { return }
                        self.spotifyArtworkCache[trackId] = data
                        self.replaceArtwork(with: data, title: title, artist: artist)
                    }
                }.resume()
            }
        }
    }

    private func enrichAppleMusicArtwork(title: String, artist: String) {
        let src = """
        tell application "Music"
            if it is running and player state is playing then
                if (count of artworks of current track) > 0 then
                    return data of artwork 1 of current track
                end if
            end if
            return ""
        end tell
        """
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let script = NSAppleScript(source: src)
            var err: NSDictionary?
            guard let result = script?.executeAndReturnError(&err), err == nil else { return }
            guard let data = result.data as Data?, !data.isEmpty,
                  NSImage(data: data) != nil, let self else { return }
            DispatchQueue.main.async {
                self.replaceArtwork(with: data, title: title, artist: artist)
            }
        }
    }

    private func replaceArtwork(with data: Data, title: String, artist: String) {
        artworkCache["\(title)|\(artist)"] = data
        guard case let .music(t, a, p, b, _) = current,
              t == title, a == artist else { return }
        current = .music(title: t, artist: a, isPlaying: p, bundleId: b, artwork: data)
        updateAccent(from: data)
    }

    private func fetchAppleScriptFallback() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            // 1) Dedicated apps (Spotify / Apple Music) — show playing AND paused.
            // Returns nil only when the app is closed/stopped (then we clear).
            if let info = self.fetchAppleScriptNowPlaying() {
                DispatchQueue.main.async {
                    let key = "\(info.title)|\(info.artist)"
                    self.current = .music(title: info.title, artist: info.artist,
                                          isPlaying: info.isPlaying, bundleId: info.bundleId,
                                          artwork: self.artworkCache[key])
                    self.updateAccent(from: self.artworkCache[key])
                    self.updateAudioReactor()
                    if info.bundleId == "com.spotify.client" {
                        self.enrichSpotifyArtwork(title: info.title, artist: info.artist)
                    } else if info.bundleId == "com.apple.Music" {
                        self.enrichAppleMusicArtwork(title: info.title, artist: info.artist)
                    }
                }
                return
            }
            // 2) Browser media (YouTube etc.) via injected JavaScript
            if let b = BrowserMediaProbe.probe() {
                Self.debug("Browser probe: \(b.title) [\(b.bundleId)] art=\(b.artworkURL.isEmpty ? "no" : "yes")")
                DispatchQueue.main.async {
                    let key = "\(b.title)|\(b.artist)"
                    self.mediaIsVideo = true
                    self.current = .music(title: b.title, artist: b.artist,
                                          isPlaying: true, bundleId: b.bundleId,
                                          artwork: self.artworkCache[key])
                    self.updateAccent(from: self.artworkCache[key])
                    self.updateAudioReactor()
                }
                if !b.artworkURL.isEmpty, let url = URL(string: b.artworkURL) {
                    self.downloadArtwork(url, title: b.title, artist: b.artist)
                }
                return
            }
            // 3) Nothing playing — force-clear music (refreshEvents won't, since
            // it treats music as higher priority and bails).
            DispatchQueue.main.async { self.clearMusic() }
        }
    }

    /// Drop out of the music activity to the idle activity (event or clock),
    /// bypassing refreshEvents' "music has priority" guard.
    private func clearMusic() {
        guard case .music = current else { return }
        playback = nil
        mediaIsVideo = false
        accentColor = nil
        accentPalette = []
        current = idleActivity()
        updateAudioReactor()
    }

    /// Recompute the album-art accent color + palette (off the main thread).
    private func updateAccent(from art: Data?) {
        guard let art else { accentColor = nil; accentPalette = []; return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let c = DominantColor.from(art)
            let p = DominantColor.palette(art)
            DispatchQueue.main.async {
                self?.accentColor = c
                self?.accentPalette = p
            }
        }
    }

    /// The activity to show when no media is playing: next event, else clock.
    private func idleActivity() -> LiveActivity {
        guard !transientActive, let event = nextUpcomingEvent() else { return .clock }
        let mins = max(0, Int(event.startDate.timeIntervalSinceNow / 60))
        let timeStr = event.startDate.formatted(.dateTime.hour().minute())
        return .upcomingEvent(title: event.title ?? "Event",
                              calendarColor: event.calendar.cgColor,
                              minutesUntil: mins, timeString: timeStr)
    }

    private func downloadArtwork(_ url: URL, title: String, artist: String) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, !data.isEmpty else { return }
            DispatchQueue.main.async { self.replaceArtwork(with: data, title: title, artist: artist) }
        }.resume()
    }

    private func fetchAppleScriptNowPlaying()
        -> (title: String, artist: String, isPlaying: Bool, bundleId: String)? {
        for (app, bundle) in [("Spotify", "com.spotify.client"), ("Music", "com.apple.Music")] {
            if let info = queryMusicApp(app, bundleId: bundle) { return info }
        }
        return nil
    }

    private func queryMusicApp(_ app: String, bundleId: String)
        -> (title: String, artist: String, isPlaying: Bool, bundleId: String)? {
        let src = """
        tell application "\(app)"
            if it is running then
                set ps to (player state as string)
                if ps is "playing" or ps is "paused" then
                    return ps & "|||" & (name of current track) & "|||" & (artist of current track)
                end if
            end if
            return ""
        end tell
        """
        let script = NSAppleScript(source: src)
        var err: NSDictionary?
        let result = script?.executeAndReturnError(&err)
        guard err == nil, let str = result?.stringValue, !str.isEmpty else { return nil }
        let parts = str.components(separatedBy: "|||")
        guard parts.count >= 3 else { return nil }
        let isPlaying = parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "playing"
        return (parts[1].trimmingCharacters(in: .whitespaces),
                parts[2].trimmingCharacters(in: .whitespaces),
                isPlaying,
                bundleId)
    }

    // MARK: - Media controls

    func playPause() {
        guard case let .music(_, _, _, bundleId, _) = current else { return }
        if BrowserMediaProbe.isBrowser(bundleId) {
            BrowserMediaProbe.control(.playPause, bundleId: bundleId!)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refreshMedia() }
            return
        }
        if mr.isAvailable, mr.playPause() { return }
        sendAppleScriptCommand("playpause", bundleId: bundleId)
    }

    func nextTrack() {
        guard case let .music(_, _, _, bundleId, _) = current else { return }
        if BrowserMediaProbe.isBrowser(bundleId) {
            BrowserMediaProbe.control(.forward, bundleId: bundleId!)   // +10s for video
            return
        }
        if mr.isAvailable, mr.next() { return }
        sendAppleScriptCommand("next track", bundleId: bundleId)
    }

    func previousTrack() {
        guard case let .music(_, _, _, bundleId, _) = current else { return }
        if BrowserMediaProbe.isBrowser(bundleId) {
            BrowserMediaProbe.control(.back, bundleId: bundleId!)      // -10s for video
            return
        }
        if mr.isAvailable, mr.previous() { return }
        sendAppleScriptCommand("previous track", bundleId: bundleId)
    }

    private func sendAppleScriptCommand(_ command: String, bundleId: String?) {
        let app: String
        switch bundleId {
        case "com.spotify.client": app = "Spotify"
        case "com.apple.Music":    app = "Music"
        default: return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let script = NSAppleScript(source: "tell application \"\(app)\" to \(command)")
            var err: NSDictionary?
            script?.executeAndReturnError(&err)
            DispatchQueue.main.async { self?.refreshMedia() }
        }
    }

    // MARK: - Calendar events

    private func checkCalendarAccess() {
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return }
        ek.requestAccess(to: .event) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshEvents() }
        }
    }

    private func refreshEvents() {
        if transientActive || timerActive { return }  // timer/transient own the pill
        if case .music = current { return }   // music takes priority

        if let event = nextUpcomingEvent() {
            let mins = max(0, Int(event.startDate.timeIntervalSinceNow / 60))
            let timeStr = event.startDate.formatted(.dateTime.hour().minute())
            current = .upcomingEvent(title: event.title ?? "Event",
                                     calendarColor: event.calendar.cgColor,
                                     minutesUntil: mins,
                                     timeString: timeStr)
        } else {
            current = .clock
        }
    }

    private func nextUpcomingEvent() -> EKEvent? {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .authorized || status.rawValue == 4 else { return nil }
        let now = Date()
        let end = Calendar.current.date(byAdding: .hour, value: 2, to: now)!

        // Honor the user's calendar selection (empty = all calendars).
        let selected = AppSettings.shared.selectedCalendarIDs
        let cals: [EKCalendar]? = selected.isEmpty ? nil
            : ek.calendars(for: .event).filter { selected.contains($0.calendarIdentifier) }
        let pred = ek.predicateForEvents(withStart: now, end: end, calendars: cals)
        return ek.events(matching: pred)
            .filter { !$0.isAllDay }
            .min { $0.startDate < $1.startDate }
    }
}
