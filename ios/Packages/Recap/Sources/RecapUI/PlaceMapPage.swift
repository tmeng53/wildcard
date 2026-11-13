#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import MapKit
import RecapDomain
import SwiftUI

/// 小队最爱去 and 新发现: one place on a full-bleed map under the title. The frosted map clears and
/// closes in on the place, the heads of who trained there drop onto it one by one, then the count
/// (or 新) and the place's name pop in; 新发现 also sends two ripples out. A tap on the heads fans
/// them out, each with its line; a tap on the name opens 地点页; the map drags a little. The
/// squad's other places that week sit faint around it. From the approved prototype (2026-11-12).
struct PlaceMapPage: View {
    enum Kind {
        /// 小队最爱去: each head's line is how many times they trained there.
        case favorite
        /// 新发现: each head's line is the first day they trained there.
        case discovery
    }

    let kind: Kind
    let spotlight: PlaceSpotlight
    let page: PageContext
    /// Pushes 地点页 over the story.
    let openPlace: (Place) -> Void
    /// The reader played with the page: it stays up until they tap on.
    let stay: () -> Void
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Everyone's head, made once as the page appears (not in `init`: the page is made anew on
    /// every frame of its clock).
    @State private var heads: [MemberID: CharacterPlayer] = [:]
    @State private var fanned = false
    @State private var pan = CGSize.zero
    @State private var panStart: CGSize?

