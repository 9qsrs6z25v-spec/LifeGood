import Foundation

// MARK: - 手錶包（手錶 v1，v25.574；watch/judge.md §5.2、§6.2、附錄 A；watch/build/v1/brief.md §2）
//
// 這個檔屬於三個 target：iPhone App（LifeGood）、手錶 App（LifeGoodWatch）、手錶小格（LifeGoodWatchWidgets）。
// 只准用 Foundation 與 WidgetSnapshot.swift／DayTimelineAttributes.swift 的純資料型別（iPhone 小工具 target 不編它）。
//
// iPhone → 手錶的一整包。iPhone 的 WatchPackageBuilder（Models/，只讀 App Group 的檔）一欄一欄抄、消毒，
// WatchBridge 用 WatchPackageCodec 壓縮後經 WatchConnectivity 送；手錶的 WatchSync 解開後存進
// **手錶自己的** App Group 同一個檔名（WidgetSnapshotStore.write，檔名 WidgetSnapshotFile.watch），
// 手錶 App 與手錶小格都用 WidgetSnapshotStore.read(WatchPackage.self) 讀。
//
// ⚠️ 白名單：任何卡號、帳號、安全碼、有效期限、發票驗證碼、卡名、卡費金額、存摺數字、淨資產、收入、
//    部屬請假、AI 金鑰、CloudKit token、email 一律不准放（watch judge §6.2、財富 judge §7.2）。
// ⚠️ 真的白名單（judge §6.2-1、評論 🔴12）：外層一律用這個檔的型別、WatchPackageBuilder 一欄一欄抄；
//    不准把 WidgetLifeSnapshot／WidgetMoneySnapshot／WidgetBillsSnapshot 整個放進來。
//    這個檔用到的每一個型別的每一欄都列在 scratchpad/watch/build/pkg_allowlist.txt，
//    scratchpad/watch/build/pkg_keys_check.py 多一欄就擋（每版送出前跑）。
// v1 只有今天、錢、要繳；v2 以後的欄位（記帳台、今天記的帳、跑步、旅行…）那一版再加，一律選填。
// [手錶 v2] v25.576（watch/build/v2/brief.md §2）：記一筆、今天記的帳、手機條碼——
//   • 包多 recentAmounts、titleHints、todayRecords、includedIds、queuedIds、carrierBarcode（全部選填；v1 的手錶照樣解得開）
//   • WatchMoney 多 templates、topCategoryKeys、categories（記帳台；手錶自己的型別 WatchTemplate／WatchCategory，
//     不放 WidgetQuickTemplate／WidgetCategory——真的白名單）
//   • 手錶 → iPhone 的 WatchRecord（記一筆），兩邊同一組 WatchLink 鍵與 WatchRecordCodec
//   • 手錶上不給的分類（WatchCategoryRule）、時段（WatchTimeSlot：iPhone 算「這個時段最常寫的名稱」、手錶查）
// [手錶 v6] v25.578（watch/judge.md §2.14、§3.1、§4.1、§5.2、附錄 A／B；watch/build/v6/brief.md §2）：旅行——
//   • 包多 timeZoneId（每一天的起訖是用哪個時區算的）、tripToday／tripTomorrow（旅途中今天、明天的站；全部選填）
//   • WatchTripDay／WatchTripStop／WatchCurrency：只有站名、時間、第幾站、地址、座標、電話、打卡時間、天氣字與出處、
//     這趟的幣別與匯率、這趟最近記過的金額（只有數字）與常用分類——沒有備註、照片、伴手禮「給誰」、同行者
//   • 手錶 → iPhone 的 WatchCheckIn（打卡：到了／離開，送「設成」不送「切換」）；WatchRecord 多外幣與記到哪一站（選填）

/// iPhone → 手錶的一整包（watch_v1.json）
struct WatchPackage: Codable, Equatable, WidgetSnapshotPayload {
    static let file = WidgetSnapshotFile.watch
    static let schemaVersion = 1

