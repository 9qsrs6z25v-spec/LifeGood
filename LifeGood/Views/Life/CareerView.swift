import SwiftUI

// MARK: - 美化紀錄（CareerView）
// [2026-06] 本次美化方向：
//   1. summaryCard：加入彩色頂端 Capsule 條 + 漸層圖示圓（對齊 OverviewView.summaryCard 規格）
//   2. statCard：加入漸層圖示圓（LinearGradient + stroke）+ 細邊框 + 雙層陰影（對齊 LifeOverviewView.statBadge 規格）
//   3. dashboardSection：加入錯落進場動畫（對齊 OverviewView summaryCard onAppear 規格）
//   4. subCategoryBreakdown 區塊標題：Capsule 側條 + 分類數膠囊（對齊 milestoneTimelineSection 標題規格）
//   5. subCategoryBreakdown 列：漸層圖示圓 + 計數膠囊 + mini 比例進度條 + 交錯進場動畫
//   6. milestoneListSection 區塊標題：Capsule 側條 + 里程碑計數膠囊（對齊統一 section header 規格）
//   7. careerRow：左側 4pt 分類色彩強調條 + 44pt 漸層圖示圓 + 陰影（對齊 ExpenseRow 規格）
//   8. 空狀態：雙層脈衝光環 + 漸層底圓 + icon + 說明文字（對齊 VariableExpenseView emptyStateView 規格）
//   9. milestoneListSection：加入交錯淡入 + 向上進場動畫（對齊 FamilyView 規格）

struct CareerView: View {
    @EnvironmentObject var store: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var editingItem: LifeMilestone?
    @State private var showAdd = false
    @State private var selectedSub: CareerSubCategory?
    @State private var showPremiumAlert = false

    // 進場動畫旗標
    @State private var dashboardAppeared = false
    @State private var subCatRowsAppeared = false
    @State private var milestoneRowsAppeared = false
    @State private var emptyIconPulse = false

    private var careerMilestones: [LifeMilestone] {
        store.milestones
            .filter { $0.category == .career }
            .sorted { $0.date > $1.date }
    }

    private var filtered: [LifeMilestone] {
        guard let sub = selectedSub else { return careerMilestones }
        return careerMilestones.filter { $0.careerSubCategory == sub }
    }

    private var currentCompany: String? {
        // 以最近一筆入職為基準，若之後有對應離職則視為已離職
        let sorted = careerMilestones
        guard let latestJoin = sorted.first(where: { $0.careerSubCategory == .join && !($0.companyName ?? "").isEmpty }) else {
            return nil
        }
        if sorted.first(where: { $0.careerSubCategory == .resign && $0.date > latestJoin.date }) != nil {
            return nil
        }
        return latestJoin.companyName
    }

    private var currentPosition: String? {
        // 最新一筆有 jobTitle 的里程碑（入職/升職/轉職/降職）
        careerMilestones.first(where: {
            let sub = $0.careerSubCategory
            return (sub == .join || sub == .promote || sub == .transfer || sub == .demote)
                && !($0.jobTitle ?? "").isEmpty
        })?.jobTitle
    }

    private var totalCompanies: Int {
        let names = careerMilestones
            .filter { $0.careerSubCategory == .join }
            .compactMap { $0.companyName?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Set(names).count
    }

    private var yearsAtCurrentCompany: Double? {
        guard currentCompany != nil else { return nil }
        guard let latestJoin = careerMilestones.first(where: { $0.careerSubCategory == .join && !($0.companyName ?? "").isEmpty }) else {
            return nil
        }
        let days = Calendar.current.dateComponents([.day], from: latestJoin.date, to: Date()).day ?? 0
        return max(0, Double(days) / 365.0)
    }

    private var subCounts: [CareerSubCategory: Int] {
        var dict: [CareerSubCategory: Int] = [:]
        for m in careerMilestones {
            if let s = m.careerSubCategory { dict[s, default: 0] += 1 }
        }
        return dict
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    dashboardSection
                    subCategoryBreakdown
                    milestoneListSection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("職涯")
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
            .sheet(isPresented: $showAdd) { AddMilestoneView(initialCategory: .career) }
            .sheet(item: $editingItem) { item in AddMilestoneView(editing: item) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    // MARK: - 看板

    private var dashboardSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                summaryCard(title: "目前公司", value: currentCompany ?? "—",
                            icon: "building.2.fill", color: .blue, delay: 0.06)
                summaryCard(title: "目前職位", value: currentPosition ?? "—",
                            icon: "person.badge.key.fill", color: .indigo, delay: 0.12)
            }
            HStack(spacing: 12) {
                statCard(title: "任職年資",
                         value: yearsAtCurrentCompany.map { String(format: "%.1f 年", $0) } ?? "—",
                         icon: "clock.fill", color: .orange, delay: 0.18)
                statCard(title: "任職公司數", value: "\(totalCompanies)",
                         icon: "building.columns.fill", color: .teal, delay: 0.24)
                statCard(title: "職涯里程碑", value: "\(careerMilestones.count)",
                         icon: "trophy.fill", color: Color(red: 1.00, green: 0.72, blue: 0.18), delay: 0.30)
            }
        }
        .padding(.horizontal)
        .onAppear {
            withAnimation { dashboardAppeared = true }
        }
    }

