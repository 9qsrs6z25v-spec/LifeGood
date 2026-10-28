import SwiftUI

// MARK: - [v25.588] 部屬匯出可選：出圖
//
// 規格：scratchpad/orgmove/export/design.md §3.3（圖片版逐塊示意）、§6.4-3／4／5／15／16；
// 工作清單：scratchpad/orgmove/build/export/brief.md 的 G2。
//
// 主控寫好、各組只呼叫不改簽名的：width、decorate、pageHeader、SubExportSectionTitle、renderPaged、renderSingle。
// G2 寫：render(_:perPage:) 的 items(_:)、SubExportBoardView（出圖專用看板）、各區出圖專用的靜態列。
//
// 出圖專用的列一律是純靜態 View：沒有 Button、沒有 MarqueeText、沒有 @State／onAppear／進場動畫、
// 標題不設 lineLimit（整行折行）——所以 B1（執掌列透明）、B2（長標題變「…」）、B12（＋、鈴鐺、勾選圈、箭頭）不會發生。

enum SubExportImage {
    /// 出圖寬度一律 430pt（收的人多半用手機看；iPad、Mac 也一樣，不跟視窗變寬）
    static let width: CGFloat = 430

    /// 算圖一律淺色（照 VehicleDetailView.exportDecorate）＋補環境物件（缺了 ImageRenderer 會當掉）
    /// ＋固定字級（使用者字放大時圖不會跟著變長）＋膠囊換行（ItemChipBar／ItemRow 的出圖模式）
    /// [v25.588 裁定] 加 @MainActor：appStores() 是 View 的擴充（跟著 View 在主執行緒），呼叫端（renderPaged／renderSingle）
    /// 本來就都在 @MainActor；照 SideRoleView.shareJPG、VehicleDetailView.exportDecorate 的寫法。要退回就刪掉這一行屬性。
    @MainActor
    static func decorate(_ view: AnyView) -> AnyView {
        AnyView(
            view.appStores()
                .environment(\.colorScheme, .light)
                .environment(\.itemRowChipsWrap, true)
                .dynamicTypeSize(.large)
        )
    }

    /// 每頁頂端重複的抬頭：左「👤 王小明・部屬卡片」、右「2026/10/1～10/31」（右邊空字串就不畫）
    /// [v25.588 裁定] @MainActor：呼叫端（render、部屬總覽 teamExportImage）都在 @MainActor；要退回就刪掉這一行屬性。
    @MainActor
    static func pageHeader(title: String, trailing: String) -> AnyView {
        AnyView(SubExportPageHeader(title: title, trailing: trailing))
    }

    /// 共用（卡片、部屬總覽都走這裡）：抬頭＋看板（第 1 張開頭，當第一個 sectionHeader；照股票卡片）＋各區列。
    /// - 有列：PagedImageExporter.exportSections 分頁（每頁重複抬頭、區塊中段換頁重複同一個標題、頁尾頁碼與匯出時間）
    /// - 0 列（只要看板、或勾的全是 0）：exportSections 會回空陣列＝按了沒反應（B3），所以改整張渲染一張
    /// - perPage nil＝〔全部一張〕
    /// - emptyNote：整張一張時看板下面多一行灰字（「（這段期間沒有：成就）」）；分頁時請自己放成最後一個 .sectionHeader
    /// - expected＝應該要有幾張；urls 比它少＝有幾張出不來（exportSections 遇到空白頁會跳過）
    @MainActor
    static func renderPaged(baseName: String, header: AnyView, board: AnyView?,
                            items: [PagedExportItem], perPage: Int?, emptyNote: String? = nil,
                            now: Date = Date()) -> SubExportRenderResult {
        var rows = 0
        for item in items {
            if case .row = item { rows += 1 }
        }
        if rows == 0 {
            let url = renderSingle(baseName: baseName, header: header, board: board, trailingNote: emptyNote, now: now)
            return SubExportRenderResult(urls: url.map { [$0] } ?? [], expected: 1)
        }
        var all: [PagedExportItem] = []
        if let board { all.append(.sectionHeader(board)) }
        all.append(contentsOf: items)
        let per = max(1, perPage ?? rows)
        let expected = SubExportComposer.pageEstimate(rows: rows, perPage: per)
        let urls = PagedImageExporter.exportSections(baseName: baseName, width: width, itemsPerPage: per,
                                                     header: header, items: all,
                                                     decorate: { SubExportImage.decorate($0) })
        return SubExportRenderResult(urls: urls, expected: expected)
    }

