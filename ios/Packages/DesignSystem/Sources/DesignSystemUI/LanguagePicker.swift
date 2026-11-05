#if canImport(SwiftUI)
import SwiftUI

extension View {
    /// The app's languages in a glass menu from this view, each in its own words, the one spoken
    /// now ticked; picking one speaks it at once (`AppLanguage.pick`). The open screen's globe and
    /// 设置's 语言 both show it.
    public func languagePicker(isPresented: Binding<Bool>) -> some View {
        let current = AppLanguage.current
        return glassMenu(
            isPresented: isPresented, title: Text("语言", bundle: .module),
            items: AppLanguage.allCases.map { language in
                GlassMenuItem(
                    Text(verbatim: language.name), isSelected: language == current, id: "language.\(language.rawValue)"
                ) {
                    if language != current { language.pick() }
                }
            }
        )
    }
}
#endif
