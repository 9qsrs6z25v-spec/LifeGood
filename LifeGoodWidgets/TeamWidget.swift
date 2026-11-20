import SwiftUI
import WidgetKit
import AppIntents

// MARK: - 部屬今天（小工具 v5，只屬於 LifeGoodWidgets）
//
// 由 G2 實作，規格見 scratchpad/widgets/v5/brief.md 的 G2；design_life.md L5（:376-430）；主控定案 A、E、3、11、12、16、17。
// （主控建好的空檔，已登記 pbxproj：A01A000002000090／A01B000002000090）
// systemSmall、systemMedium＋鎖定畫面 accessoryRectangular、accessoryInline；StandBy 用小的。
// 只讀 life_v1.json 的 team（WidgetLifeSnapshot.teamSummary(at:plantArea:)），只數人頭與排序，字都是 App 寫的。
// 鎖定畫面、StandBy 沒有任何名字。
//
// • 中：左上「部屬・10/13 週二」（選了廠區「部屬 A・10/13 週二」）、右上「🎂 明天 王小明生日」（Link → 生日名單）；
//   三格大數字（請假一定第一格、0 也寫，再來那一天有人的班別人數多到少，最多三格）＋名字（放不下「張大明 等 3 人」）；
//   「顯示假別」開著多一行「李大華 特休・陳美玲 病假 4 小時」；「任務 逾期 2・今天到期 3・週報逾期 1」；
//   下面最多 2 條任務（逾期在前，紅字「逾期 2 天」；每條 Link → 那件任務的卡片）。矮的中型放不下時
//   ViewThatFits 依序拿掉：第二條任務 → 假別行 → 名字 → 全部任務列。
// • 小（也是 StandBy）：「部屬 10/13」／「請假 2」（大字）／「大夜 3・小夜 2」（沒排班「今天沒有排班」）／
//   「逾期任務 2」（有逾期才出現，紅字＋字）。小型本來就沒有名字。
// • 鎖定畫面長方形：「部屬 請假 2・大夜 3・小夜 2」／「任務 逾期 2・今天到期 3」／（有逾期報告）「週報逾期 1」；
//   一行字：「部屬 請假 2・大夜 3」。不寫廠區、不寫任何名字。
// • 沒快照「打開 LifeGood 一次…」、沒有部屬（舊檔也算）「還沒有部屬資料」、過期「打開 LifeGood 更新」，點了都開部屬總覽。
// • 隱私（使用者決定）：鎖定畫面、StandBy 一律不放名字（不管設定）；主畫面「顯示名字」關掉＝名字、生日、
//   任務上的名字都不畫；假別要「顯示名字」也開著才畫（主控定案 11）。名字只用 WidgetTeamCell.allNames／shortNames、
//   leaveDetailText、birthdayText、WidgetTeamTask.name（App 寫的字），這個檔不拼人名句子。
// • 時間軸：now ∪ 每份 team 的 00:00 ∪ validUntil（過了寫「打開 LifeGood 更新」），.never（App 改了會叫重畫）。
// • 點了：整塊 → 部屬總覽（WidgetLink.team）；任務 → WidgetTeamTask.url；生日 → WidgetLink.birthdays。沒有打勾按鈕。
//
// 型別（internal 的都帶 TeamWidget 前綴或是 brief 指定的名字；畫面零件 private，也帶 TeamWidget 前綴）：
//   TeamWidget、TeamConfigIntent、TeamWidgetEntry、TeamWidgetProvider、TeamWidgetModel、TeamWidgetCellText、
//   TeamWidgetTaskRow、TeamWidgetEntryView

// MARK: - Widget

