import SwiftUI

// MARK: - 美化紀錄（ChildrenResumeView）
// [2026-06 v1] 本次美化方向：
//   1. childCard → 左側 4pt 藍/粉依性別漸層強調條 + 44pt LinearGradient 漸層圖示圓 + 陰影，
//      對齊 FamilyView.memberRow / StockView.stockCard 卡片規格
//   2. 角色膠囊 → 從 RoundedRectangle(cornerRadius:4) 升級為 Capsule，
//      padding 從 (.horizontal,6)(.vertical,2) 統一為 (.horizontal,7)(.vertical,2.5)，
//      對齊 VehicleView / SavingsInsuranceView vehicleCard 膠囊規格
//   3. 生日資訊 → 日期加圖示膠囊徽章，年齡文字改為彩色膠囊（對齊 SpouseResumeView.marriageRow 規格）
//   4. recordBadge → 從純文字圖示升級為微型彩色膠囊（帶半透明背景），資訊密度與可讀性提升
//   5. 空狀態 → 雙層脈衝光環 + 漸層底圓 + 圖示 + 說明文字，
//      對齊 FamilyView.emptyMembersPlaceholder / VariableExpenseView.emptyStateView 規格
//   6. 卡片列表 → 交錯淡入 + 向上進場動畫（cardsAppeared），對齊 FamilyView membersAppeared 規格
//   7. DateFormatter 改為靜態共用實例，避免每次 render 重新分配
// [2026-06 v2] 本次美化方向：
//   8. heroStatsCard：頂部新增「粉藍雙色漸層」英雄統計卡（兒子藍→女兒粉），
//      含兒子/女兒/生涯紀錄 KPI 橫列 + 右上計數膠囊 + 散景裝飾圓，
//      加入 heroAppeared spring 進場動畫，對齊 SubordinateView.summaryStatsBar 規格。
//   9. childrenSectionHeader：清單區塊上方加入「Capsule 4pt 漸層側條 + 兒女 N 位計數膠囊」，
//      對齊 StockView.activeStocksSectionHeader / FamilyView sectionHeader 標題規格。
//  10. childCard 圖示圓：補入 Circle().stroke(accent.opacity(0.18), lineWidth:0.75) overlay，
//      對齊 OverviewView.recentRow v3 stroke border 規格，視覺與 categoryRow 圖示圓一致。
//  11. .navigationBarTitleDisplayMode(.large) 補齊，與其他列表頁 (IncomeView / StockView) 對齊。
// [2026-06 v3] 本次美化方向：
//  12. heroStatsCard 第三顆散景圓（中右 55pt, white.opacity(0.06), blur 8）：
//      補齊第三顆，對齊 IncomeView / VariableExpenseView v4 /
//      SubordinateDetailView v3 三圓散景標準規格（140/90/55 pt）。
//  13. heroStatsCard 頂部玻璃光澤：white.opacity(0.15)→clear 升為 white.opacity(0.18)→clear，
//      對齊全 App 英雄卡玻璃光澤統一規格（OverviewView / IncomeView / VariableExpenseView v3）。
//  14. heroStatsCard KPI 橫列前補入 white.opacity(0.20) 分隔線（0.5pt），
//      對齊 IncomeView.summaryHeader / VehicleView summaryHeader KPI 分隔線規格。
//  15. heroKpiCell 補 28pt LinearGradient 半透明圖示圓（icon 參數）+
//      contentTransition(.numericText()) 讓 KPI 有視覺錨點且數字切換流暢，
//      對齊 SubordinateOverviewView v3 heroKpiCell / TalentMatrixView.heroKpiCell 規格。
//  16. heroStatsCard 兒子/女兒計數膠囊補 Capsule stroke 邊框（white.opacity(0.30) 0.75pt），
//      對齊全 App Capsule 計數徽章細邊框規格（SubordinateOverviewView v3 /
//      TalentMatrixView.summaryHeroCard 計數膠囊規格）。
//  17. childCardNameRow 角色膠囊補 Capsule stroke 細邊框（accent.opacity(0.22) 0.6pt），
//      對齊 FamilyView.memberRow v2 / CareerView v3 膠囊細邊框規格，消除同頁膠囊
//      有無邊框不均衡。
//  18. childCardBirthdayRow 年齡膠囊補 Capsule stroke 細邊框（accent.opacity(0.22) 0.6pt），
//      對齊 childCardNameRow 膠囊規格，讓同卡片兩種膠囊視覺語言一致。
//  19. childCard shadow 升級為雙層：accent 色調光暈（radius 6, opacity 0.18）+
//      黑底基礎（radius 8, opacity 0.06），對齊 SubordinateOverviewView v3 /
//      MyCalendarView 雙層 shadow 規格，提升卡片立體感。
// [2026-07 v4] 大字自適應補齊：
//  20. heroStatsCard 頂部「兒女總覽」42pt 總數大字原本沒有 lineLimit/minimumScaleFactor，
//      是本卡片唯一沒有防截斷保護的大字（同卡片 heroKpiCell 的 KPI 數字、childCard 的
//      角色/年齡膠囊皆已有 lineLimit(1) + minimumScaleFactor），資料量大或大字級輔助模式下
//      有被截斷風險。補上 .lineLimit(1) + .minimumScaleFactor(0.6)，對齊 heroKpiCell 既有
//      防截斷規格，維持在可辨識最小字級以上。純視覺調整，children.count 等既有資料邏輯
//      完全未變動。
//      （下次美化本檔案時，可轉往其他仍留有待辦的畫面）

