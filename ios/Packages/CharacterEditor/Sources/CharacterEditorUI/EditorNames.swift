#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import SwiftUI

/// Display names for what the editor offers. The art names variants by folder (`bob`,
/// `tuxedo`); people see these, from the String Catalog. A variant added to the art without a
/// name here shows its folder name until one is added.
enum EditorNames {
    static func tab(_ tab: EditorTab) -> Text {
        switch tab {
        case .look: Text("长相", bundle: .module)
        case .hair: Text("发型", bundle: .module)
        case .face: Text("脸", bundle: .module)
        case .outfit: Text("穿搭", bundle: .module)
        case .prop: Text("道具", bundle: .module)
        case .persona: Text("性格", bundle: .module)
        }
    }

    static func persona(_ persona: Persona) -> Text {
        switch persona {
        case .deadpan: Text("淡人", bundle: .module)
        case .energetic: Text("高能量", bundle: .module)
        case .showoff: Text("显眼包", bundle: .module)
        case .drama: Text("戏精", bundle: .module)
        case .shy: Text("社恐", bundle: .module)
        }
    }

    static func species(_ id: String) -> Text {
        guard let key = species[id] else { return Text(verbatim: id) }
        return Text(LocalizedStringKey(key), bundle: .module)
    }

    /// A face part's name goes by its slot too, since a mouth and a body are both `cat`.
    static func variant(_ variant: String, in slot: Slot) -> Text {
        guard let key = faces["\(slot)/\(variant)"] ?? variants[variant] else { return Text(verbatim: variant) }
        return Text(LocalizedStringKey(key), bundle: .module)
    }

    /// The tile that takes a piece off, for VoiceOver: 不戴 for a hat, 不拿 for a prop.
    static func nothing(in slot: Slot) -> Text {
        switch slot.rawValue {
        case "prop": Text("不拿", bundle: .module)
        case "glasses": Text("不戴眼镜", bundle: .module)
        case "brows": Text("没有眉毛", bundle: .module)
        case "cheeks": Text("不加", bundle: .module)
        default: Text("不戴", bundle: .module)
        }
    }

    private static let species = ["person": "人", "cat": "猫", "dog": "狗", "rabbit": "兔子", "bear": "熊"]

