import SwiftUI

// MARK: - [v25.602 職能雷達 v2] 課的總覽（人才矩陣第四段〔職能〕；G1 負責；radar/judge.md §4.7、§3.8、§6、§13；radar/build/v2/brief.md §4 G1）
//
// • 人才矩陣（TalentMatrixView）只多 Picker 一個 tag(3)「職能」＋一行呼叫 CompetencyTeamView(members: members)：
//   部門篩選、〔含已轉出〕用人才矩陣現有的那兩個狀態（members 已經篩好），這裡不另外存。
// • 規則全部在 CompetencyMath（teamModel、teamSortedRows、findPeople…）；body 只排版：let m = model 一次，格子、欄頭、卡片都拆成小
//   private struct（CompTeam… 前綴），不在 body 裡寫長運算式。
// • 看不擋訂閱；〔一次評全課〕（CompetencyTeamBatchButton，G4）擋訂閱。這個檔不寫任何 store。
// • 名字、分數只在 App 裡：通知、小工具、手錶、鎖定畫面、靈動島一個字都不加；這一版不做分享匯出（v4）。
//   [v25.605 v4b] 熱力表右上〔分享…〕（先選〔圖片｜文字〕→ 提醒「圖上有 N 位同仁的名字和職能分數…」→ 分享面板）：使用者自己按的分享，
//   看不擋訂閱；照畫面上那一份 model（列照 m.rows，不照排序）；部門字讀人才矩陣的 talentMatrixDeptFilter（只讀、不寫）。
//   規則在 CompetencyMath.heatShare…，提醒／面板在 CompetencyTeamTools（CompetencyHeatShareFlow），圖在 CompetencyTeamShareImage。
//   [v25.606 v5a] 最下面「帶訓中」（CompetencyTeamTools 的 CompetencyTeamMentoringSection；字照 CompetencyMath.mentoringLines）：
//   一位帶訓者一行「陳怡君 → 王小明（Gas）」，點學的人開那位的〔職能〕（既有的 CompTeamPersonSheet，看不擋）；
//   熱力表、四張卡、課平均不加帶訓者評。
// • 字不用「他／她」：用名字或「這位同仁」。
// • 熱力表不用 Grid／Table／LazyHGrid：固定的名字欄 VStack＋ScrollView(.horizontal) 裡「一組一個 VStack（組名＋一欄一個 VStack）」，
//   一欄一個 VStack 紅框橘框才能整欄框住；名字欄與格子用同一組 @ScaledMetric 常數（CompTeamMetrics）才對得齊。
// 骨架（主控）：CompetencyTeamView(members:) 是跨組契約（TalentMatrixView 那一行在叫），不准改參數。
// 要退回這一版：TalentMatrixView 刪 tag(3) 那一行與呼叫這個 View 的兩行，這個檔與 CompetencyTeamTools.swift 連同 pbxproj 八處拿掉。

struct CompetencyTeamView: View {
    /// 人才矩陣現在的名單（部門篩選、〔含已轉出〕之後；照順序）
    let members: [Subordinate]

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager

    /// 本職學能｜人格特質（不記住，每次從本職學能開始）
    @State private var area: CompetencyTeamArea = .skill
    /// 點欄頭排序：哪一欄（"組|項目"；nil＝照原順序）、高到低
    @State private var sortColumnId: String?
    @State private var descending = true
    /// 單點風險 sheet、〔看某某〕、點一格的歷史（sheet(item:)）
    @State private var riskRequest: CompTeamRiskRequest?
    @State private var personRequest: CompTeamPersonRequest?
    @State private var historyRequest: CompetencyCellHistoryRequest?
    /// 〔看某某〕按下去時先記在這裡，風險 sheet 真的關好（onDismiss）才開那位的〔職能〕
    /// （G1 審查修：原本 asyncAfter(0.35) 固定等，關的動畫還沒跑完就開下一張會被 SwiftUI 丟掉；照 OrganizationView openPendingOrgMove 的做法）
    @State private var pendingPerson: CompTeamPersonRequest?
    /// [v25.605 職能雷達 v4b] 課的總覽分享：按〔分享…〕那一刻抓的一份（提醒和內容同一份）
    @State private var heatShare: CompetencyHeatShareRequest?
    /// [v25.605 v4b] 人才矩陣記住的部門篩選（同一個鍵；這裡只讀，標題的部門字用）
    @AppStorage("talentMatrixDeptFilter") private var deptFilterRaw: String = ""

