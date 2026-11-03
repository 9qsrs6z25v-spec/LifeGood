import SwiftUI
import WatchKit

// MARK: - 說一句的畫面（手錶 v7a，v25.585；watch/judge.md §2.6、§2.17、§4.1「說一句」、§6.1；watch/build/v7a/brief.md G3-2）
//
// 只屬於 LifeGoodWatch。骨架（主控）：型別名、參數＝契約（RecordSheet 在叫），G3 填畫面；名字、參數不准改。
//   • VoiceTile：記帳台第 4 格「🎤 說一句」。能用＝TextFieldLink（系統聽寫；watchOS 9 起）→ onSubmit(那一句)；
//     不能用（包的 voiceReady 不是 true）＝一般按鈕 → onBlocked（RecordSheet 推「說一句」那一頁寫為什麼）
//   • VoiceDoneView：講完那一頁（「🎤 說一句」／你講的那一句（手腕放下不畫）／送到哪了或結果／〔完成〕）
//   • VoiceInfoView：不能用時那一頁（WatchVoiceText.blockedReason＋blockedFooter）
//   • VoiceDeskLineView：記帳台最下面那一行（VoiceOutboxRule.deskLine；點了＝看過了）
// 字一律拿 WatchVoiceText／VoiceOutboxRule 的結果（View 不拼金額、不拼付款字）。
//
// [G3] 樣子照 RecordSheet.swift 的 RecordTileView／RecordDoneView（那邊的 RecordLook 是 private，這裡 VoiceLook 用一樣的數字）。
//   • 系統聽寫：TextFieldLink(prompt:label:onSubmit:)——點了打開系統的輸入畫面（按麥克風聽寫、也能手寫、鍵盤），
//     App 自己不碰麥克風，所以不用麥克風權限、不加說明字。onSubmit 是系統輸入畫面收起來之後才叫；寫待送盒 RecordSheet 放下一輪
//   • 手腕放下（dimmed）：能按的變暗不拿掉（.disabled(dimmed)）、字調暗、版面不跳；原文、站名照 hidesPersonal 換（RecordSheet 組好）
//   • 只 import SwiftUI、WatchKit（pbxwatch_check M、T 段）

/// 這個檔裡幾頁共用的樣子（跟 RecordSheet.swift 的 RecordLook 一樣的數字）
private enum VoiceLook {
    static let cornerRadius: CGFloat = 12
    static let tileFill = Color.white.opacity(0.14)
    /// 手腕放下時能按的變暗（judge §2.17）
    static let dimmedTileOpacity: Double = 0.5
    static let dimmedOpacity: Double = 0.75
    /// 說一句的紫（WatchVoiceText.tileTint，iPhone 說一句同一個色）
    static let tint = Color(watchHex: WatchVoiceText.tileTint)
    /// 狀態下面那一行小字（同 RecordDoneView 的 A3B2D9）
    static let note = Color(watchHex: 0xA3B2D9)
}

/// 「說一句」那一頁要的（RecordSheet 的 @State；原文只在記憶體）
struct VoiceDoneInfo: Equatable {
    /// 這一句的編號（VoiceOutbox.status(of:)）
    let id: UUID
    /// 你講的那一句（去頭尾空白；手腕放下、沒解鎖不畫）
    let text: String
    /// 旅途中記到哪（「記到 弘大」；不在旅途中 nil）
    let target: WatchTripRecordTarget?
}

// MARK: - 記帳台第 4 格

/// 記帳台第 4 格「🎤 說一句」（樣子跟 RecordTileView 一樣：91×58／41mm 以下 50）
struct VoiceTile: View {
    let tile: RecordDeskTile
    /// 包的 voiceReady == true
    let ready: Bool
    let dimmed: Bool
    let compact: Bool
    /// 系統聽寫打好、按了完成（字還沒去空白）
    let onSubmit: (String) -> Void
    /// 不能用時點了
    let onBlocked: () -> Void

    var body: some View {
        if ready {
            readyLink
        } else {
            blockedButton
        }
    }

    /// 能用：點了直接打開系統輸入畫面（watchOS 9 起；三個參數都寫標籤）
    private var readyLink: some View {
        TextFieldLink(prompt: Text(WatchVoiceText.prompt), label: {
            VoiceTileLabel(tile: tile, locked: false, compact: compact)
        }, onSubmit: { text in
            onSubmit(text)
        })
        .buttonStyle(.plain)
        .disabled(dimmed)
        .opacity(dimmed ? VoiceLook.dimmedTileOpacity : 1)
    }

