#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI

/// 设置 › 生日: the member's ticket from sign-up with their character under the lamp, then the
/// birthday on the flip clock, opening on the saved day or on 2000-01-01 (never a day from Apple
/// Health, Tracy 2026-11-08), and why it's asked. 保存 saves a day the member turned to; 删除生日,
/// in red, forgets a saved one. Either goes back once it saved.
struct BirthdayView: View {
    @Bindable var model: MeModel
    @State private var draft: BirthdayDraft
    /// Which call is on its way, so its button shows 三拍 and the other waits.
    @State private var working: Work?
    /// Set once this page has saved: a failure shows only for a save made here.
    @State private var tried = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sceneTheme) private var theme
    private let today: LocalDay

    private enum Work { case save, forget }

    init(model: MeModel, now: Date = .now, in timeZone: TimeZone = .current) {
        self.model = model
        _draft = State(initialValue: BirthdayDraft(saved: model.overview?.birthday))
        today = LocalDay(at: now, in: timeZone)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                Text(copy: "生日", bundle: .module)
                    .typeStyle(TypeRamp.taskTitle)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityAddTraits(.isHeader)
                CharacterStage(issued: model.overview?.joinedAt) {
                    MeStage(character: model.overview?.character, size: CGSize(width: 150, height: 190))
                        .padding(.bottom, CharacterStage<EmptyView, EmptyView>.stubHeight)
                } stub: {
                    Text(verbatim: model.overview?.character.nickname ?? "")
                        .typeStyle(TypeRamp.headline)
                        .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                        .lineLimit(1)
                }
                .aspectRatio(Self.ticketShape, contentMode: .fit)
                .accessibilityHidden(true)
                VStack(spacing: Space.xs) {
                    FlipClockView.date(
                        values: $draft.values, years: BirthdayDraft.years(through: today), identifier: "birthday")
                    Text(copy: "用来算心率区间", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
                .frame(maxWidth: .infinity)
                if tried && model.saveFailed {
                    SaveFailed().frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.l)
        }
        .background(Color(role: .bgCanvas, in: theme))
        .actionBar {
            VStack(spacing: Space.xxs) {
                Button {
                    run(.save, draft.birthday(today: today))
                } label: {
                    Text(copy: "保存", bundle: .module).loadingLabel(working == .save).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(working != nil || !draft.isTouched || draft.birthday(today: today) == nil)
                .accessibilityIdentifier("birthday.save")
                if model.overview?.birthday != nil {
                    Button {
                        run(.forget, nil)
                    } label: {
                        Text(copy: "删除生日", bundle: .module).loadingLabel(working == .forget)
                    }
                    .buttonStyle(TextButtonStyle(.danger))
                    .disabled(working != nil)
                    .accessibilityIdentifier("birthday.delete")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("birthday.page")
        .pushedPage(canGoBack: working == nil)
    }

    private func run(_ work: Work, _ birthday: Birthday?) {
        working = work
        Task {
            let saved = await model.save(birthday: birthday)
            (working, tried) = (nil, true)
            if saved { dismiss() }
        }
    }

    /// The ticket's shape, the design's 358 by 300.
    private static let ticketShape: Double = 358.0 / 300.0
}

extension Birthday {
    /// 1996.04.18, as 设置's row shows it.
    var dotted: String { description.replacingOccurrences(of: "-", with: ".") }
}
#endif
