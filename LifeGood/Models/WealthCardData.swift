import SwiftUI

// MARK: - 財富卡片頁的字和數字（v25.564，財富 v3；wealth/judge.md §4.1、§4.2、§4.3、§4.4）
//
// 照 VehicleCardData／HouseCardData：卡片頁的每一段字、每一個數、風景的資料（WealthTideScene、WealthCycleScene）
// 都在這裡一次組好（WealthCardData.build，在主執行緒的 .task(id:) 叫一次，坑 #21、#22），body 只畫。
// 數字一律讀 WealthFacts（LifeStore.wealthFacts 的快取），不自己再算一份餘額、期別。
//
// 分工：G2 實作（這個檔＋Views/Life/WealthCardViews.swift）。主控只開檔。
//
// [v25.564] G2：
// • WealthCardData.build(id:facts:life:expense:finance:now:masked:)：照里程碑的子分類組四種頁（信用卡／銀行／證券戶／保單）；
//   找不到那筆里程碑（被刪了）回 nil，卡片頁自己關。
// • 信用卡（§4.1）：看板九種狀態（停用、逾期、要繳〔自動扣／扣款帳戶會不夠／自己繳〕、結帳前 3 天、新卡、已繳、沒有要繳）、
//   帳單週期風景（WealthCycleScene）、四格、這期帳單（一句、標成已繳後那一行、最低應繳、你輸入的帳單金額差多少、分類長條、清單、
//   結帳日前 2 天的註腳）、還沒出帳、綁在這張卡的定期扣款（linkFrom 照今天找）、每期帳單（近 12 期）、年費與回饋小抄、卡片資料。
//   刷卡算哪一期照 WealthFacts.statements 同一個規則（結帳日當天算這期；〔算到下一期〕的往後一期）。
// • 銀行（§4.2）：看板八種狀態、水位風景（WealthTideScene：前 30 天到後 30 天，每個幣別各自追 balanceAfter，多幣別換台幣加總）、
//   四格、接下來 30 天（next30，每列扣完剩）、連到這個帳戶的、外幣、存摺明細（ledger 每列餘額、篩選、月份）、帳戶資料。
// • 證券戶（§4.3 v3）：熱氣球（股票頁同一支 StockBoardData）、持股、資料；沒有記一筆、轉帳、對存摺。
// • 保單（§4.4 v3）：看板（不畫風景）、繳費進度格、保障內容、繳費、醫療地圖一行、資料。
// • 號碼（卡號、有效期限、安全碼、票證、帳號、保單號碼）這裡只放遮好的字（•••• 5678）；完整的由卡片頁按〔顯示〕過 Face ID 後
//   才讀（WealthCardPage.reveal，只放在 @State，30 秒收回）。安全碼只有存了（cardSecurityCipher 不是 nil）才有那一列（使用者第 6 題）。
// • 遮住（財富頁右上的眼睛）：金額一律 WealthFormat.masked／「••••」；%、日期、件數照常。
//
// [v25.566] 財富 v5 G2（build/v5/brief.md §6 G2；judge §4.2 ⑤⑥⑧、§5.5）：
// • ⑤ 外幣：有外幣就出現（只有台幣才不出現；judge §11 ③-B4 玉山只有美金也有一格）；一個幣別一格「美金　US$3,200.00
//   約 NT$102,400（10/19 匯率 32.0）」（WealthFormat.fxNote，日期＝AppQuoteClock.ratesUpdatedAt，build 時抓一次放 ctx）；
//   台幣沒有數字就不放台幣那格；格子下一行說明、〔＋ 換匯〕（WealthTransferSheet exchange，v2 的轉帳綁定）。
// • ⑥ 定存：帳戶的每一期（WealthFacts.Account.timeDeposits：沒開始、存著、到期待決定）一格 FinanceProgressData，字全讀
//   WealthFacts.TimeDeposit（label、rateText、progress、progressEnds、maturityText、interestText），不自己再算利息、到期日；
//   舊的「定存」種類帳戶還沒補過（同要確認那一條：沒收起來、存摺上有錢、帳本裡從沒有過）＝一列〔補上利率和到期日 ›〕；
//   沒收起來的帳戶最下〔＋ 定存〕（有補資料那一列時不重複）；收起來的帳戶沒有〔＋ 定存〕〔換匯〕。
// • 看起來是定存帳戶（Account.showsAsDeposit）：看板「定存」「NT$500,000」「3/15 到期・還有 147 天・預估利息 8,500」、
//   膠囊「3/15 到期・147 天」（7 天內、到期待決定 warn）、手寫 Grow / slowly!；四格本金／預估利息／到期／上次對存摺；
//   換帳戶列同看板大字。舊的定存種類照舊寫存摺上（它的錢就在存摺上）。
// • 明細新種類 .timeDeposit（轉定存、定存到期、定存解約）：篩選「定存」（定存利息那幾列也歸這裡）、圓裡「定」、金色；
//   點了開定存表單（WealthCardOpen.timeDeposit）。定存利息（.interest＋timeDepositId）點了也開定存表單。
// • ⑧ 存款保險：這家銀行合計超過 300 萬才多一列（facts.insurance(for:)；遮住時不寫金額）；種類舊定存寫「定存（以前記的）」。

// MARK: - 型別

/// 卡片頁是哪一種
enum WealthCardKind: Equatable {
    case card, bank, broker, policy
}

/// 格子、資料列點了做什麼（要訂閱的那幾種由卡片頁擋）
enum WealthCardTap: Equatable {
    case none
    /// 捲到那一區
    case scroll(WealthCardAnchor)
    /// 打開編輯（要訂閱）
    case edit(WealthEditorFocus?)
    /// 對存摺（要訂閱）
    case anchor(String)
}

/// 一列點了打開什麼
enum WealthCardOpen: Equatable {
    case none
    /// 那筆記帳（不擋：記帳本來就不用訂閱，同 v2）
    case expense(UUID)
    /// 那筆收入（不擋）
    case income(UUID)
    /// 那檔股票（看的，不擋）
    case stock(UUID)
    /// 另一張卡片頁（卡費那一列、交割的證券戶）
    case card(UUID, WealthCardAnchor?)
    /// 財富頁自己記的存款、提款、利息、手續費（要訂閱）：BankDeposit 的 id
    case record(UUID, WealthRecordKind)
    /// 對存摺那一列（要訂閱）
    case anchorEdit(UUID)
    /// 轉帳那一列：問要不要刪（要訂閱）
    case transfer(UUID)
    /// [v25.566] 一期定存（WealthFacts.TimeDeposit.id；轉定存、定存到期、定存利息、⑥ 一格）：開定存表單（要訂閱）
    case timeDeposit(UUID)
}

/// 存摺明細的篩選（只列有的）
enum WealthLedgerFilter: String, CaseIterable, Identifiable {
    case all, inflow, outflow, cardBill, transfer, stock, deposit, anchor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .inflow: return "入帳"
        case .outflow: return "扣款"
        case .cardBill: return "卡費"
        case .transfer: return "轉帳"
        case .stock: return "交割"
        // [v25.566] 轉定存、定存到期、定存解約、定存利息
        case .deposit: return "定存"
        case .anchor: return "對存摺"
        }
    }
}

/// ① 看板頭部（同 WealthPageBoard 的欄位）
struct WealthCardBoard {
    var date = ""
    var dateIcon = "calendar"
    var capsule: String? = nil
    var capsuleIcon: String? = nil
    /// neutral＝一般膠囊字色
    var capsuleTone: MoneyTone = .neutral
    var label = ""
    var big = ""
    var bigTone: MoneyTone? = nil
    var line = FinanceLine()
    /// 手寫（英文兩行；不寫＝空）
    var greeting: [String] = []
    /// 整個頭部 VoiceOver 念的一句
    var accessibilityText = ""
}

/// 看板下的一格（MoneyTile：圖示＋標籤／大字／一行灰字；要上色的那段放 accent）
struct WealthCardTile: Identifiable {
    let id: String
    let icon: String
    let tint: TripBoardTint
    let label: String
    let value: String
    var valueTone: MoneyTone? = nil
    var detail: String? = nil
    var accent: String? = nil
    var accentTone: MoneyTone = .neutral
    var tap: WealthCardTap = .none
}

/// 清單的一列（刷卡、接下來、存摺明細）
struct WealthCardRow: Identifiable {
    let id: String
    let date: Date
    /// 日期塊「12」
    let dayText: String
    /// 日期塊下面「10月」「10月・三」
    let monthText: String
    /// 圓裡一個字
    let glyph: String
    /// 圓的顏色
    let mark: UInt32
    let title: String
    let detail: String
    let amountText: String
    var amountTone: MoneyTone? = nil
    /// 金額底下小字「餘額 128,400」「扣完剩 76,060」
    var sub: String? = nil
    /// 標題旁小牌「定期」「下一期」
    var tag: String? = nil
    /// 扣完剩變負的：整列 warn
    var warn = false
    var open: WealthCardOpen = .none
    var accessibilityText = ""
    /// 刷卡：WealthCardEntry.id（〔算到下一期〕）
    var entryId: String? = nil
    /// 刷卡：已經〔算到下一期〕了
    var shifted = false
    /// 刷卡：分類（圖例篩選）
    var category = ""
    /// 存摺明細：篩選、月份、幣別、帶正負的金額（月份小計）
    var filter: WealthLedgerFilter = .all
    var monthKey = ""
    var code = "NT$"
    var signedValue: Double = 0
}

/// 資料卡的一列（號碼類只放遮好的字；secret 不是 nil 才有〔顯示〕）
struct WealthCardInfo: Identifiable {
    enum Secret: String {
        case cardNumber, expiry, securityCode, easyCard, iPass, happyGo, account, policy
    }
    let id: String
    let label: String
    let value: String
    var secret: Secret? = nil
    var tone: MoneyTone? = nil
    var tap: WealthCardTap = .none
    /// 列尾那顆小字按鈕（「改」）；nil＝整列點
    var tapTitle: String? = nil
}

/// 這期帳單的一段分類（長條＋圖例）
struct WealthCardPart: Identifiable {
    let id: String
    let name: String
    let value: Double
    /// 金額的字「6,820」（圖例：名稱＋這個）
    let text: String
    let theme: MoneyArtTheme
}

/// ③ 這期帳單
struct WealthCardStatementBlock {
    let key: String
    /// 「10 月帳單」
    let title: String
    /// 「9/13–10/12・23 筆」
    let trailing: String
    /// 「NT$18,600・10/27（二）截止・還有 8 天」
    var headline = FinanceLine()
    /// 「✓ 10/25 從房貸扣款繳了 18,600」
    var paidLine: String? = nil
    /// 〔改一下 ›〕（你標的、App 當作的）
    var canEditPaid = false
    /// 〔取消已繳〕（你標的）
    var canUnpay = false
    /// 〔標成已繳〕〔帳單金額不一樣〕
    var showButtons = false
    var minimumNote: String? = nil
    /// 「（你輸入的；App 算的是 17,420，差 +1,180）」
    var statedNote: String? = nil
    /// 帳單比 App 算的多：〔補記差額〕的金額
    var diffAmount: Double? = nil
    /// 這一期的結帳日：〔補記差額〕那筆記帳的日期（記成今天會算進下一期，下一期多算一次）
    var close: Date? = nil
    /// 「含前期未繳 8,600」
    var carriedNote: String? = nil
    var parts: [WealthCardPart] = []
    /// 新到舊
    var rows: [WealthCardRow] = []
    var closingNote: String? = nil
}

/// ⑥ 每期帳單的一根
struct WealthCardHistoryBar: Identifiable {
    let key: String
    /// x 軸的字「10月」
    let axis: String
    let amount: Double
    let paid: Bool
    /// 要繳（含逾期）：卡面色
    let due: Bool
    /// 按住的泡泡「9 月帳單（8/13–9/12）39,300・含國泰人壽 24,000・9/26 已繳」
    let bubble: String
    var id: String { key }
}

/// 連到這張卡／這個帳戶的一列
struct WealthCardLinkRow: Identifiable {
    let id: String
    let icon: String
    let tint: UInt32
    let title: String
    let detail: String
    let trailing: String
    var trailingTone: MoneyTone? = nil
    var open: WealthCardOpen = .none
    /// 長按〔改到別的帳戶…〕
    var moveExpenseId: UUID? = nil
    var moveIncomeId: UUID? = nil
}

/// ⑦ 年費與回饋小抄
struct WealthCardFee {
    var annualFee: String? = nil
    /// 「一年刷滿 24萬（12/1–11/30）」
    var waiveTitle: String? = nil
    /// 「今年 19.2萬・還差 4.8萬（還有 42 天）」「今年已達免年費 ✓」
    var waiveDetail: String? = nil
    var waiveFraction: Double = 0
    var waiveDone = false
    var perks: String? = nil

    var isEmpty: Bool { annualFee == nil && waiveTitle == nil && perks == nil }
}

/// 白卡裡的一格（FinanceTileGrid：外幣、今年進來／出去／利息）
struct WealthCardFTile: FinanceTileContent {
    let id: String
    let label: String
    let value: String
    var valueTone: MoneyTone? = nil
    var sub: String = ""
    var subTone: MoneyTone? = nil
    var isTappable: Bool = false
    var tapHint: String = ""
}

/// 信用卡頁的各區
struct WealthCardCredit {
    var statement: WealthCardStatementBlock? = nil
    var unbilledTrailing = ""
    var unbilledHead = FinanceLine()
    var unbilledRows: [WealthCardRow] = []
    var recurring: [WealthCardLinkRow] = []
    var recurringTrailing: String? = nil
    var recurringIds: [UUID] = []
    var history: [WealthCardHistoryBar] = []
    var historyAverage: Double = 0
    var historyAverageText = ""
    var historySummary = ""
    var fee = WealthCardFee()
    var info: [WealthCardInfo] = []
    var photos: [String] = []
    var isDisabled = false
    var faceColor = 0
}

/// 銀行帳戶頁的各區
struct WealthCardBank {
    var upcomingTrailing: String? = nil
    var upcoming: [WealthCardRow] = []
    var linkedOut: [WealthCardLinkRow] = []
    var linkedIn: [WealthCardLinkRow] = []
    var linkedTrailing: String? = nil
    var foreign: [WealthCardFTile] = []
    /// [v25.566] ⑤ 格子下一行（換匯怎麼記）；沒有外幣＝nil
    var foreignNote: String? = nil
    /// [v25.566] ⑤〔＋ 換匯〕（有外幣就有；按鈕本身擋訂閱）
    var canExchange = false
    /// [v25.566] ⑥ 定存：一期一格（照到期日）
    var deposits: [WealthCardDepositCell] = []
    /// [v25.566] ⑥ 標題右邊「1 筆・合計 NT$50萬」（遮住「1 筆」）
    var depositsTrailing: String? = nil
    /// [v25.566] 舊的「定存」種類帳戶、還沒補任何一期：一列〔補上利率和到期日 ›〕
    var legacyDepositPrompt = false
    /// [v25.566] ⑥ 最下〔＋ 定存〕（收起來的帳戶沒有）
    var canAddDeposit = false
    var yearTiles: [WealthCardFTile] = []
    var recordsTitle = ""
    /// 新到舊（只有今天以前）
    var ledger: [WealthCardRow] = []
    var filters: [WealthLedgerFilter] = []
    /// 月份小計用的幣別（一個幣別＝那個；好幾個＝台幣）
    var primaryCode = "NT$"
    var info: [WealthCardInfo] = []
    var note = ""
    var photos: [String] = []
    var hidden = false
    /// 收起來前問「還有 3,200，要轉到哪？」；存摺上是 0＝nil
    var leftover: String? = nil
}

