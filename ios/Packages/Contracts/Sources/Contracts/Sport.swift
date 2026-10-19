import Foundation

/// A sport from the list. The API's OpenAPI document is the list of record; `APIContract`'s
/// tests fail when the two differ. Names people see live in the String Catalog, keyed by the
/// raw value. 生活也算练 sports count toward 本周 like any other 练了.
public enum Sport: String, CaseIterable, Hashable, Sendable {
    // 跑走
    case run, walk, hike, trailRun
    // 力量
    case strength, crossfit, hyrox, kettlebell
    // 有氧和课程
    case spin, elliptical, rowing, hiit, jumpRope, aerobics
    // 身心
    case yoga, matPilates, reformerPilates, barre, stretching
    // 水上
    case swim, surf, paddleboard, kayak
    // 球拍
    case tennis, badminton, pickleball, tableTennis, squash
    // 球类
    case basketball, soccer, volleyball, golf, baseballSoftball, ultimate
    // 骑行
    case roadCycling, mountainBiking
    // 户外和冬季
    case climb, ski, snowboard, skate
    // 格斗
    case boxing, kickboxing, jiuJitsu, martialArts
    // 舞蹈
    case dance
    // 生活也算练
    case dogWalk, walkCommute, bikeCommute, deepClean, moving, strollerWalk, gardening

    public var category: SportCategory {
        switch self {
        case .run, .walk, .hike, .trailRun: .runWalk
        case .strength, .crossfit, .hyrox, .kettlebell: .strength
        case .spin, .elliptical, .rowing, .hiit, .jumpRope, .aerobics: .cardio
        case .yoga, .matPilates, .reformerPilates, .barre, .stretching: .mindBody
        case .swim, .surf, .paddleboard, .kayak: .water
        case .tennis, .badminton, .pickleball, .tableTennis, .squash: .racket
        case .basketball, .soccer, .volleyball, .golf, .baseballSoftball, .ultimate: .ball
        case .roadCycling, .mountainBiking: .cycling
        case .climb, .ski, .snowboard, .skate: .outdoorWinter
        case .boxing, .kickboxing, .jiuJitsu, .martialArts: .combat
        case .dance: .dance
        case .dogWalk, .walkCommute, .bikeCommute, .deepClean, .moving, .strollerWalk, .gardening: .everyday
        }
    }
}

/// The picker's tabs, in the order they show. 其他 is a `CustomSport`, not a tab of sports.
public enum SportCategory: String, CaseIterable, Hashable, Sendable {
    case runWalk, strength, cardio, mindBody, water, racket, ball, cycling, outdoorWinter, combat, dance, everyday

    /// This category's sports, in list order.
    public var sports: [Sport] { Sport.allCases.filter { $0.category == self } }
}

/// 其他: a sport the member names themselves.
public struct CustomSport: Hashable, Sendable {
    /// Characters, counted as people see them.
    public static let maxLength = 20

    public let name: String

    public init(_ name: String) throws(ContractsError) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.unicodeScalars.contains(where: {
                $0.properties.generalCategory == .control || $0.properties.isWhitespace && $0 != " " && $0 != "\u{3000}"
            })
        else { throw .multilineCustomSport }
        guard (1...Self.maxLength).contains(trimmed.count) else { throw .customSportLength(trimmed.count) }
        // A bidi control (U+202E flips what follows), or only format characters such as a lone
        // zero-width joiner, shows as a blank or garbled label. Joiners inside 🏃‍♀️ are fine.
        guard
            !trimmed.unicodeScalars.contains(where: { $0.properties.isBidiControl }),
            trimmed.unicodeScalars.contains(where: {
                $0.properties.generalCategory != .format && !$0.properties.isWhitespace
            })
        else { throw .invisibleCustomSport }
        self.name = trimmed
    }
}

/// What a 练了 or a planned training day is: a listed sport or the member's own.
public enum Activity: Hashable, Sendable {
    case sport(Sport)
    case custom(CustomSport)
}
