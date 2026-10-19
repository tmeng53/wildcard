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

    static func variant(_ variant: String) -> Text {
        guard let key = variants[variant] else { return Text(verbatim: variant) }
        return Text(LocalizedStringKey(key), bundle: .module)
    }

    /// The tile that takes a piece off: 不戴 for a hat, 不拿 for a prop.
    static func nothing(in slot: Slot) -> Text {
        slot == "prop" ? Text("不拿", bundle: .module) : Text("不戴", bundle: .module)
    }

    private static let species = ["person": "人", "cat": "猫", "dog": "狗", "rabbit": "兔子", "bear": "熊"]

    private static let variants = [
        // Bodies
        "peach": "人", "tan": "人", "cat": "猫", "tuxedo": "奶牛猫", "calico": "三花", "tortie": "玳瑁",
        "orangewhite": "橘猫", "lihua": "狸花", "siamese": "暹罗", "ragdoll": "布偶", "shiba": "柴犬", "golden": "金毛",
        "corgi": "柯基", "husky": "哈士奇", "collie": "边牧", "bichon": "比熊", "rabbit": "兔子", "lop": "垂耳兔",
        "dutch": "荷兰兔", "bear": "熊",
        // Hair
        "bob": "波波头", "bun": "丸子头", "buzz": "寸头", "curls": "卷发", "curtain": "中分", "long": "长发",
        "pigtails": "双马尾", "ponytail": "马尾", "spacebuns": "双丸子", "wolf": "狼尾",
        // Hats, clothes and props
        "cap": "棒球帽", "headband": "发带", "hoodie": "卫衣", "jersey": "球衣", "tank": "背心", "tee": "T恤",
        "greenshorts": "运动短裤", "leggings": "紧身裤", "shorts": "短裤", "dumbbell": "哑铃", "racket": "网球拍",
        "basketball": "篮球",
    ]
}
#endif
