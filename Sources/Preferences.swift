import AppKit
import ServiceManagement
import SwiftUI

enum Appearance: String, CaseIterable {
    case system = "System", light = "Light", dark = "Dark"

    var native: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    @Published var showCount = UserDefaults.standard.object(forKey: "showCount") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showCount, forKey: "showCount")
            onChange?()
        }
    }
    @Published var appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            onChange?()
        }
    }
    @Published var hotkeyAvailable = true
    @Published private(set) var loginStatus = SMAppService.Status.notRegistered
    @Published private(set) var loginError: String?
    var onChange: (() -> Void)?

    func refreshLogin() {
        loginStatus = SMAppService.mainApp.status
    }

    func setLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            loginError = error.localizedDescription
        }
        refreshLogin()
    }
}

struct PreferencesView: View {
    @ObservedObject var preferences: Preferences
    let openAbout: () -> Void
    @AppStorage(Inbox.automaticTitlesKey) private var automaticTitles = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                BrandMark()
                Text("Settings").font(.system(.title2, design: .rounded, weight: .semibold))
            }
            Picker("Appearance", selection: $preferences.appearance) {
                ForEach(Appearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Open at login", isOn: Binding(
                get: { preferences.loginStatus == .enabled || preferences.loginStatus == .requiresApproval },
                set: { preferences.setLogin($0) }
            ))
            if preferences.loginStatus == .requiresApproval {
                Button("Approve in System Settings") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let error = preferences.loginError {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Show inbox count in menu bar", isOn: $preferences.showCount)
            Toggle("Fetch link titles automatically", isOn: $automaticTitles)
                .help("Contacts the HTTPS sites you save. Refresh Link Titles is available on demand.")
            Divider()
            Text(preferences.hotkeyAvailable ? "Quick capture: Control + Option + Space" :
                    "Shortcut unavailable. Use the menu bar icon.")
            Text("Paste with Command + V or Control + V.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Select with Up or Down. Return edits. Command + Shift + A archives.")
                .font(.callout).foregroundStyle(.secondary)
            Button("About Tucknote…", action: openAbout)
        }
        .padding(22).frame(width: 420, alignment: .leading)
        .modifier(TucknoteSurface())
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            preferences.refreshLogin()
        }
    }
}
