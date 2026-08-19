import SwiftUI

// MARK: - 部屬「執掌」分頁：設備清單 + PM／警報時間軸
//
// 讓使用者記錄部屬管理的設備、每台設備的預防保養（PM）時間與警報事件，
// 頁面下方以單一時間軸並列 PM（綠）與警報（紅），一眼看出兩者的相關性；
// 警報條目並標示「距該設備上次 PM N 天」輔助判讀。

// MARK: - 美化紀錄（SubordinateEquipmentView）[2026-07]
// 美化方向（對齊 SubordinateRosterView / GradeTitleView 等頁面規格，僅視覺調整，未動業務邏輯）：
//   • 設備清單空狀態：靜態圖示 → 升級為 double-pulse ring（雙圈脈衝動畫），
//     使用 Task + onAppear/onDisappear 取消，避免頁面切換後動畫殘留閃爍
//   • 設備列（equipmentRow）加入 stagger opacity+Y offset 入場動畫，與部門/職等列一致
//   • 時間軸列（timelineRow）同步加入 stagger 入場動畫
//   • 設備名稱／時間軸設備名稱文字補 lineLimit(1)+minimumScaleFactor，避免長名稱在大字級下截斷或爆版
//   • EquipmentEditorSheet 的 PM／警報空狀態提示補上圖示錨點（對齊 GradeTitleView noCandidatesHint 規格）
// [2026-07 v2] EquipmentEditorSheet 補齊 PM／警報清單項目新增/刪除時的過場動畫：
//   • 新增：Button 內的 append 包入 withAnimation(.spring(response:0.42, dampingFraction:0.78))；
//     刪除：removeAll 同款包入，並在每筆 row 的 VStack 補上
//     .transition(.opacity.combined(with: .move(edge: .top)))（對齊 AddExpenseView／
//     ResumeGiftSection 既有清單新增/刪除過場規格），避免項目瞬間跳出/消失。
//   純視覺調整，PM／警報記錄的儲存、排序（依日期新到舊）、刪除設備等既有商業邏輯完全未變動。
// [2026-07 v3] equipmentRow 的「PM N／警報 N」數量標籤，補齊統一膠囊徽章樣式：
//   • 原本是無底色裸 Label，與同一列「30天內 N 次」徽章及 TravelMapView.spotRow「造訪 N 次」
//     既有膠囊規格（padding+background opacity+clipShape(Capsule)）不一致；
//     統一補上膠囊底色，警報為 0 時改用中性 Color(.tertiarySystemFill) 避免誤讀為異常。
//   純視覺調整，PM／警報筆數計算與顯示條件完全未變動。
// [2026-07 v4] 補齊 v3 留下的待辦：SubordinateEquipmentTimelineSection.timelineRow 左側
//   22pt 節點圖示原本只是單層 fill(color.opacity(0.15)) 純色圓，與 equipmentRow（36pt）／
//   TravelMapView.spotRow（44pt）等錨點圖示既有的「LinearGradient 漸層 + Circle().stroke
//   外框」規格不一致。改為同款漸層（topLeading→bottomTrailing，0.22→0.09）+
//   Circle().stroke(color.opacity(0.28), lineWidth: 0.75)，小尺寸邊框寬度比照
//   spotRow 44pt 規格而非 equipmentRow 36pt 的 1pt，避免小圓上邊框顯得過粗。
//   純視覺調整，PM／警報時間軸排序、天數計算等既有商業邏輯完全未變動。
//   （本檔案設備清單空狀態、equipmentRow、timelineRow 進場動畫、PM／警報膠囊徽章與
//   節點圖示規格至此已全數收斂一致）
// [2026-08 v5] EquipmentEditorSheet 工具列「儲存／新增」按鈕補齊載入狀態：
//   • save()／deleteEquipment() 皆自帶 isSaving 忙碌守衛（guard !isSaving + disabled(isSaving)）
//     避免快速連點造成重複寫入，但按鈕本身在存檔期間毫無視覺提示，與全 App「Add*View 儲存按鈕
//     載入狀態」系列（AddExpenseView／AddIncomeView／AddVehicleView／AddStockView／
//     AddRealEstateView／AddSavingsInsuranceView，v25.81～v25.91）已收斂一致的規格脫節。
//   • 補上 ProgressView().scaleEffect(0.7).tint(.green)，isSaving 為 true 時顯示於按鈕左側，
//     對齊上述系列既有做法。純視覺層調整，save()／deleteEquipment() 內部守衛判斷與設備／
//     PM／警報寫回 lifeStore 等既有商業邏輯完全未變動。
//   （下次美化本檔案時：可轉往其他仍留有待辦的畫面。另全 App 仍有多處編輯 Sheet 帶 isSaving
//   忙碌守衛卻同樣缺此載入視覺——FamilyMembersResumeView／SubordinateView／GradeTitleView／
//   OrganizationView／SubordinateDetailView／MyCalendarView／LifeFinanceView／ResumeView／
//   ChildDetailView，可作為下次美化比照本次補齊的清單，逐步達成全 App 均值性。）

