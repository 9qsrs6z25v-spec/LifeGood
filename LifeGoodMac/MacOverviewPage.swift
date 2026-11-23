// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] 收支簡版總覽（brief.md §G2-7、judge_mac.md §F2）。Mac 1 不用 Table、不用 Charts。
//
// 上面 4 格（本月收入／本月支出／本月結餘／今天花了）→ 有分帳時一行說明 → 本月花在哪裡（變動支出，只算自己那份）→ 最近交易 10 筆。
// 數字全部由 MacMoneyStore.overview(now:calendar:) 一次算好（照抄 ExpenseStore），這裡只排版。
// 點一筆＝ui.selection（右邊詳情）；連按兩下＝edit.requestEdit；右鍵〔編輯〕〔刪除…〕；⌫＝edit.requestDelete（要確認，G3）。

import SwiftUI

struct MacOverviewPage: View {
    @EnvironmentObject private var money: MacMoneyStore
    @EnvironmentObject private var ui: MacUIState
    @EnvironmentObject private var edit: MacEditCenter

    var body: some View {
        let numbers = money.overview(now: Date(), calendar: .current)
        MacOverviewList(numbers: numbers, selection: $ui.selection, edit: edit)
    }
}

// MARK: - 整頁（一個 List：只有最近交易那幾列有 tag、選得到）

fileprivate struct MacOverviewList: View {
    let numbers: MacOverviewNumbers
    @Binding var selection: MacEntryRef?
    let edit: MacEditCenter

    var body: some View {
        List(selection: $selection) {
            Section {
                MacOverviewCards(numbers: numbers)
                if numbers.splitDeducted > 0 {
                    MacSplitNote(amount: numbers.splitDeducted)
                }
            }
            Section {
                MacCategoryList(rows: numbers.categories)
            } header: {
                Text("本月花在哪裡（變動支出，只算自己那份）")
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

// MARK: - 4 格

fileprivate struct MacOverviewCards: View {
    let numbers: MacOverviewNumbers

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                MacIncomeCard(numbers: numbers)
                MacSpendCard(numbers: numbers)
                MacBalanceCard(numbers: numbers)
                MacTodayCard(numbers: numbers)
            }
        }
        .padding(.vertical, 6)
    }
}

/// 本月收入（小字：今年累計）
fileprivate struct MacIncomeCard: View {
    let numbers: MacOverviewNumbers

    var body: some View {
        MacStatCard(title: "本月收入", value: MacText.short(numbers.income),
                    note: "今年累計 " + MacText.short(numbers.yearToDateIncome), tint: .primary)
    }
}

/// 本月支出（小字：固定・變動）
fileprivate struct MacSpendCard: View {
    let numbers: MacOverviewNumbers

    var body: some View {
        MacStatCard(title: "本月支出", value: MacText.short(numbers.spend),
                    note: "固定 " + MacText.short(numbers.fixed) + "・變動 " + MacText.short(numbers.variable),
                    tint: .primary)
    }
}

/// 本月結餘（小字：本月還沒有收入／透支 NT$…／存下 39%）
fileprivate struct MacBalanceCard: View {
    let numbers: MacOverviewNumbers

    var body: some View {
        MacStatCard(title: "本月結餘", value: MacText.short(numbers.balance),
                    note: MacOverviewText.savedLine(income: numbers.income, spend: numbers.spend),
                    tint: numbers.balance < 0 ? .red : .primary)
    }
}

/// 今天花了（變動支出今天＋固定支出每天攤的）
fileprivate struct MacTodayCard: View {
    let numbers: MacOverviewNumbers

    var body: some View {
        MacStatCard(title: "今天花了", value: MacText.short(numbers.today), note: nil, tint: .primary)
    }
}

fileprivate struct MacStatCard: View {
    let title: String
    let value: String
    let note: String?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(note ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

// MARK: - 本月花在哪裡

fileprivate struct MacCategoryList: View {
    let rows: [MacCategoryRow]

    var body: some View {
        if rows.isEmpty {
            Text("這個月還沒有變動支出")
                .foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 6) {
                GridRow {
                    Text("分類").foregroundStyle(.secondary)
                    Text("金額").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text("占比").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text("筆數").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                }
                ForEach(rows) { row in
                    GridRow {
                        Label(row.category.rawValue, systemImage: row.category.icon)
                        Text(MacText.money(row.amount)).monospacedDigit()
                        Text(MacOverviewText.share(row.share)).monospacedDigit()
                        Text("\(row.count)").monospacedDigit()
                    }
                }
            }
            .padding(.vertical, 4)
        }
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
                .foregroundStyle(row.kind == .income ? Color.green : Color.primary)
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