struct TeamWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.team, intent: TeamConfigIntent.self,
                               provider: TeamWidgetProvider()) { entry in
            TeamWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("部屬今天")
        .description("今天誰請假、各班幾個人、哪些任務逾期")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - 長按設定

/// 「部屬今天」：廠區、要不要顯示名字與假別（選項型別 WidgetPlantAreaEntity 在共用檔 WidgetConfigTypes.swift）。
/// 廠區 nil、「全部廠區」、快照裡找不到的（改名、刪掉）一律當全部
struct TeamConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "部屬今天"
    static var description = IntentDescription("選廠區、要不要顯示名字與假別")

    @Parameter(title: "廠區")
    var plant: WidgetPlantAreaEntity?

    /// 主畫面才有名字；鎖定畫面、StandBy 不管這個都不放
    @Parameter(title: "顯示名字", default: true)
    var showNames: Bool

    /// 「李大華 特休・陳美玲 病假 4 小時」；「顯示名字」也開著才畫
    @Parameter(title: "顯示假別", default: false)
    var showLeaveTypes: Bool

    init() {}
}

// MARK: - Timeline

struct TeamWidgetEntry: TimelineEntry {
    /// 畫面一律拿這個當「現在」（不在 View 裡呼叫 Date()）
    let date: Date
    /// nil＝還沒打開過新版 App（或檔案讀不到）
    let snapshot: WidgetLifeSnapshot?
    /// 廠區；nil＝全部
    let plantArea: String?
    let showsNames: Bool
    let showsLeaveTypes: Bool

    static func make(date: Date, snapshot: WidgetLifeSnapshot?, configuration: TeamConfigIntent) -> TeamWidgetEntry {
        let plant: String? = validPlant(configuration.plant?.plantFilter, snapshot: snapshot)
        return TeamWidgetEntry(date: date, snapshot: snapshot, plantArea: plant,
                               showsNames: configuration.showNames,
                               showsLeaveTypes: configuration.showLeaveTypes)
    }

    /// 選的廠區快照裡已經沒有（改名、刪掉、那一廠的人都離開了）：退回全部，不會整塊變 0
    static func validPlant(_ plant: String?, snapshot: WidgetLifeSnapshot?) -> String? {
        guard let name = plant, !name.isEmpty else { return nil }
        let areas: [String] = snapshot?.plantAreas ?? []
        return areas.contains(name) ? name : nil
    }
}

/// 不上網：只讀 life 快照。00:00 換到明天那一份、validUntil 之後寫「打開 LifeGood 更新」
struct TeamWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TeamWidgetEntry {
        TeamWidgetSample.entry(now: Date())
    }

    func snapshot(for configuration: TeamConfigIntent, in context: Context) async -> TeamWidgetEntry {
        let now = Date()
        if context.isPreview {
            // 小工具庫裡的預覽：契約的樣本（WidgetLifeSample.teamDay，人名都是假的）
            return TeamWidgetSample.entry(now: now)
        }
        let snapshot = WidgetSnapshotStore.read(WidgetLifeSnapshot.self)
        return TeamWidgetEntry.make(date: now, snapshot: snapshot, configuration: configuration)
    }

    func timeline(for configuration: TeamConfigIntent, in context: Context) async -> Timeline<TeamWidgetEntry> {
        let now = Date()
        let snapshot = WidgetSnapshotStore.read(WidgetLifeSnapshot.self)
        let dates: [Date] = TeamWidgetTimeline.entryDates(snapshot: snapshot, now: now)
        let entries: [TeamWidgetEntry] = dates.map { date in
            TeamWidgetEntry.make(date: date, snapshot: snapshot, configuration: configuration)
        }
        return Timeline(entries: entries, policy: .never)
    }
}

/// 哪些時間點要換畫面
private enum TeamWidgetTimeline {
    /// now ∪ 每份 team 的開始／結束（00:00 換到明天那一份）∪ validUntil，比 now 晚的排好去重。
    /// 沒快照：只有 now（App 寫了快照會叫重畫：WidgetKind.lifeKinds 含部屬今天）
    static func entryDates(snapshot: WidgetLifeSnapshot?, now: Date) -> [Date] {
        guard let snap = snapshot else { return [now] }
        var times = Set<Date>()
        for day in snap.team ?? [] {
            times.insert(day.dayStart)
            times.insert(day.dayEnd)
        }
        times.insert(snap.validUntil)
        let later: [Date] = times.filter { $0 > now }.sorted()
        return [now] + later
    }
}

