// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.644 mac4 G2] 固定支出頁（頭、膠囊、時間軸、分組表格、詳情；judge_mac §R8；brief §2 G2 第 2 條）。
//
// • 跟 Mac 3 變動支出頁同一個骨架：頭固定高 250 的一般 View；Table 在下面撐滿，不放進捲動容器、外面不包型別抹除；
//   這頁的圖只有詳情欄的金額走勢（MacFixedChart.swift）。
// • 數字由 MacFixedScreen.make 一次算完（同一個 now、Calendar.current）；body 只排版、不寫 store。
// • 時間軸：每天一格，只有 .help（滑鼠停著看那天扣什麼），點了不選（格子裡沒有按鈕、點擊手勢）。
// • Table：Table(of:selection:sortOrder:)，8 支欄＋rows 一組一個 MacFixedGroupRows（Section＋TableRow）；
//   欄每支一個 private func、回傳型別寫死；內容閉包只放一個具名 Cell；builder 裡不寫 if；修飾器包成 MacFixedTableActions。
//   sortOrder 空＝照 iPhone 一類一組；點過欄名＝整串一組，篩選列出現〔回到分組〕。
// • 選取守門（sim4: guard4#1）：一個 MacFixedGuardKey、一個 .onChange(of: key) { _, new in }；寫 ui 一律在 .onChange 裡。
// • 這頁沒有搜尋、分類篩選、月份切換（iPhone 固定支出頁也沒有）；沒有 ⌘C。

import SwiftUI

struct MacFixedPage: View {
    @EnvironmentObject private var money: MacMoneyStore
    @EnvironmentObject private var ui: MacUIState
    @EnvironmentObject private var edit: MacEditCenter
    /// 空＝照 iPhone 分組；點過欄名＝整串一組
    @State private var sortOrder: [MacFixedSort] = []
    /// 「顯示已停止」預設勾（不存 UserDefaults）
    @State private var showEnded: Bool = true

    var body: some View {
        let screen: MacFixedScreen = MacFixedScreen.make(money: money, showEnded: showEnded, order: sortOrder,
                                                         now: Date(), calendar: .current)
        let key = MacFixedGuardKey(selection: ui.selection, rowIDs: screen.rowIDs, showEnded: showEnded,
                                   sorted: !sortOrder.isEmpty)
        MacFixedLayout(screen: screen, showEnded: $showEnded, sortOrder: $sortOrder, ui: ui, edit: edit)
            .navigationSubtitle(screen.subtitle)
            .modifier(MacFixedSelectionGuard(key: key, ui: ui))
    }
}

// MARK: - 這一頁要的東西（一次算完）

struct MacFixedScreen {
    let board: MacFixedBoardData
    let header: MacFixedHeader
    let chips: [MacFixedChip]
    let railDays: [MacFixedRailDay]
    let railLabel: String
    let groups: [MacFixedGroupSection]
    let rowIDs: [MacEntryRef]
    /// 篩選列右邊「24 筆」
    let countText: String
    /// 有任何一筆固定支出（沒有＝「還沒有固定支出」）
    let hasFixed: Bool
    /// 副標「2026 年 11 月」
    let subtitle: String

    @MainActor
    static func make(money: MacMoneyStore, showEnded: Bool, order: [MacFixedSort], now: Date,
                     calendar: Calendar) -> MacFixedScreen {
        let board = MacFixedBoardData.build(money: money, now: now, calendar: calendar)
        let groups = MacFixedTable.groups(money: money, showEnded: showEnded, order: order, now: now, calendar: calendar)
        let rows: [MacFixedRow] = groups.flatMap { g in g.rows }
        let ids: [MacEntryRef] = rows.map { r in r.id }
        let subtitle = "\(calendar.component(.year, from: now)) 年 \(board.month) 月"
        return MacFixedScreen(board: board, header: MacFixedHeadline.header(board), chips: MacFixedHeadline.chips(board),
                              railDays: MacFixedSchedule.railDays(board), railLabel: MacFixedSchedule.railLabel(board),
                              groups: groups, rowIDs: ids, countText: MacFixedTable.countText(groups),
                              hasFixed: board.hasFixed, subtitle: subtitle)
    }
}

// MARK: - 選取守門（一個 key、一個 .onChange）

struct MacFixedGuardKey: Equatable {
    let selection: MacEntryRef?
    let rowIDs: [MacEntryRef]
    let showEnded: Bool
    let sorted: Bool
}

struct MacFixedSelectionGuard: ViewModifier {
    /// 這次畫出來的選取、列、顯示已停止、有沒有點過欄名（onChange 拿到新的那份）
    let key: MacFixedGuardKey
    @ObservedObject var ui: MacUIState

