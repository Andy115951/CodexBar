import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct ChatboxProviderPresentationTests {
    @Test
    func `manual credential fields expose explicit save and automatic restore actions`() throws {
        let fixture = try ProviderSettingsDescriptorTests().makeSettingsFixture(suite: "Chatbox-save-actions")
        let context = fixture.settingsContext(provider: .chatbox)
        let field = try #require(ChatboxProviderImplementation().settingsFields(context: context).first)
        let submission = try #require(field.submission)
        #expect(submission.title == "Save and verify")
        #expect(submission.resetTitle == "Restore automatic detection")
    }

    @Test
    func `verification rejects cached balances and reports newly refreshed usage`() async throws {
        let fixture = try ProviderSettingsDescriptorTests().makeSettingsFixture(suite: "Chatbox-verify-outcome")
        let context = fixture.settingsContext(provider: .chatbox)
        let implementation = ChatboxProviderImplementation()
        let oldDate = Date(timeIntervalSince1970: 1_792_454_400)
        fixture.store.snapshots[.chatbox] = UsageSnapshot(primary: nil, secondary: nil, updatedAt: oldDate)

        await ChatboxProviderImplementation.verify(context: context, refresh: {})
        #expect(implementation.settingsFields(context: context).first?.footerText ==
            "Settings saved. Verification failed; see the provider error above.")

        await ChatboxProviderImplementation.verify(context: context) {
            fixture.store.snapshots[.chatbox] = UsageSnapshot(
                primary: nil, secondary: nil, updatedAt: oldDate.addingTimeInterval(1))
        }
        #expect(implementation.settingsFields(context: context).first?.footerText ==
            "Credentials verified. Usage refreshed.")
    }

    @Test
    func `verification joins a settings refresh that replaced its request`() async throws {
        let fixture = try ProviderSettingsDescriptorTests().makeSettingsFixture(suite: "Chatbox-verify-replacement")
        let context = fixture.settingsContext(provider: .chatbox)
        let oldDate = Date(timeIntervalSince1970: 1_792_454_400)
        fixture.store.snapshots[.chatbox] = UsageSnapshot(primary: nil, secondary: nil, updatedAt: oldDate)
        var replacement: ProviderRefreshTaskState?
        var refreshCount = 0

        await ChatboxProviderImplementation.verify(context: context) {
            refreshCount += 1
            if refreshCount == 1 {
                let request = fixture.store.providerRefreshCoordinator.beginReplacingRequest(for: .chatbox)
                request.state.install(task: Task {})
                replacement = request.state
            } else {
                fixture.store.snapshots[.chatbox] = UsageSnapshot(
                    primary: nil, secondary: nil, updatedAt: oldDate.addingTimeInterval(1))
                if let replacement {
                    fixture.store.providerRefreshCoordinator.complete(replacement, for: .chatbox, retryRequired: false)
                }
            }
        }

        #expect(refreshCount == 2)
        #expect(ChatboxProviderImplementation().settingsFields(context: context).first?.footerText ==
            "Credentials verified. Usage refreshed.")
    }

    @Test
    func `a rejected override is retained without falling back to app credentials`() async throws {
        let fixture = try ProviderSettingsDescriptorTests().makeSettingsFixture(suite: "Chatbox-verify-rejection")
        let context = fixture.settingsContext(provider: .chatbox)
        fixture.settings[providerConfig: .chatbox, field: .apiKey] = "fixture-manual-key"
        var refreshCount = 0

        await ChatboxProviderImplementation.verify(context: context) {
            refreshCount += 1
            fixture.store.errors[.chatbox] = "fixture-authentication-error"
        }

        #expect(refreshCount == 1)
        #expect(fixture.settings[providerConfig: .chatbox, field: .apiKey] == "fixture-manual-key")
        #expect(ChatboxProviderImplementation().settingsFields(context: context).first?.footerText ==
            "Settings saved. Verification failed; see the provider error above.")
    }

    @Test
    func `verification does not echo errors or validate a changed configuration`() async throws {
        let fixture = try ProviderSettingsDescriptorTests().makeSettingsFixture(suite: "Chatbox-verify-scope")
        let context = fixture.settingsContext(provider: .chatbox)
        let implementation = ChatboxProviderImplementation()

        await ChatboxProviderImplementation.verify(context: context) {
            fixture.store.errors[.chatbox] = "fixture-private-error"
        }
        #expect(implementation.settingsFields(context: context).first?.footerText ==
            "Settings saved. Verification failed; see the provider error above.")

        await ChatboxProviderImplementation.verify(context: context) {
            fixture.settings[providerConfig: .chatbox, field: .apiKey] = "fixture-new-key"
            fixture.store.errors[.chatbox] = nil
            fixture.store.snapshots[.chatbox] = UsageSnapshot(primary: nil, secondary: nil, updatedAt: Date())
        }
        #expect(implementation.settingsFields(context: context).first?.footerText ==
            "Settings saved. Verification was interrupted; refresh to try again.")
    }

    @Test
    func `chatbox source and subtitle follow the displayed snapshot activation method`() throws {
        let fixture = try ProviderSettingsDescriptorTests()
            .makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-chatbox-presentation")
        let metadata = try #require(ProviderDescriptorRegistry.metadata[.chatbox])
        let context = fixture.presentationContext(provider: .chatbox, metadata: metadata)
        let implementation = try #require(ProviderCatalog.implementation(for: .chatbox))

        let presentation = implementation.presentation(context: context)

        #expect(presentation.detailLine(context) == "API")
        #expect(presentation.showsVersionInSettings == false)
        for (source, title) in [
            ("Chatbox app account", "Account login"),
            ("Chatbox app license", "License activation"),
            ("Manual key", "Manual key"),
        ] {
            fixture.store.snapshots[.chatbox] = try UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date(),
                details: [ProviderDetailSection(rows: [
                    ProviderDetailSection.Row(label: "Credential source", value: source),
                ])])
            #expect(fixture.store.sourceLabel(for: .chatbox) == "\(L(title)) · API")
            #expect(presentation.detailLine(context) == fixture.store.sourceLabel(for: .chatbox))
        }
    }
}