    /// 整張一張：抬頭＋看板＋（可選）一行灰字＋頁尾。檔名「部屬卡片_20261028_1020.jpg」（西曆、不放名字）
    @MainActor
    static func renderSingle(baseName: String, header: AnyView, board: AnyView?, trailingNote: String?,
                             now: Date) -> URL? {
        let stamp = "美好人生 · " + SubExportComposer.ymd(now, cal: SubExportComposer.gregorian)
            + " " + SubExportComposer.hm(now, cal: SubExportComposer.gregorian) + " 匯出"
        let page = SubExportSinglePage(header: header, board: board, note: trailingNote, stamp: stamp)
        let renderer = ImageRenderer(content: decorate(AnyView(page)))
        var measured = CGSize.zero
        renderer.render { size, _ in measured = size }
        renderer.scale = ImageExportLimits.safeScale(for: measured)
        guard let ui = renderer.uiImage, !ImageExportLimits.isBlank(ui),
              let data = ui.jpegData(compressionQuality: 0.95) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(SubExportComposer.singleFileName(base: baseName, now: now))
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: 部屬卡片（G2）

    /// 部屬卡片的圖：看板（勾了才有）＋各區＋最後一張的「（這段期間沒有：…）」
    @MainActor
    static func render(_ m: SubExportModel, perPage: Int?) -> SubExportRenderResult {
        let name = m.snapshot.name.isEmpty ? "這位同仁" : m.snapshot.name
        let header = pageHeader(title: "👤 \(name)・部屬卡片", trailing: SubExportComposer.periodCore(m))
        let board: AnyView? = m.options.includeBoard ? AnyView(SubExportBoardView(m: m)) : nil
        let empty = SubExportComposer.emptyBlockLabels(m)
        let note: String? = empty.isEmpty ? nil : "（這段期間沒有：" + empty.joined(separator: "、") + "）"
        return renderPaged(baseName: SubExportComposer.fileBase, header: header, board: board,
                           items: items(m), perPage: perPage, emptyNote: note, now: m.now)
    }

    /// 各區：標題（.sectionHeader）＋列（.row），照 SubExportBlock.allCases 順序；0 列的區塊不畫，
    /// 收成最後一個 .sectionHeader 灰字「（這段期間沒有：…）」。
    /// [v25.588 部屬匯出] G2：字一律取自 model／SubExportComposer 的小函式（不自己寫 DateFormatter，B9）；
    /// .row 的總數一定等於 m.pageRowCount（選項頁「約 N 張」才準）——會議系列 1 列＋每條議程 1 列、
    /// 別人會議的段 1 列＋每條 1 列，別的區塊每筆 1 列。
    @MainActor
    static func items(_ m: SubExportModel) -> [PagedExportItem] {
        var out: [PagedExportItem] = []
        for b in SubExportBlock.allCases where m.isSelected(b) && m.rowCount(b) > 0 {
            out.append(.sectionHeader(AnyView(sectionTitle(b, m))))
            for v in blockRows(b, m) {
                out.append(.row(v))
            }
        }
        let empty = SubExportComposer.emptyBlockLabels(m)
        if !empty.isEmpty {
            let note = "（這段期間沒有：" + empty.joined(separator: "、") + "）"
            out.append(.sectionHeader(AnyView(SubExportEmptyNote(text: note))))
        }
        #if DEBUG
        var rows = 0
        for item in out {
            if case .row = item { rows += 1 }
        }
        assert(rows == m.pageRowCount, "[v25.588] 出圖列數 \(rows) 跟 pageRowCount \(m.pageRowCount) 對不起來")
        #endif
        return out
    }

    // MARK: [v25.588 部屬匯出] 區塊標題的圖示、顏色、右邊膠囊

    /// 區塊的圖示與顏色（照卡片；紀錄類照 SubordinateDetailView.colorFor、SubordinateRecordType.icon）
    static func blockLook(_ b: SubExportBlock) -> (icon: String, color: Color) {
        switch b {
        case .reports: return ("doc.text.fill", .purple)
        case .meetings: return ("person.3.fill", .indigo)
        case .tasks: return ("checklist", .cyan)
        case .mentioned: return ("at", .pink)
        case .sideRoles: return ("person.badge.plus", .indigo)
        case .leaves: return ("calendar.badge.minus", .teal)
        case .completed: return ("checkmark.circle.fill", .green)
        case .history: return ("arrow.up.right.circle.fill", .orange)
        case .proCon: return (SubordinateRecordType.pro.icon, .green)
        case .achievements: return (SubordinateRecordType.achievement.icon, .orange)
        case .improvements: return (SubordinateRecordType.improvement.icon, .blue)
        case .faults: return (SubordinateRecordType.fault.icon, .pink)
        case .missOps: return (SubordinateRecordType.missOperation.icon, .purple)
        case .equipment: return ("wrench.and.screwdriver.fill", .teal)
        case .timeline: return ("clock.arrow.circlepath", .teal)
        case .shifts: return ("calendar", .indigo)
        }
    }

    /// 右邊件數膠囊：「未交 2」「2 個」「未完成 6」「4 筆・36 小時」「2 台」「8 天」
    static func badgeText(_ b: SubExportBlock, _ m: SubExportModel) -> String {
        let n = m.rowCount(b)
        switch b {
        case .reports: return "未交 \(n)"
        case .meetings: return "\(n) 個"
        case .tasks: return "未完成 \(n)"
        case .leaves:
            let h = m.leaveHours
            return h > 0 ? "\(n) 筆・" + SubExportComposer.hoursText(h) : "\(n) 筆"
        case .equipment: return "\(n) 台"
        case .shifts: return "\(m.shiftDays) 天"
        case .sideRoles, .completed: return "\(n)"
        default: return "\(n) 筆"
        }
    }

    @MainActor
    private static func sectionTitle(_ b: SubExportBlock, _ m: SubExportModel) -> SubExportSectionTitle {
        let look = blockLook(b)
        return SubExportSectionTitle(title: b.label, icon: look.icon, color: look.color, badge: badgeText(b, m))
    }

    // MARK: [v25.588 部屬匯出] 各區的列（出圖專用、純靜態）

    @MainActor
    private static func blockRows(_ b: SubExportBlock, _ m: SubExportModel) -> [AnyView] {
        switch b {
        case .reports: return reportRows(m)
        case .meetings: return meetingRows(m)
        case .tasks: return taskRows(m)
        case .mentioned: return mentionRows(m)
        case .sideRoles: return sideRoleRows(m)
        case .leaves: return leaveRows(m)
        case .completed: return completedRows(m)
        case .history: return historyRows(m)
        case .proCon, .achievements, .improvements, .faults, .missOps: return recordRows(b, m)
        case .equipment: return equipmentRows(m)
        case .timeline: return timelineRows(m)
        case .shifts: return shiftRows(m)
        }
    }

    @MainActor
    private static func row(_ lead: SubExportRowLead, _ chips: SubExportChips, _ title: String,
                            details: SubExportDetails = SubExportDetails(), trailing: String = "",
                            indented: Bool = false) -> AnyView {
        AnyView(SubExportRow(lead: lead, chips: chips.list, title: title, details: details.list,
                             trailing: trailing, indented: indented))
    }

    /// 膠囊太長會超出 430pt（ChipFlowLayout 照膠囊的理想寬度擺、不會折行），超過就截掉尾巴。
    /// 只用在膠囊（會議名、機台名、人名清單）；標題、內容一律整行折行、不截。
    private static func clip(_ s: String, _ limit: Int = 26) -> String {
        guard s.count > limit, limit > 1 else { return s }
        return String(s.prefix(limit - 1)) + "…"
    }

    /// 報告：紫色文件圓；〔周報〕〔報告日 10/30（五）〕；題目；備註
    @MainActor
    private static func reportRows(_ m: SubExportModel) -> [AnyView] {
        var out: [AnyView] = []
        for r in m.reports {
            var chips = SubExportChips()
            chips.add(clip(SubExportComposer.trim(r.reportType)), .purple)
            chips.add("報告日 " + SubExportComposer.md(r.date, wd: true, now: m.now, cal: m.calendar))
            var det = SubExportDetails()
            if m.options.includeNotes { det.add("備註", r.note) }
            let title = r.topic.isEmpty ? "未命名報告" : r.topic
            out.append(row(.disc("doc.text.fill", .purple), chips, title, details: det))
        }
        return out
    }

    /// 會議：系列一列（〔每週四 10:00・60 分鐘〕〔下一場 10/29（四）〕、主題）＋每條未完成議程各一列（縮排、空心圓）；
    /// 別人會議的段：一列「別人的會議交給王小明的：製造一課晨會（林志豪）」＋底下各條
    @MainActor
    private static func meetingRows(_ m: SubExportModel) -> [AnyView] {
        let cal = m.calendar
        var out: [AnyView] = []
        for b in m.meetings {
            let mt = b.meeting
            let parts = SubExportComposer.meetingWhenText(b, now: m.now, cal: cal).components(separatedBy: "｜")
            var chips = SubExportChips()
            for (i, p) in parts.enumerated() {
                let color: Color = (i > 0 && b.next != nil) ? .indigo : .secondary
                chips.add(p, color)
            }
            var det = SubExportDetails()
            if m.options.includeNotes { det.add("備註", mt.note) }
            let title = mt.topic.isEmpty ? "未命名會議" : mt.topic
            out.append(row(.disc("person.3.fill", .indigo), chips, title, details: det))
            for ctx in b.openItems {
                let showSession = mt.rule != nil || ctx.occurrenceId != nil
                let session = showSession ? SubExportComposer.sessionText(ctx, now: m.now, cal: cal) : ""
                out.append(agendaRow(ctx.item, session: session, m, showAssignees: true))
            }
        }
        let name = m.snapshot.name.isEmpty ? "這位同仁" : m.snapshot.name
        for g in m.othersAgenda {
            let head = "別人的會議交給\(name)的：\(g.topic)（\(g.ownerName)）"
            out.append(row(.disc("person.3.sequence.fill", .indigo), SubExportChips(), head))
            for x in g.items {
                let session = SubExportComposer.md(x.sessionDate, now: m.now, cal: cal) + " 那場"
                out.append(agendaRow(x.item, session: session, m, showAssignees: false))
            }
        }
        return out
    }

    /// 議程一列：空心圓（只是「未完成」記號，不是按鈕）；〔10/15 那場〕〔截止 11/2（一）〕〔負責 陳怡君〕；內容；備註
    @MainActor
    private static func agendaRow(_ item: MeetingItem, session: String, _ m: SubExportModel,
                                  showAssignees: Bool) -> AnyView {
        var chips = SubExportChips()
        chips.add(session)
        if let due = item.dueDate {
            chips.add("截止 " + SubExportComposer.md(due, wd: true, now: m.now, cal: m.calendar), .orange)
        }
        if showAssignees {
            let who = SubExportComposer.assigneeOthers(item, m.snapshot)
            if !who.isEmpty { chips.add(clip("負責 " + who.joined(separator: "、")), .blue) }
        }
        var det = SubExportDetails()
        if m.options.includeNotes { det.add("備註", item.note) }
        let title = item.content.isEmpty ? "未填內容" : item.content
        return row(.open, chips, title, details: det, indented: true)
    }

    /// 任務：青色清單圓（警報任務鈴鐺、缺失任務紅三角）；〔截止〕或〔立案〕〔機台〕〔系統〕〔🔧 關聯機台〕〔兼任 X〕〔缺失任務〕；
    /// 〔逾期、準時與自訂分〕開著：截止膠囊紅＋〔逾期 8 天〕、〔+5分〕（缺失任務不畫分）；細節攤開、備註
    @MainActor
    private static func taskRows(_ m: SubExportModel) -> [AnyView] {
        let s = m.snapshot, o = m.options, cal = m.calendar
        var out: [AnyView] = []
        for t in m.tasks {
            var chips = SubExportChips()
            let overdue: Int? = o.includeMarks ? SubExportComposer.overdueDays(t, now: m.now, cal: cal) : nil
            if let due = t.dueDate {
                let dueColor: Color = overdue == nil ? .secondary : .red
                chips.add("截止 " + SubExportComposer.md(due, wd: true, now: m.now, cal: cal), dueColor)
                if let n = overdue { chips.add("逾期 \(n) 天", .red) }
            } else {
                chips.add("立案 " + SubExportComposer.md(t.date, now: m.now, cal: cal))
            }
            if let info = SubExportComposer.alarmInfo(t, s) {
                // 機台膠囊照卡片用齒輪（鈴鐺只留在列左邊的圖示圓，膠囊不再放鈴鐺）
                chips.add(clip(info.name), .teal, icon: "gearshape.2.fill")
                chips.add(clip(SubExportComposer.trim(info.system)))
            }
            for id in t.linkedEquipmentIds {
                if let n = s.equipmentNames[id] { chips.add(clip(n), .teal, icon: "wrench.fill") }
            }
            if let side = SubExportComposer.sideRoleName(t, s) {
                chips.add(clip("兼任 " + side), .indigo, icon: "link")
            }
            if t.isDereliction { chips.add("缺失任務", .red) }
            if o.includeMarks, let cs = t.customScore, !t.isDereliction {
                let scoreColor: Color = cs >= 0 ? .green : .red
                chips.add(SubExportComposer.scoreText(cs), scoreColor)
            }
            var det = SubExportDetails()
            if o.taskDetails {
                det.add("內容", t.content)
                det.add("處理措施", t.responseAction)
                det.add("回復結果", t.responseResult)
            }
            if o.includeNotes { det.add("備註", t.note) }
            let title = t.topic.isEmpty ? "未命名任務" : t.topic
            out.append(row(taskLead(t), chips, title, details: det))
        }
        return out
    }

    private static func taskLead(_ t: SubordinateTask) -> SubExportRowLead {
        if t.isDereliction { return .disc("exclamationmark.triangle.fill", .red) }
        if t.equipmentLink != nil { return .disc("bell.fill", .teal) }
        return .disc("checklist", .cyan)
    }

    /// 被標註：粉紅 @ 圓；〔任務〕〔來自 陳怡君〕〔10/21〕；題目（別人的缺失也只寫〔任務〕，快照已處理）
    @MainActor
    private static func mentionRows(_ m: SubExportModel) -> [AnyView] {
        var out: [AnyView] = []
        for x in m.mentioned {
            var chips = SubExportChips()
            chips.add(x.kind, .pink)
            chips.add(clip("來自 " + x.ownerName))
            chips.add(SubExportComposer.md(x.date, now: m.now, cal: m.calendar))
            out.append(row(.disc("at", .pink), chips, x.topic))
        }
        return out
    }

    /// 兼任：靛色圓；〔在任〕或〔卸任〕〔場控・2026/9～12〕；職務名；右邊〔待辦 2/3〕（total 0 不畫）
    @MainActor
    private static func sideRoleRows(_ m: SubExportModel) -> [AnyView] {
        var out: [AnyView] = []
        for x in m.sideRoles {
            var chips = SubExportChips()
            let stateColor: Color = x.isActive ? .indigo : .secondary
            chips.add(x.isActive ? "在任" : "卸任", stateColor)
            let period = SubExportComposer.sideRolePeriod(start: x.start, end: x.end, cal: m.calendar)
            var det = SubExportDetails()
            if x.duty.isEmpty {
                chips.add(period)
            } else if x.duty.count <= 12 {
                chips.add("\(x.duty)・\(period)")
            } else {
                // 職責太長放膠囊會超出去：膠囊只放期間，職責另起一行
                chips.add(period)
                det.add("職責", x.duty)
            }
            let trailing = x.total > 0 ? "待辦 \(x.done)/\(x.total)" : ""
            out.append(row(.disc("person.badge.plus", .indigo), chips, x.name, details: det, trailing: trailing))
        }
        return out
    }

    /// 請假：藍綠日曆圓；〔10/23（五）〕或〔9/30（三）～10/1（四）〕〔還沒到〕；標題「特休 8 小時」（不拿事由當標題）；
    /// 〔事由〕勾了多一行「事由　…」；備註
    @MainActor
    private static func leaveRows(_ m: SubExportModel) -> [AnyView] {
        let cal = m.calendar, o = m.options
        let today = cal.startOfDay(for: m.now)
        var out: [AnyView] = []
        for r in m.leaves {
            var when = SubExportComposer.md(r.date, wd: true, now: m.now, cal: cal)
            if let end = r.endDate, cal.startOfDay(for: end) > cal.startOfDay(for: r.date) {
                when += "～" + SubExportComposer.md(end, wd: true, now: m.now, cal: cal)
            }
            var chips = SubExportChips()
            chips.add(when)
            if cal.startOfDay(for: r.date) > today { chips.add("還沒到", .teal) }
            var det = SubExportDetails()
            if o.leaveReason { det.add("事由", r.content) }
            if o.includeNotes { det.add("備註", r.note) }
            out.append(row(.disc("calendar.badge.minus", .teal), chips, leaveTitle(r), details: det))
        }
        return out
    }

    /// 「特休 8 小時」；沒有假別寫「請假 8 小時」；都沒有寫「請假」
    private static func leaveTitle(_ r: SubordinateRecord) -> String {
        var parts: [String] = [r.leaveType?.rawValue ?? "請假"]
        if let h = r.leaveHours, h > 0 { parts.append(SubExportComposer.hoursText(h)) }
        return parts.joined(separator: " ")
    }

    /// 完成項目：綠色打勾；〔報告・周報〕〔議程・P1 製程檢討會〕〔任務〕〔缺失任務〕；題目；右邊〔完成 10/22 16:05〕（at 空的不畫）；
    /// 〔逾期、準時與自訂分〕開著多〔準時〕〔超前〕〔逾期 3 天〕
    @MainActor
    private static func completedRows(_ m: SubExportModel) -> [AnyView] {
        let cal = m.calendar
        var out: [AnyView] = []
        for c in m.completed {
            var chips = SubExportChips()
            // 右邊有〔完成 …〕膠囊，左欄約 208pt，種類膠囊（議程・會議名）超過 16 字截短
            chips.add(clip(SubExportComposer.completedKindText(c), 16), completedColor(c))
            if m.options.includeMarks, let tm = SubExportComposer.timingText(at: c.at, due: c.due, cal: cal) {
                chips.add(tm, timingColor(tm))
            }
            var trailing = ""
            if let at = c.at {
                trailing = "完成 " + SubExportComposer.md(at, now: m.now, cal: cal) + " " + SubExportComposer.hm(at, cal: cal)
            }
            out.append(row(.done(.green), chips, c.title, trailing: trailing))
        }
        return out
    }

    private static func completedColor(_ c: SubExportModel.CompletedLine) -> Color {
        if c.isDereliction { return .red }
        switch c.kind {
        case .task: return .cyan
        case .agenda: return .indigo
        case .report: return .purple
        }
    }

    private static func timingColor(_ text: String) -> Color {
        if text == "準時" { return .green }
        if text == "超前" { return .blue }
        return .red
    }

    /// 升職歷程：橘色向上圓；「升職　技術員 → 工程師」；〔2025/7/1〕；備註
    @MainActor
    private static func historyRows(_ m: SubExportModel) -> [AnyView] {
        var out: [AnyView] = []
        for h in m.history {
            var chips = SubExportChips()
            chips.add(SubExportComposer.ymd(h.date, cal: m.calendar))
            var det = SubExportDetails()
            if m.options.includeNotes { det.add("備註", h.note) }
            out.append(row(.disc("arrow.up.right.circle.fill", .orange), chips, "\(h.kind)　\(h.text)", details: det))
        }
        return out
    }

    /// 紀錄類（優缺點、成就、改善、缺失紀錄、Miss）：各自顏色圖示；〔優點／缺點〕（優缺點那一區）〔10/15〕〔一般〕（Miss）；內容；備註
    @MainActor
    private static func recordRows(_ b: SubExportBlock, _ m: SubExportModel) -> [AnyView] {
        var out: [AnyView] = []
        for r in m.records[b] ?? [] {
            let color = recordColor(r.type)
            var chips = SubExportChips()
            if b == .proCon { chips.add(r.type == .pro ? "優點" : "缺點", color) }
            chips.add(SubExportComposer.md(r.date, now: m.now, cal: m.calendar))
            if b == .missOps, let sev = r.severity { chips.add(sev.rawValue, severityColor(sev)) }
            var det = SubExportDetails()
            if m.options.includeNotes { det.add("備註", r.note) }
            let title = r.content.isEmpty ? "未填內容" : r.content
            out.append(row(.disc(r.type.icon, color), chips, title, details: det))
        }
        return out
    }

    /// 照 SubordinateDetailView.colorFor
    private static func recordColor(_ t: SubordinateRecordType) -> Color {
        switch t {
        case .pro: return .green
        case .con: return .red
        case .achievement: return .orange
        case .improvement: return .blue
        case .fault: return .pink
        case .missOperation: return .purple
        case .leave: return .teal
        }
    }

    /// 照 SubordinateDetailView.severityColor
    private static func severityColor(_ s: MissOpSeverity) -> Color {
        switch s {
        case .minor: return .yellow
        case .normal: return .orange
        case .severe: return .red
        }
    }

    /// 執掌設備：藍綠扳手圓；〔真空〕〔製造一課〕〔上次 PM 10/13〕；機台名；「這段期間　PM 紀錄 2・警報 1」
    @MainActor
    private static func equipmentRows(_ m: SubExportModel) -> [AnyView] {
        var out: [AnyView] = []
        for x in m.equipment {
            var chips = SubExportChips()
            chips.add(clip(SubExportComposer.trim(x.line.system)))
            chips.add(clip(SubExportComposer.trim(x.line.department)))
            if let last = x.lastPM {
                chips.add("上次 PM " + SubExportComposer.md(last, now: m.now, cal: m.calendar))
            }
            var det = SubExportDetails()
            det.add("這段期間", "PM 紀錄 \(x.pmCount)・警報 \(x.alarmCount)")
            out.append(row(.disc("wrench.and.screwdriver.fill", .teal), chips, x.line.name, details: det))
        }
        return out
    }

    /// PM／警報時間軸：停機（橘暫停）、完成復機（綠播放）、保養（藍綠扳手）、警報（紅三角）；機台名；內容；
    /// 〔10/27 03:12〕（警報有時分）〔PM 後 14 天〕
    @MainActor
    private static func timelineRows(_ m: SubExportModel) -> [AnyView] {
        let cal = m.calendar
        var out: [AnyView] = []
        for x in m.timeline {
            let look = timelineLook(x)
            var chips = SubExportChips()
            chips.add(x.isAlarm ? "警報" : "PM " + x.phase, look.color)
            let day = SubExportComposer.md(x.date, now: m.now, cal: cal)
            if x.isAlarm {
                chips.add(day + " " + SubExportComposer.hm(x.date, cal: cal))
                if let n = x.daysAfterPM { chips.add("PM 後 \(n) 天") }
            } else {
                chips.add(day)
            }
            var det = SubExportDetails()
            det.add("", x.text)
            out.append(row(.disc(look.icon, look.color), chips, x.machine, details: det))
        }
        return out
    }

    private static func timelineLook(_ x: SubExportModel.TimelineLine) -> (icon: String, color: Color) {
        if x.isAlarm { return ("exclamationmark.triangle.fill", .red) }
        switch x.phase {
        case "停機": return ("pause.circle.fill", .orange)
        case "完成復機": return ("play.circle.fill", .green)
        default: return ("wrench.fill", .teal)
        }
    }

    /// 排班：靛色日曆圓；「大夜班 6 天」；〔10/5（一）～10/10（六）〕
    @MainActor
    private static func shiftRows(_ m: SubExportModel) -> [AnyView] {
        let cal = m.calendar
        var out: [AnyView] = []
        for r in m.shiftRuns {
            var when = SubExportComposer.md(r.start, wd: true, now: m.now, cal: cal)
            if r.days > 1 { when += "～" + SubExportComposer.md(r.end, wd: true, now: m.now, cal: cal) }
            var chips = SubExportChips()
            chips.add(when)
            out.append(row(.disc("calendar", .indigo), chips, "\(r.type.rawValue) \(r.days) 天"))
        }
        return out
    }
}

/// 每頁抬頭（主控寫好）
struct SubExportPageHeader: View {
    let title: String
    let trailing: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
    }
}

