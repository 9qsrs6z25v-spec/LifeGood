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
// [2026-06 v2] 本次美化方向：
//   6. summaryHeader 頂部玻璃光澤：背景 ZStack 末層加入 LinearGradient [white.opacity(0.18), clear]
//      top→center 玻璃反光覆蓋層，對齊 OverviewView.monthlyBalanceCard v3 /
//      FinanceOverviewView.totalAssetsCard v3 英雄卡玻璃光澤規格。
//   7. heroKpiCell 圖示圓：純色 color.opacity(0.22) 30pt →
//      LinearGradient (0.24→0.09) 32pt + Circle stroke (color.opacity(0.18), 0.75pt)，
//      對齊 OverviewView.summaryCard v3 / FinanceOverviewView.assetCard 圖示圓規格；
//      value 文字加 minimumScaleFactor(0.72) 防止大數字截斷。
//   8. itemRow 左側 4pt 強調條：持有中→紫色漸層，已售出→紅色漸層，
//      對齊 RealEstateView.estateCard / StockView.stockCard 左側強調條規格。
//   9. itemRow 右側估值 + 增值率膠囊：補入 item.currentValue.ntdWanString 估值大字
//      (.system(size:15, weight:.bold, design:.rounded))，
//      增值率改為彩色 Capsule 膠囊（綠漲/紅跌 + 細邊框 0.5pt），
//      對齊 RealEstateView.estateCard 估值 + 增值率膠囊設計語言。
//  10. cityPanel 物件列交錯進場動畫：加入 cityPanelRowsAppeared 旗標 + 0.04s stagger，
//      對齊 IncomeView.incomeListSections / StockView.cardsAppeared 規格。
// [2026-06 v3] 本次美化方向：
//  11. summaryHeader 縣市分配彩條（miniCityBar）：KPI 橫列下方（≥2 個縣市時）新增縣市物件
//      數量佔比彩條 + 圖例點陣列（色點 + 縣市名稱）；5 種固定漸層色按筆數高低排列；
//      miniBarAppeared 左展開 spring 動畫（scaleEffect x 0.04→1.0，anchor:.leading）
//      + glow overlay（白頂光 + 黑底柔化），
//      對齊 VehicleView.summaryHeader v2 / FinanceOverviewView.totalAssetsCard v4 彩條規格。
//  12. summaryHeader shadow 升級雙層：主色光暈 opacity 0.45→0.52；
//      疊加 .shadow(color:.black.opacity(0.08), radius:8, y:4)，
//      對齊 SubordinateOverviewView v3 / SubordinateDetailView.headerCard 雙層 shadow 規格。
//  13. itemRow 日期膠囊補 stroke border：購入日期 green + 售出日期 red 膠囊各補
//      .overlay(Capsule().stroke(color.opacity(0.22), lineWidth:0.6))，
//      對齊 CareerView v2 / OverviewView.recentRow v3 日期膠囊細邊框規格。

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
    // [v2] cityPanel 物件列交錯進場動畫旗標
    @State private var cityPanelRowsAppeared = false
    // [v3] 縣市分配彩條左展開動畫旗標
    @State private var miniBarAppeared = false

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

            // [v3] 縣市分配彩條（≥2 個縣市時顯示）
            if propertiesByCity.count >= 2 {
                miniCityBar
                    .padding(.top, 10)
            }
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
                // [v2] 頂部玻璃反光覆蓋層（對齊 OverviewView.monthlyBalanceCard v3 規格）
                LinearGradient(
                    colors: [.white.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .allowsHitTesting(false)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        // [v3] 雙層 shadow：主色光暈 + 黑底基礎陰影（對齊 SubordinateOverviewView v3 規格）
        .shadow(color: Color(red: 0.32, green: 0.14, blue: 0.72).opacity(0.52), radius: 18, x: 0, y: 9)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
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

    // [v2] heroKpiCell：圖示圓升級為 32pt LinearGradient + stroke border，對齊 OverviewView.summaryCard v3
    private func heroKpiCell(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.24), color.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(color.opacity(0.18), lineWidth: 0.75))
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    // MARK: - [v3] 縣市分配彩條
    // 各縣市按物件筆數高低由左到右排列，最多顯示 5 個縣市，其餘合併為「其他」
    private var miniCityBar: some View {
        let all = propertiesByCity.sorted { $0.items.count > $1.items.count }
        let top5 = Array(all.prefix(5))
        let rest = all.count > 5 ? all.dropFirst(5).reduce(0) { $0 + $1.items.count } : 0
        let total = Double(top5.reduce(0) { $0 + $1.items.count } + rest)
        let pal: [Color] = [
            Color(red: 0.72, green: 0.55, blue: 1.00), // 紫
            Color(red: 0.60, green: 1.00, blue: 0.75), // 翠綠
            Color(red: 1.00, green: 0.78, blue: 0.75), // 珊瑚粉
            Color(red: 0.55, green: 0.85, blue: 1.00), // 天藍
            Color(red: 1.00, green: 0.88, blue: 0.55), // 暖黃
        ]
        return VStack(spacing: 6) {
            // 比例彩條
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(top5.indices, id: \.self) { idx in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(pal[idx % pal.count])
                            .frame(
                                width: max(4, geo.size.width * CGFloat(top5[idx].items.count) / CGFloat(max(1, total))),
                                height: 6
                            )
                    }
                    if rest > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.25))
                            .frame(
                                width: max(4, geo.size.width * CGFloat(rest) / CGFloat(max(1, total))),
                                height: 6
                            )
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 6)
            // 左展開 spring 動畫（對齊 VehicleView.summaryHeader v2 彩條規格）
            .scaleEffect(x: miniBarAppeared ? 1.0 : 0.04, anchor: .leading)
            // Glow overlay：頂部白光 + 底部柔化
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(0.35), .clear, .black.opacity(0.08)],
                    startPoint: .top, endPoint: .bottom
                )
                .allowsHitTesting(false)
            )
            // 圖例點陣列
            HStack(spacing: 8) {
                ForEach(top5.indices, id: \.self) { idx in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(pal[idx % pal.count])
                            .frame(width: 5, height: 5)
                        Text(top5[idx].city)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                if rest > 0 {
                    HStack(spacing: 3) {
                        Circle().fill(Color.white.opacity(0.30)).frame(width: 5, height: 5)
                        Text("其他")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.58, dampingFraction: 0.78).delay(0.20)) {
                miniBarAppeared = true
            }
        }
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

            // [v2] 物件列進場動畫：每次縣市 panel 開啟時重置並重播
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        Button {
                            viewingItem = item
                        } label: {
                            itemRow(item)
                        }
                        .buttonStyle(.plain)
                        .opacity(cityPanelRowsAppeared ? 1 : 0)
                        .offset(y: cityPanelRowsAppeared ? 0 : 12)
                        .animation(
                            .spring(response: 0.44, dampingFraction: 0.80)
                                .delay(0.04 * Double(idx)),
                            value: cityPanelRowsAppeared
                        )
                        if idx < items.count - 1 {
                            Divider().padding(.leading, 74)
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
            .onAppear {
                cityPanelRowsAppeared = false
                withAnimation(.spring(response: 0.44, dampingFraction: 0.80).delay(0.08)) {
                    cityPanelRowsAppeared = true
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
    }

    // [v2] itemRow：加入左側 4pt 強調條 + 右側估值大字 + 增值率彩色膠囊
    private func itemRow(_ item: RealEstate) -> some View {
        let isSold = item.soldDate != nil
        let accent: Color = isSold ? .red : .purple
        let rate = item.appreciationRate
        let rateColor: Color = rate >= 0 ? .green : .red
        let rateIcon = rate >= 0 ? "arrow.up.right" : "arrow.down.right"

        return HStack(spacing: 0) {
            // [v2] 左側 4pt 漸層強調條（對齊 RealEstateView.estateCard / StockView.stockCard 規格）
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.trailing, 10)

            // 44pt LinearGradient 漸層圓 + stroke + 陰影（對齊 ExpenseRow 規格）
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
                    .overlay(Circle().stroke(accent.opacity(0.18), lineWidth: 0.75))
                Image(systemName: isSold ? "building.2" : "building.2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .padding(.trailing, 12)

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
                    // [v3] 補 stroke border，對齊全 App 日期膠囊細邊框規格
                    .overlay(Capsule().stroke(Color.green.opacity(0.22), lineWidth: 0.6))

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
                        // [v3] 補 stroke border，對齊全 App 日期膠囊細邊框規格
                        .overlay(Capsule().stroke(Color.red.opacity(0.22), lineWidth: 0.6))
                    }
                }
            }

            Spacer(minLength: 4)

            // [v2] 右側：估值大字 + 增值率彩色膠囊（對齊 RealEstateView.estateCard 設計語言）
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.currentValue.ntdWanString)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                if item.purchasePrice > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: rateIcon)
                            .font(.system(size: 8, weight: .bold))
                        Text(String(format: "%.1f%%", abs(rate)))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(rateColor)
                    .padding(.horizontal, 6).padding(.vertical, 2.5)
                    .background(rateColor.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(rateColor.opacity(0.22), lineWidth: 0.5))
                }
            }
            .padding(.trailing, 6)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 4)
        }
        .padding(.leading, 10).padding(.vertical, 10)
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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    private func formatDate(_ d: Date) -> String {
        Self.dateFormatter.string(from: d)
    }
}