    var body: some View {
        GeometryReader { proxy in
            let focus = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * MapPageLayout.focusHeight)
            ZStack(alignment: .top) {
                map(height: focus.y * 2)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    .clipped()
                    // The map itself takes no touch; the page drags it, alongside the story's own
                    // touch, so a tap still moves on and a pull down still closes.
                    .contentShape(Rectangle())
                    .offset(pan)
                    .simultaneousGesture(drag)
                marker(width: proxy.size.width)
                    .position(focus)
                    .offset(pan)
                PageTitle(label: label, title: title, onMap: true)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear(perform: makeHeads)
        .onChange(of: spotlight, makeHeads)
    }

    private var label: Text { Text(copy: "本周", bundle: .module) }

    private var title: Text {
        switch kind {
        case .favorite: Text(copy: "小队最爱去", bundle: .module)
        case .discovery: Text(copy: "新发现", bundle: .module)
        }
    }

    // MARK: The map

    /// The map centred on the place (`height` is twice the place's depth on the page, so its middle
    /// is the place), frosted until it clears and closing in as it does.
    private func map(height: Double) -> some View {
        let clear = Self.ease(page.ramp(MapPageLayout.clearStart, MapPageLayout.clearStart + MapPageLayout.clearLength))
        return Map(
            initialPosition: .camera(
                MapCamera(
                    centerCoordinate: Self.coordinate(of: spotlight.place.place), distance: MapPageLayout.cameraDistance
                )),
            interactionModes: []
        ) {
            ForEach(pins, id: \.key) { pin in
                Annotation(pin.name, coordinate: pin.coordinate, anchor: .bottom) {
                    FaintPin(head: heads[pin.member])
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .annotationTitles(.hidden)
        .allowsHitTesting(false)
        .frame(height: height)
        .scaleEffect(1 + (MapPageLayout.zoom - 1) * clear)
        .blur(radius: MapPageLayout.frost * (1 - clear))
        .overlay { Color(role: .bgCanvas, in: theme).opacity(MapPageLayout.fog * (1 - clear)) }
        .accessibilityHidden(true)
    }

    /// The squad's other places that week, each with the first of those who trained there.
    private var pins: [Pin] {
        spotlight.others.compactMap { other in
            other.visitors.first.map {
                Pin(
                    key: other.key, name: other.place.name, coordinate: Self.coordinate(of: other.place),
                    member: $0.member)
            }
        }
    }

    private struct Pin {
        let key: String
        let name: String
        let coordinate: CLLocationCoordinate2D
        let member: MemberID
    }

    /// The map drags a little way and stays where it is let go.
    private var drag: some Gesture {
        DragGesture(minimumDistance: Space.xs)
            .onChanged { drag in
                let start = panStart ?? pan
                if panStart == nil {
                    panStart = pan
                    stay()
                }
                pan = CGSize(
                    width: Self.clamp(start.width + drag.translation.width),
                    height: Self.clamp(start.height + drag.translation.height))
            }
            .onEnded { _ in panStart = nil }
    }

    // MARK: The heads and the place's name

    private var people: [PlaceWeek.Visitor] { Array(spotlight.place.visitors.prefix(MapPageLayout.headLimit)) }

    private var headSize: Double { kind == .favorite ? 50 : 60 }

    /// The heads over the place, the count or 新 on them and the place's name under them, as one
    /// piece the size of the page's width.
    private func marker(width: Double) -> some View {
        let size = headSize
        let count = people.count
        let gap = count > 1 ? min(size + 30, (width - 2 * Space.m - size) / Double(count - 1)) : 0
        return ZStack {
            if kind == .discovery { ripples }
            ForEach(Array(people.enumerated()), id: \.element.member) { index, visitor in
                let middle = Double(index) - Double(count - 1) / 2
                head(visitor, index: index)
                    .offset(x: fanned ? middle * gap : middle * size * 0.56)
                    .zIndex(Double(count - index))
            }
            badge
                .offset(
                    x: (Double(count - 1) / 2) * size * 0.56 + size / 2 - 10,
                    y: -size / 2 - 8
                )
                .opacity(fanned ? 0 : 1)
                .zIndex(Double(count + 1))
            fanButton(width: width)
                .zIndex(Double(count + 2))
            placeLabel
                .offset(y: size / 2 + 2 + (fanned ? MapPageLayout.lineHeight : 0) + MapPageLayout.labelHeight / 2)
                .zIndex(Double(count + 3))
        }
        .frame(width: width, height: size + 2 * MapPageLayout.labelHeight + MapPageLayout.lineHeight)
    }

    private func head(_ visitor: PlaceWeek.Visitor, index: Int) -> some View {
        let start = (kind == .favorite ? 1.3 : 1.35) + Double(index) * 0.12
        let drop = page.pop(start, start + 0.62)
        return MemberHead(player: heads[visitor.member], size: headSize)
            .overlay(alignment: .top) {
                line(visitor)
                    .fixedSize()
                    .offset(y: headSize + 2)
                    .opacity(fanned ? 1 : 0)
                    .animation(
                        .wildcard(Motion.change, reduceMotion: reduceMotion).delay(fanned ? 0.15 : 0), value: fanned)
            }
            .offset(y: -70 * (1 - drop))
            .opacity(page.ramp(start, start + 0.37))
    }

    /// One tight line under a fanned-out head: their name, then how often or since when.
    private func line(_ visitor: PlaceWeek.Visitor) -> some View {
        HStack(spacing: Space.xxs) {
            Text(verbatim: page.cast.nickname(of: visitor.member))
                .typeStyle(TypeRamp.captionEmphasis)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
            Group {
                switch kind {
                case .favorite: Text(copy: "\(visitor.visits) 次", bundle: .module)
                case .discovery: Text(verbatim: "\(visitor.firstDay.month).\(visitor.firstDay.day)")
                }
            }
            .typeStyle(TypeRamp.caption)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
        }
        .frame(height: MapPageLayout.lineHeight)
    }

    /// The whole week's 训练 there, or 新, on the graphite badge.
    private var badge: some View {
        let shown = page.pop(kind == .favorite ? 1.85 : 1.9, (kind == .favorite ? 1.85 : 1.9) + 0.42)
        return Group {
            switch kind {
            case .favorite: Text(verbatim: "\(spotlight.place.visits.count)")
            case .discovery: Text(copy: "新", bundle: .module)
            }
        }
        .typeStyle(TypeRamp.captionEmphasis)
        .foregroundStyle(Color(role: .fgOnInk, in: theme))
        .padding(.horizontal, Space.xs)
        .frame(minWidth: 24, minHeight: 24)
        .background(Color(role: .bgInk, in: theme), in: Capsule())
        .scaleEffect(max(shown, 0.01))
        .opacity(min(max(shown, 0), 1))
        .accessibilityHidden(true)
    }

    /// The heads' tap target: fans them out and back.
    private func fanButton(width: Double) -> some View {
        Button {
            stay()
            withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) { fanned.toggle() }
        } label: {
            Color.clear
                .frame(width: min(180, width), height: headSize + 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: people.map { page.cast.nickname(of: $0.member) }.joined(separator: "、")))
        .accessibilityIdentifier("recap.place.heads")
    }

    /// The place's name on a white pill, which opens 地点页.
    private var placeLabel: some View {
        let start = kind == .favorite ? 2.0 : 2.05
        return Button {
            openPlace(spotlight.place.place)
        } label: {
            HStack(spacing: Space.xs) {
                Text(verbatim: spotlight.place.place.name)
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(1)
                if kind == .favorite {
                    Text(copy: "\(spotlight.place.visits.count) 次", bundle: .module)
                        .typeStyle(TypeRamp.callout)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
                Image(systemName: "chevron.right")
                    .typeStyle(TypeRamp.captionEmphasis)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Space.s)
            .frame(height: MapPageLayout.labelHeight)
            .background(Color(role: .bgCanvas, in: theme), in: Capsule())
            .shadow(color: Color(role: .fgDefault, in: theme).opacity(0.12), radius: 9, y: 6)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.horizontal, Space.m)
        .opacity(page.ramp(start, start + 0.3))
        .accessibilityIdentifier("recap.place.open")
    }

    /// 新发现's two rings going out from the place.
    private var ripples: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { ring in
                let start = 1.65 + Double(ring) * 0.32
                let spread = page.moves ? page.ramp(start, start + 1.1) : 1
                Circle()
                    .stroke(Color(role: .bgInk, in: theme), lineWidth: 2)
                    .frame(width: 100, height: 100)
                    .scaleEffect(0.4 + 1.5 * spread)
                    .opacity(page.time < start || !page.moves ? 0 : 0.5 * (1 - spread))
            }
        }
        .accessibilityHidden(true)
    }

    private func makeHeads() {
        let members = spotlight.place.visitors.map(\.member) + spotlight.others.compactMap { $0.visitors.first?.member }
        heads = Dictionary(
            members.compactMap { member in page.cast.player(of: member).map { (member, $0) } },
            uniquingKeysWith: { first, _ in first })
    }

    private static func coordinate(of place: Place) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, -MapPageLayout.panLimit), MapPageLayout.panLimit)
    }

    /// Slow in and out, as the prototype's frost and zoom.
    private static func ease(_ fraction: Double) -> Double {
        fraction * fraction * (3 - 2 * fraction)
    }
}

/// Where 小队最爱去 and 新发现 put things, from the approved prototype.
private enum MapPageLayout {
    /// How far down the page the place sits.
    static let focusHeight = 0.56
    static let cameraDistance: Double = 2400
    /// The map closes in this much on the place.
    static let zoom = 1.25
    /// The frost's blur and the white over it, as they start.
    static let frost: Double = 16
    static let fog = 0.18
    static let clearStart = 0.2
    static let clearLength = 1.4
    /// How far the map drags each way.
    static let panLimit: Double = 50
    static let headLimit = 5
    static let lineHeight: Double = 16
    static let labelHeight: Double = 36
}

/// Another place the squad trained at that week: someone who did, faint, on a pin.
private struct FaintPin: View {
    let head: CharacterPlayer?
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            MemberHead(player: head, size: 30)
            Rectangle()
                .fill(Color(role: .bgCanvas, in: theme))
                .frame(width: 10, height: 10)
                .rotationEffect(.degrees(45))
                .offset(y: -6)
                .frame(height: 4, alignment: .top)
        }
        .opacity(0.55)
    }
}

#endif
