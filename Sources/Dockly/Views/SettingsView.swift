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
        Form {
            Section("General") {
                Toggle("Launch Dockly at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        launchAtLogin = on
                        if !LaunchAtLogin.set(on) { launchAtLogin = LaunchAtLogin.isEnabled }
                    }
                ))
                .disabled(!LaunchAtLogin.isAvailable)
                if !LaunchAtLogin.isAvailable {
                    Text("Available once Dockly is built as an .app bundle (run build-app.sh) and launched from /Applications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Global hotkey to toggle (⌥⌘D)", isOn: $settings.hotkeyEnabled)
                Toggle("Sound effects", isOn: $settings.soundEffects)
            }

            Section("Life Dashboard") {
                HStack {
                    Text("Backend URL")
                    Spacer()
                    TextField("http://localhost:3000", text: $settings.lifeDashboardURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                Text("Run `npm start` in your life-dashboard folder to enable calendar and task sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Picker("Expand on", selection: $settings.expandTrigger) {
                    ForEach(AppSettings.ExpandTrigger.allCases, id: \.self) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Stay open for")
                        Spacer()
                        Stepper(
                            value: $settings.autoCollapseDelay,
                            in: 0.1...15.0,
                            step: 0.1
                        ) {
                            Text("\(settings.autoCollapseDelay, specifier: "%.1f") s")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    Slider(value: $settings.autoCollapseDelay, in: 0.1...15.0, step: 0.1)
                    HStack {
                        Text("0.1 s").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("15 s").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Edge Decoration") {
                Toggle("Adapt color to album art", isOn: $settings.adaptiveAccent)
                Text("The pill glows in the colors of whatever's playing.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(isOn: $settings.audioReactive) {
                    HStack(spacing: 6) {
                        Text("React to music (DJ mode)")
                        BetaBadge()
                    }
                }
                .disabled(!djModeSupported)
                if djModeSupported {
                    Text("Bars + border react to the live audio. macOS shows a recording indicator while it listens (required for any system-audio capture); it only runs while music is playing and disappears when paused.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("DJ mode needs macOS 14.4 or later (it uses a Core Audio tap to read the beat). Everything else works on your Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if settings.audioReactive && djModeSupported {
                    HStack {
                        Text("Sensitivity")
                        Spacer()
                        Slider(value: $settings.djSensitivity, in: 0.5...3.0, step: 0.1)
                            .frame(width: 150)
                        Text("\(settings.djSensitivity, specifier: "%.1f")×")
                            .monospacedDigit().frame(width: 36, alignment: .trailing)
                    }
                    Toggle("Speed up border with volume", isOn: $settings.djReactSpeed)
                    Toggle("Pulse border brightness", isOn: $settings.djReactPulse)
                    Toggle("Bounce the pill on the beat", isOn: $settings.djBeatBounce)
                }
                Picker("Edge style", selection: $settings.pillEdgeStyle) {
                    ForEach(PillEdgeStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                if settings.pillEdgeStyle != .off {
                    ColorPicker("Edge color", selection: edgeColor1Binding,
                                supportsOpacity: true)
                    if settings.pillEdgeStyle == .gradient {
                        ColorPicker("Gradient end", selection: edgeColor2Binding,
                                    supportsOpacity: true)

                        Picker("Direction", selection: $settings.pillEdgeDirection) {
                            ForEach(PillEdgeDirection.allCases) { d in
                                Text(d.label).tag(d)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("Animation", selection: $settings.pillEdgeAnimation) {
                            ForEach(PillEdgeAnimation.allCases) { a in
                                Text(a.label).tag(a)
                            }
                        }
                        .pickerStyle(.menu)

                        if settings.pillEdgeAnimation != .none {
                            HStack {
                                Text("Speed")
                                Spacer()
                                Slider(value: $settings.pillEdgeAnimSpeed, in: 0.25...3.0, step: 0.25)
                                    .frame(width: 160)
                                Text("\(settings.pillEdgeAnimSpeed, specifier: "%.2f")×")
                                    .monospacedDigit()
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                    }
                    HStack {
                        Text("Edge width")
                        Spacer()
                        Slider(value: $settings.pillEdgeWidth, in: 0.5...5.0, step: 0.5)
                            .frame(width: 160)
                        Text("\(settings.pillEdgeWidth, specifier: "%.1f") pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section {
                Toggle("Glow inward from the edge", isOn: $settings.pillInnerGlow)
                if settings.pillInnerGlow {
                    Text("Matches the border colors. Shows only when expanded or peeking.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("Intensity")
                        Spacer()
                        Slider(value: $settings.pillInnerGlowIntensity, in: 0.1...1.0, step: 0.05)
                            .frame(width: 160)
                        Text("\(Int(settings.pillInnerGlowIntensity * 100))%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                    HStack {
                        Text("Distance")
                        Spacer()
                        Slider(value: $settings.pillInnerGlowDistance, in: 2...24, step: 1)
                            .frame(width: 160)
                        Text("\(Int(settings.pillInnerGlowDistance)) pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                HStack(spacing: 6) {
                    Text("Inner Glow")
                    BetaBadge()
                }
            } footer: {
                Text("Experimental — may have rendering quirks during resize or on some displays.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Calendars") {
                CalendarPicker()
            }

            Section("Tabs") {
                Text("Choose which panels appear in the tab bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(DocklyTab.allCases) { tab in
                    Toggle(isOn: tabToggle(tab)) {
                        HStack {
                            Image(systemName: tab.icon).frame(width: 18)
                            Text(tab.title)
                        }
                    }
                }
            }

            Section("Size & Geometry") {
                sizeRow(title: "Compact width",
                        value: $settings.compactWingWidth,
                        range: 24...90, step: 2, unit: "pt")
                sizeRow(title: "Compact extra height",
                        value: $settings.compactExtraHeight,
                        range: 0...40, step: 1, unit: "pt")
                sizeRow(title: "Expanded width",
                        value: $settings.expandedWidth,
                        range: 340...620, step: 10, unit: "pt")
                sizeRow(title: "Expanded extra height",
                        value: $settings.expandedExtraHeight,
                        range: -30...120, step: 5, unit: "pt")
                sizeRow(title: "Notch width nudge",
                        value: $settings.notchWidthOffset,
                        range: -60...60, step: 2, unit: "pt")
                sizeRow(title: "Notch height nudge",
                        value: $settings.notchHeightOffset,
                        range: -16...40, step: 1, unit: "pt")
                Text("Compact width/height control the closed pill. Expanded controls the open panel. Use the nudges to match Dockly's notch to your physical notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notch Debug") {
                Toggle("Show notch outline on the pill", isOn: $settings.showNotchDebugOverlay)
                Text("Draws a red box where Dockly thinks the notch is, with its measured size and a green center line. Use it to align the width/height nudges.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NotchDebugView()
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 680)
    }

    private func sizeRow(title: String, value: Binding<Double>,
                         range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Slider(value: value, in: range, step: step).frame(width: 180)
            Text("\(value.wrappedValue, specifier: "%.0f") \(unit)")
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
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

    private var innerGlowColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: settings.pillInnerGlowColorHex) ?? .systemBlue) },
            set: { settings.pillInnerGlowColorHex = NSColor($0).hexString }
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
