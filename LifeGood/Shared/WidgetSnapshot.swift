import Foundation

// MARK: - 桌面小工具的快照（v25.545；v2 擴充）
//
// 這個檔案同時屬於「主 App」與「LifeGoodWidgets」兩個 target。
//
// [v2] 加了：記帳台、一按就記、接下來要繳、鎖定畫面三型、控制項兩個的 kind；
//      money 快照的分類、常記範本、車子卡、下個月 1–7 號、隱藏金額版與鎖定畫面版的字；
//      bills_v1.json（接下來要繳）；隱藏金額開關（App Group 的 UserDefaults）。
//      money 的新欄位一律是選填（舊檔解得開、schema 不升），App 一打開就補齊。
//
// [v3] 加了：旅行小工具、控制項「說一句」「記到…」的 kind；money 的車子選單（vehicleOptions）、
//      「記到哪裡」的選項（recordTargets）、記帳台照設定挑卡（deskTiles(choiceIDs:)）；
//      life 的旅行（trips、tripPhase）、隔天每一種的第一場（nextDayFirstStops）、照設定篩行程（filtered(kinds:)）；
//      bills 的鎖定畫面類別字（lockTitle）與範圍（WidgetBillScope）。新欄位一律選填、schema 不升。
//      小工具長按設定用的 AppEnum／AppEntity 在 WidgetConfigTypes.swift（兩個 target 都編）。
//
// [v4] 加了：股票今天（小＋鎖定畫面三型、中）、金價匯率、我的車、淨資產的 kind；
//      finance_v1.json（WidgetFinanceSnapshot：stocks、rates、vehicles、netWorth，App 用跟理財頁同一套算好）；
//      quotes_v1.json（WidgetQuoteCache：**小工具自己**上網抓的股價、金價匯率，App 不讀不寫）。
//      「小工具不算錢」唯一的例外：股票用小工具自己抓的新價重算市值、比均價、漲跌，金價匯率用新價寫漲跌——
//      算式與寫法全部在共用檔 WidgetQuoteService.swift（WidgetFinanceStock.figures／WidgetRateChoice.figures），
//      金額字一律走 WidgetMoneyFormat.swift（逐字照抄 App 的 ntdWanString／MoneyFormat／FinanceText／StockCardText）。
//      小工具的畫面檔不准自己乘、不准自己拼「NT$」。
//
// [v5] 加了：部屬今天（WidgetKind.team）、控制項「今日行程」（WidgetKind.controlDayTimeline）的 kind；
//      life 的選填欄位 hasTeam／team（今天、明天各一份：請假、班別、逾期／今天到期的任務、各廠區件數、生日）、
//      plantAreas（廠區清單）、familyTasks（家庭待辦今天到期、未完成，今天明天各一份）、
//      countdowns（60 天內的結婚紀念日、家人生日、兼任職務重要日期，App 算好「下一次那一天」）。
//      小工具只照日期挑那一份、照廠區篩、數人頭與排序（WidgetTeamDay.summary）；名字、假別、班別、
//      「逾期 2 天」這些字全部是 App 寫的。「今天（大）」②③④ 的每一列在 WidgetLifeSnapshot 的
//      todaySpecials／todayTeamLine／todayTodos／upcomingLines 組好（WidgetLineItem）。
//      規格：scratchpad/widgets/v5/brief.md §3。
//
// 分工跟靈動島一樣：App 把小工具要顯示的「字」與「數字」算好、格式化好，寫成 App Group 裡的
// 小檔案；小工具只讀這些檔、照著畫。**小工具裡不做任何金額計算與格式化**——「NT$4.6萬」
// 「每天 NT$2,402」「已花 62%」全部是 App 用自己那套函式（MoneyFormat／ntdWanString）組好的字。
//
// 換日不靠小工具算：App 寫快照時就把「今天、明天……」每一天要顯示的字各準備一份，
// 小工具只依現在時間挑對應的那一份。
//
// [手錶 v1，v25.574] 這個檔也編進手錶兩個 target（LifeGoodWatch、LifeGoodWatchWidgets；watch/judge.md §7.3）：
//      手錶包的每一天那一份照用 WidgetLifeDay／WidgetMoneyDay（currentStop(at:)、lines(hidden:) 手錶直接呼叫）。
//      所以下面那條「只准 Foundation」對手錶一樣成立；新增欄位會不會流上手錶由 pkg_keys_check.py 擋（白名單）。
//
// ⚠️ 這個檔案只准用 Foundation、TimelineStop／DayTimelineFormat／DayTimelineLink
//    （DayTimelineAttributes.swift）與同檔型別。不准引用 App 才有的型別
//    （ExpenseStore、AppMode、MoneyFormat、OverviewBoardData…）：Widget target 編不過，
//    而為了編過改寫字面字串，就會重演 v25.454（共用檔寫 "life"、rawValue 其實是「人生」，
//    點靈動島永遠跳錯頁）。網址一律用 WidgetLink（WidgetLink.swift）組。

// MARK: - 名字

enum WidgetShared {
    /// App Group。v25.544 已加到 LifeGood.entitlements 與 LifeGoodWidgets.entitlements，
    /// 使用者也已在 Apple Developer 後台註冊並掛到兩個 App ID。
    static let appGroupID = "group.com.lifegood.app"
    /// App Group 裡放快照的資料夾
    static let folderName = "Widgets"

    /// [v2] App Group 共用的 UserDefaults（隱藏金額開關、控制項交給 App 的網址）。
    /// entitlements 沒生效時是 nil：讀一律當「沒設定」，寫什麼都不做。
    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }
}

/// WidgetKit 的 kind。小工具的 StaticConfiguration 與 App 的 reloadTimelines(ofKind:) 都用這裡的值，
/// 兩邊不准各寫一份字面字串。
enum WidgetKind {
    /// 還能花（systemSmall；StandBy 用同一個）
    static let moneyLeft = "LifeGoodMoneyLeft"
    /// 今天（systemSmall、systemMedium）
    static let today = "LifeGoodToday"

    // MARK: [v2]

    /// 記帳台（systemMedium）：左半還能花、右半四張卡（連結）
    static let ledgerDesk = "LifeGoodLedgerDesk"
    /// 一按就記（systemSmall、systemMedium）：常記範本的互動按鈕，不開 App
    static let quickRecord = "LifeGoodQuickRecord"
    /// 接下來要繳（systemMedium）
    static let bills = "LifeGoodBills"
    /// 鎖定畫面「已花」（accessoryCircular）＋記帳一行字（accessoryInline）
    static let lockSpent = "LifeGoodLockSpent"
    /// 鎖定畫面「下一場」（accessoryRectangular）＋行程一行字（accessoryInline）
    static let lockNextStop = "LifeGoodLockNextStop"
    /// 鎖定畫面「下一筆要繳」（accessoryRectangular）
    static let lockNextBill = "LifeGoodLockNextBill"
    /// 控制項「記一筆」（ControlWidgetButton）。控制項的 kind 用反向網域名
    static let controlAddExpense = "com.lifegood.app.control.addExpense"
    /// 控制項「隱藏金額」（ControlWidgetToggle）
    static let controlHideAmounts = "com.lifegood.app.control.hideAmounts"

    // MARK: [v3]

    /// 旅行（systemSmall、systemMedium、accessoryRectangular）：出發倒數、旅途中第幾天＋下一站。讀 life_v1.json 的 trips
    static let travel = "LifeGoodTravel"
    /// 控制項「說一句」（ControlWidgetButton → LifeGoodOpenIntent(url: WidgetLink.voiceRecord)）
    static let controlVoice = "com.lifegood.app.control.voice"
    /// 控制項「記到…」（AppIntentControlConfiguration：選一個變動分類，或一台車＋車子分類）
    static let controlRecordTo = "com.lifegood.app.control.recordTo"

    // MARK: [v4]

    /// 股票今天：systemSmall（一檔）＋鎖定畫面 accessoryCircular／accessoryRectangular／accessoryInline（同一檔的價與漲跌）
    static let stock = "LifeGoodStock"
    /// 股票今天（三檔）：systemMedium
    static let stocks = "LifeGoodStocks"
    /// 金價匯率：systemSmall＋鎖定畫面 accessoryCircular／accessoryRectangular／accessoryInline
    static let rates = "LifeGoodRates"
    /// 我的車：systemSmall、systemMedium＋鎖定畫面 accessoryCircular／accessoryRectangular
    static let vehicle = "LifeGoodVehicle"
    /// 淨資產：systemSmall、systemMedium＋鎖定畫面 accessoryCircular／accessoryRectangular
    static let netWorth = "LifeGoodNetWorth"

    /// [v4] finance_v1.json 的 stocks 變了要重畫的（App 寫手只重畫受影響的那幾種）
    static let stockKinds = [stock, stocks]
    /// [v4] finance_v1.json 的 rates 變了
    static let ratesKinds = [rates]
    /// [v4] finance_v1.json 的 vehicles 變了
    static let vehicleKinds = [vehicle]
    /// [v4] finance_v1.json 的 netWorth 變了
    static let netWorthKinds = [netWorth]
    /// [v4] 理財四個小工具全部（finance_v1.json 第一次寫、整份換掉時）
    static let financeKinds = [stock, stocks, rates, vehicle, netWorth]

    // MARK: [v5]

    /// 部屬今天：systemSmall、systemMedium＋鎖定畫面 accessoryRectangular／accessoryInline。讀 life_v1.json 的 team
    static let team = "LifeGoodTeam"
    /// 控制項「今日行程」（ControlWidgetToggle：靈動島開／關，DayTimelineToggleIntent）
    static let controlDayTimeline = "com.lifegood.app.control.dayTimeline"
    /// [v5] life_v1.json 的 team／plantAreas／hasTeam 變了要重畫的
    static let teamKinds = [team]
    /// [v5] 靈動島開、續期、收掉時要重畫的控制項（WidgetRefresh.reloadControls）。
    /// 同時要重畫 WidgetKind.today（中型「上靈動島」按鈕看靈動島有沒有在跑）
    static let dayTimelineControlKinds = [controlDayTimeline]

    // MARK: [健康 v7b]

    /// 控制項「開始跑步」（ControlWidgetButton → LifeGoodOpenIntent(url: WidgetLink.healthRun)；控制中心、鎖定畫面、動作按鈕）。
    /// 不讀快照、沒有值，不用重畫
    static let controlStartRun = "com.lifegood.app.control.startRun"

    /// money_v1.json 變了要重畫的（App 的寫手、一按就記的按鈕都用這一組）
    static let moneyKinds = [moneyLeft, ledgerDesk, quickRecord, lockSpent]
    /// [v3] money_v1.json 變了要重畫的控制項（「記到…」的「Taycan 電費」從 money 快照讀）。
    /// 用 WidgetRefresh.reloadControls(_:)
    static let moneyControlKinds = [controlRecordTo]
    /// life_v1.json 變了要重畫的全部（[v3] 加旅行；[v5] 加部屬今天）。
    /// [v5] App 寫手只重畫受影響的那幾種（WidgetSnapshotWriter.lifeKindsToReload），這一組是「全部」
    static let lifeKinds = [today, lockNextStop, travel, team]
    /// bills_v1.json 變了要重畫的
    static let billsKinds = [bills, lockNextBill]
}

/// 快照檔名。分檔是為了只改了帳就只重寫 money、只重畫「還能花」。
enum WidgetSnapshotFile: String {
    case money = "money_v1.json"
    case life = "life_v1.json"
    /// [v2] 接下來要繳
    case bills = "bills_v1.json"
    /// [v4] 理財四個小工具（App 寫）
    case finance = "finance_v1.json"
    /// [v4] 小工具自己抓的股價、金價匯率（**只有小工具讀寫**，App 不讀不寫）
    case quotes = "quotes_v1.json"
    /// [手錶 v1] 手錶包（WatchPackage，Shared/WatchPackage.swift）：iPhone 的 App Group 留「最新的那一包」
    ///（WatchBridge 比內容、冷啟動回覆用）；手錶收到後存進**手錶自己的** App Group 同一個檔名（手錶 App、手錶小格都讀）
    case watch = "watch_v1.json"
    /// [手錶 v1] 手錶附加資料快取（WatchExtrasCache，Models/WatchExtrasWriter.swift）：**只在 iPhone**，
    /// App 開著時寫要碰帳本才算得出來的東西（v1：哪幾期卡費是自己繳），組手錶包時只讀這個檔
    case watchExtras = "watch_extras_v1.json"
}

// MARK: - [v2] 隱藏金額

/// 控制中心「隱藏金額」開關與 App 設定頁的同一個開關。存在 App Group 的 UserDefaults，
/// 不跟 iCloud 同步（iPhone、iPad 各自設）。
///
/// 開著時：所有小工具的金額改成 mask（「NT$ ••••」），百分比、日期、期數、筆數照常。
/// 「每天 NT$2,402」這種金額夾在句子裡的，App 已經在快照裡另外寫好「隱藏版」的字
///（WidgetMoneyDay.masked）；單純一個金額的欄位（WidgetBill.amountText、
/// WidgetQuickTemplate.amountText、QuickRecordEntry.amountText）小工具直接整個換成 mask。
///
/// 小工具在 provider（getTimeline／getSnapshot）讀一次放進 entry，View 裡不要讀。
/// 改了之後一律呼叫 WidgetRefresh.afterHideAmountsChanged()（WidgetActions.swift）重畫全部。
enum WidgetHideAmounts {
    static let key = "widget_hide_amounts"
    /// 遮起來的金額長這樣（我們自己的寫法，不是系統鎖著時的灰色色塊）
    static let mask = "NT$ ••••"

    static var isOn: Bool { WidgetShared.defaults?.bool(forKey: key) ?? false }

    static func set(_ on: Bool) {
        WidgetShared.defaults?.set(on, forKey: key)
    }
}

/// 時間門檻：兩邊用同一組數字
enum WidgetFreshness {
    /// 「還能花」快照超過這麼久沒更新，最下面一行改成「上次更新 10/11」（照樣換日顯示）
    static let moneyStaleAfter: TimeInterval = 2 * 24 * 3600
    /// 「今天」中型：快照超過這麼久沒更新，右下角寫「10:02 更新」
    static let lifeShowUpdatedAfter: TimeInterval = 3 * 3600
    /// 倒數字（「25 分後」）只在這麼多分鐘以內寫；更遠的只寫時間
    static let countdownMaxMinutes = 90
}

// MARK: - 快照的共同規矩

/// 每一份快照都要有的東西。
///
/// generatedAt 是「寫的當下」，**不算內容**：寫檔時拿掉它再比，內容沒變就不寫、不叫重畫
///（App 在背景叫重畫會吃掉小工具每天的額度）。所以快照裡**不准放由 generatedAt 推出來的字**
///（例如「10:02 更新」「上次更新 10/11」），那些由小工具用 WidgetDateText 從 generatedAt 組。
protocol WidgetSnapshotPayload: Codable, Equatable {
    static var file: WidgetSnapshotFile { get }
    /// 這一版的格式號。讀到的檔 schema 對不上就當作沒有快照（顯示「打開 LifeGood 一次」）。
    static var schemaVersion: Int { get }
    var schema: Int { get }
    var generatedAt: Date { get set }
}

// MARK: - 還能花（money_v1.json）

/// 「還能花」的三種狀態（跟收支總覽頭部同一套判斷）
enum WidgetMoneyState: String, Codable {
    /// 有收入基準、還沒超支：本月還能花
    case normal
    /// 有收入基準、已經超支：本月已超支（紅）
    case over
    /// 一筆收入紀錄都沒有：本月支出
    case noIncome
}

/// 「這個月的錢」橫條（跟總覽同一條縮短；不畫斜線預估）。
/// 三個值都是 0…1，以 max(收入基準, 本月支出, 1) 為整條的長度，App 已經夾好範圍。
struct WidgetMoneyBar: Codable, Equatable {
    /// 固定支出（紫）從 0 畫到這裡
    var fixed: Double
    /// 變動支出（藍）接在固定後面，長度是這個值（fixed + variable ≤ 1）
    var variable: Double
    /// 收入基準那一道直線的位置；沒有收入紀錄是 nil（不畫線）。
    /// fixed + variable 超過它的那一截＝超支，小工具畫成紅色。
    var income: Double?
}

