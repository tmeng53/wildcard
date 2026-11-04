#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The glass menu in the style guide: a 「···」 header button opening 编辑, and 删除 asking first.
struct GlassMenuSample: View {
    @State private var isOpen = false

    var body: some View {
        HStack {
            Spacer()
            HeaderButton(Text("编辑", bundle: .module), systemImage: "ellipsis") { isOpen = true }
                .glassMenu(isPresented: $isOpen, items: items)
        }
    }

    private var items: [GlassMenuItem] {
        [
            GlassMenuItem(Text("编辑", bundle: .module), systemImage: "pencil", id: "styleguide.menu.edit") {},
            GlassMenuItem(
                Text("删除", bundle: .module), systemImage: "trash", role: .destructive, id: "styleguide.menu.delete",
                confirm: .init(
                    Text("删除这条？", bundle: .module), label: Text("删除", bundle: .module), id: "styleguide.menu.confirm")
            ) {},
        ]
    }
}
#endif
