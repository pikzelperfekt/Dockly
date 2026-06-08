import Foundation
import AppKit

// macOS 15.4+/26 locked MediaRemote's now-playing info behind a private
// entitlement, so browser media (YouTube etc.) never reaches us that way.
// This probes Chromium browsers + Safari via AppleScript-injected JavaScript,
// reading navigator.mediaSession metadata from whichever tab is playing.
//
// Requires: Automation permission (prompted on first use). For Safari, also
// "Develop ▸ Allow JavaScript from Apple Events". Chromium: "View ▸ Developer
// ▸ Allow JavaScript from Apple Events".
enum BrowserMediaProbe {
    struct Result { let title: String; let artist: String; let artworkURL: String; let bundleId: String }

    // Finds a non-paused <video>/<audio> and returns "title|||artist|||artworkURL".
    // Backslash-free + single-quoted so it embeds cleanly in an AppleScript string.
    private static let js =
    "(function(){var ms=document.querySelectorAll('video,audio');var m=null;" +
    "for(var i=0;i<ms.length;i++){if(!ms[i].paused&&!ms[i].ended){m=ms[i];break;}}" +
    "if(!m){return '';}" +
    "var d=navigator.mediaSession&&navigator.mediaSession.metadata;" +
    "var t=(d&&d.title)||document.title||'';" +
    "var a=(d&&d.artist)||'';" +
    "var art='';if(d&&d.artwork&&d.artwork.length){art=d.artwork[d.artwork.length-1].src||'';}" +
    "return t+'|||'+a+'|||'+art;})()"

    private static let chromiumApps: [(name: String, bundleId: String)] = [
        ("Google Chrome", "com.google.Chrome"),
        ("Brave Browser", "com.brave.Browser"),
        ("Microsoft Edge", "com.microsoft.edgemac"),
        ("Arc", "company.thebrowser.Browser"),
        ("Chromium", "org.chromium.Chromium"),
        ("Vivaldi", "com.vivaldi.Vivaldi")
    ]

    static func probe() -> Result? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        // Only attempt browsers that are actually running — avoids AppleScript
        // compile errors against absent apps' terminology, and wasted work.
        if running.contains("com.apple.Safari"), let r = probeSafari() { return r }
        for app in chromiumApps where running.contains(app.bundleId) {
            if let r = probeChromium(appName: app.name, bundleId: app.bundleId) { return r }
        }
        return nil
    }

    static func isBrowser(_ bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        return bundleId == "com.apple.Safari" || chromiumApps.contains { $0.bundleId == bundleId }
    }

    enum Command { case playPause, forward, back }

    /// Run a media control on the playing tab of the given browser.
    static func control(_ cmd: Command, bundleId: String) {
        let action: String
        switch cmd {
        case .playPause: action = "if(m.paused){m.play()}else{m.pause()}"
        case .forward:   action = "m.currentTime=Math.min((m.duration||1e9),m.currentTime+10)"
        case .back:      action = "m.currentTime=Math.max(0,m.currentTime-10)"
        }
        let body =
        "(function(){var ms=document.querySelectorAll('video,audio');" +
        "for(var i=0;i<ms.length;i++){var m=ms[i];if(!m.paused||m.currentTime>0){\(action);return 'ok';}}" +
        "return '';})()"
        DispatchQueue.global(qos: .userInitiated).async { _ = exec(body, bundleId: bundleId) }
    }

    @discardableResult
    private static func exec(_ jsBody: String, bundleId: String) -> String? {
        let src: String
        if bundleId == "com.apple.Safari" {
            src = """
            tell application "Safari"
                if it is not running then return ""
                repeat with w in windows
                    try
                        set r to (do JavaScript "\(jsBody)" in (current tab of w))
                        if r is not "" then return r
                    end try
                end repeat
                return ""
            end tell
            """
        } else if let app = chromiumApps.first(where: { $0.bundleId == bundleId }) {
            src = """
            tell application "\(app.name)"
                if it is not running then return ""
                repeat with w in windows
                    try
                        set r to (execute (active tab of w) javascript "\(jsBody)")
                        if r is not "" then return r
                    end try
                end repeat
                return ""
            end tell
            """
        } else { return nil }
        guard let script = NSAppleScript(source: src) else { return nil }
        var err: NSDictionary?
        let out = script.executeAndReturnError(&err).stringValue
        return (err == nil) ? out : nil
    }

    private static func probeChromium(appName: String, bundleId: String) -> Result? {
        let escaped = js.replacingOccurrences(of: "\"", with: "\\\"")
        // Only probe each window's active tab — fast, and where the watched
        // video almost always is.
        let src = """
        tell application "\(appName)"
            if it is not running then return ""
            repeat with w in windows
                try
                    set r to (execute (active tab of w) javascript "\(escaped)")
                    if r is not "" then return r
                end try
            end repeat
            return ""
        end tell
        """
        return run(src, bundleId: bundleId)
    }

    private static func probeSafari() -> Result? {
        let escaped = js.replacingOccurrences(of: "\"", with: "\\\"")
        let src = """
        tell application "Safari"
            if it is not running then return ""
            repeat with w in windows
                try
                    set r to (do JavaScript "\(escaped)" in (current tab of w))
                    if r is not "" then return r
                end try
            end repeat
            return ""
        end tell
        """
        return run(src, bundleId: "com.apple.Safari")
    }

    private static func run(_ source: String, bundleId: String) -> Result? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var err: NSDictionary?
        let desc = script.executeAndReturnError(&err)
        if let err = err {
            let code = (err[NSAppleScript.errorNumber] as? Int) ?? 0
            if code != 0 {  // -600 = not running, -1743 = no automation permission
                ActivityManager.debug("probe \(bundleId): err \(code) \(err[NSAppleScript.errorMessage] as? String ?? "")")
            }
            return nil
        }
        guard let out = desc.stringValue, !out.isEmpty else { return nil }
        let parts = out.components(separatedBy: "|||")
        guard let title = parts.first?.trimmingCharacters(in: .whitespaces), !title.isEmpty
        else { return nil }
        let artist = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        let art = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespaces) : ""
        return Result(title: title, artist: artist, artworkURL: art, bundleId: bundleId)
    }
}
