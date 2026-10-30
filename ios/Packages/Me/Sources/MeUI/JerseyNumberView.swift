#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI

/// 球衣号码: the member picks the number on their player card, 00 to 99, on a wheel under the
/// number as the card prints it. Squadmates may wear the same one.
struct JerseyNumberView: View {
    @Bindable var model: MeModel
    let close: () -> Void
    @State private var picked: JerseyNumber
    /// Set once this page has saved: a failure shows only for a save made here, never for an
    /// earlier one on another page, and 保存 waits while one is on its way.
    @State private var saving = false
    @State private var saved = false
    @Environment(\.sceneTheme) private var theme

    init(model: MeModel, close: @escaping () -> Void) {
        self.model = model
        self.close = close
        _picked = State(initialValue: model.overview?.cardNumber ?? Self.numbers[0])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderButton(Text("返回", bundle: .module), systemImage: "chevron.left", action: close)
                .accessibilityIdentifier("number.back")
            Text("球衣号码", bundle: .module)
                .typeStyle(TypeRamp.largeTitle)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Space.s)
            Text(verbatim: picked.text)
                .typeStyle(TypeRamp.scoreHero)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(picked.value)))
                .frame(maxWidth: .infinity)
                .padding(.top, Space.l)
                .accessibilityHidden(true)
            Picker(selection: $picked) {
                ForEach(Self.numbers, id: \.self) { number in
                    Text(verbatim: number.text).tag(number)
                }
            } label: {
                Text("球衣号码", bundle: .module)
            }
            .pickerStyle(.wheel)
            .accessibilityIdentifier("number.picker")
            Spacer(minLength: Space.l)
            if saved && model.saveFailed {
                SaveFailed().frame(maxWidth: .infinity).padding(.bottom, Space.s)
            }
            Button {
                saving = true
                Task {
                    await model.save(jerseyNumber: picked)
                    (saving, saved) = (false, true)
                    if !model.saveFailed { close() }
                }
            } label: {
                Text("保存", bundle: .module).frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(saving)
            .accessibilityIdentifier("number.save")
        }
        .padding(.horizontal, Space.pageMargin)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.l)
        .background(Color(role: .bgCanvas, in: theme))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("number.page")
    }

    /// Every number the API takes, 00 to 99.
    private static let numbers = JerseyNumber.range.compactMap { try? JerseyNumber($0) }
}
#endif
