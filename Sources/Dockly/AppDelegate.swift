import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = Updater.shared          // start background update checks
        setupStatusItem()
        notchController = NotchWindowController()
        notchController?.setup()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: .docklyOpenSettings,
            object: nil
        )

        if !AppSettings.shared.hasOnboarded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showOnboarding()
            }
        }
    }

    @objc private func showOnboardingMenu() { showOnboarding() }

    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        Updater.shared.checkForUpdates()
    }

    private func showOnboarding() {
        if onboardingWindow != nil {
            NSApp.activate(ignoringOtherApps: true)
            onboardingWindow?.makeKeyAndOrderFront(nil)
            return
        }
        let ctrl = NSHostingController(rootView: OnboardingView { [weak self] in
            AppSettings.shared.hasOnboarded = true
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        })
        let win = NSWindow(contentViewController: ctrl)
        win.title = "Welcome to Dockly"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        onboardingWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "Dockly"
        )
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "Welcome / Tips…", action: #selector(showOnboardingMenu), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Dockly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let ctrl = NSHostingController(rootView: SettingsView())
            let win = NSWindow(contentViewController: ctrl)
            win.title = "Dockly Settings"
            win.styleMask = [.titled, .closable]
            win.setContentSize(NSSize(width: 520, height: 620))
            win.center()
            settingsWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func screenParametersChanged() {
        notchController?.repositionPanel()
    }
}
