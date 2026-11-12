import Foundation

// [v25.622] 水電趨勢 v3：每一期的度數、計費期間（judge_utility C2–C6、C13 的規則部分）。
// - 同步鍵 lifegood_utility_readings_v1（UtilityReadingBook），用 UtilityPayment.id 當 key。
//   UtilityPayment／UtilityMeter／RealEstate 一個欄位都沒加：還沒更新的 iPad 改任何一間房子都會整包重寫
//   lifegood_realestates、洗掉不認得的欄位；這個鍵它不認得、不會碰。
// - 讀只准問 UtilityReadingIndex.value(for:)（base 對不上、墓碑、壞值都在這裡擋掉；CSV、趨勢、表單都走這支）。
// - 寫只有：繳費表單存檔（recordSave）、整理重複（recordMove）、備份匯入、iCloud 合併、清除所有資料。
//   開 App、背景、同步、畫面算資料時一律不寫（commit 只在這幾條路裡清墓碑）。
// - 日期只存「2026-07-13」（UtilityDay；H2：在哪個時區打開都是那一天），不存 Date。
// - 這個檔只進 App target（不進小工具、手錶）；字只在房子詳情、水電趨勢、繳費表單出現。

// MARK: - 日期 key（只准用這一組）

enum UtilityDay {
    /// 「2026-07-13」（手機日曆的那一天）
    static func key(_ d: Date) -> String { WealthCal.dayKey(d) }

    /// 「2026-07-13」→ 那天 00:00；格式不對、沒有這天（2-30）＝nil
    static func date(_ k: String) -> Date? { WealthTransferSchedule.date(fromKey: k) }

    /// b − a 幾個日曆日
    static func days(_ a: Date, _ b: Date) -> Int { WealthCal.days(from: a, to: b) }

    /// 計費期間幾天：頭尾都算（7/13–9/11＝61）
    static func span(_ a: Date, _ b: Date) -> Int { days(a, b) + 1 }
}

// MARK: - 新鍵的資料長相（C3）

/// 同步鍵 lifegood_utility_readings_v1：每一期水電的度數、計費期間、帳單標記（UtilityPayment.id 當 key）。
/// 不加在 UtilityPayment 上：還沒更新的 iPad 改任何一間房子都會整包重寫 lifegood_realestates、洗掉不認得的欄位；這個鍵它不碰。
struct UtilityReadingBook: Codable, Equatable {
    /// 同步鍵（UtilityReadingStore 存讀、CloudSyncManager.syncKeys 用同一個字）
    static let syncKey = "lifegood_utility_readings_v1"
    /// 墓碑留幾天（另一台還沒同步的舊值不會把它長回來）
    static let tombstoneDays = 30

    /// 逐筆解（壞一筆只丟那筆）
    var readings: [UtilityReading]?
    var extra: [String: JSONValue]?
}

struct UtilityReading: Codable, Equatable {
    /// ＝ UtilityPayment.id
    var id: UUID
    /// 只給除錯；算數不看
    var estateId: UUID?
    /// 寫入那時的 UtilityPayment.type.rawValue（「電費」）；跟現在的類型對不上就不算（M7）
    var base: String?
    /// 度（電 kWh；水、天然瓦斯 1 度＝1 立方公尺）
    var usage: Double?
    /// 「2026-07-13」日期 key（H2，不存 Date）
    var periodStart: String?
    /// 「2026-09-11」
    var periodEnd: String?
    /// 本期指數：v5 才有畫面，v3 先定欄位（免得 v3 的裝置存回去洗掉）
    var meterReading: Double?
    /// nil＝一般；「估計」「補繳」「扣減」（v4 才有畫面）。字串，不是 enum
    var billKind: String?
    /// 寫入一律填；讀到 nil 當 distantPast
    var updatedAt: Date?
    var extra: [String: JSONValue]?

    /// 墓碑＝度數、期間、指數、標記全 nil（只剩 id＋updatedAt）
    var isTombstone: Bool {
        usage == nil && periodStart == nil && periodEnd == nil && meterReading == nil && billKind == nil
    }
}

