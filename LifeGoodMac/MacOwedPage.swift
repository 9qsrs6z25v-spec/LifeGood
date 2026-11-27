// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.646 mac6 G2] 誰還欠我頁（judge_mac.md §T3-1、§T3-4、§T3-6、§T3-7）：看板、人卡片、〔還沒還｜還清了〕、每一頓表、工具列、表單。
//
// • 跟變動支出頁同一個骨架：body 裡 `let now = Date()` 算一次、MacOwedScreen.make 一次算完；body 只排版、不寫 store。
//   整頁 VStack(spacing: 10)；人卡片那條橫向 ScrollView 在看板裡、Table 外面上方；Table 不放進捲動容器、不包 AnyView。
// • Table（Mac 3 十二條＋Section 版）：Table(of:selection:sortOrder:)，5 支欄＋rows 一人一組 MacOwedPersonRows（Section＋TableRow）；
//   欄每支一個 private func、回傳型別寫死；內容閉包只放一個具名 Cell；builder 裡不寫 if；修飾器包成 MacOwedTableActions。
// • 選取守門：一個 MacOwedGuardKey、一個 .onChange(of: key) { old, new in }；寫 ui 一律在 onChange、按鈕事件裡。
// • 表單本身不寫：按〔記下來〕才 edit.requestRepay；〔改成還沒還〕確認框預設〔取消〕。edit 只用 repayBlock／requestRepay／
//   unrepayBlock／requestUnrepay／isBusy。⌘C 在這頁什麼都不複製（不加 copyable／onCopyCommand）；名字只在畫面。
// • 不准：refresh(、adopt(、MacCloudWriter、journal.、UserDefaults、Logger、print(、NSPasteboard、.copyable(、onCopyCommand、
//   .textSelection、.onDeleteCommand、accessibilityIdentifier、ShareLink、.badge(、GeometryReader、AnyView（§T3-10）。

import SwiftUI

struct MacOwedPage: View {
    @EnvironmentObject private var app: MacAppModel
    @EnvironmentObject private var money: MacMoneyStore
    @EnvironmentObject private var ui: MacUIState
    @EnvironmentObject private var edit: MacEditCenter
    @State private var tab: MacOwedTab = .unpaid
    /// 點到的人（nil＝全部）；不存本機鍵
    @State private var person: String? = nil
    /// 表格選到的那一頓（MacOwedRow.id＝"支出|人"；不直接綁 ui.selection：同一頓兩個人時支出 id 會撞）
    @State private var mealSelection: String? = nil
    @State private var sortOrder: [MacOwedSort] = [MacOwedSort(\MacOwedRow.date, order: .reverse)]
    @State private var repayAsk: MacOwedRepayAsk? = nil
    @State private var undoAsk: MacOwedUndoAsk? = nil
    /// 標完跳下一頓的那一列（那一次不動 ui.selection：詳情欄留在剛標的那筆）
    @State private var keepDetail: String? = nil

    var body: some View {
        let now = Date()
        let screen: MacOwedScreen = MacOwedScreen.make(book: money.owedBook, expenses: money.expenses, tab: tab,
                                                       person: person, now: now, calendar: .current)
        let groups: [MacOwedGroup] = MacOwedScreen.sorted(screen.groups, by: sortOrder)
        let picked: MacOwedPicked? = MacOwedScreen.pick(groups, id: mealSelection)
        let key: MacOwedGuardKey = MacOwedGuardKey.make(tab: tab, person: person, selection: mealSelection, groups: groups,
                                                        people: screen.people)
        MacOwedLayout(screen: screen, groups: groups, picked: picked, tab: $tab, person: $person, selection: $mealSelection,
                      sortOrder: $sortOrder, repayAsk: $repayAsk, undoAsk: $undoAsk, ui: ui, edit: edit)
            .modifier(MacOwedSelectionGuard(key: key, person: $person, selection: $mealSelection, keepDetail: $keepDetail, ui: ui))
            .sheet(item: $repayAsk) { a in
                MacOwedRepaySheet(ask: a).macStores(app)
            }
            .modifier(MacOwedUndoDialog(ask: $undoAsk, edit: edit))
    }
}

