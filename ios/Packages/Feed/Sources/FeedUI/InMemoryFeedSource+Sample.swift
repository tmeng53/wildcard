import Contracts
import DesignSystemUI
import FeedDomain
import Foundation

extension InMemoryFeedSource {
    /// The squad the 动态 screen is reviewed against, on `now`'s day in `zone`: today a run with
    /// two photos and its route from Apple Health, emoji and three comments, a 请假条, a salad and
    /// a run from Health with only its map; yesterday a swim with its laps and my own leg day;
    /// two days ago a tennis serve without a photo and a confessed burger; and my own run this morning,
    /// shared to no squad, which only 我的动态 shows. `photos` are the sample photos by
    /// their names in `samplePhotoSizes`; without them the photos' places stay grey. With `coach`,
    /// 毛头 coaches the squad: today's 战术板 line, a word and 🔥 on the run, 🫡 on the 请假条 and
    /// a word on the swim.
    public static func sample(
        viewer: MemberID, squad: SquadID, now: Date, zone: TimeZone, photos: [String: Data] = [:],
        coach: Bool = false
    ) -> InMemoryFeedSource {
        let jay = MemberID(UUID()), coco = MemberID(UUID()), mia = MemberID(UUID()), doudou = MemberID(UUID())
        let fish = MemberID(UUID()), kiki = MemberID(UUID())
        guard let audience = try? Audience([squad]) else {
            return InMemoryFeedSource(viewer: viewer, posts: [], characters: [:])
        }
        let write = SamplePosts(today: LocalDay(at: now, in: zone), zone: zone, audience: audience)
        var posts = [
            write.post(
                jay, 0, 7, 42,
                write.fromHealth(
                    "run", ["track", "tennis"], "下雨也跑了，鞋已阵亡", tile: 3,
                    WorkoutSummary(durationSec: 2700, distanceM: 7400, paceSecPerKm: 365, avgHr: 151)),
                reactions: [(coco, "💪"), (mia, "😂"), (doudou, "💪")],
                comments: [(coco, nil, "鞋：我没签这个合同"), (jay, coco, "它会习惯的"), (mia, nil, "下次带我一起淋")]),
            write.post(mia, 0, 12, 30, write.taggedSalad, reactions: [(coco, "❤️")]),
            write.post(
                kiki, 0, 6, 48,
                write.fromHealth(
                    "run", [], "河边风好大", tile: 1,
                    WorkoutSummary(durationSec: 2460, distanceM: 7000, paceSecPerKm: 351, avgHr: 152))),
            write.post(
                doudou, 1, 21, 5,
                write.fromHealth(
                    "swim", ["pool"], "夜泳人，泳池是我的", tile: 2,
                    WorkoutSummary(durationSec: 2400, distanceM: 1200, avgHr: 139, laps: 24, poolLengthM: 50)),
                reactions: [(jay, "🔥"), (mia, "😮")]),
            write.post(
                viewer, 1, 19, 20,
                write.fromHealth(
                    "strength", ["gym"], "练腿日，明天下楼梯靠扶手", tile: 2,
                    WorkoutSummary(durationSec: 3600, avgHr: 128, maxHr: 156, activeEnergyKcal: 420)),
                reactions: [(jay, "😂"), (coco, "💪"), (mia, "😂"), (doudou, "🤣")],
                comments: [(jay, nil, "扶手：今天也是被需要的一天")]),
            write.post(fish, 2, 18, 10, .trained(write.training("tennis", minutes: 50, [], "发球终于过网了"))),
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
        return InMemoryFeedSource(
            viewer: viewer, posts: posts + [write.runOnMyOwn(viewer)], characters: characters, photos: byPath,
            coach: coach ? sampleCoach(on: posts, now: now, mia: mia) : nil)
    }

    /// 毛头's line for today and its replies to the run (posts[0]),
    /// the swim (posts[3]), which @s Mia, and the 请假条 (the last).
    private static func sampleCoach(on posts: [FeedPost], now: Date, mia: MemberID) -> CoachActivity {
        let maotou = CoachSpeaker(id: "xiaohun", name: localized("毛头"))
        let note = CoachNote(
            day: LocalDay(at: now, in: SquadTimeZone.newYorkClock), text: localized("今天谁先动，谁就是队长"),
            coach: maotou, writtenAt: now.addingTimeInterval(-3600))
        func reply(_ post: FeedPost?, _ text: String?, _ emoji: String?, mentioning: [MemberID] = []) -> CoachReply? {
            guard let post else { return nil }
            return CoachReply(
                checkIn: post.id, coach: maotou, text: text, emoji: emoji.flatMap { try? Emoji($0) },
                mentions: mentioning,
                writtenAt: post.checkIn.createdAt.date.addingTimeInterval(120))
        }
        let replies = [
            reply(posts.first, localized("下雨还跑，鞋的牺牲我记下了"), "🔥"),
            reply(posts.count > 3 ? posts[3] : nil, "@Mia " + localized("夜泳人，记一笔"), nil, mentioning: [mia]),
            reply(posts.last, nil, "🫡"),
        ]
        return CoachActivity(note: note, replies: replies.compactMap(\.self))
    }

    /// The sample squad's characters, by nickname: who they are and how they look.
    private static func sampleCharacters(_ members: [String: MemberID]) -> [MemberID: MemberCharacter] {
        let looks: [String: CharacterLook] = [
            "阿杰": CharacterLook(
                persona: "energetic",
                variants: ["body": "peach", "hair": "curls", "top": "warmup-tee", "bottom": "warmup-shorts"],
                colors: ["body": "#C68A5E"]),
            "Coco": CharacterLook(
                persona: "drama",
                variants: ["body": "lop", "top": "warmup-hoodie", "bottom": "warmup-leggings"]),
            "Mia": CharacterLook(
                persona: "deadpan",
                variants: ["body": "calico", "cheeks": "rosy", "top": "warmup-tee", "bottom": "moss-cargo"]),
            "豆豆": CharacterLook(
                persona: "energetic",
                variants: ["body": "shiba", "cheeks": "rosy", "top": "nolook-jersey", "bottom": "warmup-shorts"]),
            "小鱼": CharacterLook(
                persona: "shy",
                variants: ["body": "peach", "hair": "ponytail", "top": "warmup-tee", "bottom": "warmup-leggings"]),
            "Kiki": CharacterLook(
                persona: "showoff",
                variants: [
                    "body": "peach", "hair": "bob", "glasses": "round", "top": "warmup-hoodie",
                    "bottom": "warmup-shorts",
                ]),
            "Momo": CharacterLook(
                persona: "energetic",
                variants: ["body": "peach", "hair": "long", "top": "warmup-tank", "bottom": "warmup-shorts"]),
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

    /// The sample photos `sample` refers to, by name, with their sizes in pixels: landscape
    /// venues, a portrait leg day (taller than 4:5, so the feed crops it), a portrait salad and
    /// a square burger.
    public static let samplePhotoSizes: [String: (width: Int, height: Int)] = [
        "track": (1080, 720), "pool": (1080, 720), "tennis": (1080, 720), "gym": (1080, 1440),
        "salad": (1080, 1350), "burger": (1080, 1080),
    ]

    static func localized(_ key: String) -> String {
        String(copyKey: key, bundle: Bundle.module)
    }
}

/// Writes the sample's posts on days counted back from `today`, at times on the member's clock;
/// teammates react, then comment, ten minutes apart after each post.
private struct SamplePosts {
    let today: LocalDay
    let zone: TimeZone
    let audience: Audience

    func training(
        _ sport: Sport, minutes: Int? = nil, _ photos: [String], _ caption: String, workout: Workout? = nil
    ) -> Training {
        Training(
            activity: .sport(sport), minutes: minutes.flatMap { try? WorkoutMinutes($0) }, photos: self.photos(photos),
            caption: line(caption), workout: workout)
    }

    /// A 训练 posted from Apple Health with its numbers, and its tile at `tile`: a swim's laps,
    /// the 17th the fastest, an hour of sets' heart rate indoors, or a loop through a park.
    func fromHealth(_ sport: Sport, _ photos: [String], _ caption: String, tile: Int, _ summary: WorkoutSummary)
        -> CheckIn.Entry
    {
        let minutes = (summary.durationSec ?? 0) / 60
        return .trained(
            training(
                sport, minutes: minutes, photos, caption,
                workout: workout(sport.rawValue, minutes: minutes, tile: tile, summary)))
    }

    private func workout(_ sport: String, minutes: Int, tile: Int, _ summary: WorkoutSummary) -> Workout {
        let ended = time(on: today, 7, 0)
        let source = WorkoutSource(provider: WorkoutSource.appleHealth, id: "sample-\(sport)-\(minutes)")
        let start = Timestamp(ended.addingTimeInterval(-Double(minutes) * 60))
        if sport == "swim" {
            let laps: [Double] = (0..<24).map { (lap: Int) -> Double in
                guard lap != 16 else { return 44 }
                let spread: Int = (lap * 7) % 9
                return 50 + Double(spread)
            }
            return Workout(
                source: source, startedAt: start, endedAt: Timestamp(ended), summary: summary,
                series: WorkoutSeries(laps: laps), tilePosition: tile)
        }
        if sport == "strength" {
            // No route indoors: the heart rate through the hour, sets and rests, with a warm-up
            // and a cool-down under the zones of a 32-year-old resting at 62.
            let beats = (0...60).map { (minute: Int) -> HeartRatePoint in
                let easy = minute < 6 || minute > 55
                return HeartRatePoint(
                    seconds: Double(minute) * 60, bpm: easy ? 86 + minute % 6 : 110 + (minute * 13) % 46)
            }
            return Workout(
                source: source, startedAt: start, endedAt: Timestamp(ended), summary: summary,
                series: WorkoutSeries(heartRate: beats, zones: HeartRateZones(age: 32, restingBpm: 62)),
                tilePosition: tile)
        }
        let route: [RoutePoint] = (0...80).map { (step: Int) -> RoutePoint in
            let turn: Double = Double(step) / 80 * 1.7 * Double.pi
            let angle: Double = turn + Double(minutes) * 0.1
            let lat: Double = 40.7812 + 0.006 * sin(angle)
            let lon: Double = -73.9665 + 0.009 * cos(angle)
            return RoutePoint(lat: lat, lon: lon)
        }
        return Workout(
            source: source, startedAt: start, endedAt: Timestamp(ended), summary: summary, route: route,
            tilePosition: tile)
    }

    func training(_ sport: Sport, minutes: Int? = nil, _ photo: String, _ caption: String) -> Training {
        training(sport, minutes: minutes, [photo], caption)
    }

    /// My run this morning, only recorded (发布到动态 off): only 我的动态 shows it, saying 未发动态.
    func runOnMyOwn(_ viewer: MemberID) -> FeedPost {
        post(viewer, 0, 6, 30, .trained(training("run", minutes: 30, [], "早上自己慢跑一圈")), inFeed: false)
    }

    func meal(
        _ photo: String, _ caption: String, at place: Place? = nil, healthy: Int? = nil, tasty: Int? = nil
    ) -> Meal {
        let rating = healthy.flatMap { healthy in tasty.flatMap { try? MealRating(healthy: healthy, tasty: $0) } }
        return Meal(photos: photos([photo]), caption: line(caption), place: place, rating: rating)
    }

    /// Mia's salad, tagged with the restaurant it came from and rated, as 动态 shows a place and
    /// a meal's 成绩条.
    var taggedSalad: CheckIn.Entry {
        let place = try? Place(name: "Sweetgreen", category: "restaurant", latitude: 40.7448, longitude: -73.9881)
        return .healthyMeal(meal("salad", "今天的草，吃得很体面", at: place, healthy: 5, tasty: 4))
    }

    func post(
        _ author: MemberID, _ daysAgo: Int, _ hour: Int, _ minute: Int, _ entry: CheckIn.Entry,
        reactions: [(MemberID, String)] = [],
        comments: [(MemberID, MemberID?, String)] = [], inFeed: Bool = true
    ) -> FeedPost {
        let day = today.adding(days: -daysAgo)
        let made = time(on: day, hour, minute)
        func after(_ index: Int) -> Timestamp { Timestamp(made.addingTimeInterval(Double(index + 1) * 600)) }
        return FeedPost(
            checkIn: CheckIn(
                id: CheckInID(UUID()), member: author, day: day, createdAt: Timestamp(made),
                audience: audience, inFeed: inFeed,
                entry: entry),
            reactions: Responses(
                reactions.enumerated().compactMap { index, pair in
                    (try? Emoji(pair.1)).map { .init(member: pair.0, kind: $0, moment: after(index)) }
                }),
            comments: comments.enumerated().compactMap { index, comment in
                (try? CommentText(InMemoryFeedSource.localized(comment.2))).map {
                    Comment(
                        id: CommentID(UUID()), member: comment.0, text: $0, replyTo: comment.1.map(ReplyTarget.member),
                        commentedAt: after(reactions.count + index))
                }
            })
    }

    private func time(on day: LocalDay, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)
        return calendar.date(from: components) ?? .distantPast
    }

    private func photos(_ names: [String]) -> Photos? {
        let refs = names.compactMap { name in
            let size = InMemoryFeedSource.samplePhotoSizes[name].flatMap {
                try? PhotoSize(width: $0.width, height: $0.height)
            }
            return try? PhotoRef(path: "\(InMemoryFeedSource.photoFolder)/\(name)", size: size)
        }
        return try? Photos(refs)
    }

    private func line(_ key: String) -> Caption? {
        try? Caption(InMemoryFeedSource.localized(key))
    }
}