    var schema: Int = WatchPackage.schemaVersion
    /// iPhone 組這一包的時間（不算內容：WidgetSnapshotStore.write 比內容時會換掉它）
    var generatedAt: Date
    /// 今天、明天的行程（life_v1.json 一欄一欄抄、消毒）；iPhone 從來沒寫過 life 快照是 nil
    var life: WatchLife? = nil
    /// 還能花（money_v1.json 一欄一欄抄）；iPhone 設定「送到手錶：錢」關掉是 nil（手錶 ② 錢整頁不出現）
    var money: WatchMoney? = nil
    /// 接下來要繳（bills_v1.json 一列一列消毒）；財富那幾列只剩類別字、沒有金額；會領回的（isIncome）整列不放。
    /// 「錢」關掉是 nil
    var bills: [WatchBill]? = nil
    /// iPhone 的「隱藏金額」開著（WidgetHideAmounts.isOn）：手錶這個或自己的「遮住金額」任一個開著就遮
    var phoneHidesAmounts: Bool = false
    /// 會議細節裡的部屬名字（judge Q7／§13-7）：false 時 iPhone 根本沒送（部屬會議 stop.owner 是空字串）
    var showOwnerNames: Bool = true

    // MARK: [v2] 記一筆、今天記的帳、手機條碼（一律選填；「錢」關掉時前三個是 nil）

    /// 這個分類最近 3 個不同金額（台幣、四捨五入到元，新到舊）：金額頁的膠囊、一打開的金額。
    /// 鍵有兩種：「飲食」＝整天；「飲食@11-14」＝只看那個時段（WatchTimeSlot.amountKey）。手錶先用這個時段的、不夠再用整天的補
    var recentAmounts: [String: [Double]]? = nil
    /// 分類 key → 時段 key（WatchTimeSlot.keys）→ 這個時段最常寫的名稱（「飲食」→「11-14」→「午餐」）
    var titleHints: [String: [String: String]]? = nil
    /// 今天的變動支出，新到舊、最多 10 筆（名稱、金額字、時間、圖示、是不是手錶記的；
    /// 沒有備註、照片、同行者、付款卡）
    var todayRecords: [WatchRecordRow]? = nil
    /// 帳本裡已經有的手錶編號（近 3 天入帳、而且還在帳本裡，最多 100）：手錶待送盒看到就刪檔
    var includedIds: [UUID]? = nil
    /// 還在 iPhone 收件匣、等打開 iPhone 上的 LifeGood 才入帳的手錶編號：手錶寫「在 iPhone 等著入帳」
    var queuedIds: [UUID]? = nil
    /// 手機條碼「/ABC1234」：iPhone 設定「手機條碼」打開、而且格式對才有（發票驗證碼永遠不在這裡）
    var carrierBarcode: String? = nil

    // MARK: [v6] 旅行（一律選填；「送到手錶：旅行」關掉時 tripToday／tripTomorrow 是 nil、life.trips 也是 nil）

    /// 每一天的起訖是 iPhone 用哪個時區算的（「Asia/Taipei」；WatchExtrasCache 帶過來，是 App 寫快照那一刻的時區，
    /// 不是組包那一刻的）。手錶自己的時區跟它差幾小時，第一頁最上面寫「換時區了…」（WatchTripText.timeZoneHint）
    var timeZoneId: String? = nil
    /// 旅途中今天的站（今天不在任何一趟的期間裡是 nil）
    var tripToday: WatchTripDay? = nil
    /// 旅途中明天的站：過了午夜 iPhone 的 LifeGood 還沒打開，手錶照樣有「今天」的站（旅途最後一天是 nil）
    var tripTomorrow: WatchTripDay? = nil
}