/// [v25.566] ⑥ 定存的一格（FinanceProgressCell 畫；點了開那一期的定存表單）
struct WealthCardDepositCell: Identifiable {
    /// 那一期（WealthFacts.TimeDeposit.id；自動續存還沒寫進帳本的那一期也是固定 id）
    let id: UUID
    let progress: FinanceProgressData
    /// 整格 VoiceOver 念的一句（按鈕的 label）
    let accessibilityText: String
    /// 到期了、還沒決定怎麼處理（格子下一行 warn）
    var waiting = false
}

/// 證券戶頁
struct WealthCardBroker {
    var holdings: [MoneyItem] = []
    var info: [WealthCardInfo] = []
    var note = ""
    var photos: [String] = []
}

/// 保單頁
struct WealthCardPolicy {
    var coverage: [String] = []
    var payment: String? = nil
    var medicalNote: String? = nil
    var info: [WealthCardInfo] = []
    var note = ""
    var photos: [String] = []
}

// MARK: - 整頁

struct WealthCardData {
    let id: UUID
    let kind: WealthCardKind
    /// 工具列中間的名字
    let title: String
    /// 編輯表單的類型
    let editKind: WealthAccountKind
    var board = WealthCardBoard()
    var scene: MoneyBoardScene = .towers(.empty)
    var band: CGFloat = 132
    var seed = 0
    var tiles: [WealthCardTile] = []
    /// 保單：看板下的繳費進度格
    var progress: FinanceProgressData? = nil
    /// ⓪ 換項目列（不到兩個＝空）
    var switcher: [FinanceSwitcherItem] = []
    /// 記一筆選單要用的幣別（銀行）
    var codes: [String] = ["NT$"]
    var credit: WealthCardCredit? = nil
    var bank: WealthCardBank? = nil
    var broker: WealthCardBroker? = nil
    var policy: WealthCardPolicy? = nil

    init(id: UUID, kind: WealthCardKind, title: String, editKind: WealthAccountKind) {
        self.id = id
        self.kind = kind
        self.title = title
        self.editKind = editKind
    }

    /// 在主執行緒叫（ntdWanString 用到 NumberFormatter）。找不到那筆里程碑＝nil
    static func build(id: UUID, facts: WealthFacts, life: LifeStore, expense: ExpenseStore, finance: FinanceStore,
                      now: Date = Date(), masked: Bool) -> WealthCardData? {
        guard let m = life.milestones.first(where: { $0.id == id }) else { return nil }
        let expenses = expense.expenses
        let byId = Dictionary(expenses.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let x = WealthCardCtx(facts: facts, item: m, milestones: life.milestones, book: life.wealthBook,
                              expenses: expenses, expensesById: byId, incomes: expense.incomes,
                              stocks: finance.stocks, rates: FinanceRates(expense), today: WealthCal.day(now),
                              masked: masked, rateDate: AppQuoteClock.ratesUpdatedAt,
                              depositBankIds: Set(life.wealthDeposits.all.map { $0.bankId }))
        switch m.financeSubCategory ?? .bank {
        case .creditCard:
            guard let c = facts.card(id) else { return nil }
            return buildCredit(x, c)
        case .bank:
            guard let a = facts.account(id) else { return nil }
            return buildBank(x, a)
        case .securities:
            guard let a = facts.account(id) else { return nil }
            return buildBroker(x, a)
        case .insurance:
            return buildPolicy(x)
        }
    }
}

/// build 一次要用的東西
private struct WealthCardCtx {
    let facts: WealthFacts
    let item: LifeMilestone
    let milestones: [LifeMilestone]
    let book: WealthBook
    let expenses: [Expense]
    let expensesById: [UUID: Expense]
    let incomes: [Income]
    let stocks: [Stock]
    let rates: FinanceRates
    let today: Date
    let masked: Bool
    /// [v25.566] 匯率是哪天更新的（AppQuoteClock.ratesUpdatedAt；外幣格子「10/19 匯率 32.0」；沒記過 nil）
    let rateDate: Date?
    /// [v25.566] 定存帳本裡有過任何一期的帳戶（含已經結束的）：舊定存帳戶的〔補上利率和到期日〕跟要確認同一條規則
    let depositBankIds: Set<UUID>
}

// MARK: - 字

enum WealthCardText {
    static let dots = "••••"
    private static let weekdays = ["日", "一", "二", "三", "四", "五", "六"]

    static func ntd(_ v: Double, masked: Bool) -> String { masked ? WealthFormat.masked : WealthFormat.ntd(v) }
    static func ntdWan(_ v: Double, masked: Bool) -> String { masked ? WealthFormat.masked : v.ntdWanString }
    static func plain(_ v: Double, code: String = "NT$", masked: Bool) -> String {
        masked ? dots : WealthFormat.plain(v, code: code)
    }
    static func wan(_ v: Double, masked: Bool) -> String { masked ? dots : WealthPageText.wan(v) }
    static func money(_ v: Double, code: String, masked: Bool) -> String {
        masked ? WealthFormat.masked : WealthFormat.money(v, code: code)
    }
    /// 「−52,340」「+80,000」（台幣不寫 NT$）
    static func signed(_ v: Double, out: Bool, code: String = "NT$", masked: Bool) -> String {
        masked ? dots : (out ? "−" : "+") + WealthFormat.plain(Swift.abs(v), code: code)
    }
    static func md(_ d: Date) -> String { WealthFormat.monthDay(d) }
    static func weekday(_ d: Date) -> String {
        let w = WealthCal.calendar.component(.weekday, from: d)
        return (w >= 1 && w <= 7) ? weekdays[w - 1] : ""
    }
    /// 「10/27（二）」
    static func mdw(_ d: Date) -> String { md(d) + "（" + weekday(d) + "）" }
    static func dayNum(_ d: Date) -> String { "\(WealthCal.calendar.component(.day, from: d))" }
    static func monthText(_ d: Date) -> String { "\(WealthCal.month(d))月" }
    /// 「2021/8」
    static func ym(_ d: Date) -> String {
        let c = WealthCal.calendar.dateComponents([.year, .month], from: d)
        return "\(c.year ?? 0)/\(c.month ?? 0)"
    }
    static func codeName(_ code: String) -> String { FinanceRates.isNTD(code) ? "台幣" : code }

    /// 刷卡的分類字（變動支出照分類；固定支出歸「訂閱」「保險」「電信」…）
    static func categoryName(_ e: Expense?) -> String {
        guard let e else { return "其他" }
        if e.expenseType == .fixed {
            switch e.fixedCategory {
            case .subscription?: return "訂閱"
            case .insurance?: return "保險"
            case .telecom?: return "電信"
            case .utilities?: return "水電"
            case .loan?: return "貸款"
            case .rent?: return "房租"
            case .management?: return "管理費"
            case .other?, nil: return "定期"
            }
        }
        return e.variableCategory?.rawValue ?? "其他"
    }

    /// 定期扣款多久一次「每月 6 日」「每季 6 日」「每年 8/15」
    static func schedule(_ e: Expense) -> String {
        let day = WealthCal.calendar.component(.day, from: e.date)
        switch e.recurrence {
        case .monthly?: return "每月 \(day) 日"
        case .quarterly?: return "每季 \(day) 日"
        case .yearly?: return "每年 " + md(e.date)
        case nil: return md(e.date)
        }
    }

    /// 收入多久一次「每月 5 日」「每年 3/1」
    static func incomeSchedule(_ i: Income) -> String {
        let day = WealthCal.calendar.component(.day, from: i.date)
        switch i.period {
        case .monthly: return "每月 \(day) 日"
        case .yearly: return "每年 " + md(i.date)
        case .once: return md(i.date)
        }
    }

    /// 定期扣款換成一個月多少（月繳＋季繳÷3＋年繳÷12）
    static func monthly(_ e: Expense, rates: FinanceRates) -> Double {
        let ntd = WealthSchedule.ntd(of: e, raw: e.amount, rates: rates)
        switch e.recurrence {
        case .monthly?: return ntd
        case .quarterly?: return ntd / 3
        case .yearly?: return ntd / 12
        case nil: return 0
        }
    }

    /// 證券戶的短名（「元大證券」→「元大」）
    static func brokerShort(_ name: String) -> String {
        let s = name.replacingOccurrences(of: "證券", with: "").trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? name : s
    }
}

// MARK: - 信用卡（§4.1）

extension WealthCardData {
    fileprivate static func buildCredit(_ x: WealthCardCtx, _ c: WealthFacts.Card) -> WealthCardData {
        let m = x.item
        let prefs = x.book.card(c.id)
        let shifted = Set(prefs.nextPeriodEntries ?? [])
        var d = WealthCardData(id: c.id, kind: .card, title: c.fullName, editKind: .card)
        d.seed = MoneyItem.seed(c.id)
        d.band = 132
        d.board = creditBoard(x, c)
        d.scene = .cardCycle(cycleScene(c, today: x.today))
        d.tiles = creditTiles(x, c)
        d.switcher = cardSwitcher(x, current: c)

        var cr = WealthCardCredit()
        cr.isDisabled = c.isDisabled
        cr.faceColor = c.faceColor
        if let s = c.dueStatement ?? c.statements.last(where: { $0.isClosed }) {
            cr.statement = statementBlock(s, c: c, x: x, shifted: shifted)
        }

        // ④ 還沒出帳
        let b = c.billingDay
        let curStart = WealthCal.addDays(1, to: WealthCardCycle.previousClose(c.nextClose, billingDay: b))
        // 還沒結帳的每一期（含〔算到下一期〕被推到更後面那一期的）：跟 Facts 的 unbilled 同一群
        let un = c.entries.filter { closeOf($0, billingDay: b, shifted: shifted) >= c.nextClose }
        // 前期未繳（上一期只繳一部分、自動扣最低剩下的）算在還沒結帳那一期：四格的「還沒出帳」（Facts unbilled）含它，
        // 這一句也寫出來，兩個數才對得上（驗證 build/v3/verify/card_text.py C）
        let carried = c.statements.filter { $0.status == .unbilled }.reduce(0.0) { $0 + $1.carriedIn }
        cr.unbilledTrailing = WealthCardText.md(c.nextClose) + " 結帳・" + WealthCardText.md(c.nextDue) + " 截止"
        var unRuns: [FinanceRun] = []
        if un.isEmpty {
            unRuns.append(FinanceRun(text: "這期還沒刷"))
        } else {
            let total = un.reduce(0.0) { $0 + $1.amount }
            unRuns.append(FinanceRun(text: WealthCardText.md(curStart) + " 起刷了 "))
            unRuns.append(FinanceRun(text: WealthCardText.plain(total, masked: x.masked), bold: true))
            unRuns.append(FinanceRun(text: "・\(un.count) 筆"))
        }
        if carried > 0.5 {
            unRuns.append(FinanceRun(text: "＋前期未繳 "))
            unRuns.append(FinanceRun(text: WealthCardText.plain(carried, masked: x.masked), bold: true))
        }
        cr.unbilledHead = FinanceLine(runs: unRuns)
        cr.unbilledRows = un.reversed().map { entryRow($0, x: x, shifted: shifted.contains($0.id)) }

        // ⑤ 綁在這張卡的定期扣款
        let recs = recurringOnCard(c.id, x: x)
        cr.recurringIds = recs.map(\.id)
        cr.recurring = recs.map { e -> WealthCardLinkRow in
            let ntd = WealthSchedule.ntd(of: e, raw: e.amount, rates: x.rates)
            return WealthCardLinkRow(id: e.id.uuidString, icon: MoneyArtTheme.of(e).hero, tint: MoneyArtTheme.of(e).tint,
                                     title: e.title, detail: WealthCardText.schedule(e),
                                     trailing: WealthCardText.plain(ntd, masked: x.masked), open: .expense(e.id))
        }
        if !recs.isEmpty {
            let avg = recs.reduce(0.0) { $0 + WealthCardText.monthly($1, rates: x.rates) }
            cr.recurringTrailing = "平均每月約 " + WealthCardText.plain(avg, masked: x.masked)
        }

        // ⑥ 每期帳單
        fillHistory(&cr, c: c, x: x, shifted: shifted)
        // ⑦ 年費與回饋
        cr.fee = feeBlock(c: c, prefs: prefs, x: x)
        // ⑧ 卡片資料、⑨ 照片
        cr.info = cardInfo(c, x: x)
        cr.photos = m.photoFileNames ?? []
        d.credit = cr
        return d
    }

    /// 這一筆刷卡算哪一期（同 WealthFacts.statements：結帳日當天算這期；〔算到下一期〕往後一期）
    fileprivate static func closeOf(_ e: WealthCardEntry, billingDay b: Int, shifted: Set<String>) -> Date {
        var close = WealthCardCycle.statementClose(for: e.date, billingDay: b)
        if shifted.contains(e.id) { close = WealthCardCycle.nextClose(after: close, billingDay: b) }
        return close
    }

    /// 現在刷這張卡、還沒結束的定期扣款（改卡的歷史照今天找）
    fileprivate static func recurringOnCard(_ cardId: UUID, x: WealthCardCtx) -> [Expense] {
        let list = x.expenses.filter { e -> Bool in
            guard e.expenseType == .fixed, e.recurrence != nil else { return false }
            if let end = e.endDate, WealthCal.day(end) < x.today { return false }
            return WealthFacts.recurringTarget(e, at: x.today, history: x.book.links(e.id)) == cardId
        }
        func rank(_ e: Expense) -> Int {
            switch e.recurrence {
            case .monthly?: return 0
            case .quarterly?: return 1
            case .yearly?: return 2
            case nil: return 3
            }
        }
        return list.sorted { l, r in
            let rl = rank(l)
            let rr = rank(r)
            if rl != rr { return rl < rr }
            let dl = WealthCal.calendar.component(.day, from: l.date)
            let dr = WealthCal.calendar.component(.day, from: r.date)
            if dl != dr { return dl < dr }
            return l.title < r.title
        }
    }

    fileprivate static func entryRow(_ e: WealthCardEntry, x: WealthCardCtx, shifted: Bool) -> WealthCardRow {
        let exp = x.expensesById[e.expenseId]
        let title = exp?.title ?? "刷卡"
        let cat = WealthCardText.categoryName(exp)
        let theme = exp.map { MoneyArtTheme.of($0) } ?? MoneyArtTheme.misc
        let isFixed = exp?.expenseType == .fixed
        let amount = x.masked ? WealthCardText.dots : WealthFormat.grouped(e.amount.rounded(), decimals: 0)
        var r = WealthCardRow(id: e.id, date: e.date, dayText: WealthCardText.dayNum(e.date),
                              monthText: WealthCardText.monthText(e.date), glyph: String(cat.prefix(1)),
                              mark: theme.tint, title: title, detail: cat, amountText: amount)
        if shifted {
            r.tag = "下一期"
        } else if isFixed {
            r.tag = "定期"
        }
        r.open = .expense(e.expenseId)
        r.entryId = e.id
        r.shifted = shifted
        r.category = cat
        let said = x.masked ? "金額已遮住" : WealthPageText.spoken(e.amount)
        r.accessibilityText = WealthPageText.spokenDate(e.date) + "，" + title + "，" + cat + "，" + said
        return r
    }

    // MARK: 看板

