import SwiftUI

@MainActor
final class CaptureDraft: ObservableObject {
    @Published var input = ""
    @Published var category: Category?
    @Published private(set) var waitingCount = 0
    private var incoming: [String] = []

    /// Stages incoming text for review, keeping an existing draft intact.
    @discardableResult
    func receive(_ text: String) -> Bool {
        guard let text = CaptureInput.validate(text) else { return false }
        if input == text || incoming.contains(text) { return true }
        guard incoming.count < 10 else { return false }
        incoming.append(text)
        waitingCount = incoming.count
        showNextIfEmpty()
        return true
    }

    func clearAndAdvance() {
        input = ""
        category = nil
        showNextIfEmpty()
    }

    func showNextIfEmpty() {
        guard input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let next = incoming.first else { return }
        incoming.removeFirst()
        waitingCount = incoming.count
        category = nil
        input = next
    }
}
