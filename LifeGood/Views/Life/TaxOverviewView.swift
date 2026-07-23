import SwiftUI

// MARK: - 美化紀錄（TaxOverviewView）
// [2026-06] 本次美化方向：
//   1. annualSummaryCard → 升級為紅橘漸層英雄卡片（對齊 VariableExpenseView header 設計語言）：
//      頂部左置年度稅費大字、右置年收入 + 稅費率膠囊；底部 4 個 taxStat 改用 44pt 漸層圖示圓
//      搭配散景裝飾圓，整體對齊同系列 hero card 視覺語言。
//   2. yearPicker → 左右箭頭改為綠色填充圓形膠囊按鈕（提升觸碰目標；對齊 MacaronDatePicker 風格）
//      + 年份文字加大至 .title3，提升可讀性。
//   3. sectionHeader → 改為 Capsule 側條 + .semibold 標題（對齊 OverviewView categoryBreakdownSection
//      標題規格），支援可選計數膠囊參數，強化各 section 層級對比。
//   4. taxRecordsSection 各列 → 加入 38pt 漸層圖示圓 + 日期膠囊徽章，對齊 ExpenseRow 規格；
//      空狀態改用圖示 + 說明文字佔位塊（對齊 FixedExpenseView emptyStateView 風格）。
//   5. monthlyBreakdown 橫條 → 改用紅橘漸層 Capsule 填充；加入左展開進場動畫（對齊
//      allocationSection bar 規格），月份以膠囊徽章顯示，金額對齊右側。
//   6. taxSavingSection → taxSavingRow 圖示升級為 34pt 漸層圓（對齊 ExpenseRow icon 規格）；
//      進度條換用 Capsule 漸層（綠 → 橘）。
//   7. taxChecklistSection → 每列加入彩色圓形圖示 + 月份膠囊徽章 + 「應注意」改為 Capsule
//      （對齊統一列表 row 規格）；末項前加 Divider 視覺分隔。
//   8. deductionTipsSection → 圖示升級為 34pt 漸層圓，對齊 taxSavingRow 統一視覺。
//   9. 英雄卡片進場 spring 動畫（heroCardAppeared）+ 月份條進場動畫（monthBarAppeared）。
// [2026-06 v2] 本次美化方向：
//  10. taxRecordsSection 各列 → 38pt → 44pt 漸層圖示圓 + 左側 4pt 紅色強調條 + 交錯進場動畫
//      (taxRowsAppeared 旗標，0.05s/列 stagger)，對齊 ExpenseRow / FixedExpenseRow 視覺規格；
//      Divider leading 從 64 → 72（對齊 4pt bar + 14pt gap + 44pt icon + 12pt spacing）
//  11. taxRecordsSection / taxSavingSection 空狀態 → 雙層脈衝光環（emptyIconPulse）+ 漸層底圓，
//      對齊 VariableExpenseView.emptyStateView / IncomeView.emptyState 空狀態設計規格
//  12. taxChecklistSection / deductionTipsSection → 加入交錯淡入進場動畫
//      (checklistRowsAppeared / tipsRowsAppeared + 0.05s stagger)，
//      對齊 taxRecordsSection stagger 規格
// [2026-06 v3] 本次美化方向：
//  13. annualSummaryCard 玻璃光澤：背景 ZStack 末層加入 LinearGradient [.white.opacity(0.18), .clear]
//      top→center 玻璃反光覆蓋層，對齊 VariableExpenseView / IncomeView / OverviewView v3 英雄卡規格
//  14. annualSummaryCard 第三顆散景圓：右側中央加入微型模糊圓（width:50, opacity:0.05, blur:8）,
//      對齊 ChartView / VariableExpenseView v4 三顆散景圓設計語言
//  15. taxStatCell 圖示圓升級：36pt → 40pt LinearGradient 底 + Circle().stroke(color.opacity(0.25), 0.75pt)
//      overlay + 圖示 14→15pt，對齊 FinanceOverviewView allocationSection / OverviewView summaryCard v3 規格；
//      value Text 補 .contentTransition(.numericText()) 讓年份切換時數字平滑過渡
//  16. taxSavingSection 彙總列升級：純 Text HStack → 36pt 綠色漸層圖示圓（leaf.fill）+
//      右側金額改為綠色 Capsule 膠囊徽章（帶細邊框 0.6pt），
//      對齊 ResumeGiftSection 彙總列 / SpouseResumeView 金額設計語言
//  17. fmtShort 小數位補齊：「%.0f萬」→「%.1f萬」，對齊 OverviewView.smartCurrency /
//      FinanceOverviewView.fmtShort 的 1 位小數顯示規格，避免精度損失
// [2026-07 v4] 本次美化方向：
//  18. fmtShort 改用共用 Double.ntdWanString：原本手刻的「%.1f億／%.1f萬」缺少 NT$ 字首，
//      與同頁 fmt(taxTotal)（NT$ 前綴）、annualSummaryCard 年收入膠囊左右並排時字首不一致；
//      也未處理 ≥9999.95萬 應進位為億的邊界（會顯示成不合理的「10000.0萬」）。改呼叫全 App
//      共用的 ntdWanString，年收入 KPI 膠囊／月份長條金額／節稅彙總膠囊／扣除額已累積徽章
//      四類共 5 處呼叫點字首統一補齊「NT$」；月份長條金額欄位加 lineLimit(1) +
//      minimumScaleFactor(0.7)，扣除額已累積徽章加 lineLimit(1)，防止補上字首後在既有窄欄位/
//      膠囊內截斷。純顯示層調整，稅費加總、節稅累積、扣除額試算等既有邏輯未變動。