    fileprivate static func creditBoard(_ x: WealthCardCtx, _ c: WealthFacts.Card) -> WealthCardBoard {
        var b = WealthCardBoard()
        let t = x.today
        let mk = x.masked
        b.date = WealthPageText.boardDate(t) + "・下次結帳 " + WealthCardText.md(c.nextClose)
        b.dateIcon = "creditcard.fill"
        let payer: String? = c.payerName
        let lastClosed = c.statements.last(where: { $0.isClosed })
        let toClose = WealthCal.days(from: t, to: c.nextClose)
        var bigValue: Double? = nil

        if c.isDisabled, c.due < 0.5 {
            b.capsule = c.closedDate.map { WealthCardText.md($0) + " 停用" } ?? "已停用"
            b.capsuleIcon = "pause.circle.fill"
            b.label = "已停用"
            b.big = mk ? WealthFormat.masked : "NT$0"
            b.line = FinanceLine.text("歷史帳單都還在")
        } else if let s = c.dueStatement, s.status == .overdue {
            let n = Swift.max(1, WealthCal.days(from: s.due, to: t))
            b.capsule = "已過截止日 \(n) 天"
            b.capsuleIcon = "exclamationmark.circle.fill"
            b.capsuleTone = .bad
            b.label = s.label + "還沒繳"
            b.big = WealthCardText.ntd(s.amount, masked: mk)
            b.bigTone = .bad
            bigValue = s.amount
            b.line = FinanceLine(runs: [
                FinanceRun(text: "可能有循環利息與違約金，最低應繳約 "),
                FinanceRun(text: WealthCardText.plain(s.minimumDue, masked: mk), bold: true),
            ])
            b.greeting = ["Pay", "today!"]
        } else if let s = c.dueStatement {
            let n = WealthCal.days(from: t, to: s.due)
            let range = WealthCardText.md(s.start) + "–" + WealthCardText.md(s.close) + " 刷的"
            b.big = WealthCardText.ntd(s.amount, masked: mk)
            bigValue = s.amount
            if c.payMode.isAuto {
                let short = payerShortage(c, statement: s, x: x)
                let dayWord = n <= 0 ? "今天" : "\(n) 天"
                b.label = s.label
                if let sh = short {
                    b.capsule = (payer ?? "扣款帳戶") + "會差 " + WealthCardText.plain(sh.short, masked: mk)
                    b.capsuleIcon = "exclamationmark.triangle.fill"
                    b.capsuleTone = .warn
                    b.line = FinanceLine(runs: [
                        FinanceRun(text: WealthCardText.md(sh.date) + " " + (payer ?? "扣款帳戶") + "預估只剩 "),
                        FinanceRun(text: WealthCardText.plain(sh.before, masked: mk), bold: true, tone: .warn),
                    ])
                    b.greeting = ["Top it", "up!"]
                } else {
                    let from = payer.map { "從\($0)扣" } ?? "扣款"
                    b.capsule = WealthCardText.md(s.due) + " " + from + "・" + dayWord
                    b.capsuleIcon = "calendar"
                    let how = c.payMode == .autoMin ? "最低" : "全額"
                    b.line = FinanceLine.text(range + "・" + WealthCardText.mdw(s.due) + from + how)
                    b.greeting = ["Stay", "on track!"]
                }
            } else {
                b.capsule = n <= 0 ? "今天截止" : WealthCardText.md(s.due) + " 截止・\(n) 天"
                b.capsuleIcon = "calendar"
                b.capsuleTone = n <= 3 ? .warn : .neutral
                b.label = s.label + "要繳"
                let usual = payer.map { "，通常從\($0)" } ?? ""
                b.line = FinanceLine.text(range + "・" + c.payMode.title + usual)
                b.greeting = ["Pay", "on time!"]
            }
        } else if toClose >= 0, toClose <= 3, !c.isDisabled {
            b.capsule = toClose == 0 ? "今天結帳" : "結帳・\(toClose) 天"
            b.capsuleIcon = "flag.fill"
            b.label = "本期累積"
            b.big = WealthCardText.ntd(c.unbilled, masked: mk)
            bigValue = c.unbilled
            b.line = FinanceLine(runs: [
                FinanceRun(text: "這幾天刷的"),
                FinanceRun(text: "可能算下一期", bold: true),
                FinanceRun(text: "（看店家什麼時候請款）"),
            ])
            b.greeting = ["Bill", "closing"]
        } else if c.entries.isEmpty {
            b.label = "本期累積"
            b.big = mk ? WealthFormat.masked : "NT$0"
            b.line = FinanceLine.text("記帳時選這張卡就會算進來")
            b.greeting = ["Hello,", "card!"]
        } else if !c.payMode.isAuto, let p = lastClosed, p.isPaid {
            b.capsule = p.label + "已繳 ✓"
            b.capsuleIcon = "checkmark.circle.fill"
            b.capsuleTone = .good
            b.label = p.label + "已繳"
            b.big = WealthCardText.ntd(p.amount, masked: mk)
            bigValue = p.amount
            let when = WealthCardText.md(p.paidOn ?? p.due)
            let from = p.paidFrom.flatMap { x.facts.account($0)?.name }.map { " 從\($0)" } ?? " "
            b.line = FinanceLine.text(when + from + "繳的・下次 " + WealthCardText.md(c.nextClose) + " 結帳")
            b.greeting = ["All", "paid!"]
        } else {
            if let p = lastClosed, p.isPaid {
                b.capsule = p.label + (c.payMode.isAuto ? "已扣 ✓" : "已繳 ✓")
                b.capsuleIcon = "checkmark.circle.fill"
                b.capsuleTone = .good
            }
            b.label = "本期累積（還沒結帳）"
            b.big = WealthCardText.ntd(c.unbilled, masked: mk)
            bigValue = c.unbilled
            let from = payer.map { " 從\($0)" } ?? " "
            b.line = FinanceLine.text(WealthCardText.md(c.nextClose) + " 結帳・" + WealthCardText.md(c.nextDue) + from
                                      + c.payMode.title)
            b.greeting = ["Spend", "wisely!"]
        }
        let said: String
        if mk {
            said = "金額已遮住"
        } else if let v = bigValue {
            said = WealthPageText.spoken(v)
        } else {
            said = b.big
        }
        var a11y = c.fullName + "，" + b.label + " " + said
        if let cap = b.capsule { a11y += "，" + cap }
        let plainLine = b.line.plain
        if !plainLine.isEmpty { a11y += "。" + plainLine }
        b.accessibilityText = a11y
        return b
    }

    /// 自動扣的卡：扣款帳戶 30 天內第一次不夠扣的就是這張卡的這一期帳單
    fileprivate static func payerShortage(_ c: WealthFacts.Card, statement s: WealthStatement,
                                          x: WealthCardCtx) -> WealthShortage? {
        guard let acc = x.facts.account(c.payerId), let sh = acc.shortage else { return nil }
        // 卡費那一列的標題＝「卡名 10 月帳單」（WealthFacts 組的）；整段比，卡名開頭一樣的別張卡不會被認成這張
        guard sh.kind == .cardBill, WealthCal.day(sh.date) == WealthCal.day(s.due),
              sh.title.hasPrefix(c.name + " " + s.label) else { return nil }
        return sh
    }

    // MARK: 風景：帳單週期

    fileprivate static func cycleScene(_ c: WealthFacts.Card, today: Date) -> WealthCycleScene {
        let b = c.billingDay
        let curStart = WealthCal.addDays(1, to: WealthCardCycle.previousClose(c.nextClose, billingDay: b))
        let last = c.statements.last(where: { $0.isClosed })
        let first = WealthCal.day(last?.start ?? curStart)
        let end = WealthCal.day(c.nextDue)
        let days = Swift.max(2, WealthCal.days(from: first, to: end) + 1)
        var sums: [Int: Double] = [:]
        for e in c.entries {
            let i = WealthCal.days(from: first, to: e.date)
            guard i >= 0, i < days, WealthCal.day(e.date) <= today else { continue }
            sums[i, default: 0] += Swift.max(0, e.amount)
        }
        let top = sums.values.max() ?? 0
        let lastClose: Date? = last.map { WealthCal.day($0.close) }
        var bars: [WealthCycleScene.Bar] = []
        for (i, v) in sums.sorted(by: { $0.key < $1.key }) where v > 0.5 && top > 0 {
            let day = WealthCal.addDays(i, to: first)
            let billed: Bool = lastClose.map { day <= $0 } ?? false
            bars.append(WealthCycleScene.Bar(day: i, height: Swift.min(1, (v / top).squareRoot()), billed: billed))
        }
        var marks: [WealthCycleScene.Mark] = []
        func addMark(_ date: Date, _ kind: WealthCycleScene.Mark.Kind, _ paid: Bool) {
            let i = WealthCal.days(from: first, to: date)
            if i >= 0 && i < days { marks.append(WealthCycleScene.Mark(day: i, kind: kind, paid: paid)) }
        }
        if let l = last {
            addMark(l.close, .close, false)
            addMark(l.due, .due, l.isPaid)
        }
        addMark(c.nextClose, .close, false)
        addMark(c.nextDue, .due, false)
        let ci = WealthCal.days(from: first, to: c.nextClose)
        let closingTo: Int? = (ci >= 0 && ci < days) ? ci : nil
        let closingFrom: Int? = closingTo.map { Swift.max(0, $0 - 2) }
        let ti = Swift.min(Swift.max(0, WealthCal.days(from: first, to: today)), days - 1)
        return WealthCycleScene(days: days, todayIndex: ti, bars: bars, marks: marks, tint: c.faceColor,
                                closingFrom: closingFrom, closingTo: closingTo)
    }

    // MARK: 四格

    fileprivate static func creditTiles(_ x: WealthCardCtx, _ c: WealthFacts.Card) -> [WealthCardTile] {
        let mk = x.masked
        var tiles: [WealthCardTile] = []
        let overdue = c.dueStatement?.isOverdue == true
        let dueDetail: String
        if let s = c.dueStatement {
            dueDetail = s.isOverdue ? "已過截止日" : WealthCardText.md(s.due) + " 截止"
        } else if let p = c.lastPaid {
            dueDetail = p.label + "已繳"
        } else {
            dueDetail = "沒有要繳的"
        }
        tiles.append(WealthCardTile(id: "due", icon: "doc.text.fill", tint: .orange, label: "要繳",
                                    value: WealthCardText.ntd(c.due, masked: mk), valueTone: overdue ? .bad : nil,
                                    detail: dueDetail, tap: .scroll(.statement)))
        tiles.append(WealthCardTile(id: "unbilled", icon: "cart.fill", tint: .green, label: "還沒出帳",
                                    value: WealthCardText.ntdWan(c.unbilled, masked: mk),
                                    detail: "\(c.unbilledCount) 筆・" + WealthCardText.md(c.nextClose) + " 結帳",
                                    tap: .scroll(.unbilled)))
        if let limit = c.limit, let avail = c.available, let usage = c.usage {
            tiles.append(WealthCardTile(id: "available", icon: "creditcard.fill", tint: .purple, label: "還能刷",
                                        value: WealthCardText.ntdWan(avail, masked: mk),
                                        detail: "額度 " + WealthCardText.wan(limit, masked: mk),
                                        tap: .scroll(.cardInfo)))
            tiles.append(WealthCardTile(id: "usage", icon: "chart.pie.fill", tint: .azure, label: "額度用了",
                                        value: WealthFormat.percent(usage),
                                        valueTone: c.usageTier >= 2 ? .warn : nil,
                                        detail: c.usageTierName, tap: .scroll(.statement)))
        } else {
            tiles.append(WealthCardTile(id: "limit", icon: "plus.circle.fill", tint: .purple, label: "額度",
                                        value: "沒填", detail: "這張卡沒填額度 ›", tap: .edit(nil)))
        }
        return tiles
    }

    // MARK: ③ 這期帳單

    fileprivate static func statementBlock(_ s: WealthStatement, c: WealthFacts.Card, x: WealthCardCtx,
                                           shifted: Set<String>) -> WealthCardStatementBlock {
        let mk = x.masked
        let b = c.billingDay
        let entries = c.entries.filter { closeOf($0, billingDay: b, shifted: shifted) == s.close }
        let trailing = WealthCardText.md(s.start) + "–" + WealthCardText.md(s.close) + "・\(entries.count) 筆"
        var blk = WealthCardStatementBlock(key: s.key, title: s.label, trailing: trailing)
        blk.close = s.close

        // 一句
        var runs: [FinanceRun] = [FinanceRun(text: WealthCardText.ntd(s.amount, masked: mk), bold: true)]
        let n = WealthCal.days(from: x.today, to: s.due)
        switch s.status {
        case .overdue:
            runs.append(FinanceRun(text: "・" + WealthCardText.mdw(s.due) + "截止・"))
            runs.append(FinanceRun(text: "已過截止日 \(Swift.max(1, -n)) 天", tone: .bad))
        case .due:
            let left = n <= 0 ? "今天截止" : "還有 \(n) 天"
            runs.append(FinanceRun(text: "・" + WealthCardText.mdw(s.due) + "截止・" + left))
        default:
            runs.append(FinanceRun(text: "・" + WealthCardText.mdw(s.due) + "截止"))
        }
        blk.headline = FinanceLine(runs: runs)

        // 已繳那一行、兩顆按鈕
        let when = WealthCardText.md(s.paidOn ?? s.due)
        let fromName: String? = s.paidFrom.flatMap { x.facts.account($0)?.name }
        let paidAmt = WealthCardText.plain(s.paidAmount, masked: mk)
        switch s.status {
        case .paid:
            if s.isExplicitPaid {
                blk.paidLine = "✓ " + when + (fromName.map { " 從\($0)繳了 " } ?? " 繳了 ") + paidAmt
                blk.canEditPaid = true
                blk.canUnpay = true
            } else if c.payMode.isAuto {
                blk.paidLine = "✓ " + when + (fromName.map { " 從\($0)扣了 " } ?? " 已扣 ") + paidAmt
            } else {
                // 自己繳／每次問我的卡，改版前（trackFrom 以前）截止的帳單一律當作繳了
                blk.paidLine = "✓ " + when + (fromName.map { " 從\($0)繳了 " } ?? " 繳了 ") + paidAmt
            }
        case .assumedPaid:
            blk.paidLine = "✓ App 當作 " + when + (fromName.map { " 從\($0)繳了 " } ?? " 繳了 ") + paidAmt
            blk.canEditPaid = true
        case .due, .overdue:
            blk.showButtons = true
        case .unbilled:
            break
        }
        if s.isPaid, s.amount - s.paidAmount > 0.5, var line = blk.paidLine {
            line += "（剩 " + WealthCardText.plain(s.amount - s.paidAmount, masked: mk) + " 算進下一期）"
            blk.paidLine = line
        }
        if !c.payMode.isAuto, s.status == .due || s.status == .overdue {
            blk.minimumNote = "最低應繳約 " + WealthCardText.plain(s.minimumDue, masked: mk)
                + "（一般消費的 10%，以帳單為準）。只繳最低，剩下的會算循環利息。"
        }
        if let diff = s.statedDiff, Swift.abs(diff) > 0.5 {
            let sign = diff > 0 ? "+" : "-"
            let diffText = mk ? WealthCardText.dots : sign + WealthFormat.grouped(Swift.abs(diff).rounded(), decimals: 0)
            blk.statedNote = "（你輸入的；App 算的是 " + WealthCardText.plain(s.computedAmount, masked: mk)
                + "，差 " + diffText + "）"
            if diff > 0.5 { blk.diffAmount = diff.rounded() }
        }
        if s.carriedIn > 0.5 {
            blk.carriedNote = "含前期未繳 " + WealthCardText.plain(s.carriedIn, masked: mk)
        }

        // 分類長條（前 4 類＋其他）
        var sums: [String: Double] = [:]
        var themes: [String: MoneyArtTheme] = [:]
        for e in entries {
            let exp = x.expensesById[e.expenseId]
            let cat = WealthCardText.categoryName(exp)
            sums[cat, default: 0] += e.amount
            if themes[cat] == nil { themes[cat] = exp.map { MoneyArtTheme.of($0) } ?? MoneyArtTheme.misc }
        }
        let ranked = sums.filter { $0.key != "其他" && $0.value > 0.5 }.sorted { $0.value > $1.value }
        var parts: [WealthCardPart] = []
        var rest = sums["其他"] ?? 0
        for (i, p) in ranked.enumerated() {
            if i < 4 {
                let text = WealthCardText.plain(p.value, masked: mk)
                parts.append(WealthCardPart(id: p.key, name: p.key, value: p.value, text: text,
                                            theme: themes[p.key] ?? MoneyArtTheme.misc))
            } else {
                rest += p.value
            }
        }
        if rest > 0.5 {
            parts.append(WealthCardPart(id: "其他", name: "其他", value: rest,
                                        text: WealthCardText.plain(rest, masked: mk), theme: MoneyArtTheme.misc))
        }
        blk.parts = parts
        // 清單（圖例的「其他」＝不在前 4 類的）
        let shown = Set(parts.map(\.name).filter { $0 != "其他" })
        blk.rows = entries.reversed().map { e -> WealthCardRow in
            var r = entryRow(e, x: x, shifted: shifted.contains(e.id))
            if !shown.contains(r.category) { r.category = "其他" }
            return r
        }
        // 結帳日前 2 天到結帳日刷的：銀行可能算到下一期
        let from = WealthCal.addDays(-2, to: WealthCal.day(s.close))
        let near = entries.filter { WealthCal.day($0.date) >= from && WealthCal.day($0.date) <= WealthCal.day(s.close) }
        if !near.isEmpty {
            var seen: [String] = []
            for e in near {
                let t = WealthCardText.md(e.date)
                if !seen.contains(t) { seen.append(t) }
            }
            blk.closingNote = "App 用刷卡日分期，結帳日當天刷的算這期；" + seen.joined(separator: "、")
                + " 刷的 \(near.count) 筆銀行可能算到下一期。"
        }
        return blk
    }

