import SwiftUI

// MARK: - [v25.600 職能雷達 v1a-2] 評分紀錄明細、點一格的歷史（G1 負責；radar/judge.md §4.3④「點雷達頂點、軸名或橫條那一列」、
//  §3.4 停用的項目在舊紀錄裡、§3.7-10 評分紀錄可以點開看、改、刪、§6、§13；radar/build/v1a-2/brief.md §4 G1）
//
// • 字、數字、雷達全部照 CompetencyMath.sessionDetails／cellHistory 算好的畫；body 裡不寫長運算式。
// • §13 追加：每一格的評語不做——這兩頁一個字的評語都不顯示、沒有評語圖示（總評照 v1a-1 留著）。
// • 看不擋；〔改分數〕〔改日期〕〔刪除〕要訂閱（isPremium／premiumLockAlert）、唯讀時不出現。已轉出的同仁舊紀錄照樣能改。
// • sheet 一律 sheet(item:)＋.appStores()；dismiss 後寫 store 放下一個 runloop。
// 骨架（主控）：型別名與 init 參數是跨組契約，不准改；body 由 G1 換成真的。自己加的型別一律 CompHist… 前綴、private。

/// 打開一天的評分紀錄明細（sheet(item:) 用）
struct CompetencyRecordRequest: Identifiable {
    let id = UUID()
    let subordinateId: UUID
    let dayKey: String
}

/// 打開點一格的歷史（sheet(item:) 用）
struct CompetencyCellHistoryRequest: Identifiable {
    let id = UUID()
    let subordinateId: UUID
    let groupId: UUID
    let itemId: UUID
}

/// 一天的評分紀錄明細（唯讀雷達畫當時的樣子；同一天兩張時可以切）＋〔改分數〕〔改日期〕〔刪除〕
struct CompetencyRecordDetailView: View {
    let subordinateId: UUID
    let dayKey: String

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// 現在看哪一天（改日期成功後換成新的那天）
    @State private var day: String
    /// 同一天兩張時選哪一張（記評分 id，不記第幾張：改過一張之後順序會換）
    @State private var pickId: UUID?
    @State private var ratingRequest: CompetencyRatingRequest?
    @State private var moveRequest: CompHistMoveRequest?
    @State private var pendingDelete: CompHistDeleteTarget?
    @State private var showDeleteConfirm = false
    @State private var showPremiumAlert = false
    /// 頁內一行結果（「已改成 10/31」綠字；改不成紅字）
    @State private var resultLine: CompHistResultLine?

    init(subordinateId: UUID, dayKey: String) {
        self.subordinateId = subordinateId
        self.dayKey = dayKey
        _day = State(initialValue: dayKey)
    }

    private var details: [CompetencySessionDetailModel] {
        CompetencyMath.sessionDetails(dayKey: day,
                                      sessions: lifeStore.competencySessions(of: subordinateId),
                                      setup: lifeStore.competencySetup)
    }

    /// 選的那一張（不在了就第一張）
    private func current(in list: [CompetencySessionDetailModel]) -> CompetencySessionDetailModel? {
        if let id = pickId, let d = list.first(where: { $0.id == id }) { return d }
        return list.first
    }

