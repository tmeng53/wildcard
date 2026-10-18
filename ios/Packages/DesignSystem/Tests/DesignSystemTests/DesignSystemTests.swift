import Testing

@testable import DesignSystem

struct RGBColorTests {
    @Test func hexIsUppercaseWithLeadingZeros() {
        #expect(SRGBColor(red: 0x0E, green: 0x1B, blue: 0x3D).hex == "#0E1B3D")
        #expect(SRGBColor(red: 0, green: 0, blue: 0).hex == "#000000")
    }

    @Test func contrastRatioMatchesWCAGEndpoints() {
        let black = SRGBColor(red: 0, green: 0, blue: 0)
        #expect(black.contrastRatio(with: Palette.white) == 21)
        #expect(Palette.white.contrastRatio(with: Palette.white) == 1)
    }

    @Test func contrastRatioIsSymmetric() {
        #expect(Palette.ink.contrastRatio(with: Palette.medal) == Palette.medal.contrastRatio(with: Palette.ink))
    }
}

struct PaletteTests {
    @Test func tokensKeepTheTrackMeetPalette() {
        #expect(Palette.ink.hex == "#0E1B3D")
        #expect(Palette.track.hex == "#EE5A36")
        #expect(Palette.medal.hex == "#F6B92B")
        #expect(Palette.sky.hex == "#1F6BFF")
    }

    /// Body-size text needs 4.5:1 (WCAG 2.2, 1.4.3).
    @Test(arguments: [
        (ColorRole.textPrimary, ColorRole.canvas),
        (.textPrimary, .surface),
        (.textPrimary, .skyWash),
        (.textSecondary, .canvas),
        (.textSecondary, .surface),
        (.textOnFill, .sky),
        (.textOnFill, .textPrimary),
        (.textPrimary, .achievement),
        (.textPrimary, .fresh),
        (.textPrimary, .brand),
    ])
    func smallTextIsReadable(text: ColorRole, background: ColorRole) {
        #expect(text.color.contrastRatio(with: background.color) >= 4.5)
    }

    /// White on track red is 3.4:1, enough only for large or bold text (WCAG 3:1), so the
    /// main action's label is 17 pt semibold or bigger.
    @Test func whiteOnBrandIsLargeTextOnly() {
        let ratio = ColorRole.textOnFill.color.contrastRatio(with: ColorRole.brand.color)
        #expect(ratio >= 3)
        #expect(ratio < 4.5)
    }

    @Test func noRoleUsesAWarmOffWhite() {
        // Cream backgrounds are off-brand: every light surface leans cool (blue >= red).
        for role in [ColorRole.canvas, .surface, .skyWash, .divider] {
            #expect(role.color.blue >= role.color.red, "\(role) leans warm")
        }
    }
}

struct TypographyTests {
    @Test func facesMapToShippedPostScriptNames() {
        #expect(Face.text(.semibold).postScriptName == "PingFangSC-Semibold")
        #expect(Face.text(.regular).postScriptName == "PingFangSC-Regular")
        #expect(Face.scoreboard(.extraBold).postScriptName == "BarlowCondensed-ExtraBold")
        #expect(Face.scoreboard(.semibold).postScriptName == "BarlowCondensed-SemiBold")
    }

    @Test func rampGetsSmallerFromHeroToCaption() {
        let sizes = [
            TypeRamp.hero, TypeRamp.title, TypeRamp.headline, TypeRamp.body, TypeRamp.callout, TypeRamp.caption,
        ].map(\.size)
        #expect(sizes == [34, 24, 17, 16, 15, 13])
    }

    @Test func scoreboardStylesUseTheScoreboardFace() {
        for style in [TypeRamp.scoreHero, TypeRamp.scoreLarge, TypeRamp.scoreMedium, TypeRamp.scoreLabel] {
            guard case .scoreboard = style.face else {
                Issue.record("\(style) is not a scoreboard face")
                continue
            }
        }
    }
}

struct MotionTests {
    @Test func springsSettleQuicklyEnoughForTaps() {
        #expect(Motion.snappy.response == 0.3)
        #expect(Motion.snappy.dampingFraction == 0.86)
    }

    @Test func onlyCelebrationsBounce() {
        let bouncing = Motion.all.filter { $0.spring.dampingFraction < 0.8 }.map(\.name)
        #expect(bouncing == ["bouncy"])
    }
}