    // MARK: ⑥ 每期帳單

    fileprivate static func fillHistory(_ cr: inout WealthCardCredit, c: WealthFacts.Card, x: WealthCardCtx,
                                        shifted: Set<String>) {
        let mk = x.masked
        let closed = Array(c.statements.filter { $0.isClosed }.suffix(12))
        guard !closed.isEmpty else { return }
        let b = c.billingDay
        var used: Set<String> = []
        var bars: [WealthCardHistoryBar] = []
        for s in closed {
            var axis = WealthCardText.monthText(s.close)
            if used.contains(axis) {
                let y = WealthCal.calendar.component(.year, from: s.close) % 100
                axis = "\(y)/\(WealthCal.month(s.close))"
            }
            used.insert(axis)
            let entries = c.entries.filter { closeOf($0, billingDay: b, shifted: shifted) == s.close }
            var bubble = s.label + "（" + WealthCardText.md(s.start) + "–" + WealthCardText.md(s.close) + "）"
                + WealthCardText.plain(s.amount, masked: mk)
            if let big = entries.max(by: { $0.amount < $1.amount }), s.amount > 0.5, big.amount >= s.amount * 0.4 {
                let name = x.expensesById[big.expenseId]?.title ?? "一筆"
                bubble += "・含" + name + " " + WealthCardText.plain(big.amount, masked: mk)
            }
            switch s.status {
            case .paid: bubble += "・" + WealthCardText.md(s.paidOn ?? s.due) + " 已繳"
            case .assumedPaid: bubble += "・" + WealthCardText.md(s.paidOn ?? s.due) + " 當作已繳"
            case .due: bubble += "・" + WealthCardText.md(s.due) + " 截止"
            case .overdue: bubble += "・過了截止日還沒繳"
            case .unbilled: break
            }
            let due = s.status == .due || s.status == .overdue
            bars.append(WealthCardHistoryBar(key: s.key, axis: axis, amount: Swift.max(0, s.amount), paid: s.isPaid,
                                             due: due, bubble: bubble))
        }
        cr.history = bars
        let avg = bars.reduce(0.0) { $0 + $1.amount } / Double(bars.count)
        cr.historyAverage = avg
        cr.historyAverageText = "平均 " + WealthCardText.wan(avg, masked: mk)
        cr.historySummary = "每期帳單，近 \(bars.count) 期" + (mk ? "" : "，平均 " + WealthPageText.spoken(avg))
    }

    // MARK: ⑦ 年費與回饋

    fileprivate static func feeBlock(c: WealthFacts.Card, prefs: WealthCardPrefs, x: WealthCardCtx) -> WealthCardFee {
        let mk = x.masked
        var f = WealthCardFee()
        if let a = x.item.annualFee, a > 0.5 {
            f.annualFee = WealthCardText.plain(a, masked: mk)
        }
        let waiveAmount = prefs.feeWaiveAmount.flatMap { $0 > 0.5 ? $0 : nil }
        let waiveCount = prefs.feeWaiveCount.flatMap { $0 > 0 ? $0 : nil }
        if waiveAmount != nil || waiveCount != nil {
            let startMonth = Swift.min(12, Swift.max(1, prefs.feeYearStartMonth ?? 1))
            let cal = WealthCal.calendar
            let year = cal.component(.year, from: x.today)
            var comps = DateComponents(year: year, month: startMonth, day: 1)
            var start = cal.date(from: comps) ?? x.today
            if start > x.today {
                comps.year = year - 1
                start = cal.date(from: comps) ?? start
            }
            let end = WealthCal.addDays(-1, to: WealthCal.addMonths(12, to: start))
            let span = "（" + WealthCardText.md(start) + "–" + WealthCardText.md(end) + "）"
            let inYear = c.entries.filter { WealthCal.day($0.date) >= start && WealthCal.day($0.date) <= x.today }
            let left = Swift.max(0, WealthCal.days(from: x.today, to: end))
            if let goal = waiveAmount {
                let spent = inYear.reduce(0.0) { $0 + $1.amount }
                f.waiveTitle = "一年刷滿 " + WealthCardText.wan(goal, masked: mk) + span
                f.waiveFraction = Swift.min(1, spent / goal)
                if spent >= goal {
                    f.waiveDone = true
                    f.waiveDetail = "今年已達免年費 ✓"
                } else {
                    f.waiveDetail = "今年 " + WealthCardText.wan(spent, masked: mk) + "・還差 "
                        + WealthCardText.wan(goal - spent, masked: mk) + "（還有 \(left) 天）"
                }
            } else if let goal = waiveCount {
                let n = inYear.count
                f.waiveTitle = "一年刷 \(goal) 次" + span
                f.waiveFraction = Swift.min(1, Double(n) / Double(goal))
                if n >= goal {
                    f.waiveDone = true
                    f.waiveDetail = "今年已達免年費 ✓"
                } else {
                    f.waiveDetail = "今年 \(n) 次・還差 \(goal - n) 次（還有 \(left) 天）"
                }
            }
        }
        if let p = prefs.perksNote?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            f.perks = p
        }
        return f
    }

    // MARK: ⑧ 卡片資料

    fileprivate static func cardInfo(_ c: WealthFacts.Card, x: WealthCardCtx) -> [WealthCardInfo] {
        let m = x.item
        var rows: [WealthCardInfo] = []
        rows.append(WealthCardInfo(id: "issuer", label: "發卡銀行", value: c.issuer ?? "—"))
        let cardName = (m.cardName ?? "").trimmingCharacters(in: .whitespaces)
        rows.append(WealthCardInfo(id: "name", label: "卡名", value: cardName.isEmpty ? m.title : cardName))
        let last4 = (c.last4 ?? "").isEmpty ? nil : c.last4
        if m.cardNumberCipher != nil || last4 != nil {
            rows.append(WealthCardInfo(id: "number", label: "卡號", value: "•••• " + (last4 ?? "••••"),
                                       secret: m.cardNumberCipher != nil ? .cardNumber : nil))
        }
        if m.expiryDate != nil {
            rows.append(WealthCardInfo(id: "expiry", label: "有效期限", value: "••／••", secret: .expiry))
        }
        // 第 6 題「我要存」：有存安全碼才多這一列（跟卡號同一顆 Face ID）
        if m.cardSecurityCipher != nil {
            rows.append(WealthCardInfo(id: "cvc", label: "安全碼", value: "•••", secret: .securityCode))
        }
        if let l = c.limit {
            rows.append(WealthCardInfo(id: "limit", label: "額度", value: WealthCardText.plain(l, masked: x.masked)))
        } else {
            rows.append(WealthCardInfo(id: "limit", label: "額度", value: "沒填", tap: .edit(nil), tapTitle: "填"))
        }
        let billing = "每月 \(c.billingDay) 日" + (c.billingDayMissing ? "（沒填，先當這天）" : "")
        let paying = "每月 \(c.paymentDay) 日" + (c.paymentDayMissing ? "（沒填，先當這天）" : "")
        rows.append(WealthCardInfo(id: "billing", label: "結帳日", value: billing,
                                   tone: c.billingDayMissing ? .warn : nil,
                                   tap: c.billingDayMissing ? .edit(.cardDays) : .none,
                                   tapTitle: c.billingDayMissing ? "填" : nil))
        rows.append(WealthCardInfo(id: "paying", label: "繳款截止日", value: paying,
                                   tone: c.paymentDayMissing ? .warn : nil,
                                   tap: c.paymentDayMissing ? .edit(.cardDays) : .none,
                                   tapTitle: c.paymentDayMissing ? "填" : nil))
        let how: String
        if let p = c.payerName {
            how = c.payMode.title + (c.payMode.isAuto ? "，從\(p)扣" : "，通常從\(p)")
        } else {
            how = c.payMode.title + "，還沒選從哪扣"
        }
        rows.append(WealthCardInfo(id: "pay", label: "卡費怎麼繳", value: how,
                                   tone: c.payerName == nil ? .warn : nil,
                                   tap: c.payerName == nil ? .edit(.payFrom) : .none,
                                   tapTitle: c.payerName == nil ? "選" : nil))
        rows.append(WealthCardInfo(id: "since", label: "核卡日", value: WealthPageText.ymd(m.date)))
        let tickets: [(String, String, String?, WealthCardInfo.Secret)] = [
            ("easy", "悠遊卡", m.easyCardNumber, .easyCard),
            ("ipass", "一卡通", m.iPassNumber, .iPass),
            ("happygo", "Happy Go", m.happyGoNumber, .happyGo),
        ]
        for (key, label, raw, secret) in tickets {
            guard let r = raw?.trimmingCharacters(in: .whitespaces), !r.isEmpty else { continue }
            rows.append(WealthCardInfo(id: key, label: label, value: CardVault.maskedTail(r), secret: secret))
        }
        let status: String
        if c.isDisabled {
            status = "已停用" + (c.closedDate.map { "（" + WealthCardText.md($0) + "）" } ?? "")
        } else {
            status = "使用中"
        }
        rows.append(WealthCardInfo(id: "status", label: "狀態", value: status))
        return rows
    }

    // MARK: ⓪ 換卡列

    fileprivate static func cardSwitcher(_ x: WealthCardCtx, current c: WealthFacts.Card) -> [FinanceSwitcherItem] {
        let list = WealthPageText.orderCards(x.facts.cards.filter { $0.isDisabled == c.isDisabled })
        guard list.count > 1 else { return [] }
        return list.map { k -> FinanceSwitcherItem in
            let name = k.nickname ?? k.name
            let v = k.due > 0.5 ? k.due : k.unbilled
            let trailing = x.masked ? "" : WealthFormat.grouped(v.rounded(), decimals: 0)
            return FinanceSwitcherItem(id: k.id, title: MoneyBoardText.short(name, max: 8), trailing: trailing,
                                       tone: k.dueStatement?.isOverdue == true ? .bad : .neutral)
        }
    }
}

// MARK: - 銀行帳戶（§4.2）

extension WealthCardData {
    fileprivate static func buildBank(_ x: WealthCardCtx, _ a: WealthFacts.Account) -> WealthCardData {
        let m = x.item
        var d = WealthCardData(id: a.id, kind: .bank, title: a.name, editKind: .bank)
        d.seed = MoneyItem.seed(a.id)
        d.band = 132
        d.codes = WealthPageText.codes(a).map { WealthFacts.norm($0) }
        d.board = bankBoard(x, a)
        d.scene = .tide(tideScene(a, x: x))
        d.tiles = bankTiles(x, a)
        d.switcher = bankSwitcher(x, current: a)

        var bk = WealthCardBank()
        bk.hidden = a.hidden
        bk.primaryCode = WealthFacts.norm(a.singleCode ?? "NT$")
        // ③ 接下來 30 天
        bk.upcoming = a.next30.map { upcomingRow($0, x: x) }
        if !a.next30.isEmpty {
            var t = "\(a.next30.count) 件"
            if let low = a.lowestNTD { t += "・最低 " + WealthCardText.wan(low, masked: x.masked) }
            bk.upcomingTrailing = t
        }
        // ④ 連到這個帳戶的
        fillLinks(&bk, a: a, x: x)
        // ⑤ 外幣（[v25.566] 有外幣就出現；只有台幣才不出現）
        fillForeign(&bk, a: a, codes: d.codes, x: x)
        // ⑥ [v25.566] 定存
        fillDeposits(&bk, a: a, x: x)
        // ⑦ 存摺明細
        fillLedger(&bk, a: a, x: x)
        // ⑧ 帳戶資料、⑨ 備註與照片
        bk.info = bankInfo(a, x: x)
        bk.note = m.note.trimmingCharacters(in: .whitespacesAndNewlines)
        bk.photos = m.photoFileNames ?? []
        if !a.hidden, Swift.abs(a.ntdTotal) > 0.5 {
            bk.leftover = "還有 " + (a.singleCode.map { WealthCardText.plain(a.balance($0), code: $0, masked: x.masked) }
                                     ?? "約 " + WealthCardText.wan(a.ntdTotal, masked: x.masked))
        }
        d.bank = bk
        return d
    }

    // MARK: ⑤ 外幣

    /// [v25.566] 一個幣別一格：「美金　US$3,200.00　約 NT$102,400（10/19 匯率 32.0）」；台幣沒有數字不放台幣那格
    fileprivate static func fillForeign(_ bk: inout WealthCardBank, a: WealthFacts.Account, codes: [String],
                                        x: WealthCardCtx) {
        let mk = x.masked
        guard codes.contains(where: { !FinanceRates.isNTD($0) }) else { return }
        let shown = codes.filter { code in
            !FinanceRates.isNTD(code) || Swift.abs(a.balance(code)) > 0.004
        }
        bk.foreign = shown.map { code -> WealthCardFTile in
            let v = a.balance(code)
            var sub = ""
            var subTone: MoneyTone? = nil
            if !FinanceRates.isNTD(code) {
                if let r = x.rates.known(code) {
                    sub = mk ? "約 " + WealthCardText.dots : WealthFormat.fxNote(v, rate: r, rateDate: x.rateDate)
                } else {
                    sub = "沒有匯率"
                    subTone = .warn
                }
            }
            return WealthCardFTile(id: code, label: WealthCardText.codeName(code),
                                   value: WealthCardText.money(v, code: code, masked: mk),
                                   valueTone: v < -0.004 ? .bad : nil, sub: sub, subTone: subTone)
        }
        // 收起來（銷戶）的帳戶不給換匯（同 ⑥〔＋ 定存〕；表單的帳戶選單也不列收起來的）
        bk.canExchange = !a.hidden
        bk.foreignNote = a.hidden ? nil : "換匯會在兩邊各記一筆、綁在一起；匯率可以改。"
    }

