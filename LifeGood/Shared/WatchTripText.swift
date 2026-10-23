import Foundation

// MARK: - 旅行的字與規則（手錶 v6，v25.578；watch/judge.md §2.14、§2.17、§3.1、§4.1、§4.4、§5.6、§6.1；
//         watch/build/v6/brief.md §2）
//
// 這個檔只屬於手錶兩個 target（LifeGoodWatch、LifeGoodWatchWidgets），iPhone 兩個 target 都不編。
// 只准用 Foundation 與 WatchPackage.swift／WidgetSnapshot.swift／DayTimelineAttributes.swift／WatchText.swift 的純資料型別。
// scratchpad/watch/build/v6/sim_v6.py 跟這個檔一模一樣（同名函式），改了兩邊一起改、重跑 sim。
//
// 手錶「只排版、不算」：站、時間、第幾站、天氣字都是 iPhone 組好的（WatchTripDay，WatchExtrasWriter）；
// 這裡只挑現在是哪一站、把幾段字用「・」接起來、把手錶上按過還沒被 iPhone 確認的打卡補上去。
//
// 隱私（judge §2.17、§6.1）：站名、時間、天氣、出處都照顯示（景點算低隱私）；過夜那一站錶面、手腕放下寫「住宿」
// （不露飯店名）；記一筆的金額照 WatchPrivacyRule 遮。**錶面、智慧型堆疊不放天氣**（放不下「 Weather」出處）。
// 天氣一定跟出處一起：包裡沒有 weatherSource，這裡就不給天氣字（WeatherKit 規定，judge §2.14）。
//
// 打卡（WatchCheckInLog）：存在**手錶**的 App Group UserDefaults（手錶小格也讀得到，錶面「下一場」按了〔到了〕馬上換）。
// 一筆＝一次〔到了〕或〔離開〕；iPhone 寫回包裡（那一站有到達／離開時間了）、24 小時、iPhone 說那一站不在了 → 拿掉。

// MARK: - ④ 旅行那一頁什麼時候有

enum WatchTripPageKind: Equatable {
    /// 旅途中（包裡有今天的站，或出發那天到回來那天）：排第一頁
    case during
    /// 出發前 7 天到出發前一天：排最後一頁
    case upcoming
}

extension WatchLife {
    /// 照抄 WidgetLifeSnapshot.tripPhase(at:)（WidgetSnapshot.swift）；scratchpad/watch/build/v6/copy_check_v6.py 核對
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

// MARK: - 手錶上按過的打卡（還沒被 iPhone 寫回包裡的）

struct WatchCheckInItem: Codable, Equatable, Identifiable {
    enum State: String, Codable {
        /// 還沒送出去（WatchConnectivity 還沒啟動好）
        case holding
        /// 送出了（transferUserInfo 排隊中）
        case sent
        /// iPhone 收到了（transferUserInfo 送完，還沒有回話）
        case delivered
        /// iPhone 回：先排著，打開 iPhone 上的 LifeGood 才寫進行程
        case queued
        /// iPhone 回：寫進行程了
        case done
        /// iPhone 回：那一站本來就打過卡（phoneTime 是 iPhone 上那個時間）
        case already
    }

    var checkIn: WatchCheckIn
    var state: State
    var phoneTime: Date? = nil

    var id: UUID { checkIn.id }
    var isDeparture: Bool { checkIn.departure != nil }
}

/// 手錶 App Group UserDefaults「watch_trip_checkins_v1」（JSON）。任何執行緒都可以叫（同一個行程裡過 lock）；
/// 手錶小格只讀（WatchText.nextUp 補上還沒被確認的打卡）
enum WatchCheckInLog {
    static let key = "watch_trip_checkins_v1"
    /// 留多久（按下去之後）
    static let keep: TimeInterval = 24 * 3600
    /// 包要比按下去晚這麼多，「那一站不在包裡」才算數
    static let missSlack: TimeInterval = 60

    private static let lock = NSLock()

    static func all() -> [WatchCheckInItem] {
        lock.lock()
        defer { lock.unlock() }
        return unlockedAll()
    }

    /// 加一筆（同一個編號換掉）
    static func add(_ item: WatchCheckInItem) {
        lock.lock()
        defer { lock.unlock() }
        var list = unlockedAll().filter { $0.id != item.id }
        list.append(item)
        unlockedSave(list)
    }

    /// 讀出那一筆、改、寫回；沒有那一筆回 false
    @discardableResult
    static func update(_ id: UUID, _ change: (inout WatchCheckInItem) -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var list = unlockedAll()
        guard let i = list.firstIndex(where: { $0.id == id }) else { return false }
        change(&list[i])
        unlockedSave(list)
        return true
    }

    static func remove(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        unlockedSave(unlockedAll().filter { $0.id != id })
    }

    /// 收到 iPhone 的新包（WatchSync.applyData 寫好檔之後，背景執行緒）：iPhone 已經寫回去的、太舊的、那一站不在了的拿掉
    static func reconcile(with package: WatchPackage, now: Date) {
        lock.lock()
        defer { lock.unlock() }
        let old = unlockedAll()
        let kept = reconciled(old, package: package, now: now)
        if kept != old {
            unlockedSave(kept)
        }
    }

