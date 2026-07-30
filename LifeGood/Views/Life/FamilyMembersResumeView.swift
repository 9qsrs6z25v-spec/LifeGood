import SwiftUI
import PhotosUI

// MARK: - 美化紀錄
// 版本：v2（2026-06）
// 美化方向：
//   • FamilyMembersResumeView（列表）v1
//       - Capsule 側條 sectionHeader（4pt 漸層） + 計數 Capsule 徽章（含 stroke 0.6pt 邊框）
//       - 44pt 漸層圖示圓（role 對應色） + shadow；角色徽章改 Capsule
//       - familySide 顯示 Capsule 小標籤
//       - stagger 入場動畫（rowsAppeared + 0.06s delay/row）
//       - 全空 empty state（雙脈衝擴散環 + figure.2.and.child.holdinghands）
//   • FamilyMemberDetailView（詳細頁）v2
//       - hero card 頂部玻璃光澤 overlay（.white.opacity(0.18)→.clear，.top→.center）
//       - role 漸層 hero card + bokeh 裝飾 + cardAppeared spring 動畫
//       - sectionHeaderWithAdd：Capsule 側條 + .subheadline.weight(.bold) + 計數徽章（含 stroke 0.6pt）
//       - 靜態 dateFormatter / currencyFormatter（效能優化，避免每次 render 重新建立）
//       - eventsSection stagger 入場動畫（eventsAppeared + 0.06s delay/row）
//       - eventsSection 每行升級為 36pt 日曆圖示圓（orange→orange.opacity(0.65) 漸層 + stroke 1pt）
//       - eventsSection 日期改 Capsule 徽章（tertiarySystemFill 底色 + calendar icon）
//       - memberGiftsSection 標頭改 Capsule 側條；禮金行升級為 36pt 圖示圓（含 stroke 1pt）
//       - memberGiftsSection 金額改 Capsule 徽章（pink.opacity(0.10) 底色 + stroke 0.6pt）
//       - smartGiftAmount()：萬/億 智慧量級顯示（≥1億→億，≥1萬→萬，其餘 NT$）
//       - photoCard 加 shadow（black.opacity(0.06)，radius 4）
// [2026-06 v3] 本次美化方向（familyHeroCard + 圖示圓精修 + 詳細頁細節對齊）：
//   1. FamilyMembersResumeView 頂部新增粉紅漸層英雄統計卡（familyHeroCard）：
//      補齊全 App 主要列表頁唯一缺少頂部英雄卡的均值落差；
//      粉紅→洋紅漸層 + 三顆散景裝飾圓 + 頂部玻璃光澤 + 白色 RoundedRectangle stroke overlay；
//      左上 figure.2.and.child.holdinghands 圖示圓 + 「家人履歷」小標 + 右上人數膠囊；
//      大字：總家人人數；KPI 橫列三格（直系親屬 / 兄弟姐妹 / 其他親屬）；
//      heroCardAppeared spring 進場動畫，對齊 ResumeView.resumeHeroCard /
//      ChildrenResumeView.heroStatsCard / CareerView.summaryCard 英雄卡規格。
//   2. memberRow 44pt 圖示圓：補入 Circle().stroke(.white.opacity(0.30), lineWidth:0.75) overlay，
//      對齊 FamilyView v2 / CareerView v2 / SubordinateView v2 / ResumeGiftSection 圖示圓邊框規格。
//   3. memberRow 角色膠囊：補入 Capsule().stroke(roleColor.opacity(0.22), lineWidth:0.6)，
//      對齊 FamilyView v2 / LifeOverviewView.categoryBreakdownSection 膠囊細邊框規格。
//   4. memberRow familySide 膠囊：補入 Capsule().stroke(Color.secondary.opacity(0.18), lineWidth:0.6)，
//      對齊 VehicleView v3 / StockView v3 次要資訊膠囊細邊框規格。
//   5. sectionHeader 計數徽章：從 frame(width:32,height:18) 固定尺寸改為 padding 自適應方式，
//      對齊 ResumeView.sectionHeader / ChildrenResumeView 計數徽章標準規格。
//   6. List 補入 .scrollContentBackground(.hidden) + .background(systemGroupedBackground)，
//      深色模式不再出現白色 List 背景，對齊 FixedExpenseView / ResumeView / CareerView 規格。
//   7. FamilyMemberDetailView.headerCard：補第三顆散景圓（55pt white.opacity(0.06) offset(30,30) blur 8）
//      + RoundedRectangle stroke(.white.opacity(0.18), 0.75pt) overlay，
//      對齊 ChartView v4 / StockDetailView v3 / SubordinateDetailView v3 英雄卡三圓+邊框規格；
//      角色 Capsule 補入 Capsule().stroke(.white.opacity(0.28), 0.6pt) 細邊框。
//   8. eventsSection 入場動畫：.easeOut(duration:0.4) → .spring(response:0.5, dampingFraction:0.82)，
//      對齊 FamilyView.statsStrip / SubordinateDetailView.eventsAppeared spring 規格。
//   9. eventsSection event row 日曆圖示圓：補入 Circle().stroke(.orange.opacity(0.22), lineWidth:0.75)，
//      對齊 FamilyMemberDetailView memberGiftsSection 36pt 圖示圓邊框規格統一。
//  10. eventsSection 日期 Capsule：補入 Capsule().stroke(Color(.separator).opacity(0.20), lineWidth:0.5)，
//      對齊 ChildDetailView v2 / SpouseResumeView v2 / CareerView v2 日期膠囊邊框規格。
//  11. photoCard 照片日期：從純 tertiary 小字升級為「calendar icon + 日期」Capsule 徽章
//      （tertiarySystemFill 底色 + separator 細邊框），
//      對齊 eventsSection 日期 Capsule / ChildDetailView v2 / CareerView v2 日期規格。
// [2026-07 v4] 金額量級一致性：memberGiftsSection 私有 smartGiftAmount(_:) 手刻「%.1f億／%.1f萬」
//      邏輯與全 App 共用 Double.ntdWanString 完全重複，且缺少捨入至萬位上限應進位為億的邊界處理
//      （會顯示成不合理的「10000.0萬」），與 ResumeView.giftHeroCard / SpouseResumeView 等同類禮金
//      金額顯示風格不一致。禮金總計 Capsule 徽章、分類金額 Capsule 徽章兩處呼叫點改用共用
//      Double.ntdWanString，並補上 lineLimit(1) + minimumScaleFactor(0.7)（對齊 StockView /
//      TaxOverviewView 等同類 Capsule 金額徽章防截斷規格）。移除已無呼叫端的私有
//      smartGiftAmount／formatGiftTotal／currencyFormatter 死碼。純顯示層調整，禮金加總等既有邏輯未變動。
// [2026-07 v5] 表單 Section header 補齊：FamilyEventEditor（新增/編輯紀錄）與
//      FamilyAlbumPhotoEditor（新增/編輯照片）共 5 個 Section（基本資訊 ×2／內容／照片／備註）
//      原本是本檔案唯二仍在用系統預設純文字 Section("...") 標頭的地方，與同檔案
//      FamilyMembersResumeView.sectionHeader／FamilyMemberDetailView.sectionHeaderWithAdd
//      早已升級的「4pt 漸層 Capsule 側條 + 圖示 + 粗體標題」規格脫節，也是全 App 這輪
//      「表單 Section header 補齊」系列（BusinessCardEditor v25.24／OrgPersonEditor v25.22／
//      EInvoiceSetupView v25.21／ChildDetailView v25.01）尚未覆蓋到的最後兩個編輯 sheet。
//      新增共用 familyEditorSectionHeader(_:icon:color:)，依內容給主題色（基本資訊＝indigo／
//      內容／備註＝secondary／照片＝teal），刪除紀錄／刪除此筆兩個 Section 維持無標頭
//      （對齊 ChildDetailView v25.01 慣例：刪除區塊不加標頭）。純視覺層調整，日期/標題/內容/
//      照片欄位綁定、save()／deleteRecord() 等既有商業邏輯完全未變動。
//      （下次美化本檔案時，可轉往其他仍留有待辦的畫面）
// ─────────────────────────────────────────────

