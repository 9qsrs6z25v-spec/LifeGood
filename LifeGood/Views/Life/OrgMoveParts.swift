import SwiftUI

// MARK: - [v25.590 轉組織 v1a-1] 精靈、交接單頁、卡片、部屬總覽共用的小零件（主控寫好、凍結：各組只准呼叫，不改簽名）
//（orgmove/build/v1a-1/brief.md §2-4）

/// 打開交接單頁（`.sheet(item:)` 用；一律 `.sheet(item:)`＋`.appStores()`）
struct OrgMoveSheetRequest: Identifiable, Equatable {
    let moveId: UUID
    var id: UUID { moveId }
}

/// 打開轉組織精靈（部屬卡片「…」〔轉組織〕）
struct OrgMoveWizardRequest: Identifiable, Equatable {
    let personId: UUID
    /// [v25.592 轉組織 v1b] 組織頁改部門時〔用轉組織〕：新部門先帶這個（nil＝照舊不帶）
    var presetDeptId: UUID? = nil
    var id: UUID { personId }
}

/// 挑人那一頁要做什麼（交接清單〔交給…〕〔全部交給 ▾〕〔這組交給 ▾〕、交接單〔改交給…〕、部屬總覽〔分給…〕）
struct OrgMovePickRequest: Identifiable, Equatable {
    let id = UUID()
    /// 標題（「交給誰」「分給誰」「改交給誰」）
    let title: String
    /// 轉組織的那位（清單不列）
    let personId: UUID
    /// 目前選的（打勾）
    let selected: UUID?
    /// 呼叫端自己認得的用途（例：某一列的 id、"all"、某一組的 id）
    let purpose: String
    /// [v25.591 轉組織 v1a-2] 〔到兼任換人…〕：這個兼任的成員排最前面（副標「尾牙籌備成員」）；nil＝一般挑人
    var sideRoleId: UUID? = nil
    /// [v25.591 轉組織 v1a-2] 不列的另外幾位（〔這天交給別人…〕不列原本的接手人）
    var excluding: [UUID] = []
}

/// 挑人：先列「舊部門、同廠區」，再列其他部屬（副標「部門・廠區・職稱」）；這位同仁自己不列；「我」不在清單
///（任務只能放在部屬身上；judge §4.3）。點一下：先關這一頁，**下一個 runloop** 才回呼 onPick（呼叫端可以直接寫 store）。
struct OrgMovePersonPicker: View {
    let request: OrgMovePickRequest
    let onPick: (UUID, String) -> Void

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    init(request: OrgMovePickRequest, onPick: @escaping (UUID, String) -> Void) {
        self.request = request
        self.onPick = onPick
    }

