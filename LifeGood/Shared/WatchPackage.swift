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
// [手錶 v4] v25.580（watch/judge.md §2.9、§5.7、附錄 A；watch/build/v4/brief.md §2）：手錶自己記跑步——
//   • 包多 runWeek（這週跑步：主角運動、這週公里、次數、目標、連續週數、每天公里、iPhone 處理過的手錶跑步編號 seen；選填）。
//     只有數字與 Apple 健康編號：沒有地名、路線、心率、名字
//   • WatchRunMeta：手錶寫進 Apple 健康那一筆的 LifeGood 附註（鍵、寫法）；手錶寫、iPhone 帶進來時讀，兩邊同一組
// [手錶 v5] v25.582（watch/judge.md §2.12、§2.13、§3.1、§6.1、附錄 B；watch/build/v5/brief.md §2）：跑步——這週、錶面、老路線
//   • WatchRunWeek 多 recent（這週那幾趟，最多 5 趟：名字兩種、時間、公里、秒數、⌚︎、0～1000 相對形狀最多 40 點、亮點字）、
//     latest（最新一趟的亮點字，跨週也留著）。**沒有經緯度、沒有比例尺、沒有地點、沒有心率**（心率只在手錶自己記的那一份）
//   • WatchRunRecent／WatchRunHighlight／WatchRunShapeXY：手錶自己的型別（WorkoutSession／WorkoutHighlights 照舊不准進包）
//   • 手錶 → iPhone 的「我跑完了」ranWorkout（＋ranAt）、「沒存成」unsavedRun（WatchLink 鍵）
//   • 錶面「這週跑步」小格的 kind（WatchWidgetKind.runWeek）；runWeek 變了重畫它（WatchPackageDiff）
// [手錶 v7b] v25.584（watch/judge.md §3.2、§3.4、§2.16、§2.17、§6.1；watch/build/v7b/brief.md §2）：watchOS 26 的卡與控制項
//   • 包多 relevanceCards（智慧型堆疊卡：iPhone 照設定挑好、字寫好的早安、快開會了、卡費快到了、旅途下一站，
//     加上平常跑步的時段；選填。iPhone「智慧型堆疊卡」總開關關掉＝nil）。WatchRelevanceCards／WatchRelevanceCard／
//     WatchCardLine／WatchRunSlot 只有卡上那幾個字、圖示名、時間與點了開哪裡——**卡費沒有卡名、金額、末四碼；
//     會議沒有部屬名字；沒有天氣**（組卡的規則在 Shared/WatchRelevance.swift，pkg_keys_check C7 擋）
//   • 堆疊卡、控制項的 kind（WatchWidgetKind.card*／control*）；WatchPackageDiff.relevanceKinds（手錶收到新包要重新問系統
//     「什麼時候浮上來」的那幾種）

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

    // MARK: [v4] 跑步（選填；v6 以前的 iPhone 送來的沒有）

    /// 這週跑步（iPhone 健康頁看板同一套數字，WatchExtrasWriter 算好）。手錶自己記、seen 裡沒有的那幾趟，
    /// 手錶自己加上去（WatchRunText.home）；iPhone 從來沒算過（還沒更新、健康頁沒打開過）是 nil：③ 大字寫「—」
    var runWeek: WatchRunWeek? = nil

    // MARK: [v7b] 智慧型堆疊卡（選填；v5 以前的 iPhone 送來的沒有）

    /// 智慧型堆疊卡（WatchRelevancePlan.cards 從這一包已經消毒過的 life／bills／旅行組；平常跑步的時段 WatchExtrasWriter 算）。
    /// iPhone 設定「智慧型堆疊卡」關掉是 nil：手錶不浮任何卡，你自己加的「下一場」「已花」「這週跑步」也不自己往上排
    var relevanceCards: WatchRelevanceCards? = nil
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

// MARK: - [v4] 跑步（judge §2.9、§5.7、附錄 A）

