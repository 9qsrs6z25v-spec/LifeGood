import SwiftUI

// [v25.634] ExpenseSplitEditor：記帳表單「誰付多少」打開的編輯器（judge_companions §C7；build/companions1/brief.md §2 G1 5–6）。
// - AddExpenseView 先用 ExpenseSplitMath.resolve 算好現在的分帳（人、總額都對過）當 initial，這裡只改那一份草稿。
// - 每個動作都是 draft = ExpenseSplitMath.xxx(draft, …)；這裡不寫 store、不寫 UserDefaults。
// - 〔完成〕：先 dismiss，下一個 runloop 才把草稿交回去（onDone；表單存檔時才寫 ExpenseSplitStore）。
// - 每一列都是 fileprivate struct（純值＋closure）、清單包 AnyView（25.618 記帳表單閃退的教訓）。

struct ExpenseSplitEditor: View {
    /// 超過幾個人就把後面的摺起來（第 9 人起）
    static let foldLimit = 8

    let meName: String
    /// 已還的人那一列右邊的字（share.id → 「已還 11/22・國泰世華 ✓」）
    let paidInfo: [UUID: String]
    let onDone: (ExpenseSplitDraft) -> Void

    @State private var draft: ExpenseSplitDraft
    @State private var showAll = false
    @Environment(\.dismiss) private var dismiss

    init(meName: String, initial: ExpenseSplitDraft, paidInfo: [UUID: String],
         onDone: @escaping (ExpenseSplitDraft) -> Void) {
        self.meName = meName
        self.paidInfo = paidInfo
        self.onDone = onDone
        _draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            AnyView(editorList)
                .navigationTitle(ExpenseSplitText.rowTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { editorToolbar }
        }
    }

    // MARK: - 算好的值

    /// 畫面上列出來的人（超過 8 人、還沒按「還有 N 人」時只列前 8 個）
    private var visibleRows: [ExpenseSplitDraftRow] {
        if showAll || draft.rows.count <= Self.foldLimit { return draft.rows }
        return Array(draft.rows.prefix(Self.foldLimit))
    }

    /// 摺起來的人數（0＝沒摺）
    private var hiddenCount: Int {
        showAll ? 0 : max(0, draft.rows.count - Self.foldLimit)
    }

    // MARK: - 動作（只改草稿）

    private func setRole(_ id: UUID, _ role: String) {
        draft = ExpenseSplitMath.settingRole(draft, id: id, role: role)
    }

    private func setAmount(_ id: UUID, _ amount: Double) {
        draft = ExpenseSplitMath.settingAmount(draft, id: id, amount: amount)
    }

    private func treatAll() {
        draft = ExpenseSplitMath.allTreat(draft)
    }

    private func evenAll() {
        draft = ExpenseSplitMath.evenOwe(draft)
    }

    private func resetEven() {
        draft = ExpenseSplitMath.resetManual(draft)
    }

    /// 〔完成〕：草稿先抓成常數，dismiss 之後下一個 runloop 才交回去
    private func finish() {
        let d = draft
        let done = onDone
        dismiss()
        DispatchQueue.main.async { done(d) }
    }

    // MARK: - 畫面

