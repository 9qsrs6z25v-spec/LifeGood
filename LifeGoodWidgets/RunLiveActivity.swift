import SwiftUI
import UIKit
import WidgetKit
import ActivityKit
import AppIntents

// MARK: - 跑步即時動態 · 鎖定畫面＋靈動島＋手錶（健康 v6，v25.556）
//
// 只屬於 LifeGoodWidgets target（A01C000002000001）。放在 LifeGoodLifeBundle（LifeGoodWidgetsBundle.swift，主控已加）。
// 資料：共用檔 RunActivityAttributes.swift（字都是 App 組好的）；暫停鈕：共用檔 RunPauseIntent.swift。
// 規格：scratchpad/health/judge.md §4.4、樣稿②-4；health/build/v6/brief.md §G2。
//
// • 鎖定畫面（RunLALockCard）：天空底（WidgetSky，不放雲和月牙：右上是暫停鈕）
//     [跑者] 晨跑・跑步中                ( ⏸ )
//     3.42 公里      21:05       6'20"
//     距離           時間         這一公里
//   暫停：「晨跑・已暫停」、時間停住變灰、鈕變 ▶︎、第三格是 App 換好的平均（「平均配速」）。
//   過期（context.isStale）多一行：記錄中「好一陣子沒更新了…」、暫停 30 分鐘「已暫停 30 分鐘・不跑了就打開 LifeGood 按結束」。
//   完成：整張換成一列綠勾「完成　5.20 公里・32:10・6'11"」（App 用 dismissalPolicy .after 留 15 分鐘）。
// • 靈動島：縮起「[跑者] 3.42 ── 21:05」（右邊計時字固定寬 58）、只剩一點位置只有跑者（暫停中是 ⏸）、
//   長按展開＝標題＋暫停鈕、三個數字。
// • 手錶智慧型堆疊（.supplementalActivityFamilies([.small])，iOS 18）：RunLASmallView，沒有按鈕（手錶上點了開完整那張）。
// • 時間：Text(timerInterval: clockStart…+24h, pauseTime: pausedAt, countsDown: false) 系統自己走，App 不每秒推。
//   小工具裡計時字會撐滿寬度（Apple 文件），一定配 frame＋multilineTextAlignment。
// • 不畫路線形狀、不畫地點（ContentState 根本沒有；judge 待決定 9）。只有一顆鈕（暫停／繼續），結束要打開 App。
// • [v25.557] 點卡片本身（鎖定畫面、靈動島）：widgetURL＝WidgetLink.healthRun（lifegood://life/health/run?src=widget，共用檔）
//   → App 的 DeepLinkRouter 切到人生 › 健康、健康頁打開跑步畫面（在跑）／成果頁（剛跑完）。暫停鈕是 Button(intent:)，不走這條。
//   自動暫停：共用檔 headline 自己寫「晨跑・自動暫停」，這裡不用改字。
// • 只讀共用檔的字（headline、staleNote、buttonIcon…）與 context.state 的字，這裡不算任何數字。
// • 新型別一律 RunLA 開頭（小工具 target 裡已經有 internal 的 LockScreenView、TimelineStrip、StopDetail；
//   private 也會撞名，v25.485 的教訓）。不准引用 App 的型別（WorkoutPalette、WorkoutFormat 都不在這個 target）。

struct RunLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            RunLALockView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(RunLAColors.lockTint)
                .activitySystemActionForegroundColor(RunLAColors.lockInk)
                // [v25.557] 點卡片（不是暫停鈕）：打開 App 直接到跑步畫面（在跑回到那一趟、剛跑完到成果頁；HealthView.openRunFromLink）
                .widgetURL(WidgetLink.healthRun)
        } dynamicIsland: { context in
            DynamicIsland {
                // 四個角是圓的，貼邊的內容會被切掉：每一區都往內縮 6（同今日行程 v25.382、照片匯入）
                DynamicIslandExpandedRegion(.leading) {
                    RunLAExpandedLeading(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RunLAExpandedTrailing(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RunLAExpandedBottom(state: context.state, isStale: context.isStale)
                }
            } compactLeading: {
                RunLACompactLeading(attributes: context.attributes, state: context.state)
            } compactTrailing: {
                RunLACompactTrailing(state: context.state)
            } minimal: {
                RunLAMinimal(attributes: context.attributes, state: context.state)
            }
            .keylineTint(RunLAColors.sport(context.attributes.sport, dark: true))
            // [v25.557] 靈動島（縮起、只剩一點、展開）點了一樣到跑步畫面；暫停鈕是按鈕，不會觸發這個（DynamicIsland.widgetURL，iOS 16.1）
            .widgetURL(WidgetLink.healthRun)
        }
        // iOS 18：手錶智慧型堆疊（有戴 Apple Watch 時系統自己放上去）；版面看 activityFamily（RunLALockView）
        .supplementalActivityFamilies([.small])
    }
}

