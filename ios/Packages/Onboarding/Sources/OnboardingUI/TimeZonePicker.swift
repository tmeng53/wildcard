#if os(iOS)
import DesignSystem
import DesignSystemUI
import Foundation
import SwiftUI

/// A time zone as the 比赛时区 row and its list name it: its region's name in the app's language
/// (北美东部时间) and the city it is named after (New York).
struct ZoneName: Identifiable, Hashable {
    let id: String
    let region: String
    let city: String
    /// Seconds ahead of UTC now, for the list's order.
    let offset: Int

    init(_ identifier: String, locale: Locale, now: Date = .now) {
        let zone = TimeZone(identifier: identifier)
        id = identifier
        city = identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? identifier
        region = zone?.localizedName(for: .generic, locale: locale) ?? city
        offset = zone?.secondsFromGMT(for: now) ?? 0
    }

    /// Every zone named after a city, west to east, then by name. `Etc/…` and bare names
    /// (`UTC`) are left out: nobody lives in them.
    static func all(locale: Locale) -> [ZoneName] {
        TimeZone.knownTimeZoneIdentifiers
            .filter { $0.contains("/") && !$0.hasPrefix("Etc/") }
            .map { ZoneName($0, locale: locale) }
            .sorted { ($0.offset, $0.region, $0.city) < ($1.offset, $1.region, $1.city) }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [region, city, id].contains { $0.localizedStandardContains(query) }
    }
}

/// 比赛时区: every time zone in the system's list with search, the picked one ticked, for a
/// sheet. One pick closes it: the caller dismisses the sheet in `pick`.
struct TimeZonePicker: View {
    let selected: String
    let pick: (String) -> Void
    @Environment(\.sceneTheme) private var theme
    @State private var query = ""
    @State private var zones: [ZoneName] = []

    var body: some View {
        NavigationStack {
            List(shown) { zone in
                Button {
                    pick(zone.id)
                } label: {
                    HStack(spacing: Space.s) {
                        VStack(alignment: .leading, spacing: Space.xxs / 2) {
                            Text(verbatim: zone.region)
                                .typeStyle(TypeRamp.body)
                                .foregroundStyle(Color(role: .fgDefault, in: theme))
                            Text(verbatim: zone.city)
                                .typeStyle(TypeRamp.footnote)
                                .foregroundStyle(Color(role: .fgMuted, in: theme))
                        }
                        Spacer(minLength: Space.xs)
                        if zone.id == selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: Sizing.smallIcon, weight: .semibold))
                                .foregroundStyle(Color(role: .fgDefault, in: theme))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(zone.id == selected ? .isSelected : [])
                .accessibilityIdentifier("squad.timeZone.\(zone.id)")
            }
            .listStyle(.plain)
            .searchable(
                text: $query, placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("搜索城市或时区", bundle: .module)
            )
            .navigationTitle(Text("比赛时区", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            // Some 400 names in the app's language: off the main actor, so the sheet slides up smoothly.
            let locale = AppLanguage.current.locale
            zones = await Task.detached { ZoneName.all(locale: locale) }.value
        }
    }

    /// The picked zone first, then every one the search finds.
    private var shown: [ZoneName] {
        let found = zones.filter { $0.matches(query) }
        guard query.isEmpty, let current = found.first(where: { $0.id == selected }) else { return found }
        return [current] + found.filter { $0.id != selected }
    }
}
#endif