/// 今天、明天的行程。從 WidgetLifeSnapshot 一欄一欄抄：
/// team、plantAreas、hasTeam、countdowns、familyTasks（內容）、workout 這個型別裡根本沒有。
struct WatchLife: Codable, Equatable {
    /// life 快照寫的時間（iPhone 前景時每 30 分鐘會換一次，WidgetSnapshotWriter.restampLife）
    var generatedAt: Date
    var dataDay: String
    /// 後天 00:00：過了整份不能用（「打開 iPhone 上的 LifeGood，更新今天的行程」）
    var validUntil: Date
    /// [0]＝今天、[1]＝明天。每天：greeting＝[]；財富全天的 title／shortTitle＝lockTitle（「卡費」）；
    /// 部屬會議 stop.owner 照 showOwnerNames（不同意＝""）
    var days: [WidgetLifeDay]
    /// 還沒回來的旅行（最多 3 趟，原樣；名字、日期、行李數）：「今天要留意」⑤「韓國三日遊・還有 5 天」
    var trips: [WidgetTrip]? = nil
    /// dayKey →「家庭待辦今天到期」幾件（只有件數，沒有內容）
    var familyDue: [String: Int]? = nil
}

extension WatchLife {
    /// 這個時間點要顯示哪一天；過期回 nil。比第一天還早就用第一天。
    /// 照抄 WidgetLifeSnapshot.day(at:)（WidgetSnapshot.swift），scratchpad/watch/build/v1/copy_check.py 核對
    func day(at date: Date) -> WidgetLifeDay? {
        guard date < validUntil else { return nil }
        if let hit = days.first(where: { $0.contains(date) }) { return hit }
        if let first = days.first, date < first.dayStart { return first }
        return nil
    }

    /// 照抄 WidgetLifeSnapshot.isExpired(at:)
    func isExpired(at date: Date) -> Bool { date >= validUntil }

    /// 照抄 WidgetLifeSnapshot.showsUpdatedAt(at:)：超過 3 小時寫「09:24 更新」
    func showsUpdatedAt(at date: Date) -> Bool {
        date.timeIntervalSince(generatedAt) > WidgetFreshness.lifeShowUpdatedAfter
    }

    /// 某一天的隔天那一份（「明天 10/23 週五・3 件」）；包裡沒有（那一天是最後一天）回 nil
    func day(after d: WidgetLifeDay) -> WidgetLifeDay? {
        days.first { $0.dayStart >= d.dayEnd }
    }

    /// 那一天家庭待辦今天到期幾件（沒有＝0）
    func familyDueCount(_ dayKey: String) -> Int {
        familyDue?[dayKey] ?? 0
    }
}

/// 還能花。從 WidgetMoneySnapshot 一欄一欄抄：vehicleCard、vehicleOptions 這個型別裡沒有。
/// [v2] 記帳台的範本、分類改成手錶自己的型別（WatchTemplate、WatchCategory），手錶上不給的分類（WatchCategoryRule）iPhone 先拿掉。
struct WatchMoney: Codable, Equatable {
    var generatedAt: Date
    var dataDay: String
    var month: Int
    /// 今天到月底每天一份＋下個月 1–7 號（照原樣）；**每一天的 incomeText 都清成 nil**（收入＝高隱私）
    var days: [WidgetMoneyDay]

    // MARK: [v2] 記帳台（選填；v1 的包沒有）

    /// 一按就記的常記範本（照 iPhone 小工具那一份的順序：次數多到少，最多 4 個；沒有付款卡）
    var templates: [WatchTemplate]? = nil
    /// 近 60 天最常記的分類 key（多到少；手錶上不給的已拿掉）
    var topCategoryKeys: [String]? = nil
    /// 手錶上可以選的分類（照 VariableCategory.allCases 的順序；股票、房地產、稅費、節稅不在）
    var categories: [WatchCategory]? = nil
}