// MARK: - 顏色

/// 即時動態用的顏色（色碼照 WidgetPalette／共用檔的運動色；App 的 WorkoutPalette 不在這個 target）
enum RunLAColors {
    /// 鎖定畫面卡的底（activityBackgroundTint）＝天空下緣：淺 F4F8FD／深 0E1428。
    /// 這個修飾器在 ActivityConfiguration 的閉包裡給、讀不到 colorScheme，所以用會自己換的 UIColor
    static let lockTint: Color = adaptive(light: 0xF4F8FD, dark: 0x0E1428)

    /// 系統動作鈕（右上角關閉之類）的字色＝WidgetPalette.ink：淺 0B1B45／深 F3F6FF
    static let lockInk: Color = adaptive(light: 0x0B1B45, dark: 0xF3F6FF)

    /// 靈動島過期那一行的黃（WidgetPalette 深色的 warn）
    static let islandWarn: Color = Color(widgetHex: 0xFFC14D)

    /// 靈動島完成那一行的綠（WidgetPalette 深色的 good）
    static let islandGood: Color = Color(widgetHex: 0x5BD99A)

    /// 運動色（共用檔 RunActivitySport.tintHex／tintHexDark；靈動島底是黑的，一律用深色那一組）
    static func sport(_ sport: RunActivitySport, dark: Bool) -> Color {
        Color(widgetHex: dark ? sport.tintHexDark : sport.tintHex)
    }

    /// 淺色／深色各一個色碼 → 會跟著系統外觀換的顏色
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        let lightColor = uiColor(light)
        let darkColor = uiColor(dark)
        let provider = UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        })
        return Color(uiColor: provider)
    }

    /// 0xRRGGBB → UIColor
    private static func uiColor(_ hex: UInt32) -> UIColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        return UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

// MARK: - 字

/// 計時字與圖示名（字都從共用檔拿；這裡只組 Text）
enum RunLAText {
    /// 往上數的計時字：從 clockStart 數，暫停中、完成停在 pausedAt（系統自己走，App 不每秒推）
    static func timer(_ state: RunActivityAttributes.ContentState) -> Text {
        Text(timerInterval: RunActivityAttributes.timerRange(state),
             pauseTime: state.pausedAt,
             countsDown: false,
             showsHours: true)
    }

    /// 靈動島縮起左邊、只剩一點位置時的圖示：記錄中跑者（運動圖示）、暫停中 ⏸、完成 ✓
    static func islandIcon(_ attributes: RunActivityAttributes, _ state: RunActivityAttributes.ContentState) -> String {
        switch state.phase {
        case .running:
            return attributes.sport.icon
        case .paused:
            return "pause.fill"
        case .finished:
            return "checkmark"
        }
    }

    /// 過期時多寫的那一行（完成那張沒有）
    static func staleLine(_ state: RunActivityAttributes.ContentState, isStale: Bool) -> String? {
        guard isStale else { return nil }
        return RunActivityAttributes.staleNote(state)
    }
}

// MARK: - 三個數字（鎖定畫面、靈動島展開共用）

/// 三格的字級與顏色
struct RunLAFigureStyle {
    /// 數字的字級（鎖定畫面 26、靈動島 22）；「公里」是一半
    let valueSize: CGFloat
    /// 下面小字的字級（鎖定畫面 12、靈動島 11）
    let labelSize: CGFloat
    /// 數字的顏色
    let value: Color
    /// 小字的顏色
    let label: Color
    /// 計時字的顏色（暫停中、完成變灰：時間停住了）
    let timer: Color