// MARK: - 一列、一組（Row 沒有名字欄位；組才有名字）

/// 每一頓表的一列（全 let；字在建列時算好）
struct MacOwedRow: Identifiable {
    /// ＝MacOwedMeal.id（"支出UUID|人UUID"）
    let id: String
    let expenseID: UUID
    let shareID: UUID
    /// 吃飯那天（排序用）
    let date: Date
    /// 今年「11/20」；不是今年「2025/12/3」
    let dateText: String
    /// 那頓（店名；沒打名字用分類）
    let title: String
    /// 分類色圓點（建列時算好）
    let dot: Color
    /// 刷卡金額（排序用）
    let total: Double
    let totalText: String
    /// 還沒還：還欠多少；還清了：還了多少
    let amount: Double
    let amountText: String
    let days: Int
    /// 「今天」「等了 6 天」／「已還 11/21・現金 ✓」
    let statusText: String
    /// 等了超過 30 天（系統橘）
    let late: Bool
    /// 還清了分頁（系統綠）
    let settled: Bool
    let ref: MacOwedMealRef
    /// 〔已還…〕頁面預判（nil＝頁面看不出來要擋；真正的判斷在寫入層剛重抓的那份上）
    let repayReason: String?
    /// 〔改成還沒還〕頁面預判
    let undoReason: String?
}

typealias MacOwedSort = KeyPathComparator<MacOwedRow>

/// 一人一組（id＝名字；同名兩人併一組，跟 iPhone 一樣）
struct MacOwedGroup: Identifiable {
    let id: String
    let name: String
    /// 「NT$750（2 頓・等了 35 天）」（owedPersonValue）
    let headerText: String
    /// 字首圓色號 0～5
    let avatarIndex: Int
    let rows: [MacOwedRow]
}

/// 〔已還…〕表單（打開那一刻的 ref＋已算好的字，打開後不改）
struct MacOwedRepayAsk: Identifiable {
    let id: String
    let ref: MacOwedMealRef
    /// 「王小明 還了 NT$375」（只在畫面）
    let title: String
    /// 「11/20 鼎泰豐 信義店・總額 NT$1,500」
    let mealLine: String
}

/// 〔改成還沒還〕確認框
struct MacOwedUndoAsk {
    let ref: MacOwedMealRef
    /// 「11/20 鼎泰豐 信義店・NT$375。電腦不會動存摺。」（不帶名字）
    let message: String
}

// MARK: - 按鈕能不能按、要開什麼（頁面預判＋edit 的 block；不寫）

@MainActor
enum MacOwedActions {
    /// 〔已還…〕擋的原因（nil＝可以開表單；沒選＝""）（sim6: owed6#23）
    static func repayBlocked(_ p: MacOwedPicked?, edit: MacEditCenter) -> String? {
        guard let p else { return "" }
        if let r = p.row.repayReason { return r }
        return edit.repayBlock(p.row.ref)
    }

    /// 〔改成還沒還〕擋的原因（nil＝可以問；沒選＝""）
    static func undoBlocked(_ p: MacOwedPicked?, edit: MacEditCenter) -> String? {
        guard let p else { return "" }
        if let r = p.row.undoReason { return r }
        return edit.unrepayBlock(p.row.ref)
    }

    /// sim6: owed6#24 Return／⌘↩／連按兩下／右鍵／工具列：只開表單（ref＝那一列的），不寫
    static func repayAsk(_ p: MacOwedPicked?, edit: MacEditCenter) -> MacOwedRepayAsk? {
        guard let p, repayBlocked(p, edit: edit) == nil else { return nil }
        let r = p.row
        return MacOwedRepayAsk(id: r.id, ref: r.ref, title: MacOwedText.repayTitle(name: p.name, amount: r.amount),
                               mealLine: "\(r.dateText) \(r.title)・總額 \(r.totalText)")
    }

