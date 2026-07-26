import SwiftUI
import MapKit
import UIKit

// MARK: - 旅遊地圖
// 資料來源：變動支出「娛樂」分類且已附經緯度的紀錄。
// 以「項目名稱|地址」聚合成去過的地點，撒點於地圖，並依台灣縣市分組呈現足跡。
// 沿用美食地圖（FoodMapView）驗證過的 MapKit / 照片顯示模式，主題色改為娛樂紫。

// MARK: - 美化紀錄（TravelMapView）2026-07
// [2026-07 v1] 首次美化方向（對齊已完成美化的 FoodMapView 娛樂紫姊妹頁規格，
// 拉齊兩頁視覺均值）：
//   1. 金額顯示改用共用 Double.ntdWanString（FinanceModels.swift），支援「萬 / 億」
//      量級自動切換（原本 TravelMapView 與 TravelSpotDetailSheet 各自維護一份只到
//      「萬」量級的 fmtShort/decimalFormatter，已移除重複程式碼），避免旅遊花費達億
//      量級時顯示過長。
//   2. statsCard／headerCard 英雄卡：補齊三顆散景裝飾圓 + 頂部玻璃光澤覆層
//      （LinearGradient [.white.opacity(0.18)→.clear] top→center），對齊
//      FoodMapView.statsCard／headerCard v3 三圓散景規格；加入 spring 進場動畫
//      （statsCardAppeared／cardAppeared），總花費大字補上 contentTransition(.numericText())。
//   3. spotRow：44pt 圖示圓補上陰影；新增「最近造訪」calendar 圖示膠囊徽章
//      （tertiarySystemFill），對齊 FoodMapView.restaurantRow 規格；金額改用主題紫
//      強調色 + contentTransition。
//   4. visitsSection 列行：34pt 圖示圓補齊 stroke 邊框；日期改為膠囊徽章樣式；
//      加入交錯淡入 + 向上進場動畫（visitsAppeared），對齊 StockDetailView
//      transactionsSection / FoodMapView.visitsSection stagger 規格。
//   5. companionCard 圖示圓補上漸層 + 陰影 + 邊框，姓名文字加入自適應縮放，避免長
//      姓名截斷。
//   6. 關閉按鈕維持 topBarLeading（左側），符合全 App 一致慣例。
//   7. 未變動任何地圖標註、資料聚合（aggregates／spotsByCity／cityOptions）、篩選
//      或排序等既有商業邏輯。
// [2026-07 v2] emptyOverlay／chip 補齊與 FoodMapView 姊妹頁仍缺的兩處均值差距：
//   8. emptyOverlay 原本只是單層 fill 圓配 0.94↔1.08 呼吸縮放，且「有照片」篩選導致
//      零筆時仍顯示「還沒有旅遊足跡／在娛樂支出記錄地點…」，會誤導使用者以為完全沒
//      記錄過，其實只是篩選條件太嚴。改為 photoOnly 感知：篩選中→灰階圖示 + 「目前
//      沒有附照片的地點／關閉右上角『有照片』開關可查看全部地點」提示且不做脈衝
//      （對齊 FoodMapView.emptyOverlay isPhotoFilter 分支）；真正尚無足跡→升級為
//      雙層脈衝光環 + 漸層底圓 + 細邊框，並改用可取消的 Task 排程（onAppear 先取消
//      前一個再排新的、onDisappear 一併取消歸零），對齊 FoodMapView／LifeOverviewView
//      既有雙層光環空狀態規格。背景改用 .ultraThinMaterial 圓角卡片，取代原本貼在地
//      圖上的不透明 systemGroupedBackground 色塊，深色模式下更自然融入地圖底色。
//   9. chip()：scaleEffect(isSelected ? 1.04 : 1.0) 缺少對應 .animation(value:)，切換
//      期間／縣市篩選時膠囊是瞬間跳變而非彈簧回彈，與姊妹頁 FoodMapView.chip 的
//      .spring(response:0.26, dampingFraction:0.72) 規格不一致；補上同款動畫修飾。
//   純視覺與空狀態文案調整，地圖標註、資料聚合、篩選或排序等既有商業邏輯完全未變動。
// [2026-07 v3] TravelAlbumSheet 空狀態補齊最後一處均值差距：
//   10. 原本用系統原生 ContentUnavailableView（純圖示 + 文字，無動畫），與本檔案
//       emptyOverlay 已升級的雙層脈衝光環規格不一致。改為 albumEmptyState：同款雙層
//       脈衝光環 + 漸層底圓 + 細邊框 + .ultraThinMaterial 圓角卡片，並用可取消的
//       Task 排程管理脈衝（onAppear 排程、onDisappear 取消歸零，避免 sheet 反覆開關
//       時重疊多個計時任務）。純視覺調整，相簿照片彙整（entries／photoNames 展開）
//       邏輯完全未變動。
//   純視覺與空狀態文案調整，地圖標註、資料聚合、篩選或排序等既有商業邏輯完全未變動。
//   （下次美化本檔案時，可從 listSheet／citySection 卡片（清單 sheet 內的縣市分組卡片
//   目前僅套用系統 List 樣式，未比對是否需要圓角卡片化）繼續找可統一之處）

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
    @State private var emptyIconPulseTask: Task<Void, Never>?
    @State private var statsCardAppeared = false

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

    // MARK: - 空狀態（雙層脈衝光環 + 漸層底圓，photoOnly 篩選中另用灰階提示不做脈衝）

    private var emptyOverlay: some View {
        let isPhotoFilter = photoOnly
        return VStack(spacing: 14) {
            ZStack {
                if !isPhotoFilter {
                    // 外層脈衝光環
                    Circle()
                        .stroke(accent.opacity(emptyIconPulse ? 0 : 0.25), lineWidth: 1.5)
                        .frame(width: 100, height: 100)
                        .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                        .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false), value: emptyIconPulse)
                    // 內層脈衝光環（延遲 0.3s 製造波紋層次）
                    Circle()
                        .stroke(accent.opacity(emptyIconPulse ? 0 : 0.13), lineWidth: 1)
                        .frame(width: 100, height: 100)
                        .scaleEffect(emptyIconPulse ? 1.60 : 1.0)
                        .animation(.easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false), value: emptyIconPulse)
                }
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isPhotoFilter
                                ? [Color(.systemFill), Color(.secondarySystemFill)]
                                : [accent.opacity(0.85), accent.opacity(0.50)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .overlay(Circle().stroke(.white.opacity(isPhotoFilter ? 0 : 0.30), lineWidth: 0.75))
                Image(systemName: isPhotoFilter ? "photo" : "airplane.departure")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isPhotoFilter ? Color.secondary : Color.white)
            }
            .onAppear {
                emptyIconPulseTask?.cancel()
                emptyIconPulse = false
                guard !isPhotoFilter else { return }
                emptyIconPulseTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    emptyIconPulse = true
                }
            }
            // [除錯] photoOnly 切換不會改變外層 ZStack 的身分，單靠 onAppear/onDisappear
            // 不會在篩選切換時重觸發；空清單時來回切一次「有照片」篩選會讓脈衝動畫永久
            // 停止（對齊 FoodMapView.emptyOverlay 的既有修法，改用 onChange 明確驅動）。
            .onChange(of: photoOnly) { _, filtering in
                emptyIconPulseTask?.cancel()
                emptyIconPulse = false
                if !filtering {
                    emptyIconPulseTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        emptyIconPulse = true
                    }
                }
            }
            .onDisappear {
                emptyIconPulseTask?.cancel()
                emptyIconPulse = false
            }

            Text(isPhotoFilter ? "目前沒有附照片的地點" : "還沒有旅遊足跡")
                .font(.headline)
            Text(isPhotoFilter
                 ? "關閉右上角「有照片」開關可查看全部地點"
                 : "在「娛樂」變動支出記錄時選擇地點（並可附照片），\n這裡就會標出你去過的地方。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 4)
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    // 等 sheet 關閉再開另一張詳細 sheet，避免同一 run loop 內兩個 sheet
                    // 的關閉／開啟互相搶跑，對齊 FoodMapView 同型修復。
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        selectedSpot = spot
                    }
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
                    .shadow(color: accent.opacity(0.22), radius: 6, x: 0, y: 3)
                Circle().stroke(accent.opacity(0.22), lineWidth: 0.75).frame(width: 44, height: 44)
                Image(systemName: "figure.walk").font(.system(size: 17, weight: .semibold)).foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(spot.name.isEmpty ? "未命名地點" : spot.name)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                HStack(spacing: 5) {
                    Text("造訪 \(spot.visitCount) 次")
                        .font(.caption2.weight(.semibold)).foregroundStyle(accent)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(accent.opacity(0.10)).clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                    if let last = spot.lastVisit {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar").font(.system(size: 8, weight: .medium))
                            Text(fmtRelative(last)).font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill)).clipShape(Capsule())
                    }
                    if !spot.photoNames.isEmpty {
                        Label("\(spot.photoNames.count)", systemImage: "photo")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(spot.totalSpent.ntdWanString)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.42, green: 0.16, blue: 0.82))
                    .contentTransition(.numericText())
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
                    Text(total.ntdWanString)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
                        .contentTransition(.numericText())
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
                // 三顆散景裝飾圓（對齊 FoodMapView.statsCard v3 規格）
                Circle().fill(.white.opacity(0.12)).frame(width: 120, height: 120)
                    .offset(x: 80, y: -40).blur(radius: 12)
                Circle().fill(.white.opacity(0.07)).frame(width: 70, height: 70)
                    .offset(x: -55, y: 42).blur(radius: 8)
                Circle().fill(.white.opacity(0.05)).frame(width: 55, height: 55)
                    .offset(x: 50, y: 30).blur(radius: 6)
                LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
                    .allowsHitTesting(false)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.42, green: 0.16, blue: 0.82).opacity(0.38), radius: 14, x: 0, y: 7)
        .padding(.horizontal)
        .opacity(statsCardAppeared ? 1 : 0)
        .offset(y: statsCardAppeared ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                statsCardAppeared = true
            }
        }
        .onDisappear { statsCardAppeared = false }
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
        // 補上選中彈簧動畫，對齊 FoodMapView.chip 規格，避免膠囊縮放瞬間跳變
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isSelected)
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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

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
    @State private var cardAppeared = false
    @State private var visitsAppeared = false

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
                    .font(.title3.bold()).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.7)
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
                detailKpi(icon: "dollarsign.circle", label: "累計", value: spot.totalSpent.ntdWanString)
                detailKpi(icon: "chart.bar", label: "平均", value: spot.averageSpent.ntdWanString)
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(
            ZStack {
                LinearGradient(colors: [Color(red: 0.62, green: 0.36, blue: 1.0),
                                        Color(red: 0.42, green: 0.16, blue: 0.82)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // 三顆散景裝飾圓 + 頂部玻璃光澤（對齊 FoodMapView.headerCard v3 規格）
                Circle().fill(.white.opacity(0.12)).frame(width: 110, height: 110)
                    .offset(x: 70, y: -35).blur(radius: 12)
                Circle().fill(.white.opacity(0.07)).frame(width: 65, height: 65)
                    .offset(x: -50, y: 35).blur(radius: 8)
                Circle().fill(.white.opacity(0.04)).frame(width: 50, height: 50)
                    .offset(x: 40, y: 28).blur(radius: 6)
                LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
                    .allowsHitTesting(false)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.42, green: 0.16, blue: 0.82).opacity(0.35), radius: 14, x: 0, y: 7)
        .padding(.horizontal)
        .opacity(cardAppeared ? 1 : 0)
        .offset(y: cardAppeared ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                cardAppeared = true
            }
        }
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
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.14)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
                Circle().stroke(.white.opacity(0.25), lineWidth: 0.75).frame(width: 36, height: 36)
                Image(systemName: "person.2.fill").font(.system(size: 15)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("最常同行").font(.caption2).foregroundStyle(.white.opacity(0.8))
                Text(name).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
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
                                .fill(LinearGradient(colors: [accent.opacity(0.18), accent.opacity(0.07)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(accent.opacity(0.18), lineWidth: 0.75))
                            Image(systemName: "calendar").font(.system(size: 13, weight: .medium)).foregroundStyle(accent.opacity(0.85))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Self.dateFmt.string(from: exp.date))
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(accent.opacity(0.10)).clipShape(Capsule())
                                .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                            if let m = exp.diningMember, !m.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "person.2.fill").font(.system(size: 9))
                                    Text(m).font(.system(size: 10, weight: .medium))
                                }
                                .foregroundStyle(.pink)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.pink.opacity(0.10)).clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.pink.opacity(0.22), lineWidth: 0.6))
                            }
                        }
                        Spacer(minLength: 4)
                        Text(exp.amount.ntdWanString)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .opacity(visitsAppeared ? 1 : 0)
                    .offset(y: visitsAppeared ? 0 : 10)
                    .animation(
                        .spring(response: 0.44, dampingFraction: 0.82).delay(0.05 * Double(min(idx, 10))),
                        value: visitsAppeared
                    )
                    if idx < sorted.count - 1 { Divider().padding(.leading, 58) }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .onAppear {
            withAnimation(.spring(response: 0.50, dampingFraction: 0.82).delay(0.08)) {
                visitsAppeared = true
            }
        }
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
}

