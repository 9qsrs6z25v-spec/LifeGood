import SwiftUI

// [v25.534] 房屋卡片上每一個字、每一個數字，都在 HouseCardData.build 一次算好（照 StockCardData）。
// 畫面（HouseCardViews）只排版、上色；外殼（RealEstateDetailView）只管點了要做什麼。
// - 房貸的數字一律讀 HouseFacts，這裡不另算一份（年列的利息／本金也是用 HouseFacts.owed(at:) 拆）。
// - 日期一律西曆＋zh_TW（HouseCardFormat），手機設民國曆也印「2026/4」。
// - 金額一律 MoneyFormat.short／compact、FinanceText：≥ 1 萬「NT$x.x萬」，< 1 萬「NT$2,300」。
// - 要加起來等於合計的數字（帳本格子、長條、篩選小計、年份小計、每個月住這裡）用最大餘數法分尾數，
//   畫面上相加才會剛好等於那個合計。
// - 帳本以記帳為準、用支出 id 去重；同一筆掛在好幾個陣列時，保險 > 附屬資產 > 水電 > 房屋價金 > 變動支出 先掛到的擁有。
// - 「買房費用」歸一次性、不算自備款。舊版 App 會把支出上的這個分類洗成 nil，所以分類一律能接受 nil：
//   退回看它在房子哪個陣列（在 variableExpenses 就用那一列的分類）。
// 這裡只放值型別，不放 View、不用 Color（顏色由畫面依 bucket／mark 對照）；import SwiftUI 只為了 MoneyBoardChip／MoneyTone。

// MARK: - 格式

