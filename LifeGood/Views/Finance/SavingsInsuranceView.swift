import SwiftUI

// MARK: - 美化紀錄（SavingsInsuranceView）
// [2026-06] 本次美化方向：
//   1. summaryHeader → 升級為藍色漸層英雄卡片：含保單計數膠囊 + NT$ 目前估值 +
//      損益 KPI 膠囊（參照 FixedExpenseView fixedSummaryHeader 規格），
//      加入進場動畫（headerAppeared 旗標，對齊 IncomeView / FixedExpenseView）
//   2. emptyState → 升級為雙層脈衝光環 + 漸層底圓 + 藍色 CTA 按鈕，
//      對齊 FixedExpenseView emptyStateView 的空狀態設計規格
//   3. insuranceCard → 加入左側 4pt 藍色強調條 + 44pt 漸層圖示圓 + 陰影，
//      改用彩色膠囊標籤顯示幣別與繳費週期，
//      補入已繳期數比例進度條（LinearGradient + spring 動畫），
//      對齊 FixedExpenseRow / ExpenseRow 視覺規格
//   4. 保單列表 → 改為 List（insetGrouped），
//      加入交錯淡入 + 向上進場動畫（cardsAppeared 旗標），
//      補 .navigationBarTitleDisplayMode(.large)，對齊各列表頁規格
//   5. 結構整體調整：VStack+summaryHeader+List → 單一 insetGrouped List，
//      header 嵌入為 Section，捲動行為與 VariableExpenseView 對齊