struct TaxOverviewView: View {
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    // 進場動畫旗標
    @State private var heroCardAppeared = false
    @State private var monthBarAppeared = false
    @State private var taxRowsAppeared = false
    @State private var checklistRowsAppeared = false
    @State private var tipsRowsAppeared = false
    /// 年份切換進場動畫延遲任務：快速連續切換年份會疊出多個 asyncAfter，
    /// 較舊的一個可能在較新的已把旗標設回 true 之後才觸發，動畫倒退造成閃爍；
    /// 改用可取消的 Task（比照 MainTabView.micEnterTask 既有寫法），切換時先取消前一個再排新的。
    @State private var yearNavAnimTask: Task<Void, Never>?
    @State private var yearChangeRowsTask: Task<Void, Never>?
    // 拆成兩個獨立旗標：taxRecordsSection（稅務紀錄是否為空）與 taxSavingSection
    // （節稅記錄是否為空）是兩個互不相關的條件，常常一個空一個不空。共用同一個
    // @State 時，若其中一個空狀態先掛載並把旗標設成 true，之後另一個空狀態掛載時
    // 旗標已是 true、.animation(value:) 偵測不到「從 false 變 true」的變化，
    // 脈衝光環會直接停在動畫結束狀態（不透明度 0）、永遠不會播放。
    @State private var emptyRecordsPulse = false
    @State private var emptySavingPulse = false
    @State private var emptyRecordsPulseTask: Task<Void, Never>?
    @State private var emptySavingPulseTask: Task<Void, Never>?

    // MARK: - 商業邏輯（不動）

    private var taxExpenses: [Expense] {
        expenseStore.expenses.filter {
            $0.variableCategory == .tax &&
            Calendar.current.component(.year, from: $0.date) == selectedYear
        }
        .sorted { $0.date > $1.date }
    }

    private var taxSavingExpenses: [Expense] {
        expenseStore.expenses.filter {
            $0.variableCategory == .taxSaving &&
            Calendar.current.component(.year, from: $0.date) == selectedYear
        }
        .sorted { $0.date > $1.date }
    }

    private struct TaxSavingAmounts {
        let direct: Double
        let fixed: Double
        var total: Double { direct + fixed }
    }

