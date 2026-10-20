#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import PhotosUI
import SwiftUI

/// The system photo picker, as a social app's new post opens it (spec rev 186, C3): pick up
/// to three in order, the first becomes the cover, or go on with 不加照片.
struct PhotoStep: View {
    @Environment(\.sceneTheme) private var theme
    let model: TodayModel
    @State private var items: [PhotosPickerItem] = []
    @State private var isPreparing = false

    var body: some View {
        NavigationStack {
            PhotosPicker(
                selection: $items, maxSelectionCount: Photos.maxCount, selectionBehavior: .ordered,
                matching: .images, preferredItemEncoding: .current
            ) {
                EmptyView()
            }
            .photosPickerStyle(.inline)
            .photosPickerDisabledCapabilities(.selectionActions)
            .photosPickerAccessoryVisibility(.hidden, edges: .all)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(Text("最近项目", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        model.cancel()
                    } label: {
                        Text("取消", bundle: .module)
                    }
                    .accessibilityIdentifier("photos.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPreparing {
                        ProgressView()
                    } else if items.isEmpty {
                        Button {
                            model.photosPicked([])
                        } label: {
                            Text("不加照片", bundle: .module)
                        }
                        .accessibilityIdentifier("photos.skip")
                    } else {
                        Button {
                            Task { await prepareAndContinue() }
                        } label: {
                            Text("下一步", bundle: .module)
                        }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("photos.next")
                    }
                }
            }
        }
        .tint(Color(role: .fgAccent, in: theme))
    }

    /// Loads each picked photo and shrinks it off the main actor, in the order picked. A photo
    /// that can't be read is left out rather than stopping the post.
    private func prepareAndContinue() async {
        isPreparing = true
        defer { isPreparing = false }
        var prepared: [PreparedPhoto] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                let photo = try? await PhotoPreparation.prepare(data)
            else { continue }
            prepared.append(photo)
        }
        model.photosPicked(prepared)
    }
}
#endif