extension UtilityReadingBook {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case readings
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        readings = CompetencyCoding.lossyArray(UtilityReading.self, c, .readings)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(readings, forKey: .readings)
    }
}

extension UtilityReading {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, estateId, base, usage, periodStart, periodEnd, meterReading, billKind, updatedAt
    }
    static let knownKeys: Set<String> = Set(CodingKeys.allCases.map { $0.rawValue })

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        estateId = try? c.decodeIfPresent(UUID.self, forKey: .estateId)
        base = try? c.decodeIfPresent(String.self, forKey: .base)
        usage = try? c.decodeIfPresent(Double.self, forKey: .usage)
        periodStart = try? c.decodeIfPresent(String.self, forKey: .periodStart)
        periodEnd = try? c.decodeIfPresent(String.self, forKey: .periodEnd)
        meterReading = try? c.decodeIfPresent(Double.self, forKey: .meterReading)
        billKind = try? c.decodeIfPresent(String.self, forKey: .billKind)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        extra = CompetencyCoding.readExtra(decoder, known: Self.knownKeys)
    }

    func encode(to encoder: Encoder) throws {
        try CompetencyCoding.writeExtra(extra, encoder, known: Self.knownKeys)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(estateId, forKey: .estateId)
        try c.encodeIfPresent(base, forKey: .base)
        try c.encodeIfPresent(usage, forKey: .usage)
        try c.encodeIfPresent(periodStart, forKey: .periodStart)
        try c.encodeIfPresent(periodEnd, forKey: .periodEnd)
        try c.encodeIfPresent(meterReading, forKey: .meterReading)
        try c.encodeIfPresent(billKind, forKey: .billKind)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - 表單填的那兩欄（打開時一份、存檔時一份；一樣就不寫）

/// 度數＋計費期間（期間是日期 key）。三個都 nil＝空的
struct UtilityReadingDraft: Equatable {
    var usage: Double?
    var startKey: String?
    var endKey: String?

    static let empty = UtilityReadingDraft(usage: nil, startKey: nil, endKey: nil)

    var isEmpty: Bool { usage == nil && startKey == nil && endKey == nil }
}

// MARK: - 合併、清墓碑、寫（純函式；UtilityReadingStore 只叫這些）

extension UtilityReadingBook {
    var isEmpty: Bool { (readings ?? []).isEmpty }

    /// 同一個 id 的原始那筆（不驗證；有兩筆時留 updatedAt 新的）
    func rawReading(_ id: UUID) -> UtilityReading? {
        var best: UtilityReading? = nil
        for r in readings ?? [] where r.id == id {
            if let b = best, (b.updatedAt ?? .distantPast) >= (r.updatedAt ?? .distantPast) { continue }
            best = r
        }
        return best
    }

    /// 新增或整筆換掉（同一個 id 只留這一筆）
    mutating func upsert(_ r: UtilityReading) {
        var list: [UtilityReading] = readings ?? []
        list.removeAll { x in x.id == r.id }
        list.append(r)
        readings = list
    }

    /// 兩台合併（iCloud 增量、第一次同步〔合併〕、備份〔合併〕）：照 id 取 updatedAt 新的整筆（一樣新留 self；M10 選 (a)）；
    /// extra 合在一起（self 優先）。合併兩次結果一樣（冪等）
    func merged(with other: UtilityReadingBook) -> UtilityReadingBook {
        var out = self
        out.readings = CompetencyCoding.mergeList(readings, other.readings,
                                                  key: { (r: UtilityReading) -> UUID in r.id },
                                                  stamp: { (r: UtilityReading) -> Date in r.updatedAt ?? .distantPast })
        out.extra = CompetencyCoding.mergeExtra(extra, other.extra)
        return out
    }

    /// 清墓碑（存檔時叫）：只清墓碑、而且 updatedAt 超過 30 天的。沒有要清的回 self
    func purged(now: Date) -> UtilityReadingBook {
        guard let list = readings else { return self }
        let limit: Date = now.addingTimeInterval(-Double(Self.tombstoneDays) * 86_400)
        let kept: [UtilityReading] = list.filter { r in
            guard r.isTombstone else { return true }
            return (r.updatedAt ?? .distantPast) > limit
        }
        guard kept.count != list.count else { return self }
        var out = self
        out.readings = kept
        return out
    }

    /// 第二道防線（commit 先叫）：度數、指數不是有限數（nan、inf）就丟掉那一欄（JSONEncoder 遇到會整包失敗）
    func sanitized() -> UtilityReadingBook {
        guard let list = readings else { return self }
        var changed = false
        var fixed: [UtilityReading] = []
        for r in list {
            var x = r
            if let u = x.usage, !u.isFinite {
                x.usage = nil
                changed = true
            }
            if let m = x.meterReading, !m.isFinite {
                x.meterReading = nil
                changed = true
            }
            fixed.append(x)
        }
        guard changed else { return self }
        var out = self
        out.readings = fixed
        return out
    }

    /// 匯出：只帶這幾期的（照 id）
    func filtered(to ids: Set<UUID>) -> UtilityReadingBook {
        var out = self
        if let list = readings {
            out.readings = list.filter { r in ids.contains(r.id) }
        }
        return out
    }

    /// 取代（只換這幾個 id）：這幾個 id 換成 other 裡的，其他不動
    func replacing(ids: Set<UUID>, with other: UtilityReadingBook) -> UtilityReadingBook {
        var out = self
        let keep: [UtilityReading] = (readings ?? []).filter { r in !ids.contains(r.id) }
        let incoming: [UtilityReading] = (other.readings ?? []).filter { r in ids.contains(r.id) }
        let all: [UtilityReading] = keep + incoming
        out.readings = (readings == nil && all.isEmpty) ? nil : all
        return out
    }

    /// C5：繳費表單存檔。回 nil＝不用寫。
    /// - edited == opened → 不寫（打開時沒有、存的時候也空，一樣不碰：M7）
    /// - edited 全空：原本那筆還有指數或帳單標記（v4／v5 的裝置寫的）→ 留著那兩欄、度數期間清掉；不然寫墓碑
    /// - 其他 → 寫整筆（base＝現在的類型、updatedAt＝now）；原本的 extra 留著，指數、標記只在 base 對得上時留著
    func saving(paymentId: UUID, estateId: UUID, type: UtilityType, opened: UtilityReadingDraft,
                edited: UtilityReadingDraft, now: Date) -> UtilityReadingBook? {
        guard edited != opened else { return nil }
        let raw: UtilityReading? = rawReading(paymentId)
        var r: UtilityReading = raw ?? UtilityReading(id: paymentId)
        let sameBase: Bool = raw?.base == type.rawValue
        if !sameBase {
            r.meterReading = nil
            r.billKind = nil
        }
        r.estateId = estateId
        r.base = type.rawValue
        r.usage = edited.usage
        r.periodStart = edited.startKey
        r.periodEnd = edited.endKey
        r.updatedAt = now
        if r.isTombstone {
            // 墓碑：base 也清掉（跟 ExpenseKindTag 的墓碑一樣只留 id、時間、extra）
            r.base = nil
        }
        var out = self
        out.upsert(r)
        return out
    }

    /// C14：整理重複時，被拿掉那一期的度數搬到留下那一期（新 id、base 用留下那期的類型、updatedAt now）。
    /// 被拿掉那期沒有（驗過的）度數或期間、或留下那期已經有 → nil（不寫）。被拿掉那筆原樣留著（孤兒不算）
    func moving(from: UtilityPayment, to: UtilityPayment, now: Date) -> UtilityReadingBook? {
        let index = UtilityReadingIndex(book: self)
        guard from.id != to.id, index.value(for: from) != nil, index.value(for: to) == nil,
              let src = rawReading(from.id) else { return nil }
        var r: UtilityReading = src
        r.id = to.id
        r.base = to.type.rawValue
        r.updatedAt = now
        var out = self
        out.upsert(r)
        return out
    }
}

// MARK: - 讀（C4：只准問這一支）

/// 驗過的計費期間：兩個 key 都解得開、迄 ≥ 起、天數 1…186、迄日跟繳費日差 ≤ 400 天
struct UtilityReadingPeriod: Equatable {
    let start: Date
    let end: Date
    /// 頭尾都算
    let days: Int
    let startKey: String
    let endKey: String
}

/// 一期驗過的值（index.value(for:) 回的）。全部欄位都壞掉或空的那筆當沒有（回 nil）
struct UtilityReadingValue: Equatable {
    /// 有限數、≥ 0、< 1,000,000 才留
    let usage: Double?
    let period: UtilityReadingPeriod?
    let meterReading: Double?
    let billKind: String?

    /// 表單打開時的那一份
    var draft: UtilityReadingDraft {
        UtilityReadingDraft(usage: usage, startKey: period?.startKey, endKey: period?.endKey)
    }
}

struct UtilityReadingIndex {
    static let maxUsage: Double = 1_000_000
    static let maxDays = 186
    static let maxGapFromPaid = 400

    private let byId: [UUID: UtilityReading]

    init(book: UtilityReadingBook) {
        let list: [UtilityReading] = book.readings ?? []
        // 同一個 id 有兩筆：留 updatedAt 新的（N5；不用 uniqueKeysWithValues）
        byId = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, b in
            (b.updatedAt ?? .distantPast) > (a.updatedAt ?? .distantPast) ? b : a
        })
    }

    static let empty = UtilityReadingIndex(book: UtilityReadingBook())

    /// 這一期驗過的度數、期間。條件：有這個 id、不是墓碑、base == p.type.rawValue（M7）；壞的欄位當沒有
    func value(for p: UtilityPayment) -> UtilityReadingValue? {
        guard let r = byId[p.id], !r.isTombstone, r.base == p.type.rawValue else { return nil }
        let usage: Double? = Self.validUsage(r.usage)
        let period: UtilityReadingPeriod? = Self.validPeriod(start: r.periodStart, end: r.periodEnd, paidOn: p.date)
        let meter: Double? = Self.validMeter(r.meterReading)
        let kind: String? = (r.billKind?.isEmpty ?? true) ? nil : r.billKind
        if usage == nil && period == nil && meter == nil && kind == nil { return nil }
        return UtilityReadingValue(usage: usage, period: period, meterReading: meter, billKind: kind)
    }

    /// 度數：有限數、≥ 0、< 1,000,000（N4、M8）
    static func validUsage(_ v: Double?) -> Double? {
        guard let v, v.isFinite, v >= 0, v < maxUsage else { return nil }
        return v
    }

    static func validMeter(_ v: Double?) -> Double? {
        guard let v, v.isFinite, v >= 0 else { return nil }
        return v
    }

    /// 期間：兩個 key 都解得開、迄 ≥ 起、天數 1…186；迄日跟繳費日差超過 400 天（打錯年份）也當沒有（N1、N2、P1-5）
    static func validPeriod(start: String?, end: String?, paidOn: Date) -> UtilityReadingPeriod? {
        guard let sk = start, let ek = end, let s = UtilityDay.date(sk), let e = UtilityDay.date(ek) else { return nil }
        let span: Int = UtilityDay.span(s, e)
        guard span >= 1, span <= maxDays else { return nil }
        guard abs(UtilityDay.days(e, paidOn)) <= maxGapFromPaid else { return nil }
        return UtilityReadingPeriod(start: s, end: e, days: span, startKey: sk, endKey: ek)
    }
}

