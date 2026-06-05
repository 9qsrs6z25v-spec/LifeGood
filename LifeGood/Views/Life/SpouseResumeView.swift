import SwiftUI

// MARK: - 美化紀錄（SpouseResumeView）
// [2026-06] 本次美化方向：
//   1. profileSection → 粉紅漸層英雄卡片：配偶名字大字 + 心形圖示圓 + 散景裝飾圓，
//      底部三欄 KPI（結婚年數 / 共同消費金額 / 禮金筆數），
//      對齊 FinanceOverviewView.totalAssetsCard 設計語言；
//      加入 cardAppeared spring 進場動畫（透明度 + Y 位移）
//   2. marriageSection / milestoneSection / expenseSection header：
//      Capsule 漸層側條 + subheadline.bold + 計數膠囊徽章，
//      對齊 LifeOverviewView.milestoneTimelineSection 標題設計語言
//   3. marriageRow：36pt LinearGradient 漸層圖示圓（對齊 LifeFinanceView.milestoneRow 規格），
//      日期以彩色膠囊徽章呈現；結婚年數以粉紅膠囊強調
//   4. milestoneRow：左側 4pt 粉紅強調條 + 40pt 漸層圖示圓 + 日期膠囊，
//      對齊 LifeOverviewView.milestoneTimelineSection row 規格；
//      加入交錯淡入 + 向上進場動畫（milestonesAppeared）
//   5. expenseRow：升級為 44pt LinearGradient 漸層圖示圓 + 陰影 + 分類色膠囊，
//      金額改用 ntdWanString，對齊 ExpenseRow / IncomeView.incomeRow 視覺規格；
//      加入交錯淡入 + 向上進場動畫（expensesAppeared）
//   6. 空狀態：漸層圖示圓 + 說明文字佔位，對齊 FixedExpenseView emptyStateView 規格
//   7. formatCurrency 改用 .ntdWanString，統一全 App 金額顯示規格；
//      DateFormatter 改為靜態共用實例，避免每次 render 重新分配