// MARK: - 家人履歷 列表

/// 顯示直系（爸媽）+ 二等親屬（兄弟姐妹 / 其他親屬）的列表，點選進入個人詳細頁。
struct FamilyMembersResumeView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @State private var viewingMember: FamilyMember?
    @State private var rowsAppeared = false
    @State private var emptyIconPulse = false
    // [v3] 英雄卡進場動畫旗標
    @State private var heroCardAppeared = false

    private var directRelatives: [FamilyMember] {
        lifeStore.familyMembers
            .filter { $0.role == .father || $0.role == .mother }
            .sorted { $0.role.rawValue < $1.role.rawValue }
    }

    private var siblings: [FamilyMember] {
        lifeStore.familyMembers
            .filter {
                [.elderBrother, .elderSister, .youngerBrother, .youngerSister].contains($0.role)
            }
            .sorted { $0.role.rawValue < $1.role.rawValue }
    }

    private var others: [FamilyMember] {
        lifeStore.familyMembers
            .filter { $0.role == .otherRelative }
    }

    private var allMembers: [FamilyMember] { directRelatives + siblings + others }

    var body: some View {
        NavigationStack {
            // [v3] VStack 包住英雄卡 + 列表，補齊全 App 列表頁均值
            VStack(spacing: 0) {
                // [v3] 頂部英雄統計卡（有家人時才顯示）
                if !allMembers.isEmpty {
                    familyHeroCard
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                        .opacity(heroCardAppeared ? 1 : 0)
                        .offset(y: heroCardAppeared ? 0 : 20)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                heroCardAppeared = true
                            }
                        }
                        .onDisappear {
                            // 重置旗標：切到其他分頁再切回時能重新播放英雄卡進場動畫
                            heroCardAppeared = false
                        }
                }

                if allMembers.isEmpty {
                    emptyState
                } else {
                    List {
                        if !directRelatives.isEmpty {
                            Section {
                                ForEach(Array(directRelatives.enumerated()), id: \.element.id) { idx, m in
                                    Button { viewingMember = m } label: {
                                        memberRow(m, index: idx)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                sectionHeader("直系親屬", count: directRelatives.count, color: .orange)
                            }
                        }
                        if !siblings.isEmpty {
                            Section {
                                ForEach(Array(siblings.enumerated()), id: \.element.id) { idx, m in
                                    Button { viewingMember = m } label: {
                                        memberRow(m, index: directRelatives.count + idx)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                sectionHeader("兄弟姐妹", count: siblings.count, color: .pink)
                            }
                        }
                        if !others.isEmpty {
                            Section {
                                ForEach(Array(others.enumerated()), id: \.element.id) { idx, m in
                                    Button { viewingMember = m } label: {
                                        memberRow(m, index: directRelatives.count + siblings.count + idx)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                sectionHeader("其他親屬", count: others.count, color: .indigo)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    // [v3] 深色模式不再顯示白色 List 背景，對齊 FixedExpenseView / ResumeView 規格
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGroupedBackground))
                    .onAppear {
                        // [v3] easeOut → spring，對齊全 App stagger 動畫規格
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) {
                            rowsAppeared = true
                        }
                    }
                    .onDisappear {
                        // 重置旗標：切到其他分頁再切回時能重新播放列表進場動畫
                        rowsAppeared = false
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("家人履歷")
            .sheet(item: $viewingMember) { member in
                FamilyMemberDetailView(memberId: member.id)
            }
        }
    }

    // MARK: - [v3] 頂部英雄統計卡（粉紅→洋紅漸層）

    /// 補齊全 App 主要列表頁均值，列出直系 / 兄弟姐妹 / 其他親屬人數 KPI。
    private var familyHeroCard: some View {
        let accent = Color.pink
        let accentDark = Color(red: 0.90, green: 0.22, blue: 0.55)
        let total = allMembers.count

        return ZStack(alignment: .topLeading) {
            // 漸層背景（粉紅→洋紅，象徵家庭溫暖主題）
            LinearGradient(
                colors: [accent, accentDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 散景裝飾圓 1（右上主光暈）
            Circle()
                .fill(.white.opacity(0.13))
                .frame(width: 110, height: 110)
                .offset(x: 80, y: -35)
                .blur(radius: 16)

            // 散景裝飾圓 2（左下次光暈）
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 80, height: 80)
                .offset(x: -70, y: 45)
                .blur(radius: 12)

            // 散景裝飾圓 3（中右微光，對齊全 App 三圓規格）
            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: 55, height: 55)
                .offset(x: 35, y: 20)
                .blur(radius: 8)

            // 頂部玻璃光澤（對齊全 App 英雄卡 glass shine 統一規格）
            LinearGradient(
                colors: [.white.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .center
            )

            // 卡片內容
            VStack(alignment: .leading, spacing: 0) {
                // 頂部列：圖示圓 + 小標 + 人數計數膠囊
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.22))
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(.white.opacity(0.30), lineWidth: 0.75))
                        Image(systemName: "figure.2.and.child.holdinghands")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Text("家人履歷")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(total) 位")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.white.opacity(0.90))
                    .padding(.horizontal, 9).padding(.vertical, 3.5)
                    .background(.white.opacity(0.22))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 0.75))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                // 大字：總人數
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(total)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Text("位家人")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)

                // 分隔線
                Rectangle()
                    .fill(.white.opacity(0.20))
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)

                // KPI 橫列（直系親屬 / 兄弟姐妹 / 其他親屬）
                HStack(spacing: 0) {
                    heroKpiCell(
                        value: directRelatives.isEmpty ? "—" : "\(directRelatives.count) 位",
                        label: "直系親屬",
                        icon: "person.2.fill"
                    )
                    Rectangle().fill(.white.opacity(0.22)).frame(width: 0.5)
                    heroKpiCell(
                        value: siblings.isEmpty ? "—" : "\(siblings.count) 位",
                        label: "兄弟姐妹",
                        icon: "person.3.fill"
                    )
                    Rectangle().fill(.white.opacity(0.22)).frame(width: 0.5)
                    heroKpiCell(
                        value: others.isEmpty ? "—" : "\(others.count) 位",
                        label: "其他親屬",
                        icon: "person.circle.fill"
                    )
                }
                .background(.white.opacity(0.10))
                .padding(.top, 10)
                .padding(.bottom, 14)
                .padding(.horizontal, 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.75)
        )
        .shadow(color: accent.opacity(0.35), radius: 14, x: 0, y: 6)
        .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
    }

    /// 英雄卡 KPI 格（值大字 + 說明小字 + 圖示），對齊 ResumeView.heroKpiCell 規格。
    private func heroKpiCell(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.80))
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: Section Header（Capsule 側條 + 計數徽章）
    // [v3] 計數徽章從 frame 固定尺寸改為 padding 自適應，對齊 ResumeView.sectionHeader 規格
    private func sectionHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.6)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
            Text("\(count) 位")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color.opacity(0.85))
                .padding(.horizontal, 7).padding(.vertical, 2.5)
                .background(color.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.6))
            Spacer()
        }
        .padding(.horizontal, 4)
        .textCase(nil)
    }

    // MARK: Member Row（44pt 漸層圓 + Capsule 角色徽章 + stagger）
    private func memberRow(_ m: FamilyMember, index: Int) -> some View {
        let roleColor = accentColor(for: m.role)
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [roleColor, roleColor.opacity(0.7)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .shadow(color: roleColor.opacity(0.35), radius: 5, x: 0, y: 3)
                // [v3] stroke 細邊框，對齊 FamilyView v2 / CareerView v2 圖示圓邊框規格
                Circle()
                    .stroke(.white.opacity(0.30), lineWidth: 0.75)
                    .frame(width: 44, height: 44)
                Image(systemName: m.role.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(m.chineseName.isEmpty ? m.role.rawValue : m.chineseName)
                        .font(.subheadline.weight(.semibold))
                    Text(m.role.rawValue)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(roleColor.opacity(0.12))
                        .foregroundStyle(roleColor)
                        .clipShape(Capsule())
                        // [v3] 角色膠囊細邊框，對齊 FamilyView v2 膠囊規格
                        .overlay(Capsule().stroke(roleColor.opacity(0.22), lineWidth: 0.6))
                    if let side = m.familySide {
                        Text(side.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.10))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                            // [v3] familySide 膠囊細邊框，對齊 VehicleView v3 次要膠囊規格
                            .overlay(Capsule().stroke(Color.secondary.opacity(0.18), lineWidth: 0.6))
                    }
                }
                HStack(spacing: 8) {
                    if !m.familyEvents.isEmpty {
                        Label("\(m.familyEvents.count) 則紀錄", systemImage: "doc.text")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if !m.familyPhotos.isEmpty {
                        Label("\(m.familyPhotos.count) 張照片", systemImage: "photo")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if m.familyEvents.isEmpty && m.familyPhotos.isEmpty {
                        Text("尚無紀錄").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .opacity(rowsAppeared ? 1 : 0)
        .offset(y: rowsAppeared ? 0 : 14)
        .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.06 * Double(index)),
                   value: rowsAppeared)
    }

    // MARK: Empty State（雙脈衝環）
    private var emptyState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color.pink.opacity(emptyIconPulse ? 0 : 0.3), lineWidth: 2)
                    .frame(width: emptyIconPulse ? 90 : 60, height: emptyIconPulse ? 90 : 60)
                Circle()
                    .stroke(Color.pink.opacity(emptyIconPulse ? 0 : 0.15), lineWidth: 2)
                    .frame(width: emptyIconPulse ? 120 : 80, height: emptyIconPulse ? 120 : 80)
                Circle()
                    .fill(LinearGradient(colors: [.pink, .pink.opacity(0.7)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                    .shadow(color: .pink.opacity(0.3), radius: 8, x: 0, y: 4)
                Image(systemName: "figure.2.and.child.holdinghands")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                    emptyIconPulse = true
                }
            }
            // 對齊本檔案 heroCardAppeared／rowsAppeared 既有寫法：離開時重置旗標，
            // 否則再次回到空清單狀態時 emptyIconPulse 已是 true，withAnimation 判定無變化
            // 不會重新排程 repeatForever 動畫，兩個脈衝環會停在淡出終態（opacity: 0）不再脈動。
            .onDisappear { emptyIconPulse = false }

            VStack(spacing: 6) {
                Text("尚未新增家人").font(.title3.bold())
                Text("在「家庭」頁面新增家人後，這裡會顯示他們的履歷")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Role Accent Color
    private func accentColor(for role: FamilyMemberRole) -> Color {
        switch role {
        case .spouse:                                            return .pink
        case .father, .elderBrother, .youngerBrother, .son:    return .orange
        case .mother, .elderSister, .youngerSister, .daughter: return .pink
        case .otherRelative:                                    return .indigo
        }
    }
}

// MARK: - 家人詳細履歷

struct FamilyMemberDetailView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let memberId: UUID
    @State private var addingEvent = false
    @State private var editingEvent: FamilyEvent?
    @State private var addingPhoto = false
    @State private var editingPhoto: FamilyAlbumPhoto?
    @State private var viewingPhotoURL: URL?
    @State private var cardAppeared = false
    @State private var eventsAppeared = false
    @EnvironmentObject var expenseStore: ExpenseStore

    // 靜態格式化器（避免每次 render 重新建立）
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    private var member: FamilyMember {
        lifeStore.familyMembers.first(where: { $0.id == memberId })
            ?? FamilyMember(role: .otherRelative)
    }

    private var sortedFamilyPhotos: [FamilyAlbumPhoto] {
        member.familyPhotos.sorted { $0.date > $1.date }
    }

    private var roleColor: Color {
        switch member.role {
        case .spouse:                                            return .pink
        case .father, .elderBrother, .youngerBrother, .son:    return .orange
        case .mother, .elderSister, .youngerSister, .daughter: return .pink
        case .otherRelative:                                    return .indigo
        }
    }

    /// 變動支出 .social 中將此家人列為收受人的紀錄
    private var memberGifts: [Expense] {
        let target = member.chineseName
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

    private func memberGiftsSection(_ gifts: [Expense]) -> some View {
        // 依社交子分類一次分桶（O(n)），取代原本 ForEach 內對 gifts 逐分類各 filter 一次（O(分類數 × n)）；
        // 只桶入有 socialSubCategory 的項目，維持與原本 filter 相同的行為（無子分類的項目不歸類到任何分類列）
        var grouped: [SocialSubCategory: [Expense]] = [:]
        for e in gifts {
            if let sub = e.socialSubCategory {
                grouped[sub, default: []].append(e)
            }
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(LinearGradient(colors: [.pink, .pink.opacity(0.6)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 18)
                Image(systemName: "gift.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.pink)
                Text("收到的禮金")
                    .font(.subheadline.weight(.bold))
                Spacer()
                // 禮金總計 Capsule 徽章
                Text(gifts.reduce(0) { $0 + $1.amount }.ntdWanString)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.pink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.pink.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.pink.opacity(0.22), lineWidth: 0.6))
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)

            ForEach(SocialSubCategory.allCases) { sub in
                let items = grouped[sub] ?? []
                if !items.isEmpty {
                    HStack(spacing: 10) {
                        // 36pt 粉色漸層圖示圓 + stroke 邊框
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.pink, .pink.opacity(0.65)],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 36, height: 36)
                            Circle()
                                .stroke(.pink.opacity(0.22), lineWidth: 1)
                                .frame(width: 36, height: 36)
                            Image(systemName: sub.icon)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        Text(sub.rawValue).font(.subheadline)
                        Spacer()
                        Text("\(items.count) 筆")
                            .font(.caption2).foregroundStyle(.secondary)
                        // 分類金額 Capsule 徽章
                        Text(items.reduce(0) { $0 + $1.amount }.ntdWanString)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.pink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.pink.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(.pink.opacity(0.22), lineWidth: 0.6))
                    }
                    .padding(.horizontal).padding(.vertical, 6)
                    Divider().padding(.leading, 58)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    var body: some View {
        // memberGifts 對全部支出做雙重 filter + sort，整頁只算一次快照後共用，
        // 避免 isEmpty 判斷與 memberGiftsSection 內部分類統計各自重新全量掃描
        let gifts = memberGifts
        return NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    eventsSection
                    if !gifts.isEmpty {
                        memberGiftsSection(gifts)
                    }
                    photosSection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
            }
            .sheet(isPresented: $addingEvent) {
                FamilyEventEditor(memberId: memberId, editing: nil)
            }
            .sheet(item: $editingEvent) { ev in
                FamilyEventEditor(memberId: memberId, editing: ev)
            }
            .sheet(isPresented: $addingPhoto) {
                FamilyAlbumPhotoEditor(memberId: memberId, editing: nil)
            }
            .sheet(item: $editingPhoto) { ph in
                FamilyAlbumPhotoEditor(memberId: memberId, editing: ph)
            }
            .sheet(item: $viewingPhotoURL) { url in
                PhotoViewerSheet(url: url)
            }
        }
    }

    private var displayName: String {
        if !member.chineseName.isEmpty { return member.chineseName }
        if !member.englishName.isEmpty { return member.englishName }
        return member.role.rawValue
    }

    // MARK: 頂部資訊 - 漸層 Hero Card + Bokeh + Spring 動畫

    private var headerCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [roleColor, roleColor.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // 散景裝飾圓 1（左上）
            Circle()
                .fill(.white.opacity(0.12))
                .blur(radius: 20)
                .frame(width: 110, height: 110)
                .offset(x: -70, y: -40)
            // 散景裝飾圓 2（右下）
            Circle()
                .fill(.white.opacity(0.07))
                .blur(radius: 28)
                .frame(width: 150, height: 150)
                .offset(x: 80, y: 50)
            // [v3] 散景裝飾圓 3（中右微光，對齊全 App 三圓規格）
            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: 55, height: 55)
                .offset(x: 30, y: 30)
                .blur(radius: 8)

            // 玻璃光澤（頂部高光）
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(
                    colors: [.white.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .center
                ))

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 82, height: 82)
                    Circle()
                        .strokeBorder(.white.opacity(0.4), lineWidth: 2)
                        .frame(width: 82, height: 82)
                    Image(systemName: member.role.icon)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white)
                }

                Text(displayName)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text(member.role.rawValue)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(.white.opacity(0.2))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    // [v3] 角色膠囊細邊框，對齊 ChildDetailView v2 / SpouseResumeView v2 規格
                    .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 0.6))

                if let bd = member.birthday {
                    Label(Self.dateFormatter.string(from: bd), systemImage: "birthday.cake.fill")
                        .font(.caption).foregroundStyle(.white.opacity(0.85))
                } else if let by = member.birthYear {
                    Label("\(by) 年生", systemImage: "birthday.cake.fill")
                        .font(.caption).foregroundStyle(.white.opacity(0.85))
                }
                if let note = member.relativeNote, !note.isEmpty {
                    Text(note).font(.caption2).foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        // [v3] RoundedRectangle stroke overlay，對齊 StockDetailView v3 / SubordinateDetailView v3 規格
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.18), lineWidth: 0.75)
        )
        .shadow(color: roleColor.opacity(0.3), radius: 12, x: 0, y: 6)
        .padding(.horizontal)
        .scaleEffect(cardAppeared ? 1 : 0.96)
        .opacity(cardAppeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { cardAppeared = true }
        }
    }

    // MARK: 紀錄章節

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeaderWithAdd("紀錄", count: member.familyEvents.count,
                                 icon: "doc.text.fill", color: .orange) {
                addingEvent = true
            }

            if member.familyEvents.isEmpty {
                emptyPlaceholder(icon: "doc.text", text: "尚無紀錄", color: .orange)
            } else {
                let sortedEvents = member.familyEvents.sorted { $0.date > $1.date }
                let lastEventId = sortedEvents.last?.id
                ForEach(Array(sortedEvents.enumerated()), id: \.element.id) { idx, ev in
                    Button { editingEvent = ev } label: {
                        HStack(spacing: 12) {
                            // 36pt 橘色漸層圖示圓 + stroke 邊框
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.orange, .orange.opacity(0.65)],
                                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 36, height: 36)
                                // [v3] 統一雙層邊框（白色外 + 橘色細描），對齊 memberGiftsSection 36pt 圖示圓規格
                                Circle()
                                    .stroke(.white.opacity(0.25), lineWidth: 1)
                                    .frame(width: 36, height: 36)
                                Circle()
                                    .stroke(.orange.opacity(0.22), lineWidth: 0.75)
                                    .frame(width: 36, height: 36)
                                Image(systemName: "calendar")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ev.title.isEmpty ? "未命名紀錄" : ev.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                if !ev.content.isEmpty {
                                    Text(ev.content)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            // 日期 Capsule 徽章
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary.opacity(0.7))
                                Text(Self.dateFormatter.string(from: ev.date))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                            // [v3] 日期膠囊細邊框，對齊 ChildDetailView v2 / SpouseResumeView v2 規格
                            .overlay(Capsule().stroke(Color(.separator).opacity(0.20), lineWidth: 0.5))
                        }
                        .padding(.horizontal).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(eventsAppeared ? 1 : 0)
                    .offset(y: eventsAppeared ? 0 : 10)
                    .animation(.spring(response: 0.48, dampingFraction: 0.8).delay(0.06 * Double(idx)),
                               value: eventsAppeared)
                    if ev.id != lastEventId {
                        Divider().padding(.leading, 60)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .onAppear {
            // [v3] easeOut → spring，對齊 FamilyView.statsStrip / SubordinateDetailView spring 規格
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.18)) {
                eventsAppeared = true
            }
        }
    }

    // MARK: 照片相簿

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeaderWithAdd("相簿", count: member.familyPhotos.count,
                                 icon: "photo.fill", color: .blue) {
                addingPhoto = true
            }

            if member.familyPhotos.isEmpty {
                emptyPlaceholder(icon: "photo", text: "尚無照片", color: .blue)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(sortedFamilyPhotos) { p in
                            Button { editingPhoto = p } label: {
                                photoCard(p)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func photoCard(_ p: FamilyAlbumPhoto) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let url = p.photoURL {
                    AsyncThumbnailView(url: url, size: CGSize(width: 130, height: 100))
                        .onTapGesture { viewingPhotoURL = url }
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 130, height: 100)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                        )
                }
            }
            Text(p.title.isEmpty ? "未命名" : p.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)
            // [v3] 日期升級為 Capsule 徽章，對齊 eventsSection 日期規格
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.7))
                Text(Self.dateFormatter.string(from: p.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6).padding(.vertical, 2.5)
            .background(Color(.tertiarySystemFill))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(.separator).opacity(0.20), lineWidth: 0.5))
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    // MARK: Helpers

    private func sectionHeaderWithAdd(
        _ title: String, count: Int, icon: String, color: Color,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.6)],
                                      startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 18)
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(title).font(.subheadline.weight(.bold))
            Capsule()
                .fill(color.opacity(0.12))
                .frame(width: 32, height: 18)
                .overlay(
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color)
                )
                .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.6))
            Spacer()
            Button(action: action) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)
    }

    private func emptyPlaceholder(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(color.opacity(0.5))
            Text(text).font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal).padding(.bottom, 12)
    }

    private func formatDate(_ d: Date) -> String {
        Self.dateFormatter.string(from: d)
    }
}

