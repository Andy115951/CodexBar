import Foundation

public enum ChatboxDetailPresentation {
    /// Use the credential source from the same snapshot as the displayed balances.
    public static func sourceLabel(
        details: [ProviderDetailSection],
        localize: (String) -> String) -> String
    {
        let source = details.flatMap(\.rows).first { $0.label == "Credential source" }?.value
        let title: String
        switch source {
        case "Chatbox app account": title = "Account login"
        case "Chatbox app license": title = "License activation"
        case "Manual key": title = "Manual key"
        default: return "API"
        }
        return "\(localize(title)) · API"
    }

    public static func localized(
        _ details: [ProviderDetailSection],
        localize: (String) -> String) -> [ProviderDetailSection]
    {
        details.compactMap { section in
            let rows = section.rows.compactMap { row in
                let value = switch row.label {
                case "License status": self.status(row.value).map(localize) ?? row.value
                case "Credential source": self.source(row.value).map(localize) ?? row.value
                default: row.value
                }
                return try? ProviderDetailSection.Row(
                    id: row.id,
                    label: localize(row.label),
                    value: value,
                    secondaryValue: row.secondaryValue,
                    progress: row.progress,
                    severity: row.severity,
                    usageValue: row.usageValue)
            }
            // Preserve the canonical section title used by saved visibility preferences.
            let title = section.title.map { localize($0 == "Remaining quota" ? "Quota and license information" : $0) }
            return try? ProviderDetailSection(title: title, rows: rows, chart: section.chart)
        }
    }

    private static func status(_ value: String) -> String? {
        switch value {
        case "active": "Activated"
        case "inactive": "Inactive"
        case "expired": "Expired"
        case "disabled": "Disabled"
        case "refunding": "Refunding"
        case "refunded": "Refunded"
        default: nil
        }
    }

    private static func source(_ value: String) -> String? {
        switch value {
        case "Chatbox app account", "Chatbox app license", "Manual key": value
        default: nil
        }
    }
}
