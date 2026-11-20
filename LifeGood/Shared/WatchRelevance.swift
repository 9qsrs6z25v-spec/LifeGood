import Foundation

// MARK: - 智慧型堆疊卡、「什麼時候該浮上來」（手錶 v7b，v25.584；watch/judge.md §3.2、§2.16、§2.17、§6.1、§13；
//         watch/build/v7b/brief.md §1、§2）
//
// 這個檔屬於三個 target：iPhone App（WatchPackageBuilder 組卡、WatchExtrasWriter 算平常跑步的時段）、
// 手錶 App（WatchSync 收到新包時問系統重新排）、手錶小格（五種堆疊卡、「下一場」「已花」「這週跑步」的 relevance()）。
// **只准 Foundation** 與 WatchPackage.swift／WidgetSnapshot.swift／DayTimelineAttributes.swift／WidgetLink.swift 的純資料型別；
// 手錶才有的型別（WatchSport、WatchRunLogEntry、WatchCheckInLog、WatchText…）一律由手錶小格算好傳進來。
// 規則跟 scratchpad/watch/build/v7b/sim_v7b.py 的同名函式一模一樣（改了兩邊一起改、重跑 sim）。
//
// 卡的字（iPhone 組；錶面、堆疊＝鎖定畫面，judge §6.1）：
//   • 早安（06:30 到今天第一件開始，最晚 09:00）：「今天 4 件・09:30 起」／「家人生日」／「卡費 10/27・5 天後」
//     （堆疊卡 194 點寬，卡費那一行不寫星期，樣稿②-5）
//   • 快開會了（每一場開始前 20 分鐘到開始後 10 分鐘；旅遊景點不算，旅途下一站那一張管）：
//     「09:30 部門會議」／「12F 大會議室・30 分鐘」／「之後還有 3 件」。**不寫部屬名字**（lockedSurfaceTitle）；
//     手腕放下第一行換「09:30 會議」（lockTitle：會議名抬手才寫，§13-7、主控補充）
//   • 卡費快到了（自己繳的卡費截止前 3 天起，每天 09:00–21:00；同一天截止的只算一張）：
//     「卡費 10/27（二）截止」／「3 天後・要自己繳」／「繳完到 iPhone 財富頁按已繳」——**沒有卡名、金額、末四碼**
//   • 旅途下一站（每一站前 30 分鐘到預定抵達；已經到了的不浮）：「下一站 14:00 弘大」／「第 3／5 站・停留 90 分」／
//     「第 2 天／共 3 天」。過夜那一站「住宿」；**不放天氣**（放不下「 Weather」出處）；手腕放下第一行「下一站 14:00」
//   • 平常跑步的時間（手錶自己組字，公里跟 ③ 同一套）：「平常晨跑的時間」／「這週 9.4／20 公里」／「還差 10.6・剩 4 天」；
//     週日只在離目標 3 公里以內才浮；那個時段（前 60 分鐘起）今天已經跑過就不浮
// 會跑的倒數（「5 分後」「25 分後」）不寫：堆疊卡沒有時間軸、系統拿一次字就畫，倒數會停在拿字那一刻（brief §1-3）。
//
// 你自己加的「下一場」「已花」「這週跑步」（watchOS 11 起，TimelineProvider 的 relevance()；judge §3.2）：
//   每場開始前 60 分鐘到結束／平日 11:30–13:30、17:30–19:30／平常跑步的時段（同那張卡）。
// iPhone「智慧型堆疊卡」總開關關掉（包裡 relevanceCards＝nil）：五種卡都不浮、這三種也不自己往上排。

/// [v7b] 堆疊卡的五種（iPhone 設定頁各自一個開關；手錶小格各自一個 RelevanceConfiguration）
enum WatchRelevanceKind: String, CaseIterable, Identifiable {
    case morning
    case meeting
    case cardBill
    case usualRun
    case tripStop

    var id: String { rawValue }

    /// iPhone 設定頁、手錶小格的名字
    var title: String {
        switch self {
        case .morning:  return "早安"
        case .meeting:  return "快開會了"
        case .cardBill: return "卡費快到了"
        case .usualRun: return "平常跑步的時間"
        case .tripStop: return "旅途下一站"
        }
    }

