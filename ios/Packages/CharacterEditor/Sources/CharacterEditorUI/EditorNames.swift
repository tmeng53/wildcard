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

    static func species(_ id: String) -> Text {
        guard let key = species[id] else { return Text(verbatim: id) }
        return Text(LocalizedStringKey(key), bundle: .module)
    }

    /// A variant's name. Face parts share folder names across slots (`round` eyes and `round`
    /// glasses), so they are looked up as `slot/variant` first.
    static func variant(_ variant: String, in slot: Slot) -> Text {
        guard let key = variants["\(slot.rawValue)/\(variant)"] ?? variants[variant] else {
            return Text(verbatim: variant)
        }
        return Text(LocalizedStringKey(key), bundle: .module)
    }

    /// The tile that takes a piece off: 不戴 for a hat or glasses, 没有 for brows or cheeks,
    /// 不拿 for a prop.
    static func nothing(in slot: Slot) -> Text {
        switch slot.rawValue {
        case "prop": Text("nothing.prop", bundle: .module)
        case "glasses": Text("nothing.glasses", bundle: .module)
        case "brows": Text("nothing.brows", bundle: .module)
        case "cheeks": Text("nothing.cheeks", bundle: .module)
        default: Text("nothing.hat", bundle: .module)
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
        "cap": "棒球帽", "headband": "发带", "hoodie": "卫衣", "jersey": "球衣", "tank": "背心", "tee": "T恤",
        "greenshorts": "运动短裤", "leggings": "紧身裤", "shorts": "短裤", "dumbbell": "哑铃", "racket": "网球拍",
        // Shoes
        "sneaker": "小白鞋", "runner": "跑鞋", "climbing": "攀岩鞋",
        // Faces
        "eyes/dot": "豆豆眼", "eyes/happy": "笑眼", "eyes/round": "圆眼", "eyes/sharp": "丹凤眼",
        "eyes/sleepy": "困困眼", "eyes/sparkle": "星星眼", "brows/arched": "挑眉", "brows/bold": "浓眉",
        "brows/soft": "淡眉", "brows/worried": "八字眉", "mouth/cat": "猫猫嘴", "mouth/grin": "咧嘴笑",
        "mouth/oh": "哦", "mouth/smile": "微笑", "mouth/smirk": "坏笑", "cheeks/flushed": "红脸蛋",
        "cheeks/freckles": "雀斑", "cheeks/rosy": "腮红", "glasses/round": "圆框", "glasses/square": "方框",
    ]
}
#endif