    /// summaryCard：彩色頂端 Capsule 條 + 漸層圖示圓，對齊 OverviewView.summaryCard
    private func summaryCard(title: String, value: String, icon: String, color: Color, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 彩色頂端條
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 4)
                .padding(.bottom, 10)

            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.16))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(value)
                .font(.subheadline.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(
            ZStack {
                Color(.systemBackground)
                color.opacity(0.04)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: color.opacity(0.13), radius: 10, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
        .opacity(dashboardAppeared ? 1 : 0)
        .offset(y: dashboardAppeared ? 0 : 18)
        .animation(.spring(response: 0.50, dampingFraction: 0.78).delay(delay), value: dashboardAppeared)
    }

    /// statCard：漸層圖示圓 + 細邊框，對齊 LifeOverviewView.statBadge 規格
    private func statCard(title: String, value: String, icon: String, color: Color, delay: Double) -> some View {
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
                    .frame(width: 44, height: 44)
                Circle()
                    .stroke(color.opacity(0.22), lineWidth: 1.5)
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
        .opacity(dashboardAppeared ? 1 : 0)
        .offset(y: dashboardAppeared ? 0 : 18)
        .animation(.spring(response: 0.50, dampingFraction: 0.78).delay(delay), value: dashboardAppeared)
    }

    // MARK: - 子分類統計

    @ViewBuilder
    private var subCategoryBreakdown: some View {
        let validSubs = CareerSubCategory.allCases.filter { subCounts[$0, default: 0] > 0 }
        let maxCount = validSubs.map { subCounts[$0, default: 0] }.max() ?? 1

        if !subCounts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                // 標準化區塊標題：Capsule 側條 + 計數膠囊
                HStack(spacing: 10) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.55)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: 4, height: 18)
                    Text("子分類統計")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Text("\(validSubs.count) 類")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.blue.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.blue.opacity(0.22), lineWidth: 0.75))
                }
                .padding(.horizontal)

                VStack(spacing: 0) {
                    ForEach(Array(validSubs.enumerated()), id: \.element) { idx, sub in
                        let count = subCounts[sub, default: 0]
                        let accent = subColor(sub)
                        let ratio = maxCount > 0 ? Double(count) / Double(maxCount) : 0

                        VStack(spacing: 8) {
                            HStack(spacing: 12) {
                                // 漸層圖示圓（對齊 categoryBreakdownSection 規格）
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [accent.opacity(0.20), accent.opacity(0.08)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 34, height: 34)
                                    Circle()
                                        .stroke(accent.opacity(0.22), lineWidth: 1)
                                        .frame(width: 34, height: 34)
                                    Image(systemName: sub.icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(accent)
                                }
                                Text(sub.rawValue)
                                    .font(.subheadline)
                                Spacer()
                                // 計數膠囊徽章
                                Text("\(count) 筆")
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(accent.opacity(0.12))
                                    .foregroundStyle(accent)
                                    .clipShape(Capsule())
                            }

                            // 比例進度條
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color(.systemFill))
                                        .frame(height: 4)
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [accent, accent.opacity(0.60)],
                                                startPoint: .leading, endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geo.size.width * ratio, height: 4)
                                        .animation(.spring(response: 0.6, dampingFraction: 0.78), value: ratio)
                                }
                            }
                            .frame(height: 4)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        // 交錯進場動畫
                        .opacity(subCatRowsAppeared ? 1 : 0)
                        .offset(y: subCatRowsAppeared ? 0 : 12)
                        .animation(
                            .spring(response: 0.48, dampingFraction: 0.80)
                                .delay(0.06 * Double(idx)),
                            value: subCatRowsAppeared
                        )

                        if idx < validSubs.count - 1 {
                            Divider().padding(.leading, 62)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                .padding(.horizontal)
                .onAppear {
                    withAnimation(.spring(response: 0.50, dampingFraction: 0.82).delay(0.05)) {
                        subCatRowsAppeared = true
                    }
                }
            }
        }
    }

    // MARK: - 里程碑列表

    private var milestoneListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 標準化區塊標題：Capsule 側條 + 計數膠囊
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .orange.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Text("職涯里程碑")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if !filtered.isEmpty {
                    let totalCount = careerMilestones.count
                    let shownCount = filtered.count
                    Text(selectedSub == nil ? "\(totalCount) 筆" : "\(shownCount) / \(totalCount) 筆")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.orange.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.orange.opacity(0.22), lineWidth: 0.75))
                }
            }
            .padding(.horizontal)

            filterRow

            if filtered.isEmpty {
                // 升級空狀態：脈衝光環 + 漸層圓底 + icon（對齊 emptyStateView 規格）
                emptyMilestoneState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, item in
                        careerRow(item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if subscription.isPremium { editingItem = item }
                                else { showPremiumAlert = true }
                            }
                            .opacity(milestoneRowsAppeared ? 1 : 0)
                            .offset(y: milestoneRowsAppeared ? 0 : 14)
                            .animation(
                                .spring(response: 0.45, dampingFraction: 0.82)
                                    .delay(0.06 * Double(idx)),
                                value: milestoneRowsAppeared
                            )
                        if item.id != filtered.last?.id {
                            Divider().padding(.leading, 72)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                .padding(.horizontal)
                .onAppear {
                    withAnimation(.spring(response: 0.50, dampingFraction: 0.82).delay(0.05)) {
                        milestoneRowsAppeared = true
                    }
                }
            }
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "全部", isSelected: selectedSub == nil) {
                    selectedSub = nil
                }
                ForEach(CareerSubCategory.allCases) { sub in
                    FilterChip(title: sub.rawValue, icon: sub.icon,
                               isSelected: selectedSub == sub,
                               tint: subColor(sub)) {
                        selectedSub = sub
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    /// 空狀態：雙層脈衝光環 + 漸層底圓，對齊 VariableExpenseView.emptyStateView
    private var emptyMilestoneState: some View {
        let accent = Color.orange
        return VStack(spacing: 20) {
            ZStack {
                // 外層脈衝光環
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.28), lineWidth: 1.5)
                    .frame(width: 108, height: 108)
                    .scaleEffect(emptyIconPulse ? 1.38 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 內層脈衝光環（波紋層次）
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.14), lineWidth: 1)
                    .frame(width: 108, height: 108)
                    .scaleEffect(emptyIconPulse ? 1.65 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 主圓底（漸層填色）
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.15), accent.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 86, height: 86)
                    .overlay(
                        Circle()
                            .stroke(accent.opacity(0.22), lineWidth: 1.2)
                    )
                Image(systemName: selectedSub == nil ? "briefcase" : "magnifyingglass")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(accent.opacity(0.72))
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    emptyIconPulse = true
                }
            }

            VStack(spacing: 8) {
                Text(selectedSub == nil ? "尚無職涯里程碑" : "此分類尚無紀錄")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.70))
                Text(selectedSub == nil ? "點擊右上角 + 記錄職涯中的每個重要時刻" : "換一個分類篩選試試")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    /// careerRow：左側 4pt 分類色彩強調條 + 44pt 漸層圖示圓，對齊 ExpenseRow 規格
    private func careerRow(_ item: LifeMilestone) -> some View {
        let accent = subColor(item.careerSubCategory ?? .join)
        return HStack(alignment: .center, spacing: 0) {
            // 左側彩色強調條
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.40)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.trailing, 14)

            HStack(alignment: .top, spacing: 12) {
                // 44pt 漸層圖示圓 + 陰影（對齊 ExpenseRow 規格）
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.22), accent.opacity(0.09)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: accent.opacity(0.22), radius: 6, x: 0, y: 3)
                    Image(systemName: item.careerSubCategory?.icon ?? "briefcase.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if item.isManagerial == true {
                            Text("管理職")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.18))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }

                    // 子分類膠囊 + 副標題
                    HStack(spacing: 6) {
                        if let sub = item.careerSubCategory {
                            Text(sub.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 7).padding(.vertical, 2.5)
                                .background(accent.opacity(0.12))
                                .foregroundStyle(accent)
                                .clipShape(Capsule())
                        }
                        subtitleText(for: item)
                    }
                }

                Spacer(minLength: 4)

                Text(formatDate(item.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 16)
    }

    // 副標題文字（純文字，不含膠囊）
    @ViewBuilder
    private func subtitleText(for item: LifeMilestone) -> some View {
        let parts: [String] = {
            var p: [String] = []
            if let d = item.department, !d.isEmpty { p.append(d) }
            if let j = item.jobTitle, !j.isEmpty { p.append(j) }
            if let g = item.jobGrade, !g.isEmpty { p.append(g) }
            return p
        }()
        if item.careerSubCategory == .salaryAdjust,
           let before = item.salaryBefore, before > 0,
           let after = item.salaryAfter, after > 0 {
            let pct = (after - before) / before * 100
            Text(String(format: "NT$%.0f → NT$%.0f（%@%.1f%%）", before, after, pct >= 0 ? "+" : "", pct))
                .font(.caption)
                .foregroundStyle(pct >= 0 ? .green : .red)
                .lineLimit(1)
        } else if item.careerSubCategory == .resign {
            if let m = item.mood, !m.isEmpty {
                Text("心境：\(m)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else if let f = item.futurePlan, !f.isEmpty {
                Text("規劃：\(f)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        } else if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if !item.note.isEmpty {
            Text(item.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func subColor(_ sub: CareerSubCategory) -> Color {
        switch sub {
        case .join:         return .green
        case .promote:      return .blue
        case .salaryAdjust: return .cyan
        case .transfer:     return .orange
        case .demote:       return .purple
        case .resign:       return .red
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }
}
