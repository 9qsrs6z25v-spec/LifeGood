import SwiftUI

struct LifeOverviewView: View {
    @EnvironmentObject var store: LifeStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showEditProfile = false
    @State private var showAddVariable = false
    @State private var showAddFixed = false
    @State private var showAddStock = false
    @State private var showAddRealEstate = false
    @State private var showPremiumAlert = false

    var body: some View {
        // 計算一次，避免 statsCard / milestoneTimeline / categoryBreakdown 各自重算（共 5 次）
        let allMS = store.combinedMilestones(realEstates: financeStore.realEstates)
        return NavigationStack {
            VStack(spacing: 0) {
                ProfileFlashCard(
                    profile: store.profile,
                    totalAssets: financeStore.totalAssets,
                    spouse: store.spouse,
                    onEdit: {
                        if subscription.isPremium { showEditProfile = true }
                        else { showPremiumAlert = true }
                    }
                )
                .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 20) {
                        statsCard(allMS)
                        milestoneTimelineSection(allMS)
                        categoryBreakdownSection(allMS)
                    }
                    .padding(.vertical)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("人生總覽")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    quickAddMenu
                }
            }
            .sheet(isPresented: $showEditProfile) { EditProfileView() }
            .sheet(isPresented: $showAddVariable) { AddExpenseView(expenseType: .variable) }
            .sheet(isPresented: $showAddFixed) { AddExpenseView(expenseType: .fixed) }
            .sheet(isPresented: $showAddStock) { AddStockView() }
            .sheet(isPresented: $showAddRealEstate) { AddRealEstateView() }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    private var quickAddMenu: some View {
        Menu {
            // 記帳與股票為免費功能
            Button { showAddVariable = true } label: { Label("變動支出", systemImage: "arrow.up.arrow.down.circle.fill") }
            Button { showAddFixed = true } label: { Label("固定支出", systemImage: "pin.circle.fill") }
            Button { showAddStock = true } label: { Label("股票", systemImage: "chart.line.uptrend.xyaxis") }
            // 房地產需訂閱
            Button {
                if subscription.isPremium { showAddRealEstate = true }
                else { showPremiumAlert = true }
            } label: { Label("房地產", systemImage: "building.2.fill") }
        } label: {
            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
        }
    }

    // MARK: - 里程碑分類色彩

    private func milestoneColor(_ cat: MilestoneCategory) -> Color {
        switch cat {
        case .marriage:    return Color(red: 1.00, green: 0.40, blue: 0.60)
        case .family:      return Color(red: 1.00, green: 0.60, blue: 0.20)
        case .realEstate:  return Color(red: 0.42, green: 0.58, blue: 0.80)
        case .career:      return Color(red: 0.25, green: 0.60, blue: 0.95)
        case .education:   return Color(red: 0.45, green: 0.75, blue: 0.40)
        case .achievement: return Color(red: 0.20, green: 0.78, blue: 0.55)
        case .travel:      return Color(red: 0.55, green: 0.35, blue: 0.95)
        case .pet:         return Color(red: 0.90, green: 0.50, blue: 0.20)
        case .health:      return Color(red: 0.95, green: 0.28, blue: 0.32)
        case .other:       return Color.secondary
        }
    }

    // MARK: - 統計卡

    private func statsCard(_ allMS: [LifeMilestone]) -> some View {
        HStack(spacing: 12) {
            statBadge(title: "總里程碑",
                      count: allMS.count,
                      icon: "trophy.fill", color: .orange)
            statBadge(title: "本年新增", count: milestonesThisYear(allMS),
                      icon: "calendar.badge.plus", color: .green)
            statBadge(title: "分類數", count: usedCategories(allMS),
                      icon: "square.grid.2x2.fill", color: .blue)
        }
        .padding(.horizontal)
    }

    private func statBadge(title: String, count: Int, icon: String, color: Color) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.14))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text("\(count)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: color.opacity(0.14), radius: 10, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    private func milestonesThisYear(_ allMS: [LifeMilestone]) -> Int {
        let year = Calendar.current.component(.year, from: Date())
        return allMS.filter {
            Calendar.current.component(.year, from: $0.date) == year
        }.count
    }

    private func usedCategories(_ allMS: [LifeMilestone]) -> Int {
        Set(allMS.map { $0.category }).count
    }

    // MARK: - 里程碑時間軸

    private func milestoneTimelineSection(_ allMS: [LifeMilestone]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .orange.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Text("最近里程碑")
                    .font(.subheadline.weight(.bold))
                Spacer()
            }
            .padding(.horizontal)

            let sorted = allMS.sorted { $0.date > $1.date }
            let recent = Array(sorted.prefix(5))
            if recent.isEmpty {
                emptyMilestonePlaceholder
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { idx, m in
                        let accent = milestoneColor(m.category)
                        HStack(alignment: .center, spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(accent.opacity(0.14))
                                    .frame(width: 40, height: 40)
                                Image(systemName: m.category.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(m.category.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatDate(m.date))
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.secondarySystemFill))
                                .clipShape(Capsule())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        if idx < recent.count - 1 {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                .padding(.horizontal)
            }
        }
    }

    private var emptyMilestonePlaceholder: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.systemFill))
                    .frame(width: 64, height: 64)
                Image(systemName: "trophy")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.secondary)
            }
            Text("暫無里程碑")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("新增生命中的重要時刻")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        .padding(.horizontal)
    }

    // MARK: - 分類統計

    private func categoryBreakdownSection(_ allMS: [LifeMilestone]) -> some View {
        let grouped = Dictionary(grouping: allMS, by: { $0.category })
        let entries = MilestoneCategory.allCases
            .compactMap { cat -> (MilestoneCategory, Int)? in
                guard let count = grouped[cat]?.count, count > 0 else { return nil }
                return (cat, count)
            }
        let maxCount = entries.map(\.1).max() ?? 1

        return Group {
            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .blue.opacity(0.55)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .frame(width: 4, height: 18)
                        Text("分類統計")
                            .font(.subheadline.weight(.bold))
                        Spacer()
                    }
                    .padding(.horizontal)

                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.0) { index, entry in
                            let accent = milestoneColor(entry.0)
                            let ratio = maxCount > 0 ? Double(entry.1) / Double(maxCount) : 0

                            VStack(spacing: 8) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(accent.opacity(0.14))
                                            .frame(width: 36, height: 36)
                                        Image(systemName: entry.0.icon)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(accent)
                                    }
                                    Text(entry.0.displayName)
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(entry.1) 筆")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(accent)
                                }

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color(.systemFill))
                                            .frame(height: 5)
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [accent, accent.opacity(0.65)],
                                                    startPoint: .leading, endPoint: .trailing
                                                )
                                            )
                                            .frame(width: geo.size.width * ratio, height: 5)
                                            .animation(.spring(response: 0.6, dampingFraction: 0.78), value: ratio)
                                    }
                                }
                                .frame(height: 5)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            if index < entries.count - 1 {
                                Divider().padding(.leading, 64)
                            }
                        }
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                    .padding(.horizontal)
                }
            }
        }
    }

    private static let milestoneDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/M/d"
        return f
    }()

    private func formatDate(_ date: Date) -> String {
        Self.milestoneDateFormatter.string(from: date)
    }
}