/// [v4] 這週跑步（iPhone 的 WatchRunWeekBuilder 用 WorkoutFacts 算好；跟健康頁看板、小工具「這週跑了」同一套）。
/// 一週從星期一算（WorkoutFacts.weekStart）。只有數字與 Apple 健康編號：沒有地名、路線、心率、名字
struct WatchRunWeek: Codable, Equatable {
    /// iPhone 算這一份的時間
    var generatedAt: Date
    /// 這週主角運動（WorkoutSport.rawValue：run／walk／bike／hike；WorkoutFacts.heroSport）
    var sport: String
    /// 這週週一 00:00。手錶的「這週」跟它不一樣＝iPhone 的數字是上週的（手錶從 0 算起，WatchRunText.home）
    var weekStart: Date
    /// 這週主角運動的公里（WorkoutFacts.weekDistanceKm）
    var doneKm: Double
    /// 每週目標（WorkoutPrefs.goalKm(for:)）；沒設是 nil
    var goalKm: Double? = nil
    /// 這週含主角運動的趟數（WorkoutFacts.weekCount）
    var runs: Int
    /// 週一到週日每天的公里（7 個；主角運動）：③ 小風景條插旗
    var dayKm: [Double]
    /// 連續幾週有運動（WorkoutFacts.streak）
    var streakWeeks: Int
    /// 這週已經算進連續週數（這週有任何一趟算數的運動）。false 時手錶自己跑了一趟（任何運動）＝連續週數 +1
    var weekCounted: Bool
    /// iPhone 處理過的手錶跑步 Apple 健康編號：這週帶進來的、合成用掉的、最近「不再帶進來」的（在 iPhone 刪掉的那一趟）。
    /// 手錶自己記的那一趟編號在這裡＝iPhone 已經算過（或你刪掉了），手錶不再自己加
    var seen: [String]

    // MARK: [v5] 這週那幾趟、最新一趟的亮點（選填；v4 的 iPhone 送來的沒有）

    /// 這週那幾趟（新到舊、最多 5 趟；跑走騎登山）：手錶「這週」清單、「那一趟」（WatchRunRecentBuilder.recent）
    var recent: [WatchRunRecent]? = nil
    /// 最新一趟（LifeGood 手錶記的、2 天內）的亮點字：手錶摘要「河濱老路線・第 12 次…」那兩行。跨週也留著
    /// （週日晚上跑、週一才帶進 iPhone）。都沒有 nil（WatchRunRecentBuilder.latest）
    var latest: WatchRunHighlight? = nil
}

/// [v5] 這週的一趟（iPhone 的 WatchRunRecentBuilder 組；手錶「這週」清單一列、「那一趟」）。
/// 名字有兩種（抬手寫你取的、手腕放下寫時段名）；路線只有 0～1000 的相對形狀
struct WatchRunRecent: Codable, Equatable, Identifiable {
    /// iPhone 那一趟的編號（WorkoutSession.id）
    var id: String
    /// Apple 健康編號（手錶記的那一趟帶進來、或跟 iPhone 那一筆合成過的：手錶拿它對自己的 WatchRunLog）；沒有 nil
    var workoutId: String? = nil
    /// WatchSport.rawValue（run／walk／bike／hike）
    var sport: String
    /// 抬手：「河濱晨跑」（你取的名字，可能是地名；只在手錶 App 抬手出現）
    var title: String
    /// 手腕放下：「晨跑」（你自己取的名字換成時段名；judge §2.17）
    var privateTitle: String
    var start: Date
    /// 這一種運動的公里（同一趟的動作加總）
    var km: Double
    /// 移動秒數（扣掉暫停）
    var movingSeconds: Double
    /// LifeGood 手錶記的（列尾 ⌚︎）
    var byLifeGoodWatch: Bool = false
    /// 路線形狀（0～1000、北在上、最多 40 點；沒有經緯度）；沒有路線 nil
    var shape: [WatchRunShapeXY]? = nil
    /// 這一趟的亮點（同一條路第幾次、破紀錄）；都沒有 nil
    var highlight: WatchRunHighlight? = nil
}