/// 某一天「還能花」要顯示的全部字。小工具不改字、不拼字（除了把它們放進版面）。
///
/// 例（10/13 週二 10:05，正常）：
///   dateText「10/13 週二」 title「本月還能花」 hero「NT$4.6萬」
///   line「每天 NT$2,402」 footer「已花 62%・還有 19 天」
/// 已超支：title「本月已超支」 hero「NT$3,200」 line「每天 已超支」 footer「已花 103%・還有 19 天」
/// 沒有收入：title「本月支出」 hero「NT$7.4萬」 line「記一筆收入，才算得出還能花」
///          footer「今天 NT$1,240・3 筆」（今天還沒記帳：「今天 還沒花錢」）
struct WidgetMoneyDay: Codable, Equatable, Identifiable {
    /// 「2026-10-13」（WidgetDateText.dayKey）
    var dayKey: String
    /// 這一天的 00:00 與隔天 00:00（App 用 Calendar.current 算的絕對時間）
    var dayStart: Date
    var dayEnd: Date
    /// 左上角日期「10/13 週二」（WidgetDateText.dayLabel）
    var dateText: String
    var state: WidgetMoneyState
    /// 小標
    var title: String
    /// 大字
    var hero: String
    /// 第二行
    var line: String
    /// 最下面一行（快照太舊時小工具改寫成「上次更新 10/11」，見 WidgetMoneySnapshot.isStale）
    var footer: String
    /// 本月支出 ÷ 收入基準（0.62＝62%、1.03＝103%，不夾上限）；沒有收入紀錄是 0。
    /// footer 裡的「62%」就是它；這個數字留給之後的進度環（v2 鎖定畫面）。
    var spentRatio: Double
    /// 今天起還剩幾天（含今天）
    var remainingDays: Int
    var bar: WidgetMoneyBar

    // MARK: [v2] 以下都是選填：v1 寫的舊檔沒有這些欄位，照樣解得開（App 一打開就補齊）

    /// 記帳台左半「今天 NT$1,240・3 筆」；今天還沒記帳「今天 還沒花錢」（小工具畫綠色）
    var todayText: String? = nil
    /// 今天記了幾筆變動支出（「今天 還沒花錢」要不要畫綠、鎖定圓形沒收入時的「3 筆」由 App 寫在 lock 裡）
    var todayCount: Int? = nil
    /// 記帳台左半「收入 NT$12萬・預估」（薪水進來後沒有「・預估」）；沒有收入紀錄是 nil（不寫這行）
    var incomeText: String? = nil
    /// 隱藏金額時的四行字（見 WidgetMoneyMasked）
    var masked: WidgetMoneyMasked? = nil
    /// 鎖定畫面「已花」圓形與一行字（見 WidgetMoneyLock）
    var lock: WidgetMoneyLock? = nil

    var id: String { dayKey }
    /// 超支旗標（大字、小標、第二行用紅色；著色模式靠「已超支」三個字）
    var isOver: Bool { state == .over }

    func contains(_ date: Date) -> Bool { dayStart <= date && date < dayEnd }

    /// [v2] 依「隱藏金額」挑要顯示的字。小工具一律經過這裡拿字，不自己拼。
    /// hidden 而快照是 v1 舊檔（沒有 masked）：大字寫 mask，其他行留空（不冒險露出夾在句子裡的金額）。
    func lines(hidden: Bool) -> WidgetMoneyLines {
        guard hidden else {
            return WidgetMoneyLines(title: title, hero: hero, line: line, footer: footer,
                                    todayText: todayText ?? footer, incomeText: incomeText)
        }
        guard let m = masked else {
            return WidgetMoneyLines(title: title, hero: WidgetHideAmounts.mask, line: "", footer: "",
                                    todayText: "", incomeText: nil)
        }
        return WidgetMoneyLines(title: m.title, hero: m.hero, line: m.line, footer: m.footer,
                                todayText: m.footer, incomeText: nil)
    }
}

/// [v2] 隱藏金額時「還能花」那四行。全部是 App 組好的字。
///
/// 正常／超支：title「本月已花」 hero「62%」（超支「103%」） line「還有 19 天」 footer「今天 3 筆」
/// 沒有收入紀錄：title「本月支出」 hero「NT$ ••••」 line「記一筆收入，才算得出還能花」 footer「今天 3 筆」
/// 今天還沒記帳時 footer 是「今天 還沒花錢」。
struct WidgetMoneyMasked: Codable, Equatable {
    var title: String
    var hero: String
    var line: String
    var footer: String
}

/// [v2] 鎖定畫面「已花」。全部不含金額，所以隱藏金額開關不影響它。
///
/// 正常：ringValue 0.62、ringText「62%」、ringCaption「已花」、inlineText「今天 3 筆・已花 62%」
/// 超支：ringValue 1、ringText「超支」、ringCaption「已花」、inlineText「今天 3 筆・已花 103%」
/// 沒有收入紀錄：ringValue 0、ringText「3 筆」（小工具在上面畫購物車圖示）、ringCaption「今天」、
///              inlineText「今天 3 筆・還沒有收入紀錄」
/// 今天還沒記帳時「今天 3 筆」那一段是「今天 還沒花錢」、ringText 是「0 筆」。
struct WidgetMoneyLock: Codable, Equatable {
    /// 進度環 0…1（App 已經夾好）
    var ringValue: Double
    var ringText: String
    var ringCaption: String
    var inlineText: String
}

/// [v2] WidgetMoneyDay.lines(hidden:) 的結果：小工具畫面直接拿這幾個字。
struct WidgetMoneyLines: Equatable {
    var title: String
    var hero: String
    var line: String
    var footer: String
    /// 記帳台左半「今天」那一行（隱藏時＝footer「今天 3 筆」）
    var todayText: String
    /// 記帳台左半「收入」那一行；nil＝不寫（沒有收入紀錄、或隱藏金額）
    var incomeText: String?
}

struct WidgetMoneySnapshot: Codable, Equatable, WidgetSnapshotPayload {
    static let file = WidgetSnapshotFile.money
    static let schemaVersion = 1

    var schema: Int = WidgetMoneySnapshot.schemaVersion
    var generatedAt: Date
    /// 寫的當下是哪一天「2026-10-13」
    var dataDay: String
    /// 寫的當下是幾月（1…12）
    var month: Int
    /// 從今天到這個月最後一天，每天一份，依日期排序（至少今天一份）。
    /// 明天以後的那幾份是 App 用同一套規則推的：今天花的歸零、剩餘天數減一、每天還能花重算；
    /// 本月支出、收入基準照今天的（還沒記的帳 App 不知道，打開 App 就會重寫）。
    ///
    /// [v2] 月底之後**再接下個月 1–7 號**（App 側 WidgetMoneyExtras.nextMonthBoard，固定 7 天）：
    /// 用下個月的收入基準（那天的本月收入與近 6 個月中位數取大）與那天有效的固定支出月等值算，
    /// 本月支出＝固定支出＋已經記在下個月的變動支出（通常 0）。11/1 早上沒開 App 也是 11 月的數。
    /// 過了這 7 天才退回 v1 的「X 月開始了」提示（hasEnded）。
    var days: [WidgetMoneyDay]

    // MARK: [v2] 以下都是選填（v1 舊檔沒有）

    /// 14 個變動分類，照 VariableCategory.allCases 的順序（記帳台的卡、之後 v3 的選單）
    var categories: [WidgetCategory]? = nil
    /// 近 60 天記最多次的分類 key（VariableCategory.rawValue），多到少，**至少 3 個**
    ///（不夠用 飲食、購物、交通、日用品 依序補；有 vehicleCard 時不放「汽車」，免得跟第三張卡重複）
    var topCategoryKeys: [String]? = nil
    /// 記帳台第三張卡：有車（沒賣掉）就是「⚡ Taycan 電費」這種；沒車是 nil（第三張改放第三多的分類）
    var vehicleCard: WidgetVehicleCard? = nil
    /// 一按就記的常記範本：近 60 天「同名稱＋同金額＋同分類（＋同車）」出現 ≥3 次，最多 4 個，
    /// 次數多到少。沒有符合的是空陣列（小工具寫說明）；nil＝v1 舊檔
    var templates: [WidgetQuickTemplate]? = nil

    // MARK: [v3] 以下也是選填（v2 舊檔沒有）

    /// 沒賣掉的車，依 FinanceStore.vehicles 的順序，各帶它可以記的車子分類
    ///（VehicleVariableCategory.categories(for: powerType) 的順序）。記帳台按鈕、控制項「記到…」的選單。
    /// 沒有車是空陣列；nil＝v2 以前的舊檔（選單只有分類）
    var vehicleOptions: [WidgetVehicleOption]? = nil
}

extension WidgetMoneySnapshot {
    /// 這個時間點要顯示哪一天。比第一天還早（時鐘往回調、時區往回）就用第一天；
    /// 過了最後一天（跨月）回 nil，改顯示「11 月開始了」（hasEnded）。
    func day(at date: Date) -> WidgetMoneyDay? {
        if let hit = days.first(where: { $0.contains(date) }) { return hit }
        if let first = days.first, date < first.dayStart { return first }
        return nil
    }

    /// 已經過了快照裡最後一天（＝跨月了，v1 只能請使用者打開 App）
    func hasEnded(at date: Date) -> Bool {
        guard let last = days.last else { return true }
        return date >= last.dayEnd
    }

    /// 超過兩天沒更新：最下面一行改成 WidgetDateText.lastUpdated(generatedAt)
    func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(generatedAt) > WidgetFreshness.moneyStaleAfter
    }

    // MARK: [v2] 記帳台

    /// 記帳台右半要畫的卡有沒有資料（v1 舊檔沒有分類 → 右半寫「打開 LifeGood 一次」）
    var hasDeskData: Bool { categories != nil && topCategoryKeys != nil }

    func category(forKey key: String) -> WidgetCategory? {
        categories?.first(where: { $0.key == key })
    }

    /// 記帳台右半 2×2 的四張卡，依序：最常記的分類、第二多的分類、車子卡（沒車＝第三多的分類）、
    /// 「＋ 記一筆」（固定）。只挑、不算；網址一律 WidgetLink 組好。資料不夠時少於 4 張，
    /// 但「記一筆」一定在最後。
    func deskTiles() -> [WidgetDeskTile] {
        let keys = (topCategoryKeys ?? []).filter { category(forKey: $0) != nil }
        var tiles: [WidgetDeskTile] = []
        for key in keys.prefix(2) {
            if let c = category(forKey: key) { tiles.append(WidgetDeskTile.category(c)) }
        }
        if let car = vehicleCard {
            tiles.append(WidgetDeskTile.vehicle(car))
        } else if keys.count > 2, let c = category(forKey: keys[2]) {
            tiles.append(WidgetDeskTile.category(c))
        }
        tiles.append(WidgetDeskTile.addExpense)
        return tiles
    }

    // MARK: [v3] 記到哪裡、記帳台照設定挑卡

    /// 「記到哪裡」的全部選項：14 個變動分類（照 categories 的順序），再接每台車的每個車子分類
    ///（照 vehicleOptions 的順序）。v1／v2 舊檔沒有 vehicleOptions 時只有分類；沒有 categories 時只有車。
    /// 記帳台按鈕（WidgetDeskButtonEntity）、控制項「記到…」（WidgetRecordTargetEntity）的選單都從這裡來。
    func recordTargets() -> [WidgetRecordTarget] {
        var out: [WidgetRecordTarget] = []
        for c in categories ?? [] {
            out.append(WidgetRecordTarget(id: WidgetDeskChoice.categoryID(c.key), title: c.title, icon: c.icon,
                                          top: c.top, bottom: c.bottom, tint: c.tint,
                                          categoryKey: c.key, vehicleId: nil, vehicleCategoryKey: nil))
        }
        for v in vehicleOptions ?? [] {
            for cat in v.categories {
                out.append(WidgetRecordTarget(id: WidgetDeskChoice.vehicleID(v.vehicleId, cat.key),
                                              title: cat.title, icon: cat.icon,
                                              top: v.top, bottom: v.bottom, tint: v.tint,
                                              categoryKey: nil, vehicleId: v.vehicleId,
                                              vehicleCategoryKey: cat.key))
            }
        }
        return out
    }

    /// 用設定存的 id 找回那個選項；車子賣掉、刪掉（快照裡沒有了）回 nil
    func recordTarget(id: String) -> WidgetRecordTarget? {
        recordTargets().first { $0.id == id }
    }

    /// 記帳台右半的卡，照長按設定挑：choiceIDs[0…2] 是按鈕 1／2／3 存的 id
    ///（WidgetDeskButtonEntity.id；nil、"auto"、快照裡找不到的 id 都當「自動」）。
    ///
    /// • 指定的：說一句（紫）、新增收入（綠）、某個變動分類、某台車的某個車子分類
    /// • 自動的：照 deskTiles() 的挑法依序補（最常記的分類、車子卡……），已經被指定的同一個目的地跳過
    /// • 第 4 張固定「＋ 記一筆」
    /// 三格都自動時，結果（除了 id）跟 deskTiles() 一模一樣——升級後沒改設定的記帳台外觀不變。
    /// 回傳的 id 前面加了格子編號（「s0-cat-飲食」），同一個分類放兩格 ForEach 也不會撞 id。
    func deskTiles(choiceIDs: [String?]) -> [WidgetDeskTile] {
        let targets = recordTargets()
        var picked: [WidgetDeskTile?] = []
        for slot in 0..<WidgetDeskChoice.slotCount {
            let raw: String? = slot < choiceIDs.count ? choiceIDs[slot] : nil
            picked.append(Self.explicitDeskTile(raw, targets: targets))
        }
        var taken = Set<String>()
        for tile in picked {
            if let tile { taken.insert(tile.url.absoluteString) }
        }
        var pool: [WidgetDeskTile] = autoDeskPool().filter { !taken.contains($0.url.absoluteString) }
        var out: [WidgetDeskTile] = []
        for (slot, choice) in picked.enumerated() {
            var tile: WidgetDeskTile
            if let choice {
                tile = choice
            } else if !pool.isEmpty {
                tile = pool.removeFirst()
            } else {
                continue
            }
            tile.id = "s\(slot)-" + tile.id
            out.append(tile)
        }
        out.append(WidgetDeskTile.addExpense)
        return out
    }

    /// 自動格子的候選，照現在的挑法排：deskTiles() 的前三張（不含「記一筆」），
    /// 再接 topCategoryKeys 裡還沒出現的分類（指定的格子拿走了幾張，自動的才補得滿）
    private func autoDeskPool() -> [WidgetDeskTile] {
        var out: [WidgetDeskTile] = deskTiles().filter { $0.style != .add }
        var seen = Set<String>()
        for tile in out { seen.insert(tile.url.absoluteString) }
        for key in topCategoryKeys ?? [] {
            guard let c = category(forKey: key) else { continue }
            let tile = WidgetDeskTile.category(c)
            if seen.insert(tile.url.absoluteString).inserted {
                out.append(tile)
            }
        }
        return out
    }

    /// 一格的指定值 → 卡；自動（nil／"auto"）或找不到 → nil
    private static func explicitDeskTile(_ raw: String?, targets: [WidgetRecordTarget]) -> WidgetDeskTile? {
        guard let id = raw, id != WidgetDeskChoice.autoID else { return nil }
        if id == WidgetDeskChoice.voiceID { return WidgetDeskTile.voice }
        if id == WidgetDeskChoice.incomeID { return WidgetDeskTile.addIncome }
        guard let target = targets.first(where: { $0.id == id }) else { return nil }
        return WidgetDeskTile.target(target)
    }
}

// MARK: - [v2] 記帳台、一按就記用的資料

/// 一個變動分類的樣子。key 原封不動帶回網址（lifegood://add/expense?cat=<key>），App 用
/// VariableCategory(rawValue:) 還原——小工具裡不准寫任何分類的字面字串。
struct WidgetCategory: Codable, Equatable, Identifiable {
    /// VariableCategory.rawValue（「飲食」）
    var key: String
    /// 卡上的字（目前跟 key 一樣，「飲食」）
    var title: String
    /// SF Symbol（VariableCategory.icon，「fork.knife」）
    var icon: String
    /// App 分類卡的兩色漸層與分類色（MoneyArtTheme.of(_:) 的 top／bottom／tint，0xRRGGBB）
    var top: UInt32
    var bottom: UInt32
    var tint: UInt32

    var id: String { key }
}

