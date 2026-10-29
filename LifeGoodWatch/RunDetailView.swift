import SwiftUI

// MARK: - 那一趟（手錶 v5，v25.582；watch/judge.md §2.12、§2.13、§2.17；watch/build/v5/brief.md G3-2）
//
// 只屬於 LifeGoodWatch。名字 RunDetailView(runId:) 不准改（RootView 的 WatchRoute.runDetail 在叫）。只 import SwiftUI：
// **沒有地圖框架、不畫地圖**（pbxwatch_check R 段擋）。
// 第二層（這週點一列推進來：WatchModel.openRunDetail；背景純黑）：
//   「河濱晨跑」（Title3 20 semibold）＋右邊「今天 06:05」／「5.20 公里」（大字 38、41mm 34）／「32:04・配速 6'10"」／
//   「♥ 平均 152・最高 171」（手錶記的才有）
//   亮點（RunHighlightLinesView，跑完摘要也用）：「河濱老路線・第 12 次・比上次快 42 秒」（「比上次快 42 秒」綠 5BD99A；慢、差不多灰）／
//     「★ 最快 5 公里 新紀錄 30:51（快 18 秒）」（琥珀 FFC14D）／手錶記的、iPhone 還沒帶進來：灰字「第幾次、破紀錄，iPhone 帶進來後會算好」
//   路線小圖 72 點：0～1000 相對形狀（WatchRunShapeXY；Canvas 畫，同一段相鄰兩點一條線、運動色、不打地圖、沒有經緯度）
// 字全部是 WatchRunWeekText.detail 組好的。什麼都不能改（改名、刪除在 iPhone 健康頁）：沒有按鈕。
// 手腕放下（§2.17）：名字換 privateTitle、亮點用 privateLines（「老路線・第 12 次」）、小圖換一行「路線在 iPhone 健康頁」（同樣高度）；
//   公里、時間、配速、心率照顯示（§6.1）；字 0.75。
// 找不到（過了週一、iPhone 刪掉了）：「這一趟不在這週了」。

struct RunDetailView: View {
    let runId: String

    @ObservedObject private var model = WatchModel.shared
    @Environment(\.isLuminanceReduced) private var dimmed

    /// 手腕放下時字調暗
    static let dimmedOpacity: Double = 0.75

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .navigationTitle(WatchRunWeekText.detailTitle)
        .containerBackground(Color.black, for: .navigation)
    }

    // MARK: 內容

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let d = findDetail(now: now) {
            detailScroll(d)
        } else {
            goneView
        }
    }

    /// 包裡這週那幾趟＋手錶自己記的（WatchRunWeekText.detail）
    private func findDetail(now: Date) -> WatchRunDetail? {
        WatchRunWeekText.detail(id: runId, package: model.package, own: WatchRunLog.all(), now: now)
    }

    private func detailScroll(_ d: WatchRunDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                RunDetailHead(title: dimmed ? d.privateTitle : d.title, when: d.when)
                RunDetailBig(big: d.big)
                lineText(d.line)
                heartRow(d.heartLine)
                highlights(dimmed ? d.privateLines : d.lines)
                shapeBlock(d)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scenePadding(.horizontal)
            .opacity(dimmed ? Self.dimmedOpacity : 1)
        }
    }

    /// 「32:04・配速 6'10"」（騎車「1:02:10・時速 21.5」）
    private func lineText(_ line: String) -> some View {
        Text(line)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(WatchStyle.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// 「♥ 平均 152・最高 171」；沒有（內建體能訓練、iPhone 記的）不畫
    @ViewBuilder
    private func heartRow(_ line: String?) -> some View {
        if let line {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(WatchStyle.heart)
                Text(line)
                    .foregroundStyle(WatchStyle.small)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.footnote)
        }
    }

    /// 亮點兩行（抬手、手腕放下兩份已經照 dimmed 挑好）；什麼都沒有不畫
    @ViewBuilder
    private func highlights(_ lines: WatchRunHighlightLines) -> some View {
        if !lines.isEmpty {
            RunHighlightLinesView(lines: lines)
                .padding(.top, 2)
        }
    }

    /// 路線小圖（不到 2 點整塊不出現）；手腕放下換一行字（同樣高度）
    @ViewBuilder
    private func shapeBlock(_ d: WatchRunDetail) -> some View {
        if d.shape.count >= 2 {
            RunDetailShapeBlock(points: d.shape, tint: WatchStyle.sport(d.sport), hidden: d.shapeHidden, dimmed: dimmed)
        }
    }

    /// 找不到：「這一趟不在這週了」
    private var goneView: some View {
        ScrollView {
            Text(WatchRunWeekText.detailGone)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .scenePadding(.horizontal)
                .opacity(dimmed ? Self.dimmedOpacity : 1)
        }
    }
}

// MARK: - 亮點兩行（「那一趟」、跑完摘要共用；judge §2.12、§2.13）

