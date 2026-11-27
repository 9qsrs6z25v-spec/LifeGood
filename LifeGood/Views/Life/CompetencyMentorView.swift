import SwiftUI

// MARK: - [v25.606 職能雷達 v5a] 帶訓者頁（G1 負責；radar/judge_v5a.md §C1、§C2；radar/build/v5a/brief.md §3 G1）
//
// • 入口：〔職能〕分頁「…」〔帶訓者〕（擋訂閱；唯讀、已轉出不出現）、系統頁「誰在帶誰」點一列（只看）。sheet(item:)＋.appStores()。
// • 列出這位同仁要學的每一組（人格特質＋每個要學的系統）一列：「Gas System　陳怡君・從 5/4」或「還沒有」〔設定〕；
//   帶訓者被刪除／轉出：名字照快照、後面灰字「（已不在名冊）」，不自動拿掉。
// • 〔設定〕小表單：從名冊挑（在職、排除自己）或〔名冊外的人〕自己打名字（最多 10 字）；開始日（DatePicker in: ...今天，預設今天）；
//   〔拿掉帶訓者〕。一組一位（換人＝蓋掉；舊的帶訓者評照留、紀錄上寫當時的名字）。
// • 每一列〔記這位帶訓者的評分〕：既有的 CompetencyRatingSheet，request.rater＝那一列的 rater（擋訂閱）。
// • 規則、字全部在 CompetencyMath（mentorRows、mentorCandidates、cleanMentorName…）；寫入只走 LifeStore.setCompetencyMentor／
//   clearCompetencyMentor（一次 batched）；dismiss 後寫 store 放下一個 runloop。看不擋、動手才擋（isPremium／premiumLockAlert）。
// • 字不用「他／她」：名字、「這位同仁」、「帶訓者」。通知、小工具、手錶、鎖定畫面、靈動島一個字都不加。
// 骨架（主控）：CompetencyMentorRequest、CompetencyMentorView(subordinateId:) 是跨組契約（〔職能〕分頁、系統頁在叫），不准改；
// body 由 G1 換成真的。自己加的型別一律 private、CompMentor… 前綴。
// 要退回這一件：這個檔連同 pbxproj 四處（A01A／A01B000001001649）拿掉，叫它的那幾行拿掉。
// [G1] 已轉出、這台比較舊：只看（〔設定〕〔記這位帶訓者的評分〕不出現）；系統頁點進來沒訂閱也能看，〔設定〕〔記…〕才擋。

/// 打開帶訓者頁（sheet(item:)；每次新的 id）
struct CompetencyMentorRequest: Identifiable {
    let id = UUID()
    let subordinateId: UUID
}

struct CompetencyMentorView: View {
    let subordinateId: UUID

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    /// 〔設定〕／〔換人〕打開的小表單（sheet(item:)）
    @State private var editRequest: CompMentorEditRequest?
    /// 〔記這位帶訓者的評分〕＝既有的評分畫面、帶訓者模式（sheet(item:)）
    @State private var ratingRequest: CompetencyRatingRequest?
    @State private var showPremiumAlert = false
    /// 剛存好「已儲存 11/2 陳怡君（帶訓者）的評分（3 格）」（3 秒後自己消失）
    @State private var toastText: String?
    @State private var toastTask: Task<Void, Never>?

    /// 每一組一列（CompetencyMath.mentorRows；body 只叫一次）
    private var rows: [CompetencyMentorRow] {
        CompetencyMath.mentorRows(setup: lifeStore.competencySetup,
                                  subordinateId: subordinateId,
                                  roster: lifeStore.competencyMentorRoster,
                                  today: CompetencyMath.dayKey(Date()))
    }

    private var isArchived: Bool { OrgMoveIndex.isArchived(subordinateId) }

    /// 這台能改（唯讀、已轉出只看）
    private var canEdit: Bool { !lifeStore.competencyReadOnly && !OrgMoveIndex.isArchived(subordinateId) }