/// 記帳台第三張卡「⚡ Taycan 電費」：點了開新增支出、已選汽車／電費、連到那台車、度數欄看得到
///（跟從車子頁記電費一樣，App 用 AddVehicleView.makeVariablePreset）。
struct WidgetVehicleCard: Codable, Equatable {
    var vehicleId: UUID
    /// 「Taycan」
    var vehicleName: String
    /// VehicleVariableCategory.rawValue（「電費」）
    var categoryKey: String
    /// 卡上的字「Taycan 電費」（App 組好）
    var title: String
    /// SF Symbol（VehicleVariableCategory.icon，「bolt.fill」）
    var icon: String
    /// 青綠漸層（樣稿：0x7FE3D0 → 0x1A9C8C，分類色 0x138A7E）
    var top: UInt32
    var bottom: UInt32
    var tint: UInt32
}

/// 一按就記的常記範本（例「7-11 咖啡 NT$65」）。按鈕把它原樣變成一筆 QuickRecordEntry。
struct WidgetQuickTemplate: Codable, Equatable, Identifiable {
    /// 穩定的 id（makeId；同一組名稱＋金額＋分類＋車，每次寫快照都一樣）
    var id: String
    /// 「7-11 咖啡」（那幾筆支出的名稱，去頭尾空白）
    var title: String
    /// 65（台幣；小工具不拿來算，只原樣寫進收件匣）
    var amount: Double
    /// 「NT$65」（App 組好；隱藏金額時小工具換成 WidgetHideAmounts.mask）
    var amountText: String
    /// VariableCategory.rawValue
    var categoryKey: String
    /// 連到哪台車（汽車分類的範本）；沒有是 nil
    var vehicleId: UUID? = nil
    /// VehicleVariableCategory.rawValue（有車才有）
    var vehicleCategoryKey: String? = nil
    /// SF Symbol：有車用車子分類的圖示，否則用變動分類的圖示
    var icon: String
    var top: UInt32
    var bottom: UInt32
    var tint: UInt32
    /// 近 60 天記了幾次（排序用，v3 選單會顯示）
    var count: Int

    /// 範本 id 的組法：分類｜車｜車子分類｜名稱｜金額（以分為單位的整數）。只有 App 會呼叫。
    static func makeId(title: String, amount: Double, categoryKey: String,
                       vehicleId: UUID?, vehicleCategoryKey: String?) -> String {
        let cents = amount.isFinite ? Int((amount * 100).rounded()) : 0
        let car = vehicleId?.uuidString ?? "-"
        let carCat = vehicleCategoryKey ?? "-"
        return [categoryKey, car, carCat, title, String(cents)].joined(separator: "|")
    }
}

/// 記帳台右半一張卡（WidgetMoneySnapshot.deskTiles() 組，不存檔）
struct WidgetDeskTile: Equatable, Identifiable {
    enum Style: Equatable {
        /// 分類卡（App 分類卡的漸層＋白色圖示）
        case category
        /// 車子卡（青綠漸層）
        case vehicle
        /// 「＋ 記一筆」（白 78% 底、App 藍圖示；顏色由小工具的 palette 決定，不用 top／bottom）
        case add
        /// [v3] 🎤 說一句（紫漸層，跟 App 的 AI 麥克風同色；畫法同分類卡）
        case voice
        /// [v3] 新增收入（綠漸層，跟 App「新增收入」按鈕同色；畫法同分類卡）
        case income
    }

    var id: String
    var style: Style
    var title: String
    var icon: String
    var top: UInt32
    var bottom: UInt32
    var tint: UInt32
    /// 點了開哪裡（新增支出，帶 src=widget）
    var url: URL

    static func category(_ c: WidgetCategory) -> WidgetDeskTile {
        WidgetDeskTile(id: "cat-" + c.key, style: .category, title: c.title, icon: c.icon,
                       top: c.top, bottom: c.bottom, tint: c.tint,
                       url: WidgetLink.addExpense(categoryKey: c.key))
    }

    static func vehicle(_ v: WidgetVehicleCard) -> WidgetDeskTile {
        WidgetDeskTile(id: "car-" + v.vehicleId.uuidString, style: .vehicle, title: v.title, icon: v.icon,
                       top: v.top, bottom: v.bottom, tint: v.tint,
                       url: WidgetLink.addExpense(vehicleId: v.vehicleId, vehicleCategoryKey: v.categoryKey))
    }

    /// 「＋ 記一筆」：空白的新增支出
    static let addExpense = WidgetDeskTile(id: "add", style: .add, title: "記一筆", icon: "plus",
                                           top: 0xFFFFFF, bottom: 0xFFFFFF, tint: 0x2F6FE0,
                                           url: WidgetLink.addExpense())

    // MARK: [v3]

    /// 🎤 說一句：打開 App 直接開始聽（lifegood://add/expense?voice=1&src=widget）。
    /// 顏色＝App 浮動麥克風的漸層（MainTabView aiMicButton：rgb(0.55,0.35,0.95) → rgb(0.40,0.20,0.85)）
    static let voice = WidgetDeskTile(id: WidgetDeskChoice.voiceID, style: .voice, title: "說一句",
                                      icon: "mic.fill", top: 0x8C59F2, bottom: 0x6633D9, tint: 0x6633D9,
                                      url: WidgetLink.voiceRecord)

    /// 新增收入（lifegood://add/income?src=widget）。
    /// 顏色＝App FAB「新增收入」的漸層（rgb(0.16,0.74,0.50) → rgb(0.07,0.50,0.38)）
    static let addIncome = WidgetDeskTile(id: WidgetDeskChoice.incomeID, style: .income, title: "新增收入",
                                          icon: "banknote.fill", top: 0x29BD80, bottom: 0x128061, tint: 0x128061,
                                          url: WidgetLink.addIncome)

    /// 「記到哪裡」的一個選項 → 卡（分類卡或車子卡；網址 WidgetRecordTarget.url）
    static func target(_ t: WidgetRecordTarget) -> WidgetDeskTile {
        WidgetDeskTile(id: t.id, style: t.isVehicle ? .vehicle : .category, title: t.title, icon: t.icon,
                       top: t.top, bottom: t.bottom, tint: t.tint, url: t.url)
    }
}

// MARK: - [v3] 記到哪裡（記帳台按鈕、控制項「記到…」）

/// 一台沒賣掉的車與它可以記的車子分類（App 寫進 money 快照）
struct WidgetVehicleOption: Codable, Equatable, Identifiable {
    var vehicleId: UUID
    /// 「Taycan」（App 去頭尾空白；空的寫「車子」）
    var name: String
    /// VehicleVariableCategory.categories(for: 這台車的 powerType)，照那個順序
    var categories: [WidgetVehicleCategoryOption]
    /// 青綠漸層（跟 WidgetVehicleCard 同一組：0x7FE3D0 → 0x1A9C8C，分類色 0x138A7E）
    var top: UInt32
    var bottom: UInt32
    var tint: UInt32

    var id: UUID { vehicleId }
}

/// 一台車的一個車子分類
struct WidgetVehicleCategoryOption: Codable, Equatable, Identifiable {
    /// VehicleVariableCategory.rawValue（「電費」）：原樣帶回網址 vcat=
    var key: String
    /// 選單、卡、控制項上的字（App 組好：「Taycan 電費」）
    var title: String
    /// SF Symbol（VehicleVariableCategory.icon：電費 bolt.fill、停車 parkingsign.circle…）
    var icon: String

    var id: String { key }
}

/// 「記到哪裡」的一個選項：一個變動分類，或一台車＋一個車子分類。
/// 不存檔，由 money 快照組（WidgetMoneySnapshot.recordTargets()）。點了開新增支出、分類或車子帶好、數字鍵盤跳出。
struct WidgetRecordTarget: Equatable, Identifiable {
    /// 設定存的 id：分類「cat:飲食」、車子「car:<車 UUID>:電費」（WidgetDeskChoice.categoryID／vehicleID）
    var id: String
    /// 「飲食」「Taycan 電費」
    var title: String
    var icon: String
    var top: UInt32
    var bottom: UInt32
    var tint: UInt32
    /// 變動分類 key（VariableCategory.rawValue）；車子的是 nil
    var categoryKey: String?
    /// 車子的才有
    var vehicleId: UUID?
    /// VehicleVariableCategory.rawValue；車子的才有
    var vehicleCategoryKey: String?

    var isVehicle: Bool { vehicleId != nil }

    /// lifegood://add/expense?cat=…／?vehicle=…&vcat=…（&src=widget）——跟 v2 記帳台的卡同一種網址
    var url: URL {
        WidgetLink.addExpense(categoryKey: categoryKey, vehicleId: vehicleId,
                              vehicleCategoryKey: vehicleCategoryKey)
    }
}

/// 記帳台按鈕 1／2／3 的選擇。長按設定存的是 id 字串（WidgetDeskButtonEntity.id），這裡是 id 的規則。
enum WidgetDeskChoice {
    /// 可以換的格子數（第 4 格「＋ 記一筆」固定，J:208）
    static let slotCount = 3
    /// 自動：照現在的挑法（預設）
    static let autoID = "auto"
    /// 🎤 說一句
    static let voiceID = "voice"
    /// 新增收入
    static let incomeID = "income"

    /// 一個變動分類：「cat:飲食」
    static func categoryID(_ key: String) -> String {
        "cat:" + key
    }

    /// 一台車的一個車子分類：「car:<UUID>:電費」
    static func vehicleID(_ vehicleId: UUID, _ categoryKey: String) -> String {
        "car:" + vehicleId.uuidString + ":" + categoryKey
    }
}

// MARK: - 今天（life_v1.json）

/// 時間軸上的一站＋小工具多要的兩樣東西。stop 原封不動是靈動島那一份（同一段程式挑的）。
struct WidgetStop: Codable, Equatable, Identifiable {
    var stop: TimelineStop
    /// 地點：個人事件、系統行事曆的地點，旅遊景點的地址；部屬會議沒有地點欄位，是空字串
    var location: String
    /// StandBy（背景被拿掉）時代替主題的字，不含任何人名：
    /// 部屬會議「部屬會議」、個人事件「會議／事務」、系統行事曆「系統行事曆」、
    /// 旅遊景點照樣寫站名（景點算低隱私），過夜那一站寫「住宿」
    var lockTitle: String

    var id: String { stop.id }

    /// [v2] 鎖定畫面、StandBy 用的標題（使用者決定 2：項目名稱、會議主題可以放，人名不放）。
    /// 會議、我的行事曆、系統行事曆寫主題（stop.title）；旅遊景點寫 lockTitle（過夜那站「住宿」）；
    /// 主題是空的退回 lockTitle。**stop.owner（部屬姓名）在這些地方一律不寫。**
    var lockedSurfaceTitle: String {
        if stop.kind == .trip { return lockTitle }
        let t = stop.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? lockTitle : t
    }
}

/// 全天的事的種類。宣告順序就是優先序（生日最優先）。
enum WidgetAllDayKind: String, Codable {
    case birthday
    case anniversary
    /// 兼任職務的重要日期（尾牙：場勘日）與卸任日
    case sideRole
    case milestone
    /// 我的行事曆裡的全日事件（durationMinutes == 0）
    case personal
    /// 系統行事曆的全日事件
    case appleCalendar
    /// [v25.565] 財富：卡費截止／扣款、交割、卡片到期、開戶日（財富 v4，judge §6.5）。
    /// 主畫面寫卡名不寫金額；鎖定畫面只寫類別字（lockTitle「卡費」「交割」「卡片到期」「財富」）
    case wealth

    /// 越小越優先：生日＞結婚紀念日＞兼任職務＞里程碑＝財富＞其他全日事件
    var priority: Int {
        switch self {
        case .birthday:      return 0
        case .anniversary:   return 1
        case .sideRole:      return 2
        case .milestone:     return 3
        case .wealth:        return 3
        case .personal:      return 4
        case .appleCalendar: return 5
        }
    }
}

/// 一件全天的事（生日、紀念日…）。App 已經依 priority 排好。
struct WidgetAllDayItem: Codable, Equatable, Identifiable {
    /// 跟我的行事曆同一套 id（「bd-<UUID>」「anniv-<UUID>」「ms-<UUID>」「srkd-<UUID>」…）
    var id: String
    var kind: WidgetAllDayKind
    /// 中型膠囊、小型「今天沒排行程」的第二行：「媽媽 62 歲生日」「尾牙：場勘日」
    var title: String
    /// 小型最下面一行（窄）：「媽媽生日」
    var shortTitle: String
    /// StandBy：不寫是誰——「家人生日」「結婚紀念日」「兼任職務」「里程碑」
    var lockTitle: String
    /// SF Symbol 名稱（生日 birthday.cake.fill、紀念日 heart.fill、兼任職務／里程碑 flag.fill…）
    var icon: String
}

struct WidgetLifeDay: Codable, Equatable, Identifiable {
    /// 「2026-10-13」
    var dayKey: String
    var dayStart: Date
    var dayEnd: Date
    /// 「10/13 週二」
    var dateText: String
    /// 「10/13」（今天沒排行程時的大字）
    var shortDateText: String
    /// 這一天全部有時間的行程，依開始時間排序。跟靈動島同一段程式挑的（TodayAgenda），
    /// 但不裁成 8 站。已經離開的旅遊景點不在裡面（跟靈動島一樣）。
    var stops: [WidgetStop]
    /// 全天的事，已依 WidgetAllDayKind.priority 排好；沒有是空陣列
    var allDay: [WidgetAllDayItem]
    /// 中型右上角手寫問候，兩行：["Have a nice", "Tuesday!"]。空陣列＝不寫
    var greeting: [String]
    /// 這一天是旅遊期間、部屬會議已經被藏起來（stops 裡本來就沒有，這裡只是告訴小工具）
    var hidesMeetings: Bool
    /// 隔天的第一場（「今天的行程結束了／明天 08:30／早會」用）；隔天沒有行程是 nil
    var nextDayFirstStop: WidgetStop?
    /// [v3] 隔天**每一種**行程的第一場（最多 4 個，依開始時間排好；隔天沒有行程是空陣列）。
    /// 「今天」設定關掉某幾種時，「明天 08:30 …」要從留下的種類挑（WidgetLifeSnapshot.filtered(kinds:)）。
    /// v2 以前的舊檔是 nil
    var nextDayFirstStops: [WidgetStop]? = nil

    var id: String { dayKey }

    func contains(_ date: Date) -> Bool { dayStart <= date && date < dayEnd }

    /// 進行中那一場（跟靈動島 currentStop 同一個判斷）
    func currentStop(at now: Date) -> WidgetStop? {
        stops.first { $0.stop.start <= now && now < $0.stop.end }
    }

    /// 下一場（還沒開始的第一場）
    func nextStop(at now: Date) -> WidgetStop? {
        stops.first { $0.stop.start > now }
    }

    /// 還沒結束的（進行中＋還沒開始），依開始時間
    func remainingStops(at now: Date) -> [WidgetStop] {
        stops.filter { $0.stop.end > now }
    }

    // MARK: [v3]

    /// 旅途中的下一站：還沒開始的第一個旅遊景點（kind == .trip）；今天的景點都開始了是 nil
    func nextTripStop(at now: Date) -> WidgetStop? {
        stops.first { $0.stop.kind == .trip && $0.stop.start > now }
    }

    /// 今天還沒走完的旅遊景點（進行中＋還沒開始），依開始時間
    func remainingTripStops(at now: Date) -> [WidgetStop] {
        stops.filter { $0.stop.kind == .trip && $0.stop.end > now }
    }

    /// 只留 kinds 這幾種行程（「今天」小工具的設定）。
    /// 全天的事：我的行事曆／系統行事曆的全日事件跟著那一種藏；生日、紀念日、兼任職務、里程碑照常（WidgetAllDayKind.stopKind）。
    /// 隔天的第一場：從 nextDayFirstStops 挑留下的種類；舊檔沒有這欄時，原本那一場的種類有留才保留。
    /// ⚠️ 快照裡「隔天那一份」也在的話，WidgetLifeSnapshot.filtered(kinds:) 會用它重挑（比較準），小工具請用那一支。
    func filtered(kinds: Set<TimelineStopKind>) -> WidgetLifeDay {
        var d = self
        d.stops = stops.filter { kinds.contains($0.stop.kind) }
        d.allDay = allDay.filter { item in
            guard let k = item.kind.stopKind else { return true }
            return kinds.contains(k)
        }
        if let firsts = nextDayFirstStops {
            let kept: [WidgetStop] = firsts.filter { kinds.contains($0.stop.kind) }
            d.nextDayFirstStops = kept
            d.nextDayFirstStop = kept.first
        } else if let first = nextDayFirstStop, !kinds.contains(first.stop.kind) {
            d.nextDayFirstStop = nil
        }
        return d
    }
}