// MARK: - 繳費表單的規則（RealEstateEditors.swift 的 UtilityUsageSection／UtilityPaymentEditor 只叫這裡）

/// 度數欄打的字
enum UtilityUsageParse: Equatable {
    /// 空白＝不填
    case empty
    case value(Double)
    /// 負的、nan、inf、≥ 1,000,000、不是數字
    case invalid
}

/// 「上一期」：同一個表（C8）、繳費日比這期早、最近的那一期
struct UtilityPreviousPeriod: Equatable {
    let paymentId: UUID
    let usage: Double?
    let period: UtilityReadingPeriod?

    /// 「上一期 486 度」；上一期沒度數 nil
    var usagePlaceholder: String? {
        guard let u = usage else { return nil }
        return "上一期 " + UtilityMath.usageText(u)
    }
}

/// 打開表單那一刻的基本欄位（快照）。存檔時跟現在的一樣＝「只改了度數那一段」，走快路（C5-1）
struct UtilityEditorBasics: Equatable {
    let type: UtilityType
    /// 繳費日（同一天就算一樣）
    let dayKey: String
    let amountText: String
    let note: String
    let meterId: String?
    let photos: [String]
    let bankId: UUID?
    let bankCurrency: String
    let cardId: UUID?
}

/// 表單一打開就帶好的期間（打開那一刻算一次）
struct UtilityUsageDefaults: Equatable {
    let start: Date
    let end: Date
    /// true＝上一期有期間推出來的（算真的，沒動也存）；false＝從繳費日猜的，只當灰字（沒動過不存，U10）
    let real: Bool
}

