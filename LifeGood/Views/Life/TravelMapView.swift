import SwiftUI
import MapKit
import UIKit

// MARK: - 旅遊地圖
// 資料來源：變動支出「娛樂」分類且已附經緯度的紀錄。
// 以「項目名稱|地址」聚合成去過的地點，撒點於地圖，並依台灣縣市分組呈現足跡。
// 沿用美食地圖（FoodMapView）驗證過的 MapKit / 照片顯示模式，主題色改為娛樂紫。

// MARK: - 台灣縣市解析（自地址字串推斷縣市）

enum TravelCityParser {
    /// 依「臺」正規化後可比對到的縣市（含直轄市與縣市）。
    static let names: [String] = [
        "基隆市", "臺北市", "新北市", "桃園市", "新竹市", "新竹縣", "苗栗縣",
        "臺中市", "彰化縣", "南投縣", "雲林縣", "嘉義市", "嘉義縣", "臺南市",
        "高雄市", "屏東縣", "宜蘭縣", "花蓮縣", "臺東縣", "澎湖縣", "金門縣", "連江縣"
    ]

    /// 從地址推斷縣市；找不到回傳空字串。會把「台」正規化為「臺」以相容兩種寫法。
    static func parse(_ address: String?) -> String {
        guard let address, !address.isEmpty else { return "" }
        let normalized = address.replacingOccurrences(of: "台", with: "臺")
        return names.first { normalized.contains($0) } ?? ""
    }
}

// MARK: - 旅遊地點聚合資料

struct TravelSpotAggregate: Identifiable {
    let id: String              // 以「名稱|地址」作 stable key
    let name: String
    let address: String
    let city: String            // 解析自地址；未知為 ""
    let coordinate: CLLocationCoordinate2D
    let visits: [Expense]

    var visitCount: Int { visits.count }
    var totalSpent: Double { visits.reduce(0) { $0 + $1.amount } }
    var averageSpent: Double { visitCount > 0 ? totalSpent / Double(visitCount) : 0 }
    var lastVisit: Date? { visits.map(\.date).max() }
    var photoNames: [String] { visits.flatMap { $0.photoFileNames } }

