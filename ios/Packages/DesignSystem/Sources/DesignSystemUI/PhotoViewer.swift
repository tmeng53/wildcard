#if os(iOS)
import DesignSystem
import SwiftUI
import UIKit

extension View {
    /// Opens a post's photos full screen when `isPresented` turns on, zooming out of this view
    /// as the Photos app does: the whole photo on ink, pinch or double tap to zoom in, swipe
    /// between them, swipe down (or 关闭) to put it back. `page` is the photo showing, shared
    /// with this view, so closing on the second photo leaves the second one showing here.
    /// `load` gives photo `index` as JPEG (or any format ImageIO reads), nil while it can't.
    public func photoViewer(
        isPresented: Binding<Bool>, count: Int, page: Binding<Int>,
        load: @escaping @Sendable (Int) async -> Data?
    ) -> some View {
        pageViewer(isPresented: isPresented, count: count, page: page) { index, isShowing in
            ViewerPhoto(isShowing: isShowing) { await load(index) }
                .accessibilityLabel(Text(copy: "第 \(index + 1) 张，共 \(count) 张", bundle: .module))
        }
    }

    /// The same full-screen viewer for pages that aren't all photos (a post's map or chart beside
    /// its photos): `content` draws page `index`, told whether it is the one showing; a photo's
    /// page is a `ViewerPhoto`.
    public func pageViewer<Page: View>(
        isPresented: Binding<Bool>, count: Int, page: Binding<Int>,
        @ViewBuilder content: @escaping (_ index: Int, _ isShowing: Bool) -> Page
    ) -> some View {
        modifier(PageViewerPresenter(isPresented: isPresented, count: count, page: page, content: content))
    }
}

/// The zoom from the pages on the screen to the viewer and back, which also gives the viewer
/// its swipe down to close.
private struct PageViewerPresenter<Page: View>: ViewModifier {
    @Binding var isPresented: Bool
    let count: Int
    @Binding var page: Int
    let content: (Int, Bool) -> Page
    @Namespace private var zoom

    func body(content view: Content) -> some View {
        view
            .matchedTransitionSource(id: Self.source, in: zoom)
            .fullScreenCover(isPresented: $isPresented) {
                PageViewer(count: count, page: $page, content: content)
                    .navigationTransition(.zoom(sourceID: Self.source, in: zoom))
            }
    }

    private static var source: String { "photos" }
}

/// The pages full screen, one each, on ink.
struct PageViewer<Page: View>: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let count: Int
    @Binding var page: Int
    let content: (Int, Bool) -> Page

    var body: some View {
        TabView(selection: $page) {
            ForEach(0..<count, id: \.self) { index in
                content(index, index == page)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: count > 1 ? .always : .never))
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            HeaderButton(Text(copy: "关闭", bundle: .module), systemImage: "xmark", on: .ink) { dismiss() }
                .padding(.horizontal, Space.m)
                .accessibilityIdentifier("photoViewer.close")
        }
        .background(Color(role: .bgInk, in: theme).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photoViewer")
    }
}

/// One photo of the viewer, zoomable, decoded off the main actor so the swipe to it doesn't drop
/// frames. `load` gives it as JPEG (or any format ImageIO reads), nil while it can't.
public struct ViewerPhoto: View {
    private let isShowing: Bool
    private let load: @Sendable () async -> Data?
    @State private var image: UIImage?

    public init(isShowing: Bool, load: @escaping @Sendable () async -> Data?) {
        self.isShowing = isShowing
        self.load = load
    }

    public var body: some View {
        ZoomablePhoto(image: image, isShowing: isShowing)
            .task {
                guard let data = await load() else { return }
                image = await Self.decode(data)
            }
            .accessibilityElement()
            .accessibilityAddTraits(.isImage)
    }

    private nonisolated static func decode(_ data: Data) async -> UIImage? {
        await UIImage(data: data)?.byPreparingForDisplay()
    }
}

/// UIKit's scroll view, for the zoom the Photos app has: pinch, a double tap to zoom in on a
/// spot and out again, rubber-banding at the edges. SwiftUI has no zooming scroll view.
/// A photo swiped away goes back to whole, as in the Photos app.
private struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage?
    let isShowing: Bool

    func makeUIView(context: Context) -> ZoomingView { ZoomingView() }

    func updateUIView(_ view: ZoomingView, context: Context) {
        view.show(image)
        if !isShowing { view.zoomOut() }
    }
}

/// The photo fitted whole, centred, zoomed up to `maximumZoomScale` times.
final class ZoomingView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var fittedBounds: CGSize = .zero
    /// How far a double tap zooms in.
    private let doubleTapZoom: CGFloat = 2.5

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show(_ image: UIImage?) {
        guard imageView.image !== image else { return }
        imageView.image = image
        fit()
    }

    /// Back to the whole photo at once, for a page swiped away.
    func zoomOut() {
        guard zoomScale != minimumZoomScale else { return }
        setZoomScale(minimumZoomScale, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedBounds { fit() }
    }

    /// Back to the whole photo, as large as fits.
    private func fit() {
        fittedBounds = bounds.size
        zoomScale = 1
        guard let size = imageView.image?.size, size.width > 0, size.height > 0, bounds.width > 0 else { return }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        imageView.frame = CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale))
        contentSize = imageView.frame.size
        center()
    }

    /// Keeps a photo smaller than the screen in the middle of it.
    private func center() {
        let horizontal = max((bounds.width - contentSize.width) / 2, 0)
        let vertical = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    @objc private func doubleTapped(_ tap: UITapGestureRecognizer) {
        guard zoomScale == minimumZoomScale else {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }
        let spot = tap.location(in: imageView)
        let size = CGSize(width: bounds.width / doubleTapZoom, height: bounds.height / doubleTapZoom)
        zoom(
            to: CGRect(origin: CGPoint(x: spot.x - size.width / 2, y: spot.y - size.height / 2), size: size),
            animated: true)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { center() }
}
#endif
