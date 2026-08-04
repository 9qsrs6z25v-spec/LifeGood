import SwiftUI

// MARK: - 美化方向（v16.78）
// 本檔案已依照全站設計語言（參考 IncomeView / FixedExpenseView）完成視覺升級：
// 1. summaryHeader：純白卡片 → 藍色系漸層 Hero 卡（呼應 FinanceOverviewView 中「儲蓄險」代表色 .blue／shield.fill），
//    加入 bokeh 裝飾圓球、進場淡入 + 位移動畫，損益區塊改為白底半透明膠囊徽章。
// 2. insuranceCard：新增左側圓角圖示（shield.fill），標題字重提升、金額字級加大，
//    卡片圓角 12→14、陰影加強，與其他資產卡片（RealEstateView／StockView）階層感一致。
// 3. emptyState：改為漸層圓底 + 呼吸感光暈脈衝動畫，對齊 IncomeView 空狀態樣式。
// 4. fmtSmart：金額量級補上「億」門檻（沿用 RealEstateView 慣例：< 萬顯示元、萬~億顯示萬、≥ 億顯示億）。
// 5. 商業邏輯（幣別分組、損益試算、新增/刪除/付費鎖）完全未變動。
// 下次美化其他頁面時，可比照本檔案的 Hero 卡 + 圖示卡 + 呼吸空狀態 三段式作為基準模板。
struct SavingsInsuranceView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var editingItem: SavingsInsurance?
    @State private var showPremiumAlert = false
    @State private var headerAppeared = false
    @State private var emptyIconPulse = false

    private let accent = Color(red: 0.20, green: 0.47, blue: 0.93)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader
                    .opacity(headerAppeared ? 1 : 0)
                    .offset(y: headerAppeared ? 0 : 16)
                    .onAppear {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                            headerAppeared = true
                        }
                    }

                if store.insurances.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.insurances) { item in
                            insuranceCard(item)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .onTapGesture {
                                    if subscription.isPremium { editingItem = item }
                                    else { showPremiumAlert = true }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        if subscription.isPremium {
                                            if let linkedId = item.linkedExpenseId {
                                                expenseStore.expenses.removeAll { $0.id == linkedId }
                                            }
                                            store.deleteInsurance(item)
                                        } else {
                                            showPremiumAlert = true
                                        }
                                    } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .background(Color(.systemGroupedBackground))
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("儲蓄險")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if subscription.isPremium { showAdd = true }
                        else { showPremiumAlert = true }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(accent)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddSavingsInsuranceView() }
            .sheet(item: $editingItem) { item in AddSavingsInsuranceView(editing: item) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    // MARK: - 摘要（Hero 漸層卡）

    private var summaryHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Label("保單總覽", systemImage: "shield.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text("\(store.insurances.count) 張保單")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.18))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            }

            // 依幣別分組顯示（商業邏輯未變動）
            let grouped = Dictionary(grouping: store.insurances, by: { $0.currencyCode })
            let codes = grouped.keys.sorted { a, b in
                if a == "NT$" { return true }
                if b == "NT$" { return false }
                return a < b
            }
            ForEach(codes, id: \.self) { code in
                if let items = grouped[code], !items.isEmpty {
                    let totalCurrent = items.reduce(0) { $0 + $1.currentValue }
                    let totalPaid = items.reduce(0) { $0 + $1.totalPaid }
                    let gain = totalCurrent - totalPaid
                    let gainRate = totalPaid > 0 ? gain / totalPaid * 100 : 0

                    VStack(spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("目前價值 (\(code))")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.75))
                                Text(fmtSmart(totalCurrent, code: code))
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                                    .contentTransition(.numericText())
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("已繳總額")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.75))
                                Text(fmtSmart(totalPaid, code: code))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                            }
                        }

                        HStack {
                            let isPositive = gain >= 0
                            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption.weight(.bold))
                            Text((isPositive ? "+" : "") + fmtSmart(gain, code: code))
                                .font(.caption.weight(.bold))
                            Text(String(format: "(%@%.2f%%)", isPositive ? "+" : "", gainRate))
                                .font(.caption2)
                            Spacer()
                        }
                        .foregroundStyle(isPositive ? Color(red: 0.72, green: 1.0, blue: 0.80) : Color(red: 1.0, green: 0.80, blue: 0.76))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(.top, codes.first == code ? 0 : 4)

                    if code != codes.last {
                        Rectangle()
                            .fill(.white.opacity(0.16))
                            .frame(height: 0.5)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.24, green: 0.50, blue: 0.95),
                        Color(red: 0.13, green: 0.28, blue: 0.68)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 130, height: 130)
                    .offset(x: 100, y: -50)
                    .blur(radius: 14)
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 80, height: 80)
                    .offset(x: -80, y: 60)
                    .blur(radius: 10)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.13, green: 0.28, blue: 0.68).opacity(0.35), radius: 14, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - 空狀態（呼吸光暈）

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.25), lineWidth: 1.5)
                    .frame(width: 100, height: 100)
                    .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.14), accent.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 82, height: 82)
                    .overlay(Circle().stroke(accent.opacity(0.20), lineWidth: 1.2))
                Image(systemName: "shield")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(accent.opacity(0.75))
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    emptyIconPulse = true
                }
            }

            VStack(spacing: 8) {
                Text("尚無儲蓄險紀錄")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.65))
                Text("點擊右上角 + 新增保單")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 保單卡片

    private func insuranceCard(_ item: SavingsInsurance) -> some View {
        let isNT = item.currencyCode == "NT$"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.85), accent.opacity(0.55)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: "shield.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                }
                .shadow(color: accent.opacity(0.35), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(item.currencyCode)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(isNT ? Color.green.opacity(0.12) : Color.blue.opacity(0.12))
                            .foregroundStyle(isNT ? .green : .blue)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if !item.company.isEmpty {
                        Text(item.company).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(fmtSmart(item.currentValue, code: item.currencyCode))
                        .font(.subheadline.bold())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("目前價值").font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Divider()

            HStack {
                Label(item.paymentPeriod.rawValue + " " + fmtSmart(item.premiumAmount, code: item.currencyCode), systemImage: "calendar")
                if item.annualRate > 0 {
                    Text(String(format: "%.2f%%", item.annualRate))
                        .foregroundStyle(.blue)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(item.elapsedPeriods)/\(item.totalPeriods) 期")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text("期滿 " + fmtSmart(item.expectedReturn, code: item.currencyCode))
                        .foregroundStyle(.green)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.07), radius: 5, y: 2)
    }

    private func fmt(_ v: Double, code: String) -> String {
        let isUSD = code == "US$" || code == "USD" || code.lowercased() == "美金"
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencySymbol = code
        f.maximumFractionDigits = isUSD ? 2 : 0
        return f.string(from: NSNumber(value: v)) ?? "\(code)0"
    }

    /// 依數字大小自動帶單位：< 萬顯示原始金額、萬 ~ 億顯示「萬」、≥ 億顯示「億」
    private func fmtSmart(_ v: Double, code: String) -> String {
        let isUSD = code == "US$" || code == "USD" || code.lowercased() == "美金"
        let absV = abs(v)
        let sign = v < 0 ? "-" : ""
        if !isUSD && absV >= 100_000_000 {
            return "\(sign)\(code)\(String(format: "%.2f", absV / 100_000_000))億"
        }
        if !isUSD && absV >= 10_000 {
            return "\(sign)\(code)\(String(format: "%.1f", absV / 10_000))萬"
        }
        return fmt(v, code: code)
    }
}