    /// 純規則（sim_v6.py checkin_reconcile）：
    ///   • 按下去超過 24 小時 → 拿掉
    ///   • 包裡找得到那一站，而且這一筆要的都有了（〔到了〕看到達、〔離開〕看離開；時間以 iPhone 的為準）→ 拿掉
    ///   • 包裡找不到那一站、iPhone 回過 done／already、包比按下去晚 60 秒以上 → 那一站在 iPhone 上被改掉了，拿掉
    ///   • 其他留著（queued：等打開 iPhone 上的 LifeGood；還沒回話的：等）
    static func reconciled(_ items: [WatchCheckInItem], package: WatchPackage, now: Date) -> [WatchCheckInItem] {
        let days: [WatchTripDay] = [package.tripToday, package.tripTomorrow].compactMap { $0 }
        var out: [WatchCheckInItem] = []
        for item in items {
            let c = item.checkIn
            if now.timeIntervalSince(c.createdAt) >= keep { continue }
            var found: WatchTripStop? = nil
            for day in days where day.planId == c.planId {
                if let s = day.stops.first(where: { $0.id == c.stopId }) {
                    found = s
                    break
                }
            }
            if let s = found {
                let arrivalDone = c.arrival == nil || s.arrivedAt != nil
                let departureDone = c.departure == nil || s.departedAt != nil
                if arrivalDone && departureDone { continue }
            } else if item.state == .done || item.state == .already,
                      package.generatedAt > c.createdAt.addingTimeInterval(missSlack) {
                continue
            }
            out.append(item)
        }
        return out
    }

    private static func unlockedAll() -> [WatchCheckInItem] {
        guard let data = WidgetShared.defaults?.data(forKey: key),
              let list = try? WidgetSnapshotStore.makeDecoder().decode([WatchCheckInItem].self, from: data) else {
            return []
        }
        return list
    }

    private static func unlockedSave(_ items: [WatchCheckInItem]) {
        guard let d = WidgetShared.defaults else { return }
        if items.isEmpty {
            d.removeObject(forKey: key)
            return
        }
        guard let data = try? WidgetSnapshotStore.makeEncoder().encode(items) else { return }
        d.set(data, forKey: key)
    }
}

/// 〔到了〕〔離開〕下面那一行（TripCheckIns 組、TripPage／TripStopDetail 畫）
enum WatchCheckInStatus: Equatable {
    /// 送出去了，等 iPhone 回話（最多 5 秒）
    case waiting
    /// 還沒送到 iPhone（不在旁邊、還沒啟動好、沒回話）
    case offline
    /// iPhone 收到了（還沒回話）
    case delivered
    /// iPhone 被叫醒、LifeGood 沒開：排著，打開才寫進行程
    case queued
    /// 寫進 iPhone 的行程了
    case done
    /// 那一站本來就打過卡（iPhone 上那個時間）
    case already(Date)
    /// 那一趟或那一站在 iPhone 上被刪了
    case gone
}

// MARK: - ④ 旅行那一頁（judge §2.14；樣稿①-6、③第三排第 6 格）

struct WatchTripPage: Equatable {
    enum Mode: Equatable {
        /// 出發前 7 天到出發前一天
        case upcoming
        /// 下一站（還沒到）
        case next
        /// 現在這一站（到了還沒離開）
        case here
        /// 今天的站都走完了
        case dayDone
        /// 旅途中、今天沒有排站
        case noStops
        /// 旅途中、包裡沒有今天那一份（iPhone 的 LifeGood 很久沒打開）
        case stale
    }

    enum Action: Equatable {
        case arrive
        case depart
    }

