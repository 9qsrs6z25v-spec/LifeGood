import SwiftUI

// [v25.634] PeoplePickerSheet：記帳表單的「同行人員」和社交禮金的「收受人」共用的選人清單
// （judge_companions §C6；build/companions1/brief.md §2 G1 1–4）。
// - 名單由 AddExpenseView 組好傳進來（家人、人際關係、部屬・課別、公司・部門、名片；同行人員前面多「最近一起吃過」）。
// - 搜尋（組名、姓名、小字）；搜尋框打的字名單裡沒有 → 最上面〔＋ 加「名字」〕（SplitPeople.addRow 檢查「、」逗號分號、20 字）。
// - 打的名字只放進 selection（存檔照舊串進 diningMember／socialRecipient），不建人際關係、不寫 store、不寫 UserDefaults。
// - 已還錢的人（lockedNames）不能取消：跳提示。
// - 每一列都是 fileprivate struct（純值＋closure）、清單包 AnyView（25.618 記帳表單閃退的教訓：型別不要疊太深）。

/// 哪一個選單（sheet(item:) 的 item）
enum PeoplePickerKind: String, Identifiable {
    case dining, social

    var id: String { rawValue }
}

/// 名單上的一個人：名字（存檔就是存名字）＋一行小字（部門、職稱、公司）
struct PeopleCandidate: Identifiable, Equatable {
    let name: String
    let detail: String

    var id: String { name }

    init(name: String, detail: String) {
        self.name = name
        self.detail = detail
    }
}

/// 名單的一組（組名當 id：同名的組在組名單時已經併成一組）
struct PeopleGroup: Identifiable, Equatable {
    let title: String
    let people: [PeopleCandidate]

    var id: String { title }

    init(title: String, people: [PeopleCandidate]) {
        self.title = title
        self.people = people
    }
}

struct PeoplePickerSheet: View {
    let title: String
    let prompt: String
    /// 標題下面一行小字（同行人員：ExpenseSplitText.pickerSubtitle；收受人 nil）
    let subtitle: String?
    let groups: [PeopleGroup]
    @Binding private var selection: Set<String>
    /// 本人的名字：不是 nil 也不是空的才有「我（…）」那一列（收受人傳 nil）
    let meName: String?
    /// 已還錢的人：不能取消勾選
    let lockedNames: Set<String>
    /// 搜尋框打的字可以直接加（〔＋ 加「名字」〕）
    let allowTyping: Bool
    /// 〔完成〕、「已選 N」膠囊的顏色（同行人員綠、收受人粉）
    let accent: Color

    @State private var query = ""
    @State private var lockedAlert = false
    @Environment(\.dismiss) private var dismiss

    init(title: String, prompt: String, subtitle: String?, groups: [PeopleGroup], selection: Binding<Set<String>>,
         meName: String?, lockedNames: Set<String>, allowTyping: Bool, accent: Color) {
        self.title = title
        self.prompt = prompt
        self.subtitle = subtitle
        self.groups = groups
        _selection = selection
        self.meName = meName
        self.lockedNames = lockedNames
        self.allowTyping = allowTyping
        self.accent = accent
    }

    var body: some View {
        NavigationStack {
            AnyView(pickerList)
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { pickerToolbar }
                .alert(ExpenseSplitText.pickerLocked, isPresented: $lockedAlert) {
                    Button("知道了", role: .cancel) {}
                }
        }
    }

    // MARK: - 算好的值（body 只拿結果）

    /// 搜尋字（去前後空白）
    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searching: Bool { !trimmedQuery.isEmpty }

