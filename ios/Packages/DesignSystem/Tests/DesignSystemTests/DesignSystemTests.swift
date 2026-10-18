import Testing

@testable import DesignSystem

struct SRGBColorTests {
    @Test func hexIsUppercaseWithLeadingZeros() {
        #expect(SRGBColor(red: 0x0E, green: 0x1B, blue: 0x3D).hex == "#0E1B3D")
        #expect(SRGBColor(red: 0, green: 0, blue: 0).hex == "#000000")
    }

    @Test func contrastRatioMatchesWCAGEndpoints() {
        #expect(Palette.black.contrastRatio(with: Palette.white) == 21)
        #expect(Palette.white.contrastRatio(with: Palette.white) == 1)
    }

    @Test func contrastRatioIsSymmetric() {
        #expect(Palette.ink.contrastRatio(with: Palette.honey) == Palette.honey.contrastRatio(with: Palette.ink))
    }
}

struct NeutralTests {
    @Test func neutralsMatchTheApprovedSpec() {
        let neutrals: [ColorRole] = [.canvas, .surface, .divider, .textPrimary, .textSecondary, .textTertiary]
        #expect(
            neutrals.map { $0.color(in: .pool).hex } == [
                "#FFFFFF", "#F3F5F8", "#E8EBF0", "#22252E", "#6B7080", "#AEB2BC",
            ])
    }

    /// A theme swaps only the signature group; neutrals and the meaning accents never change.
    @Test func onlyTheSignatureGroupFollowsTheScene() {
        let themed = ColorRole.allCases.filter { role in
            Set(SceneTheme.allCases.map { role.color(in: $0) }).count > 1
        }
        #expect(
            themed.map(\.rawValue) == [
                "signature", "signatureShade", "signatureWash", "onSignature", "signatureText", "progressFill",
            ])
    }

    @Test func noNeutralIsAWarmOffWhite() {
        // Cream backgrounds are off-brand, so every neutral background leans cool (blue >= red)
        // in every scene. The warm washes are deliberate and pinned here: the track, tennis and climbing
        // scenes' own washes (scene colors, never neutrals) and the 坦白放纵餐 tag's honey wash.
        func isWarm(_ color: SRGBColor) -> Bool { color.blue < color.red }
        for theme in SceneTheme.allCases {
            for role in [ColorRole.canvas, .surface, .divider] {
                #expect(!isWarm(role.color(in: theme)), "\(role) leans warm in \(theme)")
            }
        }
        #expect(SceneTheme.allCases.filter { isWarm($0.colors.wash) } == [.track, .tennis, .climbing])
        #expect(Meaning.allCases.filter { isWarm($0.accent(in: .pool).wash) } == [.indulgence])
    }

    /// Body-size text needs 4.5:1 (WCAG 2.2, 1.4.3).
    @Test(arguments: [
        (ColorRole.textPrimary, ColorRole.canvas),
        (.textPrimary, .surface),
        (.textSecondary, .canvas),
        (.textSecondary, .surface),
    ])
    func neutralTextIsReadable(text: ColorRole, background: ColorRole) {
        #expect(text.color(in: .pool).contrastRatio(with: background.color(in: .pool)) >= 4.5)
    }

    /// Tertiary ink is for denominators and decoration only; this pins that it is too faint for text.
    @Test func tertiaryIsDecorationOnly() {
        #expect(ColorRole.textTertiary.color(in: .pool).contrastRatio(with: Palette.white) < 3)
    }
}

struct CharacterToneTests {
    /// The avatar's skin, fur and hair swatches, as Tracy approved them (2026-10-18).
    @Test func tonesMatchTheApprovedSpec() {
        #expect(
            Palette.skinTones.map(\.hex) == [
                "#F9DCC4", "#F5CDAE", "#E8B48F", "#D9A27A", "#B97F57", "#8D5A3B", "#5E3B27",
            ])
        #expect(Palette.catFur.map(\.hex) == ["#F2A65A", "#F6E6CC", "#A3A7B0", "#4A4650", "#FBFAF6", "#C9874F"])
        #expect(Palette.bearFur.map(\.hex) == ["#B98563", "#7E5236", "#D9B07E", "#F2EFE8", "#3F393B", "#A8927E"])
        #expect(
            Palette.hairColors.map(\.hex) == [
                "#2A2333", "#4A2F25", "#6B4330", "#B07B4A", "#E2BF74", "#A2452F", "#C4C2CA",
            ])
    }
}

