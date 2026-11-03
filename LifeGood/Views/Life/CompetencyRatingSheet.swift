import SwiftUI

// MARK: - [v25.599 職能雷達 v1a-1] 評分畫面（G3 負責；radar/judge.md §3.7、§4.5、§13；radar/build/v1a-1/brief.md §4 G3）
//
// • sheet .large；日期（不能晚於今天；同一天或已有那天就打開那一張）、這次評、〔全部照上次〕／〔這組照上次〕（範圍不同不帶）、
//   灰點上次、high ≤ 10 一排／兩排圓按鈕、high > 10 滑桿＋數字欄＋〔－〕〔＋〕（§13）、淡框點一下＝確認、〔⋯〕清掉、
//   只在下一格空的才捲、底部那一行＋〔儲存〕、VoiceOver 可調整。
// • 規則全部在 CompetencyMath（ratingPlan、carriedCells、draft(from:)、footerCounts、footerText、buildSession、savedToast）。
// • 存檔：先 dismiss，下一個 runloop 再 lifeStore.saveCompetencySession。
// • 範圍用打開時的（openedTrait／openedSkill；judge §3.3「改範圍時正在評分：照打開時的範圍存」）；改已經有的那一張用它自己的範圍。
// • body 只排版：每一列要的字、狀態先在 rowModels(_:) 算成 CompRatingRowModel；子 View 都很小（型別檢查不逾時）。
// • 字不用「他／她」：找不到名字寫「這位同仁」。評分、總評只在 App 裡（通知、小工具、手錶、鎖定畫面、靈動島一個字都沒加）。
// 骨架（主控）：CompetencyRatingRequest、CompetencyRatingSheet(request:onSaved:) 是跨組契約，不准改。
//
// [v25.600 職能雷達 v1a-2]（radar/build/v1a-2/brief.md §4 G2 1–7；judge §3.7-5、§13）
// • request.sessionId：評分紀錄〔改分數〕打開的就是那一張（沒刪、我評的、是這位的；不然照日子找）。
// • 底部那一行、儲存按鈕：改已經有的那一張時跟打開時比（footerCounts(baseline:)＋CompetencyMath.canSave）——
//   沒改寫「沒有改動（這一張 12 格）」、儲存灰；不會再寫「改了 12 格」。
// • 數字欄：打跟現在一樣的數字不算改（關掉不問）；打了不是數字 → 那一格下面紅字「請打 0～100 的整數」、兩顆〔儲存〕都灰，
//   字留著到改對或清掉為止。
// • 〔⋯〕只有〔不適用〕（已經是不適用寫〔取消不適用〕＝清掉）〔清掉〕；VoiceOver 自訂動作一樣兩個。
//   §13 每一格的評語不做：畫面上沒有評語；別台寫的評語原樣存回去（draft 帶著 comment）。
// • 改舊紀錄：現在已停用的系統、項目照樣列出來，標頭／列名後面灰字「已停用」；「這次評」膠囊寫短名（chipTitle）。
// 要退回這一版：還原這個檔到 69f6fa6（request.sessionId 那兩行是主控加的，要留）。
//
// [v25.601 職能雷達 v1b]（radar/build/v1b/brief.md §1-4～6、§1-11、§4 G2 7–11；judge §4.5、§13）
// • 目標：openSession 時算 targetMarks（CompetencyMath.ratingTargetMarks，照這位現在的職等；沒職等、沒目標＝空），
//   每一格下面「E2 目標 3 ✓」「E2 目標 3・差 1」「E2 目標 3」（ratingTargetRowText），底部多一行「E2 達標 10／12」
//  （ratingTargetLine；算哪幾區跟 counts 同一條：新的一張只算勾了的區、改已經有的那一張算全部）。
// • 每一分的說明（§13 出廠空、使用者自己打）：選中那一分有說明才在按鈕下面寫「能教人：…」／「4 分：…」
//  （levelDetail＋levelDetailLine；超過 11 級、範圍跟等級表不一樣不寫）。VoiceOver 的值也接目標與說明。
// • 日子轉換：fileprivate compRatingDate 刪掉，改叫 CompetencyMath.noonDate（sim 台北、洛杉磯對過）。
// 要退回這一件：刪 targetMarks 與它在 openSession／footer 的兩行、CompRatingRowModel 的 targetText／detailLine、
// CompRatingRowCaption 那兩段、CompRatingFooter.targetLine；noonDate 那一行可以留。
//
// [v25.602 職能雷達 v2]〔一次評全課〕模式（radar/build/v2/brief.md §1-12、§4 G2-A；judge §4.7）
// • request.batch == nil：跟 v1b 一模一樣（新加的都只在 batch 有值時才動；存檔、取消、buildSession 一行都沒動）。
// • 最上面一行「2／3　陳怡君」（CompRatingBatchHeader；VoiceOver「第 2 位，共 3 位，陳怡君」）。
// • 「這次評」預設勾 batch.groupIds 跟這一張的組的交集（交集空＝照舊全勾）。
// • hasNext 時右上〔下一位 ›〕取代右上〔儲存〕（底部那一行的〔儲存〕照舊）：沒改直接 onNext＋dismiss；
//   有改先問「這一位還沒儲存」〔儲存，下一位〕（存得了才有）〔不儲存，下一位〕〔繼續評分〕（CompRatingNextAsk）。
// • 按〔儲存〕照原本的存檔（先 dismiss、下一個 runloop 寫 store、onSaved），換下一位由 host 決定。
// 要退回這一件：刪 batchHasNext／nextTapped／goNext／showNextAsk、toolbar 的 if 那一段、content 的 .modifier、
// openSession 的 batch 那一行、CompRatingBatchHeader、CompRatingNextAsk、compRatingBatchSpoken。

/// 打開評分畫面的請求（sheet(item:) 用）
struct CompetencyRatingRequest: Identifiable {
    let id = UUID()
    let subordinateId: UUID
    /// 要評哪一天（nil＝今天）
    var dayKey: String? = nil
    /// [v25.600 v1a-2] 評分紀錄〔改分數〕：要改的就是這一張（同一天兩台各評一張時不會改錯；nil＝照 dayKey 找那一天的）
    var sessionId: UUID? = nil
    /// [v25.602 v2]〔一次評全課〕的這一頁（「2／3　陳怡君」、預設勾的組、後面還有沒有人）；nil＝照舊一位一張（主控加的契約）
    var batch: CompetencyRatingBatch? = nil
}