    private var canEdit: Bool { !lifeStore.competencyReadOnly }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("評分紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .modifier(CompHistDetailSheets(subordinateId: subordinateId,
                                       ratingRequest: $ratingRequest,
                                       moveRequest: $moveRequest,
                                       onMoved: moveFinished))
        .alert(pendingDelete?.title ?? "", isPresented: $showDeleteConfirm, presenting: pendingDelete) { t in
            Button("刪除", role: .destructive) { deleteNow(t.id) }
            Button("取消", role: .cancel) {}
        } message: { t in
            Text(t.message)
        }
        .premiumLockAlert(isPresented: $showPremiumAlert)
    }

    @ViewBuilder
    private var content: some View {
        let list: [CompetencySessionDetailModel] = details
        VStack(spacing: 14) {
            if let r = resultLine {
                CompHistResultView(line: r)
            }
            if list.count > 1, let cur = current(in: list) {
                CompHistPickerBlock(list: list, selected: cur.id, onPick: { pickId = $0 })
            }
            if let d = current(in: list) {
                CompHistDetailBlock(detail: d, regular: horizontalSizeClass == .regular)
                if canEdit {
                    CompHistActions(onRate: { startRate(d) }, onMove: { startMove(d) }, onDelete: { askDelete(d) })
                }
            } else {
                CompHistGoneView()
            }
        }
    }

    // MARK: 動作（看不擋、動手才擋）

    private func startRate(_ d: CompetencySessionDetailModel) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        resultLine = nil
        ratingRequest = CompetencyRatingRequest(subordinateId: subordinateId, dayKey: d.dayKey, sessionId: d.id)
    }

    private func startMove(_ d: CompetencySessionDetailModel) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        resultLine = nil
        moveRequest = CompHistMoveRequest(sessionId: d.id, dayKey: d.dayKey)
    }

    private func askDelete(_ d: CompetencySessionDetailModel) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        pendingDelete = CompHistDeleteTarget(id: d.id, title: d.deleteTitle, message: d.deleteMessage)
        showDeleteConfirm = true
    }

    /// 刪完整頁關掉（同一天還有別張也一起關，簡單）；先 dismiss，下一個 runloop 再寫 store
    private func deleteNow(_ id: UUID) {
        let store: LifeStore = lifeStore
        pendingDelete = nil
        dismiss()
        DispatchQueue.main.async {
            store.deleteCompetencySession(id)
        }
    }

    /// 改日期的小表單關掉、寫完之後（problem nil＝成功）
    private func moveFinished(_ sessionId: UUID, _ key: String, _ problem: String?) {
        if let p = problem {
            resultLine = CompHistResultLine(text: p, ok: false)
            return
        }
        day = key
        pickId = sessionId
        resultLine = CompHistResultLine(text: "已改成 " + CompetencyMath.shortDay(key), ok: true)
    }
}

/// 點一格的歷史（.medium）：現在、每一分的名字（有才有）、歷史、在其他系統
struct CompetencyCellHistorySheet: View {
    let subordinateId: UUID
    let groupId: UUID
    let itemId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    private var model: CompetencyCellHistoryModel {
        CompetencyMath.cellHistory(groupId: groupId, itemId: itemId,
                                   setup: lifeStore.competencySetup,
                                   subordinateId: subordinateId,
                                   sessions: lifeStore.competencySessions(of: subordinateId))
    }

    private var tint: Color {
        CompetencyPalette.tint(isTrait: groupId == CompetencySetupBook.traitGroupId)
    }

    var body: some View {
        let m: CompetencyCellHistoryModel = model
        return NavigationStack {
            CompHistCellList(model: m, tint: tint)
                .navigationTitle(m.title)
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

// MARK: - 明細頁的小零件（自己的型別一律 CompHist… 前綴、private）

/// 〔改日期〕小表單請求
private struct CompHistMoveRequest: Identifiable {
    let id = UUID()
    let sessionId: UUID
    let dayKey: String
}

/// 〔刪除這次評分〕要刪的那一張（確認框的字先存起來）
private struct CompHistDeleteTarget {
    let id: UUID
    let title: String
    let message: String
}

/// 頁內一行結果
private struct CompHistResultLine: Equatable {
    let text: String
    let ok: Bool
}

/// 〔改分數〕評分畫面、〔改日期〕小表單（sheet(item:)＋.appStores()）
private struct CompHistDetailSheets: ViewModifier {
    let subordinateId: UUID
    @Binding var ratingRequest: CompetencyRatingRequest?
    @Binding var moveRequest: CompHistMoveRequest?
    let onMoved: (UUID, String, String?) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $ratingRequest) { r in
                CompetencyRatingSheet(request: r, onSaved: nil)
                    .appStores()
            }
            .sheet(item: $moveRequest) { r in
                CompHistMoveSheet(subordinateId: subordinateId, request: r, onDone: onMoved)
                    .appStores()
            }
    }
}

private struct CompHistResultView: View {
    let line: CompHistResultLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: line.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(line.ok ? Color.green : Color.red)
            Text(line.text)
                .font(.footnote)
                .foregroundStyle(line.ok ? Color.green : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }
}

/// 同一天兩張以上：一行說明＋segmented「第 1 張｜第 2 張」
private struct CompHistPickerBlock: View {
    let list: [CompetencySessionDetailModel]
    let selected: UUID
    let onPick: (UUID) -> Void

