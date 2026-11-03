import SwiftUI
import WatchKit

// MARK: - 開始跑步：準備、倒數（手錶 v4，v25.580；watch/judge.md §2.10、§2.17、§2.18；watch/build/v4/brief.md G3-2）
//
// 只屬於 LifeGoodWatch。**骨架（主控寫）：名字 RunPrepView()、RunCountdownView() 不准改（RootView 的 RunFlowView 在叫）；G3 填內容。**
// 這兩頁都在 RootView 的 RunFlowView 裡（WorkoutManager.phase：preparing／countdown），不是彈出頁，背景純黑。
//
// 準備頁（46mm，06:02）：
//   左上 ✕（不跑了：cancelPrep → 回 ③）
//   「🏃 跑步」（Title3 semibold、運動色）／「健走・騎車・登山」（Footnote 灰）——轉錶冠換：跑步 → 健走 → 騎車 → 登山
//     （錶冠綁 Double＋.focusable()，judge §7.8-15；一格一種、不連續；WatchSport.crownOrder）
//   那一行（WatchRunText.prepLine，一次只寫最要緊的一句）：健康沒讓存運動（琥珀、〔開始〕灰、不能按）／還沒問過（按〔開始〕先出說明卡）／
//     沒有位置／只有大約位置（WorkoutManager 進頁時已經問過一次精確位置）／低電量模式／「● GPS 找到了」（綠）、「● 找 GPS 中…可以先開始」
//   大圓鈕〔開始〕（46mm 104 點、41mm 88、40mm 76；綠 1F9D57；不能按時灰、縮小，讓健康那一句寫得下）
//   「這週 9.4／20 公里」（WatchRunText.home 的 prepWeekLine；從來沒收過不寫；〔開始〕不能按時收起來）
// 第一次按〔開始〕（prepLine.asksFirst）：先出說明卡（WatchRunText.permissionCard）〔好〕→ requestPermissions（手錶上跳健康、位置框）
//   → 回準備頁再按一次〔開始〕。說明卡不用 sheet（根已經是跑步那一頁）：卡出現時整頁換成卡（可以捲；錶冠給卡捲，不會換到運動）。
// 倒數：全螢幕 3、2、1（96 點、運動色，外圈跟著少 1/3），「點一下跳過」；震動、數完開始由 WorkoutManager 做。
// 手腕放下：字 0.75、按鈕暫時不能按（不拿掉、版面不跳）；倒數不加動畫。
// [裁定] 沒開始成功（Apple 健康的運動開不起來、beginCollection 失敗）回到準備頁時，那一行先寫 WorkoutManager.problem（琥珀）。

struct RunPrepView: View {
    @ObservedObject private var runs = WorkoutManager.shared
    @ObservedObject private var route = RouteRecorder.shared
    @ObservedObject private var model = WatchModel.shared
    @Environment(\.isLuminanceReduced) private var dimmed

    /// 錶冠轉到第幾種（WatchSport.crownOrder 的第幾個；digitalCrownRotation 只收浮點數）。onAppear 才對上 runs.sport
    @State private var crown: Double = 0
    @State private var showsCard = false
    /// 「這週 9.4／20 公里」：進這頁算一次（定位每秒更新會重畫這頁，不每次重讀手錶的跑步紀錄）
    @State private var weekLine: String?
    @FocusState private var crownFocused: Bool

    /// 手腕放下時字調暗
    static let dimmedOpacity: Double = 0.75
    /// 左上 ✕ 的 VoiceOver
    static let closeLabel = "不跑了"
    /// 大圓鈕裡的圖示
    static let startIcon = "play.fill"
    /// 錶冠最大到第幾種（跑步 0、健走 1、騎車 2、登山 3）
    static let crownMax = Double(WatchSport.crownOrder.count - 1)
    /// 進頁之後晚一點再把錶冠焦點給運動那一塊（剛出現時給焦點偶爾沒反應，同 AmountPicker）
    static let focusDelayNanos: UInt64 = 300_000_000
    /// 40mm（SE，162×197 點）：圓鈕再小一點
    static let smallestHeight: CGFloat = 200