struct CompetencyRatingSheet: View {
    let request: CompetencyRatingRequest
    /// 存好之後（已經 dismiss）給〔職能〕分頁顯示底部小提示「已儲存 10/30 的評分（12 格）」
    var onSaved: ((String) -> Void)? = nil
    /// [v25.602 v2]〔一次評全課〕右上〔下一位 ›〕（這一位不存、換下一位；呼叫完由這張自己 dismiss）。nil＝沒有這顆（主控加的契約）
    var onNext: (() -> Void)? = nil

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var loaded = false
    @State private var date: Date = Date()
    /// 打開時的「今天」「2026-11-03」
    @State private var today: String = ""
    /// 這次評的日子
    @State private var dayKey: String = ""
    /// 這一天已經有的那一張（有＝這次會改那一張）
    @State private var editing: CompetencySession? = nil
    /// 打開時的範圍（新的一張照這兩個存）
    @State private var openedTrait: CompetencyRange = CompetencyRange.standard
    @State private var openedSkill: CompetencyRange = CompetencyRange.standard
    @State private var sections: [CompetencyRatingSection] = []
    /// 「這次評」膠囊打勾的組
    @State private var included: Set<UUID> = []
    @State private var draft: [CompetencyCellKey: CompetencyDraftCell] = [:]
    /// 照上次帶進來、點過一下的（變實心；值不變、還是算「照上次」）
    @State private var confirmed: Set<CompetencyCellKey> = []
    @State private var note: String = ""
    /// 打開時的樣子（判斷有沒有改：有改，關掉先問）
    @State private var initialDraft: [CompetencyCellKey: CompetencyDraftCell] = [:]
    @State private var initialNote: String = ""
    /// 數字欄正在打的字（離開欄位才算數）
    @State private var inputText: [CompetencyCellKey: String] = [:]
    /// 「超出範圍，改成 100」
    @State private var clampNotes: [CompetencyCellKey: String] = [:]
    /// 要捲過去的下一格
    @State private var scrollTarget: CompetencyCellKey? = nil
    @State private var showPremiumAlert = false
    @State private var showDiscard = false
    /// [v25.601 v1b] 每一格的目標（openSession 算；照這位現在的職等，沒職等、沒目標＝空）
    @State private var targetMarks: [CompetencyCellKey: CompetencyTargetMark] = [:]
    /// [v25.602 v2]〔下一位 ›〕時這一位有改沒存：先問 3 選 1
    @State private var showNextAsk = false
    @FocusState private var focusedKey: CompetencyCellKey?
    @FocusState private var noteFocused: Bool

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("評分・" + personName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .bottom) { footer }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog("不儲存就關掉？", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("不儲存", role: .destructive) { dismiss() }
            Button("繼續評分", role: .cancel) {}
        }
        .premiumLockAlert(isPresented: $showPremiumAlert)
        .onAppear { loadIfNeeded() }
        .onChange(of: date) { _, newValue in dateChanged(newValue) }
        .onChange(of: focusedKey) { oldValue, newValue in focusChanged(from: oldValue, to: newValue) }
    }

    // MARK: 版面

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { cancelTapped() }
        }
        ToolbarItem(placement: .confirmationAction) {
            // [v25.602 v2]〔一次評全課〕後面還有人：右上換成〔下一位 ›〕（底部那一行的〔儲存〕照舊）
            if batchHasNext {
                Button { nextTapped() } label: { Text("下一位 ›") }
                    .accessibilityLabel("下一位")
            } else {
            Button("儲存") { save() }
                .disabled(!canSave)
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("完成") { endEditing() }
        }
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // [v25.602 v2]〔一次評全課〕最上面一行「2／3　陳怡君」
                    if let b = request.batch {
                        CompRatingBatchHeader(text: b.positionText)
                    }
                    topCard
                    if loaded && sections.isEmpty {
                        CompRatingEmptyNote()
                    }
                    ForEach(sections) { sec in
                        sectionBlock(sec)
                    }
                    noteCard
                }
                .disabled(readOnly)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .onChange(of: scrollTarget) { _, newValue in
                guard let k = newValue else { return }
                scrollTarget = nil
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(k, anchor: .center)
                }
            }
        }
        // [v25.602 v2]〔下一位 ›〕有改沒存時的 3 選 1（掛在 content 上，不跟 body 的「不儲存就關掉？」擠同一個 View）
        .modifier(CompRatingNextAsk(isPresented: $showNextAsk, canSave: canSave,
                                    onSave: { save() }, onSkip: { goNext() }))
    }

    /// [v25.600 職能雷達 v1a-2 裁定] 評分紀錄〔改分數〕打開的那一張：日期不能在這裡改（改了會在別天多存一張、原本那一張還在）；
    /// 搬日子用明細頁的〔改日期〕。要退回這一件：刪這個 var、topCard 的 dateLocked 那一行、CompRatingTopCard 的 dateLocked
    private var dateLocked: Bool {
        guard let sid = request.sessionId, let e = editing else { return false }
        return e.id == sid
    }

    private var topCard: some View {
        CompRatingTopCard(date: $date,
                          dateLocked: dateLocked,
                          infoLine: editingLine,
                          joinWarning: joinWarningLine,
                          readOnlyLine: readOnly ? "這台的 App 比較舊，評分請在已更新的那台做" : nil,
                          chips: chips,
                          carryAllTitle: carryAllTitle,
                          carryAllEnabled: carryAllEnabled,
                          onToggle: { id in toggleIncluded(id) },
                          onCarryAll: { carry(includedSections) })
    }

    @ViewBuilder
    private func sectionBlock(_ sec: CompetencyRatingSection) -> some View {
        if included.contains(sec.id) {
            CompRatingSectionView(section: sec,
                                  rows: rowModels(sec),
                                  actions: actions,
                                  focus: $focusedKey,
                                  onCarry: { carry([sec]) })
        } else {
            CompRatingCollapsedRow(title: sec.title, tint: CompetencyPalette.tint(isTrait: sec.isTrait))
        }
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("總評")
                .font(.subheadline.weight(.semibold))
            TextField("總評（只有你看得到）", text: $note, axis: .vertical)
                .lineLimit(2...6)
                .focused($noteFocused)
                .padding(10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 1))
    }

    private var footer: some View {
        let c: CompetencyFooterCounts = counts
        return CompRatingFooter(text: CompetencyMath.footerText(c),
                                targetLine: targetLine,
                                canSave: canSave,
                                onSave: { save() })
    }

    /// [v25.601 v1b] 底部「E2 達標 10／12」：算哪幾區跟 counts 同一條（新的一張只算勾了的區；改已經有的那一張算全部，
    /// 沒勾的區 effectiveDraft 原樣放回去）。沒職等、沒目標 nil
    private var targetLine: String? {
        guard !targetMarks.isEmpty else { return nil }
        let secs: [CompetencyRatingSection] = editing == nil ? includedSections : sections
        return CompetencyMath.ratingTargetLine(marks: targetMarks, sections: secs, draft: effectiveDraft)
    }

    // MARK: 算好給畫面的

    private var subordinate: Subordinate? {
        lifeStore.subordinates.first { $0.id == request.subordinateId }
    }

    private var personName: String {
        let n: String = (subordinate?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "這位同仁" : n
    }

    private var readOnly: Bool { lifeStore.competencyReadOnly }

    private var includedSections: [CompetencyRatingSection] {
        sections.filter { included.contains($0.id) }
    }

    /// 存檔、底部那一行用的草稿：勾了的區＋（改已經有的那一張時）沒勾的區原樣放回去（不然 buildSession 會蓋 clearedAt）
    private var effectiveDraft: [CompetencyCellKey: CompetencyDraftCell] {
        var out: [CompetencyCellKey: CompetencyDraftCell] = [:]
        for (k, c) in draft where included.contains(k.groupId) && c.isSet {
            out[k] = c
        }
        if let e = editing {
            let original: [CompetencyCellKey: CompetencyDraftCell] = CompetencyMath.draft(from: e)
            for (k, c) in original where !included.contains(k.groupId) {
                out[k] = c
            }
        }
        return out
    }

    /// [v25.600 v1a-2] 改已經有的那一張時跟打開時比（baseline＝打開時的 draft(from:)）：沒改「沒有改動（這一張 12 格）」。
    /// 改已經有的那一張時算全部的區：沒勾「這次評」的區 effectiveDraft 原樣放回去 → 算「沒動」（不然「這一張 N 格」會變少）；
    /// 新的一張照 v1a-1 只算勾了的區。要退回這一件：baseline 拿掉、sections 改回 includedSections（＝v1a-1）
    private var counts: CompetencyFooterCounts {
        let baseline: [CompetencyCellKey: CompetencyDraftCell]? = editing == nil ? nil : initialDraft
        let secs: [CompetencyRatingSection] = editing == nil ? includedSections : sections
        return CompetencyMath.footerCounts(draft: effectiveDraft, sections: secs, baseline: baseline)
    }

    /// 新的一張：有評 1 格以上才能存（數字欄打了會改的數字也算：按儲存時先算數）；改已經有的那一張：有改格子或總評才亮；
    /// 數字欄打了不是數字 → 灰；唯讀不能存。[v25.600 v1a-2] 規則在 CompetencyMath.canSave（sim 對照）
    private var canSave: Bool {
        guard loaded, !readOnly else { return false }
        return CompetencyMath.canSave(counts: counts, noteChanged: note != initialNote,
                                      pendingChange: hasPendingChange, invalidInput: hasInvalidInput)
    }

    /// [v25.600 v1a-2] 數字欄每一格打的字（只看這次評的區）：空白、跟現在一樣 → 不算改；會改 → .changed；不是數字 → .invalid
    private var inputChecks: [CompetencyInputCheck] {
        var out: [CompetencyInputCheck] = []
        for (k, t) in inputText where included.contains(k.groupId) {
            guard let sec = sections.first(where: { $0.id == k.groupId }) else { continue }
            out.append(CompetencyMath.checkInput(t, current: currentValue(k), range: sec.range))
        }
        return out
    }

    /// 數字欄打了會改分數的數字、還沒離開欄位（打一樣的數字不算）
    private var hasPendingChange: Bool {
        inputChecks.contains { c in
            if case .changed(_) = c { return true }
            return false
        }
    }

    /// 數字欄打了不是數字（兩顆〔儲存〕都灰）
    private var hasInvalidInput: Bool {
        inputChecks.contains(.invalid)
    }

    /// 這一格現在的分數（沒評、不適用 nil）
    private func currentValue(_ key: CompetencyCellKey) -> Int? {
        guard let c = draft[key], !c.na else { return nil }
        return c.value
    }

    /// 有改：關掉先問「不儲存就關掉？」（數字欄打一樣的數字不算改）
    private var hasChanges: Bool {
        draft != initialDraft || note != initialNote || hasPendingChange
    }

    /// 「今天已經評過一次，這次會改那一張」「10/30 已經有一張，這次會改那一張」
    private var editingLine: String? {
        guard editing != nil else { return nil }
        if dayKey == today { return "今天已經評過一次，這次會改那一張" }
        return CompetencyMath.shortDay(dayKey) + " 已經有一張，這次會改那一張"
    }

    /// 早於報到日：「這天王小明還沒報到，確定嗎？」（橘字、照樣能存）
    private var joinWarningLine: String? {
        guard let j = subordinate?.joinDate else { return nil }
        let joinKey: String = CompetencyMath.dayKey(j)
        guard !dayKey.isEmpty, dayKey < joinKey else { return nil }
        return "這天" + personName + "還沒報到，確定嗎？"
    }

    private var chips: [CompRatingChip] {
        var out: [CompRatingChip] = []
        // [v25.600 v1a-2] 膠囊寫短名（系統有短名寫短名）。要退回這一件：chipTitle 改回 title
        for sec in sections {
            out.append(CompRatingChip(id: sec.id, title: sec.chipTitle, isOn: included.contains(sec.id),
                                      tint: CompetencyPalette.tint(isTrait: sec.isTrait)))
        }
        return out
    }

    /// 〔全部照上次（4/30）〕：勾了的區裡能照上次的格子，最新的那一天；沒有就不出現
    private var carryAllTitle: String? {
        var best: String? = nil
        for sec in includedSections where sec.canCarry {
            for ax in sec.axes where ax.previousSameRange {
                guard let d = ax.previous?.dayKey else { continue }
                if best == nil || d > (best ?? "") { best = d }
            }
        }
        guard let b = best else { return nil }
        return "全部照上次（" + CompetencyMath.shortDay(b) + "）"
    }

    /// 還有空格可以帶才按得下去
    private var carryAllEnabled: Bool {
        let cells: [CompetencyCellKey: CompetencyDraftCell] = CompetencyMath.carriedCells(includedSections)
        return cells.keys.contains { draft[$0]?.isSet != true }
    }

    /// 勾了的區、照畫面順序的每一格（自動捲用）
    private var orderedKeys: [CompetencyCellKey] {
        var out: [CompetencyCellKey] = []
        for sec in includedSections {
            for ax in sec.axes {
                out.append(CompetencyCellKey(groupId: sec.id, itemId: ax.id))
            }
        }
        return out
    }

    private var actions: CompRatingActions {
        CompRatingActions(
            tap: { k, v in tapValue(k, v) },
            setValue: { k, v in setValueQuietly(k, v) },
            confirm: { k in confirmCarried(k) },
            clear: { k in clearCell(k) },
            na: { k in toggleNA(k) },
            adjust: { k, up in adjust(k, up: up) },
            text: { k in textBinding(k) })
    }

    /// 一區的每一列（body 不寫長運算式：字、狀態都在這裡算好）
    private func rowModels(_ sec: CompetencyRatingSection) -> [CompRatingRowModel] {
        let tint: Color = CompetencyPalette.tint(isTrait: sec.isTrait)
        let scale: CompetencyScale? = lifeStore.competencySetup.scaleFor(group: sec.id)
        // 每一分的名字只在範圍一樣時才寫（改舊紀錄用舊範圍時不寫；§13 出廠沒有名字 → 都是 nil）
        // [v25.600 v1a-2 驗證修] 超過 11 級（例 0–100）不寫名字（§13；1–5 時設的名字在 0–100 裡還留著）。要退回這一件：拿掉 && 後面
        let namesOK: Bool = scale?.range == sec.range && CompetencyMath.namesAllowed(sec.range)
        var out: [CompRatingRowModel] = []
        for ax in sec.axes {
            let key = CompetencyCellKey(groupId: sec.id, itemId: ax.id)
            let cell: CompetencyDraftCell? = draft[key]
            let na: Bool = cell?.na == true
            let value: Int? = na ? nil : cell?.value
            let carried: Bool = cell?.carried == true && cell?.isSet == true
            let isConfirmed: Bool = confirmed.contains(key)
            var level: String? = nil
            if namesOK, let v = value { level = scale?.levelName(v) }
            let spoken: String = compRatingSpokenValue(cell: cell, level: level, carried: carried,
                                                       previous: ax.previous, range: sec.range)
            let invalid: String? = invalidNote(key, value: value, range: sec.range)
            // [v25.601 v1b] 目標「E2 目標 3 ✓」、選中那一分的說明「能教人：…」（照上次的淡框也寫）
            let target: String? = targetMarks[key].map {
                CompetencyMath.ratingTargetRowText($0, value: value, na: na, range: sec.range)
            }
            var detail: String? = nil
            if namesOK, !na, let v = value {
                detail = detailLine(scale: scale, itemId: ax.id, value: v, level: level, range: sec.range)
            }
            // VoiceOver 也念紅字（整列是 children: .ignore，只念 a11yValue）
            var spokenAll: String = spoken
            if let w = invalid { spokenAll += "，" + w }
            // [v25.601 v1b 審查修] VoiceOver 不念「✓」的符號名稱：念「E2 目標 3，達標」（跟雷達那一句一樣）
            if let tx = target { spokenAll += "，" + tx.replacingOccurrences(of: " ✓", with: "，達標") }
            if let dl = detail { spokenAll += "，" + dl }
            let row = CompRatingRowModel(id: key, name: ax.name, sectionTitle: sec.title, isNew: ax.isNew,
                                         archived: ax.archived,
                                         range: sec.range, tint: tint, value: value, na: na,
                                         faint: carried && !isConfirmed, carriedConfirmed: carried && isConfirmed,
                                         levelName: level, previousText: ax.previousText,
                                         previousNearest: ax.previousNearest, clampNote: clampNotes[key],
                                         invalidNote: invalid, a11yValue: spokenAll,
                                         targetText: target, detailLine: detail)
            out.append(row)
        }
        return out
    }

    /// [v25.601 v1b] 選中那一分的說明一行（項目自己的蓋過等級表的；§13 沒寫說明 nil）
    private func detailLine(scale: CompetencyScale?, itemId: UUID, value v: Int, level: String?,
                            range: CompetencyRange) -> String? {
        let item: CompetencyItem? = lifeStore.competencySetup.item(itemId)
        guard let d = CompetencyMath.levelDetail(scale: scale, item: item, value: v, range: range) else { return nil }
        return CompetencyMath.levelDetailLine(value: v, name: level, detail: d)
    }

    /// [v25.600 v1a-2] 數字欄打了不是數字：那一格下面紅字「請打 0～100 的整數」（打一樣的、會改的、空白都沒有）
    private func invalidNote(_ key: CompetencyCellKey, value: Int?, range: CompetencyRange) -> String? {
        guard let t = inputText[key] else { return nil }
        let check: CompetencyInputCheck = CompetencyMath.checkInput(t, current: value, range: range)
        return check == .invalid ? CompetencyMath.invalidInputText(range) : nil
    }

    // MARK: 打開、換日子

    private func loadIfNeeded() {
        guard !loaded else { return }
        let t: String = CompetencyMath.dayKey(Date())
        let sessions: [CompetencySession] = lifeStore.competencySessions(of: request.subordinateId)
        // [v25.600 v1a-2] 評分紀錄〔改分數〕：打開的就是那一張（日子＝那一張的日子），不走 sessionOn。
        // 要退回這一件：target 拿掉（＝v1a-1 照 dayKey 找）
        let target: CompetencySession? = requestedSession()
        var key: String = target?.dayKey ?? request.dayKey ?? t
        if target == nil && (key > t || CompetencyMath.parseDay(key) == nil) { key = t }
        today = t
        dayKey = key
        // 今天就用現在（中午 12 點在上午會晚於 DatePicker 的上限 ...Date()）；以前的日子用那天中午
        //（那一張的日子在這台時區晚於今天時也用現在：DatePicker 不能超過 ...Date()）
        // [v25.601 v1b] compRatingDate 搬進 CompetencyMath.noonDate（sim 台北、洛杉磯對過）
        if key < t, let d = CompetencyMath.noonDate(key) { date = d }
        openedTrait = lifeStore.competencySetup.traitRange
        openedSkill = lifeStore.competencySetup.skillRange
        let e: CompetencySession? = target ?? CompetencyMath.sessionOn(key, sessions: sessions)
        openSession(e, sessions: sessions, keepDraft: false)
        loaded = true
    }

    /// [v25.600 v1a-2] request.sessionId 那一張還在（沒刪、我評的、是這位同仁的、日子認得）才用；不然 nil（照日子找）
    private func requestedSession() -> CompetencySession? {
        guard let id = request.sessionId, let s = lifeStore.competencyRatings.session(id) else { return nil }
        guard s.isLive, s.isByMe, s.subordinateId == request.subordinateId else { return nil }
        guard CompetencyMath.parseDay(s.dayKey) != nil else { return nil }
        return s
    }

    /// 改日期：那一天已經有一張 → 直接換成那一張；沒有 → 保留現在的草稿（範圍外的、這一天沒有的格子拿掉）
    private func dateChanged(_ d: Date) {
        guard loaded else { return }
        let key: String = CompetencyMath.dayKey(d)
        guard key != dayKey else { return }
        commitAllInput()
        focusedKey = nil
        dayKey = key
        let sessions: [CompetencySession] = lifeStore.competencySessions(of: request.subordinateId)
        let e: CompetencySession? = CompetencyMath.sessionOn(key, sessions: sessions)
        openSession(e, sessions: sessions, keepDraft: true)
    }

    private func openSession(_ e: CompetencySession?, sessions: [CompetencySession], keepDraft: Bool) {
        let oldIds: Set<UUID> = Set(sections.map { $0.id })
        let plan: [CompetencyRatingSection] = CompetencyMath.ratingPlan(setup: lifeStore.competencySetup,
                                                                       subordinateId: request.subordinateId,
                                                                       sessions: sessions, dayKey: dayKey, editing: e)
        let ids: Set<UUID> = Set(plan.map { $0.id })
        let kept: [CompetencyCellKey: CompetencyDraftCell] = keepDraft ? keptDraft(for: plan) : [:]
        editing = e
        sections = plan
        // [v25.601 v1b] 每一格的目標（換到這一張的範圍；照這位現在的職等）。要退回這一件：刪這一行
        targetMarks = CompetencyMath.ratingTargetMarks(setup: lifeStore.competencySetup,
                                                       grade: lifeStore.competencyCurrentGrade(for: request.subordinateId),
                                                       sections: plan)
        if e == nil {
            // 新的一張：ratingPlan 用的是設定現在的範圍 → 存檔的範圍跟畫面上這一份一樣
            // （一打開時就是打開時的範圍；只有換日子時別台剛好改了範圍才會不同）
            openedTrait = lifeStore.competencySetup.traitRange
            openedSkill = lifeStore.competencySetup.skillRange
        }
        if keepDraft {
            included = included.intersection(ids).union(ids.subtracting(oldIds))
        } else {
            included = ids
            // [v25.602 v2]〔一次評全課〕：預設只勾選的組（跟這一張的組取交集；交集空照舊全勾）
            if let b = request.batch {
                let pick: Set<UUID> = ids.intersection(b.groupIds)
                included = pick.isEmpty ? ids : pick
            }
        }
        inputText = [:]
        clampNotes = [:]
        if let e {
            let d: [CompetencyCellKey: CompetencyDraftCell] = CompetencyMath.draft(from: e)
            let n: String = e.note ?? ""
            draft = d
            confirmed = []
            note = n
            initialDraft = d
            initialNote = n
        } else if keepDraft {
            draft = kept
            confirmed = confirmed.filter { kept[$0]?.carried == true }
            initialDraft = [:]
            initialNote = ""
        } else {
            draft = [:]
            confirmed = []
            note = ""
            initialDraft = [:]
            initialNote = ""
        }
    }

    /// 換到沒有評分的日子時留下來的格子：這一天的區裡有、分數在範圍內；照上次的格子跟新的「上一次」不一樣就變成這次評的
    private func keptDraft(for plan: [CompetencyRatingSection]) -> [CompetencyCellKey: CompetencyDraftCell] {
        var out: [CompetencyCellKey: CompetencyDraftCell] = [:]
        var oldRanges: [UUID: CompetencyRange] = [:]
        for old in sections { oldRanges[old.id] = old.range }
        for sec in plan {
            // 範圍不一樣（例：從用 1–5 的舊那一張換到用 1–10 的新日子）：原始分數意思不同，不帶
            if let r = oldRanges[sec.id], r != sec.range { continue }
            for ax in sec.axes {
                let key = CompetencyCellKey(groupId: sec.id, itemId: ax.id)
                guard var c = draft[key], c.isSet else { continue }
                if !c.na, let v = c.value, !sec.range.contains(v) { continue }
                if c.carried {
                    let p: CompetencyCellValue? = ax.previous
                    let sameNA: Bool = p?.na == c.na
                    let sameValue: Bool = c.na || p?.value == c.value
                    if !(ax.previousSameRange && sameNA && sameValue) { c.carried = false }
                }
                out[key] = c
            }
        }
        return out
    }

    // MARK: 動作

    private func toggleIncluded(_ id: UUID) {
        if included.contains(id) {
            included.remove(id)
        } else {
            included.insert(id)
        }
    }

    /// 〔全部照上次〕／〔這組照上次〕：只填還空著的格子（不蓋你已經點的）
    private func carry(_ secs: [CompetencyRatingSection]) {
        let cells: [CompetencyCellKey: CompetencyDraftCell] = CompetencyMath.carriedCells(secs)
        for (k, c) in cells where draft[k]?.isSet != true {
            draft[k] = c
            confirmed.remove(k)
            clampNotes[k] = nil
        }
    }

    /// 點一個數字（按鈕、數字欄打完）：從空變有值時，下一格還空才捲過去
    private func tapValue(_ key: CompetencyCellKey, _ v: Int) {
        let wasSet: Bool = draft[key]?.isSet == true
        applyValue(key, v)
        if !wasSet && draft[key]?.isSet == true { scrollToNext(after: key) }
    }

    /// 滑桿、〔－〕〔＋〕、VoiceOver 上下滑：不捲（拖到一半被捲走很難用）
    private func setValueQuietly(_ key: CompetencyCellKey, _ v: Int) {
        clampNotes[key] = nil
        // [v25.600 v1a-2] 數字欄打了一半（或打了不是數字）又動滑桿／〔－〕〔＋〕：以最後動的為準，欄位改寫成新的分數
        inputText[key] = nil
        applyValue(key, v)
    }

    /// 淡框那一格點同一個值＝確認（值不變、還是算照上次）；實心再點同一個值什麼都不做；點別的數字＝這次評的
    private func applyValue(_ key: CompetencyCellKey, _ v: Int) {
        let old: CompetencyDraftCell? = draft[key]
        if let o = old, !o.na, o.value == v {
            if o.carried { confirmed.insert(key) }
            return
        }
        draft[key] = CompetencyDraftCell(value: v, na: false, comment: old?.comment, carried: false)
        confirmed.remove(key)
    }

    private func confirmCarried(_ key: CompetencyCellKey) {
        if draft[key]?.carried == true { confirmed.insert(key) }
    }

    /// 〔⋯〕〔清掉〕、VoiceOver 在最低分再往下
    private func clearCell(_ key: CompetencyCellKey) {
        draft[key] = nil
        confirmed.remove(key)
        clampNotes[key] = nil
        inputText[key] = nil
    }

    /// [v25.600 v1a-2]〔⋯〕〔不適用〕／〔取消不適用〕（judge §3.7-5）：已經是不適用 → 清掉（未評）；不是 → 標不適用
    /// （不畫頂點、不算平均）。別台寫的那一格評語原樣帶著（§13 每一格的評語不做、不顯示）。從空變不適用時下一格空的才捲。
    /// 點任何一個分數＝改回評分（applyValue 會蓋掉不適用）。要退回這一件：拿掉這支與 CompRatingActions.na
    private func toggleNA(_ key: CompetencyCellKey) {
        if draft[key]?.na == true {
            clearCell(key)
            return
        }
        let old: CompetencyDraftCell? = draft[key]
        let wasSet: Bool = old?.isSet == true
        draft[key] = CompetencyDraftCell(value: nil, na: true, comment: old?.comment, carried: false)
        confirmed.remove(key)
        clampNotes[key] = nil
        inputText[key] = nil
        if focusedKey == key { focusedKey = nil }
        if !wasSet { scrollToNext(after: key) }
    }

    /// VoiceOver 上下滑：往上 未評 → 最低分、v → v+1；往下 v → v−1、最低分 → 清掉（未評）
    private func adjust(_ key: CompetencyCellKey, up: Bool) {
        guard let sec = sections.first(where: { $0.id == key.groupId }) else { return }
        let r: CompetencyRange = sec.range
        let cell: CompetencyDraftCell? = draft[key]
        let current: Int? = cell?.na == true ? nil : cell?.value
        if up {
            if let v = current {
                if v < r.high { setValueQuietly(key, v + 1) }
            } else {
                setValueQuietly(key, r.low)
            }
        } else {
            guard let v = current else { return }
            if v > r.low {
                setValueQuietly(key, v - 1)
            } else {
                clearCell(key)
            }
        }
    }

    private func scrollToNext(after key: CompetencyCellKey) {
        guard !reduceMotion else { return }
        let keys: [CompetencyCellKey] = orderedKeys
        guard let i = keys.firstIndex(of: key), i + 1 < keys.count else { return }
        let next: CompetencyCellKey = keys[i + 1]
        if draft[next]?.isSet == true { return }
        scrollTarget = next
    }

    // MARK: 數字欄（§13：high > 10）

    private func textBinding(_ key: CompetencyCellKey) -> Binding<String> {
        Binding(
            get: { inputText[key] ?? valueString(key) },
            set: { inputText[key] = $0 })
    }

    private func valueString(_ key: CompetencyCellKey) -> String {
        guard let c = draft[key], !c.na, let v = c.value else { return "" }
        return "\(v)"
    }

    private func focusChanged(from old: CompetencyCellKey?, to new: CompetencyCellKey?) {
        guard let o = old, o != new else { return }
        commitInput(o)
    }

    /// 離開數字欄才算數：全形也認；超出範圍夾回並提示；空白＝不改。
    /// [v25.600 v1a-2] 不是數字＝不改，而且字留著（紅字「請打 0～100 的整數」、〔儲存〕灰，到改對或清掉為止）。
    /// 要退回這一件：parse 失敗那一行的 inputText[key] = raw 拿掉
    private func commitInput(_ key: CompetencyCellKey) {
        guard let raw = inputText[key] else { return }
        inputText[key] = nil
        guard let sec = sections.first(where: { $0.id == key.groupId }) else { return }
        let trimmed: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        guard let parsed = CompetencyMath.parseInput(trimmed, sec.range) else {
            inputText[key] = raw
            return
        }
        tapValue(key, parsed.value)
        if parsed.clamped {
            clampNotes[key] = "超出範圍，改成 \(parsed.value)"
        } else {
            clampNotes[key] = nil
        }
    }

    /// 每一個打到一半的數字欄都算數
    private func commitAllInput() {
        let keys: [CompetencyCellKey] = Array(inputText.keys)
        for k in keys { commitInput(k) }
    }

    private func endEditing() {
        commitAllInput()
        focusedKey = nil
        noteFocused = false
    }

    // MARK: 關掉、儲存

    /// [v25.602 v2]〔一次評全課〕後面還有人（右上〔下一位 ›〕）
    private var batchHasNext: Bool {
        request.batch?.hasNext == true
    }

    /// [v25.602 v2]〔下一位 ›〕：有改沒存先問；沒改直接換下一位
    private func nextTapped() {
        endEditing()
        if hasChanges {
            showNextAsk = true
        } else {
            goNext()
        }
    }

    /// [v25.602 v2] 這一位不存、換下一位（host 在 onNext 記下要換人，sheet 關掉後開下一位）
    private func goNext() {
        let callback: (() -> Void)? = onNext
        callback?()
        dismiss()
    }

    private func cancelTapped() {
        endEditing()
        if hasChanges {
            showDiscard = true
        } else {
            dismiss()
        }
    }

    /// 沒有確認框；先 dismiss，下一個 runloop 再寫 store
    private func save() {
        commitAllInput()
        guard canSave else { return }
        guard subscription.isPremium else {
            showPremiumAlert = true
            return
        }
        let gradeId: UUID? = subordinate?.gradeTitleId
        let s: CompetencySession = CompetencyMath.buildSession(
            existing: editing, newId: UUID(), subordinateId: request.subordinateId, dayKey: dayKey,
            traitRange: openedTrait, skillRange: openedSkill, draft: effectiveDraft, sections: sections,
            setup: lifeStore.competencySetup, note: note, gradeTitleId: gradeId, gradeLabel: gradeLabel(gradeId),
            now: Date())
        let toast: String = CompetencyMath.savedToast(s)
        let store: LifeStore = lifeStore
        let callback: ((String) -> Void)? = onSaved
        dismiss()
        DispatchQueue.main.async {
            store.saveCompetencySession(s)
            callback?(toast)
        }
    }

    /// 職等快照「E2 工程師」（沒有就 nil）
    private func gradeLabel(_ id: UUID?) -> String? {
        guard let id, let gt = lifeStore.gradeTitles.first(where: { $0.id == id }) else { return nil }
        let s: String = (gt.grade + " " + gt.title).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}

// MARK: - 小函式（純；下一版主控再搬進 CompetencyMath＋sim）
// [v25.601 v1b] 「2026-10-30」→ 那一天中午的那一支已經搬進 CompetencyMath.noonDate

/// VoiceOver 的值：「4 分，上次 2 分」「4 分，照上次」「未評，上次 2 分」「不適用」
fileprivate func compRatingSpokenValue(cell: CompetencyDraftCell?, level: String?, carried: Bool,
                                       previous: CompetencyCellValue?, range: CompetencyRange) -> String {
    var parts: [String] = []
    if cell?.na == true {
        parts.append("不適用")
    } else if let v = cell?.value {
        parts.append("\(v) 分")
        if let level { parts.append(level) }
    } else {
        parts.append("未評")
    }
    if carried {
        parts.append("照上次")
    } else if let p = previous {
        let pt: String = p.na ? "不適用" : (CompetencyMath.cellText(p, in: range) + " 分")
        parts.append("上次 " + pt)
    }
    return parts.joined(separator: "，")
}

/// [v25.602 v2] VoiceOver：「2／3　陳怡君」→「第 2 位，共 3 位，陳怡君」（認不出來照原字念）
fileprivate func compRatingBatchSpoken(_ text: String) -> String {
    guard let sp = text.range(of: "　") else { return text }
    let head: String = String(text[..<sp.lowerBound])
    let name: String = String(text[sp.upperBound...])
    let parts: [String] = head.components(separatedBy: "／")
    guard parts.count == 2 else { return text }
    return "第 " + parts[0] + " 位，共 " + parts[1] + " 位，" + name
}

// MARK: - [v25.602 v2]〔一次評全課〕的小零件

/// 最上面一行「2／3　陳怡君」
private struct CompRatingBatchHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(compRatingBatchSpoken(text))
    }
}

