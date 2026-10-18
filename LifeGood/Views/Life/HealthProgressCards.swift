import SwiftUI

// MARK: - 健康頁：個人紀錄、月曆（健康 v7，v25.557；health/judge.md §3.10、§6 v7「月曆＋請假週」、build/v7/brief.md §G3）
//
// 只屬於 App target（A01C000001000002）。主控建空殼（能編譯的最小樣子），G3 填內容；
// 這兩個型別只有 G3 的 HealthView 用，簽章 G3 可以改（改了 HealthView 那一頭一起改）。
// 字和數字都讀 WorkoutFacts（WorkoutProgress.swift：personalRecords、recordFootnote、monthGrid、calendarMonths、heatLevel）、
// 顏色讀 WorkoutPalette.heat／heatInk；body 不寫長運算式、長修飾器鏈（拆小 view／computed var）。
//
// • HealthRecordsCard（插在每週公里（月曆）和重訓中間）：FinanceCardHeader「個人紀錄」＋白卡，每列
//   「最快 1 公里　5'41"　9/28 ›」（整列是按鈕，點了打開那一趟的成果頁）、列間細線（FinanceInfoRows）、最下面灰字 recordFootnote。
//   資料是 HealthPageData.records（.task 裡算好的），這裡只畫。
// • HealthCalendarCard（每週公里下面）：FinanceCardHeader「月曆」（右邊「10 月・9 趟」）＋白卡：
//   ‹ 2026 年 10 月 ›（第一筆運動那個月到下個月）／一二三四五六日＋週／每週一列 7 格＋最右一格（打勾／葉子／空白，不打叉、不染紅）／
//   下面「連續 6 週（9/7 那週起）」＋圖例「少 ▢▢▢▢▢ 多」。
//   - 每格：圓角 6、底色 WorkoutPalette.heat（五階，一個藍色由淺到深）、日期 heatInk、最多兩個運動小圖示、第三種起「+1」；
//     今天 1.5 外框；不是這個月的 0.35 透明、不能點；以後的日子不上色。
//   - 點一天：一趟直接 onOpen；兩趟以上 confirmationDialog 讓你選（「晨跑 5.2 公里・06:05」）；沒運動不反應。
//   - 長按一週（那一列，含最右邊那格）：「這週請假」／「取消請假」→ onLeave(on, 週一)；過去的週也可以補標（brief §1-9）。
//     VoiceOver 在最右邊那格有同名的動作。
//   - grid 在 .task(id:) 算（refreshKey＝workoutsRevision＋今天，HealthView 給；換月也重算），body 只畫；一個月最多 42＋6 格，不用 Lazy。

// MARK: - 個人紀錄

/// 健康頁「個人紀錄」（插在每週公里和重訓中間）：「最快 1 公里　5'41"　9/28 ›」…；點一列打開那一趟
struct HealthRecordsCard: View {
    let records: [WorkoutRecord]
    let onOpen: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "個人紀錄")
            VStack(alignment: .leading, spacing: 0) {
                FinanceInfoRows(rows: rows)
                Divider().padding(.leading, 14)
                footnote
            }
            .modifier(FinanceCardChrome())
        }
    }

    /// 每一列包好（FinanceInfoRows 收已經包好的畫面）
    private var rows: [FinanceInfoRows.Row] {
        let open = onOpen
        return records.map { r in
            FinanceInfoRows.Row(id: r.id, content: AnyView(HealthRecordLine(record: r, onOpen: open)))
        }
    }

    private var footnote: some View {
        Text(WorkoutFacts.recordFootnote)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }
}

/// 個人紀錄的一列：左「最快 1 公里」、右「5'41"」粗＋「9/28」灰＋ ›；整列是按鈕
private struct HealthRecordLine: View {
    let record: WorkoutRecord
    let onOpen: (UUID) -> Void

    var body: some View {
        Button {
            onOpen(record.sessionId)
        } label: {
            line
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("點兩下看那一趟")
        .accessibilityAddTraits(.isButton)
    }

    private var line: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(record.label)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(record.valueText)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            Text(record.dateText)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    /// VoiceOver：「最快 1 公里，5 分 41 秒，9 月 28 日」「最長，10.2 公里，8 月 23 日」
    private var spoken: String {
        let value = record.kind.smallerIsBetter ? WorkoutFacts.voiceDuration(record.value) : record.valueText
        return record.label + "，" + value + "，" + HealthCalendarSpeech.monthDay(record.date)
    }
}

/// VoiceOver 的日期字（「9 月 28 日」）
private enum HealthCalendarSpeech {
    static func monthDay(_ date: Date) -> String {
        let c = WorkoutFacts.calendar.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0) 月 \(c.day ?? 0) 日"
    }
}

