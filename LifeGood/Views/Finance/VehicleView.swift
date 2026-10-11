import SwiftUI

// MARK: - 美化紀錄（VehicleView）
// [2026-06 v1] 本次美化方向：
//   1. summaryHeader → 升級為 teal 漸層英雄卡片：總估值大字 + 車輛計數膠囊 +
//      右側折舊資產損益 KPI 膠囊 + 散景裝飾圓，
//      加入 KPI 橫列（購入成本 / 月養車費），對齊 FixedExpenseView fixedSummaryHeader 規格；
//      加入進場動畫（headerAppeared 旗標）
//   2. emptyState → 升級為雙層脈衝光環 + 漸層底圓 + teal CTA 按鈕，
//      對齊 SavingsInsuranceView emptyStateView 空狀態設計規格
//   3. vehicleCard → 加入左側 4pt teal 漸層強調條 + 44pt 漸層圖示圓 + 陰影，
//      品牌/燃料類型標籤改用 Capsule 膠囊（對齊 ExpenseRow 視覺規格），
//      估值以主要大字顯示（.system(size: 17, weight: .bold, design: .rounded)），
//      折舊率與持有年數改為彩色膠囊標籤
//   4. 卡片列表 → 改為 insetGrouped List + 交錯淡入進場動畫（cardsAppeared 旗標），
//      對齊 SavingsInsuranceView / StockView 列表規格
//
// [2026-06 v2] 本次美化方向：
//   5. activeVehiclesSectionHeader → 新增「持有中 N 輛」Section 標頭
//      （左側 4pt Capsule 漸層條 + subheadline.bold 文字 + 輛數 Capsule 膠囊），
//      加入 vehiclesSectionHeaderAppeared 進場動畫；對齊 StockView activeStocksSectionHeader 規格
//   6. summaryHeader 迷你車輛估值佔比彩條 → KPI 橫列下方加入白色分隔線 +
//      多色分配彩條（每輛車按估值比例著色，由高到低排列）+ 圖例點陣列（色點 + 車名），
//      對齊 FinanceOverviewView totalAssetsCard mini allocation bar 規格
// [2026-06 v3] 本次美化方向：
//   7. summaryHeader 背景 ZStack 末層加入 LinearGradient [.white.opacity(0.18), .clear]
//      top→center 玻璃反光覆蓋層，對齊 VariableExpenseView / IncomeView / OverviewView v3/v4
//      英雄卡片 glass shine 統一規格，消除此頁與其他英雄卡的視覺均值落差。
//   8. summaryHeader mini allocation bar：補入 clipShape(RoundedRectangle) +
//      glow overlay（白色頂光 + 底部柔化），對齊 StockView.allocationMiniBar v3 規格；
//      補入左展開 spring 動畫（miniBarAppeared scaleEffect x: 0.04→1.0 anchor: .leading），
//      對齊 FinanceOverviewView.totalAssetsCard v4 彩條動畫規格。
//   9. vehicleCard 圖示圓：補入 Circle().stroke(heroAccent.opacity(0.18), lineWidth: 0.75)，
//      對齊 StockView.stockCard / SavingsInsuranceView.insuranceCard 圖示圓邊框規格。
//  10. vehicleCard 品牌/動力類型 Capsule：各加入 .overlay(Capsule().stroke(…opacity(0.22), 0.6pt))
//      細邊框，對齊 StockView.stockCard symbol Capsule / IncomeView.incomeRow 膠囊規格。
//  11. vehicleCard 折舊率膠囊：補入 .overlay(Capsule().stroke(…opacity(0.22), 0.6pt))，
//      對齊全 App 損益膠囊細邊框規格（FinanceOverviewView / StockView）。
//  12. fmtShort「NT$%.0f萬」→「%.1f萬」：去掉 NT$ 前綴、加 1 位小數，
//      對齊 TaxOverviewView v3 / OverviewView.smartCurrency 的萬量級顯示規格。
//
// [2026-08 v13] summaryHeader 英雄卡大字自適應收尾：
//  13. 頂部「車輛總估值」32pt 大字原本沒有 lineLimit／minimumScaleFactor 防截斷保護，
//      是同卡片內唯一缺這道防護的數字——右上角「折舊損失」KPI 膠囊已有
//      .lineLimit(1).minimumScaleFactor(0.7)，這裡當時被漏掉；估值達億量級或機型/幣別
//      顯示較長字串時可能被系統裁切。補上 .lineLimit(1) + .minimumScaleFactor(0.6)，
//      對齊 OverviewView v25.30／LifeOverviewView v25.29／LifeRealEstateView v25.28／
//      ChildrenResumeView v25.27 同一輪「英雄卡大字自適應收尾」規格，讓大額估值在小螢幕
//      上自動縮字而不被截斷，同時維持在可辨識最小字級以上。純視覺層調整，totalValue／
//      fmtShort 等既有金額計算與資料綁定完全未變動。

