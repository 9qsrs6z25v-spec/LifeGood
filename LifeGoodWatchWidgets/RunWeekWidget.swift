import SwiftUI
import WidgetKit

// MARK: - 錶面「這週跑步」（手錶 v5，v25.582；watch/judge.md §3.1、§2.17、§6.1；watch/build/v5/brief.md §2、G4）
//
// 只屬於 LifeGoodWatchWidgets。**RunWeekEntry、RunWeekProvider、RunWeekWidget 主控寫好（不准改）；RunWeekWidgetView 以下 G4 填。**
// 四個形狀（字全部是 WatchRunWeekText.face 組好的 WatchRunFace，這裡只排版）：
//   • 圓形：環 73%（Gauge accessoryCircularCapacity）、中間「14.6」、下面「跑」；達標環滿＋小 ✓；沒設目標不畫環（只有字）
//   • 角落：跑者圖示＋沿邊量表「14.6／20」（widgetLabel）；**點了直接到準備頁**（WidgetLink.healthRun）
//   • 一行字：跑者圖示＋「14.6／20 公里・連續 6 週」
//   • 長方形（也能放進智慧型堆疊）：「這週 14.6／20 公里」／一到日 7 根小柱（EB6834、線 ≥ 2 點）／「3 次・連續 6 週・剩 4 天」
//   圓形、一行字、長方形點了開 ③ 跑步（WidgetLink.health(nil)）。
// 隱私（§2.17、§6.1）：只有公里、次數、天數、連續週數（可以上鎖定畫面，手腕放下照樣顯示）；**不寫名字、不畫路線**。
// 時間軸：現在＋往後每天 00:00（7 天，含下週一 00:00 歸零那一筆；週日不歸零）——不用等 iPhone（WatchRunWeekText.faceDates）。
// 手錶跑完一趟（WatchRunLog 變了）WatchSync.reloadRunWeekWidget 馬上重畫；iPhone 送新包時 runWeek 變了才重畫（WatchPackageDiff）。
// 每一格最外層 .containerBackground(for: .widget)（少了整格變成系統的英文提示，judge §7.8-10）。

/// 一筆 entry：那一刻＋那一刻的字（provider 算好；View 不讀檔）
struct RunWeekEntry: TimelineEntry {
    let date: Date
    let face: WatchRunFace
}

/// 這週跑步：讀包、手錶自己記的那幾趟、上一次用的運動（手錶 App Group）一次，往後每天 00:00 各算一份
struct RunWeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> RunWeekEntry {
        RunWeekEntry(date: Date(), face: WatchRunWeekText.face(package: nil, own: [], now: Date(), lastSport: nil))
    }

    func getSnapshot(in context: Context, completion: @escaping (RunWeekEntry) -> Void) {
        let now = Date()
        completion(RunWeekEntry(date: now, face: Self.face(at: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RunWeekEntry>) -> Void) {
        let now = Date()
        let package = WidgetSnapshotStore.read(WatchPackage.self)
        let own = WatchRunLog.all()
        let last = WatchRunPrefs.lastSport
        let entries: [RunWeekEntry] = WatchRunWeekText.faceDates(now: now).map { d in
            RunWeekEntry(date: d, face: WatchRunWeekText.face(package: package, own: own, now: d, lastSport: last))
        }
        completion(Timeline(entries: entries, policy: .after(WatchRunWeekText.faceReloadAt(now: now))))
    }

    /// 現在那一份（快照）
    private static func face(at now: Date) -> WatchRunFace {
        WatchRunWeekText.face(package: WidgetSnapshotStore.read(WatchPackage.self), own: WatchRunLog.all(),
                              now: now, lastSport: WatchRunPrefs.lastSport)
    }
}

struct RunWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchWidgetKind.runWeek, provider: RunWeekProvider()) { entry in
            RunWeekWidgetView(entry: entry)
        }
        .configurationDisplayName("這週跑步")
        .description("這週跑了幾公里、離目標還差多少；角落那一格點了直接到開始跑步")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

// MARK: - G4 填（下面這個 View 的名字與參數不准改）

