import SwiftUI
import WatchKit

// MARK: - 記一筆的金額頁（手錶 v2，v25.576；watch/judge.md §2.6 第二步之二、§4.2、§7.8-15、§2.18；
//         評論 🔴4；watch/build/v2/brief.md G3-2）
//
// 只屬於 LifeGoodWatch。RecordSheet 推進來（RecordStep.amount）：
//   頁首「飲食・午餐」（setup.title）／大字「180」（一打開＝這個時段上次的金額）／「轉錶冠調金額」（前 3 次）／
//   最近 3 個金額膠囊（40mm 2 顆）／〔⌨︎〕自己打數字（DigitPad）＋〔記下來〕。
// 錶冠（judge §7.8-15、評論 🔴4）：digitalCrownRotation 只收浮點數 → 綁 Double（金額清單 RecordText.amountSteps 的第幾格，
//   0、5…200、210…2,000、2,100…10,000、10,500…100,000，共 481 格），那個 View 一定 .focusable()，
//   @FocusState 一打開就給焦點（還沒反應時點一下大字也會拿到焦點）。轉到哪一格＝RecordText.stepAmount（View 不算步距）。
//   膠囊、數字鍵設的金額不一定在格上（187）：先記下對到的那一格（lastIndex），錶冠沒真的轉就不會被蓋成 185。
// 金額 0（這個分類沒記過、也還沒轉）〔記下來〕不能按；手腕放下能按的變暗、暫時不能按。付款方式手錶上不選。
// 手腕放下（或系統要遮）：大字「NT$ ••••」、膠囊「•••」（judge §2.17「記一筆：金額 → •••」；版面不動）。
//   只看手腕放下／系統遮，不看「遮住金額」設定：抬手時要看得到自己正在調的數字。

