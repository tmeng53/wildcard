import Contracts
import FeedDomain
import Foundation

extension InMemoryFeedSource {
    /// The squad the 动态 screen is reviewed against, on `now`'s day in `zone`: today a run with
    /// a photo and emoji, a 请假条 and a salad; yesterday a swim and my own leg day;
    /// two days ago a tennis serve and a confessed burger. `photos` are the sample photos by
    /// `samplePhotoNames`; without them the photos' places stay grey.
    public static func sample(
        viewer: MemberID, squad: SquadID, now: Date, zone: TimeZone, photos: [String: Data] = [:]
    ) -> InMemoryFeedSource {
        let jay = MemberID(UUID()), coco = MemberID(UUID()), mia = MemberID(UUID()), doudou = MemberID(UUID())
        let fish = MemberID(UUID()), kiki = MemberID(UUID())
        guard let audience = try? Audience([squad]) else {
            return InMemoryFeedSource(viewer: viewer, posts: [], characters: [:])
        }
        let write = SamplePosts(today: LocalDay(at: now, in: zone), zone: zone, audience: audience)
        var posts = [
            write.post(
                jay, 0, 7, 42, .trained(write.training("run", minutes: 45, "track", "下雨也跑了，鞋已阵亡")),
                reactions: [(coco, "💪"), (mia, "😂"), (doudou, "💪")]),
            write.post(mia, 0, 12, 30, .healthyMeal(write.meal("salad", "今天的草，吃得很体面")), reactions: [(coco, "❤️")]),
            write.post(
                doudou, 1, 21, 5, .trained(write.training("swim", minutes: 40, "pool", "夜泳人，泳池是我的")),
                reactions: [(jay, "🔥"), (mia, "😮")]),
            write.post(
                viewer, 1, 19, 20, .trained(write.training("strength", minutes: 60, "gym", "练腿日，明天下楼梯靠扶手")),
                reactions: [(jay, "😂"), (coco, "💪"), (mia, "😂"), (doudou, "🤣")]),
            write.post(fish, 2, 18, 10, .trained(write.training("tennis", "tennis", "发球终于过网了"))),
            write.post(
                kiki, 2, 20, 45, .cheatMeal(write.meal("burger", "坦白：两个汉堡，不后悔")),
                reactions: [(jay, "🤤"), (fish, "🤤")]),
        ]
        if let note = try? Disclaimer(localized("腿说今天它请假，我尊重它的决定")) {
            posts.append(
                write.post(
                    coco, 0, 7, 10, .disclaimer(note), reactions: [(jay, "😂"), (mia, "🥹"), (doudou, "🫂")]))
        }
        let characters = sampleCharacters([
            "阿杰": jay, "Coco": coco, "Mia": mia, "豆豆": doudou, "小鱼": fish, "Kiki": kiki, "Momo": viewer,
        ])
        let byPath = Dictionary(uniqueKeysWithValues: photos.map { ("\(photoFolder)/\($0.key)", $0.value) })
        return InMemoryFeedSource(viewer: viewer, posts: posts, characters: characters, photos: byPath)
    }

    /// The sample squad's characters, by nickname: who they are and how they look.
    private static func sampleCharacters(_ members: [String: MemberID]) -> [MemberID: MemberCharacter] {
        let looks: [String: CharacterLook] = [
            "阿杰": CharacterLook(
                persona: "energetic", variants: ["body": "peach", "hair": "curls", "top": "tee", "bottom": "shorts"],
                colors: ["body": "#C68A5E"]),
            "Coco": CharacterLook(persona: "drama", variants: ["body": "lop", "top": "hoodie", "bottom": "leggings"]),
            "Mia": CharacterLook(
                persona: "deadpan", variants: ["body": "calico", "top": "tee", "bottom": "greenshorts"]),
            "豆豆": CharacterLook(
                persona: "energetic", variants: ["body": "shiba", "top": "jersey", "bottom": "shorts"]),
            "小鱼": CharacterLook(
                persona: "shy", variants: ["body": "peach", "hair": "ponytail", "top": "tee", "bottom": "leggings"]),
            "Kiki": CharacterLook(
                persona: "showoff",
                variants: ["body": "peach", "hair": "bob", "glasses": "round", "top": "hoodie", "bottom": "shorts"]),
            "Momo": CharacterLook(
                persona: "energetic", variants: ["body": "peach", "hair": "long", "top": "tank", "bottom": "shorts"]),
        ]
        var characters: [MemberID: MemberCharacter] = [:]
        for (nickname, member) in members {
            guard let look = looks[nickname], let name = try? Nickname(nickname) else { continue }
            characters[member] = MemberCharacter(nickname: name, look: look)
        }
        return characters
    }

    /// Where the sample posts' photos are, as a member's folder in Storage.
    fileprivate static let photoFolder = "sample"

    /// The sample photos `sample` refers to, by name.
    public static let samplePhotoNames = ["track", "salad", "pool", "gym", "tennis", "burger"]

    fileprivate static func localized(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }
}

/// Writes the sample's posts on days counted back from `today`, at times on the member's clock;
/// teammates react ten minutes apart after each post.
private struct SamplePosts {
    let today: LocalDay
    let zone: TimeZone
    let audience: Audience

    func training(_ sport: Sport, minutes: Int? = nil, _ photo: String, _ caption: String) -> Training {
        Training(
            activity: .sport(sport), minutes: minutes.flatMap { try? WorkoutMinutes($0) }, photos: photos(photo),
            caption: line(caption))
    }

    func meal(_ photo: String, _ caption: String) -> Meal {
        Meal(photos: photos(photo), caption: line(caption))
    }

    func post(
        _ author: MemberID, _ daysAgo: Int, _ hour: Int, _ minute: Int, _ entry: CheckIn.Entry,
        reactions: [(MemberID, String)] = []
    ) -> FeedPost {
        let day = today.adding(days: -daysAgo)
        let made = time(on: day, hour, minute)
        func after(_ index: Int) -> Timestamp { Timestamp(made.addingTimeInterval(Double(index + 1) * 600)) }
        return FeedPost(
            checkIn: CheckIn(
                id: CheckInID(UUID()), member: author, day: day, createdAt: Timestamp(made), audience: audience,
                entry: entry),
            reactions: Responses(
                reactions.enumerated().compactMap { index, pair in
                    (try? Emoji(pair.1)).map { .init(member: pair.0, kind: $0, moment: after(index)) }
                }))
    }

    private func time(on day: LocalDay, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)
        return calendar.date(from: components) ?? .distantPast
    }

    private func photos(_ name: String) -> Photos? {
        (try? PhotoRef(path: "\(InMemoryFeedSource.photoFolder)/\(name)")).flatMap { try? Photos([$0]) }
    }

    private func line(_ key: String) -> Caption? {
        try? Caption(InMemoryFeedSource.localized(key))
    }
}
