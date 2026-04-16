import SwiftUI

struct SavingsInsuranceView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @State private var showAdd = false
    @State private var editingItem: SavingsInsurance?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader

                if store.insurances.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(store.insurances) { item in
                                insuranceCard(item)
                                    .onTapGesture { editingItem = item }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)
                        .padding(.bottom, 20)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("儲蓄險")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddSavingsInsuranceView() }
            .sheet(item: $editingItem) { item in AddSavingsInsuranceView(editing: item) }
        }
    }

    private var summaryHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("保單總價值")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(fmtTWD(store.totalInsuranceValue))
                    .font(.title2.bold())
            }
            Spacer()
            Text("\(store.insurances.count) 張保單")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "shield").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("尚無儲蓄險紀錄").font(.headline).foregroundStyle(.secondary)
            Text("點擊右上角 + 新增保單").font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private func insuranceCard(_ item: SavingsInsurance) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.name).font(.subheadline.weight(.semibold))
                        Text(item.currency.rawValue)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(item.currency == .usd ? Color.blue.opacity(0.12) : Color.green.opacity(0.12))
                            .foregroundStyle(item.currency == .usd ? .blue : .green)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if !item.company.isEmpty {
                        Text(item.company).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(fmt(item.currentValue, currency: item.currency))
                        .font(.subheadline.bold())
                    Text("目前價值").font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Divider()

            HStack {
                Label(item.paymentPeriod.rawValue + " " + fmt(item.premiumAmount, currency: item.currency), systemImage: "calendar")
                if item.annualRate > 0 {
                    Text(String(format: "%.2f%%", item.annualRate))
                        .foregroundStyle(.blue)
                }
                Spacer()
                Text("期滿 " + fmt(item.expectedReturn, currency: item.currency))
                    .foregroundStyle(.green)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        .contextMenu {
            Button(role: .destructive) {
                if let linkedId = item.linkedExpenseId {
                    expenseStore.expenses.removeAll { $0.id == linkedId }
                }
                store.deleteInsurance(item)
            } label: {
                Label("刪除", systemImage: "trash")
            }
        }
    }

    private func fmt(_ v: Double, currency: Currency) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencySymbol = currency.symbol
        f.maximumFractionDigits = currency == .usd ? 2 : 0
        return f.string(from: NSNumber(value: v)) ?? "\(currency.symbol)0"
    }

    private func fmtTWD(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }
}
