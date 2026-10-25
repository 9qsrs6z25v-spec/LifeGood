import Foundation

// MARK: - 這週、那一趟、錶面「這週跑步」、摘要的亮點兩行（手錶 v5，v25.582；watch/judge.md §2.12、§2.13、§2.17、§3.1、§6.1；
//         watch/build/v5/brief.md §2；模擬：watch/build/v5/sim_v5.py 同名函式，改了兩邊一起改）
//
// 這個檔屬於手錶 App 與手錶小格兩個 target（iPhone 兩個 target 不編，同 WatchRunText.swift）。只准 Foundation。
// View 不自己拼字、不加減公里：每一頁、每一格拿這裡組好的結果排版。
//
// 資料從哪來：
//   • 包裡的 runWeek（iPhone 算好：這週公里、每天公里、連續週數、seen；[v5] recent 這週那幾趟、latest 最新一趟的亮點字）
//   • 手錶自己記、iPhone 還沒處理過的那幾趟（WatchRunLog；規則照 WatchRunText.home：存好了、seen 裡沒有、這週開始、
//     至少 60 秒、同一個編號只算一次——home 算好放在 WatchRunHome.ownExtra，這裡不重算）
// 一週從星期一算（WatchRunFacts.calendar，firstWeekday＝2）：週一 00:00 歸零、週日不歸零。
//
// ⚠️ 隱私（judge §2.17、§6.1）：
//   • 錶面「這週跑步」小格只有公里、次數、天數、連續週數（可以上鎖定畫面）——不寫名字、不畫路線
//   • 手錶 App 抬手：「河濱晨跑」、「河濱老路線・第 12 次」；手腕放下換「晨跑」「老路線・第 12 次」、路線小圖換一行字
//   • 路線只有 iPhone 給的 0～1000 相對形狀（WatchRunShapeXY）：沒有經緯度、沒有比例尺

// MARK: - 「這週」（judge §2.13）

/// 「這週」的一根小柱（週一到週日）
struct WatchRunBar: Equatable, Identifiable {
    /// 0＝週一 … 6＝週日
    var index: Int
    /// 「一」…「日」
    var label: String
    var km: Double
    /// 0～1（這週公里最多那一天＝1；都是 0 就全是 0，View 畫成一個點）
    var height: Double
    var isToday: Bool

    var id: Int { index }
}

/// 「這週」清單的一列（點了推「那一趟」：WatchRoute.runDetail(id)）
struct WatchRunRow: Equatable, Identifiable {
    /// iPhone 那一趟的編號；手錶自己記、iPhone 還沒帶進來的是「w-<手錶編號>」（WatchRunWeekText.ownPrefix）
    var id: String
    var sport: WatchSport
    /// 抬手：「河濱晨跑」
    var title: String
    /// 手腕放下：「晨跑」
    var privateTitle: String
    /// 「今天 06:05・5.20 公里・⌚︎」「10/20 19:10・5.10 公里」
    var line: String
}

/// 「這週」那一頁
struct WatchRunWeekPage: Equatable {
    /// 這週主角（小柱的顏色）
    var sport: WatchSport
    /// 7 根（週一到週日）
    var bars: [WatchRunBar]
    /// 「連續 6 週・最快 5 公里 30:51（今天）」；都沒有 nil
    var line: String?
    /// 新到舊、最多 5 列
    var rows: [WatchRunRow]
    /// 這週一趟都沒有：「這週還沒動，跑完會出現在這裡」；有就 nil
    var empty: String?
    /// 「iPhone 10/21 22:10 更新」（超過 12 小時）／「iPhone 還沒算這週」（過了週一 00:00）；新的、沒收過 nil
    var footnote: String?
}

/// 亮點那兩行（摘要、那一趟共用；judge §2.12、§2.13）
struct WatchRunHighlightLines: Equatable {
    /// 「河濱老路線・第 12 次」（手腕放下「老路線・第 12 次」）；沒有 nil
    var routeHead: String?
    /// 「比上次快 42 秒」（接在 routeHead 後面、中間「・」）；沒有 nil
    var routeDelta: String?
    /// routeDelta 的顏色：快＝green（5BD99A）、慢或差不多＝normal（灰）
    var deltaTone: WatchRunTone
    /// 「最快 5 公里 新紀錄 30:51（快 18 秒）」（前面畫 ★、琥珀）；沒破 nil
    var recordLine: String?
    /// 手錶記的、iPhone 還沒帶進來：灰字「第幾次、破紀錄，iPhone 帶進來後會算好」；其他 nil
    var pending: String?

