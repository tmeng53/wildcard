#if os(iOS)
import Charts
import Contracts
import DesignSystem
import DesignSystemUI
import Foundation
import SwiftUI
import UIKit

/// A heart-rate curve on the brand's graphite (Tracy, 2026-11-08), coloured by zone when the post
/// carries the poster's zones. Detailed, as a post's cover: each zone's start on the right, the
/// minutes in each zone under the curve, and a press-and-hold that scrubs along it, showing the
/// reading, its time and its zone at the top left until the finger lifts. The hold comes first,
/// so a swipe still pages the cover. Small, on the compose page's tile: the curve alone.
struct HeartRateChart: View {
    private let trace: HeartRateTrace
    private let startedAt: Date?
    private let isDetailed: Bool
    /// The reading under the finger while it scrubs; nil once it lifts or the scrub is cancelled.
    @State private var picked: HeartRatePoint?

    init(points: [HeartRatePoint], zones: HeartRateZones?, startedAt: Date?, isDetailed: Bool) {
        trace = HeartRateTrace(points: points, zones: zones)
        self.startedAt = startedAt
        self.isDetailed = isDetailed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if isDetailed { header }
            chart
            if isDetailed, !trace.minutes.isEmpty { zoneMinutes }
        }
        .padding(isDetailed ? Space.s : Space.xxs + 2)
        .padding(.bottom, isDetailed ? Space.s : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(ZoneColors.fill))
        .foregroundStyle(Color(ZoneColors.ink))
        .haptic(.zone, trigger: pickedZone) { old, new in old != new && new != nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(copy: "心率曲线", bundle: .module))
        .accessibilityValue(accessibilityMinutes)
        .accessibilityIdentifier("workout.chart")
    }

    private var pickedZone: HeartRateZone? { picked.flatMap { trace.zones?.zone(of: $0.bpm) } }

    @ViewBuilder private var header: some View {
        if let picked {
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                Text(verbatim: "\(picked.bpm)").typeStyle(TypeRamp.scoreInline)
                Text(verbatim: "bpm").typeStyle(TypeRamp.label)
                if let time = time(of: picked) {
                    Text(verbatim: "· \(time)").typeStyle(TypeRamp.caption).opacity(0.85)
                }
                if let zone = pickedZone { tag(zone) }
            }
            .lineLimit(1)
            .frame(height: Self.headerHeight, alignment: .leading)
            .accessibilityIdentifier("workout.chart.reading")
        } else {
            Text(copy: "心率曲线", bundle: .module)
                .typeStyle(TypeRamp.caption)
                .opacity(0.85)
                .frame(height: Self.headerHeight, alignment: .leading)
        }
    }

    private func tag(_ zone: HeartRateZone) -> some View {
        zone.name
            .typeStyle(TypeRamp.captionEmphasis)
            .foregroundStyle(Color(ZoneColors.fill))
            .padding(.horizontal, Space.xxs + 2)
            .background(Color(ZoneColors.zone(zone.rawValue)), in: Capsule())
    }

    private var chart: some View {
        Chart {
            ForEach(Array(trace.stretches.enumerated()), id: \.offset) { index, stretch in
                ForEach(Array(stretch.points.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("time", point.seconds), y: .value("bpm", point.bpm),
                        series: .value("stretch", index)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color(of: stretch.zone))
                    .lineStyle(StrokeStyle(lineWidth: isDetailed ? 3 : 2, lineCap: .round, lineJoin: .round))
                }
            }
            if let picked {
                RuleMark(x: .value("time", picked.seconds))
                    .foregroundStyle(Color(ZoneColors.ink).opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                PointMark(x: .value("time", picked.seconds), y: .value("bpm", picked.bpm))
                    .symbol {
                        Circle()
                            .fill(Color(ZoneColors.fill))
                            .overlay { Circle().strokeBorder(color(of: pickedZone), lineWidth: 3) }
                            .frame(width: Self.dot, height: Self.dot)
                    }
            }
        }
        .chartXScale(domain: timeDomain)
        .chartYScale(domain: trace.bpmRange.lowerBound...trace.bpmRange.upperBound)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: isDetailed ? (trace.zones?.starts ?? []) : []) { value in
                AxisValueLabel {
                    if let bpm = value.as(Int.self) { zoneStart(bpm) }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if isDetailed {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            HoldToScrub { location in
                                picked = location.flatMap { reading(at: $0, proxy: proxy, geometry: geometry) }
                            })
                }
            }
        }
    }

    private func zoneStart(_ bpm: Int) -> some View {
        HStack(spacing: Space.xxs) {
            Capsule()
                .fill(color(of: trace.zones?.zone(of: bpm)))
                .frame(width: Space.xs - 2, height: 3)
            Text(verbatim: "\(bpm)")
                .typeStyle(TypeRamp.scoreCaption)
                .foregroundStyle(Color(ZoneColors.ink).opacity(0.6))
        }
    }

    /// The reading at `location`, in the chart's overlay.
    private func reading(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> HeartRatePoint? {
        guard let plot = proxy.plotFrame else { return nil }
        let across = location.x - geometry[plot].origin.x
        guard let seconds: Double = proxy.value(atX: across) else { return nil }
        return trace.reading(at: seconds)
    }

    /// The curve's first to last reading, at least a second wide so a flat series still draws.
    private var timeDomain: ClosedRange<Double> {
        let start = trace.points.first?.seconds ?? 0
        return start...max(trace.points.last?.seconds ?? start, start + 1)
    }

    private var zoneMinutes: some View {
        VStack(alignment: .leading, spacing: Space.xxs + 2) {
            GeometryReader { geometry in
                let total = max(trace.minutes.map(\.minutes).reduce(0, +), 1)
                let gaps = Double(trace.minutes.count - 1) * 2
                HStack(spacing: Space.xxs / 2) {
                    ForEach(trace.minutes, id: \.zone) { entry in
                        Capsule()
                            .fill(Color(ZoneColors.zone(entry.zone.rawValue)))
                            .opacity(isLit(entry.zone) ? 1 : 0.3)
                            .frame(
                                width: max(2, (geometry.size.width - gaps) * Double(entry.minutes) / Double(total)))
                    }
                }
            }
            .frame(height: 6)
            // Where the zones' names don't fit (English on the smallest phone), the dots carry them.
            ViewThatFits(in: .horizontal) {
                minutesRow(named: true)
                minutesRow(named: false)
            }
        }
        .accessibilityIdentifier("workout.chart.zones")
    }

    private func minutesRow(named: Bool) -> some View {
        HStack(spacing: Space.xs) {
            ForEach(trace.minutes, id: \.zone) { entry in
                HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                    Circle()
                        .fill(Color(ZoneColors.zone(entry.zone.rawValue)))
                        .frame(width: 6, height: 6)
                    if named { entry.zone.name.typeStyle(TypeRamp.caption).opacity(0.7) }
                    Text(copy: "\(entry.minutes) 分", bundle: .module).typeStyle(TypeRamp.scoreSmall)
                }
                .fixedSize()
                .opacity(isLit(entry.zone) ? 1 : 0.35)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func isLit(_ zone: HeartRateZone) -> Bool { picked == nil || pickedZone == zone }

    /// A zone's colour; below 轻松 the line dims, so it reads as outside every zone (as warming up
    /// and cooling down are), and without zones the whole line is white.
    private func color(of zone: HeartRateZone?) -> Color {
        if let zone { return Color(ZoneColors.zone(zone.rawValue)) }
        return Color(ZoneColors.ink).opacity(trace.zones == nil ? 1 : Self.belowZones)
    }

    /// The reading's clock time, in the app's language; nil without the workout's start.
    private func time(of point: HeartRatePoint) -> String? {
        startedAt?.addingTimeInterval(point.seconds)
            .formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguage.current.locale))
    }

    private var accessibilityMinutes: Text {
        trace.minutes.reduce(Text(verbatim: "")) { words, entry in
            words + entry.zone.name + Text(verbatim: " ") + Text(copy: "\(entry.minutes) 分", bundle: .module)
                + Text(verbatim: "  ")
        }
    }

    /// As tall as the post's 「…」 over the cover's corner, so the zones' axis starts below it.
    private static let headerHeight = Sizing.control
    private static let belowZones = 0.4
    private static let dot = 12.0
    fileprivate static let hold = 0.15
    /// How far the finger may wander before the hold counts, as a swipe that pages the cover.
    fileprivate static let slop = 10.0
}

/// Press and hold the curve, then slide along it. A UIKit long press, not a SwiftUI one: a SwiftUI
/// gesture with a drag in it keeps the cover's pager from paging when a swipe starts on the chart.
/// This one fails once the finger moves first, so the swipe pages, and once it holds the pager
/// can't start, so the slide only scrubs. Its hold is shorter than the card's emoji bar's, so a
/// hold on the curve scrubs.
private struct HoldToScrub: UIGestureRecognizerRepresentable {
    /// Where the finger is, in the view it's on, while it scrubs; nil once it lifts.
    let scrubbed: (CGPoint?) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = HeartRateChart.hold
        recognizer.allowableMovement = HeartRateChart.slop
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed: scrubbed(context.converter.localLocation)
        default: scrubbed(nil)
        }
    }
}

extension HeartRateZone {
    /// 轻松, 适中, 剧烈 or 峰值.
    var name: Text {
        switch self {
        case .light: Text(copy: "轻松", bundle: .module)
        case .moderate: Text(copy: "适中", bundle: .module)
        case .vigorous: Text(copy: "剧烈", bundle: .module)
        case .peak: Text(copy: "峰值", bundle: .module)
        }
    }
}
#endif