/// 〔下一位 ›〕時這一位有改沒存：〔儲存，下一位〕（存得了才有；存完 host 換下一位）〔不儲存，下一位〕〔繼續評分〕
private struct CompRatingNextAsk: ViewModifier {
    @Binding var isPresented: Bool
    let canSave: Bool
    let onSave: () -> Void
    let onSkip: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("這一位還沒儲存", isPresented: $isPresented, titleVisibility: .visible) {
                if canSave {
                    Button("儲存，下一位") { onSave() }
                }
                Button("不儲存，下一位", role: .destructive) { onSkip() }
                Button("繼續評分", role: .cancel) {}
            }
    }
}

// MARK: - 畫面要的小 struct

/// 一列要的全部東西（rowModels(_:) 算好）
private struct CompRatingRowModel: Identifiable {
    let id: CompetencyCellKey
    let name: String
    let sectionTitle: String
    let isNew: Bool
    /// [v25.600 v1a-2] 改舊紀錄時：這一項現在已停用（或這個系統拿掉了），名字後面灰字「已停用」
    let archived: Bool
    let range: CompetencyRange
    let tint: Color
    /// 這次的分數（不適用 nil）
    let value: Int?
    let na: Bool
    /// 照上次帶進來、還沒點（淡框）
    let faint: Bool
    /// 照上次帶進來、點過一下（實心；還是算照上次）
    let carriedConfirmed: Bool
    let levelName: String?
    let previousText: String?
    let previousNearest: Int?
    let clampNote: String?
    /// [v25.600 v1a-2] 數字欄打了不是數字：「請打 0～100 的整數」（紅字）
    let invalidNote: String?
    let a11yValue: String
    /// [v25.601 v1b]「E2 目標 3 ✓」「E2 目標 3・差 1」「E2 目標 3」（沒職等、沒目標 nil）
    let targetText: String?
    /// [v25.601 v1b] 選中那一分的說明「能教人：…」「4 分：…」（§13 沒寫說明 nil）
    let detailLine: String?

