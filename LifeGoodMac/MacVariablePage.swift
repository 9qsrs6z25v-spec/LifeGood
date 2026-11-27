// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.642 mac3 G2] 變動支出頁（看板、花在哪裡、一天一組的表格、月份、搜尋、選取守門；judge_mac §Q8；brief §2 G2 第 9～16 條）。
//
// • 跟 Mac 2 收入頁同一個骨架：頭固定高 250 的一般 View；Table 在下面撐滿，不放進捲動容器、外面不包 AnyView；不用 Charts。
// • 數字由 MacVariableScreen.make 一次算完（同一個 now、Calendar.current）；body 只排版、不寫 store。
// • Table（scout_macui §5 十二條＋列版四條）：Table(of:selection:sortOrder:)，9 支欄＋rows 一天一個 MacVariableDayRows（Section＋TableRow）；
//   欄每支一個 private func、回傳型別寫死；內容閉包只放一個具名 Cell；builder 裡不寫 if；修飾器包成 MacVariableTableActions。
// • 選取守門（sim3: guard3#1～#3）：一個 MacVariableGuardKey、一個 .onChange(of: key) { old, new in }；寫 ui 一律在 .onChange 裡。
// • 月份按鈕不綁快捷鍵（⌘[ ⌘] ⌘T 只在選單綁一次）；搜尋字只放 @State，不存、不寫 log、不做建議。

import SwiftUI

struct MacVariablePage: View {
    @EnvironmentObject private var money: MacMoneyStore
    @EnvironmentObject private var ui: MacUIState
    @EnvironmentObject private var edit: MacEditCenter
    @State private var categoryFilter: VariableCategory? = nil
    @State private var query: String = ""
    @State private var sortOrder: [MacVariableSort] = [MacVariableSort(\MacVariableRow.date, order: .reverse)]
    @FocusState private var searchFocused: Bool

    var body: some View {
        let now = Date()
        let screen: MacVariableScreen = MacVariableScreen.make(money: money, ui: ui, query: query, category: categoryFilter,
                                                               order: sortOrder, now: now, calendar: .current)
        let key = MacVariableGuardKey(selection: ui.selection, rowIDs: screen.rowIDs, month: ui.variableMonth, query: query,
                                      category: categoryFilter, searchAll: ui.variableSearchAll)
        MacVariableLayout(screen: screen, category: $categoryFilter, sortOrder: $sortOrder, ui: ui, edit: edit)
            .navigationSubtitle(screen.subtitle)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    MacVariableStepButton(step: -1, ui: ui, money: money)
                    MacVariableStepButton(step: 1, ui: ui, money: money)
                    MacVariableTodayButton(ui: ui, money: money)
                }
            }
            .searchable(text: $query, placement: .toolbar, prompt: "搜尋名稱、備註、分類、地點")
            .searchFocused($searchFocused)
            .modifier(MacVariableSelectionGuard(key: key, focus: $searchFocused, ui: ui, money: money))
            .onAppear { takeCategoryRequest() }
    }

    /// [v25.648 mac7] 總覽分類卡跳過來：讀到就清、只看那一類（不存 UserDefaults；sim7: jump7#2）
    private func takeCategoryRequest() {
        guard let c = ui.variableCategoryRequest else { return }
        ui.variableCategoryRequest = nil
        categoryFilter = c
    }
}

// MARK: - 這一頁要的東西（一次算完）

struct MacVariableScreen {
    let board: MacVariableBoardData
    let header: MacVariableHeader
    /// 跟近 3 個月同期比那一句（只有本月才有）
    let line: String?
    let chips: [MacVariableChip]
    let days: [MacVariableDay]
    let rowIDs: [MacEntryRef]
    /// 篩選列右邊「86 筆・你的份合計 NT$2.3萬」
    let subtotal: String
    /// 有任何一筆變動支出（沒有＝「還沒有變動支出，按 ⌘N 記一筆」）
    let hasVariable: Bool
    /// 搜尋框有字（去頭尾空白）
    let hasQuery: Bool
    let isCurrent: Bool
    /// 「2026 年 10 月」
    let monthTitle: String
    /// 副標「2026 年 11 月」／搜全部月份（而且有搜尋字，同 days 的 everyMonth）時「全部月份」
    let subtitle: String
    /// 「花在哪裡」的「其他」那列能不能點（sim3: shop#1）
    let otherClickable: Bool

