import SwiftUI
import Charts
import UIKit
import UniformTypeIdentifiers

// MARK: - 財富的卡片頁（v25.564，財富 v3；wealth/judge.md §4.0–4.4）
//
// 一個入口 WealthCardPage(accountId:scrollTo:)：照那筆里程碑的子分類畫信用卡頁（§4.1）、銀行帳戶頁（§4.2）、
// 證券戶頁（§4.3 基本版）、保單頁（§4.4 基本版）。從財富頁項目卡、接下來 30 天、履歷、我的行事曆、要確認打開
// （呼叫端一律 .sheet(item:) { WealthCardPage(accountId: …).appStores() }）。
// 骨架照股票、房屋、車子的卡片頁（U3 §4.3）：ScrollViewReader > ScrollView > VStack(spacing: 22)；⓪ FinanceSwitcherStrip；
// 工具列 左「關閉」、中 MarqueeText、右綠〔＋〕＋綠字「編輯」（沒有分享、刪除在編輯頁最下面）；一個 WealthCardSheet＋
// 一個 .sheet(item:)＋.appStores()；資料 WealthCardData.build 在 .task(id:) 算一次；整頁掛 WealthPrivacyCurtain(armed: true)，
// 切到背景號碼收回。每區一個小 struct（坑 #7）。
//
// 分工：G2 實作（這個檔＋Models/WealthCardData.swift）。主控只放能編譯的入口，簽章不要改（G1、G3 在叫）。
//
// [v25.564] G2：
// • 字和數字全在 WealthCardData（Models/WealthCardData.swift），這裡只排版、上色、決定點了做什麼。
// • 彈出頁一個 WealthCardSheet（id 每次新的 UUID，坑 #8）＋一個 .sheet(item:)，內容 .appStores()；記帳、收入、股票表單外面
//   再包 WealthPrivacyCurtain(armed: true)。確認框一個（停用卡、收起來、刪轉帳）；付費說明一個；號碼解不開的說明一個。
// • 付費（第 10 題）：看全部不擋；記一筆、刷這張卡記一筆、轉帳、對存摺、編輯、改到別張卡／別的帳戶、權益與說明的＋、補記差額、
//   財富自己記的那一筆（存提款、對存摺、刪轉帳）要訂閱；標成已繳、帳單金額不一樣、取消已繳、算到下一期、停用／啟用、
//   收起來／打開、看號碼、打開記帳／收入／股票那一筆（記帳本來就不擋，同 v2）不擋。
// • 號碼（第 6、7 題）：〔顯示〕一顆 Face ID 全部解開（卡號、有效期限、安全碼〔有存才有那一列〕、票證、帳號、保單號碼），
//   只放在 @State（WealthCardReveal），30 秒、切到背景、離開這頁就收回；帳號〔複製〕剪貼簿只在這台、60 秒過期。
// • 寫 store：store 先抓進區域常數，下一個 runloop 才寫（長按選單、確認框正在收起來）。
//
// [v25.565] 財富 v4（build/v4/brief.md §G4-8）：卡片頁自己的要確認 #12〔看綁了哪些〕直接捲到「綁在這張卡的定期扣款」
//（WealthChecksSection(onOpenCard:)，不再疊一張卡片頁）。從財富頁、理財、行事曆、小工具、通知打開都是 WealthCardPage(accountId:)。
//
// [v25.566] 財富 v5 G2（build/v5/brief.md §6 G2；judge §4.2 ⑤⑥⑧）：
// • ⑤ 外幣（WealthCardForeignSection）：標題「外幣」、一個幣別一格、格子下一行說明、〔＋ 換匯〕（WealthTransferSheet exchange，要訂閱）。
// • ⑥ 定存（WealthCardDepositsSection，.id(.deposits)）：一期一格 FinanceProgressCell（點了開那一期的定存表單）、
//   舊的定存種類帳戶〔補上利率和到期日 ›〕、最下〔＋ 定存〕；新增、看、改都是 WealthTimeDepositSheet(accountId:editing:)（要訂閱）。
// • 明細、接下來 30 天點「轉定存」「定存到期」「定存利息」＝WealthCardOpen.timeDeposit：開定存表單，帳戶帶那一期自己的帳戶
//   （轉進薪轉的那一列在薪轉頁點，表單還是台灣銀行那一期）。
// • 記一筆選單（右上〔＋〕、存摺明細〔＋ 記一筆〕）多「定存」、有外幣時多「換匯」。
//
// [v25.567] 財富 v6 G2（build/v6/brief.md §6 G2；judge §4.3、§4.4）：
// • 證券戶：持股前面 ② 要交割（WealthCardBrokerDuesSection，.id(.dues)：一天一列，點了打開那檔股票；不夠的那天綠字〔轉帳過去〕
//   ＝WealthTransferSheet(toId:amount:) 帶好到哪、差多少，要訂閱）；持股後面 ⑤ 以前記在這裡的交割紀錄（WealthCardLegacySection，
//   .id(.legacy)：收成一列，點了展開唯讀明細；有交割銀行時右上綠字〔搬到薪轉〕＝WealthSettlementMoveSheet，不擋訂閱）。
// • 保單：④ 繳費連著記帳＝整塊點了開記帳那一筆（不擋）；沒連＝〔連到記帳的保費〕（WealthPolicyLinkSheet，要訂閱）
//  〔新建一筆〕（要訂閱 → 確認框「在記帳建一筆保費？」→ 下一個 runloop LifeStore.savePolicyPremium）；沒填保費＝「填保費 ›」；
//   ⑤ 誰的保單（WealthCardInfoSection；都沒寫一列「寫下要保人、被保險人、受益人 ›」）。看板風景是踏腳石（.stones）。
//
// [v25.568] 財富 v7 G2（build/v7/brief.md §4 G2；judge §4.1 ⑧⑨、§4.2 ⑧⑨、§4.4 ⑦、§7.1、§7.2）：
// • 〔顯示〕改讀密文：有效期限、保單號碼、悠遊卡／一卡通／Happy Go 卡號＝WealthSecrets.reveal（密文在 WealthVaultBook，
//   里程碑那一欄只留後 4 碼、是「有沒有」）；完整帳號＝WealthSecrets.revealAccount（帳本的密文；還沒搬的舊明碼也照看得到）。
//   卡號、安全碼照舊（第 6 題「我要存」：安全碼照樣加密存、Face ID 後 30 秒看得到）。open 一律 openIfKey（CardVault.open 本身也不產生金鑰）。
// • 30 秒收回、切背景收回、帳號〔複製〕60 秒＋只在這台都不動；這台還沒同步到金鑰：照舊跳說明（第一句改「這台還沒同步到金鑰」；
//   CardVault.keyMissingHere 時不再叫你去編輯畫面重打——重打也會被擋下，改說「金鑰同步過來就看得到」：missingKeyText）。
// • 照片 footer：信用卡「…拍到像完整卡號的數字會提醒你。」（提醒在表單加照片那一刻，WealthPhotoScan）；銀行、證券戶「…照片不會加密。」

/// 打開卡片頁時捲到哪一區（財富頁 ③ 點一列＝.upcoming；要確認、四格點了也用）
enum WealthCardAnchor: String, Hashable {
    case top, checks
    // 信用卡
    case statement, unbilled, recurring, history, fee, cardInfo, photos
    // 銀行（[v25.566] deposits＝⑥ 定存）
    case upcoming, linked, foreign, deposits, ledger, accountInfo, note
    // 證券戶、保單（[v25.567] dues＝② 要交割、legacy＝⑤ 以前記在這裡的交割紀錄）
    case holdings, payment, dues, legacy
}

// MARK: - 彈出頁、確認框、動作

/// 卡片頁的彈出頁（一個 .sheet(item:)；id 每次新的，同一種再打開一次也會重建表單）
struct WealthCardSheet: Identifiable {
    enum Kind {
        /// 編輯帳戶（類型、那筆里程碑、先捲到哪一段）
        case editor(WealthAccountKind, LifeMilestone, WealthEditorFocus?)
        /// 記一筆（帳戶、種類、幣別、編輯哪一筆）
        case record(UUID, WealthRecordKind, String?, BankDeposit?)
        /// 轉帳（從這個帳戶轉出）
        case transfer(UUID)
        /// 對存摺（帳戶、幣別、編輯哪一筆）
        case anchor(UUID, String, BankDeposit?)
        /// 標成已繳（卡、哪一期）
        case paid(UUID, String?)
        /// 帳單金額不一樣（卡、哪一期）
        case stated(UUID, String?)
        /// 改到別張卡／別的帳戶（從哪、記帳、收入、改到卡）
        case moveLinks(UUID, [UUID], [UUID], Bool)
        /// 記帳表單（刷這張卡、從這個帳戶、金額、標題、日期〔nil＝今天〕）
        case addExpense(UUID?, UUID?, Double?, String?, Date?)
        case expense(Expense)
        case income(Income)
        case stock(Stock)
        /// 另一張卡片頁（卡費那一列、交割的證券戶）
        case card(UUID, WealthCardAnchor?)
        /// [v25.566] 定存表單（帳戶、哪一期；nil＝新增）
        case timeDeposit(UUID, UUID?)
        /// [v25.566] 換匯（這個帳戶兩個幣別互轉；只有一個外幣＝從別的台幣帳戶轉進來）
        case exchange(UUID)
        /// [v25.567] 證券戶舊交割搬家（證券戶 id；先給你看會動到哪些；不擋訂閱）
        case settlementMove(UUID)
        /// [v25.567] 保單〔連到記帳的保費〕（保單 id；要訂閱）
        case policyLink(UUID)
        /// [v25.567] 要交割不夠〔轉帳過去〕（轉到哪個帳戶、先填好的金額；要訂閱）
        case transferTo(UUID, Double)
    }
    let id = UUID()
    let kind: Kind
}

/// 要先問的事（一個 confirmationDialog）
enum WealthCardConfirm: Identifiable {
    /// 停用這張卡（還有幾筆定期扣款刷它）
    case disableCard(UUID, Int)
    /// 收起來（銷戶）；存摺上還有錢＝「還有 3,200」
    case hideAccount(UUID, String?)
    /// 刪一筆轉帳（BankDeposit 的 id）
    case deleteTransfer(UUID)
    /// [v25.567] 保單〔新建一筆〕：照保單的保費在記帳建一筆固定支出（保單 id；確認框的字讀 WealthCardPolicy.createMessage）
    case createPolicyExpense(UUID)

    var id: String {
        switch self {
        case .disableCard(let id, _): return "disable-" + id.uuidString
        case .hideAccount(let id, _): return "hide-" + id.uuidString
        case .deleteTransfer(let id): return "transfer-" + id.uuidString
        case .createPolicyExpense(let id): return "policyexpense-" + id.uuidString
        }
    }

    var title: String {
        switch self {
        case .disableCard: return "停用這張卡？"
        case .hideAccount: return "收起來（銷戶）？"
        case .deleteTransfer: return "刪除這筆轉帳？"
        case .createPolicyExpense: return "在記帳建一筆保費？"
        }
    }

    /// 確認框的字（〔新建一筆〕的那一句在 WealthCardData 組好，卡片頁的 confirmMessage 換上；這裡是找不到時的一般說法）
    var message: String {
        switch self {
        case .disableCard(_, let n):
            let base = "停用後不會出現在記帳的卡片選單，歷史帳單照算。"
            return n > 0 ? base + "還有 \(n) 筆定期扣款刷它，要先改嗎？" : base
        case .hideAccount(_, let left):
            let base = "收起來以後不算進存款合計、不出現在記帳的選單；歷史照留，隨時可以重新打開。"
            if let l = left { return l + "，要轉到哪？" + base }
            return base
        case .deleteTransfer:
            return "轉帳兩邊各記了一筆：可以兩邊一起刪，或只刪這個帳戶這一筆。"
        case .createPolicyExpense:
            return "照保單的保費在記帳建一筆固定支出（保險）；以前的不補記。記帳、稅務頁都看得到，在記帳改金額保單跟著。"
        }
    }
}

