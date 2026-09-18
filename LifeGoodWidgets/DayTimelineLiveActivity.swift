import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - 今日行程時間軸 · 靈動島（v25.377）
//
// 版面限制（Apple 的硬規則，不是設計選擇）：
//   • 展開區高度上限約 160pt，超過會被系統截掉
//   • 沒有捲動、沒有手勢；唯一能互動的是 Button／Toggle（iOS 17+ App Intent）
//   • 點靈動島＝開 App，長按＝展開。「點一下放大」是做不到的
//
// 所以時間軸上的每個點都是一顆 Button，按下去換 selectedIndex，
// 下方固定區塊顯示那一場的時間、標題與內容。
//
// [v25.383] 軸上混了三種來源：部屬會議（橘）、我的行事曆的個人事件（青）、
// iOS 系統行事曆（綠）。點的顏色與詳情的圖示都跟著來源走。

struct DayTimelineLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DayTimelineAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .widgetURL(DayTimelineLink.today)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                // [v25.382] 四個角是圓的，貼著邊放的內容會被切掉
                //（使用者回報「M608 ESH」的 M 不見了）。
                // 每一區都往內縮，DynamicIslandExpandedSpec.sidePadding 集中管理。
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.dayLabel, systemImage: "calendar")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.leading, DayTimelineLayout.sidePadding)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(countLabel(context.state))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, DayTimelineLayout.sidePadding)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        TimelineStrip(state: context.state)
                        StopDetail(stop: context.state.selected, roomy: true)
                    }
                    .padding(.horizontal, DayTimelineLayout.sidePadding)
                    .padding(.bottom, 2)
                }
            } compactLeading: {
                Image(systemName: "calendar.day.timeline.left")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text(DayTimelineFormat.compactTrailing(context.state))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.orange)
            } minimal: {
                Image(systemName: "calendar.day.timeline.left")
                    .foregroundStyle(.orange)
            }
            // [v25.381] 點一下開 App 是系統行為，改不了；但開到哪裡可以決定。
            // 導到「我的行事曆」——那就是這條時間軸的完整版。
            .widgetURL(DayTimelineLink.today)
            .keylineTint(.orange)
        }
    }

    /// 字串在 ViewBuilder 外組好
    private func countLabel(_ state: DayTimelineAttributes.ContentState) -> String {
        guard !state.stops.isEmpty else { return "沒有行程" }
        return "第 \(state.safeIndex + 1) / \(state.stops.count) 場"
    }
}

// MARK: - 時間軸

/// 一條軸、幾顆可按的點。點的位置依實際時間等比落在軸上，
/// 所以「上午擠、下午空」這種一天的形狀看得出來。
struct TimelineStrip: View {
    let state: DayTimelineAttributes.ContentState

    private let dotSize: CGFloat = 11
    private let selectedDotSize: CGFloat = 17
    /// 兩端各留半顆點的寬度，最前與最後一站才不會被切到
    private var inset: CGFloat { selectedDotSize / 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geo in
                let usable = max(0, geo.size.width - inset * 2)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 3)
                        .padding(.horizontal, inset)

                    // 現在時間的游標
                    if let p = state.nowPosition() {
                        Capsule()
                            .fill(Color.orange.opacity(0.85))
                            .frame(width: 2, height: 15)
                            .offset(x: inset + usable * p - 1)
                    }