enum VehicleSortOption: String, CaseIterable, Identifiable {
    case purchasePrice = "購入價格"
    case currentValue = "估值"
    case depreciationRate = "折舊率"
    case yearsOwned = "持有年數"
    case monthlyExpense = "每月養車費"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .purchasePrice: return "tag"
        case .currentValue: return "chart.line.uptrend.xyaxis"
        case .depreciationRate: return "arrow.down.right"
        case .yearsOwned: return "calendar"
        case .monthlyExpense: return "creditcard"
        }
    }
}

// [v25.527] 理財介面重做（使用者：「就照你建議的吧，一次做完」）：
//   - 青色英雄卡換成「今年這條路」看板（FinanceBoards.swift 的 VehicleBoard）：1 月到 12 月，
//     車停在今天，路邊一個月一個圓標（大小＝那個月花多少），前面的路牌是接下來要繳的；
//     膠囊是每度電、每公里、折舊、車貸還要繳。
//   - 看板只算還持有的車（原本的總估值連賣掉的也加進去）。
//   - 車輛卡換成跟收支同一張項目卡（MoneyItemCard）：卡面是最新的一張照片，沒有就是插畫；
//     有車貸的多一條「車貸 已繳 28／60 期・還要 NT$38萬」。賣掉的另外一段、淡一點。
//
// [v25.538] 先修資料（畫面不變）：
//   - 拿掉列表底部的「折舊開關」：它不擋付費、開關狀態不保存，一按「套用」就用每年 15% 永久蓋掉
//     全部持有中車輛的估值（連手填的），關掉也不會還原。改成編輯頁估值欄下的「照每年 15% 估（帶入）」，
//     只把數字填進欄位，按儲存才算數。
//   - 拿掉永遠不會打開的 editingItem sheet（編輯只從卡片進）。
//
// [v25.539] 同一套數字：每台車（含已售出）在 .task 裡 build 一次 VehicleFacts，項目卡、看板、排序都讀它；
//   排序「每月養車費」「折舊率」「估值」照卡片上寫的那個數排；持有中／已售出用 isSold(asOf:)（售出日到了才算賣掉）。

