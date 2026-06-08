import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Wrapper for any tab whose content should live below the notch line.
struct BelowNotchContent<Content: View>: View {
    @Environment(\.notchGeometry) var notch
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.notchH + notch.belowNotch)
            content()
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Live tab — wraps the existing music / clock / event live content

struct LiveTabView: View {
    @ObservedObject var activities: ActivityManager
    @Binding var now: Date

    var body: some View {
        Group {
            switch activities.current {
            case .clock:
                BelowNotchContent { clockView }
            case let .music(title, artist, isPlaying, bundleId, artwork):
                MusicTabView(title: title, artist: artist, isPlaying: isPlaying,
                             bundleId: bundleId, artwork: artwork, activities: activities)
            case let .upcomingEvent(title, color, minutes, timeStr):
                BelowNotchContent { eventView(title: title, color: color,
                                              minutes: minutes, timeStr: timeStr) }
            case let .battery(event, percent):
                BelowNotchContent { batteryView(event: event, percent: percent) }
            case let .volume(percent, muted):
                BelowNotchContent { volumeView(percent: percent, muted: muted) }
            case let .bluetooth(name, connected, icon):
                BelowNotchContent { bluetoothView(name: name, connected: connected, icon: icon) }
            case let .focus(on):
                BelowNotchContent { focusView(on: on) }
            case .timer:
                BelowNotchContent { TimerRunningView() }
            }
        }
    }