    var body: some View {
        let list: [CompetencyMentorRow] = rows
        let editable: Bool = canEdit
        return NavigationStack {
            List {
                CompMentorNoticeSection(archived: isArchived, readOnly: lifeStore.competencyReadOnly, toast: toastText)
                Section {
                    if list.isEmpty {
                        Text("還沒有要學的組")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(list) { r in
                        CompMentorRowView(row: r, canEdit: editable, onEdit: startEdit, onRate: startRate)
                    }
                } footer: {
                    Text("帶訓者評＝你把帶訓者說的分數記下來，不算進目前分數、熱力表、匯出。一組一位；換人時以前記的照留。")
                }
            }
            .navigationTitle("帶訓者")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .sheet(item: $editRequest) { req in
            CompMentorEditSheet(request: req, subordinateId: subordinateId,
                                candidates: lifeStore.competencyMentorCandidates(for: subordinateId))
                .appStores()
        }
        .sheet(item: $ratingRequest) { r in
            CompetencyRatingSheet(request: r, onSaved: { t in showToast(t) })
                .appStores()
        }
        .premiumLockAlert(isPresented: $showPremiumAlert)
        .onDisappear { toastTask?.cancel() }
    }

    // MARK: 動作（看不擋、動手才擋）

    /// 〔設定〕／〔換人〕（擋訂閱）
    private func startEdit(_ row: CompetencyMentorRow) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        editRequest = CompMentorEditRequest(groupId: row.id, title: row.title, current: row.mentor)
    }

    /// 〔記這位帶訓者的評分〕（擋訂閱）：既有的評分畫面、帶訓者模式
    private func startRate(_ r: CompetencyRaterChoice) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        ratingRequest = CompetencyRatingRequest(subordinateId: subordinateId, rater: r)
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { toastText = text }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { toastText = nil }
        }
    }
}

// MARK: - 頂上一節（已轉出／這台比較舊／剛存好）

private struct CompMentorNoticeSection: View {
    let archived: Bool
    let readOnly: Bool
    let toast: String?

    var body: some View {
        if archived || readOnly || toast != nil {
            Section {
                if archived {
                    CompMentorNoticeRow(icon: "archivebox.fill", text: "已轉出，帶訓者留著可以看", color: .secondary)
                }
                if readOnly {
                    CompMentorNoticeRow(icon: "exclamationmark.triangle.fill",
                                        text: "這台的 App 比較舊，請在已更新的那台改", color: .orange)
                }
                if let t = toast {
                    CompMentorNoticeRow(icon: "checkmark.circle.fill", text: t, color: .green)
                        .transition(.opacity)
                }
            }
        }
    }
}

/// 一行小字（照〔職能〕分頁 CompTabNoticeRow 的樣子）
private struct CompMentorNoticeRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 一列（一組）

private struct CompMentorRowView: View {
    let row: CompetencyMentorRow
    let canEdit: Bool
    let onEdit: (CompetencyMentorRow) -> Void
    let onRate: (CompetencyRaterChoice) -> Void