    /// iPhone 設定頁那一列的小字（什麼時候浮上來、寫什麼不寫什麼）
    var whenText: String {
        switch self {
        case .morning:  return "06:30 到今天第一件開始（最晚 09:00）：今天幾件、家人生日、卡費"
        case .meeting:  return "每一場開始前 20 分鐘到開始後 10 分鐘；不寫部屬名字"
        case .cardBill: return "自己繳的卡費截止前 3 天起，每天 09:00–21:00；只寫「卡費」和日期"
        case .usualRun: return "近 4 週同一個時段跑過 3 次以上；週日只在離目標 3 公里以內"
        case .tripStop: return "旅途中每一站前 30 分鐘到抵達；不放天氣"
        }
    }

    /// 手錶小格的 kind
    var widgetKind: String {
        switch self {
        case .morning:  return WatchWidgetKind.cardMorning
        case .meeting:  return WatchWidgetKind.cardMeeting
        case .cardBill: return WatchWidgetKind.cardBill
        case .usualRun: return WatchWidgetKind.cardRun
        case .tripStop: return WatchWidgetKind.cardTrip
        }
    }

    /// iPhone App Group UserDefaults 的開關（沒設定過＝開；WatchPhoneSettings.stackKinds、WatchSettingsSection 同一組鍵）
    var settingsKey: String { "watch_stack_" + rawValue }

    /// 要你做事的（會議、卡費、旅途下一站）請系統排前面一點；早安、平常跑步只是資訊
    var isScheduled: Bool {
        switch self {
        case .meeting, .cardBill, .tripStop: return true
        case .morning, .usualRun:            return false
        }
    }

    /// 找不到那一張卡、預覽時畫的圖示
    var icon: String {
        switch self {
        case .morning:  return WatchRelevancePlan.sunIcon
        case .meeting:  return "calendar"
        case .cardBill: return WatchRelevancePlan.cardIcon
        case .usualRun: return "figure.run"
        case .tripStop: return WatchRelevancePlan.tripIcon
        }
    }
}

/// [v7b] 一段「這時候該浮上來」（end 一定比 start 晚）
struct WatchRelevanceWindow: Equatable {
    var start: Date
    var end: Date
}

/// [v7b] 「平常跑步的時間」卡要的數字。手錶小格用 WatchRunText.home 算好（③ 跑步同一套：iPhone 的這週＋手錶自己記的），
/// 運動的圖示與色也由手錶傳進來（這個檔不碰 WatchSport）
struct WatchRunNumbers: Equatable {
    /// 主角運動的 SF Symbol、色
    var icon: String
    var tint: UInt32
    /// 這週公里、目標（沒設 nil）、次數、連續週數、這週還剩幾天（含今天）
    var km: Double
    var goalKm: Double?
    var runs: Int
    var streakWeeks: Int
    var daysLeft: Int
}

enum WatchRelevancePlan {

    // MARK: 時間（一天裡的分鐘；judge §3.2 表）

    /// 早安：06:30 起，到今天第一件開始（最晚 09:00）
    static let morningFromMinute = 6 * 60 + 30
    static let morningLatestMinute = 9 * 60
    /// 快開會了：開始前 20 分鐘到開始後 10 分鐘
    static let meetingLeadMinutes = 20
    static let meetingTailMinutes = 10
    /// 卡費快到了：截止前 3 天起，每天 09:00–21:00
    static let billDaysBefore = 3
    static let billFromMinute = 9 * 60
    static let billToMinute = 21 * 60
    /// 旅途下一站：預定抵達前 30 分鐘到預定抵達
    static let tripLeadMinutes = 30
    /// 「下一場」：開始前 60 分鐘到結束
    static let nextUpLeadMinutes = 60
    /// 「已花」：平日（一～五）吃飯結帳前
    static let spentSlots: [(from: Int, to: Int)] = [(11 * 60 + 30, 13 * 60 + 30), (17 * 60 + 30, 19 * 60 + 30)]
    /// 「已花」、平常跑步往後排幾天（含今天）
    static let daysAhead = 7
    /// 早安卡的卡費、出發倒數看幾天內
    static let soonDays = 7
    /// 平常跑步的時段：看近 28 天、60 分鐘內 3 趟以上、前後各多 15 分鐘、最多 2 段
    static let runLookbackDays = 28
    static let runSlotMinCount = 3
    static let runClusterMinutes = 60
    static let runSlotPadMinutes = 15
    static let maxRunSlots = 2
    /// 週日只在離目標這麼多公里以內才浮
    static let runSundayGapKm = 3.0
    /// 那個時段開始前 60 分鐘起今天已經跑過（主角運動）：今天那一段不浮
    static let runAlreadyRanLeadMinutes = 60
    /// 一種卡一次最多請系統排幾段（照開始時間，越近越前面：Apple「照優先序排，系統可能只用前面幾個」）
    static let maxPerKind = 10

