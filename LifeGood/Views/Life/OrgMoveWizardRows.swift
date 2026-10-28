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