// MARK: - 月曆

/// 點了有兩趟以上的那一天：讓你選哪一趟（confirmationDialog 的資料；每次新的 id）
private struct HealthCalendarPick: Identifiable {
    struct Option: Identifiable {
        let id: UUID
        /// 「晨跑 5.2 公里・06:05」
        let label: String
    }

    let id = UUID()
    /// 「10/15 週四」
    let title: String
    let options: [Option]
}

/// 健康頁「月曆」（每週公里下面）：每天一格的深淺、最右邊一欄打勾／葉子；長按一週請假、取消請假
struct HealthCalendarCard: View {
    let sessions: [WorkoutSession]
    let leave: WorkoutLeaveBook
    /// 什麼時候要重算：HealthView 給「workoutsRevision－今天」（運動、請假一改 workoutsRevision 就加一；過午夜換今天）
    let refreshKey: String
    /// 打開那一趟的成果頁
    let onOpen: (UUID) -> Void
    /// 長按一週：(請假 true／取消 false, 那一週的週一)。HealthView 排到下一輪主執行緒才寫 store
    let onLeave: (Bool, Date) -> Void

    @Environment(\.colorScheme) private var scheme

    /// 能翻到的月（舊到新；.task 算）
    @State private var months: [Date] = []
    /// 使用者翻到的那個月（1 號 00:00）；nil＝這個月（還沒翻過）。存月份不存第幾個：
    /// 補進更早的運動（Apple 健康帶進來）時能翻的月從前面變多，存第幾個會跳到別的月
    @State private var chosenMonth: Date?
    /// 現在畫的是第幾個月（.task 算好；左右箭頭讀它）
    @State private var shownIndex = 0
    /// 現在畫的那個月（.task 算；nil＝還沒算好）
    @State private var grid: WorkoutMonthGrid?
    /// 點了有兩趟以上的那一天
    @State private var pick: HealthCalendarPick?

    init(sessions: [WorkoutSession], leave: WorkoutLeaveBook, refreshKey: String,
         onOpen: @escaping (UUID) -> Void, onLeave: @escaping (Bool, Date) -> Void) {
        self.sessions = sessions
        self.leave = leave
        self.refreshKey = refreshKey
        self.onOpen = onOpen
        self.onLeave = onLeave
    }

    private var pal: TripBoardPalette { TripBoardPalette(scheme) }

