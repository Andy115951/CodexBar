import Foundation

public enum ChatboxProviderDescriptor {
    public static let descriptor = Self.spec.makeDescriptor(
        credentials: Self.credentials,
        fetchPlan: ProviderFetchPlan(
            sourceModes: [.auto, .api],
            pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [Self.makeStrategy()] })))

    public static let spec = PluginProviderSpec(
        id: .chatbox,
        displayName: "Chatbox AI",
        sessionLabel: "Plan compute points",
        weeklyLabel: "Expansion pack",
        dashboardURL: "https://chatboxai.app",
        color: .init(hex: 0x4778F5),
        confetti: [0x4778F5, 0xA9C2FF],
        noDataMessage: "Chatbox AI cost history is not available.",
        history: .unavailable,
        burnDownWidgetSelectable: false,
        environmentKey: "CHATBOX_LICENSE_KEY",
        menuBarMetrics: .init(supported: [.automatic, .primary, .secondary]),
        apiKeyField: .init(
            id: "chatbox-license-key",
            title: "License key override",
            subtitle: "Click Save and verify or press Return to apply this key. "
                + "Leave empty or restore automatic detection to read Chatbox's current account or activated license. "
                + "Saved keys are stored in CodexBar's local config file.",
            placeholder: "Automatic from Chatbox"),
        availability: .configuredKey)

    private static let credentials = ProviderCredentialAdapter(
        supportsAPIKeyOverride: true,
        requiresAPIKeyForAPISource: false,
        environmentProjections: [.apiKey(Self.spec.environmentKey)],
        tokenResolver: { kind, environment, fileURL in
            guard kind == .primary,
                  let credential = ChatboxSettingsReader.credential(environment: environment, fileURL: fileURL)
            else { return nil }
            return ProviderTokenResolution(
                token: credential.key, source: credential.source == "manual" ? .environment : .authFile)
        },
        authDetector: { environment, _ in
            ChatboxSettingsReader.credential(environment: environment) == nil ? [] : ["api"]
        },
        missingCredentialMessage: { _ in
            "Open Chatbox and sign in or activate a license, or enter a license key in CodexBar Settings."
        })

    static func makeStrategy(transport: any ProviderHTTPTransport = ChatboxHTTPTransport()) -> ScriptFetchStrategy {
        ScriptFetchStrategy(
            id: "chatbox.js",
            provider: .chatbox,
            bundledPlugin: "chatbox",
            secretKey: self.spec.environmentKey,
            sourceLabel: "api",
            transport: transport,
            resolveValues: { context in
                guard let credential = ChatboxSettingsReader.credential(environment: context.env) else { return nil }
                return .init(
                    settings: ["CHATBOX_AUTH_SOURCE": credential.source],
                    secrets: [Self.spec.environmentKey: credential.key])
            },
            isEnabled: { _ in true })
    }
}
