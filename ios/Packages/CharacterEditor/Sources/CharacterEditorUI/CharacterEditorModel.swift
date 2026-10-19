#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import AvatarUI
import CharacterEditorDomain
import Foundation
import Observation

/// The editor's tabs, in order. 发型 shows only while the character is a person.
public enum EditorTab: String, CaseIterable, Hashable, Sendable {
    case look, hair, outfit, prop, persona
}

/// Where the editor is open: as a step of sign-up, or from 我 to change the character.
public enum EditorContext: Hashable, Sendable {
    case signUp(step: Int, total: Int)
    case profile
}

/// What the editor hands back when the person is done.
public struct EditedCharacter: Hashable, Sendable {
    public let outfit: Outfit
    public let persona: Persona
    public let nickname: String
}

/// The editor's state on screen: the draft, the open tab and the character playing on the
/// stage. While the person dresses the character it stands still, and every change plays one
/// move; on the 性格 tab it plays the persona's idle, so the persona shows.
@MainActor @Observable
public final class CharacterEditorModel {
    public private(set) var draft: CharacterDraft
    public var tab: EditorTab {
        didSet { if tab != oldValue { restyle(move: false) } }
    }
    /// Nil until the first figure is built.
    public private(set) var player: CharacterPlayer?
    /// Thumbnails of the tiles, kept while the editor is open.
    let thumbnails = ThumbnailCache()
    /// Bumped by every change, so a slower figure build never replaces a newer look.
    @ObservationIgnored private var request = 0
    @ObservationIgnored private var clips: [String: Clip] = [:]
    @ObservationIgnored private var outfitOnStage: Outfit?

    public init(draft: CharacterDraft, tab: EditorTab = .look) {
        self.draft = draft
        self.tab = tab
    }

    /// The placeholder character's catalog and a look to start from: the one given, or a random
    /// one until sign-up hands over the last look its first screen showed.
    public static func placeholder(
        look: Outfit? = nil, persona: Persona = .energetic, nickname: String, tab: EditorTab = .look
    ) throws(AvatarError) -> CharacterEditorModel {
        let catalog = try Catalog.placeholder()
        var generator = SystemRandomNumberGenerator()
        let start = look ?? CharacterDraft.randomLook(from: catalog, using: &generator)
        return CharacterEditorModel(
            draft: CharacterDraft(catalog: catalog, look: start, persona: persona, nickname: nickname), tab: tab)
    }

    /// A fixed look for screenshots and UI tests: a person with a bob, a tee, shorts and a
    /// dumbbell.
    public static let sampleLook = PlaceholderCharacter.lifter

    public var tabs: [EditorTab] {
        EditorTab.allCases.filter { $0 != .hair || draft.wearsHair }
    }

    /// The field keeps what is typed, so pinyin still being composed is never cut; a name
    /// longer than the limit just can't be saved.
    public var nickname: String {
        get { draft.nickname }
        set { draft.nickname = newValue }
    }

    /// What to save, once the nickname is a valid one.
    public var result: EditedCharacter? {
        draft.name.map { EditedCharacter(outfit: draft.outfit, persona: draft.persona, nickname: $0) }
    }

    /// Builds the first figure. The stage stays empty for the moment this takes.
    func start() {
        guard player == nil else { return }
        restyle(move: false)
    }

    func pick(_ variant: String?, for slot: Slot) {
        guard draft.pick(variant, for: slot) else { return }
        if tab == .hair && !draft.wearsHair { tab = .look }
        restyle(move: true)
    }

    func pickColor(_ color: RGBAColor?, for slot: Slot) {
        guard draft.pickColor(color, for: slot) else { return }
        restyle(move: true)
    }

    func choose(_ persona: Persona) {
        guard draft.choose(persona) else { return }
        restyle(move: true)
    }

    func undo() {
        guard draft.undo() else { return }
        if tab == .hair && !draft.wearsHair { tab = .look }
        restyle(move: true)
    }

    func shuffle() {
        var generator = SystemRandomNumberGenerator()
        draft.shuffle(using: &generator)
        if tab == .hair && !draft.wearsHair { tab = .look }
        restyle(move: true)
    }

    /// The persona's cheer, for a tap on the character.
    func cheer() {
        guard let player, let cheer = clip("cheer") else { return }
        try? player.play(cheer)
    }

    /// The persona one step along, for a swipe across the stage on the 性格 tab.
    func choosePersona(after step: Int) {
        let all = Persona.allCases
        guard let index = all.firstIndex(of: draft.persona) else { return }
        let next = index + step
        guard all.indices.contains(next) else { return }
        choose(all[next])
    }

    /// Dresses the stage in the draft's outfit and idle, then plays one move if asked: the
    /// persona's cheer. The figure is built off the main actor, since it reads and parses art.
    private func restyle(move: Bool) {
        request += 1
        let ticket = request
        let outfit = draft.outfit
        // A new persona or tab keeps the figure on stage; only new clothes need a new one.
        if let player, outfitOnStage == outfit {
            show(player.figure, wearing: outfit, ticket: ticket, move: move)
            return
        }
        Task {
            guard let figure = try? await Self.figure(wearing: outfit) else { return }
            self.show(figure, wearing: outfit, ticket: ticket, move: move)
        }
    }

    private func show(_ figure: Figure, wearing outfit: Outfit, ticket: Int, move: Bool) {
        guard ticket == request else { return }
        outfitOnStage = outfit
        let idle = (tab == .persona ? clip("idle") : nil) ?? .still
        if let player {
            try? player.wear(figure, idle: idle)
        } else {
            player = try? CharacterPlayer(figure: figure, idle: idle)
        }
        if move, let cheer = clip("cheer") {
            try? player?.play(cheer)
        }
    }

    private func clip(_ name: String) -> Clip? {
        let key = "\(draft.persona.rawValue)/\(name)"
        if let clip = clips[key] { return clip }
        let clip = try? PlaceholderCharacter.clip(name, persona: draft.persona)
        clips[key] = clip
        return clip
    }

    /// Reads and parses the art for an outfit away from the main actor.
    nonisolated static func figure(wearing outfit: Outfit) async throws -> Figure {
        try await Task.detached(priority: .userInitiated) {
            try PlaceholderCharacter.figure(wearing: outfit)
        }.value
    }
}
#endif