    // MARK: 字、圖示、色

    static let morningEmpty = "今天沒排行程"
    static let lastOne = "今天最後一件"
    static let billPay = "・要自己繳"
    static let billHowTo = "繳完到 iPhone 財富頁按已繳"
    static let overnightName = "住宿"
    static let missingLine = "打開 iPhone 上的 LifeGood 一次"
    /// 星期的一個字（同 WatchText.weekdayChars）
    static let weekdayChars = ["日", "一", "二", "三", "四", "五", "六"]

    static let sunIcon = "sun.horizon.fill"
    static let cardIcon = "creditcard.fill"
    static let familyIcon = "house.fill"
    static let tripIcon = "airplane"
    /// 色碼（同 WatchPalette：琥珀、倒數藍、旅遊紫、行程四色）；生日蛋糕粉
    static let amber: UInt32 = 0xFFC14D
    static let cakePink: UInt32 = 0xFF8FB1
    static let tripTint: UInt32 = 0xBF5AF2
    /// WatchCardLine.tone
    static let toneAmber = "amber"
    static let toneBlue = "blue"
    static let toneDim = "dim"

    /// 卡的 id：「meeting@<場次 id>」（手錶小格拿它找回這一張；旅途下一站「tripStop@<站的 UUID>」）
    static func cardId(_ kind: WatchRelevanceKind, _ ref: String) -> String {
        kind.rawValue + "@" + ref
    }

    // MARK: - iPhone：組卡（WatchPackageBuilder；吃的是**已經消毒過的這一包**）

    /// 照設定挑的那幾種卡（kinds）。package 是 WatchPackageBuilder 剛組好、消毒過的那一包：
    /// life（部屬名字照設定清掉、財富只剩類別字）、bills（卡費沒有金額、卡名）、tripToday／tripTomorrow。
    /// 不看「現在幾點」：過了的卡手錶自己不浮，包的內容只跟資料一起變（內容沒變不送，judge §5.8）
    static func cards(package: WatchPackage, kinds: Set<WatchRelevanceKind>) -> [WatchRelevanceCard] {
        var out: [WatchRelevanceCard] = []
        let bills = package.bills ?? []
        if let life = package.life {
            for day in life.days {
                if kinds.contains(.morning), let c = morningCard(day: day, life: life, bills: bills) {
                    out.append(c)
                }
                if kinds.contains(.meeting) {
                    for s in day.stops where s.stop.kind != .trip {
                        out.append(meetingCard(s, in: day))
                    }
                }
            }
        }
        if kinds.contains(.cardBill) {
            out.append(contentsOf: billCards(bills))
        }
        if kinds.contains(.tripStop) {
            let tripDays: [WatchTripDay] = [package.tripToday, package.tripTomorrow].compactMap { $0 }
            for day in tripDays {
                out.append(contentsOf: tripCards(day))
            }
        }
        return sorted(out)
    }

    /// 開始時間早的先（同一刻 id 小的先）；同一個 id 只留第一張
    static func sorted(_ list: [WatchRelevanceCard]) -> [WatchRelevanceCard] {
        let ordered = list.sorted { a, b in
            if a.start != b.start { return a.start < b.start }
            return a.id < b.id
        }
        var taken = Set<String>()
        var out: [WatchRelevanceCard] = []
        for c in ordered where !taken.contains(c.id) {
            taken.insert(c.id)
            out.append(c)
        }
        return out
    }

