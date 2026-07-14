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
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, e in
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
                        if idx < sorted.count - 1 { Divider().padding(.leading, 57) }
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

    // 進場動畫旗標
    @State private var headerAppeared = false
    // Tab 區塊進場旗標：切換 Tab 時重置並重播
    @State private var tabSectionsAppeared = false

    enum DetailTab: String, CaseIterable { case daily = "主動性"; case rating = "潛力性" }
    @State private var detailTab: DetailTab = .daily
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
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                        tabSectionsAppeared = true
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: tab == .daily ? "person.2.fill" : "star.fill")
                                        .font(.caption2)
                                    Text(tab.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(tab == .daily ? subordinate.proactivityScore(mentionedCount: mentionedItemsCache.count) : subordinate.potentialScore)")
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
                        recordSection(.leave)
                            .opacity(tabSectionsAppeared ? 1 : 0)
                            .offset(y: tabSectionsAppeared ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.10), value: tabSectionsAppeared)
                        completedSection
                            .opacity(tabSectionsAppeared ? 1 : 0)
                            .offset(y: tabSectionsAppeared ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.13), value: tabSectionsAppeared)
                    } else {
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
                    Button("編輯") {
                        if subscription.isPremium { showEdit = true }
                        else { showPremiumAlert = true }
                    }.foregroundStyle(.green)
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
                scoreCell("主動性", subordinate.proactivityScore(mentionedCount: mentionedCount))
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 34)
                scoreCell("潛力性", subordinate.potentialScore)
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 34)
                scoreCell("綜合", subordinate.overallScore(mentionedCount: mentionedCount))
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
                statBadge(count: recordCounts[.pro] ?? 0,           label: "優點", color: .green)
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 32)
                statBadge(count: recordCounts[.con] ?? 0,           label: "缺點", color: .red)
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 32)
                statBadge(count: recordCounts[.achievement] ?? 0,   label: "成就", color: .orange)
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 32)
                statBadge(count: recordCounts[.missOperation] ?? 0, label: "Miss", color: .purple)
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 32)
                statBadge(count: recordCounts[.leave] ?? 0,         label: "請假", color: .teal)
            }
            .padding(.vertical, 8)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // 第二列 KPI：報告 / 會議 / 任務 / 被標註 / 請假
            HStack(spacing: 0) {
                statBadge(count: subordinate.weeklyReports.count, label: "報告", color: .purple)
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 32)
                statBadge(count: subordinate.meetings.count,      label: "會議", color: .indigo)
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 32)
                statBadge(count: subordinate.tasks.count,         label: "任務", color: .cyan)
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 32)
                statBadge(count: mentionedCount,                   label: "被標註", color: .pink)
                Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 32)
                statBadge(count: recordCounts[.leave] ?? 0,       label: "請假", color: .teal)
            }
            .padding(.vertical, 8)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 8)
        }
        .padding(20)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.22, green: 0.53, blue: 0.98),
                        Color(red: 0.10, green: 0.35, blue: 0.82)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 右上主散景圓
                Circle()
                    .fill(.white.opacity(0.13))
                    .frame(width: 130, height: 130)
                    .offset(x: 85, y: -50)
                    .blur(radius: 14)
                // 左下次散景圓
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 80, height: 80)
                    .offset(x: -60, y: 50)
                    .blur(radius: 10)
                // [v3] 第三顆散景圓（中右側）
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 55, height: 55)
                    .offset(x: 30, y: 28)
                    .blur(radius: 8)
                // [v3] 頂部玻璃光澤
                LinearGradient(
                    colors: [.white.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.10, green: 0.35, blue: 0.82).opacity(0.42), radius: 18, x: 0, y: 9)
        .shadow(color: .black.opacity(0.09), radius: 8, x: 0, y: 4)
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
    private func statBadge(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    // 分數看板單格：大白數字 + 標籤
    private func scoreCell(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity)
    }

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
            for item in m.items where item.isCompleted {
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
                let itemsText = m.items.map(\.content).joined(separator: "\n")
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
                                    let pending = m.items.filter { !$0.isCompleted }
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
                    let pendingItems = m.items.filter { !$0.isCompleted }
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
        }
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

    /// 請假時數 = 總時長 − 與當日班別休息時段重疊的時間
    private var computedLeaveHours: Double {
        max(0, endDate.timeIntervalSince(date) / 3600 - restDeductionHours)
    }

    /// 依當日班別的休息時段，計算需扣除的休息時數（跨日則逐日累加）
    private var restDeductionHours: Double {
        guard type == .leave, endDate > date,
              let sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { return 0 }
        let cal = Calendar.current
        let schedule = ShiftScheduleStore.shared.schedule
        var total = 0.0
        var day = cal.startOfDay(for: date)
        let last = cal.startOfDay(for: endDate)
        while day <= last {
            if let shift = sub.shifts.first(where: { cal.isDate($0.date, inSameDayAs: day) })?.type,
               let rest = schedule.restRange(for: shift),
               let rStart = cal.date(byAdding: .minute, value: rest.startMinutes, to: day),
               let rEnd = cal.date(byAdding: .minute, value: rest.endMinutes, to: day), rEnd > rStart {
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
                    }
                    Section {
                        HStack {
                            Text("開始時間")
                            Spacer()
                            FiveMinuteDateTimePicker(selection: $date).fixedSize()
                        }
                        HStack {
                            Text("結束時間")
                            Spacer()
                            FiveMinuteDateTimePicker(selection: $endDate, minimumDate: date).fixedSize()
                        }
                        if restDeductionHours > 0 {
                            HStack {
                                Text("扣除休息").foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "−%.1f 小時", restDeductionHours))
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
                            Text(String(format: "%.1f 小時", computedLeaveHours))
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
                    }
                    .opacity(leaveInfoAppeared ? 1 : 0)
                    .offset(y: leaveInfoAppeared ? 0 : 10)
                    .animation(.easeInOut(duration: 0.2), value: computedLeaveHours)
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
                    Button(editing != nil ? "儲存" : "新增") { save() }.bold().foregroundStyle(.green).disabled(!canSave)
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
        guard var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
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
        guard let e = editing, var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
        sub.records.removeAll { $0.id == e.id }
        lifeStore.update(sub); dismiss()
    }
}

