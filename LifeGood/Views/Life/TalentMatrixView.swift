import SwiftUI
import Charts

// MARK: - 部屬評分（潛力 / 主動性）

extension Subordinate {
    /// 潛力分數（記錄式評分，0~100；與部屬列表的評分一致）：
    /// 基礎 80，優點/成就/進步加分，缺點/缺失/疏失/請假扣分。
    var potentialScore: Int {
        var score: Double = 80
        for rec in records {
            switch rec.type {
            case .pro:         score += 2
            case .con:         score -= 2
            case .achievement: score += 3
            case .improvement: score += 1
            case .fault:       score -= 3
            case .missOperation:
                switch rec.severity {
                case .minor:  score -= 1
                case .normal: score -= 2
                case .severe: score -= 4
                case .none:   score -= 2
                }
            case .leave:
                score -= (rec.leaveHours ?? 8) / 16
            }
        }
        return max(0, min(100, Int(score.rounded())))
    }

    /// 主動性分數（日常，0~100）：完成任務 / 完成會議議程項目加分，請假時數扣分。
    var proactivityScore: Int {
        let completedTasks = tasks.filter { $0.isCompleted }.count
        let completedItems = meetings.flatMap { $0.items }.filter { $0.isCompleted }.count
        let leaveHours = records.filter { $0.type == .leave }.reduce(0.0) { $0 + ($1.leaveHours ?? 8) }
        var score = 60.0
        score += Double(completedTasks) * 3      // 每完成一項任務 +3
        score += Double(completedItems) * 2      // 每完成一個議程項目 +2
        score -= leaveHours / 8 * 2              // 每請假 8 小時 -2
        return max(0, min(100, Int(score.rounded())))
    }
}

// MARK: - 人才矩陣（主動性 × 潛力 散布圖）

struct TalentMatrixView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDeptId: UUID? = nil

    private var members: [Subordinate] {
        lifeStore.subordinates
            .filter { selectedDeptId == nil || $0.departmentId == selectedDeptId }
    }

    private var selectedDeptName: String {
        guard let id = selectedDeptId,
              let d = lifeStore.departments.first(where: { $0.id == id }) else { return "全部部門" }
        return d.name.isEmpty ? (d.code.isEmpty ? "未命名部門" : d.code) : d.name
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                deptFilter
                if members.isEmpty {
                    emptyHint
                } else {
                    chart
                    quadrantLegend
                    Spacer(minLength: 0)
                }
            }
            .padding(.top, 8)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("人才矩陣")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } } }
        }
    }

    private var deptFilter: some View {
        Menu {
            Button("全部部門") { selectedDeptId = nil }
            ForEach(lifeStore.departments) { d in
                Button(d.name.isEmpty ? d.code : d.name) { selectedDeptId = d.id }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(selectedDeptName).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
        }
        .padding(.horizontal)
    }

    // 自動縮放：軸範圍取所有成員的最小～最大，留一點邊距
    private func domain(_ values: [Int]) -> ClosedRange<Double> {
        let v = values.map(Double.init)
        guard let lo = v.min(), let hi = v.max() else { return 0...100 }
        if lo == hi { return max(0, lo - 5)...(hi + 5) }
        let pad = (hi - lo) * 0.12
        return (lo - pad)...(hi + pad)
    }

    private var xDomain: ClosedRange<Double> { domain(members.map { $0.proactivityScore }) }
    private var yDomain: ClosedRange<Double> { domain(members.map { $0.potentialScore }) }
    private var xMid: Double { (xDomain.lowerBound + xDomain.upperBound) / 2 }
    private var yMid: Double { (yDomain.lowerBound + yDomain.upperBound) / 2 }

    private func pointColor(_ m: Subordinate) -> Color {
        let hiX = Double(m.proactivityScore) >= xMid
        let hiY = Double(m.potentialScore) >= yMid
        switch (hiY, hiX) {
        case (true, true):   return .green     // 高潛力高主動：明星
        case (true, false):  return .blue      // 高潛力低主動：潛力股
        case (false, true):  return .orange    // 低潛力高主動：苦勞型
        case (false, false): return .red        // 低潛力低主動：待加強
        }
    }

    private var chart: some View {
        Chart {
            // 象限分隔線
            RuleMark(x: .value("主動性中位", xMid))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color(.separator))
            RuleMark(y: .value("潛力中位", yMid))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color(.separator))

            ForEach(members) { m in
                PointMark(
                    x: .value("主動性", m.proactivityScore),
                    y: .value("潛力", m.potentialScore)
                )
                .symbolSize(140)
                .foregroundStyle(pointColor(m))
                .annotation(position: .top, spacing: 1) {
                    Text(m.name.isEmpty ? "未命名" : m.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxisLabel("主動性（日常：任務 / 會議完成、出勤）", alignment: .center)
        .chartYAxisLabel("潛力（評分系統）")
        .frame(height: 380)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.15), lineWidth: 0.75))
        .padding(.horizontal)
    }

    private var quadrantLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            legendRow(.green, "明星（高潛力・高主動）")
            legendRow(.blue, "潛力股（高潛力・低主動）")
            legendRow(.orange, "苦勞型（低潛力・高主動）")
            legendRow(.red, "待加強（低潛力・低主動）")
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
    }

    private func legendRow(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.dots.scatter")
                .font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text(selectedDeptId == nil ? "尚無部屬資料" : "此部門沒有部屬").foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
