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
//
// [手錶 v6，v25.578] 旅途中（judge §2.14「旅途中記一筆自動變外幣」、§7.8-15；watch/build/v6/brief.md G2-3）：
//   • setup.currency 有值＝外幣：大字「₩18,000」（遮住「₩ ••••」）、下面一行「≈ NT$412（匯率）」（遮住「≈ NT$ ••••」，版面不動）、
//     錶冠一格照幣別（韓元 ₩1,000；一樣綁 Double 的格數，WatchTripText.foreignStep*）、膠囊「₩18,000」、數字鍵打原幣。
//     步距、換算、字一律拿 WatchTripText（View 不算）；〔記下來〕交回 RecordSheet 的是原幣整數，台幣由 RecordText.record 換。
//   • setup.target 有值＝旅途中：再下面一行「📍 記到 弘大 ›」，點了 onPickStop（RecordSheet 推「記到哪裡」）。
//   • 41mm 以下（WatchStyle.isCompact）旅途中多了兩行：不畫「轉錶冠調金額」（也不算一次）、膠囊只放 2 顆；不加 ScrollView
//     （錶冠綁在大字上）。外幣時 45mm 也不畫那一行提示（多了「≈ NT$」「記到」兩行，加上提示約 209 點會擠掉〔記下來〕）。
//     不在旅途中（currency、target 都 nil）跟 v2 一模一樣。

struct AmountPicker: View {
    let setup: RecordAmountSetup
    /// [v6] 旅途中「📍 記到 弘大 ›」點了（RecordSheet 推「記到哪裡」）；nil＝那一行沒有箭頭、點了不做事
    let onPickStop: (() -> Void)?
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
    /// [v6] 遮住時「≈ NT$」那一行
    static let approxMask = "≈ " + WidgetHideAmounts.mask

