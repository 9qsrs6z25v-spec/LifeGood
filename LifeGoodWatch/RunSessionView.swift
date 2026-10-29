import SwiftUI
import WatchKit

// MARK: - 跑步中（手錶 v4，v25.580；watch/judge.md §2.11、§2.17、§2.18；watch/build/v4/brief.md G4-1）
//
// 只屬於 LifeGoodWatch。**骨架（主控寫）：名字 RunSessionView() 不准改（RootView 的 RunFlowView 在叫）；G4 填內容。**
// RootView 的 RunFlowView 在 WorkoutManager.phase 是 running／paused 時整個畫面換成這一頁（不是彈出頁，背景純黑）。
//
// 左右滑三頁（TabView＋.page，照 Apple 範例 PagingView；預設中間的數字頁）：
//   〔控制〕 ◄─► 〔數字〕 ◄─► 〔正在播放〕（系統的 NowPlayingView，控制 AirPods 上的 Podcast、音樂）
// • 數字頁：TimelineView 每秒一次（手腕放下系統一秒最多一次，秒照跳）→ WatchRunText.live 給的頁首與四個數字：
//     「🏃 晨跑」（時段名，不寫地名）／「21:05」移動時間／「3.42 公里」／「6'20" 這一公里」（騎車「21.4 時速」）／「152 ♥ 心率」。
//   頁首狀態：「晨跑・GPS 弱」、「⏸ 已自動暫停」（琥珀、時間變灰）、「⏸ 已暫停 0:42」（琥珀、時間變灰、心率那一格換大〔▶ 繼續〕）、
//   「已接回」（綠，當機重開後 3 秒）。View 不自己拼字、不自己算配速。
// • 控制頁：兩顆圓鈕〔⏸ 暫停〕／〔▶ 繼續〕與〔■ 按住結束〕（外圈 1 秒填滿才結束；只點一下、手指滑開都不會結束：
//   onLongPressGesture(minimumDuration:maximumDistance:perform:onPressingChanged:)——**沒有 maximumDistance 的那支只有 tvOS**）；
//   下面兩顆小開關「🔊 語音 開／關」「震動 開／關」（這一趟有效，也記成下次的預設：WorkoutManager.setVoiceOn／setHapticOn）。
// • 每跑滿一公里（WorkoutManager.kmFlash 不是 nil 的那 3 秒）：整個畫面蓋一層「第 3 公里／6'10"／這一公里／平均 6'08"」，
//   點一下不做事（3 秒後 WorkoutManager 自己清掉）；震動、講話也是 WorkoutManager 做。
// • 按了暫停／繼續（phase 變）、手腕放下或抬起來：回到數字頁（Apple 範例的做法）。
// • 手腕放下：四個數字照顯示、秒照跳（judge §2.17；運動中 Apple 也這樣）；字調暗、頁點收起來、按鈕暫時不能按（不拿掉、版面不跳）；
//   沒有一秒好幾次的動畫（按住結束那一圈只在你按著的時候動）。

struct RunSessionView: View {
    @ObservedObject private var runs = WorkoutManager.shared
    @Environment(\.isLuminanceReduced) private var dimmed

    /// 現在在哪一頁（預設數字頁）
    @State private var page: RunSessionTab = .metrics

    var body: some View {
        ZStack {
            pages
            flashLayer
        }
        .onChange(of: runs.phase) { _, _ in
            showMetrics()
        }
        .onChange(of: dimmed) { _, _ in
            showMetrics()
        }
    }

    // MARK: 三頁

    private var pages: some View {
        TabView(selection: $page) {
            RunControlsPage()
                .tag(RunSessionTab.controls)
            RunMetricsPage()
                .tag(RunSessionTab.metrics)
            nowPlaying
                .tag(RunSessionTab.nowPlaying)
        }
        .tabViewStyle(.page(indexDisplayMode: indexMode))
    }

    /// 系統的「正在播放」（WatchKit，watchOS 7）
    private var nowPlaying: some View {
        NowPlayingView()
            .containerBackground(Color.black, for: .tabView)
    }

    /// 頁點：手腕放下收起來
    private var indexMode: PageTabViewStyle.IndexDisplayMode {
        dimmed ? .never : .automatic
    }

    /// 每跑滿一公里那 3 秒：整個畫面蓋上去
    @ViewBuilder
    private var flashLayer: some View {
        if let flash = runs.kmFlash {
            RunKmFlashView(flash: flash, sport: runs.sport, voiceOn: runs.voiceOn)
        }
    }

    // MARK: 動作

    /// 回到數字頁（按了暫停／繼續、手腕放下或抬起來）
    private func showMetrics() {
        if page != .metrics {
            page = .metrics
        }
    }
}

