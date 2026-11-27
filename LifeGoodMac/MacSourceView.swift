// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] 資料來源頁（brief.md §G2-9、judge_mac.md §F4、§O6）：帳號狀態、5 個鍵各有沒有、筆數、大小、iPhone 最後同步時間、
// 〔重新整理 ⌘R〕；下面放 G3 的 MacWriteSettingsSection()（寫入開關、自我檢查、最近在電腦改的、備份）。
// [v25.641 mac2 G3] 〔重新整理〕那段多一列「這台存的資料」（本機快照的時間）。
// 不顯示 email、不顯示帳號雜湊、不顯示任何一筆的內容。

import SwiftUI

struct MacSourceView: View {
    @EnvironmentObject private var money: MacMoneyStore
    @EnvironmentObject private var app: MacAppModel

    var body: some View {
        Form {
            MacSourceAccountSection(money: money)
            MacSourceDataSection(money: money)
            MacSourceRefreshSection(app: app, money: money)
            MacWriteSettingsSection()
        }
        .formStyle(.grouped)
    }
}

// MARK: - iCloud 帳號

fileprivate struct MacSourceAccountSection: View {
    @ObservedObject var money: MacMoneyStore

    var body: some View {
        Section("iCloud 帳號") {
            LabeledContent("狀態", value: money.account.summary)
            if money.isOffline {
                LabeledContent("連線", value: "離線中，資料停在 " + (money.lastFetch.map { d in MacText.fullDayTime(d) } ?? "—"))
            }
            if let problem = money.lastProblem {
                LabeledContent("這一輪", value: problem)
            }
        }
    }
}

// MARK: - 5 個鍵

fileprivate struct MacSourceItem: Identifiable {
    let key: String
    let label: String
    let exists: Bool
    let count: Int?
    let bytes: Int?
    let updatedAt: Date?
    var id: String { key }

    /// 畫面上的名字（judge_mac.md §F4）
    static func label(for key: String) -> String {
        switch key {
        case MacCloud.expensesKey: return "支出"
        case MacCloud.incomesKey: return "收入"
        case MacCloud.ratesKey: return "匯率"
        case MacCloud.splitsKey: return "分帳"
        case MacCloud.kindsKey: return "細項"
        default: return key
        }
    }

    @MainActor
    static func all(_ money: MacMoneyStore) -> [MacSourceItem] {
        MacCloud.readKeys.map { key in
            let rec = money.records[key]
            return MacSourceItem(key: key, label: label(for: key), exists: rec?.record != nil,
                                 count: money.counts[key], bytes: rec?.data?.count, updatedAt: rec?.updatedAt)
        }
    }
}

fileprivate struct MacSourceDataSection: View {
    @ObservedObject var money: MacMoneyStore

    var body: some View {
        Section {
            MacSourceGrid(items: MacSourceItem.all(money), fetched: money.hasFetchedThisLaunch)
        } header: {
            Text("資料")
        } footer: {
            Text("電腦版只讀這 5 包；打開下面的「允許這台 Mac 修改」之後，才會寫回支出、收入這兩包。")
        }
    }
}

fileprivate struct MacSourceGrid: View {
    let items: [MacSourceItem]
    let fetched: Bool

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
            GridRow {
                Text("資料").foregroundStyle(.secondary)
                Text("有沒有").foregroundStyle(.secondary)
                Text("筆數").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Text("大小").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Text("iPhone 最後同步").foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                GridRow {
                    MacSourceName(item: item)
                    Text(MacSourceText.exists(item, fetched: fetched))
                    Text(MacSourceText.count(item)).monospacedDigit()
                    Text(MacSourceText.size(item)).monospacedDigit()
                    Text(MacSourceText.updated(item)).monospacedDigit()
                }
            }
        }
    }
}

fileprivate struct MacSourceName: View {
    let item: MacSourceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.label)
            Text(item.key)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

fileprivate enum MacSourceText {
    static func exists(_ item: MacSourceItem, fetched: Bool) -> String {
        guard fetched else { return "…" }
        return item.exists ? "✓" : "沒有"
    }

    static func count(_ item: MacSourceItem) -> String {
        guard item.exists, let n = item.count else { return "—" }
        return WidgetMoneyFormat.number(Double(n), digits: 0)
    }

    static func size(_ item: MacSourceItem) -> String {
        guard let b = item.bytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
    }

    static func updated(_ item: MacSourceItem) -> String {
        guard let d = item.updatedAt else { return "—" }
        return MacText.dayTime(d)
    }
}

// MARK: - 重新整理

fileprivate struct MacSourceRefreshSection: View {
    let app: MacAppModel
    @ObservedObject var money: MacMoneyStore

    var body: some View {
        Section {
            HStack {
                Button("重新整理") { app.requestRefresh() }
                    .disabled(money.isRefreshing)
                Text("⌘R")
                    .foregroundStyle(.secondary)
                Spacer()
                if money.isRefreshing {
                    ProgressView().controlSize(.small)
                } else if let last = money.lastFetch {
                    Text("最後讀取 " + MacText.fullDayTime(last))
                        .foregroundStyle(.secondary)
                }
            }
            if let phone = money.lastPhoneSync {
                LabeledContent("iPhone 最後同步", value: MacText.fullDayTime(phone))
            }
            LabeledContent("這台存的資料", value: MacSourceRefreshSection.snapshotText(money))
        }
    }

    /// [v25.641 mac2 G3] 本機快照那一列：只寫時間，不顯示內容、不顯示雜湊
    @MainActor
    static func snapshotText(_ money: MacMoneyStore) -> String {
        guard money.showingCache else { return "每次讀到 iCloud 就更新" }
        let saved = money.cacheSavedAt.map { d in MacText.dayTime(d) } ?? "—"
        return saved + "（還沒讀到 iCloud，先顯示這份；這時候不能改）"
    }
}
