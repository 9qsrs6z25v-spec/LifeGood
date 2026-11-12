import Foundation

// [v25.620] 水電瓦斯趨勢：資料層（純函式、值型別）。
// - 來源只有一份：HouseCardData.build 裡的帳本列（HouseLedger.events，mark == .utility、不是年列）→ UtilityRows.build。
//   「近 12 個月」、「每個月住這裡」的水電、小圖都讀同一批 rows，不在別的地方再寫一份擁有權規則。
// - 歸表只准問 UtilityMeterSlotIndex.meterOf；卡片表那一列的「最近一期」規則不變，只共用「沒填號碼的主表要不要藏」那條。
// - 這裡不放 Color、不放 View；顏色由 UtilityTrendChart.swift 的 UtilityPalette 照 type／shape 對照
//   （.task(id:) 的 key 沒有深淺色，存了顏色切深色模式不會重算）。
// - 日期差一律用 Calendar 的日曆日；比率只走 UtilityMath.ratio；字典一律 uniquingKeysWith。
// - v1 只有金額；度數、計費期間是 v3（新同步鍵），這一版沒有。

// MARK: - 猜類型

/// [v25.620] 從標題（和備註）猜水電瓦斯是哪一種；猜不到回 nil（趨勢圖不畫、只算進合計）。
/// 本體從 AddExpenseView.swift 的 guessUtilityType 搬過來；記帳表單、AI 記帳仍叫 guessUtilityType（猜不到＝電費，行為不變）。
/// 先把房子名稱、自動標題裡的「水電瓦斯」字樣拿掉（標題和備註都拿），再照「瓦斯 → 電 → 水」的順序找；標題找不到才看備註。
func guessUtilityTypeIfAny(title: String, note: String = "", estateName: String) -> UtilityType? {
    func match(_ text: String) -> UtilityType? {
        let lower = text.lowercased()
        let gasWords = ["瓦斯", "天然氣", "gas"]
        let electricWords = ["電", "台電", "electric"]
        let waterWords = ["水費", "自來水", "台水", "水", "water"]
        if gasWords.contains(where: { lower.contains($0) }) { return .gas }
        if electricWords.contains(where: { lower.contains($0) }) { return .electricity }
        if waterWords.contains(where: { lower.contains($0) }) { return .water }
        return nil
    }
    var cleaned = title
    let name = estateName.trimmingCharacters(in: .whitespaces)
    // 新增物件沒填名稱時，房子名稱就是拿標題當的；整段拿掉就什麼都不剩，這時不拿
    if !name.isEmpty && name != title.trimmingCharacters(in: .whitespaces) {
        cleaned = cleaned.replacingOccurrences(of: name, with: " ")
    }
    cleaned = cleaned.replacingOccurrences(of: RealEstateExpenseCategory.utility.rawValue, with: " ")
    // 備註常會打房子名稱（「水岸花園 9月」），所以備註也一樣清；備註不會被拿去當房子名稱，不需要上面那個例外
    var cleanedNote = note
    if !name.isEmpty {
        cleanedNote = cleanedNote.replacingOccurrences(of: name, with: " ")
    }
    cleanedNote = cleanedNote.replacingOccurrences(of: RealEstateExpenseCategory.utility.rawValue, with: " ")
    return match(cleaned) ?? match(cleanedNote)
}

// MARK: - 數學

enum UtilityMath {
    /// a ÷ b；b 要 > 0、結果要是有限數，不然 nil（N3）
    static func ratio(_ a: Double, _ b: Double) -> Double? {
        guard a.isFinite, b.isFinite, b > 0 else { return nil }
        let r: Double = a / b
        return r.isFinite ? r : nil
    }

    /// 變化百分比的整數（四捨五入、取絕對值）：800 對 670 → 19；455 對 520 → 13。算不出 nil
    static func percentMagnitude(_ a: Double, vs b: Double) -> Int? {
        guard let r = ratio(a, b) else { return nil }
        let pct: Double = (abs(r - 1) * 100).rounded()
        guard pct.isFinite, pct < 1_000_000 else { return nil }
        return Int(pct)
    }

    /// 兩個日期差幾個日曆日（b − a；用 Calendar，不用秒數 ÷ 86400）
    static func days(_ a: Date, _ b: Date, cal: Calendar) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? 0
    }

    /// 一串排好的繳費日的「週期」：間隔中位數在 25～35 或 50～70 天就用它，否則 30 天
    static func cycleDays(_ dates: [Date], cal: Calendar) -> Int {
        guard dates.count >= 2 else { return 30 }
        var gaps: [Int] = []
        for i in 1..<dates.count {
            let g = days(dates[i - 1], dates[i], cal: cal)
            if g > 0 { gaps.append(g) }
        }
        guard !gaps.isEmpty else { return 30 }
        let sorted = gaps.sorted()
        let mid = sorted.count / 2
        let median: Int = sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
        if (25...35).contains(median) || (50...70).contains(median) { return median }
        return 30
    }

    /// 這一期（繳費日往前一個週期：[繳費日 − 週期, 繳費日 − 1]）有超過一半的天落在 6–9 月
    static func summerDominant(paidOn d: Date, cycle: Int, cal: Calendar) -> Bool {
        let n = min(max(cycle, 1), 186)
        guard let start = cal.date(byAdding: .day, value: -n, to: cal.startOfDay(for: d)) else { return false }
        var summer = 0
        for i in 0..<n {
            guard let day = cal.date(byAdding: .day, value: i, to: start) else { continue }
            let m = cal.component(.month, from: day)
            if m >= 6 && m <= 9 { summer += 1 }
        }
        return summer * 2 > n
    }
}

// MARK: - 歸表

/// 歸到哪個表：assigned＝確定是這個表；id == nil 且 assigned == false＝沒指定（同種有 2 個以上的表、meterId 是 nil 或對不上）
struct UtilityMeterAssignment: Equatable {
    let id: String?
    let assigned: Bool

    static let unassigned = UtilityMeterAssignment(id: nil, assigned: false)
}

/// 一間房子的表（RealEstate.utilityMeterSlots），建一次、查 O(1)。卡片和趨勢共用。
struct UtilityMeterSlotIndex {
    /// 全部的格（主表在前、額外的表接後面），跟 RealEstate.utilityMeterSlots 同順序
    let slots: [UtilityMeterSlot]
    /// 趨勢用的表：拿掉「沒填號碼的主表、同種還有別的表」那種（卡片也不畫它）
    let trendSlots: [UtilityMeterSlot]
    private let allIds: Set<String>
    private let trendById: [String: UtilityMeterSlot]
    /// 同一種只有一個趨勢用的表時，那個表的 id
    private let onlyByType: [UtilityType: String]
    /// 表在 trendSlots 裡的順序（圖例、點形排序用）
    private let orderById: [String: Int]

    init(_ slots: [UtilityMeterSlot]) {
        self.slots = slots
        let kept: [UtilityMeterSlot] = slots.filter { !UtilityMeterSlotIndex.hidesMain($0, in: slots) }
        self.trendSlots = kept
        self.allIds = Set(slots.map(\.id))
        self.trendById = Dictionary(kept.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var count: [UtilityType: Int] = [:]
        var first: [UtilityType: String] = [:]
        for s in kept {
            count[s.type, default: 0] += 1
            if first[s.type] == nil { first[s.type] = s.id }
        }
        var only: [UtilityType: String] = [:]
        for (t, n) in count where n == 1 {
            if let id = first[t] { only[t] = id }
        }
        self.onlyByType = only
        var order: [String: Int] = [:]
        for (i, s) in kept.enumerated() where order[s.id] == nil { order[s.id] = i }
        self.orderById = order
    }

    static let empty = UtilityMeterSlotIndex([])

    /// 沒填號碼的主表、同一種還有別的表：卡片不畫這一列、趨勢也不算它（HouseCardData 卡片的表那幾列共用這條）
    static func hidesMain(_ slot: UtilityMeterSlot, in slots: [UtilityMeterSlot]) -> Bool {
        guard slot.isMain && slot.number.isEmpty else { return false }
        return slots.contains { $0.type == slot.type && $0.id != slot.id }
    }

    /// meterId 是不是現在任何一格（卡片「最近一期」照舊用這個判斷，結果不變）
    func contains(_ id: String) -> Bool { allIds.contains(id) }

    func slot(_ id: String) -> UtilityMeterSlot? { trendById[id] }

    func order(of id: String) -> Int { orderById[id] ?? Int.max }

    /// 趨勢歸表：meterId 是這一種現在的表 → 那個表；這一種只有 1 個表 → 那個表（nil 也算）；其他 → 沒指定。
    /// 不用 enum 字串插值當 key（主表的 id 是 utilityMeterSlots 給的「main-electricity」）
    func meterOf(_ p: UtilityPayment?, type: UtilityType?) -> UtilityMeterAssignment {
        guard let t = type else { return .unassigned }
        if let mid = p?.meterId, let s = trendById[mid], s.type == t {
            return UtilityMeterAssignment(id: mid, assigned: true)
        }
        if let only = onlyByType[t] {
            return UtilityMeterAssignment(id: only, assigned: true)
        }
        return .unassigned
    }

    /// 圖例上的表名：「客廳」；沒取名寫「電號 21-40-0218-50-1」；號碼也沒填寫「電費（沒填電號）」
    func displayName(_ id: String) -> String {
        guard let s = trendById[id] else { return "" }
        if !s.name.isEmpty { return s.name }
        let label = UtilityMeterSlotIndex.numberLabel(s.type)
        if !s.number.isEmpty { return "\(label) \(s.number)" }
        return "\(s.type.rawValue)（沒填\(label)）"
    }

    static func numberLabel(_ t: UtilityType) -> String {
        switch t {
        case .water: return "水號"
        case .electricity: return "電號"
        case .gas: return "瓦斯表號"
        }
    }
}

// MARK: - 一列（帳本裡的一筆水電）

/// 趨勢的一期。值型別、不放 Color。
struct UtilityRow: Equatable {
    /// 帳本列 id（「u-」「l-util-」「e-」…），一間房子裡唯一
    let key: String
    /// 水／電／瓦斯；只在記帳、猜不到是哪一種的（S4b）是 nil：只算進合計、不畫
    let type: UtilityType?
    /// 歸到哪個表（meterOf）；沒指定是 nil
    let meterId: String?
    let meterAssigned: Bool
    /// 帳本列的日期：有連記帳的＝記帳那筆的日期；沒連（或連的找不到）＝繳費日
    let date: Date
    /// 帳本列的台幣金額
    let amount: Double
    /// 房子水電那一期的 id（S1–S3）；只在記帳的是 nil
    let paymentId: UUID?
    /// 記帳那筆的 id；沒連到記帳的是 nil
    let expenseId: UUID?
    let photoCount: Int
    /// 只在記帳記的（S4）：點的說明句尾加「（記帳裡的）」
    let fromExpenseOnly: Bool
}

/// 一間房子的全部水電列（舊到新），HouseCardData.build 算一次
struct UtilityRowSet: Equatable {
    /// 照日期舊到新；同一天：房子水電陣列裡的順序在前，只在記帳的照 key 排
    var rows: [UtilityRow] = []
    /// 連到的記帳已經改連別間房子（M2）：帳本還看得到，但不算進這間的水電
    var otherEstateCount = 0
    /// 只在記帳、猜不到是水電瓦斯哪一種（S4b）：算進合計、不畫
    var untypedCount = 0

    static let empty = UtilityRowSet()

    /// 近 12 個月合計：日期在 asOf 往前 12 個月內（rows 本來就都在 asOf 以前）
    func total12m(asOf: Date, cal: Calendar) -> Double {
        let back: Date = cal.startOfDay(for: cal.date(byAdding: .month, value: -12, to: asOf) ?? asOf)
        var total = 0.0
        for r in rows where cal.startOfDay(for: r.date) >= back {
            total += r.amount
        }
        return total
    }
}

enum UtilityRows {
    /// 帳本列 → 水電列。events 是 HouseLedger.events（已經 onOrBeforeAsOf、已經用支出 id 去重、擁有者先掛到的贏）。
    /// - S1 `.utility(pid)`：有連記帳、找得到；S2／S3 `.legacy(.utility, pid)`：沒連、或連的找不到（同 id 只一列）
    /// - S4 其他 mark == .utility 的列（只在記帳、或變動支出分類是水電瓦斯）：類型用 guessUtilityTypeIfAny 猜
    /// - 連到的記帳 linkedRealEstateId 是別間（M2）：不算
    /// - 固定支出年列（S5、M1）本來就不是 .utility 的非年列，不在這裡
    static func build(estate re: RealEstate, events: [HouseLedgerEvent], expensesById: [UUID: Expense],
                      slots: UtilityMeterSlotIndex) -> UtilityRowSet {
        let payments: [UUID: UtilityPayment] = Dictionary(re.utilityPayments.map { ($0.id, $0) },
                                                           uniquingKeysWith: { a, _ in a })
        var orderOf: [UUID: Int] = [:]
        for (i, p) in re.utilityPayments.enumerated() where orderOf[p.id] == nil { orderOf[p.id] = i }
        let variables: [UUID: RealEstateVariableExpense] = Dictionary(re.variableExpenses.map { ($0.id, $0) },
                                                                      uniquingKeysWith: { a, _ in a })
        var result = UtilityRowSet()
        var out: [(row: UtilityRow, order: Int)] = []
        var seenKeys = Set<String>()
        for e in events where e.mark == .utility && !e.isYearRow {
            guard seenKeys.insert(e.id).inserted else { continue }
            if let eid = e.expenseId, let ex = expensesById[eid],
               let linked = ex.linkedRealEstateId, linked != re.id {
                result.otherEstateCount += 1
                continue
            }
            var payment: UtilityPayment? = nil
            var guessed: UtilityType? = nil
            var fromExpenseOnly = false
            switch e.source {
            case .utility(let pid):
                payment = payments[pid]
            case .legacy(let kind, let id):
                if kind == .utility {
                    payment = payments[id]
                } else if kind == .variable, let v = variables[id] {
                    guessed = guessUtilityTypeIfAny(title: v.name, note: "", estateName: re.name)
                } else {
                    guessed = guessUtilityTypeIfAny(title: e.title, note: "", estateName: re.name)
                }
            case .expense(let eid):
                fromExpenseOnly = true
                if let ex = expensesById[eid] {
                    guessed = guessUtilityTypeIfAny(title: ex.title, note: ex.note, estateName: re.name)
                } else {
                    guessed = guessUtilityTypeIfAny(title: e.title, note: "", estateName: re.name)
                }
            default:
                guessed = guessUtilityTypeIfAny(title: e.title, note: "", estateName: re.name)
            }
            let type: UtilityType? = payment?.type ?? guessed
            if type == nil { result.untypedCount += 1 }
            let meter: UtilityMeterAssignment = slots.meterOf(payment, type: type)
            let row = UtilityRow(key: e.id, type: type, meterId: meter.id, meterAssigned: meter.assigned,
                                 date: e.date, amount: e.amount, paymentId: payment?.id, expenseId: e.expenseId,
                                 photoCount: e.photoCount, fromExpenseOnly: fromExpenseOnly)
            let order: Int = payment.flatMap { orderOf[$0.id] } ?? Int.max
            out.append((row: row, order: order))
        }
        out.sort { (a: (row: UtilityRow, order: Int), b: (row: UtilityRow, order: Int)) -> Bool in
            if a.row.date != b.row.date { return a.row.date < b.row.date }
            if a.order != b.order { return a.order < b.order }
            return a.row.key < b.row.key
        }
        result.rows = out.map { $0.row }
        return result
    }
}

// MARK: - 圖的資料

enum UtilityTrendShape: Equatable {
    case circle, triangle, square
}

/// 圖上的一點（Data 攤平成一層；顏色由畫面照 type 對照）
struct UtilityTrendPoint: Identifiable, Equatable {
    /// ＝UtilityRow.key
    let key: String
    /// 金額模式＝繳費日（帳本列日期）
    let x: Date
    let y: Double
    /// 「<表 id>#<段>」；沒指定表的每點自己一個 series（不連線）
    let seriesId: String
    let type: UtilityType
    let shape: UtilityTrendShape
    /// false＝沒指定是哪個表：灰色小點
    let assigned: Bool
    /// 空心點只給 v4 的帳單標記；v1 一律 false
    let hollow: Bool
    /// 點太多時只畫最近的（v2「全部」範圍才會用到）；v1 一律 true
    let visible: Bool

    var id: String { key }
}

/// 圖例一項
struct UtilityLegendEntry: Identifiable, Equatable {
    enum Mark: Equatable {
        /// 一個表：同色，點形不同
        case dot(UtilityTrendShape)
        /// 沒指定是哪個表：灰點
        case unassigned
        /// 每期平均：虛線
        case average
    }
    let id: String
    let mark: Mark
    let text: String
}

/// 圖例一排（最多 2 項，Data 先分好，畫面不用算寬度）
struct UtilityLegendRow: Identifiable, Equatable {
    let id: Int
    let entries: [UtilityLegendEntry]
}

/// 一張圖（小圖、v2 全頁共用）。保證：至少 2 點、domain 合法（N6）
struct UtilityTrendChartData: Equatable {
    let type: UtilityType
    /// 全部的點（含灰點），照 x 舊到新
    let points: [UtilityTrendPoint]
    /// 要連線的點：只放 2 點以上的段（只有一點的段只畫點）
    let lines: [UtilityTrendPoint]
    /// 每期平均（畫的那個量 ≥ 4 點才有；沒指定表的不算）
    let average: Double?
    let xDomain: ClosedRange<Date>
    let yDomain: ClosedRange<Double>
    /// 換種類、資料變了就換（圖外殼 .id 用，順便清掉手指位置）
    let identity: String
    /// VoiceOver 唸的一句
    let accessibilityText: String
    /// 照 x 排好的點（找最近一點用，O(log n)）
    private let pickXs: [Date]
    private let pickKeys: [String]
    private let xByKey: [String: Date]

    init(type: UtilityType, points: [UtilityTrendPoint], lines: [UtilityTrendPoint], average: Double?,
         xDomain: ClosedRange<Date>, yDomain: ClosedRange<Double>, identity: String, accessibilityText: String) {
        self.type = type
        self.points = points
        self.lines = lines
        self.average = average
        self.xDomain = xDomain
        self.yDomain = yDomain
        self.identity = identity
        self.accessibilityText = accessibilityText
        let sorted: [UtilityTrendPoint] = points.sorted { (a: UtilityTrendPoint, b: UtilityTrendPoint) -> Bool in
            a.x != b.x ? a.x < b.x : a.key < b.key
        }
        self.pickXs = sorted.map(\.x)
        self.pickKeys = sorted.map(\.key)
        self.xByKey = Dictionary(points.map { ($0.key, $0.x) }, uniquingKeysWith: { a, _ in a })
    }

    /// 手指按到的日期最近的那一點（二分搜尋）
    func nearestKey(to d: Date) -> String? {
        guard !pickXs.isEmpty else { return nil }
        var lo = 0
        var hi = pickXs.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if pickXs[mid] < d { lo = mid + 1 } else { hi = mid }
        }
        if lo == 0 { return pickKeys[0] }
        if lo >= pickXs.count { return pickKeys[pickXs.count - 1] }
        let before: Double = abs(d.timeIntervalSince(pickXs[lo - 1]))
        let after: Double = abs(pickXs[lo].timeIntervalSince(d))
        return after < before ? pickKeys[lo] : pickKeys[lo - 1]
    }

    /// 選到的那一點的 x；查不到（已經刪了）nil
    func x(of key: String?) -> Date? {
        guard let key else { return nil }
        return xByKey[key]
    }
}

/// 小圖區塊裡一種（電費／水費／瓦斯費）
struct UtilityTrendPanel: Equatable {
    let type: UtilityType
    /// 右上角「每期多少錢・近 2 年」
    let title: String
    /// 不到 2 點時 nil（寫 pending）
    let chart: UtilityTrendChartData?
    /// 只有 1 期：「記了 1 期水費（11/5 NT$455），再記 1 期就畫出變化」
    let pending: String?
    /// 只有 1 期的第二行：「手邊有舊帳單或繳費紀錄，可以補記前幾期（右上角 ＋）」
    let pendingHint: String?
    let legend: [UtilityLegendRow]
    /// 超過 3 個表：「還有 1 個表沒畫」
    let hiddenMeterNote: String?
    /// 沒點時的說明行：「11/10 那期比去年同期多 19%」
    let defaultCaption: String
    /// 點到一點時的說明行（key → 那句）
    let pickedCaptions: [String: String]

    /// 說明行：查得到點的那句，查不到（沒點、或點的那期刪了）用沒點時那句
    func caption(for key: String?) -> String {
        guard let key, let s = pickedCaptions[key] else { return defaultCaption }
        return s
    }
}

/// 「水電瓦斯」白卡最上面的小圖區塊
struct UtilityTrendBoard: Equatable {
    /// 近 2 年有 ≥ 1 期的種類，電 → 水 → 瓦斯
    let kinds: [UtilityType]
    /// 第一次打開預設：最近一筆繳費的種類
    let defaultKind: UtilityType
    let panels: [UtilityType: UtilityTrendPanel]

    /// 要畫哪一種：上次看的那一種還在就用它，不然用預設
    func resolvedKind(_ remembered: UtilityType?) -> UtilityType {
        if let r = remembered, kinds.contains(r) { return r }
        return defaultKind
    }

    func panel(for remembered: UtilityType?) -> UtilityTrendPanel? {
        panels[resolvedKind(remembered)]
    }
}

// MARK: - 算圖

enum UtilityTrendBuild {
    static let rangeMonths = 24
    static let maxPointsPerMeter = 24
    static let maxMeters = 3
    static let order: [UtilityType] = [.electricity, .water, .gas]

    /// 小圖區塊；近 2 年一期都沒有（或只有猜不到類型的）時 nil
    static func board(_ set: UtilityRowSet, slots: UtilityMeterSlotIndex, asOf: Date, cal: Calendar) -> UtilityTrendBoard? {
        let start: Date = cal.startOfDay(for: cal.date(byAdding: .month, value: -rangeMonths, to: asOf) ?? asOf)
        let inRange: [UtilityRow] = set.rows.filter { r in r.type != nil && cal.startOfDay(for: r.date) >= start }
        guard let latest = inRange.last, let latestType = latest.type else { return nil }
        var kinds: [UtilityType] = []
        var panels: [UtilityType: UtilityTrendPanel] = [:]
        for t in order {
            let mine: [UtilityRow] = inRange.filter { $0.type == t }
            guard !mine.isEmpty else { continue }
            let history: [UtilityRow] = set.rows.filter { $0.type == t }
            kinds.append(t)
            panels[t] = panel(t, rows: mine, history: history, slots: slots, asOf: asOf, cal: cal)
        }
        return UtilityTrendBoard(kinds: kinds, defaultKind: latestType, panels: panels)
    }

    /// 一種的圖、圖例、說明行。rows＝近 2 年這一種（舊到新）；history＝這一種全部（配對去年同期用）
    static func panel(_ t: UtilityType, rows: [UtilityRow], history: [UtilityRow], slots: UtilityMeterSlotIndex,
                      asOf: Date, cal: Calendar) -> UtilityTrendPanel {
        let title = "每期多少錢・近 2 年"
        // 表：期數多的優先，一樣多照表的順序；最多畫 3 個
        var byMeter: [String: [UtilityRow]] = [:]
        var unassigned: [UtilityRow] = []
        for r in rows {
            if r.meterAssigned, let mid = r.meterId {
                byMeter[mid, default: []].append(r)
            } else {
                unassigned.append(r)
            }
        }
        let meterIds: [String] = byMeter.keys.sorted { (a: String, b: String) -> Bool in
            let na = byMeter[a]?.count ?? 0
            let nb = byMeter[b]?.count ?? 0
            if na != nb { return na > nb }
            let oa = slots.order(of: a)
            let ob = slots.order(of: b)
            return oa != ob ? oa < ob : a < b
        }
        let drawn: [String] = Array(meterIds.prefix(maxMeters))
        let hiddenCount: Int = meterIds.count - drawn.count
        let multi: Bool = drawn.count >= 2
        let shapes: [UtilityTrendShape] = [.circle, .triangle, .square]

        // 每個表全部的歷史（配對去年同期、上一期用）
        var historyByMeter: [String: [UtilityRow]] = [:]
        for r in history where r.meterAssigned {
            if let mid = r.meterId { historyByMeter[mid, default: []].append(r) }
        }

        var points: [UtilityTrendPoint] = []
        var lines: [UtilityTrendPoint] = []
        var picked: [String: String] = [:]
        var assignedYs: [Double] = []
        var latestAssigned: (row: UtilityRow, meter: String)? = nil
        var primaryCycle = 30
        for (i, mid) in drawn.enumerated() {
            let mine: [UtilityRow] = Array((byMeter[mid] ?? []).suffix(maxPointsPerMeter))
            let past: [UtilityRow] = historyByMeter[mid] ?? mine
            let cycle: Int = UtilityMath.cycleDays(past.map(\.date), cal: cal)
            if i == 0 { primaryCycle = cycle }
            let shape: UtilityTrendShape = shapes[min(i, shapes.count - 1)]
            let segs: [UtilityTrendPoint] = segmented(mine, meterId: mid, type: t, shape: shape)
            points += segs
            lines += lineOnly(segs)
            assignedYs += mine.map(\.amount)
            let name: String? = multi ? slots.displayName(mid) : nil
            let indexOf: [String: Int] = indexByKey(past)
            for r in mine {
                let c: String? = indexOf[r.key].flatMap { comparison(at: $0, in: past, type: t, cycle: cycle, cal: cal) }
                picked[r.key] = pickedCaption(r, comparison: c, meterName: name, asOf: asOf)
            }
            if let last = mine.last {
                if let cur = latestAssigned {
                    if last.date > cur.row.date { latestAssigned = (row: last, meter: mid) }
                } else {
                    latestAssigned = (row: last, meter: mid)
                }
            }
        }
        let grays: [UtilityRow] = Array(unassigned.suffix(maxPointsPerMeter))
        for r in grays {
            points.append(UtilityTrendPoint(key: r.key, x: r.date, y: r.amount, seriesId: "none#" + r.key, type: t,
                                            shape: .circle, assigned: false, hollow: false, visible: true))
            picked[r.key] = "\(dateText(r.date, asOf: asOf)) 繳 \(MoneyFormat.short(r.amount))（沒指定是哪個表）"
        }
        points.sort { (a: UtilityTrendPoint, b: UtilityTrendPoint) -> Bool in a.x != b.x ? a.x < b.x : a.key < b.key }

        let average: Double? = assignedYs.count >= 4 ? assignedYs.reduce(0, +) / Double(assignedYs.count) : nil

        // 圖例
        var entries: [UtilityLegendEntry] = []
        if multi {
            for (i, mid) in drawn.enumerated() {
                entries.append(UtilityLegendEntry(id: "m-" + mid, mark: .dot(shapes[min(i, shapes.count - 1)]),
                                                  text: slots.displayName(mid)))
            }
        }
        if !grays.isEmpty {
            entries.append(UtilityLegendEntry(id: "none", mark: .unassigned, text: "沒指定是哪個表（\(grays.count) 期）"))
        }
        if average != nil {
            entries.append(UtilityLegendEntry(id: "avg", mark: .average, text: "每期平均"))
        }
        var legend: [UtilityLegendRow] = []
        var i = 0
        while i < entries.count {
            let chunk: [UtilityLegendEntry] = Array(entries[i..<min(i + 2, entries.count)])
            legend.append(UtilityLegendRow(id: legend.count, entries: chunk))
            i += 2
        }
        let hiddenNote: String? = hiddenCount > 0 ? "還有 \(hiddenCount) 個表沒畫" : nil

        // 說明行（沒點時）：最近一期（有指定表的）的比較；比不了就寫那期繳多少
        var caption = ""
        var latestComparison: String? = nil
        if let la = latestAssigned {
            let past: [UtilityRow] = historyByMeter[la.meter] ?? []
            let cycle: Int = UtilityMath.cycleDays(past.map(\.date), cal: cal)
            latestComparison = indexByKey(past)[la.row.key].flatMap { comparison(at: $0, in: past, type: t, cycle: cycle, cal: cal) }
            let head: String = multi ? "\(slots.displayName(la.meter))：" : ""
            let d: String = dateText(la.row.date, asOf: asOf)
            if let c = latestComparison {
                caption = "\(head)\(d) 那期\(c)"
            } else {
                caption = "\(head)\(d) 繳 \(MoneyFormat.short(la.row.amount))"
            }
        } else if let g = grays.last {
            caption = "\(dateText(g.date, asOf: asOf)) 繳 \(MoneyFormat.short(g.amount))"
        }

        // 只有 1 點：不畫圖，寫 pending
        guard points.count >= 2 else {
            var pending: String? = nil
            var hint: String? = nil
            if let only = rows.last {
                pending = "記了 1 期\(t.rawValue)（\(dateText(only.date, asOf: asOf)) \(MoneyFormat.short(only.amount))），再記 1 期就畫出變化"
                hint = "手邊有舊帳單或繳費紀錄，可以補記前幾期（右上角 ＋）"
            }
            return UtilityTrendPanel(type: t, title: title, chart: nil, pending: pending, pendingHint: hint,
                                     legend: [], hiddenMeterNote: nil, defaultCaption: caption, pickedCaptions: [:])
        }

        let chart = UtilityTrendChartData(
            type: t, points: points, lines: lines, average: average,
            xDomain: xDomain(points, cycle: primaryCycle, cal: cal),
            yDomain: yDomain(points, average: average),
            identity: identity(t, points: points),
            accessibilityText: spoken(t, points: points, comparison: latestComparison))
        return UtilityTrendPanel(type: t, title: title, chart: chart, pending: nil, pendingHint: nil,
                                 legend: legend, hiddenMeterNote: hiddenNote, defaultCaption: caption, pickedCaptions: picked)
    }