    /// 什麼都不寫
    static let blank = WatchRunHighlightLines(routeHead: nil, routeDelta: nil, deltaTone: .normal,
                                             recordLine: nil, pending: nil)

    /// 有沒有要畫的
    var isEmpty: Bool { routeHead == nil && recordLine == nil && pending == nil }
}

/// 「那一趟」（judge §2.13 第二層）
struct WatchRunDetail: Equatable {
    var sport: WatchSport
    /// 抬手「河濱晨跑」
    var title: String
    /// 手腕放下「晨跑」
    var privateTitle: String
    /// 「今天 06:05」「10/20 19:10」
    var when: String
    /// 「5.20」
    var big: String
    /// 「32:04・配速 6'10"」（騎車「1:02:10・時速 21.5」）
    var line: String
    /// 「平均 152・最高 171」（前面畫 ♥；手錶自己記的那幾趟才有，iPhone 不存心率）
    var heartLine: String?
    /// 亮點（抬手、手腕放下兩份：View 照 dimmed 挑）
    var lines: WatchRunHighlightLines
    var privateLines: WatchRunHighlightLines
    /// 路線形狀（0～1000）；不到 2 點＝沒有小圖
    var shape: [WatchRunShapeXY]
    /// 手腕放下時小圖那一塊換這句（judge §2.13「路線在 iPhone 健康頁」）
    var shapeHidden: String
}

// MARK: - 錶面「這週跑步」（judge §3.1）

/// 錶面小格四種形狀的字（WidgetKit；手腕放下照樣顯示：公里、次數、天數可以上鎖定畫面，§2.17）
struct WatchRunFace: Equatable {
    var sport: WatchSport
    /// 收過 iPhone 的這週跑步
    var hasData: Bool
    /// 圓形中間「14.6」；沒收過「—」
    var big: String
    /// 圓形的環 0～1（這週公里 ÷ 目標）；沒設目標、沒收過 nil（不畫環）
    var ring: Double?
    /// 達標（環滿＋小 ✓）
    var reached: Bool
    /// 圓形下面「跑」「騎」
    var caption: String
    /// 角落沿邊「14.6／20」（沒目標「14.6 公里」；沒收過「—」）
    var corner: String
    /// 一行字「14.6／20 公里・連續 6 週」（前面 View 畫運動圖示）
    var inline: String
    /// 長方形第一行「這週 14.6／20 公里」
    var title: String
    /// 長方形中間 7 根小柱的高（0～1；週一到週日）
    var bars: [Double]
    /// 今天是第幾根（週一 0）
    var todayIndex: Int
    /// 長方形第三行「3 次・連續 6 週・剩 4 天」
    var line3: String
}

enum WatchRunWeekText {
    // MARK: 固定的字

    /// 手錶自己記的那一列的 id 開頭（後面接 WatchRunLogEntry.id）
    static let ownPrefix = "w-"
    /// 一到日
    static let dayLabels = ["一", "二", "三", "四", "五", "六", "日"]
    static let todayWord = "今天"
    /// 列尾的手錶記號（LifeGood 手錶記的）
    static let watchMark = "⌚︎"
    static let emptyWeek = "這週還沒動，跑完會出現在這裡"
    static let notThisWeek = "iPhone 還沒算這週"
    static let pendingNote = "第幾次、破紀錄，iPhone 帶進來後會算好"
    static let shapeHidden = "路線在 iPhone 健康頁"
    static let weekTitle = "這週"
    /// 「那一趟」找不到（過了週一、iPhone 刪掉了）
    static let detailGone = "這一趟不在這週了"
    /// 「那一趟」頁首（navigationTitle）
    static let detailTitle = "那一趟"
    /// 「這週」最多幾列
    static let maxRows = 5
    /// 手錶自己存的小圖最多幾點（跟 iPhone 送的一樣）
    static let shapeMaxPoints = 40
    /// 包裡的這週跑步超過這麼久沒更新，「這週」最下面寫「iPhone 10/21 22:10 更新」（judge §5.6）
    static let staleSeconds: Double = 12 * 3600
    /// 錶面小格沒資料時（judge §3.1「LifeGood／打開 iPhone 上的 App 一次」）
    static let faceNoDataTitle = "LifeGood"
    static let faceNoDataLine = "打開 iPhone 上的 App 一次"

    // MARK: 共用的小字