// MARK: - 紀錄編輯器

/// 紀錄／相簿編輯 Sheet 共用 Section header：4pt 漸層 Capsule 色條 + 圖示 + 粗體標題，
/// 對齊 ChildDetailView.childEditorSectionHeader／OrganizationView.orgPersonEditorSectionHeader
/// 規格；FamilyEventEditor／FamilyAlbumPhotoEditor 共用。
@ViewBuilder
private func familyEditorSectionHeader(_ title: String, icon: String, color: Color) -> some View {
    HStack(spacing: 7) {
        Capsule()
            .fill(LinearGradient(colors: [color, color.opacity(0.70)], startPoint: .top, endPoint: .bottom))
            .frame(width: 4, height: 18)
        Image(systemName: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }
}

struct FamilyEventEditor: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let memberId: UUID
    let editing: FamilyEvent?

    @State private var date: Date = Date()
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var showDeleteConfirm = false
    /// 存檔中鎖住儲存／刪除按鈕，避免 sheet 收合動畫播完前快速連點建立兩筆重複紀錄
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField("標題", text: $title)
                } header: {
                    familyEditorSectionHeader("基本資訊", icon: "person.text.rectangle", color: .indigo)
                }
                Section {
                    TextField("選填，紀錄這天的事情", text: $content, axis: .vertical)
                        .lineLimit(5...12)
                } header: {
                    familyEditorSectionHeader("內容", icon: "note.text", color: .secondary)
                }
                if editing != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("刪除紀錄", systemImage: "trash")
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .navigationTitle(editing == nil ? "新增紀錄" : "編輯紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .alert("確定刪除？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) { deleteRecord() }
                Button("取消", role: .cancel) {}
            }
            .onAppear {
                if let e = editing {
                    date = e.date; title = e.title; content = e.content
                }
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard var member = lifeStore.familyMembers.first(where: { $0.id == memberId }) else { return }
        isSaving = true
        let id = editing?.id ?? UUID()
        let newEvent = FamilyEvent(
            id: id,
            date: date,
            title: title.trimmingCharacters(in: .whitespaces),
            content: content.trimmingCharacters(in: .whitespaces)
        )
        if let idx = member.familyEvents.firstIndex(where: { $0.id == id }) {
            member.familyEvents[idx] = newEvent
        } else {
            member.familyEvents.append(newEvent)
        }
        lifeStore.update(member)
        dismiss()
    }

    private func deleteRecord() {
        guard !isSaving else { return }
        guard var member = lifeStore.familyMembers.first(where: { $0.id == memberId }),
              let e = editing else { return }
        isSaving = true
        member.familyEvents.removeAll { $0.id == e.id }
        lifeStore.update(member)
        dismiss()
    }
}

