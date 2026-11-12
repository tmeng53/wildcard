#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI

/// 球衣号码: the member picks the number on their player card, 00 to 99, on a wheel under the
/// number as the card prints it. Squadmates may wear the same one. It opens from the character
/// editor's 球衣号码, which the app passes this page to, pushed over the editor; `close` goes back
/// once the number saved.
public struct JerseyNumberView: View {
    @Bindable private var model: MeModel
    private let close: () -> Void
    @State private var picked: JerseyNumber
    /// Set once this page has saved: a failure shows only for a save made here, never for an
    /// earlier one on another page, and 保存 waits while one is on its way.
    @State private var saving = false
    @State private var saved = false
    @Environment(\.sceneTheme) private var theme

    public init(model: MeModel, close: @escaping () -> Void) {
        self.model = model
        self.close = close
        _picked = State(initialValue: model.overview?.cardNumber ?? Self.numbers[0])
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(copy: "球衣号码", bundle: .module)
                .typeStyle(TypeRamp.largeTitle)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .accessibilityAddTraits(.isHeader)
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
                Text(copy: "球衣号码", bundle: .module)
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
                Text(copy: "保存", bundle: .module).loadingLabel(saving).frame(maxWidth: .infinity)
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
        .pushedPage()
        // A brand page wherever it opens: it is pushed in the editor's cover over 我, whose stack
        // doesn't inherit 我's tone, so without this 保存 wore the gym scene's steel blue.
        .accentTone(.brand)
    }

    /// Every number the API takes, 00 to 99.
    private static let numbers = JerseyNumber.range.compactMap { try? JerseyNumber($0) }
}
#endif
