import SwiftUI

// MARK: - [v25.600 職能雷達 v1a-2] 每一分的名字（G4 負責；radar/judge.md §4.4 每一分的名字頁、§3.3、§13；radar/build/v1a-2/brief.md §4 G4）
//
// • §13：出廠空的；〔套用範本 ▾〕OJT 五級／人格五級／ILUO 四級讓使用者自己選；〔先只用數字〕清掉。
// • 每一級一列「3　[能獨立]」（最多 4 字，按鈕下面用）；超過 11 級（例 0–100）不設名字，只寫一句說明。
// • 草稿在這一頁（@State），按〔完成〕才寫（setCompetencyLevelNames）；沒訂閱看得到、改要訂閱。
// • 〔套用範本 ▾〕放在頁面最上面一節（不放工具列：標題「本職學能・每一分的名字」在 SE 上加兩顆按鈕會被擠掉）。
// • 推進來的：左上是系統的返回鍵，沒按〔完成〕就不存（footer 寫）；sheet 打開（showsDoneButton）：左上〔取消〕、有改時不能往下滑關掉。
// • 範本的字只在 CompetencyMath.levelTemplates（這個檔不寫範本裡的名字）。
// 要退回這一件：把這個檔換回骨架（CompetencyLevelNamesView 只留 Form＋levelNamesSummary＋標題）。
// 骨架（主控）：型別名與 init 參數是跨組契約，不准改；body 由 G4 換成真的。自己加的型別一律 CompNames… 前綴、private。
//
// MARK: [v25.601 職能雷達 v1b] 每一分的說明（G4；radar/build/v1b/brief.md §1-4、§4 G4；judge §13）
// • 名字頁每一級多一欄「說明」（最多 30 字，CompetencyMath.levelDetailMax）：草稿 details，〔完成〕名字＋說明一起寫
//   （setCompetencyLevelNames(scaleId:names:details:)）。出廠空的；〔套用範本〕名字＋說明一起填進草稿；〔先只用數字〕兩個都清。
// • 最下面一節「每一項自己的說明」：人格列人格項目；本職列共用學習項目＋每個系統自己的項目 → 推進 CompetencyItemDetailsView（看不擋）。
// • CompetencyItemDetailsView(itemId:showsDoneButton:)（internal，系統頁也用）：項目自己的每一分說明蓋過通用說明；
//   placeholder＝通用說明；超過 11 級一句話；〔完成〕擋訂閱 → dismiss 後下一個 runloop setCompetencyItemLevelDetails。
// • 超過 11 級（例 0–100）不做每一分的名字、說明（namesAllowed）。範本的字照舊只在 CompetencyMath.levelTemplates。
// 要退回這一件：刪掉 details 草稿、CompNamesRow 的說明欄、itemSection、CompetencyItemDetailsView 與 CompNamesItem…／CompNamesDetailRow，
// done() 改回 setCompetencyLevelNames(scaleId:names:)（系統頁的〔說明〕也要一起退）。
//
// MARK: [v25.602 職能雷達 v2] 項目自己的說明照舊範圍寫的（G3；radar/build/v2/brief.md §1-6、§4 G3-C；v1b adjudicate 待辦第 1 件）
// • 改範圍時共用層把還沒標範圍的說明標成舊範圍（CompetencyMath.applyingRangeChange）；照新範圍評分時不顯示，改回原範圍就回來。
// • CompetencyItemDetailsView 最上面多一節：橘字 itemDetailsOldText「這些說明是照 1–5 寫的…」＋〔清掉重寫〕
//  （先擋唯讀與訂閱 → 確認「清掉值班技能自己的說明？」→ 下一個 runloop clearCompetencyItemLevelDetails、草稿清空；不關頁）。
// • 在新範圍改一句按〔完成〕＝整份改標新範圍（setCompetencyItemLevelDetails 自己標，這個檔不用多寫）。
// 要退回這一件：刪 oldRangeSection、askClearDetails／clearDetailsNow 與 CompNamesOldRangeRow，sections 裡那一行。

