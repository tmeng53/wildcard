import Testing

@testable import DesignSystem

struct SRGBColorTests {
    @Test func hexIsUppercaseWithLeadingZeros() {
        #expect(SRGBColor(red: 0x0E, green: 0x1B, blue: 0x3D).hex == "#0E1B3D")
        #expect(SRGBColor(red: 0, green: 0, blue: 0).hex == "#000000")
    }

    @Test func contrastRatioMatchesWCAGEndpoints() {
        #expect(SRGBColor(red: 0, green: 0, blue: 0).contrastRatio(with: Palette.white) == 21)
        #expect(Palette.white.contrastRatio(with: Palette.white) == 1)
    }

    @Test func contrastRatioIsSymmetric() {
        #expect(Palette.ink.contrastRatio(with: Palette.poolWash) == Palette.poolWash.contrastRatio(with: Palette.ink))
    }
}

struct NeutralTests {
    @Test func neutralsMatchTheApprovedSpec() {
        let neutrals: [ColorRole] = [.bgCanvas, .bgSubtle, .borderDefault, .fgDefault, .fgMuted, .fgSubtle]
        #expect(
            neutrals.map { $0.color(in: .pool).hex } == [
                "#FFFFFF", "#F3F5F8", "#E8EBF0", "#22252E", "#6B7080", "#AEB2BC",
            ])
    }

    /// A theme swaps only the accent group; neutrals never change.
    @Test func onlyTheAccentGroupFollowsTheScene() {
        let themed = ColorRole.allCases.filter { role in
            Set(SceneTheme.allCases.map { role.color(in: $0) }).count > 1
        }
        #expect(
            themed.map(\.rawValue) == [
                "bgAccent", "bgAccentSubtle", "fgAccent", "bgScene", "ring", "bgKind", "fgKind",
            ])
    }

    @Test func noNeutralIsAWarmOffWhite() {
        // Cream backgrounds are off-brand, so every neutral background leans cool (blue >= red).
        // The warm washes and floors are the track, tennis and climbing scenes' own colors.
        func isWarm(_ color: SRGBColor) -> Bool { color.blue < color.red }
        for theme in SceneTheme.allCases {
            for role in [ColorRole.bgCanvas, .bgSubtle, .borderDefault] {
                #expect(!isWarm(role.color(in: theme)), "\(role) leans warm in \(theme)")
            }
        }
        #expect(SceneTheme.allCases.filter { isWarm($0.colors.accentSubtle) } == [.track, .tennis, .climbing])
        #expect(SceneTheme.allCases.filter { isWarm($0.colors.floor) } == [.track, .tennis, .climbing])
    }

    /// Body-size text needs 4.5:1 (WCAG 2.2, 1.4.3).
    @Test(arguments: [
        (ColorRole.fgDefault, ColorRole.bgCanvas),
        (.fgDefault, .bgSubtle),
        (.fgMuted, .bgCanvas),
        (.fgMuted, .bgSubtle),
    ])
    func neutralTextIsReadable(text: ColorRole, background: ColorRole) {
        #expect(text.color(in: .pool).contrastRatio(with: background.color(in: .pool)) >= 4.5)
    }

    /// Subtle ink is for denominators, placeholders and decoration; this pins that it is too faint
    /// for text.
    @Test func subtleIsDecorationOnly() {
        #expect(ColorRole.fgSubtle.color(in: .pool).contrastRatio(with: Palette.white) < 3)
    }
}