    /// 早安（那一天 06:30 到第一件開始，最晚 09:00；第一件 06:30 以前就開始的那天不浮）。
    /// 第一行「今天 4 件・09:30 起」（沒排「今天沒排行程」）；第二、三行依序挑兩樣：
    /// 家人生日、紀念日（lockTitle：「家人生日」，不寫是誰）→ 自己繳的卡費 7 天內（「卡費 10/27・5 天後」，不寫星期）→
    /// 家庭待辦今天到期（件數）→ 7 天內出發的旅行（手腕放下「旅行・還有 5 天」）。行程、這幾樣都沒有就不浮
    static func morningCard(day: WidgetLifeDay, life: WatchLife, bills: [WatchBill]) -> WatchRelevanceCard? {
        let from = day.dayStart.addingTimeInterval(Double(morningFromMinute) * 60)
        var to = day.dayStart.addingTimeInterval(Double(morningLatestMinute) * 60)
        if let first = day.stops.first, first.stop.start < to {
            to = first.stop.start
        }
        guard to > from else { return nil }
        var shown: [WatchCardLine] = []
        var hidden: [WatchCardLine] = []
        // 家人生日、紀念日
        for item in day.allDay where item.kind == .birthday || item.kind == .anniversary {
            let line = WatchCardLine(icon: item.icon, tint: cakePink, text: item.lockTitle)
            shown.append(line)
            hidden.append(line)
        }
        // 自己繳的卡費 7 天內（最近一筆）
        if let due = nearestCardDue(bills, from: day.dayStart) {
            let n = WidgetDateText.daysFrom(day.dayStart, to: due)
            let text = n <= 0 ? "卡費今天截止" : "卡費 " + monthDay(due, withWeekday: false) + "・" + dueText(n)
            let line = WatchCardLine(icon: cardIcon, tint: amber, text: text, tone: n <= 0 ? toneAmber : nil)
            shown.append(line)
            hidden.append(line)
        }
        // 家庭待辦今天到期（只有件數）
        let family = life.familyDueCount(day.dayKey)
        if family > 0 {
            let line = WatchCardLine(icon: familyIcon, text: "家庭待辦 今天到期 \(family)")
            shown.append(line)
            hidden.append(line)
        }
        // 7 天內出發的旅行
        if let trip = (life.trips ?? []).first(where: { (1...soonDays).contains(WidgetDateText.daysFrom(day.dayStart, to: $0.firstDay)) }) {
            let n = WidgetDateText.daysFrom(day.dayStart, to: trip.firstDay)
            shown.append(WatchCardLine(icon: tripIcon, tint: tripTint, text: trip.title + "・還有 \(n) 天"))
            hidden.append(WatchCardLine(icon: tripIcon, tint: tripTint, text: "旅行・還有 \(n) 天"))
        }
        guard !day.stops.isEmpty || !shown.isEmpty else { return nil }
        let head: String
        if let first = day.stops.first {
            head = "今天 \(day.stops.count) 件・" + DayTimelineFormat.time(first.stop.start) + " 起"
        } else {
            head = morningEmpty
        }
        let headLine = WatchCardLine(icon: sunIcon, tint: amber, text: head)
        let lines = [headLine] + Array(shown.prefix(2))
        let privateLines = [headLine] + Array(hidden.prefix(2))
        return WatchRelevanceCard(id: cardId(.morning, day.dayKey), kind: WatchRelevanceKind.morning.rawValue,
                                  start: from, end: to, lines: lines,
                                  privateLines: privateLines == lines ? nil : privateLines,
                                  link: WidgetLink.today(nil).absoluteString)
    }

    /// 自己繳的卡費（needsAction）裡，那一天起 0～7 天內截止、最近的那一個截止日；沒有 nil
    static func nearestCardDue(_ bills: [WatchBill], from day: Date) -> Date? {
        var best: Date? = nil
        for b in bills where b.bill.kind == .cardBill && b.needsAction {
            let n = WidgetDateText.daysFrom(day, to: b.bill.dueDate)
            guard n >= 0 && n <= soonDays else { continue }
            if let cur = best, cur <= b.bill.dueDate { continue }
            best = b.bill.dueDate
        }
        return best
    }

    /// 快開會了（開始前 20 分鐘到開始後 10 分鐘）。第一行用 lockedSurfaceTitle（會議主題，**不是部屬名字**）；
    /// 手腕放下第一行換 lockTitle（「部屬會議」「會議」「系統行事曆」）。第二行同錶面（WatchText.faceDetail）
    static func meetingCard(_ s: WidgetStop, in day: WidgetLifeDay) -> WatchRelevanceCard {
        let from = s.stop.start.addingTimeInterval(-Double(meetingLeadMinutes) * 60)
        let to = s.stop.start.addingTimeInterval(Double(meetingTailMinutes) * 60)
        let time = DayTimelineFormat.time(s.stop.start)
        let mark = markSymbol(s.stop.kind)
        let tint = kindTint(s.stop.kind)
        let head = WatchCardLine(icon: mark, tint: tint, text: time + " " + s.lockedSurfaceTitle)
        let privateHead = WatchCardLine(icon: mark, tint: tint, text: time + " " + s.lockTitle)
        let detail = WatchCardLine(text: stopDetail(s))
        let after = day.stops.filter { $0.stop.start > s.stop.start }.count
        let tail = WatchCardLine(text: after > 0 ? "之後還有 \(after) 件" : lastOne, tone: toneBlue)
        return WatchRelevanceCard(id: cardId(.meeting, s.stop.id), kind: WatchRelevanceKind.meeting.rawValue,
                                  start: from, end: to, lines: [head, detail, tail],
                                  privateLines: [privateHead, detail, tail],
                                  link: WidgetLink.today(s.stop).absoluteString)
    }