extension WidgetAllDayKind {
    /// [v3] 「今天」設定關掉某一種行程時，要跟著藏的全天的事屬於哪一種：
    /// 我的行事曆的全日事件跟「我的行事曆」、系統行事曆的全日事件跟「系統行事曆」；
    /// 生日、結婚紀念日、兼任職務、里程碑不屬於哪一種行程，是 nil（一律照常顯示）
    var stopKind: TimelineStopKind? {
        switch self {
        case .personal:      return .personal
        case .appleCalendar: return .appleCalendar
        case .birthday, .anniversary, .sideRole, .milestone, .wealth:
            return nil
        }
    }
}

struct WidgetLifeSnapshot: Codable, Equatable, WidgetSnapshotPayload {
    static let file = WidgetSnapshotFile.life
    static let schemaVersion = 1

    var schema: Int = WidgetLifeSnapshot.schemaVersion
    var generatedAt: Date
    var dataDay: String
    /// 過了這個時間（後天 00:00）整份不能用，顯示「打開 LifeGood 更新今天的行程」
    var validUntil: Date
    /// [0]＝今天、[1]＝明天
    var days: [WidgetLifeDay]

    // MARK: [v3] 以下選填（v2 以前的舊檔沒有）

    /// 旅行小工具：還沒回來的旅行（進行中＋接下來的），依出發時間排好，最多 3 趟。
    /// **不受 validUntil 管**：倒數、第幾天由小工具用日期算，App 好幾天沒開也照樣對。
    /// 沒有任何旅行是空陣列；nil＝舊檔
    var trips: [WidgetTrip]? = nil

    // MARK: [v5] 以下選填（v4 以前的舊檔沒有；App 一打開就補齊）

    /// 有沒有任何部屬（LifeStore.subordinates 非空）。nil＝舊檔。不是 true 時部屬今天寫「還沒有部屬資料」
    var hasTeam: Bool? = nil
    /// 部屬今天：[0]＝今天、[1]＝明天（跟 days 同兩天；受 validUntil 管）。沒有部屬時兩份都是空的；nil＝舊檔
    var team: [WidgetTeamDay]? = nil
    /// 廠區清單（部屬今天設定的選單）：Subordinate.plantArea 去頭尾空白、非空、去重、排好。nil＝舊檔
    var plantAreas: [String]? = nil
    /// 家庭待辦：[0]＝今天、[1]＝明天（受 validUntil 管）。nil＝舊檔
    var familyTasks: [WidgetFamilyTasksDay]? = nil
    /// 接下來的倒數（結婚紀念日、家人生日、兼任職務重要日期），依日期排好。
    /// **不受 validUntil 管**：存的是「那一天 00:00」，小工具只算差幾天。nil＝舊檔
    var countdowns: [WidgetCountdown]? = nil

    // MARK: [健康 v7b] 以下選填（v25.557 以前的舊檔沒有；App 一打開就補齊）

    /// 「今天（大）」最下面那一行運動：[0]＝今天、[1]＝明天（跟 days 同兩天；受 validUntil 管）。
    /// 字由 App 組好（WorkoutFacts.widgetWorkoutDays）；那一天沒什麼好寫的 text 是空字串。nil＝舊檔。
    /// 不受「今天」長按設定（顯示哪幾種行程）影響：filtered(kinds:) 只篩 days
    var workout: [WidgetWorkoutDay]? = nil
}

// MARK: - [v3] 旅行

/// 一趟旅行。App 從 LifeStore.tripPlans 算好（封面不做）；小工具只用日期算「還有幾天」「第幾天」。
struct WidgetTrip: Codable, Equatable, Identifiable {
    var id: UUID
    /// 行程名（TripPlan.displayTitle 去頭尾空白；空的寫「旅行」）
    var title: String
    /// 出發時間（含時分，TripPlan.startDate）
    var startDate: Date
    /// 回程：最後一站離開的時間（TripPlan.endDate）
    var endDate: Date
    /// 出發那一天的 00:00（Calendar.current）
    var firstDay: Date
    /// 共幾天（TripPlan.dayCount，至少 1）
    var dayCount: Int
    /// 最後一天的隔天 00:00（＝firstDay＋dayCount 天）：過了這個時間就算回來了
    var afterLastDay: Date
    /// 行前準備「要帶去的東西」打勾幾條／共幾條（TripPlan.checklistProgress(.packing)）。
    /// packingTotal 是 0 就不寫「行李 8/15」
    var packingDone: Int
    var packingTotal: Int
    /// 點了開那一趟（WidgetLink.trip(id) 的 absoluteString）
    var link: String

    var url: URL { URL(string: link) ?? WidgetLink.trip(id) }
}

/// 旅行小工具這一刻要畫哪一種（WidgetLifeSnapshot.tripPhase(at:)）
enum WidgetTripPhase: Equatable {
    /// 沒有下一趟（舊檔、沒有旅行、都回來了）：「還沒有排下一趟旅行」。
    /// 不叫 none：跟 Optional.none 撞名會被編譯器警告、用錯
    case noTrip
    /// 還沒出發。daysUntil＝今天到出發那天差幾天（至少 1；出發那天就算旅途中第 1 天）
    case upcoming(WidgetTrip, daysUntil: Int)
    /// 旅途中。day＝第幾天（1 起算，已夾在 1…dayCount）
    case during(WidgetTrip, day: Int)
}

extension WidgetLifeSnapshot {
    /// 這個時間點要顯示哪一天；過期回 nil。比第一天還早就用第一天。
    func day(at date: Date) -> WidgetLifeDay? {
        guard date < validUntil else { return nil }
        if let hit = days.first(where: { $0.contains(date) }) { return hit }
        if let first = days.first, date < first.dayStart { return first }
        return nil
    }

    func isExpired(at date: Date) -> Bool { date >= validUntil }

    /// 中型右下角要不要寫「10:02 更新」
    func showsUpdatedAt(at date: Date) -> Bool {
        date.timeIntervalSince(generatedAt) > WidgetFreshness.lifeShowUpdatedAfter
    }

    // MARK: [v3]

    /// 四種行程全部（「今天」設定四個開關都開）
    static let allStopKinds: Set<TimelineStopKind> = [.meeting, .personal, .appleCalendar, .trip]

    /// 「今天」小工具的設定：只留 kinds 這幾種行程（每一天都篩，見 WidgetLifeDay.filtered(kinds:)）。
    /// 四種都留＝原樣回傳（跟 v2 一模一樣）。快照裡有隔天那一份的，「明天的第一場」直接從隔天那一份
    ///（篩過的）挑，最準；最後一天才靠 nextDayFirstStops。trips 不受影響。
    /// provider 先篩再排 timeline（倒數、換場都照篩過的算）。
    func filtered(kinds: Set<TimelineStopKind>) -> WidgetLifeSnapshot {
        if kinds.isSuperset(of: Self.allStopKinds) { return self }
        var out = self
        var newDays: [WidgetLifeDay] = []
        for (i, day) in days.enumerated() {
            var d = day.filtered(kinds: kinds)
            if i + 1 < days.count {
                d.nextDayFirstStop = days[i + 1].stops.first { kinds.contains($0.stop.kind) }
            }
            newDays.append(d)
        }
        out.days = newDays
        return out
    }

    /// 旅行小工具這一刻要畫哪一種。trips 已依出發時間排好；挑第一趟還沒回來的（afterLastDay > now）。
    /// 出發那一天 00:00 起就算旅途中第 1 天（跟 App「旅遊期間」以天為單位的判斷一樣，LifeStore.tripPlan(covering:)）。
    /// 日差是整數、不是金額，小工具可以算（主控定案）。
    func tripPhase(at now: Date) -> WidgetTripPhase {
        let list: [WidgetTrip] = trips ?? []
        guard let trip = list.first(where: { $0.afterLastDay > now }) else { return .noTrip }
        if now < trip.firstDay {
            let n = WidgetDateText.daysFrom(now, to: trip.firstDay)
            return .upcoming(trip, daysUntil: max(1, n))
        }
        let day = WidgetDateText.daysFrom(trip.firstDay, to: now) + 1
        let total = max(trip.dayCount, 1)
        return .during(trip, day: min(max(day, 1), total))
    }
}

// MARK: - [v5] 部屬今天（life_v1.json 的 team）
//
// App 用 TeamDay（LifeGood/Models/TeamDay.swift：從部屬總覽抽出來的同一套判斷——當日請假、
// 未完成任務、逾期紅字、報告逾期）算好今天、明天各一份；名字、假別時數、班別字、「逾期 2 天」全部是 App 寫的字。
// 小工具只做三件事：照日期挑那一份（WidgetLifeSnapshot.teamDay(at:)）、照廠區篩、數人頭與排序
// （WidgetTeamDay.summary(plantArea:)）。
// 隱私（使用者決定）：鎖定畫面、StandBy、控制中心**不准畫任何名字**——只准用數字字
// （WidgetTeamCell.text、WidgetTeamSummary.countsLine／shiftsLine／taskLine／overdueBadge）；
// 名字（allNames／shortNames／leaveDetailText／birthdayText／WidgetTeamTask.name）只准畫在主畫面，
// 而且主畫面的名字可以關（設定「顯示名字」）、假別預設不畫（「顯示假別」）。

/// 一個人：請假名單、某一班的名單
struct WidgetTeamPerson: Codable, Equatable, Identifiable {
    /// 部屬 UUID
    var subId: UUID
    /// 「李大華」（App 去頭尾空白；空的寫「未命名」）
    var name: String
    /// 廠區（Subordinate.plantArea 去頭尾空白；空字串＝未分廠區）
    var plantArea: String
    /// 只有請假名單有：假別與時數「特休」「病假 4 小時」「4 小時」（同一人同一天兩筆用「、」接；
    /// 都沒填寫「請假」）。班別名單是空字串
    var detail: String

    var id: UUID { subId }
}

/// 某一個班別那一天排了誰
struct WidgetTeamShift: Codable, Equatable, Identifiable {
    /// ShiftType.shortLabel：「大夜」「小夜」「假值」「日值」「時差」。App 寫，小工具不寫死班別的字。
    /// 「休」（restDay）不寫進來；那一天沒有人的班別也不寫進來
    var label: String
    /// ShiftType.allCases 的位置（人數一樣時照這個排）
    var order: Int
    /// 那一天這一班的人（照部屬清單的順序）
    var people: [WidgetTeamPerson]

    var id: String { label }
}

/// 一件逾期、或這一天到期的部屬任務（中型下面那兩條；點了開那件任務的卡片）
struct WidgetTeamTask: Codable, Equatable, Identifiable {
    var subId: UUID
    var taskId: UUID
    /// 部屬名字（主畫面「顯示名字」開著才畫）
    var name: String
    /// 主題（空的寫「未命名任務」，同部屬總覽）
    var topic: String
    /// 到期那天 00:00（dueDate ?? date，同部屬總覽「未完成任務」的排序鍵）
    var dueDay: Date
    var plantArea: String
    /// 逾期（跟部屬總覽的紅字同一個判斷 TeamDay.isOverdue：有截止時間、而且已經過了）
    var isOverdue: Bool
    /// 到期那天就是這一天、而且還沒逾期
    var isDueToday: Bool
    /// 逾期幾天（到期那天到這一天差幾個日曆天；沒逾期是 0）
    var overdueDays: Int
    /// 右邊的字（App 寫）：「逾期 2 天」；截止時間今天已經過了「已逾期」；今天到期「今天」
    var dueText: String
    /// lifegood://life/team/task?sub=<UUID>&task=<UUID>&src=widget（WidgetLink.teamTask 的 absoluteString）
    var link: String

    var id: UUID { taskId }
    var url: URL { URL(string: link) ?? WidgetLink.teamTask(subId: subId, taskId: taskId) }
}

/// 部屬生日（只算部屬；組織人員沒有廠區、不放）
struct WidgetTeamBirthday: Codable, Equatable, Identifiable {
    var subId: UUID
    var name: String
    var plantArea: String
    /// 0＝這一份的那一天、1＝隔天
    var dayOffset: Int

    var id: String { subId.uuidString + "-" + String(dayOffset) }

    /// 「今天 王小明生日」「明天 王小明等 2 人生日」（list 要是同一天的）；空的回 nil。**只准畫在主畫面**
    static func text(_ list: [WidgetTeamBirthday]) -> String? {
        guard let first = list.first else { return nil }
        let when = first.dayOffset == 0 ? "今天 " : "明天 "
        if list.count == 1 { return when + first.name + "生日" }
        return when + first.name + "等 " + String(list.count) + " 人生日"
    }
}

/// 一個廠區的件數。用**全部**未完成任務算（tasks 只放前 20 件；畫面上的數字一律用這裡的）
struct WidgetTeamCounts: Codable, Equatable, Identifiable {
    /// 廠區；空字串＝未分廠區
    var plantArea: String
    /// 逾期的任務（WidgetTeamTask.isOverdue 同一個判斷）
    var overdueTasks: Int
    /// 這一天到期、還沒逾期
    var dueTodayTasks: Int
    /// 未完成（部屬總覽「未完成任務」的件數）
    var openTasks: Int
    /// 逾期的報告（部屬總覽「報告」區標「逾期」的：這一週以前、還沒完成）
    var overdueReports: Int

    var id: String { plantArea }
}

/// 部屬今天的一天（今天、明天各一份）
struct WidgetTeamDay: Codable, Equatable, Identifiable {
    /// 「2026-10-13」
    var dayKey: String
    var dayStart: Date
    var dayEnd: Date
    /// 「10/13 週二」
    var dateText: String
    /// 「10/13」
    var shortDateText: String
    /// 這一天請假的人（一人一筆，照請假開始時間；部屬總覽「當日請假」同一個判斷）
    var leaves: [WidgetTeamPerson]
    /// 這一天班表上有人的班別（不含「休」），照 ShiftType 順序；那一天請假的人不算（同班表格子只顯示假別）
    var shifts: [WidgetTeamShift]
    /// 逾期的在前（照部屬總覽「未完成任務」的順序：到期早的先）、再這一天到期的；
    /// 全部的前 20 件，再補每個廠區的前 2 件（篩廠區時才不會空掉）
    var tasks: [WidgetTeamTask]
    /// 每個廠區一筆（含未分廠區的空字串）；沒有部屬是空陣列
    var counts: [WidgetTeamCounts]
    /// 這一天（dayOffset 0）與隔天（1）生日的部屬
    var birthdays: [WidgetTeamBirthday]

    var id: String { dayKey }

    func contains(_ date: Date) -> Bool { dayStart <= date && date < dayEnd }
}

/// 三格裡的一格（「請假 2」＋名字）
struct WidgetTeamCell: Equatable, Identifiable {
    /// 「leave」或「shift-大夜」
    var id: String
    /// 「請假」「大夜」
    var label: String
    var people: [WidgetTeamPerson]
    var isLeave: Bool
    /// 排序用（請假 -1、班別照 ShiftType 順序）
    var order: Int

    var count: Int { people.count }
    /// 「請假 2」「大夜 3」（只有數字：鎖定畫面、StandBy 可以用）
    var text: String { label + " " + String(people.count) }
    /// 名字全寫：「李大華・陳美玲」；沒有人是空字串。**只准畫在主畫面**
    var allNames: String { people.map { $0.name }.joined(separator: "・") }
    /// 放不下時：「張大明 等 3 人」；一個人就是名字；沒有人是空字串。**只准畫在主畫面**
    var shortNames: String {
        guard let first = people.first else { return "" }
        if people.count == 1 { return first.name }
        return first.name + " 等 " + String(people.count) + " 人"
    }
}

/// 部屬今天這一刻要畫的東西（照廠區篩過）。數字字可以上鎖定畫面；名字只准主畫面
struct WidgetTeamSummary: Equatable {
    /// 最多幾格（請假＋兩個班別）
    static let maxCells = 3
    /// 中型下面最多幾條任務
    static let taskRowLimit = 2