/// 卡片上的日期與小字。固定西曆＋zh_TW：手機設民國曆時 Calendar.current 會印出「115/4」。
enum HouseCardFormat {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "zh_TW")
        return c
    }()

    /// 「2026/4」
    static func ym(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month], from: d)
        return "\(c.year ?? 0)/\(c.month ?? 0)"
    }

    /// 「2026/3/5」
    static func ymd(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// 「9/18」
    static func md(_ d: Date) -> String {
        let c = calendar.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// 跟 now 同一年寫「9/18」，不同年寫「2027/1/5」
    static func shortDate(_ d: Date, now: Date) -> String {
        calendar.component(.year, from: d) == calendar.component(.year, from: now) ? md(d) : ymd(d)
    }

    /// 帳本左邊日期塊的大字「05」
    static func day(_ d: Date) -> String {
        String(format: "%02d", calendar.component(.day, from: d))
    }

    static func year(_ d: Date) -> Int {
        calendar.component(.year, from: d)
    }

    /// 兩個日子所在的月份差幾個月（2026/10/11 → 2066/3/5＝473）
    static func monthsBetween(_ a: Date, _ b: Date) -> Int {
        let ma = HouseFacts.monthStart(a, calendar)
        let mb = HouseFacts.monthStart(b, calendar)
        return calendar.dateComponents([.month], from: ma, to: mb).month ?? 0
    }

    /// 「39 年 5 個月」「5 個月」「2 年」；0 以下回 nil
    static func span(months: Int) -> String? {
        guard months > 0 else { return nil }
        let y = months / 12
        let m = months % 12
        if y == 0 { return "\(m) 個月" }
        return m == 0 ? "\(y) 年" : "\(y) 年 \(m) 個月"
    }

    /// 住了／持有多久：「1 年 2 個月」「7 個月」；不滿 1 個月回 nil（膠囊不出現）
    static func lived(from a: Date, to b: Date) -> String? {
        guard b > a else { return nil }
        let c = calendar.dateComponents([.year, .month], from: a, to: b)
        return span(months: (c.year ?? 0) * 12 + (c.month ?? 0))
    }

    /// 格子、牌子裡的金額不寫 NT$（「1944萬」「+720萬」「-50萬」）
    static func compact(_ v: Double, signed: Bool = false) -> String {
        (signed && v > 0 ? "+" : "") + MoneyFormat.compact(v)
    }

    /// 一位小數、整數不寫小數（坪數、面積）
    static func number1(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? String(format: "%.0f", r) : String(format: "%.1f", r)
    }

    /// 「32 ㎡（9.7 坪）」：坪＝㎡ × 0.3025
    static func area(squareMeters m2: Double) -> String {
        let ping = number1(m2 * 0.3025)
        return "\(number1(m2)) ㎡（\(ping) 坪）"
    }

    /// 唸給 VoiceOver 的金額：「1207.6 萬」
    static func spoken(_ v: Double) -> String {
        MoneyFormat.compact(v)
            .replacingOccurrences(of: "萬", with: " 萬")
            .replacingOccurrences(of: "億", with: " 億")
    }

    /// 記帳存的 PDF 帳單不算照片
    static func isImage(_ fileName: String) -> Bool {
        !fileName.lowercased().hasSuffix(".pdf")
    }

    /// 帳本列標題：去掉開頭的「項目 N：」「【房名】」「房名 - 」「房名-」。
    /// 從卡片記的支出名稱會被自動填成「項目 12：一日拾樂-裝修」，不去掉的話帳本滿滿都是房名。
    static func cleanTitle(_ raw: String, estateName: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("項目") {
            var rest = Substring(t.dropFirst(2))
            while let c = rest.first, c == " " { rest = rest.dropFirst() }
            var digits = 0
            while let c = rest.first, c.isASCII, c.isNumber {
                rest = rest.dropFirst()
                digits += 1
            }
            while let c = rest.first, c == " " { rest = rest.dropFirst() }
            if digits > 0, let c = rest.first, c == "：" || c == ":" {
                t = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }
        let name = estateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return t }
        if t.hasPrefix("【" + name + "】") {
            t = String(t.dropFirst(name.count + 2)).trimmingCharacters(in: .whitespaces)
        } else if t.hasPrefix(name) {
            var rest = Substring(t.dropFirst(name.count))
            while let c = rest.first, c == " " { rest = rest.dropFirst() }
            if let c = rest.first, c == "-" || c == "－" || c == "–" || c == "—" {
                t = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
            } else if rest.isEmpty {
                t = ""
            }
        }
        return t
    }
}

// MARK: - 最大餘數法

enum HouseRound {
    /// 把 parts 換成 unit 的整數倍，加起來剛好等於 total（先四捨五入到 unit）。
    /// 先全部無條件捨去，差多少個 unit 就從小數部分最大的開始各補一個（多了就從最小的開始各扣一個）。
    static func largestRemainder(_ parts: [Double], total: Double, unit: Double) -> [Double] {
        guard !parts.isEmpty, unit > 0, total.isFinite else { return parts }
        let scaled: [Double] = parts.map { $0.isFinite ? $0 / unit : 0 }
        var units: [Double] = scaled.map { $0.rounded(.down) }
        let fractions: [Double] = scaled.indices.map { scaled[$0] - units[$0] }
        let target = (total / unit).rounded()
        let gap = target - units.reduce(0, +)
        // 呼叫端給的 total 跟 parts 差太遠（不該發生）就不硬分，免得迴圈跑很久
        guard abs(gap) <= Double(parts.count * 4) else { return units.map { $0 * unit } }
        var diff = Int(gap)
        let order: [Int] = parts.indices.sorted { a, b in
            fractions[a] != fractions[b] ? fractions[a] > fractions[b] : a < b
        }
        var i = 0
        while diff > 0 {
            units[order[i % order.count]] += 1
            diff -= 1
            i += 1
        }
        i = 0
        while diff < 0 {
            units[order[order.count - 1 - (i % order.count)]] -= 1
            diff += 1
            i += 1
        }
        return units.map { $0 * unit }
    }

    /// 帳本分尾數的單位：合計一萬以上分到 0.1 萬（畫面寫「NT$x.x萬」），以下分到 1 元
    static func ledgerUnit(_ total: Double) -> Double {
        abs(total) >= 10_000 ? 1_000 : 1
    }

    /// 四捨五入到 unit
    static func round(_ v: Double, unit: Double) -> Double {
        unit > 0 ? (v / unit).rounded() * unit : v
    }
}

// MARK: - 一句話、格子、點了做什麼

/// 一句話裡的一段：金額要粗體、上色時拆開（畫面用 Text 一段一段接起來）
struct HouseRun: Equatable {
    let text: String
    var bold = false
    /// nil＝一般字色
    var tone: MoneyTone? = nil
}

/// 一句話（看板那一句、出租的「每月實際」、帳本兩句…）
struct HouseLine: Equatable {
    var runs: [HouseRun] = []
    /// 整句純文字（VoiceOver、匯出用）
    var plain: String { runs.map(\.text).joined() }

    static func text(_ s: String) -> HouseLine {
        HouseLine(runs: [HouseRun(text: s)])
    }
}

/// 格子或圖例點了要做什麼（畫面依這個呼叫 HouseCardActions）
enum HouseTap: Equatable {
    /// 不能點
    case none
    /// 捲到「房貸」區（actions.scrollTo(.mortgage)）
    case scrollToMortgage
    /// 捲到「我的帳本」並把篩選切過去（actions.setLedgerFilter＋scrollTo(.ledger)）
    case ledgerFilter(HouseLedgerFilter)
    /// 打開編輯頁並捲到那一欄（actions.edit）
    case edit(HouseEditFocus)
}

/// 白卡裡 3×2 的一格（樣子照股票帳本的 tile：小標籤、大數字、小字）
struct HouseTile: Identifiable, Equatable {
    /// 小標籤「借款本金」
    let label: String
    /// 大數字，不寫 NT$（「1944萬」「2066/3」「7 個月」）
    let value: String
    /// 大數字的顏色；nil＝一般字色
    var valueTone: MoneyTone? = nil
    /// 下面的小字（「推算」「7 期」「+720萬」）；空字串＝不寫
    var sub: String = ""
    /// 小字的顏色；nil＝灰字
    var subTone: MoneyTone? = nil
    /// 點了做什麼
    var tap: HouseTap = .none

    var id: String { label }
}

// MARK: - 帳本的分類

/// 帳本的四大類：買房（自備款）／房貸／一次性／持有
enum HouseLedgerBucket: Hashable { case purchase, mortgage, oneTime, holding }

/// 帳本篩選膠囊（順序＝畫面上的順序）
enum HouseLedgerFilter: Hashable, CaseIterable { case all, purchase, mortgage, oneTime, holding }

extension HouseLedgerBucket {
    /// 篩選膠囊、年份組裡的名字「買房」「房貸」「一次性」「持有」
    var title: String {
        switch self {
        case .purchase: return "買房"
        case .mortgage: return "房貸"
        case .oneTime: return "一次性"
        case .holding: return "持有"
        }
    }

    /// 總表長條圖例的名字「自備款」「已繳房貸」「一次性」「持有」
    var legendTitle: String {
        switch self {
        case .purchase: return "自備款"
        case .mortgage: return "已繳房貸"
        case .oneTime: return "一次性"
        case .holding: return "持有"
        }
    }

    /// 長條、圖例的順序
    static let ordered: [HouseLedgerBucket] = [.purchase, .mortgage, .oneTime, .holding]
}

extension HouseLedgerFilter {
    /// 膠囊上的字「全部」「買房」…
    var title: String {
        bucket?.title ?? "全部"
    }

    /// 這個篩選只看哪一類；.all 是 nil
    var bucket: HouseLedgerBucket? {
        switch self {
        case .all: return nil
        case .purchase: return .purchase
        case .mortgage: return .mortgage
        case .oneTime: return .oneTime
        case .holding: return .holding
        }
    }
}

/// 「＋ 記一筆」的選項（順序＝選單順序）
enum HouseLedgerAddKind: String, CaseIterable, Identifiable {
    case housePayment, purchaseCost, renovation, furniture, repair, cleaning, utility, tax, insurance, other, mortgageSegment

    var id: String { rawValue }

    /// 選單上的字
    var title: String {
        switch self {
        case .housePayment: return "房屋價金（頭期款、簽約金）"
        case .purchaseCost: return "買房費用（仲介、代書、契稅）"
        case .mortgageSegment: return "房貸一段"
        default: return category?.rawValue ?? rawValue
        }
    }

    /// 選單上的圖示
    var icon: String {
        category?.icon ?? "building.columns.fill"
    }

    /// AddExpenseView 預設帶的子分類；房貸一段是 nil（走房貸 preset），水電瓦斯由 D 直接開 UtilityPaymentEditor
    var category: RealEstateExpenseCategory? {
        switch self {
        case .housePayment: return .housePayment
        case .purchaseCost: return .purchaseCost
        case .renovation: return .renovation
        case .furniture: return .furniture
        case .repair: return .repair
        case .cleaning: return .cleaning
        case .utility: return .utility
        case .tax: return .tax
        case .insurance: return .insurance
        case .other: return .other
        case .mortgageSegment: return nil
        }
    }
}

/// 帳本列左邊 32pt 圓裡的一個字（畫面依它對照分類色：價 6B4BE0、費 8A5CF6、裝 14A3A3…）
enum HouseLedgerMark: String, Equatable {
    case price = "價"
    case fee = "費"
    case renovation = "裝"
    case furniture = "家"
    case repair = "修"
    case cleaning = "清"
    case utility = "電"
    case tax = "稅"
    case insurance = "保"
    case other = "其"
    case mortgage = "貸"
    case fixed = "固"

    var glyph: String { rawValue }

    /// 總表格子小字用的名字（「裝修・家具」「水電・稅費・維修…」）
    var shortName: String {
        switch self {
        case .price: return "價金"
        case .fee: return "買房費用"
        case .renovation: return "裝修"
        case .furniture: return "家具"
        case .repair: return "維修"
        case .cleaning: return "清潔"
        case .utility: return "水電"
        case .tax: return "稅費"
        case .insurance: return "保險"
        case .other: return "其他"
        case .mortgage: return "房貸"
        case .fixed: return "固定支出"
        }
    }

    static func of(_ c: RealEstateExpenseCategory?) -> HouseLedgerMark {
        switch c {
        case .housePayment?: return .price
        case .purchaseCost?: return .fee
        case .renovation?: return .renovation
        case .furniture?: return .furniture
        case .repair?: return .repair
        case .cleaning?: return .cleaning
        case .utility?: return .utility
        case .tax?: return .tax
        case .insurance?: return .insurance
        case .other?, nil: return .other
        }
    }
}

// MARK: - 帳本一列

struct HouseLedgerEvent: Identifiable {
    enum Source: Equatable {
        case expense(UUID)                 // 有記帳支出（點→AddExpenseView 編輯）
        case utility(UUID)                 // UtilityPayment.id（點→UtilityPaymentEditor）
        case mortgageYear(Int)             // 房貸年列（點→捲到房貸區）
        case fixedYear(UUID, Int)          // 連到房子的固定支出某一年（Expense.id, 年）
        case legacy(LegacyKind, UUID)      // 沒連到記帳的舊資料（item.id）
    }
    enum LegacyKind: Equatable { case paid, variable, utility, insurance, asset }
    let id: String
    let date: Date
    let bucket: HouseLedgerBucket
    let category: RealEstateExpenseCategory?
    let title: String
    let detail: String
    let amount: Double
    let source: Source
    /// 32pt 分類色圓裡的字
    let mark: HouseLedgerMark
    /// 屬於哪一年（西曆）
    let year: Int
    /// 日期塊大字「05」
    let dayText: String
    /// 日期塊小字「2026/9」
    let monthText: String
    /// 右邊的金額「NT$12.5萬」「NT$1,850」
    let amountText: String
    /// 這一列有幾張照片（細字裡已寫進「3 張照片」，給畫面加小圖示用）
    let photoCount: Int
    /// 灰色小標「沒連到記帳」
    let isUnlinked: Bool
    /// 記帳裡那筆支出的 id（刪除時連記帳、銀行扣款一起清用）；舊資料、房貸年列是 nil
    let expenseId: UUID?
    /// 長按選單有沒有「刪除」：房貸年列、固定支出年列不能刪
    let canDelete: Bool
    /// 整列給 VoiceOver 唸的一句
    let accessibilityText: String

    init(id: String, date: Date, bucket: HouseLedgerBucket, category: RealEstateExpenseCategory?,
         title: String, detail: String, amount: Double, source: Source, mark: HouseLedgerMark,
         photoCount: Int = 0, isUnlinked: Bool = false, expenseId: UUID? = nil) {
        self.id = id
        self.date = date
        self.bucket = bucket
        self.category = category
        self.title = title
        self.detail = detail
        self.amount = amount
        self.source = source
        self.mark = mark
        self.year = HouseCardFormat.year(date)
        self.dayText = HouseCardFormat.day(date)
        self.monthText = HouseCardFormat.ym(date)
        let money = MoneyFormat.short(amount)
        self.amountText = money
        self.photoCount = photoCount
        self.isUnlinked = isUnlinked
        self.expenseId = expenseId
        switch source {
        case .mortgageYear, .fixedYear: self.canDelete = false
        default: self.canDelete = true
        }
        var spoken = HouseCardFormat.ymd(date) + "，" + title
        if !detail.isEmpty { spoken += "，" + detail }
        spoken += "，" + money
        if isUnlinked { spoken += "，沒連到記帳" }
        self.accessibilityText = spoken
    }

    /// 房貸年列、固定支出年列（不是一筆真正的記帳）
    var isYearRow: Bool {
        switch source {
        case .mortgageYear, .fixedYear: return true
        default: return false
        }
    }
}

extension HouseLedgerEvent: Equatable {}

/// 帳本裡一年一組
struct HouseLedgerYear: Identifiable, Equatable {
    /// 西曆年
    let year: Int
    /// 這一年的列，新到舊
    let events: [HouseLedgerEvent]
    /// 真正的記帳筆數（不含房貸、固定支出年列）
    let recordCount: Int
    /// 這一年的小計（已用最大餘數法分好，各年相加＝這個篩選的小計）
    let total: Double
    /// 組頭「2026 年・79 筆・NT$862.6萬」（沒有記帳列時省掉「N 筆」）
    let title: String
    /// 今年（賣掉的是賣出那年）：預設展開，往年收起
    let isCurrent: Bool

    var id: Int { year }
}

/// 篩選膠囊
struct HouseLedgerFilterChip: Identifiable, Equatable {
    let filter: HouseLedgerFilter
    /// 已分好尾數的小計（四類相加＝全部＝T）
    let amount: Double
    /// 膠囊上的字「買房 NT$486萬」
    let text: String
    /// 這個篩選有幾列（含年列）；0 時畫面可以不畫這顆
    let rowCount: Int

    var id: HouseLedgerFilter { filter }
}

/// 總表「到今天總共付了」下面四段長條的一段
struct HouseLedgerPart: Identifiable, Equatable {
    let bucket: HouseLedgerBucket
    /// 已分好尾數（四段相加＝T）
    let value: Double
    /// 圖例的字「自備款 486萬」
    let legend: String

    var id: HouseLedgerBucket { bucket }
}

// MARK: - 帳本

struct HouseLedger {
    /// 全部的列，新到舊（含房貸年列、固定支出年列）；匯出逐筆也照這個順序
    var events: [HouseLedgerEvent] = []
    /// 真正的記帳筆數（不含年列）：卡 2 頂端「紀錄・79 筆」
    var recordCount = 0
    /// 卡 2 頂端的字「紀錄・79 筆」
    var recordsTitle = "紀錄"
    /// 一列都沒有（卡 1 只留購入、估值兩格，卡 2 寫 emptyHint）
    var isEmpty: Bool { events.isEmpty }
    /// 區塊標題右邊「從 2026/3 買下」
    var headerTrailing = ""

    /// 分尾數的單位（一萬以上 1000＝0.1 萬，以下 1 元）
    var unit: Double = 1
    /// 到今天總共付了 T（原始金額加完才四捨五入一次）
    var total: Double = 0
    /// 各類還沒分尾數的原始合計
    var rawTotals: [HouseLedgerBucket: Double] = [:]
    /// 各類已分好尾數的合計（四類相加＝total）
    var totals: [HouseLedgerBucket: Double] = [:]
    /// 自備款（房屋價金去重後的合計，原始金額）：「要確認」的購入價差也讀這個，兩邊同一個數
    var downPayment: Double = 0
    /// 自備款幾筆
    var downPaymentCount = 0

    /// 卡 1 的 3×2 格（沒有紀錄時只有「購入」「估值」兩格）
    var tiles: [HouseTile] = []
    /// 「到今天總共付了」（賣掉的寫「到賣出那天總共付了」）
    var totalLabel = "到今天總共付了"
    /// 右邊的「NT$862.6萬」
    var totalText = ""
    /// 10pt 四段長條＋圖例（值 0 的段畫面自己略過）；沒有紀錄時是空的
    var parts: [HouseLedgerPart] = []
    /// 「其中 NT$487.6萬（自備款＋已還本金）已經變成房子裡你的那一份。」算不出借款本金時 nil
    var mineLine: HouseLine? = nil
    /// 「照估值今天賣掉，還掉本金拿回 …」；算不出本金、已賣出、房貸還沒開始時 nil
    var sellLine: HouseLine? = nil
    /// 沒有紀錄時卡 2 的那句話；有紀錄時 nil
    var emptyHint: String? = nil

    /// 篩選膠囊（全部、買房、房貸、一次性、持有）
    var filters: [HouseLedgerFilterChip] = []
    /// 每個篩選的年份分組（新到舊）；用 years(for:) 取
    var yearsByFilter: [HouseLedgerFilter: [HouseLedgerYear]] = [:]

    func years(for filter: HouseLedgerFilter) -> [HouseLedgerYear] {
        yearsByFilter[filter] ?? []
    }

    func amount(_ bucket: HouseLedgerBucket) -> Double {
        totals[bucket] ?? 0
    }
}

// MARK: - 要確認

/// 房子陣列裡一筆連到記帳的項目（「要確認」修正用）
struct HouseItemLink: Equatable {
    enum Place: Equatable {
        case mortgage, paid, variable, insurance, asset, utility
        /// 房子本身的舊版單筆房貸連結 RealEstate.linkedExpenseId
        case estateMortgage
        /// 房子本身的售出虧損連結 RealEstate.saleLinkedExpenseId
        case estateSale

        /// 確認文字裡的名字
        var title: String {
            switch self {
            case .mortgage, .estateMortgage: return "房貸"
            case .paid: return "房屋價金"
            case .variable: return "變動支出"
            case .insurance: return "保險"
            case .asset: return "附屬資產"
            case .utility: return "水電"
            case .estateSale: return "售出虧損"
            }
        }
    }
    let place: Place
    /// 陣列項目的 id；房子本身的連結（estateMortgage／estateSale）是 nil
    let itemId: UUID?
    let expenseId: UUID
}

/// 同一筆支出掛在好幾個地方
struct HouseDuplicate: Equatable {
    let expenseId: UUID
    /// 要留下的那個陣列（保險 > 附屬資產 > 水電 > 房屋價金 > 變動支出）
    let keep: HouseItemLink.Place
    /// 它出現的每一處（同一個陣列出現兩次就寫兩次）
    let places: [HouseItemLink.Place]
}

struct HouseCheck: Identifiable {
    enum Kind: String {
        /// 賣掉了，房貸固定支出還在記帳裡每月扣
        case soldStillCharging
        /// 房貸年限沒填，期數是猜的（240 期）
        case termMissing
        /// 記帳那邊刪掉了，房子這邊還留著
        case orphans
        /// 同一筆支出掛在兩個地方
        case duplicates
        /// 自備款＋借款本金≠購入價
        case purchaseMismatch
        /// 估值是 0
        case valueMissing
        /// 已售出、成交價沒填
        case soldPriceMissing
        /// 算不出利率
        case rateUnsolvable
    }

    /// D 按下按鈕（先付費、confirm 非 nil 時再確認）之後要做的事，修正需要的 id 都在裡面
    enum Fix: Equatable {
        /// RealEstateSale.syncMortgageStops(of:soldDate:in:) 寫回 expenseStore.expenses（這幾筆是現在還在扣的）
        case stopMortgagesAtSale(expenseIds: [UUID])
        /// 打開那一段（actions.openSegment）：連到記帳的開 AddExpenseView 去填年限
        case openSegment(HouseFacts.Segment)
        /// 移除孤兒：paid／variable／insurance／asset／mortgage 拿掉那一項；utility 只把 linkedExpenseId 設 nil；
        /// estateMortgage／estateSale 把房子身上那個連結設 nil
        case removeOrphans([HouseItemLink])
        /// 整理重複：每筆只留在 keep 那個陣列（同陣列重複只留第一列），其餘 removeAll { $0.linkedExpenseId == id }；不刪支出
        case mergeDuplicates([HouseDuplicate])
        /// 打開編輯頁捲到那一欄（actions.edit）
        case edit(HouseEditFocus)
    }

    let kind: Kind
    /// 一句話（「2 筆在記帳那邊已經刪掉，房子這邊還留著」）
    let message: String
    /// 右邊按鈕的字「在賣出日停止」「去填」「移除」「整理」「去看」「去改」
    let button: String
    /// 按下去的確認文字；只開編輯頁的（去填／去改／去看）是 nil
    let confirm: String?
    let fix: Fix
    /// 左邊注意色圖示
    var icon: String = "exclamationmark.triangle.fill"

    var id: String { kind.rawValue }
    /// 按鈕給 VoiceOver 的名字（「整理：1 筆保險同時掛在…」）
    var accessibilityLabel: String { button + "：" + message }
}

// MARK: - 各區的資料

/// 看板（天空＋房子）上的字
struct HouseBoardData: Equatable {
    /// 日期列「苗栗縣竹南鎮・透天 4 層」「苗栗縣竹南鎮・大樓 12F」；已售出「苗栗縣竹南鎮・已售出」；不放門牌
    var date = ""
    /// 日期列圖示：house.fill；已售出 checkmark.seal.fill
    var dateIcon = "house.fill"
    /// 右上膠囊「增值 ▲30%」「跌價 ▼5%」「持平」；已售出「持有 5 年 2 個月」；估值沒填或購入價 0 時 nil
    var capsule: String? = nil
    /// 膠囊圖示；capsule 是 nil 時也是 nil
    var capsuleIcon: String? = nil
    /// 膠囊的字色（.up 紅、.down 綠；.neutral 時畫面傳 capsuleTint nil）
    var capsuleTone: MoneyTone = .neutral
    /// 小字「房屋估值」「房屋估值（還沒填，先用購入價）」；已售出「賣出價差」
    var label = "房屋估值"
    /// 大字「NT$3150萬」；已售出「+NT$720萬」
    var big = ""
    /// 大字顏色：已售出用 MoneyTone.change（賺紅賠綠）；其他 nil
    var bigTone: MoneyTone? = nil
    /// 一句話（金額那段 bold＋tone）
    var line = HouseLine()
    /// 手寫問候兩行：「Welcome home,」「Miaoli」；出租「Home pays back,」；已售出「So long,」；沒填縣市第二行「sweet home!」
    var greeting: [String] = []
    /// 整個看板 header 合成一個 VoiceOver 元素時唸的一句
    var accessibilityText = ""
}

/// 看板下的「房貸進度」格
struct HouseProgressData: Equatable {
    struct Tick: Identifiable, Equatable {
        /// 0…1，軌道上的位置
        let fraction: Double
        /// 「2031/4」（VoiceOver 用；畫面只畫細刻度）
        let label: String
        var id: String { label }
    }
    /// 標題「房貸進度」
    var title = "房貸進度"
    /// 標題右邊「2026/4 → 2066/3」
    var range = ""
    /// 圓點位置 0…1（用月數算）；還沒開始是 0
    var fraction: Double = 0
    /// 段和段交界的細刻度（第 2…n 段的第一期）
    var ticks: [Tick] = []
    /// 圓點上的小牌「今天」；還沒開始「還沒開始」
    var dotPill = "今天"
    /// 右端小牌「2066/3 繳完」
    var endPill = ""
    /// 軌道下左邊「已繳 7 期」「已繳 14 期（2 筆同時在繳）」；還沒開始「第一期 2027/1」
    var left = ""
    /// 軌道下右邊「還有 473 期（39 年 5 個月）」
    var right = ""
    /// 最下面一句「2031/4 起每月改繳 NT$6.4萬」；月付不會變時「每月 NT$3.7萬，繳到 2066/3」
    var note = ""
    /// 房貸還沒開始（圓點停在最左邊）
    var notStarted = false
    /// 整格給 VoiceOver 唸的一句
    var accessibilityText = ""
}

/// 「房貸」區
struct HouseMortgageData: Equatable {
    enum Status: Equatable {
        /// 繳款中：藍底白字「1」
        case paying
        /// 還沒開始：灰框「2」
        case notStarted
        /// 已繳完：綠勾
        case done
        /// 提前停扣：灰色「停」
        case stopped
        /// 房子賣掉時還沒繳完：「賣出時結清」
        case soldSettled
    }

    /// 階梯圖的一塊（一段）
    struct Step: Identifiable, Equatable {
        /// 段的 id（跟 HouseFacts.Segment.id、Row.id 同一個）
        let id: UUID
        /// 第幾段（1 起算）
        let index: Int
        /// 左緣：第一期扣款日
        let start: Date
        /// 右緣：最後一期算數的扣款日
        let end: Date
        /// 實心畫到哪一天（已繳的最後一期）；還沒繳任何一期是 nil（整塊淡色）
        let paidUntil: Date?
        /// 底：跟它同時在繳、開始得比較早的段疊在下面
        let yStart: Double
        /// 頂＝yStart＋每月金額
        let yEnd: Double
        /// 每月金額（季繳 ÷3、年繳 ÷12）
        let monthly: Double
        /// 塊頂端的字「3.7萬」
        let annotation: String
        /// 選到這一塊時圖下說明「第 2 段・2031/4–2036/3・每月 NT$6.4萬」
        let caption: String
    }

    /// 段落清單的一列
    struct Row: Identifiable, Equatable {
        /// 段的 id
        let id: UUID
        /// 點、長按時交給 actions.openSegment／deleteSegment
        let segment: HouseFacts.Segment
        /// 第幾段（1 起算）
        let index: Int
        let status: Status
        /// 28pt 圓裡的字：「1」「2」「停」；已繳完是空字串（畫勾）
        let badge: String
        /// 標題「第 1 段」或使用者取的名字
        let title: String
        /// 細字「2026/4 – 2031/3・60 期」
        let range: String
        /// 右邊「NT$3.7萬/月」（季繳「/季」、年繳「/年」）
        let amount: String
        /// 最下一行「第 7／60 期」「2031/4 開始」「已繳完」「已停止 2027/5」「賣出時結清」
        let statusText: String
        /// 繳款中的細進度條 0…1；其他狀態 nil
        let progress: Double?
        /// 「下次 11/5 扣款」；只有繳款中才有
        let nextText: String?
        /// 灰色小標「沒連到記帳」
        let isUnlinked: Bool
        /// 注意色小標「期數沒填」
        let termMissing: Bool
        /// 整列給 VoiceOver 唸的一句
        let accessibilityText: String
    }

    /// 區塊標題右邊「5 段・2066/3 繳完」；已售出「5 段・2031/5 賣出」
    var trailing = ""
    /// 3×2 格（算得出本金和利率）或三格（算不出）；全部繳完只留借款本金、已付利息、繳完；已售出是空的
    var tiles: [HouseTile] = []
    /// 格子下一行可點的提示（點→actions.edit(.loanPrincipal)）：算不出本金或利率時才有
    var principalHint: String? = nil
    /// 「全部繳完總共 NT$2974.1萬，其中利息約 NT$1030.1萬・換算年利率約 2.1%」；已售出 nil
    var totalLine: HouseLine? = nil
    /// 「今年付的利息約 NT$24.3萬（自住房貸利息，報稅每年最多列舉 30 萬）」；算不出利率、今年沒付、已售出時 nil
    var interestLine: HouseLine? = nil
    /// 已售出時清單上面那一行「房子 2031/5 賣掉了，房貸算到那天」；沒賣是 nil
    var soldNote: String? = nil

    /// 階梯圖要不要畫（已售出、沒有可畫的段時 false）
    var showChart = false
    /// 階梯圖每一塊
    var steps: [Step] = []
    /// 橫軸左右端
    var chartStart = Date()
    var chartEnd = Date()
    /// 橫軸刻度（每 10 年一格；短的房貸縮成 5、2、1 年）
    var axisDates: [Date] = []
    /// 縱軸上限（最高那一塊的 yEnd）
    var chartMax: Double = 0
    /// 「今天」那條線；不在範圍內或已售出時 nil
    var today: Date? = nil
    /// 圖下預設說明「每一階是一段：高度是那段每個月要繳多少」（選到一塊時換成那塊的 caption）
    var chartCaption = "每一階是一段：高度是那段每個月要繳多少"

    /// 段落清單，依開始時間由舊到新
    var rows: [Row] = []
    /// 最下面的小字（反推利率的說明）；算不出利率或已售出時 nil
    var footnote: String? = nil
    /// 「＋ 加一段」預設的起始日：最後一段的最後一期（貸款第一期＝起始日的下一期，剛好接上）
    var newSegmentStart = Date()
}

/// 「每個月住這裡」區
struct HouseLivingData: Equatable {
    enum Kind: String, Equatable {
        /// 利息（暖橘）
        case interest
        /// 還本金（紫）
        case principal
        /// 算不出利率時的一整塊「房貸」
        case mortgage
        /// 管理費等固定費用（靛）
        case fixed
        /// 水電瓦斯（青）
        case utility
        /// 稅費・保險（藍灰）
        case taxInsurance
        /// 維修・清潔・其他（琥珀）
        case upkeep
    }

    struct Part: Identifiable, Equatable {
        let kind: Kind
        /// 圖例的名字「利息」「管理費等固定費用」
        let label: String
        /// 每月金額（已用最大餘數法分到百位，各段相加＝total）
        let value: Double
        /// 「NT$3.5萬」「NT$2,300」
        let valueText: String
        /// 點圖例：利息／還本金／房貸→捲到房貸；其他→帳本切到「持有」
        let tap: HouseTap

        var id: String { kind.rawValue }
        /// 圖例整段字「利息 NT$3.5萬」
        var legend: String { label + " " + valueText }
    }

    /// 區塊標題右邊「近 7 個月平均」（滿一年「近 12 個月平均」）
    var trailing = ""
    /// 合計（四捨五入到百位）；看板膠囊「住這裡每月」、出租區也用這個數
    var total: Double = 0
    /// 大字列「平均每月 約 NT$4.5萬」
    var headline = ""
    /// 12pt 分段長條＋圖例（只放大於 0 的段）
    var parts: [Part] = []
    /// 「真正花掉的是 約 NT$4.3萬（利息＋持有花費）；NT$2,300 是在還本金，會變成你的。」分不出利息本金時 nil
    var summary: HouseLine? = nil
    /// 「填上當初借多少，就能分出利息和本金」（點→actions.edit(.loanPrincipal)）；分得出、或這個月沒房貸時 nil
    var splitHint: String? = nil
    /// 「買進還不到一年，房屋稅（5 月）和地價稅（11 月）可能還沒繳到，這裡會先偏低。」不符合時 nil
    var firstYearHint: String? = nil
    /// 最下面的小字
    var footnote = "頭期款、裝修、家具這種一次性的錢不算在這裡，請看下面的「我的帳本」。"
}

/// 「出租」區
struct HouseRentalData: Equatable {
    /// 區塊標題右邊「月租 NT$2.5萬」
    var trailing = ""
    /// 三格：月租、年報酬（小字「用估值算」）、租金付掉房貸（沒有房貸時沒有這格）
    var tiles: [HouseTile] = []
    /// 金色進度條 0…1（最多 1）；這個月沒房貸時 nil（不畫）
    var coverFraction: Double? = nil
    /// 進度條旁的字「租金付掉房貸 68%」；超過時「租金比房貸多」；沒房貸時 nil
    var coverText: String? = nil
    /// 月租 − 每個月住這裡（≥ 0 是多收，< 0 是倒貼）
    var net: Double = 0
    /// 「扣掉房貸和住這裡的花費，每月實際貼 NT$2.0萬」（金額段 bold＋good／bad）
    var line = HouseLine()
}

/// 「房屋資料」區
struct HouseInfoData: Equatable {
    enum RowKind: Equatable {
        /// 一般的一列
        case plain
        /// 地址：點了選單「複製」「在地圖打開」（用 addressQuery）
        case address
        /// 權狀：可以展開，展開內容是 deeds
        case deeds
        /// 保險：點→actions.openExpense(id)；沒連到記帳是 nil（不能點）
        case insurance(UUID?)
        /// 注意色一列（「估值一年沒更新了」）
        case warning
        /// 備註（可以多行）
        case note
    }

    struct Row: Identifiable, Equatable {
        let id: String
        /// 左邊標籤（寬 84）「地址」「類型」…；warning 列是空字串
        let label: String
        let value: String
        var kind: RowKind = .plain
    }

    /// 展開權狀後的一份
    struct DeedBlock: Identifiable, Equatable {
        let id: UUID
        /// 「土地權狀」「建物權狀 2」
        let title: String
        /// 坐落、地號、建號、門牌、完工日、用途、附屬建物、面積（㎡ 和坪並列）
        let rows: [Row]
    }

    /// 區塊標題右邊「透天・45.2 坪」
    var trailing: String? = nil
    /// 由上到下的列（沒有值的列不放）
    var rows: [Row] = []
    /// 權狀展開內容；沒有權狀是空的
    var deeds: [DeedBlock] = []
    /// 「複製」「在地圖打開」、衛星圖查座標用的完整地址（縣市只寫一次）；沒填地址時 nil
    var addressQuery: String? = nil
    /// 「補上地址、坪數、樓層 → 編輯」；資料夠多時 nil
    var hint: String? = nil
}

/// 「樓層與物品」區（D 畫）
struct HouseFloorsData: Equatable {
    /// 一件家電家具（附屬資產）
    struct Asset: Identifiable, Equatable {
        /// RealEstatePropertyAsset.id
        let id: UUID
        /// 「冷氣・大金・NT$4.2萬」
        let text: String
        /// 價格（連結支出的台幣金額，沒連結用 asset.amount）
        let price: Double
        /// 點了打開連結的記帳支出（actions.openExpense）；沒連結 nil
        let expenseId: UUID?
    }

    /// 一層（最高在最上）
    struct Floor: Identifiable, Equatable {
        /// FloorInfo.id（物品樹 CRUD 用）
        let id: UUID
        /// 左邊 40pt 方塊的字「3F」「B1」「RF」「夾層」
        let label: String
        /// 地下室（方塊用深灰）
        let isBasement: Bool
        let isRoof: Bool
        /// 房間小膠囊「主臥」「客臥」
        let rooms: [String]
        /// 灰字「32 ㎡（9.7 坪）」；沒填面積 nil
        let areaText: String?
        /// 物品樹節點總數（遞迴）
        let treeCount: Int
        /// 掛到這一層的家電家具
        let assets: [Asset]
        /// 右邊「12 件」（樹＋家電）；0 件是空字串
        let countText: String
        /// 「3 樓，主臥、客臥，32 平方公尺，12 件東西」
        let accessibilityText: String
    }

    /// 由上到下（最高樓在最上面）
    var floors: [Floor] = []
    /// 位置對不上任何一層的家電（「其他位置」）
    var otherAssets: [Asset] = []
    /// 最後一行「家電家具 14 件，共 NT$38萬」；沒有家電時 nil
    var assetSummary: String? = nil
    /// 區塊標題右邊「4 層・36 件」；沒有樓層也沒有家電時 nil
    var trailing: String? = nil
    /// 沒有樓層也沒有家電（只顯示一行提示＋「去加樓層」）
    var isEmpty = true
}

/// 「水電瓦斯」區
struct HouseUtilitiesData {
    /// 一個表
    struct Meter: Identifiable {
        /// 「main-water」「main-electricity」「main-gas」或額外表的 UtilityMeter.id
        let id: String
        let type: UtilityType
        /// 額外表自己取的名字「客廳」；主表是空字串
        let name: String
        /// 「電號」；沒填表號時「電費（沒填電號）」
        let title: String
        /// 號碼（等寬字）；沒填是空字串（長按複製用它）
        let number: String
        /// 所有權人；沒填是空字串
        let owner: String
        /// 瓦斯「用戶編號 123456」；沒有是空字串
        let userNumber: String
        /// 最近一期（同一種表只掛在第一列）；點列→actions.openUtility(latest)
        let latest: UtilityPayment?
        /// 右邊「9/18・NT$1,850」；沒有繳費 nil（VoiceOver、舊呼叫端用）
        let latestText: String?
        /// 最近一期的收據張數（點收據圖示看全部）
        let latestPhotoCount: Int
        /// [v25.560] 右邊分兩行：上「10/17」、下「NT$1,850」（以前擠成一行，金額會被切成「NT$...」）
        var latestDate: String? = nil
        var latestAmount: String? = nil
    }

    /// 全部繳費中的一筆（「看全部」展開後）
    struct Payment: Identifiable {
        let payment: UtilityPayment
        /// 「2026/9/18」
        let dateText: String
        /// 「電費」
        let typeText: String
        /// 「NT$1,850」
        let amountText: String
        /// 收據張數
        let photoCount: Int
        var id: UUID { payment.id }
    }

    /// 區塊標題右邊「近 12 個月 NT$2.7萬」；這段期間沒有繳費 nil
    var trailing: String? = nil
    /// 近 12 個月合計（跟帳本「持有」裡的水電同一批）
    var total12m: Double = 0
    /// 每個表一列：主表（水、電、瓦斯）在前，額外的表接在後面
    var meters: [Meter] = []
    /// 全部繳費，新到舊
    var payments: [Payment] = []
    /// 「看全部 5 筆」；沒有繳費 nil
    var showAllTitle: String? = nil
    /// 沒有表號也沒有繳費（縮成一行「＋ 記第一筆水電費（表號在「編輯」填）」）
    var isEmpty: Bool { meters.isEmpty && payments.isEmpty }
}

/// 「電梯保養」區
struct HouseElevatorData {
    struct Record: Identifiable {
        let record: ElevatorMaintenance
        /// 「2026/8/12」
        let dateText: String
        /// 照片張數（點了用 CutePhotoViewer 看全部）
        let photoCount: Int
        var id: UUID { record.id }
    }

    /// 區塊標題右邊「共 6 次」；沒有紀錄 nil
    var trailing: String? = nil
    /// 一句話「上次保養 2026/8/12・平均每 30 天一次，下次大約 9/11」；超過時後半段換注意色「已經超過 29 天沒保養」
    var line = HouseLine()
    /// 超過預計日期了
    var isOverdue = false
    /// 上次保養日；沒有紀錄 nil
    var lastDate: Date? = nil
    /// 相鄰兩次相差天數的中位數；不到 2 筆 nil
    var medianDays: Int? = nil
    /// 下次大約＝上次＋中位數；不到 2 筆、或已售出時 nil
    var nextDate: Date? = nil
    /// 超過下次大約幾天（> 0 才有）；沒超過 nil
    var overdueDays: Int? = nil
    /// 全部紀錄，新到舊（畫面先列 3 筆＋「看全部」）
    var records: [Record] = []
}

/// 「照片與文件」區的張數（D 畫）
struct HouseMediaData: Equatable {
    /// 照片張數：裝潢照片＋關聯支出的圖片（PDF 不算）＋水電收據＋電梯保養照片
    var photoCount = 0
    /// 文件份數＝documents.count
    var documentCount = 0
    /// 區塊標題右邊「12 張・3 份」；兩樣都沒有時 nil
    var trailing: String? = nil
    /// 有圖片的關聯支出（集錦要列的那幾筆，跟張數同一批）
    var photoExpenseIds: [UUID] = []
    /// 沒有任何照片和文件（整區縮成一行「＋ 加照片或文件」）
    var isEmpty: Bool { photoCount == 0 && documentCount == 0 }
}

// MARK: - 卡片資料

struct HouseCardData {
    let estateId: UUID
    /// 房名，空白→「未命名房屋」（工具列標題、分享頁首、名牌）
    let name: String
    /// build 時那一份房子資料（各區要讀原始欄位時用）
    let estate: RealEstate
    let facts: HouseFacts
    /// 看板風景（剖面房子）
    let scene: HouseSceneModel
    /// 我的帳本
    let ledger: HouseLedger
    /// 要確認（一件都沒有時整區不出現）
    let checks: [HouseCheck]

    /// 看板的 seed＝MoneyItem.seed(estateId)
    var seed = 0
    var isSold = false
    /// 出租中（monthlyRental > 0 且沒賣）
    var isRented = false
    /// 數字算到哪一天：今天；賣掉的是賣出日
    var asOf = Date()
    /// 有房貸段，但第一期還沒扣（預售屋、剛撥款）
    var loanNotStarted = false
    /// 沒有房貸、帳本也沒有任何一列（空的新房子）
    var isBlank = false

    /// 看板上的字
    var board = HouseBoardData()
    /// 看板下的房貸進度格；沒有房貸、已售出、全部繳完時 nil
    var progress: HouseProgressData? = nil
    /// 全部繳完時取代進度格的一行「房貸 2066/3 全部繳完」（前面 checkmark.seal.fill）；其他時候 nil
    var paidOffLine: String? = nil
    /// 看板下的膠囊（值是 0 或沒資料的不放）
    var chips: [MoneyBoardChip] = []
    /// 「要確認」區塊標題右邊「3 件」；沒有時 nil
    var checksTrailing: String? = nil
    /// 「房貸」區；沒有房貸段時 nil（整區不出現）
    var mortgage: HouseMortgageData? = nil
    /// 「每個月住這裡」；已售出、或房貸／固定費用／持有花費都是 0 時 nil
    var living: HouseLivingData? = nil
    /// 「出租」；沒出租或已售出時 nil
    var rental: HouseRentalData? = nil
    /// 「房屋資料」（永遠顯示）
    var info = HouseInfoData()
    /// 「樓層與物品」（D 畫）
    var floors = HouseFloorsData()
    /// 「水電瓦斯」（永遠顯示，空的時縮成一行）
    var utilities = HouseUtilitiesData()
    /// 「電梯保養」；沒勾「有電梯」時 nil
    var elevator: HouseElevatorData? = nil
    /// 「照片與文件」的張數（D 畫）
    var media = HouseMediaData()

    static func build(_ re: RealEstate, expense: ExpenseStore, now: Date = Date()) -> HouseCardData {
        build(re, expenses: expense.expenses, ntd: { expense.ntdValue(of: $0) }, now: now)
    }

    static func build(_ re: RealEstate, expenses: [Expense], ntd: (Expense) -> Double, now: Date = Date(), calendar: Calendar = .current) -> HouseCardData {
        let facts = HouseFacts.build(re, expenses: expenses, now: now, calendar: calendar)
        let c = HouseBuildContext.make(re, facts: facts, expenses: expenses, ntd: ntd, now: now, calendar: calendar)
        let trimmed = re.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "未命名房屋" : trimmed
        let ledger = HouseLedger.build(c)
        let checks = HouseCheck.build(c, ledger: ledger)
        let scene = sceneModel(c, name: name)

        var d = HouseCardData(estateId: re.id, name: name, estate: re, facts: facts,
                              scene: scene, ledger: ledger, checks: checks)
        d.seed = MoneyItem.seed(re.id)
        d.isSold = re.isSold
        d.isRented = re.monthlyRental > 0 && !re.isSold
        d.asOf = facts.asOf
        d.loanNotStarted = c.notStarted
        d.isBlank = !facts.hasMortgage && ledger.isEmpty
        d.checksTrailing = checks.isEmpty ? nil : "\(checks.count) 件"
        d.mortgage = mortgageData(c)
        d.living = livingData(c, ledger: ledger)
        let livingTotal = d.living?.total ?? 0
        d.rental = rentalData(c, livingTotal: livingTotal)
        let place = HousePlace.make(re)
        d.board = boardData(c, name: name, place: place, isBlank: d.isBlank)
        d.progress = progressData(c)
        if facts.isPaidOff, !re.isSold, let payoff = facts.payoffDate {
            d.paidOffLine = "房貸 " + HouseCardFormat.ym(payoff) + " 全部繳完"
        }
        d.chips = chipsData(c, ledger: ledger, livingTotal: livingTotal)
        d.info = infoData(c, place: place)
        d.floors = floorsData(c)
        d.utilities = utilitiesData(c)
        d.elevator = elevatorData(c)
        d.media = mediaData(c)
        return d
    }

    /// 換房列一顆膠囊的字與色（持有「▲30%」、已售「賣 ▲18%」；算不出→nil）
    static func switcherTrailing(_ re: RealEstate) -> (text: String, tone: MoneyTone)? {
        let price = re.purchasePrice
        let value = re.isSold ? (re.soldPrice ?? re.currentValue) : re.currentValue
        guard price > 0, value > 0 else { return nil }
        let r = value / price - 1
        let head = re.isSold ? "賣 " : ""
        if abs(r) < 0.005 { return (text: head + "持平", tone: MoneyTone.neutral) }
        let arrow = r > 0 ? "▲" : "▼"
        let tone: MoneyTone = r > 0 ? .up : .down
        return (text: head + arrow + FinanceText.percent1(abs(r)), tone: tone)
    }
}

// MARK: - 建資料時共用的東西

private struct HouseBuildContext {
    let re: RealEstate
    let facts: HouseFacts
    let expenses: [Expense]
    let byId: [UUID: Expense]
    /// 每筆支出的台幣金額（ExpenseStore.ntdValue）
    let ntd: [UUID: Double]
    let now: Date
    /// 今天；賣掉的是賣出日
    let asOf: Date
    let cal: Calendar
    /// 帳本不列的支出：房貸固定支出（含舊版單筆連結、只在記帳那邊連到這間的）、賣出虧損那一筆
    let excluded: Set<UUID>

    var notStarted: Bool { facts.hasMortgage && !facts.hasStarted }

    func amount(_ ex: Expense) -> Double { ntd[ex.id] ?? ex.amount }

    static func make(_ re: RealEstate, facts: HouseFacts, expenses: [Expense], ntd: (Expense) -> Double,
                     now: Date, calendar: Calendar) -> HouseBuildContext {
        let byId = Dictionary(expenses.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let money = Dictionary(expenses.map { ($0.id, ntd($0)) }, uniquingKeysWith: { a, _ in a })
        var excluded = RealEstateSale.mortgageExpenseIds(of: re, expenses: expenses)
        for s in facts.segments {
            if let id = s.linkedExpenseId { excluded.insert(id) }
        }
        if let sale = re.saleLinkedExpenseId { excluded.insert(sale) }
        return HouseBuildContext(re: re, facts: facts, expenses: expenses, byId: byId, ntd: money,
                                 now: now, asOf: facts.asOf, cal: calendar, excluded: excluded)
    }

    /// 這一天在 asOf 當天或之前
    func onOrBeforeAsOf(_ d: Date) -> Bool {
        cal.startOfDay(for: d) <= cal.startOfDay(for: asOf)
    }

    /// 某個月份（1 號）正在繳的各段月付合計
    func monthlyMortgage(inMonth month: Date) -> Double {
        facts.segments.filter { $0.isPaying(inMonth: month, calendar: cal) }.reduce(0.0) { $0 + $1.monthly }
    }

    /// 這一段的期數是不是沒填（連結支出沒填年限；沒連結的舊段還是預設的 240 期）
    func termMissing(_ s: HouseFacts.Segment) -> Bool {
        if s.termIsGuess { return true }
        guard !s.isLinked else { return false }
        return re.mortgageItems.first(where: { $0.id == s.id })?.totalPeriods == 240
    }
}

/// 縣市與鄉鎮市區
private struct HousePlace {
    /// 顯示用的縣市（沒填時從地址開頭抓）
    var city = ""
    /// 「竹南鎮」；抓不到 nil
    var district: String? = nil
    /// 地址去掉開頭的縣市之後
    var rest = ""
    /// 手寫問候第二行；查不到 nil
    var english: String? = nil

    /// 「苗栗縣竹南鎮」
    var cityDistrict: String { city + (district ?? "") }
    /// 完整地址，縣市只寫一次
    var fullAddress: String { city + rest }

    private static let englishTable: [String: String] = [
        "台北": "Taipei", "新北": "New Taipei", "桃園": "Taoyuan", "台中": "Taichung",
        "台南": "Tainan", "高雄": "Kaohsiung", "基隆": "Keelung", "新竹": "Hsinchu",
        "嘉義": "Chiayi", "苗栗": "Miaoli", "彰化": "Changhua", "南投": "Nantou",
        "雲林": "Yunlin", "屏東": "Pingtung", "宜蘭": "Yilan", "花蓮": "Hualien",
        "台東": "Taitung", "澎湖": "Penghu", "金門": "Kinmen", "連江": "Matsu"
    ]

    /// 22 縣市（臺／台兩種寫法都認）
    private static let counties: [String] = [
        "台北市", "新北市", "桃園市", "台中市", "台南市", "高雄市", "基隆市", "新竹市", "嘉義市",
        "新竹縣", "苗栗縣", "彰化縣", "南投縣", "雲林縣", "嘉義縣", "屏東縣", "宜蘭縣", "花蓮縣",
        "台東縣", "澎湖縣", "金門縣", "連江縣"
    ]

    private static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "臺", with: "台").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func englishName(_ city: String) -> String? {
        let c = normalize(city)
        guard !c.isEmpty else { return nil }
        if c.unicodeScalars.allSatisfy({ $0.isASCII }) { return c }
        guard c.count >= 2 else { return nil }
        return englishTable[String(c.prefix(2))]
    }

    /// 地址開頭的郵遞區號（半形、全形數字）和空白
    private static func isLeadingJunk(_ ch: Character) -> Bool {
        if ch == " " || ch == "\u{3000}" { return true }
        if ch.isASCII { return ch.isNumber }
        return "０１２３４５６７８９".contains(ch)
    }

    static func make(_ re: RealEstate) -> HousePlace {
        var p = HousePlace()
        p.city = re.city.trimmingCharacters(in: .whitespacesAndNewlines)
        var a = Substring(re.address.trimmingCharacters(in: .whitespacesAndNewlines))
        // 郵遞區號、空白
        while let ch = a.first, isLeadingJunk(ch) {
            a = a.dropFirst()
        }
        let na = normalize(String(a))
        let nc = normalize(p.city)
        if !nc.isEmpty, na.hasPrefix(nc) {
            a = a.dropFirst(nc.count)
            // 縣市只填「苗栗」、地址寫「苗栗縣…」時把剩下的「縣」去掉
            if let ch = a.first, ch == "縣" || ch == "市" { a = a.dropFirst() }
        } else {
            for county in counties where na.hasPrefix(county) {
                a = a.dropFirst(county.count)
                if p.city.isEmpty { p.city = county }
                break
            }
        }
        p.rest = String(a).trimmingCharacters(in: .whitespacesAndNewlines)
        // 鄉鎮市區：取到第一個「鄉／鎮／市／區」為止，最多 4 個字
        let head = Array(p.rest.prefix(4))
        for (i, ch) in head.enumerated() where i >= 1 && "鄉鎮市區".contains(ch) {
            p.district = String(head[0...i])
            break
        }
        p.english = englishName(p.city)
        return p
    }
}

// MARK: - 看板

extension HouseCardData {
    fileprivate static func boardData(_ c: HouseBuildContext, name: String, place: HousePlace, isBlank: Bool) -> HouseBoardData {
        let re = c.re
        let f = c.facts
        var b = HouseBoardData()
        let rented = re.monthlyRental > 0 && !re.isSold
        let first = re.isSold ? "So long," : (rented ? "Home pays back," : "Welcome home,")
        b.greeting = [first, place.english ?? "sweet home!"]

        if re.isSold {
            b.date = [place.cityDistrict, "已售出"].filter { !$0.isEmpty }.joined(separator: "・")
            b.dateIcon = "checkmark.seal.fill"
            if let sold = re.soldDate, let held = HouseCardFormat.lived(from: re.purchaseDate, to: sold) {
                b.capsule = "持有 " + held
                b.capsuleIcon = "clock.fill"
            }
            let diff = f.value - re.purchasePrice
            b.label = "賣出價差"
            b.big = FinanceText.signed(diff)
            b.bigTone = MoneyTone.change(diff, base: re.purchasePrice > 0 ? re.purchasePrice : 1)
            let boughtAt = HouseCardFormat.ym(re.purchaseDate)
            let soldAt = HouseCardFormat.ym(re.soldDate ?? c.asOf)
            var s = "\(boughtAt) 用 \(MoneyFormat.short(re.purchasePrice)) 買 → \(soldAt) 用 \(MoneyFormat.short(f.value)) 賣"
            // 成交價沒填用估值；估值也是 0 時 HouseFacts 退回購入價，不能寫成「用估值」
            if (re.soldPrice ?? 0) <= 0 { s += f.valueIsFallback ? "（成交價沒填，先用購入價）" : "（用估值當賣價）" }
            b.line = HouseLine.text(s)
            b.accessibilityText = "\(name)，已售出，賣出價差 \(FinanceText.signed(diff))，\(s)"
            return b
        }

        b.date = [place.cityDistrict, typeText(re)].filter { !$0.isEmpty }.joined(separator: "・")
        b.dateIcon = "house.fill"
        var spokenCapsule = ""
        if !f.valueIsFallback, re.purchasePrice > 0 {
            let r = f.value / re.purchasePrice - 1
            if abs(r) < 0.005 {
                b.capsule = "持平"
                b.capsuleIcon = "equal.circle.fill"
                spokenCapsule = "跟買價持平"
            } else if r > 0 {
                b.capsule = "增值 ▲" + FinanceText.percent1(r)
                b.capsuleIcon = "chart.line.uptrend.xyaxis"
                b.capsuleTone = .up
                spokenCapsule = "增值 " + FinanceText.percent1(r)
            } else {
                b.capsule = "跌價 ▼" + FinanceText.percent1(-r)
                b.capsuleIcon = "chart.line.downtrend.xyaxis"
                b.capsuleTone = .down
                spokenCapsule = "跌價 " + FinanceText.percent1(-r)
            }
        }
        b.label = f.valueIsFallback ? "房屋估值（還沒填，先用購入價）" : "房屋估值"
        b.big = MoneyFormat.short(f.value)

        var spokenLine = ""
        if !f.hasMortgage {
            let s = isBlank ? "還沒有房貸和花費，從下面「我的帳本」記第一筆" : "沒有房貸，整間都是你的"
            b.line = HouseLine.text(s)
            spokenLine = s
        } else if f.isPaidOff {
            b.line = HouseLine.text("房貸繳完了，整間都是你的")
            spokenLine = b.line.plain
        } else if c.notStarted, let firstDue = f.firstDue {
            let month = HouseFacts.monthStart(firstDue, c.cal)
            let monthly = c.monthlyMortgage(inMonth: month)
            b.line = HouseLine(runs: [
                HouseRun(text: "房貸 " + HouseCardFormat.ym(firstDue) + " 開始・到時每月 "),
                HouseRun(text: MoneyFormat.short(monthly), bold: true)
            ])
            spokenLine = b.line.plain
        } else if f.owedIsScheduled {
            b.line = HouseLine(runs: [
                HouseRun(text: "房貸還要繳 "),
                HouseRun(text: MoneyFormat.short(f.owed), bold: true),
                HouseRun(text: "（含利息）")
            ])
            spokenLine = b.line.plain
        } else {
            let equity = f.value - f.owed
            let tone: MoneyTone = equity >= 0 ? .good : .bad
            let about = f.owedIsEstimate ? "約 " : ""
            let share: Double = f.value > 0 ? max(0, equity) / f.value : 0
            let shareText = f.value > 0 ? "（" + MoneyFormat.percent(share) + "）" : ""
            b.line = HouseLine(runs: [
                HouseRun(text: "扣掉房貸，真正是你的 " + about),
                HouseRun(text: MoneyFormat.short(equity), bold: true, tone: tone),
                HouseRun(text: shareText)
            ])
            let aboutSpoken = f.owedIsEstimate ? "約 " : " "
            spokenLine = "扣掉房貸真正是你的\(aboutSpoken)\(HouseCardFormat.spoken(equity))"
            if f.value > 0 { spokenLine += "，占 " + MoneyFormat.percent(share) }
        }
        var spoken = "\(name)，\(b.label) \(HouseCardFormat.spoken(f.value))"
        if !spokenCapsule.isEmpty { spoken += "，" + spokenCapsule }
        spoken += "，" + spokenLine
        b.accessibilityText = spoken
        return b
    }

    /// 「透天 4 層」「大樓 12F」「透天」
    fileprivate static func typeText(_ re: RealEstate) -> String {
        if re.buildingType == .apartment {
            if let span = towerSpan(re) {
                return "大樓 " + (span.lowerBound == span.upperBound ? "\(span.lowerBound)F" : "\(span.lowerBound)–\(span.upperBound)F")
            }
            return "大樓"
        }
        return re.floors.isEmpty ? "透天" : "透天 \(re.floors.count) 層"
    }

    /// 大樓你的那幾層：FloorLabel 解析 → 舊的 fromFloor／toFloor；都沒有回 nil。最多算到 200 樓。
    fileprivate static func towerSpan(_ re: RealEstate) -> ClosedRange<Int>? {
        var lo = 0
        var hi = 0
        if let span = FloorLabel.aboveGroundSpan(re.floors) {
            lo = span.lowerBound
            hi = span.upperBound
        } else if re.fromFloor > 0 {
            lo = re.fromFloor
            hi = max(re.fromFloor, re.toFloor)
        } else {
            return nil
        }
        hi = min(hi, 200)
        lo = min(max(1, lo), hi)
        return lo...hi
    }

    // MARK: 看板下的房貸進度

    fileprivate static func progressData(_ c: HouseBuildContext) -> HouseProgressData? {
        let f = c.facts
        guard f.hasMortgage, !c.re.isSold, !f.isPaidOff,
              let firstDue = f.firstDue, let payoff = f.payoffDate else { return nil }
        var p = HouseProgressData()
        p.notStarted = c.notStarted
        p.range = HouseCardFormat.ym(firstDue) + " → " + HouseCardFormat.ym(payoff)
        let totalMonths = max(1, HouseCardFormat.monthsBetween(firstDue, payoff))
        if !c.notStarted {
            let gone = Double(HouseCardFormat.monthsBetween(firstDue, c.asOf)) / Double(totalMonths)
            p.fraction = min(1, max(0, gone))
        }
        var seen = Set<String>()
        for s in f.segments.dropFirst() {
            let label = HouseCardFormat.ym(s.firstDue)
            let x = Double(HouseCardFormat.monthsBetween(firstDue, s.firstDue)) / Double(totalMonths)
            guard x > 0, x < 1, seen.insert(label).inserted else { continue }
            p.ticks.append(HouseProgressData.Tick(fraction: x, label: label))
        }
        p.dotPill = c.notStarted ? "還沒開始" : "今天"
        p.endPill = HouseCardFormat.ym(payoff) + " 繳完"

        let thisMonth = HouseFacts.monthStart(c.asOf, c.cal)
        let parallel = f.segments.filter { $0.isPaying(inMonth: thisMonth, calendar: c.cal) }.count
        if c.notStarted {
            p.left = "第一期 " + HouseCardFormat.ym(firstDue)
        } else {
            p.left = "已繳 \(f.paidCount) 期" + (parallel >= 2 ? "（\(parallel) 筆同時在繳）" : "")
        }
        let remaining = max(0, f.totalCount - f.paidCount)
        p.right = "還有 \(remaining) 期"
        if let span = HouseCardFormat.span(months: HouseCardFormat.monthsBetween(c.asOf, payoff)) {
            p.right += "（" + span + "）"
        }

        // 還沒開始要先判斷：這時 HouseFacts.nextChange 多半就是「第一期那個月從 0 變成 M」，寫「改繳」會像是月付變了
        if c.notStarted {
            let monthly = c.monthlyMortgage(inMonth: HouseFacts.monthStart(firstDue, c.cal))
            p.note = "\(HouseCardFormat.ym(firstDue)) 開始・每月 \(MoneyFormat.short(monthly))"
        } else if let change = f.nextChange {
            let month = HouseCardFormat.ym(change.month)
            if change.monthly >= 1 {
                p.note = "\(month) 起每月改繳 \(MoneyFormat.short(change.monthly))"
            } else {
                p.note = "\(month) 起暫時不用繳"
            }
        } else if f.monthlyMortgage > 0 {
            p.note = "每月 \(MoneyFormat.short(f.monthlyMortgage))，繳到 \(HouseCardFormat.ym(payoff))"
        }
        var spoken = c.notStarted ? "還沒開始，" + p.left : p.left
        spoken += "，\(p.right)，\(p.endPill)"
        if !p.note.isEmpty { spoken += "。" + p.note }
        p.accessibilityText = spoken
        return p
    }

    // MARK: 看板下的膠囊

    fileprivate static func chipsData(_ c: HouseBuildContext, ledger: HouseLedger, livingTotal: Double) -> [MoneyBoardChip] {
        let re = c.re
        let f = c.facts
        var out: [MoneyBoardChip] = []
        if re.isSold {
            let diff = f.value - re.purchasePrice
            var interest: Double? = 0
            if f.hasMortgage {
                interest = f.hasStarted ? f.interestPaid : 0
            }
            if let i = interest, i > 0 {
                out.append(MoneyBoardChip(icon: "percent", label: "付掉的利息", value: MoneyFormat.short(i)))
            }
            let holding = ledger.rawTotals[.holding] ?? 0
            if holding > 0 {
                out.append(MoneyBoardChip(icon: "wrench.and.screwdriver.fill", label: "持有花費", value: MoneyFormat.short(holding)))
            }
            // 算不出利息時不寫「實際」：少扣一大塊會把賺賠算錯
            if let i = interest, re.purchasePrice > 0 {
                let oneTime = ledger.rawTotals[.oneTime] ?? 0
                let z = diff - i - oneTime - holding
                out.append(MoneyBoardChip(icon: "equal.circle.fill", label: "扣掉這些實際", value: FinanceText.signed(z),
                                          tone: MoneyTone.change(z, base: re.purchasePrice)))
            }
            return out
        }
        if re.purchasePrice > 0 {
            out.append(MoneyBoardChip(icon: "cart.fill", label: "購入", value: MoneyFormat.short(re.purchasePrice)))
            let gain = f.value - re.purchasePrice
            if !f.valueIsFallback, abs(gain) >= 1 {
                out.append(MoneyBoardChip(icon: gain > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                                          label: "增值", value: FinanceText.signed(gain),
                                          tone: MoneyTone.change(gain, base: re.purchasePrice)))
            }
        }
        if f.monthlyMortgage >= 1 {
            out.append(MoneyBoardChip(icon: "building.columns.fill", label: "月貸", value: MoneyFormat.short(f.monthlyMortgage)))
        }
        if livingTotal >= 1 {
            out.append(MoneyBoardChip(icon: "house.fill", label: "住這裡每月", value: "約 " + MoneyFormat.short(livingTotal)))
        }
        let rented = re.monthlyRental > 0
        if let held = HouseCardFormat.lived(from: re.purchaseDate, to: c.asOf) {
            out.append(MoneyBoardChip(icon: "clock.fill", label: rented ? "持有" : "住了", value: held))
        }
        if rented {
            var v = MoneyFormat.short(re.monthlyRental)
            if f.value > 0 { v += "・報酬 " + FinanceText.percent1(re.monthlyRental * 12 / f.value) }
            out.append(MoneyBoardChip(icon: "tag.fill", label: "月租", value: v, tone: .good))
        }
        return out
    }

    // MARK: 風景

    fileprivate static func sceneModel(_ c: HouseBuildContext, name: String) -> HouseSceneModel {
        let re = c.re
        let f = c.facts
        let shape: HouseSceneModel.Shape
        if re.buildingType == .apartment {
            let span = towerSpan(re) ?? (1...1)
            let label = span.lowerBound == span.upperBound ? "\(span.lowerBound)F" : "\(span.lowerBound)–\(span.upperBound)F"
            shape = .tower(ownedLow: span.lowerBound, ownedHigh: span.upperBound,
                           totalFloors: max(span.upperBound + 2, 6), label: label)
        } else {
            let floors: [HouseSceneFloor] = FloorLabel.sorted(re.floors).map { fl -> HouseSceneFloor in
                let parsed = FloorLabel.parse(fl.floorNumber)
                var isBasement = false
                var isRoof = false
                var label = parsed.short
                switch parsed.kind {
                case .basement: isBasement = true
                case .roof: isRoof = true
                case .mezzanine: label = "M"
                default: break
                }
                return HouseSceneFloor(label: label, isBasement: isBasement, isRoof: isRoof, rooms: fl.functions)
            }
            shape = .house(floors: floors, hasElevator: re.hasElevator)
        }
        // 賣掉時房貸已經結清、還沒開始扣的也還不欠：都不畫斜線
        let owed: Double = (re.isSold || c.notStarted) ? 0 : f.owed
        let fraction: Double = f.value > 0 ? min(1, owed / f.value) : 0
        var owedLabel: String? = nil
        if owed > 0 {
            owedLabel = (f.owedIsScheduled ? "還要繳 " : "房貸 ") + MoneyFormat.percent(fraction)
        }
        return HouseSceneModel(shape: shape, owedFraction: fraction, owedLabel: owedLabel,
                               isRented: re.monthlyRental > 0 && !re.isSold, isSold: re.isSold,
                               notStarted: c.notStarted, name: MoneyBoardText.short(name, max: 8))
    }
}

// MARK: - 房貸區

extension HouseCardData {
    fileprivate static func mortgageData(_ c: HouseBuildContext) -> HouseMortgageData? {
        let re = c.re
        let f = c.facts
        guard f.hasMortgage, let payoff = f.payoffDate else { return nil }
        var m = HouseMortgageData()
        let n = f.segments.count
        if re.isSold {
            m.trailing = "\(n) 段・" + HouseCardFormat.ym(re.soldDate ?? c.asOf) + " 賣出"
            m.soldNote = "房子 " + HouseCardFormat.ym(re.soldDate ?? c.asOf) + " 賣掉了，房貸算到那天"
        } else {
            m.trailing = "\(n) 段・" + HouseCardFormat.ym(payoff) + " 繳完"
            m.tiles = mortgageTiles(c, payoff: payoff)
            if f.principal == nil {
                m.principalHint = "填上當初跟銀行借多少，就能算出還欠多少本金、付了多少利息 →"
            } else if f.monthlyRate == nil {
                m.principalHint = "借款本金跟每期金額對不起來，先只算含利息的數字；借款本金可以在「編輯」改 →"
            }
            m.totalLine = mortgageTotalLine(f)
            if f.monthlyRate != nil, f.hasStarted, let iy = f.interestThisYear, iy >= 1 {
                var runs = [HouseRun(text: "今年付的利息約 "), HouseRun(text: MoneyFormat.short(iy), bold: true)]
                if re.monthlyRental <= 0 { runs.append(HouseRun(text: "（自住房貸利息，報稅每年最多列舉 30 萬）")) }
                m.interestLine = HouseLine(runs: runs)
            }
            if f.principal != nil, f.monthlyRate != nil {
                m.footnote = "本金和利息是用借款本金和每期金額反推的（等於一個平均利率），跟銀行對帳單會差幾千元；借款本金可以在「編輯」改。"
            }
        }
        m.steps = mortgageSteps(c)
        m.showChart = !re.isSold && !m.steps.isEmpty
        if let first = m.steps.map(\.start).min(), let last = m.steps.map(\.end).max() {
            m.chartStart = first
            m.chartEnd = last
            m.axisDates = axisDates(from: first, to: last)
            if !re.isSold, c.asOf >= first, c.asOf <= last { m.today = c.asOf }
        }
        m.chartMax = m.steps.map(\.yEnd).max() ?? 0
        m.rows = f.segments.enumerated().map { segmentRow(c, segment: $0.element, index: $0.offset + 1) }
        let lastDue = f.segments.compactMap { $0.lastScheduledDue ?? $0.lastCountedDue }.max()
        m.newSegmentStart = lastDue ?? c.now
        return m
    }

    fileprivate static func mortgageTiles(_ c: HouseBuildContext, payoff: Date) -> [HouseTile] {
        let f = c.facts
        let sourceText: String
        switch f.principalSource {
        case .entered: sourceText = "你填的"
        case .ledger: sourceText = "記帳裡的"
        case .estimated: sourceText = "推算"
        case .unknown: sourceText = ""
        }
        let full = f.principal != nil && f.monthlyRate != nil && f.balance != nil
        var left = HouseCardFormat.span(months: HouseCardFormat.monthsBetween(c.asOf, payoff)).map { "還有 " + $0 } ?? ""
        if f.isPaidOff { left = "已全部繳完" }
        let payoffTile = HouseTile(label: "繳完", value: HouseCardFormat.ym(payoff), sub: left)
        let paidTile = HouseTile(label: "已繳", value: HouseCardFormat.compact(f.paid), sub: "\(f.paidCount) 期")
        let leftTile = HouseTile(label: "還要繳", value: HouseCardFormat.compact(f.left), sub: "含利息")
        var principalTile: HouseTile? = nil
        if let p = f.principal {
            principalTile = HouseTile(label: "借款本金", value: HouseCardFormat.compact(p), sub: sourceText,
                                      tap: .edit(.loanPrincipal))
        }
        // 還沒開始扣：HouseFacts 在第一段起始日之前把還欠算成 0，已還本金、已付利息會變成怪數字，不放這兩格
        let repaid: Double = f.hasStarted ? (f.principalRepaid ?? 0) : 0
        let interest: Double = f.hasStarted ? (f.interestPaid ?? 0) : 0
        let interestTile = HouseTile(label: "已付利息", value: HouseCardFormat.compact(interest),
                                     sub: (repaid < interest ? "本金只還了 " : "本金還了 ") + HouseCardFormat.compact(repaid))

        if f.isPaidOff {
            if full, let pt = principalTile { return [pt, interestTile, payoffTile] }
            return [paidTile, payoffTile]
        }
        if c.notStarted {
            var tiles: [HouseTile] = []
            if let pt = principalTile { tiles.append(pt) }
            tiles.append(leftTile)
            tiles.append(payoffTile)
            return tiles
        }
        if full, let pt = principalTile, let b = f.balance {
            let owedTile = HouseTile(label: "還欠本金", value: HouseCardFormat.compact(b), sub: "到今天")
            return [pt, owedTile, interestTile, paidTile, leftTile, payoffTile]
        }
        return [paidTile, leftTile, payoffTile]
    }

    fileprivate static func mortgageTotalLine(_ f: HouseFacts) -> HouseLine {
        let s = f.scheduledTotal
        if let p = f.principal, let r = f.monthlyRate, s > p {
            return HouseLine(runs: [
                HouseRun(text: "全部繳完總共 "),
                HouseRun(text: MoneyFormat.short(s), bold: true),
                HouseRun(text: "，其中利息約 "),
                HouseRun(text: MoneyFormat.short(s - p), bold: true),
                HouseRun(text: "・換算年利率約 " + FinanceText.percent1(r * 12))
            ])
        }
        return HouseLine(runs: [
            HouseRun(text: "全部繳完總共 "),
            HouseRun(text: MoneyFormat.short(s), bold: true),
            HouseRun(text: "（含利息）")
        ])
    }

    fileprivate static func mortgageSteps(_ c: HouseBuildContext) -> [HouseMortgageData.Step] {
        let cal = c.cal
        var out: [HouseMortgageData.Step] = []
        for (i, s) in c.facts.segments.enumerated() {
            guard s.countedPeriods > 0, let end = s.lastCountedDue else { continue }
            let start = s.firstDue
            let ms = HouseFacts.monthStart(start, cal)
            let me = HouseFacts.monthStart(end, cal)
            // 跟前面的段在同一段時間都在繳：疊在它們上面
            var base = 0.0
            for prev in out {
                let ps = HouseFacts.monthStart(prev.start, cal)
                let pe = HouseFacts.monthStart(prev.end, cal)
                if ps <= me && ms <= pe { base = max(base, prev.yEnd) }
            }
            let paidUntil: Date? = s.paidPeriods > 0 ? s.due(s.paidPeriods, calendar: cal) : nil
            let caption = "\(s.displayTitle)・\(HouseCardFormat.ym(start))–\(HouseCardFormat.ym(end))・每月 \(MoneyFormat.short(s.monthly))"
            out.append(HouseMortgageData.Step(id: s.id, index: i + 1, start: start, end: end, paidUntil: paidUntil,
                                              yStart: base, yEnd: base + s.monthly, monthly: s.monthly,
                                              annotation: HouseCardFormat.compact(s.monthly), caption: caption))
        }
        return out
    }

    /// 橫軸刻度：40 年的房貸每 10 年一格，短的縮成 5、2、1 年
    fileprivate static func axisDates(from a: Date, to b: Date) -> [Date] {
        let cal = HouseCardFormat.calendar
        let y0 = cal.component(.year, from: a)
        let y1 = cal.component(.year, from: b)
        let span = max(0, y1 - y0)
        let step = span > 20 ? 10 : (span > 10 ? 5 : (span > 4 ? 2 : 1))
        var out: [Date] = []
        var y = y0
        while y <= y1 + step && out.count < 30 {
            if let d = cal.date(from: DateComponents(year: y, month: 1, day: 1)) { out.append(d) }
            y += step
        }
        return out
    }

    fileprivate static func segmentRow(_ c: HouseBuildContext, segment s: HouseFacts.Segment, index: Int) -> HouseMortgageData.Row {
        let re = c.re
        let status: HouseMortgageData.Status
        let finishedBeforeSale = s.paidPeriods >= s.scheduledPeriods && s.scheduledPeriods > 0
        if re.isSold && !finishedBeforeSale {
            status = .soldSettled
        } else if s.isDone || finishedBeforeSale {
            status = s.scheduledPeriods < s.contractPeriods ? .stopped : .done
        } else if !s.hasStarted {
            status = .notStarted
        } else {
            status = .paying
        }
        let badge: String
        let statusText: String
        var progress: Double? = nil
        var nextText: String? = nil
        switch status {
        case .paying:
            badge = "\(index)"
            statusText = "第 \(s.paidPeriods)／\(s.countedPeriods) 期"
            progress = s.countedPeriods > 0 ? Double(s.paidPeriods) / Double(s.countedPeriods) : nil
            if let next = s.nextDue(onOrAfter: c.asOf, calendar: c.cal) {
                nextText = "下次 \(HouseCardFormat.shortDate(next.date, now: c.asOf)) 扣款"
            }
        case .notStarted:
            badge = "\(index)"
            statusText = HouseCardFormat.ym(s.firstDue) + " 開始"
        case .done:
            badge = ""
            statusText = "已繳完"
        case .stopped:
            badge = "停"
            statusText = "已停止 " + HouseCardFormat.ym(s.endDate ?? s.lastScheduledDue ?? s.firstDue)
        case .soldSettled:
            badge = "\(index)"
            statusText = "賣出時結清"
        }
        var range = HouseCardFormat.ym(s.firstDue)
        if let last = s.lastCountedDue, s.countedPeriods > 1 { range += " – " + HouseCardFormat.ym(last) }
        range += "・\(s.countedPeriods) 期"
        let unit: String
        switch s.periodMonths {
        case 3: unit = "/季"
        case 12: unit = "/年"
        default: unit = "/月"
        }
        let amount = MoneyFormat.short(s.perPeriod) + unit
        let missing = c.termMissing(s)
        var spoken = "\(s.displayTitle)，\(range)，\(amount)，\(statusText)"
        if let nextText { spoken += "，" + nextText }
        if !s.isLinked { spoken += "，沒連到記帳" }
        if missing { spoken += "，期數沒填" }
        return HouseMortgageData.Row(id: s.id, segment: s, index: index, status: status, badge: badge,
                                     title: s.displayTitle, range: range, amount: amount, statusText: statusText,
                                     progress: progress, nextText: nextText, isUnlinked: !s.isLinked,
                                     termMissing: missing, accessibilityText: spoken)
    }
}

// MARK: - 每個月住這裡、出租

extension HouseCardData {
    fileprivate static func livingData(_ c: HouseBuildContext, ledger: HouseLedger) -> HouseLivingData? {
        let re = c.re
        let f = c.facts
        guard !re.isSold else { return nil }
        let cal = c.cal

        // 期間＝max(購入日, asOf − 12 個月) 到 asOf
        let back = cal.date(byAdding: .month, value: -12, to: c.asOf) ?? c.asOf
        let start = max(re.purchaseDate, back)
        let comps = cal.dateComponents([.month, .day], from: start, to: c.asOf)
        let months = min(12, max(1, (comps.month ?? 0) + ((comps.day ?? 0) >= 15 ? 1 : 0)))
        let startDay = cal.startOfDay(for: start)

        // 持有花費：帳本「持有」裡同一批列（固定支出年列另外算成每月）
        var utility = 0.0
        var taxIns = 0.0
        var upkeep = 0.0
        for e in ledger.events where e.bucket == .holding && !e.isYearRow && cal.startOfDay(for: e.date) >= startDay {
            switch e.mark {
            case .utility: utility += e.amount
            case .tax, .insurance: taxIns += e.amount
            default: upkeep += e.amount
            }
        }
        // 稅費、保險一年繳一次，一律 ÷ 12；其他 ÷ 期間月數
        let utilityM = utility / Double(months)
        let taxInsM = taxIns / 12
        let upkeepM = upkeep / Double(months)

        // 固定費用：連到這間、不是貸款、這個月還沒過結束日的週期固定支出，換算成每月
        var fixed = 0.0
        let thisMonth = HouseFacts.monthStart(c.asOf, cal)
        for ex in c.expenses where ex.linkedRealEstateId == re.id && ex.isRecurringFixed
            && ex.fixedCategory != .loan && !c.excluded.contains(ex.id) {
            guard let rec = ex.recurrence else { continue }
            if let end = ex.endDate, cal.startOfDay(for: end) < thisMonth { continue }
            guard c.onOrBeforeAsOf(ex.date) else { continue }
            fixed += c.amount(ex) / Double(max(1, rec.periodMonths))
        }

        // 房貸：這個月的月貸 M；算得出利率時拆成利息 B×r 和還本金
        let mortgage = f.monthlyMortgage
        var interest = 0.0
        var principal = 0.0
        let canSplit = mortgage > 0 && f.monthlyRate != nil && f.owedIsPrincipal
        if canSplit, let r = f.monthlyRate {
            interest = min(mortgage, max(0, f.owed) * r)
            principal = max(0, mortgage - interest)
        }

        var raw: [(kind: HouseLivingData.Kind, label: String, value: Double, tap: HouseTap)] = []
        if canSplit {
            raw.append((kind: .interest, label: "利息", value: interest, tap: .scrollToMortgage))
            raw.append((kind: .principal, label: "還本金", value: principal, tap: .scrollToMortgage))
        } else if mortgage > 0 {
            raw.append((kind: .mortgage, label: "房貸", value: mortgage, tap: .scrollToMortgage))
        }
        raw.append((kind: .fixed, label: "管理費等固定費用", value: fixed, tap: .ledgerFilter(.holding)))
        raw.append((kind: .utility, label: "水電瓦斯", value: utilityM, tap: .ledgerFilter(.holding)))
        raw.append((kind: .taxInsurance, label: "稅費・保險", value: taxInsM, tap: .ledgerFilter(.holding)))
        raw.append((kind: .upkeep, label: "維修・清潔・其他", value: upkeepM, tap: .ledgerFilter(.holding)))
        raw = raw.filter { $0.value > 0.5 }
        let rawTotal = raw.reduce(0.0) { $0 + $1.value }
        guard rawTotal >= 1 else { return nil }

        // 分到百位，各段相加＝合計
        let total = HouseRound.round(rawTotal, unit: 100)
        let shares = HouseRound.largestRemainder(raw.map { $0.value }, total: total, unit: 100)
        var l = HouseLivingData()
        l.total = total
        l.trailing = "近 \(months) 個月平均"
        l.headline = "平均每月 約 " + MoneyFormat.short(total)
        for (i, item) in raw.enumerated() where shares[i] > 0 {
            l.parts.append(HouseLivingData.Part(kind: item.kind, label: item.label, value: shares[i],
                                                valueText: MoneyFormat.short(shares[i]), tap: item.tap))
        }
        if canSplit {
            let principalShare = l.parts.first(where: { $0.kind == .principal })?.value ?? 0
            let spent = total - principalShare
            var runs = [HouseRun(text: "真正花掉的是 約 "), HouseRun(text: MoneyFormat.short(spent), bold: true)]
            if principalShare > 0 {
                runs.append(HouseRun(text: "（利息＋持有花費）；"))
                runs.append(HouseRun(text: MoneyFormat.short(principalShare), bold: true))
                runs.append(HouseRun(text: " 是在還本金，會變成你的。"))
            } else {
                runs.append(HouseRun(text: "（利息＋持有花費）。"))
            }
            l.summary = HouseLine(runs: runs)
        } else if mortgage > 0 {
            l.splitHint = "填上當初借多少，就能分出利息和本金"
        }
        let oneYear = cal.date(byAdding: .year, value: 1, to: re.purchaseDate) ?? re.purchaseDate
        let hasTax = ledger.events.contains { $0.mark == .tax }
        if c.asOf < oneYear && !hasTax {
            l.firstYearHint = "買進還不到一年，房屋稅（5 月）和地價稅（11 月）可能還沒繳到，這裡會先偏低。"
        }
        return l
    }

    fileprivate static func rentalData(_ c: HouseBuildContext, livingTotal: Double) -> HouseRentalData? {
        let re = c.re
        let f = c.facts
        let rent = re.monthlyRental
        guard rent > 0, !re.isSold else { return nil }
        var r = HouseRentalData()
        r.trailing = "月租 " + MoneyFormat.short(rent)
        r.tiles.append(HouseTile(label: "月租", value: HouseCardFormat.compact(rent)))
        if f.value > 0 {
            r.tiles.append(HouseTile(label: "年報酬", value: FinanceText.percent1(rent * 12 / f.value),
                                     sub: f.valueIsFallback ? "用購入價算" : "用估值算"))
        }
        let m = f.monthlyMortgage
        if m >= 1 {
            let ratio = rent / m
            r.tiles.append(HouseTile(label: "租金付掉房貸", value: MoneyFormat.percent(ratio),
                                     sub: ratio > 1 ? "租金比房貸多" : ""))
            r.coverFraction = min(1, ratio)
            r.coverText = ratio > 1 ? "租金比房貸多" : "租金付掉房貸 " + MoneyFormat.percent(ratio)
        }
        let net = rent - livingTotal
        r.net = net
        r.line = HouseLine(runs: [
            HouseRun(text: "扣掉房貸和住這裡的花費，每月實際" + (net >= 0 ? "多 " : "貼 ")),
            HouseRun(text: MoneyFormat.short(abs(net)), bold: true, tone: net >= 0 ? .good : .bad)
        ])
        return r
    }
}

// MARK: - 房屋資料、樓層、水電、電梯、照片

extension HouseCardData {
    fileprivate static func infoData(_ c: HouseBuildContext, place: HousePlace) -> HouseInfoData {
        let re = c.re
        let f = c.facts
        var info = HouseInfoData()
        var rows: [HouseInfoData.Row] = []

        let ping = re.pingCount
        let typeName = re.buildingType.rawValue
        info.trailing = ping > 0 ? "\(typeName)・\(HouseCardFormat.number1(ping)) 坪" : typeName

        let address = place.fullAddress
        if !address.isEmpty {
            rows.append(.init(id: "address", label: "地址", value: address, kind: .address))
            info.addressQuery = address
        }

        var typeValue = typeName
        if re.buildingType == .apartment {
            if let span = towerSpan(re) {
                typeValue += "・" + (span.lowerBound == span.upperBound ? "\(span.lowerBound)F" : "\(span.lowerBound)–\(span.upperBound)F")
            }
        } else {
            if !re.floors.isEmpty { typeValue += "・\(re.floors.count) 層" }
            if re.hasElevator { typeValue += "（有電梯）" }
        }
        // 空的新房子（沒樓層、沒電梯、預設的透天）不寫類型：那只是預設值，不是你填的
        if re.buildingType == .apartment || !re.floors.isEmpty || re.hasElevator {
            rows.append(.init(id: "type", label: "類型", value: typeValue))
        }

        if ping > 0 {
            rows.append(.init(id: "ping", label: "坪數",
                              value: pingText(ping)))
            if re.purchasePrice > 0 {
                let bought = HouseCardFormat.compact(re.purchasePrice / ping)
                var unit = "買進 \(bought)/坪"
                if !f.valueIsFallback {
                    let now = HouseCardFormat.compact(f.value / ping)
                    unit += re.isSold ? "・賣出 \(now)/坪" : "・現在 \(now)/坪"
                }
                rows.append(.init(id: "unitPrice", label: "單價", value: unit))
            }
        }

        var bought = HouseCardFormat.ymd(re.purchaseDate)
        if let held = HouseCardFormat.lived(from: re.purchaseDate, to: c.asOf) {
            let verb = (re.isSold || re.monthlyRental > 0) ? "持有 " : "住了 "
            bought += "・" + verb + held
        }
        rows.append(.init(id: "purchase", label: "購入", value: bought))

        if !re.isSold {
            if f.valueIsFallback {
                rows.append(.init(id: "value", label: "估值", value: "還沒填（先用購入價 " + MoneyFormat.short(f.value) + "）"))
            } else {
                var v = MoneyFormat.short(f.value)
                if let at = re.valueUpdatedAt { v += "・" + HouseCardFormat.ym(at) + " 更新" }
                rows.append(.init(id: "value", label: "估值", value: v))
                if let at = re.valueUpdatedAt, let limit = c.cal.date(byAdding: .month, value: 12, to: at), limit < c.now {
                    rows.append(.init(id: "valueStale", label: "", value: "估值一年沒更新了", kind: .warning))
                }
            }
        }

        let completions = re.buildingDeeds.compactMap(\.completionDate) + [re.bldgCompletionDate].compactMap { $0 }
        if let built = completions.min() {
            var v = HouseCardFormat.ym(built) + " 完工"
            let comps = c.cal.dateComponents([.year, .month], from: built, to: c.now)
            if let y = comps.year, y >= 1 {
                v += "・\(y) 年"
            } else if let m = comps.month, m >= 1 {
                v += "・\(m) 個月"
            }
            rows.append(.init(id: "age", label: "屋齡", value: v))
        }

        let owner = re.landOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        if !owner.isEmpty { rows.append(.init(id: "owner", label: "所有權人", value: owner)) }

        info.deeds = deedBlocks(re)
        if !info.deeds.isEmpty {
            var parts: [String] = []
            if !re.landDeeds.isEmpty { parts.append("土地 \(re.landDeeds.count) 份") }
            if !re.buildingDeeds.isEmpty { parts.append("建物 \(re.buildingDeeds.count) 份") }
            rows.append(.init(id: "deeds", label: "權狀", value: parts.joined(separator: "・"), kind: .deeds))
        }

        for item in re.insuranceItems {
            let linked = item.linkedExpenseId.flatMap { c.byId[$0] }
            let price = linked.map { c.amount($0) } ?? item.amount
            let policy = item.policyNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            guard price > 0 || !policy.isEmpty else { continue }
            var name = linked.map { HouseCardFormat.cleanTitle($0.title, estateName: re.name) } ?? ""
            if name == "保險" || name == policy { name = "" }
            let head = [name, policy.isEmpty ? "" : "No." + policy].filter { !$0.isEmpty }.joined(separator: " ")
            let value = [head.isEmpty ? "未填險號" : head, price > 0 ? MoneyFormat.short(price) : ""]
                .filter { !$0.isEmpty }.joined(separator: "・")
            rows.append(.init(id: "ins-" + item.id.uuidString, label: "保險", value: value,
                              kind: .insurance(linked?.id)))
        }

        if re.isSold, let sold = re.soldDate {
            let v: String
            if let price = re.soldPrice, price > 0 {
                v = HouseCardFormat.ymd(sold) + "・成交 " + MoneyFormat.short(price)
            } else if f.valueIsFallback {
                v = "\(HouseCardFormat.ymd(sold))・成交價沒填（先用購入價 \(MoneyFormat.short(f.value))）"
            } else {
                v = "\(HouseCardFormat.ymd(sold))・用估值 \(MoneyFormat.short(f.value)) 當賣價"
            }
            rows.append(.init(id: "sold", label: "售出", value: v))
        }

        let note = re.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { rows.append(.init(id: "note", label: "備註", value: note, kind: .note)) }

        info.rows = rows
        if address.isEmpty && ping <= 0 && re.floors.isEmpty {
            info.hint = "補上地址、坪數、樓層 → 編輯"
        }
        return info
    }

    /// 「45.2 坪（149.4 ㎡）」：㎡＝坪 × 3.3058
    fileprivate static func pingText(_ ping: Double) -> String {
        let m2 = HouseCardFormat.number1(ping * 3.3058)
        return "\(HouseCardFormat.number1(ping)) 坪（\(m2) ㎡）"
    }

    fileprivate static func deedBlocks(_ re: RealEstate) -> [HouseInfoData.DeedBlock] {
        var out: [HouseInfoData.DeedBlock] = []
        func row(_ id: String, _ label: String, _ value: String) -> HouseInfoData.Row? {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : HouseInfoData.Row(id: id, label: label, value: v)
        }
        for (i, d) in re.landDeeds.enumerated() {
            let title = "土地權狀" + (re.landDeeds.count > 1 ? " \(i + 1)" : "")
            let rows: [HouseInfoData.Row] = [
                row("situation", "坐落", d.situation),
                row("number", "地號", d.number),
                row("area", "面積", d.area > 0 ? HouseCardFormat.area(squareMeters: d.area) : "")
            ].compactMap { $0 }
            out.append(HouseInfoData.DeedBlock(id: d.id, title: title, rows: rows))
        }
        for (i, d) in re.buildingDeeds.enumerated() {
            let title = "建物權狀" + (re.buildingDeeds.count > 1 ? " \(i + 1)" : "")
            let rows: [HouseInfoData.Row] = [
                row("situation", "坐落", d.situation),
                row("number", "建號", d.number),
                row("address", "門牌", d.address),
                row("completion", "完工日", d.completionDate.map { HouseCardFormat.ymd($0) } ?? ""),
                row("usage", "用途", d.usage),
                row("annex", "附屬建物", d.annex),
                row("area", "面積", d.area > 0 ? HouseCardFormat.area(squareMeters: d.area) : "")
            ].compactMap { $0 }
            out.append(HouseInfoData.DeedBlock(id: d.id, title: title, rows: rows))
        }
        return out
    }

    fileprivate static func floorsData(_ c: HouseBuildContext) -> HouseFloorsData {
        let re = c.re
        var data = HouseFloorsData()
        let sorted = FloorLabel.sorted(re.floors)
        let labels = sorted.map { FloorLabel.parse($0.floorNumber) }

        // 家電掛哪一層：floorLocation 和 floorNumber 都用 FloorLabel 正規化後比對
        var byFloor: [UUID: [HouseFloorsData.Asset]] = [:]
        var assetCount = 0
        var assetTotal = 0.0
        for a in re.propertyAssets {
            let linked = a.linkedExpenseId.flatMap { c.byId[$0] }
            let price = linked.map { c.amount($0) } ?? a.amount
            let name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let brand = a.brand.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = [name.isEmpty ? a.category.rawValue : name, brand, price > 0 ? MoneyFormat.short(price) : ""]
                .filter { !$0.isEmpty }.joined(separator: "・")
            let asset = HouseFloorsData.Asset(id: a.id, text: text, price: price, expenseId: linked?.id)
            assetCount += 1
            assetTotal += max(0, price)
            let where_ = FloorLabel.parse(a.floorLocation)
            if let idx = labels.indices.first(where: { floorMatches(where_, labels[$0]) }) {
                byFloor[sorted[idx].id, default: []].append(asset)
            } else {
                data.otherAssets.append(asset)
            }
        }

        var itemTotal = 0
        var floors: [HouseFloorsData.Floor] = []
        for (i, fl) in sorted.enumerated() {
            let parsed = labels[i]
            let tree = nodeCount(fl.items)
            let assets = byFloor[fl.id] ?? []
            let count = tree + assets.count
            itemTotal += tree
            var isBasement = false
            var isRoof = false
            switch parsed.kind {
            case .basement: isBasement = true
            case .roof: isRoof = true
            default: break
            }
            let rooms = fl.functions.map(\.rawValue)
            let areaText: String? = fl.area > 0 ? HouseCardFormat.area(squareMeters: fl.area) : nil
            var spoken = spokenFloor(parsed)
            if !rooms.isEmpty { spoken += "，" + rooms.joined(separator: "、") }
            if fl.area > 0 { spoken += "，" + HouseCardFormat.number1(fl.area) + " 平方公尺" }
            spoken += "，\(count) 件東西"
            floors.append(HouseFloorsData.Floor(id: fl.id, label: parsed.short, isBasement: isBasement, isRoof: isRoof,
                                                rooms: rooms, areaText: areaText, treeCount: tree, assets: assets,
                                                countText: count > 0 ? "\(count) 件" : "", accessibilityText: spoken))
        }
        data.floors = floors.reversed()
        if assetCount > 0 {
            data.assetSummary = "家電家具 \(assetCount) 件" + (assetTotal > 0 ? "，共 " + MoneyFormat.short(assetTotal) : "")
        }
        data.isEmpty = re.floors.isEmpty && re.propertyAssets.isEmpty
        if !data.isEmpty {
            var parts: [String] = []
            if !re.floors.isEmpty { parts.append("\(re.floors.count) 層") }
            parts.append("\(itemTotal + assetCount) 件")
            data.trailing = parts.joined(separator: "・")
        }
        return data
    }

    /// 家電的位置（FloorLabel）是不是在這一層
    fileprivate static func floorMatches(_ a: FloorLabel, _ floor: FloorLabel) -> Bool {
        if a.kind == .unknown || floor.kind == .unknown {
            let x = a.raw.replacingOccurrences(of: " ", with: "").uppercased()
            let y = floor.raw.replacingOccurrences(of: " ", with: "").uppercased()
            return !x.isEmpty && x == y
        }
        if a.kind == floor.kind { return true }
        if case .range(let lo, let hi) = floor.kind, case .floor(let n) = a.kind { return lo <= n && n <= hi }
        return false
    }

    fileprivate static func nodeCount(_ items: [FloorItem]) -> Int {
        items.reduce(0) { $0 + 1 + nodeCount($1.children) }
    }

    /// VoiceOver 唸的樓層「3 樓」「地下 1 樓」「屋頂」
    fileprivate static func spokenFloor(_ l: FloorLabel) -> String {
        switch l.kind {
        case .basement(let n): return "地下 \(n) 樓"
        case .floor(let n): return "\(n) 樓"
        case .range(let a, let b): return "\(a) 到 \(b) 樓"
        case .mezzanine: return "夾層"
        case .roof: return "屋頂"
        case .unknown: return l.raw.isEmpty ? "樓層" : l.raw
        }
    }

    fileprivate static func utilitiesData(_ c: HouseBuildContext) -> HouseUtilitiesData {
        let re = c.re
        let cal = c.cal
        var u = HouseUtilitiesData()

        func paymentAmount(_ p: UtilityPayment) -> Double {
            if let id = p.linkedExpenseId, let v = c.ntd[id] { return v }
            return p.amount
        }

        func numberLabel(_ t: UtilityType) -> String {
            switch t {
            case .water: return "水號"
            case .electricity: return "電號"
            case .gas: return "瓦斯表號"
            }
        }
        func meterTitle(_ t: UtilityType, number: String) -> String {
            number.isEmpty ? "\(t.rawValue)（沒填\(numberLabel(t))）" : numberLabel(t)
        }

        // [v25.560] 每個表一格（一格電號填了兩個號碼的，拆成兩個表）；繳費有指定表（meterId）的掛在那個表，
        // 沒指定的（舊資料、只有一個表）掛在那一種的第一個表。
        let slots = re.utilityMeterSlots()
        let slotIds = Set(slots.map(\.id))
        var order: [UUID: Int] = [:]
        for (i, p) in re.utilityPayments.enumerated() { order[p.id] = i }
        /// 比較新：日期大的；同一天取陣列裡後面那筆（只有這一份實作）
        func newer(_ a: UtilityPayment, than b: UtilityPayment) -> Bool {
            if a.date != b.date { return a.date > b.date }
            return (order[a.id] ?? 0) > (order[b.id] ?? 0)
        }
        var latestByMeter: [String: UtilityPayment] = [:]
        var latestUnassigned: [UtilityType: UtilityPayment] = [:]
        var anyPayment = Set<UtilityType>()
        for p in re.utilityPayments {
            anyPayment.insert(p.type)
            if let mid = p.meterId, slotIds.contains(mid) {
                if let cur = latestByMeter[mid], !newer(p, than: cur) { continue }
                latestByMeter[mid] = p
            } else {
                if let cur = latestUnassigned[p.type], !newer(p, than: cur) { continue }
                latestUnassigned[p.type] = p
            }
        }

        var claimed = Set<UtilityType>()
        var meters: [HouseUtilitiesData.Meter] = []
        for slot in slots {
            // 沒填表號的主表：有繳費、又沒有別的同種表時，還是列一列「電費（沒填電號）」
            if slot.number.isEmpty && slot.isMain {
                let hasOther = slots.contains { $0.type == slot.type && $0.id != slot.id }
                guard anyPayment.contains(slot.type) && !hasOther else { continue }
            }
            var mine: UtilityPayment? = latestByMeter[slot.id]
            if !claimed.contains(slot.type) {
                claimed.insert(slot.type)
                if let un = latestUnassigned[slot.type] {
                    if let m = mine { if newer(un, than: m) { mine = un } } else { mine = un }
                }
            }
            let user = slot.userNumber
            meters.append(HouseUtilitiesData.Meter(
                id: slot.id, type: slot.type, name: slot.name,
                title: meterTitle(slot.type, number: slot.number), number: slot.number,
                owner: slot.owner,
                userNumber: user.isEmpty ? "" : "用戶編號 " + user,
                latest: mine,
                latestText: mine.map { "\(HouseCardFormat.shortDate($0.date, now: c.now))・\(MoneyFormat.short(paymentAmount($0)))" },
                latestPhotoCount: mine?.photoFileNames.count ?? 0,
                latestDate: mine.map { HouseCardFormat.shortDate($0.date, now: c.now) },
                latestAmount: mine.map { MoneyFormat.short(paymentAmount($0)) }))
        }
        u.meters = meters

        // 全部繳費，新到舊（同一天：陣列裡後面的在前）
        let indexed = Array(re.utilityPayments.enumerated())
        let ordered = indexed.sorted { a, b in
            a.element.date != b.element.date ? a.element.date > b.element.date : a.offset > b.offset
        }
        u.payments = ordered.map { pair -> HouseUtilitiesData.Payment in
            let p = pair.element
            return HouseUtilitiesData.Payment(payment: p, dateText: HouseCardFormat.ymd(p.date), typeText: p.type.rawValue,
                                              amountText: MoneyFormat.short(paymentAmount(p)),
                                              photoCount: p.photoFileNames.count)
        }
        if !u.payments.isEmpty { u.showAllTitle = "看全部 \(u.payments.count) 筆" }

        // 近 12 個月＝asOf 往前 12 個月內
        let back = cal.startOfDay(for: cal.date(byAdding: .month, value: -12, to: c.asOf) ?? c.asOf)
        var total = 0.0
        for p in re.utilityPayments where cal.startOfDay(for: p.date) >= back && c.onOrBeforeAsOf(p.date) {
            total += paymentAmount(p)
        }
        u.total12m = total
        if total > 0 { u.trailing = "近 12 個月 " + MoneyFormat.short(total) }
        return u
    }

    fileprivate static func elevatorData(_ c: HouseBuildContext) -> HouseElevatorData? {
        let re = c.re
        guard re.hasElevator else { return nil }
        let cal = c.cal
        var e = HouseElevatorData()
        let sorted = re.elevatorMaintenances.sorted { $0.date > $1.date }
        e.records = sorted.map {
            HouseElevatorData.Record(record: $0, dateText: HouseCardFormat.ymd($0.date), photoCount: $0.photoFileNames.count)
        }
        guard let last = sorted.first else {
            e.line = HouseLine.text("還沒有保養紀錄")
            return e
        }
        e.trailing = "共 \(sorted.count) 次"
        e.lastDate = last.date
        let head = "上次保養 " + HouseCardFormat.ymd(last.date)
        guard sorted.count >= 2 else {
            e.line = HouseLine.text(head)
            return e
        }
        // 間隔＝相鄰兩次相差天數的中位數
        let days: [Int] = sorted.indices.dropLast().map { i -> Int in
            let newer = cal.startOfDay(for: sorted[i].date)
            let older = cal.startOfDay(for: sorted[i + 1].date)
            return cal.dateComponents([.day], from: older, to: newer).day ?? 0
        }.sorted()
        let mid = days.count / 2
        let median = days.count % 2 == 1 ? days[mid] : Int((Double(days[mid - 1] + days[mid]) / 2).rounded())
        guard median > 0, let next = cal.date(byAdding: .day, value: median, to: cal.startOfDay(for: last.date)) else {
            e.line = HouseLine.text(head)
            return e
        }
        e.medianDays = median
        // 賣掉的房子不用再提醒下次保養
        guard !re.isSold else {
            e.line = HouseLine.text(head + "・平均每 \(median) 天一次")
            return e
        }
        let over = cal.dateComponents([.day], from: next, to: cal.startOfDay(for: c.now)).day ?? 0
        e.nextDate = next
        let lead = head + "・平均每 \(median) 天一次，"
        if over > 0 {
            e.isOverdue = true
            e.overdueDays = over
            e.line = HouseLine(runs: [HouseRun(text: lead), HouseRun(text: "已經超過 \(over) 天沒保養", bold: true, tone: .warn)])
        } else {
            e.line = HouseLine.text("\(lead)下次大約 \(HouseCardFormat.shortDate(next, now: c.now))")
        }
        return e
    }

    fileprivate static func mediaData(_ c: HouseBuildContext) -> HouseMediaData {
        let re = c.re
        var m = HouseMediaData()
        var photos = re.renovationPhotos.reduce(0) { $0 + $1.photoFileNames.count }
        for ex in c.expenses where ex.linkedRealEstateId == re.id {
            let n = ex.photoFileNames.filter { HouseCardFormat.isImage($0) }.count
            if n > 0 {
                photos += n
                m.photoExpenseIds.append(ex.id)
            }
        }
        // 水電一律看 photoFileNames（舊的單張欄位已經併進去）
        photos += re.utilityPayments.reduce(0) { $0 + $1.photoFileNames.count }
        photos += re.elevatorMaintenances.reduce(0) { $0 + $1.photoFileNames.count }
        m.photoCount = photos
        m.documentCount = re.documents.count
        var parts: [String] = []
        if photos > 0 { parts.append("\(photos) 張") }
        if m.documentCount > 0 { parts.append("\(m.documentCount) 份") }
        m.trailing = parts.isEmpty ? nil : parts.joined(separator: "・")
        return m
    }
}

// MARK: - 帳本的演算法

/// 一筆支出被房子哪個陣列擁有（優先序：保險 > 附屬資產 > 水電 > 房屋價金 > 變動支出）
private enum HouseLedgerOwner {
    case insurance(RealEstateInsuranceItem)
    case asset(RealEstatePropertyAsset)
    case utility(UtilityPayment)
    case paid(RealEstatePaidItem)
    case variable(RealEstateVariableExpense)
}

extension HouseLedger {
    /// 分類→四大類。買房費用歸一次性（不算自備款）；沒有分類的當持有
    fileprivate static func bucketOf(_ c: RealEstateExpenseCategory?) -> HouseLedgerBucket {
        switch c {
        case .housePayment?: return .purchase
        case .purchaseCost?, .renovation?, .furniture?: return .oneTime
        default: return .holding
        }
    }

    fileprivate static func build(_ c: HouseBuildContext) -> HouseLedger {
        let re = c.re
        var events: [HouseLedgerEvent] = []

        // 1. 擁有者表：先掛到的贏
        var owner: [UUID: HouseLedgerOwner] = [:]
        var ownerOrder: [UUID] = []
        func claim(_ link: UUID?, _ o: HouseLedgerOwner) {
            guard let id = link, c.byId[id] != nil, owner[id] == nil else { return }
            owner[id] = o
            ownerOrder.append(id)
        }
        for it in re.insuranceItems { claim(it.linkedExpenseId, .insurance(it)) }
        for it in re.propertyAssets { claim(it.linkedExpenseId, .asset(it)) }
        for it in re.utilityPayments { claim(it.linkedExpenseId, .utility(it)) }
        for it in re.paidItems { claim(it.linkedExpenseId, .paid(it)) }
        for it in re.variableExpenses { claim(it.linkedExpenseId, .variable(it)) }

        // 2. 候選＝記帳裡連到這間的 ∪ 房子陣列連到的（用支出 id 去重），扣掉房貸與賣出虧損
        var candidates: [Expense] = []
        var seen = Set<UUID>()
        for ex in c.expenses where ex.linkedRealEstateId == re.id {
            if seen.insert(ex.id).inserted { candidates.append(ex) }
        }
        for id in ownerOrder {
            if let ex = c.byId[id], seen.insert(id).inserted { candidates.append(ex) }
        }
        var fixedRecurring: [Expense] = []
        for ex in candidates where !c.excluded.contains(ex.id) {
            if ex.expenseType == .fixed {
                if ex.fixedCategory == .loan { continue }
                if ex.isRecurringFixed {
                    fixedRecurring.append(ex)
                    continue
                }
            }
            guard c.onOrBeforeAsOf(ex.date) else { continue }
            events.append(expenseEvent(ex, owner: owner[ex.id], c: c))
        }

        // 3. 舊資料（沒連到記帳、或記帳裡找不到）：用自己的金額和日期；同一個找不到的 id 只留一列
        events += legacyEvents(c)

        // 4. 房貸每年一列、連到房子的固定支出每年一列
        events += mortgageYearEvents(c)
        events += fixedYearEvents(fixedRecurring, c: c)

        events.sort { a, b in a.date != b.date ? a.date > b.date : a.id > b.id }

        var l = HouseLedger()
        l.events = events
        l.recordCount = events.filter { !$0.isYearRow }.count
        l.recordsTitle = l.recordCount > 0 ? "紀錄・\(l.recordCount) 筆" : "紀錄"
        l.headerTrailing = "從 " + HouseCardFormat.ym(re.purchaseDate) + " 買下"

        // 5. 合計：原始金額加完才四捨五入一次，四類用最大餘數法分尾數
        var raw: [HouseLedgerBucket: Double] = [:]
        for e in events { raw[e.bucket, default: 0] += e.amount }
        l.rawTotals = raw
        let order = HouseLedgerBucket.ordered
        let rawParts = order.map { raw[$0] ?? 0 }
        let rawTotal = rawParts.reduce(0, +)
        l.unit = HouseRound.ledgerUnit(rawTotal)
        l.total = HouseRound.round(rawTotal, unit: l.unit)
        let shares = HouseRound.largestRemainder(rawParts, total: l.total, unit: l.unit)
        for (i, b) in order.enumerated() { l.totals[b] = shares[i] }
        l.downPayment = raw[.purchase] ?? 0
        l.downPaymentCount = events.filter { $0.bucket == .purchase }.count

        // 6. 篩選膠囊與年份分組（各年小計再分一次尾數，加起來＝那個篩選的小計）
        for filter in HouseLedgerFilter.allCases {
            let amount = filter.bucket.map { l.amount($0) } ?? l.total
            let rows = filter.bucket.map { b in events.filter { $0.bucket == b } } ?? events
            l.filters.append(HouseLedgerFilterChip(filter: filter, amount: amount,
                                                   text: filter.title + " " + MoneyFormat.short(amount), rowCount: rows.count))
            l.yearsByFilter[filter] = yearGroups(rows, total: amount, unit: l.unit, asOf: c.asOf)
        }

        fillSummary(&l, c: c)
        return l
    }

    fileprivate static func yearGroups(_ rows: [HouseLedgerEvent], total: Double, unit: Double, asOf: Date) -> [HouseLedgerYear] {
        guard !rows.isEmpty else { return [] }
        var byYear: [Int: [HouseLedgerEvent]] = [:]
        for e in rows { byYear[e.year, default: []].append(e) }
        let years = byYear.keys.sorted(by: >)
        let raw = years.map { y in (byYear[y] ?? []).reduce(0.0) { $0 + $1.amount } }
        let shares = HouseRound.largestRemainder(raw, total: total, unit: unit)
        let current = HouseCardFormat.year(asOf)
        return years.enumerated().map { pair -> HouseLedgerYear in
            let i = pair.offset
            let y = pair.element
            let list = byYear[y] ?? []
            let count = list.filter { !$0.isYearRow }.count
            var title = "\(y) 年"
            if count > 0 { title += "・\(count) 筆" }
            title += "・" + MoneyFormat.short(shares[i])
            return HouseLedgerYear(year: y, events: list, recordCount: count, total: shares[i], title: title,
                                   isCurrent: y == current)
        }
    }

    /// 一筆記帳支出變成一列
    fileprivate static func expenseEvent(_ ex: Expense, owner: HouseLedgerOwner?, c: HouseBuildContext) -> HouseLedgerEvent {
        let amount = c.amount(ex)
        let note = ex.note.trimmingCharacters(in: .whitespacesAndNewlines)
        var title = HouseCardFormat.cleanTitle(ex.title, estateName: c.re.name)
        var extra: [String] = []
        var photos = ex.photoFileNames.filter { HouseCardFormat.isImage($0) }.count
        var source: HouseLedgerEvent.Source = .expense(ex.id)
        let category: RealEstateExpenseCategory?
        let bucket: HouseLedgerBucket
        let mark: HouseLedgerMark
        switch owner {
        case .insurance(let it)?:
            category = .insurance
            bucket = .holding
            mark = .insurance
            let policy = it.policyNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty || title == "保險" || title == policy {
                title = policy.isEmpty ? "保險" : "保險 No." + policy
            }
        case .asset(let a)?:
            // 附屬資產一律一次性（類別 Picker 可以選成房屋價金，不能讓家電算成自備款）
            category = ex.realEstateExpenseCategory ?? a.category
            bucket = .oneTime
            mark = category == .renovation ? .renovation : .furniture
            let name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { title = name }
            extra = [a.brand, a.floorLocation].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        case .utility(let p)?:
            category = .utility
            bucket = .holding
            mark = .utility
            source = .utility(p.id)
            photos = p.photoFileNames.count
            if title.isEmpty { title = p.type.rawValue }
        case .paid?:
            category = ex.realEstateExpenseCategory ?? .housePayment
            bucket = bucketOf(category)
            mark = HouseLedgerMark.of(category)
        case .variable(let v)?:
            category = ex.realEstateExpenseCategory ?? v.category
            bucket = bucketOf(category)
            mark = HouseLedgerMark.of(category)
        case nil:
            category = ex.realEstateExpenseCategory
            // 沒有週期的舊固定支出：當一次性一列
            bucket = ex.expenseType == .fixed ? .oneTime : bucketOf(category)
            mark = HouseLedgerMark.of(category)
        }
        let categoryName = category?.rawValue ?? "其他"
        var noteUsed = false
        if title.isEmpty || title == categoryName {
            if !note.isEmpty {
                title = note
                noteUsed = true
            } else {
                title = categoryName
            }
        }
        var detail = [categoryName] + extra
        if !note.isEmpty && !noteUsed && note != title { detail.append(note) }
        if photos > 0 { detail.append("\(photos) 張照片") }
        let id: String
        if case .utility(let pid) = source { id = "u-" + pid.uuidString } else { id = "e-" + ex.id.uuidString }
        return HouseLedgerEvent(id: id, date: ex.date, bucket: bucket, category: category, title: title,
                                detail: detail.joined(separator: "・"), amount: amount, source: source, mark: mark,
                                photoCount: photos, isUnlinked: false, expenseId: ex.id)
    }

    /// 房子陣列裡沒連到記帳（或記帳裡找不到）的舊資料，照優先序、同一個找不到的 id 只留一列
    fileprivate static func legacyEvents(_ c: HouseBuildContext) -> [HouseLedgerEvent] {
        let re = c.re
        var out: [HouseLedgerEvent] = []
        var dangling = Set<UUID>()
        func isLegacy(_ link: UUID?) -> Bool {
            guard let id = link else { return true }
            guard c.byId[id] == nil else { return false }
            return dangling.insert(id).inserted
        }
        for it in re.insuranceItems where it.amount > 0 && isLegacy(it.linkedExpenseId) {
            guard c.onOrBeforeAsOf(re.purchaseDate) else { continue }
            let policy = it.policyNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(HouseLedgerEvent(id: "l-ins-" + it.id.uuidString, date: re.purchaseDate, bucket: .holding,
                                        category: .insurance, title: policy.isEmpty ? "保險" : "保險 No." + policy,
                                        detail: "保險", amount: it.amount, source: .legacy(.insurance, it.id),
                                        mark: .insurance, isUnlinked: true))
        }
        for a in re.propertyAssets where a.amount > 0 && isLegacy(a.linkedExpenseId) {
            guard c.onOrBeforeAsOf(re.purchaseDate) else { continue }
            let name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = [a.category.rawValue, a.brand, a.floorLocation]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            out.append(HouseLedgerEvent(id: "l-asset-" + a.id.uuidString, date: re.purchaseDate, bucket: .oneTime,
                                        category: a.category, title: name.isEmpty ? a.category.rawValue : name,
                                        detail: detail.joined(separator: "・"), amount: a.amount,
                                        source: .legacy(.asset, a.id),
                                        mark: a.category == .renovation ? .renovation : .furniture, isUnlinked: true))
        }
        for p in re.utilityPayments where p.amount > 0 && isLegacy(p.linkedExpenseId) {
            guard c.onOrBeforeAsOf(p.date) else { continue }
            let note = p.note.trimmingCharacters(in: .whitespacesAndNewlines)
            var detail = ["水電瓦斯"]
            if !note.isEmpty { detail.append(note) }
            if !p.photoFileNames.isEmpty { detail.append("\(p.photoFileNames.count) 張照片") }
            out.append(HouseLedgerEvent(id: "l-util-" + p.id.uuidString, date: p.date, bucket: .holding,
                                        category: .utility, title: p.type.rawValue, detail: detail.joined(separator: "・"),
                                        amount: p.amount, source: .legacy(.utility, p.id), mark: .utility,
                                        photoCount: p.photoFileNames.count, isUnlinked: true))
        }
        for it in re.paidItems where it.amount > 0 && isLegacy(it.linkedExpenseId) {
            guard c.onOrBeforeAsOf(it.date) else { continue }
            let t = HouseCardFormat.cleanTitle(it.title, estateName: re.name)
            out.append(HouseLedgerEvent(id: "l-paid-" + it.id.uuidString, date: it.date, bucket: .purchase,
                                        category: .housePayment,
                                        title: (t.isEmpty || t == "房屋價金") ? "房屋價金" : t,
                                        detail: "房屋價金", amount: it.amount, source: .legacy(.paid, it.id),
                                        mark: .price, isUnlinked: true))
        }
        for v in re.variableExpenses where v.amount > 0 && isLegacy(v.linkedExpenseId) {
            guard c.onOrBeforeAsOf(v.date) else { continue }
            let name = v.name.trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(HouseLedgerEvent(id: "l-var-" + v.id.uuidString, date: v.date, bucket: bucketOf(v.category),
                                        category: v.category, title: name.isEmpty ? v.category.rawValue : name,
                                        detail: v.category.rawValue, amount: v.amount, source: .legacy(.variable, v.id),
                                        mark: HouseLedgerMark.of(v.category), isUnlinked: true))
        }
        return out
    }

    /// 房貸每年一列：「房貸 4–10 月・7 期」，細字「利息約 24.3萬・本金約 1.6萬」。各年相加＝HouseFacts.paid
    fileprivate static func mortgageYearEvents(_ c: HouseBuildContext) -> [HouseLedgerEvent] {
        let f = c.facts
        let greg = HouseCardFormat.calendar
        struct Acc { var count = 0; var amount = 0.0; var first: Date; var last: Date }
        var byYear: [Int: Acc] = [:]
        for s in f.segments where s.paidPeriods > 0 {
            for k in 1...s.paidPeriods {
                let d = s.due(k, calendar: c.cal)
                let y = greg.component(.year, from: d)
                var acc = byYear[y] ?? Acc(first: d, last: d)
                acc.count += 1
                acc.amount += s.perPeriod
                acc.first = min(acc.first, d)
                acc.last = max(acc.last, d)
                byYear[y] = acc
            }
        }
        var out: [HouseLedgerEvent] = []
        for (y, acc) in byYear {
            let m1 = greg.component(.month, from: acc.first)
            let m2 = greg.component(.month, from: acc.last)
            let months = m1 == m2 ? "\(m1) 月" : "\(m1)–\(m2) 月"
            let title = "房貸 " + months + "・\(acc.count) 期"
            // 拆不出利息本金時細字不再重複「N 期」（標題已經寫了）
            var detail = "含利息"
            if let split = mortgageSplit(year: y, paid: acc.amount, c: c) {
                let i = HouseCardFormat.compact(split.interest)
                let pr = HouseCardFormat.compact(split.principal)
                detail = "利息約 \(i)・本金約 \(pr)"
            }
            out.append(HouseLedgerEvent(id: "mortgage-\(y)", date: acc.last, bucket: .mortgage, category: nil,
                                        title: title, detail: detail, amount: acc.amount, source: .mortgageYear(y),
                                        mark: .mortgage))
        }
        return out
    }

    /// 第 y 年付的房貸裡，本金和利息各多少（用 HouseFacts.owed(at:) 拆，各年相加＝已還本金／已付利息）。
    /// owed(at:) 在第一段起始日之前回 0、也不會自己停在賣出日，所以起點用 P、終點夾在 asOf。
    fileprivate static func mortgageSplit(year y: Int, paid: Double, c: HouseBuildContext) -> (interest: Double, principal: Double)? {
        let f = c.facts
        guard let p = f.principal, f.monthlyRate != nil, f.hasStarted, let firstStart = f.firstStart else { return nil }
        let greg = HouseCardFormat.calendar
        guard let jan1 = greg.date(from: DateComponents(year: y, month: 1, day: 1)),
              let dec31 = greg.date(from: DateComponents(year: y, month: 12, day: 31)),
              let prevDec31 = greg.date(from: DateComponents(year: y - 1, month: 12, day: 31)) else { return nil }
        let startOwed = c.cal.startOfDay(for: jan1) <= c.cal.startOfDay(for: firstStart) ? p : f.owed(at: prevDec31, calendar: c.cal)
        let endOwed = f.owed(at: min(dec31, c.asOf), calendar: c.cal)
        let principal = startOwed - endOwed
        let interest = paid - principal
        guard principal >= 0, interest >= 0 else { return nil }
        return (interest, principal)
    }

    /// 連到房子的固定支出（管理費…）每年一列：「管理費・12 期」，期數照 Expense.fixedPeriodCount 數到 asOf
    fileprivate static func fixedYearEvents(_ list: [Expense], c: HouseBuildContext) -> [HouseLedgerEvent] {
        let greg = HouseCardFormat.calendar
        var out: [HouseLedgerEvent] = []
        let endYear = greg.component(.year, from: c.asOf)
        for ex in list {
            guard let rec = ex.recurrence else { continue }
            let (component, step) = rec.componentValue
            let amount = c.amount(ex)
            let startYear = greg.component(.year, from: ex.date)
            guard startYear <= endYear else { continue }
            let cleaned = HouseCardFormat.cleanTitle(ex.title, estateName: c.re.name)
            let base = cleaned.isEmpty ? (ex.fixedCategory?.rawValue ?? "固定支出") : cleaned
            let kindName = ex.fixedCategory?.rawValue ?? "固定支出"
            let detail = "\(kindName)・\(rec.rawValue) \(MoneyFormat.short(amount))"
            var before = 0
            for y in startYear...min(endYear, startYear + 120) {
                guard let dec31 = greg.date(from: DateComponents(year: y, month: 12, day: 31)) else { continue }
                let total = ex.fixedPeriodCount(until: min(dec31, c.asOf), calendar: c.cal)
                let k = total - before
                before = total
                guard k > 0 else { continue }
                let lastDue = c.cal.date(byAdding: component, value: step * (total - 1), to: ex.date) ?? min(dec31, c.asOf)
                out.append(HouseLedgerEvent(id: "fixed-" + ex.id.uuidString + "-\(y)", date: lastDue, bucket: .holding,
                                            category: nil, title: base + "・\(k) 期", detail: detail,
                                            amount: Double(k) * amount, source: .fixedYear(ex.id, y), mark: .fixed,
                                            expenseId: ex.id))
            }
        }
        return out
    }

    /// 卡 1：格子、合計、長條、兩句話、空的時候那句話
    fileprivate static func fillSummary(_ l: inout HouseLedger, c: HouseBuildContext) {
        let re = c.re
        let f = c.facts
        var tiles: [HouseTile] = []
        tiles.append(HouseTile(label: "購入", value: re.purchasePrice > 0 ? HouseCardFormat.compact(re.purchasePrice) : "—",
                               sub: HouseCardFormat.ymd(re.purchaseDate)))
        let gain = f.value - re.purchasePrice
        var gainSub = ""
        var gainTone: MoneyTone? = nil
        if f.valueIsFallback {
            gainSub = "還沒填"
        } else if re.purchasePrice > 0 {
            gainSub = HouseCardFormat.compact(gain, signed: true)
            gainTone = MoneyTone.change(gain, base: re.purchasePrice)
        }
        tiles.append(HouseTile(label: re.isSold ? "成交價" : "估值", value: HouseCardFormat.compact(f.value),
                               sub: gainSub, subTone: gainTone))
        l.totalLabel = re.isSold ? "到賣出那天總共付了" : "到今天總共付了"
        guard !l.isEmpty else {
            l.tiles = tiles
            l.emptyHint = "頭期款、裝修、維修、水電、稅費都可以記在這裡，記了之後上面會算出你總共付了多少。"
            l.totalText = MoneyFormat.short(0)
            return
        }

        let down = l.amount(.purchase)
        var downSub = "\(l.downPaymentCount) 筆"
        if re.purchasePrice > 0, down > 0 { downSub += "・購入價 " + MoneyFormat.percent(down / re.purchasePrice) }
        tiles.append(HouseTile(label: "自備款", value: HouseCardFormat.compact(down), sub: downSub,
                               tap: .ledgerFilter(.purchase)))
        if f.hasMortgage {
            tiles.append(HouseTile(label: "已繳房貸", value: HouseCardFormat.compact(l.amount(.mortgage)),
                                   sub: "\(f.paidCount) 期", tap: .scrollToMortgage))
        } else {
            let lived = HouseCardFormat.lived(from: re.purchaseDate, to: c.asOf) ?? "不到 1 個月"
            tiles.append(HouseTile(label: (re.isSold || re.monthlyRental > 0) ? "持有" : "住了", value: lived))
        }
        tiles.append(HouseTile(label: "一次性花費", value: HouseCardFormat.compact(l.amount(.oneTime)),
                               sub: topNames(l.events, bucket: .oneTime, limit: 2), tap: .ledgerFilter(.oneTime)))
        tiles.append(HouseTile(label: "持有花費", value: HouseCardFormat.compact(l.amount(.holding)),
                               sub: topNames(l.events, bucket: .holding, limit: 3), tap: .ledgerFilter(.holding)))
        l.tiles = tiles
        l.totalText = MoneyFormat.short(l.total)
        l.parts = HouseLedgerBucket.ordered.map { b in
            HouseLedgerPart(bucket: b, value: l.amount(b), legend: b.legendTitle + " " + HouseCardFormat.compact(l.amount(b)))
        }

        // 兩句話：算得出借款本金才寫（還沒開始扣時已還本金算 0）
        guard f.owedIsPrincipal else { return }
        let repaid: Double = f.hasStarted ? (f.principalRepaid ?? 0) : 0
        let mine = l.downPayment + repaid
        if mine >= 1 {
            l.mineLine = HouseLine(runs: [
                HouseRun(text: "其中 "),
                HouseRun(text: MoneyFormat.short(mine), bold: true),
                HouseRun(text: "（自備款＋已還本金）已經變成房子裡你的那一份。")
            ])
        }
        guard !re.isSold, !c.notStarted else { return }
        let back = f.value - f.owed
        let diff = back - l.total
        l.sellLine = HouseLine(runs: [
            HouseRun(text: "照估值今天賣掉，還掉本金拿回 "),
            HouseRun(text: MoneyFormat.short(back), bold: true),
            HouseRun(text: "，比到今天付出去的" + (diff >= 0 ? "多 " : "少 ")),
            HouseRun(text: MoneyFormat.short(abs(diff)), bold: true, tone: diff >= 0 ? .good : .bad),
            HouseRun(text: "（還沒扣仲介費和房地合一稅）。")
        ])
    }

    /// 格子小字：這一類裡金額最大的幾種（「裝修・家具」「水電・稅費・維修…」）
    fileprivate static func topNames(_ events: [HouseLedgerEvent], bucket: HouseLedgerBucket, limit: Int) -> String {
        var sums: [String: Double] = [:]
        var firstSeen: [String] = []
        for e in events where e.bucket == bucket {
            let name = e.mark.shortName
            if sums[name] == nil { firstSeen.append(name) }
            sums[name, default: 0] += e.amount
        }
        let ranked = firstSeen.sorted { (sums[$0] ?? 0) > (sums[$1] ?? 0) }
        guard !ranked.isEmpty else { return "" }
        let head = ranked.prefix(limit).joined(separator: "・")
        return ranked.count > limit ? head + "…" : head
    }
}

// MARK: - 要確認的檢查

extension HouseCheck {
    fileprivate static func build(_ c: HouseBuildContext, ledger: HouseLedger) -> [HouseCheck] {
        let re = c.re
        let f = c.facts
        let cal = c.cal
        var out: [HouseCheck] = []

        // 1. 賣掉了，房貸還在記帳裡每月扣
        if re.isSold, let sold = re.soldDate {
            let soldDay = cal.startOfDay(for: sold)
            let ids = RealEstateSale.mortgageExpenseIds(of: re, expenses: c.expenses)
            var still: [UUID] = []
            for ex in c.expenses where ids.contains(ex.id) && ex.isRecurringFixed {
                if let end = ex.endDate {
                    if cal.startOfDay(for: end) > soldDay { still.append(ex.id) }
                } else {
                    still.append(ex.id)
                }
            }
            if !still.isEmpty {
                let titles = still.map { id in f.segments.first(where: { $0.linkedExpenseId == id })?.displayTitle ?? "房貸" }
                let names = segmentNames(titles)
                out.append(HouseCheck(kind: .soldStillCharging,
                                      message: "房子 \(HouseCardFormat.ym(sold)) 賣掉了，但\(names)還在記帳裡每月扣",
                                      button: "在賣出日停止",
                                      confirm: "把\(names)的最後扣款日設成 \(HouseCardFormat.ymd(sold))（賣出日），之後不再從銀行扣。",
                                      fix: .stopMortgagesAtSale(expenseIds: still)))
            }
        }

        // 2. 期數沒填
        let guesses = f.segments.filter { c.termMissing($0) }
        if let first = guesses.first {
            let names = segmentNames(guesses.map(\.displayTitle))
            let monthsSet = Set(guesses.map { $0.contractPeriods * $0.periodMonths })
            let periodsSet = Set(guesses.map(\.contractPeriods))
            var message = names + "沒填年限，"
            if monthsSet.count == 1, periodsSet.count == 1, let months = monthsSet.first, let periods = periodsSet.first,
               let years = HouseCardFormat.span(months: months) {
                message += "先當 " + years + "（\(periods) 期）算"
            } else {
                message += "先照預設的期數算"
            }
            out.append(HouseCheck(kind: .termMissing, message: message, button: "去填", confirm: nil,
                                  fix: .openSegment(first)))
        }

        // 3. 孤兒：房子這邊還連著、記帳裡已經找不到的
        let orphans = orphanLinks(c)
        if !orphans.isEmpty {
            var confirm = "把房子這邊這 \(orphans.count) 筆拿掉（水電只解除連結，收據照片留著）。記帳不會變動。"
            let lostSegments = orphans.filter { $0.place == .mortgage }.count
            if lostSegments > 0 { confirm += "其中 \(lostSegments) 段房貸拿掉後，房貸區會少這幾段。" }
            out.append(HouseCheck(kind: .orphans, message: "\(orphans.count) 筆在記帳那邊已經刪掉，房子這邊還留著",
                                  button: "移除", confirm: confirm, fix: .removeOrphans(orphans)))
        }

        // 4. 重複：同一筆支出掛在兩個地方
        let dups = duplicates(re)
        if let d = dups.first {
            let message: String
            let confirm: String
            let distinct = uniquePlaces(d.places)
            if dups.count == 1 {
                if distinct.count >= 2 {
                    let others = distinct.filter { $0 != d.keep }.map(\.title).joined(separator: "、")
                    let all = distinct.map(\.title).joined(separator: "和")
                    message = "1 筆\(d.keep.title)同時掛在\(all)，帳本已經只算一次"
                    confirm = "只留在「\(d.keep.title)」那邊，把\(others)裡重複的那一列拿掉。記帳裡的支出不會刪。"
                } else {
                    message = "1 筆\(d.keep.title)在\(d.keep.title)裡重複了，帳本已經只算一次"
                    confirm = "只留第一列，把重複的那一列拿掉。記帳裡的支出不會刪。"
                }
            } else {
                message = "\(dups.count) 筆支出同時掛在兩個地方，帳本已經只算一次"
                confirm = "每筆只留在一個地方（保險、附屬資產、水電優先），拿掉重複的列。記帳裡的支出不會刪。"
            }
            out.append(HouseCheck(kind: .duplicates, message: message, button: "整理", confirm: confirm,
                                  fix: .mergeDuplicates(dups)))
        }

        // 5. 自備款＋借款本金≠購入價（推算的本金本來就剛好相等，只查你填的、記帳裡的）
        if f.principalSource == .entered || f.principalSource == .ledger, let p = f.principal, re.purchasePrice > 0 {
            let diff = ledger.downPayment + p - re.purchasePrice
            if abs(diff) > re.purchasePrice * 0.01 {
                let gap = MoneyFormat.short(abs(diff))
                let message = diff > 0
                    ? "自備款加借款本金比購入價多 \(gap)，可能把銀行撥款也記成了房屋價金"
                    : "自備款加借款本金比購入價少 \(gap)，可能還有頭期款沒記，或借款本金填少了"
                out.append(HouseCheck(kind: .purchaseMismatch, message: message, button: "去看", confirm: nil,
                                      fix: .edit(.loanPrincipal)))
            }
        }

        // 6. 估值 0／成交價沒填
        if re.isSold {
            if (re.soldPrice ?? 0) <= 0 {
                let message = re.currentValue > 0 ? "成交價沒填，先用估值當賣價" : "成交價沒填，先用購入價當賣價"
                out.append(HouseCheck(kind: .soldPriceMissing, message: message, button: "去填", confirm: nil,
                                      fix: .edit(.soldPrice)))
            }
        } else if re.currentValue <= 0 {
            out.append(HouseCheck(kind: .valueMissing, message: "估值是 0，先用購入價算", button: "去填", confirm: nil,
                                  fix: .edit(.currentValue)))
        }

        // 7. 算不出利率（全部扣款 ≤ 本金，或要超過每月 2%）
        if f.hasMortgage, let p = f.principal, f.monthlyRate == nil {
            let message = f.contractTotal <= p
                ? "借款本金比全部要繳的還多，算不出利率"
                : "借款本金跟每期金額對不起來（年利率要超過 24%），算不出利率"
            out.append(HouseCheck(kind: .rateUnsolvable, message: message, button: "去改", confirm: nil,
                                  fix: .edit(.loanPrincipal)))
        }
        return out
    }

    /// 「第 3–5 段房貸」「第 1、3 段房貸」「房貸」「新青安、第 2 段房貸」
    fileprivate static func segmentNames(_ titles: [String]) -> String {
        var unique: [String] = []
        for t in titles where !unique.contains(t) { unique.append(t) }
        var nums: [Int] = []
        var allNumbered = !unique.isEmpty
        for t in unique {
            if t.hasPrefix("第 "), t.hasSuffix(" 段"), let n = Int(String(t.dropFirst(2).dropLast(2))) {
                nums.append(n)
            } else {
                allNumbered = false
            }
        }
        if allNumbered {
            nums.sort()
            if nums.count == 1 { return "第 \(nums[0]) 段房貸" }
            if let lo = nums.first, let hi = nums.last, hi - lo == nums.count - 1 { return "第 \(lo)–\(hi) 段房貸" }
            let list = nums.map { String($0) }.joined(separator: "、")
            return "第 \(list) 段房貸"
        }
        let joined = unique.joined(separator: "、")
        return joined.contains("貸") ? joined : joined + "房貸"
    }

    fileprivate static func orphanLinks(_ c: HouseBuildContext) -> [HouseItemLink] {
        let re = c.re
        var out: [HouseItemLink] = []
        func add(_ place: HouseItemLink.Place, _ item: UUID?, _ link: UUID?) {
            guard let id = link, c.byId[id] == nil else { return }
            out.append(HouseItemLink(place: place, itemId: item, expenseId: id))
        }
        for m in re.mortgageItems { add(.mortgage, m.id, m.linkedExpenseId) }
        for p in re.paidItems { add(.paid, p.id, p.linkedExpenseId) }
        for v in re.variableExpenses { add(.variable, v.id, v.linkedExpenseId) }
        for i in re.insuranceItems { add(.insurance, i.id, i.linkedExpenseId) }
        for a in re.propertyAssets { add(.asset, a.id, a.linkedExpenseId) }
        for u in re.utilityPayments { add(.utility, u.id, u.linkedExpenseId) }
        add(.estateMortgage, nil, re.linkedExpenseId)
        add(.estateSale, nil, re.saleLinkedExpenseId)
        return out
    }

    /// 同一個 linkedExpenseId 出現在兩處以上（不同陣列，或同一陣列兩列）
    fileprivate static func duplicates(_ re: RealEstate) -> [HouseDuplicate] {
        var places: [UUID: [HouseItemLink.Place]] = [:]
        var order: [UUID] = []
        func add(_ link: UUID?, _ place: HouseItemLink.Place) {
            guard let id = link else { return }
            if places[id] == nil { order.append(id) }
            places[id, default: []].append(place)
        }
        for i in re.insuranceItems { add(i.linkedExpenseId, .insurance) }
        for a in re.propertyAssets { add(a.linkedExpenseId, .asset) }
        for u in re.utilityPayments { add(u.linkedExpenseId, .utility) }
        for p in re.paidItems { add(p.linkedExpenseId, .paid) }
        for v in re.variableExpenses { add(v.linkedExpenseId, .variable) }
        return order.compactMap { id -> HouseDuplicate? in
            guard let list = places[id], list.count >= 2, let keep = list.first else { return nil }
            return HouseDuplicate(expenseId: id, keep: keep, places: list)
        }
    }

    fileprivate static func uniquePlaces(_ list: [HouseItemLink.Place]) -> [HouseItemLink.Place] {
        var out: [HouseItemLink.Place] = []
        for p in list where !out.contains(p) { out.append(p) }
        return out
    }
}

// MARK: - [v25.560] 一間房子的每一個水／電／瓦斯表（卡片列、繳費表單的「哪一個表」共用同一份）

/// 一個表。id 跟 UtilityPayment.meterId、HouseUtilitiesData.Meter.id 是同一套：
/// 主表「main-electricity」；主表那一格填了兩個以上號碼時「main-electricity#21-40-0218-50」；額外的表是 UtilityMeter.id
struct UtilityMeterSlot: Identifiable, Equatable {
    let id: String
    let type: UtilityType
    /// 額外的表自己取的名字「客廳」；主表是空字串
    let name: String
    /// 號碼；沒填是空字串
    let number: String
    let owner: String
    let userNumber: String
    let isMain: Bool

    /// 選單上的字：「電號 21-40-0218-50（客廳）」
    var menuTitle: String {
        let label: String
        switch type {
        case .water: label = "水號"
        case .electricity: label = "電號"
        case .gas: label = "瓦斯表號"
        }
        var t = number.isEmpty ? "\(label)（沒填）" : "\(label) \(number)"
        if !name.isEmpty { t += "（\(name)）" }
        return t
    }
}

extension RealEstate {
    /// 一格裡填了兩個以上號碼（「21-40-0218-50、21-40-0218-61」「…／…」「…, …」或換行）就拆開；
    /// 用空白隔開的，只有每一段都有 6 個以上數字才拆（號碼裡本來就可能有空白）
    static func splitMeterNumbers(_ raw: String) -> [String] {
        let seps = CharacterSet(charactersIn: "、,，/／;；\n")
        var parts: [String] = raw.components(separatedBy: seps)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var out: [String] = []
        for p in parts {
            let tokens = p.split(whereSeparator: { $0 == " " || $0 == "\u{3000}" }).map(String.init)
            let digitCounts = tokens.map { t in t.filter { $0.isNumber }.count }
            if tokens.count >= 2, digitCounts.allSatisfy({ $0 >= 6 }) {
                out.append(contentsOf: tokens)
            } else {
                out.append(p)
            }
        }
        parts = out
        return parts
    }

    /// 主表（水、電、瓦斯）在前、額外的表接在後面；主表一格填了兩個號碼的拆成兩個
    func utilityMeterSlots() -> [UtilityMeterSlot] {
        func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let mains: [(type: UtilityType, number: String, owner: String, user: String)] = [
            (type: .water, number: waterMeterNumber, owner: waterMeterOwner, user: ""),
            (type: .electricity, number: electricityMeterNumber, owner: electricityMeterOwner, user: ""),
            (type: .gas, number: gasMeterNumber, owner: gasMeterOwner, user: gasUserNumber)
        ]
        var out: [UtilityMeterSlot] = []
        for m in mains {
            let numbers = Self.splitMeterNumbers(m.number)
            let baseId = "main-\(m.type)"
            if numbers.count <= 1 {
                out.append(UtilityMeterSlot(id: baseId, type: m.type, name: "", number: numbers.first ?? "",
                                            owner: clean(m.owner), userNumber: clean(m.user), isMain: true))
            } else {
                for n in numbers {
                    out.append(UtilityMeterSlot(id: baseId + "#" + n, type: m.type, name: "", number: n,
                                                owner: clean(m.owner), userNumber: clean(m.user), isMain: true))
                }
            }
        }
        for x in extraMeters {
            out.append(UtilityMeterSlot(id: x.id.uuidString, type: x.type, name: clean(x.label),
                                        number: clean(x.meterNumber), owner: clean(x.owner),
                                        userNumber: clean(x.userNumber), isMain: false))
        }
        return out
    }
}
