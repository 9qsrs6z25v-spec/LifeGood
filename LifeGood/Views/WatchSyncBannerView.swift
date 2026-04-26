import SwiftUI

/// 顯示在 iPhone App 主畫面頂端的橫幅，提示來自 Apple Watch 的新增支出 / 同步衝突。
/// 使用者可點開檢視並選擇處理。
struct WatchSyncBannerView: View {
    @ObservedObject private var coordinator = WatchSyncCoordinator.shared
    @EnvironmentObject var store: ExpenseStore
    @State private var showingDetail = false

    var body: some View {
        Group {
            if coordinator.hasPending {
                Button {
                    showingDetail = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "applewatch")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(headlineText)
                                .font(.subheadline.weight(.semibold))
                            Text(subText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.green.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: coordinator.hasPending)
        .sheet(isPresented: $showingDetail) {
            WatchSyncDetailSheet()
                .environmentObject(store)
        }
    }

    private var headlineText: String {
        let addCount = coordinator.pendingAdditions.count
        let conflictCount = coordinator.pendingConflicts.count
        if addCount > 0 && conflictCount > 0 {
            return "Apple Watch：\(addCount) 筆新增、\(conflictCount) 筆衝突"
        } else if addCount > 0 {
            return "Apple Watch 新增 \(addCount) 筆支出"
        } else {
            return "已自動解決 \(conflictCount) 筆同步衝突"
        }
    }

    private var subText: String {
        if !coordinator.pendingAdditions.isEmpty {
            return "點選檢視 / 移除"
        }
        return "點選檢視，或還原本機版本"
    }
}

// MARK: - Detail Sheet

struct WatchSyncDetailSheet: View {
    @EnvironmentObject var store: ExpenseStore
    @ObservedObject private var coordinator = WatchSyncCoordinator.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !coordinator.pendingAdditions.isEmpty {
                    Section("Apple Watch 新增") {
                        ForEach(coordinator.pendingAdditions) { expense in
                            additionRow(expense)
                        }
                    }
                }

                if !coordinator.pendingConflicts.isEmpty {
                    Section("已自動採用較新版本") {
                        ForEach(coordinator.pendingConflicts) { conflict in
                            conflictRow(conflict)
                        }
                    }
                }

                if !coordinator.hasPending {
                    Text("沒有待處理項目")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("手錶同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("全部關閉") {
                        coordinator.dismissAllAdditions()
                        coordinator.dismissAllConflicts()
                        dismiss()
                    }
                    .disabled(!coordinator.hasPending)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func additionRow(_ expense: Expense) -> some View {
        HStack {
            Image(systemName: expense.categoryIcon)
                .foregroundStyle(.green)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title.isEmpty ? expense.categoryName : expense.title)
                    .font(.body)
                Text("\(expense.currencyCode) \(formatted(expense.amount))  ·  \(formatted(date: expense.date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                store.removeById(expense.id)
                coordinator.dismissAddition(expense)
            } label: {
                Text("移除")
            }
            .buttonStyle(.bordered)
        }
    }

    private func conflictRow(_ conflict: ExpenseConflict) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("採用版本：\(conflict.winner.title) · \(conflict.winner.currencyCode) \(formatted(conflict.winner.amount))")
                .font(.subheadline.weight(.semibold))
            Text("來源：\(conflict.winner.sourceDevice ?? "未知")  ·  \(formatted(date: conflict.winner.updatedAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text("本機原版：\(conflict.loser.title) · \(conflict.loser.currencyCode) \(formatted(conflict.loser.amount))")
                .font(.caption)
            HStack {
                Spacer()
                Button {
                    store.revertTo(conflict.loser)
                    coordinator.dismissConflict(conflict)
                } label: {
                    Text("還原本機版本")
                }
                .buttonStyle(.bordered)
                Button {
                    coordinator.dismissConflict(conflict)
                } label: {
                    Text("保留")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatted(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: amount)) ?? String(amount)
    }

    private func formatted(date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: date)
    }
}
