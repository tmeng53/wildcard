#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

// The squad's coach (approved canvas 雇教练页面, 2026-11-01): the 教练 card on 小队设置, 教练招聘会,
// a coach's 简历 and 解雇. Only the captain hires, changes and fires; every mate browses 教练招聘会
// and reads the 简历, with nothing to do there (Tracy, 2026-11-03).
// Coaches have no character of their own yet, so each stands as an ink silhouette.

/// A page the 教练 card pushes over 小队 (`CoachPage`).
public enum CoachRoute: Hashable {
    case market
    case resume(Coach)
    case fire(Coach)
    /// 换教练's confirmation: the squad's coach leaves and the other comes.
    case swap(leaving: Coach, coming: Coach)
}

/// 小队设置's 教练 card, on graphite: an empty spot and 招聘, or the coach standing whole (never
/// cropped), its name and how long it has coached; for a mate, 逛逛招聘会 too.
struct CoachCard: View {
    let hire: SquadCoach.Hire?
    let tenure: CoachTenure?
    let canHire: Bool
    let open: (CoachRoute) -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Group {
            if let hire {
                hired(hire.coach)
            } else {
                empty
            }
        }
        .inkCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("squad.coach")
    }

    private var empty: some View {
        HStack(spacing: Space.s) {
            UnevenRoundedRectangle(
                topLeadingRadius: CoachMetrics.thumbnailFigure / 2, topTrailingRadius: CoachMetrics.thumbnailFigure / 2,
                style: .continuous
            )
            .stroke(Color(role: .fgOnInkMuted, in: theme), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            .frame(width: CoachMetrics.thumbnailFigure, height: CoachMetrics.thumbnailFigure * 1.7)
            .frame(width: CoachMetrics.thumbnail, height: CoachMetrics.thumbnail)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(copy: "还没有教练", bundle: .module)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                if !canHire {
                    Text(copy: "只有队长能雇教练", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if canHire {
                Button {
                    open(.market)
                } label: {
                    Text(copy: "招聘", bundle: .module)
                }
                .buttonStyle(SecondaryButtonStyle(.onInk))
                .fixedSize()
                .accessibilityIdentifier("squad.coach.hire")
            } else {
                browse.fixedSize()
            }
        }
    }

    /// For a mate: 教练招聘会 to read, with nothing to do there; only the captain hires.
    private var browse: some View {
        Button {
            open(.market)
        } label: {
            Text(copy: "逛逛招聘会", bundle: .module).frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle(.onInk))
        .accessibilityIdentifier("squad.coach.browse")
    }

    private static func tenureText(_ tenure: CoachTenure) -> Text {
        switch tenure {
        case .days(let days): Text(copy: "执教 \(days) 天", bundle: .module)
        case .weeks(let weeks): Text(copy: "执教 \(weeks) 周", bundle: .module)
        }
    }

    private func hired(_ coach: Coach) -> some View {
        VStack(spacing: Space.s) {
            Button {
                open(.resume(coach))
            } label: {
                HStack(spacing: Space.m) {
                    // The whole coach, uncropped, its canvas's left edge on the card's padding.
                    CoachFigure(coach: coach.id.rawValue, pose: .still, crop: CoachCanvas.full) {
                        CoachSilhouette(fill: Color(role: .fgOnInkMuted, in: theme))
                            .frame(width: CoachMetrics.cardFigure * CoachMetrics.figureAspect)
                    }
                    .frame(height: CoachMetrics.cardFigure)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        CoachName(coach: coach, name: TypeRamp.headline, title: TypeRamp.footnote, onInk: true)
                        if let tenure {
                            Self.tenureText(tenure)
                                .typeStyle(TypeRamp.footnote)
                                .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                                .lineLimit(1)
                                .accessibilityIdentifier("squad.coach.tenure")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: Sizing.smallIcon, weight: .semibold))
                        .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("squad.coach.open")
            // 换教练 and 解雇 are rare, so they wait on the coach's 简历 (Tracy, 2026-11-04).
            if !canHire {
                browse
            }
        }
    }
}

/// 教练招聘会: an ink header on a white page, a card per coach (its stage, then its name, tags and
/// 期望待遇 on graphite, like the coach's card on 今天) and the coaches still to come.
struct CoachMarketPage: View {
    let market: CoachMarketLoad
    /// The squad's coach now, which the market marks instead of 求职中.
    let current: CoachID?
    let retry: () -> Void
    let open: (Coach) -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.top, proxy.safeAreaInsets.top + Space.xs)
                        .padding(.bottom, CoachMetrics.marketOverlap + Space.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.pageMargin)
                        .background(Color(role: .bgInk, in: theme))
                    content
                        .padding(.horizontal, Space.pageMargin)
                        .padding(.top, -CoachMetrics.marketOverlap)
                        .padding(.bottom, proxy.safeAreaInsets.bottom + Space.xl)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: [.top, .bottom])
        }
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.market")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.m + Space.xxs) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: "JOB FAIR")
                    .typeStyle(TypeRamp.ticketDate)
                    .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                    .accessibilityHidden(true)
                Text(copy: "教练招聘会", bundle: .module)
                    .typeStyle(TypeRamp.largeTitle)
                    .foregroundStyle(Color(role: .fgOnInk, in: theme))
                    .accessibilityAddTraits(.isHeader)
                if case .loaded(let coaches) = market {
                    Text(copy: "\(coaches.count) 位教练在找队伍", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch market {
        case .loading:
            TicketSpinner(size: CoachMetrics.spinner, on: .page)
                .frame(maxWidth: .infinity, minHeight: CoachMetrics.marketCardStage)
                .background(Color(role: .bgCanvas, in: theme), in: RoundedRectangle(cornerRadius: Radius.ticket))
        case .failed:
            StateView.offline(retryIdentifier: "coach.market.retry", retry: retry)
                .accentTone(.ink)
                .frame(maxWidth: .infinity, minHeight: CoachMetrics.marketCardStage)
                .background(Color(role: .bgCanvas, in: theme), in: RoundedRectangle(cornerRadius: Radius.ticket))
        case .loaded(let coaches):
            VStack(spacing: Space.s) {
                ForEach(coaches) { coach in
                    MarketCard(coach: coach, isCurrent: coach.id == current) { open(coach) }
                }
                MoreCoaches()
            }
        }
    }
}

/// A coach in 教练招聘会: its stage with the catchphrase, name and title, tags and 期望待遇.
private struct MarketCard: View {
    let coach: Coach
    let isCurrent: Bool
    let open: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                CoachStage(
                    coach: coach.id, catchphrase: coach.catchphrase,
                    figureHeight: CoachMetrics.marketFigure,
                    floor: CoachMetrics.marketFloor
                )
                .frame(minHeight: CoachMetrics.marketCardStage)
                .overlay(alignment: .topTrailing) {
                    StatusTag(isCurrent: isCurrent).padding(Space.s + 2)
                }
                VStack(alignment: .leading, spacing: Space.s - 2) {
                    CoachName(coach: coach, name: TypeRamp.title, title: TypeRamp.callout, onInk: true)
                    FlowRow {
                        ForEach(coach.tags, id: \.self) { tag in
                            Text(verbatim: tag)
                                .typeStyle(TypeRamp.label)
                                .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                                .lineLimit(1)
                                .padding(.horizontal, Space.s - 2)
                                .padding(.vertical, Space.xxs)
                                .background(Color(role: .borderOnInk, in: theme), in: Capsule())
                        }
                    }
                    HStack(spacing: Space.s) {
                        Text(copy: "期望待遇：\(coach.pay)", bundle: .module)
                            .typeStyle(TypeRamp.footnote)
                            .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(copy: "看简历 ›", bundle: .module)
                            .typeStyle(TypeRamp.calloutEmphasis)
                            .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.top, Space.s)
                    .overlay(alignment: .top) {
                        Hairline(on: .ink)
                    }
                }
                .padding(.horizontal, Space.m)
                .padding(.top, Space.s + 2)
                .padding(.bottom, Space.m)
                .background(Color(role: .bgBrand, in: theme))
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.ticket, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.ticket, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coach.market.coach")
    }
}

