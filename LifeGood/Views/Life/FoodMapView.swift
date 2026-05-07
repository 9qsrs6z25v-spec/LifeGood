import SwiftUI
import MapKit

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

    @State private var range: FoodMapRange = .all
    @State private var sort: FoodMapSort = .visits
    @State private var selectedCompanion: String? = nil  // nil = 全部
    @State private var selectedAggregate: RestaurantAggregate?
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                if aggregates.isEmpty {
                    emptyState
                } else {
                    mapView
                        .frame(height: 320)
                    statsCard
                    restaurantList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("美食地圖")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedAggregate) { agg in
                RestaurantDetailSheet(aggregate: agg)
                    .environmentObject(expenseStore)
            }
        }
    }

    // MARK: - 篩選列

    private var filterBar: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FoodMapRange.allCases) { r in
                        chip(r.rawValue, isSelected: range == r) { range = r }
                    }
                    Divider().frame(height: 16)
                    ForEach(FoodMapSort.allCases) { s in
                        chip(s.rawValue, isSelected: sort == s, tint: .orange) { sort = s }
                    }
                }
                .padding(.horizontal, 12)
            }
            if !companionOptions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("全部家人", isSelected: selectedCompanion == nil, tint: .pink) {
                            selectedCompanion = nil
                        }
                        ForEach(companionOptions, id: \.self) { name in
                            chip(name, isSelected: selectedCompanion == name, tint: .pink) {
                                selectedCompanion = name
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private func chip(_ label: String, isSelected: Bool, tint: Color = .green, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? tint : Color(.tertiarySystemFill))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 地圖

    private var mapView: some View {
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
        .onAppear {
            fitToAnnotations()
        }
        .onChange(of: aggregates.count) { _, _ in
            fitToAnnotations()
        }
    }

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

    private func fitToAnnotations() {
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
    }

    // MARK: - 統計卡

    private var statsCard: some View {
        let total = aggregates.reduce(0) { $0 + $1.totalSpent }
        let visits = aggregates.reduce(0) { $0 + $1.visitCount }
        let avg = visits > 0 ? total / Double(visits) : 0
        let mostVisited = aggregates.max(by: { $0.visitCount < $1.visitCount })

        return HStack(spacing: 0) {
            statBox(value: "\(aggregates.count)", label: "餐廳", color: .blue)
            Divider().frame(height: 36)
            statBox(value: "NT$ \(fmtShort(total))", label: "總花費", color: .red)
            Divider().frame(height: 36)
            statBox(value: "NT$ \(fmtShort(avg))", label: "每次", color: .orange)
            Divider().frame(height: 36)
            statBox(value: mostVisited?.name ?? "—", label: "最常去", color: .green, lineLimit: 1)
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func statBox(value: String, label: String, color: Color, lineLimit: Int = 1) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .lineLimit(lineLimit)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 餐廳清單

    private var restaurantList: some View {
        List {
            Section {
                ForEach(sortedAggregates) { agg in
                    Button { selectedAggregate = agg } label: {
                        restaurantRow(agg)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("餐廳清單（\(sortedAggregates.count)）")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func restaurantRow(_ agg: RestaurantAggregate) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(pinColor(for: agg).opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: "fork.knife")
                    .foregroundStyle(pinColor(for: agg))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(agg.name).font(.subheadline.weight(.medium)).lineLimit(1)
                if !agg.address.isEmpty {
                    Text(agg.address).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text("造訪 \(agg.visitCount) 次")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text("NT$ \(fmtShort(agg.totalSpent))")
                        .font(.caption2).foregroundStyle(.red)
                    if let last = agg.lastVisit {
                        Text("·").foregroundStyle(.tertiary)
                        Text(fmtRelative(last)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 空狀態

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("還沒有任何餐廳記錄")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("在「變動支出」分類選「飲食」並選擇店家後，這裡會顯示地圖。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
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
                .contains(selectedCompanion!))
        }
    }

    private var aggregates: [RestaurantAggregate] {
        let groups = Dictionary(grouping: foodExpensesWithLocation) { exp -> String in
            "\(exp.title)|\(exp.placeAddress ?? "")"
        }
        return groups.compactMap { (key, exps) -> RestaurantAggregate? in
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

    private var headerCard: some View {
        VStack(spacing: 8) {
            if !aggregate.address.isEmpty {
                Label(aggregate.address, systemImage: "mappin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 0) {
                statCol("造訪", "\(aggregate.visitCount) 次", .blue)
                Divider().frame(height: 36)
                statCol("總花費", "NT$ \(fmtNum(aggregate.totalSpent))", .red)
                Divider().frame(height: 36)
                statCol("平均", "NT$ \(fmtNum(aggregate.averageSpent))", .orange)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func statCol(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var visitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("造訪紀錄").font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            VStack(spacing: 0) {
                ForEach(aggregate.visits.sorted { $0.date > $1.date }) { exp in
                    HStack {
                        Text(fmtDate(exp.date)).font(.caption).foregroundStyle(.secondary)
                        if let raw = exp.diningMember, !raw.isEmpty {
                            Text(raw).font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.pink.opacity(0.12))
                                .foregroundStyle(.pink)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Spacer()
                        Text("NT$ \(fmtNum(exp.amount))")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                    Divider().padding(.leading)
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
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
