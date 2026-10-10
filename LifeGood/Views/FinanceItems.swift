import SwiftUI
import Charts
import CoreLocation

// MARK: - 理財四頁的項目卡（v25.527）
//
// 跟收支的項目卡同一張卡（MoneyItemCard）：左邊卡面、右邊名稱＋金額、一行分類與補充、一排膠囊、
// 需要的話一條進度。這裡是「一檔股票／一張保單／一台車／一間房子要寫什麼字」：
//   股票   卡面是近期的 K 線（紅漲綠跌），膠囊是今日漲跌、報酬
//   儲蓄險 卡面是保單插畫，膠囊是下次繳費、到期可領，進度是繳了幾期
//   載具   卡面是最新一張照片或插畫，膠囊是每度電／每公升、折舊，進度是車貸
//   房地產 卡面是照片或地址查出來的衛星空照，膠囊是出租、增值，進度是房貸
// 點儲蓄險先看保單卡（InsurancePolicyCard），右上角「編輯」才進入編輯（跟固定支出的預覽卡一樣）。

private func financeNumberFormatter(_ digits: Int) -> NumberFormatter {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.minimumFractionDigits = 0
    f.maximumFractionDigits = digits
    return f
}

private let financeNumber2 = financeNumberFormatter(2)
private let financeNumber4 = financeNumberFormatter(4)

private let financeDate: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_Hant_TW")
    f.dateFormat = "yyyy/M/d"
    return f
}()

enum FinanceItemText {
    /// 「612」「61.25」「1,234.5」（小數最多兩位；股數這種要四位的傳 digits: 4）
    static func number(_ v: Double, digits: Int = 2) -> String {
        let f = digits > 2 ? financeNumber4 : financeNumber2
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v)
    }

    static func date(_ d: Date) -> String { financeDate.string(from: d) }
}

// MARK: - 股票

enum StockScriptName {
    /// 卡面左下的手寫字（手寫字型沒有中文字形）：常見的台股寫英文名，沒有的寫「Stocks」
    private static let english: [String: String] = [
        "2330": "TSMC", "2317": "Foxconn", "2454": "MediaTek", "2308": "Delta", "2382": "Quanta",
        "2303": "UMC", "3711": "ASE", "2357": "Asus", "2379": "Realtek", "3008": "Largan",
        "2412": "Chunghwa", "2603": "Evergreen", "2609": "Yang Ming", "2615": "Wan Hai",
        "2002": "China Steel", "1301": "Formosa", "1303": "Nan Ya", "2207": "Hotai",
        "1216": "Uni-President", "2881": "Fubon", "2882": "Cathay", "2891": "CTBC", "2886": "Mega",
        "2884": "E.Sun", "2885": "Yuanta", "2892": "First", "2880": "Hua Nan", "2887": "Taishin",
        "2345": "Accton", "3231": "Wistron", "2356": "Inventec", "2395": "Advantech",
        "0050": "Taiwan 50", "006208": "Taiwan 50", "0056": "Dividend", "00878": "Dividend",
    ]

    static func word(_ s: Stock) -> String? {
        if let w = english[s.symbol] { return w }
        let name = s.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty, name.unicodeScalars.allSatisfy(\.isASCII) {
            // Yahoo 給的美股名字是「Apple Inc.」：拿掉公司字尾，最多留兩個字
            let drop: Set<String> = ["inc", "inc.", "corp", "corp.", "corporation", "co", "co.", "ltd", "ltd.",
                                     "plc", "holdings", "group", "company", "class", "&"]
            let words = name.replacingOccurrences(of: ",", with: " ")
                .split(separator: " ")
                .map(String.init)
                .filter { !drop.contains($0.lowercased()) }
            let short = words.prefix(2).joined(separator: " ")
            if !short.isEmpty { return short }
        }
        if s.isUSStock, !s.symbol.isEmpty { return s.symbol }
        return nil
    }

    static func caps(_ s: Stock) -> String {
        if s.isUSStock { return "US STOCK" }
        return isETF(s) ? "TAIWAN ETF" : "TAIWAN STOCK"
    }

    static func isETF(_ s: Stock) -> Bool { !s.isUSStock && s.symbol.hasPrefix("00") }
}

extension MoneyItem {
    /// 數量：台股整張寫「2 張」，零股寫「2,500 股」；美股寫「15 股」
    static func stockQuantity(_ s: Stock, shares: Double) -> String {
        if !s.isUSStock, shares >= 1000, (shares / 1000).rounded() == shares / 1000 {
            return "\(Int(shares / 1000)) 張"
        }
        return FinanceItemText.number(shares, digits: 4) + " 股"
    }

    /// 賣掉的那些的成本（台幣）：算已賣出那一張卡的報酬率用
    private static func soldCostBasis(_ s: Stock) -> Double {
        if s.transactions.isEmpty { return s.shares * s.purchasePrice * s.currencyFactor }
        let sold = s.transactions.filter { $0.kind == .sell }.reduce(0) { $0 + $1.shares }
        return sold * s.purchasePrice * s.currencyFactor
    }

