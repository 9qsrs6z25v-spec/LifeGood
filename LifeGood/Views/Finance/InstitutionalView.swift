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
    var net: [String: Double]        // symbol → 三大法人合計買賣超股數（+買超 / −賣超）
    var names: [String: String]      // symbol → 名稱
    // 分計（v25.239 起收集；舊快照檔沒有這三個 key，Optional 解碼自動為 nil，
    // 畫面對沒有分計的日子退回只畫合計）。外資含外資自營商。
    var foreign: [String: Double]?   // symbol → 外資買賣超股數
    var trust: [String: Double]?     // symbol → 投信買賣超股數
    var dealer: [String: Double]?    // symbol → 自營商買賣超股數
    // 籌碼面（v25.240 起收集）。融資融券單位是「張」（官方原始單位，不再換算）；
    // 外資持股比率單位是 %。融資融券約 21:00 才公布（比 T86 晚），
    // 當天傍晚抓到 T86 但沒抓到融資券時這三個維持 nil，下次開 App 的
    // 升級回補分支會重抓補上。
    var marginBalance: [String: Double]?   // symbol → 融資餘額（張）
    var shortBalance: [String: Double]?    // symbol → 融券餘額（張）
    var foreignPct: [String: Double]?      // symbol → 全體外資持股比率（%）
}

enum InstitutionalHistory {
    /// [v25.310] 保留天數改可調（進階設定；預設 30、範圍 5~365）。
    /// 天數越多，訊號追蹤能回測的區間越長，代價是磁碟容量（每個交易日一個 JSON 檔）。
    static let maxDaysKey = "inst_history_max_days"
    static var maxDays: Int {
        let v = UserDefaults.standard.integer(forKey: maxDaysKey)
        return v == 0 ? 30 : min(max(v, 5), 365)
    }

    /// 快照佔用統計（進階設定顯示與容量反推用）：檔案數＋總位元組
    static func storageInfo() -> (files: Int, bytes: Int64) {
        let fm = FileManager.default
        var bytes: Int64 = 0
        let dates = storedDates()
        for d in dates {
            let path = dirURL.appendingPathComponent(d + ".json").path
            if let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? Int64 {
                bytes += size
            }
        }
        return (dates.count, bytes)
    }

