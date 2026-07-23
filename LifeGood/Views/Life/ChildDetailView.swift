import SwiftUI
import PhotosUI
import MapKit

// MARK: - 美化紀錄（ChildDetailView）
// [2026-06 v1] 基礎美化：漸層英雄卡 / matchedGeometryEffect Tab / Capsule 側條段落標題 /
//              30pt 漸層圖示圓 / 彩色膠囊標籤 / 靜態 DateFormatter / contentAppeared 交錯動畫。
// [2026-06 v2] 進階美化（對齊 OverviewView / VariableExpenseView v4 規格）：
//   • headerCard → 玻璃光澤（white.opacity(0.18)→clear，top→center）+ 第三顆散景圓（55pt / blur 8）
//                  + RoundedRectangle stroke(.white.opacity(0.18), 0.75pt)
//                  + 角色 / 年齡 Capsule 加 stroke(.white.opacity(0.28–0.30), 0.6pt)
//   • 圖示圓升至 36pt（dailyRow / recordRow / consumptionRow / childGiftsSection sub）
//     + 新增 Circle stroke(accent.opacity(0.22), 1pt)；icon 字型 12→14pt
//   • 日期改為彩色 Capsule 徽章（accent tint + stroke）對齊 CareerView / SpouseResumeView 規格
//   • consumptionRow 分類 Capsule + stroke(orange.opacity(0.22), 0.6pt)
//   • childGiftsSection sub 圖示從純色 28pt 升至 36pt LinearGradient + stroke
//   • 段落分隔線 leading: 50→56（對齊 36pt 圖示 + 14pt padding + 6pt spacing）
// [2026-07 v3] 金額顯示量級統一：
//   • 私有 formatCurrency(_:) / Self.currencyFormatter 停用（純 NT$ 整數，高額時字串過長）
//     全面改用共用 Double.ntdWanString（FinanceModels.swift），支援萬/億智慧量級，
//     對齊 ResumeGiftSection / CareerView / EInvoiceSetupView 全 App 金額顯示規格。
//     影響範圍：childGiftsSection 合計與各 SocialSubCategory 小計、consumptionSection 合計、
//               consumptionRow 單筆金額。純顯示層變更，未動支出/禮金篩選與加總邏輯。
// [2026-07 v4] 空狀態補 CTA 按鈕：
//   • 新增 emptyRecordRow(accent:action:) 共用元件，dailySection／recordSection 的「尚無記錄」
//     從純文字改為「tray 圖示 + 文字 + 右側迷你新增膠囊按鈕」，按鈕採 accent 漸層底 + 陰影，
//     對齊 FamilyView v3 emptyMembersPlaceholder CTA 規格，縮小適配卡片內單行高度。
//   • consumptionSection 維持純文字空狀態（消費為連動同步、非本頁可手動新增，不適用 CTA）。
// [2026-07 v5] headerCard 三顆膠囊描邊節奏統一：
//   • 生日原本只是「calendar 圖示 + 純文字」、無底色無描邊，與角色/年齡膠囊質感不一致；
//     改為 Capsule 徽章（bg white.opacity(0.12) + stroke white.opacity(0.20), 0.6pt），
//     文字不透明度 0.78→0.85 補償底色後的可讀性，與角色(0.22/0.30)、年齡(0.16/0.25)
//     形成三段漸淡節奏（主要 → 次要 → 輔助資訊）。純視覺層調整，未動生日資料或年齡計算邏輯。
// [2026-07 v6] headerCard 右側大圖示圓補描邊：
//   • 雙層同心圓（86pt / 74pt）原本只有 fill、無 stroke，是卡片內唯一沒有邊框的圖形元素，
//     與同卡 RoundedRectangle 外框（0.18/0.75pt）、角色/年齡/生日三顆膠囊皆已有描邊不一致；
//     外圈補 stroke(.white.opacity(0.16), 0.75pt)、內圈補 stroke(.white.opacity(0.26), 1pt)，
//     對齊 dailyRow/recordRow 36pt 圖示圓已有的 Circle stroke(accent.opacity(0.22), 1pt) 規格節奏。
//   • 純視覺加強，未動任何年齡/生日計算或圖示邏輯。
// [2026-07 v7] 自訂 Tab 切換器補描邊 + 「還有 N 筆」溢出提示對齊全 App 規格：
//   • 自訂 Capsule Tab 切換器背景原本只有 fill(Color(.tertiarySystemFill))、無 stroke，
//     是本頁滾動內容中唯一沒有邊框的容器（headerCard/各 section 卡片皆已有 stroke）；
//     補 Capsule stroke(Color(.separator).opacity(0.15), 0.5pt) 呼應同頁其他容器描邊節奏。
//   • dailySection／consumptionSection 的「還有 N 筆…」原本是左側行內純文字，且標點不一致
//     （「筆...」三個句點 vs 「筆…」全形省略號）；統一改為「…」單字元，並改用水平置中
//     Capsule 膠囊徽章樣式，對齊 ResumeView.spendingSection／ResumeGiftSection／
//     OrganizationView／SpouseResumeView 全 App「還有 N 筆…」統一規格。
//   • 純視覺與標點統一，未動 prefix(20) 截斷邏輯或筆數計算。
//   （下次美化本元件時，可從這裡接著找其他可統一之處）

