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
// 分工跟靈動島一樣：App 把小工具要顯示的「字」與「數字」算好、格式化好，寫成 App Group 裡的
// 小檔案；小工具只讀這些檔、照著畫。**小工具裡不做任何金額計算與格式化**——「NT$4.6萬」
// 「每天 NT$2,402」「已花 62%」全部是 App 用自己那套函式（MoneyFormat／ntdWanString）組好的字。
//
// 換日不靠小工具算：App 寫快照時就把「今天、明天……」每一天要顯示的字各準備一份，
// 小工具只依現在時間挑對應的那一份。
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

    /// money_v1.json 變了要重畫的（App 的寫手、一按就記的按鈕都用這一組）
    static let moneyKinds = [moneyLeft, ledgerDesk, quickRecord, lockSpent]
    /// [v3] money_v1.json 變了要重畫的控制項（「記到…」的「Taycan 電費」從 money 快照讀）。
    /// 用 WidgetRefresh.reloadControls(_:)
    static let moneyControlKinds = [controlRecordTo]
    /// life_v1.json 變了要重畫的（[v3] 加旅行）
    static let lifeKinds = [today, lockNextStop, travel]
    /// bills_v1.json 變了要重畫的
    static let billsKinds = [bills, lockNextBill]
}

/// 快照檔名。分檔是為了只改了帳就只重寫 money、只重畫「還能花」。
enum WidgetSnapshotFile: String {
    case money = "money_v1.json"
    case life = "life_v1.json"
    /// [v2] 接下來要繳
    case bills = "bills_v1.json"
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

    /// 越小越優先：生日＞結婚紀念日＞兼任職務＞里程碑＞其他全日事件
    var priority: Int {
        switch self {
        case .birthday:      return 0
        case .anniversary:   return 1
        case .sideRole:      return 2
        case .milestone:     return 3
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
        case .birthday, .anniversary, .sideRole, .milestone:
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

    /// [v3] 鎖定畫面「下一筆要繳」關掉「顯示名稱」時的類別字（App 沒寫 WidgetBill.lockTitle 的舊檔才用）
    var label: String {
        switch self {
        case .fixed:    return "固定支出"
        case .mortgage: return "房貸"
        case .vehicle:  return "車子費用"
        case .premium:  return "保費"
        case .maturity: return "保單滿期"
        }
    }

    /// [v3] 記帳的固定支出（其他四種是理財的）
    var isLedger: Bool { self == .fixed }
}

/// [v3] 「接下來要繳」的範圍（長按設定 WidgetBillScopeOption → 這個）
enum WidgetBillScope: String {
    /// 記帳＋理財合一張（預設，跟 v2 一樣）
    case all
    /// 只看記帳的固定支出（Netflix、中華電信…）
    case ledger
    /// 只看理財（房貸、車子、保費、滿期）
    case finance

    func includes(_ kind: WidgetBillKind) -> Bool {
        switch self {
        case .all:     return true
        case .ledger:  return kind.isLedger
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
