import Foundation
import AppKit

// Dynamically loads private MediaRemote.framework to read system Now Playing info.
// Works with anything that registers with macOS Now Playing: Music, Spotify, Safari/Chrome
// (YouTube, web players), Podcasts, VLC, IINA, etc.
// On macOS 15.4+ Apple restricted this API; if it returns empty we fall back to AppleScript.

private typealias MRGetNowPlayingInfoFn =
    @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
private typealias MRRegisterNotificationsFn =
    @convention(c) (DispatchQueue) -> Void
private typealias MRGetIsPlayingFn =
    @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
private typealias MRGetClientFn =
    @convention(c) (DispatchQueue, @escaping (AnyObject?) -> Void) -> Void
private typealias MRGetPIDFn =
    @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void
private typealias MRSendCommandFn =
    @convention(c) (Int, AnyObject?) -> Bool
private typealias MRSetElapsedFn =
    @convention(c) (Double) -> Void

struct NowPlayingSnapshot: Equatable {
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
    let bundleId: String?
    let artwork: Data?
    // Playback position (for the scrubber). elapsed is the value sampled at `timestamp`.
    let elapsed: Double
    let duration: Double
    let rate: Double
    let timestamp: Date
    let isVideo: Bool

    static func == (lhs: NowPlayingSnapshot, rhs: NowPlayingSnapshot) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist
            && lhs.isPlaying == rhs.isPlaying && lhs.bundleId == rhs.bundleId
    }
}

final class MediaRemoteBridge {
    static let shared = MediaRemoteBridge()

    private let getNowPlaying: MRGetNowPlayingInfoFn?
    private let registerForNotifs: MRRegisterNotificationsFn?
    private let getIsPlaying: MRGetIsPlayingFn?
    private let getClient: MRGetClientFn?
    private let getPID: MRGetPIDFn?
    private let send: MRSendCommandFn?
    private let setElapsed: MRSetElapsedFn?

    var isAvailable: Bool { getNowPlaying != nil }
    var canSeek: Bool { setElapsed != nil }

    private init() {
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL) else {
            getNowPlaying = nil; registerForNotifs = nil
            getIsPlaying = nil; getClient = nil; getPID = nil; send = nil
            setElapsed = nil
            return
        }
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let ptr = CFBundleGetFunctionPointerForName(bundle, name as CFString) else { return nil }
            return unsafeBitCast(ptr, to: type)
        }
        getNowPlaying = sym("MRMediaRemoteGetNowPlayingInfo", MRGetNowPlayingInfoFn.self)
        registerForNotifs = sym("MRMediaRemoteRegisterForNowPlayingNotifications",
                                MRRegisterNotificationsFn.self)
        getIsPlaying = sym("MRMediaRemoteGetNowPlayingApplicationIsPlaying", MRGetIsPlayingFn.self)
        getClient = sym("MRMediaRemoteGetNowPlayingClient", MRGetClientFn.self)
        getPID = sym("MRMediaRemoteGetNowPlayingApplicationPID", MRGetPIDFn.self)
        send = sym("MRMediaRemoteSendCommand", MRSendCommandFn.self)
        setElapsed = sym("MRMediaRemoteSetElapsedTime", MRSetElapsedFn.self)
    }

    /// Seek the now-playing track to an absolute time (seconds).
    func seek(to seconds: Double) {
        setElapsed?(max(0, seconds))
    }

    func registerForChanges() {
        registerForNotifs?(.main)
    }

    func fetch(_ completion: @escaping (NowPlayingSnapshot?) -> Void) {
        guard let getNowPlaying else { completion(nil); return }
        getNowPlaying(.main) { [weak self] info in
            guard let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
                  !title.isEmpty else { completion(nil); return }
            let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            let album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
            let rate = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ?? 0
            let isPlaying = rate > 0
            let artwork = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
            let elapsed = (info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0
            let duration = (info["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0
            let ts = (info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date) ?? Date()
            // Media type: distinguishes video sources (YouTube, QuickTime…) from music.
            let mediaType = info["kMRMediaRemoteNowPlayingInfoMediaType"] as? String ?? ""
            let isVideo = mediaType.localizedCaseInsensitiveContains("video")

            self?.resolveBundleId { bundleId in
                completion(NowPlayingSnapshot(
                    title: title, artist: artist, album: album,
                    isPlaying: isPlaying, bundleId: bundleId, artwork: artwork,
                    elapsed: elapsed, duration: duration, rate: rate, timestamp: ts,
                    isVideo: isVideo
                ))
            }
        }
    }

    private func resolveBundleId(_ completion: @escaping (String?) -> Void) {
        // First try the dedicated client-info API. On macOS 15.4+/26, this is
        // often restricted — so we fall back to looking up the PID and asking
        // NSRunningApplication for its bundle identifier.
        if let getClient {
            getClient(.main) { [weak self] client in
                if let client {
                    let sel = NSSelectorFromString("bundleIdentifier")
                    if client.responds(to: sel),
                       let result = client.perform(sel)?.takeUnretainedValue() as? String,
                       !result.isEmpty {
                        completion(result); return
                    }
                }
                self?.resolveByPID(completion)
            }
        } else {
            resolveByPID(completion)
        }
    }

    private func resolveByPID(_ completion: @escaping (String?) -> Void) {
        guard let getPID else { completion(nil); return }
        getPID(.main) { pid in
            guard pid > 0,
                  let app = NSRunningApplication(processIdentifier: pid),
                  let id = app.bundleIdentifier,
                  !id.isEmpty
            else { completion(nil); return }
            completion(id)
        }
    }

    // Commands: 0=Play, 1=Pause, 2=TogglePlayPause, 3=Stop, 4=NextTrack, 5=PreviousTrack
    @discardableResult func playPause() -> Bool { send?(2, nil) ?? false }
    @discardableResult func next()      -> Bool { send?(4, nil) ?? false }
    @discardableResult func previous()  -> Bool { send?(5, nil) ?? false }
}