    @MainActor
    static func make(money: MacMoneyStore, ui: MacUIState, query: String, category: VariableCategory?,
                     order: [MacVariableSort], now: Date, calendar: Calendar) -> MacVariableScreen {
        let current = MacVariableMonth.start(of: now, calendar: calendar)
        let month = ui.variableMonth ?? current
        let isCurrent = MacVariableMonth.start(of: month, calendar: calendar) == current
        // sim3: month#3 不是本月：now 傳那個月最後一天 23:59:59（只顯示只看「哪個月」的 6 格）
        let boardNow = MacVariableMonth.boardNow(month: month, now: now, calendar: calendar)
        let board = MacVariableBoard.build(money: money, now: boardNow, calendar: calendar)
        let days = MacVariableTable.days(money: money, month: month, query: query, category: category,
                                         searchAll: ui.variableSearchAll, order: order, now: now, calendar: calendar)
        let rows: [MacVariableRow] = days.flatMap { d in d.rows }
        let hasQuery = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let monthTitle = MacVariableMonth.title(month, calendar: calendar)
        return MacVariableScreen(
            board: board,
            header: MacVariableHeadline.header(board, month: month, now: now, calendar: calendar),
            line: isCurrent ? MacVariableHeadline.line(board) : nil,
            chips: MacVariableHeadline.chips(board, current: isCurrent),
            days: days,
            rowIDs: rows.map { r in r.id },
            subtotal: MacVariableTable.subtotal(rows, filtering: hasQuery || category != nil),
            hasVariable: money.expenses.contains { e in e.expenseType == .variable },
            hasQuery: hasQuery,
            isCurrent: isCurrent,
            monthTitle: monthTitle,
            subtitle: ui.variableSearchAll && hasQuery ? "全部月份" : monthTitle,
            otherClickable: MacVariableBoard.otherIsPure(money: money, shops: board.shops, month: month, calendar: calendar))
    }
}

// MARK: - 選取守門（一個 key、一個 .onChange）

struct MacVariableGuardKey: Equatable {
    let selection: MacEntryRef?
    let rowIDs: [MacEntryRef]
    let month: Date?
    let query: String
    let category: VariableCategory?
    let searchAll: Bool
}

struct MacVariableSelectionGuard: ViewModifier {
    /// 這次畫出來的選取、列、月份、搜尋、篩選（onChange 拿到新舊兩份）
    let key: MacVariableGuardKey
    let focus: FocusState<Bool>.Binding
    @ObservedObject var ui: MacUIState
    let money: MacMoneyStore

    func body(content: Content) -> some View {
        content
            .onChange(of: key) { old, new in
                adjudicate(old: old, new: new)
            }
            .onChange(of: focus.wrappedValue) { _, f in ui.searchFieldFocused = f }
            .onChange(of: ui.searchRequest) { _, _ in focus.wrappedValue = true }
    }

    private func adjudicate(old: MacVariableGuardKey, new: MacVariableGuardKey) {
        // 搜尋字清空 →「搜全部月份」歸零
        if new.query.trimmingCharacters(in: .whitespaces).isEmpty && ui.variableSearchAll {
            ui.variableSearchAll = false
        }
        // sim3: guard3#1 選到的在列裡（或沒選）→ 不動
        guard let sel = new.selection, !new.rowIDs.contains(sel) else { return }
        // sim3: guard3#2 選取本身變了（⌘N 存完選到別月那筆）而且不在列裡：是變動支出、沒有搜尋字、分類篩選是全部或符合
        //                → 翻到那筆的月份（本月設 nil）；其餘 → 清選取
        if old.selection != new.selection {
            if let month = jumpMonth(sel, key: new) {
                let current = MacVariableMonth.start(of: Date(), calendar: .current)
                ui.variableMonth = month == current ? nil : month
            } else {
                ui.selection = nil
            }
            return
        }
        // sim3: guard3#3 選取沒變、別的變了（⌘[、搜尋、篩選、搜全部月份、改日期那列不見）→ 清選取（不翻回去）
        ui.selection = nil
    }

