import SwiftUI

struct SavingsInsuranceView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var editingItem: SavingsInsurance?
    @State private var showPremiumAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader

                if store.insurances.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.insurances) { item in
                            insuranceCard(item)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .onTapGesture {
                                    if subscription.isPremium { editingItem = item }
                                    else { showPremiumAlert = true }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        if subscription.isPremium {
                                            if let linkedId = item.linkedExpenseId {
                                                expenseStore.expenses.removeAll { $0.id == linkedId }
                                            }
                                            store.deleteInsurance(item)
                                        } else {
                                            showPremiumAlert = true
                                        }
                                    } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .background(Color(.systemGroupedBackground))
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("儲蓄險")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if subscription.isPremium { showAdd = true }
                        else { showPremiumAlert = true }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddSavingsInsuranceView() }
            .sheet(item: $editingItem) { item in AddSavingsInsuranceView(editing: item) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    private var summaryHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Text("保單總覽")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(store.insurances.count) 張保單")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            // 依幣別分組顯示
            let grouped = Dictionary(grouping: store.insurances, by: { $0.currencyCode })
            let codes = grouped.keys.sorted { a, b in
                if a == "NT$" { return true }
                if b == "NT$" { return false }
                return a < b
            }
            ForEach(codes, id: \.self) { code in
                if let items = grouped[code], !items.isEmpty {
                    let totalCurrent = items.reduce(0) { $0 + $1.currentValue }
                    let totalPaid = items.reduce(0) { $0 + $1.totalPaid }
                    let gain = totalCurrent - totalPaid
                    let gainRate = totalPaid > 0 ? gain / totalPaid * 100 : 0

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("目前價值 (\(code))")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(fmtSmart(totalCurrent, code: code))
                                .font(.title3.bold())
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("已繳總額")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(fmtSmart(totalPaid, code: code))
                                .font(.subheadline)
                        }
                    }

                    HStack {
                        let isPositive = gain >= 0
                        Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption).foregroundStyle(isPositive ? .green : .red)
                        Text((isPositive ? "+" : "") + fmtSmart(gain, code: code))
                            .font(.caption.bold()).foregroundStyle(isPositive ? .green : .red)
                        Text(String(format: "(%@%.2f%%)", isPositive ? "+" : "", gainRate))
                            .font(.caption2).foregroundStyle(isPositive ? .green : .red)
                        Spacer()
                    }
                    .padding(8)
                    .background((gain >= 0 ? Color.green : Color.red).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
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
        let isNT = item.currencyCode == "NT$"
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.name).font(.subheadline.weight(.semibold))
                        Text(item.currencyCode)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(isNT ? Color.green.opacity(0.12) : Color.blue.opacity(0.12))
                            .foregroundStyle(isNT ? .green : .blue)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if !item.company.isEmpty {
                        Text(item.company).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(fmtSmart(item.currentValue, code: item.currencyCode))
                        .font(.subheadline.bold())
                    Text("目前價值").font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Divider()

            HStack {
                Label(item.paymentPeriod.rawValue + " " + fmtSmart(item.premiumAmount, code: item.currencyCode), systemImage: "calendar")
                if item.annualRate > 0 {
                    Text(String(format: "%.2f%%", item.annualRate))
                        .foregroundStyle(.blue)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(item.elapsedPeriods)/\(item.totalPeriods) 期")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text("期滿 " + fmtSmart(item.expectedReturn, code: item.currencyCode))
                        .foregroundStyle(.green)
                }
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
    }

    private func fmt(_ v: Double, code: String) -> String {
        let isUSD = code == "US$" || code == "USD" || code.lowercased() == "美金"
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencySymbol = code
        f.maximumFractionDigits = isUSD ? 2 : 0
        return f.string(from: NSNumber(value: v)) ?? "\(code)0"
    }

    private func fmtSmart(_ v: Double, code: String) -> String {
        let isUSD = code == "US$" || code == "USD" || code.lowercased() == "美金"
        let absV = abs(v)
        let sign = v < 0 ? "-" : ""
        if !isUSD && absV >= 10_000 {
            return "\(sign)\(code)\(String(format: "%.1f", absV / 10_000))萬"
        }
        return fmt(v, code: code)
    }
}