    /// 「10/13 週二」（中型「部屬・10/13 週二」）
    var dateText: String
    /// 「10/13」（小型「部屬 10/13」）
    var shortDateText: String
    /// 最多三格：請假一定第一格（0 人也有），再來這一天有人的班別，人數多到少（同數照 ShiftType 順序）
    var cells: [WidgetTeamCell]
    /// 請假的人（＝cells[0].people）
    var leaves: [WidgetTeamPerson]
    var overdueTasks: Int
    var dueTodayTasks: Int
    var openTasks: Int
    var overdueReports: Int
    /// 中型下面的任務：逾期在前、再這一天到期，最多 2 條
    var taskRows: [WidgetTeamTask]
    /// 右上「今天 王小明生日」「明天 王小明生日」：今天的優先；都沒有是 nil。**只准畫在主畫面**
    var birthdayText: String?

    /// 「請假 2・大夜 3・小夜 2」（前 maxCells 格；鎖定畫面一行字用 2）
    func countsLine(maxCells: Int = WidgetTeamSummary.maxCells) -> String {
        cells.prefix(max(1, maxCells)).map { $0.text }.joined(separator: "・")
    }

    /// 小型第三行「大夜 3・小夜 2」；這一天沒有排班是空字串
    var shiftsLine: String {
        cells.filter { !$0.isLeave }.map { $0.text }.joined(separator: "・")
    }

    /// 「逾期 2・今天到期 3」（0 也寫）；includeReports 而且有逾期報告再接「・週報逾期 1」；
    /// 什麼都沒有（沒有未完成任務、沒有逾期報告）寫「都完成了」。前面的「任務 」由畫面加
    func taskLine(includeReports: Bool) -> String {
        if overdueTasks == 0 && dueTodayTasks == 0 && openTasks == 0 && overdueReports == 0 {
            return "都完成了"
        }
        var line = "逾期 " + String(overdueTasks) + "・今天到期 " + String(dueTodayTasks)
        if includeReports && overdueReports > 0 {
            line += "・週報逾期 " + String(overdueReports)
        }
        return line
    }

    /// 「今天（大）」③：只寫不是 0 的「逾期 2・今天到期 3」；都 0 回 nil（那半句不寫）
    var nonZeroTaskText: String? {
        var parts: [String] = []
        if overdueTasks > 0 { parts.append("逾期 " + String(overdueTasks)) }
        if dueTodayTasks > 0 { parts.append("今天到期 " + String(dueTodayTasks)) }
        return parts.isEmpty ? nil : parts.joined(separator: "・")
    }

    /// 小型最下面「逾期任務 2」（紅字＋字）；沒有逾期回 nil
    var overdueBadge: String? {
        overdueTasks > 0 ? "逾期任務 " + String(overdueTasks) : nil
    }

    /// 「顯示假別」開著時：「李大華 特休・陳美玲 病假 4 小時」；沒有人請假是空字串。**只准畫在主畫面**
    var leaveDetailText: String {
        leaves.map { p in p.detail.isEmpty ? p.name : p.name + " " + p.detail }.joined(separator: "・")
    }
}

extension WidgetTeamDay {
    /// 廠區篩選：filter 是 nil 或空字串＝全部
    static func inPlant(_ area: String, _ filter: String?) -> Bool {
        guard let f = filter, !f.isEmpty else { return true }
        return area == f
    }

    /// 照廠區篩、數人頭、排三格、挑兩條任務與生日（只數與排序，字都是 App 寫的）
    func summary(plantArea filter: String?) -> WidgetTeamSummary {
        let leavePeople: [WidgetTeamPerson] = leaves.filter { Self.inPlant($0.plantArea, filter) }
        var shiftCells: [WidgetTeamCell] = []
        for s in shifts {
            let people: [WidgetTeamPerson] = s.people.filter { Self.inPlant($0.plantArea, filter) }
            if !people.isEmpty {
                shiftCells.append(WidgetTeamCell(id: "shift-" + s.label, label: s.label,
                                                 people: people, isLeave: false, order: s.order))
            }
        }
        shiftCells.sort { a, b in
            if a.people.count != b.people.count { return a.people.count > b.people.count }
            return a.order < b.order
        }
        var cells: [WidgetTeamCell] = [
            WidgetTeamCell(id: "leave", label: "請假", people: leavePeople, isLeave: true, order: -1)
        ]
        cells.append(contentsOf: shiftCells.prefix(WidgetTeamSummary.maxCells - 1))

        var overdueN = 0
        var dueTodayN = 0
        var openN = 0
        var reportsN = 0
        for c in counts where Self.inPlant(c.plantArea, filter) {
            overdueN += c.overdueTasks
            dueTodayN += c.dueTodayTasks
            openN += c.openTasks
            reportsN += c.overdueReports
        }

        let mine: [WidgetTeamTask] = tasks.filter { Self.inPlant($0.plantArea, filter) }
        let ordered: [WidgetTeamTask] = mine.filter { $0.isOverdue } + mine.filter { $0.isDueToday }

        let bdays: [WidgetTeamBirthday] = birthdays.filter { Self.inPlant($0.plantArea, filter) }
        let todays: [WidgetTeamBirthday] = bdays.filter { $0.dayOffset == 0 }
        let picked: [WidgetTeamBirthday] = todays.isEmpty ? bdays.filter { $0.dayOffset == 1 } : todays

        return WidgetTeamSummary(dateText: dateText,
                                 shortDateText: shortDateText,
                                 cells: cells,
                                 leaves: leavePeople,
                                 overdueTasks: overdueN,
                                 dueTodayTasks: dueTodayN,
                                 openTasks: openN,
                                 overdueReports: reportsN,
                                 taskRows: Array(ordered.prefix(WidgetTeamSummary.taskRowLimit)),
                                 birthdayText: WidgetTeamBirthday.text(picked))
    }
}

// MARK: - [v5] 家庭待辦、倒數、「今天（大）」的列

/// 家庭待辦的一天（今天、明天各一份）
struct WidgetFamilyTasksDay: Codable, Equatable, Identifiable {
    var dayKey: String
    var dayStart: Date
    var dayEnd: Date
    /// 未完成、截止日（dueDate）在這一天
    var dueTodayCount: Int
    /// 未完成（全部）
    var openCount: Int

    var id: String { dayKey }

    func contains(_ date: Date) -> Bool { dayStart <= date && date < dayEnd }

    /// 「家庭待辦 今天到期 1」；今天沒有到期的寫「家庭待辦 未完成 4」；都 0 回 nil（不寫那半句）
    var line: String? {
        if dueTodayCount > 0 { return "家庭待辦 今天到期 " + String(dueTodayCount) }
        if openCount > 0 { return "家庭待辦 未完成 " + String(openCount) }
        return nil
    }
}

/// 一件倒數（「今天（大）」④）：結婚紀念日、家人生日、兼任職務重要日期。
/// App 算好「下一次是哪一天」（生日、紀念日 2/29 在平年算 2/28，同我的行事曆），小工具只算差幾天
struct WidgetCountdown: Codable, Equatable, Identifiable {
    /// ④ 只放這麼多天以內的（1…60 天；今天的在 ② 全天的事）
    static let horizonDays = 60

    /// 同我的行事曆的 id 前綴：「anniv-<UUID>」「bd-<UUID>」「srkd-<UUID>」
    var id: String
    /// .anniversary／.birthday／.sideRole
    var kind: WidgetAllDayKind
    /// 「結婚紀念日」「女兒 3 歲生日」「尾牙：場勘日」
    var title: String
    /// 下一次那天 00:00
    var date: Date
    /// SF Symbol：heart.fill／birthday.cake.fill／flag.fill
    var icon: String
    /// 點了去哪（v5：我的行事曆 WidgetLink.today(nil) 的 absoluteString）
    var link: String

    var url: URL { URL(string: link) ?? WidgetLink.today(nil) }
}

/// 「今天（大）」②③④ 的一列：圖示＋一句話＋點了去哪（字在 WidgetLifeSnapshot 的 today…／upcomingLines 組好）
struct WidgetLineItem: Equatable, Identifiable {
    var id: String
    /// SF Symbol
    var icon: String
    var text: String
    var url: URL
}

/// [健康 v7b] 「今天（大）」最下面那一行運動（一天一份，今天、明天各一份）。App 組好字（WorkoutFacts.widgetWorkoutDays），小工具只畫：
///   • 那一天有運動：最近那一趟「今天 晨跑 5.2 公里」「今天 胸推日・45 分鐘」，點了開那一趟的成果頁
///   • 沒有：這週的進度「這週跑了 14.6 公里・目標 20」「這週跑了 20.6 公里・達標」「新的一週・上週跑了 14.6 公里」
///     「這週請假・上週跑了 13.3 公里」，點了開健康頁
///   • 什麼都沒有（沒有任何運動紀錄、這週沒動也沒設目標、上週也沒有）：text 是空字串，那一天不畫
struct WidgetWorkoutDay: Codable, Equatable, Identifiable {
    var dayKey: String
    var dayStart: Date
    var dayEnd: Date
    /// SF Symbol：figure.run／figure.walk／figure.outdoor.cycle／figure.hiking／dumbbell.fill／figure.mixed.cardio
    var icon: String
    /// 主畫面的字；空字串＝這一天不畫
    var text: String
    /// 不寫這一趟名字的版本（名字可能是地點：「河濱晨跑」）：「今天 跑步 5.2 公里」或這週的進度。
    /// 背景被拿掉（當成 StandBy）時用；空字串＝不畫
    var privateText: String
    /// 點了去哪（WidgetLink.health(id) 的 absoluteString：有那一趟帶 id、這週的進度不帶）
    var link: String

    var id: String { dayKey }

    var url: URL { URL(string: link) ?? WidgetLink.health(nil) }

    func contains(_ date: Date) -> Bool { dayStart <= date && date < dayEnd }
}

extension WidgetLifeSnapshot {
    /// [健康 v7b] 這個時間點那一天的運動那一行；過期、舊檔回 nil；比第一天早用第一天（同 teamDay(at:)）
    func workoutDay(at date: Date) -> WidgetWorkoutDay? {
        guard date < validUntil, let list = workout else { return nil }
        if let hit = list.first(where: { $0.contains(date) }) { return hit }
        if let first = list.first, date < first.dayStart { return first }
        return nil
    }

    /// [健康 v7b] 「今天（大）」最下面那一行（圖示＋字＋網址）。privacy＝不寫這一趟的名字（privateText、點了只開健康頁）。
    /// 過期、舊檔、那一天沒字回 nil
    func workoutLine(at date: Date, privacy: Bool) -> WidgetLineItem? {
        guard let d = workoutDay(at: date) else { return nil }
        let text: String = privacy ? d.privateText : d.text
        guard !text.isEmpty else { return nil }
        let url: URL = privacy ? WidgetLink.health(nil) : d.url
        return WidgetLineItem(id: "workout-" + d.dayKey, icon: d.icon, text: text, url: url)
    }
}

extension WidgetLifeSnapshot {
    /// [v5] 這個時間點的部屬今天；過期、舊檔回 nil；比第一天早用第一天（同 day(at:)）
    func teamDay(at date: Date) -> WidgetTeamDay? {
        guard date < validUntil, let list = team else { return nil }
        if let hit = list.first(where: { $0.contains(date) }) { return hit }
        if let first = list.first, date < first.dayStart { return first }
        return nil
    }

    /// [v5] 部屬今天這一刻要畫的（照廠區篩；plantArea nil＝全部）。
    /// 沒有部屬（hasTeam 不是 true）、過期、舊檔回 nil——小工具先看 hasTeam、再看 isExpired 決定寫哪一句
    func teamSummary(at date: Date, plantArea: String?) -> WidgetTeamSummary? {
        guard hasTeam == true else { return nil }
        return teamDay(at: date)?.summary(plantArea: plantArea)
    }

    /// [v5] 這個時間點的家庭待辦；過期、舊檔回 nil
    func familyTasksDay(at date: Date) -> WidgetFamilyTasksDay? {
        guard date < validUntil, let list = familyTasks else { return nil }
        if let hit = list.first(where: { $0.contains(date) }) { return hit }
        if let first = list.first, date < first.dayStart { return first }
        return nil
    }

    /// [v5] now 之後 1…60 天內的倒數，前 limit 件（日期近到遠；countdowns 已排好）
    func upcomingCountdowns(at now: Date, limit: Int) -> [WidgetCountdown] {
        let list: [WidgetCountdown] = countdowns ?? []
        let hits: [WidgetCountdown] = list.filter { (c: WidgetCountdown) -> Bool in
            let n = WidgetDateText.daysFrom(now, to: c.date)
            return n >= 1 && n <= WidgetCountdown.horizonDays
        }
        return Array(hits.prefix(max(0, limit)))
    }

    /// [v5] 「今天（大）」② 今天誰特別的第一行：今天全天的事最多 2 件（家人生日、紀念日、兼任重要日期…，
    /// 點了開我的行事曆）；不滿 2 件時補今天生日的部屬；最後接明天生日的部屬一件。
    /// 明天的家人生日、紀念日不寫在這裡：④ 的倒數會寫「明天 媽媽 62 歲生日」，兩區才不會重複。
    /// includeTeam＝「今天」設定的「部屬會議」開著（關掉時部屬的生日也不寫）。過期回空陣列
    func todaySpecials(at now: Date, includeTeam: Bool) -> [WidgetLineItem] {
        guard let current = self.day(at: now) else { return [] }
        var out: [WidgetLineItem] = []
        for item in current.allDay.prefix(2) {
            out.append(WidgetLineItem(id: "ad-" + item.id, icon: item.icon, text: item.title,
                                      url: WidgetLink.today(nil)))
        }
        let teamToday: WidgetTeamDay? = (includeTeam && hasTeam == true) ? teamDay(at: now) : nil
        if out.count < 2, let t = teamToday,
           let text = WidgetTeamBirthday.text(t.birthdays.filter { $0.dayOffset == 0 }) {
            out.append(WidgetLineItem(id: "team-bd-0", icon: "birthday.cake.fill", text: text,
                                      url: WidgetLink.birthdays))
        }
        if let next = tomorrowBirthday(after: current, teamToday: teamToday) {
            out.append(next)
        }
        return out
    }

    /// 明天生日的部屬一件（部屬今天那一份的 dayOffset 1）。家人的明天生日交給 ④ 的倒數（「明天 媽媽 62 歲生日」），
    /// 不然同一個生日 ② ④ 各寫一次
    private func tomorrowBirthday(after current: WidgetLifeDay, teamToday: WidgetTeamDay?) -> WidgetLineItem? {
        guard let t = teamToday,
              let text = WidgetTeamBirthday.text(t.birthdays.filter { $0.dayOffset == 1 }) else { return nil }
        return WidgetLineItem(id: "team-bd-1", icon: "birthday.cake.fill", text: text,
                              url: WidgetLink.birthdays)
    }

    /// [v5] 「今天（大）」② 第二行：「部屬 請假 2・大夜 3・小夜 2」（全部廠區、只寫數字；點了開部屬總覽）。
    /// includeTeam false、沒有部屬、過期、舊檔回 nil
    func todayTeamLine(at now: Date, includeTeam: Bool) -> WidgetLineItem? {
        guard includeTeam, let s = teamSummary(at: now, plantArea: nil) else { return nil }
        return WidgetLineItem(id: "team-counts", icon: "person.2.fill", text: "部屬 " + s.countsLine(),
                              url: WidgetLink.team)
    }

    /// [v5] 「今天（大）」③ 要處理：「部屬任務 逾期 2・今天到期 3」（點了開部屬總覽）、
    /// 「家庭待辦 今天到期 1」或「家庭待辦 未完成 4」（點了開家庭）；都 0 的那半句不寫
    func todayTodos(at now: Date, includeTeam: Bool) -> [WidgetLineItem] {
        var out: [WidgetLineItem] = []
        if includeTeam, let s = teamSummary(at: now, plantArea: nil), let text = s.nonZeroTaskText {
            out.append(WidgetLineItem(id: "team-tasks", icon: "checklist", text: "部屬任務 " + text,
                                      url: WidgetLink.team))
        }
        if let f = familyTasksDay(at: now), let text = f.line {
            out.append(WidgetLineItem(id: "family-tasks", icon: "house.fill", text: text,
                                      url: WidgetLink.familyTasks))
        }
        return out
    }