    /// 那筆的月初；不是變動支出、有搜尋字、分類篩選不符 → nil
    private func jumpMonth(_ sel: MacEntryRef, key: MacVariableGuardKey) -> Date? {
        guard case .expense(let id) = sel, let e = money.expense(id), e.expenseType == .variable else { return nil }
        guard key.query.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if let c = key.category, e.variableCategory != c { return nil }
        return MacVariableMonth.start(of: e.date, calendar: .current)
    }
}

// MARK: - 工具列：〔‹〕〔›〕〔本月〕（不綁快捷鍵；反灰條件同選單）

struct MacVariableStepButton: View {
    let step: Int
    @ObservedObject var ui: MacUIState
    @ObservedObject var money: MacMoneyStore

    var body: some View {
        Button {
            ui.stepVariableMonth(step, money: money, now: Date(), calendar: .current)
        } label: {
            Label(title, systemImage: step < 0 ? "chevron.left" : "chevron.right")
        }
        .help(hint)
        .disabled(!ui.canStepVariableMonth(step, money: money, now: Date(), calendar: .current))
    }

    private var title: String { step < 0 ? "上個月" : "下個月" }
    private var hint: String { step < 0 ? "上個月（⌘[）" : "下個月（⌘]）" }
}

struct MacVariableTodayButton: View {
    @ObservedObject var ui: MacUIState
    @ObservedObject var money: MacMoneyStore

    var body: some View {
        Button("本月") { ui.variableMonth = nil }
            .help("回到本月（⌘T）")
            .disabled(!ui.canReturnVariableMonth(money: money, now: Date(), calendar: .current))
    }
}

// MARK: - 整頁版面

struct MacVariableLayout: View {
    let screen: MacVariableScreen
    @Binding var category: VariableCategory?
    @Binding var sortOrder: [MacVariableSort]
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter

    var body: some View {
        VStack(spacing: 0) {
            MacVariableHead(screen: screen, category: $category)
                .frame(height: 250)
            Divider()
            MacVariableFilterBar(category: $category, ui: ui, showSearchAll: screen.hasQuery, subtotal: screen.subtotal)
            Divider()
            MacVariableTableArea(screen: screen, category: $category, sortOrder: $sortOrder, ui: ui, edit: edit)
        }
    }
}

// MARK: - 頭：日期行、膠囊、標題、大字、一句話、膠囊列、分帳小字｜花在哪裡

struct MacVariableHead: View {
    let screen: MacVariableScreen
    @Binding var category: VariableCategory?

    // [v25.645 mac5] 看板自己有 12pt 內距：原本直向 12 拿掉、橫向 16 改 4（看板內距合起來一樣 16）、看板外直向 6，
    // 頭部 250 高才裝得下 36pt 大字＋26pt 膠囊（不然看板下緣會壓到下面的篩選列）
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            MacVariableSummary(screen: screen)
                .frame(minWidth: 240, idealWidth: 320, maxWidth: 420, alignment: .leading)
            MacVariableShops(shops: screen.board.shops, otherClickable: screen.otherClickable, category: $category)
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 4)
        .macBoard(.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MacVariableSummary: View {
    let screen: MacVariableScreen

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MacVariableDateLine(header: screen.header)
            MacHeroLabel(text: screen.header.label)
            MacVariableBigNumber(text: screen.header.big)
            MacVariableSmallText(text: screen.line, font: .callout)
            MacVariableChipRow(chips: screen.chips)
                .padding(.top, 4)
            MacVariableSmallText(text: screen.board.splitNote, font: .caption)
            MacVariableSmallText(text: screen.header.note, font: .caption)
        }
    }
}

/// 「11 月・第 23 天　［本月 86 筆］」（不是本月：只有「［86 筆］」）
struct MacVariableDateLine: View {
    let header: MacVariableHeader
    @Environment(\.colorScheme) private var scheme

    // [v25.645 mac5 G1b] 膠囊換白膠囊（cellFill 底、cellStroke 0.75 框、capsuleText 字）
    var body: some View {
        let p = MacPalette(scheme)
        HStack(spacing: 8) {
            if !header.date.isEmpty {
                Text(header.date)
                    .font(.callout)
                    .monospacedDigit()
            }
            Text(header.capsule)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(p.capsuleText)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(p.cellFill, in: Capsule())
                .overlay(Capsule().stroke(p.cellStroke, lineWidth: 0.75))
        }
    }
}

struct MacVariableBigNumber: View {
    let text: String

