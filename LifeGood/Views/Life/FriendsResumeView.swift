import SwiftUI

// [v25.636] 朋友履歷：家庭第 5 顆「朋友履歷」的列表（peoplehub2 G1；judge_peoplehub §C6、§C10-b）
//
// - 最上面「常一起吃、還沒存的人」建議卡（PersonLedger.unknownCompanions；沒有候選人就不出現）：每位〔存成朋友〕；
//   左滑「不要再提」只記這台（FriendSuggestMemory，UserDefaults.standard）。
// - 分段：朋友、同事、客戶、其他（FriendBook.sections；舊資料分在「家人」的放「其他」、列上小字「建議放到家人履歷」）。
// - 每列：名字、生日、「一起吃飯 6 頓・最近 11/18」、有欠款時灰色小字「還欠 NT$375」（.task 一次算好字典）。
// - 右上〔＋〕新增朋友；點一列 sheet(item:) 開 FriendDetailView（FriendDetailView.swift）＋.appStores()。
// - 看不擋、動手才擋（照家庭其他履歷：新增、存成朋友要訂閱）。沒有分享鈕。寫 store 一律在 action 的下一個 runloop。
// - 每一列是 fileprivate struct（純值＋closure）、清單包 AnyView（25.618 閃退教訓）。

// MARK: - .task(id:) 的 key

/// 記帳／分帳一變（modifyID）、朋友名字、本人名字、名單人數變了才重算（列上的數字、建議卡）
fileprivate struct FriendsListKey: Equatable {
    let modifyID: UUID
    let names: [String]
    let meName: String
    let people: Int
}

// MARK: - 朋友列表

struct FriendsResumeView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var subscription: SubscriptionManager

    @State private var query = ""
    @State private var viewing: FriendDetailTarget? = nil
    @State private var editor: FriendEditorTarget? = nil
    /// 朋友 key → 一起吃飯、還欠（.task 一次算好）
    @State private var stats: [String: PersonLedgerSummary] = [:]
    /// 常一起吃、還沒存的人
    @State private var suggestions: [PersonLedgerCompanion] = []
    @State private var showPremiumAlert = false
    @State private var toast: String? = nil

    init() {}

    var body: some View {
        NavigationStack {
            AnyView(friendList)
                .searchable(text: $query, prompt: FriendText.searchPrompt)
                .navigationTitle(FriendText.title)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { addTapped() } label: { Image(systemName: "plus") }
                            .accessibilityLabel(FriendText.newTitle)
                    }
                }
        }
        .overlay(alignment: .bottom) { FriendsToast(text: toast) }
        .task(id: listKey) { reload() }
        .task(id: toast) {
            guard toast != nil else { return }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if Task.isCancelled { return }
            toast = nil
        }
        .premiumLockAlert(isPresented: $showPremiumAlert)
        .sheet(item: $viewing) { t in
            FriendDetailView(relationshipId: t.id)
                .appStores()
        }
        .sheet(item: $editor) { t in
            FriendEditor(target: t)
                .appStores()
        }
    }

    // MARK: 清單（整段包 AnyView）

    private var friendList: some View {
        let list: [FriendSection] = sections
        return List {
            if showsSuggestions {
                suggestSection
            }
            if list.isEmpty {
                Section {
                    FriendsEmptyRow(text: emptyText)
                }
            } else {
                ForEach(list) { s in
                    friendSection(s)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// 建議卡只在沒在搜尋、而且有候選人時出現
    private var showsSuggestions: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !suggestions.isEmpty
    }

    private var sections: [FriendSection] {
        FriendBook.sections(lifeStore.relationships, query: query)
    }

    private var emptyText: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? FriendText.empty : "找不到符合「" + trimmed + "」的朋友"
    }

    private var suggestSection: some View {
        Section {
            ForEach(suggestions) { c in
                suggestRow(c)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(FriendText.dontSuggest) { dismissSuggestion(c) }
                            .tint(.gray)
                    }
            }
        } header: {
            Text(FriendText.suggestTitle)
        } footer: {
            Text(FriendText.suggestNote)
        }
    }

    private func suggestRow(_ c: PersonLedgerCompanion) -> FriendSuggestRow {
        FriendSuggestRow(name: c.name, detail: FriendText.suggestRow(c, calendar: .current),
                         onSave: { saveSuggestion(c) })
    }

    private func friendSection(_ s: FriendSection) -> some View {
        Section(s.title) {
            ForEach(s.friends) { r in
                friendRow(r)
            }
        }
    }

    /// ForEach 用 Relationship.id（同名不會撞）
    private func friendRow(_ r: Relationship) -> FriendRow {
        let s: PersonLedgerSummary? = stats[PersonLedger.key(r.name)]
        let id = r.id
        return FriendRow(name: r.name,
                         birthday: FriendText.birthdayLine(r.birthday, calendar: .current),
                         stats: FriendText.rowStats(s, calendar: .current),
                         owed: FriendText.rowOwed(s),
                         familyNote: r.group == .family ? FriendText.suggestFamilyNote : nil,
                         onOpen: { viewing = FriendDetailTarget(id: id) })
    }

    private var listKey: FriendsListKey {
        let people = lifeStore.familyMembers.count + lifeStore.subordinates.count + lifeStore.orgPeople.count
            + lifeStore.businessCards.count
        return FriendsListKey(modifyID: store.modifyID,
                              names: lifeStore.relationships.map { r in r.name },
                              meName: lifeStore.profile.chineseName + "|" + lifeStore.profile.englishName,
                              people: people)
    }

    // MARK: 只讀：記帳＋分帳＋名單 → @State

    private func reload() {
        let me = PersonLedger.meKeys(lifeStore.profile)
        var keys = Set<String>()
        for r in lifeStore.relationships {
            let k = PersonLedger.key(r.name)
            if !k.isEmpty && !me.contains(k) { keys.insert(k) }
        }
        let idx = ExpenseSplitStore.shared.index
        stats = PersonLedger.summaries(expenses: store.expenses, index: idx, keys: keys)
        suggestions = PersonLedger.unknownCompanions(expenses: store.expenses, index: idx,
                                                     knownKeys: PersonLedger.knownKeys(life: lifeStore),
                                                     meKeys: me, dismissed: FriendSuggestMemory.load())
    }

    // MARK: 動作（看不擋、動手才擋；寫 store 一律下一個 runloop、經 FriendActions）

    private func addTapped() {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        editor = FriendEditorTarget.adding()
    }

    private func saveSuggestion(_ c: PersonLedgerCompanion) {
        guard subscription.isPremium else { showPremiumAlert = true; return }
        suggestions.removeAll { x in x.key == c.key }
        let life = lifeStore
        let name = c.name
        DispatchQueue.main.async {
            let saved = FriendActions.save(names: [name], life: life)
            if !saved.isEmpty { toast = FriendText.savedToast(saved) }
        }
    }

    /// 「不要再提」只是這台的偏好（不寫 LifeStore），不擋訂閱
    private func dismissSuggestion(_ c: PersonLedgerCompanion) {
        FriendSuggestMemory.dismiss(c.key)
        suggestions.removeAll { x in x.key == c.key }
    }
}

