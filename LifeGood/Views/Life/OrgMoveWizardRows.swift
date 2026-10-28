import SwiftUI

// MARK: - [v25.591 轉組織 v1a-2] 精靈第 ② 步多的幾種列：會議（三顆＋新會議名稱〔改〕）、撞班那幾天、兼任〔到兼任換人…〕
// G1 寫這個檔（orgmove/build/v1a-2/brief.md §3）。OrgMoveWizard.swift 已經 1,900 行：新的列、撞班展開、改名小表單一律寫在這裡，
// 那個檔只加呼叫。主控只放骨架：下面兩個 struct 的名字與 init 不准改（字、選項都在 OrgMovePlan 組好，這裡只排版）。
// 要退回這一個檔：兩個 struct 的 body 改回 EmptyView()（下面兩個 private 小零件一起刪），OrgMoveWizard.swift 那幾行呼叫一起刪。

/// 班那一列〔交給…〕之後，撞班那幾天（只有這幾天展開；judge §4.3）：
/// 每一天「⚠ 11/4（三）林志豪已經排了日值班」＋〔改成大夜〕〔這天清掉〕〔這天交給別人…〕＋選了之後那一行灰字。
/// onChoose(day, choice)：choice＝"overwrite"／"drop"；〔這天交給別人…〕＝onPickOther(day)（呼叫端開挑人頁，回來寫部屬 id 字串）
struct OrgMoveShiftConflictList: View {
    let conflicts: [OrgMoveShiftConflict]
    let onChoose: (String, String) -> Void
    let onPickOther: (String) -> Void

    init(conflicts: [OrgMoveShiftConflict], onChoose: @escaping (String, String) -> Void,
         onPickOther: @escaping (String) -> Void) {
        self.conflicts = conflicts
        self.onChoose = onChoose
        self.onPickOther = onPickOther
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(conflicts) { c in
                OrgMoveShiftConflictDay(conflict: c, onChoose: onChoose, onPickOther: onPickOther)
            }
        }
    }
}

/// 撞班的一天（橘字一行、三顆小膠囊、選了之後那一行灰字；字都是 OrgMovePlan.shiftConflicts 組好的）
private struct OrgMoveShiftConflictDay: View {
    let conflict: OrgMoveShiftConflict
    let onChoose: (String, String) -> Void
    let onPickOther: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(conflict.warning)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            chips
            Text(conflict.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// 三顆：〔改成大夜〕〔這天清掉〕〔這天交給別人…〕（窄螢幕可以左右滑）
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                OrgMoveShiftDayChip(text: conflict.overwriteLabel, on: isOverwrite) { chooseOverwrite() }
                OrgMoveShiftDayChip(text: conflict.dropLabel, on: isDrop) { chooseDrop() }
                OrgMoveShiftDayChip(text: conflict.otherLabel, on: isOther) { pickOther() }
            }
        }
    }

    private var isOverwrite: Bool { conflict.choice == "overwrite" }
    private var isDrop: Bool { conflict.choice == "drop" }
    /// 存的是部屬 id 字串＝〔這天交給別人…〕
    private var isOther: Bool { !isOverwrite && !isDrop }

    private func chooseOverwrite() { onChoose(conflict.day, "overwrite") }
    private func chooseDrop() { onChoose(conflict.day, "drop") }
    private func pickOther() { onPickOther(conflict.day) }
}

/// 撞班那天的一顆小膠囊（選中的藍底、打勾）
private struct OrgMoveShiftDayChip: View {
    let text: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if on {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                }
                Text(text)
                    .font(.caption.weight(on ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(on ? Color.white : Color.primary)
            .background(on ? Color.blue : Color(.tertiarySystemFill), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// 會議那一列選〔交給…〕之後：「新會議名稱：週會〔改〕」（這個名稱會出現在通知與手錶上，建議不要放人名）。
/// onRename：呼叫端開改名的 alert（TextField），寫回那一列的 newTopic＋updatedAt
struct OrgMoveMeetingTopicRow: View {
    let topic: String
    let onRename: () -> Void

    init(topic: String, onRename: @escaping () -> Void) {
        self.topic = topic
        self.onRename = onRename
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("改", action: onRename)
                    .font(.caption.weight(.semibold))
                    .accessibilityLabel("改新會議名稱")
            }
            Text("這個名稱會出現在通知與手錶上，建議不要放人名")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 「新會議名稱：週會」
    private var label: String { "新會議名稱：" + topic }
}

// MARK: - [v25.592 轉組織 v1b] 精靈 v1b 多的幾個小零件（orgmove/build/v1b/brief.md §3）
// 一位同仁同時只能有一張（橘框卡、〔打開那張〕的交接單頁、〔取消那張、重排〕的確認框）、第 ③ 步「什麼時候做」的一顆、
// 第 ② 步〔＋ 自己加一項〕。字都在 OrgMovePlan 組好（plannedPrompt／cancelAsk／timingOptions），這裡只排版。
// 要退回這一段：刪到檔尾，OrgMoveWizard.swift 那幾處 [v25.592 轉組織 v1b] 呼叫一起刪。

/// 第 ① 步最上面那張橘框卡（judge §5-21「王小明已經排了 11/1 轉組織〔打開那張〕〔取消那張、重排〕」）。
/// 不用 alert：精靈剛打開就跳 alert 會跟 sheet 的動畫打架
struct OrgMoveWizPlannedCard: View {
    let prompt: OrgMovePlannedPrompt
    let onOpen: () -> Void
    let onCancel: () -> Void

    init(prompt: OrgMovePlannedPrompt, onOpen: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.prompt = prompt
        self.onOpen = onOpen
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                Text(prompt.title)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.orange)
            Text(prompt.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            buttons
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.55), lineWidth: 1)
        }
    }

    /// 〔打開那張〕〔取消那張、重排〕
    private var buttons: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                Text("打開那張")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            Button(action: onCancel) {
                Text("取消那張、重排")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(.red)
            Spacer(minLength: 0)
        }
        .controlSize(.small)
        .padding(.top, 2)
    }
}

