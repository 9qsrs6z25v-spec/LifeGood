import SwiftUI

// MARK: - 美化紀錄（FamilyView）
// [2026-06 v1] 本次美化方向：
//   1. memberRow：圖示圓升至 44pt + LinearGradient 漸層填色 + 陰影，對齊 ExpenseRow 規格
//   2. memberRow：左側 4pt 角色色彩強調條（依角色分色），增加視覺層次
//   3. memberRow：角色名稱改為彩色膠囊標籤，配偶名稱以粉紅愛心膠囊呈現
//   4. memberRow：日期以小圖示搭配文字呈現（calendar / heart.fill）
//   5. 空狀態：加入雙層脈衝光環 + 漸層圓底，對齊 VariableExpenseView emptyStateView 規格
//   6. Section header：加入粉紅側條 + 成員計數膠囊，對齊 daySectionHeader 規格
//   7. 列表：加入交錯淡入 + 向上進場動畫，對齊 FixedExpenseView 規格
// [2026-06 v2] 本次美化方向：
//   8. familySectionHeader 側條：RoundedRectangle(cornerRadius:3) 3pt/14pt → Capsule 4pt/18pt，
//      字型 .footnote.weight(.semibold) → .subheadline.weight(.bold)，去除 .opacity(0.75) 降飽；
//      對齊全 App 標準 section header（OverviewView / LifeOverviewView / CareerView）規格。
//   9. memberRow 圖示圓：補入 Circle().stroke(accent.opacity(0.18), lineWidth:0.75) overlay 細邊框，
//      對齊 CareerView v2 / VehicleView v3 / StockView v3 圖示圓邊框規格。
//  10. memberRow 角色膠囊 / 配偶心形膠囊：補入 .overlay(Capsule().stroke(…opacity(0.22), 0.6pt))，
//      對齊 OverviewView.categoryRow / LifeOverviewView.categoryBreakdownSection 膠囊邊框規格。
//  11. memberRow 右側日期：從純圖示+文字升級為 Capsule 徽章（tertiarySystemFill 底色 + padding），
//      對齊 OverviewView.recentRow / CareerView v2 / LifeOverviewView v3 日期膠囊規格。
//  12. 新增 statsStrip：地圖與成員列表間加入統計徽章橫列（總成員 / 配偶 / 兒女計數），
//      42pt 漸層圖示圓 + 數字 + 標籤，對齊 LifeOverviewView.statBadge 設計語言；
//      加入 statsAppeared spring 錯落進場動畫（0.07s stagger），對齊 LifeOverviewView.statsCard 規格。
// [2026-06 v3] 本次美化方向：
//  13. statsStrip 統計卡：背景 ZStack 加入裝飾性 bokeh 光暈圓（右上偏移，blur 10pt），
//      對齊 SettingsView / ChartView / VariableExpenseView hero card bokeh 設計語言。
//  14. statsStrip 統計卡：補入玻璃光澤 overlay（白色 LinearGradient 頂部→透明 0.15 opacity），
//      對齊 OverviewView.monthlyBalanceCard / IncomeView.summaryHeader 玻璃光澤規格；
//      同一 overlay ZStack 收納既有邊框 stroke（減少 modifier 層數）。
//  15. emptyMembersPlaceholder：補入粉紅 CTA 按鈕（漸層膠囊底色 + 陰影），
//      對齊 CareerView v3 / FixedExpenseView / VariableExpenseView emptyState CTA button 規格；
//      按鈕觸發同導覽列「＋」的 showAdd／showPremiumAlert 邏輯，無新增商業邏輯。
//  16. memberRow 圖示圓陰影：radius 6→8、opacity 0.22→0.28，增強圖示立體感，
//      對齊 FixedExpenseRow / CareerRow v3 圖示圓陰影強度規格。
// [2026-08 v4] 本次美化方向：
//  17. memberRow 補齊大字級輔助模式防護：全檔案原本 0 處 minimumScaleFactor，是唯一
//      完全沒有防截斷保護的成員列表畫面——中文名／英文名／配偶姓名皆為使用者自填、
//      長度不可控，重要親戚或配偶英文全名偏長時，在「輔助模式：特大」字級下容易被
//      lineLimit(1) 硬切甚至擠壓版面。displayName 補 minimumScaleFactor(0.85)（對齊
//      ChildVaccineScheduleView row 姓名規格）；englishName／配偶心形膠囊姓名補
//      lineLimit(1) + minimumScaleFactor(0.85)；角色膠囊 displayRoleLabel 補
//      lineLimit(1) + minimumScaleFactor(0.7)（對齊 CareerView 徽章文字縮放規格）。
//      純顯示層調整，成員資料讀寫、角色配色、配偶連結等既有邏輯完全未變動。

