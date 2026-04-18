import SwiftUI

struct LifeOverviewView: View {
    @EnvironmentObject var store: LifeStore
    @EnvironmentObject var financeStore: FinanceStore
    @State private var showEditProfile = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProfileFlashCard(
                    profile: store.profile,
                    totalAssets: financeStore.totalAssets,
                    spouse: store.spouse,
                    onEdit: { showEditProfile = true }
                )
                .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 20) {
                        statsCard
                        milestoneTimelineSection
                        categoryBreakdownSection
                    }
                    .padding(.vertical)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("人生總覽")
            .sheet(isPresented: $showEditProfile) { EditProfileView() }
        }
    }

    // MARK: - 統計卡

    private var statsCard: some View {
        HStack(spacing: 12) {
            statBadge(title: "總里程碑", count: store.combinedMilestones(realEstates: financeStore.realEstates).count,
                      icon: "trophy.fill", color: .orange)
            statBadge(title: "本年新增", count: milestonesThisYear,
                      icon: "calendar.badge.plus", color: .green)
            statBadge(title: "分類數", count: usedCategories,
                      icon: "square.grid.2x2.fill", color: .blue)
        }
        .padding(.horizontal)
    }

    private func statBadge(title: String, count: Int, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text("\(count)").font(.title3.bold())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private var milestonesThisYear: Int {
        let year = Calendar.current.component(.year, from: Date())
        return store.combinedMilestones(realEstates: financeStore.realEstates).filter {
            Calendar.current.component(.year, from: $0.date) == year
        }.count
    }

    private var usedCategories: Int {
        Set(store.combinedMilestones(realEstates: financeStore.realEstates).map { $0.category }).count
    }

    // MARK: - 里程碑時間軸

    private var milestoneTimelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近里程碑").font(.headline).padding(.horizontal)

            let sorted = store.combinedMilestones(realEstates: financeStore.realEstates).sorted { $0.date > $1.date }
            let recent = Array(sorted.prefix(5))
            if recent.isEmpty {
                Text("暫無里程碑").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(recent) { m in
                        HStack {
                            Image(systemName: m.category.icon)
                                .frame(width: 30).foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.title).font(.subheadline)
                                Text(m.category.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatDate(m.date)).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal).padding(.vertical, 10)
                        if m.id != recent.last?.id { Divider().padding(.leading, 50) }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - 分類統計

    private var categoryBreakdownSection: some View {
        let grouped = Dictionary(grouping: store.combinedMilestones(realEstates: financeStore.realEstates), by: { $0.category })
        let entries = MilestoneCategory.allCases
            .compactMap { cat -> (MilestoneCategory, Int)? in
                guard let count = grouped[cat]?.count, count > 0 else { return nil }
                return (cat, count)
            }

        return Group {
            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("分類統計").font(.headline).padding(.horizontal)
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.0) { index, entry in
                            HStack {
                                Image(systemName: entry.0.icon)
                                    .frame(width: 30).foregroundStyle(.orange)
                                Text(entry.0.rawValue).font(.subheadline)
                                Spacer()
                                Text("\(entry.1) 筆").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal).padding(.vertical, 10)
                            if index < entries.count - 1 { Divider().padding(.leading, 50) }
                        }
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                    .padding(.horizontal)
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }
}
