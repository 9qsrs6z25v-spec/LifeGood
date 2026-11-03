import SwiftUI

// MARK: - [v25.602 職能雷達 v2] 課的總覽的工具：〔找人〕、課平均雷達、兩人疊圖、〔一次評全課〕（G4 負責）；我自己調動完成那一行（主控寫好）
//（radar/judge.md §4.6 v2 兩人比較、§4.7、§6、§13；radar/build/v2/brief.md §4 G4）
//
// • 規則全部在 CompetencyMath（findPeople、thresholdOptionText、teamPairCards、batchChoices、batchQueue、batchPositionText、batchDoneText）；
//   這個檔只排版。自己的型別一律 CompTeamTool… 前綴、private。
// • 看不擋訂閱；〔一次評全課〕擋訂閱（isPremium／premiumLockAlert）、唯讀時不出現。
// • 〔一次評全課〕照名單一位一頁用現有的 CompetencyRatingSheet（request.batch 帶「2／3　陳怡君」、預設勾的組；onNext＝〔下一位 ›〕）；
//   每一位按儲存才寫（存檔照 CompetencyRatingSheet 原本的：先 dismiss、下一個 runloop 寫 store）；中途關掉，評過的都在。
// • sheet 一律 sheet(item:)＋.appStores()。字不用「他／她」。
// 骨架（主控）：下面三個 View 的名字與參數是跨組契約（CompetencyTeamView 在叫），不准改參數；body 由 G4 寫。
// G4（v25.602）：三個 View 的 body 照 brief §4 G4 寫好。要退回這一件：三個 body 換回 EmptyView()、刪掉 CompTeamTool… 開頭的小型別

// MARK: - 〔找人〕（brief §4 G4-1；主控定案 9）

/// 〔找人〕：「[Slurry System ▾] [緊急應變 ▾] ≥ [4 能教人 ▾]」→「陳怡君 4、林志豪 4」
/// [v25.602 職能雷達 v2] 三個選單（系統、項目、≥ 分數）→ CompetencyMath.findPeople。看不擋訂閱、不寫 store。
/// 選的東西找不到（切區、換部門、改範圍）就用第一組、第一欄、能獨立那一級，所以不會壞。
/// 要退回這一件：body 換回 EmptyView()
struct CompetencyTeamFindCard: View {
    let model: CompetencyTeamModel

    @EnvironmentObject var lifeStore: LifeStore

    /// 選的組、欄（"組|項目"）；nil＝第一組、第一欄
    @State private var groupId: UUID?
    @State private var columnId: String?
    /// ≥ 幾分（nil＝能獨立那一級）；levelRange＝選的時候的範圍（換了範圍就回到能獨立那一級）
    @State private var level: Int?
    @State private var levelRange: CompetencyRange?
    /// > 10 時的數字欄（打字中才用；沒在打字時照 atLeast 寫）
    @State private var levelText: String = ""
    @FocusState private var levelFocused: Bool

    private var group: CompetencyTeamGroupHeader? {
        if let g = groupId, let hit = model.groups.first(where: { $0.id == g }) { return hit }
        return model.groups.first
    }

    private var groupColumns: [CompetencyTeamColumn] {
        guard let g = group else { return [] }
        return CompTeamToolText.columns(of: g, in: model.columns)
    }

    private var column: CompetencyTeamColumn? {
        let cols: [CompetencyTeamColumn] = groupColumns
        if let c = columnId, let hit = cols.first(where: { $0.id == c }) { return hit }
        return cols.first
    }

    private var atLeast: Int {
        if let v = level, levelRange == model.range { return model.range.clamp(v) }
        return model.thresholds.independent
    }

    private var scale: CompetencyScale? {
        let id: String = model.area == .trait ? CompetencySetupBook.traitScaleId : CompetencySetupBook.skillScaleId
        return lifeStore.competencySetup.scale(id)
    }

    private var levelOptions: [Int] { Array(model.range.low...model.range.high) }

    var body: some View {
        if let g = group, let c = column {
            card(g, c)
        }
    }

    private func card(_ g: CompetencyTeamGroupHeader, _ c: CompetencyTeamColumn) -> some View {
        let v: Int = atLeast
        let r: CompetencyFindResult = CompetencyMath.findPeople(model, columnId: c.id, atLeast: v)
        let tint: Color = CompetencyPalette.tint(isTrait: g.isTrait)
        return CompTeamToolCard {
            VStack(alignment: .leading, spacing: 12) {
                CompTeamToolHeader(title: "找人", note: "選系統、項目、幾分以上，看誰做得到")
                pickers(g, c, v, tint: tint)
                CompTeamToolFindResultView(column: c, atLeast: v, result: r)
            }
        }
    }

