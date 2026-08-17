import SwiftUI
import Charts
import UIKit

// MARK: - 部屬評分（潛力 / 主動性）

extension Subordinate {
    /// 潛力分數（記錄式評分；與部屬列表的評分一致）：
    /// 基礎 80，優點/成就/進步加分，缺點/缺失/疏失扣分。請假不計入（已反映在主動性）。
    ///
    /// ⚠️ **沒有 100 分上限**（使用者要求，v25.230）。原本夾在 0~100，
    ///    表現特別突出的人一旦頂到 100 就再也看不出差異——同樣是 100 分，
    ///    可能是剛好達標，也可能是超標三倍。散布圖的座標軸走 domain()
    ///    依實際最大最小值自動縮放，scoreColor 的 `case 90...` 也是開放區間，
    ///    所以破百不會撐破任何畫面。下限仍保留 0。
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
        return max(0, Int(score.rounded()))
    }

    /// 主動性分數（日常）：完成任務 / 完成會議議程項目 / 報告加分、被標註加分，請假時數扣分。
    /// 與潛力分數一樣**沒有 100 分上限**（見上方說明），下限仍為 0。
    /// mentionedCount = 此人被其他項目 @ 標註的項目數（由 LifeStore 計算後傳入）。
    /// sideRoleDone = 此人在兼任職務裡完成的待辦數（由 LifeStore.sideRoleTaskCounts() 傳入）——
    ///   兼任職務是本職以外的實際工作量，完成的事該和本職任務同權重計分（每項 +3）。
    ///
    /// ⚠️ sideRoleDone **刻意不給預設值**。給了預設值，任何忘記傳的呼叫點都會靜默算成 0，
    ///    同一個人在列表、人才矩陣、明細頁就會顯示三個不同的分數，而且完全不會編譯錯。
    ///    設成必填的話漏掉就編不過——這裡寧可編譯失敗。
    func proactivityScore(mentionedCount: Int = 0, sideRoleDone: Int) -> Int {
        let completedTasks = tasks.filter { $0.isCompleted }.count
        let completedItems = meetings.flatMap { $0.allItems }.filter { $0.isCompleted }.count
        let completedReports = weeklyReports.filter { $0.isCompleted }.count
        // 喪假／公假為非個人意願的假別，不列入扣分（LeaveType.isScoreExempt）
        let leaveHours = records.filter { $0.type == .leave && !($0.leaveType?.isScoreExempt ?? false) }.reduce(0.0) { $0 + ($1.leaveHours ?? 8) }
        var score = 60.0
        score += Double(completedTasks) * 3      // 每完成一項任務 +3
        score += Double(completedItems)          // 每完成一個議程項目 +1（顆粒最小，且週期會議每場各有一份，權重刻意壓低）
        score += Double(completedReports) * 3    // 每完成一份報告 +3
        score += Double(mentionedCount) * 2      // 每被標註一項 +2
        score += Double(sideRoleDone) * 3        // 每完成一項兼任待辦 +3（與本職任務同權重）
        score -= leaveHours / 8 * 2              // 每請假 8 小時 -2
        return max(0, Int(score.rounded()))
    }

    /// 綜合分數＝潛力與主動性的平均（部屬列表左側顯示用）
    func overallScore(mentionedCount: Int = 0, sideRoleDone: Int) -> Int {
        Int(((Double(potentialScore)
              + Double(proactivityScore(mentionedCount: mentionedCount, sideRoleDone: sideRoleDone)))
             / 2).rounded())
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
    func proactivityBreakdown(mentionedCount: Int = 0, sideRoleDone: Int) -> [(label: String, points: Int)] {
        var items: [(String, Int)] = [("基礎分", 60)]
        let completedTasks = tasks.filter { $0.isCompleted }.count
        let completedItems = meetings.flatMap { $0.allItems }.filter { $0.isCompleted }.count
        let completedReports = weeklyReports.filter { $0.isCompleted }.count
        // 喪假／公假為非個人意願的假別，不列入扣分（LeaveType.isScoreExempt）
        let leaveHours = records.filter { $0.type == .leave && !($0.leaveType?.isScoreExempt ?? false) }.reduce(0.0) { $0 + ($1.leaveHours ?? 8) }
        if completedTasks > 0 { items.append(("完成任務 ×\(completedTasks)", completedTasks * 3)) }
        if completedItems > 0 { items.append(("完成議程項目 ×\(completedItems)", completedItems)) }
        if completedReports > 0 { items.append(("完成報告 ×\(completedReports)", completedReports * 3)) }
        if mentionedCount > 0 { items.append(("被標註 ×\(mentionedCount)", mentionedCount * 2)) }
        if sideRoleDone > 0 { items.append(("完成兼任待辦 ×\(sideRoleDone)", sideRoleDone * 3)) }
        if leaveHours > 0 {
            let h = leaveHours.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(leaveHours))" : String(format: "%.1f", leaveHours)
            items.append(("請假 \(h) 小時", -Int((leaveHours / 8 * 2).rounded())))
        }
        return items
    }
}