/// 跑步中的三頁
private enum RunSessionTab: Hashable {
    case controls
    case metrics
    case nowPlaying
}

// MARK: - 數字頁

private struct RunMetricsPage: View {
    @ObservedObject private var runs = WorkoutManager.shared
    @ObservedObject private var route = RouteRecorder.shared
    @Environment(\.isLuminanceReduced) private var dimmed

    /// 手腕放下時整頁調暗（數字照顯示）
    static let dimmedOpacity: Double = 0.8
    /// 每秒一次
    static let tick: TimeInterval = 1

    var body: some View {
        TimelineView(.periodic(from: tickStart, by: Self.tick)) { context in
            metrics(now: context.date)
        }
        .containerBackground(Color.black, for: .tabView)
    }

    /// 秒對齊開始那一刻（還沒有開始時間就從現在）
    private var tickStart: Date {
        runs.startDate ?? Date()
    }

    private func metrics(now: Date) -> some View {
        let state = liveState(now: now)
        let live = WatchRunText.live(sport: runs.sport, start: runs.startDate ?? now,
                                     movingSeconds: runs.movingSeconds(at: now), meters: runs.meters,
                                     recentPace: runs.recentPace, recentSpeed: runs.recentSpeed,
                                     heartRate: runs.heartRate, state: state, gpsWeak: route.gpsWeak, now: now)
        let sizes = RunMetricSizes.current
        let headerColor = WatchStyle.tone(live.headerTone, sport: runs.sport)
        return VStack(alignment: .leading, spacing: 0) {
            RunLiveHeader(text: live.header, icon: headerIcon(state), color: headerColor)
            RunLiveTime(text: live.time, dim: live.timeIsDim, size: sizes.number)
            RunLiveDistance(value: live.distance, size: sizes.distance)
            RunLiveValueRow(value: live.paceValue, label: live.paceLabel, size: sizes.number)
            bottomRow(heart: live.heart, size: sizes.number)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scenePadding(.horizontal)
        .ignoresSafeArea(edges: .bottom)
        .opacity(dimmed ? Self.dimmedOpacity : 1)
    }

    /// 頁首狀態：剛接回（3 秒）→ 你按的暫停 → 手錶的自動暫停 → 跑步中
    private func liveState(now: Date) -> WatchRunLiveState {
        if let until = runs.recoveredUntil, until > now {
            return .recovered
        }
        if runs.phase == .paused {
            return .paused(since: runs.pausedSince ?? now)
        }
        if runs.autoPaused {
            return .autoPaused
        }
        return .running
    }

    /// 頁首圖示：暫停（你按的、自動的）⏸，其他運動圖示
    private func headerIcon(_ state: WatchRunLiveState) -> String {
        switch state {
        case .paused, .autoPaused:
            return "pause.fill"
        case .running, .recovered:
            return runs.sport.icon
        }
    }

    /// 最下面一格：平常心率；你按了暫停換大〔▶ 繼續〕
    @ViewBuilder
    private func bottomRow(heart: String, size: CGFloat) -> some View {
        if runs.phase == .paused {
            RunResumeButton(height: size + 8, dimmed: dimmed) {
                runs.resume()
            }
            .padding(.top, 2)
        } else {
            RunLiveHeartRow(heart: heart, size: size)
        }
    }
}

/// 數字的大小：46mm（基準）距離 56、其他 30；41／42／44mm 距離 48；40mm（SE）距離 44、其他 26（judge §2.11、§2.18）
private struct RunMetricSizes {
    let distance: CGFloat
    let number: CGFloat

    /// 40mm（SE，162×197 點）
    static let smallestHeight: CGFloat = 200

    @MainActor
    static var current: RunMetricSizes {
        if WKInterfaceDevice.current().screenBounds.height < smallestHeight {
            return RunMetricSizes(distance: 44, number: 26)
        }
        if WatchStyle.isCompact {
            return RunMetricSizes(distance: 48, number: 30)
        }
        return RunMetricSizes(distance: 56, number: 30)
    }
}

/// 「🏃 晨跑」「⏸ 已暫停 0:42」：Footnote semibold，顏色照 WatchRunLive.headerTone
private struct RunLiveHeader: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(color)
    }
}

/// 移動時間「21:05」：Title2 30 semibold rounded 等寬；暫停中變灰
private struct RunLiveTime: View {
    let text: String
    let dim: Bool
    let size: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(dim ? WatchStyle.small : WatchStyle.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// 距離「3.42 公里」：56 點 heavy rounded 等寬（「12.34」太寬自己縮到 0.8）；「公里」Footnote 靠右
private struct RunLiveDistance: View {
    let value: String
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
            Spacer(minLength: 0)
            RunLiveUnit(text: WatchRunText.kmUnit)
        }
    }
}