    private var editorList: some View {
        let rows = visibleRows
        let hidden = hiddenCount
        return List {
            Section {
                SplitEditorHeaderRow(text: ExpenseSplitText.editorHeader(draft),
                                     onTreat: { treatAll() }, onEven: { evenAll() })
                SplitMeRow(label: ExpenseSplitText.meLabel(meName), value: ExpenseSplitText.meValue(draft))
                ForEach(rows) { r in
                    SplitShareRow(row: r, paid: paidInfo[r.id],
                                  onRole: { role in setRole(r.id, role) },
                                  onAmount: { v in setAmount(r.id, v) })
                }
                if hidden > 0 {
                    SplitFoldRow(text: ExpenseSplitText.foldedText(hidden), onTap: { showAll = true })
                }
            }
            Section {
                SplitEditorFooter(owe: ExpenseSplitText.footerOwe(draft), own: ExpenseSplitText.footerOwn(draft),
                                  over: draft.isOver ? ExpenseSplitText.overText(draft) : nil)
                if draft.hasManual {
                    Button(ExpenseSplitText.resetEven) { resetEven() }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("完成") { finish() }
                .bold()
                .disabled(draft.isOver)
        }
    }
}

// MARK: - 列（純值＋closure）

/// 最上面：「這頓 NT$1,500・4 人」＋〔我請客〕〔大家平分〕（同一列兩顆按鈕：一定 .borderless，不然點整列兩顆都觸發）
fileprivate struct SplitEditorHeaderRow: View {
    let text: String
    let onTreat: () -> Void
    let onEven: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.subheadline.weight(.semibold))
            HStack(spacing: 16) {
                Button(ExpenseSplitText.treatAll) { onTreat() }
                    .buttonStyle(.borderless)
                Button(ExpenseSplitText.evenAll) { onEven() }
                    .buttonStyle(.borderless)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}

/// 「我（張家瑋）　NT$375（剩下的）」：灰字、不能改
fileprivate struct SplitMeRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label).lineLimit(1)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// 一個人一列：名字、〔要還我｜我請〕、金額（手改過的標「手改」）；已還的整列灰掉、不能改
fileprivate struct SplitShareRow: View {
    let row: ExpenseSplitDraftRow
    let paid: String?
    let onRole: (String) -> Void
    let onAmount: (Double) -> Void

    var body: some View {
        if row.locked {
            lockedBody
        } else {
            editBody
        }
    }

    /// 角色選單綁的值：看不懂的 role 一律當我請（同 SplitShare.owes 的規則）
    private var roleBinding: Binding<String> {
        Binding(get: { row.role == SplitShare.roleOwe ? SplitShare.roleOwe : SplitShare.roleTreat },
                set: { onRole($0) })
    }

    private var editBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(row.name).lineLimit(1)
                if row.isManual {
                    Text(ExpenseSplitText.manualTag)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 8)
                Text("NT$").font(.subheadline).foregroundStyle(.secondary)
                SplitAmountField(amount: row.amount, onAmount: onAmount)
            }
            Picker("", selection: roleBinding) {
                Text(ExpenseSplitText.roleOweTitle).tag(SplitShare.roleOwe)
                Text(ExpenseSplitText.roleTreatTitle).tag(SplitShare.roleTreat)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private var lockedBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(row.name).lineLimit(1)
                Spacer(minLength: 8)
                Text(ExpenseSplitText.ntd(row.amount))
            }
            Text(paid ?? ExpenseSplitText.repayButton)
                .font(.caption)
            Text(ExpenseSplitText.lockedNote)
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
        .disabled(true)
    }
}

/// 金額欄（整數元、數字鍵盤）：打字時才交回去（手改＋其他人重新平分）；沒在打字時跟著草稿的金額走
fileprivate struct SplitAmountField: View {
    let amount: Double
    let onAmount: (Double) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    private static func fieldText(_ v: Double) -> String {
        String(format: "%.0f", v)
    }

    var body: some View {
        TextField("0", text: $text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 90)
            .focused($focused)
            .onAppear { text = Self.fieldText(amount) }
            .onChange(of: amount) { _, v in
                if !focused { text = Self.fieldText(v) }
            }
            .onChange(of: text) { _, t in
                if focused, let v = ExpenseSplitMath.parseAmount(t), v != amount { onAmount(v) }
            }
            .onChange(of: focused) { _, f in
                // 離開金額欄：照草稿裡的金額重寫一次（打一半、清空的不留著）
                if !f { text = Self.fieldText(amount) }
            }
    }
}

/// 超過 8 人：「還有 3 人 ›」（按了全部列出來）
fileprivate struct SplitFoldRow: View {
    let text: String
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

/// 段尾：「要還你 2 人・NT$750」「記帳只算你 NT$750（…）；刷卡、扣款照 NT$1,500」；超過總額時紅字
fileprivate struct SplitEditorFooter: View {
    let owe: String
    let own: String
    let over: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(owe).font(.subheadline.weight(.semibold))
            Text(own).font(.caption).foregroundStyle(.secondary)
            if let o = over {
                Text(o).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 換成不能分帳的分類（AddExpenseView 工具列〔儲存〕掛這個）

/// 「換成「交通」就不能分帳，王小明、陳怡君 還沒還的 NT$750 會一起拿掉。」〔還是換〕〔取消〕。
/// 選〔還是換〕叫 onConfirm（表單記下來、再存一次），取消什麼都不做（不存）。照 AmountFromDialog
struct SplitDropDialog: ViewModifier {
    @Binding var ask: SplitDropAsk?
    let onConfirm: () -> Void

    init(ask: Binding<SplitDropAsk?>, onConfirm: @escaping () -> Void) {
        _ask = ask
        self.onConfirm = onConfirm
    }

    func body(content: Content) -> some View {
        content.alert("這筆不能分帳了", isPresented: shown, presenting: ask) { _ in
            Button(ExpenseSplitText.dropConfirm, role: .destructive) { onConfirm() }
            Button("取消", role: .cancel) {}
        } message: { a in
            Text(a.message)
        }
    }

    private var shown: Binding<Bool> {
        Binding(get: { ask != nil }, set: { if !$0 { ask = nil } })
    }
}