    var mode: Mode
    /// 「韓國三日遊・第 2 天」（一天的行程不寫第幾天；出發前「韓國三日遊」）
    var header: String
    /// 「下一站・25 分後・第 3／5 站」「現在・第 3／5 站」「11/6（五）08:40 出發」
    var line2: String
    var line2IsAmber: Bool
    /// 大字：下一站的時間「14:00」、現在這一站的名字「弘大」、出發前「還有 7 天」
    var big: String
    /// 大字是時間（Title1 等寬）；不是＝站名（Title2）
    var bigIsTime: Bool
    /// 大字下面：下一站的名字「弘大」、現在「14:12 到了」（前面畫綠勾）、出發前「行李 8／15」
    var line4: String?
    var line4IsArrived: Bool
    /// 現在這一站的下一行：「下一站 17:30 明洞」「明天 09:30 景福宮」
    var line5: String?
    /// 「18°／11° 短暫陣雨 40%」；沒有天氣（或包裡沒有出處）是 nil——這時出處那一行也不畫
    var weatherText: String?
    var weatherSymbol: String?
    /// 天氣下面緊接著「 Weather ›」（點了開出處頁）
    var showsSource: Bool
    /// 進度條上每一站的位置 0…1（出發前、沒有站是空的）
    var dots: [Double]
    /// 飛機在哪 0…1（nil＝不畫進度條）
    var plane: Double?
    /// 底部主鈕〔到了〕〔離開〕；nil＝沒有
    var action: Action?
    /// 現在這一站／下一站（點大字那一塊推進去這一站）
    var focusStopId: UUID?
    var planId: UUID?
    /// 現在這一站的到達時間（〔離開〕送 iPhone 時一起帶：iPhone 那邊沒有到達時補上）；其他 nil
    var focusArrivedAt: Date? = nil
}

/// 這一站（第二層；judge §2.14「點大字那一塊」）
struct WatchTripStopDetail: Equatable {
    /// 站名（手腕放下過夜那一站「住宿」）
    var title: String
    /// 「第 3／5 站・14:00 到」
    var timeLine: String
    /// 「預計停留 90 分」「過夜」
    var dwellLine: String
    /// 「14:12 到了」「14:12 到・15:40 離開」；還沒到 nil
    var stateLine: String?
    /// 地址（沒有、或手腕放下的過夜那一站是 nil）
    var address: String?
    /// 有座標才有〔導航〕
    var latitude: Double?
    var longitude: Double?
    /// 〔電話〕：顯示「+82 2-3142-0000」、撥號「+8223142000」（只留數字與 +）；沒有是 nil
    var phoneText: String?
    var phoneDial: String?
    var weatherText: String?
    var weatherSymbol: String?
    /// 天氣兩句（有天氣字才有）
    var tips: [String]
    var showsSource: Bool
}

/// [記一筆] 記到哪裡
struct WatchTripRecordTarget: Equatable, Hashable {
    var planId: UUID
    /// nil＝整趟
    var stopId: UUID?
    /// 「弘大」；整趟是 nil
    var stopName: String?
}

/// [記一筆] 「記到哪裡」那一頁的一列
struct WatchTripRecordChoice: Equatable, Identifiable {
    var id: String
    var target: WatchTripRecordTarget
    /// 「弘大」「整趟」
    var title: String
    /// 「14:00・第 3 站」；整趟「韓國三日遊」
    var detail: String
}

/// [記一筆] 旅途中記帳用得到的（RecordSheet、AmountPicker；judge §2.14「旅途中記一筆自動變外幣」）
struct WatchTripRecordContext: Equatable {
    var planId: UUID
    /// nil＝照台幣記（國內旅行、iPhone 設定沒有那個幣別的匯率）
    var currency: WatchCurrency?
    /// 認得是哪一國、但 iPhone 沒有匯率：「韓元」
    var missingCurrencyLabel: String?
    /// 預設記到哪（現在打卡的那一站；沒打卡＝時間最近那一站；今天沒有站＝整趟）
    var defaultTarget: WatchTripRecordTarget
    /// 可以選的：今天的站（照時間軸）＋最後一列「整趟」
    var choices: [WatchTripRecordChoice]
    /// 這趟最常記的分類（外幣時記帳台換成這幾格）
    var topCategoryKeys: [String]
    /// 這趟最近記過的外幣金額（新到舊，只有外幣才有）
    var recentAmounts: [Int]
}

enum WatchTripText {
    // MARK: 常數與固定的字

    /// 出發前幾天開始多一頁
    static let upcomingDays = 7
    static let timeZoneHintText = "換時區了：打開 iPhone 上的 LifeGood 一次，日期才會對"
    static let staleText = "打開 iPhone 上的 LifeGood 一次，才有今天的站"
    /// 天氣出處（天氣下面那一行、出處頁的標題）；U+F8FF 在 Apple 的字型裡是  標誌
    static let sourceLabel = "\u{F8FF} Weather"
    static let sourceTitle = "天氣資料：\u{F8FF} Weather"
    static let sourceFallback = "打不開的話，請在 iPhone 旅行頁點「資料來源」"
    /// 包裡萬一沒帶出處網址（不會發生：沒有出處就不畫天氣）時出處頁用的（＝TripWeatherStore.attributionURL）
    static let sourceDefaultURL = "https://weatherkit.apple.com/legal-attribution.html"
    /// 過夜那一站在錶面、手腕放下的名字
    static let overnightLock = "住宿"
    static let wholeTripTitle = "整趟"
    static let arriveTitle = "到了"
    static let departTitle = "離開"
    static let navigateTitle = "導航"
    static let callTitle = "電話"
    /// 外幣時記帳台最下面那一行
    static let foreignDeskHint = "在國外：記帳台換成這趟常用的分類"
    /// 外幣金額上限（數字鍵最多 6 位數）
    static let maxForeignAmount = 999_999
    /// 外幣錶冠最多幾格
    static let maxForeignSteps = 1000
    /// 換算成台幣的上限（iPhone 收件匣 WatchRecordInbox.maxAmount 是 1,000 萬）
    static let maxTWD = 9_999_999

    // MARK: 共用小字

    /// 「1,200」（每三位一個逗號；不靠語系；同 RecordText.grouped）
    static func grouped(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 {
                out += ","
            }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }

    static func time(_ d: Date) -> String { DayTimelineFormat.time(d) }

    /// 「第 3／5 站」（k 從 0 起）
    static func positionText(_ k: Int, _ n: Int) -> String {
        "第 \(k + 1)／\(n) 站"
    }

    /// 「停留 90 分」；過夜「過夜」
    static func dwellText(_ s: WatchTripStop) -> String {
        s.isOvernight ? "過夜" : "停留 \(s.dwellMinutes) 分"
    }

