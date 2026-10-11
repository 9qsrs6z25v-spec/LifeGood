import Foundation

// MARK: - 充電與里程分析
//
// [v25.397] 把載具的充電紀錄算成一組 KPI 與趨勢。
//
// 資料來源全部是既有的變動支出欄位（v25.312／313／365 陸續加的）：
//   evKwh（充入度數）、evFromPct／evToPct（起訖電量 %）、evOdometer（里程錶）、
//   placeName／placeAddress（地點）、amount（花費）、date。
// 車子本身只多要兩個欄位：batteryCapacityKWh（原廠標稱）與 homeChargePlace（家充關鍵字）。
//
// 刻意做成純計算型別、不碰 View：這裡每一條公式都有它的陷阱與門檻，
// 混在畫面裡會沒人看得出來哪條是可信的。

struct VehicleChargeAnalytics {

    // MARK: 輸入

    /// 一次充電
    struct Session: Identifiable {
        let id: UUID
        let date: Date
        let kwh: Double
        let cost: Double
        let fromPct: Double?
        let toPct: Double?
        let odometer: Double?
        let place: String
        let isHome: Bool

        /// 這次充了幾 %（起訖都有才算）
        var deltaPct: Double? {
            guard let f = fromPct, let t = toPct, t > f else { return nil }
            return t - f
        }
        var pricePerKwh: Double? { kwh > 0 ? cost / kwh : nil }
    }

    let sessions: [Session]                 // 時間升冪
    let capacityKWh: Double?                // 原廠標稱
    let hasHomeKeyword: Bool                // 有沒有設定家充關鍵字
    /// [v25.538] 一段區間「每度跑幾公里」的合理上限：超過就是中間漏記了充電（見 intervals）
    let maxKmPerKwh: Double

    // MARK: 建構