    private var countLine: String {
        let n: Int = list.count
        let who: String = n == 2 ? "（兩台各評了一次）" : "（不同的裝置各評了一次）"
        return "這一天有 \(n) 張" + who
    }

    private var binding: Binding<UUID> {
        Binding(get: { selected }, set: { onPick($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(countLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("第幾張", selection: binding) {
                ForEach(list.indices, id: \.self) { i in
                    Text("第 \(i + 1) 張").tag(list[i].id)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 20)
    }
}

/// 一張的內容：標題、資訊行、總評、唯讀雷達（§13：每一格的評語一個字都不顯示）
private struct CompHistDetailBlock: View {
    let detail: CompetencySessionDetailModel
    let regular: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CompHistTitleLines(title: detail.title, lines: detail.infoLines)
            if let n = detail.note {
                CompHistNoteCard(note: n)
            }
            CompHistGrid(cards: detail.cards, regular: regular)
        }
    }
}

private struct CompHistTitleLines: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

/// 總評（一次評分一段；v1a-1 就有）
private struct CompHistNoteCard: View {
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("總評")
                .font(.subheadline.weight(.bold))
            Text(note)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 1))
        .padding(.horizontal)
    }
}

/// 唯讀雷達：iPad（.regular）兩欄、iPhone 一欄（照〔職能〕分頁的寫法；不疊上一次、不能點）
private struct CompHistGrid: View {
    let cards: [CompetencyChartModel]
    let regular: Bool

    /// [v1a-2 裁定] 固定兩欄（跟〔職能〕分頁 CompTabGrid 一樣；原本 .adaptive(minimum: 320) 寬度不同會變 1 或 3～4 欄）
    private static let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16, alignment: .top),
        GridItem(.flexible(), spacing: 16, alignment: .top)
    ]

    var body: some View {
        if regular {
            LazyVGrid(columns: Self.columns, alignment: .center, spacing: 16) {
                ForEach(cards) { c in
                    CompetencyChartCard(model: c, showPrevious: false, onTapAxis: nil)
                        .frame(maxWidth: 360)
                }
            }
            .padding(.horizontal)
        } else {
            VStack(spacing: 14) {
                ForEach(cards) { c in
                    CompetencyChartCard(model: c, showPrevious: false, onTapAxis: nil)
                        .padding(.horizontal)
                }
            }
        }
    }
}

/// 〔改分數〕〔改日期〕〔刪除這次評分〕（唯讀時整排不出現；擋訂閱在明細頁的動作裡）
private struct CompHistActions: View {
    let onRate: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                CompHistActionButton(title: "改分數", icon: "square.and.pencil", color: CompetencyPalette.trait,
                                     action: onRate)
                CompHistActionButton(title: "改日期", icon: "calendar", color: CompetencyPalette.system,
                                     action: onMove)
            }
            Button(role: .destructive, action: onDelete) {
                Text("刪除這次評分")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }
}

private struct CompHistActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 這一天一張都不在了（別台刪了、剛刪完、搬走了）
private struct CompHistGoneView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("這一天的評分已經不在了")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 〔改日期〕小表單

/// 「2026-10-30」→ 那一天中午（DatePicker 用；中午避開日光節約換日）。
/// [v25.600 v1a-2] 跟評分畫面的 compRatingDate 一樣（那支是 fileprivate）；下一版主控再搬進 CompetencyMath。
fileprivate func compHistNoonDate(_ key: String) -> Date? {
    guard let p = CompetencyMath.parseDay(key) else { return nil }
    var c = DateComponents()
    c.year = p.y
    c.month = p.m
    c.day = p.d
    c.hour = 12
    return Calendar.current.date(from: c)
}

/// 只改這一張算在哪一天（分數不動）。那天已經有一張、晚於今天：表單裡紅字、不關。
private struct CompHistMoveSheet: View {
    let subordinateId: UUID
    let sessionId: UUID
    let onDone: (UUID, String, String?) -> Void
    /// [v1a-2 裁定] 打開時 DatePicker 停的那一天。那一張的日子在這台晚於今天（別的時區評的）時是今天：
    /// 沒動就按〔完成〕不搬（不然會不小心搬到今天）
    let startKey: String

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var problem: String?