/// 各區要做的事（全部交回卡片頁：開表單、付費擋、問確認、寫 store 都在那裡）
struct WealthCardActions {
    var scroll: (WealthCardAnchor) -> Void = { _ in }
    var tap: (WealthCardTap) -> Void = { _ in }
    var open: (WealthCardOpen) -> Void = { _ in }
    /// 打開一張彈出頁（第二個參數＝要訂閱）
    var present: (WealthCardSheet.Kind, Bool) -> Void = { _, _ in }
    var confirm: (WealthCardConfirm) -> Void = { _ in }
    var askPremium: () -> Void = {}
    /// 〔算到下一期〕(true)／〔算回原本那一期〕(false)：刷卡的 id
    var shiftEntry: (String, Bool) -> Void = { _, _ in }
    /// 〔取消已繳〕：帳單 key
    var unpay: (String) -> Void = { _ in }
    var reveal: () -> Void = {}
    var copyAccount: () -> Void = {}
    var setDisabled: (Bool) -> Void = { _ in }
    var setHidden: (Bool) -> Void = { _ in }
}

/// 號碼解開的狀態（只活在卡片頁的 @State；30 秒、切背景、離開就清掉）
struct WealthCardReveal {
    var values: [WealthCardInfo.Secret: String] = [:]
    var on = false
    var busy = false
    var copied = false
}

// MARK: - 卡片頁

/// 財富的卡片頁（入口；簽章不改：G1、G3 用 .sheet(item:) { WealthCardPage(accountId: id, scrollTo: …).appStores() } 打開）
struct WealthCardPage: View {
    let accountId: UUID
    var scrollTo: WealthCardAnchor? = nil

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// 遮住（財富頁右上的眼睛；同一顆）
    @AppStorage(WealthMask.storageKey) private var masked = false

    /// @State 而不是 let：換項目列點一下就換一個（同一張卡片換內容，不重開 sheet）
    @State private var currentId: UUID
    /// 打開時要捲到的那一區；捲過一次就清掉
    @State private var startAnchor: WealthCardAnchor?
    /// 要捲過去的那一區（格子、確認框〔先去改〕；ScrollViewReader 裡 onChange 接）
    @State private var pendingScroll: WealthCardAnchor?
    @State private var slideDirection = 1
    @State private var data: WealthCardData?
    @State private var checks: [WealthCheck] = []
    @State private var lastBuiltKey = ""
    @State private var sheet: WealthCardSheet?
    @State private var confirm: WealthCardConfirm?
    @State private var showPremiumAlert = false
    @State private var reveal = WealthCardReveal()
    @State private var revealMessage: String?
    @State private var relockTask: Task<Void, Never>?

    init(accountId: UUID, scrollTo: WealthCardAnchor? = nil) {
        self.accountId = accountId
        self.scrollTo = scrollTo
        _currentId = State(initialValue: accountId)
        _startAnchor = State(initialValue: scrollTo)
    }