    /// 一次掃描 taxSavingExpenses + expenseStore.expenses，依子分類分桶存好直接/固定支出金額，
    /// 供 taxSavingSection / deductionTipsSection 共用，避免對每個子分類各自重複整批 filter+reduce
    /// （原本每個子分類需 4 次 O(n) 掃描，10 個子分類 = 近 40 次；改為固定 2 次）。
    private var taxSavingBySub: [TaxSavingSubCategory: TaxSavingAmounts] {
        var direct: [TaxSavingSubCategory: Double] = [:]
        for exp in taxSavingExpenses {
            if let sub = exp.taxSavingSubCategory { direct[sub, default: 0] += exp.amount }
        }
        var fixed: [TaxSavingSubCategory: Double] = [:]
        for exp in expenseStore.expenses where exp.expenseType == .fixed && exp.effectivelyTaxDeductible {
            if let sub = exp.inferredTaxSavingSubCategory {
                fixed[sub, default: 0] += yearEquivalentAmount(exp, year: selectedYear)
            }
        }
        var result: [TaxSavingSubCategory: TaxSavingAmounts] = [:]
        for sub in TaxSavingSubCategory.allCases {
            result[sub] = TaxSavingAmounts(direct: direct[sub] ?? 0, fixed: fixed[sub] ?? 0)
        }
        return result
    }

    private func yearEquivalentAmount(_ exp: Expense, year: Int) -> Double {
        let cal = Calendar.current
        let createYear = cal.component(.year, from: exp.date)
        guard createYear <= year else { return 0 }
        let monthsActive: Int
        if createYear < year {
            monthsActive = 12
        } else {
            let createMonth = cal.component(.month, from: exp.date)
            monthsActive = max(0, 12 - createMonth + 1)
        }
        switch exp.recurrence {
        case .monthly:   return exp.amount * Double(monthsActive)
        case .quarterly: return exp.amount * (Double(monthsActive) / 3.0)
        case .yearly:    return exp.amount
        case .none:      return 0
        }
    }

    private func taxByMonth(_ exps: [Expense]) -> [(month: Int, amount: Double)] {
        let cal = Calendar.current
        // 用 Dictionary(grouping:) 一次分組取代「12 次全量 filter」，避免 O(12n) 重複掃描
        let byMonth = Dictionary(grouping: exps) { cal.component(.month, from: $0.date) }
        var result: [(Int, Double)] = []
        for m in 1...12 {
            let amount = (byMonth[m] ?? []).reduce(0) { $0 + $1.amount }
            if amount > 0 { result.append((m, amount)) }
        }
        return result
    }

    private var realEstateCount: Int { financeStore.realEstates.filter { !$0.isSold }.count }
    private var vehicleCount: Int { financeStore.vehicles.filter { !$0.isSold }.count }

    private var estimatedAnnualIncome: Double {
        // 對齊 yearEquivalentAmount(_:year:) 的口徑：monthly／yearly 這種週期性收入也要以
        // 起始日 <= selectedYear 為準才計入，否則瀏覽過去年度時，今天才新增的月薪仍會被
        // 整年 x12 算進該年度的預估年收入，讓稅務占比／二代健保等 KPI 失真。
        expenseStore.incomes.reduce(0.0) { sum, inc in
            let incomeYear = Calendar.current.component(.year, from: inc.date)
            switch inc.period {
            case .monthly:
                guard incomeYear <= selectedYear else { return sum }
                return sum + inc.amount * 12
            case .yearly:
                guard incomeYear <= selectedYear else { return sum }
                return sum + inc.amount
            case .once:
                if incomeYear == selectedYear {
                    return sum + inc.amount
                }
                return sum
            }
        }
    }

    // MARK: - 主體