// MARK: - 美化紀錄（TalentMatrixView）
// [2026-06 v1] 本次美化方向：
//   1. emptyHint：從單一平面圖示 + 純文字，升級為雙層脈衝光環（indigo）
//      + 44pt LinearGradient 漸層底圓 + 標題/說明文字，
//      對齊 VariableExpenseView.emptyStateView / SubordinateView.emptyState 設計規格；
//      emptyPulse spring 動畫。
//   2. quadrantLegend：從裸露 VStack，升級為完整卡片（白底 + shadow + overlay 邊框），
//      頂部加 Capsule 漸層側條 + 方格圖示 + .subheadline.bold「象限圖例」section header，
//      對齊 StockDetailView.transactionsSection / SubordinateView sectionHeader 設計語言。
//   3. legendRow：從簡易 10pt 圓點 + 純文字，升級為 28pt LinearGradient 漸層圓（含 stroke）
//      + 主標題（.caption.semibold）+ 副說明（.caption2），
//      對齊 FinanceChartView.allocationChart 圖例列規格。
//   4. breakdownCard 標頭：從姓名 + 純文字分數，升級為 40pt 動態漸層圓（依象限色）
//      + 姓名 .subheadline.bold + 主動 / 潛力 capsule 分數徽章（帶 stroke 邊框），
//      對齊 SubordinateView.subordinateRow / StockDetailView.transactionRow 圖示圓規格。
//   5. breakdownGroup：title 列從裸 HStack，升級為 3pt Capsule 漸層側條 + .subheadline.bold
//      + 分數 capsule 徽章（帶 stroke），對齊 VariableExpenseView section header 規格；
//      明細列分數從純色字升級為彩色 Capsule 膠囊（綠加 / 紅扣），
//      對齊 StockDetailView.infoRow 損益膠囊規格。
// [2026-06 v2] 本次美化方向：
//   6. summaryHeroCard：deptFilter 下方新增藍紫漸層英雄摘要卡，顯示篩選後人數大字 +
//      部門膠囊副標 + 四格 KPI 橫列（明星/潛力股/苦勞型/待加強計數），
//      三顆散景裝飾圓 + 頂部玻璃光澤（white.opacity(0.18)→clear），
//      heroCardAppeared spring 進場動畫（opacity + Y 位移 18pt），
//      對齊 SubordinateView.summaryStatsBar / SubordinateDetailView.headerCard 設計語言。
//   7. deptFilter 選取態升級：selectedDeptId != nil 時 pill 從 secondarySystemBackground
//      改為 indigo 淺底色（opacity 0.10）+ indigo 文字 + 細邊框（0.6pt），
//      對齊 VariableExpenseView.FilterChip 選取態規格。
//   8. chartSectionHeader：chart 上方新增 Capsule 漸層側條 + chart.dots.scatter 圖示 +
//      「散布圖分析」標題 + 人數計數膠囊，
//      對齊 SubordinateView.activeSubordinatesSectionHeader / TaxOverviewView sectionHeader 規格。
//   9. 主 VStack 包裹於 ScrollView：因英雄卡 + 散布圖 + 圖例總高超出螢幕，
//      包裹 ScrollView 使用戶可自然上滑查閱圖例；breakdownCard 懸浮層維持 ZStack 疊加不受影響。
// [2026-06 v3] 本次美化方向：
//  10. chart 散布點標籤：從灰色純文字升級為彩色 Capsule 徽章（顏色對應象限），
//      視覺上名字與點顏色一致，對齊全 App Capsule stroke 膠囊規格。
//  11. legendRow 人數徽章：各象限圖例列右側新增「X 人」Capsule 計數膠囊，
//      對齊 SubordinateView / TaxOverviewView sectionHeader 計數膠囊規格。
//  12. breakdownCard 象限標籤：評分卡頭部在主動/潛力分數膠囊旁新增「明星/潛力股/
//      苦勞型/待加強」象限膠囊，顏色對應象限色，直觀顯示矩陣位置。
//  13. heroKpiCell 計數著色：KPI 格象限人數從固定白色改為對應象限色（>0 時），
//      視覺對照更直觀，對齊 FinanceChartView.heroKpiCell 動態著色規格。
//  14. chart + quadrantLegend 進場動畫：補 opacity 淡入（延遲 0.10s / 0.18s），
//      與英雄卡 heroCardAppeared spring 動畫形成視覺梯次感。
//  15. 象限人數計算抽取為 computed properties（starCount / potentialCount /
//      hardWorkerCount / needsImprovCount）+ quadrantLabel() helper，
//      供英雄卡與圖例雙用，消除重複計算。
// [2026-07 v4] 補齊 breakdownGroup 分隔線主題色：原本沿用系統灰色 Divider()，
//   是本檔案唯一還沒套用主題色分隔線的元素——同檔案 breakdownCard 卡片外框、
//   summaryHeroCard 內部分隔線皆早已改用對應主題色的 Rectangle().fill(color.opacity)
//   細線（對齊 FamilyOverviewMap.HouseView / ChildVaccineScheduleView 既有規格）。
//   改為 Rectangle().fill(color.opacity(0.20)).frame(height: 0.5)，跟隨呼叫端傳入的
//   主動性／潛力主題色，與 .regularMaterial 卡片背景更協調。純視覺層調整，
//   分數計算、items 明細列內容等既有商業邏輯完全未變動。
//   （下次美化本檔案時，可轉往其他仍留有待辦的畫面）

