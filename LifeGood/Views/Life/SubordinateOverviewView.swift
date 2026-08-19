import SwiftUI
import UIKit

// MARK: - 美化紀錄（SubordinateOverviewView）
// [2026-06 v1] 本次美化方向：
//   1. sectionHeader：升級為「漸層 Capsule 左側條 + 彩色圓形圖示圈 + 計數徽章膠囊」，
//      對齊 LifeOverviewView / FinanceChartView.sectionHeader 視覺規格
//   2. 各區塊列（請假 / 會議 / 任務）：改用 36pt 漸層圓形圖示 + 細邊框，
//      加入列間 Divider（.leading 對齊）；標籤膠囊改 Capsule（對齊全域規格）
//   3. emptyHint：從純文字升級為「小型空狀態：40pt 圖示圓 + 主色 + 說明文字」，
//      視覺重量對齊 OverviewView.emptyPlaceholder
//   4. 整體加入交錯淡入 + 向上進場動畫（sectionAppeared），
//      對齊 LifeOverviewView.timelineRowsAppeared 動畫規格
//   5. 三個主區塊（請假 / 會議 / 任務）最外層加 shadow + 極細 overlay 邊框，
//      提升深色模式下的邊界感與層次，對齊 OverviewView categoryBreakdownSection
// [2026-06 v2] 本次美化方向：
//   6. summaryHeroCard：日期選取器上方新增藍綠漸層英雄卡，顯示部屬總人數 +
//      今日請假 / 今日會議 / 待辦任務三格 KPI；三顆散景裝飾圓 + 頂部玻璃光澤
//      （white.opacity(0.18)），對齊 SubordinateView.summaryStatsCard /
//      VariableExpenseView.monthSummaryHeader 英雄卡規格；
//      heroAppeared spring 進場動畫（透明度 + Y 位移 16pt），段落進場延遲 0.10s
//   7. 時間標籤 Capsule 升級：leaveRow / meetingRow / taskRow 中裸 clock + 時間文字
//      升級為 tertiarySystemFill 底色 Capsule 徽章，
//      對齊 CareerView v2 / OverviewView.recentRow 日期 Capsule 設計語言
//   8. 彩色膠囊補細邊框：leaveType / 會議時長 / 截止日 / 部屬姓名膠囊補
//      Capsule().stroke(color.opacity(0.22), lineWidth:0.6)，
//      對齊全 App 膠囊描邊規格（BusinessCardView v2 / StockDetailView v2）
//   9. 雙層 shadow 升級：各卡片由單層 black.opacity(0.06) 升級為雙層
//      （色調主光暈 + 黑底基礎陰影），提升立體感，
//      對齊 SubordinateDetailView.headerCard / FamilyMembersResumeView v2 規格
// [2026-06 v3] 本次美化方向：
//  10. heroKpiCell 補圖示圓：icon 參數原未渲染，補 28pt LinearGradient 白色半透明
//      圖示圓（white.opacity(0.20)）+ 圖示，讓每格 KPI 有視覺錨點，
//      對齊 vehicleKpiCell（VehicleDetailView）/ statsStrip（FamilyView）設計規格；
//      KPI 分隔線高度由 36 升為 48 以配合新高度
//  11. summaryHeroCard 散景圓升級：右上主圓由 90pt/opacity 0.10 升至
//      140pt/opacity 0.13，對齊全 App 三顆散景標準規格（140/90/55 pt）
//  12. summaryHeroCard「共 N 人」徽章：補
//      .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 0.75))，
//      對齊全 App Capsule 計數徽章細邊框規格
//  13. summaryHeroCard shadow 強化：主色光暈 opacity 由 0.30 升至 0.38，
//      對齊 SubordinateDetailView.headerCard / MyCalendarView.calendarHeroCard 規格
//  14. leaveRow / meetingRow 圖示圓：補
//      .shadow(color: color.opacity(0.18), radius: 5, x: 0, y: 2)，
//      對齊 SubordinateDetailView.recordRow / meetingSection 規格
//  15. meetingItemOverviewRow / reportRow 切換按鈕：從裸 circle 圖示
//      升級為 36pt LinearGradient 漸層圓 ZStack，
//      對齊 taskRow / SubordinateDetailView.weeklyReportSection 視覺規格
// [2026-08 v4] 承接 v3 遺留缺口，taskRow 圖示圓補齊陰影統一：
//  16. taskRow 打勾圖示圓（36pt 漸層 Circle）複查後發現是本檔案四個列元件
//      （leaveRow / meetingRow / reportRow / meetingItemOverviewRow）中唯一
//      沒有 .shadow(color: accent.opacity(0.18), radius: 5, x: 0, y: 2) 的一個，
//      補齊後四列圖示圓陰影節奏完全統一。純視覺層調整，toggleTaskCompletion
//      等既有邏輯完全未變動。
//   （本檔案四個列元件圖示圓的 fill + stroke + shadow 節奏已全數收斂一致；
//    下次美化本檔案時可轉往其他仍留有待辦的畫面）