/// 區塊標題（主控寫好；照 SubordinateOverviewView.exportSectionTitle：4pt 漸層色條＋圖示＋粗字＋右邊件數膠囊）。
/// 放進 .sectionHeader 時不用自己加水平內距（PagedImageExporter 會加 20）
struct SubExportSectionTitle: View {
    let title: String
    let icon: String
    let color: Color
    /// 右邊膠囊的字（「6 筆」「未交 2」「4 筆・36 小時」）；空字串不畫
    let badge: String

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 18)
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.bold))
            Spacer()
            if !badge.isEmpty {
                badgeView
            }
        }
    }

    private var badgeView: some View {
        Text(badge)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.75))
    }
}

/// 整張一張的版面（主控寫好）：寬 430、上下 20、背景 systemGroupedBackground（decorate 會固定淺色）
struct SubExportSinglePage: View {
    let header: AnyView
    let board: AnyView?
    let note: String?
    let stamp: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let b = board {
                b.padding(.horizontal, 20)
            }
            if let n = note, !n.isEmpty {
                Text(n)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
            HStack {
                Spacer()
                Text(stamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
        }
        .frame(width: SubExportImage.width)
        .padding(.vertical, 20)
        .background(Color(.systemGroupedBackground))
    }
}

/// 出圖專用的看板（舊漸層英雄卡；沒有 Button、沒有 MarqueeText、沒有 @State、沒有鈴鐺）。
/// [v25.588 部屬匯出] 照卡片 headerCard 的外觀：縮寫圓、「王小明，3.2年資歷」（一行縮字，不跑馬燈）、
/// 白膠囊（職稱／部門／P1 廠區）、「入職 2023/8/1」（〔生日〕勾了多一顆）；
/// 〔分數〕勾了才有分數三格（至今累計）＋第一列小格（期間內）；最後一排＝這份匯出的件數（≤5 格）＋一行小字。
struct SubExportBoardView: View {
    let m: SubExportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            identityRow
            badgeRow
            scoreSection
            countSection
        }
        .padding(20)
        .heroCardShell(card: .subordinateDetail)
    }

    // MARK: 字（在 body 外組好）

    private var displayName: String {
        m.snapshot.name.isEmpty ? "這位同仁" : m.snapshot.name
    }

    private var initials: String {
        m.snapshot.name.isEmpty ? "—" : String(m.snapshot.name.prefix(2))
    }

    private var nameLine: String {
        SubordinateDetailView.nameWithSeniority(displayName, joinDate: m.snapshot.joinDate, now: m.now)
    }

    private var hasGrade: Bool {
        !SubExportComposer.trim(m.snapshot.gradeTitle).isEmpty
    }

    /// 職稱、部門、「P1 廠區」（空的不畫）。
    /// ChipFlowLayout 照膠囊的理想寬度擺、膠囊裡不折行：名字欄約 280pt，超過 24 字截掉尾巴（文字版照寫全文）
    private var tags: [String] {
        let s = m.snapshot
        var out: [String] = []
        let grade = SubExportComposer.trim(s.gradeTitle)
        if !grade.isEmpty { out.append(Self.clipTag(grade)) }
        let dept = SubExportComposer.trim(s.department)
        if !dept.isEmpty { out.append(Self.clipTag(dept)) }
        if !s.plantArea.isEmpty { out.append(Self.clipTag(s.plantArea + " 廠區")) }
        return out
    }

    private static func clipTag(_ s: String) -> String {
        guard s.count > 24 else { return s }
        return String(s.prefix(23)) + "…"
    }

    private var joinText: String? {
        guard let jd = m.snapshot.joinDate else { return nil }
        return "入職 " + SubExportComposer.ymd(jd, cal: m.calendar)
    }

    /// 只有月日＋星座（年份永遠不出去）；〔生日〕沒勾不畫
    private var birthdayText: String? {
        m.options.boardBirthday ? m.snapshot.birthdayText : nil
    }

    /// 「件數＝這份匯出的筆數（2026/10/1～10/31；還沒做完的照列）」
    private var countNote: String {
        let core = SubExportComposer.periodCore(m)
        if m.rangeStart == nil && m.rangeEnd == nil { return "件數＝這份匯出的筆數（\(core)）" }
        let tail = m.options.openItemsIgnorePeriod ? "；還沒做完的照列" : ""
        return "件數＝這份匯出的筆數（\(core)\(tail)）"
    }

    // MARK: 版面

    private var identityRow: some View {
        HStack(alignment: .center, spacing: 14) {
            initialsDisc
            VStack(alignment: .leading, spacing: 6) {
                Text(nameLine)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                tagRow
            }
            Spacer(minLength: 0)
        }
    }

    private var initialsDisc: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.25))
            Circle()
                .stroke(Color.white.opacity(0.40), lineWidth: 1.5)
            Text(initials)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 54, height: 54)
    }

    @ViewBuilder
    private var tagRow: some View {
        if !tags.isEmpty {
            ChipFlowLayout(spacing: 5) {
                ForEach(Array(tags.enumerated()), id: \.offset) { i, t in
                    SubExportBoardTag(text: t, strong: i == 0 && hasGrade)
                }
            }
        }
    }

    @ViewBuilder
    private var badgeRow: some View {
        if joinText != nil || birthdayText != nil {
            HStack(spacing: 6) {
                if let j = joinText {
                    SubExportBoardBadge(icon: "calendar.badge.clock", text: j)
                }
                if let b = birthdayText {
                    SubExportBoardBadge(icon: "birthday.cake.fill", text: b)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private var scoreSection: some View {
        if m.options.boardScores {
            VStack(spacing: 0) {
                scoreBox
                    .padding(.top, 14)
                Rectangle()
                    .fill(Color.white.opacity(0.20))
                    .frame(height: 0.5)
                    .padding(.vertical, 12)
                SubExportKpiRow(cells: m.boardRecordCells)
            }
        }
    }

    /// 分數三格（至今累計，不跟期間）＋右上小字
    private var scoreBox: some View {
        VStack(spacing: 2) {
            HStack {
                Spacer(minLength: 0)
                Text("至今累計")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(.horizontal, 10)
            HStack(spacing: 0) {
                HeroKpiCell(label: "主動性", value: "\(m.snapshot.scores.proactivity)", icon: "bolt.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "潛力性", value: "\(m.snapshot.scores.potential)", icon: "arrow.up.right.circle.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "綜合", value: "\(m.snapshot.scores.overall)", icon: "star.fill")
            }
        }
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.18), lineWidth: 0.75))
    }

    /// 這份匯出的件數（boardCells 空的＝只要看板，整排不畫）
    @ViewBuilder
    private var countSection: some View {
        if !m.boardCells.isEmpty {
            VStack(spacing: 8) {
                SubExportKpiRow(cells: m.boardCells)
                Text(countNote)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, m.options.boardScores ? 8 : 14)
        }
    }
}

// MARK: - [v25.588 部屬匯出] 看板的小零件（出圖專用，純靜態）

/// 看板的 KPI 一排（HeroKpiCell＋豎分隔線；在 heroCardShell 底下才吃得到卡片樣式）
struct SubExportKpiRow: View {
    let cells: [(label: String, value: Int)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                if i > 0 {
                    HeroKpiDivider()
                }
                HeroKpiCell(label: c.label, value: "\(c.value)", icon: SubExportKpiRow.icon(for: c.label))
            }
        }
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// 小格的圖示（照卡片看板）
    static func icon(for label: String) -> String? {
        switch label {
        case "待辦任務": return "checklist"
        case "會議": return "person.3.fill"
        case "已完成": return "checkmark.circle.fill"
        case "未交報告": return "doc.text.fill"
        case "請假": return "calendar.badge.minus"
        case "被標註": return "at"
        case "兼任": return "person.badge.plus"
        case "執掌": return "wrench.and.screwdriver.fill"
        case "優點": return "hand.thumbsup.fill"
        case "缺點": return "hand.thumbsdown.fill"
        case "成就": return "trophy.fill"
        case "Miss": return "exclamationmark.triangle.fill"
        default: return nil
        }
    }
}

