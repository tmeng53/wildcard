#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

// The squad's coach (approved canvas 雇教练页面, 2026-11-01): the 教练 card on 小队设置, 教练市场,
// a coach's 简历 and 解雇. Only the captain hires, changes and fires; everyone reads the 简历.
// Coaches have no character of their own yet, so each stands as an ink silhouette.

/// A page the 教练 card opens, over 小队设置.
enum CoachRoute: Hashable {
    case market
    case resume(Coach)
    case fire(Coach)
}

/// 小队设置's 教练 card: an empty spot and 招聘, or the coach, its week, 换教练 and 解雇.
struct CoachCard: View {
    let hire: SquadCoach.Hire?
    let week: Int?
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
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("squad.coach")
    }

    private var empty: some View {
        HStack(spacing: Space.s) {
            CoachThumbnail(isEmpty: true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("还没有教练", bundle: .module)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                if !canHire {
                    Text("只有队长能雇教练", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if canHire {
                Button {
                    open(.market)
                } label: {
                    Text("招聘", bundle: .module)
                }
                .buttonStyle(PrimaryButtonStyle(.regular))
                .accentTone(.ink)
                .fixedSize()
                .accessibilityIdentifier("squad.coach.hire")
            }
        }
    }

    private func hired(_ coach: Coach) -> some View {
        VStack(spacing: Space.s) {
            Button {
                open(.resume(coach))
            } label: {
                HStack(spacing: Space.s) {
                    CoachThumbnail(isEmpty: false)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        CoachName(coach: coach, name: TypeRamp.headline, title: TypeRamp.footnote)
                        if let week {
                            Text("执教第 \(week) 周", bundle: .module)
                                .typeStyle(TypeRamp.footnote)
                                .foregroundStyle(Color(role: .fgMuted, in: theme))
                                .lineLimit(1)
                                .accessibilityIdentifier("squad.coach.week")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: Sizing.smallIcon, weight: .semibold))
                        .foregroundStyle(Color(role: .fgSubtle, in: theme))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("squad.coach.open")
            if canHire {
                HStack(spacing: Space.xs) {
                    Button {
                        open(.market)
                    } label: {
                        Text("换教练", bundle: .module).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle(.inCard))
                    .accessibilityIdentifier("squad.coach.change")
                    Button {
                        open(.fire(coach))
                    } label: {
                        Text("解雇", bundle: .module).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle(.inCard, tone: .danger))
                    .accessibilityIdentifier("squad.coach.fire")
                }
            }
        }
    }
}

/// 教练市场: an ink header, a card per coach with its catchphrase, tags and 期望待遇, and the
/// coaches still to come.
struct CoachMarketPage: View {
    let market: CoachMarketLoad
    /// The squad's coach now, which the market marks instead of 求职中.
    let current: CoachID?
    let back: () -> Void
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
        .background(Color(role: .bgSubtle, in: theme).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.market")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.m + Space.xxs) {
            HeaderButton(Text("返回", bundle: .module), systemImage: "chevron.left", on: .ink, action: back)
                .accessibilityIdentifier("coach.market.back")
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: "COACH MARKET")
                    .typeStyle(TypeRamp.ticketDate)
                    .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                    .accessibilityHidden(true)
                Text("教练市场", bundle: .module)
                    .typeStyle(TypeRamp.largeTitle)
                    .foregroundStyle(Color(role: .fgOnInk, in: theme))
                    .accessibilityAddTraits(.isHeader)
                if case .loaded(let coaches) = market {
                    Text("\(coaches.count) 位教练在找队伍", bundle: .module)
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
            VStack(spacing: Space.m) {
                Text("网络开小差了", bundle: .module)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                Button(action: retry) { Text("再试一次", bundle: .module) }
                    .buttonStyle(PrimaryButtonStyle(.regular))
                    .accentTone(.ink)
                    .accessibilityIdentifier("coach.market.retry")
            }
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

/// A coach in 教练市场: its stage with the catchphrase, name and title, tags and 期望待遇.
private struct MarketCard: View {
    let coach: Coach
    let isCurrent: Bool
    let open: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                CoachStage(
                    catchphrase: coach.catchphrase, bubble: .leading, figureWidth: CoachMetrics.marketFigure,
                    floor: CoachMetrics.marketFloor
                )
                .frame(height: CoachMetrics.marketCardStage)
                .overlay(alignment: .topTrailing) {
                    StatusTag(isCurrent: isCurrent).padding(Space.s + 2)
                }
                VStack(alignment: .leading, spacing: Space.s - 2) {
                    CoachName(coach: coach, name: TypeRamp.title, title: TypeRamp.callout)
                    FlowRow {
                        ForEach(coach.tags, id: \.self) { tag in
                            Text(verbatim: tag)
                                .typeStyle(TypeRamp.label)
                                .foregroundStyle(Color(role: .fgDefault, in: theme))
                                .lineLimit(1)
                                .padding(.horizontal, Space.s - 2)
                                .padding(.vertical, Space.xxs)
                                .background(Color(role: .bgSubtle, in: theme), in: Capsule())
                        }
                    }
                    HStack(spacing: Space.s) {
                        Text("期望待遇：\(coach.pay)", bundle: .module)
                            .typeStyle(TypeRamp.footnote)
                            .foregroundStyle(Color(role: .fgMuted, in: theme))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("看简历 ›", bundle: .module)
                            .typeStyle(TypeRamp.calloutEmphasis)
                            .foregroundStyle(Color(role: .fgDefault, in: theme))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.top, Space.s)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color(role: .borderDefault, in: theme)).frame(height: Sizing.hairline)
                    }
                }
                .padding(.horizontal, Space.m)
                .padding(.top, Space.s + 2)
                .padding(.bottom, Space.m)
            }
            .background(Color(role: .bgCanvas, in: theme))
            .clipShape(RoundedRectangle(cornerRadius: Radius.ticket, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.ticket, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coach.market.coach")
    }
}

/// 更多教练在路上: the coaches still to come.
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
            Text("更多教练在路上", bundle: .module)
                .typeStyle(TypeRamp.calloutEmphasis)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.m)
        .background(Color(role: .bgCanvas, in: theme), in: RoundedRectangle(cornerRadius: Radius.ticket))
        .opacity(0.7)
    }
}

/// The approved canvas's sizes for the coach's pages.
enum CoachMetrics {
    /// The page loader's size, as every page's.
    static let spinner = 64.0
    /// The 教练 card's square.
    static let thumbnail = 56.0
    static let thumbnailFigure = 26.0
    /// A silhouette is twice as tall as it is wide.
    static let figureAspect = 0.5
    /// How far the market's cards ride up over its ink header.
    static let marketOverlap = 40.0
    static let marketCardStage = 188.0
    static let marketFigure = 70.0
    static let marketFloor = 40.0
    static let moreThumbnail = CGSize(width: 48, height: 56)
    static let moreFigure = 22.0
    static let resumeStage = 380.0
    static let resumeFigure = 92.0
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