    /// ≤ 10：一排三個選單（窄的時候換成兩行）；> 10：系統、項目一排，下面 Stepper＋數字欄
    @ViewBuilder
    private func pickers(_ g: CompetencyTeamGroupHeader, _ c: CompetencyTeamColumn, _ v: Int, tint: Color) -> some View {
        if model.range.usesButtons {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    groupMenu(g, tint: tint)
                    itemMenu(c, tint: tint)
                    levelMenu(v, tint: tint)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        groupMenu(g, tint: tint)
                        itemMenu(c, tint: tint)
                    }
                    levelMenu(v, tint: tint)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    groupMenu(g, tint: tint)
                    itemMenu(c, tint: tint)
                }
                levelStepper(v)
            }
        }
    }

    private func groupMenu(_ g: CompetencyTeamGroupHeader, tint: Color) -> some View {
        Menu {
            ForEach(model.groups) { h in
                CompTeamToolMenu.item(h.fullTitle, checked: h.id == g.id) {
                    pickGroup(h.id)
                }
            }
        } label: {
            CompTeamToolChip(title: g.title, tint: tint)
        }
        .accessibilityLabel("系統，" + g.fullTitle)
    }

    private func itemMenu(_ c: CompetencyTeamColumn, tint: Color) -> some View {
        Menu {
            ForEach(groupColumns) { col in
                CompTeamToolMenu.item(col.itemTitle, checked: col.id == c.id) {
                    columnId = col.id
                }
            }
        } label: {
            CompTeamToolChip(title: c.itemTitle, tint: tint)
        }
        .accessibilityLabel("項目，" + c.itemTitle)
    }

    /// ≤ 10 的「≥ 分數」選單：一項寫「3 能獨立」（那一分有名字）／「3」
    private func levelMenu(_ v: Int, tint: Color) -> some View {
        Menu {
            ForEach(levelOptions, id: \.self) { x in
                CompTeamToolMenu.item(optionText(x), checked: x == v) {
                    setLevel(x)
                }
            }
        } label: {
            CompTeamToolChip(title: "≥ " + optionText(v), tint: tint)
        }
        .accessibilityLabel("至少 \(v) 分")
    }

    /// > 10 的「≥ 分數」：數字欄（離開欄位時夾回範圍）＋ Stepper
    private func levelStepper(_ v: Int) -> some View {
        HStack(spacing: 8) {
            Text("≥")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("", text: levelTextBinding)
                .modifier(CompTeamToolNumberFieldStyle())
                .focused($levelFocused)
                .accessibilityLabel("至少幾分")
            if levelFocused {
                Button("好") { levelFocused = false }
                    .buttonStyle(.borderless)
            }
            Spacer(minLength: 8)
            Stepper("至少幾分", value: levelBinding, in: model.range.low...model.range.high)
                .labelsHidden()
        }
        .onChange(of: levelFocused) { _, focused in
            if focused {
                levelText = "\(atLeast)"
            } else {
                commitText()
            }
        }
    }

    private var levelTextBinding: Binding<String> {
        Binding(get: { levelFocused ? levelText : "\(atLeast)" },
                set: { levelText = $0 })
    }

    private var levelBinding: Binding<Int> {
        Binding(get: { atLeast },
                set: { setLevel($0) })
    }

    private func optionText(_ x: Int) -> String {
        CompetencyMath.thresholdOptionText(x, scale: scale, range: model.range)
    }

    private func pickGroup(_ id: UUID) {
        groupId = id
        columnId = nil
    }

    private func setLevel(_ x: Int) {
        let c: Int = model.range.clamp(x)
        level = c
        levelRange = model.range
        levelText = "\(c)"
    }

    /// 數字欄打完：全形數字也認、超出範圍夾回；不是數字就照舊
    private func commitText() {
        guard let p = CompetencyMath.parseInput(levelText, model.range) else { return }
        setLevel(p.value)
    }
}

/// 〔找人〕的結果：「Slurry System・緊急應變 ≥ 4・2 位」＋「陳怡君 4、林志豪 4」
private struct CompTeamToolFindResultView: View {
    let column: CompetencyTeamColumn
    let atLeast: Int
    let result: CompetencyFindResult