    func body(content: Content) -> some View {
        content
            .onChange(of: key) { _, new in
                adjudicate(new)
            }
    }

    // sim4: guard4#1 選到的不在列裡（藏起已停止、iPhone 刪了、選到變動支出或收入）→ 清選取；在列裡或沒選 → 不動
    private func adjudicate(_ new: MacFixedGuardKey) {
        guard let sel = new.selection, !new.rowIDs.contains(sel) else { return }
        ui.selection = nil
    }
}

// MARK: - 整頁版面

struct MacFixedLayout: View {
    let screen: MacFixedScreen
    @Binding var showEnded: Bool
    @Binding var sortOrder: [MacFixedSort]
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter

    var body: some View {
        VStack(spacing: 0) {
            MacFixedHead(screen: screen)
                .frame(height: 250)
            Divider()
            MacFixedFilterBar(showEnded: $showEnded, sortOrder: $sortOrder, count: screen.countText)
            Divider()
            MacFixedTableArea(screen: screen, showEnded: $showEnded, sortOrder: $sortOrder, ui: ui, edit: edit)
        }
    }
}

// MARK: - 頭：日期行＋膠囊、標題、大字、一句話｜膠囊直排；下面扣款時間軸

struct MacFixedHead: View {
    let screen: MacFixedScreen

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 20) {
                MacFixedSummary(header: screen.header)
                    .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)
                MacFixedChipColumn(chips: screen.chips)
                    .frame(minWidth: 200, alignment: .topLeading)
            }
            Spacer(minLength: 0)
            MacFixedRail(days: screen.railDays, label: screen.railLabel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MacFixedSummary: View {
    let header: MacFixedHeader

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MacFixedDateLine(header: header)
            Text(header.label)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            MacVariableBigNumber(text: header.big)
            MacVariableSmallText(text: header.line, font: .callout)
        }
    }
}

/// 「11 月・3 筆扣款　［占收入 49%］」（沒收入或沒固定支出就沒有膠囊）
struct MacFixedDateLine: View {
    let header: MacFixedHeader

    var body: some View {
        HStack(spacing: 8) {
            Text(header.date)
                .font(.callout)
                .monospacedDigit()
            MacFixedCapsule(text: header.capsule)
        }
    }
}

struct MacFixedCapsule: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.caption)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
    }
}

/// 頭右：下一站、年度預估、訂閱、貸款還要繳、節稅（有才列，直排）
struct MacFixedChipColumn: View {
    let chips: [MacFixedChip]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(chips) { chip in
                MacFixedChipView(chip: chip)
            }
        }
    }
}

struct MacFixedChipView: View {
    let chip: MacFixedChip

    var body: some View {
        Label(chip.label + " " + chip.value, systemImage: chip.icon)
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    /// warn 橘、good 綠（照 iPhone 膠囊的 tone）
    private var color: Color {
        switch chip.tone {
        case .warn: return Color.orange
        case .good: return Color.green
        case .neutral: return Color.primary
        }
    }
}

// MARK: - 扣款時間軸（1 號到月底；只有 .help，點了不選）

struct MacFixedRail: View {
    let days: [MacFixedRailDay]
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text("1")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
            MacFixedRailTrack(days: days)
            Text(lastDay)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var lastDay: String { "\(days.count)" }
}

struct MacFixedRailTrack: View {
    let days: [MacFixedRailDay]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { d in
                MacFixedRailCell(day: d)
            }
        }
    }
}

/// 一天一格：軸線＋點（過去灰實心、下一站 accent 實心大一號、之後 accent 空心）＋今天的旗；滑鼠停著看那天扣什麼
struct MacFixedRailCell: View {
    let day: MacFixedRailDay

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(height: 2)
            MacFixedRailMark(day: day)
        }
        .frame(maxWidth: .infinity, minHeight: 30)
        .contentShape(Rectangle())
        .help(day.help)
    }
}

struct MacFixedRailMark: View {
    let day: MacFixedRailDay

    var body: some View {
        ZStack {
            MacFixedRailDot(station: day.station)
            if day.isToday {
                Image(systemName: "flag.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                    .offset(y: -11)
            }
        }
    }
}

struct MacFixedRailDot: View {
    let station: MacFixedRailStation?

