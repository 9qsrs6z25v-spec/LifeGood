import SwiftUI
import Charts
import MapKit

// MARK: - 充電與里程分析
//
// [v25.397] 載具詳情「充電統計」的深入版。計算全部在 VehicleChargeAnalytics，
// 這裡只負責把它畫出來，並且在樣本不足時明講還差幾筆——
// 少少幾筆算出來的趨勢多半是雜訊，畫一條會騙人的線比不畫還糟。

struct VehicleChargeAnalyticsView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    let vehicleId: UUID

    @State private var headerAppeared = false

    init(vehicleId: UUID) {
        self.vehicleId = vehicleId
    }

    private var vehicle: Vehicle? {
        financeStore.vehicles.first { $0.id == vehicleId }
    }

    /// 這台車有填度數的充電紀錄
    private var chargeExpenses: [Expense] {
        expenseStore.expenses.filter {
            $0.linkedVehicleId == vehicleId
                && $0.vehicleExpenseCategory == .electricity
                && ($0.evKwh ?? 0) > 0
        }
    }

    /// 這台車的停車紀錄（有地點的才進得了熱點排行）
    private var parkingExpenses: [Expense] {
        expenseStore.expenses.filter {
            $0.linkedVehicleId == vehicleId && $0.vehicleExpenseCategory == .parking
        }
    }

    private var analytics: VehicleChargeAnalytics {
        VehicleChargeAnalytics(expenses: chargeExpenses,
                               capacityKWh: vehicle?.batteryCapacityKWh,
                               homeKeyword: vehicle?.homeChargePlace)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // 每一段都自己判斷資料夠不夠，不夠就自己不出現或改顯示提示
                LazyVStack(spacing: 14) {
                    let a = analytics
                    overviewCard(a)
                    rangeCard(a)
                    healthCard(a)
                    lossCard(a)
                    homeShareCard(a)
                    placeCard(a)
                    habitCard(a)
                    efficiencyCard(a)
                    monthlyCard(a)
                    parkingCard
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("充電與里程分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
            }
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { headerAppeared = true }
            }
        }
    }

    // MARK: - 1. 總覽

    private func overviewCard(_ a: VehicleChargeAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0.12)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 54, height: 54)
                    Image(systemName: "bolt.car.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(vehicle?.name ?? "載具")
                        .font(.title3.weight(.bold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(overviewSubtitle(a))
                        .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.9))
                }
                Spacer(minLength: 0)
            }
            Rectangle().fill(Color.white.opacity(0.20)).frame(height: 0.5)
            HStack(spacing: 0) {
                heroKpi("累計充電", num(a.totalKwh, 0), "kWh")
                heroKpi("平均電價", a.avgPricePerKwh.map { num($0, 2) } ?? "—", "元/度")
                heroKpi("總電費", num(a.totalCost, 0), "元")
                heroKpi("平均間隔", a.avgIntervalDays.map { num($0, 1) } ?? "—", "天")
            }
        }
        .padding(16)
        .background(
            ZStack {
                LinearGradient(colors: [Color(red: 0.10, green: 0.62, blue: 0.48),
                                        Color(red: 0.16, green: 0.45, blue: 0.94)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color.white.opacity(0.10)).blur(radius: 18)
                    .frame(width: 140, height: 140).offset(x: 110, y: -50)
                Circle().fill(Color.white.opacity(0.08)).blur(radius: 12)
                    .frame(width: 90, height: 90).offset(x: -120, y: 46)
                LinearGradient(colors: [Color.white.opacity(0.18), .clear],
                               startPoint: .top, endPoint: .center)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .opacity(headerAppeared ? 1 : 0)
        .offset(y: headerAppeared ? 0 : 16)
    }

    private func overviewSubtitle(_ a: VehicleChargeAnalytics) -> String {
        var parts = ["\(a.count) 次充電"]
        if let cap = a.capacityKWh { parts.append("原廠 " + num(cap, 0) + " kWh") }
        if !a.intervals.isEmpty { parts.append("統計 " + num(a.totalTrackedKm, 0) + " km") }
        return parts.joined(separator: "・")
    }

    private func heroKpi(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(unit).font(.system(size: 9)).foregroundStyle(.white.opacity(0.75))
            Text(title).font(.system(size: 10)).foregroundStyle(.white.opacity(0.9))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 2. 續航推估

    @ViewBuilder
    private func rangeCard(_ a: VehicleChargeAnalytics) -> some View {
        card("續航推估", icon: "gauge.with.dots.needle.67percent", color: .green) {
            if let r = a.rangeEstimate {
                VStack(alignment: .leading, spacing: 0) {
                    kpiRow([("可用容量", num(r.usableKWh, 1), "kWh"),
                            ("滿電續航", num(r.fullRangeKm, 0), "km"),
                            ("每 1% 電量", num(r.kmPerPercent, 1), "km")])
                    if let soc = r.lastSoc, let km = r.lastSocRangeKm {
                        infoLine("最後一次充到 " + num(soc, 0) + "%，約還能跑 "
                                 + num(km, 0) + " km")
                    }
                    infoLine("可用容量＝原廠標稱 × 健康度；續航＝可用容量 × 平均電耗。實際會受天氣、路況與駕駛習慣影響。")
                }
            } else {
                needMore(rangeMissing(a))
            }
        }
    }

    private func rangeMissing(_ a: VehicleChargeAnalytics) -> String {
        if a.capacityKWh == nil { return "要先在載具編輯填「原廠電池容量」才算得出續航。" }
        return "要有連續兩筆都填里程錶的充電紀錄，才算得出平均電耗。"
    }

    // MARK: - 3. 電池健康度

    @ViewBuilder
    private func healthCard(_ a: VehicleChargeAnalytics) -> some View {
        card("電池健康度", icon: "battery.100percent.bolt", color: .teal) {
            if let s = a.soh {
                VStack(alignment: .leading, spacing: 0) {
                    kpiRow([("相對初期", (s.change >= 0 ? "+" : "") + num(s.change * 100, 1), "%"),
                            ("初期推估", num(s.baseline, 1), "kWh"),
                            ("目前推估", num(s.current, 1), "kWh")])
                    infoLine("取樣：\(s.scope)，共 \(s.sampleCount) 筆（頭尾各取 5 筆的中位數比較）")
                    infoLine("⚠️ 這是「跟自己比」，不是跟原廠比。充電樁打出去的度數含充電損耗，所以推估容量天生比原廠標稱高——直接除原廠會算出 105～115%，看起來像電池變大了。要看損耗請往下。")
                    if a.capacityPoints.count >= VehicleChargeAnalytics.minTrend {
                        Text("推估容量走勢（kWh）")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, 16).padding(.top, 6)
                        Chart(a.capacityPoints) { p in
                            LineMark(x: .value("日期", p.date), y: .value("kWh", p.estimate))
                                .foregroundStyle(.teal)
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("日期", p.date), y: .value("kWh", p.estimate))
                                .foregroundStyle(p.isHome ? Color.green : Color.orange)
                                .symbolSize(26)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 130)
                        .padding(.horizontal, 16).padding(.bottom, 12)
                    }
                }
            } else {
                needMore("需要至少 \(VehicleChargeAnalytics.minSOHBaseline * 2) 筆「單次充超過 \(Int(VehicleChargeAnalytics.minDeltaPct))%」的紀錄才看得出趨勢，目前 \(a.capacityPoints.count) 筆。充電區間太小的紀錄不列入——誤差會被放大好幾倍。")
            }
        }
    }

    // MARK: - 4. 充電損耗

    @ViewBuilder
    private func lossCard(_ a: VehicleChargeAnalytics) -> some View {
        card("充電損耗", icon: "bolt.trianglebadge.exclamationmark", color: .orange) {
            if let l = a.chargingLoss {
                VStack(alignment: .leading, spacing: 0) {
                    kpiRow([("整體", l.overall.map { pct($0) } ?? "—", ""),
                            ("家充", l.home.map { pct($0) } ?? "—", ""),
                            ("外部", l.away.map { pct($0) } ?? "—", "")])
                    infoLine("充電樁打出去的度數 ÷（充電 % × 原廠容量）− 1。AC 家充一般在 10～15%、直流快充較低。")
                    infoLine("這個數字突然變高，通常是充電器或電池出了狀況的早期訊號——它是原廠容量真正能誠實回答的問題。")
                    infoLine("取樣 \(l.sampleCount) 筆（只算單次充超過 \(Int(VehicleChargeAnalytics.minDeltaPct))% 的紀錄）")
                }
            } else {
                needMore(a.capacityKWh == nil
                         ? "要先在載具編輯填「原廠電池容量」。"
                         : "還沒有「單次充超過 \(Int(VehicleChargeAnalytics.minDeltaPct))% 且有填起訖電量」的紀錄。")
            }
        }
    }

    // MARK: - 5. 家充佔比

    @ViewBuilder
    private func homeShareCard(_ a: VehicleChargeAnalytics) -> some View {
        card("家充佔比", icon: "house.fill", color: .blue) {
            if let share = a.homeKwhShare {
                VStack(alignment: .leading, spacing: 0) {
                    kpiRow([("家充度數佔比", num(share * 100, 0), "%"),
                            ("家充電價", a.avgPrice(of: a.homeSessions).map { num($0, 2) } ?? "—", "元/度"),
                            ("外部電價", a.avgPrice(of: a.awaySessions).map { num($0, 2) } ?? "—", "元/度")])
                    // 佔比條
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.orange.opacity(0.25))
                            Capsule().fill(Color.blue)
                                .frame(width: max(0, min(1, share)) * geo.size.width)
                        }
                    }
                    .frame(height: 10)
                    .padding(.horizontal, 16).padding(.top, 4)
                    HStack {
                        Text("家充").font(.system(size: 10, weight: .semibold)).foregroundStyle(.blue)
                        Spacer()
                        Text("外部").font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 16).padding(.top, 2)
                    if let saved = homeSaving(a) {
                        infoLine(saved)
                    }
                    infoLine("用度數而不是次數算：家充常常一次充比較多，用次數會低估家充實際扛下來的比例。")
                }
            } else {
                needMore("要先在載具編輯填「家充地點關鍵字」（例如「家」「自宅」），充電紀錄的地點含這段文字就算家充。")
            }
        }
    }

    /// 家充省下多少：用外部電價當對照，算家充那些度數少付了多少
    private func homeSaving(_ a: VehicleChargeAnalytics) -> String? {
        guard let homePrice = a.avgPrice(of: a.homeSessions),
              let awayPrice = a.avgPrice(of: a.awaySessions),
              awayPrice > homePrice else { return nil }
        let homeKwh = a.homeSessions.reduce(0) { $0 + $1.kwh }
        let saved = (awayPrice - homePrice) * homeKwh
        return "這些家充度數若都在外面充，大約要多付 " + num(saved, 0) + " 元。"
    }

    // MARK: - 6. 充電地點排行

    @ViewBuilder
    private func placeCard(_ a: VehicleChargeAnalytics) -> some View {
        let ranking = a.placeRanking
        card("充電地點", icon: "mappin.and.ellipse", color: .indigo, count: ranking.count) {
            if ranking.isEmpty {
                needMore("充電紀錄還沒填地點。新增電費支出時那一列「地點」填了就會出現在這裡。")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ranking.prefix(12).enumerated()), id: \.element.id) { idx, p in
                        placeRow(p, rank: idx + 1, maxKwh: ranking.first?.kwh ?? 1)
                        if idx < min(12, ranking.count) - 1 { Divider().padding(.leading, 16) }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func placeRow(_ p: VehicleChargeAnalytics.PlaceStat, rank: Int, maxKwh: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("\(rank)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                if p.isHome {
                    Image(systemName: "house.fill").font(.system(size: 9)).foregroundStyle(.blue)
                }
                Text(p.place)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(p.pricePerKwh.map { num($0, 2) + " 元/度" } ?? "—")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.indigo)
            }
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.tertiarySystemFill))
                        Capsule().fill(Color.indigo.opacity(0.65))
                            .frame(width: max(0, min(1, p.kwh / max(maxKwh, 0.001))) * geo.size.width)
                    }
                }
                .frame(height: 6)
                Text("\(p.count) 次・" + num(p.kwh, 0) + " kWh・" + num(p.cost, 0) + " 元")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 24)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    // MARK: - 7. 充電習慣

    @ViewBuilder
    private func habitCard(_ a: VehicleChargeAnalytics) -> some View {
        card("充電習慣", icon: "heart.text.square.fill", color: .pink) {
            if a.socSampleCount == 0 {
                needMore("充電紀錄還沒填起訖電量（從幾 % 充到幾 %）。")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    kpiRow([("平均起充", a.avgStartPct.map { num($0, 0) } ?? "—", "%"),
                            ("平均充到", a.avgEndPct.map { num($0, 0) } ?? "—", "%"),
                            ("充到滿", "\(a.fullChargeCount)", "次"),
                            ("深放電", "\(a.deepDischargeCount)", "次")])
                    if a.fullChargeCount > 0 || a.deepDischargeCount > 0 {
                        warnLine(habitWarning(a))
                    }
                    Text("起始電量分布")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.top, 6)
                    Chart(a.startPctHistogram, id: \.bucket) { item in
                        BarMark(x: .value("電量", "\(item.bucket * 10)"),
                                y: .value("次數", item.count))
                            .foregroundStyle(item.bucket == 0 ? Color.red.gradient : Color.pink.gradient)
                            .cornerRadius(2)
                    }
                    .frame(height: 110)
                    .padding(.horizontal, 16).padding(.bottom, 4)
                    infoLine("橫軸是「開始充電時剩幾 %」（0＝0–9%）。長期從很低才充、或常常充到 100%，都會加速電池衰退；日常維持在 20–80% 之間對電池最好。")
                    infoLine("這一段只用起訖 % 就算得出來，卻是這裡唯一真的能延長電池壽命的指標。")
                }
            }
        }
    }

    private func habitWarning(_ a: VehicleChargeAnalytics) -> String {
        var parts: [String] = []
        if a.fullChargeCount > 0 { parts.append("充到 100% 共 \(a.fullChargeCount) 次") }
        if a.deepDischargeCount > 0 { parts.append("低於 10% 才充共 \(a.deepDischargeCount) 次") }
        return parts.joined(separator: "、") + "。偶爾一次無妨（長途前充滿是合理的），常態如此才要留意。"
    }

    // MARK: - 8. 電耗

    @ViewBuilder
    private func efficiencyCard(_ a: VehicleChargeAnalytics) -> some View {
        let ivs = a.intervals
        card("電耗與成本", icon: "speedometer", color: .cyan, count: ivs.count) {
            if ivs.isEmpty {
                needMore("需要連續兩筆都填「里程錶讀數」的充電紀錄。填了之後就能算出兩次充電之間跑了多遠、用了多少電。")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    kpiRow([("平均電耗", a.avgKmPerKwh.map { num($0, 1) } ?? "—", "km/kWh"),
                            ("每公里電費", a.avgCostPerKm.map { num($0, 2) } ?? "—", "元/km"),
                            ("統計里程", num(a.totalTrackedKm, 0), "km"),
                            ("年化里程", a.annualizedKm.map { num($0, 0) } ?? "—", "km/年")])
                    if ivs.count >= VehicleChargeAnalytics.minTrend {
                        Text("電耗走勢（km/kWh，越高越省）")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, 16).padding(.top, 6)
                        Chart(ivs) { p in
                            LineMark(x: .value("日期", p.date), y: .value("km/kWh", p.kmPerKwh))
                                .foregroundStyle(.cyan)
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("日期", p.date), y: .value("km/kWh", p.kmPerKwh))
                                .foregroundStyle(.cyan).symbolSize(24)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 120)
                        .padding(.horizontal, 16).padding(.bottom, 8)
                    } else {
                        infoLine("再累積 \(VehicleChargeAnalytics.minTrend - ivs.count) 個里程區間就會畫出電耗走勢。")
                    }
                    if a.annualizedKm == nil && !ivs.isEmpty {
                        infoLine("年化里程要有跨度 30 天以上的紀錄才推算——拿兩週的資料乘 26 倍是在編故事。")
                    }
                }
            }
        }
    }

    // MARK: - 9. 每月里程

    @ViewBuilder
    private func monthlyCard(_ a: VehicleChargeAnalytics) -> some View {
        let months = a.monthlyKm
        if months.count >= 2 {
            card("每月里程與成本", icon: "calendar", color: .purple, count: months.count) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("每月行駛里程（km）")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.top, 4)
                    Chart(months) { m in
                        BarMark(x: .value("月", m.id), y: .value("km", m.km))
                            .foregroundStyle(Color.purple.gradient)
                            .cornerRadius(3)
                    }
                    .frame(height: 120)
                    .padding(.horizontal, 16)

                    Text("每公里成本走勢（元/km）")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.top, 10)
                    Chart(months) { m in
                        LineMark(x: .value("月", m.id),
                                 y: .value("元/km", m.km > 0 ? m.cost / m.km : 0))
                            .foregroundStyle(.orange)
                        PointMark(x: .value("月", m.id),
                                  y: .value("元/km", m.km > 0 ? m.cost / m.km : 0))
                            .foregroundStyle(.orange).symbolSize(24)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 100)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                    infoLine("跨月的里程區間整段算在結束那個月。要按日拆分才精準，但那需要每天的里程錶讀數。")
                }
            }
        }
    }

    // MARK: - 10. 停車熱點

    private var parkingStats: [(place: String, count: Int, cost: Double, coord: CLLocationCoordinate2D?)] {
        var buckets: [String: (count: Int, cost: Double, coord: CLLocationCoordinate2D?)] = [:]
        for e in parkingExpenses {
            let raw = (e.placeName ?? e.placeAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            var cur = buckets[raw] ?? (0, 0, nil)
            cur.count += 1
            cur.cost += e.amount
            if cur.coord == nil, let lat = e.placeLatitude, let lon = e.placeLongitude {
                cur.coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            buckets[raw] = cur
        }
        return buckets.map { (place: $0.key, count: $0.value.count,
                              cost: $0.value.cost, coord: $0.value.coord) }
            .sorted { $0.count > $1.count }
    }

    @ViewBuilder
    private var parkingCard: some View {
        let stats = parkingStats
        card("停車熱點", icon: "parkingsign.circle.fill", color: .brown, count: stats.count) {
            if stats.isEmpty {
                needMore("停車支出還沒填地點。新增停車支出時那一列「地點」填了就會出現在這裡。")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    let pins = stats.compactMap { s -> ParkingPin? in
                        s.coord.map { ParkingPin(id: s.place, name: s.place, count: s.count, coord: $0) }
                    }
                    if !pins.isEmpty {
                        Map(initialPosition: .region(region(for: pins))) {
                            ForEach(pins) { pin in
                                Annotation(pin.name, coordinate: pin.coord) {
                                    ZStack {
                                        Circle().fill(Color.brown)
                                            .frame(width: pinSize(pin, in: pins),
                                                   height: pinSize(pin, in: pins))
                                            .shadow(radius: 2)
                                        Text("\(pin.count)")
                                            .font(.caption2.weight(.bold)).foregroundStyle(.white)
                                    }
                                }
                            }
                        }
                        .mapStyle(.standard(pointsOfInterest: .excludingAll))
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16).padding(.bottom, 8)
                    }
                    ForEach(Array(stats.prefix(12).enumerated()), id: \.element.place) { idx, s in
                        HStack(spacing: 8) {
                            Text("\(idx + 1)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .frame(width: 16).foregroundStyle(.secondary)
                            Text(s.place).font(.subheadline).lineLimit(1)
                            Spacer(minLength: 0)
                            Text("\(s.count) 次・" + num(s.cost, 0) + " 元")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.brown)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        if idx < min(12, stats.count) - 1 { Divider().padding(.leading, 16) }
                    }
                    if pins.isEmpty {
                        infoLine("這些地點沒有經緯度所以畫不出地圖——用地點搜尋選出來的才會帶座標。")
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private struct ParkingPin: Identifiable {
        let id: String
        let name: String
        let count: Int
        let coord: CLLocationCoordinate2D
    }

    /// 把所有點框進畫面。只有一個點時給一個固定的小範圍，不然 span 會是 0。
    private func region(for pins: [ParkingPin]) -> MKCoordinateRegion {
        let lats = pins.map(\.coord.latitude), lons = pins.map(\.coord.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 25.03, longitude: 121.56),
                                      span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.01, (maxLat - minLat) * 1.4),
                                    longitudeDelta: max(0.01, (maxLon - minLon) * 1.4))
        return MKCoordinateRegion(center: center, span: span)
    }

    private func pinSize(_ pin: ParkingPin, in pins: [ParkingPin]) -> CGFloat {
        let maxCount = pins.map(\.count).max() ?? 1
        let ratio = Double(pin.count) / Double(max(maxCount, 1))
        return 22 + CGFloat(ratio) * 14
    }

    // MARK: - 共用零件

    @ViewBuilder
    private func card<Content: View>(_ title: String, icon: String, color: Color,
                                     count: Int? = nil,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(LinearGradient(colors: [color, color.opacity(0.5)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 16)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
                Text(title).font(.subheadline.weight(.semibold))
                if let c = count, c > 0 {
                    Text("\(c)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(color.opacity(0.13)).foregroundStyle(color)
                        .clipShape(Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            content()
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    private func kpiRow(_ items: [(String, String, String)]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                if idx > 0 { Divider().frame(height: 32) }
                VStack(spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(item.1)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.5)
                        if !item.2.isEmpty {
                            Text(item.2).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                    Text(item.0).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private func infoLine(_ text: String) -> some View {
        Text(text)
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private func warnLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10)).foregroundStyle(.orange)
            Text(text)
                .font(.caption2).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private func needMore(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            Text(text)
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.bottom, 14)
    }

    /// 數字格式化（小數位可指定）
    private func num(_ v: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", v)
    }

    private func pct(_ v: Double) -> String {
        (v >= 0 ? "+" : "") + String(format: "%.1f", v * 100) + "%"
    }
}