struct FamilyView: View {
    @EnvironmentObject var store: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var editingMember: FamilyMember?
    @State private var showPremiumAlert = false
    @State private var membersAppeared = false
    @State private var emptyIconPulse = false
    @State private var emptyIconPulseTask: Task<Void, Never>?
    // [v2] 統計徽章橫列進場動畫旗標
    @State private var statsAppeared = false

    var body: some View {
        // 一次建表供 memberRow／spouseDisplayName 共用，取代原本每一列各自對
        // store.familyMembers 做 first(where:) 全量掃描（O(members²)）。
        let membersById = Dictionary(store.familyMembers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        NavigationStack {
            // 用同一個 List 把街道圖跟成員清單放在一起；
            // 列表上滑時，街道圖會自然跟著被推上去，給下方項目更多空間。
            List {
                Section {
                    FamilyOverviewMap(
                        myName: store.profile.chineseName,
                        members: store.familyMembers
                    )
                    .frame(height: 320)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                // [v2] 統計徽章橫列（地圖下、成員清單前，有成員時才顯示）
                if !store.familyMembers.isEmpty {
                    Section {
                        statsStrip
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                if store.familyMembers.isEmpty {
                    Section {
                        emptyMembersPlaceholder
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    Section(header: familySectionHeader) {
                        ForEach(Array(store.familyMembers.enumerated()), id: \.element.id) { idx, member in
                            memberRow(member, membersById: membersById)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if subscription.isPremium { editingMember = member }
                                    else { showPremiumAlert = true }
                                }
                                .opacity(membersAppeared ? 1 : 0)
                                .offset(y: membersAppeared ? 0 : 14)
                                .animation(
                                    .spring(response: 0.45, dampingFraction: 0.82)
                                        .delay(0.05 * Double(idx)),
                                    value: membersAppeared
                                )
                                // 改用 allowsFullSwipe: false 的滑出按鈕取代 .onDelete：
                                // 避免整列滑到底直接刪除（與邊緣切頁手勢衝突，同型修正見 v25.154）
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        guard subscription.isPremium else { showPremiumAlert = true; return }
                                        store.deleteFamilyMember(member)
                                    } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            // onAppear/onDisappear 掛在 List 本身（而非 Section 內的 ForEach）：List 會延遲載入
            // （lazy-load）各列，掛在 ForEach 上等同掛在每一列產生的子視圖上，捲動使某列進出可視範圍
            // 就各自觸發一次，成員數超過一屏時，所有列共用的 membersAppeared 旗標會被反覆觸發，
            // 導致整個可視列表在捲動時無謂淡出又重播進場動畫。比照 FamilyMembersResumeView /
            // ChildrenResumeView 既有寫法，改掛在 List／容器本身，確保只在畫面進出時各觸發一次。
            .onAppear {
                withAnimation(.spring(response: 0.50, dampingFraction: 0.82).delay(0.05)) {
                    membersAppeared = true
                }
            }
            .onDisappear {
                // 重置旗標：切到其他分頁再切回時能重新播放成員列表進場動畫
                membersAppeared = false
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("家庭")
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
            .sheet(isPresented: $showAdd) { AddMilestoneView(initialCategory: .family) }
            .sheet(item: $editingMember) { member in AddMilestoneView(editingFamily: member) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    // MARK: - Section Header（帶成員計數膠囊）

    private var familySectionHeader: some View {
        let accent = Color(red: 1.00, green: 0.35, blue: 0.55)
        return HStack(spacing: 8) {
            // [v2] 側條：RoundedRectangle(cornerRadius:3) 3pt/14pt → Capsule 4pt/18pt（對齊全 App section header 規格）
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 18)
            Text("家庭成員")
                .font(.subheadline.weight(.bold))
            Spacer(minLength: 6)
            Text("\(store.familyMembers.count) 位")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(accent.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
        }
        .textCase(nil)
    }

    // MARK: - [v2] 統計徽章橫列（總成員 / 配偶 / 兒女）

    private var statsStrip: some View {
        let spouseCount  = store.familyMembers.filter { $0.role == .spouse }.count
        let childrenCount = store.familyMembers.filter { $0.role == .son || $0.role == .daughter }.count
        let items: [(title: String, count: Int, icon: String, color: Color, delay: Double)] = [
            ("總成員", store.familyMembers.count, "person.3.fill",
             Color(red: 1.00, green: 0.35, blue: 0.55), 0.06),
            ("配偶",   spouseCount,                "heart.fill",
             Color(red: 1.00, green: 0.35, blue: 0.55), 0.14),
            ("兒女",   childrenCount,               "figure.2.and.child.holdinghands",
             Color(red: 1.00, green: 0.62, blue: 0.22), 0.22),
        ]
        return HStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [item.color.opacity(0.20), item.color.opacity(0.07)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 42, height: 42)
                        Circle()
                            .stroke(item.color.opacity(0.22), lineWidth: 1.2)
                            .frame(width: 42, height: 42)
                        Image(systemName: item.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(item.color)
                    }
                    Text("\(item.count)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Text(item.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    ZStack {
                        Color(.systemBackground)
                        item.color.opacity(0.03)
                        // [v3] 裝飾性 bokeh 光暈圓（右上偏移，對齊 hero card bokeh 設計語言）
                        Circle()
                            .fill(item.color.opacity(0.12))
                            .blur(radius: 10)
                            .frame(width: 36, height: 36)
                            .offset(x: 16, y: -14)
                            .allowsHitTesting(false)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                // [v3] 玻璃光澤 + 邊框合併為單一 overlay（減少 modifier 層數）
                .overlay(
                    ZStack {
                        LinearGradient(
                            colors: [Color.white.opacity(0.15), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(item.color.opacity(0.10), lineWidth: 0.75)
                    }
                )
                .shadow(color: item.color.opacity(0.12), radius: 8, x: 0, y: 3)
                .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
                // 錯落進場動畫（對齊 LifeOverviewView.statsCard 規格）
                .opacity(statsAppeared ? 1 : 0)
                .offset(y: statsAppeared ? 0 : 16)
                .animation(
                    .spring(response: 0.50, dampingFraction: 0.78).delay(item.delay),
                    value: statsAppeared
                )
            }
        }
        .padding(.horizontal, 4)
        .onAppear {
            withAnimation { statsAppeared = true }
        }
        .onDisappear {
            // 重置旗標，讓 Section 消失（所有成員被刪除）後再次出現時能重新播放進場動畫
            statsAppeared = false
        }
    }

    // MARK: - 空狀態（雙層脈衝光環 + 漸層圓底）

    private var emptyMembersPlaceholder: some View {
        let accent = Color(red: 1.00, green: 0.35, blue: 0.55)
        return VStack(spacing: 20) {
            ZStack {
                // 外層脈衝光環
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.25), lineWidth: 1.5)
                    .frame(width: 100, height: 100)
                    .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 內層脈衝光環（延遲 0.3s，製造波紋層次）
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.13), lineWidth: 1)
                    .frame(width: 100, height: 100)
                    .scaleEffect(emptyIconPulse ? 1.60 : 1.0)
                    .animation(
                        .easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false),
                        value: emptyIconPulse
                    )
                // 主圓底（漸層填色 + 細邊框）
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.14), accent.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 82, height: 82)
                    .overlay(
                        Circle().stroke(accent.opacity(0.20), lineWidth: 1.2)
                    )
                Image(systemName: "person.3.fill")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(accent.opacity(0.70))
            }
            .onAppear {
                emptyIconPulseTask?.cancel()
                emptyIconPulseTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    emptyIconPulse = true
                }
            }
            .onDisappear {
                emptyIconPulseTask?.cancel()
                emptyIconPulse = false
            }

            VStack(spacing: 8) {
                Text("尚無家庭成員")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.65))
                Text("建立家庭成員檔案，記錄生日與重要紀念日")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            // [v3] CTA 按鈕：對齊 CareerView v3 / FixedExpenseView / VariableExpenseView emptyState 規格
            Button {
                if subscription.isPremium { showAdd = true }
                else { showPremiumAlert = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("新增家庭成員")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: accent.opacity(0.38), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - 角色配色（依親屬關係分色）

    private func roleAccentColor(_ role: FamilyMemberRole) -> Color {
        switch role {
        case .spouse:
            return Color(red: 1.00, green: 0.35, blue: 0.55)   // 粉紅：配偶
        case .son, .daughter:
            return Color(red: 1.00, green: 0.62, blue: 0.22)   // 橘色：兒女
        case .father, .mother:
            return Color(red: 0.22, green: 0.53, blue: 0.98)   // 藍色：父母
        case .elderBrother, .youngerBrother:
            return Color(red: 0.16, green: 0.74, blue: 0.50)   // 綠色：兄弟
        case .elderSister, .youngerSister:
            return Color(red: 0.68, green: 0.40, blue: 1.00)   // 紫色：姐妹
        case .otherRelative:
            return Color(.secondaryLabel)                        // 灰色：其他親屬
        }
    }

    // MARK: - 成員列（44pt 圖示圓 + 角色色彩強調條 + 膠囊標籤）

    private func memberRow(_ member: FamilyMember, membersById: [UUID: FamilyMember]) -> some View {
        let accent = roleAccentColor(member.role)
        let displayName = member.chineseName.isEmpty ? member.englishName : member.chineseName

        return HStack(spacing: 0) {
            // 左側角色色彩強調條（4pt，與 FixedExpenseRow 規格一致）
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.40)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .padding(.vertical, 8)
                .padding(.trailing, 14)

            HStack(spacing: 12) {
                // 角色圖示圓（44pt + 漸層填色 + 陰影，對齊 ExpenseRow 規格）
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
                        // [v3] 陰影強度提升（radius 6→8, opacity 0.22→0.28），對齊 FixedExpenseRow / CareerRow v3 規格
                        .shadow(color: accent.opacity(0.28), radius: 8, x: 0, y: 4)
                    // [v2] 細邊框：對齊 CareerView v2 / VehicleView v3 / StockView v3 圖示圓規格
                    Circle()
                        .stroke(accent.opacity(0.18), lineWidth: 0.75)
                        .frame(width: 44, height: 44)
                    Image(systemName: member.role.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName.isEmpty ? "（未命名）" : displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        // [v4] 中文名為使用者自填、長度不可控，補防截斷保護
                        .minimumScaleFactor(0.85)

                    // 角色膠囊 + 英文名 + 配偶名
                    HStack(spacing: 5) {
                        Text(member.displayRoleLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(accent.opacity(0.12))
                            .clipShape(Capsule())
                            // [v2] 膠囊細邊框，對齊 OverviewView.categoryRow 百分比膠囊規格
                            .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                            // [v4] 補防截斷保護，對齊 CareerView 徽章文字縮放規格
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if !member.englishName.isEmpty && !member.chineseName.isEmpty {
                            Text(member.englishName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                // [v4] 英文全名長度不可控，補防截斷保護
                                .minimumScaleFactor(0.85)
                        }
                        if let spouse = spouseDisplayName(for: member, membersById: membersById) {
                            HStack(spacing: 3) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 8))
                                Text(spouse)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                    // [v4] 配偶姓名長度不可控，補防截斷保護
                                    .minimumScaleFactor(0.85)
                            }
                            .foregroundStyle(Color(red: 1.00, green: 0.35, blue: 0.55))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(red: 1.00, green: 0.35, blue: 0.55).opacity(0.10))
                            .clipShape(Capsule())
                            // [v2] 配偶心形膠囊細邊框，對齊全 App 彩色膠囊邊框規格
                            .overlay(Capsule().stroke(Color(red: 1.00, green: 0.35, blue: 0.55).opacity(0.22), lineWidth: 0.6))
                        }
                    }
                }

                Spacer(minLength: 4)

                // [v2] 右側日期：升級為 Capsule 徽章，對齊 OverviewView.recentRow / CareerView v2 日期膠囊規格
                VStack(alignment: .trailing, spacing: 4) {
                    if let bd = member.birthday {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 9))
                            Text(formatDate(bd))
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2.5)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                    }
                    // 原本用 if/else if 讓婚期／離婚徽章只在「沒有生日」時才顯示，
                    // 但配偶幾乎都會填生日，導致已離婚的配偶在家人列表完全看不出離婚狀態
                    // （SpouseResumeView 卻正確顯示）；改為與生日徽章各自獨立顯示。
                    if member.role == .spouse, let md = member.marriageDate {
                        let spouseAccent = Color(red: 1.00, green: 0.35, blue: 0.55)
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9))
                            Text(formatDate(md))
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(spouseAccent)
                        .padding(.horizontal, 6).padding(.vertical, 2.5)
                        .background(spouseAccent.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(spouseAccent.opacity(0.20), lineWidth: 0.5))
                        if member.isDivorced, let dd = member.divorceDate {
                            HStack(spacing: 3) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 9))
                                Text(formatDate(dd))
                                    .font(.caption2.weight(.medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2.5)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.vertical, 7)
        }
    }

    private static let _dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()
    private func formatDate(_ date: Date) -> String {
        Self._dateFmt.string(from: date)
    }

    private func spouseDisplayName(for member: FamilyMember, membersById: [UUID: FamilyMember]) -> String? {
        guard let id = member.spouseId, let spouse = membersById[id] else { return nil }
        let name = spouse.chineseName.isEmpty ? spouse.englishName : spouse.chineseName
        return name.isEmpty ? nil : name
    }
}
