import SwiftUI
import AppKit

// Shared time formatters — "h" never adds a leading zero, "mm" always shows two digits.
enum DocklyClock {
    static let hourMinute: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm"; return f
    }()
    static let hourOnly: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h"; return f
    }()
    static let minuteOnly: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "mm"; return f
    }()
}

// Springy press feedback for any control — scales down on press, bounces back.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.86
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

struct NotchGeometry: Equatable {
    let notchH: CGFloat
    let notchW: CGFloat
    let belowNotch: CGFloat
    let panelW: CGFloat
}

private struct NotchGeometryKey: EnvironmentKey {
    static let defaultValue = NotchGeometry(notchH: 32, notchW: 220, belowNotch: 2, panelW: 440)
}

extension EnvironmentValues {
    var notchGeometry: NotchGeometry {
        get { self[NotchGeometryKey.self] }
        set { self[NotchGeometryKey.self] = newValue }
    }
}

struct DocklyPanelView: View {
    @ObservedObject var controller: NotchWindowController
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject private var activities = ActivityManager.shared
    @ObservedObject private var reactor = AudioReactor.shared
    @State private var now = Date()
    @Namespace private var tabSelectionNS
    @State private var popScale: CGFloat = 1.0   // quick bounce when activity changes
    @State private var breathe = false           // subtle idle pulse
    @State private var fastPulse = false         // alarm pulse when a timer finishes

    private let clockTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var screen: NSScreen { NSScreen.main ?? NSScreen.screens.first! }
    private var notchH: CGFloat { controller.notchHeight(screen: screen) }
    private var notchW: CGFloat { controller.notchWidth(screen: screen) }
    private var deadZoneHeight: CGFloat { notchH + controller.belowNotch }