    /// [v5] 「今天（大）」④ 接下來：下一趟旅行（「勇闖福岡親子行還有 38 天」；旅途中「… 第 2 天／共 7 天」；
    /// 點了開那一趟）＋最多 countdownLimit 件 60 天內的倒數（「結婚紀念日還有 23 天」；點了開我的行事曆）。
    /// 旅行、倒數不受 validUntil 管（日期不會錯）
    func upcomingLines(at now: Date, countdownLimit: Int) -> [WidgetLineItem] {
        var out: [WidgetLineItem] = []
        switch tripPhase(at: now) {
        case .noTrip:
            break
        case .upcoming(let trip, daysUntil: let n):
            out.append(WidgetLineItem(id: "trip-" + trip.id.uuidString, icon: "airplane",
                                      text: trip.title + "還有 " + String(n) + " 天", url: trip.url))
        case .during(let trip, day: let d):
            let total = max(trip.dayCount, 1)
            out.append(WidgetLineItem(id: "trip-" + trip.id.uuidString, icon: "airplane",
                                      text: trip.title + " 第 " + String(d) + " 天／共 " + String(total) + " 天",
                                      url: trip.url))
        }
        for c in upcomingCountdowns(at: now, limit: countdownLimit) {
            let n = WidgetDateText.daysFrom(now, to: c.date)
            // 明天的寫「明天 媽媽 62 歲生日」（② 不再寫明天的家人生日，這裡是唯一一處）
            let text: String = n == 1 ? "明天 " + c.title : c.title + "還有 " + String(n) + " 天"
            out.append(WidgetLineItem(id: "cd-" + c.id, icon: c.icon, text: text, url: c.url))
        }
        return out
    }
}

// MARK: - [v5] 小工具庫預覽用的樣本（寫死的展示字，人名都是假的；design_life.md §1 的範例日）

enum WidgetLifeSample {
    private static func uuid(_ text: String) -> UUID {
        UUID(uuidString: text) ?? UUID()
    }

    private static func person(_ id: String, _ name: String, _ plant: String, _ detail: String) -> WidgetTeamPerson {
        WidgetTeamPerson(subId: uuid(id), name: name, plantArea: plant, detail: detail)
    }

    /// 部屬今天：請假 2（李大華 特休、陳美玲 病假 4 小時）、大夜 3、小夜 2、任務逾期 2・今天到期 3、
    /// 週報逾期 1、明天 王小明生日。dayStart 是那一天 00:00；日期字寫死「10/13 週二」
    static func teamDay(dayStart: Date) -> WidgetTeamDay {
        let cal = Calendar.current
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 3600)
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: dayStart) ?? dayStart
        let leaves: [WidgetTeamPerson] = [
            person("5A1E0000-0000-4000-8000-000000000001", "李大華", "A", "特休"),
            person("5A1E0000-0000-4000-8000-000000000002", "陳美玲", "A", "病假 4 小時")
        ]
        let night: [WidgetTeamPerson] = [
            person("5A1E0000-0000-4000-8000-000000000003", "張大明", "A", ""),
            person("5A1E0000-0000-4000-8000-000000000004", "林小華", "A", ""),
            person("5A1E0000-0000-4000-8000-000000000005", "吳美君", "B", "")
        ]
        let evening: [WidgetTeamPerson] = [
            person("5A1E0000-0000-4000-8000-000000000006", "林志明", "B", ""),
            person("5A1E0000-0000-4000-8000-000000000007", "黃建國", "A", "")
        ]
        let wangId = uuid("5A1E0000-0000-4000-8000-000000000008")
        let leeId = uuid("5A1E0000-0000-4000-8000-000000000001")
        let task1Id = uuid("7A5C0000-0000-4000-8000-000000000001")
        let task2Id = uuid("7A5C0000-0000-4000-8000-000000000002")
        let tasks: [WidgetTeamTask] = [
            WidgetTeamTask(subId: leeId, taskId: task1Id, name: "李大華", topic: "冰水機 PM 紀錄",
                           dueDay: twoDaysAgo, plantArea: "A", isOverdue: true, isDueToday: false,
                           overdueDays: 2, dueText: "逾期 2 天",
                           link: WidgetLink.teamTask(subId: leeId, taskId: task1Id).absoluteString),
            WidgetTeamTask(subId: wangId, taskId: task2Id, name: "王小明", topic: "CDA 改善報告",
                           dueDay: dayStart, plantArea: "B", isOverdue: false, isDueToday: true,
                           overdueDays: 0, dueText: "今天",
                           link: WidgetLink.teamTask(subId: wangId, taskId: task2Id).absoluteString)
        ]
        let counts: [WidgetTeamCounts] = [
            WidgetTeamCounts(plantArea: "A", overdueTasks: 1, dueTodayTasks: 2, openTasks: 5, overdueReports: 1),
            WidgetTeamCounts(plantArea: "B", overdueTasks: 1, dueTodayTasks: 1, openTasks: 3, overdueReports: 0)
        ]
        let birthdays: [WidgetTeamBirthday] = [
            WidgetTeamBirthday(subId: wangId, name: "王小明", plantArea: "B", dayOffset: 1)
        ]
        return WidgetTeamDay(dayKey: WidgetDateText.dayKey(dayStart),
                             dayStart: dayStart,
                             dayEnd: dayEnd,
                             dateText: "10/13 週二",
                             shortDateText: "10/13",
                             leaves: leaves,
                             shifts: [WidgetTeamShift(label: "大夜", order: 0, people: night),
                                      WidgetTeamShift(label: "小夜", order: 1, people: evening)],
                             tasks: tasks,
                             counts: counts,
                             birthdays: birthdays)
    }

    /// 家庭待辦：今天到期 1、未完成 4
    static func familyTasksDay(dayStart: Date) -> WidgetFamilyTasksDay {
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(24 * 3600)
        return WidgetFamilyTasksDay(dayKey: WidgetDateText.dayKey(dayStart), dayStart: dayStart,
                                    dayEnd: dayEnd, dueTodayCount: 1, openCount: 4)
    }

    /// 倒數：結婚紀念日（23 天後）、女兒 3 歲生日（40 天後）
    static func countdowns(dayStart: Date) -> [WidgetCountdown] {
        let cal = Calendar.current
        let anniv = cal.date(byAdding: .day, value: 23, to: dayStart) ?? dayStart
        let bd = cal.date(byAdding: .day, value: 40, to: dayStart) ?? dayStart
        let link = WidgetLink.today(nil).absoluteString
        return [
            WidgetCountdown(id: "anniv-sample", kind: .anniversary, title: "結婚紀念日", date: anniv,
                            icon: "heart.fill", link: link),
            WidgetCountdown(id: "bd-sample", kind: .birthday, title: "女兒 3 歲生日", date: bd,
                            icon: "birthday.cake.fill", link: link)
        ]
    }

    /// [健康 v7b] 「今天（大）」最下面那一行運動：這週跑了 14.6 公里・目標 20（health/judge.md §8.0 的假資料）
    static func workoutDay(dayStart: Date) -> WidgetWorkoutDay {
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(24 * 3600)
        return WidgetWorkoutDay(dayKey: WidgetDateText.dayKey(dayStart), dayStart: dayStart, dayEnd: dayEnd,
                                icon: "figure.run", text: "這週跑了 14.6 公里・目標 20",
                                privateText: "這週跑了 14.6 公里・目標 20",
                                link: WidgetLink.health(nil).absoluteString)
    }

    /// 下一趟旅行：勇闖福岡親子行（38 天後出發，7 天）
    static func trip(dayStart: Date) -> WidgetTrip {
        let cal = Calendar.current
        let firstDay = cal.date(byAdding: .day, value: 38, to: dayStart) ?? dayStart
        let start = firstDay.addingTimeInterval(8.5 * 3600)
        let after = cal.date(byAdding: .day, value: 7, to: firstDay) ?? firstDay
        let id = uuid("791F0000-0000-4000-8000-000000000001")
        return WidgetTrip(id: id, title: "勇闖福岡親子行", startDate: start,
                          endDate: after.addingTimeInterval(-6 * 3600), firstDay: firstDay, dayCount: 7,
                          afterLastDay: after, packingDone: 8, packingTotal: 15,
                          link: WidgetLink.trip(id).absoluteString)
    }
}

// MARK: - [v2] 接下來要繳（bills_v1.json）

/// 一筆要繳（或要領回）的種類
enum WidgetBillKind: String, Codable {
    /// 記帳的固定支出（Netflix、中華電信）
    case fixed
    /// 房貸（每一段）
    case mortgage
    /// 車子的（車貸、停車月租、保險、保養…，VehicleFacts.upcoming）
    case vehicle
    /// 保費
    case premium
    /// 保單滿期（會領回來的錢）
    case maturity
    /// [v25.565] 信用卡卡費（一張卡一期一筆；刷這張卡的定期扣款併在裡面，記帳那幾筆不再另外列）
    case cardBill
    /// [v25.565] 股票交割（從交割銀行扣、或入帳）
    case settlement

    /// [v3] 鎖定畫面「下一筆要繳」關掉「顯示名稱」時的類別字（App 沒寫 WidgetBill.lockTitle 的舊檔才用）
    var label: String {
        switch self {
        case .fixed:    return "固定支出"
        case .mortgage: return "房貸"
        case .vehicle:  return "車子費用"
        case .premium:  return "保費"
        case .maturity: return "保單滿期"
        case .cardBill: return "卡費"
        case .settlement: return "交割"
        }
    }

    /// [v3] 記帳的固定支出（其他四種是理財的）
    var isLedger: Bool { self == .fixed }

    /// [v25.565] 財富的（卡費、交割）：鎖定畫面一律只寫類別字、不寫金額（judge §7.1；不管「顯示名稱」開不開）
    var isWealth: Bool { self == .cardBill || self == .settlement }
}

/// [v3] 「接下來要繳」的範圍（長按設定 WidgetBillScopeOption → 這個）
enum WidgetBillScope: String {
    /// 記帳＋理財合一張（預設，跟 v2 一樣）
    case all
    /// 只看記帳的固定支出（Netflix、中華電信…）
    case ledger
    /// 只看理財（房貸、車子、保費、滿期）
    case finance

    /// [v25.565] 卡費兩邊都算（記帳的定期扣款併在卡費裡；也是理財的負債）；交割算理財
    func includes(_ kind: WidgetBillKind) -> Bool {
        switch self {
        case .all:     return true
        case .ledger:  return kind.isLedger || kind == .cardBill
        case .finance: return !kind.isLedger
        }
    }
}

/// 某一天要扣的一筆。記帳的固定支出和理財的房貸、車貸、保費合成一份、已經去重。
///
/// 例：title「苗栗的家 房貸」 detail「第 8／480 期」 dueDate 10/20 00:00 amountText「NT$6.2萬」
///     title「Netflix」 detail「每月」 amountText「NT$390」
///     title「美元保單 滿期」 detail「可以領回」 amountText「+美金 3.6萬」 isIncome true
struct WidgetBill: Codable, Equatable, Identifiable {
    /// 每一次扣款一個：「<來源 id>@<yyyy-MM-dd>」（記帳「x-<支出 UUID>@…」、理財「<FinanceUpcoming.id>@…」）
    var id: String
    var kind: WidgetBillKind
    /// App 怎麼叫就怎麼叫（「Netflix」「苗栗的家 房貸」「Taycan 車貸」）
    var title: String
    /// 「第 26／60 期」「每月」「可以領回」；沒有是 nil
    var detail: String?
    /// 扣款日那一天的 00:00（Calendar.current）
    var dueDate: Date
    /// App 組好的金額字：台幣「NT$390」「NT$6.2萬」、外幣「美金 3,000」、保養「約 NT$3,000」、
    /// 滿期「+美金 3.6萬」。隱藏金額時小工具整個換成 WidgetHideAmounts.mask
    var amountText: String
    /// 會領回來的錢（保單滿期）：小工具畫綠字＋★
    var isIncome: Bool
    /// SF Symbol
    var icon: String
    /// 左邊色條：淺色、深色各一（0xRRGGBB）
    var tint: UInt32
    var tintDark: UInt32
    /// 點這一列開哪裡（WidgetLink 組好的網址字串）
    var link: String
    /// [v3] 鎖定畫面關掉「顯示名稱」時寫的類別字（App 組好：固定支出寫分類「訂閱服務」「電信費」…，
    /// 房貸「房貸」、車子「車貸／保養／車子費用」、保費「保費」、滿期「保單滿期」）。v2 舊檔是 nil
    var lockTitle: String? = nil

    /// link 解不開時退回固定支出頁
    var url: URL { URL(string: link) ?? WidgetLink.fixedExpenses }

    /// [v3] 鎖定畫面不顯示名稱時用的字：lockTitle，沒有（舊檔、空字串）就 kind.label
    var lockedTitle: String {
        let t = (lockTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? kind.label : t
    }
}

struct WidgetBillsSnapshot: Codable, Equatable, WidgetSnapshotPayload {
    static let file = WidgetSnapshotFile.bills
    static let schemaVersion = 1

    var schema: Int = WidgetBillsSnapshot.schemaVersion
    var generatedAt: Date
    /// 寫的當下是哪一天「2026-10-13」
    var dataDay: String
    /// 清單涵蓋到哪一天的 00:00（今天＋45 天）：App 兩週沒開也還有 30 天可以列
    var horizonEnd: Date
    /// 今天（含）到 horizonEnd 之前每一次扣款，依 dueDate、再依 title 排好
    var items: [WidgetBill]
}

extension WidgetBillsSnapshot {
    /// 中型列「接下來 30 天」
    static let listDays = 30

    /// 從 now 那一天（含）起 days 天內的（今天扣的也算）。過了的自己掉出去，不用 App 重寫。
    /// [v3] scope：長按設定的範圍（預設全部，跟 v2 一樣）
    func upcoming(at now: Date, days: Int = WidgetBillsSnapshot.listDays,
                  scope: WidgetBillScope = .all) -> [WidgetBill] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: days, to: today) else { return [] }
        return items.filter { $0.dueDate >= today && $0.dueDate < end && scope.includes($0.kind) }
    }

    /// 下一筆（不限 30 天，「30 天內沒有要扣的／下一筆 11/15 …」用）。[v3] scope 同上
    func next(at now: Date, scope: WidgetBillScope = .all) -> WidgetBill? {
        let today = Calendar.current.startOfDay(for: now)
        return items.first(where: { $0.dueDate >= today && scope.includes($0.kind) })
    }

    /// 過了 horizonEnd：清單已經不完整，只能請使用者打開 App
    func hasEnded(at now: Date) -> Bool { now >= horizonEnd }

    /// 超過兩天沒更新：最下面小字寫 WidgetDateText.lastUpdated(generatedAt)（跟還能花同一個門檻）
    func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(generatedAt) > WidgetFreshness.moneyStaleAfter
    }
}

// MARK: - [v4] 理財（finance_v1.json）

/// 理財四個小工具（股票今天、金價匯率、我的車、淨資產）的快照。App 用跟理財頁同一套算好、組好字
///（LifeGood/Models/WidgetFinanceBuilder.swift），小工具照著畫。
/// 股票、金價匯率小工具會自己上網抓新價（quotes_v1.json），抓不到才用這裡 App 的價（並寫是幾點的價）。
///
/// ⚠️ App 寫這份**只讀不寫**：不呼叫 FinanceOverviewData.build（它會寫每月淨資產紀錄，FinanceBoards.swift:72）。
struct WidgetFinanceSnapshot: Codable, Equatable, WidgetSnapshotPayload {
    static let file = WidgetSnapshotFile.finance
    static let schemaVersion = 1

    var schema: Int = WidgetFinanceSnapshot.schemaVersion
    var generatedAt: Date
    /// 寫的當下是哪一天「2026-10-13」（WidgetDateText.dayKey）
    var dataDay: String
    var stocks: WidgetStocksBlock
    var rates: WidgetRatesBlock
    /// 每台車：沒賣掉的照 FinanceStore.vehicles 的順序在前；賣掉但 45 天內還有要扣的接在後面
    var vehicles: [WidgetFinanceVehicle]
    /// 沒有任何資產、也沒有貸款是 nil（小工具寫「新增房地產、股票、保單或車子之後，這裡會算出淨資產」）
    var netWorth: WidgetNetWorth?
}

extension WidgetFinanceSnapshot {
    /// 快照是不是今天寫的。不是今天的：我的車、淨資產右下角寫 WidgetDateText.figuresOf(generatedAt)（「10/11 的數字」，橘字）
    func isFromToday(at now: Date) -> Bool {
        dataDay == WidgetDateText.dayKey(now)
    }

