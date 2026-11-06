import Contracts
import DesignSystem
#if os(iOS)
import DesignSystemUI
import MapKit
import SwiftUI
#endif

/// One cell of a 成绩条: the number as Health gave it, its unit and what it is.
public struct ScoreCell: Hashable, Identifiable, Sendable {
    public enum Unit: Hashable, Sendable {
        case minutes, laps, meters, kilometres, kilometresPerHour, outOfTen
    }

    public enum Label: Hashable, Sendable {
        case duration, distance, pace, speed, averageHeartRate, maxHeartRate, effort
        /// Laps, with the pool's length when Health has it.
        case laps(poolMeters: Int?)
    }

    public let cell: WorkoutCell
    public let value: String
    public let unit: Unit?
    public let label: Label

    public var id: WorkoutCell { cell }

    public init(cell: WorkoutCell, value: String, unit: Unit?, label: Label) {
        self.cell = cell
        self.value = value
        self.unit = unit
        self.label = label
    }

    /// A 训练's cells: its workout's numbers, 时长 first, or a hand-made post's minutes alone;
    /// none when it has neither.
    public static func cells(of training: Training) -> [ScoreCell] {
        if let workout = training.workout { return cells(of: workout.summary) }
        guard let minutes = training.minutes else { return [] }
        return [ScoreCell(cell: .duration, value: "\(minutes.value)", unit: .minutes, label: .duration)]
    }

    /// Each number a workout has, in the strip's order, never converted.
    public static func cells(of summary: WorkoutSummary) -> [ScoreCell] {
        summary.cells.compactMap { cell in
            switch cell {
            case .duration:
                summary.durationSec.map {
                    ScoreCell(
                        cell: cell, value: "\(max(1, Int((Double($0) / 60).rounded())))", unit: .minutes,
                        label: .duration)
                }
            case .laps:
                summary.laps.map {
                    ScoreCell(
                        cell: cell, value: "\($0)", unit: .laps,
                        label: .laps(poolMeters: summary.poolLengthM.map { Int($0.rounded()) }))
                }
            case .distance:
                summary.distanceM.map { meters in
                    // A pool swim reads in metres; anything else in kilometres.
                    summary.laps != nil || summary.poolLengthM != nil
                        ? ScoreCell(cell: cell, value: "\(Int(meters.rounded()))", unit: .meters, label: .distance)
                        : ScoreCell(
                            cell: cell, value: String(format: "%.1f", meters / 1000), unit: .kilometres,
                            label: .distance)
                }
            case .pace:
                summary.paceSecPerKm.map { pace in
                    let seconds = Int(pace.rounded())
                    return ScoreCell(
                        cell: cell, value: String(format: "%d′%02d″", seconds / 60, seconds % 60), unit: nil,
                        label: .pace)
                }
            case .speed:
                summary.speedKmh.map {
                    ScoreCell(
                        cell: cell, value: String(format: "%.1f", $0), unit: .kilometresPerHour, label: .speed)
                }
            case .averageHeartRate:
                summary.avgHr.map { ScoreCell(cell: cell, value: "\($0)", unit: nil, label: .averageHeartRate) }
            case .maxHeartRate:
                summary.maxHr.map { ScoreCell(cell: cell, value: "\($0)", unit: nil, label: .maxHeartRate) }
            case .effort:
                summary.effort.map {
                    ScoreCell(
                        cell: cell, value: $0.rounded() == $0 ? "\(Int($0))" : String(format: "%.1f", $0),
                        unit: .outOfTen, label: .effort)
                }
            }
        }
    }
}

#if os(iOS)
extension ScoreCell.Unit {
    var text: Text {
        switch self {
        case .minutes: Text("分钟", bundle: .module)
        case .laps: Text("趟", bundle: .module)
        case .meters: Text("米", bundle: .module)
        case .kilometres: Text("公里", bundle: .module)
        case .kilometresPerHour: Text("km/h", bundle: .module)
        case .outOfTen: Text(verbatim: "/10")
        }
    }
}