struct CharacterToneTests {
    /// The avatar's skin, fur and hair swatches, as Tracy approved them (2026-10-18), and its eye colors
    /// (2026-10-19).
    @Test func tonesMatchTheApprovedSpec() {
        #expect(
            Palette.skinTones.map(\.hex) == [
                "#F9DCC4", "#F5CDAE", "#E8B48F", "#D9A27A", "#B97F57", "#8D5A3B", "#5E3B27",
            ])
        #expect(Palette.catFur.map(\.hex) == ["#F2A65A", "#F6E6CC", "#A3A7B0", "#4A4650", "#FBFAF6", "#C9874F"])
        #expect(Palette.bearFur.map(\.hex) == ["#B98563", "#7E5236", "#D9B07E", "#F2EFE8", "#3F393B", "#A8927E"])
        #expect(Palette.dogFur.map(\.hex) == ["#E2B26C", "#F1DDB8", "#D98B4A", "#7A4E36", "#2F2B34", "#FBFAF6"])
        #expect(Palette.rabbitFur.map(\.hex) == ["#FBFAF6", "#E9D2B4", "#B98A64", "#9C9AA3", "#5C5862", "#3D3842"])
        #expect(
            Palette.hairColors.map(\.hex) == [
                "#2A2333", "#4A2F25", "#6B4330", "#B07B4A", "#E2BF74", "#A2452F", "#C4C2CA",
            ])
        #expect(
            Palette.eyeColors.map(\.hex) == ["#22252E", "#4A3326", "#8A5A2B", "#4A6FA5", "#4F7A5E", "#6B6F80"])
    }
}

struct SceneThemeTests {
    private func roles(_ theme: SceneTheme) -> [String] {
        let colors = theme.colors
        return [
            colors.accent, colors.accentSubtle, colors.onAccent, colors.accentText, colors.floor, colors.onFloor,
            colors.ring, colors.kindFill, colors.kindFillOnFloor, colors.kindInk,
        ].map(\.hex)
    }

    @Test func poolColors() {
        #expect(
            roles(.pool) == [
                "#079BB8", "#E2F5F9", "#FFFFFF", "#066E83", "#CDEBF1", "#22252E", "#079BB8", "#E2F5F9", "#FFFFFF",
                "#066E83",
            ])
    }

    @Test func trackColors() {
        #expect(
            roles(.track) == [
                "#E65345", "#FCEDEB", "#FFFFFF", "#B83325", "#F8DDD9", "#22252E", "#E65345", "#FCEDEB", "#FFFFFF",
                "#B83325",
            ])
    }

    @Test func gymIsSteel() {
        #expect(
            roles(.gym) == [
                "#4A6C8C", "#EDF0F4", "#FFFFFF", "#3E5C78", "#DBE2E8", "#22252E", "#4A6C8C", "#EDF0F4", "#FFFFFF",
                "#3E5C78",
            ])
    }

    @Test func tennisAndClimbingColors() {
        #expect(
            roles(.tennis) == [
                "#4F6B22", "#EEF2E4", "#FFFFFF", "#41591B", "#DDE6CC", "#22252E", "#4F6B22", "#EEF2E4", "#FFFFFF",
                "#41591B",
            ])
        #expect(
            roles(.climbing) == [
                "#8E4A2C", "#F6EDE8", "#FFFFFF", "#7A3E24", "#EBDDD5", "#22252E", "#8E4A2C", "#F6EDE8", "#FFFFFF",
                "#7A3E24",
            ])
    }

    /// Small accent text (a tag, a selected word) sits on white or the wash.
    @Test(arguments: SceneTheme.allCases)
    func accentTextIsReadable(theme: SceneTheme) {
        let text = ColorRole.fgAccent.color(in: theme)
        #expect(text.contrastRatio(with: ColorRole.bgCanvas.color(in: theme)) >= 4.5)
        #expect(text.contrastRatio(with: ColorRole.bgAccentSubtle.color(in: theme)) >= 4.5)
        #expect(
            ColorRole.fgDefault.color(in: theme).contrastRatio(with: ColorRole.bgAccentSubtle.color(in: theme)) >= 4.5)
    }

    /// The primary button's label is `TypeRamp.action` (19 pt Semibold, large text under WCAG
    /// 1.4.3). Large text and icons need 3:1; white on the pool accent is 3.3:1.
    @Test(arguments: SceneTheme.allCases)
    func labelsOnTheAccentMeetBoldTextContrast(theme: SceneTheme) {
        let ratio = ColorRole.fgOnAccent.color(in: theme).contrastRatio(with: ColorRole.bgAccent.color(in: theme))
        #expect(ratio >= 3)
    }

    @Test func dimAccentsAreBoldOnly() {
        // Pins the limit above: these pairs must never carry regular-weight small text.
        let pool = SceneTheme.pool.colors
        let track = SceneTheme.track.colors
        #expect(pool.onAccent.contrastRatio(with: pool.accent) < 4.5)
        #expect(track.onAccent.contrastRatio(with: track.accent) < 4.5)
    }

    /// A kind's icon needs 3:1 (WCAG 2.2, 1.4.11) on its button, on white and on the floor.
    @Test(arguments: SceneTheme.allCases)
    func kindIconsAreVisible(theme: SceneTheme) {
        let ink = ColorRole.fgKind.color(in: theme)
        #expect(ink.contrastRatio(with: ColorRole.bgKind.color(in: theme)) >= 3)
        #expect(ink.contrastRatio(with: ColorRole.bgKindOnScene.color(in: theme)) >= 3)
    }

    /// Kind labels and anything else written straight on the floor are body text: 4.5:1.
    @Test(arguments: SceneTheme.allCases)
    func textOnTheFloorIsReadable(theme: SceneTheme) {
        let floor = ColorRole.bgScene.color(in: theme)
        #expect(ColorRole.fgOnScene.color(in: theme).contrastRatio(with: floor) >= 4.5)
    }

    /// Every scene is light: kind buttons step out of the floor, white on the floor, the wash on white.
    @Test(arguments: SceneTheme.allCases)
    func lightKindsUseTheWashOrWhite(theme: SceneTheme) {
        #expect(ColorRole.bgKind.color(in: theme) == ColorRole.bgAccentSubtle.color(in: theme))
        #expect(ColorRole.bgKindOnScene.color(in: theme) == Palette.white)
        #expect(ColorRole.ring.color(in: theme) == ColorRole.bgAccent.color(in: theme))
    }

    /// Every scene's closed ring stands out from a white card (WCAG 1.4.11).
    @Test(arguments: SceneTheme.allCases)
    func ringsStandOutOnWhite(theme: SceneTheme) {
        #expect(ColorRole.ring.color(in: theme).contrastRatio(with: ColorRole.bgCanvas.color(in: theme)) >= 3)
    }
}

