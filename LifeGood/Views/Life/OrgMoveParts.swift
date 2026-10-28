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
        let all = OrgMovePlan.receiverCandidates(personId: request.personId, world: world)
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

/// 一列左邊 32pt 色圓裡一個字（任／缺／兼／機／報／組；同 FinanceLedgerRow 的分類色圓）
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
        case .none:
            return ("・", Color.gray)
        }
    }
}