struct VehicleView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var viewingItem: Vehicle?
    @State private var sortOption: VehicleSortOption = .purchasePrice
    @State private var sortAscending = false
    /// [v25.538] 左滑刪整台車先問一次：以前按下去就連記帳支出、照片一起刪掉，沒有確認。
    /// 要刪的車和筆數在打開確認框那一刻算好（不清掉，免得確認框收起來時標題閃成空的）
    @State private var deleteRequest: VehicleDeleteRequest?
    @State private var showDeleteConfirm = false
    @State private var showPremiumAlert = false
    @State private var headerAppeared = false
    @State private var cardsAppeared = false
    @State private var emptyIconPulse = false
    @State private var emptyPulseTask: Task<Void, Never>?
    /// 每台車的幾個數字（每月養車、估值、車貸…）與看板：掃記帳的支出算，放在 .task 裡
    @State private var facts: [UUID: VehicleFacts] = [:]
    @State private var board = VehicleBoardData()

    private let heroAccent    = Color(red: 0.18, green: 0.68, blue: 0.68)
    private let heroAccentDark = Color(red: 0.08, green: 0.46, blue: 0.48)

    /// [v25.538] 以前升冪直接回 !result：兩台一樣的時候兩個方向都成立，不是 sort 要的嚴格弱序，
    /// 也沒有次要鍵（購入價都是 0 的車每次順序不同）。改成先比選的鍵，一樣再比車名、最後比 id
    private var sortedVehicles: [Vehicle] {
        let option = sortOption
        let ascending = sortAscending
        let map = facts
        return store.vehicles.sorted { a, b in
            let ka = Self.sortKey(a, option, map[a.id])
            let kb = Self.sortKey(b, option, map[b.id])
            if ka != kb { return ascending ? ka < kb : ka > kb }
            let byName = a.name.localizedStandardCompare(b.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return a.id.uuidString < b.id.uuidString
        }
    }

    /// [v25.539] 估值、折舊率、每月養車費改照卡片上寫的那個數排（VehicleFacts）：以前「每月養車費」只比
    /// 車子鏡像的定期月均（季繳當月繳、沒算記帳連過來的），「估值」比的是沒填時的 0，跟卡片寫的對不起來。
    /// facts 還沒算好（剛打開那一下）時估值退回車子自己的欄位，其他兩個當 0
    private static func sortKey(_ v: Vehicle, _ option: VehicleSortOption, _ f: VehicleFacts?) -> Double {
        switch option {
        case .purchasePrice: return v.purchasePrice
        case .currentValue: return f?.value ?? v.currentValue
        case .depreciationRate:
            // 折得越多排越前面（降冪）：facts 的分數是「估值 ÷ 購入價 − 1」，折舊是負的，所以反過來比。
            // 算不出來的（沒填購入價、估值還沒填）當持平
            return -(f?.depreciationRate ?? 0)
        case .yearsOwned: return v.yearsOwned
        case .monthlyExpense: return f?.monthly ?? 0
        }
    }

    var body: some View {
        let sorted = sortedVehicles
        // [v25.539] 已售出＝售出日已經到了（售出日填在未來的照持有中算，跟看板、理財總覽同一個判斷）
        let now = Date()
        let active = sorted.filter { !$0.isSold(asOf: now) }
        let sold = sorted.filter { $0.isSold(asOf: now) }
        return NavigationStack {
            List {
                // 看板嵌入 List，與列表一起捲動
                Section {
                    VehicleBoard(data: board)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .opacity(headerAppeared ? 1 : 0)
                        .offset(y: headerAppeared ? 0 : 22)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                headerAppeared = true
                            }
                        }
                }

                if store.vehicles.isEmpty {
                    Section {
                        emptyState
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    if !active.isEmpty {
                        Section(header: MoneyGroupHeader(theme: .finDrive, title: "持有中", count: active.count,
                                                         total: MoneyFormat.short(board.value), unit: "輛")) {
                            ForEach(Array(active.enumerated()), id: \.element.id) { idx, item in
                                row(item, index: idx)
                            }
                        }
                    }
                    if !sold.isEmpty {
                        Section(header: MoneyGroupHeader(theme: .finDrive, title: "已售出", count: sold.count,
                                                         total: "", unit: "輛")) {
                            ForEach(Array(sold.enumerated()), id: \.element.id) { idx, item in
                                row(item, index: active.count + idx)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("汽車、機車")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(VehicleSortOption.allCases) { option in
                                Button {
                                    if sortOption == option {
                                        sortAscending.toggle()
                                    } else {
                                        sortOption = option
                                        sortAscending = false
                                    }
                                } label: {
                                    Label {
                                        Text(option.rawValue)
                                    } icon: {
                                        if sortOption == option {
                                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                        } else {
                                            Image(systemName: option.icon)
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.arrow.down")
                                Text(sortOption.rawValue)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Button {
                            if subscription.isPremium { showAdd = true }
                            else { showPremiumAlert = true }
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                        }
                    }
                }
            }
            .task(id: factsTaskKey) { rebuild() }
            .sheet(isPresented: $showAdd) { AddVehicleView().appStores() }
            .sheet(item: $viewingItem) { item in VehicleDetailView(vehicleId: item.id).appStores() }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .vehicleDeleteDialog(isPresented: $showDeleteConfirm, request: deleteRequest) { v, mode in
                deleteVehicle(v, mode: mode)
            }
            .onAppear {
                withAnimation(.spring(response: 0.50, dampingFraction: 0.82).delay(0.08)) {
                    cardsAppeared = true
                }
            }
            .onDisappear {
                headerAppeared = false
                cardsAppeared = false
                emptyIconPulse = false
            }
        }
    }

    /// [v25.539] .task(id:) 用：車子或記帳改了才重算（同 RealEstateView）。拆成獨立的 var，
    /// body 那一長串修飾器裡不放字串插值
    private var factsTaskKey: String {
        "\(store.modifyID)-\(expenseStore.modifyID)"
    }

    /// 看板與每台車的數字（每月養車、估值、車貸…）。[v25.539] 每台（含已售出）只 build 一次，
    /// 列表項目卡、看板、排序都讀這一份；同一個 now，看板和卡片才不會差一天
    private func rebuild() {
        let now = Date()
        var map: [UUID: VehicleFacts] = [:]
        for v in store.vehicles {
            map[v.id] = VehicleFacts.build(v, expense: expenseStore, now: now)
        }
        facts = map
        board = VehicleBoardData.build(vehicles: store.vehicles, facts: map, expense: expenseStore, now: now)
    }

    // MARK: - 車輛卡片

    private func row(_ item: Vehicle, index: Int) -> some View {
        MoneyItemCard(item: .vehicle(item, facts: facts[item.id]))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .contentShape(Rectangle())
            .opacity(cardsAppeared ? 1 : 0)
            .offset(y: cardsAppeared ? 0 : 18)
            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.05 * Double(min(index, 10))),
                       value: cardsAppeared)
            .onTapGesture { viewingItem = item }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                // [v25.538] 不用 role: .destructive：那會讓 List 一按就把這列滑掉（沒付費、按取消時
                // 卡片都已經不見了）；改用紅色 tint，先擋付費、再開確認框，按了才真的刪
                Button {
                    guard subscription.isPremium else {
                        showPremiumAlert = true
                        return
                    }
                    deleteRequest = VehicleDeleteRequest(
                        vehicle: item,
                        summary: VehicleDeletion.summary(of: item, expenseStore: expenseStore)
                    )
                    showDeleteConfirm = true
                } label: {
                    Label("刪除", systemImage: "trash")
                }
                .tint(.red)
            }
    }

    /// [v25.538] 收成 VehicleDeletion：以前這裡自己 removeAll 支出，沒清銀行扣款紀錄，
    /// 只靠 linkedVehicleId 連過來的支出（例如車貸）也會留下指向不存在車子的連結。
    /// 下一個 runloop 才改 store：確認框正在收的那個交易裡改 store 容易閃退
    private func deleteVehicle(_ item: Vehicle, mode: VehicleDeletion.Mode) {
        let finance = store
        let expenses = expenseStore
        let life = lifeStore
        let id = item.id
        DispatchQueue.main.async {
            // 用 store 裡最新的那一份（確認框開著的時候可能被同步改過）
            guard let v = finance.vehicles.first(where: { $0.id == id }) else { return }
            VehicleDeletion.delete(v, mode: mode, financeStore: finance, expenseStore: expenses, lifeStore: life)
        }
    }

    // MARK: - 空狀態

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                // 外層脈衝光環
                Circle()
                    .stroke(heroAccent.opacity(emptyIconPulse ? 0 : 0.28), lineWidth: 1.5)
                    .frame(width: 110, height: 110)
                    .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 內層脈衝光環（延遲製造波紋層次）
                Circle()
                    .stroke(heroAccent.opacity(emptyIconPulse ? 0 : 0.14), lineWidth: 1)
                    .frame(width: 110, height: 110)
                    .scaleEffect(emptyIconPulse ? 1.62 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 主圓底（漸層填色）
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [heroAccent.opacity(0.14), heroAccent.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .overlay(
                        Circle()
                            .stroke(heroAccent.opacity(0.22), lineWidth: 1.2)
                    )
                Image(systemName: "car.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(heroAccent.opacity(0.70))
            }
            .onAppear {
                emptyIconPulse = false
                emptyPulseTask?.cancel()
                emptyPulseTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    emptyIconPulse = true
                }
            }
            .onDisappear {
                emptyPulseTask?.cancel()
            }

            VStack(spacing: 10) {
                Text("尚無車輛紀錄")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                Text("新增汽車、機車後可追蹤估值、\n折舊與每月養車支出")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button {
                if subscription.isPremium { showAdd = true }
                else { showPremiumAlert = true }
            } label: {
                Label("新增車輛", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [heroAccent, heroAccentDark],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: heroAccentDark.opacity(0.38), radius: 10, y: 5)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - [v25.538] 刪整台車的確認框（列表左滑、卡片工具列共用）

/// 要刪的車和筆數：在打開確認框那一刻算好存起來。message 閉包每次重畫都會跑，不要在裡面掃全部記帳
struct VehicleDeleteRequest {
    let vehicle: Vehicle
    let summary: VehicleDeletion.Summary
}

extension View {
    /// 「只刪車子，記帳留著」放前面：加油、充電是真的花掉的錢，一起刪會改寫過去每個月的支出統計；
    /// 「連記帳一起刪」只有真的連到記帳時才出現（0 筆時只有一顆「刪除」）。
    /// 照片紀錄兩顆都會刪，說明（VehicleDeletion.confirmMessage）先講這個
    func vehicleDeleteDialog(isPresented: Binding<Bool>, request: VehicleDeleteRequest?,
                             onDelete: @escaping (Vehicle, VehicleDeletion.Mode) -> Void) -> some View {
        let title: String = "刪除「\(request?.vehicle.name ?? "")」？"
        return confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible,
                                  presenting: request) { req in
            if req.summary.expenseCount > 0 {
                Button("只刪車子，記帳留著", role: .destructive) { onDelete(req.vehicle, .unlinkOnly) }
                Button("連記帳一起刪", role: .destructive) { onDelete(req.vehicle, .withExpenses) }
            } else {
                Button("刪除", role: .destructive) { onDelete(req.vehicle, .unlinkOnly) }
            }
            Button("取消", role: .cancel) {}
        } message: { req in
            Text(VehicleDeletion.confirmMessage(req.summary))
        }
    }
}