    /// 一檔股票。candles：日線快取的最後幾根（沒有就畫插畫）；dayRate：今天漲跌幾成（StockBoardData 算好的）；
    /// quoteFailed：這次刷新報價沒拿到
    static func stock(_ s: Stock, candles: [MoneyCandle]?, dayRate: Double?, quoteFailed: Bool = false) -> MoneyItem {
        let cur = s.priceCurrencySymbol
        var item = MoneyItem(id: s.id, theme: .finStock, seed: seed(s.id),
                             title: s.name.isEmpty ? (s.symbol.isEmpty ? "股票" : s.symbol) : s.name,
                             amount: "", category: "")
        item.badge = s.isUSStock ? "美股" : (s.symbol.isEmpty ? nil : s.symbol)
        item.category = s.isUSStock ? s.symbol : (StockScriptName.isETF(s) ? "ETF" : "台股")
        item.scriptWord = StockScriptName.word(s)
        item.scriptCaps = StockScriptName.caps(s)

        if s.isSold {
            let realized = s.moneyRealizedProfit
            let basis = soldCostBasis(s)
            let tone = MoneyTone.change(realized, base: max(basis, 1))
            item.amount = FinanceText.signed(realized)
            item.amountTone = tone
            var detail = "已賣出"
            if let d = s.soldDate { detail = FinanceItemText.date(d) + " 賣出" }
            if s.soldPrice > 0 { detail += "・賣價 " + cur + FinanceItemText.number(s.soldPrice) }
            item.detail = detail
            if basis > 0 {
                item.chips.append(MoneyItemChip(icon: realized >= 0 ? "arrow.up.right" : "arrow.down.right",
                                                text: "報酬 " + FinanceText.signedPercent(realized / basis),
                                                tone: tone))
            }
            item.dimmed = true
            return item
        }

        item.amount = s.marketValue.ntdWanString
        var detail = stockQuantity(s, shares: s.shares)
        if s.purchasePrice > 0 { detail += "・均價 " + cur + FinanceItemText.number(s.purchasePrice) }
        item.detail = detail
        if let c = candles, c.count >= 2 { item.candles = c }

        if quoteFailed {
            item.chips.append(MoneyItemChip(icon: "exclamationmark.triangle.fill", text: "報價沒更新", tone: .warn))
        }
        if let r = dayRate {
            if abs(r) < 0.0005 {
                item.chips.append(MoneyItemChip(icon: "minus", text: "今日 平盤"))
            } else {
                item.chips.append(MoneyItemChip(icon: r > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill",
                                                text: "今日 " + FinanceText.percent1(abs(r)),
                                                tone: r > 0 ? .up : .down))
            }
        }
        if s.totalCost > 0, s.currentPrice > 0 {
            let r = s.profitLoss / s.totalCost
            item.chips.append(MoneyItemChip(icon: r >= 0 ? "arrow.up.right" : "arrow.down.right",
                                            text: "報酬 " + FinanceText.signedPercent(r),
                                            tone: MoneyTone.change(r)))
        }
        let realized = s.moneyRealizedProfit
        if abs(realized) >= 1 {
            item.chips.append(MoneyItemChip(icon: "checkmark.seal.fill", text: "已實現 " + FinanceText.signed(realized),
                                            tone: MoneyTone.change(realized, base: max(s.totalCost, 1))))
        }
        return item
    }

    /// 日線快取 → 卡面的 K 棒（最後 20 根；舊快取沒有開高低，用前一天收盤當開盤）
    static func stockCandles(_ pts: [StockDailyPoint]) -> [MoneyCandle] {
        let tail = Array(pts.suffix(21))
        var out: [MoneyCandle] = []
        for i in tail.indices {
            let p = tail[i]
            let open = p.open ?? (i > 0 ? tail[i - 1].close : p.close)
            guard open > 0, p.close > 0 else { continue }
            out.append(MoneyCandle(open: open, high: max(p.high ?? max(open, p.close), open, p.close),
                                   low: min(p.low ?? min(open, p.close), open, p.close), close: p.close))
        }
        return Array(out.suffix(20))
    }
}

// MARK: - 儲蓄險

enum InsuranceScriptName {
    /// 保險公司的英文名（手寫字型沒有中文字形）；查不到寫「Savings」
    private static let insurers: [(String, String)] = [
        ("國泰", "Cathay"), ("富邦", "Fubon"), ("南山", "Nan Shan"), ("新光", "Shin Kong"),
        ("台灣人壽", "Taiwan Life"), ("臺灣人壽", "Taiwan Life"), ("凱基", "KGI"), ("中國人壽", "China Life"),
        ("全球", "TransGlobe"), ("三商", "Mercuries"), ("遠雄", "Farglory"), ("安聯", "Allianz"),
        ("保誠", "Prudential"), ("保德信", "Prudential"), ("宏泰", "Hontai"), ("台銀", "BOT Life"),
        ("臺銀", "BOT Life"), ("元大", "Yuanta"), ("第一金", "First Life"), ("合作金庫", "TCB Life"),
        ("友邦", "AIA"), ("法國巴黎", "BNP Paribas"), ("安達", "Chubb"), ("中華郵政", "Post"), ("郵局", "Post"),
        ("台新", "Taishin"), ("玉山", "E.Sun"), ("中信", "CTBC"),
    ]