    // MARK: ⑥ 定存

    /// [v25.566] 每一期一格；標題右邊「1 筆・合計 NT$50萬」；舊的定存種類沒補任何一期＝〔補上利率和到期日〕
    fileprivate static func fillDeposits(_ bk: inout WealthCardBank, a: WealthFacts.Account, x: WealthCardCtx) {
        let terms = a.timeDeposits
        bk.deposits = terms.map { depositCell($0, x: x) }
        if !terms.isEmpty {
            let count = "\(terms.count) 筆"
            // 舊的定存種類：錢就在存摺上（depositNTD 是 0）
            let total: Double = a.isFixedDeposit ? a.ntdTotal : a.depositNTD
            let approx = !a.depositUnknownCodes.isEmpty || (a.isFixedDeposit && a.hasUnknownRate)
            if x.masked || total < 0.5 {
                bk.depositsTrailing = count
            } else {
                bk.depositsTrailing = count + "・合計 " + (approx ? "約 " : "") + total.ntdWanString
            }
        }
        bk.canAddDeposit = !a.hidden
        // 同要確認「補資料」那一條（WealthFacts depositInfoMissing）：沒收起來、存摺上有錢、帳本裡從來沒有這個帳戶的定存
        //（補過、後來到期轉活存或解約的不再催）
        let hasMoney = a.balances.values.contains(where: { $0 > 0.5 })
        bk.legacyDepositPrompt = a.isFixedDeposit && terms.isEmpty && !a.hidden && hasMoney
            && !x.depositBankIds.contains(a.id)
    }

    /// ⑥ 一格：「一年定存　NT$500,000・1.7%」／「2026/3/15 ━━●── 2027/3/15（還有 147 天）」／「到期本息續存・預估利息 8,500」
    fileprivate static func depositCell(_ t: WealthFacts.TimeDeposit, x: WealthCardCtx) -> WealthCardDepositCell {
        let mk = x.masked
        let today = x.today
        var p = FinanceProgressData()
        p.title = t.label
        var range = WealthCardText.money(t.principal, code: t.code, masked: mk)
        if let r = t.rateText { range += "・" + r }
        if t.isLegacyAccount { range += "・存摺上的錢" }
        p.range = range
        p.fraction = t.progress(today) ?? 0
        p.dotPill = "今天"
        p.endPill = t.maturityText(today).map { $0 + " 到期" } ?? "沒填到期日"
        if let ends = t.progressEnds(today: today) {
            p.left = ends.left
            p.right = ends.right
        } else {
            p.left = WealthFormat.ymd(t.start)
            p.right = "沒填到期日"
        }
        var waiting = false
        switch t.status {
        case .notStarted:
            p.fraction = 0
            p.notStarted = true
            p.dotPill = "還沒開始"
            p.left = WealthFormat.monthDay(t.start) + " 起存"
            p.note = depositNote(t, masked: mk)
        case .waiting:
            waiting = true
            p.note = "到期了，還沒決定怎麼處理（要確認裡選）"
        case .active, .ended:
            p.note = depositNote(t, masked: mk)
        }
        let line = t.maturityLine(today: today, masked: mk).replacingOccurrences(of: "・", with: "，")
        let said = mk ? "金額已遮住" : (FinanceRates.isNTD(t.code) ? WealthPageText.spoken(t.principal)
                                                                  : WealthFormat.money(t.principal, code: t.code))
        // FinanceProgressCell 念「標題（一年定存）＋accessibilityText」：這裡不再寫一次標題
        var spoken = "本金 " + said
        if let r = t.rateText { spoken += "，年利率 " + r }
        spoken += "。" + line
        // 到期處理那一句（maturityLine 已經念過預估利息，這裡不再念；沒開始的 maturityLine 只有「起存」，利息在這裡念）
        let modeText = waiting ? p.note : depositNote(t, masked: mk, withInterest: t.status == .notStarted)
        if !modeText.isEmpty { spoken += "。" + modeText.replacingOccurrences(of: "・", with: "，") }
        p.accessibilityText = spoken
        return WealthCardDepositCell(id: t.id, progress: p, accessibilityText: t.label + "，" + spoken, waiting: waiting)
    }

    /// ⑥ 一格最下一句：到期處理＋預估利息「到期本息續存・預估利息 8,500」「到期本金續存、利息轉進薪轉」「到期轉進薪轉」「到期再決定」
    fileprivate static func depositNote(_ t: WealthFacts.TimeDeposit, masked: Bool, withInterest: Bool = true) -> String {
        let selfPayout = t.payoutId == nil || t.payoutId == t.accountId
        let to = t.payoutName ?? t.accountName
        var s: String
        switch t.mode {
        case .renewAll: s = "到期本息續存"
        case .renewPrincipal: s = "到期本金續存、利息" + (selfPayout ? "轉活存" : "轉進" + to)
        case .toLive: s = selfPayout ? "到期轉活存" : "到期轉進" + to
        case .decide: s = "到期再決定"
        }
        if withInterest, let i = t.interestText(masked: masked) { s += "・" + i }
        return s
    }

    /// [v25.566] 看起來是定存帳戶時看板大字、四格「本金」、換帳戶列的數字：一筆＝那一筆的本金（原幣）；
    /// 好幾筆＝定存換台幣（約）。舊的定存種類帳戶、沒有任何一期＝nil（照原本寫存摺上：它的錢就在存摺上）
    fileprivate static func depositHeadline(_ a: WealthFacts.Account) -> (amount: Double, code: String, many: Bool)? {
        guard !a.isFixedDeposit, let first = a.timeDeposits.first else { return nil }
        if a.timeDeposits.count == 1 { return (amount: first.principal, code: first.code, many: false) }
        return (amount: a.depositNTD, code: "NT$", many: true)
    }

    /// [v25.566] 看板、四格「到期」那一期：最近要到期、還存著的 → 到期待決定的 → 第一期（沒開始、沒填到期日）
    fileprivate static func headlineTerm(_ a: WealthFacts.Account) -> WealthFacts.TimeDeposit? {
        if let n = a.nextMaturing { return n }
        if let w = a.timeDeposits.first(where: { $0.status == .waiting }) { return w }
        return a.timeDeposits.first
    }

    // MARK: 看板

    fileprivate static func bankBoard(_ x: WealthCardCtx, _ a: WealthFacts.Account) -> WealthCardBoard {
        // [v25.566] 看起來是定存帳戶（收起來的照舊）
        if !a.hidden && a.showsAsDeposit { return depositBoard(x, a) }
        var b = WealthCardBoard()
        let t = x.today
        let mk = x.masked
        let multi = a.singleCode == nil
        let code = WealthFacts.norm(a.singleCode ?? "NT$")
        let balance = a.balance(code)
        let stale: Bool = a.lastAnchorDate.map { WealthCal.days(from: $0, to: t) > 90 } ?? false
        b.date = WealthPageText.boardDate(t)
            + (a.lastAnchorDate.map { "・對過存摺 " + WealthCardText.md($0) } ?? "・還沒對過存摺")
        b.dateIcon = "checkmark.seal"
        let payday = a.ledger.first { WealthCal.day($0.date) == t && $0.kind == .recurringIncome }
        let nextOut = a.next30.first { $0.isOutflow && WealthCal.days(from: t, to: $0.date) <= 14 }
        let negative = multi ? a.ntdTotal < -0.5 : balance < -0.004

        // 膠囊
        if a.hidden {
            b.capsule = "已收起來"
            b.capsuleIcon = "archivebox.fill"
        } else if let s = a.shortage {
            b.capsule = WealthCardText.md(s.date) + " 會差 " + WealthCardText.plain(s.short, code: s.code, masked: mk)
            b.capsuleIcon = "exclamationmark.triangle.fill"
            b.capsuleTone = .warn
        } else if let p = payday {
            b.capsule = p.title + " " + WealthCardText.signed(p.amount, out: false, code: p.code, masked: mk)
            b.capsuleIcon = "banknote.fill"
            b.capsuleTone = .good
        } else if let r = nextOut {
            let n = WealthCal.days(from: t, to: r.date)
            b.capsule = WealthCardText.md(r.date) + " " + WealthPageText.shortName(r, facts: x.facts) + "・\(n) 天"
            b.capsuleIcon = upcomingIcon(r.kind)
        } else if multi {
            b.capsule = "\(a.currencies.count) 種幣別"
            b.capsuleIcon = "globe"
        } else if !FinanceRates.isNTD(code) {
            b.capsule = code
            b.capsuleIcon = "globe"
        }

        // 小字、大字
        b.label = multi ? "約當台幣" : (stale ? "存摺上（App 算的）" : "存摺上")
        b.big = multi ? WealthCardText.ntdWan(a.ntdTotal, masked: mk) : WealthCardText.money(balance, code: code, masked: mk)
        if negative { b.bigTone = .bad }

        // 一句、手寫
        if a.hidden {
            b.line = FinanceLine.text("不算進合計・不出現在記帳的選單")
        } else if negative {
            b.line = FinanceLine(runs: [FinanceRun(text: "可能漏記了收入或轉帳", tone: .bad)])
        } else if let s = a.shortage {
            b.line = FinanceLine(runs: [
                FinanceRun(text: WealthCardText.md(s.date) + " " + WealthPageText.shortName(s) + " "
                           + WealthCardText.plain(s.amount, code: s.code, masked: mk) + "，那天只剩 "),
                FinanceRun(text: WealthCardText.plain(s.before, code: s.code, masked: mk), bold: true, tone: .warn),
            ])
            b.greeting = ["Top it", "up!"]
        } else if stale {
            b.line = FinanceLine.text("跟存摺對一下，數字會更準")
        } else if let p = payday {
            var text = "今天" + p.title + "入帳"
            if let r = nextOut {
                text += "・" + WealthCardText.md(r.date) + " 要扣 " + WealthPageText.shortName(r, facts: x.facts) + " "
                    + (r.isEstimate ? "約 " : "") + WealthCardText.plain(r.amount, code: r.code, masked: mk)
            }
            b.line = FinanceLine.text(text)
            b.greeting = ["Pay", "day!"]
        } else if multi {
            let parts = WealthPageText.codes(a).map { raw -> String in
                let c = WealthFacts.norm(raw)
                let v = a.balance(c)
                let amount = FinanceRates.isNTD(c) ? WealthCardText.wan(v, masked: mk) : WealthCardText.plain(v, code: c, masked: mk)
                return WealthCardText.codeName(c) + " " + amount
            }
            b.line = FinanceLine.text(parts.joined(separator: "・"))
            b.greeting = ["Save", "steady!"]
        } else if !FinanceRates.isNTD(code) {
            if let r = x.rates.known(code) {
                // [v25.566] 「約 NT$102,400（10/19 匯率 32.0）」（judge §11 ③-B4；遮住只遮金額）
                let note = mk ? "約 " + WealthFormat.masked + "（" + WealthFormat.rateNote(r, rateDate: x.rateDate) + "）"
                              : WealthFormat.fxNote(balance, rate: r, rateDate: x.rateDate)
                b.line = FinanceLine.text(note)
            } else {
                b.line = FinanceLine(runs: [FinanceRun(text: "設定裡找不到這個幣別的匯率", tone: .warn)])
            }
            b.greeting = ["Hello,", "dollars!"]
        } else if a.notYetDebited > 0.5 {
            var parts: [String] = []
            if a.cardOwed > 0.5 { parts.append("卡費 " + WealthCardText.plain(a.cardOwed, masked: mk)) }
            if a.pendingSettlement > 0.5 { parts.append("交割 " + WealthCardText.plain(a.pendingSettlement, masked: mk)) }
            if a.scheduledOut > 0.5 { parts.append("其他 " + WealthCardText.plain(a.scheduledOut, masked: mk)) }
            b.line = FinanceLine(runs: [
                FinanceRun(text: parts.joined(separator: "、") + " 還沒扣・扣完能用 "),
                FinanceRun(text: WealthCardText.plain(a.usable, masked: mk), bold: true, tone: a.usable < 0 ? .bad : nil),
            ])
            b.greeting = ["Save", "steady!"]
        } else {
            b.line = FinanceLine.text("沒有還沒扣的卡費、交割")
            b.greeting = ["Save", "steady!"]
        }

        // VoiceOver
        let nick: String = a.nickname ?? ""
        var a11y = a.bankName + nick + "，" + b.label + " "
        if mk {
            a11y += "金額已遮住"
        } else if multi {
            a11y += "約 " + WealthPageText.spoken(a.ntdTotal)
        } else if FinanceRates.isNTD(code) {
            a11y += WealthPageText.spoken(balance)
        } else {
            a11y += WealthFormat.money(balance, code: code)
        }
        let plainLine = b.line.plain
        if !plainLine.isEmpty { a11y += "。" + plainLine.replacingOccurrences(of: "・", with: "，") }
        if let last = a.lastAnchorDate { a11y += "。上次對存摺 " + WealthPageText.spokenDate(last) + "。" }
        b.accessibilityText = a11y
        return b
    }

    /// [v25.566] 定存帳戶的看板（judge §4.2 ⑥、build/v5/brief.md §6 G2-4）：「定存」「NT$500,000」
    /// 「3/15 到期・還有 147 天・預估利息 8,500」、膠囊「3/15 到期・147 天」、手寫 Grow / slowly!。
    /// 舊的「定存」種類帳戶小字「存摺上」、大字照原本（存摺上就是定存的錢）
    fileprivate static func depositBoard(_ x: WealthCardCtx, _ a: WealthFacts.Account) -> WealthCardBoard {
        var b = WealthCardBoard()
        let t = x.today
        let mk = x.masked
        let multi = a.singleCode == nil
        let code = WealthFacts.norm(a.singleCode ?? "NT$")
        let balance = a.balance(code)
        let head = depositHeadline(a)
        let term = headlineTerm(a)
        b.date = WealthPageText.boardDate(t)
            + (a.lastAnchorDate.map { "・對過存摺 " + WealthCardText.md($0) } ?? "・還沒對過存摺")
        b.dateIcon = "checkmark.seal"

        // 膠囊：不夠扣 → 到期待決定 → 「3/15 到期・147 天」（7 天內 warn）→ 「10/25 起存」
        if let s = a.shortage {
            b.capsule = WealthCardText.md(s.date) + " 會差 " + WealthCardText.plain(s.short, code: s.code, masked: mk)
            b.capsuleIcon = "exclamationmark.triangle.fill"
            b.capsuleTone = .warn
        } else if a.timeDeposits.contains(where: { $0.status == .waiting }) {
            b.capsule = "到期了・等你決定"
            b.capsuleIcon = "lock.open.fill"
            b.capsuleTone = .warn
        } else if let n = a.nextMaturing, let mt = n.maturityText(t), let left = n.daysLeft(t) {
            b.capsule = mt + " 到期・\(left) 天"
            b.capsuleIcon = "lock.fill"
            if left <= 7 { b.capsuleTone = .warn }
        } else if let first = a.timeDeposits.first, first.status == .notStarted {
            b.capsule = WealthCardText.md(first.start) + " 起存"
            b.capsuleIcon = "calendar"
        }

        // 小字、大字
        if let h = head {
            b.label = "定存"
            b.big = h.many ? WealthCardText.ntdWan(h.amount, masked: mk) : WealthCardText.money(h.amount, code: h.code, masked: mk)
        } else {
            b.label = "存摺上"
            b.big = multi ? WealthCardText.ntdWan(a.ntdTotal, masked: mk) : WealthCardText.money(balance, code: code, masked: mk)
            let negative = multi ? a.ntdTotal < -0.5 : balance < -0.004
            if negative { b.bigTone = .bad }
        }

        // 一句、手寫
        if let term {
            b.line = FinanceLine.text(term.maturityLine(today: t, masked: mk))
        } else {
            b.line = FinanceLine.text("補上利率和到期日，就能算利息")
        }
        b.greeting = ["Grow", "slowly!"]

        // VoiceOver
        let nick: String = a.nickname ?? ""
        var a11y = a.bankName + nick + "，" + b.label + " "
        if mk {
            a11y += "金額已遮住"
        } else if let h = head {
            if h.many {
                a11y += "約 " + WealthPageText.spoken(h.amount)
            } else if FinanceRates.isNTD(h.code) {
                a11y += WealthPageText.spoken(h.amount)
            } else {
                a11y += WealthFormat.money(h.amount, code: h.code)
            }
        } else if multi {
            a11y += "約 " + WealthPageText.spoken(a.ntdTotal)
        } else if FinanceRates.isNTD(code) {
            a11y += WealthPageText.spoken(balance)
        } else {
            a11y += WealthFormat.money(balance, code: code)
        }
        if let cap = b.capsule { a11y += "，" + cap.replacingOccurrences(of: "・", with: "，") }
        let plainLine = b.line.plain
        if !plainLine.isEmpty { a11y += "。" + plainLine.replacingOccurrences(of: "・", with: "，") }
        if let last = a.lastAnchorDate { a11y += "。上次對存摺 " + WealthPageText.spokenDate(last) + "。" }
        b.accessibilityText = a11y
        return b
    }

