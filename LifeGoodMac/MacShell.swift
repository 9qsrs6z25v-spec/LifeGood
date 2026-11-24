// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] 視窗骨架（brief.md §G2-6、judge_mac.md §F1、§F3、§O6）：側欄＋內容＋詳情（inspector）＋工具列。
//
// • 側欄：收支（總覽 ⌘1；收入 ⌘2〔v25.641〕；變動支出、固定支出、圖表 反灰標「下一版」不能選）｜資料來源。
// • 工具列只有「iPhone 同步 hh:mm」和 ⟳；超過 24 小時變橘色＋「打開 iPhone 的 LifeGood 讓資料同步」。
// • 空白狀態（審核員的 iCloud 是空的）：沒登入、沒資料、家人共享的成員、讀不到 各一段。
// • 編輯的 sheet、確認框、紅條、看門狗、狀態列由 G3 的 .macEditorHost(app) 掛在整個 split view 上。
// • 每個區塊拆成小 struct；不在 body 寫 store（重新整理在按鈕、scenePhase 的動作裡）。

import SwiftUI

struct MacShell: View {
    @EnvironmentObject private var app: MacAppModel
    @EnvironmentObject private var ui: MacUIState
    @EnvironmentObject private var money: MacMoneyStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            MacSidebar()
        } detail: {
            MacDetailArea()
        }
        .inspector(isPresented: $ui.showInspector) {
            MacInspector()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                MacSyncStamp(money: money)
                MacRefreshButton(app: app, money: money)
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .macEditorHost(app)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await money.refreshIfStale(15) } }
        }
    }
}

// MARK: - 側欄

