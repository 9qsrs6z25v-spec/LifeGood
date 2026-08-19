import SwiftUI
import UIKit

// MARK: - 完成準時度 UI（共用：部屬卡片 / 總覽 / 行事曆）

extension CompletionTiming {
    /// 標籤文字
    var label: String {
        switch self {
        case .ahead:   return "超前"
        case .onTime:  return "準時"
        case .overdue: return "逾期"
        }
    }
    /// 標籤顏色
    var color: Color {
        switch self {
        case .ahead:   return .green
        case .onTime:  return .blue
        case .overdue: return .red
        }
    }
    /// 標籤圖示
    var icon: String {
        switch self {
        case .ahead:   return "hare.fill"
        case .onTime:  return "checkmark.seal.fill"
        case .overdue: return "exclamationmark.triangle.fill"
        }
    }
}

/// 完成時間戳 + 準時度膠囊（打勾後顯示）。
/// completedAt 為 nil 時不顯示任何內容；due 為 nil 時只顯示時間戳、不判定準時度。
struct CompletionStamp: View {
    let completedAt: Date?
    let due: Date?

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d HH:mm"
        return f
    }()

    var body: some View {
        if let completedAt {
            let timing = completionTiming(completedAt: completedAt, due: due)
            HStack(spacing: 5) {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 9))
                    Text("完成 \(Self.stampFormatter.string(from: completedAt))")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color(.tertiarySystemFill)).clipShape(Capsule())

                if let timing {
                    HStack(spacing: 3) {
                        Image(systemName: timing.icon).font(.system(size: 9))
                        Text(timing.label)
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(timing.color)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(timing.color.opacity(0.15)).clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - 已完成項目收合卡（共用：部屬卡片 / 總覽 / 行事曆）

/// 已完成的單筆項目（報告 / 會議項目 / 任務）
struct CompletedEntry: Identifiable {
    enum Kind { case report, meeting, task
        var icon: String {
            switch self { case .report: return "doc.text.fill"; case .meeting: return "person.3.fill"; case .task: return "checklist" }
        }
        var color: Color {
            switch self { case .report: return .purple; case .meeting: return .indigo; case .task: return .cyan }
        }
        var label: String {
            switch self { case .report: return "報告"; case .meeting: return "會議"; case .task: return "任務" }
        }
    }
    let id: UUID
    let kind: Kind
    let title: String
    let subtitle: String?
    let completedAt: Date?
    let due: Date?
    let onTap: () -> Void
}

/// 已完成項目收合卡：可展開 / 收合，列出報告 / 會議 / 任務的完成項目 + 完成時間戳。
struct CompletedCollapsibleCard: View {
    let entries: [CompletedEntry]
    @Binding var expanded: Bool
    var title: String = "已完成"

    private var sorted: [CompletedEntry] {
        entries.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        if entries.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Capsule()
                            .fill(LinearGradient(colors: [.green, .green.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                            .frame(width: 4, height: 18)
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Color.green.opacity(0.20), Color.green.opacity(0.08)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 28, height: 28)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
                        }
                        Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                        Spacer()
                        Text("\(entries.count) 筆")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.green)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.green.opacity(0.10)).clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.green.opacity(0.22), lineWidth: 0.75))
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.top, 13).padding(.bottom, expanded ? 9 : 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    // 先捕捉一次，避免下方 idx < sorted.count - 1 每列都重新呼叫 sorted
                    // 造成整份 entries 重排一次（O(n log n) × n）。
                    let sortedEntries = sorted
                    ForEach(Array(sortedEntries.enumerated()), id: \.element.id) { idx, e in
                        Button(action: e.onTap) {
                            HStack(spacing: 11) {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [e.kind.color.opacity(0.20), e.kind.color.opacity(0.08)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: e.kind.icon).font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(e.kind.color)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(e.title.isEmpty ? "未命名\(e.kind.label)" : e.title)
                                            .font(.subheadline.weight(.medium))
                                            .strikethrough(true, color: .secondary)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Text(e.kind.label)
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                                            .background(e.kind.color.opacity(0.14))
                                            .foregroundStyle(e.kind.color)
                                            .clipShape(Capsule())
                                    }
                                    if let sub = e.subtitle, !sub.isEmpty {
                                        Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    CompletionStamp(completedAt: e.completedAt, due: e.due)
                                }
                                Spacer(minLength: 4)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if idx < sortedEntries.count - 1 { Divider().padding(.leading, 57) }
                    }
                    .padding(.bottom, 6)
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        }
    }
}

// MARK: - 美化紀錄（SubordinateDetailView）
// [2026-06] 本次美化方向：
//   1. headerCard：升級為藍色漸層英雄卡片，含縮寫頭像圓、姓名大字、
//      職等/部門白色膠囊徽章、入職日期 + spring 進場動畫（headerAppeared）；
//      statBadge 改為分隔線 KPI 橫列（白底半透明背景 + 計數大字），
//      對齊 SubordinateView.summaryStatsBar 設計語言
//   2. sectionHeader：升級為「漸層 Capsule 左側條 + 30pt 漸層圖示圓 +
//      .subheadline.weight(.bold) 標題 + 計數膠囊徽章」，
//      對齊 LifeOverviewView / CareerView section header 規格
//   3. recordRow：圖示從裸 `.caption` 升級為 36pt 漸層圓（含陰影），
//      所有標籤從 RoundedRectangle(cornerRadius:3) 改為 Capsule，
//      加入日期膠囊徽章，對齊 ExpenseRow / IncomeView.incomeRow 規格
//   4. meetingSection 列：圖示升級為 36pt 漸層圓，時長膠囊改 Capsule，
//      對齊 recordRow 規格；列間加 Divider 視覺分隔
//   5. taskSection 列：截止日標籤改 Capsule，列間加 Divider
//   6. emptyHint：從純文字升級為 40pt 圖示圓 + 文字，
//      對齊 SubordinateOverviewView.emptyHint 視覺規格
//   7. 所有 section 容器：加 shadow + 極細 overlay 邊框，
//      提升深色模式下的邊界感，對齊 OverviewView.categoryBreakdownSection
// [2026-06 v2] Tab 切換器升級：
//   8. detailTab Picker(.segmented) → @Namespace + matchedGeometryEffect 自訂彩色 Capsule Pill，
//      日常→藍色（person.2.fill）、評分系統→橘色（star.fill），
//      對齊 RealEstateDetailView.tabPicker / ChildDetailView.detailTab 設計規格；
//      Tab 切換時加 spring(response:0.3, dampingFraction:0.72) 動畫
//   9. tabSectionsAppeared：Tab 切換時重置進場動畫旗標並重播，
//      區塊以 opacity+Y offset stagger 進場，對齊 CareerView.milestoneListSection 規格
// [2026-06 v3] 英雄卡 + 圖示圓精修：
//  10. headerCard 背景：補第三顆散景圓（55pt, white.opacity(0.06), blur 8, offset(30,28)）
//      + 玻璃光澤高光覆層（LinearGradient [.white.opacity(0.18), .clear] top→center），
//      對齊 SubordinateOverviewView v2 / ChildDetailView v2 三圓散景 + 玻璃光澤規格。
//  11. headerCard shadow：從單層 black.opacity(0.42) 升級為雙層
//      （藍色主光暈 opacity 0.42 + 黑底基礎 0.09），提升立體感，
//      對齊 SubordinateOverviewView v3 / MyCalendarView.calendarHeroCard 雙層 shadow 規格。
//  12. joinDate 入職日期列：從裸 caption2 文字升級為 tertiarySystemFill 底色 Capsule 徽章
//      + calendar.badge.clock 圖示，對齊 CareerView.careerRow / OverviewView.recentRow 日期膠囊規格。
//  13. recordRow 圖示圓：補 Circle().stroke(color.opacity(0.22), lineWidth: 1.0)，
//      對齊 ChildDetailView v2 / SpouseResumeView v2 的 36pt 圓形邊框規格。
//  14. recordRow 假別/嚴重度膠囊：補 Capsule().stroke(color.opacity(0.22), lineWidth: 0.6)，
//      對齊 taskSection 截止日膠囊 / SubordinateOverviewView v2 彩色膠囊細邊框規格。
//  15. meetingSection 圖示圓：補 Circle().stroke(Color.indigo.opacity(0.22), lineWidth: 1.0)，
//      統一 meetingSection / recordSection 圖示圓邊框語言。

