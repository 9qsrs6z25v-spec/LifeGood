import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - 照片匯入 · 靈動島（v25.483）
//
// 使用者指定：跳出 App 到別的軟體時，靈動島顯示百分比。
//
// 收合狀態只有一個圖示加一小段文字的寬度，所以那裡就放百分比；
// 長按展開才寫得下「存到哪裡、第幾張、進度條」。

struct PhotoImportLiveActivityWidget: Widget {
    private let tint = Color(red: 0.62, green: 0.40, blue: 0.95)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PhotoImportAttributes.self) { context in
            LockScreenView(state: context.state, tint: tint)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(tint)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.label, systemImage: "photo.badge.arrow.down.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.finished ? "完成" : context.state.countText)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressBar(fraction: context.state.fraction, tint: tint)
                        Text(context.state.finished
                             ? "照片已經存好了"
                             : "iCloud 的原圖要先下載回來，可以先去忙別的")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)
                }
            } compactLeading: {
                Image(systemName: "photo.badge.arrow.down.fill")
                    .foregroundStyle(tint)
            } compactTrailing: {
                Text(context.state.finished ? "完成" : context.state.percentText)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
            } minimal: {
                // 最小化時只剩一顆圓：畫成環狀進度比放圖示有用
                MinimalRing(fraction: context.state.fraction, tint: tint)
            }
            .keylineTint(tint)
        }
    }
}

// MARK: - 零件

private struct ProgressBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.6)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(3, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
    }
}

private struct MinimalRing: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(1)
    }
}

private struct LockScreenView: View {
    let state: PhotoImportAttributes.ContentState
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: state.finished
                      ? "checkmark" : "photo.badge.arrow.down.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(state.finished ? "照片已經存好了" : "正在取得照片")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Text(state.finished ? state.countText : state.percentText)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(tint)
                }
                ProgressBar(fraction: state.fraction, tint: tint)
                Text(state.finished
                     ? state.label
                     : state.label + "・" + state.countText + "（iCloud 的原圖要先下載）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
    }
}