// MARK: - 畫面要的字（全部在這裡組好，body 只讀）

/// 中型三格的一格：「請假」＋「2」＋名字。名字只在主畫面、「顯示名字」開著才有（不然是空字串）
struct TeamWidgetCellText: Identifiable {
    /// 「leave」「shift-大夜」（WidgetTeamCell.id）
    let id: String
    /// 「請假」「大夜」
    let label: String
    /// 「2」
    let count: String
    /// 「李大華・陳美玲」；0 人「—」
    let allNames: String
    /// 放不下時：「張大明 等 3 人」；0 人「—」
    let shortNames: String
}

/// 中型下面的一條任務（點了開那件任務的卡片）
struct TeamWidgetTaskRow: Identifiable {
    let id: UUID
    /// 「冰水機 PM 紀錄」
    let topic: String
    /// 「李大華」；「顯示名字」關掉是空字串
    let name: String
    /// 「逾期 2 天」「已逾期」「今天」（App 寫的字）
    let dueText: String
    /// 逾期：紅字（字本身就有「逾期」，著色模式靠字）
    let isOverdue: Bool
    let url: URL
}

struct TeamWidgetModel {
    /// 沒快照、沒有部屬、過期：只寫一句話
    var isMessage = true
    var message = ""
    /// 一句話下面的小字（沒有部屬：「在 App 的部屬管理加入」）
    var hint = ""
    /// 整塊點了去哪：一律部屬總覽
    var url: URL = WidgetLink.team

    /// 有選廠區（標題比較長，小型不放雲）
    var hasPlant = false
    /// 中型左上「部屬・10/13 週二」「部屬 A・10/13 週二」
    var title = ""
    /// 小型左上「部屬 10/13」「部屬 A 10/13」
    var smallTitle = ""
    /// 中型三格
    var cells: [TeamWidgetCellText] = []
    /// 格子下面寫不寫名字（「顯示名字」開著、而且不是鎖定畫面／StandBy）
    var showsNames = false
    /// 「李大華 特休・陳美玲 病假 4 小時」；不畫是空字串
    var leaveDetail = ""
    /// 右上「明天 王小明生日」；不畫是空字串
    var birthday = ""
    /// 「任務」後面那一段：「逾期 2・今天到期 3・週報逾期 1」「都完成了」
    var taskLine = ""
    /// 最多 2 條：逾期在前、再今天到期
    var taskRows: [TeamWidgetTaskRow] = []

    // 小型（主畫面、StandBy）
    /// 大字左邊的「請假」
    var leaveLabel = "請假"
    /// 大字「2」
    var leaveCount = "0"
    /// 「大夜 3・小夜 2」；那一天沒排班「今天沒有排班」
    var shiftsLine = ""
    var shiftsIsEmpty = false
    /// 「逾期任務 2」；沒有逾期是空字串
    var overdueBadge = ""

    // 鎖定畫面（只有數字）
    /// 「部屬 請假 2・大夜 3・小夜 2」
    var rectLine1 = ""
    /// 「任務 逾期 2・今天到期 3」
    var rectLine2 = ""
    /// 「週報逾期 1」；沒有是空字串
    var rectLine3 = ""
    /// 「部屬 請假 2・大夜 3」
    var inlineText = ""

    /// privacy＝鎖定畫面三型或 StandBy：一律不放名字（不管設定）
    static func make(entry: TeamWidgetEntry, privacy: Bool) -> TeamWidgetModel {
        var m = TeamWidgetModel()
        guard let snap = entry.snapshot else {
            TeamWidgetText.fillMessage(&m, text: "打開 LifeGood 一次，這裡就會出現部屬今天", hint: "",
                                       short: "打開 LifeGood")
            return m
        }
        guard snap.hasTeam == true else {
            TeamWidgetText.fillMessage(&m, text: "還沒有部屬資料", hint: "在 App 的部屬管理加入",
                                       short: "還沒有部屬資料")
            return m
        }
        guard !snap.isExpired(at: entry.date),
              let summary = snap.teamSummary(at: entry.date, plantArea: entry.plantArea) else {
            TeamWidgetText.fillMessage(&m, text: "打開 LifeGood 更新", hint: "", short: "打開 LifeGood 更新")
            return m
        }
        let names: Bool = entry.showsNames && !privacy
        m.isMessage = false
        TeamWidgetText.fillTitles(&m, summary: summary, plantArea: entry.plantArea)
        TeamWidgetText.fillMedium(&m, summary: summary, names: names, leaveTypes: entry.showsLeaveTypes)
        TeamWidgetText.fillSmall(&m, summary: summary)
        TeamWidgetText.fillLock(&m, summary: summary)
        return m
    }
}

