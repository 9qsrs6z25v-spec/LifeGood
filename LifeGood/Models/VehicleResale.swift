//
//  VehicleResale.swift
//  LifeGood
//
//  [賣車估價] 一台車的「賣車估價」：我的車、共用的選配清單、市場上看到的車 → 建議標價、心理底價。
//  - 選配是一份共用清單（名稱＋原價），我的車和每台市場上的車只存「勾了哪幾項」（optionIds）。
//    原價沒填算 0，畫面標「沒填價格」；少了／多了哪些選配直接用 id 比，不比名稱。
//  - 數學全在 VehicleResaleMath（純函式；scratchpad/resale/resale_math.py 逐行照抄驗算）。
//    畫面上每一個字在 VehicleResaleReport.build 一次組好（照 VehicleCardData 的分法），畫面只排版。
//  - 存在 Vehicle.resale（選填）。這裡每個欄位都是選填或有預設值，自訂解碼一律 try?／decodeIfPresent：
//    舊資料、還沒更新的 iPad 傳來的資料都解得開，壞掉的一筆不會害整台車解不開。
//  - 品牌選配範本（只有名稱、不帶價格）在 VehicleOptionTemplates；要加品牌就在 VehicleOptionBrand 加一個 case、
//    brand(_:) 加一段、keywords(_:) 加關鍵字。
//

import Foundation

// MARK: - 存檔的型別

/// 共用選配清單的一項：名稱＋新車時的原價
struct VehicleResaleOption: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    /// 新車時的原價（台幣元）；nil＝沒填價格（算 0）
    var price: Double?

    init(id: UUID = UUID(), name: String, price: Double? = nil) {
        self.id = id
        self.name = name
        self.price = price
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        price = try? c.decodeIfPresent(Double.self, forKey: .price)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, price
    }
}

/// 市場上看到的一台（8891、臉書社團、車商網站…）
struct VehicleResaleListing: Identifiable, Codable, Equatable {
    let id: UUID
    /// 標題或來源（「8891・2022 Taycan 4S」）
    var title: String
    /// 網址（選填，空字串＝沒填）
    var link: String
    /// 出廠（或領牌）年；nil＝沒填，不調車齡
    var builtYear: Int?
    /// 出廠月 1…12；nil＝只知道年份（當 VehicleResaleMath.unknownMonth 月算）
    var builtMonth: Int?
    var mileageKm: Double?
    /// 新車原價（不含選配，台幣元）
    var newPrice: Double?
    /// 勾了共用清單的哪幾項
    var optionIds: [UUID]
    /// 二手標價（台幣元）
    var askingPrice: Double?
    var seenDate: Date?
    var note: String

    init(id: UUID = UUID(), title: String = "", link: String = "", builtYear: Int? = nil,
         builtMonth: Int? = nil, mileageKm: Double? = nil, newPrice: Double? = nil,
         optionIds: [UUID] = [], askingPrice: Double? = nil, seenDate: Date? = nil, note: String = "") {
        self.id = id
        self.title = title
        self.link = link
        self.builtYear = builtYear
        self.builtMonth = builtMonth
        self.mileageKm = mileageKm
        self.newPrice = newPrice
        self.optionIds = optionIds
        self.askingPrice = askingPrice
        self.seenDate = seenDate
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        link = (try? c.decode(String.self, forKey: .link)) ?? ""
        builtYear = try? c.decodeIfPresent(Int.self, forKey: .builtYear)
        builtMonth = try? c.decodeIfPresent(Int.self, forKey: .builtMonth)
        mileageKm = try? c.decodeIfPresent(Double.self, forKey: .mileageKm)
        newPrice = try? c.decodeIfPresent(Double.self, forKey: .newPrice)
        optionIds = (try? c.decodeIfPresent([UUID].self, forKey: .optionIds)) ?? []
        askingPrice = try? c.decodeIfPresent(Double.self, forKey: .askingPrice)
        seenDate = try? c.decodeIfPresent(Date.self, forKey: .seenDate)
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, link, builtYear, builtMonth, mileageKm, newPrice, optionIds, askingPrice, seenDate, note
    }
}

/// 一台車的賣車估價（存在 Vehicle.resale）
struct VehicleResaleWorkspace: Codable, Equatable {
    /// 我的車出廠（或領牌）年、月
    var builtYear: Int?
    var builtMonth: Int?
    /// 我的車新車原價（不含選配，台幣元）
    var newPrice: Double?
    /// 我的車目前里程
    var mileageKm: Double?
    /// 共用的選配清單（我的車、市場上的車都從這裡打勾）
    var options: [VehicleResaleOption]
    /// 我的車勾了哪幾項
    var myOptionIds: [UUID]
    var listings: [VehicleResaleListing]
    var updatedAt: Date?