struct SceneThemeTests {
    @Test func poolColors() {
        let pool = SceneTheme.pool.colors
        #expect(
            [pool.signature, pool.shade, pool.wash, pool.onSignature, pool.signatureText, pool.progressFill].map(\.hex)
                == ["#079BB8", "#067C93", "#E2F5F9", "#FFFFFF", "#066E83", "#079BB8"])
    }

    @Test func trackColors() {
        let track = SceneTheme.track.colors
        #expect(
            [track.signature, track.shade, track.wash, track.onSignature, track.signatureText, track.progressFill]
                .map(\.hex) == ["#E65345", "#C23B2E", "#FCEDEB", "#FFFFFF", "#B83325", "#E65345"])
    }

    @Test func gymIsGraphiteWithVoltOnIt() {
        let gym = SceneTheme.gym.colors
        #expect(
            [gym.signature, gym.shade, gym.wash, gym.onSignature, gym.signatureText, gym.progressFill].map(\.hex)
                == ["#1F2128", "#000000", "#EEF0F2", "#C6F432", "#1F2128", "#C6F432"])
    }

    /// Small signature-colored text (第 42 周, selected tabs, the score) sits on white or the wash.
    @Test(arguments: SceneTheme.allCases)
    func signatureTextIsReadable(theme: SceneTheme) {
        let text = ColorRole.signatureText.color(in: theme)
        #expect(text.contrastRatio(with: ColorRole.canvas.color(in: theme)) >= 4.5)
        #expect(text.contrastRatio(with: ColorRole.signatureWash.color(in: theme)) >= 4.5)
        #expect(
            ColorRole.textPrimary.color(in: theme).contrastRatio(with: ColorRole.signatureWash.color(in: theme)) >= 4.5)
    }

    /// The 打卡 label is `TypeRamp.action` (19 pt Semibold, large text under WCAG 1.4.3). Large text
    /// and icons need 3:1; white on the pool signature is 3.3:1 and on the track signature 3.7:1.
    @Test(arguments: SceneTheme.allCases)
    func labelsOnTheSignatureMeetBoldTextContrast(theme: SceneTheme) {
        let ratio = ColorRole.onSignature.color(in: theme).contrastRatio(with: ColorRole.signature.color(in: theme))
        #expect(ratio >= 3)
    }

    @Test func tennisAndClimbingColors() {
        #expect(
            [SceneTheme.tennis, .climbing].map { theme in
                let colors = theme.colors
                return [colors.signature, colors.shade, colors.wash, colors.onSignature, colors.signatureText]
                    .map(\.hex)
            } == [
                ["#4F6B22", "#3B5119", "#EEF2E4", "#FFFFFF", "#41591B"],
                ["#8E4A2C", "#6F3820", "#F6EDE8", "#FFFFFF", "#7A3E24"],
            ])
    }

    @Test func dimSignaturesAreBoldOnly() {
        // Pins the limit above: these pairs must never carry regular-weight small text.
        let pool = SceneTheme.pool.colors
        let track = SceneTheme.track.colors
        #expect(pool.onSignature.contrastRatio(with: pool.signature) < 4.5)
        #expect(track.onSignature.contrastRatio(with: track.signature) < 4.5)
    }
}

