import SwiftUI

// [v25.636] 朋友履歷頁、朋友編輯器（peoplehub2 G2；judge_peoplehub §C7、§C8、§C12）
//
// - FriendDetailView(relationshipId:)：照 PetDetailView 一張卡一段 AnyView。頭卡（名字、分組、生日、紀念日、電話）→
//   往來（PersonLedgerSlot.swift）→ 送過的禮（PersonLedger.gifts；沒有就不出現）→ 互動紀錄 → 備註 → 同名名片。
//   用 id 找不到這位＝關頁（不強制解包）。沒有分享鈕。
// - FriendEditor(target:)：新增（預設朋友）／編輯；名字過 FriendBook.nameState；分組不提供「家人」（原本就是家人的才多列）；
//   改名提醒寫出會對不上幾頓；存檔先 dismiss、下一個 runloop 才 FriendActions.upsert；刪除要確認、只刪朋友資料。
// - 所有 sheet 一律 sheet(item:)＋.appStores()；看不擋、動手才擋（編輯、記一筆、刪除要訂閱）。

// MARK: - 朋友頁

/// .task(id:) 的 key：記帳一變（modifyID）、名字改了才重算送過的禮
fileprivate struct FriendGiftsKey: Equatable {
    let modifyID: UUID
    let name: String
}

struct FriendDetailView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let relationshipId: UUID

    @State private var editor: FriendEditorTarget? = nil
    /// 〔＋ 記一筆〕（id＝這位朋友的 id）
    @State private var adding: FriendDetailTarget? = nil
    /// 同名名片（id＝名片 id）
    @State private var openCard: FriendDetailTarget? = nil
    @State private var showPremiumAlert = false
    @State private var gifts: [PersonLedgerGift] = []

    /// 明寫：有 private @State，合成的 init 會是 private（FriendsResumeView、名片頁跨檔案要建）
    init(relationshipId: UUID) {
        self.relationshipId = relationshipId
    }

    private var friend: Relationship? {
        lifeStore.relationships.first { r in r.id == relationshipId }
    }

    private var giftsKey: FriendGiftsKey {
        FriendGiftsKey(modifyID: store.modifyID, name: friend?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Group {
                if let r = friend {
                    ScrollView { AnyView(page(r)).padding(.vertical) }
                } else {
                    Text(FriendText.notFound).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).onAppear { dismiss() }     // 被刪、或別台同步拿掉 → 關頁
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(friend?.name ?? FriendText.detailTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("編輯") { tapEdit() }.bold() }
            }
            .task(id: giftsKey) { reloadGifts() }
            .modifier(FriendDetailSheets(editor: $editor, adding: $adding, openCard: $openCard,
                                         showPremiumAlert: $showPremiumAlert, onEditorClosed: { closeIfGone() }))
        }
    }

    // MARK: 一張卡一段

    private func page(_ r: Relationship) -> some View {
        VStack(spacing: 16) {
            AnyView(PersonLedgerSlot(subject: PersonLedgerSubject.friend(r), above: AnyView(FriendHeadCard(r: r, onCall: { url in openURL(url) }).padding(.horizontal))))
            if !gifts.isEmpty {
                AnyView(FriendGiftsCard(gifts: gifts).padding(.horizontal))
            }
            AnyView(interactionsCard(r))
            if !noteText(r).isEmpty {
                AnyView(FriendNoteCard(text: noteText(r)).padding(.horizontal))
            }
            if !sameNameCards(r).isEmpty {
                AnyView(FriendCardsCard(cards: sameNameCards(r), onOpen: { id in openCard = FriendDetailTarget(id: id) })
                    .padding(.horizontal))
            }
        }
    }

    private func interactionsCard(_ r: Relationship) -> some View {
        FriendInteractionsCard(items: r.interactions.sorted(by: { a, b in a.date > b.date }),
                               onAdd: { tapAddInteraction() },
                               onDelete: { iid in deleteInteraction(iid, friendId: r.id) })
            .padding(.horizontal)
    }

    private func noteText(_ r: Relationship) -> String {
        r.note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 同名名片（v2 只靠名字；點了開名片詳情）
    private func sameNameCards(_ r: Relationship) -> [BusinessCard] {
        PersonLedger.cards(named: r.name, in: lifeStore.businessCards)
    }

    // MARK: 只讀

    private func reloadGifts() {
        gifts = friend.map { r in
            PersonLedger.gifts(expenses: store.expenses, keys: PersonLedger.names(primary: r.name, extra: []))
        } ?? []
    }

    // MARK: 動手（看不擋、動手才擋）

    private func gated(_ action: () -> Void) {
        if subscription.isPremium { action() } else { showPremiumAlert = true }
    }

    private func tapEdit() {
        gated {
            if let r = friend { editor = FriendEditorTarget.editing(r) }
        }
    }

    /// [v25.636] 編輯器收起來後：這位已經被刪了就關頁（收起動畫中那次 dismiss 可能被忽略）
    private func closeIfGone() {
        if friend == nil { dismiss() }
    }

    private func tapAddInteraction() {
        gated { adding = FriendDetailTarget(id: relationshipId) }
    }

    /// 從 Menu 按的：下一個 runloop 才寫（Menu 收起來那一輪不動 store）
    private func deleteInteraction(_ iid: UUID, friendId fid: UUID) {
        gated {
            let life = lifeStore
            DispatchQueue.main.async { FriendActions.deleteInteraction(id: iid, friendId: fid, life: life) }
        }
    }
}

