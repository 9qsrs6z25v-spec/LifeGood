import Foundation
import CryptoKit

// MARK: - [v25.563] 一套數字：財富（wealth/judge.md §3.13；build/v2/brief.md）
//
// 全 App 跟「錢在哪個帳戶」有關的數字只算這一套：財富頁列表、英雄卡、卡片頁明細、信用卡的要繳／還沒出帳／還能刷、
// 記帳／收入／股票／房屋水電／AI 記帳的扣款選單、轉帳、對存摺（v4 起理財淨資產、小工具；v7 網頁版）。
// 取代以前四份餘額（財富頁 bankBalances、記帳 allBankBalances、股票 allAccountBalances、網頁版）、
// 五份「這個帳戶有哪些幣別」、兩套信用卡期別（U1 C1、C2、C7）。照 HouseFacts／VehicleFacts：純值、build 一次。
//
// 規則（一條一行；sim_v2.py 照這裡一行一行寫過、跑過）：
// • 日子一律以「天」為單位（西曆、手機時區）：某一天的數字＝那天結束時。
// • 存摺上＝（最近一次對存摺的數字）＋（那天之後、今天以前的每一筆）；從沒對過就從 0 全部加起來；以前的沖正照舊當加減。
//   同一天：先算那天的每一筆，對存摺最後（記的是那天結束時）。
// • 每一筆：手動存提款、轉帳兩邊、利息、手續費；記帳一次性支出、一次性收入寫在 bankDeposits 的那筆；
//   直接扣這個帳戶的週期性固定支出、入這個帳戶的月薪（第 k 期＝第一期＋k 個週期一次加，D8；金額照那一期當時，D9）；
//   股票交割與股利（股票自己寫的，日期是 T+2，還沒到的不算）；
//   **信用卡帳單**：每張卡每一期，在繳款截止日從「那一期的扣款帳戶」扣一次帳單金額（v2 一律當自動扣全額；
//   刷卡當天不再扣銀行，D5）。
// • 跳過（被別的算法取代）：連到刷卡支出的、連到週期性固定支出／收入的、連到股票而那檔股票自己有交割帳戶的（v1 W8）。
// • 信用卡一期＝(上次結帳日, 這次結帳日]，結帳日當天刷的算這一期；結帳日 29–31 遇小月取月底；
//   沒填結帳日當 25 日、沒填繳款截止日當 15 日（跟以前的扣款日同一個預設）。截止日：繳款日 ≤ 結帳日 → 下個月；不然同月。
//   要繳＝已經結帳、截止日還沒到的；還沒出帳＝還沒結帳的這一期（刷到今天）；還能刷＝額度 − 要繳 − 還沒出帳（不小於 0）。
// • 換算只有一支：FinanceRates.accountAmount（v1）；查不到匯率的那一格不算進台幣合計（不當 1:1，D14），標「沒有匯率」。
// • 證券戶身上的 bankDeposits 不算進任何合計（D16）；待交割只算銀行帳戶裡、日期還沒到的股票款（同一天買賣相抵）。
//
// [v25.564] v3（build/v3/brief.md §2；sim_v3.py 照這裡寫過、跑過）：
// • 卡費怎麼繳（帳本 cards[].payMode）：自動扣全額＝v2；自動扣最低＝截止日從扣款帳戶扣「帳單 10%」、剩下的算下一期「前期未繳」；
//   自己繳＝你標成已繳那天、從你選的帳戶扣你繳的數字；沒標、過了截止日（隔天起）當作從「通常從」的帳戶繳了全額（assumedPaid，
//   要確認 #2 問一次）；每次問我＝沒標就不當作，過了截止日是逾期（#3）。你說「還沒繳」（notPaid）也是逾期。
//   改版前（帳本 trackFrom 以前截止）的帳單一律當作繳了。你輸入了帳單上的數字（statedAmount）就用它（不再加前期未繳）。
//   只繳一部分：剩下的算進下一期「前期未繳」（下一期還沒有刷卡也會長出一期）。逾期的那筆在明天的「接下來」裡從扣款帳戶扣。
// • 長按〔算到下一期〕的刷卡（cards[].nextPeriodEntries）算到下一期。
// • 定期扣款、月薪改卡改帳戶有歷史（帳本 linkFrom，跟 payFrom 同一招）：每一期照那一期那天的卡或帳戶；以前的不動。
// • 月薪的金額歷史以帳本 incomeHistory 為準（Income.amountHistory 是給還沒更新的版本的）。
// • 要確認 #4「這筆不算」（帳本 excludedExpenses）：那筆記帳不扣任何帳戶。
// • 還沒扣＝卡費（要繳＋還沒出帳）＋待交割＋已經排定、還沒到的提款（刪卡寫回的那幾期、你記的未來提款、標成已繳但日子還沒到的卡費，scheduledOut）。
// • 接下來 30 天最低、第一次不夠扣（shortage）：從今天的數字開始，30 天內（含）每一筆。
// • 要確認（checks）全部在這裡產生，字和按鈕組好；按過「知道了」的 key 記在帳本 dismissed（key 帶事件，下個月同樣的事會再出現）。
//
// [v25.565] v4（build/v4/brief.md §2；sim_v4.py 照這裡寫過、跑過）：
// • 每張卡接下來要繳的幾期（Card.dues）：已結帳還沒繳的（帳單金額；自動扣最低＝最低應繳）、這一期（到今天刷的＋結帳日前還會扣的
//   定期扣款，約）、下一期（只有定期扣款，約；0 不列）。理財「接下來 30 天」、小工具「接下來要繳」、我的行事曆、通知都讀這一份；
//   刷卡的定期扣款（Netflix 刷 CUBE）併進那一期卡費（recurringNames），不再另外一列（待決定 4）。
// • 接下來的交割（settlements）：每個帳戶每天每幣別買賣相抵；買＝從帳戶扣、賣＝入帳。
// • 理財每月淨資產回推（history，口徑 4）：某一天結束時的存款合計（照帳戶紀錄；有對過存摺的帳戶，第一次對存摺以前平推那個數，
//   沒對過的帳戶第一筆以前平推第一天的數，都標估算）、卡費還沒扣（那天已結帳沒繳的帳單＋這一期刷到那天的）、待交割（那天成交、
//   還沒交割的股票款）；匯率一律用今天的。
// • [v25.565 裁定] 賣股票還沒入帳（pendingIncoming）：同一天買賣相抵後要「入」帳、交割日還沒到的股票款（只算算進存款合計的帳戶）。
//   理財淨資產把它算進存款那一類（FinanceSnapshot.pendingIncoming）：成交當天股票市值就少了、錢 T+2 才進存摺，不加會假跌兩天
//  （買的那一邊是待交割擋掉）。財富頁的「存摺上」「還沒扣」「扣完能用」不算它（錢還沒到，不拿來扣）。回推（history）同一套：
//   Settle 留正負號，正的＝待交割、負的＝待入帳。
// • 要確認 #12：卡片效期前 30 天到那個月底（有效期限只取年月；「CUBE 3 月到期，換新卡後記得改 Netflix、Spotify…」）。
//
// [v25.566] v5 定存與外幣（build/v5/brief.md §2；sim_v5.py 照這裡寫過、跑過）：
// • 定存在財富帳本的定存那一包（WealthDepositBook，同步鍵 life_wealth_deposits_v1；WealthBook.swift）。一期一筆；
//   到期本息續存／本金續存的下一期由 WealthDepositChain 算（帳本還沒寫進去也照算，id 固定雜湊，寫進去以後同一個 id）。
// • 每一期的狀態：起存日還沒到＝notStarted（不算）；存著＝active（本金算進存款合計的「定存」）；到期了選「到期再決定」還沒決定
//   ＝waiting（本息算在定存）；到期轉活存、自動續存了、提前解約＝ended。
// • 動到帳戶的那幾筆（明細一列，WealthFacts 算的、不寫成 BankDeposit；舊 iPad 看不到，它的活存照舊含這筆錢，合計不變）：
//   起存那天「從活存轉出」＝這個帳戶 −本金（.timeDeposit）；到期轉活存＝轉進的帳戶 ＋本息（.timeDeposit）；本金續存＝轉進的帳戶
//   ＋利息（.interest）；提前解約＝轉進的帳戶 ＋本金＋實拿利息；本息續存不動任何帳戶。還沒到的在 upcoming（接下來 30 天、最低）。
// • 舊的「定存」種類帳戶（bankAccountType .fixed）：存摺上就是定存的錢（v3 起算進「定存」那一格）。補了利率、到期日以後
//   不另外加本金、不記轉出；到期的利息記進這個帳戶（本息續存）或轉進的帳戶；轉活存＝這個帳戶轉出本息、轉進的帳戶收。
//   沒補的照 v3 算，要確認問一次（可以略過）。
// • 存款合計＝每個帳戶的存摺上＋存著的定存（算進合計的帳戶才算；查不到匯率的不算）。「定存」那一格＝舊定存帳戶＋存著的定存。
// • 利息只是預估：單利、未扣稅；以月計＝本金×年利率×月數÷12，以日計＝×天數÷365；台幣到元、外幣到 0.01（WealthDepositMath）。
// • 要確認 #13：定存 7 天內到期（照到期處理寫一句）、到期再決定已經到期；#14：同一家銀行（名字去空白、臺→台）存摺上＋定存
//   合計超過 300 萬（人民幣不保不算）〔知道了〕一年內不再提；舊的定存帳戶補利率和到期日（問一次，可以略過）。
// • 外幣金額一律寫符號（US$3,200.00；認得的幣別才有，其他照舊「泰銖 1,000.00」）；換匯＝同一個帳戶的兩個幣別互轉（v2 轉帳綁定）。
// • 理財每月回推（history）：存著的定存照起存日到到期日（或解約日）一段一段加回去。
//
// [v25.567] v6 證券名片與保單總表（build/v6/brief.md §2；sim_v6.py 照這裡寫過、跑過）：
// • 保單總表（WealthPolicyFacts，Models/WealthPolicyFacts.swift）在 build 裡建一次放進 policies：財富頁的保障型保單、儲蓄險、
//   車險、房屋險四個來源合成一張，一筆記帳保費只被一張認領；保障型保單連著記帳那一筆時，金額、繳法、下次、從哪扣都讀記帳那筆
//  （記帳改了保單跟著；稅務頁本來就只讀記帳，照算）。build 多三個參數 insurances／vehicles／realEstates（預設空的）。
//   保單總表不碰任何帳戶的數字，也不進淨資產（儲蓄險的價值照舊在理財）。
// • 要確認 #15 保單跟記帳的保費像同一張（〔是同一張，連起來〕Fix.linkPolicy〔不是〕知道了）、舊資料沒寫繳法（保單頁）、
//   一年一約 60 天內到期；#12 卡片效期的 accountIds 多「保費刷這張卡的保單」（保單頁也看得到）。
// • 證券戶（Broker）：要交割（dues：這個證券戶的股票在交割銀行接下來 30 天的每一天每幣別，扣之前、差多少、一句話）；
//   舊交割紀錄（證券戶自己身上 linkedStockId 的 BankDeposit：legacyCount／legacyTotal／legacyIds；照舊不算進任何合計）。
// • 要確認 #16 證券戶身上有舊交割紀錄：〔搬到薪轉〕（Fix.moveSettlements，先給你看會動到哪些）〔留著當紀錄〕（只問一次）。
// • 股票的交割記在哪個帳戶（WealthStockSettle）：帳本 linkFrom[股票]（證券戶改交割銀行選「這幾檔也一起改」時記的，從哪天起）
//   照交割那天找；沒有歷史＝股票現在的交割銀行，再沒有＝證券戶。股票卡、股票表單、記帳改舊股票都經 LifeStore.rewriteStockSettlements 寫。
//
// （工程）build 很重（展開每一期），全 App 只透過 LifeStore.wealthFacts(expense:finance:) 拿快取的那一份
// （key＝里程碑／財富帳本的 revision＋記帳、理財的 modifyID＋匯率＋日期），打字時不重算（U1 P1、P5）。
// 不標 @MainActor（AI 記帳、LifeStore 都會叫）；但字串用到 ntdWanString（NumberFormatter），請在主執行緒叫。

// MARK: - 日曆（西曆、zh_TW、跟著手機的時區；坑 #11）

enum WealthCal {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "zh_TW")
        c.timeZone = TimeZone.autoupdatingCurrent
        return c
    }()

    /// 那天 00:00
    static func day(_ d: Date) -> Date { calendar.startOfDay(for: d) }

    static func addDays(_ n: Int, to d: Date) -> Date {
        calendar.date(byAdding: .day, value: n, to: d) ?? d
    }

    static func addMonths(_ n: Int, to d: Date) -> Date {
        calendar.date(byAdding: .month, value: n, to: d) ?? d
    }

    /// d 那個月的第 dayOfMonth 天 00:00（超過月底取月底）
    static func date(inMonthOf d: Date, day dayOfMonth: Int) -> Date {
        var comps = calendar.dateComponents([.year, .month], from: d)
        comps.day = 1
        let first = calendar.date(from: comps) ?? calendar.startOfDay(for: d)
        let maxDay = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        comps.day = min(max(dayOfMonth, 1), maxDay)
        return calendar.date(from: comps) ?? first
    }

    /// 那個月 1 號 00:00
    static func startOfMonth(_ d: Date) -> Date { date(inMonthOf: d, day: 1) }

    /// 「2026-10」：帳單 key（結帳日那個月）
    static func monthKey(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month], from: d)
        return String(format: "%04ld-%02ld", c.year ?? 0, c.month ?? 0)
    }

    /// 「2026-10-19」：快取 key
    static func dayKey(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04ld-%02ld-%02ld", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 幾月（1–12）
    static func month(_ d: Date) -> Int { calendar.component(.month, from: d) }

    /// 那天之後幾天（day 對 day）
    static func days(from a: Date, to b: Date) -> Int {
        calendar.dateComponents([.day], from: day(a), to: day(b)).day ?? 0
    }
}

// MARK: - 固定 id（D21）

enum WealthIDs {
    /// 虛擬紀錄要 UUID 時用：SHA256 前 16 位元組，每次開 App 都一樣（以前用 Hasher，每次開 App 種子不同）
    static func stable(_ seed: String) -> UUID {
        let digest = SHA256.hash(data: Data(seed.utf8))
        var b = [UInt8](repeating: 0, count: 16)
        var i = 0
        for byte in digest {
            if i >= 16 { break }
            b[i] = byte
            i += 1
        }
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    /// 股票卡寫的「現金股利入帳」那一筆 BankDeposit 的 id。
    /// ⚠️ 照 v25.316 以來 StockDetailView.stableDepositId 的 FNV-1a 一個位元都不能改：舊資料的股利入帳就是這個 id，
    ///    換算法就認不得以前的股利（刪那次配息時刪不到、重寫交割時會被當成交割紀錄清掉）。
    static func dividendDeposit(_ dividendId: UUID) -> UUID {
        let seed = "dividend-\(dividendId.uuidString)"
        var h: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 { h = (h ^ UInt64(byte)) &* 1_099_511_628_211 }
        let lo = h
        let hi = (h >> 32) ^ (h << 17) ^ 0xB3B3_B3B3_B3B3_B3B3
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i]     = UInt8((lo >> (i * 8)) & 0xff) }
        for i in 0..<8 { bytes[i + 8] = UInt8((hi >> (i * 8)) & 0xff) }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// 這檔股票每一次現金股利的入帳 id。股票卡加交易、新增股票頁存檔重寫交割紀錄時，
    /// 用它把股利那幾筆留下來（以前 removeAll { linkedStockId == 股票 } 連股利一起清掉）
    static func dividendDepositIds(of stock: Stock) -> Set<UUID> {
        var out = Set<UUID>()
        for d in stock.dividends where d.kind == .cash {
            out.insert(dividendDeposit(d.id))
        }
        return out
    }
}

// MARK: - 金額的字（不用 NumberFormatter：哪個執行緒叫都可以）

enum WealthFormat {
    /// 128400 →「128,400」；decimals 2 →「3,200.00」；負數前面一個「-」
    static func grouped(_ v: Double, decimals: Int) -> String {
        let scale: Double = decimals >= 2 ? 100 : 1
        let r = (Swift.abs(v) * scale).rounded()
        guard r.isFinite, r < 9e17 else { return String(format: "%.0f", v) }
        let n = Int64(r)
        let unit = Int64(scale)
        let whole = n / unit
        let frac = n % unit
        let digits = String(whole)
        var rev = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { rev.append(",") }
            rev.append(ch)
        }
        var s = String(rev.reversed())
        if decimals >= 2 {
            s += frac < 10 ? ".0\(frac)" : ".\(frac)"
        }
        return (v < 0 && n != 0) ? "-" + s : s
    }

    /// 「NT$128,400」「-NT$3,200」（寫到元，對存摺、對帳單用）
    static func ntd(_ v: Double) -> String {
        let r = v.rounded()
        let body = "NT$" + grouped(Swift.abs(r), decimals: 0)
        return r < 0 ? "-" + body : body
    }

    /// 台幣「NT$128,400」；外幣「US$3,200.00」（外幣照實寫兩位小數；[v25.566] 認得的幣別寫符號，其他「泰銖 1,000.00」）
    static func money(_ v: Double, code: String) -> String {
        if FinanceRates.isNTD(code) { return ntd(v) }
        let body = foreignPrefix(code) + grouped(Swift.abs(v), decimals: 2)
        return v < 0 && (Swift.abs(v) * 100).rounded() != 0 ? "-" + body : body
    }

    /// [v25.566] 外幣的符號（設定裡的代碼「美金」「USD」都認得；judge §3.8「US$3,200.00」）；認不得＝nil
    static func currencySymbol(_ code: String) -> String? {
        guard let iso = FXRateService.isoCode(for: code) else { return nil }
        switch iso {
        case "USD": return "US$"
        case "EUR": return "€"
        case "JPY": return "JP¥"
        case "GBP": return "£"
        case "CNY": return "CN¥"
        case "HKD": return "HK$"
        case "AUD": return "A$"
        case "CAD": return "C$"
        case "SGD": return "S$"
        case "NZD": return "NZ$"
        case "KRW": return "₩"
        default: return nil
        }
    }

    /// [v25.566] 外幣金額前面那一段：認得的「US$」（直接接數字）；認不得「泰銖 」（代碼＋空白，跟以前一樣）
    static func foreignPrefix(_ code: String) -> String {
        currencySymbol(code) ?? (code + " ")
    }

    /// [v25.566] 「2026/3/15」（進度條兩端、隔年的到期日）
    static func ymd(_ d: Date) -> String {
        let c = WealthCal.calendar.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// [v25.566] 匯率那一段：「10/19 匯率 32.0」；沒有更新時間「匯率 32.0」（rateDate＝AppQuoteClock.ratesUpdatedAt）
    static func rateNote(_ r: Double, rateDate: Date?) -> String {
        if let d = rateDate { return monthDay(d) + " 匯率 " + rate(r) }
        return "匯率 " + rate(r)
    }

    /// [v25.566] 外幣一格（judge §8 v5 做好 3）：「US$3,200.00・約 NT$102,400（10/19 匯率 32.0）」；
    /// 查不到匯率「US$3,200.00・沒有匯率」。rate：設定裡的匯率（FinanceRates.known）
    static func fxLine(_ v: Double, code: String, rate r: Double?, rateDate: Date?) -> String {
        money(v, code: code) + "・" + fxNote(v, rate: r, rateDate: rateDate)
    }

    /// [v25.566] 外幣一格的後半（卡片頁 ⑤ 那一格的小字、外幣帳戶看板那一句、項目卡第二行）：
    /// 「約 NT$102,400（10/19 匯率 32.0）」；查不到匯率「沒有匯率」
    static func fxNote(_ v: Double, rate r: Double?, rateDate: Date?) -> String {
        guard let r else { return "沒有匯率" }
        return "約 " + ntd(v * r) + "（" + rateNote(r, rateDate: rateDate) + "）"
    }

    /// [v25.567] 「10/21（三）」（證券戶要交割那一句）
    static func monthDayWeek(_ d: Date) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let w = WealthCal.calendar.component(.weekday, from: d)
        let name = (w >= 1 && w <= 7) ? names[w - 1] : ""
        return monthDay(d) + "（" + name + "）"
    }

    /// 「10/27」
    static func monthDay(_ d: Date) -> String {
        let c = WealthCal.calendar.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    /// 0.083 →「8.3%」
    static func percent(_ ratio: Double) -> String {
        String(format: "%.1f%%", ratio * 100)
    }

    /// [v25.564] 遮住（財富頁右上眼睛）時金額一律寫這個；%、日期、件數照常
    static let masked = "NT$ ••••"

    /// [v25.564] 句子裡的金額（台幣不寫 NT$）：「128,400」「-3,200」；外幣「US$3,200.00」（[v25.566] 符號同 money）
    static func plain(_ v: Double, code: String) -> String {
        if FinanceRates.isNTD(code) { return grouped(v.rounded(), decimals: 0) }
        return foreignPrefix(code) + grouped(v, decimals: 2)
    }

    /// [v25.564] 匯率「32.0」「32.05」（至少一位小數、最多四位、去尾 0）
    static func rate(_ r: Double) -> String {
        var s = String(format: "%.4f", r)
        while s.hasSuffix("0") && !s.hasSuffix(".0") { s.removeLast() }
        return s
    }
}

// MARK: - [v25.564] 遮住（財富頁右上的眼睛；judge §3.12、§7.2-3）

/// 記在這台裝置（@AppStorage(WealthMask.storageKey)，不同步）；財富頁、卡片頁同一顆。跟小工具的「隱藏金額」各自一顆。
/// 遮住時金額一律 WealthFormat.masked（%、日期、件數照常）；關掉遮住要 Face ID（手機借人時別人按不開）
enum WealthMask {
    static let storageKey = "wealth_masked"

    /// 關掉遮住前問一次 Face ID／Touch ID／密碼；通過＝true。裝置沒設密碼（unavailable）本來就擋不住，直接放行
    @MainActor
    static func confirmUnmask() async -> Bool {
        switch await CardVault.unlock(reason: "顯示財富頁的金額") {
        case .ok: return true
        case .denied: return false
        case .unavailable: return true
        }
    }
}

// MARK: - 期數一次算、金額照當時（D8、D9）

enum WealthSchedule {
    /// 固定支出第 k 期（從 0 起）的扣款日：第一期＋k 個週期，一次加（月底取月底；同 Expense.nextFixedDueDate）。
    /// 貸款的第一期是起始日的下一個週期（撥款日 3/5 → 第一期 4/5）。
    static func fixedDue(_ exp: Expense, _ k: Int) -> Date? {
        guard let rec = exp.recurrence else { return nil }
        let (component, step) = rec.componentValue
        let cal = WealthCal.calendar
        let first: Date = exp.fixedCategory == .loan
            ? (cal.date(byAdding: component, value: step, to: exp.date) ?? exp.date)
            : exp.date
        return cal.date(byAdding: component, value: step * k, to: first)
    }

    /// 固定支出到 until 那天（含）為止的每一期；結束日當期照算（同 Expense.fixedPeriodCount）。最多 1200 期
    static func fixedPeriods(_ exp: Expense, through until: Date) -> [(index: Int, date: Date)] {
        guard exp.expenseType == .fixed, exp.recurrence != nil else { return [] }
        let limit = WealthCal.day(until)
        let end: Date? = exp.endDate.map { WealthCal.day($0) }
        var out: [(index: Int, date: Date)] = []
        var k = 0
        while k < 1200 {
            guard let due = fixedDue(exp, k) else { break }
            let d = WealthCal.day(due)
            if d > limit { break }
            if let e = end, d > e { break }
            out.append((index: k, date: due))
            k += 1
        }
        return out
    }

