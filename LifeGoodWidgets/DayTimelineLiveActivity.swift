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
// [v25.380] 軸上混了兩種來源：部屬會議（橘）與我的行事曆的個人事件（青），
// 點的顏色與詳情的圖示都跟著來源走。

struct DayTimelineLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DayTimelineAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .widgetURL(DayTimelineLink.today)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.dayLabel, systemImage: "calendar")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(countLabel(context.state))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        TimelineStrip(state: context.state)
                        StopDetail(stop: context.state.selected)
                    }
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
        VStack(alignment: .leading, spacing: 3) {
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

// MARK: - 來源配色

/// [v25.380] 時間軸現在混了兩種來源，一眼要分得出來
enum DayTimelineStyle {
    static func color(_ kind: TimelineStopKind) -> Color {
        switch kind {
        case .meeting:  return .orange
        case .personal: return .cyan
        }
    }

    static func icon(_ kind: TimelineStopKind) -> String {
        switch kind {
        case .meeting:  return "person.2.fill"
        case .personal: return "calendar"
        }
    }
}

// MARK: - 單場詳情

struct StopDetail: View {
    let stop: TimelineStop?

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
                    if !stop.owner.isEmpty {
                        Text(stop.owner)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.white.opacity(0.14), in: Capsule())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer(minLength: 0)
                }
                Text(stop.title.isEmpty ? "未命名行程" : stop.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !stop.detail.isEmpty {
                    Text(stop.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
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
