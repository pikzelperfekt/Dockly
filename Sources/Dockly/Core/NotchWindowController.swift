import AppKit
import SwiftUI
import Combine

// NSPanel subclass that can become key without activating the app — so the
// SwiftUI TextEditor inside Notes can actually receive typing.
private final class DocklyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// Flipped container so its layer uses the same top-left origin as the
// NSHostingView — keeps the shadow's notch path the right way up.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// NSHostingView subclass that fires expand/collapse via tracking area,
// recognises two-finger horizontal swipes, and surfaces file drag-enter
// so we can auto-expand to the Tray tab.
private final class PillView<V: View>: NSHostingView<V> {
    var onEnter:        (() -> Void)?
    var onExit:         (() -> Void)?
    var onSwipePrev:    (() -> Void)?
    var onSwipeNext:    (() -> Void)?
    var onFileDragHover: (() -> Void)?
    var onVolumeScroll: ((CGFloat) -> Void)?

    private var lastSwipeAt: TimeInterval = 0
    private var scrollVolumeAccum: CGFloat = 0

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent)  { onExit?()  }

    // Deliver the FIRST click to the content even when the panel isn't key —
    // otherwise the first click is swallowed activating the window (the
    // "have to click twice to open" bug).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Two-finger horizontal swipe → previous / next tab.
    // Only treat the very start of a trackpad gesture as a "swipe" so we don't
    // fire on regular scrolling that happens to drift sideways.
    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return }
        guard event.phase == .began || event.phase == .changed else { return }
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY

        // Vertical scroll → volume (accumulate so ~12pt of scroll = one step).
        if abs(dy) > abs(dx) * 1.2 {
            scrollVolumeAccum += dy
            let step: CGFloat = 12
            while abs(scrollVolumeAccum) >= step {
                onVolumeScroll?(scrollVolumeAccum > 0 ? 1 : -1)   // up = louder
                scrollVolumeAccum -= (scrollVolumeAccum > 0 ? step : -step)
            }
            return
        }

        // Horizontal swipe → previous / next tab (or track when peeking).
        let now = event.timestamp
        guard now - lastSwipeAt > 0.45 else { return }
        guard abs(dx) > 6, abs(dx) > abs(dy) * 1.8 else { return }
        lastSwipeAt = now
        if dx > 0 { onSwipePrev?() } else { onSwipeNext?() }
    }

    // File drag landed over the pill → ask controller to expand into Tray.
    // We return `.copy` so the dragging session continues; the actual drop
    // is handled by the SwiftUI .onDrop in TrayTabView once it's on screen.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) {
            onFileDragHover?()
            return .copy
        }
        return []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { false }
}

final class NotchWindowController: NSObject, ObservableObject {
    @Published private(set) var isExpanded = false
    @Published private(set) var isPeeking  = false
    @Published private(set) var isCursorNearby: Bool = false
    @Published private(set) var cursorParallax: CGFloat = 0   // -1 (left) … 1 (right)
    @Published private(set) var compactExtension: CGFloat = 0

    let belowNotch: CGFloat       = 0
    let expandedContentH: CGFloat = 110
    let peekContentH: CGFloat     = 30
    let compactCornerRadius: CGFloat = 10
    let expandedCornerRadius: CGFloat = 18

    // User-tunable geometry (read live from settings)
    var expandedW: CGFloat { CGFloat(AppSettings.shared.expandedWidth) }
    var maxCompactExtension: CGFloat { CGFloat(AppSettings.shared.compactWingWidth) }
    let peekToExpandDwell: TimeInterval = 0.5

    private var panel: NSPanel?
    private var pillView: PillView<DocklyPanelView>?
    private var contentLayer: CALayer?
    private var contentMaskLayer: CAShapeLayer?
    private var shadowLayer: CAShapeLayer?
    let concaveTop: CGFloat = 11      // inverted top-corner radius
    let expandedTabBarHeight: CGFloat = 30   // reserved row for the tab bar
    // Transparent margin around the pill inside the window, so the drop shadow
    // has room to render (sides + bottom; the top stays flush to the screen).
    let shadowMargin: CGFloat = 14