    private var caption: String {
        let n: Int = result.personIds.count
        let head: String = column.fullTitle + " ≥ \(atLeast)"
        return n > 0 ? head + "・\(n) 位" : head
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(result.text)
                .font(.subheadline)
                .foregroundStyle(result.personIds.isEmpty ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 課平均雷達＋兩人疊圖（brief §4 G4-2、G4-3；主控定案 10、11）

/// 課平均雷達（每組一張「平均 3 位」）＋兩人疊圖（選兩位：一實線一虛線）
/// [v25.602 職能雷達 v2] 課平均＝model.averageCards（不疊上一次、不疊目標；沒人評過的組 CompetencyMath 已經不畫）；
/// 兩人疊圖＝lifeStore.competencyPairCards（第一位實線、第二位灰色虛線，跟 v1a「上一次」同一套線型，色弱分得出）。
/// 看不擋訂閱、不寫 store。要退回這一件：body 換回 EmptyView()
struct CompetencyTeamRadarSection: View {
    let model: CompetencyTeamModel
    /// 人才矩陣現在的名單（兩人疊圖要讀這兩位的評分）
    let members: [Subordinate]

    @EnvironmentObject var lifeStore: LifeStore

    /// 兩人疊圖選的兩位（不在名單裡了就當沒選）；〔疊在一起看〕展開
    @State private var pickA: UUID?
    @State private var pickB: UUID?
    @State private var showsPair = false

    /// 能選的人：在職的（已轉出不列）
    private var candidates: [CompetencyTeamRow] { model.rows.filter { !$0.archived } }
    private var candidateIds: [UUID] { candidates.map { $0.id } }
    private var personA: CompetencyTeamRow? { CompTeamToolText.row(pickA, in: candidates) }
    private var personB: CompetencyTeamRow? { CompTeamToolText.row(pickB, in: candidates) }

    private var pairReady: Bool {
        guard let a = personA, let b = personB else { return false }
        return a.id != b.id
    }

    private var tint: Color { CompetencyPalette.tint(isTrait: model.area == .trait) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !model.averageCards.isEmpty {
                averageBlock
            }
            if candidates.count >= 2 {
                pairBlock
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: candidateIds) { _, _ in
            // 換部門、有人轉出：選的人不在名單裡了就收起來
            if !pairReady { showsPair = false }
        }
    }

    private var averageBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            CompTeamToolHeader(title: "課平均", note: "不用學、還沒評、不適用的不算；已轉出不算")
            CompTeamToolChartGrid(cards: model.averageCards, showPrevious: false)
        }
    }

    private var pairBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            CompTeamToolHeader(title: "兩人疊圖", note: "第一位實線、第二位灰色虛線")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    pickerRow
                    toggleButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    pickerRow
                    toggleButton
                }
            }
            if showsPair && pairReady {
                pairCardsView
            }
        }
    }

    private var pickerRow: some View {
        HStack(spacing: 6) {
            personMenu(first: true)
            Text("比")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            personMenu(first: false)
        }
    }

    private func personMenu(first: Bool) -> some View {
        let chosen: CompetencyTeamRow? = first ? personA : personB
        let otherId: UUID? = first ? personB?.id : personA?.id
        let options: [CompetencyTeamRow] = candidates.filter { $0.id != otherId }
        let chipTint: Color = first ? tint : Color.gray
        let who: String = first ? "第一位，實線，" : "第二位，灰色虛線，"
        return Menu {
            ForEach(options) { row in
                CompTeamToolMenu.item(row.name, checked: row.id == chosen?.id) {
                    pick(row.id, first: first)
                }
            }
        } label: {
            CompTeamToolChip(title: chosen?.name ?? "選一位", tint: chipTint)
        }
        .accessibilityLabel(who + (chosen?.name ?? "還沒選"))
    }

    private var toggleButton: some View {
        Button {
            showsPair.toggle()
        } label: {
            Text(showsPair && pairReady ? "收起" : "疊在一起看")
        }
        .buttonStyle(.bordered)
        .disabled(!pairReady)
    }

    private var pairCardsView: some View {
        CompTeamToolChartGrid(cards: pairCardModels, showPrevious: true)
    }

    private var pairCardModels: [CompetencyChartModel] {
        guard let a = personA, let b = personB, a.id != b.id else { return [] }
        return lifeStore.competencyPairCards(members: members, a: a.id, b: b.id, area: model.area)
    }

    private func pick(_ id: UUID, first: Bool) {
        if first {
            pickA = id
        } else {
            pickB = id
        }
    }
}

