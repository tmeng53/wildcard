#if os(iOS)
import DesignSystem
import Photos
import SwiftUI
import UIKit

/// 存图's sheet: a big preview of the exact picture being saved, 关闭 at the top right, then
/// 保存到相册 (a brand capsule, which says 已存到相册 once it is in Photos) and 分享 (the system
/// share sheet). 出赛表's poster and the 战报's last page open it on a finished picture. A picture
/// the member can still change (the 成绩卡) brings a live preview that changes it with a tap, its
/// options under the preview, and draws the picture when it is saved or shared; a change after
/// a save offers 保存到相册 again.
public struct SavePictureSheet<Preview: View, Options: View>: View {
    private enum Saving: Equatable {
        case ready, saving, saved, failed
    }

    /// A picture handed to the share sheet.
    private struct Shared: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    @Environment(\.sceneTheme) private var theme
    private let preview: Preview
    private let options: Options
    private let picture: @MainActor () -> UIImage?
    private let choices: AnyHashable
    private let close: () -> Void
    @State private var saving = Saving.ready
    @State private var sharing: Shared?

    /// The preview's width; a taller picture (the 战报's, phone-shaped) is held to the room left.
    private static var previewWidth: Double { 300 }

    /// A picture the member changes on the preview.
    /// - Parameters:
    ///   - choices: what the member picked; when it changes, 保存到相册 is offered again.
    ///   - picture: draws the picture as it is now, to save or share.
    ///   - preview: the picture, live, at its own shape; the sheet sizes and rounds it.
    ///   - options: what goes under the preview.
    public init(
        choices: AnyHashable, picture: @escaping @MainActor () -> UIImage?, close: @escaping () -> Void,
        @ViewBuilder preview: () -> Preview, @ViewBuilder options: () -> Options
    ) {
        self.choices = choices
        self.picture = picture
        self.close = close
        self.preview = preview()
        self.options = options()
    }

    public var body: some View {
        VStack(spacing: Space.m) {
            HStack {
                Spacer()
                HeaderButton(Text("关闭", bundle: .module), systemImage: "xmark", action: close)
                    .accessibilityIdentifier("savePicture.close")
            }
            preview
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .frame(maxWidth: Self.previewWidth, maxHeight: .infinity)
                .accessibilityIdentifier("savePicture.preview")
            options
            VStack(spacing: Space.xs) {
                Button(action: save) {
                    label.frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(.large))
                .accentTone(.brand)
                .disabled(saving == .saving || saving == .saved)
                .accessibilityIdentifier("savePicture.save")
                Button(action: share) {
                    Text("分享", bundle: .module).frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("savePicture.share")
            }
        }
        .padding(.horizontal, Space.pageMargin)
        .padding(.vertical, Space.s)
        .background(Color(role: .bgCanvas, in: theme))
        .onChange(of: choices) { saving = .ready }
        .sheet(item: $sharing) { shared in
            ShareSheet(image: shared.image)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
    }

    private var label: Text {
        switch saving {
        case .ready, .saving: Text("保存到相册", bundle: .module)
        case .saved: Text("已存到相册", bundle: .module)
        case .failed: Text("没存上，再试一次", bundle: .module)
        }
    }

    /// Adds the picture to Photos, asking only to add (never to read the library).
    private func save() {
        guard let image = picture() else {
            saving = .failed
            return
        }
        saving = .saving
        Task {
            do {
                try await Self.add(image)
                saving = .saved
            } catch {
                saving = .failed
            }
        }
    }

    private func share() {
        guard let image = picture() else {
            saving = .failed
            return
        }
        sharing = Shared(image: image)
    }
}

extension SavePictureSheet where Preview == PicturePreview, Options == EmptyView {
    /// A finished picture: the 出赛表's poster, the 战报's last page.
    public init(image: UIImage, close: @escaping () -> Void) {
        self.init(
            choices: AnyHashable(0), picture: { image }, close: close, preview: { PicturePreview(image: image) },
            options: { EmptyView() })
    }
}

extension SavePictureSheet {
    /// Photos runs the change block on its own queue, so it is built here, outside the view's
    /// main-actor isolation: a block that inherited it would trap Swift 6's isolation check.
    fileprivate nonisolated static func add(_ image: UIImage) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}

/// A finished picture as `SavePictureSheet` previews it: whole, at its own shape.
public struct PicturePreview: View {
    let image: UIImage

    public var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .accessibilityHidden(true)
    }
}

/// The system share sheet on a picture: Messages, Xiaohongshu and the rest.
private struct ShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