struct ClothesTests {
    /// The old check-in colors live on only as outfit swatches.
    @Test func clothesKeepTheirColors() {
        #expect(
            [Palette.cobalt, Palette.mint, Palette.honey, Palette.lavender, Palette.graphite].map(\.hex) == [
                "#2D5BA0", "#278C5E", "#A0760E", "#9062DE", "#1F2128",
            ])
    }
}

struct LayoutTests {
    @Test func spacingIsSevenStepsOnAFourPointGrid() {
        let steps = [Space.xxs, Space.xs, Space.s, Space.m, Space.l, Space.xl, Space.xxl]
        #expect(steps == [4, 8, 12, 16, 24, 32, 48])
        #expect(steps.allSatisfy { $0.truncatingRemainder(dividingBy: 4) == 0 })
    }

    @Test func spacingAliasesMatchTheSpec() {
        #expect([Space.pageMargin, Space.cardPadding, Space.cardGap, Space.labelGap] == [16, 16, 12, 8])
        #expect([Space.sectionGap, Space.headerGap] == [32, 24])
    }

    @Test func radiiAreSixTenTwelveAndCapsules() {
        #expect([Radius.thumbnail, Radius.pick, Radius.card] == [6, 10, 12])
        #expect(Radius.capsule(height: Sizing.primaryControl) == 26)
        #expect(Radius.concentric(outer: Radius.card, inset: 6) == 6)
        #expect(Radius.concentric(outer: Radius.thumbnail, inset: 8) == 0)
    }

    @Test func controlsComeInThreeHeights() {
        #expect([Sizing.primaryControl, Sizing.control, Sizing.compactControl] == [52, 44, 36])
        #expect(Sizing.pickRow == 52)
        #expect([Sizing.checkBadge, Sizing.selectionStroke, Sizing.hairline, Sizing.swatch] == [20, 1.5, 1, 32])
        #expect([Sizing.switchWidth, Sizing.switchHeight, Sizing.switchKnobInset] == [51, 31, 2])
    }

