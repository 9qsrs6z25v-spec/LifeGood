import SwiftUI
import MapKit

struct LifeRealEstateView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var viewingItem: RealEstate?
    @State private var selectedCity: String?
    @State private var cameraPosition: MapCameraPosition = .region(Self.taiwanRegion)
    @State private var showPremiumAlert = false

    private static let taiwanRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 23.75, longitude: 121.0),
        span: MKCoordinateSpan(latitudeDelta: 4.5, longitudeDelta: 5.5)
    )

    // MARK: - 台灣縣市座標（縣市政府中心點）
    static let cityCoords: [String: CLLocationCoordinate2D] = [
        "臺北市": .init(latitude: 25.0330, longitude: 121.5654),
        "新北市": .init(latitude: 25.0120, longitude: 121.4657),
        "桃園市": .init(latitude: 24.9936, longitude: 121.3010),
        "臺中市": .init(latitude: 24.1477, longitude: 120.6736),
        "臺南市": .init(latitude: 22.9997, longitude: 120.2270),
        "高雄市": .init(latitude: 22.6273, longitude: 120.3014),
        "基隆市": .init(latitude: 25.1276, longitude: 121.7392),
        "新竹市": .init(latitude: 24.8138, longitude: 120.9675),
        "嘉義市": .init(latitude: 23.4801, longitude: 120.4491),
        "新竹縣": .init(latitude: 24.8387, longitude: 121.0177),
        "苗栗縣": .init(latitude: 24.5602, longitude: 120.8214),
        "彰化縣": .init(latitude: 24.0518, longitude: 120.5161),
        "南投縣": .init(latitude: 23.9157, longitude: 120.6869),
        "雲林縣": .init(latitude: 23.7092, longitude: 120.4313),
        "嘉義縣": .init(latitude: 23.4518, longitude: 120.2555),
        "屏東縣": .init(latitude: 22.5519, longitude: 120.5487),
        "宜蘭縣": .init(latitude: 24.7021, longitude: 121.7378),
        "花蓮縣": .init(latitude: 23.9872, longitude: 121.6015),
        "臺東縣": .init(latitude: 22.7583, longitude: 121.1444),
        "澎湖縣": .init(latitude: 23.5712, longitude: 119.5793),
        "金門縣": .init(latitude: 24.4370, longitude: 118.3172),
        "連江縣": .init(latitude: 26.1605, longitude: 119.9515)
    ]

    private var ownedCount: Int {
        financeStore.realEstates.filter { $0.soldDate == nil }.count
    }
    private var soldCount: Int {
        financeStore.realEstates.filter { $0.soldDate != nil }.count
    }

    /// 依縣市分組（僅包含有設定縣市的物件）
    private var propertiesByCity: [(city: String, items: [RealEstate])] {
        Dictionary(grouping: financeStore.realEstates.filter { !$0.city.isEmpty }, by: \.city)
            .map { (city: $0.key, items: $0.value) }
    }

    /// 當前選取縣市的物件
    private var selectedCityItems: [RealEstate] {
        guard let city = selectedCity else { return [] }
        return financeStore.realEstates.filter { $0.city == city }
    }

    /// 無設定縣市的物件
    private var unclassifiedItems: [RealEstate] {
        financeStore.realEstates.filter { $0.city.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader

                if financeStore.realEstates.isEmpty {
                    emptyState
                } else {
                    mapView
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("房地產")
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
            .sheet(isPresented: $showAdd) { AddRealEstateView() }
            .sheet(item: $viewingItem) { item in RealEstateDetailView(estate: item) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    // MARK: - 摘要

    private var summaryHeader: some View {
        HStack(spacing: 0) {
            statBlock(icon: "building.2.fill", label: "購入", value: "\(financeStore.realEstates.count)", color: .purple)
            Divider().frame(height: 40)
            statBlock(icon: "house.fill", label: "持有中", value: "\(ownedCount)", color: .green)
            Divider().frame(height: 40)
            statBlock(icon: "checkmark.seal.fill", label: "已售出", value: "\(soldCount)", color: .red)
        }
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
    }

    private func statBlock(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value).font(.title2.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "building.2").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("尚無房地產").font(.headline).foregroundStyle(.secondary)
            Text("點擊右上角 + 新增物件").font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    // MARK: - 地圖

    private var mapView: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition) {
                ForEach(propertiesByCity, id: \.city) { entry in
                    if let coord = Self.cityCoords[entry.city] {
                        Annotation(entry.city, coordinate: coord, anchor: .bottom) {
                            pinView(city: entry.city, count: entry.items.count)
                                .onTapGesture { togglePin(entry.city) }
                        }
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    selectedCity = nil
                }
                resetCamera()
            }

            // 底部浮動列表
            if let city = selectedCity {
                cityPanel(city: city, items: selectedCityItems)
                    .padding(.horizontal, 12)
                    .padding(.bottom, unclassifiedItems.isEmpty ? 12 : 64)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
            }

            // 未分類縣市的物件（底部 chip）
            if !unclassifiedItems.isEmpty {
                unclassifiedChip
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: - 大頭針

    private func pinView(city: String, count: Int) -> some View {
        let isSelected = selectedCity == city
        return VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.purple, .pink],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)
                    .shadow(color: .purple.opacity(0.4), radius: isSelected ? 8 : 4, y: 2)
                    .overlay(Circle().stroke(.white, lineWidth: 2))

                VStack(spacing: -2) {
                    Image(systemName: "building.2.fill")
                        .font(.caption2).foregroundStyle(.white)
                    Text("\(count)")
                        .font(.caption2.bold()).foregroundStyle(.white)
                }
            }
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 12))
                .foregroundStyle(.purple)
                .offset(y: -4)
        }
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    private func togglePin(_ city: String) {
        let isDeselecting = selectedCity == city
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedCity = isDeselecting ? nil : city
        }
        if isDeselecting {
            resetCamera()
        } else if let coord = Self.cityCoords[city] {
            // 往南偏移使大頭針顯示在地圖上半部，避免被底部面板遮住
            let span = MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
            let offsetCenter = CLLocationCoordinate2D(
                latitude: coord.latitude - span.latitudeDelta * 0.28,
                longitude: coord.longitude
            )
            withAnimation(.easeInOut(duration: 0.6)) {
                cameraPosition = .region(MKCoordinateRegion(center: offsetCenter, span: span))
            }
        }
    }

    private func resetCamera() {
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .region(Self.taiwanRegion)
        }
    }

    // MARK: - 縣市物件面板

    private func cityPanel(city: String, items: [RealEstate]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title3).foregroundStyle(.purple)
                Text(city).font(.headline)
                Text("\(items.count) 筆").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedCity = nil
                    }
                    resetCamera()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        Button {
                            viewingItem = item
                        } label: {
                            itemRow(item)
                        }
                        .buttonStyle(.plain)
                        if idx < items.count - 1 { Divider().padding(.leading, 56) }
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }

    private func itemRow(_ item: RealEstate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.soldDate != nil ? "building.2" : "building.2.fill")
                .font(.title3)
                .foregroundStyle(item.soldDate != nil ? .red : .purple)
                .frame(width: 40, height: 40)
                .background((item.soldDate != nil ? Color.red : Color.purple).opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if !item.address.isEmpty {
                    Text(item.address)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 10) {
                    Label(formatDate(item.purchaseDate), systemImage: "calendar")
                        .font(.caption2).foregroundStyle(.green)
                    if let sd = item.soldDate {
                        Label(formatDate(sd), systemImage: "checkmark.seal")
                            .font(.caption2).foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - 未分類縣市 chip

    private var unclassifiedChip: some View {
        Menu {
            ForEach(unclassifiedItems) { item in
                Button {
                    viewingItem = item
                } label: {
                    Label(item.name, systemImage: "building.2")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
                Text("未設定縣市 \(unclassifiedItems.count) 筆").font(.caption.bold())
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.orange)
            .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
        }
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: d)
    }
}
