import SwiftUI

// MARK: - 固定支出週期展開（共用）

/// 把連結到指定銀行 milestone 的「直接扣款 + 週期性」固定支出，
/// 從建立日依 recurrence 一路展開成每期一筆 BankDeposit（虛擬條目，
/// 用於顯示與餘額計算）。已截至「今天」為止。
fileprivate func expandedFixedExpenseWithdrawals(
    for bankMilestoneId: UUID,
    expenses: [Expense]
) -> [BankDeposit] {
    let now = Date()
    let cal = Calendar.current
    let candidates = expenses.filter { exp in
        exp.expenseType == .fixed
        && exp.recurrence != nil
        && exp.linkedBankMilestoneId == bankMilestoneId
        && exp.linkedCreditCardMilestoneId == nil
    }
    var result: [BankDeposit] = []
    for exp in candidates {
        guard let recurrence = exp.recurrence else { continue }
        // 貸款類（房貸 / 車貸）的「日期」代表撥款日 / 起始日；
        // 第一次實際扣款是一個週期之後（撥款日 3/5 → 第一期 4/5）。
        // 其他類型（房租、訂閱、保費⋯）的日期就是第一次扣款日。
        var current = exp.date
        if exp.fixedCategory == .loan {
            current = nextRecurrenceDate(from: current, recurrence: recurrence, calendar: cal)
        }
        var idx = 0
        while current <= now && idx < 1200 {
            let stableId = stableDepositUUID(seed: "\(exp.id.uuidString)-\(idx)")
            result.append(BankDeposit(
                id: stableId,
                date: current,
                amount: exp.amount,
                currencyCode: exp.linkedBankCurrency ?? exp.currencyCode,
                isWithdrawal: true,
                linkedExpenseId: exp.id
            ))
            idx += 1
            current = nextRecurrenceDate(from: current, recurrence: recurrence, calendar: cal)
        }
    }
    return result
}

/// 依週期算下一次日期
private func nextRecurrenceDate(from date: Date, recurrence: Recurrence, calendar: Calendar) -> Date {
    switch recurrence {
    case .monthly:
        return calendar.date(byAdding: .month, value: 1, to: date) ?? date
    case .quarterly:
        return calendar.date(byAdding: .month, value: 3, to: date) ?? date
    case .yearly:
        return calendar.date(byAdding: .year, value: 1, to: date) ?? date
    }
}

// MARK: - 信用卡支出展開（共用）

/// 信用卡虛擬條目：每期一筆的金額與發生日（包含週期性固定支出自動展開後的每期）
fileprivate struct CreditCardEntry {
    let date: Date
    let amount: Double
    /// 真實的 Expense id（多期同 id 沒關係，僅供 deposit linkage 比對使用）
    let expenseId: UUID
}

/// 把連結到指定信用卡的支出展開：
/// - 一次性支出：直接帶入（date <= now 才算）
/// - 週期性固定支出：從 exp.date 依 recurrence 展開到今天，每期一筆虛擬條目
///   貸款類起始日視為撥款日，第一期從下一個週期開始（與 expandedFixedExpenseWithdrawals 一致）
fileprivate func expandedCreditCardEntries(
    forCard cardId: UUID,
    expenses: [Expense]
) -> [CreditCardEntry] {
    let now = Date()
    let cal = Calendar.current
    var output: [CreditCardEntry] = []
    for exp in expenses where exp.linkedCreditCardMilestoneId == cardId {
        if exp.expenseType == .fixed, let recurrence = exp.recurrence {
            var current = exp.date
            if exp.fixedCategory == .loan {
                current = nextRecurrenceDate(from: current, recurrence: recurrence, calendar: cal)
            }
            var idx = 0
            while current <= now && idx < 1200 {
                output.append(CreditCardEntry(date: current, amount: exp.amount, expenseId: exp.id))
                idx += 1
                current = nextRecurrenceDate(from: current, recurrence: recurrence, calendar: cal)
            }
        } else if exp.date <= now {
            output.append(CreditCardEntry(date: exp.date, amount: exp.amount, expenseId: exp.id))
        }
    }
    return output
}

/// 把連結到指定銀行 milestone 的「週期性」收入（月薪 / 年薪），
/// 從建立日依 period 一路展開成每期一筆 BankDeposit（虛擬條目，
/// 用於顯示與餘額計算）。已截至「今天」為止。
fileprivate func expandedIncomeDeposits(
    for bankMilestoneId: UUID,
    incomes: [Income]
) -> [BankDeposit] {
    let now = Date()
    let cal = Calendar.current
    let candidates = incomes.filter {
        $0.period != .once
        && $0.linkedBankMilestoneId == bankMilestoneId
    }
    var result: [BankDeposit] = []
    for inc in candidates {
        var current = inc.date
        var idx = 0
        while current <= now && idx < 1200 {
            let stableId = stableDepositUUID(seed: "inc-\(inc.id.uuidString)-\(idx)")
            result.append(BankDeposit(
                id: stableId,
                date: current,
                amount: inc.amount,
                currencyCode: inc.linkedBankCurrency ?? "NT$",
                isWithdrawal: false,
                linkedExpenseId: inc.id
            ))
            idx += 1
            switch inc.period {
            case .monthly:
                current = cal.date(byAdding: .month, value: 1, to: current) ?? current
            case .yearly:
                current = cal.date(byAdding: .year, value: 1, to: current) ?? current
            case .once:
                break
            }
        }
    }
    return result
}

/// 從種子字串產生穩定 UUID，給虛擬 BankDeposit 用
fileprivate func stableDepositUUID(seed: String) -> UUID {
    var hasher = Hasher()
    hasher.combine(seed)
    var x = UInt(bitPattern: hasher.finalize())
    var bytes: [UInt8] = []
    for _ in 0..<8 {
        bytes.append(UInt8(x & 0xFF))
        x >>= 8
    }
    var hasher2 = Hasher()
    hasher2.combine(seed)
    hasher2.combine("fix")
    var y = UInt(bitPattern: hasher2.finalize())
    for _ in 0..<8 {
        bytes.append(UInt8(y & 0xFF))
        y >>= 8
    }
    return UUID(uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
    ))
}