    private var candidates: [(id: UUID, name: String, sub: String)] {
        let world = OrgMoveWorld(store: lifeStore)
        let skip = Set(request.excluding)
        let all = OrgMovePlan.receiverCandidates(personId: request.personId, world: world,
                                                 sideRoleId: request.sideRoleId).filter { !skip.contains($0.id) }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { c in
            c.name.localizedCaseInsensitiveContains(q) || c.sub.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(candidates, id: \.id) { c in
                    row(id: c.id, name: c.name, sub: c.sub)
                }
                if candidates.isEmpty {
                    Text("找不到符合的部屬。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .searchable(text: $query, prompt: "搜尋姓名、部門或職稱")
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func row(id: UUID, name: String, sub: String) -> some View {
        let isOn = id == request.selected
        return Button {
            dismiss()
            let pick = onPick
            DispatchQueue.main.async { pick(id, name) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isOn ? Color.teal : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if !sub.isEmpty {
                        Text(sub)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// [v25.593 轉組織 v2]〔交出去…〕挑人頁要做什麼（調出、離職、退休第 ② 步的待辦、週報、自己加的一項；交接單頁自己加的一項）
struct OrgMoveHandOutRequest: Identifiable, Equatable {
    let id = UUID()
    /// 轉組織的那位（清單不列、連到這位的組織人員也不列）
    let personId: UUID
    /// 新部門（調出才有；那個部門的管理人員排最前面）
    let toDeptId: UUID?
    /// 目前選的（打勾；「我」＝OrgMovePlan.meId）
    let selected: UUID?
    /// 呼叫端自己認得的用途（例："line:<列 id>"、"custom:<列 id>"）
    let purpose: String
}

/// [v25.593 轉組織 v2]〔交出去…〕挑人：第一列「我」（放在部屬總覽「我接的」），再列不在部屬名單、沒離職的組織人員
///（新部門的管理人員排前面；OrgMovePlan.handOutCandidates）。在職部屬不在這裡——那種用〔交給…〕。
/// 點一下：先關這一頁，**下一個 runloop** 才回呼 onPick(id, 名字)（「我」的 id 是 OrgMovePlan.meId、名字「我」；呼叫端可以直接寫 store）。
/// 主控寫好、凍結：各組只准呼叫，不改簽名。
struct OrgMoveHandOutPicker: View {
    let request: OrgMoveHandOutRequest
    let onPick: (UUID, String) -> Void

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    init(request: OrgMoveHandOutRequest, onPick: @escaping (UUID, String) -> Void) {
        self.request = request
        self.onPick = onPick
    }

    private var candidates: [OrgMoveHandOutCandidate] {
        let world = OrgMoveWorld(store: lifeStore)
        let all = OrgMovePlan.handOutCandidates(personId: request.personId, toDeptId: request.toDeptId, world: world)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { c in
            c.isMe || c.name.localizedCaseInsensitiveContains(q) || c.sub.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(candidates) { c in
                    row(c)
                }
                if candidates.count <= 1 {
                    Text("組織圖裡沒有其他不在部屬名單的人。可以先交給我，或到〔組織〕加人。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .searchable(text: $query, prompt: "搜尋姓名、部門或職稱")
            .navigationTitle("交出去給誰")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func row(_ c: OrgMoveHandOutCandidate) -> some View {
        let isOn = c.id == request.selected
        let id = c.id
        let name = c.name
        return Button {
            dismiss()
            let pick = onPick
            DispatchQueue.main.async { pick(id, name) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : (c.isMe ? "person.crop.circle" : "circle"))
                    .font(.system(size: 18))
                    .foregroundStyle(isOn ? Color.teal : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if !c.sub.isEmpty {
                        Text(c.sub)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 一列左邊 32pt 色圓裡一個字（任／缺／兼／機／報／組／會／議／班；同 FinanceLedgerRow 的分類色圓）
struct OrgMoveGlyph: View {
    let line: OrgMoveLine

    private var lookText: String { Self.look(line).text }
    private var lookColor: Color { Self.look(line).color }

    var body: some View {
        Text(lookText)
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Circle().fill(lookColor))
            .accessibilityHidden(true)
    }

    static func look(_ line: OrgMoveLine) -> (text: String, color: Color) {
        // [v25.592 轉組織 v1b] 你自己加的一項（門禁卡、鑰匙…）
        if line.isCustom { return ("自", Color.pink) }
        switch line.lineKind {
        case .some(.task):
            return line.lineLock == .dereliction ? ("缺", Color.red) : ("任", Color.cyan)
        case .some(.alarmTask):
            return ("警", Color.orange)
        case .some(.sideRole):
            return ("兼", Color.indigo)
        case .some(.equipment):
            return ("機", Color.teal)
        case .some(.report):
            return ("報", Color.purple)
        case .some(.manager), .some(.managerAdd):
            return ("組", Color.gray)
        // [v25.591 轉組織 v1a-2]
        case .some(.meeting):
            return ("會", Color.blue)
        case .some(.agenda):
            return ("議", Color.mint)
        case .some(.shifts):
            return ("班", Color.brown)
        case .none:
            return ("・", Color.gray)
        }
    }
}

// MARK: - [v25.592 轉組織 v1b] 〔＋ 自己加一項〕的小表單（精靈第 ② 步、交接單頁共用；主控寫好、凍結）

/// 打開「自己加一項」小表單（`.sheet(item:)`＋`.appStores()`）。lineId＝nil：新加；有值：改那一列
struct OrgMoveCustomRequest: Identifiable, Equatable {
    let id = UUID()
    var lineId: UUID? = nil
    var title: String = ""
    var memo: String = ""
}

/// 門禁卡、鑰匙、帳號、廠商窗口…只記在交接單上（不動任何資料）。按〔好〕：先關這一頁，**下一個 runloop** 才回呼 onSave
///（呼叫端可以直接寫 store 或草稿）。onDelete 有給才出現〔拿掉這一項〕（同樣關頁後下一個 runloop）
struct OrgMoveCustomLineEditor: View {
    let request: OrgMoveCustomRequest
    let onSave: (String, String) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var memo = ""
    @State private var loaded = false

    private static let examples = ["門禁卡", "鑰匙", "帳號", "廠商窗口", "公務手機"]

    init(request: OrgMoveCustomRequest, onSave: @escaping (String, String) -> Void, onDelete: (() -> Void)? = nil) {
        self.request = request
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例：門禁卡", text: $title)
                    exampleChips
                } header: {
                    Text("要交的東西")
                } footer: {
                    Text("只記在交接單上（可以勾已交），不會動任何資料。")
                }
                Section {
                    TextField("例：11/1 前交給總務", text: $memo, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("交接備註（會寫進分享的交接單）")
                }
                if onDelete != nil {
                    Section {
                        Button("拿掉這一項", role: .destructive) { remove() }
                    }
                }
            }
            .navigationTitle(request.lineId == nil ? "自己加一項" : "改這一項")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("好") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { load() }
        }
    }

    private var exampleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Self.examples, id: \.self) { e in
                    Button(e) { title = e }
                        .font(.caption)
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        title = request.title
        memo = request.memo
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        dismiss()
        let done = onSave
        DispatchQueue.main.async { done(t, m) }
    }

    private func remove() {
        dismiss()
        guard let del = onDelete else { return }
        DispatchQueue.main.async { del() }
    }
}
