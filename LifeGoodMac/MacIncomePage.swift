// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.641 mac2 G2] 收入頁（brief.md §2 G2 第 5～8 條、judge_mac.md §P8、scout_macui §3、§5、§7）。
//
// • 頭（看板＋長條＋範圍）固定高 250 的一般 View；Table 在下面撐滿，不放進 ScrollView／List、外面不包 AnyView。
// • 數字由 MacIncomeBoard.build 一次算完（同一個 now、Calendar.current）；列由 MacIncomeTable.rows 算好，body 只排版。
// • Table 寫法照 scout_macui §5 十二條：7 支欄每支一個 private func、回傳型別寫死；內容閉包只放一個 Cell；
//   builder 裡不寫 if；修飾器包成 MacIncomeTableActions；不用 .alignment(（金額在 Cell 裡靠右）。
// • 選取（sim2: sel#2）：搜尋字、範圍、分類變了，選到的那筆不在新列裡就取消選取；搜尋框焦點回報 ui.searchFieldFocused，
//   ⌘F（ui.searchRequest）把焦點放進搜尋框。全部在 .onChange 裡寫，不在 body 寫 store。

import SwiftUI

struct MacIncomePage: View {
    @EnvironmentObject private var money: MacMoneyStore
    @EnvironmentObject private var ui: MacUIState
    @EnvironmentObject private var edit: MacEditCenter
    @State private var range: MacIncomeRange = .month
    @State private var categoryFilter: IncomeCategory? = nil
    @State private var query: String = ""
    @State private var sortOrder: [MacIncomeSort] = [MacIncomeSort(\MacIncomeRow.date, order: .reverse)]
    @FocusState private var searchFocused: Bool

    var body: some View {
        let now = Date()
        let board: MacIncomeBoardData = MacIncomeBoard.build(money: money, now: now, calendar: .current)
        let rows: [MacIncomeRow] = MacIncomeTable.rows(incomes: money.incomes, range: range, query: query,
                                                       category: categoryFilter, now: now, calendar: .current,
                                                       order: sortOrder)
        let rowIDs: [MacEntryRef] = rows.map { r in r.id }
        MacIncomeLayout(board: board, rows: rows, hasIncomes: !money.incomes.isEmpty, now: now,
                        range: $range, sortOrder: $sortOrder, ui: ui, edit: edit)
            .navigationSubtitle(MacIncomeHeadline.monthTitle(board))
            .toolbar {
                ToolbarItem {
                    MacIncomeCategoryMenu(selection: $categoryFilter)
                }
            }
            .searchable(text: $query, placement: .toolbar, prompt: "搜尋名稱、備註、分類")
            .searchFocused($searchFocused)
            .modifier(MacIncomeSelectionGuard(query: query, range: range, categoryFilter: categoryFilter,
                                              rowIDs: rowIDs, focus: $searchFocused, ui: ui))
    }
}

// MARK: - 選取守門（.onChange 包在一起）

struct MacIncomeSelectionGuard: ViewModifier {
    let query: String
    let range: MacIncomeRange
    let categoryFilter: IncomeCategory?
    /// 這次畫出來的列（onChange 呼叫的是新的那個閉包，拿到的是新的列）
    let rowIDs: [MacEntryRef]
    let focus: FocusState<Bool>.Binding
    @ObservedObject var ui: MacUIState

    func body(content: Content) -> some View {
        content
            .onChange(of: query) { _, _ in clearHidden() }
            .onChange(of: range) { _, _ in clearHidden() }
            .onChange(of: categoryFilter) { _, _ in clearHidden() }
            .onChange(of: rowIDs) { _, _ in clearHidden() }          // 改了日期、別台刪掉 → 那列不在了
            .onChange(of: ui.selection) { _, _ in clearHidden() }    // 存完選到這個範圍看不到的那筆
            .onChange(of: focus.wrappedValue) { _, f in ui.searchFieldFocused = f }
            .onChange(of: ui.searchRequest) { _, _ in focus.wrappedValue = true }
    }