    /// 不能用（沒訂閱、沒設 AI、iPhone 還沒更新）：格子照畫、右上 🔒，點了推「說一句」那一頁寫為什麼
    private var blockedButton: some View {
        Button {
            onBlocked()
        } label: {
            VoiceTileLabel(tile: tile, locked: true, compact: compact)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
        .opacity(dimmed ? VoiceLook.dimmedTileOpacity : 1)
    }
}

/// 第 4 格的樣子：左上 🎤（紫）、右上能用 waveform（紫）／不能用 🔒（琥珀）、下面「說一句」一行；能用時紫色細框
private struct VoiceTileLabel: View {
    let tile: RecordDeskTile
    /// 不能用：右上 🔒、沒有紫框
    let locked: Bool
    let compact: Bool

    var body: some View {
        content
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: compact ? 50 : 58)
            .background(VoiceLook.tileFill, in: tileShape)
            .overlay {
                border
            }
            .contentShape(tileShape)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            Spacer(minLength: 0)
            titleText
        }
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: VoiceLook.cornerRadius, style: .continuous)
    }

    private var topRow: some View {
        HStack(alignment: .center, spacing: 2) {
            iconView
            Spacer(minLength: 2)
            badgeView
        }
    }

    private var iconView: some View {
        Image(systemName: tile.icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color(watchHex: tile.tint))
    }

    private var badgeView: some View {
        Image(systemName: locked ? "lock.fill" : "waveform")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        locked ? WatchStyle.amber : Color(watchHex: tile.tint)
    }

    private var titleText: some View {
        Text(tile.title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(WatchStyle.primary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var border: some View {
        tileShape
            .strokeBorder(borderColor, lineWidth: 1)
    }

    private var borderColor: Color {
        locked ? Color.clear : Color(watchHex: tile.tint, opacity: 0.6)
    }
}

// MARK: - 講完那一頁

/// 講完那一頁：①「🎤 說一句」②「「你講的那一句」」（手腕放下、沒解鎖換一行字）③（旅途中）「記到 弘大」
/// ④ 送到哪了／結果（Title3 20 semibold；記好了綠、還沒送到或沒記成琥珀）⑤ 小字 ⑥〔完成〕
struct VoiceDoneView: View {
    let info: VoiceDoneInfo
    /// VoiceOutbox.status(of:)；手錶上已經沒有這一句（被刪了）是 nil
    let status: WatchVoiceStatus?
    /// 金額遮不遮（WatchPrivacy.masksAmounts）
    let masked: Bool
    /// 原文、站名要不要換（WatchPrivacy.hidesPersonal：手腕放下、沒解鎖）
    let hidesPersonal: Bool
    let dimmed: Bool
    /// 〔完成〕
    let onDone: () -> Void

    static let finishTitle = "完成"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                titleLabel
                quoteText
                targetText
                statusRow
                noteText
                finishButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scenePadding(.horizontal)
        }
    }

    private var dimOpacity: Double {
        dimmed ? VoiceLook.dimmedOpacity : 1
    }

    /// 「🎤 說一句」（Headline 紫）
    private var titleLabel: some View {
        Label(WatchVoiceText.pageTitle, systemImage: "mic.fill")
            .font(.headline)
            .foregroundStyle(VoiceLook.tint)
            .opacity(dimOpacity)
    }

    /// 你講的那一句：只在抬手、解鎖時畫（judge §6.1「講完那一下看得到」）；不然換「你說的那一句（抬手才看得到）」
    @ViewBuilder
    private var quoteText: some View {
        if hidesPersonal {
            Text(WatchVoiceText.quoteHidden)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(dimOpacity)
        } else {
            Text(WatchVoiceText.quoted(info.text))
                .font(.body)
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(dimOpacity)
        }
    }

    /// 旅途中「記到 弘大」（站名 RecordSheet 已經照這一刻的手腕放下換好：過夜那一站「住宿」）
    @ViewBuilder
    private var targetText: some View {
        if let t = info.target {
            Text(WatchTripText.targetLine(t))
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .opacity(dimOpacity)
        }
    }

    /// 送到哪了／結果（WatchVoiceText.statusLine；金額照 masked 遮起來，字是 WatchVoiceText 組好的）
    private var statusRow: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: statusIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(statusIconColor)
                .frame(width: 18)
                .padding(.top, 3)
            Text(statusText)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(statusColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(dimOpacity)
    }

    private var statusText: String {
        guard let s = status else { return WatchVoiceText.statusUnknown }
        return WatchVoiceText.statusLine(s, masked: masked)
    }

    /// 結果來了、而且記好了
    private var isRecorded: Bool {
        guard let s = status, case .done(let said) = s else { return false }
        return said.isRecorded
    }

    /// 還沒送到、沒記成
    private var isWarning: Bool {
        status?.isWarning ?? false
    }

    private var statusIcon: String {
        if isRecorded { return "checkmark.circle.fill" }
        if isWarning { return "exclamationmark.triangle.fill" }
        return "iphone"
    }

    private var statusColor: Color {
        if isRecorded { return WatchStyle.green }
        if isWarning { return WatchStyle.amber }
        return WatchStyle.primary
    }

    private var statusIconColor: Color {
        if isRecorded { return WatchStyle.green }
        if isWarning { return WatchStyle.amber }
        return WatchStyle.small
    }

    /// 「錶面的「已花」幾分鐘內跟上」「這一句沒有記帳」…（WatchVoiceText.statusNote；沒有不畫）
    @ViewBuilder
    private var noteText: some View {
        if let s = status, let note = WatchVoiceText.statusNote(s) {
            Text(note)
                .font(.footnote)
                .foregroundStyle(VoiceLook.note)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(dimOpacity)
        }
    }

    /// 〔完成〕：回 ② 錢（手腕放下變暗、不拿掉）
    private var finishButton: some View {
        Button {
            onDone()
        } label: {
            Text(Self.finishTitle)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(WatchStyle.green)
        .disabled(dimmed)
        .padding(.top, 2)
    }
}

// MARK: - 不能用那一頁

/// 不能用時那一頁：mic.slash（琥珀）、為什麼（Body）、怎麼先記／怎麼換回常記的那一筆（Footnote）。
/// 打開之後 iPhone 剛好好了（reason＝WatchVoiceText.nowReady）：圖示換紫色 🎤、不寫怎麼換回來
struct VoiceInfoView: View {
    /// WatchVoiceText.blockedReason(voiceReady:)
    let reason: String

    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                iconView
                reasonText
                footerText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scenePadding(.horizontal)
        }
    }

    private var isNowReady: Bool {
        reason == WatchVoiceText.nowReady
    }

    private var dimOpacity: Double {
        dimmed ? VoiceLook.dimmedOpacity : 1
    }

    private var iconView: some View {
        Image(systemName: isNowReady ? "mic.fill" : "mic.slash.fill")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(isNowReady ? VoiceLook.tint : WatchStyle.amber)
            .opacity(dimOpacity)
    }

    private var reasonText: some View {
        Text(reason)
            .font(.body)
            .foregroundStyle(WatchStyle.primary)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(dimOpacity)
    }

    @ViewBuilder
    private var footerText: some View {
        if !isNowReady {
            Text(WatchVoiceText.blockedFooter)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(dimOpacity)
        }
    }
}