/// 〔取消那張、重排〕要的那一份：哪一張、確認框的字（OrgMovePlan.cancelAsk）
struct OrgMoveWizCancelRequest: Identifiable {
    let id = UUID()
    let moveId: UUID
    let ask: OrgMoveCancelAsk

    init(moveId: UUID, ask: OrgMoveCancelAsk) {
        self.moveId = moveId
        self.ask = ask
    }
}

/// 精靈根層：〔打開那張〕的交接單頁（`.sheet(item:)`＋`.appStores()`；關掉時 onSheetClosed：在那張單上取消、拿回來之後清單要重算）、
/// 〔取消那張、重排〕的確認框（排好的：一顆〔取消這張單〕；交出去了：〔拿回來（還沒做完的 7 項）〕〔留給接手的人〕＋〔不要取消〕）。
/// onCancel(moveId, takeBack)：呼叫端在下一個 runloop 寫 store（LifeStore.cancelOrgMove）
struct OrgMoveWizPlannedActions: ViewModifier {
    @Binding var sheet: OrgMoveSheetRequest?
    @Binding var cancel: OrgMoveWizCancelRequest?
    let onCancel: (UUID, Bool) -> Void
    let onSheetClosed: () -> Void

    init(sheet: Binding<OrgMoveSheetRequest?>, cancel: Binding<OrgMoveWizCancelRequest?>,
         onCancel: @escaping (UUID, Bool) -> Void, onSheetClosed: @escaping () -> Void) {
        self._sheet = sheet
        self._cancel = cancel
        self.onCancel = onCancel
        self.onSheetClosed = onSheetClosed
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: $sheet, onDismiss: onSheetClosed) { r in
                OrgMoveSheetView(moveId: r.moveId)
                    .appStores()
            }
            .confirmationDialog(cancelTitle, isPresented: cancelShown, titleVisibility: .visible, presenting: cancel) { r in
                cancelButtons(r)
            } message: { r in
                Text(r.ask.message)
            }
    }

    private var cancelTitle: String {
        cancel?.ask.title ?? ""
    }

    private var cancelShown: Binding<Bool> {
        Binding(get: { cancel != nil }, set: { if !$0 { cancel = nil } })
    }

    @ViewBuilder
    private func cancelButtons(_ r: OrgMoveWizCancelRequest) -> some View {
        if let c = r.ask.confirmLabel {
            Button(c, role: .destructive) { onCancel(r.moveId, false) }
        }
        if let t = r.ask.takeBackLabel {
            Button(t, role: .destructive) { onCancel(r.moveId, true) }
        }
        if let k = r.ask.keepLabel {
            Button(k) { onCancel(r.moveId, false) }
        }
        Button("不要取消", role: .cancel) {}
    }
}

/// 第 ③ 步「什麼時候做」的一顆（〔現在就交接，11/1 才改部門〕〔11/1 一起做〕；選中的藍色實心圓）
struct OrgMoveWizTimingRow: View {
    let label: String
    let on: Bool
    let action: () -> Void

    init(label: String, on: Bool, action: @escaping () -> Void) {
        self.label = label
        self.on = on
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(on ? Color.blue : Color.secondary)
                Text(label)
                    .font(.subheadline.weight(on ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var fill: Color {
        on ? Color.blue.opacity(0.1) : Color(.tertiarySystemFill)
    }
}

/// 第 ② 步〔＋ 自己加一項〕（門禁卡、鑰匙、帳號…只記在交接單上；按了開 OrgMoveCustomLineEditor）
struct OrgMoveWizAddCustomButton: View {
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Label("自己加一項", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text("門禁卡、鑰匙、帳號…只記在交接單上，不動任何資料")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
