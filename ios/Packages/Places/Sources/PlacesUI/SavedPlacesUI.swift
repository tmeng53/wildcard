#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import PlacesDomain
import SwiftUI

/// 地点页 with 收藏 (Tracy, 2026-11-12): the bookmark at the bar's right, filled once the place is
/// saved, which pops up the note card (`SavePlaceCard`) over the page. A place without an Apple
/// Maps id can't be saved and shows no bookmark.
public struct SavablePlaceScreen: View {
    private let place: Place
    private let squad: SquadID?
    private let source: any PlaceSource
    private let saved: SavedPlacesStore
    private let today: LocalDay
    private let openPost: (CheckInID) -> Void
    @State private var isCardOpen = false
    /// Counts saves made from the card, for the bookmark's tap as it fills.
    @State private var saves = 0

    public init(
        place: Place, squad: SquadID?, source: any PlaceSource, saved: SavedPlacesStore, today: LocalDay,
        openPost: @escaping (CheckInID) -> Void
    ) {
        (self.place, self.squad, self.source, self.saved) = (place, squad, source, saved)
        (self.today, self.openPost) = (today, openPost)
    }

    public var body: some View {
        PlaceScreen(place: place, squad: squad, source: source, today: today, openPost: openPost) { place in
            if place.key != nil {
                // Until the list is read, nobody can tell whether it is saved or what its note says.
                SavePlaceButton(isSaved: saved.saved(place) != nil) { isCardOpen = true }
                    .disabled(saved.phase != .loaded)
            }
        }
        .cardPopup(isPresented: $isCardOpen) {
            SavePlaceCard(place: place, store: saved) { didSave in
                isCardOpen = false
                if didSave { saves += 1 }
            }
        }
        .haptic(.save, trigger: saves)
        .task { await saved.loadIfNeeded() }
    }
}

/// 收藏's bookmark: the bar's round button, filled once the place is saved.
struct SavePlaceButton: View {
    let isSaved: Bool
    let action: () -> Void

    var body: some View {
        HeaderButton(
            isSaved ? Text(copy: "已收藏", bundle: .module) : Text(copy: "收藏", bundle: .module),
            systemImage: isSaved ? "bookmark.fill" : "bookmark", action: action
        )
        .accessibilityIdentifier("place.save")
    }
}

/// The note card 收藏 pops up: the place, its 备注 with the keyboard up, 取消 and the graphite
/// 收藏; on a place saved already it changes the note and offers 取消收藏 under them.
struct SavePlaceCard: View {
    let place: Place
    let store: SavedPlacesStore
    /// Closes the card; true once the place was saved.
    let close: (_ didSave: Bool) -> Void
    @State private var note: String
    @State private var failure: SavedPlacesError?
    @Environment(\.sceneTheme) private var theme

    init(place: Place, store: SavedPlacesStore, close: @escaping (_ didSave: Bool) -> Void) {
        (self.place, self.store, self.close) = (place, store, close)
        _note = State(initialValue: store.saved(place)?.note?.text ?? "")
    }

    private var isSaved: Bool { store.saved(place) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlaceHeading(place: place, iconSize: Sizing.control - Space.xxs)
            SectionLabel(Text(copy: "备注", bundle: .module))
                .padding(.top, Space.m)
                .padding(.bottom, Space.xs)
            InputField(
                text: $note, label: Text(copy: "备注", bundle: .module), limit: SavedPlaceNote.maxLength,
                focusesOnAppear: true
            )
            .submitLabel(.done)
            .onSubmit(save)
            .accessibilityIdentifier("savePlace.note")
            if failure == .full {
                InlineFailure(Text(copy: "最多收藏 \(SavedPlace.maxCount) 个地方", bundle: .module))
                    .padding(.top, Space.xs)
            } else if failure != nil {
                InlineFailure().padding(.top, Space.xs)
            }
            HStack(spacing: Space.s) {
                Button {
                    close(false)
                } label: {
                    Text(copy: "取消", bundle: .module).frame(maxWidth: .infinity)
                }
                .buttonStyle(TextButtonStyle(.muted))
                .accessibilityIdentifier("savePlace.cancel")
                Button(action: save) {
                    Label {
                        Text(copy: "收藏", bundle: .module)
                    } icon: {
                        Image(systemName: "bookmark.fill")
                    }
                    .loadingLabel(store.isWriting)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!SavedPlacesStore.canSave(note: note) || store.isWriting)
                .accessibilityIdentifier("savePlace.save")
            }
            .padding(.top, Space.s)
            if isSaved {
                Button(action: remove) {
                    Text(copy: "取消收藏", bundle: .module).frame(maxWidth: .infinity)
                }
                .buttonStyle(TextButtonStyle(.danger))
                .disabled(store.isWriting)
                .accessibilityIdentifier("savePlace.remove")
            }
        }
        .padding(Space.m + Space.xxs)
        .frame(width: Self.width)
        .background(Color(role: .bgCanvas, in: theme), in: RoundedRectangle(cornerRadius: Radius.menu))
        .accentTone(.brand)
    }

    /// The card's own width, the smallest phone's page between its gutters; `cardPopup` grows it
    /// to the page.
    private static var width: Double { 343 }

    private func save() {
        guard SavedPlacesStore.canSave(note: note), !store.isWriting else { return }
        Task {
            failure = await store.save(place, note: note)
            if failure == nil { close(true) }
        }
    }

    private func remove() {
        guard let key = place.key else { return }
        Task {
            failure = await store.remove(key)
            if failure == nil { close(false) }
        }
    }
}

