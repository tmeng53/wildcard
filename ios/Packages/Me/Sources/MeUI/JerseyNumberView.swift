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
    @State private var picked: Int
    /// Set once this page has saved: a failure shows only for a save made here, never for an
    /// earlier one on another page, and 保存 waits while one is on its way.
    @State private var saving = false
    @State private var saved = false
    @Environment(\.sceneTheme) private var theme

    init(model: MeModel, close: @escaping () -> Void) {
        self.model = model
        self.close = close
        _picked = State(initialValue: model.overview?.cardNumber?.value ?? 0)
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
            Text(verbatim: Self.text(picked))
                .typeStyle(TypeRamp.scoreHero)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(picked)))
                .frame(maxWidth: .infinity)
                .padding(.top, Space.l)
                .accessibilityHidden(true)
            Picker(selection: $picked) {
                ForEach(JerseyNumber.range, id: \.self) { number in
                    Text(verbatim: Self.text(number)).tag(number)
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
                // The wheel offers only 00 to 99.
                guard let number = try? JerseyNumber(picked) else { return }
                saving = true
                Task {
                    await model.save(jerseyNumber: number)
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

    private static func text(_ number: Int) -> String {
        number < 10 ? "0\(number)" : "\(number)"
    }
}
#endif
