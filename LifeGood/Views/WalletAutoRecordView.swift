import SwiftUI

// MARK: - 設定頁「Apple Pay 自動記帳」（v25.608 wallet）
//
// 只屬於「LifeGood」target。規格：scratchpad/radar/build/wallet/brief.md（G2）。
// 入口：設定 → 進階設定 → 電子發票那一段的「Apple Pay 自動記帳」（SettingsView 只加那一列）。
//
// 這一頁的資料：
//   - 卡片對應、最近自動記的、沒記到的：App Group 的三個表（WalletCardBook／WalletRecentLog／WalletMissedLog；
//     這台記住、不跟 iCloud、不進備份）。它們不會自己通知畫面，所以 onAppear、回前景、每次改完都 reload()。
//   - 支出本身：ExpenseStore（點一列開既有的記帳編輯；左滑刪除走 WalletImport.delete）。
// 隱私：金額、商家、卡名只畫在這一頁（使用者自己打開的 App 裡）；設定頁那一列只寫「n 張卡還沒對應」。
// 記帳免費：這一頁不擋訂閱（照一按就記、手錶記帳）。

struct WalletAutoRecordView: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var links: [WalletCardLink] = []
    @State private var recent: [WalletRecentItem] = []
    @State private var missed: [WalletMissedItem] = []

    /// 〔選一張〕／〔改〕開的 sheet
    @State private var pickingCard: WalletCardLink?
    /// sheet 裡選好的（sheet 關掉之後才寫：onDismiss → 下一個 runloop）
    @State private var pendingPick: WalletPendingPick?
    /// 選好之後問一次〔一起連〕〔只管以後〕
    @State private var askPast: WalletPastAsk?
    /// 點「最近自動記的」一列 → 既有的記帳編輯
    @State private var editing: Expense?
    /// 左滑〔刪除〕先問一次
    @State private var deleting: Expense?
    /// [learn] v25.611 C2：「同行人員照上一次」（這台的開關 WalletPrefs；reload() 讀）
    @State private var memberFromLast = true

    var body: some View {
        pageWithSheets
            .confirmationDialog("要一起連以前那幾筆嗎？", isPresented: askPastShown,
                                titleVisibility: .visible, presenting: askPast) { ask in
                pastButtons(ask)
            } message: { ask in
                Text(pastMessage(ask))
            }
            .confirmationDialog("刪除這筆支出？", isPresented: deletingShown,
                                titleVisibility: .visible, presenting: deleting) { e in
                deleteButtons(e)
            } message: { e in
                Text(deleteMessage(e))
            }
    }

    // MARK: 整頁

    /// 整頁＋標題＋重讀（修飾器鏈拆開，body 只掛兩個 confirmationDialog）
    private var basePage: some View {
        listContent
            .listStyle(.insetGrouped)
            .navigationTitle("Apple Pay 自動記帳")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { reload() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { reload() }
            }
    }

    /// 兩個 sheet（一律 sheet(item:)＋.appStores()）
    private var pageWithSheets: some View {
        basePage
            .sheet(item: $pickingCard, onDismiss: { applyPendingPick() }) { link in
                pickSheet(for: link).appStores()
            }
            // [learn] 編輯存檔時學到的卡在 AddExpenseView 的下一個 runloop 才寫進對應表 → 關掉後再放一輪才重讀
            .sheet(item: $editing, onDismiss: { DispatchQueue.main.async { reload() } }) { e in
                AddExpenseView(expenseType: e.expenseType, editingExpense: e).appStores()
            }
    }

    private var listContent: some View {
        let rows = liveRecentRows()
        // [learn] 每張卡以前還沒連的筆數（一次算全部的卡，不要每列算）
        let past = WalletAutoRecord.unlinkedCounts(recent: recent, ledger: store.expenses)
        return List {
            introSection(rows: rows)
            WalletSetupStepsSection()
            memorySection
            unresolvedSection
            decidedSection(past: past)
            recentSection(rows: rows)
            missedSection
            WalletLimitsSection()
        }
    }

    // MARK: 段 1 說明卡

    private func introSection(rows: [WalletRecentRow]) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("用 Apple Pay 付款就記一筆", systemImage: "creditcard.fill")
                    .font(.headline)
                Text("用 Apple Pay 付款那一刻，捷徑會自動把這筆記成變動支出：商家當名稱、分類和同行人員照同一家店上一次、連到你選的信用卡。你在記帳改過的卡片、分類，下一次會照改過的。")
                    .font(.subheadline)
                Text(introStatus(rows: rows))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func introStatus(rows: [WalletRecentRow]) -> String {
        guard let latest = rows.first else {
            return "還沒有自動記過。照下面設定好，下一次付款就會出現在這裡。"
        }
        let day = WalletAutoRecord.shortDate(latest.expense.date, calendar: .current)
        return "這支 iPhone 已經自動記了 \(rows.count) 筆・最近 \(day)"
    }

    // MARK: 段 2b 自動帶入（[learn] v25.611 C2、C3）

    private var memorySection: some View {
        Section {
            Toggle("同行人員照上一次", isOn: memberBinding)
        } header: {
            Text("自動帶入")
        } footer: {
            Text("自動記的那一筆，分類和同行人員照同一家店上一次記的帶入，你再自己改；就算把店名改了（例：7-ELEVEN 改成小七），下一次在同一家店付款還是對得到。同行人員只帶進飲食、娛樂、購物、日用品這類有同行人員欄位的分類。開關只記在這支 iPhone。")
        }
    }

    private var memberBinding: Binding<Bool> {
        Binding(get: { memberFromLast }, set: { v in
            memberFromLast = v
            WalletPrefs.setMemberFromLast(v)
        })
    }

    // MARK: 段 3 還沒對應的卡

    private var unresolvedLinks: [WalletCardLink] {
        links.filter { !$0.isDecided }
    }

    @ViewBuilder
    private var unresolvedSection: some View {
        let list = unresolvedLinks
        if !list.isEmpty {
            Section {
                ForEach(list) { link in
                    WalletUnresolvedCardRow(link: link) { pickingCard = link }
                }
            } header: {
                Text("還沒對應的卡")
            } footer: {
                Text("選了之後，以後用這張卡付款都會連到那張卡或那個帳戶。")
            }
        }
    }

    // MARK: 段 4 卡片（已對應的）

    private var decidedLinks: [WalletCardLink] {
        links.filter { $0.isDecided }
    }

    /// 「沒寫幣別、只寫 $ 時當作」的選項：設定裡有正匯率的幣別（去重、照原順序；台幣另外放第一個）
    private var dollarOptions: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for r in store.currencyRates where r.rate > 0 {
            let code = r.code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty, !FinanceRates.isNTD(code), !seen.contains(code) else { continue }
            seen.insert(code)
            out.append(code)
        }
        return out
    }

    @ViewBuilder
    private func decidedSection(past: [String: Int]) -> some View {
        let list = decidedLinks
        if !list.isEmpty {
            Section {
                ForEach(list) { link in
                    decidedRow(link, pending: pendingPast(link, past: past))
                }
            } header: {
                Text("卡片")
            } footer: {
                Text("左滑可以忘記這張卡（只忘記對應，已經記的支出不動）。卡片對應只記在這支 iPhone，換手機要重新對應一次。")
            }
        }
    }

    private func decidedRow(_ link: WalletCardLink, pending: Int) -> some View {
        WalletLinkedCardRow(
            link: link,
            status: linkStatus(link),
            dollarOptions: dollarOptions,
            dollarMissingRate: dollarMissingRate(link),
            pendingPast: pending,
            onChange: { pickingCard = link },
            onSetDollar: { code in setDollar(link, code: code) },
            onLinkPast: { linkPastNow(link) }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                forget(link)
            } label: {
                Label("忘記這張卡", systemImage: "xmark.circle")
            }
        }
    }

    /// 卡片那一列的副字（第二個值＝要不要用橘色提醒）
    private func linkStatus(_ link: WalletCardLink) -> WalletLinkStatus {
        switch link.linkTarget {
        case .noAccount?:
            return WalletLinkStatus(text: "不連帳戶", warning: false)
        case .card?, .bank?:
            guard let name = WalletImport.accountDisplay(for: link, life: lifeStore) else {
                return WalletLinkStatus(text: "對到的帳戶不見了", warning: true)
            }
            let suffix = link.auto ? "（自動對到）" : ""
            return WalletLinkStatus(text: "連到 " + name + suffix, warning: false)
        case nil:
            return WalletLinkStatus(text: "還沒對應", warning: true)
        }
    }

    /// 這張卡設了「當作美金」之類，但設定裡沒有那個幣別的匯率（只寫 $ 的會記不到）
    private func dollarMissingRate(_ link: WalletCardLink) -> Bool {
        guard let code = link.dollarCode else { return false }
        return !store.currencyRates.contains { $0.code == code && $0.rate > 0 }
    }

    /// [learn] 「還有 N 筆沒連」：連到信用卡／銀行帳戶、帳戶還在的卡才寫（〔不連帳戶〕、帳戶不見了＝0）
    private func pendingPast(_ link: WalletCardLink, past: [String: Int]) -> Int {
        guard link.linkTarget == .card || link.linkTarget == .bank else { return 0 }
        guard WalletImport.accountDisplay(for: link, life: lifeStore) != nil else { return 0 }
        return past[link.key] ?? 0
    }

    /// [learn] 卡片那一列的〔一起連〕：使用者自己按才連（按鈕本身就是〔一起連〕，不另外問）。寫 store 放下一個 runloop
    private func linkPastNow(_ link: WalletCardLink) {
        DispatchQueue.main.async {
            WalletImport.linkPast(key: link.key, expense: store, life: lifeStore, finance: financeStore)
            reload()
        }
    }

    private func setDollar(_ link: WalletCardLink, code: String?) {
        WalletCardBook.setDollarCode(link.key, code: code)
        reload()
    }

    private func forget(_ link: WalletCardLink) {
        WalletCardBook.remove(link.key)
        reload()
    }

    // MARK: 段 5 最近自動記的

    /// 最近清單裡還在帳本的（新到舊）。先建字典，不要每列 first(where:)
    private func liveRecentRows() -> [WalletRecentRow] {
        guard !recent.isEmpty else { return [] }
        var byId: [UUID: Expense] = [:]
        for e in store.expenses where byId[e.id] == nil {
            byId[e.id] = e
        }
        var rows: [WalletRecentRow] = []
        for item in recent {
            if let e = byId[item.id] {
                rows.append(WalletRecentRow(item: item, expense: e))
            }
        }
        return rows
    }

    private func recentSection(rows: [WalletRecentRow]) -> some View {
        let shown = Array(rows.prefix(WalletRecentLog.shownCount))
        return Section {
            if shown.isEmpty {
                Text("還沒有從 Apple Pay 記進來的支出。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(shown) { row in
                    recentRow(row)
                }
            }
        } header: {
            Text("最近自動記的")
        } footer: {
            Text("最近 \(WalletRecentLog.shownCount) 筆。點一筆可以改分類、金額；左滑可以刪除（連著的銀行扣款一起刪）。")
        }
    }

    private func recentRow(_ row: WalletRecentRow) -> some View {
        Button {
            editing = row.expense
        } label: {
            WalletRecentRowLabel(text: recentText(row), category: row.expense.variableCategory?.rawValue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // 不用 role: .destructive：那個 role 會先把這一列動畫拿掉，取消刪除時又跳回來
            Button {
                deleting = row.expense
            } label: {
                Label("刪除", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    /// 「11/7 7-ELEVEN NT$65・國泰 CUBE」
    private func recentText(_ row: WalletRecentRow) -> String {
        let e = row.expense
        return WalletAutoRecord.rowText(date: e.date, title: e.title,
                                        amountText: store.displayAmountText(e),
                                        account: recentAccount(row), calendar: .current)
    }

    /// 連到的卡或帳戶；都沒連：有卡名就寫卡名（還沒決定的加「（還沒對應）」），沒卡名不寫
    private func recentAccount(_ row: WalletRecentRow) -> String? {
        if let name = WalletImport.accountDisplay(of: row.expense, life: lifeStore) {
            return name
        }
        let cardName = row.item.cardName
        guard !cardName.isEmpty else { return nil }
        let decided = links.first { $0.key == row.item.cardKey }?.isDecided ?? false
        return decided ? cardName : cardName + "（還沒對應）"
    }

    // MARK: 段 6 沒記到的

    @ViewBuilder
    private var missedSection: some View {
        if !missed.isEmpty {
            Section {
                ForEach(missed) { item in
                    WalletMissedRow(item: item)
                }
                Button("清掉這幾筆") {
                    WalletMissedLog.clear()
                    reload()
                }
            } header: {
                Text("沒記到的")
            } footer: {
                Text("外幣要先到 設定 → 自訂幣別匯率 加上那個幣別。")
            }
        }
    }

    // MARK: 〔選一張〕sheet（呼叫端掛 .appStores()）

    private func pickSheet(for link: WalletCardLink) -> some View {
        WalletCardPickSheet(link: link, onPick: { target, id in
            pendingPick = WalletPendingPick(key: link.key, cardName: link.name, target: target, milestoneId: id)
        })
    }

    /// sheet 關掉之後（onDismiss）才寫對應表，再放到下一個 runloop；選了信用卡／銀行帳戶、以前有沒連的才問〔一起連〕
    private func applyPendingPick() {
        guard let pick = pendingPick else { return }
        pendingPick = nil
        DispatchQueue.main.async {
            WalletCardBook.setTarget(pick.key, target: pick.target, milestoneId: pick.milestoneId)
            reload()
            guard pick.target != .noAccount else { return }
            let count = WalletImport.unlinkedPast(key: pick.key, expense: store).count
            guard count > 0 else { return }
            let account = WalletCardBook.find(pick.key).flatMap { WalletImport.accountDisplay(for: $0, life: lifeStore) }
            askPast = WalletPastAsk(key: pick.key, cardName: pick.cardName, count: count, account: account ?? "")
        }
    }

    // MARK: 〔一起連〕〔只管以後〕

    private var askPastShown: Binding<Bool> {
        Binding(get: { askPast != nil }, set: { if !$0 { askPast = nil } })
    }

    @ViewBuilder
    private func pastButtons(_ ask: WalletPastAsk) -> some View {
        Button("一起連") {
            linkPast(ask)
        }
        Button("只管以後", role: .cancel) {}
    }

    private func pastMessage(_ ask: WalletPastAsk) -> String {
        let head = "以前用「\(ask.cardName)」自動記的 \(ask.count) 筆還沒連，"
        if ask.account.isEmpty { return head + "要一起連起來嗎？" }
        return head + "要一起連到「\(ask.account)」嗎？"
    }

    private func linkPast(_ ask: WalletPastAsk) {
        DispatchQueue.main.async {
            WalletImport.linkPast(key: ask.key, expense: store, life: lifeStore, finance: financeStore)
            reload()
        }
    }

    // MARK: 刪除

    private var deletingShown: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    @ViewBuilder
    private func deleteButtons(_ e: Expense) -> some View {
        Button("刪除", role: .destructive) {
            performDelete(e)
        }
        Button("取消", role: .cancel) {}
    }

    private func deleteMessage(_ e: Expense) -> String {
        "「\(e.title) \(store.displayAmountText(e))」會從記帳刪掉；連著的銀行扣款紀錄也一起刪。"
    }

    private func performDelete(_ e: Expense) {
        DispatchQueue.main.async {
            WalletImport.delete(e, expense: store, life: lifeStore, finance: financeStore)
            reload()
        }
    }

    // MARK: 讀這台記住的三個表

    private func reload() {
        links = WalletCardBook.all()
        recent = WalletRecentLog.all()
        missed = WalletMissedLog.all()
        memberFromLast = WalletPrefs.memberFromLast
    }
}

// MARK: - 小型別（只在這一頁用）

/// sheet 裡選好、等 sheet 關掉才寫的那一筆
private struct WalletPendingPick {
    var key: String
    var cardName: String
    var target: WalletLinkTarget
    var milestoneId: UUID?
}

/// 〔一起連〕要問的那一次
private struct WalletPastAsk: Identifiable {
    var key: String
    var cardName: String
    var count: Int
    /// 對到的卡或帳戶顯示名（找不到＝""）
    var account: String

    var id: String { key }
}

/// 「最近自動記的」一列：最近清單那一筆＋帳本裡的支出
private struct WalletRecentRow: Identifiable {
    var item: WalletRecentItem
    var expense: Expense

    var id: UUID { item.id }
}

/// 卡片那一列的副字
private struct WalletLinkStatus {
    var text: String
    var warning: Bool
}

// MARK: - 段 2 怎麼設定

private struct WalletSetupStepsSection: View {
    /// brief 第 6 節定稿字（iOS 18 繁中介面有把握的名稱：「捷徑」App、「自動化」、「交易」、「立即執行」、「捷徑輸入」、「完成」）
    /// [v25.610] 第 5 步照使用者實機截圖改：交易的變數是「交易／卡片或票卡／商家／數量／名稱」，金額叫「數量」
    private static let steps: [String] = [
        "打開「捷徑」App，點下面的「自動化」。",
        "新增一個自動化（右上角的 ＋），在清單裡選「交易」。",
        "選要自動記帳的卡片（可以全選），選「立即執行」，按下一步。",
        "建立新的空白捷徑，加入動作：搜尋「LifeGood」，選「記一筆支出」。",
        "加入後三個欄位都會先帶整筆〔交易〕，要各點一下改成裡面的那一項：「記一筆支出」後面的〔交易〕選「數量」（就是金額）；「商家」那一列選「商家」；「卡片」那一列選「卡片或票卡」。",
        "按「完成」。下一次用 Apple Pay 付款，LifeGood 就會在背景記一筆，捷徑只回「已記一筆」。"
    ]

    var body: some View {
        Section {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { pair in
                WalletSetupStepRow(number: pair.offset + 1, text: pair.element)
            }
        } header: {
            Text("怎麼設定")
        } footer: {
            Text("第一次執行時，系統可能會問要不要允許 LifeGood 執行，選允許。如果不想每次跳出執行提示，可以在那個自動化裡把通知關掉。")
        }
    }
}

private struct WalletSetupStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "\(number).circle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 段 7 說明與限制

private struct WalletLimitsSection: View {
    private static let lines: [String] = [
        "只有用 Apple Pay 付款才會記；實體卡刷卡、轉帳、自動扣繳抓不到。",
        "退款、分期、外幣實際扣款的金額不會自動改，要自己到記帳改。",
        "系統偶爾不會觸發捷徑；同一筆觸發兩次的話，90 秒內的第二次不會再記。",
        "金額只寫「$」時當作台幣；美金卡可以在上面的「卡片」改成美金（照設定裡的匯率換）。",
        "有綁手機條碼的話，同一筆的電子發票會併進這一筆。",
        "在記帳幫自動記的那筆改了卡片或帳戶，以後同一張卡就自動連到改的那個；以前還沒連的那幾筆，到上面「卡片」按「一起連」。",
        "改成不連帳戶不會學；只改這一筆。",
        "卡片對應和這份清單只存在這支 iPhone，不跟 iCloud、不進備份。",
        "小工具、通知、鎖定畫面不會出現金額、商家、卡名；捷徑只會回「已記一筆」。"
    ]

    var body: some View {
        Section {
            ForEach(Self.lines, id: \.self) { line in
                WalletLimitLine(text: line)
            }
        } header: {
            Text("說明與限制")
        }
    }
}

private struct WalletLimitLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

// MARK: - 各段的列

private struct WalletUnresolvedCardRow: View {
    let link: WalletCardLink
    let onPick: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(link.name)
                Text("最近一筆 " + WalletAutoRecord.shortDate(link.lastSeen, calendar: .current))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("選一張", action: onPick)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

private struct WalletLinkedCardRow: View {
    let link: WalletCardLink
    let status: WalletLinkStatus
    let dollarOptions: [String]
    let dollarMissingRate: Bool
    /// [learn] 以前用這張卡自動記、還沒連的筆數（0＝不寫那一行）
    let pendingPast: Int
    let onChange: () -> Void
    let onSetDollar: (String?) -> Void
    /// [learn] 〔一起連〕
    let onLinkPast: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                nameBlock
                Spacer(minLength: 8)
                Button("改", action: onChange)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            pastBlock
            dollarMenu
            if dollarMissingRate {
                Text("設定裡沒有「\(link.dollarCode ?? "")」的匯率，只寫 $ 的金額會記不到。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(link.name)
            Text(status.text)
                .font(.caption)
                .foregroundStyle(status.warning ? Color.orange : Color.secondary)
        }
    }

    /// [learn] 「還有 2 筆沒連〔一起連〕」
    @ViewBuilder
    private var pastBlock: some View {
        if pendingPast > 0 {
            HStack(spacing: 12) {
                Text("還有 \(pendingPast) 筆沒連")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer(minLength: 8)
                Button("一起連", action: onLinkPast)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var currentDollar: String {
        link.dollarCode ?? "台幣"
    }

    private var dollarMenu: some View {
        Menu {
            Button {
                onSetDollar(nil)
            } label: {
                WalletCheckLabel(text: "台幣", checked: link.dollarCode == nil)
            }
            ForEach(dollarOptions, id: \.self) { code in
                Button {
                    onSetDollar(code)
                } label: {
                    WalletCheckLabel(text: code, checked: link.dollarCode == code)
                }
            }
        } label: {
            Text("沒寫幣別、只寫 $ 時當作：\(currentDollar)")
                .font(.caption)
        }
        .buttonStyle(.borderless)
    }
}

private struct WalletCheckLabel: View {
    let text: String
    let checked: Bool

    var body: some View {
        if checked {
            Label(text, systemImage: "checkmark")
        } else {
            Text(text)
        }
    }
}

private struct WalletRecentRowLabel: View {
    let text: String
    let category: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .foregroundStyle(.primary)
            if let category, !category.isEmpty {
                Text(category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WalletMissedRow: View {
    let item: WalletMissedItem

    private var timeText: String {
        let c = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: item.at)
        return String(format: "%ld/%ld %02ld:%02ld", c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    private var amountShown: String {
        item.amountText.isEmpty ? "（沒有金額）" : item.amountText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(timeText + "　" + amountShown)
            Text(item.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 〔選一張〕sheet

private struct WalletCardPickSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let link: WalletCardLink
    /// 選好：（對到哪一種、milestone id；〔不連帳戶〕是 nil）。父頁等 sheet 關掉才寫
    let onPick: (WalletLinkTarget, UUID?) -> Void

    var body: some View {
        NavigationStack {
            pickList
                .navigationTitle("選一張")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
        }
    }

    private var pickList: some View {
        let pool = WalletAutoRecord.candidates(lifeStore.milestones)
        return List {
            Section {
                Text("捷徑給的卡片名稱：\(link.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if pool.cards.isEmpty && pool.banks.isEmpty {
                Section {
                    Text("財富裡還沒有信用卡或銀行帳戶，先到 財富 新增。")
                        .foregroundStyle(.secondary)
                }
            }
            candidateSection("信用卡", pool.cards)
            candidateSection("銀行帳戶", pool.banks)
            Section {
                noAccountRow
            } footer: {
                Text("選「不連帳戶」：以後用這張卡付款照樣會記，只是不連到財富的卡或帳戶。")
            }
        }
    }

    @ViewBuilder
    private func candidateSection(_ title: String, _ list: [WalletLinkCandidate]) -> some View {
        if !list.isEmpty {
            Section {
                ForEach(list) { c in
                    candidateRow(c)
                }
            } header: {
                Text(title)
            }
        }
    }

    private func candidateRow(_ c: WalletLinkCandidate) -> some View {
        let checked = link.linkTarget == c.kind && link.milestoneId == c.id
        return Button {
            pick(c.kind, c.id)
        } label: {
            WalletPickRowLabel(title: c.display, detail: lastFourText(c), checked: checked)
        }
    }

    private var noAccountRow: some View {
        Button {
            pick(.noAccount, nil)
        } label: {
            WalletPickRowLabel(title: "不連帳戶", detail: nil, checked: link.linkTarget == .noAccount)
        }
    }

    private func lastFourText(_ c: WalletLinkCandidate) -> String? {
        guard let l = c.lastFour, !l.isEmpty else { return nil }
        return "末四碼 " + l
    }

    private func pick(_ target: WalletLinkTarget, _ id: UUID?) {
        onPick(target, id)
        dismiss()
    }
}

private struct WalletPickRowLabel: View {
    let title: String
    let detail: String?
    let checked: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if checked {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

// MARK: - 設定頁那一列

/// 設定 → 進階設定 → 電子發票那一段的一列（SettingsView 只加這一列 NavigationLink）。不顯示金額、商家、卡名
struct WalletAutoRecordSettingsRow: View {
    @State private var unresolved = 0

    private var subtitle: String {
        unresolved > 0 ? "\(unresolved) 張卡還沒對應" : "用捷徑在付款那一刻記一筆"
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Pay 自動記帳")
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "creditcard.fill")
                .foregroundStyle(.orange)
        }
        .onAppear {
            unresolved = WalletCardBook.all().filter { !$0.isDecided }.count
        }
    }
}