    static func word(_ ins: SavingsInsurance) -> String? {
        for (key, en) in insurers where ins.company.contains(key) || ins.name.contains(key) { return en }
        return nil
    }

    static func caps(_ code: String) -> String {
        switch code {
        case "NT$", "TWD", "", "台幣", "新台幣": return "NTD POLICY"
        case "美金", "美元", "US$", "USD": return "USD POLICY"
        case "日圓", "日幣", "日元", "JPY": return "JPY POLICY"
        case "人民幣", "CNY", "RMB": return "CNY POLICY"
        case "澳幣", "澳元", "AUD": return "AUD POLICY"
        case "歐元", "EUR": return "EUR POLICY"
        case "英鎊", "GBP": return "GBP POLICY"
        default: return "FX POLICY"
        }
    }

    /// 卡面左上的小膠囊：繳費方式；繳完了寫「繳清」、滿期了寫「滿期」
    static func badge(_ ins: SavingsInsurance, now: Date) -> String {
        if !ins.moneyIsLive(now: now) { return "滿期" }
        if ins.elapsedPeriods(at: now) >= ins.totalPeriods { return "繳清" }
        switch ins.paymentPeriod {
        case .monthly: return "月繳"
        case .quarterly: return "季繳"
        case .yearly: return "年繳"
        }
    }
}

extension MoneyItem {
    private static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d"
        return f
    }()

    private static let yearMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "yyyy/M"
        return f
    }()

    /// 一張儲蓄險。金額是今天的保單價值（原幣別）；外幣在補充那一行寫約當台幣
    static func insurance(_ ins: SavingsInsurance, rates: FinanceRates, now: Date = Date()) -> MoneyItem {
        let cal = Calendar.current
        let code = ins.currencyCode
        let live = ins.moneyIsLive(now: now)
        let value = live ? ins.value(at: now) : ins.calculatedExpectedReturn
        var item = MoneyItem(id: ins.id, theme: .finSavings, seed: seed(ins.id),
                             title: ins.name.isEmpty ? "儲蓄險" : ins.name,
                             amount: FinanceText.money(value, code: code),
                             category: ins.company.trimmingCharacters(in: .whitespaces).isEmpty ? "儲蓄險" : ins.company)
        var detail: [String] = []
        if ins.annualRate > 0 { detail.append(String(format: "%.2f%%", ins.annualRate)) }
        if !FinanceRates.isNTD(code) {
            detail.append("≈ " + rates.ntd(value, code: code).ntdWanString)
        }
        item.detail = detail.isEmpty ? nil : detail.joined(separator: "・")
        item.badge = InsuranceScriptName.badge(ins, now: now)
        item.scriptWord = InsuranceScriptName.word(ins)
        item.scriptCaps = InsuranceScriptName.caps(code)
        item.dimmed = !live

        let today = cal.startOfDay(for: now)
        let daysToMaturity = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: ins.maturityDate)).day ?? 0
        let back = FinanceText.money(ins.calculatedExpectedReturn, code: code)
        if !live {
            item.chips.append(MoneyItemChip(icon: "star.fill", text: "已滿期・領回 " + back, tone: .good))
        } else {
            if let due = ins.moneyNextDue(now: now) {
                let days = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: due)).day ?? 0
                item.chips.append(MoneyItemChip(icon: "calendar",
                                                text: monthDay.string(from: due) + " 繳第 \(ins.elapsedPeriods(at: now) + 1) 期",
                                                tone: days <= 3 ? .warn : .neutral))
            }
            if daysToMaturity <= 60 {
                item.chips.append(MoneyItemChip(icon: "star.fill",
                                                text: monthDay.string(from: ins.maturityDate) + " 滿期・領 " + back,
                                                tone: .good))
            } else {
                item.chips.append(MoneyItemChip(icon: "star.fill", text: "到期 " + back))
            }
        }

        let total = ins.totalPeriods
        if total > 0 {
            let paid = ins.elapsedPeriods(at: now)
            let trailing: String
            if live, daysToMaturity <= 90 {
                trailing = daysToMaturity <= 0 ? "今天滿期" : "還有 \(daysToMaturity) 天"
            } else {
                trailing = yearMonth.string(from: ins.maturityDate) + " 滿期"
            }
            item.progress = MoneyItemProgress(fraction: Double(paid) / Double(total),
                                              leading: "已繳 \(paid)／\(total) 期", trailing: trailing)
        }
        return item
    }
}

