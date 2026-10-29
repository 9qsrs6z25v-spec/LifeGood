import SwiftUI

// MARK: - [v25.567] 財富 v6 的連動小表單（wealth/judge.md §4.3 ④⑥、§4.4 ④、§5.4、§6.3；build/v6/brief.md）
//
// 這個檔放「財富跟別頁連起來」的小零件，給財富的表單、卡片頁和理財的表單共用：
// • WealthPayFromMenu：「從哪扣」選單（同記帳的扣款選單：銀行讀存摺上、卡讀還能刷；收起來的帳戶、停用的卡不列；
//   外幣保單只列那個幣別的子帳戶和信用卡）。保單表單、儲蓄險表單、改扣款小表單都用它。（主控寫好）
// • WealthPayFromSheet：改一筆記帳固定支出從哪扣（房屋卡、車子卡的貸款列「從哪扣」點了開；從下一期起／以前的也改）。
// • WealthLoanPayFromSection：房屋卡、車子卡貸款下面那一段「從哪扣：國泰世華 房貸扣款 ›」（一筆貸款一列，點了開上面那張）。
// • WealthSettlementMoveSheet：證券戶舊交割搬家，搬之前先給你看會動到哪些（#16〔搬到薪轉〕、證券戶頁 ④）。
// • WealthPolicyLinkSheet：保單頁〔連到記帳的保費〕：從記帳裡還沒連保單的保費選一筆連起來。
// 規矩（judge §2.4）：一律 .sheet(item:)＋.appStores()；先 dismiss、下一個 runloop 才寫 store（store 先抓進區域常數）；
// 數字一律讀 LifeStore.wealthFacts（快取）；body 不寫長運算式。

/// 從哪扣：銀行（＋幣別）或信用卡（卡優先）；都沒有＝沒選
struct WealthPayFromChoice: Equatable {
    var bankId: UUID? = nil
    var bankCode: String = "NT$"
    var cardId: UUID? = nil

    var isEmpty: Bool { bankId == nil && cardId == nil }

    /// 記帳那一筆現在從哪扣（有卡＝卡；不然銀行＋幣別）
    static func of(_ e: Expense) -> WealthPayFromChoice {
        if let c = e.linkedCreditCardMilestoneId { return WealthPayFromChoice(bankId: nil, bankCode: "NT$", cardId: c) }
        return WealthPayFromChoice(bankId: e.linkedBankMilestoneId, bankCode: e.linkedBankCurrency ?? "NT$", cardId: nil)
    }
}

/// 「從哪扣」一列＋選單（Form 裡用；跟記帳表單的扣款選單同一套字）。
/// onlyCode：外幣保單只列有這個幣別的子帳戶（「玉山 · 美金」）和信用卡；nil＝全部
struct WealthPayFromMenu: View {
    @Binding var choice: WealthPayFromChoice
    var onlyCode: String? = nil
    var allowNone: Bool = true
    var title: String = "從哪扣"

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore

    var body: some View {
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        return HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            Menu {
                menuItems(facts)
            } label: {
                menuLabel(facts)
            }
        }
    }

    private func menuLabel(_ facts: WealthFacts) -> some View {
        HStack(spacing: 4) {
            Text(labelText(facts))
                .foregroundStyle(choice.isEmpty ? Color.secondary : Color.primary)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func menuItems(_ facts: WealthFacts) -> some View {
        if allowNone {
            Button("沒填") { choice = WealthPayFromChoice() }
        }
        bankSection(banks(facts))
        cardSection(facts.pickerCards)
    }

    @ViewBuilder
    private func bankSection(_ list: [WealthFacts.Account]) -> some View {
        if !list.isEmpty {
            Section("銀行") {
                ForEach(list) { a in
                    bankRow(a)
                }
            }
        }
    }

    @ViewBuilder
    private func cardSection(_ list: [WealthFacts.Card]) -> some View {
        if !list.isEmpty {
            Section("信用卡") {
                ForEach(list) { c in
                    Button(cardLabel(c)) {
                        choice = WealthPayFromChoice(bankId: nil, bankCode: "NT$", cardId: c.id)
                    }
                }
            }
        }
    }

    /// 銀行一列：好幾個幣別是子選單「美金（存摺 美金 3,200）」；一個幣別直接一顆
    @ViewBuilder
    private func bankRow(_ a: WealthFacts.Account) -> some View {
        let list: [String] = codes(of: a)
        if list.count > 1 {
            Menu(a.pickerLabel) {
                ForEach(list, id: \.self) { code in
                    Button(a.pickerLabel(code: code)) { pick(a.id, code: code) }
                }
            }
        } else {
            Button(singleLabel(a, code: list.first ?? "NT$")) { pick(a.id, code: list.first ?? "NT$") }
        }
    }

    private func pick(_ id: UUID, code: String) {
        choice = WealthPayFromChoice(bankId: id, bankCode: WealthFacts.norm(code), cardId: nil)
    }

    /// 選單列的銀行：沒收起來、不是定存（facts.pickerBanks）；外幣保單只留有那個幣別的
    private func banks(_ facts: WealthFacts) -> [WealthFacts.Account] {
        guard let code = onlyCode, !FinanceRates.isNTD(code) else { return facts.pickerBanks }
        let c = WealthFacts.norm(code)
        return facts.pickerBanks.filter { $0.currencies.contains(c) }
    }

    private func codes(of a: WealthFacts.Account) -> [String] {
        if let code = onlyCode, !FinanceRates.isNTD(code) { return [WealthFacts.norm(code)] }
        return a.currencies
    }

    /// 帳戶本來就只有一個幣別「台新銀行（存摺 NT$12.8萬）」；外幣保單從好幾個幣別只留一個「玉山 · 美金（存摺 美金 3,200）」
    private func singleLabel(_ a: WealthFacts.Account, code: String) -> String {
        guard a.currencies.count > 1 else { return a.pickerLabel }
        return a.name + " · " + a.pickerLabel(code: code)
    }

    /// 「CUBE（還能刷 27.5萬）」；沒填額度只寫卡名
    private func cardLabel(_ c: WealthFacts.Card) -> String {
        guard let left = c.available else { return c.name }
        return c.name + "（還能刷 " + WealthFormChoiceText.wan(left) + "）"
    }

    /// 選了什麼：「刷 CUBE」「薪轉」「玉山 · 美金」「沒填」
    private func labelText(_ facts: WealthFacts) -> String {
        if let cid = choice.cardId {
            return "刷 " + (facts.card(cid)?.name ?? "信用卡")
        }
        if let bid = choice.bankId {
            let name = facts.account(bid)?.name ?? "銀行帳戶"
            return FinanceRates.isNTD(choice.bankCode) ? name : name + " · " + choice.bankCode
        }
        return "沒填"
    }
}


// MARK: - 以下由 G3 實作（簽章不改；G1／G2／G4 照簽章叫）

/// [v25.567] 連動小表單共用的字（主執行緒叫；名字一律照財富的暱稱）
enum WealthLinkText {
    /// 帳戶、卡的 id → 名字（同 WealthFacts 給保單總表的 nameById：暱稱 → 銀行名／卡名）
    static func names(_ facts: WealthFacts) -> [UUID: String] {
        var out: [UUID: String] = [:]
        for a in facts.accounts { out[a.id] = a.name }
        for c in facts.cards { out[c.id] = c.name }
        return out
    }

    /// 記帳那一筆保費「每年 8/15・24,000・刷 CUBE」（同要確認 #15 的括號裡那段）
    static func premiumLine(_ e: Expense, names: [UUID: String]) -> String {
        var parts: [String] = [WealthPolicyLink.scheduleText(e)]
        parts.append(WealthPolicyFacts.amountText(e.amount, code: WealthPolicyFacts.expenseCode(e)))
        if let pay = WealthPolicyFacts.payerText(cardId: e.linkedCreditCardMilestoneId,
                                                 bankId: e.linkedBankMilestoneId, names: names) {
            parts.append(pay)
        }
        return parts.joined(separator: "・")
    }

    /// 記帳那一筆的名字（空白＝「保費」）
    static func title(_ e: Expense) -> String {
        let t = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "保費" : t
    }

    /// 貸款那一列的名字「房貸」：去掉開頭的【房名】／【車名】（HouseCardFormat.cleanTitle；找不到房子、車子傳 ""）
    static func loanTitle(_ e: Expense, finance: FinanceStore) -> String {
        var owner = ""
        if let rid = e.linkedRealEstateId, let re = finance.realEstates.first(where: { $0.id == rid }) {
            owner = re.name
        } else if let vid = e.linkedVehicleId, let v = finance.vehicles.first(where: { $0.id == vid }) {
            owner = v.name
        }
        let cleaned = HouseCardFormat.cleanTitle(e.title, estateName: owner)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty { return cleaned }
        return title(e)
    }

    /// 「從房貸扣款（國泰世華）」「從薪轉（台新銀行） · 美金」「刷 CUBE」；沒設、帳戶已經不在 nil
    static func payerLabel(_ e: Expense, facts: WealthFacts) -> String? {
        if let cid = e.linkedCreditCardMilestoneId {
            guard let c = facts.card(cid) else { return nil }
            return "刷 " + c.name
        }
        guard let bid = e.linkedBankMilestoneId, let a = facts.account(bid) else { return nil }
        var s = "從" + a.name
        let bank = a.bankName.trimmingCharacters(in: .whitespaces)
        if !bank.isEmpty && bank != a.name { s += "（" + bank + "）" }
        let code = e.linkedBankCurrency ?? "NT$"
        if !FinanceRates.isNTD(code) { s += " · " + WealthFacts.norm(code) }
        return s
    }
}

/// 改一筆記帳固定支出從哪扣（房屋卡、車子卡貸款列；judge §6.1、§6.3「從哪扣：國泰世華 房貸扣款 ›，改的是記帳那筆固定支出」）。
/// 欄位：那一筆的名字與金額（唯讀一行）、WealthPayFromMenu、「從下一期起改（以前扣的照舊）」／「以前的也改」兩選一（預設下一期）。
/// 存：先 dismiss，下一個 runloop LifeStore.setExpensePayer(expenseId, bankId:bankCode:cardId:from:（下一期＝今天；以前的也改＝nil）expense:)。
/// 要訂閱（呼叫端擋）。.presentationDetents([.medium, .large])
struct WealthPayFromSheet: View {
    let expenseId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var choice = WealthPayFromChoice()
    /// 打開時那一筆從哪扣（沒改就不能存）
    @State private var original = WealthPayFromChoice()
    @State private var allPast = false
    /// 唯讀一行：「房貸」「每月 5 日」「32,000」（打開時組好）
    @State private var itemTitle = ""
    @State private var itemSchedule = ""
    @State private var itemAmount = ""
    /// 外幣那一筆（外幣儲蓄險）只列同幣別的子帳戶和卡；台幣 nil
    @State private var onlyCode: String?
    @State private var found = true
    @State private var loaded = false
    @State private var isSaving = false

    private var saveDisabled: Bool { !found || choice == original }

    var body: some View {
        NavigationStack {
            Form {
                itemSection
                if found {
                    payerSection
                    whenSection
                }
            }
            .navigationTitle("從哪扣")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                WealthSaveToolbar(title: "存", isSaving: isSaving, disabled: saveDisabled,
                                  onCancel: { dismiss() }, onSave: { save() })
            }
            .onAppear { load() }
        }
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    private var itemSection: some View {
        Section {
            if found {
                itemRow
            } else {
                Text(Self.goneText)
                    .foregroundStyle(.secondary)
            }
        } header: {
            WealthFormHeader(title: "記帳的這一筆", icon: "list.bullet.rectangle.fill", color: .blue)
        }
    }

    private var itemRow: some View {
        HStack(spacing: 8) {
            Text(itemTitle)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(itemSchedule)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(itemAmount)
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)
        }
    }

    private var payerSection: some View {
        Section {
            WealthPayFromMenu(choice: $choice, onlyCode: onlyCode, allowNone: true)
        } header: {
            WealthFormHeader(title: "從哪扣", icon: "building.columns.fill", color: .blue)
        } footer: {
            Text(Self.payerFootnote)
        }
    }

    private var whenSection: some View {
        Section {
            Picker("從哪一期起改", selection: $allPast) {
                Text("下一期起（以前扣的照舊）").tag(false)
                Text("以前的也改").tag(true)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            WealthFormHeader(title: "從哪一期起改", icon: "calendar", color: .blue)
        } footer: {
            Text(allPast ? Self.allPastFootnote : Self.nextFootnote)
        }
    }

    static let goneText = "這筆記帳已經刪了。"
    static let payerFootnote = "改的是記帳那一筆固定支出：記帳、房屋卡、車子卡、財富頁都讀同一筆。"
    static let nextFootnote = "以前扣的期數照舊記在原本的帳戶或卡，存摺上的數字不會突然變。"
    static let allPastFootnote = "以前扣的期數也一起算到新的地方：以前的存摺上、卡費會跟著變。"

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let e = expenseStore.expenses.first(where: { $0.id == expenseId }) else {
            found = false
            return
        }
        let c = WealthPayFromChoice.of(e)
        choice = c
        original = c
        itemTitle = WealthLinkText.loanTitle(e, finance: financeStore)
        itemSchedule = WealthCardText.schedule(e)
        let code = WealthPolicyFacts.expenseCode(e)
        itemAmount = WealthPolicyFacts.amountText(e.amount, code: code)
        onlyCode = FinanceRates.isNTD(code) ? nil : code
    }

    /// 先關畫面、下一個 runloop 才寫（store 先抓進區域常數）；連著保單的那一筆，保單的舊欄位跟著寫一份
    private func save() {
        guard !isSaving, !saveDisabled else { return }
        isSaving = true
        let life = lifeStore
        let es = expenseStore
        let id = expenseId
        let c = choice
        let code: String? = c.bankId != nil ? c.bankCode : nil
        let from: Date? = allPast ? nil : Date()
        dismiss()
        DispatchQueue.main.async {
            life.setExpensePayer(id, bankId: c.bankId, bankCode: code, cardId: c.cardId, from: from, expense: es)
            if let updated = es.expenses.first(where: { $0.id == id }) {
                life.policyExpenseChanged(updated)
            }
        }
    }
}