/// [v2] 一按就記的一格（iPhone 的 WidgetQuickTemplate 一欄一欄抄；沒有付款卡、沒有車名）
struct WatchTemplate: Codable, Equatable, Identifiable {
    /// ＝WidgetQuickTemplate.id（收件匣的範本編號：同一格 3 秒內按兩次只記一筆）
    var id: String
    /// 「7-11 咖啡」
    var title: String
    /// 55（台幣）
    var amount: Double
    /// 「NT$55」（iPhone 組好；遮住時手錶換「•••」）
    var amountText: String
    /// VariableCategory.rawValue（「飲食」）
    var categoryKey: String
    /// 範本連的車（「Taycan 停車 60」）：iPhone 入帳時照小工具一按就記的規則連車、寫車子鏡像
    var vehicleId: UUID? = nil
    /// VehicleVariableCategory.rawValue（「停車」）
    var vehicleCategoryKey: String? = nil
    /// SF Symbol
    var icon: String
    /// 分類色 0xRRGGBB
    var tint: UInt32
}

/// [v2] 手錶上可以選的一個分類（iPhone 的 WidgetCategory 一欄一欄抄）
struct WatchCategory: Codable, Equatable, Identifiable {
    /// VariableCategory.rawValue（「飲食」）
    var key: String
    /// 「飲食」
    var title: String
    /// SF Symbol（「fork.knife」）
    var icon: String
    /// 分類色 0xRRGGBB
    var tint: UInt32

    var id: String { key }
}

/// [v2] 今天記的帳的一列（iPhone 帳本裡今天的變動支出；只有這幾欄）
struct WatchRecordRow: Codable, Equatable, Identifiable {
    var id: UUID
    /// 「午餐」（空的名稱 iPhone 已經換成分類名）
    var title: String
    /// 「NT$180」（ExpenseStore.displayAmountText；遮住時手錶換「NT$ ••••」）
    var amountText: String
    /// 支出的時間（手錶記的＝按下去那一刻）
    var time: Date
    /// SF Symbol（分類或車子分類的圖示）
    var icon: String
    /// 是不是手錶記的（iPhone 的 watch_imported_ids 裡有）
    var fromWatch: Bool
}

/// [v2] 手錶 → iPhone：記一筆（一按就記、選分類＋金額）。transferUserInfo 與 sendMessage 帶同一份 ["record": JSON]。
/// iPhone 轉成 QuickRecordEntry：id 同一個（也是那筆支出的編號，兩條路都到只記一次）、
/// templateId＝templateId ?? "watch.<id>"（自己打數字的每一筆都不一樣，3 秒內兩筆不會被當手滑，judge §1.4-1）、source＝"watch"。
struct WatchRecord: Codable, Equatable, Identifiable {
    var id: UUID
    /// 按下去那一刻（iPhone 那筆支出的時間；不是送到的時間）
    var createdAt: Date
    /// 一按就記才有（WatchTemplate.id）
    var templateId: String? = nil
    /// 名稱；nil＝iPhone 用分類名
    var title: String? = nil
    /// 台幣
    var amountTWD: Double
    /// 「NT$180」
    var amountText: String
    /// VariableCategory.rawValue
    var categoryKey: String
    var vehicleId: UUID? = nil
    var vehicleCategoryKey: String? = nil

    // MARK: [v6] 旅途中（一律選填；v2 的手錶送來的沒有）

    /// 外幣：iPhone 設定裡那個幣別的寫法（WatchCurrency.code，例「韓元」）＝那筆支出的 currencyCode；nil＝台幣
    var currencyCode: String? = nil
    /// 原幣金額（18000）；台幣的是 nil
    var foreignAmount: Double? = nil
    /// 手錶上換算用的匯率（0.0229；1 單位外幣＝幾台幣）。amountTWD 已經是用它換好的台幣——iPhone 入帳**一律用 amountTWD**，
    /// 隔幾天才入帳、匯率已經更新也不重算（judge §2.14）
    var rateShown: Double? = nil
    /// 記到哪一趟、哪一站（nil＝不在旅途中；tripStopId nil＝記在整趟上）
    var tripPlanId: UUID? = nil
    var tripStopId: UUID? = nil
}