struct ChildDetailView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let childId: UUID
    @State private var addingType: ChildRecordType?
    @State private var editingRecord: ChildRecord?
    @State private var addingDailyType: DailyRecordType?
    @State private var editingDaily: DailyRecord?
    @State private var showPremiumAlert = false

    // 進場動畫旗標
    @State private var headerAppeared = false
    @State private var contentAppeared = false
    // matchedGeometryEffect：tab 切換指示器平滑滑動
    @Namespace private var tabNamespace

    // 靜態 DateFormatter 共用實例（避免每次 render 重新分配）
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f
    }()
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()

    enum DetailTab: String, CaseIterable {
        case daily = "日常"
        case life = "生涯"
    }
    @State private var detailTab: DetailTab = .life

    init(child: FamilyMember) {
        self.childId = child.id
    }

    private var child: FamilyMember {
        lifeStore.familyMembers.first(where: { $0.id == childId })
            ?? FamilyMember(role: .son)
    }

    private var displayName: String {
        if !child.chineseName.isEmpty { return child.chineseName }
        if !child.englishName.isEmpty { return child.englishName }
        return child.role.rawValue
    }

    private var ageString: String {
        guard let bd = child.birthday else { return "" }
        let c = Calendar.current.dateComponents([.year, .month], from: bd, to: Date())
        let y = c.year ?? 0, m = c.month ?? 0
        return y > 0 ? "\(y) 歲 \(m) 個月" : "\(m) 個月"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                        .opacity(headerAppeared ? 1 : 0)
                        .offset(y: headerAppeared ? 0 : 20)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                headerAppeared = true
                            }
                        }

                    // 自訂 Capsule Tab 切換器（matchedGeometryEffect 讓指示器平滑滑動）
                    HStack(spacing: 0) {
                        ForEach(DetailTab.allCases, id: \.self) { tab in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                                    detailTab = tab
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: tab == .daily ? "sun.max.fill" : "star.fill")
                                        .font(.caption2)
                                    Text(tab.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 9)
                                .foregroundStyle(detailTab == tab ? .white : .secondary)
                                .background {
                                    if detailTab == tab {
                                        Capsule()
                                            .fill(tabTint(tab))
                                            .matchedGeometryEffect(id: "detailTabIndicator", in: tabNamespace)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color(.separator).opacity(0.15), lineWidth: 0.5))
                    .padding(.horizontal)

                    if detailTab == .daily {
                        dailyContent
                    } else {
                        lifeContent
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("\(displayName) 履歷")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
            }
            .sheet(item: $addingType) { type in
                ChildRecordEditorSheet(childId: childId, type: type, editing: nil)
            }
            .sheet(item: $editingRecord) { rec in
                ChildRecordEditorSheet(childId: childId, type: rec.type, editing: rec)
            }
            .sheet(item: $addingDailyType) { type in
                DailyRecordEditorSheet(childId: childId, type: type, editing: nil)
            }
            .sheet(item: $editingDaily) { rec in
                DailyRecordEditorSheet(childId: childId, type: rec.type, editing: rec)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.12)) {
                    contentAppeared = true
                }
            }
            .onChange(of: detailTab) { _, _ in
                contentAppeared = false
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                    contentAppeared = true
                }
            }
        }
    }

    private func tabTint(_ tab: DetailTab) -> Color {
        switch tab {
        case .daily: return .blue
        case .life: return .orange
        }
    }

    // MARK: - 英雄資訊卡（漸層背景 + 散景裝飾圓）

    private var headerCard: some View {
        let isSon = child.role == .son
        let gradStart: Color = isSon
            ? Color(red: 0.25, green: 0.55, blue: 0.98)
            : Color(red: 0.96, green: 0.38, blue: 0.62)
        let gradEnd: Color = isSon
            ? Color(red: 0.14, green: 0.36, blue: 0.82)
            : Color(red: 0.78, green: 0.20, blue: 0.50)

        return HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                // 角色 + 年齡膠囊
                HStack(spacing: 6) {
                    Text(child.role.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(.white.opacity(0.22))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 0.6))
                    if !ageString.isEmpty {
                        Text(ageString)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(.white.opacity(0.16))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.6))
                    }
                }
                // 姓名
                Text(displayName)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                // 生日（calendar 圖示 + 日期文字 → Capsule 徽章，對齊角色/年齡膠囊描邊節奏）
                if let bd = child.birthday {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9, weight: .medium))
                        Text(Self.dateFormatter.string(from: bd))
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.20), lineWidth: 0.6))
                }
            }
            Spacer()
            // 右側大圖示圓（雙層同心圓製造層次 + 細邊框，對齊 dailyRow/recordRow 36pt 圖示圓
            // 已有的 Circle stroke 規格，避免本卡唯一沒有描邊的圖形元素）
            ZStack {
                Circle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 86, height: 86)
                Circle()
                    .stroke(.white.opacity(0.16), lineWidth: 0.75)
                    .frame(width: 86, height: 86)
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 74, height: 74)
                Circle()
                    .stroke(.white.opacity(0.26), lineWidth: 1)
                    .frame(width: 74, height: 74)
                Image(systemName: "figure.child.circle.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .padding(20)
        .background(
            ZStack {
                LinearGradient(
                    colors: [gradStart, gradEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 右上散景裝飾圓
                Circle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 130, height: 130)
                    .offset(x: 75, y: -50)
                    .blur(radius: 14)
                // 左下補光
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 80, height: 80)
                    .offset(x: -60, y: 50)
                    .blur(radius: 10)
                // 第三顆散景圓：中下補深，增加卡片立體層次
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 55, height: 55)
                    .offset(x: 8, y: 38)
                    .blur(radius: 8)
                // 玻璃光澤：頂部白色高光漸層，對齊 OverviewView monthlyBalanceCard 規格
                LinearGradient(
                    colors: [.white.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.18), lineWidth: 0.75))
        .shadow(color: gradEnd.opacity(0.42), radius: 18, x: 0, y: 9)
        .padding(.horizontal)
    }

    // MARK: - 日常頁面（含交錯進場動畫）

    @ViewBuilder
    private var dailyContent: some View {
        // childGifts（雙重 filter + sort 全支出）一次捕捉後共用，
        // 避免 isEmpty 判斷與 childGiftsSection 內部各自再算一次（原本 2 次 → 1 次）
        let gifts = childGifts
        ForEach(Array(DailyRecordType.allCases.enumerated()), id: \.element) { idx, type in
            dailySection(type)
                .opacity(contentAppeared ? 1 : 0)
                .offset(y: contentAppeared ? 0 : 14)
                .animation(
                    .spring(response: 0.45, dampingFraction: 0.82)
                        .delay(0.05 * Double(idx)),
                    value: contentAppeared
                )
        }
        // 消費（依本人名字連動到變動支出）
        consumptionSection
            .opacity(contentAppeared ? 1 : 0)
            .offset(y: contentAppeared ? 0 : 14)
            .animation(
                .spring(response: 0.45, dampingFraction: 0.82)
                    .delay(0.05 * Double(DailyRecordType.allCases.count)),
                value: contentAppeared
            )
        // 收到的禮金（依本人名字連動到 .social 變動支出收受人）
        if !gifts.isEmpty {
            childGiftsSection(gifts)
                .opacity(contentAppeared ? 1 : 0)
                .offset(y: contentAppeared ? 0 : 14)
                .animation(
                    .spring(response: 0.45, dampingFraction: 0.82)
                        .delay(0.05 * Double(DailyRecordType.allCases.count + 1)),
                    value: contentAppeared
                )
        }
    }

    /// 變動支出 .social 中將兒女列為收受人的紀錄
    private var childGifts: [Expense] {
        let target = child.chineseName
        guard !target.isEmpty else { return [] }
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

    private func childGiftsSection(_ gifts: [Expense]) -> some View {
        let total = gifts.reduce(0) { $0 + $1.amount }
        // 依社交子分類一次分桶（O(n)），取代原本 ForEach 內對 gifts 逐分類各 filter 一次（O(分類數 × n)），
        // 對齊 FamilyMembersResumeView.memberGiftsSection 同型修復；無子分類的項目不歸類到任何分類列
        var grouped: [SocialSubCategory: [Expense]] = [:]
        for e in gifts {
            if let sub = e.socialSubCategory {
                grouped[sub, default: []].append(e)
            }
        }
        return VStack(alignment: .leading, spacing: 0) {
            // 段落標題：Capsule 漸層側條 + 計數膠囊 + 合計
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.pink, Color.pink.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Image(systemName: "gift.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.pink)
                Text("收到的禮金")
                    .font(.subheadline.weight(.semibold))
                Text("\(gifts.count) 筆")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.pink)
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                    .background(Color.pink.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.pink.opacity(0.22), lineWidth: 0.6))
                Spacer()
                Text(total.ntdWanString)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.pink)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ForEach(SocialSubCategory.allCases) { sub in
                let items = grouped[sub] ?? []
                if !items.isEmpty {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.pink.opacity(0.22), Color.pink.opacity(0.09)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 36, height: 36)
                            Circle()
                                .stroke(Color.pink.opacity(0.22), lineWidth: 1)
                                .frame(width: 36, height: 36)
                            Image(systemName: sub.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.pink)
                        }
                        Text(sub.rawValue).font(.subheadline)
                        Spacer()
                        Text("\(items.count) 筆")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(items.reduce(0) { $0 + $1.amount }.ntdWanString)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.pink)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    Rectangle()
                        .fill(Color(.separator).opacity(0.20))
                        .frame(height: 0.5)
                        .padding(.leading, 56)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.pink.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }


    private func dailySection(_ type: DailyRecordType) -> some View {
        let accent = dailyColor(type)
        let items = child.dailyRecords.filter { $0.type == type }.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 0) {
            // 段落標題：Capsule 側條 + 彩色圖示 + 標題 + 計數膠囊 + 新增按鈕
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Image(systemName: type.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                Text(type.rawValue)
                    .font(.subheadline.weight(.semibold))
                if !items.isEmpty {
                    Text("\(items.count) 筆")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(accent.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                }
                Spacer()
                Button {
                    if subscription.isPremium { addingDailyType = type }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if items.isEmpty {
                emptyRecordRow(accent: accent) {
                    if subscription.isPremium { addingDailyType = type }
                    else { showPremiumAlert = true }
                }
            } else {
                ForEach(Array(items.prefix(20).enumerated()), id: \.element.id) { idx, rec in
                    Button {
                        if subscription.isPremium { editingDaily = rec }
                        else { showPremiumAlert = true }
                    } label: {
                        dailyRow(rec)
                    }
                    .buttonStyle(.plain)
                    if idx < min(items.count, 20) - 1 {
                        Rectangle()
                            .fill(Color(.separator).opacity(0.20))
                            .frame(height: 0.5)
                            .padding(.leading, 56)
                    }
                }
                if items.count > 20 {
                    overflowCountBadge(items.count - 20)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accent.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    private func dailyRow(_ rec: DailyRecord) -> some View {
        let accent = dailyColor(rec.type)
        return HStack(spacing: 12) {
            // 36pt 漸層圖示圓 + stroke（v2 升級，對齊 VariableExpenseView ExpenseRow 規格）
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.22), accent.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Circle()
                    .stroke(accent.opacity(0.22), lineWidth: 1)
                    .frame(width: 36, height: 36)
                Image(systemName: rec.type.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                switch rec.type {
                case .milk:
                    HStack(spacing: 6) {
                        if let brand = rec.milkBrand, !brand.isEmpty {
                            Text(brand).font(.subheadline.weight(.medium))
                        }
                        if let ml = rec.mlAmount, ml > 0 {
                            // ml 數值改為彩色膠囊標籤
                            Text("\(Int(ml)) ml")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(accent)
                                .clipShape(Capsule())
                        }
                    }
                case .food:
                    HStack(spacing: 6) {
                        if let name = rec.foodName, !name.isEmpty {
                            Text(name).font(.subheadline.weight(.medium))
                        }
                        if let ml = rec.mlAmount, ml > 0 {
                            Text("\(Int(ml)) ml")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(accent)
                                .clipShape(Capsule())
                        }
                    }
                case .sleep:
                    if let end = rec.sleepEnd {
                        let dur = end.timeIntervalSince(rec.date) / 3600
                        Text(String(format: "%@ ~ %@（%.1f 小時）",
                                    Self.timeFormatter.string(from: rec.date),
                                    Self.timeFormatter.string(from: end),
                                    dur))
                            .font(.subheadline.weight(.medium))
                    } else {
                        Text(Self.timeFormatter.string(from: rec.date))
                            .font(.subheadline.weight(.medium))
                    }
                }
                Text(Self.dateTimeFormatter.string(from: rec.date))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(accent.opacity(0.72))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(accent.opacity(0.08))
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func dailyColor(_ type: DailyRecordType) -> Color {
        switch type {
        case .milk: return .blue
        case .food: return .green
        case .sleep: return .indigo
        }
    }

    // MARK: - 消費（與兒女連動的變動支出）

    private var consumptionExpenses: [Expense] {
        let name = child.chineseName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return [] }
        return expenseStore.expenses
            .filter { $0.expenseType == .variable }
            .filter { e in
                guard let raw = e.diningMember, !raw.isEmpty else { return false }
                let names = raw.split(separator: "、").map { String($0).trimmingCharacters(in: .whitespaces) }
                return names.contains(name)
            }
            .sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private var consumptionSection: some View {
        // consumptionExpenses（雙重 filter + sort，O(n log n)）一次捕捉後全段共用，
        // 避免 section 內 count / isEmpty / reduce / prefix 各自觸發重複計算（原本 8 次 → 1 次）
        let exps = consumptionExpenses
        VStack(alignment: .leading, spacing: 0) {
            // 段落標題：Capsule 漸層側條 + 計數膠囊 + 合計
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                Text("消費")
                    .font(.subheadline.weight(.semibold))
                if exps.count > 0 {
                    Text("\(exps.count) 筆")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.red.opacity(0.22), lineWidth: 0.6))
                }
                Spacer()
                if !exps.isEmpty {
                    let total = exps.reduce(0) { $0 + $1.amount }
                    Text(total.ntdWanString)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if exps.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(child.chineseName.isEmpty
                         ? "尚未設定姓名，請先填寫中文名字"
                         : "尚無連動的消費紀錄")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            } else {
                ForEach(Array(exps.prefix(20).enumerated()), id: \.element.id) { idx, e in
                    consumptionRow(e)
                    if idx < min(exps.count, 20) - 1 {
                        Rectangle()
                            .fill(Color(.separator).opacity(0.20))
                            .frame(height: 0.5)
                            .padding(.leading, 56)
                    }
                }
                if exps.count > 20 {
                    overflowCountBadge(exps.count - 20)
                }
            }
            if !child.chineseName.isEmpty {
                Rectangle()
                    .fill(Color(.separator).opacity(0.20))
                    .frame(height: 0.5)
                    .padding(.horizontal, 14)
                Text("變動支出中將「\(child.chineseName)」加入人員會自動同步到此")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.red.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    private func consumptionRow(_ e: Expense) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // 36pt 漸層圖示圓 + stroke（v2 升級）
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.22), Color.orange.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Circle()
                    .stroke(Color.orange.opacity(0.22), lineWidth: 1)
                    .frame(width: 36, height: 36)
                Image(systemName: e.variableCategory?.icon ?? "questionmark.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(e.title.isEmpty ? (e.variableCategory?.rawValue ?? "未分類") : e.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(Self.shortDateFormatter.string(from: e.date))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                    if let cat = e.variableCategory {
                        Text(cat.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.orange.opacity(0.22), lineWidth: 0.6))
                    }
                    if let raw = e.diningMember, !raw.isEmpty {
                        Text(raw).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer()
            Text(e.amount.ntdWanString)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    // MARK: - 生涯頁面

    @ViewBuilder
    private var lifeContent: some View {
        ForEach(Array(ChildRecordType.allCases.enumerated()), id: \.element) { idx, type in
            Group {
                // 疫苗章節改為「接種時程規劃」：依生日列出所有應施打疫苗，填入施打日期即完成，逾期自動標示
                if type == .vaccination {
                    ChildVaccineScheduleView(childId: childId)
                } else {
                    recordSection(type)
                }
            }
            .opacity(contentAppeared ? 1 : 0)
            .offset(y: contentAppeared ? 0 : 14)
            .animation(
                .spring(response: 0.45, dampingFraction: 0.82)
                    .delay(0.05 * Double(idx)),
                value: contentAppeared
            )
        }
    }

    // MARK: - 章節（生涯）

    private func recordSection(_ type: ChildRecordType) -> some View {
        let accent = colorFor(type)
        let items = child.childRecords.filter { $0.type == type }.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 0) {
            // 段落標題：Capsule 漸層側條 + 彩色圖示 + 標題 + 計數膠囊 + 新增按鈕
            HStack(spacing: 10) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 18)
                Image(systemName: type.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                Text(type.rawValue)
                    .font(.subheadline.weight(.semibold))
                if !items.isEmpty {
                    Text("\(items.count) 筆")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(accent.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                }
                Spacer()
                Button {
                    if subscription.isPremium { addingType = type }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if items.isEmpty {
                emptyRecordRow(accent: accent) {
                    if subscription.isPremium { addingType = type }
                    else { showPremiumAlert = true }
                }
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, rec in
                    recordRow(rec)
                    if idx < items.count - 1 {
                        Rectangle()
                            .fill(Color(.separator).opacity(0.20))
                            .frame(height: 0.5)
                            .padding(.leading, 56)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accent.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func recordRow(_ rec: ChildRecord) -> some View {
        let accent = colorFor(rec.type)
        Button {
            if subscription.isPremium { editingRecord = rec }
            else { showPremiumAlert = true }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                // 36pt 漸層圖示圓 + stroke（v2 升級）
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.22), accent.opacity(0.09)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Circle()
                        .stroke(accent.opacity(0.22), lineWidth: 1)
                        .frame(width: 36, height: 36)
                    Image(systemName: rec.type.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(primaryText(rec)).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        if rec.type == .allergy, let sev = rec.severity {
                            // Capsule 標籤（對齊 ChildrenResumeView 規格，取代 RoundedRectangle(cornerRadius:3)）
                            Text(sev.rawValue).font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(severityColor(sev).opacity(0.15))
                                .foregroundStyle(severityColor(sev))
                                .clipShape(Capsule())
                        }
                        if rec.type == .vaccination, let dose = rec.dose, !dose.isEmpty {
                            Text(dose).font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12)).foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }
                    if rec.type == .growth {
                        HStack(spacing: 8) {
                            if let h = rec.heightCm, h > 0 { Text(String(format: "身高 %.1f cm", h)).font(.caption).foregroundStyle(.secondary) }
                            if let w = rec.weightKg, w > 0 { Text(String(format: "體重 %.1f kg", w)).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    HStack(spacing: 6) {
                        Text(Self.dateFormatter.string(from: rec.date))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accent.opacity(0.80))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(accent.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(accent.opacity(0.20), lineWidth: 0.5))
                        if !rec.detail.isEmpty {
                            Text(rec.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }

                // 照片放在 row 右側，依原比例顯示（最大 80×80）
                if rec.photoFileName != nil, let url = rec.sketchURL ?? rec.photoURL {
                    // 用既有的 AsyncLocalImage 背景讀檔快取，避免清單捲動／其他列狀態
                    // 變化造成整個 body 重新求值時，同步在主執行緒重讀＋重解碼每一列的照片。
                    AsyncLocalImage(url: url) { img, _ in
                        if let img {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 80, maxHeight: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func primaryText(_ rec: ChildRecord) -> String {
        rec.type == .growth ? Self.dateFormatter.string(from: rec.date) : (rec.title.isEmpty ? rec.type.rawValue : rec.title)
    }

    private func colorFor(_ type: ChildRecordType) -> Color {
        switch type {
        case .vaccination: return .blue; case .allergy: return .red; case .growth: return .green
        case .medical: return .orange; case .education: return .purple
        case .hobby: return .pink; case .memorable: return .yellow
        }
    }

    private func severityColor(_ s: AllergySeverity) -> Color {
        switch s { case .mild: return .yellow; case .moderate: return .orange; case .severe: return .red }
    }

    // MARK: - 章節空狀態（tray 圖示 + 文字 + 迷你 CTA 按鈕）
    // [2026-07 v4] 對齊 FamilyView v3 emptyMembersPlaceholder 的漸層膠囊 CTA 規格（accent 漸層底 + 陰影），
    // 縮小成適合卡片內單行使用的尺寸，取代原本純文字「尚無記錄」；dailySection / recordSection 共用。
    // consumptionSection 空狀態不適用（消費為連動同步、非本頁可手動新增，維持純文字）。
    private func emptyRecordRow(accent: Color, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("尚無記錄")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button(action: action) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("新增")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: accent.opacity(0.30), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    // MARK: - 「還有 N 筆…」溢出提示（水平置中 Capsule 膠囊徽章）
    // [2026-07 v7] 對齊 ResumeView.spendingSection／ResumeGiftSection／OrganizationView／
    // SpouseResumeView 全 App「還有 N 筆…」統一規格；dailySection／consumptionSection 共用。
    private func overflowCountBadge(_ count: Int) -> some View {
        HStack {
            Spacer()
            Text("還有 \(count) 筆…")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 3.5)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

}

// MARK: - 日常記錄編輯 Sheet

struct DailyRecordEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let childId: UUID
    let type: DailyRecordType
    var editing: DailyRecord?

    @State private var date = Date()
    @State private var milkBrand = ""
    @State private var mlText = ""
    @State private var foodName = ""
    @State private var sleepEnd = Date()
    @State private var note = ""
    @State private var isSaving = false

    private var canSave: Bool {
        switch type {
        case .milk: return (Double(mlText) ?? 0) > 0
        case .food: return !foodName.trimmingCharacters(in: .whitespaces).isEmpty
        case .sleep: return true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch type {
                case .milk:
                    Section("喝奶記錄") {
                        HStack { Text("時間"); Spacer(); FiveMinuteDateTimePicker(selection: $date).fixedSize() }
                        TextField("奶粉品牌（選填）", text: $milkBrand)
                        HStack { TextField("ml 數", text: $mlText).keyboardType(.numberPad); Text("ml").foregroundStyle(.secondary) }
                    }
                case .food:
                    Section("食物記錄") {
                        HStack { Text("時間"); Spacer(); FiveMinuteDateTimePicker(selection: $date).fixedSize() }
                        TextField("食物名稱", text: $foodName)
                        HStack { TextField("ml 數（選填）", text: $mlText).keyboardType(.numberPad); Text("ml").foregroundStyle(.secondary) }
                    }
                case .sleep:
                    Section("睡眠記錄") {
                        HStack { Text("入睡時間"); Spacer(); FiveMinuteDateTimePicker(selection: $date).fixedSize() }
                        HStack { Text("起床時間"); Spacer(); FiveMinuteDateTimePicker(selection: $sleepEnd, minimumDate: date).fixedSize() }
                        if sleepEnd > date {
                            let hours = sleepEnd.timeIntervalSince(date) / 3600
                            HStack {
                                Text("睡眠時長").foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f 小時", hours)).foregroundStyle(.blue)
                            }
                        }
                    }
                }
                Section("備註") {
                    TextField("選填", text: $note, axis: .vertical).lineLimit(2)
                }
                if editing != nil {
                    Section {
                        Button(role: .destructive) { delete() } label: { Label("刪除", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯\(type.rawValue)" : "新增\(type.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green).disabled(!canSave || isSaving)
                }
            }
            .onAppear { loadEditing() }
        }
    }

    private func loadEditing() {
        guard let e = editing else {
            // 新育兒記錄屬「即時紀錄」：預設用當下時間對齊到 5 分鐘，不套排程 09:30 規則
            date = FiveMinuteDateTimePicker.roundedToFiveMinutes(Date())
            sleepEnd = date
            return
        }
        date = e.date
        milkBrand = e.milkBrand ?? ""
        mlText = e.mlAmount.map { $0 > 0 ? String(format: "%.0f", $0) : "" } ?? ""
        foodName = e.foodName ?? ""
        sleepEnd = e.sleepEnd ?? Date()
        note = e.note
    }

    private func save() {
        guard !isSaving else { return }
        guard var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { dismiss(); return }
        isSaving = true
        let rec = DailyRecord(
            id: editing?.id ?? UUID(), type: type, date: date,
            milkBrand: type == .milk ? milkBrand.trimmingCharacters(in: .whitespaces) : nil,
            mlAmount: (type == .milk || type == .food) ? Double(mlText) : nil,
            foodName: type == .food ? foodName.trimmingCharacters(in: .whitespaces) : nil,
            sleepEnd: type == .sleep ? sleepEnd : nil,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        if let idx = member.dailyRecords.firstIndex(where: { $0.id == rec.id }) {
            member.dailyRecords[idx] = rec
        } else {
            member.dailyRecords.append(rec)
        }
        lifeStore.update(member)
        dismiss()
    }

    private func delete() {
        guard let e = editing, var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { dismiss(); return }
        member.dailyRecords.removeAll { $0.id == e.id }
        lifeStore.update(member)
        dismiss()
    }
}

// MARK: - 兒女記錄編輯 Sheet

struct ChildRecordEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let childId: UUID
    let type: ChildRecordType
    var editing: ChildRecord?

    @State private var title = ""
    @State private var detail = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var dose = ""
    @State private var severity: AllergySeverity = .mild

    // 就醫 / 接種院所 自動完成
    @StateObject private var clinicCompleter = RestaurantSearchCompleter()
    @StateObject private var locationProvider = LocationProvider.shared
    @FocusState private var detailFieldFocused: Bool
    @State private var clinicSuppressNextUpdate: Bool = false
    @State private var clinicExpandedSuggestions: Bool = false
    @State private var clinicDebounceTask: Task<Void, Never>? = nil
    // 過往就醫紀錄的本地比對也要跟 Apple Maps 搜尋走同一組 300ms 防抖後的字串，
    // 避免打字時本地建議先跳、0.3 秒後網路建議才到造成清單重排兩次的閃爍感。
    @State private var clinicDebouncedQuery: String = ""
    @State private var photoFileName: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var sketchMode = true
    @State private var previewImage: UIImage?
    /// 進入編輯畫面時的原始照片檔名，用來判斷儲存/取消時該刪哪個檔案（見 save()/取消按鈕註解）。
    @State private var originalPhotoFileName: String?
    // 選取照片是非同步的（iCloud 圖片可能要等幾秒），若使用者在等待期間又重新選了一次，
    // 較慢完成的前一次選取不該覆蓋較新的結果；用世代編號判斷完成時是否仍是最新一次選取
    // （同型修復見 OrgPersonEditor.photoLoadGeneration）。
    @State private var photoLoadGeneration = 0
    @State private var isSaving = false

    private var canSave: Bool {
        switch type {
        case .growth: return (Double(heightText) ?? 0) > 0 || (Double(weightText) ?? 0) > 0
        default: return !title.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch type {
                case .vaccination: vaccinationFields
                case .allergy: allergyFields
                case .growth: growthFields
                case .medical: medicalFields
                case .education: educationFields
                case .hobby: hobbyFields
                case .memorable: memorableFields
                }
                Section("日期") { DatePicker("日期", selection: $date, displayedComponents: .date) }
                Section("備註") { TextField("選填", text: $note, axis: .vertical).lineLimit(2...5) }

                Section("插入圖片") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack {
                            Image(systemName: "photo")
                            Text(photoFileName == nil ? "選擇圖片" : "更換圖片")
                            Spacer()
                            if photoFileName != nil {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }

                    if photoFileName != nil {
                        Toggle("轉為素描畫", isOn: $sketchMode)
                            .onChange(of: sketchMode) { _, _ in regeneratePreview() }
                    }

                    if let img = previewImage {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if photoFileName != nil {
                        Button(role: .destructive) {
                            // 讓任何仍在進行中的照片載入 Task 過期，避免它稍後才完成、
                            // 把剛移除的照片又重新蓋回來。
                            photoLoadGeneration += 1
                            // 不在這裡立刻刪檔：使用者移除圖片後若按「取消」，原圖應該保持不變
                            // （取消不該有副作用）。實際刪除延到 save() 依最終結果判斷。
                            // 但若移除的是本次 session 剛選的新照片（尚未儲存），要立刻清掉，
                            // 否則變成孤兒檔案。
                            if let name = photoFileName, name != originalPhotoFileName {
                                ChildRecord.deletePhoto(name)
                            }
                            photoFileName = nil; previewImage = nil
                        } label: {
                            Label("移除圖片", systemImage: "xmark.circle")
                        }
                    }
                }

                if editing != nil {
                    Section { Button(role: .destructive) { delete() } label: { Label("刪除此記錄", systemImage: "trash") } }
                }
            }
            .navigationTitle(editing != nil ? "編輯\(type.rawValue)" : "新增\(type.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        // 選了新照片但按取消：新照片檔案已寫入磁碟卻不會被任何紀錄引用，
                        // 要在這裡清掉，避免變成永久孤兒檔案（同型修復見 RenovationPhotoEditor.cancel()）。
                        // 原本的照片（originalPhotoFileName）維持不動，因為 onChange 已改為不再
                        // 立刻刪除舊檔，取消時原檔仍完整保留。
                        if let current = photoFileName, current != originalPhotoFileName {
                            ChildRecord.deletePhoto(current)
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }.bold().foregroundStyle(.green).disabled(!canSave || isSaving)
                }
            }
            .onAppear { loadEditing() }
            .onChange(of: photoItem) { _, newItem in
                // 連續選兩張照片（例如第一張是要等 iCloud 下載的慢速圖，選完又反悔重選）
                // 會有兩個 Task 並行跑 loadTransferable，先前沒有世代編號守衛時，較慢完成的
                // 那個會用「self.photoItem」重新讀到的已是新選取，導致兩個 Task 存的其實是
                // 同一張新照片，且哪個後寫入 photoFileName 全憑完成順序決定，較早選的舊照片
                // 反而可能覆蓋較新的選擇。改用世代編號，只有仍是最新一次選取的 Task 才套用結果。
                photoLoadGeneration += 1
                let generation = photoLoadGeneration
                Task {
                    guard let newItem, let data = try? await newItem.loadTransferable(type: Data.self) else { return }
                    // 編輯既有記錄時 editing.id 不變，若沿用它當檔名，換照片會同路徑覆寫、photoFileName
                    // 字串不變，清單縮圖用的 AsyncLocalImage 依 url 判斷是否重讀，url 沒變就不會重讀，
                    // 換照片後清單頭像停留在舊圖（同類 bug 已在 BusinessCard/OrgPerson/FamilyAlbumPhoto
                    // 修復，改用全新 UUID 檔名）。素描檔名一律跟著同一個新 photoId 走，兩者仍保持配對。
                    let photoId = UUID()
                    let savedName = ChildRecord.savePhoto(data, id: photoId)
                    let origImage = UIImage(data: data)
                    // 素描版：CIContext 建立與 GPU 渲染移到背景執行緒，避免阻塞主執行緒
                    if let orig = origImage {
                        let sketched = await Task.detached(priority: .userInitiated) {
                            ChildRecord.applySketchEffect(orig)
                        }.value
                        if let sketched, let sketchData = sketched.jpegData(compressionQuality: 0.85) {
                            _ = ChildRecord.saveSketch(sketchData, id: photoId)
                        }
                    }
                    await MainActor.run {
                        guard generation == photoLoadGeneration else {
                            // 已被更新的選取取代：這次白存的照片/素描檔沒有任何欄位會再引用到，
                            // 立刻清掉避免孤兒檔案；不動任何已顯示的狀態。
                            if let savedName { ChildRecord.deletePhoto(savedName) }
                            return
                        }
                        // 換照片時不立刻刪舊檔：使用者選了新照片後若按「取消」，若這裡就刪掉
                        // originalPhotoFileName，該檔案會被永久刪除卻沒有任何紀錄真的改用新照片
                        // （取消不該有副作用）。改成只在 save() 依最終結果與原始檔名的差異決定要刪誰。
                        // 若這是本次 session 已經選過一次的新照片（尚未儲存），要先清掉，否則連續換兩次
                        // 照片會留下第一次選的孤兒檔案。
                        if let previous = photoFileName, previous != originalPhotoFileName {
                            ChildRecord.deletePhoto(previous)
                        }
                        photoFileName = savedName
                        previewImage = sketchMode ? loadSketchOrOrig() : origImage
                    }
                }
            }
            // 避免 300ms 防抖期間關閉表單後，Task 仍在背景驅動診所搜尋（對齊 AddExpenseView 的修復）
            .onDisappear { clinicDebounceTask?.cancel() }
        }
    }

    /// 素描檔名一律由 photoFileName 推導（與 ChildRecord.sketchURL 邏輯一致），
    /// 不可用另外亂數的 UUID，否則新增記錄時三處各自產生的 id 對不上，存的素描永遠找不到。
    private func sketchFileName(for photoName: String) -> String {
        photoName.replacingOccurrences(of: ".jpg", with: "_sketch.jpg")
    }

    private func loadSketchOrOrig() -> UIImage? {
        guard let name = photoFileName else { return nil }
        let sketchPath = ChildRecord.photosDirectory.appendingPathComponent(sketchFileName(for: name))
        if let data = try? Data(contentsOf: sketchPath), let img = UIImage(data: data) { return img }
        guard let data = try? Data(contentsOf: ChildRecord.photosDirectory.appendingPathComponent(name)),
              let img = UIImage(data: data) else { return nil }
        return img
    }

    private func regeneratePreview() {
        guard let name = photoFileName else { return }
        let sketchName = sketchFileName(for: name)

        if sketchMode {
            let sketchPath = ChildRecord.photosDirectory.appendingPathComponent(sketchName)
            if !FileManager.default.fileExists(atPath: sketchPath.path) {
                // 素描版不存在才需要讀原圖：避免每次切換 Toggle 都做一次不必要的主執行緒磁碟讀取 + JPEG 解碼
                let origPath = ChildRecord.photosDirectory.appendingPathComponent(name)
                guard let data = try? Data(contentsOf: origPath), let origImage = UIImage(data: data) else { return }
                // GPU 運算移到背景執行緒，完成後再更新預覽
                Task {
                    let sketched = await Task.detached(priority: .userInitiated) {
                        ChildRecord.applySketchEffect(origImage)
                    }.value
                    if let sketched, let sketchData = sketched.jpegData(compressionQuality: 0.85) {
                        try? sketchData.write(to: sketchPath)
                        PhotoCloudSync.upload(directory: "ChildRecordPhotos", fileName: sketchName)
                    }
                    // 運算期間使用者可能已把 Toggle 切回原圖：不檢查會讓這裡把已經正確顯示的
                    // 原圖預覽，事後又覆蓋回素描版，畫面與目前 Toggle 狀態不一致。
                    guard sketchMode, photoFileName == name else { return }
                    previewImage = loadSketchOrOrig()
                }
            } else {
                previewImage = loadSketchOrOrig()
            }
        } else {
            let origPath = ChildRecord.photosDirectory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: origPath), let origImage = UIImage(data: data) else { return }
            previewImage = origImage
        }
    }

    private var vaccinationFields: some View {
        Section("疫苗資訊") {
            TextField("疫苗名稱（如：五合一）", text: $title)
            TextField("劑次（如：第 1 劑、追加）", text: $dose)
            clinicAutocompleteField(label: "接種院所（選填）")
        }
    }
    private var allergyFields: some View {
        Section("過敏資訊") {
            TextField("過敏原（如：花生、牛奶）", text: $title)
            Picker("嚴重度", selection: $severity) { ForEach(AllergySeverity.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            TextField("反應描述（如：紅疹、氣喘）", text: $detail, axis: .vertical).lineLimit(1...3)
        }
    }
    private var growthFields: some View {
        Section("成長數據") {
            HStack { TextField("身高", text: $heightText).keyboardType(.decimalPad); Text("cm").foregroundStyle(.secondary) }
            HStack { TextField("體重", text: $weightText).keyboardType(.decimalPad); Text("kg").foregroundStyle(.secondary) }
        }
    }
    private var medicalFields: some View {
        Section("就醫資訊") {
            TextField("症狀/診斷", text: $title)
            clinicAutocompleteField(label: "院所（選填）")
        }
    }

    // MARK: - 院所自動完成（適用於就醫 / 疫苗接種院所）

    @ViewBuilder
    private func clinicAutocompleteField(label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "cross.case.fill")
                    .foregroundStyle(.red)
                    .frame(width: 18)
                TextField(label, text: $detail)
                    .focused($detailFieldFocused)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                if !detail.isEmpty {
                    Button {
                        detail = ""
                        clinicExpandedSuggestions = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if detailFieldFocused {
                clinicSuggestionsList
            }
        }
        .onAppear {
            LocationProvider.shared.requestIfNeeded()
            clinicCompleter.setRegion(LocationProvider.shared.searchRegion)
            clinicDebouncedQuery = detail
            if !detail.isEmpty { clinicCompleter.queryFragment = detail }
        }
        .onChange(of: detail) { _, newValue in
            if clinicSuppressNextUpdate {
                clinicSuppressNextUpdate = false
                clinicDebouncedQuery = newValue
                return
            }
            // 300ms 防抖，對齊 AddExpenseView / VariableExpenseView 院所/餐廳搜尋規格，
            // 避免每次按鍵都即時發出 MKLocalSearchCompleter 網路請求；過往紀錄本地比對
            // 也一併等防抖後才更新，避免本地建議先跳、網路建議 0.3 秒後才到造成清單重排兩次。
            clinicDebounceTask?.cancel()
            clinicDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                clinicCompleter.queryFragment = newValue
                clinicDebouncedQuery = newValue
                clinicExpandedSuggestions = false
            }
        }
        .onChange(of: locationProvider.lastLocation) { _, _ in
            clinicCompleter.setRegion(LocationProvider.shared.searchRegion)
            if !detail.isEmpty { clinicCompleter.queryFragment = detail }
        }
    }

    @ViewBuilder
    private var clinicSuggestionsList: some View {
        let all = allClinicSuggestions
        if !all.isEmpty {
            let limit = 20
            let visible = clinicExpandedSuggestions ? all : Array(all.prefix(limit))
            let hiddenCount = max(0, all.count - limit)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visible) { item in
                        Button { applyClinicSuggestion(item) } label: {
                            clinicSuggestionRow(item)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 44)
                    }
                    if !clinicExpandedSuggestions && hiddenCount > 0 {
                        Button {
                            clinicExpandedSuggestions = true
                        } label: {
                            HStack {
                                Image(systemName: "chevron.down.circle.fill").foregroundStyle(.blue)
                                Text("顯示更多 (\(hiddenCount))")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.blue)
                                Spacer()
                            }
                            .padding(.vertical, 10).padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else if clinicExpandedSuggestions && all.count > limit {
                        Button {
                            clinicExpandedSuggestions = false
                        } label: {
                            HStack {
                                Image(systemName: "chevron.up.circle.fill").foregroundStyle(.secondary)
                                Text("收合")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 10).padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 240)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    private func clinicSuggestionRow(_ item: ClinicSuggestion) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(item.iconColor.opacity(0.15)).frame(width: 28, height: 28)
                Image(systemName: item.iconName)
                    .foregroundStyle(item.iconColor)
                    .font(.caption)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "arrow.up.left").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    /// 合併所有小孩過往就醫 / 接種院所 + Apple Maps POI（醫療類）
    private var allClinicSuggestions: [ClinicSuggestion] {
        let q = clinicDebouncedQuery.trimmingCharacters(in: .whitespaces).lowercased()
        var seen: Set<String> = []
        var output: [ClinicSuggestion] = []

        let allRecords: [ChildRecord] = lifeStore.familyMembers.flatMap { $0.childRecords }
        let medicalAndVaccination = allRecords.filter {
            $0.type == .medical || $0.type == .vaccination
        }
        let pastDetails: [String] = medicalAndVaccination
            .map { $0.detail.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for d in pastDetails {
            if !q.isEmpty && !d.lowercased().contains(q) { continue }
            let key = "past|\(d.lowercased())"
            if seen.contains(key) { continue }
            seen.insert(key)
            output.append(ClinicSuggestion(
                id: key, source: .past, title: d, subtitle: "", completion: nil
            ))
        }

        for c in clinicCompleter.results {
            let key = "apple|\(c.title.lowercased())|\(c.subtitle.lowercased())"
            if seen.contains(key) { continue }
            seen.insert(key)
            output.append(ClinicSuggestion(
                id: key, source: .apple, title: c.title, subtitle: c.subtitle, completion: c
            ))
        }

        return output
    }

    private func applyClinicSuggestion(_ item: ClinicSuggestion) {
        clinicSuppressNextUpdate = true
        switch item.source {
        case .past:
            detail = item.title
        case .apple:
            // Apple Maps 帶「名稱 - 地址」較完整
            if item.subtitle.isEmpty {
                detail = item.title
            } else {
                detail = "\(item.title) - \(item.subtitle)"
            }
        }
        clinicExpandedSuggestions = false
        detailFieldFocused = false
    }
    private var educationFields: some View {
        Section("教育里程碑") { TextField("事件", text: $title); TextField("學校或單位（選填）", text: $detail) }
    }
    private var hobbyFields: some View {
        Section("興趣才藝") { TextField("項目", text: $title); TextField("描述（選填）", text: $detail, axis: .vertical).lineLimit(1...3) }
    }
    private var memorableFields: some View {
        Section("紀念時刻") { TextField("事件", text: $title); TextField("描述（選填）", text: $detail, axis: .vertical).lineLimit(1...3) }
    }

    private func loadEditing() {
        guard let e = editing else { return }
        title = e.title; detail = e.detail; date = e.date; note = e.note
        if let h = e.heightCm, h > 0 { heightText = String(format: "%g", h) }
        if let w = e.weightKg, w > 0 { weightText = String(format: "%g", w) }
        dose = e.dose ?? ""; severity = e.severity ?? .mild
        photoFileName = e.photoFileName
        originalPhotoFileName = e.photoFileName
        if e.photoFileName != nil {
            previewImage = sketchMode ? loadSketchOrOrig() : {
                guard let name = e.photoFileName,
                      let data = try? Data(contentsOf: ChildRecord.photosDirectory.appendingPathComponent(name)) else { return nil }
                return UIImage(data: data)
            }()
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { dismiss(); return }
        isSaving = true
        // 原始照片與最終結果不同（換照片或移除圖片）才刪除原檔；真正的刪除動作延到這裡才提交，
        // 使用者中途按「取消」不會遺失原本已存在的照片（見 photoItem onChange／移除圖片按鈕註解）。
        if let original = originalPhotoFileName, original != photoFileName {
            ChildRecord.deletePhoto(original)
        }
        let rec = ChildRecord(
            id: editing?.id ?? UUID(), type: type, date: date,
            title: title.trimmingCharacters(in: .whitespaces), detail: detail.trimmingCharacters(in: .whitespaces),
            note: note.trimmingCharacters(in: .whitespaces),
            heightCm: type == .growth ? Double(heightText) : nil, weightKg: type == .growth ? Double(weightText) : nil,
            dose: type == .vaccination ? dose.trimmingCharacters(in: .whitespaces) : nil,
            severity: type == .allergy ? severity : nil,
            photoFileName: photoFileName
        )
        if let idx = member.childRecords.firstIndex(where: { $0.id == rec.id }) { member.childRecords[idx] = rec }
        else { member.childRecords.append(rec) }
        lifeStore.update(member); dismiss()
    }

    private func delete() {
        guard let e = editing, var member = lifeStore.familyMembers.first(where: { $0.id == childId }) else { dismiss(); return }
        member.childRecords.removeAll { $0.id == e.id }
        lifeStore.update(member); dismiss()
    }
}

// MARK: - 院所候選資料型別

fileprivate struct ClinicSuggestion: Identifiable {
    enum Source { case past, apple }
    let id: String
    let source: Source
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion?

    var iconName: String {
        source == .past ? "clock.arrow.circlepath" : "cross.case.fill"
    }
    var iconColor: Color {
        source == .past ? .green : .red
    }
}