/// 組字的小函式（只挑 App 寫好的字、接「・」與數字，不拼人名句子）
private enum TeamWidgetText {
    /// 一句話（三種沒資料）；長方形、一行字寫短的
    static func fillMessage(_ m: inout TeamWidgetModel, text: String, hint: String, short: String) {
        m.isMessage = true
        m.message = text
        m.hint = hint
        m.rectLine1 = short
        m.inlineText = short
    }

    /// 標題：選了廠區「部屬 A・10/13 週二」／「部屬 A 10/13」（鎖定畫面不寫廠區，主控定案 12）
    static func fillTitles(_ m: inout TeamWidgetModel, summary: WidgetTeamSummary, plantArea: String?) {
        var prefix = "部屬"
        if let plant = plantArea, !plant.isEmpty {
            prefix = "部屬 " + plant
            m.hasPlant = true
        }
        m.title = prefix + "・" + summary.dateText
        m.smallTitle = prefix + " " + summary.shortDateText
    }

    /// 中型：三格、名字、假別、生日、任務列與兩條任務
    static func fillMedium(_ m: inout TeamWidgetModel, summary: WidgetTeamSummary, names: Bool, leaveTypes: Bool) {
        m.showsNames = names
        m.cells = summary.cells.map { cell($0, names: names) }
        if names && leaveTypes && !summary.leaves.isEmpty {
            m.leaveDetail = summary.leaveDetailText
        }
        if names, let text = summary.birthdayText {
            m.birthday = text
        }
        m.taskLine = summary.taskLine(includeReports: true)
        m.taskRows = summary.taskRows.map { taskRow($0, names: names) }
    }

    /// 小型（StandBy 同一版，本來就沒有名字）
    static func fillSmall(_ m: inout TeamWidgetModel, summary: WidgetTeamSummary) {
        if let leave = summary.cells.first {
            m.leaveLabel = leave.label
            m.leaveCount = String(leave.count)
        }
        let shifts: String = summary.shiftsLine
        m.shiftsIsEmpty = shifts.isEmpty
        m.shiftsLine = shifts.isEmpty ? "今天沒有排班" : shifts
        m.overdueBadge = summary.overdueBadge ?? ""
    }

    /// 鎖定畫面：只有數字字（countsLine、taskLine），沒有名字、沒有廠區
    static func fillLock(_ m: inout TeamWidgetModel, summary: WidgetTeamSummary) {
        m.rectLine1 = "部屬 " + summary.countsLine()
        m.rectLine2 = "任務 " + summary.taskLine(includeReports: false)
        if summary.overdueReports > 0 {
            m.rectLine3 = "週報逾期 " + String(summary.overdueReports)
        }
        m.inlineText = "部屬 " + summary.countsLine(maxCells: 2)
    }

    /// 一格：名字關掉是空字串；0 人寫「—」
    static func cell(_ c: WidgetTeamCell, names: Bool) -> TeamWidgetCellText {
        var all = ""
        var short = ""
        if names {
            all = c.people.isEmpty ? "—" : c.allNames
            short = c.people.isEmpty ? "—" : c.shortNames
        }
        return TeamWidgetCellText(id: c.id, label: c.label, count: String(c.count),
                                  allNames: all, shortNames: short)
    }

