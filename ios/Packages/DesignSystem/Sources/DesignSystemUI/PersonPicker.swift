#if canImport(SwiftUI)
import DesignSystem
import Foundation
import SwiftUI

/// The @ list over a composer (提到谁): one row per person, a head, the name and the 教练 tag for
/// a coach, the first row marked as the one a tap picks. A solid white card with a hairline and a
/// soft shadow, as the approved comment design draws it (the composer under it is the glass). At
/// most four and a half rows show; more scroll. The caller draws the heads (`AvatarUI` is above
/// this package).
public struct PersonPicker<Person: Identifiable, Head: View>: View {
    @Environment(\.sceneTheme) private var theme
    private let people: [Person]
    private let name: (Person) -> String
    private let isCoach: (Person) -> Bool
    private let head: (Person) -> Head
    private let identifier: String
    private let pick: (Person) -> Void

    private static var row: Double { 40 }
    private static var visibleRows: Double { 4.5 }
    private static var inset: Double { Space.xxs + 2 }
    private static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous) }

    public init(
        _ people: [Person], name: @escaping (Person) -> String, isCoach: @escaping (Person) -> Bool,
        identifier: String, @ViewBuilder head: @escaping (Person) -> Head, pick: @escaping (Person) -> Void
    ) {
        self.people = people
        self.name = name
        self.isCoach = isCoach
        self.head = head
        self.identifier = identifier
        self.pick = pick
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    Button {
                        pick(person)
                    } label: {
                        HStack(spacing: Space.s - 2) {
                            head(person)
                            Text(verbatim: name(person))
                                .typeStyle(TypeRamp.body)
                                .foregroundStyle(Color(role: .fgDefault, in: theme))
                                .lineLimit(1)
                            if isCoach(person) { CoachTag(.small) }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Space.xs)
                        .frame(height: Self.row)
                        .background {
                            if index == 0 {
                                RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
                                    .fill(Color(role: .bgSubtle, in: theme))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("\(identifier).\(index)")
                }
            }
            .padding(Self.inset)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The list belongs to the box being typed in: touching or scrolling it keeps the keyboard up.
        .scrollDismissesKeyboard(.never)
        .frame(maxHeight: Self.row * Self.visibleRows + 2 * Self.inset)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(role: .bgCanvas, in: theme), in: Self.shape)
        .overlay { Self.shape.strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: 1) }
        .shadow(color: Color(role: .fgDefault, in: theme).opacity(0.08), radius: 12, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("提到谁", bundle: .module))
    }
}
#endif