    /// Compact controls draw smaller than a finger; their views pad out to the tap target.
    @Test func tapTargetsAreAtLeast44Points() {
        #expect(Sizing.minimumTapTarget == 44)
        #expect(Sizing.compactControl < Sizing.minimumTapTarget)
        #expect(Sizing.swatch < Sizing.minimumTapTarget)
        for size in [Sizing.primaryControl, Sizing.control, Sizing.pickRow, Sizing.kindButton] {
            #expect(size >= Sizing.minimumTapTarget)
        }
    }

    @Test func statusAndCharacterSizesMatchTheSpec() {
        #expect([Sizing.progress, Sizing.ringWidth, Sizing.ringGap] == [4, 3, 2])
        #expect([Sizing.characterHead, Sizing.characterBust, Sizing.characterFull] == [28, 84, 132])
        #expect([Sizing.kindButton, Sizing.kindIcon, Sizing.tag] == [52, 22, 28])
        #expect([Sizing.icon, Sizing.smallIcon] == [20, 15])
        #expect([Sizing.tabBar, Sizing.tabItemWidth, Sizing.tabItemHeight, Sizing.tabBarBottom] == [62, 76, 54, 26])
    }

    @Test func scrimIsALightBlurNotADim() {
        #expect(Scrim.blurRadius == 3)
        #expect(Scrim.tint.hex == "#E8F6FA")
        #expect(Scrim.tintOpacity == 0.1)
        #expect(abs(Scrim.fadeOut - Scrim.fadeIn * Motion.exitFactor) < 0.001)
    }
}

struct TypographyTests {
    @Test func facesMapToShippedPostScriptNames() {
        #expect(Face.text(.semibold).postScriptName == "PingFangSC-Semibold")
        #expect(Face.text(.regular).postScriptName == "PingFangSC-Regular")
        #expect(Face.scoreboard(.extraBold).postScriptName == "BarlowCondensed-ExtraBold")
        #expect(Face.scoreboard(.semibold).postScriptName == "BarlowCondensed-SemiBold")
    }

    /// Six text levels, as the design system v4 canvas sets them.
    @Test func sixTextLevels() {
        let levels = [
            TypeRamp.largeTitle, TypeRamp.title, TypeRamp.headline, TypeRamp.body, TypeRamp.footnote, TypeRamp.label,
        ]
        #expect(levels.map(\.size) == [32, 22, 17, 16, 13, 12])
        #expect(
            levels.map(\.face) == [
                .text(.semibold), .text(.semibold), .text(.semibold), .text(.regular), .text(.regular),
                .text(.semibold),
            ])
        #expect(TypeRamp.label.tracking == 0.48)
        #expect(TypeRamp.taskTitle.size == 26)
    }

    @Test func controlRungsMatchTheSpec() {
        let rungs = [TypeRamp.action, TypeRamp.callout, TypeRamp.calloutEmphasis, TypeRamp.pick, TypeRamp.field]
        #expect(rungs.map(\.size) == [19, 15, 15, 16, 16])
        #expect(
            rungs.map(\.face) == [.text(.semibold), .text(.medium), .text(.semibold), .text(.medium), .text(.regular)])
        #expect(TypeRamp.calloutEmphasis.anchor == TypeRamp.callout.anchor)
        #expect(TypeRamp.footnoteEmphasis.size == TypeRamp.footnote.size)
        #expect([TypeRamp.tab, TypeRamp.tabSelected].map(\.face) == [.text(.medium), .text(.semibold)])
        #expect([TypeRamp.tab, TypeRamp.tabSelected].map(\.size) == [12, 12])
    }

    @Test func numbersAreBarlowAtFourSizes() {
        #expect(
            [TypeRamp.scoreHero, TypeRamp.scoreCard, TypeRamp.scoreInline, TypeRamp.scoreSmall].map(\.size) == [
                60, 32, 22, 18,
            ])
        #expect(
            [TypeRamp.scoreHero, TypeRamp.scoreCard, TypeRamp.scoreInline].map {
                TypeRamp.denominator(of: $0).size
            } == [33, 18, 12])
        #expect(TypeRamp.denominator(of: TypeRamp.scoreHero).face == .scoreboard(.semibold))
        let scoreboard = TypeRamp.all.filter {
            if case .scoreboard = $0.style.face { return true }
            return false
        }
        #expect(scoreboard.map(\.name) == ["scoreHero", "scoreCard", "scoreInline", "scoreSmall"])
    }
}