    /// - Parameters:
    ///   - expenses: 已經篩到「這台車 × 電費 × 有度數」的支出
    ///   - homeKeyword: 家充地點關鍵字（nil／空＝沒設定，全部視為非家充）
    ///   - powerType: [v25.538] 這台車的動力，用來挑每度里程的上限（電動機車 60、其他 12）。
    ///     沒傳的舊呼叫端先用寬的 60：寧可少擋幾段，也不要把電動機車正常的區間全部擋掉
    init(expenses: [Expense], capacityKWh: Double?, homeKeyword: String?,
         powerType: VehiclePowerType? = nil) {
        let key = (homeKeyword ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        self.hasHomeKeyword = !key.isEmpty
        self.capacityKWh = (capacityKWh ?? 0) > 0 ? capacityKWh : nil
        self.maxKmPerKwh = (powerType == nil || powerType == .electricMotorcycle) ? 60 : 12
        self.sessions = expenses
            .sorted { $0.date < $1.date }
            .map { e in
                let place = (e.placeName ?? e.placeAddress ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // [v25.538] 只有一個字的關鍵字（例如「家」）用包含會把「全家」「家樂福」的充電站都當成家充，
                // 家充佔比、家充電價、電池健康分組全被污染：一個字只認地點完全等於它，兩個字以上照舊用包含
                let lowered = place.lowercased()
                let home = !key.isEmpty && (key.count == 1 ? lowered == key : lowered.contains(key))
                return Session(id: e.id, date: e.date, kwh: e.evKwh ?? 0, cost: e.amount,
                               fromPct: e.evFromPct, toPct: e.evToPct,
                               odometer: (e.evOdometer ?? 0) > 0 ? e.evOdometer : nil,
                               place: place.isEmpty ? "未填地點" : place,
                               isHome: home)
            }
    }

    // MARK: - 樣本門檻
    //
    // 少少幾筆算出來的「趨勢」多半是雜訊。畫面在資料不足時要明講還差幾筆，
    // 而不是畫一條會騙人的線。

    static let minTrend = 5          // 趨勢圖最少樣本
    static let minSOHBaseline = 5    // 健康度基準最少樣本
    static let minDeltaPct = 15.0    // 推估容量用的最小充電區間（區間太小誤差被放大）

    var count: Int { sessions.count }

    // MARK: - A. 充電基本盤

    var totalKwh: Double { sessions.reduce(0) { $0 + $1.kwh } }
    var totalCost: Double { sessions.reduce(0) { $0 + $1.cost } }
    var avgPricePerKwh: Double? { totalKwh > 0 ? totalCost / totalKwh : nil }

    /// 平均幾天充一次
    var avgIntervalDays: Double? {
        guard sessions.count >= 2,
              let first = sessions.first?.date, let last = sessions.last?.date else { return nil }
        let days = last.timeIntervalSince(first) / 86400
        guard days > 0 else { return nil }
        return days / Double(sessions.count - 1)
    }

    // MARK: - B. 家充佔比與地點

    var homeSessions: [Session] { sessions.filter(\.isHome) }
    var awaySessions: [Session] { sessions.filter { !$0.isHome } }

    /// 家充度數佔比（0–1）。用度數而不是次數：一次家充慢慢充的度數通常比外面補一點多，
    /// 用次數會低估家充實際扛下來的比例。
    var homeKwhShare: Double? {
        guard hasHomeKeyword, totalKwh > 0 else { return nil }
        return homeSessions.reduce(0) { $0 + $1.kwh } / totalKwh
    }

    func avgPrice(of list: [Session]) -> Double? {
        let k = list.reduce(0) { $0 + $1.kwh }
        guard k > 0 else { return nil }
        return list.reduce(0) { $0 + $1.cost } / k
    }

    /// 地點排行（依累計度數大到小）
    struct PlaceStat: Identifiable {
        let id: String
        let place: String
        let count: Int
        let kwh: Double
        let cost: Double
        let isHome: Bool
        var pricePerKwh: Double? { kwh > 0 ? cost / kwh : nil }
    }

    var placeRanking: [PlaceStat] {
        var buckets: [String: [Session]] = [:]
        for s in sessions { buckets[s.place, default: []].append(s) }
        return buckets.map { key, list in
            PlaceStat(id: key, place: key, count: list.count,
                      kwh: list.reduce(0) { $0 + $1.kwh },
                      cost: list.reduce(0) { $0 + $1.cost },
                      isHome: list.contains(where: \.isHome))
        }
        .sorted { $0.kwh > $1.kwh }
    }

    // MARK: - C. 充電習慣（電池保養）
    //
    // 這一組只用起訖 % 就算得出來，卻是唯一真的能延長電池壽命的指標。

    private var withSoc: [Session] { sessions.filter { $0.fromPct != nil && $0.toPct != nil } }

    var avgStartPct: Double? {
        let v = withSoc.compactMap(\.fromPct)
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
    var avgEndPct: Double? {
        let v = withSoc.compactMap(\.toPct)
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
    /// 充到 100%（含 99 以上，實務上就是充滿）
    var fullChargeCount: Int { withSoc.filter { ($0.toPct ?? 0) >= 99 }.count }
    /// 深放電：低於 10% 才充
    var deepDischargeCount: Int { withSoc.filter { ($0.fromPct ?? 100) < 10 }.count }
    var socSampleCount: Int { withSoc.count }

    /// 起始電量分布（每 10% 一格，共 10 格）
    var startPctHistogram: [(bucket: Int, count: Int)] {
        var bins = Array(repeating: 0, count: 10)
        for s in withSoc {
            guard let f = s.fromPct else { continue }
            let i = min(9, max(0, Int(f / 10)))
            bins[i] += 1
        }
        return bins.enumerated().map { (bucket: $0.offset, count: $0.element) }
    }

    // MARK: - D. 推估容量 / 健康度 / 充電損耗
    //
    // ⚠️ 這一段最容易做錯，先把前提寫清楚：
    //    充電樁打出去的度數 ≠ 真正進到電池的度數（AC 車充損耗約一成、直流快充較低）。
    //    所以 kWh ÷ Δ% 推出來的「容量」天生比原廠標稱**高**。
    //    直接拿它除原廠標稱當健康度，會算出 105～115%，看起來像電池變大了。
    //
    //    因此這裡拆成兩件事：
    //    ① 健康度 → 用「相對初期」，只跟自己比，把損耗這個固定偏差消掉。
    //    ② 原廠標稱 → 拿去算「充電損耗率」，那才是它能誠實回答的問題。

    /// 推估容量樣本（kWh ÷ Δ% × 100）。Δ% < 15 不取，區間太小誤差被放大。
    struct CapacityPoint: Identifiable {
        let id: UUID
        let date: Date
        let estimate: Double
        let isHome: Bool
    }

    var capacityPoints: [CapacityPoint] {
        sessions.compactMap { s in
            guard let d = s.deltaPct, d >= Self.minDeltaPct, s.kwh > 0 else { return nil }
            return CapacityPoint(id: s.id, date: s.date, estimate: s.kwh / d * 100, isHome: s.isHome)
        }
    }

    /// 健康度分析結果。相對初期，不是相對原廠。
    struct SOHResult {
        /// 初期基準（最早 N 筆的中位數）
        let baseline: Double
        /// 目前水準（最新 N 筆的中位數）
        let current: Double
        /// 相對初期的變化率（-0.032＝衰退 3.2%）
        let change: Double
        /// 這組數字是從哪個充電方式算出來的
        let scope: String
        let sampleCount: Int
    }

    /// 健康度。有設家充關鍵字時**只用樣本較多的那一組**（家充或外面），
    /// 因為兩種充電方式的損耗率不同，混在一起的趨勢是假的。
    var soh: SOHResult? {
        var pool = capacityPoints
        var scope = "全部充電"
        if hasHomeKeyword {
            let home = pool.filter(\.isHome), away = pool.filter { !$0.isHome }
            if home.count >= away.count, home.count >= Self.minSOHBaseline * 2 {
                pool = home; scope = "家充"
            } else if away.count > home.count, away.count >= Self.minSOHBaseline * 2 {
                pool = away; scope = "外部充電"
            }
        }
        // 要有頭尾各一組才有「相對初期」可言
        guard pool.count >= Self.minSOHBaseline * 2 else { return nil }
        let head = Array(pool.prefix(Self.minSOHBaseline)).map(\.estimate)
        let tail = Array(pool.suffix(Self.minSOHBaseline)).map(\.estimate)
        let baseline = Self.median(head), current = Self.median(tail)
        guard baseline > 0 else { return nil }
        return SOHResult(baseline: baseline, current: current,
                         change: current / baseline - 1,
                         scope: scope, sampleCount: pool.count)
    }

    /// 充電損耗率：實際充入 ÷ (Δ% × 原廠標稱) − 1。需要原廠標稱才算得出來。
    /// 家充與快充分開算才有意義（效率差很多）。
    struct LossResult {
        let overall: Double?
        let home: Double?
        let away: Double?
        let sampleCount: Int
    }

    var chargingLoss: LossResult? {
        guard let cap = capacityKWh else { return nil }
        func rate(_ list: [Session]) -> Double? {
            var actual = 0.0, theoretical = 0.0
            for s in list {
                guard let d = s.deltaPct, d >= Self.minDeltaPct, s.kwh > 0 else { continue }
                actual += s.kwh
                theoretical += d / 100 * cap
            }
            guard theoretical > 0 else { return nil }
            return actual / theoretical - 1
        }
        let usable = sessions.filter { ($0.deltaPct ?? 0) >= Self.minDeltaPct && $0.kwh > 0 }
        guard !usable.isEmpty else { return nil }
        return LossResult(overall: rate(usable),
                          home: hasHomeKeyword ? rate(usable.filter(\.isHome)) : nil,
                          away: hasHomeKeyword ? rate(usable.filter { !$0.isHome }) : nil,
                          sampleCount: usable.count)
    }

    // MARK: - E. 電耗與里程

    /// 兩次充電之間的行駛區間。行駛距離＝里程差、耗能≈後一筆充入度數（充電樁法）。
    struct Interval: Identifiable {
        let id: UUID
        let date: Date
        let km: Double
        let kwh: Double
        let cost: Double
        var kmPerKwh: Double { kwh > 0 ? km / kwh : 0 }
        var costPerKm: Double { km > 0 ? cost / km : 0 }
    }

    /// 相鄰兩筆里程錶讀數。里程差 ≤0（誤填／換過錶）或 >2000km（中間漏記太多次）的剔除。
    private var odometerSteps: [(from: Session, to: Session, km: Double)] {
        let withOdo = sessions.filter { $0.odometer != nil }
        guard withOdo.count >= 2 else { return [] }
        var out: [(from: Session, to: Session, km: Double)] = []
        for i in 1..<withOdo.count {
            let prev = withOdo[i - 1], cur = withOdo[i]
            guard let a = prev.odometer, let b = cur.odometer else { continue }
            let km = b - a
            guard km > 0, km <= 2000 else { continue }
            out.append((from: prev, to: cur, km: km))
        }
        return out
    }

    /// [v25.538] 再加一道合理性門檻：里程 ÷ 後一筆度數超過 maxKmPerKwh（汽車 12、電動機車 60）的區間不算。
    /// 中間漏記一兩次充電時，一段 800 公里只算到後一筆的 25 度，會寫出「每度跑 32 公里」，續航推估跟著錯。
    var intervals: [Interval] {
        odometerSteps.compactMap { s -> Interval? in
            let cur = s.to
            guard cur.kwh > 0, s.km / cur.kwh <= maxKmPerKwh else { return nil }
            return Interval(id: cur.id, date: cur.date, km: s.km, kwh: cur.kwh, cost: cur.cost)
        }
    }

    var totalTrackedKm: Double { intervals.reduce(0) { $0 + $1.km } }
    var avgKmPerKwh: Double? {
        let k = intervals.reduce(0) { $0 + $1.kwh }
        guard k > 0, totalTrackedKm > 0 else { return nil }
        return totalTrackedKm / k
    }
    var avgCostPerKm: Double? {
        guard totalTrackedKm > 0 else { return nil }
        return intervals.reduce(0) { $0 + $1.cost } / totalTrackedKm
    }

    /// 每月行駛里程（依區間結束日歸月；跨月的區間整段算在結束那個月，
    /// 要按日拆分才精準，但那需要每天的里程，這裡誠實用近似）
    struct MonthKm: Identifiable {
        let id: String
        let month: Date
        let km: Double
        let cost: Double
    }

    var monthlyKm: [MonthKm] {
        let cal = Calendar.current
        var buckets: [Date: (km: Double, cost: Double)] = [:]
        for iv in intervals {
            let comps = cal.dateComponents([.year, .month], from: iv.date)
            guard let key = cal.date(from: comps) else { continue }
            var cur = buckets[key] ?? (0, 0)
            cur.km += iv.km; cur.cost += iv.cost
            buckets[key] = cur
        }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_Hant_TW"); fmt.dateFormat = "yyyy/M"
        return buckets
            .map { MonthKm(id: fmt.string(from: $0.key), month: $0.key,
                           km: $0.value.km, cost: $0.value.cost) }
            .sorted { $0.month < $1.month }
    }

    /// 年化里程：用有紀錄的區間跨度推一年開多少。跨度不足 30 天就不推——
    /// 拿兩週的資料乘 26 倍是在編故事。
    /// [v25.538] 以前分母從第一段的「結束日」算起，少算了第一段的天數，年里程被高估。
    /// 改成每段都從前一筆里程錶讀數那天算到後一筆；每段都正常時就是「第一筆到最後一筆讀數的日期差」。
    /// 里程用里程錶相鄰讀數（不套每度里程門檻）：漏記充電只會讓電耗算不準，那段路還是真的開了；
    /// 被剔除的段（倒退、跳太多）連天數一起拿掉，分子分母才對得上。
    var annualizedKm: Double? {
        let steps = odometerSteps
        let km: Double = steps.reduce(0) { $0 + $1.km }
        let seconds: Double = steps.reduce(0) { $0 + $1.to.date.timeIntervalSince($1.from.date) }
        let days = seconds / 86400
        guard km > 0, days >= 30 else { return nil }
        return km / days * 365
    }

    // MARK: - F. 續航推估（需要原廠標稱 + 電耗）

    struct RangeEstimate {
        /// 目前可用容量（原廠標稱 × 健康度變化）
        let usableKWh: Double
        /// 滿電可跑幾 km
        let fullRangeKm: Double
        /// 每 1% 電量約幾 km
        let kmPerPercent: Double
        /// 最後一次充到的電量，以及那個電量還能跑多遠（沒紀錄則 nil）
        let lastSoc: Double?
        let lastSocRangeKm: Double?
    }

    var rangeEstimate: RangeEstimate? {
        guard let cap = capacityKWh, let eff = avgKmPerKwh, eff > 0 else { return nil }
        // 健康度只拿「相對初期的變化」來折減；沒有足夠樣本就當 100%
        let health = 1 + (soh?.change ?? 0)
        let usable = cap * max(0.5, min(1.05, health))
        let full = usable * eff
        let last = sessions.last?.toPct
        return RangeEstimate(usableKWh: usable,
                             fullRangeKm: full,
                             kmPerPercent: full / 100,
                             lastSoc: last,
                             lastSocRangeKm: last.map { full * $0 / 100 })
    }

    // MARK: 工具

    static func median(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted()
        let m = s.count / 2
        return s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
    }
}
