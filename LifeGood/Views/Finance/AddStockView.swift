import SwiftUI

// MARK: - 美化紀錄（AddStockView）
// [2026-06 v1] 本次美化方向：
//   1. amountPreviewCard：頂部橘色漸層英雄卡，即時顯示持倉市值/損益 + 張數/買入均價/報酬率 KPI，
//      數字用 .contentTransition(.numericText()) 動畫，散景裝飾圓，
//      對齊 AddIncomeView.amountPreviewCard / FinanceOverviewView.totalAssetsCard 規格
//   2. quoteHeroCard：即時行情改為漸層英雄卡（漲綠跌紅動態配色），股價大字 +
//      漲跌幅膠囊 + OHLC KPI 橫列，對齊 FinanceOverviewView.totalAssetsCard 設計語言
//   3. calcSection：試算升級為「投入成本 / 目前市值」雙欄卡 + 損益大字 + 報酬率膠囊，
//      對齊 AddIncomeView.calcPreviewRows 規格
//   4. sectionHeader：各 Section 加 Capsule 漸層側條 + 圖示 + .subheadline.weight(.semibold) 標題，
//      對齊 AddExpenseView.basicInfoSection header 規格
//   5. 錯誤訊息：從紅字升級為橘色圓角橫幅（帶警告圖示），視覺更醒目但不突兀
//   6. .tint(.orange)：股票主題色統一套用，Toggle/DatePicker 等系統元件配色一致
//   7. 儲存/新增按鈕：改為橘色，對齊股票主題色
//   8. fetchButton：查詢圖示保留 .orange，與主題色一致
// [2026-06 v2] 本次美化方向：
//   9. amountPreviewCard：補第三顆散景裝飾圓（中右側 55pt, white.opacity(0.06), blur 8）
//      + 玻璃光澤高光覆層（LinearGradient [.white.opacity(0.18), .clear] 頂→中），
//      對齊 IncomeView / VariableExpenseView v4 三圓散景 + 玻璃光澤規格。
//  10. quoteHeroCard：同上補第三顆散景圓 + 玻璃光澤覆層，對齊全 App 英雄卡統一規格。
//  11. fetchError 行內錯誤：從 plain 紅字 HStack 升級為 errorBanner styled component
//      (橘色圓角橫幅 + 警告圖示)，對齊 showError 時已使用的 errorBanner 規格。
//  12. calcKPICell 標籤圓點：7pt 純色小圓點 → 26pt LinearGradient 漸層填色圓 + stroke 描邊，
//      對齊 IncomeView / FinanceOverviewView 圖示圓規格，讓試算欄位標籤更具層次。
// [2026-07 v3] 金額量級單位一致性修復：
//  13. fmtBalance（accountPicker「扣款帳戶」選單銀行/證券帳戶餘額標籤）原本手刻
//      NumberFormatter + 條件式「NT$ X萬」，是 AddExpenseView.formatBankBalance／
//      LifeFinanceView.fmtBal 已修復的同一支金額格式（先前兩處也是各自手刻，
//      已改呼叫共用 Double.ntdWanString）中，全 App 僅剩尚未跟進的一處。改呼叫
//      ntdWanString，移除已無呼叫端的 balanceFormatter 死碼。純視覺層調整，
//      帳戶餘額計算、扣款帳戶選取等既有商業邏輯完全未變動。
// [2026-08 v4] 本次美化方向（儲存按鈕載入狀態，延續 AddIncomeView／AddExpenseView／
// AddSavingsInsuranceView／AddVehicleView 待辦清單）：
//  14. 工具列「儲存／新增」按鈕：save() 自帶 isSaving 忙碌守衛（disabled(isSaving)）避免
//      快速連點造成重複股票紀錄，但按鈕本身在存檔期間毫無視覺提示。補上
//      ProgressView().scaleEffect(0.7).tint(.orange)，isSaving 為 true 時顯示於按鈕左側，
//      對齊已完成畫面的儲存按鈕載入狀態規格。純視覺層補強，save() 內部守衛判斷與
//      股票/連結支出/收入寫入邏輯完全未變動。同型 isSaving 守衛仍存在於
//      AddRealEstateView，可作為下次美化比照補齊的最後一項。
// [2026-08 v5] 補齊大字防截斷缺口：
//  15. quoteHeroCard 頂部 30pt 股價大字（Text(displayPrice...)）原本沒有 lineLimit／
//      minimumScaleFactor 防截斷保護，是同系列英雄卡 OverviewView／IncomeView／
//      FinanceOverviewView／FinanceChartView／ChartView／BusinessCardView 等皆已修過、
//      本檔案 amountPreviewCard 損益大字有防護但這處即時行情大字仍缺的同型缺口——高價股
//      （四位數以上）或窄螢幕時可能被系統裁切。補上 .lineLimit(1) + .minimumScaleFactor(0.6)，
//      對齊同卡片內其餘文字與全 App 英雄卡大字規格。純視覺層調整，displayPrice／漲跌幅計算
//      等既有商業邏輯完全未變動。
//      （下次美化本檔案時：儲存按鈕載入狀態、英雄卡大字防截斷皆已補齊，可轉往其他仍留有
//      待辦的畫面）

