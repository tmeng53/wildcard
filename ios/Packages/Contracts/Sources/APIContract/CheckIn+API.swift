import Contracts
import Foundation

// The boundary between the API's generated wire types and the app's `Contracts` types. Reading
// checks everything `Contracts` checks, so a check-in the app holds is always a valid one;
// writing can't fail, because `Contracts` values are already valid.

extension CheckIn {
    /// A check-in as the API sent it.
    public init(_ wire: Components.Schemas.CheckIn) throws(ContractsError) {
        switch wire {
        case .trained(let checkIn):
            try self.init(
                id: checkIn.id, member: checkIn.member, day: checkIn.day, createdAt: checkIn.createdAt,
                audience: checkIn.audience, entry: .trained(Training(checkIn.training)))
        case .healthyMeal(let checkIn):
            try self.init(
                id: checkIn.id, member: checkIn.member, day: checkIn.day, createdAt: checkIn.createdAt,
                audience: checkIn.audience,
                entry: .healthyMeal(Meal(caption: checkIn.meal.caption, photos: checkIn.meal.photos)))
        case .cheatMeal(let checkIn):
            try self.init(
                id: checkIn.id, member: checkIn.member, day: checkIn.day, createdAt: checkIn.createdAt,
                audience: checkIn.audience,
                entry: .cheatMeal(Meal(caption: checkIn.meal.caption, photos: checkIn.meal.photos)))
        case .disclaimer(let checkIn):
            try self.init(
                id: checkIn.id, member: checkIn.member, day: checkIn.day, createdAt: checkIn.createdAt,
                audience: checkIn.audience,
                entry: .disclaimer(
                    Disclaimer(checkIn.disclaimer.text, photos: try Photos(wire: checkIn.disclaimer.photos))))
        }
    }

    private init(
        id: String, member: String, day: String, createdAt: Date, audience: [String], entry: Entry
    ) throws(ContractsError) {
        self.init(
            id: try CheckInID(wire: id), member: try MemberID(wire: member), day: try LocalDay(day),
            createdAt: Timestamp(wire: createdAt), audience: try Audience(audience.map(SquadID.init(wire:))),
            entry: entry)
    }

    /// The body of `PUT /check-ins/{id}` that saves this check-in, with `id` in the path. The
    /// member is whoever is signed in, so it isn't in the body.
    public var draft: Components.Schemas.CheckInDraft {
        let day = day.description
        let createdAt = createdAt.date
        let audience = audience.squads.map(\.description)
        return switch entry {
        case .trained(let training):
            .trained(
                .init(
                    version: ._1, day: day, createdAt: createdAt, audience: audience, kind: .trained,
                    training: .init(
                        sport: training.activity.wireSport, customSport: training.activity.wireCustomSport,
                        minutes: training.minutes?.value, caption: training.caption?.text,
                        photos: training.photos?.wire)))
        case .healthyMeal(let meal):
            .healthyMeal(
                .init(
                    version: ._1, day: day, createdAt: createdAt, audience: audience, kind: .healthyMeal,
                    meal: .init(caption: meal.caption?.text, photos: meal.photos?.wire)))
        case .cheatMeal(let meal):
            .cheatMeal(
                .init(
                    version: ._1, day: day, createdAt: createdAt, audience: audience, kind: .cheatMeal,
                    meal: .init(caption: meal.caption?.text, photos: meal.photos?.wire)))
        case .disclaimer(let disclaimer):
            .disclaimer(
                .init(
                    version: ._1, day: day, createdAt: createdAt, audience: audience, kind: .disclaimer,
                    disclaimer: .init(text: disclaimer.text, photos: disclaimer.photos?.wire)))
        }
    }
}

extension Training {
    init(_ wire: Components.Schemas.TrainingView) throws(ContractsError) {
        self.init(
            activity: try Activity(sport: wire.sport, customSport: wire.customSport),
            minutes: try wire.minutes.map(WorkoutMinutes.init), photos: try Photos(wire: wire.photos),
            caption: try wire.caption.map(Caption.init))
    }
}

extension Meal {
    init(caption: String?, photos: [Components.Schemas.PhotoView]?) throws(ContractsError) {
        self.init(photos: try Photos(wire: photos), caption: try caption.map(Caption.init))
    }
}

extension Activity {
    /// The sport the member trained most (最常练).
    public init(_ wire: Components.Schemas.TopSport) throws(ContractsError) {
        try self.init(sport: wire.sport, customSport: wire.customSport)
    }

    init(sport: Components.Schemas.Sport, customSport: String?) throws(ContractsError) {
        switch (sport, customSport) {
        case ("custom", let name?): self = .custom(try CustomSport(name))
        case ("custom", nil): throw .strayCustomSport
        case (_, .some): throw .strayCustomSport
        case (_, nil):
            guard let listed = Sport(rawValue: sport) else { throw .unknownSport(sport) }
            self = .sport(listed)
        }
    }

    var wireSport: Components.Schemas.Sport {
        switch self {
        case .sport(let sport): sport.rawValue
        case .custom: "custom"
        }
    }

    var wireCustomSport: String? {
        if case .custom(let custom) = self { custom.name } else { nil }
    }
}

extension Photos {
    /// Nil when the API listed none.
    init?(wire: [Components.Schemas.PhotoView]?) throws(ContractsError) {
        guard let wire else { return nil }
        var photos: [PhotoRef] = []
        for photo in wire {
            guard let url = URL(string: photo.url) else { throw .invalidPhotoURL(photo.url) }
            photos.append(try PhotoRef(path: photo.path, viewURL: url))
        }
        try self.init(photos)
    }

    var wire: [Components.Schemas.PhotoRef] {
        all.map { Components.Schemas.PhotoRef(path: $0.path) }
    }
}

extension ID {
    init(wire: String) throws(ContractsError) {
        guard let uuid = UUID(uuidString: wire) else { throw .invalidID(wire) }
        self.init(uuid)
    }
}

extension Timestamp {
    /// The moment a wire `Date` holds, to the nearest millisecond: the API sends milliseconds,
    /// and a `Date` can be a hair either side of them.
    init(wire date: Date) {
        self.init(millisecondsSince1970: Int64((date.timeIntervalSince1970 * 1000).rounded()))
    }
}
