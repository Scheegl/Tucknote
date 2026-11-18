import AppKit
import Carbon
import SwiftUI

@main
enum TucknoteApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let controller = Controller()
        app.delegate = controller
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(controller) { app.run() }
    }
}

extension Notification.Name {
    static let focusCapture = Notification.Name("Tucknote.focusCapture")
}

@MainActor
final class Controller: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var popover: NSPopover?
    private let inbox = Inbox()
    private let preferences = Preferences()
    private var inboxWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var hotkey: Hotkey?
    private var pasteMonitor: Any?
    private let navigation = InboxNavigation()
    private let draft = CaptureDraft()

    private lazy var statusMenu: NSMenu = {
        let menu = NSMenu()
        for (title, action) in [("Open Inbox", #selector(openInbox)),
                                ("Refresh Link Titles", #selector(refreshLinkTitles)),
                                ("Settings…", #selector(openSettings)),
                                ("Quit Tucknote", #selector(quit))] {
            if action == #selector(quit) { menu.addItem(.separator()) }
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
        }
        return menu
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = Brand.mark()
        statusItem.button?.setAccessibilityLabel("Tucknote")
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.control, .command, .option, .shift])
            guard modifiers == .control,
                  event.keyCode == UInt16(kVK_ANSI_V) || event.charactersIgnoringModifiers?.lowercased() == "v"
            else { return event }
            return NSEvent.keyEvent(with: .keyDown, location: event.locationInWindow,
                                    modifierFlags: .command, timestamp: event.timestamp,
                                    windowNumber: event.windowNumber, context: nil,
                                    characters: "v", charactersIgnoringModifiers: "v",
                                    isARepeat: event.isARepeat, keyCode: event.keyCode) ?? event
        }
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        inbox.onChange = { [weak self] in self?.updateCounter() }
        preferences.onChange = { [weak self] in self?.applyPreferences() }
        applyPreferences()
        hotkey = Hotkey { [weak self] in self?.showCapture() }
        preferences.hotkeyAvailable = hotkey != nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showCapture()
        return false
    }

    private func applyPreferences() {
        popover?.appearance = preferences.appearance.native
        inboxWindow?.appearance = preferences.appearance.native
        settingsWindow?.appearance = preferences.appearance.native
        updateCounter()
    }

    private func installEditMenu() {
        guard NSApp.mainMenu == nil else { return }
        let main = NSMenu()
        let application = NSMenuItem()
        let appMenu = NSMenu(title: "Tucknote")
        appMenu.addItem(withTitle: "Quit Tucknote", action: #selector(quit), keyEquivalent: "q").target = self
        application.submenu = appMenu
        main.addItem(application)
        let edit = NSMenuItem()
        let menu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a")
        ] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        edit.submenu = menu
        main.addItem(edit)
        NSApp.mainMenu = main
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
    }

    private func updateCounter() {
        statusItem.button?.title = preferences.showCount ? " \(inbox.count)" : ""
        statusItem.button?.toolTip = "Tucknote · \(inbox.count) in Inbox · Right-click for menu"
    }

    @objc private func toggle() {
        let event = NSApp.currentEvent
        if let button = statusItem.button,
           event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            popover?.close()
            let edge = button.isFlipped ? button.bounds.maxY : button.bounds.minY
            statusMenu.popUp(positioning: nil, at: NSPoint(x: button.bounds.minX, y: edge), in: button)
        } else if popover?.isShown == true {
            popover?.close()
        } else {
            showCapture()
        }
    }

    private func showCapture() {
        guard let button = statusItem.button else { return }
        installEditMenu()
        let capture = popover ?? makeCapture()
        if !capture.isShown {
            capture.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        activate()
        capture.contentViewController?.view.window?.makeKey()
        NotificationCenter.default.post(name: .focusCapture, object: nil)
    }

    private func makeCapture() -> NSPopover {
        let capture = NSPopover()
        capture.behavior = .transient
        capture.delegate = self
        capture.appearance = preferences.appearance.native
        capture.contentViewController = NSHostingController(rootView: CaptureView(
            inbox: inbox,
            draft: draft,
            openInbox: { [weak self] in self?.openInbox() },
            navigate: { [weak self] destination in
                self?.navigation.destination = destination
                self?.openInbox()
            },
            openSettings: { [weak self] in self?.openSettings() }
        ))
        popover = capture
        return capture
    }

    func popoverDidClose(_ notification: Notification) {
        if let closed = notification.object as? NSPopover, closed === popover {
            popover = nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === inboxWindow {
            inboxWindow = nil
            navigation.destination = nil
        }
        if window === settingsWindow { settingsWindow = nil }
    }

    @objc private func refreshLinkTitles() { inbox.refreshLinkTitles() }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openInbox() {
        if inboxWindow == nil {
            inboxWindow = makeWindow(title: "Tucknote", view: InboxWindow(inbox: inbox, navigation: navigation), size: NSSize(width: 780, height: 490))
        }
        show(inboxWindow)
    }

    @objc private func openSettings() {
        preferences.refreshLogin()
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Tucknote Settings", view: PreferencesView(preferences: preferences),
                                        size: NSSize(width: 420, height: 320))
        }
        show(settingsWindow)
    }

    private func activate() {
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func show(_ window: NSWindow?) {
        installEditMenu()
        popover?.close()
        activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow<V: View>(title: String, view: V, size: NSSize) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.appearance = preferences.appearance.native
        window.setContentSize(size)
        window.center()
        return window
    }
}