    private var visibleTabs: [DocklyTab] {
        DocklyTab.allCases.filter { settings.enabledTabs.contains($0) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            if controller.isExpanded {
                expandedPanel
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.94, anchor: .top))
                                .combined(with: .offset(y: -6))
                                .animation(.spring(response: 0.34, dampingFraction: 0.78).delay(0.08)),
                            removal: .opacity.animation(.easeOut(duration: 0.10))
                        )
                    )
            } else {
                compactOrPeek
                    .transition(
                        .asymmetric(
                            insertion: .opacity.animation(.easeInOut(duration: 0.18).delay(0.06)),
                            removal:   .opacity.animation(.easeOut(duration: 0.12))
                        )
                    )
            }

            if settings.showNotchDebugOverlay {
                notchDebugOverlay
            }
        }
        // Inset by the shadow margin (sides + bottom) and the concave flare
        // (sides) so content lives in the visible pill body.
        .padding(.top, 0)
        .padding(.leading, controller.shadowMargin + controller.concaveTop)
        .padding(.trailing, controller.shadowMargin + controller.concaveTop)
        .padding(.bottom, controller.shadowMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .colorScheme(.dark)
        .onReceive(clockTick) { now = $0 }
        .onAppear {
            activities.start()
            syncCompactExtension(for: activities.current)
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                fastPulse = true
            }
        }
        .onChange(of: activities.current) { new in
            syncCompactExtension(for: new)
            // Exit peek if music ends
            if case .music = new {} else {
                if controller.isPeeking { controller.peek(false) }
            }
            // Gentle bounce when the activity changes — but NOT for the frequent
            // info pops (volume/battery/etc.), which looked jittery, especially
            // while scrubbing volume.
            if shouldBounce(for: new) {
                popScale = 1.06
                withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { popScale = 1.0 }
            }
        }
        .onChange(of: settings.activeTab) { _ in
            controller.handleActiveTabChange()
        }
        .onChange(of: settings.compactWingWidth) { _ in
            syncCompactExtension(for: activities.current)
        }
    }

    // Bounce only for meaningful changes — skip the rapid info pops.
    private func shouldBounce(for activity: LiveActivity) -> Bool {
        switch activity {
        case .volume, .battery, .bluetooth, .focus: return false
        default: return true
        }
    }

    private func handleCompactTap() {
        // Peek is a hover preview; clicking always opens the full panel.
        guard !controller.isExpanded else { return }
        // Jump straight to the Live tab so you see the detail of whatever the
        // wing was showing (now-playing, battery, etc.) — if it's enabled.
        if settings.enabledTabs.contains(.live) {
            settings.activeTab = .live
        }
        controller.expand(true)
    }

    private func syncCompactExtension(for activity: LiveActivity) {
        // Always show wings so the user gets info without expanding.
        // Width is computed by the controller from activity + settings.
        controller.setCompactExtension(controller.compactExtensionTarget())
    }

    // MARK: - Compact + optional peek drop-down
    // ZStack with absolute offsets so the wings are NEVER affected by the
    // peek text layout. Wings sit at a fixed 32pt at the top; the peek text
    // is offset below them and only revealed by the NSPanel growing.

    private var compactOrPeek: some View {
        ZStack(alignment: .top) {
            compactWings
                .frame(height: notchH)

            peekTextSlot
                .padding(.horizontal, 14)
                .frame(height: controller.peekContentH)
                .frame(maxWidth: .infinity, alignment: .top)
                .offset(y: notchH + controller.belowNotch)
                .opacity(controller.isPeeking ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { handleCompactTap() }
    }

    // Debug overlay — draws where Dockly thinks the notch hardware sits, plus
    // its measured dimensions, so the width/height nudges can be aligned.
    private var notchDebugOverlay: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .strokeBorder(Color.red.opacity(0.9), lineWidth: 1)
                .frame(width: notchW, height: notchH)
                .overlay(alignment: .bottom) {
                    Text("\(Int(notchW))×\(Int(notchH))")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 3)
                        .background(.black.opacity(0.6))
                        .offset(y: 12)
                }
            // Center crosshair line
            Rectangle()
                .fill(Color.green.opacity(0.6))
                .frame(width: 1, height: notchH + 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var peekTextSlot: some View {
        if case let .music(title, artist, _, _, _) = activities.current {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(artist)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            Color.clear
        }
    }

    private var compactWings: some View {
        HStack(spacing: 0) {
            leftWing
                .frame(width: controller.compactExtension)
                .opacity(controller.compactExtension > 10 ? 1 : 0)
                .scaleEffect(controller.isCursorNearby ? 1.08 : 1.0)

            Color.clear.frame(width: notchW)

            rightWing
                .frame(width: controller.compactExtension)
                .opacity(controller.compactExtension > 10 ? 1 : 0)
                .scaleEffect(controller.isCursorNearby ? 1.08 : 1.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scaleEffect(popScale * idleBreathScale * timerPulseScale * beatBounceScale)
        // Subtle 3D tilt + shift toward the cursor (parallax).
        .rotation3DEffect(.degrees(Double(controller.cursorParallax) * 7),
                          axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .offset(x: controller.cursorParallax * 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: controller.isCursorNearby)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: controller.cursorParallax)
        .animation(.easeOut(duration: 0.09), value: reactor.bass)
    }

    private var isIdleClock: Bool {
        if case .clock = activities.current { return true }
        return false
    }
    // Gentle pulse only when idle; otherwise rock-steady.
    private var idleBreathScale: CGFloat {
        guard isIdleClock, !controller.isCursorNearby else { return 1.0 }
        return breathe ? 1.03 : 0.99
    }
    // Strong alarm pulse while a finished timer is showing.
    private var timerPulseScale: CGFloat {
        if case .timer(.finished) = activities.current { return fastPulse ? 1.12 : 0.94 }
        return 1.0
    }
    // Pill bounces on the bass when DJ beat-bounce is enabled.
    private var beatBounceScale: CGFloat {
        guard settings.audioReactive, settings.djBeatBounce, reactor.running else { return 1.0 }
        return 1.0 + min(0.14, CGFloat(reactor.bass) * CGFloat(settings.djSensitivity) * 0.16)
    }

    private func peekText(title: String, artist: String) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(artist)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var leftWing: some View {
        switch activities.current {
        case .clock:
            Image(systemName: "clock.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
        case let .music(_, _, isPlaying, bundleId, artwork):
            AppIconBadge(bundleId: bundleId, artwork: artwork)
                .opacity(isPlaying ? 1.0 : 0.55)
        case let .upcomingEvent(_, color, _, _):
            Circle()
                .fill(Color(cgColor: color))
                .frame(width: 7, height: 7)
        case let .battery(event, percent):
            Image(systemName: batteryGlyph(event: event, percent: percent))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(batteryColor(event))
        case let .volume(_, muted):
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
        case let .bluetooth(_, connected, icon):
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(connected ? .blue : .white.opacity(0.5))
        case let .focus(on):
            Image(systemName: on ? "moon.fill" : "moon")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(on ? Color.purple : .white.opacity(0.6))
        case let .timer(state):
            Image(systemName: state == .finished ? "timer.circle.fill"
                  : state == .paused ? "pause.circle" : "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(state == .finished ? Color.orange : .white)
        }
    }

    private func batteryGlyph(event: BatteryMonitor.BatteryEvent, percent: Int) -> String {
        switch event {
        case .pluggedIn, .full: return "battery.100.bolt"
        case .unplugged:        return "battery.50"
        case .low:              return "battery.25"
        }
    }

    private func batteryColor(_ event: BatteryMonitor.BatteryEvent) -> Color {
        switch event {
        case .pluggedIn, .full: return .green
        case .unplugged:        return .white
        case .low:              return .red
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        switch activities.current {
        case .clock:
            // Stacked time — hour above minute, very compact for the wing
            VStack(spacing: -2) {
                Text(DocklyClock.hourOnly.string(from: now))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(DocklyClock.minuteOnly.string(from: now))
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .monospacedDigit()
        case let .music(_, _, isPlaying, _, _):
            AudioBarsView(playing: isPlaying)
        case let .upcomingEvent(_, _, minutes, _):
            Text(minutes <= 0 ? "Now" : "\(minutes)m")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        case let .battery(_, percent):
            Text("\(percent)%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        case let .volume(percent, muted):
            // Tiny volume bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(muted ? Color.red : .white)
                        .frame(width: geo.size.width * CGFloat(muted ? 0 : percent) / 100)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 4)
        case let .bluetooth(_, connected, _):
            Image(systemName: connected ? "checkmark" : "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(connected ? .blue : .white.opacity(0.6))
        case let .focus(on):
            Text(on ? "On" : "Off")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        case let .timer(state):
            TimerCountdownLabel(finished: state == .finished)
        }
    }

    // MARK: - Expanded panel
    // Tabs render edge-to-edge so they can drop content into the wing areas
    // (sides of the notch hardware) as well as below the notch.

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            tabBar
        }
        .environment(\.notchGeometry, NotchGeometry(
            notchH: notchH,
            notchW: notchW,
            belowNotch: controller.belowNotch,
            panelW: controller.expandedW
        ))
    }

    @ViewBuilder
    private var tabContent: some View {
        Group {
            switch settings.activeTab {
            case .live:
                LiveTabView(activities: activities, now: $now)
            case .tray:
                TrayTabView()
            case .tasks:
                TasksTabView()
            case .timer:
                TimerTabView()
            case .notes:
                NotesTabView()
            case .shortcuts:
                ShortcutsTabView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.18), value: settings.activeTab)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(visibleTabs) { tab in
                TabBarButton(
                    tab: tab,
                    active: settings.activeTab == tab,
                    accent: activities.accentColor.map { Color(nsColor: $0) },
                    namespace: tabSelectionNS,
                    action: {
                        Sounds.tab()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            settings.activeTab = tab
                        }
                    }
                )
            }

            // Settings gear — always present, separated from the tabs
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1, height: 16)
                .padding(.horizontal, 2)
            SettingsGearButton {
                NotificationCenter.default.post(name: .docklyOpenSettings, object: nil)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Rectangle()
                .fill(.white.opacity(0.04))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                        .frame(height: 0.5)
                }
        )
    }
}

private struct SettingsGearButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if hovering {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white.opacity(0.06))
                }
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(hovering ? 0.85 : 0.5))
            }
            .frame(width: 30, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Dockly Settings")
    }
}

