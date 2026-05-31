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
    @State private var timelineRowsAppeared = false
    @State private var categoryRowsAppeared = false

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
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.20), color.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                Circle()
                    .stroke(color.opacity(0.22), lineWidth: 1.5)
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text("\(count)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            ZStack {
                Color(.systemBackground)
                color.opacity(0.03)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.12), lineWidth: 0.75)
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
        let sorted = allMS.sorted { $0.date > $1.date }
        let recent = Array(sorted.prefix(5))

        return VStack(alignment: .leading, spacing: 12) {
            // 區塊標題
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
                if !recent.isEmpty {
                    Text("\(recent.count) / \(allMS.count) 筆")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)

            if recent.isEmpty {
                emptyMilestonePlaceholder
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { idx, m in
                        let accent = milestoneColor(m.category)

                        HStack(alignment: .center, spacing: 0) {
                            // 左側彩色強調條（每個分類獨立顏色）
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        colors: [accent, accent.opacity(0.45)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                .frame(width: 3)
                                .padding(.vertical, 10)
                                .padding(.trailing, 14)

                            // 分類圖示圓（帶漸層 + 細邊框）
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [accent.opacity(0.22), accent.opacity(0.08)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 40, height: 40)
                                Circle()
                                    .stroke(accent.opacity(0.28), lineWidth: 1.5)
                                    .frame(width: 40, height: 40)
                                Image(systemName: m.category.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(accent)
                            }
                            .padding(.trailing, 12)

                            // 標題 + 分類徽章 + 日期
                            VStack(alignment: .leading, spacing: 5) {
                                Text(m.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    // 彩色分類膠囊徽章
                                    Text(m.category.displayName)
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(accent.opacity(0.13))
                                        .foregroundStyle(accent)
                                        .clipShape(Capsule())
                                    Text(formatDate(m.date))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer(minLength: 8)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        // 錯落進場動畫：從左滑入 + 淡入
                        .opacity(timelineRowsAppeared ? 1 : 0)
                        .offset(x: timelineRowsAppeared ? 0 : -18)
                        .animation(
                            .spring(response: 0.48, dampingFraction: 0.80)
                                .delay(0.07 * Double(idx)),
                            value: timelineRowsAppeared
                        )

                        if idx < recent.count - 1 {
                            Rectangle()
                                .fill(Color(.separator).opacity(0.20))
                                .frame(height: 0.5)
                                .padding(.leading, 16 + 3 + 14 + 40 + 12) // 對齊左側強調條右緣後文字區
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                .padding(.horizontal)
                .onAppear {
                    withAnimation { timelineRowsAppeared = true }
                }
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
                        Text("\(entries.count) 類")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
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
                                            .fill(
                                                LinearGradient(
                                                    colors: [accent.opacity(0.20), accent.opacity(0.08)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 36, height: 36)
                                        Circle()
                                            .stroke(accent.opacity(0.22), lineWidth: 1)
                                            .frame(width: 36, height: 36)
                                        Image(systemName: entry.0.icon)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(accent)
                                    }
                                    Text(entry.0.displayName)
                                        .font(.subheadline)
                                    Spacer()
                                    // 筆數徽章
                                    Text("\(entry.1) 筆")
                                        .font(.system(size: 12, weight: .bold))
                                        .padding(.horizontal, 9).padding(.vertical, 4)
                                        .background(accent.opacity(0.12))
                                        .foregroundStyle(accent)
                                        .clipShape(Capsule())
                                }

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color(.systemFill))
                                            .frame(height: 5)
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [accent, accent.opacity(0.60)],
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
                            // 錯落淡入動畫
                            .opacity(categoryRowsAppeared ? 1 : 0)
                            .offset(y: categoryRowsAppeared ? 0 : 12)
                            .animation(
                                .spring(response: 0.48, dampingFraction: 0.80)
                                    .delay(0.06 * Double(index)),
                                value: categoryRowsAppeared
                            )

                            if index < entries.count - 1 {
                                Divider().padding(.leading, 64)
                            }
                        }
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                    .padding(.horizontal)
                    .onAppear {
                        withAnimation { categoryRowsAppeared = true }
                    }
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