struct SavingsInsuranceView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var editingItem: SavingsInsurance?
    @State private var showPremiumAlert = false
    @State private var headerAppeared = false
    @State private var cardsAppeared = false
    @State private var emptyIconPulse = false

    private let heroAccent = Color(red: 0.22, green: 0.53, blue: 0.98)
    private let heroAccentDark = Color(red: 0.10, green: 0.35, blue: 0.82)

    var body: some View {
        NavigationStack {
            List {
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

                if store.insurances.isEmpty {
                    Section {
                        emptyStateView
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    Section {
                        ForEach(Array(store.insurances.enumerated()), id: \.element.id) { idx, item in
                            insuranceCard(item)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .opacity(cardsAppeared ? 1 : 0)
                                .offset(y: cardsAppeared ? 0 : 18)
                                .animation(
                                    .spring(response: 0.45, dampingFraction: 0.82)
                                        .delay(0.04 * Double(idx)),
                                    value: cardsAppeared
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
                    .onAppear {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                            cardsAppeared = true
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("儲蓄險")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if subscription.isPremium { showAdd = true }
                        else { showPremiumAlert = true }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(heroAccent)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddSavingsInsuranceView() }
            .sheet(item: $editingItem) { item in AddSavingsInsuranceView(editing: item) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    // MARK: - KPI Cell（共用於 summaryHeader）

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

    // MARK: - 摘要英雄卡片

    private var summaryHeader: some View {
        let ntItems = store.insurances.filter { $0.currencyCode == "NT$" }
        let otherItems = store.insurances.filter { $0.currencyCode != "NT$" }
        let ntCurrent = ntItems.reduce(0.0) { $0 + $1.currentValue }
        let ntPaid = ntItems.reduce(0.0) { $0 + $1.totalPaid }
        let ntGain = ntCurrent - ntPaid
        let ntGainRate = ntPaid > 0 ? ntGain / ntPaid * 100 : 0.0
        let isPositive = ntGain >= 0

        return VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("保單總覽")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                    Text(store.insurances.isEmpty ? "NT$0" : fmtSmart(ntCurrent, code: "NT$"))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    if !ntItems.isEmpty {
                        Text("NT$ 保單目前估值")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .padding(.top, 1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(store.insurances.count) 張")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.22))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                    if !ntItems.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 9))
                            Text(String(format: "%@%.1f%%", isPositive ? "+" : "", ntGainRate))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.18))
                        .clipShape(Capsule())
                        .foregroundStyle(isPositive ? .white : Color(red: 1.0, green: 0.78, blue: 0.75))
                    }
                }
            }

            if !ntItems.isEmpty {
                HStack(spacing: 0) {
                    kpiCell(label: "已繳總額", value: fmtSmart(ntPaid, code: "NT$"))
                    Rectangle()
                        .fill(.white.opacity(0.25))
                        .frame(width: 0.5, height: 28)
                    kpiCell(label: "帳面損益", value: (isPositive ? "+" : "") + fmtSmart(ntGain, code: "NT$"))
                    if !otherItems.isEmpty {
                        Rectangle()
                            .fill(.white.opacity(0.25))
                            .frame(width: 0.5, height: 28)
                        kpiCell(label: "其他幣別", value: "\(otherItems.count) 張")
                    }
                }
                .padding(.vertical, 10)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.top, 14)
            }
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
                Circle()
                    .fill(.white.opacity(0.13))
                    .frame(width: 130, height: 130)
                    .offset(x: 85, y: -50)
                    .blur(radius: 14)
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 75, height: 75)
                    .offset(x: -65, y: 45)
                    .blur(radius: 9)
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

    // MARK: - 空狀態

    private var emptyStateView: some View {
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
                // 內層脈衝光環（延遲 0.3s，製造波紋層次）
                Circle()
                    .stroke(heroAccent.opacity(emptyIconPulse ? 0 : 0.14), lineWidth: 1)
                    .frame(width: 110, height: 110)
                    .scaleEffect(emptyIconPulse ? 1.60 : 1.0)
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
                    .overlay(Circle().stroke(heroAccent.opacity(0.22), lineWidth: 1.2))
                Image(systemName: "shield.slash")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(heroAccent.opacity(0.70))
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    emptyIconPulse = true
                }
            }

            VStack(spacing: 10) {
                Text("尚無儲蓄險紀錄")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                Text("儲蓄險可記錄保費、利率與到期還本，\n幫助掌握長期資產配置")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button {
                if subscription.isPremium { showAdd = true }
                else { showPremiumAlert = true }
            } label: {
                Label("新增儲蓄險", systemImage: "plus.circle.fill")
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
                    .shadow(color: heroAccentDark.opacity(0.35), radius: 10, y: 5)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 保單卡片

    private func insuranceCard(_ item: SavingsInsurance) -> some View {
        let isNT = item.currencyCode == "NT$"
        let gain = item.currentValue - item.totalPaid
        let gainRate = item.totalPaid > 0 ? gain / item.totalPaid * 100 : 0.0
        let isPositive = gain >= 0
        let periodRatio = item.totalPeriods > 0
            ? min(Double(item.elapsedPeriods) / Double(item.totalPeriods), 1.0)
            : 0.0

        return HStack(spacing: 0) {
            // 左側 4pt 強調條
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [heroAccent, heroAccentDark],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .padding(.vertical, 4)

            HStack(alignment: .top, spacing: 12) {
                // 44pt 漸層圖示圓
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [heroAccent.opacity(0.18), heroAccent.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(heroAccent.opacity(0.22), lineWidth: 1))
                        .shadow(color: heroAccent.opacity(0.18), radius: 6, y: 3)
                    Image(systemName: "shield.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(heroAccent)
                }

                VStack(alignment: .leading, spacing: 6) {
                    // 名稱 + 幣別膠囊 + 週期膠囊
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(item.currencyCode)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(isNT ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                            .foregroundStyle(isNT ? .green : .orange)
                            .clipShape(Capsule())
                        Text(item.paymentPeriod.rawValue)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.purple.opacity(0.10))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }

                    if !item.company.isEmpty {
                        Text(item.company)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // 目前估值 + 損益膠囊
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(fmtSmart(item.currentValue, code: item.currencyCode))
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                        HStack(spacing: 3) {
                            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 9))
                            Text(String(format: "%@%.1f%%", isPositive ? "+" : "", gainRate))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background((isPositive ? Color.green : Color.red).opacity(0.10))
                        .foregroundStyle(isPositive ? .green : .red)
                        .clipShape(Capsule())
                    }

                    // 利率 + 到期還本 + 已繳期數
                    HStack(spacing: 10) {
                        if item.annualRate > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "percent")
                                    .font(.system(size: 9))
                                Text(String(format: "%.2f%%", item.annualRate))
                            }
                            .font(.caption)
                            .foregroundStyle(heroAccent)
                        }
                        HStack(spacing: 3) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 9))
                            Text("到期 " + fmtSmart(item.expectedReturn, code: item.currencyCode))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(item.elapsedPeriods)/\(item.totalPeriods) 期")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    // 已繳期數進度條
                    if item.totalPeriods > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(.systemGray5))
                                    .frame(height: 4)
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [heroAccent, heroAccentDark],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * periodRatio, height: 4)
                                    .animation(.spring(response: 0.7, dampingFraction: 0.8), value: periodRatio)
                            }
                        }
                        .frame(height: 4)
                        .padding(.top, 2)
                    }
                }
                .padding(.vertical, 12)
                .padding(.trailing, 2)
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
    }

    // MARK: - 格式化

    private func fmt(_ v: Double, code: String) -> String {
        // 台幣套用「萬」規則；外幣維持原幣別與小數位
        if code == "NT$" || code == "TWD" || code.isEmpty { return v.ntdWanString }
        let isUSD = code == "US$" || code == "USD" || code.lowercased() == "美金"
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencySymbol = code
        f.maximumFractionDigits = isUSD ? 2 : 0
        return f.string(from: NSNumber(value: v)) ?? "\(code)0"
    }

    private func fmtSmart(_ v: Double, code: String) -> String {
        let isUSD = code == "US$" || code == "USD" || code.lowercased() == "美金"
        let absV = abs(v)
        let sign = v < 0 ? "-" : ""
        if !isUSD && absV >= 10_000 {
            return "\(sign)\(code)\(String(format: "%.1f", absV / 10_000))萬"
        }
        return fmt(v, code: code)
    }
}
