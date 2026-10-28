import SwiftUI

// MARK: - [v25.590 轉組織 v1a-1] 部屬卡片上的轉組織零件（看板下那一條、接手那一區、歷程那一列）
// G3 寫這個檔（orgmove/build/v1a-1/brief.md §5）。SubordinateDetailView 只加呼叫（judge §7.1-6：那個檔不加大段 body）。
// 主控只放骨架：三個 struct 的名字與 init 簽名不准改。
// 這個檔只讀不寫：一個 lifeStore 的寫入都沒有（看交接單、歷程、接手那一區都不用訂閱，judge §6）。
// 句子都是 OrgMovePlan 組好的（personHint／receiverHints／receivedSections／historyRows／receivedPreviewLine），
// 這裡只排版；body 裡不放 let 計算、不寫長運算式。
// 隱私（judge §4.12）：這些都是 App 內頁；通知、小工具、手錶、鎖定畫面一個字都沒加。
// 要退回這一個檔：三個 struct 的 body 改回 EmptyView()，刪掉下面新加的型別，SubordinateDetailView 那幾行呼叫一起刪。
// [v25.591 轉組織 v1a-2] G3（orgmove/build/v1a-2/brief.md §5）：接手那一區多會議、議程、班、兼任四種圖示，會議、議程點了開那場會議
// （OrgMoveReceivedCard 多一個有預設值的 onOpenMeeting）；chips(task:)／previewLine(task:)（兼任分身照 sideRoleLink.taskId）。
// [v25.592 轉組織 v1b] G3（orgmove/build/v1b/brief.md §5）：提示列先擋改 OrgMovePlan.hasHint（認得部門還沒改的：排好的、交出去了的）；
// 一條多灰字一行（hint.note）、下面一排小按鈕（hint.actions：〔現在套用〕〔加進交接單〕〔只做交接〕〔選部門〕〔取消這張單〕，
// 走 G2 的 .orgMoveHintActions：訂閱、確認框、寫 store、跳「今天生效」都在那裡，這個檔照舊一個 lifeStore 的寫入都沒有）、
// 灰色那一種（hint.muted：接手的人「11/1 起會從王小明接手 6 項」）；精靈帶 presetDeptId。

// MARK: - 算資料（卡片每次重畫都會算，先擋掉沒有交接單的大多數時候）

/// 卡片那幾處共用的小計算（膠囊、預覽那一行、歷程混排、要不要建 OrgMoveWorld）
enum OrgMoveCardData {

    /// 有沒有跟這位同仁有關、還在交接中的單。沒有就不建 OrgMoveWorld、不掃全部部屬（卡片每次重畫都會走到）。
    /// 只做「寬鬆」的先擋：原人是這位；或單上有一列 toId 是這位（套用之後每一列自己記著接手的人）；
    /// 或有跟著機台、還沒寫 toId 的列（保守起見照算）。真正的判斷照 OrgMovePlan.personHint／receiverHints。
    static func hasOpenMove(personId: UUID, book: OrgMoveBook, todayKey: String) -> Bool {
        book.live.contains { m in
            guard OrgMovePlan.isOpen(m, todayKey: todayKey) else { return false }
            if m.personId == personId { return true }
            return m.allLines.contains { l in
                l.toId == personId || (l.action == OrgMoveAction.withEquipment.rawValue && l.toId == nil)
            }
        }
    }

    /// 這一筆（任務／週報 id）是不是還在顯示期間的「交接自」（持有人＝現在掛著它的那位）
    static func received(_ itemId: UUID, holderId: UUID, now: Date = Date()) -> OrgMoveIndex.Received? {
        OrgMoveIndex.receivedChip(itemId, holderId: holderId, todayKey: OrgMovePlan.dayKey(now))
    }

    /// 任務、週報列多的膠囊（judge §4.6）：紫色「交接自 王小明」（有交接備註多一個 💬）、
    /// 交接那一刻已逾期的再一顆灰色「交接時已逾期」（不紅：扣分留在原人，這位從新截止日算）。
    /// 到交接完成日（生效日＋10 天）、沒有待分派就自動收（receivedChip 用算的）。
    /// [v25.591 轉組織 v1a-2] 也給會議列用（新會議 id＝單上的 newId、整場交出去的＝原 id，receivedChip 都查得到；
    /// 會議沒有逾期的事，wasOverdue 一律 false，只會有紫色那一顆）
    static func chips(itemId: UUID, holderId: UUID, now: Date = Date()) -> [ItemChip] {
        guard let r = received(itemId, holderId: holderId, now: now) else { return [] }
        return chipList(r)
    }