    static func undoAsk(_ p: MacOwedPicked?, edit: MacEditCenter) -> MacOwedUndoAsk? {
        guard let p, undoBlocked(p, edit: edit) == nil else { return nil }
        let r = p.row
        return MacOwedUndoAsk(ref: r.ref, message: "\(r.dateText) \(r.title)・\(r.amountText)。電腦不會動存摺。")
    }

    /// 工具列右邊：擋住寫原因；能按寫「選了：11/20 鼎泰豐 信義店・還欠 NT$375」（不放名字）；沒選空白
    static func rightText(tab: MacOwedTab, picked: MacOwedPicked?, edit: MacEditCenter) -> String {
        guard let p = picked else { return "" }
        let blocked: String? = tab == .unpaid ? repayBlocked(p, edit: edit) : undoBlocked(p, edit: edit)
        if let blocked { return blocked }
        let verb = tab == .unpaid ? "還欠 " : "還了 "
        return "選了：\(p.row.dateText) \(p.row.title)・\(verb)\(p.row.amountText)"
    }

    /// sim6: owed6#25 寫入開關沒開／快照中／離線：整條換一行字（寫入開關沒開多〔前往資料來源〕）；其餘 nil
    static func pageLine(tab: MacOwedTab, probe: MacOwedMealRef?, edit: MacEditCenter) -> MacOwedPageLine? {
        guard let probe else { return nil }
        let block: String? = tab == .unpaid ? edit.repayBlock(probe) : edit.unrepayBlock(probe)
        guard let block else { return nil }
        if block == MacSplitPatch.reasonText("write_off") { return MacOwedPageLine(text: block, showsSource: true) }
        if block == MacSplitPatch.reasonText("snapshot") || block == MacSplitPatch.reasonText("offline") {
            return MacOwedPageLine(text: block, showsSource: false)
        }
        return nil
    }
}

/// 工具列換成的那一行
struct MacOwedPageLine {
    let text: String
    let showsSource: Bool
}

// MARK: - 選取守門（一個 key、一個 .onChange）

struct MacOwedGuardKey: Equatable {
    let tab: MacOwedTab
    let person: String?
    let selection: String?
    /// 照畫面順序：每組的列 id
    let groups: [[String]]
    /// 這個分頁的人（名字）
    let people: [String]
    /// 選到那一頓的支出 id
    let selectedExpense: UUID?

    var flat: [String] { groups.flatMap { g in g } }

    static func make(tab: MacOwedTab, person: String?, selection: String?, groups: [MacOwedGroup],
                     people: [MacOwedPerson]) -> MacOwedGuardKey {
        let ids: [[String]] = groups.map { g in g.rows.map { r in r.id } }
        let expense: UUID? = MacOwedScreen.pick(groups, id: selection)?.row.expenseID
        return MacOwedGuardKey(tab: tab, person: person, selection: selection, groups: ids,
                               people: people.map { p in p.name }, selectedExpense: expense)
    }

    /// sim6: owed6#21 跳下一頓（N32）：舊的同一組裡 i 之後還在的那列 → 舊的整串 i 之後第一個還在的列 → nil
    static func next(_ sel: String, old: MacOwedGuardKey, new: MacOwedGuardKey) -> String? {
        let alive = Set(new.flat)
        for g in old.groups {
            guard let i = g.firstIndex(of: sel) else { continue }
            for id in g[(i + 1)...] where alive.contains(id) { return id }
        }
        let flat = old.flat
        guard let i = flat.firstIndex(of: sel) else { return nil }
        for id in flat[(i + 1)...] where alive.contains(id) { return id }
        return nil
    }
}

struct MacOwedSelectionGuard: ViewModifier {
    let key: MacOwedGuardKey
    @Binding var person: String?
    @Binding var selection: String?
    @Binding var keepDetail: String?
    @ObservedObject var ui: MacUIState