/// 更多教练在路上: the coaches still to come, a dashed outline on the white page.
private struct MoreCoaches: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        HStack(spacing: Space.s) {
            ZStack(alignment: .bottom) {
                Color(role: .borderDefault, in: theme)
                CoachSilhouette(fill: Color(role: .fgSubtle, in: theme))
                    .frame(width: CoachMetrics.moreFigure)
            }
            .frame(width: CoachMetrics.moreThumbnail.width, height: CoachMetrics.moreThumbnail.height)
            .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
            .accessibilityHidden(true)
            Text(copy: "更多教练在路上", bundle: .module)
                .typeStyle(TypeRamp.calloutEmphasis)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.m)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.ticket, style: .continuous)
                .strokeBorder(
                    Color(role: .borderDefault, in: theme),
                    style: StrokeStyle(lineWidth: Sizing.selectionStroke, dash: [6, 4]))
        }
    }
}

/// The approved canvas's sizes for the coach's pages.
enum CoachMetrics {
    /// The page loader's size, as every page's.
    static let spinner = 64.0
    /// The 教练 card's empty spot.
    static let thumbnail = 56.0
    /// The coach standing on the 教练 card, its 240 × 320 canvas whole.
    static let cardFigure = 96.0
    /// The silhouette's width in the square, for a coach without a character.
    static let thumbnailFigure = 26.0
    /// A silhouette is twice as tall as it is wide.
    static let figureAspect = 0.5
    /// How far the market's cards ride up over its ink header.
    static let marketOverlap = 40.0
    static let marketCardStage = 268.0
    /// The coach's height on its stage, here and on the 简历 and 解雇 pages.
    static let marketFigure = 190.0
    static let marketFloor = 40.0
    static let moreThumbnail = CGSize(width: 48, height: 56)
    static let moreFigure = 22.0
    static let resumeStage = 380.0
    static let resumeFigure = 184.0
    static let resumeFloor = 72.0
    /// How far the 简历's sheet rides up over the stage, and its corners.
    static let sheetOverlap = 20.0
    static let fireStage = 340.0
    static let fireFloor = 64.0
    /// Where the coach's feet stand on the floor, as a share of its height.
    static let feet = 0.3
    /// The floor's grey over the stage's.
    static let floorShade = 0.35
}
#endif
