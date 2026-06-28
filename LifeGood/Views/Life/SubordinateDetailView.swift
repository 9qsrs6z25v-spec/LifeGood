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
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard

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
                                    Text("\(tab == .daily ? subordinate.proactivityScore : subordinate.potentialScore)")
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
        }
    }

    // MARK: - 英雄頭部卡片

    private var headerCard: some View {
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
                            if subscription.isPremium { editingReport = r } else { showPremiumAlert = true }
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
                                      onTap: { if subscription.isPremium { editingReport = r } else { showPremiumAlert = true } }))
        }
        for m in subordinate.meetings {
            for item in m.items where item.isCompleted {
                out.append(CompletedEntry(id: item.id, kind: .meeting, title: item.content,
                                          subtitle: m.topic.isEmpty ? "會議" : m.topic,
                                          completedAt: item.completedAt, due: item.dueDate,
                                          onTap: { if subscription.isPremium { editingMeeting = m } else { showPremiumAlert = true } }))
            }
        }
        for t in subordinate.tasks where t.isCompleted {
            out.append(CompletedEntry(id: t.id, kind: .task, title: t.topic,
                                      subtitle: t.content.isEmpty ? nil : t.content,
                                      completedAt: t.completedAt, due: t.dueDate,
                                      onTap: { if subscription.isPremium { editingTask = t } else { showPremiumAlert = true } }))
        }
        return out
    }

    private var completedSection: some View {
        CompletedCollapsibleCard(entries: completedEntries, expanded: $showCompleted)
            .padding(.horizontal)
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
                        if subscription.isPremium { editingMeeting = m }
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
                Text(formatDate(due))
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
                            if subscription.isPremium { editingTask = t }
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
            if subscription.isPremium { editingRecord = rec }
            else { showPremiumAlert = true }
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

struct RecordEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let subordinateId: UUID
    let type: SubordinateRecordType
    var editing: SubordinateRecord?

    @State private var content = ""
    @State private var date = Date()
    @State private var endDate = Date()
    @State private var note = ""
    @State private var severity: MissOpSeverity = .normal
    @State private var leaveType: LeaveType = .personal

    private var canSave: Bool {
        !content.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var computedLeaveHours: Double {
        max(0, endDate.timeIntervalSince(date) / 3600)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("內容") {
                    TextField(placeholder, text: $content, axis: .vertical).lineLimit(2...5)
                }
                if type == .leave {
                    Section("請假資訊") {
                        Picker("假別", selection: $leaveType) {
                            ForEach(LeaveType.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                    Section("日期") {
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
                        HStack {
                            Text("請假時數").foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f 小時", computedLeaveHours))
                                .foregroundStyle(.teal).bold()
                        }
                    }
                } else {
                    Section("日期") {
                        DatePicker("發生日期", selection: $date, displayedComponents: .date)
                    }
                }
                if type == .missOperation {
                    Section("嚴重度") {
                        Picker("嚴重度", selection: $severity) {
                            ForEach(MissOpSeverity.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section("備註") {
                    TextField("選填", text: $note, axis: .vertical).lineLimit(2...5)
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
            .onAppear { loadEditing() }
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
            // 新請假：預設用排程時段（整點/半點，過 18:00 則隔天 09:30），結束預設 +1 小時
            if type == .leave {
                date = FiveMinuteDateTimePicker.defaultSchedulingTime()
                endDate = Calendar.current.date(byAdding: .hour, value: 1, to: date) ?? date
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

// MARK: - 會議編輯 Sheet

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

    var body: some View {
        NavigationStack {
            Form {
                Section("會議資訊") {
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
                }

                Section {
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
                            DatePicker("截止日", selection: Binding(
                                get: { item.dueDate ?? Date() },
                                set: { $item.wrappedValue.dueDate = $0 }
                            ), displayedComponents: .date)
                        }
                    }
                    Button { items.append(MeetingItem()) } label: {
                        Label("新增項目", systemImage: "plus.circle").foregroundStyle(.indigo)
                    }
                } header: { Text("會議項目") }

                Section("備註") {
                    TextField("選填", text: $note, axis: .vertical).lineLimit(2...5)
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

    var body: some View {
        NavigationStack {
            Form {
                Section("任務資訊") {
                    TextField("任務主題", text: $topic)
                    TextField("任務內容", text: $content, axis: .vertical).lineLimit(2...5)
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
                }
                Section {
                    Toggle(isOn: $isCompleted) {
                        Label("標記為已完成", systemImage: isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isCompleted ? .green : .primary)
                    }
                    .tint(.green)
                }
                Section("備註") {
                    TextField("選填", text: $note, axis: .vertical).lineLimit(2...5)
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
        guard var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
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
        if let idx = sub.tasks.firstIndex(where: { $0.id == task.id }) { sub.tasks[idx] = task }
        else { sub.tasks.append(task) }
        lifeStore.update(sub); dismiss()
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

    var body: some View {
        NavigationStack {
            Form {
                Section("報告") {
                    TextField("報告題目", text: $topic)
                    HStack {
                        Text("日期")
                        Spacer()
                        FiveMinuteDateTimePicker(selection: $date).fixedSize()
                    }
                }
                Section {
                    Toggle(isOn: $isCompleted) {
                        Label("標記為已完成", systemImage: isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isCompleted ? .green : .primary)
                    }
                    .tint(.green)
                }
                Section("備註") {
                    TextField("選填", text: $note, axis: .vertical).lineLimit(2...5)
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
