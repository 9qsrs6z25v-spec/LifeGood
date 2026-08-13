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

// MARK: - AI 持股健診（呼叫語音 AI 助手設定的供應商 API）

/// 把使用者目前持股＋技術面（日線/均線）＋籌碼面（法人買賣超）＋大盤現況
/// 整理成結構化資料，交給語音 AI 助手設定的 AI 供應商做分析。
/// v25.204：要求 AI 回傳 JSON，App 端解析後用原生元件排版（大盤卡＋逐檔建議卡
/// ＋配置卡＋風險卡）；JSON 解析失敗時退回純文字卡保底。
/// 按「開始分析」才呼叫（花 API 費用），結果附「非投資建議」聲明。
struct StockAIAnalysisView: View {
    @EnvironmentObject var store: FinanceStore
    @StateObject private var aiSettings = AISettingsStore.shared
    @Environment(\.dismiss) private var dismiss

    // MARK: 結構化結果

    fileprivate struct StockAdvice: Identifiable {
        let id = UUID()
        var symbol: String
        var name: String
        var action: String      // 買進加碼 / 續抱觀察 / 減碼賣出
        var reason: String
        var technical: String?
        var chips: String?
    }

    fileprivate struct AIResult {
        var marketSummary: String?
        var marketSentiment: String?    // 偏多 / 中性 / 偏空
        var stocks: [StockAdvice] = []
        var portfolio: String?
        var risks: [String] = []
        var rawFallback: String?        // JSON 解析失敗時的純文字保底
    }

    private enum Phase {
        case idle
        case loading
        case done(AIResult)
        case failed(String)
    }
    @State private var phase: Phase = .idle