    /// 卡費快到了：自己繳的卡費（同一天截止的算一張），截止前 3、2、1 天與當天各一段 09:00–21:00。
    /// 只寫「卡費」與日期——**bills 裡本來就沒有卡名、金額**（WatchPackageBuilder 消毒過），這裡也只讀 kind、needsAction、dueDate
    static func billCards(_ bills: [WatchBill]) -> [WatchRelevanceCard] {
        let cal = Calendar.current
        var dues: [Date] = []
        for b in bills where b.bill.kind == .cardBill && b.needsAction {
            let d = cal.startOfDay(for: b.bill.dueDate)
            if !dues.contains(d) {
                dues.append(d)
            }
        }
        var out: [WatchRelevanceCard] = []
        for due in dues.sorted() {
            for n in stride(from: billDaysBefore, through: 0, by: -1) {
                guard let day = cal.date(byAdding: .day, value: -n, to: due) else { continue }
                let from = day.addingTimeInterval(Double(billFromMinute) * 60)
                let to = day.addingTimeInterval(Double(billToMinute) * 60)
                let lines = [
                    WatchCardLine(icon: cardIcon, tint: amber, text: "卡費 " + monthDay(due, withWeekday: true) + "截止"),
                    WatchCardLine(lead: dueText(n), text: billPay, tone: toneAmber),
                    WatchCardLine(text: billHowTo, tone: toneDim)
                ]
                let ref = WidgetDateText.dayKey(due) + "@" + String(n)
                out.append(WatchRelevanceCard(id: cardId(.cardBill, ref), kind: WatchRelevanceKind.cardBill.rawValue,
                                              start: from, end: to, lines: lines, privateLines: nil,
                                              link: WidgetLink.expenseOverview.absoluteString))
            }
        }
        return out
    }

    /// 旅途下一站：還沒到的每一站，預定抵達前 30 分鐘到預定抵達。過夜那一站「住宿」；不放天氣、地址、電話；
    /// 手腕放下第一行只寫時間（站名抬手才寫）
    static func tripCards(_ day: WatchTripDay) -> [WatchRelevanceCard] {
        var out: [WatchRelevanceCard] = []
        let count = day.stops.count
        for (i, st) in day.stops.enumerated() where st.arrivedAt == nil {
            let from = st.arrival.addingTimeInterval(-Double(tripLeadMinutes) * 60)
            let to = st.arrival
            guard to > from else { continue }
            let time = DayTimelineFormat.time(st.arrival)
            let name = st.isOvernight ? overnightName : st.name
            let head = WatchCardLine(icon: tripIcon, tint: tripTint, text: "下一站 " + time + " " + name)
            let privateHead = WatchCardLine(icon: tripIcon, tint: tripTint, text: "下一站 " + time)
            var second = "第 \(i + 1)／\(count) 站"
            if !st.isOvernight && st.dwellMinutes > 0 {
                second += "・停留 \(st.dwellMinutes) 分"
            }
            let detail = WatchCardLine(text: second)
            let tail = WatchCardLine(text: "第 \(day.dayIndex) 天／共 \(day.dayCount) 天", tone: toneBlue)
            let link = WidgetLink.url(for: .today(stopId: st.timelineStopId)).absoluteString
            out.append(WatchRelevanceCard(id: cardId(.tripStop, st.id.uuidString), kind: WatchRelevanceKind.tripStop.rawValue,
                                          start: from, end: to, lines: [head, detail, tail],
                                          privateLines: [privateHead, detail, tail], link: link))
        }
        return out
    }

    // MARK: - iPhone：平常跑步的時段（WatchExtrasWriter.fillRun）