/// 看板的白膠囊（職稱較亮、部門與廠區淡一點；照 headerCard）
struct SubExportBoardTag: View {
    let text: String
    var strong: Bool = false

    private var weight: Font.Weight { strong ? .semibold : .medium }
    private var textColor: Color { Color.white.opacity(strong ? 1.0 : 0.88) }
    private var fillColor: Color { Color.white.opacity(strong ? 0.22 : 0.14) }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: weight))
            .foregroundStyle(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(fillColor)
            .clipShape(Capsule())
    }
}

/// 看板的「入職 2023/8/1」「3/14・雙魚座」膠囊（沒有鈴鐺）
struct SubExportBoardBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(Color.white.opacity(0.88))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.16))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.6))
    }
}

// MARK: - [v25.588 部屬匯出] 出圖專用的列（純靜態：沒有 Button、MarqueeText、@State、onAppear、lineLimit）

/// 列左邊那一個：圖示圓（ItemIconDisc，不給 action）／綠色打勾（完成項目）／空心圓（未完成議程；只是記號，不是按鈕）
enum SubExportRowLead {
    case disc(String, Color)
    case done(Color)
    case open
}

/// 膠囊收集器：空字串不加；id 照順序給（同一列兩顆字一樣的膠囊不會撞 id）
struct SubExportChips {
    private(set) var list: [ItemChip] = []