    func body(content: Content) -> some View {
        content
            .onChange(of: key) { old, new in
                adjudicate(old: old, new: new)
            }
    }

    private func adjudicate(old: MacOwedGuardKey, new: MacOwedGuardKey) {
        // sim6: owed6#19 點到的人不在新的 people（標完那人最後一頓、換分頁）→ 全部
        if let p = new.person, !new.people.contains(p) {
            person = nil
        }
        // sim6: owed6#20 換分頁、換人 → 清選取（ui.selection 不動）
        if old.tab != new.tab || old.person != new.person {
            if selection != nil { selection = nil }
            return
        }
        // sim6: owed6#21 選到的那頓不見了（標完已還、iPhone 改了）→ 跳下一頓；詳情欄留在剛標的那筆
        if let sel = new.selection, !new.flat.contains(sel) {
            let next = MacOwedGuardKey.next(sel, old: old, new: new)
            keepDetail = next
            selection = next
            return
        }
        // sim6: owed6#22 選到一頓 → 詳情欄看那筆支出（跳下一頓那一次不動）；ui.selection 被別處設成不在表裡的支出 → 不清
        guard new.selection != old.selection, let e = new.selectedExpense else { return }
        if let k = keepDetail, k == new.selection {
            keepDetail = nil
            return
        }
        ui.selection = MacEntryRef.expense(e)
    }
}

// MARK: - 整頁版面

struct MacOwedLayout: View {
    let screen: MacOwedScreen
    let groups: [MacOwedGroup]
    let picked: MacOwedPicked?
    @Binding var tab: MacOwedTab
    @Binding var person: String?
    @Binding var selection: String?
    @Binding var sortOrder: [MacOwedSort]
    @Binding var repayAsk: MacOwedRepayAsk?
    @Binding var undoAsk: MacOwedUndoAsk?
    @ObservedObject var ui: MacUIState
    @ObservedObject var edit: MacEditCenter

    var body: some View {
        VStack(spacing: 10) {
            MacOwedHead(screen: screen, tab: $tab, person: $person)
            MacOwedToolbar(tab: screen.tab, picked: picked, probe: probe, repayAsk: $repayAsk, undoAsk: $undoAsk,
                           ui: ui, edit: edit)
            MacOwedTableArea(tab: screen.tab, groups: groups, selection: $selection, sortOrder: $sortOrder,
                             repayAsk: $repayAsk, undoAsk: $undoAsk, ui: ui, edit: edit)
            MacOwedPrivacyNote()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    /// 工具列問「整頁鎖不鎖」用的那一頓（任一列；寫入開關、快照、離線跟哪一頓無關）
    private var probe: MacOwedMealRef? {
        screen.groups.first?.rows.first?.ref
    }
}

/// 底部隱私字
struct MacOwedPrivacyNote: View {
    var body: some View {
        Text("只在 LifeGood 的 iPhone、iPad、Mac App 裡看得到，不會出現在通知、小工具、手錶或鎖定畫面。")
            .font(.caption)
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 看板：還欠你、大字、一句話、膠囊、〔還沒還｜還清了〕、人卡片

struct MacOwedHead: View {
    let screen: MacOwedScreen
    @Binding var tab: MacOwedTab
    @Binding var person: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 內容欄窄（詳情欄開著、視窗 900～1050pt）放不下一排時，分頁鈕排到摘要上面，膠囊和總額不被擠成「…」
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    MacOwedSummaryBlock(screen: screen)
                    Spacer(minLength: 8)
                    MacOwedTabPicker(tab: $tab)
                }
                VStack(alignment: .leading, spacing: 8) {
                    MacOwedTabPicker(tab: $tab)
                    MacOwedSummaryBlock(screen: screen)
                }
            }
            MacOwedCardStrip(screen: screen, person: $person)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macBoard(.coral)
    }
}

struct MacOwedSummaryBlock: View {
    let screen: MacOwedScreen
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = screen.summary
        VStack(alignment: .leading, spacing: 4) {
            MacHeroLabel(text: "還欠你")
            MacHeroNumber(text: MacOwedText.ntd(s.total), value: s.total)
            Text("\(s.people) 人・\(s.meals) 筆")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(MacPalette(scheme).inkDate)
            MacOwedPillRow(screen: screen)
                .padding(.top, 2)
        }
    }
}

