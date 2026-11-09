#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import MapKit
import SwiftUI
import UIKit

/// A workout's route as a still picture, the way `WorkoutMap` draws it live: the muted map with
/// the lane in the sport category's colour and its white dashed centre line, framed with the same
/// margin. A live map can't be drawn into a saved picture, so the 成绩卡 takes this one.
public enum RouteSnapshot {
    /// The picture at `size` points, three pixels a point; nil without a route or when the map
    /// can't be had (offline).
    /// The map comes back on the main queue, where its lane is drawn: one picture, once a sheet.
    /// - Parameter lane: the lane's width in points.
    @MainActor public static func picture(
        of route: [RoutePoint], activity: Activity, size: CGSize, lane: Double = 10
    ) async -> UIImage? {
        let coordinates = route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        guard coordinates.count >= 2, size.width > 0, size.height > 0 else { return nil }
        let colors = PostBlockColors(kind: .trained, activity: activity)
        let (fill, ink) = (UIColor(Color(colors.fill)), UIColor(Color(colors.ink)))
        let options = MKMapSnapshotter.Options()
        options.mapRect = fitted(WorkoutMap.frame(around: coordinates), to: size)
        options.size = size
        options.scale = scale
        let configuration = MKStandardMapConfiguration(emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        let snapshotter = MKMapSnapshotter(options: options)
        return await withCheckedContinuation { continuation in
            snapshotter.start(with: .main) { snapshot, _ in
                guard let snapshot else {
                    continuation.resume(returning: nil)
                    return
                }
                let path = UIBezierPath()
                for (index, coordinate) in coordinates.enumerated() {
                    let point = snapshot.point(for: coordinate)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                let format = UIGraphicsImageRendererFormat()
                format.scale = scale
                let picture = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    snapshot.image.draw(at: .zero)
                    fill.setStroke()
                    path.lineWidth = lane
                    path.stroke()
                    ink.setStroke()
                    path.lineWidth = max(1, lane / 7)
                    path.setLineDash([lane / 2, lane / 2], count: 2, phase: 0)
                    path.stroke()
                }
                continuation.resume(returning: picture)
            }
        }
    }

    /// Pixels a point, as the saved pictures are drawn.
    private static let scale: CGFloat = 3

    /// `rect` grown on one side to `size`'s shape, around its middle, so the snapshot isn't
    /// stretched.
    private static func fitted(_ rect: MKMapRect, to size: CGSize) -> MKMapRect {
        let shape = size.width / size.height
        guard rect.height > 0, rect.width > 0 else { return rect }
        if rect.width / rect.height < shape {
            let width = rect.height * shape
            return rect.insetBy(dx: -(width - rect.width) / 2, dy: 0)
        }
        let height = rect.width / shape
        return rect.insetBy(dx: 0, dy: -(height - rect.height) / 2)
    }
}
#endif