/// 從哪扣那一段的一列（房貸、車貸各一筆）
struct WealthLoanPayRow: Identifiable {
    /// 記帳那一筆的 id
    let id: UUID
    /// 「房貸」
    let title: String
    /// 「每月 5 日」
    let schedule: String
    /// 「從房貸扣款（國泰世華）」「刷 CUBE」「還沒選」
    let payer: String
    let missing: Bool

    var accessibilityText: String { title + "，" + schedule + "，" + payer }
}

/// 點了開哪一筆的改扣款小表單（.sheet(item:) 用）
struct WealthLoanPayTarget: Identifiable {
    let id: UUID
}

/// 房屋卡、車子卡貸款區下面一段「從哪扣」（一筆貸款一列：「房貸 每月 5 日　從房貸扣款（國泰世華）›」；沒設「還沒選 ›」琥珀色）。
/// expenseIds：這間房／這台車的貸款固定支出（呼叫端照自己的資料給；找不到的、停了的不列）。0 列整段不出現。
/// 點一列：要訂閱（沒訂閱跳付費說明）→ .sheet(item:) { WealthPayFromSheet(expenseId:).appStores() }
struct WealthLoanPayFromSection: View {
    let expenseIds: [UUID]

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var subscription: SubscriptionManager

    @State private var open: WealthLoanPayTarget?
    @State private var showPremium = false

