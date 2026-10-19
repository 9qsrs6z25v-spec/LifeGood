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

// MARK: - [v25.564] 新財富頁（財富 v3；wealth/judge.md §3.0–3.12、build/v3/brief.md §G1）
//
// 捲動頁（同健康頁）：由上到下 ① 看板（天空、頂樓水塔、存款合計、存款組成條＋四格；WealthBoard.swift）→ ② 要確認
// （WealthChecksSection，G3）→ ③ 接下來 30 天・各帳戶夠不夠扣 → ④ 信用卡 → ⑤ 銀行帳戶 → ⑥ 證券戶 → ⑦ 保單 → ⑧ 收起來的 → ⑨ 頁尾。
// • 整頁的字和數字在 .task(id:) 裡用 WealthPageData.build 算一次存成 @State（key＝財富的一套數字的快取 key＋今天＋遮住＋深淺色）；
//   body 只畫。數字一律讀 lifeStore.wealthFacts（同一份快取）。
// • 彈出頁只有一個 enum WealthSheet（WealthItems.swift）＋一個 .sheet(item:)，內容最外層 .appStores()；記帳表單外面再包布幕。
//   確認框（停用卡、收起來）一個；付費說明一個；「為什麼數字變了」說明一次（v2 照留）。
// • 右上：眼睛（遮住：打開直接遮；關掉要 Face ID）、綠色＋（銀行帳戶／信用卡／證券戶／保單，要訂閱）、⋯（排序與收起來、
//   這頁的數字怎麼算、iCloud 與家人共享說明）。導覽列那行小計拿掉（跟大字重複）。
// • 列表頁本身不掛布幕（judge §7.2-2：只有金額，可以用遮住）；卡片頁、表單自己掛。
// • 付費（待決定 10）：看得到全部；＋、編輯、記一筆、轉帳、對存摺要訂閱；標成已繳、停用卡、收起來、排序、遮住、看卡片頁不擋。
// • 以前的 FinanceCardView、DepositEditorSheet 拿掉：卡片頁換成 WealthCardPage（G2），小表單換成 WealthEditors（G3）。
//
// [v25.565] 財富 v4（build/v4/brief.md §G4-3～5、§1-11；judge §3.4、§6.8）：
// • ①' 橋：看板下一顆膠囊「這些已算進理財淨資產 NT$1381.1萬 ›」，點了切到理財 › 總覽（AppNavigation.goToFinance(.overview)）。
//   全頁唯一會切分頁的地方。數字＝FinanceSnapshot.current(...).netWorth（理財總覽、人生總覽名片同一個數），rebuild() 一起算。
// • 深連結／財富提醒通知（DeepLinkRouter.takeWealthAccount，lifegood://life/wealth?id=）：直接打開那張卡／那個帳戶的卡片頁；
//   別的彈出頁開著先收掉、0.45 秒後（收的動畫跑完，同健康頁）才開；已經在看那一張不動。帳戶已經不在就不開。
// • ② 要確認 #12〔看綁了哪些〕：開那張卡的卡片頁、捲到「綁在這張卡的定期扣款」（同一個 .sheet(item:)）。