    /// [v25.591 轉組織 v1a-2] 任務列的膠囊：先照任務 id 找，找不到再照 sideRoleLink.taskId（兼任分身換人後是新 id，
    /// judge §4.6；OrgMoveIndex.receivedChip(task:holderId:todayKey:)）。字同 chips(itemId:)。
    /// 要退回這一件：SubordinateDetailView 的 taskChips 改回 chips(itemId: t.id, …)，刪這支
    static func chips(task t: SubordinateTask, holderId: UUID, now: Date = Date()) -> [ItemChip] {
        guard let r = OrgMoveIndex.receivedChip(task: t, holderId: holderId, todayKey: OrgMovePlan.dayKey(now)) else {
            return []
        }
        return chipList(r)
    }

    /// 紫色「交接自 王小明」（有交接備註多 💬）＋灰色「交接時已逾期」（v1a-1 的字，兩支共用）
    private static func chipList(_ r: OrgMoveIndex.Received) -> [ItemChip] {
        let from = r.fromName.trimmingCharacters(in: .whitespaces).isEmpty ? "這位同仁" : r.fromName
        let text = "交接自 " + from + (r.memo.isEmpty ? "" : " 💬")
        var out: [ItemChip] = [ItemChip(id: "handover", text: text, color: .purple, icon: "arrow.left.arrow.right")]
        if r.wasOverdue {
            out.append(ItemChip(id: "handoverLate", text: "交接時已逾期", color: .secondary))
        }
        return out
    }

    /// 任務、週報預覽多的那一行（judge §4.6）：「11/2 交接自 王小明（原訂 10/20）・備註：…」。
    /// hidden：預覽出圖（forExport）不放——交接備註只在 App 內頁與交接單的分享（brief §1-6）
    static func previewLine(itemId: UUID, holderId: UUID, hidden: Bool, now: Date = Date()) -> String? {
        guard !hidden, let r = received(itemId, holderId: holderId, now: now) else { return nil }
        return OrgMovePlan.receivedPreviewLine(r)
    }

    /// [v25.591 轉組織 v1a-2] 任務預覽那一行：同 chips(task:)，兼任分身照 sideRoleLink.taskId 也找得到。
    /// 要退回這一件：任務預覽改回 previewLine(itemId: t.id, …)，刪這支
    static func previewLine(task t: SubordinateTask, holderId: UUID, hidden: Bool, now: Date = Date()) -> String? {
        guard !hidden,
              let r = OrgMoveIndex.receivedChip(task: t, holderId: holderId, todayKey: OrgMovePlan.dayKey(now)) else {
            return nil
        }
        return OrgMovePlan.receivedPreviewLine(r)
    }
}

// MARK: - 〔潛力性〕「歷程」：升職、轉組織混在同一條

/// 「歷程」的一列（升職照舊 promotionRow、轉組織 OrgMoveHistoryRowView）
enum OrgMoveCardHistoryItem: Identifiable {
    case promotion(PromotionRecord)
    case move(OrgMoveHistoryRow)

    var id: String {
        switch self {
        case .promotion(let p): return "p-" + p.id.uuidString
        case .move(let r): return "m-" + r.moveId.uuidString
        }
    }

    /// 排序用：升職＝生效日期；轉組織＝生效日那天 00:00
    var date: Date {
        switch self {
        case .promotion(let p): return p.date
        case .move(let r): return r.date
        }
    }

    /// 新到舊排好的一條（judge §4.7）。轉組織列含已復原的（灰、寫「（已復原）」；交接單永遠在歷程裡）。
    /// 這位同仁沒有任何交接單就不建 OrgMoveWorld（卡片每次重畫都會走到）
    static func items(promotions: [PromotionRecord], personId: UUID, store: LifeStore) -> [OrgMoveCardHistoryItem] {
        var out: [OrgMoveCardHistoryItem] = promotions.map { OrgMoveCardHistoryItem.promotion($0) }
        let book = store.orgMoves
        if book.live.contains(where: { $0.personId == personId && $0.wasApplied }) {
            let rows = OrgMovePlan.historyRows(personId: personId, book: book, world: OrgMoveWorld(store: store))
            out.append(contentsOf: rows.map { OrgMoveCardHistoryItem.move($0) })
        }
        return out.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            return a.id < b.id
        }
    }
}

