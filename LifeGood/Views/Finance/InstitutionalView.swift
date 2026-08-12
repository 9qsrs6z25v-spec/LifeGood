import SwiftUI
import Charts

// MARK: - 三大法人買賣超（每日快照收集 + 連續買超篩選 + 個股柱狀圖）
// 資料來源：
//   上市 TWSE T86（https://www.twse.com.tw/rwd/zh/fund/T86，西元 yyyyMMdd，
//     fields 含「證券代號/證券名稱/三大法人買賣超股數」，依欄名找 index 不寫死）
//   上櫃 TPEx 3itrade_hedge（民國年 yyy/MM/dd，tables[0].fields 末欄
//     「三大法人買賣超股數合計」）
// 收集策略（使用者指定）：每天開 App 自動背景抓最新交易日，逐日累積、最多保留 30 天；
// 只收集到 M 天就只能篩「連續 ≤M 天」。收盤資料約 16:30 後公布，當天太早抓不到
// 不存檔、下次開 App 再試；過去的假日/無資料日存空標記避免重抓。
// 儲存：Application Support/InstitutionalNet/yyyy-MM-dd.json（整市場約數千檔，
// 用檔案不塞 UserDefaults）。

/// 單一交易日的三大法人買賣超快照
struct InstDailyRecord: Codable {
    let date: String                 // "yyyy-MM-dd"
    var net: [String: Double]        // symbol → 買賣超股數（+買超 / −賣超）
    var names: [String: String]      // symbol → 名稱
}

enum InstitutionalHistory {
    static let maxDays = 30

    static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static var dirURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("InstitutionalNet", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func storedDates() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dirURL.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }

    static func load(_ date: String) -> InstDailyRecord? {
        guard let data = try? Data(contentsOf: dirURL.appendingPathComponent(date + ".json")) else {
            return nil
        }
        return try? JSONDecoder().decode(InstDailyRecord.self, from: data)
    }

    static func save(_ rec: InstDailyRecord) {
        if let d = try? JSONEncoder().encode(rec) {
            try? d.write(to: dirURL.appendingPathComponent(rec.date + ".json"))
        }
        prune()
    }

    private static func prune() {
        let dates = storedDates()
        guard dates.count > maxDays else { return }
        for d in dates.prefix(dates.count - maxDays) {
            try? FileManager.default.removeItem(at: dirURL.appendingPathComponent(d + ".json"))
        }
    }

    /// 有資料的交易日（略過假日空標記），時間升冪、最多近 maxDays 天
    static func tradingRecords() -> [InstDailyRecord] {
        storedDates().compactMap { load($0) }.filter { !$0.net.isEmpty }.suffix(maxDays).map { $0 }
    }

    // MARK: 每日自動收集

    private static var lastCollectDay: String?

    /// 每天開 App 自動背景收集（同一天只跑一輪）。回傳新增/更新的交易日數。
    @discardableResult
    static func collectIfNeeded() async -> Int {
        let todayKey = dayFmt.string(from: Date())
        guard lastCollectDay != todayKey else { return 0 }
        lastCollectDay = todayKey
        return await autoCollect()
    }

    /// 回看近 7 個日曆日補缺（順便回補使用者幾天沒開 App 的洞）；
    /// 週末直接略過；請求間隔 1.2 秒不轟炸官方 API。
    static func autoCollect() async -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var added = 0
        for back in stride(from: 6, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -back, to: today) else { continue }
            let weekday = cal.component(.weekday, from: day)
            if weekday == 1 || weekday == 7 { continue }   // 週末
            let key = dayFmt.string(from: day)
            let existing = load(key)
            let needFetch: Bool
            if existing == nil {
                needFetch = true
            } else if back == 0, existing?.net.isEmpty == true {
                needFetch = true   // 今天先前抓太早（資料未公布），重試
            } else {
                needFetch = false
            }
            guard needFetch else { continue }
            let rec = await fetchDay(day)
            if !rec.net.isEmpty {
                save(rec)
                added += 1
            } else if back > 0 {
                save(rec)   // 過去的假日/無資料日：存空標記避免每次開 App 重抓
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
        return added
    }

    /// 抓某一天：上市（T86）＋上櫃（TPEx）合併為一份快照
    static func fetchDay(_ day: Date) async -> InstDailyRecord {
        let key = dayFmt.string(from: day)
        var net: [String: Double] = [:]
        var names: [String: String] = [:]

        func parseNumber(_ s: String) -> Double? {
            Double(s.replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespaces))
        }