    // [v25.645 mac5 G1b] 36pt 大字；只有字、沒有數值，換月份時直接換、不滾數字（brief T2、L14；MacFixedPage 也借）
    var body: some View {
        MacHeroNumber(text: text, value: 0)
    }
}

/// 有字才出現的灰色小字（一句話、分帳小字、以前的月份那行）
struct MacVariableSmallText: View {
    let text: String?
    let font: Font

    var body: some View {
        if let text {
            Text(text)
                .font(font)
                .foregroundStyle(Color.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 膠囊：一行兩顆（視窗窄也放得下）
struct MacVariableChipRow: View {
    let chips: [MacVariableChip]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(pairStarts, id: \.self) { start in
                MacVariableChipPair(chips: Array(chips[start..<min(start + 2, chips.count)]))
            }
        }
    }

    private var pairStarts: [Int] {
        Array(stride(from: 0, to: chips.count, by: 2))
    }
}

struct MacVariableChipPair: View {
    let chips: [MacVariableChip]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(chips) { chip in
                MacVariableChipView(chip: chip)
            }
        }
    }
}

struct MacVariableChipView: View {
    let chip: MacVariableChip

    // [v25.645 mac5 G1b] 白膠囊（MacPill）；圖示照舊
    var body: some View {
        MacPill(icon: icon, label: chip.label, value: chip.value, tone: chip.good ? .good : .neutral)
    }

    /// 圖示照 iPhone 看板（MoneyBoards.swift:327-350）
    private var icon: String {
        switch chip.label {
        case "今天": return "sun.max.fill"
        case "日均": return "chart.line.uptrend.xyaxis"
        case "最大一筆": return "crown.fill"
        case "最常去": return "mappin.and.ellipse"
        case "無消費": return "leaf.fill"
        default: return "circle"
        }
    }
}

/// 右邊「花在哪裡」：最多五類，點一類＝分類篩選
struct MacVariableShops: View {
    let shops: [MacVariableShop]
    let otherClickable: Bool
    @Binding var category: VariableCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("花在哪裡")
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            if shops.isEmpty {
                Text("沒有花費")
                    .font(.callout)
                    .foregroundStyle(Color.secondary)
            } else {
                ForEach(shops) { shop in
                    MacVariableShopRow(shop: shop, clickable: shop.category != .other || otherClickable, category: $category)
                }
            }
        }
    }
}

struct MacVariableShopRow: View {
    let shop: MacVariableShop
    /// 「其他」那列有併進別類或沒分類的 → 不給點（sim3: shop#1）
    let clickable: Bool
    @Binding var category: VariableCategory?

    var body: some View {
        Button {
            category = shop.category
        } label: {
            MacVariableShopLabel(shop: shop, selected: category == shop.category)
        }
        .buttonStyle(.plain)
        .disabled(!clickable)
        .help(hint)
    }

    private var hint: String {
        clickable ? "只看" + shop.category.rawValue : shop.category.rawValue + "含併進來的分類或沒分類的，請用分類選單"
    }
}

struct MacVariableShopLabel: View {
    let shop: MacVariableShop
    let selected: Bool

