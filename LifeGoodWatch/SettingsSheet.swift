import SwiftUI

// MARK: - 手錶設定（① 左上「⋯」，彈出頁）（手錶 v1，v25.574；watch/judge.md §2.15；watch/build/v1/brief.md G2-6）
//
// 只屬於 LifeGoodWatch。RootView 的 sheet(item: model.sheet) 開（WatchSheet.settings）；手錶的彈出頁系統自己會畫關閉鈕。
// 這幾列（「每公里講一句／震一下」v4 才加）：
//   ⓪ [v2] 「還沒送到 iPhone：N 筆」〔現在送〕（judge §2.15 第一行、評論 🟠14；brief G2-2）：0 筆整段不出現；
//      標題琥珀色（換手錶、清除手錶內容之前要看得到）；〔現在送〕＝RecordOutbox.resendUnconfirmed
//      （還在 10 秒內的、送出了但系統排隊裡已經沒有、iPhone 也還沒確認的再送一次；iPhone 用編號擋重複）
//   ① 遮住金額（只存在這支手錶的 App Group：WatchHideAmounts；切換後 WatchModel 馬上 reloadAllTimelines，錶面跟著遮／露）
//   ② 「iPhone 14:02 更新」〔現在更新〕（sendMessage 跟 iPhone 要一份；查問題先看這一行，judge §7.8-13）
//   ③ 錶面那一句（WatchText.faceNote，iPhone 設定頁也寫同一句）
//   ④ 版號（WatchBuildInfo.versionLine）
// 這一頁沒有金額、人名，手腕放下不用換字。字一律是常數或 WatchText／WidgetDateText 組好的，不在 Text 裡串。

struct SettingsSheet: View {
    @ObservedObject private var model = WatchModel.shared
    /// [v2] 待送盒（第一行「還沒送到 iPhone：N 筆」）
    @ObservedObject private var outbox = RecordOutbox.shared

    static let hideNote = "只在這支手錶；手腕放下時一律會遮"
    static let noPackageText = "還沒收到 iPhone 的資料"
    static let askingText = "正在跟 iPhone 要…"
    static let askFailedText = "iPhone 不在旁邊，或 LifeGood 沒打開"
    static let refreshTitle = "現在更新"
    static let resendTitle = "現在送"
    static let outboxNote = "換手錶、清除手錶內容之前，先等這一行消失（還沒送到的會跟著不見）"

    var body: some View {
        NavigationStack {
            List {
                outboxSection
                hideSection
                phoneSection
                aboutSection
            }
            .navigationTitle("設定")
            .onAppear { outbox.reload() }
        }
    }

    // MARK: ⓪ [v2] 還沒送到 iPhone：N 筆〔現在送〕

    /// 0 筆（RecordText.unsentLine 回 nil）整段不出現
    @ViewBuilder
    private var outboxSection: some View {
        if let line = RecordText.unsentLine(outbox.items) {
            Section {
                SettingsTwoLine(title: line, note: nil, noteIsAmber: false, titleIsAmber: true)
                resendButton
            } footer: {
                Text(Self.outboxNote)
                    .font(.footnote)
                    .foregroundStyle(WatchStyle.small)
            }
        }
    }

    private var resendButton: some View {
        Button {
            outbox.resendUnconfirmed()
        } label: {
            Label(Self.resendTitle, systemImage: "arrow.up.circle")
        }
    }

    // MARK: ① 遮住金額

    private var hideBinding: Binding<Bool> {
        Binding(get: { model.watchHidesAmounts },
                set: { on in model.setWatchHidesAmounts(on) })
    }

    private var hideSection: some View {
        Section {
            Toggle(isOn: hideBinding) {
                SettingsTwoLine(title: "遮住金額", note: Self.hideNote, noteIsAmber: false)
            }
        }
    }

    // MARK: ② iPhone 幾點更新〔現在更新〕

    /// 「iPhone 14:02 更新」（不是今天：「iPhone 10/21 22:10 更新」）；還沒收過「還沒收到 iPhone 的資料」
    private var receivedText: String {
        guard let t = model.lastReceivedAt else { return Self.noPackageText }
        return "iPhone " + WidgetDateText.updatedAt(t, now: Date())
    }

    /// 第二行：正在要／上次沒要到；都不是就不寫
    private var askNote: String? {
        if model.asking { return Self.askingText }
        if model.askFailed { return Self.askFailedText }
        return nil
    }

    private var phoneSection: some View {
        Section {
            SettingsTwoLine(title: receivedText, note: askNote, noteIsAmber: model.askFailed && !model.asking)
            refreshButton
        } footer: {
            Text(WatchText.faceNote)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
        }
    }

    private var refreshButton: some View {
        Button {
            model.requestFromPhone()
        } label: {
            Label(Self.refreshTitle, systemImage: "arrow.clockwise")
        }
        .disabled(model.asking)
    }

    // MARK: ④ 版號

    @ViewBuilder
    private var aboutSection: some View {
        if !WatchBuildInfo.versionLine.isEmpty {
            Section {
                Text(WatchBuildInfo.versionLine)
                    .font(.footnote)
                    .foregroundStyle(WatchStyle.small)
                    .listRowBackground(Color.clear)
            }
        }
    }
}

/// 設定頁的一列：第一行字＋（有的話）第二行小字。小字琥珀＝上次沒要到；標題琥珀＝[v2] 還沒送到 iPhone
private struct SettingsTwoLine: View {
    let title: String
    let note: String?
    let noteIsAmber: Bool
    /// [v2] 第一行用琥珀色（「還沒送到 iPhone：N 筆」）；v1 的呼叫不用帶
    var titleIsAmber: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
                .foregroundStyle(titleColor)
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(noteColor)
            }
        }
    }

    private var noteColor: Color {
        noteIsAmber ? WatchStyle.amber : WatchStyle.small
    }

    private var titleColor: Color {
        titleIsAmber ? WatchStyle.amber : Color.primary
    }
}
