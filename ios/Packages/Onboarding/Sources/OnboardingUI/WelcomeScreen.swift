#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CharacterEditorDomain
import CharacterEditorUI
import DesignSystem
import DesignSystemUI
import Observation
import SwiftUI

/// The open screen: the app's name, one line, and five characters on the scene's floor, two at
/// the back and three in front, the middle one biggest. Every so often one of them changes
/// into another look, and a tap changes it too. The middle one's look is where 角色和昵称
/// starts. Then 通过 Apple 继续, and the terms under it.
struct WelcomeScreen<SignIn: View>: View {
    let model: SignUpModel
    let policies: PolicyLinks
    let signIn: SignIn
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var crowd = WelcomeCrowd()

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / WelcomeCrowd.designWidth
            ZStack(alignment: .top) {
                floor(unit: unit)
                VStack(spacing: Space.xs) {
                    Text("WILDCARD", bundle: .module)
                        .typeStyle(TypeRamp.scoreHero)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                    Text("人人都是运动员", bundle: .module)
                        .typeStyle(TypeRamp.headline)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                }
                .padding(.top, proxy.size.height * WelcomeCrowd.titleTop)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                ForEach(crowd.spots.indices, id: \.self) { index in
                    crowdMember(index, unit: unit, bottom: proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Space.s) {
                FailureLine(failure: model.failure)
                signIn
                    .frame(height: Sizing.primaryControl)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("signup.signIn")
                Text(termsLine)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .tint(Color(role: .fgDefault, in: theme))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("signup.terms")
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.bottom, Space.xs)
        }
        .background(Color(role: .bgSubtle, in: theme).ignoresSafeArea())
        .task { await crowd.start(reduceMotion: reduceMotion) }
        .onDisappear { crowd.stop() }
        .onChange(of: crowd.middleLook) { _, look in model.welcomeLook = look }
    }

    /// 继续即表示同意用户协议和隐私政策, with 用户协议 and 隐私政策 underlined links to their pages.
    /// The catalog marks them `terms:` and `privacy:`, which become the pages the app passes.
    private var termsLine: AttributedString {
        var line = AttributedString(
            localized: "继续即表示同意[用户协议](terms:)和[隐私政策](privacy:)", bundle: .module)
        for (link, range) in line.runs[\.link] {
            guard let link else { continue }
            line[range].link = link.scheme == "terms" ? policies.terms : policies.privacyPolicy
            line[range].underlineStyle = .single
        }
        return line
    }

    /// The scene's floor across the lower part of the screen, under the characters' feet.
    private func floor(unit: Double) -> some View {
        SceneFloor()
            .frame(height: WelcomeCrowd.floorAbove * unit)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
    }

    private func crowdMember(_ index: Int, unit: Double, bottom: Double) -> some View {
        let spot = crowd.spots[index]
        let width = spot.width * unit
        let height = width * WelcomeCrowd.aspect
        let feet = bottom - spot.feetAbove * unit
        return Button {
            crowd.swap(index)
        } label: {
            ZStack {
                if let player = crowd.players[index] {
                    CharacterView(player: player)
                        .id(crowd.versions[index])
                        .transition(
                            reduceMotion ? .opacity : .scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: width, height: height)
            .animation(.wildcard(Motion.celebrate, reduceMotion: reduceMotion), value: crowd.versions[index])
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("换一个外卡运动员", bundle: .module))
        .accessibilityIdentifier("signup.crowd")
        .haptic(.pick, trigger: crowd.taps[index])
        // Feet on the floor: the canvas's feet sit near its bottom.
        .position(x: spot.centerX * unit, y: feet - height * WelcomeCrowd.feetInCanvas + height / 2)
        // Nearer the front draws on top, and everyone over the floor (zIndex 0).
        .zIndex(1 / (1 + spot.feetAbove))
    }
}

/// The open screen's five characters and the looks they change between.
@MainActor @Observable
final class WelcomeCrowd {
    struct Spot {
        let centerX: Double
        /// How far above the bottom of the screen's free area, over the sign-in button.
        let feetAbove: Double
        let width: Double
    }

    /// The design's points, on a 390-point-wide screen: two back, three in front, standing up
    /// from the sign-in button so it never covers their feet, however tall the phone is.
    static let designWidth = 390.0
    let spots = [
        Spot(centerX: 122, feetAbove: 106, width: 96), Spot(centerX: 268, feetAbove: 106, width: 96),
        Spot(centerX: 62, feetAbove: 30, width: 112), Spot(centerX: 195, feetAbove: 16, width: 132),
        Spot(centerX: 328, feetAbove: 30, width: 112),
    ]
    /// The middle one, whose look 角色和昵称 starts from.
    static let middle = 3
    /// Who changes next, round and round: the middle first.
    static let order = [3, 0, 4, 2, 1]
    static let interval: Duration = .milliseconds(1500)
    /// How many looks the crowd changes between.
    static let looks = 8
    /// The canvas is 240 by 320; its feet stand at 96% of its height.
    static let aspect = 320.0 / 240.0
    static let feetInCanvas = 0.957
    /// The title's top, as a fraction of the screen's height.
    static let titleTop = 0.12
    /// The floor's top, in design points above the bottom of the free area: above the back row.
    static let floorAbove = 146.0

    private(set) var players: [CharacterPlayer?] = Array(repeating: nil, count: 5)
    /// Bumped on every change, so the new look pops in.
    private(set) var versions = Array(repeating: 0, count: 5)
    private(set) var taps = Array(repeating: 0, count: 5)
    private(set) var middleLook: Outfit?
    @ObservationIgnored private var pool: [(outfit: Outfit, player: CharacterPlayer)] = []
    /// Which of `pool` each spot shows.
    @ObservationIgnored private var shown: [Int] = []
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var tick = 0

    /// Builds the looks off the main actor, shows five, then changes one every `interval`.
    func start(reduceMotion: Bool) async {
        guard pool.isEmpty, let catalog = try? Catalog.placeholder() else { return }
        var generator = SystemRandomNumberGenerator()
        var looks: [Outfit] = []
        while looks.count < Self.looks {
            // What a draft of it wears: an animal leaves out a person's hair and face.
            let look = CharacterDraft(
                catalog: catalog, look: CharacterDraft.randomLook(from: catalog, using: &generator),
                persona: .energetic, nickname: ""
            ).outfit
            if !looks.contains(look) { looks.append(look) }
        }
        for look in looks {
            let persona = Persona.allCases.randomElement(using: &generator) ?? .energetic
            guard let figure = try? await CastMember.figure(wearing: look),
                let idle = try? PlaceholderCharacter.clip("idle", persona: persona),
                let player = try? CharacterPlayer(figure: figure, idle: reduceMotion ? .still : idle)
            else { continue }
            pool.append((look, player))
        }
        guard pool.count >= spots.count else { return }
        shown = Array(0..<spots.count)
        players = shown.map { pool[$0].player }
        middleLook = pool[shown[Self.middle]].outfit
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard let self, !Task.isCancelled else { return }
                self.change(Self.order[self.tick % Self.order.count])
                self.tick += 1
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// A tap: this one changes now, and plays its pick.
    func swap(_ index: Int) {
        taps[index] += 1
        change(index)
    }

    /// Changes one spot into a look no other spot is showing.
    private func change(_ index: Int) {
        let free = pool.indices.filter { !shown.contains($0) }
        guard let next = free.randomElement() else { return }
        shown[index] = next
        players[index] = pool[next].player
        versions[index] += 1
        if index == Self.middle { middleLook = pool[next].outfit }
    }
}
#endif
