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
// [手錶 v4] v25.580（watch/judge.md §2.15、§2.11「語音」；watch/build/v4/brief.md G3-3）：
//   • ① 遮住金額下面：「每公里講一句（跑步）」「每公里震一下（跑步）」兩個開關＝WorkoutManager.voiceOn／hapticOn
//     （跑步中控制頁那兩顆小開關同一組；存在手錶 App Group：WatchRunPrefs）
//   • 最下面：「語音：中文（台灣）✓」／「這支手錶沒有台灣中文語音，每公里只震動」（琥珀）＋手錶上找得到的中文嗓音
//     （WatchRunVoice.chineseVoiceNames，「美佳（zh-TW）、婷婷（zh-CN）…」；你截圖給我）。打開設定時查一次，不在每次重畫都查
// [手錶 v7a] v25.585（watch/judge.md §2.15、§8 v7a；watch/build/v7a/brief.md §1-1、G2-2）：
//   • ⓪ 第一段多一行「說一句還沒送到 iPhone：N 句」（VoiceOutboxRule.unsentLine，琥珀）；記一筆、說一句兩種都 0 才整段不出現。
//     〔現在送〕兩種都補送（RecordOutbox.resendUnconfirmed＋VoiceOutbox.resendUnconfirmed；iPhone 用編號擋重複）
//   • ① 遮住金額下面：「記帳台第 4 格：🎤 說一句」開關（WatchVoiceSettings，手錶 App Group，沒設定過＝開）；
//     關掉＝第 4 格照 v2 放常記的那一筆（跟 WatchVoiceText.blockedFooter 的「手錶設定 › 記帳台第 4 格」對得上）
//   • 這幾行一樣沒有金額、人名、你講的原文（只有句數），手腕放下不用換字

struct SettingsSheet: View {
    @ObservedObject private var model = WatchModel.shared
    /// [v2] 待送盒（第一行「還沒送到 iPhone：N 筆」）
    @ObservedObject private var outbox = RecordOutbox.shared
    /// [v4] 每公里講一句／震一下（跑步）
    @ObservedObject private var runs = WorkoutManager.shared
    /// [v4] 最下面那一段：打開設定時查一次手錶上的嗓音（nil＝還沒查，那一段先不畫）
    @State private var voices: SettingsVoiceInfo?
    /// [v7a] 說一句的待送盒（第一段「說一句還沒送到 iPhone：N 句」）。`voices` 已經是 v4 的嗓音那一段，這裡叫 voiceOutbox
    @ObservedObject private var voiceOutbox = VoiceOutbox.shared
    /// [v7a] 記帳台第 4 格放說一句（打開設定時讀一次；改了馬上寫回手錶 App Group）
    @State private var voiceTile = WatchVoiceSettings.tileOn

    static let hideNote = "只在這支手錶；手腕放下時一律會遮"
    static let noPackageText = "還沒收到 iPhone 的資料"
    static let askingText = "正在跟 iPhone 要…"
    static let askFailedText = "iPhone 不在旁邊，或 LifeGood 沒打開"
    static let refreshTitle = "現在更新"
    static let resendTitle = "現在送"
    static let outboxNote = "換手錶、清除手錶內容之前，先等這一行消失（還沒送到的會跟著不見）"
    /// [v4] 手錶上一個中文嗓音都沒有
    static let noVoices = "這支手錶找不到中文語音"
    /// [v4] 嗓音清單的分隔
    static let voiceSeparator = "、"
    /// [v7a] 記帳台第 4 格那個開關
    static let voiceTileTitle = "記帳台第 4 格：🎤 說一句"
    static let voiceTileOn = "講一句就記好（要 iPhone 有訂閱、設好 AI）"
    static let voiceTileOff = "關掉：第 4 格放常記的那一筆"

    var body: some View {
        NavigationStack {
            List {
                outboxSection
                hideSection
                voiceTileSection
                runSection
                phoneSection
                aboutSection
                voiceSection
            }
            .navigationTitle("設定")
            .onAppear { outbox.reload() }
            .onAppear { voiceOutbox.reload() }
            .onAppear { loadVoices() }
        }
    }

    // MARK: ⓪ [v2] 還沒送到 iPhone：N 筆〔現在送〕（[v7a] 多「說一句還沒送到 iPhone：N 句」）