    private static let variants = [
        // Bodies
        "peach": "人", "cat": "猫", "tuxedo": "奶牛猫", "calico": "三花", "tortie": "玳瑁",
        "orangewhite": "橘猫", "lihua": "狸花", "siamese": "暹罗", "ragdoll": "布偶", "shiba": "柴犬", "golden": "金毛",
        "corgi": "柯基", "husky": "哈士奇", "collie": "边牧", "bichon": "比熊", "rabbit": "兔子", "lop": "垂耳兔",
        "dutch": "荷兰兔", "bear": "熊",
        // Hair
        "bob": "波波头", "bun": "丸子头", "buzz": "寸头", "curls": "卷发", "curtain": "中分", "long": "长发",
        "pigtails": "双马尾", "ponytail": "马尾", "spacebuns": "双丸子", "wolf": "狼尾",
        // Hats, clothes and props
        "warmup-tee": "圆领短袖 T", "warmup-tank": "运动背心", "warmup-hoodie": "连帽卫衣", "warmup-shorts": "抽绳运动短裤",
        "warmup-joggers": "束脚卫裤", "warmup-leggings": "基础紧身裤", "warmup-canvas": "帆布鞋", "warmup-runner": "基础跑鞋",
        "warmup-cap": "棒球帽", "warmup-headband": "飘带发带", "warmup-towel": "挂脖毛巾", "warmup-waistbag": "运动腰包",
        "lap-jacket": "复古拉链外套", "lap-pants": "双条纹长裤", "lap-runner": "焦糖底跑鞋", "nolook-jersey": "无袖网眼球衣",
        "nolook-shorts": "过膝篮球短裤", "nolook-hightop": "高帮绑带球鞋", "nolook-backcap": "反戴棒球帽", "moss-anorak": "半拉链冲锋衣",
        "moss-cargo": "工装短裤", "moss-trail": "锯齿底越野鞋", "moss-bucket": "渔夫帽", "moss-sling": "斜挎小包",
        "halfmoon-tank": "细罗纹美背背心", "halfmoon-flare": "高腰喇叭瑜伽裤", "halfmoon-studio": "软底训练鞋", "halfmoon-tied": "腰间系的外套",
        "deuce-polo": "俱乐部 polo 衫", "deuce-skirt": "百褶网球裙", "deuce-shorts": "白色球场短裤", "deuce-court": "硬地网球鞋",
        "deuce-visor": "空顶遮阳帽", "lap-singlet": "竞速背心", "lap-wind": "撞色复古风衣", "lap-split": "开衩竞速短裤",
        "lap-spikes": "短跑钉鞋", "lap-runcap": "软檐跑步帽", "lap-bib": "号码布 09", "lap-vest": "越野水袋背心",
        "nolook-shooter": "投篮热身长袖", "nolook-tee": "落肩大 T", "nolook-mesh": "网眼训练背心", "nolook-snap": "侧扣热身裤",
        "nolook-slides": "拖鞋配长袜", "nolook-headband": "毛巾宽头带", "moss-fleece": "摇粒绒半拉链", "moss-puffer": "蜂蜜黄羽绒马甲",
        "moss-flannel": "橄榄格子衬衫", "moss-climb": "攀岩卷边裤", "moss-boots": "高帮徒步靴", "moss-sahara": "护颈遮阳帽",
        "halfmoon-wrap": "芭蕾裹身长袖", "halfmoon-zip": "修身拉链外套", "halfmoon-biker": "高腰骑行短裤", "halfmoon-wide": "阔腿运动裤",
        "halfmoon-grip": "防滑瑜伽袜", "halfmoon-clip": "玳瑁鲨鱼夹", "halfmoon-tote": "瑜伽垫托特包", "deuce-cable": "绞花毛衣背心",
        "deuce-dress": "网球连衣裙", "deuce-pants": "俱乐部热身长裤", "deuce-socks": "条纹高筒袜球鞋", "deuce-terry": "复古毛巾头带",
        "deuce-sweater": "肩上搭的毛衣", "warmup-long": "基础长袖 T", "warmup-raglan": "插肩棒球 T", "warmup-stripe": "海魂条纹 T",
        "warmup-overalls": "工装背带裤", "warmup-hightop": "高帮帆布鞋", "warmup-beanie": "毛球针织帽", "warmup-headphones": "头戴耳机",
        "lap-baguette": "法棍发带", "nolook-ball": "篮球毛线帽", "moss-mushroom": "蘑菇渔夫帽", "halfmoon-mintchip": "薄荷巧克力背心",
        "deuce-ball": "网球毛线帽",
        "dumbbell": "哑铃", "bottle": "外卡水杯",
        "kettlebell": "壶铃", "yogamat": "瑜伽垫", "racket": "网球拍", "pickleball": "匹克球拍", "badminton": "羽毛球拍",
        "pingpong": "乒乓球拍", "chalkbag": "镁粉袋", "goggles": "泳镜",
    ]

    private static let faces = [
        "eyes/dot": "豆豆眼", "eyes/happy": "笑眼", "eyes/round": "圆眼", "eyes/sharp": "丹凤眼", "eyes/sleepy": "困困眼",
        "eyes/sparkle": "星星眼", "brows/arched": "挑眉", "brows/bold": "浓眉", "brows/soft": "淡眉",
        "brows/worried": "八字眉", "mouth/cat": "猫猫嘴", "mouth/grin": "咧嘴笑", "mouth/oh": "哦", "mouth/smile": "微笑",
        "mouth/smirk": "坏笑", "cheeks/flushed": "红脸蛋", "cheeks/freckles": "雀斑", "cheeks/rosy": "腮红",
        "glasses/round": "圆框", "glasses/square": "方框",
    ]
}
#endif