    var usesButtons: Bool { range.usesButtons }
    /// [v25.601 v1b] 目標那一行的顏色：達標（結尾 ✓）綠、有差橘、沒評灰
    var targetColor: Color {
        guard let t = targetText else { return Color.secondary }
        if t.hasSuffix("✓") { return Color.green }
        if t.contains("差") { return Color.orange }
        return Color.secondary
    }
    var buttonRows: [[Int]] { CompetencyMath.buttonRows(range) }
    var isSet: Bool { value != nil || na }
    /// 「Gas System，緊急應變」
    var a11yLabel: String { sectionTitle + "，" + name }
    /// [v25.600 v1a-2]〔⋯〕與 VoiceOver 自訂動作的字：已經是不適用寫「取消不適用」
    var naTitle: String { na ? "取消不適用" : "不適用" }
}

/// 列要回呼的動作（sheet 那邊改 @State）
private struct CompRatingActions {
    let tap: (CompetencyCellKey, Int) -> Void
    let setValue: (CompetencyCellKey, Int) -> Void
    let confirm: (CompetencyCellKey) -> Void
    let clear: (CompetencyCellKey) -> Void
    /// [v25.600 v1a-2]〔不適用〕／〔取消不適用〕
    let na: (CompetencyCellKey) -> Void
    let adjust: (CompetencyCellKey, Bool) -> Void
    let text: (CompetencyCellKey) -> Binding<String>
}