extension ScoreCell.Label {
    var text: Text {
        switch self {
        case .duration: Text("时长", bundle: .module)
        case .distance: Text("距离", bundle: .module)
        case .pace: Text("配速", bundle: .module)
        case .speed: Text("均速", bundle: .module)
        case .averageHeartRate: Text("平均心率", bundle: .module)
        case .maxHeartRate: Text("最高心率", bundle: .module)
        case .effort: Text("费力", bundle: .module)
        case .laps(let pool?): Text("\(pool) 米泳池", bundle: .module)
        case .laps(nil): Text("趟数", bundle: .module)
        }
    }
}

/// A 训练's 成绩条 (Tracy, 2026-11-06): its numbers side by side on the sport's scene colour,
/// 时长 first. Under a post's cover with no seam; on the compose page each cell can be tapped
/// to strike it out (dimmed, a line through), so it isn't posted, and tapped again to bring it
/// back.
public struct ScoreStrip: View {
    @Environment(\.locale) private var locale
    private let cells: [ScoreCell]
    private let colors: PostBlockColors
    private let struck: Set<WorkoutCell>
    private let toggle: ((WorkoutCell) -> Void)?

    /// - Parameter toggle: strikes a cell out or back; nil where the strip is only read.
    public init(
        cells: [ScoreCell], activity: Activity, struck: Set<WorkoutCell> = [],
        toggle: ((WorkoutCell) -> Void)? = nil
    ) {
        self.cells = cells
        colors = PostBlockColors(kind: .trained, activity: activity)
        self.struck = struck
        self.toggle = toggle
    }