    /// 手錶 App 的站名：手腕放下（或系統要遮）時過夜那一站寫「住宿」
    static func stopName(_ s: WatchTripStop, dimmed: Bool) -> String {
        (dimmed && s.isOvernight) ? overnightLock : s.name
    }

    /// 錶面上的站名（錶面＝鎖定畫面：過夜那一站一律「住宿」）
    static func faceName(_ s: WatchTripStop) -> String {
        s.isOvernight ? overnightLock : s.name
    }

    /// 「韓國三日遊・第 2 天」；一天的行程只寫名字
    static func header(_ day: WatchTripDay) -> String {
        day.dayCount > 1 ? day.title + "・第 \(day.dayIndex) 天" : day.title
    }

    // MARK: 今天是哪一份、現在在哪一站

    /// 現在要用的那一天：包裡今天、明天那一份裡包含 now 的；補上手錶上按過、iPhone 還沒寫回包裡的打卡。沒有回 nil
    static func currentDay(package: WatchPackage?, now: Date, pending: [WatchCheckInItem]) -> WatchTripDay? {
        guard let package else { return nil }
        let days: [WatchTripDay] = [package.tripToday, package.tripTomorrow].compactMap { $0 }
        guard let day = days.first(where: { $0.contains(now) }) else { return nil }
        return merged(day, pending: pending)
    }

    /// 包裡 day 的隔天那一份（「明天 09:30 景福宮」）；沒有 nil
    static func nextDay(package: WatchPackage?, after day: WatchTripDay) -> WatchTripDay? {
        guard let package else { return nil }
        let days: [WatchTripDay] = [package.tripToday, package.tripTomorrow].compactMap { $0 }
        return days.first { $0.dayStart >= day.dayEnd }
    }

    /// 手錶上按過、iPhone 還沒寫回包裡的打卡補上去：只補那一站還沒有的（iPhone 回「本來就打過」的不補，以 iPhone 為準）
    static func merged(_ day: WatchTripDay, pending: [WatchCheckInItem]) -> WatchTripDay {
        var out = day
        for i in out.stops.indices {
            let sid = out.stops[i].id
            for item in pending where item.checkIn.planId == day.planId && item.checkIn.stopId == sid {
                guard item.state != .already else { continue }
                if out.stops[i].arrivedAt == nil, let a = item.checkIn.arrival {
                    out.stops[i].arrivedAt = a
                }
                if out.stops[i].departedAt == nil, let d = item.checkIn.departure {
                    out.stops[i].departedAt = d
                }
            }
        }
        return out
    }

    /// 現在的焦點：到了還沒離開的那一站（同 TripPlan.currentStopId：第一個）；不然下一站
    /// （還沒到、還沒離開、預計離開還沒過的第一站）；都沒有＝nil
    static func focus(_ day: WatchTripDay, now: Date) -> (index: Int, isHere: Bool)? {
        if let i = day.stops.firstIndex(where: { $0.arrivedAt != nil && $0.departedAt == nil }) {
            return (index: i, isHere: true)
        }
        if let i = day.stops.firstIndex(where: { $0.arrivedAt == nil && $0.departedAt == nil && $0.departure > now }) {
            return (index: i, isHere: false)
        }
        return nil
    }

    /// index 之後第一個還沒到、還沒離開的站
    static func nextStop(_ day: WatchTripDay, after index: Int) -> WatchTripStop? {
        guard index + 1 < day.stops.count else { return nil }
        return day.stops[(index + 1)...].first { $0.arrivedAt == nil && $0.departedAt == nil }
    }

    /// ④ 那一頁要不要有、排第幾（WatchModel.tripKind）
    static func pageKind(package: WatchPackage?, now: Date) -> WatchTripPageKind? {
        guard let package else { return nil }
        let days: [WatchTripDay] = [package.tripToday, package.tripTomorrow].compactMap { $0 }
        if days.contains(where: { $0.contains(now) }) { return .during }
        guard let life = package.life else { return nil }
        switch life.tripPhase(at: now) {
        case .noTrip:
            return nil
        case .upcoming(_, daysUntil: let n):
            return n <= upcomingDays ? .upcoming : nil
        case .during:
            return .during
        }
    }

    /// 天氣資料出處頁的網址：包裡今天、明天那一份帶的（WatchTripDay.weatherSource）；都沒有用 sourceDefaultURL
    static func weatherSourceURL(package: WatchPackage?) -> String {
        if let s = package?.tripToday?.weatherSource, !s.isEmpty { return s }
        if let s = package?.tripTomorrow?.weatherSource, !s.isEmpty { return s }
        return sourceDefaultURL
    }

    /// 錶面「下一場」點進來的場次 id 是旅途中的哪一站（WatchModel.open）；不是回 nil
    static func tripStopId(timelineId: String, in package: WatchPackage?) -> UUID? {
        guard let package else { return nil }
        let days: [WatchTripDay] = [package.tripToday, package.tripTomorrow].compactMap { $0 }
        for day in days {
            if let s = day.stops.first(where: { $0.timelineStopId == timelineId }) { return s.id }
        }
        return nil
    }

    // MARK: ④ 那一頁