    init(builtYear: Int? = nil, builtMonth: Int? = nil, newPrice: Double? = nil, mileageKm: Double? = nil,
         options: [VehicleResaleOption] = [], myOptionIds: [UUID] = [],
         listings: [VehicleResaleListing] = [], updatedAt: Date? = nil) {
        self.builtYear = builtYear
        self.builtMonth = builtMonth
        self.newPrice = newPrice
        self.mileageKm = mileageKm
        self.options = options
        self.myOptionIds = myOptionIds
        self.listings = listings
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        builtYear = try? c.decodeIfPresent(Int.self, forKey: .builtYear)
        builtMonth = try? c.decodeIfPresent(Int.self, forKey: .builtMonth)
        newPrice = try? c.decodeIfPresent(Double.self, forKey: .newPrice)
        mileageKm = try? c.decodeIfPresent(Double.self, forKey: .mileageKm)
        options = (try? c.decodeIfPresent(LossyArray<VehicleResaleOption>.self, forKey: .options))?.elements ?? []
        myOptionIds = (try? c.decodeIfPresent([UUID].self, forKey: .myOptionIds)) ?? []
        listings = (try? c.decodeIfPresent(LossyArray<VehicleResaleListing>.self, forKey: .listings))?.elements ?? []
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case builtYear, builtMonth, newPrice, mileageKm, options, myOptionIds, listings, updatedAt
    }

    /// 還沒存過時的起點：購入日當出廠年月、購入價當新車原價、記帳裡最近一次里程錶當目前里程（畫面會說是帶入的）
    static func starting(from v: Vehicle, odometerKm: Double?, calendar: Calendar) -> VehicleResaleWorkspace {
        let c = calendar.dateComponents([.year, .month], from: v.purchaseDate)
        return VehicleResaleWorkspace(builtYear: c.year, builtMonth: c.month,
                                      newPrice: v.purchasePrice > 0 ? v.purchasePrice : nil,
                                      mileageKm: VehicleResaleMath.positive(odometerKm))
    }
}

// MARK: - 品牌選配範本（只有名稱，原價使用者自己填）

enum VehicleOptionBrand: String, CaseIterable, Identifiable {
    case porsche = "保時捷"
    case benz = "賓士"
    case bmw = "BMW"

    var id: String { rawValue }
}

enum VehicleOptionTemplates {
    /// 這個品牌常見的選配名稱（台灣常見的叫法，括號是原廠名稱方便對照）。不寫價格：每台車、每年的價目表都不一樣
    static func brand(_ b: VehicleOptionBrand) -> [String] {
        switch b {
        case .porsche: return porsche
        case .benz: return benz
        case .bmw: return bmw
        }
    }

    /// 從車輛資料的品牌、車名猜品牌；猜不出來回 nil（讓使用者自己選）
    static func guess(name: String, brand: String) -> VehicleOptionBrand? {
        let text = (brand + " " + name).lowercased()
        for b in VehicleOptionBrand.allCases {
            if keywords(b).contains(where: { text.contains($0) }) { return b }
        }
        return nil
    }

    /// 比對用的關鍵字（一律小寫）
    private static func keywords(_ b: VehicleOptionBrand) -> [String] {
        switch b {
        case .porsche: return ["保時捷", "porsche", "taycan", "macan", "cayenne", "911", "panamera"]
        case .benz: return ["賓士", "benz", "mercedes", "amg"]
        case .bmw: return ["bmw", "寶馬"]
        }
    }

    private static let porsche: [String] = [
        "Sport Chrono 跑車計時套件",
        "後輪轉向",
        "自調式氣壓懸吊（含 PASM）",
        "動態底盤控制（PDCC）",
        "陶瓷複合煞車（PCCB）",
        "全景玻璃車頂",
        "Burmester 高階環繞音響",
        "BOSE 環繞音響",
        "抬頭顯示器",
        "矩陣式 LED 頭燈（PDLS Plus）",
        "夜視輔助",
        "360 度環景攝影",
        "主動式定速巡航（ACC）",
        "車道維持輔助",
        "14 向／18 向電動跑車座椅",
        "座椅通風",
        "方向盤加熱",
        "軟關門",
        "副駕駛顯示螢幕",
        "四區恆溫空調",
        "碳纖維內裝套件",
        "Sport Design 外觀套件",
        "跑車排氣系統（燃油車）",
        "22 kW 車載充電器（Taycan）",
        "熱泵（Taycan）",
        "20 吋輪圈",
        "21 吋輪圈",
        "特殊車色（Paint to Sample）"
    ]

    private static let benz: [String] = [
        "AMG Line 外觀套件",
        "夜色套件",
        "全景天窗",
        "Burmester 環繞音響",
        "抬頭顯示器",
        "360 度環景攝影",
        "DIGITAL LIGHT 頭燈",
        "MULTIBEAM LED 頭燈",
        "AIRMATIC 氣壓懸吊",
        "後輪轉向",
        "智慧駕駛輔助套件",
        "記憶座椅",
        "座椅通風",
        "按摩座椅",
        "方向盤加熱",
        "64 色氛圍燈",
        "AR 擴增實境導航",
        "副駕駛顯示螢幕",
        "KEYLESS-GO 免鑰匙進入",
        "電動尾門",
        "軟關門",
        "後座娛樂系統",
        "隱私玻璃",
        "19 吋 AMG 輪圈",
        "20 吋 AMG 輪圈",
        "21 吋 AMG 輪圈",
        "特殊車色（MANUFAKTUR）"
    ]

    private static let bmw: [String] = [
        "M 款跑車套件（M Sport）",
        "M 跑車煞車",
        "M 跑車座椅",
        "雷射頭燈",
        "全景天窗（Sky Lounge）",
        "Harman Kardon 音響",
        "Bowers & Wilkins 鑽石音響",
        "抬頭顯示器",
        "360 度環景攝影",
        "Driving Assistant Professional 智慧駕駛輔助",
        "Parking Assistant Plus 停車輔助",
        "整合式主動轉向",
        "適應性 M 懸吊",
        "氣壓懸吊",
        "座椅通風",
        "按摩座椅",
        "方向盤加熱",
        "舒適進入",
        "軟關門",
        "手勢控制",
        "後座娛樂系統",
        "碳纖維飾板",
        "19 吋輪圈",
        "20 吋輪圈",
        "21 吋輪圈",
        "Individual 特殊車色"
    ]
}