/// [v2] 手錶上不給選的分類（要連到別的東西，留在 iPhone；judge §2.6）。iPhone 組包時拿掉，手錶不會送這幾種
enum WatchCategoryRule {
    static let blockedKeys: Set<String> = ["股票", "房地產", "稅費", "節稅"]

    static func isAllowed(_ key: String) -> Bool {
        !blockedKeys.contains(key)
    }
}

/// [v2] 一天分幾個時段（「這個時段最常寫的名稱」）。iPhone（WatchExtrasWriter）與手錶（RecordText）同一支；
/// 時間一律用 Calendar.current 的小時
enum WatchTimeSlot {
    /// 早 5～10 點、中午 11～14 點、下午 15～16 點、晚上 17～20 點、深夜 21～4 點
    static let keys = ["5-10", "11-14", "15-16", "17-20", "21-4"]

    static func key(hour: Int) -> String {
        if hour >= 5 && hour <= 10 { return "5-10" }
        if hour >= 11 && hour <= 14 { return "11-14" }
        if hour >= 15 && hour <= 16 { return "15-16" }
        if hour >= 17 && hour <= 20 { return "17-20" }
        return "21-4"
    }

    static func key(for date: Date, calendar: Calendar) -> String {
        key(hour: calendar.component(.hour, from: date))
    }

    /// recentAmounts 裡「這個分類、這個時段」那一份的鍵：「飲食@11-14」
    static func amountKey(category: String, slot: String) -> String {
        category + "@" + slot
    }
}

/// [v2] 記一筆的 JSON（不壓縮，一筆不到 1 KB；兩邊同一組編碼器）
enum WatchRecordCodec {
    static func encode(_ record: WatchRecord) -> Data? {
        try? WidgetSnapshotStore.makeEncoder().encode(record)
    }

    static func decode(_ data: Data) -> WatchRecord? {
        try? WidgetSnapshotStore.makeDecoder().decode(WatchRecord.self, from: data)
    }
}

extension WatchMoney {
    /// 照抄 WidgetMoneySnapshot.day(at:)：比第一天還早就用第一天；過了最後一天回 nil
    func day(at date: Date) -> WidgetMoneyDay? {
        if let hit = days.first(where: { $0.contains(date) }) { return hit }
        if let first = days.first, date < first.dayStart { return first }
        return nil
    }

    /// 照抄 WidgetMoneySnapshot.hasEnded(at:)：過了快照裡最後一天（＝過了下個月 7 號）
    func hasEnded(at date: Date) -> Bool {
        guard let last = days.last else { return true }
        return date >= last.dayEnd
    }

    /// 照抄 WidgetMoneySnapshot.isStale(at:)：超過兩天沒更新寫「上次更新 10/20」
    func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(generatedAt) > WidgetFreshness.moneyStaleAfter
    }
}

// MARK: - [v6] 旅行（judge §2.14、§5.2、附錄 A）

/// 旅途中的一天（WatchExtrasWriter 從 LifeStore.tripPlans 的時間軸挑那一天的站、組好；手錶只排版）
struct WatchTripDay: Codable, Equatable {
    var planId: UUID
    /// 「韓國三日遊」（跟 WidgetTrip.title 同一個字：TripPlan.displayTitle 去頭尾空白，空的寫「旅行」）
    var title: String
    /// 「2026-11-07」（WidgetDateText.dayKey）
    var dayKey: String
    /// 這一天 00:00、隔天 00:00（iPhone 用 timeZoneId 那個時區算的）
    var dayStart: Date
    var dayEnd: Date
    /// 第幾天（1 起算，已夾在 1…dayCount）、共幾天（至少 1）
    var dayIndex: Int
    var dayCount: Int
    /// 這一天的站，照時間軸順序（含已經離開的：畫進度條、算「第 3／5 站」）
    var stops: [WatchTripStop]
    /// 這趟記帳用的幣別與匯率（國內旅行、認不得是哪一國、iPhone 設定沒有那個幣別的匯率都是 nil：照台幣記）
    var currency: WatchCurrency? = nil
    /// 認得是哪一國、但 iPhone 設定沒有那個幣別的匯率：「韓元」（手錶記帳台寫「要記韓元：到 iPhone 設定加匯率」）
    var missingCurrencyLabel: String? = nil
    /// 天氣出處網址（TripWeatherStore.attributionURL）。**有任何一站有天氣字才有**；沒有它手錶不准畫天氣（judge §2.14）
    var weatherSource: String? = nil
    /// 這趟最近記過的外幣金額（新到舊、不重複、最多 3 個；已經對齊到錶冠一格）。只有數字，沒有名稱
    var recentAmounts: [Double]? = nil
    /// 這趟最常記的分類 key（多到少，最多 4 個；手錶上不給的已拿掉）：外幣時記帳台換成這幾格
    var topCategoryKeys: [String]? = nil