    /// 「今天 06:05」「10/20 19:10」
    static func whenText(_ start: Date, now: Date) -> String {
        let day = WatchRunFacts.calendar.isDate(start, inSameDayAs: now) ? todayWord : WidgetDateText.shortDate(start)
        return day + " " + DayTimelineFormat.time(start)
    }

    /// 「今天」「10/20」（「這週」那一行的「（今天）」）
    static func dayWord(_ date: Date, now: Date) -> String {
        WatchRunFacts.calendar.isDate(date, inSameDayAs: now) ? todayWord : WidgetDateText.shortDate(date)
    }

    /// 「32:04・配速 6'10"」；騎車「1:02:10・時速 21.5」（同 WatchRunText.summary 那一行的規則）
    static func paceLine(sport: WatchSport, km: Double, movingSeconds: Double) -> String {
        var line = WatchRunFormat.clock(seconds: movingSeconds)
        let minutes = movingSeconds / 60
        if sport == .bike {
            if let v = WatchRunFormat.speedKmh(km: km, minutes: minutes) {
                line += "・時速 " + WatchRunFormat.speedNumber(v)
            }
        } else if km > 0 && minutes > 0 {
            line += "・配速 " + WatchRunFormat.pace(km: km, minutes: minutes)
        }
        return line
    }