/// [v5] 一趟的亮點字（iPhone 照 WorkoutSession.highlights 寫好：WorkoutFacts.routeCapsule／routeDeltaText／recordValueText；
/// 手錶只排版，不重算）
struct WatchRunHighlight: Codable, Equatable {
    /// iPhone 那一趟的編號
    var sessionId: String
    /// Apple 健康編號（手錶摘要拿它認「是不是剛跑完的那一趟」）；沒有 nil
    var workoutId: String? = nil
    /// 那一趟開始的時間（「這週」那一行的「（今天）」）
    var start: Date
    /// 「河濱老路線・第 12 次」（同一條路第 2 次起才有；抬手）
    var routeHead: String? = nil
    /// 「老路線・第 12 次」（手腕放下：不寫地名）
    var routePrivateHead: String? = nil
    /// 「比上次快 42 秒」「比上次慢 15 秒」「跟上次差不多」；算不出來 nil
    var routeDelta: String? = nil
    /// 比上次快（「比上次快 42 秒」綠 5BD99A）；慢、差不多 false；沒有比 nil
    var routeFaster: Bool? = nil
    /// 「最快 5 公里 新紀錄 30:51（快 18 秒）」（破紀錄才有；只寫第一個）
    var recordLine: String? = nil
    /// 「最快 5 公里 30:51」（手錶「這週」那一行）
    var recordShort: String? = nil
}

/// [v5] 路線形狀的一點：0～1000 的相對座標（北在上、等比例、置中）＋第幾段（暫停前後不連線）。
/// 沒有經緯度、沒有比例尺：看得出形狀，看不出在哪裡
struct WatchRunShapeXY: Codable, Equatable {
    var x: Int
    var y: Int
    /// 第幾段（0 起）
    var s: Int
}

/// [v4] 手錶寫進 Apple 健康那一筆的 LifeGood 附註（自訂 metadata；鍵不能用 HK 開頭）。
/// 手錶（WorkoutManager）寫、iPhone（HealthKitManager.makeImported）讀，兩邊同一組（judge §5.7）
enum WatchRunMeta {
    /// 「watch 25.580」：LifeGood 手錶記的（iPhone 認來源的第二道：bundle id 之外再看這個）
    static let recorderKey = "LifeGood.recorder"
    /// 「365,735,1105,1485,1851」：每跑滿一公里那一刻的移動秒數（整數秒；暫停不算）
    static let kmTimesKey = "LifeGood.kmTimes"
    /// 「1,1」：每一次暫停是不是自動的（1＝自動）；iPhone 照 Apple 健康的暫停事件分，這個留著查問題
    static let autoPausesKey = "LifeGood.autoPauses"
    /// recorder 的開頭
    static let recorderPrefix = "watch"
    /// kmTimes 最多幾個（超過的不寫：1,000 公里）
    static let maxTimes = 1_000

    /// 「watch 25.580」；版號空的＝「watch」
    static func recorder(version: String) -> String {
        let v = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? recorderPrefix : recorderPrefix + " " + v
    }

    /// 秒數取整數（四捨五入）；NaN、負的當 0，超大夾住（Int(Double) 碰到這些會閃退；arm64_32 的 Int 是 32 位）
    static func whole(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(min(seconds, 360_000_000).rounded())
    }

    /// [365.2, 734.8] →「365,735」（最多 maxTimes 個）
    static func encodeTimes(_ times: [Double]) -> String {
        times.prefix(maxTimes).map { String(whole($0)) }.joined(separator: ",")
    }