struct AmountPicker: View {
    let setup: RecordAmountSetup
    let onRecord: (Int) -> Void

    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.redactionReasons) private var reasons
    /// 現在的金額（錶冠、膠囊、數字鍵都改它）
    @State private var amount: Int
    /// 錶冠轉的是金額清單的第幾格（digitalCrownRotation 只收浮點數）
    @State private var crownValue: Double
    /// 上一次對到的那一格
    @State private var lastIndex: Int
    /// ⌨︎ 自己打數字（整頁換成 DigitPad）
    @State private var showPad = false
    /// 「轉錶冠調金額」這一次要不要出現（前 RecordText.crownHintTimes 次）
    @State private var showsCrownHint = false
    @State private var hintCounted = false
    @FocusState private var crownFocused: Bool

    static let recordTitle = "記下來"
    static let padLabel = "自己打數字"
    static let capsuleHeight: CGFloat = 32
    static let padButtonSize: CGFloat = 44
    /// 40mm（寬 162 點）以下：膠囊只放 2 顆（judge §2.18）
    static let narrowWidth: CGFloat = 170
    /// 推進來之後補給一次焦點（onAppear 當下有時還收不到）
    static let focusDelayNanos: UInt64 = 300_000_000
    static let dimmedOpacity: Double = 0.75

    init(setup: RecordAmountSetup, onRecord: @escaping (Int) -> Void) {
        self.setup = setup
        self.onRecord = onRecord
        let idx = RecordText.stepIndex(for: setup.initialAmount)
        _amount = State(initialValue: setup.initialAmount)
        _crownValue = State(initialValue: Double(idx))
        _lastIndex = State(initialValue: idx)
    }

    var body: some View {
        page
            .navigationTitle(setup.title)
    }

    @ViewBuilder
    private var page: some View {
        if showPad {
            DigitPad(initial: amount) { value in
                padDone(value)
            }
        } else {
            mainView
        }
    }

    // MARK: 主畫面

    private var mainView: some View {
        VStack(alignment: .leading, spacing: 6) {
            amountLabel
            hintLabel
            capsuleRow
            Spacer(minLength: 0)
            bottomRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scenePadding(.horizontal)
        .onAppear {
            mainAppeared()
        }
        .task {
            await focusCrownSoon()
        }
    }

    /// 手腕放下、系統要遮：金額換掉（judge §2.17）
    private var masked: Bool {
        dimmed || reasons.contains(.privacy)
    }

    /// 「NT$ 180」；遮住「NT$ ••••」
    private var amountString: String {
        masked ? WidgetHideAmounts.mask : "NT$ " + RecordText.grouped(amount)
    }

    /// 大字「180」（46mm 38／41mm 34 rounded 等寬）；錶冠綁在這裡
    private var amountLabel: some View {
        Text(amountString)
            .font(WatchStyle.heroFont(compact: WatchStyle.isCompact))
            .monospacedDigit()
            .foregroundStyle(WatchStyle.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(dimmed ? Self.dimmedOpacity : 1)
            .focusable()
            .focused($crownFocused)
            .digitalCrownRotation($crownValue, from: 0, through: Double(RecordText.amountSteps.count - 1), by: 1,
                                  sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
            .onChange(of: crownValue) { _, value in
                crownMoved(value)
            }
    }

    /// 「轉錶冠調金額」（Footnote A3B2D9；前 3 次）
    @ViewBuilder
    private var hintLabel: some View {
        if showsCrownHint {
            Text(RecordText.crownHint)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: 最近的金額

    @ViewBuilder
    private var capsuleRow: some View {
        if !shownRecent.isEmpty {
            HStack(spacing: 5) {
                ForEach(shownRecent, id: \.self) { n in
                    capsuleButton(n)
                }
            }
        }
    }

    /// 這個分類最近 3 個不同金額（RecordText 組好、新到舊）；40mm 只放 2 顆
    private var shownRecent: [Int] {
        let narrow = WKInterfaceDevice.current().screenBounds.width < Self.narrowWidth
        return Array(setup.recent.prefix(narrow ? 2 : 3))
    }

    private func capsuleButton(_ n: Int) -> some View {
        Button {
            setAmount(n)
            // 點了按鈕焦點可能被拿走：還給大字，錶冠接著轉
            crownFocused = true
        } label: {
            AmountCapsuleLabel(text: masked ? RecordText.tileMask : RecordText.grouped(n), selected: n == amount)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
        .opacity(dimmed ? Self.dimmedOpacity : 1)
    }

    // MARK: 底列

    private var bottomRow: some View {
        HStack(spacing: 6) {
            padButton
            recordButton
        }
    }

    /// 〔⌨︎〕自己打數字
    private var padButton: some View {
        Button {
            showPad = true
        } label: {
            Image(systemName: "keyboard")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WatchStyle.primary)
                .frame(width: Self.padButtonSize, height: Self.padButtonSize)
                .background(AmountLook.capsuleFill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
        .opacity(dimmed ? Self.dimmedOpacity : 1)
        .accessibilityLabel(Text(Self.padLabel))
    }

    /// 〔記下來〕（金額 0、手腕放下時不能按）
    private var recordButton: some View {
        Button {
            onRecord(amount)
        } label: {
            Text(Self.recordTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(WatchStyle.green)
        .disabled(amount <= 0 || dimmed)
    }

    // MARK: 改金額

    /// 錶冠轉了：真的換一格才改金額
    private func crownMoved(_ value: Double) {
        guard value.isFinite else { return }
        let i = Int(value.rounded())
        guard i != lastIndex else { return }
        lastIndex = i
        amount = RecordText.stepAmount(at: i)
    }

    /// 膠囊、數字鍵：金額照設，錶冠對到「≤ 它」的那一格（先設 lastIndex，onChange 不會把 187 蓋成 185）
    private func setAmount(_ value: Int) {
        amount = value
        let i = RecordText.stepIndex(for: value)
        lastIndex = i
        crownValue = Double(i)
    }

    private func padDone(_ value: Int) {
        setAmount(value)
        showPad = false
    }

    // MARK: 焦點、提示

    private func mainAppeared() {
        crownFocused = true
        guard !hintCounted else { return }
        hintCounted = true
        let defaults = WidgetShared.defaults
        let shown = defaults?.integer(forKey: RecordText.crownHintKey) ?? 0
        guard shown < RecordText.crownHintTimes else { return }
        showsCrownHint = true
        defaults?.set(shown + 1, forKey: RecordText.crownHintKey)
    }

    private func focusCrownSoon() async {
        try? await Task.sleep(nanoseconds: Self.focusDelayNanos)
        guard !Task.isCancelled, !showPad else { return }
        crownFocused = true
    }
}

/// 這個檔的顏色
private enum AmountLook {
    static let capsuleFill = Color.white.opacity(0.16)
}

/// 最近金額的一顆膠囊（選中的綠框）
private struct AmountCapsuleLabel: View {
    /// 「1,200」（RecordText.grouped）
    let text: String
    let selected: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(WatchStyle.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: AmountPicker.capsuleHeight)
            .background(AmountLook.capsuleFill, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(selected ? WatchStyle.green : Color.clear, lineWidth: 2)
            }
            .contentShape(Capsule())
    }
}
