# Shipping & Auto-Updates — how this works

A reference for humans **and AI agents** maintaining Dockly (and a recipe to
reuse for other macOS apps). No backend, no database — just GitHub Releases +
[Sparkle](https://sparkle-project.org).

---

## TL;DR — cut a new release

```bash
./release.sh <version> <github-user>      # e.g. ./release.sh 1.02 pikzelperfekt
./make-dmg.sh                             # optional: also build the installer DMG
gh release create v<version> \
  dist/releases/Dockly.zip dist/releases/appcast.xml dist/Dockly.dmg \
  --title "Dockly <version>" --notes "what changed"
```

Every installed copy checks `…/releases/latest/download/appcast.xml` daily (and
via **Check for Updates…**), sees the new version, verifies the EdDSA signature,
downloads, and self-installs. Use **increasing** version numbers.

---

## How auto-updates work

- The app embeds **Sparkle** and has `SUFeedURL` + `SUPublicEDKey` in `Info.plist`.
- Sparkle fetches the **appcast** (an XML file) from the feed URL.
- The appcast lists the newest version, a download URL, and an **EdDSA signature**.
- Sparkle compares versions, downloads, verifies the signature against the
  embedded public key, installs, and relaunches.
- Hosting is just **static files** on GitHub Releases — the appcast + the zip.
  The `…/releases/latest/download/<asset>` URL always points at the newest
  release's assets, so the feed self-tracks.

## Files involved

| File | Role |
|------|------|
| `Package.swift` | Adds the Sparkle SPM dep. Weak-links CoreAudio (see Ventura). |
| `Info.plist` | `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, `SUScheduledCheckInterval`, `CFBundleShortVersionString`/`CFBundleVersion`. |
| `Sources/Dockly/Core/Updater.swift` | Wraps `SPUStandardUpdaterController`; powers background checks + "Check for Updates…". |
| `build-app.sh` | Builds the universal app, generates the icon, **embeds + signs Sparkle.framework**, code-signs. Honors `CODESIGN_IDENTITY`, `DOCKLY_SUFFIX`, `DOCKLY_DEFINES`. |
| `make-dmg.sh` | Builds the app, then a styled drag-to-Applications DMG. |
| `release.sh` | Bumps the version, builds, zips (`ditto`), and runs Sparkle's `generate_appcast` (signs with the private key in the login Keychain). |

## One-time setup for a NEW app

1. **Add Sparkle** to `Package.swift`:
   ```swift
   dependencies: [ .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0") ],
   // target deps: .product(name: "Sparkle", package: "Sparkle")
   ```
2. **Generate signing keys** (once per app, or reuse one):
   ```bash
   .build/artifacts/sparkle/Sparkle/bin/generate_keys
   ```
   It stores the **private key in the login Keychain** and prints the public key.
3. **Add to `Info.plist`:**
   - `SUFeedURL` → `https://github.com/<user>/<repo>/releases/latest/download/appcast.xml`
   - `SUPublicEDKey` → the printed public key
   - `SUEnableAutomaticChecks` = true, `SUScheduledCheckInterval` = 86400
4. **Embed Sparkle.framework** into the `.app` (build-app.sh does this: copy the
   xcframework's `macos-arm64_x86_64/Sparkle.framework` into `Contents/Frameworks`,
   add `@executable_path/../Frameworks` rpath, sign inner XPC helpers first).
5. **Create the repo + first release** (see TL;DR).

## Universal + Ventura (macOS 13) compatibility

- Always build **universal**: `swift build -c release --arch arm64 --arch x86_64`.
  A Mac stuck on Ventura is usually **Intel** — an arm64-only build shows
  "not supported on this Mac" (that's the *arch* message, not the OS one).
- macOS-14.4-only APIs (e.g. Core Audio process taps / `CATapDescription`) get
  STRONG-linked even under `#available`, which makes dyld refuse to launch on 13.
  Fix: **weak-link the framework** in `Package.swift`:
  ```swift
  linkerSettings: [ .unsafeFlags(["-Xlinker","-weak_framework","-Xlinker","CoreAudio"]) ]
  ```
  Verify: `nm -m <binary> | grep <Symbol>` should show **weak external**.
  Keep the actual calls behind `#available(macOS 14.4, *)`.

## Signing & notarization

- **Ad-hoc** (`codesign -s -`, the default) works but: (a) Gatekeeper needs a
  one-time right-click → Open, and (b) **TCC re-prompts for permissions on every
  launch** because there's no stable identity.
- **Stable identity = no re-prompts.** Build with a real cert:
  ```bash
  CODESIGN_IDENTITY="Developer ID Application: <Name> (TEAMID)" ./release.sh <v> <user>
  ```
- **Notarize** (zero Gatekeeper friction, needs the paid Apple Developer Program —
  NOT App Store): set `NOTARY_PROFILE=<notarytool-keychain-profile>` before
  `release.sh`; it submits + staples.

## Gotchas / lessons learned

- **Replace the `SUFeedURL` placeholder** (`YOUR_GITHUB_USER`) with the real
  username before the first build, or update checks 404.
- **Private repo ⇒ broken updates.** Release assets on a private repo aren't
  publicly reachable; the appcast/zip must be public. Use a public repo (or a
  public releases mirror / Cloudflare).
- **Never commit the private key** (it lives in the Keychain). `.gitignore`
  excludes `.build/`, `dist/`, keys.
- **The running app caches the feed URL at launch** — after changing it, relaunch
  the freshly-built copy or you'll test a stale URL.
- TCC usage-description keys are mandatory or the app **hard-crashes** (SIGABRT)
  on first use: `NSAppleEventsUsageDescription`, `NSBluetoothAlwaysUsageDescription`,
  `NSAudioCaptureUsageDescription`, `NSCalendarsUsageDescription`.
