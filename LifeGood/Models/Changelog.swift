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
