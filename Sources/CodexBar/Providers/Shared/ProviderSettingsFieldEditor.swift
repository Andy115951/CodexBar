import Observation

/// Keeps edits in memory until a field's explicit submission action commits them.
@MainActor
@Observable
final class ProviderSettingsFieldEditor {
    private var draft: String?
    private(set) var isSubmitting = false

    func value(savedValue: String) -> String {
        self.draft ?? savedValue
    }

    func edit(_ value: String) {
        guard !self.isSubmitting else { return }
        self.draft = value
    }

    func hasUnappliedChanges(savedValue: String) -> Bool {
        self.value(savedValue: savedValue) != savedValue
    }

    func beginSubmission(savedValue: String, reset: Bool = false) -> String? {
        guard !self.isSubmitting else { return nil }
        let value = reset ? "" : self.value(savedValue: savedValue)
        self.isSubmitting = true
        self.draft = nil
        return value
    }

    func savedValueChanged() {
        self.draft = nil
    }

    func finishSubmission() {
        self.isSubmitting = false
    }
}