    static func taskRow(_ t: WidgetTeamTask, names: Bool) -> TeamWidgetTaskRow {
        let name: String = names ? t.name : ""
        return TeamWidgetTaskRow(id: t.taskId, topic: t.topic, name: name, dueText: t.dueText,
                                 isOverdue: t.isOverdue, url: t.url)
    }
}

/// 小工具庫預覽與 placeholder：契約的樣本（請假 2、大夜 3、小夜 2、逾期 2・今天到期 3、週報逾期 1、
/// 明天 王小明生日；日期字寫死「10/13 週二」），G2 不另寫一份人名
private enum TeamWidgetSample {
    static func entry(now: Date) -> TeamWidgetEntry {
        let cal = Calendar.current
        let today: Date = cal.startOfDay(for: now)
        let until: Date = cal.date(byAdding: .day, value: 2, to: today) ?? today.addingTimeInterval(2 * 86_400)
        var snap = WidgetLifeSnapshot(generatedAt: now,
                                      dataDay: WidgetDateText.dayKey(now),
                                      validUntil: until,
                                      days: [])
        snap.hasTeam = true
        snap.team = [WidgetLifeSample.teamDay(dayStart: today)]
        snap.plantAreas = ["A", "B"]
        return TeamWidgetEntry(date: now, snapshot: snap, plantArea: nil,
                               showsNames: true, showsLeaveTypes: false)
    }
}

// MARK: - 畫面

struct TeamWidgetEntryView: View {
    let entry: TeamWidgetEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var surface: WidgetPalette.Surface {
        WidgetPalette.Surface(renderingMode: renderingMode, showsBackground: showsBackground)
    }

    private var palette: WidgetPalette {
        WidgetPalette(colorScheme, mono: surface.isMono)
    }

    private var isAccessory: Bool {
        family == .accessoryRectangular || family == .accessoryInline
    }

    /// 鎖定畫面、StandBy：沒有任何名字（主控定案 E）
    private var privacy: Bool {
        isAccessory || surface.isStandBy
    }

    var body: some View {
        let model = TeamWidgetModel.make(entry: entry, privacy: privacy)
        TeamWidgetContent(model: model, palette: palette, family: family)
            .containerBackground(for: .widget) {
                background(for: model)
            }
            .widgetURL(model.url)
    }

    /// 主畫面全彩畫天空；著色、StandBy、鎖定畫面透明
    @ViewBuilder
    private func background(for model: TeamWidgetModel) -> some View {
        if surface.drawsSky && !isAccessory {
            WidgetSky(palette: palette, moon: skyMoon(for: model))
        } else {
            Color.clear
        }
    }

    /// 雲／月牙不壓字（J:56）：中型右上有生日就不放；小型選了廠區（標題變長）不放
    private func skyMoon(for model: TeamWidgetModel) -> WidgetSkyMoon {
        if family == .systemMedium {
            return model.birthday.isEmpty ? WidgetSkyMoon.topTrailing : WidgetSkyMoon.none
        }
        return model.hasPlant ? WidgetSkyMoon.none : WidgetSkyMoon.topTrailing
    }
}

/// 依尺寸、狀態挑版面（ViewBuilder 裡只比對 Bool 與 WidgetFamily）
private struct TeamWidgetContent: View {
    let model: TeamWidgetModel
    let palette: WidgetPalette
    let family: WidgetFamily

    var body: some View {
        if family == .accessoryInline {
            Text(model.inlineText)
        } else if family == .accessoryRectangular {
            TeamWidgetRect(model: model)
        } else if model.isMessage {
            TeamWidgetMessage(text: model.message, hint: model.hint, palette: palette)
        } else if family == .systemMedium {
            TeamWidgetMedium(model: model, palette: palette)
        } else {
            TeamWidgetSmall(model: model, palette: palette)
        }
    }
}

// MARK: 中型

