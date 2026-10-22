import Foundation
import Testing
@testable import CodexBarCore

struct ChatboxSettingsReaderTests {
    @Test(arguments: ["login", "manual"])
    func `both app activation methods resolve the selected key`(method: String) throws {
        let data = Data("""
        {"settings":{"licenseKey":" selected-key ","licenseActivationMethod":"\(method)",
        "memorizedManualLicenseKey":"old-manual-key","licenseDetail":{"key":"inspected-key"}}}
        """.utf8)
        let credential = try #require(ChatboxSettingsReader.parseCredential(data))
        #expect(credential.key == "selected-key")
        #expect(credential.source == (method == "login" ? "app-login" : "app-license"))
    }

    @Test(arguments: [
        "invalid", "[]", "{}", #"{"settings":null}"#,
        #"{"settings":{"licenseKey":123}}"#,
        #"{"settings":{"licenseKey":" \n "}}"#,
        #"{"settings":{"licenseKey":"key\nheader"}}"#,
        #"{"settings":{"licenseKey":"key","licenseActivationMethod":"unknown"}}"#,
        #"{"settings":{"licenseKey":"","memorizedManualLicenseKey":"stale-key"}}"#,
        #"{"settings":{"licenseDetail":{"key":"inspected-key"}}}"#,
    ])
    func `invalid or cleared credentials do not recover stale keys`(json: String) {
        #expect(ChatboxSettingsReader.parseCredential(Data(json.utf8)) == nil)
    }