fileprivate struct MacSidebar: View {
    @EnvironmentObject private var ui: MacUIState

    var body: some View {
        List(selection: pageSelection) {
            Section("收支") {
                MacSidebarRow(page: .overview, note: "⌘1").tag(MacPage.overview)
                MacSidebarRow(page: .income, note: "⌘2").tag(MacPage.income)
                MacSidebarRow(page: .variable, note: "下一版")
                MacSidebarRow(page: .fixed, note: "下一版")
                MacSidebarRow(page: .chart, note: "下一版")
            }
            Section {
                MacSidebarRow(page: .source, note: nil).tag(MacPage.source)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
    }

    /// 只收開放的頁（沒有 tag 的列本來就選不到；這裡再擋一次）
    private var pageSelection: Binding<MacPage?> {
        Binding(
            get: { ui.page },
            set: { p in
                if let p, p.isOpen { ui.page = p }
            }
        )
    }
}

fileprivate struct MacSidebarRow: View {
    let page: MacPage
    let note: String?

    var body: some View {
        HStack(spacing: 6) {
            Label(page.title, systemImage: page.icon)
            Spacer(minLength: 4)
            if let note {
                Text(note).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(page.isOpen ? Color.primary : Color.secondary)
        .help(page.isOpen ? page.title : "下一版開放")
    }
}

// MARK: - 內容區

fileprivate struct MacDetailArea: View {
    @EnvironmentObject private var ui: MacUIState
    @EnvironmentObject private var money: MacMoneyStore

    var body: some View {
        Group {
            switch ui.page {
            case .source:
                MacSourceView()
            case .income:
                // [v25.641 mac2] 收入頁；沒有帳本照 Mac 1 的空白狀態
                if money.account.hasLedger {
                    MacIncomePage()
                } else {
                    MacEmptyState(state: money.account)
                }
            default:
                if money.account.hasLedger {
                    MacOverviewPage()
                } else {
                    MacEmptyState(state: money.account)
                }
            }
        }
        .navigationTitle(ui.page.navTitle)
    }
}

// MARK: - 空白狀態（judge_mac.md §F3）

fileprivate struct MacEmptyContent {
    let title: String
    let icon: String
    let lines: [String]

    /// 每一段最後都寫這句（§F3 的「LifeGood 電腦版目前只能看」改成這句，brief.md §G2-6）
    static let footer = "電腦版打開『允許這台 Mac 修改』之後才能改"

    static let setupLines = [
        "1. iPhone 的 LifeGood → 設定 → 打開 iCloud 同步",
        "2. 這台 Mac 要登入跟 iPhone 同一個 Apple 帳號",
        "3. 按 ⌘R 重新讀取",
    ]

    static func make(_ state: MacAccountState) -> MacEmptyContent {
        switch state {
        case .noAccount:
            return MacEmptyContent(title: "這台 Mac 還沒登入 iCloud", icon: "person.crop.circle.badge.exclamationmark",
                                   lines: ["請到「系統設定 → Apple 帳號」登入 iCloud，要跟 iPhone 同一個 Apple 帳號",
                                           "登入之後按 ⌘R 重新讀取"])
        case .notOwner:
            return MacEmptyContent(title: "電腦版目前只支援資料擁有者", icon: "person.2.slash",
                                   lines: ["家人共享給你的資料，這一版請在 iPhone 看",
                                           "資料擁有者用自己的 Apple 帳號登入這台 Mac 就能用"])
        case .restricted:
            return MacEmptyContent(title: "這台 Mac 的 iCloud 被限制使用", icon: "lock.icloud",
                                   lines: ["可能是螢幕使用時間或管理設定擋住了；請到「系統設定」確認",
                                           "確認之後按 ⌘R 重新讀取"])
        case .temporarilyUnavailable:
            return MacEmptyContent(title: "iCloud 暫時無法使用", icon: "icloud.slash",
                                   lines: ["請到「系統設定 → Apple 帳號」確認登入狀態",
                                           "等一下再按 ⌘R 重新讀取"])
        case .couldNotDetermine:
            return MacEmptyContent(title: "讀不到 iCloud 帳號狀態", icon: "icloud.slash",
                                   lines: ["等一下再按 ⌘R 重新讀取"])
        case .failed(let message):
            return MacEmptyContent(title: "讀不到 iCloud 的資料", icon: "exclamationmark.icloud",
                                   lines: [message, "按 ⌘R 再試一次"])
        default:
            return MacEmptyContent(title: "這台 Mac 還讀不到 LifeGood 的資料", icon: "icloud.and.arrow.down",
                                   lines: setupLines + ["家人共享的成員：電腦版目前只支援資料擁有者"])
        }
    }
}

fileprivate struct MacEmptyState: View {
    let state: MacAccountState

    var body: some View {
        if state == .unknown || state == .checking {
            ProgressView("正在讀取 iCloud…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MacEmptyCard(content: MacEmptyContent.make(state))
        }
    }
}

fileprivate struct MacEmptyCard: View {
    let content: MacEmptyContent
    @EnvironmentObject private var app: MacAppModel

    var body: some View {
        ContentUnavailableView {
            Label(content.title, systemImage: content.icon)
        } description: {
            MacEmptyLines(lines: content.lines)
        } actions: {
            Button("重新讀取") { app.requestRefresh() }
        }
    }
}

fileprivate struct MacEmptyLines: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.self) { line in
                Text(line)
            }
            Text(MacEmptyContent.footer)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 工具列

fileprivate struct MacSyncStamp: View {
    @ObservedObject var money: MacMoneyStore

    var body: some View {
        let info = MacSyncStamp.info(offline: money.isOffline, lastFetch: money.lastFetch,
                                     phone: money.lastPhoneSync, account: money.account,
                                     showingCache: money.showingCache, cacheSavedAt: money.cacheSavedAt, now: Date())
        Text(info.text)
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(info.stale ? Color.orange : Color.secondary)
            .help("iPhone 最後一次把收支推上 iCloud 的時間")
    }

    /// 超過 24 小時沒更新＝橘色（judge_mac.md §F1）
    /// [v25.641 mac2] 顯示這台存的資料（本機快照）時最優先：離線「…・離線中」（橘色），線上「…・正在讀 iCloud…」
    static func info(offline: Bool, lastFetch: Date?, phone: Date?, account: MacAccountState,
                     showingCache: Bool, cacheSavedAt: Date?,
                     now: Date) -> (text: String, stale: Bool) {
        if showingCache {
            let saved = cacheSavedAt.map { d in MacText.stamp(d, now: now) } ?? "—"
            let head = "先顯示這台存的資料（" + saved + "）"
            if offline { return (head + "・離線中", true) }
            return (head + "・正在讀 iCloud…", false)
        }
        if offline {
            let at = lastFetch.map { d in MacText.stamp(d, now: now) } ?? "—"
            return ("離線中，資料停在 " + at, true)
        }
        switch account {
        case .available:
            break
        case .unknown, .checking:
            return ("正在讀取 iCloud…", false)
        case .noData:
            return ("iCloud 上還沒有收支資料", false)
        default:
            return ("沒有讀到 iCloud", false)
        }
        guard let phone else { return ("iPhone 還沒同步過", false) }
        let text = "iPhone 同步 " + MacText.stamp(phone, now: now)
        if now.timeIntervalSince(phone) > 24 * 3600 {
            return (text + "・打開 iPhone 的 LifeGood 讓資料同步", true)
        }
        return (text, false)
    }
}

fileprivate struct MacRefreshButton: View {
    let app: MacAppModel
    @ObservedObject var money: MacMoneyStore

    var body: some View {
        Button {
            app.requestRefresh()
        } label: {
            Label("重新整理", systemImage: "arrow.clockwise")
        }
        .help("重新整理（⌘R）")
        .disabled(money.isRefreshing)
    }
}

// MARK: - 共用的字（日期、金額）

/// 日期格式（時區、曆法跟著這台 Mac，跟 iPhone 一樣看裝置）
private func macDateFormatter(_ format: String) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_Hant_TW")
    f.dateFormat = format
    return f
}

enum MacText {
    private static let hm = macDateFormatter("HH:mm")
    private static let md = macDateFormatter("M/d")
    private static let mdhm = macDateFormatter("M/d HH:mm")
    private static let ymd = macDateFormatter("yyyy/M/d")
    private static let ymdhm = macDateFormatter("yyyy/M/d HH:mm")

    /// 「14:05」
    static func time(_ d: Date) -> String { hm.string(from: d) }
    /// 「11/23」
    static func day(_ d: Date) -> String { md.string(from: d) }
    /// 「11/23 12:30」
    static func dayTime(_ d: Date) -> String { mdhm.string(from: d) }
    /// 「2026/11/23」
    static func fullDay(_ d: Date) -> String { ymd.string(from: d) }
    /// 「2026/11/23 12:30」
    static func fullDayTime(_ d: Date) -> String { ymdhm.string(from: d) }
    /// 今天＝「14:05」，其他天＝「11/22 14:05」
    static func stamp(_ d: Date, now: Date) -> String {
        Calendar.current.isDate(d, inSameDayAs: now) ? time(d) : dayTime(d)
    }

    /// 完整金額「NT$9,820」（四捨五入到元）
    static func money(_ v: Double) -> String {
        "NT$" + WidgetMoneyFormat.number(v.rounded(), digits: 0)
    }

    /// 詳情用：有小數照寫「NT$120.5」
    static func exactMoney(_ v: Double) -> String {
        "NT$" + WidgetMoneyFormat.number(v, digits: 2)
    }

    /// 「NT$8.6萬」（＝App 的 MoneyFormat.short）
    static func short(_ v: Double) -> String { WidgetMoneyFormat.short(v) }
}