    /// 鎖定畫面：WidgetPalette 的 ink／label
    static func lock(_ palette: WidgetPalette, running: Bool) -> RunLAFigureStyle {
        RunLAFigureStyle(valueSize: 26, labelSize: 12,
                         value: palette.ink, label: palette.label,
                         timer: running ? palette.ink : palette.label)
    }

    /// 靈動島（黑底）：白字、小字白 0.6、暫停中計時字白 0.55
    static func island(running: Bool) -> RunLAFigureStyle {
        RunLAFigureStyle(valueSize: 22, labelSize: 11,
                         value: Color.white, label: Color.white.opacity(0.6),
                         timer: running ? Color.white : Color.white.opacity(0.55))
    }
}

/// 「3.42 公里｜21:05｜6'20"」＋下面「距離｜時間｜這一公里」
struct RunLAFigureRow: View {
    let state: RunActivityAttributes.ContentState
    let style: RunLAFigureStyle

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RunLAFigureCell(label: "距離", style: style, value: distance)
            RunLAFigureCell(label: "時間", style: style, value: clock)
            RunLAFigureCell(label: state.thirdLabel, style: style, value: third)
        }
    }

    private var distance: RunLADistanceValue {
        RunLADistanceValue(text: state.distanceText, size: style.valueSize, color: style.value)
    }

    /// 計時字會撐滿寬度（Apple 文件）：格子本身已經 maxWidth、靠左，字也靠左
    private var clock: some View {
        RunLAText.timer(state)
            .font(.system(size: style.valueSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(style.timer)
            .multilineTextAlignment(.leading)
            .lineLimit(1)
    }

    private var third: some View {
        Text(state.thirdText)
            .font(.system(size: style.valueSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(style.value)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// 一格：上面數字、下面小字；三格等寬靠左
struct RunLAFigureCell<Value: View>: View {
    let label: String
    let style: RunLAFigureStyle
    let value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            value
            Text(label)
                .font(.system(size: style.labelSize, weight: .semibold))
                .foregroundStyle(style.label)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 「3.42 公里」：數字大、「公里」一半大，對齊同一條底線
struct RunLADistanceValue: View {
    let text: String
    let size: CGFloat
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(text)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("公里")
                .font(.system(size: unitSize, weight: .semibold))
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var unitSize: CGFloat { (size / 2).rounded() }
}

// MARK: - 暫停鈕、完成那一列（鎖定畫面、靈動島共用）

/// 唯一的一顆鈕：記錄中〔⏸〕按了暫停、暫停中〔▶︎〕按了繼續（RunPauseIntent 在 App 的行程裡跑，不開 App 畫面）。
/// 帶著這一趟的 runId：按到殘留的舊一趟，App 只收掉殘留、不會動到正在記的這一趟
struct RunLAPauseButton: View {
    let attributes: RunActivityAttributes
    let state: RunActivityAttributes.ContentState
    /// 直徑：鎖定畫面 40、靈動島展開 34
    let diameter: CGFloat
    /// 圓的底色
    let fill: Color
    /// 圖示的顏色
    let iconColor: Color

    var body: some View {
        Button(intent: intent) {
            RunLAPauseDisc(icon: RunActivityAttributes.buttonIcon(state),
                           diameter: diameter, fill: fill, iconColor: iconColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(RunActivityAttributes.buttonLabel(state)))
    }

    private var intent: RunPauseIntent {
        RunPauseIntent(pause: RunActivityAttributes.buttonPauses(state), runId: attributes.runId)
    }
}

/// 暫停鈕的圓
struct RunLAPauseDisc: View {
    let icon: String
    let diameter: CGFloat
    let fill: Color
    let iconColor: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(iconColor)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
    }
}

/// 完成那一列：綠勾「完成　5.20 公里・32:10・6'11"」（字是 App 組好的 finishedLine）
struct RunLAFinishedRow: View {
    let line: String
    /// 字級（鎖定畫面 15、靈動島 15）
    let size: CGFloat
    let ink: Color
    let good: Color

    var body: some View {
        HStack(spacing: 10) {
            RunLACheckDisc(fill: good)
            Text("完成")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(ink)
            Text(line)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 綠圓白勾（直徑 26）
struct RunLACheckDisc: View {
    let fill: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white)
        }
        .frame(width: 26, height: 26)
    }
}

// MARK: - 鎖定畫面（含手錶智慧型堆疊）

/// 鎖定畫面閉包裡那一個 view：手錶智慧型堆疊（.small）換小版，其他（鎖定畫面、StandBy）是天空卡
struct RunLALockView: View {
    let attributes: RunActivityAttributes
    let state: RunActivityAttributes.ContentState
    let isStale: Bool

    @Environment(\.activityFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if isSmall {
            RunLASmallView(attributes: attributes, state: state, isStale: isStale, palette: palette)
        } else {
            RunLALockCard(attributes: attributes, state: state, isStale: isStale, palette: palette)
        }
    }

    /// 用 if case，不用 switch：ActivityFamily 之後多 case 也不怕
    private var isSmall: Bool {
        if case .small = family { return true }
        return false
    }

    private var palette: WidgetPalette { WidgetPalette(scheme) }
}

/// 鎖定畫面那張天空卡（樣稿②-4）。高度：記錄中 ≈ 14＋40＋8＋47＋14 ≈ 123；過期兩行 ≈ 156（上限 160）
struct RunLALockCard: View {
    let attributes: RunActivityAttributes
    let state: RunActivityAttributes.ContentState
    let isStale: Bool
    let palette: WidgetPalette

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { WidgetSky(palette: palette, moon: WidgetSkyMoon.none) }
    }

    @ViewBuilder
    private var content: some View {
        if state.phase == .finished {
            RunLAFinishedRow(line: state.finishedLine ?? "", size: 15, ink: palette.ink, good: palette.good)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                RunLALockHeader(attributes: attributes, state: state, palette: palette)
                RunLALockBody(state: state, isStale: isStale, palette: palette)
            }
        }
    }
}

/// 第一列「[跑者] 晨跑・跑步中」＋右邊圓鈕（深藍底、天空色圖示）
struct RunLALockHeader: View {
    let attributes: RunActivityAttributes
    let state: RunActivityAttributes.ContentState
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: attributes.sport.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            Text(attributes.headline(state))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            RunLAPauseButton(attributes: attributes, state: state, diameter: 40,
                             fill: palette.ink, iconColor: palette.skyBottom)
        }
    }

    private var tint: Color { RunLAColors.sport(attributes.sport, dark: palette.isDark) }
}

/// 三個數字＋（過期時）多一行提醒
struct RunLALockBody: View {
    let state: RunActivityAttributes.ContentState
    let isStale: Bool
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RunLAFigureRow(state: state, style: style)
            if let note = RunLAText.staleLine(state, isStale: isStale) {
                Text(note)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.warn)
                    .lineLimit(2)
            }
        }
    }

    private var style: RunLAFigureStyle {
        RunLAFigureStyle.lock(palette, running: state.phase == .running)
    }
}

