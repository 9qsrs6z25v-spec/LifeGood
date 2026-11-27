import SwiftUI

// [v25.634] 誰還欠我（companions1 G3；judge_companions C10／C11）
//
// - OwedListView：依人分組（金額大到小）、每頓新到舊；〔還沒還｜還清了（最近 90 天）〕。
//   從變動支出頁開（opensCards: true）點一頓開那筆的詳情卡；從詳情卡〔看誰還欠我〕開（false）不再疊詳情卡。
//   **沒有分享**；名字、欠款只在 App 裡（不上通知、小工具、手錶、鎖定畫面、靈動島）。
// - SplitRepaySheet：〔已還〕選日期、帳戶或現金；〔記下來〕先 dismiss、下一個 runloop 才 ExpenseSplitActions.repay
//   （先寫存款、再標已還；存款 linkedExpenseId 一定是 nil、note 不寫人名，都在 ExpenseSplitRepay.deposit／note）。
// - SplitUndoDialog：〔改成還沒還〕（有存款的問要不要一起刪）；按了下一個 runloop 才 ExpenseSplitActions.undo。
// body、build 都不寫 store；畫面上的字都從 ExpenseSplitText 拿。

// MARK: - 誰還欠我

struct OwedListView: View {
    /// true＝點一頓開詳情卡（變動支出頁開的）；false＝從詳情卡開的，不再一層一層疊詳情卡
    let opensCards: Bool

    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    /// 0＝還沒還、1＝還清了
    @State private var tab = 0
    @State private var unpaid: [SplitOwedPerson] = []
    @State private var settled: [SplitOwedPerson] = []
    @State private var summary = SplitOwedSummary()
    /// 帳戶 id → 名字（還清了那頁「已還 11/21・國泰世華 ✓」用）
    @State private var accountNames: [UUID: String] = [:]
    @State private var repayTarget: SplitRepayTarget? = nil
    @State private var undoAsk: SplitUndoAsk? = nil
    @State private var card: FinanceCardTarget? = nil
    @State private var toast: String? = nil
    /// [v25.636] 名單上已經有的名字 key（〔存成朋友〕只給名單外的人）
    @State private var knownKeys: Set<String> = []
    @State private var showPremiumAlert = false

    init(opensCards: Bool = true) {
        self.opensCards = opensCards
    }