//
// [G4] 四個形狀都只排 entry.face（WatchRunWeekText.face 組好的字與數字），不讀檔、不算公里、不拼字；
// 不碰名字、亮點、路線（judge §2.17、§6.1：錶面＝鎖定畫面，只有公里、次數、天數、連續週數）。
// 手腕放下不另外處理（只有數字，照樣顯示）；著色錶面靠字和形狀分（環、柱、✓），不靠顏色。
//   • 圓形：有目標＝Gauge .accessoryCircularCapacity（環＝face.ring）＋「14.6」＋「跑」（達標換 ✓）；
//           沒目標／沒收過＝AccessoryWidgetBackground 小圓底＋圖示＋「9.4」＋「跑」，不畫環
//   • 角落：中間跑者圖示；widgetLabel 沿邊量表，兩端「14.6」…「20」（face.corner 在「／」拆開）；
//           沒目標／沒收過＝沿邊彎字 face.corner（「9.4 公里」「—」）
//   • 一行字：Label(face.inline, systemImage: 運動圖示)
//   • 長方形：「🏃 這週 14.6／20 公里」／一到日 7 根小柱（有公里運動色、沒有 2 點的線）／「3 次・連續 6 週・剩 4 天」

/// 一筆 entry 的畫面：挑形狀、帶網址（角落→準備頁，其他→③ 跑步）；最外層是 widget 用的夜空底（錶面上系統會拿掉，堆疊裡看得到）
struct RunWeekWidgetView: View {
    let entry: RunWeekEntry

    @Environment(\.widgetFamily) private var family

    /// 角落的跑者點了直接到準備頁（WatchModel.open(.healthRun) → openRunPrep）；其他形狀開 ③ 跑步
    private var url: URL {
        family == .accessoryCorner ? WidgetLink.healthRun : WidgetLink.health(nil)
    }

    var body: some View {
        content
            .widgetURL(url)
            .containerBackground(for: .widget) {
                WatchWidgetStyle.sky
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            RunWeekCircular(face: entry.face)
        case .accessoryCorner:
            RunWeekCorner(face: entry.face)
        case .accessoryInline:
            Label(entry.face.inline, systemImage: entry.face.sport.icon)
        default:
            RunWeekRect(sport: entry.face.sport,
                        heading: entry.face.title,
                        bars: entry.face.bars,
                        todayIndex: entry.face.todayIndex,
                        line3: entry.face.line3)
        }
    }
}

// MARK: - 圓形：環 73%＋「14.6」＋「跑」（達標換 ✓）；沒目標不畫環

private struct RunWeekCircular: View {
    let face: WatchRunFace

    private var tint: Color { WatchWidgetStyle.color(face.sport.tint) }

    var body: some View {
        if let ring = face.ring {
            Gauge(value: ring, in: 0...1) {
                EmptyView()
            } currentValueLabel: {
                RunWeekRingLabel(face: face)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(tint)
            .accessibilityLabel(Text(face.inline))
        } else {
            RunWeekPlainCircle(face: face)
        }
    }
}

/// 圓形中間的大數字「14.6」（沒收過「—」）
private struct RunWeekNumber: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// 圓形下面那個小字「跑」「騎」
private struct RunWeekCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// 環裡面：「14.6」＋「跑」；達標（環滿）時「跑」換成小 ✓
private struct RunWeekRingLabel: View {
    let face: WatchRunFace

    var body: some View {
        VStack(spacing: 0) {
            RunWeekNumber(text: face.big)
            belowView
        }
    }

    @ViewBuilder
    private var belowView: some View {
        if face.reached {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .widgetAccentable()
        } else {
            RunWeekCaption(text: face.caption)
        }
    }
}

/// 沒設目標、沒收過 iPhone 的這週跑步：系統小圓底＋運動圖示＋「9.4」＋「跑」（不畫環）
private struct RunWeekPlainCircle: View {
    let face: WatchRunFace

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: face.sport.icon)
                    .font(.system(size: 9, weight: .semibold))
                    .widgetAccentable()
                RunWeekNumber(text: face.big)
                RunWeekCaption(text: face.caption)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(face.inline))
    }
}

// MARK: - 角落：中間跑者，沿邊量表「14.6」…「20」（點了直接到準備頁，網址在 RunWeekWidgetView）

private struct RunWeekCorner: View {
    let face: WatchRunFace

    private var tint: Color { WatchWidgetStyle.color(face.sport.tint) }

    /// 量表兩端的字；沒目標、沒收過（face.corner 沒有「／」）是 nil
    private var ends: RunWeekCornerEnds? { RunWeekCornerEnds(face.corner) }

    var body: some View {
        Image(systemName: face.sport.icon)
            .font(.system(size: 20, weight: .semibold))
            .widgetAccentable()
            .widgetLabel {
                edge
            }
            .accessibilityLabel(Text(face.inline))
    }