/// 手錶智慧型堆疊（.small）：沒有按鈕（手錶上點了會打開完整那張）。
/// 「[跑者] 晨跑・跑步中」／「3.42 公里」／「21:05」（過期時這一列換成提醒）
struct RunLASmallView: View {
    let attributes: RunActivityAttributes
    let state: RunActivityAttributes.ContentState
    let isStale: Bool
    let palette: WidgetPalette

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if state.phase == .finished {
            RunLASmallFinished(line: state.finishedLine ?? "", palette: palette)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                RunLASmallHeader(attributes: attributes, state: state, palette: palette)
                RunLADistanceValue(text: state.distanceText, size: 24, color: palette.ink)
                RunLASmallClockLine(state: state, isStale: isStale, palette: palette)
            }
        }
    }
}

/// 手錶：圖示＋標題（13 pt）
struct RunLASmallHeader: View {
    let attributes: RunActivityAttributes
    let state: RunActivityAttributes.ContentState
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: attributes.sport.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(attributes.headline(state))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
        }
    }

    private var tint: Color { RunLAColors.sport(attributes.sport, dark: palette.isDark) }
}

/// 手錶第三列：計時字（15 pt）；過期時換成提醒（12 pt、兩行）
struct RunLASmallClockLine: View {
    let state: RunActivityAttributes.ContentState
    let isStale: Bool
    let palette: WidgetPalette

