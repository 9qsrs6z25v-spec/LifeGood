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