// MARK: - 記帳台最下面那一行

/// 記帳台最下面那一行：「上一句・已記一筆：…」（沒記成琥珀）／「1 句在 iPhone 等著記」／「1 句還沒送到 iPhone」（琥珀）。
/// 結果那一種（line.id 有值）點了＝看過了（RecordSheet markSeen）；在等的、還沒送到的不能點（畫成一般的字，不畫成按不了的按鈕）
struct VoiceDeskLineView: View {
    let line: VoiceDeskLine
    let dimmed: Bool
    let onTap: () -> Void

    var body: some View {
        if line.id != nil {
            tapButton
        } else {
            lineContent
        }
    }

    private var tapButton: some View {
        Button {
            onTap()
        } label: {
            lineContent
        }
        .buttonStyle(.plain)
        .disabled(dimmed || line.id == nil)
    }

    private var lineContent: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VoiceLook.tint)
                .padding(.top, 2)
            lineText
        }
        .padding(.top, 2)
        .opacity(dimmed ? VoiceLook.dimmedOpacity : 1)
        .contentShape(Rectangle())
    }

    private var lineText: some View {
        Text(line.text)
            .font(.footnote)
            .foregroundStyle(textColor)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textColor: Color {
        line.isWarning ? WatchStyle.amber : WatchStyle.small
    }
}