/// 朋友頁的 sheet(item:)＋訂閱提示（拆出來，FriendDetailView body 才不會疊太深）
fileprivate struct FriendDetailSheets: ViewModifier {
    @Binding var editor: FriendEditorTarget?
    @Binding var adding: FriendDetailTarget?
    @Binding var openCard: FriendDetailTarget?
    @Binding var showPremiumAlert: Bool
    let onEditorClosed: () -> Void

    func body(content: Content) -> some View {
        content
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .sheet(item: $editor, onDismiss: onEditorClosed) { t in
                FriendEditor(target: t)
                    .appStores()
            }
            .sheet(item: $adding) { t in
                FriendInteractionEditor(friendId: t.id)
                    .appStores()
            }
            .sheet(item: $openCard) { t in
                BusinessCardDetailView(cardId: t.id)
                    .appStores()
            }
    }
}

// MARK: - 卡（純值＋closure；外框照 PersonLedgerCard）

/// 卡的外框：systemBackground、圓角 14、0.75 細框、淡陰影（跟往來卡一樣）
fileprivate struct FriendCardShell: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
    }
}

/// 卡的標題列：左邊標題、右邊一行灰字（可以沒有）
fileprivate struct FriendCardTitle: View {
    let title: String
    let trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer(minLength: 8)
            if let t = trailing {
                Text(t)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

fileprivate struct FriendHeadCard: View {
    let name: String
    let group: RelationshipGroup
    let birthday: String?
    let anniversary: String?
    /// 去前後空白；空＝不顯示
    let phone: String
    /// 撥得出去才有（FriendText.telURL）；沒有＝電話只是字
    let telURL: URL?
    let onCall: (URL) -> Void

    /// 從這一位的資料算好每一行（純值；撥號交給呼叫端的 openURL）
    init(r: Relationship, onCall: @escaping (URL) -> Void) {
        self.name = r.name
        self.group = r.group
        self.birthday = FriendText.dateLine("生日", r.birthday, calendar: .current)
        self.anniversary = FriendText.dateLine("紀念日", r.anniversary, calendar: .current)
        self.phone = r.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        self.telURL = FriendText.telURL(r.phone)
        self.onCall = onCall
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            FriendGroupChip(group: group)
            if group == .family {
                Text(FriendText.suggestFamilyNote)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let b = birthday {
                FriendInfoLine(icon: "gift", text: b)
            }
            if let a = anniversary {
                FriendInfoLine(icon: "heart", text: a)
            }
            if !phone.isEmpty {
                FriendPhoneLine(phone: phone, url: telURL, onCall: onCall)
            }
        }
        .modifier(FriendCardShell())
    }
}

/// 分組膠囊（「朋友」＋圖示）
fileprivate struct FriendGroupChip: View {
    let group: RelationshipGroup

    var body: some View {
        Label(group.rawValue, systemImage: group.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.green.opacity(0.14)))
    }
}

/// 頭卡一行（生日、紀念日）
fileprivate struct FriendInfoLine: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

/// 電話：撥得出去就是可按的（點了撥號），不然只是字
fileprivate struct FriendPhoneLine: View {
    let phone: String
    let url: URL?
    let onCall: (URL) -> Void

    var body: some View {
        if let u = url {
            Button { onCall(u) } label: {
                Label(phone, systemImage: "phone.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
        } else {
            Label(phone, systemImage: "phone")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// 送過的禮（社交、收受人有這位；整筆；多位收受人寫「多人合送」）
fileprivate struct FriendGiftsCard: View {
    let gifts: [PersonLedgerGift]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FriendCardTitle(title: FriendText.giftsTitle, trailing: FriendText.giftsHeader(gifts))
            ForEach(gifts) { g in
                FriendGiftRow(label: FriendText.giftLabel(g, calendar: .current),
                              amount: ExpenseSplitText.ntd(g.amount), shared: g.shared)
            }
        }
        .modifier(FriendCardShell())
    }
}

fileprivate struct FriendGiftRow: View {
    let label: String
    let amount: String
    let shared: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                if shared {
                    Text(FriendText.giftShared)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(amount)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }
}

/// 互動紀錄（新到舊；呼叫端排好）：右上〔＋ 記一筆〕、每筆右邊「⋯」刪除
fileprivate struct FriendInteractionsCard: View {
    let items: [InteractionRecord]
    let onAdd: () -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(FriendText.interactionsTitle)
                    .font(.headline)
                Spacer(minLength: 8)
                Button(action: onAdd) {
                    Label(FriendText.addInteraction, systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
            if items.isEmpty {
                Text(FriendText.interactionEmpty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { rec in
                    FriendInteractionRow(date: ExpenseSplitText.ymd(rec.date, .current), note: rec.note,
                                         onDelete: { onDelete(rec.id) })
                }
            }
        }
        .modifier(FriendCardShell())
    }
}

fileprivate struct FriendInteractionRow: View {
    let date: String
    let note: String
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(note)
                    .font(.subheadline)
            }
            Spacer(minLength: 8)
            Menu {
                Button("刪除", role: .destructive) { onDelete() }
            } label: {
                Image(systemName: "ellipsis")
                    .padding(6)
            }
            .accessibilityLabel("更多")
        }
    }
}

fileprivate struct FriendNoteCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FriendCardTitle(title: FriendText.noteTitle, trailing: nil)
            Text(text)
                .font(.subheadline)
        }
        .modifier(FriendCardShell())
    }
}

