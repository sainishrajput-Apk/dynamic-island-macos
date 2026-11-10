import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = IslandController()
    private var statusItem: NSStatusItem?
    private var lockItem: NSMenuItem?
    private var breakItem: NSMenuItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
        buildMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Dynamic Island")
        let menu = NSMenu()
        menu.delegate = self

        let lock = NSMenuItem(title: "Lock Position", action: #selector(toggleLock), keyEquivalent: "")
        lock.target = self; menu.addItem(lock); lockItem = lock

        let brk = NSMenuItem(title: "Break Reminders", action: #selector(toggleBreaks), keyEquivalent: "")
        brk.target = self; menu.addItem(brk); breakItem = brk

        let reset = NSMenuItem(title: "Reset Position", action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self; menu.addItem(reset)

        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self; menu.addItem(prefs)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Dynamic Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        lockItem?.state = Settings.shared.positionLocked ? .on : .off
        breakItem?.state = Settings.shared.breakEnabled ? .on : .off
    }

    @objc private func toggleBreaks() { Settings.shared.breakEnabled.toggle() }

    @objc private func toggleLock() { Settings.shared.positionLocked.toggle() }

    @objc private func resetPosition() {
        NotificationCenter.default.post(name: .resetPositionRequested, object: nil)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: Settings.shared)))
            w.title = "Dynamic Island Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                self?.settingsWindow = nil           // free the window's memory when closed
            }
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
