#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// 三拍, the loader for a button or a line (loader design A, 2026-10-24): three dots hopping in
/// turn like running steps, in the foreground style around them (ink on a brand page, the scene's
/// colour on its turf, white in a filled button). It shows only once the wait has lasted `delay`.
/// With Reduce Motion on, the dots stay put and only brighten in turn. A whole page waits with the
/// character instead (`AvatarUI`'s `LoadingCharacter`).
public struct LoadingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let delay: Double
    @State private var isShown: Bool

    /// `delay`: 0 shows the dots at once, for a caller that has already waited.
    public init(delay: Double = Loading.inlineDelay) {
        self.delay = delay
        _isShown = State(initialValue: delay <= 0)
    }

    public var body: some View {
        TimelineView(.animation(paused: !isShown)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: Loading.dotGap) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .frame(width: Loading.dot, height: Loading.dot)
                        .opacity(Loading.dotOpacity(dot: index, at: time))
                        .offset(y: reduceMotion ? 0 : -Loading.dotRise * Loading.hop(dot: index, at: time))
                }
            }
            .frame(width: Loading.dotsWidth, height: Loading.dot + Loading.dotRise, alignment: .bottom)
        }
        .opacity(isShown ? 1 : 0)
        .task {
            guard !isShown else { return }
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            isShown = true
        }
        .accessibilityElement()
        .accessibilityLabel(Text("加载中", bundle: .module))
        .accessibilityHidden(!isShown)
    }
}

extension View {
    /// A control's label while its action is under way: once `isWorking` has lasted
    /// `Loading.inlineDelay`, 三拍 takes the label's place, and stays at least
    /// `Loading.minimumShown`. The control keeps its size; the caller stops it taking taps.
    public func loadingLabel(_ isWorking: Bool) -> some View {
        modifier(LoadingLabel(isWorking: isWorking))
    }

    /// A page, or the part of one, while what it shows is read: once `isLoading` has lasted
    /// `Loading.pageDelay`, `loader` covers it (the character jogging, on the page's own
    /// background, so nothing under it shows through), and stays at least `Loading.minimumShown`,
    /// fading out over what arrived.
    public func loadingCover(_ isLoading: Bool, @ViewBuilder loader: () -> some View) -> some View {
        modifier(LoadingCover(isLoading: isLoading, loader: loader()))
    }
}

/// A small part of a control (an icon beside its words) that turns into 三拍 while the control's
/// action is under way, with `loadingLabel`'s timing. Unlike `loadingLabel`, the dots take the
/// part's place rather than its frame, for a part narrower than they are.
public struct LoadingSwap<Idle: View>: View {
    private let isWorking: Bool
    private let idle: Idle
    @State private var gate = WaitGate()

    public init(_ isWorking: Bool, @ViewBuilder idle: () -> Idle) {
        self.isWorking = isWorking
        self.idle = idle()
    }

    public var body: some View {
        Group {
            if gate.isShown { LoadingDots(delay: 0) } else { idle }
        }
        .task(id: isWorking) { await gate.follow(isWorking, delay: Loading.inlineDelay) }
    }
}

struct LoadingLabel: ViewModifier {
    let isWorking: Bool
    @State private var gate = WaitGate()

    func body(content: Content) -> some View {
        content
            .opacity(gate.isShown ? 0 : 1)
            // The dots speak for the control while they show.
            .accessibilityHidden(gate.isShown)
            .overlay {
                if gate.isShown { LoadingDots(delay: 0) }
            }
            .task(id: isWorking) { await gate.follow(isWorking, delay: Loading.inlineDelay) }
    }
}

struct LoadingCover<Loader: View>: ViewModifier {
    let isLoading: Bool
    let loader: Loader
    @State private var gate = WaitGate()

    func body(content: Content) -> some View {
        content
            // Under the cover, VoiceOver reads only the cover.
            .accessibilityHidden(gate.isShown)
            .overlay {
                if gate.isShown {
                    // One element saying it is loading, whatever the loader hides from VoiceOver.
                    loader
                        .transition(.opacity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("加载中", bundle: .module))
                        .accessibilityIdentifier("loading.cover")
                }
            }
            .animation(.wildcard(Motion.fadeIn), value: gate.isShown)
            .task(id: isLoading) { await gate.follow(isLoading, delay: Loading.pageDelay) }
    }
}

/// When a loader shows: only after a wait of `delay`, and then for at least `Loading.minimumShown`.
@MainActor @Observable
final class WaitGate {
    private(set) var isShown = false
    private var shownAt: ContinuousClock.Instant?

    /// Follows the wait starting (`waiting`) or ending. A `task(id:)` calls it, so a change
    /// cancels the step before it: a wait that ends before `delay` never shows.
    func follow(_ waiting: Bool, delay: Double) async {
        if waiting {
            guard !isShown else { return }
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            shownAt = .now
            isShown = true
        } else {
            guard isShown, let shownAt else { return }
            let shown = ContinuousClock.now - shownAt
            let seconds = Double(shown.components.seconds) + Double(shown.components.attoseconds) / 1e18
            let hold = Loading.hold(afterShowing: seconds)
            if hold > 0 {
                try? await Task.sleep(for: .seconds(hold))
                guard !Task.isCancelled else { return }
            }
            isShown = false
            self.shownAt = nil
        }
    }
}
#endif