    private var tint: Color { CompetencyPalette.tint(isTrait: row.isTrait) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                CompMentorRowTexts(row: row)
                Spacer(minLength: 8)
                editButton
            }
            rateButton
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    /// 右邊〔設定〕（有帶訓者寫〔換人〕）
    @ViewBuilder
    private var editButton: some View {
        if canEdit {
            Button {
                onEdit(row)
            } label: {
                Text(row.mentor == nil ? "設定" : "換人")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(row.title + (row.mentor == nil ? "，設定帶訓者" : "，換帶訓者"))
        }
    }

    /// 下面〔記這位帶訓者的評分〕（能改、而且這一組有帶訓者才有）
    @ViewBuilder
    private var rateButton: some View {
        if canEdit, let r = row.rater {
            Button {
                onRate(r)
            } label: {
                Label("記這位帶訓者的評分", systemImage: "square.and.pencil")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("記" + r.name + "的評分")
        }
    }
}

/// 「Gas System」＋下一行「陳怡君・從 5/4」「（已不在名冊）」／「還沒有」
private struct CompMentorRowTexts: View {
    let row: CompetencyMentorRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
                .font(.subheadline.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(row.mentorText)
                    .font(.footnote)
                    .foregroundStyle(row.mentor == nil ? Color.secondary : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let n = row.missingNote {
                    Text(n)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 〔設定〕小表單

/// 打開〔設定〕（打開那一刻的帶訓者當起點）
private struct CompMentorEditRequest: Identifiable {
    let id = UUID()
    let groupId: UUID
    /// 「Gas System」「人格特質」
    let title: String
    let current: CompetencyMentor?
}

private struct CompMentorEditSheet: View {
    let request: CompMentorEditRequest
    let subordinateId: UUID
    /// 打開那一刻的名冊（在職、不是這位自己；lifeStore.competencyMentorCandidates(for:)）
    let candidates: [CompetencyTeamPerson]

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    @State private var pickId: UUID?
    @State private var outside: Bool
    @State private var nameText: String
    @State private var date: Date
    @State private var showClear = false

    init(request: CompMentorEditRequest, subordinateId: UUID, candidates: [CompetencyTeamPerson]) {
        self.request = request
        self.subordinateId = subordinateId
        self.candidates = candidates
        let cur: CompetencyMentor? = request.current
        var pick: UUID? = nil
        var out: Bool = false
        var name: String = ""
        if let c = cur {
            if let mid = c.mentorId {
                if candidates.contains(where: { $0.id == mid }) { pick = mid }
            } else {
                out = true
                let n: String = (c.mentorName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                name = String(n.prefix(CompetencyMath.mentorNameMax))
            }
        }
        var start: Date = Date()
        let today: String = CompetencyMath.dayKey(Date())
        if let k = cur?.startKey, k < today, let d = CompetencyMath.noonDate(k) {
            start = d
        }
        _pickId = State(initialValue: pick)
        _outside = State(initialValue: out)
        _nameText = State(initialValue: name)
        _date = State(initialValue: start)
    }

    /// 現在的帶訓者有部屬 id、但已經不在名冊：「現在：陳怡君（已不在名冊）」
    private var missingLine: String? {
        guard let c = request.current, let mid = c.mentorId else { return nil }
        guard !candidates.contains(where: { $0.id == mid }) else { return nil }
        return "現在：" + CompetencyMath.mentorName(c, roster: lifeStore.competencyMentorRoster) + CompetencyMath.mentorMissingNote
    }

    /// 「拿掉Gas System的帶訓者？」
    private var clearTitle: String {
        "拿掉" + request.title + "的帶訓者？"
    }

    private var canSave: Bool {
        pickId != nil || (outside && CompetencyMath.cleanMentorName(nameText) != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                pickSection
                if outside {
                    nameSection
                }
                dateSection
                if request.current != nil {
                    clearSection
                }
            }
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { save() }
                        .disabled(!canSave)
                }
            }
            .alert(clearTitle, isPresented: $showClear) {
                Button("拿掉", role: .destructive) { clear() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("以前記的帶訓者評分照留。")
            }
        }
        .presentationDetents([.large])
    }

    /// 「從名冊挑」：一列一位＋最後〔名冊外的人〕
    private var pickSection: some View {
        Section {
            if let t = missingLine {
                Text(t)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if candidates.isEmpty {
                Text("名冊裡沒有別的在職同仁")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(candidates) { p in
                CompMentorPickRow(title: p.name, isOn: !outside && pickId == p.id) {
                    pickId = p.id
                    outside = false
                }
            }
            CompMentorPickRow(title: "名冊外的人", isOn: outside) {
                outside = true
                pickId = nil
            }
        } header: {
            Text("從名冊挑")
        }
    }

    /// 名冊外的人：自己打名字（最多 10 字）
    private var nameSection: some View {
        Section {
            TextField("名字（最多 10 字）", text: $nameText)
                .onChange(of: nameText) { _, v in
                    if v.count > CompetencyMath.mentorNameMax {
                        nameText = String(v.prefix(CompetencyMath.mentorNameMax))
                    }
                }
        } header: {
            Text("名冊外的人")
        }
    }

    /// 開始帶的日子（不能選明天以後）
    private var dateSection: some View {
        Section {
            DatePicker("開始", selection: $date, in: ...Date(), displayedComponents: .date)
        } header: {
            Text("開始帶的日子")
        }
    }

    /// 〔拿掉帶訓者〕（有帶訓者才有；先問一次）
    private var clearSection: some View {
        Section {
            Button(role: .destructive) {
                showClear = true
            } label: {
                Text("拿掉帶訓者")
            }
        }
    }

    /// 〔完成〕：先 dismiss，下一個 runloop 才寫（一次 batched；名字空、不在名冊、是自己 LifeStore 會不寫）
    private func save() {
        guard canSave else { return }
        let store: LifeStore = lifeStore
        let sid: UUID = subordinateId
        let gid: UUID = request.groupId
        let mid: UUID? = outside ? nil : pickId
        let n: String? = outside ? nameText : nil
        let key: String = CompetencyMath.dayKey(date)
        dismiss()
        DispatchQueue.main.async {
            _ = store.setCompetencyMentor(sid, groupId: gid, mentorId: mid, name: n, startKey: key)
        }
    }

    /// 〔拿掉〕：先 dismiss，下一個 runloop 才寫（以前記的帶訓者評照留）
    private func clear() {
        let store: LifeStore = lifeStore
        let sid: UUID = subordinateId
        let gid: UUID = request.groupId
        dismiss()
        DispatchQueue.main.async {
            store.clearCompetencyMentor(sid, groupId: gid)
        }
    }
}

/// 名冊一列：名字＋選中打勾
private struct CompMentorPickRow: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 8)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(CompetencyPalette.trait)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