enum UtilityUsageForm {
    static let usageError = "度數要填 0 或正的數字"
    static let periodOrderError = "『到』要在『從』之後"
    static let longPeriodWarning = "超過 6 個月了，確定是同一張帳單嗎？（超過 6 個月不算每天平均）"
    static let collapsedTitle = "＋ 度數和計費期間（選填）"

    /// 度數欄：去掉空白和千分位逗號；空的＝不填；負的、nan、inf、≥ 1,000,000、不是數字＝擋存檔（0 可以：空屋）
    static func parseUsage(_ text: String) -> UtilityUsageParse {
        let cleaned: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        if cleaned.isEmpty { return .empty }
        guard let v = Double(cleaned), v.isFinite, v >= 0, v < UtilityReadingIndex.maxUsage else { return .invalid }
        return .value(v)
    }

    /// 紅字（擋存檔）：度數
    static func usageMessage(_ text: String) -> String? {
        parseUsage(text) == .invalid ? usageError : nil
    }

    /// 紅字（擋存檔）：有期間、「到」早於「從」（照日曆日比）
    static func periodMessage(hasPeriod: Bool, start: Date, end: Date) -> String? {
        guard hasPeriod else { return nil }
        return UtilityDay.days(start, end) < 0 ? periodOrderError : nil
    }