    private func focusView(on: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: on ? "moon.fill" : "moon")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(on ? Color.purple : .white.opacity(0.6))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(on ? "Focus On" : "Focus Off")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(on ? "Notifications silenced" : "Notifications resumed")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func volumeView(percent: Int, muted: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: muted ? "speaker.slash.fill"
                  : percent == 0 ? "speaker.fill"
                  : percent < 40 ? "speaker.wave.1.fill"
                  : percent < 75 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(muted ? .red : .white)
                .frame(width: 30)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2)).frame(height: 6)
                    Capsule().fill(muted ? Color.red : .white)
                        .frame(width: geo.size.width * CGFloat(muted ? 0 : percent) / 100, height: 6)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 14)
            Text("\(muted ? 0 : percent)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 26, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bluetoothView(name: String, connected: Bool, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(connected ? .blue : .white.opacity(0.6))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(connected ? "Connected" : "Disconnected")
                    .font(.system(size: 11))
                    .foregroundStyle(connected ? .blue.opacity(0.9) : .white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func batteryView(event: BatteryMonitor.BatteryEvent, percent: Int) -> some View {
        let (glyph, color, title): (String, Color, String) = {
            switch event {
            case .pluggedIn: return ("battery.100.bolt", .green, "Charging")
            case .unplugged: return ("battery.50", .white, "On Battery")
            case .full:      return ("battery.100.bolt", .green, "Fully Charged")
            case .low:       return ("battery.25", .red, "Low Battery")
            }
        }()
        return HStack(spacing: 14) {
            Image(systemName: glyph)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(percent)%")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var clockView: some View {
        // Horizontal time + date column. Stacked numerals live in the
        // compact wing — here we have room to breathe.
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(DocklyClock.hourMinute.string(from: now))
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(width: 1, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(now, format: .dateTime.weekday(.wide))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(now, format: .dateTime.month(.wide).day())
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func eventView(title: String, color: CGColor, minutes: Int, timeStr: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Up next")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .textCase(.uppercase)
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(cgColor: color))
                    .frame(width: 4)
                    .padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(minutes <= 0 ? "Starting now"
                         : minutes == 1 ? "In 1 minute · \(timeStr)"
                         : "In \(minutes) minutes · \(timeStr)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(cgColor: color).opacity(0.9))
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Music inside the Live tab

struct MusicTabView: View {
    let title: String
    let artist: String
    let isPlaying: Bool
    let bundleId: String?
    let artwork: Data?
    @ObservedObject var activities: ActivityManager
    @Environment(\.notchGeometry) var notch

    var body: some View {
        let (c1, c2) = MusicApp.accentColor(forBundle: bundleId)
        // Skip the notch row, then lay everything out vcentered in the
        // remaining below-notch space. Art on left, title in middle,
        // controls on right — all vertically centered.
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.notchH + notch.belowNotch)

            ZStack {
                // Centered title + artist, capped so it never bleeds into the controls
                VStack(spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(isPlaying ? 1.0 : 0.65))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(isPlaying ? 0.55 : 0.40))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: notch.panelW * 0.45)

                // Left: album art / thumbnail, vcentered. Click → focus source app.
                HStack {
                    artHolder(c1: c1, c2: c2)
                        .padding(.leading, 10)
                        .onTapGesture { activateSourceApp() }
                        .help("Open \(appName)")
                    Spacer(minLength: 0)
                }

                // Right: controls, vcentered
                HStack {
                    Spacer(minLength: 0)
                    HStack(spacing: 2) {
                        circleButton("backward.fill", size: 11, padding: 6) { activities.previousTrack() }
                        circleButton(isPlaying ? "pause.fill" : "play.fill",
                                     size: 14, padding: 8, accent: true) { activities.playPause() }
                        circleButton("forward.fill", size: 11, padding: 6) { activities.nextTrack() }
                    }
                    .padding(.trailing, 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Scrubber along the bottom — tinted to the album accent.
            if let progress = activities.playback {
                ScrubberView(progress: progress, accent: activities.accent) { activities.seek(to: $0) }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appName: String {
        guard let id = bundleId,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        else { return "app" }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func activateSourceApp() {
        guard let id = bundleId,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg)
    }

    @ViewBuilder
    private func artHolder(c1: Color, c2: Color) -> some View {
        let size: CGFloat = 44
        ZStack {
            if let artwork, let nsImage = NSImage(data: artwork) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [c1, c2],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size, height: size)
                if let icon = MusicApp.icon(forBundle: bundleId) {
                    Image(nsImage: icon).resizable().interpolation(.high)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(systemName: activities.mediaIsVideo ? "play.rectangle.fill" : "music.note")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        // Soft outline + ambient glow give the art a sense of depth
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: c1.opacity(isPlaying ? 0.45 : 0.12), radius: 8, x: 0, y: 2)
    }

    private func circleButton(_ symbol: String, size: CGFloat, padding: CGFloat,
                              accent: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size + padding * 2, height: size + padding * 2)
                .background(Circle().fill(.white.opacity(accent ? 0.22 : 0.08)))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Scrubber

private struct ScrubberView: View {
    let progress: PlaybackProgress
    let accent: Color
    let onSeek: (Double) -> Void

    @State private var dragging = false
    @State private var dragFraction: Double = 0

    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var now = Date()

    var body: some View {
        let elapsed = dragging ? dragFraction * progress.duration : progress.current(at: now)
        let frac = progress.duration > 0 ? min(1, max(0, elapsed / progress.duration)) : 0

        VStack(spacing: 3) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18)).frame(height: 4)
                    Capsule().fill(accent).frame(width: w * frac, height: 4)
                    Circle()
                        .fill(.white)
                        .frame(width: dragging ? 10 : 7, height: dragging ? 10 : 7)
                        .offset(x: w * frac - (dragging ? 5 : 3.5))
                        .shadow(color: .black.opacity(0.3), radius: 2)
                }
                .frame(height: 12)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            dragging = true
                            dragFraction = min(1, max(0, v.location.x / w))
                        }
                        .onEnded { _ in
                            onSeek(dragFraction * progress.duration)
                            dragging = false
                        }
                )
            }
            .frame(height: 12)

            HStack {
                Text(timeString(elapsed))
                Spacer()
                Text(timeString(progress.duration))
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.45))
        }
        .onReceive(tick) { now = $0 }
    }

    private func timeString(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Tray tab

struct TrayTabView: View {
    @ObservedObject var store: TrayStore = .shared
    @State private var isTargeted: Bool = false

    var body: some View {
        BelowNotchContent { trayBody }
    }

    private var trayBody: some View {
        VStack(spacing: 8) {
            HStack {
                Text("File Tray")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .textCase(.uppercase)
                Spacer()
                if !store.items.isEmpty {
                    Button(action: { store.clear() }) {
                        Text("Clear")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            ZStack {
                if store.items.isEmpty {
                    emptyState
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(store.items) { item in
                                TrayItemTile(item: item, onRemove: { store.remove(item) })
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(isTargeted ? 0.12 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(isTargeted ? 0.5 : 0.12),
                                          style: StrokeStyle(lineWidth: 1, dash: isTargeted ? [] : [4, 4]))
                    )
            )
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.35))
            Text("Drop files here")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var any = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            any = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let u = item as? URL { url = u }
                else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else { url = nil }
                guard let url else { return }
                DispatchQueue.main.async { store.add(url: url) }
            }
        }
        return any
    }
}

private struct TrayItemTile: View {
    let item: TrayItem
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: item.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)

                if hovering {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white, .black.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                }
            }
            Text(item.originalName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 64)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(hovering ? 0.08 : 0.0))
        )
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Reveal in Finder") { TrayStore.shared.revealInFinder(item) }
            Button("Share via AirDrop") { TrayStore.shared.airdrop(item) }
            Divider()
            Button("Remove", role: .destructive) { onRemove() }
        }
        .onDrag {
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
    }
}