// MARK: - 保單卡（點儲蓄險先看這張）

struct InsurancePolicyCard: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    let insurance: SavingsInsurance
    @State private var showEdit = false
    @State private var showPremiumAlert = false

    /// 讀 store 裡最新的那一份（編輯存檔後馬上看得到；找不到才用打開時的快照）
    private var current: SavingsInsurance { store.insurances.first { $0.id == insurance.id } ?? insurance }

    var body: some View {
        let ins = current
        let rates = FinanceRates(expenseStore)
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    InsurancePolicyHero(ins: ins, rates: rates)
                    InsurancePolicyDetails(ins: ins, rates: rates)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("保單")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("編輯") {
                        if subscription.isPremium { showEdit = true } else { showPremiumAlert = true }
                    }
                    .bold()
                }
            }
            .sheet(isPresented: $showEdit) { AddSavingsInsuranceView(editing: ins) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }
}

/// 保單卡的上半：插畫橫幅、名稱、今天的價值、投保到滿期的時間軸、保費與價值的成長圖
struct InsurancePolicyHero: View {
    let ins: SavingsInsurance
    let rates: FinanceRates
    var now: Date = Date()

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = MoneyArtTheme.finSavings
        let code = ins.currencyCode
        let live = ins.moneyIsLive(now: now)
        let value = live ? ins.value(at: now) : ins.calculatedExpectedReturn
        VStack(alignment: .leading, spacing: 0) {
            MoneyArtwork(theme: theme, seed: MoneyItem.seed(ins.id), layout: .banner)
                .equatable()
                .frame(height: 92)
                .overlay(alignment: .bottomLeading) {
                    MoneyArtScript(word: InsuranceScriptName.word(ins) ?? theme.word,
                                   caps: InsuranceScriptName.caps(code), maxWidth: 220, size: 24)
                        .padding(.leading, 14)
                        .padding(.bottom, 20)
                }
                .clipShape(MoneyBannerShape())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ins.name.isEmpty ? "儲蓄險" : ins.name)
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.ink(scheme))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(live ? "今天的保單價值" : "滿期領回")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(FinanceText.money(value, code: code))
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if !FinanceRates.isNTD(code) {
                            Text("≈ " + rates.ntd(value, code: code).ntdWanString)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                InsurancePolicyTimeline(ins: ins, now: now)
                if ins.totalPeriods > 0 {
                    InsurancePolicyChart(ins: ins, now: now)
                }
            }
            .padding(16)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04), lineWidth: 0.75)
        }
        .shadow(color: scheme == .dark ? Color.black.opacity(0.32) : Color(tb: 0x1E3A6E, 0.08), radius: 8, x: 0, y: 3)
    }

    private var subtitle: String {
        var parts: [String] = []
        let company = ins.company.trimmingCharacters(in: .whitespaces)
        if !company.isEmpty { parts.append(company) }
        let period: String
        switch ins.paymentPeriod {
        case .monthly: period = "月繳"
        case .quarterly: period = "季繳"
        case .yearly: period = "年繳"
        }
        parts.append(period + " " + FinanceText.money(ins.premiumAmount, code: ins.currencyCode))
        if ins.annualRate > 0 { parts.append(String(format: "年利率 %.2f%%", ins.annualRate)) }
        return parts.joined(separator: "・")
    }
}

/// 投保 ── 今天 ── 滿期 的時間軸
struct InsurancePolicyTimeline: View {
    let ins: SavingsInsurance
    let now: Date

    @Environment(\.colorScheme) private var scheme