    var body: some View {
        if let note = RunLAText.staleLine(state, isStale: isStale) {
            Text(note)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.warn)
                .lineLimit(2)
        } else {
            RunLAText.timer(state)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(clockColor)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }

    private var clockColor: Color { state.phase == .running ? palette.ink : palette.label }
}

/// 手錶：完成（綠勾＋「完成」，下面 finishedLine 最多兩行）
struct RunLASmallFinished: View {
    let line: String
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.good)
                Text("完成")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.ink)
            }
            Text(line)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 靈動島（底是黑的：字白、運動色用深色那一組）

/// 縮起左邊「[跑者] 3.42」（暫停中圖示換 ⏸）
struct RunLACompactLeading: View {
    let attributes: RunActivityAttributes
    let state: RunActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: RunLAText.islandIcon(attributes, state))
                .font(.system(size: 13, weight: .semibold))
            // 「42.19」這種五個字的距離在比較窄的機型也不要被切成「42…」：放不下時縮小一點
            Text(state.distanceText)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(RunLAColors.sport(attributes.sport, dark: true))
    }
}

/// 縮起右邊「21:05」：計時字會撐滿，一定固定寬（58：「1:05:12」也放得下），靠右
struct RunLACompactTrailing: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        RunLAText.timer(state)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .frame(width: 58, alignment: .trailing)
    }

    private var color: Color { state.phase == .running ? Color.white : Color.white.opacity(0.55) }
}

/// 只剩一點位置：只有跑者（暫停中 ⏸）
struct RunLAMinimal: View {
    let attributes: RunActivityAttributes
    let state: RunActivityAttributes.ContentState

    var body: some View {
        Image(systemName: RunLAText.islandIcon(attributes, state))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(RunLAColors.sport(attributes.sport, dark: true))
    }
}

/// 展開左上：「[跑者] 晨跑・跑步中」（高度對齊右邊 34 的圓鈕）
struct RunLAExpandedLeading: View {
    let attributes: RunActivityAttributes
    let state: RunActivityAttributes.ContentState

    var body: some View {
        Label(attributes.headline(state), systemImage: attributes.sport.icon)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(RunLAColors.sport(attributes.sport, dark: true))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(minHeight: 34)
            .padding(.leading, 6)
    }
}

/// 展開右上：暫停鈕（直徑 34、白 0.18 底、白圖示）；完成時不畫
struct RunLAExpandedTrailing: View {
    let attributes: RunActivityAttributes
    let state: RunActivityAttributes.ContentState

    var body: some View {
        if state.phase != .finished {
            RunLAPauseButton(attributes: attributes, state: state, diameter: 34,
                             fill: Color.white.opacity(0.18), iconColor: Color.white)
                .padding(.trailing, 6)
        }
    }
}

/// 展開下面：三個數字（過期時多一行黃字）；完成時一列綠勾（結束後系統會從靈動島拿掉，這是保險）。
/// 高度 ≈ 34（上面那一列）＋ 8 ＋ 41 ＋ 4 ＋ 26 ≈ 113（上限 160）
struct RunLAExpandedBottom: View {
    let state: RunActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        content
            .padding(.horizontal, 6)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private var content: some View {
        if state.phase == .finished {
            RunLAFinishedRow(line: state.finishedLine ?? "", size: 15,
                             ink: Color.white, good: RunLAColors.islandGood)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                RunLAFigureRow(state: state, style: RunLAFigureStyle.island(running: state.phase == .running))
                RunLAIslandStaleLine(state: state, isStale: isStale)
            }
        }
    }
}

/// 靈動島展開：過期那一行（11 pt、黃）；沒過期不畫
struct RunLAIslandStaleLine: View {
    let state: RunActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if let note = RunLAText.staleLine(state, isStale: isStale) {
            Text(note)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RunLAColors.islandWarn)
                .lineLimit(2)
        }
    }
}