struct MeaningTests {
    @Test func accentsMatchTheApprovedSpec() {
        #expect(
            Meaning.allCases.map { [$0.accent.ink.hex, $0.accent.wash.hex, $0.accent.text.hex] } == [
                ["#2D5BA0", "#EAF0F8", "#224780"],
                ["#278C5E", "#E5F3EB", "#1B6545"],
                ["#A0760E", "#FBF1DC", "#6E4F07"],
                ["#9062DE", "#F3EEFC", "#5B3AA6"],
            ])
    }

    @Test(arguments: SceneTheme.allCases)
    func accentsAreTheSameInEveryScene(theme: SceneTheme) {
        #expect(Meaning.allCases.map { $0.accent(in: theme) } == Meaning.allCases.map(\.accent))
    }

    /// A tag is dark text on the accent's wash: 4.5:1.
    @Test(arguments: Meaning.allCases, SceneTheme.allCases)
    func tagTextIsReadable(meaning: Meaning, theme: SceneTheme) {
        let accent = meaning.accent(in: theme)
        #expect(accent.text.contrastRatio(with: accent.wash) >= 4.5)
    }

    /// Icons need 3:1 (WCAG 2.2, 1.4.11) on every light surface they sit on, glass included.
    @Test(arguments: Meaning.allCases, SceneTheme.allCases)
    func iconInkIsVisible(meaning: Meaning, theme: SceneTheme) {
        let ink = meaning.accent(in: theme).ink
        for background in [ColorRole.canvas, .surface, .signatureWash] {
            #expect(ink.contrastRatio(with: background.color(in: theme)) >= 3, "\(meaning) on \(background)")
        }
    }
}

struct LayoutTests {
    @Test func spacingAndRadiiMatchTheSpec() {
        #expect([Space.xxs, Space.xs, Space.s, Space.m, Space.l, Space.xl, Space.xxl] == [4, 8, 12, 16, 24, 32, 48])
        #expect(Space.gutter == 16)
        #expect([Radius.s, Radius.m, Radius.button, Radius.l, Radius.xl] == [14, 16, 18, 24, 26])
        #expect(Radius.capsule(height: Sizing.capsuleHeight) == 22)
    }

    @Test func tapTargetsAreAtLeast44Points() {
        #expect(Sizing.capsuleHeight >= Sizing.minimumTapTarget)
        #expect(Sizing.checkInHeight >= Sizing.minimumTapTarget)
        #expect(Sizing.capsuleGlyph < Sizing.capsuleIcon)
    }

    @Test func pickerControlsMatchTheSpec() {
        #expect(Radius.tile == 13)
        #expect([Sizing.searchFieldHeight, Sizing.pillHeight, Sizing.tileHeight] == [44, 36, 86])
        #expect([Sizing.pillGlyph, Sizing.tileGlyph, Sizing.checkBadge] == [15, 28, 18])
        #expect([Sizing.categoryPillHeight, Sizing.categoryItemInset] == [34, 14])
        #expect(Sizing.selectionStroke == 1.75)
        #expect([Lift.opacity, Lift.radius, Lift.y] == [0.12, 1, 1])
    }

    /// Pills and category pills draw smaller than a finger, so they pad out to the tap target;
    /// the search field and tiles are already big enough.
    /// The pill and the category pill draw smaller than a tap target; their views pad out to it.
    @Test func pickerTokenSizesRelateAsDrawn() {
        #expect(Sizing.pillHeight < Sizing.minimumTapTarget)
        #expect(Sizing.categoryPillHeight < Sizing.minimumTapTarget)
        #expect(Sizing.searchFieldHeight >= Sizing.minimumTapTarget)
        #expect(Sizing.tileHeight >= Sizing.minimumTapTarget)
        #expect([Sizing.pillGap, Sizing.pillInset, Sizing.fieldInset] == [6, 10, 14])
    }

    @Test func frostGetsWhiterFromNavigationToCards() {
        #expect([Frost.capsuleFill, Frost.bannerFill, Frost.cardFill] == [0.5, 0.62, 0.76])
        #expect(Tint.selected == 0.14)
    }

    @Test func scrimIsALightBlurNotADim() {
        #expect(Scrim.blurRadius == 3)
        #expect(Scrim.tint.hex == "#E8F6FA")
        #expect(Scrim.tintOpacity == 0.1)
    }
}