    /// 長按設定選的那一檔；nil、找不到（賣掉、刪掉）→ 市值最大那一檔（items 第一個）；沒有持股 nil
    func stock(id: String?) -> WidgetFinanceStock? {
        let all: [WidgetFinanceStock] = self.stocks.items
        if let id, let hit = all.first(where: { $0.id.uuidString == id }) { return hit }
        return all.first
    }

    /// 中型三檔：設定選的（照第 1／2／3 檔的順序、跳過找不到的與重複的），不夠的用市值大到小補滿 3 檔
    func threeStocks(ids: [String?]) -> [WidgetFinanceStock] {
        let all: [WidgetFinanceStock] = self.stocks.items
        var out: [WidgetFinanceStock] = []
        var seen = Set<UUID>()
        for raw in ids {
            guard let raw, let hit = all.first(where: { $0.id.uuidString == raw }) else { continue }
            if seen.insert(hit.id).inserted { out.append(hit) }
        }
        for s in all where out.count < WidgetStocksBlock.mediumCount {
            if seen.insert(s.id).inserted { out.append(s) }
        }
        return Array(out.prefix(WidgetStocksBlock.mediumCount))
    }

    /// 長按設定選的那一台；nil、找不到 → 第一台沒賣掉的（沒有就第一台）；沒有車 nil
    func vehicle(id: String?) -> WidgetFinanceVehicle? {
        if let id, let hit = vehicles.first(where: { $0.id.uuidString == id }) { return hit }
        return vehicles.first(where: { !$0.isSold }) ?? vehicles.first
    }
}

// MARK: [v4] 股票

/// 股票（持有中）
struct WidgetStocksBlock: Codable, Equatable {
    /// 持有中（沒賣掉、股數 > 0、有代號），依 App 的市值大到小，最多 maxItems 檔
    var items: [WidgetFinanceStock]
    /// 中型最下面一行：「今年股利 NT$3.9萬・最近 10/5 配息 NT$530」。
    /// 今年＝全部股票今年領的現金股利（StockBoardData.dividendsThisYear 同一個數）；
    /// 最近＝全部股票裡日期最晚的那一筆現金股利。只有一樣就只寫那一樣；兩樣都沒有 nil（不寫這行）。
    /// **不寫下次配息日、不猜**（App 只記已經領到的）
    var dividendLine: String?
    /// 隱藏金額版：「今年股利 NT$ ••••・最近 10/5 配息 NT$ ••••」（日期照寫）
    var dividendLineMasked: String?

    /// 快照最多放幾檔（設定選單、小工具上網抓價都從這裡挑）
    static let maxItems = 20
    /// 中型列幾檔
    static let mediumCount = 3
}

/// 一檔持有中的股票。價錢都是原幣別（美股＝美元），金額都是台幣。
struct WidgetFinanceStock: Codable, Equatable, Identifiable {
    var id: UUID
    /// App 的代號「2330」「VOO」
    var symbol: String
    /// 「台積電」（沒填名字用代號）
    var name: String
    /// 手寫英文名「TSMC」（StockScriptName.word；沒有寫 MoneyArtTheme.finStock.word「Stocks」）
    var script: String
    /// 小工具上網抓價要試的 Yahoo 代號，照順序試、第一個抓到的就用。跟 App 抓日線同一套
    ///（StockDailyHistory.suffixCandidates）：美股「VOO」；台股學過的「2330.TW」，沒學過的「6488.TW」「6488.TWO」兩個都放
    var yahooSymbols: [String]
    var isUS: Bool
    /// 股數（台股 1 張＝1000 股；Stock.shares）
    var shares: Double
    /// 「2 張」「3.2 股」（StockCardText.quantity(s, shares: s.shares)）
    var qtyText: String
    /// 均價（原幣別，Stock.purchasePrice）；0＝沒填（不寫「比均價」）
    var avgPrice: Double
    /// 換成台幣的係數：台股 1、美股＝App 的美金匯率（Stock.currencyFactor）。小工具重算市值只准乘這個
    var currencyFactor: Double
    /// App 存的現價（Stock.currentPrice，原幣別）；0＝還沒有報價
    var appPrice: Double
    /// App 的前一個交易日收盤（Stock.moneyPreviousClose(now:)）；不知道 nil
    var appPreviousClose: Double?
    /// App 最後一次報價成功更新這一檔的時間（AppQuoteClock）；v4 以前沒記過是 nil（小工具寫「App 的價」）
    var appQuoteAt: Date?
    /// 今年領的現金股利「NT$3.9萬」（moneyCashDividends(今年 1/1 00:00…現在)）；今年沒有 nil
    var dividendsThisYearText: String?
    /// 最近一次現金股利「10/5 配息 NT$530」（這一檔 dividends 裡日期最晚的現金股利，cashTotal × currencyFactor）；從來沒有 nil
    var lastDividendText: String?
    /// 點了開那一檔（WidgetLink.financeStock(id) 的 absoluteString）
    var link: String

    var url: URL { URL(string: link) ?? WidgetLink.financeStock(id) }

    /// 設定選單、中型列的名字：「2330 台積電」（名字就是代號時只寫一次）
    var menuTitle: String {
        name == symbol ? symbol : symbol + " " + name
    }
}

// MARK: [v4] 金價匯率

/// 設定「自訂幣別匯率」裡、App 認得的幣別（金價匯率小工具的選單與「抓不到時用 App 的價」）
struct WidgetRatesBlock: Codable, Equatable {
    /// FXRateService.isoCode(for:) 認得的、匯率 > 0 的，照設定頁的順序；同一個代碼只留第一個
    var items: [WidgetFinanceRate]
    /// App 最後一次自動更新匯率成功的時間（AppQuoteClock.ratesUpdatedAt）；沒記過 nil
    var appUpdatedAt: Date?
}

struct WidgetFinanceRate: Codable, Equatable, Identifiable {
    /// FXRateService 的代碼：「USD」「JPY」「XAU」「XAU(錢)」「XAU(盎司)」「XAG」
    var code: String
    /// 使用者在設定頁填的幣別字（去頭尾空白）：「美金」「日圓」「黃金(克)」
    var label: String
    /// 1 單位幾台幣（App 存的值）
    var rate: Double

    var id: String { code }
}

/// 金價匯率小工具可以選來顯示的一個（大字、下面那一行、鎖定畫面）。不存檔，WidgetRatesBlock.choices() 組
struct WidgetRateChoice: Equatable, Identifiable {
    /// FXRateService 的代碼（小工具上網抓價就把它丟給 FXRateService.fetchDayQuotes）
    var code: String
    /// 「黃金 每克」「黃金 每台錢」「美金」（使用者填的字）
    var title: String
    /// 鎖定畫面圓形上面的小字：「金/克」「金/錢」「美金」（其他幣別取前 3 個字）
    var shortTitle: String
    /// App 自訂幣別匯率裡的值；使用者沒填這個幣別是 nil
    var appRate: Double?
    /// 黃金、白銀（期貨換算）：大字前面有「NT$」、時間前面寫「期貨換算」
    var isMetal: Bool

    var id: String { code }
}

extension WidgetRatesBlock {
    /// 黃金每克（FXRateService 的內部代碼，同 App「黃金」「黃金(克)」）
    static let goldGramCode = "XAU"
    /// 黃金每台錢（3.75 克）
    static let goldQianCode = "XAU(錢)"
    static let usdCode = "USD"

    /// 沒有快照時也有的兩個：黃金每克、黃金每台錢（小工具自己抓得到，使用者沒在設定頁填也可以看）
    static let goldChoices: [WidgetRateChoice] = [
        WidgetRateChoice(code: goldGramCode, title: "黃金 每克", shortTitle: "金/克", appRate: nil, isMetal: true),
        WidgetRateChoice(code: goldQianCode, title: "黃金 每台錢", shortTitle: "金/錢", appRate: nil, isMetal: true)
    ]

    /// 選單：黃金每克、黃金每台錢（App 有填就帶 App 的值），再接 items 裡其他的（照設定頁的順序）
    func choices() -> [WidgetRateChoice] {
        var out: [WidgetRateChoice] = []
        for gold in Self.goldChoices {
            var c = gold
            c.appRate = items.first(where: { $0.code == gold.code })?.rate
            out.append(c)
        }
        for item in items where item.code != Self.goldGramCode && item.code != Self.goldQianCode {
            let label = item.label.isEmpty ? item.code : item.label
            let metal = item.code.hasPrefix("XAU") || item.code.hasPrefix("XAG")
            out.append(WidgetRateChoice(code: item.code, title: label, shortTitle: String(label.prefix(3)),
                                        appRate: item.rate, isMetal: metal))
        }
        return out
    }

    func choice(code: String) -> WidgetRateChoice? {
        choices().first { $0.code == code }
    }

    /// 大字的預設：黃金每克
    var defaultMain: WidgetRateChoice {
        choice(code: Self.goldGramCode) ?? Self.goldChoices[0]
    }

    /// 下面那一行的預設：美金（自訂幣別匯率裡有填才有，沒有 nil＝不寫）
    var defaultSecond: WidgetRateChoice? {
        choice(code: Self.usdCode)
    }
}

// MARK: [v4] 我的車

/// 車子的動力（決定插畫、主題色、中型的兩顆按鈕；App 從 VehiclePowerType 換過來）
enum WidgetVehiclePower: String, Codable {
    case electric
    case gasoline
    case hybrid
    case motorcycle
    case electricMotorcycle

    /// 記能源的那一顆按鈕是電費（電車、電動機車）還是加油（油車、油電、機車）
    var chargesElectric: Bool {
        self == .electric || self == .electricMotorcycle
    }
}

/// 一台車要顯示的字與數字。全部由 App 用 VehicleFacts 算好（跟車子卡片、載具頁看板同一個數）
struct WidgetFinanceVehicle: Codable, Equatable, Identifiable {
    var id: UUID
    /// 小工具上的名字（VehicleScriptName.shareName：車名像車牌時改寫「保時捷 電車」；空的「未命名車輛」）
    var name: String
    var power: WidgetVehiclePower
    /// 「電車」「油車」「油電」「機車」「電動機車」（VehiclePowerType.shortName）
    var powerText: String
    var isSold: Bool
    /// 主題色（VehicleScriptName.theme(v)）：電車 finElectric 0x7FE3D0→0x1A9C8C（tint 0x138A7E）、
    /// 油車油電 finGas 0x8EC5FF→0x2F6FE0（tint 0x2F6FE0）、機車 0x8DB3D6→0x3C5A86（tint 0x4A6FA5）
    var top: UInt32
    var bottom: UInt32
    var tint: UInt32
    /// 插畫的 SF Symbol（theme.hero：「car.fill」「scooter」）。**不用照片**（照片可能拍到車牌）
    var symbol: String
    /// 「約 NT$5,200」（FinanceText.about100(VehicleFacts.monthly)）；沒有紀錄 nil
    var monthlyText: String?
    /// 中型：「每度電 NT$7.9」「每公升 NT$30.5」；兩種都沒有 nil
    var energyText: String?
    /// 中型：「估值 NT$260萬」（已售出「成交 NT$200萬」）；估值沒填 nil
    var valueText: String?
    /// 車貸（有填年限的那幾筆合起來，同車子卡片的進度條）；沒有 nil
    var loan: WidgetVehicleLoan?
    /// 今天起 45 天內每一次要扣的（車貸、停車月租、保險、保養估計…），依日期、名稱排，最多 8 筆。
    /// 跟「接下來要繳」同一套：VehicleFacts.upcoming 在今天、15 天後各算一次合併（id＋日子去重）
    var upcoming: [WidgetVehicleDue]
    /// 中型的兩顆按鈕：電車、電動機車［記電費、記停車］；油車、油電、機車［記加油、記停車］
    var buttons: [WidgetVehicleButton]
    /// 點了開那一台車的卡片（WidgetLink.financeVehicle(id) 的 absoluteString）
    var link: String

    var url: URL { URL(string: link) ?? WidgetLink.financeVehicle(id) }
}

/// 車貸（多筆合起來）。App 算的那一刻已繳 paid 期；之後的扣款日在 dues，過了 00:00 就自己加一期
struct WidgetVehicleLoan: Codable, Equatable {
    /// 已繳幾期（VehicleFacts.loan.elapsed，有填年限的各筆加總）
    var paid: Int
    /// 總期數（VehicleFacts.loan.total）
    var total: Int
    /// 接下來會扣的期（各筆車貸合在一起依日期排，最多 6 期；date 是那天 00:00）
    var dues: [WidgetLoanDue]
    /// 「2029/9 繳完」（最晚那一筆的 payoffDate）；沒有 nil
    var payoffText: String?
    /// 還沒開始扣：「2026/11 開始」（最早的 firstDue）；已經開始 nil
    var startText: String?

    /// now 那一刻已繳幾期：App 算的＋dues 裡日期 ≤ now 的（扣款日當天 00:00 起就算繳了，同 App 的已繳），不超過 total
    func paid(at now: Date) -> Int {
        let more = dues.filter { $0.date <= now }.count
        return min(total, paid + more)
    }

    /// 繳清了沒
    func isDone(at now: Date) -> Bool {
        paid(at: now) >= total
    }

    /// 「車貸 已繳 25／60 期」；繳清「車貸繳清」；還沒開始「車貸 2026/11 開始」（同車子卡片的字）
    func progressText(at now: Date) -> String {
        if isDone(at: now) { return "車貸繳清" }
        let n = paid(at: now)
        if n == 0, let start = startText { return "車貸 " + start }
        return "車貸 已繳 \(n)／\(total) 期"
    }

    /// 進度環、進度條 0…1
    func fraction(at now: Date) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(paid(at: now)) / Double(total)))
    }
}

struct WidgetLoanDue: Codable, Equatable {
    /// 扣款日那一天的 00:00
    var date: Date
    /// 第幾期
    var index: Int
}

/// 一台車的一次扣款
struct WidgetVehicleDue: Codable, Equatable, Identifiable {
    /// 「<VehicleUpcoming.id>@<yyyy-MM-dd>」
    var id: String
    /// 扣款日那一天的 00:00
    var date: Date
    /// 「車貸」「停車月租」「保養（估計）」（VehicleUpcoming.title）
    var title: String
    /// 車貸「第 26 期」（WidgetLoanDue 那一期）；其他 nil
    var periodText: String?
    /// 「NT$3.2萬」「NT$4,999」；保養估計「約 NT$8,000」
    var amountText: String
}

/// 中型的一顆按鈕：打開 App 的新增支出、車子與分類帶好（你按儲存才算）
struct WidgetVehicleButton: Codable, Equatable, Identifiable {
    /// VehicleVariableCategory.rawValue「電費」「油錢」「停車」：原樣帶回網址 vcat=
    var categoryKey: String
    /// 「記電費」「記加油」「記停車」
    var title: String
    /// 「bolt.fill」「fuelpump.fill」「parkingsign.circle」
    var icon: String
    /// WidgetLink.addExpense(vehicleId:vehicleCategoryKey:) 的 absoluteString
    var link: String

    var id: String { categoryKey }
    var url: URL { URL(string: link) ?? WidgetLink.addExpense() }
}

extension WidgetFinanceVehicle {
    /// 今天（含）以後還沒扣的，依日期
    func remainingDues(at now: Date) -> [WidgetVehicleDue] {
        let today = Calendar.current.startOfDay(for: now)
        return upcoming.filter { $0.date >= today }
    }

    /// 「下一筆」那一行（不含「下一筆 」三個字）：第一個日子要扣的，同一天好幾筆合在一起——
    /// 「11/5 車貸 第 26 期」「11/5 車貸 第 26 期、停車月租」。都扣完了（App 太久沒開）nil
    func nextText(at now: Date) -> String? {
        let list = remainingDues(at: now)
        guard let first = list.first else { return nil }
        // [v4 G3] 有期數的（車貸）排第一個：App 依（日子、名稱）排，「停車月租」的「停」排在「車貸」前面，
        // 照原順序會變成「11/5 停車月租、車貸」、第幾期不見了
        let sameDay: [WidgetVehicleDue] = list.filter { $0.date == first.date && $0.periodText != nil }
            + list.filter { $0.date == first.date && $0.periodText == nil }
        var names: [String] = []
        for (i, d) in sameDay.enumerated() {
            if i == 0, let p = d.periodText {
                names.append(d.title + " " + p)
            } else {
                names.append(d.title)
            }
        }
        return WidgetDateText.shortDate(first.date) + " " + names.joined(separator: "、")
    }

