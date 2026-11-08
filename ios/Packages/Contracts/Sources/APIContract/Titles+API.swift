import Contracts

// 头衔徽章 as the API sends them: the badge's shape, colour, tone and glyph pass through as text, a
// shape this build doesn't draw becoming a circle.

extension TitleBadge {
    public init(_ wire: Components.Schemas.TitleBadge) {
        self.init(shape: wire.shape, colour: wire.colour, tone: wire.tone, glyph: wire.glyph)
    }
}

extension WornTitle {
    public init(_ wire: Components.Schemas.WornTitle) {
        self.init(title: wire.title, badge: TitleBadge(wire.badge))
    }
}

extension BoardTitle {
    public init(_ wire: Components.Schemas.BoardTitle) throws(ContractsError) {
        self.init(
            title: wire.title, badge: TitleBadge(wire.badge),
            weeks: try wire.weeks.map { week throws(ContractsError) in
                Week(weekStart: try LocalDay(week.weekStart), speech: week.speech, squadName: week.squadName)
            })
    }
}

extension TitleBoard {
    public init(_ wire: Components.Schemas.TitleBoard) throws(ContractsError) {
        self.init(
            titles: try wire.titles.map { title throws(ContractsError) in try BoardTitle(title) }, worn: wire.worn)
    }

    /// A squadmate's board, from their card.
    public init(_ wire: Components.Schemas.PlayerCard) throws(ContractsError) {
        self.init(
            titles: try wire.titles.map { title throws(ContractsError) in try BoardTitle(title) }, worn: wire.worn)
    }
}
