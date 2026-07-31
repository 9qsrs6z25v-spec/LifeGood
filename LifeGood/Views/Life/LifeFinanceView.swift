import SwiftUI

// MARK: - 美化紀錄（LifeFinanceView · v7 · 2026-07-31）
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
// [2026-06 v3] summaryHeader + milestoneRow 細節升級：
//   9. summaryHeader background ZStack → 補上玻璃光澤 overlay（LinearGradient .white.opacity(0.18)→.clear
//      top→center），對齊全 App 英雄卡三散景＋玻璃光澤標準（AddVehicleView / SavingsInsuranceView 同款）。
//  10. KPI 圖示圓 → 從 Circle().fill(.white.opacity(0.16)) 升級為
//      LinearGradient([.white.opacity(0.26), .white.opacity(0.10)]) + strokeBorder(.white.opacity(0.30), 0.75pt)，
//      對齊 FinanceChartView KPI 圖示圓規格（多一層光澤感，白色比例梯度更柔和）。
//  11. KPI 數字加入 contentTransition(.numericText())，資料切換時平滑捲動。
//  12. KPI 背景條 → 補上 .white.opacity(0.18) strokeBorder，增加容器定義感。
//  13. milestoneRow 非銀行類日期 → 從純文字升級為 Capsule 徽章（tertiarySystemFill 底），
//      對齊 MyCalendarView / creditCardChartSection 日期 Badge 規格。
// [2026-07 v4] DepositEditorSheet 轉帳/沖正帳戶餘額格式一致性修復：
//  14. fmtBal(_:) 先前自製 NumberFormatter 手刻「NT$ X萬」（無條件捨去小數、且未處理
//      億級單位，例如 1.2 億的帳戶會顯示成「NT$12000萬」），與全 App 其餘畫面共用的
//      Double.ntdWanString（「NT$1.2萬」保留一位小數、億以上自動換算為「億」）風格不一致，
//      是本檔案唯一未接上共用金額量級格式的地方（對齊 v23.79 AddExpenseView.formatBankBalance
//      同型修復）。改呼叫既有 ntdWanString，「轉入帳戶」選單與「沖正」目前總額顯示對齊全 App
//      金額規則。純視覺調整，未變動帳戶餘額計算、轉帳或沖正等既有邏輯。
// [2026-07 v5] 主畫面「銀行帳戶總餘額」英雄卡大字 + 導覽列小計精度修復：
//  15. formatTwdShort(_:) 先前用 maximumFractionDigits=0 的 decimalFormatter 直接對
//      「金額 / 億」「金額 / 萬」四捨五入到整數（無小數位），例如 1.25 億會被捨入顯示成
//      「NT$ 1 億」，實際少報 25%；4.56 萬會顯示成「NT$ 5 萬」，同樣嚴重失真——是本頁級距
//      最大的金額顯示 bug（比 v4 修的 fmtBal 精度問題更嚴重，因為這裡連小數位都沒有保留）。
//      改呼叫全 App 共用的 Double.ntdWanString（億/萬保留一位小數），summaryHeader 30pt 大字
//      與導覽列小計兩處同步套用；移除已無呼叫端的 formatTwdShort 死碼。純顯示層調整，未變動
//      銀行餘額換算或加總邏輯。
// [2026-07 v6] FinanceCardView 信用卡明細卡金額量級一致性修復：
//  16. creditCardDetail 的「額度」原本手刻 cl/10000 只顯示到萬（無條件捨去小數、未處理億級
//      單位），「年費」原本用「NT$\(fmtNum(af))」純整數無量級轉換，與同一張卡緊接在下方、
//      v23.97 才剛加入的「本期已用」「可用額度」（已用共用 ntdWanString「NT$X萬」規格）風格
//      不一致，是同一張信用卡明細卡上最顯眼的落差；「額度」「年費」兩處改呼叫共用 ntdWanString。
//  17. 「最近一期」加總與信用卡個別支出列金額原本用「-NT$ \(fmtNum(...))」純整數顯示，同樣未
//      處理萬/億量級；改為「-」+ ntdWanString（對齊 StockDetailView 損益金額 "(pl >= 0 ? "+" :
//      "") + fmt(pl)" 的正負號拼接慣例）。以上四處純顯示層調整，額度／年費／消費金額等既有
//      試算與資料綁定邏輯未變動。
// [2026-07 v7] DepositEditorSheet 新增/編輯表單 Section header 補齊：
//  18. 「轉帳資訊」「沖正」「幣別 存款‧提款」共 3 個 Section 原本是系統預設純文字標頭，
//      是全 App「表單 Section header 補齊」系列（StockDetailView.stockEditorSectionHeader／
//      RealEstateDetailView.realEstateEditorSectionHeader 等既有做法）尚未覆蓋到的一處。新增
//      depositEditorSectionHeader(_:icon:color:)（4pt 漸層 Capsule 側條 + 圖示 + 粗體標題），
//      主題色依語意分配（轉帳資訊＝blue／沖正＝orange，呼應差額正負著色／存款‧提款＝green，
//      呼應本表單既有「新增」按鈕綠色）。純標題視覺升級，save()／saveTransfer()／saveAdjust()
//      等既有商業邏輯完全未變動。

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
            // 固定薪水設有結束日者，展開至結束月（含）為止；之後停止入帳，
            // 與 Income.isActive(in:)／收入頁計算一致。current 單調遞增，失效後即可跳出。
            if !inc.isActive(in: current, calendar: cal) { break }
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