    /// 鎖定畫面圓形沒有車貸時，圓裡寫下一筆的日子「11/5」；沒有 nil
    func nextShortDate(at now: Date) -> String? {
        remainingDues(at: now).first.map { WidgetDateText.shortDate($0.date) }
    }
}

// MARK: [v4] 淨資產

/// 淨資產（理財總覽頭部同一套：FinanceSnapshot.current＋FinanceHistory.series(months: 2)）
struct WidgetNetWorth: Codable, Equatable {
    /// 這份數字是哪個月的「2026-10」（WidgetDateText.monthKey）。跨月了（App 還沒開）小工具不寫「比上月」
    var monthKey: String
    /// 「10 月」
    var monthText: String
    /// 大字「NT$1720萬」（MoneyFormat.short(FinanceSnapshot.netWorth)）
    var netWorthText: String
    /// 淨資產是負的（大字用紅色，同理財總覽 bigTone .bad；著色模式靠「-」）
    var isNegative: Bool
    /// 「比上月 ↑1.8%」「比上月 ↓0.6%」「比上月 持平」（理財總覽 changeCapsule 同一個算法與寫法）；上個月沒有數字 nil
    var changeText: String?
    /// 鎖定畫面圓形：「↑1.8%」「↓0.6%」「持平」；沒有 nil
    var changeShort: String?
    /// 1 上升、-1 下降、0 持平或沒有（只拿來上色；著色模式靠 ↑↓ 字）
    var changeDirection: Int
    /// 理財總覽頭部那一句：「總資產 NT$3795萬・貸款還欠 約 NT$2075萬」「總資產 NT$3795萬・沒有貸款」
    var line: String
    /// 隱藏金額版：「總資產 NT$ ••••・貸款還欠 NT$ ••••」「總資產 NT$ ••••・沒有貸款」
    var lineMasked: String
    /// 資產各類（房地產、股票、載具、儲蓄險；[v25.565] 存款；> 0 的，金額大到小）
    var assets: [WidgetNetWorthPart]
    /// 貸款各類（房貸、車貸、其他貸款；[v25.565] 卡費與交割；> 0 的，金額大到小）
    var debts: [WidgetNetWorthPart]
    /// 中型兩條的長度（0…1）：資產、貸款比較大的那一條是 1
    var assetsBar: Double
    var debtsBar: Double
    /// 鎖定畫面長方形第三行：「資產 4 類・10 月」（沒有資產「10 月」）
    var summaryText: String
    /// 淨資產裡股票用的是幾點的價（持有中股票的 AppQuoteClock 最新那一筆）；沒有股票或不知道 nil
    var stockPriceAt: Date?

    /// 快照的月份就是現在這個月（跨月了就不寫「比上月」，改寫 WidgetDateText.figuresOf(generatedAt)）
    func isCurrentMonth(at now: Date) -> Bool {
        monthKey == WidgetDateText.monthKey(now)
    }
}

/// 淨資產的一類（資產或貸款）
struct WidgetNetWorthPart: Codable, Equatable, Identifiable {
    /// 「realEstate」「stock」「vehicle」「savings」「mortgage」「carLoan」「otherLoan」
    var key: String
    /// 「房地產」「股票」「載具」「儲蓄險」「房貸」「車貸」「其他貸款」
    var title: String
    /// SF Symbol：house.fill／chart.line.uptrend.xyaxis／car.fill／shield.lefthalf.filled；
    /// 房貸 house、車貸 car、其他貸款 banknote
    var icon: String
    /// 「NT$3178萬」（MoneyFormat.short）。房貸、車貸照理財總覽：推算的寫「約 NT$…」、算不出本金的寫「還要繳 NT$…」
    var amountText: String
    /// 占資產（或占貸款）幾成「84%」（MoneyFormat.percent）。隱藏金額時小工具改寫這個
    var shareText: String
    /// 0…1：在自己那一條裡占多長
    var share: Double
    /// 顏色（資產照 FinanceAssetKind.theme：房紫 0xB79CFF→0x6B4BE0、股橘 0xFFB45E→0xF07A2A、
    /// 車青綠 0x7FE3D0→0x1A9C8C、險藍 0x8EC5FF→0x3A6FE0；房貸同房、車貸同車、其他貸款灰 0xC5CCDA→0x7A869E）
    var top: UInt32
    var bottom: UInt32

    var id: String { key }
}

// MARK: - [v4] 小工具自己抓的價（quotes_v1.json：只有小工具讀寫，App 不讀不寫）

/// 股票、金價匯率小工具自己上網抓到的價。抓到就合併寫進來（LifeGoodWidgets/WidgetQuoteStore.swift），
/// 下次畫的時候跟 finance 快照裡 App 的價比誰新。App 不讀這個檔、也不回寫股票資料（兩邊不打架）。
struct WidgetQuoteCache: Codable, Equatable, WidgetSnapshotPayload {
    static let file = WidgetSnapshotFile.quotes
    static let schemaVersion = 1

    var schema: Int = WidgetQuoteCache.schemaVersion
    /// 最後一次寫的時間
    var generatedAt: Date
    /// App 的股票代號（WidgetFinanceStock.symbol「2330」）→ 抓到的價
    var stocks: [String: WidgetQuote]
    /// FXRateService 的代碼（「XAU」「USD」）→ 抓到的價
    var rates: [String: WidgetRateQuote]

    static func empty(at now: Date) -> WidgetQuoteCache {
        WidgetQuoteCache(generatedAt: now, stocks: [:], rates: [:])
    }
}

/// 一檔股票抓到的價（Yahoo v8 chart，range=1d&interval=1d 的 meta）
struct WidgetQuote: Codable, Equatable {
    /// 抓到的是哪個 Yahoo 代號（下次排第一個試）
    var yahooSymbol: String
    /// regularMarketPrice（原幣別）
    var price: Double
    /// 前一個交易日收盤（meta.previousClose，沒有就 chartPreviousClose——range=1d 時它就是昨收）；沒有 nil
    var previousClose: Double?
    /// 這個價是幾點成交的（regularMarketTime）；沒有 nil
    var marketTime: Date?
    /// 這一個交易時段（currentTradingPeriod.regular 的 start／end）；沒有 nil
    var sessionStart: Date?
    var sessionEnd: Date?
    /// 小工具抓的時間（跟 App 的 appQuoteAt 比誰新）
    var fetchedAt: Date

    /// 這是收盤價嗎（寫「13:30 收盤」「10/13 收盤」）：成交時間在這個時段開始之前（開盤前看到的是上一個交易日）、
    /// 或成交時間已經到收盤前 1 分鐘內、或**抓的時候**已經收盤 1 分鐘以上（成交少的股票最後一筆早於收盤）。
    /// [v4 驗證] 以前最後一條看「現在」過了收盤：13:15 抓到 13:14 那筆、之後收盤後都抓不到（沒網路、被擋），
    /// 盤中那筆會被寫成「13:14 收盤」，隔天變「10/14 收盤」、價錢卻不是收盤價。改看抓的時間：
    /// 盤中抓的就照實寫「13:14」「10/14 13:14」（收盤後 1 小時內 WidgetQuoteStore.stockReloadAt 會每 15 分再抓）。
    /// 多 1 分鐘：13:30 整點那一次常常還沒拿到收盤集合競價那一筆
    func isClose(at now: Date) -> Bool {
        guard let t = marketTime else { return false }
        if let start = sessionStart, t < start { return true }
        if let end = sessionEnd {
            if t >= end.addingTimeInterval(-60) { return true }
            if fetchedAt >= end.addingTimeInterval(60) { return true }
        }
        return false
    }
}

/// 一個幣別（或黃金）抓到的價：1 單位幾台幣（FXRateService.fetchDayQuotes，算法同 App 的自動更新）
struct WidgetRateQuote: Codable, Equatable {
    var rate: Double
    /// 前一日收盤換算的同一個單位；沒有 nil（不寫「比昨天」）
    var previousRate: Double?
    /// 這個價是幾點的（Yahoo regularMarketTime；黃金看期貨那一筆）
    var asOf: Date?
    /// 小工具抓的時間
    var fetchedAt: Date
}

// MARK: - 日期與時間的字（兩邊共用，不含金額）

enum WidgetDateText {
    private static let dayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        // [v25.545] 跟著手機目前的時區走：App 一路活在背景、人飛到日本才打開時，
        // 快取的 formatter 不會還停在台灣時區，把「今天」寫成前一天
        f.timeZone = .autoupdatingCurrent
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d EEE"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        // [v25.545] 跟著手機目前的時區走：App 一路活在背景、人飛到日本才打開時，
        // 快取的 formatter 不會還停在台灣時區，把「今天」寫成前一天
        f.timeZone = .autoupdatingCurrent
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d"
        return f
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        // [v25.545] 跟著手機目前的時區走：App 一路活在背景、人飛到日本才打開時，
        // 快取的 formatter 不會還停在台灣時區，把「今天」寫成前一天
        f.timeZone = .autoupdatingCurrent
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// [v2] 「10/15 (週四)」（接下來要繳的日期）
    private static let billDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .autoupdatingCurrent
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d (EEE)"
        return f
    }()

    /// 「10/13 週二」
    static func dayLabel(_ date: Date) -> String { dayLabelFormatter.string(from: date) }

    /// [v2] 「10/15 (週四)」
    static func billDate(_ date: Date) -> String { billDateFormatter.string(from: date) }

    /// [v2] 記帳台左上「10 月・第 13 天」
    static func monthDayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        return "\(month) 月・第 \(day) 天"
    }

    /// [v2] now 那一天到 date 那一天差幾天（日曆天；同一天 0、明天 1、昨天 -1）。日差不是金額，小工具可以算
    static func daysFrom(_ now: Date, to date: Date) -> Int {
        let cal = Calendar.current
        let a = cal.startOfDay(for: now)
        let b = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// [v2] 扣款日倒數：「今天扣款」「明天扣款」「2 天後」；會領回的（isIncome）寫「今天到期」「明天到期」。
    /// 已經過了回 nil（那一列不該再出現）
    static func dueText(_ due: Date, from now: Date, isIncome: Bool = false) -> String? {
        let n = daysFrom(now, to: due)
        if n < 0 { return nil }
        if n == 0 { return isIncome ? "今天到期" : "今天扣款" }
        if n == 1 { return isIncome ? "明天到期" : "明天扣款" }
        return "\(n) 天後"
    }

    /// [v2] 今天、明天要扣的（小工具畫橘字，跟收支總覽一樣）
    static func isDueSoon(_ due: Date, from now: Date) -> Bool {
        let n = daysFrom(now, to: due)
        return n >= 0 && n <= 1
    }

    /// 「10/13」
    static func shortDate(_ date: Date) -> String { shortDateFormatter.string(from: date) }

    /// 「2026-10-13」（只拿來辨認是哪一天，不顯示）
    static func dayKey(_ date: Date) -> String { dayKeyFormatter.string(from: date) }

    /// 「上次更新 10/11」
    static func lastUpdated(_ generatedAt: Date) -> String {
        "上次更新 " + shortDate(generatedAt)
    }

    /// 「10:02 更新」；不是今天寫的寫「10/12 22:00 更新」（[v25.545] 隔天早上只寫 22:00 會看不懂是哪天）
    static func updatedAt(_ generatedAt: Date, now: Date = Date()) -> String {
        let time = DayTimelineFormat.time(generatedAt) + " 更新"
        if Calendar.current.isDate(generatedAt, inSameDayAs: now) { return time }
        return shortDate(generatedAt) + " " + time
    }

    /// [v4] 「2026-10」：這份數字是哪個月的（淨資產跨月就不寫「比上月」）。西曆、跟著手機目前的時區
    static func monthKey(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .autoupdatingCurrent
        let c = cal.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// [v4] 「10/11 的數字」：理財快照不是今天寫的（我的車、淨資產右下角，橘字）
    static func figuresOf(_ generatedAt: Date) -> String {
        shortDate(generatedAt) + " 的數字"
    }

    /// [v4] now 之後的 count 個 00:00（Calendar.current；不含 now 本身）。我的車、淨資產每天換日用
    static func midnights(after now: Date, count: Int) -> [Date] {
        let cal = Calendar.current
        var out: [Date] = []
        var day = cal.startOfDay(for: now)
        for _ in 0..<max(0, count) {
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            out.append(next)
            day = next
        }
        return out
    }

    /// 「11 月開始了」（快照的月份過完了、App 還沒打開）
    static func monthStarted(_ date: Date) -> String {
        let month = Calendar.current.component(.month, from: date)
        return "\(month) 月開始了"
    }

    /// 倒數字：「25 分後」「1 小時後」「1 小時 20 分後」。
    /// 分鐘無條件進位（10:05:00 到 10:30 是 25 分；10:05:30 也還是 25 分）。
    /// 已經到了、或超過 WidgetFreshness.countdownMaxMinutes 回 nil（不寫倒數，只寫時間）。
    /// 「40 分後結束」＝這個字＋「結束」。
    static func countdown(to target: Date, from now: Date) -> String? {
        let seconds = target.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        let minutes = Int((seconds / 60).rounded(.up))
        guard minutes <= WidgetFreshness.countdownMaxMinutes else { return nil }
        if minutes < 60 { return "\(minutes) 分後" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) 小時後" : "\(hours) 小時 \(rest) 分後"
    }
}

// MARK: - 讀寫

/// 快照的讀與寫。小工具只呼叫 read；App 只呼叫 write（WidgetSnapshotWriter）。
enum WidgetSnapshotStore {

    /// App Group 的根目錄；entitlements 沒生效時是 nil（這時 read 一律 nil、write 一律 false）
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetShared.appGroupID)
    }

    /// <App Group>/Widgets/。create 為 true 時順手建資料夾（已經有就沒事）。
    static func folderURL(create: Bool) -> URL? {
        guard let base = containerURL else { return nil }
        let folder = base.appendingPathComponent(WidgetShared.folderName, isDirectory: true)
        if create {
            // 不能用最嚴格的 complete：手機鎖著時 StandBy／鎖定畫面的小工具會讀不到
            let attributes: [FileAttributeKey: Any] = [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
            do {
                try FileManager.default.createDirectory(at: folder,
                                                        withIntermediateDirectories: true,
                                                        attributes: attributes)
            } catch {
                return nil
            }
        }
        return folder
    }

    static func fileURL(_ file: WidgetSnapshotFile, create: Bool = false) -> URL? {
        folderURL(create: create)?.appendingPathComponent(file.rawValue, isDirectory: false)
    }

    /// 小工具用：讀不到、解不開、schema 對不上都回 nil（＝還沒打開過新版 App）
    static func read<T: WidgetSnapshotPayload>(_ type: T.Type) -> T? {
        guard let url = fileURL(T.file),
              let data = try? Data(contentsOf: url),
              let value = try? makeDecoder().decode(T.self, from: data),
              value.schema == T.schemaVersion else { return nil }
        return value
    }

    /// App 用：整檔一次換掉（原子寫入），保護等級「開機後第一次解鎖就能讀」。
    ///
    /// 跟舊檔比：拿掉 generatedAt 之後內容一模一樣就**不寫**、回 false——呼叫端看到 false
    /// 就不要叫 WidgetCenter 重畫。真的寫了才回 true。寫失敗也回 false。
    @discardableResult
    static func write<T: WidgetSnapshotPayload>(_ snapshot: T) -> Bool {
        guard let url = fileURL(T.file, create: true) else { return false }
        let encoder = makeEncoder()
        guard let newData = try? encoder.encode(snapshot) else { return false }
        if let oldData = try? Data(contentsOf: url),
           let old = try? makeDecoder().decode(T.self, from: oldData) {
            // 用舊檔的 generatedAt 重新編一次：編出來跟舊檔一個位元組都不差＝內容沒變
            var probe = snapshot
            probe.generatedAt = old.generatedAt
            if let probeData = try? encoder.encode(probe), probeData == oldData {
                return false
            }
        }
        do {
            try newData.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    /// 兩邊同一組設定。sortedKeys 讓同樣的內容永遠編出同樣的位元組（write 的比對靠它）；
    /// 日期用預設的 deferredToDate（Date 自己的秒數原樣進出，不會因為換算差一點點）。
    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .deferredToDate
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf",
                                                                 negativeInfinity: "-inf",
                                                                 nan: "nan")
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .deferredToDate
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf",
                                                                   negativeInfinity: "-inf",
                                                                   nan: "nan")
        return d
    }
}