    var body: some View {
        NavigationStack {
            withPresentations(scroller)
        }
        // 不是 .active（App 切換器、控制中心、來電）就把號碼收回；布幕一律掛著（judge §7.1）
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { lock() }
        }
        .onDisappear { lock() }
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    private var scroller: some View {
        ScrollViewReader { proxy in
            ScrollView {
                pageContent
            }
            .background(Color(.systemGroupedBackground))
            .task(id: taskKey) { rebuild() }
            .onChange(of: pendingScroll) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(target, anchor: .top)
                }
                pendingScroll = nil
            }
        }
        // 換項目列釘在導覽列下面：同一類不只一個才出現
        .safeAreaInset(edge: .top, spacing: 0) { switcherBar }
        .navigationTitle(data?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
    }

    // MARK: 內容

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: slideDirection > 0 ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: slideDirection > 0 ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var pageContent: some View {
        VStack(spacing: 22) {
            if let d = data {
                WealthCardBoardView(data: d, actions: actions)
                    .id(WealthCardAnchor.top)
                if !checks.isEmpty {
                    // [v25.565] #12〔看綁了哪些〕：就是這張卡，直接捲到綁在這張卡的定期扣款（不再疊一張卡片頁）
                    WealthChecksSection(checks: checks, limit: nil, onOpenCard: { _ in showRecurring() })
                        .id(WealthCardAnchor.checks)
                }
                kindSections(d)
            } else {
                Color.clear.frame(height: 360)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 28)
        // 換項目時整包內容依方向滑入（id 變了就觸發轉場）；各區自己的展開、篩選跟著歸零
        .id(currentId)
        .transition(slideTransition)
    }

    /// 四種頁各自的區（在邊界抹成 AnyView：型別不要太深，坑 #6）
    private func kindSections(_ d: WealthCardData) -> AnyView {
        let a = actions
        switch d.kind {
        case .card:
            guard let c = d.credit else { return AnyView(EmptyView()) }
            return AnyView(WealthCreditSections(cardId: d.id, credit: c, reveal: reveal, actions: a))
        case .bank:
            guard let b = d.bank else { return AnyView(EmptyView()) }
            return AnyView(WealthBankSections(accountId: d.id, bank: b, codes: d.codes, reveal: reveal,
                                              isPremium: subscription.isPremium, masked: masked, actions: a))
        case .broker:
            guard let b = d.broker else { return AnyView(EmptyView()) }
            return AnyView(WealthBrokerSections(brokerId: d.id, broker: b, reveal: reveal, actions: a))
        case .policy:
            guard let p = d.policy else { return AnyView(EmptyView()) }
            return AnyView(WealthPolicySections(policyId: d.id, policy: p, isPremium: subscription.isPremium,
                                                reveal: reveal, actions: a))
        }
    }

    // MARK: 算資料、換項目

    private var taskKey: String { key(for: currentId) }

    /// 換項目、財富帳本／里程碑、記帳、理財改了、換日、遮住都要重算
    private func key(for id: UUID) -> String {
        "\(id.uuidString)-\(lifeStore.wealthRevision)-\(expenseStore.modifyID)-\(financeStore.modifyID)"
            + "-\(WealthCal.dayKey(Date()))-\(masked)"
    }

    /// 在主執行緒算（一套數字讀 LifeStore 的快取）
    private func build(for id: UUID) -> (data: WealthCardData?, checks: [WealthCheck]) {
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        let d = WealthCardData.build(id: id, facts: facts, life: lifeStore, expense: expenseStore,
                                     finance: financeStore, now: Date(), masked: masked)
        return (d, facts.checks(for: id))
    }

    private func rebuild() {
        let k = taskKey
        if data != nil && k == lastBuiltKey {
            scrollToStartIfNeeded()
            return
        }
        let built = build(for: currentId)
        guard let d = built.data else {
            // 被刪掉了（編輯頁最下面刪的、別台裝置同步過來的）：晚一點才關，編輯頁可能還在往下收
            data = nil
            lastBuiltKey = ""
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                dismiss()
            }
            return
        }
        data = d
        checks = built.checks
        lastBuiltKey = k
        scrollToStartIfNeeded()
    }

    /// [v25.565] 要確認 #12〔看綁了哪些〕：捲到「綁在這張卡的定期扣款」（ScrollViewReader 的 onChange(of: pendingScroll) 接）
    private func showRecurring() {
        pendingScroll = .recurring
    }

    /// 打開時要捲到的那一區：等各區真的畫出來再捲
    private func scrollToStartIfNeeded() {
        guard let a = startAnchor else { return }
        startAnchor = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            pendingScroll = a
        }
    }

    @ViewBuilder
    private var switcherBar: some View {
        if let items = data?.switcher, items.count > 1 {
            FinanceSwitcherStrip(items: items, selected: currentId) { id in
                select(id, in: items)
            }
            .padding(.vertical, 4)
            .background(.bar)
        }
    }

    /// 換到另一個（新的那個先同步算好再換，滑進來的不會是一塊空白）；號碼先收回
    private func select(_ id: UUID, in items: [FinanceSwitcherItem]) {
        guard id != currentId else { return }
        let from = items.firstIndex { $0.id == currentId } ?? 0
        let to = items.firstIndex { $0.id == id } ?? 0
        let built = build(for: id)
        lock()
        slideDirection = to >= from ? 1 : -1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            currentId = id
            data = built.data
            checks = built.checks
        }
        lastBuiltKey = built.data == nil ? "" : key(for: id)
    }

    // MARK: 工具列

    private var addIcon: some View {
        Image(systemName: "plus.circle.fill")
            .font(.title3)
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color.white, Color(tb: 0x1F9D57))
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("關閉") { dismiss() }
        }
        // 標題就是暱稱（太長跑馬燈）
        ToolbarItem(placement: .principal) {
            MarqueeText(data?.title ?? "")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 14) {
                addButton
                Button {
                    handle(.edit(nil))
                } label: {
                    Text("編輯").foregroundStyle(.green)
                }
                .disabled(data == nil)
            }
        }
    }

    /// 右上綠〔＋〕：銀行（存款／提款／利息／手續費／轉帳／對存摺，要訂閱，沒訂閱按了直接跳說明）；
    /// 卡（刷這張卡記一筆〔要訂閱〕、標成已繳〔不擋〕）；證券戶、保單沒有
    @ViewBuilder
    private var addButton: some View {
        switch data?.kind {
        case .card?:
            cardAddMenu
        case .bank?:
            bankAddMenu
        default:
            EmptyView()
        }
    }

    private var cardAddMenu: some View {
        Menu {
            Button {
                present(.addExpense(currentId, nil, nil, nil, nil), premium: true)
            } label: {
                Label("刷這張卡記一筆", systemImage: "creditcard")
            }
            Button {
                present(.paid(currentId, nil), premium: false)
            } label: {
                Label("標成已繳", systemImage: "checkmark.circle")
            }
        } label: {
            addIcon
        }
        .accessibilityLabel("記一筆")
    }

    @ViewBuilder
    private var bankAddMenu: some View {
        if subscription.isPremium {
            Menu {
                WealthBankAddItems(accountId: currentId, codes: data?.codes ?? ["NT$"], actions: actions,
                                   accountHidden: data?.bank?.hidden ?? false)
            } label: {
                addIcon
            }
            .accessibilityLabel("記一筆")
        } else {
            Button {
                showPremiumAlert = true
            } label: {
                addIcon
            }
            .accessibilityLabel("記一筆")
        }
    }

    // MARK: 點了做什麼

    private var actions: WealthCardActions {
        var a = WealthCardActions()
        a.scroll = { anchor in pendingScroll = anchor }
        a.tap = { t in handle(t) }
        a.open = { o in open(o) }
        a.present = { k, p in present(k, premium: p) }
        a.confirm = { c in confirm = c }
        a.askPremium = { showPremiumAlert = true }
        a.shiftEntry = { entry, next in shiftEntry(entry, next: next) }
        a.unpay = { k in unpay(k) }
        a.reveal = { toggleReveal() }
        a.copyAccount = { copyAccount() }
        a.setDisabled = { on in setDisabled(on) }
        a.setHidden = { on in setHidden(on) }
        return a
    }

    private func requirePremium(_ action: () -> Void) {
        if subscription.isPremium {
            action()
        } else {
            showPremiumAlert = true
        }
    }

    private func present(_ kind: WealthCardSheet.Kind, premium: Bool) {
        if premium && !subscription.isPremium {
            showPremiumAlert = true
            return
        }
        sheet = WealthCardSheet(kind: kind)
    }

    private func handle(_ t: WealthCardTap) {
        switch t {
        case .none:
            break
        case .scroll(let a):
            pendingScroll = a
        case .edit(let focus):
            guard let d = data, let m = lifeStore.milestones.first(where: { $0.id == currentId }) else { return }
            present(.editor(d.editKind, m, focus), premium: true)
        case .anchor(let code):
            present(.anchor(currentId, code, nil), premium: true)
        }
    }

    private func open(_ o: WealthCardOpen) {
        switch o {
        case .none:
            break
        // 打開記帳、收入那一筆＝看那一筆（記帳本來就不用訂閱；judge §10 第 10 題的擋法只擋財富自己的新增、編輯、記一筆、
        // 轉帳、對存摺），跟 v2 的帳戶頁一樣不擋
        case .expense(let id):
            guard let e = expenseStore.expenses.first(where: { $0.id == id }) else { return }
            present(.expense(e), premium: false)
        case .income(let id):
            guard let i = expenseStore.incomes.first(where: { $0.id == id }) else { return }
            present(.income(i), premium: false)
        case .stock(let id):
            guard let s = financeStore.stocks.first(where: { $0.id == id }) else { return }
            present(.stock(s), premium: false)
        case .card(let id, let anchor):
            if id == currentId {
                pendingScroll = anchor ?? .top
            } else {
                present(.card(id, anchor), premium: false)
            }
        case .record(let depId, let kind):
            guard let dep = deposit(depId) else { return }
            present(.record(currentId, kind, dep.currencyCode, dep), premium: true)
        case .anchorEdit(let depId):
            guard let dep = deposit(depId) else { return }
            present(.anchor(currentId, WealthFacts.norm(dep.currencyCode), dep), premium: true)
        case .transfer(let depId):
            requirePremium { confirm = .deleteTransfer(depId) }
        case .timeDeposit(let termId):
            // [v25.566] 帳戶帶那一期自己的（定存到期轉進薪轉的那一列在薪轉頁點，表單還是台灣銀行那一期）
            let owner = lifeStore.timeDepositRecord(termId)?.bankId ?? currentId
            present(.timeDeposit(owner, termId), premium: true)
        }
    }

    private func deposit(_ id: UUID) -> BankDeposit? {
        lifeStore.milestones.first(where: { $0.id == currentId })?.bankDeposits?.first(where: { $0.id == id })
    }

    // MARK: 寫 store（store 先抓進區域常數、下一個 runloop 才寫）

    private func shiftEntry(_ entryId: String, next: Bool) {
        let life = lifeStore
        let cid = currentId
        DispatchQueue.main.async {
            life.setEntryNextPeriod(cardId: cid, entryId: entryId, next)
        }
    }

    private func unpay(_ key: String) {
        let life = lifeStore
        let cid = currentId
        DispatchQueue.main.async {
            life.clearStatementPaid(cardId: cid, key: key)
        }
    }

    private func setDisabled(_ on: Bool) {
        let life = lifeStore
        let cid = currentId
        DispatchQueue.main.async {
            life.setCardDisabled(cid, disabled: on)
        }
    }

    private func setHidden(_ on: Bool) {
        let life = lifeStore
        let cid = currentId
        DispatchQueue.main.async {
            life.setWealthHidden(cid, hidden: on)
        }
    }

    private func deleteTransfer(_ depositId: UUID, pair: Bool) {
        let life = lifeStore
        let cid = currentId
        DispatchQueue.main.async {
            life.deleteBankDeposit(depositId, in: cid, includingPair: pair)
        }
    }

    /// [v25.567] 保單〔新建一筆〕確定：照 WealthCardData 組好的那一筆（第一期 WealthPolicyLink.firstDue、以前的不補記）在記帳建
    /// 一筆固定支出（保險）並連起來（確認框正在收起來：下一個 runloop 才寫）
    private func createPolicyExpense(_ policyId: UUID) {
        guard data?.id == policyId, let draft = data?.policy?.createDraft else { return }
        let life = lifeStore
        let es = expenseStore
        DispatchQueue.main.async {
            _ = life.savePolicyPremium(policyId: policyId, draft: draft, useExpenseId: nil, create: true, expense: es)
        }
    }

    /// 確認框的字：〔新建一筆〕讀資料端組好的那一句（保費、繳法、從哪扣、第一期）
    private func confirmMessage(_ c: WealthCardConfirm) -> String {
        switch c {
        case .createPolicyExpense:
            return data?.policy?.createMessage ?? c.message
        case .disableCard, .hideAccount, .deleteTransfer:
            return c.message
        }
    }

    /// 確認框按了要開表單：等確認框收起來再開（同一個畫面一次只能彈一個）
    private func presentLater(_ kind: WealthCardSheet.Kind) {
        if !subscription.isPremium {
            showPremiumAlert = true
            return
        }
        DispatchQueue.main.async {
            sheet = WealthCardSheet(kind: kind)
        }
    }

    // MARK: 號碼（Face ID、30 秒收回、切背景收回；明碼只在 @State）

    private var revealReason: String {
        switch data?.kind {
        case .card?: return "檢視完整卡號、有效期限、安全碼與票證號碼"
        case .policy?: return "檢視完整保單號碼"
        default: return "檢視完整帳號"
        }
    }

    private var revealAlertTitle: String {
        data?.kind == .card ? "卡號與安全資訊" : "號碼與安全資訊"
    }

    private func toggleReveal() {
        if reveal.on {
            lock()
            return
        }
        guard !reveal.busy else { return }
        reveal.busy = true
        let reason = revealReason
        let id = currentId
        Task { @MainActor in
            let result = await CardVault.unlock(reason: reason)
            reveal.busy = false
            guard id == currentId else { return }
            switch result {
            case .ok:
                let got = secretValues(for: id)
                if got.missingKey {
                    revealMessage = Self.missingKeyText
                }
                reveal.values = got.values
                reveal.on = true
                scheduleRelock()
            case .denied:
                break
            case .unavailable(let message):
                revealMessage = message
            }
        }
    }

    /// 這一筆的完整號碼（只在按了〔顯示〕、Face ID 過了才讀）。
    /// [v25.568] 有效期限、票證號、保單號碼讀密文那一包（WealthVaultBook）；完整帳號讀帳本的密文（或還沒搬的舊明碼）。
    /// 里程碑那一欄是「有沒有」：空的＝沒有這個號碼（還沒更新的 iPad 清掉了，密文不算數）；規則都在 WealthSecrets，這裡只排字
    private func secretValues(for id: UUID) -> (values: [WealthCardInfo.Secret: String], missingKey: Bool) {
        guard let m = lifeStore.milestones.first(where: { $0.id == id }) else { return ([:], false) }
        var v: [WealthCardInfo.Secret: String] = [:]
        var missing = false
        if let cipher = m.cardNumberCipher {
            if let n = Self.openIfKey(cipher), !n.isEmpty { v[.cardNumber] = CardVault.grouped(n) } else { missing = true }
        }
        // 第 6 題「我要存」：安全碼照樣加密存，跟卡號同一顆 Face ID
        if let cipher = m.cardSecurityCipher {
            if let s = Self.openIfKey(cipher), !s.isEmpty { v[.securityCode] = s } else { missing = true }
        }
        // 有效期限（「03/27」）、三種票證（卡）、保單號碼（保單）：一個迴圈（那一欄空的＝沒有這個號碼，跳過）
        let sub = m.financeSubCategory ?? .bank
        let entry = lifeStore.wealthVault.entry(id)
        let pairs: [(WealthSecretField, WealthCardInfo.Secret)] = Self.vaultPairs(sub)
        for (field, slot) in pairs {
            let r = WealthSecrets.reveal(field, milestone: m, entry: entry,
                                         open: { (d: Data) -> String? in Self.openIfKey(d) })
            if r.missingKey { missing = true }
            guard let s = r.value, !s.isEmpty else { continue }
            v[slot] = Self.revealedText(s, for: field)
        }
        // 帳號（銀行、證券戶）：還沒搬的舊明碼 → 帳本的密文（第 7 題）；只剩末 4 碼、沒有密文＝沒有〔顯示〕可看
        if sub == .bank || sub == .securities {
            let account = WealthSecrets.revealAccount(milestone: m, prefs: lifeStore.wealthBook.account(id),
                                                      open: { (d: Data) -> String? in Self.openIfKey(d) })
            if account.missingKey { missing = true }
            if let s = account.value, !s.isEmpty { v[.account] = s }
        }
        return (v, missing)
    }

    /// 這一種頁要從密文那一包解哪幾個號碼（跟 sim_v7 reveal 同：卡＝有效期限＋三種票證、保單＝保單號碼、其他沒有）
    private static func vaultPairs(_ sub: FinanceSubCategory) -> [(WealthSecretField, WealthCardInfo.Secret)] {
        switch sub {
        case .creditCard:
            return [(.expiry, .expiry), (.easyCard, .easyCard), (.iPass, .iPass), (.happyGo, .happyGo)]
        case .insurance:
            return [(.policy, .policy)]
        case .bank, .securities:
            return []
        }
    }

    /// 解出來的字怎麼排：一卡通照舊能分組就四碼一組（悠遊卡、Happy Go、保單號碼、有效期限照原樣）
    private static func revealedText(_ s: String, for field: WealthSecretField) -> String {
        guard field == .iPass, CardVault.isSafeToRegroup(s) else { return s }
        return CardVault.grouped(s, limit: CardVault.iPassDigits)
    }

    /// [v25.568] 〔顯示〕解不開時的說明（同表單 WealthEditors.missingKeyMessage 的分法）：這台還沒同步到金鑰（CardVault.keyMissingHere）
    /// 時重打也存不了（CardVault 規矩 2：免得蓋掉另一台的金鑰），所以不叫你去重打；這台有金鑰卻解不開（密文是另一把金鑰封的）才請你重打
    private static var missingKeyText: String {
        // 「原本存的號碼都還在」只在還沒同步到金鑰時說（金鑰同步過來就解得開）；這台有金鑰卻解不開＝照舊請你重打
        let retype: String = CardVault.keyMissingHere
            ? "金鑰同步過來就看得到；在那之前這台也存不了新打的號碼（免得蓋掉另一台的金鑰）。原本存的號碼都還在。"
            : "若金鑰已經遺失，請到編輯畫面重新輸入一次。"
        return "這台還沒同步到金鑰，看不到原本存的號碼。"
            + "金鑰是透過 iCloud 鑰匙圈同步的，請確認「設定 → Apple ID → iCloud → 密碼與鑰匙圈」已開啟；"
            + retype
    }

    /// 這台有金鑰才解。[v25.568] CardVault.open 本身也從不產生金鑰了（CardVault 規矩 3）；這裡照留，
    /// 沒有金鑰時直接當作解不開（照樣跳「這台還沒同步到金鑰」的說明）
    private static func openIfKey(_ cipher: Data?) -> String? {
        guard CardVault.hasKey else { return nil }
        return CardVault.open(cipher)
    }

    /// 看完 30 秒自動收回
    private func scheduleRelock() {
        relockTask?.cancel()
        relockTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            lock()
        }
    }

    /// 收回號碼（Face ID 視窗出來那一刻也是 .inactive：那時還沒解開，只是再收一次；busy 照留）
    private func lock() {
        relockTask?.cancel()
        relockTask = nil
        guard reveal.on || !reveal.values.isEmpty || reveal.copied else { return }
        let busy = reveal.busy
        var fresh = WealthCardReveal()
        fresh.busy = busy
        reveal = fresh
    }

    /// 帳號〔複製〕：剪貼簿只在這台（不經 iCloud 到別台）、60 秒後清掉
    private func copyAccount() {
        guard reveal.on, let n = reveal.values[.account], !n.isEmpty else { return }
        UIPasteboard.general.setItems([[UTType.plainText.identifier: n]],
                                      options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
        reveal.copied = true
    }

    // MARK: 彈出頁、確認框（分段掛：坑 #7）

    private func withPresentations<Content: View>(_ content: Content) -> some View {
        withAlerts(content.sheet(item: $sheet) { s in sheetView(s).appStores() })
    }

    private func withAlerts<Content: View>(_ content: Content) -> some View {
        content
            .confirmationDialog(confirm?.title ?? "", isPresented: confirmPresented, titleVisibility: .visible,
                                presenting: confirm) { c in
                confirmButtons(c)
            } message: { c in
                Text(confirmMessage(c))
            }
            .alert(revealAlertTitle, isPresented: revealMessagePresented) {
                Button("好") { revealMessage = nil }
            } message: {
                Text(revealMessage ?? "")
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
    }

    private var confirmPresented: Binding<Bool> {
        Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })
    }

    private var revealMessagePresented: Binding<Bool> {
        Binding(get: { revealMessage != nil }, set: { if !$0 { revealMessage = nil } })
    }

    @ViewBuilder
    private func confirmButtons(_ c: WealthCardConfirm) -> some View {
        switch c {
        case .disableCard(_, let n):
            if n > 0 {
                Button("先去改") { pendingScroll = .recurring }
                Button("直接停用", role: .destructive) { setDisabled(true) }
            } else {
                Button("停用", role: .destructive) { setDisabled(true) }
            }
            Button("取消", role: .cancel) {}
        case .hideAccount(_, let left):
            if left != nil {
                Button("轉帳") { presentLater(.transfer(currentId)) }
                Button("對存摺成 0") {
                    presentLater(.anchor(currentId, data?.bank?.primaryCode ?? "NT$", nil))
                }
                Button("直接收起來", role: .destructive) { setHidden(true) }
            } else {
                Button("收起來", role: .destructive) { setHidden(true) }
            }
            Button("取消", role: .cancel) {}
        case .deleteTransfer(let depId):
            Button("兩邊一起刪", role: .destructive) { deleteTransfer(depId, pair: true) }
            Button("只刪這一筆", role: .destructive) { deleteTransfer(depId, pair: false) }
            Button("取消", role: .cancel) {}
        case .createPolicyExpense(let pid):
            Button("建一筆") { createPolicyExpense(pid) }
            Button("取消", role: .cancel) {}
        }
    }

    /// 每一種在邊界抹成 AnyView（坑 #6）；記帳、收入、股票表單外面再包布幕（切到背景蓋住帳戶名、金額）
    private func sheetView(_ s: WealthCardSheet) -> AnyView {
        switch s.kind {
        case .editor(let kind, let m, let focus):
            return AnyView(WealthAccountEditor(kind: kind, editing: m, focus: focus))
        case .record(let id, let kind, let code, let dep):
            return AnyView(WealthRecordSheet(accountId: id, kind: kind, code: code, editing: dep))
        case .transfer(let id):
            return AnyView(WealthTransferSheet(fromId: id))
        case .anchor(let id, let code, let dep):
            return AnyView(WealthAnchorSheet(accountId: id, code: code, editing: dep))
        case .paid(let id, let key):
            return AnyView(WealthPaidSheet(cardId: id, statementKey: key))
        case .stated(let id, let key):
            return AnyView(WealthStatedAmountSheet(cardId: id, statementKey: key))
        case .moveLinks(let from, let expenseIds, let incomeIds, let toCards):
            return AnyView(WealthMoveLinksSheet(fromId: from, expenseIds: expenseIds, incomeIds: incomeIds,
                                                toCards: toCards))
        case .addExpense(let card, let bank, let amount, let title, let day):
            let preset = AddExpensePreset(date: day, paymentCardId: card, paymentBankId: bank, amount: amount,
                                          title: title)
            return AnyView(AddExpenseView(expenseType: .variable, preset: preset)
                .modifier(WealthPrivacyCurtain(armed: true)))
        case .expense(let e):
            return AnyView(AddExpenseView(expenseType: e.expenseType, editingExpense: e)
                .modifier(WealthPrivacyCurtain(armed: true)))
        case .income(let i):
            return AnyView(AddIncomeView(editing: i)
                .modifier(WealthPrivacyCurtain(armed: true)))
        case .stock(let st):
            return AnyView(StockDetailView(stock: st)
                .modifier(WealthPrivacyCurtain(armed: true)))
        case .card(let id, let anchor):
            return AnyView(WealthCardPage(accountId: id, scrollTo: anchor))
        // [v25.566] 定存表單、換匯（兩張表單自己掛 WealthPrivacyCurtain）
        case .timeDeposit(let account, let term):
            return AnyView(WealthTimeDepositSheet(accountId: account, editing: term))
        case .exchange(let id):
            return AnyView(WealthTransferSheet(fromId: id, toId: id, exchange: true))
        // [v25.567] 搬交割、連記帳保費（G3 的兩張表單自己掛布幕）、要交割不夠轉帳過去（從哪轉表單裡選）
        case .settlementMove(let id):
            return AnyView(WealthSettlementMoveSheet(brokerId: id))
        case .policyLink(let id):
            return AnyView(WealthPolicyLinkSheet(policyId: id))
        case .transferTo(let id, let amount):
            return AnyView(WealthTransferSheet(toId: id, amount: amount))
        }
    }
}

