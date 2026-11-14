import Foundation
import UIKit
import Combine

// MARK: - [v25.568] 財富 v7：給網頁版的一包數字（wealth/judge.md §6.9、§7.1；build/v7/brief.md §2-4）
//
// 網頁版（docs/app.js）以前自己用舊算法算銀行餘額（刷卡當天就扣、沒算卡費截止日與交割），跟 App 對不上。
// v7 起 App 把財富的一套數字（WealthFacts）算好，寫成一包 JSON 放在同步鍵 life_wealth_facts_v1（跟著 iCloud 上去，
// 網頁版用 CloudKit JS 讀同一筆 KVBlob）；網頁版讀得到這包就照這包顯示，讀不到才用自己的舊算法。
// • 只放：合計（存款合計、活存／定存／外幣、卡費還沒扣、待交割、扣完能用、理財淨資產）、每個帳戶的暱稱、銀行、後 4 碼、
//   存摺上（每個幣別）、每張卡的要繳／截止日／還沒出帳／還能刷／結帳日／截止日、接下來的交割、定存到期日。
// • **不放**：完整卡號、安全碼、完整帳號、有效期限、保單號碼、票證號（CardVault 規矩 4：這裡不准呼叫 CardVault.open，
//   也用不到——後 4 碼都是明碼欄位）。不放任何 email、Apple ID、token。
// • 只寫不讀：App 自己不讀這一包（LifeStore 不載入它），所以不用 decodeIfPresent；欄位加了網頁版沒用到也無妨。
// • 寫手 WealthWebFactsWriter：記帳、理財、人生一改，防抖 5 秒算一次；跟上次寫的一模一樣就不寫（不白推 iCloud）。
//   只在 App 開著時寫（用哪一台就以哪一台算的為準，兩台不會互相蓋來蓋去）。
// • CSV「財富帳戶清單」也讀這一包（同一套數字；UnifiedExporter.exportCSV(_:accounts:)）。
// 日期一律寫成西曆字串「2026-10-27」（WealthCal.dayKey）：網頁版的 reviveDates 只轉數字，名字也避開它的 DATE_KEYS。

struct WealthWebFacts: Encodable, Equatable {
    /// 同步鍵（CloudSyncManager.syncKeys；網頁版 KV_KEYS.wealthFacts）
    static let syncKey = "life_wealth_facts_v1"
    /// 這一包的格式版本（網頁版看到不認得的版本就退回舊算法）
    static let currentVersion = 1

    var version: Int
    /// 哪一天算的（App 那台的今天）
    var asOf: String
    /// 存款合計（存摺上＋存著的定存；算進存款合計、沒收起來的銀行帳戶；查不到匯率的不算）
    var cash: Double
    /// 有幣別查不到匯率（大字前加「約」）
    var cashApprox: Bool
    var live: Double
    var fixedDeposit: Double
    var foreign: Double
    /// 卡費還沒扣（要繳＋還沒出帳）
    var owedCards: Double
    /// 待交割
    var pendingSettlement: Double
    /// 已經排定、還沒到的提款
    var scheduledOut: Double
    /// 扣完活存能用
    var usable: Double
    /// 理財淨資產（同 App 理財總覽 FinanceSnapshot.netWorth；口徑 4：含存款、扣卡費與待交割）
    var netWorth: Double?
    var accounts: [Account]
    var brokers: [Broker]
    var cards: [Card]
    var settlements: [Settlement]
    var deposits: [Deposit]

    struct Balance: Encodable, Equatable {
        var code: String
        var amount: Double
    }

    /// 一個銀行帳戶（證券戶在 brokers）
    struct Account: Encodable, Equatable {
        /// 里程碑 id（網頁版對得上那一筆）
        var id: String
        /// 暱稱 → 銀行名
        var name: String
        var bank: String
        /// 帳號後 4 碼（沒有 nil）
        var last4: String?
        var hidden: Bool
        var countsInCash: Bool
        /// 每個幣別的存摺上（台幣在前）
        var balances: [Balance]
        /// 存摺上換台幣（查不到匯率的不算）
        var ntd: Double
        /// 存著的定存（台幣）
        var depositNTD: Double
        /// 還沒扣（從這裡扣的卡費＋從這裡交割的股票款＋排定的提款）
        var notYetDebited: Double
        /// 扣完能用
        var usable: Double
        var unknownCodes: [String]
    }

    /// 一個證券戶（券商名片：持股市值讀股票頁，不算進存款合計）
    struct Broker: Encodable, Equatable {
        var id: String
        var name: String
        var last4: String?
        /// 交割銀行（暱稱）
        var settlementBank: String?
        var marketValue: Double
        var nextSettlementDay: String?
        /// 正的＝要從交割銀行扣，負的＝會入帳
        var nextSettlementAmount: Double
    }

