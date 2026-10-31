import Foundation
import MapKit

// MARK: - [v25.595] 旅遊規劃本：AI 排好的行程貼進來就變成一份行程
//
// 格式刻意簡單：一行一個欄位「欄位：內容」，看到「景點：」「住宿：」就是新的一站，「第 2 天」分天。
// AI 寫得出來、人也看得懂、打錯一點也讀得進來（全形半形冒號、前面的 - ＊ 1.、Markdown 粗體、
// 同一行用｜隔開好幾個欄位都可以）。讀不懂的行不會丟掉：放進那一站（或整份行程）的備註。
//
// 範例：
//   行程：福岡三天兩夜
//   出發：2026/12/20 08:30
//   交通：開車
//
//   第1天
//   景點：太宰府天滿宮
//   地址：福岡県太宰府市宰府4-7-1
//   停留：90
//   必去：是
//
//   住宿：博多綠色飯店
//   退房：10:00
//
//   攜帶：護照、日幣、充電器
//   伴手禮：明太子 ×2（給家人）

enum TripPlanImport {

    struct Result {
        var plan: TripPlan
        /// 讀的時候幫你補的、猜的（預覽頁列出來）
        var warnings: [String]
        /// 每一站在第幾天（1 起算；跟 plan.stops 同順序），預覽頁分天用
        var stopDays: [Int]
        /// AI 給的座標（找位置時當參考；找不到才用它）
        var hints: [UUID: CLLocationCoordinate2D]
    }

    // MARK: 欄位名稱（同義字都收）

    private enum Key {
        case title, start, mode, note, stop, lodging, address, phone, dwell, arrival, must, checkout, coord
        case packing, souvenir
    }

    private static let keyWords: [(String, Key)] = [
        ("行程名稱", .title), ("行程", .title), ("標題", .title), ("旅程", .title),
        ("出發時間", .start), ("出發日期", .start), ("出發", .start), ("開始", .start), ("日期", .start),
        ("交通方式", .mode), ("交通", .mode), ("移動方式", .mode),
        ("備註", .note), ("說明", .note), ("注意", .note), ("提醒", .note),
        ("景點", .stop), ("地點", .stop), ("站", .stop), ("行程點", .stop),
        ("早餐", .stop), ("午餐", .stop), ("晚餐", .stop), ("餐廳", .stop), ("活動", .stop),
        ("住宿", .lodging), ("飯店", .lodging), ("旅館", .lodging), ("民宿", .lodging), ("過夜", .lodging),
        ("地址", .address),
        ("電話", .phone),
        ("停留時間", .dwell), ("停留", .dwell), ("時長", .dwell), ("待", .dwell),
        ("抵達時間", .arrival), ("抵達", .arrival), ("到達", .arrival), ("時間", .arrival),
        ("必去", .must),
        ("退房時間", .checkout), ("退房", .checkout),
        ("座標", .coord), ("經緯度", .coord),
        ("攜帶物品", .packing), ("攜帶", .packing), ("要帶", .packing), ("行李", .packing), ("帶去", .packing),
        ("伴手禮", .souvenir), ("要買", .souvenir), ("紀念品", .souvenir),
    ]

    // MARK: 給 AI 的說明（〔複製給 AI 的說明〕）