    /// sim2: sel#2　選到的不在新的列裡 → 取消選取（⌘⌫ 不會刪到畫面上看不到的那一筆）
    private func clearHidden() {
        if let s = ui.selection, !rowIDs.contains(s) {
            ui.selection = nil
        }
    }
}

// MARK: - 整頁版面

struct MacIncomeLayout: View {
    let board: MacIncomeBoardData
    let rows: [MacIncomeRow]
    let hasIncomes: Bool
    let now: Date
    @Binding var range: MacIncomeRange
    @Binding var sortOrder: [MacIncomeSort]
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter

    var body: some View {
        VStack(spacing: 0) {
            MacIncomeHeader(board: board, now: now, range: $range, count: rows.count)
                .frame(height: 250)
            Divider()
            MacIncomeTableArea(rows: rows, hasIncomes: hasIncomes, range: $range, sortOrder: $sortOrder,
                               ui: ui, edit: edit)
        }
    }
}

// MARK: - 頭：大字、今年累計、一句話、膠囊｜長條、範圍

struct MacIncomeHeader: View {
    let board: MacIncomeBoardData
    let now: Date
    @Binding var range: MacIncomeRange
    let count: Int

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            MacIncomeSummary(board: board, now: now)
                .frame(minWidth: 200, idealWidth: 260, maxWidth: 320, alignment: .leading)
            MacIncomeChartBox(board: board, range: $range, count: count)
                .frame(minWidth: 200, maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MacIncomeSummary: View {
    let board: MacIncomeBoardData
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("本月已入帳")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            MacIncomeBigNumber(value: board.income)
            MacIncomeYearLine(yearToDate: board.yearToDate)
            MacIncomeLineText(text: MacIncomeHeadline.line(board))
            MacIncomeChipRow(chips: MacIncomeHeadline.chips(board, now: now, calendar: .current))
                .padding(.top, 4)
        }
    }
}

struct MacIncomeBigNumber: View {
    let value: Double

    var body: some View {
        Text(MacText.short(value))
            .font(.system(size: 30, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
    }
}

/// 「今年累計 NT$91.2萬」（今年累計 > 0 才有）
struct MacIncomeYearLine: View {
    let yearToDate: Double

    var body: some View {
        if yearToDate > 0 {
            Text("今年累計 " + MacText.short(yearToDate))
                .font(.callout)
                .monospacedDigit()
        }
    }
}

struct MacIncomeLineText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 膠囊：一行兩顆（視窗窄也放得下）
struct MacIncomeChipRow: View {
    let chips: [MacIncomeChip]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(pairStarts, id: \.self) { start in
                MacIncomeChipPair(chips: Array(chips[start..<min(start + 2, chips.count)]))
            }
        }
    }

    private var pairStarts: [Int] {
        Array(stride(from: 0, to: chips.count, by: 2))
    }
}

struct MacIncomeChipPair: View {
    let chips: [MacIncomeChip]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(chips) { chip in
                MacIncomeChipView(chip: chip)
            }
        }
    }
}

struct MacIncomeChipView: View {
    let chip: MacIncomeChip

    var body: some View {
        Label(chip.label + " " + chip.value, systemImage: chip.icon)
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    /// 上月存下＝綠、上月透支＝紅、其餘膠囊照一般字色
    private var tint: Color {
        guard let good = chip.good else { return Color.primary }
        return good ? Color.green : Color.red
    }
}

struct MacIncomeChartBox: View {
    let board: MacIncomeBoardData
    @Binding var range: MacIncomeRange
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MacIncomeChartOrEmpty(board: board)
            MacIncomeRangeBar(range: $range, count: count)
        }
    }
}

struct MacIncomeChartOrEmpty: View {
    let board: MacIncomeBoardData

    var body: some View {
        if board.bars.isEmpty {
            Text("記下收入之後，這裡會一個月一根")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 140)
        } else {
            MacIncomeChart(bars: board.bars, expected: MacIncomeHeadline.expected(board),
                           summary: MacIncomeHeadline.chartSummary(board))
        }
    }
}