    /// 近 28 天主角運動每一趟的開始時間 → 平常跑步的時段（最多 2 段，早的先）。
    /// 一天裡的分鐘數排好，找 60 分鐘內擠最多趟的那一段（一樣多取早的）；3 趟以上就是一個時段：
    /// 最早那一趟前 15 分鐘到最晚那一趟後 15 分鐘（06:00、06:15、06:05 → 05:45–06:30）；拿掉那幾趟再找下一段。
    /// label：時段名（傳那一段的中位數分鐘進去；iPhone 用 WorkoutFacts.timeOfDayName）
    static func runSlots(starts: [Date], now: Date, label: (Int) -> String) -> [WatchRunSlot] {
        let cal = Calendar.current
        let from = now.addingTimeInterval(-Double(runLookbackDays) * 86_400)
        var minutes: [Int] = starts.filter { $0 >= from && $0 <= now }.map { d in
            let c = cal.dateComponents([.hour, .minute], from: d)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        minutes.sort()
        var out: [WatchRunSlot] = []
        while out.count < maxRunSlots && minutes.count >= runSlotMinCount {
            var bestStart = 0
            var bestCount = 0
            for i in 0..<minutes.count {
                var j = i
                while j < minutes.count && minutes[j] - minutes[i] <= runClusterMinutes {
                    j += 1
                }
                if j - i > bestCount {
                    bestCount = j - i
                    bestStart = i
                }
            }
            guard bestCount >= runSlotMinCount else { break }
            let cluster = Array(minutes[bestStart..<(bestStart + bestCount)])
            let lo = max(0, cluster[0] - runSlotPadMinutes)
            let hi = min(24 * 60, cluster[cluster.count - 1] + runSlotPadMinutes)
            out.append(WatchRunSlot(startMinute: lo, endMinute: hi, label: label(cluster[cluster.count / 2])))
            minutes.removeSubrange(bestStart..<(bestStart + bestCount))
        }
        return out.sorted { $0.startMinute < $1.startMinute }
    }

    // MARK: - 手錶小格：現在該請系統浮上來的卡

    /// 這一種卡現在該請系統排的那幾張（結束了的不算；旅途下一站按過〔到了〕的不算；最多 maxPerKind 張，近的先）。
    /// forLookup＝true：手錶小格拿 id 找回那一張（不管時間、週日、今天跑過、到了沒），一張都不漏
    static func liveCards(kind: WatchRelevanceKind, package: WatchPackage?, run: WatchRunNumbers?, runStarts: [Date],
                          arrivedStopIds: Set<UUID>, now: Date, forLookup: Bool) -> [WatchRelevanceCard] {
        guard let pack = package?.relevanceCards else { return [] }
        var list: [WatchRelevanceCard]
        if kind == .usualRun {
            list = usualRunCards(slots: pack.runSlots, numbers: run, runStarts: runStarts, now: now, forLookup: forLookup)
        } else {
            list = pack.cards.filter { $0.kind == kind.rawValue }
        }
        if forLookup {
            return list
        }
        list = list.filter { $0.end > now && $0.end > $0.start }
        if kind == .tripStop && !arrivedStopIds.isEmpty {
            let gone = Set(arrivedStopIds.map { cardId(.tripStop, $0.uuidString) })
            list = list.filter { !gone.contains($0.id) }
        }
        return Array(sorted(list).prefix(maxPerKind))
    }

    /// 手錶小格拿 id 找回那一張（找不到 nil：包換了、那一場被刪了）
    static func card(kind: WatchRelevanceKind, id: String, package: WatchPackage?, run: WatchRunNumbers?,
                     now: Date) -> WatchRelevanceCard? {
        let list = liveCards(kind: kind, package: package, run: run, runStarts: [], arrivedStopIds: [],
                             now: now, forLookup: true)
        return list.first { $0.id == id }
    }

    /// 找不到那一張、預覽、佔位：名字＋「打開 iPhone 上的 LifeGood 一次」（沒有任何你的資料）
    static func fallbackCard(_ kind: WatchRelevanceKind) -> WatchRelevanceCard {
        let lines = [WatchCardLine(icon: kind.icon, text: kind.title),
                     WatchCardLine(text: missingLine, tone: toneDim)]
        return WatchRelevanceCard(id: cardId(kind, "fallback"), kind: kind.rawValue,
                                  start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 60),
                                  lines: lines, privateLines: nil, link: WidgetLink.today(nil).absoluteString)
    }

    /// 畫哪一份：手腕放下、沒解鎖（hidesNames）換 privateLines（沒有就照 lines）
    static func shownLines(_ card: WatchRelevanceCard, hidesNames: Bool) -> [WatchCardLine] {
        if hidesNames, let p = card.privateLines {
            return p
        }
        return card.lines
    }

    // MARK: 平常跑步的時間（手錶組字）