    fileprivate static func upcomingIcon(_ k: WealthLedgerRow.Kind) -> String {
        switch k {
        case .stockBuy, .stockSell, .dividend: return "arrow.left.arrow.right"
        case .cardBill: return "creditcard"
        // [v25.566] 轉定存、定存到期
        case .timeDeposit: return "lock.fill"
        default: return "calendar"
        }
    }

    // MARK: 風景：水位

    fileprivate static func tideScene(_ a: WealthFacts.Account, x: WealthCardCtx) -> WealthTideScene {
        let today = x.today
        let days = 61
        let todayIndex = 30
        let start = WealthCal.addDays(-todayIndex, to: today)
        let end = WealthCal.addDays(days - 1 - todayIndex, to: today)
        let multi = a.singleCode == nil
        let codes: [String] = multi ? WealthPageText.codes(a).map { WealthFacts.norm($0) }
                                    : [WealthFacts.norm(a.singleCode ?? "NT$")]
        let past: [WealthLedgerRow] = Array(a.ledger.reversed())
        var totals = [Double](repeating: 0, count: days)
        var negativeDays = Set<Int>()
        for code in codes {
            // 多幣別換台幣加總：查不到匯率的那個幣別不算（不當 1:1，D14）
            let rate: Double = multi ? (x.rates.known(code) ?? 0) : 1
            let pastRows = past.filter { WealthFacts.norm($0.code) == code }
            let futureRows = a.upcoming.filter { WealthFacts.norm($0.code) == code }
            // 窗口裡第一次對存摺以前的那幾天：從那次對存摺往回推（App 算的＋那次的差）。不然第一次對存摺以前 App 算的數字
            // （常常只記了收入）會讓那天掉一大階、其他天全擠在最下面（judge §11.3 ②-3：9/19 是 114,199，不是 1,635,445）。
            // 只動風景；明細每列的餘額照 WealthFacts（對存摺那列寫「差 …」）。還沒有任何紀錄的日子照舊是 0（新開的帳戶）
            let firstAnchor: Int? = pastRows.firstIndex { r in
                r.kind == .anchor && WealthCal.day(r.date) >= start
            }
            let shift: Double = firstAnchor.flatMap { k in pastRows[k].anchorDiff } ?? 0
            var cur: Double = 0
            var pi = 0
            var fi = 0
            for i in 0..<days {
                let day = WealthCal.addDays(i - todayIndex, to: today)
                if i <= todayIndex {
                    while pi < pastRows.count, WealthCal.day(pastRows[pi].date) <= day {
                        cur = pastRows[pi].balanceAfter
                        if let k = firstAnchor, pi < k { cur += shift }
                        pi += 1
                    }
                    if i == todayIndex { cur = a.balance(code) }
                } else {
                    while fi < futureRows.count, WealthCal.day(futureRows[fi].date) <= day {
                        cur = futureRows[fi].balanceAfter
                        fi += 1
                    }
                    if cur < -0.004 { negativeDays.insert(i) }
                }
                totals[i] += cur * rate
            }
        }
        let lo = totals.min() ?? 0
        let hi = totals.max() ?? 0
        let span = hi - lo
        let level: [Double] = totals.map { v -> Double in
            span < 0.5 ? 0.5 : 0.08 + 0.84 * (v - lo) / span
        }
        var zero: Double? = nil
        if lo < -0.5 {
            zero = span < 0.5 ? 0.5 : Swift.min(0.92, Swift.max(0.08, 0.08 + 0.84 * (0 - lo) / span))
        }
        // 小牌：一天一塊（同一天取第一筆）、對存摺不畫
        var events: [WealthTideScene.Event] = []
        var used = Set<Int>()
        let inWindow = past.filter { WealthCal.day($0.date) >= start }
            + a.upcoming.filter { WealthCal.day($0.date) <= end }
        for r in inWindow where r.kind != .anchor {
            let i = WealthCal.days(from: start, to: r.date)
            guard i >= 0, i < days, !used.contains(i) else { continue }
            let label = tideLabel(r, facts: x.facts)
            guard !label.isEmpty else { continue }
            used.insert(i)
            events.append(WealthTideScene.Event(day: i, label: label, up: !r.isOutflow))
        }
        var anchorDay: Int? = nil
        if let last = a.lastAnchorDate {
            let i = WealthCal.days(from: start, to: last)
            if i >= 0 && i < days { anchorDay = i }
        }
        let foreign = a.isForeignType || (!multi && !FinanceRates.isNTD(codes.first ?? "NT$"))
        return WealthTideScene(days: days, todayIndex: todayIndex, level: level, events: events, anchorDay: anchorDay,
                               shortage: negativeDays.sorted(), zeroLevel: zero, foreign: foreign)
    }

    /// 水位小牌（≤ 4 個字）
    fileprivate static func tideLabel(_ r: WealthLedgerRow, facts: WealthFacts) -> String {
        switch r.kind {
        case .cardBill:
            let name = facts.card(r.cardId).map { WealthPageText.cardShort($0.name) }
                ?? WealthPageText.cardShort(fromBillTitle: r.title)
            return String(name.prefix(4))
        case .income, .recurringIncome:
            return r.title.contains("薪") ? "薪" : String(r.title.prefix(2))
        case .stockBuy, .stockSell: return "交割"
        case .dividend: return "股利"
        case .transferOut: return "轉出"
        case .transferIn: return "轉入"
        case .expense, .fixedExpense: return String(r.title.suffix(2))
        case .deposit: return "存"
        case .withdrawal: return "提"
        case .interest: return "息"
        case .fee: return "費"
        case .legacyAdjust: return "調"
        case .anchor: return ""
        // [v25.566] 轉定存、定存到期、定存解約
        case .timeDeposit: return "定存"
        }
    }

    // MARK: 四格

    fileprivate static func bankTiles(_ x: WealthCardCtx, _ a: WealthFacts.Account) -> [WealthCardTile] {
        // [v25.566] 定存帳戶（同看板：收起來的照舊）：本金／預估利息／到期／上次對存摺
        if !a.hidden && a.showsAsDeposit { return depositTiles(x, a) }
        let mk = x.masked
        let t = x.today
        let multi = a.singleCode == nil
        let code = multi ? "NT$" : WealthFacts.norm(a.singleCode ?? "NT$")
        let monthStart = WealthCal.startOfMonth(t)
        // 一個幣別：只加那個幣別（原幣）；好幾個幣別：換台幣，查不到匯率的不算（不當 1:1，D14）
        let rows = a.ledger.filter {
            WealthCal.day($0.date) >= monthStart && $0.kind != .anchor && (multi || WealthFacts.norm($0.code) == code)
        }
        func value(_ r: WealthLedgerRow) -> Double {
            multi ? r.amount * (x.rates.known(WealthFacts.norm(r.code)) ?? 0) : r.amount
        }
        let ins = rows.filter { !$0.isOutflow }
        let outs = rows.filter { $0.isOutflow }
        let inSum = ins.reduce(0.0) { $0 + value($1) }
        let outSum = outs.reduce(0.0) { $0 + value($1) }
        var tiles: [WealthCardTile] = []
        let inDetail: String = ins.max(by: { value($0) < value($1) }).map { r in
            WealthCardText.md(r.date) + " " + String(r.title.prefix(6))
        } ?? "這個月還沒有"
        tiles.append(WealthCardTile(id: "in", icon: "arrow.down.circle.fill", tint: .green, label: "這個月進來",
                                    value: WealthCardText.signed(inSum, out: false, code: code, masked: mk),
                                    valueTone: inSum > 0.5 ? .good : nil, detail: inDetail, tap: .scroll(.ledger)))
        tiles.append(WealthCardTile(id: "out", icon: "arrow.up.circle.fill", tint: .orange, label: "這個月出去",
                                    value: WealthCardText.signed(outSum, out: true, code: code, masked: mk),
                                    detail: "\(outs.count) 筆", tap: .scroll(.ledger)))
        if let s = a.shortage {
            tiles.append(WealthCardTile(id: "low", icon: "drop.fill", tint: .azure, label: "30 天內最低",
                                        value: "差 " + WealthCardText.plain(s.short, code: s.code, masked: mk),
                                        valueTone: .warn,
                                        detail: WealthCardText.md(s.date) + " " + WealthPageText.shortName(s) + "前",
                                        tap: .scroll(.upcoming)))
        } else if let low = a.lowestNTD {
            var detail = "30 天內"
            if let ld = a.lowestDate {
                if let r = a.next30.last(where: { WealthCal.day($0.date) == WealthCal.day(ld) }) {
                    detail = WealthCardText.md(ld) + " " + WealthPageText.shortName(r, facts: x.facts) + "後"
                } else {
                    detail = WealthCardText.md(ld)
                }
            }
            tiles.append(WealthCardTile(id: "low", icon: "drop.fill", tint: .azure, label: "30 天內最低",
                                        value: mk ? WealthCardText.dots : "約 " + WealthPageText.wan(low),
                                        valueTone: low < 0 ? .bad : nil, detail: detail, tap: .scroll(.upcoming)))
        } else {
            tiles.append(WealthCardTile(id: "low", icon: "drop.fill", tint: .azure, label: "30 天內最低",
                                        value: "—", detail: "30 天內沒有要扣的"))
        }
        tiles.append(anchorTile(a, today: t))
        return tiles
    }

    /// 「上次對存摺」那格（一般帳戶、定存帳戶共用）
    fileprivate static func anchorTile(_ a: WealthFacts.Account, today t: Date) -> WealthCardTile {
        let anchorCode = a.singleCode.map { WealthFacts.norm($0) } ?? "NT$"
        if let last = a.lastAnchorDate {
            let n = WealthCal.days(from: last, to: t)
            return WealthCardTile(id: "anchor", icon: "checkmark.seal.fill", tint: .violet, label: "上次對存摺",
                                  value: WealthCardText.md(last), valueTone: n > 90 ? .warn : nil,
                                  detail: n == 0 ? "今天" : "\(n) 天前", tap: .anchor(anchorCode))
        }
        return WealthCardTile(id: "anchor", icon: "checkmark.seal.fill", tint: .violet, label: "上次對存摺",
                              value: "還沒對過", detail: "對一下 ›", tap: .anchor(anchorCode))
    }

    /// [v25.566] 定存帳戶的四格：本金（一筆原幣／好幾筆換台幣）、預估利息、到期、上次對存摺；前三格點了捲到 ⑥ 定存
    fileprivate static func depositTiles(_ x: WealthCardCtx, _ a: WealthFacts.Account) -> [WealthCardTile] {
        let mk = x.masked
        let t = x.today
        let terms = a.timeDeposits
        var tiles: [WealthCardTile] = []

        // 本金
        let principalValue: String
        let principalDetail: String
        if let h = depositHeadline(a) {
            principalValue = h.many ? WealthCardText.ntdWan(h.amount, masked: mk) : WealthCardText.money(h.amount, code: h.code, masked: mk)
            principalDetail = h.many ? "\(terms.count) 筆・換成台幣" : (terms.first?.label ?? "定存")
        } else if let first = terms.first {
            // 舊的定存種類：補了的那一期（存摺上的錢）
            principalValue = WealthCardText.money(first.principal, code: first.code, masked: mk)
            principalDetail = terms.count > 1 ? "\(terms.count) 筆" : first.label
        } else {
            let code = WealthFacts.norm(a.singleCode ?? "NT$")
            principalValue = a.singleCode == nil ? WealthCardText.ntdWan(a.ntdTotal, masked: mk)
                                                 : WealthCardText.money(a.balance(code), code: code, masked: mk)
            principalDetail = "存摺上"
        }
        tiles.append(WealthCardTile(id: "principal", icon: "lock.fill", tint: .orange, label: "本金",
                                    value: principalValue, detail: principalDetail, tap: .scroll(.deposits)))

        // 預估利息（一筆原幣；好幾筆換台幣加總，查不到匯率的不算）
        let rated = terms.filter { ($0.rate ?? 0) > 0 }
        let interestValue: String
        let interestDetail: String
        if rated.isEmpty {
            interestValue = "—"
            interestDetail = terms.isEmpty ? "補上利率就能算" : "沒填利率"
        } else if rated.count == 1, let one = rated.first {
            interestValue = WealthCardText.plain(one.interest, code: one.code, masked: mk)
            interestDetail = "年利率 " + (one.rateText ?? "")
        } else {
            let sum = rated.reduce(0.0) { $0 + $1.interest * (x.rates.known($1.code) ?? 0) }
            interestValue = WealthCardText.plain(sum, masked: mk)
            interestDetail = "\(rated.count) 筆・單利未扣稅"
        }
        tiles.append(WealthCardTile(id: "interest", icon: "percent", tint: .green, label: "預估利息",
                                    value: interestValue, detail: interestDetail, tap: .scroll(.deposits)))

        // 到期
        var dueValue = "—"
        var dueDetail = terms.isEmpty ? "補上到期日 ›" : "沒填到期日"
        var dueTone: MoneyTone? = nil
        if let term = headlineTerm(a) {
            if let mt = term.maturityText(t) { dueValue = mt }
            switch term.status {
            case .waiting:
                dueDetail = "到期了・等你決定"
                dueTone = .warn
            case .notStarted:
                dueDetail = WealthCardText.md(term.start) + " 起存"
            case .active, .ended:
                if let left = term.daysLeft(t) {
                    dueDetail = left <= 0 ? "今天到期" : "還有 \(left) 天"
                    if left <= 7 { dueTone = .warn }
                }
            }
        }
        tiles.append(WealthCardTile(id: "maturity", icon: "hourglass", tint: .azure, label: "到期",
                                    value: dueValue, valueTone: dueTone, detail: dueDetail, tap: .scroll(.deposits)))

        tiles.append(anchorTile(a, today: t))
        return tiles
    }

    // MARK: ③ 接下來 30 天

