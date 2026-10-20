import Contracts
import DesignSystem

// The five scenes' stations and floors, from the approved home design (version 15, 2026-10-19).
// Coordinates are after each scene's art is lifted (track and pool 70, tennis 60, climbing 40,
// gym 24) to make room for the 打卡 button.
extension StageLayout {
    public static func of(_ scene: SceneTheme) -> StageLayout {
        switch scene {
        case .track: track
        case .pool: pool
        case .gym: gym
        case .tennis: tennis
        case .climbing: climbing
        }
    }

    static let track = StageLayout(
        stations: [
            Station(
                kind: .jogging, capacity: 4,
                path: .loop(
                    from: -30, to: 420,
                    lanes: [StationPath.Lap(y: 371, direction: 1), StationPath.Lap(y: 422, direction: -1)]),
                speed: 48, scale: nil),
            Station(
                kind: .hurdles, capacity: 2,
                path: .loop(from: -30, to: 420, lanes: [StationPath.Lap(y: 320, direction: 1)]), speed: 62,
                scale: nil),
        ],
        stationsBySport: [.run: [.jogging, .hurdles]],
        field: [StageRect(x: 55...335, y: 350...470)],
        open: [StageRect(x: 0...390, y: 448...478), StageRect(x: 0...390, y: 506...650)],
        props: [])

    private static let poolLanes: [StationPath.Lane] = [294.0, 327, 360, 393].map {
        StationPath.Lane(from: 36, to: 354, y: $0)
    }

    static let pool = StageLayout(
        stations: [
            Station(kind: .swimming, capacity: 4, path: .lanes(poolLanes), speed: 34, scale: nil)
        ],
        stationsBySport: [.swim: [.swimming]],
        // The far deck across the water.
        field: [StageRect(x: 75...315, y: 250...250)],
        open: [StageRect(x: 0...390, y: 232...262), StageRect(x: 0...390, y: 440...650)],
        props: [StageRect(x: 330...373, y: 490...522), StageRect(x: 80...92, y: 450...520)],
        water: 272...406)

    static let gym = StageLayout(
        stations: [
            Station(
                kind: .treadmill, capacity: 2, path: .spots([StagePoint(x: 66, y: 385), StagePoint(x: 142, y: 385)]),
                speed: 0, scale: nil),
            Station(
                kind: .squatRack, capacity: 2, path: .spots([StagePoint(x: 246, y: 388), StagePoint(x: 322, y: 388)]),
                speed: 0, scale: nil),
            Station(
                kind: .dumbbells, capacity: 2, path: .spots([StagePoint(x: 80, y: 506), StagePoint(x: 150, y: 506)]),
                speed: 0, scale: nil),
            Station(
                kind: .yogaMat, capacity: 2, path: .spots([StagePoint(x: 250, y: 502), StagePoint(x: 326, y: 502)]),
                speed: 0, scale: nil),
        ],
        stationsBySport: [.run: [.treadmill], .strength: [.squatRack, .dumbbells], .yoga: [.yogaMat]],
        field: [StageRect(x: 75...315, y: 420...500)],
        open: [StageRect(x: 0...390, y: 300...650)],
        props: [
            StageRect(x: 236...370, y: 516...560), StageRect(x: 6...168, y: 542...564),
            StageRect(x: 40...350, y: 350...392), StageRect(x: 40...178, y: 440...456),
        ])

    static let tennis = StageLayout(
        stations: [
            Station(
                kind: .rally, capacity: 4,
                path: .spots([
                    StagePoint(x: 130, y: 316), StagePoint(x: 130, y: 432), StagePoint(x: 262, y: 316),
                    StagePoint(x: 262, y: 432),
                ]), speed: 0, scale: nil),
            Station(
                kind: .serve, capacity: 2, path: .spots([StagePoint(x: 40, y: 292), StagePoint(x: 350, y: 436)]),
                speed: 0, scale: nil),
        ],
        stationsBySport: [.tennis: [.rally, .serve]],
        field: [StageRect(x: 70...330, y: 316...440)],
        // The net.
        fieldGaps: [StageRect(x: 0...390, y: 345...372)],
        open: [StageRect(x: 0...390, y: 462...650)],
        props: [StageRect(x: 328...376, y: 492...530), StageRect(x: 34...46, y: 462...532)])

    static let climbing = StageLayout(
        stations: [
            Station(
                kind: .topRope, capacity: 4,
                path: .climb([132.0, 177, 222, 267].map { StationPath.Column(x: $0, top: 260, bottom: 392) }),
                speed: 9, scale: 0.19),
            Station(
                kind: .bouldering, capacity: 2,
                path: .climb([322.0, 362].map { StationPath.Column(x: $0, top: 340, bottom: 396) }),
                speed: 7, scale: 0.19),
            Station(
                kind: .chalk, capacity: 2, path: .spots([StagePoint(x: 150, y: 500), StagePoint(x: 240, y: 500)]),
                speed: 0, scale: nil),
        ],
        stationsBySport: [.climb: [.topRope, .bouldering, .chalk]],
        // The foot of the wall.
        field: [StageRect(x: 75...315, y: 452...452)],
        open: [StageRect(x: 0...390, y: 432...650)],
        props: [StageRect(x: 336...380, y: 528...560)])
}
