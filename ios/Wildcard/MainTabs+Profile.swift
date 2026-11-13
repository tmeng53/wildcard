import CharacterEditorUI
import CheckInUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import FeedUI
import HomeWidgetUI
import LocationDomain
import MeDomain
import MeUI
import NotificationsDomain
import NotificationsUI
import PlacesDomain
import RecapUI
import ScheduleUI
import SquadDomain
import SquadUI
import SwiftUI

extension MainTabs {
    /// 我, with 出赛表, 换装, 商店街 (and 换装 over it) or 我的动态 pushed over it, and a post opened from the wall or from
    /// 训练记录 pushed over that; closing the post reads 我 again, as an edit or a delete there may
    /// change the record.
    var profilePage: some View {
        NavigationStack {
            MeView(
                model: profile,
                destinations: MeDestinations(
                    editCharacter: wardrobe.editCharacter, schedule: { showsSchedule = true },
                    street: wardrobe.openShop, streetHasNews: wardrobe.hasNews,
                    openPost: {
                        post = OpenedPost(id: $0, model: feed.page(of: $0))
                        (profilePlace, profilePlacePost) = (nil, nil)
                    },
                    privacyPolicy: PolicyPages.privacyPolicy, terms: PolicyPages.terms,
                    writeReview: PolicyPages.writeReview, admin: admin, health: today.health,
                    location: location, widgetGuide: AnyView(WidgetGuide(now: LaunchOptions.now())),
                    badgeMarks: wardrobe.badgeMarks),
                isSettingsOpen: $showsSettings
            ) {
                MyPostsTile(store: newestPosts) { wall = PostWallStore(source: myPosts) }
            }
            .navigationRoot()
            .navigationDestination(isPresented: $showsSchedule) {
                ScheduleView(model: schedule)
                    .environment(\.sceneTheme, today.scene)
                    // Its buttons keep the scene's colour, as its poster does; 我's own are brand.
                    .accentTone(.scene)
            }
            .navigationDestination(isPresented: showsShop) {
                if let shop = wardrobe.shop {
                    ShoppingStreetPage(model: shop)
                        // A piece tried on: the editor over the street, so back returns to it.
                        .navigationDestination(isPresented: showsEditor(overShop: true)) { profileEditor }
                }
            }
            .navigationDestination(isPresented: showsEditor(overShop: false)) { profileEditor }
            .navigationDestination(isPresented: showsWall) {
                if let wall {
                    PostWallView(
                        store: wall,
                        open: {
                            post = OpenedPost(id: $0.id, model: postPage($0.id, over: wall))
                            (profilePlace, profilePlacePost) = (nil, nil)
                        },
                        checkIn: { selection = .today }
                    )
                    .navigationDestination(item: $post) { opened in
                        PostDetailView(model: opened.model, post: opened.id) { post = nil }
                            .environment(\.sceneTheme, today.scene)
                            .navigationDestination(item: $profilePlace) { place in
                                profilePlacePage(place, over: wall)
                            }
                    }
                }
            }
            // A post from 训练记录 is pushed straight over 我.
            .navigationDestination(item: recordPost) { opened in
                PostDetailView(model: opened.model, post: opened.id) { post = nil }
                    .environment(\.sceneTheme, today.scene)
                    .navigationDestination(item: $profilePlace) { place in
                        profilePlacePage(place, over: nil)
                    }
            }
        }
        .onChange(of: post?.id) { _, id in if id == nil { Task { await profile.reload() } } }
        // The place popped: a post that was over it goes too, so it never comes back with the next place.
        .onChange(of: profilePlace) { _, place in if place == nil { profilePlacePost = nil } }
        // 商店街 follows what 我 reads, made again only while it is closed so an open one keeps its place.
        .task(id: wardrobe.key) { wardrobe.refresh() }
        .accentTone(.brand)
    }

    /// 我的动态 is pushed; the system's back closes it.
    private var showsWall: Binding<Bool> {
        Binding(
            get: { wall != nil },
            set: {
                guard !$0 else { return }
                (wall, post, profilePlace, profilePlacePost) = (nil, nil, nil, nil)
            })
    }

    /// A place opened on 我, with a tile's post pushed over it on 我's own stack, so back returns to
    /// the place; a post from 我的动态's place still tells the wall what changed.
    private func profilePlacePage(_ place: Place, over wall: PostWallStore?) -> some View {
        placePage(place) { id in
            profilePlacePost = OpenedPost(id: id, model: wall.map { postPage(id, over: $0) } ?? feed.page(of: id))
        }
        .navigationDestination(item: $profilePlacePost) { opened in
            PostDetailView(model: opened.model, post: opened.id) { profilePlacePost = nil }
                .environment(\.sceneTheme, today.scene)
        }
    }

    /// 商店街 is pushed; the system's back closes it.
    private var showsShop: Binding<Bool> {
        Binding(
            get: { wardrobe.showsShop && wardrobe.shop != nil },
            set: { if !$0 { wardrobe.showsShop = false } })
    }

    /// A post opened from 训练记录, over 我 while 我的动态 isn't open; the system's back closes it.
    private var recordPost: Binding<OpenedPost?> {
        Binding(get: { wall == nil ? post : nil }, set: { if $0 == nil { post = nil } })
    }
}