    /// 只提醒、不擋：超過 186 天（約 6 個月）
    static func periodWarning(hasPeriod: Bool, start: Date, end: Date) -> String? {
        guard hasPeriod, UtilityDay.days(start, end) >= 0 else { return nil }
        return UtilityDay.span(start, end) > UtilityReadingIndex.maxDays ? longPeriodWarning : nil
    }

    /// 「7/13 – 9/11（約 2 個月）」（表單不顯示天數，UX §3）
    static func periodSummary(start: Date, end: Date) -> String {
        let a: String = HouseCardFormat.md(start)
        let b: String = HouseCardFormat.md(end)
        return "\(a) – \(b)（\(monthsText(start: start, end: end))）"
    }

    /// 「約 2 個月」；不到 20 天「不到 1 個月」
    static func monthsText(start: Date, end: Date) -> String {
        let span: Int = UtilityDay.span(start, end)
        if span < 20 { return "不到 1 個月" }
        let months: Int = max(1, Int((Double(span) / 30.4).rounded()))
        return "約 \(months) 個月"
    }

    /// 〔1 個月〕〔2 個月〕（L6）：到＝從＋N 個月−1 天（月底照 Calendar 截：1/31＋1 個月＝2/28，再 −1 天＝2/27）
    static func endAfter(months n: Int, from start: Date) -> Date {
        let plus: Date = WealthCal.addMonths(n, to: WealthCal.day(start))
        return WealthCal.addDays(-1, to: plus)
    }