    func contains(_ date: Date) -> Bool { dayStart <= date && date < dayEnd }
}

/// 旅途中的一站（TripPlan.timeline 的一格＋那一站的地址、座標、電話、打卡、天氣字）
struct WatchTripStop: Codable, Equatable, Identifiable {
    /// TripStop.id（打卡送回 iPhone 用）
    var id: UUID
    /// 跟 life 那一站同一個場次 id（「t」＋行程編號前 8 碼＋抵達時間的秒，TodayAgenda 的寫法）：
    /// 錶面「下一場」點進來找得到這一站
    var timelineStopId: String
    /// 站名（TripStop.displayName）。過夜那一站是飯店名：錶面、手腕放下換「住宿」（手錶自己換）
    var name: String
    var isOvernight: Bool
    /// 時間軸上的抵達、離開（打過卡的是實際時間；後面的站跟著挪，iPhone 算好的）
    var arrival: Date
    var departure: Date
    /// 預計停留（分鐘）
    var dwellMinutes: Int
    /// 地址（TripStop.displayAddress）；沒有是空字串
    var address: String
    var latitude: Double? = nil
    var longitude: Double? = nil
    /// 電話（Apple 地圖給的國際格式「+82 2-3142-0000」，原樣）；沒有是 nil
    var phone: String? = nil
    /// 現場打卡的到達、離開（TripStop.actualArrival／actualDeparture）
    var arrivedAt: Date? = nil
    var departedAt: Date? = nil
    /// 「18°／11° 短暫陣雨 40%」（TripWeatherStore 快取那一天的預報；沒有是 nil）
    var weatherText: String? = nil
    /// SF Symbol（WeatherKit 給的「cloud.drizzle」）
    var weatherSymbol: String? = nil
    /// 天氣提醒前兩句（TripDayWeather.tips：「有 40% 的機會下雨，摺傘放包裡」）
    var weatherTips: [String]? = nil
}

/// 這趟記帳用的外幣
struct WatchCurrency: Codable, Equatable {
    /// iPhone 設定裡那個幣別的寫法（CurrencyRate.code，例「韓元」「KRW」）＝那筆支出存的 currencyCode
    var code: String
    /// 給人看的名字「韓元」
    var label: String
    /// 金額前面的符號「₩」；認不得是 ""（手錶寫「韓元 18,000」）
    var symbol: String
    /// 1 單位外幣＝幾台幣（0.0229；iPhone 設定那一刻的匯率）
    var rateToTWD: Double
    /// 錶冠轉一格多少（韓元 1000、日圓 100、美金 1）
    var crownStep: Double
}

/// [v6] 手錶 → iPhone：打卡（judge §4.1、§4.4、附錄 B）。送的是「設成幾點」不是「切換」：
/// 〔到了〕＝arrival 是按下去那一刻、departure nil；〔離開〕＝departure 是按下去那一刻（arrival 帶手錶上看到的到達時間）。
/// iPhone 只補還沒有的（那一站已經打過卡就不蓋，回「已經在 14:05 打過卡」）；那一站被刪了回「這一站在 iPhone 上改過了」
struct WatchCheckIn: Codable, Equatable, Identifiable {
    var id: UUID
    var planId: UUID
    var stopId: UUID
    var arrival: Date? = nil
    var departure: Date? = nil
    /// 按下去那一刻
    var createdAt: Date
}

