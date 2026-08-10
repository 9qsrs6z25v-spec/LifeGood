import SwiftUI

// MARK: - 卡牌稀有度

enum CardRarity {
    case common
    case uncommon
    case rare
    case epic
    case legendary

    /// 汽車分級：0~50萬 / 51~100萬 / 101~200萬 / 201萬以上
    init(price: Double) {
        let wan = price / 10000
        switch wan {
        case ..<51: self = .common
        case ..<101: self = .uncommon
        case ..<201: self = .rare
        default: self = .legendary
        }
    }

    /// 房地產分級：0~600萬 / 601~1000萬 / 1001~1500萬 / 1501~2000萬 / 2001萬以上
    static func realEstate(price: Double) -> CardRarity {
        let wan = price / 10000
        switch wan {
        case ..<601: return .common
        case ..<1001: return .uncommon
        case ..<1501: return .rare
        case ..<2001: return .epic
        default: return .legendary
        }
    }

    /// 股票分級：以市值或成本（萬元）分級
    /// 0~10萬 / 11~50萬 / 51~100萬 / 101~300萬 / 301萬以上
    static func stock(value: Double) -> CardRarity {
        let wan = value / 10000
        switch wan {
        case ..<11:  return .common
        case ..<51:  return .uncommon
        case ..<101: return .rare
        case ..<301: return .epic
        default:     return .legendary
        }
    }

    var label: String {
        switch self {
        case .common: return "COMMON"
        case .uncommon: return "UNCOMMON"
        case .rare: return "RARE"
        case .epic: return "EPIC"
        case .legendary: return "LEGENDARY"
        }
    }

    var borderGradient: [Color] {
        switch self {
        case .common: return [.gray.opacity(0.4), .gray.opacity(0.2)]
        case .uncommon: return [.cyan, .blue.opacity(0.6), .cyan]
        case .rare: return [.yellow, .orange, .yellow]
        case .epic: return [.purple, .pink, .purple, .indigo, .purple]
        case .legendary: return [.purple, .pink, .orange, .yellow, .green, .cyan, .blue, .purple]
        }
    }

    var bgGradient: [Color] {
        switch self {
        case .common: return [Color(.systemBackground), Color(.systemGray6)]
        case .uncommon: return [Color(.systemBackground), Color.cyan.opacity(0.05)]
        case .rare: return [Color(.systemBackground), Color.orange.opacity(0.08)]
        case .epic: return [Color(.systemBackground), Color.purple.opacity(0.10)]
        case .legendary: return [Color.black.opacity(0.9), Color.purple.opacity(0.15), Color.black.opacity(0.9)]
        }
    }

    var borderWidth: CGFloat {
        switch self {
        case .common: return 1
        case .uncommon: return 2
        case .rare: return 2.5
        case .epic: return 2.8
        case .legendary: return 3
        }
    }

    var textColor: Color {
        switch self {
        case .common: return .primary
        case .uncommon: return .cyan
        case .rare: return .orange
        case .epic: return .purple
        case .legendary: return .yellow
        }
    }

    var shadowColor: Color {
        switch self {
        case .common: return .clear
        case .uncommon: return .cyan.opacity(0.3)
        case .rare: return .orange.opacity(0.4)
        case .epic: return .purple.opacity(0.45)
        case .legendary: return .purple.opacity(0.5)
        }
    }
}

// MARK: - 售出印章

struct SoldStamp: View {
    var size: CGFloat = 18

    var body: some View {
        Text("售出")
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .tracking(2)
            .foregroundStyle(.red)
            .padding(.horizontal, size * 0.55)
            .padding(.vertical, size * 0.2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.red, lineWidth: size * 0.14)
            )
            .rotationEffect(.degrees(-15))
            .shadow(color: .black.opacity(0.3), radius: size * 0.18, x: size * 0.08, y: size * 0.15)
    }
}