    static func page(package: WatchPackage?, now: Date, pending: [WatchCheckInItem], dimmed: Bool,
                     compact: Bool) -> WatchTripPage? {
        guard let package else { return nil }
        if let day = currentDay(package: package, now: now, pending: pending) {
            return dayPage(day, tomorrow: nextDay(package: package, after: day), now: now, dimmed: dimmed)
        }
        guard let life = package.life else { return nil }
        switch life.tripPhase(at: now) {
        case .noTrip:
            return nil
        case .upcoming(let trip, daysUntil: let n):
            guard n <= upcomingDays else { return nil }
            return upcomingPage(trip, days: n, compact: compact)
        case .during(let trip, day: let d):
            return stalePage(trip, day: d)
        }
    }

    static func dayPage(_ day: WatchTripDay, tomorrow: WatchTripDay?, now: Date, dimmed: Bool) -> WatchTripPage {
        let n = day.stops.count
        let head = header(day)
        guard let f = focus(day, now: now) else {
            return restPage(day, tomorrow: tomorrow, header: head, dimmed: dimmed)
        }
        let stop = day.stops[f.index]
        let pos = positionText(f.index, n)
        let weather = weatherParts(stop, day: day)
        if f.isHere {
            let arrived = time(stop.arrivedAt ?? stop.arrival) + " 到了"
            return WatchTripPage(mode: .here, header: head, line2: "現在・" + pos, line2IsAmber: false,
                                 big: stopName(stop, dimmed: dimmed), bigIsTime: false,
                                 line4: arrived, line4IsArrived: true,
                                 line5: hereNextLine(day, index: f.index, tomorrow: tomorrow, dimmed: dimmed),
                                 weatherText: weather.text, weatherSymbol: weather.symbol,
                                 showsSource: weather.text != nil,
                                 dots: dots(n), plane: plane(n, index: f.index, isHere: true), action: .depart,
                                 focusStopId: stop.id, planId: day.planId, focusArrivedAt: stop.arrivedAt)
        }
        return WatchTripPage(mode: .next, header: head, line2: nextLine2(stop, position: pos, now: now),
                             line2IsAmber: false,
                             big: time(stop.arrival), bigIsTime: true,
                             line4: stopName(stop, dimmed: dimmed), line4IsArrived: false, line5: nil,
                             weatherText: weather.text, weatherSymbol: weather.symbol,
                             showsSource: weather.text != nil,
                             dots: dots(n), plane: plane(n, index: f.index, isHere: false), action: .arrive,
                             focusStopId: stop.id, planId: day.planId)
    }

    /// 下一站那一行：90 分鐘內「下一站・25 分後・第 3／5 站」；預計時間已經過了（還沒按到了）「這一站・第 3／5 站」；
    /// 更遠「下一站・第 3／5 站」
    static func nextLine2(_ stop: WatchTripStop, position: String, now: Date) -> String {
        if let c = WidgetDateText.countdown(to: stop.arrival, from: now) {
            return "下一站・" + c + "・" + position
        }
        if stop.arrival <= now {
            return "這一站・" + position
        }
        return "下一站・" + position
    }

    /// 現在這一站下面那一行：「下一站 17:30 明洞」；今天最後一站接「明天 09:30 景福宮」；都沒有 nil
    static func hereNextLine(_ day: WatchTripDay, index: Int, tomorrow: WatchTripDay?, dimmed: Bool) -> String? {
        if let next = nextStop(day, after: index) {
            return "下一站 " + time(next.arrival) + " " + stopName(next, dimmed: dimmed)
        }
        if let first = tomorrow?.stops.first {
            return "明天 " + time(first.arrival) + " " + stopName(first, dimmed: dimmed)
        }
        return nil
    }

    /// 今天沒有焦點（都走完了、今天沒有站）：明天第一站；最後一天「旅程結束」
    static func restPage(_ day: WatchTripDay, tomorrow: WatchTripDay?, header head: String,
                         dimmed: Bool) -> WatchTripPage {
        let n = day.stops.count
        let first = tomorrow?.stops.first
        let base = n == 0 ? "今天沒有排站" : "今天的站都走完了"
        let line2 = first == nil ? base : base + "・明天第一站"
        var big = "—"
        var bigIsTime = false
        var line4: String? = nil
        if let t = first {
            big = time(t.arrival)
            bigIsTime = true
            line4 = stopName(t, dimmed: dimmed)
        } else if n > 0 && day.dayIndex >= day.dayCount {
            big = "旅程結束"
        }
        return WatchTripPage(mode: n == 0 ? .noStops : .dayDone, header: head, line2: line2, line2IsAmber: false,
                             big: big, bigIsTime: bigIsTime, line4: line4, line4IsArrived: false, line5: nil,
                             weatherText: nil, weatherSymbol: nil, showsSource: false,
                             dots: dots(n), plane: n == 0 ? nil : 1, action: nil,
                             focusStopId: nil, planId: day.planId)
    }