struct TypographyTests {
    @Test func facesMapToShippedPostScriptNames() {
        #expect(Face.text(.semibold).postScriptName == "PingFangSC-Semibold")
        #expect(Face.text(.regular).postScriptName == "PingFangSC-Regular")
        #expect(Face.scoreboard(.extraBold).postScriptName == "BarlowCondensed-ExtraBold")
        #expect(Face.scoreboard(.semibold).postScriptName == "BarlowCondensed-SemiBold")
    }

    @Test func textRampGetsSmallerFromHeroToFootnote() {
        let sizes = [
            TypeRamp.hero, TypeRamp.title, TypeRamp.headline, TypeRamp.body, TypeRamp.callout, TypeRamp.caption,
            TypeRamp.footnote,
        ].map(\.size)
        #expect(sizes == [30, 24, 17, 16, 15, 13, 12])
        #expect(TypeRamp.action.size == 19)
    }

    @Test func pickerRungsMatchTheSpec() {
        let rungs = [TypeRamp.calloutEmphasis, TypeRamp.tileLabel, TypeRamp.field, TypeRamp.sectionLabel]
        #expect(rungs.map(\.size) == [15, 14, 17, 13])
        #expect(rungs.map(\.face) == [.text(.semibold), .text(.medium), .text(.medium), .text(.semibold)])
        #expect(TypeRamp.sectionLabel.tracking == 0.26)
        #expect(TypeRamp.calloutEmphasis.anchor == TypeRamp.callout.anchor)
    }

    @Test func scoreboardRampMatchesTheSpec() {
        let sizes = [
            TypeRamp.scoreHero, TypeRamp.scoreLarge, TypeRamp.scoreLargeDenominator, TypeRamp.scoreMedium,
            TypeRamp.scoreSmall, TypeRamp.scoreSmallDenominator, TypeRamp.scoreLabel,
        ].map(\.size)
        #expect(sizes == [92, 52, 28, 30, 20, 14, 14])
        #expect(TypeRamp.scoreHero.tracking == -1.84)
        #expect(TypeRamp.scoreMedium.face == .scoreboard(.extraBold))
    }

    @Test func everyRungUsesTheRightFamily() {
        let scoreboard = TypeRamp.all.filter {
            if case .scoreboard = $0.style.face { return true }
            return false
        }
        #expect(
            scoreboard.map(\.name) == [
                "scoreHero", "scoreLarge", "scoreLargeDenominator", "scoreMedium", "scoreSmall",
                "scoreSmallDenominator", "scoreLabel",
            ])
    }
}

struct MotionTests {
    @Test func springsMatchTheSpec() {
        #expect(Motion.all.map(\.name) == ["snappy", "burst", "panel", "bouncy", "smooth"])
        #expect(Motion.all.map(\.spring.response) == [0.3, 0.24, 0.37, 0.5, 0.45])
        #expect(Motion.all.map(\.spring.dampingFraction) == [0.86, 0.6, 0.52, 0.6, 1])
        #expect(Motion.burstStagger == 0.028)
        #expect([Motion.collapseDuration, Motion.collapseStagger] == [0.19, 0.016])
    }

    /// Bounce is reserved for the expressive moments (the check-in burst, glass panels springing
    /// in, celebrations). Taps and ordinary transitions never overshoot visibly.
    @Test func onlyExpressiveSpringsBounce() {
        let bouncing = Motion.all.filter { $0.spring.dampingFraction < 0.8 }.map(\.name)
        #expect(bouncing == ["burst", "panel", "bouncy"])
        #expect(Motion.snappy.dampingFraction >= 0.8)
        #expect(Motion.smooth.dampingFraction == 1)
    }

    @Test func capsulesLandOnTheArcAboveTheButton() {
        let rounded = Meaning.allCases.map { meaning in
            let offset = BurstLayout.offset(for: meaning)
            return [(offset.x * 10).rounded() / 10, (offset.y * 10).rounded() / 10]
        }
        #expect(rounded == [[-121.7, -39.6], [-60.1, -113.0], [60.1, -113.0], [121.7, -39.6]])
    }
}