struct SpouseResumeView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore

    // 進場動畫旗標
    @State private var cardAppeared = false
    @State private var milestonesAppeared = false
    @State private var expensesAppeared = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    private var spouse: FamilyMember? {
        lifeStore.familyMembers.first { $0.role == .spouse }
    }

    /// 變動支出中，diningMember 含有配偶名字的紀錄
    private var spouseExpenses: [Expense] {
        guard let s = spouse, !s.chineseName.isEmpty else { return [] }
        let target = s.chineseName
        return expenseStore.expenses
            .filter { $0.expenseType == .variable }
            .filter { e in
                guard let raw = e.diningMember, !raw.isEmpty else { return false }
                let names = raw.split(separator: "、").map { String($0).trimmingCharacters(in: .whitespaces) }
                return names.contains(target)
            }
            .sorted { $0.date > $1.date }
    }

    private var spouseExpenseTotal: Double {
        spouseExpenses.reduce(0) { $0 + $1.amount }
    }

    /// 變動支出 .social 中將配偶列為收受人的紀錄
    private var spouseGifts: [Expense] {
        guard let s = spouse, !s.chineseName.isEmpty else { return [] }
        let target = s.chineseName
        return expenseStore.expenses
            .filter { $0.expenseType == .variable && $0.variableCategory == .social }
            .filter { e in
                guard let raw = e.socialRecipient, !raw.isEmpty else { return false }
                let names = raw.components(separatedBy: CharacterSet(charactersIn: ",、，"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                return names.contains(target)
            }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                if let s = spouse {
                    // 英雄卡
                    Section {
                        heroCard(s)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .opacity(cardAppeared ? 1 : 0)
                            .offset(y: cardAppeared ? 0 : 22)
                            .onAppear {
                                withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                    cardAppeared = true
                                }
                            }
                    }
                    marriageSection(s)
                    milestoneSection
                    giftSection
                    expenseSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("配偶履歷")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - 英雄卡片

    private static let heroAccent      = Color(red: 0.96, green: 0.35, blue: 0.58)
    private static let heroAccentDark  = Color(red: 0.76, green: 0.18, blue: 0.40)

    private func heroCard(_ s: FamilyMember) -> some View {
        let accent     = Self.heroAccent
        let accentDark = Self.heroAccentDark
        let marriageComp: (year: Int, month: Int)? = s.marriageDate.map { md in
            let c = Calendar.current.dateComponents([.year, .month], from: md, to: Date())
            return (c.year ?? 0, c.month ?? 0)
        }

        return VStack(spacing: 0) {
            // 頂部：名字 + 愛心圖示
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("配偶")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(s.chineseName.isEmpty ? "未填寫姓名" : s.chineseName)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .contentTransition(.numericText())
                    if !s.englishName.isEmpty {
                        Text(s.englishName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.68))
                            .padding(.top, 1)
                    }
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.20))
                        .frame(width: 52, height: 52)
                    Image(systemName: s.isDivorced ? "heart.slash.fill" : "heart.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(s.isDivorced ? .white.opacity(0.55) : .white)
                }
            }

            // 分隔線
            Rectangle()
                .fill(.white.opacity(0.20))
                .frame(height: 0.5)
                .padding(.vertical, 14)

            // 三欄 KPI
            HStack(spacing: 0) {
                kpiCell(label: "結婚年數",
                        value: marriageComp.map { "\($0.year)年\($0.month)月" } ?? "未填寫")

                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 28)

                kpiCell(label: "共同消費",
                        value: spouseExpenseTotal.ntdWanString)

                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 28)

                kpiCell(label: "禮金紀錄",
                        value: "\(spouseGifts.count) 筆")
            }
            .padding(.vertical, 8)
            .background(.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            ZStack {
                LinearGradient(
                    colors: [accent, accentDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 右上主散景圓
                Circle()
                    .fill(.white.opacity(0.13))
                    .frame(width: 140, height: 140)
                    .offset(x: 90, y: -55)
                    .blur(radius: 14)
                // 左下補光
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 90, height: 90)
                    .offset(x: -70, y: 55)
                    .blur(radius: 10)
                // 中右小散景
                Circle()
                    .fill(.white.opacity(0.05))
                    .frame(width: 55, height: 55)
                    .offset(x: 55, y: 38)
                    .blur(radius: 8)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: accentDark.opacity(0.42), radius: 16, x: 0, y: 8)
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
                .minimumScaleFactor(0.60)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    // MARK: - Section Header 共用

    private func sectionHeader(title: String, color: Color, count: Int? = nil) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 18)
            Text(title)
                .font(.subheadline.weight(.bold))
            Spacer()
            if let n = count, n > 0 {
                Text("\(n) 筆")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.75))
            }
        }
        .textCase(nil)
    }

    // MARK: - 婚姻紀錄

    private func marriageSection(_ s: FamilyMember) -> some View {
        let accent = Self.heroAccent
        return Section(header: sectionHeader(title: "婚姻紀錄", color: accent)) {
            // 結婚日期
            marriageRow(
                icon: "calendar.badge.checkmark",
                accent: accent,
                label: "結婚日期",
                trailing: {
                    if let md = s.marriageDate {
                        Text(Self.dateFormatter.string(from: md))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(accent.opacity(0.08))
                            .clipShape(Capsule())
                    } else {
                        Text("未填寫").font(.subheadline).foregroundStyle(.tertiary)
                    }
                }
            )

            // 結婚年數
            if let md = s.marriageDate {
                let c = Calendar.current.dateComponents([.year, .month], from: md, to: Date())
                marriageRow(
                    icon: "clock.fill",
                    accent: accent,
                    label: "結婚年數",
                    trailing: {
                        Text("\(c.year ?? 0) 年 \(c.month ?? 0) 月")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(accent.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.75))
                    }
                )
            }

            // 離婚
            if s.isDivorced {
                marriageRow(
                    icon: "heart.slash.fill",
                    accent: .red,
                    label: "已離婚",
                    trailing: {
                        if let dd = s.divorceDate {
                            Text(Self.dateFormatter.string(from: dd))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                )
            }
        }
    }

    private func marriageRow<Trailing: View>(
        icon: String,
        accent: Color,
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            // 36pt 漸層圖示圓
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.20), accent.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Text(label)
                .font(.subheadline)
            Spacer()
            trailing()
        }
        .padding(.vertical, 4)
    }

    // MARK: - 里程碑

    private var milestoneSection: some View {
        let accent  = Self.heroAccent
        let derived = lifeStore.familyDerivedMilestones
            .filter { $0.category == .marriage }
            .sorted { $0.date > $1.date }

        return Section(
            header: sectionHeader(title: "相關里程碑", color: accent,
                                  count: derived.isEmpty ? nil : derived.count)
        ) {
            if derived.isEmpty {
                emptyPlaceholder(icon: "heart.text.square", text: "尚無相關里程碑")
            } else {
                ForEach(Array(derived.enumerated()), id: \.element.id) { idx, m in
                    milestoneRow(m, accent: accent)
                        .opacity(milestonesAppeared ? 1 : 0)
                        .offset(y: milestonesAppeared ? 0 : 12)
                        .animation(
                            .spring(response: 0.44, dampingFraction: 0.82)
                                .delay(0.05 * Double(idx)),
                            value: milestonesAppeared
                        )
                        .onAppear {
                            if idx == 0 {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                                    milestonesAppeared = true
                                }
                            }
                        }
                }
            }
        }
    }

    private func milestoneRow(_ m: LifeMilestone, accent: Color) -> some View {
        HStack(alignment: .center, spacing: 0) {
            // 左側粉紅強調條
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.45)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 3)
                .padding(.vertical, 10)
                .padding(.trailing, 12)

            // 40pt 漸層圖示圓 + 細邊框
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.22), accent.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                Circle()
                    .stroke(accent.opacity(0.28), lineWidth: 1.5)
                    .frame(width: 40, height: 40)
                Image(systemName: m.title.contains("結婚") ? "heart.fill" : "heart.slash.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(m.title.contains("結婚") ? accent : Color.gray)
            }
            .padding(.trailing, 12)

            // 標題 + 日期膠囊
            VStack(alignment: .leading, spacing: 5) {
                Text(m.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(Self.dateFormatter.string(from: m.date))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    // MARK: - 禮金（共用元件）

    @ViewBuilder
    private var giftSection: some View {
        if !spouseGifts.isEmpty {
            ResumeGiftSection(gifts: spouseGifts, recipientName: spouse?.chineseName ?? "配偶")
        }
    }

    // MARK: - 共同消費

    @ViewBuilder
    private var expenseSection: some View {
        let accent = Color(red: 1.00, green: 0.62, blue: 0.22)
        Section(
            header: sectionHeader(title: "共同消費", color: accent,
                                  count: spouseExpenses.isEmpty ? nil : spouseExpenses.count),
            footer: Text("變動支出中將「\(spouse?.chineseName ?? "配偶")」加入人員的紀錄會自動同步到此。")
        ) {
            if spouseExpenses.isEmpty {
                emptyPlaceholder(icon: "bag", text: "尚無共同消費紀錄")
            } else {
                // 合計列
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.red.opacity(0.18), Color.red.opacity(0.07)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        Image(systemName: "sum")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
                    }
                    Text("合計 \(spouseExpenses.count) 筆")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(spouseExpenseTotal.ntdWanString)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
                        .contentTransition(.numericText())
                }
                .padding(.vertical, 4)

                // 消費列（交錯進場）
                ForEach(Array(spouseExpenses.prefix(20).enumerated()), id: \.element.id) { idx, e in
                    expenseRow(e)
                        .opacity(expensesAppeared ? 1 : 0)
                        .offset(y: expensesAppeared ? 0 : 12)
                        .animation(
                            .spring(response: 0.44, dampingFraction: 0.82)
                                .delay(0.04 * Double(min(idx, 14))),
                            value: expensesAppeared
                        )
                        .onAppear {
                            if idx == 0 {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                                    expensesAppeared = true
                                }
                            }
                        }
                }

                if spouseExpenses.count > 20 {
                    Text("還有 \(spouseExpenses.count - 20) 筆…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    private func expenseRow(_ e: Expense) -> some View {
        let accent = e.variableCategory?.accentColor ?? Color.orange
        return HStack(spacing: 12) {
            // 44pt 漸層圖示圓 + 陰影（對齊 ExpenseRow / IncomeView.incomeRow 規格）
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
                Image(systemName: e.variableCategory?.icon ?? "questionmark.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(e.title.isEmpty ? (e.variableCategory?.rawValue ?? "未分類") : e.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let cat = e.variableCategory {
                        Text(cat.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(accent.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    if let raw = e.diningMember, !raw.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill").font(.system(size: 9))
                            Text(raw).font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    Text(Self.dateFormatter.string(from: e.date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 4)

            Text(e.amount.ntdWanString)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
                .contentTransition(.numericText())
        }
        .padding(.vertical, 5)
    }

    // MARK: - 空狀態佔位

    private func emptyPlaceholder(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(.secondarySystemFill), Color(.systemFill)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
