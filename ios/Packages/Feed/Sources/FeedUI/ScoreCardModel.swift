#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import FeedDomain
import Foundation
import ImageIO
import Observation
import SportsUI
import UIKit

/// The 成绩卡's sheet over one of the member's 训练: what they picked (`ScoreCard`), the post's
/// pictures as they load, 本周第 N 次 and the character's still in each pose.
@MainActor @Observable
final class ScoreCardModel: Identifiable {
    typealias Still = (drawing: FigureDrawing, placements: [Placement])

    let checkIn: CheckIn
    let training: Training
    private(set) var card: ScoreCard
    /// The author's nickname, top left.
    let nickname: String?
    /// The squad's name, bottom right while 小队名 is on; nil hides the switch.
    let squadName: String?
    /// The post's numbers as its 成绩条 shows them.
    let cells: [WorkoutCell: ScoreCell]
    /// 本周第 N 次, once read.
    private(set) var weekCount: Int?
    /// The post's photos as they load.
    private(set) var photos: [PhotoRef: CGImage] = [:]
    /// The route as a still map, once drawn.
    private(set) var map: UIImage?
    /// Bumps on each tap on the character, which hops.
    private(set) var hops = 0
    /// Bumps on each tap that changes the card, for its haptic.
    private(set) var changes = 0
    /// 点数字和人物可以换, under the preview until the member first taps anything.
    private(set) var showsHint: Bool

    @ObservationIgnored private let look: Outfit
    @ObservationIgnored private let persona: Persona
    @ObservationIgnored private let species: String?
    @ObservationIgnored private var stills: [ScoreCard.Pose: Still] = [:]
    @ObservationIgnored private let defaults: UserDefaults

    nonisolated var id: CheckInID { checkIn.id }

    /// The picture's own size, in points: 3:4, the 出赛表 poster's.
    static let size = CGSize(width: 360, height: 480)
    /// The top of an A2 card, where the picture is, in card points.
    static let pictureSize = CGSize(width: 360, height: 300)
    /// Remembered on the phone once the hint was tapped away.
    static let hintSeenKey = "scoreCard.hintSeen"

    /// Nil for a post that isn't a 训练.
    init?(
        _ checkIn: CheckIn, character: MemberCharacter?, squadName: String?, defaults: UserDefaults
    ) {
        guard case .trained(let training) = checkIn.entry else { return nil }
        self.checkIn = checkIn
        self.training = training
        nickname = character?.nickname.text
        self.squadName = squadName.flatMap { $0.isEmpty ? nil : $0 }
        look = character?.look.outfit ?? PlaceholderCharacter.lifter
        persona = character?.look.moves ?? .energetic
        species = character?.look.species
        cells = Dictionary(ScoreCell.cells(of: training).map { ($0.cell, $0) }, uniquingKeysWith: { first, _ in first })
        card = ScoreCard(training: training, hasKit: Self.kits != nil, holdsProp: look.variants["prop"] != nil)
        self.defaults = defaults
        showsHint = !defaults.bool(forKey: Self.hintSeenKey)
    }

    // MARK: Taps

    /// The next number stands big.
    func tapHero() {
        card.nextHero()
        changed()
    }

    /// Strikes a number of the strip out of the picture, or brings it back.
    func tap(_ cell: WorkoutCell) {
        card.toggle(cell)
        changed()
    }

    /// The character hops into its next pose.
    func tapCharacter() {
        card.nextPose()
        hops += 1
        changed()
    }

    func pick(_ backdrop: ScoreCard.Backdrop) {
        guard backdrop != card.backdrop else { return }
        card.pick(backdrop)
        changed()
    }

    func showSquad(_ shows: Bool) {
        card.showsSquad = shows
        changed()
    }

    private func changed() {
        changes += 1
        guard showsHint else { return }
        showsHint = false
        defaults.set(true, forKey: Self.hintSeenKey)
    }

    // MARK: Loading

    /// Reads the photos, draws the route and counts the week, side by side.
    func load(from store: FeedStore) async {
        async let count = store.weekCount(of: checkIn)
        async let route = drawRoute()
        for case .photo(let ref) in card.backdrops where photos[ref] == nil {
            guard let jpeg = await store.photo(ref), let image = await Self.decode(jpeg) else { continue }
            photos[ref] = image
        }
        map = await route
        weekCount = await count
    }

    private func drawRoute() async -> UIImage? {
        guard card.backdrops.contains(.map), let route = training.workout?.route else { return nil }
        return await RouteSnapshot.picture(of: route, activity: training.activity, size: Self.pictureSize)
    }

    private nonisolated static func decode(_ jpeg: Data) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }

    // MARK: Character

    /// The character in the card's pose: a still from a move it already has, at its signature
    /// moment. The sport's move and the cheer and flex wear the sport's kit; the prop pose wears
    /// the member's own look with what it holds.
    var still: Still? { still(card.pose) }

    private func still(_ pose: ScoreCard.Pose) -> Still? {
        if let kept = stills[pose] { return kept }
        let kit = Self.kits?.kit(for: training.activity, in: SportList.shared.catalog)
        let dressed = kit?.dress(look) ?? look
        let (outfit, clip): (Outfit, Clip?) =
            switch pose {
            case .sport: (dressed, kit.flatMap { try? PlaceholderCharacter.move(for: $0, persona: persona) })
            case .cheer: (dressed, try? PlaceholderCharacter.clip("cheer", persona: persona, species: species))
            case .flex: (dressed, try? PlaceholderCharacter.clip(for: .pump, persona: persona))
            case .prop: (look, (try? PlaceholderCharacter.propMove(for: look)) ?? nil)
            }
        let move = clip ?? .still
        let start = Date(timeIntervalSinceReferenceDate: 0)
        guard let figure = try? PlaceholderCharacter.figure(wearing: outfit),
            let player = try? CharacterPlayer(figure: figure, idle: move, now: start)
        else { return nil }
        let frame = player.frame(at: start.addingTimeInterval(PlaceholderCharacter.keyPose(of: move) * move.duration))
        stills[pose] = frame
        return frame
    }

    private static let kits = try? PlaceholderCharacter.sportKits()
}

// The 成绩卡 from 动态.
extension FeedModel {
    /// Whether `post` offers 存成绩卡: one of the member's own 训练.
    func canSaveScoreCard(_ post: FeedPost) -> Bool {
        guard post.author == viewer, case .trained = post.checkIn.entry else { return false }
        return true
    }

    /// Opens the 成绩卡's sheet over one of the member's 训练.
    func openScoreCard(_ post: FeedPost) {
        guard canSaveScoreCard(post) else { return }
        closeBar()
        scoreCard = ScoreCardModel(
            post.checkIn, character: store.characters[post.author], squadName: squadName(), defaults: defaults)
    }
}
#endif
