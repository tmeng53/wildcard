import Contracts
import DesignSystem

#if os(iOS)
import DesignSystemUI
import MapKit
import SwiftUI
#endif

/// Where a lap chart's bars stand across `width` points: one slot a lap, each bar most of its
/// slot, so every lap fits however many there are. A slot too thin for a gap gets none.
public enum LapBars {
    public struct Bar: Equatable, Sendable {
        public let start: Double
        public let width: Double

        public init(start: Double, width: Double) {
            self.start = start
            self.width = width
        }
    }

    public static func across(_ width: Double, count: Int) -> [Bar] {
        guard count > 0, width > 0 else { return [] }
        let slot = width / Double(count)
        let gap = slot >= 3 ? slot * 0.3 : 0
        return (0..<count).map { Bar(start: Double($0) * slot, width: slot - gap) }
    }
}

#if os(iOS)
extension ScoreCell.Unit {
    public var text: Text {
        switch self {
        case .minutes: Text(copy: "分钟", bundle: .module)
        case .laps: Text(copy: "趟", bundle: .module)
        case .runs: Text(copy: "score.runs.unit", bundle: .module)
        case .meters: Text(copy: "米", bundle: .module)
        case .kilometres: Text(copy: "公里", bundle: .module)
        case .kilometresPerHour: Text(copy: "km/h", bundle: .module)
        case .per100Meters: Text(copy: "/100 米", bundle: .module)
        case .outOfTen: Text(verbatim: "/10")
        case .kilocalories: Text(copy: "千卡", bundle: .module)
        }
    }
}

extension ScoreCell.Label {
    public var text: Text {
        switch self {
        case .duration: Text(copy: "时长", bundle: .module)
        case .distance: Text(copy: "距离", bundle: .module)
        case .pace: Text(copy: "配速", bundle: .module)
        case .speed: Text(copy: "均速", bundle: .module)
        case .averageHeartRate: Text(copy: "平均心率", bundle: .module)
        case .maxHeartRate: Text(copy: "最高心率", bundle: .module)
        case .effort: Text(copy: "强度", bundle: .module)
        case .runs: Text(copy: "score.runs", bundle: .module)
        case .descent: Text(copy: "落差", bundle: .module)
        case .topSpeed: Text(copy: "最高速", bundle: .module)
        case .elevationGain: Text(copy: "爬升", bundle: .module)
        case .calories: Text(copy: "卡路里", bundle: .module)
        case .laps(let pool?): Text(copy: "\(pool) 米泳池", bundle: .module)
        case .laps(nil): Text(copy: "趟数", bundle: .module)
        }
    }
}

/// A 训练's 成绩条 (Tracy, 2026-11-06): its numbers side by side on the sport category's colour,
/// 时长 first. Under a post's cover with no seam: its top corners square against the cover's
/// edge and its bottom ones rounded (Tracy, 2026-11-07). On the compose page and wherever a post
/// is being made, the same bar with every corner rounded, each cell a button that strikes its
/// number out of the post (faded and crossed through) or brings it back.
public struct ScoreStrip: View {
    @Environment(\.locale) private var locale
    private let cells: [ScoreCell]
    private let meal: [MealScoreCell]
    private let colors: PostBlockColors
    private let bottom: Bottom
    private let struck: Set<WorkoutCell>
    private let onToggle: ((WorkoutCell) -> Void)?
    private let fill: Fill

    /// Under a card (rounded) or across a post's ticket, where the stub goes on under it (square).
    public enum Bottom: Sendable {
        case rounded
        case square
    }

    /// What the strip stands on.
    public enum Fill: Sendable {
        /// Its own block in the sport category's colour.
        case block
        /// Nothing of its own: a band the caller lays it on, such as the 成绩卡's.
        case none
    }

    /// Read only, under a post's cover.
    public init(cells: [ScoreCell], activity: Activity, bottom: Bottom = .rounded, fill: Fill = .block) {
        self.cells = cells
        meal = []
        self.bottom = bottom
        self.fill = fill
        colors = PostBlockColors(kind: .trained, activity: activity)
        struck = []
        onToggle = nil
    }

