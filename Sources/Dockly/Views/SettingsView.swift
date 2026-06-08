import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    // DJ mode relies on Core Audio process taps (macOS 14.4+).
    private var djModeSupported: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            appearanceTab.tabItem { Label("Appearance", systemImage: "paintbrush") }
            musicTab.tabItem { Label("Music", systemImage: "music.note") }
            tabsTab.tabItem { Label("Tabs", systemImage: "square.grid.2x2") }
            integrationsTab.tabItem { Label("Integrations", systemImage: "link") }
            sizeTab.tabItem { Label("Size", systemImage: "ruler") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 560)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch Dockly at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        launchAtLogin = on
                        if !LaunchAtLogin.set(on) { launchAtLogin = LaunchAtLogin.isEnabled }
                    }
                ))
                .disabled(!LaunchAtLogin.isAvailable)
                Toggle("Global hotkey to toggle (⌥⌘D)", isOn: $settings.hotkeyEnabled)
                Toggle("Sound effects", isOn: $settings.soundEffects)
            } footer: {
                if !LaunchAtLogin.isAvailable {
                    Text("Launch at login works once Dockly is in /Applications.")
                }
            }

            Section {
                Picker("Open the panel on", selection: $settings.expandTrigger) {
                    ForEach(AppSettings.ExpandTrigger.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                slider("Stay open for", $settings.autoCollapseDelay,
                       0.1...15.0, step: 0.1, fmt: "%.1f", unit: "s")
            } header: {
                Text("Opening")
            } footer: {
                Text("“Hover” opens when your cursor approaches the notch; “Click” waits for a click. After your cursor leaves, it stays open for the time above.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        Form {
            Section {
                Toggle("Adapt border to album art", isOn: $settings.adaptiveAccent)
            } header: {
                Text("Album color")
            } footer: {
                Text("The border glows in the colors of whatever's playing, overriding the colors below while music is on.")
            }

            Section("Border") {
                Picker("Style", selection: $settings.pillEdgeStyle) {
                    ForEach(PillEdgeStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if settings.pillEdgeStyle != .off {
                    ColorPicker("Color", selection: edgeColor1Binding, supportsOpacity: true)
                    if settings.pillEdgeStyle == .gradient {
                        ColorPicker("Gradient end", selection: edgeColor2Binding, supportsOpacity: true)
                        Picker("Direction", selection: $settings.pillEdgeDirection) {
                            ForEach(PillEdgeDirection.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Picker("Animation", selection: $settings.pillEdgeAnimation) {
                            ForEach(PillEdgeAnimation.allCases) { Text($0.label).tag($0) }
                        }
                        if settings.pillEdgeAnimation != .none {
                            slider("Animation speed", $settings.pillEdgeAnimSpeed,
                                   0.25...3.0, step: 0.25, fmt: "%.2f", unit: "×")
                        }
                    }
                    slider("Thickness", $settings.pillEdgeWidth,
                           0.5...5.0, step: 0.5, fmt: "%.1f", unit: "pt")
                }
            }

            Section {
                Toggle("Inner glow", isOn: $settings.pillInnerGlow)
                if settings.pillInnerGlow {
                    slider("Intensity", $settings.pillInnerGlowIntensity,
                           0.1...1.0, step: 0.05, fmt: "%.0f", unit: "%", scale: 100)
                    slider("Distance", $settings.pillInnerGlowDistance,
                           2...24, step: 1, fmt: "%.0f", unit: "pt")
                }
            } header: {
                HStack(spacing: 6) { Text("Inner Glow"); BetaBadge() }
            } footer: {
                Text("A soft glow just inside the border, matching its colors. Shows only when expanded or peeking.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Music

    private var musicTab: some View {
        Form {
            Section {
                Toggle(isOn: $settings.audioReactive) {
                    HStack(spacing: 6) { Text("React to music (DJ mode)"); BetaBadge() }
                }
                .disabled(!djModeSupported)

                if settings.audioReactive && djModeSupported {
                    slider("Sensitivity", $settings.djSensitivity,
                           0.5...3.0, step: 0.1, fmt: "%.1f", unit: "×")
                    Toggle("Speed up border with the music", isOn: $settings.djReactSpeed)
                    Toggle("Pulse border brightness", isOn: $settings.djReactPulse)
                    Toggle("Bounce the pill on the beat", isOn: $settings.djBeatBounce)
                }
            } header: {
                Text("DJ Mode")
            } footer: {
                if djModeSupported {
                    Text("The equalizer bars and border react to the live beat. macOS shows a recording indicator while it listens (required to read system audio) — only while music plays.")
                } else {
                    Text("DJ mode needs macOS 14.4 or later. Everything else works on your Mac.")
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Tabs

    private var tabsTab: some View {
        Form {
            Section {
                ForEach(DocklyTab.allCases) { tab in
                    Toggle(isOn: tabToggle(tab)) {
                        Label(tab.title, systemImage: tab.icon)
                    }
                }
            } header: {
                Text("Panels")
            } footer: {
                Text("Choose which panels appear in the tab bar when Dockly is open.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Integrations

    private var integrationsTab: some View {
        Form {
            Section {
                TextField("http://localhost:3000", text: $settings.lifeDashboardURL)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Life Dashboard")
            } footer: {
                Text("Run your life-dashboard backend to sync Tasks and events. Default: http://localhost:3000")
            }

            Section("Calendars") {
                CalendarPicker()
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Size

    private var sizeTab: some View {
        Form {
            Section("Closed pill") {
                sizeRow("Width", $settings.compactWingWidth, 24...90, 2)
                sizeRow("Extra height", $settings.compactExtraHeight, 0...40, 1)
            }
            Section("Open panel") {
                sizeRow("Width", $settings.expandedWidth, 340...620, 10)
                sizeRow("Extra height", $settings.expandedExtraHeight, -30...120, 5)
            }
            Section {
                sizeRow("Width nudge", $settings.notchWidthOffset, -60...60, 2)
                sizeRow("Height nudge", $settings.notchHeightOffset, -16...40, 1)
                Toggle("Show notch outline", isOn: $settings.showNotchDebugOverlay)
                NotchDebugView()
            } header: {
                Text("Notch alignment")
            } footer: {
                Text("Use the nudges (and the outline overlay) to line Dockly's pill up exactly with your Mac's physical notch.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About

    private var aboutTab: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        return Form {
            Section {
                LabeledContent("Version", value: version)
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                Link("View on GitHub", destination: URL(string: "https://github.com/pikzelperfekt/Dockly")!)
            } header: {
                Text("Dockly")
            } footer: {
                Text("A Dynamic-Island-style notch hub for macOS. Updates install automatically.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Reusable slider row

    private func slider(_ title: String, _ value: Binding<Double>,
                        _ range: ClosedRange<Double>, step: Double,
                        fmt: String, unit: String, scale: Double = 1) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range, step: step)
            Text("\(value.wrappedValue * scale, specifier: fmt)\(unit)")
                .monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
        }
    }

    private func sizeRow(_ title: String, _ value: Binding<Double>,
                         _ range: ClosedRange<Double>, _ step: Double) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range, step: step)
            Text("\(value.wrappedValue, specifier: "%.0f") pt")
                .monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private var edgeColor1Binding: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: settings.pillEdgeColor1Hex) ?? .systemBlue) },
            set: { settings.pillEdgeColor1Hex = NSColor($0).hexString }
        )
    }

    private var edgeColor2Binding: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: settings.pillEdgeColor2Hex) ?? .systemPurple) },
            set: { settings.pillEdgeColor2Hex = NSColor($0).hexString }
        )
    }

    private func tabToggle(_ tab: DocklyTab) -> Binding<Bool> {
        Binding(
            get: { settings.enabledTabs.contains(tab) },
            set: { on in
                if on { settings.enabledTabs.insert(tab) }
                else { settings.enabledTabs.remove(tab) }
                if !settings.enabledTabs.contains(settings.activeTab),
                   let first = DocklyTab.allCases.first(where: { settings.enabledTabs.contains($0) }) {
                    settings.activeTab = first
                }
            }
        )
    }
}

// MARK: - Notch debug visual
// Shows the detected notch geometry: screen, notch height/width, derived
// pill metrics. Refreshes each time the panel is shown.

private struct NotchDebugView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let info = detect() {
                metricsGrid(info)
                preview(info)
            } else {
                Text("No notched screen detected. Using fallback geometry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct NotchInfo {
        let screenName: String
        let screenSize: CGSize
        let notchHeight: CGFloat
        let notchWidth: CGFloat
        let auxLeftWidth: CGFloat
        let auxRightWidth: CGFloat
    }

    private func detect() -> NotchInfo? {
        guard let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
                ?? NSScreen.main else { return nil }

        let lw: CGFloat
        let rw: CGFloat
        if #available(macOS 12.0, *) {
            lw = s.auxiliaryTopLeftArea?.width ?? 0
            rw = s.auxiliaryTopRightArea?.width ?? 0
        } else {
            lw = 0; rw = 0
        }
        let settings = AppSettings.shared
        let baseNH = (s.safeAreaInsets.top > 0) ? s.safeAreaInsets.top : 32
        let nh = max(16, baseNH + CGFloat(settings.notchHeightOffset))
        let baseNW: CGFloat = (lw > 0 && rw > 0)
            ? max(80, min(320, s.frame.width - lw - rw))
            : 220
        let nw = max(40, baseNW + CGFloat(settings.notchWidthOffset))

        return NotchInfo(
            screenName: s.localizedName,
            screenSize: s.frame.size,
            notchHeight: nh,
            notchWidth: nw,
            auxLeftWidth: lw,
            auxRightWidth: rw
        )
    }

    @ViewBuilder
    private func metricsGrid(_ i: NotchInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            metricRow("Screen", "\(i.screenName) (\(Int(i.screenSize.width))×\(Int(i.screenSize.height)))")
            metricRow("Notch height", "\(format(i.notchHeight)) pt")
            metricRow("Notch width", "\(format(i.notchWidth)) pt")
            metricRow("Aux top-left", "\(format(i.auxLeftWidth)) pt")
            metricRow("Aux top-right", "\(format(i.auxRightWidth)) pt")
        }
        .font(.system(size: 11))
        .monospacedDigit()
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(value).foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func preview(_ i: NotchInfo) -> some View {
        // Actual-size (1:1) preview of the closed pill, including the user's
        // width/height sizing. The black area = the real notch; the lighter
        // wings = how far the compact pill extends past it.
        let s = AppSettings.shared
        let wing = CGFloat(s.compactWingWidth)
        let extraH = CGFloat(s.compactExtraHeight)
        let pillW = i.notchWidth + wing * 2
        let pillH = i.notchHeight + extraH

        VStack(spacing: 6) {
            ZStack(alignment: .top) {
                // The compact pill at real size (sharp top, rounded bottom)
                PillShape(cornerRadius: 10)
                    .fill(Color.black)
                    .overlay(
                        PillShape(cornerRadius: 10)
                            .stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
                    )
                    .frame(width: pillW, height: pillH)

                // The notch hardware region marked inside
                Rectangle()
                    .strokeBorder(Color.red.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: i.notchWidth, height: i.notchHeight)
            }
            .frame(maxWidth: .infinity)
            .frame(height: pillH + 8)

            Text("Pill \(Int(pillW))×\(Int(pillH)) pt · notch \(Int(i.notchWidth))×\(Int(i.notchHeight)) pt (actual size)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.10))
        )
    }

    private func format(_ v: CGFloat) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

// MARK: - Calendar picker

private struct CalendarPicker: View {
    @ObservedObject private var store = CalendarListStore.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        if !store.authorized {
            VStack(alignment: .leading, spacing: 6) {
                Text("Calendar access not granted.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Request access") { store.requestAccess() }
                    .controlSize(.small)
            }
        } else if store.calendars.isEmpty {
            Text("No calendars found.")
                .font(.caption).foregroundStyle(.secondary)
                .onAppear { store.loadCalendars() }
        } else {
            Text("Pick which calendars feed the upcoming-event activity. None checked = all of them.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(store.calendars) { cal in
                Toggle(isOn: binding(for: cal.id)) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(nsColor: NSColor(hex: cal.colorHex) ?? .systemBlue))
                            .frame(width: 9, height: 9)
                        Text(cal.title)
                    }
                }
            }
            .onAppear { store.loadCalendars() }
        }
    }

    // When the selection set is empty, all calendars are effectively on, so show
    // them checked; flipping one off starts an explicit selection of the rest.
    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: {
                settings.selectedCalendarIDs.isEmpty || settings.selectedCalendarIDs.contains(id)
            },
            set: { on in
                var set = settings.selectedCalendarIDs
                if set.isEmpty {
                    // First explicit change — seed with all currently-shown calendars.
                    set = Set(store.calendars.map(\.id))
                }
                if on { set.insert(id) } else { set.remove(id) }
                // If everything ended up selected again, collapse back to "all".
                settings.selectedCalendarIDs = (set.count == store.calendars.count) ? [] : set
            }
        )
    }
}

// Small orange "BETA" pill used to flag experimental features.
struct BetaBadge: View {
    var body: some View {
        Text("BETA")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.orange))
    }
}

// Sharp top corners, rounded bottom — matches the actual pill shape.
private struct PillShape: Shape {
    var cornerRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
