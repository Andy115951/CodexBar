import Testing
@testable import CodexBar

@MainActor
struct ProviderSettingsFieldEditorTests {
    @Test
    func `typing remains a draft until submission commits the complete value`() throws {
        let editor = ProviderSettingsFieldEditor()
        var saved = "fixture-old-key"
        editor.edit("fixture-new-key")
        #expect(saved == "fixture-old-key")
        #expect(editor.value(savedValue: saved) == "fixture-new-key")
        #expect(editor.hasUnappliedChanges(savedValue: saved))

        saved = try #require(editor.beginSubmission(savedValue: saved))
        #expect(saved == "fixture-new-key")
        #expect(editor.isSubmitting)
        #expect(!editor.hasUnappliedChanges(savedValue: saved))
        editor.finishSubmission()
        #expect(!editor.isSubmitting)
    }

    @Test
    func `restore automatic clears both the saved override and an unfinished edit`() throws {
        let editor = ProviderSettingsFieldEditor()
        editor.edit("fixture-unfinished-key")
        let submitted = try #require(editor.beginSubmission(savedValue: "fixture-saved-key", reset: true))
        #expect(submitted.isEmpty)
        #expect(editor.value(savedValue: submitted).isEmpty)
    }

    @Test
    func `clearing the field is staged until explicitly submitted`() throws {
        let editor = ProviderSettingsFieldEditor()
        editor.edit("")
        #expect(editor.hasUnappliedChanges(savedValue: "fixture-saved-key"))
        let submitted = try #require(editor.beginSubmission(savedValue: "fixture-saved-key"))
        #expect(submitted.isEmpty)
    }

    @Test
    func `in flight verification blocks duplicate submissions and edits`() throws {
        let editor = ProviderSettingsFieldEditor()
        _ = try #require(editor.beginSubmission(savedValue: "fixture-key"))
        #expect(editor.beginSubmission(savedValue: "fixture-key", reset: true) == nil)
        editor.edit("fixture-other-key")
        #expect(editor.value(savedValue: "fixture-key") == "fixture-key")
        editor.finishSubmission()
        editor.edit("fixture-other-key")
        #expect(editor.value(savedValue: "fixture-key") == "fixture-other-key")
    }

    @Test
    func `external saved value changes discard a stale draft`() {
        let editor = ProviderSettingsFieldEditor()
        editor.edit("fixture-stale-draft")
        editor.savedValueChanged()
        #expect(editor.value(savedValue: "fixture-external-key") == "fixture-external-key")
    }
}