/// 「6'20"　這一公里」（騎車「21.4　時速」）：數字 30 點、標籤 Footnote 靠右
private struct RunLiveValueRow: View {
    let value: String
    let label: String
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
            Spacer(minLength: 0)
            RunLiveUnit(text: label)
        }
    }
}

/// 「152 ♥　心率」
private struct RunLiveHeartRow: View {
    let heart: String
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(heart)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
            Image(systemName: "heart.fill")
                .font(.system(size: heartIconSize, weight: .semibold))
                .foregroundStyle(WatchStyle.heart)
            Spacer(minLength: 0)
            RunLiveUnit(text: WatchRunText.heartLabel)
        }
    }

    /// ♥ 比數字小一半左右
    private var heartIconSize: CGFloat {
        (size * 0.55).rounded()
    }
}

/// 右邊的小標籤「公里」「這一公里」「心率」：Footnote A3B2D9
private struct RunLiveUnit: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(WatchStyle.small)
            .lineLimit(1)
            .fixedSize()
    }
}

/// 你按了暫停：心率那一格換大〔▶ 繼續〕（綠；高度跟一列數字差不多，版面不跳）
private struct RunResumeButton: View {
    let height: CGFloat
    let dimmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
        .accessibilityLabel(Text(WatchRunText.resumeTitle))
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: "play.fill")
            Text(WatchRunText.resumeTitle)
                .lineLimit(1)
        }
        .font(.headline)
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background {
            Capsule().fill(WatchStyle.go)
        }
        .contentShape(Capsule())
    }
}

// MARK: - 控制頁

private struct RunControlsPage: View {
    @ObservedObject private var runs = WorkoutManager.shared
    @Environment(\.isLuminanceReduced) private var dimmed

    /// 按住結束那一圈填到哪（0 → 1，按著時 1 秒填滿；放開退回 0）
    @State private var holdProgress: CGFloat = 0

    /// 手腕放下時字調暗
    static let dimmedOpacity: Double = 0.75
    /// 圓鈕最大 76 點（judge §2.11）；40mm 兩顆放不下時照螢幕寬縮
    static let maxDiameter: CGFloat = 76
    /// 兩顆圓鈕中間
    static let gap: CGFloat = 10
    /// 按著時手指可以移動多遠還算按著（碰到袖子、手指滑一點不會中斷；滑開就不算）
    static let holdSlop: CGFloat = 20
    /// 外圈粗細
    static let ringWidth: CGFloat = 5

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: Self.gap) {
                pauseButton
                endControl
            }
            HStack(spacing: 6) {
                voiceToggle
                hapticToggle
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scenePadding(.horizontal)
        .opacity(dimmed ? Self.dimmedOpacity : 1)
        .containerBackground(Color.black, for: .tabView)
        .onChange(of: dimmed) { _, _ in
            holdProgress = 0
        }
    }

    /// 圓鈕直徑：最大 76；螢幕窄（40mm 162 點）時兩顆＋左右留白放得下為準
    private var diameter: CGFloat {
        let width = WKInterfaceDevice.current().screenBounds.width
        let fit = ((width - 24 - Self.gap) / 2).rounded(.down)
        return min(Self.maxDiameter, max(56, fit))
    }

    private var isPaused: Bool {
        runs.phase == .paused
    }

    // MARK: 〔⏸ 暫停〕／〔▶ 繼續〕

    private var pauseButton: some View {
        Button {
            togglePause()
        } label: {
            RunRoundControl(icon: isPaused ? "play.fill" : "pause.fill",
                            title: isPaused ? WatchRunText.resumeTitle : WatchRunText.pauseTitle,
                            color: isPaused ? WatchStyle.go : WatchStyle.amber,
                            diameter: diameter)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
    }

    private func togglePause() {
        if isPaused {
            runs.resume()
        } else {
            runs.pause()
        }
    }

    // MARK: 〔■ 按住結束〕

    private var endControl: some View {
        VStack(spacing: 4) {
            endCircle
            RunControlTitle(text: WatchRunText.endTitle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(WatchRunText.endTitle))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            holdFinished()
        }
    }

    /// 紅圓＋外圈（按著 1 秒填滿才叫 end()）
    private var endCircle: some View {
        RunHoldRing(progress: holdProgress, color: WatchStyle.red, diameter: diameter, ringWidth: Self.ringWidth)
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: WatchRunText.holdSeconds, maximumDistance: Self.holdSlop,
                                perform: { holdFinished() },
                                onPressingChanged: { pressing in pressingChanged(pressing) })
            .disabled(dimmed)
    }

    /// 按著：外圈 1 秒線性填滿；放開（還沒滿）：很快退回 0
    private func pressingChanged(_ pressing: Bool) {
        let animation: Animation = pressing
            ? .linear(duration: WatchRunText.holdSeconds)
            : .easeOut(duration: 0.2)
        withAnimation(animation) {
            holdProgress = pressing ? 1 : 0
        }
    }

    /// 按滿 1 秒：結束（手腕放下時不算）
    private func holdFinished() {
        guard !dimmed else { return }
        runs.end()
    }

    // MARK: 小開關

    private var voiceToggle: some View {
        Button {
            runs.setVoiceOn(!runs.voiceOn)
        } label: {
            RunSmallToggleLabel(icon: runs.voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                                title: WatchRunText.voiceTitle, on: runs.voiceOn)
        }
        .buttonStyle(.bordered)
        .disabled(dimmed)
    }

    private var hapticToggle: some View {
        Button {
            runs.setHapticOn(!runs.hapticOn)
        } label: {
            RunSmallToggleLabel(icon: "waveform", title: WatchRunText.hapticTitle, on: runs.hapticOn)
        }
        .buttonStyle(.bordered)
        .disabled(dimmed)
    }
}