    /// v2 的 `AmountPicker(setup:) { … }` 照樣編得過（onPickStop 預設 nil）
    init(setup: RecordAmountSetup, onPickStop: (() -> Void)? = nil, onRecord: @escaping (Int) -> Void) {
        self.setup = setup
        self.onPickStop = onPickStop
        self.onRecord = onRecord
        // init 裡還不能叫 instance 方法：直接照幣別分（同 stepIndex(_:)）
        let idx = setup.currency.map { WatchTripText.foreignStepIndex(for: setup.initialAmount, $0) }
            ?? RecordText.stepIndex(for: setup.initialAmount)
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
            DigitPad(initial: amount, currency: setup.currency) { value in
                padDone(value)
            }
        } else {
            mainView
        }
    }

    // MARK: 主畫面

    private var mainView: some View {
        VStack(alignment: .leading, spacing: mainSpacing) {
            amountLabel
            approxLabel
            targetRow
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

    /// 「NT$ 180」；遮住「NT$ ••••」。[v6] 外幣「₩18,000」；遮住「₩ ••••」
    private var amountString: String {
        if let c = setup.currency {
            return masked ? WatchTripText.foreignMask(c) : WatchTripText.foreignText(amount, c)
        }
        return masked ? WidgetHideAmounts.mask : "NT$ " + RecordText.grouped(amount)
    }

    /// [v6] 41mm 以下的旅途中（多了「≈ NT$」「記到」兩行）：不畫「轉錶冠調金額」、膠囊只放 2 顆、行距 6 → 4
    private var tripCompact: Bool {
        setup.target != nil && WatchStyle.isCompact
    }

    /// 每一行之間（v2 6；41mm 以下的旅途中 4，40mm 也放得下〔記下來〕）
    private var mainSpacing: CGFloat {
        tripCompact ? 4 : 6
    }

    /// [v6] 這一頁不畫「轉錶冠調金額」（也不算一次）：41mm 以下的旅途中；外幣（多了「≈ NT$」「記到」兩行，
    /// 45mm 加上提示約 209 點、放不下〔記下來〕）。台幣、不在旅途中照 v2
    private var hidesCrownHint: Bool {
        tripCompact || setup.currency != nil
    }

    // MARK: 錶冠的格（View 不算步距：台幣 RecordText、外幣 WatchTripText）

    /// 錶冠有幾格（台幣 481；韓元 1,000）
    private var stepCount: Int {
        setup.currency.map { WatchTripText.foreignStepCount($0) } ?? RecordText.amountSteps.count
    }

    /// 第 i 格的金額（外幣是原幣）
    private func stepAmount(_ i: Int) -> Int {
        if let c = setup.currency {
            return WatchTripText.foreignStepAmount(at: i, c)
        }
        return RecordText.stepAmount(at: i)
    }

    /// 這個金額在第幾格（「≤ 它」的最後一格）
    private func stepIndex(_ v: Int) -> Int {
        if let c = setup.currency {
            return WatchTripText.foreignStepIndex(for: v, c)
        }
        return RecordText.stepIndex(for: v)
    }

    /// 錶冠的上限（格數 − 1；至少 0）
    private var crownMax: Double {
        Double(max(stepCount - 1, 0))
    }

    /// 錶冠綁在大字上。台幣照 v2（481 格）；[v6] 外幣的格數照幣別（韓元 1,000 格，WatchTripText.foreignStepCount）。
    /// 幣別換了 RecordSheet 用 .id 整頁重來，不會兩種格混在一起
    @ViewBuilder
    private var amountLabel: some View {
        if let c = setup.currency {
            amountText
                .digitalCrownRotation($crownValue, from: 0, through: Double(WatchTripText.foreignStepCount(c) - 1), by: 1,
                                      sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                .onChange(of: crownValue) { _, value in
                    crownMoved(value)
                }
        } else {
            amountText
                .digitalCrownRotation($crownValue, from: 0, through: Double(RecordText.amountSteps.count - 1), by: 1,
                                      sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                .onChange(of: crownValue) { _, value in
                    crownMoved(value)
                }
        }
    }

    /// 大字「180」（46mm 38／41mm 34 rounded 等寬）；[v6] 外幣「₩18,000」（字長，可縮到一半）
    private var amountText: some View {
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
    }

    /// [v6] 外幣：大字下面「≈ NT$412（匯率）」（WatchTripText.approxLine）；遮住「≈ NT$ ••••」（這一行不拿掉，版面不動）
    @ViewBuilder
    private var approxLabel: some View {
        if let c = setup.currency {
            Text(masked ? Self.approxMask : WatchTripText.approxLine(amount, c))
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .opacity(dimmed ? Self.dimmedOpacity : 1)
        }
    }

    /// [v6] 旅途中「📍 記到 弘大 ›」：點了換別站或整趟（手腕放下變暗、暫時不能按）
    @ViewBuilder
    private var targetRow: some View {
        if let t = setup.target {
            Button {
                onPickStop?()
            } label: {
                AmountTargetLabel(text: WatchTripText.targetLine(t), showsChevron: onPickStop != nil)
            }
            .buttonStyle(.plain)
            .disabled(dimmed)
            .opacity(dimmed ? Self.dimmedOpacity : 1)
        }
    }

    /// 「轉錶冠調金額」（Footnote A3B2D9；前 3 次）。[v6] 41mm 以下的旅途中、外幣時不畫（hidesCrownHint）
    @ViewBuilder
    private var hintLabel: some View {
        if showsCrownHint && !hidesCrownHint {
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

    /// 這個分類最近 3 個不同金額（RecordText 組好、新到舊）；40mm 只放 2 顆。[v6] 外幣是這趟最近記過的原幣；41mm 以下的旅途中 2 顆
    private var shownRecent: [Int] {
        let narrow = WKInterfaceDevice.current().screenBounds.width < Self.narrowWidth
        return Array(setup.recent.prefix((narrow || tripCompact) ? 2 : 3))
    }

    /// 膠囊的字：「1,200」；[v6] 外幣「₩18,000」；遮住「•••」
    private func capsuleText(_ n: Int) -> String {
        if let c = setup.currency {
            return masked ? RecordText.tileMask : WatchTripText.foreignText(n, c)
        }
        return masked ? RecordText.tileMask : RecordText.grouped(n)
    }

    private func capsuleButton(_ n: Int) -> some View {
        Button {
            setAmount(n)
            // 點了按鈕焦點可能被拿走：還給大字，錶冠接著轉
            crownFocused = true
        } label: {
            AmountCapsuleLabel(text: capsuleText(n), selected: n == amount)
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

    /// 錶冠轉了：真的換一格才改金額（先在 Double 上夾到 0…格數−1 再轉 Int：arm64_32 的 Int 只有 32 位）
    private func crownMoved(_ value: Double) {
        guard value.isFinite else { return }
        let clamped = min(max(value.rounded(), 0), crownMax)
        let i = Int(clamped)
        guard i != lastIndex else { return }
        lastIndex = i
        amount = stepAmount(i)
    }

    /// 膠囊、數字鍵：金額照設，錶冠對到「≤ 它」的那一格（先設 lastIndex，onChange 不會把 187 蓋成 185）
    private func setAmount(_ value: Int) {
        amount = value
        let i = stepIndex(value)
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
        // [v6] 41mm 以下的旅途中、外幣時不畫提示，也不算一次（回到台灣照樣有前 3 次）
        guard !hintCounted, !hidesCrownHint else { return }
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
    /// [v6] 「記到」前面的圖釘（旅遊紫）
    static let pinTint = Color(watchHex: WatchPalette.trip)
}

/// [v6] 「📍 記到 弘大 ›」那一行（Footnote semibold；箭頭只有點得進去時才畫）
private struct AmountTargetLabel: View {
    /// 「記到 弘大」（WatchTripText.targetLine）
    let text: String
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AmountLook.pinTint)
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            chevron
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var chevron: some View {
        if showsChevron {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WatchStyle.small)
        }
    }
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