    /// 出發前 7 天到出發前一天：「韓國三日遊」／「11/6（五）08:40 出發」／大字「還有 7 天」／「行李 8／15」
    static func upcomingPage(_ trip: WidgetTrip, days n: Int, compact: Bool) -> WatchTripPage {
        let date = WatchText.billDate(trip.startDate, withWeekday: !compact)
        let packing: String? = trip.packingTotal > 0 ? "行李 \(trip.packingDone)／\(trip.packingTotal)" : nil
        // 「11/6（五）08:40 出發」：全形括號後面不空格；41mm 不寫星期「11/6 08:40 出發」
        let gap = compact ? " " : ""
        return WatchTripPage(mode: .upcoming, header: trip.title, line2: date + gap + time(trip.startDate) + " 出發",
                             line2IsAmber: false, big: "還有 \(n) 天", bigIsTime: false,
                             line4: packing, line4IsArrived: false, line5: nil,
                             weatherText: nil, weatherSymbol: nil, showsSource: false,
                             dots: [], plane: nil, action: nil, focusStopId: nil, planId: trip.id)
    }

    /// 旅途中、包裡沒有今天那一份：叫你打開 iPhone 一次
    static func stalePage(_ trip: WidgetTrip, day d: Int) -> WatchTripPage {
        let head = max(trip.dayCount, 1) > 1 ? trip.title + "・第 \(d) 天" : trip.title
        return WatchTripPage(mode: .stale, header: head, line2: staleText, line2IsAmber: true,
                             big: "—", bigIsTime: false, line4: nil, line4IsArrived: false, line5: nil,
                             weatherText: nil, weatherSymbol: nil, showsSource: false,
                             dots: [], plane: nil, action: nil, focusStopId: nil, planId: trip.id)
    }

    /// 天氣字：包裡有出處網址才給（WeatherKit 規定；judge §2.14）
    static func weatherParts(_ stop: WatchTripStop, day: WatchTripDay) -> (text: String?, symbol: String?) {
        guard let t = stop.weatherText, !t.isEmpty, day.weatherSource != nil else { return (text: nil, symbol: nil) }
        return (text: t, symbol: stop.weatherSymbol)
    }

    /// 進度條上每一站的位置：2 站以上平均排開 0…1；1 站在正中間
    static func dots(_ n: Int) -> [Double] {
        if n <= 0 { return [] }
        if n == 1 { return [0.5] }
        return (0..<n).map { Double($0) / Double(n - 1) }
    }

    /// 飛機在哪：下一站＝前一站跟它的中間（第一站＝最左邊）；現在這一站＝它的位置
    static func plane(_ n: Int, index k: Int, isHere: Bool) -> Double {
        if n <= 1 { return isHere ? 0.5 : 0 }
        let span = Double(n - 1)
        if isHere { return Double(k) / span }
        return max(0, (Double(k) - 0.5) / span)
    }

    // MARK: 這一站（第二層）

    static func stopDetail(package: WatchPackage?, stopId: UUID, now: Date, pending: [WatchCheckInItem],
                           dimmed: Bool) -> WatchTripStopDetail? {
        guard let package else { return nil }
        let days: [WatchTripDay] = [package.tripToday, package.tripTomorrow].compactMap { $0 }
        for raw in days {
            let day = merged(raw, pending: pending)
            guard let i = day.stops.firstIndex(where: { $0.id == stopId }) else { continue }
            return stopDetail(day.stops[i], index: i, day: day, dimmed: dimmed)
        }
        return nil
    }

    static func stopDetail(_ s: WatchTripStop, index: Int, day: WatchTripDay, dimmed: Bool) -> WatchTripStopDetail {
        let timeLine = positionText(index, day.stops.count) + "・" + time(s.arrival) + " 到"
        let dwellLine = s.isOvernight ? "過夜" : "預計停留 \(s.dwellMinutes) 分"
        var state: String? = nil
        if let a = s.arrivedAt, let d = s.departedAt {
            state = time(a) + " 到・" + time(d) + " 離開"
        } else if let a = s.arrivedAt {
            state = time(a) + " 到了"
        } else if let d = s.departedAt {
            state = time(d) + " 離開"
        }
        let trimmed = s.address.trimmingCharacters(in: .whitespacesAndNewlines)
        let hideAddress = trimmed.isEmpty || (dimmed && s.isOvernight)
        let weather = weatherParts(s, day: day)
        let tips: [String] = weather.text == nil ? [] : (s.weatherTips ?? [])
        return WatchTripStopDetail(title: stopName(s, dimmed: dimmed), timeLine: timeLine, dwellLine: dwellLine,
                                   stateLine: state, address: hideAddress ? nil : trimmed,
                                   latitude: s.latitude, longitude: s.longitude,
                                   phoneText: phoneText(s.phone), phoneDial: phoneDial(s.phone),
                                   weatherText: weather.text, weatherSymbol: weather.symbol, tips: tips,
                                   showsSource: weather.text != nil)
    }

