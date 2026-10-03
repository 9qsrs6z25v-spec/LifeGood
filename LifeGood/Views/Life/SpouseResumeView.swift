import SwiftUI

// MARK: - 美化紀錄（SpouseResumeView）
// [2026-06 v1] 本次美化方向：
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
// [2026-06 v2] 補齊缺失的全 App 設計語言標準元素：
//   A. heroCard background ZStack → 頂部玻璃光澤：LinearGradient([.white.opacity(0.18), .clear], top→center)
//      對齊 FinanceOverviewView、StockView、VehicleView 的 totalAssetsCard 玻璃效果
//   B. KPI 底欄背景 → 加入光澤 glow overlay：LinearGradient([.white.opacity(0.28), .clear, .black.opacity(0.08)])
//      對齊 VariableExpenseView.monthSummaryHeader KPI 區域光澤規格
//   C. marriageRow 36pt 圖示圓 → 加入細邊框 stroke(accent.opacity(0.28), lineWidth: 1.0)
//      對齊 milestoneRow 40pt 圓已有邊框，確保 section 內視覺一致
//   D. expenseRow 44pt 圖示圓 → 加入細邊框 stroke(accent.opacity(0.28), lineWidth: 1.5)
//      對齊 IncomeView.incomeRow / OverviewView.recentRow 的圓形邊框規格
//   E. expenseRow 日期文字 → 改為膠囊徽章（tertiarySystemFill 背景），
//      對齊 VariableExpenseView.expenseRow 日期膠囊標準
// [2026-06 v3] 細節升級（對齊全 App 最新標準元素）：
//   F. heroCard 愛心圖示圓：Circle().fill(.white.opacity(0.20)) →
//      LinearGradient([.white.opacity(0.30), .white.opacity(0.12)]) 底 +
//      Circle().stroke(.white.opacity(0.35), 0.75pt)，對齊 ChildDetailView v2 / OrganizationView v2 英雄圖示圓規格。
//   G. kpiCell 加入 28pt LinearGradient 半透明圖示圓（依 KPI 語意分配圖示）+
//      contentTransition(.numericText())，對齊 ChildrenResumeView v3 heroKpiCell /
//      SubordinateOverviewView v3 heroKpiCell 規格。
//   H. sectionHeader 加入 icon 參數（Image(systemName:) 圖示，對齊 TaxOverviewView.sectionHeader /
//      CareerView.milestoneListSection 標題規格），補足全 App section header 圖示元素。
//   I. expenseRow 分類膠囊補 Capsule stroke 細邊框（accent.opacity(0.22) 0.6pt），
//      對齊 CareerView v2 / FoodMapView v3 / LifeOverviewView.categoryBreakdownSection 膠囊邊框規格。
//   J. 合計列（sumRow）圖示圓補 Circle().stroke(Color.red.opacity(0.18), 0.75pt)，
//      對齊 taxSavingSection 彙總列 v3 / expenseRow 圖示圓統一描邊規格。
//   K. emptyPlaceholder 升級：38pt 裸圓 → 雙層脈衝光環 + 漸層底圓 + 圖示，
//      加入 emptyIconPulse 動畫旗標，對齊 TaxOverviewView v2 / VariableExpenseView emptyStateView 規格。
//   L. milestoneRow 左側強調條：3pt RoundedRectangle(cornerRadius:2) → 4pt Capsule，
//      對齊全 App 統一 4pt Capsule 強調條規格（TaxOverviewView.taxRecordsSection / VehicleView.vehicleCard）。
//   M. heroCard shadow 升級雙層：補加 .shadow(color:.black.opacity(0.06), radius:8, y:4)，
//      對齊 FamilyMembersResumeView v3 / SubordinateOverviewView v3 雙層 shadow 規格。