    /// The strip's height, the design's.
    public static let height: Double = 58

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                if index > 0 {
                    Rectangle()
                        .fill(Color(role: colors.ink, in: colors.scene).opacity(0.35))
                        .frame(width: 1)
                        .padding(.vertical, Space.s)
                }
                if let toggle {
                    Button {
                        toggle(cell.cell)
                    } label: {
                        face(cell)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(struck.contains(cell.cell) ? Text("不发", bundle: .module) : Text("发", bundle: .module))
                    .accessibilityHint(struck.contains(cell.cell) ? Text("点一下恢复", bundle: .module) : Text("点一下划掉", bundle: .module))
                    .accessibilityIdentifier("strip.\(cell.cell.rawValue)")
                } else {
                    face(cell)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("strip.\(cell.cell.rawValue)")
                }
            }
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(Color(role: colors.fill, in: colors.scene))
        .foregroundStyle(Color(role: colors.ink, in: colors.scene))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("post.strip")
    }

    private func face(_ cell: ScoreCell) -> some View {
        let isStruck = struck.contains(cell.cell)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs / 2) {
                Text(verbatim: cell.value)
                    .typeStyle(TypeRamp.scoreInline)
                    .strikethrough(isStruck, pattern: .solid)
                if let unit = cell.unit {
                    unit.text.typeStyle(TypeRamp.label)
                }
            }
            cell.label.text
                .typeStyle(TypeRamp.caption)
                .opacity(0.85)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.leading, Space.s)
        .opacity(isStruck ? 0.45 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A workout's route on a map, drawn live from the stored points as a lane in the sport's scene
/// colour with a white dashed centre line. No one is drawn on it, and it doesn't move under a
/// finger: a tap goes to the card.
public struct WorkoutMap: View {
    private let route: [RoutePoint]
    private let colors: PostBlockColors
    private let lane: Double

    /// - Parameter lane: the lane's width in points; thinner on a small tile.
    public init(route: [RoutePoint], activity: Activity, lane: Double = 10) {
        self.route = route
        colors = PostBlockColors(kind: .trained, activity: activity)
        self.lane = lane
    }

    public var body: some View {
        let coordinates = route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        Map(initialPosition: .rect(Self.frame(around: coordinates)), interactionModes: []) {
            MapPolyline(coordinates: coordinates)
                .stroke(
                    Color(role: colors.fill, in: colors.scene),
                    style: StrokeStyle(lineWidth: lane, lineCap: .round, lineJoin: .round))
            MapPolyline(coordinates: coordinates)
                .stroke(
                    Color(role: colors.ink, in: colors.scene),
                    style: StrokeStyle(lineWidth: max(1, lane / 7), lineCap: .round, dash: [lane / 2, lane / 2]))
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .accessibilityLabel(Text("路线地图", bundle: .module))
        .accessibilityIdentifier("workout.map")
    }

    /// The route's bounds with a margin, so the lane doesn't touch the edge.
    private static func frame(around coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        let points = coordinates.map(MKMapPoint.init)
        guard let first = points.first else { return .world }
        var rect = MKMapRect(origin: first, size: MKMapSize(width: 0, height: 0))
        for point in points.dropFirst() {
            rect = rect.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }
        let margin = max(rect.width, rect.height) * 0.18 + 200
        return rect.insetBy(dx: -margin, dy: -margin)
    }
}

/// A workout's chart on the sport's scene colour: heart rate as a line, or for a swim each lap's
/// time as a bar, the fastest in white and the rest dimmed. With `label`, its name top left.
public struct WorkoutChart: View {
    private let series: WorkoutSeries
    private let colors: PostBlockColors
    private let showsLabel: Bool

    public init(series: WorkoutSeries, activity: Activity, showsLabel: Bool = false) {
        self.series = series
        colors = PostBlockColors(kind: .trained, activity: activity)
        self.showsLabel = showsLabel
    }

    public var body: some View {
        let ink = Color(role: colors.ink, in: colors.scene)
        Canvas { context, size in
            let pad = size.width > 100 ? Space.s : Space.xxs + 2
            let top = showsLabel ? Space.xxl : pad
            let area = CGRect(x: pad, y: top, width: size.width - 2 * pad, height: size.height - top - pad)
            if let laps = series.laps, !laps.isEmpty {
                Self.drawLaps(laps, fastest: series.fastestLap, in: area, ink: ink, context: context)
            } else if let hr = series.hr, hr.count >= 2 {
                Self.drawHeartRate(hr, in: area, ink: ink, lineWidth: size.width > 100 ? 2.5 : 2, context: context)
            }
        }
        .background(Color(role: colors.fill, in: colors.scene))
        .overlay(alignment: .topLeading) {
            if showsLabel {
                label
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(ink.opacity(0.85))
                    .padding(Space.s)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityIdentifier("workout.chart")
    }

    private var label: Text {
        if let laps = series.laps, !laps.isEmpty, let fastest = series.fastestLap {
            return Text("每趟用时 · 最快第 \(fastest + 1) 趟", bundle: .module)
        }
        return Text("心率曲线", bundle: .module)
    }

    private static func drawLaps(
        _ laps: [Double], fastest: Int?, in area: CGRect, ink: Color, context: GraphicsContext
    ) {
        let slowest = laps.max() ?? 1
        let quickest = laps.min() ?? 0
        let gap = area.width / Double(laps.count) * 0.3
        let width = max(2, area.width / Double(laps.count) - gap)
        for (index, lap) in laps.enumerated() {
            // A faster lap stands taller.
            let share = slowest == quickest ? 0.6 : 0.35 + 0.6 * (slowest - lap) / (slowest - quickest)
            let height = area.height * share
            let bar = CGRect(
                x: area.minX + Double(index) * (width + gap), y: area.maxY - height, width: width, height: height)
            context.fill(
                Path(roundedRect: bar, cornerRadius: min(2, width / 2)),
                with: .color(index == fastest ? ink : ink.opacity(0.55)))
        }
    }

    private static func drawHeartRate(
        _ points: [HeartRatePoint], in area: CGRect, ink: Color, lineWidth: Double, context: GraphicsContext
    ) {
        let lowest = Double(points.map(\.bpm).min() ?? 0)
        let highest = Double(points.map(\.bpm).max() ?? 1)
        let start = points.first?.seconds ?? 0
        let span = max((points.last?.seconds ?? 1) - start, 1)
        var path = Path()
        for (index, point) in points.enumerated() {
            let across = area.minX + (point.seconds - start) / span * area.width
            let share = highest == lowest ? 0.5 : (Double(point.bpm) - lowest) / (highest - lowest)
            let location = CGPoint(x: across, y: area.maxY - share * area.height)
            if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
        }
        context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
    }
}
#endif