struct CompetencyLevelNamesView: View {
    /// "trait"（人格特質）／"skill"（本職學能）
    let scaleId: String
    /// 從改範圍那一問用 sheet 打開時：右上〔完成〕會關掉這一頁（從設定頁推進來時〔完成〕寫完退回上一頁）
    var showsDoneButton: Bool = false

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    /// 草稿：每一分的名字（打開時＝現在的；〔完成〕才寫）
    @State private var names: [Int: String] = [:]
    /// [v25.601 v1b] 草稿：每一分的說明（打開時＝等級表現在的；〔完成〕才寫）。要退回這一件：刪這個 @State
    @State private var details: [Int: String] = [:]
    @State private var loaded = false
    /// 套範本時級數不一樣的那一句（「範本只有 5 級：6～10 沒有名字，可以自己補。」）
    @State private var templateNote: String?
    @State private var showPremiumAlert = false

    private var scale: CompetencyScale? { lifeStore.competencySetup.scale(scaleId) }
    private var range: CompetencyRange { scale?.range ?? CompetencyRange.standard }
    private var readOnly: Bool { lifeStore.competencyReadOnly }
    private var allowed: Bool { CompetencyMath.namesAllowed(range) }
    private var levels: [Int] { Array(range.low...range.high) }

    /// 草稿跟現在存的不一樣（去空白、4 字上限後比；[v25.601 v1b] 說明也比，30 字上限）
    private var changed: Bool {
        let now: [Int: String] = CompetencyMath.currentLevelNames(scale, range: range)
        if Self.normalized(names, in: range) != Self.normalized(now, in: range) { return true }
        let nowDetails: [Int: String] = CompetencyMath.currentLevelDetails(scale?.levels, range: range)
        return Self.normalizedDetails(details, in: range) != Self.normalizedDetails(nowDetails, in: range)
    }

    /// 右上〔完成〕：能設名字（而且不是唯讀）才有；sheet 打開的一定有（關掉用）
    private var showsDone: Bool { showsDoneButton || (allowed && !readOnly) }

    private var titleText: String {
        scaleId == CompetencySetupBook.traitScaleId ? "人格特質・每一分的名字" : "本職學能・每一分的名字"
    }