    /// 打開那一刻帶的期間：上一期有期間 → 從＝上一期迄＋1、到＝從＋上一期天數−1（算真的）；
    /// 沒有 → 從繳費日猜（到＝繳費日前 7 天、從＝到往前 2 個月＋1 天），只當灰字
    static func defaults(previous: UtilityPreviousPeriod?, paidOn: Date) -> UtilityUsageDefaults {
        if let p = previous?.period {
            let start: Date = WealthCal.addDays(1, to: p.end)
            let end: Date = WealthCal.addDays(p.days - 1, to: start)
            return UtilityUsageDefaults(start: start, end: end, real: true)
        }
        let end: Date = WealthCal.addDays(-7, to: WealthCal.day(paidOn))
        let start: Date = WealthCal.addDays(1, to: WealthCal.addMonths(-2, to: end))
        return UtilityUsageDefaults(start: start, end: end, real: false)
    }

    /// 自動打開：這一期有度數或期間；或同一個表的上一期有度數
    static func autoOpens(opened: UtilityReadingValue?, previous: UtilityPreviousPeriod?) -> Bool {
        if let o = opened, o.usage != nil || o.period != nil { return true }
        return previous?.usage != nil
    }

    /// 存檔時那兩欄的值；nil＝有紅字（擋存檔）。區塊沒打開過 → 原封不動回 opened（不會把預設的期間偷偷存進去）
    static func edited(open: Bool, usageText: String, hasPeriod: Bool, start: Date, end: Date,
                       opened: UtilityReadingDraft) -> UtilityReadingDraft? {
        guard open else { return opened }
        var usage: Double? = nil
        switch parseUsage(usageText) {
        case .empty: usage = nil
        case .value(let v): usage = v
        case .invalid: return nil
        }
        guard periodMessage(hasPeriod: hasPeriod, start: start, end: end) == nil else { return nil }
        let startKey: String? = hasPeriod ? UtilityDay.key(start) : nil
        let endKey: String? = hasPeriod ? UtilityDay.key(end) : nil
        return UtilityReadingDraft(usage: usage, startKey: startKey, endKey: endKey)
    }

    /// 度數帶回輸入框：「702」「28.5」（最多 2 位小數、去掉多餘的 0）
    static func usageFieldText(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "" }
        let rounded: Double = (v * 100).rounded() / 100
        var s = String(format: "%.2f", rounded)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// 「上一期」：同一個表（UtilityMeterSlotIndex.meterOf）、同一種、繳費日（日曆日）比這期早、最近的那筆
    /// （同一天以前有兩筆：陣列裡後面那筆）。這期沒指定是哪個表（同種 2 個表以上又沒選）→ nil
    static func previous(estate: RealEstate, editingId: UUID?, type: UtilityType, meterId: String?, paidOn: Date,
                         index: UtilityReadingIndex) -> UtilityPreviousPeriod? {
        let slots = UtilityMeterSlotIndex(estate.utilityMeterSlots())
        var probe = UtilityPayment(id: editingId ?? UUID(), type: type, date: paidOn)
        probe.meterId = meterId
        let mine: UtilityMeterAssignment = slots.meterOf(probe, type: type)
        guard mine.assigned, let mid = mine.id else { return nil }
        let today: Date = WealthCal.day(paidOn)
        var best: UtilityPayment? = nil
        for p in estate.utilityPayments where p.id != editingId && p.type == type {
            guard WealthCal.day(p.date) < today else { continue }
            let m: UtilityMeterAssignment = slots.meterOf(p, type: type)
            guard m.assigned, m.id == mid else { continue }
            if let b = best, WealthCal.day(b.date) > WealthCal.day(p.date) { continue }
            best = p
        }
        guard let b = best else { return nil }
        let v: UtilityReadingValue? = index.value(for: b)
        return UtilityPreviousPeriod(paymentId: b.id, usage: v?.usage, period: v?.period)
    }