    /// 一張信用卡（只有後 4 碼；**沒有有效期限**）
    struct Card: Encodable, Equatable {
        var id: String
        var name: String
        var issuer: String?
        var last4: String?
        var disabled: Bool
        /// 要繳（已經結帳、還沒繳）
        var due: Double
        /// 要繳那一期的繳款截止日（沒有要繳 nil）
        var dueDay: String?
        /// 還沒出帳
        var unbilled: Double
        var unbilledCount: Int
        var nextCloseDay: String
        var nextDueDay: String
        var limit: Double?
        /// 還能刷（沒填額度 nil）
        var available: Double?
        var billingDay: Int
        var paymentDay: Int
        /// 「自己繳」「自動扣全額」…
        var payMode: String
        /// 從哪個帳戶扣（暱稱）
        var payer: String?
    }

    /// 接下來的交割（35 天內；每個帳戶每天每幣別買賣相抵）
    struct Settlement: Encodable, Equatable {
        var day: String
        var accountId: String
        var account: String
        var broker: String?
        var code: String
        var amount: Double
        var ntd: Double?
        /// 買＝從帳戶扣；賣＝入帳
        var outflow: Bool
    }

    /// 一期定存（沒開始、存著、到期待決定；結束的不放）
    struct Deposit: Encodable, Equatable {
        var accountId: String
        var account: String
        var code: String
        var principal: Double
        var rate: Double?
        var startDay: String
        /// 到期日（沒有 nil）
        var maturityDay: String?
        /// 「本息續存」「到期轉活存」…
        var mode: String
        /// notStarted／active／waiting
        var status: String
    }

    // MARK: 組

    /// 從財富的一套數字組（netWorth：理財總覽那個數；算不出來 nil）。在主執行緒叫
    static func make(_ f: WealthFacts, netWorth: Double?) -> WealthWebFacts {
        var accounts: [Account] = []
        for a in f.banks {
            var balances: [Balance] = []
            for code in a.currencies {
                balances.append(Balance(code: code, amount: money(a.balance(code))))
            }
            accounts.append(Account(id: a.id.uuidString, name: a.name, bank: a.bankName, last4: a.last4,
                                    hidden: a.hidden, countsInCash: a.countsInCash, balances: balances,
                                    ntd: money(a.ntdTotal), depositNTD: money(a.depositNTD),
                                    notYetDebited: money(a.notYetDebited), usable: money(a.usable),
                                    unknownCodes: a.unknownCodes))
        }
        var brokers: [Broker] = []
        for b in f.brokers {
            let last4: String? = f.account(b.id)?.last4
            let next: String? = b.nextSettlementDate.map { WealthCal.dayKey($0) }
            brokers.append(Broker(id: b.id.uuidString, name: b.name, last4: last4, settlementBank: b.settlementName,
                                  marketValue: money(b.marketValue), nextSettlementDay: next,
                                  nextSettlementAmount: money(b.nextSettlementAmount)))
        }
        var cards: [Card] = []
        for c in f.cards {
            let dueDay: String? = c.due > 0.004 ? c.dueStatement.map { WealthCal.dayKey($0.due) } : nil
            cards.append(Card(id: c.id.uuidString, name: c.fullName, issuer: c.issuer, last4: c.last4,
                              disabled: c.isDisabled, due: money(c.due), dueDay: dueDay,
                              unbilled: money(c.unbilled), unbilledCount: c.unbilledCount,
                              nextCloseDay: WealthCal.dayKey(c.nextClose), nextDueDay: WealthCal.dayKey(c.nextDue),
                              limit: c.limit, available: c.available.map { money($0) },
                              billingDay: c.billingDay, paymentDay: c.paymentDay,
                              payMode: c.payMode.title, payer: c.payerName))
        }
        var settlements: [Settlement] = []
        for s in f.settlements {
            settlements.append(Settlement(day: WealthCal.dayKey(s.day), accountId: s.accountId.uuidString,
                                          account: s.accountName, broker: s.brokerName, code: s.code,
                                          amount: money(s.amount), ntd: s.ntd.map { money($0) }, outflow: s.isOutflow))
        }
        var deposits: [Deposit] = []
        for t in f.timeDeposits {
            deposits.append(Deposit(accountId: t.accountId.uuidString, account: t.accountName, code: t.code,
                                    principal: money(t.principal), rate: t.rate, startDay: WealthCal.dayKey(t.start),
                                    maturityDay: t.maturity.map { WealthCal.dayKey($0) }, mode: t.mode.shortTitle,
                                    status: statusText(t.status)))
        }
        return WealthWebFacts(version: currentVersion, asOf: WealthCal.dayKey(f.today), cash: money(f.cash),
                              cashApprox: f.cashIsApprox, live: money(f.live), fixedDeposit: money(f.fixedDeposit),
                              foreign: money(f.foreign), owedCards: money(f.owedCards),
                              pendingSettlement: money(f.pendingSettlement), scheduledOut: money(f.scheduledOut),
                              usable: money(f.usable), netWorth: netWorth.map { money($0) },
                              accounts: accounts, brokers: brokers, cards: cards,
                              settlements: settlements, deposits: deposits)
    }

