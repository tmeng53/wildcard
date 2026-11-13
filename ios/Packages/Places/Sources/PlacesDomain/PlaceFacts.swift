import Contracts
import Foundation

/// What Apple Maps says of a place, read on the phone (Tracy, 2026-11-12: its phone and website
/// on every place's card): never sent to the server. Each is nil when Maps has none.
public struct PlaceFacts: Hashable, Sendable {
    /// The street address on one line, such as 「897 Broadway」.
    public var address: String?
    /// The phone number as Maps writes it, such as 「(212) 780-9300」.
    public var phone: String?
    public var website: URL?

    public init(address: String? = nil, phone: String? = nil, website: URL? = nil) {
        (self.address, self.phone, self.website) = (address, phone, website)
    }

    /// Where a tap on the phone capsule calls: its digits and a leading +.
    public var phoneURL: URL? {
        guard let phone else { return nil }
        let dialled = phone.filter { $0.isNumber || $0 == "+" }
        return dialled.isEmpty ? nil : URL(string: "tel:\(dialled)")
    }

    /// The website as the capsule says it: its host without `www.`, such as 「equinox.com」.
    public var websiteName: String? {
        guard let host = website?.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

extension Place {
    /// Apple Maps' page of the place (在地图中打开): by Maps' own id when it has one, so Maps shows
    /// its card; else its name at its spot.
    public var mapsLink: URL? {
        var parts = URLComponents(string: "https://maps.apple.com/place")
        parts?.queryItems =
            if let id = appleID {
                [URLQueryItem(name: "place-id", value: id)]
            } else {
                [
                    URLQueryItem(name: "name", value: name),
                    URLQueryItem(name: "coordinate", value: "\(latitude),\(longitude)"),
                ]
            }
        return parts?.url
    }
}
