import Foundation
import Combine

enum ShortcutsLayout: String, CaseIterable, Codable, Identifiable {
    case grid, list
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

enum PillEdgeStyle: String, CaseIterable, Codable, Identifiable {
    case off, solid, gradient
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off:      return "None"
        case .solid:    return "Solid"
        case .gradient: return "Gradient"
        }
    }
}

enum PillEdgeDirection: String, CaseIterable, Codable, Identifiable {
    case diagonal, horizontal, vertical
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum PillEdgeAnimation: String, CaseIterable, Codable, Identifiable {
    case none, rotate, rainbow, breathe
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:    return "Static"
        case .rotate:  return "Rotate"
        case .rainbow: return "Rainbow"
        case .breathe: return "Breathe"
        }
    }
}

enum DocklyTab: String, CaseIterable, Codable, Identifiable {
    case live, tray, tasks, timer, notes, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live:      return "Live"
        case .tray:      return "Tray"
        case .tasks:     return "Tasks"
        case .timer:     return "Timer"
        case .notes:     return "Notes"
        case .shortcuts: return "Shortcuts"
        }
    }

    var icon: String {
        switch self {
        case .live:      return "waveform"
        case .tray:      return "tray.full.fill"
        case .tasks:     return "checklist"
        case .timer:     return "timer"
        case .notes:     return "note.text"
        case .shortcuts: return "bolt.fill"
        }
    }

    /// Usable body height below the notch (excludes the notch strip AND the
    /// reserved tab-bar row — the controller adds those).
    var contentHeight: CGFloat {
        switch self {
        case .live:      return 96
        case .tray:      return 104
        case .tasks:     return 150
        case .timer:     return 124
        case .notes:     return 140
        case .shortcuts: return 150
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum ExpandTrigger: String, CaseIterable {
        case hover, click
        var label: String { rawValue.capitalized }
    }

    @Published var expandTrigger: ExpandTrigger {
        didSet { store("expand_trigger", expandTrigger.rawValue) }
    }
    @Published var autoCollapseDelay: Double {
        didSet { store("collapse_delay", autoCollapseDelay) }
    }
    @Published var lifeDashboardURL: String {
        didSet { store("ld_url", lifeDashboardURL) }
    }
    @Published var enabledWidgets: Set<String> {
        didSet {
            if let data = try? JSONEncoder().encode(enabledWidgets) {
                UserDefaults.standard.set(data, forKey: "enabled_widgets")
            }
        }
    }
    @Published var enabledTabs: Set<DocklyTab> {
        didSet {
            if let data = try? JSONEncoder().encode(enabledTabs) {
                UserDefaults.standard.set(data, forKey: "enabled_tabs")
            }
        }
    }
    @Published var activeTab: DocklyTab {
        didSet { store("active_tab", activeTab.rawValue) }
    }

    @Published var pillEdgeStyle: PillEdgeStyle {
        didSet { store("pill_edge_style", pillEdgeStyle.rawValue) }
    }
    @Published var pillEdgeColor1Hex: String {
        didSet { store("pill_edge_color1", pillEdgeColor1Hex) }
    }
    @Published var pillEdgeColor2Hex: String {
        didSet { store("pill_edge_color2", pillEdgeColor2Hex) }
    }
    @Published var pillEdgeWidth: Double {
        didSet { store("pill_edge_width", pillEdgeWidth) }
    }
    @Published var pillEdgeDirection: PillEdgeDirection {
        didSet { store("pill_edge_direction", pillEdgeDirection.rawValue) }
    }
    @Published var pillEdgeAnimation: PillEdgeAnimation {
        didSet { store("pill_edge_animation", pillEdgeAnimation.rawValue) }
    }
    @Published var pillEdgeAnimSpeed: Double {
        didSet { store("pill_edge_anim_speed", pillEdgeAnimSpeed) }
    }
    @Published var pillInnerGlow: Bool {
        didSet { store("pill_inner_glow", pillInnerGlow) }
    }
    @Published var pillInnerGlowColorHex: String {
        didSet { store("pill_inner_glow_color", pillInnerGlowColorHex) }
    }
    @Published var pillInnerGlowIntensity: Double {
        didSet { store("pill_inner_glow_intensity", pillInnerGlowIntensity) }
    }
    @Published var pillInnerGlowDistance: Double {
        didSet { store("pill_inner_glow_distance", pillInnerGlowDistance) }
    }
    @Published var shortcutsLayout: ShortcutsLayout {
        didSet { store("shortcuts_layout", shortcutsLayout.rawValue) }
    }
    // Geometry — user-tunable pill sizing
    @Published var compactWingWidth: Double {
        didSet { store("compact_wing_width", compactWingWidth) }
    }
    @Published var expandedWidth: Double {
        didSet { store("expanded_width", expandedWidth) }
    }
    @Published var notchWidthOffset: Double {
        didSet { store("notch_width_offset", notchWidthOffset) }
    }
    @Published var notchHeightOffset: Double {
        didSet { store("notch_height_offset", notchHeightOffset) }
    }
    @Published var showNotchDebugOverlay: Bool {
        didSet { store("show_notch_debug_overlay", showNotchDebugOverlay) }
    }
    @Published var hotkeyEnabled: Bool {
        didSet { store("hotkey_enabled", hotkeyEnabled) }
    }
    @Published var hasOnboarded: Bool {
        didSet { store("has_onboarded", hasOnboarded) }
    }
    /// Pull the pill's edge/glow color from the current album art.
    @Published var adaptiveAccent: Bool {
        didSet { store("adaptive_accent", adaptiveAccent) }
    }
    @Published var soundEffects: Bool {
        didSet { store("sound_effects", soundEffects) }
    }
    /// "DJ mode" — bars + border react to the live audio.
    @Published var audioReactive: Bool {
        didSet { store("audio_reactive", audioReactive) }
    }
    @Published var djSensitivity: Double {          // 0.5…3.0 multiplier
        didSet { store("dj_sensitivity", djSensitivity) }
    }
    @Published var djReactSpeed: Bool {             // border speeds up with volume
        didSet { store("dj_react_speed", djReactSpeed) }
    }
    @Published var djReactPulse: Bool {             // border brightness pulses
        didSet { store("dj_react_pulse", djReactPulse) }
    }
    @Published var djBeatBounce: Bool {             // pill bounces on the bass
        didSet { store("dj_beat_bounce", djBeatBounce) }
    }
    // Which calendars feed the upcoming-event activity. Empty = all calendars.
    @Published var selectedCalendarIDs: Set<String> {
        didSet {
            if let data = try? JSONEncoder().encode(selectedCalendarIDs) {
                UserDefaults.standard.set(data, forKey: "selected_calendar_ids")
            }
        }
    }
    @Published var compactExtraHeight: Double {
        didSet { store("compact_extra_height", compactExtraHeight) }
    }
    @Published var expandedExtraHeight: Double {
        didSet { store("expanded_extra_height", expandedExtraHeight) }
    }

    private init() {
        let ud = UserDefaults.standard
        expandTrigger = ExpandTrigger(rawValue: ud.string(forKey: "expand_trigger") ?? "") ?? .hover
        autoCollapseDelay = ud.double(forKey: "collapse_delay") > 0 ? ud.double(forKey: "collapse_delay") : 0.6
        lifeDashboardURL = ud.string(forKey: "ld_url") ?? "http://localhost:3000"

        if let data = ud.data(forKey: "enabled_widgets"),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            enabledWidgets = decoded
        } else {
            enabledWidgets = ["clock", "tasks", "calendar"]
        }

        if let data = ud.data(forKey: "enabled_tabs"),
           let decoded = try? JSONDecoder().decode(Set<DocklyTab>.self, from: data) {
            enabledTabs = decoded
        } else {
            enabledTabs = Set(DocklyTab.allCases)
        }

        activeTab = DocklyTab(rawValue: ud.string(forKey: "active_tab") ?? "") ?? .live

        pillEdgeStyle = PillEdgeStyle(rawValue: ud.string(forKey: "pill_edge_style") ?? "") ?? .off
        pillEdgeColor1Hex = ud.string(forKey: "pill_edge_color1") ?? "#5AC8FA"
        pillEdgeColor2Hex = ud.string(forKey: "pill_edge_color2") ?? "#AF52DE"
        let storedWidth = ud.double(forKey: "pill_edge_width")
        pillEdgeWidth = storedWidth > 0 ? storedWidth : 1.5
        pillEdgeDirection = PillEdgeDirection(rawValue: ud.string(forKey: "pill_edge_direction") ?? "") ?? .diagonal
        pillEdgeAnimation = PillEdgeAnimation(rawValue: ud.string(forKey: "pill_edge_animation") ?? "") ?? .none
        let animSpeed = ud.double(forKey: "pill_edge_anim_speed")
        pillEdgeAnimSpeed = animSpeed > 0 ? animSpeed : 1.0
        pillInnerGlow = ud.bool(forKey: "pill_inner_glow")
        pillInnerGlowColorHex = ud.string(forKey: "pill_inner_glow_color") ?? "#5AC8FA"
        let glowI = ud.double(forKey: "pill_inner_glow_intensity")
        pillInnerGlowIntensity = glowI > 0 ? glowI : 0.6
        let glowD = ud.double(forKey: "pill_inner_glow_distance")
        pillInnerGlowDistance = glowD > 0 ? glowD : 6
        shortcutsLayout = ShortcutsLayout(rawValue: ud.string(forKey: "shortcuts_layout") ?? "") ?? .grid

        let w = ud.double(forKey: "compact_wing_width")
        compactWingWidth = w > 0 ? w : 52
        let ew = ud.double(forKey: "expanded_width")
        expandedWidth = ew > 0 ? ew : 440
        notchWidthOffset = ud.object(forKey: "notch_width_offset") != nil
            ? ud.double(forKey: "notch_width_offset") : 0
        notchHeightOffset = ud.object(forKey: "notch_height_offset") != nil
            ? ud.double(forKey: "notch_height_offset") : 0
        showNotchDebugOverlay = ud.bool(forKey: "show_notch_debug_overlay")
        hotkeyEnabled = ud.object(forKey: "hotkey_enabled") != nil ? ud.bool(forKey: "hotkey_enabled") : true
        hasOnboarded = ud.bool(forKey: "has_onboarded")
        adaptiveAccent = ud.object(forKey: "adaptive_accent") != nil ? ud.bool(forKey: "adaptive_accent") : true
        soundEffects = ud.object(forKey: "sound_effects") != nil ? ud.bool(forKey: "sound_effects") : false
        audioReactive = ud.bool(forKey: "audio_reactive")
        let djS = ud.double(forKey: "dj_sensitivity")
        djSensitivity = djS > 0 ? djS : 1.5
        djReactSpeed = ud.object(forKey: "dj_react_speed") != nil ? ud.bool(forKey: "dj_react_speed") : true
        djReactPulse = ud.object(forKey: "dj_react_pulse") != nil ? ud.bool(forKey: "dj_react_pulse") : true
        djBeatBounce = ud.bool(forKey: "dj_beat_bounce")
        if let data = ud.data(forKey: "selected_calendar_ids"),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            selectedCalendarIDs = decoded
        } else {
            selectedCalendarIDs = []   // empty = all
        }
        compactExtraHeight = ud.object(forKey: "compact_extra_height") != nil
            ? ud.double(forKey: "compact_extra_height") : 0
        expandedExtraHeight = ud.object(forKey: "expanded_extra_height") != nil
            ? ud.double(forKey: "expanded_extra_height") : 0
    }

    private func store(_ key: String, _ value: some Any) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