/// 「這次評」一顆膠囊
private struct CompRatingChip: Identifiable {
    let id: UUID
    let title: String
    let isOn: Bool
    let tint: Color
}

private enum CompRatingButtonKind {
    /// 這次評的（實心主題色白字）
    case solid
    /// 照上次帶進來、還沒點（淡色外框）
    case faint
    /// 沒選
    case plain
}

// MARK: - 上面：日期、評分人、說明、這次評、全部照上次

private struct CompRatingTopCard: View {
    @Binding var date: Date
    /// [v25.600 v1a-2 裁定] 〔改分數〕打開的那一張：日期灰掉，下面一行說明
    let dateLocked: Bool
    let infoLine: String?
    let joinWarning: String?
    let readOnlyLine: String?
    let chips: [CompRatingChip]
    let carryAllTitle: String?
    let carryAllEnabled: Bool
    let onToggle: (UUID) -> Void
    let onCarryAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("日期", selection: $date, in: ...Date(), displayedComponents: .date)
                .disabled(dateLocked)
            if dateLocked {
                Text(Self.dateLockedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("評分人")
                Spacer()
                Text("我").foregroundStyle(.secondary)
            }
            CompRatingNotices(infoLine: infoLine, joinWarning: joinWarning, readOnlyLine: readOnlyLine)
            if !chips.isEmpty {
                CompRatingChipRow(chips: chips, onToggle: onToggle)
            }
            if let t = carryAllTitle {
                CompRatingCarryAllButton(title: t, enabled: carryAllEnabled, action: onCarryAll)
            }
        }
        .font(.subheadline)
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 1))
    }

    private static let dateLockedText: String = "要改這一次的日期，請用評分紀錄裡的〔改日期〕。"
}