// MARK: - 數學（純函式）

enum VehicleResaleMath {
    /// 里程係數：市場上那台每比我的車多跑 1 萬公里，它的殘值率先加 1.5 個百分點再拿來比（少跑就減）。
    /// 意思是「同一台車多跑 1 萬公里，大約少值新車總值的 1.5%」：一年約開 1～1.5 萬公里，
    /// 殘值率一年掉的那幾個百分點裡，里程大約占兩成。
    static let mileagePointsPer10kKm: Double = 0.015
    /// 車齡係數：市場上那台每比我的車老 1 年，殘值率加 8 個百分點（比較新就減）。
    /// 進口豪華車、電車前幾年殘值率一年大約掉 8～12 個百分點，取保守的 8。
    static let agePointsPerYear: Double = 0.08
    /// 建議標價＝換算結果的中位數 × 1.05（網路上一定會被殺價，先留 5%）
    static let askMarkup: Double = 1.05
    /// 建議標價、心理底價四捨五入到千元
    static let roundStep: Double = 1_000
    /// 只填年份、沒填月份的車當那年 7 月出廠（年中）
    static let unknownMonth = 7
    /// 4 台以上，心理底價才用第 25 百分位；不到 4 台用最低的那台
    static let percentileMinCount = 4
    static let bottomPercentile: Double = 0.25

    /// 我的車算好的數字
    struct Mine: Equatable {
        let newPrice: Double
        let optionsTotal: Double
        /// 出廠到今天幾個月；沒填出廠年是 nil（不調車齡）
        let ageMonths: Int?
        /// 沒填是 nil（不調里程）
        let km: Double?
        var newTotal: Double { newPrice + optionsTotal }
    }

    /// 市場上一台跟我的車比的結果（標價、新車原價都有才算得出來）
    struct Comparison: Equatable {
        /// 新車原價＋勾的選配原價
        let newTotal: Double
        let asking: Double
        /// 殘值率＝標價 ÷ newTotal
        let rate: Double
        let ageMonths: Int?
        let km: Double?
        /// 它 − 我（公里）；任一邊沒填是 nil
        let kmDiff: Double?
        /// 它 − 我（月）；正＝它比較老。任一邊沒填是 nil
        let ageDiffMonths: Int?
        /// 殘值率要加的（小數：0.026＝2.6 個百分點）；沒得比是 0
        let kmAdjust: Double
        let ageAdjust: Double
        /// max(0, rate + kmAdjust + ageAdjust)
        let adjustedRate: Double
        /// 換算成我的車＝我的新車總值 × adjustedRate；我的新車總值 ≤ 0 時 nil
        let converted: Double?
    }

    enum Missing: Equatable {
        case asking, newPrice
    }

    struct Summary: Equatable {
        let count: Int
        let low: Double
        let high: Double
        let median: Double
        /// 中位數 × askMarkup，四捨五入到 roundStep
        let suggested: Double
        /// 心理底價（第 25 百分位，或不到 4 台時最低的那台），四捨五入到 roundStep
        let bottom: Double
        let bottomUsesMin: Bool
    }

    /// 選配勾了誰
    struct Usage: Equatable {
        var mine = false
        var listings = 0
        var total: Int { (mine ? 1 : 0) + listings }
    }

    struct OptionDiff: Equatable {
        /// 我有、它沒有（照清單順序）
        let missing: [VehicleResaleOption]
        /// 它有、我沒有
        let extra: [VehicleResaleOption]
    }

    static func positive(_ v: Double?) -> Double? {
        guard let v, v.isFinite, v > 0 else { return nil }
        return v
    }

    /// 名稱比對用：去頭尾空白、不分大小寫（只用在「清單上是不是已經有同名的」）
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 清單上有勾的那幾項（照清單順序；清單上已經沒有的 id 不算）
    static func checked(_ ids: [UUID], catalog: [VehicleResaleOption]) -> [VehicleResaleOption] {
        let set = Set(ids)
        return catalog.filter { set.contains($0.id) }
    }

    /// 勾的選配原價合計（沒填價格算 0）
    static func optionsTotal(_ ids: [UUID], catalog: [VehicleResaleOption]) -> Double {
        var sum = 0.0
        for o in checked(ids, catalog: catalog) {
            sum += max(0, o.price ?? 0)
        }
        return sum
    }

    /// 出廠到今天幾個月（只看年月；月份沒填當 unknownMonth）；沒填年回 nil
    static func ageMonths(year: Int?, month: Int?, today: Date, calendar: Calendar) -> Int? {
        guard let year, year > 1900 else { return nil }
        let m = min(12, max(1, month ?? unknownMonth))
        let c = calendar.dateComponents([.year, .month], from: today)
        let ty = c.year ?? year
        let tm = c.month ?? m
        return max(0, (ty - year) * 12 + (tm - m))
    }