/// 雷達卡一格一張（iPhone 一欄、iPad 兩三欄）；空的時候寫一行
private struct CompTeamToolChartGrid: View {
    let cards: [CompetencyChartModel]
    let showPrevious: Bool

    var body: some View {
        if cards.isEmpty {
            Text("這兩位在這一區都不用學")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: CompTeamToolText.gridColumns, alignment: .leading, spacing: 12) {
                ForEach(cards) { c in
                    CompetencyChartCard(model: c, showPrevious: showPrevious)
                }
            }
        }
    }
}

// MARK: - 〔一次評全課〕（brief §4 G4-4；主控定案 12）

/// 〔一次評全課〕按鈕＋選組＋一位一頁評分（擋訂閱）
/// [v25.602 職能雷達 v2] 唯讀、沒有能選的組時不出現。選組 → 照名單一位一頁開現有的 CompetencyRatingSheet
///（request.batch 帶「2／3　陳怡君」、預設勾的組；onNext＝〔下一位 ›〕）。存檔在 CompetencyRatingSheet 自己（先 dismiss、下一個 runloop 寫 store），
/// 這裡只數存了幾位、換下一位；中途關掉，評過的都在。名單在按〔開始〕那一刻定好。要退回這一件：body 換回 EmptyView()
struct CompetencyTeamBatchButton: View {
    let members: [Subordinate]

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager

    @State private var showPremiumAlert = false
    /// 選組 sheet、一位一頁的評分 sheet（sheet(item:)）
    @State private var setupRequest: CompTeamToolBatchSetupRequest?
    @State private var current: CompetencyRatingRequest?
    /// 這一批：名單（按〔開始〕那一刻定好）、預設勾的組、評到第幾位、存了幾位
    @State private var queue: [CompetencyTeamPerson] = []
    @State private var groupIds: Set<UUID> = []
    @State private var index = 0
    @State private var saved = 0
    /// 這一頁關掉後要換下一位（按了〔儲存〕或〔下一位 ›〕）；沒有＝〔取消〕＝整批結束
    @State private var advance = false
    @State private var running = false
    /// 選組 sheet 按了〔開始〕：等那一頁關完（onDismiss）才開第一位，免得兩張 sheet 疊在一起開不出來
    @State private var startPending = false
    /// 結束後的底部小提示「評好 2／3 位」（3 秒後消失）
    @State private var doneText: String?
    @State private var toastTask: Task<Void, Never>?