extension Notification.Name {
    static let docklyOpenSettings = Notification.Name("docklyOpenSettings")
}

// MARK: - Tab bar button

private struct TabBarButton: View {
    let tab: DocklyTab
    let active: Bool
    var accent: Color? = nil
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Active indicator slides between tabs via matchedGeometryEffect
                if active {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill((accent ?? .white).opacity(accent == nil ? 0.13 : 0.30))
                        .matchedGeometryEffect(id: "tabIndicator", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white.opacity(0.06))
                }

                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(active ? .white : .white.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - App Icon Badge (compact, left wing)

struct AppIconBadge: View {
    let bundleId: String?
    let artwork: Data?

    var body: some View {
        ZStack {
            // Prefer the actual album art / video thumbnail when we have it
            if let artwork, let img = NSImage(data: artwork) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else if let icon = MusicApp.icon(forBundle: bundleId) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Audio Bars (compact, right wing)

// Live countdown text that observes TimerManager so it ticks in the wing.
struct TimerCountdownLabel: View {
    var finished: Bool
    @ObservedObject private var timer = TimerManager.shared

    var body: some View {
        Text(finished ? "Done" : TimerManager.format(timer.remaining))
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(finished ? Color.orange : .white)
    }
}

struct AudioBarsView: View {
    var playing: Bool
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Group {
            if playing {
                if settings.audioReactive {
                    ReactiveBars()
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        HStack(alignment: .center, spacing: 2.5) {
                            bar(at: t, phase: 0.0)
                            bar(at: t, phase: 1.1)
                            bar(at: t, phase: 2.3)
                        }
                    }
                }
            } else {
                HStack(spacing: 2.5) {
                    Capsule().fill(.white.opacity(0.55)).frame(width: 2.5, height: 9)
                    Capsule().fill(.white.opacity(0.55)).frame(width: 2.5, height: 9)
                }
            }
        }
    }

    private func bar(at t: TimeInterval, phase: Double) -> some View {
        let h = 4.0 + abs(sin(t * 4.2 + phase) + sin(t * 7.3 + phase * 0.7)) * 4.5
        return Capsule()
            .fill(.white)
            .frame(width: 2.5, height: h)
    }
}

// Three bars driven by live bass / mid / treble energy.
private struct ReactiveBars: View {
    @ObservedObject private var reactor = AudioReactor.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            barFor(reactor.bass)
            barFor(reactor.mid)
            barFor(reactor.treble)
        }
        .animation(.easeOut(duration: 0.08), value: reactor.bass)
        .animation(.easeOut(duration: 0.08), value: reactor.mid)
        .animation(.easeOut(duration: 0.08), value: reactor.treble)
    }

    private func barFor(_ v: Float) -> some View {
        let scaled = min(1, CGFloat(v) * CGFloat(settings.djSensitivity))
        return Capsule().fill(.white)
            .frame(width: 2.5, height: 3 + scaled * 11)
    }
}