// MARK: - Calendar tab (removed — kept private as the upcoming-event live
// activity still uses CalendarListStore via ActivityManager)

private struct CalendarTabView_Removed: View {
    @ObservedObject var store: CalendarListStore = .shared

    var body: some View {
        BelowNotchContent { calendarBody }
    }

    private var calendarBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .textCase(.uppercase)
                Spacer()
                Text(Date(), format: .dateTime.weekday(.abbreviated).month().day())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            if !store.authorized {
                permissionView
            } else if store.events.isEmpty {
                emptyView
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.events) { ev in
                            EventRow(event: ev)
                        }
                    }
                }
            }
        }
        .onAppear { store.refresh() }
    }

    private var emptyView: some View {
        VStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.3))
            Text("Nothing on the books")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionView: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.4))
            Text("Calendar access not granted")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
            Button("Request access") { store.requestAccess() }
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EventRow: View {
    let event: DayEvent

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: event.color))
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(event.startString)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(nsColor: event.color).opacity(0.95))
                    if let loc = event.location {
                        Text("· \(loc)")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Tasks tab (Life Dashboard)

struct TasksTabView: View {
    @ObservedObject var store: LifeDashboardStore = .shared

    var body: some View {
        BelowNotchContent { tasksBody }
            .onAppear { store.start(); store.refresh() }
    }

    private var tasksBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tasks")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .textCase(.uppercase)
                Spacer()
                Circle()
                    .fill(store.online ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Button(action: { store.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            if !store.online {
                offline
            } else {
                let pending = store.tasks.filter { !$0.done }
                if pending.isEmpty {
                    centered("checkmark.circle", "All clear — no open tasks")
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(pending) { task in
                                TaskRow(task: task)
                            }
                        }
                    }
                }
            }
        }
    }

    private var offline: some View {
        VStack(spacing: 5) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.3))
            Text("Life Dashboard offline")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            Text("Run `npm start` in your life-dashboard folder")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func centered(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(.white.opacity(0.3))
            Text(text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TaskRow: View {
    let task: LDTask
    @State private var hovering = false
    @State private var done = false

    private func complete() {
        guard !done else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { done = true }
        // Let the check + fade play, then remove from the list.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            LifeDashboardStore.shared.complete(task)
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            Button(action: complete) {
                Image(systemName: (done || hovering) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle((done || hovering) ? Color.green : .white.opacity(0.45))
                    .scaleEffect(done ? 1.25 : 1.0)
            }
            .buttonStyle(PressableStyle())
            .help("Mark complete")

            Text(task.text)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .strikethrough(done, color: .white.opacity(0.5))
                .lineLimit(1)
            Spacer(minLength: 0)
            if let due = task.dueDate {
                Text(Self.prettyDue(due))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .contentShape(Rectangle())
        .opacity(done ? 0.4 : 1.0)
        .onHover { hovering = $0 }
    }

    private static func prettyDue(_ iso: String) -> String {
        // iso may be YYYY-MM-DD or YYYY-MM-DDTHH:MM
        let datePart = String(iso.prefix(10))
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: datePart) else { return iso }
        let out = DateFormatter(); out.dateFormat = "MMM d"
        return out.string(from: d)
    }
}

// MARK: - Timer tab

struct TimerTabView: View {
    @ObservedObject var timer = TimerManager.shared

    private let presets: [(String, TimeInterval)] = [
        ("1m", 60), ("3m", 180), ("5m", 300), ("10m", 600), ("25m", 1500), ("1h", 3600)
    ]

    var body: some View {
        BelowNotchContent {
            if timer.isActive { TimerRunningView() } else { presetGrid }
        }
    }

    private var presetGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Start a Timer")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .textCase(.uppercase)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6),
                                GridItem(.flexible(), spacing: 6),
                                GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(presets, id: \.0) { p in
                    Button(action: { timer.start(p.1) }) {
                        Text(p.0)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(.white.opacity(0.08)))
                    }
                    .buttonStyle(PressableStyle(scale: 0.92))
                }
            }
        }
    }
}