    /// 「平均 152・最高 171」；都沒有 nil
    static func heartLine(avg: Double?, max top: Double?) -> String? {
        var parts: [String] = []
        if let a = avg, a.isFinite, a > 0, a < 400 {
            parts.append("平均 \(WatchRunFormat.wholeSeconds(a))")
        }
        if let m = top, m.isFinite, m > 0, m < 400 {
            parts.append("最高 \(WatchRunFormat.wholeSeconds(m))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "・")
    }

    /// 亮點字 → 兩行（private＝手腕放下：不寫地名）
    static func lines(_ h: WatchRunHighlight?, hideNames hide: Bool) -> WatchRunHighlightLines {
        guard let h else { return .blank }
        let head = hide ? h.routePrivateHead : h.routeHead
        let delta = head == nil ? nil : h.routeDelta
        let tone: WatchRunTone = (h.routeFaster == true) ? .green : .normal
        return WatchRunHighlightLines(routeHead: head, routeDelta: delta, deltaTone: tone,
                                      recordLine: h.recordLine, pending: nil)
    }

    /// 手錶記的、iPhone 還沒帶進來（不寫假的：只寫一句灰字）
    static let pendingLines = WatchRunHighlightLines(routeHead: nil, routeDelta: nil, deltaTone: .normal,
                                                     recordLine: nil, pending: pendingNote)

    /// 這週的 recent（包裡的是 iPhone 那一週的：過了週一 00:00、iPhone 還沒算新的一週，舊的那幾趟不放）
    static func recentThisWeek(_ package: WatchPackage?, now: Date) -> [WatchRunRecent] {
        guard let list = package?.runWeek?.recent else { return [] }
        let week = WatchRunFacts.week(of: now)
        return list.filter { $0.start >= week.start && $0.start < week.end }
    }

    // MARK: 「這週」

    /// 「這週」那一頁：7 根小柱（WatchRunText.home 的 dayKm）＋「連續 6 週・最快 5 公里 30:51（今天）」＋新到舊最多 5 列
    /// （iPhone 送的這週那幾趟＋手錶自己記、iPhone 還沒帶進來的那幾趟）
    static func weekPage(package: WatchPackage?, own: [WatchRunLogEntry], now: Date,
                         lastSport: WatchSport?) -> WatchRunWeekPage {
        let home = WatchRunText.home(package: package, own: own, now: now, lastSport: lastSport)
        let bars = makeBars(home.dayKm, todayIndex: home.todayIndex)
        let rows = makeRows(package: package, extra: home.ownExtra, now: now)
        var parts: [String] = []
        if home.streakWeeks > 0 {
            parts.append("連續 \(home.streakWeeks) 週")
        }
        if let record = weekRecord(package: package, now: now) {
            parts.append(record)
        }
        return WatchRunWeekPage(sport: home.sport, bars: bars,
                                line: parts.isEmpty ? nil : parts.joined(separator: "・"),
                                rows: rows, empty: rows.isEmpty ? emptyWeek : nil,
                                footnote: weekFootnote(package: package, now: now))
    }

    /// 7 根小柱（高度＝那天公里 ÷ 這週最多那一天）
    static func makeBars(_ dayKm: [Double], todayIndex: Int) -> [WatchRunBar] {
        var km = Array(repeating: 0.0, count: 7)
        for i in 0..<min(7, dayKm.count) {
            let v = dayKm[i]
            km[i] = v.isFinite ? max(0, v) : 0
        }
        let top = km.max() ?? 0
        var out: [WatchRunBar] = []
        for i in 0..<7 {
            let h = top > 0 ? km[i] / top : 0
            out.append(WatchRunBar(index: i, label: dayLabels[i], km: km[i], height: h, isToday: i == todayIndex))
        }
        return out
    }

    /// 清單：iPhone 送的這週那幾趟＋手錶自己的（home.ownExtra），新到舊、最多 5 列
    static func makeRows(package: WatchPackage?, extra: [WatchRunLogEntry], now: Date) -> [WatchRunRow] {
        var items: [(start: Date, row: WatchRunRow)] = []
        for r in recentThisWeek(package, now: now) {
            let sport = WatchSport(rawValue: r.sport) ?? .run
            var line = whenText(r.start, now: now) + "・" + WatchRunFormat.preciseKmNumber(r.km, sport: sport) + " 公里"
            if r.byLifeGoodWatch { line += "・" + watchMark }
            let row = WatchRunRow(id: r.id, sport: sport, title: r.title, privateTitle: r.privateTitle, line: line)
            items.append((start: r.start, row: row))
        }
        for e in extra {
            let sport = WatchSport(rawValue: e.sport) ?? .run
            let name = WatchRunFacts.timeOfDayName(sport, start: e.start)
            let line = whenText(e.start, now: now) + "・"
                + WatchRunFormat.preciseKmNumber(e.meters / 1000, sport: sport) + " 公里・" + watchMark
            let row = WatchRunRow(id: ownPrefix + e.id.uuidString, sport: sport, title: name,
                                  privateTitle: name, line: line)
            items.append((start: e.start, row: row))
        }
        items.sort { $0.start > $1.start }
        return Array(items.prefix(maxRows).map { $0.row })
    }

    /// 「最快 5 公里 30:51（今天）」：這週最新一個破紀錄（recent 新到舊先找，找不到看 latest）；沒有 nil
    static func weekRecord(package: WatchPackage?, now: Date) -> String? {
        let list = recentThisWeek(package, now: now).sorted { $0.start > $1.start }
        for r in list {
            if let short = r.highlight?.recordShort {
                return short + "（" + dayWord(r.start, now: now) + "）"
            }
        }
        let week = WatchRunFacts.week(of: now)
        if let h = package?.runWeek?.latest, let short = h.recordShort, h.start >= week.start, h.start < week.end {
            return short + "（" + dayWord(h.start, now: now) + "）"
        }
        return nil
    }

    /// 「iPhone 還沒算這週」（過了週一 00:00）／「iPhone 10/21 22:10 更新」（超過 12 小時）；其他 nil
    static func weekFootnote(package: WatchPackage?, now: Date) -> String? {
        guard let w = package?.runWeek else { return nil }
        let week = WatchRunFacts.week(of: now)
        if abs(w.weekStart.timeIntervalSince(week.start)) >= 1 {
            return notThisWeek
        }
        if now.timeIntervalSince(w.generatedAt) > staleSeconds {
            return "iPhone " + WidgetDateText.updatedAt(w.generatedAt, now: now)
        }
        return nil
    }

    // MARK: 那一趟

    /// 「這週」點一列（id＝WatchRunRow.id）：iPhone 送的那一趟（名字、亮點、形狀；手錶自己也記過的補心率）、
    /// 或手錶自己記、iPhone 還沒帶進來的那一趟（時段名、心率、手錶存的小圖、灰字「iPhone 帶進來後會算好」）。找不到 nil
    static func detail(id: String, package: WatchPackage?, own: [WatchRunLogEntry], now: Date) -> WatchRunDetail? {
        if id.hasPrefix(ownPrefix) {
            let raw = String(id.dropFirst(ownPrefix.count))
            guard let e = own.first(where: { $0.id.uuidString == raw }) else { return nil }
            // [驗證 v5-2] 看著這一頁的時候 iPhone 帶進來了（包裡這週那幾趟有同一個 Apple 健康編號）：換成 iPhone 那一份
            // （名字、亮點、形狀），不再一直寫「iPhone 帶進來後會算好」
            if let wid = e.workoutId, !wid.isEmpty,
               let r = package?.runWeek?.recent?.first(where: { $0.workoutId == wid }) {
                return phoneDetail(r, own: own, now: now)
            }
            var d = ownDetail(e, now: now)
            // [驗證 v5-2] 帶進來又在 iPhone 刪掉（seen 有、recent 沒有）：不會再算了，灰字不寫（同 summaryLines）
            if let wid = e.workoutId, package?.runWeek?.seen.contains(wid) == true {
                d.lines = .blank
                d.privateLines = .blank
            }
            return d
        }
        guard let r = package?.runWeek?.recent?.first(where: { $0.id == id }) else { return nil }
        return phoneDetail(r, own: own, now: now)
    }

    /// iPhone 送的那一趟（名字、亮點、形狀；手錶自己也記過的補心率、iPhone 沒形狀時用手錶存的小圖）
    static func phoneDetail(_ r: WatchRunRecent, own: [WatchRunLogEntry], now: Date) -> WatchRunDetail {
        let sport = WatchSport(rawValue: r.sport) ?? .run
        var heart: String? = nil
        var shape = r.shape ?? []
        if let wid = r.workoutId, let e = own.first(where: { $0.workoutId == wid }) {
            heart = heartLine(avg: e.heartAvg, max: e.heartMax)
            if shape.count < 2 { shape = e.shape ?? [] }
        }
        return WatchRunDetail(sport: sport, title: r.title, privateTitle: r.privateTitle,
                              when: whenText(r.start, now: now),
                              big: WatchRunFormat.preciseKmNumber(r.km, sport: sport),
                              line: paceLine(sport: sport, km: r.km, movingSeconds: r.movingSeconds),
                              heartLine: heart,
                              lines: lines(r.highlight, hideNames: false),
                              privateLines: lines(r.highlight, hideNames: true),
                              shape: shape.count >= 2 ? shape : [], shapeHidden: shapeHidden)
    }

    /// 手錶自己記、iPhone 還沒帶進來的那一趟
    static func ownDetail(_ e: WatchRunLogEntry, now: Date) -> WatchRunDetail {
        let sport = WatchSport(rawValue: e.sport) ?? .run
        let name = WatchRunFacts.timeOfDayName(sport, start: e.start)
        let km = e.meters / 1000
        let shape = e.shape ?? []
        let pending = e.saved ? pendingLines : WatchRunHighlightLines.blank
        return WatchRunDetail(sport: sport, title: name, privateTitle: name, when: whenText(e.start, now: now),
                              big: WatchRunFormat.preciseKmNumber(km, sport: sport),
                              line: paceLine(sport: sport, km: km, movingSeconds: e.movingSeconds),
                              heartLine: heartLine(avg: e.heartAvg, max: e.heartMax),
                              lines: pending, privateLines: pending,
                              shape: shape.count >= 2 ? shape : [], shapeHidden: shapeHidden)
    }

    // MARK: 跑完摘要的亮點兩行（judge §2.12）

    /// 剛跑完的那一趟（r.workoutId）：包裡 latest 或這週 recent 有它＝iPhone 帶進來、算好了 → 有什麼寫什麼（第一次跑這條路、
    /// 沒破紀錄就什麼都不寫）；seen 有它（帶進來又被你刪掉）→ 不寫；都沒有 → 灰字「iPhone 帶進來後會算好」。
    /// 沒存好（saved＝false）、沒有編號：不寫。hide＝手腕放下（「老路線・第 12 次」）
    static func summaryLines(_ r: WatchRunRecord, saved: Bool, package: WatchPackage?, hide: Bool) -> WatchRunHighlightLines {
        guard saved, let id = r.workoutId, !id.isEmpty else { return .blank }
        // [驗證 v5-3] 不到 1 分鐘的那一趟（〔存下來〕的；開始到結束，同 iPhone 帶進來、③ 的規矩）：iPhone 不會帶進來，灰字不寫
        if (r.end ?? r.updatedAt).timeIntervalSince(r.start) < WatchRunMath.shortSeconds {
            return .blank
        }
        let w = package?.runWeek
        if let h = w?.latest, h.workoutId == id {
            return lines(h, hideNames: hide)
        }
        if let hit = w?.recent?.first(where: { $0.workoutId == id }) {
            return lines(hit.highlight, hideNames: hide)
        }
        if let seen = w?.seen, seen.contains(id) {
            return .blank
        }
        return pendingLines
    }

    // MARK: 錶面「這週跑步」

    /// 四種形狀的字（judge §3.1：圓形「14.6」一圈 73%、角落「14.6／20」、一行字「14.6／20 公里・連續 6 週」、
    /// 長方形「這週 14.6／20 公里」／7 根小柱／「3 次・連續 6 週・剩 4 天」）。數字全照 WatchRunText.home（③ 同一套）
    static func face(package: WatchPackage?, own: [WatchRunLogEntry], now: Date, lastSport: WatchSport?) -> WatchRunFace {
        let home = WatchRunText.home(package: package, own: own, now: now, lastSport: lastSport)
        let verb = WatchRunFacts.verb(home.sport)
        let bars = makeBars(home.dayKm, todayIndex: home.todayIndex).map { $0.height }
        guard home.hasData else {
            return WatchRunFace(sport: home.sport, hasData: false, big: "—", ring: nil, reached: false, caption: verb,
                                corner: "—", inline: faceNoDataLine, title: faceNoDataTitle, bars: bars,
                                todayIndex: home.todayIndex, line3: faceNoDataLine)
        }
        let kmText = WatchRunFormat.kmNumber(home.km)
        var ring: Double? = nil
        var reached = false
        var pair = kmText + " 公里"
        var corner = kmText + " 公里"
        if let g = home.goalKm, g > 0 {
            let v = home.km / g
            ring = v.isFinite ? min(1, max(0, v)) : 0
            reached = home.km >= g - 0.05
            pair = kmText + "／" + WatchRunText.goalText(g) + " 公里"
            corner = kmText + "／" + WatchRunText.goalText(g)
        }
        var inline = pair
        if home.streakWeeks > 0 {
            inline += "・連續 \(home.streakWeeks) 週"
        }
        var parts: [String] = []
        parts.append(home.runs > 0 ? "\(home.runs) 次" : "這週還沒" + verb)
        if home.streakWeeks > 0 {
            parts.append("連續 \(home.streakWeeks) 週")
        }
        parts.append(reached ? "已達標" : "剩 \(home.daysLeft) 天")
        return WatchRunFace(sport: home.sport, hasData: true, big: kmText, ring: ring, reached: reached, caption: verb,
                            corner: corner, inline: inline, title: weekTitle + " " + pair, bars: bars,
                            todayIndex: home.todayIndex, line3: parts.joined(separator: "・"))
    }

    /// 錶面小格的時間軸：現在＋往後每天 00:00（7 天，含下週一 00:00 歸零那一筆；週日不歸零）。iPhone 沒送新包也會自己換天
    static func faceDates(now: Date) -> [Date] {
        let cal = WatchRunFacts.calendar
        let today = cal.startOfDay(for: now)
        var out: [Date] = [now]
        for k in 1...7 {
            if let d = cal.date(byAdding: .day, value: k, to: today), d > now {
                out.append(d)
            }
        }
        return out
    }

    /// 什麼時候跟系統要下一份時間軸（最後一筆那一刻）
    static func faceReloadAt(now: Date) -> Date {
        faceDates(now: now).last ?? now.addingTimeInterval(86_400)
    }

    // MARK: 手錶自己存的小圖

    /// 摘要那份小圖（0～1）→ 存進 WatchRunLog 的 0～1000 形狀（平均抽到最多 40 點，最後一點一定留；同一點連續的只留一個）
    static func compactShape(_ points: [WatchRunShapePoint], maxPoints: Int = shapeMaxPoints) -> [WatchRunShapeXY] {
        guard points.count >= 2, maxPoints >= 2 else { return [] }
        var picked: [WatchRunShapePoint] = []
        if points.count <= maxPoints {
            picked = points
        } else {
            let step = Double(points.count - 1) / Double(maxPoints - 1)
            for i in 0..<maxPoints {
                let idx = min(points.count - 1, Int((Double(i) * step).rounded()))
                picked.append(points[idx])
            }
        }
        var out: [WatchRunShapeXY] = []
        for p in picked {
            let q = WatchRunShapeXY(x: unit(p.x), y: unit(p.y), s: max(0, p.seg))
            if let last = out.last, last == q { continue }
            out.append(q)
        }
        return out.count >= 2 ? out : []
    }

    /// 0～1 → 0～1000（NaN、超出範圍夾住）
    static func unit(_ v: Double) -> Int {
        guard v.isFinite else { return 0 }
        return Int((min(max(v, 0), 1) * 1000).rounded())
    }
}
