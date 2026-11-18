import AppKit
import Carbon
import SwiftUI

enum InboxDestination {
    case entry(UUID)
    case source(String)
}

@MainActor
final class InboxNavigation: ObservableObject {
    @Published var destination: InboxDestination?
}

struct EntryKeyboard: NSViewRepresentable {
    var handle: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyScope { KeyScope() }

    func updateNSView(_ view: KeyScope, context: Context) {
        view.handle = handle
    }

    static func dismantleNSView(_ view: KeyScope, coordinator: ()) {
        view.stopMonitoring()
    }

    final class KeyScope: NSView {
        var handle: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, window.isKeyWindow,
                      event.window === window, self.handle?(event) == true else { return event }
                return nil
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }

    static func handle(_ event: NSEvent, entries: [Entry], selected: Binding<UUID?>,
                       focusList: () -> Void, edit: (Entry) -> Void, archive: (Entry) -> Void) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = Int(event.keyCode)
        let currentIndex = entries.firstIndex { $0.id == selected.wrappedValue }
        if modifiers.isEmpty, key == kVK_UpArrow || key == kVK_DownArrow {
            guard !entries.isEmpty else { return false }
            let down = key == kVK_DownArrow
            let index = currentIndex.map { min(max($0 + (down ? 1 : -1), 0), entries.count - 1) }
                ?? (down ? 0 : entries.count - 1)
            focusList()
            selected.wrappedValue = entries[index].id
            return true
        }
        guard let currentIndex else { return false }
        let entry = entries[currentIndex]
        if modifiers.isEmpty, [kVK_Return, kVK_ANSI_KeypadEnter].contains(key) {
            if !event.isARepeat { edit(entry) }
            return true
        }
        if modifiers == [.command, .shift], key == kVK_ANSI_A, entry.status == .inbox {
            if !event.isARepeat { archive(entry) }
            return true
        }
        if modifiers.isEmpty, key == kVK_Escape {
            selected.wrappedValue = nil
            return true
        }
        return false
    }
}