    /// 換月、資料一改就重算
    private var taskKey: String {
        refreshKey + "|" + (chosenMonth.map { String(Int($0.timeIntervalSince1970)) } ?? "now")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "月曆", trailing: grid?.trailing)
            cardBody
                .modifier(FinanceCardChrome())
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .task(id: taskKey) { rebuild() }
        .confirmationDialog(pickTitle, isPresented: pickBinding, titleVisibility: .visible, presenting: pick) { p in
            pickButtons(p)
        }
    }

    // MARK: 算（.task 裡；body 只畫）

    private func rebuild() {
        let now = Date()
        let ms = WorkoutFacts.calendarMonths(sessions, now: now)
        if ms != months { months = ms }
        guard !ms.isEmpty else {
            grid = nil
            return
        }
        let thisMonth = WorkoutFacts.monthStart(now)
        let fallback = ms.firstIndex(of: thisMonth) ?? max(0, ms.count - 2)
        // 翻過的那個月還在能翻的範圍就照它；不在了（例：那個月的運動都刪了）回這個月
        let picked = chosenMonth.flatMap { m in ms.firstIndex(of: m) }
        let i = min(max(0, picked ?? fallback), ms.count - 1)
        if i != shownIndex { shownIndex = i }
        let g = WorkoutFacts.monthGrid(sessions, month: ms[i], leave: leave, now: now)
        if g != grid { grid = g }
    }

    private var canGoBack: Bool { shownIndex > 0 }
    private var canGoForward: Bool { shownIndex + 1 < months.count }

    private func goBack() {
        let i = shownIndex - 1
        guard canGoBack, i < months.count else { return }
        chosenMonth = months[i]
    }

    private func goForward() {
        let i = shownIndex + 1
        guard canGoForward, i >= 0 else { return }
        chosenMonth = months[i]
    }

    // MARK: 畫

    @ViewBuilder
    private var cardBody: some View {
        if let g = grid {
            VStack(alignment: .leading, spacing: 8) {
                monthBar(g)
                weekdayRow
                VStack(spacing: 4) {
                    ForEach(g.weeks) { w in
                        weekRow(w)
                    }
                }
                footer(g)
            }
            .padding(12)
        } else {
            Color.clear.frame(height: 300)
        }
    }

    /// ‹ 2026 年 10 月 ›
    private func monthBar(_ g: WorkoutMonthGrid) -> some View {
        HStack(spacing: 8) {
            monthArrow("chevron.left", label: "上個月", enabled: canGoBack) { goBack() }
            Spacer(minLength: 4)
            Text(g.title)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(pal.ink)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            monthArrow("chevron.right", label: "下個月", enabled: canGoForward) { goForward() }
        }
    }

    private func monthArrow(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(enabled ? pal.hint : Color.secondary.opacity(0.4))
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// 一 二 三 四 五 六 日 ＋ 週
    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(Self.weekdayLabels, id: \.self) { w in
                Text(w)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            Text("週")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: Self.markWidth)
        }
        .accessibilityHidden(true)
    }

    private static let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]
    /// 最右邊「週」那一欄的寬
    private static let markWidth: CGFloat = 28

    /// 一週一列：7 格＋最右一格；長按整列（含最右邊那格）請假／取消請假
    private func weekRow(_ w: WorkoutMonthWeek) -> some View {
        HStack(spacing: 4) {
            ForEach(w.days) { d in
                dayCell(d)
            }
            HealthCalendarMarkCell(week: w, pal: pal, onLeave: onLeave)
                .frame(width: Self.markWidth)
        }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contextMenu {
            leaveMenu(w)
        }
    }

    @ViewBuilder
    private func leaveMenu(_ w: WorkoutMonthWeek) -> some View {
        let on = !w.isLeave
        let start = w.start
        let handler = onLeave
        Button {
            handler(on, start)
        } label: {
            Label(w.isLeave ? "取消請假" : "這週請假", systemImage: w.isLeave ? "xmark.circle" : "leaf")
        }
    }

    /// 一天：有運動、是這個月的才能點
    @ViewBuilder
    private func dayCell(_ d: WorkoutMonthDay) -> some View {
        let cell = HealthCalendarDayCell(day: d, dark: pal.dark, todayStroke: pal.hint)
        if d.inMonth && !d.sessionIds.isEmpty {
            Button {
                tapDay(d)
            } label: {
                cell
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(d.spoken)
            .accessibilityHint(dayHint(d))
            .accessibilityAddTraits(.isButton)
        } else {
            cell
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(d.spoken)
                .accessibilityHidden(!d.inMonth)
        }
    }

    /// VoiceOver 的提示：一趟「點兩下看這一趟」、兩趟以上「點兩下選一趟」
    private func dayHint(_ d: WorkoutMonthDay) -> String {
        d.sessionIds.count > 1 ? "點兩下選一趟" : "點兩下看這一趟"
    }

    /// 連續週數那一行＋「長按一週可以請假」＋圖例
    private func footer(_ g: WorkoutMonthGrid) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(g.footer)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(pal.label)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text("長按一週可以請假")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                HealthCalendarLegend(dark: pal.dark)
            }
        }
        .padding(.top, 4)
    }

    // MARK: 點一天

    private func tapDay(_ d: WorkoutMonthDay) {
        let ids = d.sessionIds
        if ids.count == 1, let id = ids.first {
            onOpen(id)
            return
        }
        guard ids.count > 1 else { return }
        var options: [HealthCalendarPick.Option] = []
        for id in ids {
            guard let s = sessions.first(where: { $0.id == id }) else { continue }
            options.append(HealthCalendarPick.Option(id: id, label: optionLabel(s)))
        }
        if options.count == 1, let only = options.first {
            onOpen(only.id)
            return
        }
        guard !options.isEmpty else { return }
        pick = HealthCalendarPick(title: WorkoutFormat.day(d.date), options: options)
    }

    /// 「晨跑 5.2 公里・06:05」「重訓・19:30」
    private func optionLabel(_ s: WorkoutSession) -> String {
        let km = s.totalDistanceKm
        let dist = km >= 0.05 ? " " + WorkoutFormat.km(km) : ""
        return WorkoutFacts.title(s) + dist + "・" + WorkoutFormat.time(s.date)
    }

    private var pickTitle: String {
        pick?.title ?? ""
    }

    private var pickBinding: Binding<Bool> {
        Binding(get: { pick != nil }, set: { if !$0 { pick = nil } })
    }

    /// 選了一趟：選單收起來那一輪先過，下一輪才打開成果頁（不跟收選單搶同一輪）
    @ViewBuilder
    private func pickButtons(_ p: HealthCalendarPick) -> some View {
        let open = onOpen
        ForEach(p.options) { o in
            Button(o.label) {
                let id = o.id
                DispatchQueue.main.async { open(id) }
            }
        }
        Button("取消", role: .cancel) { }
    }
}