private struct CompRatingNotices: View {
    let infoLine: String?
    let joinWarning: String?
    let readOnlyLine: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let s = readOnlyLine {
                Text(s).font(.caption).foregroundStyle(.orange)
            }
            if let s = infoLine {
                Text(s).font(.caption).foregroundStyle(.secondary)
            }
            if let s = joinWarning {
                Text(s).font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

private struct CompRatingChipRow: View {
    let chips: [CompRatingChip]
    let onToggle: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("這次評")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips) { c in
                        CompRatingChipButton(chip: c, action: { onToggle(c.id) })
                    }
                }
            }
        }
    }
}

private struct CompRatingChipButton: View {
    let chip: CompRatingChip
    let action: () -> Void

    private var fg: Color { chip.isOn ? chip.tint : Color.secondary }
    private var bg: Color { chip.isOn ? chip.tint.opacity(0.12) : Color(.tertiarySystemFill) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if chip.isOn {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                }
                Text(chip.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(bg, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chip.title)
        .accessibilityValue(chip.isOn ? "這次評" : "這次不評")
    }
}

private struct CompRatingCarryAllButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "arrow.uturn.backward")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CompetencyPalette.trait)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(CompetencyPalette.trait.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

private struct CompRatingEmptyNote: View {
    var body: some View {
        Text("沒有要評的項目。到 設定 → 職能項目 加人格特質或系統。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 一區（一組）

private struct CompRatingSectionView: View {
    let section: CompetencyRatingSection
    let rows: [CompRatingRowModel]
    let actions: CompRatingActions
    let focus: FocusState<CompetencyCellKey?>.Binding
    let onCarry: () -> Void

    private var tint: Color { CompetencyPalette.tint(isTrait: section.isTrait) }
    private var showsCarry: Bool { section.axes.contains { $0.previous != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CompRatingSectionHeader(title: section.title, rangeText: section.range.text, tint: tint,
                                    archived: section.archived,
                                    showsCarry: showsCarry, canCarry: section.canCarry,
                                    blockedNote: section.carryBlockedNote, onCarry: onCarry)
            ForEach(rows) { row in
                if row.id != rows.first?.id {
                    Divider()
                }
                CompRatingRow(model: row, actions: actions, focus: focus)
                    .id(row.id)
            }
        }
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 1))
    }
}

/// 「人格特質（1–5）」＋〔這組照上次〕；範圍改過寫「範圍改過（1–5 → 1–10），這組要重新點」
private struct CompRatingSectionHeader: View {
    let title: String
    let rangeText: String
    let tint: Color
    /// [v25.600 v1a-2] 改舊紀錄時：這個系統現在已停用（或這位不用學），標題後面灰字「已停用」
    let archived: Bool
    let showsCarry: Bool
    let canCarry: Bool
    let blockedNote: String?
    let onCarry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tint)
                    .frame(width: 3, height: 16)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                Text("（" + rangeText + "）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if archived {
                    Text("已停用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if showsCarry {
                    Button("這組照上次", action: onCarry)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(canCarry ? tint : Color.secondary)
                        .disabled(!canCarry)
                }
            }
            if let n = blockedNote {
                Text(n)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.bottom, 4)
    }
}

