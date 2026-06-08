import SwiftUI
import MapKit

// MARK: - 美化紀錄（FoodMapView）
// [2026-06] 本次美化方向：
//   1. statsCard（清單 sheet 頂部）：升級為橘色漸層英雄卡片（食物主題配色），
//      含散景裝飾圓 + KPI 格（造訪次數 / 平均每次 / 最常光顧），
//      對齊 VariableExpenseView.monthSummaryHeader 設計規格；
//      加入進場 spring 動畫（statsCardAppeared）
//   2. emptyOverlay：升級為雙層脈衝光環 + 橘色漸層底圓 + 圖示 + 引導說明，
//      對齊 VariableExpenseView.emptyStateView 空狀態設計規格
//   3. restaurantRow：圖示圓升至 44pt + LinearGradient 漸層填色 + 陰影，
//      造訪次數改為彩色膠囊；金額右對齊帶「均」輔助文字，對齊 ExpenseRow 視覺規格
//   4. chip：選中時加入投影（shadow） + scaleEffect(1.04)，對齊 FilterChip 規格
//   5. RestaurantDetailSheet.headerCard：升級為橘色漸層英雄卡片（含散景裝飾圓），
//      stat 改為三格 KPI（含圖示圓），對齊 FinanceOverviewView.totalAssetsCard 規格
//   6. RestaurantDetailSheet.visitsSection：Capsule 側條標題 + 計數膠囊；
//      每列加入 34pt 漸層圖示圓 + 日期膠囊徽章 + 同行者粉紅膠囊，
//      金額右對齊 .rounded 字體，對齊 IncomeView.incomeRow 規格

// MARK: - 餐廳聚合資料

struct RestaurantAggregate: Identifiable {
    let id: String              // 以 「店名|地址」 作 stable key
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let visits: [Expense]
    var visitCount: Int { visits.count }
    var totalSpent: Double { visits.reduce(0) { $0 + $1.amount } }
    var averageSpent: Double { visitCount > 0 ? totalSpent / Double(visitCount) : 0 }
    var lastVisit: Date? { visits.map(\.date).max() }
    /// 最常一起共餐的家人
    var topCompanion: String? {
        var counts: [String: Int] = [:]
        for exp in visits {
            guard let raw = exp.diningMember, !raw.isEmpty else { continue }
            for name in raw.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespaces) })
                where !name.isEmpty {
                counts[name, default: 0] += 1
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}

// MARK: - 篩選範圍

enum FoodMapRange: String, CaseIterable, Identifiable {
    case month = "本月"
    case quarter = "近 3 月"
    case half = "近半年"
    case year = "近一年"
    case all = "全部"
    var id: String { rawValue }

    func contains(_ date: Date) -> Bool {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .month:
            return cal.isDate(date, equalTo: now, toGranularity: .month)
        case .quarter:
            guard let from = cal.date(byAdding: .month, value: -3, to: now) else { return true }
            return date >= from
        case .half:
            guard let from = cal.date(byAdding: .month, value: -6, to: now) else { return true }
            return date >= from
        case .year:
            guard let from = cal.date(byAdding: .year, value: -1, to: now) else { return true }
            return date >= from
        case .all:
            return true
        }
    }
}

enum FoodMapSort: String, CaseIterable, Identifiable {
    case visits = "造訪次數"
    case spent = "總花費"
    case recent = "最近造訪"
    var id: String { rawValue }
}

// MARK: - 主畫面

struct FoodMapView: View {
    @EnvironmentObject var expenseStore: ExpenseStore
    @ObservedObject private var locationProvider = LocationProvider.shared

    @State private var range: FoodMapRange = .all
    @State private var sort: FoodMapSort = .visits
    @State private var selectedCompanion: String? = nil  // nil = 全部
    @State private var selectedAggregate: RestaurantAggregate?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasCenteredInitially = false
    @State private var showListSheet = false
    @State private var photoOnly = false
    @State private var emptyIconPulse = false
    @State private var statsCardAppeared = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                mapLayer

                topOverlay
                    .padding(.top, 8)
                    .padding(.horizontal, 10)

                bottomOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)

                if aggregates.isEmpty {
                    emptyOverlay
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                LocationProvider.shared.requestIfNeeded()
                tryInitialCenter()
            }
            .onChange(of: locationProvider.lastLocation) { _, _ in
                tryInitialCenter()
            }
            .onChange(of: aggregates.count) { _, _ in
                tryInitialCenter()
            }
            .sheet(item: $selectedAggregate) { agg in
                RestaurantDetailSheet(aggregate: agg)
                    .environmentObject(expenseStore)
            }
            .sheet(isPresented: $showListSheet) {
                listSheet
            }
        }
    }

    // MARK: - 地圖底層

    private var mapLayer: some View {
        Map(position: $cameraPosition) {
            ForEach(aggregates) { agg in
                Annotation(agg.name, coordinate: agg.coordinate) {
                    Button {
                        selectedAggregate = agg
                    } label: {
                        ZStack {
                            Circle()
                                .fill(pinColor(for: agg))
                                .frame(width: pinSize(for: agg), height: pinSize(for: agg))
                                .shadow(radius: 2)
                            Text("\(agg.visitCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - 上層 overlay：標題 + 篩選

    private var topOverlay: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("美食地圖")
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)

            VStack(alignment: .leading, spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(FoodMapRange.allCases) { r in
                            chip(r.rawValue, isSelected: range == r) { range = r }
                        }
                    }
                }
                if !companionOptions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            chip("全部家人", isSelected: selectedCompanion == nil, tint: .pink) {
                                selectedCompanion = nil
                            }
                            ForEach(companionOptions, id: \.self) { name in
                                chip(name, isSelected: selectedCompanion == name, tint: .pink) {
                                    selectedCompanion = name
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 下層 overlay：清單按鈕 + 照片開關

    private var bottomOverlay: some View {
        HStack {
            Button {
                showListSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                    Text("餐廳清單")
                        .font(.caption.weight(.semibold))
                    Text("\(sortedAggregates.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.green)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                photoOnly.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: photoOnly ? "photo.fill" : "photo")
                    Text("照片")
                        .font(.caption.weight(.semibold))
                    // 開關指示
                    Image(systemName: photoOnly ? "checkmark.circle.fill" : "circle")
                        .font(.caption2)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(photoOnly ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.ultraThinMaterial))
                .foregroundStyle(photoOnly ? .white : .primary)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 空狀態 overlay（雙層脈衝光環 + 橘色漸層底圓）

    private var emptyOverlay: some View {
        let accent = Color(red: 1.00, green: 0.55, blue: 0.18)
        let isPhotoFilter = photoOnly
        return VStack(spacing: 16) {
            ZStack {
                if !isPhotoFilter {
                    // 外層脈衝光環（對齊 VariableExpenseView emptyStateView 雙層環規格）
                    Circle()
                        .stroke(accent.opacity(emptyIconPulse ? 0 : 0.25), lineWidth: 1.5)
                        .frame(width: 108, height: 108)
                        .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                        .animation(
                            .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                            value: emptyIconPulse
                        )
                    // 內層脈衝光環（延遲 0.3s，製造波紋層次）
                    Circle()
                        .stroke(accent.opacity(emptyIconPulse ? 0 : 0.13), lineWidth: 1)
                        .frame(width: 108, height: 108)
                        .scaleEffect(emptyIconPulse ? 1.62 : 1.0)
                        .animation(
                            .easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false),
                            value: emptyIconPulse
                        )
                }
                // 主圓底（漸層填色 + 細邊框）
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isPhotoFilter
                                ? [Color(.systemFill), Color(.secondarySystemFill)]
                                : [accent.opacity(0.15), accent.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .overlay(
                        Circle()
                            .stroke(isPhotoFilter ? Color.clear : accent.opacity(0.22), lineWidth: 1.2)
                    )
                Image(systemName: isPhotoFilter ? "photo" : "fork.knife.circle")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(isPhotoFilter ? .secondary : accent.opacity(0.72))
            }
            .onAppear {
                if !isPhotoFilter {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        emptyIconPulse = true
                    }
                }
            }
            .onDisappear { emptyIconPulse = false }

            VStack(spacing: 8) {
                Text(isPhotoFilter ? "目前沒有附照片的餐廳" : "還沒有任何餐廳記錄")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                Text(isPhotoFilter
                     ? "關閉右上角「照片」開關可查看全部餐廳"
                     : "在「變動支出」分類選「飲食」\n並選擇店家後，這裡會顯示地圖")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 清單 sheet

    private var listSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statsCard
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FoodMapSort.allCases) { s in
                            chip(s.rawValue, isSelected: sort == s, tint: .orange) { sort = s }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 8)
                List {
                    ForEach(sortedAggregates) { agg in
                        Button {
                            showListSheet = false
                            // 等 sheet 關閉再開另一張詳細 sheet
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                selectedAggregate = agg
                            }
                        } label: {
                            restaurantRow(agg)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("餐廳清單（\(sortedAggregates.count)）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("關閉") { showListSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 篩選 chip（對齊 FilterChip 規格：shadow + scaleEffect）

    private func chip(_ label: String, isSelected: Bool, tint: Color = .green, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(isSelected ? .semibold : .medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? tint : Color(.tertiarySystemFill))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
                .shadow(color: isSelected ? tint.opacity(0.32) : .clear, radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isSelected)
    }

    // MARK: - 地圖

    /// 依造訪次數決定 pin 大小（22~44）
    private func pinSize(for agg: RestaurantAggregate) -> CGFloat {
        let maxVisits = aggregates.map(\.visitCount).max() ?? 1
        let ratio = Double(agg.visitCount) / Double(maxVisits)
        return CGFloat(22 + ratio * 22)
    }

    private func pinColor(for agg: RestaurantAggregate) -> Color {
        let count = agg.visitCount
        if count >= 10 { return .red }
        if count >= 5 { return .orange }
        if count >= 2 { return .yellow }
        return .blue
    }

    /// 第一次顯示地圖時：有定位 → 以使用者為中心 10 公里範圍；
    /// 沒定位時若有餐廳資料 → 自動框出全部餐廳。
    private func tryInitialCenter() {
        guard !hasCenteredInitially else { return }
        if let loc = locationProvider.lastLocation {
            cameraPosition = .region(MKCoordinateRegion(
                center: loc.coordinate,
                latitudinalMeters: 10000, longitudinalMeters: 10000
            ))
            hasCenteredInitially = true
            return
        }
        // 沒定位 → 如果有餐廳資料就框全部
        guard !aggregates.isEmpty else { return }
        let lats = aggregates.map(\.coordinate.latitude)
        let lons = aggregates.map(\.coordinate.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.01, (maxLon - minLon) * 1.4)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        hasCenteredInitially = true
    }

    // MARK: - 統計卡（橘色漸層英雄卡片）

    private var statsCard: some View {
        let total = aggregates.reduce(0) { $0 + $1.totalSpent }
        let visits = aggregates.reduce(0) { $0 + $1.visitCount }
        let avg = visits > 0 ? total / Double(visits) : 0
        let mostVisited = aggregates.max(by: { $0.visitCount < $1.visitCount })

        return VStack(spacing: 0) {
            // 頂部：餐廳總數 + 總花費大字
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("美食探索紀錄")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                    Text("NT$ \(fmtShort(total))")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                Spacer()
                Text("\(aggregates.count) 間")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(.white.opacity(0.22))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            }

            // KPI 橫列：造訪次數 / 平均每次 / 最常光顧
            HStack(spacing: 0) {
                foodKpiCell(label: "造訪總次", value: "\(visits) 次")
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 28)
                foodKpiCell(label: "平均每次", value: "NT$ \(fmtShort(avg))")
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 28)
                foodKpiCell(label: "最常光顧", value: mostVisited?.name ?? "—")
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.55, blue: 0.18),
                        Color(red: 0.85, green: 0.32, blue: 0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 裝飾性散景圓，增加卡片層次感
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 120, height: 120)
                    .offset(x: 80, y: -40)
                    .blur(radius: 12)
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 70, height: 70)
                    .offset(x: -55, y: 42)
                    .blur(radius: 8)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.85, green: 0.32, blue: 0.05).opacity(0.38), radius: 14, x: 0, y: 7)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .opacity(statsCardAppeared ? 1 : 0)
        .offset(y: statsCardAppeared ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                statsCardAppeared = true
            }
        }
    }

    private func foodKpiCell(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    // MARK: - 餐廳列（44pt 漸層圖示圓 + 彩色膠囊標籤）

    private func restaurantRow(_ agg: RestaurantAggregate) -> some View {
        let accent = pinColor(for: agg)
        return HStack(spacing: 12) {
            // 44pt 漸層圖示圓（對齊 ExpenseRow 規格）
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
                Image(systemName: "fork.knife")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(agg.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !agg.address.isEmpty {
                    Text(agg.address)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                // 造訪次數膠囊 + 最近造訪日
                HStack(spacing: 5) {
                    Text("造訪 \(agg.visitCount) 次")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(accent.opacity(0.12))
                        .clipShape(Capsule())
                    if let last = agg.lastVisit {
                        Text(fmtRelative(last))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 4)

            // 右側：總花費 + 平均
            VStack(alignment: .trailing, spacing: 3) {
                Text("NT$ \(fmtShort(agg.totalSpent))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.85, green: 0.32, blue: 0.05))
                    .contentTransition(.numericText())
                Text("均 NT$ \(fmtShort(agg.averageSpent))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 資料聚合

    private var foodExpensesWithLocation: [Expense] {
        expenseStore.expenses.filter { exp in
            exp.expenseType == .variable
            && exp.variableCategory == .food
            && exp.placeLatitude != nil
            && exp.placeLongitude != nil
            && range.contains(exp.date)
            && (selectedCompanion == nil || (exp.diningMember ?? "")
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .contains(selectedCompanion ?? ""))
        }
    }

    private var aggregates: [RestaurantAggregate] {
        let groups = Dictionary(grouping: foodExpensesWithLocation) { exp -> String in
            "\(exp.title)|\(exp.placeAddress ?? "")"
        }
        let all: [RestaurantAggregate] = groups.compactMap { (key, exps) -> RestaurantAggregate? in
            guard let first = exps.first,
                  let lat = first.placeLatitude,
                  let lon = first.placeLongitude else { return nil }
            return RestaurantAggregate(
                id: key,
                name: first.title,
                address: first.placeAddress ?? "",
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                visits: exps
            )
        }
        if photoOnly {
            return all.filter { agg in agg.visits.contains { !$0.photoFileNames.isEmpty } }
        }
        return all
    }

    private var sortedAggregates: [RestaurantAggregate] {
        switch sort {
        case .visits:
            return aggregates.sorted { $0.visitCount > $1.visitCount }
        case .spent:
            return aggregates.sorted { $0.totalSpent > $1.totalSpent }
        case .recent:
            return aggregates.sorted { ($0.lastVisit ?? .distantPast) > ($1.lastVisit ?? .distantPast) }
        }
    }

    private var companionOptions: [String] {
        var set = Set<String>()
        for exp in expenseStore.expenses where
            exp.expenseType == .variable && exp.variableCategory == .food {
            guard let raw = exp.diningMember, !raw.isEmpty else { continue }
            for n in raw.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespaces) })
                where !n.isEmpty {
                set.insert(n)
            }
        }
        return set.sorted()
    }

    // MARK: - 格式化

    private func fmtShort(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        if abs(v) >= 10_000 {
            let s = f.string(from: NSNumber(value: v / 10_000)) ?? "0"
            return "\(s)萬"
        }
        return f.string(from: NSNumber(value: v)) ?? "0"
    }

    private func fmtRelative(_ date: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                       to: cal.startOfDay(for: Date())).day ?? 0
        if days == 0 { return "今天" }
        if days == 1 { return "昨天" }
        if days < 7 { return "\(days) 天前" }
        if days < 30 { return "\(days / 7) 週前" }
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"
        return f.string(from: date)
    }
}

// MARK: - 餐廳詳細 Sheet

struct RestaurantDetailSheet: View {
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    let aggregate: RestaurantAggregate
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Map(position: $cameraPosition) {
                        Marker(aggregate.name, coordinate: aggregate.coordinate)
                            .tint(.red)
                    }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    headerCard

                    if !aggregatePhotos.isEmpty {
                        photoGallerySection
                    }

                    visitsSection

                    if let companion = aggregate.topCompanion {
                        companionCard(companion)
                    }

                    Button {
                        openInMaps()
                    } label: {
                        Label("用地圖開啟", systemImage: "map.fill")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(aggregate.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
            }
            .onAppear {
                cameraPosition = .region(MKCoordinateRegion(
                    center: aggregate.coordinate,
                    latitudinalMeters: 800, longitudinalMeters: 800
                ))
            }
        }
    }

    // 餐廳詳情英雄卡（橘色漸層，對齊 FinanceOverviewView.totalAssetsCard 設計語言）
    private var headerCard: some View {
        VStack(spacing: 0) {
            // 地址列
            if !aggregate.address.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.caption)
                    Text(aggregate.address)
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.82))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            }

            // KPI 三格：造訪次數 / 總花費 / 平均每次
            HStack(spacing: 0) {
                detailKpiCell(icon: "calendar.circle.fill", label: "造訪次數",
                              value: "\(aggregate.visitCount) 次")
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 32)
                detailKpiCell(icon: "yensign.circle.fill", label: "總花費",
                              value: "NT$ \(fmtNum(aggregate.totalSpent))")
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 32)
                detailKpiCell(icon: "chart.bar.fill", label: "平均每次",
                              value: "NT$ \(fmtNum(aggregate.averageSpent))")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.55, blue: 0.18),
                        Color(red: 0.85, green: 0.32, blue: 0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 110, height: 110)
                    .offset(x: 70, y: -35)
                    .blur(radius: 12)
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 65, height: 65)
                    .offset(x: -50, y: 35)
                    .blur(radius: 8)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.85, green: 0.32, blue: 0.05).opacity(0.38), radius: 14, x: 0, y: 7)
        .padding(.horizontal)
    }

    private func detailKpiCell(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.85))
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    /// 此餐廳所有造訪所累積的照片檔名
    private var aggregatePhotos: [String] {
        aggregate.visits.flatMap { $0.photoFileNames }
    }

    @State private var viewingPhotoURL: IdentifiableURL?

    private var photoGallerySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "photo.stack").foregroundStyle(.orange)
                Text("照片（\(aggregatePhotos.count)）")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(aggregatePhotos, id: \.self) { name in
                        let url = Expense.photoURL(for: name)
                        Button {
                            viewingPhotoURL = IdentifiableURL(url: url)
                        } label: {
                            if let img = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 110, height: 90)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.tertiarySystemFill))
                                    .frame(width: 110, height: 90)
                                    .overlay(
                                        Image(systemName: "icloud.and.arrow.down")
                                            .foregroundStyle(.tertiary)
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .sheet(item: $viewingPhotoURL) { wrapper in
            PhotoLightbox(url: wrapper.url)
        }
    }

    // 造訪紀錄（Capsule 側條標題 + 34pt 漸層圖示圓 + 日期膠囊 + 同行者粉紅膠囊）
    private var visitsSection: some View {
        let accent = Color(red: 1.00, green: 0.55, blue: 0.18)
        let sorted = aggregate.visits.sorted { $0.date > $1.date }

        return VStack(alignment: .leading, spacing: 8) {
            // Section header（Capsule 側條 + 計數膠囊，對齊 milestoneTimelineSection 規格）
            HStack(spacing: 10) {
                Capsule()
                    .fill(LinearGradient(
                        colors: [accent, accent.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 4, height: 18)
                Text("造訪紀錄")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("\(sorted.count) 筆")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(accent.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.75))
            }
            .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, exp in
                    HStack(spacing: 10) {
                        // 34pt 漸層圖示圓
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [accent.opacity(0.18), accent.opacity(0.07)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .frame(width: 34, height: 34)
                            Image(systemName: "fork.knife")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(accent.opacity(0.85))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            // 日期膠囊徽章
                            Text(fmtDate(exp.date))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(accent.opacity(0.10))
                                .clipShape(Capsule())
                            // 同行者粉紅膠囊
                            if let raw = exp.diningMember, !raw.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 9))
                                    Text(raw)
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundStyle(.pink)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.pink.opacity(0.10))
                                .clipShape(Capsule())
                            }
                        }

                        Spacer(minLength: 4)

                        Text("NT$ \(fmtNum(exp.amount))")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.85, green: 0.32, blue: 0.05))
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if idx < sorted.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
            .padding(.horizontal)
        }
    }

    private func companionCard(_ name: String) -> some View {
        HStack {
            Image(systemName: "person.2.fill").foregroundStyle(.pink)
            Text("最常一起：")
                .font(.caption).foregroundStyle(.secondary)
            Text(name).font(.caption.weight(.semibold))
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func openInMaps() {
        let coord = aggregate.coordinate
        let placemark = MKPlacemark(coordinate: coord)
        let item = MKMapItem(placemark: placemark)
        item.name = aggregate.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsMapTypeKey: NSNumber(value: MKMapType.standard.rawValue)
        ])
    }

    private func fmtNum(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "0"
    }

    private func fmtDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"
        return f.string(from: date)
    }
}
