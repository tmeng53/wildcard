#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

extension MealScoreCell.Label {
    public var text: Text {
        switch self {
        case .healthy: Text(copy: "健康", bundle: .module)
        case .tasty: Text(copy: "好吃", bundle: .module)
        case .calorieValue: Text(copy: "卡价比", bundle: .module)
        }
    }
}

/// 卡价比's cell as a button whose tap says what it is, 「卡路里性价比」, and nothing more.
struct CalorieValueInfo<Face: View>: View {
    @ViewBuilder let face: Face
    @State private var showsInfo = false

    var body: some View {
        Button {
            showsInfo = true
        } label: {
            face
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsInfo) {
            Text(copy: "卡路里性价比", bundle: .module)
                .typeStyle(TypeRamp.footnote)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .presentationCompactAdaptation(.popover)
        }
    }
}
#endif
