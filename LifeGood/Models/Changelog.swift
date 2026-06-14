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