    static func mine(_ ws: VehicleResaleWorkspace, today: Date, calendar: Calendar) -> Mine {
        Mine(newPrice: positive(ws.newPrice) ?? 0,
             optionsTotal: optionsTotal(ws.myOptionIds, catalog: ws.options),
             ageMonths: ageMonths(year: ws.builtYear, month: ws.builtMonth, today: today, calendar: calendar),
             km: positive(ws.mileageKm))
    }

    /// 這台缺什麼所以先不算（先看標價、再看新車原價）
    static func missing(_ l: VehicleResaleListing) -> Missing? {
        if positive(l.askingPrice) == nil { return .asking }
        if positive(l.newPrice) == nil { return .newPrice }
        return nil
    }

    static func compare(_ l: VehicleResaleListing, mine: Mine, catalog: [VehicleResaleOption],
                        today: Date, calendar: Calendar) -> Comparison? {
        guard let asking = positive(l.askingPrice), let price = positive(l.newPrice) else { return nil }
        let total = price + optionsTotal(l.optionIds, catalog: catalog)
        let rate = asking / total
        let age = ageMonths(year: l.builtYear, month: l.builtMonth, today: today, calendar: calendar)
        let km = positive(l.mileageKm)
        var kmDiff: Double? = nil
        var kmAdjust = 0.0
        if let theirs = km, let myKm = mine.km {
            kmDiff = theirs - myKm
            kmAdjust = (theirs - myKm) / 10_000 * mileagePointsPer10kKm
        }
        var ageDiff: Int? = nil
        var ageAdjust = 0.0
        if let theirs = age, let myAge = mine.ageMonths {
            ageDiff = theirs - myAge
            ageAdjust = Double(theirs - myAge) / 12 * agePointsPerYear
        }
        let adjusted = max(0, rate + kmAdjust + ageAdjust)
        let converted: Double? = mine.newTotal > 0 ? mine.newTotal * adjusted : nil
        return Comparison(newTotal: total, asking: asking, rate: rate, ageMonths: age, km: km,
                          kmDiff: kmDiff, ageDiffMonths: ageDiff, kmAdjust: kmAdjust, ageAdjust: ageAdjust,
                          adjustedRate: adjusted, converted: converted)
    }

    /// 每台換算成我的車的價格 → 區間、中位數、建議標價、心理底價；一台都沒有回 nil
    static func summary(_ values: [Double]) -> Summary? {
        let v = values.filter { $0.isFinite }.sorted()
        guard let first = v.first, let last = v.last else { return nil }
        let med = median(v)
        let usesMin = v.count < percentileMinCount
        let rawBottom = usesMin ? first : percentile(v, bottomPercentile)
        return Summary(count: v.count, low: first, high: last, median: med,
                       suggested: roundToStep(med * askMarkup), bottom: roundToStep(rawBottom),
                       bottomUsesMin: usesMin)
    }

    /// sorted 要先排好
    static func median(_ sorted: [Double]) -> Double {
        let n = sorted.count
        guard n > 0 else { return 0 }
        if n % 2 == 1 { return sorted[n / 2] }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }

    /// 線性內插（同 Excel PERCENTILE.INC、numpy 預設）；sorted 要先排好
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard let first = sorted.first else { return 0 }
        guard sorted.count > 1 else { return first }
        let pos = p * Double(sorted.count - 1)
        let lo = Int(pos.rounded(.down))
        let hi = min(sorted.count - 1, lo + 1)
        let frac = pos - Double(lo)
        return sorted[lo] + (sorted[hi] - sorted[lo]) * frac
    }

    /// 四捨五入到千元（.rounded() 是一般的四捨五入：.5 進位）
    static func roundToStep(_ v: Double) -> Double {
        (v / roundStep).rounded() * roundStep
    }

    /// 少了／多了哪些選配：直接用 id 比
    static func diff(mine: [UUID], theirs: [UUID], catalog: [VehicleResaleOption]) -> OptionDiff {
        let m = Set(mine)
        let t = Set(theirs)
        let missing = catalog.filter { m.contains($0.id) && !t.contains($0.id) }
        let extra = catalog.filter { t.contains($0.id) && !m.contains($0.id) }
        return OptionDiff(missing: missing, extra: extra)
    }

    /// 每個選配有誰勾（刪除前確認、清單上的「我的車和市場上 2 台勾了」）
    static func usage(_ ws: VehicleResaleWorkspace) -> [UUID: Usage] {
        var out: [UUID: Usage] = [:]
        for id in ws.myOptionIds {
            out[id, default: Usage()].mine = true
        }
        for l in ws.listings {
            for id in Set(l.optionIds) {
                out[id, default: Usage()].listings += 1
            }
        }
        return out
    }
}

// MARK: - 字