// Shared running-timer UI (used in the Timer tab and the Live activity tab).
struct TimerRunningView: View {
    @ObservedObject var timer = TimerManager.shared

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(timer.state == .finished ? Color.orange : Color.accentColor,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(timer.state == .finished ? "0:00" : TimerManager.format(timer.remaining))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)

            VStack(spacing: 8) {
                if timer.state == .finished {
                    Text("Time's up!")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    circle("plus", "+1m") { timer.addMinute() }
                    if timer.state != .finished {
                        circle(timer.state == .paused ? "play.fill" : "pause.fill",
                               timer.state == .paused ? "Resume" : "Pause", accent: true) {
                            timer.togglePause()
                        }
                    }
                    circle("xmark", "Stop") { timer.cancel() }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func circle(_ icon: String, _ help: String, accent: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(accent ? 0.2 : 0.08)))
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }
}

// MARK: - Notes tab

struct NotesTabView: View {
    @ObservedObject var store: NotesStore = .shared

    var body: some View {
        BelowNotchContent { notesBody }
    }

    private var notesBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Notes")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .textCase(.uppercase)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.05))

                if store.text.isEmpty {
                    Text("Jot something down…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.25))
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $store.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Shortcuts tab

struct ShortcutsTabView: View {
    @ObservedObject var store: ShortcutsStore = .shared
    @ObservedObject var settings: AppSettings = .shared

    var body: some View {
        BelowNotchContent { shortcutsBody }
    }

    private var shortcutsBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Shortcuts")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .textCase(.uppercase)
                Spacer()
                // Layout toggle: grid <-> list
                Button(action: {
                    settings.shortcutsLayout = settings.shortcutsLayout == .grid ? .list : .grid
                }) {
                    Image(systemName: settings.shortcutsLayout.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Toggle grid / list")

                Button(action: { store.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            if !store.available {
                centeredMessage("shortcuts.app", "Shortcuts CLI unavailable")
            } else if store.loading && store.shortcuts.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.shortcuts.isEmpty {
                centeredMessage("bolt.slash", "No shortcuts found")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    if settings.shortcutsLayout == .grid {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6),
                                            GridItem(.flexible(), spacing: 6)],
                                  spacing: 6) {
                            ForEach(store.shortcuts, id: \.self) { name in
                                ShortcutChip(name: name, layout: .grid,
                                             running: store.running.contains(name),
                                             action: { store.runShortcut(name) })
                            }
                        }
                    } else {
                        LazyVStack(spacing: 4) {
                            ForEach(store.shortcuts, id: \.self) { name in
                                ShortcutChip(name: name, layout: .list,
                                             running: store.running.contains(name),
                                             action: { store.runShortcut(name) })
                            }
                        }
                    }
                }
            }
        }
        .onAppear { if store.shortcuts.isEmpty { store.refresh() } }
    }

    private func centeredMessage(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.3))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Derives a stable color + glyph per shortcut name (macOS doesn't expose the
// real Shortcuts icon via CLI, so we synthesize a consistent identity).
enum ShortcutVisual {
    static func color(for name: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.95, green: 0.35, blue: 0.40),  // red
            Color(red: 0.98, green: 0.58, blue: 0.20),  // orange
            Color(red: 0.95, green: 0.78, blue: 0.25),  // yellow
            Color(red: 0.35, green: 0.78, blue: 0.45),  // green
            Color(red: 0.30, green: 0.68, blue: 0.95),  // blue
            Color(red: 0.55, green: 0.45, blue: 0.92),  // indigo
            Color(red: 0.78, green: 0.42, blue: 0.88),  // purple
            Color(red: 0.95, green: 0.45, blue: 0.70),  // pink
            Color(red: 0.40, green: 0.75, blue: 0.78),  // teal
        ]
        var hash = 5381
        for byte in name.utf8 { hash = ((hash << 5) &+ hash) &+ Int(byte) }
        return palette[abs(hash) % palette.count]
    }

