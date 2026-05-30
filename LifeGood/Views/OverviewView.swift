import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var store: ExpenseStore

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "TWD"
        f.currencySymbol = "NT$"
        f.maximumFractionDigits = 0
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    monthlyTotalCard

                    HStack(spacing: 12) {
                        summaryCard(
                            title: "變動支出",
                            amount: store.currentMonthVariableTotal,
                            icon: "arrow.up.arrow.down.circle.fill",
                            color: .orange
                        )
                        summaryCard(
                            title: "固定支出",
                            amount: store.currentMonthFixedTotal,
                            icon: "pin.circle.fill",
                            color: .blue
                        )
                    }
                    .padding(.horizontal)

                    todayCard
                    categoryBreakdownSection
                    recentTransactionsSection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("總覽")
        }
    }

    // MARK: - 本月總支出

    private var monthlyTotalCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label(currentMonthString(), systemImage: "calendar")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                let count = store.currentMonthExpenses.count
                Text("\(count) 筆交易")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.18))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            VStack(spacing: 6) {
                Text("本月總支出")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))

                Text(formatCurrency(store.currentMonthTotal))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }
            .padding(.vertical, 22)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.80, blue: 0.48),
                    Color(red: 0.00, green: 0.58, blue: 0.55)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(
            color: Color(red: 0.0, green: 0.65, blue: 0.45).opacity(0.38),
            radius: 18, x: 0, y: 8
        )
        .padding(.horizontal)
    }

    // MARK: - 摘要卡片

    private func summaryCard(title: String, amount: Double, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(formatCurrency(amount))
                .font(.title3.bold())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
    }

    // MARK: - 今日花費

    private var todayCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "sun.max.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 46, height: 46)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text("今日花費")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(formatCurrency(store.todayTotal))
                    .font(.title2.bold())
            }

            Spacer()

            Text(todayDateString())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - 分類支出

    private var categoryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("本月變動支出分類")

            let categoryTotals = store.variableCategoryTotals()
            let maxAmount = categoryTotals.map(\.amount).max() ?? 1

            if categoryTotals.isEmpty {
                emptyState(icon: "chart.pie", message: "尚無分類資料")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(categoryTotals.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Image(systemName: item.category.icon)
                                    .font(.subheadline)
                                    .foregroundStyle(.green)
                                    .frame(width: 36, height: 36)
                                    .background(Color.green.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 9))

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.category.rawValue)
                                        .font(.subheadline.weight(.medium))
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule()
                                                .fill(Color(.systemGray5))
                                                .frame(height: 4)
                                            Capsule()
                                                .fill(Color.green.opacity(0.7))
                                                .frame(
                                                    width: geo.size.width * CGFloat(item.amount / maxAmount),
                                                    height: 4
                                                )
                                        }
                                    }
                                    .frame(height: 4)
                                }

                                Spacer()

                                Text(formatCurrency(item.amount))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)

                            if index < categoryTotals.count - 1 {
                                Divider().padding(.leading, 64)
                            }
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - 最近交易

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("最近交易")

            let recent = Array(store.expenses.sorted { $0.date > $1.date }.prefix(5))

            if recent.isEmpty {
                emptyState(icon: "list.bullet.clipboard", message: "尚無交易紀錄")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.offset) { index, expense in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Image(systemName: expense.categoryIcon)
                                    .font(.subheadline)
                                    .foregroundStyle(.green)
                                    .frame(width: 36, height: 36)
                                    .background(Color.green.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 9))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(expense.title)
                                        .font(.subheadline.weight(.medium))
                                    Text(expense.categoryName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(formatCurrency(expense.amount))
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    Text(formatDate(expense.date))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)

                            if index < recent.count - 1 {
                                Divider().padding(.leading, 64)
                            }
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Shared UI Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .padding(.horizontal)
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Color(.systemGray3))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? "NT$0"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private func currentMonthString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: Date())
    }

    private func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: Date())
    }
}

#Preview {
    OverviewView()
        .environmentObject(ExpenseStore())
}