// MARK: - 看板下那一條提示列

/// 看板下面、分頁切換器上面那一條細提示列（原人＋接手的人；有事才出現，沒事整條不佔位）
/// [v25.592 轉組織 v1b] 提示列上的按鈕（hint.actions）設 actionRequest，body 掛 .orgMoveHintActions（G2 的 modifier：
/// 訂閱、確認框、下一個 runloop 寫 store、做完跳「今天生效」都在那裡）。要退回這一件：刪 actionRequest、requestAction、
/// body 的 .orgMoveHintActions，OrgMoveHintBarList／OrgMoveHintBarRow 刪 onAction
struct OrgMoveHintBars: View {
    let personId: UUID
    /// 點〔看〕：打開那一張交接單（moveId）
    let onOpen: (UUID) -> Void

    @EnvironmentObject var lifeStore: LifeStore
    /// [v25.592 轉組織 v1b] 提示列上按了哪一顆（modifier 用完清 nil）
    @State private var actionRequest: OrgMoveHintActionRequest?

    init(personId: UUID, onOpen: @escaping (UUID) -> Void) {
        self.personId = personId
        self.onOpen = onOpen
    }

    /// 原人那一條在前（每人最多一條）、接手的那幾條在後（每張還在交接中、有交給這位的單一條）。
    /// 例：王小明「11/1 從製造一課調來・交出去 5・做完 0」＋橘點「待分派 1」；陳怡君「從王小明接手 4 項・做完 0」
    /// [v25.592 轉組織 v1b] 先擋改 OrgMovePlan.hasHint：多認得部門還沒改的（「11/1 起調設備課・交接單排好了（16 項）」
    /// 「11/1 起調設備課・已交出 9 項」、接手的人灰色「11/1 起會從王小明接手 6 項」）。
    /// 要退回這一件：改回 OrgMoveCardData.hasOpenMove(personId:book:todayKey:)
    private var hints: [OrgMoveHint] {
        let now = Date()
        let book = lifeStore.orgMoves
        guard OrgMovePlan.hasHint(personId: personId, book: book, todayKey: OrgMovePlan.dayKey(now)) else {
            return []
        }
        let world = OrgMoveWorld(store: lifeStore)
        var out: [OrgMoveHint] = []
        if let h = OrgMovePlan.personHint(personId: personId, book: book, world: world, now: now) {
            out.append(h)
        }
        out.append(contentsOf: OrgMovePlan.receiverHints(personId: personId, book: book, world: world, now: now))
        return out
    }

    /// [v25.592 轉組織 v1b] 按過〔現在套用〕〔選部門〕：之後提示列就算全空了，也留一個 0 高的透明底給 .orgMoveHintActions 掛
    ///（「今天生效」那張、選部門那一頁、確認框都掛在這條提示列上；交接完成日已經過了才按的，改好那一刻這條就收了，
    /// 沒有底「今天生效」就跳不出來——同 OrgMoveDueCard 的 busy）。只有這種時候才多那 16pt 的間距，離開卡片就沒了。
    /// 要退回這一件：刪 keepHost、requestAction 裡那一行，OrgMoveHintBarList 刪 keepHost 與 else if 那一段
    @State private var keepHost = false

    /// [v25.592 轉組織 v1b] 提示列上按了一顆：交給 .orgMoveHintActions（這裡不判斷訂閱、不寫 store）
    private func requestAction(_ moveId: UUID, _ action: OrgMoveHintAction) {
        if action == .applyNow || action == .pickDept { keepHost = true }
        actionRequest = OrgMoveHintActionRequest(moveId: moveId, action: action)
    }

    var body: some View {
        OrgMoveHintBarList(hints: hints, keepHost: keepHost, onOpen: onOpen, onAction: requestAction)
            .orgMoveHintActions($actionRequest)
    }
}

private struct OrgMoveHintBarList: View {
    let hints: [OrgMoveHint]
    /// [v25.592 轉組織 v1b] 提示列空了也留 0 高的透明底（OrgMoveHintBars.keepHost）
    let keepHost: Bool
    let onOpen: (UUID) -> Void
    /// [v25.592 轉組織 v1b] 按了一條上的按鈕（moveId、哪一顆）
    let onAction: (UUID, OrgMoveHintAction) -> Void