/// 標題列、三格、名字、假別、任務列、兩條任務。
/// 矮的中型（SE 一類，內容約 289×116）放不下時 ViewThatFits 由上往下挑：
/// ① 假別＋2 條 ② 假別＋1 條 ③ 沒假別＋2 條 ④ 沒假別＋1 條 ⑤ 沒名字＋1 條 ⑥ 只有標題、三格、任務列。字級不縮
private struct TeamWidgetMedium: View {
    let model: TeamWidgetModel
    let palette: WidgetPalette

    var body: some View {
        ViewThatFits(in: .vertical) {
            column(showsDetail: true, showsNames: true, rowLimit: 2)
            column(showsDetail: true, showsNames: true, rowLimit: 1)
            column(showsDetail: false, showsNames: true, rowLimit: 2)
            column(showsDetail: false, showsNames: true, rowLimit: 1)
            column(showsDetail: false, showsNames: false, rowLimit: 1)
            column(showsDetail: false, showsNames: false, rowLimit: 0)
        }
    }

    /// 不在尾巴放 Spacer：frame 的 .topLeading 已經把內容貼上面；Spacer 會在 ViewThatFits 量高度時
    /// 多算一個 3pt 間距，6.1 吋（內容約 126pt）的「沒假別＋2 條」（約 122pt）就可能被擠成 1 條
    private func column(showsDetail: Bool, showsNames: Bool, rowLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            TeamWidgetMediumHeader(model: model, palette: palette)
            TeamWidgetCellsRow(cells: model.cells, showsNames: showsNames && model.showsNames, palette: palette)
            TeamWidgetPlainLine(text: showsDetail ? model.leaveDetail : "", palette: palette)
            TeamWidgetTaskHeadline(text: model.taskLine, palette: palette)
            TeamWidgetTaskList(rows: Array(model.taskRows.prefix(rowLimit)), palette: palette)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 左「部屬・10/13 週二」，右「🎂 明天 王小明生日」（Link → 生日名單；放不下縮的是生日）
private struct TeamWidgetMediumHeader: View {
    let model: TeamWidgetModel
    let palette: WidgetPalette

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(model.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.inkDate)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 6)
            birthdayLink
        }
    }

    @ViewBuilder
    private var birthdayLink: some View {
        if !model.birthday.isEmpty {
            Link(destination: WidgetLink.birthdays) {
                TeamWidgetBirthdayLabel(text: model.birthday, palette: palette)
            }
        }
    }
}

/// 蛋糕＋「明天 王小明生日」
private struct TeamWidgetBirthdayLabel: View {
    let text: String
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "birthday.cake.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.label)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// 三格（每格平分寬度；只有請假一格時佔滿）
private struct TeamWidgetCellsRow: View {
    let cells: [TeamWidgetCellText]
    let showsNames: Bool
    let palette: WidgetPalette

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(cells, id: \.id) { cell in
                TeamWidgetCellView(cell: cell, showsNames: showsNames, palette: palette)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// 一格：「請假」12pt＋「2」24pt（著色模式染重點色），下面名字 11pt 一行（放不下換「張大明 等 3 人」）
private struct TeamWidgetCellView: View {
    let cell: TeamWidgetCellText
    let showsNames: Bool
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(cell.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
                    .fixedSize()
                TeamWidgetNumber(text: cell.count, size: 24, palette: palette)
            }
            namesView
        }
    }

    @ViewBuilder
    private var namesView: some View {
        if showsNames {
            ViewThatFits(in: .horizontal) {
                namesText(cell.allNames)
                namesText(cell.shortNames)
            }
        }
    }

    private func namesText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.inkSoft)
            .lineLimit(1)
    }
}

/// 大數字（rounded bold；著色模式染重點色；放不下最多縮到 0.7）
private struct TeamWidgetNumber: View {
    let text: String
    let size: CGFloat
    let palette: WidgetPalette

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .widgetAccentable()
    }
}

/// 假別一行（11pt、尾巴截）；空字串不畫
private struct TeamWidgetPlainLine: View {
    let text: String
    let palette: WidgetPalette

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.inkSoft)
                .lineLimit(1)
        }
    }
}