struct SubordinateDetailView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let subordinateId: UUID
    @State private var showEdit = false
    @State private var showPromotion = false   // 升職表單
    @State private var showCompleted = false
    @State private var previewItem: SubordinateItemRef?
    @State private var addingType: SubordinateRecordType?
    @State private var editingRecord: SubordinateRecord?
    @State private var addingMeeting = false
    @State private var editingMeeting: SubordinateMeeting?
    @State private var addingTask = false
    @State private var editingTask: SubordinateTask?
    @State private var addingReport = false
    @State private var editingReport: WeeklyReport?
    @State private var showPremiumAlert = false
    @State private var shareItem: CardSharePayload?

    // 進場動畫旗標
    @State private var headerAppeared = false
    // Tab 區塊進場旗標：切換 Tab 時重置並重播
    @State private var tabSectionsAppeared = false
    /// tabSectionsAppeared 重播延遲任務：50ms 內快速切換 Tab 會疊出多個 asyncAfter，
    /// 較舊的一個可能在較新的已把旗標設回 true 之後才觸發，動畫倒退造成閃爍；
    /// 改用可取消的 Task（比照 MainTabView.micEnterTask 既有寫法），切換時先取消前一個再排新的。
    @State private var tabSectionsAppearTask: Task<Void, Never>?

    enum DetailTab: String, CaseIterable { case daily = "主動性"; case rating = "潛力性"; case duty = "執掌" }
    @State private var detailTab: DetailTab = .daily
    /// 兼任職務：檢視中的職務（點卡片開該職務的管理頁）
    @State private var viewingSideRole: LifeMilestone?
    /// 「加入兼任職務」挑選面板
    @State private var showJoinSideRole = false
    // matchedGeometryEffect：Tab 指示器平滑滑動（對齊 RealEstateDetailView / ChildDetailView 規格）
    @Namespace private var tabNamespace

    init(subordinate: Subordinate) { self.subordinateId = subordinate.id }

    private var subordinate: Subordinate {
        lifeStore.subordinates.first(where: { $0.id == subordinateId }) ?? Subordinate(name: "")
    }

    private var gradeTitleText: String {
        if let gt = lifeStore.gradeTitles.first(where: { $0.id == subordinate.gradeTitleId }) {
            return "\(gt.grade) — \(gt.title)"
        }
        return subordinate.jobTitle
    }

    private var departmentText: String {
        if let dept = lifeStore.departments.first(where: { $0.id == subordinate.departmentId }) {
            return dept.code.isEmpty ? dept.name : "\(dept.code) \(dept.name)"
        }
        return subordinate.department
    }

    var body: some View {
        // mentionedItems 會對「全部部屬」的 tasks/meetings/reports 做一次全量標註掃描，
        // 整頁需要用到 5 次（tab 徽章、分數看板 x2、KPI 統計、mentionedSection），
        // 這裡只算一次快取供全部呼叫點共用，避免同一次 render 重複掃描 5 次。
        let mentionedItemsCache = mentionedItems
        return NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard(mentionedCount: mentionedItemsCache.count)

                    // 自訂 Capsule Pill Tab 切換器（matchedGeometryEffect 讓指示器平滑滑動）
                    // 日常→藍色 / 評分系統→橘色，對齊 RealEstateDetailView.tabPicker 規格
                    HStack(spacing: 0) {
                        ForEach(DetailTab.allCases, id: \.self) { tab in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                                    detailTab = tab
                                }
                                // 切換 Tab 時重置進場動畫，讓新 Tab 區塊重新滑入
                                tabSectionsAppeared = false
                                tabSectionsAppearTask?.cancel()
                                tabSectionsAppearTask = Task {
                                    try? await Task.sleep(nanoseconds: 50_000_000)
                                    guard !Task.isCancelled else { return }
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                        tabSectionsAppeared = true
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: tabIcon(tab))
                                        .font(.caption2)
                                    Text(tab.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(tabBadgeValue(tab, mentionedCount: mentionedItemsCache.count))")
                                        .font(.caption.weight(.bold))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .foregroundStyle(detailTab == tab ? .white : .secondary)
                                .background {
                                    if detailTab == tab {
                                        Capsule()
                                            .fill(tabTint(tab))
                                            .matchedGeometryEffect(id: "subDetailTabIndicator", in: tabNamespace)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
                    .padding(.horizontal)
                    .onAppear {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.10)) {
                            tabSectionsAppeared = true
                        }
                    }
                    .onDisappear {
                        // 畫面關閉時取消尚未觸發的 Tab 切換重播任務，避免 sheet 收合中途
                        // 仍在 50ms 延遲內的 Task 補跑 withAnimation，在已消失的畫面上留下動畫殘留
                        tabSectionsAppearTask?.cancel()
                    }

                    if detailTab == .daily {
                        weeklyReportSection
                            .opacity(tabSectionsAppeared ? 1 : 0)
                            .offset(y: tabSectionsAppeared ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.00), value: tabSectionsAppeared)
                        meetingSection
                            .opacity(tabSectionsAppeared ? 1 : 0)
                            .offset(y: tabSectionsAppeared ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.03), value: tabSectionsAppeared)
                        taskSection
                            .opacity(tabSectionsAppeared ? 1 : 0)
                            .offset(y: tabSectionsAppeared ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.05), value: tabSectionsAppeared)
                        mentionedSection(mentionedItemsCache)
                            .opacity(tabSectionsAppeared ? 1 : 0)
                            .offset(y: tabSectionsAppeared ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.07), value: tabSectionsAppeared)
                        sideRoleSection
                            .opacity(tabSectionsAppeared ? 1 : 0)
                            .offset(y: tabSectionsAppeared ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.09), value: tabSectionsAppeared)
                        recordSection(.leave)
                            .opacity(tabSectionsAppeared ? 1 : 0)
                            .offset(y: tabSectionsAppeared ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.10), value: tabSectionsAppeared)
                        completedSection
                            .opacity(tabSectionsAppeared ? 1 : 0)
                            .offset(y: tabSectionsAppeared ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.13), value: tabSectionsAppeared)
                    } else if detailTab == .duty {
                        SubordinateEquipmentSection(subordinateId: subordinateId)
                            .opacity(tabSectionsAppeared ? 1 : 0)
                            .offset(y: tabSectionsAppeared ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.00), value: tabSectionsAppeared)
                        SubordinateEquipmentTimelineSection(subordinateId: subordinateId)
                            .opacity(tabSectionsAppeared ? 1 : 0)
                            .offset(y: tabSectionsAppeared ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.05), value: tabSectionsAppeared)
                    } else {
                        promotionSection
                            .opacity(tabSectionsAppeared ? 1 : 0)
                            .offset(y: tabSectionsAppeared ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.00), value: tabSectionsAppeared)
                        proConSection
                            .opacity(tabSectionsAppeared ? 1 : 0)
                            .offset(y: tabSectionsAppeared ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.00), value: tabSectionsAppeared)
                        recordSection(.achievement)
                            .opacity(tabSectionsAppeared ? 1 : 0)
                            .offset(y: tabSectionsAppeared ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.05), value: tabSectionsAppeared)
                        recordSection(.improvement)
                            .opacity(tabSectionsAppeared ? 1 : 0)
                            .offset(y: tabSectionsAppeared ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.10), value: tabSectionsAppeared)
                        recordSection(.fault)
                            .opacity(tabSectionsAppeared ? 1 : 0)
                            .offset(y: tabSectionsAppeared ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.15), value: tabSectionsAppeared)
                        recordSection(.missOperation)
                            .opacity(tabSectionsAppeared ? 1 : 0)
                            .offset(y: tabSectionsAppeared ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.20), value: tabSectionsAppeared)
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("部屬卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Menu {
                            Button { exportJPG(mentioned: mentionedItemsCache) } label: { Label("匯出圖片", systemImage: "photo") }
                            Button { exportText(mentioned: mentionedItemsCache) } label: { Label("匯出文字", systemImage: "text.alignleft") }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        // 升職（使用者指定）：付費鎖比照編輯
                        Button {
                            if subscription.isPremium { showPromotion = true }
                            else { showPremiumAlert = true }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                        }
                        Button("編輯") {
                            if subscription.isPremium { showEdit = true }
                            else { showPremiumAlert = true }
                        }.foregroundStyle(.green)
                    }
                }
            }
            .sheet(item: $shareItem) { item in ShareSheet(items: item.items) }
            .sheet(isPresented: $showPromotion) { PromotionSheet(subordinateId: subordinateId) }
            .sheet(item: $viewingSideRole) { role in
                // 不給跳回部屬明細：我們就是從那裡進來的，會無限疊 sheet
                SideRoleWorkspaceView(roleId: role.id, allowSubordinateJump: false)
            }
            .sheet(isPresented: $showJoinSideRole) {
                NavigationStack {
                    SideRoleJoinPicker(personId: subordinateId, personName: subordinate.name)
                }
            }
            .sheet(isPresented: $showEdit) { AddSubordinateView(editing: subordinate) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .sheet(item: $addingType) { type in
                RecordEditorSheet(subordinateId: subordinateId, type: type, editing: nil)
            }
            .sheet(item: $editingRecord) { rec in
                RecordEditorSheet(subordinateId: subordinateId, type: rec.type, editing: rec)
            }
            .sheet(isPresented: $addingMeeting) {
                MeetingEditorSheet(subordinateId: subordinateId, editing: nil)
            }
            .sheet(item: $editingMeeting) { m in
                MeetingEditorSheet(subordinateId: subordinateId, editing: m)
            }
            .sheet(isPresented: $addingReport) {
                WeeklyReportEditorSheet(subordinateId: subordinateId, editing: nil)
            }
            .sheet(item: $editingReport) { r in
                WeeklyReportEditorSheet(subordinateId: subordinateId, editing: r)
            }
            .sheet(isPresented: $addingTask) {
                TaskEditorSheet(subordinateId: subordinateId, editing: nil)
            }
            .sheet(item: $editingTask) { t in
                TaskEditorSheet(subordinateId: subordinateId, editing: t)
            }
            .sheet(item: $previewItem) { ref in
                SubordinateItemCard(ref: ref)
            }
        }
    }

    // MARK: - 英雄頭部卡片

    /// 這位部屬在兼任職務裡的待辦統計（完成／總數）。
    /// 只看一個人，直接查自己的即可，不必跑整批 sideRoleTaskCounts()。
    private var sideRoleStat: (done: Int, total: Int) {
        var done = 0, total = 0
        for role in lifeStore.sideRoles {
            guard let m = role.sideRoleMembers?.first(where: { $0.linkedPersonId == subordinate.id })
            else { continue }
            for t in role.sideRoleTasks ?? [] where t.assigneeIds?.contains(m.id) == true {
                total += 1
                if t.isCompleted { done += 1 }
            }
        }
        return (done, total)
    }

    private func headerCard(mentionedCount: Int) -> some View {
        let initials = String(subordinate.name.prefix(2))
        // 一次計算所有類型計數，避免 KPI 橫列 5 個 statBadge 各自 O(n) 掃描 records
        let recordCounts = subordinate.records.reduce(into: [SubordinateRecordType: Int]()) { $0[$1.type, default: 0] += 1 }
        return VStack(spacing: 0) {
            // 頂部：縮寫頭像 + 姓名 + 職等/部門膠囊
            HStack(alignment: .center, spacing: 14) {
                // 縮寫頭像圓（白色半透明底）
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.25))
                        .frame(width: 54, height: 54)
                    Circle()
                        .stroke(.white.opacity(0.40), lineWidth: 1.5)
                        .frame(width: 54, height: 54)
                    Text(initials)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(subordinate.name)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    // 職等 + 部門膠囊
                    HStack(spacing: 5) {
                        if !gradeTitleText.isEmpty {
                            Text(gradeTitleText)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.white.opacity(0.22))
                                .clipShape(Capsule())
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        if !departmentText.isEmpty {
                            Text(departmentText)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.88))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.white.opacity(0.14))
                                .clipShape(Capsule())
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            // [v3] 入職日期 Capsule 徽章（對齊 CareerView / OverviewView.recentRow 規格）
            if let jd = subordinate.joinDate {
                HStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 9))
                        Text("入職 \(formatDate(jd))")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.16))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.6))
                    Spacer()
                }
                .padding(.top, 10)
            }

            // 分數看板：主動性 / 潛力性 / 綜合
            HStack(spacing: 0) {
                HeroKpiCell(label: "主動性", value: "\(subordinate.proactivityScore(mentionedCount: mentionedCount, sideRoleDone: sideRoleStat.done))",
                            icon: "bolt.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "潛力性", value: "\(subordinate.potentialScore)",
                            icon: "arrow.up.right.circle.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "綜合", value: "\(subordinate.overallScore(mentionedCount: mentionedCount, sideRoleDone: sideRoleStat.done))",
                            icon: "star.fill")
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.18), lineWidth: 0.75))
            .padding(.top, 14)

            // 分隔線
            Rectangle()
                .fill(.white.opacity(0.20))
                .frame(height: 0.5)
                .padding(.vertical, 14)

            // KPI 橫列：優點 / 缺點 / 成就 / Miss / 請假
            HStack(spacing: 0) {
                HeroKpiCell(label: "優點", value: "\(recordCounts[.pro] ?? 0)",
                            icon: "hand.thumbsup.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "缺點", value: "\(recordCounts[.con] ?? 0)",
                            icon: "hand.thumbsdown.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "成就", value: "\(recordCounts[.achievement] ?? 0)",
                            icon: "trophy.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "Miss", value: "\(recordCounts[.missOperation] ?? 0)",
                            icon: "exclamationmark.triangle.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "請假", value: "\(recordCounts[.leave] ?? 0)",
                            icon: "calendar.badge.minus")
            }
            .padding(.vertical, 8)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // 第二列 KPI：報告 / 會議 / 任務 / 被標註 / 請假
            HStack(spacing: 0) {
                HeroKpiCell(label: "報告", value: "\(subordinate.weeklyReports.count)",
                            icon: "doc.text.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "會議", value: "\(subordinate.meetings.count)",
                            icon: "person.3.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "任務", value: "\(subordinate.tasks.count)",
                            icon: "checklist")
                HeroKpiDivider()
                HeroKpiCell(label: "被標註", value: "\(mentionedCount)",
                            icon: "at")
                HeroKpiDivider()
                HeroKpiCell(label: "請假", value: "\(recordCounts[.leave] ?? 0)",
                            icon: "calendar.badge.minus")
            }
            .padding(.vertical, 8)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 8)
        }
        .padding(20)
        .heroCardShell(card: .subordinateDetail)
        .padding(.horizontal)
        .opacity(headerAppeared ? 1 : 0)
        .offset(y: headerAppeared ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                headerAppeared = true
            }
        }
    }

    // KPI 單格：白色大數字 + 小標籤（對齊 FixedExpenseView 英雄卡 KPI 橫列規格）

    // 分數看板單格：大白數字 + 標籤

    // MARK: - 會議章節

    // MARK: - 報告章節

    private var weeklyReportSection: some View {
        let items = subordinate.weeklyReports.filter { !$0.isCompleted }.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("報告", icon: "doc.text.fill", color: .purple, count: items.count) {
                Button {
                    if subscription.isPremium { addingReport = true } else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.purple)
                }
            }
            if items.isEmpty {
                emptyHint
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, r in
                    HStack(alignment: .center, spacing: 10) {
                        Button {
                            lifeStore.toggleWeeklyReportCompletion(subordinateId: subordinateId, reportId: r.id)
                        } label: {
                            Image(systemName: r.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(r.isCompleted ? Color.green : Color.purple)
                        }
                        .buttonStyle(.plain)

                        Button {
                            if subscription.isPremium { previewItem = .report(subId: subordinateId, report: r) } else { showPremiumAlert = true }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(r.topic.isEmpty ? "未命名報告" : r.topic)
                                    .font(.subheadline.weight(.medium))
                                    .strikethrough(r.isCompleted, color: .secondary)
                                    .foregroundStyle(r.isCompleted ? .secondary : .primary)
                                    .lineLimit(1)
                                HStack(spacing: 3) {
                                    Image(systemName: "calendar").font(.system(size: 8))
                                    Text(formatDate(r.date))
                                }
                                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill)).clipShape(Capsule())
                                if !r.note.isEmpty {
                                    Text(r.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                if r.isCompleted {
                                    CompletionStamp(completedAt: r.completedAt, due: r.date)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .opacity(r.isCompleted ? 0.7 : 1)
                    if idx < items.count - 1 { Divider().padding(.leading, 64) }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - 已完成（報告 / 會議項目 / 任務）收合於最下方

    private var completedEntries: [CompletedEntry] {
        var out: [CompletedEntry] = []
        for r in subordinate.weeklyReports where r.isCompleted {
            out.append(CompletedEntry(id: r.id, kind: .report, title: r.topic,
                                      subtitle: r.note.isEmpty ? nil : r.note,
                                      completedAt: r.completedAt, due: r.date,
                                      onTap: { if subscription.isPremium { previewItem = .report(subId: subordinateId, report: r) } else { showPremiumAlert = true } }))
        }
        for m in subordinate.meetings {
            for item in m.allItems where item.isCompleted {
                out.append(CompletedEntry(id: item.id, kind: .meeting, title: item.content,
                                          subtitle: m.topic.isEmpty ? "會議" : m.topic,
                                          completedAt: item.completedAt, due: item.dueDate,
                                          onTap: { if subscription.isPremium { previewItem = .meeting(subId: subordinateId, meeting: m) } else { showPremiumAlert = true } }))
            }
        }
        for t in subordinate.tasks where t.isCompleted {
            out.append(CompletedEntry(id: t.id, kind: .task, title: t.topic,
                                      subtitle: t.content.isEmpty ? nil : t.content,
                                      completedAt: t.completedAt, due: t.dueDate,
                                      onTap: { if subscription.isPremium { previewItem = .task(subId: subordinateId, task: t) } else { showPremiumAlert = true } }))
        }
        return out
    }

    private var completedSection: some View {
        CompletedCollapsibleCard(entries: completedEntries, expanded: $showCompleted)
            .padding(.horizontal)
    }

    // MARK: - 被標註的項目（此部屬被 @ 標註的任務/會議/報告）

    /// 全部部屬的任務/會議/報告中，內容或備註 @ 標註到「本人」的項目
    private var mentionedItems: [SubordinateItemRef] {
        let me = subordinate.id
        let sortedPeople = MentionText.sortedByNameLengthDescending(lifeStore.mentionPeople())
        func hit(_ texts: String...) -> Bool {
            texts.contains { MentionText.mentionedIDs(in: $0, sortedPeople: sortedPeople).contains(me) }
        }
        var out: [SubordinateItemRef] = []
        for s in lifeStore.subordinates {
            for t in s.tasks where hit(t.content, t.note) {
                out.append(.task(subId: s.id, task: t))
            }
            for m in s.meetings {
                let itemsText = m.allItems.map(\.content).joined(separator: "\n")
                if hit(m.note, itemsText) { out.append(.meeting(subId: s.id, meeting: m)) }
            }
            for r in s.weeklyReports where hit(r.note) {
                out.append(.report(subId: s.id, report: r))
            }
        }
        return out
    }

    private func mentionedRowInfo(_ ref: SubordinateItemRef)
        -> (icon: String, color: Color, title: String, owner: String, kind: String) {
        func owner(_ id: UUID) -> String {
            let n = lifeStore.subordinates.first { $0.id == id }?.name ?? ""
            return n.isEmpty ? "未命名" : n
        }
        switch ref {
        case .task(let s, let t):    return ("checklist", .cyan, t.topic.isEmpty ? "未命名任務" : t.topic, owner(s), "任務")
        case .meeting(let s, let m): return ("person.3.fill", .indigo, m.topic.isEmpty ? "未命名會議" : m.topic, owner(s), "會議")
        case .report(let s, let r):  return ("doc.text.fill", .purple, r.topic.isEmpty ? "未命名報告" : r.topic, owner(s), "報告")
        case .leave(let s, let rec): return ("calendar.badge.minus", .teal, rec.leaveType?.rawValue ?? "請假", owner(s), "請假")
        case .record(let s, let rec): return (rec.type.icon, colorFor(rec.type), rec.content.isEmpty ? rec.type.rawValue : rec.content, owner(s), rec.type.rawValue)
        }
    }

    private func mentionedSection(_ items: [SubordinateItemRef]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("被標註的項目", icon: "at", color: .pink, count: items.count) { EmptyView() }
            if items.isEmpty {
                emptyHint
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, ref in
                    Button { previewItem = ref } label: { mentionedRow(ref) }
                        .buttonStyle(.plain)
                    if idx < items.count - 1 { Divider().padding(.leading, 58) }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - 兼任職務參與

    /// 這位部屬參與了哪些兼任職務、各自負責幾則待辦。
    /// 掛在「主動性」分頁——兼任待辦本來就計入主動性分數，放這裡口徑一致。
    private var sideRoleSection: some View {
        let parts = lifeStore.sideRoleParticipations(of: subordinateId)
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("兼任職務參與", icon: "person.badge.plus", color: .indigo,
                          count: parts.count) {
                Button {
                    guard subscription.isPremium else { showPremiumAlert = true; return }
                    showJoinSideRole = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.indigo)
                }
                .buttonStyle(.plain)
            }
            if parts.isEmpty {
                emptyHint
            } else {
                ForEach(Array(parts.enumerated()), id: \.element.role.id) { idx, p in
                    Button { viewingSideRole = p.role } label: { sideRoleRow(p.role, member: p.member) }
                        .buttonStyle(.plain)
                    if idx < parts.count - 1 { Divider().padding(.leading, 58) }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    private func sideRoleRow(_ role: LifeMilestone, member: SideRoleMember) -> some View {
        let tasks = lifeStore.sideRoleTasks(of: member.id, in: role)
        let done = tasks.filter(\.isCompleted).count
        return HStack(spacing: 11) {
            ZStack {
                Circle().fill(LinearGradient(colors: [.indigo.opacity(0.20), .indigo.opacity(0.08)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.indigo)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(SideRoleFormat.displayName(role))
                        .font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    if role.isActiveSideRole {
                        Text("在任").font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background(Color.indigo.opacity(0.14))
                            .foregroundStyle(.indigo).clipShape(Capsule())
                    }
                }
                Text([member.dutyInRole, SideRoleFormat.period(role)]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if !tasks.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "checklist").font(.system(size: 9))
                    Text("\(done)/\(tasks.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(done == tasks.count ? .green : .indigo)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background((done == tasks.count ? Color.green : Color.indigo).opacity(0.12))
                .clipShape(Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func mentionedRow(_ ref: SubordinateItemRef) -> some View {
        let info = mentionedRowInfo(ref)
        return HStack(spacing: 11) {
            ZStack {
                Circle().fill(LinearGradient(colors: [info.color.opacity(0.20), info.color.opacity(0.08)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 34, height: 34)
                Image(systemName: info.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(info.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(info.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    Text(info.kind).font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                        .background(info.color.opacity(0.14)).foregroundStyle(info.color).clipShape(Capsule())
                }
                Text("來自 \(info.owner)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var meetingSection: some View {
        let items = subordinate.meetings.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("會議", icon: "person.3.fill", color: .indigo, count: items.count) {
                Button {
                    if subscription.isPremium { addingMeeting = true }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.indigo)
                }
            }
            if items.isEmpty {
                emptyHint
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, m in
                    Button {
                        if subscription.isPremium { previewItem = .meeting(subId: subordinateId, meeting: m) }
                        else { showPremiumAlert = true }
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            // [v3] 36pt 漸層圖示圓 + 陰影 + 細邊框（對齊 recordRow v3 規格）
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.indigo.opacity(0.20), Color.indigo.opacity(0.08)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 36, height: 36)
                                    .shadow(color: Color.indigo.opacity(0.18), radius: 5, x: 0, y: 2)
                                Circle()
                                    .stroke(Color.indigo.opacity(0.22), lineWidth: 1.0)
                                    .frame(width: 36, height: 36)
                                Image(systemName: "person.3.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.indigo)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(m.topic.isEmpty ? "未命名會議" : m.topic)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                HStack(spacing: 5) {
                                    // 日期膠囊
                                    HStack(spacing: 3) {
                                        Image(systemName: "calendar")
                                            .font(.system(size: 8))
                                        Text(formatDateTime(m.date))
                                    }
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color(.tertiarySystemFill))
                                    .clipShape(Capsule())

                                    // 時長 Capsule
                                    Text("\(m.durationMinutes) 分鐘")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.indigo.opacity(0.12))
                                        .foregroundStyle(.indigo)
                                        .clipShape(Capsule())

                                    if let r = m.recurrence {
                                        Text(r.rawValue)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    let pending = m.allItems.filter { !$0.isCompleted }
                                    if !pending.isEmpty {
                                        Text("\(pending.count) 個待辦項目")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // 議程項目（僅未完成；已完成移至底部「已完成」收合區）
                    let pendingItems = m.allItems.filter { !$0.isCompleted }
                    if !pendingItems.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(pendingItems) { item in
                                meetingItemRow(meeting: m, item: item)
                            }
                        }
                        .padding(.leading, 64)
                        .padding(.trailing, 16)
                        .padding(.bottom, 8)
                    }

                    if idx < items.count - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    /// 會議議程項目列：左側打勾圓圈（切換完成）+ 內容（完成時刪除線）。
    private func meetingItemRow(meeting m: SubordinateMeeting, item: MeetingItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                lifeStore.toggleMeetingItemCompletion(subordinateId: subordinateId, meetingId: m.id, itemId: item.id)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(item.isCompleted ? Color.green : Color.indigo.opacity(0.55))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.content.isEmpty ? "未填內容" : item.content)
                    .font(.caption)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .lineLimit(3)
                if item.isCompleted {
                    CompletionStamp(completedAt: item.completedAt, due: item.dueDate)
                }
            }

            Spacer(minLength: 0)

            if let due = item.dueDate {
                let c = Calendar.current.dateComponents([.hour, .minute], from: due)
                Text((c.hour == 0 && c.minute == 0) ? formatDate(due) : formatDateTime(due))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
        .opacity(item.isCompleted ? 0.7 : 1)
    }

    // MARK: - 任務章節

    private var taskSection: some View {
        // 僅顯示未完成；已完成移至底部「已完成」收合區
        let items = subordinate.tasks.filter { !$0.isCompleted }.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("任務", icon: "checklist", color: .cyan, count: items.count) {
                Button {
                    if subscription.isPremium { addingTask = true }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.cyan)
                }
            }
            if items.isEmpty {
                emptyHint
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, t in
                    HStack(alignment: .center, spacing: 10) {
                        // 左側可點打勾圓圈：直接切換完成，不進編輯頁
                        Button {
                            lifeStore.toggleTaskCompletion(subordinateId: subordinateId, taskId: t.id)
                        } label: {
                            Image(systemName: t.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(t.isCompleted ? Color.green : Color.cyan)
                        }
                        .buttonStyle(.plain)

                        Button {
                            if subscription.isPremium { previewItem = .task(subId: subordinateId, task: t) }
                            else { showPremiumAlert = true }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.topic.isEmpty ? "未命名任務" : t.topic)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(t.isCompleted ? .secondary : .primary)
                                    .strikethrough(t.isCompleted, color: .secondary)
                                    .lineLimit(1)
                                HStack(spacing: 5) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "calendar")
                                            .font(.system(size: 8))
                                        Text(formatDateTime(t.date))
                                    }
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color(.tertiarySystemFill))
                                    .clipShape(Capsule())

                                    if let due = t.dueDate {
                                        let isOverdue = due < Date() && !t.isCompleted
                                        let dueColor: Color = isOverdue ? .red : .cyan
                                        HStack(spacing: 3) {
                                            Image(systemName: "flag.fill")
                                                .font(.system(size: 7))
                                            Text("截止 \(formatDate(due))")
                                        }
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(dueColor.opacity(0.12))
                                        .foregroundStyle(dueColor)
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(dueColor.opacity(0.22), lineWidth: 0.6))
                                    }
                                    // 與兼任待辦連動：打勾會同步兩邊，評分也只算一次
                                    if let back = t.sideRoleLink {
                                        SideRoleLinkBadge(back: back)
                                    }
                                }
                                if t.isCompleted {
                                    CompletionStamp(completedAt: t.completedAt, due: t.dueDate)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .opacity(t.isCompleted ? 0.6 : 1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if idx < items.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - 優缺點

    /// 升職歷程（潛力性分頁）：from → to 時間軸，新到舊；無紀錄時整卡隱藏。
    /// 紀錄由工具列「升職」按鈕（PromotionSheet）產生。
    @ViewBuilder
    private var promotionSection: some View {
        let promotions = subordinate.promotions.sorted { $0.date > $1.date }
        if !promotions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("升職歷程", icon: "arrow.up.right.circle.fill", color: .orange,
                              count: promotions.count) { }
                ForEach(Array(promotions.enumerated()), id: \.element.id) { idx, p in
                    promotionRow(p)
                    if idx < promotions.count - 1 {
                        Divider().padding(.leading, 62)
                    }
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
            )
            .shadow(color: Color.orange.opacity(0.12), radius: 10, x: 0, y: 4)
            .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
            .padding(.horizontal)
        }
    }

    private func promotionRow(_ p: PromotionRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [Color.orange.opacity(0.22), Color.orange.opacity(0.10)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.orange.opacity(0.20), lineWidth: 0.75))
                    .shadow(color: Color.orange.opacity(0.18), radius: 5, x: 0, y: 2)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 4) {
                // from → to（from 可能為空：首任職稱直接顯示 to）
                HStack(spacing: 5) {
                    if !p.fromTitle.isEmpty {
                        Text(p.fromTitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .strikethrough(false)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                    Text(p.toTitle.isEmpty ? "—" : p.toTitle)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.primary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9))
                        Text(formatDate(p.date))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
                    if !p.note.isEmpty {
                        Text(p.note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var proConSection: some View {
        let items = subordinate.records.filter { $0.type == .pro || $0.type == .con }.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("優缺點", icon: "hand.thumbsup.fill", color: .green, count: items.count) {
                Menu {
                    Button {
                        if subscription.isPremium { addingType = .pro }
                        else { showPremiumAlert = true }
                    } label: { Label("優點", systemImage: "hand.thumbsup.fill") }
                    Button {
                        if subscription.isPremium { addingType = .con }
                        else { showPremiumAlert = true }
                    } label: { Label("缺點", systemImage: "hand.thumbsdown.fill") }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                }
            }
            if items.isEmpty {
                emptyHint
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, rec in
                    recordRow(rec)
                    if idx < items.count - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - 通用記錄章節

    private func recordSection(_ type: SubordinateRecordType) -> some View {
        let items = subordinate.records.filter { $0.type == type }.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader(type.rawValue, icon: type.icon, color: colorFor(type), count: items.count) {
                Button {
                    if subscription.isPremium { addingType = type }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(colorFor(type))
                }
            }
            if items.isEmpty {
                emptyHint
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, rec in
                    recordRow(rec)
                    if idx < items.count - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }

    // MARK: - Section Header（漸層側條 + 漸層圖示圓 + 計數膠囊）

    private func sectionHeader<Action: View>(
        _ title: String,
        icon: String,
        color: Color,
        count: Int? = nil,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(spacing: 10) {
            // 漸層 Capsule 側條
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 18)
            // 30pt 漸層圖示圓
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.20), color.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                Circle()
                    .stroke(color.opacity(0.20), lineWidth: 1)
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.subheadline.weight(.bold))
            Spacer()
            // 計數膠囊（有資料時顯示）
            if let c = count, c > 0 {
                Text("\(c) 筆")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.75))
            }
            action()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - 通用記錄列（36pt 漸層圖示圓 + Capsule 標籤）

    private func recordRow(_ rec: SubordinateRecord) -> some View {
        let color = colorFor(rec.type)
        return Button {
            guard subscription.isPremium else { showPremiumAlert = true; return }
            previewItem = rec.type == .leave ? .leave(subId: subordinateId, rec: rec)
                                             : .record(subId: subordinateId, rec: rec)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                // [v3] 36pt 漸層圖示圓 + 陰影 + 細邊框
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.22), color.opacity(0.09)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .shadow(color: color.opacity(0.20), radius: 5, x: 0, y: 2)
                    Circle()
                        .stroke(color.opacity(0.22), lineWidth: 1.0)
                        .frame(width: 36, height: 36)
                    Image(systemName: rec.type.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(rec.content)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 5) {
                        // 日期膠囊
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 8))
                            Text(formatDate(rec.date))
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())

                        // [v3] 嚴重度 Capsule + stroke 細邊框（失誤操作）
                        if rec.type == .missOperation, let sev = rec.severity {
                            Text(sev.rawValue)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(severityColor(sev).opacity(0.15))
                                .foregroundStyle(severityColor(sev))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(severityColor(sev).opacity(0.22), lineWidth: 0.6))
                        }
                        // [v3] 假別 Capsule + stroke 細邊框（請假）
                        if rec.type == .leave {
                            if let lt = rec.leaveType {
                                Text(lt.rawValue)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.teal.opacity(0.15))
                                    .foregroundStyle(.teal)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.teal.opacity(0.22), lineWidth: 0.6))
                            }
                            if let h = rec.leaveHours, h > 0 {
                                Text(h.truncatingRemainder(dividingBy: 1) == 0
                                     ? "\(Int(h))h" : String(format: "%.1fh", h))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        // 備註指示圖示
                        if !rec.note.isEmpty {
                            Image(systemName: "note.text")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 空狀態提示（40pt 圖示圓 + 文字，對齊 SubordinateOverviewView.emptyHint 規格）

    private var emptyHint: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 40, height: 40)
                Image(systemName: "tray")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(.secondary)
            }
            Text("尚無記錄")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // Tab 主題色（對齊 ChildDetailView.tabTint 規格）
    private func tabTint(_ tab: DetailTab) -> Color {
        switch tab {
        case .daily: return Color(red: 0.22, green: 0.53, blue: 0.98)   // 藍
        case .rating: return Color(red: 0.96, green: 0.55, blue: 0.18)  // 橘
        case .duty: return Color(red: 0.18, green: 0.62, blue: 0.60)    // 藍綠
        }
    }

    private func tabIcon(_ tab: DetailTab) -> String {
        switch tab {
        case .daily: return "person.2.fill"
        case .rating: return "star.fill"
        case .duty: return "wrench.and.screwdriver.fill"
        }
    }

    /// Tab 徽章數字：主動性/潛力性顯示分數，執掌顯示設備台數
    private func tabBadgeValue(_ tab: DetailTab, mentionedCount: Int) -> Int {
        switch tab {
        case .daily: return subordinate.proactivityScore(mentionedCount: mentionedCount, sideRoleDone: sideRoleStat.done)
        case .rating: return subordinate.potentialScore
        case .duty: return subordinate.equipments.count
        }
    }

    // MARK: - 匯出圖片

    private static let stampFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmm"; return f
    }()

    /// 把部屬卡片（英雄卡 + 目前分頁全部章節）渲染成 JPG 並開啟系統分享面板
    /// （對齊 TalentMatrixView.exportJPG／SubordinateItemCard.shareJPG 既有規格）。
    @MainActor
    private func exportJPG(mentioned: [SubordinateItemRef]) {
        let content = exportContent(mentioned: mentioned)
            .frame(width: 430)
            .padding(.vertical, 20)
            .background(Color(.systemGroupedBackground))
            .environmentObject(lifeStore)
            .environmentObject(subscription)
        let renderer = ImageRenderer(content: content)
        renderer.scale = max(UIScreen.main.scale, 3)
        guard let ui = renderer.uiImage, let data = ui.jpegData(compressionQuality: 0.95) else { return }
        let subName = subordinate.name.isEmpty ? "部屬" : subordinate.name
        let name = "部屬卡片_\(subName)_\(Self.stampFmt.string(from: Date())).jpg"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            shareItem = CardSharePayload(items: [url])
        } catch { }
    }

    /// 供 ImageRenderer 使用的靜態版面：英雄卡 + 目前分頁的全部章節（不含進場動畫修飾）。
    @ViewBuilder
    private func exportContent(mentioned: [SubordinateItemRef]) -> some View {
        VStack(spacing: 16) {
            headerCard(mentionedCount: mentioned.count)
            switch detailTab {
            case .daily:
                weeklyReportSection
                meetingSection
                taskSection
                mentionedSection(mentioned)
                recordSection(.leave)
                completedSection
            case .rating:
                promotionSection
                proConSection
                recordSection(.achievement)
                recordSection(.improvement)
                recordSection(.fault)
                recordSection(.missOperation)
            case .duty:
                SubordinateEquipmentSection(subordinateId: subordinateId)
                SubordinateEquipmentTimelineSection(subordinateId: subordinateId)
            }
        }
    }

    /// 把部屬卡片（基本資料＋分數＋目前分頁內容）組成 Emoji 排版純文字並開啟系統分享面板。
    private func exportText(mentioned: [SubordinateItemRef]) {
        let divider = "━━━━━━━━━━━━━━"
        let sub = subordinate
        var lines: [String] = []
        lines.append("👤 部屬卡片｜\(sub.name.isEmpty ? "未命名" : sub.name)")
        lines.append(divider)
        if !gradeTitleText.isEmpty { lines.append("💼 職稱：\(gradeTitleText)") }
        if !departmentText.isEmpty { lines.append("🏢 部門：\(departmentText)") }
        if !sub.plantArea.isEmpty { lines.append("🏭 廠區：\(sub.plantArea)") }
        if let jd = sub.joinDate { lines.append("📅 入職：\(formatDate(jd))") }
        let srDone = sideRoleStat.done
        lines.append("📊 主動性 \(sub.proactivityScore(mentionedCount: mentioned.count, sideRoleDone: srDone))｜潛力性 \(sub.potentialScore)｜綜合 \(sub.overallScore(mentionedCount: mentioned.count, sideRoleDone: srDone))")

        switch detailTab {
        case .daily:
            // 含已完成事項一併匯出：✅/⬜️ 並列，完成者附完成時間
            let reports = sub.weeklyReports
            if !reports.isEmpty {
                let done = reports.filter(\.isCompleted).count
                lines.append(""); lines.append("📄 報告（\(done)/\(reports.count) 完成）")
                for r in reports.sorted(by: { $0.date > $1.date }) {
                    var row = "\(r.isCompleted ? "✅" : "⬜️") \(r.topic.isEmpty ? "未命名報告" : r.topic)｜\(formatDate(r.date))"
                    if r.isCompleted, let at = r.completedAt { row += "｜🏁 \(formatDate(at))" }
                    lines.append(row)
                }
            }
            if !sub.meetings.isEmpty {
                lines.append(""); lines.append("👥 會議")
                for m in sub.meetings.sorted(by: { $0.date > $1.date }) {
                    let done = m.allItems.filter(\.isCompleted).count
                    lines.append("• \(m.topic.isEmpty ? "未命名會議" : m.topic)｜\(formatDateTime(m.date))\(m.allItems.isEmpty ? "" : "｜議程 \(done)/\(m.allItems.count)")")
                    for item in m.allItems {
                        var row = "　\(item.isCompleted ? "✅" : "⬜️") \(item.content.isEmpty ? "未填內容" : item.content)"
                        if item.isCompleted, let at = item.completedAt { row += "｜🏁 \(formatDate(at))" }
                        else if let due = item.dueDate { row += "｜⏰ \(formatDate(due))" }
                        lines.append(row)
                    }
                }
            }
            let tasks = sub.tasks
            if !tasks.isEmpty {
                let done = tasks.filter(\.isCompleted).count
                lines.append(""); lines.append("📋 任務（\(done)/\(tasks.count) 完成）")
                for t in tasks.sorted(by: { $0.date > $1.date }) {
                    var row = "\(t.isCompleted ? "✅" : "⬜️") \(t.topic.isEmpty ? "未命名任務" : t.topic)"
                    if t.isCompleted, let at = t.completedAt { row += "｜🏁 \(formatDate(at))" }
                    else if let due = t.dueDate { row += "｜⏰ 截止 \(formatDate(due))" }
                    lines.append(row)
                }
            }
            let leaves = sub.records.filter { $0.type == .leave }
            if !leaves.isEmpty {
                lines.append(""); lines.append("🌴 請假記錄（\(leaves.count)）")
                for rec in leaves.sorted(by: { $0.date > $1.date }).prefix(10) {
                    var row = "• \(formatDate(rec.date))"
                    if let lt = rec.leaveType { row += "｜\(lt.rawValue)" }
                    if let h = rec.leaveHours, h > 0 { row += "｜\(String(format: "%g", h)) 小時" }
                    lines.append(row)
                }
            }
        case .rating:
            let groups: [(SubordinateRecordType, String)] = [
                (.pro, "👍 優點"), (.con, "👎 缺點"),
                (.achievement, "🏆 成就"), (.improvement, "📈 進步"),
                (.fault, "⚠️ 缺失"), (.missOperation, "❌ Miss Operation")
            ]
            for (type, title) in groups {
                let recs = sub.records.filter { $0.type == type }
                if !recs.isEmpty {
                    lines.append(""); lines.append("\(title)（\(recs.count)）")
                    for rec in recs.sorted(by: { $0.date > $1.date }) {
                        lines.append("• \(rec.content.isEmpty ? "未填內容" : rec.content)｜\(formatDate(rec.date))")
                    }
                }
            }
        case .duty:
            if !sub.equipments.isEmpty {
                lines.append(""); lines.append("🛠 執掌設備（\(sub.equipments.count) 台）")
                for eq in sub.equipments {
                    var row = "• \(eq.name.isEmpty ? "未命名設備" : eq.name)｜🔧 PM \(eq.pmRecords.count)｜🚨 警報 \(eq.alarms.count)"
                    if let last = eq.pmRecords.map(\.date).max() { row += "｜上次 PM \(formatDate(last))" }
                    lines.append(row)
                }
                // 時間軸（新到舊）：PM 與警報合併，警報標示距同設備上次 PM 天數
                struct Entry { let date: Date; let text: String }
                var entries: [Entry] = []
                for eq in sub.equipments {
                    let name = eq.name.isEmpty ? "未命名設備" : eq.name
                    let pmDates = eq.pmRecords.map(\.date).sorted()
                    for pm in eq.pmRecords {
                        entries.append(Entry(date: pm.date,
                                             text: "🔧 \(formatDate(pm.date))｜\(name)｜PM 保養\(pm.note.isEmpty ? "" : "｜\(pm.note)")"))
                    }
                    for al in eq.alarms {
                        let prior = pmDates.last(where: { $0 <= al.date })
                        let daysText = prior.flatMap {
                            Calendar.current.dateComponents([.day], from: $0, to: al.date).day
                        }.map { "｜PM 後 \($0) 天" } ?? ""
                        entries.append(Entry(date: al.date,
                                             text: "🚨 \(formatDateTime(al.date))｜\(name)｜\(al.content.isEmpty ? "警報" : al.content)\(daysText)"))
                    }
                }
                if !entries.isEmpty {
                    lines.append(""); lines.append("⏱ PM／警報時間軸")
                    for e in entries.sorted(by: { $0.date > $1.date }) {
                        lines.append(e.text)
                    }
                }
            }
        }
        shareItem = CardSharePayload(items: [lines.joined(separator: "\n")])
    }

    private func colorFor(_ type: SubordinateRecordType) -> Color {
        switch type {
        case .pro: return .green; case .con: return .red
        case .achievement: return .orange; case .improvement: return .blue
        case .fault: return .pink; case .missOperation: return .purple
        case .leave: return .teal
        }
    }

    private func severityColor(_ s: MissOpSeverity) -> Color {
        switch s { case .minor: return .yellow; case .normal: return .orange; case .severe: return .red }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d HH:mm"; return f
    }()

    private func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private func formatDateTime(_ date: Date) -> String {
        Self.dateTimeFormatter.string(from: date)
    }
}

// MARK: - 記錄編輯 Sheet

// MARK: - 美化紀錄（RecordEditorSheet）
// [2026-07 v1] 首次美化方向：本檔案主畫面（SubordinateDetailView）已有 3 版美化紀錄，
// 但四個編輯 Sheet（RecordEditorSheet／MeetingEditorSheet／TaskEditorSheet／
// WeeklyReportEditorSheet）皆未涵蓋，與主畫面漸層 icon 圓 / Capsule 徽章規格脫節。
// 本次先補齊最小的 RecordEditorSheet：
//   1. 新增 editorSectionHeader(_:icon:tint:) 統一 Section 標題（4pt 漸層色條 + 圖示 +
//      .subheadline.bold），對齊 AddVehicleView／AddStockView／RenovationPhotoEditor.
//      renoSectionHeader 規格，取代原本純文字 Section("...") 標題；色條沿用 accent
//      （對齊該記錄類型於列表 recordRow 使用的 colorFor 主題色，維持列表→編輯頁色彩延續）。
//   2. 「扣除休息」／「請假時數」原為純文字 HStack，改為彩色 Capsule 徽章（底色 12% +
//      細邊框）+ contentTransition(.numericText())，對齊 App 全域數值徽章規格；
//      並包在 leaveInfoAppeared spring 進場動畫內，對齊 AddVehicleView.calcSectionAppeared
//      「計算衍生值區塊」進場規格。
//   3. 嚴重度 Picker 下方補一列彩色圓點 + 文字即時預覽（沿用 severityColor 對照：
//      輕微黃／一般橘／嚴重紅，與 recordRow 嚴重度 Capsule 用色一致）。
//   4. 純視覺層調整，未動請假時數計算（computedLeaveHours／restDeductionHours）、
//      儲存／刪除邏輯或任何欄位驗證規則。
// （後續已於 [2026-07 v2]（見下方 MeetingEditorSheet 前的紀錄）補齊 MeetingEditorSheet／
//   TaskEditorSheet／WeeklyReportEditorSheet 三個編輯 Sheet 的統一 Section header 規格）

struct RecordEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let subordinateId: UUID
    let type: SubordinateRecordType
    var editing: SubordinateRecord?
    var initialDate: Date? = nil   // 新請假時的預設日期（例如從班表格子帶入）

    @State private var content = ""
    @State private var date = Date()
    @State private var endDate = Date()
    @State private var note = ""
    @State private var severity: MissOpSeverity = .normal
    @State private var leaveType: LeaveType = .personal
    @State private var leaveInfoAppeared = false
    @State private var isSaving = false

    /// 對齊主畫面 colorFor(_:) 主題色，讓編輯頁 Section 色條與列表列行同色系。
    private var accent: Color {
        switch type {
        case .pro: return .green; case .con: return .red
        case .achievement: return .orange; case .improvement: return .blue
        case .fault: return .pink; case .missOperation: return .purple
        case .leave: return .teal
        }
    }

    private func severityColor(_ s: MissOpSeverity) -> Color {
        switch s { case .minor: return .yellow; case .normal: return .orange; case .severe: return .red }
    }

    private var canSave: Bool {
        !content.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 請假時數 = 逐日「請假區間 ∩ 當日班別上班時段」加總 − 休息時段重疊。
    /// 多日請假不再把下班時間與休假日灌進時數（先前用「總經過時間 − 休息」計算，
    /// 跨多日時會連下班與週末都算進去，主動性扣分失真）。
    private var computedLeaveHours: Double {
        max(0, workOverlapHours - restDeductionHours)
    }

    /// 當日的有效班別：有排班用排班（休息／時差假等無上班時間者回 nil）；
    /// 未排班時，平日視為日值班（未使用班表功能時的合理預設）、週末視為休假不計。
    private func effectiveShiftType(on day: Date, sub: Subordinate, cal: Calendar) -> ShiftType? {
        if let assigned = sub.shifts.first(where: { cal.isDate($0.date, inSameDayAs: day) })?.type {
            return assigned.hasWorkTime ? assigned : nil
        }
        let wd = cal.component(.weekday, from: day)
        return (wd == 1 || wd == 7) ? nil : .dayDuty
    }

    /// 逐日計算請假區間與「當日班別上班時段」的重疊時數（跨夜班別自動延伸到隔日）。
    private var workOverlapHours: Double {
        guard type == .leave, endDate > date,
              let sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { return 0 }
        let cal = Calendar.current
        let schedule = ShiftScheduleStore.shared.schedule
        var total = 0.0
        var day = cal.startOfDay(for: date)
        // endDate 的 FiveMinuteDateTimePicker 未設 maximumDate，使用者可拖到遠未來日期；
        // 逐日迴圈若不設上限，會在 Form body 重新求值（每次拖動選擇器）時同步跑天文數字次數，
        // 造成主執行緒卡死。夾在「請假開始日 + 366 天」內，與 SubordinateRosterView.buildLeaveLookup
        // 遠未來日期防護同一套思路。
        let cappedEnd = cal.date(byAdding: .day, value: 366, to: day) ?? cal.startOfDay(for: endDate)
        let last = min(cal.startOfDay(for: endDate), cappedEnd)
        while day <= last {
            if let shiftType = effectiveShiftType(on: day, sub: sub, cal: cal) {
                let wd = cal.component(.weekday, from: day)
                let isHoliday = (wd == 1 || wd == 7)
                if let r = schedule.range(for: shiftType, isHoliday: isHoliday),
                   let wStart = cal.date(byAdding: .minute, value: r.startMinutes, to: day),
                   // 跨夜班別（如小夜 16:00–00:00、假日大夜 20:30–08:30）endMinutes ≤ startMinutes，
                   // 換算成同日 Date 會比 wStart 早，多加 1440 分鐘（+1 天）延伸到隔日
                   let wEnd = cal.date(byAdding: .minute,
                                       value: r.endMinutes + (r.endMinutes <= r.startMinutes ? 1440 : 0),
                                       to: day), wEnd > wStart {
                    let s = max(date, wStart), e = min(endDate, wEnd)
                    if e > s { total += e.timeIntervalSince(s) / 3600 }
                }
            }
            guard let n = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = n
        }
        return total
    }

    /// 依當日班別的休息時段，計算需扣除的休息時數（跨日則逐日累加）。
    /// 班別解析與 workOverlapHours 同一套 effectiveShiftType，兩邊日曆口徑一致。
    private var restDeductionHours: Double {
        guard type == .leave, endDate > date,
              let sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { return 0 }
        let cal = Calendar.current
        let schedule = ShiftScheduleStore.shared.schedule
        var total = 0.0
        var day = cal.startOfDay(for: date)
        // 同 workOverlapHours：夾住遠未來 endDate，避免逐日迴圈跑出天文數字次數。
        let cappedEnd = cal.date(byAdding: .day, value: 366, to: day) ?? cal.startOfDay(for: endDate)
        let last = min(cal.startOfDay(for: endDate), cappedEnd)
        while day <= last {
            if let shift = effectiveShiftType(on: day, sub: sub, cal: cal),
               let rest = schedule.restRange(for: shift),
               let rStart = cal.date(byAdding: .minute, value: rest.startMinutes, to: day),
               // 休息時段可能跨午夜（如晚班 23:00–00:30，startMinutes > endMinutes，見
               // ShiftTimeRange／eveningShift 預設班別本身就跨日）。此時 endMinutes 換算成
               // 同一天的 Date 會比 rStart 還早，導致 rEnd > rStart 這個判斷失敗，整天的
               // 休息時段扣除被直接跳過（而非部分扣除），造成請假時數被高估。跨日時把
               // endMinutes 多加 1440 分鐘（+1 天）換算，其餘 clamp 邏輯不變。
               let rEnd = cal.date(byAdding: .minute,
                                    value: rest.endMinutes + (rest.endMinutes < rest.startMinutes ? 1440 : 0),
                                    to: day), rEnd > rStart {
                let s = max(date, rStart), e = min(endDate, rEnd)
                if e > s { total += e.timeIntervalSince(s) / 3600 }
            }
            guard let n = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = n
        }
        return total
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholder, text: $content, axis: .vertical).lineLimit(2...5)
                } header: {
                    editorSectionHeader("內容", icon: "text.alignleft")
                }
                if type == .leave {
                    Section {
                        Picker("假別", selection: $leaveType) {
                            ForEach(LeaveType.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } header: {
                        editorSectionHeader("請假資訊", icon: "calendar.badge.clock")
                    } footer: {
                        if leaveType.isScoreExempt {
                            Label("此假別（喪假／公假）不列入主動性扣分", systemImage: "checkmark.shield")
                                .foregroundStyle(.teal)
                        }
                    }
                    // restDeductionHours 會逐日走訪 date...endDate 並對 sub.shifts 做線性掃描，
                    // FiveMinuteDateTimePicker 拖曳/捲動時每一格都觸發 Form body 重新求值。
                    // 先前把這兩行搬進下方 Section 的內容 closure 裡「只算一次」，但下面
                    // .animation(value:) 是掛在 Section 之外的修飾詞鏈上，看不到 Section
                    // closure 內的區域變數，只能改呼叫 computedLeaveHours（內部又重呼叫一次
                    // restDeductionHours），等於一次 render 其實還是重算 2 次。搬到 Section
                    // 外層、與 .animation 同一層級，兩處都能直接讀同一份已算好的值。
                    let deduction = restDeductionHours
                    let leaveHours = max(0, workOverlapHours - deduction)
                    Section {
                        HStack {
                            Text("開始時間")
                            Spacer()
                            FiveMinuteDateTimePicker(selection: $date).fixedSize()
                        }
                        HStack {
                            Text("結束時間")
                            Spacer()
                            FiveMinuteDateTimePicker(selection: $endDate, minimumDate: date,
                                                      maximumDate: Calendar.current.date(byAdding: .day, value: 366, to: date)).fixedSize()
                        }
                        if deduction > 0 {
                            HStack {
                                Text("扣除休息").foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "−%.1f 小時", deduction))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.12))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.orange.opacity(0.25), lineWidth: 0.6))
                                    .contentTransition(.numericText())
                            }
                        }
                        HStack {
                            Text("請假時數").foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f 小時", leaveHours))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.teal)
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(Color.teal.opacity(0.12))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.teal.opacity(0.25), lineWidth: 0.6))
                                .contentTransition(.numericText())
                        }
                    } header: {
                        editorSectionHeader("日期", icon: "calendar")
                    } footer: {
                        Text("僅計入上班時段：有排班依班表計，未排班的平日以日值班計，週末與休假日不計入時數。")
                    }
                    .opacity(leaveInfoAppeared ? 1 : 0)
                    .offset(y: leaveInfoAppeared ? 0 : 10)
                    .animation(.easeInOut(duration: 0.2), value: leaveHours)
                } else {
                    Section {
                        DatePicker("發生日期", selection: $date, displayedComponents: .date)
                    } header: {
                        editorSectionHeader("日期", icon: "calendar")
                    }
                }
                if type == .missOperation {
                    Section {
                        Picker("嚴重度", selection: $severity) {
                            ForEach(MissOpSeverity.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        HStack(spacing: 6) {
                            Circle().fill(severityColor(severity)).frame(width: 8, height: 8)
                            Text("目前嚴重度：\(severity.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                    } header: {
                        editorSectionHeader("嚴重度", icon: "exclamationmark.triangle.fill")
                    }
                }
                Section {
                    MentionTextField(text: $note, placeholder: "選填（可打 @ 標註人員）", people: lifeStore.mentionPeople())
                } header: {
                    editorSectionHeader("備註", icon: "note.text", tint: Color(.systemGray2))
                }
                if editing != nil {
                    Section {
                        Button(role: .destructive) { deleteRecord() } label: { Label("刪除此記錄", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯\(type.rawValue)" : "新增\(type.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    // [美化 v25.99] 存檔中顯示同色 ProgressView，對齊 GradeTitleView v25.95／
                    // SubordinateView v25.94 等 isSaving 忙碌守衛按鈕載入狀態規格。
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView().scaleEffect(0.7).tint(.green)
                        }
                        Button(editing != nil ? "儲存" : "新增") { save() }.bold().foregroundStyle(.green).disabled(!canSave || isSaving)
                    }
                }
            }
            .onAppear {
                loadEditing()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.05)) {
                    leaveInfoAppeared = true
                }
            }
        }
    }

    /// 統一 Section 標題：4pt 漸層色條 + 圖示 + 粗體文字，對齊 AddVehicleView／AddStockView／
    /// RenovationPhotoEditor.renoSectionHeader 規格。tint 預設沿用 accent（依記錄類型主題色）。
    private func editorSectionHeader(_ title: String, icon: String, tint: Color? = nil) -> some View {
        let color = tint ?? accent
        return HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.bold))
        }
    }

    private var placeholder: String {
        switch type {
        case .pro: return "描述優點（如：溝通能力強）"
        case .con: return "描述缺點（如：會議發言較少）"
        case .achievement: return "描述成就（如：完成 Q3 專案）"
        case .improvement: return "描述改善（如：文件撰寫變得清晰）"
        case .fault: return "描述缺失（如：忘記交付報告）"
        case .missOperation: return "描述事件（如：誤刪正式資料）"
        case .leave: return "請假事由（如：身體不適）"
        }
    }

    private func loadEditing() {
        guard let e = editing else {
            // 新請假：預設用點選的格子日期（無則今日），時間預設 08:30–17:30
            if type == .leave {
                let cal = Calendar.current
                let base = initialDate ?? Date()
                date = cal.date(bySettingHour: 8, minute: 30, second: 0, of: base) ?? base
                endDate = cal.date(bySettingHour: 17, minute: 30, second: 0, of: base) ?? base
            }
            return
        }
        content = e.content; date = e.date; note = e.note
        endDate = e.endDate ?? Calendar.current.date(byAdding: .hour, value: 8, to: e.date) ?? e.date
        severity = e.severity ?? .normal
        leaveType = e.leaveType ?? .personal
    }

    private func save() {
        guard !isSaving else { return }
        guard var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
        isSaving = true
        let rec = SubordinateRecord(
            id: editing?.id ?? UUID(), type: type,
            content: content.trimmingCharacters(in: .whitespaces),
            date: date, endDate: type == .leave ? endDate : nil,
            note: note.trimmingCharacters(in: .whitespaces),
            severity: type == .missOperation ? severity : nil,
            leaveType: type == .leave ? leaveType : nil,
            leaveHours: type == .leave ? computedLeaveHours : nil
        )
        if let idx = sub.records.firstIndex(where: { $0.id == rec.id }) { sub.records[idx] = rec }
        else { sub.records.append(rec) }
        lifeStore.update(sub); dismiss()
    }

    private func deleteRecord() {
        guard !isSaving else { return }
        guard let e = editing, var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
        isSaving = true
        sub.records.removeAll { $0.id == e.id }
        lifeStore.update(sub); dismiss()
    }
}

// MARK: - 新增部屬項目（先選部屬，再開對應編輯器）

// MARK: - 美化紀錄（AddSubItemSheet）
// [2026-07 v1] 承接本檔案 MeetingEditorSheet／TaskEditorSheet／WeeklyReportEditorSheet
// v3 末尾待辦「本檔案其餘尚未套用漸層圖示圓規格的次要清單列」：
// 「選擇部屬」步驟的清單列先前是裸 26pt 單色圖示（固定寫死 .green，與 kind 無關），
// 是本檔案唯一未套用 36pt LinearGradient 漸層圖示圓（fill 0.22→0.09 + shadow + stroke
// 0.22 lineWidth 1.0）規格的清單列，與 recordRow／meetingSection 等既有列不一致。
// SubAddKind 新增 color 計算屬性（任務＝cyan／會議＝indigo／報告＝purple，沿用本檔案
// CompletedEntry.Kind.color 已建立的識別色慣例），清單列圖示改用該色套上標準漸層圓，
// 選到哪種項目就呈現對應色，與選完後開啟的編輯器 Section 識別色一致。
// 純視覺層調整，未變動 pickedSubId 選取、切換至對應 EditorSheet 等既有商業邏輯。
// [2026-07 v2] 承接 v1 末尾待辦：AddSubItemSheet 空狀態原本是系統原生 ContentUnavailableView
// （純圖示 + 文字，無動畫），與本檔案／SubordinateEquipmentView／SubordinateRosterView
// 等既有頁面級空狀態已升級的雙圈脈衝光環（double-pulse ring）規格不一致，是「選擇部屬」
// 這個入口畫面唯一還沒補上動態回饋的角落。改為 emptyState：62pt 雙圈 stroke 光環（外圈
// 1.35→1.62 縮放呼吸 + 內圈延遲 0.3s 錯開）+ 漸層底圓 + 細邊框，圖示與描述文字沿用原
// ContentUnavailableView 的 "person.2.slash" / 引導文案；主題色改用 kind.color（任務＝
// cyan／會議＝indigo／報告＝purple，對齊清單列已套用的識別色慣例），取代原本與 kind
// 無關的系統預設灰。動畫改用可取消的 Task 排程（onAppear 先取消前一個再排新的、
// onDisappear 一併取消歸零），對齊 SubordinateEquipmentView.emptyState 既有寫法，避免
// sheet 快速開關造成動畫殘留閃爍。純視覺層調整，pickedSubId 選取、切換至對應
// EditorSheet 等既有商業邏輯完全未變動。
// （下次美化本檔案時，可留意其餘子頁面是否仍有零星未套用漸層圖示圓／統一 Section 標頭
//   規格的角落）

// MARK: - 美化紀錄（SubordinateItemCard）
// [2026-08 v1] 本檔案最後一處從未美化過的畫面：部屬事項預覽卡（點任務/會議/報告/請假/
//   通用記錄列後彈出的唯讀卡片），titleBlock 圖示圓、field/richBlock 內容區塊皆是本檔案
//   碩果僅存的裸元件（無邊框/陰影/進場動畫），與同檔案其餘章節早已統一的視覺語言脫節：
//   1. titleBlock 44pt 圖示圓：補 Circle().stroke(color.opacity(0.22), lineWidth: 0.75) +
//      .shadow(color: color.opacity(0.18), radius: 5, y: 2)，對齊本檔案 meetingSection 等
//      章節、以及全 App StockDetailView／VehicleView／IncomeView 既有 44pt 圖示圓描邊＋陰影規格。
//   2. titleBlock 標題大字：補 .lineLimit(2) + .minimumScaleFactor(0.7)，任務/會議主題字數
//      不定，避免大字級輔助模式下超長標題被裁切或無限撐高版面。
//   3. field() / richBlock() 內容區塊：補 overlay(RoundedRectangle stroke separator.opacity(0.12))
//      細邊框，對齊本檔案卡片型容器（recordRow／meetingSection 等）皆有的邊界描邊規格，
//      深色模式下不再與背景融為一片。
//   4. cardBody 整體：新增 cardAppeared 進場動畫旗標（opacity 0+offset 12 → 1/0，
//      spring 0.46/0.82），對齊本檔案其餘 sheet／卡片一致採用的淡入進場規格，
//      取代原本無任何動畫、內容瞬間跳出的呈現方式。
//   純視覺層調整，任務/會議/報告/請假/記錄資料讀取、分享（JPG／文字）、@ 標註開啟連結、
//   編輯導頁等既有商業邏輯完全未變動。
//   （下次美化本檔案時，可轉往其他仍留有待辦的畫面）

/// 可從行事曆 / 部屬總覽的「＋」新增的部屬項目類型
enum SubAddKind: String, Identifiable, CaseIterable {
    case task, meeting, report
    var id: String { rawValue }
    var title: String {
        switch self {
        case .task: return "部屬任務"
        case .meeting: return "部屬會議"
        case .report: return "部屬報告"
        }
    }
    var icon: String {
        switch self {
        case .task: return "checklist"
        case .meeting: return "person.3.fill"
        case .report: return "doc.text.fill"
        }
    }
    /// 對齊全檔案「任務＝cyan／會議＝indigo／報告＝purple」識別色慣例（見 CompletedEntry.Kind.color）
    var color: Color {
        switch self {
        case .task: return .cyan
        case .meeting: return .indigo
        case .report: return .purple
        }
    }
}

/// 兩步驟 Sheet：先選部屬（單一 sheet 內切換內容，避免多 sheet 競態），選完直接進對應編輯器
struct AddSubItemSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    let kind: SubAddKind
    @State private var pickedSubId: UUID?
    @State private var emptyIconPulse = false
    @State private var emptyPulseTask: Task<Void, Never>?

    var body: some View {
        if let subId = pickedSubId {
            switch kind {
            case .task:    TaskEditorSheet(subordinateId: subId, editing: nil)
            case .meeting: MeetingEditorSheet(subordinateId: subId, editing: nil)
            case .report:  WeeklyReportEditorSheet(subordinateId: subId, editing: nil)
            }
        } else {
            NavigationStack {
                Group {
                    if lifeStore.subordinates.isEmpty {
                        emptyState
                    } else {
                        List {
                            ForEach(lifeStore.subordinates.sorted { $0.name < $1.name }) { sub in
                                Button {
                                    pickedSubId = sub.id
                                } label: {
                                    HStack(spacing: 12) {
                                        // [v1] 36pt 漸層圖示圓 + 陰影 + 細邊框，對齊 recordRow／meetingSection
                                        // 等本檔案既有清單列規格，取代先前裸 26pt 單色圖示；
                                        // 色彩改用 kind.color（任務＝cyan／會議＝indigo／報告＝purple），
                                        // 與下方對應編輯器 Section 識別色一致，不再固定寫死 .green。
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [kind.color.opacity(0.22), kind.color.opacity(0.09)],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 36, height: 36)
                                                .shadow(color: kind.color.opacity(0.20), radius: 5, x: 0, y: 2)
                                            Circle()
                                                .stroke(kind.color.opacity(0.22), lineWidth: 1.0)
                                                .frame(width: 36, height: 36)
                                            Image(systemName: kind.icon)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(kind.color)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(sub.name.isEmpty ? "未命名" : sub.name)
                                                .foregroundStyle(.primary)
                                            let subtitle = [sub.department, sub.jobTitle]
                                                .filter { !$0.isEmpty }.joined(separator: " · ")
                                            if !subtitle.isEmpty {
                                                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("選擇部屬")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                }
            }
        }
    }

    // MARK: 空狀態（雙圈脈衝，對齊 SubordinateEquipmentView.emptyState 規格）

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(kind.color.opacity(emptyIconPulse ? 0 : 0.28), lineWidth: 1.5)
                    .frame(width: 62, height: 62)
                    .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                    .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false), value: emptyIconPulse)
                Circle()
                    .stroke(kind.color.opacity(emptyIconPulse ? 0 : 0.14), lineWidth: 1)
                    .frame(width: 62, height: 62)
                    .scaleEffect(emptyIconPulse ? 1.62 : 1.0)
                    .animation(.easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false), value: emptyIconPulse)
                Circle()
                    .fill(LinearGradient(colors: [kind.color.opacity(0.16), kind.color.opacity(0.06)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(kind.color.opacity(0.22), lineWidth: 1))
                Image(systemName: "person.2.slash")
                    .font(.system(size: 20, weight: .light)).foregroundStyle(kind.color.opacity(0.75))
            }
            .onAppear {
                emptyIconPulse = false
                emptyPulseTask?.cancel()
                emptyPulseTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    emptyIconPulse = true
                }
            }
            .onDisappear {
                emptyPulseTask?.cancel()
                emptyIconPulse = false
            }
            Text("尚無部屬").font(.caption).foregroundStyle(.secondary)
            Text("請先在『部屬』頁新增部屬，才能建立\(kind.title)")
                .font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - 會議編輯 Sheet

// MARK: - 美化紀錄（MeetingEditorSheet／TaskEditorSheet／WeeklyReportEditorSheet）
// [2026-07 v2] 承接 RecordEditorSheet 上一版美化紀錄（[2026-07 v1]）末尾提及的待辦項目：
// 本次為這三個編輯 Sheet 補齊與 RecordEditorSheet 相同的統一 Section 標題規格
// （4pt 漸層色條 + 圖示 + .subheadline.bold，取代純文字 Section(標題) 字串），
// 主題色沿用各自項目在主畫面列表列（meetingSection／taskSection／weeklyReportSection）
// 已使用的識別色：會議＝indigo、任務＝cyan、報告＝purple；備註區一律用中性灰
// （對齊 RecordEditorSheet 備註區 tint: Color(.systemGray2) 的既有規格）。
// 另外會議項目清單原本無空狀態提示，新增時畫面會顯得空白，補上一列輕量文字提示。
// 純視覺層調整，未變動任何儲存／刪除／指派/週期換算等既有商業邏輯。
// [2026-07 v3] 承接上一版（v2）末尾待辦：TaskEditorSheet／WeeklyReportEditorSheet
// 的「標記為已完成」Toggle Section 原本是全檔唯一沒有 header 的 Section，
// 補上 editorSectionHeader("完成狀態", icon: "checkmark.seal.fill", tint: .green)，
// 綠色呼應 Toggle 開啟時的勾選綠，與 isCompleted 狀態語意一致；純視覺層調整，
// $isCompleted binding／save() 寫回 completedAt 等既有商業邏輯完全未變動。
// （「本檔案其餘尚未套用漸層圖示圓規格的次要清單列」已於 AddSubItemSheet [2026-07 v1]
//   處理完成，下次美化本檔案時可轉往其他仍留有待辦的畫面）
// [2026-08 v25.99] 本次美化方向（RecordEditorSheet／MeetingEditorSheet／TaskEditorSheet／
// WeeklyReportEditorSheet 工具列儲存按鈕補齊載入狀態）：
//   • 這四個編輯 Sheet 的 save() 皆自帶 isSaving 忙碌守衛（disabled(isSaving)）避免快速連點
//     造成重複紀錄，但按鈕本身在存檔期間毫無視覺提示。比照 GradeTitleView v25.95／
//     SubordinateView v25.94 等全 App 儲存按鈕載入狀態規格，於按鈕左側補上
//     HStack { if isSaving { ProgressView().scaleEffect(0.7).tint(.green) }；Button(...) }。
//   • 純視覺層調整，四個 save()／deleteRecord()／deleteMeeting()／deleteTask()／
//     deleteReport() 內部守衛判斷與請假時數計算、任務換人指派等既有商業邏輯完全未變動。
//   • 全 App 同型待辦清單（v25.96 OrganizationView 紀錄）已剩 MyCalendarView／
//     LifeFinanceView／ResumeView／ChildDetailView，下次可依序比照補齊。

struct MeetingEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let subordinateId: UUID
    var editing: SubordinateMeeting?

    @State private var topic = ""
    @State private var createdAt = Date()
    @State private var date = Date()
    @State private var durationText = "60"
    @State private var hasRecurrence = false
    @State private var frequency: MeetingRecurrence = .weekly
    /// 1=週日 … 7=週六
    @State private var weekdays: Set<Int> = []
    @State private var hasRuleEnd = false
    @State private var ruleEndDate = Date()
    @State private var items: [MeetingItem] = []
    @State private var occurrences: [MeetingOccurrence] = []
    @State private var note = ""
    @State private var isSaving = false
    /// 正在編輯的場次（以原定日期為鍵）。用 .sheet(item:) 開——本檔案的 Sheet 一律走這個模式。
    @State private var editingOccurrence: DateBox?
    /// 正在新增的臨時場次（規則之外加開的一場），值是預設的開會時間
    @State private var creatingAdHoc: DateBox?
    /// 正在挑負責人的項目 id。狀態放這裡、.sheet 掛在 Form 根層——
    /// 掛在 Form 的 Section 上會讓外層編輯頁被一併收掉（見 MeetingItemsEditor 註解）。
    @State private var pickingAssigneeFor: IDBox?

    /// 負責人姓名快取：sideRolePersonCandidates() 每次呼叫都會重建三種來源、做去重與排序，
    /// 直接在每一列裡呼叫會讓打字時每個字元都重算一次全公司名單。
    /// 編輯頁開著的期間人員名單不會變，所以 onAppear 建一次就好。
    @State private var peopleIndex: [UUID: SideRolePersonCandidate] = [:]

    /// 統一 Section 標題：4pt 漸層色條 + 圖示 + 粗體文字，對齊 RecordEditorSheet.editorSectionHeader 規格。
    private func editorSectionHeader(_ title: String, icon: String, tint: Color = .indigo) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [tint, tint.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.subheadline.weight(.bold))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // 會議資訊＝這個 Task 本身（名稱／何時立的／備註），與「什麼時候開」分開。
                Section {
                    TextField("Task 名稱", text: $topic)
                    HStack {
                        Text("產生時間")
                        Spacer()
                        FiveMinuteDateTimePicker(selection: $createdAt).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("備註").font(.caption).foregroundStyle(.secondary)
                        MentionTextField(text: $note, placeholder: "選填（可打 @ 標註人員）",
                                         people: lifeStore.mentionPeople())
                    }
                } header: {
                    editorSectionHeader("會議資訊", icon: "person.badge.clock")
                }

                Section {
                    HStack {
                        Text("開始時間")
                        Spacer()
                        FiveMinuteDateTimePicker(selection: $date).fixedSize()
                    }
                    HStack {
                        TextField("會議長度", text: $durationText).keyboardType(.numberPad)
                        Text("分鐘").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("結束時間").foregroundStyle(.secondary)
                        Spacer()
                        Text(MeetingTimeFormat.rangeText(start: date, minutes: Int(durationText) ?? 60))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.indigo)
                    }
                    Toggle("設定週期", isOn: $hasRecurrence)
                    if hasRecurrence {
                        Picker("重複頻率", selection: $frequency) {
                            ForEach(MeetingRecurrence.allCases) { Text($0.rawValue).tag($0) }
                        }
                        if frequency == .weekly || frequency == .biweekly {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("星期幾（不選＝沿用開始日的星期）")
                                    .font(.caption).foregroundStyle(.secondary)
                                weekdayChips
                            }
                        }
                        Toggle("設定結束日期", isOn: $hasRuleEnd)
                        if hasRuleEnd {
                            DatePicker("重複到", selection: $ruleEndDate, displayedComponents: .date)
                        } else {
                            Text("未設結束日期時，下方只列出未來三個月的場次。")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    editorSectionHeader("會議時間", icon: "calendar.badge.clock")
                }

                if hasRecurrence {
                    occurrenceSection
                } else {
                    MeetingItemsEditor(items: $items, peopleIndex: peopleIndex,
                                       pickingAssigneeFor: $pickingAssigneeFor)
                    adHocSection
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) { deleteMeeting() } label: { Label("刪除會議", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯會議" : "新增會議")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    // [美化 v25.99] 存檔中顯示同色 ProgressView，對齊 RecordEditorSheet／
                    // GradeTitleView v25.95 等 isSaving 忙碌守衛按鈕載入狀態規格。
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView().scaleEffect(0.7).tint(.green)
                        }
                        Button(editing != nil ? "儲存" : "新增") { save() }
                            .bold().foregroundStyle(.green)
                            .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    }
                }
            }
            .sheet(item: $editingOccurrence) { box in
                MeetingOccurrenceEditor(scheduledDate: box.id,
                                        durationMinutes: Int(durationText) ?? 60,
                                        occurrence: occurrences.first { $0.scheduledDate == box.id },
                                        peopleIndex: peopleIndex,
                                        onSave: applyOccurrence)
            }
            .sheet(item: $creatingAdHoc) { box in
                MeetingOccurrenceEditor(scheduledDate: box.id,
                                        durationMinutes: Int(durationText) ?? 60,
                                        occurrence: nil,
                                        peopleIndex: peopleIndex,
                                        isAdHoc: true,
                                        onSave: applyOccurrence)
            }
            .sheet(item: $pickingAssigneeFor) { box in
                NavigationStack {
                    MeetingAssigneePicker(
                        initial: items.first { $0.id == box.id }?.assigneeIds ?? [],
                        onDone: { ids in
                            guard let idx = items.firstIndex(where: { $0.id == box.id }) else { return }
                            items[idx].assigneeIds = ids
                        }
                    )
                }
            }
            // 切換週期時就把議程項目搬到該去的地方：不重複的會議項目住在 items，
            // 有週期的會議住在各場次。等到存檔才搬的話，切換後畫面會先變成空的、
            // 存完又冒回來，使用者會以為資料掉了。
            .onChange(of: hasRecurrence) { _, on in
                if on {
                    guard !items.isEmpty else { return }
                    occurrences.append(MeetingOccurrence(scheduledDate: date, items: items))
                    items = []
                } else {
                    // 只把「規則生的」場次項目併回 items；臨時加開的場次保留原樣——
                    // 它們在沒有週期的模式下照樣存在（加開場次區），拆掉等於把
                    // 使用者親手加的那幾場砍成一團混在一起的項目清單。
                    items.append(contentsOf: occurrences.filter { !$0.isAdHoc }.flatMap(\.items))
                    occurrences.removeAll { !$0.isAdHoc }
                }
            }
            .onAppear {
                peopleIndex = Dictionary(lifeStore.sideRolePersonCandidates().map { ($0.id, $0) },
                                         uniquingKeysWith: { a, _ in a })
                if let e = editing {
                    topic = e.topic; date = e.date; createdAt = e.createdAt
                    durationText = "\(e.durationMinutes)"
                    if let r = e.rule {
                        hasRecurrence = true
                        frequency = r.frequency
                        weekdays = Set(r.weekdays)
                        if let end = r.endDate { hasRuleEnd = true; ruleEndDate = end }
                    }
                    items = e.items; note = e.note; occurrences = e.occurrences
                } else {
                    // 新會議：預設時間用排程時段（整點/半點，過 18:00 則隔天 09:30）
                    date = FiveMinuteDateTimePicker.defaultSchedulingTime()
                    createdAt = Date()
                    ruleEndDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
                }
            }
        }
    }

    // MARK: 週期規則

    private var currentRule: MeetingRecurrenceRule? {
        guard hasRecurrence else { return nil }
        return MeetingRecurrenceRule(frequency: frequency,
                                     weekdays: weekdays.sorted(),
                                     endDate: hasRuleEnd ? ruleEndDate : nil)
    }

    private static let weekdayLabels = ["日", "一", "二", "三", "四", "五", "六"]

    private var weekdayChips: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { wd in
                let on = weekdays.contains(wd)
                Button {
                    if on { weekdays.remove(wd) } else { weekdays.insert(wd) }
                } label: {
                    Text(Self.weekdayLabels[wd - 1])
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(on ? Color.indigo : Color(.tertiarySystemFill), in: Circle())
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 場次列表

    /// 用目前編輯中的內容組出一份暫時的會議，借它的展開邏輯算場次。
    /// 存檔前就要看得到場次，所以不能等寫進 store 才展開。
    private var draftMeeting: SubordinateMeeting {
        SubordinateMeeting(id: editing?.id ?? UUID(), topic: topic, date: date,
                           durationMinutes: Int(durationText) ?? 60,
                           rule: currentRule, items: items, note: note,
                           createdAt: createdAt, occurrences: occurrences)
    }

    /// 場次清單的顯示窗：只列「七天前」之後的場次，最多 40 筆。
    /// 一個開了兩年的每週會議展開後上百場，全列出來會把編輯頁淹掉。
    private var visibleOccurrences: [ResolvedMeetingOccurrence] {
        let cal = Calendar.current
        let horizon = cal.date(byAdding: .month, value: 3, to: Date()) ?? Date()
        let floor = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let all = draftMeeting.expandedOccurrences(from: floor, horizon: horizon)
        let kept = all.filter { $0.date >= floor || $0.isMaterialised }
        return Array(kept.prefix(40))
    }

    @ViewBuilder
    private var occurrenceSection: some View {
        let list = visibleOccurrences
        Section {
            if list.isEmpty {
                Text("目前的週期設定沒有產生任何場次。若有指定星期幾，請確認開始日期之後有符合的日子。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(list) { occ in
                Button { editingOccurrence = DateBox(id: occ.scheduledDate) } label: {
                    occurrenceRow(occ)
                }
                .buttonStyle(.plain)
            }
            Button {
                creatingAdHoc = DateBox(id: FiveMinuteDateTimePicker.defaultSchedulingTime())
            } label: {
                Label("新增臨時場次", systemImage: "calendar.badge.plus").foregroundStyle(.indigo)
            }
        } header: {
            editorSectionHeader("場次（\(list.count)）", icon: "calendar.day.timeline.left")
        } footer: {
            Text("每一場各有自己的議程項目。點一場可以編輯項目、改期或取消那一場，不影響其他場次。臨時場次是在週期之外加開的一場，日期時間自由指定。")
                .font(.caption2)
        }
    }

    private func occurrenceRow(_ occ: ResolvedMeetingOccurrence) -> some View {
        let done = occ.items.filter(\.isCompleted).count
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(MeetingTimeFormat.dateTime24.string(from: occ.date))
                        .font(.subheadline.weight(.medium))
                        .strikethrough(occ.isCancelled, color: .secondary)
                        .foregroundStyle(occ.isCancelled ? Color.secondary : Color.primary)
                    if occ.isCancelled { occurrenceBadge("已取消", .red) }
                    else if occ.isMoved { occurrenceBadge("已改期", .orange) }
                    if occ.isAdHoc { occurrenceBadge("臨時", .indigo) }
                }
                HStack(spacing: 8) {
                    if occ.isMoved {
                        Text("原定 \(MeetingTimeFormat.dateTime24.string(from: occ.scheduledDate))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if occ.items.isEmpty {
                        Text("尚無議程").font(.caption2).foregroundStyle(.tertiary)
                    } else {
                        Text("議程 \(done)/\(occ.items.count)")
                            .font(.caption2)
                            .foregroundStyle(done == occ.items.count ? Color.green : Color.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func occurrenceBadge(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }

    /// 沒開週期時的「加開場次」：不必先設週期也能加額外的會議時間，
    /// 每一場有自己的日期時間與議程項目（使用者需求 v25.237）。
    @ViewBuilder
    private var adHocSection: some View {
        let list = occurrences.filter(\.isAdHoc).sorted { $0.effectiveDate < $1.effectiveDate }
        Section {
            ForEach(list) { occ in
                Button { editingOccurrence = DateBox(id: occ.scheduledDate) } label: {
                    occurrenceRow(resolvedAdHoc(occ))
                }
                .buttonStyle(.plain)
            }
            Button {
                creatingAdHoc = DateBox(id: FiveMinuteDateTimePicker.defaultSchedulingTime())
            } label: {
                Label("加開一場", systemImage: "calendar.badge.plus").foregroundStyle(.indigo)
            }
        } header: {
            editorSectionHeader("加開場次" + (list.isEmpty ? "" : "（\(list.count)）"),
                                icon: "calendar.badge.plus")
        } footer: {
            Text("臨時需要多開一場時用這裡，不必設定週期。每一場有自己的時間與議程項目。")
                .font(.caption2)
        }
    }

    /// 把原始覆寫包成顯示用的展開結果（加開場次列共用 occurrenceRow 的外觀）
    private func resolvedAdHoc(_ o: MeetingOccurrence) -> ResolvedMeetingOccurrence {
        ResolvedMeetingOccurrence(scheduledDate: o.scheduledDate, date: o.effectiveDate,
                                  isCancelled: o.isCancelled, isMoved: o.movedTo != nil,
                                  items: o.items, isMaterialised: true, isAdHoc: o.isAdHoc)
    }

    /// 場次編輯完成後寫回。全部清空的場次直接回收，不留空殼在存檔裡。
    private func applyOccurrence(_ updated: MeetingOccurrence) {
        if let idx = occurrences.firstIndex(where: { $0.scheduledDate == updated.scheduledDate }) {
            if updated.isMeaningful { occurrences[idx] = updated }
            else { occurrences.remove(at: idx) }
        } else if updated.isMeaningful {
            occurrences.append(updated)
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
        isSaving = true
        // items ⇄ 場次的搬動已經在切換「設定週期」的當下就做掉了（見 onChange），
        // 這裡不再搬一次，否則會搬兩遍。
        var meeting = SubordinateMeeting(
            id: editing?.id ?? UUID(),
            topic: topic.trimmingCharacters(in: .whitespaces),
            date: date, durationMinutes: Int(durationText) ?? 60,
            rule: currentRule,
            items: items, note: note.trimmingCharacters(in: .whitespaces),
            createdAt: createdAt, occurrences: occurrences
        )
        meeting.pruneOccurrences()
        if let idx = sub.meetings.firstIndex(where: { $0.id == meeting.id }) { sub.meetings[idx] = meeting }
        else { sub.meetings.append(meeting) }
        lifeStore.update(sub); dismiss()
    }

    private func deleteMeeting() {
        guard !isSaving else { return }
        guard let e = editing, var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
        isSaving = true
        sub.meetings.removeAll { $0.id == e.id }
        lifeStore.update(sub); dismiss()
    }
}

// MARK: - 議程項目編輯（會議本身與各場次共用）

/// 以原定日期當 id 的 .sheet(item:) 包裝。UUID 不是 Identifiable，Date 也不是。
struct DateBox: Identifiable { let id: Date }

/// 議程項目清單的編輯區塊。抽成獨立的 View 有兩個理由：
///   1. 不重複會議（項目在 meeting.items）與週期會議的單一場次（項目在
///      occurrence.items）要用同一份 UI，否則兩邊會慢慢長歪。
///   2. 挑負責人的 sheet 狀態跟著清單走，放在外層會讓兩處各維護一份。
/// 「這筆同時是某個兼任職務的待辦」徽章。
/// 使用者看到它才會知道：這裡打勾兼任那邊也會完成，而且評分不會被算兩次。
struct SideRoleLinkBadge: View {
    let back: SideRoleBackLink
    @EnvironmentObject var lifeStore: LifeStore

    var body: some View {
        let name = lifeStore.milestones.first { $0.id == back.roleId }?
            .sideRoleName?.trimmingCharacters(in: .whitespaces) ?? ""
        HStack(spacing: 3) {
            Image(systemName: "link")
                .font(.system(size: 7))
            Text(name.isEmpty ? "兼任職務" : name)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.indigo.opacity(0.12))
        .foregroundStyle(.indigo)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.indigo.opacity(0.22), lineWidth: 0.6))
    }
}

/// ⚠️ 這是一個「整段 Section」的元件，要直接放在 Form 底下，不要再包一層 Section。
///    包在別人的 Section 裡的話，SwiftUI 會把它整組壓成單一列。
struct MeetingItemsEditor: View {
    @Binding var items: [MeetingItem]
    var title: String = "會議項目"
    var icon: String = "checklist"
    /// 由外層 onAppear 建好傳入：sideRolePersonCandidates() 每次呼叫都會重建
    /// 三種來源、去重與排序，放在每一列裡呼叫會讓打字時每個字元都重算全公司名單。
    let peopleIndex: [UUID: SideRolePersonCandidate]
    /// 挑負責人的彈頁狀態**由外層編輯頁持有**、.sheet 掛在編輯頁根層。
    /// ⚠️ 曾把 .sheet 掛在這個 Section 上（v25.229）：Form 的列由 UIKit 代管，
    /// 從列層級發起 sheet 會讓系統向上找錯簡報來源，彈出挑人頁的同時把
    /// 外層的會議編輯頁一併收掉——使用者按「指派負責人」就被踢出編輯、改到一半全丟。
    @Binding var pickingAssigneeFor: IDBox?

    @EnvironmentObject var lifeStore: LifeStore

    var body: some View {
        Section {
            if items.isEmpty {
                HStack {
                    Spacer()
                    Text("尚未新增項目").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            ForEach($items) { $item in
                itemEditor($item)
            }
            Button { items.append(MeetingItem()) } label: {
                Label("新增項目", systemImage: "plus.circle").foregroundStyle(.indigo)
            }
        } header: {
            // 對齊 MeetingEditorSheet.editorSectionHeader 規格（4pt 漸層色條 + 圖示 + 粗體）
            HStack(spacing: 8) {
                Capsule()
                    .fill(LinearGradient(colors: [.indigo, .indigo.opacity(0.55)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 16)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.indigo)
                Text(title).font(.subheadline.weight(.bold))
            }
        }
    }

    /// 單一議程項目。刻意抽成函式：本檔案曾因 ForEach 內大量巢狀 Binding
    /// 轉換撞上 Swift 型別推導逾時。
    @ViewBuilder
    private func itemEditor(_ item: Binding<MeetingItem>) -> some View {
        let value = item.wrappedValue
        VStack(alignment: .leading, spacing: 8) {
            if items.first?.id != value.id { Divider() }
            HStack {
                TextField("項目名稱", text: item.content)
                Button(role: .destructive) { items.removeAll { $0.id == value.id } } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            // 負責人（多選）：部屬／名片／組織人員三種來源都可挑，可搜尋。
            Button { pickingAssigneeFor = IDBox(id: value.id) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 12)).foregroundStyle(.indigo)
                    Text(value.assigneeIds.isEmpty ? "指派負責人" : "負責人（\(value.assigneeIds.count)）")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            if !value.assigneeIds.isEmpty {
                FlexibleChipWrap(items: value.assigneeIds) { pid in
                    assigneeChip(pid, itemId: value.id)
                }
            }

            Toggle("設定截止時間", isOn: Binding(
                get: { value.dueDate != nil },
                set: { item.wrappedValue.dueDate = $0 ? (value.dueDate ?? FiveMinuteDateTimePicker.defaultSchedulingTime()) : nil }
            ))
            if value.dueDate != nil {
                DatePicker("截止", selection: Binding(
                    get: { item.wrappedValue.dueDate ?? Date() },
                    set: { item.wrappedValue.dueDate = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
            }
            Toggle(isOn: Binding(
                get: { item.wrappedValue.isCompleted },
                set: { newVal in
                    item.wrappedValue.isCompleted = newVal
                    item.wrappedValue.completedAt = newVal ? (value.completedAt ?? Date()) : nil
                }
            )) {
                Label(value.isCompleted ? "已完成" : "未完成",
                      systemImage: value.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(value.isCompleted ? Color.green : Color.secondary)
            }
            MentionTextField(text: item.note, placeholder: "項目備註（可打 @ 標註人員）",
                             people: lifeStore.mentionPeople())
        }
    }

    /// 已選負責人膠囊。點一下即移除——挑錯人時不必再開一次挑人頁。
    private func assigneeChip(_ pid: UUID, itemId: UUID) -> some View {
        let person = peopleIndex[pid]
        return Button {
            guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
            items[idx].assigneeIds.removeAll { $0 == pid }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: person?.kind.icon ?? "person.crop.circle.badge.questionmark")
                    .font(.system(size: 10))
                Text(person?.name ?? "已移除的人員")
                    .font(.caption)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.indigo.opacity(person == nil ? 0.05 : 0.12), in: Capsule())
            .foregroundStyle(person == nil ? Color.secondary : Color.indigo)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 單一場次編輯

/// 週期會議中「某一場」的編輯頁：這一場自己的議程項目、改期、取消。
/// 改動只回寫給呼叫端（編輯頁的暫存陣列），按會議的「儲存」才真的落地，
/// 所以在會議編輯頁按「取消」時，場次的改動也會一起被丟掉。
struct MeetingOccurrenceEditor: View {
    let scheduledDate: Date
    let durationMinutes: Int
    /// 既有的覆寫；nil 表示這一場使用者還沒動過
    let occurrence: MeetingOccurrence?
    let peopleIndex: [UUID: SideRolePersonCandidate]
    /// 新增臨時場次模式：日期直接可編（沒有「原定／改期」的概念，這一場就不是規則生的）
    var isAdHoc: Bool = false
    let onSave: (MeetingOccurrence) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var items: [MeetingItem] = []
    @State private var isCancelled = false
    @State private var isMoved = false
    @State private var movedTo = Date()
    @State private var adHocDate = Date()
    @State private var loaded = false
    /// 挑負責人的彈頁：狀態在這裡、.sheet 掛在 Form 根層（掛在 Section 上
    /// 會把本編輯頁一併收掉，見 MeetingItemsEditor 註解）
    @State private var pickingAssigneeFor: IDBox?

    /// 這一場實際開會時間（時間列與存檔共用）
    private var effectiveStart: Date {
        if isAdHoc { return adHocDate }
        return isMoved ? movedTo : scheduledDate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isAdHoc {
                        HStack {
                            Text("日期時間")
                            Spacer()
                            FiveMinuteDateTimePicker(selection: $adHocDate).fixedSize()
                        }
                    } else {
                        HStack {
                            Text("原定")
                            Spacer()
                            Text(MeetingTimeFormat.dateTime24.string(from: scheduledDate))
                                .foregroundStyle(.secondary)
                        }
                        Toggle("改期", isOn: $isMoved)
                        if isMoved {
                            HStack {
                                Text("改到")
                                Spacer()
                                FiveMinuteDateTimePicker(selection: $movedTo).fixedSize()
                            }
                        }
                    }
                    HStack {
                        Text("時間").foregroundStyle(.secondary)
                        Spacer()
                        Text(MeetingTimeFormat.rangeText(start: effectiveStart,
                                                         minutes: durationMinutes))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.indigo)
                    }
                    if !isAdHoc {
                        Toggle(isOn: $isCancelled) {
                            Label("取消這一場", systemImage: "calendar.badge.minus")
                                .foregroundStyle(isCancelled ? Color.red : Color.primary)
                        }
                    }
                } header: {
                    Text("這一場")
                } footer: {
                    Text(isAdHoc
                         ? "臨時場次是在週期之外加開的一場，不影響原本的週期。"
                         : "取消或改期只影響這一場，週期本身不變。")
                }

                MeetingItemsEditor(items: $items, title: "這一場的議程項目",
                                   peopleIndex: peopleIndex,
                                   pickingAssigneeFor: $pickingAssigneeFor)

                if occurrence?.isAdHoc == true {
                    Section {
                        Button(role: .destructive) {
                            // 交回一個「什麼狀態都沒有」的場次：applyOccurrence 對
                            // isMeaningful == false 的覆寫是直接回收，等同刪除這一場。
                            // 規則生的場次沒有這顆按鈕——它們用「取消」，刪了下次還是會長回來。
                            onSave(MeetingOccurrence(id: occurrence?.id ?? UUID(),
                                                     scheduledDate: scheduledDate))
                            dismiss()
                        } label: {
                            Label("刪除這一場臨時場次", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isAdHoc ? "臨時場次" : "場次")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isAdHoc ? "新增" : "完成") { commit() }.bold().foregroundStyle(.green)
                }
            }
            .sheet(item: $pickingAssigneeFor) { box in
                NavigationStack {
                    MeetingAssigneePicker(
                        initial: items.first { $0.id == box.id }?.assigneeIds ?? [],
                        onDone: { ids in
                            guard let idx = items.firstIndex(where: { $0.id == box.id }) else { return }
                            items[idx].assigneeIds = ids
                        }
                    )
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                items = occurrence?.items ?? []
                isCancelled = occurrence?.isCancelled ?? false
                if let m = occurrence?.movedTo { isMoved = true; movedTo = m }
                else { movedTo = scheduledDate }
                adHocDate = scheduledDate
            }
        }
    }

    private func commit() {
        // 臨時場次的 scheduledDate 就是使用者挑的日期；事後編輯（isAdHoc 已存在
        // occurrence 上）要保留旗標，否則議程清空的那一刻它會被回收、從清單上消失。
        onSave(MeetingOccurrence(id: occurrence?.id ?? UUID(),
                                 scheduledDate: isAdHoc ? adHocDate : scheduledDate,
                                 movedTo: isMoved ? movedTo : nil,
                                 isCancelled: isCancelled,
                                 items: items,
                                 isAdHoc: isAdHoc || (occurrence?.isAdHoc ?? false)))
        dismiss()
    }
}

// MARK: - 議程項目負責人挑選（部屬／名片／組織人員）

/// 議程項目的負責人挑選頁。與兼任職務的出席者挑選共用同一份候選清單
/// （sideRolePersonCandidates()，已處理「同一位部屬同時出現在名片列」的去重），
/// 但這裡存的是 **id 而非姓名**——負責人要能連回本人的紀錄，姓名快照做不到。
struct MeetingAssigneePicker: View {
    let initial: [UUID]
    let onDone: ([UUID]) -> Void

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// 刻意用自己的 @State 而非 @Binding：外層是用 Binding(get:set:) 現組的，
    /// SwiftUI 追蹤不到它的相依性，打勾後畫面不會更新。改完按「完成」才寫回。
    @State private var selected: [UUID] = []

    private func matches(_ p: SideRolePersonCandidate) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return p.name.localizedCaseInsensitiveContains(q)
            || p.subtitle.localizedCaseInsensitiveContains(q)
            || p.department.localizedCaseInsensitiveContains(q)
    }

    private var grouped: [(dept: String, people: [SideRolePersonCandidate])] {
        let list = lifeStore.sideRolePersonCandidates().filter(matches)
        var order: [String] = []
        var map: [String: [SideRolePersonCandidate]] = [:]
        for p in list {
            let key = p.department.isEmpty ? "未分部門" : p.department
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(p)
        }
        // 明確標型別：本檔案曾因具名 tuple 的鏈式推導撞上 type-check 逾時
        return order.map { (dept: String) -> (dept: String, people: [SideRolePersonCandidate]) in
            (dept: dept, people: map[dept] ?? [])
        }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.dept) { group in
                Section(group.dept) {
                    ForEach(group.people) { p in row(p) }
                }
            }
            if grouped.isEmpty {
                Text("找不到符合的人。負責人只能從部屬、名片或組織人員中挑選。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .searchable(text: $query, prompt: "搜尋姓名、職稱或部門")
        .navigationTitle("指派負責人")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { onDone(selected); dismiss() }.bold()
            }
        }
        .onAppear { selected = initial }
    }

    private func row(_ p: SideRolePersonCandidate) -> some View {
        let isOn = selected.contains(p.id)
        return Button {
            if isOn { selected.removeAll { $0 == p.id } } else { selected.append(p.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isOn ? .indigo : .secondary)
                Image(systemName: p.kind.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.indigo.opacity(0.7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name).foregroundStyle(.primary)
                    if !p.subtitle.isEmpty {
                        Text(p.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 任務編輯 Sheet

struct TaskEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let subordinateId: UUID
    var editing: SubordinateTask?

    @State private var topic = ""
    @State private var content = ""
    @State private var date = Date()
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var note = ""
    @State private var isCompleted = false
    @State private var assignedSubId = UUID()   // 指派給哪位部屬（可換人處理）
    @State private var isSaving = false

    /// 統一 Section 標題：4pt 漸層色條 + 圖示 + 粗體文字，對齊 RecordEditorSheet.editorSectionHeader 規格。
    private func editorSectionHeader(_ title: String, icon: String, tint: Color = .cyan) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [tint, tint.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.subheadline.weight(.bold))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("任務主題", text: $topic)
                    MentionTextField(text: $content, placeholder: "任務內容（可打 @ 標註人員）", people: lifeStore.mentionPeople())
                    HStack {
                        Text("任務日期")
                        Spacer()
                        FiveMinuteDateTimePicker(selection: $date).fixedSize()
                    }
                    Toggle("設定截止日", isOn: $hasDueDate)
                    if hasDueDate {
                        HStack {
                            Text("截止日期")
                            Spacer()
                            FiveMinuteDateTimePicker(selection: $dueDate).fixedSize()
                        }
                    }
                } header: {
                    editorSectionHeader("任務資訊", icon: "checklist")
                }
                Section {
                    Picker(selection: $assignedSubId) {
                        ForEach(lifeStore.subordinates) { s in
                            Text(s.name.isEmpty ? "未命名" : s.name).tag(s.id)
                        }
                    } label: {
                        Label("指派給", systemImage: "person.crop.circle.badge.checkmark")
                    }
                } header: {
                    editorSectionHeader("指派人員", icon: "person.crop.circle.badge.checkmark")
                } footer: {
                    if assignedSubId != subordinateId {
                        Text("儲存後此任務會移交給所選人員。")
                    }
                }
                Section {
                    Toggle(isOn: $isCompleted) {
                        Label("標記為已完成", systemImage: isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isCompleted ? .green : .primary)
                    }
                    .tint(.green)
                } header: {
                    editorSectionHeader("完成狀態", icon: "checkmark.seal.fill", tint: .green)
                }
                Section {
                    MentionTextField(text: $note, placeholder: "選填（可打 @ 標註人員）", people: lifeStore.mentionPeople())
                } header: {
                    editorSectionHeader("備註", icon: "note.text", tint: Color(.systemGray2))
                }
                if editing != nil {
                    Section {
                        Button(role: .destructive) { deleteTask() } label: { Label("刪除任務", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯任務" : "新增任務")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    // [美化 v25.99] 存檔中顯示同色 ProgressView，對齊 RecordEditorSheet／
                    // GradeTitleView v25.95 等 isSaving 忙碌守衛按鈕載入狀態規格。
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView().scaleEffect(0.7).tint(.green)
                        }
                        Button(editing != nil ? "儲存" : "新增") { save() }
                            .bold().foregroundStyle(.green)
                            .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    }
                }
            }
            .onAppear {
                assignedSubId = subordinateId
                if let e = editing {
                    topic = e.topic; content = e.content; date = e.date; note = e.note
                    isCompleted = e.isCompleted
                    if let d = e.dueDate { hasDueDate = true; dueDate = d }
                } else {
                    // 新任務：預設時間用排程時段（整點/半點，過 18:00 則隔天 09:30）
                    date = FiveMinuteDateTimePicker.defaultSchedulingTime()
                    dueDate = date
                }
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        // 完成時間：原本未完成→改完成時記下現在；維持完成則沿用舊時間；取消完成則清空
        let completedAt: Date? = isCompleted ? (editing?.completedAt ?? Date()) : nil
        let task = SubordinateTask(
            id: editing?.id ?? UUID(),
            topic: topic.trimmingCharacters(in: .whitespaces),
            content: content.trimmingCharacters(in: .whitespaces),
            date: date, dueDate: hasDueDate ? dueDate : nil,
            note: note.trimmingCharacters(in: .whitespaces),
            isCompleted: isCompleted, completedAt: completedAt,
            // 重建時保留既有欄位——不帶的話存個檔就把兼任連結/提醒對應洗掉
            sideRoleLink: editing?.sideRoleLink,
            reminderId: editing?.reminderId
        )
        let targetId = assignedSubId
        // 換人：先從原持有者移除該任務
        if targetId != subordinateId,
           var old = lifeStore.subordinates.first(where: { $0.id == subordinateId }) {
            old.tasks.removeAll { $0.id == task.id }
            lifeStore.update(old)
        }
        // 寫入目標人員（同一人則原地更新 / 新增；換人則加到新人員）
        guard var target = lifeStore.subordinates.first(where: { $0.id == targetId }) else { dismiss(); return }
        if let idx = target.tasks.firstIndex(where: { $0.id == task.id }) { target.tasks[idx] = task }
        else { target.tasks.append(task) }
        lifeStore.update(target)
        // Apple 提醒事項同步（開啟時才動作）
        lifeStore.syncReminderForSubordinateTask(subordinateId: targetId, taskId: task.id)
        dismiss()
    }

    private func deleteTask() {
        guard !isSaving else { return }
        guard let e = editing, var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
        isSaving = true
        ReminderBridge.shared.deleteAsync(id: e.reminderId)
        sub.tasks.removeAll { $0.id == e.id }
        lifeStore.update(sub); dismiss()
    }
}

// MARK: - 報告編輯

struct WeeklyReportEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let subordinateId: UUID
    var editing: WeeklyReport?

    @State private var topic = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var isCompleted = false
    @State private var isSaving = false

    /// 統一 Section 標題：4pt 漸層色條 + 圖示 + 粗體文字，對齊 RecordEditorSheet.editorSectionHeader 規格。
    private func editorSectionHeader(_ title: String, icon: String, tint: Color = .purple) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [tint, tint.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.subheadline.weight(.bold))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("報告題目", text: $topic)
                    HStack {
                        Text("日期")
                        Spacer()
                        FiveMinuteDateTimePicker(selection: $date).fixedSize()
                    }
                } header: {
                    editorSectionHeader("報告", icon: "doc.text.fill")
                }
                Section {
                    Toggle(isOn: $isCompleted) {
                        Label("標記為已完成", systemImage: isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isCompleted ? .green : .primary)
                    }
                    .tint(.green)
                } header: {
                    editorSectionHeader("完成狀態", icon: "checkmark.seal.fill", tint: .green)
                }
                Section {
                    MentionTextField(text: $note, placeholder: "選填（可打 @ 標註人員）", people: lifeStore.mentionPeople())
                } header: {
                    editorSectionHeader("備註", icon: "note.text", tint: Color(.systemGray2))
                }
                if editing != nil {
                    Section {
                        Button(role: .destructive) { deleteReport() } label: { Label("刪除報告", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯報告" : "新增報告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    // [美化 v25.99] 存檔中顯示同色 ProgressView，對齊 RecordEditorSheet／
                    // GradeTitleView v25.95 等 isSaving 忙碌守衛按鈕載入狀態規格。
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView().scaleEffect(0.7).tint(.green)
                        }
                        Button(editing != nil ? "儲存" : "新增") { save() }
                            .bold().foregroundStyle(.green)
                            .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    }
                }
            }
            .onAppear {
                if let e = editing {
                    topic = e.topic; date = e.date; note = e.note; isCompleted = e.isCompleted
                } else {
                    date = FiveMinuteDateTimePicker.defaultSchedulingTime()
                }
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
        isSaving = true
        let report = WeeklyReport(
            id: editing?.id ?? UUID(),
            topic: topic.trimmingCharacters(in: .whitespaces),
            date: date,
            note: note.trimmingCharacters(in: .whitespaces),
            isCompleted: isCompleted,
            // 由切換保留／補上完成時間：仍完成→沿用既有戳記（首次完成則記為現在）；取消完成→清空
            completedAt: isCompleted ? (editing?.completedAt ?? Date()) : nil
        )
        if let idx = sub.weeklyReports.firstIndex(where: { $0.id == report.id }) { sub.weeklyReports[idx] = report }
        else { sub.weeklyReports.append(report) }
        lifeStore.update(sub); dismiss()
    }

    private func deleteReport() {
        guard !isSaving else { return }
        guard let e = editing, var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
        isSaving = true
        sub.weeklyReports.removeAll { $0.id == e.id }
        lifeStore.update(sub); dismiss()
    }
}

// MARK: - 5 分鐘間隔 + 24 小時制日期時間選擇器

/// 包裝 UIDatePicker：分鐘只允許 5 的倍數，並強制 24 小時制（維持繁體中文）。
/// SwiftUI 原生 DatePicker 無法設定 minuteInterval，故以 UIViewRepresentable 實作。
struct FiveMinuteDateTimePicker: UIViewRepresentable {
    @Binding var selection: Date
    var minimumDate: Date? = nil
    var maximumDate: Date? = nil

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .compact
        picker.minuteInterval = 5
        picker.locale = Self.hour24Locale
        picker.minimumDate = minimumDate
        picker.maximumDate = maximumDate
        picker.date = selection
        picker.addTarget(context.coordinator,
                         action: #selector(Coordinator.valueChanged(_:)),
                         for: .valueChanged)
        picker.setContentHuggingPriority(.required, for: .horizontal)
        picker.setContentCompressionResistancePriority(.required, for: .horizontal)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        picker.minuteInterval = 5
        picker.locale = Self.hour24Locale
        picker.minimumDate = minimumDate
        picker.maximumDate = maximumDate
        if picker.date != selection { picker.date = selection }
    }

    /// 回報固有大小，避免在 Form 的 HStack 中被 Spacer 壓縮到幾乎消失
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIDatePicker, context: Context) -> CGSize? {
        let intrinsic = uiView.intrinsicContentSize
        if intrinsic.width > 0 && intrinsic.height > 0 { return intrinsic }
        return uiView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        let parent: FiveMinuteDateTimePicker
        init(_ parent: FiveMinuteDateTimePicker) { self.parent = parent }
        @objc func valueChanged(_ sender: UIDatePicker) { parent.selection = sender.date }
    }

    /// 維持繁中、但強制 0–23 小時制
    private static var hour24Locale: Locale {
        var components = Locale.Components(locale: Locale(identifier: "zh_Hant_TW"))
        components.hourCycle = .zeroToTwentyThree
        return Locale(components: components)
    }

    /// 新增任務 / 會議的預設時間：
    /// 1. 無條件進位到下一個整點或半點（:00 / :30）
    /// 2. 若不在 09:00–18:00 範圍內 → 改用 09:30（晚上 18:00 後用「隔天」09:30，清晨太早用「當天」09:30）
    static func defaultSchedulingTime(from now: Date = Date()) -> Date {
        let cal = Calendar.current
        let hourNow = cal.component(.hour, from: now)
        let minuteNow = cal.component(.minute, from: now)

        // 進位到下一個 :00 / :30
        let rounded: Date
        if minuteNow == 0 {
            rounded = cal.date(bySettingHour: hourNow, minute: 0, second: 0, of: now) ?? now
        } else if minuteNow <= 30 {
            rounded = cal.date(bySettingHour: hourNow, minute: 30, second: 0, of: now) ?? now
        } else {
            let base = cal.date(bySettingHour: hourNow, minute: 0, second: 0, of: now) ?? now
            rounded = cal.date(byAdding: .hour, value: 1, to: base) ?? now
        }

        // 落在 09:00–18:00（含邊界）就直接用
        let h = cal.component(.hour, from: rounded)
        let m = cal.component(.minute, from: rounded)
        let withinWindow = h >= 9 && (h < 18 || (h == 18 && m == 0))
        if withinWindow { return rounded }

        // 否則改用 09:30：晚上（now 已過 18:00）用隔天，清晨太早用當天
        let dayAnchor = hourNow >= 18 ? (cal.date(byAdding: .day, value: 1, to: now) ?? now) : now
        return cal.date(bySettingHour: 9, minute: 30, second: 0, of: dayAnchor) ?? now
    }

    /// 把時間對齊到最接近的 5 分鐘倍數（秒歸零）。用於「即時紀錄」類（如育兒）的預設值，
    /// 這類是記錄當下發生的事，不適合套用排程用的 09:30 規則。
    static func roundedToFiveMinutes(_ date: Date) -> Date {
        let cal = Calendar.current
        let minute = cal.component(.minute, from: date)
        let second = cal.component(.second, from: date)
        let target = Int((Double(minute) / 5.0).rounded()) * 5
        let base = cal.date(byAdding: .second, value: -second, to: date) ?? date
        return cal.date(byAdding: .minute, value: target - minute, to: base) ?? date
    }
}

// MARK: - @標註（名片 / 部屬）系統

/// 可被 @ 標註的人員（來源：部屬 + 名片）
struct MentionPerson: Identifiable, Hashable {
    enum Kind: String { case sub, card }
    let id: UUID
    let kind: Kind
    let name: String
    let subtitle: String
}

extension LifeStore {
    /// 供 @ 標註使用的人員清單（部屬 + 名片）
    ///
    /// ⚠️ 每新增一位有部門的部屬，syncOrgPersonFor(subordinate:) 會**自動**幫他建一張
    ///    名片。所以「全部部屬 + 全部名片」會讓同一個人在挑人清單裡出現兩次
    ///    （一列標「部屬」、一列標「名片」，名字一模一樣），這是使用者長期回報
    ///    「選人時常常出現兩個相同的名字」的原因。
    ///
    ///    凡是能循「名片 ← 組織人員 → 部屬」連回某位部屬的名片一律不列，
    ///    部屬身分才是這個人的正典 id。
    ///
    ///    去重不影響既有文字：標註在文字裡是以「@名字」純文字儲存、顯示時才依名字
    ///    解析成連結（見 MentionText），不是存 id。也不影響評分：mentionedCounts()
    ///    產生的計數表本來就只有 counts[部屬 id] 會被 proactivityScore 讀取，
    ///    先前多出來的那份名片計數從來沒有人用。
    func mentionPeople() -> [MentionPerson] {
        var out: [MentionPerson] = []
        let listedSubIds = Set(subordinates.map(\.id))
        let cardIdsOwnedBySubordinates = Set(
            orgPeople.compactMap { p -> UUID? in
                guard let sid = p.linkedSubordinateId, listedSubIds.contains(sid) else { return nil }
                return p.linkedBusinessCardId
            }
        )
        for s in subordinates where !s.name.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append(MentionPerson(id: s.id, kind: .sub, name: s.name,
                                     subtitle: s.jobTitle.isEmpty ? s.department : s.jobTitle))
        }
        for c in businessCards where !c.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !cardIdsOwnedBySubordinates.contains(c.id) {
            out.append(MentionPerson(id: c.id, kind: .card, name: c.name, subtitle: c.company))
        }
        return out
    }

    /// 一次掃描所有部屬的任務/會議/報告，統計每個人被 @ 標註到的「項目數」。
    /// 同一項目同一人只計一次。用於主動性加分與看板「被標註」計數。
    func mentionedCounts() -> [UUID: Int] {
        // 人員清單只排序一次，往下傳給每筆任務/會議/報告的 mentionedIDs，
        // 避免同一份清單在巢狀迴圈中被重複 filter + sort。
        let sortedPeople = MentionText.sortedByNameLengthDescending(mentionPeople())
        var counts: [UUID: Int] = [:]
        for s in subordinates {
            for t in s.tasks {
                let ids = MentionText.mentionedIDs(in: t.content, sortedPeople: sortedPeople)
                    .union(MentionText.mentionedIDs(in: t.note, sortedPeople: sortedPeople))
                for id in ids { counts[id, default: 0] += 1 }
            }
            for m in s.meetings {
                var ids = MentionText.mentionedIDs(in: m.note, sortedPeople: sortedPeople)
                for item in m.allItems {
                    ids.formUnion(MentionText.mentionedIDs(in: item.content, sortedPeople: sortedPeople))
                    ids.formUnion(MentionText.mentionedIDs(in: item.note, sortedPeople: sortedPeople))
                }
                for id in ids { counts[id, default: 0] += 1 }
            }
            for r in s.weeklyReports {
                for id in MentionText.mentionedIDs(in: r.note, sortedPeople: sortedPeople) { counts[id, default: 0] += 1 }
            }
        }
        return counts
    }
}

/// 標註文字工具：文字內以乾淨的 `@名字` 儲存，顯示時再依名字解析為可點連結。
enum MentionText {
    /// 插入時使用的純文字（只有名字，不含代碼）
    static func plainToken(for p: MentionPerson) -> String { "@\(p.name)" }

    /// 取出文字中所有被 @ 標註且能對應到人員的 id（用於「被標註的項目」）
    static func mentionedIDs(in raw: String, people: [MentionPerson]) -> Set<UUID> {
        mentionedIDs(in: raw, sortedPeople: sortedByNameLengthDescending(people))
    }

    /// 以最長名字優先比對，避免「王」先於「王小明」誤配
    static func sortedByNameLengthDescending(_ people: [MentionPerson]) -> [MentionPerson] {
        people.filter { !$0.name.isEmpty }.sorted { $0.name.count > $1.name.count }
    }

    /// 供呼叫端在迴圈中重複解析多筆文字時使用：人員清單先排序一次再重複傳入，
    /// 避免每呼叫一次就重新 filter + sort 整份人員清單。
    static func mentionedIDs(in raw: String, sortedPeople: [MentionPerson]) -> Set<UUID> {
        var ids = Set<UUID>()
        var s = Substring(raw)
        while let atIdx = s.firstIndex(of: "@") {
            let afterAt = s[s.index(after: atIdx)...]
            if let p = sortedPeople.first(where: { afterAt.hasPrefix($0.name) }) {
                ids.insert(p.id)
                s = afterAt[afterAt.index(afterAt.startIndex, offsetBy: p.name.count)...]
            } else {
                s = afterAt
            }
        }
        return ids
    }

    /// 將文字內的 `@名字` 依人員清單解析為可點連結（藍字）；找不到對應者則維持純文字。
    static func attributed(_ raw: String, people: [MentionPerson]) -> AttributedString {
        // 以最長名字優先比對，避免「王」先於「王小明」誤配
        let sorted = people.filter { !$0.name.isEmpty }.sorted { $0.name.count > $1.name.count }
        var out = AttributedString()
        var s = Substring(raw)
        while let atIdx = s.firstIndex(of: "@") {
            out += AttributedString(String(s[s.startIndex..<atIdx]))          // @ 前的文字
            let afterAt = s[s.index(after: atIdx)...]
            if let p = sorted.first(where: { afterAt.hasPrefix($0.name) }) {
                var link = AttributedString("@\(p.name)")
                link.link = URL(string: "lifegood://person/\(p.kind.rawValue)/\(p.id.uuidString)")
                link.foregroundColor = .blue
                out += link
                s = afterAt[afterAt.index(afterAt.startIndex, offsetBy: p.name.count)...]
            } else {
                out += AttributedString("@")
                s = afterAt
            }
        }
        out += AttributedString(String(s))
        return out
    }
}

/// 帶 @ 標註下拉選單的輸入框（純文字 + 建議清單）
struct MentionTextField: View {
    @Binding var text: String
    var placeholder: String
    var lineLimit: ClosedRange<Int> = 2...6
    let people: [MentionPerson]

    @State private var activeQuery: String? = nil

    private var suggestions: [MentionPerson] {
        guard let q = activeQuery else { return [] }
        let query = q.lowercased()
        let base = query.isEmpty ? people : people.filter { $0.name.lowercased().contains(query) }
        return Array(base.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(lineLimit)
                .onChange(of: text) { _, v in updateQuery(v) }

            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions) { p in
                        Button { insert(p) } label: { row(p) }
                            .buttonStyle(.plain)
                        if p.id != suggestions.last?.id { Divider().padding(.leading, 50) }
                    }
                }
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator).opacity(0.25), lineWidth: 0.75))
            }
        }
    }

    private func row(_ p: MentionPerson) -> some View {
        let tint: Color = p.kind == .sub ? .blue : .teal
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [tint.opacity(0.20), tint.opacity(0.08)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                Circle().stroke(tint.opacity(0.22), lineWidth: 1).frame(width: 28, height: 28)
                Image(systemName: p.kind == .sub ? "person.fill" : "person.crop.rectangle.stack.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                // [v25.77] 補齊 lineLimit/minimumScaleFactor，對齊下方 subtitle 與 headerCard subordinate.name 規格
                Text(p.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !p.subtitle.isEmpty {
                    Text(p.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(p.kind == .sub ? "部屬" : "名片")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6).padding(.vertical, 1.5)
                .background(tint.opacity(0.14))
                .foregroundStyle(tint)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    /// 偵測游標前最後一段 `@查詢`（其後不能有空白/換行；@ 前須為開頭或空白）
    private func updateQuery(_ s: String) {
        guard let atRange = s.range(of: "@", options: .backwards) else { activeQuery = nil; return }
        let after = s[atRange.upperBound...]
        if after.contains(where: { $0 == " " || $0 == "\n" || $0 == "\t" }) { activeQuery = nil; return }
        if atRange.lowerBound > s.startIndex {
            let before = s[s.index(before: atRange.lowerBound)]
            if before != " " && before != "\n" && before != "\t" { activeQuery = nil; return }
        }
        activeQuery = String(after)
    }

    private func insert(_ p: MentionPerson) {
        guard let atRange = text.range(of: "@", options: .backwards) else { activeQuery = nil; return }
        text.replaceSubrange(atRange.lowerBound..<text.endIndex, with: MentionText.plainToken(for: p) + " ")
        activeQuery = nil
    }
}

// MARK: - 美化紀錄（MentionTextField）
// [2026-08 v1] 首次美化：MentionTextField 自 4b07cbb 導入後（供 RecordEditorSheet／
// MeetingEditorSheet／TaskEditorSheet／WeeklyReportEditorSheet 共用的 @ 標註輸入框），
// row(_:) 建議清單列一直沿用裸 24pt 單色 SF Symbol 圖示（無底圓）+ 純文字 kind 標籤
// （無底色），與本檔案 meetingItemOverviewRow／CompletedCollapsibleCard 等既有列的
// 28-36pt LinearGradient 漸層圖示圓（fill 0.20→0.08 + stroke 0.22 lineWidth 1）與
// Capsule 底色標籤規格不一致。改為：圖示套上 28pt 漸層圓（依 kind 用 blue／teal 識別色）
// + stroke 描邊；trailing 的「部屬」/「名片」標籤改用 Capsule().fill(color.opacity(0.14))
// 包底色，與 kind.color 標籤慣例一致。Divider 對齊縮排隨圖示加寬同步從 40→50。
// 純視覺調整，未變動 updateQuery／insert／suggestions 等既有 @ 標註邏輯。
// [v25.77] row(_:) 主要一行 p.name（部屬姓名或名片自填姓名，長度不可控）自 v1 改版後
// 只有下方 p.subtitle 補了 lineLimit(1)，p.name 本身反而沒有防截斷，與同檔案 headerCard
// 的 Text(subordinate.name)（.lineLimit(1) + .minimumScaleFactor(0.8)）規格不一致。
// 「輔助模式：特大」字級下，@ 標註建議清單較長的姓名會換行，把 trailing 的「部屬」/「名片」
// 膠囊擠出原本的垂直置中對齊。補上 .lineLimit(1) + .minimumScaleFactor(0.8)，對齊
// headerCard 相同規格。純視覺調整，未變動任何 @ 標註邏輯。

// MARK: - 部屬事項預覽卡（點開先看卡片，右上角編輯才進入編輯）

/// 部屬事項參照（任務 / 會議 / 報告 / 請假）
enum SubordinateItemRef: Identifiable {
    case task(subId: UUID, task: SubordinateTask)
    case meeting(subId: UUID, meeting: SubordinateMeeting)
    case report(subId: UUID, report: WeeklyReport)
    case leave(subId: UUID, rec: SubordinateRecord)
    case record(subId: UUID, rec: SubordinateRecord)   // 通用記錄（優點/缺點/成就/改善/缺失/Miss Operation）
    var id: String {
        switch self {
        case .task(_, let t):    return "t_\(t.id.uuidString)"
        case .meeting(_, let m): return "m_\(m.id.uuidString)"
        case .report(_, let r):  return "r_\(r.id.uuidString)"
        case .leave(_, let rec): return "l_\(rec.id.uuidString)"
        case .record(_, let rec): return "rec_\(rec.id.uuidString)"
        }
    }
}

/// UUID 的 .sheet(item:) 包裝（UUID 不是 Identifiable）。
/// 不能是 private：MeetingItemsEditor（internal）的 @Binding 屬性用到它，
/// 屬性的型別存取層級不能比屬性所屬的型別窄，否則編譯錯誤。
struct IDBox: Identifiable { let id: UUID }

/// 分享項目的 Identifiable 包裝（供 .sheet(item:) 使用）：可裝圖片暫存檔 URL 或純文字
private struct CardSharePayload: Identifiable { let id = UUID(); let items: [Any] }

struct SubordinateItemCard: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    let ref: SubordinateItemRef

    @State private var showEdit = false
    @State private var openSub: Subordinate?
    @State private var openCard: IDBox?
    @State private var shareItem: CardSharePayload?
    // [v1] 卡片內容進場動畫旗標，對齊本檔案其餘 sheet／卡片一致採用的淡入進場規格
    @State private var cardAppeared = false

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d (E) HH:mm"; return f
    }()
    private func fmt(_ d: Date) -> String { Self.dateFmt.string(from: d) }
    private static let dateOnlyFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d (E)"; return f
    }()
    /// 有設定時間（非午夜 00:00）才顯示時分，否則僅顯示日期。
    private func fmtDue(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour == 0 && c.minute == 0) ? Self.dateOnlyFmt.string(from: d) : Self.dateFmt.string(from: d)
    }

    // MARK: - 分享為圖片

    private static let stampFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmm"; return f
    }()

    /// 把卡片內容渲染成 JPG 並開啟系統分享面板（對齊 TalentMatrixView.exportJPG 既有寫法）。
    @MainActor
    private func shareJPG() {
        let content = VStack(alignment: .leading, spacing: 16) { cardBody }
            .frame(width: 420)
            .padding(20)
            .background(Color(.systemBackground))
            .environmentObject(lifeStore)
        let renderer = ImageRenderer(content: content)
        renderer.scale = max(UIScreen.main.scale, 3)
        guard let ui = renderer.uiImage, let data = ui.jpegData(compressionQuality: 0.95) else { return }
        let name = "\(navTitle)_\(Self.stampFmt.string(from: Date())).jpg"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            shareItem = CardSharePayload(items: [url])
        } catch { }
    }

    /// 把卡片內容組成 Emoji 排版純文字並開啟系統分享面板
    /// （LINE／訊息可直接貼上顯示，比 HTML 檔案更適合聊天分享）。
    private func shareText() {
        shareItem = CardSharePayload(items: [shareTextContent()])
    }

    private static let weekdayShort = ["日", "一", "二", "三", "四", "五", "六"]

    private func ruleSummary(_ r: MeetingRecurrenceRule) -> String {
        var s = r.frequency.rawValue
        if (r.frequency == .weekly || r.frequency == .biweekly), !r.weekdays.isEmpty {
            let days = r.weekdays.sorted().compactMap { wd -> String? in
                guard wd >= 1 && wd <= 7 else { return nil }
                return "週" + Self.weekdayShort[wd - 1]
            }
            if !days.isEmpty { s += "（\(days.joined(separator: "、"))）" }
        }
        if let end = r.endDate { s += "，至 \(Self.dateOnlyFmt.string(from: end))" }
        return s
    }

    /// 卡片上只列「七天前」之後、最多 12 場——這是預覽卡不是完整清單，
    /// 開了兩年的每週會議展開後上百場，全塞進來會把卡片拉到看不完。
    private func displayOccurrences(of m: SubordinateMeeting) -> [ResolvedMeetingOccurrence] {
        let cal = Calendar.current
        let horizon = cal.date(byAdding: .month, value: 3, to: Date()) ?? Date()
        let floor = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let all = m.expandedOccurrences(from: floor, horizon: horizon)
        let kept = all.filter { $0.date >= floor || !$0.items.isEmpty }
        return Array(kept.prefix(12))
    }

    @ViewBuilder
    private func occurrenceBlock(_ occ: ResolvedMeetingOccurrence,
                                 meeting: SubordinateMeeting, subId: UUID) -> some View {
        let head = MeetingTimeFormat.dateTime24.string(from: occ.date)
            + (occ.isCancelled ? "（已取消）" : occ.isMoved ? "（已改期）" : "")
            + (occ.isAdHoc ? "（臨時）" : "")
        if occ.items.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: occ.isCancelled ? "calendar.badge.minus" : "calendar")
                    .font(.system(size: 11))
                Text(head).font(.caption)
                Text("尚無議程").font(.caption2).foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .foregroundStyle(occ.isCancelled ? Color.red.opacity(0.8) : Color.secondary)
            .padding(.horizontal, 4)
        } else {
            agendaBlock(title: head, items: occ.items, meeting: meeting, subId: subId)
        }
    }

    private func agendaBlock(title: String, items: [MeetingItem],
                             meeting: SubordinateMeeting, subId: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ForEach(items) { item in
                agendaRow(item, meetingId: meeting.id, subId: subId)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding().background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // [v1] 補 overlay 細邊框，對齊 field()／richBlock() 同批補齊規格
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
    }

    private func agendaRow(_ item: MeetingItem, meetingId: UUID, subId: UUID) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                lifeStore.toggleMeetingItemCompletion(subordinateId: subId, meetingId: meetingId, itemId: item.id)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15)).foregroundStyle(item.isCompleted ? Color.green : Color.indigo)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(MentionText.attributed(item.content.isEmpty ? "未填內容" : item.content, people: people))
                    .font(.subheadline).tint(.blue)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                if let who = assigneeNames(item.assigneeIds) {
                    Label(who, systemImage: "person.2.fill")
                        .font(.caption2).foregroundStyle(.indigo)
                }
                if let due = item.dueDate {
                    Label(fmtDue(due), systemImage: "clock")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let back = item.sideRoleLink { SideRoleLinkBadge(back: back) }
                if !item.note.isEmpty {
                    Text(MentionText.attributed(item.note, people: people))
                        .font(.caption2).tint(.blue).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if item.isCompleted, let at = item.completedAt {
                Text(fmtDue(at)).font(.caption2).foregroundStyle(.green)
            }
        }
    }

    /// 匯出文字用的議程列（會議本身與各場次共用一份格式）
    private func agendaLines(_ items: [MeetingItem]) -> [String] {
        var lines: [String] = []
        for item in items {
            var row = "\(item.isCompleted ? "✅" : "⬜️") \(item.content.isEmpty ? "未填內容" : item.content)"
            if let who = assigneeNames(item.assigneeIds) { row += "｜👤 \(who)" }
            lines.append(row)
            if item.isCompleted, let at = item.completedAt {
                lines.append("　└ 🏁 \(fmtDue(at)) 完成")
            } else if let due = item.dueDate {
                lines.append("　└ ⏰ 截止 \(fmtDue(due))")
            }
            if !item.note.isEmpty { lines.append("　└ 💬 \(item.note)") }
        }
        return lines
    }

    /// 負責人可能來自部屬／名片／組織人員三種來源，統一走挑人清單那份反查。
    private func assigneeNames(_ ids: [UUID]) -> String? {
        let names = ids.compactMap { lifeStore.sideRolePerson($0)?.name }
        return names.isEmpty ? nil : names.joined(separator: "、")
    }

    private func shareTextContent() -> String {
        let divider = "━━━━━━━━━━━━━━"
        var lines: [String] = []
        switch ref {
        case .task(let subId, let snap):
            let t = lifeStore.subordinates.first { $0.id == subId }?.tasks.first { $0.id == snap.id } ?? snap
            lines.append("📋 任務｜\(t.topic.isEmpty ? "未命名任務" : t.topic)")
            lines.append(divider)
            lines.append("🗓 任務日期：\(fmt(t.date))")
            if let due = t.dueDate { lines.append("⏰ 截止日期：\(fmt(due))") }
            if t.isCompleted, let at = t.completedAt { lines.append("✅ 完成時間：\(fmt(at))") }
            if !t.content.isEmpty { lines.append(""); lines.append("📝 內容"); lines.append(t.content) }
            if !t.note.isEmpty { lines.append(""); lines.append("💬 備註"); lines.append(t.note) }
        case .meeting(let subId, let snap):
            let m = lifeStore.subordinates.first { $0.id == subId }?.meetings.first { $0.id == snap.id } ?? snap
            lines.append("👥 會議｜\(m.topic.isEmpty ? "未命名會議" : m.topic)")
            lines.append(divider)
            lines.append("🕐 會議時間：\(fmt(m.date)) – \(MeetingTimeFormat.time24.string(from: m.endDate))")
            lines.append("⏱ 會議長度：\(m.durationMinutes) 分鐘")
            lines.append("🗓 產生時間：\(fmt(m.createdAt))")
            if let r = m.rule { lines.append("🔁 週期：\(ruleSummary(r))") }
            if m.isRecurring || !m.occurrences.isEmpty {
                // 有週期、或不開週期但有加開場次：都依場次分段
                for occ in displayOccurrences(of: m) {
                    lines.append("")
                    var head = "📅 \(MeetingTimeFormat.dateTime24.string(from: occ.date))"
                    if occ.isCancelled { head += "（已取消）" }
                    else if occ.isMoved { head += "（原定 \(MeetingTimeFormat.dateTime24.string(from: occ.scheduledDate))）" }
                    if occ.isAdHoc { head += "（臨時）" }
                    lines.append(head)
                    if occ.items.isEmpty { lines.append("　（尚無議程）") }
                    else { lines.append(contentsOf: agendaLines(occ.items)) }
                }
            } else if !m.allItems.isEmpty {
                let done = m.allItems.filter(\.isCompleted).count
                lines.append("")
                lines.append("📌 議程項目（\(done)/\(m.allItems.count) 完成）")
                lines.append(contentsOf: agendaLines(m.allItems))
            }
            if !m.note.isEmpty { lines.append(""); lines.append("💬 備註"); lines.append(m.note) }
        case .report(let subId, let snap):
            let r = lifeStore.subordinates.first { $0.id == subId }?.weeklyReports.first { $0.id == snap.id } ?? snap
            lines.append("📄 報告｜\(r.topic.isEmpty ? "未命名報告" : r.topic)")
            lines.append(divider)
            lines.append("🗓 報告日期：\(fmt(r.date))")
            if r.isCompleted, let at = r.completedAt { lines.append("✅ 完成時間：\(fmt(at))") }
            if !r.note.isEmpty { lines.append(""); lines.append("💬 備註"); lines.append(r.note) }
        case .leave(let subId, let snap), .record(let subId, let snap):
            let rec = lifeStore.subordinates.first { $0.id == subId }?.records.first { $0.id == snap.id } ?? snap
            let emoji: String = {
                switch rec.type {
                case .pro: return "👍"; case .con: return "👎"
                case .achievement: return "🏆"; case .improvement: return "📈"
                case .fault: return "⚠️"; case .missOperation: return "❌"
                case .leave: return "🌴"
                }
            }()
            lines.append("\(emoji) \(rec.type.rawValue)｜\(rec.content.isEmpty ? "未填內容" : rec.content)")
            lines.append(divider)
            lines.append("🗓 日期：\(fmt(rec.date))")
            if let end = rec.endDate { lines.append("🗓 結束：\(fmt(end))") }
            if let lt = rec.leaveType { lines.append("🌴 假別：\(lt.rawValue)") }
            if let hours = rec.leaveHours, hours > 0 { lines.append("⏱ 時數：\(String(format: "%g", hours)) 小時") }
            if let sev = rec.severity { lines.append("⚠️ 嚴重度：\(sev.rawValue)") }
            if !rec.note.isEmpty { lines.append(""); lines.append("💬 備註"); lines.append(rec.note) }
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    cardBody
                }
                .padding()
                // [v1] 淡入 + 向上進場動畫，對齊本檔案其餘卡片規格
                .opacity(cardAppeared ? 1 : 0)
                .offset(y: cardAppeared ? 0 : 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Menu {
                            Button { shareJPG() } label: { Label("匯出圖片", systemImage: "photo") }
                            Button { shareText() } label: { Label("匯出文字", systemImage: "text.alignleft") }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button("編輯") { showEdit = true }.bold().foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showEdit) { editor }
            .sheet(item: $openSub) { s in SubordinateDetailView(subordinate: s) }
            .sheet(item: $openCard) { box in BusinessCardDetailView(cardId: box.id) }
            .sheet(item: $shareItem) { item in ShareSheet(items: item.items) }
            .environment(\.openURL, OpenURLAction { url in handleMention(url) })
            .onAppear {
                withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) {
                    cardAppeared = true
                }
            }
        }
    }

    private var navTitle: String {
        switch ref {
        case .task: return "任務"
        case .meeting: return "會議"
        case .report: return "報告"
        case .leave: return "請假"
        case .record(_, let rec): return rec.type.rawValue
        }
    }

    /// 供標註解析用的人員清單
    private var people: [MentionPerson] { lifeStore.mentionPeople() }

    /// 通用記錄類型對應色（與 SubordinateDetailView.colorFor 一致）
    private func recordColor(_ type: SubordinateRecordType) -> Color {
        switch type {
        case .pro: return .green; case .con: return .red
        case .achievement: return .orange; case .improvement: return .blue
        case .fault: return .pink; case .missOperation: return .purple
        case .leave: return .teal
        }
    }

    @ViewBuilder
    private var cardBody: some View {
        // 每個 case 都從 lifeStore 取最新資料（編輯儲存後即時反映），找不到才退回快照
        switch ref {
        case .task(let subId, let snap):
            let t = lifeStore.subordinates.first { $0.id == subId }?.tasks.first { $0.id == snap.id } ?? snap
            titleBlock(icon: "checklist", color: .cyan, title: t.topic.isEmpty ? "未命名任務" : t.topic)
            ownerBlock(subId: subId, accent: .cyan)
            taskStatusRow(t)
            field("任務日期", fmt(t.date))
            if let due = t.dueDate { field("截止日期", fmt(due)) }
            if t.isCompleted, let at = t.completedAt { field("完成時間", fmt(at)) }
            richBlock("內容", t.content)
            richBlock("備註", t.note)
        case .meeting(let subId, let snap):
            let m = lifeStore.subordinates.first { $0.id == subId }?.meetings.first { $0.id == snap.id } ?? snap
            titleBlock(icon: "person.3.fill", color: .indigo, title: m.topic.isEmpty ? "未命名會議" : m.topic)
            ownerBlock(subId: subId, accent: .indigo)
            field("會議時間", "\(fmt(m.date)) – \(MeetingTimeFormat.time24.string(from: m.endDate))")
            field("會議長度", "\(m.durationMinutes) 分鐘")
            field("產生時間", fmt(m.createdAt))
            if let r = m.rule { field("週期", ruleSummary(r)) }
            if m.isRecurring || !m.occurrences.isEmpty {
                // 有週期、或不開週期但有加開場次：議程項目屬於各場次，
                // 攤平顯示會看不出哪一項是哪一場的
                ForEach(displayOccurrences(of: m)) { occ in
                    occurrenceBlock(occ, meeting: m, subId: subId)
                }
            } else if !m.allItems.isEmpty {
                agendaBlock(title: "議程項目", items: m.allItems, meeting: m, subId: subId)
            }
            richBlock("備註", m.note)
        case .report(let subId, let snap):
            let r = lifeStore.subordinates.first { $0.id == subId }?.weeklyReports.first { $0.id == snap.id } ?? snap
            titleBlock(icon: "doc.text.fill", color: .purple, title: r.topic.isEmpty ? "未命名報告" : r.topic)
            ownerBlock(subId: subId, accent: .purple)
            field("報告日期", fmt(r.date))
            if r.isCompleted, let at = r.completedAt { field("完成時間", fmt(at)) }
            richBlock("備註", r.note)
        case .leave(let subId, let snap):
            let rec = lifeStore.subordinates.first { $0.id == subId }?.records.first { $0.id == snap.id } ?? snap
            titleBlock(icon: "calendar.badge.minus", color: .teal, title: rec.leaveType?.rawValue ?? "請假")
            ownerBlock(subId: subId, accent: .teal)
            field("開始", fmt(rec.date))
            if let end = rec.endDate { field("結束", fmt(end)) }
            if let h = rec.leaveHours { field("請假時數", String(format: "%.1f 小時", h)) }
            richBlock("事由", rec.content)
            richBlock("備註", rec.note)
        case .record(let subId, let snap):
            let rec = lifeStore.subordinates.first { $0.id == subId }?.records.first { $0.id == snap.id } ?? snap
            titleBlock(icon: rec.type.icon, color: recordColor(rec.type), title: rec.type.rawValue)
            ownerBlock(subId: subId, accent: recordColor(rec.type))
            field("日期", fmt(rec.date))
            if let end = rec.endDate { field("結束", fmt(end)) }
            if let sev = rec.severity { field("嚴重度", sev.rawValue) }
            richBlock("內容", rec.content)
            richBlock("備註", rec.note)
        }
    }

    // MARK: - 負責部屬資訊卡 / 任務狀態列

    /// 負責部屬資訊卡：姓名＋職等職稱＋部門＋廠區，點擊可開啟該部屬卡片。
    /// 職等/部門優先用 id 對照（gradeTitles/departments），沒有再退回文字欄位，
    /// 與 SubordinateDetailView.gradeTitleText/departmentText 同一套解析。
    @ViewBuilder
    private func ownerBlock(subId: UUID, accent: Color) -> some View {
        if let sub = lifeStore.subordinates.first(where: { $0.id == subId }) {
            let gradeTitle: String = {
                if let gt = lifeStore.gradeTitles.first(where: { $0.id == sub.gradeTitleId }) {
                    return "\(gt.grade) — \(gt.title)"
                }
                return sub.jobTitle
            }()
            let dept: String = {
                if let d = lifeStore.departments.first(where: { $0.id == sub.departmentId }) {
                    return d.code.isEmpty ? d.name : "\(d.code) \(d.name)"
                }
                return sub.department
            }()
            Button {
                openSub = sub
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.08)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 36, height: 36)
                        Circle().stroke(accent.opacity(0.22), lineWidth: 0.75).frame(width: 36, height: 36)
                        Image(systemName: "person.fill")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(accent)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("負責部屬").font(.caption2).foregroundStyle(.secondary)
                            Text(sub.name.isEmpty ? "未命名" : sub.name)
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        }
                        // 職稱 / 部門 / 廠區 膠囊列（有值才顯示）
                        HStack(spacing: 5) {
                            if !gradeTitle.isEmpty {
                                Text(gradeTitle)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(accent.opacity(0.10)).foregroundStyle(accent)
                                    .clipShape(Capsule())
                            }
                            if !dept.isEmpty {
                                Text(dept)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color(.tertiarySystemFill)).foregroundStyle(.secondary)
                                    .clipShape(Capsule())
                            }
                            if !sub.plantArea.isEmpty {
                                Text("\(sub.plantArea) 廠區")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color(.tertiarySystemFill)).foregroundStyle(.secondary)
                                    .clipShape(Capsule())
                            }
                        }
                        .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// 任務狀態列：已完成（綠）／逾期 N 天（紅）／進行中（青）
    private func taskStatusRow(_ t: SubordinateTask) -> some View {
        let (text, color): (String, Color) = {
            if t.isCompleted { return ("已完成", .green) }
            if let due = t.dueDate {
                let days = Calendar.current.dateComponents(
                    [.day],
                    from: Calendar.current.startOfDay(for: due),
                    to: Calendar.current.startOfDay(for: Date())
                ).day ?? 0
                if days > 0 { return ("逾期 \(days) 天", .red) }
            }
            return ("進行中", .cyan)
        }()
        return HStack {
            Text("狀態").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(text)
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(color.opacity(0.12)).foregroundStyle(color)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.6))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
    }

    // [v1] 補 Circle().stroke + shadow，對齊本檔案 meetingSection 等章節既有 44pt 圖示圓規格；
    // 標題補 lineLimit + minimumScaleFactor，避免超長主題在大字級輔助模式下裁切或撐高版面。
    private func titleBlock(icon: String, color: Color, title: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.08)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .shadow(color: color.opacity(0.18), radius: 5, x: 0, y: 2)
                Circle().stroke(color.opacity(0.22), lineWidth: 0.75).frame(width: 44, height: 44)
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(color)
            }
            Text(title).font(.title3.weight(.bold)).foregroundStyle(.primary)
                .lineLimit(2).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }

    // [v1] 補 overlay 細邊框，對齊本檔案其餘卡片型容器（recordRow／meetingSection 等）皆有的邊界描邊規格
    private func field(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
    }

    @ViewBuilder
    private func richBlock(_ label: String, _ content: String) -> some View {
        if !content.trimmingCharacters(in: .whitespaces).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(MentionText.attributed(content, people: people))
                    .font(.subheadline).foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tint(.blue)
            }
            .padding().background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch ref {
        case .task(let subId, let task):     TaskEditorSheet(subordinateId: subId, editing: task)
        case .meeting(let subId, let meeting): MeetingEditorSheet(subordinateId: subId, editing: meeting)
        case .report(let subId, let report):  WeeklyReportEditorSheet(subordinateId: subId, editing: report)
        case .leave(let subId, let rec):       RecordEditorSheet(subordinateId: subId, type: rec.type, editing: rec)
        case .record(let subId, let rec):      RecordEditorSheet(subordinateId: subId, type: rec.type, editing: rec)
        }
    }

    /// 點標註連結 → 開啟該人員的部屬卡片 / 名片
    private func handleMention(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "lifegood", url.host == "person" else { return .systemAction }
        let parts = url.pathComponents.filter { $0 != "/" }   // [kind, uuid]
        guard parts.count == 2, let uid = UUID(uuidString: parts[1]) else { return .handled }
        if parts[0] == "sub" {
            if let s = lifeStore.subordinates.first(where: { $0.id == uid }) { openSub = s }
        } else if parts[0] == "card" {
            if lifeStore.businessCards.contains(where: { $0.id == uid }) { openCard = IDBox(id: uid) }
        }
        return .handled
    }
}

