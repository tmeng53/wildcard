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
        case .look: Text("样子", bundle: .module)
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
        case "cheeks": Text("脸蛋什么都不加", bundle: .module)
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
        "dumbbell": "哑铃", "racket": "网球拍",
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