enum VehicleResaleText {
    /// 西曆（手機設民國曆也一樣）
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "zh_TW")
        return c
    }()

    /// 「NT$268.5萬」（全 App 共用的萬／億格式）
    static func money(_ v: Double) -> String { v.ntdWanString }

    /// 「NT$2,685,000」
    static func full(_ v: Double) -> String { "NT$" + FinanceItemText.number(v.rounded(), digits: 0) }

    /// 「35,000 公里」
    static func km(_ v: Double) -> String { FinanceItemText.number(v.rounded(), digits: 0) + " 公里" }

    /// 「52.8%」
    static func pct(_ r: Double) -> String { String(format: "%.1f%%", r * 100) }

    /// 「+2.6 個百分點」「−0.8 個百分點」；小到四捨五入是 0.0 時 nil（畫面寫「幾乎不變」）
    static func points(_ r: Double) -> String? {
        let s = String(format: "%.1f", abs(r * 100))
        guard s != "0.0" else { return nil }
        let sign = r > 0 ? "+" : "−"
        return sign + s + " 個百分點"
    }

    /// 係數說明用：一位小數、整數不寫 .0（1.5、8）
    static func plain(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? String(format: "%.0f", r) : String(format: "%.1f", r)
    }

    /// 「4 年 1 個月」「7 個月」「2 年」「不到 1 個月」
    static func span(months: Int) -> String {
        let m = max(0, months)
        if m == 0 { return "不到 1 個月" }
        let y = m / 12
        let r = m % 12
        if y == 0 { return "\(r) 個月" }
        return r == 0 ? "\(y) 年" : "\(y) 年 \(r) 個月"
    }

    /// 「2022/9」；只有年份「2022 年」
    static func ym(year: Int, month: Int?) -> String {
        guard let month else { return "\(year) 年" }
        return "\(year)/\(month)"
    }

    /// 「2026/9」
    static func ym(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month], from: d)
        return "\(c.year ?? 0)/\(c.month ?? 0)"
    }

    /// 「2026/9/30」
    static func ymd(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// 選配列右邊：「NT$12萬」；沒填「沒填價格」
    static func optionPrice(_ price: Double?) -> String {
        guard let p = VehicleResaleMath.positive(price) else { return "沒填價格" }
        return money(p)
    }

    /// 誰勾了這個選配：「我的車和市場上 2 台」「我的車」「市場上 1 台」；沒人勾是空字串
    static func who(_ u: VehicleResaleMath.Usage?) -> String {
        let mine = u?.mine ?? false
        let n = u?.listings ?? 0
        if mine && n > 0 { return "我的車和市場上 \(n) 台" }
        if mine { return "我的車" }
        if n > 0 { return "市場上 \(n) 台" }
        return ""
    }

    /// 網址：沒寫 http(s):// 的補 https://；看不懂回 nil（畫面就不放「網頁」那顆）
    static func url(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let lower = t.lowercased()
        let full = (lower.hasPrefix("http://") || lower.hasPrefix("https://")) ? t : "https://" + t
        guard let u = URL(string: full), u.host() != nil else { return nil }
        return u
    }
}

// MARK: - 畫面上的每一個字

struct VehicleResaleReport: Equatable {
    /// 白卡裡的一列：左標籤、右值（下面可以接一行灰字）
    struct Row: Identifiable, Equatable {
        let id: String
        let label: String
        let value: String
        var detail: String? = nil
        var strong = false
    }

    /// 選配清單的一列（我的車那張卡的選配也用它，usage 空字串）
    struct OptionRow: Identifiable, Equatable {
        let id: UUID
        let name: String
        let priceText: String
        let priceMissing: Bool
        let usage: String
    }

    /// 市場上那台跟我的車比，選配少了／多了／一樣
    struct OptionLine: Identifiable, Equatable {
        enum Kind: Equatable {
            case missing, extra, same
        }
        let kind: Kind
        let text: String
        var id: String { "\(kind)-\(text)" }
    }

    struct MyCar: Equatable {
        let rows: [Row]
        let options: [OptionRow]
        /// 卡片最下面那一行（點了編輯）
        let hint: String
    }

    struct Summary: Equatable {
        let suggested: Double
        let suggestedText: String
        /// 「NT$2,755,000・中位數 NT$262.4萬 × 1.05，四捨五入到千元」
        let suggestedDetail: String
        /// 估值區間、中位數、心理底價
        let rows: [Row]
        /// 「用 3 台算」「用 3 台算・1 台資料不夠」
        let countText: String
        /// 1～2 台：「再多加幾台會更準」
        let hint: String?
    }

    struct Listing: Identifiable, Equatable {
        let id: UUID
        let title: String
        let link: URL?
        /// 「2022/3・4 年 7 個月・48,000 公里・2026/10/12 看到」
        let subtitle: String
        let rows: [Row]
        /// 里程、車齡各一句（怎麼調成我的車）
        let steps: [String]
        let optionLines: [OptionLine]
        /// 缺標價、缺原價：「這台先不算」
        let problem: String?
        let note: String
    }

    let myCar: MyCar
    let summary: Summary?
    /// summary 是 nil 時寫的那一句
    let emptyText: String
    let catalog: [OptionRow]
    let catalogTrailing: String?
    let catalogEmptyText: String
    let listings: [Listing]
    let listingsTrailing: String?
    let valueRow: Row
    /// 有建議標價、而且跟目前估值不一樣才給按
    let canApply: Bool
    let applyMessage: String
    let footnotes: [String]

    static func displayName(_ v: Vehicle) -> String {
        let name = v.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "未命名車輛" : name
    }

    private static func money(_ v: Double) -> String { VehicleResaleText.money(v) }

