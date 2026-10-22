import SwiftUI

// MARK: - 設定頁「Apple Watch」段（手錶 v1，v25.574；只屬於主 App；watch/judge.md §2.16、§6.3、§6.5、§6.6；
//         watch/build/v1/brief.md G1-7）
//
// SettingsView 用 disclosureBlock 包它（跟「桌面小工具」同一組；沒配對手錶整段不出現）。
// 這一版的列：
//   • 加入別人的共享時：「這支 iPhone 加入了別人的共享，手錶會看到共享裡的行程」（judge §6.6）
//   • 狀態：「手錶版已安裝・上次送到手錶 09:24・6 KB」／「手錶版已安裝・還沒送過」／沒裝時怎麼裝
//   • 錢（還能花、接下來要繳）［開］：關掉＝iPhone 下一次送包就不放，手錶 ② 錢整頁消失
//   • 會議細節裡的部屬名字［開］：只在手錶 App 抬手看會議細節時；關著＝連送都不送。加入別人共享的 iPhone 沒設定過預設關
//   • 背景建立資料：N 次（給查問題用，judge §5.4）
// 手機條碼（v2）、旅行（v6）、智慧型堆疊（v7b）這一版不放。
// 改了開關：寫 App Group（WatchPhoneSettings 同一組鍵）→ bridge.settingsChanged() 重組重送。

struct WatchSettingsSection: View {
    @ObservedObject var bridge: WatchBridge

    /// 送到手錶：錢（WatchPhoneSettings.sendMoney 同一個鍵；沒設定過＝開）
    @AppStorage(WatchPhoneSettings.sendMoneyKey, store: WidgetShared.defaults) private var sendMoney = true
    /// 會議細節裡的部屬名字（沒設定過＝這支 iPhone 不是加入別人的共享就開）
    @State private var showOwnerNames =
        WatchPhoneSettings.showOwnerNames(isShareParticipant: CloudKitManager.shared.isShareParticipant)

    var body: some View {
        Section {
            if CloudKitManager.shared.isShareParticipant {
                shareRow
            }
            statusRow
            moneyToggle
            ownerToggle
            diagnosticsRow
        } header: {
            Text("送到手錶的內容")
        } footer: {
            Text(Self.footnote)
        }
    }

    // MARK: 列

    private var shareRow: some View {
        rowLabel(icon: "person.2.fill", color: .orange,
                 title: "這支 iPhone 加入了別人的共享",
                 subtitle: "手錶會看到共享裡的行程")
    }

    private var statusRow: some View {
        rowLabel(icon: "applewatch", color: .indigo,
                 title: bridge.isWatchAppInstalled ? "手錶版已安裝" : "手錶版還沒裝",
                 subtitle: statusSubtitle)
    }

    private var moneyToggle: some View {
        Toggle(isOn: $sendMoney) {
            rowLabel(icon: "dollarsign.circle.fill", color: .green,
                     title: "錢（還能花、接下來要繳）",
                     subtitle: sendMoney ? "送到手錶" : "不送：手錶上沒有「錢」那一頁")
        }
        .tint(.indigo)
        .onChange(of: sendMoney) { _, _ in
            bridge.settingsChanged()
        }
    }

    private var ownerToggle: some View {
        Toggle(isOn: $showOwnerNames) {
            rowLabel(icon: "person.fill", color: .blue,
                     title: "會議細節裡的部屬名字",
                     subtitle: Self.ownerSubtitle)
        }
        .tint(.indigo)
        .onChange(of: showOwnerNames) { _, on in
            WatchPhoneSettings.setShowOwnerNames(on)
            bridge.settingsChanged()
        }
    }

    private var diagnosticsRow: some View {
        Text(diagnosticsText)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// 圖示圓＋標題／小字（SettingsView 的 settingsActionRow 是 private，這裡自己畫一個小的）
    private func rowLabel(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 字

    /// 「上次送到手錶 09:24・6 KB」／「還沒送過」／沒裝時怎麼裝
    private var statusSubtitle: String {
        guard bridge.isWatchAppInstalled else { return Self.installHint }
        guard let at = bridge.lastSentAt else { return "還沒送過" }
        return "上次送到手錶 " + Self.sentTime(at, now: Date()) + "・" + Self.kilobytes(bridge.lastSentBytes)
    }

    /// 「背景建立資料：0 次」；有過的話後面接最近一次「（最近 10/22 03:12）」
    private var diagnosticsText: String {
        let n = AppStoresDiagnostics.count
        let head = "背景建立資料：" + String(n) + " 次"
        guard n > 0, let last = AppStoresDiagnostics.last else { return head }
        return head + "（最近 " + Self.sentTime(last, now: Date()) + "）"
    }

    /// 同一天只寫「09:24」；不同天「10/21 22:10」
    static func sentTime(_ at: Date, now: Date) -> String {
        let time = DayTimelineFormat.time(at)
        if Calendar.current.isDate(at, inSameDayAs: now) { return time }
        return WidgetDateText.shortDate(at) + " " + time
    }

    /// 「6 KB」（無條件進位、最少 1 KB）
    static func kilobytes(_ bytes: Int) -> String {
        String(max(1, (bytes + 1023) / 1024)) + " KB"
    }

    /// 說明一次寫成單一字串常數，不要在 Text(...) 裡用 + 串接
    private static let installHint = "iPhone「Watch」App › 可用的 App › LifeGood〔安裝〕"

    private static let ownerSubtitle = "只在手錶 App 抬手看會議細節時；錶面、通知、手腕放下都不寫"

    private static let footnote =
        "卡名、卡費金額、存摺、淨資產、部屬請假、完整號碼不會送到手錶。手腕放下時手錶上的金額一律遮起來。"
        + "會議主題會出現在錶面與通知上。"
        + "錶面上至少放一格 LifeGood，數字才會自己跟上；只放在智慧型堆疊的話，要打開手錶 App 一次才會更新。"
}
