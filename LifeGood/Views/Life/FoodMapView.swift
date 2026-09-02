import SwiftUI
import MapKit

// MARK: - 美化紀錄（FoodMapView）
// [2026-06 v1] 本次美化方向：
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
// [2026-06 v2] 本次美化方向：
//   7. RestaurantDetailSheet.headerCard：加入 cardAppeared spring 進場動畫
//      （透明度 + Y 位移），對齊 SpouseResumeView.heroCard 進場規格
//   8. RestaurantDetailSheet.photoGallerySection header：升級為 Capsule 4pt 漸層側條
//      + subheadline.bold + 計數膠囊徽章，對齊 visitsSection header 設計語言
//   9. RestaurantDetailSheet.visitsSection：加入 visitsAppeared 交錯淡入 + 向上進場動畫，
//      對齊 StockDetailView.transactionsSection stagger 規格
//  10. RestaurantDetailSheet.companionCard：升級為粉紅漸層英雄小卡（含散景圓 + 36pt 漸層
//      圖示圓 + 粉紅膠囊強調標籤），對齊 SpouseResumeView.heroCard 設計語言
// [2026-06 v3] 本次美化方向：
//  11. statsCard 散景圓升至三顆（新增 55pt 中右側裝飾圓），
//      頂部加入玻璃光澤覆層（LinearGradient [.white.opacity(0.18), .clear], top→center），
//      對齊 IncomeView.summaryHeader / VariableExpenseView.monthSummaryHeader v3 規格；
//      「N 間」計數膠囊補入 Capsule().stroke 邊框，大字金額加 minimumScaleFactor(0.6)。
//  12. RestaurantDetailSheet.headerCard 散景圓升至三顆（新增 50pt 中右側），
//      頂部加入玻璃光澤覆層，對齊全 App 英雄卡三圓散景 + 玻璃光澤規格；
//      在 KPI 列上方加入餐廳名稱（.title3.bold 白色大字 + mappin 地址副標），
//      強化視覺層次感，對齊 SpouseResumeView.heroCard 姓名大字設計。
//  13. restaurantRow 44pt 圖示圓：補入 Circle().stroke(accent.opacity(0.22), lineWidth:0.75)
//      overlay 細邊框，對齊 FamilyView v2 / CareerView v2 圖示圓邊框規格；
//      「造訪 N 次」膠囊補入 Capsule().stroke 邊框；
//      最近造訪日從純文字升級為 tertiarySystemFill Capsule 徽章，
//      對齊 OverviewView.recentRow / ChildrenResumeView.childCard 日期膠囊設計語言。
//  14. visitsSection 34pt 圖示圓：補入 Circle().stroke(accent.opacity(0.18), lineWidth:0.75)；
//      日期膠囊補入 Capsule().stroke(accent.opacity(0.22), lineWidth:0.6)；
//      同行者粉紅膠囊補入 Capsule().stroke(.pink.opacity(0.22), lineWidth:0.6)，
//      對齊全 App 膠囊徽章統一描邊規格。
//  15. companionCard 散景圓升至兩顆（新增 45pt 左下角）；
//      玻璃光澤覆層（top→center white.opacity(0.15)）；
//      「TOP」膠囊補入 Capsule().stroke(.white.opacity(0.35), lineWidth:0.75)；
//      36pt 圖示圓補入 Circle().stroke(.white.opacity(0.25), lineWidth:0.75)，
//      對齊 SpouseResumeView.heroCard 整體規格。
// [2026-07 v4] 一致性小步美化：
//  16. 餐廳清單 sheet「關閉」按鈕：topBarTrailing → topBarLeading，
//      對齊全 App「關閉／取消」一律置左的慣例（此為此檔案唯一例外，已統一）
// [2026-07 v5] 金額量級一致性：
//  17. FoodMapView.statsCard／restaurantRow 私有 fmtShort(_:) 只到「萬」量級（無條件捨去
//      小數、未處理億級單位），與同檔案 RestaurantDetailSheet.fmtWan（v3 已補上億級）及全 App
//      共用 Double.ntdWanString（萬/億自動切換、保留一位小數）不一致，四處呼叫改用 ntdWanString，
//      移除 fmtShort 與專用 decimalFormatter 死碼。
// [2026-07 v6] 金額量級一致性收尾：
//  18. RestaurantDetailSheet.detailKpiCell「總花費」「平均每次」原本各自呼叫私有
//      fmtWan(_:)／「NT$ \(fmtNum(_:))」，「平均每次」未做萬/億量級轉換，金額較大時
//      與同列「總花費」顯示規格不一致；兩處改用共用 Double.ntdWanString（對齊同檔案
//      restaurantRow 已使用的規格），並移除只剩單一呼叫點、與共用元件重複的私有
//      fmtWan(_:) 死碼。純顯示層調整，就診/造訪聚合等既有邏輯未變動。
// [2026-07 v7] 餐廳清單 sheet 補齊與姊妹頁 TravelMapView.listSheet 的均值差距：
//  19. listSheet 原本用系統原生 List(.insetGrouped) 裝載餐廳列，是「地圖類清單 sheet」
//      唯一還沒升級成自訂圓角卡片的頁面，深色模式下 List 分隔線/背景與本檔案其餘卡片
//      風格不一致；改為 ScrollView + restaurantListCard（VStack + RoundedRectangle 16pt
//      圓角＋細邊框＋陰影＋列間 Divider），對齊 TravelMapView.citySection 圓角卡規格。
//      （未比照 TravelMapView 額外做縣市分組——本頁餐廳資料無對應縣市解析欄位，若強加
//      會超出單純視覺調整範圍，故僅統一「容器樣式」，維持原本單一清單排序）。
//  20. restaurantRow 補上獨立 padding（水平 14／垂直 11）＋ contentShape(Rectangle())，
//      取代原本依賴 List 列自帶 inset 的寫法，確保脫離 List 後點擊熱區與視覺間距不變。
//  21. 新增 restaurantListEmptyState：篩選（如「照片」開關）後清單結果為零筆時，原本
//      只會看到裸露的空白 List，新增輕量灰階圖示＋提示文字卡片，對齊 emptyOverlay
//      isPhotoFilter 分支的簡化提示規格（不做全頁雙層脈衝光環，因這只是清單內的次要
//      篩選態，非首次使用的頁面級空狀態）。
//      純視覺容器調整，排序、篩選、開啟詳細 sheet 等既有商業邏輯完全未變動。
//      （下次美化本檔案時，可考慮 RestaurantDetailSheet.photoGallerySection 之後段落，
//      或比照 TravelMapView 補上縣市分組所需的地址解析，惟後者屬新增資料維度，需先
//      評估是否超出單純視覺調整範圍）
// [2026-07 v8] 補齊 photoGallerySection 之後段落的視覺一致性缺口：
//  22. RestaurantDetailSheet 底部「用地圖開啟」按鈕：原本是本 sheet 唯一沒有描邊／陰影
//      的扁平元素（headerCard／photoGallerySection／visitsSection／companionCard 皆已有
//      stroke + shadow），補上 Capsule 同款描邊（Color.blue.opacity(0.22), 0.75pt）與
//      輕量陰影（Color.blue.opacity(0.14), radius 6），文字字重 medium→semibold 對齊
//      全 App CTA 按鈕文字權重規格。純視覺調整，開啟地圖行為與座標計算完全未變動。
//      （visitsSection／companionCard 已在 v2–v3 完成描邊與進場動畫，本輪聚焦補齊最後
//      一處視覺缺口；下次美化本檔案時，可考慮比照 TravelMapView 補上縣市分組地址解析）
// [2026-08 v9] visitsSection 金額量級一致性補漏：
//  23. RestaurantDetailSheet.visitsSection 每筆造訪金額原本呼叫本檔案私有 fmtNum(_:)
//      （純千分位整數格式，無萬/億量級轉換），是 v5／v6 兩輪「金額量級一致性」清查時
//      唯一漏掉的呼叫點——v5 修的是 statsCard／restaurantRow，v6 修的是
//      detailKpiCell，兩輪都沒碰到 visitsSection 這筆逐次金額，單次餐費金額較高時
//      （如萬元等級聚餐）會與同 sheet 其餘金額顯示規格不一致。改呼叫共用
//      Double.ntdWanString，並移除只剩單一呼叫點的私有 fmtNum(_:)／decimalFormatter
//      死碼；同時補上 .lineLimit(1) + .minimumScaleFactor(0.7) 防截斷，對齊
//      visitsSection 同列日期／同行者膠囊已有的防護規格。純顯示層調整，
//      exp.amount 等既有資料完全未變動。
//      （下次美化本檔案時，可考慮比照 TravelMapView 補上縣市分組所需的地址解析）

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
            for name in raw.components(separatedBy: CharacterSet(charactersIn: ",、，")).map({ $0.trimmingCharacters(in: .whitespaces) })
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
    @StateObject private var locationProvider = LocationProvider.shared

    @State private var range: FoodMapRange = .all
    @State private var sort: FoodMapSort = .visits
    @State private var selectedCompanion: String? = nil  // nil = 全部
    @State private var selectedAggregate: RestaurantAggregate?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasCenteredInitially = false
    @State private var showListSheet = false
    @State private var showAlbumSheet = false
    @State private var photoOnly = false
    @State private var emptyIconPulse = false
    @State private var emptyIconPulseTask: Task<Void, Never>?
    @State private var statsCardAppeared = false

    var body: some View {
        let aggs = aggregates  // 單次計算，消除 body 內重複呼叫
        return NavigationStack {
            ZStack(alignment: .topLeading) {
                mapContent(aggs)

                topOverlay
                    .padding(.top, 8)
                    .padding(.horizontal, 10)

                bottomOverlay(count: aggs.count)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)

                if aggs.isEmpty {
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
            .onChange(of: aggs.count) { _, _ in
                tryInitialCenter()
            }
            .sheet(item: $selectedAggregate) { agg in
                RestaurantDetailSheet(aggregate: agg)
                    .environmentObject(expenseStore)
            }
            .sheet(isPresented: $showListSheet) {
                listSheet(aggs)
            }
            .sheet(isPresented: $showAlbumSheet) {
                // [模板化] 共用 MapAlbumSheet（與旅遊/醫療地圖同款）：彙整所有餐廳照片，
                // 支援依地點/依月份分組切換
                MapAlbumSheet(
                    title: "美食相簿",
                    accent: Color(red: 1.00, green: 0.55, blue: 0.18),
                    emptyTitle: "還沒有美食照片",
                    emptyHint: "在「飲食」變動支出記錄時附上照片，\n這裡就會集結成相簿。",
                    items: aggs.flatMap { agg in
                        agg.visits.flatMap { v in
                            v.photoFileNames.map {
                                AlbumPhotoItem(id: $0, url: Expense.photoURL(for: $0),
                                               group: agg.name, date: v.date)
                            }
                        }
                    }
                )
            }
        }
    }

    // MARK: - 地圖底層

    private func mapContent(_ aggs: [RestaurantAggregate]) -> some View {
        let maxCount = aggs.map(\.visitCount).max() ?? 1  // 單次計算，供每個 pin 共用
        return Map(position: $cameraPosition) {
            ForEach(aggs) { agg in
                Annotation(agg.name, coordinate: agg.coordinate) {
                    Button {
                        selectedAggregate = agg
                    } label: {
                        let sz = pinSize(for: agg, maxCount: maxCount)
                        ZStack {
                            Circle()
                                .fill(pinColor(for: agg))
                                .frame(width: sz, height: sz)
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
        let options = companionOptions  // 單次捕捉，避免 isEmpty 判斷與 ForEach 各呼叫一次 O(n) 掃描
        return HStack(alignment: .top, spacing: 8) {
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
                if !options.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            chip("全部家人", isSelected: selectedCompanion == nil, tint: .pink) {
                                selectedCompanion = nil
                            }
                            ForEach(options, id: \.self) { name in
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

    private func bottomOverlay(count: Int) -> some View {
        HStack {
            Button {
                showListSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                    Text("餐廳清單")
                        .font(.caption.weight(.semibold))
                    Text("\(count)")
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

            // 美食相簿（對齊 TravelMapView.bottomOverlay 旅遊相簿按鈕）
            Button {
                showAlbumSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "photo.stack")
                    Text("美食相簿")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)

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
                emptyIconPulseTask?.cancel()
                if !isPhotoFilter {
                    emptyIconPulseTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        emptyIconPulse = true
                    }
                }
            }
            // [除錯] photoOnly 切換不會改變外層 ZStack 的身分（只有內層脈衝環用
            // if !isPhotoFilter 條件插入/移除），單靠 onAppear/onDisappear 不會在
            // 篩選切換時重觸發；空狀態時來回切一次「照片」開關會讓脈衝動畫永久停止
            // （關閉時 Task 未取消、旗標未歸零；重新開啟時環是新插入但已無 Task 讓
            // emptyIconPulse 從 false 變 true，animation(value:) 不會對初始插入播放）。
            // 改用 onChange(of:) 明確以 isPhotoFilter 驅動 Task 生命週期。
            .onChange(of: isPhotoFilter) { _, filtering in
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

    private func listSheet(_ aggs: [RestaurantAggregate]) -> some View {
        let items = sortedAggregates(from: aggs)
        return NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statsCard(items)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(FoodMapSort.allCases) { s in
                                chip(s.rawValue, isSelected: sort == s, tint: .orange) { sort = s }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    if items.isEmpty {
                        restaurantListEmptyState
                    } else {
                        restaurantListCard(items)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("餐廳清單（\(items.count)）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { showListSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// 餐廳清單圓角卡片（對齊 TravelMapView.citySection 圓角卡 + 分隔線規格）
    private func restaurantListCard(_ items: [RestaurantAggregate]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, agg in
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
                if idx < items.count - 1 { Divider().padding(.leading, 60) }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    /// 篩選後餐廳清單為空狀態（對齊 emptyOverlay isPhotoFilter 分支的輕量灰階提示規格）
    private var restaurantListEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text("目前沒有符合篩選條件的餐廳")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .padding(.horizontal)
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

    /// 依造訪次數決定 pin 大小（22~44），maxCount 由呼叫端傳入避免重複計算 aggregates
    private func pinSize(for agg: RestaurantAggregate, maxCount: Int) -> CGFloat {
        let ratio = Double(agg.visitCount) / Double(maxCount)
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
        let aggs = aggregates  // 單次計算，避免三次重複呼叫
        guard !aggs.isEmpty else { return }
        let lats = aggs.map(\.coordinate.latitude)
        let lons = aggs.map(\.coordinate.longitude)
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

    private func statsCard(_ aggs: [RestaurantAggregate]) -> some View {
        let total = aggs.reduce(0) { $0 + $1.totalSpent }
        let visits = aggs.reduce(0) { $0 + $1.visitCount }
        let avg = visits > 0 ? total / Double(visits) : 0
        let mostVisited = aggs.max(by: { $0.visitCount < $1.visitCount })

        return VStack(spacing: 0) {
            // 頂部：餐廳總數 + 總花費大字
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("美食探索紀錄")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                    Text(total.ntdWanString)
                        .heroBigValueFont()
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
                Spacer()
                Text("\(aggs.count) 間")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(.white.opacity(0.22))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 0.75))
                    .foregroundStyle(.white)
            }

            // KPI 橫列：造訪次數 / 平均每次 / 最常光顧
            HStack(spacing: 0) {
                HeroKpiCell(label: "造訪總次", value: "\(visits) 次", icon: "figure.walk")
                HeroKpiDivider()
                HeroKpiCell(label: "平均每次", value: avg.ntdWanString, icon: "chart.bar.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "最常光顧", value: mostVisited?.name ?? "—", icon: "star.fill")
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .heroCardShell(card: .foodMapStats)
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
        .onDisappear { statsCardAppeared = false }
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
                    .overlay(Circle().stroke(accent.opacity(0.22), lineWidth: 0.75))
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
                // [v3] 造訪次數膠囊 + 最近造訪日膠囊徽章
                HStack(spacing: 5) {
                    Text("造訪 \(agg.visitCount) 次")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(accent.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                    if let last = agg.lastVisit {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 8, weight: .medium))
                            Text(fmtRelative(last))
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                    }
                }
            }

            Spacer(minLength: 4)

            // 右側：總花費 + 平均
            VStack(alignment: .trailing, spacing: 3) {
                Text(agg.totalSpent.ntdWanString)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.85, green: 0.32, blue: 0.05))
                    .contentTransition(.numericText())
                Text("均 \(agg.averageSpent.ntdWanString)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    // MARK: - 資料聚合

    private static let memberSeparators = CharacterSet(charactersIn: ",、，")

    private var foodExpensesWithLocation: [Expense] {
        expenseStore.expenses.filter { exp in
            exp.expenseType == .variable
            && exp.variableCategory == .food
            && exp.placeLatitude != nil
            && exp.placeLongitude != nil
            && range.contains(exp.date)
            && (selectedCompanion == nil || (exp.diningMember ?? "")
                .components(separatedBy: Self.memberSeparators)
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

    // 接收 body 中已計算的 aggs，避免在 listSheet 內再次觸發 aggregates 的 Dictionary(grouping:) 計算
    private func sortedAggregates(from base: [RestaurantAggregate]) -> [RestaurantAggregate] {
        switch sort {
        case .visits:
            return base.sorted { $0.visitCount > $1.visitCount }
        case .spent:
            return base.sorted { $0.totalSpent > $1.totalSpent }
        case .recent:
            return base.sorted { ($0.lastVisit ?? .distantPast) > ($1.lastVisit ?? .distantPast) }
        }
    }

    private var companionOptions: [String] {
        var set = Set<String>()
        for exp in expenseStore.expenses where
            exp.expenseType == .variable && exp.variableCategory == .food {
            guard let raw = exp.diningMember, !raw.isEmpty else { continue }
            for n in raw.components(separatedBy: Self.memberSeparators)
                            .map({ $0.trimmingCharacters(in: .whitespaces) })
                where !n.isEmpty {
                set.insert(n)
            }
        }
        return set.sorted()
    }

    // MARK: - 格式化

    private static let relativeDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"
        return f
    }()

    private func fmtRelative(_ date: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                       to: cal.startOfDay(for: Date())).day ?? 0
        if days == 0 { return "今天" }
        if days == 1 { return "昨天" }
        if days < 7 { return "\(days) 天前" }
        if days < 30 { return "\(days / 7) 週前" }
        return Self.relativeDateFormatter.string(from: date)
    }
}

// MARK: - 餐廳詳細 Sheet

struct RestaurantDetailSheet: View {
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    let aggregate: RestaurantAggregate
    @State private var cameraPosition: MapCameraPosition = .automatic
    // 進場動畫旗標
    @State private var cardAppeared = false
    @State private var visitsAppeared = false

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
                        .opacity(cardAppeared ? 1 : 0)
                        .offset(y: cardAppeared ? 0 : 20)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                cardAppeared = true
                            }
                        }

                    if !aggregatePhotos.isEmpty {
                        photoGallerySection
                    }

                    visitsSection

                    if let companion = aggregate.topCompanion {
                        companionCard(companion)
                    }

                    // [v8] 底部「用地圖開啟」原本是全檔案唯一沒有描邊/陰影的扁平元素，
                    // 與 headerCard／photoGallerySection／visitsSection／companionCard 皆已有的
                    // 描邊＋陰影節奏不一致；補上 Capsule stroke + 輕量陰影，字重升級對齊
                    // 其餘 CTA 文字權重，純視覺調整，開啟地圖行為完全未變動。
                    Button {
                        openInMaps()
                    } label: {
                        Label("用地圖開啟", systemImage: "map.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.blue.opacity(0.22), lineWidth: 0.75)
                            )
                            .shadow(color: Color.blue.opacity(0.14), radius: 6, x: 0, y: 3)
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

    // [v3] 餐廳詳情英雄卡（橘色漸層 + 三顆散景圓 + 玻璃光澤，對齊全 App 英雄卡規格）
    private var headerCard: some View {
        VStack(spacing: 0) {
            // [v3] 餐廳名稱大字（.title3.bold 白色，提升視覺層次）
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(aggregate.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    if !aggregate.address.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 10, weight: .medium))
                            Text(aggregate.address)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white.opacity(0.80))
                    }
                }
                Spacer()
            }
            .padding(.bottom, 14)

            // KPI 三格：造訪次數 / 總花費 / 平均每次
            HStack(spacing: 0) {
                HeroKpiCell(label: "造訪次數", value: "\(aggregate.visitCount) 次",
                            icon: "calendar.circle.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "總花費", value: aggregate.totalSpent.ntdWanString,
                            icon: "yensign.circle.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "平均每次", value: aggregate.averageSpent.ntdWanString,
                            icon: "chart.bar.fill")
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .heroCardShell(card: .foodMapDetail)
        .padding(.horizontal)
    }


    /// 此餐廳所有造訪所累積的照片檔名
    private var aggregatePhotos: [String] {
        aggregate.visits.flatMap { $0.photoFileNames }
    }

    @State private var viewingPhotoURL: IdentifiableURL?

    private var photoGallerySection: some View {
        let photoAccent = Color(red: 1.00, green: 0.55, blue: 0.18)
        return VStack(alignment: .leading, spacing: 8) {
            // 升級為 Capsule 4pt 側條 + subheadline.bold + 計數膠囊，對齊 visitsSection header
            HStack(spacing: 10) {
                Capsule()
                    .fill(LinearGradient(
                        colors: [photoAccent, photoAccent.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 4, height: 18)
                Image(systemName: "photo.stack")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(photoAccent)
                Text("照片")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("\(aggregatePhotos.count) 張")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(photoAccent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(photoAccent.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(photoAccent.opacity(0.22), lineWidth: 0.75))
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(aggregatePhotos, id: \.self) { name in
                        let url = Expense.photoURL(for: name)
                        Button {
                            viewingPhotoURL = IdentifiableURL(url: url)
                        } label: {
                            AsyncThumbnailView(url: url, size: CGSize(width: 110, height: 90))
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
                        // [v3] 34pt 漸層圖示圓 + stroke 邊框
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [accent.opacity(0.18), accent.opacity(0.07)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(accent.opacity(0.18), lineWidth: 0.75))
                            Image(systemName: "fork.knife")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(accent.opacity(0.85))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            // [v3] 日期膠囊徽章 + stroke
                            Text(fmtDate(exp.date))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(accent.opacity(0.10))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                            // [v3] 同行者粉紅膠囊 + stroke
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
                                .overlay(Capsule().stroke(Color.pink.opacity(0.22), lineWidth: 0.6))
                            }
                        }

                        Spacer(minLength: 4)

                        Text(exp.amount.ntdWanString)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.85, green: 0.32, blue: 0.05))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    // 交錯淡入 + 向上進場動畫，對齊 StockDetailView.transactionsSection 規格
                    .opacity(visitsAppeared ? 1 : 0)
                    .offset(y: visitsAppeared ? 0 : 10)
                    .animation(
                        .spring(response: 0.44, dampingFraction: 0.82)
                            .delay(0.05 * Double(min(idx, 10))),
                        value: visitsAppeared
                    )

                    if idx < sorted.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
            .padding(.horizontal)
            .onAppear {
                withAnimation(.spring(response: 0.50, dampingFraction: 0.82).delay(0.08)) {
                    visitsAppeared = true
                }
            }
        }
    }

    private func companionCard(_ name: String) -> some View {
        let pinkLight = Color(red: 0.96, green: 0.35, blue: 0.60)
        let pinkDark  = Color(red: 0.76, green: 0.18, blue: 0.42)
        return HStack(spacing: 14) {
            // [v3] 36pt 粉紅漸層圖示圓 + stroke
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [pinkLight.opacity(0.28), pinkLight.opacity(0.12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 36, height: 36)
                    .shadow(color: pinkLight.opacity(0.22), radius: 5, x: 0, y: 2)
                    .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.75))
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(pinkLight)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("最常一起用餐")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
                Text(name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer()

            // [v3] 粉紅膠囊強調標籤 + stroke
            Text("TOP")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(pinkLight)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.white.opacity(0.22))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 0.75))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            ZStack {
                LinearGradient(
                    colors: [pinkLight, pinkDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // [v3] 兩顆散景裝飾圓
                Circle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 80, height: 80)
                    .offset(x: 60, y: -25)
                    .blur(radius: 10)
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 45, height: 45)
                    .offset(x: -50, y: 20)
                    .blur(radius: 7)
                // [v3] 玻璃光澤
                LinearGradient(
                    colors: [.white.opacity(0.15), .clear],
                    startPoint: .top, endPoint: .center
                )
                .allowsHitTesting(false)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: pinkDark.opacity(0.32), radius: 10, x: 0, y: 5)
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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"
        return f
    }()

    private func fmtDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }
}