    /// 表單 footer（照種類）
    static func footer(_ t: UtilityType) -> String {
        switch t {
        case .electricity:
            return "帳單上『計費度數』和『計費期間』那兩行。台電一般住家兩個月一期，例如 115/07/13～115/09/11、用了 702 度（115 年就是 2026 年）。不填也沒關係，圖會用金額畫。"
        case .water:
            return "帳單上『用水度數』和『計費期間』（或抄表日）。1 度＝1 立方公尺＝1000 公升，例如兩個月用了 28 度。不填也沒關係，圖會用金額畫。"
        case .gas:
            return "帳單上『使用度數』和『計費期間』，1 度＝1 立方公尺。不填也沒關係，圖會用金額畫。"
        }
    }
}

// MARK: - CSV（UnifiedExport「房地產-水電瓦斯繳費」最後多 5 欄；度數走 value(for:)，L5）

enum UtilityReadingCSV {
    /// 接在原本 6 欄後面（原本 6 欄順序不動）
    static let extraHeader = "meter,usage,periodStart,periodEnd,billKind"

    /// 5 欄的原始字（還沒跳脫；呼叫端照原本的 esc 包 meter、billKind）：
    /// 表的顯示名（「電號 21-40-0218-50-1」「客廳」；沒指定空白）、度數、期間 key、帳單標記
    static func columns(_ u: UtilityPayment, slots: UtilityMeterSlotIndex, index: UtilityReadingIndex) -> [String] {
        let a: UtilityMeterAssignment = slots.meterOf(u, type: u.type)
        let meter: String = a.id.map { slots.displayName($0) } ?? ""
        let v: UtilityReadingValue? = index.value(for: u)
        let usage: String = v?.usage.map { UtilityMath.plainNumber($0) } ?? ""
        let start: String = v?.period?.startKey ?? ""
        let end: String = v?.period?.endKey ?? ""
        let kind: String = v?.billKind ?? ""
        return [meter, usage, start, end, kind]
    }
}

// MARK: - 存、讀、同步（C6）

extension Notification.Name {
    /// UtilityReadingStore 的 book 變了（自己存、iCloud 合併、備份）。FinanceStore 聽這個只跳 modifyID（不指派 realEstates、不存、不推）
    static let utilityReadingsDidChange = Notification.Name("utilityReadingsDidChange")
}

final class UtilityReadingStore: ObservableObject {
    static let shared = UtilityReadingStore()

    @Published private(set) var book: UtilityReadingBook {
        didSet { index = UtilityReadingIndex(book: book) }
    }
    /// 所有畫面、HouseCardData.build 問這個（book 一變就重建）
    private(set) var index: UtilityReadingIndex

    private init() {
        let b = Self.readStored()
        book = b
        index = UtilityReadingIndex(book: b)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadFromCloud(_:)),
            name: .cloudSyncDidPullChanges,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private static func readStored() -> UtilityReadingBook {
        guard let d = UserDefaults.standard.data(forKey: UtilityReadingBook.syncKey),
              let b = try? JSONDecoder().decode(UtilityReadingBook.self, from: d) else { return UtilityReadingBook() }
        return b
    }

    /// 寫進 UserDefaults、推 iCloud。**不碰 realEstates／expenses**（不會引發整包重寫）。
    /// 編碼失敗：印一行、不覆蓋舊資料、不推
    private func persist() {
        do {
            let d = try JSONEncoder().encode(book)
            UserDefaults.standard.set(d, forKey: UtilityReadingBook.syncKey)
        } catch {
            print("[UtilityReadingStore] 度數那一包編碼失敗，沒有存：\(error)")
            return
        }
        CloudSyncManager.shared.pushAll()
    }

    /// 自己寫的唯一一條路：丟掉非有限數（第二道防線）→ 清墓碑 → 跟現在一樣就不動 → 存、推、通知重畫
    private func commit(_ next: UtilityReadingBook, now: Date) {
        let cleaned = next.sanitized().purged(now: now)
        guard cleaned != book else { return }
        book = cleaned
        persist()
        NotificationCenter.default.post(name: .utilityReadingsDidChange, object: nil)
    }