    /// 立即套用保留天數（進階設定調小天數時呼叫，馬上刪最舊的快照）
    static func applyRetentionNow() { prune() }

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
            } else if existing?.net.isEmpty == true {
                // 空標記每天重驗一次（今天＝抓太早重試；過去＝可能是網路失敗誤存的
                // 空標記，也可能是真休市——重驗一次成本一兩個請求，能自癒就值得）
                needFetch = true
            } else if existing?.net.isEmpty == false,
                      existing?.foreign == nil || existing?.marginBalance == nil {
                // 升級回補：舊版快照缺分計（v25.239 前）或缺融資券/外資持股
                //（v25.240 前，或當天抓太早融資券還沒公布）。官方歷史日期照樣
                // 查得到，回看窗內重抓一次補上，補齊後不會再進到這個分支。
                needFetch = true
            } else {
                needFetch = false
            }
            guard needFetch else { continue }
            let (rec, definitive) = await fetchDay(day)
            if !rec.net.isEmpty {
                save(rec)
                added += 1
            } else if back > 0, definitive {
                // 官方**有回應**且明確說沒資料（休市日）才存空標記。
                // 網路失敗的空回傳不落地——落了會把那一天永久標成沒資料，
                // 一次斷網就毒掉整個回看窗（歷來「一直沒有法人資料」的元凶之一）。
                save(rec)
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
        return added
    }

    /// 抓某一天：上市（T86）＋上櫃（TPEx）合併為一份快照，含外資／投信／自營分計
    /// 回傳 (快照, definitive)。definitive＝至少一個官方來源**成功回應**
    ///（含「明確說當天沒資料」的休市回應）；純網路失敗為 false，
    /// 呼叫端據此決定能不能存空標記。
    static func fetchDay(_ day: Date) async -> (InstDailyRecord, Bool) {
        let key = dayFmt.string(from: day)
        var definitive = false
        var net: [String: Double] = [:]
        var names: [String: String] = [:]
        var foreign: [String: Double] = [:]
        var trust: [String: Double] = [:]
        var dealer: [String: Double] = [:]

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
                let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if parsed?["stat"] is String { definitive = true }   // 官方有回應（OK 或休市訊息）
                if let json = parsed,
                   (json["stat"] as? String) == "OK",
                   let fields = json["fields"] as? [String],
                   let rows = json["data"] as? [[Any]],
                   let codeIdx = fields.firstIndex(of: "證券代號"),
                   let nameIdx = fields.firstIndex(of: "證券名稱"),
                   let netIdx = fields.firstIndex(of: "三大法人買賣超股數") {
                    // 分計欄（依欄名找；找不到就只存合計，不因官方改欄名整天資料泡湯）。
                    // 「外資」照一般看盤軟體口徑＝外陸資（不含外資自營商）＋外資自營商。
                    let fIdx1 = fields.firstIndex(of: "外陸資買賣超股數(不含外資自營商)")
                    let fIdx2 = fields.firstIndex(of: "外資自營商買賣超股數")
                    let tIdx = fields.firstIndex(of: "投信買賣超股數")
                    let dIdx = fields.firstIndex(of: "自營商買賣超股數")
                    for row in rows {
                        guard row.count > max(codeIdx, max(nameIdx, netIdx)),
                              let code = (row[codeIdx] as? String)?
                                  .trimmingCharacters(in: .whitespaces), !code.isEmpty,
                              let netStr = row[netIdx] as? String,
                              let v = parseNumber(netStr) else { continue }
                        net[code] = v
                        names[code] = (row[nameIdx] as? String)?
                            .trimmingCharacters(in: .whitespaces) ?? code
                        func col(_ idx: Int?) -> Double? {
                            guard let idx, row.count > idx, let s = row[idx] as? String else { return nil }
                            return parseNumber(s)
                        }
                        if let f1 = col(fIdx1) { foreign[code] = f1 + (col(fIdx2) ?? 0) }
                        if let t = col(tIdx) { trust[code] = t }
                        if let d = col(dIdx) { dealer[code] = d }
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
                    let parsedT = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    if parsedT?["tables"] != nil { definitive = true }   // 官方有回應
                    if let json = parsedT,
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
                            // 分計：TPEx 欄名整排重複（買進/賣出/買賣超 ×7 組）沒法靠名字找，
                            // 用固定位置（10 外資合計、13 投信、22 自營合計），但**驗算後才收**：
                            // 三者相加要等於末欄合計，不合就代表官方改了版面，寧可當天只存合計。
                            if row.count > 22,
                               let f = (row[10] as? String).flatMap(parseNumber),
                               let t = (row[13] as? String).flatMap(parseNumber),
                               let dd = (row[22] as? String).flatMap(parseNumber),
                               abs(f + t + dd - v) < 1 {
                                foreign[code] = f; trust[code] = t; dealer[code] = dd
                            }
                        }
                    }
                } catch {}
            }
        }
        // 籌碼面：融資融券餘額（上市 MI_MARGN + 上櫃 margin/balance）與外資持股比率
        //（上市 MI_QFIIS + 上櫃 insti/qfii）。各自獨立失敗——例如融資券當天
        // 還沒公布（約 21:00）——不影響已抓到的法人資料。
        var marginBal: [String: Double] = [:]
        var shortBal: [String: Double] = [:]
        var fPct: [String: Double] = [:]

        // 上市融資融券：欄名「買進/賣出/前日餘額/今日餘額」融資融券兩組重複，
        // 用 firstIndex（融資）/lastIndex（融券）取「今日餘額」。
        if let url = URL(string: "https://www.twse.com.tw/rwd/zh/marginTrading/MI_MARGN?date=\(ymd)&selectType=STOCK&response=json") {
            do {
                var req = URLRequest(url: url)
                req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                let (data, _) = try await URLSession.shared.data(for: req)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tables = json["tables"] as? [[String: Any]],
                   let table = tables.first(where: { (($0["fields"] as? [String]) ?? []).contains("今日餘額") }),
                   let fields = table["fields"] as? [String],
                   let rows = table["data"] as? [[Any]],
                   let codeIdx = fields.firstIndex(of: "代號"),
                   let mIdx = fields.firstIndex(of: "今日餘額"),
                   let sIdx = fields.lastIndex(of: "今日餘額"), sIdx != mIdx {
                    for row in rows {
                        guard row.count > sIdx,
                              let code = (row[codeIdx] as? String)?
                                  .trimmingCharacters(in: .whitespaces),
                              !code.isEmpty, code != "合計" else { continue }
                        if let s = row[mIdx] as? String, let v = parseNumber(s) { marginBal[code] = v }
                        if let s = row[sIdx] as? String, let v = parseNumber(s) { shortBal[code] = v }
                    }
                }
            } catch {}
        }

        // 上櫃新版 www 端點的日期參數（2026/08/14 這種西元斜線格式；query 裡的
        // 斜線不需要編碼，實測可用）
        let tpexDayArg: String? = {
            guard let y = comps.year, let m = comps.month, let d = comps.day else { return nil }
            return String(format: "%04d/%02d/%02d", y, m, d)
        }()

        // 上櫃融資融券（新版 www 端點；欄名唯一，直接依名找）
        if let dayArg = tpexDayArg,
           let url = URL(string: "https://www.tpex.org.tw/www/zh-tw/margin/balance?date=\(dayArg)&response=json") {
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
                   let mIdx = fields.firstIndex(of: "資餘額"),
                   let sIdx = fields.firstIndex(of: "券餘額") {
                    for row in rows {
                        guard row.count > max(mIdx, sIdx),
                              let code = (row[codeIdx] as? String)?
                                  .trimmingCharacters(in: .whitespaces), !code.isEmpty else { continue }
                        if let s = row[mIdx] as? String, let v = parseNumber(s) { marginBal[code] = v }
                        if let s = row[sIdx] as? String, let v = parseNumber(s) { shortBal[code] = v }
                    }
                }
            } catch {}
        }

        func parsePct(_ s: String) -> Double? {
            parseNumber(s.replacingOccurrences(of: "%", with: ""))
        }

        // 上市外資持股比率
        if let url = URL(string: "https://www.twse.com.tw/rwd/zh/fund/MI_QFIIS?date=\(ymd)&selectType=ALLBUT0999&response=json") {
            do {
                var req = URLRequest(url: url)
                req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                let (data, _) = try await URLSession.shared.data(for: req)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   (json["stat"] as? String) == "OK",
                   let fields = json["fields"] as? [String],
                   let rows = json["data"] as? [[Any]],
                   let codeIdx = fields.firstIndex(of: "證券代號"),
                   let pctIdx = fields.firstIndex(where: { $0.contains("全體外資") && $0.contains("持股比率") }) {
                    for row in rows {
                        guard row.count > max(codeIdx, pctIdx),
                              let code = (row[codeIdx] as? String)?
                                  .trimmingCharacters(in: .whitespaces), !code.isEmpty,
                              let s = row[pctIdx] as? String, let v = parsePct(s) else { continue }
                        fPct[code] = v
                    }
                }
            } catch {}
        }

        // 上櫃外資持股比率（僑外資及陸資持股比率；排除「尚可投資比率」那欄）
        if let dayArg = tpexDayArg,
           let url = URL(string: "https://www.tpex.org.tw/www/zh-tw/insti/qfii?date=\(dayArg)&response=json") {
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
                   let pctIdx = fields.firstIndex(where: { $0.contains("持股比率") && !$0.contains("尚可") }) {
                    for row in rows {
                        guard row.count > max(codeIdx, pctIdx),
                              let code = (row[codeIdx] as? String)?
                                  .trimmingCharacters(in: .whitespaces), !code.isEmpty,
                              let s = row[pctIdx] as? String, let v = parsePct(s) else { continue }
                        fPct[code] = v
                    }
                }
            } catch {}
        }

        let rec = InstDailyRecord(date: key, net: net, names: names,
                                  foreign: foreign.isEmpty ? nil : foreign,
                                  trust: trust.isEmpty ? nil : trust,
                                  dealer: dealer.isEmpty ? nil : dealer,
                                  marginBalance: marginBal.isEmpty ? nil : marginBal,
                                  shortBalance: shortBal.isEmpty ? nil : shortBal,
                                  foreignPct: fPct.isEmpty ? nil : fPct)
        return (rec, definitive)
    }
}