/// 月曆的一天：圓角 6 的格子，底色＝那天動了多久（五階），日期數字＋最多兩個運動小圖示（第三種起「+1」）
private struct HealthCalendarDayCell: View {
    let day: WorkoutMonthDay
    let dark: Bool
    /// 今天外框的顏色
    let todayStroke: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: String(day.day))
                .font(.caption2.weight(day.isToday ? .heavy : .semibold))
                .monospacedDigit()
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            icons
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay { todayRing }
        .opacity(day.inMonth ? 1 : 0.35)
    }

    /// 以後的日子不上色（只留很淡的格子，看得出是哪一天）
    private var fill: Color {
        if day.isFuture { return WorkoutPalette.heat(0, dark: dark).opacity(0.45) }
        return WorkoutPalette.heat(day.level, dark: dark)
    }

    private var ink: Color {
        if day.isFuture { return Color.secondary }
        return WorkoutPalette.heatInk(day.level, dark: dark)
    }

    /// 運動小圖示（高度固定：沒運動的那天也留同樣高，一列不會高低不齊）
    private var icons: some View {
        HStack(spacing: 1) {
            ForEach(day.sports, id: \.self) { sp in
                Image(systemName: sp.icon)
                    .font(.system(size: 8, weight: .bold))
            }
            if day.more > 0 {
                Text(verbatim: "+" + String(day.more))
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .foregroundStyle(ink)
        .lineLimit(1)
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var todayRing: some View {
        if day.isToday {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(todayStroke, lineWidth: 1.5)
        }
    }
}

/// 月曆最右邊那一格：有運動打勾（MoneyTone.good）、沒運動但請假是葉子、其他空白（不打叉、不染紅）。
/// VoiceOver：「10/12 那週，有運動」＋動作「這週請假／取消請假」（長按選單 VoiceOver 不好叫出來）
private struct HealthCalendarMarkCell: View {
    let week: WorkoutMonthWeek
    let pal: TripBoardPalette
    let onLeave: (Bool, Date) -> Void

    var body: some View {
        mark
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityAction(named: Text(actionName)) { leaveAction() }
    }

    @ViewBuilder
    private var mark: some View {
        switch week.mark {
        case .active:
            Image(systemName: "checkmark")
                .font(.caption.weight(.heavy))
                .foregroundStyle(MoneyTone.good.color(pal))
        case .leave:
            Image(systemName: "leaf.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(leafColor)
        case .none:
            Color.clear
        }
    }

    /// 葉子：柔和的綠（不是達標的綠勾那麼重）
    private var leafColor: Color {
        Color(tb: pal.dark ? 0x8FD6A8 : 0x3C8D5A)
    }

    private var actionName: String {
        week.isLeave ? "取消請假" : "這週請假"
    }

    private func leaveAction() {
        onLeave(!week.isLeave, week.start)
    }

    /// 「10/12 那週，有運動」「10/19 那週，請假」「10/26 那週，還沒有運動」
    private var spoken: String {
        let head = WorkoutFormat.monthDay(week.start) + " 那週，"
        switch week.mark {
        case .active:
            return head + (week.isLeave ? "有運動，請假" : "有運動")
        case .leave:
            return head + "請假"
        case .none:
            return head + "還沒有運動"
        }
    }
}

/// 月曆圖例：「少 ▢▢▢▢▢ 多」
private struct HealthCalendarLegend: View {
    let dark: Bool

    var body: some View {
        HStack(spacing: 3) {
            Text("少")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(WorkoutPalette.heat(level, dark: dark))
                    .frame(width: 11, height: 11)
            }
            Text("多")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("格子越深，那天動得越久")
    }
}