    var body: some View {
        // 一次計算子分類明細，供 annualSummaryCard / taxSavingSection / deductionTipsSection 共用
        let breakdown = taxSavingBySub
        let savingTotal = taxSavingExpenses.reduce(0.0) { $0 + $1.amount }
            + breakdown.values.reduce(0.0) { $0 + $1.fixed }
        // taxExpenses 是 filter+sort（O(n log n)），一次算好供 annualSummaryCard／
        // taxRecordsSection／monthlyBreakdown 共用，避免同一次 body 求值各自重跑三次。
        let exps = taxExpenses
        return NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    yearPicker
                    annualSummaryCard(savingTotal, exps: exps)
                        .opacity(heroCardAppeared ? 1 : 0)
                        .offset(y: heroCardAppeared ? 0 : 20)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                heroCardAppeared = true
                            }
                        }
                    taxRecordsSection(exps)
                    monthlyBreakdown(exps)
                    taxSavingSection(savingTotal, breakdown: breakdown)
                    taxChecklistSection
                    deductionTipsSection(breakdown: breakdown)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("稅務")
            .onChange(of: selectedYear) { _, _ in
                // yearPicker 只重置 heroCardAppeared/monthBarAppeared；
                // 此處補齊其餘旗標，確保切換年份後：
                //   1. emptyRecordsPulse/emptySavingPulse 歸零，下一個空狀態出現時脈衝動畫正確重啟
                //   2. 列項旗標歸零後延遲 0.08 s 重播進場動畫，對齊英雄卡片節奏
                emptyRecordsPulseTask?.cancel()
                emptySavingPulseTask?.cancel()
                emptyRecordsPulse = false
                emptySavingPulse = false
                taxRowsAppeared = false
                checklistRowsAppeared = false
                tipsRowsAppeared = false
                yearChangeRowsTask?.cancel()
                yearChangeRowsTask = Task {
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.50, dampingFraction: 0.82)) {
                        taxRowsAppeared = true
                        checklistRowsAppeared = true
                        tipsRowsAppeared = true
                    }
                }
            }
            .onDisappear {
                yearNavAnimTask?.cancel()
                yearChangeRowsTask?.cancel()
                emptyRecordsPulseTask?.cancel()
                emptySavingPulseTask?.cancel()
                heroCardAppeared = false
                emptyRecordsPulse = false
                emptySavingPulse = false
                taxRowsAppeared = false
                checklistRowsAppeared = false
                tipsRowsAppeared = false
            }
        }
    }

    // MARK: - 年度選擇（升級：圓形膠囊按鈕 + 加大年份文字）

    private var yearPicker: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                    selectedYear -= 1
                    heroCardAppeared = false
                    monthBarAppeared = false
                    yearNavAnimTask?.cancel()
                    yearNavAnimTask = Task {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                            heroCardAppeared = true
                            monthBarAppeared = true
                        }
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("\(String(selectedYear)) 年度")
                    .font(.title3.weight(.bold))
                Text("年度稅務報告")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                    selectedYear += 1
                    heroCardAppeared = false
                    monthBarAppeared = false
                    yearNavAnimTask?.cancel()
                    yearNavAnimTask = Task {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                            heroCardAppeared = true
                            monthBarAppeared = true
                        }
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        .padding(.horizontal)
    }

    // MARK: - 年度摘要英雄卡（升級：紅橘漸層 + 散景裝飾 + KPI 統計行）

    private func annualSummaryCard(_ savingTotal: Double, exps: [Expense]) -> some View {
        let taxTotal = exps.reduce(0) { $0 + $1.amount }
        let taxRatio = estimatedAnnualIncome > 0 ? taxTotal / estimatedAnnualIncome * 100 : 0

        return VStack(spacing: 0) {
            // 頂部：稅費 + 年收入
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("年度稅費支出")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                    Text(fmt(taxTotal))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    if taxTotal > 0 && estimatedAnnualIncome > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: taxRatio > 10 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .font(.system(size: 9))
                            Text("佔年收入 \(String(format: "%.1f", taxRatio))%")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(taxRatio > 10 ? 0.28 : 0.18))
                        .clipShape(Capsule())
                    }
                }
                Spacer()
                // 年收入 KPI 膠囊
                if estimatedAnnualIncome > 0 {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("預估年收入")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                        Text(fmtShort(estimatedAnnualIncome))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.white.opacity(0.18))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 0.75))
                }
            }

            // 分隔線
            Rectangle()
                .fill(.white.opacity(0.20))
                .frame(height: 0.5)
                .padding(.vertical, 14)

            // 4 個統計格
            HStack(spacing: 0) {
                taxStatCell(icon: "building.2.fill",      label: "持有房產", value: "\(realEstateCount) 筆", color: Color(red: 0.42, green: 0.62, blue: 1.00))
                taxStatDivider()
                taxStatCell(icon: "car.fill",             label: "持有車輛", value: "\(vehicleCount) 台",   color: Color(red: 1.00, green: 0.72, blue: 0.20))
                taxStatDivider()
                taxStatCell(icon: "doc.text.fill",        label: "稅費筆數", value: "\(exps.count) 筆", color: Color(red: 1.00, green: 0.78, blue: 0.75))
                taxStatDivider()
                taxStatCell(icon: "leaf.fill",            label: "節稅累積", value: fmtShort(savingTotal), color: Color(red: 0.62, green: 1.00, blue: 0.75))
            }
        }
        .padding(20)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.90, green: 0.28, blue: 0.22),
                        Color(red: 0.70, green: 0.15, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 右上散景圓
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 140, height: 140)
                    .offset(x: 85, y: -55)
                    .blur(radius: 14)
                // 左下散景圓
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 85, height: 85)
                    .offset(x: -65, y: 48)
                    .blur(radius: 10)
                // 右中微型散景圓（v3：第三顆，增加卡片立體層次感）
                Circle()
                    .fill(.white.opacity(0.05))
                    .frame(width: 50, height: 50)
                    .offset(x: 70, y: 36)
                    .blur(radius: 8)
                // 玻璃光澤反光層（v3：對齊 VariableExpenseView / IncomeView 英雄卡規格）
                LinearGradient(
                    colors: [.white.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.70, green: 0.15, blue: 0.12).opacity(0.42), radius: 18, x: 0, y: 9)
        .padding(.horizontal)
    }

    // [v3] 36pt → 40pt + stroke overlay + contentTransition（對齊 FinanceOverviewView allocationSection kpi 規格）
    private func taxStatCell(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.35), color.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(color.opacity(0.25), lineWidth: 0.75))
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.70))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func taxStatDivider() -> some View {
        Rectangle()
            .fill(.white.opacity(0.22))
            .frame(width: 0.5, height: 44)
    }

    // MARK: - 稅費紀錄（升級：漸層圖示圓 + 日期膠囊 + 空狀態佔位）

    private func taxRecordsSection(_ exps: [Expense]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("稅費紀錄", icon: "list.bullet.rectangle", color: .red,
                          count: exps.isEmpty ? nil : exps.count)

            if exps.isEmpty {
                // [v2] 雙層脈衝光環空狀態（對齊 VariableExpenseView.emptyStateView 規格）
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(Color.red.opacity(emptyRecordsPulse ? 0 : 0.28), lineWidth: 1.5)
                            .frame(width: 100, height: 100)
                            .scaleEffect(emptyRecordsPulse ? 1.38 : 1.0)
                            .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false), value: emptyRecordsPulse)
                        Circle()
                            .stroke(Color.red.opacity(emptyRecordsPulse ? 0 : 0.14), lineWidth: 1)
                            .frame(width: 100, height: 100)
                            .scaleEffect(emptyRecordsPulse ? 1.60 : 1.0)
                            .animation(.easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false), value: emptyRecordsPulse)
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.red.opacity(0.14), Color.red.opacity(0.06)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 80, height: 80)
                            .overlay(Circle().stroke(Color.red.opacity(0.20), lineWidth: 1.2))
                        Image(systemName: "doc.text")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(Color.red.opacity(0.65))
                    }
                    .onAppear {
                        emptyRecordsPulseTask?.cancel()
                        emptyRecordsPulseTask = Task {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            guard !Task.isCancelled else { return }
                            emptyRecordsPulse = true
                        }
                    }
                    Text("本年度尚無稅費紀錄")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                // [v2] 44pt 漸層圓 + 左側 4pt 強調條 + 交錯進場動畫（對齊 ExpenseRow / FixedExpenseRow）
                ForEach(Array(exps.enumerated()), id: \.element.id) { idx, exp in
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(
                                colors: [Color.red.opacity(0.85), Color.red.opacity(0.35)],
                                startPoint: .top, endPoint: .bottom))
                            .frame(width: 4)
                            .padding(.vertical, 10)
                            .padding(.trailing, 14)
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(
                                        colors: [Color.red.opacity(0.20), Color.red.opacity(0.08)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 44, height: 44)
                                    .shadow(color: Color.red.opacity(0.20), radius: 6, x: 0, y: 3)
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Color.red.opacity(0.85))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exp.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(fmtDate(exp.date))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Color(.tertiarySystemFill))
                                    .clipShape(Capsule())
                            }
                            Spacer(minLength: 4)
                            Text(fmt(exp.amount))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.red.opacity(0.85))
                                .contentTransition(.numericText())
                        }
                        .padding(.trailing, 14)
                        .padding(.vertical, 10)
                    }
                    .opacity(taxRowsAppeared ? 1 : 0)
                    .offset(y: taxRowsAppeared ? 0 : 12)
                    .animation(
                        .spring(response: 0.44, dampingFraction: 0.82).delay(0.05 * Double(idx)),
                        value: taxRowsAppeared
                    )

                    if idx < exps.count - 1 {
                        Divider().padding(.leading, 72)
                    }
                }
                .padding(.bottom, 4)
                .onAppear {
                    withAnimation(.spring(response: 0.50, dampingFraction: 0.82).delay(0.08)) {
                        taxRowsAppeared = true
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - 月份分佈（升級：漸層 Capsule + 進場動畫 + 月份膠囊徽章）

    @ViewBuilder
    private func monthlyBreakdown(_ exps: [Expense]) -> some View {
        let byMonth = taxByMonth(exps)
        if !byMonth.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("月份分佈", icon: "calendar", color: .orange,
                              count: byMonth.count)

                let maxAmount = byMonth.map(\.amount).max() ?? 1
                ForEach(Array(byMonth.enumerated()), id: \.element.month) { idx, item in
                    HStack(spacing: 10) {
                        // 月份膠囊
                        Text("\(item.month)月")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(red: 0.90, green: 0.28, blue: 0.22))
                            .frame(width: 30, alignment: .trailing)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color(red: 0.90, green: 0.28, blue: 0.22).opacity(0.10))
                            .clipShape(Capsule())

                        // 漸層 Capsule 進度條（左側展開進場）
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(.systemFill))
                                    .frame(height: 12)
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.90, green: 0.28, blue: 0.22),
                                                Color(red: 1.00, green: 0.55, blue: 0.20)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(
                                        width: max(8, geo.size.width * CGFloat(monthBarAppeared ? item.amount / maxAmount : 0)),
                                        height: 12
                                    )
                                    .animation(
                                        .spring(response: 0.65, dampingFraction: 0.80)
                                            .delay(0.06 * Double(idx)),
                                        value: monthBarAppeared
                                    )
                            }
                        }
                        .frame(height: 12)

                        Text(fmtShort(item.amount))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 66, alignment: .trailing)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }
                .padding(.bottom, 6)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
            .padding(.horizontal)
            .onAppear {
                // 與 yearPicker 前後年份切換共用同一個 yearNavAnimTask：避免這裡自己排的
                // 未持有 token 的 asyncAfter 和年份切換排的 Task 各自獨立觸發，較舊的一個
                // 在較新的已把 monthBarAppeared 設回 false 之後才觸發，造成進度條動畫倒退閃爍。
                yearNavAnimTask?.cancel()
                yearNavAnimTask = Task {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    guard !Task.isCancelled else { return }
                    monthBarAppeared = true
                }
            }
        }
    }

    // MARK: - 年度稅務檢核（升級：彩色圖示圓 + 月份膠囊 + 列間 Divider）

    private var taxChecklistSection: some View {
        let items: [(month: String, title: String, relevant: Bool, color: Color)] = [
            ("5月",  "綜合所得稅申報",     selectedYear < Calendar.current.component(.year, from: Date()), .indigo),
            ("5月",  "房屋稅繳納",         realEstateCount > 0,        .blue),
            ("7月",  "汽機車使用牌照稅",    vehicleCount > 0,            .orange),
            ("11月", "地價稅繳納",         realEstateCount > 0,        .purple),
            ("4月",  "汽機車燃料費",        vehicleCount > 0,            .teal),
            ("全年", "二代健保補充保費",    estimatedAnnualIncome > 0,  .green),
        ]

        let relevantCount = items.filter(\.relevant).count
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("年度稅務檢核", icon: "checkmark.square.fill", color: .green,
                          count: relevantCount > 0 ? relevantCount : nil)

            // [v2] 交錯淡入進場動畫（對齊 taxRecordsSection stagger 規格）
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                HStack(spacing: 12) {
                    // 狀態圖示圓
                    ZStack {
                        Circle()
                            .fill(
                                item.relevant
                                ? LinearGradient(colors: [item.color.opacity(0.20), item.color.opacity(0.08)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color(.systemFill), Color(.systemFill)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 36, height: 36)
                        Image(systemName: item.relevant ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(item.relevant ? item.color : Color(.tertiaryLabel))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.subheadline.weight(item.relevant ? .semibold : .regular))
                            .foregroundStyle(item.relevant ? .primary : .secondary)
                        // 月份膠囊
                        Text(item.month)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(item.relevant ? item.color : .secondary)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background((item.relevant ? item.color : Color.secondary).opacity(0.10))
                            .clipShape(Capsule())
                    }

                    Spacer(minLength: 4)

                    if item.relevant {
                        Text("應注意")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.orange.opacity(0.22), lineWidth: 0.6))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .opacity(checklistRowsAppeared ? 1 : 0)
                .offset(y: checklistRowsAppeared ? 0 : 12)
                .animation(
                    .spring(response: 0.44, dampingFraction: 0.82).delay(0.05 * Double(i)),
                    value: checklistRowsAppeared
                )

                if i < items.count - 1 {
                    Divider().padding(.leading, 62)
                }
            }
            .padding(.bottom, 4)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
        .onAppear {
            withAnimation(.spring(response: 0.50, dampingFraction: 0.82).delay(0.10)) {
                checklistRowsAppeared = true
            }
        }
    }

    // MARK: - 節稅累積（升級：漸層圖示圓 + 更精緻進度條）

    private func taxSavingSection(_ savingTotal: Double, breakdown: [TaxSavingSubCategory: TaxSavingAmounts]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("節稅累積", icon: "leaf.fill", color: .green, count: nil)

            if savingTotal == 0 {
                // [v2] 雙層脈衝光環空狀態（對齊 IncomeView.emptyState 設計規格）
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(Color.green.opacity(emptySavingPulse ? 0 : 0.26), lineWidth: 1.5)
                            .frame(width: 100, height: 100)
                            .scaleEffect(emptySavingPulse ? 1.38 : 1.0)
                            .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false), value: emptySavingPulse)
                        Circle()
                            .stroke(Color.green.opacity(emptySavingPulse ? 0 : 0.13), lineWidth: 1)
                            .frame(width: 100, height: 100)
                            .scaleEffect(emptySavingPulse ? 1.60 : 1.0)
                            .animation(.easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false), value: emptySavingPulse)
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.green.opacity(0.14), Color.green.opacity(0.05)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 80, height: 80)
                            .overlay(Circle().stroke(Color.green.opacity(0.18), lineWidth: 1.2))
                        Image(systemName: "leaf")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(Color.green.opacity(0.65))
                    }
                    .onAppear {
                        emptySavingPulseTask?.cancel()
                        emptySavingPulseTask = Task {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            guard !Task.isCancelled else { return }
                            emptySavingPulse = true
                        }
                    }
                    VStack(spacing: 8) {
                        Text("本年度尚無節稅紀錄")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("可在「變動支出」分類選「節稅」新增\n保險、房貸、房租固定支出也會自動納入")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                // [v3] 彙總列升級：36pt 漸層圖示圓 + 綠色 Capsule 金額徽章（對齊 ResumeGiftSection 彙總行規格）
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.green.opacity(0.22), Color.green.opacity(0.09)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(Color.green.opacity(0.18), lineWidth: 0.75))
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    Text("年度節稅總額")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(fmtShort(savingTotal))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(LinearGradient(
                            colors: [Color.green.opacity(0.82), Color.green.opacity(0.58)],
                            startPoint: .leading, endPoint: .trailing))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.green.opacity(0.30), lineWidth: 0.6))
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 14).padding(.vertical, 10)

                Divider().padding(.leading, 62)

                ForEach(TaxSavingSubCategory.allCases) { sub in
                    let amounts = breakdown[sub] ?? TaxSavingAmounts(direct: 0, fixed: 0)
                    if amounts.total > 0 {
                        taxSavingRow(sub: sub, amounts: amounts)
                        Divider().padding(.leading, 58)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    private func taxSavingRow(sub: TaxSavingSubCategory, amounts: TaxSavingAmounts) -> some View {
        let total = amounts.total
        let limit = sub.annualLimit
        let progress: Double = {
            guard let limit = limit, limit > 0 else { return 0 }
            return min(1, total / limit)
        }()
        let reachedCap = limit != nil && total >= (limit ?? 0)
        let direct   = amounts.direct
        let fromFixed = amounts.fixed
        let rowColor: Color = reachedCap ? .orange : .green

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // 34pt 漸層圖示圓
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [rowColor.opacity(0.20), rowColor.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                    Image(systemName: sub.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(rowColor)
                }

                Text(sub.rawValue)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(fmt(total))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(rowColor)
                    .contentTransition(.numericText())

                if reachedCap {
                    Text("已達上限")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if let limit = limit {
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.systemFill))
                                .frame(height: 5)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: reachedCap
                                            ? [Color.orange, Color.orange.opacity(0.65)]
                                            : [Color.green, Color.green.opacity(0.65)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(progress), height: 5)
                        }
                    }
                    .frame(height: 5)
                    HStack {
                        Text("上限 \(fmt(limit))")
                            .font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(.caption2)
                            .foregroundStyle(reachedCap ? .orange : .secondary)
                    }
                }
            } else {
                Text(sub.limitNote).font(.caption2).foregroundStyle(.tertiary)
            }

            // 來源拆解
            if direct > 0 && fromFixed > 0 {
                HStack(spacing: 6) {
                    sourceTag("直接記錄", value: fmt(direct),    color: .green)
                    sourceTag("固定支出", value: fmt(fromFixed), color: .blue)
                    Spacer()
                }
            } else if fromFixed > 0 && direct == 0 {
                HStack {
                    sourceTag("來自固定支出", value: fmt(fromFixed), color: .blue)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func sourceTag(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.caption2.weight(.medium))
            Text(value).font(.caption2)
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    // MARK: - 節稅項目提醒（升級：34pt 漸層圖示圓）

    private func deductionTipsSection(breakdown: [TaxSavingSubCategory: TaxSavingAmounts]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("節稅項目提醒", icon: "lightbulb.fill", color: Color(red: 1.00, green: 0.78, blue: 0.20))

            // [v2] 交錯淡入進場動畫（對齊 taxChecklistSection stagger 規格）
            ForEach(Array(TaxSavingSubCategory.allCases.enumerated()), id: \.element) { idx, sub in
                let acc = breakdown[sub]?.total ?? 0
                let iconColor: Color = acc > 0 ? .green : .blue

                HStack(alignment: .top, spacing: 12) {
                    // 34pt 漸層圖示圓
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [iconColor.opacity(0.18), iconColor.opacity(0.07)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 34, height: 34)
                        Image(systemName: sub.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("\(sub.rawValue)扣除額")
                                .font(.subheadline.weight(.semibold))
                            if acc > 0 {
                                Text("已累積 \(fmtShort(acc))")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.green)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Color.green.opacity(0.12))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.green.opacity(0.22), lineWidth: 0.6))
                            }
                        }
                        Text(sub.limitNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .opacity(tipsRowsAppeared ? 1 : 0)
                .offset(y: tipsRowsAppeared ? 0 : 12)
                .animation(
                    .spring(response: 0.44, dampingFraction: 0.82).delay(0.05 * Double(idx)),
                    value: tipsRowsAppeared
                )

                if idx < TaxSavingSubCategory.allCases.count - 1 {
                    Divider().padding(.leading, 62)
                }
            }
            .padding(.bottom, 4)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
        .onAppear {
            withAnimation(.spring(response: 0.50, dampingFraction: 0.82).delay(0.12)) {
                tipsRowsAppeared = true
            }
        }
    }

    // MARK: - 輔助：統一 section 標題（升級：Capsule 側條 + semibold + 可選計數膠囊）

    private func sectionHeader(_ title: String, icon: String, color: Color, count: Int? = nil) -> some View {
        HStack(spacing: 10) {
            // 左側 Capsule 側條（對齊 OverviewView categoryBreakdownSection）
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 18)

            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)

            Text(title)
                .font(.subheadline.weight(.semibold))

            Spacer()

            if let count = count {
                Text("\(count) 項")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - 格式化輔助

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f
    }()

    private func fmt(_ v: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    // [v4] 改呼叫共用 ntdWanString：補齊 NT$ 字首 + 萬轉億邊界防呆（見檔頭 v4 美化紀錄）
    private func fmtShort(_ v: Double) -> String {
        v.ntdWanString
    }

    private static let fmtDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()

    private func fmtDate(_ d: Date) -> String {
        Self.fmtDateFormatter.string(from: d)
    }
}
