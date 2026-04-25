import SwiftUI

struct LifeFinanceView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @State private var selectedSub: FinanceSubCategory?
    @State private var viewingItem: LifeMilestone?
    @State private var showAdd = false

    private var financeMilestones: [LifeMilestone] {
        lifeStore.milestones
            .filter { $0.category == .achievement }
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

    private var milestoneList: some View {
        List {
            ForEach(filteredMilestones) { item in
                milestoneRow(item)
                    .contentShape(Rectangle())
                    .onTapGesture { viewingItem = item }
            }
        }
        .listStyle(.insetGrouped)
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
            Text(formatDate(item.date)).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
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
                    if sub == .bank { depositSection }
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

    private var deposits: [BankDeposit] {
        (item.bankDeposits ?? []).sorted { $0.date < $1.date }
    }

    private var depositSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "dollarsign.circle.fill").foregroundStyle(.blue)
                Text("銀行存款").font(.headline)
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

                ForEach(deposits, id: \.id) { dep in
                    depositRow(dep)
                }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func depositRow(_ dep: BankDeposit) -> some View {
        Button {
            editingDeposit = dep
        } label: {
            HStack {
                Text(fmtDate(dep.date)).font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Text("\(dep.currencyCode) \(fmtNum(dep.amount))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(dep.currencyCode == "NT$" ? .primary : .blue)
            }
            .padding(.horizontal).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var depositChart: some View {
        let data = deposits
        let maxAmount = data.map(\.amount).max() ?? 1

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(data, id: \.id) { dep in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(dep.currencyCode == "NT$" ? Color.blue : Color.orange)
                            .frame(
                                width: max(12, (UIScreen.main.bounds.width - 80) / CGFloat(max(data.count, 1))),
                                height: max(4, CGFloat(dep.amount / maxAmount) * 120)
                            )
                        Text(shortDate(dep.date))
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(height: 140, alignment: .bottom)
            .frame(maxWidth: .infinity)
        }
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: date)
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
