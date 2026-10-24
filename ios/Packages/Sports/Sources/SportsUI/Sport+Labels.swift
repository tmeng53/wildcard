#if os(iOS)
import Contracts
import Foundation
import SwiftUI
import UIKit

extension Sport {
    /// The sport's names, icon and category in the app's list; nil for a sport the list doesn't
    /// have yet (one added on the server since the list was read).
    public var entry: SportCatalog.Entry? { SportList.shared.catalog.entry(for: self) }

    /// The name people see.
    public var name: Text { Text(verbatim: localizedName) }

    /// The name as a string, in the app's language.
    public var localizedName: String {
        entry?.names.localized ?? Bundle.module.localizedString(forKey: "sport.unknown", value: nil, table: nil)
    }

    /// The name on a card or poster row, where a long one would clip: the list's short name, else
    /// the name.
    public var cardName: Text {
        Text(verbatim: entry?.shortNames?.localized ?? localizedName)
    }

    /// The SF Symbol drawn beside the name: the list's, when this iOS has it.
    public var symbol: String {
        guard let icon = entry?.icon, UIImage(systemName: icon) != nil else { return Self.generalSymbol }
        return icon
    }

    /// For a sport whose own symbol this iOS lacks, and for sports people name themselves.
    static let generalSymbol = "figure.mixed.cardio"
}

extension SportCatalog.Category {
    public var name: Text { Text(verbatim: names.localized) }
}

extension Activity {
    public var name: Text {
        switch self {
        case .sport(let sport): sport.name
        case .custom(let custom): Text(verbatim: custom.name)
        }
    }

    /// The name for a card or poster row: short where the full name is long.
    public var cardName: Text {
        switch self {
        case .sport(let sport): sport.cardName
        case .custom(let custom): Text(verbatim: custom.name)
        }
    }

    public var symbol: String {
        switch self {
        case .sport(let sport): sport.symbol
        case .custom: Sport.generalSymbol
        }
    }

    /// The name as plain text, for lines that join several.
    public var localizedName: String {
        switch self {
        case .sport(let sport): sport.localizedName
        case .custom(let custom): custom.name
        }
    }

    /// A stable key for identifiers and `ForEach`.
    public var key: String {
        switch self {
        case .sport(let sport): sport.rawValue
        case .custom(let custom): "custom.\(custom.name)"
        }
    }
}
#endif
