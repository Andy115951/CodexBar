import Testing
@testable import CodexBarCore

struct ChatboxDetailPresentationTests {
    @Test(arguments: [
        ("Chatbox app account", "Account login"),
        ("Chatbox app license", "License activation"),
        ("Manual key", "Manual key"),
    ])
    func `source labels distinguish activation methods while retaining the API channel`(
        source: String,
        title: String) throws
    {
        let details = try [ProviderDetailSection(rows: [
            ProviderDetailSection.Row(label: "Credential source", value: source),
        ])]
        let label = ChatboxDetailPresentation.sourceLabel(details: details) { "translated:\($0)" }
        #expect(label == "translated:\(title) · API")
    }

    @Test
    func `missing or unknown credential sources never guess an activation method`() throws {
        let unknown = try ProviderDetailSection(rows: [
            ProviderDetailSection.Row(label: "Credential source", value: "unrecognized-private-value"),
        ])
        let unrelated = try ProviderDetailSection(rows: [
            ProviderDetailSection.Row(label: "Other", value: "Chatbox app account"),
        ])
        for details in [[], [unknown], [unrelated]] {
            #expect(ChatboxDetailPresentation.sourceLabel(details: details, localize: { $0 }) == "API")
        }
    }

    @Test
    func `canonical labels and known values localize without changing quota data`() throws {
        let rows = try [
            ProviderDetailSection.Row(label: "Plan compute points", value: "7,500 / 10,000", usageValue: 2500),
            ProviderDetailSection.Row(label: "License status", value: "active"),
            ProviderDetailSection.Row(label: "Credential source", value: "Chatbox app license"),
        ]
        let section = try ProviderDetailSection(title: "Remaining quota", rows: rows)
        let translations = [
            "Quota and license information": "额度与授权信息",
            "Plan compute points": "套餐计算点数",
            "License status": "授权状态",
            "Activated": "已激活",
            "Credential source": "凭证来源",
            "Chatbox app license": "Chatbox 应用内 License 激活",
        ]
        let result = try #require(ChatboxDetailPresentation.localized([section]) { translations[$0] ?? $0 }.first)
        #expect(result.title == "额度与授权信息")
        #expect(result.rows.map(\.label) == ["套餐计算点数", "授权状态", "凭证来源"])
        #expect(result.rows.map(\.value) == [
            "7,500 / 10,000", "已激活", "Chatbox 应用内 License 激活",
        ])
        #expect(result.rows.first?.usageValue == 2500)
        #expect(result.rows.first?.id == rows.first?.id)
    }

    @Test(arguments: ["Chatbox app account", "Chatbox app license", "Manual key"])
    func `both app activation paths and manual override have localizable sources`(source: String) throws {
        let row = try ProviderDetailSection.Row(label: "Credential source", value: source)
        let section = try ProviderDetailSection(rows: [row])
        let localized = ChatboxDetailPresentation.localized([section]) { "translated:\($0)" }
        #expect(localized.first?.rows.first?.value == "translated:\(source)")
    }

    @Test
    func `unknown statuses and unrelated values remain unchanged`() throws {
        let rows = try [
            ProviderDetailSection.Row(label: "License status", value: "future-status"),
            ProviderDetailSection.Row(label: "Credential source", value: "future-source"),
            ProviderDetailSection.Row(label: "Other", value: "active"),
        ]
        let section = try ProviderDetailSection(rows: rows)
        let localized = ChatboxDetailPresentation.localized([section]) { "translated:\($0)" }
        #expect(localized.first?.rows.map(\.value) == ["future-status", "future-source", "active"])
    }
}