    init(subordinateId: UUID, request: CompHistMoveRequest, onDone: @escaping (UUID, String, String?) -> Void) {
        self.subordinateId = subordinateId
        self.sessionId = request.sessionId
        self.onDone = onDone
        // 今天就用現在（中午 12 點在上午會晚於 DatePicker 的上限 ...Date()）；以前的日子用那天中午
        //（那一張的日子在這台時區晚於今天——別的時區評的——也用現在：DatePicker 不能超過 ...Date()；照評分畫面 key < t）
        let today: String = CompetencyMath.dayKey(Date())
        let start: Date = request.dayKey < today ? (compHistNoonDate(request.dayKey) ?? Date()) : Date()
        self.startKey = CompetencyMath.dayKey(start)
        _date = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日期", selection: $date, in: ...Date(), displayedComponents: .date)
                } footer: {
                    Text("分數不變，只改這一次評分算在哪一天。")
                }
                if let p = problem {
                    Section {
                        Text(p)
                            .font(.subheadline)
                            .foregroundStyle(Color.red)
                    }
                }
            }
            .navigationTitle("改日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { finish() }
                }
            }
            .onChange(of: date) {
                problem = nil
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// 先在表單裡判斷（有問題紅字、不關）；可以 → dismiss → 下一個 runloop 寫 store
    private func finish() {
        let key: String = CompetencyMath.dayKey(date)
        guard let s = lifeStore.competencyRatings.session(sessionId), s.isLive else {
            problem = "找不到這次評分"
            return
        }
        if key == s.dayKey || key == startKey {
            dismiss()
            return
        }
        let sessions: [CompetencySession] = lifeStore.competencySessions(of: subordinateId)
        let today: String = CompetencyMath.dayKey(Date())
        if let p = CompetencyMath.moveSessionProblem(s, to: key, sessions: sessions, today: today) {
            problem = p
            return
        }
        let store: LifeStore = lifeStore
        let id: UUID = sessionId
        let done = onDone
        dismiss()
        DispatchQueue.main.async {
            let r: String? = store.moveCompetencySession(id, toDay: key)
            done(id, key, r)
        }
    }
}

// MARK: - 點一格的歷史（§13：沒有評語）

private struct CompHistCellList: View {
    let model: CompetencyCellHistoryModel
    let tint: Color

    var body: some View {
        List {
            Section {
                Text(model.nowLine)
                    .font(.headline)
                if let a = model.archivedNote {
                    Text(a)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !model.levels.isEmpty {
                Section("每一分的名字") {
                    ForEach(model.levels) { lv in
                        CompHistLevelRowView(level: lv, tint: tint)
                    }
                }
            }
            Section("歷史") {
                CompHistRows(rows: model.rows)
            }
            if let o = model.otherLine {
                Section {
                    Text(o)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// 「●4　能教人」（現在這一分主題色、實心點；其他空心）
private struct CompHistLevelRowView: View {
    let level: CompetencyLevelRow
    let tint: Color

    private var spoken: String {
        let base: String = level.name.isEmpty ? "\(level.id) 分" : "\(level.id) 分 \(level.name)"
        return level.isCurrent ? base + "，現在" : base
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: level.isCurrent ? "circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(level.isCurrent ? tint : Color.secondary)
            Text("\(level.id)")
                .font(.subheadline.weight(level.isCurrent ? .bold : .regular))
                .monospacedDigit()
                .frame(minWidth: 28, alignment: .leading)
            if !level.name.isEmpty {
                Text(level.name)
                    .font(.subheadline)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(level.isCurrent ? tint : Color.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

private struct CompHistRows: View {
    let rows: [CompetencyHistoryRow]

    var body: some View {
        if rows.isEmpty {
            Text("還沒評過")
                .foregroundStyle(.secondary)
        } else {
            ForEach(rows) { r in
                CompHistRowView(row: r)
            }
        }
    }
}

/// 左「10/30（五）」、右「4」；第二行小字「原 1–5 的 4（當時：能教人）」
private struct CompHistRowView: View {
    let row: CompetencyHistoryRow

    private var spoken: String {
        var s: String = row.dayText + "，" + row.valueText
        if let d = row.detailText { s += "，" + d }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(row.dayText)
                    .font(.subheadline)
                Spacer(minLength: 8)
                Text(row.valueText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            if let d = row.detailText {
                Text(d)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}
