import SwiftUI

// MARK: - 美化紀錄（供下次美化比對，維持各頁視覺一致性；未變更任何商業邏輯／計算公式）
// 1. 主題色：沿用 IncomeView / VariableExpenseView 的空狀態雙層脈衝光環樣式，圖示改為 shield，
//    強調色改用靛藍（indigo，代表「保障」語意）以區隔固定支出(藍)/收入(綠)/變動支出(橘)；
//    工具列「+」維持與其他理財子頁（Stock/Vehicle/RealEstate）一致的 .green，不單獨改色。
// 2. summaryHeader：卡片化（圓角 16、輕陰影、淡入＋輕微位移進場動畫），損益膠囊維持既有配色邏輯。
// 3. insuranceCard：左側色條 + 圓形 shield 圖示，列表加入錯落淡入進場動畫（index 遞增 delay）。
// 4. emptyState：漸層圓底 + 雙層脈衝光環 + CTA 按鈕（對齊 FixedExpenseView 空狀態語言）。
// 5. fmtSmart：金額量級新增「億」（≥ 1 億）顯示，避免鉅額數字過長；原本「萬」邏輯不變。
// 6. 深色模式：一律使用 Color(.systemBackground) / (.secondarySystemGroupedBackground) 等系統色。

struct SavingsInsuranceView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var editingItem: SavingsInsurance?
    @State private var showPremiumAlert = false
    @State private var headerAppeared = false
    @State private var listAppeared = false
    @State private var emptyIconPulse = false

    private static let accent = Color(red: 0.35, green: 0.34, blue: 0.84)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader

                if store.insurances.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(Array(store.insurances.enumerated()), id: \.element.id) { index, item in
                            insuranceCard(item)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .opacity(listAppeared ? 1 : 0)
                                .offset(y: listAppeared ? 0 : 10)
                                .animation(
                                    .spring(response: 0.45, dampingFraction: 0.85)
                                        .delay(Double(min(index, 8)) * 0.045),
                                    value: listAppeared
                                )
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
                    .onAppear {
                        withAnimation { listAppeared = true }
                    }
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
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddSavingsInsuranceView() }
            .sheet(item: $editingItem) { item in AddSavingsInsuranceView(editing: item) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    private var summaryHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Text("保單總覽")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(store.insurances.count) 張保單")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }

            // 依幣別分組顯示
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

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("目前價值 (\(code))")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(fmtSmart(totalCurrent, code: code))
                                .font(.title3.bold())
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("已繳總額")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(fmtSmart(totalPaid, code: code))
                                .font(.subheadline)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                        }
                    }

                    HStack {
                        let isPositive = gain >= 0
                        Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption).foregroundStyle(isPositive ? .green : .red)
                        Text((isPositive ? "+" : "") + fmtSmart(gain, code: code))
                            .font(.caption.bold()).foregroundStyle(isPositive ? .green : .red)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(String(format: "(%@%.2f%%)", isPositive ? "+" : "", gainRate))
                            .font(.caption2).foregroundStyle(isPositive ? .green : .red)
                        Spacer()
                    }
                    .padding(8)
                    .background((gain >= 0 ? Color.green : Color.red).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(Color(.systemGroupedBackground))
        .opacity(headerAppeared ? 1 : 0)
        .offset(y: headerAppeared ? 0 : -8)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                headerAppeared = true
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Self.accent.opacity(emptyIconPulse ? 0 : 0.25), lineWidth: 1.5)
                    .frame(width: 100, height: 100)
                    .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                Circle()
                    .stroke(Self.accent.opacity(emptyIconPulse ? 0 : 0.14), lineWidth: 1)
                    .frame(width: 100, height: 100)
                    .scaleEffect(emptyIconPulse ? 1.65 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).delay(0.25).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Self.accent.opacity(0.14), Self.accent.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 82, height: 82)
                    .overlay(
                        Circle().stroke(Self.accent.opacity(0.20), lineWidth: 1.2)
                    )
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Self.accent.opacity(0.8))
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    emptyIconPulse = true
                }
            }

            VStack(spacing: 8) {
                Text("尚無儲蓄險紀錄")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.7))
                Text("新增保單即可追蹤已繳保費與期滿價值")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            Button {
                if subscription.isPremium { showAdd = true }
                else { showPremiumAlert = true }
            } label: {
                Label("新增保單", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Self.accent, Self.accent.opacity(0.75)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Self.accent.opacity(0.35), radius: 10, y: 5)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func insuranceCard(_ item: SavingsInsurance) -> some View {
        let isNT = item.currencyCode == "NT$"
        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isNT ? Color.green.opacity(0.55) : Color.blue.opacity(0.55))
                .frame(width: 3)
                .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill((isNT ? Color.green : Color.blue).opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "shield.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(isNT ? .green : .blue)
                    }

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
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
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
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private func fmt(_ v: Double, code: String) -> String {
        let isUSD = code == "US$" || code == "USD" || code.lowercased() == "美金"
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencySymbol = code
        f.maximumFractionDigits = isUSD ? 2 : 0
        return f.string(from: NSNumber(value: v)) ?? "\(code)0"
    }

    /// 金額量級智慧顯示：≥ 1 億顯示「億」、≥ 1 萬顯示「萬」，避免鉅額數字過長難以辨識
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