    private static let ym: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "yyyy/M"
        return f
    }()

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let theme = MoneyArtTheme.finSavings
        let span = ins.maturityDate.timeIntervalSince(ins.startDate)
        let t = span > 0 ? min(1, max(0, now.timeIntervalSince(ins.startDate) / span)) : 1
        let live = ins.moneyIsLive(now: now)
        let middle: String
        if now < ins.startDate {
            middle = "還沒開始"
        } else if !live {
            middle = "已滿期"
        } else {
            middle = "今天・第 \(ins.elapsedPeriods(at: now)) 期"
        }
        let card = scheme == .dark ? Color(.secondarySystemGroupedBackground) : Color.white
        return VStack(spacing: 6) {
            Canvas { ctx, size in
                let w = size.width
                let cy = size.height / 2
                let x0: CGFloat = 8
                let x1 = w - 8
                let x = x0 + (x1 - x0) * CGFloat(t)
                ctx.fill(Path(roundedRect: CGRect(x: x0, y: cy - 3, width: x1 - x0, height: 6), cornerRadius: 3),
                         with: .color(pal.progressTrack))
                if x > x0 {
                    ctx.fill(Path(roundedRect: CGRect(x: x0, y: cy - 3, width: x - x0, height: 6), cornerRadius: 3),
                             with: .linearGradient(Gradient(colors: [theme.topColor, theme.bottomColor]),
                                                   startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x, y: 0)))
                }
                for ex in [x0, x1] {
                    let r = CGRect(x: ex - 6, y: cy - 6, width: 12, height: 12)
                    ctx.fill(Path(ellipseIn: r), with: .color(card))
                    ctx.stroke(Path(ellipseIn: r), with: .color(theme.tintColor), lineWidth: 2)
                }
                let big = CGRect(x: x - 8, y: cy - 8, width: 16, height: 16)
                ctx.fill(Path(ellipseIn: big.insetBy(dx: -3, dy: -3)), with: .color(theme.tintColor.opacity(0.25)))
                ctx.fill(Path(ellipseIn: big), with: .color(theme.tintColor))
                ctx.stroke(Path(ellipseIn: big), with: .color(card), lineWidth: 2.5)
            }
            .frame(height: 24)
            .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline) {
                Text(Self.ym.string(from: ins.startDate) + " 投保")
                Spacer(minLength: 6)
                Text(middle)
                    .foregroundStyle(theme.ink(scheme))
                Spacer(minLength: 6)
                Text(Self.ym.string(from: ins.maturityDate) + " 滿期")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 保費與保單價值：灰色的柱是每年累積繳了多少，藍線是保單價值，綠色虛線是滿期可領
struct InsurancePolicyChart: View {
    let ins: SavingsInsurance
    let now: Date

    @Environment(\.colorScheme) private var scheme

    private struct YearBar: Identifiable {
        let id: Int
        let paid: Double
        let past: Bool
    }

    private struct ValuePoint: Identifiable {
        let id: Int
        let x: Double
        let value: Double
    }

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let theme = MoneyArtTheme.finSavings
        let code = ins.currencyCode
        let ppy = Double(ins.moneyPeriodsPerYear)
        let total = ins.totalPeriods
        let years = max(1, Int((Double(total) / ppy).rounded(.up)))
        let rate = ins.annualRate / 100 / ppy
        let elapsed = ins.elapsedPeriods(at: now)
        let live = ins.moneyIsLive(now: now)
        let expected = ins.calculatedExpectedReturn
        let bars: [YearBar] = (1...years).map { y in
            let periods = min(Int(Double(y) * ppy), total)
            return YearBar(id: y, paid: ins.premiumAmount * Double(periods),
                           past: Double(elapsed) > Double(y - 1) * ppy)
        }
        let points: [ValuePoint] = (0...total).map { p in
            ValuePoint(id: p, x: Double(p) / ppy,
                       value: SavingsInsurance.futureValue(payment: ins.premiumAmount, ratePerPeriod: rate, periods: p))
        }
        let todayValue = ins.value(at: now)
        let paidColor = pal.dark ? Color(tb: 0x8A94AD) : Color(tb: 0xA8B0C2)
        let futureColor = paidColor.opacity(0.35)
        let green = MoneyTone.good.color(pal)
        return VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(bars) { b in
                    BarMark(xStart: .value("年", Double(b.id - 1) + 0.18),
                            xEnd: .value("年", Double(b.id) - 0.18),
                            y: .value("已繳保費", b.paid))
                        .foregroundStyle(b.past ? paidColor : futureColor)
                        .cornerRadius(3)
                }
                ForEach(points) { p in
                    LineMark(x: .value("年", p.x), y: .value("保單價值", p.value))
                        .foregroundStyle(theme.tintColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                RuleMark(y: .value("滿期", expected))
                    .foregroundStyle(green)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                if live, elapsed > 0 {
                    PointMark(x: .value("年", Double(elapsed) / ppy), y: .value("保單價值", todayValue))
                        .foregroundStyle(theme.tintColor)
                        .symbolSize(80)
                        .annotation(position: .top, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Text("今天 " + FinanceText.money(todayValue, code: code))
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(theme.ink(scheme))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.regularMaterial, in: Capsule())
                        }
                }
            }
            .chartXScale(domain: 0...Double(years))
            // 上面留一截給「今天」的小牌子
            .chartYScale(domain: 0...(max(expected, bars.last?.paid ?? 0, 1) * 1.22))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 130)
            .accessibilityLabel("保單價值走勢")
            .accessibilityValue("今天 " + FinanceText.money(todayValue, code: code) + "，滿期 " + FinanceText.money(expected, code: code))
            HStack {
                Text("第 1 年")
                Spacer()
                Text("第 \(years) 年")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            ChipFlowLayout(spacing: 12) {
                MoneyLegendItem(mark: .swatch, color: paidColor, text: "已繳保費", pal: pal)
                MoneyLegendItem(mark: .swatch, color: theme.tintColor, text: "保單價值", pal: pal)
                MoneyLegendItem(mark: .dash, color: green, text: "滿期 " + FinanceText.money(expected, code: code), pal: pal)
            }
            .padding(.top, 2)
        }
    }
}