/// 依幣別計算銀行帳戶的目前餘額（含信用卡彙總扣款 NT$ + 固定支出／週期性收入展開）。
/// 獨立成檔案層級的共用函式（而非 LifeFinanceView 的 private 方法），讓 DepositEditorSheet
/// 的轉帳／沖正也能算出與列表頁一致的完整餘額，不必各自維護一份簡化、容易脫節的版本。
fileprivate func bankBalances(
    for ms: LifeMilestone, now: Date,
    expensesById: [UUID: Expense], incomesById: [UUID: Income],
    lifeStore: LifeStore, expenseStore: ExpenseStore
) -> [String: Double] {
    var totals: [String: Double] = [:]
    for dep in ms.bankDeposits ?? [] where dep.date <= now {
        // 跳過已連結到信用卡支出的存款（用信用卡彙總取代）
        if let expId = dep.linkedExpenseId,
           let exp = expensesById[expId],
           exp.linkedCreditCardMilestoneId != nil { continue }
        // 跳過已連結到固定支出（含週期）的存款 — 改用展開的虛擬條目取代，避免漏算或重算
        if let expId = dep.linkedExpenseId,
           let exp = expensesById[expId],
           exp.expenseType == .fixed, exp.recurrence != nil { continue }
        // 跳過已連結到週期性收入的存款 — 改用展開的虛擬條目取代
        if let incId = dep.linkedExpenseId,
           let inc = incomesById[incId],
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
fileprivate func balanceInTWD(_ balances: [String: Double], expenseStore: ExpenseStore) -> Double {
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
        // 一次取出，避免 toolbar + summaryHeader 各自重複計算 O(n×1200) 的銀行餘額展開
        let bankBalanceTWD = allBankBalanceInTWD
        NavigationStack {
            // [對齊 SavingsInsuranceView 看板規格] 英雄看板與篩選列改為 List 內首個 Section，
            // 隨內容一起捲動，不再固定釘在列表上方。
            milestoneList(balance: bankBalanceTWD)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("財富")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        Text(bankBalanceTWD.ntdWanString)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(bankBalanceTWD >= 0 ? Color.blue : Color.red)
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

    private func summaryHeader(balance: Double) -> some View {
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
                    Text(balance.ntdWanString)
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
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.26), .white.opacity(0.10)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 30, height: 30)
                            Circle()
                                .strokeBorder(.white.opacity(0.30), lineWidth: 0.75)
                                .frame(width: 30, height: 30)
                            Image(systemName: sub.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text("\(count)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
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
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.75)
            )
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
                // 玻璃光澤：頂部白色漸層 → 透明，對齊全 App 英雄卡規格
                LinearGradient(
                    colors: [.white.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        )
        // [對齊 SavingsInsuranceView 看板規格] 圓角 20 卡片 + 16pt 水平內縮，取代原本滿版無圓角橫幅
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: heroAccentDark.opacity(0.42), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 16)
    }

    // MARK: - 篩選

    private var filterChips: some View {
        // 一次 reduce 建立計數表，避免 ForEach 內對每個分類各做一次 O(n) filter
        let countBySub: [FinanceSubCategory: Int] = financeMilestones.reduce(into: [:]) { dict, m in
            if let sub = m.financeSubCategory { dict[sub, default: 0] += 1 }
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(label: "全部", icon: "tray.full.fill",
                           tint: heroAccent, isSelected: selectedSub == nil) { selectedSub = nil }
                ForEach(FinanceSubCategory.allCases) { sub in
                    let count = countBySub[sub, default: 0]
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

    private func milestoneList(balance: Double) -> some View {
        // 一次批次算好所有銀行帳戶餘額，避免每一列各自呼叫 bankBalances(for:)
        // 對 expenses/incomes 做 O(deposits × expenses) 全量掃描（對齊 AddExpenseView.allBankBalances() 的批次建表作法）
        let balancesByBank = allBankBalances()
        // 一次依 linkedBankMilestoneId 分組信用卡，避免每一列銀行帳戶各自對
        // lifeStore.milestones 做一次 O(n) filter（N 家銀行 × M 筆信用卡 = O(n×m)）
        let cardsByBank = Dictionary(grouping: lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .creditCard && $0.linkedBankMilestoneId != nil
        }, by: { $0.linkedBankMilestoneId! })
        return List {
            Section {
                summaryHeader(balance: balance)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .opacity(headerAppeared ? 1 : 0)
                    .offset(y: headerAppeared ? 0 : 22)
                    .onAppear {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                            headerAppeared = true
                        }
                    }
                    .onDisappear {
                        headerAppeared = false
                    }
                filterChips
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(Array(filteredMilestones.enumerated()), id: \.element.id) { idx, item in
                VStack(spacing: 0) {
                    milestoneRow(item, balances: balancesByBank[item.id])
                        .contentShape(Rectangle())
                        .onTapGesture { viewingItem = item }

                    if item.financeSubCategory == .bank {
                        let cards = cardsByBank[item.id] ?? []
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
        .scrollContentBackground(.hidden)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.08)) {
                rowsAppeared = true
            }
        }
        .onDisappear {
            rowsAppeared = false
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

    private func milestoneRow(_ item: LifeMilestone, balances: [String: Double]?) -> some View {
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
                    let display = bankBalanceDisplay(balances: balances ?? [:])
                    Text(display.text)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(display.amount >= 0 ? Color.blue : Color.red)
                        .contentTransition(.numericText())
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 9, weight: .medium))
                    Text(formatDate(item.date))
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    /// 一次批次算好所有銀行帳戶的餘額：expensesById／incomesById 各建一次表，
    /// 銀行帳戶逐筆存款改為 O(1) 查表，取代原本 bankBalances(for:) 每次呼叫都對
    /// expenseStore.expenses / incomes 做 first(where:) 全量掃描（O(deposits × expenses)），
    /// 而 milestoneRow 是列表每一列都會呼叫的路徑，未批次化會在任何無關的 @Published 變動時
    /// 對每一列重跑一次全量掃描。對齊 AddExpenseView.allBankBalances() 的批次建表作法。
    private func allBankBalances() -> [UUID: [String: Double]] {
        let now = Date()
        let expensesById = Dictionary(expenseStore.expenses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let incomesById = Dictionary(expenseStore.incomes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let banks = lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .bank
        }
        var result: [UUID: [String: Double]] = [:]
        for ms in banks {
            result[ms.id] = bankBalances(for: ms, now: now, expensesById: expensesById, incomesById: incomesById, lifeStore: lifeStore, expenseStore: expenseStore)
        }
        return result
    }

    /// 帳戶餘額顯示：單幣別→該幣別；多幣別→換算 TWD 等值
    private func bankBalanceDisplay(balances: [String: Double]) -> (text: String, amount: Double) {
        if balances.count <= 1 {
            let entry = balances.first ?? ("NT$", 0)
            return ("\(entry.0) \(formatNumber(entry.1))", entry.1)
        }
        let twd = balanceInTWD(balances, expenseStore: expenseStore)
        return ("≈ NT$ \(formatNumber(twd))", twd)
    }

    /// 所有銀行帳戶的台幣等值總和
    private var allBankBalanceInTWD: Double {
        allBankBalances().values.reduce(0) { $0 + balanceInTWD($1, expenseStore: expenseStore) }
    }

    private static let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()

    private func formatNumber(_ v: Double) -> String {
        Self.decimalFormatter.string(from: NSNumber(value: v)) ?? "0"
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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    private func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
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

    /// 刪除里程碑並清除其他 Store 對此 id 的懸空引用（比照 ResumeView.deleteMilestoneCleaningLinks
    /// 同型修復，LifeStore.deleteMilestone 本身無法觸及 FinanceStore／ExpenseStore）。
    private func deleteMilestoneCleaningLinks(_ item: LifeMilestone) {
        lifeStore.deleteMilestone(item)

        var stocks = financeStore.stocks
        var stocksChanged = false
        for i in stocks.indices {
            if stocks[i].linkedBankMilestoneId == item.id {
                stocks[i].linkedBankMilestoneId = nil
                stocks[i].linkedBankCurrency = nil
                stocksChanged = true
            }
            if stocks[i].linkedSecuritiesMilestoneId == item.id {
                stocks[i].linkedSecuritiesMilestoneId = nil
                stocksChanged = true
            }
        }
        if stocksChanged { financeStore.stocks = stocks }

        var expenses = expenseStore.expenses
        var expensesChanged = false
        for i in expenses.indices {
            if expenses[i].linkedBankMilestoneId == item.id {
                expenses[i].linkedBankMilestoneId = nil
                expensesChanged = true
            }
            if expenses[i].linkedCreditCardMilestoneId == item.id {
                expenses[i].linkedCreditCardMilestoneId = nil
                expensesChanged = true
            }
        }
        if expensesChanged { expenseStore.expenses = expenses }

        var incomes = expenseStore.incomes
        var incomesChanged = false
        for i in incomes.indices where incomes[i].linkedBankMilestoneId == item.id {
            incomes[i].linkedBankMilestoneId = nil
            incomesChanged = true
        }
        if incomesChanged { expenseStore.incomes = incomes }
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
                Button("刪除", role: .destructive) { deleteMilestoneCleaningLinks(item); dismiss() }
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

    private static let fmtMonthYearFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM/yy"; return f
    }()
    private static let fmtYearMonthZhFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy 年 M 月"; return f
    }()

    private func fmtMonthYear(_ d: Date) -> String {
        Self.fmtMonthYearFormatter.string(from: d)
    }

    private func fmtYearMonthZh(_ d: Date) -> String {
        Self.fmtYearMonthZhFormatter.string(from: d)
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

    /// 信用卡本期已用 / 可用額度 / 使用率（依帳單日計算本期，過帳單日自動重置）
    @ViewBuilder
    private func creditUsageBlock(limit: Double) -> some View {
        let spent = currentCycleSpent(item)
        let available = max(0, limit - spent)
        let ratio = limit > 0 ? min(1, spent / limit) : 0
        let barColor: Color = ratio > 0.8 ? .red : (ratio > 0.5 ? .orange : .green)
        infoRow("本期已用", spent.ntdWanString)
        infoRow("可用額度", available.ntdWanString)
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill)).frame(height: 8)
                    Capsule().fill(barColor).frame(width: max(4, geo.size.width * ratio), height: 8)
                }
            }
            .frame(height: 8)
            Text("使用率 \(Int((ratio * 100).rounded()))%　·　依帳單日計算本期，過帳單日重置")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    /// 本期（自最近一個帳單日之後）刷這張卡的消費總額；週期性固定支出會依 recurrence 展開
    private func currentCycleSpent(_ card: LifeMilestone) -> Double {
        let cal = Calendar.current
        let now = Date()
        let cycleStart = Self.creditCardCycleStart(billingDay: card.billingDay, now: now, calendar: cal)
        return expandedCreditCardEntries(forCard: card.id, expenses: expenseStore.expenses)
            .filter { $0.date > cycleStart && $0.date <= now }
            .reduce(0) { $0 + $1.amount }
    }

    /// 本期起點＝今天(含)以前最近的一個帳單日；無帳單日則以當月 1 號為界
    static func creditCardCycleStart(billingDay: Int?, now: Date, calendar cal: Calendar) -> Date {
        let startOfToday = cal.startOfDay(for: now)
        guard let bd = billingDay, bd >= 1 else {
            return cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? startOfToday
        }
        func billingDate(inMonthOf ref: Date) -> Date {
            var comps = cal.dateComponents([.year, .month], from: ref)
            let maxDay = cal.range(of: .day, in: .month, for: ref)?.count ?? 28
            comps.day = min(bd, maxDay)   // 帳單日超過該月天數時取月底
            return cal.date(from: comps) ?? cal.startOfDay(for: ref)
        }
        let thisMonth = billingDate(inMonthOf: now)
        if thisMonth <= startOfToday { return thisMonth }
        // 本月帳單日還沒到 → 上一期結帳在上個月的帳單日
        let prev = cal.date(byAdding: .month, value: -1, to: now) ?? now
        return billingDate(inMonthOf: prev)
    }

    @ViewBuilder
    private var creditCardDetail: some View {
        if let c = item.cardName, !c.isEmpty { infoRow("卡別", c) }
        if let l = item.cardLastFour, !l.isEmpty { infoRow("卡號末四碼", l) }
        if let cl = item.creditLimit, cl > 0 {
            infoRow("額度", cl.ntdWanString)
            creditUsageBlock(limit: cl)
        }
        if let af = item.annualFee, af > 0 { infoRow("年費", af.ntdWanString) }
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

    private static let fmtDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()
    private static let fmtNumFormatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()

    private func fmtDate(_ date: Date) -> String {
        Self.fmtDateFormatter.string(from: date)
    }

    private func fmtNum(_ v: Double) -> String {
        Self.fmtNumFormatter.string(from: NSNumber(value: v)) ?? "0"
    }

    // MARK: - 銀行存款章節

    /// 銀行存款列表：真實 BankDeposit + 信用卡逐月彙總 + 固定支出週期展開 + 週期性收入展開
    private var deposits: [BankDeposit] {
        let now = Date()
        // 先建一次 expensesById／incomesById 查表，取代逐筆 first(where:) 對
        // expenseStore.expenses／incomes 的全量線性掃描（O(bankDeposits × (expenses+incomes))），
        // 對齊 allBankBalances() 的批次建表作法。
        let expensesById = Dictionary(expenseStore.expenses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let incomesById = Dictionary(expenseStore.incomes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let real = (item.bankDeposits ?? []).filter { dep in
            guard dep.date <= now else { return false }
            guard let linkedId = dep.linkedExpenseId else { return true }
            // 連結到 Expense
            if let exp = expensesById[linkedId] {
                // 信用卡支出：用每月彙總取代
                if exp.linkedCreditCardMilestoneId != nil { return false }
                // 固定支出（週期）：用展開虛擬條目取代
                if exp.expenseType == .fixed && exp.recurrence != nil { return false }
                return true
            }
            // 連結到 Income（週期性 → 用展開取代）
            if let inc = incomesById[linkedId] {
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
                depositChart(allDeposits)
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

    /// 接收呼叫端（creditCardChartSection）已算好的 entries，避免每次都重新呼叫
    /// expandedCreditCardEntries 展開週期性支出（O(每筆固定支出 × 期數)）。
    private func creditCardMonthlyTotals(_ entries: [CreditCardEntry]) -> [CreditCardMonthlyTotal] {
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

    /// 接收呼叫端（creditCardChartSection）已算好的 entries，理由同 creditCardMonthlyTotals(_:)。
    private func creditCardDailyTotals(_ entries: [CreditCardEntry]) -> [CreditCardDailyTotal] {
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
        // 預先求值一次 entries／dailyTotals，往下傳給 creditCardChart／creditCardMonthlyTotals，
        // 避免三處各自重新呼叫 expandedCreditCardEntries 展開週期性支出。
        let entries = expandedCreditCardEntries(forCard: milestoneId, expenses: expenseStore.expenses)
        let dailyTotals = creditCardDailyTotals(entries)
        return VStack(alignment: .leading, spacing: 0) {
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
                let dailyCount = dailyTotals.count
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

            if dailyTotals.isEmpty {
                Text("尚無扣款記錄").font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal).padding(.bottom, 12)
            } else {
                creditCardChart(dailyTotals)
                    .padding(.horizontal).padding(.bottom, 8)

                // 最近一期加總
                if let last = creditCardMonthlyTotals(entries).last {
                    HStack {
                        Text("最近一期").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("-\(last.amount.ntdWanString)").font(.caption.bold())
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
                                Text("-\(exp.amount.ntdWanString)")
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
    private func creditCardChartPages(_ data: [CreditCardDailyTotal]) -> [[CreditCardDailyTotal]] {
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
    private func creditCardChart(_ dailyTotals: [CreditCardDailyTotal]) -> some View {
        let pages = creditCardChartPages(dailyTotals)
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
        // 過去 isEmpty／count／ForEach 各自獨立呼叫 linkedCreditCards（對 lifeStore.milestones
        // 全量 filter），同一次 render 被呼叫 4 次；改為先算一次本地變數全段共用。
        let cards = linkedCreditCards
        return VStack(alignment: .leading, spacing: 0) {
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
                if !cards.isEmpty {
                    Text("\(cards.count) 張")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.orange.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.orange.opacity(0.22), lineWidth: 0.75))
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            if cards.isEmpty {
                Text("尚無信用卡").font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 16).padding(.bottom, 14)
            } else {
                ForEach(cards) { card in
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
        // deposits 除了信用卡彙總虛擬條目外，也包含週期性固定支出／收入展開後的虛擬條目
        // （expandedFixedExpenseWithdrawals／expandedIncomeDeposits），兩者同樣不存在於
        // item.bankDeposits 中。信用卡彙總條目一律 linkedExpenseId == nil（見 1364 行），
        // 固定支出／收入展開條目則帶有真實的 linkedExpenseId，需一併排除才不會被誤判為信用卡。
        dep.linkedExpenseId == nil && !(item.bankDeposits ?? []).contains(where: { $0.id == dep.id })
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

    /// 接收呼叫端（depositSection）已算好的 deposits，避免各自獨立重算一次 deposits
    /// （expensesById／incomesById 建表 + 固定支出／週期性收入展開，屬於較重的計算）。
    private func depositChart(_ data: [BankDeposit]) -> some View {
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
        Self.shortDateFormatter.string(from: date)
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
    @State private var isSaving = false

    private var bankMilestones: [LifeMilestone] {
        lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .bank && $0.id != milestoneId
        }
    }

    /// expensesById／incomesById 由呼叫端批次建表傳入一次，避免每一列都對 expenseStore.expenses
    /// 做 first(where:) 全量掃描（對齊 AddStockView.accountBalance() 的批次建表修復規格）。
    /// 改呼叫檔案層級共用的 bankBalances()（與列表頁 milestoneRow／allBankBalances() 同一份邏輯），
    /// 取代原本只加總 bankDeposits 原始條目的簡化版本——簡化版漏算信用卡彙總扣款、
    /// 且週期性固定支出／收入只算到第一筆種子條目，會讓「轉入帳戶」下拉與「沖正」的
    /// 「目前總額」明顯低估負債、高估餘額，導致沖正調整值算錯。
    private func bankBalance(for ms: LifeMilestone, expensesById: [UUID: Expense], incomesById: [UUID: Income]) -> Double {
        balanceInTWD(
            bankBalances(for: ms, now: Date(), expensesById: expensesById, incomesById: incomesById, lifeStore: lifeStore, expenseStore: expenseStore),
            expenseStore: expenseStore
        )
    }

    private func currentBalance(expensesById: [UUID: Expense], incomesById: [UUID: Income]) -> Double {
        guard let ms = lifeStore.milestones.first(where: { $0.id == milestoneId }) else { return 0 }
        return bankBalance(for: ms, expensesById: expensesById, incomesById: incomesById)
    }

    private static let numFormatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()

    private func fmtNum(_ v: Double) -> String {
        Self.numFormatter.string(from: NSNumber(value: v)) ?? "0"
    }

    // 【美化方向】轉帳/沖正帳戶餘額格式：先前自製 NumberFormatter 手刻「NT$ X萬」
    // （無條件捨去小數、未處理億級單位），與全 App 共用的 Double.ntdWanString
    // （「NT$1.2萬」保留一位小數、億以上自動換算）風格不一致。改呼叫共用 ntdWanString，
    // 與全 App 金額量級顯示規則對齊。純視覺調整，未變動帳戶餘額計算邏輯。
    private func fmtBal(_ v: Double) -> String {
        v.ntdWanString
    }

    // 【美化方向】存款/提款/轉帳/沖正編輯 sheet Section header：轉帳資訊／沖正／
    // 「幣別 存款‧提款」三個 Section 原本是系統預設純文字標頭，是全 App「表單 Section header
    // 補齊」系列（StockDetailView.stockEditorSectionHeader／RealEstateDetailView.
    // realEstateEditorSectionHeader 等既有做法）尚未覆蓋到的一處。新增檔案層級共用
    // depositEditorSectionHeader(_:icon:color:)（4pt 漸層 Capsule 側條 + 圖示 + 粗體標題），
    // 主題色依語意分配（轉帳資訊＝blue，呼應轉入帳戶／沖正＝orange，呼應差額正負著色／
    // 存款‧提款＝green，呼應本表單既有「新增」按鈕綠色）。純標題視覺升級，欄位資料綁定、
    // save()／saveTransfer()／saveAdjust() 等既有商業邏輯完全未變動。
    private func depositEditorSectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .textCase(nil)
    }

    var body: some View {
        let expensesById = Dictionary(expenseStore.expenses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let incomesById = Dictionary(expenseStore.incomes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        NavigationStack {
            Form {
                Section {
                    Picker("類型", selection: $txType) {
                        ForEach(TransactionType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    // 編輯既有存款/提款時鎖定類型：saveTransfer()/saveAdjust() 不認得 editing，
                    // 若在編輯途中改選「轉帳」/「沖正」會另外新增一筆（或兩筆）記錄，
                    // 原本正在編輯的那筆卻完全沒被處理，變成帳戶餘額被靜默灌入幽靈記錄。
                    .disabled(editing != nil)
                    if editing != nil {
                        Text("編輯時無法變更類型").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if txType == .transfer {
                    Section {
                        Picker("轉入帳戶", selection: $transferTargetId) {
                            Text("請選擇").tag(nil as UUID?)
                            ForEach(bankMilestones) { ms in
                                let name = ms.bankName ?? ms.title
                                Text("\(name)（\(fmtBal(bankBalance(for: ms, expensesById: expensesById, incomesById: incomesById)))）")
                                    .tag(ms.id as UUID?)
                            }
                        }
                        DatePicker("日期", selection: $date, displayedComponents: .date)
                        HStack {
                            Text(currency).foregroundStyle(.secondary)
                            TextField("金額", text: $amountText).keyboardType(.decimalPad)
                        }
                    } header: {
                        depositEditorSectionHeader("轉帳資訊", icon: "arrow.left.arrow.right", color: .blue)
                    }
                } else if txType == .adjust {
                    Section {
                        HStack {
                            Text("目前總額").foregroundStyle(.secondary)
                            Spacer()
                            Text(fmtBal(currentBalance(expensesById: expensesById, incomesById: incomesById))).foregroundStyle(.blue)
                        }
                        DatePicker("日期", selection: $date, displayedComponents: .date)
                        HStack {
                            Text(currency).foregroundStyle(.secondary)
                            TextField("調整後金額", text: $amountText).keyboardType(.decimalPad)
                        }
                        if let target = Double(amountText) {
                            let diff = target - currentBalance(expensesById: expensesById, incomesById: incomesById)
                            HStack {
                                Text("差額").foregroundStyle(.secondary)
                                Spacer()
                                Text("\(diff >= 0 ? "+" : "")\(fmtNum(diff))")
                                    .foregroundStyle(diff >= 0 ? Color.green : Color.red)
                                    .bold()
                            }
                        }
                        TextField("備註（如：對帳調整）", text: $adjustNote, axis: .vertical).lineLimit(2...3)
                    } header: {
                        depositEditorSectionHeader("沖正", icon: "arrow.triangle.2.circlepath", color: .orange)
                    }
                } else {
                    Section {
                        DatePicker("日期", selection: $date, displayedComponents: .date)
                        HStack {
                            Text(currency).foregroundStyle(.secondary)
                            TextField("金額", text: $amountText).keyboardType(.decimalPad)
                        }
                    } header: {
                        depositEditorSectionHeader("\(currency) \(txType.rawValue)", icon: "banknote.fill", color: .green)
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
                    .disabled(saveDisabled || isSaving)
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
        guard !isSaving else { return }
        guard var ms = lifeStore.milestones.first(where: { $0.id == milestoneId }) else { dismiss(); return }
        isSaving = true
        // 「沖正」紀錄的 txType 在 onAppear 只會回填成 .deposit/.withdrawal（此表單沒有「編輯沖正」的重算 UI），
        // 若直接用預設值重建 BankDeposit 會把 isAdjust／note 清掉，等於使用者只是打開又存檔就把「沖正」
        // 紀錄靜默改成普通存提款、遺失對帳備註。這裡保留原始 isAdjust／note，避免資料被改型別。
        let dep = BankDeposit(id: editing?.id ?? UUID(), date: date, amount: Double(amountText) ?? 0,
                              currencyCode: currency, isWithdrawal: txType == .withdrawal,
                              isAdjust: editing?.isAdjust ?? false,
                              note: (editing?.isAdjust == true) ? editing?.note : nil)
        var list = ms.bankDeposits ?? []
        if let idx = list.firstIndex(where: { $0.id == dep.id }) { list[idx] = dep }
        else { list.append(dep) }
        ms.bankDeposits = list
        lifeStore.update(ms); dismiss()
    }

    private func saveTransfer() {
        guard !isSaving else { return }
        let amount = Double(amountText) ?? 0
        guard amount > 0, let targetId = transferTargetId else { return }
        isSaving = true

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
        guard !isSaving else { return }
        guard let targetAmount = Double(amountText),
              var ms = lifeStore.milestones.first(where: { $0.id == milestoneId }) else { dismiss(); return }
        let expensesById = Dictionary(expenseStore.expenses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let incomesById = Dictionary(expenseStore.incomes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let diff = targetAmount - currentBalance(expensesById: expensesById, incomesById: incomesById)
        guard diff != 0 else { dismiss(); return }
        isSaving = true
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