    private var model: CompetencyTeamModel {
        lifeStore.competencyTeamModel(members: members, area: area)
    }

    var body: some View {
        let m = model
        return VStack(alignment: .leading, spacing: 12) {
            areaPicker
            if let e = m.emptyText {
                Text(e)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                content(m)
            }
        }
        .padding(.horizontal)
        .modifier(CompTeamSheets(riskRequest: $riskRequest, personRequest: $personRequest,
                                 historyRequest: $historyRequest, onOpenPerson: openPerson,
                                 onRiskDismissed: riskDismissed))
        .modifier(CompetencyHeatShareFlow(request: $heatShare))
    }

    private var areaPicker: some View {
        Picker("", selection: $area) {
            ForEach(CompetencyTeamArea.allCases) { a in
                Text(a.title).tag(a)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("看哪一區")
    }

    @ViewBuilder
    private func content(_ m: CompetencyTeamModel) -> some View {
        CompTeamCardsGrid(cards: m.cards, onTap: { card in openRisk(card, model: m) })
        // [v25.605 v4b] 熱力表右上〔分享…〕（只在有欄時：emptyText 那一支沒有）
        HStack {
            Spacer(minLength: 0)
            CompetencyHeatShareMenu(onPick: { image in startHeatShare(m, image: image) })
        }
        CompTeamTable(model: m, rows: sortedRows(m), sortColumnId: activeSortId(m), descending: descending,
                      onTapHeader: tapHeader, onTapCell: tapCell)
        Text(m.legend)
            .font(.caption2)
            .foregroundStyle(.secondary)
        CompetencyTeamBatchButton(members: members)
        CompetencyTeamFindCard(model: m)
        CompetencyTeamRadarSection(model: m, members: members)
        CompetencyTeamMentoringSection(lines: mentoringLines, onOpen: openLearner)
    }

    /// [v25.606 v5a] 最下面「帶訓中」（名單＝人才矩陣現在的名單；已轉出的不列）
    private var mentoringLines: [CompetencyMentoringLine] {
        CompetencyMath.mentoringLines(setup: lifeStore.competencySetup,
                                      people: lifeStore.competencyTeamPeople(members),
                                      roster: lifeStore.competencyMentorRoster)
    }

    // MARK: 排序（第一下高到低、第二下低到高、第三下回原順序；切了區找不到那一欄就照原順序）

    private func activeSortId(_ m: CompetencyTeamModel) -> String? {
        guard let id = sortColumnId, m.columns.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    private func sortedRows(_ m: CompetencyTeamModel) -> [CompetencyTeamRow] {
        guard let id = sortColumnId, let idx = m.columns.firstIndex(where: { $0.id == id }) else { return m.rows }
        return CompetencyMath.teamSortedRows(m.rows, column: idx, descending: descending)
    }

    private func tapHeader(_ columnId: String) {
        if sortColumnId == columnId {
            if descending {
                descending = false
            } else {
                sortColumnId = nil
                descending = true
            }
        } else {
            sortColumnId = columnId
            descending = true
        }
    }

    // MARK: [v25.605 v4b] 課的總覽分享（使用者自己按的分享，不擋訂閱；不寫 store）

    /// 按下去那一刻抓一份（部門字照人才矩陣的篩選，只讀）。分享的是 m.rows 原本的順序（排序只是看）
    private func startHeatShare(_ m: CompetencyTeamModel, image: Bool) {
        let today: String = CompetencyMath.dayKey(Date())
        var names: [UUID: String] = [:]
        for d in lifeStore.departments {
            names[d.id] = CompetencyMath.heatShareDeptName(name: d.name, code: d.code)
        }
        let selected: Set<UUID> = CompetencyMath.heatShareSelectedIds(deptFilterRaw)
        let scope: String = CompetencyMath.heatShareScope(selectedIds: selected, names: names)
        let title: String = CompetencyMath.heatShareTitle(m, scope: scope, today: today, withRange: false)
        let text: String = CompetencyMath.heatShareText(m, scope: scope, today: today)
        let pages: [CompetencyHeatSharePage] = CompetencyMath.heatSharePages(m, title: title)
        let w = CompetencyMath.heatShareWarning(m, image: image)
        heatShare = CompetencyHeatShareRequest(image: image, model: m, text: text, pages: pages,
                                               title: w.title, message: w.message)
    }

    // MARK: 點格子、卡片、〔看某某〕（只是看，不擋訂閱）

    private func tapCell(_ cell: CompetencyTeamCell) {
        guard cell.kind != .notRequired else { return }
        historyRequest = CompetencyCellHistoryRequest(subordinateId: cell.personId, groupId: cell.groupId, itemId: cell.itemId)
    }

    private func openRisk(_ card: CompetencyTeamCard, model m: CompetencyTeamModel) {
        guard CompTeamCardView.opensRisk(card) else { return }
        let entries: [CompetencyRiskEntry] = m.risks.filter { $0.kind == card.id }
        guard !entries.isEmpty else { return }
        riskRequest = CompTeamRiskRequest(id: card.id, title: card.title, entries: entries)
    }

    /// 〔看林志豪〕：先關風險 sheet，關好之後（riskDismissed）才開那位的〔職能〕分頁
    private func openPerson(_ id: UUID) {
        let raw: String = model.rows.first(where: { $0.id == id })?.name ?? ""
        let name: String = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "這位同仁" : raw
        pendingPerson = CompTeamPersonRequest(id: id, name: name)
        riskRequest = nil
    }

    /// [v25.606 v5a]「帶訓中」點學的人：開那位的〔職能〕（只是看，不擋訂閱）
    private func openLearner(_ id: UUID, _ name: String) {
        personRequest = CompTeamPersonRequest(id: id, name: name)
    }

    /// 風險 sheet 關好了：有按〔看某某〕才開下一張（下一個 runloop）；往下滑關掉的什麼都不開
    private func riskDismissed() {
        guard let p = pendingPerson else { return }
        pendingPerson = nil
        DispatchQueue.main.async {
            personRequest = p
        }
    }
}

// MARK: - sheet（風險、看某某、點一格；都 sheet(item:)＋.appStores()）

/// 單點風險 sheet（一種卡一份；列的是點的那一刻的字）
private struct CompTeamRiskRequest: Identifiable {
    /// "independent"／"trainer"
    let id: String
    let title: String
    let entries: [CompetencyRiskEntry]
}

/// 〔看某某〕：用 sheet 包那位的〔職能〕分頁（不改 SubordinateDetailView）
private struct CompTeamPersonRequest: Identifiable {
    let id: UUID
    let name: String
}

private struct CompTeamSheets: ViewModifier {
    @Binding var riskRequest: CompTeamRiskRequest?
    @Binding var personRequest: CompTeamPersonRequest?
    @Binding var historyRequest: CompetencyCellHistoryRequest?
    let onOpenPerson: (UUID) -> Void
    let onRiskDismissed: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $riskRequest, onDismiss: onRiskDismissed) { r in
                CompTeamRiskSheet(request: r, onOpen: onOpenPerson)
                    .appStores()
            }
            .sheet(item: $personRequest) { r in
                CompTeamPersonSheet(request: r)
                    .appStores()
            }
            .sheet(item: $historyRequest) { r in
                CompetencyCellHistorySheet(subordinateId: r.subordinateId, groupId: r.groupId, itemId: r.itemId)
                    .appStores()
            }
    }
}

/// 點「只剩一人能獨立」「只剩一人能教人」卡片後的那幾段字（judge §4.7）
private struct CompTeamRiskSheet: View {
    let request: CompTeamRiskRequest
    let onOpen: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(request.entries) { e in
                        CompTeamRiskEntryView(entry: e, onOpen: onOpen)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 單點風險一段：欄名、那一段字、〔看林志豪〕
private struct CompTeamRiskEntryView: View {
    let entry: CompetencyRiskEntry
    let onOpen: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.title)
                .font(.subheadline.weight(.semibold))
            Text(entry.text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            if let pid = entry.focusPersonId, let t = entry.buttonTitle {
                Button(t) { onOpen(pid) }
                    .buttonStyle(.bordered)
                    .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
    }
}

/// 〔看某某〕那位的〔職能〕分頁
private struct CompTeamPersonSheet: View {
    let request: CompTeamPersonRequest

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                SubordinateCompetencyTab(subordinateId: request.id)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(request.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 最上面四張卡（iPhone 2×2、iPad 一排四張）

private struct CompTeamCardsGrid: View {
    let cards: [CompetencyTeamCard]
    let onTap: (CompetencyTeamCard) -> Void

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(cards) { c in
                CompTeamCardView(card: c, onTap: { onTap(c) })
            }
        }
    }
}

private struct CompTeamCardView: View {
    let card: CompetencyTeamCard
    let onTap: () -> Void

    /// 只有「只剩一人能獨立／能教人」而且有那種欄，點了才開單點風險
    static func opensRisk(_ c: CompetencyTeamCard) -> Bool {
        (c.id == "independent" || c.id == "trainer") && c.value > 0
    }

    private var valueColor: Color {
        guard card.alert else { return Color.secondary }
        return (card.id == "independent" || card.id == "target") ? Color.red : Color.orange
    }

    /// 「只剩一人能獨立，1 欄，Chemical System・緊急應變，按兩下看說明」
    private var spoken: String {
        let isColumns: Bool = card.id == "independent" || card.id == "trainer"
        var s: String = card.title + "，" + (isColumns ? "\(card.value) 欄" : card.valueText)
        if let n = card.note { s += "，" + n }
        if CompTeamCardView.opensRisk(card) { s += "，按兩下看說明" }
        return s
    }

    var body: some View {
        if CompTeamCardView.opensRisk(card) {
            Button(action: onTap) { face }
                .buttonStyle(.plain)
                .accessibilityLabel(spoken)
        } else {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
        }
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(card.valueText)
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(valueColor)
            Text(card.note ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 熱力表（judge §4.7：固定名字欄＋系統欄橫捲；一組一個 VStack、一欄一個 VStack）

/// 名字欄與格子共用的尺寸（同一組常數才對得齊）
private struct CompTeamMetrics {
    let colWidth: CGFloat
    let nameWidth: CGFloat
    let groupHeight: CGFloat
    let headerHeight: CGFloat
    let rowHeight: CGFloat
    let footHeight: CGFloat
    /// 一欄裡上下的間距（名字欄也用這個）
    let vSpacing: CGFloat = 2
    /// 一組裡左右的間距
    let hSpacing: CGFloat = 3
    /// 組與組之間
    let groupSpacing: CGFloat = 8
}

/// 一欄＋它在 columns 的位置（cells 照這個位置取）
private struct CompTeamIndexedColumn: Identifiable {
    let ci: Int
    let column: CompetencyTeamColumn
    var id: String { column.id }
}

private struct CompTeamTable: View {
    let model: CompetencyTeamModel
    /// 排好的列
    let rows: [CompetencyTeamRow]
    let sortColumnId: String?
    let descending: Bool
    let onTapHeader: (String) -> Void
    let onTapCell: (CompetencyTeamCell) -> Void

    @ScaledMetric(relativeTo: .caption) private var colWidth: CGFloat = 48
    @ScaledMetric(relativeTo: .caption) private var nameWidth: CGFloat = 96
    @ScaledMetric(relativeTo: .caption) private var groupHeight: CGFloat = 20
    @ScaledMetric(relativeTo: .caption) private var headerHeight: CGFloat = 36
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 40
    @ScaledMetric(relativeTo: .caption) private var footHeight: CGFloat = 28

    private var metrics: CompTeamMetrics {
        CompTeamMetrics(colWidth: colWidth, nameWidth: nameWidth, groupHeight: groupHeight,
                        headerHeight: headerHeight, rowHeight: rowHeight, footHeight: footHeight)
    }

    var body: some View {
        let mt = metrics
        return HStack(alignment: .top, spacing: 0) {
            CompTeamNameColumn(model: model, rows: rows, metrics: mt)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: mt.groupSpacing) {
                    ForEach(model.groups) { g in
                        CompTeamGroupView(group: g, columns: indexedColumns(g), rows: rows, metrics: mt,
                                          sortColumnId: sortColumnId, descending: descending,
                                          onTapHeader: onTapHeader, onTapCell: onTapCell)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
    }

    /// 這一組的欄（位置從 group.start 起算；超出 columns 的不畫）
    private func indexedColumns(_ g: CompetencyTeamGroupHeader) -> [CompTeamIndexedColumn] {
        let lo: Int = max(0, min(g.start, model.columns.count))
        let hi: Int = max(lo, min(g.start + g.count, model.columns.count))
        var out: [CompTeamIndexedColumn] = []
        for ci in lo..<hi {
            out.append(CompTeamIndexedColumn(ci: ci, column: model.columns[ci]))
        }
        return out
    }
}

/// 固定的名字欄：兩列欄頭的高度留白、每位一格（名字＋「E2・借調中・到 1/29」）、最後三格列名
private struct CompTeamNameColumn: View {
    let model: CompetencyTeamModel
    let rows: [CompetencyTeamRow]
    let metrics: CompTeamMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.vSpacing) {
            Color.clear.frame(width: metrics.nameWidth, height: metrics.groupHeight)
            Color.clear.frame(width: metrics.nameWidth, height: metrics.headerHeight)
            ForEach(rows) { r in
                CompTeamNameCell(row: r, width: metrics.nameWidth, height: metrics.rowHeight)
            }
            CompTeamFootLabel(text: model.independentLabel, width: metrics.nameWidth, height: metrics.footHeight)
            CompTeamFootLabel(text: model.trainerLabel, width: metrics.nameWidth, height: metrics.footHeight)
            CompTeamFootLabel(text: "課平均", width: metrics.nameWidth, height: metrics.footHeight)
        }
        .padding(.vertical, 2)
    }
}

private struct CompTeamNameCell: View {
    let row: CompetencyTeamRow
    let width: CGFloat
    let height: CGFloat

    private var displayName: String {
        row.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "這位同仁" : row.name
    }

    /// 第二行：「E2」「E2・借調中・到 1/29」「已轉出」（沒有 nil）
    private var subline: String? {
        if row.archived { return "已轉出" }
        let parts: [String] = [row.gradeShort, row.awayText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "・")
    }

    private var sublineColor: Color {
        (!row.archived && row.awayText != nil) ? Color.orange : Color.secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(displayName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(row.archived ? Color.secondary : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let s = subline {
                Text(s)
                    .font(.caption2)
                    .foregroundStyle(sublineColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: width, height: height, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct CompTeamFootLabel: View {
    let text: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, height: height, alignment: .leading)
    }
}

/// 一組：組名一列（寬＝這組幾欄）＋一欄一個 VStack
private struct CompTeamGroupView: View {
    let group: CompetencyTeamGroupHeader
    let columns: [CompTeamIndexedColumn]
    let rows: [CompetencyTeamRow]
    let metrics: CompTeamMetrics
    let sortColumnId: String?
    let descending: Bool
    let onTapHeader: (String) -> Void
    let onTapCell: (CompetencyTeamCell) -> Void

    private var titleWidth: CGFloat {
        let n: CGFloat = CGFloat(max(columns.count, 1))
        return n * metrics.colWidth + (n - 1) * metrics.hSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.vSpacing) {
            Text(group.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CompetencyPalette.tint(isTrait: group.isTrait))
                .lineLimit(1)
                .frame(width: titleWidth, height: metrics.groupHeight, alignment: .leading)
                .accessibilityLabel(group.fullTitle)
            HStack(alignment: .top, spacing: metrics.hSpacing) {
                ForEach(columns) { c in
                    CompTeamColumnView(column: c.column, ci: c.ci, rows: rows, isTrait: group.isTrait, metrics: metrics,
                                       sortMark: sortMark(c.column.id), onTapHeader: onTapHeader, onTapCell: onTapCell)
                }
            }
        }
    }

    /// 排序中的那一欄 ▼（高到低）／▲（低到高）
    private func sortMark(_ id: String) -> String? {
        guard sortColumnId == id else { return nil }
        return descending ? "▼" : "▲"
    }
}

/// 一欄：欄頭按鈕、每位一格、能獨立／能教人／課平均；整欄紅框（能獨立 ≤ 1）或橘框（能教人 ≤ 1）
private struct CompTeamColumnView: View {
    let column: CompetencyTeamColumn
    let ci: Int
    let rows: [CompetencyTeamRow]
    let isTrait: Bool
    let metrics: CompTeamMetrics
    let sortMark: String?
    let onTapHeader: (String) -> Void
    let onTapCell: (CompetencyTeamCell) -> Void

    private var strokeColor: Color {
        if column.red { return Color.red }
        if column.orange { return Color.orange }
        return Color.clear
    }

    var body: some View {
        VStack(spacing: metrics.vSpacing) {
            CompTeamColumnHeader(column: column, sortMark: sortMark, isTrait: isTrait,
                                 width: metrics.colWidth, height: metrics.headerHeight,
                                 onTap: { onTapHeader(column.id) })
            ForEach(rows) { r in
                rowCell(r)
            }
            CompTeamFootValue(text: column.independentText, color: column.red ? Color.red : Color.primary,
                              bold: column.red, width: metrics.colWidth, height: metrics.footHeight)
            CompTeamFootValue(text: column.trainerText, color: column.orange ? Color.orange : Color.primary,
                              bold: column.orange, width: metrics.colWidth, height: metrics.footHeight)
            CompTeamFootValue(text: column.averageText, color: Color.secondary,
                              bold: false, width: metrics.colWidth, height: metrics.footHeight)
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(strokeColor, lineWidth: 2))
    }

    @ViewBuilder
    private func rowCell(_ r: CompetencyTeamRow) -> some View {
        if ci < r.cells.count {
            CompTeamCellView(cell: r.cells[ci], isTrait: isTrait, archived: r.archived,
                             width: metrics.colWidth, height: metrics.rowHeight,
                             onTap: { onTapCell(r.cells[ci]) })
        } else {
            Color.clear.frame(width: metrics.colWidth, height: metrics.rowHeight)
        }
    }
}

/// 欄頭：項目短名（排序中的加 ▼／▲）；點了照這一欄的分數排
private struct CompTeamColumnHeader: View {
    let column: CompetencyTeamColumn
    let sortMark: String?
    let isTrait: Bool
    let width: CGFloat
    let height: CGFloat
    let onTap: () -> Void

    private var title: String {
        guard let s = sortMark else { return column.itemTitle }
        return column.itemTitle + " " + s
    }

    private var titleColor: Color {
        sortMark == nil ? Color.primary : CompetencyPalette.tint(isTrait: isTrait)
    }

    /// 「Chemical System・緊急應變，能獨立 1 位，能教人 1 位，課平均 2.67，按兩下照分數排」
    private var spoken: String {
        var s: String = column.fullTitle
        if column.requiredCount == 0 {
            s += "，沒有人要學"
        } else {
            s += "，能獨立 \(column.independentCount) 位，能教人 \(column.trainerCount) 位"
        }
        s += column.averageT == nil ? "，課平均還沒有分數" : "，課平均 " + column.averageText
        if let m = sortMark { s += m == "▼" ? "，現在高到低" : "，現在低到高" }
        return s + "，按兩下照分數排"
    }

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(width: width, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
    }
}

/// 能獨立／能教人／課平均那三列的一格
private struct CompTeamFootValue: View {
    let text: String
    let color: Color
    let bold: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Text(text)
            .font(bold ? Font.caption.weight(.bold) : Font.caption)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

/// 一格：數字一定寫、底色五階（深色模式同一個顏色、透明度高一點）、—／·／／、◤ 未達目標（右上紅色小三角）
private struct CompTeamCellView: View {
    let cell: CompetencyTeamCell
    let isTrait: Bool
    let archived: Bool
    let width: CGFloat
    let height: CGFloat
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private static let lightAlpha: [Double] = [0.10, 0.22, 0.36, 0.52, 0.70]
    private static let darkAlpha: [Double] = [0.20, 0.32, 0.46, 0.62, 0.80]

    private var fill: Color {
        switch cell.kind {
        case .value:
            let list: [Double] = colorScheme == .dark ? CompTeamCellView.darkAlpha : CompTeamCellView.lightAlpha
            let tier: Int = max(0, min(cell.tier ?? 0, list.count - 1))
            return CompetencyPalette.tint(isTrait: isTrait).opacity(list[tier])
        case .notRequired:
            return Color(.tertiarySystemFill)
        case .unrated, .na:
            return Color.clear
        }
    }

    /// 未評、不適用：透明底加一圈淡框，跟「—」灰底分得出
    private var borderColor: Color {
        (cell.kind == .unrated || cell.kind == .na) ? Color.secondary.opacity(0.3) : Color.clear
    }

    private var textColor: Color {
        cell.kind == .value ? Color.primary : Color.secondary
    }

    var body: some View {
        if cell.kind == .notRequired {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(cell.spoken)
        } else {
            Button(action: onTap) { face }
                .buttonStyle(.plain)
                .accessibilityLabel(cell.spoken)
        }
    }

    private var face: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 4)
                .fill(fill)
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(borderColor, lineWidth: 1)
            Text(cell.text)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if cell.belowTarget {
                CompTeamCornerMark()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(RoundedRectangle(cornerRadius: 4))
        .opacity(archived ? 0.5 : 1)
    }
}

/// ◤ 未達目標：格子右上角的小直角三角形
private struct CompTeamCornerMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