/// 保單卡的下半：一行一個數字
struct InsurancePolicyDetails: View {
    let ins: SavingsInsurance
    let rates: FinanceRates
    var now: Date = Date()

    @Environment(\.colorScheme) private var scheme

    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "yyyy/M/d"
        return f
    }()

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let code = ins.currencyCode
        let paid = ins.elapsedPeriods(at: now)
        let paidAmount = ins.premiumAmount * Double(paid)
        var rows: [(String, Text)] = []
        rows.append(("已繳", Text("\(paid)／\(ins.totalPeriods) 期・" + FinanceText.money(paidAmount, code: code))))
        rows.append(("全部保費", Text(FinanceText.money(ins.moneyFullPremium, code: code))))
        let back = Text(FinanceText.money(ins.calculatedExpectedReturn, code: code)).foregroundStyle(MoneyTone.good.color(pal))
        if let g = ins.moneyGainRate, abs(g) >= 0.005 {
            rows.append(("到期可領", Text("\(back)（\(g > 0 ? "多" : "少") \(FinanceText.percent1(abs(g)))）")))
        } else {
            rows.append(("到期可領", back))
        }
        if let due = ins.moneyNextDue(now: now) {
            rows.append(("下次繳費", Text(Self.ymd.string(from: due) + "・第 \(paid + 1) 期")))
        }
        rows.append(("投保日", Text(Self.ymd.string(from: ins.startDate))))
        rows.append(("滿期日", Text(Self.ymd.string(from: ins.maturityDate))))
        if !FinanceRates.isNTD(code) {
            if let r = rates.known(code) {
                rows.append(("匯率", Text("1 \(code) ≈ NT$" + FinanceItemText.number(r))))
            } else {
                rows.append(("匯率", Text("設定裡沒有\(code)的匯率，換算時當 1").foregroundStyle(MoneyTone.warn.color(pal))))
            }
        }
        if ins.linkedExpenseId != nil {
            rows.append(("記帳", Text("已連結固定支出（保費會記在固定支出）")))
        }
        let note = ins.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                if i > 0 {
                    Divider().padding(.leading, 14)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.0)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    row.1
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .accessibilityElement(children: .combine)
            }
            if !note.isEmpty {
                Divider().padding(.leading, 14)
                VStack(alignment: .leading, spacing: 4) {
                    Text("備註")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(note)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - 載具

enum VehicleScriptName {
    /// 品牌的英文名（手寫字型沒有中文字形）；品牌本來就是英文就直接用
    private static let brands: [(String, String)] = [
        ("特斯拉", "Tesla"), ("豐田", "Toyota"), ("本田", "Honda"), ("日產", "Nissan"), ("馬自達", "Mazda"),
        ("三菱", "Mitsubishi"), ("中華", "CMC"), ("福特", "Ford"), ("賓士", "Mercedes"), ("寶馬", "BMW"),
        ("奧迪", "Audi"), ("福斯", "Volkswagen"), ("現代", "Hyundai"), ("起亞", "Kia"), ("凌志", "Lexus"),
        ("速霸陸", "Subaru"), ("鈴木", "Suzuki"), ("保時捷", "Porsche"), ("富豪", "Volvo"), ("納智捷", "Luxgen"),
        ("標緻", "Peugeot"), ("雪鐵龍", "Citroen"), ("斯柯達", "Skoda"), ("比亞迪", "BYD"), ("光陽", "Kymco"),
        ("三陽", "SYM"), ("山葉", "Yamaha"), ("睿能", "Gogoro"), ("宏佳騰", "Aeon"), ("哈雷", "Harley"),
    ]

    static func word(_ v: Vehicle) -> String? {
        let brand = v.brand.trimmingCharacters(in: .whitespaces)
        if !brand.isEmpty, brand.unicodeScalars.allSatisfy(\.isASCII) { return brand }
        for (key, en) in brands where brand.contains(key) || v.name.contains(key) { return en }
        return nil
    }

    /// 手寫字下面的小字：車名是英文就寫車名（MODEL Y），不然寫動力
    static func caps(_ v: Vehicle) -> String {
        let name = v.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty, name.count <= 18, name.unicodeScalars.allSatisfy(\.isASCII) { return name.uppercased() }
        switch v.powerType {
        case .gasoline: return "ON THE ROAD"
        case .electric: return "ELECTRIC"
        case .hybrid: return "HYBRID"
        case .motorcycle: return "MOTORCYCLE"
        case .electricMotorcycle: return "E-SCOOTER"
        }
    }

    static func theme(_ v: Vehicle) -> MoneyArtTheme {
        switch v.powerType {
        case .gasoline, .hybrid: return .finDrive
        case .electric: return .finElectric
        case .motorcycle: return .finMoto
        case .electricMotorcycle: return .finScooter
        }
    }
}

extension MoneyItem {
    /// 一台車。卡面是最新一張照片（車輛照片優先），沒有照片就是插畫
    static func vehicle(_ v: Vehicle, facts: VehicleFacts?, now: Date = Date()) -> MoneyItem {
        var item = MoneyItem(id: v.id, theme: VehicleScriptName.theme(v), seed: seed(v.id),
                             title: v.name.isEmpty ? "車" : v.name,
                             amount: v.currentValue.ntdWanString,
                             category: v.powerType.rawValue)
        var detail: [String] = []
        let brand = v.brand.trimmingCharacters(in: .whitespaces)
        if !brand.isEmpty { detail.append(brand) }
        let years = v.yearsOwned
        if v.isSold {
            if let d = v.soldDate { detail.append(FinanceItemText.date(d) + " 賣出") }
        } else if years >= 0.1 {
            detail.append("持有 " + FinanceItemText.number(years, digits: 1) + " 年")
        }
        item.detail = detail.isEmpty ? nil : detail.joined(separator: "・")
        let owner = v.ownerName.trimmingCharacters(in: .whitespaces)
        item.badge = v.isSold ? "已售出" : (owner.isEmpty ? nil : MoneyBoardText.short(owner, max: 6))
        item.scriptWord = VehicleScriptName.word(v)
        item.scriptCaps = VehicleScriptName.caps(v)
        item.dimmed = v.isSold
        let photos = v.photoRecords.filter { !$0.photoFileNames.isEmpty }
        let cover = photos.filter { $0.category == .appearance }.max { $0.date < $1.date }
            ?? photos.max { $0.date < $1.date }
        item.photoURL = cover?.photoURL

        if let f = facts, !v.isSold {
            if let p = f.perKwh {
                item.chips.append(MoneyItemChip(icon: "bolt.fill", text: "每度 NT$" + FinanceItemText.number(p, digits: 1)))
            } else if let fuel = f.fuelPerMonth {
                item.chips.append(MoneyItemChip(icon: "fuelpump.fill", text: "油錢 " + MoneyFormat.short(fuel) + "/月"))
            }
        }
        if v.purchasePrice > 0, v.currentValue > 0 {
            let r = v.currentValue / v.purchasePrice - 1
            if abs(r) >= 0.005 {
                item.chips.append(MoneyItemChip(icon: r < 0 ? "arrow.down.right" : "arrow.up.right",
                                                text: (r < 0 ? "折舊 -" : "增值 +") + FinanceText.percent1(abs(r))))
            }
        }
        if let f = facts, !v.isSold, f.monthly > 0 {
            item.chips.append(MoneyItemChip(icon: "creditcard.fill", text: "每月 " + MoneyFormat.short(f.monthly)))
        }
        if let f = facts, !v.isSold, let s = f.loan {
            if s.isDone {
                item.chips.insert(MoneyItemChip(icon: "checkmark.seal.fill", text: "車貸繳清", tone: .good), at: 0)
            } else {
                item.progress = MoneyItemProgress(fraction: Double(s.elapsed) / Double(max(s.total, 1)),
                                                  leading: "車貸 已繳 \(s.elapsed)／\(s.total) 期",
                                                  trailing: "還要 " + MoneyFormat.short(f.loanLeft > 0 ? f.loanLeft : s.left))
            }
        } else if let f = facts, !v.isSold, f.loanLeft >= 1 {
            item.chips.append(MoneyItemChip(icon: "banknote.fill", text: "車貸還要 " + MoneyFormat.short(f.loanLeft)))
        }
        return item
    }
}

// MARK: - 房地產

/// 房子的地址 → 座標（卡面的衛星空照用）。
/// 查過的存起來（只存在這台裝置）；查不到的一週內不再查；跟行程卡的地圖快照、逆地理編碼排同一條隊
/// （TripHeroGate，一次一個：同時打太多會被 Apple 節流）。
///
/// ⚠️ 類別不標 @MainActor（View 用 @ObservedObject 指向 .shared，理由同 TripPlaceNameStore）；
///    只有會動到狀態的 resolve 標。
final class RealEstateGeocoder: ObservableObject {
    static let shared = RealEstateGeocoder()
    private static let key = "realestate_geocode_v1"

    /// 查到新的座標就 +1（卡片跟著重畫）
    @Published private(set) var version = 0
    /// 地址 → [緯度, 經度]；查不到存 [0, 0, 查的時間]
    private var map: [String: [Double]]
    private var inFlight = Set<String>()

    private init() {
        map = (UserDefaults.standard.dictionary(forKey: Self.key) as? [String: [Double]]) ?? [:]
    }

    /// 要拿去查的地址：縣市＋地址；沒填地址就用建物權狀的門牌
    static func address(of re: RealEstate) -> String? {
        if !re.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return re.fullAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let b = re.bldgAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return b.isEmpty ? nil : b
    }

    func coordinate(for address: String?) -> CLLocationCoordinate2D? {
        guard let address, let v = map[address], v.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: v[0], longitude: v[1])
    }

    /// 還沒查過（或查不到已經超過一週）就查一次
    @MainActor
    func resolve(_ address: String) async {
        if let v = map[address] {
            if v.count == 2 { return }
            if v.count == 3, Date().timeIntervalSince1970 - v[2] < 7 * 86_400 { return }
        }
        guard !inFlight.contains(address) else { return }
        inFlight.insert(address)
        defer { inFlight.remove(address) }

        let gate = TripHeroGate.shared
        guard await gate.acquire() else { return }
        defer { gate.release() }
        guard await gate.waitIfPaused() else { return }

        do {
            let marks = try await CLGeocoder().geocodeAddressString(address, in: nil,
                                                                    preferredLocale: Locale(identifier: "zh_Hant_TW"))
            if let c = marks.first?.location?.coordinate {
                map[address] = [c.latitude, c.longitude]
            } else {
                map[address] = [0, 0, Date().timeIntervalSince1970]
            }
        } catch let error as CLError where error.code == .network {
            // 沒網路（或被節流）：下次再查，不記成「查不到」
            return
        } catch {
            if Task.isCancelled { return }
            map[address] = [0, 0, Date().timeIntervalSince1970]
        }
        UserDefaults.standard.set(map, forKey: Self.key)
        version += 1
    }
}

extension MoneyItem {
    /// 一間房子。卡面：地址查得到座標就是衛星空照，不然是最新的一張裝潢照片，都沒有是插畫
    static func realEstate(_ re: RealEstate, coordinate: CLLocationCoordinate2D?, now: Date = Date()) -> MoneyItem {
        var item = MoneyItem(id: re.id, theme: .finHome, seed: seed(re.id),
                             title: re.name.isEmpty ? (re.city.isEmpty ? "房子" : re.city) : re.name,
                             amount: re.currentValue.ntdWanString,
                             category: re.buildingType.rawValue)
        var detail: [String] = []
        if re.buildingType == .apartment {
            let from = re.fromFloor
            let to = max(re.fromFloor, re.toFloor)
            if from > 0 {
                item.badge = to > from ? "\(from)–\(to)F" : "\(from)F"
                detail.append(to > from ? "\(from)–\(to) 樓" : "\(from) 樓")
            }
        } else {
            let floors = re.floors.isEmpty ? re.totalFloors : re.floors.count
            if floors > 0 {
                item.badge = "\(floors) 層"
                detail.append("\(floors) 層")
            }
        }
        if re.pingCount > 0 { detail.append(FinanceItemText.number(re.pingCount, digits: 1) + " 坪") }
        if re.isSold, let d = re.soldDate { detail.append(FinanceItemText.date(d) + " 賣出") }
        item.detail = detail.isEmpty ? nil : detail.joined(separator: "・")
        if re.isSold { item.badge = "已售出" }
        item.dimmed = re.isSold

        if let address = RealEstateGeocoder.address(of: re) {
            item.place = TripPlaceName.parse(address)
        }
        if let c = coordinate {
            item.latitude = c.latitude
            item.longitude = c.longitude
        } else {
            let photos = re.renovationPhotos.filter { !$0.photoFileNames.isEmpty }
            item.photoURL = photos.max { $0.date < $1.date }?.photoURL
        }

        if !re.isSold, re.monthlyRental > 0 {
            item.chips.append(MoneyItemChip(icon: "tag.fill", text: "出租 " + MoneyFormat.short(re.monthlyRental) + "/月",
                                            tone: .good))
        }
        if re.purchasePrice > 0 {
            let r = re.currentValue / re.purchasePrice - 1
            if abs(r) >= 0.005 {
                item.chips.append(MoneyItemChip(icon: r > 0 ? "arrow.up.right" : "arrow.down.right",
                                                text: (r > 0 ? "增值 " : "跌價 ") + FinanceText.signedPercent(r),
                                                tone: MoneyTone.change(r)))
            }
        }

        // 房貸：還在繳的那一段畫一條進度；全部繳完寫「貸款已繳清」
        let left = re.moneyMortgageLeft(at: now)
        if !re.isSold, !re.mortgageItems.isEmpty {
            if left <= 0, re.mortgageItems.allSatisfy({ $0.startDate <= now }) {
                item.chips.insert(MoneyItemChip(icon: "checkmark.seal.fill", text: "貸款已繳清", tone: .good), at: 0)
            } else if let main = re.mortgageItems.filter({ $0.isPayingNow }).max(by: { $0.totalAmount < $1.totalAmount }) {
                let paid = main.elapsedPeriods
                var trailing = "還要 " + MoneyFormat.short(left)
                if let y = re.moneyMortgageEndYear { trailing = "\(String(y)) 繳完・" + trailing }
                item.progress = MoneyItemProgress(fraction: Double(paid) / Double(max(main.totalPeriods, 1)),
                                                  leading: "房貸 已繳 \(paid)／\(main.totalPeriods) 期",
                                                  trailing: trailing)
            }
        }
        return item
    }
}
