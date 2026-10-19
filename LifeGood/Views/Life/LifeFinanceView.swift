import SwiftUI

// MARK: - 美化紀錄（LifeFinanceView · v9 · 2026-08-03）
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
// [2026-08 v8] insuranceDetail「保費」金額量級補齊：
//  19. 承接 v6 對同一張 FinanceCardView 明細卡「額度」「年費」的修法，「保費」原本仍是
//      「NT$\(fmtNum(pa))」純整數無量級轉換，是 v6 當時漏掉、同一批 infoRow 金額欄位中
//      唯一沒跟進 ntdWanString 的一處。改呼叫共用 Double.ntdWanString；fmtNum(_:) 本身在
//      同一 struct 內仍有 depositRow／餘額列等其他呼叫端（非本次金額欄位性質，維持原樣），
//      故保留不動，僅改「保費」這一處呼叫點。純顯示層調整，保費／到期日等既有資料綁定
//      完全未變動。
// [2026-08 v9] milestoneRow「銀行帳戶」列表餘額量級補齊：
//  20. bankBalanceDisplay(_:) 是本檔案 v4～v8 四輪 ntdWanString 一致性修復唯一漏掉的一處：
//      主列表每一列銀行帳戶餘額原本用私有 formatNumber(_:)（純千分位整數，無萬/億量級），
//      同一筆帳戶點進 FinanceCardView 詳情頁卻已是 ntdWanString 規格，導致「列表 NT$
//      1,234,567」點進去變成「詳情頁 NT$123.4萬」，同一數字兩種顯示語言。多幣別（USD／
//      JPY 等）分支不能直接沿用 ntdWanString（會寫死錯誤的「NT$」字首蓋掉原幣別），
//      故於 FinanceModels.swift 新增 Double.wanString(symbolPrefix:)，沿用相同萬/億進位
//      規則、僅符號可自訂；單一幣別分支改呼叫 entry.1.wanString(symbolPrefix: entry.0)，
//      多幣別台幣等值分支改呼叫既有 ntdWanString。移除已無呼叫端的 formatNumber(_:)／
//      decimalFormatter 死碼。純顯示層調整，餘額換算、幣別歸戶等既有邏輯完全未變動。
// [2026-08 v25.101] 本次美化方向（DepositEditorSheet 工具列儲存按鈕補齊載入狀態）：
//  21. DepositEditorSheet 的 save()／saveTransfer()／saveAdjust() 三個存檔入口共用同一顆
//      isSaving 忙碌守衛（disabled(saveDisabled || isSaving)）避免快速連點造成重複存款／
//      提款／轉帳／沖正紀錄，但按鈕本身在存檔期間毫無視覺提示。比照 MyCalendarView
//      v25.100／SubordinateDetailView v25.99 等全 App 儲存按鈕載入狀態規格，於按鈕左側補上
//      HStack { if isSaving { ProgressView().scaleEffect(0.7).tint(.green) }；Button(...) }。
//      純視覺層調整，三個 save 函式內部守衛判斷與帳戶餘額寫入等既有商業邏輯完全未變動。
//      全 App 同型待辦清單（v25.96 起紀錄）已於 v25.102 補齊 ResumeView，僅剩
//      ChildDetailView，下次可依序比照補齊。
//   （下次美化本檔案時，可轉往其他仍留有待辦的畫面）

// MARK: - [v25.563] 算錢的共用函式搬去 Models/WealthFacts.swift

// 以前這裡有四支展開（固定支出、信用卡、月薪）、虛擬紀錄的雜湊 id、跳過規則、每個帳戶的餘額、1:1 換台幣、
// 信用卡期別——v2 全部搬進 WealthFacts.swift（WealthIDs、WealthFacts.isReplaced、WealthCardCycle…；一套數字：
// 存摺上、卡費在繳款截止日才扣、期數一次算、金額照當時、對存摺、轉帳）。這個檔一律讀 lifeStore.wealthFacts(expense:finance:)。

// MARK: - [v25.562] 切到背景就蓋住

/// armed 的畫面一切到背景，App 切換器的縮圖看到的是一層霧＋鎖頭，不是卡號、帳號、金額。
/// 只看 scenePhase：叫出 App 切換器、下拉控制中心、來電那一刻是 .inactive 就蓋，回到 .active 才拿掉。
/// armed 是 false 就什麼都不做（沒有號碼的表單不被打擾）。財富卡片一律 armed（judge §7.1、§9-14），
/// 編輯表單有號碼才 armed。
/// ⚠️ 每個敏感的 sheet 自己掛（財富卡片、編輯表單）：sheet 蓋在 App 最外層畫面的上面，
///    掛在 LifeGoodApp 最外層蓋不到 sheet。號碼要不要收回由各畫面自己決定
///    （財富卡片收回；編輯表單裡打到一半的卡號不收，只蓋）。
struct WealthPrivacyCurtain: ViewModifier {
    let armed: Bool
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.overlay {
            if armed && scenePhase != .active {
                WealthPrivacyCurtainCover()
            }
        }
    }
}

// MARK: - [v25.562] 刪財富帳戶的確認框（財富卡片、履歷共用；字由 LifeStore.financeDeletionImpact 數好）

/// 還在用的卡：〔改成停用〕〔仍要刪除〕〔取消〕；銀行和其他：〔刪除〕〔取消〕。
/// 拆成 ViewModifier：卡片頁的 body 已經掛了一長串 sheet／alert，再塞會讓型別檢查逾時（坑 #7）。
/// onDelete 由呼叫端決定怎麼刪（卡片頁先關畫面、下一個 runloop 才寫 store；履歷直接刪）。
struct FinanceDeleteAlert: ViewModifier {
    @Binding var pending: FinanceDeletionImpact?
    let onDisable: (LifeMilestone) -> Void
    let onDelete: (LifeMilestone) -> Void

    func body(content: Content) -> some View {
        content.alert(
            pending?.title ?? "確定要刪除嗎？",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { impact in
            if impact.offersDisable {
                Button("改成停用") { onDisable(impact.item) }
            }
            Button(impact.deleteButtonTitle, role: .destructive) { onDelete(impact.item) }
            Button("取消", role: .cancel) {}
        } message: { impact in
            Text(impact.message)
        }
    }
}

/// 布幕本身：厚霧（ultraThin 的霧太薄，大字卡號還認得出來）＋鎖頭＋「美好人生」
private struct WealthPrivacyCurtainCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.thickMaterial)
            VStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("美好人生")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - [v25.563] 「為什麼數字變了」說明一次（judge §9-1；字由 WealthFacts.passbookNotice 用你自己的數字組好）

fileprivate struct WealthNoticeAlert {
    let title: String
    let message: String
}

/// 拆成 ViewModifier：財富頁 body 已經掛了 sheet、toolbar，再塞一個 alert 會讓型別檢查變慢（坑 #7）。
/// 只有一顆〔知道了〕：按了才記成說明過（onDone），換頁回來不再跳。
fileprivate struct WealthNoticeAlertModifier: ViewModifier {
    @Binding var notice: WealthNoticeAlert?
    let onDone: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            notice?.title ?? "",
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }),
            presenting: notice
        ) { _ in
            Button("知道了") { onDone() }
        } message: { n in
            Text(n.message)
        }
    }
}