    fileprivate static func upcomingRow(_ r: WealthLedgerRow, x: WealthCardCtx) -> WealthCardRow {
        let mk = x.masked
        var title = r.title
        var detail = ""
        var glyph = "扣"
        var mark: UInt32 = 0x6B7FA3
        switch r.kind {
        case .stockBuy, .stockSell:
            let broker = r.stockId.flatMap { sid in x.facts.brokers.first(where: { $0.holdingIds.contains(sid) }) }
            title = (broker.map { WealthCardText.brokerShort($0.name) } ?? "") + "交割"
            detail = r.title
            glyph = "交"
            mark = 0x6B44E0
        case .cardBill:
            if r.isEstimate, let c = x.facts.card(r.cardId) {
                detail = "約，" + WealthCardText.md(c.nextClose) + " 結帳後確定"
            }
            glyph = "卡"
            mark = 0xE0453A
        case .recurringIncome, .income, .dividend:
            glyph = r.title.contains("薪") ? "薪" : "收"
            mark = 0x1F9D57
        case .fixedExpense, .expense:
            detail = r.kind.badge
            glyph = String(r.title.prefix(1))
        case .transferIn, .transferOut:
            glyph = "轉"
            mark = 0x2F7FE8
        case .timeDeposit:
            // [v25.566] 轉定存、定存到期（還沒到的利息是估的：金額前面「約」照 isEstimate）
            glyph = "定"
            mark = 0xA86A00
            detail = "定存"
        default:
            detail = r.kind.badge
            // [v25.566] 定存利息（本金續存的利息轉進來、舊定存帳戶記進存摺的利息）
            // （標題已經是「定存利息」「台灣銀行 定存利息」：細字只寫「定存」，不重複）
            if r.timeDepositId != nil {
                glyph = "息"
                mark = 0xA86A00
                detail = "定存"
            }
        }
        let amount = mk ? WealthCardText.dots : WealthPageText.signed(r)
        var row = WealthCardRow(id: r.id, date: r.date, dayText: WealthCardText.dayNum(r.date),
                                monthText: WealthCardText.monthText(r.date) + "・" + WealthCardText.weekday(r.date),
                                glyph: glyph, mark: mark, title: title, detail: detail, amountText: amount)
        row.amountTone = r.isOutflow ? nil : .good
        row.sub = "扣完剩 " + WealthCardText.plain(r.balanceAfter, code: r.code, masked: mk)
        row.warn = r.balanceAfter < -0.004
        row.open = openFor(r)
        let said = mk ? "金額已遮住" : (r.isOutflow ? "扣 " : "進 ") + WealthFormat.money(r.amount, code: r.code)
        let after = mk ? "" : "，扣完剩 " + WealthFormat.money(r.balanceAfter, code: r.code)
        row.accessibilityText = WealthPageText.spokenDate(r.date) + "，" + title + "，" + said + after
        return row
    }

    /// 一列點了打開什麼（接下來、存摺明細共用）
    fileprivate static func openFor(_ r: WealthLedgerRow) -> WealthCardOpen {
        switch r.kind {
        case .cardBill:
            if let c = r.cardId { return .card(c, r.isEstimate ? .unbilled : .statement) }
            return .none
        case .stockBuy, .stockSell, .dividend:
            if let s = r.stockId { return .stock(s) }
            return .none
        case .transferIn, .transferOut:
            if let d = r.depositId { return .transfer(d) }
            return .none
        case .anchor:
            if let d = r.depositId { return .anchorEdit(d) }
            return .none
        case .deposit, .withdrawal, .interest, .fee:
            // [v25.566] 定存利息（WealthFacts 算的，不是 BankDeposit）：開那一期的定存表單
            if r.kind == .interest, let t = r.timeDepositId { return .timeDeposit(t) }
            guard let d = r.depositId else { return .none }
            return .record(d, recordKind(r.kind))
        case .expense, .fixedExpense:
            if let e = r.expenseId { return .expense(e) }
            if let i = r.incomeId { return .income(i) }
            return .none
        case .income, .recurringIncome:
            if let i = r.incomeId { return .income(i) }
            return .none
        case .legacyAdjust:
            return .none
        // [v25.566] 轉定存、定存到期、定存解約：開那一期的定存表單
        case .timeDeposit:
            if let t = r.timeDepositId { return .timeDeposit(t) }
            return .none
        }
    }

    /// 明細的種類 → 記一筆表單的種類
    fileprivate static func recordKind(_ k: WealthLedgerRow.Kind) -> WealthRecordKind {
        switch k {
        case .withdrawal: return .withdrawal
        case .interest: return .interest
        case .fee: return .fee
        default: return .deposit
        }
    }

    // MARK: ④ 連到這個帳戶的

    fileprivate static func fillLinks(_ bk: inout WealthCardBank, a: WealthFacts.Account, x: WealthCardCtx) {
        let mk = x.masked
        var out: [WealthCardLinkRow] = []
        for c in WealthPageText.orderCards(x.facts.cards.filter { $0.payerId == a.id && !$0.isDisabled }) {
            let next = c.dueStatement?.due ?? c.nextDue
            out.append(WealthCardLinkRow(id: "card-" + c.id.uuidString, icon: "creditcard.fill", tint: 0xE0453A,
                                         title: c.name + " 卡費", detail: c.payMode.title,
                                         trailing: WealthCardText.md(next), open: .card(c.id, .statement)))
        }
        let fixed = x.expenses.filter { e -> Bool in
            // 不先濾「現在連著卡」的：〔改到別張卡〕選了以後才生效（linkFrom）時，那天以前照樣從這個帳戶扣，照今天找
            guard e.expenseType == .fixed, e.recurrence != nil else { return false }
            if let end = e.endDate, WealthCal.day(end) < x.today { return false }
            return WealthFacts.recurringTarget(e, at: x.today, history: x.book.links(e.id)) == a.id
        }
        for e in fixed {
            let ntd = WealthSchedule.ntd(of: e, raw: e.amount, rates: x.rates)
            var row = WealthCardLinkRow(id: "fx-" + e.id.uuidString, icon: MoneyArtTheme.of(e).hero,
                                        tint: MoneyArtTheme.of(e).tint, title: e.title,
                                        detail: WealthCardText.schedule(e),
                                        trailing: WealthCardText.plain(ntd, masked: mk), open: .expense(e.id))
            row.moveExpenseId = e.id
            out.append(row)
        }
        for br in x.facts.brokers where br.settlementBankId == a.id {
            let when = br.nextSettlementDate.map { WealthCardText.md($0) } ?? ""
            out.append(WealthCardLinkRow(id: "broker-" + br.id.uuidString, icon: "chart.line.uptrend.xyaxis",
                                         tint: 0x6B44E0, title: br.name + "交割", detail: "股票買賣", trailing: when,
                                         open: .card(br.id, nil)))
        }
        var into: [WealthCardLinkRow] = []
        let key = WealthCal.dayKey(x.today)
        for inc in x.incomes where inc.period != .once {
            if let end = inc.endDate, WealthCal.day(end) < x.today { continue }
            let target = WealthCardCycle.payer(statementKey: key, linked: inc.linkedBankMilestoneId,
                                               history: x.book.links(inc.id))
            guard target == a.id else { continue }
            // 外幣月薪照原幣寫（入外幣子帳戶的那種）
            let incCode = WealthFacts.norm(inc.linkedBankCurrency ?? "NT$")
            var row = WealthCardLinkRow(id: "in-" + inc.id.uuidString, icon: "banknote.fill", tint: 0x1F9D57,
                                        title: inc.title, detail: WealthCardText.incomeSchedule(inc),
                                        trailing: WealthCardText.signed(inc.amount, out: false, code: incCode, masked: mk),
                                        trailingTone: .good, open: .income(inc.id))
            row.moveIncomeId = inc.id
            into.append(row)
        }
        bk.linkedOut = out
        bk.linkedIn = into
        let n = out.count + into.count
        bk.linkedTrailing = n > 0 ? "\(n) 項" : nil
    }

    // MARK: ⑦ 存摺明細

    fileprivate static func fillLedger(_ bk: inout WealthCardBank, a: WealthFacts.Account, x: WealthCardCtx) {
        let mk = x.masked
        let multi = a.singleCode == nil
        // 今年進來／出去／利息（對存摺不算；好幾個幣別換台幣）
        let yearStart = WealthCal.calendar.date(from: DateComponents(
            year: WealthCal.calendar.component(.year, from: x.today), month: 1, day: 1)) ?? x.today
        // 一個幣別：只加那個幣別、照原幣寫；好幾個幣別：換台幣，查不到匯率的不算（不當 1:1，D14）
        let one: String = WealthFacts.norm(a.singleCode ?? "NT$")
        let thisYear = a.ledger.filter {
            WealthCal.day($0.date) >= yearStart && $0.kind != .anchor && (multi || WealthFacts.norm($0.code) == one)
        }
        func val(_ r: WealthLedgerRow) -> Double {
            multi ? r.amount * (x.rates.known(WealthFacts.norm(r.code)) ?? 0) : r.amount
        }
        let inSum = thisYear.filter { !$0.isOutflow }.reduce(0.0) { $0 + val($1) }
        let outSum = thisYear.filter { $0.isOutflow }.reduce(0.0) { $0 + val($1) }
        let interest = thisYear.filter { $0.kind == .interest }.reduce(0.0) { $0 + val($1) }
        let foreignOne = !multi && !FinanceRates.isNTD(one)
        let inText = foreignOne ? WealthCardText.money(inSum, code: one, masked: mk) : WealthCardText.ntdWan(inSum, masked: mk)
        let outText = foreignOne ? WealthCardText.money(outSum, code: one, masked: mk) : WealthCardText.ntdWan(outSum, masked: mk)
        let intCode = multi ? "NT$" : one
        bk.yearTiles = [
            WealthCardFTile(id: "yin", label: "今年進來", value: inText, sub: multi ? "換成台幣" : ""),
            WealthCardFTile(id: "yout", label: "今年出去", value: outText, sub: multi ? "換成台幣" : ""),
            WealthCardFTile(id: "yint", label: "今年利息", value: WealthCardText.plain(interest, code: intCode, masked: mk)),
        ]
        bk.recordsTitle = "紀錄・\(a.ledger.count) 筆"
        var present = Set<WealthLedgerFilter>()
        bk.ledger = a.ledger.map { r -> WealthCardRow in
            let row = ledgerRow(r, x: x)
            present.insert(row.filter)
            return row
        }
        bk.filters = [WealthLedgerFilter.all] + WealthLedgerFilter.allCases.filter { $0 != .all && present.contains($0) }
    }

    fileprivate static func ledgerRow(_ r: WealthLedgerRow, x: WealthCardCtx) -> WealthCardRow {
        let mk = x.masked
        var filter: WealthLedgerFilter
        var glyph: String
        var mark: UInt32
        switch r.kind {
        case .anchor:
            filter = .anchor; glyph = "對"; mark = 0x7A5AF8
        case .cardBill:
            filter = .cardBill; glyph = "卡"; mark = 0xE0453A
        case .transferIn, .transferOut:
            filter = .transfer; glyph = "轉"; mark = 0x2F7FE8
        case .stockBuy, .stockSell, .dividend:
            filter = .stock; glyph = r.kind == .dividend ? "息" : "交"; mark = 0x6B44E0
        case .timeDeposit:
            // [v25.566] 轉定存、定存到期、定存解約（金色）
            filter = .deposit; glyph = "定"; mark = 0xA86A00
        default:
            filter = r.isOutflow ? .outflow : .inflow
            glyph = String(r.title.prefix(1))
            mark = r.isOutflow ? 0x6B7FA3 : 0x1F9D57
        }
        switch r.kind {
        case .deposit: glyph = "存"
        case .withdrawal: glyph = "提"
        case .interest: glyph = "息"
        case .fee: glyph = "費"
        case .recurringIncome: glyph = r.title.contains("薪") ? "薪" : "入"
        default: break
        }
        // [v25.566] 定存利息（WealthFacts 算的，帶 timeDepositId）也歸「定存」篩選、金色
        if r.kind == .interest && r.timeDepositId != nil {
            filter = .deposit
            mark = 0xA86A00
        }
        let title: String = r.kind == .anchor ? "對存摺" : r.title
        var detail: String
        let amount: String
        if r.kind == .anchor {
            detail = "存摺上 " + WealthCardText.plain(r.amount, code: r.code, masked: mk) + "（那天結束時）"
            let diff = r.anchorDiff ?? 0
            if Swift.abs(diff) < 0.005 {
                amount = "差 0"
            } else {
                amount = "差 " + WealthCardText.signed(diff, out: diff < 0, code: r.code, masked: mk)
            }
        } else {
            // [v25.566] 徽章跟來源同一個字（定存）只寫一次
            let src = source(r)
            detail = src == r.kind.badge ? src : r.kind.badge + "・" + src
            amount = WealthCardText.signed(r.amount, out: r.isOutflow, code: r.code, masked: mk)
        }
        if let n = r.note?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty, r.kind != .anchor {
            detail += "・" + n
        }
        var row = WealthCardRow(id: r.id, date: r.date, dayText: WealthCardText.dayNum(r.date),
                                monthText: WealthCardText.monthText(r.date), glyph: glyph, mark: mark, title: title,
                                detail: detail, amountText: amount)
        row.amountTone = (r.kind != .anchor && !r.isOutflow) ? .good : nil
        row.sub = "餘額 " + WealthCardText.plain(r.balanceAfter, code: r.code, masked: mk)
        row.open = openFor(r)
        // 明細的卡費一期一列：點了開那張卡、捲到每期帳單
        if r.kind == .cardBill, let cid = r.cardId { row.open = .card(cid, .history) }
        row.filter = filter
        row.monthKey = WealthCal.monthKey(r.date)
        row.code = WealthFacts.norm(r.code)
        row.signedValue = r.kind == .anchor ? 0 : (r.isOutflow ? -r.amount : r.amount)
        let said = mk ? "金額已遮住" : amount
        let bal = mk ? "" : "，" + r.balanceText
        row.accessibilityText = WealthPageText.spokenDate(r.date) + "，" + title + "，" + said + bal
        return row
    }

    /// 明細細字裡「從哪來」：財富頁、記帳、收入、股票、轉帳
    fileprivate static func source(_ r: WealthLedgerRow) -> String {
        switch r.kind {
        // [v25.566] 定存利息是 App 照那一期定存算的（不是財富頁記的那一筆）
        case .deposit, .withdrawal, .interest, .fee: return r.timeDepositId != nil ? "定存" : "財富頁"
        case .expense, .fixedExpense: return "記帳"
        case .income, .recurringIncome: return "收入"
        case .stockBuy, .stockSell, .dividend: return "股票"
        case .transferIn, .transferOut: return "轉帳"
        case .cardBill: return r.isEstimate ? "估的" : "信用卡"
        case .legacyAdjust: return "以前的沖正"
        case .anchor: return "對存摺"
        // [v25.566] 轉定存、定存到期、定存解約（App 照定存算的那幾列）
        case .timeDeposit: return "定存"
        }
    }

    // MARK: ⑧ 帳戶資料