    var body: some View {
        if let s = station {
            if s.isNext {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
            } else if s.past {
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
            } else {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - 篩選列：☑ 顯示已停止｜〔回到分組〕（點過欄名才出現）｜筆數

struct MacFixedFilterBar: View {
    @Binding var showEnded: Bool
    @Binding var sortOrder: [MacFixedSort]
    let count: String

    var body: some View {
        HStack(spacing: 12) {
            Toggle("顯示已停止", isOn: $showEnded)
                .toggleStyle(.checkbox)
            if !sortOrder.isEmpty {
                Button("回到分組") { sortOrder = [] }
                    .help("照 iPhone 一類一組排回來")
            }
            Spacer(minLength: 8)
            Text(count)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - 表格區：沒有固定支出／全部都已停止（藏起來了）／表格

struct MacFixedTableArea: View {
    let screen: MacFixedScreen
    @Binding var showEnded: Bool
    @Binding var sortOrder: [MacFixedSort]
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter

    var body: some View {
        if !screen.hasFixed {
            MacFixedEmptyNote()
        } else if screen.groups.isEmpty {
            MacFixedAllEnded(showEnded: $showEnded)
        } else {
            MacFixedTableView(groups: screen.groups, sortOrder: $sortOrder, ui: ui, edit: edit)
        }
    }
}

struct MacFixedEmptyNote: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("還沒有固定支出")
            Text("按 ⌘N 記一筆（選〔固定〕）")
                .font(.callout)
        }
        .foregroundStyle(Color.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 「顯示已停止」關掉後一列都沒有（按鈕事件裡改狀態）
struct MacFixedAllEnded: View {
    @Binding var showEnded: Bool

    var body: some View {
        VStack(spacing: 10) {
            Text("全部都已停止")
                .foregroundStyle(Color.secondary)
            Button("顯示已停止") { showEnded = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 8 欄表格（一類一組；§P／§Q Table 防超時）

struct MacFixedTableView: View {
    let groups: [MacFixedGroupSection]
    @Binding var sortOrder: [MacFixedSort]
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter

    var body: some View {
        Table(of: MacFixedRow.self, selection: $ui.selection, sortOrder: $sortOrder) {
            titleColumn()
            categoryColumn()
            periodColumn()
            amountColumn()
            monthlyColumn()
            nextDueColumn()
            payColumn()
            statusColumn()
        } rows: {
            ForEach(groups) { g in MacFixedGroupRows(group: g) }
        }
        .modifier(MacFixedTableActions(ui: ui, edit: edit))
    }

    private func titleColumn() -> TableColumn<MacFixedRow, MacFixedSort, MacFixedTitleCell, Text> {
        TableColumn(Text("項目"), value: \MacFixedRow.title) { row in
            MacFixedTitleCell(row: row)
        }
        .width(min: 90, ideal: 170, max: 320)
    }

    private func categoryColumn() -> TableColumn<MacFixedRow, MacFixedSort, MacFixedCategoryCell, Text> {
        TableColumn(Text("分類"), value: \MacFixedRow.category) { row in
            MacFixedCategoryCell(row: row)
        }
        .width(min: 56, ideal: 110, max: 200)
    }

    private func periodColumn() -> TableColumn<MacFixedRow, MacFixedSort, MacFixedPeriodCell, Text> {
        TableColumn(Text("週期"), value: \MacFixedRow.periodRank) { row in
            MacFixedPeriodCell(row: row)
        }
        .width(min: 36, ideal: 48, max: 80)
    }

    private func amountColumn() -> TableColumn<MacFixedRow, MacFixedSort, MacFixedAmountCell, Text> {
        TableColumn(Text("金額"), value: \MacFixedRow.amount) { row in
            MacFixedAmountCell(row: row)
        }
        .width(min: 72, ideal: 120, max: 220)
    }

    private func monthlyColumn() -> TableColumn<MacFixedRow, MacFixedSort, MacFixedMonthlyCell, Text> {
        TableColumn(Text("月均"), value: \MacFixedRow.monthly) { row in
            MacFixedMonthlyCell(row: row)
        }
        .width(min: 56, ideal: 90, max: 160)
    }

    private func nextDueColumn() -> TableColumn<MacFixedRow, MacFixedSort, MacFixedNextDueCell, Text> {
        TableColumn(Text("下次扣款"), value: \MacFixedRow.nextDue) { row in
            MacFixedNextDueCell(row: row)
        }
        .width(min: 64, ideal: 110, max: 180)
    }

    private func payColumn() -> TableColumn<MacFixedRow, MacFixedSort, MacFixedPayCell, Text> {
        TableColumn(Text("扣款方式"), value: \MacFixedRow.payText) { row in
            MacFixedPayCell(row: row)
        }
        .width(min: 40, ideal: 72, max: 120)
    }

    private func statusColumn() -> TableColumn<MacFixedRow, MacFixedSort, MacFixedStatusCell, Text> {
        TableColumn(Text("狀態"), value: \MacFixedRow.statusRank) { row in
            MacFixedStatusCell(row: row)
        }
        .width(min: 60, ideal: 140)
    }
}

/// 一類一組：Section 的 header 是組頭（選不到），裡面每列一個 TableRow
struct MacFixedGroupRows: TableRowContent {
    typealias TableRowValue = MacFixedRow
    let group: MacFixedGroupSection

    var tableRowBody: some TableRowContent<MacFixedRow> {
        Section {
            ForEach(group.rows) { row in
                TableRow(row)
            }
        } header: {
            MacFixedGroupHeader(group: group)
        }
    }
}

// MARK: - 表格的右鍵、連按兩下、⌫、Return／Space（沒有 ⌘C）

struct MacFixedTableActions: ViewModifier {
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter

    func body(content: Content) -> some View {
        content
            .contextMenu(forSelectionType: MacEntryRef.self) { refs in
                MacFixedMenu(refs: refs, edit: edit)
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

/// 右鍵選單：〔編輯〕〔停止扣款…〕〔刪除…〕（組頭、空白處是空集合 → 不顯示項目）
struct MacFixedMenu: View {
    let refs: Set<MacEntryRef>
    let edit: MacEditCenter

    var body: some View {
        if let r = refs.first {
            Button("編輯") { edit.requestEdit(r) }
                .disabled(!edit.canEdit(r))
            Button("停止扣款…") { edit.requestStop(r) }
                .disabled(!edit.canStop(r))
            Button("刪除…", role: .destructive) { edit.requestDelete(r) }
                .disabled(!edit.canDelete(r))
        }
    }
}

// MARK: - 詳情欄（MacInspector 選到固定支出時叫這個；下面接 MacInspectorEditSection）

/// 基本資料 → 貸款進度 → 儲蓄險（只列支出上有的）→ 金額走勢（＋金額紀錄）→ 備註
struct MacFixedInspector: View {
    let expense: Expense
    @ObservedObject var money: MacMoneyStore

    var body: some View {
        let info = MacFixedInspectorInfo.make(expense, money: money, now: Date(), calendar: .current)
        MacFixedFactsSection(title: info.title, rows: info.facts)
        MacFixedLoanSection(loan: info.loan)
        MacFixedSavingsSection(rows: info.savings)
        MacFixedTrendSection(info: info)
        MacFixedNoteSection(note: info.note)
    }
}

struct MacFixedFactsSection: View {
    let title: String
    let rows: [MacFixedInfoRow]

    var body: some View {
        Section {
            ForEach(rows) { row in
                LabeledContent(row.label, value: row.value)
            }
        } header: {
            Text(title)
                .font(.headline)
        }
    }
}

struct MacFixedLoanSection: View {
    let loan: MacFixedLoanInfo?

    var body: some View {
        if let loan {
            Section("貸款進度") {
                ProgressView(value: loan.progressValue, total: loan.progressTotal)
                MacFixedLoanSpan(loan: loan)
                ForEach(loan.rows) { row in
                    LabeledContent(row.label, value: row.value)
                }
            }
        }
    }
}

/// 進度條下面「2023/11/5 ─ 15% ─ 2043/11/5」
struct MacFixedLoanSpan: View {
    let loan: MacFixedLoanInfo

    var body: some View {
        HStack(spacing: 4) {
            Text(loan.startText)
            Spacer(minLength: 4)
            Text(loan.percentText)
            Spacer(minLength: 4)
            Text(loan.endText)
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(Color.secondary)
    }
}

struct MacFixedSavingsSection: View {
    let rows: [MacFixedInfoRow]

    var body: some View {
        if !rows.isEmpty {
            Section("儲蓄險") {
                ForEach(rows) { row in
                    LabeledContent(row.label, value: row.value)
                }
                Text("期數、到期日、預估領回請在 iPhone 看")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
        }
    }
}

struct MacFixedTrendSection: View {
    let info: MacFixedInspectorInfo

    var body: some View {
        Section("金額走勢") {
            MacFixedTrendGraph(trend: info.trend)
            ForEach(info.history) { h in
                LabeledContent(h.date, value: h.amount)
            }
            MacVariableSmallText(text: info.historyMore, font: .caption)
        }
    }
}

/// 2 筆以上畫圖（實線＋虛線預測），不到 2 筆寫一句怎麼記
struct MacFixedTrendGraph: View {
    let trend: MacFixedTrend

    var body: some View {
        if trend.actual.count >= 2 {
            MacFixedTrendChart(trend: trend)
                .frame(height: 140)
        } else {
            Text("改金額時選〔從今天起〕就會記下一筆，記滿兩筆會畫出走勢和虛線預測")
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MacFixedNoteSection: View {
    let note: String

    var body: some View {
        Section("備註") {
            Text(note)
        }
    }
}
