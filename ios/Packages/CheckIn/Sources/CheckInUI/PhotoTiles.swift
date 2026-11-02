#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import ImageIO
import PhotosUI
import SwiftUI
import UIKit

/// The post's photos as a row of square tiles, the cover first and marked 封面, then 「+ 照片」
/// while there is room for another (up to three). + asks 拍照 or 从相册选 (straight to the
/// album on a phone without a camera); × takes a photo off; tapping another photo makes it the
/// cover, and tapping the cover shows the photos whole, full screen.
struct PhotoTiles: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: ComposeModel
    @State private var isChoosingSource = false
    @State private var isPickingFromLibrary = false
    @State private var isTakingPhoto = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var isPreparing = false
    @State private var page = 0
    @State private var isViewing = false

    /// A tile's side: three photos and 「+」 fit across the smallest phone.
    static let side: Double = 76

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                PhotoTile(
                    photo: photo, number: index + 1, isCover: index == 0, load: model.loadPhoto,
                    tap: {
                        if index == 0 { view() } else { model.makeCover(photo) }
                    },
                    remove: { model.remove(photo) })
            }
            if model.canAddPhoto {
                addTile
            }
        }
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.photos)
        .photoViewer(isPresented: $isViewing, count: model.photos.count, page: $page, load: jpeg)
        .confirmationDialog(Text("加照片", bundle: .module), isPresented: $isChoosingSource) {
            Button {
                isTakingPhoto = true
            } label: {
                Text("拍照", bundle: .module)
            }
            .accessibilityIdentifier("compose.addPhoto.camera")
            Button {
                isPickingFromLibrary = true
            } label: {
                Text("从相册选", bundle: .module)
            }
            .accessibilityIdentifier("compose.addPhoto.library")
        }
        .photosPicker(
            isPresented: $isPickingFromLibrary, selection: $picked,
            maxSelectionCount: Photos.maxCount - model.photos.count, selectionBehavior: .ordered, matching: .images,
            preferredItemEncoding: .current
        )
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await prepare(items) }
        }
        .fullScreenCover(isPresented: $isTakingPhoto) {
            CameraPicker { data in
                Task { await prepare([data]) }
            }
            .ignoresSafeArea()
        }
    }

    private var addTile: some View {
        Button {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                isChoosingSource = true
            } else {
                isPickingFromLibrary = true
            }
        } label: {
            VStack(spacing: Space.xxs) {
                if isPreparing {
                    LoadingDots()
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: Sizing.icon, weight: .medium))
                    Text("照片", bundle: .module)
                        .typeStyle(TypeRamp.label)
                }
            }
            .foregroundStyle(Color(role: .fgMuted, in: theme))
            .frame(width: Self.side, height: Self.side)
            .background(
                Color(role: .bgSubtle, in: theme),
                in: RoundedRectangle(cornerRadius: Radius.pick, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isPreparing)
        .accessibilityLabel(Text("加照片", bundle: .module))
        .accessibilityIdentifier("compose.addPhoto")
    }

    /// Photo `index` as it will be posted, while it's still one of them.
    private var jpeg: @Sendable (Int) async -> Data? {
        let photos = model.photos
        let load = model.loadPhoto
        return { index in
            guard photos.indices.contains(index) else { return nil }
            switch photos[index] {
            case .new(let photo): return photo.jpeg
            case .saved(let ref): return await load(ref)
            }
        }
    }

    /// Opens on the cover.
    private func view() {
        page = 0
        isViewing = true
    }

    /// Loads each picked photo and shrinks it off the main actor, in the order picked. A photo
    /// that can't be read is left out rather than stopping the post.
    private func prepare(_ items: [PhotosPickerItem]) async {
        var data: [Data] = []
        isPreparing = true
        for item in items {
            if let loaded = try? await item.loadTransferable(type: Data.self) { data.append(loaded) }
        }
        await prepare(data)
    }

    private func prepare(_ data: [Data]) async {
        isPreparing = true
        defer { isPreparing = false }
        var prepared: [PreparedPhoto] = []
        for each in data {
            if let photo = try? await PhotoPreparation.prepare(each) { prepared.append(photo) }
        }
        model.add(prepared)
    }
}

/// One photo: the cover ringed and labelled 封面, × at its corner to take it off.
private struct PhotoTile: View {
    @Environment(\.sceneTheme) private var theme
    let photo: ComposedPhoto
    let number: Int
    let isCover: Bool
    let load: @Sendable (PhotoRef) async -> Data?
    let tap: () -> Void
    let remove: () -> Void

    var body: some View {
        Button(action: tap) {
            ComposedPhotoImage(photo: photo, load: load)
                .frame(width: PhotoTiles.side, height: PhotoTiles.side)
                .clipShape(RoundedRectangle(cornerRadius: Radius.pick, style: .continuous))
                .overlay {
                    if isCover {
                        RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
                            .strokeBorder(Color(role: .bgBrand, in: theme), lineWidth: Sizing.selectionStroke)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if isCover {
                        Text("封面", bundle: .module)
                            .typeStyle(TypeRamp.label)
                            .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                            .padding(.horizontal, Space.xs)
                            .background(Color(role: .bgBrand, in: theme), in: Capsule())
                            .padding(Space.xxs + 2)
                    }
                }
        }
        .buttonStyle(PressableButtonStyle())
        .haptic(.pick, trigger: isCover)
        .accessibilityLabel(isCover ? Text("封面", bundle: .module) : Text("第 \(number) 张照片", bundle: .module))
        .accessibilityHint(isCover ? Text("全屏看", bundle: .module) : Text("设为封面", bundle: .module))
        .accessibilityAddTraits(isCover ? .isSelected : [])
        .accessibilityIdentifier(isCover ? "compose.cover" : "compose.photo.\(number)")
        .overlay(alignment: .topTrailing) {
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: Self.glyph, weight: .bold))
                    .foregroundStyle(Color(role: .fgOnInk, in: theme))
                    .frame(width: Self.badge, height: Self.badge)
                    .background(Color(role: .bgInk, in: theme).opacity(0.7), in: Circle())
                    .padding(Space.xxs)
                    // The tap reaches past the small badge, to a finger's width.
                    .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget, alignment: .topTrailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("删掉这张", bundle: .module))
            .accessibilityIdentifier("compose.photo.\(number).remove")
        }
    }

    private static let badge: Double = 22
    private static let glyph: Double = 10
}

/// A photo on the compose page: one just picked, decoded off the main actor, or one already on
/// the post, loaded first.
struct ComposedPhotoImage: View {
    @Environment(\.sceneTheme) private var theme
    let photo: ComposedPhoto
    let load: @Sendable (PhotoRef) async -> Data?
    @State private var image: CGImage?

    var body: some View {
        switch photo {
        case .new(let prepared):
            PhotoImage(photo: prepared)
        case .saved(let ref):
            Color(role: .borderDefault, in: theme)
                .overlay {
                    if let image {
                        Image(decorative: image, scale: 1).resizable().scaledToFill()
                    }
                }
                .clipped()
                .task(id: ref.path) {
                    guard let data = await load(ref) else { return }
                    image = await Self.decode(data)
                }
        }
    }

    private nonisolated static func decode(_ data: Data) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }
}

/// The system camera, for 拍照. Hands back the photo as JPEG; closes either way.
private struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let took: (Data) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Full quality here: `PhotoPreparation` shrinks and recompresses it.
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 1) {
                parent.took(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif
