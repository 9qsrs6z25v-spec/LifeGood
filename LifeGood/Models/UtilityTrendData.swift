import Foundation

// [v25.620] 水電瓦斯趨勢：資料層（純函式、值型別）。
// - 來源只有一份：HouseCardData.build 裡的帳本列（HouseLedger.events，mark == .utility、不是年列）→ UtilityRows.build。
//   「近 12 個月」、「每個月住這裡」的水電、小圖都讀同一批 rows，不在別的地方再寫一份擁有權規則。
// - 歸表只准問 UtilityMeterSlotIndex.meterOf；卡片表那一列的「最近一期」規則不變，只共用「沒填號碼的主表要不要藏」那條。
// - 這裡不放 Color、不放 View；顏色由 UtilityTrendChart.swift 的 UtilityPalette 照 type／shape 對照
//   （.task(id:) 的 key 沒有深淺色，存了顏色切深色模式不會重算）。
// - 日期差一律用 Calendar 的日曆日；比率只走 UtilityMath.ratio；字典一律 uniquingKeysWith。
// - v1 只有金額；度數、計費期間是 v3（新同步鍵），這一版沒有。
// - [v25.621] v2 全頁「水電趨勢」：UtilityTrendSource 在 HouseCardData.build 算一次（全頁不重跑帳本），
//   UtilityTrendPage.build 在全頁的 .task／換選擇時算好 UtilityTrendScreen，body 只讀。還是只有金額。

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
/// [v25.621] Equatable：放進 UtilityRowSet（build 只建一次，水電區卡片的表那幾列也讀 rows.slots）
struct UtilityMeterSlotIndex: Equatable {
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
    /// [v25.621] M2 那幾筆連到的房子 id（一筆一個；全頁提示寫房名用）
    var otherEstateIds: [UUID] = []
    /// [v25.621] 這間的表（build 只建一次：水電區卡片的表那幾列、小圖、全頁共用）
    var slots: UtilityMeterSlotIndex = UtilityMeterSlotIndex.empty

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
        result.slots = slots
        var out: [(row: UtilityRow, order: Int)] = []
        var seenKeys = Set<String>()
        for e in events where e.mark == .utility && !e.isYearRow {
            guard seenKeys.insert(e.id).inserted else { continue }
            if let eid = e.expenseId, let ex = expensesById[eid],
               let linked = ex.linkedRealEstateId, linked != re.id {
                result.otherEstateCount += 1
                result.otherEstateIds.append(linked)
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
            panels[t] = panel(t, rows: mine, history: history, slots: slots, asOf: asOf, cal: cal,
                              title: "每期多少錢・近 2 年", maxPoints: maxPointsPerMeter)
        }
        return UtilityTrendBoard(kinds: kinds, defaultKind: latestType, panels: panels)
    }

    /// 一種的圖、圖例、說明行。rows＝近 2 年這一種（舊到新）；history＝這一種全部（配對去年同期用）
    /// [v25.621] title／maxPoints 由呼叫端給：小圖「每期多少錢・近 2 年」、每個表最多 24 點；全頁〔全部〕「每期多少錢・全部」、不限
    static func panel(_ t: UtilityType, rows: [UtilityRow], history: [UtilityRow], slots: UtilityMeterSlotIndex,
                      asOf: Date, cal: Calendar, title: String, maxPoints: Int) -> UtilityTrendPanel {
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
            let mine: [UtilityRow] = Array((byMeter[mid] ?? []).suffix(maxPoints))
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
        let grays: [UtilityRow] = Array(unassigned.suffix(maxPoints))
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

// MARK: - [v25.621] 全頁「水電趨勢」：來源（HouseCardData.build 算一次，全頁不重跑帳本）

/// 固定支出「水電瓦斯」連這間（S5）：不算進圖（避免跟真的帳單重複算），只寫一行提示
struct UtilityFixedNote: Equatable {
    /// 「每月」「每季」「每年」（Recurrence.rawValue）
    let recurrence: String
    /// 每期的台幣金額
    let amount: Double
}

/// 賣出後還有的一期（房子水電那邊記的；帳本照賣出日截掉了，只寫提示）
struct UtilityAfterSale: Equatable {
    let date: Date
    let amount: Double
}

/// 全頁的來源：帳本裡的水電列＋提示要的事實。Equatable：全頁 `.task(id: source)` 用它（內容變了才重算）
struct UtilityTrendSource: Equatable {
    let estateId: UUID
    /// 「一日拾樂」（沒取名「未命名房屋」）
    let estateName: String
    let rows: UtilityRowSet
    /// 今天；賣掉的是賣出日
    let asOf: Date
    let isSold: Bool
    let soldDate: Date?
    /// 出租中（monthlyRental > 0 且沒賣）
    let isRented: Bool
    /// S5：還在扣的固定支出「水電瓦斯」（結束日在 asOf 以前的不算）
    let fixedNotes: [UtilityFixedNote]
    /// M1：水電連到的記帳變成週期固定支出（帳本走年列，不在 rows）
    let becameFixedCount: Int
    /// 賣出後還有的期（舊到新）
    let afterSale: [UtilityAfterSale]
    /// 任一種 ≥ 2 期：小圖下面才出「水電趨勢 ›」
    let showsPage: Bool
}

enum UtilityTrendSourceBuild {
    /// events＝HouseLedger.events（S5、M1 是裡面的固定支出年列）；ntd＝每筆支出的台幣金額（HouseBuildContext.ntd）
    static func make(estate re: RealEstate, name: String, events: [HouseLedgerEvent], expensesById: [UUID: Expense],
                     ntd: [UUID: Double], rows: UtilityRowSet, asOf: Date, cal: Calendar) -> UtilityTrendSource {
        var linked = Set<UUID>()
        for p in re.utilityPayments {
            if let id = p.linkedExpenseId { linked.insert(id) }
        }
        let asOfDay: Date = cal.startOfDay(for: asOf)
        var seen = Set<UUID>()
        var notes: [UtilityFixedNote] = []
        var became = 0
        for e in events {
            guard case .fixedYear(let eid, _) = e.source else { continue }
            guard seen.insert(eid).inserted else { continue }
            if linked.contains(eid) {
                became += 1
                continue
            }
            guard let ex = expensesById[eid], ex.fixedCategory == .utilities else { continue }
            if let end = ex.endDate, cal.startOfDay(for: end) < asOfDay { continue }
            let amount: Double = ntd[eid] ?? ex.amount
            let rec: String = ex.recurrence?.rawValue ?? Recurrence.monthly.rawValue
            notes.append(UtilityFixedNote(recurrence: rec, amount: amount))
        }
        var after: [UtilityAfterSale] = []
        if re.isSold {
            for p in re.utilityPayments {
                var d: Date = p.date
                var amount: Double = p.amount
                if let lid = p.linkedExpenseId, let ex = expensesById[lid] {
                    d = ex.date
                    amount = ntd[lid] ?? ex.amount
                }
                guard amount > 0, cal.startOfDay(for: d) > asOfDay else { continue }
                after.append(UtilityAfterSale(date: d, amount: amount))
            }
            after.sort { (a: UtilityAfterSale, b: UtilityAfterSale) -> Bool in a.date < b.date }
        }
        var count: [UtilityType: Int] = [:]
        for r in rows.rows {
            if let t = r.type { count[t, default: 0] += 1 }
        }
        let shows: Bool = count.values.contains { $0 >= 2 }
        let rented: Bool = re.monthlyRental > 0 && !re.isSold
        return UtilityTrendSource(estateId: re.id, estateName: name, rows: rows, asOf: asOf, isSold: re.isSold,
                                  soldDate: re.soldDate, isRented: rented, fixedNotes: notes,
                                  becameFixedCount: became, afterSale: after, showsPage: shows)
    }
}

// MARK: - [v25.621] 全頁「水電趨勢」：畫面要的值（全頁 .task／換選擇時算好，body 只讀）

/// 全頁的選擇；UtilityTrendPage.build 校正過放在 screen.picks，全頁再寫回（N8）
struct UtilityTrendPicks: Equatable {
    var kind: UtilityType
    /// nil＝全部的表
    var meterId: String?
    /// true＝〔全部〕（資料超過 2 年才有這顆）；false＝近 2 年
    var allRange: Bool
}

/// 表 Picker 的一項（同一種有 2 個以上的表才有）
struct UtilityMeterChoice: Identifiable, Equatable {
    let id: String
    let name: String
}

/// 兩欄一列：「合計」「NT$5,100（6 期）」
struct UtilityStatLine: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
}

/// 明細卡：點到的那期（沒點是最近一期）
struct UtilityTrendDetail: Equatable {
    let key: String
    /// 「9/20 繳」
    let head: String
    /// 「NT$1,590」
    let amountText: String
    /// 約每月、比較、表、收據（有才放）
    let facts: [UtilityStatLine]
    /// 「9/20 繳・NT$1,590・約每月 NT$770（推估）・比去年同期多 15%」（VoiceOver 唸這句）
    let line: String
    /// 房子水電那一期（〔打開這一期〕用）；只在記帳、房子其他支出的是 nil（沒有那顆）
    let paymentId: UUID?
    /// 沒有〔打開這一期〕時的一行字
    let sourceNote: String?
}

/// 統計卡（近 12 個月，照繳費日、從 asOf 往回）＋每年合計
struct UtilityTrendStats: Equatable {
    /// 「近 12 個月」
    let title: String
    /// 合計、每期平均；2 期以上才有最高、最低
    let lines: [UtilityStatLine]
    /// 「近 12 個月 合計 NT$5,100（6 期）・每期平均 NT$850・最高 9/20 繳 NT$1,590・最低 3/20 繳 NT$540」；沒有紀錄是空字串
    let summary: String
    /// 近 12 個月一期都沒有：「近 12 個月沒有電費紀錄」
    let emptyText: String?
    /// 「2025 從 9 月才開始記，先不比」或「2026 到 11/12 合計 NT$5,990，比 2025 同一段多 3%」；只有今年的紀錄時 nil
    let yearNote: String?
    /// 完整年度 ≥ 2 個才有（最近 3 年）：「2024 全年」「NT$7,200（6 期）」
    let years: [UtilityStatLine]
}

/// 全部繳費的一列（新到舊）
struct UtilityPaymentLine: Identifiable, Equatable {
    /// ＝UtilityRow.key
    let id: String
    /// 「2026/11/10・電費」
    let title: String
    /// 「電號 21-40-0218-50-1」「沒指定是哪個電號」「在記帳記的」（有才有，用「・」接）
    let subText: String?
    let amountText: String
    let photoCount: Int
    /// nil＝只在記帳（不能點）
    let paymentId: UUID?
    /// 第一列以外上面畫細線
    let divider: Bool
    let accessibilityText: String
}

/// 頁尾灰字一條
struct UtilityHintLine: Identifiable, Equatable {
    let id: String
    let text: String
}

/// 全頁一次算好的全部字與數字
struct UtilityTrendScreen: Equatable {
    /// 「一日拾樂・水電趨勢」；賣掉的「一日拾樂・持有期間的水電」
    let navTitle: String
    /// 校正過的選擇（N8：種類沒了 → 第一種、表沒了 → 全部、近 2 年沒資料 → 全部）
    let picks: UtilityTrendPicks
    /// 有 ≥ 1 期的種類，電 → 水 → 瓦斯；空的＝只有猜不到類型的（或一筆都沒有）
    let kinds: [UtilityType]
    /// 同一種 2 個表以上才有
    let meterChoices: [UtilityMeterChoice]
    /// v2 只有「金額」（v3 才有〔度數｜金額｜每度幾元〕）
    let quantityText: String
    /// 資料超過 2 年才有〔全部〕
    let showsRangeToggle: Bool
    /// 這一種的圖（UtilityTrendBuild.panel，全頁用 height 200）；kinds 空的時 nil
    let panel: UtilityTrendPanel?
    /// 明細：key → 那一期（圖上每一點都有）
    let details: [String: UtilityTrendDetail]
    /// 沒點時的明細＝最近一期
    let latestKey: String?
    let stats: UtilityTrendStats?
    /// 全部繳費（新到舊、全部種類）
    let payments: [UtilityPaymentLine]
    /// 先列的 24 筆
    let previewPayments: [UtilityPaymentLine]
    /// 「看全部 30 筆」；不到 24 筆 nil
    let showAllTitle: String?
    /// 「14 筆」
    let paymentsTrailing: String
    let hints: [UtilityHintLine]
    /// kinds 空的時那一行
    let emptyText: String?

    /// 點到的那期；沒點、或點的那期不在了（N7）用最近一期。只是查字典
    func detail(for key: String?) -> UtilityTrendDetail? {
        if let key, let d = details[key] { return d }
        guard let k = latestKey else { return nil }
        return details[k]
    }
}

enum UtilityTrendPage {
    static let previewCount = 24
    /// 點超過這麼多（只有〔全部〕會）就抽稀，最近 12 點一律畫
    static let thinAbove = 120
    static let alwaysShownRecent = 12

    /// 全頁的畫面。純函式：estateNames 只拿來寫 M2 那行的房名（全頁從 FinanceStore 讀、不寫）
    static func build(_ src: UtilityTrendSource, picks: UtilityTrendPicks, estateNames: [UUID: String],
                      cal: Calendar) -> UtilityTrendScreen {
        let asOf: Date = src.asOf
        let slots: UtilityMeterSlotIndex = src.rows.slots
        let typed: [UtilityRow] = src.rows.rows.filter { $0.type != nil }
        var kinds: [UtilityType] = []
        for t in UtilityTrendBuild.order where typed.contains(where: { $0.type == t }) {
            kinds.append(t)
        }
        let kind: UtilityType = kinds.contains(picks.kind) ? picks.kind : (kinds.first ?? picks.kind)
        let ofKind: [UtilityRow] = typed.filter { $0.type == kind }
        let choices: [UtilityMeterChoice] = meterChoices(kind, rows: ofKind, slots: slots)
        let meterId: String? = choices.contains(where: { $0.id == picks.meterId }) ? picks.meterId : nil
        let kindRows: [UtilityRow] = filtered(ofKind, meterId: meterId)
        let start2y: Date = cal.startOfDay(for: cal.date(byAdding: .month, value: -UtilityTrendBuild.rangeMonths, to: asOf) ?? asOf)
        let recent: [UtilityRow] = kindRows.filter { cal.startOfDay(for: $0.date) >= start2y }
        let hasOld: Bool = recent.count < kindRows.count
        let allRange: Bool = hasOld && (picks.allRange || recent.isEmpty)
        let shown: [UtilityRow] = allRange ? kindRows : recent
        let resolved = UtilityTrendPicks(kind: kind, meterId: meterId, allRange: allRange)

        var panel: UtilityTrendPanel? = nil
        if !shown.isEmpty {
            let title: String = allRange ? "每期多少錢・全部" : "每期多少錢・近 2 年"
            let maxPoints: Int = allRange ? Int.max : UtilityTrendBuild.maxPointsPerMeter
            let p: UtilityTrendPanel = UtilityTrendBuild.panel(kind, rows: shown, history: ofKind, slots: slots,
                                                               asOf: asOf, cal: cal, title: title, maxPoints: maxPoints)
            panel = thinned(p)
        }
        let details: [String: UtilityTrendDetail] = detailMap(shown, type: kind, history: ofKind, slots: slots,
                                                              asOf: asOf, cal: cal)
        let stats: UtilityTrendStats? = kinds.isEmpty ? nil : statsOf(kindRows, type: kind, asOf: asOf, cal: cal)
        let lines: [UtilityPaymentLine] = paymentLines(src.rows.rows, slots: slots)
        let preview: [UtilityPaymentLine] = Array(lines.prefix(previewCount))
        let showAll: String? = lines.count > previewCount ? "看全部 \(lines.count) 筆" : nil
        let hintLines: [UtilityHintLine] = hints(src, kind: kinds.isEmpty ? nil : kind, kindRows: kindRows,
                                                 slots: slots, estateNames: estateNames, cal: cal)
        let head: String = src.isSold ? "持有期間的水電" : "水電趨勢"
        var empty: String? = nil
        if kinds.isEmpty {
            empty = src.rows.rows.isEmpty ? "這間房子還沒有水電紀錄" : "這間房子的水電都沒寫是水、電還是瓦斯，畫不出趨勢"
        }
        return UtilityTrendScreen(navTitle: "\(src.estateName)・\(head)", picks: resolved, kinds: kinds,
                                  meterChoices: choices, quantityText: "金額", showsRangeToggle: hasOld,
                                  panel: panel, details: details, latestKey: shown.last?.key, stats: stats,
                                  payments: lines, previewPayments: preview, showAllTitle: showAll,
                                  paymentsTrailing: "\(lines.count) 筆", hints: hintLines, emptyText: empty)
    }

    /// 表 Picker：這一種的趨勢表裡、有 ≥ 1 期指定到它的；2 個以上才給
    static func meterChoices(_ t: UtilityType, rows: [UtilityRow], slots: UtilityMeterSlotIndex) -> [UtilityMeterChoice] {
        var used = Set<String>()
        for r in rows where r.meterAssigned {
            if let m = r.meterId { used.insert(m) }
        }
        var out: [UtilityMeterChoice] = []
        for s in slots.trendSlots where s.type == t && used.contains(s.id) {
            out.append(UtilityMeterChoice(id: s.id, name: slots.displayName(s.id)))
        }
        return out.count >= 2 ? out : []
    }

    /// 選了一個表：只留指定到那個表的期；nil＝全部（含沒指定的灰點）
    static func filtered(_ rows: [UtilityRow], meterId: String?) -> [UtilityRow] {
        guard let m = meterId else { return rows }
        return rows.filter { $0.meterAssigned && $0.meterId == m }
    }

    /// 同一種有 2 個以上的趨勢表
    static func hasManyMeters(_ t: UtilityType, slots: UtilityMeterSlotIndex) -> Bool {
        var n = 0
        for s in slots.trendSlots where s.type == t { n += 1 }
        return n >= 2
    }

    /// 點超過 120（只有〔全部〕會）：較舊的點每 step 點畫一點，最近 12 點一律畫；線照畫
    static func thinned(_ p: UtilityTrendPanel) -> UtilityTrendPanel {
        guard let c = p.chart, c.points.count > thinAbove else { return p }
        let n: Int = c.points.count
        let step: Int = (n + thinAbove - 1) / thinAbove
        var pts: [UtilityTrendPoint] = []
        for (i, q) in c.points.enumerated() {
            let keep: Bool = i >= n - alwaysShownRecent || i % step == 0
            pts.append(UtilityTrendPoint(key: q.key, x: q.x, y: q.y, seriesId: q.seriesId, type: q.type, shape: q.shape,
                                         assigned: q.assigned, hollow: q.hollow, visible: keep))
        }
        let chart = UtilityTrendChartData(type: c.type, points: pts, lines: c.lines, average: c.average,
                                          xDomain: c.xDomain, yDomain: c.yDomain, identity: c.identity,
                                          accessibilityText: c.accessibilityText)
        return UtilityTrendPanel(type: p.type, title: p.title, chart: chart, pending: p.pending, pendingHint: p.pendingHint,
                                 legend: p.legend, hiddenMeterNote: p.hiddenMeterNote, defaultCaption: p.defaultCaption,
                                 pickedCaptions: p.pickedCaptions)
    }

    /// 每一期的明細（同一個表、照繳費日排好的全部歷史拿來比去年同期、上一期、推估約每月）
    static func detailMap(_ shown: [UtilityRow], type t: UtilityType, history: [UtilityRow], slots: UtilityMeterSlotIndex,
                          asOf: Date, cal: Calendar) -> [String: UtilityTrendDetail] {
        var byMeter: [String: [UtilityRow]] = [:]
        for r in history where r.meterAssigned {
            if let m = r.meterId { byMeter[m, default: []].append(r) }
        }
        var cycles: [String: Int] = [:]
        var positions: [String: [String: Int]] = [:]
        for (m, list) in byMeter {
            cycles[m] = UtilityMath.cycleDays(list.map(\.date), cal: cal)
            positions[m] = UtilityTrendBuild.indexByKey(list)
        }
        let many: Bool = hasManyMeters(t, slots: slots)
        var out: [String: UtilityTrendDetail] = [:]
        for r in shown {
            var list: [UtilityRow]? = nil
            var pos: Int? = nil
            var cycle = 30
            if r.meterAssigned, let m = r.meterId {
                list = byMeter[m]
                pos = positions[m]?[r.key]
                cycle = cycles[m] ?? 30
            }
            out[r.key] = detail(r, type: t, meterRows: list, position: pos, cycle: cycle, many: many,
                                slots: slots, asOf: asOf, cal: cal)
        }
        return out
    }

    /// 一期的明細：「9/20 繳・NT$1,590・約每月 NT$770（推估）・比去年同期多 15%」
    static func detail(_ r: UtilityRow, type t: UtilityType, meterRows: [UtilityRow]?, position: Int?, cycle: Int,
                       many: Bool, slots: UtilityMeterSlotIndex, asOf: Date, cal: Calendar) -> UtilityTrendDetail {
        let head: String = "\(UtilityTrendBuild.dateText(r.date, asOf: asOf)) 繳"
        let amountText: String = MoneyFormat.short(r.amount)
        var monthly: String? = nil
        var comparison: String? = nil
        if let list = meterRows, let i = position, i >= 0, i < list.count {
            comparison = UtilityTrendBuild.comparison(at: i, in: list, type: t, cycle: cycle, cal: cal)
            if i > 0 {
                monthly = monthlyEstimate(r.amount, from: list[i - 1].date, to: r.date, cal: cal)
            }
        }
        var facts: [UtilityStatLine] = []
        if let m = monthly { facts.append(UtilityStatLine(id: "monthly", label: "約每月", value: m)) }
        if let c = comparison { facts.append(UtilityStatLine(id: "compare", label: "比較", value: c)) }
        if many {
            let label: String = UtilityMeterSlotIndex.numberLabel(t)
            let name: String = r.meterAssigned ? slots.displayName(r.meterId ?? "") : "沒指定是哪個\(label)"
            facts.append(UtilityStatLine(id: "meter", label: label, value: name))
        }
        if r.photoCount > 0 { facts.append(UtilityStatLine(id: "receipt", label: "收據", value: "\(r.photoCount) 張")) }
        var parts: [String] = [head, amountText]
        if let m = monthly { parts.append("約每月 " + m) }
        if let c = comparison { parts.append(c) }
        var note: String? = nil
        if r.paymentId == nil {
            note = r.fromExpenseOnly ? "這筆是在記帳裡記的，要看或改請到記帳" : "這筆記在房子的其他支出，要看或改請到帳本"
        }
        return UtilityTrendDetail(key: r.key, head: head, amountText: amountText, facts: facts,
                                  line: parts.joined(separator: "・"), paymentId: r.paymentId, sourceNote: note)
    }

    /// 約每月（推估，v2 沒有計費期間）：上一期繳費日＋1 → 這期繳費日（頭尾都算＝兩個繳費日差幾天），
    /// 20～70 天才寫；金額 ÷ 天數 × 30，四捨五入到十位（ROUND_HALF_UP）
    static func monthlyEstimate(_ amount: Double, from prev: Date, to cur: Date, cal: Calendar) -> String? {
        let days: Int = UtilityMath.days(prev, cur, cal: cal)
        guard days >= 20, days <= 70 else { return nil }
        guard let perDay = UtilityMath.ratio(amount, Double(days)) else { return nil }
        let raw: Double = perDay * 30
        let tens: Double = (raw / 10).rounded() * 10
        guard tens.isFinite, tens > 0 else { return nil }
        return MoneyFormat.short(tens) + "（推估）"
    }

    /// 「9/20 繳 NT$1,590」
    static func paidText(_ r: UtilityRow, asOf: Date) -> String {
        "\(UtilityTrendBuild.dateText(r.date, asOf: asOf)) 繳 \(MoneyFormat.short(r.amount))"
    }

    /// 近 12 個月（繳費日在 asOf 往前 12 個月內，跟水電區標題同一條）＋每年合計
    static func statsOf(_ rows: [UtilityRow], type t: UtilityType, asOf: Date, cal: Calendar) -> UtilityTrendStats {
        let back: Date = cal.startOfDay(for: cal.date(byAdding: .month, value: -12, to: asOf) ?? asOf)
        let inYear: [UtilityRow] = rows.filter { cal.startOfDay(for: $0.date) >= back }
        let yearly: (note: String?, years: [UtilityStatLine]) = yearSummary(rows, asOf: asOf, cal: cal)
        guard let first = inYear.first else {
            return UtilityTrendStats(title: "近 12 個月", lines: [], summary: "", emptyText: "近 12 個月沒有\(t.rawValue)紀錄",
                                     yearNote: yearly.note, years: yearly.years)
        }
        var total = 0.0
        var hi: UtilityRow = first
        var lo: UtilityRow = first
        for r in inYear {
            total += r.amount
            if r.amount >= hi.amount { hi = r }
            if r.amount <= lo.amount { lo = r }
        }
        let n: Int = inYear.count
        let avg: Double = (total / Double(n)).rounded()
        var lines: [UtilityStatLine] = []
        lines.append(UtilityStatLine(id: "total", label: "合計", value: "\(MoneyFormat.short(total))（\(n) 期）"))
        lines.append(UtilityStatLine(id: "avg", label: "每期平均", value: MoneyFormat.short(avg)))
        if n >= 2 {
            lines.append(UtilityStatLine(id: "max", label: "最高", value: paidText(hi, asOf: asOf)))
            lines.append(UtilityStatLine(id: "min", label: "最低", value: paidText(lo, asOf: asOf)))
        }
        let parts: [String] = lines.map { "\($0.label) \($0.value)" }
        let summary: String = "近 12 個月 " + parts.joined(separator: "・")
        return UtilityTrendStats(title: "近 12 個月", lines: lines, summary: summary, emptyText: nil,
                                 yearNote: yearly.note, years: yearly.years)
    }

    /// 週期：期數最多的那個表的繳費間隔中位數（UtilityMath.cycleDays）；都沒指定表就用全部
    static func cycleOf(_ rows: [UtilityRow], cal: Calendar) -> Int {
        var byMeter: [String: [Date]] = [:]
        for r in rows where r.meterAssigned {
            if let m = r.meterId { byMeter[m, default: []].append(r.date) }
        }
        var best: [Date] = []
        var bestId: String? = nil
        for m in byMeter.keys.sorted() {
            let ds: [Date] = byMeter[m] ?? []
            if bestId == nil || ds.count > best.count {
                best = ds
                bestId = m
            }
        }
        if best.isEmpty { best = rows.map(\.date) }
        return UtilityMath.cycleDays(best, cal: cal)
    }

    /// 每年合計（UX §1.2）。「從年初就有紀錄」＝第一筆的日期 ≤ 那年 1/1 ＋ 週期 ＋ 15 天。
    /// - 今年跟去年比「同一天以前」：去年從年初就有紀錄才比（今年 1/1～asOf 對 去年 1/1～asOf 減一年），
    ///   不然「2025 從 9 月才開始記，先不比」；第一筆就在今年 → nil
    /// - 完整年度（今年以前、從年初就有紀錄）≥ 2 個才列「2024 全年」（最近 3 年）
    /// - 年份一律西曆（手機設民國曆時傳進來的 Calendar.current 的年是 115，會印成「114 從 9 月才開始記」）；時區跟著傳進來的那個
    static func yearSummary(_ rows: [UtilityRow], asOf: Date, cal given: Calendar) -> (note: String?, years: [UtilityStatLine]) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = given.timeZone
        let cal: Calendar = gregorian
        guard let first = rows.first else { return (note: nil, years: []) }
        let y: Int = cal.component(.year, from: asOf)
        let firstYear: Int = cal.component(.year, from: first.date)
        guard firstYear < y else { return (note: nil, years: []) }
        let cycle: Int = cycleOf(rows, cal: cal)
        let firstDay: Date = cal.startOfDay(for: first.date)
        func started(_ year: Int) -> Bool {
            guard let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let cutoff = cal.date(byAdding: .day, value: cycle + 15, to: jan1) else { return false }
            return firstDay <= cal.startOfDay(for: cutoff)
        }
        var note: String
        if !started(y - 1) {
            note = "\(y - 1) 從 \(cal.component(.month, from: first.date)) 月才開始記，先不比"
        } else {
            let lastCut: Date = cal.startOfDay(for: cal.date(byAdding: .year, value: -1, to: asOf) ?? asOf)
            var thisSum = 0.0
            var lastSum = 0.0
            for r in rows {
                let ry: Int = cal.component(.year, from: r.date)
                if ry == y {
                    thisSum += r.amount
                } else if ry == y - 1 && cal.startOfDay(for: r.date) <= lastCut {
                    lastSum += r.amount
                }
            }
            note = "\(y) 到 \(HouseCardFormat.md(asOf)) 合計 \(MoneyFormat.short(thisSum))"
            if let pct = UtilityMath.percentMagnitude(thisSum, vs: lastSum) {
                if pct == 0 {
                    note += "，跟 \(y - 1) 同一段差不多"
                } else {
                    let word: String = thisSum > lastSum ? "多" : "少"
                    note += "，比 \(y - 1) 同一段\(word) \(pct)%"
                }
            }
        }
        var full: [Int] = []
        if firstYear <= y - 1 {
            for yr in firstYear...(y - 1) where started(yr) { full.append(yr) }
        }
        var years: [UtilityStatLine] = []
        if full.count >= 2 {
            for yr in full.suffix(3) {
                var sum = 0.0
                var n = 0
                for r in rows where cal.component(.year, from: r.date) == yr {
                    sum += r.amount
                    n += 1
                }
                years.append(UtilityStatLine(id: "y\(yr)", label: "\(yr) 全年", value: "\(MoneyFormat.short(sum))（\(n) 期）"))
            }
        }
        return (note: note, years: years)
    }

    /// 全部繳費，新到舊、全部種類（rows 是舊到新）
    static func paymentLines(_ rows: [UtilityRow], slots: UtilityMeterSlotIndex) -> [UtilityPaymentLine] {
        var out: [UtilityPaymentLine] = []
        for r in rows.reversed() {
            let typeText: String = r.type?.rawValue ?? RealEstateExpenseCategory.utility.rawValue
            let title: String = "\(HouseCardFormat.ymd(r.date))・\(typeText)"
            var subs: [String] = []
            if let t = r.type, hasManyMeters(t, slots: slots) {
                let label: String = UtilityMeterSlotIndex.numberLabel(t)
                subs.append(r.meterAssigned ? slots.displayName(r.meterId ?? "") : "沒指定是哪個\(label)")
            }
            if r.fromExpenseOnly { subs.append("在記帳記的") }
            let sub: String? = subs.isEmpty ? nil : subs.joined(separator: "・")
            let money: String = MoneyFormat.short(r.amount)
            var spoken: String = "\(title)，\(money)"
            if let s = sub { spoken += "，" + s }
            if r.photoCount > 0 { spoken += "，收據 \(r.photoCount) 張" }
            out.append(UtilityPaymentLine(id: r.key, title: title, subText: sub, amountText: money,
                                          photoCount: r.photoCount, paymentId: r.paymentId, divider: !out.isEmpty,
                                          accessibilityText: spoken))
        }
        return out
    }

    /// 頁尾灰字（有才出現）：出租、賣出、賣出後、固定支出 S5、M1、M2、S4b、週期改變
    static func hints(_ src: UtilityTrendSource, kind: UtilityType?, kindRows: [UtilityRow], slots: UtilityMeterSlotIndex,
                      estateNames: [UUID: String], cal: Calendar) -> [UtilityHintLine] {
        var out: [UtilityHintLine] = []
        let asOf: Date = src.asOf
        if src.isRented {
            out.append(UtilityHintLine(id: "rented", text: "出租中：只算你自己記的水電"))
        }
        if src.isSold {
            let sold: Date = src.soldDate ?? asOf
            out.append(UtilityHintLine(id: "sold", text: "只畫到 \(HouseCardFormat.ymd(sold)) 賣出那天"))
        }
        if let one = src.afterSale.first {
            if src.afterSale.count == 1 {
                let d: String = UtilityTrendBuild.dateText(one.date, asOf: asOf)
                out.append(UtilityHintLine(id: "afterSale", text: "賣出後還有 1 期（\(d) 繳 \(MoneyFormat.short(one.amount))）沒算進來"))
            } else {
                var sum = 0.0
                for a in src.afterSale { sum += a.amount }
                out.append(UtilityHintLine(id: "afterSale",
                                           text: "賣出後還有 \(src.afterSale.count) 期（合計 \(MoneyFormat.short(sum))）沒算進來"))
            }
        }
        if let f = src.fixedNotes.first {
            let text: String
            if src.fixedNotes.count == 1 {
                text = "這間還有一筆\(f.recurrence)『水電瓦斯』固定支出 \(MoneyFormat.short(f.amount))，沒算進圖裡（避免跟真的帳單重複算）"
            } else {
                text = "這間還有 \(src.fixedNotes.count) 筆『水電瓦斯』固定支出，沒算進圖裡（避免跟真的帳單重複算）"
            }
            out.append(UtilityHintLine(id: "fixed", text: text))
        }
        if src.becameFixedCount > 0 {
            out.append(UtilityHintLine(id: "becameFixed",
                                       text: "有 \(src.becameFixedCount) 筆水電連到的記帳改成了固定支出，沒畫進圖"))
        }
        let others: [UUID] = src.rows.otherEstateIds
        if !others.isEmpty {
            let unique = Set(others)
            var text: String = "有 \(others.count) 筆水電已經在記帳改連到別間房子，算在那邊"
            if unique.count == 1, let id = others.first, let name = estateNames[id], !name.isEmpty {
                text = "有 \(others.count) 筆水電已經在記帳改連到『\(name)』，算在那間"
            }
            out.append(UtilityHintLine(id: "otherEstate", text: text))
        }
        if src.rows.untypedCount > 0 {
            out.append(UtilityHintLine(id: "untyped",
                                       text: "有 \(src.rows.untypedCount) 筆水電在記帳裡，沒寫是水、電還是瓦斯，只算進合計"))
        }
        if let t = kind {
            out += cycleHints(t, rows: kindRows, slots: slots, cal: cal)
        }
        return out
    }

    /// 週期改變（UX §5）：同一個表最近 3 次繳費間隔的中位數跟以前不同類（每月 20～40 天、兩個月 50～75 天）
    static func cycleHints(_ t: UtilityType, rows: [UtilityRow], slots: UtilityMeterSlotIndex, cal: Calendar) -> [UtilityHintLine] {
        var byMeter: [String: [Date]] = [:]
        for r in rows where r.meterAssigned {
            if let m = r.meterId { byMeter[m, default: []].append(r.date) }
        }
        let many: Bool = hasManyMeters(t, slots: slots)
        let ids: [String] = byMeter.keys.sorted { (a: String, b: String) -> Bool in
            let oa: Int = slots.order(of: a)
            let ob: Int = slots.order(of: b)
            return oa != ob ? oa < ob : a < b
        }
        var out: [UtilityHintLine] = []
        for m in ids {
            guard let change = UtilityMath.cycleChange(byMeter[m] ?? [], cal: cal) else { continue }
            let when: String = HouseCardFormat.ym(change.from)
            var text: String = change.toMonthly
                ? "從 \(when) 起改成每月一期，每期看起來少一半是正常的"
                : "從 \(when) 起改成兩個月一期，每期看起來多一倍是正常的"
            if many { text = "\(slots.displayName(m))：" + text }
            out.append(UtilityHintLine(id: "cycle-" + m, text: text))
        }
        return out
    }
}

extension UtilityMath {
    /// 一段間隔是每月（20～40 天）、兩個月（50～75 天），還是都不像（nil）
    static func cycleClass(_ gap: Int) -> Int? {
        if gap >= 20 && gap <= 40 { return 1 }
        if gap >= 50 && gap <= 75 { return 2 }
        return nil
    }

    /// [v25.621] 週期改變：照繳費日排好的一個表。間隔（> 0 天的）至少 5 段；最近 3 段**每一段**都像同一類、
    /// 更早那幾段的中位數像另一類（每月／兩個月）→ 改變了（中間夾一筆在記帳補記的，那段不像任何一類，就不判斷）。
    /// from＝改了之後第一期的繳費日（最近 3 段的第一段結尾那期）
    static func cycleChange(_ dates: [Date], cal: Calendar) -> (from: Date, toMonthly: Bool)? {
        guard dates.count >= 2 else { return nil }
        var gaps: [Int] = []
        var ends: [Int] = []
        for i in 1..<dates.count {
            let g: Int = days(dates[i - 1], dates[i], cal: cal)
            if g > 0 {
                gaps.append(g)
                ends.append(i)
            }
        }
        guard gaps.count >= 5 else { return nil }
        let k: Int = gaps.count - 3
        let recent: [Int] = Array(gaps[k...])
        guard let b = cycleClass(recent[0]), recent.allSatisfy({ cycleClass($0) == b }) else { return nil }
        let before: [Int] = Array(gaps[..<k]).sorted()
        let mid: Int = before.count / 2
        let beforeMedian: Int = before.count % 2 == 1 ? before[mid] : (before[mid - 1] + before[mid]) / 2
        guard let a = cycleClass(beforeMedian), a != b else { return nil }
        return (from: dates[ends[k]], toMonthly: b == 1)
    }
}