/// 銀行的記一筆選單（右上〔＋〕、存摺明細〔＋ 記一筆〕共用）
struct WealthBankAddItems: View {
    let accountId: UUID
    let codes: [String]
    let actions: WealthCardActions
    /// [v25.566] 收起來（銷戶）的帳戶：不列「定存」「換匯」（同 ⑥ 沒有〔＋ 定存〕）
    var accountHidden = false

    /// [v25.566] 這個帳戶有外幣（「換匯」才出現）
    private var hasForeign: Bool {
        !accountHidden && codes.contains { !FinanceRates.isNTD($0) }
    }

    var body: some View {
        ForEach(WealthRecordKind.allCases) { k in
            Button(k.title) {
                actions.present(.record(accountId, k, nil, nil), true)
            }
        }
        Button("轉帳") {
            actions.present(.transfer(accountId), true)
        }
        // [v25.566] 定存（記在這個帳戶）、換匯（有外幣才有）
        if !accountHidden {
            Button("定存") {
                actions.present(.timeDeposit(accountId, nil), true)
            }
        }
        if hasForeign {
            Button("換匯") {
                actions.present(.exchange(accountId), true)
            }
        }
        if codes.count > 1 {
            Menu("對存摺") {
                ForEach(codes, id: \.self) { c in
                    Button(WealthCardText.codeName(c)) {
                        actions.present(.anchor(accountId, c, nil), true)
                    }
                }
            }
        } else {
            Button("對存摺") {
                actions.present(.anchor(accountId, codes.first ?? "NT$", nil), true)
            }
        }
    }
}

// MARK: - ① 看板

/// 看板（天空＋風景＋四格／保單的繳費進度格）：外框照 WealthBoard（MoneyBoardChrome、圓角讀英雄卡設定）
struct WealthCardBoardView: View {
    let data: WealthCardData
    let actions: WealthCardActions

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    /// 只讀「圓角」（同 WealthBoard／VehicleCardBoard）
    @ObservedObject private var heroStyle = HeroStyleStore.shared

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let corner = CGFloat(heroStyle.value(.corner, .lifeFinance))
        VStack(alignment: .leading, spacing: 0) {
            header(pal)
            if hasBelow {
                below(pal)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
            }
        }
        .modifier(MoneyBoardChrome(pal: pal, corner: corner))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var hasBelow: Bool {
        !data.tiles.isEmpty || data.progress != nil
    }

    private func header(_ pal: TripBoardPalette) -> some View {
        let b = data.board
        let tint: Color? = b.capsuleTone == MoneyTone.neutral ? nil : b.capsuleTone.color(pal)
        let line: Text? = b.line.runs.isEmpty ? nil : FinanceLineText.text(b.line, pal: pal)
        return MoneyBoardHeader(
            date: b.date,
            dateIcon: b.dateIcon,
            capsule: b.capsule,
            capsuleIcon: b.capsuleIcon,
            capsuleTint: tint,
            label: b.label,
            big: b.big,
            bigTone: b.bigTone,
            line: line,
            greeting: b.greeting,
            scene: data.scene,
            band: data.band,
            seed: data.seed)
            // 整個頭部一個 VoiceOver 元素，唸資料端組好的那一句（風景本來就 accessibilityHidden）
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(b.accessibilityText)
    }

