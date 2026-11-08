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
                id: checkIn.id, member: checkIn.member, day: checkIn.day, postedDay: checkIn.postedDay,
                createdAt: checkIn.createdAt,
                audience: checkIn.audience, entry: .trained(Training(checkIn.training, postedAt: checkIn.createdAt)))
        case .healthyMeal(let checkIn):
            try self.init(
                id: checkIn.id, member: checkIn.member, day: checkIn.day, postedDay: checkIn.postedDay,
                createdAt: checkIn.createdAt,
                audience: checkIn.audience,
                entry: .healthyMeal(
                    Meal(caption: checkIn.meal.caption, photos: checkIn.meal.photos, postedAt: checkIn.createdAt)))
        case .cheatMeal(let checkIn):
            try self.init(
                id: checkIn.id, member: checkIn.member, day: checkIn.day, postedDay: checkIn.postedDay,
                createdAt: checkIn.createdAt,
                audience: checkIn.audience,
                entry: .cheatMeal(
                    Meal(caption: checkIn.meal.caption, photos: checkIn.meal.photos, postedAt: checkIn.createdAt)))
        case .disclaimer(let checkIn):
            try self.init(
                id: checkIn.id, member: checkIn.member, day: checkIn.day, postedDay: checkIn.postedDay,
                createdAt: checkIn.createdAt,
                audience: checkIn.audience,
                entry: .disclaimer(
                    Disclaimer(
                        checkIn.disclaimer.text, restDay: checkIn.disclaimer.restDay == true,
                        photos: try Photos(wire: checkIn.disclaimer.photos, postedAt: checkIn.createdAt))))
        }
    }

    private init(
        id: String, member: String, day: String, postedDay: String?, createdAt: Date, audience: [String],
        entry: Entry
    ) throws(ContractsError) {
        let posted: LocalDay? = if let postedDay { try LocalDay(postedDay) } else { nil }
        self.init(
            id: try CheckInID(wire: id), member: try MemberID(wire: member), day: try LocalDay(day),
            postedDay: posted, createdAt: Timestamp(wire: createdAt),
            audience: try Audience(audience.map(SquadID.init(wire:))),
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
                    training: training.wire))
        case .healthyMeal(let meal):
            .healthyMeal(
                .init(
                    version: ._1, day: day, createdAt: createdAt, audience: audience, kind: .healthyMeal,
                    meal: meal.wire))
        case .cheatMeal(let meal):
            .cheatMeal(
                .init(
                    version: ._1, day: day, createdAt: createdAt, audience: audience, kind: .cheatMeal,
                    meal: meal.wire))
        case .disclaimer(let disclaimer):
            .disclaimer(
                .init(
                    version: ._1, day: day, createdAt: createdAt, audience: audience, kind: .disclaimer,
                    disclaimer: disclaimer.wire))
        }
    }

    /// The body of `PATCH /check-ins/{id}` that makes the saved check-in this one: its fields and
    /// photos, all of them. The day, time and audience stay as posted, so they aren't in it.
    public var edit: Components.Schemas.CheckInEdit {
        switch entry {
        case .trained(let training): .trained(.init(version: ._1, kind: .trained, training: training.wire))
        case .healthyMeal(let meal): .healthyMeal(.init(version: ._1, kind: .healthyMeal, meal: meal.wire))
        case .cheatMeal(let meal): .cheatMeal(.init(version: ._1, kind: .cheatMeal, meal: meal.wire))
        case .disclaimer(let disclaimer):
            .disclaimer(.init(version: ._1, kind: .disclaimer, disclaimer: disclaimer.wire))
        }
    }
}

extension Training {
    var wire: Components.Schemas.Training {
        .init(
            sport: activity.wireSport, customSport: activity.wireCustomSport, minutes: minutes?.value,
            caption: caption?.text, photos: photos?.wire, workout: workout?.wire)
    }
}

extension Meal {
    var wire: Components.Schemas.Meal { .init(caption: caption?.text, photos: photos?.wire) }
}

extension Disclaimer {
    var wire: Components.Schemas.Disclaimer { .init(text: text, restDay: restDay ? true : nil, photos: photos?.wire) }
}

extension Training {
    init(_ wire: Components.Schemas.TrainingView, postedAt: Date) throws(ContractsError) {
        self.init(
            activity: try Activity(sport: wire.sport, customSport: wire.customSport),
            minutes: try wire.minutes.map(WorkoutMinutes.init),
            photos: try Photos(wire: wire.photos, postedAt: postedAt),
            caption: try wire.caption.map(Caption.init), workout: wire.workout.map(Workout.init))
    }
}