    var body: some View {
        if !hints.isEmpty {
            VStack(spacing: 8) {
                ForEach(hints) { h in
                    OrgMoveHintBarRow(hint: h, onOpen: onOpen, onAction: onAction)
                }
            }
            .padding(.horizontal)
        } else if keepHost {
            Color.clear
                .frame(height: 0)
                .accessibilityHidden(true)
        }
    }
}

/// 一條：白卡、圓角 14、左邊雙箭頭、右邊〔看〕；第二行橘點「待分派 1」、橘字警告（judge §4.7 表）
/// [v25.592 轉組織 v1b] 再一行灰字（note）、最下面一排小按鈕（actions）；muted＝整條灰（灰底、灰圖示、灰字、沒有陰影）。
/// 上半截（圖示、字、〔看〕）照舊整塊點了開交接單；按鈕那一排空白的地方點了也開交接單（按鈕自己的點擊優先）。
/// 要退回這一件：改回一整顆 Button（上半截 OrgMoveCardHintMain 的內容＋原本的背景、陰影），刪 OrgMoveCardHintActionStrip
private struct OrgMoveHintBarRow: View {
    let hint: OrgMoveHint
    let onOpen: (UUID) -> Void
    let onAction: (UUID, OrgMoveHintAction) -> Void

    private var hasActions: Bool { !hint.actions.isEmpty }
    /// 有按鈕時上半截底下留少一點（按鈕那一排自己有下邊距）
    private var mainBottom: CGFloat { hasActions ? 7 : 11 }
    private var fill: Color { hint.muted ? Color(.tertiarySystemFill) : Color(.systemBackground) }
    private var shadowOpacity: Double { hint.muted ? 0 : 0.05 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OrgMoveCardHintMain(hint: hint, bottomPadding: mainBottom, onOpen: onOpen)
            if hasActions {
                OrgMoveCardHintActionStrip(moveId: hint.moveId, actions: hint.actions,
                                           onOpen: onOpen, onAction: onAction)
            }
        }
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(shadowOpacity), radius: 6, x: 0, y: 2)
    }
}

/// [v25.592 轉組織 v1b] 提示列上半截（v1a 那一整條）：左圖示、字、右〔看〕；整塊點了開交接單
private struct OrgMoveCardHintMain: View {
    let hint: OrgMoveHint
    let bottomPadding: CGFloat
    let onOpen: (UUID) -> Void

    private var iconColor: Color { hint.muted ? Color.gray : Color.blue }
    private var linkColor: Color { hint.muted ? Color.secondary : Color.blue }

    var body: some View {
        Button {
            onOpen(hint.moveId)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                OrgMoveCardIcon(color: iconColor, size: 30, iconSize: 12)
                OrgMoveCardHintTexts(hint: hint)
                Spacer(minLength: 6)
                OrgMoveLinkLabel(text: "看", color: linkColor)
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, bottomPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("打開交接單")
    }
}

/// [v25.592 轉組織 v1b] 提示列的字：主句、橘點「待分派 1」、橘字警告、灰字一行（note：「排好之後多了 1 件（先跟著王小明）」）。
/// muted 的主句灰、點與警告也灰（不用紫／橘；照理灰色那一種不會有點與警告）
private struct OrgMoveCardHintTexts: View {
    let hint: OrgMoveHint

    private var textColor: Color { hint.muted ? Color.secondary : Color.primary }
    private var alertColor: Color { hint.muted ? Color.secondary : Color.orange }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hint.text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(textColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let badge = hint.badge {
                OrgMoveDotLabel(text: badge, color: alertColor)
            }
            if let warning = hint.warning {
                Text(warning)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(alertColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = hint.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// [v25.592 轉組織 v1b] 提示列最下面一排小按鈕（對齊字的左邊：圖示 30＋間距 10＋左邊距 14＝54）。
/// 一排放不下（字放大時）就直的排。空白的地方點了照舊開交接單
private struct OrgMoveCardHintActionStrip: View {
    let moveId: UUID
    let actions: [OrgMoveHintAction]
    let onOpen: (UUID) -> Void
    let onAction: (UUID, OrgMoveHintAction) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                chips
            }
            VStack(alignment: .leading, spacing: 6) {
                chips
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 54)
        .padding(.trailing, 14)
        .padding(.bottom, 11)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen(moveId)
        }
    }

    private var chips: some View {
        ForEach(actions) { a in
            OrgMoveCardHintActionChip(action: a) {
                onAction(moveId, a)
            }
        }
    }
}

/// [v25.592 轉組織 v1b] 一顆小按鈕：〔現在套用〕藍底白字（最要緊的那一顆）、〔取消這張單〕紅字、其他藍字（淡底膠囊）
private struct OrgMoveCardHintActionChip: View {
    let action: OrgMoveHintAction
    let onTap: () -> Void

