import Contracts
import DesignSystem

// The five scenes' stations and floors, from the approved simple home design (2026-10-20).
// Station coordinates are after each scene's art is lifted (track and pool 36, tennis 30, gym 24,
// climbing 10) to make room for the 打卡 button; the floors are drawn in screen coordinates.
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

    /// The track's lane lines, the first along the top of lane 1 and the last along the front of
    /// lane 4, where the floor starts.
    static let trackLines = [310.0, 361, 412, 463, 514]

    // Runners jog lanes 1 to 3 in the middle of each, back and forth, turning before the edge.
    static let track = StageLayout(
        stations: [
            Station(
                kind: .jogging, capacity: 6,
                path: .lanes(
                    zip(trackLines, trackLines.dropFirst()).prefix(3).map {
                        StationPath.Lane(from: 40, to: 350, y: ($0 + $1) / 2)
                    }, speed: 52), scale: nil)
        ],
        stationsBySport: ["run": [.jogging]],
        standing: [StageRect(x: 0...390, y: 346...650)],
        props: [],
        lines: trackLines)

    private static let poolLanes: [StationPath.Lane] = [328.0, 361, 394, 427].map {
        StationPath.Lane(from: 40, to: 350, y: $0)
    }

    // Only the deck in front of the water.
    static let pool = StageLayout(
        stations: [
            Station(kind: .swimming, capacity: 4, path: .lanes(poolLanes, speed: 34), scale: nil)
        ],
        stationsBySport: ["swim": [.swimming]],
        standing: [StageRect(x: 0...390, y: 474...650)],
        props: [])

    static let gym = StageLayout(
        stations: [
            Station(
                kind: .treadmill, capacity: 2, path: .spots([StagePoint(x: 66, y: 385), StagePoint(x: 142, y: 385)]),
                scale: nil),
            Station(
                kind: .squatRack, capacity: 2, path: .spots([StagePoint(x: 246, y: 388), StagePoint(x: 322, y: 388)]),
                scale: nil),
            Station(
                kind: .dumbbells, capacity: 2, path: .spots([StagePoint(x: 80, y: 506), StagePoint(x: 150, y: 506)]),
                scale: nil),
            Station(
                kind: .yogaMat, capacity: 2, path: .spots([StagePoint(x: 250, y: 502), StagePoint(x: 326, y: 502)]),
                scale: nil),
        ],
        stationsBySport: ["run": [.treadmill], "strength": [.squatRack, .dumbbells], "yoga": [.yogaMat]],
        standing: [StageRect(x: 0...390, y: 420...650)],
        props: [StageRect(x: 40...350, y: 350...392), StageRect(x: 40...178, y: 440...456)])

    static let tennis = StageLayout(
        stations: [
            Station(
                kind: .rally, capacity: 4,
                path: .spots([
                    StagePoint(x: 130, y: 346), StagePoint(x: 130, y: 462), StagePoint(x: 262, y: 346),
                    StagePoint(x: 262, y: 462),
                ]), scale: nil),
            Station(
                kind: .serve, capacity: 2, path: .spots([StagePoint(x: 40, y: 322), StagePoint(x: 350, y: 466)]),
                scale: nil),
        ],
        stationsBySport: ["tennis": [.rally, .serve]],
        standing: [StageRect(x: 0...390, y: 346...650)],
        // The net.
        props: [StageRect(x: 0...390, y: 375...402)])

    static let climbing = StageLayout(
        stations: [
            Station(
                kind: .topRope, capacity: 4,
                path: .climb(
                    [132.0, 177, 222, 267].map { StationPath.Column(x: $0, top: 290, bottom: 422) }, speed: 9),
                scale: 0.19),
            Station(
                kind: .bouldering, capacity: 2,
                path: .climb([322.0, 356].map { StationPath.Column(x: $0, top: 370, bottom: 426) }, speed: 7),
                scale: 0.19),
            Station(
                kind: .chalk, capacity: 2, path: .spots([StagePoint(x: 150, y: 530), StagePoint(x: 240, y: 530)]),
                scale: nil),
        ],
        stationsBySport: ["climb": [.topRope, .bouldering, .chalk]],
        // From the foot of the wall.
        standing: [StageRect(x: 0...390, y: 470...650)],
        props: [])
}