    /// 週期性收入（每月／每年）到 until 那天（含）為止的每一期：第 k 期＝起始日＋k 個週期一次加；
    /// 有結束日的照 Income.isActive(in:)（結束那個月含）。單次收入回空的。最多 1200 期
    static func incomePeriods(_ inc: Income, through until: Date) -> [(index: Int, date: Date)] {
        let component: Calendar.Component
        switch inc.period {
        case .once: return []
        case .monthly: component = .month
        case .yearly: component = .year
        }
        let cal = WealthCal.calendar
        let limit = WealthCal.day(until)
        var out: [(index: Int, date: Date)] = []
        var k = 0
        while k < 1200 {
            guard let due = cal.date(byAdding: component, value: k, to: inc.date) else { break }
            if WealthCal.day(due) > limit { break }
            if !inc.isActive(in: due, calendar: cal) { break }
            out.append((index: k, date: due))
            k += 1
        }
        return out
    }

    /// 那一期的金額（D9）：history（已照日期排好）裡「那一期那天（含）以前最後一筆」；
    /// 找到的是最新一筆就用現在的金額（記帳表單直接改金額、沒補紀錄的，最新那一段跟著現在）；
    /// 那一期比第一筆還早用第一筆；沒有紀錄＝現在的金額
    static func amount(at date: Date, current: Double, sortedHistory h: [AmountSnapshot]) -> Double {
        guard !h.isEmpty else { return current }
        let d = WealthCal.day(date)
        var found: Int? = nil
        for (i, s) in h.enumerated() where WealthCal.day(s.date) <= d { found = i }
        guard let i = found else { return h[0].amount }
        return i == h.count - 1 ? current : h[i].amount
    }

    /// 支出一筆（或一期）的台幣值：只有外幣儲蓄險是原幣存的（同 ExpenseStore.ntdValue(of:)）
    static func ntd(of exp: Expense, raw: Double, rates: FinanceRates) -> Double {
        guard let o = exp.originalCurrencyAmount else { return raw }
        return raw * rates.rate(o.code)
    }
}

// MARK: - 信用卡的期別（全 App 只有這一份；v1 的 CreditCardCycle 搬過來）

enum WealthCardCycle {
    static let defaultBillingDay = 25
    static let defaultPaymentDay = 15

    /// 實際拿來算的結帳日（沒填 25；舊資料打錯的 0、45 夾到 1–31）
    static func billingDay(_ raw: Int?) -> Int { min(max(raw ?? defaultBillingDay, 1), 31) }
    /// 實際拿來算的繳款截止日（沒填 15）
    static func paymentDay(_ raw: Int?) -> Int { min(max(raw ?? defaultPaymentDay, 1), 31) }

    /// d 那個月的結帳日（00:00；超過月底取月底）
    static func closeDate(inMonthOf d: Date, billingDay b: Int) -> Date {
        WealthCal.date(inMonthOf: d, day: b)
    }

    /// 這天刷的算哪一期：那一期的結帳日。一期＝(上次結帳日, 這次結帳日]，結帳日當天刷的算這一期
    static func statementClose(for d: Date, billingDay b: Int) -> Date {
        let dd = WealthCal.day(d)
        let thisMonth = closeDate(inMonthOf: dd, billingDay: b)
        if dd <= thisMonth { return thisMonth }
        return closeDate(inMonthOf: WealthCal.addMonths(1, to: WealthCal.startOfMonth(dd)), billingDay: b)
    }

    /// close 的前一次結帳日
    static func previousClose(_ close: Date, billingDay b: Int) -> Date {
        closeDate(inMonthOf: WealthCal.addMonths(-1, to: WealthCal.startOfMonth(close)), billingDay: b)
    }

    /// [v25.564] close 的下一次結帳日（〔算到下一期〕、前期未繳長出來的那一期）
    static func nextClose(after close: Date, billingDay b: Int) -> Date {
        closeDate(inMonthOf: WealthCal.addMonths(1, to: WealthCal.startOfMonth(close)), billingDay: b)
    }

    /// 結帳日 close 那一期的繳款截止日：繳款日 ≤ 結帳日 → 下個月；不然同一個月（同 LifeMilestone.creditCardWithdrawalDate）
    static func dueDate(close: Date, billingDay b: Int, paymentDay p: Int) -> Date {
        let monthStart = WealthCal.startOfMonth(close)
        let month = p <= b ? WealthCal.addMonths(1, to: monthStart) : monthStart
        return WealthCal.date(inMonthOf: month, day: p)
    }

    /// 「10 月帳單」（結帳日那個月）
    static func label(close: Date) -> String { "\(WealthCal.month(close)) 月帳單" }

    /// 改扣款帳戶時的「下一期」：明天起刷的那一期（結帳日當天改，今天這期照舊從原本的帳戶扣）
    static func nextStatement(billingDay raw: Int?, now: Date) -> (key: String, label: String) {
        let close = statementClose(for: WealthCal.addDays(1, to: WealthCal.day(now)), billingDay: billingDay(raw))
        return (WealthCal.monthKey(close), label(close: close))
    }

    /// 這一期（帳單 key）從哪個帳戶扣（D10）：沒有歷史＝卡現在的扣款帳戶；
    /// 有歷史找「fromKey ≤ 這一期」的最後一段，那一段是最新的一段就用卡現在的 linkedBankMilestoneId
    /// （還沒更新的 iPad 改了扣款帳戶，新的那一段也跟得上）；比第一段還早用第一段的帳戶
    static func payer(statementKey key: String, linked: UUID?, history: [WealthPayFrom]?) -> UUID? {
        let h = (history ?? []).sorted { $0.fromKey < $1.fromKey }
        guard !h.isEmpty else { return linked }
        var found: Int? = nil
        for (i, e) in h.enumerated() where e.fromKey <= key { found = i }
        guard let idx = found else { return h[0].accountId }
        return idx == h.count - 1 ? linked : h[idx].accountId
    }
}

/// 一筆刷卡（定期扣款每一期一筆），金額台幣
struct WealthCardEntry: Identifiable {
    let id: String
    let date: Date
    let amount: Double
    let expenseId: UUID
    /// 定期扣款展開出來的那一期（不是第一期）
    let isRecurring: Bool
}

/// [v25.564] 一期帳單的狀態（WealthFacts.statements 一次判定；畫面照它寫字）
enum WealthStatementStatus: Equatable {
    /// 還沒結帳（這一期刷到今天；結帳日當天也是）
    case unbilled
    /// 已經結帳、截止日還沒過（自己繳的卡截止日當天也還是這個）
    case due
    /// 過了截止日還沒繳（每次問我沒標、你說還沒繳）：要繳裡算它、明天從扣款帳戶扣（接下來）
    case overdue
    /// 已繳（自動扣、你標的、改版前的）
    case paid
    /// 自己繳的卡過了截止日、你沒標：當作從「通常從」的帳戶繳了全額（隔天要確認問一次）
    case assumedPaid
}

/// 一期帳單
struct WealthStatement: Identifiable {
    /// 「2026-10」（結帳日那個月；西曆）
    let key: String
    /// 這一期第一天（上次結帳日隔天）
    let start: Date
    /// 結帳日
    let close: Date
    /// 繳款截止日
    let due: Date
    /// 帳單金額（台幣）：你輸入了帳單上的數字就用它；不然＝App 算的＋前期未繳
    let amount: Double
    /// 幾筆
    let count: Int
    /// 這一期從哪個帳戶扣（D10；帳戶不在了是 nil）
    let payerId: UUID?
    /// 結帳日已經過了（結帳日當天還沒出帳）
    let isClosed: Bool
    /// 已繳（status 是 paid 或 assumedPaid）
    let isPaid: Bool
    /// [v25.564] App 算的（這一期刷的合計，不含前期未繳）
    let computedAmount: Double
    /// [v25.564] 你輸入的帳單金額（〔帳單金額不一樣〕）
    let statedAmount: Double?
    /// [v25.564] 前期未繳（上一期只繳一部分、自動扣最低剩下的）
    let carriedIn: Double
    let status: WealthStatementStatus
    /// [v25.564] 已繳、當作已繳：從銀行扣的那天、帳戶（nil＝別的方式：現金、超商，或沒設扣款帳戶）、金額
    let paidOn: Date?
    let paidFrom: UUID?
    let paidAmount: Double
    /// [v25.564] 你標的已繳（可以〔取消已繳〕、〔改一下〕）
    let isExplicitPaid: Bool
    /// [v25.564] 你說還沒繳
    let notPaid: Bool

    var id: String { key }
    /// 「10 月帳單」
    var label: String { WealthCardCycle.label(close: close) }
    var isOverdue: Bool { status == .overdue }
    /// [v25.564] 最低應繳（估算，judge §3.13 C-8）：帳單的 10%、四捨五入到元；畫面寫「約…（以帳單為準）」
    var minimumDue: Double { (amount * 0.1).rounded() }
    /// [v25.564] 只繳一部分剩下的（算進下一期「前期未繳」）
    var unpaidRemainder: Double { isPaid ? Swift.max(0, amount - paidAmount) : 0 }
    /// [v25.564] 你改過帳單金額：App 算的跟你輸入的差多少（帳單 − App；沒改＝nil）
    var statedDiff: Double? { statedAmount.map { $0 - (computedAmount + carriedIn) } }
}

// MARK: - 明細一列（今天以前的、接下來 35 天的）

struct WealthLedgerRow: Identifiable {
    enum Kind {
        case deposit, withdrawal, interest, fee
        case transferOut, transferIn
        /// 對存摺（存摺上的數字）
        case anchor
        /// 以前的沖正（照舊當加減）
        case legacyAdjust
        /// 記帳一次性支出／收入寫在帳戶裡的那筆
        case expense, income
        /// 直接扣這個帳戶的週期性固定支出、入這個帳戶的月薪（展開的每一期）
        case fixedExpense, recurringIncome
        /// 信用卡一期帳單
        case cardBill
        /// 股票交割、股利（股票自己寫的）
        case stockBuy, stockSell, dividend
        /// [v25.566] 定存：起存那天從活存轉出、到期轉活存、提前解約轉回（WealthFacts 算的，timeDepositId＝那一期）
        case timeDeposit

        /// 徽章（D16：證券寫「買入」「賣出」，不再寫「賣出獲利」）
        var badge: String {
            switch self {
            case .deposit: return "存款"
            case .withdrawal: return "提款"
            case .interest: return "利息"
            case .fee: return "手續費"
            case .transferOut: return "轉出"
            case .transferIn: return "轉入"
            case .anchor: return "對存摺"
            case .legacyAdjust: return "沖正"
            case .expense: return "扣款"
            case .income: return "收入"
            case .fixedExpense: return "固定扣款"
            case .recurringIncome: return "入帳"
            case .cardBill: return "卡費"
            case .stockBuy: return "買入"
            case .stockSell: return "賣出"
            case .dividend: return "股利"
            case .timeDeposit: return "定存"
            }
        }
    }

    /// 真的紀錄＝BankDeposit.id.uuidString；固定支出「fx-<支出>-<k>」；月薪「in-<收入>-<k>」；卡費「bill-<卡>-<2026-10>」
    let id: String
    let date: Date
    /// 幣別（台幣一律 "NT$"）
    let code: String
    /// 金額（正的）；對存摺＝存摺上的數字
    let amount: Double
    /// 錢出去（對存摺看 anchorDiff）
    let isOutflow: Bool
    let kind: Kind
    /// 「@GoGo 9 月帳單」「中華電信」「轉給 國泰世華」「買 0050」「對存摺」
    let title: String
    let note: String?
    /// 這一列之後、這個幣別的存摺上
    var balanceAfter: Double
    /// 對存摺：跟 App 算的差多少（存摺上 − App 算的）
    var anchorDiff: Double?
    /// 真的紀錄（點了可以編輯／刪除）
    let depositId: UUID?
    let expenseId: UUID?
    let incomeId: UUID?
    let stockId: UUID?
    let cardId: UUID?
    let statementKey: String?
    let transferPairId: UUID?
    /// 還沒結帳的那一期卡費（接下來 35 天裡、金額會再變）；[v25.566] 還沒到的定存利息（預估）
    let isEstimate: Bool
    /// [v25.566] 定存那幾列（轉定存、定存到期、定存利息、解約）：那一期定存的 id（點了開定存表單）
    let timeDepositId: UUID?

    init(id: String, date: Date, code: String, amount: Double, isOutflow: Bool, kind: Kind,
         title: String, note: String? = nil, balanceAfter: Double = 0, anchorDiff: Double? = nil,
         depositId: UUID? = nil, expenseId: UUID? = nil, incomeId: UUID? = nil, stockId: UUID? = nil,
         cardId: UUID? = nil, statementKey: String? = nil, transferPairId: UUID? = nil,
         isEstimate: Bool = false, timeDepositId: UUID? = nil) {
        self.id = id
        self.date = date
        self.code = code
        self.amount = amount
        self.isOutflow = isOutflow
        self.kind = kind
        self.title = title
        self.note = note
        self.balanceAfter = balanceAfter
        self.anchorDiff = anchorDiff
        self.depositId = depositId
        self.expenseId = expenseId
        self.incomeId = incomeId
        self.stockId = stockId
        self.cardId = cardId
        self.statementKey = statementKey
        self.transferPairId = transferPairId
        self.isEstimate = isEstimate
        self.timeDepositId = timeDepositId
    }

    /// 「+NT$80,000」「-美金 10.00」；對存摺「NT$74,199」
    var amountText: String {
        if kind == .anchor { return WealthFormat.money(amount, code: code) }
        return (isOutflow ? "-" : "+") + WealthFormat.money(amount, code: code)
    }

    /// 「餘額 128,400」（底下小字；跟存摺一樣一列一列對得上）
    var balanceText: String { "餘額 " + WealthFormat.money(balanceAfter, code: code) }
}

/// [v25.564] 要確認的一條（judge §3.5；#11「存了安全碼」照使用者第 6 題「我要存」整條不做）。
/// 字和按鈕在這裡組好，畫面只畫（照 VehicleCheck）。id 也是「知道了」記在帳本 dismissed 的 key（帶事件：下個月同樣的事 key 不一樣）
struct WealthCheck: Identifiable {
    /// 宣告順序＝同一種語氣裡的先後
    enum Kind: String, CaseIterable {
        // bad：不夠扣、過期、負的
        case shortage, cardOverdue, askPaid, negative
        // warn
        case assumedPaid, cardFeeExpense, disabledRecurring, noPayer, legacyFX, unknownRate
        // [v25.565] warn：卡片效期前 30 天（#12）
        case cardExpiring
        // [v25.567] warn：證券戶身上有舊交割紀錄（#16）、一年一約保單 60 天內到期
        case legacySettlement, policyRenewal
        // [v25.566] warn：定存 7 天內到期、到期再決定已經到期（#13）
        case depositMaturing
        // [v25.566] info：舊的定存帳戶補利率和到期日、同一家銀行超過 300 萬（#14）
        case depositInfoMissing, depositInsurance
        // [v25.567] info：保單跟記帳的保費像同一張（#15）、舊資料的保單沒寫繳法（保單頁）
        case policyMatch, policyCycle
        // info
        case cardDaysMissing, staleAnchor

        var order: Int { Kind.allCases.firstIndex(of: self) ?? 0 }
    }
    enum Tone: Int {
        case bad = 0, warn = 1, info = 2
    }
    /// 按了做什麼（畫面照這個開表單或叫 LifeStore；不在背景偷偷改，都是你按了才改）
    enum Fix: Equatable {
        /// 〔知道了〕〔不用改〕〔它不是卡費〕：記進帳本 dismissed（LifeStore.dismissWealthCheck）
        case dismiss
        /// 〔轉帳過去〕：開轉帳小表單（轉出預設存摺上最多的另一個台幣活存，金額預填差額）
        case transfer(to: UUID, from: UUID?, amount: Double)
        /// 〔對〕：照 App 當作的寫成你標的已繳（LifeStore.markStatementPaid）
        case confirmPaid(cardId: UUID, key: String, on: Date, from: UUID?)
        /// 〔不是，改一下〕〔繳了〕〔標成已繳〕：開「標成已繳」小表單（那一期）
        case editPaid(cardId: UUID, key: String)
        /// 〔還沒〕：記成還沒繳（LifeStore.markStatementNotPaid）→ 逾期
        case markNotPaid(cardId: UUID, key: String)
        /// 〔這筆不算〕：那筆記帳不扣帳戶（LifeStore.excludeExpenseFromWealth）
        case excludeExpense(UUID)
        /// 〔改刷別張〕：開「一次改到別張卡」小表單（這幾筆）
        case moveRecurring(cardId: UUID, expenseIds: [UUID])
        /// 〔已經退訂〕：這幾筆定期扣款在那天結束（先確認，LifeStore.endRecurring）
        case endRecurring(expenseIds: [UUID], on: Date)
        /// 〔填日子〕〔選帳戶〕：開那個帳戶／卡的編輯表單
        case editAccount(UUID)
        /// 〔改過來〕：舊版記錯的外幣扣款改成換算後的數字（先確認，LifeStore.fixLegacyFX）
        case fixLegacyFX(accountId: UUID, depositId: UUID, amount: Double)
        /// 〔去設定〕：設定裡的匯率
        case openRates
        /// 〔對存摺〕：開對存摺小表單（那個幣別）
        case anchor(accountId: UUID, code: String)
        /// [v25.565] 打開那張卡的卡片頁、捲到「綁在這張卡的定期扣款」（#12〔看綁了哪些〕）
        case openCard(UUID)
        /// [v25.566] 定存到期怎麼處理（#13〔改成轉活存〕〔改成本息續存〕、到期再決定〔轉活存〕〔本息續存〕）：
        /// LifeStore.setTimeDepositOnMaturity（mode＝WealthMaturityMode.rawValue；自動續存還沒寫進帳本的那一期先寫進去再改）
        case setMaturity(depositId: UUID, mode: String)
        /// [v25.566] 打開定存表單（舊的定存帳戶〔補資料〕：depositId nil、帶這個帳戶與存摺上的數字）
        case editTimeDeposit(accountId: UUID, depositId: UUID?)
        /// [v25.566] #14 存款保險〔知道了〕：這家銀行一年內不再提（LifeStore.quietDepositInsurance；銀行 key）
        case quietInsurance(String)
        /// [v25.567] #15〔是同一張，連起來〕：保單連到記帳的這一筆保費（LifeStore.linkPolicy；不擋訂閱，跟〔對〕一樣是確認）
        case linkPolicy(policyId: UUID, expenseId: UUID)
        /// [v25.567] 保單頁〔年繳〕：舊資料沒寫繳法（LifeStore.setPolicyCycle；cycle＝WealthPolicyCycle.rawValue）
        case setPolicyCycle(policyId: UUID, cycle: String)
        /// [v25.567] #16〔搬到薪轉〕：先開「會動到哪些」（WealthSettlementMoveSheet），你按確定才搬（不擋訂閱：修資料，同〔改過來〕）
        case moveSettlements(brokerId: UUID)
    }
    struct Action: Identifiable, Equatable {
        let title: String
        let fix: Fix
        var id: String { title }
    }

    let id: String
    let kind: Kind
    let tone: Tone
    let text: String
    /// 1～2 顆
    let actions: [Action]
    /// 跟哪些帳戶、卡有關（卡片頁的「要確認」只列自己的）
    let accountIds: [UUID]
    /// false：只在帳戶頁出現（很久沒對存摺：不催）
    var onPage: Bool = true

    /// SF Symbol（iOS 18 都有）
    var icon: String {
        switch kind {
        case .shortage: return "exclamationmark.triangle.fill"
        case .cardOverdue, .askPaid: return "exclamationmark.circle.fill"
        case .negative: return "minus.circle.fill"
        case .assumedPaid: return "questionmark.circle.fill"
        case .cardFeeExpense: return "doc.on.doc.fill"
        case .disabledRecurring: return "creditcard.fill"
        case .noPayer: return "building.columns.fill"
        case .legacyFX: return "arrow.triangle.2.circlepath"
        case .unknownRate: return "dollarsign.circle.fill"
        case .cardExpiring: return "calendar.badge.exclamationmark"
        case .depositMaturing: return "lock.open.fill"
        case .depositInfoMissing: return "lock.fill"
        case .depositInsurance: return "shield.lefthalf.filled"
        case .legacySettlement: return "arrow.left.arrow.right.circle.fill"
        case .policyRenewal: return "calendar.badge.clock"
        case .policyMatch: return "link.circle.fill"
        case .policyCycle: return "questionmark.circle.fill"
        case .cardDaysMissing: return "calendar"
        case .staleAnchor: return "checkmark.seal.fill"
        }
    }

    /// VoiceOver：「轉帳過去：10/21 薪轉要扣…」
    var accessibilityLabel: String { (actions.first?.title ?? "") + "：" + text }
}

/// [v25.564] 接下來 30 天第一次不夠扣（judge §3.5 #1、§4.2 ③）
struct WealthShortage: Equatable {
    /// 那天
    let date: Date
    /// 幣別（台幣 "NT$"）
    let code: String
    /// 是哪一筆（「買 00878」「CUBE 10 月帳單」）
    let title: String
    let kind: WealthLedgerRow.Kind
    /// 那一筆扣多少、扣之前剩多少、差多少（都是正的）
    let amount: Double
    let before: Double
    let short: Double
}

// MARK: - [v25.565] v4：接下來要繳的卡費、交割、理財每月回推（judge §6.4–6.6；sim_v4.py）

/// 一張卡接下來要繳的一期（理財「接下來 30 天」、小工具「接下來要繳」、我的行事曆、今天小工具、通知都讀這一份）
struct WealthCardDue: Identifiable {
    let cardId: UUID
    /// 卡的名字（暱稱 → 卡名）：「CUBE」
    let cardName: String
    /// 帳單 key「2026-10」（結帳日那個月）
    let key: String
    let close: Date
    /// 繳款截止日（自動扣＝扣款那天）
    let due: Date
    /// 這一期會從銀行扣多少（台幣）：已結帳＝帳單（自動扣最低＝最低應繳）；還沒結帳＝到今天刷的＋結帳日前還會扣的定期扣款
    let amount: Double
    /// 還沒結帳（金額會再變，寫「約」）
    let isEstimate: Bool
    /// .due／.overdue（已結帳）或 .unbilled
    let status: WealthStatementStatus
    let payMode: WealthPayMode
    /// 這一期從哪個帳戶扣（沒設 nil）
    let payerId: UUID?
    let payerName: String?
    /// 這一期裡刷這張卡的定期扣款（照日期、不重複）：「Spotify」「Netflix」
    let recurringNames: [String]
    let recurringIds: [UUID]

    var id: String { cardId.uuidString + "-" + key }
    /// 自己繳／每次問我（行事曆畫橘色、截止前 3 天與當天提醒）
    var isManual: Bool { !payMode.isAuto }

    /// 「自己繳」「薪轉自動扣」「薪轉自動扣最低」「過了截止日」
    var modeText: String {
        if status == .overdue { return "過了截止日" }
        switch payMode {
        case .autoFull: return payerName.map { $0 + "自動扣" } ?? "自動扣"
        case .autoMin: return payerName.map { $0 + "自動扣最低" } ?? "自動扣最低"
        case .manual, .askEachTime: return "自己繳"
        }
    }

    /// 「含 Netflix」「含 Spotify、Netflix」「含 Spotify、Netflix 等 3 筆」；沒有 nil
    var recurringText: String? {
        let n = recurringNames
        if n.isEmpty { return nil }
        if n.count == 1 { return "含 " + n[0] }
        if n.count == 2 { return "含 " + n[0] + "、" + n[1] }
        return "含 " + n[0] + "、" + n[1] + " 等 \(n.count) 筆"
    }

    /// 「NT$18,600」；還沒結帳「約 NT$6,739」
    var amountText: String { (isEstimate ? "約 " : "") + WealthFormat.ntd(amount) }
}