    /// 沿邊那一條：有目標＝量表（角落的量表系統畫兩端的字，所以「14.6」「20」放兩端）；沒目標＝彎字「9.4 公里」
    @ViewBuilder
    private var edge: some View {
        if let ring = face.ring, let e = ends {
            Gauge(value: ring, in: 0...1) {
                EmptyView()
            } currentValueLabel: {
                Text(face.corner)
            } minimumValueLabel: {
                Text(e.low)
            } maximumValueLabel: {
                Text(e.high)
            }
            .tint(tint)
        } else if let ring = face.ring {
            Gauge(value: ring, in: 0...1) {
                EmptyView()
            } currentValueLabel: {
                Text(face.corner)
            }
            .tint(tint)
        } else {
            Text(face.corner)
        }
    }
}

/// 角落量表兩端的字：face.corner「14.6／20」→ 前「14.6」、後「20」（只拆開 WatchRunWeekText 組好的字，不自己算）
private struct RunWeekCornerEnds {
    let low: String
    let high: String

    /// 沒有「／」（沒目標「9.4 公里」、沒收過「—」）或拆出空字串就是 nil
    init?(_ corner: String) {
        let sep: Character = "／"
        guard let i = corner.firstIndex(of: sep) else { return nil }
        let a = String(corner[..<i])
        let b = String(corner[corner.index(after: i)...])
        guard !a.isEmpty, !b.isEmpty else { return nil }
        low = a
        high = b
    }
}

// MARK: - 長方形（也能放進智慧型堆疊）：「這週 14.6／20 公里」／7 根小柱／「3 次・連續 6 週・剩 4 天」

private struct RunWeekRect: View {
    let sport: WatchSport
    /// 「這週 14.6／20 公里」（沒收過「LifeGood」）
    let heading: String
    /// 週一到週日 0～1
    let bars: [Double]
    let todayIndex: Int
    /// 「3 次・連續 6 週・剩 4 天」（沒收過「打開 iPhone 上的 App 一次」）
    let line3: String

    private var tint: Color { WatchWidgetStyle.color(sport.tint) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            RunWeekRectHead(icon: sport.icon, text: heading)
            RunWeekMiniBars(bars: bars, today: todayIndex, tint: tint)
            RunWeekRectFoot(text: line3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 第一行：運動圖示＋「這週 14.6／20 公里」
private struct RunWeekRectHead: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .widgetAccentable()
    }
}

/// 第三行：「3 次・連續 6 週・剩 4 天」
private struct RunWeekRectFoot: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// 一到日 7 根小柱（高 14 點，底對齊）：有公里＝運動色、高度照 face.bars；沒有＝2 點的線（brief G4-1：一律 secondary 40%，樣稿②每天都一樣）
private struct RunWeekMiniBars: View {
    let bars: [Double]
    /// 今天是第幾根（週一 0）；brief 的簽章照帶，顏色不分今天前後（樣稿沒分，20% 在錶面上幾乎看不到）
    let today: Int
    let tint: Color

    private static let fullHeight: CGFloat = 14
    /// 線至少 2 點（judge §3.1）
    private static let lineHeight: CGFloat = 2
    /// 沒有公里那一天的線（brief G4-1「0 的 Color.secondary.opacity(0.4)」）
    private static let emptyColor: Color = Color.secondary.opacity(0.4)

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<7, id: \.self) { i in
                bar(i)
            }
        }
        .frame(height: Self.fullHeight, alignment: .bottom)
        .accessibilityHidden(true)
    }

    /// 第 i 根的高（0～1，夾好；缺的、不是數字的當 0）
    private func level(_ i: Int) -> Double {
        guard i >= 0, i < bars.count else { return 0 }
        let h = bars[i]
        return h.isFinite ? min(1, max(0, h)) : 0
    }

    private func barHeight(_ level: Double) -> CGFloat {
        max(Self.lineHeight, Self.fullHeight * CGFloat(level))
    }

    @ViewBuilder
    private func bar(_ i: Int) -> some View {
        let v = level(i)
        if v > 0 {
            RoundedRectangle(cornerRadius: 1)
                .fill(tint)
                .frame(maxWidth: .infinity)
                .frame(height: barHeight(v))
                .widgetAccentable()
        } else {
            RoundedRectangle(cornerRadius: 1)
                .fill(Self.emptyColor)
                .frame(maxWidth: .infinity)
                .frame(height: Self.lineHeight)
        }
    }
}