/// [v6] 打卡的 JSON（不壓縮；兩邊同一組編碼器）
enum WatchCheckInCodec {
    static func encode(_ checkIn: WatchCheckIn) -> Data? {
        try? WidgetSnapshotStore.makeEncoder().encode(checkIn)
    }

    static func decode(_ data: Data) -> WatchCheckIn? {
        try? WidgetSnapshotStore.makeDecoder().decode(WatchCheckIn.self, from: data)
    }
}

/// 一筆要繳。bill 是 iPhone 小工具那一份消毒過的：
/// 財富（卡費、交割，kind.isWealth）title＝lockedTitle（「卡費」）、amountText＝""、detail＝nil；
/// 每一列 link＝""（手錶不開 iPhone 的網址）；會領回的（isIncome）根本不在這裡。
struct WatchBill: Codable, Equatable, Identifiable {
    var bill: WidgetBill
    /// 自己繳的卡費（WealthCardDue.isManual，iPhone 的 WatchExtrasWriter 算好）：「5 天後・要自己繳」、今天要留意
    var needsAction: Bool

    var id: String { bill.id }
}

// MARK: - 傳話的鍵（iPhone、手錶兩邊同一份）

enum WatchLink {
    /// 手錶 → iPhone：sendMessage(["want": "pkg"])＝給我最新的包（回覆 ["pkg": Data, "v": 1, "t": 秒]；沒有包回 ["none": 1]）
    static let wantKey = "want"
    static let wantPackage = "pkg"
    /// iPhone → 手錶：application context／complication user info／sendMessage 回覆的那一包（LZFSE 壓過的 JSON）
    static let packageKey = "pkg"
    /// 格式號（＝WatchPackage.schemaVersion）
    static let versionKey = "v"
    /// 送出的時間（1970 起的秒）：讓每一次 updateApplicationContext 的內容都不一樣（強制重送也送得出去）
    static let sentAtKey = "t"
    /// 回覆「iPhone 上還沒有包」（iPhone 的 LifeGood 從來沒打開過）
    static let noneKey = "none"
    /// 壓完超過這麼大改用 transferFile（application context 實測上限約 65 KB，judge §5.2）
    static let maxContextBytes = 48 * 1024

    /// 通知〔看議程〕（部屬會議那一類 LG_MEETING 的前景按鈕；iPhone NotificationActions 用同一個字）
    static let viewAgendaAction = "LG_VIEW_AGENDA"
    /// 部屬會議通知 userInfo 的會議 UUID 字串（＝DeepLinkRouter.meetingNotificationKey，iPhone 端寫）
    static let meetingIdKey = "meeting_id"

    // MARK: [v2] 記一筆（附錄 B）

    /// 手錶 → iPhone：["record": Data(WatchRecordCodec)]（transferUserInfo；iPhone 在旁邊再 sendMessage 一次）
    static let recordKey = "record"
    /// iPhone 回 sendMessage：["ok": "imported" | "queued" | "failed", "today": 3]
    static let okKey = "ok"
    /// 已經進帳本（iPhone 的 LifeGood 開著、或剛用過還活著）
    static let okImported = "imported"
    /// 先放 iPhone 收件匣，打開 iPhone 上的 LifeGood 才入帳
    static let okQueued = "queued"
    /// 解不開、寫不進收件匣：手錶留著，transferUserInfo 那一份照樣會到
    static let okFailed = "failed"
    /// 入帳之後今天記了幾筆（iPhone 讀剛寫好的 money 快照；沒有就不帶）
    static let todayCountKey = "today"

    // MARK: [v6] 打卡（附錄 B）