/// 這次不評的區：收起來只剩一行
private struct CompRatingCollapsedRow: View {
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(tint.opacity(0.5))
                .frame(width: 3, height: 14)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("這次不評")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.systemBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 一列（一格）

private struct CompRatingRow: View {
    let model: CompRatingRowModel
    let actions: CompRatingActions
    let focus: FocusState<CompetencyCellKey?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CompRatingRowTitle(name: model.name, isNew: model.isNew, archived: model.archived,
                               canClear: model.isSet, naTitle: model.naTitle, tint: model.tint,
                               onNA: { actions.na(model.id) }, onClear: { actions.clear(model.id) })
            input
            CompRatingRowCaption(model: model)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.a11yLabel)
        .accessibilityValue(model.a11yValue)
        .accessibilityAdjustableAction { direction in
            adjust(direction)
        }
        .accessibilityAction(named: model.naTitle) { actions.na(model.id) }
        .accessibilityAction(named: "清掉") { actions.clear(model.id) }
    }

    @ViewBuilder
    private var input: some View {
        if model.usesButtons {
            CompRatingButtons(rows: model.buttonRows, selected: model.value, faint: model.faint,
                              carriedConfirmed: model.carriedConfirmed, previousNearest: model.previousNearest,
                              levelName: model.levelName, tint: model.tint,
                              onTap: { v in actions.tap(model.id, v) })
        } else {
            CompRatingSlider(model: model, text: actions.text(model.id), focus: focus,
                             onSet: { v in actions.setValue(model.id, v) },
                             onConfirm: { actions.confirm(model.id) })
        }
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment:
            actions.adjust(model.id, true)
        case .decrement:
            actions.adjust(model.id, false)
        @unknown default:
            break
        }
    }
}