    /// 今天起 7 天，每一天每一個時段一張（forLookup＝false 時：結束了、週日離目標還遠、今天那個時段已經跑過的不算）
    static func usualRunCards(slots: [WatchRunSlot], numbers: WatchRunNumbers?, runStarts: [Date], now: Date,
                              forLookup: Bool) -> [WatchRelevanceCard] {
        guard let n = numbers else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var out: [WatchRelevanceCard] = []
        for offset in 0..<daysAhead {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            for slot in slots {
                let from = day.addingTimeInterval(Double(slot.startMinute) * 60)
                let to = day.addingTimeInterval(Double(slot.endMinute) * 60)
                guard to > from else { continue }
                if !forLookup {
                    if to <= now { continue }
                    if cal.component(.weekday, from: day) == 1 && !sundayWorth(n) { continue }
                    if ranAlready(runStarts, day: day, slotStart: from) { continue }
                }
                out.append(usualRunCard(slot: slot, day: day, start: from, end: to, numbers: n))
            }
        }
        return out
    }

    /// 週日：有目標、還沒達標、差 3 公里以內
    static func sundayWorth(_ n: WatchRunNumbers) -> Bool {
        guard let goal = n.goalKm, goal > 0 else { return false }
        let gap = goal - max(0, n.km)
        return gap > 0 && gap <= runSundayGapKm
    }

    /// 那一天、那個時段開始前 60 分鐘起，已經有一趟主角運動
    static func ranAlready(_ starts: [Date], day: Date, slotStart: Date) -> Bool {
        let cal = Calendar.current
        let from = slotStart.addingTimeInterval(-Double(runAlreadyRanLeadMinutes) * 60)
        return starts.contains { cal.isDate($0, inSameDayAs: day) && $0 >= from }
    }

    /// 「平常晨跑的時間」／「這週 9.4／20 公里」／「還差 10.6・剩 4 天」（達標「這週達標了・連續 6 週」；
    /// 沒設目標「這週 9.4 公里」／「2 次・剩 4 天」）。只有數字，手腕放下照樣顯示
    static func usualRunCard(slot: WatchRunSlot, day: Date, start: Date, end: Date,
                             numbers n: WatchRunNumbers) -> WatchRelevanceCard {
        let head = WatchCardLine(icon: n.icon, tint: n.tint, text: "平常" + slot.label + "的時間")
        let km = kmNumber(n.km)
        let second: WatchCardLine
        let third: WatchCardLine
        if let goal = n.goalKm, goal > 0 {
            second = WatchCardLine(text: "這週 " + km + "／" + goalText(goal) + " 公里")
            let gap = goal - max(0, n.km)
            if gap > 0 {
                third = WatchCardLine(lead: "還差 " + kmNumber(gap), text: "・剩 \(n.daysLeft) 天", tone: toneBlue)
            } else {
                third = WatchCardLine(text: "這週達標了・連續 \(n.streakWeeks) 週")
            }
        } else {
            second = WatchCardLine(text: "這週 " + km + " 公里")
            third = WatchCardLine(text: "\(n.runs) 次・剩 \(n.daysLeft) 天")
        }
        let ref = WidgetDateText.dayKey(day) + "@" + String(slot.startMinute)
        return WatchRelevanceCard(id: cardId(.usualRun, ref), kind: WatchRelevanceKind.usualRun.rawValue,
                                  start: start, end: end, lines: [head, second, third], privateLines: nil,
                                  link: WidgetLink.healthRun.absoluteString)
    }

    // MARK: - 手錶小格：你自己加的「下一場」「已花」「這週跑步」什麼時候自己往上排（relevance()，watchOS 11 起）

    /// 「下一場」：今天、明天每一場開始前 60 分鐘到結束（還沒結束的；最多 maxPerKind 段，近的先）
    static func nextUpWindows(package: WatchPackage?, now: Date) -> [WatchRelevanceWindow] {
        guard let package, package.relevanceCards != nil, let life = package.life, !life.isExpired(at: now) else {
            return []
        }
        var out: [WatchRelevanceWindow] = []
        for day in life.days {
            for s in day.stops {
                let from = s.stop.start.addingTimeInterval(-Double(nextUpLeadMinutes) * 60)
                let to = s.stop.end
                guard to > from, to > now else { continue }
                out.append(WatchRelevanceWindow(start: from, end: to))
            }
        }
        out.sort { $0.start < $1.start }
        return Array(out.prefix(maxPerKind))
    }

    /// 「已花」：今天起 7 天裡的平日（一～五）11:30–13:30、17:30–19:30（「錢」沒送就沒有）
    static func spentWindows(package: WatchPackage?, now: Date) -> [WatchRelevanceWindow] {
        guard let package, package.relevanceCards != nil, package.money != nil else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var out: [WatchRelevanceWindow] = []
        for offset in 0..<daysAhead {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = cal.component(.weekday, from: day)
            guard weekday >= 2 && weekday <= 6 else { continue }
            for slot in spentSlots {
                let from = day.addingTimeInterval(Double(slot.from) * 60)
                let to = day.addingTimeInterval(Double(slot.to) * 60)
                guard to > now else { continue }
                out.append(WatchRelevanceWindow(start: from, end: to))
            }
        }
        return Array(out.prefix(maxPerKind))
    }

