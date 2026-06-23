import SwiftUI
import Charts

// MARK: - 部屬評分（潛力 / 主動性）

extension Subordinate {
    /// 潛力分數（記錄式評分，0~100；與部屬列表的評分一致）：
    /// 基礎 80，優點/成就/進步加分，缺點/缺失/疏失扣分。請假不計入（已反映在主動性）。
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
                break   // 請假不計入潛力（已反映在主動性）
            }
        }
        return max(0, min(100, Int(score.rounded())))
    }

    /// 主動性分數（日常，0~100）：完成任務 / 完成會議議程項目加分，請假時數扣分。
    var proactivityScore: Int {
        let completedTasks = tasks.filter { $0.isCompleted }.count
        let completedItems = meetings.flatMap { $0.items }.filter { $0.isCompleted }.count
        let completedReports = weeklyReports.filter { $0.isCompleted }.count
        let leaveHours = records.filter { $0.type == .leave }.reduce(0.0) { $0 + ($1.leaveHours ?? 8) }
        var score = 60.0
        score += Double(completedTasks) * 3      // 每完成一項任務 +3
        score += Double(completedItems) * 2      // 每完成一個議程項目 +2
        score += Double(completedReports) * 3    // 每完成一份週報 +3
        score -= leaveHours / 8 * 2              // 每請假 8 小時 -2
        return max(0, min(100, Int(score.rounded())))
    }

    /// 綜合分數＝潛力與主動性的平均（部屬列表左側顯示用）
    var overallScore: Int {
        Int(((Double(potentialScore) + Double(proactivityScore)) / 2).rounded())
    }

    /// 潛力評分的計算明細（分組條目 + 加減分）
    var potentialBreakdown: [(label: String, points: Int)] {
        var items: [(String, Int)] = [("基礎分", 80)]
        var pro = 0, con = 0, ach = 0, imp = 0, fault = 0
        var mMinor = 0, mNormal = 0, mSevere = 0
        for r in records {
            switch r.type {
            case .pro:         pro += 1
            case .con:         con += 1
            case .achievement: ach += 1
            case .improvement: imp += 1
            case .fault:       fault += 1
            case .missOperation:
                switch r.severity {
                case .minor:  mMinor += 1
                case .severe: mSevere += 1
                default:      mNormal += 1
                }
            case .leave:       break   // 不計入潛力
            }
        }
        if ach > 0   { items.append(("成就 ×\(ach)", ach * 3)) }
        if pro > 0   { items.append(("優點 ×\(pro)", pro * 2)) }
        if imp > 0   { items.append(("進步 ×\(imp)", imp)) }
        if con > 0   { items.append(("缺點 ×\(con)", -con * 2)) }
        if fault > 0 { items.append(("缺失 ×\(fault)", -fault * 3)) }
        if mMinor > 0  { items.append(("疏失·輕微 ×\(mMinor)", -mMinor)) }
        if mNormal > 0 { items.append(("疏失·一般 ×\(mNormal)", -mNormal * 2)) }
        if mSevere > 0 { items.append(("疏失·嚴重 ×\(mSevere)", -mSevere * 4)) }
        return items
    }

    /// 主動性評分的計算明細（分組條目 + 加減分）
    var proactivityBreakdown: [(label: String, points: Int)] {
        var items: [(String, Int)] = [("基礎分", 60)]
        let completedTasks = tasks.filter { $0.isCompleted }.count
        let completedItems = meetings.flatMap { $0.items }.filter { $0.isCompleted }.count
        let completedReports = weeklyReports.filter { $0.isCompleted }.count
        let leaveHours = records.filter { $0.type == .leave }.reduce(0.0) { $0 + ($1.leaveHours ?? 8) }
        if completedTasks > 0 { items.append(("完成任務 ×\(completedTasks)", completedTasks * 3)) }
        if completedItems > 0 { items.append(("完成議程項目 ×\(completedItems)", completedItems * 2)) }
        if completedReports > 0 { items.append(("完成週報 ×\(completedReports)", completedReports * 3)) }
        if leaveHours > 0 {
            let h = leaveHours.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(leaveHours))" : String(format: "%.1f", leaveHours)
            items.append(("請假 \(h) 小時", -Int((leaveHours / 8 * 2).rounded())))
        }
        return items
    }
}

// MARK: - 人才矩陣（主動性 × 潛力 散布圖）

struct TalentMatrixView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDeptId: UUID? = nil
    @State private var selected: Subordinate?

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
            ZStack {
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

                // 點選某點 → 展開計算明細指示窗；點窗外關閉
                if let m = selected {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { selected = nil }
                        }
                    breakdownCard(m)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                        .zIndex(1)
                }
            }
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
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .onTapGesture { loc in selectNearest(at: loc, proxy: proxy, geo: geo) }
            }
        }
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

    // 找最靠近點擊位置的成員（命中半徑 50pt）
    private func selectNearest(at loc: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard let anchor = proxy.plotFrame else { return }
        let rect = geo[anchor]
        var best: Subordinate?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for m in members {
            guard let px = proxy.position(forX: m.proactivityScore),
                  let py = proxy.position(forY: m.potentialScore) else { continue }
            let p = CGPoint(x: rect.minX + px, y: rect.minY + py)
            let d = hypot(p.x - loc.x, p.y - loc.y)
            if d < bestDist { bestDist = d; best = m }
        }
        if let best, bestDist < 50 {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { selected = best }
        }
    }

    // 計算明細指示窗
    private func breakdownCard(_ m: Subordinate) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name.isEmpty ? "未命名" : m.name).font(.headline)
                    Text("主動性 \(m.proactivityScore)　潛力 \(m.potentialScore)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { selected = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    breakdownGroup("主動性（日常）", color: .blue, total: m.proactivityScore, items: m.proactivityBreakdown)
                    breakdownGroup("潛力（評分）", color: .indigo, total: m.potentialScore, items: m.potentialBreakdown)
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 300)
        }
        .padding(16)
        .frame(maxWidth: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(.separator).opacity(0.2), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.22), radius: 22, x: 0, y: 10)
        .contentShape(Rectangle())
        .onTapGesture { }   // 吸收點擊，避免點到卡片本身就關閉
        .padding(.horizontal, 24)
    }

    private func breakdownGroup(_ title: String, color: Color, total: Int,
                                items: [(label: String, points: Int)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.bold))
                Spacer()
                Text("\(total) 分").font(.subheadline.weight(.bold)).foregroundStyle(color)
            }
            Divider()
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                HStack {
                    Text(it.label).font(.caption).foregroundStyle(.primary)
                    Spacer()
                    Text(it.points >= 0 ? "+\(it.points)" : "\(it.points)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(it.points >= 0 ? .green : .red)
                        .monospacedDigit()
                }
            }
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
