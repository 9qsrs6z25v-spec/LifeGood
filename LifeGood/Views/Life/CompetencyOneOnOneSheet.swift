import SwiftUI

// MARK: - [v25.607 職能雷達 v5b] 加到一對一議程（G2 負責；radar/judge_v5b.md §C2；radar/build/v5b/brief.md §4 G2）
//
// • 入口：〔職能〕分頁「…」〔加到一對一議程…〕（擋訂閱在分頁那邊；唯讀、已轉出、沒有一對一會議不出現）。sheet(item:)＋.appStores()。
// • 上面選「哪一場」：這位同仁的一對一（LifeStore.competencyOneOnOneChoices：有週期的列下一場「1on1（隔週）・11/14」、
//   不重複的列那一場）；預設第一個（最近的一場）。
// • 下面候選議程（request.candidates；分頁打開那一刻算好的：目標差距、跟帶訓者看法不一樣、超過 6 個月沒評的組）打勾，
//   預設勾前 3 個；同一場已經有一模一樣的內容：灰字「已經在議程裡」、不能勾（CompetencyMath.agendaRows／defaultAgendaPicks）。
// • 〔加入議程〕：dismiss 之後下一個 runloop 叫 LifeStore.addCompetencyAgendaItems（MeetingQuickAddItemSheet.save 同一個寫法；
//   沒有負責人、沒有到期日、備註空）；加了幾個用 onAdded 傳回分頁的小提示「已加 3 個議程到 11/14 的 1on1」。
// • 字只用分數與項目名，不寫評語（§13）。字不用「他／她」。通知、小工具、手錶、鎖定畫面、靈動島一個字都不加。
// 骨架（主控）：CompetencyOneOnOneRequest、CompetencyOneOnOneSheet(request:onAdded:) 是跨組契約（〔職能〕分頁在叫），不准改；
// body 由 G2 換成真的。自己加的型別一律 private、CompOne… 前綴。
// G2：換一場 → 照那一場重算預設勾選；〔加入議程〕要有一場、而且勾的裡面至少一個不是「已經在議程裡」才能按；議程不在這裡組 MeetingItem。
// 要退回這一件：這個檔連同 pbxproj 四處（A01A／A01B000001001651）拿掉，叫它的那幾行拿掉。

/// 打開〔加到一對一議程…〕（sheet(item:)；每次新的 id）。candidates＝分頁打開那一刻算好的（CompetencyMath.agendaCandidates）
struct CompetencyOneOnOneRequest: Identifiable {
    let id = UUID()
    let subordinateId: UUID
    let candidates: [CompetencyAgendaCandidate]
}

struct CompetencyOneOnOneSheet: View {
    let request: CompetencyOneOnOneRequest
    /// 加好了：小提示的字「已加 3 個議程到 11/14 的 1on1」（分頁 showToast）
    var onAdded: ((String) -> Void)? = nil

    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    /// 選的那一場（CompetencyOneOnOneChoice.id；空＝第一個）
    @State private var choiceId: String = ""
    /// 勾的候選議程（CompetencyAgendaRow.id）
    @State private var picks: Set<String> = []
    @State private var didInit = false

    init(request: CompetencyOneOnOneRequest, onAdded: ((String) -> Void)? = nil) {
        self.request = request
        self.onAdded = onAdded
    }

    /// 「哪一場」（第一個＝預設；body 只叫一次）
    private var choices: [CompetencyOneOnOneChoice] {
        lifeStore.competencyOneOnOneChoices(of: request.subordinateId)
    }

    /// 選的那一場；找不到（還沒初始化、那一場不在了）＝第一個
    private func current(_ list: [CompetencyOneOnOneChoice]) -> CompetencyOneOnOneChoice? {
        list.first(where: { $0.id == choiceId }) ?? list.first
    }

