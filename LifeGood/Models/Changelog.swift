import Foundation

/// 單筆版本更新紀錄（內建、隨版本打包；只在管理控制台檢視）。
struct ChangelogEntry: Identifiable {
    let version: String     // 例 "18.76"
    let build: Int          // 例 425
    let date: String        // 例 "2026/06/11"
    let notes: [String]     // 該版更新重點（條列）
    var id: String { "\(version)_\(build)" }
}

/// 內建版本更新紀錄。
/// 慣例：**每次改版在最上面新增一筆**（新到舊）。
enum Changelog {
    static let entries: [ChangelogEntry] = [
        ChangelogEntry(version: "22.58", build: 525, date: "2026/06/24", notes: [
            "【靜態除錯 v22.58】全面複查 79 個 Swift 檔，發現並修復五個問題：① LifeStore.toggleMeetingItemCompletion / toggleWeeklyReportCompletion：兩個方法均缺少 isLoading 批次保護，對 subordinates 的 subscript 寫入觸發 didSet → save()，再加上方法尾部的顯式 save() 呼叫，每次打勾共觸發兩次磁碟序列化與兩次 CloudKit pushAll；補 isLoading = true / false 包圍寫入，確保只有顯式 save() 執行一次，對齊 toggleTaskCompletion / setShift 既有規格。② MyCalendarView.annualOccurrence：對非閏年的 2/29 生日，Calendar.date(from:) 不回傳 nil 而是自動溢位到 3/1，導致閏日生日在非閏年顯示於錯誤月份；改以 calendar.range(of: .day, in: .month) 取得該年該月實際天數，提前截斷 comp.day，完全避開溢位行為。③ MyCalendarView.subReportDateText：每次呼叫都新建 DateFormatter（含完整 locale 載入），view body render 期間重複分配；改為 private static let 快取，對齊同檔其他所有格式器規格。④ AddExpenseView.formatCurrency：每次呼叫都新建 NumberFormatter（建立成本高），在儲蓄保險區塊於 view body render 時重複分配；改為 private static let savingsCurrencyFmt 複用同一物件，每次只更新 currencySymbol 與 maximumFractionDigits 屬性。⑤ ChildDetailView 院所自動完成（MKLocalSearchCompleter）：onChange(of: detail) 在每次按鍵時立即發出查詢，無防抖保護，造成大量不必要的 MapKit 網路請求；補 300ms 防抖 Task（clinicDebounceTask），對齊 AddExpenseView / VariableExpenseView 餐廳 / 支出搜尋既有規格。其餘防護機制（force unwrap 全無、as! 全無、fatalError 僅 EInvoiceClient 啟動守衛、CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、所有 @Published 更新主執行緒隔離）均確認正常。"
        ]),
        ChangelogEntry(version: "22.57", build: 524, date: "2026/06/23", notes: [
            "報告改為顯示『本週全部報告 + 任何未完成（含逾期）』，不再只看當日；逾期/本週/待辦以彩色標籤標示，未完成優先排序。",
            "部屬總覽與我的行事曆的報告章節同步套用新規則，並顯示報告日期。"
        ]),
        ChangelogEntry(version: "22.56", build: 523, date: "2026/06/23", notes: [
            "整合：將班表日期表頭水平同步修正、週報→報告改名與報告彙整、當日事件卡精簡等更新併入本線（保留既有美化）。"
        ]),
        ChangelogEntry(version: "22.55", build: 522, date: "2026/06/23", notes: [
            "我的行事曆『當日事件』卡片不再列入部屬會議與部屬任務（下方已有獨立的部屬事項卡片，避免重複）。"
        ]),
        ChangelogEntry(version: "22.54", build: 521, date: "2026/06/23", notes: [
            "部屬班表：改用 onScrollGeometryChange 直接讀取捲動位移，修正左右滑動時頂部日期表頭不跟著移動的問題（iOS 17 保留量測後援）。",
            "『週報』章節更名為『報告』（含編輯頁與評分明細）。",
            "部屬總覽於『會議』上方新增『報告』彙整章節（可勾選完成、點擊編輯）。",
            "我的行事曆部屬事項於『部屬會議』上方新增『部屬報告』卡片（可勾選完成）。"
        ]),
        ChangelogEntry(version: "22.53", build: 520, date: "2026/06/23", notes: [
            "部屬班表：修正左右捲動表格時，頂部凍結日期表頭未跟著水平移動的問題（改以 overlayPreferenceValue 即時同步位移）。"
        ]),
        ChangelogEntry(version: "22.52", build: 519, date: "2026/06/11", notes: [
            "部屬卡片新增『週報』章節（會議上方）：可新增週報題目、勾選完成；每完成一份週報 +3 併入主動性評分。"
        ]),
        ChangelogEntry(version: "22.50", build: 517, date: "2026/06/11", notes: [
            "部屬列表左側分數改為『潛力 × 主動性』的綜合平均（頂部平均/優秀統計同步）。",
            "部屬卡片『主動性 / 潛力性』分頁按鈕，標題旁加上各自分數。"
        ]),
        ChangelogEntry(version: "22.49", build: 516, date: "2026/06/11", notes: [
            "部屬總覽『未完成會議條目』顯示截止日期（逾期紅字）。",
            "我的行事曆未來里程碑下方新增部屬事項：請假/會議/任務/未完成會議條目/未完成任務（依所選日期，任務與會議條目可打勾）。"
        ]),
        ChangelogEntry(version: "22.48", build: 515, date: "2026/06/11", notes: [
            "部屬卡片分頁『日常 / 評分系統』改名為『主動性 / 潛力性』。",
            "部屬總覽在『未完成任務』上方新增『未完成會議條目』章節，可逐條打勾。"
        ]),
        ChangelogEntry(version: "22.47", build: 514, date: "2026/06/11", notes: [
            "人才矩陣：點散布圖上的點會彈出計算明細卡（主動性 / 潛力各條目加減分），點卡片外即關閉。"
        ]),
        ChangelogEntry(version: "22.46", build: 513, date: "2026/06/11", notes: [
            "潛力評分不再把請假計入（請假已反映在主動性），避免重複計算；列表評分同步。"
        ]),
        ChangelogEntry(version: "22.45", build: 512, date: "2026/06/11", notes: [
            "新增『人才矩陣』散布圖（部屬頁右上）：X 軸主動性（任務/會議完成、出勤）、Y 軸潛力（評分系統），依成員最大/最小值自動縮放，分四象限定位每位成員。"
        ]),
        ChangelogEntry(version: "22.44", build: 511, date: "2026/06/11", notes: [
            "部屬會議章節：除了會議名稱，也列出議程項目並可逐項打勾完成（部屬詳情頁與部屬總覽同步）。"
        ]),
        ChangelogEntry(version: "22.42", build: 509, date: "2026/06/11", notes: [
            "部屬班表：凍結頂部日期表頭列（往下捲也看得到日期），姓名欄維持凍結；水平捲動表頭與內容同步。",
            "點格子設定班別時，上方可微調 / 直接選日期，避免點歪選不準。"
        ]),
        ChangelogEntry(version: "22.40", build: 507, date: "2026/06/11", notes: [
            "完整備份可選照片時間範圍（全部 / 最近一年 / 最近三年 / 自訂），避免照片過多時檔案過大；結構化資料一律完整。"
        ]),
        ChangelogEntry(version: "22.39", build: 506, date: "2026/06/22", notes: [
            "【靜態除錯 v22.39】發現並修復三個畫面缺少 onDisappear 進場動畫旗標重置的問題：① OrganizationView.peopleAppeared：唯一的 peopleAppeared 旗標未在 onDisappear 重置，使用者切換分頁後返回組織圖頁時人員列表進場動畫不再播放；補 .onDisappear { peopleAppeared = false }。② SubordinateOverviewView：heroAppeared / sectionAppeared 兩個旗標均缺 onDisappear 重置，切換分頁後返回部屬總覽時英雄卡與統計區塊進場動畫不再播放；補 .onDisappear { heroAppeared = false; sectionAppeared = false }。③ FinanceOverviewView：appearedCards（各資產卡）/ miniBarAppeared / allocationBarAppeared / allocationRowsAppeared / cashFlowSectionAppeared 五組旗標全部缺 onDisappear 重置，切換分頁後返回理財總覽時所有進場動畫均不再播放；按各節點分別補對應 onDisappear 重置，對齊 v22.36 LifeOverviewView / v22.35 CareerView / v22.24 FamilyView 同型修復規格。全域掃描（force unwrap、Optional、競態條件、CloudKit 節流、主執行緒重運算、index 越界）：其餘防護機制均確認正常。"
        ]),
        ChangelogEntry(version: "22.36", build: 505, date: "2026/06/22", notes: [
            "【靜態除錯 v22.36】發現並修復兩個進場動畫旗標缺少 onDisappear 重置的問題：① LifeOverviewView 三個旗標（statsCardAppeared / timelineRowsAppeared / categoryRowsAppeared）均無 .onDisappear { flag = false }；當使用者滾動使各區塊離開畫面後再捲回，或切換功能後返回，旗標已為 true，進場動畫不再播放；補三處 .onDisappear 重置，對齊 v22.35 CareerView / v22.24 FamilyView 同型修復規格。② MyCalendarView 四個旗標（heroCardAppeared / todayCardAppeared / weekCardAppeared / milestonesCardAppeared）同樣缺少 .onDisappear 重置；補四處，確保每次返回行事曆頁時進場動畫正確重播。全域掃描（force unwrap、Optional、競態條件、CloudKit 節流、主執行緒重運算、index 越界）：其餘防護機制均確認正常。"
        ]),
        ChangelogEntry(version: "22.35", build: 504, date: "2026/06/22", notes: [
            "【靜態除錯 v22.35】CareerView 三個進場動畫旗標（dashboardAppeared / subCatRowsAppeared / milestoneRowsAppeared）缺少 onDisappear 重置：使用者切換分頁後返回職涯頁，旗標已為 true，onAppear 觸發時動畫不再播放；補三處 .onDisappear { flag = false }，對齊 v22.24 FamilyView / v22.30 EInvoiceSetupView / v22.33 FamilyOverviewMap 同型修復規格。全域掃描（force unwrap、Optional、競態條件、CloudKit 節流、主執行緒重運算、index 越界）：FinanceChartView v5 膠囊邊框均為純視覺修飾確認安全；其餘防護機制均正常。"
        ]),
        ChangelogEntry(version: "22.34", build: 503, date: "2026/06/21", notes: [
            "【UI 美化 v5】FinanceChartView：補齊三大 section 膠囊細邊框——① stockPerformanceSection 股票代號膠囊 + 報酬率膠囊補入 .overlay(Capsule().stroke(plC.opacity(0.22), lineWidth: 0.6))；② realEstatePerformanceSection 升值率膠囊補入 appColor.opacity(0.22) 細邊框、租報率膠囊補入 Color.blue.opacity(0.22) 細邊框；③ insuranceSummarySection 已繳金額中性膠囊補入 Color(.separator).opacity(0.40) 細邊框、預估報酬率膠囊補入 rateColor.opacity(0.22) 細邊框；全頁所有 Capsule 標籤均具備 0.6pt 描邊，對齊 sectionHeader 計數膠囊 / allocationChart 百分比膠囊全 App 膠囊視覺語言規格。"
        ]),
        ChangelogEntry(version: "22.33", build: 502, date: "2026/06/21", notes: [
            "【動畫修復】FamilyOverviewMap.houseRowsAppeared 進場動畫旗標未在 onDisappear 重置：使用者捲動使街道圖離開視窗後再捲回，或切換分頁後返回，旗標已為 true，導致 onAppear 觸發時動畫不再播放；補 .onDisappear { houseRowsAppeared = false }，對齊 v22.24 FamilyView.statsAppeared、v22.30 EInvoiceSetupView.heroAppeared 同型修復規格。其餘防護機制（force unwrap 全無、as! 全無、fatalError 僅 EInvoiceClient 啟動守衛、CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、所有 @Published 更新主執行緒隔離）均確認正常。"
        ]),
        ChangelogEntry(version: "22.32", build: 501, date: "2026/06/21", notes: [
            "【靜態除錯】全面複查 FullBackup、NotificationManager、StockView、MainTabView 等核心檔案，發現並修復兩個效能問題：① FullBackup.gatherAttachmentFiles()：原本使用 contentsOfDirectory(atPath:) 取得檔名後，在 export() 中對每個附件再額外呼叫 fm.attributesOfItem(atPath:) 取得檔案大小，N 個附件造成 N 次系統呼叫；改為 contentsOfDirectory(at:includingPropertiesForKeys:[.fileSizeKey]) 一次取得所有 URL 及檔案大小資源值，export() 直接使用，N 次 attributesOfItem 降為 0 次。② NotificationManager.rescheduleAll()：原本呼叫 schedule() 的實作，每處理一個事件都 await center.pendingNotificationRequests() 一次系統 API 呼叫，N 個事件造成 N 次非必要的系統呼叫；抽取 addScheduleRequests(for:) 私有方法包含排程邏輯，rescheduleAll() 改為一次批次取得 pending 通知並批次移除，再逐一呼叫 addScheduleRequests(for:)，系統 API 呼叫從 N 次降為 1 次。StockView.refreshAllPrices() 的逐次更新設計確認為刻意設計（避免 CloudKit async 期間快照覆蓋），保持不變。isCurrentlyManagerial 確認只在 shouldExpandManagement 被呼叫一次，無需修正。"
        ]),
        ChangelogEntry(version: "22.31", build: 500, date: "2026/06/21", notes: [
            "【靜態除錯】全面複查 78 個 Swift 檔，發現並修復一個資料遺失 bug：AddRealEstateView.loadFrom() 以 split(separator:\"-\") 解析 waterMeterNumber 時，預設 omittingEmptySubsequences: true 會將末尾或中間的空欄位消滅，使 combinedWaterNumber（格式為「站所-編號-檢核」）在任一欄位為空時分割結果為 count==2，既不符合 count>=3 也不符合 count==1 的條件，導致 waterStation / waterCode / waterCheck 全部留空，使用者下次開啟編輯並儲存後水表號碼資料遺失；改為 split(separator:\"-\", omittingEmptySubsequences: false)，保留空欄位後 count 恆為 3，三個欄位均可正確還原。其餘防護機制（force unwrap 全無、as! 全無、fatalError 僅 EInvoiceClient 啟動守衛、CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、visible[0] count>=2 外層守衛、FinanceChartView v4 美化純視覺無邏輯變更）均確認正常。"
        ]),
        ChangelogEntry(version: "22.30", build: 499, date: "2026/06/21", notes: [
            "【靜態除錯】發現並修復兩個問題：① EInvoiceSetupView.heroAppeared 進場旗標未在 onDisappear 重置：heroCard（未連結）與 statusHeroCard（已連結）共用同一個 @State heroAppeared，使用者連結或取消連結載具後，新英雄卡 onAppear 時旗標已為 true，導致進場動畫（opacity 0→1、Y 偏移）完全不播放；補 .onDisappear { heroAppeared = false } 於兩處，對齊 v22.24 FamilyView statsAppeared 同型修復規格。② statusHeroCard KPI 計算重複過濾 importHistory：monthCount 與 monthTotal 各自呼叫 filter { invDate >= monthStart }，造成 O(2n) 雙重遍歷；改為先 let monthFiltered = ...filter{ ... } 再分別取 .count / .reduce，降至 O(n)。其餘防護機制（force unwrap 全無、as! 全無、fatalError 僅 EInvoiceClient 啟動守衛、CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、所有 @Published 更新主執行緒隔離）均確認正常。"
        ]),
        ChangelogEntry(version: "22.29", build: 498, date: "2026/06/21", notes: [
            "【UI 美化 v2】EInvoiceSetupView：① heroCard 加入第三顆散景裝飾圓（white.opacity(0.05), 55pt, blur:8）+ 頂部玻璃光澤高光覆層（LinearGradient [.white.opacity(0.18)→.clear] top→center），對齊 IncomeView / VariableExpenseView v4 三圓散景 + 玻璃光澤規格；② statusHeroCard 新增第二、三顆散景圓 + 玻璃光澤覆層 + 三欄 KPI 橫列（累計匯入 / 本月發票 / 本月支出），各含 28pt 漸層圓圖示及智慧量級金額，對齊 LifeOverviewView.statsStrip 設計規格；③ EInvoiceHistoryView.historyRow 日期升級為 calendar 圖示 + tertiarySystemFill Capsule 徽章、發票號碼改同規格膠囊，金額改用 ntdWanString 萬/億 智慧量級，對齊 CareerView / VariableExpenseView 設計語言；④ 卡片內所有 Divider() 升級為 Rectangle().fill(Color(.separator).opacity(0.20)).frame(height:0.5)，對齊全 App 分隔線規格。"
        ]),
        ChangelogEntry(version: "22.28", build: 497, date: "2026/06/21", notes: [
            "【靜態除錯】全面複查 78 個 Swift 檔，發現並修復一個問題：PhotoLightbox.onAppear（MultiPhotoGallery.swift）在 .onAppear 閉包中以 UIImage(contentsOfFile:) 同步讀取全解析度照片，在大圖時阻塞主執行緒並造成介面短暫凍結；改用 .task(id: url) + Task.detached(priority: .userInitiated) 背景讀取，對齊 v22.27 AsyncThumbnailView 已建立的非同步模式。同時補正 project.pbxproj 版本號（MARKETING_VERSION / CURRENT_PROJECT_VERSION 停留在 22.25/494，未隨 22.26、22.27 兩版 Changelog 更新），一併對齊至 22.28/497。其餘防護機制（強制解包全無、as! 全無、fatalError 僅 EInvoiceClient 啟動守衛、CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、visible[0] 均有 count>=2 外層守衛、dataStatBadgesAppeared 固定 3 元素、FullBackup 雙層 OOM 守衛、所有 @Published 更新主執行緒隔離）均確認正常。"
        ]),
        ChangelogEntry(version: "22.27", build: 496, date: "2026/06/20", notes: [
            "【靜態除錯】發現並修復五個問題：① FullBackup.restore()：manifest JSON 讀取長度（manifestLen）原無上限，損壞備份檔若 manifestLen 欄位超大會觸發 OOM；加入 50 MB 守衛，與既有附件 100 MB 守衛共同構成雙層防護。② SubscriptionManager.applyRemoteFreeAccess()：寫入 @Published remoteAllFree 未聲明執行緒隔離；加上 @MainActor，與兩個呼叫端既有的 DispatchQueue.main.async 一致。③ IncomeView.filteredIncomes：O(n log n) 排序 + 過濾為計算屬性，每次 body 重繪都重算；改為 cachedFilteredIncomes（@State），透過 .task(id: store.modifyID-category-keyword) 懶惰重建，只在資料或篩選條件改變時才排序。④ VariableExpenseView.filteredExpenses：同上模式，O(n) 過濾改為 cachedFilteredExpenses，新增 .task 快取。⑤ MultiPhotoGallery.thumbnail(for:)：UIImage(contentsOfFile:) 在 view body 的 @ViewBuilder 中同步讀檔，每次 ScrollView 重繪都阻塞主執行緒；抽出 AsyncThumbnailView，以 Task.detached(priority: .userInitiated) 背景讀取後回寫 @State image，首次渲染前顯示佔位符。其餘防護機制均確認正常。"
        ]),
        ChangelogEntry(version: "22.26", build: 495, date: "2026/06/20", notes: [
            "【UI 美化 v2】FamilyMembersResumeView / FamilyMemberDetailView：① hero card 加頂部玻璃光澤 overlay（white.opacity(0.18)→clear）；② eventsSection 升級 36pt 橘色漸層圖示圓（+ stroke 1pt），日期改 Capsule 徽章（tertiarySystemFill 底色），並加 stagger 入場動畫（0.06s/row）；③ memberGiftsSection 禮金子項目圖示圓從 32pt 升至 36pt（+ stroke 1pt），金額改 Capsule 徽章（pink.opacity(0.10) 底色 + stroke 0.6pt），新增 smartGiftAmount() 萬/億 智慧量級顯示；④ sectionHeader 計數徽章統一加 stroke 0.6pt 邊框；⑤ photoCard 加 shadow（black.opacity(0.06), radius 4）。"
        ]),
        ChangelogEntry(version: "22.25", build: 494, date: "2026/06/20", notes: [
            "【靜態除錯】全面複查 78 個 Swift 檔，發現並修復三個問題：① FullBackup.restore()：附件迴圈讀取失敗時原以 break 中斷，導致後續附件全部略過；改為 continue，讓其餘附件繼續還原。同時新增 100 MB 大小上限（att.size <= 100_000_000）守衛，防止損壞或惡意備份檔透過超大 size 欄位觸發 OOM。② BusinessCardView / BusinessCardDetailView：fmtDate() 每次呼叫都建立新的 DateFormatter，名片列表 render 時隨名片數量建立等量物件；改為 static let 快取，對齊 RealEstateView / FoodMapView / LifeFinanceView 等既有修復規格。③ ResumeView.body：allSorted（combinedMilestones + sorted，O(n log n)）在 isEmptyAll 判斷與 groupedSections / filteredByCategory 各呼叫一次，每次 body render 共 2 次；對齊 LifeOverviewView（let allMS 單次捕捉）規格，在 body 頂端以 let sorted = allSorted 一次計算後傳入 groupedList(_:) / filteredList(category:sorted:)，呼叫次數 2→1。其餘防護機制（force unwrap 全無、as! 全無、fatalError 僅 EInvoiceClient 啟動守衛、CloudKit 30 秒節流與 2 秒防抖、isSyncing 並行守衛、@Published 更新主執行緒隔離）均確認正常。"
        ]),
        ChangelogEntry(version: "22.24", build: 493, date: "2026/06/20", notes: [
            "【動畫修復】ChartView.loadChartData()：空白態脈衝旗標（trendEmptyPulse 等）已有歸零，但圓餅圖例行旗標（variablePieRowsAppeared / fixedPieRowsAppeared）與支出類型比例進場旗標（typeBreakdownAppeared）未歸零，導致切換時間區間後這三個進場動畫再也不播放。修復：一律在 isLoading=true 前同步歸零，確保每次重載後進場動畫能重新觸發。",
            "【動畫修復】SubordinateView v2：summaryStatsCard（summaryAppeared）與 activeSubordinatesSectionHeader（headerAppeared）缺少歸零路徑——當所有部屬被刪除後這兩個 section 從畫面移除，旗標卡在 true；再新增部屬時 section 重出現但 onAppear 找不到狀態變化，進場動畫不再播放。修復：補 .onChange(of: lifeStore.subordinates.isEmpty) 在列表歸零時重置旗標，對齊 FamilyView v22.11 同類修復規格。"
        ]),
        ChangelogEntry(version: "22.22", build: 492, date: "2026/06/20", notes: [
            "【CloudKit 閃爍修復】CloudKitManager.fetchChanges：原本在 fetchRecordZoneChangesResultBlock 中，無論成功或失敗均先發 KV/照片通知，導致 changeTokenExpired 重試路徑下各 Store 被觸發兩次 reloadFromCloud——第一次是不完整的部分資料，第二次才是完整資料，造成畫面閃爍。修復：將通知發送移入 .success 分支；changeTokenExpired 時完全略過通知直接重試，retry 成功後再一次性通知；zoneNotFound 與其他錯誤仍發已拉取的部分資料通知並回報失敗。",
            "【圓餅圖動畫修復】ChartView.pieChartBody：原本以 Chart(entries.indices, id: \\.self) 用陣列位置作為 SectorMark 的 identity，當某分類支出歸零從陣列消失、其餘分類位移時，SwiftUI 會將不同分類的扇形誤判為同一身分並執行錯誤的變形動畫。修復：改以內部 PieSlice: Identifiable（id = 分類 rawValue）取代 entries.indices，讓 Chart 依語意身分追蹤各扇形，分類出現/消失時正確執行淡入淡出而非錯位變形。"
        ]),
        ChangelogEntry(version: "22.21", build: 491, date: "2026/06/20", notes: [
            "【效能修復】VehicleDetailView.deleteVehicle：刪除車輛時原本對每筆連結的定期/變動支出各別呼叫一次 expenseStore.expenses.removeAll { }，N 筆支出觸發 N 次 @Published didSet → save() + pushAll()；對齊 RealEstateView.deleteEstate v20.5 修復規格，改為先收集所有連結 ID 至 Set<UUID>，最後一次 removeAll 完成，@Published 通知與磁碟 I/O 各從最多 N 次降為 1 次。"
        ]),
        ChangelogEntry(version: "22.19", build: 489, date: "2026/06/19", notes: [
            "【靜態掃描】全面複查 78 個 Swift 檔（強制解包、Optional 處理、型別錯誤、index 越界、retain cycle、競態條件、CloudKit 節流、畫面閃爍、效能瓶頸）：無 force unwrap（!）、無 as! 強制轉型、無 fatalError（EInvoiceClient 唯一一處為啟動期程式員錯誤守衛，屬正當用法）；所有陣列索引存取均有邊界守衛（validOffsets filter、compactMap、firstIndex、guard bounds）；所有非 singleton 閉包均以 [weak self] 捕捉，singleton 正確省略；CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、modifyKV 序列佇列重試均正常；@Published 更新全在主執行緒；MyCalendarView 每次 body render 最多 14 次 eventsOn()（heroIsToday=false 時 14 次，=true 時 7 次）符合預期；SubordinateView deptCache O(1) 查表已確認；FinanceChartView sortedStocks 一次捕捉已確認；VariableExpenseView / AddExpenseView 300ms 搜尋防抖已確認；OverviewView .task(id: modifyID) 快取更新機制已確認；StockDetailView sortedTransactions 4 次、sortedDividends 3 次呼叫因陣列極小（< 50 項）影響可忽略，不需修正；EInvoiceSyncManager @MainActor 批次 append 防止多次 didSet；NotificationManager enumerateFires 上限 61；無新問題。"
        ]),
        ChangelogEntry(version: "22.18", build: 488, date: "2026/06/19", notes: [
            "【UI 美化】StockDetailView v2：圖示圓 38pt → 44pt + stroke 細邊框（transactionRow / dividendRow）；種類標籤 RoundedRectangle → Capsule + stroke；損益/報酬率改彩色 Capsule 膠囊；summaryFooter / dividendsFooter 膠囊補入 stroke；空狀態升級為 40pt 圖示圓 + 說明文字；sectionHeader 色條升級為橙色漸層 + 計數膠囊；flashCard 股票代號升級為 Capsule；三個卡片補入 overlay 細邊框。"
        ]),
        ChangelogEntry(version: "22.17", build: 487, date: "2026/06/19", notes: [
            "【效能修復】MyCalendarView v2（最新美化提交）引入兩個效能 bug：① calendarHeroCard 內部呼叫 eventsOn() 8 次（今日 1 次 + 未來 7 天各 1 次），加上 weekPreviewSection 7 次、todayEventsSection 1 次，每次 body render 共 16 次 eventsOn()；② upcomingMilestones（O(n log n) filter+sort）在 calendarHeroCard 與 upcomingMilestonesSection 共被存取 6 次。修復：在 body 頂端預先計算 weekEventsMap（一次性 7 次 eventsOn()）與 upcomingMS（1 次）並向下傳參，將 calendarHeroCard / todayEventsSection / weekPreviewSection / upcomingMilestonesSection 由 computed property 改為接收預算資料的函式；當 selectedDate == 今天時共享同一份 weekEventsMap，eventsOn() 呼叫次數從 16 降為 7，upcomingMilestones 從 6 降為 1。"
        ]),
        ChangelogEntry(version: "22.16", build: 486, date: "2026/06/19", notes: [
            "【靜態除錯 v22.16】全面掃描後僅發現一個效能 bug：SubordinateView.sortedSubordinates 的 .department 排序在 sort closure 內每次比較都呼叫 departments.first(where:)（O(n) 線性掃描），導致整體排序退化為 O(n² log n)；對齊已有的 dateAdded 預計算模式，改在排序前一次性建立 deptCache: [UUID: String] 字典，比較時 O(1) 查表，同時移除已無用的 deptLabel() 輔助函式。其餘強制解包均由上游 guard/if-let 保護，CloudKit 節流（2 s debounce + 30 s cooldown）與 singleton retain cycle 均屬既有設計無需更動，FamilyView.onDisappear 重置動畫旗標為故意行為，未發現新問題。"
        ]),
        ChangelogEntry(version: "22.14", build: 484, date: "2026/06/19", notes: [
            "【崩潰修復】MyCalendarView：EKCalendarItem.title 型別為 String!，對其直接呼叫 .isEmpty 若 EventKit 回傳 nil 會 crash；改以 (ev.title ?? \"\") 先做 nil 合併再判斷。",
            "【強制解包修復】EInvoiceClient.swift endpoint：改用閉包初始化並加 fatalError 訊息，讓格式錯誤於啟動時立即可見。PaywallView / EInvoiceSetupView：三組 Apple/電子發票靜態 URL 從行內 URL(string:)! 改為 struct static let 常數，集中維護、語意清晰。",
            "【效能修復】SubordinateOverviewView：① `var calendar: Calendar { Calendar.current }` 改為 `let calendar = Calendar.current`，消除 todayLeaves / todayMeetings / todayTasks / isSameDay 等熱路徑每次存取都重建 Calendar 的開銷；② fmtTime / fmtDateTime 改用 static let DateFormatter，不再每次呼叫都分配新物件。",
            "【效能修復】LifeFinanceView / FinanceCardView：formatNumber / formatTwdShort / formatDate / fmtMonthYear / fmtYearMonthZh / fmtDate / fmtNum 等 7 個函式原先每次呼叫都建立新的 NumberFormatter 或 DateFormatter，改為 static let 單例後呼叫成本從 O(建立) 降為 O(1)。"
        ]),
        ChangelogEntry(version: "22.13", build: 483, date: "2026/06/19", notes: [
            "【靜態 Debug】全面複查 78 個 Swift 檔（強制解包、Optional 越界、retain cycle、競態條件、CloudKit 節流、畫面閃爍、效能瓶頸）。",
            "【效能修復】FinanceChartView.stockPerformanceSection：stocksSortedByProfitLoss（O(n log n) 排序）原本在 ForEach 資料源呼叫一次，再於每筆列的 Divider 判斷（i < stocksSortedByProfitLoss.count - 1）又各呼叫一次，共 N+1 次排序（10 筆股票 = 11 次）；改在 else 區塊頂端以 let sortedStocks = Array(stocksSortedByProfitLoss.enumerated()) 一次捕捉，ForEach 與 Divider 條件均改用 sortedStocks，排序次數從 N+1 降為 1。",
            "【效能修復】FinanceOverviewView.ntdAllocations：insuranceValueNTD（O(n) reduce over store.insurances）原本在函式內被呼叫 4 次（totalAssetsNTD 內一次 + if 判斷、value: 欄位、percentage: 計算各一次）；改在函式頂端以 let insVal = insuranceValueNTD 單次捕捉後全段共用，並內聯計算 total（不再透過 totalAssetsNTD 中轉），呼叫次數 4→1。",
            "【確認安全】CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛均正常；saveQueue.async 僅操作 value type 快照無 retain cycle；所有 @Published 更新均在主執行緒；無 force unwrap（!）、無 as! 強制轉型、無 fatalError；RenovationPhotoEditor v2 / RenovationStackViewer 美化程式碼確認安全。"
        ]),
        ChangelogEntry(version: "22.11", build: 481, date: "2026/06/18", notes: [
            "【靜態 Debug】全面複查 78 個 Swift 檔，找到並修復兩個問題：① FamilyView v2 statsStrip 缺少 onDisappear 重置 statsAppeared，導致所有成員被刪除後再新增時進場動畫不再播放（已補 .onDisappear { statsAppeared = false }）；② NotificationManager.enumerateFires safety 上限為 5000，但呼叫端只取前 60 筆，最多浪費 4940 次日期計算（已收緊至 61）。其餘防護機制（CloudKit 30 秒節流、2 秒防抖、isSyncing 守衛、isLoading 批次保護、force unwrap 全無、as! 全無、fatalError 全無）均確認正常。"
        ]),
        ChangelogEntry(version: "22.10", build: 480, date: "2026/06/18", notes: [
            "【版本號同步】project.pbxproj MARKETING_VERSION 已於先前提交升至 22.10，但 Changelog 最新條目仍為 22.9（build 479），版本顯示不一致；本次補齊 Changelog 條目並將 CURRENT_PROJECT_VERSION 從 479 遞增至 480，使兩者對齊。",
            "【靜態掃描】延續 build 479 對全 78 個 Swift 檔的完整複查（強制解包、Optional 鏈結、型別轉換、retain cycle、競態條件、CloudKit 節流、畫面閃爍、效能瓶頸）：無新問題。所有防護機制（CloudKit 30 秒節流、2 秒防抖、isSyncing 並行守衛、modifyKV 序列佇列重試、NSLock fetchLock、isLoading 批次寫入保護、lossyDecodeArray 彈性解碼）均確認正常運作。",
            "【確認安全】VehicleView miniBarAppeared 動畫冪等、applyDepreciation 值型快照無競態、StockView allocationMiniBar totalVal max(…,1) 防除零、scrollOffset 1pt 閾值節流、OverviewView .task(id: store.modifyID) 快取更新機制均正常；無 force unwrap（!）、無 as! 強制轉型、無 fatalError。"
        ]),
        ChangelogEntry(version: "22.9", build: 479, date: "2026/06/18", notes: [
            "【Build 號修復】project.pbxproj CURRENT_PROJECT_VERSION 在 VehicleView v3 提交（build 478）後未同步遞增，停留在 477，導致 MARKETING_VERSION（22.9）與 CURRENT_PROJECT_VERSION（477）不一致；修復 Debug/Release 兩個 buildSettings 區塊，版本號升至 build 479。",
            "【靜態掃描】全面複查 78 個 Swift 檔（強制解包、Optional 鏈結、型別轉換、retain cycle、競態條件、CloudKit 節流、畫面閃爍、效能瓶頸）：VehicleView v3 新增程式碼（miniBarAppeared DispatchQueue.main.asyncAfter 動畫觸發、glow overlay、fmtShort 所有呼叫端均傳正值、vehicleCard 圖示圓/膠囊 stroke）確認安全；StockView v3 allocationMiniBar glow overlay 確認安全；除 build 號不一致外無其他新問題。",
            "【確認安全】VehicleView applyDepreciation 以 value type 快照原地修改無競態、miniBarAppeared 設定為冪等操作不引發重複動畫；StockView allocationMiniBar totalVal = max(..., 1) 防除零、scrollOffset 以 > 1 pt 閾值節流重繪；CloudKit 30 秒節流、2 秒防抖、isSyncing 並行守衛、modifyKV 序列佇列重試均正常。"
        ]),
        ChangelogEntry(version: "22.9", build: 478, date: "2026/06/18", notes: [
            "【UI 美化】VehicleView v3：① summaryHeader 補入頂部玻璃光澤 LinearGradient [white.opacity(0.18), clear]，對齊全 App 英雄卡 glass shine 統一規格；② mini 估值彩條補入 glow overlay（白色頂光 + 底部柔化）+ 左展開 spring 動畫（miniBarAppeared scaleEffect），對齊 StockView.allocationMiniBar v3 / FinanceOverviewView.totalAssetsCard v4 規格；③ vehicleCard 圖示圓補入 stroke 細邊框，對齊 StockView / SavingsInsuranceView 圖示圓規格；④ 品牌、動力類型、折舊率三種 Capsule 補入 overlay stroke（0.6pt），對齊全 App 膠囊 stroke 均值規格；⑤ fmtShort「NT$%.0f萬」→「%.1f萬」，去掉多餘 NT$ 前綴並加 1 位小數，對齊 TaxOverviewView v3 / OverviewView.smartCurrency 顯示規格。"
        ]),
        ChangelogEntry(version: "22.8", build: 477, date: "2026/06/18", notes: [
            "【靜態掃描】全面複查 78 個 Swift 檔（強制解包、Optional 越界、型別轉換、retain cycle、競態條件、CloudKit 節流、畫面閃爍、效能瓶頸）：無 force unwrap（!）、無 as! 強制轉型、無 fatalError；所有陣列索引存取均有邊界守衛；所有非 singleton 閉包均以 [weak self] 捕捉。",
            "【確認正常】CloudKit 機制：pushAll 2 秒防抖（Timer on main）、syncNowIfDue 30 秒節流（lastSyncDate）、isSyncing 並行守衛、modifyKV 0.5 秒序列佇列重試、fetchLock NSLock 執行緒安全存取均正常運作。",
            "【確認正常】@ObservedObject singleton 誤用已全數修復（v22.4 MyCalendarView、v22.7 FoodMapView/ChildDetailView/AdminConsoleView/AddExpenseView）；LifeGoodApp 所有 singleton store 以 @StateObject 持有。",
            "【確認正常】EInvoiceSyncManager：批次 pendingExpenses/newHistoryRecords 單次 append、revert @MainActor 隔離、persistHistory 背景序列佇列均正常；SubscriptionManager listenForTransactions guard else continue（非 return）正常；BackupManager I/O 背景佇列正常。",
            "【確認正常】LifeStore isLoading 批次寫入保護、lossyDecodeArray 彈性解碼、save() 值型快照背景編碼均正常；ExpenseStore delete(at:from:) validOffsets 邊界守衛正常。",
            "【確認正常】AIService.decodeJSON firstBrace <= lastBrace 守衛（v20.3 修復）、speechRecognizer [req] 捕捉避免 @MainActor 跨執行緒存取均正常；ChartView 100ms Task.sleep 防抖與 Task.isCancelled 檢查正常。",
            "無新問題：所有防護機制均正常運作，本版為靜態驗證掃描，版本升至 22.8。"
        ]),
        ChangelogEntry(version: "22.7", build: 476, date: "2026/06/17", notes: [
            "【UI 穩定性修復】FoodMapView、ChildRecordEditorSheet（ChildDetailView）、AdminConsoleView、AddExpenseView 四個視圖：LocationProvider.shared、RemoteAdminManager.shared、SubscriptionManager.shared 均以 @ObservedObject 搭配行內 singleton 初始化，SwiftUI 不保證跨重繪週期穩定持有，可能在父視圖更新時丟棄觀察訂閱造成地圖/定位/訂閱狀態 UI 異常；與 v22.4 修復 MyCalendarView 的方式一致，改為 @StateObject。",
            "【靜態掃描】全面複查 78 個 Swift 檔（強制解包、Optional 越界、型別轉換、retain cycle、競態條件、CloudKit 節流、畫面閃爍、效能瓶頸）：無 force unwrap（!）、無 as! 強制轉型、無 fatalError；CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛均正常；HolographicBuildingView 最新美化程式碼（SceneKit weak 捕捉、Binding 讀寫路徑）確認安全；@ObservedObject singleton 誤用為本版唯一實質改動。"
        ]),
        ChangelogEntry(version: "22.4", build: 473, date: "2026/06/17", notes: [
            "【競態條件修復】CloudKitManager.modifyKV 重試路徑：原本用 DispatchQueue.global(qos:.utility).asyncAfter 安排重試，繞過 CloudKitManager 自有的 serial queue，導致同一 KV 記錄可能被並行寫入觸發 CKErrorServerRecordChanged 死循環；改為 self.queue.asyncAfter，確保所有重試仍在序列佇列內依序執行。",
            "【邏輯修復】SubscriptionManager.listenForTransactions：for-await 迴圈內 guard let self else { return } 的 return 會永久終止整個交易監聽迴圈，導致 self 若被提前釋放（理論上不應發生但防禦性正確）後所有未完成的 StoreKit 交易無法被 finish，重啟後持續重播；改為 continue 僅跳過當次迭代。",
            "【資料完整性修復】EInvoiceSyncManager.revert：撤銷已匯入發票時直接呼叫 removeAll 略過 ExpenseStore.delete(_:) 的 Expense.deletePhoto 路徑，若對應支出附有照片將造成孤立檔案殘留；修復為先逐筆呼叫 deletePhoto 清理照片，再執行 removeAll。",
            "【UI 穩定性修復】MyCalendarView（主視圖與 PersonalEventEditor）：AppleCalendarBridge.shared 與 LocationProvider.shared 均以 @ObservedObject 搭配行內初始化使用，SwiftUI 不保證跨重繪週期穩定持有，可能在父視圖更新時丟棄觀察訂閱造成 UI 狀態遺失；改為 @StateObject，符合 singleton 的正確 SwiftUI 持有語意。"
        ]),
        ChangelogEntry(version: "22.3", build: 472, date: "2026/06/17", notes: [
            "【修復警告】ChildDetailView.swift：第 1140 行 .onChange(of: photoItem) 使用已棄用的單參數語法（iOS 16 舊式），在 iOS 17+ 產生編譯器警告；改為雙參數新式語法 { _, _ in }，與全檔其他 onChange 保持一致。",
            "【靜態掃描】全面複查 78 個 Swift 檔（強制解包、Optional 越界、型別轉換、retain cycle、競態條件、CloudKit 節流、畫面閃爍、效能瓶頸）：無 force unwrap（!）、無 as! 強制轉型、無 fatalError；所有陣列索引存取均有邊界守衛（stackedHousePhotos/renovationStackedPhotos count>=2 守衛、diningMembersLabel count==1 守衛、dataStatBadgesAppeared 固定 3 元素）；CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛均正常；EInvoiceSyncManager 批次 append 與背景序列 persistHistory 均正常；RemoteAdmin singleton 無 [weak self] 兩處不影響記憶體正確性（已多版記錄）；deprecated onChange 修復為本版唯一實質改動。"
        ]),
        ChangelogEntry(version: "22.2", build: 471, date: "2026/06/17", notes: [
            "【效能修復】TaxOverviewView.body：totalTaxSaving（= taxSavingExpenses O(n) + reduce）在 annualSummaryCard 與 taxSavingSection 各自為 computed property，body 同時渲染時仍各算一次共 2 次；v21.9 僅在各 section 內部以 let 避免多次存取，未解決跨 section 重複；本次將兩個 computed property 改為 func(_ savingTotal: Double)，在 body 頂端以 let savingTotal = totalTaxSaving 單次計算後傳入，掃描次數 2→1，同時修正 v21.9 注釋中誤稱「整體降為 1 次」的說明不符實情。",
            "【效能修復】FinanceOverviewView.body：ntdAllocations（含 4 次 O(n) reduce + sort）在 totalAssetsCard 與 allocationSection 各為 computed property，body 同時渲染時各算一次共 2 次；v2 注釋雖有「合併兩個 ntdAllocations 呼叫為一次」但僅合併 allocationSection 內部、未解決跨 section 重複；本次將兩個 computed property 改為 func(_ allocations: [AssetAllocation])，在 body 頂端以 let allocations = ntdAllocations 單次計算後傳入，掃描次數 2→1。"
        ]),
        ChangelogEntry(version: "22.1", build: 470, date: "2026/06/16", notes: [
            "【效能修復】ChildDetailView.consumptionSection：consumptionExpenses（雙重 filter + sort 全支出，O(n log n)）原本在 section 內被呼叫 8 次——count 判斷×2、isEmpty 判斷×2、reduce 合計×1、prefix(20) 取資料×1、count Divider 判斷×1、count 超量提示×1；改在 consumptionSection 頂端以 let exps = consumptionExpenses 單次捕捉後全段共用（對齊 dailyContent 的 let gifts = childGifts 既有規格），掃描次數 8→1。",
            "【靜態掃描】全面複查 78 個 Swift 檔：無強制解包越界、無新增 retain cycle、CloudKit 30 秒節流與 2 秒防抖均正常；消費段落修復為本版唯一實質改動。"
        ]),
        ChangelogEntry(version: "21.9", build: 469, date: "2026/06/16", notes: [
            "【效能修復】TaxOverviewView.annualSummaryCard：totalTaxSaving（= taxSavingExpenses O(n) + 10×fixed 掃描）被 body 分別在 annualSummaryCard 與 taxSavingSection 各計算一次（共 2 次）；在 annualSummaryCard 頂端加入 let savingTotal = totalTaxSaving，統計格改用 savingTotal，21.8 已修 taxSavingSection 側，本次補齊 annualSummaryCard 側，整體降為 1 次計算。",
            "【效能修復】ChildDetailView.dailyContent + childGiftsSection：childGifts（雙重 filter + sort 全支出）在 isEmpty 判斷（dailyContent 內）與 childGiftsSection 入口各呼叫一次，共 2 次；將 childGiftsSection 從 computed property 改為接受 [Expense] 參數的 func，dailyContent 頂端以 let gifts = childGifts 單次捕捉後傳入，掃描次數 2→1。"
        ]),
        ChangelogEntry(version: "21.8", build: 468, date: "2026/06/16", notes: [
            "【效能修復】ChildDetailView.childGiftsSection：childGifts（雙重 filter + sort 全支出）原本在 isEmpty 判斷、reduce、count、8 個 SocialSubCategory ForEach 內共被呼叫 10 次；改在 childGiftsSection 頂端以 let gifts = childGifts 單次捕捉後共用，掃描次數從 10 次降至 1 次。",
            "【效能修復】TaxOverviewView.totalTaxSaving：原實作對 taxSavingExpenses（O(n) filter+sort）逐一呼叫 10 個 TaxSavingSubCategory，共計 10 次 O(n) 掃描；改以一次 reduce 加總全量直接支出（等價於 10 個子分類之和），掃描次數 10→1。",
            "【效能修復】TaxOverviewView.taxSavingSection：totalTaxSaving 被呼叫 3 次（sectionHeader 條件、isEmpty 判斷、fmt 顯示）；改以 let savingTotal = totalTaxSaving 在 section 頂端單次捕捉後共用；同步移除 sectionHeader 中恒回傳 nil 的無效三元運算。"
        ]),
        ChangelogEntry(version: "21.7", build: 467, date: "2026/06/16", notes: [
            "【效能修復】OverviewView.monthlyBalanceCard：spendingRatio / spendingBarColor 為 struct-level computed property，在 body 內被存取 10+ 次，每次均重新執行 currentMonthTotal（= currentMonthVariableTotal + currentMonthFixedTotal，各含一次 O(n) 掃描）；移除兩個 computed property，改在 monthlyBalanceCard 頂端以 let total / spendingRatio / barColor 各算一次，GeometryReader 等閉包直接捕捉局部常數。",
            "【效能修復】OverviewView.todayCard：store.todayTotal（O(n) filter + 固定日均計算）被呼叫兩次；改以 let todayTotal = store.todayTotal 單次捕捉後共用，呼叫次數 2→1。"
        ]),
        ChangelogEntry(version: "21.6", build: 466, date: "2026/06/16", notes: [
            "【UI 美化】ChildrenResumeView：新增粉藍漸層英雄統計卡（兒子/女兒/生涯紀錄 KPI 三格）、玻璃光澤與 bokeh 裝飾圓、入場 spring 動畫。",
            "【UI 美化】ChildrenResumeView：新增「兒女清單」Section Header（Capsule 漸層側條 + 位數徽章）。",
            "【UI 美化】ChildrenResumeView：兒女卡片頭像圓圈新增 0.75pt stroke 細邊框，與全 App v3 圖示標準一致。",
            "【UI 美化】ChildrenResumeView：啟用 .navigationBarTitleDisplayMode(.large) 大標題模式。"
        ]),
        ChangelogEntry(version: "21.5", build: 465, date: "2026/06/16", notes: [
            "【靜態 Debug】全面複查 78 個 Swift 檔（強制解包、Optional 鏈結、retain cycle、競態條件、CloudKit 節流、畫面閃爍、效能瓶頸）。",
            "【確認安全】無 force unwrap（!）、無 as! 型別轉換、無 fatalError；所有陣列索引存取均有邊界守衛；所有閉包以 [weak self] 捕捉。",
            "【確認正常】RealEstateDetailView.gallerySummary 與 renovationPhotosContent 各自呼叫 linkedExpensePhotos 一次（O(n) 過濾），合計 O(2n)，無 O(n²) 問題。",
            "【確認正常】CloudKit 30 秒節流（syncNowIfDue）、pushAll 2 秒防抖、isSyncing 並發守衛、modifyKV 0.5 秒重試延遲均正確運作。",
            "【確認正常】LifeStore / FinanceStore / ExpenseStore 所有批次寫入均以 isLoading 旗標保護；所有 @Published 更新均在主執行緒執行。",
            "【確認正常】LifeOverviewView.body 以 let allMS = store.combinedMilestones(...) 單次捕捉里程碑，不重複計算；ExpenseStore 圖表方法均為 O(n) 預分組。",
            "無新問題：全部防護機制均正常運作，本版為靜態驗證掃描。"
        ]),
        ChangelogEntry(version: "21.4", build: 464, date: "2026/06/16", notes: [
            "【靜態 Debug】全面複查 78 個 Swift 檔（強制解包、Optional 鏈結、retain cycle、競態條件、CloudKit 節流、畫面閃爍、效能瓶頸）。",
            "【確認安全】所有陣列索引存取均有邊界守衛；無 force unwrap（!）、無 as! 型別轉換、無 fatalError 呼叫。",
            "【確認安全】所有閉包均以 [weak self] 捕捉；RemoteAdmin singleton 兩處缺少 [weak self] 的 DispatchQueue.main.async 不影響記憶體正確性（沿用既有記錄）。",
            "【確認正常】CloudKit 30 秒節流（syncNowIfDue）、pushAll 2 秒防抖、isSyncing 並發守衛均正確運作，scenePhase 切換不觸發額外同步。",
            "【確認正常】LifeStore / FinanceStore / ExpenseStore 所有批次寫入均以 isLoading 旗標保護；所有 @Published 屬性更新均在主執行緒執行。",
            "【確認正常】圖表資料預分組（O(n)）、VariableExpenseView 搜尋 300ms 防抖、ChartView 100ms 更新聚合與獨立空狀態旗標均正常。",
            "無新問題：全部防護機制均正常運作，本版為靜態驗證掃描。"
        ]),
        ChangelogEntry(version: "21.2", build: 462, date: "2026/06/15", notes: [
            "【效能修復】FoodMapView.topOverlay：companionOptions（O(n) 掃描所有支出）原本被呼叫兩次——isEmpty 判斷一次、ForEach 資料源一次；改以 let options = companionOptions 在 topOverlay 頂端單次捕捉後共用，降至 1 次掃描。",
            "【效能修復】FoodMapView.statsCard：原本為 var，內部以 let aggs = aggregates 獨立呼叫一次 aggregates（O(n) 聚合）；listSheet 中已有 let items = sortedAggregates 捕捉過一次 aggregates，statsCard 另外再算一次造成重複。改為 statsCard(_ aggs:) 函式接收外部傳入的 items，listSheet 改呼叫 statsCard(items)，消除清單 sheet 開啟時 aggregates 被呼叫兩次的多餘計算。",
            "【效能修復】FoodMapView.fmtRelative：日期超過 30 天時以 let f = DateFormatter() 在函式內建立一次性物件，清單 render 時每列各建一個（DateFormatter 建立成本高）；新增 static let relativeDateFormatter 快取，對齊同檔 decimalFormatter / RestaurantDetailSheet.dateFormatter 的既有做法。",
            "【靜態掃描】全面複查 78 個 Swift 檔：除上述三處外，無新增強制解包越界、retain cycle、@Published 競態條件或 CloudKit 節流問題。"
        ]),
        ChangelogEntry(version: "21.1", build: 461, date: "2026/06/15", notes: [
            "【效能修復】FoodMapView：aggregates 計算屬性在每次 body rebuild 中原本被呼叫 2+2N 次（N＝餐廳數量）——body 中 isEmpty/onChange/ForEach 各 1 次，加上 pinSize(for:) 透過 maxVisitCount 每個 annotation 呼叫 2 次。50 間餐廳時達 102 次重複計算。",
            "【效能修復】修復方式：body 以 let aggs = aggregates 單次捕捉；mapLayer var 改為 mapContent(_ aggs:) 函式並於內部一次計算 maxCount；pinSize(for:) 改為 pinSize(for:maxCount:) 接收外部傳入的 maxCount，不再反查 aggregates；bottomOverlay var 改為 bottomOverlay(count:) 函式，移除對 sortedAggregates 的額外呼叫。",
            "【效能修復】tryInitialCenter()：原本對 aggregates 呼叫 3 次（isEmpty + latitude map + longitude map），改以 let aggs = aggregates 在函式頂端單次捕捉後共用。",
            "修復後每次 body render 呼叫 aggregates 次數：50 間餐廳時從 102 次降至 1 次。"
        ]),
        ChangelogEntry(version: "20.9", build: 459, date: "2026/06/15", notes: [
            "【效能修復】TaxOverviewView.annualSummaryCard：taxExpenses（O(n log n) filter+sort）原本透過 totalTax 被呼叫 3 次、再加 taxExpenses.count 直接呼叫 1 次，共 4 次重複計算；改在 annualSummaryCard 頂端以 let exps = taxExpenses / let taxTotal = exps.reduce(0) 各計算一次後全段共用，同時移除已無呼叫者的 totalTax 計算屬性。",
            "【效能修復】TaxOverviewView.monthlyBreakdown：taxByMonth（內部含 taxExpenses O(n log n)）原本在同一 @ViewBuilder 區塊被呼叫 4 次（isEmpty 判斷、count 標頭、max 計算、ForEach 資料源）；改以 let byMonth = taxByMonth 在判斷前一次捕捉，降至 1 次計算，對齊 v20.0 taxByMonth 迴圈修復規格。",
            "【靜態掃描】全面複查 78 個 Swift 檔：除上述兩處外，無強制解包越界、無新增 retain cycle、@Published 屬性均在主執行緒更新、CloudKit 30 秒節流與 2 秒防抖均正常。"
        ]),
        ChangelogEntry(version: "20.8", build: 458, date: "2026/06/15", notes: [
            "【靜態 Debug】全面複查 78 個 Swift 檔（強制解包、Optional 鏈結、retain cycle、競態條件、CloudKit 節流、畫面閃爍、效能瓶頸）。",
            "【確認安全】所有閉包均正確使用 [weak self]；RemoteAdmin 兩處缺少 [weak self] 的 DispatchQueue.main.async 為 singleton，不影響記憶體安全性（沿用 v20.5 記錄）。",
            "【確認安全】NotificationManager.recurrenceLabel：names[wd - 1] 存取前已以 wd >= 1, wd <= 7 守衛保護；FinanceModels.seedTransactionsFromLegacyIfNeeded：seeds.first 以 if let 安全解包。",
            "【確認正常】CloudKit 30 秒節流（syncNowIfDue）、pushAll 2 秒防抖、modifyKV 0.5 秒延遲重試均正常；ChartView 四個獨立空狀態脈衝旗標（v20.7）運作正確。",
            "【確認正常】VariableExpenseView 搜尋 300ms 防抖、FixedExpenseView NSCache 格式器、.task(id: store.modifyID) 快取更新均正常，無多餘計算。",
            "無新問題：全部防護機制均正常運作，本版為靜態驗證掃描。"
        ]),
        ChangelogEntry(version: "20.7", build: 457, date: "2026/06/15", notes: [
            "【修復】SubscriptionManager.refreshStatus：多訂閱方案並存時改保留到期日最晚者，避免月費方案覆蓋年費方案導致 isPremium 提早回傳 false。",
            "【修復】AIService.startRecording：語音辨識 Task 完成回呼發生錯誤時自動呼叫 stopRecording()，防止 isRecording 卡在 true 造成麥克風指示燈永遠亮著。",
            "【修復】EInvoiceSyncManager.revert：補標 @MainActor，確保 expenseStore.expenses（@Published）一律在主執行緒修改。",
            "【修復】ChartView 畫面閃爍：將共用的 pieEmptyPulse 拆分為 trendEmptyPulse／variablePieEmptyPulse／fixedPieEmptyPulse／typeBreakdownEmptyPulse 四個獨立旗標；隱形量測層同時渲染三個圖表時各自管理動畫，不再互搶旗標造成 resetAll → 重新動畫的閃爍循環。",
        ]),
        ChangelogEntry(version: "20.6", build: 456, date: "2026/06/14", notes: [
            "【靜態 Debug】全面複查 78 個 Swift 檔（強制解包、Optional 鏈結、retain cycle、競態條件、CloudKit 節流、畫面閃爍、效能瓶頸）。",
            "【確認安全】NotificationManager.recurrenceLabel：names[wd - 1] 存取前已以 wd >= 1, wd <= 7 守衛保護，無越界風險。",
            "【確認安全】EInvoiceSyncManager.performSync：類別標注 @MainActor 且方法非 nonisolated，async 掛起後仍回主執行緒；importHistory.insert / expenseStore.expenses.append 均在主執行緒執行，無競態條件。",
            "【確認安全】LifeStore 所有 CRUD（update/delete）以 firstIndex 取得索引後立即寫入，全程在主執行緒；isLoading 旗標正確批次保護多步驟寫入，避免中間態被持久化。",
            "【確認安全】BackupManager：外層 DispatchQueue.global.async 以 [weak self] 捕捉，內層 DispatchQueue.main.async 透過 self? 選用鏈安全存取，無 retain cycle。",
            "【確認安全】RemoteAdmin：缺少 [weak self] 的 DispatchQueue.main.async 均屬 singleton，永不釋放，記憶體正確性不受影響（與 v20.5 記錄一致）。",
            "【確認正常】CloudKit 30 秒節流（syncNowIfDue）、pushAll 2 秒防抖、modifyKV 0.5 秒延遲均正常，scenePhase 切換不會觸發超出節流的額外同步。",
            "【確認正常】OverviewView.categoryBreakdownSection：store.variableCategoryTotals() 每次 body render 僅呼叫一次（O(n) 掃描，< 1ms），前次掃描未覆蓋此函式；確認與 recentItems 同屬一次計算，無需額外快取。",
            "【確認正常】RealEstateView.deleteEstate（v20.5 修復）、FixedExpenseView.cachedGroupedByCategory（v20.4）、VariableExpenseView.debouncedSearchText（v20.4）均已正確實作，功能正常。",
            "無新問題：全部防護機制均正常運作，本版為靜態驗證掃描。"
        ]),
        ChangelogEntry(version: "20.5", build: 455, date: "2026/06/14", notes: [
            "【效能修復】RealEstateView.deleteEstate：刪除不動產時原本對每筆關聯支出 ID 各別呼叫一次 expenseStore.expenses.removeAll { }，最多觸發 9 次 @Published 更新與 9 次 save() 磁碟寫入；改為先收集所有 ID 至 Set<UUID>，最後一次 removeAll 完成，將 @Published 通知與磁碟 I/O 各從最多 9 次降為 1 次。",
            "【效能修復】FamilyMemberDetailView.photosSection：ForEach 內 inline member.familyPhotos.sorted { } 每次 view body 求值都建立新陣列；抽成 sortedFamilyPhotos computed property，使程式意圖更清晰，並讓未來可在此處加入 @State 快取時有明確切入點。",
            "【靜態掃描】全面複查 78 個 Swift 檔：stackedHousePhotos / renovationStackedPhotos 的 visible[0] 存取均由呼叫端 count >= 2 守衛保護，實際安全；RemoteAdmin.writeConfig 第 188 行 DispatchQueue.main.async 缺少 [weak self]，因 RemoteAdmin 為 singleton 不影響記憶體正確性，記錄備查但不修改以避免過度改動；其餘強制解包、Optional 鏈結、CloudKit 節流、競態條件均未發現新問題。"
        ]),
        ChangelogEntry(version: "20.4", build: 454, date: "2026/06/14", notes: [
            "【效能】FixedExpenseView.groupedByCategory：從每次 body render 時當場執行 O(n log n) 分組排序，改為 @State cachedGroupedByCategory + .task(id: store.modifyID) 觸發更新；修正當 store.incomes 或 store.currencyRates 等與固定支出無關的 @Published 屬性變動時，仍重複執行分組排序的多餘計算。",
            "【效能】VariableExpenseView.filteredExpenses：搜尋過濾從每次按鍵立即以 searchText 觸發 O(n×8) 字串比對，改為 debouncedSearchText + 300ms 防抖 Task，對齊 AddExpenseView.completerDebounceTask 既有規格，避免快速輸入時連續觸發高頻過濾運算。",
            "【效能】IncomeView.filteredIncomes：同上，搜尋過濾加入 300ms 防抖（debouncedSearchText），對齊 VariableExpenseView 規格，減少輸入時 O(n log n) sort + O(n×3) filter 的重複觸發。"
        ]),
        ChangelogEntry(version: "20.3", build: 453, date: "2026/06/14", notes: [
            "【修正 Crash】AIService.decodeJSON：AI 回傳字串中若 } 出現於 { 之前（如錯誤訊息 \"}...{\" 格式），原本的 firstBrace...lastBrace 形成逆向 ClosedRange，Swift 在 String.subscript 處 fatal error；補上 firstBrace <= lastBrace 防衛條件，改拋 AIParseError.invalidResponse 而非崩潰。",
            "【靜態掃描】全面複查 78 個 Swift 檔：CloudKitManager NSLock 區段均為簡單值型別寫入（無 throw），無 deadlock 風險；LifeStore 的 guard let si/ti firstIndex 模式、FinanceModels.seedTransactionsFromLegacyIfNeeded 的 seeds.first if-let 均有 Optional 保護；EInvoiceSyncManager.persistHistory() 已透過 persistQueue.async 卸載磁碟 I/O；ChartView 以 @State variableBreakdownCache/fixedBreakdownCache + onChange 觸發更新，無多餘重繪；CloudKit 30 秒節流、pushAll 2 秒防抖均正常。"
        ]),
        ChangelogEntry(version: "20.2", build: 452, date: "2026/06/14", notes: [
            "【UI 美化】IncomeView v3：incomeRow 存入銀行標籤前景色從 .secondary 升級為分類主題色（accent.opacity(0.85)），背景從 tertiarySystemFill 升級為 accent.opacity(0.08)，對齊 ExpenseRow.diningMember 膠囊設計語言。",
            "【UI 美化】IncomeView v3：incomeRow 加入股票連結指示（chart.line.uptrend.xyaxis 11pt 藍色圖示），當 income.linkedStockId 不為 nil 時顯示，告知使用者該筆收入已連結股票配息，對齊 ExpenseRow.mappin 地點指示規格。",
            "【UI 美化】IncomeView v3：incomeListSections 新增月份分頁展開（visibleMonths 預設 3），非搜尋狀態下只顯示近 3 個月收入，超出部分以「展開更早三個月」按鈕 + 隱藏筆數膠囊呈現，對齊 VariableExpenseView.expenseListSectionsFor 的 visibleWeeks 分頁規格。"
        ]),
        ChangelogEntry(version: "20.1", build: 451, date: "2026/06/14", notes: [
            "【靜態 Debug】全面掃描 78 個 Swift 檔，確認本分支無強制解包（force unwrap）、無 as! 強制轉型、無陣列 index 越界風險。",
            "【記憶體安全】確認所有閉包（CloudKit callback、Timer、SpeechRecognizer 語音辨識、SubscriptionManager 交易監聽）均以 [weak self] 保護，無 retain cycle。",
            "【競態條件】確認 CloudKitManager.refreshAccountStatus 回主執行緒後才寫入 accountStatus；saveQueue.async 僅操作 value type 快照；NSLock fetchLock 正確保護 Set 並行寫入。",
            "【CloudKit 節流】確認 syncNowIfDue 30 秒節流、pushAll 2 秒防抖、modifyKV 0.5 秒延遲重試均完整運作，無閃爍風險。",
            "【@Published 批次更新】確認 isLoading 旗標在多筆寫入期間阻擋 didSet→save() 連鎖；EInvoiceSyncManager.performSync 以 pendingExpenses 一次性 append，只觸發一次 CloudKit push。",
            "【效能確認】ExpenseStore 圖表資料（dailyData/weeklyData/monthlyData）已以 O(n) 分組取代 O(n×周期數) 逐區間 filter；LifeStore.backfillOrgPeopleFromSubordinates 以 Set 加速連結查詢至 O(1)。",
            "無需修改：以上所有防護機制均正常，本版為靜態驗證掃描。"
        ]),
        ChangelogEntry(version: "20.0", build: 450, date: "2026/06/13", notes: [
            "【效能】TaxOverviewView.taxByMonth：修正迴圈內每次迭代各自呼叫 taxExpenses（filter+sort）共 12 次的重複計算；改以 let exps = taxExpenses 在迴圈外一次捕捉，降至 1 次 O(n log n)。",
            "【效能】TaxOverviewView.taxRecordsSection：修正 taxExpenses 在同一 section 內被多次呼叫（含 ForEach 每列一次的 count-1 判斷）；改以 let exps = taxExpenses 提前捕捉並全段共用，消除 N+3 次重複計算。",
            "【效能】FinanceOverviewView.allocationSection：修正 ntdAllocations 在同一 view builder 中被呼叫兩次（allocationsForHeader + allocations）；合併為單一 let allocations = ntdAllocations，避免重複排序。",
            "靜態掃描其餘 75 個 Swift 檔：無強制解包越界、無新增 retain cycle、CloudKit 30s 節流與 2s 防抖均正常，無需額外修改。"
        ]),
        ChangelogEntry(version: "19.9", build: 449, date: "2026/06/13", notes: [
            "靜態掃描全部 Swift 檔：確認無強制解包越界、Optional 鏈式呼叫安全、所有 retain cycle 已以 [weak self] 處置、@Published 屬性皆在主執行緒更新。",
            "確認 CloudKit 30 秒節流（syncNowIfDue）與 2 秒防抖（pushAll）正常，無新增閃爍或重複同步風險。",
            "確認 OverviewView.recentItems 已透過 let items = recentItems 在 recentTransactionsSection 內一次捕捉，每次 body render 僅排序一次，無重複計算問題。",
            "確認 saveQueue.async 串行背景佇列僅操作 value type 快照，無競態條件；NSLock fetchLock 正確保護 CloudKit fetch callback 中的 Set 寫入。",
            "無需修改：本版為純靜態驗證掃描，所有既有防護機制均正常運作。"
        ]),
        ChangelogEntry(version: "19.8", build: 448, date: "2026/06/13", notes: [
            "【修正】TaxOverviewView 切換年份時動畫旗標未完整重置：yearPicker 按鈕僅重置 heroCardAppeared/monthBarAppeared，taxRowsAppeared、checklistRowsAppeared、tipsRowsAppeared、emptyIconPulse 未歸零。導致第二次切換至無資料年份時，空狀態脈衝動畫（repeatForever，value: emptyIconPulse）因值未改變而靜止不動；同時切換有資料年份時各列進場 stagger 動畫亦不重播。新增 .onChange(of: selectedYear) 補齊全部旗標重置，並在 0.08 s 後重播列項進場動畫，對齊英雄卡片節奏。"
        ]),
        ChangelogEntry(version: "19.7", build: 447, date: "2026/06/13", notes: [
            "【修正】CareerView 薪資調整百分比顯示 bug：降薪時格式字串 \"▼ %.1f%%\" 帶入負數 pct 導致輸出「▼ -5.3%」，▼ 與 - 號重複。改用 abs(pct) 輸出「▼ 5.3%」，方向由箭頭表達，移除冗餘負號。",
            "【效能】FoodMapView.statsCard 中 aggregates 原本被獨立呼叫三次（reduce×2 + max），每次均重新篩選/聚合全部飲食支出；改在函式頂端捕捉 let aggs = aggregates，共用一份結果，降低為一次 O(n) 聚合。",
            "【效能/UI】FoodMapView.listSheet 中 sortedAggregates 原本在 ForEach 與 navigationTitle 各自呼叫一次；改以 let items = sortedAggregates 捕捉後共用，避免重複排序。同時修正 statsCardAppeared 缺少 onDisappear 重置，導致第二次開啟清單 sheet 時進場動畫不再播放。"
        ]),
        ChangelogEntry(version: "19.5", build: 445, date: "2026/06/13", notes: [
            "【修正】FoodMapView 同行者篩選邏輯錯誤：companionOptions 與 foodExpensesWithLocation 原本只以 ASCII 逗號（,）分割 diningMember，導致 AI 語音記帳以全型頓號（、）分隔的同行者無法正確拆解，同行者篩選 chip 完全失效；改用 CharacterSet(\",、，\")，對齊 topCompanion 的作法。",
            "【效能】FoodMapView 地圖 pin 大小計算從 O(n²) 降至 O(n)：pinSize(for:) 原本對每個 annotation 都重新呼叫 aggregates.map(.visitCount).max()（每次完整重跑聚合），改為快取 maxVisitCount computed property 只計算一次。",
            "【效能】FoodMapView / RestaurantDetailSheet 的 fmtShort、fmtNum、fmtDate 改用 static let 快取 NumberFormatter / DateFormatter，不再每次呼叫都建立新物件（NumberFormatter 建立成本高，清單 render 時大量建立會造成短暫卡頓）。"
        ]),
        ChangelogEntry(version: "19.4", build: 444, date: "2026/06/12", notes: [
            "【UI 美化】CareerView v2：careerRow 日期從純 .caption2 文字升級為彩色 Capsule 徽章，對齊 SpouseResumeView / OverviewView.recentRow 日期標籤規格。",
            "【UI 美化】CareerView v2：salaryAdjust 薪資漲跌百分比改用彩色 Capsule 膠囊（綠漲/紅跌）+ 前後金額以 .caption2.secondary 輔助顯示，提升資訊層次，對齊 IncomeView.incomeRow 數值排版。",
            "【UI 美化】CareerView v2：summaryCard 數值字型由 .subheadline.bold() 升至 .system(size:15,weight:.bold,design:.rounded) + minimumScaleFactor(0.72)，對齊 OverviewView.summaryCard 金額字型規格。"
        ]),
        ChangelogEntry(version: "19.3", build: 443, date: "2026/06/12", notes: [
            "靜態層級全面 debug 掃描（78 個 Swift 檔）：確認強制解包已消除、Optional 鏈式呼叫安全、所有 retain cycle 已以 [weak self] 處理、@Published 屬性皆在主執行緒更新。",
            "確認 CloudKit 同步維持 30 秒節流（syncNowIfDue）及 2 秒防抖（pushAll），無新增閃爍風險。",
            "確認 19.2 各項修復（StockView scrollOffset 門檻、FixedExpenseView NSCache、RealEstateView static formatter、MyCalendarView 地點搜尋防抖）均已正確實作；版本號由 build 442 升至 443。"
        ]),
        ChangelogEntry(version: "19.2", build: 442, date: "2026/06/12", notes: [
            "修正：EInvoiceSyncManager.persistHistory() 將 JSON 序列化與寫檔移至背景序列佇列，避免在 @MainActor（主執行緒）做同步 I/O 造成短暫卡頓。",
            "修正：RealEstateView.fmt() 改用三個 static 快取 NumberFormatter，不再每次呼叫建立新的重量級格式器（防止列表 render 時大量建立物件）。",
            "修正：StockView scrollOffset 更新加入 1pt 門檻（差值 ≤1pt 不更新），避免每個 scroll frame 都觸發全量 body 重繪，改善捲動流暢度。",
            "修正：FixedExpenseView.currencyFormatterCache 由 static Dictionary 改為 NSCache，可受系統記憶體壓力自動釋放，消除無限增長的記憶體洩漏。",
            "修正：MyCalendarView 地點搜尋 onChange 補上 300ms 防抖（對齊 AddExpenseView 設計），避免每次按鍵都立即觸發 MKLocalSearchCompleter 查詢。"
        ]),
        ChangelogEntry(version: "18.99", build: 440, date: "2026/06/12", notes: [
            "修正：SpeechRecognizer.startRecording() 在 recognizer 為 nil（裝置不支援 zh-TW 語音辨識）時，不再啟動音訊 session；改為顯示錯誤訊息，避免麥克風佔用卻無實際轉錄。",
            "修正：FullBackup.magicData 改為 static let（從 static var 計算屬性改為儲存屬性），消除每次存取時的 force-unwrap 與重複建立 Data 物件。"
        ]),
        ChangelogEntry(version: "18.98", build: 439, date: "2026/06/12", notes: [
            "修正：uploadPhoto 忽略 CloudKit fetch 錯誤，網路異常時改為提前回報、不再以空 CKRecord 強行儲存（避免不必要的 serverRecordChanged 衝突）。",
            "修正：AI 記帳同行者欄位，純空白輸入現在正確回傳 nil，不再存入無效空白字串。"
        ]),
        ChangelogEntry(version: "18.97", build: 438, date: "2026/06/11", notes: [
            "完整備份匯出時，底部導覽上方顯示細進度條 + 小百分比，不影響操作。"
        ]),
        ChangelogEntry(version: "18.96", build: 437, date: "2026/06/11", notes: [
            "新增『完整備份（含照片）』：把結構化資料 + 所有模組照片/文件打包成單一 .lifegood 檔，可重新匯入（合併/取代）。",
            "採自訂單一檔容器、串流寫入，照片很多也不會吃爆記憶體。"
        ]),
        ChangelogEntry(version: "18.95", build: 436, date: "2026/06/11", notes: [
            "房屋資料集錦改善大量照片的開啟效能：縮圖改用降採樣 + 背景非同步載入 + 記憶體快取，並改為懶載入（只載入畫面上看得到的），照片很多時不再卡頓。"
        ]),
        ChangelogEntry(version: "18.94", build: 435, date: "2026/06/11", notes: [
            "匯出 CSV 補齊房地產巢狀明細：樓層、資產物件（含子物件路徑）、貸款、已支出、變動支出、附屬資產、土地/建物權狀、保險、水電瓦斯、文件、電梯保養。"
        ]),
        ChangelogEntry(version: "18.93", build: 434, date: "2026/06/11", notes: [
            "管理控制台新增『版本更新紀錄』：可檢視歷代版本的更新內容（僅管理者可見）。"
        ]),
        ChangelogEntry(version: "18.77–18.91", build: 432, date: "2026/06/11", notes: [
            "多個頁面視覺美化（付費牆、多照片廊、班表事項列、固定/變動支出摘要卡等）。",
            "修正多個靜態分析發現的 bug，包含 ForEach 刪除項目造成的越界當機。"
        ]),
        ChangelogEntry(version: "18.75", build: 424, date: "2026/06/11", notes: [
            "修正：人生資料（家庭/部屬等）載入改為逐筆容錯解碼，單一壞紀錄不再讓整批資料消失。",
            "有機會自動救回先前『某版後消失』的兒女 / 家庭成員。"
        ]),
        ChangelogEntry(version: "18.73", build: 421, date: "2026/06/11", notes: [
            "房屋資料集錦照片：模糊填底改在白框內、不外溢。",
            "修正橫式照片會跑出螢幕的問題。"
        ]),
        ChangelogEntry(version: "18.72", build: 420, date: "2026/06/11", notes: [
            "人生總覽：個人看板改為隨內容一起捲動，不再固定佔用畫面。"
        ]),
        ChangelogEntry(version: "18.71", build: 419, date: "2026/06/11", notes: [
            "照片全螢幕檢視背景改用同張照片的高斯模糊，畫面不再死黑。"
        ]),
        ChangelogEntry(version: "18.70", build: 418, date: "2026/06/11", notes: [
            "推廣期間付費牆改為『全功能限時免費』文案，並說明早鳥永久保留。"
        ]),
        ChangelogEntry(version: "18.69", build: 417, date: "2026/06/11", notes: [
            "新增遠端『全功能免費』總開關 + 隱藏管理控制台（關於頁連點 20 下）。",
            "新增不重複 iCloud 使用者人數統計；早鳥永久保留解鎖。"
        ]),
        ChangelogEntry(version: "18.68", build: 416, date: "2026/06/11", notes: [
            "班表新增『日值班』班別（平日 08:30–17:30，可自訂）與單日設定按鈕。",
            "清除班別後自動回到班表頁。"
        ]),
        ChangelogEntry(version: "18.67", build: 415, date: "2026/06/11", notes: [
            "部屬總覽：點請假 / 會議 / 任務項目可直接開啟該項目的編輯畫面。"
        ]),
        ChangelogEntry(version: "18.56", build: 407, date: "2026/06/11", notes: [
            "新增『單獨匯出部屬資料』（含班表 / 任務 / 會議 / 請假）與合併匯入。"
        ]),
        ChangelogEntry(version: "18.55", build: 406, date: "2026/06/11", notes: [
            "部屬可設定『分廠區』；班表依廠區分段顯示。",
            "修正：編輯部屬時不再清掉已排好的班別。"
        ]),
        ChangelogEntry(version: "18.54", build: 405, date: "2026/06/11", notes: [
            "套用小夜班一律對齊整週一至五；套用大夜 / 小夜班後自動關閉彈窗回班表。"
        ]),
        ChangelogEntry(version: "18.53", build: 404, date: "2026/06/11", notes: [
            "班表套用範本改用中午錨點計算，修正跨時區可能的日期位移。"
        ]),
        ChangelogEntry(version: "18.51", build: 402, date: "2026/06/11", notes: [
            "班表新增『套用小夜班（5 天）』與獨立『清除班別』按鈕。"
        ]),
        ChangelogEntry(version: "17.79", build: 382, date: "2026/06/05", notes: [
            "iCloud 同步：把過去被吞掉的錯誤顯示在設定頁，方便排查。",
            "修正兩台裝置同時編輯同一筆資料時上傳衝突遺失更新的問題。"
        ]),
        ChangelogEntry(version: "17.77", build: 380, date: "2026/06/04", notes: [
            "新增『部屬班表』：棋盤式燈號（縱軸部屬、橫軸整月），可排大夜 / 小夜輪班、依部門篩選。"
        ])
    ]
}