struct ChildrenResumeView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @State private var viewingChild: FamilyMember?
    @State private var cardsAppeared = false
    @State private var emptyIconPulse = false
    @State private var emptyIconPulseTask: Task<Void, Never>?
    /// [v2] 英雄統計卡進場動畫旗標
    @State private var heroAppeared = false

    // [v2] 英雄卡主題色：藍（兒子）→ 粉紫（女兒），兩色皆用
    private let heroBlue = Color(red: 0.30, green: 0.52, blue: 0.94)
    private let heroPink = Color(red: 0.88, green: 0.28, blue: 0.55)

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    private var children: [FamilyMember] {
        lifeStore.familyMembers
            .filter { $0.role == .son || $0.role == .daughter }
            .sorted { ($0.birthday ?? .distantPast) < ($1.birthday ?? .distantPast) }
    }

    var body: some View {
        // children 是 filter+sort（O(n log n)），一次算好供 heroStatsCard／childrenSectionHeader／
        // ForEach／emptyState 檢查共用，避免同一次 body 求值各自重跑（heroStatsCard 內部原本
        // 就會再獨立呼叫三次）。
        let children = self.children
        NavigationStack {
            ScrollView {
                if children.isEmpty {
                    emptyState
                        .padding(.top, 60)
                } else {
                    VStack(spacing: 0) {
                        // [v2] 英雄統計卡：粉藍漸層 + KPI + 進場動畫
                        heroStatsCard(children)
                            .opacity(heroAppeared ? 1 : 0)
                            .offset(y: heroAppeared ? 0 : 22)
                            .onAppear {
                                withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                    heroAppeared = true
                                }
                            }
                            .onDisappear {
                                // 重置旗標：切到其他分頁再切回時能重新播放英雄卡進場動畫
                                heroAppeared = false
                            }

                        // [v2] 清單區塊標題
                        childrenSectionHeader(children)
                            .padding(.top, 20)
                            .padding(.bottom, 8)

                        LazyVStack(spacing: 12) {
                            ForEach(Array(children.enumerated()), id: \.element.id) { idx, child in
                                childCard(child)
                                    .opacity(cardsAppeared ? 1 : 0)
                                    .offset(y: cardsAppeared ? 0 : 18)
                                    .animation(
                                        .spring(response: 0.45, dampingFraction: 0.82)
                                            .delay(0.06 * Double(idx)),
                                        value: cardsAppeared
                                    )
                                    .onTapGesture { viewingChild = child }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .onAppear {
                            withAnimation(.spring(response: 0.50, dampingFraction: 0.82).delay(0.05)) {
                                cardsAppeared = true
                            }
                        }
                        .onDisappear {
                            // 重置旗標：切到其他分頁再切回時能重新播放卡片列表進場動畫
                            cardsAppeared = false
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("兒女履歷")
            .navigationBarTitleDisplayMode(.large)  // [v2] 對齊 IncomeView / StockView 大標題規格
            .sheet(item: $viewingChild) { child in
                ChildDetailView(child: child)
            }
        }
    }

    // MARK: - [v2] 英雄統計卡

    private func heroStatsCard(_ children: [FamilyMember]) -> some View {
        let sons = children.filter { $0.role == .son }.count
        let daughters = children.filter { $0.role == .daughter }.count
        let totalRecords = children.reduce(0) { $0 + $1.childRecords.count }

        return VStack(spacing: 0) {
            // 頂部：總數大字 + 右側性別膠囊
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("兒女總覽")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(children.count)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("位")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                Spacer()
                // [v3] 計數膠囊補 Capsule stroke 邊框，對齊全 App 計數徽章細邊框規格
                VStack(alignment: .trailing, spacing: 6) {
                    if sons > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.child")
                                .font(.system(size: 10))
                            Text("兒子 \(sons) 位")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(0.22))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 0.75))
                        .foregroundStyle(.white)
                    }
                    if daughters > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.child")
                                .font(.system(size: 10))
                            Text("女兒 \(daughters) 位")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(0.22))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 0.75))
                        .foregroundStyle(.white)
                    }
                }
            }

            // [v3] KPI 橫列前分隔線（對齊 IncomeView / VehicleView summaryHeader 分隔線規格）
            Rectangle()
                .fill(.white.opacity(0.20))
                .frame(height: 0.5)
                .padding(.top, 12)

            // KPI 橫列：兒子 / 女兒 / 生涯紀錄
            HStack(spacing: 0) {
                heroKpiCell(icon: "figure.child", label: "兒子", value: "\(sons) 位")
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 36)
                heroKpiCell(icon: "figure.child.and.lock", label: "女兒", value: "\(daughters) 位")
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 36)
                heroKpiCell(icon: "list.clipboard.fill", label: "生涯紀錄", value: "\(totalRecords) 筆")
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            ZStack {
                // 粉藍雙色漸層：兒子藍（topLeading）→ 女兒粉紫（bottomTrailing）
                LinearGradient(
                    colors: [heroBlue, heroPink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 右上主散景圓（對齊三圓散景 140pt 主圓規格）
                Circle()
                    .fill(.white.opacity(0.13))
                    .frame(width: 130, height: 130)
                    .offset(x: 85, y: -50)
                    .blur(radius: 14)
                    .allowsHitTesting(false)
                // 左下次散景圓（對齊三圓散景 90pt 次圓規格）
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 80, height: 80)
                    .offset(x: -60, y: 40)
                    .blur(radius: 10)
                    .allowsHitTesting(false)
                // [v3] 中右微型散景圓（55pt），補齊三圓散景標準規格
                // 對齊 IncomeView / VariableExpenseView v4 / SubordinateDetailView v3
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 55, height: 55)
                    .offset(x: 30, y: 28)
                    .blur(radius: 8)
                    .allowsHitTesting(false)
                // [v3] 頂部玻璃光澤升為 0.18（對齊全 App 英雄卡統一規格）
                LinearGradient(
                    colors: [.white.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .allowsHitTesting(false)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: heroPink.opacity(0.38), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // [v3] KPI 格：補 28pt LinearGradient 圖示圓 + contentTransition
    // 對齊 SubordinateOverviewView v3 heroKpiCell / TalentMatrixView.heroKpiCell 規格
    private func heroKpiCell(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - [v2] 清單 Section Header

    private func childrenSectionHeader(_ children: [FamilyMember]) -> some View {
        HStack(spacing: 10) {
            // 4pt Capsule 漸層側條（對齊 OverviewView categoryBreakdownSection 標題規格）
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [heroBlue, heroBlue.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 20)
            Text("兒女清單")
                .font(.subheadline.weight(.bold))
            Spacer()
            Text("\(children.count) 位")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(heroBlue)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(heroBlue.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(heroBlue.opacity(0.22), lineWidth: 0.75))
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 兒女卡片（左側強調條 + 漸層圖示圓）

    private func childCard(_ child: FamilyMember) -> some View {
        let isSon = child.role == .son
        let accent: Color = isSon ? .blue : Color(red: 0.96, green: 0.35, blue: 0.60)

        return HStack(spacing: 0) {
            // 左側 4pt 漸層強調條
            RoundedRectangle(cornerRadius: 3)
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

            HStack(spacing: 12) {
                // 44pt 漸層圖示圓 + [v2] stroke border
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
                    // [v2] stroke border：對齊 OverviewView.recentRow v3 stroke border 規格
                    Circle()
                        .stroke(accent.opacity(0.18), lineWidth: 0.75)
                        .frame(width: 44, height: 44)
                    Image(systemName: isSon ? "figure.child" : "figure.child.and.lock")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                }

                childCardInfo(child, accent: accent)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 2)
            }
            .padding(.vertical, 12)
            .padding(.trailing, 14)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accent.opacity(0.10), lineWidth: 0.75)
        )
        // [v3] 雙層陰影：色調光暈 + 黑底基礎，對齊 SubordinateOverviewView v3 規格
        .shadow(color: accent.opacity(0.18), radius: 6, x: 0, y: 2)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    // MARK: - 兒女卡片：中央資訊欄（姓名 / 生日 / 徽章）

    @ViewBuilder
    private func childCardInfo(_ child: FamilyMember, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            childCardNameRow(child, accent: accent)
            if let bd = child.birthday {
                childCardBirthdayRow(bd, accent: accent)
            }
            let badges = recordBadges(for: child)
            if !badges.isEmpty {
                childCardBadgesRow(badges)
            }
        }
    }

    private func childCardNameRow(_ child: FamilyMember, accent: Color) -> some View {
        HStack(spacing: 6) {
            Text(childDisplayName(child))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            // [v3] 角色膠囊補細邊框，對齊 FamilyView v2 / CareerView v3 膠囊規格
            Text(child.role.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 7).padding(.vertical, 2.5)
                .background(accent.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
        }
    }

    private func childCardBirthdayRow(_ bd: Date, accent: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "birthday.cake.fill")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(accent.opacity(0.70))
            Text(Self.dateFormatter.string(from: bd))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            // [v3] 年齡膠囊補細邊框，對齊 childCardNameRow 膠囊設計語言
            Text(ageString(from: bd))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(accent.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
        }
    }

    private func childCardBadgesRow(_ badges: [(type: ChildRecordType, count: Int)]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(badges, id: \.type) { item in
                    recordBadge(type: item.type, count: item.count)
                }
            }
        }
    }

    // MARK: - 紀錄徽章（微型彩色膠囊）

    /// 一次掃描算出各類紀錄筆數（取代原本 7 個 inline filter，降低 body 型別檢查負擔），
    /// 依固定顯示順序回傳「筆數 > 0」的類別。
    private func recordBadges(for child: FamilyMember) -> [(type: ChildRecordType, count: Int)] {
        var counts: [ChildRecordType: Int] = [:]
        for r in child.childRecords { counts[r.type, default: 0] += 1 }
        let order: [ChildRecordType] = [.vaccination, .allergy, .growth, .medical, .education, .hobby, .memorable]
        return order.compactMap { t in
            let n = counts[t] ?? 0
            return n > 0 ? (type: t, count: n) : nil
        }
    }

    private func recordBadge(type: ChildRecordType, count: Int) -> some View {
        let c = colorFor(type)
        return HStack(spacing: 3) {
            Image(systemName: type.icon)
                .font(.system(size: 9, weight: .medium))
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(c)
        .padding(.horizontal, 6).padding(.vertical, 2.5)
        .background(c.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(c.opacity(0.20), lineWidth: 0.5))
    }

    // MARK: - 空狀態（雙層脈衝光環 + 漸層底圓）

    private var emptyState: some View {
        let accent = Color(red: 0.96, green: 0.35, blue: 0.60)
        return VStack(spacing: 24) {
            ZStack {
                // 外層脈衝光環
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.28), lineWidth: 1.5)
                    .frame(width: 110, height: 110)
                    .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 內層脈衝光環（延遲 0.3s）
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.14), lineWidth: 1)
                    .frame(width: 110, height: 110)
                    .scaleEffect(emptyIconPulse ? 1.60 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 漸層底圓
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.14), accent.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .overlay(Circle().stroke(accent.opacity(0.22), lineWidth: 1.2))
                Image(systemName: "figure.2.and.child.holdinghands")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(accent.opacity(0.70))
            }
            .onAppear {
                emptyIconPulse = false
                emptyIconPulseTask?.cancel()
                emptyIconPulseTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    emptyIconPulse = true
                }
            }
            .onDisappear {
                emptyIconPulseTask?.cancel()
                emptyIconPulse = false
            }

            VStack(spacing: 8) {
                Text("尚無兒女資料")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                Text("在家庭頁面新增兒子或女兒後顯示於此")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - Helpers

    private func colorFor(_ type: ChildRecordType) -> Color {
        switch type {
        case .vaccination: return .blue
        case .allergy:     return .red
        case .growth:      return .green
        case .medical:     return .orange
        case .education:   return .purple
        case .hobby:       return .pink
        case .memorable:   return Color(red: 0.95, green: 0.70, blue: 0.12)
        }
    }

    private func childDisplayName(_ child: FamilyMember) -> String {
        if !child.chineseName.isEmpty { return child.chineseName }
        if !child.englishName.isEmpty { return child.englishName }
        return child.role.rawValue
    }

    private func ageString(from birthday: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: birthday, to: Date())
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        if y > 0 { return "\(y) 歲 \(m) 月" }
        return "\(m) 個月"
    }
}