    // [v25.645 mac5 G1b] 名稱前一顆 20pt 分類色圖示圓；ProgressView 換 MacMeterBar
    var body: some View {
        HStack(spacing: 8) {
            MacIconBadge(icon: shop.category.icon, top: shop.category.accentColor,
                         bottom: shop.category.accentColor.opacity(0.7), size: 20, solid: false)
            Text(shop.category.rawValue)
                .fontWeight(selected ? Font.Weight.semibold : Font.Weight.regular)
                .lineLimit(1)
                .frame(width: 56, alignment: .leading)
            Text(MacText.money(shop.amount))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 96, alignment: .trailing)
            Text(WidgetMoneyFormat.percent(shop.share))
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
                .frame(width: 44, alignment: .trailing)
            MacMeterBar(fraction: min(max(shop.share, 0), 1), tint: shop.category.accentColor)
                .frame(maxWidth: 220)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 篩選列：分類｜搜全部月份（有搜尋字才出現）｜小計

struct MacVariableFilterBar: View {
    @Binding var category: VariableCategory?
    @ObservedObject var ui: MacUIState
    let showSearchAll: Bool
    let subtotal: String

    // sim7: tbl7#18 小計換合計膠囊（變動橘）；分類、搜全部月份照舊
    var body: some View {
        HStack(spacing: 12) {
            MacVariableCategoryPicker(selection: $category)
            if showSearchAll {
                Toggle("搜全部月份", isOn: $ui.variableSearchAll)
                    .toggleStyle(.checkbox)
            }
            Spacer(minLength: 8)
            MacTableSumPill(text: subtotal, tint: MacPageTheme.orange.top)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

/// 分類篩選（只篩顯示、不存）：全部＋14 類，字用 rawValue
struct MacVariableCategoryPicker: View {
    @Binding var selection: VariableCategory?

    var body: some View {
        Picker("分類", selection: $selection) {
            Text("全部").tag(VariableCategory?.none)
            ForEach(VariableCategory.allCases) { c in
                Text(c.rawValue).tag(VariableCategory?.some(c))
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help("只看某一類變動支出")
    }
}

// MARK: - 表格區：沒有變動支出／篩完是空的／表格

struct MacVariableTableArea: View {
    let screen: MacVariableScreen
    @Binding var category: VariableCategory?
    @Binding var sortOrder: [MacVariableSort]
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter

    var body: some View {
        if !screen.hasVariable {
            MacVariableEmptyNote(text: "還沒有變動支出，按 ⌘N 記一筆")
        } else if screen.days.isEmpty {
            MacVariableNoMatch(screen: screen, category: $category, ui: ui)
        } else {
            MacVariableTableView(days: screen.days, sortOrder: $sortOrder, ui: ui, edit: edit)
        }
    }
}

struct MacVariableEmptyNote: View {
    let text: String

    // sim7: tbl7#19 沒有變動支出：大圖示圓＋原字（變動橘）
    var body: some View {
        MacTableEmpty(icon: "cart.fill", tint: MacPageTheme.orange.top, title: text, detail: nil)
    }
}

/// 「2026 年 10 月沒有變動支出」＋〔回到本月〕／「這個月沒有符合的」＋〔搜全部月份〕／「沒有符合的」（按鈕事件裡改狀態）
struct MacVariableNoMatch: View {
    let screen: MacVariableScreen
    @Binding var category: VariableCategory?
    @ObservedObject var ui: MacUIState

    // sim7: tbl7#20 篩完是空的：放大鏡圓＋原字；三顆按鈕跟著頁面顏色、只改頁內狀態（判斷順序＝BASE）
    var body: some View {
        VStack(spacing: 12) {
            MacEmptyHint(icon: "magnifyingglass", tint: MacPageTheme.orange.top, title: text, detail: nil)
            if ui.variableSearchAll && screen.hasQuery {
                EmptyView()
            } else if screen.hasQuery {
                MacTableEmptyButton(title: "搜全部月份", tint: MacPageTheme.orange.bottom) { ui.variableSearchAll = true }
            } else if category != nil {
                MacTableEmptyButton(title: "看全部分類", tint: MacPageTheme.orange.bottom) { category = nil }
            } else if !screen.isCurrent {
                MacTableEmptyButton(title: "回到本月", tint: MacPageTheme.orange.bottom) { ui.variableMonth = nil }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var text: String {
        if ui.variableSearchAll && screen.hasQuery { return "沒有符合的" }
        if screen.hasQuery || category != nil { return "這個月沒有符合的" }
        return screen.monthTitle + "沒有變動支出"
    }
}

// MARK: - 9 欄表格（一天一組；scout_macui §5）

struct MacVariableTableView: View {
    let days: [MacVariableDay]
    @Binding var sortOrder: [MacVariableSort]
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter

    var body: some View {
        Table(of: MacVariableRow.self, selection: $ui.selection, sortOrder: $sortOrder) {
            timeColumn()
            titleColumn()
            categoryColumn()
            amountColumn()
            mineColumn()
            payColumn()
            withColumn()
            placeColumn()
            noteColumn()
        } rows: {
            ForEach(days) { day in MacVariableDayRows(day: day) }
        }
        .modifier(MacVariableTableActions(ui: ui, edit: edit, days: days))
    }

    private func timeColumn() -> TableColumn<MacVariableRow, MacVariableSort, MacVariableTimeCell, Text> {
        TableColumn(Text("時間"), value: \MacVariableRow.date) { row in
            MacVariableTimeCell(row: row)
        }
        .width(min: 48, ideal: 84, max: 140)
    }

    private func titleColumn() -> TableColumn<MacVariableRow, MacVariableSort, MacVariableTitleCell, Text> {
        TableColumn(Text("項目"), value: \MacVariableRow.title) { row in
            MacVariableTitleCell(row: row)
        }
        .width(min: 90, ideal: 170, max: 320)
    }

    private func categoryColumn() -> TableColumn<MacVariableRow, MacVariableSort, MacVariableCategoryCell, Text> {
        TableColumn(Text("分類"), value: \MacVariableRow.category) { row in
            MacVariableCategoryCell(row: row)
        }
        .width(min: 48, ideal: 90, max: 160)
    }

    private func amountColumn() -> TableColumn<MacVariableRow, MacVariableSort, MacVariableAmountCell, Text> {
        TableColumn(Text("金額"), value: \MacVariableRow.amount) { row in
            MacVariableAmountCell(row: row)
        }
        .width(min: 72, ideal: 110, max: 200)
    }

    private func mineColumn() -> TableColumn<MacVariableRow, MacVariableSort, MacVariableMineCell, Text> {
        TableColumn(Text("我的份"), value: \MacVariableRow.mine) { row in
            MacVariableMineCell(row: row)
        }
        .width(min: 56, ideal: 84, max: 140)
    }

    private func payColumn() -> TableColumn<MacVariableRow, MacVariableSort, MacVariablePayCell, Text> {
        TableColumn(Text("付款"), value: \MacVariableRow.payText) { row in
            MacVariablePayCell(row: row)
        }
        .width(min: 40, ideal: 64, max: 120)
    }

    private func withColumn() -> TableColumn<MacVariableRow, MacVariableSort, MacVariableWithCell, Text> {
        TableColumn(Text("同行"), value: \MacVariableRow.with) { row in
            MacVariableWithCell(row: row)
        }
        .width(min: 40, ideal: 90, max: 180)
    }

    private func placeColumn() -> TableColumn<MacVariableRow, MacVariableSort, MacVariablePlaceCell, Text> {
        TableColumn(Text("地點"), value: \MacVariableRow.place) { row in
            MacVariablePlaceCell(row: row)
        }
        .width(min: 48, ideal: 120, max: 240)
    }

    private func noteColumn() -> TableColumn<MacVariableRow, MacVariableSort, MacVariableNoteCell, Text> {
        TableColumn(Text("備註"), value: \MacVariableRow.note) { row in
            MacVariableNoteCell(row: row)
        }
        .width(min: 60, ideal: 180)
    }
}

/// 一天一組：Section 的 header 是組頭（選不到），裡面每列一個 TableRow
struct MacVariableDayRows: TableRowContent {
    typealias TableRowValue = MacVariableRow
    let day: MacVariableDay

    var tableRowBody: some TableRowContent<MacVariableRow> {
        Section {
            ForEach(day.rows) { row in
                TableRow(row)
            }
        } header: {
            MacVariableDayHeader(day: day)
        }
    }
}

// MARK: - 表格的右鍵、連按兩下、⌫、Return／Space、⌘C

struct MacVariableTableActions: ViewModifier {
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter
    let days: [MacVariableDay]

    func body(content: Content) -> some View {
        content
            .contextMenu(forSelectionType: MacEntryRef.self) { refs in
                MacVariableMenu(refs: refs, edit: edit)
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
            // ⌘C 用系統的（白名單組字：不帶同行、收受人、分帳、我的份）；沒選＝空陣列
            .copyable(MacVariableCopy.lines(selection: ui.selection, days: days))
    }
}

/// 右鍵選單（組頭、空白處是空集合 → 不顯示項目）；沒有〔拷貝這一筆〕
struct MacVariableMenu: View {
    let refs: Set<MacEntryRef>
    let edit: MacEditCenter

    var body: some View {
        if let r = refs.first {
            Button("編輯") { edit.requestEdit(r) }
                .disabled(!edit.canEdit(r))
            Button("複製成新的一筆") { edit.requestDuplicate(r) }
                .disabled(!edit.canDuplicate(r))
            Button("刪除…", role: .destructive) { edit.requestDelete(r) }
                .disabled(!edit.canDelete(r))
        }
    }
}