    private func below(_ pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let p = data.progress {
                FinanceProgressCell(p: p, pal: pal, tappable: false)
            }
            if !data.tiles.isEmpty {
                tilesView(pal)
            }
        }
    }

    /// 一列兩格；字放到 xxLarge 以上一列一格
    @ViewBuilder
    private func tilesView(_ pal: TripBoardPalette) -> some View {
        if typeSize >= .xxLarge {
            VStack(spacing: 8) {
                ForEach(data.tiles) { t in
                    tile(t, pal: pal)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            MoneyTileGrid(tiles: data.tiles.map { AnyView(tile($0, pal: pal)) })
        }
    }

    private func tile(_ t: WealthCardTile, pal: TripBoardPalette) -> some View {
        let a = actions
        let tap = t.tap
        let action: (() -> Void)? = tap == WealthCardTap.none ? nil : { a.tap(tap) }
        return MoneyTile(icon: t.icon, tint: t.tint, label: t.label, value: t.value, valueTone: t.valueTone,
                         detail: t.detail, accent: t.accent, accentTone: t.accentTone, action: action,
                         actionHint: Self.hint(tap), watermark: t.icon, pal: pal)
    }

    private static func hint(_ t: WealthCardTap) -> String {
        switch t {
        case .none: return ""
        case .scroll: return "點兩下捲到那一區"
        case .edit: return "點兩下打開編輯"
        case .anchor: return "點兩下對存摺"
        }
    }
}

// MARK: - 共用：一列、資料卡、照片

/// 清單的一列（照 FinanceLedgerRow：52pt 日期塊、32pt 圓裡一個字、標題與細字、右邊金額＋底下小字）
struct WealthCardRowView: View {
    let row: WealthCardRow
    let pal: TripBoardPalette

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            dateBlock
            Text(row.glyph)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color.white)
                .frame(width: 32, height: 32)
                .background(Color(tb: row.mark), in: Circle())
                .accessibilityHidden(true)
            texts
            Spacer(minLength: 6)
            amount
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(rowFill)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityText)
    }

    private var rowFill: Color {
        row.warn ? MoneyTone.warn.color(pal).opacity(0.10) : Color.clear
    }

    private var dateBlock: some View {
        VStack(spacing: 0) {
            Text(row.dayText)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .monospacedDigit()
            Text(row.monthText)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 52)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let tag = row.tag {
                    FinanceMiniTag(text: tag, color: MoneyTone.good.color(pal))
                }
            }
            if !row.detail.isEmpty {
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private var amountColor: Color {
        if row.warn { return MoneyTone.warn.color(pal) }
        return row.amountTone?.color(pal) ?? Color.primary
    }

    private var amount: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(row.amountText)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(amountColor)
                .lineLimit(1)
            if let sub = row.sub {
                Text(sub)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(row.warn ? MoneyTone.warn.color(pal) : Color.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// 一列可以點（打開那一筆）；刷卡的長按〔算到下一期〕／〔算回原本那一期〕
struct WealthCardRowButton: View {
    let row: WealthCardRow
    let actions: WealthCardActions
    let pal: TripBoardPalette

    var body: some View {
        Button {
            actions.open(row.open)
        } label: {
            WealthCardRowView(row: row, pal: pal)
        }
        .buttonStyle(.plain)
        .disabled(row.open == WealthCardOpen.none)
        .contextMenu {
            menuItems
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        if let e = row.entryId {
            if row.shifted {
                Button {
                    actions.shiftEntry(e, false)
                } label: {
                    Label("算回原本那一期", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button {
                    actions.shiftEntry(e, true)
                } label: {
                    Label("算到下一期", systemImage: "arrow.right.to.line")
                }
            }
        }
        if row.open != WealthCardOpen.none {
            Button {
                actions.open(row.open)
            } label: {
                Label("打開這一筆", systemImage: "square.and.pencil")
            }
        }
    }
}

/// 一串列（中間細線、可以收成前 N 筆）
struct WealthCardRowList: View {
    let rows: [WealthCardRow]
    var limit: Int = 5
    let moreTitle: String
    let actions: WealthCardActions
    let pal: TripBoardPalette

    @State private var showAll = false

    var body: some View {
        let shown: [WealthCardRow] = showAll ? rows : Array(rows.prefix(limit))
        VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, r in
                if i > 0 {
                    Divider().padding(.leading, 14)
                }
                WealthCardRowButton(row: r, actions: actions, pal: pal)
            }
            if !showAll && rows.count > limit {
                Divider().padding(.leading, 14)
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showAll = true }
                } label: {
                    Text(moreTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(pal.hint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 資料卡（卡片資料、帳戶資料、證券戶、保單資料）：號碼類只露末 4 碼＋〔顯示〕
struct WealthCardInfoSection: View {
    let title: String
    let rows: [WealthCardInfo]
    let reveal: WealthCardReveal
    let actions: WealthCardActions

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: title)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    if i > 0 {
                        Divider().padding(.leading, 14)
                    }
                    WealthCardInfoLine(row: r, reveal: reveal, actions: actions, pal: pal)
                }
            }
            .modifier(FinanceCardChrome())
            if reveal.copied {
                Text("已複製：只在這台裝置，60 秒後從剪貼簿清掉")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 資料卡的一列：左標籤、右值；號碼列尾〔顯示〕（帳號解開後多〔複製〕）；要補填的列尾小字按鈕
struct WealthCardInfoLine: View {
    let row: WealthCardInfo
    let reveal: WealthCardReveal
    let actions: WealthCardActions
    let pal: TripBoardPalette

    private var valueText: String {
        if reveal.on, let s = row.secret, let v = reveal.values[s], !v.isEmpty { return v }
        return row.value
    }

    private var valueColor: Color {
        row.tone?.color(pal) ?? Color.primary
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(row.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 96, alignment: .leading)
            Text(valueText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var trailing: some View {
        if row.secret != nil {
            if reveal.on && row.secret == .account {
                smallButton("複製", icon: "doc.on.doc") { actions.copyAccount() }
            }
            smallButton(reveal.on ? "隱藏" : "顯示", icon: nil) { actions.reveal() }
                .disabled(reveal.busy)
        } else if let t = row.tapTitle, row.tap != WealthCardTap.none {
            let tap = row.tap
            smallButton(t, icon: nil) { actions.tap(tap) }
        }
    }

    private func smallButton(_ title: String, icon: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2.weight(.bold))
                }
                Text(title)
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(pal.hint)
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 32, minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 照片廊（v25.559 那支原樣：只看，加、刪在「編輯」裡）＋備註；右上綠＋（要訂閱 → 編輯）
struct WealthCardPhotosSection: View {
    let title: String
    var note: String = ""
    let photos: [String]
    let footer: String
    var emptyHint: String? = nil
    let actions: WealthCardActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: title, addLabel: "加照片", onAdd: { actions.tap(.edit(nil)) })
            VStack(alignment: .leading, spacing: 10) {
                if !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !photos.isEmpty {
                    MultiPhotoGallery(
                        fileNames: .constant(photos),
                        urlFor: { LifeMilestone.photoURL(for: $0) },
                        onSaveImage: { _ in nil },
                        onDeleteFile: { _ in },
                        title: "照片",
                        allowAdding: false
                    )
                } else if let emptyHint {
                    Text(emptyHint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .modifier(FinanceCardChrome())
            Text(footer)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// 連到這張卡／這個帳戶的一列（圖示＋名字＋多久一次＋右邊金額或日期＋›）
struct WealthCardLinkLine: View {
    let row: WealthCardLinkRow
    let pal: TripBoardPalette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: row.icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .background(Color(tb: row.tint), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(row.trailing)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(row.trailingTone?.color(pal) ?? Color.primary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 白卡外的一顆大按鈕（停用這張卡、收起來）
struct WealthCardWideButton: View {
    let title: String
    let tone: MoneyTone
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tone.color(TripBoardPalette(scheme)))
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
        .modifier(FinanceCardChrome())
    }
}

// MARK: - 信用卡頁（§4.1）

/// 信用卡頁 ③–⑨（① 看板、② 要確認在外殼）
struct WealthCreditSections: View {
    let cardId: UUID
    let credit: WealthCardCredit
    let reveal: WealthCardReveal
    let actions: WealthCardActions

    var body: some View {
        VStack(spacing: 22) {
            if let s = credit.statement {
                WealthCardStatementSection(cardId: cardId, block: s, actions: actions)
                    .id(WealthCardAnchor.statement)
            }
            WealthCardUnbilledSection(credit: credit, actions: actions)
                .id(WealthCardAnchor.unbilled)
            if !credit.recurring.isEmpty {
                WealthCardRecurringSection(cardId: cardId, credit: credit, actions: actions)
                    .id(WealthCardAnchor.recurring)
            }
            if !credit.history.isEmpty {
                WealthCardHistorySection(cardId: cardId, credit: credit, actions: actions)
                    .id(WealthCardAnchor.history)
            }
            WealthCardFeeSection(fee: credit.fee, actions: actions)
                .id(WealthCardAnchor.fee)
            WealthCardInfoSection(title: "卡片資料", rows: credit.info, reveal: reveal, actions: actions)
                .id(WealthCardAnchor.cardInfo)
            disableButton
            WealthCardPhotosSection(title: "權益與說明", photos: credit.photos,
                                    footer: "不要拍卡片正反面（完整卡號、安全碼）。拍到像完整卡號的數字會提醒你。",
                                    emptyHint: "權益 DM、帳單說明可以拍起來放這裡（按右上＋）", actions: actions)
                .id(WealthCardAnchor.photos)
        }
    }

    /// 最下紅字「停用這張卡」（不擋；確認框問還在刷它的定期扣款）／停用的「重新啟用」
    @ViewBuilder
    private var disableButton: some View {
        if credit.isDisabled {
            WealthCardWideButton(title: "重新啟用這張卡", tone: .good) {
                actions.setDisabled(false)
            }
        } else {
            WealthCardWideButton(title: "停用這張卡", tone: .bad) {
                actions.confirm(.disableCard(cardId, credit.recurringIds.count))
            }
        }
    }
}

/// ③ 這期帳單：一句大字、〔標成已繳〕〔帳單金額不一樣〕、分類長條＋可點圖例、前 5 筆、註腳
struct WealthCardStatementSection: View {
    let cardId: UUID
    let block: WealthCardStatementBlock
    let actions: WealthCardActions

    @Environment(\.colorScheme) private var scheme
    /// 圖例點了：清單只剩那一類
    @State private var picked: String?

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: block.title, trailing: block.trailing)
            VStack(alignment: .leading, spacing: 0) {
                top(pal)
                    .padding(14)
                if !block.parts.isEmpty {
                    partsView(pal)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
                if !rows.isEmpty {
                    Divider().padding(.leading, 14)
                    WealthCardRowList(rows: rows, moreTitle: "看全部 \(rows.count) 筆", actions: actions, pal: pal)
                        .id(picked ?? "all")
                }
                notes
                    .padding(14)
            }
            .modifier(FinanceCardChrome())
        }
    }

    private var rows: [WealthCardRow] {
        guard let p = picked else { return block.rows }
        return block.rows.filter { $0.category == p }
    }

    private func top(_ pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceLineText.text(block.headline, pal: pal)
                .font(.headline)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let s = block.statedNote {
                statedRow(s, pal: pal)
            }
            if let c = block.carriedNote {
                Text(c)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MoneyTone.warn.color(pal))
            }
            if let p = block.paidLine {
                paidRow(p, pal: pal)
            }
            if block.showButtons {
                buttons(pal)
            }
            if let m = block.minimumNote {
                Text(m)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statedRow(_ text: String, pal: TripBoardPalette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let diff = block.diffAmount {
                // 記在那一期的結帳日（同〔帳單金額不一樣〕表單的〔補記〕）：記成今天會算進下一期，下一期多算一次
                Button {
                    actions.present(.addExpense(cardId, nil, diff, "帳單差額", block.close), true)
                } label: {
                    FinanceGreenPill(title: "補記差額")
                }
                .buttonStyle(MoneyPressStyle())
            }
        }
    }

    private func paidRow(_ text: String, pal: TripBoardPalette) -> some View {
        let key = block.key
        return VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MoneyTone.good.color(pal))
                .fixedSize(horizontal: false, vertical: true)
            if block.canEditPaid || block.canUnpay {
                HStack(spacing: 16) {
                    if block.canEditPaid {
                        Button("改一下 ›") {
                            actions.present(.paid(cardId, key), false)
                        }
                    }
                    if block.canUnpay {
                        Button("取消已繳") {
                            actions.unpay(key)
                        }
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(pal.hint)
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MoneyTone.good.color(pal).opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// 〔標成已繳〕（綠，不擋）〔帳單金額不一樣〕（不擋）；放不下一列就疊起來
    private func buttons(_ pal: TripBoardPalette) -> some View {
        let key = block.key
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                paidButton(key)
                statedButton(key, pal: pal)
            }
            VStack(spacing: 8) {
                paidButton(key)
                statedButton(key, pal: pal)
            }
        }
    }

    private func paidButton(_ key: String) -> some View {
        Button {
            actions.present(.paid(cardId, key), false)
        } label: {
            Label("標成已繳", systemImage: "checkmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(tb: 0x1F9D57), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(MoneyPressStyle())
    }

    private func statedButton(_ key: String, pal: TripBoardPalette) -> some View {
        Button {
            actions.present(.stated(cardId, key), false)
        } label: {
            Text("帳單金額不一樣")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(pal.hint)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(pal.hint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(MoneyPressStyle())
    }

    private func partsView(_ pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FinanceStackBar(parts: barParts, height: 10, pal: pal)
            ChipFlowLayout(spacing: 12) {
                ForEach(block.parts) { p in
                    legend(p, pal: pal)
                }
            }
        }
    }

    private var barParts: [FinanceBarPart] {
        block.parts.map { p in
            let dim = picked != nil && picked != p.name
            return FinanceBarPart(id: p.id, value: p.value, color: p.theme.midColor.opacity(dim ? 0.3 : 1))
        }
    }

    private func legend(_ p: WealthCardPart, pal: TripBoardPalette) -> some View {
        let name = p.name
        let on = picked == name
        return FinanceLegendButton(color: p.theme.midColor, label: on ? "✓ " + name : name, valueText: p.text,
                                   accessibilityLabel: name + " " + p.text,
                                   hint: on ? "點兩下看全部" : "點兩下只看這一類", pal: pal, action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                picked = (picked == name) ? nil : name
            }
        })
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let c = block.closingNote {
                Text(c)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("發票匯入、一按就記的不會算進卡片，可在記帳裡補選付款方式。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// ④ 還沒出帳：「10/13 起刷了 6,200・5 筆」＋清單
struct WealthCardUnbilledSection: View {
    let credit: WealthCardCredit
    let actions: WealthCardActions

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "還沒出帳", trailing: credit.unbilledTrailing)
            VStack(alignment: .leading, spacing: 0) {
                FinanceLineText.text(credit.unbilledHead, pal: pal)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .padding(14)
                if !credit.unbilledRows.isEmpty {
                    Divider().padding(.leading, 14)
                    WealthCardRowList(rows: credit.unbilledRows, moreTitle: "看全部 \(credit.unbilledRows.count) 筆",
                                      actions: actions, pal: pal)
                }
            }
            .modifier(FinanceCardChrome())
        }
    }
}

/// ⑤ 綁在這張卡的定期扣款＋〔一次改到別張卡…〕
struct WealthCardRecurringSection: View {
    let cardId: UUID
    let credit: WealthCardCredit
    let actions: WealthCardActions

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "綁在這張卡的定期扣款", trailing: credit.recurringTrailing)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(credit.recurring.enumerated()), id: \.element.id) { i, r in
                    if i > 0 {
                        Divider().padding(.leading, 52)
                    }
                    Button {
                        actions.open(r.open)
                    } label: {
                        WealthCardLinkLine(row: r, pal: pal)
                    }
                    .buttonStyle(.plain)
                }
                moveButton(pal)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                Text("換卡或停卡時，記得到銀行或商家改扣款卡號。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
            }
            .modifier(FinanceCardChrome())
        }
    }

    private func moveButton(_ pal: TripBoardPalette) -> some View {
        let ids = credit.recurringIds
        let from = cardId
        return Button {
            actions.present(.moveLinks(from, ids, [], true), true)
        } label: {
            Text("一次改到別張卡…")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(pal.hint)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(pal.hint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(MoneyPressStyle())
    }
}

/// ⑥ 每期帳單（MoneyChartCard 主題 72；一期一根、已繳柱頂小勾、要繳那根卡面色、虛線平均；按住看那期）
struct WealthCardHistorySection: View {
    let cardId: UUID
    let credit: WealthCardCredit
    let actions: WealthCardActions

    @Environment(\.colorScheme) private var scheme
    @State private var picked: String?

    var body: some View {
        MoneyChartCard(theme: .wealthCardTrends, title: "每期帳單", trailing: "近 \(credit.history.count) 期",
                       content: AnyView(chartBlock))
    }

    private var tint: Color { WealthCardPalette.tint(credit.faceColor) }

    /// 按住的那一根；沒按住＝最近一期（〔帳單金額不一樣〕用）
    private var selected: WealthCardHistoryBar? {
        if let p = picked, let b = credit.history.first(where: { $0.key == p }) { return b }
        return credit.history.last
    }

    private var chartBlock: some View {
        let pal = TripBoardPalette(scheme)
        return VStack(alignment: .leading, spacing: 10) {
            bubble(pal)
            WealthCardHistoryChart(bars: credit.history, average: credit.historyAverage,
                                   averageText: credit.historyAverageText, tint: tint,
                                   summary: credit.historySummary, picked: $picked)
            legend(pal)
            selectedRow(pal)
        }
        .padding(.horizontal, 16)
    }

    private func bubble(_ pal: TripBoardPalette) -> some View {
        let text: String = picked.flatMap { p in credit.history.first(where: { $0.key == p })?.bubble }
            ?? "按住一根看那一期"
        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(picked == nil ? pal.label : pal.ink)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    }

    private func legend(_ pal: TripBoardPalette) -> some View {
        ChipFlowLayout(spacing: 12) {
            MoneyLegendItem(mark: .swatch, color: tint.opacity(0.45), text: "已繳（柱頂 ✓）", pal: pal)
            MoneyLegendItem(mark: .swatch, color: tint, text: "這期要繳", pal: pal)
            MoneyLegendItem(mark: .dash, color: Color.orange, text: credit.historyAverageText, pal: pal)
        }
    }

    @ViewBuilder
    private func selectedRow(_ pal: TripBoardPalette) -> some View {
        if let b = selected {
            let key = b.key
            HStack(spacing: 8) {
                Text(b.bubble)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Button("帳單金額不一樣") {
                    actions.present(.stated(cardId, key), false)
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(pal.hint)
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
    }
}

/// 每期帳單的圖（Swift Charts，高 170；chartXSelection 是 iOS 17）。整張圖一個 VoiceOver 元素
private struct WealthCardHistoryChart: View {
    let bars: [WealthCardHistoryBar]
    let average: Double
    let averageText: String
    let tint: Color
    let summary: String
    @Binding var picked: String?

    var body: some View {
        plot
            .chartXSelection(value: $picked)
            .frame(height: 170)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
    }

    private var plot: some View {
        Chart {
            ForEach(bars) { b in
                bar(b)
            }
            if average > 0.5 {
                averageRule
            }
        }
        .chartXAxis {
            AxisMarks(values: bars.map(\.key)) { value in
                AxisValueLabel {
                    if let k = value.as(String.self) {
                        Text(axisText(k))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(yText(v))
                            .font(.caption2)
                    }
                }
            }
        }
    }

    @ChartContentBuilder
    private func bar(_ b: WealthCardHistoryBar) -> some ChartContent {
        BarMark(x: .value("期", b.key), y: .value("帳單", b.amount), width: .ratio(0.6))
            .foregroundStyle(tint.opacity(opacity(b)))
            .cornerRadius(3)
            .annotation(position: .top, spacing: 2) {
                if b.paid {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(tint)
                }
            }
    }

    private var averageRule: some ChartContent {
        RuleMark(y: .value("平均", average))
            .foregroundStyle(Color.orange)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .annotation(position: .top, alignment: .leading, spacing: 2) {
                Text(averageText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.orange)
            }
    }

    /// 要繳那根卡面色、其他淡色；按住一根時其他的再淡一點
    private func opacity(_ b: WealthCardHistoryBar) -> Double {
        let base = b.due ? 1.0 : 0.45
        guard let p = picked else { return base }
        return p == b.key ? 1.0 : base * 0.5
    }

    private func axisText(_ key: String) -> String {
        bars.first(where: { $0.key == key })?.axis ?? ""
    }

    /// 「4萬」「2萬」「0」；遮住時平均那行已經是 ••••，軸上的字也不寫
    private func yText(_ v: Double) -> String {
        if averageText.contains("••••") { return "" }
        return WealthPageText.wan(v)
    }
}

/// ⑦ 年費與回饋小抄（都沒填：一列「＋ 記年費條件和回饋」→ 編輯）
struct WealthCardFeeSection: View {
    let fee: WealthCardFee
    let actions: WealthCardActions

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "年費與回饋小抄")
            if fee.isEmpty {
                emptyRow(pal)
            } else {
                FinanceInfoRows(rows: rows(pal))
                    .modifier(FinanceCardChrome())
            }
        }
    }

    private func emptyRow(_ pal: TripBoardPalette) -> some View {
        Button {
            actions.tap(.edit(nil))
        } label: {
            Text("＋ 記年費條件和回饋")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(pal.hint)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
        .modifier(FinanceCardChrome())
    }

    private func rows(_ pal: TripBoardPalette) -> [FinanceInfoRows.Row] {
        var out: [FinanceInfoRows.Row] = []
        if let a = fee.annualFee {
            out.append(FinanceInfoRows.Row(id: "fee", content: AnyView(FinanceInfoRow(label: "年費", value: Text(a)))))
        }
        if let t = fee.waiveTitle {
            out.append(FinanceInfoRows.Row(id: "waive", content: AnyView(waiveRow(t, pal: pal))))
        }
        if let p = fee.perks {
            out.append(FinanceInfoRows.Row(id: "perks", content: AnyView(perksRow(p, pal: pal))))
        }
        return out
    }

    private func waiveRow(_ title: String, pal: TripBoardPalette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("免年費")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                if let d = fee.waiveDetail {
                    Text(d)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(fee.waiveDone ? MoneyTone.good.color(pal) : Color.secondary)
                        .multilineTextAlignment(.trailing)
                }
                if !fee.waiveDone {
                    FinanceThinBar(fraction: fee.waiveFraction, color: Color(tb: 0xF0A23A), track: pal.progressTrack)
                        .frame(maxWidth: 180)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private func perksRow(_ text: String, pal: TripBoardPalette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("回饋小抄")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                Text("你自己寫的一段字，App 不估回饋")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 銀行帳戶頁（§4.2）

/// 銀行帳戶頁 ③–⑨
struct WealthBankSections: View {
    let accountId: UUID
    let bank: WealthCardBank
    let codes: [String]
    let reveal: WealthCardReveal
    let isPremium: Bool
    let masked: Bool
    let actions: WealthCardActions

    var body: some View {
        VStack(spacing: 22) {
            WealthCardUpcomingSection(bank: bank, actions: actions)
                .id(WealthCardAnchor.upcoming)
            if !bank.linkedOut.isEmpty || !bank.linkedIn.isEmpty {
                WealthCardLinkedSection(accountId: accountId, bank: bank, actions: actions)
                    .id(WealthCardAnchor.linked)
            }
            if !bank.foreign.isEmpty {
                WealthCardForeignSection(tiles: bank.foreign, note: bank.foreignNote, canExchange: bank.canExchange,
                                         actions: actions, accountId: accountId)
                    .id(WealthCardAnchor.foreign)
            }
            // [v25.566] ⑥ 定存（有格子、舊定存帳戶要補資料、或可以新增時出現）
            if showsDeposits {
                WealthCardDepositsSection(accountId: accountId, bank: bank, actions: actions)
                    .id(WealthCardAnchor.deposits)
            }
            WealthCardLedgerSection(accountId: accountId, bank: bank, codes: codes, isPremium: isPremium,
                                    masked: masked, actions: actions)
                .id(WealthCardAnchor.ledger)
            WealthCardInfoSection(title: "帳戶資料", rows: bank.info, reveal: reveal, actions: actions)
                .id(WealthCardAnchor.accountInfo)
            hideButton
            WealthCardPhotosSection(title: "備註與照片", note: bank.note, photos: bank.photos,
                                    footer: "別拍到完整帳號和密碼。照片不會加密。",
                                    emptyHint: bank.note.isEmpty ? "存摺封面、約定轉帳設定可以拍起來放這裡（按右上＋）" : nil,
                                    actions: actions)
                .id(WealthCardAnchor.note)
        }
    }

    /// [v25.566] ⑥ 定存要不要出現
    private var showsDeposits: Bool {
        !bank.deposits.isEmpty || bank.legacyDepositPrompt || bank.canAddDeposit
    }

    /// 最下紅字「收起來（銷戶）」：存摺上還有錢先問要轉到哪；收起來的顯示「重新打開」
    @ViewBuilder
    private var hideButton: some View {
        if bank.hidden {
            WealthCardWideButton(title: "重新打開", tone: .good) {
                actions.setHidden(false)
            }
        } else {
            WealthCardWideButton(title: "收起來（銷戶）", tone: .bad) {
                actions.confirm(.hideAccount(accountId, bank.leftover))
            }
        }
    }
}

/// ③ 接下來 30 天（先 5 筆；日期塊＋一句＋金額＋扣完剩）
struct WealthCardUpcomingSection: View {
    let bank: WealthCardBank
    let actions: WealthCardActions

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "接下來 30 天", trailing: bank.upcomingTrailing)
            Group {
                if bank.upcoming.isEmpty {
                    Text("接下來 30 天沒有會動到這個帳戶的事")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                } else {
                    WealthCardRowList(rows: bank.upcoming, moreTitle: "看全部 \(bank.upcoming.count) 件",
                                      actions: actions, pal: pal)
                }
            }
            .modifier(FinanceCardChrome())
        }
    }
}

/// ④ 連到這個帳戶的（從這裡扣／入這裡；長按固定支出、收入〔改到別的帳戶…〕）
struct WealthCardLinkedSection: View {
    let accountId: UUID
    let bank: WealthCardBank
    let actions: WealthCardActions

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "連到這個帳戶的", trailing: bank.linkedTrailing)
            VStack(alignment: .leading, spacing: 0) {
                if !bank.linkedOut.isEmpty {
                    groupTitle("從這裡扣", pal: pal)
                    lines(bank.linkedOut, pal: pal)
                }
                if !bank.linkedIn.isEmpty {
                    groupTitle("入這裡", pal: pal)
                    lines(bank.linkedIn, pal: pal)
                }
            }
            .padding(.bottom, 6)
            .modifier(FinanceCardChrome())
            Text("刪除或收起來前看這裡，就知道會影響什麼。長按扣款、收入可以改到別的帳戶。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func groupTitle(_ t: String, pal: TripBoardPalette) -> some View {
        Text(t)
            .font(.caption.weight(.heavy))
            .foregroundStyle(pal.label)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }

    private func lines(_ rows: [WealthCardLinkRow], pal: TripBoardPalette) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                if i > 0 {
                    Divider().padding(.leading, 52)
                }
                line(r, pal: pal)
            }
        }
    }

    private func line(_ r: WealthCardLinkRow, pal: TripBoardPalette) -> some View {
        let canMove = r.moveExpenseId != nil || r.moveIncomeId != nil
        let expenseIds: [UUID] = r.moveExpenseId.map { [$0] } ?? []
        let incomeIds: [UUID] = r.moveIncomeId.map { [$0] } ?? []
        let from = accountId
        return Button {
            actions.open(r.open)
        } label: {
            WealthCardLinkLine(row: r, pal: pal)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if canMove {
                Button {
                    actions.present(.moveLinks(from, expenseIds, incomeIds, false), true)
                } label: {
                    Label("改到別的帳戶…", systemImage: "arrow.left.arrow.right")
                }
            }
            Button {
                actions.open(r.open)
            } label: {
                Label("打開", systemImage: "square.and.pencil")
            }
        }
    }
}

/// ⑤ 外幣（[v25.566] 有外幣就有）：一格一個幣別「美金　US$3,200.00　約 NT$102,400（10/19 匯率 32.0）」；
/// 格子下一行說明、〔＋ 換匯〕（要訂閱：WealthCardPage.present 擋）
struct WealthCardForeignSection: View {
    let tiles: [WealthCardFTile]
    var note: String? = nil
    var canExchange = false
    let actions: WealthCardActions
    let accountId: UUID

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "外幣")
            VStack(alignment: .leading, spacing: 10) {
                FinanceTileGrid(tiles: tiles, pal: pal)
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if canExchange {
                    exchangeButton(pal)
                }
            }
            .padding(12)
            .modifier(FinanceCardChrome())
        }
    }

    private func exchangeButton(_ pal: TripBoardPalette) -> some View {
        let a = actions
        let id = accountId
        return Button {
            a.present(.exchange(id), true)
        } label: {
            Label("換匯", systemImage: "plus")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MoneyTone.good.color(pal))
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityLabel("換匯")
    }
}

/// ⑥ [v25.566] 定存（judge §4.2 ⑥）：一期一格（FinanceProgressCell：過去那段、今天一顆點、右端「3/15 到期」），點了開那一期的
/// 定存表單；舊的「定存」種類帳戶還沒補任何一期＝一列〔補上利率和到期日 ›〕；最下〔＋ 定存〕。新增、看、改都要訂閱（present 擋）
struct WealthCardDepositsSection: View {
    let accountId: UUID
    let bank: WealthCardBank
    let actions: WealthCardActions

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "定存", trailing: bank.depositsTrailing)
            if bank.legacyDepositPrompt {
                legacyRow(pal)
            }
            ForEach(bank.deposits) { cell in
                depositButton(cell, pal: pal)
            }
            // 舊定存帳戶已經有〔補上利率和到期日 ›〕（開同一張表單）：不再多一顆〔＋ 定存〕
            if bank.canAddDeposit && !bank.legacyDepositPrompt {
                addRow(pal)
            }
            if !bank.deposits.isEmpty {
                Text(Self.footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static let footnote = "利息是預估（單利、未扣稅），以銀行入帳為準；到期本息續存會自動接下一期。"
    static let legacyTitle = "這個帳戶是以前記的定存：補上利率和到期日"
    static let legacyDetail = "補了就能算利息、到期前 7 天提醒你；存款合計不會多算。"

    /// 一格（整格一顆按鈕；VoiceOver 念 FinanceProgressCell 的標題＋資料端組好的一句）
    private func depositButton(_ cell: WealthCardDepositCell, pal: TripBoardPalette) -> some View {
        let a = actions
        let id = cell.id
        let hint = cell.waiting ? "到期了，點兩下決定轉活存還是續存" : "點兩下打開這筆定存"
        return Button {
            a.open(.timeDeposit(id))
        } label: {
            FinanceProgressCell(p: cell.progress, pal: pal, tappable: true)
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityHint(hint)
    }

    /// 〔補上利率和到期日 ›〕（舊的「定存」種類帳戶）
    private func legacyRow(_ pal: TripBoardPalette) -> some View {
        let a = actions
        let id = accountId
        return Button {
            a.present(.timeDeposit(id, nil), true)
        } label: {
            legacyLabel(pal)
        }
        .buttonStyle(MoneyPressStyle())
        .modifier(FinanceCardChrome())
    }

    private func legacyLabel(_ pal: TripBoardPalette) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .background(Color(tb: 0xA86A00), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.legacyTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.legacyDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// 最下〔＋ 定存〕
    private func addRow(_ pal: TripBoardPalette) -> some View {
        let a = actions
        let id = accountId
        return Button {
            a.present(.timeDeposit(id, nil), true)
        } label: {
            Label("定存", systemImage: "plus")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MoneyTone.good.color(pal))
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
        .modifier(FinanceCardChrome())
        .accessibilityLabel("新增定存")
    }
}

/// ⑦ 存摺明細：今年進來／出去／利息；紀錄・N 筆＋〔＋ 記一筆〕＋篩選＋月份頭＋每列餘額（先 3 個月）
struct WealthCardLedgerSection: View {
    let accountId: UUID
    let bank: WealthCardBank
    let codes: [String]
    let isPremium: Bool
    let masked: Bool
    let actions: WealthCardActions

    @Environment(\.colorScheme) private var scheme
    @State private var filter: WealthLedgerFilter = .all
    @State private var months = 3

    /// 一個月的一組
    fileprivate struct MonthGroup: Identifiable {
        let key: String
        let title: String
        let totals: String
        let rows: [WealthCardRow]
        var id: String { key }
    }

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "存摺明細")
            FinanceTileGrid(tiles: bank.yearTiles, pal: pal)
                .padding(12)
                .modifier(FinanceCardChrome())
            records(pal)
        }
    }

    private func records(_ pal: TripBoardPalette) -> some View {
        let all = groups
        let shown = Array(all.prefix(months))
        return VStack(alignment: .leading, spacing: 0) {
            recordsTop
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)
            if bank.filters.count > 2 {
                filterRow(pal)
                    .padding(.bottom, 4)
            }
            if all.isEmpty {
                Text(bank.ledger.isEmpty ? "還沒有紀錄：記一筆存款或對一次存摺就從這裡開始算" : "這一類沒有紀錄")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(14)
            }
            ForEach(shown) { g in
                monthHeader(g, pal: pal)
                WealthCardRowList(rows: g.rows, limit: 50, moreTitle: "看這個月全部 \(g.rows.count) 筆",
                                  actions: actions, pal: pal)
            }
            if all.count > months {
                moreMonths(pal)
            }
        }
        .modifier(FinanceCardChrome())
    }

    /// 「再看 3 個月」（上面一條細線）
    private func moreMonths(_ pal: TripBoardPalette) -> some View {
        VStack(spacing: 0) {
            Divider().padding(.leading, 14)
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { months += 3 }
            } label: {
                Text("再看 3 個月")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pal.hint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var recordsTop: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(bank.recordsTitle)
                .font(.headline)
            Spacer(minLength: 8)
            FinanceAddMenuPill(canEdit: isPremium, askPremium: { actions.askPremium() }) {
                WealthBankAddItems(accountId: accountId, codes: codes, actions: actions, accountHidden: bank.hidden)
            }
        }
    }

    private func filterRow(_ pal: TripBoardPalette) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(bank.filters) { f in
                    FinanceFilterChip(text: f.title, on: filter == f, pal: pal) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            filter = f
                            months = 3
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func monthHeader(_ g: MonthGroup, pal: TripBoardPalette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(g.title)
            Spacer(minLength: 8)
            Text(g.totals)
                .monospacedDigit()
        }
        .font(.footnote.weight(.heavy))
        .foregroundStyle(pal.label)
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// 照篩選切好、依月份分組（明細本來就新到舊）
    private var groups: [MonthGroup] {
        let rows: [WealthCardRow] = filter == .all ? bank.ledger : bank.ledger.filter { $0.filter == filter }
        var out: [MonthGroup] = []
        var current: [WealthCardRow] = []
        var key = ""
        for r in rows {
            if r.monthKey != key {
                if !current.isEmpty { out.append(group(key, current)) }
                key = r.monthKey
                current = []
            }
            current.append(r)
        }
        if !current.isEmpty { out.append(group(key, current)) }
        return out
    }

    /// 「10 月・5 筆」＋「+80,000／−25,799」（只加這個帳戶的主要幣別；好幾個幣別時只加台幣）
    private func group(_ key: String, _ rows: [WealthCardRow]) -> MonthGroup {
        let parts = key.split(separator: "-")
        let year = parts.first.flatMap { Int($0) } ?? 0
        let month = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        let thisYear = WealthCal.calendar.component(.year, from: Date())
        let head = (year == thisYear ? "" : "\(year) 年 ") + "\(month) 月・\(rows.count) 筆"
        let code = bank.primaryCode
        let same = rows.filter { $0.code == code && $0.filter != .anchor }
        let ins = same.filter { $0.signedValue > 0 }.reduce(0.0) { $0 + $1.signedValue }
        let outs = same.filter { $0.signedValue < 0 }.reduce(0.0) { $0 - $1.signedValue }
        var totals = ""
        if masked {
            totals = WealthCardText.dots
        } else if ins > 0.004 || outs > 0.004 {
            totals = "+" + WealthFormat.plain(ins, code: code) + "／−" + WealthFormat.plain(outs, code: code)
        }
        return MonthGroup(key: key, title: head, totals: totals, rows: rows)
    }
}

// MARK: - 證券戶頁（§4.3；[v25.567] ② 要交割、⑤ 以前記在這裡的交割紀錄）

/// 證券戶：② 要交割、③ 持股（緊湊項目卡，點了彈那檔的 StockDetailView）、⑤ 以前記在這裡的交割紀錄、⑥ 資料。
/// 沒有記一筆、轉帳、對存摺（④ 要確認 #16 在外殼的要確認區）
struct WealthBrokerSections: View {
    let brokerId: UUID
    let broker: WealthCardBroker
    let reveal: WealthCardReveal
    let actions: WealthCardActions

    var body: some View {
        VStack(spacing: 22) {
            if !broker.dues.isEmpty {
                WealthCardBrokerDuesSection(dues: broker.dues, actions: actions)
                    .id(WealthCardAnchor.dues)
            }
            if !broker.holdings.isEmpty {
                holdings
                    .id(WealthCardAnchor.holdings)
            }
            if broker.legacyTitle != nil {
                WealthCardLegacySection(brokerId: brokerId, broker: broker, actions: actions)
                    .id(WealthCardAnchor.legacy)
            }
            WealthCardInfoSection(title: "資料", rows: broker.info, reveal: reveal, actions: actions)
                .id(WealthCardAnchor.accountInfo)
            if !broker.note.isEmpty || !broker.photos.isEmpty {
                WealthCardPhotosSection(title: "備註與照片", note: broker.note, photos: broker.photos,
                                        footer: "別拍到完整帳號和密碼。照片不會加密。", actions: actions)
                    .id(WealthCardAnchor.note)
            }
        }
    }

    private var holdings: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "持股", trailing: "\(broker.holdings.count) 檔")
            ForEach(broker.holdings, id: \.id) { item in
                Button {
                    actions.open(.stock(item.id))
                } label: {
                    MoneyItemCard(item: item, compact: true)
                }
                .buttonStyle(MoneyPressStyle())
            }
            Text("買賣、股利在理財 › 股票記，這裡只看。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// ② [v25.567] 要交割（judge §4.3 ②；樣稿③-B5）：一天一列「10/21（三）早上從薪轉扣 52,340・買 00878 2,000 股」＋
/// 「薪轉現在 128,400，夠」；點一列打開那檔股票（看的，不擋）；不夠的那天多一顆綠字〔轉帳過去〕（要訂閱：present 擋）
struct WealthCardBrokerDuesSection: View {
    let dues: [WealthCardBrokerDue]
    let actions: WealthCardActions

    @Environment(\.colorScheme) private var scheme

    static let footnote = "讀交割銀行接下來 30 天的存摺；同一天的買賣先相抵，交割日早上 10 點前帳戶裡要有錢。"

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "要交割", trailing: "\(dues.count) 筆")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(dues.enumerated()), id: \.element.id) { i, d in
                    if i > 0 {
                        Divider().padding(.leading, 52)
                    }
                    WealthCardBrokerDueLine(due: d, actions: actions, pal: pal)
                }
            }
            .modifier(FinanceCardChrome())
            Text(Self.footnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 要交割的一列：一顆按鈕打開那檔股票；不夠的那天下面另一顆〔轉帳過去〕（兩顆分開，不疊在一起）
struct WealthCardBrokerDueLine: View {
    let due: WealthCardBrokerDue
    let actions: WealthCardActions
    let pal: TripBoardPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowButton
            if due.isShort && due.transferTo != nil {
                transferButton
            }
        }
        .background(rowFill)
    }

    private var rowFill: Color {
        due.isShort ? MoneyTone.warn.color(pal).opacity(0.08) : Color.clear
    }

    private var statusColor: Color {
        due.isShort ? MoneyTone.warn.color(pal) : Color.secondary
    }

    private var iconName: String {
        due.isOutflow ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill"
    }

    /// 不夠 warn；扣款紫（同明細的交割）；入帳綠
    private var iconColor: Color {
        if due.isShort { return MoneyTone.warn.color(pal) }
        return due.isOutflow ? Color(tb: 0x6B44E0) : MoneyTone.good.color(pal)
    }

    private var rowHint: String {
        due.stockId == nil ? "" : "點兩下打開那檔股票"
    }

    private var rowButton: some View {
        let a = actions
        let sid = due.stockId
        return Button {
            if let sid { a.open(.stock(sid)) }
        } label: {
            rowLabel
        }
        .buttonStyle(.plain)
        .disabled(sid == nil)
        .accessibilityLabel(due.accessibilityText)
        .accessibilityHint(rowHint)
    }

    private var rowLabel: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            texts
            Spacer(minLength: 6)
            chevron
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(due.line)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text(due.status)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(statusColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var chevron: some View {
        if due.stockId != nil {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
    }

    /// 〔轉帳過去〕：到交割銀行、差多少先填好（從哪轉在表單裡選；要訂閱）
    private var transferButton: some View {
        let a = actions
        let to = due.transferTo
        let amount = due.transferAmount
        return Button {
            if let to { a.present(.transferTo(to, amount), true) }
        } label: {
            Label("轉帳過去", systemImage: "arrow.right.circle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MoneyTone.good.color(pal))
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .padding(.leading, 52)
                .padding(.trailing, 14)
                .padding(.bottom, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityHint(transferHint)
    }

    /// 台幣的差額先填好；外幣的不填（轉帳表單的金額是轉出那邊的幣別）
    private var transferHint: String {
        due.transferAmount > 0 ? "點兩下打開轉帳，差多少已經填好" : "點兩下打開轉帳，交割銀行已經選好"
    }
}

/// ⑤ [v25.567] 以前記在這裡的交割紀錄（judge §4.3 ⑤）：收成一列「以前記在這裡的交割紀錄 18 筆 ›」，點了展開唯讀明細
///（徽章買入／賣出／股利，不寫餘額、點了不開）；有交割銀行時標題右邊綠字〔搬到薪轉〕（WealthSettlementMoveSheet：先給你看
/// 會動到哪些，你按確定才搬；不擋訂閱，修資料同〔改過來〕）；灰字「不算進任何合計」
struct WealthCardLegacySection: View {
    let brokerId: UUID
    let broker: WealthCardBroker
    let actions: WealthCardActions

    @Environment(\.colorScheme) private var scheme
    @State private var expanded = false

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            header(pal)
            VStack(alignment: .leading, spacing: 0) {
                toggleRow
                if expanded {
                    expandedList(pal)
                }
            }
            .modifier(FinanceCardChrome())
            if let note = broker.legacyNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func header(_ pal: TripBoardPalette) -> some View {
        HStack(alignment: .center, spacing: 10) {
            FinanceCardHeader(title: "舊交割紀錄")
            if broker.canMoveLegacy {
                moveButton(pal)
            }
        }
    }

    private func moveButton(_ pal: TripBoardPalette) -> some View {
        let a = actions
        let id = brokerId
        return Button {
            a.present(.settlementMove(id), false)
        } label: {
            Text(broker.legacyMoveTitle)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MoneyTone.good.color(pal))
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityHint("點兩下先看會動到哪些紀錄")
    }

    private var toggleRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
        } label: {
            toggleLabel
        }
        .buttonStyle(.plain)
        .accessibilityHint(toggleHint)
    }

    private var toggleHint: String {
        expanded ? "點兩下收起來" : "點兩下展開"
    }

    private var toggleLabel: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "tray.full")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .background(Color(tb: 0x6B44E0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            Text(broker.legacyTitle ?? "")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    static let farAway = "這些紀錄的日子太遠，明細列不出來；搬的時候照樣會列在清單裡。"

    @ViewBuilder
    private func expandedList(_ pal: TripBoardPalette) -> some View {
        Divider().padding(.leading, 14)
        if broker.legacyRows.isEmpty {
            Text(Self.farAway)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
        } else {
            WealthCardRowList(rows: broker.legacyRows, limit: 8, moreTitle: "看全部 \(broker.legacyRows.count) 筆",
                              actions: actions, pal: pal)
        }
    }
}

// MARK: - 保單頁（§4.4；[v25.567] 踏腳石、繳費＝記帳那一筆、誰的保單）

/// 保單：③ 保障內容（＋⑥ 醫療地圖一行）、④ 繳費、⑤ 誰的保單、⑦ 資料、⑧ 照片
struct WealthPolicySections: View {
    let policyId: UUID
    let policy: WealthCardPolicy
    let isPremium: Bool
    let reveal: WealthCardReveal
    let actions: WealthCardActions

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(spacing: 22) {
            coverage(pal)
            WealthCardPolicyPaymentSection(policyId: policyId, policy: policy, isPremium: isPremium, actions: actions)
                .id(WealthCardAnchor.payment)
            people(pal)
            WealthCardInfoSection(title: "資料", rows: policy.info, reveal: reveal, actions: actions)
                .id(WealthCardAnchor.accountInfo)
            WealthCardPhotosSection(title: "保單照片", note: policy.note, photos: policy.photos,
                                    footer: "保單首頁、條款可以拍起來放這裡；別拍到身分證字號。", actions: actions)
                .id(WealthCardAnchor.photos)
        }
    }

    /// 白卡裡一行灰綠字的按鈕（沒寫保障內容、沒寫誰的保單：打開編輯）
    private func hintButton(_ title: String, pal: TripBoardPalette) -> some View {
        let a = actions
        return Button {
            a.tap(.edit(nil))
        } label: {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(pal.hint)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
        .modifier(FinanceCardChrome())
    }

    private func coverage(_ pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "保障內容")
            if policy.coverage.isEmpty {
                hintButton("寫下保障內容，醫療地圖就看得到 ›", pal: pal)
            } else {
                coverageList
            }
            if let m = policy.medicalNote {
                Text(m)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var coverageList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(policy.coverage.enumerated()), id: \.offset) { i, item in
                if i > 0 {
                    Divider().padding(.leading, 14)
                }
                Text(item)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
            }
        }
        .modifier(FinanceCardChrome())
    }

    /// ⑤ 誰的保單：要保人・被保險人・受益人（一列一個人）；都沒寫一行〔寫下要保人、被保險人、受益人 ›〕
    @ViewBuilder
    private func people(_ pal: TripBoardPalette) -> some View {
        if policy.peopleRows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                FinanceCardHeader(title: "誰的保單")
                hintButton("寫下要保人、被保險人、受益人 ›", pal: pal)
            }
        } else {
            WealthCardInfoSection(title: "誰的保單", rows: policy.peopleRows, reveal: reveal, actions: actions)
        }
    }
}

/// ④ [v25.567] 繳費（judge §4.4 ④：記帳的那一筆）：連著＝整塊點了開記帳那一筆（記帳不擋）＋灰字「在這裡改＝改記帳那一筆…」；
/// 沒連＝你填的保費＋〔連到記帳的保費〕（要訂閱）〔新建一筆〕（有記帳週期才有；要訂閱 → 確認框）；沒填保費＝「填保費 ›」
struct WealthCardPolicyPaymentSection: View {
    let policyId: UUID
    let policy: WealthCardPolicy
    let isPremium: Bool
    let actions: WealthCardActions

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "繳費", trailing: policy.linked ? "記帳那一筆" : nil)
            card(pal)
            if let n = policy.paymentNote {
                Text(n)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func card(_ pal: TripBoardPalette) -> some View {
        if policy.linked {
            linkedCard
        } else {
            unlinkedCard(pal)
        }
    }

    /// 連著：整塊一顆按鈕（打開記帳那一筆；記帳本來就不用訂閱）
    private var linkedCard: some View {
        let a = actions
        let eid = policy.paymentExpenseId
        return Button {
            if let eid { a.open(.expense(eid)) }
        } label: {
            linkedLabel
        }
        .buttonStyle(MoneyPressStyle())
        .modifier(FinanceCardChrome())
        .accessibilityHint("點兩下打開記帳那一筆")
    }

    private var linkedLabel: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(policy.payment ?? "")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    /// 沒連：你填的保費（或〔填保費 ›〕）＋下面一列兩顆按鈕
    private func unlinkedCard(_ pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let p = policy.payment {
                Text(p)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
            } else {
                fillPremiumRow(pal)
            }
            Divider().padding(.leading, 14)
            buttons(pal)
        }
        .modifier(FinanceCardChrome())
    }

    /// 沒填保費：〔填保費 ›〕打開編輯、捲到保費那一段（要訂閱：卡片頁擋）
    private func fillPremiumRow(_ pal: TripBoardPalette) -> some View {
        let a = actions
        return Button {
            a.tap(.edit(.premium))
        } label: {
            Text("填保費 ›")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(pal.hint)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
    }

    /// 〔連到記帳的保費〕〔新建一筆〕（一列最多兩顆）
    private func buttons(_ pal: TripBoardPalette) -> some View {
        HStack(spacing: 0) {
            linkButton(pal)
            if policy.canCreateExpense {
                Divider().frame(height: 28)
                createButton(pal)
            }
        }
    }

    private func linkButton(_ pal: TripBoardPalette) -> some View {
        let a = actions
        let id = policyId
        return Button {
            a.present(.policyLink(id), true)
        } label: {
            buttonLabel("連到記帳的保費", icon: "link", pal: pal)
        }
        .buttonStyle(MoneyPressStyle())
    }

    /// 〔新建一筆〕：沒訂閱跳付費說明；有訂閱先問（確認框的字是資料端組好的那一句）
    private func createButton(_ pal: TripBoardPalette) -> some View {
        let a = actions
        let id = policyId
        let premium = isPremium
        return Button {
            if premium {
                a.confirm(.createPolicyExpense(id))
            } else {
                a.askPremium()
            }
        } label: {
            buttonLabel("新建一筆", icon: "plus", pal: pal)
        }
        .buttonStyle(MoneyPressStyle())
    }

    private func buttonLabel(_ title: String, icon: String, pal: TripBoardPalette) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(MoneyTone.good.color(pal))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(Rectangle())
    }
}