    private var showsButton: Bool {
        !lifeStore.competencyReadOnly && !lifeStore.competencyBatchChoices.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsButton || running {
                batchButton
            }
            if let t = doneText {
                CompTeamToolToast(text: t)
            }
        }
        .sheet(item: $setupRequest, onDismiss: { setupClosed() }) { r in
            CompTeamToolBatchSetup(members: members, choices: r.choices, onStart: { ids, q in begin(ids, q) })
                .appStores()
        }
        .sheet(item: $current, onDismiss: { sheetClosed() }) { r in
            CompetencyRatingSheet(request: r, onSaved: { _ in batchSaved() }, onNext: { advance = true })
                .appStores()
        }
        .premiumLockAlert(isPresented: $showPremiumAlert)
        .onDisappear { toastTask?.cancel() }
    }

    private var batchButton: some View {
        Button {
            tapped()
        } label: {
            Label("一次評全課", systemImage: "list.bullet.clipboard")
        }
        .buttonStyle(.bordered)
        .disabled(running)
        .accessibilityHint("選要評的組，照名單一位一頁評分")
    }

    private func tapped() {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        guard !lifeStore.competencyReadOnly, !running else { return }
        let choices: [CompetencyBatchChoice] = lifeStore.competencyBatchChoices
        guard !choices.isEmpty else { return }
        setupRequest = CompTeamToolBatchSetupRequest(choices: choices)
    }

    /// 選組 sheet 按〔開始〕（那一頁已經 dismiss）：名單定好，等選組 sheet 關完（setupClosed）再開第一位
    private func begin(_ ids: Set<UUID>, _ q: [CompetencyTeamPerson]) {
        guard !q.isEmpty else { return }
        toastTask?.cancel()
        doneText = nil
        queue = q
        groupIds = ids
        index = 0
        saved = 0
        advance = false
        running = true
        startPending = true
    }

    /// 選組 sheet 關完：按了〔開始〕才開第一位（左上〔取消〕、往下滑關掉＝什麼都不做）
    private func setupClosed() {
        guard startPending else { return }
        startPending = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            openCurrent(at: 0)
        }
    }

    /// 開第 start 位（中途被別台刪掉的人跳過）
    private func openCurrent(at start: Int) {
        guard running else { return }
        let list: [CompetencyTeamPerson] = queue
        var i: Int = start
        while i < list.count && !personExists(list[i].id) {
            i += 1
        }
        index = i
        guard i < list.count else {
            finish()
            return
        }
        let p: CompetencyTeamPerson = list[i]
        let n: Int = list.count
        let b = CompetencyRatingBatch(positionText: CompetencyMath.batchPositionText(index: i, total: n, name: p.name),
                                      groupIds: groupIds, hasNext: i + 1 < n)
        current = CompetencyRatingRequest(subordinateId: p.id, batch: b)
    }

    private func personExists(_ id: UUID) -> Bool {
        lifeStore.subordinates.contains { $0.id == id }
    }

    /// 這一位按了〔儲存〕（CompetencyRatingSheet 已經 dismiss、在下一個 runloop 寫好了）
    private func batchSaved() {
        saved += 1
        advance = true
    }

    /// 一頁關掉：等關完（onSaved 那個 runloop 也跑完）再決定換下一位或結束
    private func sheetClosed() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard running else { return }
            let next: Int = index + 1
            if advance && next < queue.count {
                advance = false
                openCurrent(at: next)
            } else {
                finish()
            }
        }
    }

    private func finish() {
        let text: String = CompetencyMath.batchDoneText(saved: saved, total: queue.count)
        running = false
        advance = false
        startPending = false
        current = nil
        queue = []
        showToast(text)
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { doneText = text }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { doneText = nil }
        }
    }
}

/// 打開選組 sheet（sheet(item:) 用；能選的組在按下那一刻定好）
private struct CompTeamToolBatchSetupRequest: Identifiable {
    let id = UUID()
    let choices: [CompetencyBatchChoice]
}

/// 選組 sheet：一組一個開關（預設全開）＋「要評 3 位：王小明、陳怡君、林志豪」；右上〔開始〕、左上〔取消〕
private struct CompTeamToolBatchSetup: View {
    let members: [Subordinate]
    let choices: [CompetencyBatchChoice]
    /// 選的組、名單（按〔開始〕那一刻定好）；呼叫前已經 dismiss
    let onStart: (Set<UUID>, [CompetencyTeamPerson]) -> Void

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    @State private var picked: Set<UUID>

    init(members: [Subordinate], choices: [CompetencyBatchChoice],
         onStart: @escaping (Set<UUID>, [CompetencyTeamPerson]) -> Void) {
        self.members = members
        self.choices = choices
        self.onStart = onStart
        _picked = State(initialValue: Set(choices.map { $0.id }))
    }

    private var queue: [CompetencyTeamPerson] {
        lifeStore.competencyBatchQueue(members: members, groupIds: picked)
    }

    var body: some View {
        let q: [CompetencyTeamPerson] = queue
        return NavigationStack {
            CompTeamToolBatchForm(choices: choices, picked: $picked, queueText: CompTeamToolText.queueLine(q))
                .navigationTitle("一次評全課")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarItems(q) }
        }
    }

    @ToolbarContentBuilder
    private func toolbarItems(_ q: [CompetencyTeamPerson]) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("開始") { start(q) }
                .disabled(q.isEmpty)
        }
    }

    private func start(_ q: [CompetencyTeamPerson]) {
        guard !q.isEmpty else { return }
        let ids: Set<UUID> = picked
        let callback: (Set<UUID>, [CompetencyTeamPerson]) -> Void = onStart
        dismiss()
        callback(ids, q)
    }
}

/// 選組 sheet 的表單
private struct CompTeamToolBatchForm: View {
    let choices: [CompetencyBatchChoice]
    @Binding var picked: Set<UUID>
    let queueText: String