// MARK: - 台股報價資料

struct StockQuote {
    var name: String = ""
    var exchange: String = ""
    var lastPrice: Double = 0
    var yesterdayClose: Double = 0
    var openPrice: Double = 0
    var highPrice: Double = 0
    var lowPrice: Double = 0
    var volume: String = ""
    var date: String = ""
    var time: String = ""

    var changeAmount: Double { lastPrice > 0 ? lastPrice - yesterdayClose : 0 }
    var changePercent: Double { yesterdayClose > 0 ? changeAmount / yesterdayClose * 100 : 0 }
    var isUp: Bool { changeAmount >= 0 }
}

// MARK: - 新增/編輯股票

struct AddStockView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    var editing: Stock?

    @State private var name = ""
    @State private var symbol = ""
    @State private var purchaseDate = Date()
    @State private var lotsText = ""
    @State private var purchasePriceText = ""
    @State private var currentPriceText = ""
    @State private var note = ""
    @State private var showError = false
    @State private var errorText = "請輸入股票名稱、張數和買入價格"
    // 儲存為同步寫回 store（含連結支出/收入的建立與刪除）後立即 dismiss()，
    // sheet 收合動畫期間按鈕仍可觸發，快速連點會產生重複股票紀錄或重複的
    // 已實現損益支出/收入；補上忙碌守衛比照 AddRealEstateView 既有修法。
    @State private var isSaving = false

    @State private var isSold = false
    @State private var soldPriceText = ""
    @State private var soldDate = Date()

    @State private var selectedBankMilestoneId: UUID?
    @State private var selectedBankCurrency: String = "NT$"
    @State private var selectedSecuritiesMilestoneId: UUID?

    /// 扣款帳戶選單的餘額快取：allAccountBalances() 雖已改為批次建表，但 accountPicker
    /// 是 Form body 的一部分，任何欄位每次按鍵都會重新求值、重建整批表——改為只在
    /// expenseStore.expenses／lifeStore.milestones 實際變動時（.task(id:)）才重算一次快取，
    /// 對齊 AddExpenseView.cachedBankBalances 既有修復規格。
    @State private var cachedAccountBalances: [UUID: Double] = [:]

    @State private var isFetching = false
    @State private var fetchError = ""
    @State private var quote: StockQuote?

    // 進場動畫旗標
    @State private var cardAppeared = false

    var body: some View {
        NavigationStack {
            Form {
                // 頂部即時預覽卡（橘色漸層英雄卡）
                Section {
                    amountPreviewCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .opacity(cardAppeared ? 1 : 0)
                        .offset(y: cardAppeared ? 0 : 20)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                cardAppeared = true
                            }
                        }
                }

                Section {
                    HStack {
                        // 代號可含英文字母（如主動式 ETF 00981A），改用一般鍵盤；
                        // 儲存時已自動 uppercased，小寫輸入也沒問題
                        TextField("股票代號（如 2330、00981A）", text: $symbol)
                            .keyboardType(.asciiCapable)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        fetchButton
                    }
                    TextField("股票名稱", text: $name)
                    // v2：從 plain 紅字升級為 errorBanner styled component，對齊全 App 錯誤橫幅規格
                    if !fetchError.isEmpty {
                        errorBanner(fetchError)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    if !bankMilestones.isEmpty || !securitiesMilestones.isEmpty {
                        accountPicker
                    }
                    DatePicker("買入日期", selection: $purchaseDate, displayedComponents: .date)

                    HStack {
                        Toggle("已賣出", isOn: $isSold)
                            .frame(maxWidth: .infinity)
                        if isSold {
                            Divider()
                            HStack {
                                Text("NT$").foregroundStyle(.secondary)
                                TextField("賣出股價", text: $soldPriceText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    if isSold {
                        DatePicker("賣出日期", selection: $soldDate, in: purchaseDate..., displayedComponents: .date)
                    }
                } header: {
                    sectionHeader("股票資訊", icon: "chart.line.uptrend.xyaxis")
                }

                Section {
                    HStack {
                        TextField("持有張數", text: $lotsText)
                            .keyboardType(.decimalPad)
                        Text("張").foregroundStyle(.secondary)
                    }
                    if let lots = Double(lotsText), lots > 0 {
                        HStack {
                            Text("約合").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(formatShares(lots * 1000) + " 股")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("買入價格（每股）", text: $purchasePriceText)
                            .keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("目前價格（每股）", text: $currentPriceText)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    sectionHeader("持股資訊", icon: "chart.bar.fill")
                } footer: {
                    Text("台股 1 張 = 1000 股，可輸入小數（例：0.5 = 500 股零股）")
                }

                calcSection

                if let q = quote {
                    quoteDetailSection(q)
                }

                Section {
                    TextField("選填備註", text: $note, axis: .vertical)
                        .lineLimit(3)
                } header: {
                    sectionHeader("備註", icon: "note.text")
                }

                if showError {
                    Section {
                        errorBanner(errorText)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .tint(.orange)
            .navigationTitle(editing != nil ? "編輯股票" : "新增股票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 6) {
                        // [美化] 存檔中顯示同色 ProgressView，對齊 AddIncomeView／AddExpenseView／
                        // AddSavingsInsuranceView／AddVehicleView 儲存按鈕載入狀態規格
                        if isSaving {
                            ProgressView().scaleEffect(0.7).tint(.orange)
                        }
                        Button(editing != nil ? "儲存" : "新增") { save() }
                            .bold()
                            .foregroundStyle(.orange)
                            .disabled(isSaving)
                    }
                }
            }
            .onAppear { loadEditing() }
        }
    }

    // MARK: - Section Header（Capsule 側條 + 圖示 + 粗體標題）

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.orange, .orange.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 18)
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .textCase(nil)
        .padding(.bottom, 2)
    }

    // MARK: - 錯誤橫幅（橘色圓角，帶警告圖示）

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.footnote.weight(.semibold))
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.25), lineWidth: 0.75))
        .padding(.horizontal, 16)
    }

    // MARK: - KPI 格（白底英雄卡片內使用，白字白輔助文）

    private func kpiCell(_ label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    // MARK: - 頂部即時預覽英雄卡

    private var amountPreviewCard: some View {
        let lots = Double(lotsText) ?? 0
        let purchasePrice = Double(purchasePriceText) ?? 0
        let currentPrice = Double(currentPriceText) ?? 0
        let shares = lots * 1000
        let totalCost = shares * purchasePrice
        let marketValue = shares * currentPrice
        let pl = marketValue - totalCost
        let returnRate = totalCost > 0 ? pl / totalCost * 100 : 0
        let hasData = lots > 0 && purchasePrice > 0
        let hasCurrentPrice = currentPrice > 0

        return VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(hasData ? "持倉概覽" : "股票持倉")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                    if hasData && hasCurrentPrice {
                        Text(formatCurrency(marketValue))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                        Text("目前市值")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.white.opacity(0.20))
                            .clipShape(Capsule())
                            .foregroundStyle(.white)
                    } else if hasData {
                        Text(formatCurrency(totalCost))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                        Text("投入成本")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.white.opacity(0.20))
                            .clipShape(Capsule())
                            .foregroundStyle(.white)
                    } else {
                        Text(name.isEmpty ? "輸入股票資訊" : name)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(name.isEmpty ? 0.45 : 1.0))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Text(name.isEmpty ? "填入後即時預覽" : "輸入張數與股價預覽")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.white.opacity(0.20))
                            .clipShape(Capsule())
                            .foregroundStyle(.white)
                    }
                }
                Spacer()
                // 損益 KPI 膠囊（有輸入成本和市值時顯示）
                if hasData && hasCurrentPrice {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("投資損益")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                        HStack(spacing: 3) {
                            Image(systemName: pl >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text((pl >= 0 ? "+" : "") + formatCurrency(pl))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .contentTransition(.numericText())
                        }
                        .foregroundStyle(pl >= 0
                            ? Color(red: 0.60, green: 1.00, blue: 0.75)
                            : Color(red: 1.0, green: 0.78, blue: 0.75))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.18))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(pl >= 0 ? 0.35 : 0.25), lineWidth: 0.75))
                    }
                }
            }

            // KPI 底列（張數 / 買入均價 / 報酬率）
            if hasData {
                Rectangle()
                    .fill(.white.opacity(0.20))
                    .frame(height: 0.5)
                    .padding(.vertical, 12)

                HStack(spacing: 0) {
                    kpiCell("張數", value: "\(lotsText) 張")
                    Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 28)
                    kpiCell("買入均價", value: "NT$\(purchasePriceText)")
                    if hasCurrentPrice && totalCost > 0 {
                        Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 28)
                        kpiCell("報酬率", value: String(format: "%@%.1f%%",
                                                        returnRate >= 0 ? "+" : "", returnRate))
                    }
                }
                .padding(.vertical, 8)
                .background(.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.55, blue: 0.15),
                        Color(red: 0.72, green: 0.33, blue: 0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 右上散景圓，增加卡片層次感
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
                // v2：第三顆散景裝飾圓（中右側），對齊三圓散景標準
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 55, height: 55)
                    .offset(x: 20, y: 30)
                    .blur(radius: 8)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        // v2：玻璃光澤高光覆層，對齊全 App 英雄卡規格
        .overlay(
            LinearGradient(
                colors: [.white.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
        )
        .shadow(color: Color(red: 0.72, green: 0.33, blue: 0.05).opacity(0.42), radius: 18, x: 0, y: 9)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 帳戶選擇器（銀行 / 證券）

    private var bankMilestones: [LifeMilestone] {
        lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .bank
        }
    }

    private var securitiesMilestones: [LifeMilestone] {
        lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .securities
        }
    }

    private func bankCurrencies(for ms: LifeMilestone) -> [String] {
        let codes = (ms.bankDeposits ?? [])
            .filter { !$0.isWithdrawal }
            .map(\.currencyCode)
        var unique: [String] = []
        for c in codes where !unique.contains(c) { unique.append(c) }
        return unique.isEmpty ? ["NT$"] : unique
    }

    /// 計算全部銀行 / 證券帳戶的目前餘額，一次算好整批供 accountPicker 查表。
    /// 原本 accountBalance(for:) 每次呼叫都對 expenseStore.expenses 做 first(where:)/filter
    /// 全量掃描，而 accountPicker 是 Form body 的一部分，任何欄位每次按鍵都會觸發整個 body
    /// 重新求值——帳戶選單因此在打字時對 expenses 反覆全量掃描（O(帳戶數 × expenses) 每次按鍵）。
    /// 改為批次建表：expensesById／expensesByCardMilestone 各建一次，逐帳戶查表 O(1)，
    /// 對齊 AddExpenseView.allBankBalances() 既有修復規格。
    private func allAccountBalances() -> [UUID: Double] {
        let now = Date()
        let expensesById = Dictionary(expenseStore.expenses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let expensesByCardMilestone = Dictionary(grouping: expenseStore.expenses.filter {
            $0.linkedCreditCardMilestoneId != nil && $0.date <= now
        }, by: { $0.linkedCreditCardMilestoneId! })
        var result: [UUID: Double] = [:]
        for ms in bankMilestones + securitiesMilestones {
            var total: Double = 0
            for dep in ms.bankDeposits ?? [] {
                guard dep.date <= now else { continue }
                if let expId = dep.linkedExpenseId,
                   let exp = expensesById[expId],
                   exp.linkedCreditCardMilestoneId != nil {
                    continue
                }
                total += dep.isWithdrawal ? -dep.amount : dep.amount
            }
            if ms.financeSubCategory == .bank {
                let cards = lifeStore.milestones.filter {
                    $0.financeSubCategory == .creditCard && $0.linkedBankMilestoneId == ms.id
                }
                for card in cards {
                    for exp in expensesByCardMilestone[card.id] ?? [] { total -= exp.amount }
                }
            }
            result[ms.id] = total
        }
        return result
    }

    // 【美化方向】扣款帳戶選單餘額格式：先前自製 NumberFormatter 手刻「NT$ X萬」
    // （NT$ 後多一個空白、無條件捨去小數、未處理億級單位），與同一系列已修復的
    // AddExpenseView.formatBankBalance／LifeFinanceView.fmtBal（皆已改呼叫共用
    // Double.ntdWanString："NT$1.2萬" 無空白、億以上自動換算、非整數保留一位小數）
    // 風格不一致，餘額達千萬以上時也會顯示成不合理的鉅額「萬」數字。改呼叫共用
    // ntdWanString，與全 App 金額量級顯示規則對齊。純視覺調整，未變動帳戶餘額計算邏輯。
    private func fmtBalance(_ value: Double) -> String {
        value.ntdWanString
    }

    private var accountPickerLabel: String {
        if let id = selectedSecuritiesMilestoneId,
           let ms = securitiesMilestones.first(where: { $0.id == id }) {
            return ms.title
        }
        if let id = selectedBankMilestoneId,
           let ms = bankMilestones.first(where: { $0.id == id }) {
            let name = ms.bankName ?? ms.title
            return "\(name) · \(selectedBankCurrency)"
        }
        return "未選擇"
    }

    private var accountPicker: some View {
        HStack {
            Text("扣款帳戶").foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("不指定") {
                    selectedBankMilestoneId = nil
                    selectedSecuritiesMilestoneId = nil
                    selectedBankCurrency = "NT$"
                }
                if !bankMilestones.isEmpty {
                    Section("銀行") {
                        ForEach(bankMilestones) { ms in
                            let currencies = bankCurrencies(for: ms)
                            let name = ms.bankName ?? ms.title
                            let label = "\(name)（\(fmtBalance(cachedAccountBalances[ms.id] ?? 0))）"
                            if currencies.count > 1 {
                                Menu(label) {
                                    ForEach(currencies, id: \.self) { code in
                                        Button(code) {
                                            selectedBankMilestoneId = ms.id
                                            selectedBankCurrency = code
                                            selectedSecuritiesMilestoneId = nil
                                        }
                                    }
                                }
                            } else {
                                Button(label) {
                                    selectedBankMilestoneId = ms.id
                                    selectedBankCurrency = currencies.first ?? "NT$"
                                    selectedSecuritiesMilestoneId = nil
                                }
                            }
                        }
                    }
                }
                if !securitiesMilestones.isEmpty {
                    Section("證券") {
                        ForEach(securitiesMilestones) { ms in
                            let label = "\(ms.title)（\(fmtBalance(cachedAccountBalances[ms.id] ?? 0))）"
                            Button(label) {
                                selectedSecuritiesMilestoneId = ms.id
                                selectedBankMilestoneId = nil
                                selectedBankCurrency = "NT$"
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(accountPickerLabel)
                        .foregroundStyle((selectedBankMilestoneId == nil && selectedSecuritiesMilestoneId == nil) ? .secondary : .primary)
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        // 只在 expenses／milestones 實際變動時才重算批次表，避免表單任何欄位每次按鍵
        // 都重跑一次 O(帳戶數 × expenses) 全量掃描（見 cachedAccountBalances 宣告處說明）。
        .task(id: "\(expenseStore.modifyID)-\(lifeStore.milestones.count)") {
            cachedAccountBalances = allAccountBalances()
        }
    }

    // MARK: - 取得報價按鈕

    private var fetchButton: some View {
        Button {
            Task { await fetchStockInfo() }
        } label: {
            if isFetching {
                ProgressView()
                    .controlSize(.small)
                    .tint(.orange)
            } else {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }
        }
        .buttonStyle(.plain)
        .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty || isFetching)
    }

    // MARK: - 台股即時報價

    private func fetchStockInfo() async {
        let trimmed = symbol.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isFetching = true
        fetchError = ""
        defer { isFetching = false }

        if let result = await fetchTWSE(symbol: trimmed, exchange: "tse") {
            // 使用者可能在等待網路回應期間已把代號改成別的股票，回應回來時要先確認代號沒變才套用，
            // 避免舊代號的報價套到新代號的欄位上。
            guard symbol.trimmingCharacters(in: .whitespaces) == trimmed else { return }
            applyQuote(result)
            return
        }
        if let result = await fetchTWSE(symbol: trimmed, exchange: "otc") {
            guard symbol.trimmingCharacters(in: .whitespaces) == trimmed else { return }
            applyQuote(result)
            return
        }

        guard symbol.trimmingCharacters(in: .whitespaces) == trimmed else { return }
        quote = nil
        fetchError = "查無股票代號 \(trimmed) 的報價"
    }

    private func applyQuote(_ q: StockQuote) {
        quote = q
        if q.lastPrice > 0 {
            currentPriceText = String(format: "%.2f", q.lastPrice)
        } else if q.yesterdayClose > 0 {
            currentPriceText = String(format: "%.2f", q.yesterdayClose)
        }
        if !q.name.isEmpty && name.isEmpty {
            name = q.name
        }
    }

    private func fetchTWSE(symbol: String, exchange: String) async -> StockQuote? {
        let urlString = "https://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch=\(exchange)_\(symbol).tw"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let msgArray = json["msgArray"] as? [[String: Any]],
                  let m = msgArray.first else { return nil }

            let z = Double(m["z"] as? String ?? "") ?? 0
            let y = Double(m["y"] as? String ?? "") ?? 0
            guard z > 0 || y > 0 else { return nil }

            return StockQuote(
                name: (m["n"] as? String ?? "").trimmingCharacters(in: .whitespaces),
                exchange: exchange == "tse" ? "上市" : "上櫃",
                lastPrice: z,
                yesterdayClose: y,
                openPrice: Double(m["o"] as? String ?? "") ?? 0,
                highPrice: Double(m["h"] as? String ?? "") ?? 0,
                lowPrice: Double(m["l"] as? String ?? "") ?? 0,
                volume: m["v"] as? String ?? "",
                date: m["d"] as? String ?? "",
                time: m["t"] as? String ?? ""
            )
        } catch {
            return nil
        }
    }

    // MARK: - 即時行情英雄卡

    private func quoteDetailSection(_ q: StockQuote) -> some View {
        Section {
            quoteHeroCard(q)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if !q.volume.isEmpty {
                row("成交量", "\(q.volume) 張")
            }
            if !q.date.isEmpty || !q.time.isEmpty {
                row("更新時間", "\(q.date) \(q.time)")
            }
        } header: {
            sectionHeader("即時行情", icon: "waveform.path.ecg.rectangle")
        } footer: {
            Text("資料來源：臺灣證券交易所。盤中為即時報價，收盤後為收盤價。")
        }
    }

    private func quoteHeroCard(_ q: StockQuote) -> some View {
        let displayPrice = q.lastPrice > 0 ? q.lastPrice : q.yesterdayClose
        let isUp = q.isUp
        let plColor: Color = isUp
            ? Color(red: 0.60, green: 1.00, blue: 0.75)
            : Color(red: 1.0, green: 0.78, blue: 0.75)
        let sign = isUp ? "+" : ""

        return VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    if !q.exchange.isEmpty {
                        Text(q.exchange)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(.white.opacity(0.22))
                            .clipShape(Capsule())
                            .foregroundStyle(.white)
                    }
                    Text(displayPrice > 0 ? String(format: "%.2f", displayPrice) : "—")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(q.name.isEmpty ? symbol : q.name)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.20))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                // 漲跌幅 KPI 膠囊
                VStack(alignment: .trailing, spacing: 4) {
                    Text("漲跌")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                    HStack(spacing: 3) {
                        Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(String(format: "%@%.2f", sign, q.changeAmount))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Text(String(format: "%@%.2f%%", sign, q.changePercent))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                    }
                    .foregroundStyle(plColor)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.18))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 0.75))
                }
            }

            // OHLC KPI 橫列
            if q.openPrice > 0 || q.highPrice > 0 || q.yesterdayClose > 0 {
                Rectangle()
                    .fill(.white.opacity(0.20))
                    .frame(height: 0.5)
                    .padding(.vertical, 10)

                HStack(spacing: 0) {
                    if q.openPrice > 0 {
                        kpiCell("開盤", value: String(format: "%.2f", q.openPrice))
                    }
                    if q.highPrice > 0 {
                        if q.openPrice > 0 {
                            Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 28)
                        }
                        kpiCell("最高", value: String(format: "%.2f", q.highPrice))
                    }
                    if q.lowPrice > 0 {
                        Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 28)
                        kpiCell("最低", value: String(format: "%.2f", q.lowPrice))
                    }
                    if q.yesterdayClose > 0 {
                        Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 28)
                        kpiCell("昨收", value: String(format: "%.2f", q.yesterdayClose))
                    }
                }
                .padding(.vertical, 8)
                .background(.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            ZStack {
                LinearGradient(
                    colors: isUp
                        ? [Color(red: 0.15, green: 0.60, blue: 0.30), Color(red: 0.07, green: 0.40, blue: 0.20)]
                        : [Color(red: 0.65, green: 0.18, blue: 0.22), Color(red: 0.42, green: 0.08, blue: 0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 120, height: 120)
                    .offset(x: 80, y: -40)
                    .blur(radius: 12)
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 70, height: 70)
                    .offset(x: -55, y: 45)
                    .blur(radius: 8)
                // v2：第三顆散景裝飾圓（中右側），對齊三圓散景標準
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 50, height: 50)
                    .offset(x: 18, y: 28)
                    .blur(radius: 7)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        // v2：玻璃光澤高光覆層，對齊全 App 英雄卡規格
        .overlay(
            LinearGradient(
                colors: [.white.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
        )
        .shadow(color: (isUp ? Color.green : Color.red).opacity(0.35), radius: 16, x: 0, y: 7)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    // MARK: - 試算卡片（投入成本 / 市值雙欄 + 損益大字 + 報酬率膠囊）

    @ViewBuilder
    private var calcSection: some View {
        if let lots = Double(lotsText), let cost = Double(purchasePriceText),
           let current = Double(currentPriceText), lots > 0, cost > 0 {
            let shares = lots * 1000
            let totalCost = shares * cost
            let marketValue = shares * current
            let pl = marketValue - totalCost
            let returnRate = totalCost > 0 ? pl / totalCost * 100 : 0

            Section {
                calcCard(totalCost: totalCost, marketValue: marketValue, pl: pl, returnRate: returnRate)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                // 賣出損益（已賣出時額外顯示）
                if isSold, let sp = Double(soldPriceText), sp > 0 {
                    let soldPL = shares * (sp - cost)
                    let soldRR = totalCost > 0 ? soldPL / totalCost * 100 : 0
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("賣出損益")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text((soldPL >= 0 ? "+" : "") + formatCurrency(soldPL))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(soldPL >= 0 ? .green : .red)
                                .contentTransition(.numericText())
                        }
                        Spacer()
                        Text(String(format: "%@%.1f%%", soldRR >= 0 ? "+" : "", soldRR))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background((soldPL >= 0 ? Color.green : Color.red).opacity(0.12))
                            .foregroundStyle(soldPL >= 0 ? .green : .red)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(
                                (soldPL >= 0 ? Color.green : Color.red).opacity(0.22), lineWidth: 0.75
                            ))
                    }
                }
            } header: {
                sectionHeader("試算", icon: "function")
            }
        }
    }

    private func calcCard(totalCost: Double, marketValue: Double, pl: Double, returnRate: Double) -> some View {
        VStack(spacing: 10) {
            // 投入成本 / 目前市值雙欄
            HStack(spacing: 10) {
                calcKPICell(label: "投入成本", value: formatCurrency(totalCost), color: .blue)
                calcKPICell(label: "目前市值", value: formatCurrency(marketValue), color: .orange)
            }

            // 損益大字 + 報酬率膠囊
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("損益")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text((pl >= 0 ? "+" : "") + formatCurrency(pl))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(pl >= 0 ? .green : .red)
                        .contentTransition(.numericText())
                }
                Spacer()
                Text(String(format: "%@%.1f%%", returnRate >= 0 ? "+" : "", returnRate))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background((pl >= 0 ? Color.green : Color.red).opacity(0.12))
                    .foregroundStyle(pl >= 0 ? .green : .red)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(
                        (pl >= 0 ? Color.green : Color.red).opacity(0.25), lineWidth: 0.75
                    ))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // v2：calcKPICell 標籤從 7pt 純色小圓點升級為 26pt 漸層圓 + stroke 描邊，對齊圖示圓設計語言
    private func calcKPICell(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            // 26pt 漸層圖示圓（對齊 FinanceOverviewView / IncomeView 圖示圓規格）
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.22), color.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 26, height: 26)
                Circle()
                    .stroke(color.opacity(0.22), lineWidth: 0.75)
                    .frame(width: 26, height: 26)
                Image(systemName: label == "投入成本" ? "arrow.down.circle.fill" : "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            ZStack {
                Color(.systemBackground)
                color.opacity(0.04)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.12), lineWidth: 0.75))
        .shadow(color: color.opacity(0.12), radius: 6, y: 2)
    }

    // MARK: - 儲存

    private func save() {
        guard !isSaving else { return }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let lots = Double(lotsText), lots > 0,
              let price = Double(purchasePriceText), price > 0 else {
            errorText = "請輸入股票名稱、張數和買入價格"
            showError = true; return
        }
        // 已標記「已賣出」卻沒填賣出價格時，(Double(soldPriceText) ?? 0) 會靜默把賣出價當 0，
        // 存出「賣出價 0、100% 虧損」的錯誤記錄且不提示使用者，這裡改成擋下並要求補填。
        if isSold, (Double(soldPriceText) ?? 0) <= 0 {
            errorText = "已標記為賣出，請輸入賣出價格"
            showError = true; return
        }
        showError = false
        isSaving = true
        let shares = lots * 1000
        let stockId = editing?.id ?? UUID()
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let sp = isSold ? (Double(soldPriceText) ?? 0) : 0
        var expId = editing?.linkedExpenseId
        var incId = editing?.linkedIncomeId

        if isSold && sp > 0 {
            let pl = shares * (sp - price)
            if pl >= 0 {
                incId = syncSoldIncome(stockId: stockId, name: trimmedName, profit: pl, date: soldDate, note: trimmedNote, existingId: incId)
                // 改用 expenseStore.delete(_:) 清除連結支出，確保附加照片一併移除，避免孤兒照片
                if let eid = expId, let exp = expenseStore.expenses.first(where: { $0.id == eid }) {
                    expenseStore.delete(exp)
                }
                expId = nil
            } else {
                expId = syncSoldExpense(stockId: stockId, name: trimmedName, loss: abs(pl), date: soldDate, note: trimmedNote, existingId: expId)
                if let iid = incId { expenseStore.incomes.removeAll { $0.id == iid }; incId = nil }
            }
        } else {
            if let eid = expId, let exp = expenseStore.expenses.first(where: { $0.id == eid }) {
                expenseStore.delete(exp)
            }
            expId = nil
            if let iid = incId { expenseStore.incomes.removeAll { $0.id == iid }; incId = nil }
        }

        let item = Stock(
            id: stockId,
            name: trimmedName,
            symbol: symbol.trimmingCharacters(in: .whitespaces).uppercased(),
            purchaseDate: purchaseDate,
            shares: shares, purchasePrice: price,
            currentPrice: Double(currentPriceText) ?? price,
            note: trimmedNote,
            isSold: isSold,
            soldPrice: sp,
            soldDate: isSold ? soldDate : nil,
            linkedExpenseId: expId,
            linkedIncomeId: incId,
            linkedBankMilestoneId: selectedBankMilestoneId,
            linkedBankCurrency: selectedBankMilestoneId != nil ? selectedBankCurrency : nil,
            linkedSecuritiesMilestoneId: selectedSecuritiesMilestoneId,
            transactions: editing?.transactions ?? [],
            dividends: editing?.dividends ?? []
        )
        if editing != nil { financeStore.update(item) } else { financeStore.add(item) }
        syncAccountTransactions(for: item, previous: editing)
        dismiss()
    }

    /// 同步股票買賣到所選銀行/證券帳戶的存款記錄
    private func syncAccountTransactions(for stock: Stock, previous: Stock?) {
        // 移除舊帳戶中本股票的記錄
        let prevAccountIds = [previous?.linkedBankMilestoneId, previous?.linkedSecuritiesMilestoneId].compactMap { $0 }
        for prevId in prevAccountIds {
            if var oldMs = lifeStore.milestones.first(where: { $0.id == prevId }) {
                oldMs.bankDeposits?.removeAll { $0.linkedStockId == stock.id }
                lifeStore.update(oldMs)
            }
        }

        // 取得目標帳戶
        let targetId = stock.linkedBankMilestoneId ?? stock.linkedSecuritiesMilestoneId
        guard let accId = targetId,
              var ms = lifeStore.milestones.first(where: { $0.id == accId }) else { return }

        var list = ms.bankDeposits ?? []
        list.removeAll { $0.linkedStockId == stock.id }

        let currency = stock.linkedBankCurrency ?? "NT$"

        if !stock.transactions.isEmpty {
            // 已使用交易紀錄模式：每筆交易寫一筆 BankDeposit（依 T+2 交割日）
            for tx in stock.transactions {
                list.append(BankDeposit(
                    id: UUID(),
                    date: tx.settlementDate,
                    amount: tx.amount,
                    currencyCode: currency,
                    isWithdrawal: tx.kind == .buy,
                    linkedExpenseId: nil,
                    linkedStockId: stock.id
                ))
            }
        } else {
            // 舊版聚合模式：一筆買入 + 一筆賣出（若有），皆依 T+2 交割
            let cost = stock.shares * stock.purchasePrice
            if cost > 0 {
                list.append(BankDeposit(
                    id: UUID(),
                    date: StockTransaction.taiwanSettlementDate(from: stock.purchaseDate),
                    amount: cost,
                    currencyCode: currency, isWithdrawal: true,
                    linkedExpenseId: nil, linkedStockId: stock.id
                ))
            }
            if stock.isSold, stock.soldPrice > 0, let sd = stock.soldDate {
                let saleAmount = stock.shares * stock.soldPrice
                if saleAmount > 0 {
                    list.append(BankDeposit(
                        id: UUID(),
                        date: StockTransaction.taiwanSettlementDate(from: sd),
                        amount: saleAmount,
                        currencyCode: currency, isWithdrawal: false,
                        linkedExpenseId: nil, linkedStockId: stock.id
                    ))
                }
            }
        }

        ms.bankDeposits = list
        lifeStore.update(ms)
    }

    private var soldAccountId: UUID? {
        selectedBankMilestoneId ?? selectedSecuritiesMilestoneId
    }

    private func syncSoldIncome(stockId: UUID, name: String, profit: Double, date: Date, note: String, existingId: UUID?) -> UUID {
        let incId = existingId ?? UUID()
        let income = Income(
            id: incId, title: "賣出 \(name)（獲利）",
            amount: profit, date: date,
            category: .investment, period: .once,
            note: note, linkedStockId: stockId,
            linkedBankMilestoneId: soldAccountId,
            linkedBankCurrency: soldAccountId != nil ? selectedBankCurrency : nil
        )
        if existingId != nil { expenseStore.update(income) }
        else { expenseStore.add(income) }
        return incId
    }

    private func syncSoldExpense(stockId: UUID, name: String, loss: Double, date: Date, note: String, existingId: UUID?) -> UUID {
        let expId = existingId ?? UUID()
        // 帶回既有 photoFileNames：使用者可能在 AddExpenseView 為這筆連結支出另外附加照片，
        // 本函式每次存檔都整筆重建 Expense，不帶回會把照片默默清空、原始檔案變孤兒
        // （同一 bug class 見 AddRealEstateView.syncInsuranceExpense 上方註解）。
        let existingPhotos = existingId.flatMap { id in expenseStore.expenses.first(where: { $0.id == id })?.photoFileNames } ?? []
        let expense = Expense(
            id: expId, title: "賣出 \(name)（虧損）",
            amount: loss, date: date,
            expenseType: .variable, variableCategory: .stock,
            linkedStockId: stockId, note: note,
            linkedBankMilestoneId: soldAccountId,
            linkedBankCurrency: soldAccountId != nil ? selectedBankCurrency : nil,
            photoFileNames: existingPhotos
        )
        if existingId != nil { expenseStore.update(expense) }
        else { expenseStore.add(expense) }
        return expId
    }

    // MARK: - 載入編輯

    private func loadEditing() {
        guard let e = editing else { return }
        name = e.name; symbol = e.symbol
        purchaseDate = e.purchaseDate
        // 從股數轉換回張數顯示（1 張 = 1000 股）
        let lots = e.shares / 1000
        if lots == lots.rounded() {
            lotsText = String(format: "%.0f", lots)
        } else {
            lotsText = String(format: "%g", lots)
        }
        purchasePriceText = String(format: "%.2f", e.purchasePrice)
        currentPriceText = String(format: "%.2f", e.currentPrice)
        note = e.note
        isSold = e.isSold
        soldPriceText = e.soldPrice > 0 ? String(format: "%.2f", e.soldPrice) : ""
        soldDate = e.soldDate ?? Date()
        selectedBankMilestoneId = e.linkedBankMilestoneId
        selectedBankCurrency = e.linkedBankCurrency ?? "NT$"
        selectedSecuritiesMilestoneId = e.linkedSecuritiesMilestoneId
    }

    private func formatCurrency(_ value: Double) -> String {
        value.ntdWanString
    }

    private static let sharesFormatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()

    private func formatShares(_ value: Double) -> String {
        Self.sharesFormatter.string(from: NSNumber(value: value)) ?? "0"
    }
}
