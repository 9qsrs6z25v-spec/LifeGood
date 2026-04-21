import SwiftUI

struct CareerView: View {
    @EnvironmentObject var store: LifeStore
    @State private var editingItem: LifeMilestone?
    @State private var showAdd = false
    @State private var selectedSub: CareerSubCategory?

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
                VStack(spacing: 16) {
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
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddMilestoneView(initialCategory: .career) }
            .sheet(item: $editingItem) { item in AddMilestoneView(editing: item) }
        }
    }

    // MARK: - 看板

    private var dashboardSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                summaryCard(title: "目前公司", value: currentCompany ?? "—",
                            icon: "building.2.fill", color: .blue)
                summaryCard(title: "目前職位", value: currentPosition ?? "—",
                            icon: "person.badge.key.fill", color: .indigo)
            }
            HStack(spacing: 12) {
                statCard(title: "任職年資",
                         value: yearsAtCurrentCompany.map { String(format: "%.1f 年", $0) } ?? "—",
                         icon: "clock.fill", color: .orange)
                statCard(title: "任職公司數", value: "\(totalCompanies)",
                         icon: "building.columns.fill", color: .teal)
                statCard(title: "職涯里程碑", value: "\(careerMilestones.count)",
                         icon: "trophy.fill", color: .yellow)
            }
        }
        .padding(.horizontal)
    }

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption).foregroundStyle(color)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - 子分類統計

    @ViewBuilder
    private var subCategoryBreakdown: some View {
        if !subCounts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("子分類統計").font(.headline).padding(.horizontal)
                VStack(spacing: 0) {
                    ForEach(CareerSubCategory.allCases) { sub in
                        if let count = subCounts[sub], count > 0 {
                            HStack {
                                Image(systemName: sub.icon).frame(width: 30)
                                    .foregroundStyle(subColor(sub))
                                Text(sub.rawValue).font(.subheadline)
                                Spacer()
                                Text("\(count) 筆").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal).padding(.vertical, 10)
                            if CareerSubCategory.allCases.last(where: { subCounts[$0, default: 0] > 0 }) != sub {
                                Divider().padding(.leading, 50)
                            }
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - 里程碑列表

    private var milestoneListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("職涯里程碑").font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            filterRow

            if filtered.isEmpty {
                Text("此分類尚無紀錄").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(filtered) { item in
                        careerRow(item)
                            .contentShape(Rectangle())
                            .onTapGesture { editingItem = item }
                        if item.id != filtered.last?.id {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                .padding(.horizontal)
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
                    FilterChip(title: sub.rawValue, icon: sub.icon, isSelected: selectedSub == sub) {
                        selectedSub = sub
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func careerRow(_ item: LifeMilestone) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.careerSubCategory?.icon ?? "briefcase.fill")
                .font(.title3)
                .foregroundStyle(subColor(item.careerSubCategory ?? .join))
                .frame(width: 36, height: 36)
                .background(subColor(item.careerSubCategory ?? .join).opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title).font(.subheadline.weight(.medium))
                    if item.isManagerial == true {
                        Text("管理職")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
                subtitle(for: item)
            }

            Spacer()

            Text(formatDate(item.date)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func subtitle(for item: LifeMilestone) -> some View {
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
                .font(.caption).foregroundStyle(pct >= 0 ? .green : .red).lineLimit(1)
        } else if item.careerSubCategory == .resign {
            if let m = item.mood, !m.isEmpty {
                Text("心境：\(m)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if let f = item.futurePlan, !f.isEmpty {
                Text("規劃：\(f)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        } else if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        } else if !item.note.isEmpty {
            Text(item.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func subColor(_ sub: CareerSubCategory) -> Color {
        switch sub {
        case .join: return .green
        case .promote: return .blue
        case .salaryAdjust: return .cyan
        case .transfer: return .orange
        case .demote: return .purple
        case .resign: return .red
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }
}