    fileprivate static func bankInfo(_ a: WealthFacts.Account, x: WealthCardCtx) -> [WealthCardInfo] {
        let m = x.item
        let prefs = x.book.account(a.id)
        var rows: [WealthCardInfo] = []
        rows.append(WealthCardInfo(id: "bank", label: "銀行", value: a.bankName))
        rows.append(WealthCardInfo(id: "nick", label: "暱稱", value: a.nickname ?? "—"))
        if let br = m.branchName?.trimmingCharacters(in: .whitespaces), !br.isEmpty {
            rows.append(WealthCardInfo(id: "branch", label: "分行", value: br))
        }
        if let acc = accountRow(a, prefs: prefs, m: m) { rows.append(acc) }
        // [v25.566] 舊的「定存」種類：定存不再是帳戶種類（定存記在帳戶裡，⑥）
        let typeText = a.isFixedDeposit ? "定存（以前記的）" : (m.bankAccountType?.rawValue ?? "活存")
        rows.append(WealthCardInfo(id: "type", label: "種類", value: typeText))
        let codes = WealthPageText.codes(a).map { WealthCardText.codeName(WealthFacts.norm($0)) }
        rows.append(WealthCardInfo(id: "codes", label: "幣別", value: codes.joined(separator: "、")))
        if let p = a.purpose?.trimmingCharacters(in: .whitespaces), !p.isEmpty {
            rows.append(WealthCardInfo(id: "purpose", label: "用途", value: p))
        }
        rows.append(WealthCardInfo(id: "opened", label: "開戶日", value: WealthPageText.ymd(m.date)))
        rows.append(WealthCardInfo(id: "count", label: "算進存款合計", value: a.countsInCash ? "是" : "否"))
        if a.hidden {
            let when = a.closedDate.map { "（" + WealthCardText.md($0) + "）" } ?? ""
            rows.append(WealthCardInfo(id: "hidden", label: "狀態", value: "已收起來" + when))
        }
        // [v25.566] 存款保險：這家銀行（存摺上＋定存）合計超過 300 萬才有這一列（judge §4.2 ⑧；遮住不寫金額）
        if let g = x.facts.insurance(for: a.id) {
            rows.append(WealthCardInfo(id: "insurance", label: "存款保險",
                                       value: x.masked ? "這家合計超過 300 萬" : g.text, tone: .warn))
        }
        return rows
    }

    /// 帳號那一列：末 4 碼「••7890」；有密文或舊的明碼才有〔顯示〕
    fileprivate static func accountRow(_ a: WealthFacts.Account, prefs: WealthAccountPrefs,
                                       m: LifeMilestone) -> WealthCardInfo? {
        let raw = (m.accountNumber ?? "").trimmingCharacters(in: .whitespaces)
        // 第 7 題：新存的里程碑只留末 4 碼（完整的在帳本密文）；只有末 4 碼時〔顯示〕也只是同 4 個數字，不給按鈕
        let hasSecret = prefs.accountNumberCipher != nil || raw.count > 4
        let last4: String? = (a.last4 ?? "").isEmpty ? nil : a.last4
        guard hasSecret || last4 != nil else { return nil }
        return WealthCardInfo(id: "account", label: "帳號", value: "••" + (last4 ?? "••••"),
                              secret: hasSecret ? .account : nil)
    }

    // MARK: ⓪ 換帳戶列

    fileprivate static func bankSwitcher(_ x: WealthCardCtx, current a: WealthFacts.Account) -> [FinanceSwitcherItem] {
        let list = WealthPageText.orderBanks(x.facts.banks.filter { $0.hidden == a.hidden })
        guard list.count > 1 else { return [] }
        return list.map { k -> FinanceSwitcherItem in
            var trailing = ""
            if !x.masked {
                // [v25.566] 定存帳戶寫定存的數字（同看板大字）
                let head: (amount: Double, code: String, many: Bool)? = (!k.hidden && k.showsAsDeposit) ? depositHeadline(k) : nil
                if let h = head {
                    trailing = h.many ? "約 " + WealthPageText.wan(h.amount) : WealthFormat.plain(h.amount, code: h.code)
                } else if let c = k.singleCode {
                    trailing = WealthFormat.plain(k.balance(c), code: WealthFacts.norm(c))
                } else {
                    trailing = "約 " + WealthPageText.wan(k.ntdTotal)
                }
            }
            let tone: MoneyTone = (k.shortage != nil) ? .warn : .neutral
            return FinanceSwitcherItem(id: k.id, title: MoneyBoardText.short(k.name, max: 8), trailing: trailing, tone: tone)
        }
    }
}

// MARK: - 證券戶（§4.3 v3）

extension WealthCardData {
    fileprivate static func buildBroker(_ x: WealthCardCtx, _ a: WealthFacts.Account) -> WealthCardData {
        let m = x.item
        let mk = x.masked
        let t = x.today
        let br = x.facts.broker(a.id)
        var d = WealthCardData(id: a.id, kind: .broker, title: a.name, editKind: .broker)
        d.seed = MoneyItem.seed(a.id)
        d.band = 118
        let ids = br?.holdingIds ?? []
        let byId = Dictionary(x.stocks.map { ($0.id, $0) }, uniquingKeysWith: { p, _ in p })
        let holdings: [Stock] = ids.compactMap { byId[$0] }
        d.scene = .balloons(FinBalloonScene(balloons: StockBoardData.build(stocks: holdings).balloons))

        var b = WealthCardBoard()
        b.date = WealthPageText.boardDate(t) + (br?.settlementName.map { "・交割 " + $0 } ?? "")
        b.dateIcon = "chart.line.uptrend.xyaxis"
        if let nd = br?.nextSettlementDate {
            let n = WealthCal.days(from: t, to: nd)
            if n >= 0 && n <= 14 {
                b.capsule = WealthCardText.md(nd) + " 交割・" + (n == 0 ? "今天" : "\(n) 天")
                b.capsuleIcon = "arrow.left.arrow.right"
            }
        }
        b.label = "持股市值（股票頁）"
        let mv = br?.marketValue ?? 0
        b.big = WealthCardText.ntdWan(mv, masked: mk)
        if let k = br, !holdings.isEmpty {
            let tone = MoneyTone.change(k.unrealized, base: Swift.max(1, k.cost))
            let sign = k.unrealized >= 0 ? "+" : "-"
            var gain = sign + WealthPageText.wan(Swift.abs(k.unrealized))
            if let r = k.unrealizedRatio { gain += "（" + (r >= 0 ? "+" : "-") + WealthFormat.percent(Swift.abs(r)) + "）" }
            b.line = FinanceLine(runs: [
                FinanceRun(text: "\(holdings.count) 檔・未實現 "),
                FinanceRun(text: mk ? WealthCardText.dots : gain, bold: true, tone: mk ? nil : tone),
            ])
        } else {
            b.line = FinanceLine.text("還沒有持股：在理財 › 股票記買進時選這個證券戶")
        }
        b.greeting = ["Rise", "high!"]
        var a11y = a.name + "，持股市值 " + (mk ? "金額已遮住" : WealthPageText.spoken(mv))
        let plainLine = b.line.plain
        if !plainLine.isEmpty { a11y += "。" + plainLine }
        b.accessibilityText = a11y
        d.board = b

        var bk = WealthCardBroker()
        bk.holdings = holdings.map { s -> MoneyItem in
            var item = MoneyItem.stock(s, candles: nil, dayRate: nil)
            // 遮住：市值、已實現的金額不露（報酬 %、股數照常）
            if mk {
                item.amount = WealthFormat.masked
                item.chips = item.chips.filter { !$0.text.hasPrefix("已實現") }
            }
            return item
        }
        var info: [WealthCardInfo] = []
        info.append(WealthCardInfo(id: "broker", label: "券商", value: a.bankName))
        if let acc = accountRow(a, prefs: x.book.account(a.id), m: m) { info.append(acc) }
        info.append(WealthCardInfo(id: "type", label: "類型", value: m.securitiesAccountType?.rawValue ?? "一般"))
        info.append(WealthCardInfo(id: "opened", label: "開戶日", value: WealthPageText.ymd(m.date)))
        info.append(WealthCardInfo(id: "settle", label: "交割銀行", value: br?.settlementName ?? "還沒設",
                                   tone: br?.settlementName == nil ? .warn : nil,
                                   tap: .edit(.settlement), tapTitle: "改"))
        bk.info = info
        bk.note = m.note.trimmingCharacters(in: .whitespacesAndNewlines)
        bk.photos = m.photoFileNames ?? []
        d.broker = bk
        d.switcher = brokerSwitcher(x, current: a)
        return d
    }

    fileprivate static func brokerSwitcher(_ x: WealthCardCtx, current a: WealthFacts.Account) -> [FinanceSwitcherItem] {
        let list = x.facts.securities.filter { $0.hidden == a.hidden }
        guard list.count > 1 else { return [] }
        return list.map { k -> FinanceSwitcherItem in
            let mv = x.facts.broker(k.id)?.marketValue ?? 0
            let trailing = x.masked ? "" : WealthPageText.wan(mv)
            return FinanceSwitcherItem(id: k.id, title: MoneyBoardText.short(k.name, max: 8), trailing: trailing,
                                       tone: .neutral)
        }
    }
}

// MARK: - 保單（§4.4 v3）

extension WealthCardData {
    /// 保單的名字（同財富頁 ⑦：暱稱 → 「保險公司 醫療險」→ 標題）
    fileprivate static func policyTitle(_ m: LifeMilestone, book: WealthBook) -> String {
        let kind = book.policy(m.id).kind ?? WealthPolicyKind.from(legacy: m.insuranceType)
        if let n = book.account(m.id).trimmedNickname { return n }
        let company = (m.insuranceCompany ?? "").trimmingCharacters(in: .whitespaces)
        return company.isEmpty ? m.title : company + " " + kind.shortTitle
    }

    fileprivate static func buildPolicy(_ x: WealthCardCtx) -> WealthCardData {
        let m = x.item
        let mk = x.masked
        let t = x.today
        let prefs = x.book.policy(m.id)
        let kind = prefs.kind ?? WealthPolicyKind.from(legacy: m.insuranceType)
        var d = WealthCardData(id: m.id, kind: .policy, title: policyTitle(m, book: x.book), editKind: .policy)
        d.seed = MoneyItem.seed(m.id)
        d.band = 28
        d.scene = .towers(.empty)

        let premium = m.premiumAmount ?? 0
        let cycle = prefs.cycle
        let times = cycle?.timesPerYear ?? 1
        let yearly = (cycle == nil || times == 0) ? premium : premium * Double(times)
        let start = WealthCal.day(m.date)
        let elapsedYears = Swift.max(0, WealthCal.calendar.dateComponents([.year], from: start, to: t).year ?? 0)
        let payYears = prefs.payYears.flatMap { $0 > 0 ? $0 : nil }
        let yearIndex = elapsedYears + 1
        let payer: String? = prefs.payFromId.flatMap { id -> String? in
            if let c = x.facts.card(id) { return "刷 " + c.name }
            if let a = x.facts.account(id) { return "從" + a.name + "扣" }
            return nil
        }

        var b = WealthCardBoard()
        b.date = WealthPageText.boardDate(t) + (payYears.map { "・第 \(Swift.min(yearIndex, $0))／\($0) 年" } ?? "")
        b.dateIcon = "cross.case.fill"
        if let next = prefs.nextDue {
            b.capsule = "下次 " + WealthPageText.ymd(next)
            b.capsuleIcon = "calendar"
        }
        b.label = cycle == .single ? "躉繳保費" : (cycle == nil ? "保費" : "一年保費")
        b.big = premium > 0.5 ? WealthCardText.ntd(yearly, masked: mk) : "—"
        var parts: [String] = []
        if let py = payYears {
            let paid = Swift.min(yearIndex, py)
            parts.append(paid >= py ? "已繳 \(py) 年・繳完了" : "已繳 \(paid) 年・還剩 \(py - paid) 年")
        }
        if let p = payer { parts.append(p) }
        b.line = FinanceLine.text(parts.isEmpty ? kind.shortTitle : parts.joined(separator: "・"))
        b.greeting = ["Stay", "covered!"]
        var a11y = d.title + "，" + b.label + " " + (mk ? "金額已遮住" : (premium > 0.5 ? WealthPageText.spoken(yearly) : "沒填"))
        if !parts.isEmpty { a11y += "。" + parts.joined(separator: "，") }
        b.accessibilityText = a11y
        d.board = b

        // 看板下：繳費進度
        if let py = payYears {
            let endDate = WealthCal.calendar.date(byAdding: .year, value: py, to: start) ?? start
            let total = Double(Swift.max(1, WealthCal.days(from: start, to: endDate)))
            let gone = Double(Swift.max(0, WealthCal.days(from: start, to: t)))
            let paid = Swift.min(yearIndex, py)
            var p = FinanceProgressData()
            p.title = "繳費進度"
            p.range = WealthCardText.ym(start) + " → " + WealthCardText.ym(endDate)
            p.fraction = Swift.min(1, gone / total)
            p.dotPill = "今天"
            p.endPill = WealthCardText.ym(endDate) + " 繳完"
            p.left = "已繳 \(paid) 年"
            p.right = paid >= py ? "繳完了" : "還有 \(py - paid) 年"
            p.accessibilityText = "已繳 \(paid) 年，共 \(py) 年"
            d.progress = p
        }

        var pol = WealthCardPolicy()
        pol.coverage = (prefs.coverageItems ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if premium > 0.5 {
            var pay: [String] = []
            pay.append((cycle?.title ?? "保費") + " " + WealthCardText.plain(premium, masked: mk))
            if let next = prefs.nextDue {
                pay.append(cycle == .year ? "每年 " + WealthCardText.md(next) : "下次 " + WealthPageText.ymd(next))
            }
            if let p = payer { pay.append(p) }
            if let py = payYears, cycle == .year { pay.append("第 \(Swift.min(yearIndex, py))／\(py) 期") }
            pol.payment = pay.joined(separator: "・")
        }
        if kind.legacyType == .health || kind.legacyType == .accident {
            pol.medicalNote = "這張保單會出現在醫療地圖的「醫療保障」"
        }
        var info: [WealthCardInfo] = []
        let company = (m.insuranceCompany ?? "").trimmingCharacters(in: .whitespaces)
        info.append(WealthCardInfo(id: "company", label: "保險公司", value: company.isEmpty ? "—" : company))
        info.append(WealthCardInfo(id: "title", label: "保單名稱", value: m.title))
        info.append(WealthCardInfo(id: "kind", label: "險種", value: kind.title))
        if let no = m.policyNumber?.trimmingCharacters(in: .whitespaces), !no.isEmpty {
            info.append(WealthCardInfo(id: "policy", label: "保單號碼", value: CardVault.maskedTail(no), secret: .policy))
        }
        info.append(WealthCardInfo(id: "since", label: "生效日", value: WealthPageText.ymd(m.date)))
        if let until = prefs.coverageUntil?.trimmingCharacters(in: .whitespaces), !until.isEmpty {
            info.append(WealthCardInfo(id: "until", label: "保障到", value: until))
        }
        if let s = prefs.insured?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            info.append(WealthCardInfo(id: "insured", label: "被保險人", value: s))
        }
        if let s = prefs.policyholder?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            info.append(WealthCardInfo(id: "holder", label: "要保人", value: s))
        }
        if let s = m.beneficiary?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            info.append(WealthCardInfo(id: "beneficiary", label: "受益人", value: s))
        }
        pol.info = info
        pol.note = m.note.trimmingCharacters(in: .whitespacesAndNewlines)
        pol.photos = m.photoFileNames ?? []
        d.policy = pol
        d.switcher = policySwitcher(x)
        return d
    }

    fileprivate static func policySwitcher(_ x: WealthCardCtx) -> [FinanceSwitcherItem] {
        let list = x.milestones.filter { m in
            m.category == .achievement && m.financeSubCategory == .insurance && x.book.account(m.id).hidden != true
        }
        guard list.count > 1 else { return [] }
        return list.map { m -> FinanceSwitcherItem in
            FinanceSwitcherItem(id: m.id, title: MoneyBoardText.short(policyTitle(m, book: x.book), max: 8),
                                trailing: "", tone: .neutral)
        }
    }
}