/// The place's kind icon in a mist disc, its name, and its kind under it.
struct PlaceHeading: View {
    let place: Place
    let iconSize: Double
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: place.kind.symbol)
                .font(.system(size: iconSize * 0.45, weight: .semibold))
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .frame(width: iconSize, height: iconSize)
                .background(Color(role: .bgSubtle, in: theme), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs / 2) {
                Text(verbatim: place.name)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(2)
                if let kind = place.kind.localizedName {
                    Text(verbatim: kind)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .lineLimit(1)
                }
            }
        }
    }
}

/// 收藏, pushed from 我's bookmark: every place the member saved in one list, newest first, each
/// with its note, or a grey 写备注 that pops up the note card. A tap opens the place's page; a
/// swipe left removes it. Only the member sees it.
public struct SavedPlacesPage: View {
    private let store: SavedPlacesStore
    private let open: (Place) -> Void
    @State private var editing: Place?
    @State private var removeFailed = false
    @Environment(\.sceneTheme) private var theme

    /// - Parameter open: a row was tapped: its place's page.
    public init(store: SavedPlacesStore, open: @escaping (Place) -> Void) {
        (self.store, self.open) = (store, open)
    }

    public var body: some View {
        List {
            Text(copy: "收藏", bundle: .module)
                .typeStyle(TypeRamp.largeTitle)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .accessibilityAddTraits(.isHeader)
                .listRowSeparator(.hidden)
            if removeFailed {
                InlineFailure()
                    .listRowSeparator(.hidden)
            }
            ForEach(store.places) { saved in
                SavedPlaceRow(saved: saved, open: { open(saved.place) }, writeNote: { editing = saved.place })
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { removeFailed = await store.remove(saved.key) != nil }
                        } label: {
                            Label {
                                Text(copy: "删除", bundle: .module)
                            } icon: {
                                Image(systemName: "trash")
                            }
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay { emptyOrFailed }
        .background(Color(role: .bgCanvas, in: theme))
        .barTitleOnScroll(Text(copy: "收藏", bundle: .module))
        .pushedPage()
        .cardPopup(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let editing {
                SavePlaceCard(place: editing, store: store) { _ in
                    // A save that ends after a tap off the card leaves a card opened since alone.
                    if self.editing == editing { self.editing = nil }
                }
            }
        }
        .refreshable {
            removeFailed = false
            await store.load()
        }
        .task { await store.loadIfNeeded() }
    }

    @ViewBuilder private var emptyOrFailed: some View {
        if store.places.isEmpty {
            switch store.phase {
            case .loading, .signedOut:
                EmptyView()
            case .loaded:
                StateView(Text(copy: "还没有收藏", bundle: .module))
                    .accessibilityIdentifier("savedPlaces.empty")
            case .failed:
                StateView.offline(retryIdentifier: "savedPlaces.retry") { Task { await store.load() } }
            }
        }
    }
}

/// One saved place: its kind's icon on a mist tile, its name, the note (or a grey 写备注 to write
/// one) and its kind.
private struct SavedPlaceRow: View {
    let saved: SavedPlace
    let open: () -> Void
    let writeNote: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: saved.place.kind.symbol)
                .font(.system(size: Sizing.kindIcon, weight: .semibold))
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .frame(width: Sizing.kindButton, height: Sizing.kindButton)
                .background(
                    Color(role: .bgSubtle, in: theme),
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs / 2) {
                Text(verbatim: saved.place.name)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(1)
                note
                if let kind = saved.place.kind.localizedName {
                    Text(verbatim: kind)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.s)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(copy: "写备注", bundle: .module), writeNote)
        .accessibilityIdentifier("savedPlaces.row")
    }

    @ViewBuilder private var note: some View {
        if let note = saved.note {
            Text(verbatim: note.text)
                .typeStyle(TypeRamp.callout)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
        } else {
            Button(action: writeNote) {
                Text(copy: "写备注", bundle: .module)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgSubtle, in: theme))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("savedPlaces.writeNote")
        }
    }
}
#endif