// MARK: - 相簿編輯器

struct FamilyAlbumPhotoEditor: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let memberId: UUID
    let editing: FamilyAlbumPhoto?

    @State private var date: Date = Date()
    @State private var title: String = ""
    @State private var note: String = ""
    @State private var photoFileName: String?
    @State private var pendingImageData: Data?
    // 快取解碼結果，避免 body 直接對 pendingImageData 呼叫 UIImage(data:)：
    // 標題／備註每次按鍵都會觸發 Form body 重新求值，若解碼寫在 body 裡就等於
    // 每次按鍵都在主執行緒重新解碼一次完整 JPEG（同型修復見 OrgPersonEditor.pendingImage）。
    @State private var pendingImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var isPresentingPhotoPicker: Bool = false
    // 選取照片是非同步的，若使用者在等待期間又重新選了一次（或移除照片），
    // 較慢完成的前一次選取不該覆蓋較新的狀態；用世代編號判斷是否仍是最新一次選取
    // （同型修復見 OrgPersonEditor.photoLoadGeneration）。
    @State private var photoLoadGeneration = 0
    /// 存檔中鎖住儲存／刪除按鈕，避免 sheet 收合動畫播完前快速連點建立兩筆重複紀錄
    @State private var isSaving = false
    /// 相簿選取的照片（尤其 iCloud 原圖）仍在下載/解碼時鎖住儲存按鈕，避免使用者搶先按下
    /// 「儲存」，讓 save() 在 pendingImageData 還沒寫入前就已存檔完成、選取的照片被悄悄丟棄。
    @State private var isPhotoLoading = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField("標題", text: $title)
                } header: {
                    familyEditorSectionHeader("基本資訊", icon: "person.text.rectangle", color: .indigo)
                }

                Section {
                    if let img = pendingImage {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else if let url = currentPhotoURL {
                        // 用既有的 AsyncLocalImage 背景讀檔快取，避免 title／note 每次按鍵
                        // 觸發整個 Form body 重新求值時，同步在主執行緒重讀＋重解碼 JPEG。
                        AsyncLocalImage(url: url) { img, _ in
                            if let img {
                                Image(uiImage: img)
                                    .resizable().scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: 240)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }

                    Menu {
                        Button { showCamera = true } label: { Label("拍照", systemImage: "camera.fill") }
                        Button { isPresentingPhotoPicker = true } label: {
                            Label("從相簿選取", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        HStack {
                            Image(systemName: "camera.viewfinder")
                            Text(pendingImageData != nil || photoFileName != nil ? "更換照片" : "新增照片")
                            Spacer()
                            if pendingImageData != nil || photoFileName != nil {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }

                    if pendingImageData != nil || photoFileName != nil {
                        Button(role: .destructive) {
                            // 讓任何仍在進行中的照片載入 Task 過期，避免它稍後才完成、
                            // 把已被使用者移除的照片又重新蓋回來。
                            photoLoadGeneration += 1
                            pendingImageData = nil
                            pendingImage = nil
                            if let name = photoFileName { FamilyAlbumPhoto.deletePhoto(name) }
                            photoFileName = nil
                        } label: {
                            Label("移除照片", systemImage: "xmark.circle")
                        }
                    }
                } header: {
                    familyEditorSectionHeader("照片", icon: "photo", color: .teal)
                }

                Section {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                } header: {
                    familyEditorSectionHeader("備註", icon: "note.text", color: .secondary)
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: { Label("刪除此筆", systemImage: "trash") }
                        .disabled(isSaving)
                    }
                }
            }
            .navigationTitle(editing == nil ? "新增照片" : "編輯照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving || isPhotoLoading)
                }
            }
            .alert("確定刪除？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) { deleteRecord() }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in
                    // 讓任何仍在進行中的相簿選取 Task 過期，避免它稍後才完成、
                    // 把剛拍好的照片又蓋回相簿選的舊結果。
                    photoLoadGeneration += 1
                    pendingImageData = image.jpegData(compressionQuality: 0.85)
                    pendingImage = image
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $isPresentingPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                photoLoadGeneration += 1
                let generation = photoLoadGeneration
                guard let item else { isPhotoLoading = false; return }
                isPhotoLoading = true
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        await MainActor.run { if generation == photoLoadGeneration { isPhotoLoading = false } }
                        return
                    }
                    let decoded = UIImage(data: data)
                    await MainActor.run {
                        guard generation == photoLoadGeneration else { return }
                        pendingImageData = data
                        pendingImage = decoded
                        isPhotoLoading = false
                    }
                }
            }
            .onAppear {
                if let e = editing {
                    date = e.date; title = e.title; note = e.note
                    photoFileName = e.photoFileName
                }
            }
        }
    }

    private var currentPhotoURL: URL? {
        guard let name = photoFileName else { return nil }
        return FamilyAlbumPhoto.photosDirectory.appendingPathComponent(name)
    }

    private func save() {
        guard !isSaving else { return }
        guard var member = lifeStore.familyMembers.first(where: { $0.id == memberId }) else { return }
        isSaving = true
        let id = editing?.id ?? UUID()
        if let data = pendingImageData {
            if let oldName = photoFileName { FamilyAlbumPhoto.deletePhoto(oldName) }
            // 檔名用全新 UUID（而非沿用編輯中相片項目不變的 id），確保換照片後
            // photoURL 一定改變；相簿縮圖已改用 AsyncThumbnailView 依 url 快取讀取，
            // 同路徑覆寫會讓已載入過的舊縮圖停留在畫面上不更新。
            photoFileName = FamilyAlbumPhoto.savePhoto(data, id: UUID())
        }
        let newPhoto = FamilyAlbumPhoto(
            id: id,
            date: date,
            title: title.trimmingCharacters(in: .whitespaces),
            photoFileName: photoFileName,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        if let idx = member.familyPhotos.firstIndex(where: { $0.id == id }) {
            member.familyPhotos[idx] = newPhoto
        } else {
            member.familyPhotos.append(newPhoto)
        }
        lifeStore.update(member)
        dismiss()
    }

    private func deleteRecord() {
        guard !isSaving else { return }
        guard var member = lifeStore.familyMembers.first(where: { $0.id == memberId }),
              let e = editing else { return }
        isSaving = true
        if let name = e.photoFileName { FamilyAlbumPhoto.deletePhoto(name) }
        member.familyPhotos.removeAll { $0.id == e.id }
        lifeStore.update(member)
        dismiss()
    }
}