// MARK: - 旅遊相簿 Sheet（彙整所有地點照片）

struct TravelAlbumSheet: View {
    @Environment(\.dismiss) private var dismiss
    let spots: [TravelSpotAggregate]

    @State private var viewingPhotoURL: IdentifiableURL?
    @State private var emptyIconPulse = false
    @State private var emptyIconPulseTask: Task<Void, Never>?
    private let accent = Color(red: 0.68, green: 0.40, blue: 1.00)   // 娛樂紫，對齊本頁地圖 accent

    /// (地點名稱, 照片檔名) 依地點展開
    private var entries: [(spot: String, name: String)] {
        spots.flatMap { spot in spot.photoNames.map { (spot: spot.name, name: $0) } }
    }

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    albumEmptyState
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

    // MARK: - 空狀態（雙層脈衝光環 + 漸層底圓，對齊 emptyOverlay／FoodMapView 既有規格）

    private var albumEmptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.25), lineWidth: 1.5)
                    .frame(width: 100, height: 100)
                    .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                    .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false), value: emptyIconPulse)
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.13), lineWidth: 1)
                    .frame(width: 100, height: 100)
                    .scaleEffect(emptyIconPulse ? 1.60 : 1.0)
                    .animation(.easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false), value: emptyIconPulse)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.85), accent.opacity(0.50)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .overlay(Circle().stroke(.white.opacity(0.30), lineWidth: 0.75))
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .onAppear {
                emptyIconPulseTask?.cancel()
                emptyIconPulse = false
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

            Text("還沒有旅遊照片")
                .font(.headline)
            Text("在「娛樂」變動支出記錄時附上照片，\n這裡就會集結成相簿。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 4)
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 共用縮圖

private func photoThumb(url: URL, width: CGFloat, height: CGFloat) -> some View {
    AsyncThumbnailView(url: url, size: CGSize(width: width, height: height))
}