extension Workout {
    init(_ wire: Components.Schemas.WorkoutView) {
        self.init(
            source: WorkoutSource(provider: wire.provider, id: wire.providerWorkoutId),
            startedAt: Timestamp(wire: wire.startedAt), endedAt: Timestamp(wire: wire.endedAt),
            summary: WorkoutSummary(wire.summary), series: wire.series.map(WorkoutSeries.init),
            route: wire.route?.map { RoutePoint(lat: $0.lat, lon: $0.lon) }, tilePosition: wire.tilePosition,
            chartPosition: wire.chartPosition)
    }

    var wire: Components.Schemas.Workout {
        .init(
            provider: source.provider, providerWorkoutId: source.id, summary: summary.wire,
            series: series.map { series in
                .init(
                    hr: series.heartRate?.map { Components.Schemas.HeartRatePoint(t: $0.seconds, bpm: $0.bpm) },
                    laps: series.laps)
            },
            route: route?.map { Components.Schemas.RoutePoint(lat: $0.lat, lon: $0.lon) },
            tilePosition: tilePosition, chartPosition: chartPosition, startedAt: startedAt.date, endedAt: endedAt.date)
    }
}

extension WorkoutSummary {
    init(_ wire: Components.Schemas.WorkoutSummary) {
        self.init(
            durationSec: wire.durationSec, distanceM: wire.distanceM, paceSecPerKm: wire.paceSecPerKm,
            speedKmh: wire.speedKmh, avgHr: wire.avgHr, maxHr: wire.maxHr, effort: wire.effort, laps: wire.laps,
            poolLengthM: wire.poolLengthM, runs: wire.runs, descentM: wire.descentM, topSpeedKmh: wire.topSpeedKmh,
            elevationGainM: wire.elevationGainM, paceSecPer100m: wire.paceSecPer100m)
    }

    var wire: Components.Schemas.WorkoutSummary {
        .init(
            durationSec: durationSec, distanceM: distanceM, paceSecPerKm: paceSecPerKm, speedKmh: speedKmh,
            avgHr: avgHr, maxHr: maxHr, effort: effort, laps: laps, poolLengthM: poolLengthM, runs: runs,
            descentM: descentM, topSpeedKmh: topSpeedKmh, elevationGainM: elevationGainM, paceSecPer100m: paceSecPer100m
        )
    }
}

extension WorkoutSeries {
    init(_ wire: Components.Schemas.WorkoutSeries) {
        self.init(heartRate: wire.hr?.map { HeartRatePoint(seconds: $0.t, bpm: $0.bpm) }, laps: wire.laps)
    }
}

extension Meal {
    init(caption: String?, photos: [Components.Schemas.PhotoView]?, postedAt: Date) throws(ContractsError) {
        self.init(photos: try Photos(wire: photos, postedAt: postedAt), caption: try caption.map(Caption.init))
    }
}

extension Activity {
    /// The sport the member trained most (最常练).
    public init(_ wire: Components.Schemas.TopSport) throws(ContractsError) {
        try self.init(sport: wire.sport, customSport: wire.customSport)
    }

    /// The sport of a day's 练了 on a squadmate's 出赛表; nil for a day without one.
    public init?(_ wire: Components.Schemas.DayMark) throws(ContractsError) {
        guard wire.status == .trained, let sport = wire.sport else { return nil }
        try self.init(sport: sport, customSport: wire.customSport)
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
    /// Nil when the API listed none. `postedAt` is when their check-in was posted.
    init?(wire: [Components.Schemas.PhotoView]?, postedAt: Date) throws(ContractsError) {
        guard let wire else { return nil }
        var photos: [PhotoRef] = []
        for photo in wire {
            guard let url = URL(string: photo.url) else { throw .invalidPhotoURL(photo.url) }
            let size = try photo.size.map { size throws(ContractsError) in
                try PhotoSize(width: size.width, height: size.height)
            }
            photos.append(try PhotoRef(path: photo.path, size: size, viewURL: url, postedAt: Timestamp(wire: postedAt)))
        }
        try self.init(photos)
    }

    var wire: [Components.Schemas.PhotoRef] {
        all.map { photo in
            Components.Schemas.PhotoRef(
                path: photo.path,
                size: photo.size.map { Components.Schemas.PhotoSize(width: $0.width, height: $0.height) })
        }
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
