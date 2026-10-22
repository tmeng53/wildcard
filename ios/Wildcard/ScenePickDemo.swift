import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInUI
import DesignSystem
import DesignSystemUI
import Foundation
import ScenePickDomain
import ScenePickUI
import SwiftUI

/// Opens the scene pick on its own, until the 战报's last page and squad settings put it in their
/// flows: the sticker where the approved design puts it on that page, the squad along the bottom,
/// and the reveal after 「就它了」, ending on the picked scene where home will take over.
/// `-scene-pick` opens it; `-scene-pick-members 8` brings eight (the queue); UI tests add
/// `-scene-pick-reveal <scene> <seconds>` to hold the reveal of that scene on one moment.
@MainActor
enum ScenePickDemo {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-scene-pick") }

    static var members: Int {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-scene-pick-members"), flag + 1 < arguments.count,
            let count = Int(arguments[flag + 1])
        else { return 5 }
        return min(max(count, 1), 8)
    }

    /// The reveal to hold, from `-scene-pick-reveal`.
    static var frozen: (scene: SceneTheme, time: Double)? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-scene-pick-reveal"), flag + 2 < arguments.count,
            let scene = SceneTheme(rawValue: arguments[flag + 1]), let time = Double(arguments[flag + 2])
        else { return nil }
        return (scene, time)
    }

    /// The design's squad: it trains at the track this week and was at the pool 5 weeks ago, and
    /// has never opened the rest.
    static let options = [
        SceneOption(scene: .track, lastTrained: .thisWeek),
        SceneOption(scene: .pool, lastTrained: .weeksAgo(5)),
        SceneOption(scene: .gym, lastTrained: .never),
        SceneOption(scene: .tennis, lastTrained: .never),
        SceneOption(scene: .climbing, lastTrained: .never),
    ]

    /// Stand-in teammates, each a different look and persona.
    static func squad(_ count: Int) -> [CharacterPlayer] {
        let looks = [
            PlaceholderCharacter.lifter,
            Outfit(["body": "cat", "hat": "cap", "top": "tank", "bottom": "greenshorts", "prop": "racket"]),
            Outfit(["body": "bear", "top": "hoodie", "bottom": "leggings"]),
            Outfit([
                "body": "peach", "hair": "buzz", "eyes": "sharp", "brows": "bold", "mouth": "smirk",
                "hat": "headband", "top": "jersey", "bottom": "shorts",
            ]),
        ]
        return (0..<count).compactMap { index in
            let persona = Persona.allCases[index % Persona.allCases.count]
            guard let figure = try? PlaceholderCharacter.figure(wearing: looks[index % looks.count]),
                let idle = try? PlaceholderCharacter.clip("idle", persona: persona)
            else { return nil }
            return try? CharacterPlayer(
                figure: figure, idle: idle, now: Date().addingTimeInterval(-Double(index) * 0.6))
        }
    }
}

/// A pick that always goes through, as the API will once it lands.
private struct DemoPickService: ScenePickService {
    func pick(_ scene: SceneTheme) async throws(ScenePickError) {}
}

struct ScenePickDemoView: View {
    private struct Reveal {
        let unboxing: Unboxing
        let scene: SceneTheme
        let startedAt: Date
        let frozenAt: Double?
    }

    @State private var picker = ScenePicker(options: ScenePickDemo.options, service: DemoPickService())
    @State private var players = ScenePickDemo.squad(ScenePickDemo.members)
    @State private var reveal: Reveal? = ScenePickDemo.frozen.map { frozen in
        let opened = ScenePickDemo.options.first { $0.scene == frozen.scene }?.isOpened ?? false
        return Reveal(unboxing: Unboxing(boxed: !opened), scene: frozen.scene, startedAt: .now, frozenAt: frozen.time)
    }
    @State private var landed: SceneTheme?

    var body: some View {
        if let landed {
            SceneBackdrop(scene: landed)
                .ignoresSafeArea()
        } else if let reveal {
            UnboxRevealView(
                reveal.unboxing, scene: reveal.scene, startedAt: reveal.startedAt, frozenAt: reveal.frozenAt,
                onFinished: { landed = reveal.scene },
                page: { page },
                backdrop: { SceneBackdrop(scene: reveal.scene) })
        } else {
            page
        }
    }

    /// The 战报's last page as far as the pick needs it: the sticker where the design puts it and
    /// the squad standing above the page's buttons, laid out on the design's 390 × 844 stage.
    private var page: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / Unboxing.stage.width
            ZStack(alignment: .top) {
                SceneSticker(picker: picker) { unboxing, scene in
                    reveal = Reveal(unboxing: unboxing, scene: scene, startedAt: .now, frozenAt: nil)
                }
                .position(x: Unboxing.stage.width / 2, y: Self.stickerCenter)
                SquadLineup(players: players)
                    .frame(height: Self.lineupHeight)
                    .offset(y: Self.lineupTop)
                Color(role: .bgCanvas, in: .pool)
                    .frame(height: Self.buttonsHeight)
                    .offset(y: Unboxing.stage.height - Self.buttonsHeight)
            }
            .frame(width: Unboxing.stage.width, height: Unboxing.stage.height, alignment: .top)
            .scaleEffect(unit, anchor: .topLeading)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .background(Color(role: .bgScene, in: .pool))
        .environment(\.sceneTheme, .pool)
        .ignoresSafeArea()
    }

    // Where the design's page puts things, on its 390 × 844 stage.
    private static let stickerCenter = 376.0
    private static let lineupHeight = 96.0
    /// The page's buttons: 存图 and 排下周 on white, 144 high, which the squad stands 12 into.
    private static let buttonsHeight = 144.0
    private static let lineupTop = Unboxing.stage.height - buttonsHeight + 12 - lineupHeight
}