struct LifeFinanceView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    /// 一套數字（lifeStore.wealthFacts）要股票的交割、股利；保單那區數儲蓄險
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    /// 遮住（記在這台裝置，不同步；卡片頁讀同一個鍵）
    @AppStorage(WealthMask.storageKey) private var masked = false

    /// 整頁的字和數字（.task(id:) 算一次；nil＝還沒算好）
    @State private var page: WealthPageData?
    /// 上次算 page 用的 key：畫面重新出現（切分頁回來）.task(id:) 會再跑一次，key 一樣就不重算
    @State private var lastBuiltKey = ""
    /// 今天（過了午夜回到前景，換新的一天）
    @State private var dayKey = WealthCal.dayKey(Date())
    @State private var sheet: WealthSheet?
    /// 長按「停用」「收起來」等確認的那一個
    @State private var confirm: WealthPageConfirm?
    @State private var showPremiumAlert = false
    /// [v25.563] 第一次打開說明「為什麼數字變了」；nil＝沒在說
    @State private var notice: WealthNoticeAlert?
    /// 進場動畫（掛在 ScrollView 本身，坑 #13：不掛在列上，捲動不會重播）
    @State private var appeared = false

    /// 財富的一套數字的快取 key（里程碑／帳本 revision＋記帳、理財 modifyID＋匯率＋日期）＋今天＋遮住＋深淺色
    /// （信用卡的使用率條顏色分深淺，資料端組好）＋匯率更新時間（頁尾「匯率是 10/15 的」：匯率數字沒變、只是剛更新過也要換）
    private var pageKey: String {
        let base = WealthFacts.cacheKey(revision: lifeStore.wealthRevision, expense: expenseStore,
                                        finance: financeStore, now: Date())
        let m: String = masked ? "m" : "-"
        let d: String = scheme == .dark ? "d" : "l"
        let r: Int = Int(AppQuoteClock.ratesUpdatedAt?.timeIntervalSince1970 ?? 0)
        return "\(base)|\(dayKey)|\(m)|\(d)|\(r)"
    }

    // MARK: 主體

    // 修飾器鏈拆兩段（捲動頁一段、彈出頁與生命週期一段），閉包裡只叫具名函式：body 一個運算式不要太大（坑 #7）
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                scrollPage(proxy)
            }
            .sheet(item: $sheet) { s in
                sheetView(s).appStores()
            }
            .modifier(WealthPageConfirmDialog(confirm: $confirm, onChoose: { c, go in confirmed(c, goFix: go) }))
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .task(id: pageKey) { rebuild() }
            .onAppear { pageAppeared() }
            .onChange(of: scenePhase) { _, phase in sceneChanged(phase) }
            // [v25.565] 小工具卡費／交割列、財富提醒通知：打開那張卡／那個帳戶
            .onDeepLinkItem { openDeepLinkedAccount() }
        }
        // [v25.563] 第一次打開：用你自己的數字說明為什麼銀行的數字變了（說一次，跟 iCloud 同步）
        .modifier(WealthNoticeAlertModifier(notice: $notice, onDone: { markPassbookNoticeSeen() }))
    }

    /// 捲動頁本身：大標「財富」、底色、右上三顆；進場動畫掛在 ScrollView 本身
    private func scrollPage(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            pageContent(proxy)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("財富")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
    }

    @ViewBuilder
    private func pageContent(_ proxy: ScrollViewProxy) -> some View {
        if let p = page {
            sections(p, proxy: proxy)
        } else {
            Color.clear.frame(height: 420)
        }
    }

    /// 由上到下 ①、①' 橋～⑨（VStack 剛好 10 個；再加要先包一層）
    private func sections(_ p: WealthPageData, proxy: ScrollViewProxy) -> some View {
        let actions = pageActions
        return VStack(spacing: 20) {
            WealthBoard(data: p, onTile: { a in scroll(to: a, proxy) }, onStarter: { k in addAccount(k) })
            bridgeBlock(p)
            checksBlock(p)
            upcomingBlock(p)
            cardsBlock(p, actions: actions)
            banksBlock(p, actions: actions)
            brokersBlock(p, actions: actions)
            policiesBlock(p, actions: actions)
            hiddenBlock(p, actions: actions)
            footerBlock(p)
        }
    }

    /// [v25.565] ①' 橋（新手、還沒算出淨資產不出現）：點了切到理財 › 總覽
    @ViewBuilder
    private func bridgeBlock(_ p: WealthPageData) -> some View {
        if let b = p.bridge {
            WealthPageBridgeView(bridge: b, onTap: { goToFinanceOverview() })
        }
    }

    /// ② 要確認（G3 的 WealthChecksSection；0 件整區不出現）。
    /// [v25.565] #12〔看綁了哪些〕交回這頁開卡片頁（同一個 .sheet(item:)，不在要確認裡再疊一張）
    @ViewBuilder
    private func checksBlock(_ p: WealthPageData) -> some View {
        if !p.checks.isEmpty {
            WealthChecksSection(checks: p.checks, onOpenCard: { id in openCardRecurring(id) })
        }
    }

    @ViewBuilder
    private func upcomingBlock(_ p: WealthPageData) -> some View {
        if let u = p.upcoming {
            WealthPageUpcomingSection(data: u,
                                      onRow: { id in open(.card(id, .upcoming)) },
                                      onAll: { open(.upcomingAll) })
                .id(WealthPageAnchor.upcoming)
        }
    }

    @ViewBuilder
    private func cardsBlock(_ p: WealthPageData, actions: WealthPageActions) -> some View {
        if let h = p.cardsHeader, !p.cards.isEmpty {
            WealthPageCardsSection(header: h, rows: p.cards, actions: actions)
                .id(WealthPageAnchor.cards)
        }
    }

    /// ⑤ 銀行帳戶（只有卡：換一張提示卡；新手：不出現）
    @ViewBuilder
    private func banksBlock(_ p: WealthPageData, actions: WealthPageActions) -> some View {
        if !p.banks.isEmpty || p.showBankPrompt {
            WealthPageBanksSection(header: p.banksHeader, rows: p.banks, showPrompt: p.showBankPrompt, actions: actions)
                .id(WealthPageAnchor.banks)
        }
    }

    @ViewBuilder
    private func brokersBlock(_ p: WealthPageData, actions: WealthPageActions) -> some View {
        if let h = p.brokersHeader, !p.brokers.isEmpty {
            WealthPageBrokersSection(header: h, rows: p.brokers, actions: actions)
        }
    }

    @ViewBuilder
    private func policiesBlock(_ p: WealthPageData, actions: WealthPageActions) -> some View {
        if let pol = p.policies {
            WealthPagePoliciesSection(data: pol, actions: actions)
        }
    }

    @ViewBuilder
    private func hiddenBlock(_ p: WealthPageData, actions: WealthPageActions) -> some View {
        if let h = p.hidden {
            WealthPageHiddenSection(data: h, actions: actions)
        }
    }

    @ViewBuilder
    private func footerBlock(_ p: WealthPageData) -> some View {
        if let f = p.footer {
            WealthPageFooterView(line: f)
        }
    }

    // MARK: 資料

    /// 整頁一次算好（WealthPageData.build 在主執行緒：ntdWanString 用共用的 NumberFormatter）。
    /// key 跟上次算的一樣（畫面重新出現）就不重算；資料一改 wealthRevision／modifyID 就變，key 跟著變
    private func rebuild() {
        let key = pageKey
        guard page == nil || key != lastBuiltKey else { return }
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        let rates = FinanceRates(expenseStore)
        // [v25.565] 橋的數字：理財淨資產（跟理財總覽同一個 FinanceSnapshot；財富的部分讀同一份 wealthFacts 快取）
        let snap = FinanceSnapshot.current(finance: financeStore, expense: expenseStore, rates: rates)
        page = WealthPageData.build(facts: facts, milestones: lifeStore.milestones, book: lifeStore.wealthBook,
                                    expenses: expenseStore.expenses, insurances: financeStore.insurances,
                                    rates: rates, ratesUpdatedAt: AppQuoteClock.ratesUpdatedAt,
                                    now: Date(), masked: masked, dark: scheme == .dark, netWorth: snap.netWorth)
        lastBuiltKey = key
    }

    private func pageAppeared() {
        refreshDay()
        checkPassbookNotice()
        if !appeared {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
        }
    }

    /// 回到前景：日期變了換新的一天（改了 dayKey，pageKey 就變，整頁重算）
    private func sceneChanged(_ phase: ScenePhase) {
        guard phase == .active else { return }
        refreshDay()
    }

    private func refreshDay() {
        let k = WealthCal.dayKey(Date())
        if k != dayKey { dayKey = k }
    }

    // MARK: 動作（付費照待決定 10）

    private var pageActions: WealthPageActions {
        WealthPageActions(open: { s in open(s) },
                          edit: { id, kind in edit(id, kind: kind) },
                          confirm: { c in confirm = c },
                          restore: { id, isCard in restore(id, isCard: isCard) })
    }

    /// 打開一張彈出頁；要訂閱的那幾種（新增、編輯、記一筆、轉帳、對存摺、刷這張卡記一筆）沒訂閱先跳付費說明
    private func open(_ s: WealthSheet) {
        if s.needsPremium && !subscription.isPremium {
            showPremiumAlert = true
            return
        }
        sheet = s
    }

    /// 新增財富帳戶（右上＋、新手的三顆大按鈕）
    private func addAccount(_ kind: WealthAccountKind) {
        open(.editor(kind, nil))
    }

    /// 長按「編輯」：拿 store 裡最新的那一筆里程碑（page 是上一次算的）
    private func edit(_ id: UUID, kind: WealthAccountKind) {
        guard let m = lifeStore.milestones.first(where: { $0.id == id }) else { return }
        open(.editor(WealthAccountKind(sub: m.financeSubCategory) ?? kind, m))
    }

    /// 收起來的：重新啟用卡／不收起來帳戶（不擋訂閱）。選單收起來那一次畫面更新先過，下一輪才寫 store
    private func restore(_ id: UUID, isCard: Bool) {
        let life = lifeStore
        DispatchQueue.main.async {
            if isCard {
                life.setCardDisabled(id, disabled: false)
            } else {
                life.setWealthHidden(id, hidden: false)
            }
        }
    }

    /// 確認框按了：goFix＝〔先去改〕（停用前先去卡片頁改定期扣款）；不然照做（停用／收起來）。
    /// 確認框正在收起來：寫 store、開卡片頁都放到下一輪主執行緒
    private func confirmed(_ c: WealthPageConfirm, goFix: Bool) {
        let life = lifeStore
        switch c {
        case .disableCard(let id, _, _):
            if goFix {
                DispatchQueue.main.async { sheet = .card(id, .recurring) }
            } else {
                DispatchQueue.main.async { life.setCardDisabled(id, disabled: true) }
            }
        case .hideAccount(let id, _):
            DispatchQueue.main.async { life.setWealthHidden(id, hidden: true) }
        }
    }

    /// [v25.565] ①' 橋：切到理財 › 總覽（寫 @AppStorage 的鍵就切過去；judge §6.8 只有這裡和理財「存款」明信片會切分頁）
    private func goToFinanceOverview() {
        AppNavigation.goToFinance(.overview)
    }

    /// [v25.565] #12〔看綁了哪些〕：開那張卡的卡片頁、捲到綁在這張卡的定期扣款（看卡片頁不擋訂閱：直接設 sheet）
    private func openCardRecurring(_ id: UUID) {
        sheet = .card(id, .recurring)
    }

    /// [v25.565] 小工具「接下來要繳」的卡費／交割列、財富提醒通知點進來：打開那張卡／那個帳戶的卡片頁。
    /// 不是財富的請求 takeWealthAccount 回 nil（留給別頁）；帳戶已經刪了就不開；已經在看那一張就不動。
    /// 別的彈出頁開著：先收掉，0.45 秒後（收的動畫跑完）才開——照健康頁 openSessionFromLink 的寫法
    ///（只隔一輪主執行緒，收的動畫還在跑，新的那張可能開不起來）。這裡只開彈出頁，不寫 store
    private func openDeepLinkedAccount() {
        guard let id = DeepLinkRouter.shared.takeWealthAccount() else { return }
        guard lifeStore.milestones.contains(where: { $0.id == id }) else { return }
        if case .card(let shown, _)? = sheet, shown == id { return }
        let target = WealthSheet.card(id, nil)
        guard sheet != nil else {
            sheet = target
            return
        }
        sheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            reopenAfterSheet(target)
        }
    }

    /// [v25.565] 彈出頁收掉之後才開那張卡：那 0.45 秒裡又開了別的就不動
    private func reopenAfterSheet(_ target: WealthSheet) {
        guard sheet == nil else { return }
        sheet = target
    }

    /// 看板的格子、圖例：捲到那一區（那一區不在就不動）
    private func scroll(to anchor: WealthPageAnchor, _ proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    /// 眼睛：打開遮住直接遮；關掉要 Face ID（手機借人時別人按不開；裝置沒設密碼直接放行）。
    /// 改完馬上重組一次（同一次畫面更新就換字，不等 .task(id:) 下一輪：遮住時不會先閃一下真的金額）
    private func toggleMask() {
        if masked {
            Task {
                if await WealthMask.confirmUnmask() {
                    masked = false
                    rebuild()
                }
            }
        } else {
            masked = true
            rebuild()
        }
    }

    // MARK: 右上（眼睛、綠色＋、⋯）

    /// 同健康頁：一個 ToolbarItem 裡 HStack(spacing: 12)（三顆的間距自己給，不交給系統把它們包成一組）
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                eyeButton
                addButton
                moreMenu
            }
        }
    }

    /// 遮住中＝實心 eye.slash.fill；沒遮＝eye（brief G1-0、G1-5）
    private var eyeButton: some View {
        Button {
            toggleMask()
        } label: {
            Image(systemName: eyeIcon)
                .font(.body.weight(.semibold))
        }
        .accessibilityLabel(eyeLabel)
    }

    private var eyeIcon: String { masked ? "eye.slash.fill" : "eye" }

    private var eyeLabel: String { masked ? "顯示金額（要 Face ID）" : "遮住金額" }

    /// 綠色＋：有訂閱是選單（銀行帳戶／信用卡／證券戶／保單）；沒訂閱是一顆只跳付費說明的按鈕（付費在選單打開前就擋）
    @ViewBuilder
    private var addButton: some View {
        if subscription.isPremium {
            Menu {
                ForEach(WealthAccountKind.allCases) { k in
                    Button {
                        addAccount(k)
                    } label: {
                        Label(k.title, systemImage: k.icon)
                    }
                }
            } label: {
                addIcon
            }
            .accessibilityLabel("新增財富帳戶")
        } else {
            Button {
                showPremiumAlert = true
            } label: {
                addIcon
            }
            .accessibilityLabel("新增財富帳戶")
        }
    }

    /// 綠圓白「＋」（同健康頁：綠用 1F9D57，深色也是白色的＋）
    private var addIcon: some View {
        Image(systemName: "plus.circle.fill")
            .font(.title3)
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color.white, Color(tb: 0x1F9D57))
    }

    /// ⋯：排序與收起來、這頁的數字怎麼算、iCloud 與家人共享說明（都不擋訂閱）
    private var moreMenu: some View {
        Menu {
            Button {
                open(.order)
            } label: {
                Label("排序與收起來", systemImage: "arrow.up.arrow.down")
            }
            Button {
                open(.info(.howItWorks))
            } label: {
                Label(WealthPageInfoTopic.howItWorks.title, systemImage: "questionmark.circle")
            }
            Button {
                open(.info(.iCloud))
            } label: {
                Label(WealthPageInfoTopic.iCloud.title, systemImage: "icloud")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
        .accessibilityLabel("更多")
    }

    // MARK: 彈出頁（每一種在邊界抹成 AnyView：型別不要太深，坑 #6）

    private func sheetView(_ s: WealthSheet) -> AnyView {
        switch s {
        case .card(let id, let anchor):
            return AnyView(WealthCardPage(accountId: id, scrollTo: anchor))
        case .editor(let kind, let m):
            return AnyView(WealthAccountEditor(kind: kind, editing: m))
        case .record(let id, let kind):
            return AnyView(WealthRecordSheet(accountId: id, kind: kind))
        case .transfer(let id):
            return AnyView(WealthTransferSheet(fromId: id))
        case .anchor(let id, let code):
            return AnyView(WealthAnchorSheet(accountId: id, code: code))
        case .paid(let id):
            return AnyView(WealthPaidSheet(cardId: id))
        case .addExpense(let id):
            // 刷這張卡記一筆：記帳表單外面再包布幕（切到背景蓋住）
            return AnyView(AddExpenseView(expenseType: .variable, preset: AddExpensePreset(paymentCardId: id))
                .modifier(WealthPrivacyCurtain(armed: true)))
        case .order:
            return AnyView(WealthOrderSheet())
        case .info(let topic):
            return AnyView(WealthPageInfoSheet(topic: topic))
        case .upcomingAll:
            return AnyView(WealthPageUpcomingSheet(items: page?.upcoming?.all ?? []))
        }
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
}

// MARK: - [v25.564] 停用卡、收起來的確認框

/// 拆成 ViewModifier：財富頁 body 已經掛了 sheet、alert、toolbar，再塞會讓型別檢查變慢（坑 #7）。
/// 停用卡還有定期扣款刷它：〔先去改〕〔直接停用〕〔取消〕；沒有：〔停用〕〔取消〕；收起來：〔收起來〕〔取消〕。
/// onChoose 的第二個參數＝〔先去改〕
fileprivate struct WealthPageConfirmDialog: ViewModifier {
    @Binding var confirm: WealthPageConfirm?
    let onChoose: (WealthPageConfirm, Bool) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            confirm?.title ?? "",
            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
            titleVisibility: .visible,
            presenting: confirm
        ) { c in
            buttons(c)
        } message: { c in
            Text(c.message)
        }
    }

    @ViewBuilder
    private func buttons(_ c: WealthPageConfirm) -> some View {
        switch c {
        case .disableCard(_, _, let n):
            if n > 0 {
                Button("先去改") { onChoose(c, true) }
                Button("直接停用", role: .destructive) { onChoose(c, false) }
            } else {
                Button("停用", role: .destructive) { onChoose(c, false) }
            }
        case .hideAccount:
            Button("收起來") { onChoose(c, false) }
        }
        Button("取消", role: .cancel) {}
    }
}