    static func build(vehicle v: Vehicle, workspace ws: VehicleResaleWorkspace, isSaved: Bool,
                      today: Date, calendar: Calendar = VehicleResaleText.calendar) -> VehicleResaleReport {
        let mine = VehicleResaleMath.mine(ws, today: today, calendar: calendar)
        var listings: [Listing] = []
        var values: [Double] = []
        for (i, l) in ws.listings.enumerated() {
            let comp = VehicleResaleMath.compare(l, mine: mine, catalog: ws.options, today: today, calendar: calendar)
            if let c = comp?.converted { values.append(c) }
            listings.append(makeListing(l, index: i, comp: comp, mine: mine, ws: ws, today: today, calendar: calendar))
        }
        let math = VehicleResaleMath.summary(values)
        let skipped = ws.listings.count - values.count
        let summary: Summary? = math.map { makeSummary($0, skipped: skipped) }
        let canApply = math.map { abs($0.suggested - v.currentValue) >= 1 } ?? false
        return VehicleResaleReport(
            myCar: makeMyCar(v, ws: ws, mine: mine, isSaved: isSaved),
            summary: summary,
            emptyText: makeEmptyText(ws, mine: mine),
            catalog: makeCatalog(ws),
            catalogTrailing: ws.options.isEmpty ? nil : "\(ws.options.count) 項",
            catalogEmptyText: "先列出這款車有哪些選配和原價（例：Sport Chrono 套件 NT$12萬），我的車和市場上的車就能直接打勾比較。",
            listings: listings,
            listingsTrailing: ws.listings.isEmpty ? nil : "\(ws.listings.count) 台",
            valueRow: makeValueRow(v),
            canApply: canApply,
            applyMessage: makeApplyMessage(v),
            footnotes: footnoteLines)
    }

    /// 車輛卡入口那一行
    static func entrySubtitle(_ v: Vehicle, today: Date, calendar: Calendar = VehicleResaleText.calendar) -> String {
        guard let ws = v.resale else { return "列出選配、記下市場上看到的車，幫你算建議標價" }
        let mine = VehicleResaleMath.mine(ws, today: today, calendar: calendar)
        let values = ws.listings.compactMap { l in
            VehicleResaleMath.compare(l, mine: mine, catalog: ws.options, today: today, calendar: calendar)?.converted
        }
        if let s = VehicleResaleMath.summary(values) {
            return "建議標價 \(money(s.suggested))・比了 \(s.count) 台"
        }
        return ws.listings.isEmpty ? "已填我的車，再加幾台市場上看到的車" : "市場上的車還缺標價或原價，補上就算得出來"
    }

    // MARK: 我的車

    private static func makeMyCar(_ v: Vehicle, ws: VehicleResaleWorkspace, mine: VehicleResaleMath.Mine,
                                  isSaved: Bool) -> MyCar {
        let checked = VehicleResaleMath.checked(ws.myOptionIds, catalog: ws.options)
        let unpriced = checked.filter { VehicleResaleMath.positive($0.price) == nil }.count
        var rows: [Row] = []
        rows.append(Row(id: "name", label: "車子", value: displayName(v)))
        let built = builtText(year: ws.builtYear, month: ws.builtMonth, age: mine.ageMonths)
        rows.append(Row(id: "built", label: "出廠／領牌", value: built ?? "還沒填（不調車齡）"))
        rows.append(Row(id: "price", label: "新車原價", value: mine.newPrice > 0 ? money(mine.newPrice) : "還沒填",
                        detail: "不含選配"))
        let optionValue = checked.isEmpty ? "沒勾" : "\(checked.count) 項・\(money(mine.optionsTotal))"
        let optionDetail: String? = unpriced > 0 ? "\(unpriced) 項沒填價格，先算 0" : nil
        rows.append(Row(id: "options", label: "選配", value: optionValue, detail: optionDetail))
        rows.append(Row(id: "total", label: "新車總值", value: mine.newTotal > 0 ? money(mine.newTotal) : "還沒填",
                        detail: "新車原價＋選配", strong: true))
        let kmValue = mine.km.map { VehicleResaleText.km($0) } ?? "還沒填（不調里程）"
        rows.append(Row(id: "km", label: "目前里程", value: kmValue))
        var options: [OptionRow] = []
        for o in checked {
            options.append(OptionRow(id: o.id, name: o.name, priceText: VehicleResaleText.optionPrice(o.price),
                                     priceMissing: VehicleResaleMath.positive(o.price) == nil, usage: ""))
        }
        let hint: String
        if !isSaved {
            hint = "先用車輛資料帶入（購入日、購入價），點這裡改成正確的、勾上你的選配"
        } else if mine.newPrice <= 0 {
            hint = "先填新車原價，才換算得出來"
        } else {
            hint = "編輯我的車和選配"
        }
        return MyCar(rows: rows, options: options, hint: hint)
    }

    /// 「2022/9・4 年 1 個月」；沒填年 nil
    private static func builtText(year: Int?, month: Int?, age: Int?) -> String? {
        guard let year else { return nil }
        var s = VehicleResaleText.ym(year: year, month: month)
        if let age { s += "・" + VehicleResaleText.span(months: age) }
        return s
    }

    // MARK: 選配清單

    private static func makeCatalog(_ ws: VehicleResaleWorkspace) -> [OptionRow] {
        let usage = VehicleResaleMath.usage(ws)
        var out: [OptionRow] = []
        for o in ws.options {
            let who = VehicleResaleText.who(usage[o.id])
            let name = o.name.trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(OptionRow(id: o.id, name: name.isEmpty ? "未命名選配" : name,
                                 priceText: VehicleResaleText.optionPrice(o.price),
                                 priceMissing: VehicleResaleMath.positive(o.price) == nil,
                                 usage: who.isEmpty ? "還沒有車勾" : who + "勾了"))
        }
        return out
    }