    var body: some View {
        Form {
            readOnlySection
            if allowed {
                templateSection
                namesSection
                itemSection
            } else {
                notAllowedSection
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { loadIfNeeded() }
        .onChange(of: names) { _, new in clampNames(new) }
        .onChange(of: details) { _, new in clampDetails(new) }
        .interactiveDismissDisabled(showsDoneButton && changed)
        .premiumLockAlert(isPresented: $showPremiumAlert)
    }

    // MARK: 工具列

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if showsDoneButton {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        if showsDone {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { done() }
            }
        }
    }

    // MARK: 各節

    @ViewBuilder
    private var readOnlySection: some View {
        if readOnly {
            Section {
                Label("這台的 App 比較舊，設定請在已更新的那台改", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var notAllowedSection: some View {
        Section {
            Text(CompetencyMath.namesNotAllowedText(range))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var templateSection: some View {
        Section {
            CompNamesTemplateMenu(disabled: readOnly,
                                  onPick: { t in applyTemplate(t) },
                                  onClear: { clearAll() })
            if let n = templateNote {
                Text(n)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } footer: {
            Text(Self.templateFooter)
        }
    }

    private var namesSection: some View {
        Section {
            ForEach(levels, id: \.self) { v in
                CompNamesRow(value: v, text: binding(v), detail: detailBinding(v), disabled: readOnly)
            }
        } header: {
            Text("每一分（\(range.text)）")
        } footer: {
            Text(namesFooter)
        }
    }

    /// [v25.601 v1b] 每一項自己的說明（看不擋；推進去名字頁的草稿留著）。要退回這一件：刪這一節與 itemEntries
    @ViewBuilder
    private var itemSection: some View {
        let rows: [CompNamesItemEntry] = itemEntries
        Section {
            if rows.isEmpty {
                Text("還沒有項目")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { e in
                NavigationLink {
                    CompetencyItemDetailsView(itemId: e.id)
                } label: {
                    CompNamesItemLabel(entry: e)
                }
            }
        } header: {
            Text("每一項自己的說明")
        } footer: {
            Text(itemFooter)
        }
    }

    /// 人格：人格項目；本職：共用學習項目＋每個系統自己的項目（小字寫是哪裡的）
    private var itemEntries: [CompNamesItemEntry] {
        let s: CompetencySetupBook = lifeStore.competencySetup
        let r: CompetencyRange = range
        var out: [CompNamesItemEntry] = []
        if scaleId == CompetencySetupBook.traitScaleId {
            for it in s.traitItems {
                out.append(CompNamesItemEntry(item: it, caption: nil, range: r))
            }
            return out
        }
        for it in s.sharedItems {
            out.append(CompNamesItemEntry(item: it, caption: "共用學習項目", range: r))
        }
        for g in s.activeSystems {
            let cap: String = g.displayName + " 自己的"
            for it in s.ownItems(g.id) {
                out.append(CompNamesItemEntry(item: it, caption: cap, range: r))
            }
        }
        return out
    }

    private var itemFooter: String {
        scaleId == CompetencySetupBook.traitScaleId ? Self.itemFooterBase : Self.itemFooterBase + Self.itemFooterShared
    }

    private static let itemFooterBase =
        "項目自己的說明蓋過上面的通用說明，沒寫的那一分照通用說明。"

    private static let itemFooterShared =
        "共用學習項目的說明每個系統都一樣。"

    private var namesFooter: String {
        showsDoneButton ? Self.namesFooterBase : Self.namesFooterBase + Self.namesFooterPushed
    }

    private static let templateFooter =
        "範本只是起點，套了之後每一分都還能自己改。出廠只用數字。"

    private static let namesFooterBase =
        "按鈕下面寫這個名字（最多 4 字）。空的那一分只寫數字。說明會寫在評分按鈕下面，例：「3 分：自己做得來」。"

    private static let namesFooterPushed =
        "改完按〔完成〕才會存。"

    // MARK: 草稿

    private func binding(_ v: Int) -> Binding<String> {
        Binding(
            get: { names[v] ?? "" },
            set: { t in setName(v, t) }
        )
    }

    /// 打字只改草稿（brief §1.7：打字不擋，〔完成〕才擋訂閱——擋在打字時被拒的字會留在欄位裡、跟草稿對不上）。
    /// 唯讀時欄位是 disabled。超過 4 字由 onChange 截掉
    private func setName(_ v: Int, _ t: String) {
        guard !readOnly, t != (names[v] ?? "") else { return }
        names[v] = t
    }

    /// [v25.601 v1b] 說明那一欄（打字只改草稿，〔完成〕才擋訂閱；唯讀時欄位 disabled）
    private func detailBinding(_ v: Int) -> Binding<String> {
        Binding(
            get: { details[v] ?? "" },
            set: { t in setDetail(v, t) }
        )
    }

    private func setDetail(_ v: Int, _ t: String) {
        guard !readOnly, t != (details[v] ?? "") else { return }
        details[v] = t
    }

    /// [v25.601 v1b] 說明超過 30 字截掉、換行拿掉（打字、貼上都走這裡）
    private func clampDetails(_ new: [Int: String]) {
        var fixed: [Int: String] = new
        var dirty: Bool = false
        for (k, s) in new {
            let c: String = CompNamesDetailText.clamp(s)
            if c != s {
                fixed[k] = c
                dirty = true
            }
        }
        if dirty { details = fixed }
    }

    /// 比較用（說明）：範圍裡、去空白、30 字上限、空的拿掉
    private static func normalizedDetails(_ d: [Int: String], in r: CompetencyRange) -> [Int: String] {
        var out: [Int: String] = [:]
        for (k, s) in d where r.contains(k) {
            if let c = CompetencyMath.cleanShortName(s, max: CompetencyMath.levelDetailMax) {
                out[k] = c
            }
        }
        return out
    }

    /// 超過 4 字的截掉（打字、貼上都走這裡）
    private func clampNames(_ new: [Int: String]) {
        let maxLen: Int = CompetencyMath.levelNameMax
        var fixed: [Int: String] = new
        var dirty: Bool = false
        for (k, s) in new where s.count > maxLen {
            fixed[k] = String(s.prefix(maxLen))
            dirty = true
        }
        if dirty { names = fixed }
    }

    /// 比較用：範圍裡、去空白、4 字上限、空的拿掉
    private static func normalized(_ d: [Int: String], in r: CompetencyRange) -> [Int: String] {
        var out: [Int: String] = [:]
        for (k, s) in d where r.contains(k) {
            if let c = CompetencyMath.cleanShortName(s, max: CompetencyMath.levelNameMax) {
                out[k] = c
            }
        }
        return out
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        names = CompetencyMath.currentLevelNames(scale, range: range)
        details = CompetencyMath.currentLevelDetails(scale?.levels, range: range)
    }

    // MARK: 動作（每一個改動先擋唯讀與訂閱）

    /// 能不能改：唯讀 → 不能（不跳訂閱）；沒訂閱 → 跳訂閱說明
    private func gate() -> Bool {
        if readOnly { return false }
        if !subscription.isPremium {
            showPremiumAlert = true
            return false
        }
        return true
    }

    /// 套範本只改草稿；級數不一樣頁內寫一句
    private func applyTemplate(_ t: CompetencyLevelTemplate) {
        guard gate() else { return }
        let r = CompetencyMath.applyTemplate(t, to: range)
        names = r.names
        // [v25.601 v1b] 範本的說明一起填進草稿（§13：只有按了才填）
        details = CompetencyMath.applyTemplateDetails(t, to: range)
        templateNote = r.note
    }

    /// 〔先只用數字〕：草稿全部清掉（名字、說明一起；按〔完成〕才寫）
    private func clearAll() {
        guard gate() else { return }
        names = [:]
        details = [:]
        templateNote = nil
    }

    /// 〔完成〕：沒改直接關；有改先擋訂閱（沒訂閱不關頁），關掉之後下一個 runloop 才寫 store
    private func done() {
        guard allowed, !readOnly, changed else {
            dismiss()
            return
        }
        guard subscription.isPremium else {
            showPremiumAlert = true
            return
        }
        let store: LifeStore = lifeStore
        let sid: String = scaleId
        let n: [Int: String] = names
        let d: [Int: String] = details
        dismiss()
        DispatchQueue.main.async {
            // [v25.601 v1b] 名字＋說明一起寫。要退回這一件：改回 setCompetencyLevelNames(scaleId: sid, names: n)
            store.setCompetencyLevelNames(scaleId: sid, names: n, details: d)
        }
    }
}

// MARK: - 〔套用範本 ▾〕（範本＋〔先只用數字〕）

private struct CompNamesTemplateMenu: View {
    let disabled: Bool
    let onPick: (CompetencyLevelTemplate) -> Void
    let onClear: () -> Void

    var body: some View {
        Menu {
            ForEach(CompetencyMath.levelTemplates) { t in
                Button(t.menuTitle) { onPick(t) }
            }
            Divider()
            Button("先只用數字", role: .destructive) { onClear() }
        } label: {
            Label("套用範本", systemImage: "wand.and.stars")
        }
        .disabled(disabled)
    }
}

// MARK: - 一列「3　[能獨立]」

private struct CompNamesRow: View {
    let value: Int
    let text: Binding<String>
    /// [v25.601 v1b] 說明那一欄。要退回這一件：刪 detail 與下面第二個 TextField
    let detail: Binding<String>
    let disabled: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(value)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(width: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                TextField("（只用數字）", text: text)
                    .submitLabel(.done)
                    .disabled(disabled)
                    .accessibilityLabel("\(value) 分的名字")
                TextField(CompNamesDetailText.placeholder, text: detail, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.footnote)
                    .disabled(disabled)
                    .accessibilityLabel("\(value) 分的說明")
            }
        }
    }
}

// MARK: - [v25.601 職能雷達 v1b] 說明欄共用的小東西（名字頁、說明頁）

private enum CompNamesDetailText {
    static let placeholder: String = "說明（選填，最多 \(CompetencyMath.levelDetailMax) 字）"

    /// 換行拿掉、超過 30 字截掉
    static func clamp(_ s: String) -> String {
        let oneLine: String = s.replacingOccurrences(of: "\n", with: "")
        if oneLine.count > CompetencyMath.levelDetailMax {
            return String(oneLine.prefix(CompetencyMath.levelDetailMax))
        }
        return oneLine
    }
}

// MARK: - [v25.601 職能雷達 v1b] 「每一項自己的說明」一列

private struct CompNamesItemEntry: Identifiable {
    /// 項目代號
    let id: UUID
    let title: String
    /// 「共用學習項目」「Gas System 自己的」；人格項目 nil
    let caption: String?
    /// 「寫了 2 分」「照通用說明」
    let count: String

    init(item: CompetencyItem, caption: String?, range: CompetencyRange) {
        self.id = item.id
        self.title = item.displayName
        self.caption = caption
        self.count = CompetencyMath.itemDetailCountText(item, range: range)
    }
}

private struct CompNamesItemLabel: View {
    let entry: CompNamesItemEntry

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .foregroundStyle(.primary)
                if let c = entry.caption {
                    Text(c)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(entry.count)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - [v25.601 職能雷達 v1b] 一個項目自己的每一分說明（名字頁推進來、系統頁用 sheet 打開）
// 型別名與 init(itemId:showsDoneButton:) 是跨組契約（brief §5）。
// 草稿 details（打開時＝項目現在的 levelDetails）；欄位 placeholder＝等級表那一分的通用說明；
// 〔完成〕：沒改直接關；有改擋訂閱（沒訂閱不關頁）→ dismiss 後下一個 runloop setCompetencyItemLevelDetails。
// 〔全部清掉〕只改草稿（空的那一分照通用說明）。超過 11 級只寫一句話。
// 要退回這一件：刪這個 struct 與 CompNamesDetailRow（名字頁的 itemSection、系統頁的〔說明〕也要一起刪）。

struct CompetencyItemDetailsView: View {
    let itemId: UUID
    /// sheet 打開（系統頁往右滑〔說明〕）：左上〔取消〕、有改時不能往下滑關掉
    var showsDoneButton: Bool = false

    init(itemId: UUID, showsDoneButton: Bool = false) {
        self.itemId = itemId
        self.showsDoneButton = showsDoneButton
    }

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    /// 草稿：這一項自己的每一分說明（〔完成〕才寫）
    @State private var details: [Int: String] = [:]
    @State private var loaded = false
    @State private var showPremiumAlert = false

    private var setup: CompetencySetupBook { lifeStore.competencySetup }
    /// 這一項（沒刪才算；停用的照樣可以寫）
    private var item: CompetencyItem? {
        guard let it = setup.item(itemId), it.isLive else { return nil }
        return it
    }
    private var isTraitItem: Bool { item?.groupId == CompetencySetupBook.traitGroupId }
    private var scale: CompetencyScale? {
        setup.scale(isTraitItem ? CompetencySetupBook.traitScaleId : CompetencySetupBook.skillScaleId)
    }
    private var range: CompetencyRange { isTraitItem ? setup.traitRange : setup.skillRange }
    private var readOnly: Bool { lifeStore.competencyReadOnly }
    private var allowed: Bool { CompetencyMath.namesAllowed(range) }
    private var levels: [Int] { Array(range.low...range.high) }
    /// 等級表的通用說明（placeholder 用）
    private var generalDetails: [Int: String] { CompetencyMath.currentLevelDetails(scale?.levels, range: range) }

    /// 草稿跟現在存的不一樣（去空白、30 字上限後比）
    private var changed: Bool {
        guard let it = item else { return false }
        let now: [Int: String] = CompetencyMath.currentLevelDetails(it.levelDetails, range: range)
        return Self.normalized(details, in: range) != Self.normalized(now, in: range)
    }

    /// 右上〔完成〕：能寫（不是唯讀、這一項還在、≤ 11 級）才有；sheet 打開的一定有（關掉用）
    private var showsDone: Bool { showsDoneButton || (allowed && !readOnly && item != nil) }

    private var titleText: String {
        guard let it = item else { return "每一分的說明" }
        return it.displayName + "・每一分的說明"
    }

    var body: some View {
        Form {
            sections
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { loadIfNeeded() }
        .onChange(of: details) { _, new in clampDetails(new) }
        .interactiveDismissDisabled(showsDoneButton && changed)
        .premiumLockAlert(isPresented: $showPremiumAlert)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if showsDoneButton {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        if showsDone {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { done() }
            }
        }
    }

    // MARK: 各節

    @ViewBuilder
    private var sections: some View {
        if readOnly {
            Section {
                Label("這台的 App 比較舊，設定請在已更新的那台改", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        // [v25.602 職能雷達 v2] 照舊範圍寫的說明：一行橘字＋〔清掉重寫〕（沒標別的範圍時什麼都不畫）
        oldRangeSection
        if item == nil {
            messageSection("這一項已經不在了")
        } else if !allowed {
            messageSection(Self.notAllowedText(range))
        } else {
            detailsSection
            clearSection
        }
    }

    /// [v25.602 職能雷達 v2] 「這些說明是照 1–5 寫的，現在是 1–10，評分時先不顯示…」＋〔清掉重寫〕
    @ViewBuilder
    private var oldRangeSection: some View {
        if let it = item, let old = CompetencyMath.itemDetailsOldRange(it, range: range) {
            Section {
                CompNamesOldRangeRow(text: Self.oldRangeText(old, now: range, allowed: allowed),
                                     itemName: it.displayName,
                                     disabled: readOnly,
                                     canWrite: { askClearDetails() },
                                     onClear: { clearDetailsNow() })
            }
        }
    }

    /// [v25.602 職能雷達 v2 審查修] 頂上那一行：≤ 11 級照 CompetencyMath.itemDetailsOldText；超過 11 級（例 0–100）不能寫說明，
    /// 「改一句就照 0–100 用」做不到，拿掉那半句。下一版主控可搬進 CompetencyMath。要退回這一件：改回 itemDetailsOldText(old, now: range)
    private static func oldRangeText(_ old: CompetencyRange, now r: CompetencyRange, allowed: Bool) -> String {
        if allowed { return CompetencyMath.itemDetailsOldText(old, now: r) }
        return "這些說明是照 " + old.text + " 寫的，現在是 " + r.text + "，評分時先不顯示。改回 " + old.text + " 就會再出現。"
    }

    private func messageSection(_ text: String) -> some View {
        Section {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var detailsSection: some View {
        Section {
            ForEach(levels, id: \.self) { v in
                CompNamesDetailRow(value: v,
                                   name: scale?.levelName(v),
                                   placeholder: placeholder(v),
                                   text: binding(v),
                                   disabled: readOnly)
            }
        } header: {
            Text("每一分（\(range.text)）")
        } footer: {
            Text(detailsFooter)
        }
    }

    private var clearSection: some View {
        Section {
            Button(role: .destructive) {
                clearAll()
            } label: {
                Label("全部清掉（回到通用說明）", systemImage: "arrow.uturn.backward")
            }
            .disabled(readOnly || details.isEmpty)
        }
    }

    private var detailsFooter: String {
        showsDoneButton ? Self.footerBase : Self.footerBase + Self.footerPushed
    }

    private static let footerBase =
        "這一項自己的說明蓋過通用說明；空的那一分照通用說明（灰字）。每一分最多 30 字，寫在評分按鈕下面。"

    private static let footerPushed =
        "改完按〔完成〕才會存。"

    /// 「現在是 0–100，超過 11 級不設每一分的說明，只用數字。」
    private static func notAllowedText(_ r: CompetencyRange) -> String {
        "現在是 " + r.text + "，超過 11 級不設每一分的說明，只用數字。"
    }

    /// 欄位的灰字：等級表那一分的通用說明；沒有就寫「說明（選填，最多 30 字）」
    private func placeholder(_ v: Int) -> String {
        generalDetails[v] ?? CompNamesDetailText.placeholder
    }

    // MARK: 草稿

    private func binding(_ v: Int) -> Binding<String> {
        Binding(
            get: { details[v] ?? "" },
            set: { t in setDetail(v, t) }
        )
    }

    /// 打字只改草稿（〔完成〕才擋訂閱）；唯讀時欄位 disabled
    private func setDetail(_ v: Int, _ t: String) {
        guard !readOnly, t != (details[v] ?? "") else { return }
        details[v] = t
    }

    private func clampDetails(_ new: [Int: String]) {
        var fixed: [Int: String] = new
        var dirty: Bool = false
        for (k, s) in new {
            let c: String = CompNamesDetailText.clamp(s)
            if c != s {
                fixed[k] = c
                dirty = true
            }
        }
        if dirty { details = fixed }
    }

    private static func normalized(_ d: [Int: String], in r: CompetencyRange) -> [Int: String] {
        var out: [Int: String] = [:]
        for (k, s) in d where r.contains(k) {
            if let c = CompetencyMath.cleanShortName(s, max: CompetencyMath.levelDetailMax) {
                out[k] = c
            }
        }
        return out
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let it = item else { return }
        details = CompetencyMath.currentLevelDetails(it.levelDetails, range: range)
    }

    /// 〔全部清掉〕：只改草稿（按〔完成〕才寫）
    private func clearAll() {
        guard !readOnly else { return }
        details = [:]
    }

    /// [v25.602 職能雷達 v2] 〔清掉重寫〕先擋：唯讀 → 不能（不跳訂閱）；沒訂閱 → 跳訂閱說明（確認框之前擋，免得兩個框疊在一起）
    private func askClearDetails() -> Bool {
        if readOnly { return false }
        if !subscription.isPremium {
            showPremiumAlert = true
            return false
        }
        return true
    }

    /// [v25.602 職能雷達 v2] 確認〔清掉〕：說明和範圍標記都拿掉（回到通用說明），草稿一起清空；不關頁，下一個 runloop 才寫 store
    private func clearDetailsNow() {
        guard !readOnly, subscription.isPremium, item != nil else { return }
        let store: LifeStore = lifeStore
        let id: UUID = itemId
        details = [:]
        DispatchQueue.main.async {
            store.clearCompetencyItemLevelDetails(id)
        }
    }

    /// 〔完成〕：沒改直接關；有改先擋訂閱（沒訂閱不關頁），關掉之後下一個 runloop 才寫 store
    private func done() {
        guard allowed, !readOnly, item != nil, changed else {
            dismiss()
            return
        }
        guard subscription.isPremium else {
            showPremiumAlert = true
            return
        }
        let store: LifeStore = lifeStore
        let id: UUID = itemId
        let d: [Int: String] = details
        dismiss()
        DispatchQueue.main.async {
            store.setCompetencyItemLevelDetails(id, details: d)
        }
    }
}

// MARK: - [v25.601 職能雷達 v1b] 說明頁一列「3　能獨立／[說明]」

private struct CompNamesDetailRow: View {
    let value: Int
    /// 等級表那一分的名字（灰字；沒有就不寫）
    let name: String?
    let placeholder: String
    let text: Binding<String>
    let disabled: Bool

    private var spokenLabel: String {
        guard let n = name else { return "\(value) 分的說明" }
        return "\(value) 分，" + n + "，說明"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(value)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(width: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                if let n = name {
                    Text(n)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                TextField(placeholder, text: text, axis: .vertical)
                    .lineLimit(1...3)
                    .disabled(disabled)
                    .accessibilityLabel(spokenLabel)
            }
        }
    }
}

// MARK: - [v25.602 職能雷達 v2] 說明頁頂上「照舊範圍寫的」一行＋〔清掉重寫〕（確認框掛在按鈕上；這一列自己存要不要問）

private struct CompNamesOldRangeRow: View {
    /// CompetencyMath.itemDetailsOldText(old, now:)
    let text: String
    /// 「值班技能」（確認框標題用）
    let itemName: String
    let disabled: Bool
    /// 擋唯讀、訂閱（回 false＝不問）
    let canWrite: () -> Bool
    let onClear: () -> Void

    @State private var showConfirm = false

    init(text: String, itemName: String, disabled: Bool, canWrite: @escaping () -> Bool,
         onClear: @escaping () -> Void) {
        self.text = text
        self.itemName = itemName
        self.disabled = disabled
        self.canWrite = canWrite
        self.onClear = onClear
    }

    private var confirmTitle: String { "清掉" + itemName + "自己的說明？" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            clearButton
        }
        .padding(.vertical, 2)
    }

    private var clearButton: some View {
        Button(role: .destructive) {
            if canWrite() { showConfirm = true }
        } label: {
            Label("清掉重寫", systemImage: "trash")
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .confirmationDialog(confirmTitle, isPresented: $showConfirm, titleVisibility: .visible) {
            Button("清掉", role: .destructive) { onClear() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清掉後照每一分的通用說明。")
        }
    }
}