// MARK: - 新增部屬項目（先選部屬，再開對應編輯器）

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
}

/// 兩步驟 Sheet：先選部屬（單一 sheet 內切換內容，避免多 sheet 競態），選完直接進對應編輯器
struct AddSubItemSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    let kind: SubAddKind
    @State private var pickedSubId: UUID?

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
                        ContentUnavailableView("尚無部屬", systemImage: "person.2.slash",
                                               description: Text("請先在『部屬』頁新增部屬，才能建立\(kind.title)"))
                    } else {
                        List {
                            ForEach(lifeStore.subordinates.sorted { $0.name < $1.name }) { sub in
                                Button {
                                    pickedSubId = sub.id
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: kind.icon)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.green).frame(width: 26)
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
// （下次美化本檔案時，可考慮：任務／報告的「標記為已完成」Toggle Section 補上統一
//   Section header；或處理本檔案其餘尚未套用漸層圖示圓規格的次要清單列）

struct MeetingEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let subordinateId: UUID
    var editing: SubordinateMeeting?

    @State private var topic = ""
    @State private var date = Date()
    @State private var durationText = "60"
    @State private var recurrence: MeetingRecurrence?
    @State private var hasRecurrence = false
    @State private var items: [MeetingItem] = []
    @State private var note = ""

    private var allSubordinates: [Subordinate] { lifeStore.subordinates }

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
                Section {
                    TextField("會議主題", text: $topic)
                    HStack {
                        Text("日期時間")
                        Spacer()
                        FiveMinuteDateTimePicker(selection: $date).fixedSize()
                    }
                    HStack {
                        TextField("會議長度", text: $durationText).keyboardType(.numberPad)
                        Text("分鐘").foregroundStyle(.secondary)
                    }
                    Toggle("設定週期", isOn: $hasRecurrence)
                    if hasRecurrence {
                        Picker("週期", selection: $recurrence) {
                            Text("不重複").tag(nil as MeetingRecurrence?)
                            ForEach(MeetingRecurrence.allCases) { Text($0.rawValue).tag($0 as MeetingRecurrence?) }
                        }
                    }
                } header: {
                    editorSectionHeader("會議資訊", icon: "calendar.badge.clock")
                }

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
                        VStack(spacing: 8) {
                            if items.first?.id != item.id { Divider() }
                            HStack {
                                TextField("項目內容", text: $item.content)
                                Button(role: .destructive) { items.removeAll { $0.id == item.id } } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            Picker("負責人", selection: $item.assigneeId) {
                                Text("未指定").tag(nil as UUID?)
                                ForEach(allSubordinates) { s in Text(s.name).tag(s.id as UUID?) }
                            }
                            Toggle("設定截止時間", isOn: Binding(
                                get: { item.dueDate != nil },
                                set: { $item.wrappedValue.dueDate = $0 ? (item.dueDate ?? FiveMinuteDateTimePicker.defaultSchedulingTime()) : nil }
                            ))
                            if item.dueDate != nil {
                                DatePicker("截止", selection: Binding(
                                    get: { item.dueDate ?? Date() },
                                    set: { $item.wrappedValue.dueDate = $0 }
                                ), displayedComponents: [.date, .hourAndMinute])
                            }
                            Toggle(isOn: Binding(
                                get: { item.isCompleted },
                                set: { newVal in
                                    $item.wrappedValue.isCompleted = newVal
                                    $item.wrappedValue.completedAt = newVal ? (item.completedAt ?? Date()) : nil
                                }
                            )) {
                                Label(item.isCompleted ? "已完成" : "未完成",
                                      systemImage: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isCompleted ? .green : .secondary)
                            }
                        }
                    }
                    Button { items.append(MeetingItem()) } label: {
                        Label("新增項目", systemImage: "plus.circle").foregroundStyle(.indigo)
                    }
                } header: {
                    editorSectionHeader("會議項目", icon: "checklist")
                }

                Section {
                    MentionTextField(text: $note, placeholder: "選填（可打 @ 標註人員）", people: lifeStore.mentionPeople())
                } header: {
                    editorSectionHeader("備註", icon: "note.text", tint: Color(.systemGray2))
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
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let e = editing {
                    topic = e.topic; date = e.date
                    durationText = "\(e.durationMinutes)"
                    if let r = e.recurrence { hasRecurrence = true; recurrence = r }
                    items = e.items; note = e.note
                } else {
                    // 新會議：預設時間用排程時段（整點/半點，過 18:00 則隔天 09:30）
                    date = FiveMinuteDateTimePicker.defaultSchedulingTime()
                }
            }
        }
    }

    private func save() {
        guard var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
        let meeting = SubordinateMeeting(
            id: editing?.id ?? UUID(),
            topic: topic.trimmingCharacters(in: .whitespaces),
            date: date, durationMinutes: Int(durationText) ?? 60,
            recurrence: hasRecurrence ? recurrence : nil,
            items: items, note: note.trimmingCharacters(in: .whitespaces)
        )
        if let idx = sub.meetings.firstIndex(where: { $0.id == meeting.id }) { sub.meetings[idx] = meeting }
        else { sub.meetings.append(meeting) }
        lifeStore.update(sub); dismiss()
    }

    private func deleteMeeting() {
        guard let e = editing, var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
        sub.meetings.removeAll { $0.id == e.id }
        lifeStore.update(sub); dismiss()
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
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty)
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
        // 完成時間：原本未完成→改完成時記下現在；維持完成則沿用舊時間；取消完成則清空
        let completedAt: Date? = isCompleted ? (editing?.completedAt ?? Date()) : nil
        let task = SubordinateTask(
            id: editing?.id ?? UUID(),
            topic: topic.trimmingCharacters(in: .whitespaces),
            content: content.trimmingCharacters(in: .whitespaces),
            date: date, dueDate: hasDueDate ? dueDate : nil,
            note: note.trimmingCharacters(in: .whitespaces),
            isCompleted: isCompleted, completedAt: completedAt
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
        lifeStore.update(target); dismiss()
    }

    private func deleteTask() {
        guard let e = editing, var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
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
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty)
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
        guard var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
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
        guard let e = editing, var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
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
    func mentionPeople() -> [MentionPerson] {
        var out: [MentionPerson] = []
        for s in subordinates where !s.name.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append(MentionPerson(id: s.id, kind: .sub, name: s.name,
                                     subtitle: s.jobTitle.isEmpty ? s.department : s.jobTitle))
        }
        for c in businessCards where !c.name.trimmingCharacters(in: .whitespaces).isEmpty {
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
                for item in m.items { ids.formUnion(MentionText.mentionedIDs(in: item.content, sortedPeople: sortedPeople)) }
                for id in ids { counts[id, default: 0] += 1 }
            }
            for r in s.weeklyReports {
                for id in MentionText.mentionedIDs(in: r.note, sortedPeople: sortedPeople) { counts[id, default: 0] += 1 }
            }
        }
        return counts
    }

    /// 某人被 @ 標註到的項目數
    func mentionedCount(for subId: UUID) -> Int { mentionedCounts()[subId] ?? 0 }
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
                        if p.id != suggestions.last?.id { Divider().padding(.leading, 40) }
                    }
                }
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator).opacity(0.25), lineWidth: 0.75))
            }
        }
    }

    private func row(_ p: MentionPerson) -> some View {
        HStack(spacing: 10) {
            Image(systemName: p.kind == .sub ? "person.fill" : "person.crop.rectangle.stack.fill")
                .font(.system(size: 13)).foregroundStyle(p.kind == .sub ? Color.blue : Color.teal)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                if !p.subtitle.isEmpty {
                    Text(p.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(p.kind == .sub ? "部屬" : "名片")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(p.kind == .sub ? Color.blue : Color.teal)
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

private struct IDBox: Identifiable { let id: UUID }

struct SubordinateItemCard: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    let ref: SubordinateItemRef

    @State private var showEdit = false
    @State private var openSub: Subordinate?
    @State private var openCard: IDBox?

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    cardBody
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("編輯") { showEdit = true }.bold().foregroundStyle(.green) }
            }
            .sheet(isPresented: $showEdit) { editor }
            .sheet(item: $openSub) { s in SubordinateDetailView(subordinate: s) }
            .sheet(item: $openCard) { box in BusinessCardDetailView(cardId: box.id) }
            .environment(\.openURL, OpenURLAction { url in handleMention(url) })
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
            field("任務日期", fmt(t.date))
            if let due = t.dueDate { field("截止日期", fmt(due)) }
            if t.isCompleted, let at = t.completedAt { field("完成時間", fmt(at)) }
            richBlock("內容", t.content)
            richBlock("備註", t.note)
        case .meeting(let subId, let snap):
            let m = lifeStore.subordinates.first { $0.id == subId }?.meetings.first { $0.id == snap.id } ?? snap
            titleBlock(icon: "person.3.fill", color: .indigo, title: m.topic.isEmpty ? "未命名會議" : m.topic)
            field("會議時間", fmt(m.date))
            field("會議長度", "\(m.durationMinutes) 分鐘")
            if !m.items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("議程項目").font(.caption).foregroundStyle(.secondary)
                    ForEach(m.items) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Button {
                                lifeStore.toggleMeetingItemCompletion(subordinateId: subId, meetingId: m.id, itemId: item.id)
                            } label: {
                                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 15)).foregroundStyle(item.isCompleted ? .green : .indigo)
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(MentionText.attributed(item.content.isEmpty ? "未填內容" : item.content, people: people))
                                    .font(.subheadline).tint(.blue)
                                    .strikethrough(item.isCompleted, color: .secondary)
                                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                if let due = item.dueDate {
                                    Label(fmtDue(due), systemImage: "clock")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            if item.isCompleted, let at = item.completedAt {
                                Text(fmtDue(at)).font(.caption2).foregroundStyle(.green)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding().background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            richBlock("備註", m.note)
        case .report(let subId, let snap):
            let r = lifeStore.subordinates.first { $0.id == subId }?.weeklyReports.first { $0.id == snap.id } ?? snap
            titleBlock(icon: "doc.text.fill", color: .purple, title: r.topic.isEmpty ? "未命名報告" : r.topic)
            field("報告日期", fmt(r.date))
            if r.isCompleted, let at = r.completedAt { field("完成時間", fmt(at)) }
            richBlock("備註", r.note)
        case .leave(let subId, let snap):
            let rec = lifeStore.subordinates.first { $0.id == subId }?.records.first { $0.id == snap.id } ?? snap
            titleBlock(icon: "calendar.badge.minus", color: .teal, title: rec.leaveType?.rawValue ?? "請假")
            field("開始", fmt(rec.date))
            if let end = rec.endDate { field("結束", fmt(end)) }
            if let h = rec.leaveHours { field("請假時數", String(format: "%.1f 小時", h)) }
            richBlock("事由", rec.content)
            richBlock("備註", rec.note)
        case .record(let subId, let snap):
            let rec = lifeStore.subordinates.first { $0.id == subId }?.records.first { $0.id == snap.id } ?? snap
            titleBlock(icon: rec.type.icon, color: recordColor(rec.type), title: rec.type.rawValue)
            field("日期", fmt(rec.date))
            if let end = rec.endDate { field("結束", fmt(end)) }
            if let sev = rec.severity { field("嚴重度", sev.rawValue) }
            richBlock("內容", rec.content)
            richBlock("備註", rec.note)
        }
    }

    private func titleBlock(icon: String, color: Color, title: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.08)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 44, height: 44)
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(color)
            }
            Text(title).font(.title3.weight(.bold)).foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