    // MARK: 估價結果

    private static func makeSummary(_ s: VehicleResaleMath.Summary, skipped: Int) -> Summary {
        let range = s.count == 1 ? money(s.low) : "\(money(s.low)) ～ \(money(s.high))"
        let rangeDetail: String? = s.count == 1 ? "只有 1 台" : nil
        let bottomDetail = s.bottomUsesMin
            ? "不到 \(VehicleResaleMath.percentileMinCount) 台，先用最低的那台"
            : "最低的四分之一（第 25 百分位）"
        let rows: [Row] = [
            Row(id: "range", label: "估值區間", value: range, detail: rangeDetail),
            Row(id: "median", label: "中位數", value: money(s.median)),
            Row(id: "bottom", label: "心理底價", value: money(s.bottom), detail: bottomDetail, strong: true)
        ]
        var count = "用 \(s.count) 台算"
        if skipped > 0 { count += "・\(skipped) 台資料不夠" }
        let hint: String? = s.count <= 2 ? "再多加幾台會更準" : nil
        let markup = String(format: "%.2f", VehicleResaleMath.askMarkup)
        let detail = "\(VehicleResaleText.full(s.suggested))・中位數 \(money(s.median)) × \(markup)，四捨五入到千元"
        return Summary(suggested: s.suggested, suggestedText: money(s.suggested), suggestedDetail: detail,
                       rows: rows, countText: count, hint: hint)
    }

    private static func makeEmptyText(_ ws: VehicleResaleWorkspace, mine: VehicleResaleMath.Mine) -> String {
        if ws.listings.isEmpty {
            return "加一台市場上看到的車（8891、臉書社團、車商網站都可以），就算得出建議標價。"
        }
        if mine.newTotal <= 0 { return "先在「我的車」填新車原價，才換算得出來。" }
        return "市場上的車還缺二手標價或新車原價，補上就算得出來。"
    }

    private static func valueKnown(_ v: Vehicle) -> Bool {
        v.currentValue > 0 || v.valueUpdatedAt != nil
    }

    private static func makeValueRow(_ v: Vehicle) -> Row {
        // 標籤欄只有 104pt：「你的車目前估值」七個字會折行，說法放到下面那行灰字
        guard valueKnown(v) else {
            return Row(id: "value", label: "目前估值", value: "還沒填", detail: "你的車目前還沒填估值，車輛卡先用購入價")
        }
        var detail = "你的車目前的估值（車輛卡、淨資產用這個）"
        if let at = v.valueUpdatedAt { detail += "・" + VehicleResaleText.ym(at) + " 更新" }
        return Row(id: "value", label: "目前估值", value: money(v.currentValue), detail: detail)
    }

    private static func makeApplyMessage(_ v: Vehicle) -> String {
        let now = valueKnown(v) ? "現在是 \(money(v.currentValue))" : "現在還沒填估值"
        return "車輛卡和理財總覽的淨資產都會改用這個估值（\(now)）。之後在編輯頁也能再改。"
    }

    // MARK: 市場上的一台