    private let accent = Color(red: 1.00, green: 0.62, blue: 0.22)
    // 台股慣例：偏多/買進紅、偏空/賣出綠
    private let upColor = Color(red: 0.92, green: 0.26, blue: 0.21)
    private let downColor = Color(red: 0.13, green: 0.65, blue: 0.37)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    content
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("AI 持股健診")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let holdings = store.stocks.filter { !$0.isSold }
        if !aiSettings.isReady {
            infoCard(icon: "key.slash.fill", color: .secondary,
                     title: "尚未設定 AI 供應商",
                     text: "此功能使用「語音 AI 助手」的 API 設定。請先到 設定 > 語音 AI 助手 選擇供應商並填入 API Key。")
        } else if holdings.isEmpty {
            infoCard(icon: "chart.line.uptrend.xyaxis", color: accent,
                     title: "沒有持有中的股票",
                     text: "先新增股票持股，再回來做 AI 健診。")
        } else {
            switch phase {
            case .idle:
                idleCard(holdings: holdings)
            case .loading:
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("AI 分析中…依供應商約需 10~30 秒")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            case .done(let result):
                resultHeader
                if let raw = result.rawFallback {
                    // JSON 解析失敗保底：仍以純文字卡呈現
                    sectionCard(title: "分析結果", icon: "sparkles", color: accent) {
                        Text(raw)
                            .font(.subheadline)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    if let summary = result.marketSummary {
                        marketCard(summary: summary, sentiment: result.marketSentiment)
                    }
                    ForEach(result.stocks) { advice in
                        stockAdviceCard(advice)
                    }
                    if let portfolio = result.portfolio, !portfolio.isEmpty {
                        sectionCard(title: "整體配置觀點", icon: "chart.pie.fill", color: .indigo) {
                            Text(portfolio)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if !result.risks.isEmpty {
                        sectionCard(title: "風險提醒", icon: "exclamationmark.triangle.fill", color: .orange) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(result.risks.enumerated()), id: \.offset) { _, risk in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("•").foregroundStyle(.orange)
                                        Text(risk)
                                    }
                                    .font(.subheadline)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Text("以上為 AI 生成之參考觀點，非投資建議。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            case .failed(let err):
                infoCard(icon: "exclamationmark.triangle.fill", color: .orange,
                         title: "分析失敗", text: err)
                Button {
                    Task { await analyze() }
                } label: {
                    Label("重試", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
        }
    }

    // MARK: 結果元件

    private var resultHeader: some View {
        HStack {
            Label("分析結果", systemImage: "sparkles")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accent)
            Spacer()
            Button {
                Task { await analyze() }
            } label: {
                Label("重新分析", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 2)
    }

    /// 大盤卡：情緒膠囊（偏多紅／中性灰／偏空綠）＋簡評
    private func marketCard(summary: String, sentiment: String?) -> some View {
        sectionCard(title: "大盤現況", icon: "globe.asia.australia.fill", color: .blue) {
            VStack(alignment: .leading, spacing: 8) {
                if let sentiment, !sentiment.isEmpty {
                    let color = sentimentColor(sentiment)
                    HStack(spacing: 4) {
                        Image(systemName: sentimentIcon(sentiment))
                            .font(.system(size: 10, weight: .bold))
                        Text(sentiment)
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(color.opacity(0.12))
                    .foregroundStyle(color)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.6))
                }
                Text(summary)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 逐檔建議卡：名稱＋代號膠囊＋建議膠囊（買進紅/續抱藍/減碼綠）＋觀點列
    private func stockAdviceCard(_ advice: StockAdvice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(advice.name.isEmpty ? advice.symbol : advice.name)
                    .font(.subheadline.weight(.bold))
                if !advice.symbol.isEmpty {
                    Text(advice.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(accent.opacity(0.12))
                        .foregroundStyle(accent)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                }
                Spacer()
                let color = actionColor(advice.action)
                Text(advice.action)
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(color.opacity(0.12))
                    .foregroundStyle(color)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.6))
            }
            if !advice.reason.isEmpty {
                adviceRow(label: "觀點", color: accent, text: advice.reason)
            }
            if let tech = advice.technical, !tech.isEmpty {
                adviceRow(label: "技術面", color: .blue, text: tech)
            }
            if let chips = advice.chips, !chips.isEmpty {
                adviceRow(label: "籌碼面", color: .purple, text: chips)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    private func adviceRow(label: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 6).padding(.vertical, 2.5)
                .background(color.opacity(0.10))
                .foregroundStyle(color)
                .clipShape(Capsule())
                .fixedSize()
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionCard<Content: View>(title: String, icon: String, color: Color,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
            content()
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    private func actionColor(_ action: String) -> Color {
        if action.contains("買") { return upColor }
        if action.contains("減") || action.contains("賣") { return downColor }
        return .blue
    }

    private func sentimentColor(_ s: String) -> Color {
        if s.contains("多") { return upColor }
        if s.contains("空") { return downColor }
        return .secondary
    }

    private func sentimentIcon(_ s: String) -> String {
        if s.contains("多") { return "arrow.up.right" }
        if s.contains("空") { return "arrow.down.right" }
        return "minus"
    }

    // MARK: 起始/提示元件

    private func idleCard(holdings: [Stock]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("將提供給 AI 的資料", systemImage: "doc.text.magnifyingglass")
                .font(.subheadline.weight(.bold))
            VStack(alignment: .leading, spacing: 6) {
                bulletRow("持股 \(holdings.count) 檔（名稱、股數、成本、現價、損益）")
                bulletRow("技術面：近 3 個月日線、MA5／MA20（已快取，不另抓）")
                bulletRow("籌碼面：已收集的三大法人買賣超")
                bulletRow("大盤：加權指數近一個月走勢（現抓）")
            }
            Text("使用 \(aiSettings.activeProvider?.displayName ?? "") API，一次分析約消耗一次請求費用。分析結果僅供參考，非投資建議。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button {
                Task { await analyze() }
            } label: {
                Label("開始分析", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
    }

    private func infoCard(icon: String, color: Color, title: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(color)
            Text(title).font(.subheadline.weight(.semibold))
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(accent)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.primary.opacity(0.85))
    }

    // MARK: 分析流程

    private func analyze() async {
        phase = .loading
        let prompt = await buildPrompt()
        let system = """
        你是台股投資分析助手。使用者提供持股現況、技術面（均線）、籌碼面（三大法人買賣超）與近月大盤走勢。
        只回傳 JSON（不要 markdown 圍欄、不要 JSON 以外的任何文字），格式如下：
        {"market":{"summary":"大盤簡評 2~3 句","sentiment":"偏多|中性|偏空 三選一"},
         "stocks":[{"symbol":"2330","name":"台積電","action":"買進加碼|續抱觀察|減碼賣出 三選一","reason":"建議理由 2~3 句","technical":"技術面解讀 1~2 句","chips":"籌碼面解讀 1~2 句"}],
         "portfolio":"整體配置觀點 2~3 句",
         "risks":["風險提醒（2~4 條）"]}
        所有文字用繁體中文、語氣務實直接、不吹捧；某檔資料不足就在對應欄位直說。stocks 必須涵蓋使用者提供的每一檔持股。
        """
        do {
            let out = try await AIExpenseParserService.shared.completeText(
                system: system, prompt: prompt, maxTokens: 2000)
            phase = .done(Self.parseResult(out))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// 解析 AI 回傳的 JSON；失敗時整段當純文字保底
    fileprivate static func parseResult(_ raw: String) -> AIResult {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 容錯：去掉 markdown 圍欄、抓第一個 { 到最後一個 } 之間
        if let a = s.firstIndex(of: "{"), let b = s.lastIndex(of: "}"), a < b {
            s = String(s[a...b])
        }
        guard let data = s.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return AIResult(rawFallback: raw)
        }
        var result = AIResult()
        if let market = json["market"] as? [String: Any] {
            result.marketSummary = market["summary"] as? String
            result.marketSentiment = market["sentiment"] as? String
        }
        for item in (json["stocks"] as? [[String: Any]]) ?? [] {
            result.stocks.append(StockAdvice(
                symbol: (item["symbol"] as? String ?? "").trimmingCharacters(in: .whitespaces),
                name: (item["name"] as? String ?? "").trimmingCharacters(in: .whitespaces),
                action: item["action"] as? String ?? "續抱觀察",
                reason: item["reason"] as? String ?? "",
                technical: item["technical"] as? String,
                chips: item["chips"] as? String
            ))
        }
        result.portfolio = json["portfolio"] as? String
        result.risks = (json["risks"] as? [String]) ?? []
        // 解析出來什麼都沒有：退回純文字
        if result.stocks.isEmpty && (result.marketSummary ?? "").isEmpty {
            return AIResult(rawFallback: raw)
        }
        return result
    }

    private func fmt2(_ v: Double) -> String { String(format: "%.2f", v) }

    /// 把持股＋日線快取＋法人快照＋大盤現抓整理成給 AI 的結構化文字
    private func buildPrompt() async -> String {
        let holdings = store.stocks.filter { !$0.isSold }
        var lines: [String] = []
        lines.append("【持股明細】")
        // 法人快照整批載入一次（背景執行緒）
        let instRecords = await Task.detached(priority: .userInitiated) {
            InstitutionalHistory.tradingRecords()
        }.value
        for s in holdings {
            var l = "・\(s.name)（\(s.symbol)）：\(Int(s.shares)) 股，成本 \(fmt2(s.purchasePrice))，現價 \(fmt2(s.currentPrice))，損益 \(String(format: "%+.1f%%", s.returnRate))，市值約 \(Int(s.marketValue)) 元"
            // 技術面（日線快取）
            let closes = StockDailyHistory.cached(symbol: s.symbol).map(\.close)
            if closes.count >= 20 {
                let ma5 = closes.suffix(5).reduce(0, +) / 5
                let ma20 = closes.suffix(20).reduce(0, +) / 20
                let last = closes.last ?? 0
                l += "；MA5 \(fmt2(ma5))、MA20 \(fmt2(ma20))（現價\(last >= ma20 ? "站上" : "跌破")月線）"
                if closes.count >= 21 {
                    let chg = (last / closes[closes.count - 21] - 1) * 100
                    l += "、近 20 日\(String(format: "%+.1f%%", chg))"
                }
            }
            // 籌碼面（法人快照）
            if !instRecords.isEmpty {
                var streak = 0
                var sum5 = 0.0
                for (i, rec) in instRecords.reversed().enumerated() {
                    if let v = rec.net[s.symbol] {
                        if i < 5 { sum5 += v }
                        if v > 0, streak == i { streak += 1 }
                    }
                }
                let sheets5 = Int((sum5 / 1000).rounded())
                l += "；法人近 5 日\(sheets5 >= 0 ? "買超" : "賣超") \(abs(sheets5)) 張"
                if streak >= 2 { l += "、已連續買超 \(streak) 天" }
            }
            lines.append(l)
        }
        // 大盤（加權指數，現抓 Yahoo）
        if let taiex = await fetchTAIEX() {
            lines.append("")
            lines.append("【大盤（加權指數）】\(taiex)")
        }
        if let first = instRecords.first?.date, let last = instRecords.last?.date {
            lines.append("")
            lines.append("【法人資料範圍】\(first) ～ \(last)（共 \(instRecords.count) 個交易日）")
        }
        return lines.joined(separator: "\n")
    }

    /// 加權指數近一個月走勢（Yahoo ^TWII）
    private func fetchTAIEX() async -> String? {
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/%5ETWII?range=1mo&interval=1d") else { return nil }
        do {
            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chart = json["chart"] as? [String: Any],
                  let result = (chart["result"] as? [[String: Any]])?.first,
                  let quote = ((result["indicators"] as? [String: Any])?["quote"]
                               as? [[String: Any]])?.first,
                  let rawCloses = quote["close"] as? [Any] else { return nil }
            let closes = rawCloses.compactMap { $0 as? Double }
            guard let last = closes.last, let first = closes.first, closes.count >= 2 else { return nil }
            let monthChg = (last / first - 1) * 100
            var text = "目前約 \(Int(last)) 點，近一個月 \(String(format: "%+.1f%%", monthChg))"
            if closes.count >= 6 {
                let weekChg = (last / closes[closes.count - 6] - 1) * 100
                text += "、近五個交易日 \(String(format: "%+.1f%%", weekChg))"
            }
            return text
        } catch { return nil }
    }
}
