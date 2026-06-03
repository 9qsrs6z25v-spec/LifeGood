import SwiftUI
import MapKit

// MARK: - 美化紀錄（LifeRealEstateView）
// [2026-06] 本次美化方向：
//   1. summaryHeader → 升級為紫色漸層英雄卡片：總物件數大字 + 散景裝飾圓，
//      底部三欄 KPI（購入 / 持有中 / 已售出）各帶彩色漸層圖示圓，
//      加入 headerAppeared spring 進場動畫，對齊 FinanceOverviewView totalAssetsCard 規格。
//   2. emptyState → 升級為雙層脈衝光環 + 紫色漸層底圓 + 說明文字 + 紫色 CTA 按鈕，
//      對齊 VariableExpenseView.emptyStateView 空狀態設計規格。
//   3. cityPanel 標題列 → Capsule 側條 + subheadline.bold + 物件數膠囊徽章，
//      對齊 milestoneTimelineSection 標題規格；底部關閉按鈕改為圓角膠囊。
//   4. itemRow → 圖示從 40pt 純色升至 44pt LinearGradient 漸層圓 + 陰影，
//      日期改為彩色膠囊徽章，對齊 ExpenseRow / incomeRow 視覺規格。
//   5. 加入 navigationBarTitleDisplayMode(.large)，與其他主列表頁對齊。

struct LifeRealEstateView: View {
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var viewingItem: RealEstate?
    @State private var selectedCity: String?
    @State private var cameraPosition: MapCameraPosition = .region(Self.taiwanRegion)
    @State private var showPremiumAlert = false
    @State private var headerAppeared = false
    @State private var emptyIconPulse = false

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
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showAdd) { AddRealEstateView() }
            .sheet(item: $viewingItem) { item in RealEstateDetailView(estate: item) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    // MARK: - 摘要英雄卡片

    private var summaryHeader: some View {
        VStack(spacing: 0) {
            // 頂部：總物件數大字 + 計數膠囊
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("不動產概況")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                    Text("\(financeStore.realEstates.count)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("筆不動產紀錄")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.top, 1)
                }
                Spacer()
                // 右上角：增值狀態膠囊
                if ownedCount > 0 {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("持有中")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                        HStack(spacing: 3) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(ownedCount) 筆")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color(red: 0.60, green: 1.00, blue: 0.75))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.18))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 0.75))
                    }
                }
            }

            // 分隔線
            Rectangle()
                .fill(.white.opacity(0.20))
                .frame(height: 0.5)
                .padding(.vertical, 14)

            // 三欄 KPI：購入 / 持有中 / 已售出
            HStack(spacing: 0) {
                heroKpiCell(icon: "building.2.fill", label: "總購入",
                            value: "\(financeStore.realEstates.count)", color: Color(red: 0.72, green: 0.55, blue: 1.00))
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 36)
                heroKpiCell(icon: "house.fill", label: "持有中",
                            value: "\(ownedCount)", color: Color(red: 0.60, green: 1.00, blue: 0.75))
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 36)
                heroKpiCell(icon: "checkmark.seal.fill", label: "已售出",
                            value: "\(soldCount)", color: Color(red: 1.00, green: 0.78, blue: 0.75))
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.50, green: 0.30, blue: 0.90),
                        Color(red: 0.32, green: 0.14, blue: 0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 右上主散景圓
                Circle()
                    .fill(.white.opacity(0.13))
                    .frame(width: 140, height: 140)
                    .offset(x: 90, y: -55)
                    .blur(radius: 14)
                // 左下次散景圓
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 90, height: 90)
                    .offset(x: -70, y: 55)
                    .blur(radius: 10)
                // 右下微光
                Circle()
                    .fill(.white.opacity(0.05))
                    .frame(width: 55, height: 55)
                    .offset(x: 80, y: 40)
                    .blur(radius: 10)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.32, green: 0.14, blue: 0.72).opacity(0.45), radius: 18, x: 0, y: 9)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .opacity(headerAppeared ? 1 : 0)
        .offset(y: headerAppeared ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                headerAppeared = true
            }
        }
    }

    private func heroKpiCell(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.22))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    // MARK: - 空狀態

    private var emptyState: some View {
        let accent = Color(red: 0.50, green: 0.30, blue: 0.90)
        return VStack(spacing: 24) {
            Spacer()
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
                            colors: [accent.opacity(0.18), accent.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 86, height: 86)
                    .overlay(
                        Circle()
                            .stroke(accent.opacity(0.25), lineWidth: 1.2)
                    )
                Image(systemName: "building.2")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(accent.opacity(0.75))
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    emptyIconPulse = true
                }
            }

            VStack(spacing: 10) {
                Text("尚無房地產紀錄")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                Text("記錄你持有的每一筆不動產，\n追蹤增值與月租金現金流")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button {
                if subscription.isPremium { showAdd = true }
                else { showPremiumAlert = true }
            } label: {
                Label("新增第一筆房地產", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [accent, Color(red: 0.32, green: 0.14, blue: 0.72)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color(red: 0.32, green: 0.14, blue: 0.72).opacity(0.38), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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
            // 標題列：Capsule 側條 + 城市名稱 + 計數膠囊（對齊 milestoneTimelineSection 標題規格）
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .purple.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Image(systemName: "mappin.circle.fill")
                    .font(.subheadline).foregroundStyle(.purple)
                Text(city).font(.subheadline.weight(.bold))
                // 計數膠囊徽章
                Text("\(items.count) 筆")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.purple.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.purple.opacity(0.22), lineWidth: 0.75))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedCity = nil
                    }
                    resetCamera()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                        Text("收合")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Color(.secondarySystemBackground))

            Rectangle()
                .fill(Color(.separator).opacity(0.20))
                .frame(height: 0.5)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        Button {
                            viewingItem = item
                        } label: {
                            itemRow(item)
                        }
                        .buttonStyle(.plain)
                        if idx < items.count - 1 {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
    }

    private func itemRow(_ item: RealEstate) -> some View {
        let isSold = item.soldDate != nil
        let accent: Color = isSold ? .red : .purple
        return HStack(spacing: 12) {
            // 44pt LinearGradient 漸層圓 + 陰影（對齊 ExpenseRow 規格）
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
                Image(systemName: isSold ? "building.2" : "building.2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !item.address.isEmpty {
                    Text(item.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // 日期膠囊徽章（對齊 incomeRow 日期規格）
                HStack(spacing: 5) {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9))
                        Text(formatDate(item.purchaseDate))
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.green.opacity(0.10))
                    .clipShape(Capsule())

                    if let sd = item.soldDate {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 9))
                            Text(formatDate(sd))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.red.opacity(0.10))
                        .clipShape(Capsule())
                    }
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
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