    var body: some View {
        let list: [CompetencyOneOnOneChoice] = choices
        let pick: CompetencyOneOnOneChoice? = current(list)
        let rows: [CompetencyAgendaRow] = CompetencyMath.agendaRows(request.candidates, choice: pick)
        let addable: Bool = canAdd(rows, pick)
        return NavigationStack {
            List {
                CompOneChoiceSection(list: list, choiceId: $choiceId)
                agendaSection(rows)
            }
            .navigationTitle("加到一對一議程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("加入議程") { save() }
                        .disabled(!addable)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            guard !didInit else { return }
            didInit = true
            choiceId = list.first?.id ?? ""
            picks = CompetencyMath.defaultAgendaPicks(rows)
        }
        .onChange(of: choiceId) { _, _ in
            resetPicks()
        }
    }

    /// 第二節「議程」：候選打勾（已經在議程裡的灰字、不能勾）
    @ViewBuilder
    private func agendaSection(_ rows: [CompetencyAgendaRow]) -> some View {
        Section {
            if rows.isEmpty {
                Text("現在沒有候選議程（目標都達到、跟帶訓者看法差不多、六個月內都評過）。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { r in
                    CompOneRow(row: r, picked: picks.contains(r.id), onToggle: { toggle(r) })
                }
            }
        } header: {
            Text("議程")
        } footer: {
            Text("議程只寫分數與項目名，不寫評語；沒有負責人、沒有到期日。加了以後在部屬卡片〔會議〕那一場看得到、可以改。")
        }
    }

    /// 有一場、而且勾的裡面至少一個不是「已經在議程裡」
    private func canAdd(_ rows: [CompetencyAgendaRow], _ pick: CompetencyOneOnOneChoice?) -> Bool {
        guard pick != nil else { return false }
        return rows.contains { picks.contains($0.id) && !$0.already }
    }

    /// 換一場：照那一場重算預設勾選
    private func resetPicks() {
        let rows: [CompetencyAgendaRow] = CompetencyMath.agendaRows(request.candidates, choice: current(choices))
        picks = CompetencyMath.defaultAgendaPicks(rows)
    }

    /// 勾／不勾（已經在議程裡的不動）
    private func toggle(_ r: CompetencyAgendaRow) {
        guard !r.already else { return }
        if picks.contains(r.id) {
            picks.remove(r.id)
        } else {
            picks.insert(r.id)
        }
    }

    /// 〔加入議程〕：dismiss 之後下一個 runloop 才寫（LifeStore.addCompetencyAgendaItems；寫的時候再比一次「已經有」）
    private func save() {
        let list: [CompetencyOneOnOneChoice] = choices
        guard let c = current(list) else { return }
        let rows: [CompetencyAgendaRow] = CompetencyMath.agendaRows(request.candidates, choice: c)
        let texts: [String] = rows.filter { picks.contains($0.id) && !$0.already }.map { $0.text }
        guard !texts.isEmpty else { return }
        let store = lifeStore
        let sid: UUID = request.subordinateId
        let today: String = CompetencyMath.dayKey(Date())
        let callback = onAdded
        dismiss()
        DispatchQueue.main.async {
            let n: Int = store.addCompetencyAgendaItems(subordinateId: sid, meetingId: c.meetingId,
                                                        scheduledDate: c.scheduledDate, contents: texts)
            if n > 0 { callback?(CompetencyMath.agendaAddedToast(n, choice: c, today: today)) }
        }
    }
}

/// 第一節「哪一場」：沒有之後的場次＝一行灰字；不然 Picker（要念得到，不 labelsHidden）
private struct CompOneChoiceSection: View {
    let list: [CompetencyOneOnOneChoice]
    @Binding var choiceId: String

    var body: some View {
        Section {
            if list.isEmpty {
                Text("這位同仁的一對一三個月內沒有之後的場次。到部屬卡片〔會議〕加一場再來。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker("哪一場", selection: $choiceId) {
                    ForEach(list) { c in
                        Text(c.title).tag(c.id)
                    }
                }
            }
        } header: {
            Text("哪一場")
        }
    }
}

/// 候選議程一列：打勾；已經在議程裡＝灰字、不能勾
private struct CompOneRow: View {
    let row: CompetencyAgendaRow
    let picked: Bool
    let onToggle: () -> Void

    private var iconName: String {
        if row.already { return "checkmark.circle" }
        return picked ? "checkmark.circle.fill" : "circle"
    }

    private var iconColor: Color {
        if row.already { return Color.secondary }
        return picked ? CompetencyPalette.trait : Color.secondary
    }

    private var kindText: String {
        switch row.kind {
        case "gap": return "目標差距"
        case "mentor": return "跟帶訓者看法不一樣"
        case "stale": return "該再評了"
        default: return ""
        }
    }

    private var kindLine: String {
        guard row.already else { return kindText }
        return kindText.isEmpty ? CompetencyMath.agendaAlreadyText : kindText + "・" + CompetencyMath.agendaAlreadyText
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                CompOneRowText(text: row.text, kindLine: kindLine, dimmed: row.already)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(row.already)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// 一列的字：議程內容＋小字種類（已經在議程裡多「・已經在議程裡」）
private struct CompOneRowText: View {
    let text: String
    let kindLine: String
    let dimmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(dimmed ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
            if !kindLine.isEmpty {
                Text(kindLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
