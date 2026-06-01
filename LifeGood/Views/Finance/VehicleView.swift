import SwiftUI

// MARK: - 美化紀錄（VehicleView）
// [2026-06] 本次美化方向：
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

struct VehicleView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var editingItem: Vehicle?
    @State private var viewingItem: Vehicle?
    @State private var sortOption: VehicleSortOption = .purchasePrice
    @State private var sortAscending = false
    @State private var depreciationEnabled = false
    @State private var showPremiumAlert = false
    @State private var headerAppeared = false
    @State private var cardsAppeared = false
    @State private var emptyIconPulse = false

    private let heroAccent    = Color(red: 0.18, green: 0.68, blue: 0.68)
    private let heroAccentDark = Color(red: 0.08, green: 0.46, blue: 0.48)

    private var sortedVehicles: [Vehicle] {
        store.vehicles.sorted { a, b in
            let result: Bool
            switch sortOption {
            case .purchasePrice: result = a.purchasePrice > b.purchasePrice
            case .currentValue: result = a.currentValue > b.currentValue
            case .depreciationRate: result = a.depreciationRate > b.depreciationRate
            case .yearsOwned: result = a.yearsOwned > b.yearsOwned
            case .monthlyExpense: result = a.monthlyExpense > b.monthlyExpense
            }
            return sortAscending ? !result : result
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // 英雄摘要卡片嵌入 List，與列表一起捲動
                Section {
                    summaryHeader
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
                    Section {
                        ForEach(Array(sortedVehicles.enumerated()), id: \.element.id) { idx, item in
                            vehicleCard(item)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 18)
                                .animation(
                                    .spring(response: 0.45, dampingFraction: 0.82)
                                        .delay(0.05 * Double(idx)),
                                    value: cardsAppeared
                                )
                                .onTapGesture { viewingItem = item }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        guard subscription.isPremium else {
                                            showPremiumAlert = true
                                            return
                                        }
                                        for fe in item.fixedExpenses {
                                            if let linkedId = fe.linkedExpenseId {
                                                expenseStore.expenses.removeAll { $0.id == linkedId }
                                            }
                                        }
                                        for ve in item.variableExpenses {
                                            if let linkedId = ve.linkedExpenseId {
                                                expenseStore.expenses.removeAll { $0.id == linkedId }
                                            }
                                        }
                                        store.deleteVehicle(item)
                                    } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .onAppear {
                        withAnimation(.spring(response: 0.50, dampingFraction: 0.82).delay(0.08)) {
                            cardsAppeared = true
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
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
            .sheet(isPresented: $showAdd) { AddVehicleView() }
            .sheet(item: $viewingItem) { item in VehicleDetailView(vehicle: item) }
            .sheet(item: $editingItem) { item in AddVehicleView(editing: item) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        depreciationEnabled.toggle()
                        if depreciationEnabled { applyDepreciation() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: depreciationEnabled ? "arrow.down.right.circle.fill" : "arrow.down.right.circle")
                                .foregroundStyle(depreciationEnabled ? .orange : .secondary)
                            Text("折舊開關")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(depreciationEnabled ? .orange : .secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 英雄摘要卡片

    private var summaryHeader: some View {
        let totalValue = store.totalVehicleValue
        let totalCost = store.vehicles.reduce(0.0) { $0 + $1.purchasePrice }
        let monthly = store.vehicles.reduce(0.0) { $0 + $1.monthlyExpense }
        let count = store.vehicles.count
        let depreciationLoss = totalCost - totalValue

        return VStack(spacing: 0) {
            // 頂部：總估值 + 車輛計數膠囊
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("車輛總估值")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                    Text(fmtShort(totalValue))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    if totalValue > 0 {
                        Text("購入成本 \(fmtShort(totalCost))")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.top, 1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    // 車輛計數膠囊
                    Text("\(count) 輛")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.22))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)

                    // 折舊損失 KPI 膠囊（有資料時顯示）
                    if depreciationLoss > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.right")
                                .font(.system(size: 9, weight: .bold))
                            Text("-\(fmtShort(depreciationLoss))")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.75))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(0.18))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.75))
                    }
                }
            }

            // KPI 橫列：購入成本 / 月養車費
            HStack(spacing: 0) {
                kpiCell(label: "折舊估損", value: depreciationLoss > 0 ? "-\(fmtShort(depreciationLoss))" : "—")
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 28)
                kpiCell(label: "月養車費", value: monthly > 0 ? fmt(monthly) : "—")
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 28)
                kpiCell(label: "持有輛數", value: "\(count) 輛")
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            ZStack {
                LinearGradient(
                    colors: [heroAccent, heroAccentDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 右上主散景圓
                Circle()
                    .fill(.white.opacity(0.13))
                    .frame(width: 130, height: 130)
                    .offset(x: 85, y: -50)
                    .blur(radius: 14)
                // 左下次散景圓
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 75, height: 75)
                    .offset(x: -65, y: 45)
                    .blur(radius: 9)
                // 右下微光
                Circle()
                    .fill(.white.opacity(0.05))
                    .frame(width: 55, height: 55)
                    .offset(x: 95, y: 40)
                    .blur(radius: 10)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: heroAccentDark.opacity(0.42), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func kpiCell(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    emptyIconPulse = true
                }
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

    // MARK: - 車輛卡片

    private func vehicleCard(_ item: Vehicle) -> some View {
        let powerColor: Color = item.powerType == .electric ? .green :
                                item.powerType == .hybrid   ? .blue  : .orange

        return HStack(spacing: 0) {
            // 左側 4pt teal 漸層強調條
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [heroAccent, heroAccent.opacity(0.40)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.trailing, 14)

            VStack(alignment: .leading, spacing: 10) {
                // ① 頂部：圖示圓 + 名稱 + 品牌/燃料膠囊
                HStack(spacing: 12) {
                    // 44pt 漸層圖示圓 + 陰影（對齊 ExpenseRow 規格）
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [heroAccent.opacity(0.22), heroAccent.opacity(0.09)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                            .shadow(color: heroAccent.opacity(0.22), radius: 6, x: 0, y: 3)
                        Image(systemName: "car.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(heroAccent)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        // 品牌 + 燃料類型膠囊標籤
                        HStack(spacing: 5) {
                            if !item.brand.isEmpty {
                                Text(item.brand)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(heroAccent)
                                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                                    .background(heroAccent.opacity(0.12))
                                    .clipShape(Capsule())
                                    .lineLimit(1)
                            }
                            HStack(spacing: 3) {
                                Image(systemName: item.powerType.icon)
                                    .font(.system(size: 9))
                                Text(item.powerType.rawValue)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(powerColor)
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(powerColor.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }

                    Spacer(minLength: 4)

                    // 右側：估值大字 + 折舊膠囊
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(fmtShort(item.currentValue))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.right")
                                .font(.system(size: 8, weight: .bold))
                            Text(String(format: "%.1f%%", item.depreciationRate))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(red: 0.90, green: 0.25, blue: 0.25).opacity(0.10))
                        .clipShape(Capsule())
                    }
                }

                // ② 分隔線
                Rectangle()
                    .fill(Color(.separator).opacity(0.20))
                    .frame(height: 0.5)

                // ③ 定期支出明細（精簡 Capsule 標籤）
                if !item.fixedExpenses.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(item.fixedExpenses) { fe in
                            HStack {
                                HStack(spacing: 4) {
                                    Text(fe.category.rawValue)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.10))
                                        .clipShape(Capsule())
                                    Text(fe.period == .monthly ? "每月" : "每年")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Text(fmt(fe.amount))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }

                // ④ 變動支出明細（最近 3 筆）
                if !item.variableExpenses.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(item.variableExpenses.suffix(3)) { ve in
                            HStack {
                                Text(ve.category.rawValue)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.10))
                                    .clipShape(Capsule())
                                Spacer()
                                Text(fmt(ve.amount))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                            }
                        }
                        if item.variableExpenses.count > 3 {
                            Text("還有 \(item.variableExpenses.count - 3) 筆...")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }

                // ⑤ 底部：購入成本 + 持有年數 + 月費合計
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "tag")
                            .font(.system(size: 10))
                        Text("購入 \(fmtShort(item.purchasePrice))")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    Text("·")
                        .font(.caption2).foregroundStyle(.tertiary)

                    Text(String(format: "持有 %.1f 年", item.yearsOwned))
                        .font(.caption2).foregroundStyle(.secondary)

                    Spacer()

                    let totalVar = item.variableTotal
                    if item.monthlyExpense > 0 || totalVar > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "creditcard")
                                .font(.system(size: 9))
                            Text(item.monthlyExpense > 0 ? "月費 \(fmt(item.monthlyExpense))" : "變動 \(fmt(totalVar))")
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    AngularGradient(
                        colors: CardRarity(price: item.purchasePrice).borderGradient,
                        center: .center
                    ),
                    lineWidth: CardRarity(price: item.purchasePrice).borderWidth
                )
        )
        .shadow(color: CardRarity(price: item.purchasePrice).shadowColor, radius: 6, y: 2)
        .overlay(alignment: .topLeading) {
            if item.isSold {
                SoldStamp(size: 16)
                    .offset(x: -8, y: -8)
            }
        }
    }

    // MARK: - 折舊計算

    private func applyDepreciation() {
        var updated = store.vehicles
        for i in updated.indices {
            let v = updated[i]
            guard !v.isSold, v.purchasePrice > 0 else { continue }
            let depreciated = v.purchasePrice * pow(1 - 0.15, v.yearsOwned)
            updated[i].currentValue = max(0, (depreciated / 10000).rounded() * 10000)
        }
        store.vehicles = updated
    }

    // MARK: - Helpers

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    private func fmtShort(_ v: Double) -> String {
        if v >= 100_000_000 { return String(format: "%.1f億", v / 100_000_000) }
        if v >= 10_000 { return String(format: "NT$%.0f萬", v / 10_000) }
        return fmt(v)
    }
}