struct SpouseResumeView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager

    // 進場動畫旗標
    @State private var cardAppeared = false
    @State private var milestonesAppeared = false
    @State private var expensesAppeared = false
    // [v3] 空狀態脈衝光環動畫旗標：里程碑／消費兩個空狀態各自獨立一份，避免共用同一旗標時
    // 其中一個先掛載把旗標設成 true，另一個掛載時偵測不到「從 false 變 true」而不會播放
    // （同型修復比照 TaxOverviewView v24.22 拆分 emptyRecordsPulse／emptySavingPulse）。
    @State private var milestoneEmptyPulse = false
    @State private var expenseEmptyPulse = false
    @State private var milestoneEmptyPulseTask: Task<Void, Never>?
    @State private var expenseEmptyPulseTask: Task<Void, Never>?
    // 協定
    @State private var editingAgreement: SpouseAgreement?
    @State private var agreementSpouseId: UUID?
    @State private var agreementEmptyPulse = false
    @State private var agreementEmptyPulseTask: Task<Void, Never>?
    @State private var showDoneAgreements = false
    @State private var showPremiumAlert = false

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
            // spouseExpenses／spouseGifts（全量 filter+字串切分+sort）改在此算一次，
            // 往下傳給 heroCard／giftSection／expenseSection，避免原本各自重複呼叫
            // spouseExpenses／spouseExpenseTotal／spouseGifts 造成單次 render 十次上下的全量掃描。
            let expenses = spouseExpenses
            let expenseTotal = expenses.reduce(0) { $0 + $1.amount }
            let gifts = spouseGifts
            List {
                if let s = spouse {
                    // 英雄卡
                    Section {
                        heroCard(s, expenseTotal: expenseTotal, giftCount: gifts.count)
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
                            .onDisappear {
                                // 重置旗標：切到其他分頁再切回時能重新播放英雄卡進場動畫
                                cardAppeared = false
                            }
                    }
                    marriageSection(s)
                    agreementSection(s)
                    milestoneSection
                    giftSection(gifts)
                    expenseSection(expenses, expenseTotal: expenseTotal)
                }
            }
            .listStyle(.insetGrouped)
            // onAppear/onDisappear 掛在 List 本身（而非 ForEach 內每一列）：List 會延遲載入
            // （lazy-load）各列，掛在 ForEach 上等同掛在每一列各自的子視圖上，捲動使某列進出可視範圍
            // 就各自觸發一次，milestonesAppeared／expensesAppeared 是所有列共用的旗標，
            // 反覆觸發會讓可視列表在捲動時無謂淡出又重播進場動畫。比照 FamilyView 既有寫法，
            // 改掛在 List 本身，確保只在畫面進出時各觸發一次。
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                    milestonesAppeared = true
                    expensesAppeared = true
                }
            }
            .onDisappear {
                // 重置旗標：切到其他分頁再切回時能重新播放里程碑／消費列表進場動畫
                milestonesAppeared = false
                expensesAppeared = false
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("配偶履歷")
            .navigationBarTitleDisplayMode(.large)
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .sheet(item: $editingAgreement) { ag in
                if let sid = agreementSpouseId {
                    NavigationStack { SpouseAgreementEditor(memberId: sid, agreement: ag) }
                }
            }
        }
    }

    // MARK: - 英雄卡片

    private static let heroAccent      = Color(red: 0.96, green: 0.35, blue: 0.58)
    private static let heroAccentDark  = Color(red: 0.76, green: 0.18, blue: 0.40)

    private func heroCard(_ s: FamilyMember, expenseTotal: Double, giftCount: Int) -> some View {
        let accent     = Self.heroAccent
        let accentDark = Self.heroAccentDark
        let marriageComp: (year: Int, month: Int)? = s.marriageDate.map { md in
            let endDate = (s.isDivorced ? s.divorceDate : nil) ?? Date()
            let c = Calendar.current.dateComponents([.year, .month], from: md, to: endDate)
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
                        .heroBigValueFont()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .contentTransition(.numericText())
                    if !s.englishName.isEmpty {
                        // [v25.74] 補齊 lineLimit/minimumScaleFactor，對齊上方 chineseName 與 ResumeView 姊妹規格
                        Text(s.englishName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.top, 1)
                    }
                }
                Spacer()
                // [v3] 圖示圓升級：LinearGradient 底 + stroke 細邊框，對齊 ChildDetailView v2 規格
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.30), .white.opacity(0.12)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    Circle()
                        .stroke(.white.opacity(0.35), lineWidth: 0.75)
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

            // 三欄 KPI（[v3] 各格加 28pt 漸層圖示圓 + contentTransition，對齊 ChildrenResumeView v3 規格）
            HStack(spacing: 0) {
                HeroKpiCell(label: "結婚年數",
                            value: marriageComp.map { "\($0.year)年\($0.month)月" } ?? "未填寫",
                            icon: "calendar")

                HeroKpiDivider()

                HeroKpiCell(label: "共同消費",
                            value: expenseTotal.ntdWanString,
                            icon: "bag.fill")

                HeroKpiDivider()

                HeroKpiCell(label: "禮金紀錄",
                            value: "\(giftCount) 筆",
                            icon: "gift.fill")
            }
            .padding(.vertical, 8)
            .background(
                // [v2-B] KPI 底欄光澤 glow：白頂→透明中→暗底，對齊 VariableExpenseView KPI 規格
                ZStack {
                    Color.white.opacity(0.10)
                    LinearGradient(
                        colors: [.white.opacity(0.28), .clear, .black.opacity(0.08)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .heroCardShell(card: .spouseResume)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // [v3] 加入 icon 參數 + 28pt 漸層圖示圓 + contentTransition，對齊 ChildrenResumeView v3 heroKpiCell 規格

    // MARK: - Section Header 共用

    // [v3] 加入 icon 參數，對齊 TaxOverviewView.sectionHeader / CareerView 標題規格
    private func sectionHeader(title: String, icon: String, color: Color, count: Int? = nil) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 18)
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
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
        return Section(header: sectionHeader(title: "婚姻紀錄", icon: "heart.fill", color: accent)) {
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
                let endDate = (s.isDivorced ? s.divorceDate : nil) ?? Date()
                let c = Calendar.current.dateComponents([.year, .month], from: md, to: endDate)
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
            // 36pt 漸層圖示圓 + [v2-C] 細邊框，對齊 milestoneRow 及全 App 圖示圓規格
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.20), accent.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Circle()
                    .stroke(accent.opacity(0.28), lineWidth: 1.0)
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

    // MARK: - 協定

    /// 與配偶談定的事。進行中的排前面，已完成／已作廢收在可展開區塊裡——
    /// 這些是「曾經談過但已經翻頁」的事，平常擋在主清單前面只會製造雜訊，
    /// 但也不該直接看不到（使用者會以為被刪了）。
    private func agreementSection(_ s: FamilyMember) -> some View {
        let accent = Color(red: 0.55, green: 0.42, blue: 0.92)
        let all = (s.agreements ?? []).sorted { $0.agreedDate > $1.agreedDate }
        let active = all.filter { $0.status == .active }
        let archived = all.filter { $0.status != .active }

        return Section(
            header: HStack(spacing: 10) {
                sectionHeader(title: "協定", icon: "hands.sparkles.fill", color: accent,
                              count: active.isEmpty ? nil : active.count)
                Button {
                    guard subscription.isPremium else { showPremiumAlert = true; return }
                    agreementSpouseId = s.id
                    editingAgreement = SpouseAgreement()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
        ) {
            if all.isEmpty {
                emptyPlaceholder(icon: "hands.sparkles", text: "尚無協定", color: accent,
                                 pulse: $agreementEmptyPulse, pulseTask: $agreementEmptyPulseTask)
            } else {
                ForEach(Array(active.enumerated()), id: \.element.id) { idx, ag in
                    agreementRow(ag, spouseId: s.id, accent: accent)
                        .opacity(milestonesAppeared ? 1 : 0)
                        .offset(y: milestonesAppeared ? 0 : 12)
                        .animation(
                            .spring(response: 0.44, dampingFraction: 0.82)
                                .delay(0.05 * Double(idx)),
                            value: milestonesAppeared
                        )
                }
                if !archived.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showDoneAgreements.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "archivebox.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("已完成／已作廢（\(archived.count)）")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: showDoneAgreements ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    if showDoneAgreements {
                        ForEach(archived) { ag in
                            agreementRow(ag, spouseId: s.id, accent: accent)
                        }
                    }
                }
            }
        }
    }

    private func agreementRow(_ ag: SpouseAgreement, spouseId: UUID, accent: Color) -> some View {
        let isArchived = ag.status != .active
        let sub = ag.subtitleText
        return HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.09)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(accent.opacity(0.22), lineWidth: 0.75))
                Image(systemName: ag.category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(ag.title.isEmpty ? "（未填內容）" : ag.title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(isArchived, color: .secondary)
                    .foregroundStyle(isArchived ? .secondary : .primary)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Text(ag.category.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(accent.opacity(0.12))
                        .clipShape(Capsule())
                    if !sub.isEmpty {
                        Text(sub)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if !ag.detail.isEmpty {
                    Text(ag.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Self.dateFormatter.string(from: ag.agreedDate))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                if isArchived {
                    Text(ag.status.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard subscription.isPremium else { showPremiumAlert = true; return }
            agreementSpouseId = spouseId
            editingAgreement = ag
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                guard subscription.isPremium else { showPremiumAlert = true; return }
                lifeStore.deleteAgreement(ag.id, for: spouseId)
            } label: {
                Label("刪除", systemImage: "trash")
            }
        }
    }

    // MARK: - 里程碑

    private var milestoneSection: some View {
        let accent  = Self.heroAccent
        let derived = lifeStore.familyDerivedMilestones
            .filter { $0.category == .marriage }
            .sorted { $0.date > $1.date }

        return Section(
            header: sectionHeader(title: "相關里程碑", icon: "star.fill", color: accent,
                                  count: derived.isEmpty ? nil : derived.count)
        ) {
            if derived.isEmpty {
                emptyPlaceholder(icon: "heart.text.square", text: "尚無相關里程碑", pulse: $milestoneEmptyPulse, pulseTask: $milestoneEmptyPulseTask)
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
                }
            }
        }
    }

    private func milestoneRow(_ m: LifeMilestone, accent: Color) -> some View {
        HStack(alignment: .center, spacing: 0) {
            // [v3] 左側強調條：3pt RoundedRectangle → 4pt Capsule，對齊全 App 統一強調條規格
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.45)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 4)
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
    private func giftSection(_ gifts: [Expense]) -> some View {
        if !gifts.isEmpty {
            ResumeGiftSection(gifts: gifts, recipientName: spouse?.chineseName ?? "配偶")
        }
    }

    // MARK: - 共同消費

    @ViewBuilder
    private func expenseSection(_ expenses: [Expense], expenseTotal: Double) -> some View {
        let accent = Color(red: 1.00, green: 0.62, blue: 0.22)
        Section(
            header: sectionHeader(title: "共同消費", icon: "bag.fill", color: accent,
                                  count: expenses.isEmpty ? nil : expenses.count),
            footer: Text("變動支出中將「\(spouse?.chineseName ?? "配偶")」加入人員的紀錄會自動同步到此。")
        ) {
            if expenses.isEmpty {
                emptyPlaceholder(icon: "bag", text: "尚無共同消費紀錄", color: accent, pulse: $expenseEmptyPulse, pulseTask: $expenseEmptyPulseTask)
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
                        // [v3] 補 stroke 邊框，對齊 taxSavingSection 彙總列 v3 規格
                        Circle()
                            .stroke(Color.red.opacity(0.18), lineWidth: 0.75)
                            .frame(width: 36, height: 36)
                        Image(systemName: "sum")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
                    }
                    Text("合計 \(expenses.count) 筆")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(expenseTotal.ntdWanString)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
                        .contentTransition(.numericText())
                }
                .padding(.vertical, 4)

                // 消費列（交錯進場）
                ForEach(Array(expenses.prefix(20).enumerated()), id: \.element.id) { idx, e in
                    expenseRow(e)
                        .opacity(expensesAppeared ? 1 : 0)
                        .offset(y: expensesAppeared ? 0 : 12)
                        .animation(
                            .spring(response: 0.44, dampingFraction: 0.82)
                                .delay(0.04 * Double(min(idx, 14))),
                            value: expensesAppeared
                        )
                }

                if expenses.count > 20 {
                    Text("還有 \(expenses.count - 20) 筆…")
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
            // 44pt 漸層圖示圓 + 陰影 + [v2-D] 細邊框（對齊 ExpenseRow / IncomeView.incomeRow 規格）
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
                Circle()
                    .stroke(accent.opacity(0.28), lineWidth: 1.5)
                    .frame(width: 44, height: 44)
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
                            // [v3] 補 stroke 邊框，對齊 CareerView v2 / FoodMapView v3 膠囊邊框規格
                            .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                    }
                    if let raw = e.diningMember, !raw.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill").font(.system(size: 9))
                            Text(raw).font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    // [v2-E] 日期改為膠囊徽章，對齊 VariableExpenseView.expenseRow 標準
                    Text(Self.dateFormatter.string(from: e.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
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
    // [v3] 升級：雙層脈衝光環 + 漸層底圓，對齊 TaxOverviewView v2 / VariableExpenseView emptyStateView 規格

    private func emptyPlaceholder(icon: String, text: String, color: Color = Self.heroAccent, pulse: Binding<Bool>, pulseTask: Binding<Task<Void, Never>?>) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(color.opacity(pulse.wrappedValue ? 0 : 0.26), lineWidth: 1.5)
                    .frame(width: 88, height: 88)
                    .scaleEffect(pulse.wrappedValue ? 1.38 : 1.0)
                    .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false), value: pulse.wrappedValue)
                Circle()
                    .stroke(color.opacity(pulse.wrappedValue ? 0 : 0.13), lineWidth: 1)
                    .frame(width: 88, height: 88)
                    .scaleEffect(pulse.wrappedValue ? 1.60 : 1.0)
                    .animation(.easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false), value: pulse.wrappedValue)
                Circle()
                    .fill(LinearGradient(
                        colors: [color.opacity(0.14), color.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 70, height: 70)
                    .overlay(Circle().stroke(color.opacity(0.18), lineWidth: 1.2))
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(color.opacity(0.65))
            }
            .onAppear {
                pulse.wrappedValue = false
                pulseTask.wrappedValue?.cancel()
                pulseTask.wrappedValue = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    pulse.wrappedValue = true
                }
            }
            .onDisappear {
                pulseTask.wrappedValue?.cancel()
                pulse.wrappedValue = false
            }
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - 協定編輯

/// 協定的新增／編輯表單。
///
/// 「負責方」與「金額」是選填開關而不是永遠顯示的欄位——多數協定兩者都用不到
///（「今年不買車」既沒有負責方也沒有金額），永遠攤開會讓表單看起來比實際複雜。
/// 選了分類會依 suggestsParty / suggestsAmount 預先幫你打開對應開關，
/// 但仍可自由改：家事分工也可能有金額（請鐘點的費用）。
struct SpouseAgreementEditor: View {
    let memberId: UUID
    @State var agreement: SpouseAgreement

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    @State private var hasParty = false
    @State private var hasAmount = false
    @State private var hasCadence = false
    @State private var amountText = ""
    /// 進表單當下這則是不是全新的（用來決定標題與有沒有刪除鈕）
    @State private var isNew = false

    private var canSave: Bool {
        !agreement.title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("協定內容（例：今年不買車）", text: $agreement.title, axis: .vertical)
                    .lineLimit(2)
                Picker("分類", selection: $agreement.category) {
                    ForEach(SpouseAgreementCategory.allCases) { c in
                        Label(c.title, systemImage: c.icon).tag(c)
                    }
                }
                DatePicker("約定日期", selection: $agreement.agreedDate, displayedComponents: .date)
            } header: {
                Text("協定")
            }

            Section {
                Toggle("指定負責方", isOn: $hasParty)
                if hasParty {
                    Picker("負責方", selection: Binding(
                        get: { agreement.party ?? .both },
                        set: { agreement.party = $0 }
                    )) {
                        ForEach(SpouseAgreementParty.allCases) { p in
                            Label(p.title, systemImage: p.icon).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("分工")
            } footer: {
                Text("家事分工這類「誰負責什麼」的協定才需要。")
            }

            Section {
                Toggle("有金額", isOn: $hasAmount)
                if hasAmount {
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("金額", text: $amountText)
                            .keyboardType(.numberPad)
                    }
                }
                Toggle("有週期", isOn: $hasCadence)
                if hasCadence {
                    Picker("週期", selection: Binding(
                        get: { agreement.cadence ?? .monthly },
                        set: { agreement.cadence = $0 }
                    )) {
                        ForEach(SpouseAgreementCadence.allCases) { c in
                            Text(c.title).tag(c)
                        }
                    }
                }
            } header: {
                Text("金額與週期")
            } footer: {
                Text("例：每月家用各出三萬 → 金額 30000、週期每月。")
            }

            Section {
                Picker("狀態", selection: $agreement.status) {
                    ForEach(SpouseAgreementStatus.allCases) { st in
                        Text(st.title).tag(st)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("狀態")
            } footer: {
                Text("改成「已完成」或「已作廢」不會刪除紀錄，只會收進配偶頁的收合區塊裡。")
            }

            Section("詳細說明") {
                TextField("前因後果、細節條件…", text: $agreement.detail, axis: .vertical)
                    .lineLimit(5)
            }

            Section("備註") {
                TextField("選填備註", text: $agreement.note, axis: .vertical).lineLimit(3)
            }

            if !isNew {
                Section {
                    Button(role: .destructive) {
                        lifeStore.deleteAgreement(agreement.id, for: memberId)
                        dismiss()
                    } label: {
                        Label("刪除此協定", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle(isNew ? "新增協定" : "編輯協定")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("儲存") { save() }.disabled(!canSave)
            }
        }
        .onChange(of: agreement.category) { _, newValue in
            // 只在使用者還沒動過這兩個開關時才幫忙預設，
            // 不覆蓋已經明確打開／關閉的選擇。
            if agreement.party == nil { hasParty = newValue.suggestsParty }
            if agreement.amount == nil { hasAmount = newValue.suggestsAmount }
        }
        .onAppear {
            // 全新的一則：title 為空且不在既有清單裡
            let existing = lifeStore.familyMembers
                .first { $0.id == memberId }?.agreements ?? []
            isNew = !existing.contains { $0.id == agreement.id }
            hasParty = agreement.party != nil || (isNew && agreement.category.suggestsParty)
            hasAmount = agreement.amount != nil || (isNew && agreement.category.suggestsAmount)
            hasCadence = agreement.cadence != nil
            if let a = agreement.amount, a > 0 { amountText = String(Int(a)) }
        }
    }

    private func save() {
        var item = agreement
        item.title = item.title.trimmingCharacters(in: .whitespaces)
        item.detail = item.detail.trimmingCharacters(in: .whitespaces)
        item.note = item.note.trimmingCharacters(in: .whitespaces)
        // 開關關掉就一律清成 nil，不留上一次填過的殘值——
        // 否則關掉「有金額」再存檔，卡片副標仍會印出金額。
        item.party = hasParty ? (item.party ?? .both) : nil
        item.amount = hasAmount ? (Double(amountText).flatMap { $0 > 0 ? $0 : nil }) : nil
        item.cadence = hasCadence ? (item.cadence ?? .monthly) : nil
        lifeStore.upsertAgreement(item, for: memberId)
        dismiss()
    }
}
