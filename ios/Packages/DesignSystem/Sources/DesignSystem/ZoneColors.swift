/// The colours of a chart read by heart-rate zone (Tracy, 2026-11-08): the brand's graphite under
/// it, whatever the sport, since the zones' four colours can't all show on every sport's own
/// colour, with white words on it. Each zone takes a sport category's colour lightened toward
/// white (45%, 35%, 20% and 10%) so it reads on the graphite: 轻松 the water sports' blue, 适中 the ball sports' green,
/// 剧烈 cardio's orange and 峰值 running's red.
public enum ZoneColors {
    /// Under the chart.
    public static let fill = Palette.brand
    /// Words, numbers and a curve without zones; below 轻松 the chart dims it, outside every zone.
    public static let ink = Palette.white

    /// Zone `index` (0 轻松 to 3 峰值); the last one for any higher.
    public static func zone(_ index: Int) -> SRGBColor {
        tones[min(max(index, 0), tones.count - 1)]
    }

    static let tones = [
        SRGBColor(red: 0x77, green: 0xC8, blue: 0xD8),
        SRGBColor(red: 0x6D, green: 0xB3, blue: 0x94),
        SRGBColor(red: 0xD3, green: 0x86, blue: 0x49),
        SRGBColor(red: 0xE8, green: 0x64, blue: 0x58),
    ]
}
