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
        ("建議停留時間", .dwell), ("建議停留", .dwell), ("預計停留", .dwell), ("遊玩時間", .dwell), ("所需時間", .dwell),
        ("預約時間", .arrival), ("訂位時間", .arrival), ("住址", .address), ("電話號碼", .phone), ("交通工具", .mode),
        ("必備物品", .packing), ("準備物品", .packing),
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
        - 一行一個欄位，寫成「欄位：內容」。不要用表格、不要用 emoji，時間不要寫在行首。
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
        var startDateText: String?
        var startClockText: String?
        var mode: TripTravelMode = .driving
        var planNotes: [String] = []
        var stops: [TripStop] = []
        var stopDays: [Int] = []
        var arrivalTexts: [UUID: String] = [:]
        /// 「時間：09:30-11:00」的長度（沒寫停留時當停留）
        var rangeDwell: [UUID: Int] = [:]
        var explicitDwell: Set<UUID> = []
        var hints: [UUID: CLLocationCoordinate2D] = [:]
        var packing: [TripChecklistItem] = []
        var souvenirs: [TripChecklistItem] = []
        var warnings: [String] = []

        var day = 1
        var dayMode: TripTravelMode?   // 「第2天」底下、第一站前面寫的交通
        var listMode: Key?             // 正在讀「攜帶」「伴手禮」下面一條一條的
        var current: TripStop?         // 正在讀的那一站

        func flush() {
            guard var s = current else { return }
            current = nil
            s.name = s.name.trimmingCharacters(in: .whitespaces)
            s.note = s.note.trimmingCharacters(in: .whitespacesAndNewlines)
            stops.append(s)
            stopDays.append(day)
        }

        /// 這一天的住宿寫在中間（先 check-in 再去吃晚餐）：搬到當天最後，時間軸才在那裡過夜
        func closeDay() {
            guard let first = stopDays.firstIndex(of: day),
                  let li = stops.indices.last(where: { $0 >= first && stops[$0].isOvernight }),
                  li != stops.count - 1 else { return }
            let lodging = stops.remove(at: li)
            stops.append(lodging)   // first 之後都是同一天，stopDays 不用動
        }

        func addNote(_ text: String) {
            if current != nil {
                current!.note += (current!.note.isEmpty ? "" : "\n") + text
            } else {
                planNotes.append(text)
            }
        }

        let rawLines = raw.components(separatedBy: .newlines)
        // AI 常在程式碼區塊外加開場白、結尾說明：有區塊就只讀區塊裡面
        let fenced = rawLines.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
        var inFence = false

        for rawLine in rawLines {
            if rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inFence.toggle(); continue }
            if fenced && !inFence { continue }
            // 同一行用｜隔開好幾個欄位（「景點：太宰府｜停留：90」）
            let segments = rawLine.contains("｜") || rawLine.contains("|")
                ? rawLine.components(separatedBy: CharacterSet(charactersIn: "｜|"))
                : [rawLine]
            for seg in segments {
                var line = cleanLine(seg)
                if line.isEmpty { continue }

                // 「09:00 景點：…」「12:00-13:00 午餐：…」：前面的時間＝這一站的時間
                var leadTime: String?
                if let r = line.range(of: #"^[0-9]{1,2}[:：][0-9]{2}(\s*[-–—~～至到]\s*[0-9]{1,2}[:：][0-9]{2})?"#,
                                      options: .regularExpression) {
                    let rest = cleanLine(String(line[r.upperBound...]))
                    if let k = splitKey(rest)?.0, k == .stop || k == .lodging {
                        leadTime = String(line[r])
                        line = rest
                    }
                }

                if let n = dayNumber(line) {
                    flush()
                    closeDay()
                    listMode = nil
                    dayMode = nil
                    // 「第1天（12/20 六）」：沒寫出發日期就用這一天
                    if startDateText == nil, stops.isEmpty, hasDatePart(line) { startDateText = line }
                    if n > day, let last = stops.indices.last, stopDays[last] == day, !stops[last].isOvernight {
                        // 換天了，前一天最後一站沒寫住宿：時間軸要在這裡過夜才會換到隔天
                        stops[last].isOvernight = true
                        warnings.append("第\(day)天最後一站「\(stops[last].name)」沒有寫住宿，當成在那裡過夜")
                    }
                    day = max(day, n)
                    continue
                }

                guard let kv = splitKey(line) else {
                    if let k = listHeading(line) { flush(); listMode = k; continue }
                    // 清單底下一條一條的；像一句話（「希望你玩得愉快！」「規劃重點：」）＝清單結束
                    if let k = listMode, !looksLikeSentence(line) {
                        if k == .packing { packing += items(line) } else { souvenirs += items(line) }
                    } else {
                        listMode = nil
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
                    let (name, must) = stripMustMark(value)
                    if isNoPlace(name, lodging: key == .lodging) {
                        planNotes.append("第\(day)天：" + value)
                        continue
                    }
                    let s = TripStop(name: name, dwellMinutes: 60, legModeOverride: dayMode,
                                     isMustVisit: must, isOvernight: key == .lodging)
                    if let lt = leadTime {
                        arrivalTexts[s.id] = lt
                        if let d = rangeMinutes(lt) { rangeDwell[s.id] = d }
                    }
                    current = s
                case .packing, .souvenir:
                    flush()
                    listMode = key
                    if key == .packing { packing += items(value) } else { souvenirs += items(value) }
                case .title:
                    if current == nil && stops.isEmpty && title.isEmpty { title = value } else { addNote(value) }
                case .start:
                    if current == nil && stops.isEmpty {
                        // 「出發日期」「出發時間」分兩行寫；第1天底下再寫一次「日期：」不要蓋掉
                        if hasDatePart(value) {
                            if startDateText == nil { startDateText = value }
                        } else if startClockText == nil, clock(value) != nil {
                            startClockText = value
                        } else {
                            planNotes.append("出發：" + value)
                        }
                    } else {
                        addNote("出發：" + value)
                    }
                case .mode:
                    if let m = travelMode(value) {
                        if current != nil { current!.legModeOverride = m }
                        else if stops.isEmpty && day == 1 { mode = m }
                        else { dayMode = m }
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
                    if current != nil, let m = minutes(value) {
                        current!.dwellMinutes = m
                        explicitDwell.insert(current!.id)
                    }
                case .arrival:
                    if let c = current {
                        arrivalTexts[c.id] = value
                        if let d = rangeMinutes(value) { rangeDwell[c.id] = d }
                    }
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
        closeDay()

        guard !stops.isEmpty || !title.isEmpty || !packing.isEmpty || !souvenirs.isEmpty else { return nil }
        if stops.isEmpty { warnings.append("沒有讀到任何一站（要有「景點：…」）") }

        // 「時間：09:30-11:00」：沒寫停留就用這段的長度
        for i in stops.indices where !explicitDwell.contains(stops[i].id) && !stops[i].isOvernight {
            if let d = rangeDwell[stops[i].id] { stops[i].dwellMinutes = d }
        }

        // 出發時間：沒寫或看不懂就排明天 09:00
        let startParts = [startDateText, startClockText].compactMap { $0 }
        let startText: String? = startParts.isEmpty ? nil : startParts.joined(separator: " ")
        let start: Date
        if let t = startText, let d = date(t, now: now, cal: cal) {
            start = d
        } else {
            let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
            start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
            warnings.append(startText == nil ? "沒有寫出發時間，先排明天 09:00（匯入後可以改）"
                                              : "看不懂出發時間「\(startText ?? "")」，先排明天 09:00（匯入後可以改）")
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
        // 開頭不是字也不是數字的都拿掉：- * • # > 、emoji（📍🏨⏱️📅）、1️⃣、▪、【、(；再拿掉「1.」「1、」「1)」
        while let f = t.first, !(f.isLetter || f.isWholeNumber) {
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
        // 後面要接結尾、空白、括號、冒號、分隔符號：「第1天晚餐建議提早排隊。」不是分天
        if let r = t.range(of: #"^第\s*([0-9０-９一二三四五六七八九十兩]+)\s*[天日](?=$|[\s（(:：\-－–—｜|,，、.。】\]」])"#,
                           options: .regularExpression) {
            let inner = t[r].dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
            return number(String(inner))
        }
        if let r = t.range(of: #"^(?i)(day|d)\s*([0-9]+)\b"#, options: .regularExpression) {
            let digits = t[r].filter(\.isNumber)
            return Int(String(digits))
        }
        return nil
    }

    /// 欄位名稱：只看字（emoji、空白、＊、編號不算：「景點1」「📍景點」），括號後面不看（「景點(必去)」），「…清單」也收
    private static func keyFor(_ rawHead: Substring) -> Key? {
        var head = rawHead
        if let p = head.firstIndex(where: { "（(【[".contains($0) }) { head = head[..<p] }
        var word = String(head.filter { $0.isLetter })
        guard !word.isEmpty else { return nil }
        if let k = keyWords.first(where: { $0.0 == word })?.1 { return k }
        for suffix in ["清單", "列表"] where word.hasSuffix(suffix) { word.removeLast(suffix.count) }
        return keyWords.first(where: { $0.0 == word })?.1
    }

    /// 「欄位：內容」→ 認得的欄位才算（「18:00」的「18」不是字，不算欄位）
    private static func splitKey(_ line: String) -> (Key, String)? {
        guard let idx = line.firstIndex(where: { $0 == "：" || $0 == ":" }),
              line.distance(from: line.startIndex, to: idx) <= 12,
              let key = keyFor(line[..<idx]) else { return nil }
        return (key, line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces))
    }

    /// 沒有冒號的清單標題（「### 🧳 攜帶物品」「伴手禮清單」）
    private static func listHeading(_ line: String) -> Key? {
        guard line.count <= 12, let k = keyFor(line[...]), k == .packing || k == .souvenir else { return nil }
        return k
    }

    /// 像一句話（清單結束了）：很長、有句號驚嘆號問號、冒號結尾（「規劃重點：」）
    private static func looksLikeSentence(_ line: String) -> Bool {
        line.count > 30 || line.hasSuffix("：") || line.hasSuffix(":") || line.contains { "。！？!?".contains($0) }
    }

    /// 「住宿：無（搭晚班機返台）」「住宿：回家」「早餐：飯店內享用」「活動：自由活動」：不是一個地方
    private static func isNoPlace(_ name: String, lodging: Bool) -> Bool {
        let t = name.lowercased()
        if t.isEmpty { return false }
        if t.range(of: #"^(無|沒有|不用|不需要?|免|none|n/?a|[-－—–]+)(?=$|[\s（(，,、。:：]|住宿)"#, options: .regularExpression) != nil {
            return true
        }
        if lodging { return t.range(of: #"^(返|回)(台|家|國)"#, options: .regularExpression) != nil }
        return ["飯店內", "飯店早餐", "飯店享用", "旅館內", "自理", "自由活動", "自由選擇", "自行", "便利商店", "超商"]
            .contains { t.contains($0) }
    }

    /// 「09:30-11:00」→ 90（分）
    static func rangeMinutes(_ v: String) -> Int? {
        let t = v.replacingOccurrences(of: "：", with: ":")
        guard let r = t.range(of: #"[0-9]{1,2}:[0-9]{2}\s*[-–—~～至到]\s*[0-9]{1,2}:[0-9]{2}"#, options: .regularExpression) else { return nil }
        let n = t[r].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard n.count == 4 else { return nil }
        let d = (n[2] * 60 + n[3]) - (n[0] * 60 + n[1])
        return d > 0 ? d : nil
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

    private static let modeWords: [(TripTravelMode, [String])] = [
        (.plane, ["飛機", "航班", "搭機", "plane", "flight", "fly"]),
        (.walking, ["步行", "走路", "徒步", "walk"]),
        (.transit, ["大眾運輸", "電車", "捷運", "地鐵", "地下鐵", "公車", "火車", "列車", "高鐵", "新幹線", "巴士", "客運",
                    "jr", "西鐵", "輕軌", "渡輪", "搭船", "船班", "transit", "train", "bus", "subway", "metro"]),
        (.driving, ["開車", "自駕", "租車", "汽車", "計程車", "car", "drive", "driving", "taxi"]),
    ]

    /// 「電車＋步行」「搭JR後步行」：取最先出現的那一種
    private static func travelMode(_ v: String) -> TripTravelMode? {
        let t = v.lowercased()
        var best: (at: String.Index, mode: TripTravelMode)?
        for (m, words) in modeWords {
            for w in words {
                if let r = t.range(of: w), best == nil || r.lowerBound < best!.at { best = (r.lowerBound, m) }
            }
        }
        return best?.mode
    }

    /// 「90」「90分」「90 分鐘」「1.5小時」「1小時30分」「1小時半」「2h」「30min」
    static func minutes(_ v: String) -> Int? {
        // 括號裡的不算（「約1.5小時（含午餐30分）」）
        let t = v.lowercased()
            .replacingOccurrences(of: #"[（(][^）)]*[）)]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "")
        let digitsOnly = t.filter { $0.isNumber || $0 == "." }
        if !digitsOnly.isEmpty, digitsOnly == t, let n = Double(t) { return max(0, Int(n.rounded())) }
        var total = 0.0
        var matched = false
        if let r = t.range(of: #"[0-9]+(\.[0-9]+)?(?=(小時|鐘頭|個小時|個半|hr|h|時))"#, options: .regularExpression),
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
        // （給家人）(送同事)
        if let r = name.range(of: #"[（(]\s*[給送]\s*([^）)]+)[）)]"#, options: .regularExpression) {
            forWhom = String(name[r]).trimmingCharacters(in: CharacterSet(charactersIn: "（()）給送 "))
            name.removeSubrange(r)
        }
        // ×2 x2 *2「×2盒」「 2盒」
        if let r = name.range(of: #"[×xX*＊]\s*[0-9]+\s*[個盒包份瓶罐組件條袋箱入]?|\s[0-9]+\s*[個盒包份瓶罐組件條袋箱入]"#,
                              options: .regularExpression) {
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
        if Task.isCancelled { return nil }
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