/// 膠囊 1、2：人數、筆數；膠囊 3：還沒還「有 1 筆等了 35 天」（warn；沒有就不畫）／還清了「最近 90 天還清 N 筆」（good）
struct MacOwedPillRow: View {
    let screen: MacOwedScreen

    var body: some View {
        let s = screen.summary
        HStack(spacing: 8) {
            MacPill(icon: "person.2.fill", label: "", value: "\(s.people) 人", tone: .neutral)
            MacPill(icon: "fork.knife", label: "", value: "\(s.meals) 筆", tone: .neutral)
            if screen.tab == .settled {
                MacPill(icon: "checkmark.seal.fill", label: "", value: "最近 90 天還清 \(screen.settledCount) 筆", tone: .good)
            } else if let late = MacOwedText.owedLate(s) {
                MacPill(icon: "clock.fill", label: "", value: late, tone: .warn)
            }
        }
    }
}

struct MacOwedTabPicker: View {
    @Binding var tab: MacOwedTab

    var body: some View {
        Picker("分頁", selection: $tab) {
            Text("還沒還").tag(MacOwedTab.unpaid)
            Text("還清了（最近 90 天）").tag(MacOwedTab.settled)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

/// 人卡片一排（人多可以左右捲）；點一張＝只看那個人，再點一次或點「全部」回來
struct MacOwedCardStrip: View {
    let screen: MacOwedScreen
    @Binding var person: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                MacOwedAllCard(count: screen.people.count, total: screen.allTotal, selected: screen.person == nil,
                               pick: $person)
                ForEach(screen.people) { p in
                    MacOwedPersonCard(person: p, selected: screen.person == p.name, pick: $person,
                                      settled: screen.tab == .settled)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .frame(height: 70)
    }
}

// MARK: - 工具列：〔已還…〕／〔改成還沒還…〕＋右邊灰字；寫入關著換一行字

struct MacOwedToolbar: View {
    let tab: MacOwedTab
    let picked: MacOwedPicked?
    let probe: MacOwedMealRef?
    @Binding var repayAsk: MacOwedRepayAsk?
    @Binding var undoAsk: MacOwedUndoAsk?
    @ObservedObject var ui: MacUIState
    @ObservedObject var edit: MacEditCenter

    var body: some View {
        let line: MacOwedPageLine? = MacOwedActions.pageLine(tab: tab, probe: probe, edit: edit)
        HStack(spacing: 10) {
            if let line {
                MacOwedLockedLine(line: line, ui: ui)
            } else {
                MacOwedActionButton(tab: tab, picked: picked, repayAsk: $repayAsk, undoAsk: $undoAsk, edit: edit)
                Spacer(minLength: 8)
                Text(MacOwedActions.rightText(tab: tab, picked: picked, edit: edit))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
        }
        .frame(height: 30)
    }
}

/// 〔已還…〕（⌘↩，全 Mac 只綁這一次）／〔改成還沒還…〕；反灰原因寫在右邊灰字，不放進 help
struct MacOwedActionButton: View {
    let tab: MacOwedTab
    let picked: MacOwedPicked?
    @Binding var repayAsk: MacOwedRepayAsk?
    @Binding var undoAsk: MacOwedUndoAsk?
    @ObservedObject var edit: MacEditCenter

    var body: some View {
        if tab == .unpaid {
            Button("已還…") { repayAsk = MacOwedActions.repayAsk(picked, edit: edit) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(MacOwedActions.repayBlocked(picked, edit: edit) != nil)
                .help("標成已還（現金）")
        } else {
            Button("改成還沒還…") { undoAsk = MacOwedActions.undoAsk(picked, edit: edit) }
                .disabled(MacOwedActions.undoBlocked(picked, edit: edit) != nil)
                .help("把最近一筆還款改成還沒還")
        }
    }
}

/// 寫入開關沒開／快照中／離線：一行字（寫入開關沒開多〔前往資料來源〕）
struct MacOwedLockedLine: View {
    let line: MacOwedPageLine
    @ObservedObject var ui: MacUIState

    var body: some View {
        HStack(spacing: 10) {
            Text(line.text)
                .font(.callout)
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
            if line.showsSource {
                Button("前往資料來源") { ui.page = .source }
            }
            Spacer(minLength: 8)
        }
    }
}

// MARK: - 表格區：沒人／表格

struct MacOwedTableArea: View {
    let tab: MacOwedTab
    let groups: [MacOwedGroup]
    @Binding var selection: String?
    @Binding var sortOrder: [MacOwedSort]
    @Binding var repayAsk: MacOwedRepayAsk?
    @Binding var undoAsk: MacOwedUndoAsk?
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter

    var body: some View {
        if groups.isEmpty {
            MacOwedEmpty(tab: tab)
        } else {
            MacOwedTableView(tab: tab, groups: groups, selection: $selection, sortOrder: $sortOrder, repayAsk: $repayAsk,
                             undoAsk: $undoAsk, ui: ui, edit: edit)
        }
    }
}

/// 還沒還沒人「都還清了」；還清了沒人「最近 90 天沒有還清的」
struct MacOwedEmpty: View {
    let tab: MacOwedTab

    var body: some View {
        MacEmptyHint(icon: "checkmark.seal", tint: MacPageTheme.coral.tint,
                     title: tab == .unpaid ? MacOwedText.owedEmpty : MacOwedText.owedSettledEmpty,
                     detail: tab == .unpaid ? "有人要還你錢時，會出現在這裡" : nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 5 欄表格（一人一組）

struct MacOwedTableView: View {
    let tab: MacOwedTab
    let groups: [MacOwedGroup]
    @Binding var selection: String?
    @Binding var sortOrder: [MacOwedSort]
    @Binding var repayAsk: MacOwedRepayAsk?
    @Binding var undoAsk: MacOwedUndoAsk?
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter

    var body: some View {
        Table(of: MacOwedRow.self, selection: $selection, sortOrder: $sortOrder) {
            dateColumn()
            titleColumn()
            totalColumn()
            amountColumn()
            statusColumn()
        } rows: {
            ForEach(groups) { g in MacOwedPersonRows(group: g) }
        }
        .modifier(MacOwedTableActions(tab: tab, groups: groups, selection: selection, repayAsk: $repayAsk,
                                      undoAsk: $undoAsk, ui: ui, edit: edit))
    }

    private func dateColumn() -> TableColumn<MacOwedRow, MacOwedSort, MacOwedDateCell, Text> {
        TableColumn(Text("日期"), value: \MacOwedRow.date) { row in
            MacOwedDateCell(row: row)
        }
        .width(min: 56, ideal: 84, max: 120)
    }

    private func titleColumn() -> TableColumn<MacOwedRow, MacOwedSort, MacOwedTitleCell, Text> {
        TableColumn(Text("那頓"), value: \MacOwedRow.title) { row in
            MacOwedTitleCell(row: row)
        }
        .width(min: 100, ideal: 220, max: 400)
    }

    private func totalColumn() -> TableColumn<MacOwedRow, MacOwedSort, MacOwedTotalCell, Text> {
        TableColumn(Text("總額"), value: \MacOwedRow.total) { row in
            MacOwedTotalCell(row: row)
        }
        .width(min: 72, ideal: 110, max: 180)
    }

    /// 第 4 欄標題由分頁給：還沒還「還欠」、還清了「還了」
    private func amountColumn() -> TableColumn<MacOwedRow, MacOwedSort, MacOwedAmountCell, Text> {
        let title: String = tab == .unpaid ? "還欠" : "還了"
        return TableColumn(Text(title), value: \MacOwedRow.amount) { row in
            MacOwedAmountCell(row: row)
        }
        .width(min: 72, ideal: 110, max: 180)
    }

    private func statusColumn() -> TableColumn<MacOwedRow, MacOwedSort, MacOwedStatusCell, Text> {
        TableColumn(Text("狀態"), value: \MacOwedRow.days) { row in
            MacOwedStatusCell(row: row)
        }
        .width(min: 80, ideal: 160)
    }
}

/// 一人一組：Section 的 header 是組頭（選不到），裡面每列一個 TableRow
struct MacOwedPersonRows: TableRowContent {
    typealias TableRowValue = MacOwedRow
    let group: MacOwedGroup

    var tableRowBody: some TableRowContent<MacOwedRow> {
        Section {
            ForEach(group.rows) { row in
                TableRow(row)
            }
        } header: {
            MacOwedGroupHeader(group: group)
        }
    }
}

// MARK: - 表格的右鍵、連按兩下、Return、Space（沒有 ⌘C、⌫）

struct MacOwedTableActions: ViewModifier {
    let tab: MacOwedTab
    let groups: [MacOwedGroup]
    let selection: String?
    @Binding var repayAsk: MacOwedRepayAsk?
    @Binding var undoAsk: MacOwedUndoAsk?
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter

    func body(content: Content) -> some View {
        content
            .contextMenu(forSelectionType: String.self) { ids in
                MacOwedMenu(tab: tab, picked: MacOwedScreen.pick(groups, id: ids.first), repayAsk: $repayAsk,
                            undoAsk: $undoAsk, ui: ui, edit: edit)
            } primaryAction: { ids in
                primary(ids.first)
            }
            .onKeyPress(.return) {
                primary(selection)
                return .handled
            }
            .onKeyPress(.space) {
                ui.showInspector = true
                return .handled
            }
    }

    /// sim6: owed6#24 連按兩下／Return：還沒還分頁開〔已還…〕表單（只開表單、不寫）；還清了分頁（或擋住的）打開詳情欄
    private func primary(_ id: String?) {
        let picked: MacOwedPicked? = MacOwedScreen.pick(groups, id: id)
        if tab == .unpaid, let a = MacOwedActions.repayAsk(picked, edit: edit) {
            repayAsk = a
        } else if picked != nil {
            ui.showInspector = true
        }
    }
}

/// 右鍵選單（組頭、空白處是空集合 → 不顯示項目）；沒有〔拷貝〕
struct MacOwedMenu: View {
    let tab: MacOwedTab
    let picked: MacOwedPicked?
    @Binding var repayAsk: MacOwedRepayAsk?
    @Binding var undoAsk: MacOwedUndoAsk?
    @ObservedObject var ui: MacUIState
    let edit: MacEditCenter

    var body: some View {
        if let p = picked {
            if tab == .unpaid {
                Button("已還…") { repayAsk = MacOwedActions.repayAsk(p, edit: edit) }
                    .disabled(MacOwedActions.repayBlocked(p, edit: edit) != nil)
            } else {
                Button("改成還沒還…") { undoAsk = MacOwedActions.undoAsk(p, edit: edit) }
                    .disabled(MacOwedActions.undoBlocked(p, edit: edit) != nil)
            }
            Button("看這筆支出") {
                ui.selection = MacEntryRef.expense(p.row.expenseID)
                ui.showInspector = true
            }
        }
    }
}

// MARK: - 5 欄的具名 Cell＋組頭（只排版：不讀 Environment、不加動畫）

struct MacOwedDateCell: View {
    let row: MacOwedRow

    var body: some View {
        Text(row.dateText)
            .monospacedDigit()
            .lineLimit(1)
    }
}

/// 8pt 分類色圓點＋那頓
struct MacOwedTitleCell: View {
    let row: MacOwedRow

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(row.dot)
                .frame(width: 8, height: 8)
            Text(row.title)
                .lineLimit(1)
        }
    }
}

struct MacOwedTotalCell: View {
    let row: MacOwedRow

    var body: some View {
        Text(row.totalText)
            .monospacedDigit()
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct MacOwedAmountCell: View {
    let row: MacOwedRow

    var body: some View {
        Text(row.amountText)
            .monospacedDigit()
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// 還沒還：等了超過 30 天系統橘；還清了：系統綠（欠款不是壞事，不用紅）
struct MacOwedStatusCell: View {
    let row: MacOwedRow

    var body: some View {
        Text(row.statusText)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(tint)
    }

    private var tint: Color {
        if row.settled { return Color.green }
        return row.late ? Color.orange : Color.primary
    }
}

/// 組頭「(王) 王小明　NT$750（2 頓・等了 35 天）」（名字只在畫面）
struct MacOwedGroupHeader: View {
    let group: MacOwedGroup

    var body: some View {
        HStack(spacing: 8) {
            MacOwedAvatar(name: group.name, size: 18)
            Text(group.name)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text(group.headerText)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
    }
}

// MARK: - 〔改成還沒還〕確認框（預設〔取消〕）

struct MacOwedUndoDialog: ViewModifier {
    @Binding var ask: MacOwedUndoAsk?
    let edit: MacEditCenter

    private var isPresented: Binding<Bool> {
        Binding(get: { ask != nil }, set: { shown in if !shown { ask = nil } })
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(MacOwedText.undoCashTitle, isPresented: isPresented, titleVisibility: .visible,
                                   presenting: ask) { a in
            MacOwedUndoButtons(ask: a, edit: edit)
        } message: { a in
            Text(a.message)
        }
    }
}

private struct MacOwedUndoButtons: View {
    let ask: MacOwedUndoAsk
    let edit: MacEditCenter

    var body: some View {
        Button("改成還沒還", role: .destructive) { edit.requestUnrepay(ask.ref) }
        Button("取消", role: .cancel) {}
            .keyboardShortcut(.defaultAction)
    }
}

// MARK: - 標已還表單（表單本身不寫：〔記下來〕才 requestRepay）

struct MacOwedRepaySheet: View {
    let ask: MacOwedRepayAsk
    @EnvironmentObject private var edit: MacEditCenter
    @Environment(\.dismiss) private var dismiss
    /// 照 iPhone：初值＝現在（帶時分）
    @State private var day: Date = Date()

    var body: some View {
        let now = Date()
        let limit: Date = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        VStack(spacing: 0) {
            MacOwedRepayForm(ask: ask, day: $day, now: now, limit: limit)
            Divider()
            HStack(spacing: 10) {
                Spacer(minLength: 8)
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("記下來") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(edit.isBusy)
            }
            .padding(12)
        }
        .frame(width: 380)
    }

    private func save() {
        edit.requestRepay(ask.ref, date: day)
        dismiss()
    }
}

/// 標題、那頓、日期（不准今天以後）、進哪裡（只有現金）
struct MacOwedRepayForm: View {
    let ask: MacOwedRepayAsk
    @Binding var day: Date
    let now: Date
    /// 今天 23:59:59（寫入層 gate r7 同一條線）
    let limit: Date

    var body: some View {
        Form {
            Section {
                Text(ask.title)
                    .font(.title3.weight(.semibold))
                Text(ask.mealLine)
                    .font(.callout)
                    .foregroundStyle(Color.secondary)
            }
            Section {
                DatePicker("日期", selection: $day, in: ...limit, displayedComponents: .date)
            } footer: {
                Text(MacOwedText.repayDate(day, now: now, calendar: .current))
            }
            Section {
                LabeledContent("進哪裡", value: MacOwedText.repayCash)
            } footer: {
                Text("要記到帳戶，請在 iPhone 的誰還欠我按〔已還〕。")
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 300)
    }
}