// MARK: - 列（純值＋closure）

/// 建議卡一列：名字、「一起 3 次・最近 11/18」、〔存成朋友〕
fileprivate struct FriendSuggestRow: View {
    let name: String
    let detail: String
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(FriendText.saveAsFriend, action: onSave)
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
        }
    }
}

/// 朋友一列：名字、生日、一起吃飯、還欠（灰色小字）、家人組的小字；點了開朋友頁
fileprivate struct FriendRow: View {
    let name: String
    let birthday: String?
    let stats: String?
    let owed: String?
    let familyNote: String?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                FriendRowLines(name: name, birthday: birthday, stats: stats, owed: owed, familyNote: familyNote)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 朋友一列左邊那幾行（沒有的就不放）
fileprivate struct FriendRowLines: View {
    let name: String
    let birthday: String?
    let stats: String?
    let owed: String?
    let familyNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.body)
                .foregroundStyle(Color.primary)
            if let b = birthday {
                Text(b).font(.caption).foregroundStyle(.secondary)
            }
            if let s = stats {
                Text(s).font(.caption).foregroundStyle(.secondary)
            }
            if let o = owed {
                Text(o).font(.caption).foregroundStyle(.secondary)
            }
            if let f = familyNote {
                Text(f).font(.caption2).foregroundStyle(.orange)
            }
        }
    }
}

/// 空狀態（沒有朋友／搜尋找不到）
fileprivate struct FriendsEmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 存好了的提示「阿傑 存成朋友了」（2.5 秒自己消失；照 OwedToast）
fileprivate struct FriendsToast: View {
    let text: String?

    @ViewBuilder
    var body: some View {
        if let t = text {
            Text(t)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.horizontal, 16).padding(.bottom, 16)
        }
    }
}
