import SwiftUI

// MARK: - 財富的表單、小表單、要確認（v25.564，財富 v3；wealth/judge.md §5、§4.5、§3.5、§5.6）
//
// • WealthAccountEditor：新增／編輯銀行帳戶、信用卡、證券戶、保單（從履歷搬出來；類型開了就鎖住）。
//   存的地方還是 LifeMilestone（身分＋舊欄位，給舊 iPad、網頁版、醫療地圖）＋財富帳本（LifeStore.saveWealthAccount）。
//   安全碼（使用者第 6 題「我要存」）：「記錄檢核碼（CVV／CVC）」開關＋欄位照留（預設關），CardVault 加密、Face ID 才看得到。
//   刪除只在編輯頁最下面（FinanceDeleteAlert＋LifeStore.deleteFinanceMilestone；卡先建議〔改成停用〕、銀行先建議〔收起來就好〕）。
// • 小表單（.presentationDetents([.medium, .large])）：記一筆、轉帳、對存摺、標成已繳、帳單金額不一樣、一次改到別張卡／改到別的帳戶、
//   排序與收起來、匯率。
// • WealthChecksSection：財富頁 ②、卡片頁 ② 共用的「要確認」（FinanceCardHeader＋白卡裡 FinanceCheckRow；0 件整區不出現），
//   按鈕照 WealthCheck.Fix 開表單或叫 LifeStore。
// 每個表單自己掛 WealthPrivacyCurtain（有號碼的表單 armed）；儲存鈕忙碌守衛；刪除一律先問；先 dismiss、下一個 runloop 才寫 store。
//
// 分工：G3 實作（這個檔＋ResumeView、MyCalendarView、LifeOverviewView、AddExpenseView）。主控只放能編譯的入口，簽章不要改（G1、G2 在叫）。

/// 表單的類型（開了就鎖住）
enum WealthAccountKind: String, CaseIterable, Identifiable {
    case bank, card, broker, policy

    var id: String { rawValue }

    /// 里程碑的子分類 → 表單類型（沒有子分類＝nil：那是一件財富大事，用原本的里程碑表單）
    init?(sub: FinanceSubCategory?) {
        switch sub {
        case .bank?: self = .bank
        case .creditCard?: self = .card
        case .securities?: self = .broker
        case .insurance?: self = .policy
        case nil: return nil
        }
    }

    var sub: FinanceSubCategory {
        switch self {
        case .bank: return .bank
        case .card: return .creditCard
        case .broker: return .securities
        case .policy: return .insurance
        }
    }

    /// 「銀行帳戶」「信用卡」「證券戶」「保單」（＋選單、表單標題「新增銀行帳戶」）
    var title: String {
        switch self {
        case .bank: return "銀行帳戶"
        case .card: return "信用卡"
        case .broker: return "證券戶"
        case .policy: return "保單"
        }
    }

    var icon: String {
        switch self {
        case .bank: return "building.columns.fill"
        case .card: return "creditcard.fill"
        case .broker: return "chart.line.uptrend.xyaxis"
        case .policy: return "cross.case.fill"
        }
    }
}

/// 從要確認點進表單時先捲到哪一段
enum WealthEditorFocus: String {
    case cardDays, payFrom, settlement
}

/// 新增／編輯財富帳戶（入口；G3 換成真的，簽章不改）。onSaved：存好之後（履歷的里程碑表單要跟著關）
struct WealthAccountEditor: View {
    let kind: WealthAccountKind
    var editing: LifeMilestone? = nil
    var focus: WealthEditorFocus? = nil
    var onSaved: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text(kind.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                }
        }
    }
}

/// 記一筆的種類（存款／提款／利息／手續費；轉帳、對存摺另外兩張小表單）
enum WealthRecordKind: String, CaseIterable, Identifiable {
    case deposit, withdrawal, interest, fee

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deposit: return "存款"
        case .withdrawal: return "提款"
        case .interest: return "利息"
        case .fee: return "手續費"
        }
    }
}

/// 記一筆（存款、提款、利息、手續費）；editing：點明細裡財富頁自己記的那一筆
struct WealthRecordSheet: View {
    let accountId: UUID
    var kind: WealthRecordKind = .deposit
    var code: String? = nil
    var editing: BankDeposit? = nil

    var body: some View { Text("記一筆") }
}

/// 轉帳（含換匯）；要確認〔轉帳過去〕帶 to、from、amount
struct WealthTransferSheet: View {
    var fromId: UUID? = nil
    var toId: UUID? = nil
    var amount: Double? = nil

    var body: some View { Text("轉帳") }
}

/// 對存摺（取代沖正）；editing：點明細裡的對存摺那一列
struct WealthAnchorSheet: View {
    let accountId: UUID
    var code: String = "NT$"
    var editing: BankDeposit? = nil

    var body: some View { Text("對存摺") }
}

/// 標成已繳（哪一期 nil＝最早沒繳的那一期）；也是〔不是，改一下〕〔繳了〕打開的
struct WealthPaidSheet: View {
    let cardId: UUID
    var statementKey: String? = nil

    var body: some View { Text("標成已繳") }
}

/// 帳單金額不一樣（哪一期 nil＝最近一期已結帳的）
struct WealthStatedAmountSheet: View {
    let cardId: UUID
    var statementKey: String? = nil

    var body: some View { Text("帳單金額不一樣") }
}

/// 一次改到別張卡（toCards true）／改到別的帳戶（false）：選新的、從哪天起（LifeStore.moveWealthLinks）
struct WealthMoveLinksSheet: View {
    let fromId: UUID
    var expenseIds: [UUID] = []
    var incomeIds: [UUID] = []
    var toCards: Bool = true

    var body: some View { Text("改到別的") }
}

/// 排序與收起來（⋯ → 一張表單；List edit mode，三段：銀行、信用卡、證券）
struct WealthOrderSheet: View {
    var body: some View { Text("排序與收起來") }
}

/// 匯率（要確認〔去設定〕；設定頁那一段是 private，這裡另外一張小表單改 ExpenseStore.currencyRates）
struct WealthRatesSheet: View {
    var body: some View { Text("匯率") }
}

/// 要確認（財富頁 ②、卡片頁 ② 共用；0 件整區不出現）。limit：先放幾件，「再看 N 件」
struct WealthChecksSection: View {
    let checks: [WealthCheck]
    var limit: Int? = 3

    var body: some View {
        if !checks.isEmpty {
            Text("要確認")
        }
    }
}