// MARK: - 美化紀錄（VehicleDetailView）
// [2026-06 v1] 本次美化方向：
//   1. flashCard：加入 cardAppeared spring 進場動畫（透明度 + Y 位移），
//      對齊 StockDetailView flashCard 進場規格。
//   2. sectionHeader：升級為 Capsule 色條 + subheadline.bold + 計數膠囊，
//      對齊 VariableExpenseView / StockDetailView section 標題設計語言。
//   3. fixedExpenses 列：加入 38pt 藍色漸層圖示圓 + 分類 / 週期標籤 + 月均輔助文字，
//      對齊 FixedExpenseView FixedExpenseRow 視覺規格。
//   4. variableExpenses 列：加入 38pt 橘色漸層圖示圓 + 分類標籤 + 日期膠囊，
//      對齊 VariableExpenseView expenseRow 視覺規格。
//   5. 兩個列表：加入行間 Divider + 交錯淡入進場動畫（infoRowsAppeared），
//      對齊 StockDetailView transactionsSection 動畫規格。
//   6. infoSection 卡片：補極細 overlay 邊框，提升精緻感與深色模式相容性。
// [2026-06 v2] 本次美化方向：
//   7. flashCard 玻璃光澤：非 legendary 卡片背景加入 .white.opacity(0.18)→.clear
//      由上到中的 LinearGradient overlay，對齊全 App 英雄卡玻璃光澤規格
//      （OverviewView / StockView / VariableExpenseView 等）。
//   8. 圖示圓升圓形＋邊框：fixedExpenseRow / variableExpenseRow 圖示圓從
//      RoundedRectangle(cornerRadius:10) 升級為 Circle +
//      stroke(color.opacity(0.20), lineWidth: 0.75)，
//      對齊全 App 標準圓形圖示圓規格（ExpenseRow / incomeRow 等）。
//   9. vehicleKpiStrip：flashCard 正下方加入 KPI 橫列
//      （月固定支出 / 近12月變動 / 持有年限），各含 30pt 漸層圓圖示，
//      kpiStripAppeared spring 進場動畫；
//      對齊 LifeOverviewView.statsStrip / FamilyView.statsStrip 設計規格。
//  10. 金額色彩：支出列右側金額從 .primary 升為各自 accent 顏色（藍 / 橘），
//      提升視覺層次，讓定期與變動的分類色貫穿整列。
// [2026-07 v3] 補齊與 StockDetailView／RealEstateDetailView 兩個同型閃卡的視覺落差：
//  11. flashCard 估值大字（52pt）：原本唯獨本檔案缺少 minimumScaleFactor + lineLimit(1) +
//      contentTransition(.numericText())，車輛估值達六位數以上時大字有截斷風險，且切換車輛
//      時數字為硬切換而非平滑過渡；補上對齊 StockDetailView.market value（0.55）規格。
//  12. infoSection 空狀態：原本定期／變動支出兩張卡片各自以 isEmpty 整卡隱藏，若車輛兩者皆無
//      記錄，此區塊會完全留白、無任何提示，與 StockDetailView（交易/股利空狀態卡）、
//      RealEstateDetailView（emptySectionRow）等同型詳情頁不一致。新增 emptyExpensesCard，
//      兩份清單皆空時顯示「尚無支出記錄」提示卡，對齊全 App 空狀態設計規格。
// [2026-07 v4] 金額量級單位（萬／億）一致性：
//  13. flashCard 估值大字、底部「購入」值原本各自呼叫私有 fmtWan(_:)（僅 `%g` 除以萬，
//      無條件只顯示「萬」），車輛估值一旦達 1 億以上會顯示成 5～6 位數的「萬」大數字
//      （例如 12345.7萬），未跟進全 App 共用 Double.ntdWanString 既有的萬→億量級進位規則，
//      與同檔案 vehicleKpiStrip／fixedExpenseRow／variableExpenseRow（皆用 fmt = ntdWanString）
//      不一致。新增 splitWan(_:) 從 ntdWanString 拆出「數字／單位」二段供大字沿用既有字級設計，
//      兩處呼叫點改用 splitWan，並移除已無呼叫端的私有 fmtWan 死碼。純顯示層調整，估值／
//      購入價等既有試算邏輯完全未變動。
//      （StockDetailView 已於 v24.98、RealEstateDetailView 已於 v24.99 比照本次做法
//      補齊，全 App 詳情頁閃卡估值大字量級單位規格至此已收斂一致）
// [2026-08 v5] flashCard 車名補齊姊妹閃卡防截斷規格：
//  14. Text(vehicle.name)（.title.bold()）原本沒有 multilineTextAlignment／lineLimit／
//      minimumScaleFactor，也沒有橫向 padding，是 Vehicle／RealEstate／Stock 三款同型閃卡中
//      唯一缺這組防護的車名大字——RealEstateDetailView.estate.name／StockDetailView.stock.name
//      皆已有 .multilineTextAlignment(.center) + 外層 .padding(.horizontal, 24)，長車名在本頁
//      沒有橫向留白、換行也會靠左而非置中，與姊妹頁面觀感不一致。補上
//      .multilineTextAlignment(.center) + .lineLimit(2) + .minimumScaleFactor(0.7)，
//      並在外層 VStack 加上 .padding(.horizontal, 24)，對齊兩個姊妹閃卡規格，
//      讓超長車名（例如含年份/配備等級的完整車型名）自動縮字換行但不致無法辨識，
//      也不會頂到卡片邊緣。純視覺層調整，vehicle.name／brand 等既有資料完全未變動。

// MARK: - 汽車檢視卡片