    /// 一個表的點：照順序；x 往回走就斷成新的一段（金額模式 x＝繳費日，不會往回走）
    static func segmented(_ rows: [UtilityRow], meterId: String, type: UtilityType,
                          shape: UtilityTrendShape) -> [UtilityTrendPoint] {
        var out: [UtilityTrendPoint] = []
        var seg = 0
        var lastX: Date? = nil
        for r in rows {
            if let lx = lastX, r.date < lx { seg += 1 }
            lastX = r.date
            out.append(UtilityTrendPoint(key: r.key, x: r.date, y: r.amount, seriesId: "\(meterId)#\(seg)", type: type,
                                         shape: shape, assigned: true, hollow: false, visible: true))
        }
        return out
    }

    /// key → 在陣列裡的位置（同一個 key 留第一個）
    static func indexByKey(_ rows: [UtilityRow]) -> [String: Int] {
        var out: [String: Int] = [:]
        for (i, r) in rows.enumerated() where out[r.key] == nil { out[r.key] = i }
        return out
    }

    /// 只留 2 點以上的段（只有一點的段只畫點、不畫線）
    static func lineOnly(_ pts: [UtilityTrendPoint]) -> [UtilityTrendPoint] {
        var count: [String: Int] = [:]
        for p in pts { count[p.seriesId, default: 0] += 1 }
        return pts.filter { (count[$0.seriesId] ?? 0) >= 2 }
    }

    /// 跟誰比：有去年同期 → 比去年同期；沒有 → 比上一期；都沒有 nil。比較一律中性字、不加箭頭。
    /// meterRows＝同一個表全部（舊到新），idx＝這一期在裡面的位置。只比金額（v1 沒有度數）
    static func comparison(at idx: Int, in meterRows: [UtilityRow], type: UtilityType, cycle: Int, cal: Calendar) -> String? {
        guard idx >= 0, idx < meterRows.count else { return nil }
        let r: UtilityRow = meterRows[idx]
        if let ly = lastYear(of: idx, in: meterRows, cycle: cycle, cal: cal),
           let pct = UtilityMath.percentMagnitude(r.amount, vs: ly.amount) {
            if pct == 0 { return "跟去年同期差不多" }
            return r.amount > ly.amount ? "比去年同期多 \(pct)%" : "比去年同期少 \(pct)%"
        }
        guard idx > 0 else { return nil }
        let prev: UtilityRow = meterRows[idx - 1]
        guard let pct = UtilityMath.percentMagnitude(r.amount, vs: prev.amount) else { return nil }
        var s: String
        if pct == 0 {
            s = "跟上一期差不多"
        } else {
            let diff: Double = abs(r.amount - prev.amount)
            let money: String = MoneyFormat.short(diff)
            s = r.amount > prev.amount ? "比上一期多 \(money)（+\(pct)%）" : "比上一期少 \(money)（−\(pct)%）"
        }
        if type == .electricity {
            let a: Bool = UtilityMath.summerDominant(paidOn: r.date, cycle: cycle, cal: cal)
            let b: Bool = UtilityMath.summerDominant(paidOn: prev.date, cycle: cycle, cal: cal)
            // 一期夏月為主、一期不是，而且夏月那期比較高，才補這半句（不拿夏天解釋非夏月變高）
            let summerHigher: Bool = (a && !b && r.amount > prev.amount) || (b && !a && prev.amount > r.amount)
            if summerHigher { s += "，夏天（6–9 月）本來就比較高" }
        }
        return s
    }

