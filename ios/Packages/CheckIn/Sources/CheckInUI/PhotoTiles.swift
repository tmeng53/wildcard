#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import ImageIO
import PhotosUI
import SportsUI
import SwiftUI
import UIKit

/// The post's photos as a row of square tiles, the cover first and marked 封面, then 「+ 照片」
/// while there is room for another (up to three). A 训练 from Health has its map and chart among
/// them, which don't count toward the three. + asks 拍照 or 从相册选 (straight to the album on
/// a phone without a camera); × takes a tile off, the map too; a long press drags a tile to
/// another place, and the first is the cover; tapping a photo shows the photos whole, full
/// screen.
struct PhotoTiles: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: ComposeModel
    @State private var isChoosingSource = false
    @State private var isPickingFromLibrary = false
    @State private var isTakingPhoto = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var page = 0
    @State private var isViewing = false

    /// A tile's side: three photos and 「+」 fit across the smallest phone.
    static let side: Double = 76

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.xs) {
                ForEach(Array(model.tiles.enumerated()), id: \.element.id) { index, tile in
                    ComposeTile(
                        tile: tile, number: index + 1, isCover: index == 0, model: model,
                        view: {
                            if case .photo(let photo) = tile, let page = model.photos.firstIndex(of: photo) {
                                view(page)
                            }
                        },
                        remove: { model.remove(tile) }
                    )
                    .draggable(tile.id)
                    .dropDestination(for: String.self) { dropped, _ in
                        guard let id = dropped.first else { return false }
                        model.move(id, onto: tile.id)
                        return true
                    }
                }
                if model.canAddPhoto {
                    addTile
                }
            }
            // Room for the × badges and the cover's ring, which the scroll view would clip.
            .padding(.vertical, Space.xxs)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.tiles)
        .photoViewer(isPresented: $isViewing, count: model.photos.count, page: $page, load: jpeg)
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
                if model.isPreparingPhotos {
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
        .disabled(model.isPreparingPhotos)
        .accessibilityLabel(Text("加照片", bundle: .module))
        .accessibilityIdentifier("compose.addPhoto")
        .glassMenu(
            isPresented: $isChoosingSource, title: Text("加照片", bundle: .module),
            items: [
                GlassMenuItem(Text("拍照", bundle: .module), systemImage: "camera", id: "compose.addPhoto.camera") {
                    isTakingPhoto = true
                },
                GlassMenuItem(
                    Text("从相册选", bundle: .module), systemImage: "photo.on.rectangle", id: "compose.addPhoto.library"
                ) {
                    isPickingFromLibrary = true
                },
            ])
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

    /// Opens on photo `index`.
    private func view(_ index: Int) {
        page = index
        isViewing = true
    }

    /// Loads each picked photo and shrinks it off the main actor, in the order picked. A photo
    /// that can't be read is left out rather than stopping the post.
    private func prepare(_ items: [PhotosPickerItem]) async {
        var data: [Data] = []
        model.isPreparingPhotos = true
        for item in items {
            if let loaded = try? await item.loadTransferable(type: Data.self) { data.append(loaded) }
        }
        await prepare(data)
    }

    private func prepare(_ data: [Data]) async {
        model.isPreparingPhotos = true
        defer { model.isPreparingPhotos = false }
        var prepared: [PreparedPhoto] = []
        for each in data {
            if let photo = try? await PhotoPreparation.prepare(each) { prepared.append(photo) }
        }
        model.add(prepared)
    }
}

/// One tile, a photo or the workout's map or chart: the cover ringed and labelled 封面, × at its
/// corner to take it off.
private struct ComposeTile: View {
    @Environment(\.sceneTheme) private var theme
    let tile: ComposedTile
    let number: Int
    let isCover: Bool
    let model: ComposeModel
    let view: () -> Void
    let remove: () -> Void

    var body: some View {
        Button(action: view) {
            face
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
        .accessibilityLabel(label)
        .accessibilityHint(isWorkout ? Text("长按拖动换位置", bundle: .module) : Text("全屏看，长按拖动换位置", bundle: .module))
        .accessibilityAddTraits(isCover ? .isSelected : [])
        .accessibilityIdentifier(
            tile == .workout(.chart)
                ? "compose.chartTile"
                : isWorkout ? "compose.workoutTile" : isCover ? "compose.cover" : "compose.photo.\(number)"
        )
        .overlay(alignment: .topTrailing) {
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: Self.glyph, weight: .bold))
                    .foregroundStyle(Color(role: .fgOnInk, in: theme))
                    .frame(width: Self.badge, height: Self.badge)
                    .background(Color(role: .bgInk, in: theme).opacity(0.7), in: Circle())
                    .padding(Space.xxs)
                    // The tap reaches past the small badge, but stays clear of the tile's middle,
                    // which opens it.
                    .frame(width: Sizing.compactControl, height: Sizing.compactControl, alignment: .topTrailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("删掉这张", bundle: .module))
            .accessibilityIdentifier(
                tile == .workout(.chart)
                    ? "compose.chartTile.remove"
                    : isWorkout ? "compose.workoutTile.remove" : "compose.photo.\(number).remove")
        }
    }

    private var isWorkout: Bool { if case .workout = tile { true } else { false } }

    @ViewBuilder private var face: some View {
        switch tile {
        case .photo(let photo):
            ComposedPhotoImage(photo: photo, load: model.loadPhoto)
        case .workout(.map):
            if let route = model.workout?.route { WorkoutMap(route: route, activity: model.currentActivity, lane: 5) }
        case .workout(.chart):
            if let series = model.workout?.series { WorkoutChart(series: series, activity: model.currentActivity) }
        }
    }

    private var label: Text {
        let place = isCover ? Text("封面", bundle: .module) : Text("第 \(number) 张", bundle: .module)
        return switch tile {
        case .photo: place
        case .workout(.map): Text("路线地图，\(place)", bundle: .module)
        case .workout(.chart): Text("数据图，\(place)", bundle: .module)
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
