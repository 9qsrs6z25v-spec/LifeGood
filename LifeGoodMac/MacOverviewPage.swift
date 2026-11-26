// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] 收支簡版總覽（brief.md §G2-7、judge_mac.md §F2）。Mac 1 不用 Table、不用 Charts。
//
// 上面 4 格（本月收入／本月支出／本月結餘／今天花了）→ 有分帳時一行說明 → 本月花在哪裡（變動支出，只算自己那份）→ 最近交易 10 筆。
// 數字全部由 MacMoneyStore.overview(now:calendar:) 一次算好（照抄 ExpenseStore），這裡只排版。
// 點一筆＝ui.selection（右邊詳情）；連按兩下＝edit.requestEdit；右鍵〔編輯〕〔刪除…〕；⌫＝edit.requestDelete（要確認，G3）。
// [v25.645 mac5] 最上面一條記帳小鎮（MacGameStrip）；四格放進綠色看板、白卡＋彩色圖示圓（G1a，judge_mac.md §S6-2）。
// [v25.648 mac7 G2] 總覽補完（judge_mac.md §U3-7）：上面換成 iPhone 總覽看板、中間每天花多少＋未來 7 天要扣、分類卡（點一張跳變動支出只看那一類）；最近交易照舊。

import SwiftUI

struct MacOverviewPage: View {
    @EnvironmentObject private var money: MacMoneyStore
    @EnvironmentObject private var ui: MacUIState
    @EnvironmentObject private var edit: MacEditCenter

    var body: some View {
        // [v25.648 mac7 G2] 一次算完（同一個 now、Calendar.current）：最近交易、分帳說明照舊；看板、每日長條、未來 7 天、分類卡照 iPhone 總覽（sim7: ov7#18）
        let now = Date()
        let cal = Calendar.current
        let numbers = money.overview(now: now, calendar: cal)
        let board = MacOverviewBoardData.build(money: money, now: now, calendar: cal)
        let stats = MacOverviewStats.categoryStats(money: money, now: now, calendar: cal)
        // [v25.645 mac5] 最上面記帳小鎮的遊戲列（關掉時是空的）
        VStack(spacing: 0) {
            MacGameStrip()
            MacOverviewList(numbers: numbers, board: board, stats: stats, selection: $ui.selection, edit: edit)
        }
    }
}

// MARK: - 整頁（一個 List：只有最近交易那幾列有 tag、選得到）

fileprivate struct MacOverviewList: View {
    let numbers: MacOverviewNumbers
    let board: MacOverviewBoardData
    let stats: [MacOverviewCategoryStat]
    @Binding var selection: MacEntryRef?
    let edit: MacEditCenter

    var body: some View {
        List(selection: $selection) {
            Section {
                MacOverviewHeroBoard(data: board)
                    .listRowSeparator(.hidden)
                if numbers.splitDeducted > 0 {
                    MacSplitNote(amount: numbers.splitDeducted)
                }
            }
            Section {
                MacOverviewMiddle(board: board)
                    .listRowSeparator(.hidden)
            }
            Section {
                MacOverviewCategoryCards(stats: stats)
                    .listRowSeparator(.hidden)
            } header: {
                MacOverviewCategoryHeader(stats: stats)
            }
            Section {
                MacRecentRows(rows: numbers.recent)
            } header: {
                Text("最近交易")
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: MacEntryRef.self) { refs in
            MacRecentMenu(refs: refs, edit: edit)
        } primaryAction: { refs in
            if let ref = refs.first { edit.requestEdit(ref) }
        }
        .onDeleteCommand {
            if let ref = selection { edit.requestDelete(ref) }
        }
    }
}

// MARK: - 中間：每天花多少＋未來 7 天要扣（未來 7 天 0 筆就只剩長條）

fileprivate struct MacOverviewMiddle: View {
    let board: MacOverviewBoardData

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MacOverviewDailyCard(data: board)
            if !board.upcoming.isEmpty {
                MacOverviewUpcomingCard(bills: board.upcoming)
                    .frame(width: 320)
            }
        }
        .padding(.vertical, 6)
    }
}

/// 本月有分帳才出現
fileprivate struct MacSplitNote: View {
    let amount: Double

    var body: some View {
        Label("分帳已扣掉別人那份 " + MacText.money(amount) + "（只算你自己那份）", systemImage: "person.2")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

// MARK: - 最近交易

fileprivate struct MacRecentRows: View {
    let rows: [MacRecentRow]

    var body: some View {
        if rows.isEmpty {
            Text("還沒有記帳")
                .foregroundStyle(.secondary)
        } else {
            ForEach(rows) { row in
                MacRecentRowView(row: row)
                    .tag(row.ref)
            }
        }
    }
}

fileprivate struct MacRecentRowView: View {
    let row: MacRecentRow
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            Text(MacOverviewText.date(row))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(row.title)
                .lineLimit(1)
            Text("（" + row.detail + "）")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(MacOverviewText.amount(row))
                .monospacedDigit()
                .foregroundStyle(row.kind == .income ? MacTone.good.color(MacPalette(scheme)) : Color.primary)
        }
    }
}

/// 右鍵選單（選取的那一筆）
fileprivate struct MacRecentMenu: View {
    let refs: Set<MacEntryRef>
    let edit: MacEditCenter

    var body: some View {
        if let ref = refs.first {
            Button("編輯") { edit.requestEdit(ref) }
                .disabled(!edit.canEdit(ref))
            Button("刪除…", role: .destructive) { edit.requestDelete(ref) }
                .disabled(!edit.canDelete(ref))
        }
    }
}

// MARK: - 字

enum MacOverviewText {
    /// 本月結餘那格的小字（sim_mac1.py saved_line）
    static func savedLine(income: Double, spend: Double) -> String {
        let balance = income - spend
        if income <= 0 { return "本月還沒有收入" }
        if balance < 0 { return "透支 " + WidgetMoneyFormat.short(-balance) }
        return "存下 " + WidgetMoneyFormat.percent(balance / income)
    }

    /// 占比「46%」；本月變動合計是 0＝「—」
    static func share(_ r: Double?) -> String {
        guard let r else { return "—" }
        return WidgetMoneyFormat.percent(r)
    }

    /// 變動「11/23 12:30」；固定、收入「11/22」
    static func date(_ row: MacRecentRow) -> String {
        row.kind == .variable ? MacText.dayTime(row.date) : MacText.day(row.date)
    }

    /// 支出「−NT$180」、收入「＋NT$6.2萬」
    static func amount(_ row: MacRecentRow) -> String {
        let text = WidgetMoneyFormat.short(abs(row.amount))
        return (row.kind == .income ? "＋" : "−") + text
    }
}
