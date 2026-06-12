import SwiftUI

// MARK: - 美化紀錄（LifeFinanceView）
// [2026-06 v1] 本次美化方向：
//   1. summaryHeader → 升級為藍色漸層英雄卡片（對齊 SavingsInsuranceView summaryHeader 規格）：
//      銀行總餘額台幣等值大字 + 計數膠囊 + 餘額正負色 + 散景裝飾圓；
//      底部四欄 KPI（銀行 / 信用卡 / 證券 / 保險），對齊 FinanceChartView 英雄卡 KPI 規格；
//      headerAppeared spring 進場動畫（透明度 + Y 位移）。
//   2. filterChips → 加入底部分隔線 overlay + padding 對齊 IncomeView.categoryFilter 規格；
//      chip 樣式從純綠改為依選取分類主色動態著色，對齊 StockView / SavingsInsuranceView filter 規格。
//   3. milestoneRow → 圖示從 36pt 純色升級為 44pt 雙層漸層圓（LinearGradient 底色 + stroke），
//      對齊 IncomeView.incomeRow / StockView.stockCard 圖示視覺規格；
//      加入列表交錯淡入 + 向上進場動畫（rowsAppeared），對齊 VariableExpenseView 規格。
//   4. creditCardSubRow → 圖示從 24pt 升級為 32pt 漸層圓，對齊 milestoneRow 規格；
//      停用卡以 .tertiary 淡化，視覺上更一目了然。
// [2026-06 v2] FinanceCardView 美化方向（depositSection + depositRow + linkedCreditCardSection + creditCardChartSection）：
//   5. depositSection 標題列：Capsule 側條（藍色漸層）+ .semibold 標題 + 筆數計數膠囊，
//      對齊 OverviewView categoryBreakdownSection / CareerView milestoneListSection 標題規格。
//   6. depositRow：加入 36pt 漸層圖示圓（依類型分色圖示：存入/提款/信用卡/股票/沖正），
//      Badge 從 RoundedRectangle(cornerRadius:3) 升級為 Capsule + 細邊框（0.6pt）；
//      備註文字加入顯示（.caption2 .secondary），日期移至副文字行；
//      金額字型升為 .system(size:15, weight:.bold, design:.rounded) + contentTransition(.numericText())；
//      對齊 IncomeView.incomeRow / StockView.stockCard 視覺規格。
//   7. linkedCreditCardSection 標題列：同步升級 Capsule 側條（橙色）+ 張數膠囊；
//      信用卡列從 20pt 圖示升至 36pt 漸層圓（含 stroke），對齊 creditCardSubRow 36pt 規格。
//   8. creditCardChartSection 個別支出列：加入 32pt 漸層圓圖示（使用分類圖示），
//      日期從純文字改為 Capsule 徽章（tertiarySystemFill 底）；
//      金額字型升為 .system(size:14, weight:.bold, design:.rounded) + contentTransition；
//      對齊 OverviewView.recentRow 視覺語言，形成帳戶詳頁統一 row 規格。

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
    // 進場動畫旗標
    @State private var headerAppeared = false
    @State private var rowsAppeared = false

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
                    .opacity(headerAppeared ? 1 : 0)
                    .offset(y: headerAppeared ? 0 : 22)
                    .onAppear {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                            headerAppeared = true
                        }
                    }
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

    // MARK: - 摘要（英雄卡）

    private let heroAccent     = Color(red: 0.22, green: 0.53, blue: 0.98)
    private let heroAccentDark = Color(red: 0.10, green: 0.35, blue: 0.82)

    private var summaryHeader: some View {
        let balance = allBankBalanceInTWD
        let isPositive = balance >= 0
        // 一次取出，避免 ForEach 內 4 次重複 O(n) filter
        let milestones = allFinanceMilestones
        let totalCount = milestones.count
        let countBySub: [FinanceSubCategory: Int] = milestones.reduce(into: [:]) { dict, m in
            if let sub = m.financeSubCategory { dict[sub, default: 0] += 1 }
        }

        return VStack(spacing: 0) {
            // 頂部：銀行總餘額 + 計數膠囊
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("銀行帳戶總餘額（台幣等值）")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    Text(formatTwdShort(balance))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(isPositive ? .white : Color(red: 1.0, green: 0.78, blue: 0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .shadow(
                            color: isPositive ? .clear : Color.red.opacity(0.40),
                            radius: 6, x: 0, y: 2
                        )
                }
                Spacer()
                // 帳戶計數膠囊
                VStack(alignment: .trailing, spacing: 4) {
                    Text("帳戶總計")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                    Text("\(totalCount) 筆")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(.white.opacity(0.20))
                .clipShape(Capsule())
                .foregroundStyle(.white)
            }

            // 分隔線
            Rectangle()
                .fill(.white.opacity(0.20))
                .frame(height: 0.5)
                .padding(.vertical, 14)

            // 四欄 KPI：銀行 / 信用卡 / 證券 / 保險
            HStack(spacing: 0) {
                ForEach(Array(FinanceSubCategory.allCases.enumerated()), id: \.element) { i, sub in
                    let count = countBySub[sub, default: 0]
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.16))
                                .frame(width: 30, height: 30)
                            Image(systemName: sub.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text("\(count)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(sub.rawValue)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .frame(maxWidth: .infinity)

                    if i < FinanceSubCategory.allCases.count - 1 {
                        Rectangle()
                            .fill(.white.opacity(0.22))
                            .frame(width: 0.5, height: 36)
                    }
                }
            }
            .padding(.vertical, 6)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            ZStack {
                LinearGradient(
                    colors: [heroAccent, heroAccentDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 右上主散景圓
                Circle()
                    .fill(.white.opacity(0.13))
                    .frame(width: 140, height: 140)
                    .offset(x: 90, y: -55)
                    .blur(radius: 14)
                // 左下補光
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 90, height: 90)
                    .offset(x: -70, y: 55)
                    .blur(radius: 10)
                // 右下小散景（增加層次）
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 55, height: 55)
                    .offset(x: 60, y: 40)
                    .blur(radius: 8)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .shadow(color: heroAccentDark.opacity(0.35), radius: 12, x: 0, y: 6)
    }

    // MARK: - 篩選

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(label: "全部", icon: "tray.full.fill",
                           tint: heroAccent, isSelected: selectedSub == nil) { selectedSub = nil }
                ForEach(FinanceSubCategory.allCases) { sub in
                    let count = financeMilestones.filter { $0.financeSubCategory == sub }.count
                    if count > 0 {
                        chipButton(label: "\(sub.rawValue) \(count)", icon: sub.icon,
                                   tint: colorFor(sub), isSelected: selectedSub == sub) { selectedSub = sub }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color(.separator).opacity(0.22), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 1)
        }
    }

    private func chipButton(label: String, icon: String, tint: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption2)
                Text(label).font(.caption.weight(isSelected ? .semibold : .medium))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(isSelected ? tint : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .shadow(color: isSelected ? tint.opacity(0.35) : .clear, radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isSelected)
    }

    // MARK: - 列表

    private func linkedCards(for bankId: UUID) -> [LifeMilestone] {
        lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .creditCard && $0.linkedBankMilestoneId == bankId
        }
    }

    private var milestoneList: some View {
        List {
            ForEach(Array(filteredMilestones.enumerated()), id: \.element.id) { idx, item in
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
                // 交錯淡入 + 向上進場，對齊 VariableExpenseView / IncomeView 規格
                .opacity(rowsAppeared ? 1 : 0)
                .offset(y: rowsAppeared ? 0 : 12)
                .animation(
                    .spring(response: 0.44, dampingFraction: 0.82)
                        .delay(0.04 * Double(min(idx, 12))),
                    value: rowsAppeared
                )
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.08)) {
                rowsAppeared = true
            }
        }
    }

    private func creditCardSubRow(_ card: LifeMilestone) -> some View {
        let disabled = card.isDisabled == true
        let accent: Color = disabled ? .secondary : .orange
        return HStack(spacing: 10) {
            // 縮排 + 32pt 漸層圓（對齊 milestoneRow 子層規格）
            Rectangle().fill(Color.clear).frame(width: 16)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.18), accent.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                Circle()
                    .stroke(accent.opacity(disabled ? 0.08 : 0.18), lineWidth: 0.75)
                    .frame(width: 32, height: 32)
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(card.cardName ?? card.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(disabled ? .secondary : .primary)
                        .lineLimit(1)
                    if disabled {
                        Text("已停用")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.14))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
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
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .opacity(disabled ? 0.65 : 1.0)
    }

    private func milestoneRow(_ item: LifeMilestone) -> some View {
        let accent = colorFor(item.financeSubCategory ?? .bank)
        return HStack(spacing: 12) {
            // 44pt 漸層圖示圓（對齊 IncomeView.incomeRow 規格）
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.22), accent.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Circle()
                    .stroke(accent.opacity(0.20), lineWidth: 1)
                    .frame(width: 44, height: 44)
                Image(systemName: item.financeSubCategory?.icon ?? "banknote.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
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
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(display.amount >= 0 ? Color.blue : Color.red)
                        .contentTransition(.numericText())
                }
            } else {
                Text(formatDate(item.date)).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
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
        let cardName = item.cardName.flatMap { $0.isEmpty ? nil : $0 } ?? item.title
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
        let bn = item.bankName.flatMap { $0.isEmpty ? nil : $0 } ?? item.title
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
        // 預先取出 deposits，避免 header count + content 兩次重算
        let allDeposits = deposits
        return VStack(alignment: .leading, spacing: 0) {
            // 標題列：Capsule 側條 + 計數膠囊，對齊 OverviewView categoryBreakdownSection 規格
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Text(sub == .securities ? "證券交易" : "銀行存款")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if !allDeposits.isEmpty {
                    Text("\(allDeposits.count) 筆")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.blue.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.blue.opacity(0.22), lineWidth: 0.75))
                }
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
                    Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            if allDeposits.isEmpty {
                Text("尚無存款記錄").font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 16).padding(.bottom, 14)
            } else {
                depositChart
                    .padding(.horizontal).padding(.bottom, 8)

                let sortedDesc = allDeposits.sorted { $0.date > $1.date }
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
            // 標題列：Capsule 側條（橙色）+ 筆數膠囊，對齊 depositSection 標題規格
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .orange.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Text("消費趨勢")
                    .font(.subheadline.weight(.bold))
                Spacer()
                let dailyCount = creditCardDailyTotals.count
                if dailyCount > 0 {
                    Text("\(dailyCount) 筆")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.orange.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.orange.opacity(0.22), lineWidth: 0.75))
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

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
                // 信用卡個別支出列：32pt 漸層圖示圓 + 日期 Capsule 徽章 + 金額 rounded bold
                // 對齊 depositRow 視覺語言，形成帳戶詳頁統一 row 規格
                ForEach(visible) { exp in
                    Button { editingExpense = exp } label: {
                        HStack(spacing: 10) {
                            // 32pt 漸層圖示圓（橙色 = 信用卡消費）
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.orange.opacity(0.18), Color.orange.opacity(0.07)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 32, height: 32)
                                Circle()
                                    .stroke(Color.orange.opacity(0.18), lineWidth: 0.75)
                                    .frame(width: 32, height: 32)
                                Image(systemName: exp.categoryIcon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.orange)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(exp.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                // 日期 Capsule 徽章
                                Text(fmtDate(exp.date))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color(.tertiarySystemFill))
                                    .clipShape(Capsule())
                            }

                            Spacer(minLength: 4)

                            VStack(alignment: .trailing, spacing: 3) {
                                Text("-NT$ \(fmtNum(exp.amount))")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.red)
                                    .contentTransition(.numericText())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Image(systemName: "chevron.right")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
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
            // 標題列：Capsule 側條（橙色）+ 張數膠囊，對齊 depositSection 標題規格
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .orange.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Text("信用卡")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if !linkedCreditCards.isEmpty {
                    Text("\(linkedCreditCards.count) 張")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.orange.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.orange.opacity(0.22), lineWidth: 0.75))
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            if linkedCreditCards.isEmpty {
                Text("尚無信用卡").font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 16).padding(.bottom, 14)
            } else {
                ForEach(linkedCreditCards) { card in
                    let disabled = card.isDisabled == true
                    let accent: Color = disabled ? .secondary : .orange
                    Button { viewingLinkedCard = card } label: {
                        HStack(spacing: 12) {
                            // 36pt 漸層圖示圓，對齊 creditCardSubRow 規格
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [accent.opacity(0.20), accent.opacity(0.08)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 36, height: 36)
                                Circle()
                                    .stroke(accent.opacity(disabled ? 0.08 : 0.20), lineWidth: 0.75)
                                    .frame(width: 36, height: 36)
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(accent)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 5) {
                                    Text(card.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(disabled ? .secondary : .primary)
                                        .lineLimit(1)
                                    if disabled {
                                        Text("已停用")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.10))
                                            .clipShape(Capsule())
                                    }
                                }
                                HStack(spacing: 4) {
                                    if let cn = card.cardName, !cn.isEmpty {
                                        Text(cn).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    if let lf = card.cardLastFour, !lf.isEmpty {
                                        Text("末\(lf)")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                                            .background(Color(.tertiarySystemFill))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .opacity(disabled ? 0.65 : 1.0)
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

    // MARK: - depositRow（v2 美化）
    // 【美化方向】36pt 漸層圖示圓（依存款類型分色：存入/提款/信用卡/股票/沖正）；
    //   Badge 升級為 Capsule + 細邊框；備註文字顯示；
    //   金額升至 .system(size:15, weight:.bold, design:.rounded) + contentTransition；
    //   對齊 IncomeView.incomeRow / StockView.stockCard 視覺規格
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
        let amountColor: Color = {
            if isStock { return dep.isWithdrawal ? Color.red : Color.green }
            if dep.isWithdrawal { return isVirtual ? Color.orange : Color.red }
            return dep.currencyCode == "NT$" ? Color.green : Color.blue
        }()
        let iconName: String = {
            if dep.isAdjust { return "arrow.2.circlepath" }
            if isStock { return dep.isWithdrawal ? "chart.line.downtrend.xyaxis" : "chart.line.uptrend.xyaxis" }
            if isVirtual { return "creditcard.fill" }
            if dep.linkedExpenseId != nil { return dep.isWithdrawal ? "minus.circle.fill" : "plus.circle.fill" }
            return dep.isWithdrawal ? "arrow.up.circle.fill" : "banknote.fill"
        }()
        return Button {
            handleDepositTap(dep, isVirtual: isVirtual, isStock: isStock)
        } label: {
            HStack(spacing: 12) {
                // 36pt 漸層圖示圓：依存款類型分色圖示
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [badgeColor.opacity(0.20), badgeColor.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Circle()
                        .stroke(badgeColor.opacity(0.20), lineWidth: 0.75)
                        .frame(width: 36, height: 36)
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(badgeColor)
                }

                // 主文字區：Badge 膠囊 + 備註 + 日期
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        if let txt = badgeText {
                            Text(txt)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(badgeColor)
                                .padding(.horizontal, 7).padding(.vertical, 2.5)
                                .background(badgeColor.opacity(0.10))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(badgeColor.opacity(0.22), lineWidth: 0.6))
                        }
                        if let note = dep.note, !note.isEmpty {
                            Text(note)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    // 日期：小型 Capsule 徽章
                    Text(fmtDate(dep.date))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 4)

                // 金額 + chevron
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(dep.isWithdrawal ? "-" : "+")\(dep.currencyCode) \(fmtNum(dep.amount))")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(amountColor)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 把單筆金額換算成台幣（NT$ 直接回傳；找不到匯率時不換算以免丟資料）
    private func depositAmountInTWD(_ amount: Double, currency: String) -> Double {
        if currency == "NT$" { return amount }
        if let rate = expenseStore.currencyRates.first(where: { $0.code == currency }), rate.rate > 0 {
            return amount * rate.rate
        }
        return amount
    }

    @State private var depositChartPage: Int = 0

    private var depositChart: some View {
        let data = deposits
        // 混幣帳戶（例如台幣存款 + 美金提款）一律換算 TWD 後再累計，
        // 避免外幣提款被當成台幣金額直接相減；單一幣別則保留原幣別不換算。
        let currencies = Set(data.map(\.currencyCode))
        let isMixed = currencies.count > 1
        let displayCurrency = isMixed ? "NT$" : (currencies.first ?? "NT$")
        var balances: [(date: Date, balance: Double, id: UUID)] = []
        var running: Double = 0
        for dep in data {
            let amt = isMixed ? depositAmountInTWD(dep.amount, currency: dep.currencyCode) : dep.amount
            if dep.isWithdrawal { running -= amt } else { running += amt }
            balances.append((dep.date, running, dep.id))
        }
        // 每頁 30 筆，由舊到新切頁；超過 30 筆可左右滑動
        let pageSize = 30
        var pages: [[(date: Date, balance: Double, id: UUID)]] = []
        var i = 0
        while i < balances.count {
            let end = min(i + pageSize, balances.count)
            pages.append(Array(balances[i..<end]))
            i = end
        }

        return VStack(alignment: .leading, spacing: 6) {
            if !pages.isEmpty {
                GeometryReader { geo in
                    let pageWidth = geo.size.width
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(Array(pages.enumerated()), id: \.offset) { idx, pageData in
                                depositChartPageView(pageData)
                                    .frame(width: pageWidth)
                                    .id(idx)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: Binding<Int?>(
                        get: { depositChartPage },
                        set: { if let v = $0 { depositChartPage = v } }
                    ))
                }
                .frame(height: 150)

                if pages.count > 1 {
                    HStack(spacing: 6) {
                        Spacer()
                        ForEach(0..<pages.count, id: \.self) { p in
                            Circle()
                                .fill(p == depositChartPage ? Color.blue : Color.secondary.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                        Spacer()
                    }
                }
            }

            if let last = balances.last {
                HStack {
                    Text("目前總額").font(.caption).foregroundStyle(.secondary)
                    if isMixed {
                        Text("（含外幣換算）").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text("\(displayCurrency) \(fmtNum(last.balance))").font(.caption.bold())
                        .foregroundStyle(last.balance >= 0 ? Color.blue : Color.red)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    /// 單頁的餘額長條圖：Y 軸最大 / 最小值依「本頁」資料自適應
    @ViewBuilder
    private func depositChartPageView(_ pageData: [(date: Date, balance: Double, id: UUID)]) -> some View {
        let maxBal = pageData.map(\.balance).max() ?? 1
        let minBal = min(0, pageData.map(\.balance).min() ?? 0)
        let range = max(maxBal - minBal, 1)
        let labelStride = max(1, pageData.count / 6)
        GeometryReader { geo in
            let chartHeight: CGFloat = 120
            let barAreaWidth = geo.size.width
            let barWidth = max(4, (barAreaWidth - CGFloat(pageData.count - 1) * 4) / CGFloat(max(pageData.count, 1)))
            VStack(spacing: 2) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(pageData.enumerated()), id: \.element.id) { _, item in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(item.balance >= 0 ? Color.blue : Color.red)
                            .frame(
                                width: barWidth,
                                height: max(4, CGFloat(abs(item.balance - minBal) / range) * chartHeight)
                            )
                    }
                }
                .frame(height: chartHeight, alignment: .bottom)

                HStack(alignment: .top, spacing: 4) {
                    ForEach(Array(pageData.enumerated()), id: \.element.id) { idx, item in
                        Text(idx % labelStride == 0 ? shortDate(item.date) : " ")
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

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: date)
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
            // 換算成台幣再加總，外幣提款 / 存款才不會被當成台幣金額直接計算
            let twd = depositAmountInTWD(dep.amount, currency: dep.currencyCode)
            total += dep.isWithdrawal ? -twd : twd
        }
        return total
    }

    /// 把單筆金額換算成台幣（NT$ 直接回傳；找不到匯率時不換算以免丟資料）
    private func depositAmountInTWD(_ amount: Double, currency: String) -> Double {
        if currency == "NT$" { return amount }
        if let rate = expenseStore.currencyRates.first(where: { $0.code == currency }), rate.rate > 0 {
            return amount * rate.rate
        }
        return amount
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
