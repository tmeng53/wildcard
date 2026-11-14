import Contracts
import Foundation

// Reading a coach message (教练消息卡) from the API's wire types, and sending an answer to one.

extension CoachMessage {
    /// A step, style or cast this build doesn't know is left out, drawn plain or stands in as the
    /// coach and the reader; a member id that can't be read is left off the stage.
    public init(_ wire: Components.Schemas.CoachMessage) {
        self.init(
            cards: wire.cards.map(Card.init),
            answered: Dictionary(
                wire.answered.map { ($0.path, Answered(tap: $0.tap, stars: $0.stars, text: $0.text)) },
                uniquingKeysWith: { first, _ in first }))
    }

    /// Answers as `PUT …/answer` sends them back.
    public static func answered(_ wire: [Components.Schemas.CoachMessageAnswered]) -> [String: Answered] {
        Dictionary(
            wire.map { ($0.path, Answered(tap: $0.tap, stars: $0.stars, text: $0.text)) },
            uniquingKeysWith: { first, _ in first })
    }
}

extension CoachMessage.Card {
    init(_ wire: Components.Schemas.CoachMessageCard) {
        self.init(
            path: wire.path, line: CatalogNames(wire.line), body: wire.body.map(CatalogNames.init),
            about: wire.about.map {
                CoachMessage.About(icon: $0.icon, name: CatalogNames($0.name), detail: $0.detail.map(CatalogNames.init))
            },
            stage: CoachMessage.Stage(wire.stage), stars: wire.stars,
            input: wire.input.map { CoachMessage.Input(placeholder: $0.placeholder.map(CatalogNames.init)) },
            buttons: wire.buttons.map {
                CoachMessage.Button(
                    id: $0.id, label: CatalogNames($0.label), icon: $0.icon,
                    style: CoachMessage.ButtonStyle(rawValue: $0.style) ?? .outline,
                    tap: $0.tap.compactMap(CoachMessage.Step.init))
            },
            thanks: wire.thanks.map { CatalogNames($0.value1) })
    }
}

extension CoachMessage.Stage {
    init(_ wire: Components.Schemas.CoachMessageCard.StagePayload) {
        let cast: CoachMessage.Cast =
            switch wire.cast {
            case "coach": .coach
            case "coachAndSquad": .coachAndSquad
            case "members": .members((wire.members ?? []).compactMap { try? MemberID(wire: $0) })
            default: .coachAndMe
            }
        self.init(cast: cast, move: wire.move, scene: wire.scene)
    }
}

extension CoachMessage.Step {
    /// Nil for a step with none of the fields this build knows.
    init?(_ wire: Components.Schemas.CoachMessageStep) {
        if let open = wire.open {
            self = .open(open)
        } else if let feedback = wire.feedback {
            self = .feedback(feedback)
        } else if wire.close == true {
            self = .close
        } else if let next = wire.next {
            self = .next(next)
        } else {
            return nil
        }
    }
}

extension CoachMessage.Part {
    /// The body of `PUT /squads/{squadId}/coach/messages/{messageId}/answer`.
    public func wire(on path: String) -> Components.Schemas.CoachMessageAnswer {
        switch self {
        case .tap(let button): .init(version: ._1, path: path, tap: button)
        case .stars(let stars): .init(version: ._1, path: path, stars: stars)
        case .text(let text): .init(version: ._1, path: path, text: text)
        }
    }
}