    /// 最常一起同行的家人 / 同伴
    var topCompanion: String? {
        var counts: [String: Int] = [:]
        for exp in visits {
            guard let raw = exp.diningMember, !raw.isEmpty else { continue }
            for name in raw.components(separatedBy: CharacterSet(charactersIn: ",、，"))
                .map({ $0.trimmingCharacters(in: .whitespaces) }) where !name.isEmpty {
                counts[name, default: 0] += 1
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}

// MARK: - 主畫面

struct TravelMapView: View {
    @EnvironmentObject var expenseStore: ExpenseStore
    @StateObject private var locationProvider = LocationProvider.shared

    private let accent = Color(red: 0.68, green: 0.40, blue: 1.00)   // 娛樂紫

    @State private var range: FoodMapRange = .all
    @State private var sort: FoodMapSort = .visits
    @State private var selectedCity: String? = nil        // nil = 全部縣市
    @State private var selectedSpot: TravelSpotAggregate?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasCenteredInitially = false
    @State private var showListSheet = false
    @State private var showAlbumSheet = false
    @State private var photoOnly = false
    @State private var emptyIconPulse = false

    var body: some View {
        let spots = aggregates
        return NavigationStack {
            ZStack(alignment: .topLeading) {
                mapContent(spots)

                topOverlay
                    .padding(.top, 8)
                    .padding(.horizontal, 10)

                bottomOverlay(count: spots.count)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)

                if spots.isEmpty {
                    emptyOverlay
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                LocationProvider.shared.requestIfNeeded()
                tryInitialCenter(spots)
            }
            .onChange(of: locationProvider.lastLocation) { _, _ in tryInitialCenter(spots) }
            .onChange(of: spots.count) { _, _ in tryInitialCenter(spots) }
            .sheet(item: $selectedSpot) { spot in
                TravelSpotDetailSheet(spot: spot)
                    .environmentObject(expenseStore)
            }
            .sheet(isPresented: $showListSheet) { listSheet(spots) }
            .sheet(isPresented: $showAlbumSheet) { TravelAlbumSheet(spots: spots) }
        }
    }

    // MARK: - 地圖底層

    private func mapContent(_ spots: [TravelSpotAggregate]) -> some View {
        let maxCount = spots.map(\.visitCount).max() ?? 1
        return Map(position: $cameraPosition) {
            ForEach(spots) { spot in
                Annotation(spot.name, coordinate: spot.coordinate) {
                    Button {
                        selectedSpot = spot
                    } label: {
                        let sz = pinSize(spot.visitCount, maxCount: maxCount)
                        ZStack {
                            Circle()
                                .fill(pinColor(spot.visitCount))
                                .frame(width: sz, height: sz)
                                .shadow(radius: 2)
                            Text("\(spot.visitCount)")
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

    // MARK: - 上層 overlay：標題 + 期間 + 縣市篩選

    private var topOverlay: some View {
        let cities = cityOptions
        return HStack(alignment: .top, spacing: 8) {
            Text("旅遊地圖")
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
                if !cities.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            chip("全部縣市", isSelected: selectedCity == nil) { selectedCity = nil }
                            ForEach(cities, id: \.self) { city in
                                chip(city, isSelected: selectedCity == city) {
                                    selectedCity = (selectedCity == city) ? nil : city
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 下層 overlay：清單 + 相簿 + 照片開關

    private func bottomOverlay(count: Int) -> some View {
        HStack(spacing: 8) {
            Button { showListSheet = true } label: {
                pillLabel(icon: "list.bullet.rectangle", text: "地點清單", badge: "\(count)")
            }
            .buttonStyle(.plain)

            Button { showAlbumSheet = true } label: {
                pillLabel(icon: "photo.stack", text: "旅遊相簿", badge: nil)
            }
            .buttonStyle(.plain)

            Spacer()

            Button { photoOnly.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: photoOnly ? "photo.fill" : "photo")
                    Text("有照片").font(.caption.weight(.semibold))
                    Image(systemName: photoOnly ? "checkmark.circle.fill" : "circle").font(.caption2)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(photoOnly ? AnyShapeStyle(accent) : AnyShapeStyle(.ultraThinMaterial))
                .foregroundStyle(photoOnly ? .white : .primary)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
        }
    }

    private func pillLabel(icon: String, text: String, badge: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text).font(.caption.weight(.semibold))
            if let badge {
                Text(badge)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(accent)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }

    // MARK: - 空狀態

    private var emptyOverlay: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(accent.opacity(0.16)).frame(width: 92, height: 92)
                    .scaleEffect(emptyIconPulse ? 1.08 : 0.94)
                Circle()
                    .fill(LinearGradient(colors: [accent.opacity(0.9), accent.opacity(0.5)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 60, height: 60)
                Image(systemName: "airplane.departure")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text("還沒有旅遊足跡")
                .font(.headline)
            Text("在「娛樂」變動支出記錄時選擇地點（並可附照片），\n這裡就會標出你去過的地方。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).opacity(0.92))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                emptyIconPulse = true
            }
        }
        .onDisappear { emptyIconPulse = false }
    }

    // MARK: - 清單 sheet（統計卡 + 依縣市分組）

    private func listSheet(_ spots: [TravelSpotAggregate]) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statsCard(spots)
                    sortPicker
                    ForEach(spotsByCity(spots), id: \.city) { group in
                        citySection(group.city, items: group.items)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("旅遊清單")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { showListSheet = false }
                }
            }
        }
    }

    private var sortPicker: some View {
        Picker("排序", selection: $sort) {
            ForEach(FoodMapSort.allCases) { s in Text(s.rawValue).tag(s) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    private func citySection(_ city: String, items: [TravelSpotAggregate]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse").font(.caption).foregroundStyle(accent)
                Text(city).font(.subheadline.weight(.bold))
                Spacer()
                Text("\(items.count) 個地點")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(accent.opacity(0.10)).clipShape(Capsule())
                    .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.75))
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)

            ForEach(Array(items.enumerated()), id: \.element.id) { idx, spot in
                Button {
                    showListSheet = false
                    selectedSpot = spot
                } label: {
                    spotRow(spot)
                }
                .buttonStyle(.plain)
                if idx < items.count - 1 { Divider().padding(.leading, 60) }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    private func spotRow(_ spot: TravelSpotAggregate) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.08)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Circle().stroke(accent.opacity(0.22), lineWidth: 0.75).frame(width: 44, height: 44)
                Image(systemName: "figure.walk").font(.system(size: 17, weight: .semibold)).foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(spot.name.isEmpty ? "未命名地點" : spot.name)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                HStack(spacing: 6) {
                    Text("造訪 \(spot.visitCount) 次")
                        .font(.caption2.weight(.semibold)).foregroundStyle(accent)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(accent.opacity(0.10)).clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                    if !spot.photoNames.isEmpty {
                        Label("\(spot.photoNames.count)", systemImage: "photo")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("NT$ \(fmtShort(spot.totalSpent))")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                if let last = spot.lastVisit {
                    Text(fmtRelative(last)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    // MARK: - 統計英雄卡（娛樂紫漸層）

    private func statsCard(_ spots: [TravelSpotAggregate]) -> some View {
        let total = spots.reduce(0) { $0 + $1.totalSpent }
        let visits = spots.reduce(0) { $0 + $1.visitCount }
        let cityCount = Set(spots.map(\.city).filter { !$0.isEmpty }).count
        let mostVisited = spots.max(by: { $0.visitCount < $1.visitCount })

        return VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("旅遊足跡紀錄").font(.caption).foregroundStyle(.white.opacity(0.80))
                    Text("NT$ \(fmtShort(total))")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
                }
                Spacer()
                Text("\(spots.count) 個地點")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(.white.opacity(0.22)).clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 0.75))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 0) {
                kpiCell(label: "造訪總次", value: "\(visits) 次")
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 28)
                kpiCell(label: "足跡縣市", value: "\(cityCount) 個")
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 28)
                kpiCell(label: "最常去", value: mostVisited?.name ?? "—")
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 12)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(
            ZStack {
                LinearGradient(colors: [Color(red: 0.62, green: 0.36, blue: 1.0),
                                        Color(red: 0.42, green: 0.16, blue: 0.82)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.12)).frame(width: 120, height: 120)
                    .offset(x: 80, y: -40).blur(radius: 12)
                Circle().fill(.white.opacity(0.06)).frame(width: 66, height: 66)
                    .offset(x: -55, y: 40).blur(radius: 8)
                LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
                    .allowsHitTesting(false)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.42, green: 0.16, blue: 0.82).opacity(0.38), radius: 14, x: 0, y: 7)
        .padding(.horizontal)
    }

    private func kpiCell(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 4)
    }

    private func chip(_ text: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(isSelected ? AnyShapeStyle(accent) : AnyShapeStyle(.ultraThinMaterial))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.primary.opacity(isSelected ? 0 : 0.08), lineWidth: 0.6))
                .scaleEffect(isSelected ? 1.04 : 1.0)
                .shadow(color: .black.opacity(isSelected ? 0.14 : 0), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 地圖初始置中

    private func tryInitialCenter(_ spots: [TravelSpotAggregate]) {
        guard !hasCenteredInitially else { return }
        if let loc = locationProvider.lastLocation {
            cameraPosition = .region(MKCoordinateRegion(
                center: loc.coordinate, latitudinalMeters: 10000, longitudinalMeters: 10000))
            hasCenteredInitially = true
            return
        }
        guard !spots.isEmpty else { return }
        let lats = spots.map(\.coordinate.latitude)
        let lons = spots.map(\.coordinate.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.01, (maxLon - minLon) * 1.4))
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        hasCenteredInitially = true
    }

    // MARK: - 資料聚合

    private var entertainmentExpensesWithLocation: [Expense] {
        expenseStore.expenses.filter { exp in
            exp.expenseType == .variable
            && exp.variableCategory == .entertainment
            && exp.placeLatitude != nil
            && exp.placeLongitude != nil
            && range.contains(exp.date)
        }
    }

    private var aggregates: [TravelSpotAggregate] {
        let groups = Dictionary(grouping: entertainmentExpensesWithLocation) { exp in
            "\(exp.title)|\(exp.placeAddress ?? "")"
        }
        var all: [TravelSpotAggregate] = groups.compactMap { key, exps in
            guard let first = exps.first,
                  let lat = first.placeLatitude,
                  let lon = first.placeLongitude else { return nil }
            return TravelSpotAggregate(
                id: key,
                name: first.title,
                address: first.placeAddress ?? "",
                city: TravelCityParser.parse(first.placeAddress),
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                visits: exps)
        }
        if photoOnly { all = all.filter { !$0.photoNames.isEmpty } }
        if let city = selectedCity { all = all.filter { $0.city == city } }
        return all
    }

    private func sortedSpots(_ base: [TravelSpotAggregate]) -> [TravelSpotAggregate] {
        switch sort {
        case .visits: return base.sorted { $0.visitCount > $1.visitCount }
        case .spent:  return base.sorted { $0.totalSpent > $1.totalSpent }
        case .recent: return base.sorted { ($0.lastVisit ?? .distantPast) > ($1.lastVisit ?? .distantPast) }
        }
    }

    /// 依縣市分組（未知縣市歸「其他」），組內套用目前排序，組別依地點數多寡排列。
    private func spotsByCity(_ spots: [TravelSpotAggregate]) -> [(city: String, items: [TravelSpotAggregate])] {
        Dictionary(grouping: spots) { $0.city.isEmpty ? "其他" : $0.city }
            .map { (city: $0.key, items: sortedSpots($0.value)) }
            .sorted { a, b in
                if a.items.count != b.items.count { return a.items.count > b.items.count }
                return a.city < b.city
            }
    }

    private var cityOptions: [String] {
        var set = Set<String>()
        for exp in entertainmentExpensesWithLocation {
            let c = TravelCityParser.parse(exp.placeAddress)
            if !c.isEmpty { set.insert(c) }
        }
        return set.sorted()
    }

    // MARK: - 地圖 pin 樣式

    private func pinSize(_ count: Int, maxCount: Int) -> CGFloat {
        let ratio = Double(count) / Double(max(1, maxCount))
        return CGFloat(22 + ratio * 22)
    }

    private func pinColor(_ count: Int) -> Color {
        if count >= 10 { return Color(red: 0.42, green: 0.16, blue: 0.82) }
        if count >= 5 { return accent }
        if count >= 2 { return Color(red: 0.80, green: 0.62, blue: 1.0) }
        return .blue
    }

    // MARK: - 格式化

    private static let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    private func fmtShort(_ v: Double) -> String {
        if abs(v) >= 10_000 {
            let s = Self.decimalFormatter.string(from: NSNumber(value: v / 10_000)) ?? "0"
            return "\(s)萬"
        }
        return Self.decimalFormatter.string(from: NSNumber(value: v)) ?? "0"
    }

    private func fmtRelative(_ date: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: Date())).day ?? 0
        if days == 0 { return "今天" }
        if days == 1 { return "昨天" }
        if days < 7 { return "\(days) 天前" }
        if days < 30 { return "\(days / 7) 週前" }
        return Self.dateFormatter.string(from: date)
    }
}

// MARK: - 地點詳細 Sheet

struct TravelSpotDetailSheet: View {
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    let spot: TravelSpotAggregate
    private let accent = Color(red: 0.68, green: 0.40, blue: 1.00)

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var viewingPhotoURL: IdentifiableURL?

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "yyyy/M/d (E)"; return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Map(position: $cameraPosition) {
                        Marker(spot.name, coordinate: spot.coordinate).tint(.purple)
                    }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    headerCard
                    if !spot.photoNames.isEmpty { photoGallerySection }
                    if let companion = spot.topCompanion { companionCard(companion) }
                    visitsSection
                }
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(spot.name.isEmpty ? "地點" : spot.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
            }
            .onAppear {
                cameraPosition = .region(MKCoordinateRegion(
                    center: spot.coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200))
            }
            .sheet(item: $viewingPhotoURL) { wrapper in PhotoLightbox(url: wrapper.url) }
        }
    }

    private var headerCard: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(spot.name.isEmpty ? "未命名地點" : spot.name)
                    .font(.title3.bold()).foregroundStyle(.white).lineLimit(2)
                if !spot.address.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin").font(.caption2)
                        Text(spot.address).font(.caption).lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                detailKpi(icon: "figure.walk", label: "造訪", value: "\(spot.visitCount) 次")
                detailKpi(icon: "dollarsign.circle", label: "累計", value: "NT$ \(fmtShort(spot.totalSpent))")
                detailKpi(icon: "chart.bar", label: "平均", value: "NT$ \(fmtShort(spot.averageSpent))")
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(
            LinearGradient(colors: [Color(red: 0.62, green: 0.36, blue: 1.0),
                                    Color(red: 0.42, green: 0.16, blue: 0.82)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.42, green: 0.16, blue: 0.82).opacity(0.35), radius: 14, x: 0, y: 7)
        .padding(.horizontal)
    }

    private func detailKpi(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(.white.opacity(0.85))
            Text(value).font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity)
    }

    private func companionCard(_ name: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(.white.opacity(0.22)).frame(width: 36, height: 36)
                Image(systemName: "person.2.fill").font(.system(size: 15)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("最常同行").font(.caption2).foregroundStyle(.white.opacity(0.8))
                Text(name).font(.subheadline.weight(.bold)).foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(
            LinearGradient(colors: [.pink.opacity(0.9), .pink.opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var photoGallerySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("照片", icon: "photo.stack", trailing: "\(spot.photoNames.count) 張")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(spot.photoNames, id: \.self) { name in
                        let url = Expense.photoURL(for: name)
                        Button { viewingPhotoURL = IdentifiableURL(url: url) } label: {
                            photoThumb(url: url, width: 110, height: 90)
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
    }

    private var visitsSection: some View {
        let sorted = spot.visits.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("造訪紀錄", icon: "clock.arrow.circlepath", trailing: "\(sorted.count) 筆")
            VStack(spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, exp in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.08)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 34, height: 34)
                            Image(systemName: "calendar").font(.system(size: 13)).foregroundStyle(accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.dateFmt.string(from: exp.date)).font(.subheadline.weight(.medium))
                            if let m = exp.diningMember, !m.isEmpty {
                                Text(m).font(.caption2).foregroundStyle(.pink)
                            }
                        }
                        Spacer()
                        Text("NT$ \(fmtShort(exp.amount))")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    if idx < sorted.count - 1 { Divider().padding(.leading, 58) }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func sectionHeader(_ title: String, icon: String, trailing: String) -> some View {
        HStack(spacing: 10) {
            Capsule().fill(LinearGradient(colors: [accent, accent.opacity(0.55)],
                                          startPoint: .top, endPoint: .bottom)).frame(width: 4, height: 18)
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(accent)
            Text(title).font(.subheadline.weight(.bold))
            Spacer()
            Text(trailing)
                .font(.caption2.weight(.semibold)).foregroundStyle(accent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(accent.opacity(0.10)).clipShape(Capsule())
                .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.75))
        }
        .padding(.horizontal)
    }

    private static let shortDecimal: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()
    private func fmtShort(_ v: Double) -> String {
        if abs(v) >= 10_000 {
            let s = Self.shortDecimal.string(from: NSNumber(value: v / 10_000)) ?? "0"
            return "\(s)萬"
        }
        return Self.shortDecimal.string(from: NSNumber(value: v)) ?? "0"
    }
}

// MARK: - 旅遊相簿 Sheet（彙整所有地點照片）

struct TravelAlbumSheet: View {
    @Environment(\.dismiss) private var dismiss
    let spots: [TravelSpotAggregate]

    @State private var viewingPhotoURL: IdentifiableURL?

    /// (地點名稱, 照片檔名) 依地點展開
    private var entries: [(spot: String, name: String)] {
        spots.flatMap { spot in spot.photoNames.map { (spot: spot.name, name: $0) } }
    }

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView("還沒有旅遊照片", systemImage: "photo.on.rectangle.angled",
                                           description: Text("在娛樂支出附上照片，就會集結成相簿。"))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                                let url = Expense.photoURL(for: entry.name)
                                Button { viewingPhotoURL = IdentifiableURL(url: url) } label: {
                                    photoThumb(url: url, width: 104, height: 104)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("旅遊相簿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
            }
            .sheet(item: $viewingPhotoURL) { wrapper in PhotoLightbox(url: wrapper.url) }
        }
    }
}

// MARK: - 共用縮圖

private func photoThumb(url: URL, width: CGFloat, height: CGFloat) -> some View {
    Group {
        if let img = UIImage(contentsOfFile: url.path) {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: width, height: height).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemFill))
                .frame(width: width, height: height)
                .overlay(Image(systemName: "icloud.and.arrow.down").foregroundStyle(.tertiary))
        }
    }
}