    /// [v2]「還沒送到 iPhone：N 筆」；0 筆 nil
    private var recordUnsentLine: String? {
        RecordText.unsentLine(outbox.items)
    }

    /// [v7a]「說一句還沒送到 iPhone：N 句」；0 句 nil
    private var voiceUnsentLine: String? {
        VoiceOutboxRule.unsentLine(voiceOutbox.items)
    }

    /// 記一筆、說一句兩種都 0（兩行都是 nil）整段不出現
    private var hasUnsent: Bool {
        recordUnsentLine != nil || voiceUnsentLine != nil
    }

    @ViewBuilder
    private var outboxSection: some View {
        if hasUnsent {
            Section {
                if let line = recordUnsentLine {
                    SettingsTwoLine(title: line, note: nil, noteIsAmber: false, titleIsAmber: true)
                }
                if let line = voiceUnsentLine {
                    SettingsTwoLine(title: line, note: nil, noteIsAmber: false, titleIsAmber: true)
                }
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
            // 記一筆、說一句兩種都補送（還在系統排隊裡的不再送；iPhone 用編號擋重複）
            outbox.resendUnconfirmed()
            voiceOutbox.resendUnconfirmed()
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

    // MARK: [v7a] 記帳台第 4 格：🎤 說一句

    /// 開：「講一句就記好（要 iPhone 有訂閱、設好 AI）」；關：「關掉：第 4 格放常記的那一筆」
    private var voiceTileNote: String {
        voiceTile ? Self.voiceTileOn : Self.voiceTileOff
    }

    private var voiceTileSection: some View {
        Section {
            Toggle(isOn: $voiceTile) {
                SettingsTwoLine(title: Self.voiceTileTitle, note: voiceTileNote, noteIsAmber: false)
            }
            .onChange(of: voiceTile) { _, on in
                WatchVoiceSettings.setTileOn(on)
            }
        }
    }

    // MARK: [v4] 每公里講一句／震一下（跑步）

    private var voiceBinding: Binding<Bool> {
        Binding(get: { runs.voiceOn },
                set: { on in runs.setVoiceOn(on) })
    }

    private var hapticBinding: Binding<Bool> {
        Binding(get: { runs.hapticOn },
                set: { on in runs.setHapticOn(on) })
    }

    private var runSection: some View {
        Section {
            Toggle(isOn: voiceBinding) {
                SettingsTwoLine(title: WatchRunText.voiceRow, note: nil, noteIsAmber: false)
            }
            Toggle(isOn: hapticBinding) {
                SettingsTwoLine(title: WatchRunText.hapticRow, note: nil, noteIsAmber: false)
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

    // MARK: [v4] 最下面：語音、手錶上的中文嗓音

    /// 「語音：中文（台灣）✓」／「這支手錶沒有台灣中文語音，每公里只震動」（琥珀）；footer 列出中文嗓音
    @ViewBuilder
    private var voiceSection: some View {
        if let info = voices {
            Section {
                SettingsTwoLine(title: info.status, note: nil, noteIsAmber: false, titleIsAmber: !info.hasTaiwan)
            } footer: {
                Text(info.names)
                    .font(.footnote)
                    .foregroundStyle(WatchStyle.small)
            }
        }
    }

    /// 查一次：有沒有台灣中文嗓音、手錶上的中文嗓音（speechVoices() 不便宜，不放在每次重畫）
    private func loadVoices() {
        let hasTaiwan = WatchRunVoice.hasTaiwanVoice
        let names = WatchRunVoice.chineseVoiceNames()
        voices = SettingsVoiceInfo(hasTaiwan: hasTaiwan,
                                   status: hasTaiwan ? WatchRunText.voiceReady : WatchRunText.voiceMissing,
                                   names: names.isEmpty ? Self.noVoices : names.joined(separator: Self.voiceSeparator))
    }
}

/// [v4] 設定最下面那一段的字（打開設定時查一次）
private struct SettingsVoiceInfo: Equatable {
    /// 有台灣中文嗓音（沒有：標題琥珀）
    let hasTaiwan: Bool
    /// 「語音：中文（台灣）✓」／「這支手錶沒有台灣中文語音，每公里只震動」
    let status: String
    /// 「美佳（zh-TW）、婷婷（zh-CN）」；一個都沒有「這支手錶找不到中文語音」
    let names: String
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