        // 上市：TWSE T86（西元 yyyyMMdd；依欄名找 index，欄位順序改版也不怕）
        let ymd = key.replacingOccurrences(of: "-", with: "")
        if let url = URL(string: "https://www.twse.com.tw/rwd/zh/fund/T86?date=\(ymd)&selectType=ALLBUT0999&response=json") {
            do {
                var req = URLRequest(url: url)
                req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                let (data, _) = try await URLSession.shared.data(for: req)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   (json["stat"] as? String) == "OK",
                   let fields = json["fields"] as? [String],
                   let rows = json["data"] as? [[Any]],
                   let codeIdx = fields.firstIndex(of: "證券代號"),
                   let nameIdx = fields.firstIndex(of: "證券名稱"),
                   let netIdx = fields.firstIndex(of: "三大法人買賣超股數") {
                    for row in rows {
                        guard row.count > max(codeIdx, max(nameIdx, netIdx)),
                              let code = (row[codeIdx] as? String)?
                                  .trimmingCharacters(in: .whitespaces), !code.isEmpty,
                              let netStr = row[netIdx] as? String,
                              let v = parseNumber(netStr) else { continue }
                        net[code] = v
                        names[code] = (row[nameIdx] as? String)?
                            .trimmingCharacters(in: .whitespaces) ?? code
                    }
                }
            } catch {}
        }

        // 上櫃：TPEx（民國年 yyy/MM/dd；末欄「三大法人買賣超股數合計」依欄名找）
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: day)
        if let y = comps.year, let m = comps.month, let d = comps.day {
            let rocDate = "\(y - 1911)/\(String(format: "%02d", m))/\(String(format: "%02d", d))"
            let urlString = "https://www.tpex.org.tw/web/stock/3insti/daily_trade/3itrade_hedge_result.php?l=zh-tw&se=EW&t=D&d=\(rocDate)&o=json"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: urlString) {
                do {
                    var req = URLRequest(url: url)
                    req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                    let (data, _) = try await URLSession.shared.data(for: req)
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let tables = json["tables"] as? [[String: Any]],
                       let table = tables.first,
                       let fields = table["fields"] as? [String],
                       let rows = table["data"] as? [[Any]],
                       let codeIdx = fields.firstIndex(of: "代號"),
                       let nameIdx = fields.firstIndex(of: "名稱"),
                       let netIdx = fields.lastIndex(where: { $0.contains("三大法人買賣超") }) {
                        for row in rows {
                            guard row.count > max(codeIdx, max(nameIdx, netIdx)),
                                  let code = (row[codeIdx] as? String)?
                                      .trimmingCharacters(in: .whitespaces), !code.isEmpty,
                                  let netStr = row[netIdx] as? String,
                                  let v = parseNumber(netStr) else { continue }
                            net[code] = v
                            names[code] = (row[nameIdx] as? String)?
                                .trimmingCharacters(in: .whitespaces) ?? code
                        }
                    }
                } catch {}
            }
        }
        return InstDailyRecord(date: key, net: net, names: names)
    }
}

// MARK: - 法人連續買超篩選頁

struct InstitutionalBuyView: View {
    @Environment(\.dismiss) private var dismiss
    /// 連續買超天數門檻（1~30；實際上限受已收集天數限制）
    @AppStorage("inst_streak_days") private var streakDays: Int = 3
    @State private var records: [InstDailyRecord] = []   // 交易日、時間升冪
    @State private var rows: [StreakRow] = []
    @State private var loading = true
    @State private var collecting = false

    private let accent = Color(red: 1.00, green: 0.62, blue: 0.22)