/// 「任務」（灰）＋「逾期 2・今天到期 3・週報逾期 1」
private struct TeamWidgetTaskHeadline: View {
    let text: String
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 4) {
            Text("任務")
                .foregroundStyle(palette.label)
                .fixedSize()
            Text(text)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.system(size: 12, weight: .semibold))
    }
}

/// 中型下面的任務；每條是一個 Link（點了開那件任務的卡片）。沒有就不畫
private struct TeamWidgetTaskList: View {
    let rows: [TeamWidgetTaskRow]
    let palette: WidgetPalette

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(rows, id: \.id) { row in
                    Link(destination: row.url) {
                        TeamWidgetTaskRowView(row: row, palette: palette)
                    }
                }
            }
        }
    }
}

/// 一條：點、主題、名字（灰）、「逾期 2 天」（紅）／「今天」（橘）
private struct TeamWidgetTaskRowView: View {
    let row: TeamWidgetTaskRow
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dueColor)
                .frame(width: 5, height: 5)
            Text(row.topic)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            nameText
            dueLabel
        }
    }

    /// 逾期紅、今天到期橘（著色模式顏色會被洗掉：字本身就有「逾期」「今天」）
    private var dueColor: Color {
        row.isOverdue ? palette.bad : palette.warn
    }

    @ViewBuilder
    private var nameText: some View {
        if !row.name.isEmpty {
            Text(row.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .frame(width: 48, alignment: .leading)
        }
    }

    /// 固定寬度，兩條才對得齊
    private var dueLabel: some View {
        Text(row.dueText)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(dueColor)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 58, alignment: .trailing)
    }
}

// MARK: 小型（主畫面、StandBy）

/// 「部屬 10/13」／「請假 2」（大字）／「大夜 3・小夜 2」／「逾期任務 2」（有逾期才出現）。
/// 沒有名字，StandBy 同一版（不畫天空、白字）
private struct TeamWidgetSmall: View {
    let model: TeamWidgetModel
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.smallTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.inkDate)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            TeamWidgetSmallHero(label: model.leaveLabel, count: model.leaveCount, palette: palette)
                .padding(.top, 2)
            TeamWidgetShiftsLine(text: model.shiftsLine, isEmpty: model.shiftsIsEmpty, palette: palette)
            Spacer(minLength: 2)
            TeamWidgetBadge(text: model.overdueBadge, palette: palette)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 「請假」13pt＋「2」34pt
private struct TeamWidgetSmallHero: View {
    let label: String
    let count: String
    let palette: WidgetPalette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .fixedSize()
            TeamWidgetNumber(text: count, size: 34, palette: palette)
        }
    }
}

/// 「大夜 3・小夜 2」14pt；沒排班「今天沒有排班」12pt 灰
private struct TeamWidgetShiftsLine: View {
    let text: String
    let isEmpty: Bool
    let palette: WidgetPalette

    var body: some View {
        if isEmpty {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

/// 「逾期任務 2」12.5pt 紅字（著色模式靠「逾期」兩個字）；空字串不畫
private struct TeamWidgetBadge: View {
    let text: String
    let palette: WidgetPalette

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(palette.bad)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: 一句話

/// 沒快照「打開 LifeGood 一次…」、沒有部屬「還沒有部屬資料」＋小字、過期「打開 LifeGood 更新」
private struct TeamWidgetMessage: View {
    let text: String
    let hint: String
    let palette: WidgetPalette

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.label)
                .widgetAccentable()
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(4)
            hintText
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var hintText: some View {
        if !hint.isEmpty {
            Text(hint)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.label)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

// MARK: 鎖定畫面長方形

/// 「部屬 請假 2・大夜 3・小夜 2」／「任務 逾期 2・今天到期 3」／「週報逾期 1」。
/// 只有數字字，沒有名字、沒有廠區；系統單色，只用 .secondary 分深淺
private struct TeamWidgetRect: View {
    let model: TeamWidgetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(model.rectLine1)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .widgetAccentable()
            rectLine(model.rectLine2, size: 13)
            rectLine(model.rectLine3, size: 12.5)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func rectLine(_ text: String, size: CGFloat) -> some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: size, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}
