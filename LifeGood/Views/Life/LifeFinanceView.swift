import SwiftUI

struct LifeFinanceView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @State private var selectedSub: FinanceSubCategory?
    @State private var editingItem: LifeMilestone?

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
            .sheet(item: $editingItem) { item in
                AddMilestoneView(editing: item)
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
                        Image(systemName: sub.icon)
                            .font(.title3).foregroundStyle(colorFor(sub))
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
                chipButton(label: "全部", isSelected: selectedSub == nil) {
                    selectedSub = nil
                }
                ForEach(FinanceSubCategory.allCases) { sub in
                    let count = financeMilestones.filter { $0.financeSubCategory == sub }.count
                    if count > 0 {
                        chipButton(label: "\(sub.rawValue) \(count)", isSelected: selectedSub == sub) {
                            selectedSub = sub
                        }
                    }
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    private func chipButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
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
                    .onTapGesture { editingItem = item }
            }
            .onDelete { offsets in
                let items = offsets.map { filteredMilestones[$0] }
                items.forEach { lifeStore.deleteMilestone($0) }
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

            Text(formatDate(item.date))
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func subtitle(for item: LifeMilestone) -> some View {
        switch item.financeSubCategory {
        case .bank:
            let parts = [item.branchName, item.bankAccountType?.rawValue].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty {
                Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        case .creditCard:
            let parts = [item.cardName, item.cardLastFour.map { "末\($0)" }].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty {
                Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        case .securities:
            if let accType = item.securitiesAccountType {
                Text(accType.rawValue).font(.caption).foregroundStyle(.secondary)
            }
        case .insurance:
            let parts = [item.insuranceType?.rawValue, item.policyNumber].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty {
                Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        case .none:
            if !item.note.isEmpty {
                Text(item.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func colorFor(_ sub: FinanceSubCategory) -> Color {
        switch sub {
        case .bank: return .blue
        case .creditCard: return .orange
        case .securities: return .green
        case .insurance: return .purple
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }
}