/// 範圍（本月｜今年｜全部）＋筆數
struct MacIncomeRangeBar: View {
    @Binding var range: MacIncomeRange
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Picker("範圍", selection: $range) {
                ForEach(MacIncomeRange.allCases) { r in
                    Text(r.title).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Text("\(count) 筆")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 工具列：分類篩選（只篩顯示、不存）

struct MacIncomeCategoryMenu: View {
    @Binding var selection: IncomeCategory?

    var body: some View {
        Picker("分類", selection: $selection) {
            Text("全部").tag(IncomeCategory?.none)
            ForEach(IncomeCategory.allCases) { c in
                Text(c.rawValue).tag(IncomeCategory?.some(c))
            }
        }
        .pickerStyle(.menu)
        .help("只看某一類收入")
    }
}

// MARK: - 表格區：沒有收入／篩完是空的／表格＋合計

struct MacIncomeTableArea: View {
    let rows: [MacIncomeRow]
    let hasIncomes: Bool
    @Binding var range: MacIncomeRange
    @Binding var sortOrder: [MacIncomeSort]
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter

    var body: some View {
        if !hasIncomes {
            MacIncomeEmptyNote(text: "還沒有收入紀錄，按 ⌘⇧N 記一筆")
        } else if rows.isEmpty {
            MacIncomeNoMatch(range: $range)
        } else {
            VStack(spacing: 0) {
                MacIncomeTableView(rows: rows, sortOrder: $sortOrder, ui: ui, edit: edit)
                MacIncomeTableFooter(rows: rows, range: range)
            }
        }
    }
}

struct MacIncomeEmptyNote: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 「本月沒有符合的」＋〔在全部裡找〕（按鈕事件裡改範圍）
struct MacIncomeNoMatch: View {
    @Binding var range: MacIncomeRange

    var body: some View {
        VStack(spacing: 10) {
            Text(range.emptyText)
                .foregroundStyle(.secondary)
            if range != .all {
                Button("在全部裡找") { range = .all }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 表格下面：「本月合計 NT$85,000」或「12 筆」；有每年的收入多一句說明
struct MacIncomeTableFooter: View {
    let rows: [MacIncomeRow]
    let range: MacIncomeRange

    var body: some View {
        HStack(spacing: 12) {
            Text(MacIncomeTable.footer(rows, range: range))
                .monospacedDigit()
            if MacIncomeTable.hasYearly(rows) {
                Text("每年的收入，大字照每月 1/12 算")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - 7 欄表格（scout_macui §5）

struct MacIncomeTableView: View {
    let rows: [MacIncomeRow]
    @Binding var sortOrder: [MacIncomeSort]
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter

    var body: some View {
        Table(rows, selection: $ui.selection, sortOrder: $sortOrder) {
            dateColumn()
            titleColumn()
            categoryColumn()
            periodColumn()
            amountColumn()
            bankColumn()
            noteColumn()
        }
        .modifier(MacIncomeTableActions(ui: ui, edit: edit))
    }

    private func dateColumn() -> TableColumn<MacIncomeRow, MacIncomeSort, MacIncomeDateCell, Text> {
        TableColumn(Text("日期"), value: \MacIncomeRow.date) { row in
            MacIncomeDateCell(row: row)
        }
        .width(min: 84, ideal: 96, max: 120)
    }

    private func titleColumn() -> TableColumn<MacIncomeRow, MacIncomeSort, MacIncomeTitleCell, Text> {
        TableColumn(Text("項目"), value: \MacIncomeRow.title) { row in
            MacIncomeTitleCell(row: row)
        }
        .width(min: 100, ideal: 180, max: 320)
    }

    private func categoryColumn() -> TableColumn<MacIncomeRow, MacIncomeSort, MacIncomeCategoryCell, Text> {
        TableColumn(Text("分類"), value: \MacIncomeRow.category) { row in
            MacIncomeCategoryCell(row: row)
        }
        .width(min: 48, ideal: 64, max: 100)
    }

    private func periodColumn() -> TableColumn<MacIncomeRow, MacIncomeSort, MacIncomePeriodCell, Text> {
        TableColumn(Text("週期"), value: \MacIncomeRow.periodRank) { row in
            MacIncomePeriodCell(row: row)
        }
        .width(min: 56, ideal: 140, max: 220)
    }

    private func amountColumn() -> TableColumn<MacIncomeRow, MacIncomeSort, MacIncomeAmountCell, Text> {
        TableColumn(Text("金額"), value: \MacIncomeRow.amount) { row in
            MacIncomeAmountCell(row: row)
        }
        .width(min: 80, ideal: 110, max: 160)
    }

    private func bankColumn() -> TableColumn<MacIncomeRow, MacIncomeSort, MacIncomeBankCell, Text> {
        TableColumn(Text("入帳"), value: \MacIncomeRow.bankText) { row in
            MacIncomeBankCell(row: row)
        }
        .width(min: 48, ideal: 100, max: 180)
    }

    private func noteColumn() -> TableColumn<MacIncomeRow, MacIncomeSort, MacIncomeNoteCell, Text> {
        TableColumn(Text("備註"), value: \MacIncomeRow.note) { row in
            MacIncomeNoteCell(row: row)
        }
        .width(min: 60, ideal: 200)
    }
}

// MARK: - Cell（每格一個小 View；字在建列時就算好）

struct MacIncomeDateCell: View {
    let row: MacIncomeRow

    var body: some View {
        Text(MacText.fullDay(row.date))
            .monospacedDigit()
            .foregroundStyle(row.dimmed ? Color.secondary : Color.primary)
    }
}

struct MacIncomeTitleCell: View {
    let row: MacIncomeRow

    var body: some View {
        Text(row.title)
            .lineLimit(1)
            .foregroundStyle(row.dimmed ? Color.secondary : Color.primary)
    }
}

struct MacIncomeCategoryCell: View {
    let row: MacIncomeRow

    var body: some View {
        Text(row.category)
            .lineLimit(1)
            .foregroundStyle(row.dimmed ? Color.secondary : Color.primary)
    }
}

struct MacIncomePeriodCell: View {
    let row: MacIncomeRow

    var body: some View {
        Text(row.periodText)
            .lineLimit(1)
            .foregroundStyle(row.dimmed ? Color.secondary : Color.primary)
    }
}

struct MacIncomeAmountCell: View {
    let row: MacIncomeRow

    var body: some View {
        Text(row.amountText)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(row.dimmed ? Color.secondary : Color.green)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct MacIncomeBankCell: View {
    let row: MacIncomeRow

    var body: some View {
        Text(row.bankText)
            .lineLimit(1)
            .foregroundStyle(Color.secondary)
    }
}

struct MacIncomeNoteCell: View {
    let row: MacIncomeRow

    var body: some View {
        Text(row.note)
            .lineLimit(1)
            .foregroundStyle(Color.secondary)
    }
}

// MARK: - 表格的右鍵、連按兩下、⌫、Return／Space

struct MacIncomeTableActions: ViewModifier {
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter

    func body(content: Content) -> some View {
        content
            .contextMenu(forSelectionType: MacEntryRef.self) { refs in
                MacIncomeMenu(refs: refs, edit: edit)
            } primaryAction: { refs in
                if let r = refs.first { edit.requestEdit(r) }
            }
            .onDeleteCommand {
                if let r = ui.selection, !ui.searchFieldFocused { edit.requestDelete(r) }
            }
            .onKeyPress(.return) {
                ui.showInspector = true
                return .handled
            }
            .onKeyPress(.space) {
                ui.showInspector = true
                return .handled
            }
    }
}

/// 右鍵選單（收入頁自己的；不動總覽的 MacRecentMenu）
struct MacIncomeMenu: View {
    let refs: Set<MacEntryRef>
    let edit: MacEditCenter

    var body: some View {
        if let r = refs.first {
            Button("編輯") { edit.requestEdit(r) }
                .disabled(!edit.canEdit(r))
            Button("刪除…", role: .destructive) { edit.requestDelete(r) }
                .disabled(!edit.canDelete(r))
        }
    }
}