/// 「河濱老路線・第 12 次・比上次快 42 秒」（後半快＝綠、慢或差不多＝灰）／「★ 最快 5 公里 新紀錄 30:51（快 18 秒）」（琥珀）／
/// 灰字「第幾次、破紀錄，iPhone 帶進來後會算好」。字全部是 WatchRunWeekText 組好的（WatchRunHighlightLines），
/// 手腕放下那一份（不寫地名）由叫的人挑好再傳進來
struct RunHighlightLinesView: View {
    let lines: WatchRunHighlightLines

    /// routeHead 跟 routeDelta 中間（同 WatchRunWeekText 其他字的分隔）
    static let joiner = "・"
    static let recordIcon = "star.fill"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            routeText
            recordRow
            pendingText
        }
    }

    /// 「河濱老路線・第 12 次」＋「・比上次快 42 秒」（同一段字、可以折行）
    @ViewBuilder
    private var routeText: some View {
        if let head = lines.routeHead {
            routeLine(head)
                .font(.footnote.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func routeLine(_ head: String) -> Text {
        let headText: Text = Text(head).foregroundStyle(WatchStyle.primary)
        guard let delta = lines.routeDelta else { return headText }
        let deltaText: Text = Text(Self.joiner + delta).foregroundStyle(deltaColor)
        return headText + deltaText
    }

    /// 快＝綠 5BD99A；慢、差不多＝灰
    private var deltaColor: Color {
        lines.deltaTone == .green ? WatchStyle.saved : WatchStyle.small
    }

    /// 「★ 最快 5 公里 新紀錄 30:51（快 18 秒）」；沒破不畫
    @ViewBuilder
    private var recordRow: some View {
        if let record = lines.recordLine {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Image(systemName: Self.recordIcon)
                    .font(.system(size: 11, weight: .semibold))
                Text(record)
                    .font(.footnote.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(WatchStyle.amber)
        }
    }

    /// iPhone 還沒帶進來：灰字（不寫假的）
    @ViewBuilder
    private var pendingText: some View {
        if let note = lines.pending {
            Text(note)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 「河濱晨跑」＋右邊「今天 06:05」

private struct RunDetailHead: View {
    let title: String
    let when: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            // 名字長的時候先縮、再截；右邊的時間一定寫完整
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            Text(when)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: - 「5.20 公里」：大字 38（41mm 34）heavy rounded 等寬

private struct RunDetailBig: View {
    let big: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(big)
                .font(WatchStyle.heroFont(compact: WatchStyle.isCompact))
                .monospacedDigit()
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(WatchRunText.kmUnit)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: - 小圖那一塊（高 72；抬手畫形狀、手腕放下一行字，版面不跳）

private struct RunDetailShapeBlock: View {
    let points: [WatchRunShapeXY]
    let tint: Color
    /// 「路線在 iPhone 健康頁」
    let hidden: String
    let dimmed: Bool

    /// 小圖的高（judge §2.13「路線小圖 72 點」）
    static let height: CGFloat = 72

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.height)
            .padding(.vertical, 2)
    }

    @ViewBuilder
    private var content: some View {
        if dimmed {
            Text(hidden)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            RunShapeOutline(points: points, tint: tint)
        }
    }
}

// MARK: - 路線形狀（Canvas：0～1000 相對座標放進正中間的正方形，同一段相鄰兩點一條線；單一運動色，沒有地圖）

private struct RunShapeOutline: View {
    let points: [WatchRunShapeXY]
    let tint: Color

    static let lineWidth: CGFloat = 3
    /// 線寬一半＋一點：圓頭不被切掉
    static let inset: CGFloat = 3
    /// WatchRunShapeXY 的滿格（0～1000）
    static let full = 1000

    var body: some View {
        // 畫布的閉包只抓值（點、顏色、留白、筆）：不碰這個 View 的東西
        let shape = points
        let color = tint
        let inset = Self.inset
        let full = Self.full
        let style = StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round)
        return Canvas { context, size in
            let side = min(size.width, size.height) - inset * 2
            guard shape.count >= 2, side > 0 else { return }
            let frame = RunShapeFrame(side: side, offX: (size.width - side) / 2, offY: (size.height - side) / 2,
                                      full: full)
            var path = Path()
            for i in 0..<shape.count {
                let p = shape[i]
                if i > 0 && shape[i - 1].s == p.s {
                    path.addLine(to: frame.point(p))
                } else {
                    path.move(to: frame.point(p))
                }
            }
            context.stroke(path, with: .color(color), style: style)
        }
        .accessibilityHidden(true)
    }
}

/// 0～1000 → 畫布上的點（等比例、置中；iPhone 已經把形狀放正中間、北在上）
private struct RunShapeFrame {
    let side: CGFloat
    let offX: CGFloat
    let offY: CGFloat
    /// 滿格（1000）
    let full: Int

    func point(_ p: WatchRunShapeXY) -> CGPoint {
        let x = CGFloat(min(max(p.x, 0), full)) / CGFloat(full) * side + offX
        let y = CGFloat(min(max(p.y, 0), full)) / CGFloat(full) * side + offY
        return CGPoint(x: x, y: y)
    }
}