    /// 「這週跑步」：跟「平常跑步的時間」卡同一組時段（週日、今天跑過的規矩也一樣）
    static func runWeekWindows(package: WatchPackage?, run: WatchRunNumbers?, runStarts: [Date],
                               now: Date) -> [WatchRelevanceWindow] {
        let cards = liveCards(kind: .usualRun, package: package, run: run, runStarts: runStarts, arrivedStopIds: [],
                              now: now, forLookup: false)
        return cards.map { WatchRelevanceWindow(start: $0.start, end: $0.end) }
    }

    // MARK: - 小字（照抄手錶那幾支；sim_v7b、verify_v7b 核對兩邊一樣）

    /// 「10/27（二）」；withWeekday false＝「10/27」（＝WatchText.billDate）
    static func monthDay(_ date: Date, withWeekday: Bool) -> String {
        let cal = Calendar.current
        let c = cal.dateComponents([.month, .day, .weekday], from: date)
        let base = "\(c.month ?? 0)/\(c.day ?? 0)"
        guard withWeekday else { return base }
        let i = min(max((c.weekday ?? 1) - 1, 0), weekdayChars.count - 1)
        return base + "（" + weekdayChars[i] + "）"
    }

    /// 「今天截止」「明天截止」「3 天後」（＝WatchText.cardDueText）
    static func dueText(_ n: Int) -> String {
        if n <= 0 { return "今天截止" }
        if n == 1 { return "明天截止" }
        return "\(n) 天後"
    }

    /// 「30 分鐘」「1 小時」「1 小時 30 分」（＝WatchText.duration）
    static func duration(_ minutes: Int) -> String {
        let m = max(0, minutes)
        if m < 60 { return "\(m) 分鐘" }
        let h = m / 60
        let r = m % 60
        return r == 0 ? "\(h) 小時" : "\(h) 小時 \(r) 分"
    }

    /// 部屬會議的議程幾項（＝WatchText.agendaItems(…).count；只數，不帶內容）
    static func agendaCount(_ s: WidgetStop) -> Int {
        guard s.stop.kind == .meeting else { return 0 }
        return s.stop.detail.components(separatedBy: "、")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    /// 第二行（不寫人名）：部屬會議「30 分鐘・議程 3 項」；其他「12F 大會議室・30 分鐘」（沒地點只寫時長）（＝WatchText.faceDetail）
    static func stopDetail(_ s: WidgetStop) -> String {
        var parts: [String] = []
        if s.stop.kind == .meeting {
            parts.append(duration(s.stop.durationMinutes))
            let n = agendaCount(s)
            if n > 0 { parts.append("議程 \(n) 項") }
        } else {
            let place = s.location.trimmingCharacters(in: .whitespacesAndNewlines)
            if !place.isEmpty { parts.append(place) }
            parts.append(duration(s.stop.durationMinutes))
        }
        return parts.joined(separator: "・")
    }

    /// 行程種類的記號（＝WatchText.markSymbol）：● 部屬會議、○ 我的行事曆、■ 系統行事曆、✈︎ 旅遊景點
    static func markSymbol(_ kind: TimelineStopKind) -> String {
        switch kind {
        case .meeting:       return "circle.fill"
        case .personal:      return "circle"
        case .appleCalendar: return "square.fill"
        case .trip:          return "airplane"
        }
    }

    /// 行程種類的顏色（＝WatchPalette.kind）
    static func kindTint(_ kind: TimelineStopKind) -> UInt32 {
        switch kind {
        case .meeting:       return 0xFF9F0A
        case .personal:      return 0x64D2FF
        case .appleCalendar: return 0x30D158
        case .trip:          return 0xBF5AF2
        }
    }

    /// 「9.4」（一位小數；＝WatchRunFormat.kmNumber）
    static func kmNumber(_ km: Double) -> String {
        guard km.isFinite, km > 0 else { return "0.0" }
        return String(format: "%.1f", km)
    }

    /// 目標「20」「12.5」（＝WatchRunFormat.goalText）
    static func goalText(_ km: Double) -> String {
        km == km.rounded() ? String(format: "%.0f", km) : String(format: "%.1f", km)
    }
}