// MARK: 設備清單章節

struct SubordinateEquipmentSection: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    let subordinateId: UUID

    @State private var addingEquipment = false
    @State private var editingEquipment: ManagedEquipment?
    @State private var pickingExisting = false
    @State private var showPremiumAlert = false
    @State private var rowsAppeared = false
    @State private var rowsAppearedTask: Task<Void, Never>?
    @State private var emptyIconPulse = false
    @State private var emptyPulseTask: Task<Void, Never>?

    private let accent = Color.teal

    private var subordinate: Subordinate {
        lifeStore.subordinates.first { $0.id == subordinateId } ?? Subordinate(name: "")
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d"; return f
    }()

    var body: some View {
        // 機台存放於共用機台池（機台屬於部門、生老病死跟著機台）；
        // 這裡只列出「這位部屬目前擔任負責人」的機台
        let equipments = lifeStore.equipmentPool
            .filter { $0.ownerId == subordinateId }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return VStack(alignment: .leading, spacing: 0) {
            // 段落標題（對齊本頁其他章節規格：漸層側條 + 圖示 + 標題 + 計數 + 新增鈕）
            HStack(spacing: 10) {
                Capsule()
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 18)
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(accent)
                Text("執掌設備").font(.subheadline.weight(.semibold))
                if !equipments.isEmpty {
                    Text("\(equipments.count) 台")
                        .font(.caption2.weight(.semibold)).foregroundStyle(accent)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(accent.opacity(0.12)).clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                }
                Spacer()
                Menu {
                    Button {
                        if subscription.isPremium { addingEquipment = true }
                        else { showPremiumAlert = true }
                    } label: {
                        Label("新增機台", systemImage: "plus")
                    }
                    Button {
                        if subscription.isPremium { pickingExisting = true }
                        else { showPremiumAlert = true }
                    } label: {
                        Label("選取現有機台", systemImage: "checklist")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)

            if equipments.isEmpty {
                emptyState
            } else {
                ForEach(Array(equipments.enumerated()), id: \.element.id) { idx, eq in
                    equipmentRow(eq)
                        .opacity(rowsAppeared ? 1 : 0)
                        .offset(y: rowsAppeared ? 0 : 12)
                        .animation(.spring(response: 0.50, dampingFraction: 0.78).delay(0.04 * Double(idx)), value: rowsAppeared)
                    if idx < equipments.count - 1 {
                        Rectangle().fill(Color(.separator).opacity(0.20))
                            .frame(height: 0.5).padding(.leading, 56)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.08), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
        .premiumLockAlert(isPresented: $showPremiumAlert)
        .onAppear {
            rowsAppearedTask?.cancel()
            rowsAppearedTask = Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                rowsAppeared = true
            }
        }
        .onDisappear {
            rowsAppearedTask?.cancel()
            rowsAppeared = false
        }
        .sheet(isPresented: $addingEquipment) {
            EquipmentEditorSheet(editing: nil,
                                 defaultDepartmentId: subordinate.departmentId,
                                 defaultOwnerId: subordinateId)
        }
        .sheet(item: $editingEquipment) { eq in
            // 點開一律先看機台詳情卡片（編輯在卡片右上），與部門所屬設備清單行為一致
            EquipmentDetailCard(equipmentId: eq.id)
        }
        .sheet(isPresented: $pickingExisting) {
            EquipmentClaimPicker(subordinateId: subordinateId)
        }
    }

    // MARK: 空狀態（雙圈脈衝，對齊 SubordinateRosterView 規格）

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.28), lineWidth: 1.5)
                    .frame(width: 62, height: 62)
                    .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                    .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false), value: emptyIconPulse)
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.14), lineWidth: 1)
                    .frame(width: 62, height: 62)
                    .scaleEffect(emptyIconPulse ? 1.62 : 1.0)
                    .animation(.easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false), value: emptyIconPulse)
                Circle()
                    .fill(LinearGradient(colors: [accent.opacity(0.16), accent.opacity(0.06)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(accent.opacity(0.22), lineWidth: 1))
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 20, weight: .light)).foregroundStyle(accent.opacity(0.75))
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
            Text("尚未執掌任何機台").font(.caption).foregroundStyle(.secondary)
            Text("可新增機台，或從部門機台池選取現有機台").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private func equipmentRow(_ eq: ManagedEquipment) -> some View {
        let lastPM = eq.pmRecords.map(\.date).max()
        let recentAlarms = eq.alarms.filter {
            $0.date > (Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date())
        }.count
        Button {
            if subscription.isPremium { editingEquipment = eq }
            else { showPremiumAlert = true }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.09)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                    Circle().stroke(accent.opacity(0.22), lineWidth: 1).frame(width: 36, height: 36)
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(eq.name.isEmpty ? "未命名設備" : eq.name)
                        .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    HStack(spacing: 6) {
                        Label("PM \(eq.pmRecords.count)", systemImage: "wrench.fill")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Color.green.opacity(0.12)).foregroundStyle(.green)
                            .clipShape(Capsule())
                        Label("警報 \(eq.alarms.count)", systemImage: "bell.badge.fill")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(eq.alarms.isEmpty ? Color(.tertiarySystemFill) : Color.red.opacity(0.12))
                            .foregroundStyle(eq.alarms.isEmpty ? Color.secondary : Color.red)
                            .clipShape(Capsule())
                        if recentAlarms > 0 {
                            Text("30天內 \(recentAlarms) 次")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1.5)
                                .background(Color.red.opacity(0.12)).foregroundStyle(.red)
                                .clipShape(Capsule())
                        }
                        if !eq.system.isEmpty {
                            Text(eq.system)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1.5)
                                .background(Color.cyan.opacity(0.12)).foregroundStyle(.cyan)
                                .clipShape(Capsule())
                                .lineLimit(1)
                        }
                        if let deptName = lifeStore.departments.first(where: { $0.id == eq.departmentId })?.name,
                           !deptName.isEmpty {
                            Text(deptName)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1.5)
                                .background(Color.indigo.opacity(0.12)).foregroundStyle(.indigo)
                                .clipShape(Capsule())
                                .lineLimit(1)
                        }
                    }
                    if !eq.note.isEmpty {
                        Text(eq.note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    if let last = lastPM {
                        Text("上次 PM").font(.system(size: 9)).foregroundStyle(.tertiary)
                        Text(Self.dateFmt.string(from: last)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PM／警報時間軸章節

struct SubordinateEquipmentTimelineSection: View {
    @EnvironmentObject var lifeStore: LifeStore
    let subordinateId: UUID

    @State private var rowsAppeared = false
    @State private var rowsAppearedTask: Task<Void, Never>?

    private enum EntryKind { case pm, alarm }
    private struct TimelineEntry: Identifiable {
        let id: UUID
        let kind: EntryKind
        let date: Date
        let equipmentName: String
        let text: String
        /// 警報：距同設備上一次 PM 的天數（無 PM 紀錄則 nil）
        let daysSincePM: Int?
    }

    private var entries: [TimelineEntry] {
        var result: [TimelineEntry] = []
        for eq in lifeStore.equipmentPool where eq.ownerId == subordinateId {
            let name = eq.name.isEmpty ? "未命名設備" : eq.name
            let pmDates = eq.pmRecords.map(\.date).sorted()
            for pm in eq.pmRecords {
                result.append(TimelineEntry(id: pm.id, kind: .pm, date: pm.date,
                                            equipmentName: name, text: pm.note, daysSincePM: nil))
            }
            for al in eq.alarms {
                // 該設備在警報發生前最近的一次 PM（pmDates 已排序，二分搜尋取代線性掃描）
                let prior = Self.lastDate(lessThanOrEqualTo: al.date, in: pmDates)
                let days = prior.flatMap {
                    Calendar.current.dateComponents([.day], from: $0, to: al.date).day
                }
                result.append(TimelineEntry(id: al.id, kind: .alarm, date: al.date,
                                            equipmentName: name, text: al.content, daysSincePM: days))
            }
        }
        return result.sorted { $0.date > $1.date }
    }

    /// 在已遞增排序的 sortedDates 中，二分搜尋「不晚於 date」的最後一筆日期。
    private static func lastDate(lessThanOrEqualTo date: Date, in sortedDates: [Date]) -> Date? {
        var lo = 0, hi = sortedDates.count - 1
        var result: Date? = nil
        while lo <= hi {
            let mid = (lo + hi) / 2
            if sortedDates[mid] <= date {
                result = sortedDates[mid]
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return result
    }

    private static let dateTimeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d HH:mm"; return f
    }()
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d"; return f
    }()
    private func fmt(_ e: TimelineEntry) -> String {
        e.kind == .alarm ? Self.dateTimeFmt.string(from: e.date) : Self.dateFmt.string(from: e.date)
    }

    var body: some View {
        let all = entries
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Capsule()
                        .fill(LinearGradient(colors: [.indigo, Color.indigo.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 4, height: 18)
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.indigo)
                    Text("PM／警報時間軸").font(.subheadline.weight(.semibold))
                    Spacer()
                    // 圖例
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Circle().fill(Color.green).frame(width: 7, height: 7)
                            Text("PM").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 3) {
                            Circle().fill(Color.red).frame(width: 7, height: 7)
                            Text("警報").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

                ForEach(Array(all.enumerated()), id: \.element.id) { idx, e in
                    timelineRow(e, isLast: idx == all.count - 1)
                        .opacity(rowsAppeared ? 1 : 0)
                        .offset(y: rowsAppeared ? 0 : 10)
                        .animation(.spring(response: 0.50, dampingFraction: 0.78).delay(0.03 * Double(idx)), value: rowsAppeared)
                }
                .padding(.bottom, 6)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.indigo.opacity(0.08), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
            .padding(.horizontal)
            .onAppear {
                rowsAppearedTask?.cancel()
                rowsAppearedTask = Task {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard !Task.isCancelled else { return }
                    rowsAppeared = true
                }
            }
            .onDisappear {
                rowsAppearedTask?.cancel()
                rowsAppeared = false
            }
        }
    }

    @ViewBuilder
    private func timelineRow(_ e: TimelineEntry, isLast: Bool) -> some View {
        let color: Color = e.kind == .pm ? .green : .red
        HStack(alignment: .top, spacing: 12) {
            // 左側：節點 + 連接線
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.09)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 22, height: 22)
                    Circle().stroke(color.opacity(0.28), lineWidth: 0.75).frame(width: 22, height: 22)
                    Image(systemName: e.kind == .pm ? "wrench.fill" : "bell.fill")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(color)
                }
                if !isLast {
                    Rectangle().fill(Color(.separator).opacity(0.35))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(e.equipmentName)
                        .font(.caption.weight(.semibold)).foregroundStyle(.primary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(e.kind == .pm ? "PM 保養" : "警報")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(color.opacity(0.12)).foregroundStyle(color)
                        .clipShape(Capsule())
                    if e.kind == .alarm, let days = e.daysSincePM {
                        Text("PM 後 \(days) 天")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Color.orange.opacity(0.12)).foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text(fmt(e)).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                if !e.text.isEmpty {
                    Text(e.text).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(.bottom, isLast ? 4 : 12)
        }
        .padding(.horizontal, 14)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 設備編輯 Sheet

struct EquipmentEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    var editing: ManagedEquipment?
    /// 新增時預帶的所屬部門／負責人（從部門頁開＝該部門；從部屬執掌頁開＝該部屬與其部門）
    var defaultDepartmentId: UUID? = nil
    var defaultOwnerId: UUID? = nil

    @State private var name = ""
    @State private var note = ""
    @State private var system = ""
    @State private var departmentId: UUID?
    @State private var ownerId: UUID?
    @State private var pmRecords: [EquipmentPMRecord] = []
    @State private var alarms: [EquipmentAlarm] = []
    @State private var isSaving = false

    /// 填寫過的系統別膠囊（全機台池去重、依名稱排序、上限 12）
    private var systemSuggestions: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in lifeStore.equipmentPool.map({ $0.system.trimmingCharacters(in: .whitespaces) })
        where !s.isEmpty && !seen.contains(s) {
            seen.insert(s); out.append(s)
        }
        return Array(out.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.prefix(12))
    }

    private var sortedDepartments: [Department] {
        lifeStore.departments.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// 負責人候選：全部部屬，機台所屬部門的成員排最前，其餘依姓名排序
    private var ownerCandidates: [Subordinate] {
        let sorted = lifeStore.subordinates.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        guard let did = departmentId else { return sorted }
        return sorted.filter { $0.departmentId == did } + sorted.filter { $0.departmentId != did }
    }

    /// 統一 Section 標題（對齊 MeetingEditorSheet.editorSectionHeader 規格）
    private func editorSectionHeader(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [tint, tint.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            Text(title).font(.subheadline.weight(.bold))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("設備名稱（如：CVD-01）", text: $name)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("系統別（如：CDA、冰水、廢水，選填）", text: $system)
                        // 填過的系統別變膠囊：點一下帶入、再點取消（比照重大決議廠區）
                        if !systemSuggestions.isEmpty {
                            FlexibleChipWrap(items: systemSuggestions) { s in
                                systemChip(s)
                            }
                            .padding(.bottom, 2)
                        }
                    }
                    TextField("備註（位置、型號等，選填）", text: $note)
                    Picker("所屬部門", selection: $departmentId) {
                        Text("未指定").tag(UUID?.none)
                        ForEach(sortedDepartments) { d in
                            Text(d.name.isEmpty ? "未命名部門" : d.name).tag(UUID?.some(d.id))
                        }
                    }
                    Picker("負責人", selection: $ownerId) {
                        Text("未指派").tag(UUID?.none)
                        ForEach(ownerCandidates) { s in
                            Text(s.name.isEmpty ? "未命名" : s.name).tag(UUID?.some(s.id))
                        }
                    }
                } header: {
                    editorSectionHeader("設備資訊", icon: "gearshape.2.fill", tint: .teal)
                } footer: {
                    Text("機台屬於部門；PM／警報等歷史記錄跟著機台，換負責人不會搬動記錄。")
                }

                Section {
                    if pmRecords.isEmpty {
                        HStack(spacing: 6) {
                            Spacer()
                            Image(systemName: "wrench").font(.caption).foregroundStyle(.tertiary)
                            Text("尚未新增 PM 記錄").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    ForEach($pmRecords) { $pm in
                        VStack(spacing: 6) {
                            if pmRecords.first?.id != pm.id { Divider() }
                            HStack {
                                DatePicker("保養日期", selection: $pm.date, displayedComponents: .date)
                                Button(role: .destructive) {
                                    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                                        pmRecords.removeAll { $0.id == pm.id }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            TextField("保養內容（選填）", text: $pm.note)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Button {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                            pmRecords.append(EquipmentPMRecord())
                        }
                    } label: {
                        Label("新增 PM 記錄", systemImage: "plus.circle").foregroundStyle(.green)
                    }
                } header: {
                    editorSectionHeader("預防保養（PM）", icon: "wrench.fill", tint: .green)
                }

                Section {
                    if alarms.isEmpty {
                        HStack(spacing: 6) {
                            Spacer()
                            Image(systemName: "bell.slash").font(.caption).foregroundStyle(.tertiary)
                            Text("尚未新增警報").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    ForEach($alarms) { $al in
                        VStack(spacing: 6) {
                            if alarms.first?.id != al.id { Divider() }
                            HStack {
                                DatePicker("發生時間", selection: $al.date, displayedComponents: [.date, .hourAndMinute])
                                Button(role: .destructive) {
                                    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                                        alarms.removeAll { $0.id == al.id }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            TextField("警報內容（如：高溫警報、壓力異常）", text: $al.content)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Button {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                            alarms.append(EquipmentAlarm())
                        }
                    } label: {
                        Label("新增警報", systemImage: "plus.circle").foregroundStyle(.red)
                    }
                } header: {
                    editorSectionHeader("警報記錄", icon: "bell.badge.fill", tint: .red)
                } footer: {
                    Text("機台有負責人時，新增的警報會自動掛到負責人的任務欄位（預設 3 天內處理，可再調整截止時間，並需回報處理措施與回復結果）。")
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) { deleteEquipment() } label: {
                            Label("刪除此設備", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯設備" : "新增設備")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 6) {
                        // [美化 v25.92] 存檔中顯示同色 ProgressView，對齊 AddIncomeView／AddExpenseView／
                        // AddVehicleView／AddStockView／AddRealEstateView 儲存按鈕載入狀態規格
                        if isSaving {
                            ProgressView().scaleEffect(0.7).tint(.green)
                        }
                        Button(editing != nil ? "儲存" : "新增") { save() }
                            .bold().foregroundStyle(.green)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    }
                }
            }
            .onAppear {
                if let e = editing {
                    name = e.name; note = e.note; system = e.system
                    departmentId = e.departmentId; ownerId = e.ownerId
                    pmRecords = e.pmRecords.sorted { $0.date > $1.date }
                    alarms = e.alarms.sorted { $0.date > $1.date }
                } else {
                    departmentId = defaultDepartmentId
                    ownerId = defaultOwnerId
                }
            }
        }
    }

    /// 系統別膠囊：點一下帶入輸入框、再點清空
    private func systemChip(_ s: String) -> some View {
        let on = system.trimmingCharacters(in: .whitespaces) == s
        return Button {
            system = on ? "" : s
        } label: {
            Text(s)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(on ? Color.cyan.opacity(0.18) : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(on ? Color.cyan : Color.secondary)
                .overlay(Capsule().stroke(on ? Color.cyan.opacity(0.4) : .clear, lineWidth: 1))
        }
        .buttonStyle(.borderless)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        let eq = ManagedEquipment(
            id: editing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            note: note.trimmingCharacters(in: .whitespaces),
            pmRecords: pmRecords,
            alarms: alarms,
            departmentId: departmentId,
            ownerId: ownerId,
            system: system.trimmingCharacters(in: .whitespaces)
        )
        // 這次編輯新加的警報（編輯前不存在的 id）→ 自動掛到負責人的任務欄位
        let previousAlarmIds = Set((editing?.alarms ?? []).map(\.id))
        let newAlarms = alarms.filter { !previousAlarmIds.contains($0.id) }
        lifeStore.upsertEquipment(eq)
        lifeStore.createTasksForNewAlarms(equipment: eq, newAlarms: newAlarms)
        dismiss()
    }

    private func deleteEquipment() {
        guard !isSaving else { return }
        guard let e = editing else { dismiss(); return }
        isSaving = true
        lifeStore.deleteEquipment(id: e.id)
        dismiss()
    }
}

// MARK: - 選取現有機台（部屬執掌頁）

/// 從機台池挑選機台給這位部屬執掌：點一下接手（成為負責人）、再點一下釋回。
/// 直接寫回 store（比照 DeptManagerPicker 立即寫入模式），關閉即生效。
struct EquipmentClaimPicker: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let subordinateId: UUID

    @State private var query = ""

    /// 依部門分組（依部門名排序，未指定部門排最後），組內依機台名排序
    private var grouped: [(deptName: String, items: [ManagedEquipment])] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let pool = lifeStore.equipmentPool
            .filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q)
                || $0.note.localizedCaseInsensitiveContains(q)
                || $0.system.localizedCaseInsensitiveContains(q) }
        var buckets: [UUID?: [ManagedEquipment]] = [:]
        for eq in pool { buckets[eq.departmentId, default: []].append(eq) }
        func deptName(_ id: UUID?) -> String {
            guard let id, let d = lifeStore.departments.first(where: { $0.id == id }) else { return "未指定部門" }
            return d.name.isEmpty ? "未命名部門" : d.name
        }
        return buckets
            .map { (deptName($0.key), $0.value.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                    $0.key == nil) }
            .sorted { a, b in
                if a.2 != b.2 { return !a.2 }   // 未指定部門排最後
                return a.0.localizedStandardCompare(b.0) == .orderedAscending
            }
            .map { (deptName: $0.0, items: $0.1) }
    }

    private func ownerName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        let n = lifeStore.subordinates.first { $0.id == id }?.name ?? ""
        return n.isEmpty ? "未命名" : n
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("搜尋機台名稱／系統別／備註", text: $query)
                }
                if grouped.isEmpty {
                    Section {
                        HStack(spacing: 6) {
                            Spacer()
                            Image(systemName: "gearshape.2").font(.caption).foregroundStyle(.tertiary)
                            Text(query.isEmpty ? "機台池是空的，先在部門頁或執掌頁新增機台" : "找不到符合的機台")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                ForEach(grouped, id: \.deptName) { group in
                    Section(group.deptName) {
                        ForEach(group.items) { eq in
                            claimRow(eq)
                        }
                    }
                }
            }
            .navigationTitle("選取機台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() }.bold() }
            }
        }
    }

    private func claimRow(_ eq: ManagedEquipment) -> some View {
        let mine = eq.ownerId == subordinateId
        return Button {
            // 點選接手／釋回：立即寫回（只改負責人欄位，機台記錄不動）
            lifeStore.assignEquipmentOwner(equipmentId: eq.id, ownerId: mine ? nil : subordinateId)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: mine ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(mine ? Color.teal : Color(.systemGray3))
                VStack(alignment: .leading, spacing: 2) {
                    Text(eq.name.isEmpty ? "未命名設備" : eq.name)
                        .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text("PM \(eq.pmRecords.count)・警報 \(eq.alarms.count)")
                            .font(.caption2).foregroundStyle(.secondary)
                        if !eq.system.isEmpty {
                            Text(eq.system)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1.5)
                                .background(Color.cyan.opacity(0.12)).foregroundStyle(.cyan)
                                .clipShape(Capsule())
                        }
                        if !mine, let owner = ownerName(eq.ownerId) {
                            Text("目前：\(owner)")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1.5)
                                .background(Color.orange.opacity(0.12)).foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 機台詳情卡片

/// 部門所屬設備點開的檢視卡片（非編輯畫面）：
/// 名稱＋系統/部門/負責人膠囊 → 四格 KPI（PM 總數/距上次 PM/警報總數/30 天警報）
/// → 備註 → PM／警報時間軸（警報標示距同機台上次 PM 天數）。右上「編輯」才進編輯表單。
struct EquipmentDetailCard: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let equipmentId: UUID

    @State private var showEditor = false

    private var equipment: ManagedEquipment? {
        lifeStore.equipmentPool.first { $0.id == equipmentId }
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d"; return f
    }()
    private static let dateTimeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d HH:mm"; return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if let eq = equipment {
                    ScrollView {
                        VStack(spacing: 14) {
                            heroCard(eq)
                            kpiRow(eq)
                            if !eq.note.isEmpty { noteCard(eq) }
                            timelineCard(eq)
                        }
                        .padding(.vertical)
                    }
                } else {
                    // 機台已被刪除（例如編輯表單裡刪除）→ 自動關閉卡片
                    Color.clear.onAppear { dismiss() }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("機台詳情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("編輯") { showEditor = true }.bold()
                }
            }
            .sheet(isPresented: $showEditor) {
                if let eq = equipment {
                    EquipmentEditorSheet(editing: eq)
                }
            }
        }
    }

    // MARK: 標頭

    private func heroCard(_ eq: ManagedEquipment) -> some View {
        let deptName = lifeStore.departments.first { $0.id == eq.departmentId }?.name
        let ownerName: String? = eq.ownerId.map { oid in
            let n = lifeStore.subordinates.first { $0.id == oid }?.name ?? ""
            return n.isEmpty ? "未命名" : n
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [.teal, .cyan],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 50, height: 50)
                        .shadow(color: Color.teal.opacity(0.30), radius: 6, x: 0, y: 3)
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(eq.name.isEmpty ? "未命名設備" : eq.name)
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    FlexibleChipWrap(items: heroChips(eq, deptName: deptName, ownerName: ownerName)) { chip in
                        Label(chip.text, systemImage: chip.icon)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(chip.color.opacity(0.12))
                            .foregroundStyle(chip.color)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(chip.color.opacity(0.22), lineWidth: 0.6))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.teal.opacity(0.10), radius: 12, x: 0, y: 5)
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        .padding(.horizontal)
    }

    private struct HeroChip: Hashable { let text: String; let icon: String; let colorTag: Int
        var color: Color {
            switch colorTag {
            case 0: return .cyan
            case 1: return .indigo
            case 2: return .purple
            default: return .secondary
            }
        }
    }

    private func heroChips(_ eq: ManagedEquipment, deptName: String?, ownerName: String?) -> [HeroChip] {
        var chips: [HeroChip] = []
        if !eq.system.isEmpty {
            chips.append(HeroChip(text: eq.system, icon: "circle.hexagongrid.fill", colorTag: 0))
        }
        if let deptName, !deptName.isEmpty {
            chips.append(HeroChip(text: deptName, icon: "building.2.fill", colorTag: 1))
        }
        chips.append(ownerName.map { HeroChip(text: "負責人 \($0)", icon: "person.fill", colorTag: 2) }
                     ?? HeroChip(text: "未指派負責人", icon: "person.slash", colorTag: 3))
        return chips
    }

    // MARK: 四格 KPI

    private func kpiRow(_ eq: ManagedEquipment) -> some View {
        let lastPM = eq.pmRecords.map(\.date).max()
        let daysSincePM = lastPM.flatMap {
            Calendar.current.dateComponents([.day], from: $0, to: Date()).day
        }
        let recentAlarms = eq.alarms.filter {
            $0.date > (Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date())
        }.count
        return HStack(spacing: 10) {
            kpiCell(value: "\(eq.pmRecords.count)", label: "PM 總數", color: .green)
            kpiCell(value: daysSincePM.map { "\($0) 天" } ?? "—",
                    label: "距上次 PM", color: (daysSincePM ?? 0) >= 90 ? .orange : .teal)
            kpiCell(value: "\(eq.alarms.count)", label: "警報總數",
                    color: eq.alarms.isEmpty ? .secondary : .red)
            kpiCell(value: "\(recentAlarms)", label: "30天警報",
                    color: recentAlarms == 0 ? .secondary : .red)
        }
        .padding(.horizontal)
    }

    private func kpiCell(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.14), lineWidth: 0.75))
    }

    // MARK: 備註

    private func noteCard(_ eq: ManagedEquipment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(LinearGradient(colors: [Color(.systemGray2), Color(.systemGray2).opacity(0.55)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 16)
                Image(systemName: "note.text")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text("備註").font(.subheadline.weight(.bold))
            }
            Text(eq.note)
                .font(.subheadline).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: 時間軸（PM 綠／警報紅，警報標示距上次 PM 天數）

    private struct CardEntry: Identifiable {
        let id: UUID
        let isPM: Bool
        let date: Date
        let text: String
        let daysSincePM: Int?
    }

    private func entries(_ eq: ManagedEquipment) -> [CardEntry] {
        var out: [CardEntry] = []
        let pmDates = eq.pmRecords.map(\.date).sorted()
        for pm in eq.pmRecords {
            out.append(CardEntry(id: pm.id, isPM: true, date: pm.date, text: pm.note, daysSincePM: nil))
        }
        for al in eq.alarms {
            let prior = pmDates.last(where: { $0 <= al.date })
            let days = prior.flatMap {
                Calendar.current.dateComponents([.day], from: $0, to: al.date).day
            }
            out.append(CardEntry(id: al.id, isPM: false, date: al.date, text: al.content, daysSincePM: days))
        }
        return out.sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private func timelineCard(_ eq: ManagedEquipment) -> some View {
        let all = entries(eq)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(LinearGradient(colors: [.indigo, Color.indigo.opacity(0.55)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 16)
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.indigo)
                Text("PM／警報時間軸").font(.subheadline.weight(.bold))
                Spacer()
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Circle().fill(Color.green).frame(width: 7, height: 7)
                        Text("PM").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 3) {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                        Text("警報").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            if all.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.tertiary)
                    Text("尚無 PM／警報記錄，按右上「編輯」新增")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14).padding(.bottom, 14)
            } else {
                ForEach(Array(all.enumerated()), id: \.element.id) { idx, e in
                    cardTimelineRow(e, isLast: idx == all.count - 1)
                }
                .padding(.bottom, 6)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func cardTimelineRow(_ e: CardEntry, isLast: Bool) -> some View {
        let color: Color = e.isPM ? .green : .red
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.09)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 22, height: 22)
                    Circle().stroke(color.opacity(0.28), lineWidth: 0.75).frame(width: 22, height: 22)
                    Image(systemName: e.isPM ? "wrench.fill" : "bell.fill")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(color)
                }
                if !isLast {
                    Rectangle().fill(Color(.separator).opacity(0.35))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(e.isPM ? "PM 保養" : "警報")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(color.opacity(0.12)).foregroundStyle(color)
                        .clipShape(Capsule())
                    if !e.isPM, let days = e.daysSincePM {
                        Text("PM 後 \(days) 天")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Color.orange.opacity(0.12)).foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text(e.isPM ? Self.dateFmt.string(from: e.date) : Self.dateTimeFmt.string(from: e.date))
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                if !e.text.isEmpty {
                    // 檢視卡片以完整內容為主，不做行數截斷
                    Text(e.text).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, isLast ? 4 : 12)
        }
        .padding(.horizontal, 14)
        .fixedSize(horizontal: false, vertical: true)
    }
}
