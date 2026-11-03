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
    @State private var loaded = false
    /// 套範本時級數不一樣的那一句（「範本只有 5 級：6～10 沒有名字，可以自己補。」）
    @State private var templateNote: String?
    @State private var showPremiumAlert = false

    private var scale: CompetencyScale? { lifeStore.competencySetup.scale(scaleId) }
    private var range: CompetencyRange { scale?.range ?? CompetencyRange.standard }
    private var readOnly: Bool { lifeStore.competencyReadOnly }
    private var allowed: Bool { CompetencyMath.namesAllowed(range) }
    private var levels: [Int] { Array(range.low...range.high) }

    /// 草稿跟現在存的不一樣（去空白、4 字上限後比）
    private var changed: Bool {
        let now: [Int: String] = CompetencyMath.currentLevelNames(scale, range: range)
        return Self.normalized(names, in: range) != Self.normalized(now, in: range)
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
                CompNamesRow(value: v, text: binding(v), disabled: readOnly)
            }
        } header: {
            Text("每一分的名字（\(range.text)）")
        } footer: {
            Text(namesFooter)
        }
    }

    private var namesFooter: String {
        showsDoneButton ? Self.namesFooterBase : Self.namesFooterBase + Self.namesFooterPushed
    }

    private static let templateFooter =
        "範本只是起點，套了之後每一分都還能自己改。出廠只用數字。"

    private static let namesFooterBase =
        "按鈕下面寫這個名字（最多 4 字）。空的那一分只寫數字。"

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
        templateNote = r.note
    }

    /// 〔先只用數字〕：草稿全部清掉（按〔完成〕才寫）
    private func clearAll() {
        guard gate() else { return }
        names = [:]
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
        dismiss()
        DispatchQueue.main.async {
            store.setCompetencyLevelNames(scaleId: sid, names: n)
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
    let disabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(value)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(width: 32, alignment: .leading)
            TextField("（只用數字）", text: text)
                .submitLabel(.done)
                .disabled(disabled)
                .accessibilityLabel("\(value) 分的名字")
        }
    }
}
