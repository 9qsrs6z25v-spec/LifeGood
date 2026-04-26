import SwiftUI

struct LifeFinanceView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @State private var selectedSub: FinanceSubCategory?
    @State private var viewingItem: LifeMilestone?
    @State private var showAdd = false

    private var financeMilestones: [LifeMilestone] {
        lifeStore.milestones
            .filter { $0.category == .achievement && $0.linkedBankMilestoneId == nil }
            .sorted { $0.date > $1.date }
    }

    private var filteredMilestones: [LifeMilestone] {
        if let sub = selectedSub {
            return financeMilestones.filter { $0.financeSubCategory == sub }
        }
        return financeMilestones
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader
                filterChips
                milestoneList
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("財富")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddMilestoneView(initialCategory: .achievement)
            }
            .sheet(item: $viewingItem) { item in
                FinanceCardView(milestoneId: item.id)
            }
        }
    }

    // MARK: - 摘要

    private var summaryHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("理財帳戶總覽").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(financeMilestones.count) 筆").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                ForEach(FinanceSubCategory.allCases) { sub in
                    let count = financeMilestones.filter { $0.financeSubCategory == sub }.count
                    VStack(spacing: 2) {
                        Image(systemName: sub.icon).font(.title3).foregroundStyle(colorFor(sub))
                        Text("\(count)").font(.caption.bold())
                        Text(sub.rawValue).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - 篩選

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(label: "全部", isSelected: selectedSub == nil) { selectedSub = nil }
                ForEach(FinanceSubCategory.allCases) { sub in
                    let count = financeMilestones.filter { $0.financeSubCategory == sub }.count
                    if count > 0 {
                        chipButton(label: "\(sub.rawValue) \(count)", isSelected: selectedSub == sub) { selectedSub = sub }
                    }
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    private func chipButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? Color.green : Color(.tertiarySystemFill))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 列表

    private func linkedCards(for bankId: UUID) -> [LifeMilestone] {
        lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .creditCard && $0.linkedBankMilestoneId == bankId
        }
    }

    private var milestoneList: some View {
        List {
            ForEach(filteredMilestones) { item in
                VStack(spacing: 0) {
                    milestoneRow(item)
                        .contentShape(Rectangle())
                        .onTapGesture { viewingItem = item }

                    if item.financeSubCategory == .bank {
                        let cards = linkedCards(for: item.id)
                        if !cards.isEmpty {
                            ForEach(cards) { card in
                                creditCardSubRow(card)
                                    .contentShape(Rectangle())
                                    .onTapGesture { viewingItem = card }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func creditCardSubRow(_ card: LifeMilestone) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.clear).frame(width: 20)
            Image(systemName: "creditcard.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(width: 24, height: 24)
                .background(Color.orange.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(card.cardName ?? card.title)
                    .font(.caption.weight(.medium))
                HStack(spacing: 4) {
                    if let lf = card.cardLastFour, !lf.isEmpty {
                        Text("末\(lf)").font(.caption2).foregroundStyle(.tertiary)
                    }
                    if let bd = card.billingDay, let pd = card.paymentDay {
                        Text("帳單\(bd)日 繳款\(pd)日")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func milestoneRow(_ item: LifeMilestone) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.financeSubCategory?.icon ?? "banknote.fill")
                .font(.title3)
                .foregroundStyle(colorFor(item.financeSubCategory ?? .bank))
                .frame(width: 36, height: 36)
                .background(colorFor(item.financeSubCategory ?? .bank).opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.medium))
                subtitle(for: item)
            }
            Spacer()
            if item.financeSubCategory == .bank {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("開戶日期：\(formatDate(item.date))")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text("存款總額 NT$ \(formatNumber(bankTotalBalance(for: item)))")
                        .font(.caption.bold())
                        .foregroundStyle(bankTotalBalance(for: item) >= 0 ? .blue : .red)
                }
            } else {
                Text(formatDate(item.date)).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    /// 計算銀行的目前總額（含信用卡彙總扣款 + 股票交易）
    private func bankTotalBalance(for ms: LifeMilestone) -> Double {
        var total: Double = 0
        // 真實 BankDeposit（過濾舊版可能殘留的信用卡支出記錄）
        let real = (ms.bankDeposits ?? []).filter { dep in
            guard let expId = dep.linkedExpenseId,
                  let exp = expenseStore.expenses.first(where: { $0.id == expId }) else { return true }
            return exp.linkedCreditCardMilestoneId == nil
        }
        for dep in real {
            total += dep.isWithdrawal ? -dep.amount : dep.amount
        }
        // 連結的信用卡支出（依 linkedCreditCardMilestoneId）
        let cards = lifeStore.milestones.filter {
            $0.financeSubCategory == .creditCard && $0.linkedBankMilestoneId == ms.id
        }
        for card in cards {
            let exps = expenseStore.expenses.filter { $0.linkedCreditCardMilestoneId == card.id }
            for exp in exps { total -= exp.amount }
        }
        return total
    }

    private func formatNumber(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "0"
    }

    @ViewBuilder
    private func subtitle(for item: LifeMilestone) -> some View {
        switch item.financeSubCategory {
        case .bank:
            let parts = [item.branchName, item.bankAccountType?.rawValue].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty { Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        case .creditCard:
            let parts = [item.cardName, item.cardLastFour.map { "末\($0)" }].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty { Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        case .securities:
            if let accType = item.securitiesAccountType { Text(accType.rawValue).font(.caption).foregroundStyle(.secondary) }
        case .insurance:
            let parts = [item.insuranceType?.rawValue, item.policyNumber].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty { Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        case .none:
            if !item.note.isEmpty { Text(item.note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
    }

    private func colorFor(_ sub: FinanceSubCategory) -> Color {
        switch sub {
        case .bank: return .blue; case .creditCard: return .orange
        case .securities: return .green; case .insurance: return .purple
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }
}

// MARK: - 財富卡片詳細頁

struct FinanceCardView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject var expenseStore: ExpenseStore
    let milestoneId: UUID
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showAddDeposit = false
    @State private var addDepositCurrency = "NT$"
    @State private var editingDeposit: BankDeposit?
    @State private var viewingLinkedCard: LifeMilestone?
    @State private var depositsExpanded = false

    private var item: LifeMilestone {
        lifeStore.milestones.first(where: { $0.id == milestoneId })
            ?? LifeMilestone(title: "", category: .achievement)
    }

    private var sub: FinanceSubCategory { item.financeSubCategory ?? .bank }

    private var color: Color {
        switch sub {
        case .bank: return .blue; case .creditCard: return .orange
        case .securities: return .green; case .insurance: return .purple
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    detailCard
                    if sub == .bank || sub == .securities { depositSection }
                    if sub == .bank { linkedCreditCardSection }
                    if sub == .creditCard { creditCardChartSection }
                    if !item.note.isEmpty { noteCard }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("財富卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showEdit = true } label: { Text("編輯").foregroundStyle(.green) }
                        Button { showDeleteConfirm = true } label: { Text("刪除").foregroundStyle(.red) }
                    }
                }
            }
            .sheet(isPresented: $showEdit) { AddMilestoneView(editing: item) }
            .sheet(item: $viewingLinkedCard) { card in
                FinanceCardView(milestoneId: card.id)
            }
            .sheet(isPresented: $showAddDeposit) {
                DepositEditorSheet(milestoneId: milestoneId, currency: addDepositCurrency, editing: nil)
            }
            .sheet(item: $editingDeposit) { dep in
                DepositEditorSheet(milestoneId: milestoneId, currency: dep.currencyCode, editing: dep)
            }
            .alert("確定要刪除嗎？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) { lifeStore.deleteMilestone(item); dismiss() }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private var headerCard: some View {
        VStack(spacing: 10) {
            Image(systemName: sub.icon)
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(
                    LinearGradient(colors: [color, color.opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(Circle())

            Text(item.title).font(.title3.bold())
            Text(sub.rawValue)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(color.opacity(0.12))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(fmtDate(item.date)).font(.caption).foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch sub {
            case .bank: bankDetail
            case .creditCard: creditCardDetail
            case .securities: securitiesDetail
            case .insurance: insuranceDetail
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    @ViewBuilder
    private var bankDetail: some View {
        if let b = item.branchName, !b.isEmpty { infoRow("分行", b) }
        if let a = item.accountNumber, !a.isEmpty { infoRow("帳號", a) }
        if let t = item.bankAccountType { infoRow("帳戶類型", t.rawValue) }
        infoRow("開戶日期", fmtDate(item.date))
    }

    @ViewBuilder
    private var creditCardDetail: some View {
        if let c = item.cardName, !c.isEmpty { infoRow("卡別", c) }
        if let l = item.cardLastFour, !l.isEmpty { infoRow("卡號末四碼", l) }
        if let cl = item.creditLimit, cl > 0 { infoRow("額度", "NT$\(fmtNum(cl))") }
        if let af = item.annualFee, af > 0 { infoRow("年費", "NT$\(fmtNum(af))") }
        if let bd = item.billingDay { infoRow("帳單日", "每月 \(bd) 日") }
        if let pd = item.paymentDay { infoRow("繳款日", "每月 \(pd) 日") }
        infoRow("核卡日期", fmtDate(item.date))
        if let ed = item.expiryDate { infoRow("到期日", fmtDate(ed)) }
    }

    @ViewBuilder
    private var securitiesDetail: some View {
        if let a = item.accountNumber, !a.isEmpty { infoRow("帳號", a) }
        if let t = item.securitiesAccountType { infoRow("帳戶類型", t.rawValue) }
        infoRow("開戶日期", fmtDate(item.date))
    }

    @ViewBuilder
    private var insuranceDetail: some View {
        if let co = item.insuranceCompany, !co.isEmpty { infoRow("保險公司", co) }
        if let pn = item.policyNumber, !pn.isEmpty { infoRow("保單號碼", pn) }
        if let it = item.insuranceType { infoRow("險種", it.rawValue) }
        if let pa = item.premiumAmount, pa > 0 { infoRow("保費", "NT$\(fmtNum(pa))") }
        infoRow("生效日", fmtDate(item.date))
        if let ed = item.expiryDate { infoRow("到期日", fmtDate(ed)) }
        if let b = item.beneficiary, !b.isEmpty { infoRow("受益人", b) }
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("備註").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(item.note).font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline)
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    private func fmtDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }

    private func fmtNum(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "0"
    }

    // MARK: - 銀行存款章節

    /// 銀行存款列表：直接扣款的 BankDeposit + 信用卡逐月彙總（虛擬條目）
    private var deposits: [BankDeposit] {
        // 過濾：排除舊版本可能殘留、屬於信用卡支出的 BankDeposit（避免重複）
        let real = (item.bankDeposits ?? []).filter { dep in
            guard let expId = dep.linkedExpenseId,
                  let exp = expenseStore.expenses.first(where: { $0.id == expId }) else { return true }
            return exp.linkedCreditCardMilestoneId == nil
        }
        let aggregated = aggregatedCreditCardWithdrawals()
        return (real + aggregated).sorted { $0.date < $1.date }
    }

    /// 將連結到本銀行的信用卡支出依月份彙總成虛擬 BankDeposit
    private func aggregatedCreditCardWithdrawals() -> [BankDeposit] {
        let cards = lifeStore.milestones.filter {
            $0.financeSubCategory == .creditCard && $0.linkedBankMilestoneId == milestoneId
        }
        var result: [BankDeposit] = []
        for card in cards {
            let cardExpenses = expenseStore.expenses.filter {
                $0.linkedCreditCardMilestoneId == card.id
            }
            let groups = Dictionary(grouping: cardExpenses) { exp -> String in
                let withdrawalDate = LifeMilestone.creditCardWithdrawalDate(
                    for: exp.date,
                    billingDay: card.billingDay,
                    paymentDay: card.paymentDay
                )
                let comps = Calendar.current.dateComponents([.year, .month], from: withdrawalDate)
                return "\(comps.year ?? 0)-\(comps.month ?? 0)"
            }
            for (_, exps) in groups {
                let total = exps.reduce(0.0) { $0 + $1.amount }
                let firstDate = exps.first?.date ?? Date()
                let withdrawalDate = LifeMilestone.creditCardWithdrawalDate(
                    for: firstDate,
                    billingDay: card.billingDay,
                    paymentDay: card.paymentDay
                )
                let stableId = stableUUID(seed: "\(card.id)-\(withdrawalDate.timeIntervalSince1970)")
                result.append(BankDeposit(
                    id: stableId,
                    date: withdrawalDate,
                    amount: total,
                    currencyCode: "NT$",
                    isWithdrawal: true,
                    linkedExpenseId: nil
                ))
            }
        }
        return result
    }

    private func stableUUID(seed: String) -> UUID {
        var hasher = Hasher()
        hasher.combine(seed)
        var x = UInt(bitPattern: hasher.finalize())
        var bytes: [UInt8] = []
        for _ in 0..<8 {
            bytes.append(UInt8(x & 0xFF))
            x >>= 8
        }
        var hasher2 = Hasher()
        hasher2.combine(seed)
        hasher2.combine("vc")
        var y = UInt(bitPattern: hasher2.finalize())
        for _ in 0..<8 {
            bytes.append(UInt8(y & 0xFF))
            y >>= 8
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private var depositSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "dollarsign.circle.fill").foregroundStyle(.blue)
                Text(sub == .securities ? "證券交易" : "銀行存款").font(.headline)
                Spacer()
                Menu {
                    Button { addDepositCurrency = "NT$"; showAddDeposit = true } label: {
                        Label("台幣", systemImage: "dollarsign")
                    }
                    ForEach(expenseStore.currencyRates) { rate in
                        Button { addDepositCurrency = rate.code; showAddDeposit = true } label: {
                            Label(rate.code, systemImage: "coloncurrencysign")
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.blue)
                }
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)

            if deposits.isEmpty {
                Text("尚無存款記錄").font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal).padding(.bottom, 12)
            } else {
                depositChart
                    .padding(.horizontal).padding(.bottom, 8)

                let sortedDesc = deposits.sorted { $0.date > $1.date }
                let visible = depositsExpanded ? sortedDesc : Array(sortedDesc.prefix(6))
                ForEach(visible, id: \.id) { dep in
                    depositRow(dep)
                }
                if sortedDesc.count > 6 {
                    Button {
                        withAnimation { depositsExpanded.toggle() }
                    } label: {
                        HStack {
                            Spacer()
                            Text(depositsExpanded ? "收起" : "展開全部 (\(sortedDesc.count) 筆)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.blue)
                            Image(systemName: depositsExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 信用卡圖表章節（顯示於信用卡卡片）

    private struct CreditCardMonthlyTotal: Identifiable {
        let id: String
        let date: Date
        let amount: Double
    }

    private var creditCardMonthlyTotals: [CreditCardMonthlyTotal] {
        let exps = expenseStore.expenses.filter { $0.linkedCreditCardMilestoneId == milestoneId }
        let groups = Dictionary(grouping: exps) { exp -> String in
            let withdrawalDate = LifeMilestone.creditCardWithdrawalDate(
                for: exp.date,
                billingDay: item.billingDay,
                paymentDay: item.paymentDay
            )
            let comps = Calendar.current.dateComponents([.year, .month], from: withdrawalDate)
            return "\(comps.year ?? 0)-\(comps.month ?? 0)"
        }
        return groups.compactMap { (key, exps) -> CreditCardMonthlyTotal? in
            guard let firstExp = exps.first else { return nil }
            let withdrawalDate = LifeMilestone.creditCardWithdrawalDate(
                for: firstExp.date,
                billingDay: item.billingDay,
                paymentDay: item.paymentDay
            )
            let total = exps.reduce(0.0) { $0 + $1.amount }
            return CreditCardMonthlyTotal(id: key, date: withdrawalDate, amount: total)
        }
        .sorted { $0.date < $1.date }
    }

    @State private var ccExpanded = false

    private var creditCardExpenseItems: [Expense] {
        expenseStore.expenses
            .filter { $0.linkedCreditCardMilestoneId == milestoneId }
            .sorted { $0.date > $1.date }
    }

    private var creditCardChartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "chart.bar.fill").foregroundStyle(.orange)
                Text("月扣款金額").font(.headline)
                Spacer()
                Text("\(creditCardMonthlyTotals.count) 期").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)

            if creditCardMonthlyTotals.isEmpty {
                Text("尚無扣款記錄").font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal).padding(.bottom, 12)
            } else {
                creditCardChart
                    .padding(.horizontal).padding(.bottom, 8)

                // 最近一期加總
                if let last = creditCardMonthlyTotals.last {
                    HStack {
                        Text("最近一期").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("-NT$ \(fmtNum(last.amount))").font(.caption.bold())
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal).padding(.bottom, 6)
                }

                Divider().padding(.horizontal)

                // 個別項目列表
                let items = creditCardExpenseItems
                let visible = ccExpanded ? items : Array(items.prefix(6))
                ForEach(visible) { exp in
                    HStack {
                        Text(fmtDate(exp.date)).font(.caption).foregroundStyle(.tertiary)
                        Text(exp.title).font(.caption).lineLimit(1)
                        Spacer()
                        Text("-NT$ \(fmtNum(exp.amount))")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal).padding(.vertical, 5)
                }
                if items.count > 6 {
                    Button {
                        withAnimation { ccExpanded.toggle() }
                    } label: {
                        HStack {
                            Spacer()
                            Text(ccExpanded ? "收起" : "展開全部 (\(items.count) 筆)")
                                .font(.caption.weight(.medium)).foregroundStyle(.orange)
                            Image(systemName: ccExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2).foregroundStyle(.orange)
                            Spacer()
                        }
                        .padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var creditCardChart: some View {
        let data = creditCardMonthlyTotals
        let maxAmount = data.map(\.amount).max() ?? 1
        let labelStride = max(1, data.count / 6)

        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, row in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.red)
                        .frame(
                            width: max(12, (UIScreen.main.bounds.width - 80) / CGFloat(max(data.count, 1))),
                            height: max(4, CGFloat(row.amount / max(maxAmount, 1)) * 120)
                        )
                    Text(index % labelStride == 0 ? shortDate(row.date) : " ")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(height: 140, alignment: .bottom)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 信用卡章節

    private var linkedCreditCards: [LifeMilestone] {
        lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .creditCard && $0.linkedBankMilestoneId == milestoneId
        }
    }

    private var linkedCreditCardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "creditcard.fill").foregroundStyle(.orange)
                Text("信用卡").font(.headline)
                Spacer()
                Text("\(linkedCreditCards.count) 張").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)

            if linkedCreditCards.isEmpty {
                Text("尚無信用卡").font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal).padding(.bottom, 12)
            } else {
                ForEach(linkedCreditCards) { card in
                    Button { viewingLinkedCard = card } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "creditcard.fill")
                                .font(.caption).foregroundStyle(.orange).frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.title).font(.subheadline.weight(.medium)).foregroundStyle(Color.primary)
                                HStack(spacing: 4) {
                                    if let cn = card.cardName, !cn.isEmpty { Text(cn).font(.caption).foregroundStyle(.secondary) }
                                    if let lf = card.cardLastFour, !lf.isEmpty { Text("末\(lf)").font(.caption).foregroundStyle(.tertiary) }
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal).padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func isVirtualCreditCardEntry(_ dep: BankDeposit) -> Bool {
        !(item.bankDeposits ?? []).contains(where: { $0.id == dep.id })
    }

    private func depositRow(_ dep: BankDeposit) -> some View {
        let isVirtual = isVirtualCreditCardEntry(dep)
        let isStock = dep.linkedStockId != nil
        let badgeText: String? = {
            if isStock {
                if dep.isWithdrawal { return "買入/虧損" }
                return "賣出獲利"
            }
            if dep.isWithdrawal { return isVirtual ? "信用卡" : "扣款" }
            return nil
        }()
        let badgeColor: Color = {
            if isStock { return .purple }
            if isVirtual { return .orange }
            return .red
        }()
        return Button {
            // 連結扣款 / 信用卡彙總 / 股票交易 不可直接編輯
            if dep.linkedExpenseId == nil && !isVirtual && !isStock { editingDeposit = dep }
        } label: {
            HStack {
                Text(fmtDate(dep.date)).font(.caption).foregroundStyle(.tertiary)
                if let txt = badgeText {
                    Text(txt).font(.caption2).foregroundStyle(badgeColor)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(badgeColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Spacer()
                Text("\(dep.isWithdrawal ? "-" : "")\(dep.currencyCode) \(fmtNum(dep.amount))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(
                        isStock ? (dep.isWithdrawal ? Color.red : Color.green) :
                        (dep.isWithdrawal ? (isVirtual ? Color.orange : Color.red) :
                         (dep.currencyCode == "NT$" ? Color.primary : Color.blue))
                    )
            }
            .padding(.horizontal).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var depositChart: some View {
        let data = deposits
        var balances: [(date: Date, balance: Double, id: UUID)] = []
        var running: Double = 0
        for dep in data {
            if dep.isWithdrawal { running -= dep.amount } else { running += dep.amount }
            balances.append((dep.date, running, dep.id))
        }
        let maxBal = balances.map(\.balance).max() ?? 1
        let minBal = min(0, balances.map(\.balance).min() ?? 0)
        let range = max(maxBal - minBal, 1)
        let useLineChart = balances.count > 12
        let labelStride = max(1, balances.count / 6)

        return VStack(alignment: .leading, spacing: 4) {
            if useLineChart {
                balanceLineChart(balances: balances, minBal: minBal, range: range, labelStride: labelStride)
            } else {
                balanceBarChart(balances: balances, minBal: minBal, range: range, labelStride: labelStride)
            }

            if let last = balances.last {
                HStack {
                    Text("目前總額").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(fmtNum(last.balance))").font(.caption.bold())
                        .foregroundStyle(last.balance >= 0 ? Color.blue : Color.red)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: date)
    }

    private func barColor(for dep: BankDeposit) -> Color {
        if dep.isWithdrawal { return .red }
        return dep.currencyCode == "NT$" ? .blue : .orange
    }

    @ViewBuilder
    private func balanceBarChart(
        balances: [(date: Date, balance: Double, id: UUID)],
        minBal: Double,
        range: Double,
        labelStride: Int
    ) -> some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(balances.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(item.balance >= 0 ? Color.blue : Color.red)
                        .frame(
                            width: max(12, (UIScreen.main.bounds.width - 80) / CGFloat(max(balances.count, 1))),
                            height: max(4, CGFloat(abs(item.balance - minBal) / range) * 120)
                        )
                    Text(index % labelStride == 0 ? shortDate(item.date) : " ")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(height: 140, alignment: .bottom)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func balanceLineChart(
        balances: [(date: Date, balance: Double, id: UUID)],
        minBal: Double,
        range: Double,
        labelStride: Int
    ) -> some View {
        let chartHeight: CGFloat = 120
        GeometryReader { geo in
            let width = geo.size.width
            let count = max(balances.count, 1)
            let stepX = count > 1 ? width / CGFloat(count - 1) : 0

            ZStack {
                // 零線
                if minBal < 0 {
                    let zeroY = chartHeight - CGFloat(-minBal / range) * chartHeight
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: zeroY))
                        p.addLine(to: CGPoint(x: width, y: zeroY))
                    }
                    .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                }

                // 折線
                Path { p in
                    for (i, item) in balances.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = chartHeight - CGFloat((item.balance - minBal) / range) * chartHeight
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // 填色
                Path { p in
                    for (i, item) in balances.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = chartHeight - CGFloat((item.balance - minBal) / range) * chartHeight
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    p.addLine(to: CGPoint(x: width, y: chartHeight))
                    p.addLine(to: CGPoint(x: 0, y: chartHeight))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.0)],
                                     startPoint: .top, endPoint: .bottom))

                // 數據點
                ForEach(Array(balances.enumerated()), id: \.element.id) { i, item in
                    let x = CGFloat(i) * stepX
                    let y = chartHeight - CGFloat((item.balance - minBal) / range) * chartHeight
                    Circle()
                        .fill(item.balance >= 0 ? Color.blue : Color.red)
                        .frame(width: 4, height: 4)
                        .position(x: x, y: y)
                }
            }
        }
        .frame(height: chartHeight)

        // X 軸日期（依 labelStride 抽樣顯示）
        HStack(spacing: 0) {
            ForEach(Array(balances.enumerated()), id: \.element.id) { i, item in
                Text(i % labelStride == 0 ? shortDate(item.date) : " ")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - 存款編輯 Sheet

struct DepositEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let milestoneId: UUID
    let currency: String
    var editing: BankDeposit?

    @State private var date = Date()
    @State private var amountText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("\(currency) 存款") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    HStack {
                        Text(currency).foregroundStyle(.secondary)
                        TextField("金額", text: $amountText).keyboardType(.decimalPad)
                    }
                }
                if editing != nil {
                    Section {
                        Button(role: .destructive) { delete() } label: { Label("刪除", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯存款" : "新增存款")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled((Double(amountText) ?? 0) <= 0)
                }
            }
            .onAppear {
                if let e = editing {
                    date = e.date
                    amountText = String(format: "%.0f", e.amount)
                }
            }
        }
    }

    private func save() {
        guard var ms = lifeStore.milestones.first(where: { $0.id == milestoneId }) else { dismiss(); return }
        let dep = BankDeposit(id: editing?.id ?? UUID(), date: date, amount: Double(amountText) ?? 0, currencyCode: currency)
        var list = ms.bankDeposits ?? []
        if let idx = list.firstIndex(where: { $0.id == dep.id }) { list[idx] = dep }
        else { list.append(dep) }
        ms.bankDeposits = list
        lifeStore.update(ms); dismiss()
    }

    private func delete() {
        guard let e = editing, var ms = lifeStore.milestones.first(where: { $0.id == milestoneId }) else { dismiss(); return }
        ms.bankDeposits?.removeAll { $0.id == e.id }
        lifeStore.update(ms); dismiss()
    }
}
