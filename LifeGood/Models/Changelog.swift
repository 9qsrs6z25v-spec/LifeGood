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
        ChangelogEntry(version: "25.37", build: 790, date: "2026/07/31", notes: [
            "【美化】人才矩陣評分明細分隔線主題色收尾（TalentMatrixView.breakdownGroup）：breakdownCard 懸浮卡片內「主動性（日常）」「潛力（評分）」兩組評分明細，標題列下方原本沿用系統灰色 Divider()，是本檔案唯一還沒套用主題色分隔線的元素——同一張卡片外框、summaryHeroCard 內部分隔線都早已改用跟隨主題色的細線，與 .regularMaterial 卡片背景較協調（同型作法見 FamilyOverviewMap.HouseView／ChildVaccineScheduleView 既有規格）。改為 Rectangle().fill(color.opacity(0.20)).frame(height: 0.5)，跟隨呼叫端傳入的主動性／潛力主題色。純視覺層調整，分數計算與明細列內容等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.36", build: 789, date: "2026/07/31", notes: [
            "【靜態除錯 v25.36：修復部屬執掌設備「PM／警報時間軸」的 O(警報數×PM筆數) 線性掃描】SubordinateEquipmentTimelineSection.entries 為每一筆警報計算「發生前最近一次 PM」時，用 `pmDates.last(where: { $0 <= al.date })` 對該設備已排序的 pmDates 陣列逐一線性掃描——pmDates 明明已經 `.sorted()` 過，卻沒利用這個排序特性，是同一類「已排序資料卻仍線性掃描」問題（近兩輪 v25.26／v25.35 分別在部屬匯入合併與班表棋盤格修過），使該畫面重算成本隨單一設備的 PM／警報紀錄雙雙隨年資累積而變成 O(警報數 × PM筆數)。改為新增 lastDate(lessThanOrEqualTo:in:) 二分搜尋，對已排序的 pmDates 以 O(log n) 取代 O(n) 線性掃描，語意（取不晚於警報時間的最後一筆 PM 日期）與原本完全等價。純效能調整，時間軸顯示內容、天數計算、排序與其餘互動邏輯未變動。經全面複查 Models 全部檔案與 Views 其餘大型清單／地圖／時間軸畫面（CloudKitManager／CloudSyncManager 節流防抖、各 Store 強制解包與 retain cycle、GradeTitleView／StockView／AppleCalendarBridge／SubscriptionManager／RemoteAdmin 既有 [weak self] 與主執行緒防護），未發現其餘新問題。"
        ]),
        ChangelogEntry(version: "25.35", build: 788, date: "2026/07/31", notes: [
            "【靜態除錯 v25.35】兩路並行複查 Models 全部檔案、Views 頂層檔案、Views/Life 與 Views/Finance 大型清單／棋盤格畫面（強制解包／Optional／型別錯誤／index 越界、retain cycle／競態條件、畫面閃爍、O(n²) 效能瓶頸），發現並修復一個真實問題：SubordinateRosterView（部屬班表棋盤格）的 shiftFor(_:_:) 與 leaveFor(_:_:) 逐格對該部屬「全部歷史」shifts／records 陣列做線性掃描，兩者只增不減、隨使用年資持續變長，使整張棋盤格的重算成本是 O(部屬數 × 顯示天數 × 該人歷史筆數)——多年累積下來，每次月份切換／部門篩選／甚至其他頁面編輯任何一位部屬觸發 LifeStore 的 objectWillChange 都會讓這張表整批重算，隨資料量增長會越來越卡頓。改為在 hScrollContent 進場時一次建立 buildShiftLookup()／buildLeaveLookup() 兩張「部屬 id → 日期 → 班別／請假別」查表（每人歷史只掃描一次），棋盤格逐格改為 O(1) 字典查詢；請假查表額外把展開範圍夾在目前顯示月份頭尾之間，避免舊資料 endDate 異常時展開出天文數字次數的迴圈。純效能調整，班別／請假顯示結果與原本逐格線性掃描完全等價，UI 與互動邏輯未變動。其餘複查範圍（CloudKitManager／CloudSyncManager 30 秒節流與 2 秒防抖、各 Store 的 reloadFromCloud key 交集守衛、Timer／NotificationCenter／completion closure 之 [weak self]、OrganizationView／MyCalendarView／TaxOverviewView 既有的一次性查表優化、SettingsView／AddRealEstateView 等）均確認正常，未發現新問題。"
        ]),
        ChangelogEntry(version: "25.34", build: 787, date: "2026/07/30", notes: [
            "【美化】理財資產總覽金額量級單位一致性收尾（FinanceChartView）：私有 fmtShort(_:) 原本只在「≥1億」「≥1萬」兩個分支手刻換算，未滿 1 萬則委派給共用 fmt(_:)（= Double.ntdWanString，固定帶「NT$」字首），造成同一個 helper 依金額大小輸出格式不一致——本檔案 6 處呼叫點（英雄卡總資產、資產配置圖甜甜圈中心／圖例列、房地產／儲蓄險明細列）皆設計成不重複顯示 NT$ 字首（頁面已用「NT$ 市值估算」副標或 currencyCode 標籤另外標示幣別），未滿 1 萬的小額資產卻會意外冒出「NT$」字首，且缺少 ntdWanString 既有的「捨入至萬位上限應進位為億」邊界防呆。改為 fmtShort(_:) 自行處理全部三個量級、不再委派 fmt(_:)，並補上與 ntdWanString 一致的億進位邊界防呆；另外 chartYAxis 座標軸金額縮寫 abbreviate(_:) 只到「萬」量級、未滿 1 萬還混用英式縮寫「%.0fk」，與全 App 中文「萬／億」量級單位慣例不一致（同型問題已於 ChartView.abbreviateCurrency 修過），因其邏輯與修正後的 fmtShort(_:) 完全等價，移除重複的 abbreviate(_:)，唯一呼叫點改呼叫 fmtShort(_:)；並移除已無任何呼叫端的私有 currencyFormatter 死碼。純顯示層調整，總資產／資產配置／房地產與儲蓄險績效等既有試算邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.33", build: 786, date: "2026/07/30", notes: [
            "【美化】健康檔案健檢清單補上「下次回診」徽章（HealthProfileEditView）：CheckupEditor 早已能設定「下次回診／追蹤日」（nextDueDate），但外層健檢清單列先前完全沒有顯示這個欄位，使用者得逐筆點開才知道有沒有排定回診，容易忘記追蹤——是本檔案 v4 完成過敏嚴重度分級著色後，唯一還留著「有欄位卻沒著色顯示」缺口的小節。新增 nextDueBadge(_:)，比照同檔案 severityColor 的交通號誌語意分級著色（已逾期＝紅／30 天內即將到期＝橘／30 天以上尚有餘裕＝綠），加在清單列右側，不必進入編輯畫面就能一眼判斷急迫程度；用藥清單「服用中／已停用」原本就已有著色徽章，此輪確認毋須再調整。純視覺層調整，僅新增讀取既有 nextDueDate 欄位並著色顯示，CheckupEditor 的寫回邏輯、upsert／刪除等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.32", build: 785, date: "2026/07/30", notes: [
            "【美化】主畫面頂部子功能列選中膠囊漸層收尾（MainTabView.subFeaturePill）：子功能列（收支/理財/人生分頁下方的橫向捲動膠囊）選中狀態原本是扁平純色 tint 底，是同一條列裡唯一還沒升級的一環——職涯／家庭分組外框（careerGroupedPills／familyGroupedPills）與正上方底部導覽列選中指示器（tabItemLabel）都早已是漸層＋深色模式加強不透明度規格。改為 LinearGradient（tint→tint 78% 透明度）＋頂部玻璃光澤覆層，外框細邊框選中時同步改為白色半透明，對齊 v25.09 FloatingActionButtonView 主 FAB「漸層＋glass shine＋白色細邊框」三件式規格，讓子功能列與全 App 其餘選中膠囊視覺一致。純視覺層調整，isSelected 判斷、分頁切換、鎖定功能導頁等既有邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.31", build: 784, date: "2026/07/30", notes: [
            "【美化】家人紀錄／相簿編輯表單 Section header 補齊（FamilyMembersResumeView.FamilyEventEditor／FamilyAlbumPhotoEditor）：新增/編輯紀錄與新增/編輯照片兩個 sheet 共 5 個 Section（基本資訊 ×2／內容／照片／備註）原本是本檔案唯二仍在用系統預設純文字 Section(\"...\") 標頭的地方，與同檔案 FamilyMembersResumeView.sectionHeader／FamilyMemberDetailView.sectionHeaderWithAdd 早已升級的「4pt 漸層 Capsule 側條 + 圖示 + 粗體標題」規格脫節，也是全 App「表單 Section header 補齊」系列（BusinessCardEditor v25.24／OrgPersonEditor v25.22／EInvoiceSetupView v25.21／ChildDetailView v25.01）尚未覆蓋到的最後兩個編輯 sheet。新增共用 familyEditorSectionHeader(_:icon:color:)，依內容給主題色（基本資訊＝indigo／內容／備註＝secondary／照片＝teal），刪除紀錄／刪除此筆兩個 Section 維持無標頭，對齊全 App 編輯表單慣例。純視覺層調整，欄位資料綁定、save()／deleteRecord() 等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.30", build: 783, date: "2026/07/30", notes: [
            "【美化】首頁本月收支英雄卡「收支餘額」大字自適應收尾（OverviewView）：monthlyBalanceCard 頂部「收支餘額」大字原本沒有 lineLimit／minimumScaleFactor 防截斷保護，是同卡片三個金額數字中最寬的一個（多了正負號，且金額本身也最大）——v4 已為同卡「本月收入」／「本月支出」兩個子欄位補上 minimumScaleFactor(0.72)，這裡當時被漏掉。比照近期 LifeOverviewView v25.29／LifeRealEstateView v25.28／ChildrenResumeView v25.27 同一輪「英雄卡大字自適應收尾」規格，加上 .lineLimit(1) + .minimumScaleFactor(0.6)，讓大額（含負數）結餘在小螢幕上不會被裁切，同時維持在可辨識最小字級以上。純視覺層調整，balance／isPositive 等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.29", build: 782, date: "2026/07/30", notes: [
            "【美化】人生總覽頁統計卡大字自適應收尾（LifeOverviewView）：statsCard 三格 statBadge（總里程碑／本年新增／分類數）的 22pt 數字大字原本沒有 lineLimit／minimumScaleFactor 防截斷保護，是本頁唯一沒有這道防護的大字——同頁 categoryBreakdown 筆數．佔比膠囊、milestoneTimeline 計數膠囊皆為短字串無此風險，但里程碑累積多年後總數可能達 3～4 位數，擠壓固定寬度欄位。比照 ChildrenResumeView v25.27／LifeRealEstateView v25.28 為卡片大字補齊的同一規格，加上 .lineLimit(1) + .minimumScaleFactor(0.6)，讓數字在資料量成長時自動縮字、不會被裁切，同時維持在可辨識最小字級以上。純視覺層調整，里程碑統計計算等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.28", build: 781, date: "2026/07/30", notes: [
            "【美化】不動產總覽頁英雄卡總數大字自適應收尾（LifeRealEstateView）：summaryHeader 頂部「不動產概況」40pt 總物件數大字原本沒有 lineLimit／minimumScaleFactor 防截斷保護，是本卡片唯一沒有這道防護的大字——同卡片 heroKpiCell 的 KPI 數字（購入／持有中／已售出）早已於 v2 補上 minimumScaleFactor(0.72)；比照 AdminConsoleView v25.19 為「目前人數」大字、ChildrenResumeView v25.27 為「兒女總覽」大字補齊的同一規格，加上 .lineLimit(1) + .minimumScaleFactor(0.6)，讓卡片內大字防截斷規格全數收斂一致，同時維持在可辨識最小字級以上。純視覺層調整，不動產筆數統計、持有中／已售出分類等既有資料邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.27", build: 780, date: "2026/07/30", notes: [
            "【美化】兒女履歷頁英雄卡總數大字自適應收尾（ChildrenResumeView）：heroStatsCard 頂部「兒女總覽」42pt 總數大字原本沒有 lineLimit／minimumScaleFactor 防截斷保護，是本卡片唯一沒有這道防護的大字——同卡片 heroKpiCell 的 KPI 數字（兒子／女兒／生涯紀錄）與 childCard 的角色／年齡膠囊皆早已補上；比照 AdminConsoleView v25.19 為「目前人數」大字補齊的同一規格，加上 .lineLimit(1) + .minimumScaleFactor(0.6)，讓卡片內大字防截斷規格全數收斂一致，同時維持在可辨識最小字級以上。純視覺層調整，兒女總數統計、性別分類等既有資料邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.26", build: 779, date: "2026/07/30", notes: [
            "【靜態除錯 v25.26：修復部屬資料合併匯入的 O(n²) 主執行緒卡頓】UnifiedImporter.applyUnified（統一匯入／合併模式）與 SubordinateImporter.importData（部屬專用匯入／合併模式）兩處班表合併邏輯，原本各自對每筆匯入班別用 `arr.contains(where: { cal.isDate($0.date, inSameDayAs: sh.date) })` 逐一比對既有班表去重，是「既有班別數 × 匯入班別數」的 O(n²) 迴圈，且逐次比對還用了比直接比較日期更重的 Calendar.isDate。SubordinateImporter.importData 由 SettingsView 匯入按鈕直接同步呼叫、未離開主執行緒，使用者用「合併」模式還原多年份、多位部屬的完整備份時（例如 5 位部屬、每位累積約 700 筆班別），約需跑 250 萬次 Calendar.isDate 比對，會讓 App 在匯入當下明顯卡頓甚至觸發看門狗判定無回應。改為兩處都先用 `Set(startOfDay 的日期)` 建一次既有班別的日期索引，逐筆比對改為 O(1) 的 Set 查詢，整體複雜度降為 O(n+m)；去重語意（同一天已有班別就保留現有、不覆蓋；本輪匯入內同一天的重複班別也會互相去重）與修改前完全一致，僅為效能重寫。另複查 TalentMatrixView／HolographicBuildingView／FamilyOverviewMap／MedicalMapView／CareerView／MyCalendarView／SubordinateDetailView／AddExpenseView／AIService／RemoteAdmin／RestaurantSearch／FeatureGate／InvoiceCategorizer／LifeModels／FinanceModels／EInvoiceClient／EInvoiceSyncManager 等檔案的強制解包、index 越界、retain cycle、競態條件、SwiftUI 過度重繪與其餘 O(n²) 迴圈，均確認已有既有防護或非使用者可觸發熱路徑，未發現新問題。"
        ]),
        ChangelogEntry(version: "25.25", build: 778, date: "2026/07/30", notes: [
            "【效能】連拍相機／相簿多選存檔改在背景執行緒處理，避免拍照時卡頓（MultiPhotoGallery）：MultiShotCameraPicker 每拍一張，JPEG 編碼＋ImageCompressor 二次解碼壓縮＋磁碟寫入原本都同步跑在 UIImagePickerController delegate 回呼所在的主執行緒，此路徑被記帳收據、裝潢照片、水電繳費收據、帳單照片等 4 處共用，連拍時每一次快門都會讓即時預覽卡住、快門回應變慢，違背「連拍」設計初衷；PhotosPicker 相簿多選路徑同樣問題（.onChange 內原本是裸 Task，沿用 View 所在的 MainActor context，逐張處理仍在主執行緒跑完才輪到下一張）。改為 Task.detached(priority: .userInitiated) 背景處理，只在存檔完成後才用 MainActor.run 回主執行緒更新 fileNames，對齊 SettingsView.recompressStoredPhotos 既有的 Task.detached + MainActor.run 慣例。",
            "【修復】一鍵壓縮既有照片工具漏掉 RealEstateDocuments 資料夾（ImageCompressor.knownPhotoDirectories）：CloudKitManager.photoDirectories（CloudKit 同步／完整備份用）列了 9 個照片資料夾，但 ImageCompressor.knownPhotoDirectories（僅供 SettingsView 一鍵壓縮工具使用）只列了其中 8 個，獨漏 \"RealEstateDocuments\"；使用者以「匯入文件」流程把房屋權狀/收據拍成 jpg 存進這個資料夾時，會被 CloudKit 同步與備份正常收錄，卻永遠不會被批次壓縮工具處理到。改為讓 knownPhotoDirectories 直接沿用 photoDirectories，兩份清單合一，之後新增照片資料夾不會再漏同步第二份清單。"
        ]),
        ChangelogEntry(version: "25.24", build: 777, date: "2026/07/29", notes: [
            "【美化】名片「新增／編輯」表單 Section header 補齊（BusinessCardView.BusinessCardEditor）：本表單是全檔案唯一仍在用系統預設純文字 Section 標頭（Section(\"基本資訊\")／Section(\"電話\")／Section(\"Email\")／Section(\"傳真\")／Section(\"地址\")／Section(\"其他\") 共 6 處）的地方，與同檔案 BusinessCardDetailView.contactCard／noteCard 早已升級、以及全 App 編輯表單 OrganizationView.orgPersonEditorSectionHeader／ChildDetailView.childEditorSectionHeader／ResumeView.profileEditorSectionHeader 既有的「4pt 漸層 Capsule 側條 + 圖示 + 粗體標題」規格脫節。新增共用 businessCardEditorSectionHeader(_:icon:color:)，6 個 Section 各自依內容給主題色（基本資訊＝indigo／電話＝blue／Email＝purple／傳真＝orange／地址＝teal／其他＝secondary），刪除名片 Section 維持無標頭（對齊全 App 編輯表單慣例）。純視覺層調整，欄位資料綁定、OCR 預填／編輯載入、新增刪除電話與 Email、save() 等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.23", build: 776, date: "2026/07/29", notes: [
            "【美化】共用照片檢視器載入／失敗狀態黑底對比收尾（AddRealEstateView.PhotoViewerSheet）：本元件是 AddRealEstateView 物件照片、RealEstateDetailView 房屋資料照片、FamilyMembersResumeView 家人照片共用的全螢幕縮放檢視器，先前雖已修正過關閉／重設鈕位置，但載入中的 ProgressView() 沒有指定 tint，在純黑背景上呈現系統預設灰色、辨識度低，與 MultiPhotoGallery.PhotoLightbox／RealEstateDetailView／RenovationPhotoEditor 等其餘黑底載入圈皆已補上 .tint(.white) 的規格不一致；讀檔失敗狀態的圖示與文字也用 .secondary（跟隨系統配色，淺色模式下在純黑背景上會偏深灰、對比不足）。改為 ProgressView 補上 .tint(.white)，失敗狀態圖示加上淡白色圓底錨點、圖示與文字統一改用分層透明度的白色，深淺色模式在黑背景上皆清楚可辨；另外圖片讀取完成後加入 0.25 秒淡入動畫（imageAppeared），取代原本讀檔完成瞬間硬切出現的生硬感，對齊 MultiPhotoGallery.PhotoLightbox 既有的淡入規格。純視覺層調整，縮放／拖曳手勢、關閉與重設鈕邏輯、照片讀檔流程完全未變動。"
        ]),
        ChangelogEntry(version: "25.22", build: 775, date: "2026/07/29", notes: [
            "【美化】組織圖「新增／編輯人員」表單 Section header 補齊（OrganizationView.OrgPersonEditor）：本表單是全檔案唯一仍在用系統預設純文字 Section 標頭（Section(\"基本資訊\")／header: { Text(\"頭像\") } 等 8 處）的地方，與同檔案 DepartmentDetailView.peopleSection／OrgPersonDetailView.sectionCard 早已升級的「4pt 漸層 Capsule 側條 + 圖示 + 粗體標題」規格脫節。新增共用 orgPersonEditorSectionHeader(_:icon:color:)，寫法對齊 ChildDetailView.childEditorSectionHeader／ResumeView.profileEditorSectionHeader 既有做法；8 個 Section 各自依內容給主題色（基本資訊＝indigo／頭像＝blue／利害關係＝purple／記事＝secondary／子女＝pink／派系與相關人員＝orange／名片連結＝teal／狀態＝gray），刪除人員 Section 維持無標頭（對齊全 App 編輯表單慣例）。順手移除 OrgPersonDetailView.formatCurrency／currencyFormatter 兩處已無任何呼叫端的死碼（金額顯示改用 ntdWanString 後遺留）。純視覺層調整，欄位資料綁定、gradeTitleId／departmentId 連動邏輯、children／relations 新增刪除、save()／delete() 等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.21", build: 774, date: "2026/07/29", notes: [
            "【美化】電子發票分類規則「新增規則」表單 Section header 補齊（EInvoiceSetupView）：CategoryRulesEditorView 的新增規則 sheet 內「關鍵字／分類／比對範圍」三個 Section 原本是系統預設純文字 Section(\"標題\")，與同一 struct 主列表既有的分類 Section header（22pt 漸層圖示圓 + 文字）及全 App 編輯表單慣例（HealthProfileEditView.healthEditorSectionHeader／MyCalendarView.editorSectionHeader／ChildDetailView.childEditorSectionHeader 等）皆不一致。新增 ruleEditorSectionHeader(_:icon:color:)（4pt 漸層 Capsule 色條 + 圖示 + .subheadline.semibold 標題），對齊本檔案主畫面既有 einvoiceSectionHeader 同款規格。純視覺層調整，新增規則的關鍵字／分類／比對開關等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.20", build: 773, date: "2026/07/29", notes: [
            "【美化】部屬清單頁部門篩選空狀態收尾（SubordinateView）：subordinateSections 篩選後 filtered.isEmpty 分支原本是裸 Text(\"此部門尚無部屬\")，未包圖示錨點、垂直置中純文字直接鋪在 List 裡，與同檔案 emptyStateView（頁面首次無部屬資料時的雙層脈衝光環大型空狀態）及全 App 其餘「篩選後零筆」次要空狀態（ResumeView.categoryEmptyState／FoodMapView.restaurantListEmptyState）不一致，同一頁面內兩種空狀態呈現落差明顯。新增 filteredEmptyState：56pt 藍色圖示圓（person.2.slash + emptyStateView 同款 accent 藍，含細邊框）+ 說明文字，對齊 ResumeView.categoryEmptyState 規格（次要篩選態僅用輕量卡片，不做全頁大型脈衝動畫，該規格保留給頁面首次無資料的 emptyStateView）。純視覺層調整，部門篩選邏輯、部屬資料來源、排序與拖曳等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.19", build: 772, date: "2026/07/29", notes: [
            "【美化】管理控制台細節收尾（AdminConsoleView）：控制台使用者人數列先前是全 App 唯一顯示大型數字卻沒有防截斷保護的地方——其餘頁面金額類數字皆已透過 ntdWanString 或個別補上 minimumScaleFactor，本頁「目前人數」卻仍是裸 Text(admin.userCount)，使用者數成長到 5 位數以上時可能被系統預設截斷；補上 .lineLimit(1) + .minimumScaleFactor(0.6)，對齊全 App 大字自適應規格。另「版本更新紀錄」Section 內「最新：v...」摘要行原本是裸 .caption 純文字，與同一 Section 底下 NavigationLink 進去的 ChangelogListView.changelogHeader 版本徽章（藍→靛漸層 Capsule）風格脫節；改為迷你版同款漸層 Capsule 徽章 + build 輔助文字，讓摘要行與詳情頁版本徽章視覺語言一致。純視覺層調整，人數讀取、版本紀錄資料來源、PIN 解鎖、訂閱門檻切換等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.18", build: 771, date: "2026/07/29", notes: [
            "【美化】報稅總覽頁金額量級單位一致性收尾（TaxOverviewView）：v4 已將年收入 KPI／節稅累積／月份長條／扣除額徽章四類共 5 處改用共用 Double.ntdWanString（萬／億量級），但當時遺留一處缺口——fmt(_:) 本身仍呼叫獨立的私有 NumberFormatter（無條件全位數，如「NT$1,234,567」），是全檔案 7 處呼叫點（年度稅費支出大字、稅務紀錄列金額、節稅子分類合計/上限/來源拆解膠囊）中唯一沒有萬/億量級單位的格式，尤其 annualSummaryCard 32pt 年度稅費支出大字與旁邊已用 fmtShort 的年收入膠囊並排時數字長度懸殊，高稅費年度更有擠壓大字排版的風險。改為 fmt(_:) 也呼叫共用 ntdWanString，與 fmtShort 完全等價後移除重複的 fmtShort(_:) 與已無呼叫端的私有 currencyFormatter 死碼，5 處原呼叫點改呼叫 fmt(_:)；年度稅費支出大字補上 lineLimit(1) + minimumScaleFactor(0.6)，對齊右側年收入 KPI 膠囊已有的防截斷規格。純顯示層調整，稅費加總、節稅累積、扣除額試算等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.17", build: 770, date: "2026/07/29", notes: [
            "【美化】履歷頁列表空狀態與大字自適應收尾（ResumeView）：filteredList 單一分類篩選後零筆時，原本是裸 Text(\"此分類尚無紀錄\")，未包在 List Section 內也沒有圖示錨點，與同檔案 emptyStateList 的雙層脈衝空狀態、以及全 App 其餘「篩選後零筆」次要空狀態（FoodMapView.restaurantListEmptyState）不一致。新增 categoryEmptyState(_:)：56pt 分類主題色圖示圓 + 說明文字，包入 Section 對齊 List 版面規格，僅次要篩選態用輕量卡片、不做全頁大型脈衝動畫（該規格保留給頁面首次無資料的 emptyState）。另補齊 milestoneRow／spendingRow 標題文字缺失的 minimumScaleFactor(0.85)，避免大字級輔助模式下長標題被裁切而非縮小；並移除 spendingRow 改用 ntdWanString 後已無呼叫端的私有 formatCurrency(_:)／currencyFormatter 死碼。純視覺層調整，分類篩選、里程碑與消費資料來源、刪除等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.16", build: 769, date: "2026/07/29", notes: [
            "【靜態除錯 v25.16】複查 Models 層（CloudKitManager／CloudSyncManager／ExpenseStore／FinanceStore／LifeStore／EInvoiceSyncManager／NotificationManager／AppleCalendarBridge／SubscriptionManager／RemoteAdmin／InvoiceCategorizer／BackupManager／UnifiedExport 等）與大型 Views（AddExpenseView、SubordinateDetailView、RealEstateDetailView、MyCalendarView、LifeFinanceView、ChartView、MainTabView、StockDetailView、OrganizationView 等），排查強制解包、index 越界、retain cycle、競態條件、畫面閃爍與效能瓶頸；Models 層每一處 firstIndex／weak self／CloudKit 30 秒節流路徑複查後確認皆有既有修復把關，未發現新問題。找到並修復 1 處真實問題：BusinessCardView 名片搜尋欄（searchText）是全 App 搜尋類欄位中唯一一處還沒補上防抖的地方——同性質的 VariableExpenseView／IncomeView（v20.4）與 MyCalendarView／ChildDetailView 診所地點自動完成欄位，都已改用 300ms 防抖的 debouncedSearchText，避免每次按鍵都立即觸發高頻過濾運算；BusinessCardView 的 filteredCards 計算屬性卻仍直接綁定 searchText，每敲一個字元就對 lifeStore.businessCards 全量重新排序＋跑 5 個欄位字串比對＋2 個陣列 contains（電話／email），比其餘已修復頁面的過濾邏輯更重，快速輸入時清單會隨每個字元跳動閃爍。改為新增 debouncedSearchText／searchDebounceTask，TextField 加上 .onChange 300ms 防抖（.onDisappear 取消），filteredCards 改讀 debouncedSearchText，寫法逐一比照既有 VariableExpenseView 規格；空狀態判斷、清除按鈕等僅作 UI 顯示用途的 searchText.isEmpty 判斷維持即時繫結不受影響。"
        ]),
        ChangelogEntry(version: "25.15", build: 768, date: "2026/07/29", notes: [
            "【靜態除錯 v25.15】複查 Models 層（ExpenseStore／FinanceStore／LifeStore／CloudKitManager／CloudSyncManager／EInvoiceSyncManager／BackupManager／FullBackup／UnifiedExport／RemoteAdmin／SubscriptionManager 等）與相片／圖表／清單類 Views（ChartView、MultiPhotoGallery、RenovationPhotoEditor、MyCalendarView、SubordinateRosterView、TravelMapView、FamilyOverviewMap 等），排查強制解包、index 越界、retain cycle、競態條件、畫面閃爍與效能瓶頸。找到並修復 1 處真實問題：FullBackup.restore() 附件還原迴圈中，單一附件因檔案截斷或 manifest 損壞未通過 size 校驗時，過去用 continue 想「跳過壞的一筆、救回後面的」，但附件之間在檔案裡沒有分隔符、全靠依序讀取 size 位元組定位，一旦某筆校驗失敗，讀取游標就與檔案內容永久錯位；由於 bytes.count == att.size 只在讀到檔尾時才會失手，錯位後續每一筆 continue 讀到的其實是「別筆附件的位元組」但長度剛好對得上，於是被當成合法資料，頂著正確檔名寫回磁碟——不是漏還原，而是靜默把多張照片／文件覆蓋成錯誤內容，比整批略過更嚴重。改為在校驗失敗當下 break 停止附件迴圈，並如實回報 written 筆數，不再對已知錯位的資料繼續假裝還原。CloudSyncManager 30 秒節流／2 秒防抖、isSyncing 並行守衛、@Published 主執行緒隔離複查後確認正常，Views 層既有的快取／防抖／背景讀圖規格亦均符合既有修復慣例，未發現新問題。"
        ]),
        ChangelogEntry(version: "25.14", build: 767, date: "2026/07/28", notes: [
            "【美化】部屬排班詳情 Sheet「操作日期」標頭一致性（SubordinateRosterView.RosterCellDetailSheet）：dateSection 原本是本 sheet 唯一還在用系統預設 Text(\"操作日期\") 純文字標頭的 Section，同一個 sheet 內 shiftSection／summarySection／actionSection 三個 Section 早在 v2 就已改用共用 sectionHeader(_:icon:color:) 輔助（Capsule 漸層色條 + 圖示 + 粗體標題），引入輔助函式當下漏改了最上面的日期 Section，是本 sheet 唯一的落差。改為呼叫 sectionHeader(\"操作日期\", icon: \"calendar\", color: .blue)，藍色呼應同 Section 內左右翻頁 chevron 按鈕既有的 .blue 著色。純視覺層調整，dayOffset 切換、日期綁定、下方班別設定套用等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.13", build: 766, date: "2026/07/28", notes: [
            "【美化】兒童疫苗接種時程「施打編輯」Sheet（ChildVaccineScheduleView.VaccineDoseEditorSheet）：該 sheet 先前是裸 Form + 系統預設 Label 標頭（灰階圖示、無色條），是本檔案唯一沒對齊「4pt 漸層 Capsule 色條 + 主題色圖示」標頭規格的地方（外層清單標頭、HealthProfileEditView 四個子編輯 sheet 皆已是此規格）。新增同款式 vaccineEditorSectionHeader(_:icon:color:)，三個 Section 一律改用：疫苗資訊／施打狀態沿用外層藍色主題，備註採全 App 慣例的 secondary 色。另補上 Toggle「已完成施打」.tint(accent)（避免系統預設綠色與本頁藍色主題衝突）與疫苗名稱／劑次文字 lineLimit(2) + minimumScaleFactor(0.85)（避免長名稱在大字級輔助模式下裁切）。純視覺層調整，接種狀態判斷、日期推算、草稿寫回與存檔邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.12", build: 765, date: "2026/07/28", notes: [
            "【美化】自訂日期選擇器主題色統一（MacaronDatePicker）：底部 compact DatePicker 先前未指定 .tint，沿用全 App 系統藍 accentColor，是卡片內唯一一處跟 5 顆馬卡龍快捷鍵、分隔線、標籤色完全無關的元素，展開的彈出日曆選中日期圓圈也是系統藍，與整張卡片的莫蘭迪馬卡龍語言脫節。新增 pickerTint（介於薰衣草與玫瑰之間的霧霧莫蘭迪紫，不偏袒任一顆快捷鍵色），套用 .tint(pickerTint) 到 DatePicker：文字按鈕與彈出日曆選中態改用此色，呼應卡片整體粉彩基調。純視覺層調整，日期選取、allowFuture 過濾等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.11", build: 764, date: "2026/07/28", notes: [
            "【美化】支出圖表頁英雄卡載入指示器（ChartView）：chartHeroCard 頂部標籤旁的白色系統原生 ProgressView（0.65 倍縮小 spinner）是本檔案最後一處殘留系統 spinner 的地方，與 25.10 版大卡（isLoading 卡片）改用的漸層圖示圓＋旋轉 chart.bar.fill 語言不一致。改為 14pt 迷你版同款造型（白色系漸層圓 + 旋轉圖示），共用大卡既有的 chartLoadingSpin 旗標（不新增 state），兩處圖示同步旋轉，視覺語言完全統一。純視覺層調整，isLoading 判斷邏輯、金額格式化等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.10", build: 763, date: "2026/07/28", notes: [
            "【美化】支出圖表頁載入狀態（ChartView）：isLoading 卡片原本是裸 ProgressView + 純文字，是全 App 載入態中唯一還在用系統原生 spinner、且與 trendChart／variablePieChart／fixedPieChart 空狀態雙層脈衝光環＋漸層圖示圓設計語言脫節的地方。改為雙層脈衝光環 + 漸層圖示圓（chart.bar.fill 圖示以線性旋轉取代圈圈 spinner），下方補上 7 條長條圖骨架佔位條（隨脈衝呼吸淡入淡出），讓「即將出現長條圖」的預期更明確；卡片補上細邊框對齊全 App 卡片統一規格。新增 chartLoadingPulse／chartLoadingSpin 旗標與可取消 chartLoadingPulseTask，寫法比照既有四個 EmptyPulse 旗標（loadChartData() 重載時歸零＋onDisappear 取消，避免快速切換週期時動畫從中途開始）。純視覺層調整，資料載入流程、期間切換、拖曳選點等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.09", build: 762, date: "2026/07/28", notes: [
            "【美化】主畫面匯出進度條／浮動新增按鈕主體造型（MainTabView）：exportProgressBar 原本只有裸文字百分比、進度軌道無邊框、與下方導覽列之間沒有視覺交界，補上 16pt 漸層圖示圓錨點（arrow.up.doc.fill）、百分比數字 contentTransition(.numericText()) 平滑過場、軌道 Capsule 描邊、頂部 0.5pt 分隔線（對齊 bottomTabBar 上緣分隔線規格）。FloatingActionButtonView.fabStack 主 FAB 與「新增收入」「新增支出」兩顆選單按鈕，是本檔案僅存的三處純色扁平按鈕（Color.green／.red／.secondary），改為漸層底 + 頂部 glass shine 白色高光 + 細邊框，對齊全 App 漸層按鈕/英雄卡片統一規格。純視覺層調整，匯出進度計算、拖曳吸邊、彈出選單開關、新增收入／支出導頁等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.08", build: 761, date: "2026/07/28", notes: [
            "【美化】部門職等頁空狀態補齊脈衝動畫（GradeTitleView）：deptEmptyState／gradeTitleEmptyState 兩處空狀態，檔案自身 [2026-06] 美化紀錄雖曾宣稱已是「double-pulse ring」，實際上只有靜態同心圓描邊、沒有任何動畫，與全 App 其餘空狀態（OrganizationView.emptyState／IncomeView.emptyState 等）共用的雙層脈衝呼吸環規格不一致。改為外層/內層 Circle().stroke + scaleEffect + repeatForever 動畫，各自搭配獨立的 deptEmptyPulse／gradeEmptyPulse 旗標與可取消 Task（onAppear 延遲 0.3s 觸發、onDisappear 取消歸零），數值與寫法逐一比照 OrganizationView.emptyState 既有規格複製，部門／職等兩個空狀態互不干擾、可同時顯示。純視覺層調整，部門與職等資料模型、儲存、雙向同步等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.07", build: 760, date: "2026/07/28", notes: [
            "【美化】旅遊地圖清單排序控制項互動元件統一（TravelMapView）：listSheet 排序控制項（造訪次數／總花費／最近造訪）原本是系統 .segmented Picker，是全 App 排序功能中，唯一還在用系統元件的一處——同型姊妹頁 FoodMapView.listSheet 排序功能早已改用水平捲動 chip 列（帶選中彈簧動畫），兩姊妹頁清單 sheet 上半部視覺語言因此不一致。改為 ScrollView(.horizontal) + 本檔案既有 chip() 助手（城市／期間篩選已在用同一款元件，含 spring(0.26/0.72) 選中動畫），spacing／padding 對齊 FoodMapView 排序 chip 列規格。sort 綁定、sortedSpots／spotsByCity 排序邏輯完全未變動，純互動元件外觀替換，屬 v25.02 為本檔案留下的待辦事項。"
        ]),
        ChangelogEntry(version: "25.06", build: 759, date: "2026/07/28", notes: [
            "【除錯】靜態排查發現一組跨 5 個檔案的同一 bug class：房地產／股票／儲蓄險等資產詳情頁存檔時，會用 expenseStore.update() 整筆重建連結的 Expense 紀錄（同步金額／日期／備註），但重建時都沒有帶回該 Expense 既有的 photoFileNames，而 Expense 建構子預設空陣列、update() 又是整筆覆蓋、不做欄位合併——若使用者曾在 AddExpenseView 為這筆連結支出另外上傳收據照片，之後只要回到資產頁重新存檔（例如改個金額），該照片會被默默清空、實體檔案永久變孤兒（本機與 iCloud 都不會再被刪除或引用）。逐一修正 5 處：RealEstateDetailView.UtilityPaymentEditor.save()、AddRealEstateView 的 syncInsuranceExpense／syncAssetExpense／syncSaleExpense、AddStockView.syncSoldExpense、AddSavingsInsuranceView.syncFixedExpense，改為重建前先讀回原 Expense 的 photoFileNames 帶入新物件。另外複查了 RealEstateDetailView／VariableExpenseView 的「複製支出」（duplicateLinkedExpense／duplicateExpense）與 AddExpenseView／AddRealEstateView 的 UtilityPayment 同步——這幾處確認是刻意設計（複製品不沿用原照片避免共用檔案；UtilityPayment 自己的收據照片存於獨立的 UtilityPhotos 資料夾，與 Expense 的 ExpensePhotos 是兩組不同檔案，本就不該互相覆蓋），非本次 bug class，未變動。另複查全 App 力度解包／as!／try!／Timer／NotificationCenter retain cycle／CloudKit 30 秒節流／O(n²) 迴圈，均未發現新問題。",
        ]),
        ChangelogEntry(version: "25.05", build: 758, date: "2026/07/28", notes: [
            "【除錯】v25.04 電費多張照片功能上線後的靜態排查：全面檢視 Models/ 共用狀態與同步邏輯（強制解包、as!/try!、Timer/NotificationCenter 是否用 [weak self]、CloudKit 30 秒節流是否被繞過、O(n²) 迴圈、UI 過度重繪）均未發現問題，本次修正聚焦於較新的 photoFileNames 多張照片欄位有兩處仍誤用舊版單張 photoFileName 的殘留：① RealEstateDetailView「房屋照片集錦」點擊水電繳費項目時，只取 photoFileName 開單張預覽，多拍的第 2 張以後照片被燈箱忽略；改為讀取完整 photoFileNames 陣列。② AddRealEstateView 新增房產流程中途自動存檔後又取消回滾（cancelAndRollback）時，水電繳費照片只刪除 photoFileName 這一張，第 2 張以後的暫存照片留在本機成孤兒檔案並被雲端上傳程式重複偵測上傳；改為逐張刪除 photoFileNames 陣列中所有檔案。",
        ]),
        ChangelogEntry(version: "25.04", build: 757, date: "2026/07/28", notes: [
            "【功能】一鍵壓縮既有照片 + 電費收據拍照連拍：① 設定頁「資料管理」新增「一鍵壓縮既有照片」（ImageCompressor.recompressAllStoredPhotos）：走訪全部 8 個照片資料夾（記帳收據/兒女記錄/家庭相簿/名片/組織人員/電梯保養/水電繳費/裝修照片），逐檔套用 v25.03 的 1080P 長邊 + JPEG 80% 壓縮，變小才回寫並重新上傳 iCloud 覆蓋雲端大圖，完成後彈窗回報「掃描 N 張、壓縮 M 張、省下 X MB」；IO 密集移背景執行緒執行、busy 旗標防連點。② 新增連拍相機 MultiShotCameraPicker（RenovationPhotoEditor.swift，與 CameraPicker 並列）：UIImagePickerController 預設介面拍一張就得離開，改用官方多拍做法 showsCameraControls=false + 自訂快門 overlay 呼叫 takePicture()，每按一次快門立即「存檔→壓縮→上傳 iCloud」並累計「已拍 N 張」，按「完成」才離開；無相機裝置（模擬器）退回相簿選取。MultiPhotoGallery 的「拍照」改用此連拍相機，記帳收據/裝修照片等所有多照片頁一體受惠。③ 電費（水電瓦斯繳費 UtilityPayment）收據照片由單張升級為多張：資料模型新增 photoFileNames 陣列（保留舊 photoFileName 欄位向下相容，舊資料自動升級為單元素陣列；恆同步 first 供舊版讀取），編輯器（UtilityPaymentEditor）原本只有相簿單選的 PhotosPicker，改用 MultiPhotoGallery（拍照連拍/相簿多選/燈箱檢視/逐張刪除），正面回應「新增電費只有上傳圖片、沒有拍照」的需求；取消時清除本次新拍未儲存的照片避免孤兒檔案。連動更新：繳費列表/總覽照片計數與照片指示改看多張陣列、四處刪除路徑（房產刪除×2/單筆刪除/取代匯入清理）改為逐張刪除、AddExpenseView 重建繳費紀錄時帶回完整照片陣列、照片總覽 .utility 分支回傳全部照片。"
        ]),
        ChangelogEntry(version: "25.03", build: 756, date: "2026/07/28", notes: [
            "【功能】照片存檔統一壓縮（1080P 長邊 + JPEG 80%）：使用者反映照片檔案太大導致匯出備份檔過大。新增 ImageCompressor.compressForStorage(_:)（CloudKitManager.swift，與 PhotoCloudSync 同檔）：存檔前解碼影像 → 長邊超過 1920px（1080P 規格）就等比例縮小 → JPEG 80% 重新編碼；無法解碼（非影像資料）或壓縮結果反而更大（來源已是小圖/高壓縮檔）時維持原資料不動，確保永不變差。套用於全部 10 個照片寫檔路徑：記帳收據（Expense.savePhoto）、兒女記錄照片與素描（ChildRecord.savePhoto/saveSketch，含 ChildDetailView.regeneratePreview 唯一繞過 saveSketch 的直接寫檔路徑）、家庭相簿（FamilyAlbumPhoto）、名片頭像（BusinessCard）、組織人員（OrgPerson）、電梯保養（ElevatorMaintenance）、水電繳費（UtilityPayment）、裝修照片（RenovationPhoto）。效果：本機儲存占用、iCloud 照片上傳量、完整備份/匯出檔案大小全面下降（現代手機原圖動輒 3–8MB，壓縮後多在數百 KB）；既有已存的大圖不受影響（僅新存檔生效）。分享用途的高解析輸出（人才矩陣/部屬卡片匯出 JPG 0.95）刻意不壓縮，維持分享畫質。"
        ]),
        ChangelogEntry(version: "25.02", build: 755, date: "2026/07/27", notes: [
            "【美化】旅遊地圖地點清單 sheet 空狀態補齊（TravelMapView）：listSheet 內 spots 為空時（多為 photoOnly「有照片」篩選到 0 筆，但下層「地點清單」按鈕不受此篩選影響、仍可點開），原本 sortPicker 下方是一片空白、沒有任何提示，與已有空狀態提示的姊妹頁 FoodMapView.restaurantListEmptyState 不一致。新增 spotsListEmptyState：對齊 FoodMapView 圓角卡（systemBackground＋16pt 圓角＋細邊框）規格，文案沿用本檔案 emptyOverlay isPhotoFilter 分支既有用語，讓地圖層／清單 sheet 層兩處空狀態說法一致。另確認 listSheet／citySection 圓角卡規格已於 FoodMapView v7 追上、兩姊妹頁視覺已對齊，不再需要調整。純視覺與空狀態文案調整，spotsByCity 分組、排序等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.01", build: 754, date: "2026/07/27", notes: [
            "【美化】兒女詳情頁編輯表單 Section 標頭一致性（ChildDetailView）：DailyRecordEditorSheet（喝奶/食物/睡眠記錄）與 ChildRecordEditorSheet（疫苗/過敏/成長/就醫/教育/興趣/紀念、日期／備註／插入圖片）共 13 處 Section，原本全是系統預設純文字標題，是 ChildDetailView.swift 內唯一還沒套用「4pt 漸層 Capsule 色條 + 圖示 + 粗體標題」規格的區塊，與 HealthProfileEditView.healthEditorSectionHeader／MyCalendarView.editorSectionHeader／ResumeView.profileEditorSectionHeader 等全 App 編輯表單慣例落差明顯。新增檔案層級共用 childEditorSectionHeader(_:icon:color:)，圖示沿用既有 DailyRecordType/ChildRecordType.icon，色彩新增 accent 計算屬性對齊 ChildDetailView.dailyColor／colorFor 同型別同色彩規格（備註類 Section 統一用中性 .secondary，對齊全 App慣例）。純視覺層調整，Section 內欄位、canSave／save()／delete() 等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "25.00", build: 753, date: "2026/07/27", notes: [
            "【美化】支出趨勢圖 Y 軸金額量級單位一致性（ChartView）：trendChart 圖表 Y 軸刻度標籤 abbreviateCurrency(_:) 原本只到「萬」量級（≥1萬顯示「%.0f萬」），未滿 1 萬則混用英式縮寫「%.1fk」（如「3.5k」），與全 App 其餘畫面一律使用中文「萬／億」量級單位的慣例不一致，且月支出趨勢達 1 億以上時會被顯示成「12000萬」這種鉅額萬數字。改為比照 FinanceOverviewView.fmtShort／共用 Double.ntdWanString 既有規格：≥1億 顯示「%.1f億」、≥1萬 顯示「%.0f萬」，移除不一致的「k」英式縮寫分支。純顯示層調整，圖表資料、期間切換、拖曳選點等既有邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.99", build: 752, date: "2026/07/27", notes: [
            "【美化】房地產詳情頁（RealEstateDetailView）金額量級單位一致性：補齊 v24.98 為 StockDetailView 完成美化時留下的待辦。flashCard 估值大字、底部「購入」值原本各自呼叫私有 fmtWan(_:)（僅 %g 除以萬，無條件只顯示「萬」），估值一旦達 1 億以上會顯示成 5～6 位數的鉅額「萬」數字，與同檔案 mortgageItems／paidItems／calcRow 等皆已改用共用 Double.ntdWanString（已支援萬→億自動進位）不一致。新增 splitWan(_:)／splitWanLabel(_:) 從 ntdWanString 拆出「數字／單位」二段供大字沿用既有字級與 contentTransition 動畫設計，移除已無呼叫端的私有 fmtWan 死碼；作法對齊 VehicleDetailView.splitWan 既有規格。至此股票／車輛／房地產三款詳情頁閃卡估值大字量級單位規格已完全收斂一致。純顯示層調整，估值、購入價、增值率等既有試算邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.98", build: 751, date: "2026/07/27", notes: [
            "【美化】股票詳情頁（StockDetailView）金額量級單位一致性：補齊 v24.88 為 VehicleDetailView（車輛詳情頁）完成美化時留下的待辦。flashCard 市值大字原本呼叫私有 fmtWan(_:)（僅 %.1f 除以萬，無條件只顯示「萬」），市值一旦達 1 億以上會顯示成 5～6 位數的鉅額「萬」數字，下方輔助文字也固定寫死「（萬元）」，與同檔案 infoRow 損益／報酬率（皆透過共用 fmt = ntdWanString，已支援萬→億自動進位）不一致。新增 splitWan(_:) 從 ntdWanString 拆出「數字／單位」二段供大字沿用既有字級與 contentTransition 動畫設計，輔助文字改為讀取拆出的單位動態組字（達 1 億以上自動顯示「億元」），移除已無呼叫端的私有 fmtWan 死碼；作法對齊 VehicleDetailView.splitWan 既有規格。純顯示層調整，市值、損益、報酬率等既有試算邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.97", build: 750, date: "2026/07/27", notes: [
            "【美化】共用馬卡龍日期選擇器（MacaronDatePicker）進場動畫一致性：本元件在兩個呼叫端（我的行事曆 MyCalendarView／部屬總覽 SubordinateOverviewView）都夾在「已有進場動畫的英雄卡」與「已有錯落進場動畫的清單 section」中間，是唯一一個一開啟畫面就直接定位、沒有進場過場的區塊，讓整條卷軸的進場節奏中間斷了一拍。改為元件自帶進場旗標（opacity 0→1 + 上移 14pt，spring 0.52/0.80，delay 0.06s 銜接在英雄卡之後），畫面消失時歸零避免分頁切換或重新開啟時動畫不重播；採自包含寫法，不需呼叫端額外傳入狀態，兩處呼叫端自動獲得一致效果。純視覺層調整，日期選取、快捷鍵、allowFuture 未來日期過濾等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.96", build: 749, date: "2026/07/27", notes: [
            "【美化】設定頁（SettingsView）AI 供應商說明字級一致性修復：「使用中的 AI 服務」下方各供應商（Claude／OpenAI／Gemini）Section 的申請 Key 教學與扣款金額提醒文字，先前額外覆寫 .font(.caption2)，是全檔案 10 處 Section footer 說明文字中唯一縮小字級的一處，比其餘資料統計、iCloud 同步、匯率設定等說明性 footer 使用的系統預設字級更小——內容又包含每次解析約需扣款多少金額的重要資訊，字級反而是全頁最小，容易被忽略或難以閱讀。移除該覆寫，改回與其餘 9 處說明性 footer 一致的預設字級；「關於」區版權宣告維持原本置中小字的版權印刷慣例，屬不同類別不受影響。純文字字級調整，供應商 Key 讀寫、選用中服務判斷等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.95", build: 748, date: "2026/07/27", notes: [
            "【美化】支出照片堆疊瀏覽器（ExpensePhotoStackViewer）補齊姊妹元件待辦：補齊 v24.91 為 RenovationStackViewer（裝潢照片堆疊瀏覽器）完成美化時留下的待辦——ExpensePhotoStackViewer（支出照片堆疊瀏覽器，用於各項支出的收據/照片檢視）規格明顯落後，本次整批補齊。空狀態從裸 Text(\"沒有照片\") 升級為 52pt 圓形圖示（photo，白 0.10 底 + 0.18 邊框）+ subheadline 說明文字；大圖讀取完成加入 opacity 淡入轉場（.transition(.opacity) + .animation(.easeOut(duration:0.28))），取代原本讀圖完成瞬間的生硬硬切；頁碼從純文字改為半透明 Capsule 膠囊徽章；日期加 calendar 圖示前綴；標題字重升級為 .bold；底部資訊面板加入進場動畫（opacity 0→1 + 上移 20pt，spring 0.55/0.78），取代原本一開啟就直接定位、毫無過場的手感，容器 onDisappear 重置旗標避免重複開啟時動畫不重播。至此支出／裝潢兩款照片堆疊瀏覽器視覺規格已完全對齊。純視覺層調整，支出照片讀取、翻頁、刪除等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.94", build: 747, date: "2026/07/27", notes: [
            "【靜態除錯 v24.94：移除 FinanceStore 未使用的 offset 刪除方法，消除潛在 index 越界地雷】deleteInsurance(at:)／deleteStock(at:)／deleteVehicle(at:)／deleteRealEstate(at:) 這組以 IndexSet 直接對 insurances／stocks／vehicles／realEstates 陣列做 remove(atOffsets:) 的方法，全庫已無任何呼叫端（SavingsInsuranceView／StockView／VehicleView／RealEstateView 等清單畫面實際都是用 ID 比對的 deleteX(_:) 版本刪除，並非 List.onDelete）。這組方法本身也不像 ExpenseStore.delete(at:from:) 那樣先把 offsets 限制在來源陣列範圍內、且沒有另外接受「目前畫面顯示用的（已排序/篩選）清單」參數，而上述四個清單畫面全部都是排序過（依現值/市值/日期等）才顯示——若日後有人比照其他清單很自然地幫這四個畫面接上原生 .onDelete 並直接傳入畫面排序後的 offsets，會出現與排序前陣列 index 對不上而刪錯項目、或 offsets 超出陣列範圍直接 crash 的問題，屬於使用者要求複查的「index 越界」同一類風險。因目前確認零呼叫端、非任何現有畫面路徑會觸發，採直接移除（而非幫死代碼補防護），消除地雷本身而不留下引誘日後誤用的 API。純 Models 層變動，未影響任何現有刪除邏輯或使用者可觸發的行為。"
        ]),
        ChangelogEntry(version: "24.93", build: 746, date: "2026/07/27", notes: [
            "【靜態除錯 v24.93：修復電子發票同步永久漏匯入的邊界問題】EInvoiceSyncManager.syncNow() 過去直接以上次同步當下的 lastSyncDate 作為下一次查詢區間的起點，完全沒有重疊緩衝。財政部電子發票載具查詢平台的資料入帳存在已知延遲（部分特店延後 1～3 天才批次上傳），若某張發票在開立當天查詢不到，等它終於出現在平台上時，下一輪同步的起點早已前進到它的開立日之後，往後任何一次同步都不會再涵蓋那個日期區間，這筆消費會被永久靜默漏匯入、且無任何錯誤提示——與本檔案過去 v24.53／56／64／73 修復過的「孤兒/漏匯入」同一類問題，唯獨同步日期區間本身沒有補上緩衝。修法：新增 3 天回溯緩衝，起點改為 lastSyncDate 往前推 3 天；重疊區間內已匯入過的發票由既有的 alreadyImported（以 invNum 去重）機制擋下，不會造成重複建立支出，僅是每次多查詢幾天份的區間。本輪同時複查 ChildVaccineSchedule／LifeModels（含班表跨日休息扣除、PersonalEvent 重複規則）、UnifiedExport 匯入清理、AIService、SubscriptionManager、BackupManager／FullBackup 串流備份、FinanceModels 複利與交易重算等多個較少被提及的檔案，以及全庫 force-unwrap／as!／try!／Timer／NotificationCenter retain cycle／ForEach 索引範圍，均確認已妥善保護、無新問題。"
        ]),
        ChangelogEntry(version: "24.92", build: 745, date: "2026/07/26", notes: [
            "【美化】全息大樓視圖（HolographicBuildingView）樓層標籤大字自適應：側邊樓層清單的樓層編號與功能標籤原本沒有 minimumScaleFactor，是本元件目前唯一缺文字自適應防護的地方，使用者輸入較長樓層代號或多個功能標籤以「・」串接、或開啟系統輔助大字體時會被直接裁切成省略號。補上 lineLimit(1) + minimumScaleFactor(0.7)，讓長字串改為自動縮小顯示、不至於小到無法辨識，對齊全 App 文字自適應規格。純視覺層調整，樓層資料、排序與選取邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.91", build: 744, date: "2026/07/26", notes: [
            "【美化】裝潢照片堆疊瀏覽器（RenovationStackViewer）補齊 v24.90 留下的待辦：底部標題／頁碼／備註／日期資訊面板原本一開啟就直接定位顯示，與全 App 其餘英雄卡（TravelMapView.statsCard／MedicalMapView.summaryCard 等）皆已有的「opacity 0→1 + 上移 20pt，spring(0.55/0.78)」進場動畫規格不一致，是同類元件中唯一還沒補上的。新增 infoPanelAppeared 旗標，onAppear 觸發進場、onDisappear 歸零避免重複開啟時動畫不重播，並在檔頭美化紀錄補上本次調整方向與下次可接續方向（ExpensePhotoStackViewer 為本元件姊妹版本，規格明顯落後，可整批補齊）。純視覺層調整，照片讀取、翻頁、刪除等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.90", build: 743, date: "2026/07/26", notes: [
            "【美化】裝潢照片堆疊瀏覽器（RenovationStackViewer）大圖載入淡入動畫：逐張展開的大圖原本 AsyncLocalImage 一讀到檔案就直接把 ZoomableImageView 硬切換上畫面，與同檔案（MultiPhotoGallery.swift）另一個全螢幕單張檢視器 PhotoLightbox 已有的「載入完成後 easeOut(0.28) 淡入」規格不一致，快速左右滑動翻頁時尤其明顯是生硬的一次性跳出。改為 img 由 nil→有值時以 .transition(.opacity) + .animation(.easeOut(duration: 0.28), value:) 淡入，時間常數直接對齊 PhotoLightbox.imageAppeared，讓 App 內兩個全螢幕照片檢視器載圖手感一致，並在檔頭美化紀錄補上本次調整方向與下次可接續的方向（底部資訊面板進場動畫），方便下次查找。純視覺層調整，照片讀取、快取、刪除等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.89", build: 742, date: "2026/07/26", notes: [
            "【美化】變動支出／固定支出頁（VariableExpenseView／FixedExpenseView）monthSummaryHeader 大字金額防截斷：兩頁「本月變動支出」「本月固定支出」32pt 大字金額原本缺少 .lineLimit(1)／.minimumScaleFactor，與同款英雄卡 IncomeView.summaryHeader、Finance/AddStockView、Finance/RealEstateView 等既有防截斷規格不一致，金額位數較多（例如逼近或超過十萬、百萬）時在小螢幕裝置上有被裁切的風險。兩處皆補上 .lineLimit(1) + .minimumScaleFactor(0.5)，縮放下限維持可辨識大小，並在檔頭美化紀錄註解補上本次調整方向。純顯示層調整，金額試算、進度條比率等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.88", build: 741, date: "2026/07/26", notes: [
            "【美化】車輛卡片（VehicleDetailView）金額量級單位一致性：flashCard 估值大字、底部「購入」值原本各自呼叫私有 fmtWan(_:)（僅 %g 除以萬，無條件只顯示「萬」），與同檔案 vehicleKpiStrip／fixedExpenseRow／variableExpenseRow 皆已改用共用 Double.ntdWanString（跟進萬→億進位邊界）不一致，車輛估值一旦達 1 億以上會顯示成 5～6 位數的鉅額「萬」數字。新增 splitWan(_:)／splitWanLabel(_:) 從 ntdWanString 拆出數字／單位二段，供大字沿用既有字級與 contentTransition 動畫設計，兩處呼叫點改用新函式，並移除已無呼叫端的私有 fmtWan 死碼。純顯示層調整，估值、購入價、折舊率等既有試算邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.87", build: 740, date: "2026/07/26", notes: [
            "【美化】我的行事曆（MyCalendarView）本週快覽日期卡邊框一致性：補齊 v24（eventRow 徽章統一化）留下的待辦，weekDayCard 54×74pt 圓角卡片先前只有 background + shadow，缺少 overlay 細邊框，與同檔案 appleCalendarBanner、三個 section 卡片（當日事件／本週快覽／未來里程碑）既有的 RoundedRectangle stroke 規格不一致，深色模式下卡片邊界較模糊。補上 overlay(RoundedRectangle(cornerRadius: 14).stroke(...))：選中時 white.opacity(0.35)（對齊 TravelMapView.statsCard 白色徽章邊框慣例），未選中時 separator.opacity(0.12)（對齊本檔案 section 卡片既有邊框規格）。純視覺層調整，選取日期、事件計算、Apple 行事曆同步等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.86", build: 739, date: "2026/07/26", notes: [
            "【美化】部屬設備清單 PM／警報時間軸節點圖示一致性（SubordinateEquipmentView.SubordinateEquipmentTimelineSection）：補齊 v24.81 留下的待辦，timelineRow 左側 22pt 節點圖示原本只是單層純色圓（fill(color.opacity(0.15))），與同檔案 equipmentRow（36pt）、TravelMapView.spotRow（44pt）等錨點圖示既有的「LinearGradient 漸層 + Circle().stroke 外框」規格不一致。改為同款漸層（topLeading→bottomTrailing，0.22→0.09）+ 細邊框（lineWidth 0.75，依小尺寸比照 spotRow 而非 equipmentRow 的 1pt），讓時間軸節點與清單列圖示質感收斂一致。純視覺層調整，PM／警報時間軸排序、天數計算等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.85", build: 738, date: "2026/07/26", notes: [
            "【美化】醫療地圖畫面（MedicalMapView）補齊 v24.80 留下的待辦：健康狀況總結英雄卡（summaryCard）補上進場動畫（opacity 0→1 + 上移 20pt，spring 0.55/0.78），對齊 TravelMapView.statsCardAppeared／FoodMapView.headerCard 等全 App 英雄卡進場動畫規格，容器 onDisappear 重置旗標避免分頁切換殘留舊狀態。至此本畫面英雄卡與六個清單型 section 進場動畫已全數收斂一致。純視覺層調整，BMI／血型／KPI／今年醫療支出等既有資料讀取與計算邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.84", build: 737, date: "2026/07/26", notes: [
            "【修復編譯錯誤】旅遊地圖空狀態圖示（TravelMapView.swift:311）：.foregroundStyle(isPhotoFilter ? .secondary : .white) 三元運算式中，Swift 型別推論以第一個分支 .secondary 錨定為 HierarchicalShapeStyle，第二個分支 .white 在該型別上會回傳 Color 而非 HierarchicalShapeStyle，兩分支型別無法統一，Xcode 回報「Static property 'white' requires the types 'HierarchicalShapeStyle' and 'Color' be equivalent」與「Member 'white' in 'HierarchicalShapeStyle' produces result of type 'Color', but context expects 'HierarchicalShapeStyle'」兩條錯誤——與 v24.46 部屬執掌設備清單修過的為同型問題（階層樣式成員在前、具體顏色在後的混用三元式）。改為兩側都明確標注 Color（Color.secondary : Color.white），顯示效果完全不變。已全案掃描其餘同型寫法：色彩成員在前者型別可正確錨定為 Color、或已有明確 : Color 型別標注，均無此問題。"
        ]),
        ChangelogEntry(version: "24.83", build: 736, date: "2026/07/26", notes: [
            "【靜態除錯 v24.83】延續 v24.82 找到的 FoodMapView.emptyOverlay 同一 bug class（篩選/搜尋狀態切換不會改變外層 ZStack 身分，onAppear/onDisappear 不會重觸發），分兩路並行複查 Models 資料層（ExpenseStore／FinanceStore／LifeStore／CloudKitManager 等 18 檔）與 Views 畫面層（70+ 檔）後，在畫面層找到 3 處尚未套用 onChange 修法的殘留實例：① VariableExpenseView.emptyStateView、② IncomeView.emptyState 的雙層脈衝光環皆只在 onAppear/onDisappear 管理 Task，isSearching 由 searchText 計算而來、不會改變畫面身分，空清單時搜尋一次再清空搜尋框會讓脈衝動畫永久停止；③ TravelMapView.emptyOverlay 的 header 註解宣稱已「對齊 FoodMapView」，但實際只複製了視覺與 Task 取消寫法，未補上 onChange(of: photoOnly)，來回切一次「有照片」篩選一樣會讓脈衝永久停止。三處皆比照 FoodMapView.swift 既有的 onChange(of:) 修法補上（先取消舊 Task、旗標歸零，非篩選/搜尋狀態才重新排程）。Models 資料層複查後確認 force-unwrap／as!／try!、retain cycle、isSyncing 競態守衛、O(n²) 迴圈、重複 I/O 均無新問題（CloudSyncManager 既有 2 秒防抖＋30 秒節流架構正確，未變動）。",
        ]),
        ChangelogEntry(version: "24.82", build: 735, date: "2026/07/26", notes: [
            "【靜態除錯 v24.82】針對 v24.74～v24.81 新增的動畫/視覺程式碼做 bug-focused 複查（分兩路並行複查 SubordinateDetailView／SubordinateEquipmentView 與 MedicalMapView／FoodMapView，另手動複查 AdminConsoleView／FamilyOverviewMap 純視覺 diff），修復 2 處真實問題：① SubordinateDetailView 切換 Tab 時排的 50ms 延遲重播 Task（tabSectionsAppearTask）只在切換時取消重排，畫面本身缺少 onDisappear，若在切換 Tab 後 50ms 內就把整個 sheet 收合關閉，尚未觸發的 Task 仍會在畫面消失後補跑 withAnimation；補上 onDisappear 取消該 Task，對齊同檔案其餘可取消 Task 一律要有 onDisappear 的既有規格。② FoodMapView.emptyOverlay 雙層脈衝光環的 onAppear／onDisappear 掛在外層 ZStack 上，但「照片」篩選開關只會讓內層脈衝環用 if !isPhotoFilter 條件插入/移除、外層 ZStack 身分不變，導致空清單時來回切一次篩選開關後脈衝動畫永久停止（關閉時 Task 未取消、旗標未歸零；重新開啟時環雖重新插入，但已無 Task 讓 emptyIconPulse 從 false 變 true 觸發 animation(value:)）；改用 onChange(of: isPhotoFilter) 明確以篩選狀態驅動 Task 生命週期修復。SubordinateDetailView／SubordinateEquipmentView 的 isSaving 存檔刪除競態守衛、force-unwrap、retain cycle、O(n²) 迴圈複查後確認均無新問題（既有 6 處 delete() 守衛與新增的 EquipmentEditorSheet 均正確套用）。",
        ]),
        ChangelogEntry(version: "24.81", build: 734, date: "2026/07/25", notes: [
            "【美化】部屬設備清單（SubordinateEquipmentSection.equipmentRow）補齊 v2 留下的待辦：PM／警報數量標籤原本是無底色裸 Label，與同一列「30天內 N 次」及全 App 計數膠囊規格不一致；統一改為膠囊徽章（background+clipShape(Capsule)，警報數為 0 時底色改用中性 tertiarySystemFill，避免誤讀為異常）。純視覺調整，PM／警報筆數計算與顯示條件完全未變動。"
        ]),
        ChangelogEntry(version: "24.80", build: 733, date: "2026/07/25", notes: [
            "【美化】醫療地圖畫面（MedicalMapView）補齊 v24.78 留下的待辦：量測趨勢／過敏／服用中藥物／健檢紀錄／健康里程碑／醫療保障六個清單型 section，全部補上與就醫地點清單同規格的錯落淡入＋上移 12pt 進場動畫（spring 0.48/0.80，每列延遲 0.05s×idx，可取消 Task 延遲觸發＋onDisappear 重置，避免分頁切換閃爍）；抽出共用私有函式 staggeredRow／triggerStaggeredAppear，避免六處重複動畫樣板。本畫面清單型 section 進場動畫至此已全數收斂一致。純視覺層調整，健康資料讀取、排序、就診紀錄等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.79", build: 732, date: "2026/07/25", notes: [
            "【美化】美食地圖餐廳詳情 sheet（FoodMapView.RestaurantDetailSheet）補齊最後一處視覺缺口：底部「用地圖開啟」按鈕原本是本 sheet 唯一沒有描邊／陰影的扁平元素，與 headerCard／photoGallerySection／visitsSection／companionCard 皆已有的描邊＋陰影節奏不一致；補上 Capsule 同款描邊與輕量陰影，文字字重 medium→semibold 對齊全 App CTA 按鈕文字權重規格。純視覺調整，開啟地圖行為與座標計算完全未變動。"
        ]),
        ChangelogEntry(version: "24.78", build: 731, date: "2026/07/25", notes: [
            "【美化】醫療地圖畫面（MedicalMapView）就醫地點清單操作流暢性補強：本檔案自 v1 起完全沒有任何進場動畫，新增 clinicRowsAppeared 錯落淡入＋上移 12pt 進場動畫（spring 0.48/0.80，每列延遲 0.05s×idx），對齊 LifeOverviewView.categoryRowsAppeared／FamilyOverviewMap.houseRowsAppeared 等全 App 清單列進場動畫規格；容器 onAppear 用可取消 Task 延遲 0.05s 觸發、onDisappear 取消並重置旗標，避免快速切換分頁殘留 asyncAfter 造成閃爍。純視覺層調整，地點聚合、排序、就診紀錄等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.77", build: 730, date: "2026/07/25", notes: [
            "【美化】家庭總覽街道地圖（FamilyOverviewMap）大字自適應與空狀態補強：房子標籤與成員姓名自 v1 調大字級後從未補上 minimumScaleFactor，較長姓名或系統加大字級時會被直接截斷，補上 0.75 下限的等比縮小；上排無爸媽／親屬時原本只留一塊純空白佔位，改為淡化虛線房屋外框＋「尚無其他成員」提示，與其餘頁面空狀態需有明確提示的規格一致。純視覺與文字顯示調整，成員分組、房子歸類等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.76", build: 729, date: "2026/07/25", notes: [
            "【美化】管理控制台（AdminConsoleView）補齊與全 App 均值的視覺一致性差距：control 頁 5 個 Section（使用者人數／訂閱／對外顯示／版本更新紀錄／PIN）原本仍是系統預設純文字標題，未套用本頁 v1 就已在 pinGate 鎖定頁與使用者人數列建立的漸層規格，也落後於 SubordinateRosterView／OrganizationView 等頁面早已統一的「4pt Capsule 漸層色條＋圖示＋.subheadline.semibold」Section 標題規格；新增共用 sectionHeader(_:icon:color:) 輔助函式並套用到全部 5 處（依內容各自搭配識別色：藍／綠／紫／靛／橘）。純標題視覺升級，Section 內容、Toggle／Button 行為與既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.75", build: 728, date: "2026/07/25", notes: [
            "【美化】美食地圖餐廳清單 sheet（FoodMapView.listSheet）補齊與姊妹頁 TravelMapView.listSheet 的均值差距：原本用系統原生 List(.insetGrouped) 裝載餐廳列，是地圖類清單 sheet 中唯一還沒升級成自訂圓角卡片的頁面；改為 ScrollView + restaurantListCard（VStack + RoundedRectangle 16pt 圓角＋細邊框＋陰影＋列間 Divider），對齊 TravelMapView.citySection 圓角卡規格（未額外做縣市分組，因本頁資料無對應縣市解析欄位，強加會超出單純視覺調整範圍）；restaurantRow 補上獨立 padding 與 contentShape，確保脫離 List 後點擊熱區與視覺間距不變；新增 restaurantListEmptyState，篩選（如「照片」開關）後清單結果為零筆時不再顯示裸露空白清單，改為輕量灰階圖示＋提示文字卡片。純視覺容器調整，排序、篩選、開啟詳細 sheet 等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.74", build: 727, date: "2026/07/25", notes: [
            "【美化】部屬新增流程「選擇部屬」空狀態（SubordinateDetailView.AddSubItemSheet）：尚無部屬時原本顯示系統原生 ContentUnavailableView（純圖示＋文字，無動畫，且圖示色與 kind 無關固定為系統灰），是全 App 少數還沒補上動態回饋的頁面級空狀態；改為 62pt 雙圈脈衝光環（double-pulse ring：外圈 1.35 倍縮放呼吸＋內圈延遲 0.3 秒錯開）＋漸層底圓＋細邊框，對齊 SubordinateEquipmentView／SubordinateRosterView 等既有頁面空狀態規格，主題色改用 kind.color（任務＝cyan／會議＝indigo／報告＝purple，與清單列圖示識別色一致），動畫改用可取消的 Task 排程（onAppear 先取消前一個再排新的、onDisappear 一併取消歸零），避免 sheet 快速開關造成動畫殘留閃爍。純視覺調整，選擇部屬、切換至對應編輯 Sheet 等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.73", build: 726, date: "2026/07/25", notes: [
            "【靜態除錯 v24.73】三路並行複查全部 86 個 Swift 檔（force-unwrap／Optional／型別／index、retain cycle／競態、畫面閃爍／效能瓶頸），修復 13 處真實問題：① 資料正確性：IncomeView.deleteIncomes 刪除配息收入時，不分青紅皂白把 stock.linkedIncomeId 清空，會誤剪斷同一檔股票不相干的「賣出獲利」連結，且從未清 stock.dividends[i].linkedIncomeId，留下指向已刪收入的孤兒連結；改為比對 income.id 才清對應欄位。② 孤兒照片（4 處）：AddRealEstateView 建物類型改非透天厝或關閉「有電梯」時，電梯保養記錄整批不寫入卻沒刪對應照片；RealEstateView.deleteEstate 與 FinanceStore.deleteRealEstate 重複清理水電/裝潢/電梯/文件檔案，多打一次 CloudKit 刪除網路請求；RealEstateDetailView.duplicateLinkedExpense 複製連動支出時把 photoFileNames 陣列直接複製，複製品與原始支出共用同一批磁碟檔案，刪任一邊都會讓另一邊照片憑空消失；MultiPhotoGallery 相簿多選用的是無主裸 Task，畫面提前關閉不會取消，寫入磁碟後 append 進脫離畫面的 fileNames，比照 onDisappear 取消＋取消時清掉已寫入的檔案修復。③ 存檔刪除競態（6 處）：SubordinateDetailView 的 RecordEditorSheet／MeetingEditorSheet／TaskEditorSheet／WeeklyReportEditorSheet 與 SubordinateEquipmentView.EquipmentEditorSheet、RealEstateDetailView.UtilityPaymentEditor 共 6 個 delete() 只在 save() 守了 isSaving，刪除本身完全沒設旗標，sheet 收合動畫播完前快速點「刪除」再點「儲存」會讓剛刪除的紀錄被原封不動地加回去，比照既有寫法補上守衛。④ 畫面閃爍：TaxOverviewView 年份切換與 monthlyBreakdown 進場共用同一個 yearNavAnimTask，由零筆年度切到有筆年度時會搶先取消 yearPicker 排的 Task，只補回 monthBarAppeared 卻漏了 heroCardAppeared，導致年度摘要卡在該年度永遠停在 opacity 0；FamilyMembersResumeView.FamilyAlbumPhotoEditor 相簿選圖（尤其 iCloud 原圖）尚未載入完成前儲存按鈕沒有鎖定，會在 pendingImageData 寫入前就存檔完成，選取的照片被悄悄丟棄，新增 isPhotoLoading 旗標鎖住儲存按鈕；MyCalendarView 的「未來 30 天里程碑」區塊（含空狀態、溢出列）早已完整實作，但先前重整版面時漏了呼叫點，英雄卡「未來 30 天」計數旁始終看不到任何內容，補上呼叫。⑤ 效能瓶頸（2 處）：FinanceOverviewView 的 totalAssetsNTD／assetCards／ntdAllocations 各自呼叫 store.totalStockValue／totalVehicleValue／totalRealEstateValue（皆為全量 filter+reduce），單次 render 合計最多被呼叫 5 次，cashFlowSection 的 monthlyCashFlow 又是 monthlyRentalIncome-monthlyMortgagePayment，三個分開呼叫等於多算兩次；RealEstateView 已出售清單每列都重新呼叫 activeEstates（filter+sort 全量陣列）取 count 當動畫延遲；均改為算一次往下傳。⑥ 資料一致性：StockView 持股計數膠囊用未過濾的 store.stocks.count，隔壁市值卻已排除已出售股票，賣光一檔後計數與市值對不上，改用同函式已收到的 active.count。⑦ 順手補上 AddVehicleView 購入日期往後調整時未回頭校正既有售出日期，避免存出售出早於購入的無效資料。CloudKit 30 秒節流／[weak self]／O(n²) 聚合複查後確認其餘既有寫法均完整涵蓋；MultiPhotoGallery/AddExpenseView 等既有 isSaving／cancelable Task 規格均已正確套用，未發現新問題。"
        ]),
        ChangelogEntry(version: "24.72", build: 725, date: "2026/07/24", notes: [
            "【美化】升級訂閱頁（PaywallView）操作區：① 「還原購買」按鈕先前完全沒有讀取 SubscriptionManager.restoreInProgress 這個既有旗標，點下去後畫面毫無回饋；補上還原中的 ProgressView 圖示替換＋「還原中…」文案＋按鈕停用，對齊訂閱方案列 purchaseInProgress「處理中，請稍候…」的回饋規格；② 訂閱方案價格 Capsule（productRow／fallbackProductRow）補上 lineLimit+minimumScaleFactor 防截斷保護，避免大字級輔助模式下價格文字被裁切或撐破膠囊邊框。純視覺與載入狀態回饋調整，購買、還原購買、商品讀取等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.71", build: 724, date: "2026/07/24", notes: [
            "【美化】部屬「執掌」分頁設備編輯表單（EquipmentEditorSheet）補齊 PM／警報清單項目新增、刪除時的過場動畫：新增時彈簧淡入＋上滑，刪除時同款淡出，取代原本瞬間跳出/消失的生硬手感，對齊 AddExpenseView／ResumeGiftSection 既有清單新增/刪除過場規格。純視覺調整，PM／警報記錄的儲存、排序、刪除設備等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.70", build: 723, date: "2026/07/24", notes: [
            "【美化】旅遊相簿空狀態（TravelAlbumSheet）補齊本頁最後一處均值差距：原本用系統原生 ContentUnavailableView（純圖示＋文字，無動畫），與同檔案地圖 emptyOverlay 已升級的雙層脈衝光環規格不一致；改為 albumEmptyState：同款雙層脈衝光環＋漸層底圓＋細邊框＋.ultraThinMaterial 圓角卡片，並用可取消的 Task 排程管理脈衝動畫（sheet 開關時正確歸零，避免重疊計時任務）。純視覺調整，相簿照片彙整邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.69", build: 722, date: "2026/07/24", notes: [
            "【美化】旅遊地圖（TravelMapView）空狀態與篩選膠囊補齊與姊妹頁 FoodMapView 的均值差距：① emptyOverlay 原本單層呼吸縮放圓，且「有照片」篩選導致零筆時仍顯示「還沒有旅遊足跡」誤導文案；升級為雙層脈衝光環＋漸層底圓＋細邊框，並依 photoOnly 篩選狀態切換灰階提示「目前沒有附照片的地點／關閉右上角『有照片』開關可查看全部地點」，避免誤以為完全沒記錄過；背景改用 .ultraThinMaterial 圓角卡片，取代原本貼在地圖上的不透明色塊，深色模式更自然融入地圖底色；② chip()（期間／縣市篩選膠囊）補上選中彈簧動畫，修復切換篩選時瞬間跳變、無回彈手感的問題。純視覺與空狀態文案調整，地圖標註、資料聚合、篩選或排序等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.68", build: 721, date: "2026/07/24", notes: [
            "【美化】主畫面殼層底部頁籤與 AI 語音麥克風（MainTabView）：① 底部頁籤選中膠囊深色模式下漸層與外框不透明度提高，修復與頂部子功能列分組膠囊相同的深色背景吃色問題，頁籤標籤文字同步補上防截斷保護；② AI 語音麥克風新增「啟動中」過渡態（按下到實際開始錄音之間，多半在等權限對話框）——輕縮小＋淡化，讓使用者立即知道按壓已被接收，不再誤以為沒按到。純視覺調整，分頁切換、麥克風錄音／AI 記帳送出等既有邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.67", build: 720, date: "2026/07/24", notes: [
            "【美化】主畫面殼層（MainTabView）頂部子功能列與浮動新增按鈕：① subFeaturePill 標題文字補上防截斷保護，避免「我的行事曆」等 4~5 字標題在大字級輔助模式下換行撐高整條頂部子功能列；② 職涯／家庭分組膠囊背景改依深色模式提高不透明度（0.10→0.20），修復深色模式下背景幾乎看不見的問題；③ 浮動新增按鈕彈出選單「新增收入／新增支出」與收合狀態「新增收支」文字同步補上防截斷保護。純視覺調整，分頁切換、FAB 拖曳吸邊、AI 語音記帳等既有邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.66", build: 719, date: "2026/07/24", notes: [
            "【美化】兒童疫苗接種時程頁（ChildVaccineScheduleView）：① 標頭新增整體接種進度條（漸層填色＋glow overlay，隨完成劑數以彈簧動畫平滑過渡），完成度計數膠囊補上防截斷保護；② 各接種期分組標頭補上「已完成／應接種」劑數膠囊，不必逐列數算即可掌握進度；③ 疫苗列表與舊版疫苗紀錄列改為交錯淡入＋向上進場動畫，並補上長疫苗名稱的自適應縮小保護；④ 未設定生日提示改為漸層圖示錨點，與全 App 提示區塊視覺一致。純視覺調整，接種狀態判斷、日期推算、存檔邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.65", build: 718, date: "2026/07/24", notes: [
            "【美化】部屬「執掌」分頁設備清單（SubordinateEquipmentView）對齊 SubordinateRosterView／GradeTitleView 規格：① 設備清單空狀態由靜態圖示升級為雙圈脈衝光環（double-pulse ring），使用可取消的 Task 排程，避免頁面快速切換造成動畫殘留閃爍；② 設備列、PM／警報時間軸列加入 stagger opacity+Y offset 入場動畫，與部門/職等等頁面列一致；③ 設備名稱、時間軸設備名稱補上 lineLimit+minimumScaleFactor，避免長名稱在大字級輔助模式下截斷或爆版；④ EquipmentEditorSheet 的 PM／警報空狀態提示補上圖示錨點，強化可辨識度。純視覺調整，設備新增/編輯/刪除、PM／警報記錄邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.64", build: 717, date: "2026/07/24", notes: [
            "【靜態除錯 v24.64】三路並行複查全部 86 個 Swift 檔（force-unwrap／Optional／型別／index、retain cycle／競態、畫面閃爍／效能），修復 6 處真實問題：① 電子發票誤記作廢發票為支出：EInvoiceSyncManager.performSync 從財政部 API 取回發票後從未檢查 invStatus，商家已作廢（非「開立」）的發票仍會照常轉成一筆真的 Expense，比照既有 skipped 計數方式在寫入前補上狀態過濾。② 5 處「新增」表單漏補 isSaving 存檔重複送出守衛（此前各輪只修了「編輯」既有紀錄的表單，這 5 個是既有寫法統一套用時漏掉的「新增」個案，快速連點會用不同 UUID 建立兩筆重複紀錄）：OrganizationView（新增組織人員，連帶複製一張多餘的自動名片）、GradeTitleView（新增部門，並重複執行雙向關聯同步）、SubordinateView（新增部屬）、ResumeView（新增里程碑／家庭成員）、LifeFinanceView（新增銀行存款／提款／轉帳，最嚴重可能兩筆轉帳都送出、造成餘額算錯）。③ HolographicBuildingView 呼吸燈動畫缺重入守衛：pulse 的 repeatForever 動畫沒有比照同函式內 tagsAppeared 的守衛寫法，onAppear 若因父層重建等原因再次觸發，會在還在振盪中的舊動畫上疊加一個新的造成跳動（此元件目前無任何呼叫點尚未上線，先行修正避免未來串接後才出現閃爍）。④ 清除 SubordinateDetailView 死碼 mentionedCount(for:)：從未被呼叫、但簽章會誘使未來新增逐列呼叫點、重新引入已在 TalentMatrixView／SubordinateView 修復過的 O(N×M) 全量重掃描，直接刪除。CloudKit 30 秒節流／force-unwrap／O(n²) 聚合複查後確認其餘均無新問題（節流、快取、［weak self］等既有寫法均完整涵蓋）。"
        ]),
        ChangelogEntry(version: "24.63", build: 716, date: "2026/07/24", notes: [
            "【靜態除錯 v24.63】並行複查全部 86 個 Swift 檔（Models／Finance Views／Life Views 三路），修復 11 處真實問題，均為前 24 輪複查漏掉的個案：① 存檔重複送出（sheet 收合動畫播完前快速連點會建立兩筆重複紀錄，比照既有 isSaving 寫法修復）：BusinessCardEditor（名片新增／編輯）、FamilyEventEditor／FamilyAlbumPhotoEditor（家庭紀錄／相簿）、AddExpenseView（記一筆支出，全 App 最常用的存檔頁面卻是唯一漏掉 isSaving 守衛的個案）、StockTransactionEditor／StockDividendEditor（股票交易／股利）、RealEstateDetailView.FloorItemEditor（樓層物件，新增／刪除因故意延遲一個 runloop 才寫回 store，快速連點會讓較晚落地的一次覆蓋掉較早一次的結果，導致其中一筆物件憑空消失）、SettingsView.exportFullBackup（完整備份匯出，同排三個匯出功能都有 exportBusy 守衛卻獨漏這個）。② 刪除／存檔競態：ChildDetailView 的 2 個育兒紀錄編輯 Sheet 只在 save() 守了 isSaving，delete() 完全沒設旗標，快速點「刪除」再點「儲存」會在 dismiss 動畫播完前讓 save() 把剛刪除的紀錄用舊表單值原封不動地加回去。③ 資料連結孤兒／誤刪：VariableExpenseView.deleteWithSync 解除股票連結時沒有比對 linkedExpenseId 是否等於被刪除的支出（複製支出出的重複 linkedStockId 刪除時會誤剪斷原始支出與股票的真實連結）；AddExpenseView 編輯既有支出時把連結對象（車輛／不動產）切換到別的物件，原本 sync 函式只會寫入新目標，舊目標的房貸／車貸／變動支出紀錄會變孤兒且金額不再更新，比照既有 removeAll 清理寫法在車貸／固定支出關聯車輛／變動支出關聯車輛／變動支出關聯不動產／房貸連結不動產五處補上舊目標清理。④ 資料正確性：AddExpenseView 切換車輛支出類別 Picker 時，若新車輛動力類型不支援原本選的類別（例如油電車換純電車後「油錢」已不在選項內），底層狀態不會自動校正，存檔會把不合動力類型的類別寫入；AddIncomeView 設定收入結束日後又把起薪日往後調整，若調整後起薪日晚於既有結束日，DatePicker 的 in: date... 只限制往後可選範圍、不會回頭修正已選定的舊值，存檔會產生 endDate 早於 date 的無效資料；IncomeView.splitCurrency 只處理「萬」字尾，累計收入達 1 億以上時「億」字尾不會被拆到獨立那一行，KPI 版面跟其餘量級不一致。全部比照既有寫法（isSaving／busy 守衛、removeAll 清理、onChange 校正）修復，未做任何無關重構；CloudKit 節流／force-unwrap／retain cycle／O(n²) 複查後確認均無新問題。"
        ]),
        ChangelogEntry(version: "24.62", build: 715, date: "2026/07/24", notes: [
            "【美化】履歷頁（ResumeView）與財富頁（LifeFinanceView）看板捲動行為對齊儲蓄險頁規格（承接 v24.61 股票頁同型調整）：兩頁的英雄看板＋篩選列過去都是固定釘在列表上方（VStack 外層、不隨捲動移動），與儲蓄險頁「看板為 List 首個 Section、隨內容一起捲動」的行為不一致。① 履歷頁：resumeHeroCard＋categoryFilter 抽成共用 headerSections（List 內首個 Section），分組列表／單分類篩選列表／空狀態三種模式共用（空狀態新增 emptyStateList 包裝，改為同款 insetGrouped List），捲動時看板隨內容上捲、大標題自動收合；② 財富頁：summaryHeader＋filterChips 移入 milestoneList 的 List 首個 Section，看板由滿版無圓角橫幅改為圓角 20 卡片＋主色光暈陰影（radius 16, y 8）＋16pt 水平內縮，對齊儲蓄險 summaryHeader 卡片規格，List 補 scrollContentBackground(.hidden)；milestoneList 改帶 balance 參數避免重複計算銀行餘額。兩頁看板內容、篩選、列表互動與進場動畫規格完全未變動。"
        ]),
        ChangelogEntry(version: "24.61", build: 714, date: "2026/07/24", notes: [
            "【美化】股票頁（StockView）看板與捲動行為對齊儲蓄險頁規格：股票頁過去用自訂 stickyTitle（固定釘在頂部、隨捲動縮放淡出的「股票」大字）+ ScrollOffsetKey preference 追蹤捲動位移 + .inline 導覽列，與儲蓄險頁的系統標準大標題（.large，捲動自動收合進導覽列）行為不一致；英雄卡也是滿版無圓角橫幅（頂部還墊 44pt 補償 stickyTitle），與儲蓄險的圓角 20 卡片式看板視覺不同。本次整組對齊：① 移除 stickyTitle／scrollOffset／titleScale／titleOpacity／ScrollOffsetKey 整套自訂機制，改用 .navigationTitle(\"股票\") + .large 系統標準大標題，捲動收合行為與儲蓄險完全一致，也省去每次捲動觸發整個 body 重繪的成本；② 英雄卡改為圓角 20 卡片 + 橙色主色光暈陰影（radius 16, y 8）+ 16pt 水平內縮，對齊儲蓄險 summaryHeader 卡片規格，並移除 44pt 頂部補償；③ 空狀態分支同步移除 stickyTitle 疊層。看板內容（總市值/持股計數/損益 KPI/配置迷你條）與其餘互動完全未變動。"
        ]),
        ChangelogEntry(version: "24.60", build: 713, date: "2026/07/23", notes: [
            "【美化】收入頁英雄卡 KPI 金額改為直式三行堆疊：v24.59 新增「今年累計」後 KPI 擴為四格，「NT$XX.X萬」單行顯示在窄格內被 minimumScaleFactor 縮得難讀。改為 NT$（小字）↵ 數字（15pt 粗體，放大近一倍）↵ 萬（小字）直式堆疊，數字成為視覺主體；新增 splitCurrency(_:) 把 ntdWanString 格式拆成幣別/數字/單位三段，未滿一萬（無「萬」字）時自動省略第三行。四格（累計收入/今年累計/月均收入/固定月收）一體適用，計算邏輯不變。"
        ]),
        ChangelogEntry(version: "24.59", build: 712, date: "2026/07/23", notes: [
            "【功能】收入頁英雄卡 KPI 新增「今年累計」：在既有「累計收入」（從最早一筆到現在）旁新增每年 1/1 重新起算的今年累計收入，跨年自動歸零重計。計算方式（ExpenseStore.yearToDateIncomeTotal）：逐月加總今年 1 月至本月的收入合計，與既有 incomeTotal(for:) 同一套規則——單次收入計實際發生月份、每月週期收入逐月累計、年薪攤 12 個月、固定薪水設有結束日者結束月後不再計入。KPI 橫列由三格（累計收入／月均收入／固定月收）擴為四格（累計收入／今年累計／月均收入／固定月收），既有 kpiCell 的 minimumScaleFactor 縮放確保四格並列不換行。"
        ]),
        ChangelogEntry(version: "24.58", build: 711, date: "2026/07/23", notes: [
            "【靜態除錯 v24.58】承接 v24.57 繼續複查全部 86 個 Swift 檔尚未覆蓋的空狀態脈衝/進場動畫，修復 11 處同一 bug class 的畫面閃爍：ChildrenResumeView／SubordinateView／OrganizationView／LifeRealEstateView（emptyIconPulse）、FoodMapView（emptyIconPulse，篩選「僅顯示有照片」快速切換即可觸發，原本 onAppear 就沒有取消保護）、ResumeView／FamilyView（emptyStatePulse／emptyIconPulse）、SpouseResumeView（emptyPlaceholder 共用元件，milestoneEmptyPulse／expenseEmptyPulse 兩處呼叫點）、TaxOverviewView（emptyRecordsPulse／emptySavingPulse，年份 Picker 已會歸零旗標卻從未取消對應 asyncAfter，快速切換年份會讓舊排程在新一輪重置後補一次遲到觸發）、GradeTitleView（rowsAppeared 進場動畫）、LifeOverviewView（categoryRowsAppeared 分類列進場動畫，此頁為 MainTabView 分頁根視圖，快速切換分頁即可觸發），皆比照既有寫法統一改為可取消的 Task（onAppear 先取消前一個再排新的、onDisappear 一併取消並歸零旗標）。另複查 TravelMapView／FoodMapView 的 sheet 切換延遲、BusinessCardView 掃描佇列/聯絡人匯入延遲、RealEstateDetailView 命名 Sheet 的鍵盤 focus 延遲、SubordinateRosterView 今日自動捲動（旗標僅觸發一次不會重複排程）等其餘 asyncAfter 用法，均為一次性交握、無可快速重複觸發路徑，不屬同一 bug class，未做改動。CloudKit 三條同步路徑（CloudSyncManager 30 秒節流＋2 秒防抖、EInvoiceSyncManager 間隔判斷、RemoteAdminManager 30 秒節流）複查後確認皆無新的繞過路徑；force-unwrap／as!／try! 複查僅有的幾處皆為編譯期常數 URL 或已由前置條件保證非空的陣列存取，retain cycle（Timer／NotificationCenter）複查亦均已妥善保護，未發現新問題。"
        ]),
        ChangelogEntry(version: "24.57", build: 710, date: "2026/07/23", notes: [
            "【靜態除錯 v24.57】承接 v24.56 並行複查（Finance／Life Views 兩路），修復 9 處畫面閃爍問題：RealEstateView／SavingsInsuranceView／StockView／VehicleView（Finance）與 CareerView／BusinessCardView／LifeOverviewView／OverviewView／SubordinateRosterView（Life）的空狀態脈衝光環／進場動畫，皆使用未持有 token 的 DispatchQueue.main.asyncAfter(0.3~0.6s) 排程進場動畫，且對應 View 皆存在可快速重複掛載/卸載的真實觸發路徑（Finance 四頁由 MainTabView 頂部子功能列 pill 快速切換分頁觸發；CareerView 快速切換篩選分類；BusinessCardView 搜尋關鍵字在零筆/有筆間快速切換且原本連 onDisappear 重置都沒有；LifeOverviewView 為多個人生子分頁「無資料時」的共用回退畫面，快速切換子分頁即可觸發，同樣原本沒有 onDisappear 重置；OverviewView 由記帳模式分頁選單快速切出切回觸發；SubordinateRosterView 快速切換部屬部門篩選觸發），較舊一次掛載排程的 closure 可能在較新一次已把旗標重置為 false 之後才觸發，造成脈衝動畫倒退/跳幀閃爍，與 v24.51~24.55 已修復的同類案例（IncomeView／VariableExpenseView／FixedExpenseView／ChartView／TaxOverviewView／MainTabView 等）屬同一 bug class 但先前複查漏掉這 9 處；比照既有寫法統一改為可取消的 Task（onAppear 先取消前一個再排新的、onDisappear 一併取消）。另 Models 層複查（force-unwrap／型別錯誤／index 越界／retain cycle／競態條件）與 Finance／Life Views 兩路其餘檔案複查後未發現新問題（既有 debounce／快取／防重入寫法已到位）。"
        ]),
        ChangelogEntry(version: "24.56", build: 709, date: "2026/07/23", notes: [
            "【靜態除錯 v24.56】並行複查全部 86 個 Swift 檔（Models／Finance Views／Life Views 三路），Models 部分修復 1 處真實問題：UnifiedImporter.applyUnified 的「取代」模式（完整備份還原）只在被淘汰的 Expense／RealEstate 上做匯入前清理（v24.53 已修復），但同一段落緊接著整批覆蓋的 familyMembers／businessCards／orgPeople 卻從未比照清理——FamilyMember 內嵌的兒女記錄照片、家庭相簿照片，以及 BusinessCard／OrgPerson 各自的大頭照，若使用者還原的完整備份中該筆家庭成員/名片/組織人脈已被移除或照片已被移除，舊照片檔案會永久留在磁碟上，並被 CloudKitManager.uploadAllLocalPhotos() 當成「未上傳的本機照片」反覆重傳；改為比照既有 Expense／RealEstate 的寫法，在整批覆蓋前先清掉被取代模式淘汰、不在新資料中的成員/名片/人脈之附帶照片檔案。Finance／Life Views 兩路複查仍在進行，結果將於後續版本補齊。"
        ]),
        ChangelogEntry(version: "24.55", build: 708, date: "2026/07/23", notes: [
            "【靜態除錯 v24.55】承接 v24.54 並行複查（Finance／Life／根層 Views 三路），修復 6 處真實問題：① VehicleView「折舊開關」按鈕點下去會直接以每年 15% 折舊率覆蓋所有車輛的「目前估值」（使用者可自由編輯的手動估值欄位，非衍生值），且無任何提示，再點一次只會切回按鈕外觀、原本輸入的估值已回不去；改為點下時先跳出確認 Alert 說明會覆蓋且無法復原，取消可安全離開。② SubordinateDetailView 的 4 個編輯 Sheet（請假/優缺點/成就疏失、會議、任務、週報）與 ChildDetailView 的 2 個編輯 Sheet（育兒即時記錄、兒女記錄）、SubordinateEquipmentView 的設備編輯 Sheet，共 7 處存檔按鈕只檢查欄位是否填寫、未檢查是否已在存檔中，這正是 v24.31/34 已於 AddIncomeView／AddVehicleView／AddSavingsInsuranceView／AddStockView 等處修復過的「sheet 收合動畫尚未播完前按鈕仍可被點擊，快速連點會建立兩筆重複紀錄」同類遺漏；比照既有 isSaving 寫法補上（存檔中鎖住按鈕、save() 開頭 guard 防重入）。③ TaxOverviewView.monthlyBreakdown 內部自己的 onAppear 動畫延遲用未持有 token 的 DispatchQueue.main.asyncAfter(0.12s)，未被 v24.53 已修復的年份切換 yearNavAnimTask 一併取消，快速切換年份經過「當年度無稅務支出」的空年份再切回有資料的年份，較舊的一次 remount 排的動畫可能在新一次 yearNavAnimTask 已把 monthBarAppeared 設回 false 之後才觸發，月份分佈進度條動畫倒退閃爍；改為共用同一個 yearNavAnimTask，切換時互相取消。④ IncomeView／VariableExpenseView／FixedExpenseView 三個空狀態的脈衝光環進場動畫同樣用未持有 token 的 DispatchQueue.main.asyncAfter(0.3s)，搜尋結果在零筆與有筆之間快速切換（如打字/修正關鍵字）時，空狀態 View 反覆掛載/卸載，較舊的一次待觸發 closure 可能在較新一次已把旗標重置為 false 後才觸發，脈衝光環動畫跳幀；比照 ChartView.trendPulseTask 既有寫法改為可取消的 Task，並補上 onDisappear 取消，三個檔案手法一致。"
        ]),
        ChangelogEntry(version: "24.54", build: 707, date: "2026/07/23", notes: [
            "【靜態除錯 v24.54】並行複查全部 86 個 Swift 檔（Models／Finance 分頁／Life 分頁／根層 Views＋App 進入點），Models 部分修復 1 處真實問題：UnifiedExport.LifeBundle（統一備份/匯出結構）長期漏帶 LifeStore 的三個集合——名片（businessCards）、組織人脈（orgPeople）、個人行事曆事件（personalEvents），三者皆有完整的 CloudSyncManager 同步鍵（life_business_cards／life_org_people／life_personal_events）與 UI 頁面（OrganizationView／SubordinateDetailView）在使用，但 UnifiedExport.build／UnifiedImporter.applyUnified／ImportResult 從未提及；由於 FullBackup.export／restore 與 BackupManager 的自動快照皆透過 UnifiedExport 走完整備份，使用者若未開 iCloud 同步、或執行「完整備份」匯出後在新機／清除後還原，備份會回報成功但名片、組織人脈、個人行事曆事件全部無聲消失且無法復原。修復：LifeBundle 補上三個欄位、build() 帶入、ImportResult 補計數與摘要文字、applyUnified 的 replace／merge 兩種模式都比照既有 subordinates／departments／gradeTitles 的寫法接上（merge 用既有 mergeItems 依 id 略過重複）。Finance／Life／根層 Views 三路複查仍在進行，結果將於後續版本補齊。"
        ]),
        ChangelogEntry(version: "24.53", build: 706, date: "2026/07/22", notes: [
            "【靜態除錯 v24.53】三路並行複查全部 86 個 Swift 檔（Models／Finance 分頁＋根層 Views／Life 分頁＋App 根層），修復 4 處真實問題：① FinanceStore.clearAll（清除所有資料）與 deleteRealEstate／deleteRealEstate(at:) 不同，直接呼叫 realEstates.removeAll() 而未先呼叫 cleanupRealEstateFiles，房地產內嵌的電梯保養／水電繳費／裝潢照片／文件檔案不會被清掉，永久留在磁碟並被 CloudKitManager.uploadAllLocalPhotos() 當成「未上傳的本機照片」反覆重傳；改為清除前先逐筆呼叫 cleanupRealEstateFiles。② UnifiedImporter 合併模式（.merge）匯入股票／車輛／房地產時，既有項目（同 id）用淺層 mergeItems 整筆略過，導致另一台裝置備份中新增的股票交易/股利、車輛支出、房地產水電繳費/裝潢照片/文件等子項目在合併模式下永遠進不來（同一 id 的房地產被判定「已存在」，附件位元組又已被 FullBackup.restore 無條件寫入磁碟，形成孤兒檔案）；比照上方家庭成員／部屬既有的深度合併寫法（appendNewByID），改為既有項目才補進新的子項目、不存在的項目整筆新增。③ AddIncomeView 固定薪資「結束日期」DatePicker 未設下限（未要求晚於收入起始日期），選到早於起始日的結束日期會讓 Income.isActive(in:) 對每個月都回傳 false，但 IncomeView.totalIncomeAll 的月數計算又用 max(1, ...) 夾住成至少 1 個月，造成「本月收入」與「累計收入」兩個畫面數字互相矛盾；比照既有已修復的日期上下限寫法補上 in: date...。④ SubordinateDetailView 切換分頁分頁（主動性/潛力性/執掌）與 TaxOverviewView 切換年度／年份 onChange 的進場動畫皆用未持有 token 的 DispatchQueue.main.asyncAfter(0.05~0.08s)，快速連續切換會疊出多個待觸發 closure，較舊的一個可能在較新的已把旗標設回 true 之後才觸發，動畫倒退造成閃爍，是 v24.52 MainTabView 麥克風動畫修復的同類、未修的殘留案例；改用可取消的 Task（比照 MainTabView.micEnterTask 既有寫法），切換時先取消前一個再排新的。CloudKit 30 秒節流／2 秒防抖複查後未發現新的繞過路徑。"
        ]),
        ChangelogEntry(version: "24.52", build: 705, date: "2026/07/22", notes: [
            "【靜態除錯 v24.52】四路並行複查全部 86 個 Swift 檔（Models／Finance 分頁／Life 分頁／根層 Views），修復 4 處真實問題：① FinanceStore.deleteRealEstate 與 LifeStore.deleteFamilyMember／clearAll（清除所有資料）刪除時只移除陣列項目，從未清掉內嵌的電梯保養／水電繳費／裝潢照片／文件檔案（房地產）與兒女記錄／家庭相簿照片（家庭成員），檔案永久留在磁碟與 iCloud、被 CloudKitManager.uploadAllLocalPhotos() 當成「未上傳的本機照片」反覆重傳，使用者按下「清除所有資料」後也會誤以為資料已完全清除；比照既有 UnifiedImporter.applyUnified／deleteOrgPerson／deleteBusinessCard 的清理寫法補上對應刪除。② EInvoiceSetupView 手機條碼驗證：.autocapitalization(.allCharacters) 只影響鍵盤輸入、對「貼上」文字無效，且 EInvoiceSyncManager.linkCarrier 內部只 trim 不轉大寫，使用者從簡訊/信件複製貼上小寫條碼會被正確格式誤判為錯誤；改為驗證前先 trim 並轉大寫，一併用轉換後的字串連結載具。③ ResumeView 家庭成員「結婚日期」與「出生日期」DatePicker 未設上限（既有「離婚日期」則有下限但也未設上限），可選未來日期，導致 ChildDetailView／ChildrenResumeView／SpouseResumeView 算出的年齡/結婚年數顯示負值（如「-1 歲」）；比照本檔案既有 MacaronDatePicker(in: ...Date()) 規格補上上限。④ MainTabView 切換「變動支出」分頁的麥克風進場動畫用 DispatchQueue.main.asyncAfter(0.05s) 且未持有 token，50ms 內快速切出又切回會疊出多個待觸發的 closure，較舊的一個可能在較新的已把 micEntered 設回 true 之後才觸發，動畫倒退造成閃爍；改用可取消的 Task（比照 ChildDetailView.clinicDebounceTask 既有寫法），切換時先取消前一個再排新的。另外複查後排除一項誤判：AdminConsoleView 的 PIN 更新原懷疑存入未 trim 的值，經追蹤 RemoteAdmin.setAdminPIN 內部本就會 trim 後才寫入 UserDefaults，並非真實問題，未做改動。RealEstateDetailView 的 ForEach(0..<draft.urls.count) 經確認 draft 為傳入時的不可變 let 快照，不會於顯示期間變動，非既有已修復案例的同類風險。CloudKit 30 秒節流／既有防抖機制複查後未發現新問題。"
        ]),
        ChangelogEntry(version: "24.51", build: 704, date: "2026/07/22", notes: [
            "【靜態除錯 v24.51】三路並行複查全部 86 個 Swift 檔（Models／Finance 分頁／人生分頁），修復 4 處真實問題：① NotificationManager 月/年重複事件的通知時間會漂移：advanceToNextOccurrence 找到「第一個未來次數」後，若該次數本身已被 Calendar 夾過（例如每月 31 號事件跳到 2 月被夾成 28 號），enumerateFires 誤把這個被夾過的日期當成新錨點繼續往後推算，導致後續每一期都改成從 28 號起算（3 月變 28 號），與行事曆畫面永遠錨定在原始 31 號算出的日期脫勾，通知時間與畫面顯示的日期對不上。改為 enumerateFires 一律以原始 baseFire 為錨點、只帶入起始期數索引往後推算。② InvoiceCategorizer：使用者新增的電子發票分類規則永遠排在預設規則之後（addRule 只會 append），若關鍵字與內建規則重複，categorize() 取第一個命中就永遠回傳預設分類，使用者規則形同無效且無任何提示；改為比對時使用者自訂規則優先於預設規則。③ AIVariableCategoryMapper 的中文分類字串比對第 4 步用 for-in 直接疊代 Dictionary 做子字串比對，Swift Dictionary 疊代順序每次啟動隨機，AI 回傳含多個關鍵字的複合字串（如「交通/稅費」）可能因疊代順序不同、在不同次啟動被分類成不同類別；改為依關鍵字長度由長到短排序後比對，結果穩定且優先命中較具體的關鍵字。④ MainTabView 浮動新增按鈕（FAB）拖曳時的畫面閃爍：拖曳手勢的 onChanged 幾乎每個像素觸發一次，但拖曳狀態（fabOffset／fabDragOffset／showQuickAdd）原本是 MainTabView 自己的 @State，即使已拆成 computed var，SwiftUI 仍視為同一棵樹整個重新求值，連帶重算頂部子功能列與底部 Tab Bar，拖曳「+」時明顯掉幀閃爍；拆成獨立的 FloatingActionButtonView（自己的 @State），讓 SwiftUI 的 diffing 把拖曳更新隔離在按鈕本身。同時把 StockView.refreshAllPrices() 的逐檔序列 await 改為 TaskGroup 平行送出報價請求，多檔股票更新報價的等待時間從「N 次序列網路往返」降到「最慢一檔的時間」，並維持原有逐筆即時角標回饋與批次寫入行為不變。CloudKit 30 秒節流／2 秒防抖、Life 分頁 30 個檔案複查後未發現新問題（既有 debounce／快取／off-main-thread 圖片載入等防護已到位）。"
        ]),
        ChangelogEntry(version: "24.50", build: 703, date: "2026/07/22", notes: [
            "【功能】部屬總覽（SubordinateOverviewView）新增「文字匯出」分享：右上角「＋」選單旁新增分享按鈕，一鍵把整頁總覽組成 Emoji 排版純文字並開啟系統分享面板（LINE／訊息貼上即完整顯示）。內容對齊頁面結構且包含已完成項目：📊 標題列（選取日期）→ 🌴 當日請假（姓名/假別/時數）→ 📄 報告（完成進度 X/Y，✅/⬜️ 並列，逾期標 ⚠️、已完成附 🏁 完成日）→ 👥 當日會議（時間/長度/議程進度，議程項目 ✅/⬜️ 全列、已完成附 🏁、未完成附 ⏰ 截止）→ 📋 未完成任務（跨所有日期，附截止日）→ 🗂 未完成會議條目（跨所有會議）→ ✅ 已完成區（與頁面底部收合卡同內容：報告/會議條目/任務依完成時間新到舊，🏁 日期＋類型 Emoji＋標題＋部屬名）。排版規格對齊部屬卡片 v24.48/24.49 的文字匯出（粗分隔線、欄位 Emoji、縮排子行）。"
        ]),
        ChangelogEntry(version: "24.49", build: 702, date: "2026/07/22", notes: [
            "【調整】部屬卡片「匯出文字」改為包含已完成事項：承接 v24.48，主動性分頁的文字匯出原本只列待完成報告/會議未完成議程/待完成任務，現改為全部列出——報告與任務章節標題帶完成進度（如「📋 任務（3/5 完成）」），每筆以 ✅/⬜️ 標示完成狀態，已完成者附 🏁 完成日期、未完成者附 ⏰ 截止日期；會議議程項目同樣完整列出（✅/⬜️ 並列，已完成附完成日期）。項目預覽卡（會議/任務/報告等單卡）的文字匯出原本即含已完成項目，行為不變。"
        ]),
        ChangelogEntry(version: "24.48", build: 701, date: "2026/07/22", notes: [
            "【功能】分享功能新增「匯出文字」：部屬卡片與項目預覽卡（會議/任務/報告/請假/紀錄）右上角的分享按鈕改為選單，除既有「匯出圖片」外新增「匯出文字」。文字格式評估後採用 Emoji 排版純文字而非 HTML——LINE／訊息／郵件貼上即完整顯示，HTML 檔案在聊天軟體只會變成需另開的附件。排版規格：標題列（類型 Emoji＋主題）＋粗分隔線（━━━），欄位逐行以對應 Emoji 開頭（🕐 時間／⏱ 長度／🗓 日期／⏰ 截止／✅ 完成）；會議議程項目以 ✅/⬜️ 呈現完成狀態、附負責人（👤）與縮排子行（└ 截止/完成時間）；請假帶假別與時數（🌴/⏱）、Miss Operation 帶嚴重度。部屬卡片文字版包含基本資料（💼 職稱／🏢 部門／🏭 廠區／📅 入職）＋分數列（📊 主動性｜潛力性｜綜合），內容隨目前分頁：主動性＝待完成報告/會議議程/任務/請假記錄；潛力性＝優缺點與成就/進步/缺失/疏失逐條列出；執掌＝設備清單（PM/警報次數、上次 PM）＋PM／警報合併時間軸（🔧/🚨，警報自動標示「PM 後 N 天」）。實作：共用 CardSharePayload（原 CardShareURL 泛化為可裝檔案 URL 或純文字）走既有 ShareSheet 分享。"
        ]),
        ChangelogEntry(version: "24.47", build: 700, date: "2026/07/22", notes: [
            "【功能】部屬卡片（SubordinateDetailView）右上角新增「匯出圖片」按鈕：與既有「編輯」按鈕並列，一鍵把整張部屬卡片渲染成高解析 JPG 並開啟系統分享面板（LINE／訊息／郵件／存到相簿等）。匯出內容為藍色英雄卡（姓名、職等職稱、部門、入職日、主動性/潛力性/綜合分數看板與 KPI 統計）加上「目前所在分頁」的全部章節——主動性分頁：週報＋會議＋任務＋被標註＋請假＋已完成；潛力性分頁：優缺點＋成就／進步／缺失／疏失紀錄；執掌分頁：設備清單＋PM／警報時間軸——切到哪個分頁就匯出哪個分頁，方便分別分享日常表現、考核紀錄或設備保養狀況。實作對齊 TalentMatrixView.exportJPG／SubordinateItemCard.shareJPG 既有規格（ImageRenderer 固定 430pt 寬、3x 縮放、靜態版面不含進場動畫，寫入暫存目錄後以 ShareSheet 分享），檔名帶部屬姓名與時間戳（如「部屬卡片_王小明_20260722_1030.jpg」）。卡片其餘互動行為不變。"
        ]),
        ChangelogEntry(version: "24.46", build: 699, date: "2026/07/22", notes: [
            "【修復編譯錯誤】部屬執掌設備清單（SubordinateEquipmentView.swift:123）：設備列「警報 N」標籤的 .foregroundStyle(eq.alarms.isEmpty ? .secondary : .red) 三元運算式中，Swift 型別推論把 .secondary 推成 HierarchicalShapeStyle，而 .red 在該型別上不存在，兩個分支型別無法統一，Xcode 回報「Member 'red' in 'HierarchicalShapeStyle'」與「Static property 'red' requires the types 'HierarchicalShapeStyle' and 'Color' be equivalent」兩條錯誤。改為兩側都明確標注 Color（Color.secondary : Color.red），顯示效果完全不變（無警報＝灰色、有警報＝紅色）。"
        ]),
        ChangelogEntry(version: "24.45", build: 698, date: "2026/07/22", notes: [
            "【功能】部屬項目預覽卡（SubordinateItemCard）右上角新增「分享」按鈕：點開部屬卡片的會議（以及任務／報告／請假／紀錄等所有同款預覽卡）後，可一鍵把卡片內容（標題、會議時間/長度、議程項目與完成狀態、備註等完整畫面）渲染成高解析 JPG 圖片，透過系統分享面板傳給其他人（LINE／訊息／郵件／存到相簿等）。實作對齊 TalentMatrixView.exportJPG 既有規格：ImageRenderer 以固定 420pt 寬、3x 縮放渲染靜態版面，寫入暫存目錄後以既有 ShareSheet（UIActivityViewController 包裝）開啟分享；檔名帶項目類型與時間戳（如「會議_20260722_1030.jpg」）。分享按鈕與既有「編輯」按鈕並列於導覽列右上角，卡片其餘互動（議程項目勾選、標註人員點擊、編輯）行為不變。"
        ]),
        ChangelogEntry(version: "24.44", build: 697, date: "2026/07/22", notes: [
            "【功能】部屬卡片新增「執掌」分頁（第三個 Tab，與主動性／潛力性並列）：記錄部屬管理的設備與其保養/警報歷史。① 執掌設備清單：可新增多台設備（名稱＋備註），每台設備可登錄多筆預防保養（PM）記錄（日期＋保養內容）與多筆警報記錄（發生時間精確到時分＋警報內容）；設備列即時彙總 PM 次數、警報次數、近 30 天警報次數與上次 PM 日期。② 頁面下方新增「PM／警報時間軸」：把所有設備的 PM（綠色扳手節點）與警報（紅色鈴鐺節點）合併成單一時間軸（新到舊），每筆警報並自動標示「PM 後 N 天」（距同一設備上一次 PM 的天數），一眼看出保養與警報的相關性；附圖例（綠＝PM、紅＝警報）。③ 資料層：Subordinate 新增 equipments（[ManagedEquipment]，含 EquipmentPMRecord／EquipmentAlarm 子模型，逐元素容錯解碼），隨既有部屬資料一併走 iCloud 同步／完整備份／部屬單獨匯出，合併匯入時既有部屬依 id 補進新設備。④ 同步修正 AddSubordinateView（編輯部屬基本資料）重建 Subordinate 時帶回既有 equipments，避免編輯姓名/部門等基本欄位時執掌資料被空陣列覆蓋。新增檔案 SubordinateEquipmentView.swift（清單章節／時間軸章節／設備編輯 Sheet）。"
        ]),
        ChangelogEntry(version: "24.43", build: 696, date: "2026/07/21", notes: [
            "【修復】合併匯入時，既有家庭成員的疫苗接種紀錄（及其他子項目）整筆被丟棄：匯出端本身沒有問題（FamilyMember.encode 已含 vaccinations，JSON 備份檔內確實帶有疫苗資料），問題出在 UnifiedImporter 的「合併」模式——familyMembers 過去用 mergeItems 以整筆成員為單位去重，只要匯入檔裡的成員 id 在本機已存在（例如兩台裝置都有同一位兒子），整筆傳入資料連同疫苗接種、兒女記錄、日常記錄、家庭活動、相簿等所有子項目一起被靜默捨棄，於是「匯出有帶、合併匯入後卻看不到」。比照部屬（subordinates）既有的深度合併寫法改寫：既有成員（同 id）改為逐類子項目補進本機缺少的資料（childRecords／dailyRecords／familyEvents／familyPhotos 依 id 去重新增；疫苗接種依劑次 scheduleId 對應——本機已有該劑紀錄則保留本機、僅在本機缺施打日期或備註時補上，本機沒有的劑次整筆帶入），基本欄位（生日／出生年）僅在本機空缺時補上、不覆蓋本機既有資料；不存在的成員維持整筆新增。完整備份（FullBackup.restore）重用同一套 UnifiedImporter，一併修復。另將部屬合併區塊內的局部 appendNewByID 提升為 UnifiedImporter 私有共用 helper，供家庭成員與部屬兩處深度合併共用。「取代」模式行為不變。"
        ]),
        ChangelogEntry(version: "24.42", build: 695, date: "2026/07/20", notes: [
            "【功能】兒女履歷「疫苗」章節升級為「疫苗接種時程規劃」：過去疫苗章節只能一筆一筆自由手動新增，現在改為依台灣兒童常規疫苗時程自動列出所有應接種的疫苗劑次（B 型肝炎、五合一、13 價肺炎鏈球菌、卡介苗、水痘、MMR、A 型肝炎、日本腦炎、四合一、流感，及輪狀病毒等常見自費項目），並以孩子的出生日期自動推算每一劑的「建議接種日」。① 使用方式簡化為「只需填施打日期」：點開任一劑次，開啟「已完成施打」並選日期即視為完成、不填即為尚未施打，另可加註備註（接種院所、反應、提醒等）。② 逾期自動標示：尚未施打且已過建議接種日者，該列自動顯示紅色「需盡快施打」，卡片標頭並彙總「N 劑逾期，需盡快施打」；建議接種日在 30 天內者顯示橘色「即將接種」，直接對應使用者「需快點規劃施打」的提醒需求。③ 卡片標頭顯示完成進度（已完成 X／全部 Y），依月齡分期（出生、1／2／4／5／6／12／15／18／27 個月、滿 5 歲–入學前）分組排列。④ 未設生日時仍可標記施打、並提示「設定生日後可自動推算建議接種日」。⑤ 資料層：FamilyMember 新增 vaccinations（[VaccineDose]）欄位，各劑次狀態獨立儲存並隨 iCloud 同步／完整備份（向下相容既有資料）；新增 VaccineSchedule.taiwan 靜態時程表與 VaccineScheduleItem／VaccineDose 模型。⑥ 相容保留：先前以自由文字手動新增的疫苗紀錄（ChildRecord）仍完整顯示於卡片下方「其他疫苗紀錄」區，點擊可續行編輯或刪除，資料不遺失。"
        ]),
        ChangelogEntry(version: "24.41", build: 694, date: "2026/07/19", notes: [
            "【修復】財富卡片銀行帳戶：固定薪水設了「收入結束日」後，銀行存款仍持續入帳、餘額未同步。承接 v24.40，Income 已支援 endDate（換工作/離職/產假），且收入頁的每月收入計算已排除已結束薪水，但財富卡片（LifeFinanceView）另有一條獨立的虛擬入帳展開邏輯：expandedIncomeDeposits 把連結到銀行 milestone 的週期性收入（月薪/年薪）從建立日一路展開成每期一筆虛擬 BankDeposit，用於銀行帳戶餘額計算（bankBalances → 總資產）與存款明細/走勢圖顯示，但這條 while 迴圈當初只用 `current <= now`（展開到今天）作為停止條件，完全沒有看 endDate，導致離職後每個月仍持續灌入一筆薪資入帳、銀行餘額與總資產持續虛增。已在迴圈內加上 `if !inc.isActive(in: current) { break }` 守衛（current 逐月單調遞增，跨過結束月即跳出），與 Income.isActive(in:)／收入頁計算採同一套「結束月含、之後停止」規則，讓銀行帳戶餘額、存款明細、走勢圖三處一致在結束月後停止入帳。純計算修正，未變動既有存款展開、信用卡彙總、固定支出扣款等其他虛擬條目邏輯。"
        ]),
        ChangelogEntry(version: "24.40", build: 693, date: "2026/07/19", notes: [
            "【功能】固定薪水可設定「收入結束日」與結束原因（換工作/離職/產假等）：收入頁面點開編輯（AddIncomeView）某筆「固定薪水」時，週期設定區塊新增「設定收入結束日」開關，開啟後可選結束日期與結束原因（離職／換工作／產假／育嬰留停／退休／資遣／其他），適用於中途換工作、留職停薪等情境。① 資料模型 Income 新增 endDate／endReason 兩個欄位（皆為選填，向下相容既有資料；透過 Codable 一併納入雲端同步與完整備份）。② 新增 Income.isActive(in:) 判斷：結束日所在月份（含）之前仍計入、之後不再計入（考量多數情況離職當月仍領到最後一份薪水，結束月採「含」）。③ 本月收入合計（ExpenseStore.currentMonthIncomeTotal）與過去月份收入估算（incomeTotal(for:)、供無當月收入時取中位數預估）兩處週期收入加總都改為排除已結束的固定薪水，換工作後上一份薪水不再灌水到本月收入。④ 收入頁英雄卡「固定月收」KPI、累計收入（totalIncomeAll，固定薪水改為僅展開至結束月為止而非一路累計到今天）同步排除／截斷已結束薪水。⑤ 收入清單列新增結束標示膠囊：已過結束月顯示灰色「原因＋年月」（例如「離職 2025/3」）、尚未到結束月顯示橘色（將結束），一眼可辨哪些固定薪水已停發。純新增欄位與條件化計算，未變動既有單次／獎金／投資等其他收入類型的計算邏輯。"
        ]),
        ChangelogEntry(version: "24.39", build: 692, date: "2026/07/19", notes: [
            "【靜態除錯 v24.39：修復 2 處真實 Bug】延續 v24.26 覆查時列為候選、評估後留待後續版本處理的兩個問題：① MainTabView 語音記帳麥克風按鈕：DragGesture.onChanged 觸發 aiStartRecording()（requestAccess 詢問權限 + startRecording()）是非同步流程，若使用者在權限詢問對話框跳出、尚未回覆的期間就快速放開手指，onEnded 讀到的 speechRecognizer.isRecording 仍是 false，guard 直接返回、不會呼叫 stopRecording()；等使用者稍後才回覆權限、startRecording() 真正把錄音狀態設成 true 時，已經沒有任何手勢會觸發停止，麥克風在使用者以為已放開的情況下仍悄悄持續錄音（且旗標卡住，下次按住會被 onChanged 既有的 !isRecording 守衛擋掉，只能靠 App 背景/前景切換的既有 stopRecording 才會解除）。新增 aiStopRequestedBeforeStart 旗標：onEnded 在偵測到「仍在啟動中就放開手指」時記下，aiStartRecording() 的 startRecording() 成功後立刻檢查該旗標並補呼叫 aiFinishRecording() 收尾，不必等下一次手勢。② ResumeView.AddMilestoneView（新增/編輯里程碑）的職涯／理財子分類：careerFields／financeDetailSection 表單只依目前 careerSub／financeSub 顯示對應欄位（例如「升遷」才顯示職稱/職等、「信用卡」才顯示卡號末四碼/年費/帳單日/繳款日、「保險」才顯示保險公司/保單號碼/受益人），但 save() 組出 LifeMilestone 時，除了 isManagerial／salary／bankAccountType 等少數欄位外，其餘欄位（companyName／department／jobTitle／jobGrade／mood／futurePlan；bankName／branchName／accountNumber／cardName／cardLastFour／creditLimit／annualFee／billingDay／paymentDay／expiryDate／insuranceCompany／policyNumber／premiumAmount／beneficiary）過去一律無條件存入，不受目前子分類限制；同一次新增/編輯過程中若使用者先切到某個子分類填了欄位、再切到另一個子分類送出（子分類 Picker 在新增與編輯既有紀錄時都可自由切換，只有最上層「分類」在編輯時才鎖定），前一個子分類殘留在 @State 的文字會被原封不動存進新子分類的紀錄裡（例如先在「升遷」填了職稱再切到「調薪」送出，調薪紀錄會被存進不相關的舊職稱；先在「信用卡」填了卡號末四碼再切到「保險」送出，保單紀錄會夾帶不相關的舊卡號）。新增 trimmedOrNil(_:when:) helper，比照 careerFields／financeDetailSection 實際顯示邏輯，把上述所有欄位依對應子分類條件化，不符合目前子分類就一律存 nil。其餘複查範圍（CloudSyncManager 30 秒節流／2 秒防抖／isSyncing 並行守衛、EInvoiceSyncManager 同步間隔判斷、CloudKitManager 自我回音比對）均確認未被繞過，未發現新的畫面閃爍或效能問題。"
        ]),
        ChangelogEntry(version: "24.38", build: 691, date: "2026/07/19", notes: [
            "【修復編譯錯誤】記帳新增/編輯畫面（AddExpenseView）Archive 打包時回報「The compiler is unable to type-check this expression in reasonable time」（AddExpenseView.swift:393）：主畫面 body 的 Form 後方原本串接了十多條各自獨立的 .onChange（selectedVehicleId／selectedVehicleExpenseCategory／selectedRealEstateLinkId／realEstateLinkExisting／selectedRealEstateExpenseCategory／selectedMortgageRealEstateId／mortgageLinkExisting／note／selectedFixedAssetLink／fixedLinkVehicleId／selectedFixedCategory／selectedLoanSubCategory），且每條都帶尾隨閉包呼叫 applyAutoTitleIfLinked()，讓 Swift 型別檢查器在 Release 最佳化下逾時而無法完成推論。改為新增一個 autoTitleSignature 計算屬性，把所有會影響「連結資產自動命名」的欄位濃縮成單一字串（備註 note 僅在房貸情境納入，維持原本行為），再以單一 .onChange(of: autoTitleSignature) 觀測，任一欄位變動即觸發自動命名。純結構重構，觀測欄位集合與觸發時機與原本完全一致，僅將十多條 .onChange 合併為一條以解除型別檢查逾時。"
        ]),
        ChangelogEntry(version: "24.37", build: 690, date: "2026/07/19", notes: [
            "【美化部屬新增流程「選擇部屬」清單列（SubordinateDetailView.AddSubItemSheet）+ 同步版本號 v24.37】從行事曆／部屬總覽按「＋」新增部屬任務／會議／報告時，第一步「選擇部屬」清單列先前是裸 26pt 單色圖示（固定寫死 .green，與新增項目種類無關），是本檔案唯一沒有套用 36pt LinearGradient 漸層圖示圓（fill 0.22→0.09 + shadow + stroke 0.22pt）規格的清單列，與同檔案 recordRow／meetingSection 等既有列不一致，選錯部屬時也缺乏顏色提示自己正在新增哪一種項目。SubAddKind 新增 color 計算屬性（任務＝cyan／會議＝indigo／報告＝purple，沿用本檔案 CompletedEntry.Kind.color 已建立的識別色慣例），清單列圖示改套用該色的標準漸層圓，與選完後開啟的對應編輯器 Section 識別色一致。純視覺層調整，未變動 pickedSubId 選取、切換至 TaskEditorSheet／MeetingEditorSheet／WeeklyReportEditorSheet 等既有商業邏輯。"
        ]),
        ChangelogEntry(version: "24.36", build: 689, date: "2026/07/19", notes: [
            "【美化個人行事曆主畫面（MyCalendarView.eventRow）重複／提醒徽章 + 同步版本號 v24.36】主畫面每日事項列表（eventRow）先前把「這是重複事件」塞進 detail 字串裡，用純文字表情符號「🔁」當前綴，是全檔案唯一用 emoji 而非 SF Symbol 表達狀態的地方，與同一排時間欄位（clock／sun.max，皆為 9pt SF Symbol + tertiary 灰階）的既有視覺節奏不一致；且個人事件即使設了提醒也完全不會顯示，需要點進詳情頁才看得到。CalendarEvent（僅供本畫面顯示用的私有結構）新增 isRecurring／hasReminder 兩個布林欄位（預設 false，不影響其餘四處既有建構呼叫），eventRow 改用 \"repeat\" 與 \"bell.fill\" 兩枚與 clock／sun.max 完全同規格的 9pt SF Symbol 徽章呈現；hasReminder 依既有 pe.reminderMinutes >= 0 語意判斷（-1 = 不提醒），純粹補齊主畫面可視性。純視覺層調整，未變動 eventsOn()／occurs()／reminderMinutes 讀寫、NotificationManager 通知排程、Apple 行事曆同步等既有商業邏輯。"
        ]),
        ChangelogEntry(version: "24.35", build: 688, date: "2026/07/18", notes: [
            "【靜態除錯 v24.35：EInvoiceHistoryView 空狀態脈衝動畫卡死】匯入歷史頁（EInvoiceSetupView.EInvoiceHistoryView）在同一個 sheet 內以 if/else 於清單／空狀態間切換：使用者對單筆紀錄「撤銷」（swipe action）或按右上角「清除全部歷史」把 sync.importHistory 清空後，畫面從清單切回空狀態，但 emptyPulse 這個雙層脈衝光環旗標是宣告在 EInvoiceHistoryView 本身（sheet 頂層、跨越 if/else 兩個分支持續存在），並非空狀態子視圖獨有；只要這個 sheet 在清單／空狀態之間切換過一次以上，第二次進入空狀態時 emptyPulse 已停留在 true，.onAppear 重新指派 true→true 不構成 SwiftUI 判定的變化，脈衝動畫不會重播，兩層光環直接卡在放大後的固定尺寸——與 v24.33 TalentMatrixView 空狀態脈衝卡死屬同一種 bug（@State 宣告在持續存在的父層、conditional 子視圖各自 onAppear 卻沒有對應 onDisappear 重置）。比照該次修法補上 .onDisappear { emptyPulse = false }。本輪同時針對尚未被 v24.20～v24.34 逐檔覆蓋、較少提及的 AdminConsoleView／MultiPhotoGallery／VehicleDetailView／HolographicBuildingView（目前無任何呼叫端引用，屬未串接的閒置元件，故所有潛在問題影響範圍為零，本輪不列入修復）四個檔案做重點複查：強制解包／as!／try!／索引越界／retain cycle（Timer／SCNAction 閉包皆已用 [weak self]／[weak root]）／CloudKit 節流／isBusy 並行守衛均確認已妥善保護，未發現其餘新問題。"
        ]),
        ChangelogEntry(version: "24.34", build: 687, date: "2026/07/18", notes: [
            "【靜態除錯 v24.34：多處儲存按鈕補上連點守衛，避免重複紀錄/資料錯亂】① RealEstateDetailView.ElevatorMaintenanceEditor（電梯保養記錄）的儲存與刪除，比照同檔案 UtilityPaymentEditor／RenovationPhotoEditor 已修過的同型 bug——save()／deleteRecord() 都是先 dismiss() 關閉 sheet，下一個 runloop 才非同步寫回 financeStore，快速連點兩下會讓兩次呼叫各自讀到同一份舊 estate 快照、各自 append／刪除，較晚寫回者蓋掉較早者，可能造成重複的保養記錄或遺失剛存的保養照片（孤兒檔案），卻唯獨這個編輯器沒有 isSaving 守衛；補上比照既有規格。② AddIncomeView／AddVehicleView.VehicleEditor／AddSavingsInsuranceView／AddStockView 四個新增/編輯表單的儲存皆是同步寫回 store 後立即 dismiss()，sheet 收合動畫尚未播完前按鈕仍可被觸發，快速連點會建立兩筆重複紀錄（AddStockView 又牽涉股票已實現損益連動的支出/收入建立與刪除，重複觸發風險更高）；四處統一補上 isSaving 忙碌旗標 + 按鈕 disabled 守衛，比照本檔案系列先前已為 AddRealEstateView／AddExpenseView 等畫面建立的規格。純新增守衛邏輯，不影響任何既有儲存資料欄位或商業邏輯。"
        ]),
        ChangelogEntry(version: "24.33", build: 686, date: "2026/07/18", notes: [
            "【靜態除錯 v24.33：TalentMatrixView 空狀態脈衝動畫卡死】emptyHint（人才矩陣依部門篩選後無符合部屬時的空狀態）只在 .onAppear 把 emptyPulse 設成 true，沒有比照全 App 其餘空狀態（FamilyView／ResumeView／LifeOverviewView／SubordinateView／ChildrenResumeView／FoodMapView／CareerView 等）在 .onDisappear 一併重置為 false。透過畫面上方的部門篩選 Menu 先切到有部屬的部門（空狀態從畫面上移除但 emptyPulse 仍停留在 true）、再切回沒有部屬的部門，.onAppear 重新掛載時 emptyPulse 已是 true，指派 true→true 不構成 SwiftUI 判定的變化，.animation(value:) 不會重新觸發，兩層脈衝光環會直接卡在放大後的固定尺寸、不再播放脈動效果。補上 .onDisappear { emptyPulse = false }，強制下次掛載時觸發 false→true 的轉場以重播動畫。本輪複查 Views/Life 目錄全部 27 個檔案，其餘強制解包／as!／索引越界／retain cycle／防抖動畫／忙碌守衛均確認已妥善保護，未發現新問題。Views 根層與 Finance 目錄的複查仍在進行中。"
        ]),
        ChangelogEntry(version: "24.32", build: 685, date: "2026/07/18", notes: [
            "【靜態除錯 v24.32：RemoteAdminManager.refresh() 補上節流，避免重複打公用 CloudKit DB】App 內所有其他 CloudKit 同步路徑（CloudSyncManager 30 秒節流、2 秒防抖；EInvoiceSyncManager 依設定間隔判斷）都有節流保護，唯獨 RemoteAdminManager.refresh()（由 LifeGoodApp 根視圖 .onAppear 呼叫的 bootstrap() 觸發，拉取 Public DB 的 AppConfig／GlobalStats）完全沒有節流；根視圖 .onAppear 在 scene 重建等情境下可能不只觸發一次，每次都會無節制送出 CKFetchRecordsOperation。新增 lastAutoRefresh 節流旗標，比照既有 30 秒節流慣例：bootstrap() 走的自動路徑 30 秒內跳過重複拉取，AdminConsoleView「重新整理人數／設定」按鈕的手動路徑則維持原樣立即生效（refresh(force:) 預設 true）。本輪同時複查 Models 目錄全部 27 個檔案，其餘強制解包／as!／try!／retain cycle／CloudKit 節流與防抖／isSyncing 並行守衛均確認已妥善保護，未發現新問題。"
        ]),
        ChangelogEntry(version: "24.31", build: 684, date: "2026/07/18", notes: [
            "【靜態除錯 v24.31：多路並行複查全部 83 個 Swift 檔，修復 12 處真實 Bug】資料遺失/損毀：① AddStockView.save() 編輯既有股票時重建全新 Stock 卻未帶入 transactions／dividends（皆預設空陣列），financeStore.update() 又是整筆覆蓋，使用者只是想改個股票名稱/備註就會把該股票所有交易紀錄與股利記錄全部靜默清空，且連帶讓 syncAccountTransactions 誤判為「無交易紀錄」而用錯分支重建銀行帳戶扣款；save() 補上 transactions/dividends 沿用 editing 既有值。② LifeStore.deleteMilestone 只移除該筆里程碑本身，未比照 deleteFamilyMember／deleteSubordinate 清除交叉引用，刪除銀行/信用卡/證券帳戶後 Stock.linkedBankMilestoneId／linkedSecuritiesMilestoneId、Expense.linkedBankMilestoneId／linkedCreditCardMilestoneId、Income.linkedBankMilestoneId 全部留下永久指向不存在帳戶的懸空 id，「連結帳戶」功能悄悄失效；在同時持有三個 store 的 ResumeView／LifeFinanceView 呼叫端補上清除邏輯（LifeStore 本身無法觸及 FinanceStore／ExpenseStore）。競態／連點：③ CloudKitManager.fetchChanges 過去只用序列佇列保護「送出操作」那一刻，ensureZoneExists／CKFetchRecordZoneChangesOperation 的完成回呼實際落在 CloudKit 自己的佇列，並未被序列化；CloudSyncManager.performSync（30 秒節流）與 handleRemoteNotification（silent push，未經過 isSyncing 守衛）前後腳呼叫時，兩個 CKFetchRecordZoneChangesOperation 會針對同一個 zone 並行拉取、各自獨立存 change token 並各自觸發 Store reload；補上 isFetching 旗標，讓後到的呼叫直接跳過。④⑤⑥ AddRealEstateView 儲存鍵、RealEstateDetailView.UtilityPaymentEditor.save()、RenovationPhotoEditor.save() 三處皆無連點守衛，其中後兩者又把實際寫回 store 的動作延後到下個 runloop（避免 present/dismiss 交易期間改 observed state 真機閃退），快速連點兩下會讓兩次呼叫各自讀到同一份舊 estate 快照、各自建立新 Expense／新記錄，較晚寫回者會蓋掉較早者剛 append 的內容，留下孤兒 Expense 或孤兒照片；三處都補上 isSaving 旗標並停用按鈕。⑦ SettingsView 匯出 JSON／CSV／部屬資料三顆按鈕沒有比照旁邊「完整備份」backupBusy 補忙碌守衛，連點會並發跑兩個 Task.detached 各自寫同一個檔名、各自把 activeShareItem 蓋過去，分享面板閃爍/重開；補上共用 exportBusy 旗標。⑧ AddExpenseView 進階模式下用相機/相簿新增照片會立即寫檔並存進 photoFileNames，但只有 saveExpense() 才會把陣列寫回 Expense 紀錄，按「取消」過去直接 dismiss() 完全不清理，這些照片永久留在磁碟且被 CloudKit 備份同步上去；比照 RenovationPhotoEditor.cancel() 同型寫法，取消時清除本次 session 新增、尚未存檔的檔案。畫面閃爍：⑨ SpouseResumeView 的「相關里程碑」與「共同消費」兩個空狀態共用同一個 emptyIconPulse 旗標，其中一個先掛載把旗標設成 true 後，另一個掛載時偵測不到「從 false 變 true」的變化，脈衝光環動畫不會播放；拆成 milestoneEmptyPulse／expenseEmptyPulse 兩個獨立旗標（emptyPlaceholder 改吃 Binding<Bool> 參數）。⑩ ChartView 四個圖表空狀態脈衝計時器（trendEmptyPulse／variablePieEmptyPulse／fixedPieEmptyPulse／typeBreakdownEmptyPulse）仍用未取消的 DispatchQueue.main.asyncAfter，loadChartData() 重載資料只會把旗標歸零、不會取消已排程的 closure，快速切換週期分頁時舊的 closure 會在稍後補一次遲到觸發，讓脈衝動畫從中途突然開始；改用可取消的 Task（比照 FinanceChartView 既有寫法），並在 loadChartData() 與 onDisappear 一併取消。正確性：⑪ FinanceChartView（僅注入 FinanceStore，未注入 ExpenseStore）的英雄卡總資產、資產配置圓餅圖直接用 FinanceStore.totalAssets／assetAllocations，對儲蓄險 currentValue／totalPaid 未做匯率換算（可在 AddSavingsInsuranceView 選 USD/JPY 等幣別），外幣保單原始數字被當成 NT$ 計入總資產，與 FinanceOverviewView（已比照 insuranceSummaryNTD 換算）同一份資料顯示互相矛盾；補上同型換算，並在「儲蓄險摘要」逐筆列補上非 NT$ 幣別的標示文字，避免誤讀成台幣金額。其餘複查範圍（Models 27 檔、Finance／根層 Views 28 檔、Life Views 27 檔全數逐檔覆蓋，並與 v23.x～v24.30 既有修復比對避免重複回報）均確認強制解包／as!／try! 已妥善守衛、CloudKit 30 秒節流／2 秒防抖／isSyncing 並行守衛未被繞過（本輪新增的 CloudKitManager.isFetching 為既有守衛的補強，非取代）。"
        ]),
        ChangelogEntry(version: "24.30", build: 683, date: "2026/07/18", notes: [
            "【美化】健康檔案編輯頁（HealthProfileEditView.AllergyEditor）過敏嚴重度選擇器：承接上一版（v24.x）留下的待辦事項，「嚴重度」原本是系統預設 Picker（純文字下拉選單，輕/中/重三個等級視覺完全相同，需點開才看得出目前選了哪一級），與同頁其餘已美化的漸層圖示圓、色塊化 metric chip 等視覺落差明顯。新增共用 severityColor(_:)（輕度＝綠／中度＝橘／重度＝紅，交通號誌語意），把 Picker 改為三段色塊按鈕列：選中的色塊填滿主題色 + 白字 + 陰影，未選中的色塊淡底 + 主題色文字 + 細邊框，並補上輕量彈簧動畫，不必進下拉選單就能一眼比較嚴重度。外層過敏清單的嚴重度徽章原本無論輕/中/重度一律固定橘色，一併改用同一份 severityColor(_:)，兩處色彩語意統一。純視覺層調整，draft.severity 讀寫、onAppear 預設值回填與儲存等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.29", build: 682, date: "2026/07/18", notes: [
            "【美化】部屬任務／週報編輯頁（SubordinateDetailView.TaskEditorSheet／WeeklyReportEditorSheet）補齊「完成狀態」Section 標頭：上一版（v24.x）美化會議/任務/週報三個編輯 Sheet 時已補齊大部分 Section 統一標頭規格，但唯獨「標記為已完成」Toggle 所在的 Section 是全檔案僅剩沒有 header 的例外，與同畫面其他 Section（會議資訊／任務資訊／指派人員／備註）視覺落差明顯。新增 editorSectionHeader(\"完成狀態\", icon: \"checkmark.seal.fill\", tint: .green) 補齊兩處，綠色呼應 Toggle 開啟時的勾選綠，與 isCompleted 狀態語意一致。純視覺層調整，$isCompleted binding 與 save() 寫回 completedAt 等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.28", build: 681, date: "2026/07/18", notes: [
            "【美化】個人檔案編輯頁（ResumeView.EditProfileView）補齊 Section 標頭：這是全 App 掃過一輪最後一個完全沒有任何美化紀錄的畫面（同檔案 ProfileFlashCard 英雄卡、母頁 LifeOverviewView 皆已完成規格對齊，唯獨這個從英雄卡鉛筆圖示點入的編輯 sheet 仍是最原始的裸 Form，三個 Section 只有系統預設純文字標題）。新增共用 profileEditorSectionHeader(_:icon:color:)（4pt 漸層色條 + 圖示 + 粗體文字，比照 HealthProfileEditView.healthEditorSectionHeader／MyCalendarView.editorSectionHeader 既有規格），補上「姓名」（indigo，person.text.rectangle.fill）／「工作」（orange，briefcase.fill）／「家庭」（pink，heart.fill）三個標頭，各自獨立主題色提升可掃視性。關閉按鈕維持原本固定左側「取消」、儲存固定右側「儲存」，本就符合全 App 一致慣例。純視覺層調整，chineseName／englishName／company／jobTitle／spouse 欄位資料來源與 loadProfile()／save() 寫回 store 等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.27", build: 680, date: "2026/07/18", notes: [
            "【美化】個人行事曆事件預覽卡（MyCalendarView.CalendarEventCard）補齊「詳細資訊」／「備註」卡片標頭：v24.x 先前已把新增/編輯表單（PersonalEventEditor）與預覽卡標頭（titleBlock 英雄卡）都升級成統一規格，但預覽卡下方 infoCard（類型/時間/長度/重複/地點等欄位列）一直是完全無標頭的裸內容區塊，noteBlock 也只有純 caption 字級的「備註」二字標籤，與同檔案編輯表單的 editorSectionHeader（4pt 漸層色條 + 圖示 + 粗體文字）視覺落差明顯。新增共用 cardSectionHeader(_:icon:tint:) 補上「詳細資訊」（info.circle，沿用卡片依事件類型變色的 accent）與「備註」（note.text，中性灰，對齊 editorSectionHeader 備註區配色）兩個標頭。純視覺層調整，fields／noteText 欄位資料來源與新增/編輯/刪除/Apple 行事曆同步等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.26", build: 679, date: "2026/07/17", notes: [
            "【靜態除錯 v24.26：多路並行複查全部 83 個 Swift 檔，修復 16 處真實 Bug】資料遺失／孤兒紀錄：① FinanceModels.RealEstate 的舊版單筆土地權狀欄位（landSituation/landNumber/landArea）過去 encode 時直接存 stored 值，AddRealEstateView 載入舊資料後即使使用者把 landDeeds 陣列裡唯一一筆權狀刪光存檔，這三個純量欄位仍保留舊值，下次 decode 的向下相容遷移邏輯會把剛刪除的權狀「復活」；改為 encode 時一律從 landDeeds.first 推導寫回。② RenovationPhotoEditor 編輯既有裝潢照片紀錄時，在畫面上刪除「原本已存在」的照片會立即刪檔並同步 CloudKit，但按「取消」只清理新增未存檔的照片，不會把 store 裡的 photoFileNames 收斂，紀錄永久留著指向已刪除檔案的孤兒引用；取消時偵測到既有照片被移除就一併回寫 store。③④ StockDetailView／StockView 刪除股票時只清 stock.linkedIncomeId 這單一欄位，未逐筆清理 StockDividend.linkedIncomeId 連結的現金股利 Income，刪股票後仍留下永久孤兒「XX 配息」收入紀錄、持續灌水收入總額；兩處都補上逐筆股利清理。正確性：⑤ LifeFinanceView.isVirtualCreditCardEntry 只判斷「id 不在 item.bankDeposits 裡」，但週期性固定支出／收入展開的虛擬條目同樣符合此條件，導致所有連結銀行的固定支出／收入扣款列被誤標成「信用卡」徽章與圖示，點擊還會開錯編輯頁（誤開無關信用卡或無反應）；改為額外要求 linkedExpenseId == nil 才視為信用卡彙總。⑥ AdminConsoleView 的「全功能免費」「對外顯示人數」開關過去 onChange 直接送出遠端寫入，不管 CloudKit 寫入是否失敗，本地鏡像 @State 永遠停在使用者撥動後的樂觀值，寫入失敗時控制台會永久顯示與實際生效狀態不符的假象；改為呼叫時帶入 completion，失敗才把鏡像撥回真實狀態。⑦⑧ FinanceChartView／FinanceOverviewView 資產總覽卡片與「股票」資產卡的計數徽章過去用未過濾的 store.stocks.count，金額卻用排除已出售的 store.totalStockValue，賣光一檔股票後計數與金額互相矛盾（與同卡片已修過的房地產口徑不一致）；統一改用排除已出售的計數。⑨ AddExpenseView 的儲蓄險已繳期數（insElapsedPeriods）漏了與正版 SavingsInsurance.elapsedPeriods 相同的 max(0, …) 下限保護，且到期日 DatePicker 沒有下限限制，使用者選到早於起始日的到期日會讓「已繳期數」「已繳總額」變成負值並存檔；補上下限保護與 DatePicker 下限。⑩ TaxOverviewView.estimatedAnnualIncome 只有一次性收入依 selectedYear 過濾，月薪／年薪這種週期性收入不論年份一律整年計入，瀏覽過去年度時今天才新增的月薪仍會被算進該年度預估年收入，連帶稅務占比／二代健保補充保費等 KPI 失真；比照本檔案既有 yearEquivalentAmount 口徑，補上起始年 <= selectedYear 的判斷。⑪ SubordinateDetailView.restDeductionHours 遇到跨午夜的班別休息時段（如晚班 23:00–00:30）時，把 endMinutes 換算成同一天的 Date 會比 rStart 還早，導致當天整段休息扣除被直接跳過（而非部分扣除），造成部屬請假時數被高估；跨日時把 endMinutes 多加 1440 分鐘換算。畫面閃爍：⑫ SettingsView「使用中的 AI 服務」各供應商 API Key 欄位過去直接綁在 aiSettings.setKey(for:) 上，每敲一個字元就同步寫入 Keychain 並讓整個 SettingsView 重繪，比照既有 CurrencyRateRow 修法抽成獨立子視圖，本地暫存＋停止輸入 400ms 才提交。⑬ CloudKitManager.runFetch 的 recordWasChangedBlock 只有 KVBlob 分支在 v24.25 補了自我回音內容比對，Photo 分支仍未擋，使用者新增/編輯任何照片後下一次節流拉取幾乎必然把自己剛推上去的同一張照片也當成「已變更」重新下載覆寫，SettingsView「從 iCloud 收到更新」提示連帶無故閃爍；比照 KV 分支補上內容比對後才寫入。⑭ IncomeView 摘要卡（headerAppeared）的進場動畫掛在 Section 內容（List 第一列）本身而非 List，捲動使卡片進出可視範圍會反覆重播淡入動畫，改掛到 List 本身對齊同檔案 listRowsAppeared 既有寫法。⑮ OrganizationView 分享 PDF 用的 pdfURL 過去存 URL? 再用 Binding(get:set:) 現包一次 IdentifiableURL，id 每次 body 重繪都重新產生，分享面板開啟中若父層任何無關 @Published 變動都可能被 SwiftUI 誤判成新項目而中途關閉/重開；改為直接把 IdentifiableURL 存進 @State（比照全庫其餘用法）。⑯ MainTabView 的 bottomTabBar 被實例化兩次（一份 .hidden() 佔位、一份真正顯示），過去共用同一個 tabBarNamespace，導致同一個 matchedGeometryEffect(id:) 在同個 namespace 裡同時有兩個 source view（Apple 文件：結果為 undefined），可能造成分頁切換時膠囊指示器位置偶發跳動；佔位副本改用獨立 namespace。效能：MyCalendarView 搜尋模式下每次打字仍會白白重算行事曆本體的非輕量預算（eventsOn 掃描家人+里程碑+行事曆全量），改為搜尋時跳過；MultiPhotoGallery 橫向縮圖列由 HStack 改 LazyHStack，避免相片數量多時一次把所有縮圖都解碼進記憶體；SettingsView 的 exportJSON／exportCSV／exportSubordinates 過去在主執行緒同步做 JSON 編碼／CSV 組字串，資料量大時會卡住 UI，比照既有 exportFullBackup／BackupManager.createSnapshot 模式，改為只在主執行緒組 struct 快照，實際編碼搬到背景執行緒；FinanceChartView／FinanceOverviewView 的進場動畫延遲呼叫改用可取消的 Task 取代 DispatchQueue.main.asyncAfter，避免快速切換頁面時孤兒更新造成動畫略過。另修正 FamilyMembersResumeView 空清單脈衝動畫離開畫面未重置旗標，導致再次進入空狀態時動畫不會重播的問題。本輪複查中發現但評估影響有限或牽涉較廣、本輪未動的候選問題：ResumeView 新增里程碑時切換職涯/理財子分類未清除依附欄位、MainTabView 語音記帳麥克風快速點放可能讓錄音在使用者放開手指後仍悄悄持續，留待後續版本評估。其餘複查範圍（Models 27 檔、Finance／根層 Views 28 檔、Life Views 27 檔全數逐檔覆蓋，並與 v22.x～v24.25 既有修復比對避免重複回報）均確認強制解包／as!／try! 已妥善守衛、CloudKit 30 秒節流／2 秒防抖／isSyncing 並行守衛未被繞過。"
        ]),
        ChangelogEntry(version: "24.25", build: 678, date: "2026/07/16", notes: [
            "【靜態除錯 v24.25：修復 1 處真實 Bug（CloudKit 同步自我回音造成畫面無謂閃爍）】CloudKitManager.runFetch 的 recordWasChangedBlock 過去只要 CloudKit 回報某筆 KVBlob record「有變更」，就無條件把內容寫回 UserDefaults 並記進 pulledKVKeys，再透過 CloudSyncManager.handleKVChanges 通知各 Store。但 CloudKit 的 server change token 只在「拉取」時前進、推送不會提前，代表本裝置每次推送完自己的異動後，下一次例行拉取（30 秒節流）幾乎必然會把「自己剛推上去、內容其實沒變」的同一筆 record 也算成「已變更」而原樣回彈；v24.19 補過的 keyed reload 只擋住了「不相關 Store 被連帶重載」，沒有擋住「同一個 Store 收到自己剛寫入內容的回音」，導致使用者每新增/編輯/刪除一筆資料，約 30 秒後 ChartView（依 ExpenseStore.modifyID 觸發 loadChartData）等畫面會無故重播 isLoading 動畫與進場動畫，LifeStore 更會因 13 個集合共用同一把 reload 而讓多個頁面同時無謂重繪，但雲端其實沒有任何新資料。修法：在 recordWasChangedBlock 寫回前，先比對新拉回的內容是否與本地既有內容完全相同，相同則視為回音，跳過寫入與加入 pulledKVKeys，只有內容真的不同才觸發後續通知與 Store 重載。本輪同時複查全部 83 個 Swift 檔，強制解包／as!／try!／索引越界／retain cycle／競態條件方面未發現新的可回歸案例（closure 皆正確使用 [weak self] 或值型捕捉，跨執行緒寫入 @Published 前均已轉回主執行緒），CloudKit 30 秒節流／2 秒防抖／isSyncing 並行守衛亦未被繞過。"
        ]),
        ChangelogEntry(version: "24.24", build: 677, date: "2026/07/16", notes: [
            "【靜態除錯 v24.24：多路並行複查全部 83 個 Swift 檔，修復 10 處真實 Bug】資料遺失／孤兒檔案：① RealEstateView.deleteEstate／RealEstateDetailView.deleteEstate／AddRealEstateView.cancelAndRollback（取消回滾）與 UnifiedImporter.applyUnified（.replace 匯入）四處刪除整筆房地產時都只清理水電繳費照片與裝潢照片，漏了電梯保養照片（ElevatorMaintenance.photoFileName）與附件文件（RealEstateDocument），四處統一補齊清理。② AddRealEstateView 電梯保養照片選擇器換照片時，先無條件刪除舊照片檔案、才嘗試寫入新照片，若寫入當下失敗（例如裝置空間不足，savePhoto() 回傳 nil），舊照片已被刪除、新照片沒存成功，使用者在毫無提示下永久遺失原本的照片；改為先寫入新照片、確認成功後才刪舊檔。畫面閃爍／不一致：③ PersonalEvent.occurs(on:) 的每月/每年重複比對過去嚴格比對「日 == 起始日」，但 NotificationManager 用 Calendar.byAdding(.month/.year) 展開通知時，月天數不足或非閏年會把結果夾到當月/當年最後一天（例如每月 31 號事件在 2/4/6/9/11 月夾到 28/30 號、閏年 2/29 事件在平年夾到 2/28），造成這類重複事件從行事曆畫面完全消失、卻仍準時收到推播通知；改用與 NotificationManager 相同的 Calendar.byAdding 邏輯算出「這個週期實際發生日」再比對。④ SubordinateRosterView 部屬班表水平捲動：v24.23 把捲動位移抽到獨立 RosterHOffsetBox（ObservableObject）並讓凍結表頭子視圖單獨觀察，但 SubordinateRosterView 自己卻用 @StateObject 持有這個物件——classic ObservableObject 下，任何持有 @StateObject/@ObservedObject 的視圖都會在其 objectWillChange 觸發時整個 body 重算，導致每次捲動寫入 hOffsetBox.value 時 SubordinateRosterView 本身也被連帶整個重繪（含棋盤格 O(人數 × 天數) 的 shiftFor/leaveFor 逐筆掃描），等於讓 v24.23 原本要隔離掉的閃爍/卡頓重新出現；改用 @State 持有同一個 class 實例（跨重繪仍保留同一份物件，但不會讓持有它的視圖訂閱其變化），只由子視圖真正觀察。⑤ SettingsView 手動設定匯率的 TextField 過去直接綁在 $store.currencyRates[index] 上，每敲一個字元都觸發 ExpenseStore.currencyRates 的 didSet（整份陣列重新編碼寫入 UserDefaults + 排程 CloudKit push）與 @Published 變動，讓整個 SettingsView（含其他所有 disclosureBlock 區塊）跟著重繪；抽成獨立 CurrencyRateRow 子視圖，比照 GradeTitleView.GradeTitleRow 既有修復規格，本地暫存文字/數值＋停止輸入 400ms 後才提交回 store。正確性：⑥ AddExpenseView 變動支出「關聯資產＝股票」且尚未連結既有股票時，會透過 syncStockInvestment() 建立全新 Stock，但股數／價格欄位留空沒有任何必填檢查，會被 (Double(...) ?? 0) 靜默存成股數 0、成本 0 的空殼持股，且與同一筆支出實際記錄的金額完全脫鉤；比照既有的「新增不動產物件必填購入價格」守衛補上。⑦ FixedExpenseView.insuranceHeaderAmount（固定支出「保險」分類小計膠囊）直接依 currencyCode 分組加總並用該幣別符號顯示，但只有儲蓄險的 amount 是原幣別存值，其餘保險（含外幣保費）在 AddExpenseView 儲存時就已換算成 NT$、currencyCode 卻仍保留原幣別代碼，導致非儲蓄險外幣保費（例如 100 美元換算後存成 NT$3,100）被誤標成「USD 3,100」顯示，與下方個別列的正確顯示相差匯率倍數；比照 FixedExpenseRow.formattedAmount 既有的 isSavingsIns 判斷分組。⑧ StockDetailView.infoSection「交易資訊」計數膠囊的基底列數寫成 4，但區塊實際固定渲染 5 列（成本總額／市值總額／損益／報酬率／購入日期），已賣出才加 1 列（賣出日期），導致徽章數字永遠少算 1；基底改為 5。⑨ FinanceChartView 資產總覽卡片頂部「X 項」總數把已出售的房地產也算進去，但正下方 KPI 橫列的房地產筆數已排除已出售，同一張卡片上總數與明細互相矛盾；改為總數同樣排除已出售房地產。競態：⑩ MainTabView.aiFinishRecording()（語音記帳）的 aiBusy 在 AI 解析完成後立刻清成 false，但實際寫入資料的 aiCommitExpense（含 Apple Maps 地點查詢與 expenseStore/lifeStore/financeStore 寫入）此時都還沒開始，麥克風按鈕的忙碌守衛因此提早失效，使用者可在上一筆記帳仍在背景 commit 時就按住麥克風開始錄下一筆，兩個 commit 交錯寫入、toast 顯示順序錯亂，畫面卻顯示「未在忙碌」造成誤導；改為 aiCommitExpense 完全結束後才清除 aiBusy。本輪另外複查出多個信心度較低或牽涉較廣的候選問題（例如：多處看板/明細卡片的 computed property 在同一次 render 被重複呼叫數次、房地產/儲蓄險/固定支出等彙總金額對非儲蓄險以外情境的跨幣別換算、RealEstateDetailView 複製連結支出時共用而非另存照片檔名、多個照片編輯器取消當下未取消進行中的照片載入 Task），評估屬於較大範圍的架構性調整或影響有限的效能微調，本輪未動，供後續版本評估。其餘複查範圍（Models 26 檔、Finance Views 23 檔、Life Views 33 檔全數逐檔覆蓋，並與 v22.x～v24.23 既有修復比對避免重複回報）均確認強制解包／as!／try! 已妥善守衛、CloudKit 30 秒節流／2 秒防抖／isSyncing 並行守衛未被繞過。"
        ]),
        ChangelogEntry(version: "24.23", build: 676, date: "2026/07/16", notes: [
            "【靜態除錯 v24.23：四路並行複查全部 83 個 Swift 檔，修復 7 處真實 Bug】資料遺失：① FinanceModels.Stock.seedTransactionsFromLegacyIfNeeded() 對「舊資料、已全部賣出且從未使用逐筆交易」的股票（shares 已歸零）因無法推算原始張數而放棄補種，但呼叫端 StockDetailView.StockDividendEditor 的 save()/performDelete() 仍無條件接著呼叫 recomputeFromTransactions()，在 transactions 仍是空的情況下把這筆股票僅存的 isSold／soldDate／soldPrice／purchasePrice 全部當成「無交易」靜默清空覆蓋；改為 seed 函式回傳是否補種成功，失敗時呼叫端跳過 recompute，保留舊欄位。② AddVehicleView／AddRealEstateView 新增流程中，只要在按下主要「新增」鍵前先新增過一筆定期/變動支出等子項目，就會經由 ensureVehicleSavedInStore()/ensureRealEstateSavedInStore() 提前把車輛/房地產寫入 FinanceStore 並同步上 CloudKit，但頂部「取消」按鈕完全沒檢查這個自動存檔狀態，使用者按取消後仍會永久留下一筆想放棄的空殼資產紀錄（連同已建立的支出/照片）；取消時比照列表頁滑動刪除的清理邏輯回滾，僅在新增流程（非編輯既有紀錄）且已自動存檔時才移除。畫面閃爍／競態：③ ChildDetailView.regeneratePreview() 切換「轉為素描畫」Toggle 時，首次需要背景運算產生素描檔的 Task 完成後不檢查 sketchMode 是否仍為開啟就直接覆寫 previewImage，使用者若在運算完成前把 Toggle 切回原圖，畫面會先正確顯示原圖、隨後又被過期的背景結果覆蓋回素描版；補上完成時的 sketchMode／photoFileName 守衛。④ GradeTitleView 職等清單的「職等」「職稱」輸入框過去直接綁在 lifeStore.gradeTitles[index] 上，每敲一個字元都觸發 LifeStore.save()（全量 12 個集合重新編碼寫入 UserDefaults + 排程 CloudKit push）與 @Published 陣列變動，讓整個 GradeTitleView（含英雄卡動畫、KPI）跟著重繪，快速輸入時明顯閃爍/卡頓；抽成獨立 GradeTitleRow 子視圖，本地暫存文字＋停止輸入 400ms 後才提交回 store（對齊 IncomeView/VariableExpenseView 既有搜尋防抖寫法）。⑤ SubordinateRosterView 部屬班表水平捲動時，凍結表頭位移雖已有 1pt 節流門檻，但真實手指拖曳的位移量幾乎每一捲動影格都超過門檻，導致整個 body（含棋盤格 O(人數 × 天數) 的 shiftFor/leaveFor 逐筆掃描）連帶重算，捲動明顯卡頓；改由獨立 ObservableObject 承載捲動位移，並把凍結表頭抽成只觀察該物件的子視圖，讓位移變化不再波及棋盤格本體。效能／正確性：⑥ NotificationManager 的 advanceToNextOccurrence／enumerateFires 對「有截止日」的每月/每年重複事件，過去用鏈式從上一步結果往下加一期，Calendar 對月天數不足會夾到當月最後一天（例如每月 31 號遇到 2 月夾成 28 號），鏈式累加會讓這個被夾住的日期變成下一步起點，往後每個月都固定卡在 28 號，通知時間永久提前 1–3 天且與行事曆畫面顯示的日期脫勾；改為每次都從原始起始日期重新加 n 期，不再鏈式累加。⑦ GradeTitleView 英雄卡「關聯鏈」KPI 直接加總所有部門的 upstreamIds+downstreamIds，但 syncReverseLinks 會把每條上下游關係雙向寫入兩個部門，等同把每條關係算兩次，顯示數字恆為實際關聯數的兩倍；除以 2 修正。其餘複查範圍（Models 26 檔、Finance Views 23 檔、Life Views 前後兩批共 33 檔全數逐檔覆蓋，並與 v23.9x～v24.22 既有修復比對避免重複回報）均確認無新問題：force unwrap／as!／try! 已妥善守衛、CloudKit 30 秒節流／2 秒防抖／isSyncing 並行守衛未被繞過。"
        ]),
        ChangelogEntry(version: "24.22", build: 675, date: "2026/07/15", notes: [
            "【靜態除錯 v24.22：多路並行複查全部 83 個 Swift 檔（含巢狀子代理逐檔覆蓋），修復 21 處真實 Bug】強制解包／Optional／型別／index 越界、retain cycle／競態條件、畫面閃爍、O(n²) 效能瓶頸。資料遺失／完整性：① AddRealEstateView 電梯保養照片選擇器的「取消前一個 Task」守衛只是無條件把登記表清空，連續選兩張照片時，較早那個 Task 完成時會把「較新、仍在執行中」的登記一併清掉，導致下一次選取的 cancel() 變成 no-op、新舊 Task 並行又互刪對方剛存好的檔案（v24.21 修復未完全堵住的殘留競態）；改用世代編號，只有仍是「最新一次選取」的 Task 才清空登記，並在刪除整筆保養記錄時一併取消尚未完成的載入 Task 避免孤兒檔案。② LifeFinanceView.DepositEditorSheet 編輯既有存款/提款時，類型 Picker 未鎖定，使用者中途切到「轉帳」或「沖正」會呼叫 saveTransfer()/saveAdjust()（兩者都不認得 editing）另外新增一筆或兩筆全新記錄，原本正在編輯的那筆完全沒被處理，帳戶餘額被靜默灌入幽靈記錄；改為編輯時停用類型切換。同一元件的 bankBalance(for:) 只單純加總 bankDeposits 原始條目，未扣信用卡彙總、週期性固定支出/收入也只算到第一筆種子條目，導致「轉入帳戶」下拉與「沖正」的目前總額被低估負債、高估餘額，沖正調整值連帶算錯；改為呼叫與列表頁 milestoneRow 同一份完整 bankBalances() 邏輯。③ AddExpenseView 用「新增物件」模式建立新房貸/新不動產連結時，購入價格留空或為 0 會被 (Double(rePurchasePriceText) ?? 0) 靜默存成 0，資產淨值、排序、稀有度全部算錯卻無任何提示；比照 AddRealEstateView／AddVehicleView／AddStockView 既有「新增資產必填價格」守衛補上。④ CloudSyncManager.beginInitialSync() 的 bootstrap 完成回呼未強制轉回主執行緒就直接修改 isSyncing（sibling function performSync() 已有這個修復但 beginInitialSync 沒跟上），zone/subscription 建立失敗時 isSyncing 從 CloudKit 背景佇列寫入，與主執行緒的並發讀寫形成資料競態，可能讓兩個同步流程繞過 isSyncing 守衛同時搶跑；補上 DispatchQueue.main.async。⑤ UnifiedImporter.applyUnified 的 .replace 模式直接 expense.expenses = payload.expense.expenses 整批覆蓋，略過 ExpenseStore.delete(_:) 才會呼叫的 Expense.deletePhoto，還原/匯入後若干支出消失但其照片檔案永久留在磁碟，且會被 CloudKitManager.uploadAllLocalPhotos() 不斷重新上傳浪費本機與 iCloud 空間；改為覆蓋前先對「舊有但新資料沒有」的支出逐一清照片。⑥ RealEstateDetailView.duplicateLinkedExpense 複製房貸相關支出時，Expense 複製建構子漏了 loanTotalAmount／loanYears／loanRate／insuranceRate 四個欄位，複製一筆已填貸款試算的房貸項目後，開啟複製品會發現貸款總額/年期/利率/保費率全部消失；補齊四欄位複製。⑦ StockDetailView.StockDividendEditor 的 .onChange(of: date) 在新增現金股利時無條件把 sharesAtEventText 重設為目前持股，使用者手動輸入的自訂股數（如記錄日當時的持股）只要調整日期就被靜默覆蓋；比照旁邊 .onChange(of: kind) 補上「欄位仍是空的才自動帶入」守衛。⑧ LifeStore.deleteOrgPerson／deleteSubordinate 刪除人員時只解除直接反向連結，未清除其他人「relations 陣列裡指向被刪者的 personId」與「其他部屬會議項目 assigneeId 指向被刪者」，留下永久指向不存在對象的失效引用（同型修復已用於 deleteFamilyMember 的 spouseId／deleteSubordinate 的 linkedSubordinateId，這兩處交叉引用當初漏補）；比照既有寫法補上清除。⑨ FamilyView.memberRow 右側日期用 if let bd = member.birthday { 生日 } else if role == .spouse, let md = marriageDate { 婚期／離婚徽章 }，兩者互斥，配偶幾乎都會填生日，導致已離婚的配偶在家人列表完全看不出離婚狀態（SpouseResumeView 卻正確顯示）；改為生日與婚期/離婚徽章各自獨立顯示。⑩ MyCalendarView.PersonalEventEditor 新增事件的「新增」按鈕沒有連點守衛，performSave() 內有多個 await 間隙，連續點兩下會用不同 UUID 並發建立兩筆重複事件、重複 Apple 行事曆項目、重複通知；比照 SubscriptionManager.purchaseInProgress 既有寫法補上 isSaving 旗標。⑪ HealthProfileEditView.AllergyEditor 嚴重度 Picker 用 get: { draft.severity ?? .mild } 顯示預設值，但使用者若沒手動點過 Picker，set 永遠不會被呼叫，draft.severity 實際存成 nil，畫面顯示「輕度」與存檔「未設定」互相矛盾（列表卡片因此不顯示嚴重度徽章）；開啟編輯畫面時把顯示的預設值寫回 draft。⑫ FullBackup.export 匯出附件時，manifest 裡的檔案 size 在迴圈開始前一次性取得並寫入檔頭，但實際位元組是在逐檔迴圈中才讀取寫入，匯出大量照片耗時較長時，若同一檔名的照片在此期間被 CloudKit 背景同步覆寫（例如 CloudKitManager.runFetch 在同一路徑 removeItem+copyItem），且新檔案大小與 manifest 記錄的不同，還原時會用錯誤的 size 切出位元組範圍，讓該附件及其後所有附件全部損壞且無錯誤提示；補上讀取後與 manifest size 不符就整個匯出失敗的守衛，寧可明確報錯也不要靜默產出壞檔。畫面閃爍／照片競態：⑬ OrgPersonEditor／FamilyMembersResumeView.FamilyAlbumPhotoEditor／ChildDetailView.ChildRecordEditorSheet／BusinessCardView 頭像共 4 處的 .onChange(of: photoItem) 選取照片後都是無守衛的 Task { await loadTransferable ... }，使用者在等待期間（尤其 iCloud 圖片需要下載）又重新選了一次或按了移除，較慢完成的前一次選取會覆蓋較新的結果，甚至讓已被使用者移除的照片又蓋回來；四處統一補上世代編號守衛，並在移除照片／改用拍照的分支一併讓進行中的載入過期。同一批修復中，FamilyAlbumPhotoEditor 過去在 Form body 內直接對 pendingImageData 呼叫 UIImage(data:)，標題/備註每次按鍵都觸發整個 Form 重新求值、連帶在主執行緒重新解碼一次完整 JPEG；改為只在照片來源產生資料當下解碼一次並快取（同型修復比照 OrgPersonEditor.pendingImage）。⑭ ChartView 的 chartHeightMeasuringLayer（用來量測 TabView 分頁高度的隱藏副本）與可見分頁共用同一個 $variablePieRowsAppeared／$fixedPieRowsAppeared，隱藏副本一掛載就搶先把旗標設成 true，等使用者第一次滑到圓餅圖分頁時旗標早已是 true，圖例交錯進場動畫因此完全不會播放；改為隱藏副本改傳入獨立的 .constant(true)，不干擾可見分頁的真正旗標。⑮ TaxOverviewView 的 taxRecordsSection 與 taxSavingSection 兩個互不相關的空狀態共用同一個 emptyIconPulse，其中一個空狀態先掛載並把旗標設成 true 後，另一個空狀態掛載時旗標已是 true，脈衝光環動畫偵測不到「從 false 變 true」的變化、直接停在動畫結束狀態（不透明度 0）不會播放；拆成 emptyRecordsPulse／emptySavingPulse 兩個獨立旗標。效能（重複計算、O(n²)）：⑯ TaxOverviewView 的 taxExpenses（filter+sort）被 annualSummaryCard／taxRecordsSection／monthlyBreakdown 三處各自獨立呼叫；改為 body 算一次往下傳。⑰ SubordinateDetailView.RecordEditorSheet 的 restDeductionHours（逐日走訪＋對 shifts 線性掃描）與內部呼叫它的 computedLeaveHours，在請假時間 Section 裡合計每次 render 被重算 4 次，FiveMinuteDateTimePicker 拖曳期間每一格都重跑；改為 Section 開頭算一次本地變數共用。⑱ ChildrenResumeView 的 children（filter+sort）在 heroStatsCard 內部就獨立呼叫 3 次，加上 body 的 isEmpty 檢查與 ForEach，一次 render 最多重算 5 次；改為 body 算一次傳給 heroStatsCard／childrenSectionHeader／ForEach。⑲ FamilyView.spouseDisplayName 對每一列成員都用 store.familyMembers.first(where:) 全量掃描配偶，對 N 位成員的清單等同 O(N²)；改為 body 建一次 [UUID: FamilyMember] 查表傳入。⑳ OrganizationView.DepartmentDetailView.peopleSection 的分隔線判斷 person.id != people.last?.id 在 ForEach 每一列都重新呼叫 people（對全公司人員重新 filter+sort），等同該部門人數 × 全公司人數的重複排序；改為 section 開頭算一次。㉑ SubordinateView.subordinateSections 的 filteredSubordinates／displayRows 被空狀態檢查、計數徽章、ForEach 三處各自獨立呼叫，displayRows 內部還會再呼叫一次 filteredSubordinates；改為一次算好 filtered／rows 兩個本地變數，全段共用。其餘複查範圍（Models 26 檔、Finance Views 21 檔、Life Views 27 檔、其餘 App/Views 8 檔全數逐檔覆蓋）均確認無新問題：force unwrap／as!／try! 絕大多數為零或已妥善守衛、CloudKit 30 秒節流／2 秒防抖／isSyncing 並行守衛未被繞過、v24.11～v24.21 既有修復維持正確且無回歸。"
        ]),
        ChangelogEntry(version: "24.21", build: 674, date: "2026/07/15", notes: [
            "【靜態除錯 v24.21：六路並行複查全部 83 個 Swift 檔，修復 17 處真實 Bug】強制解包／Optional／型別／index 越界、retain cycle／競態條件、畫面閃爍、O(n²) 效能瓶頸。資料遺失／完整性：① ChildDetailView 的插入圖片編輯器（ChildRecordEditorSheet）換照片／移除圖片會立刻刪除舊檔，使用者選好新照片或按了移除後若改按「取消」，原圖已被永久刪除卻沒有任何紀錄改用新內容；改為刪除延到 save() 依最終結果才提交，取消時原圖完整保留，session 中已選未存的新檔則在取消/再換照片時清掉避免孤兒檔案。② BusinessCardView 重新拍照辨識 OCR 覆蓋既有名片時，onAppear 的 prefilled 分支只保留 date／department 兩欄，漏了 primaryBusiness（主要往來），存檔會靜默清空這個欄位；比照 date／department 補上保留。③ ResumeView.AddMilestoneView.save() 設定配偶雙向綁定時，只把新選的另一半指回自己，沒有解除「本人原本配對的對象」與「新對象原本配對的別人」的舊 spouseId，會留下永久指向不存在配對關係的失效引用；比照 LifeStore.deleteFamilyMember 解除 spouseId 的既有寫法補上兩處清除。④ BusinessCardOCR.recognizeText 用 try? 吞掉 VNImageRequestHandler.perform 的錯誤，perform 拋錯時 completion handler 不會被呼叫，withCheckedContinuation 永遠不 resume，呼叫端 await 卡死、isProcessingScan/isRescanning 卡在 true 出不去；改用 do/catch 在 catch 分支 resume 空陣列。⑤ BackupManager.createSnapshotIfNeeded 只檢查 lastSnapshotDate 卻沒有並行守衛，冷啟動立刻切背景時 .onAppear 與 .onChange(scenePhase) 可能在同一秒內先後觸發，兩個背景佇列各自編碼寫入同一個以秒為單位命名的檔案，造成競態覆寫與重複運算；比照 CloudSyncManager.isSyncing 補上 isSnapshotting 旗標。⑥ AddRealEstateView 電梯保養照片選擇器、RealEstateDetailView 的 ElevatorMaintenanceEditor／UtilityPaymentEditor 三處，onChange(of: photoItem) 各自用無守衛的 Task 載入照片，連續選兩張照片時新舊 Task 並行，較快完成的先把 photoFileName 指向自己，較慢完成的隨後讀到已更新的值當「舊檔」誤刪，兩個 Task 互相刪對方剛存好的檔案；三處都補上取消前一個未完成 Task 的守衛。畫面閃爍（List/ForEach 進場動畫掛在錯誤層級，捲動時反覆重播，v24.20 修復 FamilyView 後仍有遺漏）：⑦ IncomeView／VariableExpenseView／FixedExpenseView 三個列表頁的 onAppear／onDisappear 過去掛在「日期或分類分組」的外層 ForEach 上而非 List 本身，捲動使任一分組進出可視範圍就各自觸發、重置所有列共用的旗標；⑧ SpouseResumeView 的里程碑／消費兩個列表區塊、⑨ ResumeGiftSection（6 個履歷頁共用元件）的禮金列表，同樣掛在會被 List 延遲載入機制個別回收的單一列 / 總計列上；六處均改掛在 List 或 Section 本身。⑩ ResumeView 的英雄卡／列表進場動畫旗標過去只有 onAppear 設 true、缺 onDisappear 重置，切到其他分頁再切回不會重播進場動畫；補上重置，對齊 CareerView／FixedExpenseView 既有寫法。效能（重複計算、O(n²)）：⑪ FinanceOverviewView 的 insuranceValueNTD／insurancePaidNTD 過去各自獨立重建匯率字典並重新 reduce store.insurances，被 totalAssetsCard／assetCards／ntdAllocations 三處合計呼叫達 5 次；改為單一 reduce(into:) 一次算出兩個值、body 只呼叫一次後往下傳參數。⑫ RealEstateDetailView 的 gallerySummary／renovationPhotosContent 各自獨立呼叫 linkedExpensePhotos（對 expenseStore.expenses 全量 filter），且 summary 不受展開狀態影響、每次 render 都會算，重複掃描兩次；改由呼叫端算一次後傳參數。⑬ LifeFinanceView.linkedCreditCardSection 的 isEmpty／count／ForEach 三處各自獨立呼叫 linkedCreditCards（對 lifeStore.milestones 全量 filter），同一次 render 被呼叫 4 次；改為區塊開頭算一次本地變數全段共用。⑭ MyCalendarView 的 heroEventsMap 在檢視非今日日期時，與 weekEventsMap 的日期範圍最多重疊 6 天，卻各自獨立呼叫較重的 eventsOn()（家人＋里程碑＋行事曆全量查詢）；改為先算聯集只呼叫一次，兩份 map 再從聯集結果取子集。⑮ OrganizationView.OrgPersonEditor.photoSection 過去直接在 body 內對 pendingImageData 呼叫 UIImage(data:)，姓名／職稱等任何欄位按鍵都會觸發 Form body 重新求值、連帶在主執行緒重新解碼一次完整 JPEG；改為只在照片來源（相機／相簿）產生資料當下解碼一次並快取。⑯ SubordinateDetailView.CompletedCollapsibleCard 展開已完成項目時，`if idx < sorted.count - 1` 在 ForEach 每一列都重新呼叫 sorted（對 entries 重新排序一次），等同整份清單被排序 n 次；改為先捕捉一次本地變數。⑰ AddExpenseView.bankPicker 的 allBankBalances() 雖已改批次建表，但仍在每次按鍵觸發的 body 重新求值中被重新呼叫、重建整批表；改為 .task(id:) 只在 store.expenses／lifeStore.milestones 實際變動時才重算並快取。附帶修復：AddExpenseView 的 showValidationError 錯誤卡片顯示後，使用者接著修正名稱／金額，卡片會一直留著誤導使用者，直到下次按儲存才重新判斷；補上 onChange(of: title/amountText) 立即清除。其餘複查範圍（含 Models 25 檔、Finance Views 15 檔、Life Views 26 檔）均確認無新問題：force unwrap／as!／try! 絕大多數為零或已妥善守衛、CloudKit 30 秒節流／2 秒防抖／isSyncing 並行守衛未被繞過、v24.11～v24.20 既有修復維持正確且無回歸。"
        ]),
        ChangelogEntry(version: "24.20", build: 673, date: "2026/07/14", notes: [
            "【靜態除錯 v24.20：修復 10 處真實 Bug】四路並行複查全部 83 個 Swift 檔案（強制解包／Optional／型別／index 越界、retain cycle／競態條件、畫面閃爍、O(n²) 效能瓶頸）。① CloudSyncManager.resolveInitialSync 的 .overwriteLocal（首次同步選「用雲端覆蓋本機」）只把 cloudBlobs 裡「雲端已有」的 key 寫回本機，雲端從未寫入過的分類（例如另一台裝置從未使用過的資料類別）完全不動，導致本機舊資料殘留，且下方 pushAllKV 還會把這批使用者明確想丟棄的舊資料原封不動地重新推回雲端；改為改走 Self.syncKeys 全清單，雲端沒有的 key 一併 removeObject。② SubscriptionManager.purchase(_:) 旁的 restorePurchases() 註解宣稱「purchase(_:) 已有 purchaseInProgress 守衛防止連點重入」，但 purchase(_:) 實際上只設定旗標、從未檢查旗標，PaywallView 快速連點購買鈕會並發呼叫兩次 product.purchase()；已補上 guard !purchaseInProgress。③ AddStockView.fetchStockInfo 等待 TWSE 報價回應期間沒有鎖定 symbol，使用者若在等待中把代號改成另一檔股票，回應返回時仍會把舊代號的報價套用到新代號欄位；三處回傳點都補上「代號沒變才套用」的守衛。④ AddStockView.save() 勾選「已賣出」卻沒填賣出價格時，(Double(soldPriceText) ?? 0) 會靜默把賣出價存成 0（100% 虧損），不提示任何錯誤；已在存檔前擋下並要求補填。⑤ FamilyView 的成員列表進場動畫 onAppear／onDisappear 過去掛在 List → Section 內的 ForEach 上，而非 List 本身：List 會延遲載入各列，掛在 ForEach 上等同掛在每一列各自的子視圖上，捲動使某列進出可視範圍就各自觸發一次，成員數超過一屏時，全部列共用的 membersAppeared 旗標被反覆觸發，導致可視列表捲動時無謂淡出又重播進場動畫；比照 FamilyMembersResumeView／ChildrenResumeView 既有寫法，改掛在 List 本身。⑥ LifeStore.deleteFamilyMember 只移除該筆成員，未清除配偶另一方的 spouseId（ResumeView 儲存配偶關係時會雙向寫入），刪除任一方後另一方的 spouseId 永久指向不存在的成員 id；比照 deleteSubordinate 解除 linkedSubordinateId 的既有寫法補上清除。⑦ LifeFinanceView 的 depositChart 及 creditCardChart／creditCardChartPages／creditCardMonthlyTotals 過去各自獨立重算一次 deposits／expandedCreditCardEntries（分別建 expensesById／incomesById 查表並展開固定支出與週期性收入／信用卡週期性扣款，屬於較重的計算），同一次 body 求值最多被重複算 2～3 次；改為由呼叫端（depositSection／creditCardChartSection）算好一次後往下傳參數。⑧ TalentMatrixView 的部門篩選變更後，若明細卡（selected）仍開著且選取的成員不在新篩選範圍內，卡片會用 ?? 0 頂替空分數卻仍疊在畫面上，呈現自相矛盾的資料；補上 .onChange(of: deptFilterRaw) 篩選一變就收起明細卡。⑨ SettingsView.isAllDataEmpty（危險操作「清除所有資料」按鈕的啟用判斷）只檢查 milestones／relationships／pets／schedules 四類，未涵蓋 LifeStore.clearAll() 實際會清空的 familyMembers／subordinates／departments／gradeTitles／businessCards／personalEvents／orgPeople／healthProfile，只有家人/部屬/組織/健康資料而無其他分類的使用者會發現按鈕被誤判為停用；改為新增 LifeStore.isEmpty（涵蓋範圍對齊 clearAll()）並改用它。⑩ UnifiedImporter 的合併匯入模式（.merge）對 life.profile 無條件覆蓋，與緊鄰兩行後對 healthProfile「僅本機為空才覆蓋」的保護邏輯不一致，匯入他人備份或分享檔會把自己的姓名等個人資料覆蓋掉；已比照 healthProfile 補上同樣保護（新增 UserProfile.isEmpty）。另附帶修復：AddSavingsInsuranceView.syncFixedExpense 建立連結的固定支出時未帶入 currencyCode（預設回退為 NT$），外幣儲蓄險的保費會被 FixedExpenseView 依幣別加總時誤算成台幣金額；EInvoiceSetupView.attemptLink 驗證手機條碼格式用未 trim 的原始輸入，而 EInvoiceSyncManager.linkCarrier 內部會 trim 後才存，貼上帶尾端換行的條碼會被誤判格式錯誤；RenovationPhotoEditor 的 cancel()／deleteRecord() 過去分別只在「新增模式」才清檔案、只刪「進入編輯畫面時的舊快照」，編輯既有裝潢照片紀錄時新增的照片，無論按取消或刪除整筆紀錄都不會被清掉，變成永久孤兒檔案；兩處都改為以目前即時的 photoFileNames／editing 快照做正確的差集清理。其餘複查範圍（含 MedicalMapView／MyCalendarView／OrganizationView／SubordinateRosterView／MainTabView 等）均確認無新問題：force unwrap／as!／try! 全數為零、陣列存取皆有邊界守衛、CloudKit 30 秒節流／2 秒防抖／isSyncing 並行守衛未被繞過、v24.11～v24.19 既有修復維持正確且無回歸。"
        ]),
        ChangelogEntry(version: "24.19", build: 672, date: "2026/07/14", notes: [
            "【靜態除錯 v24.19：修復 3 處真實 Bug】四路並行複查全部 83 個 Swift 檔案（強制解包／Optional／index 越界、retain cycle／競態條件、畫面閃爍、O(n²) 效能瓶頸）。① MainTabView.aiLookupPlace：`let search = MKLocalSearch(request:)` 後以 `withCheckedContinuation` 包裝 `search.start { resp, _ in cont.resume(...) }`，回呼閉包沒有捕捉 search，ARC 可能在非同步查詢完成前就把 search 釋放，導致 continuation 永遠不 resume——這正是 RestaurantSearch.swift 先前已修過並留下 `[search]` + `_ = search` 防呆註解的同一種 bug，唯獨 MainTabView 這處沒有比照套用；AI 記帳（語音/拍照記帳）落在餐飲/娛樂/購物/民生/醫療分類時會呼叫此函式解析地點，觸發時整筆 AI 記帳流程可能無限卡住或地點欄位靜默留空。已比照既有寫法補上 `[search]` 捕捉。② CloudSyncManager.handleKVChanges 收到 CloudKitManager 算好的實際變更 key 集合後，一路只 post 不帶 userInfo 的 `.cloudSyncDidPullChanges`；ExpenseStore／FinanceStore／LifeStore 的 reloadFromCloud 完全不看是哪些 key 變了，任何一個 Store 的雲端異動都會讓其餘兩個 Store 也整批重新解碼、重設 @Published 陣列——例如另一台裝置只改了車輛資料，這台裝置的 ChartView 卻會因為 ExpenseStore.modifyID 被無謂更新而重播圖表淡出/淡入與圓餅圖進場動畫。已讓 handleKVChanges 轉發 keys 至通知的 userInfo，三個 Store 的 reloadFromCloud 改為先比對自己名下的 key 是否有交集，無交集就跳過整批重載；首次同步覆蓋／合併等未帶 keys 的既有呼叫路徑維持原本全量重載行為不變。③ SubordinateRosterView（部屬班表）的凍結表頭同步：iOS 18 的 onScrollGeometryChange 與 iOS 17 後援的 onPreferenceChange 都無條件把捲動位移寫入 `@State hOffset`，任何一次寫入都讓 body 重新執行，連帶重建整個棋盤格（每個人每一天都呼叫 shiftFor／leaveFor 對 shifts／records 陣列做線性掃描）；部屬多、排班紀錄累積長達一兩年時，單純拖曳橫向捲動每秒觸發數十次全表重算，主執行緒明顯卡頓。比照 StockView.swift 既有的 `scrollOffset` 節流寫法（位移變化 >1pt 才寫入），為兩處寫入點加上同樣的節流守衛。其餘複查範圍（Models 24 檔／Finance Views／Life Views 及主要進入點）均確認無新問題：force unwrap／as!／try! 全數為零、陣列存取皆有邊界守衛、其餘 NotificationCenter／Timer／completion closure 均正確使用 [weak self] 或值型捕捉、CloudKit 30 秒節流／2 秒防抖／isSyncing 並行守衛未被繞過、DateFormatter/NumberFormatter 均為 static let 快取、v24.11～v24.18 既有修復維持正確且無回歸。"
        ]),
        ChangelogEntry(version: "24.18", build: 671, date: "2026/07/14", notes: [
            "【功能】部屬會議議程項目（MeetingItem）新增「截止時間」與「完成開關」：① 過去會議項目的截止日只能選日期（DatePicker 為 .date），現在編輯會議畫面（MeetingEditorSheet）每個議程項目改為「設定截止時間」Toggle + 日期時間選擇器（displayedComponents 由 .date 改為 [.date, .hourAndMinute]），可精確到時分；未開啟 Toggle 則不設截止（dueDate = nil），開啟時預設帶入排程時段（FiveMinuteDateTimePicker.defaultSchedulingTime）。② 議程項目的完成與否，過去只能在部屬詳細頁的議程列表勾選，現在編輯會議畫面每個項目也各有一個「已完成／未完成」Toggle，切換時同步寫入 completedAt（開啟＝當下時間、關閉＝清空）。③ 會議預覽卡（SubordinateItemCard 的 .meeting 分支）原本議程項目的勾選圖示是唯讀靜態圖示，現改為可點擊按鈕，直接呼叫 lifeStore.toggleMeetingItemCompletion 切換完成狀態，並在項目下方以時鐘圖示顯示截止時間（僅設有時間時顯示時分、午夜 00:00 則僅顯示日期）、已完成項目右側顯示完成時間並套刪節線。詳細頁議程列（meetingItemRow）的截止時間顯示同步改為有時分才顯示時分、否則僅日期，三處顯示邏輯一致。"
        ]),
        ChangelogEntry(version: "24.17", build: 670, date: "2026/07/14", notes: [
            "【美化】設定頁（SettingsView）「資料統計」區塊「支出記錄區間」列圖示圓升級：承接 v24.16 留下的待辦事項，該列圖示原本是 32pt 純色填色圓、是全檔案圖示圓唯一還沒套用 LinearGradient + stroke 的殘留位置，與同區塊三模式統計徽章、緊接在後的資料管理／訂閱／iCloud 同步等所有列式圖示視覺落差明顯。改為 36pt LinearGradient 漸層圓 + 描邊 + 陰影，對齊 settingsActionRow（圖示 + 標題/副標 + Spacer 同結構列）既有規格。純視覺調整，支出日期區間計算與顯示文字完全未變動；SettingsView 全檔案圖示圓規格至此已收斂一致。"
        ]),
        ChangelogEntry(version: "24.16", build: 669, date: "2026/07/14", notes: [
            "【美化】設定頁（SettingsView）「使用中的 AI 服務」Picker 補齊圖示錨點：原本是純文字裸排選單，是 aiAssistantSection 區塊中唯一沒有圖示錨點的列，與緊接在後、v6 已升級的 providerKeySection 供應商列（22pt 漸層圖示圓）視覺落差明顯。改為自訂 label（22pt 紫色漸層圖示圓 + 文字），圖示隨目前啟用中的供應商動態切換，停用時顯示中性 poweroff 圖示。純視覺調整，Picker selection binding／AIProvider 啟用判斷邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.15", build: 668, date: "2026/07/14", notes: [
            "【美化】個人行事曆事件預覽卡（MyCalendarView.CalendarEventCard）標頭承接上一版留下的待辦事項：titleBlock 原本是裸 48pt icon 圓 + 標題文字直接貼在系統分組背景上，是本檔案（已完成主畫面英雄卡／sectionHeader／PersonalEventEditor Section 標題美化）中唯一還沒接上「閃卡」規格的區塊，與 StockDetailView／SubordinateDetailView 等其他詳情頁的漸層英雄卡（雙散景圓 + 頂部玻璃光澤）視覺落差明顯。改為依事件類型變色的漸層英雄卡：會議＝indigo、事務＝cyan、里程碑＝橘、系統行事曆＝藍、生日＝粉金、紀念日＝玫瑰紅，卡內新增類型 Capsule 徽章（沿用既有 navTitle 文案）+ spring 進場動畫。另新增 heroGradientColors 一組手調深色調漸層，與純顯示用的淺色 accent（icon/欄位/按鈕沿用不變）分開計算，避免 family 粉色系等淺色 accent 直接當滿版背景時白色文字對比不足。純顯示層調整，事件／里程碑／Apple 行事曆／家人紀念日詳情欄位、編輯、開啟系統行事曆等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.14", build: 667, date: "2026/07/13", notes: [
            "【靜態除錯 v24.14：修復 1 處真實 Bug】三路並行複查全部 83 個 Swift 檔案（Models 24 個／Finance Views 23 個／Life Views 及主要進入點 35 個），聚焦 force unwrap／as!／try!／陣列越界、retain cycle、非同步覆寫競態、CloudKit 30 秒節流是否遭繞過、O(n²) 迴圈與可快取的重複運算。RealEstateView.deleteEstate（不動產列表滑動刪除）收集貸款／已支出／變動支出／保險／資產／買賣關聯支出 ID 後直接 `expenseStore.expenses.removeAll`，卻漏了刪除這些 Expense 上透過 AddExpenseView 附加的收據照片檔案——同一份資料模型在 RealEstateDetailView.deleteEstate（詳細頁刪除路徑）、VehicleView／VehicleDetailView、SavingsInsuranceView、StockView 等五處對等刪除路徑都已在刪除紀錄前先跑 `for name in exp.photoFileNames { Expense.deletePhoto(name) }`，唯獨列表頁滑動刪除這條路徑遺漏，導致從列表直接刪除不動產時，關聯支出的收據照片變成無法再被存取、也無從清除的孤兒檔案，長期占用裝置儲存空間。已補上與其餘五處一致的照片清除迴圈。Models 群組（24 檔）與 Life Views 群組（35 檔）複查後確認無新問題：force unwrap／as!／try! 全數為零、陣列刪除皆採「先建快照／id 比對」安全模式、Coordinator／Timer／NotificationCenter 閉包 [weak self] 捕捉與 deinit 清理正確、CloudKit isSyncing 並行守衛與 30 秒節流／2 秒防抖未被繞過、v24.12／v24.13 既有修復（9 處 savePhoto／saveSketch 回傳 nil、SubordinateRosterView 凍結表頭 iOS 18 版本守衛）均維持正確且無回歸。"
        ]),
        ChangelogEntry(version: "24.13", build: 666, date: "2026/07/13", notes: [
            "【靜態除錯 v24.13：修復 1 處真實 Bug】延續前幾輪多路並行複查（本次聚焦過去幾輪較少提及、複查密度較低的 24 個 Models／Views 檔案）。SubordinateRosterView 的凍結表頭同步機制：build 521（v22.54）改為 iOS 18 用 onScrollGeometryChange 直接讀取 contentOffset 同步 hOffset，並保留 GeometryReader＋PreferenceKey 量測作為 iOS 17 以下的後援，但當初只把 onScrollGeometryChange 包進 `if #available(iOS 18.0, *)`，消費 PreferenceKey 的 onPreferenceChange 卻沒有對應加上 iOS 版本守衛；導致在 iOS 18+ 裝置上，每次水平捲動同一影格內兩套機制同時對同一個 @State hOffset 寫值——GeometryReader 那套依版面量測時機、onScrollGeometryChange 依捲動回呼時機，兩者更新時間點不同步，快速滑動／甩動時表頭偶爾會與日期格短暫不同步，重複寫入也造成多餘的 body 重繪。改為 onPreferenceChange 內以 `guard #unavailable(iOS 18.0) else { return }` 提前返回，讓 iOS 17 後援量測值僅在 iOS 18 以下才會真正寫入 hOffset，與 onScrollGeometryChange 互斥，恢復 build 521 原本「iOS 18 用新法、iOS 17 用後援」的單一寫入來源設計。其餘複查範圍（force unwrap／as!／try!／unguarded index、retain cycle、CloudKit 節流、O(n²) 迴圈、@State 過度重繪）均確認無新問題，詳見本輪覆查的 SubordinateDetailView／RestaurantSearch／AIService／KeychainHelper／InvoiceCategorizer／HolographicBuildingView／AddStockView／TravelMapView 等檔案。"
        ]),
        ChangelogEntry(version: "24.12", build: 665, date: "2026/07/13", notes: [
            "【靜態除錯 v24.12：修復 2 處真實 Bug】多路並行複查全部 83 個 Swift 檔案（Models + Views）。① Expense／ElevatorMaintenance／UtilityPayment／RenovationPhoto／FamilyAlbumPhoto／ChildRecord（savePhoto＋saveSketch）／BusinessCard／OrgPerson 共 9 處 savePhoto／saveSketch，寫入本機檔案失敗時（低儲存空間、App 被系統中止等）guard 分支雖正確跳過 CloudKit 上傳，卻仍 `return name`——與成功時回傳完全相同的檔名字串，導致呼叫端（AddExpenseView／RenovationPhotoEditor 透過 MultiPhotoGallery 無條件 `fileNames.append`，以及 ChildDetailView／BusinessCardView／OrganizationView／FamilyMembersResumeView／AddRealEstateView／RealEstateDetailView 等直接寫入 photoFileName）誤以為存檔成功，把一筆指向不存在檔案的紀錄永久寫進資料模型，此後該張照片在任何畫面都顯示空白且無從復原。9 處均改為寫入失敗時回傳 nil（函式簽章改為 `-> String?`），MultiPhotoGallery.onSaveImage 對應改為 `(Data) -> String?` 並在 append 前 `if let` 解包；其餘既有 photoFileName 欄位本就是 String?，直接指派不受影響。② AddExpenseView.applySuggestion 選擇 Apple Maps 候選地點時，非同步 resolve(_:) 完成後直接覆寫 placeAddress／placeLatitude／placeLongitude，沒有任何世代比對；使用者快速連續點選兩個不同候選（例如清單上兩間鄰近的同名分店）會並發觸發兩次 resolve，先送出的請求若較晚完成，會用不相符的舊座標覆寫已經顯示的新地址，標題與地址／座標對不上、地圖釘選錯位且無任何錯誤提示。新增 placeSelectionToken，每次選擇候選或呼叫 clearPlace() 皆遞增，resolve 完成回填前比對 token 是否仍是最新一次選擇，過期結果直接丟棄。其餘複查範圍（force unwrap／as!／try!／fatalError、陣列越界守衛、[weak self] 捕捉、CloudKit 30 秒節流／2 秒防抖／isSyncing 並行守衛、O(n²) 迴圈、畫面閃爍相關 @State 重繪）均確認無新問題。"
        ]),
        ChangelogEntry(version: "24.11", build: 664, date: "2026/07/13", notes: [
            "【美化】記帳新增/編輯畫面（AddExpenseView）同行人員／收受人多選彈窗關閉鈕位置與已選提示：socialRecipientSelectorList（收受人多選 Sheet）的「完成」關閉鈕原本是 .topBarTrailing，是本檔案 NavigationStack Sheet 中唯一沒有比照全 App 一律置左規則（EInvoiceSetupView／TalentMatrixView／SubordinateRosterView 等單一「完成」鈕皆為 topBarLeading）的例外；改為 topBarLeading。diningMemberSelectorList（同行人員多選彈窗）原本是「標題置左、完成鈕置右」的自訂版面，與修正後的收受人彈窗（置左按鈕 + 置中標題）不一致，改為同款 ZStack 置中標題 + 置左按鈕版面，讓這兩個相鄰、性質相同的多選彈窗視覺語言一致。另外兩處標題旁補上「已選 N」提示膠囊（同行人員綠色、收受人粉色，對齊各自既有選取色與開啟入口圖示色），僅在有選取時顯示，不用展開清單也能得知已選人數。純顯示層／版面調整，人員多選、收受人分組、勾選切換等既有商業邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.10", build: 663, date: "2026/07/13", notes: [
            "【美化】兒女詳細頁（ChildDetailView）Tab 切換器描邊 + 「還有 N 筆」溢出提示統一：自訂 Capsule Tab 切換器背景原本只有底色、無描邊，是本頁滾動內容中唯一沒有邊框的容器；補上與 headerCard／各 section 卡片一致的細邊框。日常記錄／消費兩處「還有 N 筆」原本是左側行內純文字且標點不一致（「筆...」三點 vs 「筆…」全形省略號），改為共用 overflowCountBadge(_:) 水平置中 Capsule 膠囊徽章，對齊 ResumeView／ResumeGiftSection／OrganizationView／SpouseResumeView 全 App「還有 N 筆…」統一規格。純顯示層調整，育兒記錄／消費連動篩選與 prefix(20) 截斷邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.06", build: 662, date: "2026/07/13", notes: [
            "【美化】設定頁（SettingsView）AI 語音記帳說明區塊補齊圖示錨點：aiAssistantSection 頂部「啟用後會出現麥克風按鈕」／「語音辨識在裝置上完成」兩行說明文字原本純文字裸排、無任何圖示，是本檔案「AI 語音記帳」整組區塊（說明 + 供應商選單 + 各供應商 API Key 列）中唯一沒有圖示錨點的部分，與緊接在後的 providerKeySection 供應商列（22pt 漸層圖示圓）視覺不連貫。補上同規格 22pt 紫色漸層圖示圓（waveform），讓整組區塊圖示語言一致。純顯示層調整，語音辨識、AI 欄位抽取、API Key 讀寫與 Keychain 儲存等既有邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.05", build: 661, date: "2026/07/13", notes: [
            "【美化】財富總覽不動產全息大樓卡（HolographicBuildingView）操作流暢性 + 空狀態補齊：FloorTagView 樓層標籤原本套用 .buttonStyle(.plain)，點擊完全沒有觸控回饋，是本元件唯一沒有互動反饋的可點擊項目；補上 HUDPressableStyle（縮放至 0.96 + 0.12s ease-out），對齊 MultiPhotoGallery 縮圖按下手感。樓層清單改為進場交錯動畫（opacity 0→1 + offset x: -10→0，每列間隔 0.05 秒）。物件尚未新增任何樓層時，原本清單直接留白；補上 HUD 風格空狀態圖示 + 「尚無樓層資料」提示文字。純視覺／互動回饋層調整，SceneKit 3D 建築渲染、樓層排序與選取邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.04", build: 660, date: "2026/07/12", notes: [
            "【美化】設定頁（SettingsView）語音 AI 助手供應商列圖示圓升級：providerKeySection 標題列原本是裸 Image(systemName:) 圖示直接貼在列首、已設定 Key 時只顯示一顆孤立的 checkmark.seal.fill，與同檔案 currencyRateSection 幣別列已有的「22pt 漸層小圖示圓（fill 0.20→0.08 + stroke 0.20, 0.75pt）」規格、以及 subscriptionSection／iCloudSyncSection 已有的「狀態 Capsule 徽章」規格不一致。改為供應商圖示套用同款 22pt 漸層圖示圓，已設定 Key 時改顯示綠色「已設定」Capsule 徽章（對齊「已訂閱」／「已登入」既有配色與樣式），消除本檔案語音 AI 助手區塊圖示圓/狀態徽章雙重視覺落差。純顯示層調整，Anthropic／OpenAI／Gemini 三供應商 API Key 讀寫、Keychain 儲存、啟用中服務判斷等既有邏輯完全未變動。"
        ]),
        ChangelogEntry(version: "24.03", build: 659, date: "2026/07/12", notes: [
            "【靜態除錯 v24.03：修復 4 處真實問題】多路並行複查全部 83 個 Swift 檔案（Models + Views），修復：① CloudSyncManager.flushPushAll()（每次 Store.save() 觸發，2 秒防抖後最常走的推送路徑）原本用自建 DispatchGroup 逐一呼叫 pushKV() 卻捨棄各自成功與否的結果，且完全不設定 isSyncing 旗標；只要其中一個 key 推送失敗（例如短暫網路錯誤），group.notify 仍無條件呼叫 markSynced()，把失敗的一輪誤標為已成功、清空錯誤訊息並推進 lastSyncDate，使用者看不到同步失敗、30 秒節流還會延後下次真正重試；同時因為沒設 isSyncing，這批推送進行中若剛好觸發 scenePhase 前景喚醒的 performSync()，會並行對同一批 key 送出第二輪推送，形成本檔案其餘四個入口（beginInitialSync／resolveInitialSync／performSync）都已用 isSyncing 防護、唯獨此處漏掉的競態視窗。改為直接呼叫 CloudKitManager.pushAllKV()（已封裝好的聚合成功結果 completion），比照其餘三個入口設定 isSyncing = true/false，只在 allOK 時才 markSynced()。② SpouseResumeView 的 heroCard／marriageSection 兩處「結婚年數」皆固定算到 Date()，配偶已離婚（isDivorced + divorceDate）時仍持續往上累加天數，與同一畫面「已離婚」列顯示的離婚日期自相矛盾；改為離婚時以 divorceDate 為結算終點。③ AddRealEstateView.PhotoViewerSheet（房地產物件照片／房屋資料照片／FamilyMembersResumeView 家人照片三處共用的縮放檢視器）原本在 body 內直接呼叫 Data(contentsOf:) + UIImage(data:)，而 pinch 縮放／拖曳兩個手勢的 onChanged 都會修改 @State scale／offset 觸發 body 重新求值，等於每個手勢影格都在主執行緒重新讀檔＋解碼一次大圖，縮放時明顯卡頓；改為 .task 內以 Task.detached 背景讀取一次存進 @State，body 只讀取記憶體中已解碼的圖片。④ BusinessCardView.avatarContent（名片詳情頁大頭貼，任何 showCamera／showPhotosPicker／showQRFullscreen 等旗標切換都會觸發此區塊重繪）仍用 UIImage(contentsOfFile:) 同步讀檔，是 MedicalMapView 內註解列出的最後一處殘留同型問題；改用既有共用元件 AsyncLocalImage 背景讀取，並同步更新該處已過時的殘留清單註解。其餘複查範圍（force unwrap／as!／try!／fatalError、陣列越界守衛、[weak self] 捕捉、StockView 30 秒節流、AppleCalendarBridge 防抖、ChartView O(n) 圖表計算）均確認無新問題。"
        ]),
        ChangelogEntry(version: "24.02", build: 658, date: "2026/07/12", notes: [
            "【靜態除錯 v24.02】延續 v24.01 修完 11 處真實 bug 後的複查：本次針對強制解包／Optional／型別／index／retain cycle／競態條件、畫面閃爍、效能瓶頸三大類，重點複查較少被前幾輪掃到的 Model 檔案（KeychainHelper／FeatureGate／AppMode／HealthModels／EInvoiceSyncManager／FullBackup／NotificationManager／RestaurantSearch／AIService.SpeechRecognizer／LocationContextProvider）與 v24.01 當輪新修的 11 處（AI 記帳銀行／房地產同步、DepositEditorSheet 沖正回填、StockDetailView 交易清空歸零、IncomeView rawSpendingRatio、ChildDetailView／AddRealEstateView 換照片 UUID 檔名、AddRealEstateView 保險/資產刪除與清空連動、RealEstateDetailView 複製項目 nil 分支、SubscriptionManager 還原購買守衛、OrganizationView AsyncLocalImage）逐一覆查是否有回歸；另複查 CloudSyncManager 30 秒節流／2 秒防抖／isSyncing 並行守衛、StockView 30 秒報價節流、AppleCalendarBridge 0.3 秒防抖、FullBackup 附件位元組偏移量與 manifest／附件大小上限守衛、NotificationManager 通知數量上限與越界索引防護、ChartView X 軸標籤越界索引。結論：均實作正確、無發現新的高信心 bug 或畫面閃爍／效能問題，本次未變動任何邏輯，僅同步版本號。"
        ]),
        ChangelogEntry(version: "24.01", build: 657, date: "2026/07/12", notes: [
            "【靜態除錯 v24.01：修復 11 處真實 Bug】本次針對強制解包／Optional／型別／index／retain cycle／競態條件、畫面閃爍、效能瓶頸三大類，用多路並行複查全部 83 個 Swift 檔案（Models + Views）。修復：① MainTabView.aiCommitExpense（AI 語音記帳）原本只把 Expense 寫進 expenseStore 就結束，沒有比照 AddExpenseView.save() 呼叫銀行扣款／房地產支出同步，AI 標了扣款帳戶或房地產後，銀行餘額、房地產支出章節完全看不到這筆錢，帳實不符；且扣款幣別寫死 NT$，外幣帳戶會記錯桶。補上 aiSyncBankWithdrawal／aiSyncRealEstateExpense，幣別改讀該帳戶既有存款紀錄。② LifeFinanceView.DepositEditorSheet 編輯既有「沖正」存款紀錄時，onAppear 沒有回填 isAdjust，直接按儲存會用預設值重建 BankDeposit，靜默把沖正紀錄改成普通存提款、遺失對帳備註；save() 補上保留原始 isAdjust／note。③ StockDetailView 刪除股票最後一筆交易後，因 transactions 變空而跳過 recomputeFromTransactions()，shares／市值／損益殘留刪除前舊值，與已清空的交易列表矛盾；改為無條件呼叫，並讓 recomputeFromTransactions() 在交易與配息皆空時明確歸零。④ IncomeView 支出比例的 spendingRatio 在算出當下就被夾在 1.0，同時用於進度條寬度與「支出 X%」文字，超支超過 100% 時文字失真固定顯示 100%；拆成 rawSpendingRatio（文字用，不夾）／spendingRatio（寬度用，夾 1.0），對齊 VariableExpenseView 既有 rawRatio/barRatio 規格。⑤ ChildDetailView 換照片沿用 editing.id 當檔名同路徑覆寫，清單縮圖用的 AsyncLocalImage 依 url 判斷是否重讀，url 沒變不會重讀，換照片後停留舊圖；改用全新 UUID 檔名，素描檔名跟著同一個新 id。⑥ AddRealEstateView 電梯保養照片同樣用 item.id 當檔名，除了同型縮圖不更新，還會透過 RealEstateDetailView 的全域 ThumbnailCache（NSCache，依 url.path 為 key）跨畫面持續顯示舊圖，影響範圍比一般 View 內 @State 快取更大；改用全新 UUID。⑦ AddRealEstateView 保險／資產項目的刪除按鈕直接 expenseStore.expenses.removeAll，繞過 expenseStore.delete(_:) 的照片清理，刪除後若原支出有附加照片會變成孤兒檔案；改用 expenseStore.delete(_:)。⑧ 同檔案保險／資產金額被清空存檔時，只把 linkedExpenseId 設 nil，沒有刪除先前已連動的 Expense，孤兒紀錄會繼續計入變動支出總額且從此無法從 UI 察覺；補上刪除。⑨ RealEstateDetailView 貸款／已支出／變動支出三處 duplicateXxxItem，對 linkedExpenseId 為 nil 的項目（monthlyMortgage 舊版遷移、iCloud 還原資料常見）完全沒有 else 分支，滑動「複製」靜默無反應；比照既有 deleteXxxItem 的 else 分支補上本地複製。⑩ SubscriptionManager.restorePurchases() 沒有 purchase(_:) 已有的 in-progress 守衛，連續點擊「還原購買」會並發觸發多個 AppStore.sync()；新增 restoreInProgress 旗標，SettingsView 按鈕同步 disabled。⑪ OrganizationView.headerCard 用 UIImage(contentsOfFile:) 同步讀檔解碼，是本檔案唯一漏套用既有 AsyncLocalImage 背景讀取規格的位置，開編輯/刪除 sheet 轉場時容易掉幀；改用 AsyncLocalImage。另外修復 IncomeView／VariableExpenseView 的 groupedByDate 分組 key 只到「月.日.星期幾」沒有年份，跨年資料若同月同日同星期幾會被誤合併成同一個 Section、金額加總混在一起；分組 key 改用含年份的 yyyy-MM-dd，顯示文字仍用原本無年份格式，不影響既有版面。其餘複查範圍（force unwrap／as!／fatalError、陣列越界守衛、[weak self] 捕捉、CloudKit 30 秒節流／2 秒防抖／isSyncing 並行守衛）均確認無新問題。"
        ]),
        ChangelogEntry(version: "24.00", build: 656, date: "2026/07/12", notes: [
            "【美化】家人履歷詳細頁（FamilyMembersResumeView.FamilyMemberDetailView）禮金金額量級一致性：memberGiftsSection 私有 smartGiftAmount(_:) 手刻「%.1f億／%.1f萬」，與全 App 共用 Double.ntdWanString 邏輯重複，且未處理捨入至萬位上限應進位為億的邊界（會顯示成不合理的「10000.0萬」）。禮金總計 Capsule 徽章、分類金額 Capsule 徽章兩處呼叫點改用共用 Double.ntdWanString，並補上 lineLimit(1) + minimumScaleFactor（對齊 StockView／TaxOverviewView 等同類 Capsule 金額徽章防截斷規格）。順手移除已無呼叫端的私有 smartGiftAmount／formatGiftTotal／currencyFormatter 死碼。純顯示層調整，禮金加總等既有邏輯未變動。"
        ]),
        ChangelogEntry(version: "23.99", build: 655, date: "2026/07/12", notes: [
            "【美化】節稅總覽畫面（TaxOverviewView）金額量級一致性：私有 fmtShort(_:) 手刻「%.1f億／%.1f萬」完全缺少 NT$ 字首，與同頁英雄卡「年度稅費支出」大字（fmt，帶 NT$ 前綴）並排時字首不一致，也未處理 ≥9999.95萬 應進位為億的邊界（會顯示成不合理的「10000.0萬」）。年收入 KPI 膠囊／月份長條金額／節稅彙總膠囊／扣除額已累積徽章共 5 處呼叫點改用共用 Double.ntdWanString，其中節稅彙總膠囊、扣除額已累積徽章原本缺少防截斷規格，一併補上 lineLimit(1) + minimumScaleFactor（對齊同頁年收入膠囊既有規格）。純顯示層調整，稅費加總、節稅累積、扣除額試算等既有邏輯未變動。"
        ]),
        ChangelogEntry(version: "23.98", build: 654, date: "2026/07/12", notes: [
            "【美化】財富總覽信用卡明細卡（LifeFinanceView.FinanceCardView）金額量級一致性：「額度」原本手刻只換算到萬（無條件捨去小數、未處理億級單位）、「年費」原本純整數無量級轉換，與 v23.97 才剛加入、緊接在下方的「本期已用」「可用額度」（已用共用 ntdWanString）風格不一致；「最近一期」加總與信用卡個別支出列同樣是純整數顯示。四處統一改用共用 Double.ntdWanString，消費金額改為「-」+ ntdWanString 拼接（對齊 StockDetailView 損益金額正負號慣例）。純顯示層調整，額度／年費／消費金額等既有試算邏輯未變動。"
        ]),
        ChangelogEntry(version: "23.96", build: 652, date: "2026/07/12", notes: [
            "【美化】股票畫面（StockView）金額量級一致性：summaryHeader 總成本／損益 KPI 膠囊、soldStackPreview 已實現損益膠囊，原本各自呼叫私有 fmtShort(_:)，無 NT$ 字首、萬級無條件捨去小數、也未處理捨入至萬位上限應進位為億的邊界，與同系列 StockDetailView（fmt = ntdWanString，「+NT$1.2萬」）及全 App 共用 Double.ntdWanString 風格不一致，是本檔案唯一未接上共用金額量級格式的地方。三處呼叫改用既有 fmt（= ntdWanString），並為 soldStackPreview 損益膠囊補上 lineLimit(1) + minimumScaleFactor(0.7)（對齊 summaryHeader 損益 KPI 膠囊既有規格，防止字首變長後在窄膠囊內截斷）；移除已無呼叫端的私有 fmtShort 死碼。純顯示層調整，未變動市值／損益／報酬率等既有試算邏輯。",
        ]),
        ChangelogEntry(version: "23.95", build: 651, date: "2026/07/12", notes: [
            "【美化】美食地圖清單畫面（FoodMapView）餐廳詳情 Sheet KPI 列：「總花費」「平均每次」原本各自呼叫私有 fmtWan(_:) 與「NT$ \\(fmtNum(_:))」，「平均每次」未做萬/億量級轉換，金額較大時與同列「總花費」顯示規格不一致；兩處改用共用 Double.ntdWanString（對齊同檔案餐廳清單列已使用的規格），並移除只剩單一呼叫點、與共用元件重複的私有 fmtWan(_:) 死碼。純顯示層調整，造訪聚合、花費加總等既有邏輯未變動。",
        ]),
        ChangelogEntry(version: "23.94", build: 650, date: "2026/07/11", notes: [
            "【靜態除錯 v23.94：修復真實 Bug】本次針對強制解包／Optional／型別／index／retain cycle／競態條件、畫面閃爍、效能瓶頸三大類做多路並行複查（Models + Views 共 83 個檔案），修復 11 處新發現的真實問題：① CloudSyncManager.beginInitialSync()／repromptInitialSync() 原本完全未參照 isSyncing 旗標，使用者快速連點「立即同步」與「重新選擇同步方式」時，兩條 CloudKit 推送流程會並行打同一批 key 造成 serverRecordChanged 衝突；補上 isSyncing 守衛，決策待決期間（pendingInitialSync 顯示中）也維持鎖定，resolveInitialSync／cancelInitialSync 正確歸零。② CloudSyncManager.itemCount() 原本只加總陣列型 KV blob 的元素數，life_profile／life_health_profile 這類單一物件型 blob 恆為 0，導致雲端已有資料時仍被誤判為「雲端沒資料」而跳過覆蓋／合併詢問、靜默把本機資料當種子覆蓋雲端；改為非空物件也計為 1 筆。③ CloudSyncManager 的 flushPushAll()／performSync()／beginInitialSync()／resolveInitialSync() 原本呼叫 pushAllKV()／uploadAllLocalPhotos() 後不等實際完成、也不論成功與否，一律立即呼叫 markSynced() 清空錯誤訊息並推進 lastSyncDate，使失敗的一輪被誤標為已同步、錯誤橫幅不會顯示、30 秒節流延後下次真正重試；CloudKitManager.pushAllKV()／uploadAllLocalPhotos() 補上聚合成功結果的 completion（DispatchGroup），CloudSyncManager 四處呼叫點改為等待完成、只在全部成功時才 markSynced()。④ RealEstateDetailView 的 ElevatorMaintenanceEditor／UtilityPaymentEditor 換照片時沿用記錄自身不變的 id 當檔名（同路徑覆寫），是 v23.93 已修復的同一類 bug在房地產電梯保養／水電瓦斯繳費紀錄的漏網之魚；改為全新 UUID 檔名並於覆寫前刪除舊檔。⑤ 同檔 ThumbnailImageView 的 .task(id:) 沒有在讀取新縮圖前先清空舊圖，即使 url 改變也會在讀取完成前短暫顯示舊縮圖；補上先清空再讀，對齊 AsyncLocalImage 既有規格。⑥ FamilyMembersResumeView.FamilyAlbumPhotoEditor／OrganizationView.OrgPersonEditor／ChildDetailView.recordRow 三處原本用 UIImage(contentsOfFile:)／Data(contentsOf:) 同步讀檔＋解碼直接寫在 body／ViewBuilder 內，前兩者所在 Form 同時有姓名／標題等 TextField，每次按鍵都觸發整個 body 重新求值、跟著同步重讀重解碼照片；第三者則是清單每列都會因任何無關的 @Published 變動重跑同步讀檔。三處均改用既有的 AsyncLocalImage 背景讀取＋依 url 快取。⑦ GradeTitleView.gradeTitleRow 的職等／職稱 TextField 綁定用 first(where:)/firstIndex(where:) 對 lifeStore.gradeTitles 做全陣列線性掃描，每次按鍵在 N 筆部門職等資料下形成 O(n²)；改用 ForEach(enumerated()) 已算好的 index 直接存取（越界時退回原值）。⑧ TravelMapView 地點清單列點擊時，同一個 run loop 內先關閉清單 sheet 又設定另一個 sheet 的 item，可能造成第二張 sheet 顯示失敗或閃爍——這是 FoodMapView 已修復並在程式碼註解中說明過的同型 bug，TravelMapView 沿用同一套 UI 模式時漏了同一處修復；補上相同的 0.25 秒延遲。⑨ LifeFinanceView.linkedCards(for:) 在 milestoneList 每一列銀行帳戶各自對 lifeStore.milestones 做一次 O(n) filter，形成 O(n×m)；改為一次依 linkedBankMilestoneId 分組建表，對齊同檔 allBankBalances() 的批次建表作法。⑩ FinanceCardView.deposits 的過濾邏輯對每筆銀行存款各自呼叫 expenseStore.expenses/incomes.first(where:)，形成 O(bankDeposits × (expenses+incomes))；改為先建 expensesById／incomesById 查表再做 O(1) 查詢。⑪ AddExpenseView.allPlaceSuggestions 的「之前去過」候選對 store.expenses 做全量線性掃描，只有 Apple Maps 查詢那一半走 300ms 防抖，本機歷史那一半每次按鍵都同步全量掃描記帳歷史；改為併入同一個防抖 Task（含分類切換時立即更新），避免打字時的輸入延遲。其餘複查範圍（force unwrap／as!／fatalError、陣列越界守衛、[weak self] 捕捉、@Published 主執行緒隔離）均確認無新問題。",
        ]),
        ChangelogEntry(version: "23.93", build: 649, date: "2026/07/11", notes: [
            "【靜態除錯 v23.93：修復真實 Bug】v23.92 把 8 處清單／輪播縮圖從同步讀檔改成 AsyncThumbnailView／AsyncLocalImage（依 url 以 @State 快取 UIImage、.task(id: url) 背景讀取）後，複查發現「換照片後畫面顯示舊圖」的真實回歸：① BusinessCard／OrgPerson／FamilyAlbumPhoto 三種「編輯既有項目、更換照片」流程原本都以該項目自身不變的 id 當檔名（BusinessCardDetailView.saveAvatarData／BusinessCardEditor.save／OrgPersonEditor.save／FamilyAlbumPhotoEditor.save），刪舊檔後用同一路徑寫入新檔，photoFileName／photoURL 字串完全不變；名片清單、部門成員清單、家庭相簿列均以項目自身穩定 id 當 ForEach identity（換照片不會讓該 row 重新產生），使 AsyncLocalImage／AsyncThumbnailView 的 .task(id: url) 因 url 沒變而完全不會重新觸發，換照片後清單頭像／縮圖停留在舊圖，須離開畫面重進（view 被銷毀重建、@State 歸零）才會更新。修復：四處存檔一律改用全新 UUID 當檔名（對齊 Expense／RenovationPhoto 等既有「每次存檔皆用不重複檔名」規格），確保換照片後 url 必定改變。② 即使 url 改變，AsyncThumbnailView（`guard image == nil`）／AsyncLocalImage（`guard !didLoad`）原本用「是否已讀過一次」的旗標判斷是否要重新讀檔——同一個 view 實例只要曾經讀過一次，之後 .task(id: url) 因 url 改變而重新觸發時仍會被此旗標擋下直接 return，看似修好①仍會顯示舊圖；三處（AsyncThumbnailView／AsyncLocalImage／PhotoLightbox）均改為每次 .task(id: url) 觸發時先清空 image／didLoad 再重讀，讓「url 改變」單純由 .task(id:) 本身的重觸發機制控管，不再疊加一次性旗標誤擋。以上兩處合併才是完整修復；其餘既有 fallback 樣式、照片刪除、資料綁定、CloudKit 30 秒節流／pushAll 2 秒防抖／isSyncing 並行守衛均未變動。",
        ]),
        ChangelogEntry(version: "23.92", build: 648, date: "2026/07/11", notes: [
            "【靜態除錯 v23.92】本次針對強制解包／Optional／型別／index／retain cycle／競態條件、畫面閃爍、效能瓶頸三大類做全面掃描（Models + Views 共 83 個檔案）。前者掃描結果：未發現新的高信心 bug——`try!`／`as!`／未防護的陣列越界／缺 `[weak self]` 等既有規格皆已符合；CloudSyncManager 既有 30 秒節流／2 秒防抖／isSyncing 並行守衛亦確認正常，未做變動。",
            "【效能／畫面閃爍修復】v23.89 修復 MedicalMapView 縮圖同步讀檔阻塞主執行緒問題時，已於檔案內註記其餘 7 個檔案仍殘留同型 UIImage(contentsOfFile:) 同步讀檔；本次優先修復「每次 ScrollView／TabView 重繪或分頁切換都會重新觸發」的清單／輪播類 8 處：TravelMapView.photoThumb（旅遊相簿格狀／橫向縮圖共用）、FoodMapView 就醫地點照片橫向捲動列、FamilyMembersResumeView 相簿橫向捲動縮圖，三處改用共用 AsyncThumbnailView；OrganizationView 部門成員列表頭像、BusinessCardView 名片列表頭像，兩處抽出 avatarPlaceholder／personAvatarPlaceholder 後改用新增的共用 AsyncLocalImage 背景讀取；RealEstateDetailView 支出照片 TabView 瀏覽器、RealEstateDetailView 裝潢照片編輯 TabView（保留原有「找不到照片」與「載入中」兩種狀態的正確區分，避免載入中誤閃一次找不到照片畫面）、RenovationPhotoEditor 逐張瀏覽 TabView，三處改用 AsyncLocalImage。另外 4 處（OrganizationView／FamilyMembersResumeView／BusinessCardView 各自的新增頭像表單預覽、OrganizationView 人員詳情頁大頭卡）僅在表單開啟或進入詳情頁時渲染一次，非隨捲動重複觸發，本次不動，避免為改而改擴大變動範圍。純顯示層調整，各畫面既有的頭像/縮圖 fallback 樣式、照片刪除、資料綁定等既有邏輯未變動。",
        ]),
        ChangelogEntry(version: "23.91", build: 647, date: "2026/07/11", notes: [
            "美化履歷頁新增/編輯里程碑表單（ResumeView.AddMilestoneView）「NT$」金額欄位一致性：薪水／調薪前薪水／調薪後薪水／年費／保費五處金額輸入列原本各自手刻 HStack { Text(\"NT$\") + TextField }（部分甚至擠成單行），是 v23.84 美化購入價格金額量級時留下的下一輪待辦事項。新增共用 currencyField(_:text:) row helper，五處呼叫點統一改用，往後新增金額欄位可直接比照呼叫維持一致樣式。純顯示層重構，未變動任何欄位的資料綁定、驗證或試算邏輯。",
        ]),
        ChangelogEntry(version: "23.90", build: 646, date: "2026/07/11", notes: [
            "美化車輛詳情畫面（VehicleDetailView）補齊與同型閃卡（StockDetailView／RealEstateDetailView）的兩處視覺落差：① 閃卡估值大字（52pt）原本唯獨本檔案缺少 minimumScaleFactor + lineLimit(1) + contentTransition(.numericText())，車輛估值位數較多時有截斷風險、切換車輛時數字為硬切換，補上對齊 StockDetailView 市值大字規格。② infoSection：定期／變動支出兩張卡片原本各自以 isEmpty 整卡隱藏，若車輛兩者皆無記錄，此區塊會完全留白、無任何提示，與 StockDetailView（交易/股利空狀態卡）、RealEstateDetailView（emptySectionRow）等同型詳情頁不一致；新增 emptyExpensesCard，兩份清單皆空時顯示「尚無支出記錄」提示卡。純顯示層調整，未變動車輛估值、支出加總或刪除等既有邏輯。",
        ]),
        ChangelogEntry(version: "23.89", build: 645, date: "2026/07/11", notes: [
            "美化醫療地圖畫面（MedicalMapView）就醫地點詳情 Sheet 照片列（photoRow）縮圖載入：原本在 view body 內以 UIImage(contentsOfFile:) 同步讀檔，每次 ScrollView 重繪都可能阻塞主執行緒，且無載入中狀態，與 v22.28 已修復的 MultiPhotoGallery 縮圖同型問題，是本檔案唯一殘留的同步讀檔縮圖。改共用 MultiPhotoGallery.AsyncThumbnailView（原為 private，開放為 internal 供跨檔案共用）：背景執行緒讀檔＋載入中佔位（漸層底＋icloud 圖示＋文字）＋統一 12pt 圓角縮圖樣式。純顯示層調整，就診紀錄／花費加總等既有邏輯未變動。",
        ]),
        ChangelogEntry(version: "23.88", build: 644, date: "2026/07/11", notes: [
            "美化記帳收入新增/編輯畫面（AddIncomeView）月/年等效收入與年薪估計金額量級：私有 smartCurrency 手刻「%.1f 萬」「%.1f 億」（單位前多一個空白、無 NT$ 字首、恆固定一位小數不會整數化、且未處理捨入至萬位上限應進位為億的邊界），與全 App 共用的 Double.ntdWanString（「NT$1.2萬」無空白、整數不帶小數、億以上自動換算＋捨入邊界防呆）皆不一致，是本檔案唯一未接上共用金額量級格式的地方。改呼叫既有 ntdWanString，移除已無其他呼叫端的 formatCurrency／currencyFormatter 死碼。純顯示層調整，未變動月/年等效收入或年薪估計等既有試算邏輯。",
        ]),
        ChangelogEntry(version: "23.87", build: 643, date: "2026/07/11", notes: [
            "美化美食地圖清單畫面（FoodMapView）金額顯示量級：私有 fmtShort(_:) 只到「萬」量級（無條件捨去小數，未處理億級單位），與同檔案 RestaurantDetailSheet.fmtWan 已於 v3 補上的億級規格、以及全 App 共用的 Double.ntdWanString（萬/億自動切換、保留一位小數）皆不一致，是本檔案唯一未接上共用金額量級格式的地方。統計卡總花費／平均每次、餐廳列總花費／均消四處呼叫改用既有 ntdWanString，移除已無呼叫端的 fmtShort 與其專用 decimalFormatter 死碼。純顯示層調整，未變動花費加總或排序等既有邏輯。",
        ]),
        ChangelogEntry(version: "23.86", build: 642, date: "2026/07/11", notes: [
            "美化不動產詳情畫面（RealEstateDetailView）樓層物件樹／房屋資料集錦空狀態：floorItemsTree 與 renovationPhotosContent 兩處空狀態仍是手刻裸 HStack + Text，垂直 padding 各自為 10pt／6pt，是 v23.78（elevatorContent）修復後全檔案僅剩的兩處未接上共用 emptySectionRow(_:)（tray 圖示 + .caption/.tertiary + 統一 14/9pt padding）的空狀態，與 mortgageItems／paidItems／variableExpenses／elevatorContent 四處不一致。改呼叫既有 emptySectionRow(_:)，至此全檔案六處空狀態視覺統一。純視覺調整，未變動樓層物件或房屋資料集錦的任何既有資料邏輯。",
        ]),
        ChangelogEntry(version: "23.85", build: 641, date: "2026/07/11", notes: [
            "美化財富總覽主畫面（LifeFinanceView）銀行帳戶總餘額顯示：私有 formatTwdShort(_:) 用零小數位的 NumberFormatter 直接對「金額 / 億」「金額 / 萬」四捨五入（例如 1.25 億會被捨入顯示成「NT$ 1 億」，實際少報 25%；4.56 萬顯示成「NT$ 5 萬」），是本頁級距最大的金額顯示誤差，且與全 App 共用的 Double.ntdWanString（億/萬保留一位小數）風格不一致。改呼叫既有 ntdWanString，英雄卡 30pt 大字與導覽列小計兩處同步套用，移除已無呼叫端的 formatTwdShort 死碼。純顯示層調整，未變動銀行餘額換算或加總邏輯。",
        ]),
        ChangelogEntry(version: "23.84", build: 640, date: "2026/07/11", notes: [
            "美化履歷頁新增/編輯里程碑表單（ResumeView.AddMilestoneView）房地產「購入價格」顯示：私有 formatWan(_:) 只到「萬」量級（無條件捨去小數，未處理億級單位，例如 1.2 億的房產會顯示成「12000 萬」），與全 App 共用的 Double.ntdWanString（萬/億自動切換、保留一位小數）不一致，是本表單唯一未接上共用金額量級格式的地方（與 v23.79 AddExpenseView.formatBankBalance 同型問題）。改呼叫既有 ntdWanString，並補上 lineLimit(1) + minimumScaleFactor(0.75) 防止大字截斷；移除已無其他呼叫端的 formatWan 死碼。純顯示層調整，未變動購入價格資料或篩選邏輯。",
        ]),
        ChangelogEntry(version: "23.83", build: 639, date: "2026/07/10", notes: [
            "【靜態除錯 v23.83】本次針對強制解包／Optional／index／retain cycle／競態條件、畫面閃爍、效能瓶頸三大類做全面掃描（Models + Views 共 83 個檔案）。前者掃描結果：未發現新的高信心 bug——`try!`／`as!`／未防護的陣列越界／缺 `[weak self]` 等既有規格皆已符合，本次未做變動。",
            "【效能修復】BackupManager.createSnapshot 自動快照（App 啟動與進背景時觸發）先前在主執行緒同步做 UnifiedExporter.exportJSON（含 `.prettyPrinted`／`.sortedKeys` 全量 JSON 編碼），資料量大時會卡住主執行緒，尤其進背景是系統給的極短執行窗口。改為只在主執行緒用 UnifiedExport.build 組出純 struct 快照（很快），實際 JSONEncoder 編碼搬到既有的背景佇列做，與 FullBackup.export 已採用的模式一致；還原端解碼策略不變（`.iso8601`），格式相容。",
            "【畫面閃爍修復】GradeTitleView 的 deleteDepartment（列表刪除）、DepartmentEditor.deleteSelf（編輯畫面內刪除）、syncReverseLinks（儲存部門時雙向同步其他部門的上下游/同層級關聯）三處迴圈，先前對迴圈內每一筆關聯部門/組織人員/部屬各自呼叫 lifeStore.update()，每呼叫一次就各自觸發 LifeStore 的 didSet → save()（12 個集合全量 JSON 重編碼 + CloudKit 推送節流 + 畫面重繪），刪除或編輯一個有 N 筆關聯的部門會產生 N 次不必要的重複存檔與重繪。新增 LifeStore.withBatch(_:) 比照檔案內既有的 isLoading 批次手法，三處迴圈改用 withBatch 包住，跑完只存檔一次。",
        ]),
        ChangelogEntry(version: "23.82", build: 638, date: "2026/07/10", notes: [
            "【正確性修復】公司組織部門編輯（GradeTitleView.DepartmentEditor）勾選「上游部門」時，只清除同一目標的 downstreamIds，未同步清除 peerIds；而「下游」「同層級」兩個勾選欄位都會正確清除另外兩種關係。若使用者先勾同一部門為「同層級」，之後改勾「上游」，peerIds 會殘留該部門 id，儲存後同一目標會同時出現「上游」與「同層級」兩個互斥徽章，組織圖也會畫出矛盾的上下屬 + 平行連接線。補上 peerIds.remove(d.id)，與另外兩個勾選欄位規格一致。",
            "【正確性修復】部門刪除清除殘留關聯：GradeTitleView.deleteDepartment（列表滑動刪除）於清空其他部門的 upstreamIds／downstreamIds 後，從未清空 peerIds，刪除部門後其他部門的 peerIds 仍留著已刪除部門的 id（dangling reference），組織圖／人數統計可能因此參照到不存在的部門。同檔案 DepartmentEditor.deleteSelf（編輯畫面內刪除）雖有清 peerIds，但少了「有異動才寫回」判斷，等同刪除任一部門就對其餘所有部門無條件呼叫 lifeStore.update（全量 JSON 重編碼 + 觸發 CloudKit 推送節流），即使該部門與被刪對象毫無關聯。兩處統一補齊 peerIds 清除 + 「僅在確實有異動時才 update」判斷。",
        ]),
        ChangelogEntry(version: "23.81", build: 637, date: "2026/07/10", notes: [
            "美化電子發票自動匯入設定畫面（EInvoiceSetupView.CategoryRulesEditorView）關閉按鈕位置：自動分類規則編輯器是純關閉用途的 sheet（無另外的取消/儲存兩顆按鈕），原本唯一的「完成」關閉鈕放在 topBarTrailing（右上），與全 App 同類「純關閉 sheet」既有規格（TalentMatrixView／SubordinateRosterView 兩處，以及本檔案同層的 EInvoiceHistoryView「關閉」鈕）皆放在 topBarLeading（左上）不一致。改為 topBarLeading，對齊全 App「關閉按鈕統一放在視窗左側」規格。純視覺調整，未變動規則新增/刪除/重設等既有邏輯。",
        ]),
        ChangelogEntry(version: "23.80", build: 636, date: "2026/07/10", notes: [
            "美化財富總覽存款編輯表單（LifeFinanceView.DepositEditorSheet）轉帳/沖正帳戶餘額格式：先前 fmtBal 自製 NumberFormatter 手刻「NT$ X萬」（無條件捨去小數，且未處理億級單位，例如 1.2 億的帳戶會顯示成「NT$12000萬」），與全 App 共用的 Double.ntdWanString（「NT$1.2萬」保留一位小數、億以上自動換算為「億」）風格不一致，是本檔案唯一未接上共用金額量級格式的地方（與 v23.79 AddExpenseView.formatBankBalance 同型問題）。改呼叫既有 ntdWanString，「轉入帳戶」選單與「沖正」目前總額顯示對齊全 App 金額規則。純視覺調整，未變動帳戶餘額計算、轉帳或沖正等既有邏輯。",
        ]),
        ChangelogEntry(version: "23.79", build: 635, date: "2026/07/10", notes: [
            "美化記帳新增畫面（AddExpenseView）「扣款目標」選單帳戶餘額格式：先前 formatBankBalance 自製 NumberFormatter 手刻「NT$ 5萬」（NT$ 後多一個空白、且無條件捨去小數，例如 45,000 會被顯示成「NT$ 5萬」遺失小數），與全 App 其餘近 30 處畫面（FinanceOverviewView／RealEstateView／StockView／SavingsInsuranceView 等）共用的 Double.ntdWanString（「NT$1.2萬」無空白、保留一位小數、億以上自動換算）風格不一致，是全檔案唯一未接上共用金額量級格式的地方。改呼叫既有 ntdWanString，與全 App 金額顯示規則對齊。純視覺調整，未變動帳戶餘額加總或扣款目標選擇等既有邏輯。",
        ]),
        ChangelogEntry(version: "23.78", build: 634, date: "2026/07/10", notes: [
            "美化不動產詳情畫面（RealEstateDetailView）電梯保養空狀態：先前電梯保養分頁沒有任何保養記錄時，是全檔案唯一手刻裸 HStack + Text(\"尚無保養記錄\") 的空狀態，同畫面「貸款項目」「已支出項目」「變動支出」三處空狀態都早已改用共用 emptySectionRow(_:)（tray 圖示 + .caption/.tertiary 文字），只有電梯保養這格漏改，垂直留白也和其他三處不一致（6pt vs 9pt），切分頁時視覺會有落差。改呼叫既有 emptySectionRow(\"尚無保養記錄\")，與其餘三處空狀態對齊。純視覺調整，未變動電梯保養記錄新增/編輯/刪除等既有邏輯。",
        ]),
        ChangelogEntry(version: "23.77", build: 633, date: "2026/07/10", notes: [
            "美化日期快選元件（MacaronDatePicker，行事曆／部屬總覽等多處共用）：未選中的馬卡龍粉彩膠囊固定用 opacity(0.22) 疊在系統背景上，深色模式下背景接近純黑，5 種粉彩色會被吃成同一片死黑、幾乎分辨不出顏色差異。改為依 colorScheme 切換不透明度（淺色維持 0.22、深色提高到 0.34），並為膠囊內的日期文字補上 lineLimit(1) + minimumScaleFactor(0.8)，避免小螢幕或放大字體時文字被壓縮換行變形。純視覺調整，未變動日期選取、allowFuture 未來日限制等既有邏輯。",
        ]),
        ChangelogEntry(version: "23.76", build: 632, date: "2026/07/10", notes: [
            "美化健康檔案編輯畫面（HealthProfileEditView）四個子編輯視窗（過敏原／藥物／量測／健檢）：先前這四個 sheet 都是欄位直接平鋪的裸 Form，完全沒有分組標題，與外層清單「4pt 漸層色條 + 圖示 + 標題」的小節樣式落差最大。新增共用 healthEditorSectionHeader(_:icon:color:) 並依外層對應小節主題色分組（過敏 orange／用藥 blue／量測 pink／健檢 purple），量測視窗另拆分「日期」「體重 / 心率」「血壓」三個獨立小節取代原本純字串標題，備註欄統一歸入 secondary 色「備註」小節。純版面調整，未變動任何草稿欄位、儲存/取消邏輯。",
        ]),
        ChangelogEntry(version: "23.75", build: 631, date: "2026/07/10", notes: [
            "美化健康檔案編輯畫面（HealthProfileEditView）「慢性病 / 病史」小節：先前該清單直接輸出裸 Text(c)，是全頁唯一沒有圖示圓的清單列，與同頁「過敏」「用藥」「健檢」三個小節（皆有 36pt 主題色漸層圖示圓）視覺落差明顯，像是漏改的半成品。新增 conditionRow(_:) 補上與其他小節一致的 indigo 主題圖示圓，滑動刪除等既有互動與資料邏輯完全未變動。",
        ]),
        ChangelogEntry(version: "23.74", build: 630, date: "2026/07/10", notes: [
            "美化設定頁（SettingsView）「自訂幣別匯率」區塊：先前此區只有裸 TextField 橫排，沒有任何空狀態說明、也是全頁面唯一停留在初版樣式、從未跟上其他小節視覺規格的區塊。新增尚未設定任何匯率時的緊湊空狀態提示（對齊 HealthProfileEditView.emptyRow 規格），並為每筆匯率列補上 22pt 漸層小圖示圓、比值欄位改用等寬數字對齊，避免多筆匯率上下數字左右跳動。純視覺調整，未變動幣別新增/刪除/換算邏輯。",
        ]),
        ChangelogEntry(version: "23.73", build: 629, date: "2026/07/09", notes: [
            "【效能修復】儲蓄險相關 3 處外幣金額格式化：SavingsInsuranceView.fmt（清單逐筆金額）、AddSavingsInsuranceView.formatCurrency（新增/編輯表單 KPI 預覽，Form 內任何欄位每次按鍵都會重新求值 body）、AddExpenseView.formatBankBalance（扣款帳戶選單逐帳戶餘額）三處皆是外幣金額時就地 `let f = NumberFormatter()` 建立新物件，與已於 FixedExpenseView.formatCurrencyWithCode／FoodMapView 修復的「NumberFormatter 建立成本高，應快取重用」規格不一致。改為比照既有 NSCache&lt;NSString, NumberFormatter&gt;（或單一設定情境下的 static let）快取寫法，避免表單輸入或選單開啟時重複配置格式器。",
            "【靜態複查】RealEstateDetailView／StockDetailView／VehicleDetailView 的 estate／stock／vehicle 計算屬性雖每次存取都對 store 陣列做 first(where:) 線性掃描、且在單一 body 中被引用約 30～150 次，但這三個陣列是使用者自身房產/股票/車輛清單（規模遠小於 AddStockView/LifeFinanceView 先前修復案例中被全量掃描的 expenses 陣列），且這三個畫面本身並非表單、不會隨按鍵重新求值 body，故列為已知但影響可忽略，不比照批次查表方式做大規模改寫，避免為改而改。FullBackup.stamp()／OrganizationView.formattedExportDate() 的 DateFormatter 就地建立僅在使用者手動匯出時各執行一次，同樣影響可忽略予以保留。",
        ]),
        ChangelogEntry(version: "23.72", build: 628, date: "2026/07/09", notes: [
            "【正確性修復】儲蓄險（SavingsInsurance.elapsedPeriods，及 AddSavingsInsuranceView 內同款複製邏輯）：若使用者把到期日設定早於起始日（例如新增/編輯時打錯或调整日期順序，畫面上兩個 DatePicker 並無日期先後檢查），「已繳期數」原本只用 min(elapsedMonths / monthsPerPeriod + 1, totalPeriods) 計算，totalPeriods 在此情況下會正確被夾到 0，但 elapsedMonths 本身可能是負值，min(負值, 0) 仍會回傳負值，導致「已繳期數」變成負數，連帶使「已繳總額」（premiumAmount × elapsedPeriods）變成負數，畫面顯示出如「-119/0 期」與負值總繳金額，並污染 SavingsInsuranceView 的全體加總 KPI。比照同檔案內 RealEstateMortgageItem.elapsedPeriods 已正確使用的 min(max(0, months), totalPeriods) 寫法，補上 max(0, ...) 下限。",
            "【效能修復】財富總覽（LifeFinanceView.DepositEditorSheet 存款/提款/轉帳/沖正編輯表單）：轉帳選單逐一帳戶顯示餘額、以及沖正「目前總額」都是呼叫 bankBalance(for:)，其內部對每一筆銀行存款各自呼叫 expenseStore.expenses.first(where:) 做全量掃描；此表單是 Form，任何欄位（含金額 TextField）每次按鍵都會重新求值 body，導致銀行帳戶越多、每帳戶存款紀錄越多時，是 O(帳戶數 × 存款數 × expenses 全量) 隨每次按鍵重算，與已於 v23.71 修復的 AddStockView.accountBalance() 屬同一種未批次化的全量掃描寫法（本檔案主列表 milestoneList 其實已用 allBankBalances() 批次建表修過，只有這個編輯表單漏改）。改為 body 進入時建立一次 expensesById 查表（O(expenses)），bankBalance/currentBalance 改吃查表結果做 O(1) 查詢，取代原本每次呼叫都重新全量掃描。",
            "【畫面閃爍修復】8 個尚未套用「進場動畫旗標需在 onDisappear 歸零」既有規格的畫面：OverviewView（主畫面總覽，appearedCards「header」／todayCardAppeared／recentListAppeared／categoryListAppeared 共 4 處）、BusinessCardView（heroCardAppeared／cardsAppeared）、LifeFinanceView（headerAppeared／rowsAppeared）、FixedExpenseView（headerAppeared／categoryListAppeared）、IncomeView（headerAppeared／listRowsAppeared）、VariableExpenseView（listRowsAppeared）、LifeRealEstateView（headerAppeared／miniBarAppeared，該檔案的第三個旗標 cityPanelRowsAppeared 先前已修過）、SettingsView（heroCardAppeared）。這些畫面都是透過 MainTabView 分頁 switch／if 分支常駐內容進入（非 sheet），@State 旗標在切到其他分頁時不會重置，只設 true 未搭配 onDisappear 歸零 false，導致使用者切走再切回時，英雄卡／今日卡／分類清單／交易清單等淡入＋位移進場動畫不會再播放（尤以主畫面 OverviewView 影響最廣）。比照全 App 其餘畫面（v22.24／v22.36／v22.39／v22.87／v23.44／v23.71 等）已修復的同型規格，逐一補上 onDisappear 重置。"
        ]),
        ChangelogEntry(version: "23.71", build: 627, date: "2026/07/09", notes: [
            "【正確性修復】NotificationManager：有截止日的重複事件（每天/每週/每月/每年），若事件建立已超過約 61 次重複週期（例如每天重複的事件建立超過 61 天），排程時逐次列舉觸發時間所用的安全上限（61 筆）會被早已過去的次數用完，過濾掉過去時間後變成空陣列，導致這個仍在截止日內、理應繼續提醒的事件從此再也排不到任何通知，且 App 每次啟動的 rescheduleAll() 都是從同一個過去的原始時間重算，不會自行恢復。改為排程前先把列舉起點往前跳到第一個「現在之後」的次數，再從那裡開始列舉，確保 61 筆上限涵蓋到的都是尚未發生的未來次數。",
            "【正確性修復】我的履歷（ResumeView.AddMilestoneView）：編輯既有里程碑或既有家庭成員時，畫面上方「分類」選單仍可自由切換；save() 是依「進入編輯時的分類」各自寫回 editing／editingFamily 兩者之一的既有記錄，若編輯中途切換分類（例如把一筆既有里程碑的分類改成「家庭」），會變成用新 UUID 呼叫 store.add() 建立一筆全新記錄，而原本正在編輯的記錄完全沒有被更新或刪除，形成「多一筆新記錄 + 原記錄的編輯內容不翼而飛」的資料不一致；切到「房地產」分類時儲存則是純粹的 no-op，使用者的編輯內容會被靜默捨棄。修正為編輯既有項目時鎖定分類選單（disabled），分類僅能在新增當下決定。",
            "【效能修復】AddStockView 帳戶選擇器（accountPicker）：accountBalance(for:) 每次呼叫都對 expenseStore.expenses 做全量 filter/first(where:) 掃描，而 accountPicker 是 Form body 的一部分，新增股票時任何欄位每次按鍵都會觸發整個 body 重新求值，導致帳戶餘額對 expenses 反覆全量掃描（O(帳戶數 × expenses) 每次按鍵）。改為批次建表（allAccountBalances()：expensesById／expensesByCardMilestone 各建一次，逐帳戶查表 O(1)），對齊 AddExpenseView.allBankBalances() 既有修復規格。",
            "【畫面閃爍修復】6 個尚未套用「進場動畫旗標需在 onDisappear 歸零」既有規格的畫面：FamilyView（membersAppeared）、ChildrenResumeView（heroAppeared／cardsAppeared）、FamilyMembersResumeView（heroCardAppeared／rowsAppeared）、SpouseResumeView（cardAppeared／milestonesAppeared／expensesAppeared）、ResumeGiftSection（rowsAppeared）、ChartView（heroCardAppeared）。這些畫面都是透過 MainTabView 分頁 switch 常駐內容進入（非 sheet），@State 旗標在切到其他分頁時不會重置，只設 true 未搭配 onDisappear 歸零 false，導致使用者切走再切回時，英雄卡／清單列的淡入＋位移進場動畫不會再播放。比照全 App 其餘畫面（v22.24／v22.36／v22.39／v22.87／v23.44 等）已修復的同型規格，逐一補上 onDisappear 重置。"
        ]),
        ChangelogEntry(version: "23.70", build: 626, date: "2026/07/09", notes: [
            "我的行事曆與部屬總覽頁右上角「＋」改為選單：可選擇新增『我的會議 / 事務』（個人行事曆事件），或『部屬任務 / 會議 / 報告』。新增部屬項目時會先跳選擇部屬清單，選完直接進入對應的編輯畫面。",
            "個人事件編輯器新增預設類型參數（會議 / 事務），從選單新增時直接帶入對應類型。"
        ]),
        ChangelogEntry(version: "23.69", build: 625, date: "2026/07/09", notes: [
            "美化家庭總覽街道圖（FamilyOverviewMap）：先前已把每棟房子（HouseView）的屋身背景改為深色模式相容，但外層街道場景的整體底色仍是寫死的淺草綠漸層，深色模式下這塊「街道底圖」會維持刺眼的亮綠色，與其餘全深色的畫面格格不入。改為依系統色彩模式切換：淺色模式維持原本淺草綠街景，深色模式改用深墨綠模擬夜間街景，讓整個家庭總覽畫面在深色模式下視覺一致。純視覺調整，未變動家庭成員分組、房子排列邏輯或任何既有資料。"
        ]),
        ChangelogEntry(version: "23.68", build: 624, date: "2026/07/09", notes: [
            "美化部門職等畫面（GradeTitleView）的部門編輯器（DepartmentEditor）：先前主畫面（英雄卡／部門列／職等列）已完成美化，但點進「新增部門／編輯部門」的表單卻仍是純文字 Section 標題，風格與主畫面脫節。本次補齊：基本資訊／部門功能／上游／下游／同層級五個區塊 header 升級為與主畫面一致的漸層色條＋圖示標頭，上游／下游／同層級並加入已選數量徽章，方便一眼確認勾選狀態；勾選列（checkRow）選中/未選文字對比加強，並補上切換過場動畫；三處重複的「尚無其他部門可選」提示合併並補上圖示。純視覺調整，未變動部門雙向連結同步、刪除或任何既有儲存邏輯。"
        ]),
        ChangelogEntry(version: "23.67", build: 623, date: "2026/07/09", notes: [
            "美化裝潢照片編輯畫面（RenovationPhotoEditor）：修正先前一次美化留下的視覺重複——「照片」Section 標題原本疊了一組自製的漸層色條＋圖示＋粗體標題＋計數膠囊，但下方 MultiPhotoGallery 元件本身已內建同樣一列（粗體標題＋計數膠囊＋新增按鈕），造成標題與張數重複顯示兩次。改回與 AddExpenseView／FixedExpenseView 相同做法，Section header 僅用純文字「照片」，裝飾交由元件內建 header 負責，消除重複雜訊。另外裝潢照片全螢幕瀏覽（RenovationStackViewer）在沒有照片時的「沒有照片」純文字空狀態，升級為圓形圖示徽章＋文字的直式排版，對齊全 App 空狀態設計語言。純視覺調整，未變動照片儲存、刪除或任何既有商業邏輯。"
        ]),
        ChangelogEntry(version: "23.66", build: 622, date: "2026/07/09", notes: [
            "美化主畫面外殼（MainTabView）AI 語音記帳結果提示卡：圖示從裸 SF Symbol 升級為 32pt 漸層圓徽章（LinearGradient 填色＋stroke 邊框），卡片補上成功綠／失敗橘 accent 色 overlay 邊框與第二層柔化陰影，成功/失敗主題更醒目，對齊全 App 圖示圓與卡片邊框設計語言；記帳成功 toast 的金額顯示改用全 App 共用的萬/億智慧量級格式，取代原本高額時會顯示成長串裸整數（如 NT$ 1200000）的寫法。純視覺調整，未變動語音辨識、AI 解析、記帳寫入或任何既有商業邏輯。"
        ]),
        ChangelogEntry(version: "23.65", build: 621, date: "2026/07/09", notes: [
            "美化管理控制台（AdminConsoleView）：RemoteAdminManager 原本就有 isBusy 狀態旗標（寫入 CloudKit 期間會切 true/false），但畫面先前完全沒有讀取，切換「全功能免費」或「對外顯示人數」門檻時，使用者在網路寫入期間看不到任何進行中提示；新增同步中提示列（ProgressView＋文字，寫入完成後自動淡出消失）與相關 Toggle／按鈕在寫入期間 disabled，避免重複觸發造成重疊寫入。純粹呈現既有狀態旗標，未新增或變動任何遠端讀寫邏輯。"
        ]),
        ChangelogEntry(version: "23.64", build: 620, date: "2026/07/09", notes: [
            "旅遊地圖（TravelMapView）美化：統計英雄卡與地點詳細頁 headerCard 補齊三顆散景裝飾圓＋頂部玻璃光澤覆層與 spring 進場動畫，對齊已完成美化的美食地圖（FoodMapView）娛樂紫姊妹頁規格；地點列行圖示圓補上陰影並新增「最近造訪」膠囊徽章；造訪紀錄列行圖示圓補齊邊框、日期改為膠囊徽章樣式，並加入交錯進場動畫；金額顯示改用全 App 共用的萬/億智慧量級格式，取代原本只到「萬」量級、且在主畫面與詳細頁各自重複維護一份的 fmtShort／NumberFormatter；同行者小卡圖示補上漸層與陰影，姓名文字加入自適應縮放避免截斷。未變動地圖標註、縣市解析、資料聚合或任何既有商業邏輯。"
        ]),
        ChangelogEntry(version: "23.63", build: 619, date: "2026/07/09", notes: [
            "醫療地圖（MedicalMapView）美化：過敏、用藥、健檢、健康里程碑、醫療保障列行加入 36pt 漸層圓形圖示（對齊健康檔案編輯畫面規格），量測趨勢數值改為粉色徽章呈現；金額顯示改用全 App 共用的萬/億智慧量級格式，取代原本只到「萬」量級的重複程式碼；空狀態提示加入圖示；BMI／醫療支出大字數值補上自適應縮放避免截斷；未變動地圖標註、資料聚合或任何既有商業邏輯。"
        ]),
        ChangelogEntry(version: "23.62", build: 618, date: "2026/07/09", notes: [
            "健康檔案編輯畫面（HealthProfileEditView）美化：七個區塊統一改用漸層色條 + 彩色圖示 section header（基本資料/病史/過敏/用藥/量測/健檢/備註各自配色），過敏、用藥、健檢列行加入 36pt 漸層圓形圖示，量測數值改用彩色徽章呈現，五個列表補上空狀態提示列，BMI 數值字級放大並加入自適應縮放避免大字級裝置被截斷；未變動任何草稿寫回、刪除等既有邏輯。"
        ]),
        ChangelogEntry(version: "23.61", build: 617, date: "2026/07/08", notes: [
            "【靜態除錯 v23.61】針對從未被靜態掃描覆蓋過的 LifeModels／AppMode／AddIncomeView 三個檔案複查強制解包／Optional／型別／index 越界、retain cycle／競態條件、UI 閃爍、效能瓶頸與日期邊界，修復一處日期溢位問題：LifeMilestone.creditCardWithdrawalDate（信用卡實際扣款日推算，用於行事曆/存款/帳單月份彙總多處）直接把使用者輸入的繳款日（1～31，未限制上限）指定為 DateComponents.day 再轉換，若繳款日落在天數較少的月份（如小月填 31 日、或 2 月），Calendar.date(from:) 不會回傳 nil，而是靜默溢位到下個月 1 日以後，導致扣款日期與月份彙總跑到錯誤的月份；與先前已修復的 MyCalendarView.annualOccurrence（生日 2/29 溢位）屬同一類日期邊界問題，但此檔案先前未被掃到。改為比照該做法，換算前先查目標月實際天數並將 day 截頂。AppMode（純列舉）、AddIncomeView（金額解析皆有 guard、無強制解包、篩選 milestones 陣列規模小不構成效能問題）複查後未發現問題。",
        ]),
        ChangelogEntry(version: "23.60", build: 616, date: "2026/07/08", notes: [
            "修正部分儲蓄險固定支出卡片不顯示儲蓄險樣式（甘特圖/利率/總支出）：原本只用『正向連結（linkedInsuranceId）＋子分類為儲蓄險』判斷，早期連結遺失或子分類未存到的項目就查不到連結保單而不顯示；改為找不到正向連結時，改用『反向連結』（理財儲蓄險記得自己連到哪筆支出）找回，只要有連結保單就視為儲蓄險。",
            "同步強化編輯畫面：載入儲蓄險欄位（利率/繳費/起訖日）與儲存時，皆改為正向找不到就用反向連結找回既有保單，避免利率帶不出來、以及重新儲存時建立重複保單。"
        ]),
        ChangelogEntry(version: "23.59", build: 615, date: "2026/07/08", notes: [
            "固定支出的儲蓄險預覽卡片新增「甘特圖」繳費進度：一條時間軸從起始日到到期日，填色代表已繳進度、白圓點標示目前位置與百分比；並新增『已繳 / 總期數』、『已繳總支出』、『預計總支出』、『預計結束（到期）日』等統計。",
            "修正版本號未同步：先前多次改版只更新了內建更新紀錄，卻忘了更新 Xcode 專案的 MARKETING_VERSION 與 CURRENT_PROJECT_VERSION，導致 App 實際顯示的版本一直停在舊版；本次起同步更新為 23.59 / build 615，之後每次改版都會一併更新。"
        ]),
        ChangelogEntry(version: "23.58", build: 614, date: "2026/07/08", notes: [
            "【正確性修復】編輯固定支出的儲蓄險時複利年利率帶不出來：利率原本只存在連結的理財儲蓄險中，一旦連結遺失或未建立，編輯畫面就讀不回利率、再儲存還可能被覆寫為 0。改為把利率同步存一份在支出本身（Expense.insuranceRate），編輯載入時以支出自身的利率為主，不再依賴連結的儲蓄險是否存在。",
            "既有已建立的儲蓄險若利率已遺失，請重新填一次利率並儲存即可（之後就會穩定保存）；理財模式的儲蓄險仍會同步維護。"
        ]),
        ChangelogEntry(version: "23.57", build: 613, date: "2026/07/08", notes: [
            "修正儲蓄險利率『看起來消失』：固定支出的儲蓄險，其複利年利率是存在連結的理財儲蓄險中；先前新增的預覽卡片沒有顯示這些欄位，導致點開項目看不到利率、誤以為沒存到。預覽卡片新增「儲蓄險」明細區塊，顯示複利年利率、幣別、繳費週期、起始 / 到期日與期滿預估領回（資料仍可由右上角『編輯』修改）。"
        ]),
        ChangelogEntry(version: "23.56", build: 612, date: "2026/07/08", notes: [
            "固定支出預覽卡片新增「帳單照片」：可直接拍照或從相簿新增帳單 / 收據照片留存，點縮圖可全螢幕檢視、可刪除。照片即時寫回該筆固定支出並持久化（含 iCloud 同步），沿用全 App 共用的多照片元件。"
        ]),
        ChangelogEntry(version: "23.55", build: 611, date: "2026/07/08", notes: [
            "我的行事曆：部屬報告 / 會議 / 任務 / 請假（含未完成會議條目、未完成任務）各列改為可點擊，點開先顯示預覽卡片，右上角「編輯」才進入編輯，與部屬總覽一致。搜尋結果與已完成收合區的項目一併適用。左側勾選圈仍維持原本『點一下切換完成』。",
            "我的行事曆：當日事件列（個人事件、里程碑、系統行事曆事件、生日 / 紀念日）改為點開顯示預覽卡片。個人事件與里程碑可由右上角「編輯」進入編輯；系統行事曆事件提供「在『行事曆』App 開啟」；生日 / 紀念日為唯讀資訊卡。"
        ]),
        ChangelogEntry(version: "23.54", build: 610, date: "2026/07/08", notes: [
            "我的行事曆：移除「未來 30 天里程碑」章節（整個列表卡片不再顯示）。頂部英雄卡的『未來 30 天』統計數字仍保留。",
            "我的行事曆：在當日事項（部屬請假／報告／會議／任務）與下方「未完成會議條目／未完成任務」之間，加入一條帶「未完成待辦」標題的分隔線，讓上下兩組有明確的空間區隔。"
        ]),
        ChangelogEntry(version: "23.53", build: 609, date: "2026/07/08", notes: [
            "【靜態除錯 v23.53】複查 10 個 Finance 視圖檔案，修復一類重複出現的孤兒照片問題與一處效能瓶頸：① AddVehicleView（deleteFixedExpenses／deleteVariableExpenses）、AddRealEstateView（deleteMortgageItems／deletePaidItems／deleteVariableItems，以及賣出損益同步邏輯）、AddStockView（賣出損益同步邏輯）、SavingsInsuranceView（滑動刪除保單）皆以 expenseStore.expenses.removeAll 直接刪除連結支出，繞過 ExpenseStore.delete(_:) 的照片清除邏輯，導致刪除時連結支出的附加照片成為孤兒檔案；改為先收集連結支出 ID 清除照片檔案（或改呼叫 expenseStore.delete(_:)）再移除，對齊 StockDetailView.deleteStock／VehicleView.deleteVehicle 既有修復規格。② RealEstateDetailView.deleteEstate 原本對 6 類巢狀項目（貸款/已支出/變動支出/保險/樓層物件/水電瓦斯）逐類各自呼叫 removeAll（觸發多次 @Published 更新），且未清除連結支出的附加照片；deleteLinkedExpense／UtilityPaymentEditor.deleteRecord 也是直接 removeAll；三處皆改為收集連結支出 ID 後一次批量刪除並清除照片（或改用 expenseStore.delete(_:)），降為單次更新且不再孤兒化照片。③ StockDetailView：sortedTransactions／sortedDividends 原本在各自 section 內被 isEmpty／count／ForEach 重複呼叫 3～4 次重新排序；改為 section 頂端以區域變數算一次。其餘檔案（AddSavingsInsuranceView／HolographicBuildingView／RenovationPhotoEditor／VehicleDetailView）複查後確認先前既有修復仍完整，未發現新增問題。"
        ]),
        ChangelogEntry(version: "23.52", build: 608, date: "2026/07/08", notes: [
            "【靜態除錯 v23.52】針對久未被靜態掃描覆蓋的 8 個 Life 視圖檔案（FamilyOverviewMap／MyCalendarView／OrganizationView／MacaronDatePicker／FoodMapView／SubordinateRosterView／GradeTitleView／LifeOverviewView）逐一複查強制解包／Optional／型別／index／字典重複 key／日期邊界、retain cycle／競態條件、UI 閃爍、效能瓶頸，修復兩項問題：① MacaronDatePicker 的 allowFuture 參數（文件註明「是否允許選未來日期」）宣告後從未在 body 內實際使用，快捷日期鍵（明天/後天）與底部 DatePicker 一律允許選未來日期，若日後呼叫端傳入 allowFuture: false 會靜默失效；改為實際依旗標過濾未來日快捷鍵並以 DatePicker(in: ...Date()) 限制範圍（目前兩處既有呼叫端 MyCalendarView／SubordinateOverviewView 皆用預設值 true，行為不受影響）。② SubordinateRosterView.gridArea 內 rosterRows（對 lifeStore.subordinates 做 filter+sort+Dictionary(grouping:) 分組）被凍結姓名欄與日格內容區塊各自的 ForEach 重新呼叫一次；改為在 gridArea 頂端算一次，經 rosterHScroll(bodyWidth:rows:)／hScrollContent(bodyWidth:rows:) 往下傳參數，對齊全 App「單次計算、消除 body 內重複呼叫」規格。其餘六個檔案複查後確認：無 force unwrap／as!／try!／fatalError；Dictionary(uniqueKeysWithValues:) 僅用於天生不重複的 key（如行事曆日期由 calendar 逐日推算）；既有進場動畫旗標 onAppear/onDisappear 配對正確；各頁昂貴計算皆已算一次後傳參數；CloudKit/防抖等既有機制未受影響；未發現新增問題。"
        ]),
        ChangelogEntry(version: "23.51", build: 607, date: "2026/07/08", notes: [
            "【靜態除錯 v23.51】針對性複查健康檔案／醫療地圖／旅遊地圖三項最新功能（HealthModels／HealthProfileEditView／MedicalMapView／TravelMapView，以及 LifeStore／UnifiedExport 中健康檔案的整合點）：① TravelMapView 空狀態的 emptyIconPulse 進場脈衝旗標缺少 onDisappear 歸零，足跡刪光後再新增地點、空狀態重新出現時脈衝動畫不會再播放；比照 FoodMapView 同名旗標既有規格補上重置。② MedicalMapView.body 內 placeAggregates（內含 Dictionary(grouping:) 聚合）在 isEmpty 判斷、地圖 ForEach、清單排序等處被呼叫 5 次，healthMilestones／insuranceMilestones（filter+sort）也各被呼叫 4 次，今年就診/醫療支出的 medicalExpenses 過濾亦重複執行；改為在 body 頂端各算一次後以參數往下傳給 clinicMapSection／milestoneSection／insuranceSection／summaryCard，對齊 TravelMapView／FoodMapView 既有的「單次計算、消除 body 內重複呼叫」規格。HealthModels、HealthProfileEditView、LifeStore、UnifiedExport 複查後邏輯皆完整（逐欄位容錯解碼、isLoading 批次保護、合併模式僅在本機無資料時填入），未發現新增問題。"
        ]),
        ChangelogEntry(version: "23.50", build: 606, date: "2026/07/08", notes: [
            "【靜態除錯 v23.50】針對性複查 14 個 Models 檔案（AIService／AppleCalendarBridge／EInvoice／EInvoiceClient／EInvoiceSyncManager／FeatureGate／FinanceModels／Income／InvoiceCategorizer／KeychainHelper／NotificationManager／RemoteAdmin／RestaurantSearch／SubscriptionManager），修復兩處尚未套用逐筆容錯解碼慣例的檔案讀取：① EInvoiceSyncManager.loadHistory() 原本整批 try? JSONDecoder().decode([EInvoiceImportRecord].self, ...)，單一筆匯入紀錄損壞會讓整份電子發票匯入歷史消失；② InvoiceCategorizer.load() 原本整批解碼 [CategoryRule]，單一筆規則損壞會讓整份自動分類規則消失。兩者皆改為對齊 LifeStore/ExpenseStore/FinanceStore 既有規格：先試整批解碼，失敗再逐筆解、只跳過損壞元素。其餘 12 個檔案（含 CloudKit/網路請求節流、[weak self]、fatalError 守衛、O(n²) 迴圈）複查後皆已在先前多輪除錯中修復完成，未發現新增問題。"
        ]),
        ChangelogEntry(version: "23.49", build: 605, date: "2026/07/07", notes: [
            "固定支出項目點擊行為調整：點項目改為先顯示預覽卡片（項目名稱、金額、週期、月均換算、起始日期、節稅、扣款目標、備註），右上角「編輯」才進入編輯畫面（原本為直接進編輯），與部屬項目的預覽卡一致。預覽卡即時讀取最新資料，編輯儲存後立即反映。"
        ]),
        ChangelogEntry(version: "23.48", build: 604, date: "2026/07/07", notes: [
            "新功能（階段 3／3）：人生模式新增「醫療地圖」，放在旅遊地圖右邊，核心是「健康狀況總結」。頂部彙整卡顯示 BMI 與分級、最近血壓、服用中藥物數、今年就診次數、下次回診日與今年醫療支出；並可從右上角進入編輯健康檔案。",
            "醫療地圖整合多來源：就醫地圖（醫療變動支出中已附地點者撒點，點針看院所詳情、就診次數/花費與收據照片）、量測趨勢（體重/血壓/心率）、過敏、服用中藥物、健檢紀錄（含下次回診提醒）、健康里程碑（人生里程碑的『健康』分類）與醫療保障（財富里程碑中醫療/意外險）。",
            "新增「健康檔案」編輯畫面：可維護血型、身高、慢性病史、過敏、用藥、量測（體重/血壓/心率）與健檢紀錄；以草稿編輯、按儲存才寫回，資料經 iCloud 同步與完整備份保存。",
            "有醫療支出、健康里程碑或已建立健康檔案時，人生功能列才會出現「醫療地圖」。至此旅遊地圖／健康檔案／醫療地圖三階段功能完成。"
        ]),
        ChangelogEntry(version: "23.47", build: 603, date: "2026/07/07", notes: [
            "新功能（階段 2／3，資料層基礎）：新增「健康檔案」資料模型 HealthProfile（血型、身高、過敏、慢性病史、用藥、體重/血壓/心率時間序列量測、健檢紀錄），並提供 BMI、最近體重/血壓、服用中藥物、下次回診等衍生摘要。所有欄位採逐欄位容錯解碼，避免日後擴充欄位造成整份健康檔案解碼失敗。",
            "健康檔案已完整接入資料層：LifeStore 持久化（key life_health_profile）、清除資料一併重置、iCloud 同步（加入 syncKeys）、以及匯出/匯入與完整備份（UnifiedExport；取代模式覆蓋、合併模式僅在本機無資料時填入以免覆蓋既有）。",
            "此為階段 2，僅建立資料層基礎、尚無畫面；下一階段（醫療地圖）將提供健康檔案編輯與「健康狀況總結」。"
        ]),
        ChangelogEntry(version: "23.46", build: 602, date: "2026/07/07", notes: [
            "新功能（階段 1／3）：人生模式新增「旅遊地圖」，放在美食地圖右邊。資料來源為「娛樂」變動支出中已附地點的紀錄，以「項目名稱＋地址」聚合成去過的地點撒點於地圖，點針看該地點的造訪次數、累計/平均花費、照片集錦、最常同行者與造訪時間軸。",
            "旅遊地圖依台灣縣市分組（自地址推斷縣市，相容『台/臺』寫法），清單頁可看足跡涵蓋哪些縣市、各縣市去過幾個地點；並提供『旅遊相簿』一次瀏覽所有娛樂照片。支援期間篩選（本月～全部）、縣市篩選、依造訪次數/花費/最近排序、只看有照片。",
            "任一娛樂支出附有經緯度時，人生功能列才會出現「旅遊地圖」（與美食地圖同邏輯）。此為醫療地圖／健康檔案大功能的第一階段，後續將接續健康檔案資料模型與醫療地圖。"
        ]),
        ChangelogEntry(version: "23.45", build: 601, date: "2026/07/07", notes: [
            "UI 小步美化：兒女詳情頁（ChildDetailView）頂部英雄卡右側「雙層同心圓」大圖示，原本只有 fill 底色、沒有描邊，是卡片內唯一沒有邊框的圖形元素，與同卡角色/年齡/生日三顆膠囊、外框皆已有的描邊語言不一致；外圈補 stroke(.white.opacity(0.16), 0.75pt)、內圈補 stroke(.white.opacity(0.26), 1pt)，對齊本頁 dailyRow/recordRow 36pt 圖示圓既有的描邊規格。純視覺加強，未變動任何年齡/生日計算或既有功能。"
        ]),
        ChangelogEntry(version: "23.44", build: 600, date: "2026/07/07", notes: [
            "【靜態除錯 v23.44】四組並行掃描分別覆蓋 Models／Views‧Life／Views‧Finance／頂層 Views，找到並修復同一類 UI 閃爍問題：多個空狀態雙層脈衝光環／進場動畫旗標（emptyIconPulse／headerAppeared／cardsAppeared／miniBarAppeared 等）透過 onAppear 內的 DispatchQueue.main.asyncAfter 延遲設為 true，卻未在畫面離開時歸零、也未在下次進入前重置，一旦使用者切換分頁又切回（旗標維持 true），下次進入頁面就不會再有 false→true 的變化，脈衝／進場動畫因而不再播放。依各檔既有姊妹寫法（onDisappear 歸零或 onAppear 開頭先重置）補齊：FamilyView／ResumeView／GradeTitleView／TaxOverviewView（Life）、RealEstateView／StockView／SavingsInsuranceView／VehicleView／FinanceChartView（Finance）、FixedExpenseView／VariableExpenseView／IncomeView（頂層）共 12 個檔案；其中 SavingsInsuranceView／VehicleView 的 miniBarAppeared 原本用不可取消的 asyncAfter 觸發，一併改為可在 onDisappear 取消的 Task（對齊 FinanceOverviewView.miniBarTask 既有規格），避免孤兒延遲在畫面離開後才觸發、寫入已重置的旗標。另外修復 VariableExpenseView／IncomeView 的搜尋 300ms 防抖 Task 未在 onDisappear 取消（對齊 AddExpenseView／ChildDetailView 既有修復）。Models 目錄（CloudSyncManager／CloudKitManager／BackupManager／EInvoiceSyncManager／ExpenseStore／FinanceStore／LifeStore 等 12 個核心檔案）逐一複查強制解包／Optional／index／retain cycle／競態條件／CloudKit 30 秒節流，確認皆已正確處理、無新增問題。"
        ]),
        ChangelogEntry(version: "23.43", build: 599, date: "2026/07/07", notes: [
            "UI 小步美化：ResumeGiftSection（六個履歷頁共用的「收到的禮金」區塊）分類 DisclosureGroup 展開箭頭原本是系統預設灰階樣式，與本區塊粉紅主題色不一致，展開時內容也是直接跳出、沒有過場；新增自訂 AccentChevronDisclosureGroupStyle，箭頭改為粉紅主題色並隨展開狀態以 spring 動畫平滑旋轉 90 度，展開內容補上淡入＋由上滑入的過場動畫。純視覺加強，未變動禮金分組或金額邏輯，展開/收合狀態行為不變。"
        ]),
        ChangelogEntry(version: "23.42", build: 598, date: "2026/07/07", notes: [
            "【靜態除錯 v23.42】三個並行掃描（強制解包／Optional／index／retain cycle／競態條件；UI 閃爍／過度重繪／CloudKit 節流；效能瓶頸／O(n²)／重複 I/O）覆蓋全部 79 個 Swift 檔，找到並修復兩項尚未處理的問題：① StockView 的 activeStocks／soldStocks 原本是即時 filter 的 computed property，被 summaryHeader／activeStocksSectionHeader／allocationMiniBar（含一次全量 sort）／soldStackSection／soldStackPreview 五處各自獨立重新呼叫；而頁面又用 onPreferenceChange 即時追蹤 scrollOffset 驅動整個 body 重繪，導致單純滑動股票列表就會反覆重新掃描/排序 store.stocks 達 7 次以上；改為 body 只計算一次 active／sold 陣列，往下以參數傳給五個子區塊。② SubordinateDetailView 的 MentionText.mentionedIDs／attributed 每次呼叫都重新 filter+sort 全部人員清單，而 mentionedCounts()／mentionedItems 卻在巢狀迴圈中對每位部屬的每筆任務/會議項目/報告各別呼叫一次，形成隨部屬與紀錄數同時增長的重複排序成本；新增 sortedPeople 版本的 mentionedIDs，讓這兩處迴圈改為排序一次、重複傳入。另外修復一項 UI 閃爍問題：③ ChildDetailView 兒童紀錄「接種院所」欄位的過往就醫紀錄本地比對，原本讀取即時 detail 字串、未跟 Apple Maps 搜尋走同一組 300ms 防抖，導致每個按鍵都先讓本地建議跳一次、0.3 秒後網路建議才到又重排一次，等同防抖形同虛設；改為本地比對也改讀防抖後的 clinicDebouncedQuery，兩種來源同步更新。強制解包／Optional／型別／index／retain cycle／競態條件經全面複查未發現新問題（力 unwrap 全無、as! 全無、既有鎖/weak self 防護皆確認正常）。"
        ]),
        ChangelogEntry(version: "23.41", build: 597, date: "2026/07/07", notes: [
            "UI 小步美化：ResumeGiftSection（六個履歷頁共用的「收到的禮金」區塊）giftRow 原本圖示圓直接貼齊卡片左緣，與同頁「總計列 / 分類列」皆已有的漸層側條層級不一致；補上 3pt 粉紅漸層側條，讓總計、分類、單筆禮金三層級一眼可辨識屬於同一組清單。純視覺加強，未變動禮金資料或分類邏輯。"
        ]),
        ChangelogEntry(version: "23.40", build: 596, date: "2026/07/07", notes: [
            "UI 小步美化：ChildDetailView（兒女詳情頁）頂部英雄卡「生日」原本只是純文字＋calendar 圖示、無底色無描邊，與同排「角色 / 年齡」兩顆膠囊質感不一致；改為 Capsule 徽章（白底 12% + 描邊 20%），三顆膠囊形成主要／次要／輔助資訊的漸淡描邊節奏，視覺更統一。純視覺調整，未變動生日資料或年齡計算邏輯。"
        ]),
        ChangelogEntry(version: "23.39", build: 595, date: "2026/07/07", notes: [
            "【靜態除錯 v23.39】修復六項問題：① ChildDetailView 新增兒童紀錄時，選圖／切換素描 Toggle／存檔三處各自用 editing?.id ?? UUID() 產生不同亂數 id 來組素描檔名，導致存下的素描檔名與 ChildRecord.sketchURL 實際推導出的檔名對不上，重新開啟編輯時素描預覽會誤顯示原圖、且每次切換 Toggle 都會留下用不到的孤兒素描檔；改為一律由 photoFileName 推導素描檔名（對齊 sketchURL 的邏輯），三處呼叫點統一。② AddExpenseView 記帳「用餐人員」多選：儲存時以目前家人姓名清單反向 filter 已選集合，若某位成員後續改名或被刪除，舊記錄一旦被重新編輯儲存就會靜默把該用餐人員洗掉、清單顯示也會誤縮成『不指定』；改為保留清單中已找不到的舊名字，僅用目前家人清單決定顯示排序。③ FinanceStore／ExpenseStore 讀取 UserDefaults：整批 JSONDecoder.decode 若因單一筆資料損壞（舊格式／CloudKit 合併壞掉）而失敗，try? 會讓保單/股票/車輛/房地產或記帳/收入整個集合原地保持空值，形同資料整批消失；改用與 LifeStore 相同的逐筆容錯解碼（單筆損壞只跳過該筆），並修復 RealEstate/Stock/Vehicle 內巢狀陣列（貸款分期、繳費紀錄、股票交易/配息、樓層物件、產權文件等）原本用整批 try? 解碼、一樣會被單筆壞資料拖累整批消失的同型風險。④ 八個模型的 savePhoto／saveSketch（房地產電梯/水電瓦斯/裝潢照片、家庭相簿、兒童紀錄、名片、組織人員）在磁碟寫入失敗時仍照樣觸發 CloudKit 上傳並回傳檔名，造成永遠讀不到的孤兒照片參照；補上寫入成功才上傳的守衛（對齊 Expense.savePhoto 既有作法）。⑤ RealEstateDetailView 水電瓦斯歷史紀錄展開：isLatestPayment 對每一筆繳費都重新掃描+排序整個 utilityPayments 三次找各類型最新一筆，形成 O(n²)；改為一次分組取得三個類型最新一筆的 id 集合再查表。⑥ TaxOverviewView.taxByMonth 迴圈仍對同一份支出清單跑 12 次全量 filter；改用 Dictionary(grouping:) 一次分月分組。"
        ]),
        ChangelogEntry(version: "23.38", build: 594, date: "2026/07/07", notes: [
            "UI 小步美化（金額單位一致性）：新增/編輯房地產畫面頂部英雄卡「月租收入」KPI 格，原本直接顯示 NT$ 裸整數（月租偏高時字串偏長），與同排「目前估值 / 增值」兩格已採用的萬/億智慧量級格式不一致；改為與同卡其餘欄位一致，改用萬/億智慧量級顯示。純視覺調整，未變動任何試算或儲存邏輯。"
        ]),
        ChangelogEntry(version: "23.37", build: 593, date: "2026/07/07", notes: [
            "【靜態除錯 v23.37】修復兩個未取消的防抖 Task：MyCalendarView.PersonalEventEditor（地點搜尋）與 ChildDetailView.ChildRecordEditorSheet（診所搜尋）在 300ms 防抖期間關閉表單時，Task 仍會在背景繼續驅動搜尋，補上 onDisappear 取消（對齊 AddExpenseView 既有修復）。同時修復四項效能／閃爍問題：① LifeFinanceView 記帳總覽每一列銀行餘額改為批次建表查詢（O(1)），取代原本每列各自對 expenses/incomes 做全量掃描；連帶把兩個個位補建的 DateFormatter/NumberFormatter 改為快取。② RealEstateDetailView 水電瓦斯區塊的重繪旗標原本被 11 個不相關 sheet（電梯保養、裝潢照片、貸款/已支出項目、樓層物件、文件匯入等）共用，導致每次關閉這些無關表單都強制水電瓦斯子樹重建身分、造成閃爍；改為獨立旗標只給水電瓦斯編輯 sheet 使用。③ OrganizationView 派系關係編輯畫面的可選人員清單改為只算一次，取代原本在每一列關係都重新掃描全部組織人員。④ ChildDetailView 素描模式切換 Toggle 時，改為只在真正需要時才讀取原圖檔案，避免每次切換都做一次不必要的主執行緒磁碟讀取＋JPEG 解碼。⑤ AddExpenseView 貸款筆記自動帶入資產名稱時，改為先比對再賦值，避免打字時每個按鍵都觸發不必要的 @State 重新賦值。"
        ]),
        ChangelogEntry(version: "23.36", build: 592, date: "2026/07/06", notes: [
            "【正確性修復】記帳總覽『最近交易』：原本只把所有收支依日期由新到舊排序取前 5 筆，未過濾未來日期，導致尚未開始的分階段貸款等未來固定支出（日期在未來、數值最大）排到最前，把真正的近期消費擠掉。改為只納入日期 ≤ 今天的已發生紀錄，未來項目不再出現在最近交易。"
        ]),
        ChangelogEntry(version: "23.35", build: 591, date: "2026/07/06", notes: [
            "【正確性修復】房地產每月淨現金流：原本 monthlyMortgage 會把該物件『所有』貸款區段的月付都加總，導致尚未開始（未來才生效）或已繳滿的貸款也被算進當期月付；例如設了『今年～明年』與『明年～後年』兩個區段時，明年才開始的那筆會被提前計入。改為只計入當期實際要繳的貸款（今天 ≥ 起始日且尚未繳滿期數）。",
            "同步影響：物件卡片與詳情頁的『每月淨現金流』、理財總覽的房產現金流彙總、以及列表『月貸』顯示，皆改為只反映當期實際月付；『貸款總額 / 已繳貸款』仍為含全部區段的終生金額，不變。"
        ]),
        ChangelogEntry(version: "23.34", build: 590, date: "2026/07/06", notes: [
            "修正建置失敗：AddExpenseView 的 bankPicker 改用 allBankBalances() 批次建表後，信用卡區塊仍殘留一處舊呼叫 bankBalance(for: bank)（該函式已移除），導致『Cannot find bankBalance in scope』。改為與銀行區塊一致查表 balances[bank.id] ?? 0。"
        ]),
        ChangelogEntry(version: "23.33", build: 589, date: "2026/07/06", notes: [
            "修正建置失敗：CloudKitManager 的 accountStatus 計算屬性誤將存取修飾詞寫在 accessor 內（private set { ... }），Swift 不允許，導致『Expected get/set/willSet/didSet keyword』。改為把 private(set) 標在屬性宣告上、set 保持乾淨；外部只讀、內部可寫的語意與加鎖行為不變。"
        ]),
        ChangelogEntry(version: "23.32", build: 588, date: "2026/07/06", notes: [
            "部屬詳情頁的項目點擊行為對齊部屬總覽：任務 / 會議 / 報告 / 請假 / 優缺點 / 成就 / 改善 / 缺失 / Miss Operation 各列，點擊改為先顯示預覽卡片，右上角『編輯』才進入編輯畫面（原本為直接進編輯）。",
            "預覽卡片（SubordinateItemCard）新增通用記錄卡：支援優點 / 缺點 / 成就 / 改善 / 缺失 / Miss Operation，顯示類型、日期、嚴重度、內容與備註，並可由『編輯』進入對應編輯器。"
        ]),
        ChangelogEntry(version: "23.31", build: 587, date: "2026/07/06", notes: [
            "UI 小步美化（一致性修正）：全 App 共用的縮放照片檢視器 PhotoViewerSheet（AddRealEstateView 物件照片／RealEstateDetailView 房屋資料照片／FamilyMembersResumeView 家人照片皆共用同一元件）「關閉」按鈕原本放在畫面右上角，與全 App「關閉／取消統一置左」的既有慣例不一致；改為移至左上角，「重設縮放」圖示鈕改置右側補位。",
            "同步修正 MultiPhotoGallery.swift 內舊註解：v2 當時誤判 PhotoLightbox 是「唯一的關閉按鈕置右例外」，實際上 PhotoViewerSheet 也是同一慣例的漏網之魚，已於註解中補充說明，方便日後查找。",
            "以上均為純視覺調整，未變動任何照片載入/縮放/刪除邏輯，也未影響其他既有功能。"
        ]),
        ChangelogEntry(version: "23.30", build: 586, date: "2026/07/06", notes: [
            "【穩健性修復】TalentMatrixView.makeAxisContext()：scores／potentialScores 兩處建表原本用 Dictionary(uniqueKeysWithValues:)，若 lifeStore.subordinates 出現重複 id（例如逐筆容錯匯入或合併匯入時的 ID 碰撞）會直接 fatalError，導致打開「人才矩陣」頁面閃退；比照 SubordinateView.sortedSubordinates 既有修復規格，改用 Dictionary(_:uniquingKeysWith:) 容忍重複鍵。",
            "【穩健性修復】CloudKitManager：accountStatus 先前僅將「寫入」移到主執行緒，但 isAvailable 大量在背景 queue（push/pull 序列佇列）上直接讀取，形成跨執行緒讀寫同一屬性的競態條件；改為以 NSLock 保護 getter/setter，讀寫皆加鎖。",
            "【效能修復】OrganizationView：組織樹每個節點（deptTreeNode／departmentCard）原本各自對 departments／orgPeople 全量 filter 找子部門與人員數（O(部門數²) + O(部門數×人數)），部門/人員一多，任何導致本頁重繪的狀態變化都會重複整棵樹的全量掃描；改為進入樹狀繪製前一次建表（childrenByParent／peopleCountByDept／byId），遞迴節點全部改查表 O(1)。",
            "【效能修復】OrgPersonDetailView.giftHistory：原本被 body／giftCard 內累計/列表/計數三處各自呼叫，一次觸發三次全量 filter+字串切分+sort；改由 body 算一次傳入 giftCard(_:)，對齊既有 memberGiftsSection(_ gifts:) 查表傳遞規格。",
            "【效能修復】SpouseResumeView：spouseExpenses／spouseExpenseTotal／spouseGifts 原本在 heroCard／giftSection／expenseSection 各自獨立重複呼叫，單次 render 對 expenseStore.expenses 全量掃描達十次上下；改為 body 算一次（expenses／expenseTotal／gifts）往下傳入三個子視圖。",
            "【效能修復】AddExpenseView.bankPicker：bankBalance(for:) 原本每次呼叫都對 store.expenses 做 first(where:)/filter 全量掃描，而 bankPicker 是 Form body 一部分，金額欄位每次按鍵都會觸發整個 body 重新求值，銀行/信用卡選單因此在打字時反覆全量掃描 expenses；改為 allBankBalances() 一次批次建表（expensesById／expensesByCardMilestone），bankPicker 內查表 O(1)。",
            "【效能修復】BusinessCardView：filteredCards（全量 sort + 多欄位 contains 篩選）原本被 List／groupedByCompany／toolbar 多選按鈕 4 處各自獨立重新計算；改為 body 算一次傳入，groupedByCompany 改為接受參數的函式。",
            "本次為靜態除錯健檢：另檢查 force unwrap／try!／as!／陣列越界／retain cycle，未發現額外問題（既有 CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、StockView 30 秒節流、AppleCalendarBridge 防抖等維持不變）。"
        ]),
        ChangelogEntry(version: "23.29", build: 585, date: "2026/07/06", notes: [
            "UI 小步美化（空狀態 CTA）：子女詳情頁（ChildDetailView）的日常記錄／生涯紀錄兩類分類卡，空白時原本只顯示「尚無記錄」純文字，改為補上與該分類同色系的迷你漸層 CTA『新增』按鈕，可直接點擊新增，對齊家庭成員頁（FamilyView）空狀態 CTA 按鈕的視覺規格與操作直覺性。",
            "消費區塊（連動變動支出、非本頁可手動新增）維持原本純文字空狀態，不套用 CTA 按鈕，避免誤導使用者以為能在此直接新增消費。",
            "以上均為純視覺調整，未變動任何資料邏輯或既有功能。"
        ]),
        ChangelogEntry(version: "23.28", build: 584, date: "2026/07/06", notes: [
            "【效能修復】TalentMatrixView：yDomain／yMid 為 computed property，內部對 members 全體重新呼叫 potentialScore（O(records)）並重算 Y 軸範圍；此 getter 被 4 個象限人數統計 filter 閉包、quadrantLabel、pointColor（散布圖每個點的顏色/文字/背景/邊框共 4 處呼叫點）大量重複讀取，M 位成員單次 render 保守估計觸發 4M 次以上的全量 Y 軸重算，是繼 v23.24 AxisContext 修復 X 軸（主動性）重複掃描後，Y 軸（潛力）仍殘留的同型效能瓶頸。修復方式：AxisContext 新增 potentialScores 字典、yRange、yMid 三個欄位，於 makeAxisContext() 一次算好；quadrantLabel／pointColor／四個象限計數函式／圖表 RuleMark／PointMark／chartYScale／selectNearest 命中測試全部改為透過 ctx 查表（O(1)），對齊既有 proactivity(_:ctx:) 查表模式，全頁 Y 軸計算降為每次 render 1 次。",
            "【效能修復】ChildDetailView.childGiftsSection：v23.27 剛美化過的「收到的禮金」分類列，ForEach(SocialSubCategory.allCases) 內對同一份 gifts 陣列逐分類各自呼叫一次 filter（O(分類數 × n)）；對齊 v23.26 FamilyMembersResumeView.memberGiftsSection 同型修復規格，改為進入 ForEach 前以單一迴圈依 socialSubCategory 一次分桶（O(n)），各分類列改查字典，計算次數由 O(分類數) 降為 1 次全量掃描。",
            "【穩健性修復】LifeStore：init() 與 reloadFromCloud() 的 isLoading 批次保護旗標，原本以手動賦值 isLoading = false 結尾，日後若在 backfillOrgPeopleFromSubordinates() 呼叫與重置之間加入 guard/return 會讓旗標永久卡在 true、save() 從此靜默停擺；比照 v22.66 起其餘 12 處批次保護方法的既有規格，改為 defer { isLoading = false }。",
            "本次為純靜態健檢：另檢查 force unwrap／try!／as!／陣列越界／retain cycle／競態條件，未發現額外問題（既有 CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、StockView 30 秒節流、AppleCalendarBridge 防抖等維持不變）。"
        ]),
        ChangelogEntry(version: "23.27", build: 583, date: "2026/07/06", notes: [
            "UI 小步美化（金額單位）：子女詳情頁（ChildDetailView）的「收到的禮金」總計/分類小計、消費區塊合計、單筆消費金額，原本直接顯示台幣整數（高額時字串偏長），改為與全 App 一致的「萬 / 億」智慧量級顯示，對齊履歷禮金區塊／職涯調薪的顯示規格。",
            "程式碼清理：移除該檔案中從未被呼叫的舊版金額格式化函式與其專用 NumberFormatter（顯示已全面改用共用的萬/億智慧量級字串）。",
            "以上均為純視覺調整，未變動任何禮金/消費篩選或加總邏輯，也未影響其他既有功能。"
        ]),
        ChangelogEntry(version: "23.26", build: 582, date: "2026/07/06", notes: [
            "【正確性修復】SubscriptionManager.refreshStatus()：判斷「保留到期日最晚的訂閱」時，原本用單一複合條件 if let existingExp = foundExp, let newExp = transaction.expirationDate 當作唯一分支，只要本筆 entitlement 剛好沒有 expirationDate，就會誤判成「還沒找到過」而把已經找到的合法訂閱洗成 nil；改為先判斷是否為第一筆命中，再判斷是否要用更晚到期日取代，避免這種情況下把使用者誤判為未訂閱。",
            "【效能修復】SubordinateDetailView：mentionedItems（對全部部屬 tasks/meetings/reports 做全量 @ 標註掃描）在單次 render 中被 tab 徽章、分數看板 x2、KPI 統計、mentionedSection 共呼叫 5 次；改為在 body 頂端算一次快取，headerCard／mentionedSection 皆改為接受參數，降為 1 次。",
            "【效能修復】CareerView：careerMilestones 對 store.milestones 的 filter+sort，以及其 6 個衍生統計值（currentCompany／currentPosition／totalCompanies／yearsAtCurrentCompany／subCounts／filtered），原本由 dashboardSection／subCategoryBreakdown／milestoneListSection 各自獨立重算，單頁合計約 10 次重複掃描；改為新增 CareerStats 並在 body 頂端算一次，三個 section 全部改為接受參數。",
            "【效能修復】FamilyMemberDetailView：memberGiftsSection 內對 8 個禮金子分類各自重新 filter 一次（O(分類數 × n)），且 memberGifts 本身（雙重 filter + sort）在 body 與 section 內合計被存取約 10 次；改為 body 頂端算一次快照，並在 memberGiftsSection 內一次性分桶（維持原本「無子分類項目不歸類」的既有行為），降為 O(n)。",
            "本次為純靜態健檢：檢查 force unwrap／try!／陣列越界／retain cycle／競態條件／CloudKit 節流／畫面重複重繪，除上述 4 處外未發現新增問題（既有 StockView 30 秒節流、CloudSyncManager 30 秒節流、AppleCalendarBridge 防抖等維持不變）。"
        ]),
        ChangelogEntry(version: "23.25", build: 581, date: "2026/07/06", notes: [
            "UI 小步美化（一致性）：多個履歷頁共用的「收到的禮金」區塊（ResumeGiftSection，用於配偶／子女／部屬等 6 個履歷頁）——單筆禮金列 28pt 圖示圓補上細邊框，統一同區塊已有描邊的總計圓與分類圓；新增交錯淡入進場動畫，與全 App 其他列表列一致。",
            "UI 小步美化（大字自適應）：同區塊三處金額文字補上自動縮小（最小縮至 65%）且不換行，家族禮金總額換算到「億」量級的長字串時可自動縮小顯示、不會被裁切，也不會小到無法辨識。",
            "程式碼清理：移除該檔案中從未被呼叫的舊版金額格式化函式（顯示已全面改用萬/億智慧量級字串）。",
            "以上均為純視覺調整，未變動任何資料邏輯或既有功能。"
        ]),
        ChangelogEntry(version: "23.24", build: 580, date: "2026/07/06", notes: [
            "【效能修復】SubordinateView：頂部統計卡（summaryStatsCard）以 subordinates.map 對每位部屬呼叫 subordinateScore，且每一列 subordinateRow 也各自呼叫一次；兩者都會讀取 mentionCounts 計算屬性，而該屬性每次被存取都重新呼叫 lifeStore.mentionedCounts()（對全部部屬的任務/會議/報告做 O(N×M) 全量 @ 標註掃描）。N 位部屬的畫面單次 render 因此觸發約 2N 次全量掃描。改為在 body 頂端以 let mentionCounts = lifeStore.mentionedCounts() 算一次，summaryStatsCard / subordinateSections / listRow / subordinateRow / subordinateScore 全部改為接受此字典的參數，全頁降為 1 次全量掃描。",
            "【效能修復】TalentMatrixView（人才矩陣）：proactivity(_:) 同樣每次呼叫都讀取會重新計算 lifeStore.mentionedCounts() 的計算屬性，而此函式被散布圖座標、四象限人數統計（各自呼叫一次共 4 次）、圖表點位、命中測試、明細卡等十餘處呼叫點使用，M 位成員的單次 render 保守估計觸發 5M 次以上全量掃描，是本次發現中最嚴重的一處。改為新增 AxisContext（含分數字典 + X 軸中位數，由 body / exportJPG 匯出流程各自算一次），summaryHeroCard / chart / quadrantLegend / breakdownCard 等改為接受 ctx 參數，全頁降為 1 次全量掃描。",
            "本次為純靜態健檢，聚焦近期新增的 @ 標註 / 人才矩陣功能：另檢查 force unwrap／陣列越界／retain cycle／競態條件／CloudKit 30 秒節流／pushAll 2 秒防抖，未發現額外問題。"
        ]),
        ChangelogEntry(version: "23.23", build: 579, date: "2026/07/06", notes: [
            "UI 小步美化（一致性）：餐廳清單（FoodMapView）與名片 QR Code 全螢幕（BusinessCardView）的「關閉」按鈕，從右上角改到左上角，統一全 App「關閉／取消」一律置左的慣例。",
            "UI 小步美化（金額單位）：職涯履歷「薪資調整」的調薪前後金額，原本直接顯示台幣整數（高薪資時字串偏長），改為與全 App 一致的「萬 / 億」智慧量級顯示。",
            "以上均為純視覺調整，未變動任何資料邏輯或既有功能。"
        ]),
        ChangelogEntry(version: "23.22", build: 578, date: "2026/07/06", notes: [
            "【效能/閃爍修復】StockView 開啟頁面即打網路更新股價且無節流：切換理財子分頁再切回會整個重建 View，@State 無法擋下重複請求；加入 30 秒節流（比照 CloudSyncManager 既有節流秒數），改善頻繁切換分頁造成的重複網路請求與『更新報價中』橫幅閃爍。",
            "【閃爍修復】AppleCalendarBridge：EKEventStoreChanged 對同一次使用者操作常連續觸發多次（iOS 已知行為），原本每次都直接更新 lastChange 觸發 MyCalendarView 整頁重繪；加入 0.3 秒防抖合併。",
            "【效能修復】LifeFinanceView.body：allBankBalanceInTWD（含固定支出/信用卡分期展開，O(n×1200)）被 toolbar 與 summaryHeader 各自獨立計算共 3 次；改為 body 頂端算一次後傳入，降為 1 次。",
            "【效能修復】TaxOverviewView：節稅子分類的直接/固定支出金額原本由 taxSavingDirectTotal / taxSavingFromFixedTotal / taxSavingTotal 對每個子分類各自重新 filter 全部支出（10 個子分類 × 最多 4 次 O(n) 掃描 ≈ 40 次）；改為一次分桶計算的 taxSavingBySub 字典，body 算一次後傳入各 section，降為固定 2 次全量掃描。",
            "【穩健性修復】LifeStore：toggleTaskCompletion / toggleMeetingItemCompletion / toggleWeeklyReportCompletion / setShift / applyNightShiftRotation / applyEveningShiftWeekdays / deleteOrgPerson / deleteBusinessCard / clearAll 的 isLoading 批次保護旗標，補上 defer 重置（原本以手動賦值 isLoading = false 結尾，日後若在中間加入 guard/return 會讓旗標永久卡在 true、save() 從此停擺且不易察覺）。",
            "【正確性修復】RemoteAdmin：writeConfig / incrementUserCount 原本忽略 CloudKit fetch 的錯誤，把任何 fetch 失敗（含網路中斷等暫時性錯誤）都當成『查無此筆』直接建立無 change tag 的全新 record 寫入，可能覆蓋或衝突伺服器既有版本；比照 CloudKitManager.modifyKV 既有作法，非『查無此筆』的真錯誤直接中止並回報，不再嘗試寫入。",
            "本次為純靜態健檢：另檢查了 force unwrap／陣列越界／retain cycle／競態條件，未發現額外問題（詳見程式內註解與此前多輪稽核紀錄）。"
        ]),
        ChangelogEntry(version: "23.21", build: 577, date: "2026/07/05", notes: [
            "修正建置失敗：TalentMatrixView 的 proactivity(_:) 輔助方法誤寫成遞迴呼叫自己再帶參數（proactivity(m)(mentionedCount:)），導致『Cannot call value of non-function type Int』。改為正確呼叫模型方法 m.proactivityScore(mentionedCount:)。"
        ]),
        ChangelogEntry(version: "23.20", build: 576, date: "2026/07/05", notes: [
            "美化多照片廊（MultiPhotoGallery）：全螢幕看照片的關閉按鈕改到左上角，與全 App「關閉／取消」統一放左側的慣例一致。",
            "看照片時圖片改為淡入顯示，不再從讀取中直接跳成圖片；點縮圖新增輕量按下縮放回饋。"
        ]),
        ChangelogEntry(version: "23.19", build: 575, date: "2026/06/29", notes: [
            "強化匯入容錯：部屬的任務/會議/報告/班表/紀錄改為『逐筆容錯解碼』，單一壞紀錄只跳過該筆，不再整個陣列一起消失（改善匯入完整資料時部屬任務等未被帶入的問題）。",
            "部屬姓名/職稱/部門/備註缺欄位時不再讓整筆部屬解碼失敗。"
        ]),
        ChangelogEntry(version: "23.18", build: 574, date: "2026/06/29", notes: [
            "部屬卡片頂部看板新增第二列統計：報告 / 會議 / 任務 / 被標註 / 請假。",
            "被標註的項目併入主動性分數計算（每被標註一項 +2），人才矩陣、部屬列表、部屬卡片分數同步。"
        ]),
        ChangelogEntry(version: "23.17", build: 573, date: "2026/06/29", notes: [
            "人才矩陣右上角新增『匯出 JPG』，可將整頁（摘要+散布圖+圖例）匯出分享。",
            "人才矩陣單位選別改為多選並記住設定（下次開啟維持），可同時檢視多個部門。"
        ]),
        ChangelogEntry(version: "23.16", build: 572, date: "2026/06/29", notes: [
            "部屬卡片任務下方新增『被標註的項目』：列出其他部屬的任務/會議/報告中 @ 標註到本人的項目，點擊開預覽卡。",
            "部屬卡片頂部看板重新規劃：改為並排顯示『主動性 / 潛力性 / 綜合』三個分數。"
        ]),
        ChangelogEntry(version: "23.15", build: 571, date: "2026/06/29", notes: [
            "@ 標註改為只在文字中存『@名字』，輸入框不再顯示整串連結代碼；顯示時再依名字解析為藍色可點連結。",
            "預覽卡片改為即時讀取最新資料，編輯儲存後立即更新（不需重新開啟）。"
        ]),
        ChangelogEntry(version: "23.14", build: 570, date: "2026/06/29", notes: [
            "部屬總覽點項目改為先顯示預覽卡片，右上角『編輯』才進入編輯（任務/會議/報告/請假）。",
            "任務/會議/報告的內容與備註欄位新增 @ 標註：打 @ 或 @關鍵字可從名片與部屬中選人，存成連結。",
            "預覽卡片中的 @ 標註為可點連結，點擊即開啟該人員的部屬卡片或名片。"
        ]),
        ChangelogEntry(version: "23.13", build: 569, date: "2026/06/29", notes: [
            "開啟部屬班表時自動水平捲動，將今天置中顯示，不必再從 1 號往左滑。"
        ]),
        ChangelogEntry(version: "23.12", build: 568, date: "2026/06/29", notes: [
            "編輯任務新增『指派給』人員選單，可把任務移交給其他部屬。",
            "部屬班表快速新增請假：日期預設帶入所點格子的日期，時間預設 08:30–17:30。",
            "班別時間設定新增休息時間（日值班 12:00–13:00、小夜班 17:30–18:30，可自訂）；請假時數會自動扣除與休息時段重疊的時間。"
        ]),
        ChangelogEntry(version: "23.11", build: 567, date: "2026/06/29", notes: [
            "修正建置失敗：SubordinateView 的 onChange 改為觀察部門 id 陣列（[UUID]），避免要求 Department 遵從 Equatable。"
        ]),
        ChangelogEntry(version: "23.10", build: 566, date: "2026/06/29", notes: [
            "修正建置失敗：① ChangelogListView 誤用 Color.separator（應為 Color(.separator)）導致型別不符；② SubordinateView 工具列表達式過大，抽出 toolbarContent 與 sortMenu 子視圖以通過型別檢查。"
        ]),
        ChangelogEntry(version: "23.09", build: 565, date: "2026/06/29", notes: [
            "修正建置失敗（兩個型別檢查逾時錯誤）：將 SubordinateView 的清單內容（部門篩選 / 廠區分組 / 列表）拆分為 subordinateSections、listRow 子視圖；將 ChangelogListView 的版本列與標題拆分為 changelogRow、changelogHeader 子視圖。"
        ]),
        ChangelogEntry(version: "23.07", build: 564, date: "2026/06/29", notes: [
            "【靜態除錯 v23.07 / build 564】修復六個空狀態脈衝動畫旗標未在 onAppear 重置的問題。根本原因：DispatchQueue.main.asyncAfter 排定的 block 可能在 onDisappear 之後才觸發（例如使用者在延遲時間內快速切換頁籤），導致 emptyIconPulse / orgEmptyPulse 被設為 true 後停留不歸零；下次進入頁面時旗標已為 true，.animation(.repeatForever, value:) 等不到 false→true 轉換，脈衝圓停在展開/淡出的終止狀態（opacity 0、scale 放大），空狀態圖示旁的呼吸動畫消失。修復方式：在每個 onAppear 閉包內的 asyncAfter 呼叫之前先將旗標重置為 false，確保每次進場均能觸發完整的 false→true 動畫轉換，對齊既有 LifeOverviewView.emptyMilestonePulse / CareerView / FoodMapView / SubordinateRosterView 以 onDisappear 歸零的正確規格。受影響檔案：① SubordinateView（emptyIconPulse）② OrganizationView（orgEmptyPulse）③ LifeRealEstateView（emptyIconPulse）④ SpouseResumeView（emptyIconPulse）⑤ ChildrenResumeView（emptyIconPulse）⑥ BusinessCardView（emptyIconPulse，僅非搜尋分支）。其餘：無 force unwrap（!）、無 as! 強制轉型；CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、@Published 主執行緒隔離均正常。"
        ]),
        ChangelogEntry(version: "23.06", build: 563, date: "2026/06/29", notes: [
            "【靜態除錯 v23.06 / build 563】修復三項問題：① StockView.deleteStock()：context menu 及 swipeActions 觸發的刪除路徑以 expenseStore.expenses.removeAll { $0.id == expId } 直接移除連結支出，繞過 ExpenseStore.delete(_:) 的照片清除邏輯（for name in expense.photoFileNames { Expense.deletePhoto(name) }），導致刪除股票時連結支出的附件照片成為孤兒檔案；改為先以 expenses.first(where:) 找到支出物件再呼叫 expenseStore.delete(exp)，對齊 v22.97 StockDetailView.deleteStock() 及 v23.02 VehicleView.deleteVehicle 同型修復規格，維持單次 @Published 更新。② FinanceOverviewView totalAssetsCard mini 彩條動畫：onAppear 以 DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) 排定 miniBarAppeared = true，但 onDisappear 只重置旗標、未取消排定中的 block；使用者快速切換頁籤時（< 0.45s 後返回），孤兒 block 在 onDisappear 重置後才觸發，將 miniBarAppeared 設為 true，導致下次進入頁面時彩條跳過 spring 展開動畫直接出現；改為以 @State private var miniBarTask: Task<Void, Never>? 取代 DispatchQueue.main.asyncAfter，onDisappear 補入 miniBarTask?.cancel() + miniBarTask = nil，確保每次進場都能完整播放彩條展開動畫。③ AddExpenseView completerDebounceTask 未取消：onChange(of: title) 以 300ms 防抖 Task 送出餐廳搜尋查詢，但 NavigationStack 本身無 onDisappear 取消此 Task；使用者在 300ms 內關閉表單，Task 繼續執行並更新已離開的 view 的狀態（restaurantCompleter.queryFragment = newValue），造成不必要的 MKLocalSearchCompleter 查詢；在 NavigationStack 末尾補入 .onDisappear { completerDebounceTask?.cancel() }，確保表單關閉時立即中止進行中的搜尋防抖。其餘：無 force unwrap（!）、無 as! 強制轉型；CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、@Published 主執行緒隔離均正常。"
        ]),
        ChangelogEntry(version: "23.04", build: 562, date: "2026/06/29", notes: [
            "【靜態除錯 v23.04 / build 562】修復五項問題：① StockView.refreshAllPrices() / FinanceStore 新增 batchUpdateStockPrices(_:)：刷新 N 筆股票報價時，原本逐筆 stocks[idx].currentPrice = price 觸發 N 次 @Published 串聯更新（N 次畫面重繪 + N 次 JSON 序列化 + N 次 UserDefaults 寫入）；改為先將所有報價蒐集至 [UUID: Double] 字典，再以 stocks = updated 單次整體替換陣列，降為 1 次重繪 / 1 次序列化 / 1 次推送，對齊 v23.00 VehicleView 批次刪除同型修復規格。② StockDetailView.flashCard 雙重動畫：.animation(…, value: cardAppeared) modifier 與 onAppear { withAnimation(…) { cardAppeared = true } } 同時對同一狀態旗標套用兩個動畫上下文，造成進場動畫重複計算；移除 withAnimation wrapper，僅保留 .animation modifier，改為 onAppear { cardAppeared = true }，統一動畫來源。③ ExpenseStore.weeklyData()：O(n×12) 內層迴圈與方法頂部注釋「再 O(n) 掃描」不符；改用「calendar.dateComponents([.day], from: cutoff, to: eDay).day 除以 7」直接計算週索引（真正 O(n)），消除內層 for-in weekRanges 迴圈。④ CloudKitManager.modifyKV()：暫存檔名含 UUID().uuidString，若行程在寫入後、modifyRecordsResultBlock 清除前被系統 kill，每次上傳相同 key 均會殘留一個孤兒 JSON 檔；改為確定性檔名 kv_<key>.json，後續上傳自動覆寫，消除累積孤兒檔風險。⑤ BackupManager.createSnapshot()：兩處 Date() 呼叫（ts = Int(Date()) 在主執行緒，lastSnapshotDate = Date() 在背景 queue 的 main.async 裡）可能因執行緒切換產生微小落差，導致 availableSnapshots() 解析的檔名日期比 lastSnapshotDate 略早；改為在函式頂部捕捉 let now = Date() 並統一使用，確保檔名時間戳與 lastSnapshotDate 完全一致。"
        ]),
        ChangelogEntry(version: "23.02", build: 560, date: "2026/06/29", notes: [
            "【靜態除錯 v23.02 / build 560】修復三項問題：① VehicleView.deleteVehicle（swipeActions）及 VehicleDetailView.deleteVehicle：v23.00 批次刪除修復僅解決 N 次 @Published 更新問題，但仍直接呼叫 expenseStore.expenses.removeAll { linkedIds.contains($0.id) }，繞過 ExpenseStore.delete(_:) 的照片清除路徑，導致刪除車輛時所有連結支出的附件照片（photoFileNames）成為孤兒檔案；兩處均補入 for exp in expenseStore.expenses where linkedIds.contains(exp.id) { for name in exp.photoFileNames { Expense.deletePhoto(name) } } 循環於 removeAll 之前，對齊 v22.97 StockDetailView.deleteStock() 同型修復規格，維持單次 @Published 更新。② ChildrenResumeView.childCard 圖示圓（v3 美化引入）：Icon systemName 以 isSon ? \"figure.child\" : \"figure.child\" 設定，兩個分支相同，女兒卡片顯示與兒子相同的圖示；修正為 isSon ? \"figure.child\" : \"figure.child.and.lock\"，對齊同檔 heroKpiCell 女兒分支使用 figure.child.and.lock 的規格，消除死碼三元運算子。其餘：無 force unwrap（!）、無 as! 強制轉型；CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、@Published 主執行緒隔離均正常。"
        ]),
        ChangelogEntry(version: "23.00", build: 558, date: "2026/06/28", notes: [
            "【靜態除錯 v23.00 / build 558】修復四項問題：① SubordinateView.sortedSubordinates：indexMap 與 deptCache 均以 Dictionary(uniqueKeysWithValues:) 建立，當部屬 ID 或部門 ID 因資料損壞出現重複時會觸發 fatalError 崩潰；改用 Dictionary(_:uniquingKeysWith:) { first, _ in first } 於重複鍵時保留首個值，消除崩潰風險。② SubordinateView.summaryStatsCard：同一次 body 求值中呼叫 subordinateScore() 三次（averageScore 一次、excellentCount 一次、「待提升」inline filter 一次），subordinateScore 對每位部屬掃描 records/meetings/tasks（O(n×m)），三次各自獨立遍歷造成無謂重複；改為在 summaryStatsCard 頂部以 let scores = subordinates.map { subordinateScore($0) } 一次計算全員分數陣列，avg/excellent/needImprovement 直接從 scores 取值（O(1)），計算次數由 3 降為 1；移除已無呼叫者的 averageScore 與 excellentCount 計算屬性，對齊 v22.99 SubordinateDetailView / v22.91 SubordinateOverviewView 同型修復規格。③ VariableExpenseView.todayVariableTotal：每次 body render 均以 Calendar.current.isDateInToday 對全部 variableExpenses 掃描（O(n)），任何 store 或 @AppStorage 更新均觸發重算；改為納入既有 .task(id: store.modifyID) 區塊一次計算，存入 @State private var cachedTodayVariableTotal，屬性改為直接回傳快取值，對齊既有 cachedTrailingMonthlyAvg 快取規格。④ VehicleView 刪除車輛：每筆連結支出各別呼叫 expenseStore.expenses.removeAll { $0.id == linkedId }，N 筆連結支出觸發 N 次 @Published 更新、N 次磁碟寫入、N 次 CloudKit pushAll；改為先收集所有 linkedId 至 Set<UUID>，再以單次 removeAll { linkedIds.contains($0.id) } 批量刪除，降為 1 次更新 / 1 次寫入 / 1 次推送。其餘：無 force unwrap（!）、無 as! 強制轉型；CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、@Published 主執行緒隔離均正常。"
        ]),
        ChangelogEntry(version: "22.99", build: 557, date: "2026/06/28", notes: [
            "【靜態除錯 v22.99 / build 557】修復 SubordinateDetailView v3（build 556 最新美化）引入的效能瓶頸：headerCard 的 KPI 橫列呼叫 countFor([.pro/con/achievement/missOperation/leave]) 共 5 次，每次均對 subordinate.records 執行 O(n) filter；每次 body render 共掃描 records 陣列 5 遍。修復方式：在 headerCard 頂部以 let recordCounts = subordinate.records.reduce(into:[SubordinateRecordType:Int]()) 一次計算所有類型計數（O(n)），5 個 statBadge 改為查字典（O(1)），並移除已無呼叫者的 countFor 方法。計算次數由 5 降為 1，對齊 v22.93 LifeRealEstateView.propertiesByCity / v22.91 SubordinateOverviewView.todayLeaves/todayMeetings/incompleteTasks 同型效能修復規格。其餘：無 force unwrap（!）、無 as! 強制轉型、無 fatalError（EInvoiceClient 啟動守衛除外）；CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、@Published 主執行緒隔離均正常。"
        ]),
        ChangelogEntry(version: "22.97", build: 556, date: "2026/06/28", notes: [
            "【靜態除錯 v22.97 / build 556】修復四項靜態層級問題：① StockDetailView.deleteStock()：直接以 removeAll 刪除連結支出時不會執行 Expense.deletePhoto()，導致照片檔案孤兒化；改用 expenseStore.delete(exp) 與 expenseStore.deleteIncome(inc)，確保照片清除與持久化均走 Store CRUD 路徑。② StockDetailView.syncCashDividendIncome / removeCashDividendIncome：直接讀寫 expenseStore.incomes 陣列，繞過 ExpenseStore 的 CRUD 方法；改用 expenseStore.update(_:) / expenseStore.add(_:) / expenseStore.deleteIncome(_:)，統一持久化入口。③ LifeStore add/update/deleteSubordinate：isLoading = true … isLoading = false 之間若未來加入 guard/return，isLoading 將永久卡死為 true，導致所有後續 save() 被靜默抑制；加入 defer { isLoading = false } 防止此類潛在卡死。④ FinanceOverviewView.rateForCode：每次呼叫對 currencyRates 做線性掃描，insuranceValueNTD 與 insurancePaidNTD 各對 N 筆保單逐一查詢，總複雜度 O(N×M)；改為在各屬性內以 reduce(into:) 預建字典（O(M)），後續 N 次查詢降為 O(1)，整體降至 O(N+M)。"
        ]),
        ChangelogEntry(version: "22.95", build: 555, date: "2026/06/28", notes: [
            "【UI 美化】StockDetailView v3：① flashCard 背景升級為三顆散景裝飾圓（opacity 0.07/0.05/0.04, blur 15/12/9）+ 頂部→中央玻璃光澤覆層（LinearGradient [.white.opacity(0.18), .clear]），對齊全 App 英雄卡視覺規格。② 新增 cardAppeared spring 進場動畫（response:0.50/dampingFraction:0.78, delay:0.04）：透明度 0→1 + Y 位移 14→0，對齊 SavingsInsuranceView 閃卡進場規格。③ 市值大字（52pt）加入 minimumScaleFactor(0.55) + lineLimit(1) + contentTransition(.numericText())，防長數字溢出並對齊全 App 數值縮放規格。④ 損益膠囊補入 Capsule().stroke(color.opacity(0.22), 0.6pt)，對齊全 App 膠囊細邊框設計語言。⑤ 購入日期 / 賣出日期升級為 tertiarySystemFill Capsule 徽章（+ separator stroke 0.6pt），對齊 CareerView v2 / OverviewView.recentRow 日期規格。⑥ accountSection 圖示圓：38pt → 44pt + Circle().stroke(color.opacity(0.18), 0.75pt)，對齊 StockView.stockCard / VehicleView v3 圖示圓規格。⑦ noteCard Capsule 側條高度 16 → 20，對齊全 App sectionHeader Capsule 標準高度。"
        ]),
        ChangelogEntry(version: "22.93", build: 554, date: "2026/06/28", notes: [
            "【靜態除錯 v22.93 / build 554】修復 LifeRealEstateView v3（build 553 最新美化）引入的效能瓶頸：propertiesByCity（執行 Dictionary(grouping:) 全量分組）在 body 單次 render 中被重複計算三次——① summaryHeader 以 propertiesByCity.count >= 2 檢查是否顯示彩條、② miniCityBar 以 propertiesByCity.sorted{} 建立排序陣列、③ mapView 以 propertiesByCity 驅動 ForEach 圖釘。修復方式：在 body 頂部以 let cities = propertiesByCity 單次快取，summaryHeader / miniCityBar / mapView 由 var 改為 func 接收 cities 參數，由呼叫端傳入預算結果，計算次數由 3 降為 1，對齊 v22.85 FoodMapView.sortedAggregates(from:) 及 v22.91 SubordinateOverviewView 同型修復規格。其餘：無 force unwrap（!）、無 as! 強制轉型、無 fatalError（EInvoiceClient 啟動守衛除外）；CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、@Published 主執行緒隔離均正常。"
        ]),
        ChangelogEntry(version: "22.91", build: 553, date: "2026/06/28", notes: [
            "【靜態除錯 v22.91 / build 553】修復 SubordinateOverviewView v3（build 552）引入的效能瓶頸：summaryHeroCard（v2 新增）直接呼叫 todayLeaves.count、todayMeetings.count、incompleteTasks.count，而 leaveSection / meetingSection / taskSection 在同一次 body 求值時各自也執行一次完整的 flatMap+filter+sorted，導致三個 O(n×m) 計算各被重複執行一次（共多出 3 次 flatMap+filter+sort 呼叫）。修復方式：在 body 頂部以 let leaves、meetings、tasks 各快取一次，summaryHeroCard / leaveSection / meetingSection / taskSection 改為接受預算陣列的函式（從 var 改為 func），由呼叫端傳入已算好的結果，每次 body render 的計算次數由 6 降為 3，對齊 v22.68 SubordinateOverviewView 同型修復規格及 LifeOverviewView let allMS 單次捕捉規格。其餘：無 force unwrap（!）、無 as! 強制轉型、無 fatalError（EInvoiceClient 啟動守衛除外）；CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、@Published 主執行緒隔離均正常。"
        ]),
        ChangelogEntry(version: "22.89", build: 552, date: "2026/06/27", notes: [
            "【靜態除錯 v22.89 / build 552】修復 ResumeView v3（build 551）引入的 force unwrap：resumeHeroCard 的「最近一筆」KPI 以 mostRecent != nil ? formatDate(mostRecent!.date) : \"—\" 取值，違反全 App 無 force unwrap（!）原則；雖 nil 檢查在前不會實際崩潰，但若後續程式碼調整先後順序便有潛在風險。改為 Swift 慣用的 mostRecent.map { formatDate($0.date) } ?? \"—\"，消除強制解包運算子。其餘：無 as! 強制轉型、無 fatalError（EInvoiceClient 啟動守衛除外）；CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、@Published 主執行緒隔離均正常。"
        ]),
        ChangelogEntry(version: "22.87", build: 550, date: "2026/06/27", notes: [
            "【靜態除錯 v22.87 / build 550】全面複查 21 個核心 Swift 檔（所有 Model 層 + 主要 View 層），涵蓋 CloudKitManager、CloudSyncManager、LifeStore、ExpenseStore、FinanceStore、EInvoiceSyncManager、SubscriptionManager、RemoteAdminManager、BackupManager 等所有資料層，以及 OverviewView、MainTabView、AdminConsoleView、ChartView、SettingsView、PaywallView、FinanceOverviewView、FoodMapView、RestaurantSearch 等主要視圖層。確認安全：① 無 force unwrap（PaywallView static let URL 常數為已知合法 ASCII 字串，安全）、無 as! 強制轉型；② CloudKit 30 秒節流（syncNowIfDue）、pushAll 2 秒防抖、isSyncing 並行守衛均正常；③ 所有 @Published 更新隔離至主執行緒；④ AdminConsoleView 最新美化版（v22.86）：allFreeMirror onChange guard、applyPublicDisplay 安全解析、consoleAppeared onDisappear 歸零均確認無誤；⑤ ChartView 量測層（隱形 TabView 背景）與可見輪播共用 rowsAppeared 旗標，onAppear 觸發時由同一 state 變化驅動雙層動畫，可見圖例列進場動畫正常播放（非 Bug）；⑥ FoodMapView aggregates / companionOptions 均以 let aggs / let options 單次計算、sortedAggregates(from:) 接收預算 aggs 避免重複 Dictionary(grouping:)；⑦ RestaurantSearch LocationProvider 與 RestaurantSearchCompleter 所有 delegate callback 均以 [weak self] 防止 retain cycle；⑧ FinanceOverviewView ntdAllocations 在 body 以 let 計算一次傳入 totalAssetsCard + allocationSection，消除雙重計算；⑨ 所有 View 動畫旗標（heroAppeared、consoleAppeared、allocationBarAppeared 等）均在 onDisappear 正確歸零。全面確認後無新問題。"
        ]),
        ChangelogEntry(version: "22.86", build: 549, date: "2026/06/27", notes: [
            "【UI 美化】AdminConsoleView v1：① pinGate 插入 56pt 鎖頭漸層圓（紫→靛，shadow + stroke 0.75pt）作視覺錨點，標題 .headline / 副說明 .caption 雙層分層；PIN 錯誤從純 .red Text 升級為 Capsule 錯誤徽章（紅底半透明 + stroke 0.75pt）。② 使用者人數列升級為 36pt 藍色漸層圓圖示（stroke 0.75pt + shadow），對齊 SettingsView settingsActionRow 圖示圓規格。③ 訂閱狀態值（已解鎖/已上鎖）升級為彩色 Capsule 徽章（綠/紅底 0.12~0.15 透明度 + stroke 0.75pt）。④ 解鎖過渡以 withAnimation(.spring(response:0.5, dampingFraction:0.78)) 切換，console Form 加 .onAppear fade-in（opacity + Y 12pt）讓閘門→控制台切換更流暢。⑤ ChangelogListView 版本號升級為 LinearGradient Capsule 徽章（藍→靛白字）；日期改 Capsule 徽章（tertiarySystemFill + stroke 0.6pt）；bullet 點從 5pt 升為 7pt 藍色漸層圓，對齊全 App Capsule 標籤 / 圖示圓設計語言。"
        ]),
        ChangelogEntry(version: "22.85", build: 548, date: "2026/06/27", notes: [
            "【靜態除錯 v22.85 / build 548】修復五個問題：① BackupManager.createSnapshot：lastSnapshotDate 在背景寫入前即更新，若 App 在寫入完成前被強制結束，UserDefaults 保留指向不存在檔案的時間戳，導致後續 10 分鐘 debounce 誤判、跳過快照建立；改為在背景 do 區塊寫入成功後才回主執行緒更新時間戳，錯誤路徑不更新（原本 catch 中重置為 nil 的邏輯已不需要，直接移除）。② FullBackup.export 附件串流：附件讀取以 if let data = try? Data(...) 靜默略過讀取失敗的檔案，但 manifest 已按實際 fileSize 記錄大小，略過後後續所有附件的讀取位置偏移，還原時每筆附件的位元組範圍全部錯位，造成備份損壞；改為 try Data(...)，讀取失敗直接 throw 使整份 export 報錯，呼叫端（SettingsView try FullBackup.export）會收到錯誤並告知使用者，優於輸出損壞的備份。③ FoodMapView.sortedAggregates：原為 computed var，內部再次呼叫 self.aggregates（Dictionary(grouping:) 全量重算）；body 已以 let aggs = aggregates 計算一次，listSheet 又透過 sortedAggregates 觸發第二次 Dictionary(grouping:)，清單 sheet 開啟時每次 render 重複計算；改為 func sortedAggregates(from:) 接收 body 已算好的 aggs，listSheet 同步改為 func listSheet(_ aggs:) 傳入，消除重複計算。④ RemoteAdmin.incrementUserCount：CKError.serverRecordChanged 衝突時以 self.incrementUserCount(retriesLeft: retriesLeft - 1) 立即遞迴重試（最多 3 次），三次請求在公用 DB 上幾乎同時發出，增加 CKError.requestRateLimited 風險；補入 DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) 延遲後再重試，對齊 CloudKitManager.modifyKV 同類重試的 0.5s 延遲規格。⑤ SettingsView 復原確認 alert 訊息：message 區塊以 if let candidate = restoreCandidate 輸出 Text，當 restoreCandidate 為 nil 時（短暫狀態競態）alert 顯示空白訊息；改為 Text( restoreCandidate.map { ... } ?? fallback )，確保訊息永遠非空。其餘防護機制（force unwrap 全無、as! 全無、fatalError 僅 EInvoiceClient 啟動守衛、CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、所有 @Published 更新主執行緒隔離）均確認正常。"
        ]),
        ChangelogEntry(version: "22.83", build: 546, date: "2026/06/27", notes: [
            "【靜態除錯 v22.83】修復一個問題：RemoteAdmin.refresh() 的 perRecordResultBlock：外層 closure 以 [weak self] 捕捉，guard let self = self 在外層產生強引用後，內層 DispatchQueue.main.async { } 無 capture list，強捕捉外層的 self，部分抵銷 [weak self] 防護，CloudKit 操作期間使 RemoteAdminManager 被 GCD block 額外強持。修復方式：內層 async 補加 [weak self] 並加 guard let self 守衛，與全 App 其他 CloudKit callback 二層弱捕捉模式保持一致。其餘：force unwrap 全無、as! 全無、陣列 index 越界全有守衛、CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 主執行緒守衛、EInvoiceSyncManager @MainActor 批次寫入、AddSavingsInsuranceView v2 新增視覺元素（玻璃光澤/散景圓/邊框/漸層圖示圓/KPI 動畫）靜態分析確認安全，無新問題。"
        ]),
        ChangelogEntry(version: "22.81", build: 545, date: "2026/06/27", notes: [
            "【靜態除錯 v22.81】全面複查 79 個 Swift 檔（強制解包、Optional 處理、型別錯誤、index 越界、retain cycle、競態條件、CloudKit 節流、畫面閃爍、效能瓶頸）。確認安全：無 force unwrap（!）、無 as! 強制轉型；AppleCalendarBridge.writeOrUpdate calendarId 接受 String? 無崩潰風險；MainTabView DragGesture Task 無 retain cycle（View 為值型別）；weekdays 索引有 .indices.contains 守衛；LifeOverviewView.allMS 單次計算後傳入三個子 section；OverviewView.monthlyBalanceCard KPI 以 let 一次計算；ChartView totalForPeriod 雙呼叫因 chartData 陣列極小（≤30 筆）可忽略；CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 主執行緒守衛、saveQueue 值型快照、EInvoiceSyncManager @MainActor 批次寫入、FinanceStore reloadFromCloud 直接呼叫 load() 均正常；fmtWan（FoodMapView）NT$ 前綴三分支一致（v22.80 已修正）；無新問題。"
        ]),
        ChangelogEntry(version: "22.80", build: 544, date: "2026/06/26", notes: [
            "【靜態除錯 v22.80】全面複查 79 個 Swift 檔（強制解包、Optional 處理、型別錯誤、index 越界、retain cycle、競態條件、CloudKit 節流、畫面閃爍、效能瓶頸）。",
            "【Bug 修復】RestaurantDetailSheet.fmtWan（FoodMapView.swift）：v3 新增的萬/億量級格式函式在金額 ≥ NT$10,000 時回傳「X.X萬」或「X.X億」（無貨幣前綴），金額 < NT$10,000 時才回傳「NT$ X,XXX」，導致同一 headerCard 內「總花費」KPI 格在不同金額大小下顯示格式不一致（有/無 NT$ 前綴）。已將億、萬兩個分支均補入「NT$ 」前綴，使三個量級輸出格式統一為「NT$ X.X億 / NT$ X.X萬 / NT$ X,XXX」，與相鄰「平均每次」KPI 格的格式對齊。",
            "【確認安全】CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 主執行緒守衛、flushPushAll !isSyncing guard、saveQueue 值型快照、NSLock fetchLock 均正常；所有 @Published 更新在主執行緒；weekdays index 已有 .indices.contains 守衛；estimatedMonthlyIncome 中位數計算有 isEmpty guard；weeklyData O(n×12) 優化正常；MyCalendarView 搜尋 300ms 防抖（.task(id:)）正常；subordinateAgendaSection 計算屬性已快取為 let 常數；其餘程式碼無問題。"
        ]),
        ChangelogEntry(version: "22.76", build: 541, date: "2026/06/26", notes: [
            "【Bug 修復】GradeTitleView.deleteDepartment / DepartmentEditor.deleteSelf：刪除部門時只清除了 OrgPerson.departmentId，未清除 Subordinate.departmentId，導致部屬保留孤立的 UUID 參照（resolvedDeptName 退為空字串，部門篩選 UI 無法正確高亮）。兩個刪除路徑均補上同步清零 sub.departmentId 的迴圈，對齊既有 orgPeople 清零規格。",
            "【Bug 修復】SubordinateView：刪除已篩選的部門後，filterDeptRaw（AppStorage）仍保存該部門 UUID，篩選列無任何膠囊高亮，且搭配上一項修復後會顯示空列表，無法自行恢復。補入 .onChange(of: lifeStore.departments) 觀察器，偵測到所選部門已不存在時自動歸零 filterDeptRaw，恢復顯示全部部屬。",
            "【確認安全】全面複查 79 個 Swift 檔：無 force unwrap（!）、無 as! 強制轉型、無 fatalError；CloudKit 30 秒節流、2 秒防抖、isSyncing 主執行緒守衛、saveQueue 值型快照均正常；所有 @Published 更新在主執行緒；本次修復為上述兩個因部門篩選功能引入的實際 bug，其餘程式碼無問題。"
        ]),
        ChangelogEntry(version: "22.75", build: 540, date: "2026/06/26", notes: [
            "【靜態除錯 v22.75】MyCalendarView 搜尋加入 300ms 防抖（debouncedSearchText + .task(id: searchText)），每次按鍵不再直接觸發 O(n) 全量 searchHits() 掃描，改為停止輸入 300ms 後才執行搜尋，消除快速輸入時的主執行緒卡頓。",
            "MyCalendarView.subordinateAgendaSection 內 subIncompleteMeetingItems、subIncompleteTasks 兩個計算屬性從各呼叫兩次（.count + ForEach enumerated）減為各呼叫一次，以 let 區域常數快取，消除每次 body render 的冗餘 flatMap/filter/sorted。"
        ]),
        ChangelogEntry(version: "22.74", build: 539, date: "2026/06/25", notes: [
            "我的行事曆『部屬報告』章節不再列出已完成報告，已完成統一歸納到底部『已完成』收合卡。"
        ]),
        ChangelogEntry(version: "22.73", build: 538, date: "2026/06/25", notes: [
            "我的行事曆『已完成』改為歸納所有已勾選完成的部屬報告/會議項目/任務（不再只限當日）。",
            "搜尋結果與已完成項目改為點一下直接開啟該項目編輯（報告/任務/會議/請假/里程碑/個人事件），不再跳到日期。"
        ]),
        ChangelogEntry(version: "22.72", build: 537, date: "2026/06/25", notes: [
            "部屬頁面新增部門篩選列（全部部門 / 各部門膠囊），減少一次顯示過多。",
            "部屬清單依廠區分組顯示（與部屬班表一致）；標題顯示所選部門與人數。手動排序時維持平面以便拖曳。"
        ]),
        ChangelogEntry(version: "22.71", build: 536, date: "2026/06/25", notes: [
            "部屬卡片：報告/任務/會議議程項目完成後改收合至最下方『已完成』可展開區塊，上方僅顯示未完成。",
            "部屬總覽：底部新增統一『已完成』收合卡（報告/會議項目/任務），完成項目不再夾雜於各區塊。",
            "我的行事曆：部屬事項最下方新增『已完成（當日）』收合卡。",
            "我的行事曆新增搜尋：可依標題或內容搜尋部屬報告/會議/任務/請假、里程碑與個人事件，點結果即跳至該日期。"
        ]),
        ChangelogEntry(version: "22.70", build: 535, date: "2026/06/25", notes: [
            "修正匯入時部屬『報告』未被合併的問題：部屬資料合併匯入現在會一併帶入週報；摘要新增『報告 +N』。",
            "完整 JSON 合併匯入改為更新既有部屬的子項目（班表/任務/會議/報告/紀錄），不再只新增全新的人，避免部屬資料看似未完整匯入。"
        ]),
        ChangelogEntry(version: "22.68", build: 534, date: "2026/06/25", notes: [
            "【靜態除錯 v22.68】修復 SubordinateOverviewView 效能瓶頸：leaveSection、meetingSection、meetingItemsCard、completedCard 四個計算屬性（computed view properties）內部各自重複存取同一個 O(n×m) 計算屬性 2–4 次：todayLeaves 在 leaveSection 內存取 4 次（sectionHeader count ×1、isEmpty ×1、enumerated ×1、count-1 ×1），todayMeetings 在 meetingSection 內存取 4 次，incompleteMeetingItems 在 meetingItemsCard 內存取 3 次，completedTasks 在 completedCard 內存取 3 次；每次 body 重繪（例如 CloudKit pull 後 @Published 觸發）各計算屬性即被重複執行。修復方式：在四個 computed view property 頂部各新增一個 let 區域常數快取（let leaves / meetings / items / tasks），將後續引用全數改為存取此常數，每次 property 求值只觸發一次 O(n×m) flatMap/filter，消除每次 body render 的冗餘計算。其餘防護機制（force unwrap 全無、as! 全無、fatalError 僅 EInvoiceClient 啟動守衛、CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、所有 @Published 更新主執行緒隔離）均確認正常。"
        ]),
        ChangelogEntry(version: "22.67", build: 533, date: "2026/06/25", notes: [
            "【靜態除錯 v22.67】修復一個邏輯 bug：AddVehicleView.calcSection 試算區塊的折舊金額 / 折舊率列，僅以 purchase > 0, current > 0 為條件顯示，當目前估值 > 購入價時（升值情況，如古典車 / 收藏車），顯示負數折舊，對使用者造成誤導；補加 purchase > current 守衛，對齊 vehiclePreviewCard（depAmt 以 purchase > current 判斷、depRate 以 max(0,…) 保護）的行為，兩處顯示邏輯一致。其餘防護機制（force unwrap 全無、as! 全無、fatalError 僅 EInvoiceClient 啟動守衛、CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、所有 @Published 更新主執行緒隔離）均確認正常。"
        ]),
        ChangelogEntry(version: "22.66", build: 532, date: "2026/06/25", notes: [
            "【靜態除錯 v22.66】修復三個問題：① CloudKitManager.runFetch changeTokenExpired 分支：原本直接呼叫 fetchChanges(completion:)，若 CloudKit 持續回傳 token 過期錯誤會無限遞迴；改為對 runFetch 傳入 retriesLeft 計數器，重試一次失敗後即報錯並呼叫 completion(false)，防止無限遞迴。② AIExpenseParserService.parse：activeProvider 與 key 分成兩次獨立的 await MainActor 切換讀取，使用者若在兩次 await 之間切換 AI 供應商，會以 provider-A 的身份呼叫 provider-B 的金鑰；改以單一 MainActor.run 閉包一次性讀取，確保兩值永遠屬於同一個供應商。③ FinanceStore.reloadFromCloud：cloudSyncDidPullChanges 已由 CloudSyncManager 在主執行緒 post，多一層 DispatchQueue.main.async 會增加一個 run-loop 空窗，期間若使用者操作觸發 save() 則雲端資料覆蓋編輯；移除多餘的 async 包裝，改直接呼叫 load()，與 LifeStore / ExpenseStore 保持一致。"
        ]),
        ChangelogEntry(version: "22.64", build: 531, date: "2026/06/24", notes: [
            "任務 / 會議項目 / 報告打勾完成時，自動記下完成時間戳，並依目標日期標示『超前(綠) / 準時(藍) / 逾期(紅)』。",
            "完成戳記顯示於部屬卡片、部屬總覽與我的行事曆；取消打勾會清除戳記，編輯時保留原戳記。"
        ]),
        ChangelogEntry(version: "22.63", build: 530, date: "2026/06/24", notes: [
            "【靜態除錯 v22.63】全面複查 79 個 Swift 檔（強制解包、Optional 處理、型別錯誤、index 越界、retain cycle、競態條件、CloudKit 節流、畫面閃爍、效能瓶頸）：發現並修復一個問題：project.pbxproj 版本號停留在 22.61/528，未隨 v22.62 UI 美化提交同步更新，補正 MARKETING_VERSION 至 22.63、CURRENT_PROJECT_VERSION 至 530。其餘防護機制（force unwrap 全無、as! 全無、fatalError 僅 EInvoiceClient 啟動守衛、CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、FinanceStore reloadFromCloud DispatchQueue.main.async 保護、CloudKitManager fetchRecordZoneChangesResultBlock DispatchQueue.main.async 保護、EInvoiceSyncManager @MainActor 批次寫入、ChartView DragGesture label 比對守衛、MultiPhotoGallery Task.detached 背景讀圖、所有 DateFormatter/NumberFormatter 均為 private static let 快取）均確認正常。"
        ]),
        ChangelogEntry(version: "22.62", build: 529, date: "2026/06/24", notes: [
            "【UI 美化 v3】RealEstateDetailView：① flashCard 英雄卡背景升級為 ZStack（漸層 + 三個 bokeh 裝飾圓 opacity 0.06/0.04/0.035 + 頂部玻璃光澤 LinearGradient [.white.opacity(0.18), .clear]），對齊 VehicleView / StockView 英雄卡規格；② 主金額 52pt 文字補 minimumScaleFactor(0.5) + lineLimit(1) + contentTransition(.numericText())，防長數字溢出；③ 房屋資料分頁與資產分頁空狀態升級為 56pt 漸層圖示圓（teal / 藍色 + 細邊框 stroke），對齊 CareerView 空狀態規格。"
        ]),
        ChangelogEntry(version: "22.61", build: 528, date: "2026/06/24", notes: [
            "【靜態除錯 v22.61】修復三個問題：① FinanceStore.reloadFromCloud：NotificationCenter 在發送方執行緒觸發，load() 直接改寫 @Published 屬性可能在背景執行緒執行，補 DispatchQueue.main.async 保護；② ExpenseStore 新增 addExpenses(_ items:) 批次寫入方法，EInvoiceSyncManager 改用此 API，取代直接存取 expenseStore.expenses（@Published 陣列），確保封裝性與單次 save/push；③ ChartView DragGesture onChanged：每次拖曳都對 selectedDataPoint 賦值，即使目標不變也觸發 @State 更新與 body 重繪；補 label 比對守衛，只在資料點實際改變時才賦值，消除無效重繪。"
        ]),
        ChangelogEntry(version: "22.59", build: 526, date: "2026/06/24", notes: [
            "【靜態除錯 v22.59】SubordinateOverviewView.reportDateText：每次呼叫都新建 DateFormatter（含 zh_Hant_TW locale 載入），在 ForEach 報告列表 render 時重複分配；改為 private static let reportDateFormatter 快取，對齊同檔 fmtTimeFormatter / fmtDateTimeFormatter 及 v22.58 MyCalendarView.subReportDateFormatter 既有規格。其餘防護機制（force unwrap 全無、as! 全無、fatalError 僅 EInvoiceClient 啟動守衛、CloudKit 30 秒節流、pushAll 2 秒防抖、isSyncing 並行守衛、所有 @Published 更新主執行緒隔離）均確認正常。"
        ]),
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