    var body: some View {
        Form {
            Section {
                ForEach(choices) { c in
                    Toggle(isOn: binding(c.id)) {
                        CompTeamToolChoiceLabel(choice: c)
                    }
                }
            } header: {
                Text("要評的組")
            } footer: {
                Text("每一位的評分畫面「這次評」預設只勾這幾組，那一頁還可以改。")
            }
            Section {
                Text(queueText)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } footer: {
                Text("照人才矩陣的名單一位一頁；每一位按〔儲存〕才存，中途關掉，評過的都在。已轉出的不評。")
            }
        }
    }

    private func binding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { picked.contains(id) },
                set: { on in
                    var s: Set<UUID> = picked
                    if on {
                        s.insert(id)
                    } else {
                        s.remove(id)
                    }
                    picked = s
                })
    }
}

/// 一組的名字（人格紫點、系統藍點）
private struct CompTeamToolChoiceLabel: View {
    let choice: CompetencyBatchChoice

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(CompetencyPalette.tint(isTrait: choice.isTrait))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(choice.title)
        }
    }
}

// MARK: - 這個檔自己的小零件（CompTeamTool… 前綴、private）

/// 白卡（跟雷達卡同一套：內距 16、圓角 16、細框）
private struct CompTeamToolCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 1))
    }
}

/// 一段的標題＋小字
private struct CompTeamToolHeader: View {
    let title: String
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if let n = note {
                Text(n)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 選單的膠囊「Gas ▾」
private struct CompTeamToolChip: View {
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(tint)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// 底部小提示「評好 2／3 位」
private struct CompTeamToolToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground), in: Capsule())
    }
}

/// > 10 時的數字欄樣子（照設定頁 CompSetupRangeRow 的數字欄）
private struct CompTeamToolNumberFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(.body, design: .rounded).weight(.semibold))
            .frame(width: 56)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// 選單一項：選中的打勾（跟 v1b〔目標 E2 ▾〕同一套寫法）
private enum CompTeamToolMenu {
    @ViewBuilder
    static func item(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        if checked {
            Button(action: action) {
                Label(title, systemImage: "checkmark")
            }
        } else {
            Button(title, action: action)
        }
    }
}

/// 這個檔自己的小函式（純函式；下一版主控要搬就搬到 CompetencyMath）
private enum CompTeamToolText {
    /// 雷達卡：iPhone 一欄、iPad 兩三欄
    static let gridColumns: [GridItem] = [GridItem(.adaptive(minimum: 320), spacing: 12)]

    /// 一組的欄（columns[start ..< start + count]，夾在範圍裡）
    static func columns(of g: CompetencyTeamGroupHeader, in cols: [CompetencyTeamColumn]) -> [CompetencyTeamColumn] {
        let lo: Int = max(0, min(g.start, cols.count))
        let hi: Int = max(lo, min(g.start + g.count, cols.count))
        return Array(cols[lo..<hi])
    }

    /// 名單裡找這一位（不在了 nil）
    static func row(_ id: UUID?, in rows: [CompetencyTeamRow]) -> CompetencyTeamRow? {
        guard let id else { return nil }
        return rows.first { $0.id == id }
    }

    /// 選組 sheet 下面那一行「要評 3 位：王小明、陳怡君、林志豪」
    static func queueLine(_ q: [CompetencyTeamPerson]) -> String {
        if q.isEmpty { return "選的組裡沒有要評的人" }
        return "要評 \(q.count) 位：" + q.map { $0.name }.joined(separator: "、")
    }
}

// MARK: - 我自己調動完成那一頁的一行（judge §2.6、§5「v2 起調動完成時提示一次〔職能項目設定〕」；主控寫好，G4 不用改）

/// 打開職能項目設定（sheet(item:) 用）
private struct CompSelfMoveSetupRequest: Identifiable {
    let id = UUID()
}

/// 「新單位要學的系統不一樣嗎？〔職能項目設定〕」：只有已經設過職能項目時才出現（OrgSelfMoveDoneStep 叫這一行）
struct CompetencySelfMoveHint: View {
    @EnvironmentObject var lifeStore: LifeStore
    @State private var request: CompSelfMoveSetupRequest?

    var body: some View {
        if lifeStore.competencySetup.isConfigured {
            VStack(spacing: 8) {
                Text("新單位要學的系統不一樣嗎？")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    request = CompSelfMoveSetupRequest()
                } label: {
                    Label("職能項目設定", systemImage: "graduationcap.fill")
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .sheet(item: $request) { _ in
                NavigationStack {
                    CompetencySetupView(showsDoneButton: true)
                }
                .appStores()
            }
        }
    }
}