    /// 手錶 → iPhone：["checkIn": Data(WatchCheckInCodec)]（transferUserInfo；iPhone 在旁邊再 sendMessage 一次）。
    /// iPhone 回 ["ok": "done" | "already" | "gone" | "queued" | "failed", "at": 秒]
    static let checkInKey = "checkIn"
    /// 寫進行程了（iPhone 的 LifeGood 開著、或剛用過還活著）
    static let okDone = "done"
    /// 那一站本來就打過卡（不蓋）；"at"＝iPhone 上那個時間（1970 起的秒）
    static let okAlready = "already"
    /// 那一趟或那一站在 iPhone 上被刪了
    static let okGone = "gone"
    /// "already" 帶回來的時間
    static let checkInAtKey = "at"
}

/// 手錶小格的 kind（手錶小格 StaticConfiguration 與手錶 App／WatchSync 的 reloadTimelines(ofKind:) 都用這裡）
enum WatchWidgetKind {
    /// 下一場（圓形、角落、一行字、長方形）
    static let nextUp = "LifeGoodWatchNextUp"
    /// 已花（圓形、角落、一行字、長方形）
    static let spent = "LifeGoodWatchSpent"
    /// 會跟著包變的小格（重畫用）。[v2]「＋ 記一筆」（add）不讀包、不用重畫，不在這裡
    static let all = [nextUp, spent]
    /// [v2] ＋ 記一筆（圓形、角落；點了開記帳台）
    static let add = "LifeGoodWatchAdd"
}

// MARK: - 壓縮與解開（兩邊同一組編碼器）

enum WatchPackageCodec {
    /// JSON（WidgetSnapshotStore.makeEncoder：sortedKeys、日期原樣）→ LZFSE。失敗回 nil
    static func encode(_ package: WatchPackage) -> Data? {
        guard let json = try? WidgetSnapshotStore.makeEncoder().encode(package) else { return nil }
        guard let packed = try? (json as NSData).compressed(using: .lzfse) else { return nil }
        return packed as Data
    }

    /// LZFSE → JSON → WatchPackage；解不開、schema 對不上回 nil（當作沒收到）
    static func decode(_ data: Data) -> WatchPackage? {
        guard let json = try? (data as NSData).decompressed(using: .lzfse) else { return nil }
        guard let package = try? WidgetSnapshotStore.makeDecoder().decode(WatchPackage.self, from: json as Data) else {
            return nil
        }
        guard package.schema == WatchPackage.schemaVersion else { return nil }
        return package
    }
}

// MARK: - 新舊兩包比一比

enum WatchPackageDiff {
    /// 錶面小格要重畫哪幾種：沒有舊包＝全部；行程或要繳變了（「卡費今天截止」在下一場第三行）→ 下一場；
    /// 錢或 iPhone 的隱藏金額變了 → 已花。iPhone 決定要不要用 transferCurrentComplicationUserInfo、
    /// 手錶在背景收到新包時只重畫這幾種，都用這一支。
    /// [v6] 旅途中今天、明天的站變了（打卡、改站）也重畫下一場（旅途中「下一場」寫下一站）
    static func widgetKinds(old: WatchPackage?, new: WatchPackage) -> [String] {
        guard let old else { return WatchWidgetKind.all }
        var kinds: [String] = []
        if old.life != new.life || old.bills != new.bills
            || old.tripToday != new.tripToday || old.tripTomorrow != new.tripTomorrow {
            kinds.append(WatchWidgetKind.nextUp)
        }
        if old.money != new.money || old.phoneHidesAmounts != new.phoneHidesAmounts {
            kinds.append(WatchWidgetKind.spent)
        }
        return kinds
    }

    /// 新來的這一包比手上的舊（兩條路一起到、順序顛倒）：不收
    static func isOlder(_ new: WatchPackage, than old: WatchPackage?) -> Bool {
        guard let old else { return false }
        return new.generatedAt < old.generatedAt
    }
}
