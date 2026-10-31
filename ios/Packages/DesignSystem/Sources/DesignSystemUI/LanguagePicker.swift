#if canImport(SwiftUI)
import SwiftUI

extension View {
    /// The app's languages in a sheet from the bottom, each in its own words, the one spoken now
    /// ticked; picking one speaks it at once (`AppLanguage.pick`). The open screen's globe and
    /// 设置's 语言 both show it.
    public func languagePicker(isPresented: Binding<Bool>) -> some View {
        confirmationDialog(Text("语言", bundle: .module), isPresented: isPresented, titleVisibility: .visible) {
            let current = AppLanguage.current
            ForEach(AppLanguage.allCases, id: \.self) { language in
                Button {
                    if language != current { language.pick() }
                } label: {
                    Text(verbatim: language == current ? "\(language.name) ✓" : language.name)
                }
            }
            Button(role: .cancel) {
            } label: {
                Text("取消", bundle: .module)
            }
        }
    }
}
#endif