struct SpeechTimingTests {
    @Test func bubblesHoldThenFade() {
        #expect([Motion.speechHold, Motion.speechFade, Motion.speechStagger] == [1.6, 0.2, 0.06])
    }
}

struct HapticTests {
    @Test func everyMomentHasOneName() {
        #expect(
            Haptic.allCases.map(\.rawValue) == [
                "pick", "appear", "refuse", "tick", "checkIn", "score", "land", "reaction",
            ])
        #expect(Haptic.ringTicks == 3)
    }
}

struct MotionTests {
    @Test func springsMatchTheSpec() {
        #expect(Motion.all.map(\.name) == ["press", "change", "sheet", "page", "celebrate"])
        #expect(Motion.all.map(\.spring.response) == [0.17, 0.10, 0.24, 0.36, 0.5])
        #expect(Motion.all.map(\.spring.dampingFraction) == [0.9, 1, 0.9, 0.9, 0.6])
        #expect([Motion.ringFill, Motion.ringPopScale] == [0.5, 1.08])
        #expect([Motion.collapseDuration, Motion.collapseStagger, Motion.burstStagger] == [0.19, 0.016, 0.028])
    }

    /// The open screen's reveal and fade, as the approved design times them.
    @Test func timedCurvesMatchTheSpec() {
        #expect(Motion.reveal == MotionCurve(duration: 0.3, 0.33, 1, 0.68, 1))
        #expect([Motion.revealRise, Motion.revealStagger] == [8, 0.08])
        #expect(Motion.fadeIn == MotionCurve(duration: 0.25, 0, 0, 1, 1))
    }

    /// Bounce is kept for the moment a check-in lands; everyday motion never overshoots visibly.
    @Test func onlyTheCelebrationBounces() {
        let bouncing = Motion.all.filter { $0.spring.dampingFraction < 0.8 }.map(\.name)
        #expect(bouncing == ["celebrate"])
    }

    @Test func exitsAreAFifthFaster() {
        #expect(abs(Motion.page.exit.response - 0.288) < 0.001)
        #expect(Motion.page.exit.dampingFraction == Motion.page.dampingFraction)
    }

    @Test func capsulesLandOnTheArcAboveTheButton() {
        let rounded = CheckInKind.allCases.map { kind in
            let offset = BurstLayout.offset(for: kind)
            return [(offset.x * 10).rounded() / 10, (offset.y * 10).rounded() / 10]
        }
        #expect(rounded == [[-121.7, -39.6], [-60.1, -113.0], [60.1, -113.0], [121.7, -39.6]])
    }
}

struct BrandTests {
    /// Graphite with white on it (Tracy, 2026-10-23).
    @Test func brandIsGraphiteWithWhiteOnIt() {
        #expect(ColorRole.bgBrand.color(in: .pool).hex == "#1F2128")
        #expect(ColorRole.fgOnBrand.color(in: .pool).hex == "#FFFFFF")
    }

    /// Brand screens look the same whatever scene the squad picked.
    @Test(arguments: [ColorRole.bgBrand, .fgOnBrand])
    func brandNeverFollowsTheScene(role: ColorRole) {
        #expect(Set(SceneTheme.allCases.map { role.color(in: $0) }).count == 1)
    }

    /// A brand button's label can be small regular text, not only the 19-point action.
    @Test func labelsOnTheBrandAreReadable() {
        #expect(ColorRole.fgOnBrand.color(in: .pool).contrastRatio(with: ColorRole.bgBrand.color(in: .pool)) >= 4.5)
    }

    @Test func eachToneUsesItsOwnPair() {
        #expect([AccentTone.scene.fill, AccentTone.scene.onFill] == [.bgAccent, .fgOnAccent])
        #expect([AccentTone.brand.fill, AccentTone.brand.onFill] == [.bgBrand, .fgOnBrand])
    }
}
