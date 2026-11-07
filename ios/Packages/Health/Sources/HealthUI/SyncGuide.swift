#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI
import UIKit

/// A wearable whose own app writes its workouts into Apple Health, so the app reads them like
/// any other (Tracy, 2026-11-06: a guide, not a Fitbit, WHOOP or Oura connection of our own).
public enum Wearable: String, CaseIterable, Identifiable, Sendable {
    case fitbit, whoop, oura

    public var id: String { rawValue }

    /// Its name in the picker. Brand names, the same in every language.
    var name: String {
        switch self {
        case .fitbit: "Fitbit"
        case .whoop: "WHOOP"
        case .oura: "Oura"
        }
    }

    /// The app its steps happen in, which 打开 opens on the App Store: its page offers 打开 when
    /// it is installed, and asks no URL scheme of an app we don't own. Fitbit's app is Google
    /// Health since May 2026, on the same listing.
    var store: URL? {
        switch self {
        case .fitbit: URL(string: "https://apps.apple.com/app/id462638897")
        case .whoop: URL(string: "https://apps.apple.com/app/id933944389")
        case .oura: URL(string: "https://apps.apple.com/app/id1043837948")
        }
    }

    /// 打开 Google Health / 打开 WHOOP / 打开 Oura.
    var openTitle: Text {
        switch self {
        case .fitbit: Text("打开 Google Health", bundle: .module)
        case .whoop: Text("打开 WHOOP", bundle: .module)
        case .oura: Text("打开 Oura", bundle: .module)
        }
    }

    /// The steps in its app, then back here.
    var steps: [Text] {
        switch self {
        case .fitbit:
            [
                Text("打开 Google Health，点右上角头像", bundle: .module),
                Text("点「合作伙伴应用」", bundle: .module),
                Text("选 Apple 健康，点「全部打开」", bundle: .module),
            ]
        case .whoop:
            [
                Text("打开 WHOOP，点「更多」", bundle: .module),
                Text("App 设置 › 集成", bundle: .module),
                Text("选 Apple 健康，点「全部打开」", bundle: .module),
            ]
        case .oura:
            [
                Text("打开 Oura，点左上角菜单 › 设置", bundle: .module),
                Text("数据共享 › Apple 健康", bundle: .module),
                Text("打开「连接健康」，再全部允许", bundle: .module),
            ]
        }
    }

    /// Where step `number` (from 1)'s screenshot stands in the art tree's `guides/`. The
    /// pictures are data (put with the admin tools, the tap target already marked on them), so a
    /// menu that moves is fixed without a release; a step without one shows its words alone.
    public func screenshotPath(step number: Int) -> String { "\(rawValue)-\(number)@3x.png" }
}

/// Where the guide's screenshots come from: the app passes the art tree's `guides/` (downloaded
/// art; none is bundled), and anywhere else shows the steps' words alone.
public struct GuideScreenshots: Sendable {
    let find: @Sendable (String) -> URL?

    /// `find`: the file for a path under `guides/`, if the phone has one.
    public init(find: @escaping @Sendable (String) -> URL?) {
        self.find = find
    }

    public static let none = GuideScreenshots { _ in nil }
}

extension EnvironmentValues {
    @Entry public var guideScreenshots = GuideScreenshots.none
}

/// The text button that opens `SyncGuideSheet`: 用 Fitbit、WHOOP 或 Oura？ with a chevron, plain
/// on the page (Tracy, 2026-11-06: no box around a single line).
public struct SyncGuideLink: View {
    @Environment(\.sceneTheme) private var theme
    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xxs) {
                Text("用 Fitbit、WHOOP 或 Oura？", bundle: .module)
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .foregroundStyle(Color(role: .fgSubtle, in: theme))
            }
            .frame(minHeight: Sizing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("health.guide")
    }
}

/// 先同步到 Apple 健康: how a Fitbit, WHOOP or Oura wearer gets their workouts into Apple Health,
/// three steps each with its screenshot, and 打开 for that app. A system sheet with the system's
/// segmented control (native first).
public struct SyncGuideSheet: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.guideScreenshots) private var screenshots
    @State private var wearable: Wearable = .fitbit

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("先同步到 Apple 健康", bundle: .module)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.s)
                HeaderButton(Text("关闭", bundle: .module), systemImage: "xmark") { dismiss() }
                    .accessibilityIdentifier("health.guide.close")
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.m)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Picker(selection: $wearable) {
                        ForEach(Wearable.allCases) { Text(verbatim: $0.name).tag($0) }
                    } label: {
                        Text("设备", bundle: .module)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("health.guide.wearable")
                    ForEach(Array(wearable.steps.enumerated()), id: \.offset) { index, words in
                        GuideStep(
                            number: index + 1, words: words,
                            picture: screenshots.find(wearable.screenshotPath(step: index + 1)))
                    }
                }
                .padding(.horizontal, Space.pageMargin)
                .padding(.vertical, Space.m)
            }
            .scrollIndicators(.hidden)
        }
        .actionBar {
            Button {
                if let store = wearable.store { openURL(store) }
            } label: {
                wearable.openTitle.frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("health.guide.open")
        }
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Contain, so the sheet's own id doesn't replace its buttons' ids.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("health.guide.sheet")
    }
}

/// One step: its number in an ink circle, its words, and under them its screenshot when there is
/// one, at most 240 points wide so a whole phone screen fits beside the words' scale.
private struct GuideStep: View {
    @Environment(\.sceneTheme) private var theme
    let number: Int
    let words: Text
    let picture: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(number, format: .number)
                    .typeStyle(TypeRamp.scoreCaption)
                    .foregroundStyle(Color(role: .fgOnInk, in: theme))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color(role: .bgInk, in: theme)))
                    .accessibilityHidden(true)
                words
                    .typeStyle(TypeRamp.body)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let picture, let image = UIImage(contentsOfFile: picture.path(percentEncoded: false)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("health.guide.step.\(number)")
    }
}
#endif