/// 圓鈕：淡色底圓＋圖示＋下面一行字（〔⏸ 暫停〕琥珀、〔▶ 繼續〕綠）
private struct RunRoundControl: View {
    let icon: String
    let title: String
    let color: Color
    let diameter: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            circle
            RunControlTitle(text: title)
        }
    }

    private var circle: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
            Image(systemName: icon)
                .font(.system(size: (diameter * 0.36).rounded(), weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
    }
}

/// 〔■ 按住結束〕的圓：紅色淡底＋紅色外圈軌道＋白色進度（從 12 點鐘方向順時針）
private struct RunHoldRing: View {
    let progress: CGFloat
    let color: Color
    let diameter: CGFloat
    let ringWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
            Circle()
                .stroke(color.opacity(0.6), lineWidth: ringWidth)
            progressArc
            Image(systemName: "stop.fill")
                .font(.system(size: (diameter * 0.3).rounded(), weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: diameter, height: diameter)
    }

    private var progressArc: some View {
        Circle()
            .trim(from: 0, to: min(max(progress, 0), 1))
            .stroke(Color.white, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}

/// 圓鈕下面那一行字
private struct RunControlTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(WatchStyle.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// 「🔊 語音 開」「〰 震動 關」（開＝綠字、關＝灰字）
private struct RunSmallToggleLabel: View {
    let icon: String
    let title: String
    let on: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(title)
            Text(on ? WatchRunText.onText : WatchRunText.offText)
                .foregroundStyle(on ? WatchStyle.saved : WatchStyle.small)
        }
        .font(.footnote)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 每跑滿一公里那 3 秒（全螢幕黑）

private struct RunKmFlashView: View {
    let flash: WatchRunKmFlash
    let sport: WatchSport
    let voiceOn: Bool
    @Environment(\.isLuminanceReduced) private var dimmed

    /// 這一句真的會講（語音開著、手錶上有台灣中文嗓音、打包出來有 audio 背景模式；同 WatchRunVoice.say 的條件）：出現時看一次
    @State private var speaks = false

    /// 手腕放下時字調暗
    static let dimmedOpacity: Double = 0.8

    var body: some View {
        VStack(spacing: 2) {
            Text(flash.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(WatchStyle.sport(sport))
                .lineLimit(1)
            RunFlashBig(text: flash.big)
            Text(flash.bigLabel)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
            Text(flash.line)
                .font(.title3)
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            voiceRow
        }
        .scenePadding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(dimmed ? Self.dimmedOpacity : 1)
        .background(Color.black)
        .contentShape(Rectangle())
        .onTapGesture { }
        .accessibilityElement(children: .combine)
        .onAppear {
            speaks = voiceOn && WatchRunVoice.hasTaiwanVoice && WatchRunVoice.hasAudioBackgroundMode
        }
    }

    /// 🔊 正在講的那一句（只有真的會講才畫）
    @ViewBuilder
    private var voiceRow: some View {
        if speaks {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Image(systemName: "speaker.wave.2.fill")
                Text(flash.voice)
                    .lineLimit(2)
            }
            .font(.footnote)
            .foregroundStyle(WatchStyle.small)
            .padding(.top, 2)
        }
    }
}

/// 「6'10"」（騎車「22.0」）：56 點 heavy rounded 等寬（41mm 48）
private struct RunFlashBig: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(WatchStyle.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var size: CGFloat {
        WatchStyle.isCompact ? 48 : 56
    }
}
