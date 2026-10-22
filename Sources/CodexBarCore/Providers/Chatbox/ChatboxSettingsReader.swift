import Foundation

public enum ChatboxSettingsReader {
    struct Credential: Equatable, Sendable {
        let key: String
        let source: String
    }

    private struct Configuration: Decodable {
        struct Settings: Decodable {
            let licenseKey: String?
            let licenseActivationMethod: String?
        }

        let settings: Settings
    }

    static func credential(environment: [String: String], fileURL: URL? = nil) -> Credential? {
        if let key = ChatboxProviderDescriptor.spec.apiKey(environment: environment) {
            guard self.isValidKey(key) else { return nil }
            return Credential(key: key, source: "manual")
        }
        // HOME is inherited by ordinary test runs, so it does not prove the profile is contained.
        // Tests must explicitly select a profile instead of discovering desktop credentials.
        guard !TestProcessSafety.isRunning || fileURL != nil ||
            SettingsValue.cleaned(environment["CHATBOX_CONFIG_PATH"]) != nil,
            let file = fileURL ?? self.configurationURL(environment: environment),
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true,
            let handle = try? FileHandle(forReadingFrom: file)
        else { return nil }
        defer { try? handle.close() }
        let maximumSize = 4 * 1024 * 1024
        guard let data = try? handle.read(upToCount: maximumSize + 1), data.count <= maximumSize else { return nil }
        return self.parseCredential(data)
    }

    static func configurationURL(
        environment: [String: String],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL?
    {
        let home = SettingsValue.cleaned(environment["HOME"]).map { URL(fileURLWithPath: $0) } ?? homeDirectory
        if let path = SettingsValue.cleaned(environment["CHATBOX_CONFIG_PATH"]) {
            if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2))) }
            guard path.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: path)
        }
        #if os(macOS)
        return home.appendingPathComponent("Library/Application Support/xyz.chatboxapp.app/config.json")
        #else
        return nil
        #endif
    }

    static func parseCredential(_ data: Data) -> Credential? {
        guard let settings = try? JSONDecoder().decode(Configuration.self, from: data).settings,
              let key = settings.licenseKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              self.isValidKey(key)
        else { return nil }
        switch settings.licenseActivationMethod {
        case "login": return Credential(key: key, source: "app-login")
        case "manual", nil: return Credential(key: key, source: "app-license")
        default: return nil
        }
    }

    private static func isValidKey(_ key: String) -> Bool {
        !key.isEmpty && key.utf8.count <= 4096 &&
            key.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil
    }
}