    // The visible pill rect inside the (margined) window bounds.
    private func pillRect(in bounds: CGRect) -> CGRect {
        CGRect(x: shadowMargin, y: 0,
               width: bounds.width - shadowMargin * 2,
               height: bounds.height - shadowMargin)
    }
    private var edgeGradientLayer: CAGradientLayer?
    private var edgeMaskLayer: CAShapeLayer?
    private var innerGlowGradient: CAGradientLayer?  // mirrors the edge colors
    private var innerGlowMask: CAShapeLayer?          // wide band along the inside edge
    private var edgeAnimTimer: Timer?
    private var edgeAnimPhase: CGFloat = 0
    private var settingsSink: AnyCancellable?
    private var accentSink: AnyCancellable?
    private var collapseTimer: Timer?
    private var peekDwellTimer: Timer?
    private var globalMouseMonitor: Any?
    private var globalDragMonitor: Any?
    private var hotkeyMonitor: Any?
    private var hotkeyLocalMonitor: Any?
    private var lastDragPasteboardChangeCount: Int = NSPasteboard(name: .drag).changeCount
    private var dragSessionActive: Bool = false
    private var cachedNotchScreen: NSScreen?

    // Spring physics state
    private var springTimer: Timer?
    private var curX: CGFloat = 0;  private var velX: CGFloat = 0
    private var curY: CGFloat = 0;  private var velY: CGFloat = 0
    private var curW: CGFloat = 0;  private var velW: CGFloat = 0
    private var curH: CGFloat = 0;  private var velH: CGFloat = 0
    private var curR: CGFloat = 10; private var velR: CGFloat = 0
    private var tgtFrame = CGRect.zero
    private var tgtR: CGFloat = 10

    // MARK: - Setup