    /// 本人的名字（去空白；空的＝沒有「我」那一列）
    private var me: String? {
        guard let n = meName?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return nil }
        return n
    }

    /// 搜尋：組名、姓名、小字（照 25.537 收受人的比對法：lowercased、contains）
    private var filteredGroups: [PeopleGroup] {
        let q = trimmedQuery.lowercased()
        guard !q.isEmpty else { return groups }
        return groups.compactMap { g in
            let groupHit = g.title.lowercased().contains(q)
            let people: [PeopleCandidate] = groupHit ? g.people : g.people.filter { c in
                c.name.lowercased().contains(q) || c.detail.lowercased().contains(q)
            }
            return people.isEmpty ? nil : PeopleGroup(title: g.title, people: people)
        }
    }

    /// 搜尋時「我」那一列要不要出現（打的字是本人名字的一部分）
    private var meHit: Bool {
        guard let m = me, searching else { return false }
        return m.lowercased().contains(trimmedQuery.lowercased())
    }

    /// 名單上所有名字＋已選的＋本人（打的字跟這些一模一樣就不出現加入列）
    private var knownNames: Set<String> {
        var out = selection
        for g in groups {
            for c in g.people { out.insert(c.name) }
        }
        if let m = me { out.insert(m) }
        return out
    }

    /// 最上面〔＋ 加「名字」〕那一列（沒在搜尋、不准打字、或名單裡已經有＝nil）
    private var addRow: SplitAddRow? {
        guard allowTyping, searching else { return nil }
        return SplitPeople.addRow(query: query, knownNames: knownNames)
    }

    // MARK: - 動作（只改 selection／query；不寫 store）

    private func toggle(_ name: String) {
        if selection.contains(name) {
            if lockedNames.contains(name) {
                lockedAlert = true
            } else {
                selection.remove(name)
            }
        } else {
            // [v25.635] 名單裡不合格的名字（有「、」逗號分號換行、超過 20 字）不能勾（列本身也灰掉）；不幫使用者改名
            guard PersonLedger.canPick(name) else { return }
            selection.insert(name)
        }
    }

    /// 「不指定」：清空（已還錢的人留著）
    private func clearAll() {
        let kept = selection.intersection(lockedNames)
        if !kept.isEmpty { lockedAlert = true }
        selection = kept
    }

    private func add(_ row: SplitAddRow) {
        guard row.enabled else { return }
        selection.insert(row.name)
        query = ""
    }

    private func isLocked(_ name: String) -> Bool {
        lockedNames.contains(name) && selection.contains(name)
    }

    // MARK: - 清單

    private var pickerList: some View {
        let shown = filteredGroups
        let adding = addRow
        let showMe = searching ? meHit : (me != nil)
        return List {
            if !searching {
                if let s = subtitle, !s.isEmpty {
                    Section {
                        Text(s).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    PeopleNoneRow(picked: selection.isEmpty, onTap: { clearAll() })
                }
                if !selection.isEmpty {
                    Section("已選（\(selection.count)）") {
                        ForEach(selection.sorted(), id: \.self) { name in
                            PeoplePickerRow(title: name, detail: "", picked: true, locked: isLocked(name),
                                            blocked: !PersonLedger.canPick(name), onToggle: { toggle(name) })
                        }
                    }
                }
            }
            if let row = adding {
                Section {
                    PeopleAddRowView(row: row, onAdd: { add(row) })
                }
            }
            if showMe, let m = me {
                Section {
                    PeoplePickerRow(title: ExpenseSplitText.meLabel(m), detail: "", picked: selection.contains(m),
                                    locked: isLocked(m), blocked: !PersonLedger.canPick(m), onToggle: { toggle(m) })
                }
            }
            if searching && shown.isEmpty && !showMe && adding == nil {
                Text("找不到符合「\(trimmedQuery)」的人")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(shown) { g in
                Section(g.title) {
                    ForEach(g.people) { c in
                        PeoplePickerRow(title: c.name, detail: c.detail, picked: selection.contains(c.name),
                                        locked: isLocked(c.name), blocked: !PersonLedger.canPick(c.name),
                                        onToggle: { toggle(c.name) })
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var pickerToolbar: some ToolbarContent {
        // 關閉鈕一律置左（全 App 規則，同 25.537 收受人選單 v4）
        ToolbarItem(placement: .topBarLeading) {
            Button("完成") { dismiss() }
                .bold().foregroundStyle(accent)
        }
        if !selection.isEmpty {
            ToolbarItem(placement: .principal) {
                PeoplePickerTitle(title: title, count: selection.count, accent: accent)
            }
        }
    }
}

// MARK: - 列（純值＋closure）

/// 一個人一列（從 AddExpenseView 的 SocialRecipientRow 搬過來；多一個 locked：已還錢的人旁邊一個鎖）
/// [v25.635] blocked：名字不合格（PersonLedger.canPick 不過）→ 沒勾的灰掉、不能點、下面一行小字；已經勾著的舊資料照舊可以點掉
fileprivate struct PeoplePickerRow: View {
    let title: String
    let detail: String
    let picked: Bool
    let locked: Bool
    let blocked: Bool
    let onToggle: () -> Void

    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(picked ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .foregroundStyle(blocked && !picked ? Color.secondary : Color.primary)
                    if !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if blocked {
                        Text(PersonLedgerText.pickerBlockedNote).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if locked {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(blocked && !picked)
    }
}

/// 「不指定」那一列
fileprivate struct PeopleNoneRow: View {
    let picked: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(picked ? Color.green : Color.secondary)
                Text("不指定")
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 〔＋ 加「張家瑋」〕；名字不行時灰掉、下面一行小字
fileprivate struct PeopleAddRowView: View {
    let row: SplitAddRow
    let onAdd: () -> Void

    var body: some View {
        Button {
            onAdd()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .foregroundStyle(row.enabled ? Color.accentColor : Color.secondary)
                if let m = row.message {
                    Text(m).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!row.enabled)
    }
}

/// 工具列中間：標題＋「已選 N」膠囊（有選人才出現）
fileprivate struct PeoplePickerTitle: View {
    let title: String
    let count: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.headline)
            Text("已選 \(count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 7).padding(.vertical, 2.5)
                .background(accent.opacity(0.12))
                .clipShape(Capsule())
        }
    }
}