struct VehicleDetailView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let vehicleId: UUID
    /// 每次 body 重算時從 store 取最新值，確保編輯後立即反映
    private var vehicle: Vehicle {
        store.vehicles.first(where: { $0.id == vehicleId }) ?? Vehicle(name: "")
    }
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showPremiumAlert = false
    // 照片紀錄（保養/稅費收據等，比照房地產裝潢照片）
    @State private var addingPhotoRecord = false
    @State private var editingPhotoRecord: VehiclePhotoRecord?
    @State private var cutePhotoDraft: CutePhotoDraft?
    // 項目詳情（點定期/變動支出列開啟）＋從相簿廊直接編輯連結支出
    @State private var viewingItem: VehicleItemRef?
    @State private var editingLinkedExpense: Expense?
    // 美化：進場動畫旗標（對齊 StockDetailView / RealEstateDetailView 規格）
    @State private var cardAppeared = false
    @State private var kpiStripAppeared = false
    @State private var infoRowsAppeared = false

    private var rarity: CardRarity { CardRarity(price: vehicle.purchasePrice) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    flashCard
                        .opacity(cardAppeared ? 1 : 0)
                        .offset(y: cardAppeared ? 0 : 22)
                        .onAppear {
                            withAnimation(.spring(response: 0.52, dampingFraction: 0.78)) {
                                cardAppeared = true
                            }
                        }
                    // v2：KPI 摘要橫列（月固定 / 近12月變動 / 持有年限）
                    vehicleKpiStrip
                        .opacity(kpiStripAppeared ? 1 : 0)
                        .offset(y: kpiStripAppeared ? 0 : 14)
                        .onAppear {
                            withAnimation(.spring(response: 0.50, dampingFraction: 0.80).delay(0.18)) {
                                kpiStripAppeared = true
                            }
                        }
                    infoSection
                    photoSection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("車輛卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            if subscription.isPremium { showEdit = true }
                            else { showPremiumAlert = true }
                        } label: {
                            Text("編輯").foregroundStyle(.green)
                        }
                        Button {
                            if subscription.isPremium { showDeleteConfirm = true }
                            else { showPremiumAlert = true }
                        } label: {
                            Text("刪除").foregroundStyle(.red)
                        }
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                AddVehicleView(editing: vehicle)
            }
            .sheet(isPresented: $addingPhotoRecord) {
                VehiclePhotoEditor(vehicleId: vehicleId, editing: nil)
            }
            .sheet(item: $editingPhotoRecord) { rec in
                VehiclePhotoEditor(vehicleId: vehicleId, editing: rec)
            }
            .sheet(item: $cutePhotoDraft) { draft in
                CutePhotoViewer(draft: draft)
            }
            .sheet(item: $viewingItem) { ref in
                VehicleItemDetailSheet(vehicleId: vehicleId, item: ref)
            }
            .sheet(item: $editingLinkedExpense) { exp in
                AddExpenseView(expenseType: exp.expenseType, editingExpense: exp)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .alert("確定要刪除這輛車嗎？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) {
                    deleteVehicle()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("刪除後所有連結的記帳支出也會一併移除，此操作無法復原。")
            }
        }
    }

    // MARK: - 閃卡主體

    private var flashCard: some View {
        VStack(spacing: 0) {
            // 頂部稀有度標籤
            HStack {
                Text(rarity.label)
                    .font(.caption2.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(rarity.textColor)
                Spacer()
                Label(vehicle.powerType.rawValue, systemImage: vehicle.powerType.icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(rarity == .legendary ? .yellow : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // 車名 + 品牌
            VStack(spacing: 6) {
                Text(vehicle.name)
                    .font(.title.weight(.bold))
                    .foregroundStyle(rarity == .legendary ? .white : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                if !vehicle.brand.isEmpty {
                    Text(vehicle.brand)
                        .font(.subheadline)
                        .foregroundStyle(rarity == .legendary ? .white.opacity(0.7) : .secondary)
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 24)

            // 估值（大字）
            VStack(spacing: 4) {
                // v3：補上 minimumScaleFactor + lineLimit + contentTransition，
                // 對齊 StockDetailView 市值大字規格，防止高額估值截斷並讓切換車輛時平滑過渡
                // v4：改用 splitWan 取代 fmtWan，估值達 1 億以上自動換算為「億元」單位
                let estimate = splitWan(vehicle.currentValue)
                Text(estimate.number)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(rarity.textColor)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text("\(estimate.unit)元")
                    .font(.subheadline)
                    .foregroundStyle(rarity == .legendary ? .white.opacity(0.6) : .secondary)
            }
            .padding(.vertical, 20)

            // 底部資訊列
            HStack {
                VStack(spacing: 2) {
                    Text("購入")
                        .font(.caption2).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text(splitWanLabel(vehicle.purchasePrice))
                        .font(.caption.bold()).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.8) : Color.primary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("折舊")
                        .font(.caption2).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text(String(format: "%.1f%%", vehicle.depreciationRate))
                        .font(.caption.bold()).foregroundStyle(.red)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("持有")
                        .font(.caption2).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text(String(format: "%.1f 年", vehicle.yearsOwned))
                        .font(.caption.bold()).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.8) : Color.primary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(
            // v2：非 legendary 加玻璃光澤，legendary 本身已有豐富色彩故跳過
            LinearGradient(colors: rarity.bgGradient,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(
                    LinearGradient(
                        colors: rarity == .legendary
                            ? [Color.clear, Color.clear]
                            : [Color.white.opacity(0.18), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    AngularGradient(colors: rarity.borderGradient, center: .center),
                    lineWidth: rarity.borderWidth
                )
        )
        .shadow(color: rarity.shadowColor, radius: rarity == .legendary ? 15 : 8, y: 4)
        .overlay(alignment: .topLeading) {
            if vehicle.isSold {
                SoldStamp(size: 32)
                    .offset(x: -10, y: -14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - 詳細資訊

    private var infoSection: some View {
        VStack(spacing: 16) {
            // v3：兩份清單皆空時顯示提示卡，避免區塊完全留白
            if vehicle.fixedExpenses.isEmpty && vehicle.variableExpenses.isEmpty {
                emptyExpensesCard
            }

            // 定期支出卡片
            if !vehicle.fixedExpenses.isEmpty {
                VStack(spacing: 0) {
                    sectionHeader("定期支出", color: .blue, count: vehicle.fixedExpenses.count)
                    ForEach(Array(vehicle.fixedExpenses.enumerated()), id: \.element.id) { idx, fe in
                        Button {
                            viewingItem = .fixed(fe)
                        } label: {
                            fixedExpenseRow(fe, index: idx)
                        }
                        .buttonStyle(.plain)
                            .opacity(infoRowsAppeared ? 1 : 0)
                            .offset(y: infoRowsAppeared ? 0 : 12)
                            .animation(
                                .spring(response: 0.44, dampingFraction: 0.82)
                                    .delay(0.04 * Double(idx)),
                                value: infoRowsAppeared
                            )
                        if idx < vehicle.fixedExpenses.count - 1 {
                            Divider().padding(.leading, 66)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
            }

            // 變動支出卡片
            if !vehicle.variableExpenses.isEmpty {
                let offset = vehicle.fixedExpenses.count
                VStack(spacing: 0) {
                    sectionHeader("變動支出", color: .orange, count: vehicle.variableExpenses.count)
                    ForEach(Array(vehicle.variableExpenses.enumerated()), id: \.element.id) { idx, ve in
                        Button {
                            viewingItem = .variable(ve)
                        } label: {
                            variableExpenseRow(ve, index: idx + offset)
                        }
                        .buttonStyle(.plain)
                            .opacity(infoRowsAppeared ? 1 : 0)
                            .offset(y: infoRowsAppeared ? 0 : 12)
                            .animation(
                                .spring(response: 0.44, dampingFraction: 0.82)
                                    .delay(0.04 * Double(idx + offset)),
                                value: infoRowsAppeared
                            )
                        if idx < vehicle.variableExpenses.count - 1 {
                            Divider().padding(.leading, 66)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
            }
        }
        .padding(.horizontal)
        .onAppear {
            withAnimation(.spring(response: 0.50, dampingFraction: 0.82).delay(0.10)) {
                infoRowsAppeared = true
            }
        }
    }

    // MARK: - 照片紀錄（保養/稅費收據/保險文件等，比照房地產裝潢照片章節）

    /// 相簿廊聚合項目：照片紀錄＋連結記帳支出的附件照片（同型概念見 RealEstateDetailView.HousePhotoItem）
    private enum VehicleGalleryItem: Identifiable {
        case record(VehiclePhotoRecord)
        case expense(Expense)
        var id: String {
            switch self {
            case .record(let r): return "r-\(r.id.uuidString)"
            case .expense(let e): return "e-\(e.id.uuidString)"
            }
        }
        var date: Date {
            switch self {
            case .record(let r): return r.date
            case .expense(let e): return e.date
            }
        }
    }

    /// 該車輛定期/變動支出連結的、有附照片的記帳支出
    private var linkedExpensePhotos: [Expense] {
        var ids = Set<UUID>()
        for fe in vehicle.fixedExpenses { if let id = fe.linkedExpenseId { ids.insert(id) } }
        for ve in vehicle.variableExpenses { if let id = ve.linkedExpenseId { ids.insert(id) } }
        guard !ids.isEmpty else { return [] }
        return expenseStore.expenses.filter { ids.contains($0.id) && !$0.photoFileNames.isEmpty }
    }

    @ViewBuilder
    private var photoSection: some View {
        // 照片紀錄＋連結支出照片合流（依日期新→舊），支出項目的收據照片不用重傳一次就同步出現
        let allItems: [VehicleGalleryItem] = (
            vehicle.photoRecords.map { VehicleGalleryItem.record($0) }
            + linkedExpensePhotos.map { VehicleGalleryItem.expense($0) }
        ).sorted { $0.date > $1.date }

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                sectionHeader("照片紀錄", color: .teal, count: allItems.count)
                Button {
                    if subscription.isPremium { addingPhotoRecord = true }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.subheadline).foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)
            }

            if allItems.isEmpty {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.teal.opacity(0.15), Color.teal.opacity(0.06)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 40, height: 40)
                        Circle()
                            .stroke(Color.teal.opacity(0.18), lineWidth: 0.75)
                            .frame(width: 40, height: 40)
                        Image(systemName: "camera.on.rectangle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.teal.opacity(0.65))
                    }
                    Text("尚無照片紀錄")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("點右上「+」新增保養、稅費收據等照片；支出項目附的照片也會顯示在這裡")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(allItems) { item in
                            switch item {
                            case .record(let rec):
                                Button {
                                    handlePhotoRecordTap(rec)
                                } label: {
                                    vehiclePhotoCard(rec)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        editingPhotoRecord = rec
                                    } label: {
                                        Label("編輯資訊", systemImage: "pencil")
                                    }
                                }
                            case .expense(let e):
                                Button {
                                    handleExpensePhotoTap(e)
                                } label: {
                                    expensePhotoCard(e)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        if subscription.isPremium { editingLinkedExpense = e }
                                        else { showPremiumAlert = true }
                                    } label: {
                                        Label("編輯支出", systemImage: "pencil")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    private func handleExpensePhotoTap(_ e: Expense) {
        guard !e.photoFileNames.isEmpty else { return }
        let urls = e.photoFileNames.map { Expense.photoURL(for: $0) }
        let trimmedNote = e.note.trimmingCharacters(in: .whitespaces)
        let title = e.title.isEmpty ? (trimmedNote.isEmpty ? "支出照片" : trimmedNote) : e.title
        cutePhotoDraft = CutePhotoDraft(
            urls: urls,
            title: title,
            note: (trimmedNote.isEmpty || trimmedNote == title) ? "" : trimmedNote,
            date: e.date,
            kind: .expense
        )
    }

    /// 連結支出照片卡：橙色「支出」徽章，其餘版型同 vehiclePhotoCard
    private func expensePhotoCard(_ e: Expense) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                if e.photoFileNames.count >= 2 {
                    ZStack {
                        ForEach(Array(e.photoFileNames.prefix(3).enumerated()).reversed(), id: \.element) { idx, name in
                            ThumbnailImageView(url: Expense.photoURL(for: name))
                                .frame(width: 108, height: 108)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .rotationEffect(.degrees(Double(idx) * 3.5))
                                .offset(x: CGFloat(idx) * 3, y: CGFloat(idx) * -3)
                        }
                    }
                    .frame(width: 116, height: 116)
                } else if let first = e.photoFileNames.first {
                    ThumbnailImageView(url: Expense.photoURL(for: first))
                        .frame(width: 116, height: 116)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if e.photoFileNames.count >= 2 {
                    Text("\(e.photoFileNames.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(5)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.orange)
                Text("支出")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.orange)
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.orange.opacity(0.10))
            .clipShape(Capsule())

            Text(e.title.isEmpty ? "支出照片" : e.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(formatRowDate(e.date))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 120)
    }

    private func handlePhotoRecordTap(_ rec: VehiclePhotoRecord) {
        guard !rec.photoFileNames.isEmpty else {
            editingPhotoRecord = rec
            return
        }
        let urls = rec.photoFileNames.map { VehiclePhotoRecord.photoURL(for: $0) }
        cutePhotoDraft = CutePhotoDraft(
            urls: urls,
            title: rec.title.isEmpty ? rec.category.rawValue : rec.title,
            note: rec.note,
            date: rec.date,
            kind: .vehicle(rec.category)
        )
    }

    /// 單筆照片紀錄卡：縮圖（單張或堆疊）＋類別徽章＋標題＋日期
    private func vehiclePhotoCard(_ rec: VehiclePhotoRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                if rec.photoFileNames.count >= 2 {
                    // 多張：後兩張斜角堆疊在底、首張在上（簡化版堆疊視覺）
                    ZStack {
                        // id 用檔名（.element）而非陣列 offset：比照 MultiPhotoGallery 既有規格，
                        // 避免新增/刪除照片時因 offset 相同、內容不同，被誤判為同一個 view slot
                        // 重用舊縮圖造成堆疊縮圖短暫閃爍成錯誤照片後才刷新。
                        ForEach(Array(rec.photoFileNames.prefix(3).enumerated()).reversed(), id: \.element) { idx, name in
                            ThumbnailImageView(url: VehiclePhotoRecord.photoURL(for: name))
                                .frame(width: 108, height: 108)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .rotationEffect(.degrees(Double(idx) * 3.5))
                                .offset(x: CGFloat(idx) * 3, y: CGFloat(idx) * -3)
                        }
                    }
                    .frame(width: 116, height: 116)
                } else if let url = rec.photoURL {
                    ThumbnailImageView(url: url)
                        .frame(width: 116, height: 116)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                // 張數膠囊（多張才顯示）
                if rec.photoFileNames.count >= 2 {
                    Text("\(rec.photoFileNames.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(5)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: rec.category.icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(rec.category.color)
                Text(rec.category.rawValue)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(rec.category.color)
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(rec.category.color.opacity(0.10))
            .clipShape(Capsule())

            Text(rec.title.isEmpty
                 ? (rec.photoFileNames.count >= 2 ? "\(rec.photoFileNames.count) 張照片" : rec.category.rawValue)
                 : rec.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(formatRowDate(rec.date))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 120)
    }

    // MARK: - 定期支出列（38pt 藍色漸層圖示圓 + 月均輔助）

    private func fixedExpenseRow(_ fe: VehicleFixedExpense, index: Int) -> some View {
        let color = Color.blue
        let icon = fixedCategoryIcon(fe.category)
        let periodLabel = fe.period == .monthly ? "每月" : "每年"
        let monthlyEquiv = fe.period.toMonthly(fe.amount)

        return HStack(spacing: 12) {
            // v2：升圓形 + stroke 邊框（對齊全 App 標準圓形圖示圓規格）
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.22), color.opacity(0.09)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                    .overlay(Circle().stroke(color.opacity(0.20), lineWidth: 0.75))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(fe.category.rawValue)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(periodLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(color.opacity(0.10))
                        .foregroundStyle(color)
                        .clipShape(Capsule())
                    if fe.period == .yearly {
                        Text("月均 " + fmt(monthlyEquiv))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 4)

            // v2：金額升為 accent 顏色，讓分類色貫穿整列
            Text(fmt(fe.amount))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 變動支出列（38pt 橘色漸層圖示圓 + 日期膠囊）

    private func variableExpenseRow(_ ve: VehicleVariableExpense, index: Int) -> some View {
        let color = Color.orange

        return HStack(spacing: 12) {
            // v2：升圓形 + stroke 邊框（對齊全 App 標準圓形圖示圓規格）
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.22), color.opacity(0.09)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                    .overlay(Circle().stroke(color.opacity(0.20), lineWidth: 0.75))
                Image(systemName: ve.category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(ve.category.rawValue)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                // 日期膠囊
                Text(formatRowDate(ve.date))
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(color.opacity(0.10))
                    .foregroundStyle(color.opacity(0.85))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 4)

            // v2：金額升為 accent 顏色，讓分類色貫穿整列
            Text(fmt(ve.amount))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - v2：KPI 摘要橫列（月固定 / 近12月變動 / 持有年限）

    private var vehicleKpiStrip: some View {
        let monthlyFixed = vehicle.fixedExpenses.reduce(0.0) { $0 + $1.period.toMonthly($1.amount) }
        let twelveMonthsAgo = Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? Date()
        let recentVariable = vehicle.variableExpenses
            .filter { $0.date >= twelveMonthsAgo }
            .reduce(0.0) { $0 + $1.amount }

        return HStack(spacing: 0) {
            vehicleKpiCell(icon: "calendar.badge.clock", label: "月固定支出",
                           value: fmt(monthlyFixed), color: .blue)
            Rectangle()
                .fill(Color(.separator).opacity(0.3))
                .frame(width: 0.5, height: 28)
            vehicleKpiCell(icon: "cart.circle.fill", label: "近12月變動",
                           value: fmt(recentVariable), color: .orange)
            Rectangle()
                .fill(Color(.separator).opacity(0.3))
                .frame(width: 0.5, height: 28)
            vehicleKpiCell(icon: "clock.fill", label: "持有",
                           value: String(format: "%.1f 年", vehicle.yearsOwned), color: .green)
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal, 24)
    }

    private func vehicleKpiCell(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            // 30pt 漸層圖示圓（對齊 statsStrip 規格）
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [color.opacity(0.22), color.opacity(0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(color.opacity(0.20), lineWidth: 0.75))
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - v3：空狀態（定期／變動支出皆無記錄時顯示）

    /// 對齊 StockDetailView 交易/股利空狀態卡規格：漸層圖示圓 + 標題 + 說明文字
    private var emptyExpensesCard: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.blue.opacity(0.15), Color.blue.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 40, height: 40)
                Circle()
                    .stroke(Color.blue.opacity(0.18), lineWidth: 0.75)
                    .frame(width: 40, height: 40)
                Image(systemName: "fuelpump.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.blue.opacity(0.65))
            }
            Text("尚無支出記錄")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("點右上角「編輯」新增定期或變動支出")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    // MARK: - 輔助

    /// 美化升級：Capsule 色條 + subheadline.bold + 計數膠囊
    private func sectionHeader(_ title: String, color: Color, count: Int) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 16)
            Text(title)
                .font(.subheadline.weight(.bold))
            Spacer()
            Text("\(count) 筆")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(color.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.6))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func fixedCategoryIcon(_ cat: VehicleFixedCategory) -> String {
        switch cat {
        case .carLoan:     return "creditcard.fill"
        case .tax:         return "doc.text.fill"
        case .subscription: return "repeat.circle.fill"
        }
    }

    private static let rowDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    private func formatRowDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今日" }
        if cal.isDateInYesterday(date) { return "昨天" }
        return Self.rowDateFormatter.string(from: date)
    }

    private func deleteVehicle() {
        // 先收集所有連結支出 ID，最後一次 removeAll 完成，
        // 對齊 RealEstateView.deleteEstate v20.5 修復規格，
        // 避免逐筆呼叫各自觸發 @Published didSet → save() + pushAll()
        var linkedIds = Set<UUID>()
        for fe in vehicle.fixedExpenses {
            if let id = fe.linkedExpenseId { linkedIds.insert(id) }
        }
        for ve in vehicle.variableExpenses {
            if let id = ve.linkedExpenseId { linkedIds.insert(id) }
        }
        if !linkedIds.isEmpty {
            for exp in expenseStore.expenses where linkedIds.contains(exp.id) {
                for name in exp.photoFileNames { Expense.deletePhoto(name) }
            }
            expenseStore.expenses.removeAll { linkedIds.contains($0.id) }
        }
        store.deleteVehicle(vehicle)
    }

    private func fmt(_ v: Double) -> String {
        v.ntdWanString
    }

    /// v4：從共用 ntdWanString 拆出「數字」與「萬／億」量級單位，供大字估值沿用既有字級／
    /// 動畫設計；跟進 ntdWanString 既有的萬→億進位邊界，取代僅換算到萬的舊版 fmtWan。
    private func splitWan(_ v: Double) -> (number: String, unit: String) {
        var s = v.ntdWanString
        if s.hasPrefix("NT$") { s.removeFirst(3) }
        if s.hasSuffix("億") { return (String(s.dropLast()), "億") }
        if s.hasSuffix("萬") { return (String(s.dropLast()), "萬") }
        return (s, "")
    }

    /// v4：「數字 單位」單行組字（無單位時省略空格），供底部資訊列等窄欄位使用。
    private func splitWanLabel(_ v: Double) -> String {
        let parts = splitWan(v)
        return parts.unit.isEmpty ? parts.number : "\(parts.number) \(parts.unit)"
    }
}

// MARK: - 車輛照片紀錄編輯器（支援多張照片，結構比照 RenovationPhotoEditor）

struct VehiclePhotoEditor: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss

    let vehicleId: UUID
    let editing: VehiclePhotoRecord?

    @State private var date: Date = Date()
    @State private var category: VehiclePhotoCategory = .maintenance
    @State private var title: String = ""
    @State private var note: String = ""
    @State private var photoFileNames: [String] = []
    @State private var showDeleteConfirm: Bool = false
    // 防止「儲存」連點：save() 把寫回 store 延後到下個 runloop，連點兩下會讀到同一份
    // vehicle 快照、各自 append，後寫者蓋掉前者（同型防護見 RenovationPhotoEditor.isSaving）
    @State private var isSaving: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    Picker("類別", selection: $category) {
                        ForEach(VehiclePhotoCategory.allCases) { c in
                            Label(c.rawValue, systemImage: c.icon).tag(c)
                        }
                    }
                    TextField("標題（例：五萬公里保養、牌照稅）", text: $title)
                } header: {
                    vehSectionHeader("基本資訊", icon: "calendar.circle.fill",
                                     gradient: [Color.teal, Color.teal.opacity(0.55)])
                }

                Section {
                    MultiPhotoGallery(
                        fileNames: $photoFileNames,
                        urlFor: { VehiclePhotoRecord.photoURL(for: $0) },
                        onSaveImage: { data in
                            VehiclePhotoRecord.savePhoto(data, id: UUID())
                        },
                        onDeleteFile: { name in
                            VehiclePhotoRecord.deletePhoto(name)
                        },
                        title: "照片"
                    )
                    .padding(.vertical, 4)
                } header: {
                    // 純文字標題：裝飾（標題／計數）由 MultiPhotoGallery 內建 header 負責，
                    // 這裡疊加會重複顯示（同型取捨見 RenovationPhotoEditor 照片 Section 註解）
                    Text("照片")
                } footer: {
                    Text("可拍照或從相簿一次選多張：保養單據、稅費收據、保險文件、事故照片等。")
                }

                Section {
                    TextField("選填備註（例：保養廠、金額、里程數）", text: $note, axis: .vertical).lineLimit(3)
                } header: {
                    vehSectionHeader("備註", icon: "note.text",
                                     gradient: [Color(.systemGray2), Color(.systemGray3)])
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("刪除此筆", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "新增照片紀錄" : "編輯照片紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { cancel() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(photoFileNames.isEmpty || isSaving)
                }
            }
            .alert("確定刪除？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) { deleteRecord() }
                Button("取消", role: .cancel) {}
            }
            .onAppear { setupInitial() }
        }
    }

    /// 統一 Section header（4pt Capsule 漸層色條 + 彩色圖示 + .subheadline.bold）
    private func vehSectionHeader(_ title: String, icon: String, gradient: [Color]) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(gradient.first ?? Color(.systemGray))
            Text(title)
                .font(.subheadline.weight(.bold))
        }
    }

    private func setupInitial() {
        if let e = editing {
            date = e.date
            category = e.category
            title = e.title
            note = e.note
            photoFileNames = e.photoFileNames
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard var vehicle = store.vehicles.first(where: { $0.id == vehicleId }) else { return }
        isSaving = true
        let recordId = editing?.id ?? UUID()

        let record = VehiclePhotoRecord(
            id: recordId,
            date: date,
            category: category,
            title: title.trimmingCharacters(in: .whitespaces),
            photoFileNames: photoFileNames,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        if let idx = vehicle.photoRecords.firstIndex(where: { $0.id == recordId }) {
            vehicle.photoRecords[idx] = record
        } else {
            vehicle.photoRecords.append(record)
        }
        // 先關 sheet、下個 runloop 才改 @Published store：避免在關閉 sheet 的
        // view-update 交易裡同步改 observed state 造成真機閃退（同型見 RenovationPhotoEditor.save）
        let financeStore = store
        dismiss()
        DispatchQueue.main.async { financeStore.update(vehicle) }
    }

    /// 取消：清掉本次 session 新增、尚未存檔的照片檔；編輯模式下若刪了原有照片，
    /// 回寫 store 收斂檔名，避免孤兒引用（完整理由見 RenovationPhotoEditor.cancel 註解）
    private func cancel() {
        let original = Set(editing?.photoFileNames ?? [])
        for name in photoFileNames where !original.contains(name) {
            VehiclePhotoRecord.deletePhoto(name)
        }
        let remaining = photoFileNames.filter { original.contains($0) }
        if let e = editing, Set(remaining) != original,
           var vehicle = store.vehicles.first(where: { $0.id == vehicleId }),
           let idx = vehicle.photoRecords.firstIndex(where: { $0.id == e.id }) {
            vehicle.photoRecords[idx].photoFileNames = remaining
            let financeStore = store
            dismiss()
            DispatchQueue.main.async { financeStore.update(vehicle) }
            return
        }
        dismiss()
    }

    private func deleteRecord() {
        guard var vehicle = store.vehicles.first(where: { $0.id == vehicleId }),
              let e = editing else { return }
        // 刪畫面上即時的 photoFileNames 而非進場快照，避免漏刪編輯中新增的照片
        //（同型理由見 RenovationPhotoEditor.deleteRecord 註解）
        for name in photoFileNames {
            VehiclePhotoRecord.deletePhoto(name)
        }
        vehicle.photoRecords.removeAll { $0.id == e.id }
        let financeStore = store
        dismiss()
        DispatchQueue.main.async { financeStore.update(vehicle) }
    }
}

// MARK: - 車輛項目參照（點開定期/變動支出列的詳情用）

fileprivate enum VehicleItemRef: Identifiable {
    case fixed(VehicleFixedExpense)
    case variable(VehicleVariableExpense)

    var id: UUID {
        switch self {
        case .fixed(let f): return f.id
        case .variable(let v): return v.id
        }
    }
}

// MARK: - 車輛項目詳情（分類/金額/週期＋連結支出資訊，右上「編輯」開啟連結支出）

fileprivate struct VehicleItemDetailSheet: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let vehicleId: UUID
    let item: VehicleItemRef

    @State private var editingExpense: Expense?
    @State private var showPremiumAlert = false
    @State private var cuteDraft: CutePhotoDraft?

    /// 每次 body 重算都從 store 取最新版本：右上「編輯」存檔回來後畫面立即反映
    private var currentItem: VehicleItemRef {
        guard let v = store.vehicles.first(where: { $0.id == vehicleId }) else { return item }
        switch item {
        case .fixed(let f):
            return v.fixedExpenses.first(where: { $0.id == f.id }).map { .fixed($0) } ?? item
        case .variable(let vr):
            return v.variableExpenses.first(where: { $0.id == vr.id }).map { .variable($0) } ?? item
        }
    }

    private var linkedExpense: Expense? {
        let linkedId: UUID?
        switch currentItem {
        case .fixed(let f): linkedId = f.linkedExpenseId
        case .variable(let v): linkedId = v.linkedExpenseId
        }
        guard let linkedId else { return nil }
        return expenseStore.expenses.first(where: { $0.id == linkedId })
    }

    private var navTitle: String {
        switch currentItem {
        case .fixed(let f): return f.category.rawValue
        case .variable(let v): return v.category.rawValue
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch currentItem {
                case .fixed(let fe):
                    Section("項目資訊") {
                        infoRow("分類", fe.category.rawValue)
                        infoRow("金額", fe.amount.ntdWanString)
                        infoRow("週期", fe.period == .monthly ? "每月" : "每年")
                        if fe.period == .yearly {
                            infoRow("月均", fe.period.toMonthly(fe.amount).ntdWanString)
                        }
                    }
                case .variable(let ve):
                    Section("項目資訊") {
                        infoRow("分類", ve.category.rawValue)
                        infoRow("金額", ve.amount.ntdWanString)
                        infoRow("日期", Self.dateFmt.string(from: ve.date))
                    }
                }

                if let exp = linkedExpense {
                    Section("連結記帳支出") {
                        infoRow("名稱", exp.title.isEmpty ? "—" : exp.title)
                        if !exp.note.trimmingCharacters(in: .whitespaces).isEmpty {
                            infoRow("備註", exp.note)
                        }
                        infoRow("日期", Self.dateFmt.string(from: exp.date))
                        if !exp.photoFileNames.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(exp.photoFileNames, id: \.self) { name in
                                        Button {
                                            cuteDraft = CutePhotoDraft(
                                                urls: exp.photoFileNames.map { Expense.photoURL(for: $0) },
                                                title: exp.title.isEmpty ? "支出照片" : exp.title,
                                                note: exp.note,
                                                date: exp.date,
                                                kind: .expense
                                            )
                                        } label: {
                                            ThumbnailImageView(url: Expense.photoURL(for: name))
                                                .frame(width: 72, height: 72)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } else {
                    Section {
                        Text("此項目未連結記帳支出；金額與分類可在車輛卡片右上「編輯」畫面調整。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                if let exp = linkedExpense {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("編輯") {
                            if subscription.isPremium { editingExpense = exp }
                            else { showPremiumAlert = true }
                        }
                        .bold().foregroundStyle(.green)
                    }
                }
            }
            .sheet(item: $editingExpense) { exp in
                AddExpenseView(expenseType: exp.expenseType, editingExpense: exp)
            }
            .sheet(item: $cuteDraft) { draft in
                CutePhotoViewer(draft: draft)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
    }
}