/// 接下來的一筆交割（同一個帳戶、同一天、同一個幣別的買賣相抵）
struct WealthSettlementDue: Identifiable {
    /// 交割銀行帳戶
    let accountId: UUID
    let accountName: String
    /// 證券戶名（第一檔股票選的證券戶）：「元大證券」；沒選 nil
    let brokerName: String?
    let day: Date
    let code: String
    /// 原幣、正的
    let amount: Double
    /// 台幣（查不到匯率 nil）
    let ntd: Double?
    /// 買＝從帳戶扣；賣＝入帳
    let isOutflow: Bool
    let stockIds: [UUID]

    var id: String { accountId.uuidString + "-" + WealthCal.dayKey(day) + "-" + code }
    /// 「元大證券 交割」（沒選證券戶「股票 交割」）
    var title: String { (brokerName ?? "股票") + " 交割" }
    /// 「從薪轉扣」「入薪轉」
    var directionText: String { isOutflow ? "從" + accountName + "扣" : "入" + accountName }
    /// 「NT$52,340」「美金 1,200.00」
    var amountText: String { FinanceRates.isNTD(code) ? WealthFormat.ntd(amount) : WealthFormat.money(amount, code: code) }
}

/// [v25.567] 證券戶頁 ② 要交割的一天（judge §4.3 ②；樣稿③-B5）：這個證券戶的股票在交割銀行那一天的買賣相抵
struct WealthBrokerDue: Identifiable {
    /// 交割那天 00:00
    let day: Date
    /// 交割的銀行帳戶
    let accountId: UUID
    let accountName: String
    /// 幣別（台幣 "NT$"）
    let code: String
    /// 金額（正的；買賣相抵後）
    let amount: Double
    /// 從帳戶扣（買的多）；false＝入帳
    let isOutflow: Bool
    /// 「買 00878 2,000 股」「賣 0050 1,000 股」「買 00878、賣 0050」；不知道 nil
    let what: String?
    /// 那天扣之前的存摺上（這個幣別）
    let before: Double
    /// 今天的存摺上（這個幣別）
    let now: Double
    /// 差多少（夠＝0）
    let short: Double
    let stockIds: [UUID]

    var id: String { accountId.uuidString + "-" + WealthCal.dayKey(day) + "-" + code }
    var isShort: Bool { short > 0.5 }

    /// 「10/21（三）早上從薪轉扣 52,340・買 00878 2,000 股」；入帳「10/22（四）入薪轉 30,000・賣 0050 1,000 股」
    var line: String {
        let head: String = WealthFormat.monthDayWeek(day)
        let money: String = WealthFormat.plain(amount, code: code)
        var body: String
        if isOutflow {
            body = head + "早上從" + accountName + "扣 " + money
        } else {
            body = head + "入" + accountName + " " + money
        }
        if let w = what { body += "・" + w }
        return body
    }

    /// 夠：「薪轉現在 128,400，夠」（那天以前還有別的進出：「扣之前薪轉約 128,400，夠」）；
    /// 不夠：「薪轉只剩 40,000，差 12,340，明天 10 點前要轉進去」（兩天以後「10/21（三）10 點前」）；入帳：「錢在那天早上進薪轉」
    func statusLine(today: Date) -> String {
        guard isOutflow else { return "錢在那天早上進" + accountName }
        if isShort {
            let left = WealthCal.days(from: today, to: day)
            // 「今天 10 點前」「明天 10 點前」「10/21（三）10 點前」
            let when: String
            switch left {
            case ...0: when = "今天 "
            case 1: when = "明天 "
            default: when = WealthFormat.monthDayWeek(day)
            }
            let left0: String = WealthFormat.plain(before, code: code)
            let gap: String = WealthFormat.plain(short, code: code)
            // [v25.567 編] 拆兩段（一個運算式 8 個 + 太長，沒編譯環境時少冒險）
            let head: String = accountName + "只剩 " + left0 + "，差 " + gap
            return head + "，" + when + "10 點前要轉進去"
        }
        if Swift.abs(before - now) < 0.5 {
            return accountName + "現在 " + WealthFormat.plain(now, code: code) + "，夠"
        }
        return "扣之前" + accountName + "約 " + WealthFormat.plain(before, code: code) + "，夠"
    }
}

/// [v25.567] 股票的交割記在哪個帳戶（judge §4.3 ⑥「這 3 檔的交割銀行也一起改嗎？以前的交割不動」）
enum WealthStockSettle {
    /// 這檔股票 day 那天的交割記在哪個帳戶：帳本 linkFrom[股票]（證券戶改交割銀行時「這幾檔也一起改」記的，從哪天起）照那天找；
    /// 沒有歷史＝股票現在的交割銀行，再沒有＝證券戶（舊資料：交割記在證券戶身上）。最後一段一律跟著股票現在的交割銀行
    static func account(for stock: Stock, on day: Date, book: WealthBook) -> UUID? {
        let current: UUID? = stock.linkedBankMilestoneId ?? stock.linkedSecuritiesMilestoneId
        return WealthCardCycle.payer(statementKey: WealthCal.dayKey(day), linked: current, history: book.links(stock.id))
    }

    /// 寫進那個帳戶用哪個幣別：股票現在的交割銀行＝它的 linkedBankCurrency；以前的銀行、證券戶＝台幣
    static func currency(for stock: Stock, account: UUID?) -> String {
        if let a = account, a == stock.linkedBankMilestoneId { return stock.linkedBankCurrency ?? "NT$" }
        return "NT$"
    }
}

/// 理財每月淨資產回推（口徑 4）：某一天結束時的數字（台幣；用今天的匯率）
struct WealthMonthEnd: Equatable {
    var cash: Double = 0
    var cardOwed: Double = 0
    var pending: Double = 0
    /// [v25.565 裁定] 賣股票還沒入帳（那天成交、還沒交割、同一天買賣相抵後是入帳的；台幣）
    var incoming: Double = 0
    /// 有帳戶那天還沒開始記（往前平推的）
    var estimated: Bool = false
}

/// 理財每月淨資產回推用的表（WealthFacts.build 建一次；回推每個月只查表；sim_v4.py make_history／history_point）
struct WealthHistory {
    /// 一個帳戶的一個幣別：照日子排好的「那天結束時」存摺上
    fileprivate struct Line {
        let rate: Double
        let days: [Date]
        let values: [Double]
        /// 從這天起照紀錄；以前平推 startValue（有對過存摺＝第一次對存摺那天，沒有＝第一筆那天）
        let startDay: Date
        let startValue: Double
        /// [v25.566 驗證修正] startDay 那天以前（含）App 算的定存那幾列（轉定存、到期轉活存、定存利息、解約；timeDepositId 有值）。
        /// 平推 startValue 時，d 之後的這幾筆要退回去：錢在定存那一段（Span）裡、日子是確定的，跟著平推會跟 Span 重複算或漏算
        ///（例：薪轉 10/1 才第一次對存摺、3/15 從薪轉轉出 50 萬存定存 → 3/15 以前薪轉少平推 50 萬，回推在 3/15 假漲 50 萬；
        /// 美金定存到期轉進只有台幣的帳戶 → 那條美金線第一筆就是到期那一列，到期以前平推成已經有那筆錢）
        let depositSteps: [DepositStep]
    }

    /// [v25.566 驗證修正] 一筆 App 算的定存列：那天、金額（正＝進帳、負＝出去）
    fileprivate struct DepositStep {
        let day: Date
        let delta: Double
    }

    /// 一筆交割（那天、台幣；同一天同一幣別買賣相抵後的淨額）。
    /// [v25.565 裁定] 留正負號：正的＝要扣（待交割）、負的＝要入帳（賣股票還沒入帳）
    fileprivate struct Settle {
        let day: Date
        let ntd: Double
    }

    /// [v25.566] 一段存著的定存（從起存日那天結束時起、到到期日／解約日那天以前；until nil＝一直到現在）
    fileprivate struct Span {
        let from: Date
        let until: Date?
        let ntd: Double
    }

    fileprivate let lines: [Line]
    fileprivate let cards: [WealthFacts.Card]
    fileprivate let settles: [Settle]
    fileprivate let spans: [Span]

    static let empty = WealthHistory(lines: [], cards: [], settles: [], spans: [])

    /// 算進存款合計、沒收起來的銀行帳戶（同 WealthFacts.cash）；卡＝全部的卡（同 owedCards）。
    /// [v25.566] deposits：每一期定存（含已經結束的；續存鏈算出來的也在）——舊的定存種類帳戶的不算（它的錢在存摺上那條線裡）
    static func make(accounts: [WealthFacts.Account], cards: [WealthFacts.Card], deposits: [WealthFacts.TimeDeposit],
                     rates: FinanceRates) -> WealthHistory {
        var lines: [Line] = []
        var settles: [Settle] = []
        var spans: [Span] = []
        var counted = Set<UUID>()
        for a in accounts where !a.isSecurities && !a.hidden && a.countsInCash { counted.insert(a.id) }
        for t in deposits where t.countsSeparately && counted.contains(t.accountId) {
            guard let r = rates.known(t.code) else { continue }
            let from = WealthCal.day(t.start)
            if let c = t.closedDate {
                spans.append(Span(from: from, until: WealthCal.day(c), ntd: t.principal * r))
            } else if let m = t.maturity {
                if t.mode == .decide {
                    // 到期再決定：到期以前算本金，到期以後（還沒決定）照本息
                    spans.append(Span(from: from, until: m, ntd: t.principal * r))
                    spans.append(Span(from: m, until: nil, ntd: t.maturityAmount * r))
                } else {
                    spans.append(Span(from: from, until: m, ntd: t.principal * r))
                }
            } else {
                spans.append(Span(from: from, until: nil, ntd: t.principal * r))
            }
        }
        for a in accounts where !a.isSecurities && !a.hidden && a.countsInCash {
            let rows: [WealthLedgerRow] = Array(a.ledger.reversed())   // 舊到新
            for code in a.currencies {
                guard let r = rates.known(code) else { continue }
                var days: [Date] = []
                var values: [Double] = []
                var firstAnchor: Date? = nil
                for row in rows where row.code == code {
                    let d = WealthCal.day(row.date)
                    if row.kind == .anchor && firstAnchor == nil { firstAnchor = d }
                    if let last = days.last, last == d {
                        values[values.count - 1] = row.balanceAfter
                    } else {
                        days.append(d)
                        values.append(row.balanceAfter)
                    }
                }
                guard let first = days.first else { continue }
                let start: Date = firstAnchor ?? first
                let startValue: Double = days.firstIndex(of: start).map { values[$0] } ?? 0
                // [v25.566 驗證修正] startDay 以前（含）App 算的定存那幾列：平推時 d 之後的退回去（見 Line.depositSteps）
                var steps: [DepositStep] = []
                for row in rows where row.code == code && row.timeDepositId != nil && row.kind != .anchor {
                    let d = WealthCal.day(row.date)
                    guard d <= start else { continue }
                    steps.append(DepositStep(day: d, delta: row.isOutflow ? -row.amount : row.amount))
                }
                lines.append(Line(rate: r, days: days, values: values, startDay: start, startValue: startValue,
                                  depositSteps: steps))
            }
            // 股票款：同一天同一個幣別買賣相抵（[v25.565 裁定] 要扣的、要入帳的都留，正負號分開算）
            var keys: [String] = []
            var net: [String: Double] = [:]
            var dayOf: [String: Date] = [:]
            var codeOf: [String: String] = [:]
            for row in rows + a.upcoming where row.kind == .stockBuy || row.kind == .stockSell {
                let d = WealthCal.day(row.date)
                let k = WealthCal.dayKey(d) + "|" + row.code
                if net[k] == nil {
                    keys.append(k)
                    net[k] = 0
                    dayOf[k] = d
                    codeOf[k] = row.code
                }
                let signed: Double = row.kind == .stockBuy ? row.amount : -row.amount
                net[k, default: 0] += signed
            }
            for k in keys {
                guard let v = net[k], Swift.abs(v) > 0.004, let d = dayOf[k], let code = codeOf[k],
                      let r = rates.known(code) else { continue }
                settles.append(Settle(day: d, ntd: v * r))
            }
        }
        return WealthHistory(lines: lines, cards: cards, settles: settles, spans: spans)
    }

    /// day 那天結束時的存款合計、卡費還沒扣、待交割（[v25.565 裁定] ＋賣股票還沒入帳）
    func point(endOf day: Date) -> WealthMonthEnd {
        let d = WealthCal.day(day)
        var p = WealthMonthEnd()
        for l in lines {
            if d < l.startDay {
                // [v25.566 驗證修正] 平推，但 d 之後才發生的定存那幾列（轉定存、到期轉活存…）退回去
                var v: Double = l.startValue
                for s in l.depositSteps where s.day > d { v -= s.delta }
                p.cash += v * l.rate
                p.estimated = true
                continue
            }
            // 最後一個 <= d 的那天（二分）
            var lo = 0
            var hi = l.days.count - 1
            var found = -1
            while lo <= hi {
                let mid = (lo + hi) / 2
                if l.days[mid] <= d {
                    found = mid
                    lo = mid + 1
                } else {
                    hi = mid - 1
                }
            }
            if found >= 0 { p.cash += l.values[found] * l.rate }
        }
        // [v25.566] 那天存著的定存（起存日 ≤ 那天 < 到期日／解約日）
        for s in spans {
            guard s.from <= d else { continue }
            if let u = s.until, d >= u { continue }
            p.cash += s.ntd
        }
        for c in cards { p.cardOwed += WealthHistory.owed(c, endOf: d) }
        // 那天成交、還沒交割：交割日在 (那天, 那天＋2 個營業日]；要扣的算待交割、要入帳的算賣股票還沒入帳
        let limit = WealthCal.day(StockTransaction.taiwanSettlementDate(from: d))
        for s in settles where s.day > d && s.day <= limit {
            if s.ntd > 0 {
                p.pending += s.ntd
            } else {
                p.incoming += -s.ntd
            }
        }
        return p
    }

    /// 一張卡在 d 那天結束時還沒扣的卡費：那天已結帳、還沒繳的帳單＋這一期刷到那天的
    /// ＋（[v25.565 驗證修正] 同 WealthFacts.statements 的 carry）前一期在 d 以前只繳了一部分（自動扣最低、少繳）轉進這一期的那筆——
    /// 「現在」的還沒出帳（Card.unbilled＝這一期 amount）本來就含它，回推不加會讓那幾天的卡費少算、「比上月」假跌
    fileprivate static func owed(_ c: WealthFacts.Card, endOf d: Date) -> Double {
        var total: Double = 0
        var previous: WealthStatement? = nil
        for s in c.statements {
            defer { previous = s }
            let start = WealthCal.day(s.start)
            if start > d { continue }
            if s.isPaid, WealthCal.day(s.paidOn ?? s.due) <= d { continue }
            if WealthCal.day(s.close) <= d {
                total += s.amount
            } else {
                for e in c.entries {
                    let ed = WealthCal.day(e.date)
                    if ed >= start && ed <= d { total += e.amount }
                }
                // 前期沒繳完轉過來的：前一期 d 那天已經扣過（只扣了一部分）才算在這一期；前一期還沒扣時它整筆已經算在上面
                if s.carriedIn > 0.5, let p = previous, p.isPaid, WealthCal.day(p.paidOn ?? p.due) <= d {
                    total += s.carriedIn
                }
            }
        }
        return total
    }
}

// MARK: - 一套數字

struct WealthFacts {
    /// 接下來幾天（每個帳戶的 upcoming）
    static let upcomingDays = 35
    /// [v25.564] 「接下來 30 天」：最低、不夠扣、財富頁 ③、銀行頁 ③ 都看這幾天（含第 30 天）
    static let lowWindowDays = 30

    let now: Date
    /// 今天 00:00
    let today: Date
    /// 銀行帳戶（照里程碑的順序）＋證券戶（isSecurities）
    let accounts: [Account]
    let cards: [Card]
    /// 存款合計（存摺上；算進存款合計、沒收起來的銀行帳戶，每個幣別換台幣；查不到匯率的不算）
    let cash: Double
    /// 有幣別查不到匯率（大字前加「約」）
    let cashIsApprox: Bool
    /// 台幣活存（定存帳戶、外幣不算）
    let live: Double
    /// 定存（帳戶種類是定存的）
    let fixedDeposit: Double
    /// 外幣（活存帳戶裡不是台幣的那幾格，換台幣）
    let foreign: Double
    /// 卡費還沒扣：每張卡「要繳＋還沒出帳」
    let owedCards: Double
    /// 待交割：銀行帳戶裡日期還沒到的股票款
    let pendingSettlement: Double
    /// 查不到匯率的幣別
    let unknownCodes: [String]
    /// [v25.564] 已經排定、還沒到的提款（刪卡寫回的那幾期帳單、你記的未來日期提款、標成已繳但日子還沒到的卡費；台幣）
    let scheduledOut: Double
    /// [v25.564] 證券戶（券商名片：持股市值讀股票頁、交割銀行、下一筆交割）
    let brokers: [Broker]
    /// [v25.564] 要確認（照 bad → warn → info、種類先後排好；按過「知道了」的不在裡面）
    let checks: [WealthCheck]
    /// [v25.565] 接下來的交割（35 天內；每個帳戶每天每幣別買賣相抵，照日期排）
    let settlements: [WealthSettlementDue]
    /// [v25.565] 理財每月淨資產回推用（口徑 4）：history.point(endOf:)
    let history: WealthHistory
    /// [v25.566] 每一期定存（沒開始、存著、到期待決定；照到期日，沒有到期日的排最後）：卡片頁 ⑥、行事曆、提醒、理財 30 天
    let timeDeposits: [TimeDeposit]
    /// [v25.566] 同一家銀行存摺上＋定存合計超過 300 萬的（存款保險一行、要確認 #14）
    let depositInsurance: [InsuranceGroup]
    /// [v25.567] 保單總表（財富頁的保障型保單、儲蓄險、車險、房屋險合成一張；一筆記帳保費只算一次）
    let policies: WealthPolicyFacts

    /// [v25.566] 存款保險：同一家銀行（每一存款人）本金＋利息最多保 300 萬（中央存款保險；境內外幣也保，人民幣不保）
    static let insuranceLimit: Double = 3_000_000

    /// [v25.566] 這一期定存（自動續存還沒寫進帳本的那一期也找得到）
    func timeDeposit(_ id: UUID?) -> TimeDeposit? {
        guard let id else { return nil }
        return timeDeposits.first { $0.id == id }
    }

    /// [v25.566] 這個帳戶所在的銀行超過 300 萬的那一組（帳戶頁 ⑧ 存款保險那一列）；沒有＝nil
    func insurance(for accountId: UUID) -> InsuranceGroup? {
        depositInsurance.first { $0.accountIds.contains(accountId) }
    }

    /// [v25.565] 理財淨資產的負債「卡費」：卡費還沒扣＋已經排定、還沒到的提款（刪卡寫回的帳單、預約繳款、未來日期的提款）。
    /// 跟財富頁「還沒扣」同一套（還沒扣＝這個＋待交割），預約繳款、刪卡都不會讓淨資產變多
    var netWorthCardOwed: Double { owedCards + scheduledOut }

    /// [v25.565] 所有卡接下來要繳的幾期（照截止日）
    var allDues: [WealthCardDue] {
        cards.flatMap { $0.dues }.sorted { a, b in a.due != b.due ? a.due < b.due : a.id < b.id }
    }

    /// [v25.565 裁定] 賣股票還沒入帳（台幣）：接下來的交割裡，同一天同一幣別買賣相抵後是「入帳」、日子還沒到的那幾筆；
    /// 只算沒收起來、算進存款合計的銀行帳戶（同 cash、pendingSettlement）。查不到匯率的不算（同 cash）。
    /// 理財淨資產算進存款那一類（FinanceSnapshot.pendingIncoming），財富頁的還沒扣、扣完能用不算它
    var pendingIncoming: Double {
        var counted = Set<UUID>()
        for a in accounts where !a.isSecurities && !a.hidden && a.countsInCash { counted.insert(a.id) }
        var total: Double = 0
        for s in settlements where !s.isOutflow && s.day > today && counted.contains(s.accountId) {
            total += s.ntd ?? 0
        }
        return total
    }

    /// 還沒扣＝卡費＋待交割（＋[v25.564] 已經排定、還沒到的提款）
    var notYetDebited: Double { owedCards + pendingSettlement + scheduledOut }
    /// 扣完活存能用＝台幣活存 − 還沒扣（judge §3.1）
    var usable: Double { live - notYetDebited }

    /// [v25.564] 財富頁 ② 要確認（帳戶頁才出現的「很久沒對存摺」不在這裡）
    var pageChecks: [WealthCheck] { checks.filter { $0.onPage } }

    /// [v25.564] 卡片頁 ② 要確認：跟這個帳戶／卡有關的
    func checks(for id: UUID) -> [WealthCheck] { checks.filter { $0.accountIds.contains(id) } }

    func broker(_ id: UUID?) -> Broker? {
        guard let id else { return nil }
        return brokers.first { $0.id == id }
    }

    var banks: [Account] { accounts.filter { !$0.isSecurities } }
    var securities: [Account] { accounts.filter { $0.isSecurities } }
    /// 記帳、收入、房屋水電選單列的銀行：沒收起來、不是定存（judge §6.2）
    var pickerBanks: [Account] { accounts.filter { !$0.isSecurities && !$0.hidden && !$0.isFixedDeposit } }
    /// 記帳選單列的卡：沒停用的
    var pickerCards: [Card] { cards.filter { !$0.isDisabled } }

