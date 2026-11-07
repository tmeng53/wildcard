#if os(iOS)
import DesignSystem
import DesignSystemUI
import HealthDomain
import SwiftUI
import UIKit

/// 设置 › Apple 健康 (Tracy, 2026-11-06): 连接 until it is connected, then which numbers a post
/// from Health carries unless struck (时长 always), the line on striking and the route's trimmed
/// ends, and where iOS keeps the reading permission. Ink and white only, like the rest of 设置.
public struct HealthSettingsView: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Bindable private var health: HealthConnection
    @State private var isConnecting = false

    /// Pushed over 设置 on its NavigationStack, so going back is the system's.
    public init(health: HealthConnection) {
        self.health = health
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(copy: "Apple 健康", bundle: .module)
                    .typeStyle(TypeRamp.largeTitle)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityAddTraits(.isHeader)
                connection
                if health.isConnected { sharing }
                permissions
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
        .barTitleOnScroll(Text(copy: "Apple 健康", bundle: .module))
        .background(Color(role: .bgCanvas, in: theme))
        .pushedPage()
        .task { await health.refresh() }
        .accessibilityIdentifier("health.page")
    }

    private var connection: some View {
        VStack(spacing: 0) {
            if health.isConnected {
                ListRow(
                    Text(copy: "Apple 健康", bundle: .module), value: Text(copy: "已连接", bundle: .module),
                    showsDivider: false
                ) {}
                .disabled(true)
                .accessibilityIdentifier("health.connected")
            } else {
                ListRow(Text(copy: "连接 Apple 健康", bundle: .module), showsDivider: false) {
                    guard !isConnecting else { return }
                    isConnecting = true
                    Task {
                        await health.connect()
                        isConnecting = false
                    }
                }
                .accessibilityIdentifier("health.connect")
            }
        }
        .padding(.top, Space.l)
    }

    private var sharing: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            SectionLabel(Text(copy: "发到小队时默认带上", bundle: .module))
            VStack(spacing: 0) {
                ListRow(
                    Text(copy: "时长", bundle: .module), value: Text(copy: "总是带", bundle: .module), showsChevron: false
                ) {}
                .disabled(true)
                SwitchRow(Text(copy: "距离", bundle: .module), isOn: $health.sharing.distance)
                    .accessibilityIdentifier("health.share.distance")
                SwitchRow(Text(copy: "配速 / 均速", bundle: .module), isOn: $health.sharing.pace)
                    .accessibilityIdentifier("health.share.pace")
                SwitchRow(Text(copy: "心率", bundle: .module), isOn: $health.sharing.heartRate)
                    .accessibilityIdentifier("health.share.heartRate")
                SwitchRow(Text(copy: "费力", bundle: .module), isOn: $health.sharing.effort)
                    .accessibilityIdentifier("health.share.effort")
                SwitchRow(Text(copy: "趟数", bundle: .module), isOn: $health.sharing.laps)
                    .accessibilityIdentifier("health.share.laps")
                SwitchRow(Text(copy: "路线地图", bundle: .module), isOn: $health.sharing.route, showsDivider: false)
                    .accessibilityIdentifier("health.share.route")
            }
            Text(copy: "每次发的时候还可以在成绩条上点掉。路线会自动去掉起点和终点各 200 米。", bundle: .module)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xs)
        }
        .padding(.top, Space.l)
    }

    /// Health never says whether reading was allowed, so the way to change it is always here.
    private var permissions: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            ListRow(Text(copy: "在 iOS 设置里管理读取权限", bundle: .module), showsDivider: false) {
                if let settings = URL(string: UIApplication.openSettingsURLString) { openURL(settings) }
            }
            .accessibilityIdentifier("health.permissions")
            Text(copy: "没看到运动？在 设置 › 健康 › 数据访问与设备 › 外卡 里打开读取。", bundle: .module)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.l)
    }
}
#endif