struct LifeFinanceView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    /// [v25.563] 一套數字（lifeStore.wealthFacts）要股票的交割、股利
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var selectedSub: FinanceSubCategory?
    @State private var viewingItem: LifeMilestone?
    @State private var showAdd = false
    @State private var showPremiumAlert = false
    // 進場動畫旗標
    @State private var headerAppeared = false
    @State private var rowsAppeared = false
    /// [v25.563] 第一次打開說明「為什麼數字變了」；nil＝沒在說
    @State private var notice: WealthNoticeAlert?

    /// 列表最外層的列：沒掛在銀行底下的。
    /// [v25.562] 指到的銀行已經不在（舊資料：以前刪銀行沒清卡的連結）也當獨立一列——
    /// 以前只認 linkedBankMilestoneId == nil，刪掉郵局，掛在郵局底下的卡整張不見。
    private var financeMilestones: [LifeMilestone] {
        let bankIds = Set(lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .bank
        }.map(\.id))
        return lifeStore.milestones
            .filter { m in
                m.category == .achievement
                    && (m.linkedBankMilestoneId.map { !bankIds.contains($0) } ?? true)
            }
            .sorted { $0.date > $1.date }
    }

    /// 所有理財里程碑（含銀行下的信用卡），用於總覽計數
    private var allFinanceMilestones: [LifeMilestone] {
        lifeStore.milestones.filter { $0.category == .achievement }
    }

    /// [v25.562] 全部的信用卡（含掛在銀行底下的），新到舊。「信用卡」篩選與膠囊計數用，跟英雄卡的張數一樣。
    private var allCreditCards: [LifeMilestone] {
        lifeStore.milestones
            .filter { $0.category == .achievement && $0.financeSubCategory == .creditCard }
            .sorted { $0.date > $1.date }
    }

    private var filteredMilestones: [LifeMilestone] {
        guard let sub = selectedSub else { return financeMilestones }
        // [v25.562] 「信用卡」從全部的卡篩：以前只看最外層，掛在銀行底下的卡點了篩選反而看不到
        if sub == .creditCard { return allCreditCards }
        return financeMilestones.filter { $0.financeSubCategory == sub }
    }

    /// 篩選膠囊的計數：信用卡那格數全部的卡，其他照舊數最外層的列（點下去看到幾張就寫幾張）
    private var filterChipCounts: [FinanceSubCategory: Int] {
        var counts: [FinanceSubCategory: Int] = financeMilestones.reduce(into: [:]) { dict, m in
            if let sub = m.financeSubCategory { dict[sub, default: 0] += 1 }
        }
        counts[.creditCard] = allCreditCards.count
        return counts
    }

    var body: some View {
        // [v25.563] 一套數字：只叫一次往下傳（LifeStore 快取；資料沒變不重算，捲動、重畫都不重算）
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        NavigationStack {
            // [對齊 SavingsInsuranceView 看板規格] 英雄看板與篩選列改為 List 內首個 Section，
            // 隨內容一起捲動，不再固定釘在列表上方。
            milestoneList(facts: facts)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("財富")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        Text(facts.cashText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(facts.cash >= 0 ? Color.blue : Color.red)
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
                    .appStores()
            }
            .sheet(item: $viewingItem) { item in
                FinanceCardView(milestoneId: item.id)
                    .appStores()
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
        // [v25.563] 第一次打開：用你自己的數字說明為什麼銀行的數字變了（說一次，跟 iCloud 同步）
        .onAppear { checkPassbookNotice() }
        .modifier(WealthNoticeAlertModifier(notice: $notice, onDone: { markPassbookNoticeSeen() }))
    }

    // MARK: - [v25.563] 「為什麼數字變了」

    /// 說明過就不再說；有卡費還沒扣、或以前沖正過還沒對過存摺的帳戶才說（字是 passbookNotice 組好的）；
    /// 有銀行帳戶、但兩種都沒有＝數字沒變，直接記成說明過；一個銀行帳戶都沒有＝先不記（以後有了再說）
    private func checkPassbookNotice() {
        guard notice == nil,
              !lifeStore.wealthBook.hasNotice(WealthBook.passbookNoticeKey) else { return }
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        if let n = facts.passbookNotice {
            notice = WealthNoticeAlert(title: n.title, message: n.message)
        } else if !facts.banks.isEmpty {
            markPassbookNoticeSeen()
        }
    }

    /// 記成說明過：store 先抓進區域常數、下一個 runloop 才寫（alert 正在收起來）
    private func markPassbookNoticeSeen() {
        let life = lifeStore
        DispatchQueue.main.async {
            life.markWealthNoticeSeen(WealthBook.passbookNoticeKey)
        }
    }

    // MARK: - 摘要（英雄卡）

    private let heroAccent     = Color(red: 0.22, green: 0.53, blue: 0.98)
    private let heroAccentDark = Color(red: 0.10, green: 0.35, blue: 0.82)

    /// [v25.563] 「存款合計（存摺上）」：facts.cashText（「NT$81.7萬」；有幣別查不到匯率「約 NT$71.4萬」），
    /// 下面一句「卡費還沒扣 NT$4.8萬、交割 NT$5.2萬」（都沒有不出現）
    private func summaryHeader(facts: WealthFacts) -> some View {
        let isPositive = facts.cash >= 0
        let pendingLine: String? = facts.notYetDebitedText
        // 一次取出，避免 ForEach 內 4 次重複 O(n) filter
        let milestones = allFinanceMilestones
        let totalCount = milestones.count
        let countBySub: [FinanceSubCategory: Int] = milestones.reduce(into: [:]) { dict, m in
            if let sub = m.financeSubCategory { dict[sub, default: 0] += 1 }
        }

        return VStack(spacing: 0) {
            // 頂部：存款合計（存摺上）+ 計數膠囊
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("存款合計（存摺上）")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    Text(facts.cashText)
                        .heroBigValueFont()
                        .foregroundStyle(isPositive ? .white : Color(red: 1.0, green: 0.78, blue: 0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .shadow(
                            color: isPositive ? .clear : Color.red.opacity(0.40),
                            radius: 6, x: 0, y: 2
                        )
                    if let line = pendingLine {
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
        .heroCardShell(card: .lifeFinance)
        .padding(.horizontal, 16)
    }

    // MARK: - 篩選

    private var filterChips: some View {
        // 一次建立計數表，避免 ForEach 內對每個分類各做一次 O(n) filter
        let countBySub: [FinanceSubCategory: Int] = filterChipCounts
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

    private func milestoneList(facts: WealthFacts) -> some View {
        // [v25.563] facts 由 body 叫一次傳進來（英雄卡、每一列銀行、每一張卡都讀這一份）
        // 一次依 linkedBankMilestoneId 分組信用卡，避免每一列銀行帳戶各自對
        // lifeStore.milestones 做一次 O(n) filter（N 家銀行 × M 筆信用卡 = O(n×m)）
        let cardsByBank = Dictionary(grouping: lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .creditCard && $0.linkedBankMilestoneId != nil
        }, by: { $0.linkedBankMilestoneId! })
        return List {
            Section {
                summaryHeader(facts: facts)
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
                    milestoneRow(item, account: facts.account(item.id))
                        .contentShape(Rectangle())
                        .onTapGesture { viewingItem = item }

                    if item.financeSubCategory == .bank {
                        let cards = cardsByBank[item.id] ?? []
                        if !cards.isEmpty {
                            ForEach(cards) { card in
                                creditCardSubRow(card, facts: facts.card(card.id))
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

    /// [v25.563] 掛在銀行底下的卡，第二行：「要繳 NT$18,600・10/27 截止」→ 不然「還沒出帳 NT$23,000・10/25 結帳」
    /// → 都沒有「結帳 25 日・截止 10 日」（名詞照 judge §3.15：結帳日／繳款截止日）；沒填日子也沒有錢＝nil
    private func cardSubRowStatus(_ card: LifeMilestone, facts cf: WealthFacts.Card?) -> String? {
        if let cf {
            if cf.due > 0.004 {
                let dueDay = cf.dueStatement.map { "・" + WealthFormat.monthDay($0.due) + " 截止" } ?? ""
                return "要繳 " + WealthFormat.ntd(cf.due) + dueDay
            }
            if cf.unbilled > 0.004 {
                return "還沒出帳 " + WealthFormat.ntd(cf.unbilled) + "・" + WealthFormat.monthDay(cf.nextClose) + " 結帳"
            }
        }
        guard let bd = card.billingDay, let pd = card.paymentDay else { return nil }
        return "結帳 \(bd) 日・截止 \(pd) 日"
    }

    private func creditCardSubRow(_ card: LifeMilestone, facts cf: WealthFacts.Card?) -> some View {
        let disabled = card.isDisabled == true
        let accent: Color = disabled ? .secondary : .orange
        let status: String? = cardSubRowStatus(card, facts: cf)
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
                    // [v25.520] 卡名放不下改跑馬燈（原本 lineLimit(1) 切成「…」）
                    MarqueeText(card.cardName ?? card.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(disabled ? .secondary : .primary)
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
                    if let s = status {
                        Text(s)
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
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

    private func milestoneRow(_ item: LifeMilestone, account: WealthFacts.Account?) -> some View {
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
                MarqueeText(item.title).font(.subheadline.weight(.semibold))
                subtitle(for: item)
            }
            Spacer()
            if item.financeSubCategory == .bank {
                // [v25.563] 「存摺上／NT$128,400／扣完能用 NT$5.3萬」（一套數字；找不到帳戶不畫）
                if let acct = account {
                    bankBalanceColumn(acct)
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

    /// [v25.563] 銀行列右邊三行：「存摺上」／acct.balanceText（負的紅、其他藍）／
    /// acct.footnoteText（「沒有匯率」橘、「扣完能用 NT$5.3萬」灰；都沒有不出現）
    private func bankBalanceColumn(_ acct: WealthFacts.Account) -> some View {
        let negative = bankBalanceIsNegative(acct)
        let foot: String? = acct.footnoteText
        let footColor: Color = acct.hasUnknownRate ? Color.orange : Color.secondary
        return VStack(alignment: .trailing, spacing: 2) {
            Text("存摺上")
                .font(.caption2).foregroundStyle(.tertiary)
            Text(acct.balanceText)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(negative ? Color.red : Color.blue)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let f = foot {
                Text(f)
                    .font(.caption2)
                    .foregroundStyle(footColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// 大字是哪個數就看哪個數的正負：一個幣別看那個幣別（外幣查不到匯率時台幣合計是 0，不能拿它判斷），好幾個幣別看台幣合計
    private func bankBalanceIsNegative(_ acct: WealthFacts.Account) -> Bool {
        if let c = acct.singleCode { return acct.balance(c) < -0.004 }
        return acct.ntdTotal < -0.004
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
            // [v25.562] 保單號碼只露後 4 碼（列表沒有 Face ID，看完整的到卡片頁按眼睛）
            let parts = [item.insuranceType?.rawValue, maskedPolicyNumber(item)].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty { Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        case .none:
            if !item.note.isEmpty { Text(item.note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
    }

    /// 「•••• 1234」；沒填（或只有空白）＝nil，不出一個孤零零的「•••• 」
    private func maskedPolicyNumber(_ item: LifeMilestone) -> String? {
        guard let pn = item.policyNumber,
              !pn.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return CardVault.maskedTail(pn)
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
    /// [v25.562] 切到背景：號碼收回＋布幕（WealthPrivacyCurtain）
    @Environment(\.scenePhase) private var scenePhase
    @State private var showEdit = false
    /// [v25.562] 刪除確認框要講的話（LifeStore.financeDeletionImpact 數好的）；nil＝沒在問
    @State private var pendingDelete: FinanceDeletionImpact?
    /// [v25.532] 新增存款要帶哪個幣別：跟「打開」綁在一起（sheet(item:)）。以前是先改 addDepositCurrency、
    /// 再把 showAddDeposit 設成 true，sheet 有時會用到改之前的舊幣別——選港幣卻跳出台幣，多按幾次才對。
    @State private var addingDeposit: AddDepositRequest?
    @State private var editingDeposit: BankDeposit?
    @State private var viewingLinkedCard: LifeMilestone?
    @State private var depositsExpanded = false
    @State private var editingExpense: Expense?
    @State private var editingIncome: Income?
    @State private var editingStock: Stock?
    @State private var showPremiumAlert = false
    @State private var showDisableConfirm = false
    // [v25.368] 卡號／到期日／檢核碼的解鎖狀態。只活在這個畫面上，離開就沒了。
    @State private var cardRevealed = false
    @State private var cardRevealNumber = ""
    @State private var cardRevealCode = ""
    @State private var cardRevealBusy = false
    @State private var cardRevealMessage: String?
    /// 解鎖後自動上鎖的倒數；換頁或再次解鎖都會取消重來
    @State private var cardRelockTask: Task<Void, Never>?

    private var item: LifeMilestone {
        lifeStore.milestones.first(where: { $0.id == milestoneId })
            ?? LifeMilestone(title: "", category: .achievement)
    }

    private var sub: FinanceSubCategory { item.financeSubCategory ?? .bank }

    /// [v25.563] 一套數字（LifeStore 快取；資料沒變不重算）。一個 section 裡用好幾次就先抓進區域常數
    private var facts: WealthFacts { lifeStore.wealthFacts(expense: expenseStore, finance: financeStore) }
    /// 這個銀行帳戶／證券戶（不是銀行、證券是 nil）
    private var account: WealthFacts.Account? { facts.account(milestoneId) }
    /// 這張信用卡（不是卡是 nil）
    private var cardFacts: WealthFacts.Card? { facts.card(milestoneId) }

    private var color: Color {
        switch sub {
        case .bank: return .blue; case .creditCard: return .orange
        case .securities: return .green; case .insurance: return .purple
        }
    }

    /// [v25.562] 按了工具列的「刪除」：付費才問（沒付費照舊跳付費提示）。字由 LifeStore 數好（會動到幾張卡、幾筆、多少錢）
    private func requestDelete() {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        pendingDelete = lifeStore.financeDeletionImpact(item, finance: financeStore, expense: expenseStore)
    }

    /// [v25.562] 刪除改呼叫共用那支（LifeStore.deleteFinanceMilestone；履歷也是同一支）：
    /// 刪銀行，底下的卡變成沒有扣款帳戶（不再整張不見）；刪卡，[v25.563] 每一期帳單照它的扣款帳戶一期一筆留下
    /// （日期＝繳款截止日，還沒到的到那天照樣扣；存摺上今天、以後都不變）。
    /// 先關畫面、下一個 runloop 才寫 store（畫面還開著就刪，body 會拿空白的 item 重畫一次）；
    /// 三個 store 先抓進區域常數，async 閉包裡不碰 @EnvironmentObject。
    private func performDelete(_ target: LifeMilestone) {
        let life = lifeStore
        let fin = financeStore
        let exp = expenseStore
        dismiss()
        DispatchQueue.main.async {
            life.deleteFinanceMilestone(target, finance: fin, expense: exp)
        }
    }

    /// [v25.562] 不是 .active（叫出 App 切換器、回主畫面、下拉控制中心、來電）就把號碼收回。
    /// 布幕在這一頁一律掛著（judge §7.1：卡片頁的銀行名、卡名、金額在 App 切換器也要蓋住；§9-14：在財富卡片頁就蓋），
    /// 不只解開號碼的時候——所以 lockCard() 把 cardRevealed 收成 false 也不會讓布幕跟著消失。
    /// ⚠️ Face ID 視窗出來那一刻也是 .inactive：那時還沒解開（cardRevealed 是 false），lockCard() 只是再收一次；
    ///    toggleCardReveal() 的 Task 驗證通過才設 cardRevealed = true，不受影響（這裡不取消那個 Task）。
    ///    Face ID 視窗後面會短暫看到布幕，回到 .active 就拿掉。
    private func handleScenePhase(_ phase: ScenePhase) {
        if phase != .active { lockCard() }
    }

    /// [v25.562] Face ID 解不開時說明框的標題：銀行、證券、保險頁也走同一顆鈕，標題別寫「卡號」
    private var cardRevealAlertTitle: String {
        sub == .creditCard ? "卡號與安全資訊" : "號碼與安全資訊"
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
                    // [v25.559] 信用卡說明照片（在「編輯」裡加）
                    if sub == .creditCard, let photos = item.photoFileNames, !photos.isEmpty {
                        cardPhotoCard(photos)
                    }
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
                            requestDelete()
                        } label: { Text("刪除").foregroundStyle(.red) }
                    }
                }
            }
            .sheet(isPresented: $showEdit) { AddMilestoneView(editing: item).appStores() }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .sheet(item: $viewingLinkedCard) { card in
                FinanceCardView(milestoneId: card.id)
                    .appStores()
            }
            .sheet(item: $addingDeposit) { request in
                DepositEditorSheet(milestoneId: milestoneId, currency: request.currency, editing: nil)
                    .appStores()
            }
            .sheet(item: $editingDeposit) { dep in
                DepositEditorSheet(milestoneId: milestoneId, currency: dep.currencyCode, editing: dep)
                    .appStores()
            }
            // [v25.563] 疊在卡片頁上的表單也蓋住（帳戶名、金額；App 切換器看得到的是最上面這張）
            .sheet(item: $editingExpense) { exp in
                AddExpenseView(expenseType: exp.expenseType, editingExpense: exp)
                    .modifier(WealthPrivacyCurtain(armed: true))
                    .appStores()
            }
            .sheet(item: $editingIncome) { inc in
                AddIncomeView(editing: inc)
                    .modifier(WealthPrivacyCurtain(armed: true))
                    .appStores()
            }
            .sheet(item: $editingStock) { stk in
                AddStockView(editing: stk)
                    .modifier(WealthPrivacyCurtain(armed: true))
                    .appStores()
            }
            // [v25.562] 刪除確認框（跟履歷同一個）：還在用的卡〔改成停用〕〔仍要刪除〕〔取消〕；其他〔刪除〕〔取消〕
            .modifier(FinanceDeleteAlert(
                pending: $pendingDelete,
                onDisable: { _ in toggleCardDisabled(true) },
                onDelete: { target in performDelete(target) }
            ))
            // [v25.368] 卡號解鎖的說明／錯誤（[v25.562] 標題依頁面：卡「卡號與安全資訊」、其他「號碼與安全資訊」）
            .alert(cardRevealAlertTitle, isPresented: Binding(
                get: { cardRevealMessage != nil },
                set: { if !$0 { cardRevealMessage = nil } }
            )) {
                Button("好") { cardRevealMessage = nil }
            } message: {
                Text(cardRevealMessage ?? "")
            }
            // 離開這一頁就上鎖：解鎖狀態不該留到下次進來
            .onDisappear { lockCard() }
        }
        // [v25.562] 切到背景：號碼收回＋布幕（sheet 要自己蓋，掛在 App 最外層蓋不到這裡）。
        // 卡片頁一律蓋（judge §7.1、§9-14），不只解開號碼的時候
        .onChange(of: scenePhase) { _, phase in handleScenePhase(phase) }
        .modifier(WealthPrivacyCurtain(armed: true))
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
    /// 【美化 v25.61】headerCard 三分支（creditCardHeader／bankPassbookHeader／defaultHeader）補齊立體感一致性：
    /// 另兩支 case 卡片外層都已有 stroke(黑 0.06~white 0.15) + shadow(黑 0.12~0.18)，唯獨本 case（股票／保險，最常見的一支）
    /// 原本平貼無邊框無陰影。已補上與 bankPassbookHeader 相同的中性描邊 + 陰影（同樣立於 systemBackground、非彩色漸層卡）。
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
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, y: 3)
        .padding(.horizontal)
    }

    // MARK: - [v25.368] 卡號解鎖

    private var cardRevealIcon: String {
        if cardRevealBusy { return "hourglass" }
        return cardRevealed ? "eye.slash.fill" : "eye.fill"
    }

    /// 橫幅上的卡號。字串在 ViewBuilder 外組好再進 Text（本專案有型別檢查逾時的前科）。
    private func cardBannerNumber(last4: String) -> String {
        guard cardRevealed, !cardRevealNumber.isEmpty else {
            return "•••• •••• •••• " + last4
        }
        return CardVault.grouped(cardRevealNumber).replacingOccurrences(of: "-", with: " ")
    }

    private var cardBannerExpiry: String {
        guard let ed = item.expiryDate else { return "" }
        return cardRevealed ? fmtMonthYear(ed) : "••/••"
    }

    private var cardDetailNumber: String {
        guard cardRevealed, !cardRevealNumber.isEmpty else {
            return CardVault.masked(lastFour: item.cardLastFour ?? "")
        }
        return CardVault.grouped(cardRevealNumber)
    }

    private var cardDetailExpiry: String {
        guard let ed = item.expiryDate else { return "未填" }
        return cardRevealed ? fmtYearMonthZh(ed) : "••••／••"
    }

    /// 一卡通卡號顯示用分組。含數字以外字元的舊資料原樣顯示，不自作主張改寫。
    private func displayIPass(_ raw: String) -> String {
        guard CardVault.isSafeToRegroup(raw) else { return raw }
        return CardVault.grouped(raw, limit: CardVault.iPassDigits)
    }

    /// [v25.562] 一卡通：沒解開只露後 4 碼；解開照舊分組顯示
    private func iPassDisplay(_ raw: String) -> String {
        cardRevealed ? displayIPass(raw) : CardVault.maskedTail(raw)
    }

    /// 這張卡有沒有需要鎖起來的東西。只有到期日的舊卡也算——
    /// 不然它的到期日會被遮起來卻沒有任何地方可以解鎖。
    /// [v25.562] 悠遊卡、一卡通、Happy Go 號碼也只露後 4 碼，有填就要有這顆眼睛
    private var cardHasProtectedFields: Bool {
        let hasLocked = item.cardNumberCipher != nil || item.cardSecurityCipher != nil || item.expiryDate != nil
        let tickets: [String?] = [item.easyCardNumber, item.iPassNumber, item.happyGoNumber]
        let hasTicket = tickets.contains { !($0 ?? "").isEmpty }
        return hasLocked || hasTicket
    }

    /// [v25.562] Face ID 視窗上的說明字：銀行、證券、保險也用同一顆鈕解開（一頁只有一種）
    private var cardRevealReason: String {
        switch sub {
        case .creditCard: return "檢視完整卡號與到期日"
        case .bank, .securities: return "檢視完整帳號"
        case .insurance: return "檢視完整保單號碼"
        }
    }

    /// [v25.562] 帳號、保單號碼、票證號碼：沒解開只露後 4 碼（「•••• 7890」），解開才整串
    private func revealedOrMasked(_ raw: String) -> String {
        cardRevealed ? raw : CardVault.maskedTail(raw)
    }

    /// [v25.562] 號碼列尾的眼睛（存摺頭、帳號、保單號碼）：跟卡號同一顆 Face ID、30 秒或切背景收回
    private func revealEyeButton(tint: Color) -> some View {
        Button {
            toggleCardReveal()
        } label: {
            Image(systemName: cardRevealIcon)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(cardRevealBusy)
        .accessibilityLabel(cardRevealed ? "隱藏完整號碼" : "顯示完整號碼")
    }

    /// [v25.562] 資訊卡上要遮的一列（帳號、保單號碼）：值只露後 4 碼＋列尾眼睛
    private func revealInfoRow(_ label: String, raw: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(revealedOrMasked(raw)).font(.subheadline)
            revealEyeButton(tint: color)
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    private func toggleCardReveal() {
        if cardRevealed { lockCard(); return }
        guard !cardRevealBusy else { return }
        cardRevealBusy = true
        let reason = cardRevealReason
        Task { @MainActor in
            defer { cardRevealBusy = false }
            switch await CardVault.unlock(reason: reason) {
            case .ok:
                let number = CardVault.open(item.cardNumberCipher) ?? ""
                // 有密文卻解不出來＝金鑰不在這台裝置；沒有密文（只鎖到期日）則本來就沒東西可解
                if item.cardNumberCipher != nil, number.isEmpty {
                    cardRevealMessage =
                        "這台裝置沒有解密金鑰，看不到原本存的卡號。"
                        + "金鑰是透過 iCloud 鑰匙圈同步的，請確認「設定 → Apple ID → iCloud → 密碼與鑰匙圈」已開啟；"
                        + "若金鑰已經遺失，請到編輯畫面重新輸入一次完整卡號。"
                }
                cardRevealNumber = number
                cardRevealCode = CardVault.open(item.cardSecurityCipher) ?? ""
                cardRevealed = true
                scheduleRelock()
            case .denied:
                break
            case .unavailable(let message):
                cardRevealMessage = message
            }
        }
    }

    /// 看完 30 秒自動收回去，免得解鎖後把手機放著就等於沒鎖
    private func scheduleRelock() {
        cardRelockTask?.cancel()
        cardRelockTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            lockCard()
        }
    }

    private func lockCard() {
        cardRelockTask?.cancel()
        cardRelockTask = nil
        cardRevealed = false
        cardRevealNumber = ""
        cardRevealCode = ""
    }

    /// 信用卡樣式（仿真實信用卡 banner）
    private var creditCardHeader: some View {
        let disabled = item.isDisabled == true
        let cardName = item.cardName.flatMap { $0.isEmpty ? nil : $0 } ?? item.title
        let last4 = item.cardLastFour ?? "----"
        // [v25.562] 跟「上期帳單」那一列同一支（bankName 空白時用銀行的 title，以前卡面會整個不寫銀行名）
        let bankName: String? = linkedBankName
        let gradient: [Color] = disabled
            ? [Color(white: 0.55), Color(white: 0.30)]
            : [Color(red: 0.95, green: 0.55, blue: 0.20),
               Color(red: 0.75, green: 0.30, blue: 0.10)]

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if let bn = bankName, !bn.isEmpty {
                        // [v25.520] 銀行名放不下改跑馬燈（原本折成多行，把卡面撐歪）
                        MarqueeText(bn)
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

            // 卡號：預設只露末四碼，要看完整的必須先過 Face ID／密碼
            HStack(spacing: 10) {
                Text(cardBannerNumber(last4: last4))
                    .font(.title3.weight(.semibold).monospaced())
                    .tracking(2)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if cardHasProtectedFields {
                    Button {
                        toggleCardReveal()
                    } label: {
                        Image(systemName: cardRevealIcon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .disabled(cardRevealBusy)
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CARD HOLDER").font(.system(size: 9)).tracking(1.5)
                        .foregroundStyle(.white.opacity(0.7))
                    MarqueeText(cardName.uppercased())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                if !cardRevealCode.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("CVV").font(.system(size: 9)).tracking(1.5)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(cardRevealCode)
                            .font(.subheadline.weight(.semibold).monospaced())
                            .foregroundStyle(.white)
                    }
                }
                if item.expiryDate != nil {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("VALID THRU").font(.system(size: 9)).tracking(1.5)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(cardBannerExpiry)
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
                    passbookRevealRow(acc)
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

    /// [v25.562] 存摺頭的帳號：只露後 4 碼（「•••• 7890」），列尾眼睛按了要 Face ID
    private func passbookRevealRow(_ raw: String) -> some View {
        HStack {
            Text("帳號").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(revealedOrMasked(raw)).font(.subheadline.weight(.medium).monospaced())
            revealEyeButton(tint: .blue)
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
        // [v25.563] 一顆眼睛：帳號跟著存摺頭那顆眼睛一起露、一起收（這一列不再有自己的眼睛）
        if let a = item.accountNumber, !a.isEmpty { infoRow("帳號", revealedOrMasked(a)) }
        if let t = item.bankAccountType { infoRow("帳戶類型", t.rawValue) }
        infoRow("開戶日期", fmtDate(item.date))
    }

    // MARK: - [v25.563] 信用卡：要繳／還沒出帳／還能刷（一套數字 WealthFacts.Card；名詞照 judge §3.15）

    /// 額度之後那幾列（有沒有額度都要）：要繳（或剛扣完的上期帳單）、還沒出帳、還能刷＋長條、卡費從哪扣
    @ViewBuilder
    private func cardMoneyRows(_ cf: WealthFacts.Card) -> some View {
        if cf.due > 0.004 {
            infoRow("要繳", cardDueText(cf))
        } else if let lp = cf.lastPaid, WealthCal.days(from: lp.due, to: Date()) <= 45 {
            infoRow("上期帳單", cardLastPaidText(lp))
        }
        infoRow("還沒出帳", cardUnbilledText(cf))
        if let avail = cf.available {
            infoRow("還能刷", avail.ntdWanString)
            cardUsageBar(cf)
        }
        infoRow("卡費從哪扣", cardPayerText(cf))
    }

    /// 「NT$18,600（10/27 截止）」
    private func cardDueText(_ cf: WealthFacts.Card) -> String {
        let amount = WealthFormat.ntd(cf.due)
        guard let st = cf.dueStatement else { return amount }
        return amount + "（" + WealthFormat.monthDay(st.due) + " 截止）"
    }

    /// 「NT$6,200（11/12 結帳）」（0 也寫「NT$0（11/12 結帳）」）
    private func cardUnbilledText(_ cf: WealthFacts.Card) -> String {
        let amount = WealthFormat.ntd(cf.unbilled)
        let close = WealthFormat.monthDay(cf.nextClose)
        return amount + "（" + close + " 結帳）"
    }

    /// 「NT$19,400・10/10 已從台新銀行扣 ✓」；那一期沒有扣款帳戶「NT$19,400・10/10 已到截止日」
    private func cardLastPaidText(_ st: WealthStatement) -> String {
        let head = WealthFormat.ntd(st.amount) + "・" + WealthFormat.monthDay(st.due)
        if let name = facts.account(st.payerId)?.name {
            return head + " 已從" + name + "扣 ✓"
        }
        return head + " 已到截止日"
    }

    /// 「台新銀行（截止日自動扣全額）」；沒設「還沒設（卡費不會從任何帳戶扣）」
    private func cardPayerText(_ cf: WealthFacts.Card) -> String {
        guard let name = cf.payerName else { return "還沒設（卡費不會從任何帳戶扣）" }
        return name + "（截止日自動扣全額）"
    }

    /// 還能刷底下的長條＋小字「額度用了 8.3%・很寬鬆」。長條不用紅綠（judge §3.16 使用率四段色）
    private func cardUsageBar(_ cf: WealthFacts.Card) -> some View {
        let ratio: Double = Swift.min(1, Swift.max(0, cf.usage ?? 0))
        let tint: Color = Self.usageColor(tier: cf.usageTier)
        let caption: String? = cf.usageText
        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill)).frame(height: 8)
                    Capsule().fill(tint).frame(width: Swift.max(4, geo.size.width * CGFloat(ratio)), height: 8)
                }
            }
            .frame(height: 8)
            if let c = caption {
                Text(c).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal).padding(.vertical, 6)
    }

    /// judge §3.16「使用率」：很寬鬆／正常／偏高／快刷滿了，淺色、深色各一組
    private static func usageColor(tier: Int) -> Color {
        let light: UInt32
        let dark: UInt32
        switch tier {
        case 0: light = 0x6B7FA3; dark = 0x9FB0D0
        case 1: light = 0xB98500; dark = 0xFFD166
        case 2: light = 0xD9731A; dark = 0xFF9F4D
        default: light = 0xB34A00; dark = 0xFF7A33
        }
        let lightColor = rgbColor(light)
        let darkColor = rgbColor(dark)
        return Color(UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        }))
    }

    private static func rgbColor(_ hex: UInt32) -> UIColor {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    /// 「每月 12 日」；沒填「沒填（先當每月 25 日）」（舊資料打錯的 0、45 照算的寫：夾到 1–31）
    private var cardBillingDayText: String {
        if let cf = cardFacts {
            return cf.billingDayMissing ? "沒填（先當每月 \(cf.billingDay) 日）" : "每月 \(cf.billingDay) 日"
        }
        guard let bd = item.billingDay else { return "沒填（先當每月 \(WealthCardCycle.defaultBillingDay) 日）" }
        return "每月 \(bd) 日"
    }

    /// 「每月 27 日」；沒填「沒填（先當每月 15 日）」
    private var cardPaymentDayText: String {
        if let cf = cardFacts {
            return cf.paymentDayMissing ? "沒填（先當每月 \(cf.paymentDay) 日）" : "每月 \(cf.paymentDay) 日"
        }
        guard let pd = item.paymentDay else { return "沒填（先當每月 \(WealthCardCycle.defaultPaymentDay) 日）" }
        return "每月 \(pd) 日"
    }

    /// [v25.562] 扣卡費的銀行名（沒設、或那個銀行已經刪掉＝nil）——卡面用
    private var linkedBankName: String? {
        guard let bid = item.linkedBankMilestoneId,
              let b = lifeStore.milestones.first(where: { $0.id == bid }) else { return nil }
        return b.bankName.flatMap { $0.isEmpty ? nil : $0 } ?? b.title
    }

    @ViewBuilder
    private var creditCardDetail: some View {
        if let c = item.cardName, !c.isEmpty { infoRow("卡別", c) }
        // [v25.368] 卡號：有存完整卡號就整串顯示（預設遮罩），沒存就沿用末四碼
        if item.cardNumberCipher != nil {
            Button {
                toggleCardReveal()
            } label: {
                HStack {
                    Text("卡號").foregroundStyle(.secondary)
                    Spacer()
                    Text(cardDetailNumber)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.primary)
                    Image(systemName: cardRevealIcon)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .font(.subheadline)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(cardRevealBusy)
            if !cardRevealCode.isEmpty { infoRow("檢核碼", cardRevealCode) }
        } else if let l = item.cardLastFour, !l.isEmpty {
            infoRow("卡號末四碼", l)
        }
        if let cl = item.creditLimit, cl > 0 {
            infoRow("額度", cl.ntdWanString)
        }
        // [v25.563] 要繳／還沒出帳／還能刷／卡費從哪扣（有沒有額度都要；沒額度就沒有還能刷）
        if let cf = cardFacts { cardMoneyRows(cf) }
        if let af = item.annualFee, af > 0 { infoRow("年費", af.ntdWanString) }
        infoRow("結帳日", cardBillingDayText)
        infoRow("繳款截止日", cardPaymentDayText)
        infoRow("核卡日期", fmtDate(item.date))
        // [v25.368] 到期日與卡號同一把鎖，沒解鎖只顯示遮罩
        if item.expiryDate != nil { infoRow("到期日", cardDetailExpiry) }
        // [v25.562] 悠遊卡、一卡通、Happy Go 只露後 4 碼，跟卡號同一顆 Face ID（卡面那顆眼睛）
        if let ec = item.easyCardNumber, !ec.isEmpty { infoRow("悠遊卡", revealedOrMasked(ec)) }
        // [v25.369] 舊資料沒有分隔線；顯示時就分好組，不用等使用者重存一次
        if let ip = item.iPassNumber, !ip.isEmpty { infoRow("一卡通", iPassDisplay(ip)) }
        if let hg = item.happyGoNumber, !hg.isEmpty { infoRow("Happy Go", revealedOrMasked(hg)) }
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
        if let a = item.accountNumber, !a.isEmpty { revealInfoRow("帳號", raw: a) }
        if let t = item.securitiesAccountType { infoRow("帳戶類型", t.rawValue) }
        infoRow("開戶日期", fmtDate(item.date))
    }

    @ViewBuilder
    private var insuranceDetail: some View {
        if let co = item.insuranceCompany, !co.isEmpty { infoRow("保險公司", co) }
        if let pn = item.policyNumber, !pn.isEmpty { revealInfoRow("保單號碼", raw: pn) }
        if let it = item.insuranceType { infoRow("險種", it.rawValue) }
        if let pa = item.premiumAmount, pa > 0 { infoRow("保費", pa.ntdWanString) }
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

    /// [v25.559] 信用卡說明照片：只看不改（點縮圖看大圖、PDF 用 PDF 檢視器；加、刪在「編輯」裡）
    private func cardPhotoCard(_ photos: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MultiPhotoGallery(
                fileNames: .constant(photos),
                urlFor: { LifeMilestone.photoURL(for: $0) },
                onSaveImage: { _ in nil },
                onDeleteFile: { _ in },
                title: "信用卡說明",
                allowAdding: false
            )
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
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()

    private func fmtDate(_ date: Date) -> String {
        Self.fmtDateFormatter.string(from: date)
    }
    // [v25.563] fmtNum 拿掉了：明細、存摺上的金額都用 WealthFormat（WealthLedgerRow.amountText／balanceText）

    // MARK: - 銀行存款章節（[v25.563] 明細改讀一套數字：account.ledger）

    /// 標題列：Capsule 側條 + 計數膠囊 + 新增選單（對齊 OverviewView categoryBreakdownSection 規格）
    private func depositSectionHeader(count: Int) -> some View {
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
            if count > 0 {
                Text("\(count) 筆")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.blue.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.blue.opacity(0.22), lineWidth: 0.75))
            }
            Menu {
                Button { addingDeposit = AddDepositRequest(currency: "NT$") } label: {
                    Label("台幣", systemImage: "dollarsign")
                }
                ForEach(expenseStore.currencyRates) { rate in
                    Button { addingDeposit = AddDepositRequest(currency: rate.code) } label: {
                        Label(rate.code, systemImage: "coloncurrencysign")
                    }
                }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    /// 明細：今天以前、新到舊（judge §8 v2：明細不放未來的列；卡費一期一列；每列餘額）。
    /// 銀行而且只有一個幣別才畫長條圖（好幾個幣別 v3 改水位）；證券戶不畫圖、不寫目前總額（D16）
    private var depositSection: some View {
        let acct = account
        let rows: [WealthLedgerRow] = acct?.ledger ?? []
        let isSecurities = sub == .securities
        let visible: [WealthLedgerRow] = depositsExpanded ? rows : Array(rows.prefix(6))
        return VStack(alignment: .leading, spacing: 0) {
            depositSectionHeader(count: rows.count)

            if rows.isEmpty {
                Text("尚無存款記錄").font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 16).padding(.bottom, 14)
            } else {
                if !isSecurities, let a = acct {
                    if let code = a.singleCode {
                        depositChart(rows: rows, code: code)
                            .padding(.horizontal).padding(.bottom, 4)
                    }
                    passbookTotalLine(a)
                        .padding(.horizontal).padding(.bottom, 8)
                }

                LazyVStack(spacing: 0) {
                    ForEach(visible) { row in
                        depositRow(row, showsBalance: !isSecurities)
                    }
                }
                if rows.count > 6 {
                    Button {
                        withAnimation { depositsExpanded.toggle() }
                    } label: {
                        HStack {
                            Spacer()
                            Text(depositsExpanded ? "收起" : "展開全部 (\(rows.count) 筆)")
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

    /// 圖下面那一行：「存摺上　NT$128,400」（以前叫「目前總額」；負的紅）
    private func passbookTotalLine(_ a: WealthFacts.Account) -> some View {
        let negative: Bool = {
            if let c = a.singleCode { return a.balance(c) < -0.004 }
            return a.ntdTotal < -0.004
        }()
        return HStack {
            Text("存摺上").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(a.balanceText)
                .font(.caption.bold())
                .foregroundStyle(negative ? Color.red : Color.blue)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 信用卡圖表章節（顯示於信用卡卡片）

    /// 消費趨勢：每筆消費一根柱子；同日的合併為一根
    private struct CreditCardDailyTotal: Identifiable {
        let id: String
        let date: Date
        let amount: Double
    }

    /// 接收呼叫端（creditCardChartSection）已拿好的 entries（[v25.563] 一套數字的 cardFacts.entries，
    /// 定期扣款每一期一筆、期數一次算、金額照當時，台幣）
    private func creditCardDailyTotals(_ entries: [WealthCardEntry]) -> [CreditCardDailyTotal] {
        // 同一天＝一套數字的日曆（西曆、手機時區）：手機設成佛曆也不會分錯天
        let groups = Dictionary(grouping: entries) { entry -> String in
            WealthCal.dayKey(entry.date)
        }
        return groups.compactMap { (key, list) -> CreditCardDailyTotal? in
            guard let first = list.first else { return nil }
            let total = list.reduce(0.0) { $0 + $1.amount }
            return CreditCardDailyTotal(id: key, date: first.date, amount: total)
        }
        .sorted { $0.date < $1.date }
    }

    @State private var ccExpanded = false

    /// 信用卡個別項目列表的一列。
    /// 週期性固定支出會展開成每期一列，所以「一列」不等於「一筆 Expense」——
    /// 五月設定的月繳訂閱在六、七、八月各有一列，但它們指向同一筆 Expense。
    private struct CreditCardExpenseRow: Identifiable {
        let id: String
        let date: Date
        let amount: Double
        let expense: Expense
        /// 由週期自動展開出來的期別（非使用者手動記的那一筆）
        let isProjected: Bool
    }

    /// ⚠️ 這份清單以前直接列 expenseStore.expenses，週期性固定支出只會出現「原始設定」
    ///    那一筆——五月設定的月繳訂閱，六、七、八月完全看不到，看起來像漏帳。改成同樣展開。
    /// [v25.563] entries 是一套數字的 cardFacts.entries（id 固定：「cc-<支出>-<k>」，每次開 App 都一樣）
    private func creditCardExpenseRows(_ entries: [WealthCardEntry]) -> [CreditCardExpenseRow] {
        let byId = Dictionary(expenseStore.expenses.map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first })
        var rows: [CreditCardExpenseRow] = []
        for e in entries {
            guard let exp = byId[e.expenseId] else { continue }
            rows.append(CreditCardExpenseRow(id: e.id, date: e.date, amount: e.amount,
                                             expense: exp, isProjected: e.isRecurring))
        }
        return rows.sorted { $0.date > $1.date }
    }

    /// 「最近一期」：要繳的那一期；沒有就最近一期已經扣的（「10 月帳單」「NT$18,600」）
    private func latestStatementLine(_ cf: WealthFacts.Card?) -> (label: String, amount: String)? {
        guard let st = cf?.dueStatement ?? cf?.lastPaid else { return nil }
        return (st.label, WealthFormat.ntd(st.amount))
    }

    private var creditCardChartSection: some View {
        // [v25.563] 一套數字的 entries（快取），圖、最近一期、清單三處共用
        let cf = cardFacts
        let entries: [WealthCardEntry] = cf?.entries ?? []
        let dailyTotals = creditCardDailyTotals(entries)
        let latest = latestStatementLine(cf)
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

                // [v25.563] 最近一期＝要繳的那一期（沒有就最近扣過的）：「10 月帳單　NT$18,600」
                if let line = latest {
                    HStack {
                        Text(line.label).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(line.amount).font(.caption.bold())
                    }
                    .padding(.horizontal).padding(.bottom, 6)
                }

                Divider().padding(.horizontal)

                // 個別項目列表
                let items = creditCardExpenseRows(entries)
                let visible = ccExpanded ? items : Array(items.prefix(6))
                // 信用卡個別支出列：32pt 漸層圖示圓 + 日期 Capsule 徽章 + 金額 rounded bold
                // 對齊 depositRow 視覺語言，形成帳戶詳頁統一 row 規格
                ForEach(visible) { row in
                    // 展開出來的期別點下去編輯的是同一筆原始 Expense
                    Button { editingExpense = row.expense } label: {
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
                                Image(systemName: row.expense.categoryIcon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.orange)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                MarqueeText(row.expense.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                // 日期 Capsule 徽章
                                HStack(spacing: 4) {
                                    Text(fmtDate(row.date))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color(.tertiarySystemFill))
                                        .clipShape(Capsule())
                                    // 標示這一列是週期自動展開的期別，不是另外記的一筆帳，
                                    // 否則使用者會以為同一筆訂閱被重複輸入了四次。
                                    if row.isProjected {
                                        Text("週期")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.orange)
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                }
                            }

                            Spacer(minLength: 4)

                            VStack(alignment: .trailing, spacing: 3) {
                                Text("-\(row.amount.ntdWanString)")
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


    @ViewBuilder
    private func creditCardChart(_ dailyTotals: [CreditCardDailyTotal]) -> some View {
        // [v25.317] 分頁式改為共用趨勢模板壓縮法（頭尾真實、中間分桶平均，見 depositChart）
        let sampled = HeroTrendSeries.compressKeepingEnds(
            dailyTotals, maxCount: 30,
            date: { $0.date }, value: { $0.amount },
            make: { d, v, rep in CreditCardDailyTotal(id: "avg-\(rep.id)", date: d, amount: v) }
        )
        Group {
            if sampled.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    creditCardChartPage(data: sampled)
                        .frame(height: 150)
                    if dailyTotals.count > sampled.count {
                        Text("已壓縮顯示：首末為真實值，中間為區段平均（共 \(dailyTotals.count) 筆）")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
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
                                    MarqueeText(card.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(disabled ? .secondary : .primary)
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

    /// [v25.563] 點明細一列：開那一筆的來源。卡費 → 那張卡；股票交割、股利 → 股票；
    /// 記帳一次性、固定支出 → 那筆記帳；收入、月薪 → 那筆收入；財富頁自己記的（存提款、對存摺、轉帳、利息）→ 存提款表單
    private func handleDepositTap(_ row: WealthLedgerRow) {
        if let cid = row.cardId {
            if let card = lifeStore.milestones.first(where: { $0.id == cid }) { viewingLinkedCard = card }
            return
        }
        if let sid = row.stockId, let stock = financeStore.stocks.first(where: { $0.id == sid }) {
            editingStock = stock
            return
        }
        if let eid = row.expenseId, let exp = expenseStore.expenses.first(where: { $0.id == eid }) {
            editingExpense = exp
            return
        }
        if let iid = row.incomeId, let inc = expenseStore.incomes.first(where: { $0.id == iid }) {
            editingIncome = inc
            return
        }
        if let did = row.depositId, let dep = item.bankDeposits?.first(where: { $0.id == did }) {
            editingDeposit = dep
        }
    }

    // MARK: - depositRow（v2 美化；[v25.563] 改畫一套數字的 WealthLedgerRow）
    // 【美化方向】36pt 漸層圖示圓（依種類分色）；Badge 為 Capsule + 細邊框；備註文字顯示；
    //   金額 .system(size:15, weight:.bold, design:.rounded) + contentTransition；
    //   [v25.563] 銀行每一列底下小字「餘額 NT$128,400」（跟存摺一樣一列一列對得上）；對存摺那列寫「差 0」

    /// 徽章、圖示圓的顏色：對存摺／以前的沖正 indigo、股票 purple、卡費 orange、轉帳 blue、其他出去 red、進來 green
    private func ledgerTint(_ row: WealthLedgerRow) -> Color {
        switch row.kind {
        case .anchor, .legacyAdjust: return .indigo
        case .stockBuy, .stockSell, .dividend: return .purple
        case .cardBill: return .orange
        case .transferOut, .transferIn: return .blue
        default: return row.isOutflow ? .red : .green
        }
    }

    private func ledgerIcon(_ row: WealthLedgerRow) -> String {
        switch row.kind {
        case .anchor: return "checkmark.seal.fill"
        case .legacyAdjust: return "arrow.2.circlepath"
        case .cardBill: return "creditcard.fill"
        case .transferOut, .transferIn: return "arrow.left.arrow.right"
        case .stockBuy: return "chart.line.downtrend.xyaxis"
        case .stockSell, .dividend: return "chart.line.uptrend.xyaxis"
        default: return row.isOutflow ? "minus.circle.fill" : "plus.circle.fill"
        }
    }

    /// 右邊金額的顏色：對存摺 indigo、卡費 orange、出去 red、進來 green
    private func ledgerAmountColor(_ row: WealthLedgerRow) -> Color {
        switch row.kind {
        case .anchor: return .indigo
        case .cardBill: return .orange
        default: return row.isOutflow ? .red : .green
        }
    }

    /// 徽章後面的標題（「@GoGo 9 月帳單」「中華電信」「轉給 國泰世華」「買 0050」）；跟徽章一樣（存款、提款、對存摺…）就不寫
    private func ledgerTitle(_ row: WealthLedgerRow) -> String? {
        let t = row.title.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t == row.kind.badge { return nil }
        return t
    }

    /// 金額底下那行小字：對存摺「差 0」「差 +NT$120」「差 -美金 3.00」；銀行其他列「餘額 NT$128,400」；證券戶不寫
    private func ledgerSubText(_ row: WealthLedgerRow, showsBalance: Bool) -> String? {
        if row.kind == .anchor {
            let d = row.anchorDiff ?? 0
            if Swift.abs(d) < 0.005 { return "差 0" }
            let amt = WealthFormat.money(d, code: row.code)
            return "差 " + (d > 0 ? "+" + amt : amt)
        }
        return showsBalance ? row.balanceText : nil
    }

    private func depositRow(_ row: WealthLedgerRow, showsBalance: Bool) -> some View {
        let tint = ledgerTint(row)
        let icon = ledgerIcon(row)
        let title: String? = ledgerTitle(row)
        let note: String? = row.note.flatMap { $0.isEmpty ? nil : $0 }
        let subText: String? = ledgerSubText(row, showsBalance: showsBalance)
        return Button {
            handleDepositTap(row)
        } label: {
            HStack(spacing: 12) {
                ledgerIconCircle(icon: icon, tint: tint)

                // 主文字區：Badge 膠囊 + 標題、備註、日期
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        ledgerBadge(row.kind.badge, tint: tint)
                        if let t = title {
                            Text(t)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                    if let n = note {
                        Text(n)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    // 日期：小型 Capsule 徽章
                    Text(fmtDate(row.date))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 4)

                // 金額 + 餘額（或差多少）+ chevron
                VStack(alignment: .trailing, spacing: 3) {
                    Text(row.amountText)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(ledgerAmountColor(row))
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let s = subText {
                        Text(s)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
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

    /// 36pt 漸層圖示圓
    private func ledgerIconCircle(icon: String, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.20), tint.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)
            Circle()
                .stroke(tint.opacity(0.20), lineWidth: 0.75)
                .frame(width: 36, height: 36)
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    /// 徽章膠囊（存款／提款／卡費／買入／賣出／股利／對存摺…）
    private func ledgerBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(tint.opacity(0.10))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.22), lineWidth: 0.6))
    }

    /// 長條圖的點：明細反過來（舊到新）、只取這個幣別，每一列之後的存摺上
    private func depositChartPoints(rows: [WealthLedgerRow], code: String) -> [(date: Date, balance: Double, id: String)] {
        var points: [(date: Date, balance: Double, id: String)] = []
        for row in rows.reversed() where WealthFacts.norm(row.code) == WealthFacts.norm(code) {
            points.append((date: row.date, balance: row.balanceAfter, id: row.id))
        }
        return points
    }

    /// [v25.563] 存摺上的走勢（只有一個幣別的銀行才畫；好幾個幣別 v3 改水位）。
    /// 每一根＝那一列之後的存摺上（一套數字算好的，對存摺那天就是存摺上的數字）
    private func depositChart(rows: [WealthLedgerRow], code: String) -> some View {
        let points = depositChartPoints(rows: rows, code: code)
        // [v25.317] 共用趨勢模板的壓縮法：頭尾保留真實值、中間分桶平均壓到固定 30 根
        let sampled = HeroTrendSeries.compressKeepingEnds(
            points, maxCount: 30,
            date: { $0.date }, value: { $0.balance },
            make: { d, v, rep in (date: d, balance: v, id: rep.id) }
        )
        return VStack(alignment: .leading, spacing: 6) {
            if !sampled.isEmpty {
                depositChartPageView(sampled)
                    .frame(height: 150)
                if points.count > sampled.count {
                    Text("已壓縮顯示：首末為真實數字，中間為區段平均（共 \(points.count) 筆）")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    /// 單頁的長條圖：Y 軸最大 / 最小值依「本頁」資料自適應
    @ViewBuilder
    private func depositChartPageView(_ pageData: [(date: Date, balance: Double, id: String)]) -> some View {
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

/// 新增存款要用的幣別（每按一次就是新的一個，sheet(item:) 才會帶著這個幣別打開）
struct AddDepositRequest: Identifiable {
    let id = UUID()
    let currency: String
}

/// [v25.563] 刪一筆存提款紀錄先問：轉帳〔兩邊一起刪〕〔只刪這一筆〕〔取消〕；其他〔刪除〕〔取消〕。
/// 拆成 ViewModifier：表單 body 已經掛了 toolbar、task、onChange，再塞會讓型別檢查變慢（坑 #7）
fileprivate struct DepositDeleteAlert: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let isTransfer: Bool
    /// 參數：要不要兩邊一起刪
    let onDelete: (Bool) -> Void

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            if isTransfer {
                Button("兩邊一起刪", role: .destructive) { onDelete(true) }
                Button("只刪這一筆") { onDelete(false) }
            } else {
                Button("刪除", role: .destructive) { onDelete(false) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

/// [v25.563] 存款／提款／轉帳／對存摺（取代沖正；judge §4.5、§3.15）。
/// - 對存摺：打存摺上的數字（那天結束時）→ 一筆 BankDeposit(kind: anchor, anchorAmount:)，以後從這裡往後算；差額 0 也存。
///   amount／isWithdrawal 照寫差額：還沒更新的 iPad 存一次會丟掉 kind／anchorAmount，剩差額照加減，數字一樣（judge §9-3）
/// - 轉帳：兩邊各一筆、綁同一個 transferPairId（LifeStore.addTransfer）；一邊是台幣時可以改匯率；刪一筆問要不要兩邊一起刪
/// - 寫 store 一律先 dismiss、下一個 runloop 才寫（store 先抓進區域常數）
/// - 自己掛布幕：疊在財富卡片頁上，App 切換器看得到的是這一張（帳戶名、金額）
struct DepositEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    /// [v25.563] 一套數字（轉帳選單）、App 算的存摺上（對存摺）要股票的交割、股利
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    let milestoneId: UUID
    let currency: String
    var editing: BankDeposit?

    enum TransactionType: String, CaseIterable {
        case deposit = "存款"
        case withdrawal = "提款"
        case transfer = "轉帳"
        case adjust = "對存摺"
    }

    @State private var txType: TransactionType = .deposit
    @State private var date = Date()
    @State private var amountText = ""
    @State private var transferTargetId: UUID?
    /// 備註（存提款、轉帳）／差額原因（對存摺）
    @State private var adjustNote = ""
    @State private var isSaving = false
    /// 編輯時欄位只帶入一次（onAppear 再跑一次不蓋掉打到一半的）
    @State private var loaded = false
    /// 對存摺：App 算的「這個幣別那天結束時」的存摺上（只在打開、換日期、換類型時算；打字不算，judge §4.5）
    @State private var appBalance: Double?
    /// appBalance 是哪個「類型-日期-幣別」算的（對不上＝還沒算好，不給存）
    @State private var appBalanceKey = ""
    /// 轉帳：對方收哪個幣別
    @State private var transferCode: String = "NT$"
    /// 轉帳換匯：1 外幣＝幾台幣（一邊是台幣才可以改；預設設定裡的匯率）
    @State private var rateText = ""
    @State private var confirmDelete = false

    // MARK: 共用

    /// 一套數字（LifeStore 快取；打字不重算）
    private var facts: WealthFacts { lifeStore.wealthFacts(expense: expenseStore, finance: financeStore) }
    private var rates: FinanceRates { FinanceRates(expenseStore) }
    private var isEditingTransfer: Bool { editing?.isTransfer == true }
    private var isEditingAnchor: Bool { editing?.isAnchor == true }
    /// 以前記的沖正（沒有 kind）：照 v1 當存提款編輯，照舊當加減
    private var isLegacyAdjust: Bool { editing?.isAdjust == true && editing?.isAnchor != true }

    /// [v25.562] 編輯時金額帶回輸入框：四捨五入到 2 位小數再去尾 0、去尾「.」（123.45 → "123.45"、1200 → "1200"）。
    /// 以前用 "%.0f"，美金 123.45 打開直接存就變成 123。寫法同 RealEstateEditors.editableAmountText。
    private static func editableAmount(_ v: Double) -> String {
        let rounded: Double = (v * 100).rounded() / 100
        var s = String(format: "%.2f", rounded)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// 匯率帶回輸入框：4 位小數去尾 0（32.05 → "32.05"、0.215 → "0.215"）
    private static func rateString(_ r: Double) -> String {
        var s = String(format: "%.4f", r)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    // 【美化方向】存款/提款/轉帳/對存摺編輯 sheet Section header：4pt 漸層 Capsule 側條 + 圖示 + 粗體標題
    // （StockDetailView.stockEditorSectionHeader／RealEstateDetailView.realEstateEditorSectionHeader 同一套），
    // 主題色依語意分配（轉帳＝blue／對存摺＝orange／存款‧提款＝green）。
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

    // MARK: 轉帳

    /// 轉到哪：銀行帳戶（不含自己、收起來的；證券戶 v6 才加）
    private var transferTargets: [WealthFacts.Account] {
        facts.banks.filter { $0.id != milestoneId && !$0.hidden }
    }
    private var transferTarget: WealthFacts.Account? { facts.account(transferTargetId) }
    private var fromCode: String { WealthFacts.norm(currency) }
    private var toCode: String { WealthFacts.norm(transferCode) }
    /// 兩邊幣別不同、有一邊是台幣：可以改匯率（還沒選對方＝不出現：對方幣別還是預設的台幣，標題會寫錯）
    private var showsRateField: Bool {
        guard transferTargetId != nil, fromCode != toCode else { return false }
        return fromCode == "NT$" || toCode == "NT$"
    }
    /// 兩邊都是外幣、而且不同：用設定裡的匯率
    private var bothForeign: Bool {
        guard transferTargetId != nil, fromCode != toCode else { return false }
        return fromCode != "NT$" && toCode != "NT$"
    }
    /// 「匯率（1 美金＝幾台幣）」
    private var rateLabel: String {
        let foreign = fromCode == "NT$" ? toCode : fromCode
        return "匯率（1 \(foreign)＝幾台幣）"
    }
    /// 有打匯率但不是正數（空白＝用設定的）
    private var rateInvalid: Bool {
        guard showsRateField else { return false }
        let t = rateText.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return false }
        return (Double(t) ?? 0) <= 0
    }
    /// 用的匯率：一邊台幣＝打的（沒打用設定的）；同幣別、兩邊都外幣＝nil（兩邊都外幣用設定的兩個匯率）
    private var usedRate: Double? {
        guard showsRateField else { return nil }
        if let r = Double(rateText.trimmingCharacters(in: .whitespaces)), r > 0 { return r }
        return WealthFacts.defaultTransferRate(from: currency, to: transferCode, rates: rates)
    }

    /// 對方收到多少（對方的幣別；查不到匯率＝nil）
    private func transferToAmount(_ amount: Double) -> Double? {
        WealthFacts.transferAmount(amount, from: currency, to: transferCode, rate: usedRate, rates: rates)
    }

    /// 「對方收到 美金 1,560.06」；查不到匯率＝紅字、不給存；還沒選對方或沒打金額＝nil
    private var transferPreview: (text: String, ok: Bool)? {
        guard transferTargetId != nil, let amount = Double(amountText), amount > 0 else { return nil }
        guard let to = transferToAmount(amount) else {
            return ("設定裡找不到匯率，先到設定加這個幣別的匯率", false)
        }
        return ("對方收到 " + WealthFormat.money(to, code: toCode), true)
    }

    /// 換對方帳戶：對方有這邊的幣別就收同一個幣別，不然收對方第一個幣別（台幣在前）；匯率填設定裡的
    private func applyTransferTarget(_ id: UUID?) {
        guard let acc = facts.account(id) else { return }
        let codes = acc.currencies
        transferCode = codes.contains(fromCode) ? fromCode : (codes.first ?? "NT$")
        resetRate()
    }

    /// 匯率欄填設定裡的匯率（一邊台幣而且查得到才填；去尾 0）
    private func resetRate() {
        if let r = WealthFacts.defaultTransferRate(from: currency, to: transferCode, rates: rates) {
            rateText = Self.rateString(r)
        } else {
            rateText = ""
        }
    }

    /// 編輯一筆轉帳時的唯讀一行：「轉給 國泰世華・NT$40,000・9/25」「來自 台新銀行・美金 1,560.06・10/19・匯率 32.05」
    private var transferSummary: String {
        guard let e = editing else { return "" }
        let other = facts.account(e.counterpartyId)?.name ?? "別的帳戶"
        let head = e.isWithdrawal ? "轉給 " : "來自 "
        var s = head + other + "・" + WealthFormat.money(e.amount, code: e.currencyCode)
        s += "・" + WealthFormat.monthDay(e.date)
        if let r = e.fxRate, r > 0 { s += "・匯率 " + Self.rateString(r) }
        return s
    }

    // MARK: 對存摺

    /// 對存摺的差：存摺上 − App 算的，四捨五入到 0.01（外幣換算加總會有 999.9999999 這種尾巴；畫面上的差和存檔用同一支）
    private func adjustDiff(target: Double, balance: Double) -> Double {
        ((target - balance) * 100).rounded() / 100
    }

    /// 只在換類型、換日期時重算 App 算的數字（打字不算）
    private var anchorTaskKey: String { "\(txType.rawValue)-\(WealthCal.dayKey(date))-\(currency)" }
    private var appBalanceReady: Bool { appBalance != nil && appBalanceKey == anchorTaskKey }

    /// App 算的「這個帳戶這個幣別、那天結束時」：一套數字重算一次（不走快取）；編輯以前的對存摺不算它自己
    private func refreshAppBalance() {
        guard txType == .adjust else { return }
        let excluding: UUID? = isEditingAnchor ? editing?.id : nil
        let key = anchorTaskKey
        appBalance = lifeStore.passbookBalance(accountId: milestoneId, code: currency, endOf: date,
                                               excluding: excluding, expense: expenseStore, finance: financeStore)
        appBalanceKey = key
    }

    /// 「App 算的 10/19 結束時是 NT$128,520」
    private func appBalanceLine(_ v: Double) -> String {
        "App 算的 " + WealthFormat.monthDay(date) + " 結束時是 " + WealthFormat.money(v, code: currency)
    }

    /// 打了數字、App 的數字也算好了：「差 -NT$120：之後從 NT$128,400 往後算」「差 0：之後從 NT$128,400 往後算」
    private func anchorDiffLine() -> (text: String, color: Color)? {
        guard appBalanceReady, let app = appBalance, let target = Double(amountText) else { return nil }
        let d = adjustDiff(target: target, balance: app)
        let tail = "：之後從 " + WealthFormat.money(target, code: currency) + " 往後算"
        if Swift.abs(d) < 0.005 { return ("差 0" + tail, Color.secondary) }
        let amt = WealthFormat.money(d, code: currency)
        let signed = d > 0 ? "+" + amt : amt
        return ("差 " + signed + tail, d > 0 ? Color.green : Color.red)
    }

    // MARK: 刪除

    private var deleteAlertTitle: String { isEditingTransfer ? "這是一筆轉帳" : "刪除這筆紀錄？" }

    private var deleteAlertMessage: String {
        if isEditingTransfer { return transferSummary + "。對方帳戶也記了一筆，要兩邊一起刪嗎？" }
        if isEditingAnchor { return "刪掉這次對存摺，之後的數字回到 App 算的。" }
        return "刪掉後存摺上的數字會跟著變。"
    }

    // MARK: 畫面

    var body: some View {
        NavigationStack {
            Form {
                typeSection
                mainSection
                if editing != nil { deleteSection }
            }
            // [v25.520] 字面標題超過 9 個中文字寬，放不下改跑馬燈（同一個 view 沒有 principal 項目）
            .marqueeNavigationTitle(editing != nil ? "編輯" : "新增存款 / 提款 / 轉帳 / 對存摺")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editorToolbar }
            .onAppear { loadEditing() }
            .task(id: anchorTaskKey) { refreshAppBalance() }
            .onChange(of: transferTargetId) { _, newId in applyTransferTarget(newId) }
            .onChange(of: transferCode) { _, _ in resetRate() }
            .modifier(DepositDeleteAlert(
                isPresented: $confirmDelete,
                title: deleteAlertTitle,
                message: deleteAlertMessage,
                isTransfer: isEditingTransfer,
                onDelete: { both in performDelete(includingPair: both) }
            ))
        }
        // [v25.563] 疊在財富卡片頁上：切到背景蓋住（帳戶名、金額；judge §7.1、主控補②）
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    private var typeSection: some View {
        Section {
            Picker("類型", selection: $txType) {
                ForEach(TransactionType.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            // 編輯既有紀錄時鎖定類型：轉帳、對存摺各自有自己的存法，編輯途中改類型會另外新增一筆、原本那筆沒處理
            .disabled(editing != nil)
            if editing != nil {
                Text("編輯時無法變更類型").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var mainSection: some View {
        if isEditingTransfer {
            transferReadOnlySection
        } else if txType == .transfer {
            transferSection
        } else if txType == .adjust {
            anchorSection
        } else {
            plainSection
        }
    }

    /// 轉帳：轉到（銀行帳戶，括號是存摺上）、對方幣別（好幾個才有）、日期、轉出金額、匯率（一邊台幣才有）、對方收到、備註
    private var transferSection: some View {
        let targets = transferTargets
        let target = transferTarget
        let preview = transferPreview
        return Section {
            Picker("轉到", selection: $transferTargetId) {
                Text("請選擇").tag(nil as UUID?)
                ForEach(targets) { acc in
                    Text(acc.pickerLabel).tag(acc.id as UUID?)
                }
            }
            if let acc = target, acc.currencies.count > 1 {
                Picker("對方幣別", selection: $transferCode) {
                    ForEach(acc.currencies, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
            }
            DatePicker("日期", selection: $date, displayedComponents: .date)
            HStack {
                Text(currency).foregroundStyle(.secondary)
                TextField("轉出金額", text: $amountText).keyboardType(.decimalPad)
            }
            if showsRateField {
                HStack {
                    Text(rateLabel).foregroundStyle(.secondary)
                    Spacer()
                    TextField("匯率", text: $rateText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            } else if bothForeign {
                Text("兩邊都是外幣：用設定裡的匯率換算")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let p = preview {
                Text(p.text)
                    .font(.subheadline)
                    .foregroundStyle(p.ok ? Color.secondary : Color.red)
            }
            TextField("備註（選填）", text: $adjustNote)
        } header: {
            depositEditorSectionHeader("轉帳資訊", icon: "arrow.left.arrow.right", color: .blue)
        }
    }

    /// 編輯一筆轉帳：只看不改（兩邊綁在一起，改一邊會對不上），要改就刪掉重記
    private var transferReadOnlySection: some View {
        Section {
            Text(transferSummary)
                .font(.subheadline)
            if let n = editing?.note, !n.isEmpty {
                Text(n).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            depositEditorSectionHeader("轉帳", icon: "arrow.left.arrow.right", color: .blue)
        } footer: {
            Text("要改金額請刪掉重記；刪的時候會問要不要兩邊一起刪。")
        }
    }

    /// 對存摺：哪一天、存摺上是多少；下面即時寫 App 算的與差多少
    private var anchorSection: some View {
        let app: Double? = appBalanceReady ? appBalance : nil
        let diffLine = anchorDiffLine()
        return Section {
            Text("打存摺（或網銀）上這一天結束時的數字，以後就從這裡往後算")
                .font(.caption).foregroundStyle(.secondary)
            DatePicker("哪一天", selection: $date, displayedComponents: .date)
            HStack {
                Text(currency).foregroundStyle(.secondary)
                TextField("存摺上是多少", text: $amountText).keyboardType(.decimalPad)
            }
            if let a = app {
                Text(appBalanceLine(a)).foregroundStyle(.secondary)
            }
            if let line = diffLine {
                Text(line.text).foregroundStyle(line.color).bold()
            }
            TextField("差額原因（選填，例：利息、手續費）", text: $adjustNote)
        } header: {
            depositEditorSectionHeader("對存摺", icon: "checkmark.seal.fill", color: .orange)
        }
    }

    /// 存款／提款（也是以前記的沖正的編輯畫面）
    private var plainSection: some View {
        let notePlaceholder: String = isLegacyAdjust ? "備註（如：對帳調整）" : "備註（選填）"
        return Section {
            DatePicker("日期", selection: $date, displayedComponents: .date)
            HStack {
                Text(currency).foregroundStyle(.secondary)
                TextField("金額", text: $amountText).keyboardType(.decimalPad)
            }
            TextField(notePlaceholder, text: $adjustNote, axis: .vertical)
                .lineLimit(2...3)
        } header: {
            plainSectionHeader
        }
    }

    @ViewBuilder
    private var plainSectionHeader: some View {
        if isLegacyAdjust {
            depositEditorSectionHeader("沖正（以前記的）", icon: "arrow.triangle.2.circlepath", color: .orange)
        } else {
            depositEditorSectionHeader("\(currency) \(txType.rawValue)", icon: "banknote.fill", color: .green)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) { confirmDelete = true } label: { Label("刪除", systemImage: "trash") }
        }
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .topBarTrailing) {
            // [美化 v25.101] 存檔中顯示同色 ProgressView（isSaving 忙碌守衛）
            HStack(spacing: 6) {
                if isSaving {
                    ProgressView().scaleEffect(0.7).tint(.green)
                }
                // 編輯一筆轉帳只能看、刪，沒有儲存
                if !isEditingTransfer {
                    Button(editing != nil ? "儲存" : "新增") { saveTapped() }
                        .bold().foregroundStyle(.green)
                        .disabled(saveDisabled || isSaving)
                }
            }
        }
    }

    // MARK: 帶入、存檔、刪除

    private func loadEditing() {
        guard !loaded else { return }
        loaded = true
        guard let e = editing else { return }
        date = e.date
        adjustNote = e.note ?? ""
        if e.isAnchor {
            txType = .adjust
            amountText = Self.editableAmount(e.anchorAmount ?? 0)
        } else if e.isTransfer {
            txType = .transfer
            amountText = Self.editableAmount(e.amount)
        } else {
            // [v25.562] 外幣 123.45 不再被 "%.0f" 吃成 123
            txType = e.isWithdrawal ? .withdrawal : .deposit
            amountText = Self.editableAmount(e.amount)
        }
    }

    private var saveDisabled: Bool {
        switch txType {
        case .deposit, .withdrawal:
            return (Double(amountText) ?? 0) <= 0
        case .transfer:
            if isEditingTransfer || transferTargetId == nil || rateInvalid { return true }
            guard let amount = Double(amountText), amount > 0,
                  let to = transferToAmount(amount) else { return true }
            return to <= 0
        case .adjust:
            return Double(amountText) == nil || !appBalanceReady
        }
    }

    private func saveTapped() {
        switch txType {
        case .transfer: saveTransfer()
        case .adjust: saveAdjust()
        case .deposit, .withdrawal: save()
        }
    }

    /// 存款／提款：編輯時從原本那筆改（連結、kind、以前的沖正旗標都留著）；備註照畫面
    private func save() {
        guard !isSaving else { return }
        guard let amount = Double(amountText), amount > 0 else { return }
        guard var ms = lifeStore.milestones.first(where: { $0.id == milestoneId }) else { dismiss(); return }
        isSaving = true
        let trimmed = adjustNote.trimmingCharacters(in: .whitespacesAndNewlines)
        var dep: BankDeposit = editing
            ?? BankDeposit(kind: txType == .withdrawal ? BankDeposit.kindWithdrawal : BankDeposit.kindDeposit)
        dep.date = date
        dep.amount = amount
        dep.currencyCode = currency
        dep.isWithdrawal = txType == .withdrawal
        dep.note = trimmed.isEmpty ? nil : trimmed
        var list = ms.bankDeposits ?? []
        if let idx = list.firstIndex(where: { $0.id == dep.id }) { list[idx] = dep } else { list.append(dep) }
        ms.bankDeposits = list
        // 先關畫面、下一個 runloop 才寫 store（store 先抓進區域常數）
        let life = lifeStore
        let updated = ms
        dismiss()
        DispatchQueue.main.async { life.update(updated) }
    }

    /// 轉帳：兩邊各一筆、綁同一個 id（LifeStore.addTransfer 一次寫兩邊，milestones 只指派一次）
    private func saveTransfer() {
        guard !isSaving, !isEditingTransfer else { return }
        guard let amount = Double(amountText), amount > 0, let targetId = transferTargetId,
              let toAmount = transferToAmount(amount), toAmount > 0 else { return }
        isSaving = true
        let life = lifeStore
        let fromId = milestoneId
        let fCode = currency
        let tCode = transferCode
        let rate: Double? = fromCode == toCode ? nil : usedRate
        let trimmed = adjustNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let note: String? = trimmed.isEmpty ? nil : trimmed
        let day = date
        dismiss()
        DispatchQueue.main.async {
            life.addTransfer(from: fromId, fromCode: fCode, amount: amount, to: targetId, toCode: tCode,
                             toAmount: toAmount, fxRate: rate, date: day, note: note)
        }
    }

    /// 對存摺：一筆 anchor（差額 0 也存：它把以前的帳釘住，之後補記以前的帳不影響今天）；編輯就換掉同一個 id
    private func saveAdjust() {
        guard !isSaving else { return }
        guard let target = Double(amountText), appBalanceReady, let app = appBalance else { return }
        guard var ms = lifeStore.milestones.first(where: { $0.id == milestoneId }) else { dismiss(); return }
        isSaving = true
        let diff = adjustDiff(target: target, balance: app)
        let trimmed = adjustNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let dep = BankDeposit(id: editing?.id ?? UUID(), date: date, amount: Swift.abs(diff),
                              currencyCode: currency, isWithdrawal: diff < 0, isAdjust: true,
                              note: trimmed.isEmpty ? nil : trimmed,
                              kind: BankDeposit.kindAnchor, anchorAmount: target)
        var list = ms.bankDeposits ?? []
        if let idx = list.firstIndex(where: { $0.id == dep.id }) { list[idx] = dep } else { list.append(dep) }
        ms.bankDeposits = list
        // 先關畫面、下一個 runloop 才寫 store（store 先抓進區域常數）
        let life = lifeStore
        let updated = ms
        dismiss()
        DispatchQueue.main.async { life.update(updated) }
    }

    /// 刪除（確認框按了才來）：先關畫面、下一個 runloop 才刪；轉帳 includingPair＝兩邊一起刪
    private func performDelete(includingPair: Bool) {
        guard let e = editing else { dismiss(); return }
        let life = lifeStore
        let accountId = milestoneId
        let depositId = e.id
        dismiss()
        DispatchQueue.main.async {
            life.deleteBankDeposit(depositId, in: accountId, includingPair: includingPair)
        }
    }
}