struct SubordinateOverviewView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @State private var selectedDate = Date()
    @State private var heroAppeared = false
    @State private var sectionAppeared = false
    @State private var showCompleted = false
    @State private var editTarget: OverviewEditTarget?
    @State private var addPersonalKind: PersonalEventKind?   // 新增我的會議 / 事務
    @State private var subAddKind: SubAddKind?               // 新增部屬任務 / 會議 / 報告
    @State private var sharePayload: OverviewSharePayload?   // 文字匯出分享
    /// 暫時只看某位部屬（點項目上的人名膠囊設定；點 ✕ 或再點同一人取消）。
    /// 刻意用 @State 不落地：這是「看一眼」的臨時篩選，關掉頁面就重置。
    @State private var filterPersonId: UUID?

    /// 點擊總覽項目要開啟的編輯目標
    private enum OverviewEditTarget: Identifiable {
        case leave(subId: UUID, rec: SubordinateRecord)
        case meeting(subId: UUID, meeting: SubordinateMeeting)
        case task(subId: UUID, task: SubordinateTask)
        case report(subId: UUID, report: WeeklyReport)
        var id: String {
            switch self {
            case .leave(_, let r):   return "l_\(r.id.uuidString)"
            case .meeting(_, let m): return "m_\(m.id.uuidString)"
            case .task(_, let t):    return "t_\(t.id.uuidString)"
            case .report(_, let r):  return "r_\(r.id.uuidString)"
            }
        }
        /// 轉為預覽卡片參照
        var itemRef: SubordinateItemRef {
            switch self {
            case .leave(let s, let r):   return .leave(subId: s, rec: r)
            case .meeting(let s, let m): return .meeting(subId: s, meeting: m)
            case .task(let s, let t):    return .task(subId: s, task: t)
            case .report(let s, let r):  return .report(subId: s, report: r)
            }
        }
    }

    private let calendar = Calendar.current

    private func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    // MARK: - 當日請假

    /// 各清單共用的部屬來源：套用「只看某人」篩選
    private var visibleSubordinates: [Subordinate] {
        guard let pid = filterPersonId else { return lifeStore.subordinates }
        return lifeStore.subordinates.filter { $0.id == pid }
    }

    private var todayLeaves: [(sub: Subordinate, rec: SubordinateRecord)] {
        visibleSubordinates.flatMap { sub in
            sub.records
                .filter { $0.type == .leave }
                .filter { rec in
                    let start = rec.date
                    let end = rec.endDate ?? start
                    return selectedDate >= calendar.startOfDay(for: start)
                        && selectedDate < (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? .distantFuture)
                }
                .map { (sub, $0) }
        }
        .sorted { $0.rec.date < $1.rec.date }
    }

    // MARK: - 當日會議

    private var todayMeetings: [(sub: Subordinate, meeting: SubordinateMeeting)] {
        visibleSubordinates.flatMap { sub in
            sub.meetings
                .filter { isSameDay($0.date, selectedDate) }
                .map { (sub, $0) }
        }
        .sorted { $0.meeting.date < $1.meeting.date }
    }

    // MARK: - 報告（本週全部 + 任何未完成 / 逾期）

    /// 報告呈現狀態
    enum ReportStatus { case overdue, thisWeek, pending, done }

    /// 選取日所在的自然週區間 [週起, 下週起)
    private var weekInterval: DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: selectedDate)
            ?? DateInterval(start: calendar.startOfDay(for: selectedDate), duration: 86_400)
    }

    /// 顯示規則：本週的報告（含已完成）+ 任何未完成的報告（含逾期、未來週）
    /// 排序：未完成優先（逾期最前 → 日期舊到新），其後已完成（日期新到舊）
    private var displayedReports: [(sub: Subordinate, report: WeeklyReport, status: ReportStatus)] {
        let wk = weekInterval
        return visibleSubordinates.flatMap { sub in
            sub.weeklyReports.compactMap { r -> (sub: Subordinate, report: WeeklyReport, status: ReportStatus)? in
                let inWeek = wk.contains(r.date)
                if r.isCompleted {
                    return inWeek ? (sub, r, .done) : nil       // 已完成只顯示本週
                }
                if r.date < wk.start { return (sub, r, .overdue) }   // 逾期未完成
                if inWeek            { return (sub, r, .thisWeek) }   // 本週未完成
                return (sub, r, .pending)                            // 未來週、未完成
            }
        }
        .sorted { a, b in
            if a.report.isCompleted != b.report.isCompleted { return !a.report.isCompleted }
            return a.report.isCompleted ? a.report.date > b.report.date
                                        : a.report.date < b.report.date
        }
    }

    // MARK: - 當日任務（進行中或當日到期）

    private var todayTasks: [(sub: Subordinate, task: SubordinateTask)] {
        visibleSubordinates.flatMap { sub in
            sub.tasks
                .filter { t in
                    !t.isCompleted && (
                        isSameDay(t.date, selectedDate)
                        || t.dueDate.map({ isSameDay($0, selectedDate) }) == true
                    )
                }
                .map { (sub, $0) }
        }
        .sorted { $0.task.date < $1.task.date }
    }

    /// 所有部屬、所有日期的「未完成」任務總清單（逾期排最前，再依截止日 / 日期）
    private var incompleteTasks: [(sub: Subordinate, task: SubordinateTask)] {
        visibleSubordinates.flatMap { sub in
            sub.tasks.filter { !$0.isCompleted }.map { (sub, $0) }
        }
        .sorted { a, b in
            let keyA = a.task.dueDate ?? a.task.date
            let keyB = b.task.dueDate ?? b.task.date
            return keyA < keyB
        }
    }

    /// 所有部屬、所有會議的「未完成」議程項目（依會議日期新到舊）
    private var incompleteMeetingItems: [(sub: Subordinate, meeting: SubordinateMeeting, item: MeetingItem)] {
        visibleSubordinates.flatMap { sub in
            sub.meetings.flatMap { m in
                m.allItems.filter { !$0.isCompleted }.map { (sub: sub, meeting: m, item: $0) }
            }
        }
        .sorted { $0.meeting.date > $1.meeting.date }
    }


    var body: some View {
        // body 單次計算，傳入各子區塊，避免各 section 各自重複 flatMap+filter+sort
        // （v25.118 補齊 reports／dayTasks／meetingItems／completedEntries 四項遺漏的同型快取，
        //  原本 reportSection／taskSection／meetingItemsCard 各自獨立呼叫 displayedReports／
        //  todayTasks／incompleteMeetingItems／overviewCompletedEntries，每次 body 重繪都各多跑一次
        //  O(subordinates × records) 全量掃描）
        let leaves    = todayLeaves
        let meetings  = todayMeetings
        let tasks     = incompleteTasks
        let reports   = displayedReports
        let dayTasks  = todayTasks
        let meetingItems = incompleteMeetingItems
        let completedEntries = overviewCompletedEntries
        return NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summaryHeroCard(leaveCnt: leaves.count,
                                    meetCnt:  meetings.count,
                                    taskCnt:  tasks.count)
                        .opacity(heroAppeared ? 1 : 0)
                        .offset(y: heroAppeared ? 0 : 16)
                        .animation(.spring(response: 0.52, dampingFraction: 0.80), value: heroAppeared)

                    MacaronDatePicker(selectedDate: $selectedDate)

                    filterBanner

                    leaveSection(leaves)
                        .opacity(sectionAppeared ? 1 : 0)
                        .offset(y: sectionAppeared ? 0 : 14)
                        .animation(.spring(response: 0.48, dampingFraction: 0.80).delay(0.05), value: sectionAppeared)

                    reportSection(reports)
                        .opacity(sectionAppeared ? 1 : 0)
                        .offset(y: sectionAppeared ? 0 : 14)
                        .animation(.spring(response: 0.48, dampingFraction: 0.80).delay(0.11), value: sectionAppeared)

                    meetingSection(meetings)
                        .opacity(sectionAppeared ? 1 : 0)
                        .offset(y: sectionAppeared ? 0 : 14)
                        .animation(.spring(response: 0.48, dampingFraction: 0.80).delay(0.15), value: sectionAppeared)

                    taskSection(incompleteTasks: tasks, todayTasks: dayTasks,
                                meetingItems: meetingItems, completedEntries: completedEntries)
                        .opacity(sectionAppeared ? 1 : 0)
                        .offset(y: sectionAppeared ? 0 : 14)
                        .animation(.spring(response: 0.48, dampingFraction: 0.80).delay(0.19), value: sectionAppeared)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("部屬總覽")
            .onAppear {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.80)) {
                    heroAppeared = true
                }
                withAnimation(.spring(response: 0.50, dampingFraction: 0.82).delay(0.10)) {
                    sectionAppeared = true
                }
            }
            .onDisappear { heroAppeared = false; sectionAppeared = false }
            .sheet(item: $editTarget) { target in
                // 點項目先顯示預覽卡片（右上角「編輯」才進入編輯）
                SubordinateItemCard(ref: target.itemRef)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        exportMenu
                        addMenu
                    }
                }
            }
            .sheet(item: $sharePayload) { payload in ShareSheet(items: payload.items) }
            .sheet(item: $addPersonalKind) { kind in
                PersonalEventEditor(initialDate: selectedDate, editing: nil, initialKind: kind)
            }
            .sheet(item: $subAddKind) { kind in
                AddSubItemSheet(kind: kind)
            }
        }
    }

    /// 右上角匯出選單：完整文字＋各區塊圖片匯出（使用者指定）
    private var exportMenu: some View {
        Menu {
            Button { exportText() } label: { Label("完整文字", systemImage: "text.alignleft") }
            Section("圖片匯出") {
                Button { exportImage(.hero) } label: { Label("總覽看板", systemImage: "rectangle.on.rectangle") }
                Button { exportImage(.leaves) } label: { Label("請假", systemImage: "calendar.badge.minus") }
                Button { exportImage(.reports) } label: { Label("報告", systemImage: "doc.text.fill") }
                Button { exportImage(.meetings) } label: { Label("會議", systemImage: "person.3.fill") }
                Button { exportImage(.dayTasks) } label: { Label("當日任務", systemImage: "checklist") }
                Button { exportImage(.meetingItems) } label: { Label("未完成會議條目", systemImage: "person.3.sequence.fill") }
                Button { exportImage(.tasks) } label: { Label("未完成任務", systemImage: "tray.full.fill") }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
    }

    /// 右上角「＋」選單：新增我的會議／事務，或部屬任務／會議／報告
    private var addMenu: some View {
        Menu {
            Section("我的行事曆") {
                Button { addPersonalKind = .meeting } label: { Label("新增會議", systemImage: "person.3.fill") }
                Button { addPersonalKind = .task } label: { Label("新增事務", systemImage: "checklist") }
            }
            Section("部屬") {
                Button { subAddKind = .task } label: { Label("新增部屬任務", systemImage: "checklist") }
                Button { subAddKind = .meeting } label: { Label("新增部屬會議", systemImage: "person.3.fill") }
                Button { subAddKind = .report } label: { Label("新增部屬報告", systemImage: "doc.text.fill") }
            }
        } label: {
            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
        }
    }

    // MARK: - 圖片匯出

    /// 圖片匯出的區塊選項
    private enum ExportSection: String {
        case hero = "總覽看板"
        case leaves = "請假"
        case reports = "報告"
        case meetings = "會議"
        case dayTasks = "當日任務"
        case meetingItems = "未完成會議條目"
        case tasks = "未完成任務"
    }

    private static let stampFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmm"; return f
    }()

    /// 把指定區塊渲染成 JPG 並開啟系統分享面板
    /// （對齊 SubordinateDetailView.exportJPG 既有規格：寬 430、scale ≥3、JPG 0.95）。
    /// 內容太長時自動切分成多張（每張最高約 1600pt），一次分享全部檔案——
    /// 單張兩三千 pt 的長圖傳到通訊軟體會被壓到字都糊掉，不如切頁。
    @MainActor
    private func exportImage(_ section: ExportSection) {
        let content = exportImageContent(section)
            .frame(width: 430)
            .padding(.vertical, 20)
            .background(Color(.systemGroupedBackground))
            .environmentObject(lifeStore)
        let renderer = ImageRenderer(content: content)
        renderer.scale = max(UIScreen.main.scale, 3)
        guard let ui = renderer.uiImage else { return }
        let pages = Self.sliceTallImage(ui, maxPageHeightPt: 1600)
        let stamp = Self.stampFmt.string(from: Date())
        var urls: [URL] = []
        for (i, page) in pages.enumerated() {
            guard let data = page.jpegData(compressionQuality: 0.95) else { continue }
            // 多頁才帶頁碼，單頁維持原本的檔名格式
            let suffix = pages.count > 1 ? "_\(i + 1)之\(pages.count)" : ""
            let name = "部屬總覽_\(section.rawValue)_\(stamp)\(suffix).jpg"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            do { try data.write(to: url); urls.append(url) } catch { }
        }
        guard !urls.isEmpty else { return }
        sharePayload = OverviewSharePayload(items: urls)
    }

    /// 長圖切頁：超過 maxPageHeightPt 就依像素座標裁成多張。
    /// 相鄰兩頁重疊 24pt——切線落在一列文字中間時，那行字在下一頁還能完整看到。
    static func sliceTallImage(_ image: UIImage, maxPageHeightPt: CGFloat) -> [UIImage] {
        guard image.size.height > maxPageHeightPt * 1.2, let cg = image.cgImage else { return [image] }
        let scale = image.scale
        let overlapPt: CGFloat = 24
        let pageHeightPx = Int(maxPageHeightPt * scale)
        let overlapPx = Int(overlapPt * scale)
        let totalPx = cg.height
        var pages: [UIImage] = []
        var yPx = 0
        while yPx < totalPx {
            let h = min(pageHeightPx, totalPx - yPx)
            // 最後一小截（不足 1/4 頁）併入前一頁，避免尾頁只有兩行
            if h < pageHeightPx / 4, var last = pages.popLast().flatMap({ $0.cgImage }) {
                let mergedTop = max(0, totalPx - pageHeightPx)
                if let merged = cg.cropping(to: CGRect(x: 0, y: mergedTop,
                                                       width: cg.width,
                                                       height: totalPx - mergedTop)) {
                    last = merged
                }
                pages.append(UIImage(cgImage: last, scale: scale, orientation: image.imageOrientation))
                break
            }
            guard let slice = cg.cropping(to: CGRect(x: 0, y: yPx, width: cg.width, height: h)) else { break }
            pages.append(UIImage(cgImage: slice, scale: scale, orientation: image.imageOrientation))
            if yPx + h >= totalPx { break }
            yPx += pageHeightPx - overlapPx
        }
        return pages.isEmpty ? [image] : pages
    }

    /// 供 ImageRenderer 使用的靜態版面：非看板區塊在頂部附「部屬總覽｜日期」標題列，
    /// 圖片單獨分享時仍看得出日期脈絡（看板本身已含日期資訊則免）
    @ViewBuilder
    private func exportImageContent(_ section: ExportSection) -> some View {
        VStack(spacing: 12) {
            if section != .hero {
                HStack {
                    Text("📊 部屬總覽｜\(Self.shareDateFmt.string(from: selectedDate))")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            switch section {
            case .hero:
                summaryHeroCard(leaveCnt: todayLeaves.count,
                                meetCnt: todayMeetings.count,
                                taskCnt: incompleteTasks.count)
            case .leaves:
                leaveSection(todayLeaves)
            case .reports:
                reportSection(displayedReports)
            case .meetings:
                meetingSection(todayMeetings)
            case .dayTasks:
                taskGroupCard(title: "當日任務", icon: "checklist", color: .cyan,
                              items: todayTasks, emptyText: "當日無任務")
                    .padding(.horizontal)
            case .meetingItems:
                meetingItemsCard(incompleteMeetingItems)
                    .padding(.horizontal)
            case .tasks:
                taskGroupCard(title: "未完成任務", icon: "tray.full.fill", color: .orange,
                              items: incompleteTasks, emptyText: "沒有未完成任務")
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - 文字匯出

    private static let shareDateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d (E)"; return f
    }()
    private static let shareShortFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "M/d"; return f
    }()
    private static let shareTimeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    /// 把部屬總覽（請假／報告／會議／任務，含已完成收合區）組成 Emoji 排版純文字並分享
    /// （對齊部屬卡片 exportText 規格：✅/⬜️ 並列、完成附 🏁、未完成附 ⏰）。
    private func exportText() {
        let divider = "━━━━━━━━━━━━━━"
        var lines: [String] = []
        lines.append("📊 部屬總覽｜\(Self.shareDateFmt.string(from: selectedDate))")
        lines.append(divider)

        // 當日請假
        let leaves = todayLeaves
        lines.append("")
        lines.append("🌴 當日請假（\(leaves.count)）")
        if leaves.isEmpty {
            lines.append("・當日無人請假")
        } else {
            for it in leaves {
                var row = "• \(it.sub.name.isEmpty ? "未命名" : it.sub.name)"
                if let lt = it.rec.leaveType { row += "｜\(lt.rawValue)" }
                if let h = it.rec.leaveHours, h > 0 { row += "｜\(String(format: "%g", h)) 小時" }
                lines.append(row)
            }
        }

        // 報告（本週全部 + 未完成；含已完成，狀態各自標示）
        let reports = displayedReports
        if !reports.isEmpty {
            let done = reports.filter { $0.report.isCompleted }.count
            lines.append("")
            lines.append("📄 報告（\(done)/\(reports.count) 完成）")
            for it in reports {
                let who = it.sub.name.isEmpty ? "未命名" : it.sub.name
                var row = "\(it.report.isCompleted ? "✅" : "⬜️") \(it.report.topic.isEmpty ? "未命名報告" : it.report.topic)"
                if !it.report.reportType.isEmpty { row += "［\(it.report.reportType)］" }
                row += "｜\(who)"
                switch it.status {
                case .overdue: row += "｜⚠️ 逾期 \(Self.shareShortFmt.string(from: it.report.date))"
                case .thisWeek, .pending: row += "｜\(Self.shareShortFmt.string(from: it.report.date))"
                case .done:
                    if let at = it.report.completedAt { row += "｜🏁 \(Self.shareShortFmt.string(from: at))" }
                }
                lines.append(row)
            }
        }

        // 當日會議（議程 ✅/⬜️ 全列，含已完成）
        let meetings = todayMeetings
        lines.append("")
        lines.append("👥 當日會議（\(meetings.count)）")
        if meetings.isEmpty {
            lines.append("・當日無會議")
        } else {
            for it in meetings {
                let doneCnt = it.meeting.allItems.filter(\.isCompleted).count
                var head = "• \(it.meeting.topic.isEmpty ? "未命名會議" : it.meeting.topic)｜\(Self.shareTimeFmt.string(from: it.meeting.date))｜\(it.meeting.durationMinutes) 分鐘"
                if !it.meeting.allItems.isEmpty { head += "｜議程 \(doneCnt)/\(it.meeting.allItems.count)" }
                lines.append(head)
                for item in it.meeting.allItems {
                    var row = "　\(item.isCompleted ? "✅" : "⬜️") \(item.content.isEmpty ? "未填內容" : item.content)"
                    if item.isCompleted, let at = item.completedAt { row += "｜🏁 \(Self.shareShortFmt.string(from: at))" }
                    else if let due = item.dueDate { row += "｜⏰ \(Self.shareShortFmt.string(from: due))" }
                    lines.append(row)
                }
            }
        }

        // 未完成任務（跨所有日期）
        let tasks = incompleteTasks
        if !tasks.isEmpty {
            lines.append("")
            lines.append("📋 未完成任務（\(tasks.count)）")
            for it in tasks {
                let who = it.sub.name.isEmpty ? "未命名" : it.sub.name
                var row = "⬜️ \(it.task.topic.isEmpty ? "未命名任務" : it.task.topic)｜\(who)"
                if let due = it.task.dueDate { row += "｜⏰ 截止 \(Self.shareShortFmt.string(from: due))" }
                lines.append(row)
            }
        }

        // 未完成會議條目（跨所有會議）
        let pendingItems = incompleteMeetingItems
        if !pendingItems.isEmpty {
            lines.append("")
            lines.append("🗂 未完成會議條目（\(pendingItems.count)）")
            for it in pendingItems {
                let who = it.sub.name.isEmpty ? "未命名" : it.sub.name
                var row = "⬜️ \(it.item.content.isEmpty ? "未填內容" : it.item.content)｜\(who)・\(it.meeting.topic.isEmpty ? "會議" : it.meeting.topic)"
                if let due = it.item.dueDate { row += "｜⏰ \(Self.shareShortFmt.string(from: due))" }
                lines.append(row)
            }
        }

        // 已完成（報告 / 會議條目 / 任務，同底部收合卡內容）
        let completed = overviewCompletedEntries.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        if !completed.isEmpty {
            lines.append("")
            lines.append("✅ 已完成（\(completed.count)）")
            for e in completed {
                let emoji: String = {
                    switch e.kind { case .report: return "📄"; case .meeting: return "👥"; case .task: return "📋" }
                }()
                var row = "🏁 "
                if let at = e.completedAt { row += "\(Self.shareShortFmt.string(from: at))｜" }
                row += "\(emoji) \(e.title.isEmpty ? "未命名" : e.title)｜\(e.subtitle)"
                lines.append(row)
            }
        }

        sharePayload = OverviewSharePayload(items: [lines.joined(separator: "\n")])
    }

    // MARK: - 請假

    private func leaveSection(_ leaves: [(sub: Subordinate, rec: SubordinateRecord)]) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("請假", icon: "calendar.badge.minus", color: .teal, count: leaves.count)

            if leaves.isEmpty {
                emptyHint("當日無人請假", icon: "calendar.badge.minus", color: .teal)
            } else {
                ForEach(Array(leaves.enumerated()), id: \.element.rec.id) { idx, item in
                    leaveRow(item.sub, item.rec)

                    if idx < leaves.count - 1 {
                        Divider().padding(.leading, 62)
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
        .shadow(color: Color.teal.opacity(0.12), radius: 10, x: 0, y: 4)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        .padding(.horizontal)
    }

    // MARK: - 報告彙整

    private func reportSection(_ reports: [(sub: Subordinate, report: WeeklyReport, status: ReportStatus)]) -> some View {
        // 已完成移至底部「已完成」收合區，這裡只顯示未完成（逾期/本週/待辦）
        let rows = reports.filter { $0.status != .done }
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("報告（本週 / 待辦）", icon: "doc.text.fill", color: .purple, count: rows.count)

            if rows.isEmpty {
                emptyHint("本週無報告、無待辦報告", icon: "doc.text.fill", color: .purple)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.report.id) { idx, item in
                    reportRow(item.sub, item.report, status: item.status)

                    if idx < rows.count - 1 {
                        Divider().padding(.leading, 62)
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
        .shadow(color: Color.purple.opacity(0.12), radius: 10, x: 0, y: 4)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        .padding(.horizontal)
    }

    /// 狀態標籤文案與顏色
    private func reportStatusBadge(_ status: ReportStatus) -> (text: String, color: Color)? {
        switch status {
        case .overdue:  return ("逾期", .red)
        case .thisWeek: return ("本週", .purple)
        case .pending:  return ("待辦", .orange)
        case .done:     return nil
        }
    }

    private func reportRow(_ sub: Subordinate, _ report: WeeklyReport, status: ReportStatus) -> some View {
        let badge = reportStatusBadge(status)
        let reportAccent: Color = report.isCompleted ? .green : .purple
        return HStack(spacing: 12) {
            // v3：裸 circle 圖示升級為 36pt 漸層圓，對齊 taskRow 視覺規格
            Button {
                lifeStore.toggleWeeklyReportCompletion(subordinateId: sub.id, reportId: report.id)
            } label: {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [reportAccent.opacity(0.22), reportAccent.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 36, height: 36)
                        .shadow(color: reportAccent.opacity(0.18), radius: 5, x: 0, y: 2)
                    Circle()
                        .stroke(reportAccent.opacity(0.22), lineWidth: 1)
                        .frame(width: 36, height: 36)
                    Image(systemName: report.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(reportAccent)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(report.topic.isEmpty ? "未命名報告" : report.topic)
                        .font(.subheadline.weight(.semibold))
                        .strikethrough(report.isCompleted, color: .secondary)
                        .foregroundStyle(report.isCompleted ? .secondary : .primary)
                        .lineLimit(1)
                    if !report.reportType.isEmpty {
                        Text(report.reportType)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.purple.opacity(0.14))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                    if let badge {
                        Text(badge.text)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(badge.color.opacity(0.15))
                            .foregroundStyle(badge.color)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 6) {
                    personChip(sub, tint: .purple)
                    HStack(spacing: 3) {
                        Image(systemName: "calendar").font(.system(size: 8))
                        Text(reportDateText(report.date))
                    }
                    .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill)).clipShape(Capsule())
                    if !report.note.isEmpty {
                        Text(report.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if report.isCompleted {
                    CompletionStamp(completedAt: report.completedAt, due: report.date)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .opacity(report.isCompleted ? 0.7 : 1)
        .contentShape(Rectangle())
        .onTapGesture { editTarget = .report(subId: sub.id, report: report) }
    }

    private static let reportDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d (E)"
        return f
    }()

    private func reportDateText(_ date: Date) -> String {
        Self.reportDateFormatter.string(from: date)
    }

    // MARK: - 會議

    private func meetingSection(_ meetings: [(sub: Subordinate, meeting: SubordinateMeeting)]) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("會議", icon: "person.3.fill", color: .indigo, count: meetings.count)

            if meetings.isEmpty {
                emptyHint("當日無會議", icon: "person.3.fill", color: .indigo)
            } else {
                ForEach(Array(meetings.enumerated()), id: \.element.meeting.id) { idx, item in
                    meetingRow(item.sub, item.meeting)

                    if idx < meetings.count - 1 {
                        Divider().padding(.leading, 62)
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
        .shadow(color: Color.indigo.opacity(0.12), radius: 10, x: 0, y: 4)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        .padding(.horizontal)
    }

    // MARK: - 任務

    private func taskSection(incompleteTasks tasks: [(sub: Subordinate, task: SubordinateTask)],
                              todayTasks: [(sub: Subordinate, task: SubordinateTask)],
                              meetingItems: [(sub: Subordinate, meeting: SubordinateMeeting, item: MeetingItem)],
                              completedEntries: [CompletedEntry]) -> some View {
        VStack(spacing: 16) {
            // 當日任務（選取日期、未完成）
            taskGroupCard(title: "當日任務", icon: "checklist", color: .cyan,
                          items: todayTasks, emptyText: "當日無任務")

            // 未完成會議條目（跨所有部屬 / 會議的未完成議程項目）
            meetingItemsCard(meetingItems)

            // 未完成任務（跨所有日期 / 部屬的待辦總清單，逾期排最前）
            taskGroupCard(title: "未完成任務", icon: "tray.full.fill", color: .orange,
                          items: tasks, emptyText: "沒有未完成任務")

            // 已完成（報告 / 會議項目 / 任務，可收合；無已完成時不顯示）
            CompletedCollapsibleCard(entries: completedEntries, expanded: $showCompleted)
        }
        .padding(.horizontal)
    }

    /// 跨所有部屬的已完成項目（報告 / 會議議程項目 / 任務），供底部收合卡使用
    private var overviewCompletedEntries: [CompletedEntry] {
        var out: [CompletedEntry] = []
        for sub in visibleSubordinates {
            let who = sub.name.isEmpty ? "未命名" : sub.name
            for r in sub.weeklyReports where r.isCompleted {
                out.append(CompletedEntry(id: r.id, kind: .report, title: r.topic,
                                          subtitle: who, completedAt: r.completedAt, due: r.date,
                                          onTap: { editTarget = .report(subId: sub.id, report: r) }))
            }
            for m in sub.meetings {
                for item in m.allItems where item.isCompleted {
                    out.append(CompletedEntry(id: item.id, kind: .meeting, title: item.content,
                                              subtitle: "\(who)・\(m.topic.isEmpty ? "會議" : m.topic)",
                                              completedAt: item.completedAt, due: item.dueDate,
                                              onTap: { editTarget = .meeting(subId: sub.id, meeting: m) }))
                }
            }
            for t in sub.tasks where t.isCompleted {
                out.append(CompletedEntry(id: t.id, kind: .task, title: t.topic,
                                          subtitle: who, completedAt: t.completedAt, due: t.dueDate,
                                          onTap: { editTarget = .task(subId: sub.id, task: t) }))
            }
        }
        return out
    }

    /// 未完成會議條目卡
    private func meetingItemsCard(_ items: [(sub: Subordinate, meeting: SubordinateMeeting, item: MeetingItem)]) -> some View {
        cardWrap {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("未完成會議條目", icon: "person.3.sequence.fill", color: .indigo,
                              count: items.count)
                if items.isEmpty {
                    emptyHint("沒有未完成的會議條目", icon: "person.3.sequence.fill", color: .indigo)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.item.id) { idx, it in
                        meetingItemOverviewRow(it.sub, it.meeting, it.item)
                        if idx < items.count - 1 { Divider().padding(.leading, 62) }
                    }
                }
            }
        }
    }

    private func meetingItemOverviewRow(_ sub: Subordinate, _ meeting: SubordinateMeeting, _ item: MeetingItem) -> some View {
        let itemAccent: Color = item.isCompleted ? .green : .indigo
        return HStack(alignment: .center, spacing: 12) {
            // v3：裸 circle 圖示升級為 36pt 漸層圓，對齊 taskRow / leaveRow 視覺規格
            Button {
                lifeStore.toggleMeetingItemCompletion(subordinateId: sub.id, meetingId: meeting.id, itemId: item.id)
            } label: {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [itemAccent.opacity(0.22), itemAccent.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 36, height: 36)
                        .shadow(color: itemAccent.opacity(0.18), radius: 5, x: 0, y: 2)
                    Circle()
                        .stroke(itemAccent.opacity(0.22), lineWidth: 1)
                        .frame(width: 36, height: 36)
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(itemAccent)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.content.isEmpty ? "未填內容" : item.content)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(meeting.topic.isEmpty ? "未命名會議" : meeting.topic)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.12))
                        .clipShape(Capsule())
                    if let due = item.dueDate {
                        HStack(spacing: 3) {
                            Image(systemName: "flag.fill").font(.system(size: 7, weight: .semibold))
                            Text("截止 \(fmtDateTime(due))")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(due < Date() ? .red : .indigo)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background((due < Date() ? Color.red : Color.indigo).opacity(0.12))
                        .clipShape(Capsule())
                    }
                    personChip(sub)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { editTarget = .meeting(subId: sub.id, meeting: meeting) }
    }

    /// 請假列的姓名是粗體主標不是膠囊，篩選中在旁邊放一顆獨立的 ✕
    private var clearFilterX: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { filterPersonId = nil }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13)).foregroundStyle(.indigo)
        }
        .buttonStyle(.plain)
    }

    /// 人名膠囊：點一下暫時只看這個人，已篩選中顯示 ✕、再點取消。
    /// 全部清單（請假／報告／會議／任務／議程／已完成）共用同一顆。
    private func personChip(_ sub: Subordinate, tint: Color = .secondary) -> some View {
        let active = filterPersonId == sub.id
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                filterPersonId = active ? nil : sub.id
            }
        } label: {
            HStack(spacing: 3) {
                Text(sub.name.isEmpty ? "未命名" : sub.name)
                    .font(.caption2.weight(.semibold))
                if active {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(active ? Color.indigo.opacity(0.15)
                               : (tint == .secondary ? Color(.tertiarySystemFill) : tint.opacity(0.12)))
            .foregroundStyle(active ? Color.indigo : (tint == .secondary ? Color.secondary : tint))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(
                (active ? Color.indigo : tint).opacity(active ? 0.35 : 0.18), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    /// 篩選中橫幅：清單只剩一個人時，最上面要看得出「為什麼別人都不見了」
    private var filterBanner: some View {
        Group {
            if let pid = filterPersonId,
               let sub = lifeStore.subordinates.first(where: { $0.id == pid }) {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 14)).foregroundStyle(.indigo)
                    Text("只看：\(sub.name.isEmpty ? "未命名" : sub.name)")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            filterPersonId = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.indigo.opacity(0.20), lineWidth: 0.6))
                .padding(.horizontal)
            }
        }
    }

    private func taskGroupCard(title: String, icon: String, color: Color,
                               items: [(sub: Subordinate, task: SubordinateTask)],
                               emptyText: String) -> some View {
        cardWrap {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(title, icon: icon, color: color, count: items.count)
                if items.isEmpty {
                    emptyHint(emptyText, icon: icon, color: color)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.task.id) { idx, item in
                        taskRow(item.sub, item.task)
                        if idx < items.count - 1 { Divider().padding(.leading, 62) }
                    }
                }
            }
        }
    }

    /// 任務卡片外框（三個任務分組共用：底色 + 圓角 + 細邊框 + 陰影）
    private func cardWrap<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
            .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    // MARK: - 列元件

    private func leaveRow(_ sub: Subordinate, _ rec: SubordinateRecord) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // v3：補 shadow，對齊 SubordinateDetailView.recordRow / meetingSection 規格
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.teal.opacity(0.22), Color.teal.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .shadow(color: Color.teal.opacity(0.18), radius: 5, x: 0, y: 2)
                Circle()
                    .stroke(Color.teal.opacity(0.22), lineWidth: 1)
                    .frame(width: 36, height: 36)
                Image(systemName: "calendar.badge.minus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.teal)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(sub.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                filterPersonId = filterPersonId == sub.id ? nil : sub.id
                            }
                        }
                    if filterPersonId == sub.id { clearFilterX }
                    if let lt = rec.leaveType {
                        Text(lt.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.teal)
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(Color.teal.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.teal.opacity(0.22), lineWidth: 0.6))
                    }
                    if let h = rec.leaveHours, h > 0 {
                        Text(h.truncatingRemainder(dividingBy: 1) == 0
                             ? "\(Int(h))h" : String(format: "%.1fh", h))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text(fmtTime(rec.date))
                    if let end = rec.endDate {
                        Text("~")
                        Text(fmtTime(end))
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 2.5)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
                if !rec.content.isEmpty {
                    Text(rec.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { editTarget = .leave(subId: sub.id, rec: rec) }
    }

    private func meetingRow(_ sub: Subordinate, _ meeting: SubordinateMeeting) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // v3：補 shadow，對齊 SubordinateDetailView.meetingSection 規格
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.indigo.opacity(0.22), Color.indigo.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .shadow(color: Color.indigo.opacity(0.18), radius: 5, x: 0, y: 2)
                Circle()
                    .stroke(Color.indigo.opacity(0.22), lineWidth: 1)
                    .frame(width: 36, height: 36)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.indigo)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.topic.isEmpty ? "未命名會議" : meeting.topic)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(fmtTime(meeting.date))
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())

                    Text("\(meeting.durationMinutes) 分鐘")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(Color.indigo.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.indigo.opacity(0.22), lineWidth: 0.6))

                    personChip(sub)
                }
                if !meeting.allItems.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(meeting.allItems) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Button {
                                    lifeStore.toggleMeetingItemCompletion(subordinateId: sub.id, meetingId: meeting.id, itemId: item.id)
                                } label: {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 13))
                                        .foregroundStyle(item.isCompleted ? Color.green : Color.indigo.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                                Text(item.content.isEmpty ? "未填內容" : item.content)
                                    .font(.caption2)
                                    .strikethrough(item.isCompleted, color: .secondary)
                                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                    .lineLimit(2)
                            }
                            .opacity(item.isCompleted ? 0.7 : 1)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { editTarget = .meeting(subId: sub.id, meeting: meeting) }
    }

    private func taskRow(_ sub: Subordinate, _ task: SubordinateTask) -> some View {
        let isOverdue = !task.isCompleted && (task.dueDate.map { $0 < Date() } ?? false)
        let taskAccent: Color = task.isCompleted ? .green : (isOverdue ? .red : .cyan)

        return HStack(alignment: .center, spacing: 12) {
            // 可點打勾圓圈：直接切換完成狀態
            Button {
                lifeStore.toggleTaskCompletion(subordinateId: sub.id, taskId: task.id)
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [taskAccent.opacity(0.22), taskAccent.opacity(0.08)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .shadow(color: taskAccent.opacity(0.18), radius: 5, x: 0, y: 2)
                    Circle()
                        .stroke(taskAccent.opacity(0.22), lineWidth: 1)
                        .frame(width: 36, height: 36)
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : (isOverdue ? "exclamationmark.circle.fill" : "circle"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(taskAccent)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(task.topic.isEmpty ? "未命名任務" : task.topic)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .strikethrough(task.isCompleted, color: .secondary)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    personChip(sub)
                }
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(fmtTime(task.date))
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())

                    if let due = task.dueDate {
                        HStack(spacing: 3) {
                            Image(systemName: isOverdue ? "exclamationmark.triangle.fill" : "clock.badge")
                                .font(.system(size: 9, weight: .semibold))
                            Text("截止 \(fmtDateTime(due))")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(isOverdue ? .red : .cyan)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(taskAccent.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(taskAccent.opacity(0.22), lineWidth: 0.6))
                    }
                }
                if !task.content.isEmpty {
                    Text(task.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if task.isCompleted {
                    CompletionStamp(completedAt: task.completedAt, due: task.dueDate)
                }
            }
            Spacer(minLength: 4)
        }
        .opacity(task.isCompleted ? 0.6 : 1)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { editTarget = .task(subId: sub.id, task: task) }
    }

    // MARK: - 英雄摘要卡

    private func summaryHeroCard(leaveCnt: Int, meetCnt: Int, taskCnt: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 標題列
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 36, height: 36)
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("部屬總覽")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("共 \(lifeStore.subordinates.count) 人")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.white.opacity(0.20))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 0.75))
            }

            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(height: 0.5)

            HStack(spacing: 0) {
                HeroKpiCell(label: "今日請假", value: "\(leaveCnt)",
                            icon: "calendar.badge.minus")
                HeroKpiDivider()
                HeroKpiCell(label: "今日會議", value: "\(meetCnt)",
                            icon: "person.3.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "待辦任務", value: "\(taskCnt)",
                            icon: "tray.full.fill")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .heroCardShell(card: .subordinateOverview)
        .padding(.horizontal)
    }


    // MARK: - 輔助元件

    /// 區塊標題列：漸層 Capsule 左條 + 彩色圖示圓 + 計數徽章膠囊
    private func sectionHeader(_ title: String, icon: String, color: Color, count: Int) -> some View {
        HStack(spacing: 10) {
            // 漸層 Capsule 左側條（對齊 LifeOverviewView / OverviewView 規格）
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 18)

            // 彩色圖示圓
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.20), color.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                Circle()
                    .stroke(color.opacity(0.22), lineWidth: 0.75)
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
            }

            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)

            Spacer()

            // 計數徽章膠囊
            Text(count > 0 ? "\(count) 筆" : "無")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(count > 0 ? color : Color(.tertiaryLabel))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(count > 0 ? color.opacity(0.10) : Color(.tertiarySystemFill))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(count > 0 ? color.opacity(0.22) : Color.clear, lineWidth: 0.75)
                )
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 9)
    }

    /// 空狀態提示：小型圖示圓 + 說明文字（對齊 OverviewView.emptyPlaceholder 精簡版）
    private func emptyHint(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Color(.secondaryLabel))
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .padding(.bottom, 2)
    }

    private static let fmtTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let fmtDateTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f
    }()

    private func fmtTime(_ date: Date) -> String {
        Self.fmtTimeFormatter.string(from: date)
    }

    private func fmtDateTime(_ date: Date) -> String {
        Self.fmtDateTimeFormatter.string(from: date)
    }
}

/// 文字匯出分享項目的 Identifiable 包裝（供 .sheet(item:) 使用）
private struct OverviewSharePayload: Identifiable { let id = UUID(); let items: [Any] }