    static func glyph(for name: String) -> String {
        let n = name.lowercased()
        let map: [(String, String)] = [
            ("timer", "timer"), ("alarm", "alarm.fill"), ("water", "drop.fill"),
            ("home", "house.fill"), ("light", "lightbulb.fill"), ("music", "music.note"),
            ("play", "play.fill"), ("call", "phone.fill"), ("text", "message.fill"),
            ("message", "message.fill"), ("email", "envelope.fill"), ("mail", "envelope.fill"),
            ("photo", "photo.fill"), ("camera", "camera.fill"), ("note", "note.text"),
            ("weather", "cloud.sun.fill"), ("map", "map.fill"), ("direction", "location.fill"),
            ("battery", "battery.100"), ("wifi", "wifi"), ("focus", "moon.fill"),
            ("sleep", "bed.double.fill"), ("work", "briefcase.fill"), ("calendar", "calendar"),
            ("reminder", "checklist"), ("todo", "checklist"), ("coffee", "cup.and.saucer.fill"),
            ("translate", "character.bubble"), ("calc", "function"), ("convert", "arrow.left.arrow.right"),
            ("screenshot", "camera.viewfinder"), ("record", "record.circle"), ("car", "car.fill"),
            ("workout", "figure.run"), ("run", "figure.run"), ("podcast", "mic.fill"),
            ("news", "newspaper.fill"), ("shop", "cart.fill"), ("pay", "creditcard.fill"),
        ]
        for (key, glyph) in map where n.contains(key) { return glyph }
        return "bolt.fill"
    }
}

private struct ShortcutChip: View {
    let name: String
    let layout: ShortcutsLayout
    let running: Bool
    let action: () -> Void

    @State private var hovering = false

    private var color: Color { ShortcutVisual.color(for: name) }
    private var glyph: String { ShortcutVisual.glyph(for: name) }

    var body: some View {
        Button(action: action) {
            Group {
                if layout == .grid { gridContent } else { listContent }
            }
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.white.opacity(hovering ? 0.13 : 0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(name)
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(LinearGradient(colors: [color, color.opacity(0.7)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                if running {
                    ProgressView().controlSize(.small).scaleEffect(0.65)
                } else {
                    Image(systemName: glyph)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
    }

    private var gridContent: some View {
        HStack(spacing: 7) {
            iconTile.frame(width: 26, height: 26)
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }

    private var listContent: some View {
        HStack(spacing: 9) {
            iconTile.frame(width: 24, height: 24)
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Image(systemName: "play.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 0.6 : 0.25))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
    }
}
