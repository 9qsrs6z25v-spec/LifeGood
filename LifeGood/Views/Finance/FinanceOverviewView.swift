import SwiftUI

struct FinanceOverviewView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAddVariable = false
    @State private var showAddFixed = false
    @State private var showAddStock = false
    @State private var showAddRealEstate = false
    @State private var showPremiumAlert = false
    @State private var appearedCards: Set<String> = []
    @State private var allocationBarAppeared = false
    @State private var allocationRowsAppeared = false

    private func rateForCode(_ code: String) -> Double {
        if code == "NT$" { return 1 }
        return expenseStore.currencyRates.first(where: { $0.code == code })?.rate ?? 1
    }

    private var insuranceValueNTD: Double {
        store.insurances.reduce(0) { $0 + $1.currentValue * rateForCode($1.currencyCode) }
    }

    private var insurancePaidNTD: Double {
        store.insurances.reduce(0) { $0 + $1.totalPaid * rateForCode($1.currencyCode) }
    }

    private var insuranceProfitLoss: Double {
        insuranceValueNTD - insurancePaidNTD
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    totalAssetsCard
                        .padding(.horizontal)
                        .opacity(appearedCards.contains("total") ? 1 : 0)
                        .offset(y: appearedCards.contains("total") ? 0 : 20)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                _ = appearedCards.insert("total")
                            }
                        }

                    assetCards
                    allocationSection
                    cashFlowSection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("理財總覽")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    quickAddMenu
                }
            }
            .sheet(isPresented: $showAddVariable) { AddExpenseView(expenseType: .variable) }
            .sheet(isPresented: $showAddFixed) { AddExpenseView(expenseType: .fixed) }
            .sheet(isPresented: $showAddStock) { AddStockView() }
            .sheet(isPresented: $showAddRealEstate) { AddRealEstateView() }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    private func gated(_ action: () -> Void) {
        if subscription.isPremium { action() } else { showPremiumAlert = true }
    }

    private var quickAddMenu: some View {
        Menu {
            Button { showAddVariable = true } label: { Label("變動支出", systemImage: "arrow.up.arrow.down.circle.fill") }
            Button { showAddFixed = true } label: { Label("固定支出", systemImage: "pin.circle.fill") }
            Button { showAddStock = true } label: { Label("股票", systemImage: "chart.line.uptrend.xyaxis") }
            Button {
                gated { showAddRealEstate = true }
            } label: { Label("房地產", systemImage: "building.2.fill") }
        } label: {
            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
        }
    }

    private var totalAssetsNTD: Double {
        insuranceValueNTD + store.totalStockValue + store.totalVehicleValue + store.totalRealEstateValue
    }

    private var totalAssetCount: Int {
        store.insurances.count + store.stocks.count + store.vehicles.count +
        store.realEstates.filter { !$0.isSold }.count
    }

    // MARK: - 總資產卡片
    // 【美化方向 — totalAssetsCard】
    // ① 右側：取代裝飾圖示，改為「投資損益」KPI 膠囊（股票+儲蓄險合計），
    //    正值顯示↑綠色、負值顯示↓紅色，資訊密度與 IncomeView hero card 保持均值。
    // ② 頂部左側：「N 項資產」改為白色細框膠囊，視覺重量更平衡。
    // ③ 底部：加分隔線 + mini 資產配置彩條，讓用戶一眼看出資產結構分布，
    //    色彩邏輯與下方 allocationSection 的橫向彩條完全對應。

    private var totalInvestmentPL: Double { insuranceProfitLoss + stockProfitLoss }

    private var totalAssetsCard: some View {
        let pl = totalInvestmentPL
        let allocations = ntdAllocations

        return VStack(spacing: 0) {
            // 頂部：總資產 + 損益 KPI
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("總資產")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                    Text(fmt(totalAssetsNTD))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    // 項目計數膠囊
                    Text("\(totalAssetCount) 項資產")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.20))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                        .padding(.top, 1)
                }
                Spacer()
                // 投資損益 KPI（股票 + 儲蓄險）
                if store.stocks.count > 0 || store.insurances.count > 0 {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("投資損益")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                        HStack(spacing: 3) {
                            Image(systemName: pl >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text((pl >= 0 ? "+" : "") + fmtShort(pl))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(pl >= 0 ? Color(red: 0.60, green: 1.00, blue: 0.75) : Color(red: 1.0, green: 0.78, blue: 0.75))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.18))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(pl >= 0 ? 0.35 : 0.25), lineWidth: 0.75))
                    }
                }
            }

            // mini 資產配置彩條：分隔線 + 比例彩條 + 圖例
            if !allocations.isEmpty {
                Rectangle()
                    .fill(.white.opacity(0.20))
                    .frame(height: 0.5)
                    .padding(.vertical, 14)

                VStack(spacing: 6) {
                    // 比例彩條
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(allocations) { a in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(colorFor(a.type).opacity(0.90))
                                    .frame(
                                        width: max(3, CGFloat(a.percentage / 100) *
                                                   (geo.size.width - CGFloat(max(0, allocations.count - 1)) * 2))
                                    )
                            }
                        }
                    }
                    .frame(height: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                    // 圖例膠囊橫排
                    HStack(spacing: 6) {
                        ForEach(allocations) { a in
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(colorFor(a.type))
                                    .frame(width: 5, height: 5)
                                Text(a.type.rawValue)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.80))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(20)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.14, green: 0.64, blue: 0.60),
                        Color(red: 0.07, green: 0.46, blue: 0.42)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(.white.opacity(0.13))
                    .frame(width: 140, height: 140)
                    .offset(x: 90, y: -55)
                    .blur(radius: 14)
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 90, height: 90)
                    .offset(x: -70, y: 55)
                    .blur(radius: 10)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.07, green: 0.46, blue: 0.42).opacity(0.42), radius: 18, x: 0, y: 9)
    }

    // MARK: - 資產類別卡片

    private var stockProfitLoss: Double { store.totalStockProfitLoss }

    private var assetCards: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                assetCard(title: "儲蓄險", amount: insuranceValueNTD,
                          profitLoss: insuranceProfitLoss,
                          icon: "shield.fill", color: .blue,
                          count: store.insurances.count, key: "insurance")
                assetCard(title: "股票", amount: store.totalStockValue,
                          profitLoss: stockProfitLoss,
                          icon: "chart.line.uptrend.xyaxis", color: .orange,
                          count: store.stocks.count, key: "stock")
            }
            HStack(spacing: 12) {
                assetCard(title: "汽車", amount: store.totalVehicleValue,
                          profitLoss: nil,
                          icon: "car.fill", color: .teal,
                          count: store.vehicles.count, key: "vehicle")
                assetCard(title: "房地產", amount: store.totalRealEstateValue,
                          profitLoss: nil,
                          icon: "building.2.fill", color: .purple,
                          count: store.realEstates.filter { !$0.isSold }.count, key: "realEstate")
            }
        }
        .padding(.horizontal)
    }

    private let assetCardDelays: [String: Double] = [
        "insurance": 0.06, "stock": 0.12, "vehicle": 0.18, "realEstate": 0.24
    ]

    private func assetCard(title: String, amount: Double, profitLoss: Double?,
                           icon: String, color: Color, count: Int, key: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 4)
                .padding(.bottom, 10)

            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(count) 筆")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 8)

            Text(fmtShort(amount))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .contentTransition(.numericText())

            if let pl = profitLoss {
                HStack(spacing: 3) {
                    Image(systemName: pl >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                    Text((pl >= 0 ? "+" : "") + fmtShort(pl))
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(pl >= 0 ? .green : .red)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(
            ZStack {
                Color(.systemBackground)
                color.opacity(0.04)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: color.opacity(0.13), radius: 10, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
        .opacity(appearedCards.contains(key) ? 1 : 0)
        .offset(y: appearedCards.contains(key) ? 0 : 18)
        .onAppear {
            let delay = assetCardDelays[key] ?? 0
            withAnimation(.spring(response: 0.50, dampingFraction: 0.78).delay(delay)) {
                _ = appearedCards.insert(key)
            }
        }
    }

    // MARK: - 資產配置

    private var ntdAllocations: [AssetAllocation] {
        let total = totalAssetsNTD
        guard total > 0 else { return [] }
        var result: [AssetAllocation] = []
        if insuranceValueNTD > 0 {
            result.append(AssetAllocation(type: .savingsInsurance, value: insuranceValueNTD,
                                          percentage: insuranceValueNTD / total * 100))
        }
        if store.totalStockValue > 0 {
            result.append(AssetAllocation(type: .stock, value: store.totalStockValue,
                                          percentage: store.totalStockValue / total * 100))
        }
        if store.totalVehicleValue > 0 {
            result.append(AssetAllocation(type: .vehicle, value: store.totalVehicleValue,
                                          percentage: store.totalVehicleValue / total * 100))
        }
        if store.totalRealEstateValue > 0 {
            result.append(AssetAllocation(type: .realEstate, value: store.totalRealEstateValue,
                                          percentage: store.totalRealEstateValue / total * 100))
        }
        return result.sorted { $0.value > $1.value }
    }

    private var allocationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .purple.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Text("資產配置")
                    .font(.subheadline.weight(.bold))
                Spacer()
            }
            .padding(.horizontal)

            let allocations = ntdAllocations
            if allocations.isEmpty {
                emptyPlaceholder(
                    icon: "chart.pie",
                    title: "尚無資產資料",
                    subtitle: "新增資產後顯示配置比例"
                )
                .padding(.horizontal)
            } else {
                // 橫向比例彩條（從左展開進場動畫）
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(allocations) { a in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(colorFor(a.type))
                                .frame(
                                    width: max(4, CGFloat(a.percentage / 100) *
                                               (geo.size.width - CGFloat(max(0, allocations.count - 1)) * 2))
                                )
                        }
                    }
                }
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .scaleEffect(x: allocationBarAppeared ? 1.0 : 0.04, y: 1, anchor: .leading)
                .animation(.spring(response: 0.78, dampingFraction: 0.82), value: allocationBarAppeared)
                .padding(.horizontal)

                // 各類別明細列（含圖示 + 漸層進度條 + 錯落進場）
                VStack(spacing: 0) {
                    ForEach(Array(allocations.enumerated()), id: \.element.id) { idx, a in
                        let color = colorFor(a.type)
                        let ratio = a.percentage / 100.0

                        VStack(spacing: 7) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(
                                            LinearGradient(
                                                colors: [color.opacity(0.22), color.opacity(0.09)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 30, height: 30)
                                    Image(systemName: iconFor(a.type))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(color)
                                }
                                Text(a.type.rawValue)
                                    .font(.subheadline)
                                Spacer()
                                Text(fmtShort(a.value))
                                    .font(.subheadline.bold())
                                    .contentTransition(.numericText())
                                Text(String(format: "%.1f%%", a.percentage))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(color)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(color.opacity(0.12))
                                    .clipShape(Capsule())
                            }

                            // 漸層進度條（帶延遲動畫）
                            GeometryReader { barGeo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color(.systemFill))
                                        .frame(height: 4)
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [color, color.opacity(0.55)],
                                                startPoint: .leading, endPoint: .trailing
                                            )
                                        )
                                        .frame(
                                            width: barGeo.size.width * (allocationBarAppeared ? ratio : 0),
                                            height: 4
                                        )
                                        .animation(
                                            .spring(response: 0.70, dampingFraction: 0.78)
                                                .delay(0.10 + 0.08 * Double(idx)),
                                            value: allocationBarAppeared
                                        )
                                }
                            }
                            .frame(height: 4)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .opacity(allocationRowsAppeared ? 1 : 0)
                        .offset(y: allocationRowsAppeared ? 0 : 14)
                        .animation(
                            .spring(response: 0.50, dampingFraction: 0.80)
                                .delay(0.06 * Double(idx)),
                            value: allocationRowsAppeared
                        )

                        if idx < allocations.count - 1 {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                .padding(.horizontal)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                allocationBarAppeared = true
            }
            withAnimation(.spring(response: 0.50, dampingFraction: 0.80).delay(0.18)) {
                allocationRowsAppeared = true
            }
        }
    }

    // MARK: - 每月現金流
    // 【美化方向 — cashFlowSection】
    // ① 淨現金流欄放大字體（.title3.bold），加入彩色背景膠囊，正負值一目了然。
    // ② 租金收入 / 房貸支出欄以圓角方塊替換純文字，圖示圓擴大到 38pt。
    // ③ 整體卡片加極細 overlay 邊框，提升精緻感與深色模式相容性。
    // ④ 若無房地產資料顯示空狀態提示，避免三欄全為零的空洞感。

    private var cashFlowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Text("每月現金流")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("房地產")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
            }
            .padding(.horizontal)

            let flow = store.monthlyCashFlow
            let income = store.monthlyRentalIncome
            let mortgage = store.monthlyMortgagePayment

            if income == 0 && mortgage == 0 {
                // 空狀態：無房地產現金流資料
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color(.systemFill))
                            .frame(width: 52, height: 52)
                        Image(systemName: "house.badge.questionmark")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                    Text("新增房地產後顯示月現金流")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                .padding(.horizontal)
            } else {
                HStack(spacing: 0) {
                    // 租金收入
                    cashFlowSideItem(label: "租金收入", value: income,
                                     icon: "house.fill", color: .green)

                    // 分隔線
                    Rectangle()
                        .fill(Color(.separator).opacity(0.28))
                        .frame(width: 0.5, height: 56)

                    // 房貸支出
                    cashFlowSideItem(label: "房貸支出", value: mortgage,
                                     icon: "building.columns.fill", color: .red)

                    // 分隔線
                    Rectangle()
                        .fill(Color(.separator).opacity(0.28))
                        .frame(width: 0.5, height: 56)

                    // 淨現金流（強調欄）
                    cashFlowNetItem(flow: flow)
                }
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
                .padding(.horizontal)
            }
        }
    }

    private func cashFlowSideItem(label: String, value: Double,
                                  icon: String, color: Color) -> some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.10))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(fmtShort(value))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func cashFlowNetItem(flow: Double) -> some View {
        let isPositive = flow >= 0
        let netColor: Color = isPositive ? .green : .red
        return VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(netColor.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: isPositive ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(netColor)
            }
            Text("淨現金流")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text((isPositive ? "+" : "") + fmtShort(flow))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(netColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(netColor.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(netColor.opacity(0.22), lineWidth: 0.6))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 空狀態

    private func emptyPlaceholder(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.systemFill))
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    // MARK: - Helpers

    private func colorFor(_ type: AssetType) -> Color {
        switch type {
        case .savingsInsurance: return .blue
        case .stock: return .orange
        case .vehicle: return .teal
        case .realEstate: return .purple
        }
    }

    private func iconFor(_ type: AssetType) -> String {
        switch type {
        case .savingsInsurance: return "shield.fill"
        case .stock: return "chart.line.uptrend.xyaxis"
        case .vehicle: return "car.fill"
        case .realEstate: return "building.2.fill"
        }
    }

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f
    }()

    private func fmt(_ v: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    private func fmtShort(_ v: Double) -> String {
        if v >= 100_000_000 { return String(format: "%.1f億", v / 100_000_000) }
        if v >= 10_000 { return String(format: "%.0f萬", v / 10_000) }
        return fmt(v)
    }
}