    /// 貼給 ChatGPT／Claude／Gemini 的那一段。wish＝你想去哪、幾天（空的也可以）
    static func aiGuide(wish: String) -> String {
        let w = wish.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        請幫我規劃一趟旅行\(w.isEmpty ? "" : "：\(w)")。

        請「只」用下面的格式回覆（放在一個程式碼區塊裡），不要加其他說明，我要直接匯入 App：
        - 一行一個欄位，寫成「欄位：內容」。
        - 開頭寫：行程、出發（年/月/日 時:分）、交通（開車／步行／大眾運輸／飛機 選一個）、備註（選填）。
        - 每一天先寫一行「第1天」「第2天」…。
        - 每一站用「景點：」開頭，下面接 地址、停留（分鐘）、抵達（時:分，只有餐廳訂位、船班、表演這種時間固定的才寫）、交通（這一段跟預設不同才寫）、電話、必去（是）、備註。
        - 每天最後住的地方用「住宿：」開頭，下面可以寫 地址、退房（時:分）。最後一天回家就不用寫住宿。
        - 地址請寫當地語言的完整地址（日本寫日文地址），電話寫當地電話，查不到就不要寫，不要編。
        - 最後寫「攜帶：」「伴手禮：」，用頓號分開，數量寫「×2」，送誰寫「（給家人）」。

        範例：
        行程：福岡三天兩夜
        出發：2026/12/20 08:30
        交通：開車
        備註：博多站租車

        第1天
        景點：太宰府天滿宮
        地址：福岡県太宰府市宰府4-7-1
        停留：90
        必去：是
        備註：參拜後吃梅枝餅

        景點：一蘭 本社總本店
        地址：福岡県福岡市博多区中洲5-3-2
        抵達：18:00
        停留：60

        住宿：博多綠色飯店1號館
        地址：福岡県福岡市博多区博多駅中央街4-4
        退房：10:00

        第2天
        景點：柳川遊船
        交通：大眾運輸
        停留：70

        攜帶：護照、日幣現金、充電器
        伴手禮：明太子 ×2（給家人）、博多通りもん
        """
    }

    // MARK: 讀

    /// 讀一份旅遊規劃本。一站都沒有、也沒有行程名稱跟清單＝nil（不是這個格式）
    static func parse(_ raw: String, now: Date = Date(), calendar cal: Calendar = .current) -> Result? {
        var title = ""
        var startText: String?
        var mode: TripTravelMode = .driving
        var planNotes: [String] = []
        var stops: [TripStop] = []
        var stopDays: [Int] = []
        var arrivalTexts: [UUID: String] = [:]
        var hints: [UUID: CLLocationCoordinate2D] = [:]
        var packing: [TripChecklistItem] = []
        var souvenirs: [TripChecklistItem] = []
        var warnings: [String] = []

        var day = 1
        var listMode: Key?          // 正在讀「攜帶」「伴手禮」下面一條一條的
        var current: TripStop?      // 正在讀的那一站

        func flush() {
            guard var s = current else { return }
            current = nil
            s.name = s.name.trimmingCharacters(in: .whitespaces)
            s.note = s.note.trimmingCharacters(in: .whitespacesAndNewlines)
            stops.append(s)
            stopDays.append(day)
        }

        for rawLine in raw.components(separatedBy: .newlines) {
            // 同一行用｜隔開好幾個欄位（「景點：太宰府｜停留：90」）
            let segments = rawLine.contains("｜") || rawLine.contains("|")
                ? rawLine.components(separatedBy: CharacterSet(charactersIn: "｜|"))
                : [rawLine]
            for seg in segments {
                let line = cleanLine(seg)
                if line.isEmpty || line.hasPrefix("```") { continue }

                if let n = dayNumber(line) {
                    flush()
                    listMode = nil
                    if n > day, let last = stops.indices.last, stopDays[last] == day, !stops[last].isOvernight {
                        // 換天了，前一天最後一站沒寫住宿：時間軸要在這裡過夜才會換到隔天
                        stops[last].isOvernight = true
                        warnings.append("第\(day)天最後一站「\(stops[last].name)」沒有寫住宿，當成在那裡過夜")
                    }
                    day = max(day, n)
                    continue
                }

                func addNote(_ text: String) {
                    if current != nil {
                        current!.note += (current!.note.isEmpty ? "" : "\n") + text
                    } else {
                        planNotes.append(text)
                    }
                }

                guard let kv = splitKey(line) else {
                    // 沒有欄位名稱的一行：清單底下的一條、這一站（或整份行程）的備註
                    if listMode == .packing {
                        packing += items(line)
                    } else if listMode == .souvenir {
                        souvenirs += items(line)
                    } else {
                        addNote(line)
                    }
                    continue
                }
                let key = kv.0
                let value = kv.1

                switch key {
                case .stop, .lodging:
                    flush()
                    listMode = nil
                    var s = TripStop(name: value, dwellMinutes: 60)
                    s.isOvernight = key == .lodging
                    let (name, must) = stripMustMark(value)
                    s.name = name
                    s.isMustVisit = must
                    current = s
                case .packing, .souvenir:
                    flush()
                    listMode = key
                    if key == .packing { packing += items(value) } else { souvenirs += items(value) }
                case .title:
                    if current == nil && stops.isEmpty { title = value } else { addNote(value) }
                case .start:
                    if current == nil && stops.isEmpty { startText = value } else { addNote("出發：" + value) }
                case .mode:
                    if let m = travelMode(value) {
                        if current != nil { current!.legModeOverride = m } else if stops.isEmpty { mode = m }
                    } else {
                        addNote("交通：" + value)
                    }
                case .note:
                    addNote(value)
                case .address:
                    if current != nil { current!.address = value } else { planNotes.append("地址：" + value) }
                case .phone:
                    if current != nil { current!.phone = value }
                case .dwell:
                    if current != nil, let m = minutes(value) { current!.dwellMinutes = m }
                case .arrival:
                    if let c = current { arrivalTexts[c.id] = value }
                case .must:
                    if current != nil { current!.isMustVisit = yes(value) }
                case .checkout:
                    if current != nil, let hm = clock(value) {
                        current!.checkOutTime = cal.date(bySettingHour: hm.0, minute: hm.1, second: 0, of: now)
                    }
                case .coord:
                    if let c = current, let p = coordinate(value) { hints[c.id] = p }
                }
            }
        }
        flush()

        guard !stops.isEmpty || !title.isEmpty || !packing.isEmpty || !souvenirs.isEmpty else { return nil }

        // 出發時間：沒寫或看不懂就排明天 09:00
        let start: Date
        if let t = startText, let d = date(t, now: now, cal: cal) {
            start = d
        } else {
            let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
            start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
            warnings.append(startText == nil ? "沒有寫出發時間，先排明天 09:00（匯入後可以改）"
                                              : "看不懂出發時間「\(startText!)」，先排明天 09:00（匯入後可以改）")
        }

        // 指定抵達時間：「18:00」＝那一天的 18:00；「12/21 18:00」照寫的日子
        let startDay = cal.startOfDay(for: start)
        for i in stops.indices {
            guard let text = arrivalTexts[stops[i].id] else { continue }
            if hasDatePart(text), let d = date(text, now: start, cal: cal) {
                stops[i].arrivalOverride = d
            } else if let hm = clock(text),
                      let dayDate = cal.date(byAdding: .day, value: stopDays[i] - 1, to: startDay) {
                stops[i].arrivalOverride = cal.date(bySettingHour: hm.0, minute: hm.1, second: 0, of: dayDate)
            }
        }
        // 最後一站寫了住宿：當成最後一晚住那裡（行程延到隔天退房）。不警告：那是你寫的

        let unnamed = stops.filter { $0.name.isEmpty }.count
        if unnamed > 0 { warnings.append("有 \(unnamed) 站沒有名稱") }

        var plan = TripPlan(title: title, startDate: start, travelMode: mode,
                            note: planNotes.joined(separator: "\n"), stops: stops,
                            packingItems: packing, souvenirItems: souvenirs)
        plan.title = plan.title.trimmingCharacters(in: .whitespaces)
        return Result(plan: plan, warnings: warnings, stopDays: stopDays, hints: hints)
    }

    // MARK: 一行一行

    /// 去掉清單符號、編號、Markdown 粗體、引號、頭尾空白
    private static func cleanLine(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)
        // 開頭的 - * • ・ ＊ # > 與「1.」「1、」「(1)」
        while let f = t.first, "-*•・＊#>●○◆■□▪︎·".contains(f) {
            t.removeFirst()
            t = t.trimmingCharacters(in: .whitespaces)
        }
        if let r = t.range(of: #"^[0-9０-９]{1,2}[\.、．)）]\s*"#, options: .regularExpression),
           !t[r.upperBound...].hasPrefix(":") {
            // 「1. 景點：…」去掉編號；「18:00」不是編號（後面接冒號）
            let rest = t[r.upperBound...]
            if !rest.isEmpty { t = String(rest) }
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// 「第1天」「第 2 天」「第三天」「Day 2」「D2」（後面接日期、標題都可以）
    private static func dayNumber(_ line: String) -> Int? {
        let t = line.trimmingCharacters(in: .whitespaces)
        if let r = t.range(of: #"^第\s*([0-9０-９一二三四五六七八九十兩]+)\s*[天日]"#, options: .regularExpression) {
            let inner = t[r].dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
            return number(String(inner))
        }
        if let r = t.range(of: #"^(?i)(day|d)\s*([0-9]+)\b"#, options: .regularExpression) {
            let digits = t[r].filter(\.isNumber)
            return Int(String(digits))
        }
        return nil
    }

    /// 「欄位：內容」→ 認得的欄位才算（「18:00」「注意：…」這種靠欄位表分）
    private static func splitKey(_ line: String) -> (Key, String)? {
        guard let idx = line.firstIndex(where: { $0 == "：" || $0 == ":" }) else { return nil }
        let head = line[..<idx].trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "")
        guard !head.isEmpty, head.count <= 6 else { return nil }
        guard let key = keyWords.first(where: { $0.0 == head })?.1 else { return nil }
        let value = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    /// 名字裡的「（必去）」「★」：拿掉、標必去
    private static func stripMustMark(_ name: String) -> (String, Bool) {
        var n = name
        var must = false
        for mark in ["（必去）", "(必去)", "【必去】", "[必去]", "★", "⭐️", "⭐"] where n.contains(mark) {
            n = n.replacingOccurrences(of: mark, with: "")
            must = true
        }
        return (n.trimmingCharacters(in: .whitespaces), must)
    }

    private static func yes(_ v: String) -> Bool {
        let t = v.lowercased().trimmingCharacters(in: .whitespaces)
        return ["是", "要", "必去", "y", "yes", "true", "1", "✓", "✔", "v", "o", "○"].contains(t) || t.hasPrefix("是")
    }

    private static func travelMode(_ v: String) -> TripTravelMode? {
        let t = v.lowercased()
        if ["飛機", "航班", "搭機", "plane", "flight", "fly"].contains(where: t.contains) { return .plane }
        if ["步行", "走路", "徒步", "walk"].contains(where: t.contains) { return .walking }
        if ["大眾運輸", "電車", "捷運", "地鐵", "公車", "火車", "高鐵", "新幹線", "巴士", "客運", "jr", "輕軌", "渡輪", "船", "transit", "train", "bus", "subway", "metro"].contains(where: t.contains) { return .transit }
        if ["開車", "自駕", "租車", "汽車", "計程車", "car", "drive", "driving", "taxi"].contains(where: t.contains) { return .driving }
        return nil
    }

    /// 「90」「90分」「90 分鐘」「1.5小時」「1小時30分」「1小時半」「2h」「30min」
    static func minutes(_ v: String) -> Int? {
        let t = v.lowercased().replacingOccurrences(of: " ", with: "")
        let digitsOnly = t.filter { $0.isNumber || $0 == "." }
        if !digitsOnly.isEmpty, digitsOnly == t, let n = Double(t) { return max(0, Int(n.rounded())) }
        var total = 0.0
        var matched = false
        if let r = t.range(of: #"[0-9]+(\.[0-9]+)?(?=(小時|鐘頭|個小時|hr|h|時))"#, options: .regularExpression),
           let h = Double(t[r]) {
            total += h * 60; matched = true
            if t.contains("半") { total += 30 }
        } else if t.contains("半小時") || t.contains("半個小時") {
            total += 30; matched = true
        }
        if let r = t.range(of: #"[0-9]+(?=(分|min|m(?!o)))"#, options: .regularExpression), let m = Double(t[r]) {
            // 「1小時30分」：小時那段已經算過，這裡只加分鐘
            total += m; matched = true
        }
        return matched ? max(0, Int(total.rounded())) : nil
    }

    /// 「18:00」「18：00」「下午6點」「6pm」「18點30分」→（時, 分）
    static func clock(_ v: String) -> (Int, Int)? {
        let t = v.lowercased().replacingOccurrences(of: "：", with: ":").replacingOccurrences(of: " ", with: "")
        var hour: Int?
        var minute = 0
        if let r = t.range(of: #"([0-9]{1,2}):([0-9]{2})"#, options: .regularExpression) {
            let parts = t[r].split(separator: ":")
            hour = Int(parts[0]); minute = Int(parts[1]) ?? 0
        } else if let r = t.range(of: #"([0-9]{1,2})(點|時)([0-9]{1,2})?"#, options: .regularExpression) {
            let s = t[r]
            let nums = s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            hour = nums.first; minute = nums.count > 1 ? nums[1] : (s.contains("半") || t.contains("點半") ? 30 : 0)
        } else if let r = t.range(of: #"([0-9]{1,2})(am|pm)"#, options: .regularExpression) {
            hour = Int(t[r].filter(\.isNumber))
        }
        guard var h = hour else { return nil }
        if (t.contains("下午") || t.contains("晚上") || t.contains("pm")) && h < 12 { h += 12 }
        if (t.contains("凌晨") || t.contains("am")) && h == 12 { h = 0 }
        guard (0...23).contains(h), (0...59).contains(minute) else { return nil }
        return (h, minute)
    }

    /// 「2026/12/20 08:30」「2026-12-20」「2026年12月20日 8:30」「12/20 08:30」（沒寫年：今年，已經過了就明年）
    static func date(_ v: String, now: Date, cal: Calendar) -> Date? {
        let t = v.replacingOccurrences(of: "年", with: "/").replacingOccurrences(of: "月", with: "/")
            .replacingOccurrences(of: "日", with: " ").replacingOccurrences(of: "-", with: "/")
            .replacingOccurrences(of: "．", with: "/").replacingOccurrences(of: ".", with: "/")
        var y: Int?, mo: Int?, d: Int?
        if let r = t.range(of: #"([0-9]{4})/([0-9]{1,2})/([0-9]{1,2})"#, options: .regularExpression) {
            let p = t[r].split(separator: "/").compactMap { Int($0) }
            if p.count == 3 { y = p[0]; mo = p[1]; d = p[2] }
        } else if let r = t.range(of: #"([0-9]{1,2})/([0-9]{1,2})"#, options: .regularExpression) {
            let p = t[r].split(separator: "/").compactMap { Int($0) }
            if p.count == 2 { mo = p[0]; d = p[1] }
        }
        guard let month = mo, let dayN = d, (1...12).contains(month), (1...31).contains(dayN) else {
            // 只寫時間（沒有日子）：明天那個時間
            if !hasDatePart(v), let hm = clock(t) {
                let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
                return cal.date(bySettingHour: hm.0, minute: hm.1, second: 0, of: tomorrow)
            }
            return nil
        }
        // 時間在日期後面那段（「12/20 08:30」不能把 12/20 當成時間）
        let afterDate: String = {
            guard let r = t.range(of: #"[0-9]{1,2}/[0-9]{1,2}"#, options: [.regularExpression, .backwards]) else { return "" }
            return String(t[r.upperBound...])
        }()
        let (h, m) = clock(afterDate) ?? (9, 0)
        var comps = DateComponents(year: y ?? cal.component(.year, from: now), month: month, day: dayN, hour: h, minute: m)
        guard var result = cal.date(from: comps) else { return nil }
        if y == nil, result < cal.startOfDay(for: now) {
            comps.year = (comps.year ?? 0) + 1
            result = cal.date(from: comps) ?? result
        }
        return result
    }

    /// 有沒有寫日子（「12/21」「12月21日」「2026-12-21」）；「18:00-19:00」不算
    static func hasDatePart(_ v: String) -> Bool {
        v.range(of: #"(^|[^0-9:])(1[0-2]|0?[1-9])\s*[/月]\s*(3[01]|[12][0-9]|0?[1-9])(?![0-9:])"#, options: .regularExpression) != nil
            || v.range(of: #"[0-9]{4}\s*[-/年.]\s*[0-9]{1,2}\s*[-/月.]\s*[0-9]{1,2}"#, options: .regularExpression) != nil
    }

    /// 「33.5902, 130.4207」
    private static func coordinate(_ v: String) -> CLLocationCoordinate2D? {
        let nums = v.replacingOccurrences(of: "，", with: ",")
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "、" })
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard nums.count >= 2, (-90...90).contains(nums[0]), (-180...180).contains(nums[1]) else { return nil }
        return CLLocationCoordinate2D(latitude: nums[0], longitude: nums[1])
    }

    /// 「一」～「十」、「兩」、全形數字
    private static func number(_ s: String) -> Int? {
        let half = String(s.map { c -> Character in
            if let v = c.unicodeScalars.first?.value, (0xFF10...0xFF19).contains(v) {
                return Character(UnicodeScalar(v - 0xFF10 + 0x30)!)
            }
            return c
        })
        if let n = Int(half) { return n }
        let digits: [Character: Int] = ["一": 1, "二": 2, "兩": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if half == "十" { return 10 }
        if half.hasPrefix("十"), let last = half.last, let d = digits[last] { return 10 + d }
        if half.count == 2, let f = half.first, let d = digits[f], half.last == "十" { return d * 10 }
        if half.count == 3, let f = half.first, let a = digits[f], let l = half.last, let b = digits[l] { return a * 10 + b }
        if half.count == 1, let f = half.first { return digits[f] }
        return nil
    }

    /// 「護照、日幣現金、充電器」「明太子 ×2（給家人）」→ 一條一條
    private static func items(_ v: String) -> [TripChecklistItem] {
        v.components(separatedBy: CharacterSet(charactersIn: "、，,；;"))
            .map(cleanLine)
            .filter { !$0.isEmpty }
            .map(item)
    }

    private static func item(_ raw: String) -> TripChecklistItem {
        var name = raw
        var qty = 1
        var forWhom = ""
        // （給家人）(給同事)
        if let r = name.range(of: #"[（(]\s*給\s*([^）)]+)[）)]"#, options: .regularExpression) {
            forWhom = String(name[r]).trimmingCharacters(in: CharacterSet(charactersIn: "（()）給 "))
            name.removeSubrange(r)
        }
        // ×2 x2 *2 X2
        if let r = name.range(of: #"[×xX*＊]\s*([0-9]+)"#, options: .regularExpression) {
            qty = Int(name[r].filter(\.isNumber)) ?? 1
            name.removeSubrange(r)
        }
        return TripChecklistItem(name: name.trimmingCharacters(in: .whitespaces),
                                 quantity: max(1, qty), forWhom: forWhom)
    }

    // MARK: 找位置（匯入時一站一站問 Apple 地圖）

    struct Found {
        let latitude: Double
        let longitude: Double
        let address: String
        let phone: String?
    }

    /// 用名稱＋地址問一次 Apple 地圖。AI 給了座標就只在那附近找（3 公里內才算，找不到就用 AI 的座標）；
    /// 沒給座標就用 near（上一站找到的位置）當參考範圍，避免「一蘭」跑到別的縣。找不到＝nil，那一站之後自己選位置
    static func locate(_ stop: TripStop, hint: CLLocationCoordinate2D?, near: CLLocationCoordinate2D?) async -> Found? {
        let name = stop.name.trimmingCharacters(in: .whitespaces)
        let address = stop.address.trimmingCharacters(in: .whitespaces)
        let query = [name, address].filter { !$0.isEmpty }.joined(separator: " ")
        guard !query.isEmpty else {
            return hint.map { Found(latitude: $0.latitude, longitude: $0.longitude, address: "", phone: nil) }
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let center = hint ?? near {
            let meters: CLLocationDistance = hint != nil ? 20_000 : 150_000
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: meters, longitudinalMeters: meters)
        }
        var items = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
        // 名稱＋地址查不到：只用地址再查一次
        if items.isEmpty, !address.isEmpty, !name.isEmpty {
            let r2 = MKLocalSearch.Request()
            r2.naturalLanguageQuery = address
            r2.region = request.region
            items = (try? await MKLocalSearch(request: r2).start())?.mapItems ?? []
        }
        if let hint {
            let origin = CLLocation(latitude: hint.latitude, longitude: hint.longitude)
            let close = items.first { ($0.placemark.location?.distance(from: origin) ?? .infinity) <= 3_000 }
            guard let item = close else {
                return Found(latitude: hint.latitude, longitude: hint.longitude, address: "", phone: nil)
            }
            return found(item)
        }
        return items.first.map(found)
    }

    private static func found(_ item: MKMapItem) -> Found {
        let pm = item.placemark
        let addr = TripAddress.tidy([pm.postalCode, pm.administrativeArea, pm.locality,
                                     pm.thoroughfare, pm.subThoroughfare].compactMap { $0 }.joined())
        let phone = item.phoneNumber?.trimmingCharacters(in: .whitespaces)
        return Found(latitude: pm.coordinate.latitude, longitude: pm.coordinate.longitude,
                     address: addr, phone: (phone?.isEmpty ?? true) ? nil : phone)
    }
}