    var body: some View {
        section(rows)
    }

    /// 照 expenseIds 的順序；找不到的、停了的不列（名字讀一套數字：暱稱 → 銀行名、卡名）
    private var rows: [WealthLoanPayRow] {
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        var out: [WealthLoanPayRow] = []
        for id in expenseIds {
            guard let e = expenseStore.expenses.first(where: { $0.id == id }), !e.isFixedEnded else { continue }
            if out.contains(where: { $0.id == id }) { continue }
            let payer: String? = WealthLinkText.payerLabel(e, facts: facts)
            out.append(WealthLoanPayRow(id: e.id, title: WealthLinkText.loanTitle(e, finance: financeStore),
                                        schedule: WealthCardText.schedule(e), payer: payer ?? "還沒選",
                                        missing: payer == nil))
        }
        return out
    }

    @ViewBuilder
    private func section(_ list: [WealthLoanPayRow]) -> some View {
        if !list.isEmpty {
            content(list)
                .sheet(item: $open) { t in
                    WealthPayFromSheet(expenseId: t.id).appStores()
                }
                .premiumLockAlert(isPresented: $showPremium)
        }
    }

    private func content(_ list: [WealthLoanPayRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "從哪扣", trailing: nil)
            card(list)
        }
    }

    private func card(_ list: [WealthLoanPayRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                if i > 0 {
                    Divider()
                }
                rowView(r)
            }
            Text(Self.footnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .modifier(FinanceCardChrome())
    }

    private func rowView(_ r: WealthLoanPayRow) -> some View {
        Button {
            tap(r.id)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(r.schedule)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                payerText(r)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(r.accessibilityText)
        .accessibilityHint("改從哪扣")
    }

    private func payerText(_ r: WealthLoanPayRow) -> some View {
        let weight: Font.Weight = r.missing ? .semibold : .regular
        let color: Color = r.missing ? Color.orange : Color.secondary
        return Text(r.payer)
            .font(Font.subheadline.weight(weight))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    static let footnote = "改的是記帳那一筆固定支出；預設從下一期起改，以前扣的照舊。"

    /// 要訂閱：沒訂閱跳付費說明
    private func tap(_ id: UUID) {
        guard subscription.isPremium else {
            showPremium = true
            return
        }
        open = WealthLoanPayTarget(id: id)
    }
}

/// 證券戶舊交割搬家（judge §4.3 ④：搬之前先列「會動到 18 筆、薪轉的存摺上會變多少、哪幾筆薪轉已經有同一筆會跳過」，你按確定才搬）。
/// 打開時算一次 LifeStore.settlementMovePlan(brokerId:expense:finance:)（nil＝「沒有要搬的」一行＋關閉）；
/// 字照 WealthSettlementMovePlan 的 summary／bankLine／anchorLine／skipLine／keepLine／stocksLine／cashLine；
/// 按鈕〔搬到薪轉〕（綠）〔取消〕；按了先 dismiss、下一個 runloop LifeStore.moveLegacySettlements(plan, finance:)。
/// 不擋訂閱（修資料，同〔改過來〕）。.presentationDetents([.medium, .large])，掛 WealthPrivacyCurtain(armed: true)
struct WealthSettlementMoveSheet: View {
    let brokerId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var plan: WealthSettlementMovePlan?
    /// 計畫的字（打開時在主執行緒組好一次：cashLine 用 ntdWanString）
    @State private var lines: [String] = []
    @State private var loaded = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                if !loaded {
                    loadingSection
                } else if let p = plan {
                    planSection
                    buttonSection(p)
                } else {
                    emptySection
                }
            }
            .navigationTitle("搬到交割銀行")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                WealthSaveToolbar(title: "搬", isSaving: isSaving, disabled: true, showsSave: false,
                                  onCancel: { dismiss() }, onSave: {})
            }
            .task { load() }
        }
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    private var loadingSection: some View {
        Section {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
    }

    private var planSection: some View {
        Section {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, s in
                Text(s)
                    .font(Self.lineFont(i))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            WealthFormHeader(title: "會動到哪些", icon: "arrow.left.arrow.right.circle.fill", color: .purple)
        } footer: {
            Text(Self.footnote)
        }
    }

    private func buttonSection(_ p: WealthSettlementMovePlan) -> some View {
        Section {
            Button {
                move()
            } label: {
                Text("搬到" + p.bankName)
                    .bold()
                    .foregroundStyle(Color.green)
                    .frame(maxWidth: .infinity)
            }
            .disabled(isSaving)
            Button {
                dismiss()
            } label: {
                Text("取消")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var emptySection: some View {
        Section {
            Text(Self.emptyText)
                .foregroundStyle(.secondary)
            Button {
                dismiss()
            } label: {
                Text("關閉")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// 第一行（會動到幾筆、合計）粗一點
    private static func lineFont(_ i: Int) -> Font {
        i == 0 ? Font.body.weight(.semibold) : Font.subheadline
    }

    static let footnote = "搬過去的紀錄 id 不變；之後這幾檔的交割都記在交割銀行。"
    static let emptyText = "沒有要搬的紀錄（或這個證券戶還沒選交割銀行）。"

    /// 算一次計畫（重算一次一套數字，只在打開時叫）
    private func load() {
        guard !loaded else { return }
        let p = lifeStore.settlementMovePlan(brokerId: brokerId, expense: expenseStore, finance: financeStore)
        plan = p
        if let p {
            var out: [String] = [p.summary, p.bankLine]
            if let s = p.anchorLine { out.append(s) }
            if let s = p.skipLine { out.append(s) }
            if let s = p.keepLine { out.append(s) }
            if let s = p.stocksLine { out.append(s) }
            out.append(p.cashLine)
            lines = out
        }
        loaded = true
    }

    /// 你按了〔搬到薪轉〕：先關畫面、下一個 runloop 才搬（store 先抓進區域常數）
    private func move() {
        guard !isSaving, let p = plan else { return }
        isSaving = true
        let life = lifeStore
        let fs = financeStore
        dismiss()
        DispatchQueue.main.async {
            life.moveLegacySettlements(p, finance: fs)
        }
    }
}

/// 連到記帳的保費那一列
struct WealthPolicyLinkRow: Identifiable {
    /// 記帳那一筆的 id
    let id: UUID
    /// 「國泰人壽醫療險」
    let title: String
    /// 「每年 8/15・24,000・刷 CUBE」
    let detail: String
    /// 要確認 #15 認為最像的那一筆（排第一）
    let best: Bool

    var accessibilityText: String { (best ? "最像，" : "") + title + "，" + detail }
}

/// 保單頁〔連到記帳的保費〕：列出記帳裡還沒連保單的保費（WealthPolicyFacts.match(for:) 那一筆排第一、標「最像」；其他照
/// WealthPolicyLink.isPremiumExpense、沒被認領的），一列「國泰人壽醫療險　每年 8/15・24,000・刷 CUBE」；點一列先 dismiss、
/// 下一個 runloop LifeStore.linkPolicy(policyId, expenseId:expense:)。一筆都沒有：一行「記帳裡沒有還沒連保單的保費」＋說明
/// （到保單頁〔新建一筆〕，或在記帳記一筆固定支出（保險）再回來連；保單頁的〔新建一筆〕就在這顆旁邊，這裡不再疊一張表單）。要訂閱（呼叫端擋）
struct WealthPolicyLinkSheet: View {
    let policyId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [WealthPolicyLinkRow] = []
    @State private var policyTitle = ""
    @State private var loaded = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                if !loaded {
                    EmptyView()
                } else if rows.isEmpty {
                    emptySection
                } else {
                    listSection
                }
            }
            .navigationTitle("連到記帳的保費")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                WealthSaveToolbar(title: "連", isSaving: isSaving, disabled: true, showsSave: false,
                                  onCancel: { dismiss() }, onSave: {})
            }
            .onAppear { load() }
        }
        .presentationDetents([.medium, .large])
        .modifier(WealthPrivacyCurtain(armed: true))
    }

    private var listSection: some View {
        Section {
            ForEach(rows) { r in
                rowView(r)
            }
        } header: {
            WealthFormHeader(title: headerTitle, icon: "link.circle.fill", color: .green)
        } footer: {
            Text(Self.footnote)
        }
    }

    private var headerTitle: String {
        policyTitle.isEmpty ? "選記帳裡的一筆保費" : "「" + policyTitle + "」連到哪一筆"
    }

    private func rowView(_ r: WealthPolicyLinkRow) -> some View {
        Button {
            link(r.id)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    rowTitle(r)
                    Text(r.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "link")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.green)
            }
            .contentShape(Rectangle())
        }
        .disabled(isSaving)
        .accessibilityLabel(r.accessibilityText)
        .accessibilityHint("連起來")
    }

    private func rowTitle(_ r: WealthPolicyLinkRow) -> some View {
        HStack(spacing: 6) {
            Text(r.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            if r.best {
                Text("最像")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green, in: Capsule())
            }
        }
    }

    private var emptySection: some View {
        Section {
            Text(Self.emptyText)
                .foregroundStyle(.secondary)
        } footer: {
            Text(Self.emptyFootnote)
        }
    }

    static let footnote = "連起來以後保費只有一份：在記帳改金額、扣款，保單跟著；稅務頁照算，不會多一筆。"
    static let emptyText = "記帳裡沒有還沒連保單的保費"
    static let emptyFootnote = "到保單〔新建一筆〕，或在記帳記一筆固定支出（保險）再回來連。"

    /// 打開時組一次：#15 最像的那一筆排第一；其他是記帳裡的保障型保費、還沒被任何保單／儲蓄險／車／房認領的（照日期）
    private func load() {
        guard !loaded else { return }
        loaded = true
        let facts = lifeStore.wealthFacts(expense: expenseStore, finance: financeStore)
        let names = WealthLinkText.names(facts)
        let today = WealthCal.day(Date())
        policyTitle = facts.policies.policy(policyId)?.title ?? ""
        var list: [WealthPolicyLinkRow] = []
        var seen = Set<UUID>()
        if let m = facts.policies.match(for: policyId),
           let e = expenseStore.expenses.first(where: { $0.id == m.expenseId }) {
            list.append(WealthPolicyLinkRow(id: e.id, title: WealthLinkText.title(e),
                                            detail: WealthLinkText.premiumLine(e, names: names), best: true))
            seen.insert(e.id)
        }
        let claimed: Set<UUID> = facts.policies.claimed
        let others: [Expense] = expenseStore.expenses.filter { e in
            WealthPolicyLink.isPremiumExpense(e, today: today) && !claimed.contains(e.id) && !seen.contains(e.id)
        }.sorted { a, b in a.date != b.date ? a.date < b.date : a.id.uuidString < b.id.uuidString }
        for e in others {
            list.append(WealthPolicyLinkRow(id: e.id, title: WealthLinkText.title(e),
                                            detail: WealthLinkText.premiumLine(e, names: names), best: false))
        }
        rows = list
    }

    /// 點一列：先關畫面、下一個 runloop 才連（store 先抓進區域常數）
    private func link(_ expenseId: UUID) {
        guard !isSaving else { return }
        isSaving = true
        let life = lifeStore
        let es = expenseStore
        let pid = policyId
        dismiss()
        DispatchQueue.main.async {
            life.linkPolicy(pid, expenseId: expenseId, expense: es)
        }
    }
}