    /// A rated meal's, read only, under its cover in the colour of its kind (Tracy, 2026-11-12).
    public init(meal rating: MealRating, kind: CheckInKind, bottom: Bottom = .rounded) {
        cells = []
        meal = MealScoreCell.cells(of: rating)
        self.bottom = bottom
        fill = .block
        colors = PostBlockColors(kind: kind, activity: nil)
        struck = []
        onToggle = nil
    }

    /// While a post is made, or its 成绩卡: every corner rounded, and a tap on a cell calls
    /// `onToggle` with it.
    public init(
        cells: [ScoreCell], activity: Activity, struck: Set<WorkoutCell>, fill: Fill = .block,
        onToggle: @escaping (WorkoutCell) -> Void
    ) {
        self.cells = cells
        meal = []
        bottom = .rounded
        self.fill = fill
        colors = PostBlockColors(kind: .trained, activity: activity)
        self.struck = struck
        self.onToggle = onToggle
    }

    /// The strip's height, the design's.
    public static let height: Double = 58

    /// Square on top where it meets the cover, rounded underneath unless the stub goes on; all
    /// round on its own.
    private var shape: UnevenRoundedRectangle {
        if onToggle != nil {
            return UnevenRoundedRectangle(
                topLeadingRadius: Radius.pick, bottomLeadingRadius: Radius.pick, bottomTrailingRadius: Radius.pick,
                topTrailingRadius: Radius.pick, style: .continuous)
        }
        let radius = bottom == .rounded ? Radius.card : 0
        return UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                if index > 0 { divider }
                if let onToggle {
                    let isStruck = struck.contains(cell.cell)
                    Button {
                        onToggle(cell.cell)
                    } label: {
                        face(cell, isStruck: isStruck)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .haptic(.pick, trigger: isStruck)
                    .accessibilityValue(isStruck ? Text(copy: "不发", bundle: .module) : Text(copy: "发", bundle: .module))
                    .accessibilityHint(
                        isStruck ? Text(copy: "点一下恢复", bundle: .module) : Text(copy: "点一下划掉", bundle: .module)
                    )
                    .accessibilityIdentifier("strip.\(cell.cell.rawValue)")
                } else {
                    face(cell, isStruck: false)
                        .accessibilityIdentifier("strip.\(cell.cell.rawValue)")
                }
            }
            ForEach(Array(meal.enumerated()), id: \.element.id) { index, cell in
                if index > 0 { divider }
                face(cell)
                    .accessibilityIdentifier("strip.\(cell.label.rawValue)")
            }
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(fill == .block ? Color(colors.fill) : .clear, in: shape)
        .foregroundStyle(Color(colors.ink))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(onToggle == nil ? "post.strip" : "compose.score")
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(colors.ink).opacity(0.35))
            .frame(width: 1)
            .padding(.vertical, Space.s)
    }

    private func face(_ cell: ScoreCell, isStruck: Bool) -> some View {
        face(label: cell.label.text, isStruck: isStruck) {
            Text(verbatim: cell.value)
                .typeStyle(TypeRamp.scoreInline)
                .strikethrough(isStruck)
            if let unit = cell.unit {
                unit.text.typeStyle(TypeRamp.label)
            }
        }
    }

    /// A meal's cell; 卡价比's says what it is on a tap (Tracy, 2026-11-14).
    @ViewBuilder
    private func face(_ cell: MealScoreCell) -> some View {
        if cell.label == .calorieValue {
            CalorieValueInfo { mealFace(cell, info: true) }
        } else {
            mealFace(cell, info: false)
        }
    }

    private func mealFace(_ cell: MealScoreCell, info: Bool) -> some View {
        let label = HStack(spacing: Space.xxs / 2) {
            cell.label.text
            if info {
                Image(systemName: "info.circle").accessibilityHidden(true)
            }
        }
        return face(label: label, isStruck: false) {
            Text(verbatim: cell.value)
                .typeStyle(TypeRamp.scoreInline)
            if cell.isStars {
                JellyStar(lit: true, size: Self.star)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                    .accessibilityHidden(true)
            }
        }
    }

    /// The star beside a meal's 健康 and 好吃, the design's.
    private static let star: CGFloat = 16

    private func face<Caption: View, Number: View>(
        label: Caption, isStruck: Bool, @ViewBuilder number: () -> Number
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs / 2) {
                number()
            }
            label
                .typeStyle(TypeRamp.caption)
                .opacity(0.85)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.leading, Space.s)
        .opacity(isStruck ? Self.struckOpacity : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// A struck number fades on the bar, as the design's do.
    private static let struckOpacity = 0.45
}