    var body: some View {
        NavigationStack {
            AnyView(list)
                .navigationTitle(ExpenseSplitText.owedTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("完成") { dismiss() }
                    }
                }
        }
        .sheet(item: $repayTarget) { t in
            SplitRepaySheet(expenseId: t.expenseId, shareId: t.shareId, onDone: { msg in toast = msg })
                .appStores()
        }
        .sheet(item: $card) { t in
            FinanceItemCard(target: t)
                .appStores()
        }
        .modifier(SplitUndoDialog(ask: $undoAsk, life: lifeStore))
        .premiumLockAlert(isPresented: $showPremiumAlert)
        .overlay(alignment: .bottom) { OwedToast(text: toast) }
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if Task.isCancelled { return }
            toast = nil
        }
        .task(id: store.modifyID) { reload() }
    }

    // MARK: 清單（整段包 AnyView）

    private var list: some View {
        List {
            Section {
                if summary.showsEntry {
                    Text(ExpenseSplitText.owedHeader(summary))
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                OwedTabPicker(tab: $tab)
            }
            let people: [SplitOwedPerson] = tab == 0 ? unpaid : settled
            if people.isEmpty {
                Section {
                    Text(tab == 0 ? ExpenseSplitText.owedEmpty : ExpenseSplitText.owedSettledEmpty)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(people) { p in
                    personSection(p)
                }
            }
            Section {
                Text(ExpenseSplitText.owedPrivacy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func personSection(_ p: SplitOwedPerson) -> some View {
        Section {
            ForEach(p.meals) { m in
                mealRow(m)
            }
        } header: {
            OwedPersonHeader(name: p.name, value: ExpenseSplitText.owedPersonValue(p),
                             onSaveFriend: canSaveFriend(p.name) ? { saveFriend(p.name) } : nil)
        }
    }

    /// 還沒還那頁：〔已還〕；還清了那頁：已還那一行＋〔…〕→〔改成還沒還〕
    private func mealRow(_ m: SplitOwedMeal) -> OwedMealRow {
        let label = ExpenseSplitText.owedMealLabel(m, calendar: .current)
        let amount = ExpenseSplitText.ntd(m.amount)
        var openAction: (() -> Void)? = nil
        if opensCards {
            openAction = { open(m) }
        }
        if tab == 1 {
            return OwedMealRow(label: label, amount: amount, paid: paidText(m),
                               onRepay: nil, onUndo: { askUndo(m) }, onOpen: openAction)
        }
        return OwedMealRow(label: label, amount: amount, paid: nil,
                           onRepay: { repay(m) }, onUndo: nil, onOpen: openAction)
    }

    // MARK: 動作（只改 @State；寫 store 經 SplitRepaySheet／SplitUndoDialog）

    private func paidText(_ m: SplitOwedMeal) -> String {
        let name: String? = m.accountId.flatMap { id in accountNames[id] }
        return ExpenseSplitText.paidLine(date: m.repaidDate ?? m.date, accountName: name, calendar: .current)
    }

    private func repay(_ m: SplitOwedMeal) {
        repayTarget = SplitRepayTarget(expenseId: m.expenseId, shareId: m.shareId)
    }

    /// 從 Menu 按的：dialog 要等 Menu 收起來那一輪過了再開（25.614）
    private func askUndo(_ m: SplitOwedMeal) {
        let eid = m.expenseId
        let sid = m.shareId
        DispatchQueue.main.async {
            guard let s = ExpenseSplitStore.shared.index.split(eid) else { return }
            undoAsk = SplitUndoAsk.make(split: s, shareId: sid, calendar: .current)
        }
    }

    private func open(_ m: SplitOwedMeal) {
        guard opensCards else { return }
        card = .variableExpense(m.expenseId)
    }

    /// 只讀：index＋記帳 → 畫面用的值
    private func reload() {
        let idx = ExpenseSplitStore.shared.index
        let now = Date()
        let cal = Calendar.current
        summary = idx.owedSummary(expenses: store.expenses, now: now, calendar: cal)
        unpaid = ExpenseSplitIndex.people(idx.owedMeals(expenses: store.expenses, now: now, calendar: cal))
        settled = ExpenseSplitIndex.people(idx.settledMeals(expenses: store.expenses, now: now, calendar: cal))
        let pairs: [(UUID, String)] = lifeStore.milestones.map { m in (m.id, ExpenseSplitRepay.accountName(m)) }
        accountNames = Dictionary(pairs, uniquingKeysWith: { a, _ in a })
        knownKeys = PersonLedger.knownKeys(life: lifeStore)
    }

    /// [v25.636] 名單外、名字合格的人才有〔存成朋友〕
    private func canSaveFriend(_ name: String) -> Bool {
        guard PersonLedger.canPick(name) else { return false }
        let k = PersonLedger.key(name)
        return !k.isEmpty && !knownKeys.contains(k)
    }

    /// [v25.636] 〔存成朋友〕：要訂閱；下一個 runloop 才寫
    private func saveFriend(_ name: String) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        knownKeys.insert(PersonLedger.key(name))
        let life = lifeStore
        DispatchQueue.main.async {
            let saved = FriendActions.save(names: [name], life: life)
            if !saved.isEmpty { toast = FriendText.savedToast(saved) }
        }
    }
}

/// 〔還沒還｜還清了〕
fileprivate struct OwedTabPicker: View {
    @Binding var tab: Int

    var body: some View {
        Picker("", selection: $tab) {
            Text(ExpenseSplitText.owedTabUnpaid).tag(0)
            Text(ExpenseSplitText.owedTabSettled).tag(1)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// 一個人那一段的標頭：名字＋「NT$375（1 頓・等了 35 天）」
fileprivate struct OwedPersonHeader: View {
    let name: String
    let value: String
    /// [v25.636] 〔存成朋友〕（名單外的人才有）
    let onSaveFriend: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let s = onSaveFriend {
                Button(FriendText.saveAsFriend, action: s)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .textCase(nil)
    }
}

/// 一頓一列（純值；按鈕只回呼）
fileprivate struct OwedMealRow: View {
    /// 「11/20 鼎泰豐 信義店」
    let label: String
    /// 「NT$375」
    let amount: String
    /// 還清了那頁：「已還 11/21・國泰世華 ✓」
    let paid: String?
    /// 還沒還那頁：〔已還〕
    let onRepay: (() -> Void)?
    /// 還清了那頁：〔…〕→〔改成還沒還〕
    let onUndo: (() -> Void)?
    /// 點那一列開詳情卡（nil＝不開）
    let onOpen: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            OwedMealText(label: label, paid: paid)
            Spacer(minLength: 8)
            Text(amount)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
            OwedMealAction(onRepay: onRepay, onUndo: onUndo)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
    }
}

fileprivate struct OwedMealText: View {
    let label: String
    let paid: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline)
                .lineLimit(2)
            if let p = paid {
                Text(p)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
        }
    }
}

/// 列右邊：〔已還〕或〔…〕（同一列有別的點擊，一律 .borderless）
fileprivate struct OwedMealAction: View {
    let onRepay: (() -> Void)?
    let onUndo: (() -> Void)?

    @ViewBuilder
    var body: some View {
        if let r = onRepay {
            Button(ExpenseSplitText.repayButton, action: r)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
        } else if let u = onUndo {
            Menu {
                Button(ExpenseSplitText.undoButton, action: u)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
        }
    }
}

/// 完成提示小橫條（「記好了：國泰世華 ＋NT$375」；2.5 秒自己消失）
fileprivate struct OwedToast: View {
    let text: String?

    @ViewBuilder
    var body: some View {
        if let t = text {
            Text(t)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.horizontal, 16).padding(.bottom, 16)
        }
    }
}

// MARK: - 〔已還〕

/// 金額固定是那個人還欠的全額（v1 不能改）；帳戶＝成就・銀行、排除停用；沒帳戶只剩現金
struct SplitRepaySheet: View {
    let expenseId: UUID
    let shareId: UUID
    let onDone: (String) -> Void

    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    /// nil＝現金
    @State private var accountId: UUID? = nil
    /// 「上次用的」（打開時讀一次，只存這支手機）
    @State private var lastId: UUID? = nil
    @State private var seeded = false

    init(expenseId: UUID, shareId: UUID, onDone: @escaping (String) -> Void) {
        self.expenseId = expenseId
        self.shareId = shareId
        self.onDone = onDone
    }

    private var expense: Expense? {
        store.expenses.first { e in e.id == expenseId }
    }

    private var share: SplitShare? {
        guard let e = expense, let s = ExpenseSplitStore.shared.index.split(for: e) else { return nil }
        return s.liveShares.first { x in x.id == shareId }
    }

    /// 那頓、那個人找得到，而且還沒還清
    private var canSave: Bool {
        guard let s = share else { return false }
        return s.owes && !s.isSettled && s.outstanding >= 0.5
    }

    private var accounts: [LifeMilestone] {
        ExpenseSplitRepay.accounts(lifeStore.milestones, book: lifeStore.wealthBook)
    }

    private var title: String {
        guard let s = share else { return ExpenseSplitText.repayButton }
        return ExpenseSplitText.repayTitle(name: s.name, amount: s.outstanding)
    }

    private var explain: String {
        guard let e = expense else { return "" }
        return ExpenseSplitText.repayExplain(amount: share?.outstanding ?? 0,
                                             note: ExpenseSplitRepay.note(for: e, calendar: .current))
    }

    var body: some View {
        NavigationStack {
            AnyView(form)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(ExpenseSplitText.repaySave) { save() }
                            .fontWeight(.semibold)
                            .disabled(!canSave)
                    }
                }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { seed() }
    }

    private var form: some View {
        Form {
            Section {
                DatePicker(ExpenseSplitText.repayDateLabel, selection: $date, displayedComponents: .date)
            } footer: {
                Text(ExpenseSplitText.repayDate(date, now: Date(), calendar: .current))
            }
            Section {
                ForEach(accounts) { m in
                    RepayAccountRow(title: ExpenseSplitRepay.accountName(m),
                                    tag: m.id == lastId ? ExpenseSplitText.repayLastTag : nil,
                                    picked: accountId == m.id,
                                    onTap: { accountId = m.id })
                }
                RepayAccountRow(title: ExpenseSplitText.repayCash, tag: nil, picked: accountId == nil,
                                onTap: { accountId = nil })
            } header: {
                Text(ExpenseSplitText.repayWhereLabel)
            } footer: {
                Text(explain)
            }
        }
    }

    /// 打開時一次：上次用的還在就選它，不然第一個帳戶；沒帳戶＝現金
    private func seed() {
        guard !seeded else { return }
        seeded = true
        let last = ExpenseSplitRepay.lastAccountId()
        lastId = last
        accountId = ExpenseSplitRepay.defaultAccountId(accounts: accounts, last: last)
    }

    /// 〔記下來〕：值先抓成區域常數 → dismiss → 下一個 runloop 才寫（先存款、再標已還）
    private func save() {
        guard canSave, let e = expense else { return }
        let life = lifeStore
        let picked = accountId
        let acc: LifeMilestone? = accounts.first { m in m.id == picked }
        let d = date
        let sid = shareId
        let done = onDone
        dismiss()
        DispatchQueue.main.async {
            if let msg = ExpenseSplitActions.repay(expense: e, shareId: sid, date: d, account: acc, life: life,
                                                    store: ExpenseSplitStore.shared) { done(msg) }
        }
    }
}

/// 進哪裡：一個帳戶一列（勾選）
fileprivate struct RepayAccountRow: View {
    let title: String
    /// 「（上次用的）」
    let tag: String?
    let picked: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text(title + (tag ?? ""))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(picked ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
    }
}

// MARK: - 〔改成還沒還〕

/// 有存款：〔一起刪〕〔只改成還沒還〕〔取消〕；現金：〔改成還沒還〕〔取消〕。按了下一個 runloop 才寫
struct SplitUndoDialog: ViewModifier {
    @Binding var ask: SplitUndoAsk?
    let life: LifeStore

    init(ask: Binding<SplitUndoAsk?>, life: LifeStore) {
        _ask = ask
        self.life = life
    }

    private var shown: Binding<Bool> {
        Binding(get: { ask != nil }, set: { v in if !v { ask = nil } })
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(ask?.title ?? "", isPresented: shown, titleVisibility: .visible,
                                presenting: ask) { a in
                if a.hasDeposit {
                    Button(ExpenseSplitText.undoDeleteBoth, role: .destructive) { run(a, true) }
                    Button(ExpenseSplitText.undoOnly) { run(a, false) }
                } else {
                    Button(ExpenseSplitText.undoButton, role: .destructive) { run(a, false) }
                }
                Button("取消", role: .cancel) {}
            }
    }

    private func run(_ a: SplitUndoAsk, _ del: Bool) {
        let l = life
        DispatchQueue.main.async {
            ExpenseSplitActions.undo(a, deleteDeposit: del, life: l, store: ExpenseSplitStore.shared)
        }
    }
}