    @Test
    func `legacy activation keeps the current key`() {
        #expect(ChatboxSettingsReader.parseCredential(Data(#"{"settings":{"licenseKey":"legacy-key"}}"#.utf8)) ==
            .init(key: "legacy-key", source: "app-license"))
        #expect(ChatboxSettingsReader.credential(environment: [:]) == nil)
    }

    @Test
    func `profile discovery stays scoped to the configured app file`() {
        let home = URL(fileURLWithPath: "/synthetic/chatbox-home")
        #expect(ChatboxSettingsReader.configurationURL(
            environment: ["CHATBOX_CONFIG_PATH": "~/profiles/chatbox.json"], homeDirectory: home)?.path ==
            "/synthetic/chatbox-home/profiles/chatbox.json")
        #expect(ChatboxSettingsReader.configurationURL(
            environment: ["CHATBOX_CONFIG_PATH": "relative.json"], homeDirectory: home) == nil)
        #if os(macOS)
        #expect(ChatboxSettingsReader.configurationURL(environment: [:], homeDirectory: home)?.path ==
            "/synthetic/chatbox-home/Library/Application Support/xyz.chatboxapp.app/config.json")
        #endif
    }

    @Test
    func `tests require an explicit profile even when HOME contains a valid app license`() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let relativePath = "Library/Application Support/xyz.chatboxapp.app/config.json"
        let file = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try #"{"settings":{"licenseKey":"synthetic-app-key","licenseActivationMethod":"login"}}"#
            .write(to: file, atomically: true, encoding: .utf8)

        let environment = ["HOME": directory.path]
        #expect(ChatboxSettingsReader.credential(environment: environment, fileURL: file)?.key == "synthetic-app-key")
        #expect(ChatboxSettingsReader.credential(environment: environment) == nil)
        for path in ["", " \n "] {
            #expect(ChatboxSettingsReader.credential(environment: [
                "HOME": directory.path, "CHATBOX_CONFIG_PATH": path,
            ]) == nil)
        }
        for path in [file.path, "~/\(relativePath)"] {
            #expect(ChatboxSettingsReader.credential(environment: [
                "HOME": directory.path, "CHATBOX_CONFIG_PATH": path,
            ])?.key == "synthetic-app-key")
        }
        #expect(ChatboxSettingsReader.credential(environment: [
            "HOME": directory.path, "CHATBOX_LICENSE_KEY": "synthetic-manual-key",
        ])?.key == "synthetic-manual-key")
    }

    @Test
    func `refresh follows app switches and clears without modifying the profile`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("config.json")
        let env = ["HOME": directory.path, "CHATBOX_CONFIG_PATH": file.path]
        let strategy = ChatboxProviderDescriptor.makeStrategy(transport: ProviderHTTPTransportHandler { request in
            #expect(request.url?.absoluteString == "https://api.chatboxai.app/api/license/detail/all_status")
            #expect(request.httpMethod == "GET")
            #expect(request.httpBody == nil)
            let key = request.value(forHTTPHeaderField: "Authorization")
            #expect(["Bearer login-key", "Bearer manual-key", "Bearer override-key"].contains(key ?? ""))
            let response = try #require(HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (Data(ChatboxPluginTests.fixture.utf8), response)
        })
        for (method, key, source) in [
            ("login", "login-key", "Chatbox app account"), ("manual", "manual-key", "Chatbox app license"),
        ] {
            let content = "{\"settings\":{\"licenseKey\":\"\(key)\",\"licenseActivationMethod\":\"\(method)\"}}"
            try content.write(to: file, atomically: true, encoding: .utf8)
            let context = ProviderCutoverTestSupport.context(environment: env)
            #expect(await strategy.isAvailable(context))
            let result = try await strategy.fetch(context)
            #expect(result.usage.details.first?.rows.last?.value == source)
            #expect(try String(contentsOf: file, encoding: .utf8) == content)
        }
        let overridden = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: env, provider: .chatbox, config: ProviderConfig(id: .chatbox, apiKey: "override-key"))
        let overrideResult = try await strategy.fetch(ProviderCutoverTestSupport.context(environment: overridden))
        #expect(overrideResult.usage.details.first?.rows.last?.value == "Manual key")
        let cleared = ProviderConfigEnvironment.applyAPIKeyOverride(
            base: env, provider: .chatbox, config: ProviderConfig(id: .chatbox, apiKey: ""))
        let automatic = try await strategy.fetch(ProviderCutoverTestSupport.context(environment: cleared))
        #expect(automatic.usage.details.first?.rows.last?.value == "Chatbox app license")
        try #"{"settings":{"licenseKey":"","memorizedManualLicenseKey":"old-key"}}"#
            .write(to: file, atomically: true, encoding: .utf8)
        #expect(await !strategy.isAvailable(ProviderCutoverTestSupport.context(environment: env)))
        #expect(await strategy.isAvailable(ProviderCutoverTestSupport.context(environment: overridden)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["config.json"])
    }

    @Test
    func `missing oversized and nonfile profiles stay unavailable`() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("config.json")
        let environment = ["HOME": directory.path, "CHATBOX_CONFIG_PATH": file.path]
        #expect(ChatboxSettingsReader.credential(environment: environment) == nil)
        #expect(ChatboxSettingsReader.credential(environment: environment, fileURL: directory) == nil)
        try Data(repeating: 32, count: 4 * 1024 * 1024 + 1).write(to: file)
        #expect(ChatboxSettingsReader.credential(environment: environment) == nil)
        #expect(ChatboxSettingsReader.credential(environment: environment.merging([
            "CHATBOX_LICENSE_KEY": "manual-override",
        ]) { _, new in new })?.key == "manual-override")
    }

    @Test
    func `malformed explicit keys never reach requests or fall back to an app license`() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("config.json")
        try #"{"settings":{"licenseKey":"valid-app-key","licenseActivationMethod":"login"}}"#
            .write(to: file, atomically: true, encoding: .utf8)
        for key in [
            "key\r\nInjected: header",
            "key with spaces",
            "key\u{0}suffix",
            String(repeating: "x", count: 4097),
        ] {
            let credential = ChatboxSettingsReader.credential(
                environment: ["CHATBOX_LICENSE_KEY": key], fileURL: file)
            #expect(credential == nil)
        }
        #expect(ChatboxSettingsReader.credential(environment: [:], fileURL: file)?.key == "valid-app-key")
    }

    @Test
    func `saved overrides are redacted and follow the explicit secret sync policy`() throws {
        let key = "synthetic-private-license-key"
        let provider = ProviderConfig(id: .chatbox, apiKey: key)
        let config = CodexBarConfig(providers: [provider])
        let dump = try #require(String(data: config.sanitizedForDump().encodedData(), encoding: .utf8))
        #expect(!dump.contains(key))
        #expect(dump.contains("[REDACTED]"))
        let intent = try CanonicalSyncJSON.string(ProviderIntentPayload(config: provider))
        #expect(!intent.contains(key))
        #expect(try ProviderIntentPayload.secretFields(for: provider, includeSecrets: false).isEmpty)
        #expect(try ProviderIntentPayload.secretFields(for: provider, includeSecrets: true)["apiKey"] == key)
        #expect(LogMetadata.secretSummary(key) == ["state": "set", "length": String(key.count)])
    }

    @Test
    func `registration supports automatic credentials and keeps other provider keys isolated`() {
        let descriptor = ChatboxProviderDescriptor.descriptor
        #expect(!descriptor.metadata.defaultEnabled)
        #expect(descriptor.fetchPlan.sourceModes == [.auto, .api])
        #expect(descriptor.credentials?.resolveToken(environment: ["OTHER_API_KEY": "other-key"]) == nil)
        #expect(descriptor.credentials?.resolveToken(environment: ["CHATBOX_LICENSE_KEY": " override "])?.token ==
            "override")
        let config = CodexBarConfig(providers: [ProviderConfig(id: .chatbox, source: .api)])
        #expect(!CodexBarConfigValidator.validate(config).contains { $0.code == "api_key_missing" })
    }
}