    private static func makeListing(_ l: VehicleResaleListing, index: Int, comp: VehicleResaleMath.Comparison?,
                                    mine: VehicleResaleMath.Mine, ws: VehicleResaleWorkspace,
                                    today: Date, calendar: Calendar) -> Listing {
        let trimmed = l.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "第 \(index + 1) 台" : trimmed
        let age = VehicleResaleMath.ageMonths(year: l.builtYear, month: l.builtMonth, today: today, calendar: calendar)
        var steps: [String] = []
        if let c = comp {
            steps = [kmStep(c, mine: mine), ageStep(c, listing: l, mine: mine)]
        }
        return Listing(id: l.id, title: title, link: VehicleResaleText.url(l.link),
                       subtitle: listingSubtitle(l, age: age),
                       rows: listingRows(l, comp: comp, mine: mine, catalog: ws.options),
                       steps: steps,
                       optionLines: optionLines(mine: ws.myOptionIds, theirs: l.optionIds, catalog: ws.options),
                       problem: problem(l),
                       note: l.note.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func listingSubtitle(_ l: VehicleResaleListing, age: Int?) -> String {
        var parts: [String] = []
        parts.append(builtText(year: l.builtYear, month: l.builtMonth, age: age) ?? "沒填年份")
        parts.append(VehicleResaleMath.positive(l.mileageKm).map { VehicleResaleText.km($0) } ?? "沒填里程")
        if let seen = l.seenDate { parts.append(VehicleResaleText.ymd(seen) + " 看到") }
        return parts.joined(separator: "・")
    }

    private static func listingRows(_ l: VehicleResaleListing, comp: VehicleResaleMath.Comparison?,
                                    mine: VehicleResaleMath.Mine, catalog: [VehicleResaleOption]) -> [Row] {
        var rows: [Row] = []
        let checked = VehicleResaleMath.checked(l.optionIds, catalog: catalog)
        let optTotal = VehicleResaleMath.optionsTotal(l.optionIds, catalog: catalog)
        let unpriced = checked.filter { VehicleResaleMath.positive($0.price) == nil }.count
        if let price = VehicleResaleMath.positive(l.newPrice) {
            let value = checked.isEmpty ? money(price) : "\(money(price)) ＋ \(money(optTotal)) ＝ \(money(price + optTotal))"
            var detail = checked.isEmpty ? "沒勾選配" : "勾了 \(checked.count) 項選配"
            if unpriced > 0 { detail += "・\(unpriced) 項沒填價格，算 0" }
            rows.append(Row(id: "total", label: "原價＋選配", value: value, detail: detail))
        }
        if let asking = VehicleResaleMath.positive(l.askingPrice) {
            rows.append(Row(id: "asking", label: "二手標價", value: money(asking)))
        }
        guard let c = comp else { return rows }
        rows.append(Row(id: "rate", label: "殘值率", value: VehicleResaleText.pct(c.rate), detail: "標價 ÷ 原價＋選配"))
        if c.kmAdjust != 0 || c.ageAdjust != 0 {
            rows.append(Row(id: "adjusted", label: "調整後殘值率", value: VehicleResaleText.pct(c.adjustedRate),
                            detail: "照你的車齡、里程調過"))
        }
        if let converted = c.converted {
            let how = "\(money(mine.newTotal)) × \(VehicleResaleText.pct(c.adjustedRate))"
            rows.append(Row(id: "converted", label: "換算成我的車", value: money(converted), detail: how, strong: true))
        } else {
            rows.append(Row(id: "converted", label: "換算成我的車", value: "—", detail: "先填我的車的新車原價"))
        }
        return rows
    }

    private static func kmStep(_ c: VehicleResaleMath.Comparison, mine: VehicleResaleMath.Mine) -> String {
        guard let d = c.kmDiff else {
            return mine.km == nil ? "里程：你的車還沒填里程，不調" : "里程：它沒填里程，不調"
        }
        if abs(d) < 1 { return "里程：跟你一樣，不調" }
        let verb = d > 0 ? "多跑" : "少跑"
        let head = "里程：它比你\(verb) \(VehicleResaleText.km(abs(d)))"
        guard let pts = VehicleResaleText.points(c.kmAdjust) else { return head + "，殘值率幾乎不變" }
        return head + "，殘值率 " + pts
    }

    private static func ageStep(_ c: VehicleResaleMath.Comparison, listing l: VehicleResaleListing,
                                mine: VehicleResaleMath.Mine) -> String {
        guard let d = c.ageDiffMonths else {
            return mine.ageMonths == nil ? "車齡：你的車還沒填出廠年月，不調" : "車齡：它沒填年份，不調"
        }
        let guess = l.builtMonth == nil ? "（它只填年份，當 \(VehicleResaleMath.unknownMonth) 月出廠算）" : ""
        if d == 0 { return "車齡：跟你同年同月，不調" + guess }
        let verb = d > 0 ? "老" : "新"
        let head = "車齡：它比你\(verb) \(VehicleResaleText.span(months: abs(d)))"
        guard let pts = VehicleResaleText.points(c.ageAdjust) else { return head + "，殘值率幾乎不變" + guess }
        return head + "，殘值率 " + pts + guess
    }

    private static func optionLines(mine: [UUID], theirs: [UUID], catalog: [VehicleResaleOption]) -> [OptionLine] {
        let diff = VehicleResaleMath.diff(mine: mine, theirs: theirs, catalog: catalog)
        var out: [OptionLine] = []
        if !diff.missing.isEmpty {
            out.append(OptionLine(kind: .missing, text: "少了 " + names(diff.missing)))
        }
        if !diff.extra.isEmpty {
            out.append(OptionLine(kind: .extra, text: "多了 " + names(diff.extra)))
        }
        if out.isEmpty, !VehicleResaleMath.checked(mine, catalog: catalog).isEmpty {
            out.append(OptionLine(kind: .same, text: "選配跟你的一樣"))
        }
        return out
    }

    private static func names(_ list: [VehicleResaleOption]) -> String {
        list.map { o -> String in
            let n = o.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? "未命名選配" : n
        }.joined(separator: "、")
    }

    private static func problem(_ l: VehicleResaleListing) -> String? {
        guard let m = VehicleResaleMath.missing(l) else { return nil }
        switch m {
        case .asking: return "還沒填二手標價，這台先不算"
        case .newPrice: return "還沒填新車原價，算不出殘值率，這台先不算"
        }
    }

    // MARK: 怎麼算的

    static var footnoteLines: [String] {
        let km = VehicleResaleText.plain(VehicleResaleMath.mileagePointsPer10kKm * 100)
        let age = VehicleResaleText.plain(VehicleResaleMath.agePointsPerYear * 100)
        let markup = String(format: "%.2f", VehicleResaleMath.askMarkup)
        let minCount = VehicleResaleMath.percentileMinCount
        let month = VehicleResaleMath.unknownMonth
        return [
            "每台的殘值率＝二手標價 ÷（新車原價＋勾的選配原價）。選配的差別已經算在新車總值裡，沒填價格的選配算 0。",
            "里程：它每比你多跑 1 萬公里，殘值率加 \(km) 個百分點；少跑就減。",
            "車齡：它每比你老 1 年，殘值率加 \(age) 個百分點；比較新就減（只填年份的當 \(month) 月出廠）。",
            "換算成你的車＝你的新車總值 × 調整後殘值率。",
            "建議標價＝換算結果的中位數 × \(markup)（留一點讓買家殺價），四捨五入到千元；心理底價＝最低的四分之一，不到 \(minCount) 台先用最低的那台。",
            "網路上的是賣家開價，成交通常再低一些；這裡算的是「開價」，只是參考。"
        ]
    }
}
