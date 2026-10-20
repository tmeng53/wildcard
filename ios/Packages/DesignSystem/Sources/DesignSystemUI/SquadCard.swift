#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// One teammate's place in a squad card's row.
public struct SquadMember: Identifiable, Sendable, Hashable {
    public let id: String
    public let status: RingStatus
    /// Names the member's ring for UI tests.
    public let accessibilityIdentifier: String?

    public init(id: String, status: RingStatus, accessibilityIdentifier: String? = nil) {
        self.id = id
        self.status = status
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

/// The squad's week on the home scene: 本周小队训练 and the squad's name, the count against the
/// week's planned training days in big Barlow, the bar, then everyone's status rings and my own
/// count. A solid white card, straight on the scene. The caller orders the members: checked in
/// first, by time, then excused or resting, then everyone else.
public struct SquadCard<Avatar: View>: View {
    @Environment(\.sceneTheme) private var theme
    private let squadName: String
    private let done: Int
    private let goal: Int
    private let members: [SquadMember]
    private let myDone: Int
    private let myGoal: Int
    private let avatar: (SquadMember) -> Avatar

    public init(
        squadName: String, done: Int, goal: Int, members: [SquadMember], myDone: Int, myGoal: Int,
        @ViewBuilder avatar: @escaping (SquadMember) -> Avatar
    ) {
        self.squadName = squadName
        self.done = done
        self.goal = goal
        self.members = members
        self.myDone = myDone
        self.myGoal = myGoal
        self.avatar = avatar
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    SectionLabel(Text("本周小队训练", bundle: .module))
                    Text(verbatim: squadName)
                        .typeStyle(TypeRamp.headline)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .lineLimit(1)
                }
                Spacer(minLength: Space.xs)
                Score(count: done, goal: goal, size: .hero)
                    .contentTransition(.numericText(value: Double(done)))
            }
            ProgressBar(fraction: goal > 0 ? Double(done) / Double(goal) : 0)
            HStack(spacing: Space.xxs) {
                ForEach(members) { member in
                    StatusRing(status: member.status) { avatar(member) }
                        .accessibilityIdentifier(ifPresent: member.accessibilityIdentifier)
                }
                Spacer(minLength: Space.xs)
                Text("我 \(myDone)/\(myGoal)", bundle: .module)
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .contentTransition(.numericText(value: Double(myDone)))
            }
        }
        .card(on: .scene)
        .accessibilityElement(children: .contain)
    }
}
#endif
