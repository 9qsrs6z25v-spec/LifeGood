import SwiftUI

struct RealEstateDetailView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    let estate: RealEstate
    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    private var rarity: CardRarity { CardRarity.realEstate(price: estate.purchasePrice) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    flashCard
                    infoSection
                    actionSection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("房地產卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
            }
            .sheet(isPresented: $showEdit) {
                AddRealEstateView(editing: estate)
            }
            .alert("確定要刪除這筆房地產嗎？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) {
                    deleteEstate()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("刪除後所有連結的記帳支出也會一併移除，此操作無法復原。")
            }
        }
    }

    // MARK: - 閃卡主體

    private var flashCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(rarity.label)
                    .font(.caption2.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(rarity.textColor)
                Spacer()
                Label("房地產", systemImage: "building.2.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(rarity == .legendary ? .yellow : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            VStack(spacing: 6) {
                Text(estate.name)
                    .font(.title.weight(.bold))
                    .foregroundStyle(rarity == .legendary ? .white : .primary)
                    .multilineTextAlignment(.center)

                if !estate.fullAddress.isEmpty {
                    Text(estate.fullAddress)
                        .font(.subheadline)
                        .foregroundStyle(rarity == .legendary ? .white.opacity(0.7) : .secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 24)

            VStack(spacing: 4) {
                Text("\(fmtWan(estate.currentValue))")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(rarity.textColor)
                Text("萬元")
                    .font(.subheadline)
                    .foregroundStyle(rarity == .legendary ? .white.opacity(0.6) : .secondary)
            }
            .padding(.vertical, 20)

            HStack {
                VStack(spacing: 2) {
                    Text("購入")
                        .font(.caption2).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text("\(fmtWan(estate.purchasePrice)) 萬")
                        .font(.caption.bold()).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.8) : Color.primary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("增值率")
                        .font(.caption2).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text(String(format: "%@%.1f%%", estate.appreciationRate >= 0 ? "+" : "", estate.appreciationRate))
                        .font(.caption.bold()).foregroundStyle(estate.appreciationRate >= 0 ? .green : .red)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("月租")
                        .font(.caption2).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text(estate.monthlyRental > 0 ? fmt(estate.monthlyRental) : "—")
                        .font(.caption.bold()).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.8) : Color.primary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(
            LinearGradient(colors: rarity.bgGradient,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    AngularGradient(colors: rarity.borderGradient, center: .center),
                    lineWidth: rarity.borderWidth
                )
        )
        .shadow(color: rarity.shadowColor, radius: rarity == .legendary ? 15 : 8, y: 4)
        .overlay(alignment: .topLeading) {
            if estate.isSold {
                SoldStamp(size: 32)
                    .offset(x: -10, y: -14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - 詳細資訊

    private var infoSection: some View {
        VStack(spacing: 0) {
            if !estate.mortgageItems.isEmpty {
                sectionHeader("貸款明細")
                ForEach(estate.mortgageItems) { m in
                    HStack {
                        Text(m.title.isEmpty ? "房貸" : m.title)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text("\(m.elapsedPeriods)/\(m.totalPeriods) 期")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(fmt(m.amount) + "/月").font(.subheadline.bold())
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
                HStack {
                    Text("已繳貸款").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(fmt(estate.totalMortgagePaid))
                        .font(.subheadline.bold()).foregroundStyle(.blue)
                }
                .padding(.horizontal).padding(.vertical, 6)
            }

            if !estate.paidItems.isEmpty {
                sectionHeader("已支出")
                ForEach(estate.paidItems) { p in
                    HStack {
                        Text(p.title.isEmpty ? "已付款" : p.title)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.purple.opacity(0.1))
                            .foregroundStyle(.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Spacer()
                        Text(fmt(p.amount)).font(.subheadline.bold())
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
            }

            if !estate.variableExpenses.isEmpty {
                sectionHeader("變動支出")
                ForEach(estate.variableExpenses) { ve in
                    HStack {
                        Text(ve.category.rawValue)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Spacer()
                        Text(fmt(ve.amount)).font(.subheadline.bold())
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
            }

            if estate.monthlyRental > 0 {
                sectionHeader("收益")
                HStack {
                    Text("月淨現金流").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    let flow = estate.monthlyCashFlow
                    Text(fmt(flow))
                        .font(.subheadline.bold())
                        .foregroundStyle(flow >= 0 ? .green : .red)
                }
                .padding(.horizontal).padding(.vertical, 8)
                HStack {
                    Text("年租金報酬率").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2f%%", estate.rentalYield))
                        .font(.subheadline.bold()).foregroundStyle(.blue)
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
        }
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - 操作按鈕

    private var actionSection: some View {
        VStack(spacing: 12) {
            Button {
                showEdit = true
            } label: {
                Label("編輯", systemImage: "pencil")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                showDeleteConfirm = true
            } label: {
                Label("刪除", systemImage: "trash")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red.opacity(0.1))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal)
    }

    // MARK: - 輔助

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal).padding(.top, 12).padding(.bottom, 4)
    }

    private func deleteEstate() {
        for m in estate.mortgageItems {
            if let linkedId = m.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == linkedId }
            }
        }
        for p in estate.paidItems {
            if let linkedId = p.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == linkedId }
            }
        }
        for ve in estate.variableExpenses {
            if let linkedId = ve.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == linkedId }
            }
        }
        if let linkedId = estate.linkedExpenseId {
            expenseStore.expenses.removeAll { $0.id == linkedId }
        }
        store.deleteRealEstate(estate)
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    private func fmtWan(_ v: Double) -> String {
        String(format: "%g", v / 10000)
    }
}