/// 名字（新增的項目標「新」、改舊紀錄時已停用的標「已停用」）＋〔⋯〕
/// [v25.600 v1a-2]〔⋯〕只有〔不適用〕（已經是不適用寫〔取消不適用〕）〔清掉〕——§13 每一格的評語不做。
private struct CompRatingRowTitle: View {
    let name: String
    let isNew: Bool
    let archived: Bool
    let canClear: Bool
    /// 「不適用」／「取消不適用」
    let naTitle: String
    let tint: Color
    let onNA: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            if isNew {
                Text("新")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint, in: Capsule())
            }
            if archived {
                Text("已停用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Menu {
                Button(naTitle) { onNA() }
                Button("清掉", role: .destructive) { onClear() }
                    .disabled(!canClear)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
    }
}

/// 下面小字：「上次 2（4/30）」、不適用、「超出範圍，改成 100」、[v25.600 v1a-2] 打了不是數字「請打 0～100 的整數」（紅）
private struct CompRatingRowCaption: View {
    let model: CompRatingRowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // [v25.601 v1b] 選中那一分的說明（有寫才有）
            if let dl = model.detailLine {
                Text(dl)
                    .font(.caption)
                    .foregroundStyle(model.tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.na {
                Text("不適用（點一個分數就改成評分）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let p = model.previousText {
                Text(p)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // [v25.601 v1b]「E2 目標 3 ✓」「E2 目標 3・差 1」
            if let tx = model.targetText {
                Text(tx)
                    .font(.caption2)
                    .foregroundStyle(model.targetColor)
            }
            if let c = model.clampNote {
                Text(c)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if let w = model.invalidNote {
                Text(w)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }
        }
    }
}

// MARK: - high ≤ 10：圓按鈕（≤ 6 級一排 44pt、7～11 級兩排 36pt）

private struct CompRatingButtons: View {
    let rows: [[Int]]
    let selected: Int?
    let faint: Bool
    let carriedConfirmed: Bool
    let previousNearest: Int?
    let levelName: String?
    let tint: Color
    let onTap: (Int) -> Void

    private var size: CGFloat { rows.count > 1 ? 36 : 44 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(rows[r], id: \.self) { v in
                        CompRatingButton(value: v, kind: kind(v), size: size, showsDot: v == previousNearest,
                                         caption: caption(v), tint: tint, action: { onTap(v) })
                    }
                }
            }
        }
    }

    private func kind(_ v: Int) -> CompRatingButtonKind {
        guard selected == v else { return .plain }
        return faint ? .faint : .solid
    }

    /// 選中那顆下面一行：淡框「照上次」；實心有名字才寫（§13 出廠沒有名字）；點過的照上次沒有名字時寫「照上次」
    private func caption(_ v: Int) -> String? {
        guard selected == v else { return nil }
        if faint { return "照上次" }
        if let n = levelName { return n }
        return carriedConfirmed ? "照上次" : nil
    }
}

private struct CompRatingButton: View {
    let value: Int
    let kind: CompRatingButtonKind
    let size: CGFloat
    let showsDot: Bool
    let caption: String?
    let tint: Color
    let action: () -> Void

    private var fill: Color {
        switch kind {
        case .solid: return tint
        case .faint: return tint.opacity(0.10)
        case .plain: return Color(.tertiarySystemFill)
        }
    }

    private var stroke: Color {
        kind == .faint ? tint.opacity(0.55) : Color.clear
    }

    private var textColor: Color {
        switch kind {
        case .solid: return Color.white
        case .faint: return tint
        case .plain: return Color.primary
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            Button(action: action) {
                Text("\(value)")
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(textColor)
                    .frame(width: size, height: size)
                    .background(Circle().fill(fill))
                    .overlay(Circle().stroke(stroke, lineWidth: 2))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            Circle()
                .fill(Color.gray)
                .frame(width: 4, height: 4)
                .opacity(showsDot ? 1 : 0)
            Text(caption ?? " ")
                .font(.caption2)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: size)
        }
    }
}

// MARK: - high > 10：滑桿（step 1）＋數字欄＋〔－〕〔＋〕（§13）

/// 還沒評時滑桿停在中間、淡色、數字欄空白、旁邊「未評」——不算評了；動過滑桿、打了數字、按〔－〕〔＋〕才算
private struct CompRatingSlider: View {
    let model: CompRatingRowModel
    let text: Binding<String>
    let focus: FocusState<CompetencyCellKey?>.Binding
    let onSet: (Int) -> Void
    let onConfirm: () -> Void

    private var range: CompetencyRange { model.range }
    private var current: Int { model.value ?? CompetencyMath.sliderPlaceholder(model.range) }
    private var lowD: Double { Double(range.low) }
    private var highD: Double { Double(range.high) }

    private var sliderOpacity: Double {
        if model.value == nil { return 0.4 }
        return model.faint ? 0.6 : 1
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(current) },
            set: { newValue in onSet(range.clamp(Int(newValue.rounded()))) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                stepButton("minus", delta: -1)
                Slider(value: sliderValue, in: lowD...highD, step: 1)
                    .tint(model.tint)
                    .opacity(sliderOpacity)
                stepButton("plus", delta: 1)
            }
            HStack(spacing: 8) {
                TextField(range.text, text: text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.body.monospacedDigit())
                    .frame(width: 64)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                    .focused(focus, equals: model.id)
                    .onSubmit { focus.wrappedValue = nil }
                CompRatingSliderStatus(model: model, onConfirm: onConfirm)
                Spacer(minLength: 0)
            }
        }
    }

    private func stepButton(_ icon: String, delta: Int) -> some View {
        Button {
            onSet(range.clamp(current + delta))
        } label: {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(model.tint)
                .frame(width: 36, height: 36)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// 數字欄旁邊：「未評」／照上次〔確認〕／「照上次」／每一分的名字
private struct CompRatingSliderStatus: View {
    let model: CompRatingRowModel
    let onConfirm: () -> Void

    var body: some View {
        if model.na {
            Text("不適用")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if model.value == nil {
            Text("未評")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if model.faint {
            HStack(spacing: 6) {
                Text("照上次")
                    .font(.caption)
                    .foregroundStyle(model.tint)
                Button("確認", action: onConfirm)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(model.tint)
            }
        } else if model.carriedConfirmed {
            Text("照上次")
                .font(.caption)
                .foregroundStyle(model.tint)
        } else if let n = model.levelName {
            Text(n)
                .font(.caption)
                .foregroundStyle(model.tint)
        }
    }
}

// MARK: - 底部固定一條

private struct CompRatingFooter: View {
    let text: String
    /// [v25.601 v1b]「E2 達標 10／12」（沒有 nil）
    let targetLine: String?
    let canSave: Bool
    let onSave: () -> Void

    private var buttonColor: Color { canSave ? CompetencyPalette.trait : Color.gray.opacity(0.5) }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let t = targetLine {
                    Text(t)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CompetencyPalette.trait)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onSave) {
                Text("儲存")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(buttonColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
}