    var body: some View {
        NavigationStack {
            page
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        closeButton
                    }
                }
                .containerBackground(Color.black, for: .navigation)
        }
        .onAppear { appeared() }
        // 進頁、說明卡收起來、系統的健康／位置權限框問完回來（權限變了）之後：錶冠焦點還給運動那一塊
        // （卡收起來那一刻運動那一塊還不在、權限框還蓋著，要晚一點給）
        .task(id: focusKey) { await focusCrownSoon() }
    }

    /// 什麼時候要再把錶冠焦點給運動那一塊
    private var focusKey: RunPrepFocusKey {
        RunPrepFocusKey(showsCard: showsCard, health: runs.health, location: route.access)
    }

    // MARK: 外框

    /// 說明卡出現時整頁換成卡（卡要捲、錶冠給卡；運動那一塊不在畫面上就不會被轉到）
    @ViewBuilder
    private var page: some View {
        if showsCard {
            permissionCard
        } else {
            content
        }
    }

    /// 左上 ✕：不跑了（prepare 過的 session、GPS 都收掉，回 ③）
    private var closeButton: some View {
        Button {
            runs.cancelPrep()
        } label: {
            Image(systemName: "xmark")
        }
        .accessibilityLabel(Text(Self.closeLabel))
        .disabled(dimmed)
    }

    // MARK: 準備頁

    private var content: some View {
        let line = WatchRunText.prepLine(health: runs.health, location: route.access,
                                         lowPower: runs.lowPower, gpsFound: route.gpsFound)
        return VStack(alignment: .leading, spacing: 4) {
            sportBlock
            prepLineText(line)
            startButton(line)
            weekText(line)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scenePadding(.horizontal)
        .opacity(dimmed ? Self.dimmedOpacity : 1)
    }

    /// 「🏃 跑步／健走・騎車・登山」；錶冠綁在這一塊（一格一種）
    private var sportBlock: some View {
        RunPrepSportLabel(sport: runs.sport)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .focusable()
            .focused($crownFocused)
            .focusEffectDisabled()
            .digitalCrownRotation($crown, from: 0, through: Self.crownMax, by: 1,
                                  sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
            .onChange(of: crown) { _, value in
                crownMoved(value)
            }
    }

    /// 那一行：健康那一句很長（41mm 允許縮）；〔開始〕不能按時最多 5 行（圓鈕縮小、這週那一行收起來讓位置）。
    /// [裁定] 剛才沒開始成功（WorkoutManager.problem「沒開始成功：…」，回到準備頁）：這一行先寫那一句（琥珀），
    /// 不然只震一下、看不出為什麼又回到準備頁；再按〔開始〕（beginCountdown 清掉 problem）就換回原本那一行。版面不變
    private func prepLineText(_ line: WatchRunPrepLine) -> some View {
        Text(prepText(line))
            .font(.footnote)
            .foregroundStyle(prepColor(line))
            .lineLimit(line.canStart ? 3 : 5)
            .minimumScaleFactor(0.8)
    }

    /// [裁定] 那一行的字：有沒開始成功的那一句先寫它
    private func prepText(_ line: WatchRunPrepLine) -> String {
        runs.problem ?? line.text
    }

    /// [裁定] 那一行的色：沒開始成功那一句琥珀，不然照 prepLine 的 tone
    private func prepColor(_ line: WatchRunPrepLine) -> Color {
        if runs.problem != nil { return WatchStyle.amber }
        return WatchStyle.tone(line.tone, sport: runs.sport)
    }

    /// 大圓鈕〔開始〕：健康沒讓存運動＝灰、不能按；手腕放下暫時不能按
    private func startButton(_ line: WatchRunPrepLine) -> some View {
        Button {
            start(line)
        } label: {
            RunStartCircle(title: WatchRunText.startButton, icon: Self.startIcon,
                           diameter: circleDiameter(canStart: line.canStart), fill: circleFill(line))
        }
        .buttonStyle(.plain)
        .disabled(!line.canStart || dimmed)
        .frame(maxWidth: .infinity)
    }

    /// 「這週 9.4／20 公里」；從來沒收過（nil）、〔開始〕不能按時不寫
    @ViewBuilder
    private func weekText(_ line: WatchRunPrepLine) -> some View {
        if line.canStart, let week = weekLine {
            Text(week)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: 圓鈕大小、顏色

    /// 41／42／44mm 以下（寬 < 190 點）
    private var isCompact: Bool {
        WatchStyle.isCompact
    }

    /// 40mm（SE）
    private var isSmallest: Bool {
        WKInterfaceDevice.current().screenBounds.height < Self.smallestHeight
    }

    /// 46mm 104、41mm 88、40mm 76（judge §2.10、§2.18）；不能按時 76／64／56
    private func circleDiameter(canStart: Bool) -> CGFloat {
        if isSmallest { return canStart ? 76 : 56 }
        if isCompact { return canStart ? 88 : 64 }
        return canStart ? 104 : 76
    }

    /// 綠 1F9D57；不能按灰；手腕放下暗下來（不留一大塊亮綠）
    private func circleFill(_ line: WatchRunPrepLine) -> Color {
        if dimmed { return WatchStyle.small.opacity(0.25) }
        return line.canStart ? WatchStyle.go : Color.gray.opacity(0.5)
    }

    // MARK: 說明卡（第一次按〔開始〕）

    private var permissionCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(WatchRunText.permissionCard)
                    .font(.body)
                    .foregroundStyle(WatchStyle.primary)
                    .fixedSize(horizontal: false, vertical: true)
                permissionButton
            }
            .scenePadding(.horizontal)
        }
        .opacity(dimmed ? Self.dimmedOpacity : 1)
    }

    /// 〔好〕：收起說明卡、在手錶上跳健康與位置權限框（問完回準備頁，再按一次〔開始〕）
    private var permissionButton: some View {
        Button {
            permissionAccepted()
        } label: {
            Text(WatchRunText.permissionOK)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(WatchStyle.go)
        .disabled(dimmed)
    }

    // MARK: 動作

    private func appeared() {
        crown = Double(WatchSport.crownOrder.firstIndex(of: runs.sport) ?? 0)
        weekLine = WatchRunText.home(package: model.package, own: WatchRunLog.all(), now: Date(),
                                     lastSport: WatchRunPrefs.lastSport).prepWeekLine
        runs.refreshReadiness()
        crownFocused = true
    }

    private func focusCrownSoon() async {
        try? await Task.sleep(nanoseconds: Self.focusDelayNanos)
        guard !Task.isCancelled, !showsCard else { return }
        crownFocused = true
    }

    /// 錶冠轉到第幾格 → 那一種運動（先夾在 0…3 再取整數：Int(Double) 碰到 NaN、無限大會閃退）
    private func crownMoved(_ value: Double) {
        let clamped: Double = value.isFinite ? min(max(value.rounded(), 0), Self.crownMax) : 0
        let i = Int(clamped)
        guard i >= 0, i < WatchSport.crownOrder.count else { return }
        let sport = WatchSport.crownOrder[i]
        guard sport != runs.sport else { return }
        runs.setSport(sport)
    }

    /// 〔開始〕：還沒問過權限先出說明卡；不然 3、2、1
    private func start(_ line: WatchRunPrepLine) {
        guard line.canStart else { return }
        if line.asksFirst {
            showsCard = true
        } else {
            runs.beginCountdown()
        }
    }

    private func permissionAccepted() {
        showsCard = false
        Task { await runs.requestPermissions() }
    }
}

/// 準備頁錶冠焦點要重給的時機：說明卡出現／收起、健康或位置權限變了（系統權限框收起來以後焦點可能不在運動那一塊）
private struct RunPrepFocusKey: Equatable {
    let showsCard: Bool
    let health: WatchRunHealthAccess
    let location: WatchRunLocationAccess
}

// MARK: - 「🏃 跑步／健走・騎車・登山」

private struct RunPrepSportLabel: View {
    let sport: WatchSport

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            nameRow
            Text(sport.others)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var nameRow: some View {
        HStack(spacing: 5) {
            Image(systemName: sport.icon)
            Text(sport.displayName)
                .lineLimit(1)
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(WatchStyle.sport(sport))
    }
}

// MARK: - 大圓鈕〔▶ 開始〕

private struct RunStartCircle: View {
    let title: String
    let icon: String
    let diameter: CGFloat
    let fill: Color

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
            Text(title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.white)
        .frame(width: diameter, height: diameter)
        .background {
            Circle().fill(fill)
        }
        .contentShape(Circle())
    }

    /// 圓鈕小（不能按、40mm）時圖示跟著小
    private var iconSize: CGFloat {
        diameter >= 88 ? 18 : 14
    }
}

// MARK: - 3、2、1

struct RunCountdownView: View {
    @ObservedObject private var runs = WorkoutManager.shared
    @Environment(\.isLuminanceReduced) private var dimmed

    /// 手腕放下時字調暗
    static let dimmedOpacity: Double = 0.75
    static let ringWidth: CGFloat = 8

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            RunCountdownDial(count: runs.countdown, color: WatchStyle.sport(runs.sport),
                             diameter: dialDiameter, numberSize: numberSize, ringWidth: Self.ringWidth)
            Text(WatchRunText.countdownHint)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(dimmed ? Self.dimmedOpacity : 1)
        .background(Color.black)
        .contentShape(Rectangle())
        .onTapGesture {
            runs.skipCountdown()
        }
        .accessibilityAddTraits(.isButton)
    }

    /// 外圈：46mm 148、41mm 124
    private var dialDiameter: CGFloat {
        WatchStyle.isCompact ? 124 : 148
    }

    /// 數字 96 點（41mm 80）
    private var numberSize: CGFloat {
        WatchStyle.isCompact ? 80 : 96
    }
}

/// 中間大數字＋外面一圈（3 滿圈、2 剩 2/3、1 剩 1/3；不加動畫）
private struct RunCountdownDial: View {
    let count: Int
    let color: Color
    let diameter: CGFloat
    let numberSize: CGFloat
    let ringWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: ringWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, lineWidth: ringWidth)
                .rotationEffect(.degrees(-90))
            Text("\(count)")
                .font(.system(size: numberSize, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: diameter, height: diameter)
    }

    /// runs.countdown ／ 3，夾在 0…1
    private var fraction: CGFloat {
        min(max(CGFloat(count) / 3, 0), 1)
    }
}