    mutating func add(_ text: String, _ color: Color = .secondary, icon: String? = nil) {
        guard !text.isEmpty else { return }
        list.append(ItemChip(id: "c\(list.count)", text: text, color: color, icon: icon))
    }
}

/// 標題底下的細節一行：灰色粗字標籤＋內容（「內容　…」「處理措施　…」「備註　…」「事由　…」）；標籤空的只寫內容
struct SubExportDetail: Identifiable {
    let id: Int
    let label: String
    let text: String
}

/// 細節收集器：內容去頭尾空白後是空的就不加
struct SubExportDetails {
    private(set) var list: [SubExportDetail] = []

    mutating func add(_ label: String, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        list.append(SubExportDetail(id: list.count, label: label, text: t))
    }
}

/// 出圖專用的一列。外框（白卡、列間分隔線 leading 58）由 PagedImageExporter 收，列自己不加白底圓角。
/// 版面：左 36pt 圖示圓（14＋36＋8＝58 對齊分隔線）、右邊膠囊（換行排）＋標題（整行折行）＋細節；可選右邊灰膠囊。
struct SubExportRow: View {
    let lead: SubExportRowLead
    let chips: [ItemChip]
    let title: String
    var details: [SubExportDetail] = []
    /// 右邊灰膠囊（「待辦 2/3」「完成 10/22 16:05」）；空字串不畫
    var trailing: String = ""
    /// 議程列：往右縮到分隔線的位置
    var indented: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            leadView
            textColumn
            trailingView
        }
        .padding(.leading, indented ? 44 : 0)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var leadView: some View {
        switch lead {
        case .disc(let icon, let color):
            ItemIconDisc(icon: icon, color: color)
        case .done(let color):
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
        case .open:
            Image(systemName: "circle")
                .font(.system(size: 16))
                .foregroundStyle(Color.secondary.opacity(0.6))
                .padding(.top, 2)
        }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !chips.isEmpty {
                ItemChipBar(chips: chips)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(details) { d in
                SubExportDetailLine(detail: d)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var trailingView: some View {
        if !trailing.isEmpty {
            Text(trailing)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
                .fixedSize()
        }
    }
}

/// 細節一行：「內容　腔體漏率 2.1E-9 超標…」（內容整行折行、不截）
struct SubExportDetailLine: View {
    let detail: SubExportDetail

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if !detail.label.isEmpty {
                Text(detail.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                    .fixedSize()
            }
            Text(detail.text)
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 最後一張多一行灰字「（這段期間沒有：成就）」（§2.10）
struct SubExportEmptyNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