    /// 去年同期（v1 沒有計費期間）：同一個表裡，繳費日最接近「這期繳費日 −1 年」、差 ≤ 半個週期、比這期早的那一期。
    /// 用 Calendar 減一年（不用 365 天）；只看目標前後 3 期
    static func lastYear(of idx: Int, in rows: [UtilityRow], cycle: Int, cal: Calendar) -> UtilityRow? {
        let r = rows[idx]
        guard let target = cal.date(byAdding: .year, value: -1, to: r.date) else { return nil }
        var lo = 0
        var hi = idx
        while lo < hi {
            let mid = (lo + hi) / 2
            if rows[mid].date < target { lo = mid + 1 } else { hi = mid }
        }
        let from = max(0, lo - 3)
        let to = min(idx - 1, lo + 3)
        guard from <= to else { return nil }
        var best: UtilityRow? = nil
        var bestGap = Int.max
        for j in from...to {
            let gap: Int = abs(UtilityMath.days(target, rows[j].date, cal: cal))
            if gap < bestGap {
                bestGap = gap
                best = rows[j]
            }
        }
        guard let b = best, Double(bestGap) * 2 <= Double(cycle) else { return nil }
        return b
    }

    /// 點到一點：「9/20 繳 NT$1,590，比去年同期多 15%」；只在記帳的句尾「（記帳裡的）」；多個表時前面加表名
    static func pickedCaption(_ r: UtilityRow, comparison: String?, meterName: String?, asOf: Date) -> String {
        var s = "\(dateText(r.date, asOf: asOf)) 繳 \(MoneyFormat.short(r.amount))"
        if let c = comparison { s += "，" + c }
        if r.fromExpenseOnly { s += "（記帳裡的）" }
        if let n = meterName, !n.isEmpty { s = "\(n)：" + s }
        return s
    }

    /// 今年寫「9/20」，往年寫「2025/11/10」
    static func dateText(_ d: Date, asOf: Date) -> String {
        HouseCardFormat.shortDate(d, now: asOf)
    }

    /// x：最早到最新，左右各留半個週期（至少 15 天）；只有一個日期也一樣補（N6）
    static func xDomain(_ points: [UtilityTrendPoint], cycle: Int, cal: Calendar) -> ClosedRange<Date> {
        let xs: [Date] = points.map(\.x)
        let lo0: Date = xs.min() ?? Date()
        let hi0: Date = xs.max() ?? lo0
        let pad: Int = max(15, cycle / 2)
        let lo: Date = cal.date(byAdding: .day, value: -pad, to: lo0) ?? lo0.addingTimeInterval(-1_296_000)
        let hiRaw: Date = cal.date(byAdding: .day, value: pad, to: hi0) ?? hi0.addingTimeInterval(1_296_000)
        let hi: Date = hiRaw > lo ? hiRaw : lo.addingTimeInterval(1_296_000)
        return lo...hi
    }

    /// y：從 0 起，上面留兩成（照 VehicleChargeChart）
    static func yDomain(_ points: [UtilityTrendPoint], average: Double?) -> ClosedRange<Double> {
        let ys: [Double] = points.map(\.y).filter { $0.isFinite }
        let hi: Double = max(ys.max() ?? 0, average ?? 0, 1)
        let top: Double = hi * 1.2
        return 0...(top.isFinite ? top : 1)
    }

    static func identity(_ t: UtilityType, points: [UtilityTrendPoint]) -> String {
        let first: String = points.first?.key ?? ""
        let last: String = points.last?.key ?? ""
        return "\(t.rawValue)-\(points.count)-\(first)-\(last)"
    }

    /// 「電費近 2 年 8 期，每期 NT$540 到 NT$1,590，最近一期比去年同期多 19%」
    static func spoken(_ t: UtilityType, points: [UtilityTrendPoint], comparison: String?) -> String {
        let ys: [Double] = points.map(\.y)
        let lo: Double = ys.min() ?? 0
        let hi: Double = ys.max() ?? 0
        var s = "\(t.rawValue)近 2 年 \(points.count) 期，每期 \(MoneyFormat.short(lo)) 到 \(MoneyFormat.short(hi))"
        if let c = comparison { s += "，最近一期" + c }
        return s
    }
}