                    ForEach(Array(state.stops.enumerated()), id: \.element.id) { index, stop in
                        dotButton(index: index, stop: stop, usable: usable)
                    }
                }
                .frame(height: selectedDotSize, alignment: .center)
            }
            .frame(height: selectedDotSize)

            HStack {
                Text(DayTimelineFormat.time(state.axisStart))
                Spacer()
                Text(DayTimelineFormat.time(state.axisEnd))
            }
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func dotButton(index: Int, stop: TimelineStop, usable: CGFloat) -> some View {
        let isOn = index == state.safeIndex
        let size = isOn ? selectedDotSize : dotSize
        let x = inset + usable * state.position(of: stop)
        Button(intent: SelectTimelineStopIntent(index: index)) {
            ZStack {
                // 觸控區比圓點大一圈：展開區不能捲動，點太小會按不到
                Color.clear.frame(width: 26, height: selectedDotSize + 6)
                Circle()
                    .fill(isOn ? DayTimelineStyle.color(stop.kind)
                               : DayTimelineStyle.color(stop.kind).opacity(0.5))
                    .frame(width: size, height: size)
                    .overlay(
                        Circle().stroke(Color.black.opacity(isOn ? 0.35 : 0), lineWidth: 1.5)
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: x - 13)
    }
}

// MARK: - 版面常數

/// [v25.382] 展開區的尺寸拿捏。
///
/// 兩個互相拉扯的限制：
///   • 四個角是圓的，貼邊的內容會被切掉 → 要往內縮
///   • 展開區總高度上限約 160pt，超過系統直接截掉下半 → 行數不能無限加
/// 下面的數字是照這兩件事抓的，改之前先把預估高度重算一次。
enum DayTimelineLayout {
    /// 左右內縮。圓角大約吃掉 10pt，留 8pt 再加上元件自身的 inset 就夠。
    static let sidePadding: CGFloat = 8

    /// 標題行數。原本 1 行，長會議名稱會被截掉一半。
    static let titleLines = 2
    /// 內容摘要行數。原本 2 行。
    static let detailLines = 3

    // 目前的高度預估（展開區）：
    //   時間軸  17（點）＋2＋11（時刻標籤） = 30
    //   間距                                =  7
    //   詳情    14（時間列）＋34（標題 2 行）＋39（摘要 3 行）＋4 = 91
    //   下方留白                            =  2
    //   合計 ≈ 130，加上頂端那一列約 22 → ≈ 152，壓在 160 的上限內。
}

// MARK: - 來源配色

/// [v25.380] 時間軸現在混了兩種來源，一眼要分得出來
enum DayTimelineStyle {
    static func color(_ kind: TimelineStopKind) -> Color {
        switch kind {
        case .meeting:       return .orange
        case .personal:      return .cyan
        case .appleCalendar: return .green
        }
    }

    static func icon(_ kind: TimelineStopKind) -> String {
        switch kind {
        case .meeting:       return "person.2.fill"
        case .personal:      return "calendar"
        case .appleCalendar: return "calendar.badge.clock"
        }
    }
}

// MARK: - 單場詳情

struct StopDetail: View {
    let stop: TimelineStop?
    /// [v25.382] 展開的靈動島空間比較多，標題與摘要可以多給幾行；
    /// 鎖定畫面沿用原本的緊湊版。
    var roomy: Bool = false

    init(stop: TimelineStop?, roomy: Bool = false) {
        self.stop = stop
        self.roomy = roomy
    }

    private var titleLines: Int { roomy ? DayTimelineLayout.titleLines : 1 }
    private var detailLines: Int { roomy ? DayTimelineLayout.detailLines : 2 }

    var body: some View {
        if let stop {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    // [v25.380] 來源圖示：部屬會議 vs 我的行事曆
                    Image(systemName: DayTimelineStyle.icon(stop.kind))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DayTimelineStyle.color(stop.kind))
                    Text(DayTimelineFormat.range(stop))
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(DayTimelineStyle.color(stop.kind))
                    // [v25.382] 多給一個時長，不用自己算
                    Text(DayTimelineFormat.duration(stop))
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                    if !stop.owner.isEmpty {
                        Text(stop.owner)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.white.opacity(0.14), in: Capsule())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer(minLength: 0)
                }
                Text(stop.title.isEmpty ? "未命名行程" : stop.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(titleLines)
                    .multilineTextAlignment(.leading)
                if !stop.detail.isEmpty {
                    Text(stop.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(detailLines)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("今天沒有有時間的行程")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 鎖定畫面／橫幅

struct LockScreenView: View {
    let attributes: DayTimelineAttributes
    let state: DayTimelineAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.day.timeline.left")
                    .font(.system(size: 12, weight: .semibold))
                Text(attributes.dayLabel)
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text(headline)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(.orange)

            TimelineStrip(state: state)
            StopDetail(stop: state.selected)
        }
        .padding(14)
    }

    private var headline: String {
        guard !state.stops.isEmpty else { return "沒有行程" }
        if let cur = state.currentStop() {
            return "進行中 · 到 " + DayTimelineFormat.time(cur.end)
        }
        if let next = state.nextStop() {
            return "下一場 " + DayTimelineFormat.time(next.start)
        }
        return "今日行程已結束"
    }
}