    /// 讀 store 組（財富的一套數字＋理財總覽的淨資產）。在主執行緒叫（FinanceSnapshot 讀 AppStores.life）
    static func make(life: LifeStore, expense: ExpenseStore, finance: FinanceStore, now: Date = Date()) -> WealthWebFacts {
        let f = life.wealthFacts(expense: expense, finance: finance, now: now)
        let snap = FinanceSnapshot.current(finance: finance, expense: expense, rates: FinanceRates(expense), now: now)
        return make(f, netWorth: snap.netWorth)
    }

    /// 錢四捨五入到 0.01（加總的浮點雜訊不要寫出去，內容沒變時 bytes 才會一樣）
    static func money(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    private static func statusText(_ s: WealthFacts.TimeDeposit.Status) -> String {
        switch s {
        case .notStarted: return "notStarted"
        case .active: return "active"
        case .waiting: return "waiting"
        case .ended: return "ended"
        }
    }

    /// 寫進 UserDefaults 的那包 bytes（鍵照字母排：內容沒變 bytes 就一樣）
    func encoded() -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return try? enc.encode(self)
    }

    // MARK: CSV「財富帳戶清單」（judge §6.9：暱稱、銀行、末 4 碼、存摺上、卡的結帳日／截止日；不含完整卡號、帳號、有效期限）

    /// esc：UnifiedExporter 的 CSV 跳脫（逗號、引號、換行）
    func csvSection(esc: (String) -> String) -> String {
        var csv = "## 財富帳戶清單 (Wealth Accounts)\n"
        csv += "kind,name,bank,last4,passbook,billingDay,paymentDay,status\n"
        for a in accounts {
            var parts: [String] = a.balances.map { (b: Balance) -> String in
                b.code + " " + String(format: "%.2f", b.amount)
            }
            // 存著的定存另外寫一格（台幣；定存在定存那一包，不在存摺上）
            if a.depositNTD > 0.004 { parts.append("定存 NT$ " + String(format: "%.2f", a.depositNTD)) }
            let book: String = parts.joined(separator: "; ")
            let fields: [String] = ["銀行", esc(a.name), esc(a.bank), a.last4 ?? "", esc(book), "", "",
                                    a.hidden ? "收起來" : "使用中"]
            csv += fields.joined(separator: ",") + "\n"
        }
        for b in brokers {
            let fields: [String] = ["證券戶", esc(b.name), "", b.last4 ?? "", "", "", "", "使用中"]
            csv += fields.joined(separator: ",") + "\n"
        }
        for c in cards {
            let fields: [String] = ["信用卡", esc(c.name), esc(c.issuer ?? ""), c.last4 ?? "", "",
                                    String(c.billingDay), String(c.paymentDay), c.disabled ? "停用" : "使用中"]
            csv += fields.joined(separator: ",") + "\n"
        }
        return csv + "\n"
    }
}

// MARK: - 寫手（LifeGoodApp 的 .task 掛上；切到背景前再寫一次）

final class WealthWebFactsWriter {
    static let shared = WealthWebFactsWriter()

    private static let debounceSeconds = 5

    private var cancellables = Set<AnyCancellable>()
    private weak var expenseStore: ExpenseStore?
    private weak var financeStore: FinanceStore?
    private weak var lifeStore: LifeStore?
    private var started = false

    private init() {}

    /// 啟動時呼叫一次（第二次起什麼都不做）：掛監聽（記帳、理財、人生一改，防抖 5 秒），然後馬上寫一次
    func start(expense: ExpenseStore, finance: FinanceStore, life: LifeStore) {
        guard !started else { return }
        started = true
        expenseStore = expense
        financeStore = finance
        lifeStore = life
        expense.objectWillChange
            .merge(with: finance.objectWillChange)
            .merge(with: life.objectWillChange)
            .debounce(for: .seconds(Self.debounceSeconds), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.writeNow() }
            .store(in: &cancellables)
        writeNow()
    }

    /// 算一次、跟上次寫的不一樣才寫並推 iCloud（主執行緒）。App 在背景時不寫（從 iCloud 拉到別台的資料、背景被叫醒時
    /// 不跟著算：用哪一台就以哪一台算的為準，兩台不會互相蓋來蓋去）；force＝你剛切到背景那一刻（LifeGoodApp），照寫
    func writeNow(force: Bool = false) {
        guard let e = expenseStore, let f = financeStore, let l = lifeStore else { return }
        guard force || UIApplication.shared.applicationState != .background else { return }
        let facts = WealthWebFacts.make(life: l, expense: e, finance: f)
        guard let data = facts.encoded() else { return }
        let ud = UserDefaults.standard
        if ud.data(forKey: WealthWebFacts.syncKey) == data { return }
        ud.set(data, forKey: WealthWebFacts.syncKey)
        CloudSyncManager.shared.pushAll()
    }
}