// MARK: - 法人連續買超篩選頁

struct InstitutionalBuyView: View {
    @Environment(\.dismiss) private var dismiss
    /// 連續買超天數門檻（上限受保留天數與已收集天數限制）
    @AppStorage("inst_streak_days") private var streakDays: Int = 3
    @State private var records: [InstDailyRecord] = []   // 交易日、時間升冪
    @State private var rows: [StreakRow] = []
    @State private var loading = true
    @State private var collecting = false
    /// [v25.309] 分頁：0＝連買統計（既有）、1＝訊號追蹤（連買完成後 N 天漲幅回測）
    @State private var tab = 0

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
            VStack(spacing: 0) {
                Picker("頁面", selection: $tab) {
                    Text("連買統計").tag(0)
                    Text("訊號追蹤").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.top, 8).padding(.bottom, 4)

                Group {
                    if loading {
                        ProgressView("讀取法人資料中…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if records.isEmpty {
                        emptyState
                    } else if tab == 0 {
                        resultList
                    } else {
                        InstSignalTrackView(records: records)
                    }
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

    private var maxSelectableDays: Int { max(1, min(InstitutionalHistory.maxDays, records.count)) }

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
                Text("已收集 \(records.count) 個交易日（\(records.first?.date ?? "—") ～ \(records.last?.date ?? "—")）；每天開 App 自動累積，最多 \(InstitutionalHistory.maxDays) 天（進階設定可調）。資料含上市＋上櫃，收盤後約 16:30 公布。")
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

// MARK: - 訊號追蹤頁（v25.309：連買完成後 N 天漲幅回測）

/// 法人連買「訊號」的事後表現追蹤：在已收集的快照裡找出「連續買超達門檻」的
/// 完成日（例：8/15 完成連買 5 天），抓該股日線計算完成日收盤 → N 個交易日後
/// 收盤的漲跌幅；還沒滿 N 天的標示「追蹤中（第 X 天）」用最新收盤先算。
/// 頂部附已完訓訊號的勝率與平均漲幅——回測這個訊號到底準不準。
struct InstSignalTrackView: View {
    let records: [InstDailyRecord]   // 交易日、時間升冪（父頁載入）

    /// 連買達幾天算一個訊號（與統計頁門檻各自獨立）
    @AppStorage("inst_track_threshold") private var threshold = 5
    /// 訊號完成後追蹤幾個交易日（使用者指定可設定；例：10 天、20 天）
    @AppStorage("inst_track_horizon") private var horizonDays = 10

    @State private var events: [SignalEvent] = []
    @State private var priceMap: [String: [StockDailyPoint]] = [:]
    @State private var pricingProgress: (done: Int, total: Int)?
    @State private var priceTask: Task<Void, Never>?

    private let accent = Color(red: 1.00, green: 0.62, blue: 0.22)
    /// 事件上限：需要逐檔抓日線，限量控制網路與快取成本（依累計買超取大者）
    private static let maxEvents = 40

    struct SignalEvent: Identifiable {
        let symbol: String
        let name: String
        let signalDate: String   // 連買達門檻那天（yyyy-MM-dd）
        let runLength: Int       // 該段連買最終天數（可能 > 門檻）
        let totalShares: Double  // 整段連買累計買超股數
        var id: String { "\(symbol)_\(signalDate)" }
    }

    var body: some View {
        List {
            controlSection
            summarySection
            eventSection
        }
        .onAppear { recompute() }
        .onChange(of: threshold) { _, _ in recompute() }
        .onChange(of: horizonDays) { _, _ in recompute() }
        .onDisappear { priceTask?.cancel() }
    }

    // MARK: 控制列

    private var maxThreshold: Int { max(2, min(15, records.count)) }

    private var controlSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("連買達").font(.subheadline)
                    Spacer()
                    Text("\(threshold) 天＝訊號")
                        .font(.subheadline.weight(.bold)).foregroundStyle(accent).monospacedDigit()
                }
                Slider(value: Binding(get: { Double(min(threshold, maxThreshold)) },
                                      set: { threshold = Int($0.rounded()) }),
                       in: 2...Double(maxThreshold), step: 1)
                    .tint(accent)
                HStack {
                    Text("追蹤").font(.subheadline)
                    Spacer()
                    Text("\(horizonDays) 個交易日後")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.indigo).monospacedDigit()
                }
                Slider(value: Binding(get: { Double(horizonDays) },
                                      set: { horizonDays = Int($0.rounded()) }),
                       in: 3...40, step: 1)
                    .tint(.indigo)
            }
            .padding(.vertical, 2)
        } footer: {
            Text("在已收集的 \(records.count) 個交易日內，找出「連續買超達 \(threshold) 天」的完成日，顯示完成日收盤 → \(horizonDays) 個交易日後收盤的漲跌幅；未滿 \(horizonDays) 天的先以最新收盤計算並標示追蹤中。")
        }
    }

    // MARK: 勝率摘要

    private var summarySection: some View {
        let done = events.compactMap { e -> Double? in
            guard let c = change(for: e), c.done else { return nil }
            return c.pct
        }
        return Section {
            if done.isEmpty {
                Text(pricingProgress != nil
                     ? "股價載入中…（\(pricingProgress!.done)/\(pricingProgress!.total)）"
                     : "尚無已滿 \(horizonDays) 天的訊號可統計")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                let wins = done.filter { $0 > 0 }.count
                let avg = done.reduce(0, +) / Double(done.count)
                HStack(spacing: 0) {
                    statCell("已完成追蹤", "\(done.count) 筆", .secondary)
                    Divider()
                    statCell("上漲比例", String(format: "%.0f%%", Double(wins) / Double(done.count) * 100),
                             wins * 2 >= done.count ? .red : .green)
                    Divider()
                    statCell("平均漲跌", String(format: "%+.1f%%", avg), avg >= 0 ? .red : .green)
                }
            }
        } header: {
            Text("\(horizonDays) 日後表現統計（台股慣例：漲紅跌綠）")
        }
    }

    private func statCell(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(color).monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 事件清單

    private var eventSection: some View {
        Section {
            if events.isEmpty {
                Text("已收集的資料裡沒有「連買達 \(threshold) 天」的訊號")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(events) { e in
                    eventRow(e)
                }
            }
        } header: {
            Text("訊號 \(events.count) 筆（新到舊；量能前 \(Self.maxEvents) 筆）")
        }
    }

    private func eventRow(_ e: SignalEvent) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(e.symbol).font(.subheadline.weight(.semibold))
                    Text(e.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 5) {
                    Text("\(shortDate(e.signalDate)) 完成連買 \(threshold) 天")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(accent.opacity(0.12)).foregroundStyle(accent)
                        .clipShape(Capsule())
                    if e.runLength > threshold {
                        Text("共連買 \(e.runLength) 天")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red.opacity(0.10)).foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            changeBadge(e)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func changeBadge(_ e: SignalEvent) -> some View {
        if let c = change(for: e) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%+.1f%%", c.pct))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(c.pct >= 0 ? Color.red : Color.green)
                    .monospacedDigit()
                Text(c.done ? "\(horizonDays) 日後" : "追蹤中（第 \(c.elapsed) 天）")
                    .font(.system(size: 9))
                    .foregroundStyle(c.done ? Color.secondary : accent)
            }
        } else if pricingProgress != nil {
            ProgressView().controlSize(.small)
        } else {
            Text("無股價")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func shortDate(_ key: String) -> String {
        // yyyy-MM-dd → M/d
        let parts = key.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return key }
        return "\(m)/\(d)"
    }

    // MARK: 計算

    /// 訊號完成日 → N 交易日後的漲跌幅。done＝已滿 N 天；未滿用最新收盤（elapsed＝已過交易日數）
    private func change(for e: SignalEvent) -> (pct: Double, elapsed: Int, done: Bool)? {
        guard let pts = priceMap[e.symbol], !pts.isEmpty else { return nil }
        guard let startIdx = pts.firstIndex(where: {
            InstitutionalHistory.dayFmt.string(from: $0.date) == e.signalDate
        }) else { return nil }
        let base = pts[startIdx].close
        guard base > 0 else { return nil }
        let targetIdx = startIdx + horizonDays
        if targetIdx < pts.count {
            return ((pts[targetIdx].close - base) / base * 100, horizonDays, true)
        }
        let lastIdx = pts.count - 1
        guard lastIdx > startIdx else { return nil }
        return ((pts[lastIdx].close - base) / base * 100, lastIdx - startIdx, false)
    }

    /// 掃描快照找訊號事件，再逐檔載入日線
    private func recompute() {
        let thr = min(threshold, maxThreshold)
        var found: [SignalEvent] = []
        // 每檔的逐日買超序列：缺當日資料或 ≤0 視為中斷
        var allSymbols = Set<String>()
        for rec in records { for (s, v) in rec.net where v > 0 { allSymbols.insert(s) } }
        let latestNames = records.last?.names ?? [:]
        for sym in allSymbols {
            var runStart = -1, runCount = 0
            var runTotal = 0.0
            func closeRun(endIndex: Int) {
                if runCount >= thr {
                    let signalDate = records[runStart + thr - 1].date
                    let name = latestNames[sym] ?? records[endIndex].names[sym] ?? sym
                    found.append(SignalEvent(symbol: sym, name: name, signalDate: signalDate,
                                             runLength: runCount, totalShares: runTotal))
                }
                runStart = -1; runCount = 0; runTotal = 0
            }
            for (i, rec) in records.enumerated() {
                if let v = rec.net[sym], v > 0 {
                    if runCount == 0 { runStart = i }
                    runCount += 1; runTotal += v
                } else if runCount > 0 {
                    closeRun(endIndex: i - 1)
                }
            }
            if runCount > 0 { closeRun(endIndex: records.count - 1) }
        }
        // 新到舊；同日依累計買超大者；限量（要逐檔抓日線）
        events = Array(
            found.sorted {
                $0.signalDate != $1.signalDate ? $0.signalDate > $1.signalDate
                                               : $0.totalShares > $1.totalShares
            }
            .prefix(Self.maxEvents)
        )
        loadPrices()
    }

    /// 逐檔抓日線（快取新鮮直接用；間隔 0.25 秒不轟炸），完成一檔更新一檔
    private func loadPrices() {
        priceTask?.cancel()
        let symbols = Array(Set(events.map(\.symbol)))
        let need = symbols.filter { priceMap[$0] == nil }
        guard !need.isEmpty else { pricingProgress = nil; return }
        pricingProgress = (0, need.count)
        priceTask = Task {
            var done = 0
            for sym in need {
                guard !Task.isCancelled else { return }
                if StockDailyHistory.isFresh(symbol: sym) {
                    let pts = StockDailyHistory.cached(symbol: sym)
                    await MainActor.run { priceMap[sym] = pts }
                } else {
                    let pts = await StockDailyHistory.fetch(symbol: sym)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { priceMap[sym] = pts }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
                done += 1
                let progress = (done, need.count)
                await MainActor.run { pricingProgress = progress }
            }
            await MainActor.run { pricingProgress = nil }
        }
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
        /// 分計（v25.239 之前收集的舊快照沒有 → nil，該日退回畫單色合計柱）
        let foreign: Double?
        let trust: Double?
        let dealer: Double?
        var id: Date { date }
        var hasBreakdown: Bool { foreign != nil || trust != nil || dealer != nil }
    }
    @State private var points: [DayNet] = []

    private let upColor = Color(red: 0.92, green: 0.26, blue: 0.21)
    private let downColor = Color(red: 0.13, green: 0.65, blue: 0.37)
    // 分計三色（外資／投信／自營商），對齊一般看盤軟體的直覺配色
    private let foreignColor = Color.blue
    private let trustColor = Color.orange
    private let dealerColor = Color.purple

    /// 整個快照庫一筆資料都沒有（收集還沒跑完或一直失敗）——顯示提示卡說明原因
    @State private var storeIsEmpty = false

    var body: some View {
        Group {
            if points.isEmpty {
                // ⚠️ 這個佔位不能拿掉：載入前 points 是空的，若這個分支什麼都不畫，
                // 整張卡是空視圖，掛在下面的 .task 不會被觸發（SwiftUI 對不佔版面的
                // 視圖不保證跑 onAppear/task）——結果就是永遠載不了資料、卡片永遠不出現。
                // 這正是本卡上線以來從沒顯示過的原因（使用者回報「沒看到法人資訊」）。
                if storeIsEmpty {
                    collectingHint
                } else {
                    Color.clear.frame(height: 1)
                }
            }
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
                    if let last = points.last, last.hasBreakdown {
                        breakdownRow(last)
                    }
                    // 有分計的日子畫三色堆疊柱（正values往上疊、負往下疊，Charts 自動處理）；
                    // 舊快照沒有分計的日子退回單色合計柱，兩種同圖共存。
                    Chart {
                        ForEach(points) { p in
                            if p.hasBreakdown {
                                BarMark(x: .value("日", p.date),
                                        y: .value("張", (p.foreign ?? 0) / 1000),
                                        width: .fixed(6))
                                    .foregroundStyle(foreignColor)
                                BarMark(x: .value("日", p.date),
                                        y: .value("張", (p.trust ?? 0) / 1000),
                                        width: .fixed(6))
                                    .foregroundStyle(trustColor)
                                BarMark(x: .value("日", p.date),
                                        y: .value("張", (p.dealer ?? 0) / 1000),
                                        width: .fixed(6))
                                    .foregroundStyle(dealerColor)
                            } else {
                                BarMark(x: .value("日", p.date),
                                        y: .value("張", p.net / 1000),
                                        width: .fixed(6))
                                    .foregroundStyle((p.net >= 0 ? upColor : downColor).opacity(0.55))
                            }
                        }
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) }
                    .frame(height: 120)

                    legendRow
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

    /// 最新一日的分計明細列（張；外資含外資自營商）
    private func breakdownRow(_ p: DayNet) -> some View {
        HStack(spacing: 10) {
            breakdownPair("外資", p.foreign, color: foreignColor)
            breakdownPair("投信", p.trust, color: trustColor)
            breakdownPair("自營", p.dealer, color: dealerColor)
            Spacer()
            Text(String(format: "合計 %+.0f 張", p.net / 1000))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(p.net >= 0 ? upColor : downColor)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func breakdownPair(_ label: String, _ shares: Double?, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(shares.map { String(format: "%+.0f", $0 / 1000) } ?? "—")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    private var legendRow: some View {
        HStack(spacing: 10) {
            ForEach([("外資", foreignColor), ("投信", trustColor), ("自營商", dealerColor)], id: \.0) { label, color in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 8, height: 8)
                    Text(label).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if points.contains(where: { !$0.hasBreakdown }) {
                Text("灰柱＝僅有合計的舊資料")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    /// 收集說明卡：整個快照庫還是空的時候，說清楚為什麼沒有資料、什麼時候會有
    private var collectingHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Text("法人買賣超資料收集中。官方於收盤後（約 16:30）公布，開 App 時會自動收集近幾個交易日，收到後這裡會出現買賣超圖表。")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func load() async {
        let sym = symbol
        let result = await Task.detached(priority: .userInitiated) { () -> ([DayNet], Bool) in
            let records = InstitutionalHistory.tradingRecords()
            let pts = records.compactMap { rec -> DayNet? in
                guard let v = rec.net[sym],
                      let d = InstitutionalHistory.dayFmt.date(from: rec.date) else { return nil }
                return DayNet(date: d, net: v,
                              foreign: rec.foreign?[sym],
                              trust: rec.trust?[sym],
                              dealer: rec.dealer?[sym])
            }
            return (pts, records.isEmpty)
        }.value
        points = result.0
        storeIsEmpty = result.1
    }
}

// MARK: - 籌碼指標卡（融資融券餘額＋券資比＋外資持股比率）

/// 個股的融資融券餘額走勢與最新籌碼指標。資料同 InstitutionalHistory 的每日快照
///（融資融券約 21:00 公布，比法人買賣超晚；當天缺的隔天開 App 自動回補）。
/// 沒收集到該股任何資料時整卡隱藏——興櫃與美股沒有這套官方資料。
struct MarginChipCard: View {
    let symbol: String

    private struct DayMargin: Identifiable {
        let date: Date
        let margin: Double?      // 融資餘額（張）
        let short: Double?       // 融券餘額（張）
        let foreignPct: Double?  // 外資持股 %
        var id: Date { date }
    }
    @State private var points: [DayMargin] = []

    private let upColor = Color(red: 0.92, green: 0.26, blue: 0.21)
    private let downColor = Color(red: 0.13, green: 0.65, blue: 0.37)
    private let marginColor = Color.orange
    private let shortColor = Color.purple

    private var chartPoints: [DayMargin] { points.filter { $0.margin != nil } }

    var body: some View {
        Group {
            if points.isEmpty {
                // 佔位讓 .task 一定會觸發（空視圖不保證跑 task，見 InstNetBarCard 註解）。
                // 收集說明由上方的法人卡負責，這裡不重複顯示。
                Color.clear.frame(height: 1)
            }
            if let last = points.last, last.margin != nil || last.foreignPct != nil {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(colors: [.teal, .teal.opacity(0.55)],
                                               startPoint: .top, endPoint: .bottom)
                            )
                            .frame(width: 4, height: 14)
                        Text("籌碼指標")
                            .font(.subheadline.weight(.bold))
                        Text("融資融券・外資持股")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    metricsRow(last)

                    if chartPoints.count >= 2 {
                        Chart(chartPoints) { p in
                            LineMark(x: .value("日", p.date),
                                     y: .value("融資（張）", p.margin ?? 0))
                                .foregroundStyle(marginColor)
                                .lineStyle(StrokeStyle(lineWidth: 1.8))
                            AreaMark(x: .value("日", p.date),
                                     y: .value("融資（張）", p.margin ?? 0))
                                .foregroundStyle(
                                    LinearGradient(colors: [marginColor.opacity(0.18), .clear],
                                                   startPoint: .top, endPoint: .bottom)
                                )
                        }
                        // 融資餘額是「量」不是「價」：軸從資料範圍起跳，
                        // 從 0 起跳的話多數個股會是一條貼底的平線看不出增減
                        .chartYScale(domain: yDomain)
                        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
                        .frame(height: 90)
                        Text("融資餘額走勢（張）")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
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

    private var yDomain: ClosedRange<Double> {
        let vals = chartPoints.compactMap(\.margin)
        let lo = vals.min() ?? 0, hi = vals.max() ?? 1
        guard hi > lo else { return (lo * 0.95)...(hi * 1.05 + 1) }
        let pad = (hi - lo) * 0.15
        return max(0, lo - pad)...(hi + pad)
    }

    /// 最新指標列：融資（±增減）、融券（±增減）、券資比、外資持股
    private func metricsRow(_ last: DayMargin) -> some View {
        // 增減對「前一個有資料的交易日」算
        let prev = points.dropLast().last(where: { $0.margin != nil })
        let mDelta = zip2(last.margin, prev?.margin).map { $0 - $1 }
        let sDelta = zip2(last.short, prev?.short).map { $0 - $1 }
        let ratio = zip2(last.short, last.margin).flatMap { s, m in m > 0 ? s / m * 100 : nil }
        return HStack(spacing: 12) {
            if let m = last.margin { metric("融資", String(format: "%.0f 張", m), delta: mDelta) }
            if let s = last.short { metric("融券", String(format: "%.0f 張", s), delta: sDelta) }
            if let ratio { metric("券資比", String(format: "%.1f%%", ratio), delta: nil) }
            if let f = last.foreignPct { metric("外資持股", String(format: "%.1f%%", f), delta: nil) }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func zip2(_ a: Double?, _ b: Double?) -> (Double, Double)? {
        guard let a, let b else { return nil }
        return (a, b)
    }

    private func metric(_ label: String, _ value: String, delta: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                Text(value).font(.caption.weight(.semibold).monospacedDigit())
                if let delta, delta != 0 {
                    Text(String(format: "%+.0f", delta))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(delta > 0 ? upColor : downColor)
                }
            }
        }
    }

    private func load() async {
        let sym = symbol
        let result = await Task.detached(priority: .userInitiated) { () -> [DayMargin] in
            InstitutionalHistory.tradingRecords().compactMap { rec in
                guard let d = InstitutionalHistory.dayFmt.date(from: rec.date) else { return nil }
                let m = rec.marginBalance?[sym]
                let s = rec.shortBalance?[sym]
                let f = rec.foreignPct?[sym]
                guard m != nil || s != nil || f != nil else { return nil }
                return DayMargin(date: d, margin: m, short: s, foreignPct: f)
            }
        }.value
        points = result
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