// MARK: - 人才矩陣（主動性 × 潛力 散布圖）

private struct MatrixShareURL: Identifiable { let id = UUID(); let url: URL }

struct TalentMatrixView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("talentMatrixDeptFilter") private var deptFilterRaw = ""  // 逗號分隔 UUID；空=全部部門
    @State private var selected: Subordinate?
    @State private var shareItem: MatrixShareURL?

    /// 目前選取的部門（多選，持久化於 @AppStorage）
    private var selectedDeptIds: Set<UUID> {
        Set(deptFilterRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }
    private func toggleDept(_ id: UUID) {
        var s = selectedDeptIds
        if s.contains(id) { s.remove(id) } else { s.insert(id) }
        deptFilterRaw = s.map(\.uuidString).joined(separator: ",")
    }
    private func deptName(_ d: Department) -> String {
        d.name.isEmpty ? (d.code.isEmpty ? "未命名部門" : d.code) : d.name
    }
    // [v1] 空狀態脈衝動畫旗標
    @State private var emptyPulse = false
    // [v2] 英雄摘要卡進場動畫旗標
    @State private var heroCardAppeared = false
    // [v3] 散布圖 + 圖例進場動畫旗標
    @State private var chartAppeared = false
    @State private var legendAppeared = false

    private var members: [Subordinate] {
        let ids = selectedDeptIds
        return lifeStore.subordinates.filter { ids.isEmpty || ($0.departmentId.map { ids.contains($0) } ?? false) }
    }

    /// 各成員含被標註加分的主動性分數 + X 軸中位數，由呼叫端（body / exportContent）
    /// 以 lifeStore.mentionedCounts() 對 members 一次算好整批後打包傳入，避免 proactivity(_:)
    /// 被圖表/象限統計/圖例/明細卡等十餘處呼叫點各自重新觸發一次全量 mentionedCounts()
    /// 掃描（O(全部部屬 × 任務/會議/報告) 的重複計算，members 數愈多重複次數愈多）。
    private struct AxisContext {
        let mentionCounts: [UUID: Int]
        /// 部屬 id → 兼任待辦（完成／總數）。與 mentionCounts 同樣一次算好整批傳入。
        let sideRoleCounts: [UUID: (done: Int, total: Int)]
        let scores: [UUID: Int]
        let xRange: ClosedRange<Double>
        let xMid: Double
        let potentialScores: [UUID: Int]
        let yRange: ClosedRange<Double>
        let yMid: Double
    }
    private func makeAxisContext() -> AxisContext {
        let mentionCounts = lifeStore.mentionedCounts()
        let sideRoleCounts = lifeStore.sideRoleTaskCounts()
        let scores = Dictionary(members.map {
            ($0.id, $0.proactivityScore(mentionedCount: mentionCounts[$0.id] ?? 0,
                                        sideRoleDone: sideRoleCounts[$0.id]?.done ?? 0))
        }, uniquingKeysWith: { first, _ in first })
        let range = domain(members.map { scores[$0.id] ?? 0 })
        let potentialScores = Dictionary(members.map { ($0.id, $0.potentialScore) }, uniquingKeysWith: { first, _ in first })
        let yRange = domain(members.map { potentialScores[$0.id] ?? 0 })
        return AxisContext(
            mentionCounts: mentionCounts, sideRoleCounts: sideRoleCounts, scores: scores, xRange: range, xMid: (range.lowerBound + range.upperBound) / 2,
            potentialScores: potentialScores, yRange: yRange, yMid: (yRange.lowerBound + yRange.upperBound) / 2
        )
    }
    /// 含被標註加分的主動性分數（由 ctx.scores 查表，O(1)）
    private func proactivity(_ m: Subordinate, _ ctx: AxisContext) -> Int {
        ctx.scores[m.id] ?? 0
    }
    /// 潛力分數（由 ctx.potentialScores 查表，O(1)）
    private func potential(_ m: Subordinate, _ ctx: AxisContext) -> Int {
        ctx.potentialScores[m.id] ?? 0
    }

    /// 篩選摘要（全部部門 / 單一部門名 / N 個部門）
    private var selectedDeptName: String {
        let ids = selectedDeptIds
        if ids.isEmpty { return "全部部門" }
        if ids.count == 1, let d = lifeStore.departments.first(where: { ids.contains($0.id) }) { return deptName(d) }
        return "\(ids.count) 個部門"
    }

    var body: some View {
        // 每個 body 求值只算一次（含被標註加分的主動性分數 + X 軸中位數），
        // 供英雄卡 KPI、散布圖、象限圖例、明細卡共用，取代原本每處各自呼叫
        // lifeStore.mentionedCounts() 的重複全量掃描。
        let ctx = makeAxisContext()
        return NavigationStack {
            // [v2] ZStack：ScrollView 為底層主內容；breakdownCard 懸浮層疊加其上
            ZStack {
                ScrollView {
                    VStack(spacing: 12) {
                        deptFilter
                        if members.isEmpty {
                            emptyHint
                        } else {
                            // [v2] 英雄摘要卡 + section header
                            summaryHeroCard(ctx)
                            chartSectionHeader
                            chart(ctx)
                            quadrantLegend(ctx)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }

                // 點選某點 → 展開計算明細指示窗；點窗外關閉
                if let m = selected {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { selected = nil }
                        }
                    breakdownCard(m, ctx)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("人才矩陣")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { exportJPG() } label: { Label("匯出 JPG", systemImage: "square.and.arrow.up") }
                }
            }
            .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
            // 部門篩選變更後 members／ctx 會改用新篩選重新計算，若明細卡仍開著且
            // 選取的成員不在新篩選範圍內，卡片會顯示用 ?? 0 頂替的空分數、卻仍疊在畫面上，
            // 呈現自相矛盾的資料，因此篩選一變就先收起明細卡。
            .onChange(of: deptFilterRaw) { _, _ in
                selected = nil
            }
            // 所選部門被刪除時，從篩選中移除該部門 id（對齊 SubordinateView 既有修復規格：用 id 陣列
            // 觀察，避免 Department 需 Equatable）。GradeTitleView.deleteDepartment 刪除部門時只會
            // 清空受影響 Subordinate/OrgPerson 的 departmentId，不會主動清理這裡持久化的
            // talentMatrixDeptFilter，若不處理，殘留的孤兒 UUID 會讓 members 篩不到任何人、
            // 畫面顯示「所選部門沒有部屬」的空狀態假象，且已刪除的部門不再出現在篩選選單裡，
            // 使用者難以察覺原因，只能記得手動切回「全部部門」。
            .onChange(of: lifeStore.departments.map(\.id)) { _, ids in
                let validIds = Set(ids)
                let filtered = selectedDeptIds.intersection(validIds)
                if filtered != selectedDeptIds {
                    deptFilterRaw = filtered.map(\.uuidString).joined(separator: ",")
                }
            }
        }
    }

    // [v2] 選取特定部門時改為 indigo 淺底 + 細邊框，對齊 FilterChip 選取態規格；支援多選
    private var deptFilter: some View {
        let isFiltered = !selectedDeptIds.isEmpty
        return Menu {
            Button { deptFilterRaw = "" } label: {
                if selectedDeptIds.isEmpty { Label("全部部門", systemImage: "checkmark") }
                else { Text("全部部門") }
            }
            ForEach(lifeStore.departments) { d in
                Button { toggleDept(d.id) } label: {
                    if selectedDeptIds.contains(d.id) { Label(deptName(d), systemImage: "checkmark") }
                    else { Text(deptName(d)) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(selectedDeptName).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isFiltered ? Color.indigo : Color.primary)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(isFiltered ? Color.indigo.opacity(0.10) : Color(.secondarySystemBackground))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.indigo.opacity(isFiltered ? 0.22 : 0.0), lineWidth: 0.6))
        }
        .padding(.horizontal)
    }

    // MARK: - 匯出 JPG

    /// 匯出整頁（摘要 + 散布圖 + 圖例）為 JPG 並開啟分享
    @MainActor
    private func exportJPG() {
        let content = exportContent
            .frame(width: 420)
            .padding(20)
            .background(Color(.systemBackground))
            .environmentObject(lifeStore)
        let renderer = ImageRenderer(content: content)
        renderer.scale = max(UIScreen.main.scale, 3)
        guard let ui = renderer.uiImage, let data = ui.jpegData(compressionQuality: 0.95) else { return }
        let name = "人才矩陣_\(Self.stampFormatter.string(from: Date())).jpg"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            shareItem = MatrixShareURL(url: url)
        } catch { }
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmm"; return f
    }()

    /// 供 ImageRenderer 使用的靜態版面（不含互動）
    private var exportContent: some View {
        let ctx = makeAxisContext()
        return VStack(spacing: 14) {
            HStack {
                Image(systemName: "chart.dots.scatter").foregroundStyle(.indigo)
                Text("人才矩陣").font(.headline)
                Spacer()
                Text(selectedDeptName).font(.caption).foregroundStyle(.secondary)
            }
            if members.isEmpty {
                Text("尚無部屬資料").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 40)
            } else {
                summaryHeroCard(ctx)
                chart(ctx)
                quadrantLegend(ctx)
            }
        }
    }

    // MARK: - [v2] 英雄摘要卡（藍紫漸層 + 散景 + 玻璃光澤 + 四格 KPI）

    private func summaryHeroCard(_ ctx: AxisContext) -> some View {
        let total = members.count

        return VStack(spacing: 0) {
            // 頂部：人數大字 + 部門膠囊副標
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(total)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                VStack(alignment: .leading, spacing: 3) {
                    Text("人")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(selectedDeptName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.white.opacity(0.18))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 0.6))
                }
                Spacer()
            }
            .padding(.bottom, 14)

            Rectangle()
                .fill(.white.opacity(0.20))
                .frame(height: 0.5)
                .padding(.bottom, 12)

            // KPI 四格：明星 / 潛力股 / 苦勞型 / 待加強
            HStack(spacing: 0) {
                heroKpiCell(count: starCount(ctx), label: "明星", icon: "star.fill", color: .green)
                HeroKpiDivider()
                heroKpiCell(count: potentialCount(ctx), label: "潛力股", icon: "arrow.up.right.circle.fill", color: Color(red: 0.50, green: 0.65, blue: 1.0))
                HeroKpiDivider()
                heroKpiCell(count: hardWorkerCount(ctx), label: "苦勞型", icon: "hammer.fill", color: Color(red: 1.0, green: 0.78, blue: 0.35))
                HeroKpiDivider()
                heroKpiCell(count: needsImprovCount(ctx), label: "待加強", icon: "exclamationmark.triangle.fill", color: Color(red: 1.0, green: 0.50, blue: 0.50))
            }
            .padding(.vertical, 8)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .heroCardShell(card: .talentMatrix)
        .padding(.horizontal)
        .opacity(heroCardAppeared ? 1 : 0)
        .offset(y: heroCardAppeared ? 0 : 18)
        .onAppear {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.78)) {
                heroCardAppeared = true
            }
        }
    }

    // [v3] KPI 單格：>0 時數字用象限對應色，視覺對照更直觀
    // 薄轉接層：排法／字級／圖示圓一律交給 HeroKpiCell，這裡只負責把
    // count 轉字串並決定「有沒有人」的灰階狀態，避免呼叫端把 count 算兩次。
    private func heroKpiCell(count: Int, label: String, icon: String, color: Color) -> HeroKpiCell {
        HeroKpiCell(label: label, value: "\(count)", icon: icon,
                    valueColor: count > 0 ? color : .white.opacity(0.38))
    }

    // MARK: - [v2] 散布圖 Section Header（Capsule 側條 + 計數膠囊）

    private var chartSectionHeader: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(LinearGradient(
                    colors: [.indigo, .indigo.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 4, height: 16)
            Image(systemName: "chart.dots.scatter")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.indigo)
            Text("散布圖分析")
                .font(.subheadline.weight(.bold))
            Spacer()
            Text("\(members.count) 人")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.indigo)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.indigo.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.indigo.opacity(0.22), lineWidth: 0.6))
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

    // [v3] 象限人數（供英雄卡 + 圖例雙用，消除重複計算；ctx 已預算好分數與 X/Y 軸中位數）
    private func starCount(_ ctx: AxisContext) -> Int        { members.filter { Double(proactivity($0, ctx)) >= ctx.xMid && Double(potential($0, ctx)) >= ctx.yMid }.count }
    private func potentialCount(_ ctx: AxisContext) -> Int   { members.filter { Double(proactivity($0, ctx)) < ctx.xMid  && Double(potential($0, ctx)) >= ctx.yMid }.count }
    private func hardWorkerCount(_ ctx: AxisContext) -> Int  { members.filter { Double(proactivity($0, ctx)) >= ctx.xMid && Double(potential($0, ctx)) < ctx.yMid  }.count }
    private func needsImprovCount(_ ctx: AxisContext) -> Int { members.filter { Double(proactivity($0, ctx)) < ctx.xMid  && Double(potential($0, ctx)) < ctx.yMid  }.count }

    // [v3] 象限標籤 helper（依個人分數回傳名稱與對應色）
    private func quadrantLabel(_ m: Subordinate, _ ctx: AxisContext) -> (name: String, color: Color) {
        let hiX = Double(proactivity(m, ctx)) >= ctx.xMid
        let hiY = Double(potential(m, ctx)) >= ctx.yMid
        switch (hiY, hiX) {
        case (true, true):   return ("明星", .green)
        case (true, false):  return ("潛力股", .blue)
        case (false, true):  return ("苦勞型", .orange)
        default:             return ("待加強", .red)
        }
    }

    private func pointColor(_ m: Subordinate, _ ctx: AxisContext) -> Color {
        let hiX = Double(proactivity(m, ctx)) >= ctx.xMid
        let hiY = Double(potential(m, ctx)) >= ctx.yMid
        switch (hiY, hiX) {
        case (true, true):   return .green     // 高潛力高主動：明星
        case (true, false):  return .blue      // 高潛力低主動：潛力股
        case (false, true):  return .orange    // 低潛力高主動：苦勞型
        case (false, false): return .red        // 低潛力低主動：待加強
        }
    }

    private func chart(_ ctx: AxisContext) -> some View {
        Chart {
            // 象限分隔線
            RuleMark(x: .value("主動性中位", ctx.xMid))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color(.separator))
            RuleMark(y: .value("潛力中位", ctx.yMid))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color(.separator))

            ForEach(members) { m in
                PointMark(
                    x: .value("主動性", proactivity(m, ctx)),
                    y: .value("潛力", potential(m, ctx))
                )
                .symbolSize(140)
                .foregroundStyle(pointColor(m, ctx))
                // [v3] 升級為彩色 Capsule 徽章，顏色對應象限色，與散點視覺一致
                .annotation(position: .top, spacing: 1) {
                    Text(m.name.isEmpty ? "未命名" : m.name)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(pointColor(m, ctx))
                        .lineLimit(1)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(pointColor(m, ctx).opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(pointColor(m, ctx).opacity(0.22), lineWidth: 0.5))
                }
            }
        }
        .chartXScale(domain: ctx.xRange)
        .chartYScale(domain: ctx.yRange)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .onTapGesture { loc in selectNearest(at: loc, proxy: proxy, geo: geo, ctx: ctx) }
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
        // [v3] 進場淡入，英雄卡後輕微延遲呈現
        .opacity(chartAppeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.38).delay(0.10)) { chartAppeared = true }
        }
    }

    // [v1] 升級為白底卡片 + Capsule 漸層側條 section header，對齊全 App 設計語言
    private func quadrantLegend(_ ctx: AxisContext) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(LinearGradient(
                        colors: [.indigo, .indigo.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 4, height: 16)
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.indigo)
                Text("象限圖例")
                    .font(.subheadline.weight(.bold))
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)

            legendRow(.green,  "明星",  "高潛力・高主動", count: starCount(ctx))
            legendRow(.blue,   "潛力股", "高潛力・低主動", count: potentialCount(ctx))
            legendRow(.orange, "苦勞型", "低潛力・高主動", count: hardWorkerCount(ctx))
            legendRow(.red,    "待加強", "低潛力・低主動", count: needsImprovCount(ctx))

            Spacer(minLength: 10)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.10), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
        // [v3] 進場淡入，最後出現形成視覺梯次
        .opacity(legendAppeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.38).delay(0.18)) { legendAppeared = true }
        }
    }

    // [v1] 升級為 28pt 漸層圓 + stroke + 主/副標題，對齊 FinanceChartView 圖例列規格
    // [v3] 新增 count 人數膠囊，讓圖例同時顯示各象限實際人數
    private func legendRow(_ color: Color, _ title: String, _ subtitle: String, count: Int) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [color.opacity(0.22), color.opacity(0.09)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 28, height: 28)
                Circle()
                    .stroke(color.opacity(0.20), lineWidth: 0.75)
                    .frame(width: 28, height: 28)
                Circle().fill(color).frame(width: 9, height: 9)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // [v3] 象限人數膠囊
            Text("\(count) 人")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(color.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    // 找最靠近點擊位置的成員（命中半徑 50pt）
    private func selectNearest(at loc: CGPoint, proxy: ChartProxy, geo: GeometryProxy, ctx: AxisContext) {
        guard let anchor = proxy.plotFrame else { return }
        let rect = geo[anchor]
        var best: Subordinate?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for m in members {
            guard let px = proxy.position(forX: proactivity(m, ctx)),
                  let py = proxy.position(forY: potential(m, ctx)) else { continue }
            let p = CGPoint(x: rect.minX + px, y: rect.minY + py)
            let d = hypot(p.x - loc.x, p.y - loc.y)
            if d < bestDist { bestDist = d; best = m }
        }
        if let best, bestDist < 50 {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { selected = best }
        }
    }

    // [v1] breakdownCard 標頭：40pt 動態漸層圓 + 姓名 + 分數 Capsule 徽章
    private func breakdownCard(_ m: Subordinate, _ ctx: AxisContext) -> some View {
        let accent = pointColor(m, ctx)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                // 40pt 依象限色的漸層圓，對齊 SubordinateView.subordinateRow 規格
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [accent.opacity(0.26), accent.opacity(0.10)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 40, height: 40)
                        .shadow(color: accent.opacity(0.20), radius: 6, x: 0, y: 3)
                    Circle()
                        .stroke(accent.opacity(0.22), lineWidth: 0.75)
                        .frame(width: 40, height: 40)
                    Image(systemName: "person.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(m.name.isEmpty ? "未命名" : m.name)
                        .font(.subheadline.weight(.bold))
                    // [v3] 象限標籤：直觀顯示此人的矩陣位置，對應象限色
                    let ql = quadrantLabel(m, ctx)
                    HStack(spacing: 5) {
                        Text("主動 \(proactivity(m, ctx))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(Color.blue.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.blue.opacity(0.22), lineWidth: 0.5))
                        Text("潛力 \(m.potentialScore)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(Color.indigo.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.indigo.opacity(0.22), lineWidth: 0.5))
                        Text(ql.name)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(ql.color)
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(ql.color.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(ql.color.opacity(0.25), lineWidth: 0.75))
                    }
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { selected = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    breakdownGroup("主動性（日常）", color: .blue, total: proactivity(m, ctx), items: m.proactivityBreakdown(mentionedCount: ctx.mentionCounts[m.id] ?? 0,
                                                                  sideRoleDone: ctx.sideRoleCounts[m.id]?.done ?? 0))
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

    // [v1] 升級為 Capsule 側條 + 分數 Capsule 徽章；明細列加分/扣分改彩色膠囊
    // [v4] 分隔線改用主題色 Rectangle 細線，取代系統灰色 Divider()
    private func breakdownGroup(_ title: String, color: Color, total: Int,
                                items: [(label: String, points: Int)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 3, height: 14)
                Text(title).font(.subheadline.weight(.bold))
                Spacer()
                Text("\(total) 分")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.5))
            }
            Rectangle().fill(color.opacity(0.20)).frame(height: 0.5)
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                HStack {
                    Text(it.label).font(.caption).foregroundStyle(.primary)
                    Spacer()
                    let ptColor: Color = it.points >= 0 ? .green : .red
                    Text(it.points >= 0 ? "+\(it.points)" : "\(it.points)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ptColor)
                        .monospacedDigit()
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(ptColor.opacity(0.09))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // [v1] 升級為雙層脈衝光環 + 漸層底圓，對齊全 App 空狀態設計規格
    private var emptyHint: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.06))
                    .frame(width: 90, height: 90)
                    .scaleEffect(emptyPulse ? 1.18 : 1.0)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: emptyPulse)
                Circle()
                    .fill(Color.indigo.opacity(0.04))
                    .frame(width: 68, height: 68)
                    .scaleEffect(emptyPulse ? 1.22 : 1.0)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true).delay(0.3), value: emptyPulse)
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.indigo.opacity(0.24), Color.indigo.opacity(0.10)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 52, height: 52)
                        .shadow(color: Color.indigo.opacity(0.18), radius: 8, x: 0, y: 4)
                    Circle()
                        .stroke(Color.indigo.opacity(0.20), lineWidth: 0.75)
                        .frame(width: 52, height: 52)
                    Image(systemName: "chart.dots.scatter")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color.indigo.opacity(0.65))
                }
            }
            .onAppear { emptyPulse = true }
            .onDisappear { emptyPulse = false }
            Text(selectedDeptIds.isEmpty ? "尚無部屬資料" : "所選部門沒有部屬")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("請先新增部屬並記錄評分")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
