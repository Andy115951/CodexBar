import CodexBarCore

struct ChatboxProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .chatbox
    private var shared: PluginAPIKeyProviderImplementation {
        PluginAPIKeyProviderImplementation(spec: ChatboxProviderDescriptor.spec)
    }

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation(showsVersionInSettings: false) { context in
            context.store.sourceLabel(for: context.provider)
        }
    }

    @MainActor
    func decorateSourceLabel(context: ProviderSourceLabelContext, baseLabel _: String) -> String {
        ChatboxDetailPresentation.sourceLabel(
            details: context.store.presentationSnapshot(for: self.id)?.details ?? [],
            localize: L)
    }

    func localizedDetails(_ details: [ProviderDetailSection]) -> [ProviderDetailSection]? {
        ChatboxDetailPresentation.localized(details, localize: L)
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        self.shared.observeSettings(settings)
    }

    @MainActor
    func isAvailable(context: ProviderAvailabilityContext) -> Bool {
        self.shared.isAvailable(context: context)
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        self.shared.settingsFields(context: context).map { field in
            var field = field
            field.footerText = context.statusText(Self.verificationStatusID)
            field.submission = .init(
                title: "Save and verify",
                resetTitle: "Restore automatic detection",
                perform: {
                    await Self.verify(context: context) {
                        await ProviderInteractionContext.$current.withValue(.userInitiated) {
                            await context.store.refreshProvider(
                                .chatbox, allowDisabled: true, coalesceIfRefreshing: true)
                        }
                    }
                })
            return field
        }
    }

    private static let verificationStatusID = "chatbox-key-verification"

    @MainActor
    static func verify(context: ProviderSettingsContext, refresh: () async -> Void) async {
        context.setStatusText(self.verificationStatusID, "Verifying Chatbox credentials…")
        let revision = context.settings.providerConfigRevision(for: .chatbox)
        let previousUpdatedAt = context.store.presentationSnapshot(for: .chatbox)?.updatedAt
        await refresh()
        // Saving the key also schedules a settings refresh. If that replaces this request,
        // join its pending result before judging the unchanged, cached balances as a failure.
        if !Task.isCancelled,
           context.settings.providerConfigRevision(for: .chatbox) == revision,
           context.store.presentationSnapshot(for: .chatbox)?.updatedAt == previousUpdatedAt,
           context.store.providerRefreshCoordinator.coalescingState(for: .chatbox) != nil
        {
            await refresh()
        }
        guard !Task.isCancelled,
              context.settings.providerConfigRevision(for: .chatbox) == revision
        else {
            context.setStatusText(
                Self.verificationStatusID,
                "Settings saved. Verification was interrupted; refresh to try again.")
            return
        }
        let snapshot = context.store.presentationSnapshot(for: .chatbox)
        let verified = context.store.error(for: .chatbox) == nil &&
            snapshot != nil && snapshot?.updatedAt != previousUpdatedAt
        context.setStatusText(
            Self.verificationStatusID,
            verified ? "Credentials verified. Usage refreshed." :
                "Settings saved. Verification failed; see the provider error above.")
    }
}