    /// 「365,735」→ [365, 735]；空的、看不懂、不是一個比一個大的回 nil（整份不用，iPhone 改用路線推算）
    static func decodeTimes(_ text: String?) -> [Double]? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        var out: [Double] = []
        var prev = 0.0
        for part in text.split(separator: ",", omittingEmptySubsequences: false) {
            guard let v = Double(part.trimmingCharacters(in: .whitespaces)), v.isFinite, v > prev else { return nil }
            out.append(v)
            prev = v
            if out.count > maxTimes { return nil }
        }
        return out
    }

    /// [true, false] →「1,0」
    static func encodeFlags(_ flags: [Bool]) -> String {
        flags.map { $0 ? "1" : "0" }.joined(separator: ",")
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

// MARK: - [v7b] 智慧型堆疊卡（watchOS 26；judge §3.2、§2.16、§2.17、§6.1）

/// [v7b] 堆疊卡那一包。iPhone 照設定挑好、字寫好（WatchRelevancePlan.cards）；手錶小格到時間才請系統浮上來
struct WatchRelevanceCards: Codable, Equatable {
    /// 早安、快開會了、卡費快到了、旅途下一站（今天、明天；卡費是截止前 3 天到當天）。關掉的那幾種 iPhone 根本不放
    var cards: [WatchRelevanceCard]
    /// 平常跑步的時段（近 4 週同一時段 3 次以上，最多 2 段）。「平常跑步的時間」關掉是空的。
    /// 卡上的公里、還差幾公里手錶自己算（③ 跑步同一套 WatchRunText.home），所以包裡只有時段與時段名
    var runSlots: [WatchRunSlot]
}

/// [v7b] 一張堆疊卡（三行字＋什麼時候浮上來＋點了開哪裡）。**錶面、堆疊＝鎖定畫面**：
/// 卡費只寫「卡費」與日期（沒有卡名、金額、末四碼），會議寫主題不寫部屬名字，旅途下一站不放天氣
struct WatchRelevanceCard: Codable, Equatable, Identifiable {
    /// 「meeting@<場次 id>」「cardBill@2026-10-27@3」…（WatchRelevancePlan.cardId；手錶小格拿它找回這一張）
    var id: String
    /// WatchRelevanceKind.rawValue（morning／meeting／cardBill／usualRun／tripStop）
    var kind: String
    /// 從什麼時候到什麼時候該浮上來（end 一定比 start 晚）
    var start: Date
    var end: Date
    /// 抬手時的三行（最多 3 行）
    var lines: [WatchCardLine]
    /// 手腕放下、沒解鎖時換這一份（會議名、站名、旅行名抬手才寫）；nil＝跟 lines 一樣（本來就沒有名字）
    var privateLines: [WatchCardLine]? = nil
    /// 點了開手錶 App 哪裡（WidgetLink 組好的 absoluteString；手錶 WatchModel.open 認得的那幾種）
    var link: String
}

/// [v7b] 堆疊卡的一行：前面一個 SF Symbol、可以上色的開頭一段（「3 天後」琥珀）、其餘的字
struct WatchCardLine: Codable, Equatable {
    /// SF Symbol（「sun.horizon.fill」「birthday.cake.fill」「creditcard.fill」…）；nil＝不畫圖示
    var icon: String? = nil
    /// 圖示的顏色 0xRRGGBB；nil＝跟字一樣
    var tint: UInt32? = nil
    /// 開頭上色的那一段（「3 天後」「還差 10.6」）；nil＝沒有
    var lead: String? = nil
    var text: String
    /// lead 的顏色（沒有 lead 時是整行的）："amber"、"blue"、"dim"；nil＝一般
    var tone: String? = nil
}

/// [v7b] 平常跑步的一個時段（一天裡的分鐘數；05:45–06:30＝345…390）。iPhone 用近 4 週主角運動的開始時間算
struct WatchRunSlot: Codable, Equatable {
    var startMinute: Int
    var endMinute: Int
    /// 時段名「晨跑」「夜跑」「晨走」（WorkoutFacts.timeOfDayName；卡上寫「平常晨跑的時間」）
    var label: String
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

    // MARK: [v5] 我跑完了、沒存成（附錄 B）

    /// 手錶 → iPhone：["ranWorkout": "<Apple 健康編號>", "ranAt": 結束秒]（transferUserInfo；iPhone 在旁邊再 sendMessage 一次、不等回話）。
    /// 編號空字串＝存好了但讀不到編號（iPhone 照樣馬上同步一次）。〔再存一次〕存好也送這個（iPhone 順手清掉「沒存成」旗子）
    static let ranWorkoutKey = "ranWorkout"
    /// 那一趟結束的時間（1970 起的秒；iPhone 設定頁「手錶上次跑完 06:45」）
    static let ranAtKey = "ranAt"
    /// 手錶 → iPhone：["unsavedRun": 1]＝有一趟存不進 Apple 健康、留在手錶上；0＝沒有了（存好了、丟掉了、過期了）
    static let unsavedRunKey = "unsavedRun"
}

/// 手錶小格的 kind（手錶小格 StaticConfiguration 與手錶 App／WatchSync 的 reloadTimelines(ofKind:) 都用這裡）
enum WatchWidgetKind {
    /// 下一場（圓形、角落、一行字、長方形）
    static let nextUp = "LifeGoodWatchNextUp"
    /// 已花（圓形、角落、一行字、長方形）
    static let spent = "LifeGoodWatchSpent"
    /// 會跟著包變的小格（重畫用）。[v2]「＋ 記一筆」（add）不讀包、不用重畫，不在這裡。[v5] 多「這週跑步」
    static let all = [nextUp, spent, runWeek]
    /// [v2] ＋ 記一筆（圓形、角落；點了開記帳台）
    static let add = "LifeGoodWatchAdd"
    /// [v5] 這週跑步（圓形、角落、一行字、長方形；包裡的 runWeek＋手錶自己記的 WatchRunLog）
    static let runWeek = "LifeGoodWatchRunWeek"

    // MARK: [v7b] 智慧型堆疊卡（watchOS 26；只在堆疊出現、不能手動加）與控制項（watchOS 26）

    static let cardMorning = "LifeGoodWatchCardMorning"
    static let cardMeeting = "LifeGoodWatchCardMeeting"
    static let cardBill = "LifeGoodWatchCardBill"
    static let cardRun = "LifeGoodWatchCardRun"
    static let cardTrip = "LifeGoodWatchCardTrip"
    /// 五種堆疊卡
    static let cards = [cardMorning, cardMeeting, cardBill, cardRun, cardTrip]
    /// 控制項：＋ 記一筆、▶ 開始跑步、遮住金額（手錶）
    static let controlAdd = "LifeGoodWatchControlAdd"
    static let controlRun = "LifeGoodWatchControlRun"
    static let controlHide = "LifeGoodWatchControlHide"
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
    /// [v5] 這週跑步變了 → 這週跑步
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
        // [v5] 這週跑步（iPhone 帶進來一趟、改目標、刪掉一趟）
        if old.runWeek != new.runWeek {
            kinds.append(WatchWidgetKind.runWeek)
        }
        return kinds
    }

    /// [v7b] 智慧型堆疊要重新問「什麼時候該浮上來」的幾種（手錶收到新包、內容真的變了時 invalidateRelevance）：
    /// 沒有舊包、堆疊卡那一包變了（含總開關）＝全部（下一場、已花、這週跑步＋5 種卡）；
    /// 行程變了＝下一場；有沒有「錢」變了＝已花；這週跑步變了＝這週跑步＋平常跑步的時間（卡上的公里、週日差幾公里）
    static func relevanceKinds(old: WatchPackage?, new: WatchPackage) -> [String] {
        let everything = [WatchWidgetKind.nextUp, WatchWidgetKind.spent, WatchWidgetKind.runWeek] + WatchWidgetKind.cards
        guard let old else { return everything }
        if old.relevanceCards != new.relevanceCards { return everything }
        var kinds: [String] = []
        if old.life != new.life {
            kinds.append(WatchWidgetKind.nextUp)
        }
        if (old.money == nil) != (new.money == nil) {
            kinds.append(WatchWidgetKind.spent)
        }
        if old.runWeek != new.runWeek {
            kinds.append(WatchWidgetKind.runWeek)
            kinds.append(WatchWidgetKind.cardRun)
        }
        return kinds
    }

    /// 新來的這一包比手上的舊（兩條路一起到、順序顛倒）：不收
    static func isOlder(_ new: WatchPackage, than old: WatchPackage?) -> Bool {
        guard let old else { return false }
        return new.generatedAt < old.generatedAt
    }
}
