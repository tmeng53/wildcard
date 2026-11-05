#if os(iOS)
import DesignSystem
import Photos
import SwiftUI
import UIKit

/// 存图's sheet, after the flash: a big preview of the exact picture being saved, 关闭 at the
/// top right, then 保存到相册 (a brand capsule, which says 已存到相册 once it is in Photos) and
/// 分享 (the system share sheet). 出赛表's poster and the 战报's last page both open it.
public struct SavePictureSheet: View {
    private enum Saving: Equatable {
        case ready, saving, saved, failed
    }

    @Environment(\.sceneTheme) private var theme
    private let image: UIImage
    private let close: () -> Void
    @State private var saving = Saving.ready
    @State private var isSharing = false

    /// The preview's width; a taller picture (the 战报's, phone-shaped) is held to the room left.
    private static let previewWidth: Double = 300

    public init(image: UIImage, close: @escaping () -> Void) {
        self.image = image
        self.close = close
    }

    public var body: some View {
        VStack(spacing: Space.m) {
            HStack {
                Spacer()
                HeaderButton(Text("关闭", bundle: .module), systemImage: "xmark", action: close)
                    .accessibilityIdentifier("savePicture.close")
            }
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .frame(maxWidth: Self.previewWidth, maxHeight: .infinity)
                .accessibilityHidden(true)
            VStack(spacing: Space.xs) {
                Button(action: save) {
                    label.frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(.large))
                .accentTone(.brand)
                .disabled(saving == .saving || saving == .saved)
                .accessibilityIdentifier("savePicture.save")
                Button {
                    isSharing = true
                } label: {
                    Text("分享", bundle: .module).frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("savePicture.share")
            }
        }
        .padding(.horizontal, Space.pageMargin)
        .padding(.vertical, Space.s)
        .background(Color(role: .bgCanvas, in: theme))
        .sheet(isPresented: $isSharing) {
            ShareSheet(image: image)
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
        saving = .saving
        let image = image
        Task {
            do {
                try await Self.add(image)
                saving = .saved
            } catch {
                saving = .failed
            }
        }
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

/// The system share sheet on a picture: Messages, Xiaohongshu and the rest.
private struct ShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
