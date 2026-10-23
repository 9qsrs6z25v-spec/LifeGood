import SwiftUI

// MARK: - 自己打數字（手錶 v2，v25.576；watch/judge.md §2.6「數字鍵」、§4.2 第 3 步；watch/build/v2/brief.md G3-3）
//
// 只屬於 LifeGoodWatch。金額頁〔⌨︎〕整頁換成這個（AmountPicker.showPad）：
//   上面一行：打了的數字（RecordText 組好的金額字）＋右邊〔⌫〕
//   下面 3×4：1 2 3／4 5 6／7 8 9／「00」0 ✓
// 取捨（brief G3-3）：judge 寫「0～9、⌫、00」3×4，加上確定鍵放不下 → ⌫ 移到顯示那一行右邊、第 12 鍵是 ✓。
// 一打開什麼都還沒打（value＝0）：上面那一行灰灰地寫原本的金額；一按數字就從頭打（打 1、2、0、0 → 1,200），
//   ✓ 沒打任何數字（或刪光）＝照原本的金額。最多 6 位數（RecordText.maxAmount，padAppend 擋）；開頭的 0 不算。
// 每一列平分剩下的高度，最高 46mm 40／41mm 以下 34（40mm 螢幕矮，跟著縮）。手腕放下能按的變暗、暫時不能按。
// 手腕放下（或系統要遮）：上面那一行「NT$ ••••」（judge §2.17「記一筆：金額 → •••」；版面不動）。
//
// [手錶 v6，v25.578] 旅途中外幣（judge §2.14；watch/build/v6/brief.md G2-4）：currency 有值時打的是原幣——
//   上面那一行「₩18,000」（WatchTripText.foreignText）、遮住「₩ ••••」（WatchTripText.foreignMask）；最多 6 位數照舊
//   （WatchTripText.maxForeignAmount＝RecordText.maxAmount＝999,999）。換成台幣在金額頁（AmountPicker 的「≈ NT$」那一行），這裡不算。

struct DigitPad: View {
    let initial: Int
    /// [v6] 旅途中外幣（nil＝台幣）
    let currency: WatchCurrency?
    let onDone: (Int) -> Void

    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.redactionReasons) private var reasons
    /// 打了的數字；0＝還沒打（顯示原本的金額）
    @State private var value: Int

    static let doubleZero = "00"
    static let backspaceLabel = "刪掉一位"
    static let doneLabel = "好了"
    static let spacing: CGFloat = 4
    static let displayHeight: CGFloat = 30
    static let dimmedOpacity: Double = 0.75

    init(initial: Int, currency: WatchCurrency? = nil, onDone: @escaping (Int) -> Void) {
        self.initial = initial
        self.currency = currency
        self.onDone = onDone
        _value = State(initialValue: 0)
    }

    var body: some View {
        VStack(spacing: Self.spacing) {
            displayRow
            digitRow([1, 2, 3])
            digitRow([4, 5, 6])
            digitRow([7, 8, 9])
            lastRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 2)
        .opacity(dimmed ? Self.dimmedOpacity : 1)
    }

    /// 每一列最高（46mm 40、41mm 以下 34）
    private var rowMaxHeight: CGFloat {
        WatchStyle.isCompact ? 34 : 40
    }

    /// 上面那一行顯示的金額：打了就是打的；還沒打是原本的（灰）
    private var shownValue: Int {
        value > 0 ? value : initial
    }

    /// 「NT$1,200」；手腕放下、系統要遮「NT$ ••••」。[v6] 外幣「₩18,000」；遮住「₩ ••••」
    private var shownText: String {
        let hidden = dimmed || reasons.contains(.privacy)
        if let c = currency {
            return hidden ? WatchTripText.foreignMask(c) : WatchTripText.foreignText(shownValue, c)
        }
        return hidden ? WidgetHideAmounts.mask : RecordText.amountText(shownValue)
    }

    // MARK: 顯示＋⌫

    private var displayRow: some View {
        HStack(spacing: 4) {
            Text(shownText)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(value > 0 ? WatchStyle.primary : WatchStyle.small)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            backspaceButton
        }
        .frame(height: Self.displayHeight)
    }

    private var backspaceButton: some View {
        Button {
            value = RecordText.padBackspace(value)
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WatchStyle.primary)
                .frame(width: 40, height: Self.displayHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(value == 0 || dimmed)
        .accessibilityLabel(Text(Self.backspaceLabel))
    }

    // MARK: 鍵

    private func digitRow(_ digits: [Int]) -> some View {
        HStack(spacing: Self.spacing) {
            ForEach(digits, id: \.self) { d in
                digitKey(d)
            }
        }
        .frame(maxHeight: rowMaxHeight)
    }

    /// 最下面一列：「00」0 ✓
    private var lastRow: some View {
        HStack(spacing: Self.spacing) {
            textKey(Self.doubleZero) {
                value = RecordText.padAppendDoubleZero(value)
            }
            digitKey(0)
            doneKey
        }
        .frame(maxHeight: rowMaxHeight)
    }

    private func digitKey(_ d: Int) -> some View {
        textKey(String(d)) {
            value = RecordText.padAppend(value, digit: d)
        }
    }

    private func textKey(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(WatchStyle.primary)
        }
        .buttonStyle(DigitPadKeyStyle(fill: DigitPadLook.keyFill))
        .disabled(dimmed)
    }

    /// ✓：打了用打的；沒打（或刪光）用原本的
    private var doneKey: some View {
        Button {
            onDone(value > 0 ? value : initial)
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.black)
        }
        .buttonStyle(DigitPadKeyStyle(fill: WatchStyle.green))
        .disabled(dimmed)
        .accessibilityLabel(Text(Self.doneLabel))
    }
}

/// 這個檔的顏色
private enum DigitPadLook {
    static let keyFill = Color.white.opacity(0.16)
    static let cornerRadius: CGFloat = 10
}

/// 一顆鍵：填滿那一格、圓角底色、按下去變淡（手錶的 .plain 沒有按下的樣子；.bordered 有最小高度，40mm 四列放不下）
private struct DigitPadKeyStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(fill, in: RoundedRectangle(cornerRadius: DigitPadLook.cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DigitPadLook.cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