/// A workout's route on a map, drawn live from the stored points as a lane in the sport category's
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
                    Color(colors.fill),
                    style: StrokeStyle(lineWidth: lane, lineCap: .round, lineJoin: .round))
            MapPolyline(coordinates: coordinates)
                .stroke(
                    Color(colors.ink),
                    style: StrokeStyle(lineWidth: max(1, lane / 7), lineCap: .round, dash: [lane / 2, lane / 2]))
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        // The camera frames the route only when the map is made, so another route makes another map.
        .id(route)
        .allowsHitTesting(false)
        .accessibilityLabel(Text(copy: "路线地图", bundle: .module))
        .accessibilityIdentifier("workout.map")
    }

    /// The route's bounds with a margin, so the lane doesn't touch the edge.
    static func frame(around coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
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

/// A workout's chart. Heart rate is `HeartRateChart` on graphite, detailed with `label` (a post's
/// cover: zones, minutes per zone, scrubbing), the curve alone without. A swim's laps stay on the
/// sport category's colour, each lap's time as a bar, the fastest in white and the rest dimmed, with
/// `label` its name top left. With a `shape`, the chart keeps that width over height in the middle
/// of whatever box it's given, on its own colour, never stretched to the box.
public struct WorkoutChart: View {
    private let series: WorkoutSeries
    private let colors: PostBlockColors
    private let showsLabel: Bool
    private let startedAt: Date?
    private let shape: Double?

    public init(
        series: WorkoutSeries, activity: Activity, showsLabel: Bool = false, startedAt: Date? = nil,
        shape: Double? = nil
    ) {
        self.series = series
        colors = PostBlockColors(kind: .trained, activity: activity)
        self.showsLabel = showsLabel
        self.startedAt = startedAt
        self.shape = shape
    }

    public var body: some View {
        if let shape {
            face
                .aspectRatio(shape, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isHeartRate ? Color(ZoneColors.fill) : Color(colors.fill))
        } else {
            face
        }
    }

    private var isHeartRate: Bool { (series.laps?.isEmpty ?? true) && (series.heartRate?.count ?? 0) >= 2 }

    @ViewBuilder private var face: some View {
        if isHeartRate, let curve = series.heartRate {
            HeartRateChart(points: curve, zones: series.zones, startedAt: startedAt, isDetailed: showsLabel)
        } else {
            lapChart
        }
    }

    private var lapChart: some View {
        let ink = Color(colors.ink)
        return Canvas { context, size in
            let pad = size.width > 100 ? Space.s : Space.xxs + 2
            let top = showsLabel ? Space.xxl : pad
            let area = CGRect(x: pad, y: top, width: size.width - 2 * pad, height: size.height - top - pad)
            if let laps = series.laps, !laps.isEmpty {
                Self.drawLaps(laps, fastest: series.fastestLap, in: area, ink: ink, context: context)
            }
        }
        .background(Color(colors.fill))
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
            return Text(copy: "每趟用时 · 最快第 \(fastest + 1) 趟", bundle: .module)
        }
        return Text(copy: "心率曲线", bundle: .module)
    }

    private static func drawLaps(
        _ laps: [Double], fastest: Int?, in area: CGRect, ink: Color, context: GraphicsContext
    ) {
        let slowest = laps.max() ?? 1
        let quickest = laps.min() ?? 0
        for (index, (lap, slot)) in zip(laps, LapBars.across(area.width, count: laps.count)).enumerated() {
            // A faster lap stands taller.
            let share = slowest == quickest ? 0.6 : 0.35 + 0.6 * (slowest - lap) / (slowest - quickest)
            let height = area.height * share
            let bar = CGRect(x: area.minX + slot.start, y: area.maxY - height, width: slot.width, height: height)
            context.fill(
                Path(roundedRect: bar, cornerRadius: min(2, slot.width / 2)),
                with: .color(index == fastest ? ink : ink.opacity(0.55)))
        }
    }
}
#endif
