#if os(iOS)
import Contracts
import DesignSystem
import SwiftUI

extension EnvironmentValues {
    /// Where 动态's cards and the post pages pushed from them meet, for the zoom between them;
    /// nil (no zoom, the system's push) where the app sets none.
    public var postZoom: Namespace.ID? {
        get { self[PostZoomKey.self] }
        set { self[PostZoomKey.self] = newValue }
    }
}

private struct PostZoomKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension View {
    /// On a post's card: the shape its page grows out of and shrinks back into.
    func zoomSource(of post: CheckInID) -> some View {
        modifier(PostZoomSource(post: post))
    }

    /// On a post's page pushed from its card on 动态: it grows out of the card, which stays where
    /// it was in the list, and shrinks back into it as it closes, following a swipe back with
    /// the finger (the approved motion mockup, 2026-11-24). Nothing without a `zoom`.
    public func zooms(fromCardOf post: CheckInID, in zoom: Namespace.ID?) -> some View {
        modifier(PostZoomDestination(post: post, zoom: zoom))
    }
}

private struct PostZoomSource: ViewModifier {
    @Environment(\.postZoom) private var zoom
    let post: CheckInID

    func body(content: Content) -> some View {
        if let zoom {
            content.matchedTransitionSource(id: post, in: zoom) { source in
                source.clipShape(RoundedRectangle(cornerRadius: Radius.ticket, style: .continuous))
            }
        } else {
            content
        }
    }
}

private struct PostZoomDestination: ViewModifier {
    let post: CheckInID
    let zoom: Namespace.ID?

    func body(content: Content) -> some View {
        if let zoom {
            content.navigationTransition(.zoom(sourceID: post, in: zoom))
        } else {
            content
        }
    }
}
#endif
