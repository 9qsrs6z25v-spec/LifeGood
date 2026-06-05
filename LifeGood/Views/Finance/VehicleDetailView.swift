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
// [2026-06] 本次美化方向：
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
    // 美化：進場動畫旗標（對齊 StockDetailView / RealEstateDetailView 規格）
    @State private var cardAppeared = false
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
                    infoSection
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

                if !vehicle.brand.isEmpty {
                    Text(vehicle.brand)
                        .font(.subheadline)
                        .foregroundStyle(rarity == .legendary ? .white.opacity(0.7) : .secondary)
                }
            }
            .padding(.top, 16)

            // 估值（大字）
            VStack(spacing: 4) {
                Text("\(fmtWan(vehicle.currentValue))")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(rarity.textColor)
                Text("萬元")
                    .font(.subheadline)
                    .foregroundStyle(rarity == .legendary ? .white.opacity(0.6) : .secondary)
            }
            .padding(.vertical, 20)

            // 底部資訊列
            HStack {
                VStack(spacing: 2) {
                    Text("購入")
                        .font(.caption2).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text("\(fmtWan(vehicle.purchasePrice)) 萬")
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
            LinearGradient(colors: rarity.bgGradient,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
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
            // 定期支出卡片
            if !vehicle.fixedExpenses.isEmpty {
                VStack(spacing: 0) {
                    sectionHeader("定期支出", color: .blue, count: vehicle.fixedExpenses.count)
                    ForEach(Array(vehicle.fixedExpenses.enumerated()), id: \.element.id) { idx, fe in
                        fixedExpenseRow(fe, index: idx)
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
                        variableExpenseRow(ve, index: idx + offset)
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

    // MARK: - 定期支出列（38pt 藍色漸層圖示圓 + 月均輔助）

    private func fixedExpenseRow(_ fe: VehicleFixedExpense, index: Int) -> some View {
        let color = Color.blue
        let icon = fixedCategoryIcon(fe.category)
        let periodLabel = fe.period == .monthly ? "每月" : "每年"
        let monthlyEquiv = fe.period.toMonthly(fe.amount)

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.22), color.opacity(0.09)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
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

            Text(fmt(fe.amount))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
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
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.22), color.opacity(0.09)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
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

            Text(fmt(ve.amount))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
        for fe in vehicle.fixedExpenses {
            if let linkedId = fe.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == linkedId }
            }
        }
        for ve in vehicle.variableExpenses {
            if let linkedId = ve.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == linkedId }
            }
        }
        store.deleteVehicle(vehicle)
    }

    private func fmt(_ v: Double) -> String {
        v.ntdWanString
    }

    private func fmtWan(_ v: Double) -> String {
        String(format: "%g", v / 10000)
    }
}