    /// 繳費表單存檔那一刻（dismiss 之後、下一個 runloop 叫）
    func recordSave(paymentId: UUID, estateId: UUID, type: UtilityType, opened: UtilityReadingDraft,
                    edited: UtilityReadingDraft, now: Date = Date()) {
        guard let next = book.saving(paymentId: paymentId, estateId: estateId, type: type,
                                     opened: opened, edited: edited, now: now) else { return }
        commit(next, now: now)
    }

    /// 房子詳情「整理重複」：被拿掉那期的度數搬到留下那期（RealEstateDetailView.mergeDuplicates，store.update 之後同一輪）
    func recordMove(from: UtilityPayment, to: UtilityPayment, now: Date = Date()) {
        guard let next = book.moving(from: from, to: to, now: now) else { return }
        commit(next, now: now)
    }

    /// 匯出：只帶這幾期的
    func exportBook(for ids: Set<UUID>) -> UtilityReadingBook {
        book.filtered(to: ids)
    }

    /// 匯出（UnifiedExport.build，只在帶理財的範圍叫）：這幾間房子全部水電那幾期的；一期水電都沒有 nil（不帶）
    func exportBook(forEstates estates: [RealEstate]) -> UtilityReadingBook? {
        var ids = Set<UUID>()
        for re in estates {
            for p in re.utilityPayments { ids.insert(p.id) }
        }
        return ids.isEmpty ? nil : exportBook(for: ids)
    }

    /// 備份〔取代〕（理財整批歸這份檔案管）：整包換成備份裡的（舊備份沒有這一包＝呼叫端不叫）
    func importReplacingAll(_ other: UtilityReadingBook, now: Date = Date()) {
        commit(other, now: now)
    }

    /// 備份〔合併〕：照 id 合併（一樣新留本機的）
    func importMerging(_ other: UtilityReadingBook, now: Date = Date()) {
        commit(book.merged(with: other), now: now)
    }

    /// 設定「清除所有資料」（FinanceStore.clearAll 叫）：寫一包空的推上去（不是刪鍵：刪鍵的話雲端那份不會被蓋掉）
    func clearAll() {
        let wasEmpty = book == UtilityReadingBook()
        book = UtilityReadingBook()
        persist()
        if !wasEmpty { NotificationCenter.default.post(name: .utilityReadingsDidChange, object: nil) }
    }

    /// 聽 iCloud（照 ExpenseKindStore.reloadFromCloud）：帶了 keys 而且含這個鍵 → 雲端那份併上本機剛才那份，
    /// 合出來跟雲端那份不一樣（本機有它沒有的）就存回去、推上去；沒帶 keys（以雲端覆蓋這台、第一次合併已經合好）照雲端那包
    @objc private func reloadFromCloud(_ note: Notification) {
        let keys = note.userInfo?["keys"] as? [String]
        if let keys, !keys.contains(UtilityReadingBook.syncKey) { return }
        let before = book
        let cloud = Self.readStored()
        let next: UtilityReadingBook = keys == nil ? cloud : cloud.merged(with: before)
        if next != before { book = next }
        if next != cloud { persist() }
        if next != before { NotificationCenter.default.post(name: .utilityReadingsDidChange, object: nil) }
    }
}

/// 第一次同步〔合併〕（CloudSyncManager.resolveInitialSync）：這個鍵最上層是物件，mergeBlob 會整包留勝方、另一邊的度數不見；
/// 解成 Book 照 id 合併。解不開回 nil（退回原本的 mergeBlob）
enum UtilityReadingSync {
    static func handles(_ key: String) -> Bool {
        key == UtilityReadingBook.syncKey
    }

    static func mergeInitialBlob(local: Data?, cloud: Data?, localWins: Bool) -> Data? {
        guard let l = local, let c = cloud else { return nil }
        let dec = JSONDecoder()
        guard let lb = try? dec.decode(UtilityReadingBook.self, from: l),
              let cb = try? dec.decode(UtilityReadingBook.self, from: c) else { return nil }
        let merged: UtilityReadingBook = localWins ? lb.merged(with: cb) : cb.merged(with: lb)
        return try? JSONEncoder().encode(merged.sanitized())
    }
}