/// 同名名片：每張一列，點了開名片詳情
fileprivate struct FriendCardsCard: View {
    let cards: [BusinessCard]
    let onOpen: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FriendCardTitle(title: FriendText.cardsTitle, trailing: nil)
            ForEach(cards) { c in
                Button { onOpen(c.id) } label: {
                    FriendCardLine(text: FriendText.cardRow(c))
                }
                .buttonStyle(.plain)
            }
        }
        .modifier(FriendCardShell())
    }
}

fileprivate struct FriendCardLine: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 朋友編輯器（新增預設朋友；編輯＝打開那一刻的那一筆整筆換掉）

struct FriendEditor: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let target: FriendEditorTarget

    @State private var draft: FriendDraft
    @State private var nameState = FriendNameState(canSave: false, message: nil)
    @State private var renameText: String? = nil
    @State private var askDelete = false
    @State private var newNote = ""
    @State private var newDate = Date()

    init(target: FriendEditorTarget) {
        self.target = target
        _draft = State(initialValue: FriendDraft(target.base, now: Date()))
    }

    var body: some View {
        NavigationStack {
            Form {
                AnyView(nameSection)
                AnyView(groupSection)
                FriendEditorDatesSection(draft: $draft)
                AnyView(contactSection)
                FriendEditorInteractionsSection(items: $draft.interactions, newDate: $newDate, newNote: $newNote)
                if target.base != nil {
                    AnyView(deleteSection)
                }
            }
            .navigationTitle(target.base == nil ? FriendText.newTitle : FriendText.editTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { save() }.bold().disabled(!nameState.canSave)
                }
            }
            .task(id: draft.name) { await refreshName() }
            .confirmationDialog(FriendText.deleteButton, isPresented: $askDelete, titleVisibility: .visible) {
                Button("刪除", role: .destructive) { deleteNow() }
                Button("取消", role: .cancel) {}
            } message: {
                Text(FriendText.deleteConfirm)
            }
        }
    }

    // MARK: 段

    private var nameSection: some View {
        Section {
            TextField("名字", text: $draft.name)
                .autocorrectionDisabled()
            if let m = nameState.message {
                Text(m)
                    .font(.caption)
                    .foregroundStyle(nameMessageColor)
            }
            if let t = renameText {
                Text(t)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// 擋住存檔的原因寫紅字；還沒打字、或同名提醒（可以存）寫灰字
    private var nameMessageColor: Color {
        if nameState.canSave || draft.name.isEmpty { return Color.secondary }
        return Color.red
    }

    private var groupSection: some View {
        Section {
            Picker("分組", selection: $draft.group) {
                ForEach(FriendBook.groupChoices(current: target.base?.group), id: \.self) { g in
                    Label(g.rawValue, systemImage: g.icon).tag(g)
                }
            }
            if draft.group == .family {
                Text(FriendText.familyGroupWarn)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var contactSection: some View {
        Section {
            TextField("電話", text: $draft.phone)
                .keyboardType(.phonePad)
            TextField("備註", text: $draft.note, axis: .vertical)
                .lineLimit(2...6)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(FriendText.deleteButton, role: .destructive) { askDelete = true }
        }
    }

    // MARK: 只讀（只指派 @State）

    /// 名字一變：馬上算能不能存；改名提醒要掃記帳，等 0.25 秒沒再打字才算
    private func refreshName() async {
        nameState = FriendBook.nameState(draft.name, editingId: target.base?.id, life: lifeStore)
        guard let b = target.base else {
            renameText = nil
            return
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
        if Task.isCancelled { return }
        let impact = PersonLedger.renameImpact(oldName: b.name, newName: draft.name, expenses: store.expenses,
                                               index: ExpenseSplitStore.shared.index)
        renameText = FriendText.renameWarning(oldName: b.name, impact: impact)
    }

    // MARK: 寫（先 dismiss，下一個 runloop 才寫）

    private func save() {
        guard subscription.isPremium else { return }
        guard FriendBook.nameState(draft.name, editingId: target.base?.id, life: lifeStore).canSave else { return }
        let saved = draft.relationship(id: target.base?.id ?? UUID())
        let life = lifeStore
        dismiss()
        DispatchQueue.main.async { FriendActions.upsert(saved, life: life) }
    }

    /// 只刪朋友資料（朋友頁接著找不到這位 → 自己關頁）
    private func deleteNow() {
        guard subscription.isPremium else { return }
        guard let b = target.base else { return }
        let id = b.id
        let life = lifeStore
        dismiss()
        DispatchQueue.main.async { FriendActions.delete(id: id, life: life) }
    }
}

/// 生日、紀念日：各一個開關，開了才有日期（關著存 nil）
fileprivate struct FriendEditorDatesSection: View {
    @Binding var draft: FriendDraft

    var body: some View {
        Section {
            Toggle("生日", isOn: $draft.hasBirthday)
            if draft.hasBirthday {
                DatePicker("生日日期", selection: $draft.birthday, displayedComponents: .date)
            }
            Toggle("紀念日", isOn: $draft.hasAnniversary)
            if draft.hasAnniversary {
                DatePicker("紀念日日期", selection: $draft.anniversary, displayedComponents: .date)
            }
        }
    }
}

/// 編輯器裡的互動紀錄：照存的順序列出、往左滑刪；下面加一筆（去前後空白不空才加）
fileprivate struct FriendEditorInteractionsSection: View {
    @Binding var items: [InteractionRecord]
    @Binding var newDate: Date
    @Binding var newNote: String

    var body: some View {
        Section {
            ForEach(items) { rec in
                FriendEditorInteractionLine(date: ExpenseSplitText.ymd(rec.date, .current), note: rec.note)
            }
            .onDelete { offsets in items.remove(atOffsets: offsets) }
            DatePicker("日期", selection: $newDate, displayedComponents: .date)
            TextField("新的一筆互動紀錄", text: $newNote, axis: .vertical)
            Button("加入") { addNew() }
                .disabled(trimmedNote.isEmpty)
        } header: {
            Text(FriendText.interactionsTitle)
        } footer: {
            Text("往左滑可以刪掉一筆。")
        }
    }

    private var trimmedNote: String {
        newNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addNew() {
        let t = trimmedNote
        guard !t.isEmpty else { return }
        items.append(InteractionRecord(date: newDate, note: t))
        newNote = ""
    }
}

fileprivate struct FriendEditorInteractionLine: View {
    let date: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(date)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(note)
                .font(.subheadline)
        }
    }
}

// MARK: - 朋友頁〔＋ 記一筆〕

struct FriendInteractionEditor: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let friendId: UUID

    @State private var date = Date()
    @State private var note = ""

    init(friendId: UUID) {
        self.friendId = friendId
    }

    private var trimmed: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("日期", selection: $date, displayedComponents: .date)
                TextField("內容", text: $note, axis: .vertical)
                    .lineLimit(3...8)
            }
            .navigationTitle(FriendText.addInteraction)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("記下來") { saveNow() }.bold().disabled(trimmed.isEmpty)
                }
            }
        }
    }

    /// 先 dismiss，下一個 runloop 才寫
    private func saveNow() {
        guard subscription.isPremium else { return }
        let t = trimmed
        guard !t.isEmpty else { return }
        let rec = InteractionRecord(date: date, note: t)
        let fid = friendId
        let life = lifeStore
        dismiss()
        DispatchQueue.main.async { FriendActions.addInteraction(rec, friendId: fid, life: life) }
    }
}
