import SwiftUI

struct AboutTucknote: View {
    private enum StateOfCheck {
        case idle, checking, finished(Updates.Result), failed
    }

    @State private var state = StateOfCheck.idle
    @State private var check: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BrandMark()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tucknote").font(.title2.weight(.semibold))
                    Text(versionLabel).font(.callout).foregroundStyle(.secondary)
                }
            }
            Text("A little menu bar inbox for links, notes, and tasks.")
            Link("Tucknote on GitHub", destination: Updates.repository)
            Divider()
            HStack {
                Button("Check for Updates…", action: startCheck)
                    .disabled(check != nil || AppVersion.display == nil)
                if check != nil {
                    ProgressView().controlSize(.small).accessibilityLabel("Checking for updates")
                }
            }
            status
        }
        .padding(22)
        .frame(width: 420, alignment: .leading)
        .frame(minHeight: 215, alignment: .topLeading)
        .modifier(TucknoteSurface())
        .onDisappear { check?.cancel() }
    }

    private var versionLabel: String {
        guard let version = AppVersion.display else { return "Version unavailable" }
        guard let build = AppVersion.build else { return "Version \(version)" }
        return "Version \(version) (build \(build))"
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .idle:
            Text("Checks GitHub when you ask.").foregroundStyle(.secondary)
        case .checking:
            Text("Checking GitHub…").foregroundStyle(.secondary)
        case .finished(.noRelease):
            Text("No stable release has been published on GitHub yet.").foregroundStyle(.secondary)
        case .finished(.upToDate):
            Text("You’re up to date.").foregroundStyle(.secondary)
        case .finished(.newer(let version, let page, let appAvailable)):
            VStack(alignment: .leading, spacing: 6) {
                Text(appAvailable ? "Tucknote \(version) is available." : "Tucknote \(version) is available as source code.")
                Link(appAvailable ? "Open Release Downloads" : "View Release on GitHub", destination: page)
            }
        case .failed:
            Text("Couldn’t check GitHub. Try again in a moment.").foregroundStyle(.secondary)
        }
    }

    private func startCheck() {
        guard let current = AppVersion.display, check == nil else { return }
        state = .checking
        check = Task { @MainActor in
            defer { check = nil }
            do {
                let result = try await Updates.check(current: current)
                if !Task.isCancelled { state = .finished(result) }
            } catch {
                if !Task.isCancelled { state = .failed }
            }
        }
    }
}