// MARK: - 升職表單

/// 部屬升職：選新職等職稱＋生效日期＋備註。儲存時寫入升職歷程
/// （from/to 存當時職稱快照文字）並更新部屬的 gradeTitleId。
struct PromotionSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    let subordinateId: UUID

    @State private var selectedGradeTitleId: UUID?
    @State private var effectiveDate = Date()
    @State private var note = ""

    private var subordinate: Subordinate? {
        lifeStore.subordinates.first { $0.id == subordinateId }
    }

    /// 目前職稱文字（同部屬卡片 gradeTitleText 規則）
    private var currentTitleText: String {
        guard let sub = subordinate else { return "" }
        if let gt = lifeStore.gradeTitles.first(where: { $0.id == sub.gradeTitleId }) {
            return "\(gt.grade) — \(gt.title)"
        }
        return sub.jobTitle
    }

    private func titleText(_ gt: GradeTitle) -> String {
        gt.grade.isEmpty ? gt.title : "\(gt.grade) — \(gt.title)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("目前職稱") {
                    Text(currentTitleText.isEmpty ? "（未設定）" : currentTitleText)
                        .foregroundStyle(currentTitleText.isEmpty ? .secondary : .primary)
                }
                Section {
                    if lifeStore.gradeTitles.isEmpty {
                        Text("尚未建立職等職稱。請先到「職等職稱」頁新增，再回來升職。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("升任職稱", selection: $selectedGradeTitleId) {
                            Text("請選擇").tag(UUID?.none)
                            ForEach(lifeStore.gradeTitles) { gt in
                                Text(titleText(gt)).tag(Optional(gt.id))
                            }
                        }
                    }
                } header: {
                    Text("升任職稱")
                } footer: {
                    Text("升職會記入「升職歷程」（保留升職前後職稱的快照），並同步更新部屬目前職稱。")
                }
                Section {
                    DatePicker("生效日期", selection: $effectiveDate, displayedComponents: .date)
                    TextField("備註（選填，例如晉升原因）", text: $note)
                }
                Section {
                    Button {
                        applyPromotion()
                    } label: {
                        Label("確認升職", systemImage: "arrow.up.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(.orange).bold()
                    .disabled(!canPromote)
                }
            }
            .navigationTitle("升職")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }

    private var canPromote: Bool {
        guard let sel = selectedGradeTitleId else { return false }
        return sel != subordinate?.gradeTitleId
    }

    private func applyPromotion() {
        guard let idx = lifeStore.subordinates.firstIndex(where: { $0.id == subordinateId }),
              let sel = selectedGradeTitleId,
              let target = lifeStore.gradeTitles.first(where: { $0.id == sel }) else { return }
        var sub = lifeStore.subordinates[idx]
        let record = PromotionRecord(
            date: effectiveDate,
            fromTitle: currentTitleText,
            toTitle: titleText(target),
            toGradeTitleId: sel,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        sub.promotions.append(record)
        sub.gradeTitleId = sel
        // 自訂職稱文字已被職等職稱取代，清空避免舊文字在對照失敗時誤顯示
        sub.jobTitle = ""
        lifeStore.subordinates[idx] = sub   // didSet 觸發 save + iCloud 同步
        dismiss()
    }
}