    func account(_ id: UUID?) -> Account? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }
    }

    func card(_ id: UUID?) -> Card? {
        guard let id else { return nil }
        return cards.first { $0.id == id }
    }

    /// 英雄卡大字：「NT$81.7萬」；有幣別查不到匯率「約 NT$71.4萬」
    var cashText: String { (cashIsApprox ? "約 " : "") + cash.ntdWanString }

    /// 英雄卡大字下面那一句：「卡費還沒扣 NT$4.8萬」（有待交割「卡費還沒扣 NT$4.8萬、交割 NT$5.2萬」）；都沒有＝nil
    var notYetDebitedText: String? {
        var parts: [String] = []
        if owedCards > 0.5 { parts.append("卡費還沒扣 " + owedCards.ntdWanString) }
        if pendingSettlement > 0.5 {
            parts.append(parts.isEmpty ? "交割還沒扣 " + pendingSettlement.ntdWanString
                                       : "交割 " + pendingSettlement.ntdWanString)
        }
        // [v25.564] 已經排定的提款（刪卡寫回的那幾期等）
        if scheduledOut > 0.5 {
            parts.append(parts.isEmpty ? "其他還沒扣 " + scheduledOut.ntdWanString
                                       : "其他 " + scheduledOut.ntdWanString)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "、")
    }

    /// 「為什麼數字變了」：v2 第一次打開財富頁說明一次（judge §9-1：寫你自己的數字）。
    /// 沒有卡費還沒扣的帳戶、也沒有「以前沖正過、之後還沒對過存摺」的帳戶＝nil
    var passbookNotice: (title: String, message: String)? {
        let visible = banks.filter { !$0.hidden }
        let changed = visible.filter { $0.cardOwed > 0.5 }.sorted { $0.cardOwed > $1.cardOwed }
        // [v25.563 最後裁定] 以前的沖正（v1 刷卡當天扣時補到跟存摺一樣的差額）v2 照舊當加減（§1-8），
        // 卡費改在截止日才扣後，這種帳戶會多出「沖正那天還沒扣的卡費」：點名請他對一次存摺
        let adjusted = visible.filter { WealthFacts.hasLegacyAdjustSinceAnchor($0) }
        guard !changed.isEmpty || !adjusted.isEmpty else { return nil }
        var parts: [String] = []
        if !changed.isEmpty {
            var lines: [String] = []
            for a in changed.prefix(3) {
                let before = WealthFormat.ntd(a.ntdTotal - a.cardOwed)
                let after = WealthFormat.ntd(a.ntdTotal)
                lines.append("\(a.name)：\(before) → \(after)（卡費 \(WealthFormat.ntd(a.cardOwed)) 還沒扣）")
            }
            if changed.count > 3 { lines.append("另外 \(changed.count - 3) 個帳戶也一樣") }
            parts.append(lines.joined(separator: "\n"))
            parts.append("以前刷卡當天就從銀行扣；現在跟存摺一樣，卡費在繳款截止日才扣，所以數字比以前多。"
                         + "還沒扣的卡費寫在每一列下面的「扣完能用」。")
        } else {
            parts.append("以前刷卡當天就從銀行扣；現在跟存摺一樣，卡費在繳款截止日才扣。")
        }
        if !adjusted.isEmpty {
            var names: String = adjusted.prefix(3).map { $0.name }.joined(separator: "、")
            if adjusted.count > 3 { names += " 等 \(adjusted.count) 個帳戶" }
            parts.append(names + "以前沖正過：那是照以前的算法（刷卡當天就扣）補的差額，現在照樣加減，"
                         + "數字可能多了沖正那天還沒扣的卡費，請對一次存摺。")
        }
        parts.append("跟存摺對不上時，打開帳戶，按「銀行存款」右邊的＋、選幣別，再切到「對存摺」，打存摺上的數字，以後就從那裡往後算。")
        return ("銀行的數字改成跟存摺一樣", parts.joined(separator: "\n\n"))
    }

    /// 最近一次對存摺之後（從沒對過＝全部）還有以前記的沖正（isAdjust、沒有 kind）。
    /// 對存摺那天同一天的沖正已經被對存摺吸收（同一天對存摺最後算），所以只看「之後」的
    private static func hasLegacyAdjustSinceAnchor(_ a: Account) -> Bool {
        let last: Date? = a.lastAnchorDate
        return a.ledger.contains(where: { (row: WealthLedgerRow) -> Bool in
            guard row.kind == .legacyAdjust else { return false }
            guard let anchorDay = last else { return true }
            return WealthCal.day(row.date) > anchorDay
        })
    }

    // MARK: 一個帳戶

    struct Account: Identifiable {
        let id: UUID
        /// 暱稱 → 銀行名 → 標題
        let name: String
        /// 銀行名 → 標題
        let bankName: String
        let nickname: String?
        let isSecurities: Bool
        /// 帳戶種類是定存
        let isFixedDeposit: Bool
        /// 收起來了（帳本 hidden）
        let hidden: Bool
        /// 算進存款合計（帳本 countInCash，沒設＝算）
        let countsInCash: Bool
        /// 這個帳戶有的幣別（台幣在前，其他照出現的順序；D20：月薪入帳、記帳扣款的幣別也算）
        let currencies: [String]
        /// 每個幣別的存摺上（今天結束時）
        let balances: [String: Double]
        /// 換台幣的合計（查不到匯率的不算）
        let ntdTotal: Double
        /// 有數字、但查不到匯率的幣別
        let unknownCodes: [String]
        /// 從這裡扣的卡「要繳＋還沒出帳」（台幣）
        let cardOwed: Double
        /// 從這裡交割、還沒到交割日的股票款（台幣）
        let pendingSettlement: Double
        /// 最近一次對存摺（那天）
        let lastAnchorDate: Date?
        /// 明細：今天以前的，新到舊（judge §8 v2：明細不放未來的列）
        let ledger: [WealthLedgerRow]
        /// 接下來 35 天（明天起），舊到新，每一列有扣完剩多少
        let upcoming: [WealthLedgerRow]
        /// 接下來 30 天（[v25.564] 原本 35）最低（台幣；含今天的數字）；30 天內沒有事＝nil
        let lowestNTD: Double?
        let lowestDate: Date?
        // [v25.564] v3 加的
        /// 帳號末 4 碼（帳本 accountLast4 → 里程碑帳號的後 4 碼；都沒有 nil）
        let last4: String?
        /// 你排的順序（沒排過 nil；財富頁照「最近 90 天進出筆數」排）
        let sortIndex: Int?
        /// 用途（薪轉／扣款／存錢／外幣／零用）
        let purpose: String?
        /// 收起來（銷戶）那天
        let closedDate: Date?
        /// 帳戶種類是外幣
        let isForeignType: Bool
        /// 開戶日（里程碑的日期）
        let openedDate: Date
        /// 已經排定、還沒到的提款（台幣；刪卡寫回的那幾期帳單、你記的未來日期提款、標成已繳但日子還沒到的卡費）
        let scheduledOut: Double
        /// 接下來 30 天第一次不夠扣（某個幣別從 ≥0 變成 <0 的那一筆）；沒有＝nil
        let shortage: WealthShortage?
        /// 接下來 30 天（明天起、含第 30 天），舊到新，每一列有扣完剩多少
        let next30: [WealthLedgerRow]
        /// 最近 90 天的進出筆數（對存摺不算；財富頁沒排過的照它多到少）
        let recentCount: Int
        // [v25.566] v5 加的（build 建好帳戶之後才填；memberwise init 不用傳）
        /// 這個帳戶的定存（沒開始、存著、到期待決定；照到期日）
        var timeDeposits: [TimeDeposit] = []
        /// 定存算進存款合計的台幣（存著＝本金、到期待決定＝本息；舊的定存種類帳戶＝0：它的錢已經在存摺上）
        var depositNTD: Double = 0
        /// 定存查不到匯率的幣別（存款合計前面加「約」）
        var depositUnknownCodes: [String] = []

        /// [v25.566] 存摺上＋定存（台幣；水塔、帳戶頁看板用）
        var totalNTD: Double { ntdTotal + depositNTD }
        /// [v25.566] 看起來是一個定存帳戶：舊的「定存」種類，或有定存、存摺上每個幣別都是 0（水塔金水加鎖頭、卡面金色點點）
        var showsAsDeposit: Bool {
            if isFixedDeposit { return true }
            guard !timeDeposits.isEmpty else { return false }
            return !balances.values.contains(where: { Swift.abs($0) > 0.004 })
        }
        /// [v25.566] 最近要到期、還存著的那一期（沒有＝nil）
        var nextMaturing: TimeDeposit? {
            timeDeposits.first { $0.status == .active && $0.maturity != nil }
        }
        /// [v25.566] 這個幣別存著的定存本金（不含舊的定存種類帳戶：它的錢在存摺上）
        func depositAmount(_ code: String) -> Double {
            let c = WealthFacts.norm(code)
            var total: Double = 0
            for t in timeDeposits where t.countsSeparately && t.code == c {
                switch t.status {
                case .active: total += t.principal
                case .waiting: total += t.maturityAmount
                case .notStarted, .ended: break
                }
            }
            return total
        }

        /// 還沒扣＝卡費＋待交割＋已經排定的提款
        var notYetDebited: Double { cardOwed + pendingSettlement + scheduledOut }
        /// 扣完能用＝存摺上 − 還沒扣
        var usable: Double { ntdTotal - notYetDebited }
        var hasUnknownRate: Bool { !unknownCodes.isEmpty }

        /// 這個幣別的存摺上（台幣的 "TWD"／空白都算台幣）
        func balance(_ code: String) -> Double {
            balances[WealthFacts.norm(code)] ?? 0
        }

        /// 只有一個幣別有數字（或都是 0）時是那個幣別；好幾個幣別都有數字是 nil
        var singleCode: String? {
            let nonZero = balances.filter { Swift.abs($0.value) > 0.004 }.map(\.key)
            if nonZero.count > 1 { return nil }
            return nonZero.first ?? currencies.first ?? "NT$"
        }

        /// 列表那一列的金額：「NT$128,400」「美金 3,200.00」；好幾個幣別「約 NT$23.4萬」
        var balanceText: String {
            if let c = singleCode { return WealthFormat.money(balance(c), code: c) }
            return "約 " + ntdTotal.ntdWanString
        }

        /// 底下小字：查不到匯率「沒有匯率」；有還沒扣的「扣完能用 NT$5.3萬」；都沒有＝nil
        var footnoteText: String? {
            if hasUnknownRate { return "沒有匯率" }
            if notYetDebited > 0.5 { return "扣完能用 " + usable.ntdWanString }
            return nil
        }

        /// 選單括號裡的數字：「存摺 NT$12.8萬」「存摺 美金 3,200」；好幾個幣別「存摺 約 NT$23.4萬」；查不到匯率加「・沒有匯率」
        var pickerBalanceText: String {
            let body: String
            if let c = singleCode {
                body = FinanceRates.isNTD(c) ? balance(c).ntdWanString : balance(c).wanString(symbolPrefix: c)
            } else {
                body = "約 " + ntdTotal.ntdWanString
            }
            return "存摺 " + body + (hasUnknownRate ? "・沒有匯率" : "")
        }

        /// 選單一列：「台新銀行（存摺 NT$12.8萬）」；有暱稱「薪轉（台新銀行・存摺 NT$12.8萬）」
        var pickerLabel: String {
            if let n = nickname { return "\(n)（\(bankName)・\(pickerBalanceText)）" }
            return "\(bankName)（\(pickerBalanceText)）"
        }

        /// 好幾個幣別時子選單那一列：「美金（存摺 美金 3,200）」「NT$（存摺 NT$13.2萬）」
        func pickerLabel(code: String) -> String {
            let c = WealthFacts.norm(code)
            let v = balance(c)
            let text = FinanceRates.isNTD(c) ? v.ntdWanString : v.wanString(symbolPrefix: c)
            return "\(c)（存摺 \(text)）"
        }
    }

    // MARK: 一張信用卡

    struct Card: Identifiable {
        let id: UUID
        /// 卡名 → 標題
        let name: String
        let isDisabled: Bool
        /// 額度（沒填或 0＝nil）
        let limit: Double?
        /// 實際拿來算的結帳日、繳款截止日
        let billingDay: Int
        let paymentDay: Int
        let billingDayMissing: Bool
        let paymentDayMissing: Bool
        /// 這一期（還沒結帳的）從哪個帳戶扣；沒設或帳戶不在了是 nil
        let payerId: UUID?
        let payerName: String?
        /// 每一期帳單，舊到新（含還沒結帳的這一期）
        let statements: [WealthStatement]
        /// 每一筆刷卡，舊到新（台幣）
        let entries: [WealthCardEntry]
        /// 要繳：已經結帳、截止日還沒到
        let due: Double
        /// 最早一期還沒繳的帳單
        let dueStatement: WealthStatement?
        /// 還沒出帳：還沒結帳的這一期，刷到今天
        let unbilled: Double
        let unbilledCount: Int
        /// 這一期的結帳日、截止日
        let nextClose: Date
        let nextDue: Date
        /// 最近一期已經扣的帳單
        let lastPaid: WealthStatement?
        // [v25.564] v3 加的
        /// 發卡銀行（卡上印的銀行，里程碑 bankName；跟扣款帳戶無關）
        let issuer: String?
        /// 暱稱（帳本 accounts[卡].nickname）
        let nickname: String?
        /// 卡號末 4 碼
        let last4: String?
        /// 卡面顏色 0–5（帳本 faceColor；沒選過照 id 固定挑一個）
        let faceColor: Int
        /// 卡費怎麼繳
        let payMode: WealthPayMode
        /// 要繳裡過了截止日還沒繳的
        let overdue: Double
        /// 你排的順序（帳本 accounts[卡].sortIndex）
        let sortIndex: Int?
        /// 停用那天（帳本 accounts[卡].closedDate）
        let closedDate: Date?
        /// 里程碑上原本的扣款帳戶（帳戶刪了還指著它時，要確認 #7 寫「原本的帳戶已經不在了」）
        let linkedRaw: UUID?
        // [v25.565] v4 加的（build 建好卡之後才填；memberwise init 不用傳）
        /// 卡片有效期限那個月的 1 號（里程碑 expiryDate 只取年月；沒填 nil）。只給行事曆「卡片到期」、要確認 #12、通知用
        /// [v25.568] v7 起有效期限是密文：build 的 expiryMonths（LifeStore.cardExpiryMonths 解好的）優先。網頁版那一包不放它
        var expiryMonth: Date? = nil
        /// 接下來要繳的幾期（已結帳還沒繳的、這一期、下一期；照截止日；金額 0 的不列）
        var dues: [WealthCardDue] = []

        /// 卡費還沒扣＝要繳＋還沒出帳
        var owed: Double { due + unbilled }

        /// [v25.564] 項目卡、卡片頁標題：有暱稱用暱稱；不然「國泰世華 CUBE」（卡名已經以發卡銀行開頭就不重複）
        var fullName: String {
            if let n = nickname { return n }
            guard let i = issuer, !name.hasPrefix(i) else { return name }
            return i + " " + name
        }

        /// [v25.564] 當作已繳、要確認問的那幾期（截止日在 35 天內）
        func assumedPaid(today: Date) -> [WealthStatement] {
            statements.filter { $0.status == .assumedPaid && WealthCal.days(from: $0.due, to: today) <= 35 }
        }
        /// 還能刷＝額度 − 要繳 − 還沒出帳（不小於 0）；沒填額度＝nil
        var available: Double? {
            guard let l = limit else { return nil }
            return Swift.max(0, l - owed)
        }
        /// 使用率＝(要繳＋還沒出帳)÷額度；沒填額度＝nil
        var usage: Double? {
            guard let l = limit, l > 0 else { return nil }
            return owed / l
        }
        /// 0 很寬鬆（< 30%）、1 正常（< 50%）、2 偏高（< 90%）、3 快刷滿了
        var usageTier: Int {
            let u = usage ?? 0
            if u < 0.3 { return 0 }
            if u < 0.5 { return 1 }
            if u < 0.9 { return 2 }
            return 3
        }
        var usageTierName: String {
            switch usageTier {
            case 0: return "很寬鬆"
            case 1: return "正常"
            case 2: return "偏高"
            default: return "快刷滿了"
            }
        }
        /// 「額度用了 8.3%・很寬鬆」；沒填額度＝nil
        var usageText: String? {
            guard let u = usage else { return nil }
            return "額度用了 \(WealthFormat.percent(u))・\(usageTierName)"
        }
    }

    // MARK: [v25.564] 一個證券戶（券商名片，judge §3.9、§4.3：市值、持股讀股票頁，不算進存款合計）

    struct Broker: Identifiable {
        let id: UUID
        let name: String
        /// 交割銀行（帳本 settlementBankId → 這些股票最常用的交割帳戶；都沒有 nil）
        let settlementBankId: UUID?
        let settlementName: String?
        /// 持股（沒賣掉、選了這個證券戶的股票），市值大到小
        let holdingIds: [UUID]
        /// 持股市值、成本（台幣，同股票頁 Stock.marketValue／totalCost）
        let marketValue: Double
        let cost: Double
        /// 下一筆待交割：那天、金額（台幣；正的＝要從交割銀行扣，負的＝會入帳）
        let nextSettlementDate: Date?
        let nextSettlementAmount: Double
        // [v25.567] v6 加的（build 建好之後才填；memberwise init 不用傳）
        /// 交割銀行是你在證券戶填的（false＝照股票最常用的猜的、或沒有）
        var settlementFromBook: Bool = false
        /// 接下來 30 天要交割的（照日子；交割銀行裡這個證券戶的股票）
        var dues: [WealthBrokerDue] = []
        /// 以前記在證券戶身上的交割紀錄（linkedStockId 的 BankDeposit，含股利）：幾筆、合計（台幣，有正負）、哪幾筆
        var legacyCount: Int = 0
        var legacyTotal: Double = 0
        var legacyIds: [UUID] = []
        /// [v25.567 驗] 舊交割紀錄裡股票還在的幾筆（搬得動的；股票已經刪了的留在證券戶當紀錄，#16 不為它們再問）
        var legacyLiveCount: Int = 0

        var unrealized: Double { marketValue - cost }
        /// 未實現 %（成本 0＝nil）
        var unrealizedRatio: Double? { cost > 0 ? (marketValue - cost) / cost : nil }
    }

    // MARK: [v25.566] 一期定存（judge §4.2 ⑥、§5.5；sim_v5.py make_deposit）

    struct TimeDeposit: Identifiable {
        enum Status: Equatable {
            /// 起存日還沒到（還不算進存款合計；從活存轉出的那一筆在起存日）
            case notStarted
            /// 存著（本金算進存款合計的「定存」）
            case active
            /// 到期了、選了「到期再決定」還沒決定（照本息算在定存裡）
            case waiting
            /// 到期轉活存了、自動續存了（下一期接手）、提前解約了
            case ended
        }

        /// 這一期（帳本的那一筆；自動續存還沒寫進帳本的＝WealthTimeDeposit.successorId）
        let id: UUID
        let accountId: UUID
        /// 帳戶名（暱稱 → 銀行名）：「台灣銀行」
        let accountName: String
        /// 幣別（台幣 "NT$"）
        let code: String
        let principal: Double
        let rate: Double?
        let months: Int?
        let start: Date
        /// 到期日（00:00；沒有＝nil）
        let maturity: Date?
        let mode: WealthMaturityMode
        /// 到期、解約的錢轉進哪個帳戶（轉進的帳戶已經刪了＝nil：那筆錢跟著刪掉的帳戶走）
        let payoutId: UUID?
        let payoutName: String?
        /// 起存那天從這個帳戶的活存轉出（舊的定存種類帳戶一律 false）
        let fromLive: Bool
        /// 舊的「定存」種類帳戶（存摺上就是這筆定存的錢：不另外加本金、不記轉出）
        let isLegacyAccount: Bool
        /// 帳本裡還沒有（自動續存算出來的；改它之前 LifeStore 會先寫進帳本）
        let isVirtual: Bool
        /// 第幾期（0＝最早；自動續存一次 +1）
        let termIndex: Int
        /// 整期預估利息（原幣；單利、未扣稅）
        let interest: Double
        let status: Status
        let closedDate: Date?
        /// 提前解約實拿的利息（原幣）
        let closedInterest: Double
        /// 到期前 7 天提醒
        let remind: Bool
        let certificateLast4: String?
        /// 現在算進存款合計的台幣（存著＝本金、到期待決定＝本息；沒開始、結束了＝0；查不到匯率＝nil）。
        /// 舊的定存種類帳戶的也照算（畫面用），但不加進合計（countsSeparately）
        let ntd: Double?

        /// 另外加進存款合計（舊的定存種類帳戶＝false：它的錢已經在帳戶的存摺上）
        var countsSeparately: Bool { !isLegacyAccount }
        /// 到期本息（原幣）
        var maturityAmount: Double { principal + interest }
        /// 「一年定存」「6 個月定存」「定存」
        var label: String { WealthDepositMath.termLabel(months: months) }
        /// 「1.7%」；沒填 nil
        var rateText: String? { WealthDepositMath.rateText(rate) }
        /// 句子裡的名字：「台灣銀行定存」（帳戶名已經寫「定存」就不重複）
        var displayTitle: String { accountName.hasSuffix("定存") ? accountName : accountName + "定存" }

        /// 還有幾天到期（沒有到期日＝nil；過了是負的）
        func daysLeft(_ today: Date) -> Int? {
            maturity.map { WealthCal.days(from: today, to: $0) }
        }

        /// 走了幾成（0…1；沒有到期日或起存日＝到期日＝nil）
        func progress(_ today: Date) -> Double? {
            guard let m = maturity else { return nil }
            let total = WealthCal.days(from: start, to: m)
            guard total > 0 else { return nil }
            let done = WealthCal.days(from: start, to: today)
            return Swift.min(1, Swift.max(0, Double(done) / Double(total)))
        }

        /// 「3/15」；超過 300 天才到期（下一期的隔年）寫「2028/3/15」，免得看成今年
        func maturityText(_ today: Date) -> String? {
            guard let m = maturity else { return nil }
            if WealthCal.days(from: today, to: m) > 300 { return WealthFormat.ymd(m) }
            return WealthFormat.monthDay(m)
        }

        /// 「預估利息 8,500」（外幣「預估利息 US$48.00」）；沒填利率 nil。遮住「預估利息 ••••」
        func interestText(masked: Bool) -> String? {
            guard (rate ?? 0) > 0 else { return nil }
            return "預估利息 " + (masked ? "••••" : WealthFormat.plain(interest, code: code))
        }

        /// 一句（judge §8 v5 做好 1）：「3/15 到期・還有 147 天・預估利息 8,500」；
        /// 到期再決定已經到期「3/15 到期了・還沒決定怎麼處理」；沒開始「10/25 起存」；沒有到期日「沒填到期日」
        func maturityLine(today: Date, masked: Bool) -> String {
            switch status {
            case .notStarted:
                return WealthFormat.monthDay(start) + " 起存"
            case .waiting:
                return (maturityText(today) ?? "") + " 到期了・還沒決定怎麼處理"
            case .ended:
                return "已經結束"
            case .active:
                break
            }
            guard let mt = maturityText(today), let left = daysLeft(today) else {
                var s = "沒填到期日"
                if let i = interestText(masked: masked) { s += "・" + i }
                return s
            }
            var parts: [String] = [mt + " 到期", left <= 0 ? "今天到期" : "還有 \(left) 天"]
            if let i = interestText(masked: masked) { parts.append(i) }
            return parts.joined(separator: "・")
        }

        /// 項目卡第二行：「1.7%・本息續存」（沒填利率「本息續存」）
        var termLine: String {
            var parts: [String] = []
            if let r = rateText { parts.append(r) }
            parts.append(mode.shortTitle)
            return parts.joined(separator: "・")
        }

        /// 進度條兩端：左「2026/3/15」右「2027/3/15（還有 147 天）」；沒有到期日 nil
        func progressEnds(today: Date) -> (left: String, right: String)? {
            guard let m = maturity, let left = daysLeft(today) else { return nil }
            let tail = left > 0 ? "（還有 \(left) 天）" : ""
            return (WealthFormat.ymd(start), WealthFormat.ymd(m) + tail)
        }

        /// 到期處理那一句：「到期本息續存成 508,500」「到期本金續存、利息 8,500 轉進薪轉」「到期本息 508,500 轉進台灣銀行」
        /// 「到期再決定」。遮住時金額換「••••」
        func modeSentence(masked: Bool) -> String {
            let total = masked ? "••••" : WealthFormat.plain(maturityAmount, code: code)
            let int = masked ? "••••" : WealthFormat.plain(interest, code: code)
            let to = payoutName ?? accountName
            switch mode {
            case .renewAll: return "到期本息續存成 " + total
            case .renewPrincipal: return "到期本金續存、利息 " + int + " 轉進" + to
            case .toLive: return "到期本息 " + total + " 轉進" + to
            case .decide: return "到期再決定"
            }
        }
    }

    /// [v25.566] 同一家銀行的存款合計（存款保險；judge §3.5 #14、§4.2 ⑧）
    struct InsuranceGroup: Identifiable {
        /// 銀行 key（WealthFacts.bankKey）
        let id: String
        let bankName: String
        /// 這家合計（台幣：存摺上每個幣別＋存著的定存；人民幣不保、黃金存摺不是存款，都不算）
        let total: Double
        let accountIds: [UUID]

        /// 「台灣銀行合計 NT$326萬，存款保險同一家最多保 NT$300萬」（ntdWanString：主執行緒）
        var text: String {
            bankName + "合計 " + total.ntdWanString + "，存款保險同一家最多保 " + WealthFacts.insuranceLimit.ntdWanString
        }
    }

    /// [v25.566] 同一家銀行的 key：去空白、「臺」→「台」（「台灣銀行」「臺灣 銀行」是同一家）
    static func bankKey(_ name: String) -> String {
        let t = name.replacingOccurrences(of: "臺", with: "台")
        return String(t.filter { !$0.isWhitespace })
    }

    /// [v25.566] 人民幣（存款保險不保）
    static func isRMB(_ code: String) -> Bool {
        FXRateService.isoCode(for: code) == "CNY"
    }

    /// [v25.566 驗證修正] 存款保險算不算這個幣別：人民幣不保；黃金、白銀（黃金存摺：FXRateService 的 XAU、XAU(錢)、
    /// XAU(盎司)、XAG）不是存款，也不算——不然台灣銀行的黃金存摺會把「同一家合計」墊過 300 萬，多一條假的提醒
    static func isInsured(_ code: String) -> Bool {
        if isRMB(code) { return false }
        guard let iso = FXRateService.isoCode(for: code) else { return true }
        return !(iso.hasPrefix("XAU") || iso.hasPrefix("XAG"))
    }

    // MARK: - 工具

    /// 台幣一律寫 "NT$"（"TWD"、空白都算台幣，FinanceRates.isNTD）
    static func norm(_ code: String) -> String { FinanceRates.isNTD(code) ? "NT$" : code }

    /// 帳戶、卡的名字：暱稱 → 銀行名（卡：卡名）→ 標題
    static func displayName(of m: LifeMilestone, book: WealthBook) -> String {
        if let n = book.account(m.id).trimmedNickname { return n }
        if m.financeSubCategory == .creditCard {
            if let c = m.cardName?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
            return m.title
        }
        return bankName(of: m)
    }

    /// 銀行名 → 標題
    static func bankName(of m: LifeMilestone) -> String {
        if let b = m.bankName?.trimmingCharacters(in: .whitespaces), !b.isEmpty { return b }
        return m.title
    }

    /// 這筆真的存提款紀錄算存摺上時要不要跳過（被別的算法取代；v1 bankDepositIsReplaced 搬過來）：
    /// 連到刷卡支出（卡費帳單取代）、連到週期性固定支出／收入（逐期展開取代）、
    /// 連到跟股票有關的收入／支出而那檔股票自己有交割帳戶（銀行的錢只看股票自己寫的交割、股利；v1 W8）
    static func isReplaced(_ dep: BankDeposit, expensesById: [UUID: Expense], incomesById: [UUID: Income],
                           stocksById: [UUID: Stock]) -> Bool {
        guard let linkedId = dep.linkedExpenseId else { return false }
        if let exp = expensesById[linkedId] {
            if exp.linkedCreditCardMilestoneId != nil { return true }
            if exp.expenseType == .fixed, exp.recurrence != nil { return true }
            if let sid = exp.linkedStockId, stocksById[sid]?.hasOwnSettlementAccount == true { return true }
            return false
        }
        if let inc = incomesById[linkedId] {
            if inc.period != .once { return true }
            if let sid = inc.linkedStockId, stocksById[sid]?.hasOwnSettlementAccount == true { return true }
        }
        return false
    }

    /// 這個帳戶有哪些幣別（D20；記帳、收入、股票、房屋水電、AI 記帳的選單都用這一支）：
    /// 存提款紀錄（兩個方向都算）、入這裡的收入、扣這裡的記帳、交割在這裡的股票用過的幣別；台幣在前；都沒有＝["NT$"]。
    /// [v25.564] extra：新增帳戶時勾的幣別（帳本 accounts[].currencies；還沒有紀錄也列得出來）
    static func currencies(forAccount account: LifeMilestone, expenses: [Expense], incomes: [Income],
                           stocks: [Stock], extra: [String]? = nil) -> [String] {
        var seen: [String] = []
        func add(_ raw: String?) {
            guard let raw else { return }
            let c = norm(raw)
            if !seen.contains(c) { seen.append(c) }
        }
        for d in account.bankDeposits ?? [] { add(d.currencyCode) }
        for i in incomes where i.linkedBankMilestoneId == account.id { add(i.linkedBankCurrency ?? "NT$") }
        for e in expenses where e.linkedBankMilestoneId == account.id && e.linkedCreditCardMilestoneId == nil {
            add(e.linkedBankCurrency ?? "NT$")
        }
        for s in stocks where s.linkedBankMilestoneId == account.id || s.linkedSecuritiesMilestoneId == account.id {
            add(s.linkedBankCurrency ?? "NT$")
        }
        for c in extra ?? [] { add(c) }
        if seen.isEmpty { return ["NT$"] }
        if let i = seen.firstIndex(of: "NT$"), i > 0 {
            seen.remove(at: i)
            seen.insert("NT$", at: 0)
        }
        return seen
    }

    /// [v25.564] 定期扣款的這一期記到哪張卡或哪個帳戶：有改卡改帳戶的歷史（帳本 linkFrom）照那一期那天找；
    /// 沒有＝記帳那筆現在的卡（有卡）或帳戶。跟卡費的扣款帳戶（payFrom）同一支 payer：最後一段跟著現在的連結
    static func recurringTarget(_ e: Expense, at date: Date, history: [WealthPayFrom]?) -> UUID? {
        let current: UUID? = e.linkedCreditCardMilestoneId ?? e.linkedBankMilestoneId
        return WealthCardCycle.payer(statementKey: WealthCal.dayKey(date), linked: current, history: history)
    }

    /// 一張卡到 until 那天（含）的每一筆刷卡（台幣；定期扣款每一期一筆，期數一次算、金額照當時），舊到新。
    /// [v25.564] book：定期扣款改卡的歷史（linkFrom）——以前刷這張、後來改別張的，以前那幾期還算這張
    static func cardEntries(forCard cardId: UUID, expenses: [Expense], through until: Date,
                            rates: FinanceRates, book: WealthBook = WealthBook()) -> [WealthCardEntry] {
        let limit = WealthCal.day(until)
        var out: [WealthCardEntry] = []
        for exp in expenses {
            if exp.expenseType == .fixed, exp.recurrence != nil {
                let hist = book.links(exp.id)
                let mentioned = exp.linkedCreditCardMilestoneId == cardId
                    || (hist ?? []).contains(where: { (seg: WealthPayFrom) -> Bool in seg.accountId == cardId })
                guard mentioned else { continue }
                let amounts = exp.amountHistory.sorted { $0.date < $1.date }
                for p in WealthSchedule.fixedPeriods(exp, through: until) {
                    if hist != nil && recurringTarget(exp, at: p.date, history: hist) != cardId { continue }
                    let raw = WealthSchedule.amount(at: p.date, current: exp.amount, sortedHistory: amounts)
                    out.append(WealthCardEntry(
                        id: "cc-\(exp.id.uuidString)-\(p.index)", date: p.date,
                        amount: WealthSchedule.ntd(of: exp, raw: raw, rates: rates),
                        expenseId: exp.id, isRecurring: p.index > 0))
                }
            } else if exp.linkedCreditCardMilestoneId == cardId, WealthCal.day(exp.date) <= limit {
                out.append(WealthCardEntry(
                    id: "cc-\(exp.id.uuidString)", date: exp.date,
                    amount: WealthSchedule.ntd(of: exp, raw: exp.amount, rates: rates),
                    expenseId: exp.id, isRecurring: false))
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// 把刷卡分成一期一期的帳單（舊到新）。payer：這一期從哪個帳戶扣（只認還在的銀行帳戶）。
    /// [v25.564] prefs：卡費怎麼繳、每一期的註記（標成已繳、帳單金額、還沒繳）、從哪天起才追、算到下一期的刷卡。
    /// 規則（sim_v3.py 照這裡寫）：
    /// 1. 一期＝(上次結帳日, 這次結帳日]；〔算到下一期〕的那幾筆往後一期。
    /// 2. 帳單金額＝你輸入的帳單數字；沒輸入＝App 算的＋前期未繳（上一期只繳一部分剩下的）。
    /// 3. 還沒結帳＝unbilled；你標了已繳＝paid（那天、你選的帳戶、你繳的數字）；截止日在 trackFrom 以前＝paid（截止日從扣款帳戶扣全額）；
    ///    自動扣全額：截止日當天起 paid；自動扣最低：截止日當天起 paid（扣帳單的 10%，剩下的算下一期）；
    ///    自己繳：你說還沒繳→過了截止日 overdue；沒標、過了截止日（隔天起）assumedPaid（截止日從扣款帳戶扣全額）；
    ///    每次問我：過了截止日 overdue。其他＝due。
    /// 4. 只繳一部分剩下的 > 0.5 元：算進「下一次結帳日」那一期（那一期沒有刷卡也長一期出來）。
    static func statements(of card: LifeMilestone, entries: [WealthCardEntry], prefs: WealthCardPrefs,
                           bankIds: Set<UUID>, today: Date) -> [WealthStatement] {
        let b = WealthCardCycle.billingDay(card.billingDay)
        let p = WealthCardCycle.paymentDay(card.paymentDay)
        let shifted = Set(prefs.nextPeriodEntries ?? [])
        var sums: [Date: Double] = [:]
        var counts: [Date: Int] = [:]
        for e in entries {
            var close = WealthCardCycle.statementClose(for: e.date, billingDay: b)
            if shifted.contains(e.id) { close = WealthCardCycle.nextClose(after: close, billingDay: b) }
            sums[close, default: 0] += e.amount
            counts[close, default: 0] += 1
        }
        let t = WealthCal.day(today)
        let mode = prefs.mode
        let trackFrom: Date? = prefs.trackFrom.map { WealthCal.day($0) }
        var closes = sums.keys.sorted()
        var out: [WealthStatement] = []
        var carry: Double = 0
        var i = 0
        while i < closes.count {
            let close = closes[i]
            let key = WealthCal.monthKey(close)
            let due = WealthCardCycle.dueDate(close: close, billingDay: b, paymentDay: p)
            let dueDay = WealthCal.day(due)
            let start = WealthCal.addDays(1, to: WealthCardCycle.previousClose(close, billingDay: b))
            let raw = WealthCardCycle.payer(statementKey: key, linked: card.linkedBankMilestoneId, history: prefs.payFrom)
            let payer: UUID? = raw.flatMap { bankIds.contains($0) ? $0 : nil }
            let note: WealthStatementNote? = prefs.statements?[key]
            let computed = sums[close] ?? 0
            let stated: Double? = note?.statedAmount
            let amount: Double = stated ?? (computed + carry)
            let carriedIn: Double = stated == nil ? carry : 0
            let closed = close < t
            let minimum = (amount * 0.1).rounded()
            let saidNotPaid = note?.notPaid == true
            var status: WealthStatementStatus = .due
            var paidOn: Date? = nil
            var paidFrom: UUID? = nil
            var paidAmount: Double = 0
            var explicit = false
            if !closed {
                status = .unbilled
            } else if let pd = note?.paidDate {
                status = .paid
                paidOn = WealthCal.day(pd)
                paidFrom = note?.paidAccount.flatMap { bankIds.contains($0) ? $0 : nil }
                paidAmount = note?.paidAmount ?? amount
                explicit = true
            } else if let tf = trackFrom, dueDay < tf {
                status = .paid
                paidOn = dueDay
                paidFrom = payer
                paidAmount = amount
            } else {
                switch mode {
                case .autoFull:
                    if dueDay <= t {
                        status = .paid
                        paidOn = dueDay
                        paidFrom = payer
                        paidAmount = amount
                    }
                case .autoMin:
                    if dueDay <= t {
                        status = .paid
                        paidOn = dueDay
                        paidFrom = payer
                        paidAmount = Swift.min(minimum, amount)
                    }
                case .manual:
                    if saidNotPaid {
                        if dueDay < t { status = .overdue }
                    } else if dueDay < t {
                        status = .assumedPaid
                        paidOn = dueDay
                        paidFrom = payer
                        paidAmount = amount
                    }
                case .askEachTime:
                    if dueDay < t { status = .overdue }
                }
            }
            let isPaid = status == .paid || status == .assumedPaid
            carry = (isPaid && amount - paidAmount > 0.5) ? amount - paidAmount : 0
            out.append(WealthStatement(
                key: key, start: start, close: close, due: due, amount: amount, count: counts[close] ?? 0,
                payerId: payer, isClosed: closed, isPaid: isPaid,
                computedAmount: computed, statedAmount: stated, carriedIn: carriedIn, status: status,
                paidOn: paidOn, paidFrom: paidFrom, paidAmount: paidAmount,
                isExplicitPaid: explicit, notPaid: saidNotPaid))
            if carry > 0.5 {
                // 前期未繳算進下一次結帳日那一期：那一期沒有刷卡也長一期出來
                let next = WealthCardCycle.nextClose(after: close, billingDay: b)
                if i + 1 >= closes.count || closes[i + 1] != next {
                    closes.insert(next, at: i + 1)
                }
            }
            i += 1
        }
        return out
    }

    /// 一張卡的每一期帳單（刪卡時用：每一期照它的扣款帳戶寫回一筆，存摺上的數字不變）
    static func cardStatements(for card: LifeMilestone, milestones: [LifeMilestone], book: WealthBook,
                               expenses: [Expense], rates: FinanceRates, now: Date) -> [WealthStatement] {
        let bankIds = Set(milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .bank
        }.map(\.id))
        let today = WealthCal.day(now)
        let entries = cardEntries(forCard: card.id, expenses: expenses, through: today, rates: rates, book: book)
        return statements(of: card, entries: entries, prefs: book.card(card.id), bankIds: bankIds, today: today)
    }

    /// [v25.564] 卡面顏色沒選過：照 id 固定挑一個（0–5；同一張卡每次一樣）
    static func defaultFaceColor(_ id: UUID) -> Int {
        Swift.abs(MoneyItem.seed(id)) % 6
    }

    // MARK: - 換匯（轉帳）

    /// 轉帳預設的匯率（1 外幣＝幾台幣）：剛好一邊是台幣、另一邊設定裡查得到匯率才有；其他＝nil
    static func defaultTransferRate(from fromCode: String, to toCode: String, rates: FinanceRates) -> Double? {
        let f = norm(fromCode), t = norm(toCode)
        if f == t { return nil }
        if f == "NT$" { return rates.known(t) }
        if t == "NT$" { return rates.known(f) }
        return nil
    }

    /// 轉出 amount（fromCode）對方收到多少（toCode）。rate：1 外幣＝幾台幣（只在一邊是台幣時用，可以是你改過的）；
    /// 兩邊都是外幣用設定裡的匯率。台幣四捨五入到元、外幣到 0.01。換不了（查不到匯率）＝nil
    /// 例：台幣 50,000 → 美金、匯率 32.05 → 1,560.06
    static func transferAmount(_ amount: Double, from fromCode: String, to toCode: String, rate: Double?,
                               rates: FinanceRates) -> Double? {
        let f = norm(fromCode), t = norm(toCode)
        if f == t { return amount }
        let ntd: Double
        if f == "NT$" {
            ntd = amount
        } else if t == "NT$", let r = rate, r > 0 {
            ntd = amount * r
        } else if let r = rates.known(f), r > 0 {
            ntd = amount * r
        } else {
            return nil
        }
        if t == "NT$" { return ntd.rounded() }
        let toRate: Double?
        if f == "NT$", let r = rate, r > 0 { toRate = r } else { toRate = rates.known(t) }
        guard let r = toRate, r > 0 else { return nil }
        return (ntd / r * 100).rounded() / 100
    }

    // MARK: - 快取 key

    /// LifeStore.wealthFacts 的快取 key：里程碑／財富帳本的 revision＋記帳、理財的 modifyID＋匯率＋日期
    static func cacheKey(revision: Int, expense: ExpenseStore, finance: FinanceStore, now: Date) -> String {
        let rateSig = expense.currencyRates.map { "\($0.code)=\($0.rate)" }.joined(separator: ",")
        return "\(revision)|\(expense.modifyID.uuidString)|\(finance.modifyID.uuidString)|\(rateSig)|\(WealthCal.dayKey(now))"
    }

    // MARK: - build

    /// 一次建好全部（很重：展開每一期）。全 App 請用 LifeStore.wealthFacts(expense:finance:) 拿快取的。
    /// [v25.566] deposits：財富帳本的定存那一包（LifeStore.wealthDeposits）
    /// [v25.568] expiryMonths：每張卡有效期限那個月 1 號（LifeStore.cardExpiryMonths：v7 起有效期限是密文，那邊解好給）；
    /// 沒給（nil）或沒有那張卡＝照里程碑的 expiryDate（還沒搬的明碼；搬完是 nil＝沒有效期限）
    static func build(milestones: [LifeMilestone], book: WealthBook, deposits: WealthDepositBook = WealthDepositBook(),
                      expenses: [Expense], incomes: [Income],
                      stocks: [Stock], rates: FinanceRates, now: Date,
                      insurances: [SavingsInsurance] = [], vehicles: [Vehicle] = [],
                      realEstates: [RealEstate] = [], expiryMonths: [UUID: Date]? = nil) -> WealthFacts {
        let today = WealthCal.day(now)
        let horizon = WealthCal.addDays(upcomingDays, to: today)
        let finance = milestones.filter { $0.category == .achievement && $0.financeSubCategory != nil }
        let bankMs = finance.filter { $0.financeSubCategory == .bank }
        let securityMs = finance.filter { $0.financeSubCategory == .securities }
        let cardMs = finance.filter { $0.financeSubCategory == .creditCard }
        let bankIds = Set(bankMs.map(\.id))

        var nameById: [UUID: String] = [:]
        for m in finance { nameById[m.id] = displayName(of: m, book: book) }
        let expensesById = Dictionary(expenses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let incomesById = Dictionary(incomes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let stocksById = Dictionary(stocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var dividendIds = Set<UUID>()
        for s in stocks { dividendIds.formUnion(WealthIDs.dividendDepositIds(of: s)) }
        let excluded = Set(book.excludedExpenses ?? [])

        // 卡：每一期帳單（v3：卡費怎麼繳、標成已繳、帳單金額不一樣、前期未繳）；動到銀行的那一筆記到那個帳戶
        var cards: [Card] = []
        var billsByAccount: [UUID: [BillRef]] = [:]
        var owedByAccount: [UUID: Double] = [:]
        for c in cardMs {
            let prefs = book.card(c.id)
            let entries = cardEntries(forCard: c.id, expenses: expenses, through: today, rates: rates, book: book)
            let stmts = statements(of: c, entries: entries, prefs: prefs, bankIds: bankIds, today: today)
            let card = makeCard(c, name: nameById[c.id] ?? c.title, entries: entries, statements: stmts,
                                today: today, book: book, bankIds: bankIds, nameById: nameById)
            cards.append(card)
            for s in stmts {
                if let ref = billRef(cardId: c.id, cardName: card.name, statement: s, mode: card.payMode, today: today) {
                    billsByAccount[ref.accountId, default: []].append(ref)
                }
                if !s.isPaid, let payer = s.payerId, Swift.abs(s.amount) > 0.004 {
                    owedByAccount[payer, default: 0] += s.amount
                }
            }
        }

        // 直接扣銀行的週期性固定支出（v3：改帳戶有歷史，每一期照那一期那天的帳戶）；一次掃、照帳戶分好
        var fixedByBank: [UUID: [FixedRef]] = [:]
        for e in expenses where e.expenseType == .fixed && e.recurrence != nil {
            if excluded.contains(e.id.uuidString) { continue }
            let hist = book.links(e.id)
            if hist == nil && (e.linkedCreditCardMilestoneId != nil || e.linkedBankMilestoneId == nil) { continue }
            let amounts = e.amountHistory.sorted { $0.date < $1.date }
            for p in WealthSchedule.fixedPeriods(e, through: horizon) {
                guard let target = recurringTarget(e, at: p.date, history: hist), bankIds.contains(target) else { continue }
                let raw = WealthSchedule.amount(at: p.date, current: e.amount, sortedHistory: amounts)
                let own = target == e.linkedBankMilestoneId && e.linkedCreditCardMilestoneId == nil
                fixedByBank[target, default: []].append(FixedRef(expense: e, index: p.index, date: p.date,
                                                                 raw: raw, ownAccount: own))
            }
        }
        // 入銀行的週期性收入（v3：金額歷史以帳本為準；改帳戶有歷史）
        var incomesByBank: [UUID: [IncomeRef]] = [:]
        for inc in incomes where inc.period != .once {
            let hist = book.links(inc.id)
            if hist == nil && inc.linkedBankMilestoneId == nil { continue }
            let amounts = (book.incomeAmountHistory(inc.id) ?? inc.amountHistory ?? []).sorted { $0.date < $1.date }
            for p in WealthSchedule.incomePeriods(inc, through: horizon) {
                let target = WealthCardCycle.payer(statementKey: WealthCal.dayKey(p.date),
                                                   linked: inc.linkedBankMilestoneId, history: hist)
                guard let tid = target, bankIds.contains(tid) else { continue }
                let raw = WealthSchedule.amount(at: p.date, current: inc.amount, sortedHistory: amounts)
                incomesByBank[tid, default: []].append(IncomeRef(income: inc, index: p.index, date: p.date, raw: raw,
                                                                 ownAccount: tid == inc.linkedBankMilestoneId))
            }
        }

        let ctx = BuildContext(today: today, horizon: horizon, rates: rates, book: book,
                               expensesById: expensesById, incomesById: incomesById, stocksById: stocksById,
                               dividendIds: dividendIds, nameById: nameById,
                               expenses: expenses, incomes: incomes, stocks: stocks, excluded: excluded)

        // [v25.565] 卡的效期、接下來要繳的幾期（要確認 #12、理財 30 天、小工具、行事曆、通知）
        let cardMsById = Dictionary(cardMs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for i in cards.indices {
            guard let cm = cardMsById[cards[i].id] else { continue }
            let dues = makeDues(cards[i], milestone: cm, ctx: ctx, bankIds: bankIds)
            cards[i].expiryMonth = expiryMonths?[cm.id] ?? cm.expiryDate.map { WealthCal.startOfMonth($0) }
            cards[i].dues = dues
        }
        // [v25.566] 定存：續存鏈（自動續存算出來、帳本還沒寫進去的那幾期也在）→ 每一期的狀態、動到哪個帳戶的哪一天
        let legacyIds = Set(bankMs.filter { $0.bankAccountType == .fixed }.map(\.id))
        var allTerms: [TimeDeposit] = []
        var depositRefs: [UUID: [DepositRef]] = [:]
        for term in WealthDepositChain.terms(deposits.all, through: today) {
            guard bankIds.contains(term.deposit.bankId) else { continue }
            let made = makeDeposit(term, legacy: legacyIds.contains(term.deposit.bankId), bankIds: bankIds, ctx: ctx)
            allTerms.append(made.term)
            for r in made.refs { depositRefs[r.accountId, default: []].append(r) }
        }

        var accounts: [Account] = []
        for m in bankMs {
            accounts.append(makeAccount(m, isSecurities: false, ctx: ctx,
                                        fixed: fixedByBank[m.id] ?? [], incomes: incomesByBank[m.id] ?? [],
                                        bills: billsByAccount[m.id] ?? [], cardOwed: owedByAccount[m.id] ?? 0,
                                        depositRows: depositRefs[m.id] ?? []))
        }
        for m in securityMs {
            accounts.append(makeAccount(m, isSecurities: true, ctx: ctx, fixed: [], incomes: [], bills: [], cardOwed: 0,
                                        depositRows: []))
        }
        // [v25.566] 每個帳戶的定存（沒開始、存著、到期待決定；照到期日，沒有到期日的最後）
        let currentTerms: [TimeDeposit] = orderTerms(allTerms.filter { $0.status != .ended })
        for i in accounts.indices where !accounts[i].isSecurities {
            let id = accounts[i].id
            let mine = currentTerms.filter { $0.accountId == id }
            accounts[i].timeDeposits = mine
            var ntd: Double = 0
            var unknownDeposit: [String] = []
            for t in mine where t.countsSeparately {
                if let v = t.ntd {
                    ntd += v
                } else if (t.status == .active || t.status == .waiting) && !unknownDeposit.contains(t.code) {
                    unknownDeposit.append(t.code)
                }
            }
            accounts[i].depositNTD = ntd
            accounts[i].depositUnknownCodes = unknownDeposit
        }

        // 整頁
        var cash: Double = 0, live: Double = 0, fixedDeposit: Double = 0, foreign: Double = 0
        var pending: Double = 0, scheduled: Double = 0
        var unknown: [String] = []
        for a in accounts where !a.isSecurities && !a.hidden && a.countsInCash {
            for (code, value) in a.balances {
                guard let r = rates.known(code) else { continue }
                let v = value * r
                cash += v
                if a.isFixedDeposit { fixedDeposit += v }
                else if code == "NT$" { live += v }
                else { foreign += v }
            }
            for c in a.unknownCodes where !unknown.contains(c) { unknown.append(c) }
            pending += a.pendingSettlement
            scheduled += a.scheduledOut
            // [v25.566] 存著的定存（舊的定存種類帳戶的錢已經在上面那幾格裡，depositNTD 是 0）
            cash += a.depositNTD
            fixedDeposit += a.depositNTD
            for c in a.depositUnknownCodes where !unknown.contains(c) { unknown.append(c) }
        }
        let owed = cards.reduce(0.0) { $0 + $1.owed }
        var brokers = securityMs.map { makeBroker($0, ctx: ctx, bankMs: bankMs) }
        // [v25.567] 證券戶的要交割（交割銀行接下來 30 天）、舊交割紀錄
        for i in brokers.indices {
            brokers[i].dues = brokerDues(brokers[i].id, accounts: accounts, ctx: ctx)
        }
        let insurance = insuranceGroups(accounts: accounts, rates: rates)
        // [v25.567] 保單總表（四個來源去重；不碰帳戶的數字）
        let policyFacts = WealthPolicyFacts.build(milestones: milestones, book: book, expenses: expenses,
                                                  insurances: insurances, vehicles: vehicles,
                                                  realEstates: realEstates, names: nameById,
                                                  cardIds: Set(cardMs.map(\.id)), rates: rates, today: today)
        let checks = makeChecks(cards: cards, accounts: accounts, bankMs: bankMs, unknown: unknown,
                                ctx: ctx, bankIds: bankIds, terms: currentTerms, insurance: insurance,
                                deposits: deposits, brokers: brokers, policies: policyFacts)
        let settlements = makeSettlements(accounts: accounts, ctx: ctx)
        let history = WealthHistory.make(accounts: accounts, cards: cards, deposits: allTerms, rates: rates)

        return WealthFacts(now: now, today: today, accounts: accounts, cards: cards,
                           cash: cash, cashIsApprox: !unknown.isEmpty, live: live, fixedDeposit: fixedDeposit,
                           foreign: foreign, owedCards: owed, pendingSettlement: pending,
                           unknownCodes: unknown, scheduledOut: scheduled, brokers: brokers, checks: checks,
                           settlements: settlements, history: history, timeDeposits: currentTerms,
                           depositInsurance: insurance, policies: policyFacts)
    }

    // MARK: - [v25.566] 定存的零件

    /// 一期定存動到帳戶的一筆（轉定存、定存到期、定存利息、解約；sim_v5.py deposit_refs 照這裡寫）
    private struct DepositRef {
        let id: String
        let accountId: UUID
        let day: Date
        let code: String
        /// 正的＝進帳、負的＝出去
        let delta: Double
        let kind: WealthLedgerRow.Kind
        let title: String
        let termId: UUID
        /// 還沒到、利息是估的（寫「約」）
        let estimate: Bool
    }

    /// 一期定存：狀態、算進存款合計多少、動到哪些帳戶（規則見檔頭 [v25.566]）
    private static func makeDeposit(_ term: WealthDepositChain.Term, legacy: Bool, bankIds: Set<UUID>,
                                    ctx: BuildContext) -> (term: TimeDeposit, refs: [DepositRef]) {
        let d = term.deposit
        let today = ctx.today
        let code = d.code
        let start = WealthCal.day(d.start)
        let maturity: Date? = d.maturityDate
        let closed: Date? = d.closedDate.map { WealthCal.day($0) }
        let mode = d.mode
        let interest = d.estimatedInterest
        let closedInterest: Double = Swift.max(0, d.closedInterest ?? 0)
        // 轉進哪個帳戶：沒填＝自己這個帳戶；填了但那個帳戶刪了＝nil（錢跟著刪掉的帳戶走，不跑回來）
        let payout: UUID?
        if let p = d.payoutId {
            payout = bankIds.contains(p) ? p : nil
        } else {
            payout = d.bankId
        }
        var status: TimeDeposit.Status = .active
        if start > today {
            status = .notStarted
        } else if let c = closed, c <= today {
            status = .ended
        } else if let m = maturity, m <= today {
            status = mode == .decide ? .waiting : .ended
        }
        let accountName = ctx.nameById[d.bankId] ?? "銀行"
        let payoutName: String? = payout.flatMap { ctx.nameById[$0] }
        var ntd: Double? = nil
        if let r = ctx.rates.known(code) {
            switch status {
            case .active: ntd = d.principal * r
            case .waiting: ntd = (d.principal + interest) * r
            case .notStarted, .ended: ntd = 0
            }
        }
        let fromLive = !legacy && d.fromLive == true && !term.isVirtual
        let t = TimeDeposit(id: d.id, accountId: d.bankId, accountName: accountName, code: code, principal: d.principal,
                            rate: d.rate, months: (d.months ?? 0) > 0 ? d.months : nil, start: start,
                            maturity: maturity, mode: mode, payoutId: payout, payoutName: payoutName,
                            fromLive: fromLive, isLegacyAccount: legacy, isVirtual: term.isVirtual,
                            termIndex: term.index, interest: interest, status: status, closedDate: closed,
                            closedInterest: closedInterest, remind: d.remind != false,
                            certificateLast4: d.certificateLast4, ntd: ntd)

        var refs: [DepositRef] = []
        let label = WealthDepositMath.termLabel(months: t.months)
        let key = d.id.uuidString
        func add(_ suffix: String, _ account: UUID, _ day: Date, _ delta: Double, _ kind: WealthLedgerRow.Kind,
                 _ title: String, estimate: Bool) {
            guard Swift.abs(delta) > 0.004 else { return }
            refs.append(DepositRef(id: "td-\(suffix)-\(key)", accountId: account, day: day, code: code, delta: delta,
                                   kind: kind, title: title, termId: d.id, estimate: estimate))
        }
        /// 到期轉活存、提前解約：錢（本金＋利息）轉進 payout
        func pay(_ day: Date, interest got: Double, word: String) {
            let total = d.principal + got
            let future = day > today
            let named = payout == d.bankId ? word : accountName + " " + word
            if legacy {
                // 舊的定存種類帳戶：利息先記進這個帳戶，再整筆轉出（轉進自己＝留在這個帳戶）
                add("int", d.bankId, day, got, .interest, "定存利息", estimate: future)
                if let p = payout, p != d.bankId {
                    add("end-out", d.bankId, day, -total, .timeDeposit, word + "・轉出", estimate: future)
                    add("end-in", p, day, total, .timeDeposit, named, estimate: future)
                }
            } else if let p = payout {
                add("end-in", p, day, total, .timeDeposit, named, estimate: future && got > 0)
            }
        }
        // 起存那天從活存轉出（續存的下一期不轉）
        if fromLive {
            add("out", d.bankId, start, -d.principal, .timeDeposit, "轉定存（" + label + "）", estimate: false)
        }
        if let c = closed {
            pay(c, interest: closedInterest, word: "定存解約")
        } else if let m = maturity {
            let future = m > today
            switch mode {
            case .renewAll:
                // 本息續存：舊的定存種類帳戶要把利息記進存摺（下一期的本金＝本息）；新的不動任何帳戶
                if legacy { add("int", d.bankId, m, interest, .interest, "定存利息（本息續存）", estimate: future) }
            case .renewPrincipal:
                if let p = payout {
                    let named = p == d.bankId ? "定存利息" : accountName + " 定存利息"
                    add("int", p, m, interest, .interest, named, estimate: future)
                }
            case .toLive:
                pay(m, interest: interest, word: "定存到期")
            case .decide:
                break
            }
        }
        return (term: t, refs: refs)
    }

    /// 照到期日（同一天照起存日；沒有到期日的最後；sort 不保證穩定，帶著位置比）
    private static func orderTerms(_ list: [TimeDeposit]) -> [TimeDeposit] {
        list.enumerated().sorted { x, y in
            let a = x.element, b = y.element
            switch (a.maturity, b.maturity) {
            case let (ma?, mb?):
                if ma != mb { return ma < mb }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
            if a.start != b.start { return a.start < b.start }
            return x.offset < y.offset
        }.map { $0.element }
    }

    /// 同一家銀行存摺上＋定存超過 300 萬的（存款保險；收起來的、不算進合計的帳戶不算，人民幣不保、黃金存摺不算：isInsured）
    private static func insuranceGroups(accounts: [Account], rates: FinanceRates) -> [InsuranceGroup] {
        var order: [String] = []
        var totals: [String: Double] = [:]
        var names: [String: String] = [:]
        var ids: [String: [UUID]] = [:]
        for a in accounts where !a.isSecurities && !a.hidden && a.countsInCash {
            let key = bankKey(a.bankName)
            if totals[key] == nil {
                order.append(key)
                totals[key] = 0
                names[key] = a.bankName
                ids[key] = []
            }
            var v: Double = 0
            for (code, value) in a.balances where isInsured(code) {
                if let r = rates.known(code) { v += value * r }
            }
            for t in a.timeDeposits where t.countsSeparately && isInsured(t.code) {
                v += t.ntd ?? 0
            }
            totals[key, default: 0] += v
            ids[key, default: []].append(a.id)
        }
        var out: [InsuranceGroup] = []
        for k in order {
            guard let total = totals[k], total > insuranceLimit else { continue }
            out.append(InsuranceGroup(id: k, bankName: names[k] ?? k, total: total, accountIds: ids[k] ?? []))
        }
        return out
    }

    // MARK: - build 的零件

    /// [v25.565] 「含 Netflix、Spotify」那幾個名字：哪一天、哪一筆記帳、叫什麼
    private struct DueName {
        let date: Date
        let id: UUID
        let title: String
    }

    /// [v25.565] 一張卡接下來要繳的幾期（sim_v4.py make_dues 照這裡寫）：
    /// ① 已經結帳、還沒繳的（要繳／逾期）：帳單金額（自動扣最低＝最低應繳）
    /// ② 這一期（還沒結帳）：到今天刷的＋結帳日前還會扣的定期扣款（約）
    /// ③ 下一期：這一期結帳日以後、下一個結帳日以前還會扣的定期扣款（約；0 不列）
    /// 定期扣款＝記帳週期性固定支出、那一期那天刷這張卡（linkFrom 有歷史照歷史）。照截止日排
    private static func makeDues(_ card: Card, milestone c: LifeMilestone, ctx: BuildContext,
                                 bankIds: Set<UUID>) -> [WealthCardDue] {
        let b = card.billingDay
        let p = card.paymentDay
        let close1 = WealthCal.day(card.nextClose)
        let close2 = WealthCardCycle.nextClose(after: close1, billingDay: b)
        let due2 = WealthCardCycle.dueDate(close: close2, billingDay: b, paymentDay: p)
        let prefs = ctx.book.card(c.id)

        // 今天以後、下一個結帳日以前還會刷這張卡的定期扣款
        var projected1: Double = 0
        var projected2: Double = 0
        var extra1: [DueName] = []
        var extra2: [DueName] = []
        for e in ctx.expenses where e.expenseType == .fixed && e.recurrence != nil {
            let hist = ctx.book.links(e.id)
            let mentioned = e.linkedCreditCardMilestoneId == card.id
                || (hist ?? []).contains(where: { (seg: WealthPayFrom) -> Bool in seg.accountId == card.id })
            guard mentioned else { continue }
            let amounts = e.amountHistory.sorted { $0.date < $1.date }
            for per in WealthSchedule.fixedPeriods(e, through: close2) {
                let d = WealthCal.day(per.date)
                guard d > ctx.today, recurringTarget(e, at: per.date, history: hist) == card.id else { continue }
                let raw = WealthSchedule.amount(at: per.date, current: e.amount, sortedHistory: amounts)
                let v = WealthSchedule.ntd(of: e, raw: raw, rates: ctx.rates)
                let n = DueName(date: d, id: e.id, title: e.title)
                if d <= close1 {
                    projected1 += v
                    extra1.append(n)
                } else {
                    projected2 += v
                    extra2.append(n)
                }
            }
        }

        func payerFor(_ key: String) -> UUID? {
            let raw = WealthCardCycle.payer(statementKey: key, linked: c.linkedBankMilestoneId, history: prefs.payFrom)
            return raw.flatMap { bankIds.contains($0) ? $0 : nil }
        }

        var out: [WealthCardDue] = []
        // ① 已經結帳、還沒繳的
        for s in card.statements where s.status == .due || s.status == .overdue {
            let amount = card.payMode == .autoMin ? Swift.min(s.minimumDue, s.amount) : s.amount
            guard amount > 0.5 else { continue }
            let n = dueNames(card, from: WealthCal.day(s.start), to: WealthCal.day(s.close), extra: [], ctx: ctx)
            out.append(WealthCardDue(cardId: card.id, cardName: card.name, key: s.key, close: s.close, due: s.due,
                                     amount: amount, isEstimate: false, status: s.status, payMode: card.payMode,
                                     payerId: s.payerId, payerName: s.payerId.flatMap { ctx.nameById[$0] },
                                     recurringNames: n.names, recurringIds: n.ids))
        }
        // ② 這一期
        let s1 = card.statements.first { WealthCal.day($0.close) == close1 && $0.status == .unbilled }
        let total1 = (s1?.amount ?? 0) + projected1
        let amount1 = card.payMode == .autoMin ? Swift.min((total1 * 0.1).rounded(), total1) : total1
        if amount1 > 0.5 {
            let key1 = WealthCal.monthKey(close1)
            let start1 = WealthCal.addDays(1, to: WealthCardCycle.previousClose(close1, billingDay: b))
            let n = dueNames(card, from: start1, to: close1, extra: extra1, ctx: ctx)
            let payer1 = payerFor(key1)
            out.append(WealthCardDue(cardId: card.id, cardName: card.name, key: key1, close: close1, due: card.nextDue,
                                     amount: amount1, isEstimate: true, status: .unbilled, payMode: card.payMode,
                                     payerId: payer1, payerName: payer1.flatMap { ctx.nameById[$0] },
                                     recurringNames: n.names, recurringIds: n.ids))
        }
        // ③ 下一期（〔算到下一期〕、前期未繳長出來的那一期也算進來）
        let s2 = card.statements.first { WealthCal.day($0.close) == close2 }
        let total2 = (s2?.amount ?? 0) + projected2
        let amount2 = card.payMode == .autoMin ? Swift.min((total2 * 0.1).rounded(), total2) : total2
        if amount2 > 0.5 {
            let key2 = WealthCal.monthKey(close2)
            let n = dueNames(card, from: WealthCal.addDays(1, to: close1), to: close2, extra: extra2, ctx: ctx)
            let payer2 = payerFor(key2)
            out.append(WealthCardDue(cardId: card.id, cardName: card.name, key: key2, close: close2, due: due2,
                                     amount: amount2, isEstimate: true, status: .unbilled, payMode: card.payMode,
                                     payerId: payer2, payerName: payer2.flatMap { ctx.nameById[$0] },
                                     recurringNames: n.names, recurringIds: n.ids))
        }
        return out.sorted { x, y in x.due != y.due ? x.due < y.due : x.key < y.key }
    }

    /// [v25.565] 這一期裡刷這張卡的定期扣款叫什麼（照日期、同一筆只算一次；extra＝今天以後還會扣的）
    private static func dueNames(_ card: Card, from start: Date, to end: Date, extra: [DueName],
                                 ctx: BuildContext) -> (names: [String], ids: [UUID]) {
        var list: [DueName] = []
        for en in card.entries {
            let d = WealthCal.day(en.date)
            guard d >= start, d <= end, let e = ctx.expensesById[en.expenseId],
                  e.expenseType == .fixed, e.recurrence != nil else { continue }
            list.append(DueName(date: d, id: e.id, title: e.title))
        }
        list += extra
        // 照日期；同一天照原本的先後（sort 不保證穩定，帶著位置比）
        let ordered = list.enumerated().sorted { x, y in
            if x.element.date != y.element.date { return x.element.date < y.element.date }
            return x.offset < y.offset
        }.map { $0.element }
        var names: [String] = []
        var ids: [UUID] = []
        for n in ordered where !ids.contains(n.id) {
            ids.append(n.id)
            names.append(n.title)
        }
        return (names: names, ids: ids)
    }

    /// [v25.565] 接下來的交割（sim_v4.py make_settlements）：沒收起來的銀行帳戶，35 天內每天每幣別的股票款買賣相抵；
    /// 證券戶名＝第一檔股票選的證券戶
    private static func makeSettlements(accounts: [Account], ctx: BuildContext) -> [WealthSettlementDue] {
        var out: [WealthSettlementDue] = []
        for a in accounts where !a.isSecurities && !a.hidden {
            var keys: [String] = []
            var net: [String: Double] = [:]
            var dayOf: [String: Date] = [:]
            var codeOf: [String: String] = [:]
            var stockIdsOf: [String: [UUID]] = [:]
            for row in a.upcoming where row.kind == .stockBuy || row.kind == .stockSell {
                let d = WealthCal.day(row.date)
                let k = WealthCal.dayKey(d) + "|" + row.code
                if net[k] == nil {
                    keys.append(k)
                    net[k] = 0
                    dayOf[k] = d
                    codeOf[k] = row.code
                    stockIdsOf[k] = []
                }
                let signed: Double = row.kind == .stockBuy ? row.amount : -row.amount
                net[k, default: 0] += signed
                if let sid = row.stockId, !(stockIdsOf[k] ?? []).contains(sid) {
                    stockIdsOf[k, default: []].append(sid)
                }
            }
            for k in keys {
                guard let v = net[k], Swift.abs(v) > 0.004, let d = dayOf[k], let code = codeOf[k] else { continue }
                let ids: [UUID] = stockIdsOf[k] ?? []
                let brokerId: UUID? = ids.first.flatMap { sid -> UUID? in ctx.stocksById[sid]?.linkedSecuritiesMilestoneId }
                let broker: String? = brokerId.flatMap { ctx.nameById[$0] }
                let ntd: Double? = ctx.rates.known(code).map { r -> Double in Swift.abs(v) * r }
                out.append(WealthSettlementDue(accountId: a.id, accountName: a.name, brokerName: broker, day: d,
                                               code: code, amount: Swift.abs(v), ntd: ntd, isOutflow: v > 0,
                                               stockIds: ids))
            }
        }
        return out.enumerated().sorted { x, y in
            if x.element.day != y.element.day { return x.element.day < y.element.day }
            return x.offset < y.offset
        }.map { $0.element }
    }

    /// 一期帳單動到哪個帳戶的哪一天、多少（已繳：那天從那個帳戶；還沒繳：截止日從扣款帳戶；逾期：明天）
    private struct BillRef {
        let accountId: UUID
        let cardId: UUID
        let cardName: String
        let statement: WealthStatement
        let day: Date
        let amount: Double
        let isEstimate: Bool
        let overdue: Bool
    }

    /// 直接扣這個帳戶的一期固定支出（ownAccount：記帳那筆現在就扣這裡，幣別照它的 linkedBankCurrency；改帳戶以前的那幾期一律台幣）
    private struct FixedRef {
        let expense: Expense
        let index: Int
        let date: Date
        let raw: Double
        let ownAccount: Bool
    }

    /// 入這個帳戶的一期收入
    private struct IncomeRef {
        let income: Income
        let index: Int
        let date: Date
        let raw: Double
        let ownAccount: Bool
    }

    private struct BuildContext {
        let today: Date
        let horizon: Date
        let rates: FinanceRates
        let book: WealthBook
        let expensesById: [UUID: Expense]
        let incomesById: [UUID: Income]
        let stocksById: [UUID: Stock]
        let dividendIds: Set<UUID>
        let nameById: [UUID: String]
        let expenses: [Expense]
        let incomes: [Income]
        let stocks: [Stock]
        /// 要確認 #4「這筆不算」的記帳
        let excluded: Set<String>
    }

    /// 存摺上的一筆（排好照日期累加）
    private struct Event {
        let day: Date
        let code: String
        /// 加減（對存摺不用）
        let delta: Double
        /// 對存摺：存摺上的數字
        let anchor: Double?
        /// 同一天的先後（真的紀錄照存的順序在前，展開的在後；對存摺一律最後）
        let seq: Int
        let row: WealthLedgerRow
    }

    /// [v25.564] 一期帳單對銀行的影響（沒有就 nil）
    private static func billRef(cardId: UUID, cardName: String, statement s: WealthStatement, mode: WealthPayMode,
                                today: Date) -> BillRef? {
        switch s.status {
        case .paid, .assumedPaid:
            guard let from = s.paidFrom, s.paidAmount > 0.004 else { return nil }
            return BillRef(accountId: from, cardId: cardId, cardName: cardName, statement: s,
                           day: WealthCal.day(s.paidOn ?? s.due), amount: s.paidAmount, isEstimate: false, overdue: false)
        case .due, .unbilled:
            guard let payer = s.payerId, s.amount > 0.004 else { return nil }
            let amount = mode == .autoMin ? Swift.min(s.minimumDue, s.amount) : s.amount
            // 自己繳／每次問我的卡截止日當天還沒標：錢還沒離開帳戶，算明天（不然今天的存摺上先扣了、要繳裡又算一次）
            let dueDay = WealthCal.day(s.due)
            let day = dueDay > today ? dueDay : WealthCal.addDays(1, to: today)
            return BillRef(accountId: payer, cardId: cardId, cardName: cardName, statement: s,
                           day: day, amount: amount, isEstimate: s.status == .unbilled, overdue: false)
        case .overdue:
            guard let payer = s.payerId, s.amount > 0.004 else { return nil }
            return BillRef(accountId: payer, cardId: cardId, cardName: cardName, statement: s,
                           day: WealthCal.addDays(1, to: today), amount: s.amount, isEstimate: false, overdue: true)
        }
    }

    private static func makeCard(_ c: LifeMilestone, name: String, entries: [WealthCardEntry],
                                 statements stmts: [WealthStatement], today: Date, book: WealthBook,
                                 bankIds: Set<UUID>, nameById: [UUID: String]) -> Card {
        let b = WealthCardCycle.billingDay(c.billingDay)
        let p = WealthCardCycle.paymentDay(c.paymentDay)
        let prefs = book.card(c.id)
        let acct = book.account(c.id)
        let nextClose = WealthCardCycle.statementClose(for: today, billingDay: b)
        let nextDue = WealthCardCycle.dueDate(close: nextClose, billingDay: b, paymentDay: p)
        var due: Double = 0
        var overdue: Double = 0
        var dueStatement: WealthStatement? = nil
        var unbilled: Double = 0
        var unbilledCount = 0
        var lastPaid: WealthStatement? = nil
        for s in stmts {
            switch s.status {
            case .unbilled:
                unbilled += s.amount
                unbilledCount += s.count
            case .due, .overdue:
                due += s.amount
                if s.status == .overdue { overdue += s.amount }
                if dueStatement == nil { dueStatement = s }
            case .paid, .assumedPaid:
                lastPaid = s
            }
        }
        let rawPayer = WealthCardCycle.payer(statementKey: WealthCal.monthKey(nextClose),
                                             linked: c.linkedBankMilestoneId, history: prefs.payFrom)
        let payer: UUID? = rawPayer.flatMap { bankIds.contains($0) ? $0 : nil }
        let limit: Double? = (c.creditLimit ?? 0) > 0 ? c.creditLimit : nil
        let issuer: String? = c.bankName.flatMap { raw -> String? in
            let t = raw.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }
        let last4: String? = c.cardLastFour.flatMap { raw -> String? in
            let t = raw.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }
        let face = Swift.min(Swift.max(prefs.faceColor ?? defaultFaceColor(c.id), 0), 5)
        return Card(id: c.id, name: name, isDisabled: c.isDisabled == true, limit: limit,
                    billingDay: b, paymentDay: p,
                    billingDayMissing: c.billingDay == nil, paymentDayMissing: c.paymentDay == nil,
                    payerId: payer, payerName: payer.flatMap { nameById[$0] },
                    statements: stmts, entries: entries, due: due, dueStatement: dueStatement,
                    unbilled: unbilled, unbilledCount: unbilledCount,
                    nextClose: nextClose, nextDue: nextDue, lastPaid: lastPaid,
                    issuer: issuer, nickname: acct.trimmedNickname, last4: last4, faceColor: face,
                    payMode: prefs.mode, overdue: overdue, sortIndex: acct.sortIndex, closedDate: acct.closedDate,
                    linkedRaw: c.linkedBankMilestoneId)
    }

    /// 「@GoGo 沒填結帳日，先當每月 25 日結帳、隔月 15 日繳」
    private static func missingDaysText(_ c: Card) -> String {
        let payWhen = c.paymentDay <= c.billingDay ? "隔月" : "當月"
        if c.billingDayMissing && c.paymentDayMissing {
            return "\(c.name) 沒填結帳日和繳款截止日，先當每月 \(c.billingDay) 日結帳、\(payWhen) \(c.paymentDay) 日繳"
        }
        if c.billingDayMissing {
            return "\(c.name) 沒填結帳日，先當每月 \(c.billingDay) 日結帳"
        }
        return "\(c.name) 沒填繳款截止日，先當\(payWhen) \(c.paymentDay) 日繳"
    }

    /// 真的紀錄是哪一種、標題寫什麼。[v25.566] accountId：這筆記在哪個帳戶（換匯＝同一個帳戶兩個幣別互轉）
    private static func classify(_ dep: BankDeposit, accountId: UUID,
                                 ctx: BuildContext) -> (kind: WealthLedgerRow.Kind, title: String) {
        if dep.isAnchor { return (.anchor, "對存摺") }
        if dep.isAdjust { return (.legacyAdjust, "沖正") }
        if dep.isTransfer, dep.counterpartyId == accountId {
            // [v25.566] 換匯：同一個帳戶的台幣、外幣兩格互轉（v2 的轉帳綁定，兩筆同一個 transferPairId）
            if dep.isWithdrawal { return (.transferOut, "換匯（換出）") }
            return (.transferIn, "換匯（換入）")
        }
        if dep.isTransfer {
            let other = dep.counterpartyId.flatMap { ctx.nameById[$0] } ?? "別的帳戶"
            if dep.isWithdrawal { return (.transferOut, "轉給 \(other)") }
            return (.transferIn, "來自 \(other)")
        }
        if dep.kind == BankDeposit.kindInterest { return (.interest, "利息") }
        if dep.kind == BankDeposit.kindFee { return (.fee, "手續費") }
        if let sid = dep.linkedStockId {
            let name = ctx.stocksById[sid]?.name ?? "股票"
            if ctx.dividendIds.contains(dep.id) { return (.dividend, "\(name) 股利") }
            if dep.isWithdrawal { return (.stockBuy, "買 \(name)") }
            return (.stockSell, "賣 \(name)")
        }
        if let lid = dep.linkedExpenseId {
            if let e = ctx.expensesById[lid] { return (.expense, e.title) }
            if let i = ctx.incomesById[lid] { return (.income, i.title) }
        }
        if dep.isWithdrawal { return (.withdrawal, "提款") }
        return (.deposit, "存款")
    }

    private static func makeAccount(_ m: LifeMilestone, isSecurities: Bool, ctx: BuildContext,
                                    fixed: [FixedRef], incomes: [IncomeRef], bills: [BillRef],
                                    cardOwed: Double, depositRows: [DepositRef]) -> Account {
        let rates = ctx.rates
        let prefs = ctx.book.account(m.id)
        var events: [Event] = []

        // ① 真的紀錄（存提款、對存摺、轉帳、記帳一次性、股票交割與股利）
        let deposits = m.bankDeposits ?? []
        var pendingByDay: [Date: [String: Double]] = [:]
        var scheduledByCode: [String: Double] = [:]
        for (i, dep) in deposits.enumerated() {
            if isReplaced(dep, expensesById: ctx.expensesById, incomesById: ctx.incomesById,
                          stocksById: ctx.stocksById) { continue }
            // [v25.564] 要確認 #4「這筆不算」：像繳卡費的那筆記帳不扣帳戶
            if let lid = dep.linkedExpenseId, ctx.excluded.contains(lid.uuidString) { continue }
            let day = WealthCal.day(dep.date)
            let code = norm(dep.currencyCode)
            // 待交割：日期還沒到的股票款（同一天買賣相抵；股利不算）
            if !isSecurities, dep.linkedStockId != nil, !ctx.dividendIds.contains(dep.id), !dep.isTransfer,
               day > ctx.today {
                pendingByDay[day, default: [:]][code, default: 0] += dep.isWithdrawal ? dep.amount : -dep.amount
            }
            // [v25.564] 已經排定、還沒到的提款（刪卡寫回的那幾期、你記的未來日期提款）：算進還沒扣
            if !isSecurities, day > ctx.today, dep.isWithdrawal, dep.linkedStockId == nil, !dep.isAnchor {
                scheduledByCode[code, default: 0] += dep.amount
            }
            guard day <= ctx.horizon else { continue }
            let c = classify(dep, accountId: m.id, ctx: ctx)
            let anchorValue: Double? = dep.isAnchor ? dep.anchorAmount : nil
            let row = WealthLedgerRow(
                id: dep.id.uuidString, date: dep.date, code: code,
                amount: anchorValue ?? dep.amount, isOutflow: dep.isWithdrawal, kind: c.kind, title: c.title,
                note: dep.note, depositId: dep.id,
                expenseId: dep.linkedExpenseId.flatMap { lid -> UUID? in ctx.expensesById[lid] == nil ? nil : lid },
                incomeId: dep.linkedExpenseId.flatMap { lid -> UUID? in ctx.incomesById[lid] == nil ? nil : lid },
                stockId: dep.linkedStockId, transferPairId: dep.transferPairId)
            events.append(Event(day: day, code: code, delta: dep.isWithdrawal ? -dep.amount : dep.amount,
                                anchor: anchorValue, seq: i, row: row))
        }

        // ② 直接扣這裡的週期性固定支出（期數一次算、金額照那一期當時；改帳戶以前的那幾期一律台幣）
        var seq = 100_000
        for f in fixed {
            let exp = f.expense
            let ntd = WealthSchedule.ntd(of: exp, raw: f.raw, rates: rates)
            let original: (amount: Double, code: String)? = exp.originalCurrencyAmount.map { (amount: f.raw, code: $0.code) }
            let into = f.ownAccount ? (exp.linkedBankCurrency ?? "NT$") : "NT$"
            let w = rates.accountAmount(ntd: ntd, original: original, into: into)
            let code = norm(w.code)
            let row = WealthLedgerRow(
                id: "fx-\(exp.id.uuidString)-\(f.index)", date: f.date, code: code, amount: w.amount,
                isOutflow: true, kind: .fixedExpense, title: exp.title, expenseId: exp.id)
            events.append(Event(day: WealthCal.day(f.date), code: code, delta: -w.amount, anchor: nil,
                                seq: seq, row: row))
            seq += 1
        }

        // ③ 入這裡的月薪、年薪（期數一次算、金額照那一期當時）
        for r in incomes {
            let inc = r.income
            let into = r.ownAccount ? (inc.linkedBankCurrency ?? "NT$") : "NT$"
            let w = rates.accountAmount(ntd: r.raw, into: into)
            let code = norm(w.code)
            let row = WealthLedgerRow(
                id: "in-\(inc.id.uuidString)-\(r.index)", date: r.date, code: code, amount: w.amount,
                isOutflow: false, kind: .recurringIncome, title: inc.title, incomeId: inc.id)
            events.append(Event(day: WealthCal.day(r.date), code: code, delta: w.amount, anchor: nil,
                                seq: seq, row: row))
            seq += 1
        }

        // ④ 信用卡帳單（v3：已繳的照那天、那個帳戶、繳的數字；還沒繳的在截止日；逾期的明天）
        for bill in bills {
            let s = bill.statement
            // [v25.564] 標成已繳、日子還沒到（預約繳款）：那天才離開帳戶，先算進已經排定的提款（不然這幾天扣完能用多出這一筆，
            // 到那天又掉回去；驗證 build/v3/verify/data_edges.py C）
            if s.isPaid, !isSecurities, bill.day > ctx.today {
                scheduledByCode["NT$", default: 0] += bill.amount
            }
            guard bill.day <= ctx.horizon else { continue }
            let title = "\(bill.cardName) \(s.label)" + (bill.overdue ? "（還沒繳）" : "")
            let row = WealthLedgerRow(
                id: "bill-\(bill.cardId.uuidString)-\(s.key)", date: bill.day, code: "NT$", amount: bill.amount,
                isOutflow: true, kind: .cardBill, title: title,
                cardId: bill.cardId, statementKey: s.key, isEstimate: bill.isEstimate)
            events.append(Event(day: bill.day, code: "NT$", delta: -bill.amount, anchor: nil, seq: seq, row: row))
            seq += 1
        }

        // ⑤ [v25.566] 定存：起存那天從活存轉出、到期轉活存、本金續存的利息、提前解約（WealthFacts 算的，不是 BankDeposit）
        var depositCodes: [String] = []
        for r in depositRows {
            let code = norm(r.code)
            if !depositCodes.contains(code) { depositCodes.append(code) }
            guard r.day <= ctx.horizon else { continue }
            let row = WealthLedgerRow(
                id: r.id, date: r.day, code: code, amount: Swift.abs(r.delta), isOutflow: r.delta < 0,
                kind: r.kind, title: r.title, isEstimate: r.estimate, timeDepositId: r.termId)
            events.append(Event(day: r.day, code: code, delta: r.delta, anchor: nil, seq: seq, row: row))
            seq += 1
        }

        // 照日期累加：同一天先算每一筆，對存摺最後（記的是那天結束時）
        events.sort { a, b in
            if a.day != b.day { return a.day < b.day }
            let aa = a.anchor != nil, bb = b.anchor != nil
            if aa != bb { return !aa }
            return a.seq < b.seq
        }
        var running: [String: Double] = [:]
        var todayBalances: [String: Double] = [:]
        var crossedToday = false
        var past: [WealthLedgerRow] = []
        var future: [WealthLedgerRow] = []
        var lastAnchor: Date? = nil
        for e in events {
            if !crossedToday && e.day > ctx.today {
                todayBalances = running
                crossedToday = true
            }
            var row = e.row
            let before = running[e.code] ?? 0
            if let a = e.anchor {
                running[e.code] = a
                row.anchorDiff = ((a - before) * 100).rounded() / 100
                if e.day <= ctx.today { lastAnchor = e.day }
            } else {
                running[e.code] = before + e.delta
            }
            row.balanceAfter = running[e.code] ?? 0
            if e.day <= ctx.today { past.append(row) } else { future.append(row) }
        }
        if !crossedToday { todayBalances = running }

        // 台幣合計（查不到匯率的不算）
        var ntdTotal: Double = 0
        var unknown: [String] = []
        for (code, value) in todayBalances {
            if let r = rates.known(code) { ntdTotal += value * r }
            else if Swift.abs(value) > 0.004 { unknown.append(code) }
        }
        unknown.sort()

        // [v25.564] 接下來 30 天最低、第一次不夠扣（台幣；從今天的數字開始，含第 30 天）
        let windowEnd = WealthCal.addDays(lowWindowDays, to: ctx.today)
        var lowest: Double? = nil
        var lowestDate: Date? = nil
        var shortage: WealthShortage? = nil
        if events.contains(where: { $0.day > ctx.today && $0.day <= windowEnd }) {
            var run = todayBalances
            func ntdOf(_ b: [String: Double]) -> Double {
                var t: Double = 0
                for (code, value) in b { if let r = rates.known(code) { t += value * r } }
                return t
            }
            var low = ntdOf(run)
            var lowDay = ctx.today
            for e in events where e.day > ctx.today && e.day <= windowEnd {
                let before = run[e.code] ?? 0
                if let a = e.anchor { run[e.code] = a } else { run[e.code] = before + e.delta }
                let after = run[e.code] ?? 0
                if shortage == nil, e.anchor == nil, e.delta < 0, before >= -0.5, after < -0.5 {
                    shortage = WealthShortage(date: e.day, code: e.code, title: e.row.title, kind: e.row.kind,
                                              amount: -e.delta, before: before, short: -after)
                }
                let v = ntdOf(run)
                if v < low { low = v; lowDay = e.day }
            }
            lowest = low
            lowestDate = lowDay
        }

        // 待交割、已經排定的提款（台幣）
        var pendingNTD: Double = 0
        for (_, byCode) in pendingByDay {
            for (code, net) in byCode where net > 0 {
                if let r = rates.known(code) { pendingNTD += net * r }
            }
        }
        var scheduledNTD: Double = 0
        for (code, v) in scheduledByCode {
            if let r = rates.known(code) { scheduledNTD += v * r }
        }

        // 最近 90 天的進出筆數（對存摺不算）
        let recentFrom = WealthCal.addDays(-90, to: ctx.today)
        let recentCount = past.filter { $0.kind != .anchor && WealthCal.day($0.date) >= recentFrom }.count
        let next30 = future.filter { WealthCal.day($0.date) <= windowEnd }

        // [v25.566] 定存動到這個帳戶的幣別也列進來（美金定存到期轉進台幣帳戶：那個帳戶就有美金那一格）
        let codes = WealthFacts.currencies(forAccount: m, expenses: ctx.expenses, incomes: ctx.incomes,
                                           stocks: ctx.stocks, extra: (prefs.currencies ?? []) + depositCodes)
        var balances = todayBalances
        for c in codes where balances[c] == nil { balances[c] = 0 }

        // 帳號末 4 碼：帳本 → 里程碑帳號的最後 4 個數字
        let last4: String? = {
            if let l = prefs.accountLast4?.trimmingCharacters(in: .whitespaces), !l.isEmpty { return l }
            let digits = (m.accountNumber ?? "").filter { $0.isNumber }
            guard !digits.isEmpty else { return nil }
            return String(digits.suffix(4))
        }()

        return Account(
            id: m.id, name: ctx.nameById[m.id] ?? bankName(of: m), bankName: bankName(of: m),
            nickname: prefs.trimmedNickname, isSecurities: isSecurities,
            isFixedDeposit: m.bankAccountType == .fixed,
            hidden: prefs.hidden == true, countsInCash: prefs.countInCash ?? true,
            currencies: codes, balances: balances, ntdTotal: ntdTotal, unknownCodes: unknown,
            cardOwed: cardOwed, pendingSettlement: isSecurities ? 0 : pendingNTD,
            lastAnchorDate: lastAnchor, ledger: Array(past.reversed()), upcoming: future,
            lowestNTD: lowest, lowestDate: lowestDate,
            last4: last4, sortIndex: prefs.sortIndex, purpose: prefs.purpose, closedDate: prefs.closedDate,
            isForeignType: m.bankAccountType == .foreign, openedDate: m.date,
            scheduledOut: isSecurities ? 0 : scheduledNTD, shortage: isSecurities ? nil : shortage,
            next30: next30, recentCount: recentCount)
    }

    // MARK: - [v25.564] 證券戶（券商名片）

    private static func makeBroker(_ m: LifeMilestone, ctx: BuildContext, bankMs: [LifeMilestone]) -> Broker {
        let mine = ctx.stocks.filter { $0.linkedSecuritiesMilestoneId == m.id }
        let held = mine.filter { !$0.isSold }.sorted { $0.marketValue > $1.marketValue }
        let bankIds = Set(bankMs.map(\.id))
        // 交割銀行：帳本填的 → 這個證券戶的股票最常用的交割帳戶（同樣多挑 id 字串小的，每次一樣）
        var settlement: UUID? = ctx.book.account(m.id).settlementBankId
        let fromBook = settlement.map { bankIds.contains($0) } ?? false
        if settlement == nil {
            var counts: [UUID: Int] = [:]
            for s in mine { if let b = s.linkedBankMilestoneId { counts[b, default: 0] += 1 } }
            var best: UUID? = nil
            var bestCount = 0
            for (id, n) in counts.sorted(by: { $0.key.uuidString < $1.key.uuidString }) where n > bestCount {
                best = id
                bestCount = n
            }
            settlement = best
        }
        if let s = settlement, !bankIds.contains(s) { settlement = nil }
        // 下一筆交割：銀行帳戶裡這些股票、日期還沒到的（同一天買賣相抵；股利不算）
        let stockIds = Set(mine.map(\.id))
        var byDay: [Date: Double] = [:]
        for b in bankMs {
            for dep in b.bankDeposits ?? [] {
                guard let sid = dep.linkedStockId, stockIds.contains(sid), !ctx.dividendIds.contains(dep.id),
                      !dep.isTransfer else { continue }
                let day = WealthCal.day(dep.date)
                guard day > ctx.today else { continue }
                let r = ctx.rates.known(norm(dep.currencyCode)) ?? 1
                byDay[day, default: 0] += (dep.isWithdrawal ? dep.amount : -dep.amount) * r
            }
        }
        let nextDay: Date? = byDay.keys.sorted().first
        var b = Broker(id: m.id, name: ctx.nameById[m.id] ?? bankName(of: m), settlementBankId: settlement,
                       settlementName: settlement.flatMap { ctx.nameById[$0] },
                       holdingIds: held.map(\.id),
                       marketValue: held.reduce(0.0) { $0 + $1.marketValue },
                       cost: held.reduce(0.0) { $0 + $1.totalCost },
                       nextSettlementDate: nextDay,
                       nextSettlementAmount: nextDay.flatMap { byDay[$0] } ?? 0)
        b.settlementFromBook = fromBook
        // [v25.567] 以前記在證券戶身上的交割紀錄（股票表單以前可以選證券戶當交割帳戶；#16、證券戶頁 ④⑤）：
        // linkedStockId 的那幾筆（含股利），不管股票還在不在；合計換台幣（查不到匯率當 1，只拿來寫一句話）
        var legacyIds: [UUID] = []
        var legacyTotal: Double = 0
        var legacyLive = 0
        for dep in m.bankDeposits ?? [] where dep.linkedStockId != nil && !dep.isTransfer && !dep.isAnchor {
            legacyIds.append(dep.id)
            let r = ctx.rates.known(norm(dep.currencyCode)) ?? 1
            legacyTotal += (dep.isWithdrawal ? -dep.amount : dep.amount) * r
            if let sid = dep.linkedStockId, ctx.stocksById[sid] != nil { legacyLive += 1 }
        }
        b.legacyIds = legacyIds
        b.legacyCount = legacyIds.count
        b.legacyTotal = legacyTotal
        b.legacyLiveCount = legacyLive
        return b
    }

    /// [v25.567] 證券戶頁 ② 要交割（sim_v6.py broker_dues）：沒收起來的銀行帳戶裡，這個證券戶的股票接下來 30 天（含第 30 天）
    /// 的交割，每天每幣別買賣相抵；扣之前＝那天第一筆交割那一列之前的存摺上；夠不夠只看交割這幾筆（同一天別的進出不算）
    private static func brokerDues(_ brokerId: UUID, accounts: [Account], ctx: BuildContext) -> [WealthBrokerDue] {
        let mine = ctx.stocks.filter { $0.linkedSecuritiesMilestoneId == brokerId }
        let ids = Set(mine.map(\.id))
        guard !ids.isEmpty else { return [] }
        let windowEnd = WealthCal.addDays(lowWindowDays, to: ctx.today)
        var out: [WealthBrokerDue] = []
        for a in accounts where !a.isSecurities && !a.hidden {
            var keys: [String] = []
            var net: [String: Double] = [:]
            var before: [String: Double] = [:]
            var dayOf: [String: Date] = [:]
            var codeOf: [String: String] = [:]
            var buys: [String: [UUID]] = [:]
            var sells: [String: [UUID]] = [:]
            for row in a.upcoming where row.kind == .stockBuy || row.kind == .stockSell {
                guard let sid = row.stockId, ids.contains(sid) else { continue }
                let d = WealthCal.day(row.date)
                guard d <= windowEnd else { continue }
                let k = WealthCal.dayKey(d) + "|" + row.code
                if net[k] == nil {
                    keys.append(k)
                    net[k] = 0
                    dayOf[k] = d
                    codeOf[k] = row.code
                    // 這一列之前的存摺上＝這一列之後的 − 這一列（扣的加回來、入的扣掉）
                    before[k] = row.balanceAfter + (row.isOutflow ? row.amount : -row.amount)
                }
                if row.kind == .stockBuy {
                    net[k, default: 0] += row.amount
                    if !(buys[k] ?? []).contains(sid) { buys[k, default: []].append(sid) }
                } else {
                    net[k, default: 0] -= row.amount
                    if !(sells[k] ?? []).contains(sid) { sells[k, default: []].append(sid) }
                }
            }
            for k in keys {
                guard let v = net[k], Swift.abs(v) > 0.004, let d = dayOf[k], let code = codeOf[k] else { continue }
                let b0 = before[k] ?? 0
                let isOut = v > 0
                let short: Double = isOut ? Swift.max(0, v - b0) : 0
                let what = dueWhat(buys: buys[k] ?? [], sells: sells[k] ?? [], day: d, ctx: ctx)
                let bought: [UUID] = buys[k] ?? []
                let sold: [UUID] = (sells[k] ?? []).filter { !bought.contains($0) }
                let ids2: [UUID] = bought + sold
                out.append(WealthBrokerDue(day: d, accountId: a.id, accountName: a.name, code: code,
                                           amount: Swift.abs(v), isOutflow: isOut, what: what, before: b0,
                                           now: a.balance(code), short: short, stockIds: ids2))
            }
        }
        return out.enumerated().sorted { x, y in
            if x.element.day != y.element.day { return x.element.day < y.element.day }
            return x.offset < y.offset
        }.map { $0.element }
    }

    /// 「買 00878 2,000 股」「賣 0050 1,000 股」「買 00878 等 2 檔」「買 00878、賣 0050」（股數＝那天交割的交易；舊版單筆＝持股）
    private static func dueWhat(buys: [UUID], sells: [UUID], day: Date, ctx: BuildContext) -> String? {
        func name(_ id: UUID) -> String? {
            guard let s = ctx.stocksById[id] else { return nil }
            let n = s.name.trimmingCharacters(in: .whitespaces)
            return n.isEmpty ? (s.symbol.isEmpty ? nil : s.symbol) : n
        }
        func shares(_ id: UUID, buy: Bool) -> Double {
            guard let s = ctx.stocksById[id] else { return 0 }
            if !s.transactions.isEmpty {
                var total: Double = 0
                for tx in s.transactions where WealthCal.day(tx.settlementDate) == day && (tx.kind == .buy) == buy {
                    total += tx.shares
                }
                return total
            }
            if buy, WealthCal.day(StockTransaction.taiwanSettlementDate(from: s.purchaseDate)) == day { return s.shares }
            if !buy, let sd = s.soldDate, WealthCal.day(StockTransaction.taiwanSettlementDate(from: sd)) == day {
                return s.shares
            }
            return 0
        }
        func one(_ id: UUID, buy: Bool) -> String? {
            guard let n = name(id) else { return nil }
            let verb = buy ? "買 " : "賣 "
            let sh = shares(id, buy: buy)
            guard sh > 0 else { return verb + n }
            let decimals = Swift.abs(sh - sh.rounded()) < 0.0001 ? 0 : 2
            return verb + n + " " + WealthFormat.grouped(sh, decimals: decimals) + " 股"
        }
        if !buys.isEmpty && !sells.isEmpty {
            let b = buys.compactMap { name($0) }.first
            let s = sells.compactMap { name($0) }.first
            guard let bn = b, let sn = s else { return nil }
            return "買 " + bn + "、賣 " + sn
        }
        let list = buys.isEmpty ? sells : buys
        let buy = !buys.isEmpty
        guard let first = list.first else { return nil }
        if list.count == 1 { return one(first, buy: buy) }
        guard let n = name(first) else { return nil }
        return (buy ? "買 " : "賣 ") + n + " 等 \(list.count) 檔"
    }

    // MARK: - [v25.564] 要確認（judge §3.5；#11 存了安全碼不做——使用者第 6 題「我要存」）

    private static func makeChecks(cards: [Card], accounts: [Account], bankMs: [LifeMilestone], unknown: [String],
                                   ctx: BuildContext, bankIds: Set<UUID>, terms: [TimeDeposit],
                                   insurance: [InsuranceGroup], deposits: WealthDepositBook,
                                   brokers: [Broker] = [], policies: WealthPolicyFacts = WealthPolicyFacts()) -> [WealthCheck] {
        let today = ctx.today
        let book = ctx.book
        var out: [WealthCheck] = []
        func add(_ c: WealthCheck) {
            if book.isDismissed(c.id) { return }
            out.append(c)
        }
        let visibleBanks = accounts.filter { !$0.isSecurities && !$0.hidden }
        func name(_ id: UUID?) -> String? { id.flatMap { ctx.nameById[$0] } }

        // #1 接下來 30 天某一天會不夠扣
        for a in visibleBanks {
            guard let s = a.shortage else { continue }
            let what: String = s.kind == .stockBuy ? "交割（\(s.title)）" : "「\(s.title)」"
            let text = "\(WealthFormat.monthDay(s.date)) \(a.name)要扣\(what)\(WealthFormat.plain(s.amount, code: s.code))，"
                + "預估只有 \(WealthFormat.plain(s.before, code: s.code))，差 \(WealthFormat.plain(s.short, code: s.code))"
            var actions: [WealthCheck.Action] = []
            if s.code == "NT$" {
                let from = transferSource(excluding: a.id, accounts: visibleBanks)
                actions.append(WealthCheck.Action(title: "轉帳過去",
                                                  fix: .transfer(to: a.id, from: from, amount: s.short.rounded(.up))))
            }
            actions.append(WealthCheck.Action(title: "知道了", fix: .dismiss))
            add(WealthCheck(id: "short-\(a.id.uuidString)-\(WealthCal.dayKey(s.date))", kind: .shortage, tone: .bad,
                            text: text, actions: actions, accountIds: [a.id]))
        }

        // #2 自己繳的卡當作已繳（隔天問一次）、#3 每次問我過了截止日、你說還沒繳的逾期
        for c in cards {
            for s in c.statements {
                let amount = WealthFormat.grouped(s.amount.rounded(), decimals: 0)
                switch s.status {
                case .assumedPaid:
                    guard WealthCal.days(from: s.due, to: today) <= 35 else { continue }
                    let from = name(s.paidFrom).map { "從\($0)" } ?? ""
                    let text = "\(c.name) \(s.label) \(amount)，App 當作 \(WealthFormat.monthDay(s.due)) \(from)繳了，對嗎？"
                    add(WealthCheck(id: "assumed-\(c.id.uuidString)-\(s.key)", kind: .assumedPaid, tone: .warn,
                                    text: text,
                                    actions: [WealthCheck.Action(title: "對", fix: .confirmPaid(cardId: c.id, key: s.key,
                                                                                               on: s.due, from: s.paidFrom)),
                                              WealthCheck.Action(title: "不是，改一下", fix: .editPaid(cardId: c.id, key: s.key))],
                                    accountIds: [c.id]))
                case .overdue:
                    if s.notPaid {
                        let late = WealthCal.days(from: s.due, to: today)
                        let minText = WealthFormat.grouped(s.minimumDue, decimals: 0)
                        let text = "\(c.name) \(s.label) \(amount) 過了截止日 \(late) 天還沒繳：可能有循環利息與違約金，最低應繳約 \(minText)"
                        add(WealthCheck(id: "overdue-\(c.id.uuidString)-\(s.key)", kind: .cardOverdue, tone: .bad,
                                        text: text,
                                        actions: [WealthCheck.Action(title: "標成已繳", fix: .editPaid(cardId: c.id, key: s.key))],
                                        accountIds: [c.id]))
                    } else {
                        let text = "\(c.name) \(WealthFormat.monthDay(s.due)) 的帳單 \(amount) 繳了嗎？"
                        add(WealthCheck(id: "ask-\(c.id.uuidString)-\(s.key)", kind: .askPaid, tone: .bad,
                                        text: text,
                                        actions: [WealthCheck.Action(title: "繳了", fix: .editPaid(cardId: c.id, key: s.key)),
                                                  WealthCheck.Action(title: "還沒", fix: .markNotPaid(cardId: c.id, key: s.key))],
                                        accountIds: [c.id]))
                    }
                default:
                    break
                }
            }
        }

        // #10 帳戶算出來是負的
        for a in visibleBanks {
            for code in a.currencies {
                let v = a.balance(code)
                guard v < -0.5 else { continue }
                add(WealthCheck(id: "neg-\(a.id.uuidString)-\(code)-\(Int(v.rounded()))", kind: .negative, tone: .bad,
                                text: "\(a.name) \(WealthFormat.money(v, code: code))：可能漏記了收入或轉帳",
                                actions: [WealthCheck.Action(title: "對存摺", fix: .anchor(accountId: a.id, code: code))],
                                accountIds: [a.id]))
            }
        }

        // #4 記帳裡有像「繳卡費」的支出（標題含卡費／繳卡、扣銀行、沒刷卡）
        let keywords = ["卡費", "繳卡"]
        for e in ctx.expenses where e.linkedCreditCardMilestoneId == nil {
            guard let bid = e.linkedBankMilestoneId, bankIds.contains(bid),
                  !ctx.excluded.contains(e.id.uuidString),
                  keywords.contains(where: { e.title.contains($0) }) else { continue }
            let recurring = e.expenseType == .fixed && e.recurrence != nil
            // 對過存摺以前的一次性支出不影響現在的數字，不問
            if !recurring, let last = accounts.first(where: { $0.id == bid })?.lastAnchorDate,
               WealthCal.day(e.date) <= last { continue }
            let ntd = WealthSchedule.ntd(of: e, raw: e.amount, rates: ctx.rates)
            let bankName = name(bid) ?? "銀行"
            let text = "記帳 \(WealthFormat.monthDay(e.date))「\(e.title) \(WealthFormat.grouped(ntd.rounded(), decimals: 0))」"
                + "會讓\(bankName)多扣一次：卡費 App 已經自己算了"
            add(WealthCheck(id: "cardfee-\(e.id.uuidString)", kind: .cardFeeExpense, tone: .warn, text: text,
                            actions: [WealthCheck.Action(title: "這筆不算", fix: .excludeExpense(e.id)),
                                      WealthCheck.Action(title: "它不是卡費", fix: .dismiss)],
                            accountIds: [bid]))
        }

        // #5 停用的卡還綁著定期扣款
        for c in cards where c.isDisabled {
            let bound = ctx.expenses.filter { e in
                guard e.linkedCreditCardMilestoneId == c.id, e.expenseType == .fixed, e.recurrence != nil else { return false }
                guard let end = e.endDate else { return true }
                return WealthCal.day(end) >= today
            }
            guard let first = bound.first else { continue }
            let since = c.closedDate.map { WealthFormat.monthDay($0) + " 停用了" } ?? "停用了"
            let what = recurringText(first, rates: ctx.rates) + (bound.count > 1 ? " 等 \(bound.count) 筆" : "")
            let ids = bound.map(\.id)
            add(WealthCheck(id: "disrec-\(c.id.uuidString)-\(bound.count)", kind: .disabledRecurring, tone: .warn,
                            text: "\(c.name) \(since)，記帳裡 \(what)還記在它身上",
                            actions: [WealthCheck.Action(title: "改刷別張", fix: .moveRecurring(cardId: c.id, expenseIds: ids)),
                                      WealthCheck.Action(title: "已經退訂", fix: .endRecurring(expenseIds: ids, on: c.closedDate ?? today))],
                            accountIds: [c.id]))
        }

        // #7 卡沒設卡費從哪扣（含原本的帳戶刪了）
        for c in cards where !c.isDisabled && c.payerId == nil {
            let gone = c.linkedRaw.map { !bankIds.contains($0) } ?? false
            let text = gone ? "\(c.name) 原本扣卡費的帳戶已經不在了，卡費先不算進任何帳戶"
                            : "\(c.name) 沒設卡費從哪扣，卡費先不算進任何帳戶"
            add(WealthCheck(id: "nopayer-\(c.id.uuidString)", kind: .noPayer, tone: .warn, text: text,
                            actions: [WealthCheck.Action(title: "選帳戶", fix: .editAccount(c.id))],
                            accountIds: [c.id]))
        }

        // #8 舊版記錯的外幣扣款（台幣數字被當成外幣；judge §2.3，一筆一筆問）
        for m in bankMs where book.account(m.id).hidden != true {
            for dep in m.bankDeposits ?? [] {
                guard let lid = dep.linkedExpenseId, dep.linkedStockId == nil, !dep.isTransfer, !dep.isAnchor,
                      !dep.isAdjust else { continue }
                let code = norm(dep.currencyCode)
                guard code != "NT$", let r = ctx.rates.known(code), r > 1.5 else { continue }
                var ntd: Double? = nil
                var title = ""
                if let e = ctx.expensesById[lid] {
                    guard e.linkedCreditCardMilestoneId == nil, !(e.expenseType == .fixed && e.recurrence != nil) else { continue }
                    if let o = e.originalCurrencyAmount, norm(o.code) == code { continue }
                    ntd = WealthSchedule.ntd(of: e, raw: e.amount, rates: ctx.rates)
                    title = e.title
                } else if let inc = ctx.incomesById[lid] {
                    guard inc.period == .once else { continue }
                    ntd = inc.amount
                    title = inc.title
                }
                guard let v = ntd, Swift.abs(dep.amount - v) < 0.005 else { continue }
                let fixedAmount = (v / r * 100).rounded() / 100
                guard Swift.abs(fixedAmount - dep.amount) > 0.009 else { continue }
                let acctName = ctx.nameById[m.id] ?? bankName(of: m)
                let text = "\(acctName) \(WealthFormat.monthDay(dep.date))「\(title)」記成 \(WealthFormat.money(dep.amount, code: code))："
                    + "那是台幣的數字，照現在的匯率 \(WealthFormat.rate(r)) 是 \(WealthFormat.money(fixedAmount, code: code))"
                add(WealthCheck(id: "fx-\(dep.id.uuidString)", kind: .legacyFX, tone: .warn, text: text,
                                actions: [WealthCheck.Action(title: "改過來",
                                                             fix: .fixLegacyFX(accountId: m.id, depositId: dep.id, amount: fixedAmount)),
                                          WealthCheck.Action(title: "不用改", fix: .dismiss)],
                                accountIds: [m.id]))
            }
        }

        // #9 查不到匯率（[v25.566] 定存的也算：金額＝存摺上＋存著的定存）
        for code in unknown {
            let owners = accounts.filter {
                !$0.isSecurities && ($0.unknownCodes.contains(code) || $0.depositUnknownCodes.contains(code))
            }
            let names = owners.map(\.name).joined(separator: "、")
            let amounts = owners.map { (a: Account) -> String in
                WealthFormat.money(a.balance(code) + a.depositAmount(code), code: code)
            }.joined(separator: "、")
            add(WealthCheck(id: "rate-\(code)", kind: .unknownRate, tone: .warn,
                            text: "設定裡找不到「\(code)」的匯率，\(names)的 \(amounts) 先不算進合計",
                            actions: [WealthCheck.Action(title: "去設定", fix: .openRates)],
                            accountIds: owners.map(\.id)))
        }

        // #12 卡片效期前 30 天（v4）：效期那個月的 1 號往前 30 天起、到那個月底；換新卡後記得改綁在這張卡的定期扣款
        for c in cards where !c.isDisabled {
            guard let em = c.expiryMonth else { continue }
            let from = WealthCal.addDays(-30, to: em)
            let until = WealthCal.addMonths(1, to: em)
            guard today >= from, today < until else { continue }
            let horizonDay = WealthCal.addDays(400, to: today)
            var bound: [(next: Date, title: String)] = []
            for e in ctx.expenses where e.linkedCreditCardMilestoneId == c.id && e.expenseType == .fixed && e.recurrence != nil {
                if let end = e.endDate, WealthCal.day(end) < today { continue }
                let first = WealthSchedule.fixedPeriods(e, through: horizonDay)
                    .first(where: { (per: (index: Int, date: Date)) -> Bool in WealthCal.day(per.date) >= today })
                let next: Date = first.map { WealthCal.day($0.date) } ?? Date.distantFuture
                bound.append((next: next, title: e.title))
            }
            let ordered: [String] = bound.enumerated().sorted { x, y in
                if x.element.next != y.element.next { return x.element.next < y.element.next }
                return x.offset < y.offset
            }.map { $0.element.title }
            let year = WealthCal.calendar.component(.year, from: em)
            let thisYear = WealthCal.calendar.component(.year, from: today)
            let when: String = year == thisYear ? "\(WealthCal.month(em)) 月到期" : "\(year) 年 \(WealthCal.month(em)) 月到期"
            var actions: [WealthCheck.Action] = []
            let text: String
            if ordered.isEmpty {
                text = "\(c.name) \(when)：收到新卡記得改卡片資料的有效期限"
            } else {
                let more: String = ordered.count > 3 ? " 等 \(ordered.count) 筆" : ""
                text = "\(c.name) \(when)，換新卡後記得改 " + ordered.prefix(3).joined(separator: "、") + more
                actions.append(WealthCheck.Action(title: "看綁了哪些", fix: .openCard(c.id)))
            }
            actions.append(WealthCheck.Action(title: "知道了", fix: .dismiss))
            // [v25.567] 保費刷這張卡的保單：保單頁的要確認也看得到（「刷的 CUBE 2027/03 到期」）
            add(WealthCheck(id: "expiry-\(c.id.uuidString)-\(WealthCal.monthKey(em))", kind: .cardExpiring, tone: .warn,
                            text: text, actions: actions, accountIds: [c.id] + policies.policyIds(paidBy: c.id)))
        }

        // [v25.566] #13 定存 7 天內到期（照到期處理寫一句）；到期再決定、已經到期還沒決定（不能按知道了：要你選）
        for t in terms {
            guard let m = t.maturity, let mt = t.maturityText(today) else { continue }
            let id = t.id
            if t.status == .waiting {
                add(WealthCheck(id: "tdwait-\(id.uuidString)", kind: .depositMaturing, tone: .warn,
                                text: "\(t.displayTitle) \(mt) 到期了，錢還在定存裡：要轉活存還是續存？",
                                actions: [WealthCheck.Action(title: "轉活存",
                                                             fix: .setMaturity(depositId: id, mode: WealthMaturityMode.toLive.rawValue)),
                                          WealthCheck.Action(title: "本息續存",
                                                             fix: .setMaturity(depositId: id, mode: WealthMaturityMode.renewAll.rawValue))],
                                accountIds: [t.accountId]))
                continue
            }
            guard t.status == .active else { continue }
            let left = WealthCal.days(from: today, to: m)
            guard left >= 1 && left <= 7 else { continue }
            let total = WealthFormat.plain(t.maturityAmount, code: t.code)
            let to = t.payoutName ?? t.accountName
            let text: String
            var actions: [WealthCheck.Action] = []
            switch t.mode {
            case .renewAll:
                text = "\(t.displayTitle) \(mt) 到期，會本息續存成 \(total)"
                actions.append(WealthCheck.Action(title: "改成轉活存",
                                                  fix: .setMaturity(depositId: id, mode: WealthMaturityMode.toLive.rawValue)))
            case .renewPrincipal:
                let p = WealthFormat.plain(t.principal, code: t.code)
                let i = WealthFormat.plain(t.interest, code: t.code)
                text = "\(t.displayTitle) \(mt) 到期，本金 \(p) 續存、利息 \(i) 轉進\(to)"
                actions.append(WealthCheck.Action(title: "改成轉活存",
                                                  fix: .setMaturity(depositId: id, mode: WealthMaturityMode.toLive.rawValue)))
            case .toLive:
                text = "\(t.displayTitle) \(mt) 到期，本息 \(total) 會轉進\(to)"
                actions.append(WealthCheck.Action(title: "改成本息續存",
                                                  fix: .setMaturity(depositId: id, mode: WealthMaturityMode.renewAll.rawValue)))
            case .decide:
                text = "\(t.displayTitle) \(mt) 到期，還沒決定到期怎麼處理"
                actions.append(WealthCheck.Action(title: "轉活存",
                                                  fix: .setMaturity(depositId: id, mode: WealthMaturityMode.toLive.rawValue)))
                actions.append(WealthCheck.Action(title: "本息續存",
                                                  fix: .setMaturity(depositId: id, mode: WealthMaturityMode.renewAll.rawValue)))
            }
            if t.mode != .decide {
                actions.append(WealthCheck.Action(title: "照舊", fix: .dismiss))
            }
            add(WealthCheck(id: "tdsoon-\(id.uuidString)", kind: .depositMaturing, tone: .warn, text: text,
                            actions: actions, accountIds: [t.accountId]))
        }

        // [v25.566] 舊的「定存」種類帳戶：補利率和到期日（問一次，可以略過；有過任何一筆定存紀錄就不問）
        let recorded = Set(deposits.all.map(\.bankId))
        for a in visibleBanks where a.isFixedDeposit && !recorded.contains(a.id) {
            guard a.balances.values.contains(where: { $0 > 0.5 }) else { continue }
            add(WealthCheck(id: "tdlegacy-\(a.id.uuidString)", kind: .depositInfoMissing, tone: .info,
                            text: "\(a.name)是以前記的定存帳戶：補上利率和到期日，就能算利息、到期前 7 天提醒你",
                            actions: [WealthCheck.Action(title: "補資料", fix: .editTimeDeposit(accountId: a.id, depositId: nil)),
                                      WealthCheck.Action(title: "略過", fix: .dismiss)],
                            accountIds: [a.id]))
        }

        // [v25.566] #14 同一家銀行合計超過 300 萬（〔知道了〕一年內不再提）
        for g in insurance where !deposits.isInsuranceQuiet(g.id, today: today) {
            add(WealthCheck(id: "dic-\(g.id)", kind: .depositInsurance, tone: .info, text: g.text,
                            actions: [WealthCheck.Action(title: "知道了", fix: .quietInsurance(g.id))],
                            accountIds: g.accountIds))
        }

        // [v25.567] #16 證券戶身上有舊交割紀錄（只問一次：key 不帶事件；搬完就沒有紀錄、這條自己不見）
        // [v25.567 驗] 只剩股票已經刪了的紀錄（搬的時候留在證券戶當紀錄）不再問：以前搬完還一直跳〔搬到薪轉〕、按了又「沒有要搬的」
        for b in brokers where b.legacyCount > 0 && b.legacyLiveCount > 0 {
            guard let acc = accounts.first(where: { $0.id == b.id }), !acc.hidden else { continue }
            let sign = b.legacyTotal < 0 ? "−" : "+"
            let total = sign + WealthFormat.grouped(Swift.abs(b.legacyTotal).rounded(), decimals: 0)
            let head = "\(b.name)身上記了 \(b.legacyCount) 筆交割、合計 \(total)"
            var ids: [UUID] = [b.id]
            let text: String
            var actions: [WealthCheck.Action] = []
            if let bank = b.settlementBankId, let bankLabel = b.settlementName {
                ids.append(bank)
                text = head + "；交割其實是從\(bankLabel)扣的"
                actions.append(WealthCheck.Action(title: "搬到\(bankLabel)", fix: .moveSettlements(brokerId: b.id)))
            } else {
                text = head + "；選了交割銀行，就能把它們搬過去"
                actions.append(WealthCheck.Action(title: "選交割銀行", fix: .editAccount(b.id)))
            }
            actions.append(WealthCheck.Action(title: "留著當紀錄", fix: .dismiss))
            add(WealthCheck(id: "legacysettle-\(b.id.uuidString)", kind: .legacySettlement, tone: .warn, text: text,
                            actions: actions, accountIds: ids))
        }

        // [v25.567] #15 保單跟記帳的保費像同一張、舊資料沒寫繳法（保單頁）、一年一約 60 天內到期
        for c in policies.checks(today: today) { add(c) }

        // #6 卡沒填結帳日或繳款截止日（v2 偵測）
        for c in cards where !c.isDisabled && (c.billingDayMissing || c.paymentDayMissing) {
            add(WealthCheck(id: "card-days-\(c.id.uuidString)", kind: .cardDaysMissing, tone: .info,
                            text: missingDaysText(c),
                            actions: [WealthCheck.Action(title: "填日子", fix: .editAccount(c.id))],
                            accountIds: [c.id]))
        }

        // 很久沒對存摺（超過 90 天；只在帳戶頁出現，不催）
        for a in visibleBanks where !a.isFixedDeposit {
            guard let last = a.lastAnchorDate else { continue }
            let n = WealthCal.days(from: last, to: today)
            guard n > 90 else { continue }
            add(WealthCheck(id: "stale-\(a.id.uuidString)-\(WealthCal.dayKey(last))", kind: .staleAnchor, tone: .info,
                            text: "\(a.name) \(WealthFormat.monthDay(last)) 對過存摺，已經 \(n) 天了：跟存摺對一下，數字會更準",
                            actions: [WealthCheck.Action(title: "對存摺", fix: .anchor(accountId: a.id, code: a.currencies.first ?? "NT$")),
                                      WealthCheck.Action(title: "知道了", fix: .dismiss)],
                            accountIds: [a.id], onPage: false))
        }

        // 排序：bad → warn → info，同一種語氣照種類先後，同一種照產生的順序（sort 不保證穩定，帶著原本的位置比）
        let indexed = Array(out.enumerated())
        let sorted = indexed.sorted { x, y in
            if x.element.tone.rawValue != y.element.tone.rawValue { return x.element.tone.rawValue < y.element.tone.rawValue }
            if x.element.kind.order != y.element.kind.order { return x.element.kind.order < y.element.kind.order }
            return x.offset < y.offset
        }
        return sorted.map { $0.element }
    }

    /// 〔轉帳過去〕預設的轉出帳戶：存摺上台幣最多的另一個活存（不是定存、沒收起來、有錢）；都沒有＝nil（表單裡選）
    private static func transferSource(excluding id: UUID, accounts: [Account]) -> UUID? {
        var best: Account? = nil
        for a in accounts where a.id != id && !a.isFixedDeposit && !a.hidden && a.balance("NT$") > 0.5 {
            if let b = best, b.balance("NT$") >= a.balance("NT$") { continue }
            best = a
        }
        return best?.id
    }

    /// 「Disney+ 270／月」
    private static func recurringText(_ e: Expense, rates: FinanceRates) -> String {
        let ntd = WealthSchedule.ntd(of: e, raw: e.amount, rates: rates)
        let unit: String
        switch e.recurrence {
        case .monthly?: unit = "月"
        case .quarterly?: unit = "季"
        case .yearly?: unit = "年"
        case nil: unit = "次"
        }
        return "\(e.title) \(WealthFormat.grouped(ntd.rounded(), decimals: 0))／\(unit)"
    }
}

// MARK: - [v25.563] 對存摺要的「App 算的數字」

extension WealthFacts {
    /// 這個帳戶這個幣別在 day 那天結束時，App 算的存摺上；excluding：不算那一筆（編輯以前的對存摺時，不算它自己）。
    /// 用同一套算法、把「今天」當成 day 重算一次（只在選日期、打開表單時算，打字時不算）
    /// [v25.566] deposits：定存那一包（起存那天的轉定存、到期轉活存也算進「App 算的」）
    static func passbookBalance(accountId: UUID, code: String, endOf day: Date, excluding: UUID?,
                                milestones: [LifeMilestone], book: WealthBook,
                                deposits: WealthDepositBook = WealthDepositBook(), expenses: [Expense],
                                incomes: [Income], stocks: [Stock], rates: FinanceRates) -> Double {
        var list = milestones
        if let ex = excluding, let i = list.firstIndex(where: { $0.id == accountId }) {
            list[i].bankDeposits = (list[i].bankDeposits ?? []).filter { $0.id != ex }
        }
        let f = build(milestones: list, book: book, deposits: deposits, expenses: expenses, incomes: incomes,
                      stocks: stocks, rates: rates, now: day)
        return f.account(accountId)?.balance(code) ?? 0
    }
}