    struct StreakRow: Identifiable {
        let symbol: String
        let name: String
        let streak: Int
        let totalShares: Double     // 連買期間累計買超股數
        var id: String { symbol }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("讀取法人資料中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if records.isEmpty {
                    emptyState
                } else {
                    resultList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("法人連續買超")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await manualRefresh() }
                    } label: {
                        if collecting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(collecting)
                }
            }
            .task { await reload() }
            .onChange(of: streakDays) { _, _ in recompute() }
        }
    }

    private var maxSelectableDays: Int { max(1, min(30, records.count)) }

    private var resultList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("連續買超天數")
                            .font(.subheadline)
                        Spacer()
                        Text("\(streakDays) 天")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(accent)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(min(streakDays, maxSelectableDays)) },
                            set: { streakDays = Int($0.rounded()) }
                        ),
                        in: 1...Double(maxSelectableDays), step: 1
                    )
                    .tint(accent)
                }
                .padding(.vertical, 2)
            } footer: {
                Text("已收集 \(records.count) 個交易日（\(records.first?.date ?? "—") ～ \(records.last?.date ?? "—")）；每天開 App 自動累積，最多 30 天。資料含上市＋上櫃，收盤後約 16:30 公布。")
            }

            Section {
                if rows.isEmpty {
                    Text("沒有符合「連續 \(streakDays) 天買超」的股票")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        streakRowView(rank: idx + 1, row: row)
                    }
                }
            } header: {
                Text("符合 \(rows.count) 檔（依連買天數、累計買超排序）")
            }
        }
    }

    private func streakRowView(rank: Int, row: StreakRow) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(rank <= 3 ? accent : .secondary)
                .frame(width: 26, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.symbol)
                    .font(.subheadline.weight(.semibold))
                Text(row.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("連買 \(row.streak) 天")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.red.opacity(0.10))
                .foregroundStyle(.red)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.red.opacity(0.22), lineWidth: 0.6))
            Text(sheetCountText(row.totalShares))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .frame(width: 84, alignment: .trailing)
        }
    }

    /// 股數 → 張（千股）緊湊顯示
    private func sheetCountText(_ shares: Double) -> String {
        let sheets = shares / 1000
        if sheets >= 10_000 { return String(format: "%.1f萬張", sheets / 10_000) }
        if sheets >= 1_000 { return String(format: "%.0f張", sheets) }
        return String(format: "%.1f張", sheets)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "building.columns")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("尚未收集到法人資料")
                .font(.subheadline.weight(.semibold))
            Text("每天開 App 會自動在背景抓一次三大法人買賣超（收盤後約 16:30 公布）。可點右上角手動更新。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func manualRefresh() async {
        collecting = true
        _ = await InstitutionalHistory.autoCollect()
        collecting = false
        await reload()
    }

    private func reload() async {
        loading = true
        let recs = await Task.detached(priority: .userInitiated) {
            InstitutionalHistory.tradingRecords()
        }.value
        records = recs
        recompute()
        loading = false
    }

    /// 從最新交易日往回算每檔的連續買超天數與累計買超
    private func recompute() {
        guard let latest = records.last else { rows = []; return }
        let threshold = min(streakDays, maxSelectableDays)
        let reversed = Array(records.reversed())
        var result: [StreakRow] = []
        for (sym, v) in latest.net where v > 0 {
            var streak = 0
            var total = 0.0
            for rec in reversed {
                guard let n = rec.net[sym], n > 0 else { break }
                streak += 1
                total += n
            }
            if streak >= threshold {
                let name = latest.names[sym] ?? sym
                result.append(StreakRow(symbol: sym, name: name, streak: streak, totalShares: total))
            }
        }
        rows = Array(
            result.sorted {
                $0.streak != $1.streak ? $0.streak > $1.streak : $0.totalShares > $1.totalShares
            }
            .prefix(200)
        )
    }
}

// MARK: - 個股法人買賣超柱狀圖卡（股票明細技術線圖下方）

/// 近 N 個交易日的三大法人買賣超柱狀圖（台股慣例：買超紅、賣超綠）。
/// 資料來自每日收集的快照；尚未收集到該股資料時整卡隱藏。
struct InstNetBarCard: View {
    let symbol: String

    private struct DayNet: Identifiable {
        let date: Date
        let net: Double
        var id: Date { date }
    }
    @State private var points: [DayNet] = []

    private let upColor = Color(red: 0.92, green: 0.26, blue: 0.21)
    private let downColor = Color(red: 0.13, green: 0.65, blue: 0.37)

    var body: some View {
        Group {
            if points.count >= 1 {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(colors: [.orange, .orange.opacity(0.55)],
                                               startPoint: .top, endPoint: .bottom)
                            )
                            .frame(width: 4, height: 14)
                        Text("法人買賣超")
                            .font(.subheadline.weight(.bold))
                        Text("近 \(points.count) 個交易日（張）")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let last = points.last {
                            Text(last.net >= 0 ? "今日買超" : "今日賣超")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background((last.net >= 0 ? upColor : downColor).opacity(0.10))
                                .foregroundStyle(last.net >= 0 ? upColor : downColor)
                                .clipShape(Capsule())
                        }
                    }
                    Chart(points) { p in
                        BarMark(
                            x: .value("日", p.date),
                            y: .value("張", p.net / 1000),
                            width: .fixed(6)
                        )
                        .foregroundStyle(p.net >= 0 ? upColor : downColor)
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) }
                    .frame(height: 120)
                }
                .padding(14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
            }
        }
        .task { await load() }
    }

    private func load() async {
        let sym = symbol
        let result = await Task.detached(priority: .userInitiated) { () -> [(String, Double)] in
            InstitutionalHistory.tradingRecords().compactMap { rec in
                guard let v = rec.net[sym] else { return nil }
                return (rec.date, v)
            }
        }.value
        points = result.compactMap { pair in
            guard let d = InstitutionalHistory.dayFmt.date(from: pair.0) else { return nil }
            return DayNet(date: d, net: pair.1)
        }
    }
}
