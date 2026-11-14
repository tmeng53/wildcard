#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import PlacesDomain
import SwiftUI

/// 地点页 with 收藏 (Tracy, 2026-11-14, v2 A): the bookmark at the bar's right saves the place at
/// once, as Apple Maps and Google Maps do, and fills; a saved place shows its note under its name,
/// or a grey 写备注, which turns into the field in place. The filled bookmark takes it off again,
/// asking first only when that would lose a note. A place without an Apple Maps id can't be saved
/// and shows no bookmark.
public struct SavablePlaceScreen: View {
    private let place: Place
    private let squad: SquadID?
    private let source: any PlaceSource
    private let saved: SavedPlacesStore
    private let today: LocalDay
    private let openPost: (CheckInID) -> Void
    @State private var isWritingNote: Bool
    @State private var failure: SavedPlacesError?
    @State private var confirmsRemoval = false
    /// Counts saves from the bookmark, for its tap as it fills.
    @State private var saves = 0

    /// - Parameter writesNote: opens with the note's field up (收藏's 写备注).
    public init(
        place: Place, squad: SquadID?, source: any PlaceSource, saved: SavedPlacesStore, today: LocalDay,
        writesNote: Bool = false, openPost: @escaping (CheckInID) -> Void
    ) {
        (self.place, self.squad, self.source, self.saved) = (place, squad, source, saved)
        (self.today, self.openPost) = (today, openPost)
        _isWritingNote = State(initialValue: writesNote)
    }

    public var body: some View {
        PlaceScreen(place: place, squad: squad, source: source, today: today, openPost: openPost) { place in
            if place.key != nil {
                // Until the list is read, nobody can tell whether it is saved or what its note says.
                SavePlaceButton(isSaved: saved.saved(place) != nil) { toggle(place) }
                    .disabled(saved.phase != .loaded || saved.isWriting)
                    .glassConfirm(isPresented: $confirmsRemoval, removal(place))
            }
        } note: { place in
            if let entry = saved.saved(place) {
                SavedNoteRow(saved: entry, store: saved, isWriting: $isWritingNote)
            }
            if failure == .full {
                InlineFailure(Text(copy: "最多收藏 \(SavedPlace.maxCount) 个地方", bundle: .module))
            } else if failure != nil {
                InlineFailure()
            }
        }
        .haptic(.save, trigger: saves)
        .task { await saved.loadIfNeeded() }
    }

    /// Taking off a place with a note: asked first, since the note goes too.
    private func removal(_ place: Place) -> GlassMenuItem {
        GlassMenuItem(
            Text(copy: "取消收藏", bundle: .module), systemImage: "bookmark.slash", role: .destructive,
            id: "place.unsave",
            confirm: .init(
                Text(copy: "取消收藏？", bundle: .module), message: Text(copy: "备注也会一起删掉", bundle: .module),
                label: Text(copy: "取消收藏", bundle: .module), id: "place.unsave.confirm")
        ) { remove(place) }
    }

    private func toggle(_ place: Place) {
        guard let entry = saved.saved(place) else {
            Task {
                failure = await saved.save(place, note: "")
                if failure == nil { saves += 1 }
            }
            return
        }
        if entry.note == nil { remove(place) } else { confirmsRemoval = true }
    }

    private func remove(_ place: Place) {
        guard let key = place.key else { return }
        isWritingNote = false
        Task { failure = await saved.remove(key) }
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

/// A saved place's note under its name: the note, or a grey 写备注, either a tap from the field in
/// its place. The keyboard's ✓, or leaving the field, saves it; emptied, the note is gone.
struct SavedNoteRow: View {
    let saved: SavedPlace
    let store: SavedPlacesStore
    @Binding var isWriting: Bool
    @State private var draft = ""
    @State private var failure: SavedPlacesError?
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if isWriting {
                InputField(
                    text: $draft, label: Text(copy: "备注", bundle: .module), limit: SavedPlaceNote.maxLength,
                    focusesOnAppear: true
                ) { focused in
                    if !focused { commit() }
                }
                .submitLabel(.done)
                .onSubmit(commit)
                .accessibilityIdentifier("place.noteField")
            } else {
                Button {
                    draft = saved.note?.text ?? ""
                    isWriting = true
                } label: {
                    Label {
                        if let note = saved.note {
                            Text(verbatim: note.text)
                        } else {
                            Text(copy: "写备注", bundle: .module)
                        }
                    } icon: {
                        Image(systemName: "pencil")
                    }
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: saved.note == nil ? .fgSubtle : .fgDefault, in: theme))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: Sizing.control, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("place.note")
            }
            if failure != nil { InlineFailure() }
        }
        .onAppear { draft = saved.note?.text ?? "" }
    }

    /// Saves the note typed, once, unless it is the one saved already or one the API won't take.
    private func commit() {
        guard isWriting, !store.isWriting else { return }
        guard SavedPlacesStore.canSave(note: draft) else { return }
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed != (saved.note?.text ?? "") else {
            isWriting = false
            return
        }
        Task {
            failure = await store.save(saved.place, note: draft)
            if failure == nil { isWriting = false }
        }
    }
}

/// 收藏, pushed from 我's bookmark: every place the member saved in one list, newest first, each
/// with its note, or a grey 写备注 that opens the place's page with the note's field up. A tap
/// opens the place's page; a swipe left removes it. Only the member sees it.
public struct SavedPlacesPage: View {
    private let store: SavedPlacesStore
    private let open: (Place, _ writingNote: Bool) -> Void
    @State private var removeFailed = false
    @Environment(\.sceneTheme) private var theme

    /// - Parameter open: a row was tapped: its place's page, with the note's field up for 写备注.
    public init(store: SavedPlacesStore, open: @escaping (Place, _ writingNote: Bool) -> Void) {
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
                SavedPlaceRow(saved: saved, open: { open(saved.place, false) }, writeNote: { open(saved.place, true) })
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