struct LifeFinanceView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var selectedSub: FinanceSubCategory?
    @State private var viewingItem: LifeMilestone?
    @State private var showAdd = false
    @State private var showPremiumAlert = false

    private var financeMilestones: [LifeMilestone] {
        lifeStore.milestones
            .filter { $0.category == .achievement && $0.linkedBankMilestoneId == nil }
            .sorted { $0.date > $1.date }
    }

    /// 所有理財里程碑（含銀行下的信用卡），用於總覽計數
    private var allFinanceMilestones: [LifeMilestone] {
        lifeStore.milestones.filter { $0.category == .achievement }
    }

    private var filteredMilestones: [LifeMilestone] {
        if let sub = selectedSub {
            return financeMilestones.filter { $0.financeSubCategory == sub }
        }
        return financeMilestones
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader
                filterChips
                milestoneList
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("財富")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        Text(formatTwdShort(allBankBalanceInTWD))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(allBankBalanceInTWD >= 0 ? Color.blue : Color.red)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Button {
                            if subscription.isPremium { showAdd = true }
                            else { showPremiumAlert = true }
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddMilestoneView(initialCategory: .achievement)
            }
            .sheet(item: $viewingItem) { item in
                FinanceCardView(milestoneId: item.id)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    // MARK: - 摘要

    private var summaryHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("理財帳戶總覽").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(allFinanceMilestones.count) 筆").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                ForEach(FinanceSubCategory.allCases) { sub in
                    let count = allFinanceMilestones.filter { $0.financeSubCategory == sub }.count
                    VStack(spacing: 2) {
                        Image(systemName: sub.icon).font(.title3).foregroundStyle(colorFor(sub))
                        Text("\(count)").font(.caption.bold())
                        Text(sub.rawValue).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - 篩選

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(label: "全部", isSelected: selectedSub == nil) { selectedSub = nil }
                ForEach(FinanceSubCategory.allCases) { sub in
                    let count = financeMilestones.filter { $0.financeSubCategory == sub }.count
                    if count > 0 {
                        chipButton(label: "\(sub.rawValue) \(count)", isSelected: selectedSub == sub) { selectedSub = sub }
                    }
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    private func chipButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? Color.green : Color(.tertiarySystemFill))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 列表

    private func linkedCards(for bankId: UUID) -> [LifeMilestone] {
        lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .creditCard && $0.linkedBankMilestoneId == bankId
        }
    }

    private var milestoneList: some View {
        List {
            ForEach(filteredMilestones) { item in
                VStack(spacing: 0) {
                    milestoneRow(item)
                        .contentShape(Rectangle())
                        .onTapGesture { viewingItem = item }

                    if item.financeSubCategory == .bank {
                        let cards = linkedCards(for: item.id)
                        if !cards.isEmpty {
                            ForEach(cards) { card in
                                creditCardSubRow(card)
                                    .contentShape(Rectangle())
                                    .onTapGesture { viewingItem = card }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func creditCardSubRow(_ card: LifeMilestone) -> some View {
        let disabled = card.isDisabled == true
        return HStack(spacing: 8) {
            Rectangle().fill(Color.clear).frame(width: 20)
            Image(systemName: "creditcard.fill")
                .font(.caption)
                .foregroundStyle(disabled ? Color.secondary : .orange)
                .frame(width: 24, height: 24)
                .background((disabled ? Color.secondary : Color.orange).opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(card.cardName ?? card.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(disabled ? .secondary : .primary)
                    if disabled {
                        Text("已停用")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.18))
                            .foregroundStyle(.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                HStack(spacing: 4) {
                    if let lf = card.cardLastFour, !lf.isEmpty {
                        Text("末\(lf)").font(.caption2).foregroundStyle(.tertiary)
                    }
                    if let bd = card.billingDay, let pd = card.paymentDay {
                        Text("帳單\(bd)日 繳款\(pd)日")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .opacity(disabled ? 0.7 : 1.0)
    }

    private func milestoneRow(_ item: LifeMilestone) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.financeSubCategory?.icon ?? "banknote.fill")
                .font(.title3)
                .foregroundStyle(colorFor(item.financeSubCategory ?? .bank))
                .frame(width: 36, height: 36)
                .background(colorFor(item.financeSubCategory ?? .bank).opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.medium))
                subtitle(for: item)
            }
            Spacer()
            if item.financeSubCategory == .bank {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("開戶日期：\(formatDate(item.date))")
                        .font(.caption2).foregroundStyle(.tertiary)
                    let balances = bankBalances(for: item)
                    let display = bankBalanceDisplay(balances: balances)
                    Text(display.text)
                        .font(.caption.bold())
                        .foregroundStyle(display.amount >= 0 ? Color.blue : Color.red)
                }
            } else {
                Text(formatDate(item.date)).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    /// 依幣別計算銀行帳戶的目前餘額（含信用卡彙總扣款 NT$ + 股票交易 + 固定支出週期展開）
    private func bankBalances(for ms: LifeMilestone) -> [String: Double] {
        let now = Date()
        var totals: [String: Double] = [:]
        for dep in ms.bankDeposits ?? [] where dep.date <= now {
            // 跳過已連結到信用卡支出的存款（用信用卡彙總取代）
            if let expId = dep.linkedExpenseId,
               let exp = expenseStore.expenses.first(where: { $0.id == expId }),
               exp.linkedCreditCardMilestoneId != nil { continue }
            // 跳過已連結到固定支出（含週期）的存款 — 改用展開的虛擬條目取代，避免漏算或重算
            if let expId = dep.linkedExpenseId,
               let exp = expenseStore.expenses.first(where: { $0.id == expId }),
               exp.expenseType == .fixed, exp.recurrence != nil { continue }
            // 跳過已連結到週期性收入的存款 — 改用展開的虛擬條目取代
            if let incId = dep.linkedExpenseId,
               let inc = expenseStore.incomes.first(where: { $0.id == incId }),
               inc.period != .once { continue }
            totals[dep.currencyCode, default: 0] += dep.isWithdrawal ? -dep.amount : dep.amount
        }
        // 固定支出（直接扣銀行）依週期展開為每期扣款
        for dep in expandedFixedExpenseWithdrawals(for: ms.id, expenses: expenseStore.expenses) {
            totals[dep.currencyCode, default: 0] -= dep.amount
        }
        // 週期性收入依 period 展開為每期入帳
        for dep in expandedIncomeDeposits(for: ms.id, incomes: expenseStore.incomes) {
            totals[dep.currencyCode, default: 0] += dep.amount
        }
        // 信用卡彙總扣款一律以 NT$ 計（週期性固定支出依 recurrence 展開到今天）
        let cards = lifeStore.milestones.filter {
            $0.financeSubCategory == .creditCard && $0.linkedBankMilestoneId == ms.id
        }
        for card in cards {
            let entries = expandedCreditCardEntries(forCard: card.id, expenses: expenseStore.expenses)
            for entry in entries { totals["NT$", default: 0] -= entry.amount }
        }
        // 過濾掉淨額為 0 的幣別（避免單一幣別帳戶被誤判為混幣）
        let nonZero = totals.filter { $0.value != 0 }
        return nonZero.isEmpty ? totals : nonZero
    }

    /// 將某帳戶的所有幣別餘額換算成 TWD 加總
    private func balanceInTWD(_ balances: [String: Double]) -> Double {
        var total: Double = 0
        for (code, amount) in balances {
            if code == "NT$" {
                total += amount
            } else if let rate = expenseStore.currencyRates.first(where: { $0.code == code }), rate.rate > 0 {
                total += amount * rate.rate
            } else {
                total += amount  // 找不到匯率時不換算，至少不丟失資料
            }
        }
        return total
    }

    /// 帳戶餘額顯示：單幣別→該幣別；多幣別→換算 TWD 等值
    private func bankBalanceDisplay(balances: [String: Double]) -> (text: String, amount: Double) {
        if balances.count <= 1 {
            let entry = balances.first ?? ("NT$", 0)
            return ("\(entry.0) \(formatNumber(entry.1))", entry.1)
        }
        let twd = balanceInTWD(balances)
        return ("≈ NT$ \(formatNumber(twd))", twd)
    }

    /// 所有銀行帳戶的台幣等值總和
    private var allBankBalanceInTWD: Double {
        let banks = lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .bank
        }
        return banks.reduce(0) { $0 + balanceInTWD(bankBalances(for: $1)) }
    }

    private func formatNumber(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "0"
    }

    private func formatTwdShort(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        if abs(v) >= 100_000_000 {
            let s = f.string(from: NSNumber(value: v / 100_000_000)) ?? "0"
            return "NT$ \(s) 億"
        }
        if abs(v) >= 10_000 {
            let s = f.string(from: NSNumber(value: v / 10_000)) ?? "0"
            return "NT$ \(s) 萬"
        }
        let s = f.string(from: NSNumber(value: v)) ?? "0"
        return "NT$ \(s)"
    }

    @ViewBuilder
    private func subtitle(for item: LifeMilestone) -> some View {
        switch item.financeSubCategory {
        case .bank:
            let parts = [item.branchName, item.bankAccountType?.rawValue].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty { Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        case .creditCard:
            let parts = [item.cardName, item.cardLastFour.map { "末\($0)" }].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty { Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        case .securities:
            if let accType = item.securitiesAccountType { Text(accType.rawValue).font(.caption).foregroundStyle(.secondary) }
        case .insurance:
            let parts = [item.insuranceType?.rawValue, item.policyNumber].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty { Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        case .none:
            if !item.note.isEmpty { Text(item.note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
    }

    private func colorFor(_ sub: FinanceSubCategory) -> Color {
        switch sub {
        case .bank: return .blue; case .creditCard: return .orange
        case .securities: return .green; case .insurance: return .purple
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }
}

// MARK: - 財富卡片詳細頁

struct FinanceCardView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var subscription: SubscriptionManager
    let milestoneId: UUID
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showAddDeposit = false
    @State private var addDepositCurrency = "NT$"
    @State private var editingDeposit: BankDeposit?
    @State private var viewingLinkedCard: LifeMilestone?
    @State private var depositsExpanded = false
    @State private var editingExpense: Expense?
    @State private var editingIncome: Income?
    @State private var editingStock: Stock?
    @State private var showPremiumAlert = false
    @State private var showDisableConfirm = false

    private var item: LifeMilestone {
        lifeStore.milestones.first(where: { $0.id == milestoneId })
            ?? LifeMilestone(title: "", category: .achievement)
    }

    private var sub: FinanceSubCategory { item.financeSubCategory ?? .bank }

    private var color: Color {
        switch sub {
        case .bank: return .blue; case .creditCard: return .orange
        case .securities: return .green; case .insurance: return .purple
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    detailCard
                    if sub == .bank || sub == .securities { depositSection }
                    if sub == .bank { linkedCreditCardSection }
                    if sub == .creditCard { creditCardChartSection }
                    if !item.note.isEmpty { noteCard }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("財富卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            if subscription.isPremium { showEdit = true }
                            else { showPremiumAlert = true }
                        } label: { Text("編輯").foregroundStyle(.green) }
                        Button {
                            if subscription.isPremium { showDeleteConfirm = true }
                            else { showPremiumAlert = true }
                        } label: { Text("刪除").foregroundStyle(.red) }
                    }
                }
            }
            .sheet(isPresented: $showEdit) { AddMilestoneView(editing: item) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .sheet(item: $viewingLinkedCard) { card in
                FinanceCardView(milestoneId: card.id)
            }
            .sheet(isPresented: $showAddDeposit) {
                DepositEditorSheet(milestoneId: milestoneId, currency: addDepositCurrency, editing: nil)
            }
            .sheet(item: $editingDeposit) { dep in
                DepositEditorSheet(milestoneId: milestoneId, currency: dep.currencyCode, editing: dep)
            }
            .sheet(item: $editingExpense) { exp in
                AddExpenseView(expenseType: exp.expenseType, editingExpense: exp)
            }
            .sheet(item: $editingIncome) { inc in
                AddIncomeView(editing: inc)
            }
            .sheet(item: $editingStock) { stk in
                AddStockView(editing: stk)
            }
            .alert("確定要刪除嗎？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) { lifeStore.deleteMilestone(item); dismiss() }
                Button("取消", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private var headerCard: some View {
        switch sub {
        case .creditCard: creditCardHeader
        case .bank:       bankPassbookHeader
        default:          defaultHeader
        }
    }

    /// 預設樣式（證券／保險）
    private var defaultHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: sub.icon)
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(
                    LinearGradient(colors: [color, color.opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(Circle())

            Text(item.title).font(.title3.bold())
            Text(sub.rawValue)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(color.opacity(0.12))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(fmtDate(item.date)).font(.caption).foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    /// 信用卡樣式（仿真實信用卡 banner）
    private var creditCardHeader: some View {
        let disabled = item.isDisabled == true
        let cardName = item.cardName?.isEmpty == false ? item.cardName! : item.title
        let last4 = item.cardLastFour ?? "----"
        let bankName: String? = {
            guard let bid = item.linkedBankMilestoneId,
                  let b = lifeStore.milestones.first(where: { $0.id == bid }) else { return nil }
            return b.bankName ?? b.title
        }()
        let gradient: [Color] = disabled
            ? [Color(white: 0.55), Color(white: 0.30)]
            : [Color(red: 0.95, green: 0.55, blue: 0.20),
               Color(red: 0.75, green: 0.30, blue: 0.10)]

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if let bn = bankName, !bn.isEmpty {
                        Text(bn)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    Text("CREDIT CARD")
                        .font(.caption2.weight(.bold).monospaced())
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                Image(systemName: "wave.3.right")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
            }

            // 晶片
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.75)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 40, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
                )

            // 卡號
            Text("•••• •••• •••• \(last4)")
                .font(.title3.weight(.semibold).monospaced())
                .tracking(2)
                .foregroundStyle(.white)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CARD HOLDER").font(.system(size: 9)).tracking(1.5)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(cardName.uppercased())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                if let ed = item.expiryDate {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("VALID THRU").font(.system(size: 9)).tracking(1.5)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(fmtMonthYear(ed))
                            .font(.subheadline.weight(.semibold).monospaced())
                            .foregroundStyle(.white)
                    }
                }
            }

            if disabled {
                Text("已停用")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.white.opacity(0.2))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)
        .padding(.horizontal)
    }

    /// 銀行存摺樣式
    private var bankPassbookHeader: some View {
        let bn = item.bankName?.isEmpty == false ? item.bankName! : item.title
        let branch = item.branchName ?? ""
        let acc = item.accountNumber ?? ""
        let accType = item.bankAccountType?.rawValue ?? ""
        return VStack(alignment: .leading, spacing: 0) {
            // 上半 — 像存摺封面
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "building.columns.fill")
                        .foregroundStyle(.white.opacity(0.95))
                    Text("BANK PASSBOOK")
                        .font(.caption2.weight(.bold).monospaced())
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                }
                Text(bn).font(.title3.bold()).foregroundStyle(.white)
                Text("存摺").font(.caption).foregroundStyle(.white.opacity(0.85))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color(red: 0.20, green: 0.40, blue: 0.75),
                                        Color(red: 0.12, green: 0.25, blue: 0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )

            // 下半 — 像存摺內頁
            VStack(spacing: 8) {
                if !branch.isEmpty {
                    passbookRow(label: "分行", value: branch)
                }
                if !acc.isEmpty {
                    passbookRow(label: "帳號", value: acc)
                }
                if !accType.isEmpty {
                    passbookRow(label: "類型", value: accType)
                }
                passbookRow(label: "開戶日", value: fmtDate(item.date))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, y: 3)
        .padding(.horizontal)
    }

    private func passbookRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium).monospaced())
        }
        .padding(.vertical, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 0.5)
                .offset(y: 4)
        }
    }

    private func fmtMonthYear(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/yy"
        return f.string(from: d)
    }

    private func fmtYearMonthZh(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy 年 M 月"
        return f.string(from: d)
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch sub {
            case .bank: bankDetail
            case .creditCard: creditCardDetail
            case .securities: securitiesDetail
            case .insurance: insuranceDetail
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    @ViewBuilder
    private var bankDetail: some View {
        if let b = item.branchName, !b.isEmpty { infoRow("分行", b) }
        if let a = item.accountNumber, !a.isEmpty { infoRow("帳號", a) }
        if let t = item.bankAccountType { infoRow("帳戶類型", t.rawValue) }
        infoRow("開戶日期", fmtDate(item.date))
    }

    @ViewBuilder
    private var creditCardDetail: some View {
        if let c = item.cardName, !c.isEmpty { infoRow("卡別", c) }
        if let l = item.cardLastFour, !l.isEmpty { infoRow("卡號末四碼", l) }
        if let cl = item.creditLimit, cl > 0 { infoRow("額度", "\(fmtNum(cl / 10000)) 萬元") }
        if let af = item.annualFee, af > 0 { infoRow("年費", "NT$\(fmtNum(af))") }
        if let bd = item.billingDay { infoRow("帳單日", "每月 \(bd) 日") }
        if let pd = item.paymentDay { infoRow("繳款日", "每月 \(pd) 日") }
        infoRow("核卡日期", fmtDate(item.date))
        if let ed = item.expiryDate { infoRow("到期日", fmtYearMonthZh(ed)) }
        if let ec = item.easyCardNumber, !ec.isEmpty { infoRow("悠遊卡", ec) }
        if let ip = item.iPassNumber, !ip.isEmpty { infoRow("一卡通", ip) }
        if let hg = item.happyGoNumber, !hg.isEmpty { infoRow("Happy Go", hg) }
        infoRow("使用狀態", item.isDisabled == true ? "已停用" : "使用中")
        creditCardDisableButton
    }

    private var creditCardDisableButton: some View {
        let disabled = item.isDisabled == true
        return Button {
            if disabled {
                toggleCardDisabled(false)
            } else {
                showDisableConfirm = true
            }
        } label: {
            HStack {
                Image(systemName: disabled ? "checkmark.circle" : "nosign")
                Text(disabled ? "啟用卡片" : "停用卡片").font(.subheadline.weight(.medium))
                Spacer()
            }
            .foregroundStyle(disabled ? Color.green : Color.red)
            .padding(.horizontal).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            "停用此信用卡？停用後將不會出現在新增支出的信用卡選單，歷史紀錄仍會保留。",
            isPresented: $showDisableConfirm,
            titleVisibility: .visible
        ) {
            Button("停用", role: .destructive) { toggleCardDisabled(true) }
            Button("取消", role: .cancel) {}
        }
    }

    private func toggleCardDisabled(_ disabled: Bool) {
        var updated = item
        updated.isDisabled = disabled ? true : nil
        lifeStore.update(updated)
    }

    @ViewBuilder
    private var securitiesDetail: some View {
        if let a = item.accountNumber, !a.isEmpty { infoRow("帳號", a) }
        if let t = item.securitiesAccountType { infoRow("帳戶類型", t.rawValue) }
        infoRow("開戶日期", fmtDate(item.date))
    }

    @ViewBuilder
    private var insuranceDetail: some View {
        if let co = item.insuranceCompany, !co.isEmpty { infoRow("保險公司", co) }
        if let pn = item.policyNumber, !pn.isEmpty { infoRow("保單號碼", pn) }
        if let it = item.insuranceType { infoRow("險種", it.rawValue) }
        if let pa = item.premiumAmount, pa > 0 { infoRow("保費", "NT$\(fmtNum(pa))") }
        infoRow("生效日", fmtDate(item.date))
        if let ed = item.expiryDate { infoRow("到期日", fmtDate(ed)) }
        if let b = item.beneficiary, !b.isEmpty { infoRow("受益人", b) }
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("備註").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(item.note).font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline)
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    private func fmtDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }

    private func fmtNum(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "0"
    }

    // MARK: - 銀行存款章節

    /// 銀行存款列表：真實 BankDeposit + 信用卡逐月彙總 + 固定支出週期展開 + 週期性收入展開
    private var deposits: [BankDeposit] {
        let now = Date()
        let real = (item.bankDeposits ?? []).filter { dep in
            guard dep.date <= now else { return false }
            guard let linkedId = dep.linkedExpenseId else { return true }
            // 連結到 Expense
            if let exp = expenseStore.expenses.first(where: { $0.id == linkedId }) {
                // 信用卡支出：用每月彙總取代
                if exp.linkedCreditCardMilestoneId != nil { return false }
                // 固定支出（週期）：用展開虛擬條目取代
                if exp.expenseType == .fixed && exp.recurrence != nil { return false }
                return true
            }
            // 連結到 Income（週期性 → 用展開取代）
            if let inc = expenseStore.incomes.first(where: { $0.id == linkedId }) {
                if inc.period != .once { return false }
            }
            return true
        }
        let aggregated = aggregatedCreditCardWithdrawals()
        let fixedExpanded = expandedFixedExpenseWithdrawals(
            for: milestoneId,
            expenses: expenseStore.expenses
        )
        let incomeExpanded = expandedIncomeDeposits(
            for: milestoneId,
            incomes: expenseStore.incomes
        )
        return (real + aggregated + fixedExpanded + incomeExpanded).sorted { $0.date < $1.date }
    }

    /// 將連結到本銀行的信用卡支出依月份彙總成虛擬 BankDeposit。
    /// 週期性固定支出（每月 / 每季 / 每年）會依 recurrence 自動展開到今天，
    /// 例如「4/6 開始的月繳訂閱」會自動產生 4/6、5/6、6/6 …的扣款條目。
    private func aggregatedCreditCardWithdrawals() -> [BankDeposit] {
        let cards = lifeStore.milestones.filter {
            $0.financeSubCategory == .creditCard && $0.linkedBankMilestoneId == milestoneId
        }
        var result: [BankDeposit] = []
        for card in cards {
            let entries = expandedCreditCardEntries(forCard: card.id, expenses: expenseStore.expenses)
            let groups = Dictionary(grouping: entries) { entry -> String in
                let withdrawalDate = LifeMilestone.creditCardWithdrawalDate(
                    for: entry.date,
                    billingDay: card.billingDay,
                    paymentDay: card.paymentDay
                )
                let comps = Calendar.current.dateComponents([.year, .month], from: withdrawalDate)
                return "\(comps.year ?? 0)-\(comps.month ?? 0)"
            }
            for (_, list) in groups {
                let total = list.reduce(0.0) { $0 + $1.amount }
                let firstDate = list.first?.date ?? Date()
                let withdrawalDate = LifeMilestone.creditCardWithdrawalDate(
                    for: firstDate,
                    billingDay: card.billingDay,
                    paymentDay: card.paymentDay
                )
                let stableId = stableUUID(seed: "\(card.id)-\(withdrawalDate.timeIntervalSince1970)")
                result.append(BankDeposit(
                    id: stableId,
                    date: withdrawalDate,
                    amount: total,
                    currencyCode: "NT$",
                    isWithdrawal: true,
                    linkedExpenseId: nil
                ))
            }
        }
        return result
    }

    private func stableUUID(seed: String) -> UUID {
        var hasher = Hasher()
        hasher.combine(seed)
        var x = UInt(bitPattern: hasher.finalize())
        var bytes: [UInt8] = []
        for _ in 0..<8 {
            bytes.append(UInt8(x & 0xFF))
            x >>= 8
        }
        var hasher2 = Hasher()
        hasher2.combine(seed)
        hasher2.combine("vc")
        var y = UInt(bitPattern: hasher2.finalize())
        for _ in 0..<8 {
            bytes.append(UInt8(y & 0xFF))
            y >>= 8
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private var depositSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "dollarsign.circle.fill").foregroundStyle(.blue)
                Text(sub == .securities ? "證券交易" : "銀行存款").font(.headline)
                Spacer()
                Menu {
                    Button { addDepositCurrency = "NT$"; showAddDeposit = true } label: {
                        Label("台幣", systemImage: "dollarsign")
                    }
                    ForEach(expenseStore.currencyRates) { rate in
                        Button { addDepositCurrency = rate.code; showAddDeposit = true } label: {
                            Label(rate.code, systemImage: "coloncurrencysign")
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.blue)
                }
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)

            if deposits.isEmpty {
                Text("尚無存款記錄").font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal).padding(.bottom, 12)
            } else {
                depositChart
                    .padding(.horizontal).padding(.bottom, 8)

                let sortedDesc = deposits.sorted { $0.date > $1.date }
                let visible = depositsExpanded ? sortedDesc : Array(sortedDesc.prefix(6))
                ForEach(visible, id: \.id) { dep in
                    depositRow(dep)
                }
                if sortedDesc.count > 6 {
                    Button {
                        withAnimation { depositsExpanded.toggle() }
                    } label: {
                        HStack {
                            Spacer()
                            Text(depositsExpanded ? "收起" : "展開全部 (\(sortedDesc.count) 筆)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.blue)
                            Image(systemName: depositsExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 信用卡圖表章節（顯示於信用卡卡片）

    private struct CreditCardMonthlyTotal: Identifiable {
        let id: String
        let date: Date
        let amount: Double
    }

    private var creditCardMonthlyTotals: [CreditCardMonthlyTotal] {
        let entries = expandedCreditCardEntries(forCard: milestoneId, expenses: expenseStore.expenses)
        let groups = Dictionary(grouping: entries) { entry -> String in
            let withdrawalDate = LifeMilestone.creditCardWithdrawalDate(
                for: entry.date,
                billingDay: item.billingDay,
                paymentDay: item.paymentDay
            )
            let comps = Calendar.current.dateComponents([.year, .month], from: withdrawalDate)
            return "\(comps.year ?? 0)-\(comps.month ?? 0)"
        }
        return groups.compactMap { (key, list) -> CreditCardMonthlyTotal? in
            guard let first = list.first else { return nil }
            let withdrawalDate = LifeMilestone.creditCardWithdrawalDate(
                for: first.date,
                billingDay: item.billingDay,
                paymentDay: item.paymentDay
            )
            let total = list.reduce(0.0) { $0 + $1.amount }
            return CreditCardMonthlyTotal(id: key, date: withdrawalDate, amount: total)
        }
        .sorted { $0.date < $1.date }
    }

    /// 消費趨勢：每筆消費一根柱子；同日的合併為一根
    private struct CreditCardDailyTotal: Identifiable {
        let id: String
        let date: Date
        let amount: Double
    }

    private var creditCardDailyTotals: [CreditCardDailyTotal] {
        let entries = expandedCreditCardEntries(forCard: milestoneId, expenses: expenseStore.expenses)
        let calendar = Calendar.current
        let groups = Dictionary(grouping: entries) { entry -> String in
            let comps = calendar.dateComponents([.year, .month, .day], from: entry.date)
            return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
        }
        return groups.compactMap { (key, list) -> CreditCardDailyTotal? in
            guard let first = list.first else { return nil }
            let total = list.reduce(0.0) { $0 + $1.amount }
            return CreditCardDailyTotal(id: key, date: first.date, amount: total)
        }
        .sorted { $0.date < $1.date }
    }

    @State private var ccExpanded = false

    private var creditCardExpenseItems: [Expense] {
        expenseStore.expenses
            .filter { $0.linkedCreditCardMilestoneId == milestoneId }
            .sorted { $0.date > $1.date }
    }

    private var creditCardChartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "chart.bar.fill").foregroundStyle(.orange)
                Text("消費趨勢").font(.headline)
                Spacer()
                Text("\(creditCardDailyTotals.count) 筆").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)

            if creditCardDailyTotals.isEmpty {
                Text("尚無扣款記錄").font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal).padding(.bottom, 12)
            } else {
                creditCardChart
                    .padding(.horizontal).padding(.bottom, 8)

                // 最近一期加總
                if let last = creditCardMonthlyTotals.last {
                    HStack {
                        Text("最近一期").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("-NT$ \(fmtNum(last.amount))").font(.caption.bold())
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal).padding(.bottom, 6)
                }

                Divider().padding(.horizontal)

                // 個別項目列表
                let items = creditCardExpenseItems
                let visible = ccExpanded ? items : Array(items.prefix(6))
                ForEach(visible) { exp in
                    Button { editingExpense = exp } label: {
                        HStack {
                            Text(fmtDate(exp.date)).font(.caption).foregroundStyle(.tertiary)
                            Text(exp.title).font(.caption).lineLimit(1)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("-NT$ \(fmtNum(exp.amount))")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.red)
                            Image(systemName: "chevron.right")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal).padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if items.count > 6 {
                    Button {
                        withAnimation { ccExpanded.toggle() }
                    } label: {
                        HStack {
                            Spacer()
                            Text(ccExpanded ? "收起" : "展開全部 (\(items.count) 筆)")
                                .font(.caption.weight(.medium)).foregroundStyle(.orange)
                            Image(systemName: ccExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2).foregroundStyle(.orange)
                            Spacer()
                        }
                        .padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    /// 把整串資料切成每頁 30 筆（由舊到新，最後一頁可能不足 30 筆）
    private var creditCardChartPages: [[CreditCardDailyTotal]] {
        let data = creditCardDailyTotals
        guard !data.isEmpty else { return [] }
        let pageSize = 30
        var pages: [[CreditCardDailyTotal]] = []
        var i = 0
        while i < data.count {
            let end = min(i + pageSize, data.count)
            pages.append(Array(data[i..<end]))
            i = end
        }
        return pages
    }

    @State private var chartCurrentPage: Int = 0

    @ViewBuilder
    private var creditCardChart: some View {
        let pages = creditCardChartPages
        if pages.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    let pageWidth = geo.size.width
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(Array(pages.enumerated()), id: \.offset) { idx, pageData in
                                creditCardChartPage(data: pageData)
                                    .frame(width: pageWidth)
                                    .id(idx)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: Binding<Int?>(
                        get: { chartCurrentPage },
                        set: { if let v = $0 { chartCurrentPage = v } }
                    ))
                }
                .frame(height: 150)

                if pages.count > 1 {
                    HStack(spacing: 6) {
                        Spacer()
                        ForEach(0..<pages.count, id: \.self) { i in
                            Circle()
                                .fill(i == chartCurrentPage ? Color.orange : Color.secondary.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    /// 單一頁的長條圖：Y 軸最大值依本頁資料 fit
    @ViewBuilder
    private func creditCardChartPage(data: [CreditCardDailyTotal]) -> some View {
        let maxAmount = data.map(\.amount).max() ?? 1
        let labelStride = max(1, data.count / 6)
        GeometryReader { geo in
            let chartHeight: CGFloat = 120
            let barAreaWidth = geo.size.width
            let barWidth = max(4, (barAreaWidth - CGFloat(data.count - 1) * 4) / CGFloat(max(data.count, 1)))
            VStack(spacing: 2) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(data.enumerated()), id: \.element.id) { _, row in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.red)
                            .frame(
                                width: barWidth,
                                height: max(4, CGFloat(row.amount / max(maxAmount, 1)) * chartHeight)
                            )
                    }
                }
                .frame(height: chartHeight, alignment: .bottom)

                HStack(alignment: .top, spacing: 4) {
                    ForEach(Array(data.enumerated()), id: \.element.id) { idx, row in
                        Text(idx % labelStride == 0 ? shortDate(row.date) : " ")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                            .frame(width: barWidth)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
    }

    // MARK: - 信用卡章節

    private var linkedCreditCards: [LifeMilestone] {
        lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .creditCard && $0.linkedBankMilestoneId == milestoneId
        }
    }

    private var linkedCreditCardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "creditcard.fill").foregroundStyle(.orange)
                Text("信用卡").font(.headline)
                Spacer()
                Text("\(linkedCreditCards.count) 張").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)

            if linkedCreditCards.isEmpty {
                Text("尚無信用卡").font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal).padding(.bottom, 12)
            } else {
                ForEach(linkedCreditCards) { card in
                    Button { viewingLinkedCard = card } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "creditcard.fill")
                                .font(.caption).foregroundStyle(.orange).frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.title).font(.subheadline.weight(.medium)).foregroundStyle(Color.primary)
                                HStack(spacing: 4) {
                                    if let cn = card.cardName, !cn.isEmpty { Text(cn).font(.caption).foregroundStyle(.secondary) }
                                    if let lf = card.cardLastFour, !lf.isEmpty { Text("末\(lf)").font(.caption).foregroundStyle(.tertiary) }
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal).padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func isVirtualCreditCardEntry(_ dep: BankDeposit) -> Bool {
        !(item.bankDeposits ?? []).contains(where: { $0.id == dep.id })
    }

    /// 根據聚合條目 id 比對產生它的信用卡（含週期性固定支出展開後的虛擬條目）
    private func matchingAggregatedCard(card: LifeMilestone, depositId: UUID) -> LifeMilestone? {
        let entries = expandedCreditCardEntries(forCard: card.id, expenses: expenseStore.expenses)
        let groups = Dictionary(grouping: entries) { entry -> String in
            let date = LifeMilestone.creditCardWithdrawalDate(
                for: entry.date, billingDay: card.billingDay, paymentDay: card.paymentDay
            )
            let comps = Calendar.current.dateComponents([.year, .month], from: date)
            return "\(comps.year ?? 0)-\(comps.month ?? 0)"
        }
        for (_, list) in groups {
            guard let first = list.first else { continue }
            let date = LifeMilestone.creditCardWithdrawalDate(
                for: first.date, billingDay: card.billingDay, paymentDay: card.paymentDay
            )
            if stableUUID(seed: "\(card.id)-\(date.timeIntervalSince1970)") == depositId {
                return card
            }
        }
        return nil
    }

    /// 點擊存款列：依連結類型開對應的編輯頁
    private func handleDepositTap(_ dep: BankDeposit, isVirtual: Bool, isStock: Bool) {
        // 信用卡彙總：尋找產生此虛擬條目的信用卡並開啟
        if isVirtual {
            let cards = lifeStore.milestones.filter {
                $0.financeSubCategory == .creditCard && $0.linkedBankMilestoneId == milestoneId
            }
            for card in cards {
                if let matched = matchingAggregatedCard(card: card, depositId: dep.id) {
                    viewingLinkedCard = matched
                    return
                }
            }
            if let first = cards.first { viewingLinkedCard = first }
            return
        }
        // 股票交易：開啟股票編輯
        if let stockId = dep.linkedStockId,
           let stock = financeStore.stocks.first(where: { $0.id == stockId }) {
            editingStock = stock
            return
        }
        // 連結支出/收入
        if let expId = dep.linkedExpenseId {
            if let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
                editingExpense = exp
                return
            }
            if let inc = expenseStore.incomes.first(where: { $0.id == expId }) {
                editingIncome = inc
                return
            }
        }
        // 手動存款記錄：用 DepositEditorSheet
        editingDeposit = dep
    }

    private func depositRow(_ dep: BankDeposit) -> some View {
        let isVirtual = isVirtualCreditCardEntry(dep)
        let isStock = dep.linkedStockId != nil
        let badgeText: String? = {
            if dep.isAdjust { return "沖正" }
            if isStock {
                if dep.isWithdrawal { return "買入/虧損" }
                return "賣出獲利"
            }
            if isVirtual { return "信用卡" }
            if dep.linkedExpenseId != nil { return dep.isWithdrawal ? "扣款" : "收入" }
            return dep.isWithdrawal ? "提款" : "存款"
        }()
        let badgeColor: Color = {
            if dep.isAdjust { return .indigo }
            if isStock { return .purple }
            if isVirtual { return .orange }
            if dep.isWithdrawal { return .red }
            return .green
        }()
        return Button {
            handleDepositTap(dep, isVirtual: isVirtual, isStock: isStock)
        } label: {
            HStack {
                Text(fmtDate(dep.date)).font(.caption).foregroundStyle(.tertiary)
                if let txt = badgeText {
                    Text(txt).font(.caption2).foregroundStyle(badgeColor)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(badgeColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Spacer()
                Text("\(dep.isWithdrawal ? "-" : "")\(dep.currencyCode) \(fmtNum(dep.amount))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(
                        isStock ? (dep.isWithdrawal ? Color.red : Color.green) :
                        (dep.isWithdrawal ? (isVirtual ? Color.orange : Color.red) :
                         (dep.currencyCode == "NT$" ? Color.primary : Color.blue))
                    )
            }
            .padding(.horizontal).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var depositChart: some View {
        let data = deposits
        var balances: [(date: Date, balance: Double, id: UUID)] = []
        var running: Double = 0
        for dep in data {
            if dep.isWithdrawal { running -= dep.amount } else { running += dep.amount }
            balances.append((dep.date, running, dep.id))
        }
        let maxBal = balances.map(\.balance).max() ?? 1
        let minBal = min(0, balances.map(\.balance).min() ?? 0)
        let range = max(maxBal - minBal, 1)
        let useLineChart = balances.count > 12
        let labelStride = max(1, balances.count / 6)

        return VStack(alignment: .leading, spacing: 4) {
            if useLineChart {
                balanceLineChart(balances: balances, minBal: minBal, range: range, labelStride: labelStride)
            } else {
                balanceBarChart(balances: balances, minBal: minBal, range: range, labelStride: labelStride)
            }

            if let last = balances.last {
                HStack {
                    Text("目前總額").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(fmtNum(last.balance))").font(.caption.bold())
                        .foregroundStyle(last.balance >= 0 ? Color.blue : Color.red)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: date)
    }

    private func barColor(for dep: BankDeposit) -> Color {
        if dep.isWithdrawal { return .red }
        return dep.currencyCode == "NT$" ? .blue : .orange
    }

    @ViewBuilder
    private func balanceBarChart(
        balances: [(date: Date, balance: Double, id: UUID)],
        minBal: Double,
        range: Double,
        labelStride: Int
    ) -> some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(balances.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(item.balance >= 0 ? Color.blue : Color.red)
                        .frame(
                            width: max(12, (UIScreen.main.bounds.width - 80) / CGFloat(max(balances.count, 1))),
                            height: max(4, CGFloat(abs(item.balance - minBal) / range) * 120)
                        )
                    Text(index % labelStride == 0 ? shortDate(item.date) : " ")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(height: 140, alignment: .bottom)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func balanceLineChart(
        balances: [(date: Date, balance: Double, id: UUID)],
        minBal: Double,
        range: Double,
        labelStride: Int
    ) -> some View {
        let chartHeight: CGFloat = 120
        GeometryReader { geo in
            let width = geo.size.width
            let count = max(balances.count, 1)
            let stepX = count > 1 ? width / CGFloat(count - 1) : 0

            ZStack {
                // 零線
                if minBal < 0 {
                    let zeroY = chartHeight - CGFloat(-minBal / range) * chartHeight
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: zeroY))
                        p.addLine(to: CGPoint(x: width, y: zeroY))
                    }
                    .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                }

                // 折線
                Path { p in
                    for (i, item) in balances.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = chartHeight - CGFloat((item.balance - minBal) / range) * chartHeight
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // 填色
                Path { p in
                    for (i, item) in balances.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = chartHeight - CGFloat((item.balance - minBal) / range) * chartHeight
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    p.addLine(to: CGPoint(x: width, y: chartHeight))
                    p.addLine(to: CGPoint(x: 0, y: chartHeight))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.0)],
                                     startPoint: .top, endPoint: .bottom))

                // 數據點
                ForEach(Array(balances.enumerated()), id: \.element.id) { i, item in
                    let x = CGFloat(i) * stepX
                    let y = chartHeight - CGFloat((item.balance - minBal) / range) * chartHeight
                    Circle()
                        .fill(item.balance >= 0 ? Color.blue : Color.red)
                        .frame(width: 4, height: 4)
                        .position(x: x, y: y)
                }
            }
        }
        .frame(height: chartHeight)

        // X 軸日期（只渲染要顯示的標籤，平均分佈）
        let visibleLabels: [(index: Int, label: String)] = {
            var result: [(Int, String)] = []
            for i in stride(from: 0, to: balances.count, by: labelStride) {
                result.append((i, shortDate(balances[i].date)))
            }
            if let last = balances.last, (result.last?.0 ?? -1) != balances.count - 1 {
                result.append((balances.count - 1, shortDate(last.date)))
            }
            return result
        }()
        HStack {
            ForEach(visibleLabels, id: \.index) { item in
                Text(item.label)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - 存款編輯 Sheet

struct DepositEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    let milestoneId: UUID
    let currency: String
    var editing: BankDeposit?

    enum TransactionType: String, CaseIterable {
        case deposit = "存款"
        case withdrawal = "提款"
        case transfer = "轉帳"
        case adjust = "沖正"
    }

    @State private var txType: TransactionType = .deposit
    @State private var date = Date()
    @State private var amountText = ""
    @State private var transferTargetId: UUID?
    @State private var adjustNote = ""

    private var bankMilestones: [LifeMilestone] {
        lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .bank && $0.id != milestoneId
        }
    }

    private func bankBalance(for ms: LifeMilestone) -> Double {
        let now = Date()
        var total: Double = 0
        for dep in ms.bankDeposits ?? [] {
            guard dep.date <= now else { continue }
            if let expId = dep.linkedExpenseId,
               let exp = expenseStore.expenses.first(where: { $0.id == expId }),
               exp.linkedCreditCardMilestoneId != nil { continue }
            total += dep.isWithdrawal ? -dep.amount : dep.amount
        }
        return total
    }

    private var currentBalance: Double {
        guard let ms = lifeStore.milestones.first(where: { $0.id == milestoneId }) else { return 0 }
        return bankBalance(for: ms)
    }

    private func fmtNum(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "0"
    }

    private func fmtBal(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        if abs(v) >= 10000 {
            return "NT$ \(f.string(from: NSNumber(value: v / 10000)) ?? "0")萬"
        }
        return "NT$ \(f.string(from: NSNumber(value: v)) ?? "0")"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("類型", selection: $txType) {
                        ForEach(TransactionType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if txType == .transfer {
                    Section("轉帳資訊") {
                        Picker("轉入帳戶", selection: $transferTargetId) {
                            Text("請選擇").tag(nil as UUID?)
                            ForEach(bankMilestones) { ms in
                                let name = ms.bankName ?? ms.title
                                Text("\(name)（\(fmtBal(bankBalance(for: ms)))）")
                                    .tag(ms.id as UUID?)
                            }
                        }
                        DatePicker("日期", selection: $date, displayedComponents: .date)
                        HStack {
                            Text(currency).foregroundStyle(.secondary)
                            TextField("金額", text: $amountText).keyboardType(.decimalPad)
                        }
                    }
                } else if txType == .adjust {
                    Section("沖正") {
                        HStack {
                            Text("目前總額").foregroundStyle(.secondary)
                            Spacer()
                            Text(fmtBal(currentBalance)).foregroundStyle(.blue)
                        }
                        DatePicker("日期", selection: $date, displayedComponents: .date)
                        HStack {
                            Text(currency).foregroundStyle(.secondary)
                            TextField("調整後金額", text: $amountText).keyboardType(.decimalPad)
                        }
                        if let target = Double(amountText) {
                            let diff = target - currentBalance
                            HStack {
                                Text("差額").foregroundStyle(.secondary)
                                Spacer()
                                Text("\(diff >= 0 ? "+" : "")\(fmtNum(diff))")
                                    .foregroundStyle(diff >= 0 ? Color.green : Color.red)
                                    .bold()
                            }
                        }
                        TextField("備註（如：對帳調整）", text: $adjustNote, axis: .vertical).lineLimit(2...3)
                    }
                } else {
                    Section("\(currency) \(txType.rawValue)") {
                        DatePicker("日期", selection: $date, displayedComponents: .date)
                        HStack {
                            Text(currency).foregroundStyle(.secondary)
                            TextField("金額", text: $amountText).keyboardType(.decimalPad)
                        }
                    }
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) { delete() } label: { Label("刪除", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯" : "新增存款 / 提款 / 轉帳")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") {
                        switch txType {
                        case .transfer: saveTransfer()
                        case .adjust: saveAdjust()
                        default: save()
                        }
                    }
                    .bold().foregroundStyle(.green)
                    .disabled(saveDisabled)
                }
            }
            .onAppear {
                if let e = editing {
                    txType = e.isWithdrawal ? .withdrawal : .deposit
                    date = e.date
                    amountText = String(format: "%.0f", e.amount)
                }
            }
        }
    }

    private var saveDisabled: Bool {
        switch txType {
        case .deposit, .withdrawal: return (Double(amountText) ?? 0) <= 0
        case .transfer: return (Double(amountText) ?? 0) <= 0 || transferTargetId == nil
        case .adjust: return Double(amountText) == nil
        }
    }

    private func save() {
        guard var ms = lifeStore.milestones.first(where: { $0.id == milestoneId }) else { dismiss(); return }
        let dep = BankDeposit(id: editing?.id ?? UUID(), date: date, amount: Double(amountText) ?? 0,
                              currencyCode: currency, isWithdrawal: txType == .withdrawal)
        var list = ms.bankDeposits ?? []
        if let idx = list.firstIndex(where: { $0.id == dep.id }) { list[idx] = dep }
        else { list.append(dep) }
        ms.bankDeposits = list
        lifeStore.update(ms); dismiss()
    }

    private func saveTransfer() {
        let amount = Double(amountText) ?? 0
        guard amount > 0, let targetId = transferTargetId else { return }

        // 從本帳戶扣款
        if var fromMs = lifeStore.milestones.first(where: { $0.id == milestoneId }) {
            var fromList = fromMs.bankDeposits ?? []
            fromList.append(BankDeposit(
                id: UUID(), date: date, amount: amount,
                currencyCode: currency, isWithdrawal: true
            ))
            fromMs.bankDeposits = fromList
            lifeStore.update(fromMs)
        }

        // 轉入目標帳戶
        if var toMs = lifeStore.milestones.first(where: { $0.id == targetId }) {
            var toList = toMs.bankDeposits ?? []
            toList.append(BankDeposit(
                id: UUID(), date: date, amount: amount,
                currencyCode: currency, isWithdrawal: false
            ))
            toMs.bankDeposits = toList
            lifeStore.update(toMs)
        }

        dismiss()
    }

    private func saveAdjust() {
        guard let targetAmount = Double(amountText),
              var ms = lifeStore.milestones.first(where: { $0.id == milestoneId }) else { dismiss(); return }
        let diff = targetAmount - currentBalance
        guard diff != 0 else { dismiss(); return }
        var list = ms.bankDeposits ?? []
        let trimmedNote = adjustNote.trimmingCharacters(in: .whitespaces)
        list.append(BankDeposit(
            id: UUID(), date: date, amount: abs(diff),
            currencyCode: currency, isWithdrawal: diff < 0,
            isAdjust: true,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        ))
        ms.bankDeposits = list
        lifeStore.update(ms); dismiss()
    }

    private func delete() {
        guard let e = editing, var ms = lifeStore.milestones.first(where: { $0.id == milestoneId }) else { dismiss(); return }
        ms.bankDeposits?.removeAll { $0.id == e.id }
        lifeStore.update(ms); dismiss()
    }
}