    private var prominent: Bool { action == .applyNow }
    private var tint: Color { action == .cancel ? Color.red : Color.blue }
    private var textColor: Color { prominent ? Color.white : tint }
    private var chipFill: Color { prominent ? tint : tint.opacity(0.12) }

    var body: some View {
        Button(action: onTap) {
            Text(action.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(chipFill)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 橘點＋橘字（「待分派 1」）
/// [v25.592 轉組織 v1b] color 有預設值（橘）：灰色那一種提示列傳灰。要退回這一件：刪 color，兩處改回 Color.orange
private struct OrgMoveDotLabel: View {
    let text: String
    var color: Color = .orange

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
    }
}

/// 右邊的藍字連結（「看 ›」「交接單 ›」）
/// [v25.592 轉組織 v1b] color 有預設值（藍）：灰色那一種提示列傳灰。要退回這一件：刪 color，改回 Color.blue
private struct OrgMoveLinkLabel: View {
    let text: String
    var color: Color = .blue

    var body: some View {
        HStack(spacing: 2) {
            Text(text)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(color)
    }
}

/// 雙箭頭漸層圓（提示列 30pt、接手那一區標頭 30pt、歷程那一列 36pt）
private struct OrgMoveCardIcon: View {
    let color: Color
    let size: CGFloat
    let iconSize: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [color.opacity(0.20), color.opacity(0.08)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .stroke(color.opacity(0.20), lineWidth: 0.75)
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 接手的人〔主動性〕最上面那一區

/// 接手的人〔主動性〕分頁最上面「從王小明接手（4）・11/2」那一區（還在交接中才有）
struct OrgMoveReceivedCard: View {
    let personId: UUID
    /// 點標頭：打開那一張交接單（moveId）
    let onOpenMove: (UUID) -> Void
    /// 點一列待辦：開那件任務的預覽（任務 id；卡片那邊照現在的規矩要訂閱）
    let onOpenTask: (UUID) -> Void
    /// 點一列週報：開那份週報的預覽（週報 id）
    let onOpenReport: (UUID) -> Void
    /// [v25.591 轉組織 v1a-2] 點一列會議（新會議、整場交出去的）、議程：開那場會議的預覽（會議 id、持有人 id；
    /// 卡片那邊照現在的規矩要訂閱）。有預設值：v1a-1 的呼叫照樣編得過。
    /// 要退回這一件：刪這個參數與一路傳下去的 onOpenMeeting，OrgMoveReceivedRowButton 刪會議那一支
    let onOpenMeeting: (UUID, UUID) -> Void

    @EnvironmentObject var lifeStore: LifeStore

    init(personId: UUID, onOpenMove: @escaping (UUID) -> Void, onOpenTask: @escaping (UUID) -> Void,
         onOpenReport: @escaping (UUID) -> Void, onOpenMeeting: @escaping (UUID, UUID) -> Void = { _, _ in }) {
        self.personId = personId
        self.onOpenMove = onOpenMove
        self.onOpenTask = onOpenTask
        self.onOpenReport = onOpenReport
        self.onOpenMeeting = onOpenMeeting
    }

    /// 每一張還在交接中、有交給這位的單一段（每列照現在的資料算：✓ 做完、○ 還沒做、● 機台負責人、⚠ 兩個人身上）
    private var sections: [OrgMoveReceivedSection] {
        let now = Date()
        let book = lifeStore.orgMoves
        guard OrgMoveCardData.hasOpenMove(personId: personId, book: book, todayKey: OrgMovePlan.dayKey(now)) else {
            return []
        }
        return OrgMovePlan.receivedSections(personId: personId, book: book, world: OrgMoveWorld(store: lifeStore), now: now)
    }

    var body: some View {
        OrgMoveReceivedList(sections: sections, onOpenMove: onOpenMove, onOpenTask: onOpenTask,
                            onOpenReport: onOpenReport, onOpenMeeting: onOpenMeeting)
    }
}

private struct OrgMoveReceivedList: View {
    let sections: [OrgMoveReceivedSection]
    let onOpenMove: (UUID) -> Void
    let onOpenTask: (UUID) -> Void
    let onOpenReport: (UUID) -> Void
    let onOpenMeeting: (UUID, UUID) -> Void

    var body: some View {
        if !sections.isEmpty {
            VStack(spacing: 16) {
                ForEach(sections) { s in
                    OrgMoveReceivedSectionCard(section: s, onOpenMove: onOpenMove, onOpenTask: onOpenTask,
                                               onOpenReport: onOpenReport, onOpenMeeting: onOpenMeeting)
                }
            }
        }
    }
}

/// 一張單一張白卡（同卡片其他區塊：圓角 16、細邊、淡陰影）
private struct OrgMoveReceivedSectionCard: View {
    let section: OrgMoveReceivedSection
    let onOpenMove: (UUID) -> Void
    let onOpenTask: (UUID) -> Void
    let onOpenReport: (UUID) -> Void
    let onOpenMeeting: (UUID, UUID) -> Void

    private var lastIndex: Int { section.rows.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OrgMoveReceivedHeader(header: section.header) {
                onOpenMove(section.moveId)
            }
            ForEach(Array(section.rows.enumerated()), id: \.element.id) { idx, row in
                OrgMoveReceivedRowButton(row: row, onOpenTask: onOpenTask, onOpenReport: onOpenReport,
                                         onOpenMeeting: onOpenMeeting)
                if idx < lastIndex {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .padding(.bottom, 4)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }
}

/// 標頭「從王小明接手（4）・11/2」＋右邊「交接單 ›」；整條點了開交接單（看交接單不用訂閱，judge §6）
private struct OrgMoveReceivedHeader: View {
    let header: String
    let onTap: () -> Void

    /// 「從王小明接手」粗體、「（4）・11/2」灰字（照最後一個「（」切；切不到整句粗體）
    private var mainText: String {
        guard let r = header.range(of: "（", options: .backwards) else { return header }
        return String(header[..<r.lowerBound])
    }

    private var tailText: String {
        guard let r = header.range(of: "（", options: .backwards) else { return "" }
        return String(header[r.lowerBound...])
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(LinearGradient(colors: [Color.blue, Color.blue.opacity(0.55)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 18)
                OrgMoveCardIcon(color: .blue, size: 30, iconSize: 12)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(mainText)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.primary)
                    Text(tailText)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                OrgMoveLinkLabel(text: "交接單")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打開交接單")
    }
}

/// 一列：任務、週報點了開預覽（呼叫端照現在的規矩擋訂閱）；機台那列不給點。
/// [v25.591 轉組織 v1a-2] 會議（新會議、整場交出去的）、議程（含拉進兼任的議程）：開那場會議（持有人＝meetingHolderId）；
/// 兼任：taskId 已經是接手的人身上那一筆（分身換人後的新 id，OrgMovePlan.receivedRow 算好）；班不給點。
/// 要退回這一件：刪會議那一支（第一個 if）
private struct OrgMoveReceivedRowButton: View {
    let row: OrgMoveReceivedRow
    let onOpenTask: (UUID) -> Void
    let onOpenReport: (UUID) -> Void
    let onOpenMeeting: (UUID, UUID) -> Void

    var body: some View {
        if let mid = row.meetingId, let hid = row.meetingHolderId {
            Button {
                onOpenMeeting(mid, hid)
            } label: {
                OrgMoveReceivedRowLabel(row: row, tappable: true)
            }
            .buttonStyle(.plain)
        } else if let tid = row.taskId {
            Button {
                onOpenTask(tid)
            } label: {
                OrgMoveReceivedRowLabel(row: row, tappable: true)
            }
            .buttonStyle(.plain)
        } else if let rid = row.reportId {
            Button {
                onOpenReport(rid)
            } label: {
                OrgMoveReceivedRowLabel(row: row, tappable: true)
            }
            .buttonStyle(.plain)
        } else {
            OrgMoveReceivedRowLabel(row: row, tappable: false)
        }
    }
}

/// 例：「○ E-03 腔體漏率改善　截止 11/9・交接時已逾期」「● 蝕刻機 E-03　負責人」
private struct OrgMoveReceivedRowLabel: View {
    let row: OrgMoveReceivedRow
    let tappable: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            OrgMoveMarkIcon(mark: row.mark, kind: OrgMoveMarkIcon.kindFor(row))
            VStack(alignment: .leading, spacing: 3) {
                MarqueeText(row.title.isEmpty ? "未命名" : row.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.primary)
                if !row.detail.isEmpty {
                    Text(row.detail)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if tappable {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// 左邊的狀態圖示（✓ 綠勾、○ 空圈、● 機台齒輪／實心圈、⚠ 橘三角、◌ 虛線圈、・ 灰減號圈）；顏色照種類（任務青、週報紫、機台綠藍）
/// [v25.591 轉組織 v1a-2] 多四種（brief §5-1；會、議、班的顏色同 OrgMoveGlyph，兼任照 brief 用橘，OrgMoveGlyph「兼」是靛）：
/// 會議藍 person.3.fill、議程薄荷 text.bubble、班棕 calendar、兼任橘 star。○、● 畫那一種自己的圖示（● 實心、○ 空心）；
/// ✓ ⚠ ◌ ・ 照舊畫狀態。要退回這一件：Kind 刪後四個 case、kindFor 改回只看 taskId／reportId、刪 filledSymbol／outlineSymbol／symbolSize
private struct OrgMoveMarkIcon: View {
    enum Kind { case task, report, equipment, meeting, agenda, shifts, sideRole }

    let mark: String
    let kind: Kind

    /// 照 row.kind（OrgMoveLineKind 的字）；空的、認不得的照 v1a-1 推（taskId → 任務、reportId → 週報、其他 → 機台）
    static func kindFor(_ row: OrgMoveReceivedRow) -> Kind {
        switch OrgMoveLineKind(rawValue: row.kind) {
        case .some(.meeting): return .meeting
        case .some(.agenda): return .agenda
        case .some(.shifts): return .shifts
        case .some(.sideRole): return .sideRole
        case .some(.equipment): return .equipment
        case .some(.report): return .report
        case .some(.task), .some(.alarmTask): return .task
        default: break
        }
        if row.taskId != nil { return .task }
        if row.reportId != nil { return .report }
        return .equipment
    }

    private var kindColor: Color {
        switch kind {
        case .task: return .cyan
        case .report: return .purple
        case .equipment: return .teal
        case .meeting: return .blue
        case .agenda: return .mint
        case .shifts: return .brown
        case .sideRole: return .orange
        }
    }

    /// ● 的圖示（任務、週報＝實心圈；其他畫那一種）
    private var filledSymbol: String {
        switch kind {
        case .task, .report: return "circle.fill"
        case .equipment: return "gearshape.fill"
        case .meeting: return "person.3.fill"
        case .agenda: return "text.bubble.fill"
        case .shifts: return "calendar"
        case .sideRole: return "star.fill"
        }
    }

    /// ○（與其他沒列到的符號）的圖示（會議的狀態只有 ●✓⚠・，○ 照理不會出現；出現就畫空心的 person.3，同其他種類）
    private var outlineSymbol: String {
        switch kind {
        case .task, .report: return "circle"
        case .equipment: return "gearshape"
        case .meeting: return "person.3"
        case .agenda: return "text.bubble"
        case .shifts: return "calendar"
        case .sideRole: return "star"
        }
    }

    private var symbol: String {
        switch mark {
        case "✓": return "checkmark.circle.fill"
        case "⚠": return "exclamationmark.triangle.fill"
        case "◌": return "circle.dashed"
        case "●": return filledSymbol
        // 「・」＝現在在別人身上、找不到了、不要了…（灰色減號圈，跟「○ 還沒做」的空圈分得開）
        case "・": return "minus.circle"
        default: return outlineSymbol
        }
    }

    /// person.3 很寬：縮小才塞得進 24pt 那一格（其他照 19）
    private var symbolSize: CGFloat {
        symbol.hasPrefix("person.3") ? 12 : 19
    }

    private var tint: Color {
        switch mark {
        case "✓": return .green
        case "⚠", "◌": return .orange
        case "○": return kindColor
        case "●": return (kind == .task || kind == .report) ? Color.gray : kindColor
        default: return Color.gray
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: symbolSize))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }
}

// MARK: - 任務、週報列的膠囊；預覽那一行

/// 週報列「交接自 王小明」那幾顆小膠囊（樣子同 ItemChipBar 的膠囊；字在 OrgMoveCardData.chips 組好）。
/// 呼叫端：`OrgMoveHandoverChipRow(chips: OrgMoveCardData.chips(itemId: r.id, holderId: subordinateId))`
struct OrgMoveHandoverChipRow: View {
    let chips: [ItemChip]

    var body: some View {
        if !chips.isEmpty {
            HStack(spacing: 6) {
                ForEach(chips) { c in
                    OrgMoveSmallChip(chip: c)
                }
            }
        }
    }
}

private struct OrgMoveSmallChip: View {
    let chip: ItemChip

    var body: some View {
        HStack(spacing: 3) {
            if let icon = chip.icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
            }
            Text(chip.text)
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(chip.color)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(chip.color.opacity(0.14))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(chip.color.opacity(0.25), lineWidth: 0.6))
    }
}

/// 任務、週報預覽（SubordinateItemCard）資訊列多的一行（有才出現）。
/// 呼叫端：`OrgMoveReceivedPreviewLine(text: OrgMoveCardData.previewLine(itemId:holderId:hidden: forExport))`
struct OrgMoveReceivedPreviewLine: View {
    let text: String?

    var body: some View {
        if let text {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.purple)
                    .padding(.top, 3)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        }
    }
}

// MARK: - 〔潛力性〕「歷程」裡轉組織那一列

/// 〔潛力性〕「歷程」裡轉組織那一列（圖示 arrow.left.arrow.right；點了開交接單由呼叫端包 Button）
/// 畫法照 promotionRow：36pt 圓、第一行「製造一課 P1 → 設備課 P2」＋右邊「交接單 ›」、
/// 第二行日期膠囊「2026/11/1 轉組織」＋灰字「交出去 5・跟著 2」。已復原：整列灰、沒有「交接單 ›」（點了照樣打得開）。
struct OrgMoveHistoryRowView: View {
    let row: OrgMoveHistoryRow

    init(row: OrgMoveHistoryRow) {
        self.row = row
    }

    private var tint: Color { row.isUndone ? Color.gray : Color.blue }
    private var mainColor: Color { row.isUndone ? Color.secondary : Color.primary }
    /// 已復原的 title 已經寫「（已復原）」，sub 也是「（已復原）」：不寫兩次
    private var showSub: Bool { !row.isUndone && !row.sub.isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            OrgMoveCardIcon(color: tint, size: 36, iconSize: 14)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.detail)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(mainColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    if !row.isUndone {
                        OrgMoveLinkLabel(text: "交接單")
                    }
                }
                HStack(spacing: 6) {
                    OrgMoveDateCapsule(text: row.title)
                    if showSub {
                        Text(row.sub)
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .opacity(row.isUndone ? 0.7 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// 灰底日期膠囊（同 promotionRow 的日期膠囊）
private struct OrgMoveDateCapsule: View {
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "calendar")
                .font(.system(size: 9))
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(Color.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Color(.tertiarySystemFill))
        .clipShape(Capsule())
    }
}

// MARK: - 卡片的兩個 sheet（精靈、交接單頁）

/// 部屬卡片的兩個 sheet：「…」〔轉組織〕開精靈；提示列〔看〕、接手那一區標頭、歷程那一列開交接單頁。
/// 一律 `.sheet(item:)`＋`.appStores()`。包成一個 modifier：SubordinateDetailView 那一串修飾器只多一行
///（那個檔型別檢查有前科，closure 放在這裡檢查）。
struct OrgMoveCardSheets: ViewModifier {
    @Binding var wizard: OrgMoveWizardRequest?
    @Binding var sheet: OrgMoveSheetRequest?

    func body(content: Content) -> some View {
        content
            .sheet(item: $wizard) { r in
                // [v25.592 轉組織 v1b] 帶 presetDeptId（組織頁〔用轉組織〕帶新部門；卡片「…」是 nil＝照舊）。
                // 要退回這一件：改回 OrgMoveWizard(personId: r.personId)
                OrgMoveWizard(personId: r.personId, presetDeptId: r.presetDeptId)
                    .appStores()
            }
            .sheet(item: $sheet) { r in
                OrgMoveSheetView(moveId: r.moveId)
                    .appStores()
            }
    }
}

extension View {
    /// 部屬卡片的轉組織精靈、交接單頁兩個 sheet（OrgMoveCardSheets）
    func orgMoveCardSheets(wizard: Binding<OrgMoveWizardRequest?>, sheet: Binding<OrgMoveSheetRequest?>) -> some View {
        modifier(OrgMoveCardSheets(wizard: wizard, sheet: sheet))
    }
}