    func setup() {
        guard let screen = notchedScreen() else { return }
        buildPanel(on: screen)
        startGlobalMouseMonitor()
        startFileDragMonitor()
        startHotkeyMonitor()
        // React to live appearance + geometry changes from settings.
        settingsSink = AppSettings.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshEdgeAppearance()
                self?.applyGeometryNow()
            }
        }
        // React to album-art accent color changes (adaptive theming).
        accentSink = ActivityManager.shared.$accentColor.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshEdgeAppearance() }
        }
        refreshEdgeAppearance()
    }

    private func startGlobalMouseMonitor() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self, !self.isExpanded,
                  let screen = self.notchedScreen() else { return }
            let loc = NSEvent.mouseLocation
            let nh = self.notchHeight(screen: screen)
            let nw = self.notchWidth(screen: screen)
            let pillW = nw + self.compactExtension * 2 + self.concaveTop * 2

            // Peek zone = the pill's full current footprint. When already
            // peeking, grow it to include the dropdown so cursor drifting
            // down to read the text doesn't collapse the peek.
            let pillHeight = nh + self.belowNotch + (self.isPeeking ? self.peekContentH : 0)
            let peekZone = CGRect(
                x: screen.frame.midX - pillW / 2,
                y: screen.frame.maxY - pillHeight,
                width: pillW,
                height: pillHeight
            )
            // "Nearby" zone is generously larger than the pill — triggers a
            // tiny anticipation animation when the cursor is approaching.
            let nearZone = CGRect(
                x: screen.frame.midX - pillW * 0.85,
                y: screen.frame.maxY - pillHeight - 28,
                width: pillW * 1.7,
                height: pillHeight + 28
            )
            let nearby = nearZone.contains(loc)
            if self.isCursorNearby != nearby {
                self.isCursorNearby = nearby
            }
            // Parallax: where is the cursor horizontally relative to pill center?
            let p = max(-1, min(1, (loc.x - screen.frame.midX) / (pillW * 0.9)))
            self.cursorParallax = nearby ? p : 0

            if peekZone.contains(loc) {
                self.collapseTimer?.invalidate(); self.collapseTimer = nil
                self.peek(true)
            } else if self.isPeeking {
                self.scheduleCollapse()
            }
        }
    }

    // Watches for a file drag in progress anywhere on screen. When the
    // cursor enters the notch zone with files on the drag pasteboard,
    // jump to the Tray tab and expand the pill so the drop lands cleanly.
    private func startFileDragMonitor() {
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self else { return }
            if event.type == .leftMouseUp {
                self.dragSessionActive = false
                return
            }
            let pb = NSPasteboard(name: .drag)
            // Only re-check pasteboard types when the session is new
            if pb.changeCount != self.lastDragPasteboardChangeCount {
                self.lastDragPasteboardChangeCount = pb.changeCount
                self.dragSessionActive = pb.types?.contains(.fileURL) ?? false
            }
            guard self.dragSessionActive,
                  let screen = self.notchedScreen() else { return }

            let loc = NSEvent.mouseLocation
            let nh = self.notchHeight(screen: screen)
            let nw = self.notchWidth(screen: screen)
            // Generous landing strip: 2× notch width and 40pt below
            let zone = CGRect(
                x: screen.frame.midX - nw,
                y: screen.frame.maxY - nh - 40,
                width: nw * 2,
                height: nh + 40
            )
            if zone.contains(loc), !self.isExpanded {
                self.collapseTimer?.invalidate(); self.collapseTimer = nil
                AppSettings.shared.activeTab = .tray
                self.expand(true)
            }
        }
    }

    // ⌥⌘D toggles the panel open/closed from anywhere.
    private func startHotkeyMonitor() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self, AppSettings.shared.hotkeyEnabled else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.command, .option], event.charactersIgnoringModifiers?.lowercased() == "d" {
                DispatchQueue.main.async { self.expand(!self.isExpanded) }
            }
        }
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
        // Local monitor so it also works when our own panel is key.
        hotkeyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event); return event
        }
    }

    func repositionPanel() {
        guard let screen = notchedScreen() else { return }
        let f = pillFrame(screen: screen, expanded: isExpanded)
        panel?.setFrame(f, display: true)
        (curX, curY, curW, curH) = (f.minX, f.minY, f.width, f.height)
        tgtFrame = f; velX = 0; velY = 0; velW = 0; velH = 0
    }

    private func notchedScreen() -> NSScreen? {
        if #available(macOS 12.0, *) {
            if let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
                cachedNotchScreen = s
                return s
            }
        }
        if let cached = cachedNotchScreen, NSScreen.screens.contains(cached) {
            return cached
        }
        return NSScreen.main
    }

    // MARK: - Window

    private func buildPanel(on screen: NSScreen) {
        let f = pillFrame(screen: screen, expanded: false)
        (curX, curY, curW, curH) = (f.minX, f.minY, f.width, f.height)
        tgtFrame = f
        curR = compactCornerRadius
        tgtR = compactCornerRadius

        let p = DocklyPanel(contentRect: f, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false              // we draw a richer shadow ourselves
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovable = false

        // Container holds a dedicated shadow layer BEHIND the (masked) content,
        // so the blurred drop shadow isn't clipped by the content's shape mask.
        let container = FlippedView()
        container.wantsLayer = true                 // top-left origin, matches paths
        let shadow = CAShapeLayer()
        shadow.fillColor = NSColor.black.cgColor            // filled shape = casts a
        shadow.masksToBounds = false                        // shape-following shadow
        shadow.shadowColor = NSColor.black.cgColor
        shadow.shadowOpacity = 0.7
        shadow.shadowRadius = 5                              // tight, hugs the border
        shadow.shadowOffset = .zero                         // even all the way around
        container.layer?.addSublayer(shadow)
        shadowLayer = shadow

        let hv = PillView(rootView: DocklyPanelView(controller: self))
        hv.registerForDraggedTypes([.fileURL])
        if #available(macOS 13.0, *) { hv.sizingOptions = [] }
        hv.wantsLayer = true
        hv.layer?.backgroundColor = NSColor.black.cgColor
        // Custom notch shape: concave (inverted) top corners that flare into the
        // bezel, convex rounded bottom. A CAShapeLayer mask clips the content +
        // its sublayers (edge / glow) to that silhouette.
        let mask = CAShapeLayer()
        mask.fillColor = NSColor.black.cgColor
        hv.layer?.mask = mask
        hv.layer?.masksToBounds = false
        contentMaskLayer = mask
        contentLayer = hv.layer
        pillView = hv

        hv.onEnter = { [weak self] in
            // Just cancel any pending collapse; peek / expand decisions come
            // from the global mouse monitor and explicit clicks.
            self?.collapseTimer?.invalidate(); self?.collapseTimer = nil
        }
        hv.onExit = { [weak self] in
            self?.peekDwellTimer?.invalidate(); self?.peekDwellTimer = nil
            self?.scheduleCollapse()
        }
        hv.onSwipePrev = { [weak self] in
            guard let self else { return }
            if self.isExpanded {
                self.cycleTab(forward: false)
            } else if self.isPeeking {
                ActivityManager.shared.previousTrack()
            }
        }
        hv.onSwipeNext = { [weak self] in
            guard let self else { return }
            if self.isExpanded {
                self.cycleTab(forward: true)
            } else if self.isPeeking {
                ActivityManager.shared.nextTrack()
            }
        }
        hv.onFileDragHover = { [weak self] in
            guard let self else { return }
            self.collapseTimer?.invalidate(); self.collapseTimer = nil
            if !self.isExpanded {
                AppSettings.shared.activeTab = .tray
                self.expand(true)
            }
        }

        hv.frame = container.bounds
        hv.autoresizingMask = [.width, .height]
        container.addSubview(hv)
        p.contentView = container
        p.makeKeyAndOrderFront(nil)
        panel = p
    }

    func pillFrame(screen: NSScreen, expanded: Bool, peeking: Bool = false) -> CGRect {
        let s = AppSettings.shared
        let nh = notchHeight(screen: screen)
        let nw = notchWidth(screen: screen)
        let compactExtraH = CGFloat(s.compactExtraHeight)
        // Use the active tab's preferred content height (plus user nudge) when
        // expanded; a small extra strip when compact.
        // Expanded height = the tab's body height + the reserved tab-bar row.
        let expH = s.activeTab.contentHeight + expandedTabBarHeight + CGFloat(s.expandedExtraHeight)
        let extraH: CGFloat = expanded ? expH
            : (peeking ? peekContentH + compactExtraH : compactExtraH)
        let rawW: CGFloat = expanded ? expandedW : (nw + compactExtension * 2)
        // Pill content = requested body + concave flares on each side.
        let bodyW = min(max(rawW, 60), expandedW + 40)
        let pillW = bodyW + concaveTop * 2
        let pillH = nh + belowNotch + extraH
        // Window adds the transparent shadow margin (sides + bottom; top flush).
        let winW = pillW + shadowMargin * 2
        let winH = pillH + shadowMargin
        let x = screen.frame.midX - winW / 2
        let y = screen.frame.maxY - winH
        return CGRect(x: x, y: y, width: winW, height: winH)
    }

    /// Compute the wing extension appropriate for the current live activity.
    func compactExtensionTarget() -> CGFloat {
        let base = maxCompactExtension
        switch ActivityManager.shared.current {
        case .music:         return base
        case .upcomingEvent: return base * 0.85
        // Transient info pops keep full width so interrupting music doesn't
        // cause a shrink-then-grow wobble.
        case .battery:       return base
        case .volume:        return base
        case .bluetooth:     return base
        case .focus:         return base
        case .timer:         return base * 0.9
        case .clock:         return base * 0.72
        }
    }

    /// Apply current geometry settings to the pill immediately. Safe to call
    /// from settings changes — handles both compact and expanded states.
    func applyGeometryNow() {
        guard let screen = notchedScreen() else { return }
        if !isExpanded {
            // Re-derive wing width from current activity + settings
            let target = max(0, min(maxCompactExtension, compactExtensionTarget()))
            compactExtension = target
        }
        let f = pillFrame(screen: screen, expanded: isExpanded, peeking: isPeeking)
        guard abs(f.width - tgtFrame.width) > 0.5 || abs(f.height - tgtFrame.height) > 0.5 else { return }
        tgtFrame = f
        startSpring(stiffness: 260, damping: 32)
    }

    /// Re-spring the panel to the new active tab's height (no-op if compact).
    func handleActiveTabChange() {
        guard isExpanded, let screen = notchedScreen() else { return }
        tgtFrame = pillFrame(screen: screen, expanded: true)
        startSpring(stiffness: 260, damping: 34)
    }


    func setCompactExtension(_ amount: CGFloat) {
        let clamped = max(0, min(maxCompactExtension, amount))
        guard abs(compactExtension - clamped) > 0.01 else { return }
        compactExtension = clamped
        guard !isExpanded, let screen = notchedScreen() else { return }
        tgtFrame = pillFrame(screen: screen, expanded: false, peeking: isPeeking)
        startSpring(stiffness: 260, damping: 34)
    }

    func peek(_ on: Bool) {
        guard isPeeking != on, !isExpanded,
              let screen = notchedScreen() else { return }
        // Peek is only for music — silently ignore for clock/event
        if on, case .music = ActivityManager.shared.current {} else if on { return }
        isPeeking = on
        tgtFrame = pillFrame(screen: screen, expanded: false, peeking: on)
        // Gentle elastic overshoot for a gooey feel (top edge is pinned, so it
        // stretches downward rather than hopping).
        startSpring(stiffness: on ? 250 : 300, damping: on ? 22 : 28)
        refreshEdgeAppearance()   // fade the inner glow in/out
    }

    func notchHeight(screen: NSScreen) -> CGFloat {
        let offset = CGFloat(AppSettings.shared.notchHeightOffset)
        if #available(macOS 12.0, *), screen.safeAreaInsets.top > 0 {
            return max(16, screen.safeAreaInsets.top + offset)
        }
        return max(16, 32 + offset)
    }

    func notchWidth(screen: NSScreen) -> CGFloat {
        let offset = CGFloat(AppSettings.shared.notchWidthOffset)
        if #available(macOS 12.0, *),
           let lw = screen.auxiliaryTopLeftArea?.width,
           let rw = screen.auxiliaryTopRightArea?.width,
           lw > 0, rw > 0 {
            let gap = screen.frame.width - lw - rw
            if gap > 80 && gap < 320 { return max(40, gap + offset) }
        }
        return max(40, 220 + offset)
    }

    // MARK: - Tab cycling

    func cycleTab(forward: Bool) {
        guard isExpanded else { return }
        let s = AppSettings.shared
        let all = DocklyTab.allCases.filter { s.enabledTabs.contains($0) }
        guard !all.isEmpty,
              let idx = all.firstIndex(of: s.activeTab) else { return }
        let next = (idx + (forward ? 1 : -1) + all.count) % all.count
        s.activeTab = all[next]
    }

    // MARK: - Collapse scheduling

    private func scheduleCollapse() {
        guard collapseTimer == nil else { return }
        collapseTimer = Timer.scheduledTimer(
            withTimeInterval: AppSettings.shared.autoCollapseDelay, repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            self.collapseTimer = nil
            if self.isExpanded { self.expand(false) }
            if self.isPeeking { self.peek(false) }
        }
    }

    // MARK: - Spring expand / collapse

    func expand(_ on: Bool) {
        guard isExpanded != on, let screen = notchedScreen() else { return }
        isExpanded = on
        on ? Sounds.expand() : Sounds.collapse()
        if on { isPeeking = false }   // expanding supersedes peek
        tgtFrame = pillFrame(screen: screen, expanded: on, peeking: false)
        tgtR = on ? expandedCornerRadius : compactCornerRadius
        // Gooey: a little elastic overshoot opening, snappier closing.
        startSpring(stiffness: on ? 240 : 300, damping: on ? 21 : 30)
        refreshEdgeAppearance()   // fade the inner glow in/out
        // Make the panel become key when expanded so TextEditor / clicks
        // inside it actually work. Release key status when collapsing.
        if on {
            panel?.makeKey()
        } else {
            panel?.resignKey()
        }
    }

    private func startSpring(stiffness: CGFloat, damping: CGFloat) {
        springTimer?.invalidate()
        let dt: CGFloat = 1.0 / 120.0
        springTimer = Timer.scheduledTimer(withTimeInterval: dt, repeats: true) { [weak self] _ in
            self?.springStep(dt: dt, k: stiffness, c: damping)
        }
    }

    private func springStep(dt: CGFloat, k: CGFloat, c: CGFloat) {
        func s(_ cur: inout CGFloat, _ tgt: CGFloat, _ vel: inout CGFloat) {
            let f = -k * (cur - tgt) - c * vel
            vel += f * dt; cur += vel * dt
        }
        s(&curX, tgtFrame.minX, &velX)
        s(&curW, tgtFrame.width, &velW)
        s(&curH, tgtFrame.height, &velH)
        s(&curR, tgtR, &velR)

        // Pin the pill's TOP edge to the top of the screen so it only ever grows
        // downward. Deriving curY from curH (instead of springing it separately)
        // prevents the "hop" where the two springs overshoot at different rates.
        let screenTop = tgtFrame.minY + tgtFrame.height
        curY = screenTop - curH
        velY = 0

        let f = CGRect(x: curX, y: curY, width: curW, height: curH)
        // Disable CALayer implicit animations — without this, every shape /
        // bounds change kicks off its own 0.25s animation on top of our spring.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel?.setFrame(f, display: true, animate: false)
        syncEdgeGeometry()
        CATransaction.commit()

        let settled = abs(curX-tgtFrame.minX)<0.2
                   && abs(curW-tgtFrame.width)<0.2 && abs(curH-tgtFrame.height)<0.2
                   && abs(curR-tgtR)<0.1
                   && [velX,velW,velH,velR].allSatisfy { abs($0) < 1 }
        if settled {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            panel?.setFrame(tgtFrame, display: true, animate: false)
            syncEdgeGeometry()
            CATransaction.commit()
            velX=0; velY=0; velW=0; velH=0; velR=0
            springTimer?.invalidate(); springTimer = nil
            panel?.invalidateShadow()
        }
    }

    // MARK: - Edge customization

    func refreshEdgeAppearance() {
        guard contentLayer != nil else { return }
        let s = AppSettings.shared

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Adaptive album-art accent (Dynamic Island style). When on + art
        // available, it shows/recolors the edge even if the user left it off.
        let adaptive = s.adaptiveAccent ? ActivityManager.shared.accentColor : nil

        // --- Edge stroke ---
        if s.pillEdgeStyle == .off && adaptive == nil {
            edgeGradientLayer?.removeFromSuperlayer()
            edgeGradientLayer = nil
            edgeMaskLayer = nil
        } else {
            ensureEdgeLayer()
            edgeMaskLayer?.lineWidth = s.pillEdgeStyle == .off ? 2.0 : CGFloat(s.pillEdgeWidth)
            if s.pillEdgeAnimation != .breathe { edgeGradientLayer?.opacity = 1 }
            // Album color is the master override over ALL edge colors (incl.
            // rainbow). Motion animations (rotate/breathe) still apply on top.
            applyEdgeColors(adaptive: adaptive)
            applyEdgeDirection()
        }

        // --- Inner glow: an inward band that MATCHES the border colors, shown
        // only while expanded or peeking, fading in/out smoothly. ---
        let glowVisible = s.pillInnerGlow && (isExpanded || isPeeking)
        if s.pillInnerGlow, let edge = edgeGradientLayer {
            ensureInnerGlowLayer()
            let dist = CGFloat(s.pillInnerGlowDistance)
            // Mirror the edge gradient's colors/direction so it always matches.
            innerGlowGradient?.colors = edge.colors
            innerGlowGradient?.startPoint = edge.startPoint
            innerGlowGradient?.endPoint = edge.endPoint
            innerGlowGradient?.opacity = Float(s.pillInnerGlowIntensity)
            innerGlowMask?.lineWidth = dist * 2
            if let blur = CIFilter(name: "CIGaussianBlur") {
                blur.setValue(max(0.5, dist * 0.4), forKey: "inputRadius")
                innerGlowGradient?.filters = [blur]
            }
            fadeGlow(to: glowVisible)
        } else {
            innerGlowGradient?.removeFromSuperlayer()
            innerGlowGradient = nil
            innerGlowMask = nil
        }

        syncEdgeGeometry()
        CATransaction.commit()

        updateAnimationTimer()
    }

    /// Smoothly fade the inner glow in/out (used on expand/peek transitions).
    private func fadeGlow(to visible: Bool) {
        guard let g = innerGlowGradient else { return }
        let target: Float = visible ? Float(AppSettings.shared.pillInnerGlowIntensity) : 0
        if g.opacity != target {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = g.opacity; anim.toValue = target
            anim.duration = 0.28
            g.add(anim, forKey: "glowFade")
        }
        g.opacity = target
    }

    private var adaptivePaletteActive: Bool {
        AppSettings.shared.adaptiveAccent && ActivityManager.shared.accentPalette.count >= 2
    }

    private func applyEdgeColors(adaptive: NSColor? = nil) {
        let s = AppSettings.shared
        guard let g = edgeGradientLayer else { return }
        let newColors: [CGColor]
        if adaptive != nil, adaptivePaletteActive {
            // Multi-color album palette → looped so the rotating gradient blends
            // smoothly back to the start.
            let pal = ActivityManager.shared.accentPalette
            var cgs = pal.map { $0.cgColor }
            if let first = cgs.first { cgs.append(first) }  // seamless loop
            newColors = cgs
        } else if let accent = adaptive?.usingColorSpace(.sRGB) {
            // Single album accent → accent + a brighter sibling.
            var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            accent.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
            let bright = NSColor(hue: (h + 0.04).truncatingRemainder(dividingBy: 1),
                                 saturation: min(1, sat * 0.85),
                                 brightness: min(1, b * 1.15 + 0.1), alpha: 1)
            newColors = [accent.cgColor, bright.cgColor]
        } else if s.pillEdgeStyle == .solid {
            let c = NSColor(hex: s.pillEdgeColor1Hex)?.cgColor
                ?? CGColor(srgbRed: 0.36, green: 0.78, blue: 0.98, alpha: 1)
            newColors = [c, c]
        } else if s.pillEdgeAnimation == .rainbow {
            newColors = rainbowColors(phase: edgeAnimPhase)
        } else {
            let c1 = NSColor(hex: s.pillEdgeColor1Hex)?.cgColor
                ?? CGColor(srgbRed: 0.36, green: 0.78, blue: 0.98, alpha: 1)
            let c2 = NSColor(hex: s.pillEdgeColor2Hex)?.cgColor
                ?? CGColor(srgbRed: 0.69, green: 0.32, blue: 0.87, alpha: 1)
            newColors = [c1, c2]
        }
        // Smoothly cross-fade to the new colors so album changes feel alive.
        if let old = g.colors, old.count == newColors.count, adaptive != nil {
            let anim = CABasicAnimation(keyPath: "colors")
            anim.fromValue = old; anim.toValue = newColors
            anim.duration = 0.5
            g.add(anim, forKey: "colorFade")
        }
        g.colors = newColors
    }

    private func applyEdgeDirection() {
        guard let g = edgeGradientLayer else { return }
        let s = AppSettings.shared
        if s.pillEdgeAnimation == .rotate {
            // Rotating gradient — start/end orbit the center.
            let a = edgeAnimPhase
            g.startPoint = CGPoint(x: 0.5 + 0.5 * cos(a), y: 0.5 + 0.5 * sin(a))
            g.endPoint   = CGPoint(x: 0.5 - 0.5 * cos(a), y: 0.5 - 0.5 * sin(a))
            return
        }
        switch s.pillEdgeDirection {
        case .diagonal:
            g.startPoint = CGPoint(x: 0, y: 0); g.endPoint = CGPoint(x: 1, y: 1)
        case .horizontal:
            g.startPoint = CGPoint(x: 0, y: 0.5); g.endPoint = CGPoint(x: 1, y: 0.5)
        case .vertical:
            g.startPoint = CGPoint(x: 0.5, y: 0); g.endPoint = CGPoint(x: 0.5, y: 1)
        }
    }

    private func rainbowColors(phase: CGFloat) -> [CGColor] {
        // Six hues spread across the spectrum, scrolling with phase.
        (0..<6).map { i in
            let hue = (phase / (2 * .pi) + CGFloat(i) / 6).truncatingRemainder(dividingBy: 1)
            return NSColor(hue: hue, saturation: 0.85, brightness: 1.0, alpha: 1).cgColor
        }
    }

    private func ensureEdgeLayer() {
        guard let contentLayer else { return }
        if edgeGradientLayer == nil {
            let g = CAGradientLayer()
            g.startPoint = CGPoint(x: 0, y: 0)
            g.endPoint   = CGPoint(x: 1, y: 1)
            let m = CAShapeLayer()
            m.fillColor   = NSColor.clear.cgColor
            m.strokeColor = NSColor.black.cgColor
            m.lineJoin    = .round
            g.mask = m
            contentLayer.addSublayer(g)
            edgeGradientLayer = g
            edgeMaskLayer = m
        }
    }

    private func ensureInnerGlowLayer() {
        guard let contentLayer else { return }
        if innerGlowGradient == nil {
            let g = CAGradientLayer()
            // Band mask: a wide stroke along the edge path. The outer half is
            // clipped away by contentLayer.masksToBounds (rounded pill).
            let band = CAShapeLayer()
            band.fillColor = NSColor.clear.cgColor
            band.strokeColor = NSColor.black.cgColor   // mask = alpha only
            band.lineJoin = .round
            band.lineCap = .round
            g.mask = band
            g.opacity = 0
            // Insert below the edge stroke so the crisp border sits on top.
            contentLayer.insertSublayer(g, at: 0)
            innerGlowGradient = g
            innerGlowMask = band
        }
    }

    /// Update the notch shape mask + edge/glow paths each spring step.
    fileprivate func syncEdgeGeometry() {
        guard let contentLayer else { return }
        let b = contentLayer.bounds
        let pr = pillRect(in: b)             // pill within the margined window
        let bottom = curR                    // animated bottom radius
        let top = concaveTop                 // fixed concave top radius
        let local = CGRect(origin: .zero, size: pr.size)

        // Mask + shadow live in window space → path positioned at the pill rect.
        let fillWindow = notchPath(in: pr, top: top, bottom: bottom, closed: true)
        if let mask = contentMaskLayer {
            mask.frame = b
            mask.path = fillWindow
        }
        if let sh = shadowLayer {
            sh.frame = b
            sh.path = fillWindow
            sh.shadowPath = fillWindow
        }
        // Edge / glow gradient layers are framed to the pill rect → local paths.
        if let g = edgeGradientLayer, let m = edgeMaskLayer {
            g.frame = pr; m.frame = local
            m.path = notchPath(in: local, top: top, bottom: bottom, closed: false)
        }
        if let g = innerGlowGradient, let band = innerGlowMask {
            g.frame = pr; band.frame = local
            band.path = notchPath(in: local, top: top, bottom: bottom, closed: false)
        }
    }

    // Concave (inverted) top corners that flare into the bezel + convex rounded
    // bottom. `closed` = full silhouette (mask/fill); open = stroke without the
    // top edge (which sits against the screen). Layer space: y=0 top, y=h bottom.
    private func notchPath(in rect: CGRect, top tr: CGFloat, bottom br: CGFloat,
                           closed: Bool) -> CGPath {
        let ox = rect.minX, oy = rect.minY
        let w = rect.width, h = rect.height
        let tr = max(0, min(tr, w / 2)), br = max(0, min(br, min(w, h) / 2))
        // For the filled shape, push the top edge a couple px ABOVE the rect so
        // the black tucks under the menu-bar bezel with no seam/gap.
        let topY: CGFloat = closed ? -3 : 0
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x, y: oy + y) }
        let p = CGMutablePath()
        p.move(to: P(w - tr, tr))                               // top-right inner
        p.addLine(to: P(w - tr, h - br))                        // right wall
        p.addQuadCurve(to: P(w - tr - br, h), control: P(w - tr, h))   // convex bottom-right
        p.addLine(to: P(tr + br, h))                            // bottom edge
        p.addQuadCurve(to: P(tr, h - br), control: P(tr, h))    // convex bottom-left
        p.addLine(to: P(tr, tr))                                // left wall
        p.addQuadCurve(to: P(0, topY), control: P(tr, topY))    // concave top-left flare
        if closed {
            p.addLine(to: P(w, topY))                           // top edge (under bezel)
            p.addQuadCurve(to: P(w - tr, tr), control: P(w - tr, topY))  // concave top-right
            p.closeSubpath()
        } else {
            p.move(to: P(w, 0))
            p.addQuadCurve(to: P(w - tr, tr), control: P(w - tr, 0))
        }
        return p
    }

    // MARK: - Edge animation

    private func updateAnimationTimer() {
        let s = AppSettings.shared
        // Animate for the user's chosen animation, OR whenever a multi-color
        // album palette is driving the border (auto-rotate through the colors).
        let userAnim = (s.pillEdgeStyle != .off || adaptivePaletteActive) && s.pillEdgeAnimation != .none
        let needsAnim = userAnim || adaptivePaletteActive
        if needsAnim {
            guard edgeAnimTimer == nil else { return }
            edgeAnimTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.stepEdgeAnimation()
            }
        } else {
            edgeAnimTimer?.invalidate()
            edgeAnimTimer = nil
        }
    }

    private func audioLevel() -> CGFloat {
        guard AppSettings.shared.audioReactive,
              AudioReactor.shared.running else { return -1 }   // -1 = not reacting
        return CGFloat(AudioReactor.shared.level) * CGFloat(AppSettings.shared.djSensitivity)
    }

    private func stepEdgeAnimation() {
        let s = AppSettings.shared
        let lvl = min(1.5, audioLevel())
        let reacting = lvl >= 0
        // DJ mode: louder → faster rotation (if enabled).
        let speedReact = reacting && s.djReactSpeed
        let speed = CGFloat(s.pillEdgeAnimSpeed) * (speedReact ? (0.4 + lvl * 3.5) : 1)
        edgeAnimPhase += 0.04 * speed
        if edgeAnimPhase > .pi * 4 { edgeAnimPhase -= .pi * 4 }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let adaptive = s.adaptiveAccent ? ActivityManager.shared.accentColor : nil

        // Multi-color album palette: continuously rotate the gradient so the
        // border flows through the album's colors (even if no user animation).
        if adaptivePaletteActive {
            rotateGradient(phase: edgeAnimPhase)
            if s.pillEdgeAnimation == .breathe { breatheStep(s) }
            // DJ mode: pulse the border brightness with the beat (if enabled).
            if reacting && s.djReactPulse { edgeGradientLayer?.opacity = Float(0.5 + min(0.5, lvl * 0.5)) }
            else if s.pillEdgeAnimation != .breathe { edgeGradientLayer?.opacity = 1 }
            mirrorEdgeToGlow()
            CATransaction.commit()
            return
        }

        switch s.pillEdgeAnimation {
        case .rotate:
            applyEdgeDirection()
        case .rainbow:
            if adaptive == nil { applyEdgeColors() }
        case .breathe:
            breatheStep(s)
        case .none:
            break
        }
        mirrorEdgeToGlow()
        CATransaction.commit()
    }

    private func breatheStep(_ s: AppSettings) {
        let t = (sin(edgeAnimPhase) + 1) / 2
        edgeMaskLayer?.lineWidth = CGFloat(s.pillEdgeWidth) * (0.5 + t)
        edgeGradientLayer?.opacity = Float(0.45 + 0.55 * t)
    }

    // Keep the inner glow's colors/direction matched to the edge gradient.
    private func mirrorEdgeToGlow() {
        guard let edge = edgeGradientLayer, let glow = innerGlowGradient else { return }
        glow.colors = edge.colors
        glow.startPoint = edge.startPoint
        glow.endPoint = edge.endPoint
    }

    private func rotateGradient(phase: CGFloat) {
        guard let g = edgeGradientLayer else { return }
        let a = phase * 0.5
        g.startPoint = CGPoint(x: 0.5 + 0.5 * cos(a), y: 0.5 + 0.5 * sin(a))
        g.endPoint   = CGPoint(x: 0.5 - 0.5 * cos(a), y: 0.5 - 0.5 * sin(a))
    }

    deinit {
        collapseTimer?.invalidate(); springTimer?.invalidate()
        peekDwellTimer?.invalidate(); edgeAnimTimer?.invalidate()
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m) }
        if let m = globalDragMonitor { NSEvent.removeMonitor(m) }
        if let m = hotkeyMonitor { NSEvent.removeMonitor(m) }
        if let m = hotkeyLocalMonitor { NSEvent.removeMonitor(m) }
    }
}