    /// 顯示的電話（原樣、去頭尾空白）；沒有 nil
    static func phoneText(_ raw: String?) -> String? {
        let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// 撥號用：只留數字與「+」（國碼留著最保險，同 iPhone TripPhone.dialDigits）；沒有數字 nil
    static func phoneDial(_ raw: String?) -> String? {
        let kept = String((raw ?? "").filter { $0.isNumber || $0 == "+" })
        return kept.contains(where: { $0.isNumber }) ? kept : nil
    }

    // MARK: 錶面「下一場」（旅途中那一種；judge §3.1 表「旅途中（v6）」；不放天氣）

    /// 旅途中而且有現在這一站或下一站：
    ///   下一站「14:00 弘大」／「第 3／5 站・停留 90 分」／「25 分後・第 2 天」
    ///   現在這一站「弘大」／「14:12 到了・第 3／5 站」／「接著 17:30 明洞」
    /// 過夜那一站一律「住宿」。不是旅途中、今天的站都走完了回 nil（WatchText.nextUp 照一般的）
    static func faceNextUp(package: WatchPackage?, now: Date, pending: [WatchCheckInItem]) -> WatchNextUp? {
        guard let day = currentDay(package: package, now: now, pending: pending),
              let f = focus(day, now: now) else { return nil }
        let n = day.stops.count
        let stop = day.stops[f.index]
        let pos = positionText(f.index, n)
        if f.isHere {
            let arrived = stop.arrivedAt ?? stop.arrival
            let next = nextStop(day, after: f.index)
            let line3: String = next.map { "接著 " + time($0.arrival) + " " + faceName($0) } ?? "今天最後一站"
            return WatchNextUp(mark: .trip, line1: faceName(stop), line2: time(arrived) + " 到了・" + pos,
                               line3: line3, line3Icon: nil, time: time(stop.departure),
                               ring: span(from: arrived, to: stop.departure, now: now),
                               inline: faceName(stop) + "・" + time(arrived) + " 到了",
                               stopId: stop.timelineStopId, tripPlanId: day.planId)
        }
        var third: [String] = []
        if let c = WidgetDateText.countdown(to: stop.arrival, from: now) { third.append(c) }
        if day.dayCount > 1 { third.append("第 \(day.dayIndex) 天") }
        let line1 = time(stop.arrival) + " " + faceName(stop)
        return WatchNextUp(mark: .trip, line1: line1, line2: pos + "・" + dwellText(stop),
                           line3: third.joined(separator: "・"), line3Icon: nil, time: time(stop.arrival),
                           ring: lead(to: stop.arrival, now: now), inline: line1,
                           stopId: stop.timelineStopId, tripPlanId: day.planId)
    }

    /// 開始前 60 分鐘從 0 填到 1（同 WatchText.lead）
    static func lead(to start: Date, now: Date) -> Double {
        let lead = Double(WatchText.ringLeadMinutes * 60)
        let left = start.timeIntervalSince(now)
        if left >= lead { return 0 }
        if left <= 0 { return 1 }
        return 1 - left / lead
    }

    /// from 到 to 已經過了多少（0…1；同 WatchText.elapsed）
    static func span(from: Date, to: Date, now: Date) -> Double {
        let total = to.timeIntervalSince(from)
        guard total > 0 else { return 1 }
        return min(max(now.timeIntervalSince(from) / total, 0), 1)
    }

    // MARK: 換時區（judge §2.14、§5.6）

    /// 手錶現在的時區跟 iPhone 算包的時區差幾小時（比這一刻的時差，不比名字：台北、上海同一個時差不算換）：
    /// 第一頁最上面寫「換時區了：打開 iPhone 上的 LifeGood 一次，日期才會對」（琥珀）；一樣、或包裡沒寫回 nil
    static func timeZoneHint(package: WatchPackage?, now: Date, current: TimeZone = .autoupdatingCurrent) -> String? {
        guard let id = package?.timeZoneId, let tz = TimeZone(identifier: id) else { return nil }
        return tz.secondsFromGMT(for: now) == current.secondsFromGMT(for: now) ? nil : timeZoneHintText
    }

    // MARK: 打卡下面那一行

    static func checkInLine(_ s: WatchCheckInStatus, isDeparture: Bool) -> String {
        switch s {
        case .waiting:
            return "正在送到 iPhone…"
        case .offline:
            return "還沒送到 iPhone，先存在手錶上"
        case .delivered:
            return "已送到 iPhone"
        case .queued:
            return "已收到，打開 iPhone 上的 LifeGood 後寫進行程"
        case .done:
            return "已寫進 iPhone 的行程"
        case .already(let at):
            return "已經在 " + time(at) + (isDeparture ? " 打過離開" : " 打過卡")
        case .gone:
            return "這一站在 iPhone 上改過了"
        }
    }

    /// App 重開過、手上只有檔裡的狀態時推回去
    static func checkInStatus(of item: WatchCheckInItem) -> WatchCheckInStatus {
        switch item.state {
        case .holding, .sent: return .offline
        case .delivered: return .delivered
        case .queued: return .queued
        case .done: return .done
        case .already: return .already(item.phoneTime ?? item.checkIn.createdAt)
        }
    }

    // MARK: 記一筆（旅途中；judge §2.14「旅途中記一筆自動變外幣」）

    /// 旅途中（包裡有今天的站）才有；外幣、預設記到哪、可以選的站、這趟常用分類與最近金額
    static func recordContext(package: WatchPackage?, now: Date, pending: [WatchCheckInItem],
                              dimmed: Bool) -> WatchTripRecordContext? {
        guard let day = currentDay(package: package, now: now, pending: pending) else { return nil }
        let whole = WatchTripRecordTarget(planId: day.planId, stopId: nil, stopName: nil)
        var choices: [WatchTripRecordChoice] = []
        for (i, s) in day.stops.enumerated() {
            let name = stopName(s, dimmed: dimmed)
            let target = WatchTripRecordTarget(planId: day.planId, stopId: s.id, stopName: name)
            choices.append(WatchTripRecordChoice(id: s.id.uuidString, target: target, title: name,
                                                 detail: time(s.arrival) + "・第 \(i + 1) 站"))
        }
        choices.append(WatchTripRecordChoice(id: "whole", target: whole, title: wholeTripTitle, detail: day.title))
        var target = whole
        if let i = defaultStopIndex(day, now: now) {
            let s = day.stops[i]
            target = WatchTripRecordTarget(planId: day.planId, stopId: s.id, stopName: stopName(s, dimmed: dimmed))
        }
        var recent: [Int] = []
        if day.currency != nil {
            for v in day.recentAmounts ?? [] {
                guard v.isFinite, v >= 1, v <= Double(maxForeignAmount) else { continue }
                let n = Int(v.rounded())
                if !recent.contains(n) { recent.append(n) }
            }
        }
        return WatchTripRecordContext(planId: day.planId, currency: day.currency,
                                      missingCurrencyLabel: day.missingCurrencyLabel, defaultTarget: target,
                                      choices: choices, topCategoryKeys: day.topCategoryKeys ?? [],
                                      recentAmounts: recent)
    }

    /// 預設記到哪一站：到了還沒離開的那一站；不然時間最近的那一站（現在在它的抵達～離開之間＝0；同樣近取前面的）；沒有站 nil
    static func defaultStopIndex(_ day: WatchTripDay, now: Date) -> Int? {
        if let f = focus(day, now: now), f.isHere { return f.index }
        var best: Int? = nil
        var bestGap = Double.greatestFiniteMagnitude
        for (i, s) in day.stops.enumerated() {
            let gap: Double
            if now < s.arrival {
                gap = s.arrival.timeIntervalSince(now)
            } else if now > s.departure {
                gap = now.timeIntervalSince(s.departure)
            } else {
                gap = 0
            }
            if gap < bestGap {
                bestGap = gap
                best = i
            }
        }
        return best
    }

    /// 「記到 弘大」「記到 整趟」
    static func targetLine(_ t: WatchTripRecordTarget) -> String {
        "記到 " + (t.stopName ?? wholeTripTitle)
    }

    /// 錶冠一格多少（夾在 1…100,000）
    static func crownStep(_ c: WatchCurrency) -> Int {
        guard c.crownStep.isFinite, c.crownStep >= 1 else { return 1 }
        return Int(min(c.crownStep, 100_000).rounded())
    }

    /// 錶冠有幾格（0 起；最多 1,000 格，而且最後一格不超過 999,999）
    static func foreignStepCount(_ c: WatchCurrency) -> Int {
        min(maxForeignSteps, maxForeignAmount / crownStep(c) + 1)
    }

    /// 錶冠第 i 格的原幣金額（超出範圍夾回來）
    static func foreignStepAmount(at index: Int, _ c: WatchCurrency) -> Int {
        let i = min(max(index, 0), foreignStepCount(c) - 1)
        return i * crownStep(c)
    }

    /// 這個金額在第幾格（「≤ 它」的最後一格）
    static func foreignStepIndex(for amount: Int, _ c: WatchCurrency) -> Int {
        min(max(amount / crownStep(c), 0), foreignStepCount(c) - 1)
    }

    /// 「₩18,000」；沒有符號「韓元 18,000」
    static func foreignText(_ n: Int, _ c: WatchCurrency) -> String {
        c.symbol.isEmpty ? c.label + " " + grouped(n) : c.symbol + grouped(n)
    }

    /// 遮住：「₩ ••••」「韓元 ••••」
    static func foreignMask(_ c: WatchCurrency) -> String {
        (c.symbol.isEmpty ? c.label : c.symbol) + " ••••"
    }

    /// 換成台幣（四捨五入到元；> 0 的金額至少 1 元；上限 9,999,999）。入帳就用這個數（iPhone 不重算）
    static func twdAmount(_ n: Int, _ c: WatchCurrency) -> Int {
        guard n > 0, c.rateToTWD.isFinite, c.rateToTWD > 0 else { return 0 }
        let v = (Double(n) * c.rateToTWD).rounded()
        if v < 1 { return 1 }
        if v > Double(maxTWD) { return maxTWD }
        return Int(v)
    }

    /// 「≈ NT$412（0.0229）」
    static func approxLine(_ n: Int, _ c: WatchCurrency) -> String {
        "≈ NT$" + grouped(twdAmount(n, c)) + "（" + rateText(c.rateToTWD) + "）"
    }

    /// 匯率的字：1 以上兩位小數、1 以下四位，去掉尾巴的 0（「32.5」「0.0229」）
    static func rateText(_ r: Double) -> String {
        guard r.isFinite, r > 0 else { return "—" }
        let raw = String(format: r >= 1 ? "%.2f" : "%.4f", r)
        var chars = Array(raw)
        while chars.count > 1 && chars.last == "0" {
            chars.removeLast()
        }
        if chars.last == "." {
            chars.removeLast()
        }
        return String(chars)
    }

    /// 記帳台最下面那一行（沒有匯率時）：「要記韓元：到 iPhone 設定加「韓元」匯率」
    static func missingRateHint(_ label: String) -> String {
        "要記" + label + "：到 iPhone 設定加「" + label + "」匯率"
    }
}
