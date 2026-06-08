import SwiftUI

struct OnboardingView: View {
    var onDone: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @State private var page = 0
    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            // Paged content
            ZStack {
                switch page {
                case 0: welcome
                case 1: liveActivities
                case 2: customization
                default: gestures
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 30)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(page)

            footer
        }
        .frame(width: 500, height: 600)
        .background(backdrop)
    }

    // MARK: - Pages

    private var welcome: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.30, green: 0.50, blue: 0.98),
                                                  Color(red: 0.62, green: 0.30, blue: 0.92),
                                                  Color(red: 0.95, green: 0.32, blue: 0.62)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 92, height: 92)
                Image(systemName: "rectangle.topthird.inset.filled")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.white)
            }
            .shadow(color: .purple.opacity(0.4), radius: 16, y: 6)
            Text("Welcome to Dockly")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Your notch, reimagined into a living hub for media, tasks, timers, and more.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
            Spacer()
        }
    }

    private var liveActivities: some View {
        page(title: "Live Activities & Integrations",
             subtitle: "Dockly surfaces what matters, automatically.") {
            feature("waveform", .pink, "Now Playing — any app",
                    "Spotify, Apple Music, Safari & Chrome. Artwork, scrubber, and transport controls right in the notch.")
            feature("checklist", .green, "Life Dashboard tasks",
                    "Run your life-dashboard backend and your tasks appear here — tap to complete them.")
            feature("calendar", .red, "Upcoming events",
                    "Your next calendar event counts down in the pill. Pick which calendars in Settings.")
            feature("bolt.fill", .yellow, "Shortcuts",
                    "Run any macOS Shortcut straight from the notch.")
            feature("battery.100.bolt", .green, "Battery, AirPods & timers",
                    "Charging pops, Bluetooth connects, and a built-in countdown timer.")
        }
    }

    private var customization: some View {
        page(title: "Make It Yours",
             subtitle: "Tons of looks and behaviors to tweak in Settings.") {
            feature("paintpalette.fill", .purple, "Adaptive album color",
                    "The border glows in the colors of whatever's playing — or set your own gradient.")
            feature("sparkles", .blue, "Animated borders",
                    "Rotate, rainbow, breathe, or a multi-color flow pulled from the album art.")
            feature("waveform.circle.fill", .orange, "DJ mode (beta)",
                    "Bars + border react live to the beat of your music.")
            feature("ruler.fill", .teal, "Size & shape",
                    "Dial in the pill width, height, expanded size, and notch alignment.")
            feature("moon.stars.fill", .indigo, "Inner glow, sound, and more",
                    "Plenty of small touches to fine-tune the feel.")
        }
    }

    private var gestures: some View {
        page(title: "Quick Gestures",
             subtitle: "Everything's a hover, click, or swipe away.") {
            feature("cursorarrow.rays", .blue, "Hover to peek, click to open",
                    "Hover the pill for a glance; click to open the full panel.")
            feature("hand.draw.fill", .pink, "Swipe between tabs",
                    "Two-finger swipe on the open panel; swipe on the peek to skip tracks.")
            feature("tray.and.arrow.down.fill", .green, "Drag files to stash",
                    "Drop any file on the notch to tuck it into the Tray.")
            feature("command", .gray, "⌥⌘D anywhere",
                    "A global hotkey to toggle Dockly open or closed.")

            // Interactive quick-settings
            VStack(spacing: 8) {
                Toggle("Launch at login", isOn: launchBinding)
                    .disabled(!LaunchAtLogin.isAvailable)
                Toggle("Adapt color to album art", isOn: $settings.adaptiveAccent)
            }
            .padding(.top, 4)
            .toggleStyle(.switch)
            .tint(.accentColor)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Open Settings…") {
                NotificationCenter.default.post(name: .docklyOpenSettings, object: nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.system(size: 12))

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { i in
                    Circle()
                        .fill(.primary.opacity(i == page ? 0.85 : 0.25))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            if page < pageCount - 1 {
                Button("Next") { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { page += 1 } }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Get Started", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var launchBinding: Binding<Bool> {
        Binding(get: { LaunchAtLogin.isEnabled },
                set: { LaunchAtLogin.set($0) })
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func page<Content: View>(title: String, subtitle: String,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 8)
            Text(title).font(.system(size: 20, weight: .bold, design: .rounded))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(.top, 8)
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func feature(_ icon: String, _ tint: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var backdrop: some View {
        LinearGradient(colors: [Color(white: 0.13), Color(white: 0.08)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}
