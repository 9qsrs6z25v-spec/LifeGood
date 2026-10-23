import SwiftUI

// MARK: - 跑完摘要、存檔中、不到 1 分鐘（手錶 v4，v25.580；watch/judge.md §2.12、§2.17；watch/build/v4/brief.md G4-2）
//
// 只屬於 LifeGoodWatch。**骨架（主控寫）：名字 RunSummaryView() 不准改（RootView 的 RunFlowView 在叫）；G4 填內容。**
// RootView 的 RunFlowView 在 WorkoutManager.phase 是 ending／askShort／summary 時整個畫面換成這一頁（不是彈出頁，背景純黑）：
// • ending：「存進 Apple 健康中…」（轉圈）。
// • askShort（移動不到 1 分鐘）：「不到 1 分鐘，要存嗎？」〔存下來〕（照常存）〔丟掉〕（discardWorkout，回 ③）。
// • summary（可以捲；〔完成〕固定在最下面）：
//     ✓ 已存好（綠）／⚠︎ 還沒存進 Apple 健康（琥珀）
//     晨跑（時段名，不寫地名）／5.20 公里／32:04・配速 6'10"／♥ 平均 152・最高 171・340 大卡
//     路線小圖 80 點（手錶自己收的點，0～1 形狀、不打地圖；同一段相鄰兩點一條線，照那一公里的配速上色：藍快、琥珀慢、灰差不多；
//       暫停前後不連線）
//     每公里：6'05" 6'10" …／暫停 2 次・1:10（都是自動）／已存進 Apple 健康・iPhone 健康頁會自己帶進來／（出錯那一句，琥珀）
//     存好了〔不存這一趟〕（先問一次：Apple 健康裡這一趟會刪掉）；沒存好〔再存一次〕
//     〔完成〕→ 回 ③
// 字一律拿 WatchRunText.summary 的結果與 WatchRunText 的常數（View 不自己拼）。亮點那兩行（第 12 次、新紀錄）是 v5。
// 手腕放下（judge §2.17）：路線小圖換「路線已存進 Apple 健康」（還沒存好那一趟不寫這句、留同樣的高度：版面不跳）；
// 距離、時間、配速照顯示；字調暗、按鈕暫時不能按（不拿掉）。

struct RunSummaryView: View {
    @ObservedObject private var runs = WorkoutManager.shared
    @Environment(\.isLuminanceReduced) private var dimmed

    /// 〔不存這一趟〕先問一次
    @State private var asksDiscard = false

    /// 手腕放下時字調暗
    static let dimmedOpacity: Double = 0.75
    /// 路線小圖的高（judge §2.12）
    static let routeHeight: CGFloat = 80

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }

    /// 照 phase 換三種
    @ViewBuilder
    private var content: some View {
        switch runs.phase {
        case .ending:
            savingView
        case .askShort:
            shortView
        default:
            summaryView
        }
    }

    // MARK: 存進 Apple 健康中…

    private var savingView: some View {
        VStack(spacing: 8) {
            RunSavingMark(dimmed: dimmed)
            Text(WatchRunText.savingText)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .scenePadding(.horizontal)
        .opacity(dimmed ? Self.dimmedOpacity : 1)
    }

    // MARK: 不到 1 分鐘

    private var shortView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(WatchRunText.shortAsk)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WatchStyle.primary)
                    .fixedSize(horizontal: false, vertical: true)
                shortFacts
                saveShortButton
                discardShortButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scenePadding(.horizontal)
        }
        .opacity(dimmed ? Self.dimmedOpacity : 1)
    }

    /// 「0:42・配速 8'45"」：這一趟多短（WatchRunText.summary 的那一行）
    @ViewBuilder
    private var shortFacts: some View {
        if let r = runs.result {
            RunSummaryShortLine(summary: WatchRunText.summary(r, saved: false))
        }
    }

    /// 〔存下來〕：照常存進 Apple 健康
    private var saveShortButton: some View {
        Button {
            runs.saveShort()
        } label: {
            Text(WatchRunText.saveShortTitle)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(WatchStyle.go)
        .disabled(dimmed)
    }

    /// 〔丟掉〕：不存（「健身」App 也不會有這一筆）
    private var discardShortButton: some View {
        Button(role: .destructive) {
            runs.discardShort()
        } label: {
            Text(WatchRunText.discardShortTitle)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(dimmed)
    }

    // MARK: 摘要

    @ViewBuilder
    private var summaryView: some View {
        if let r = runs.result {
            summaryScroll(WatchRunText.summary(r, saved: runs.saved), canDiscard: r.workoutId != nil)
        } else {
            // 不該發生（摘要一定有那一趟）：至少留〔完成〕，不會卡在這一頁
            VStack {
                Spacer(minLength: 0)
                doneBar
            }
        }
    }

    /// canDiscard：真的拿到 Apple 健康那一筆（有編號）才能〔不存這一趟〕（存好了但讀不到那一筆時刪不了，不出這顆）
    private func summaryScroll(_ s: WatchRunSummary, canDiscard: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                RunSummaryHead(summary: s)
                RunSummaryNumbers(summary: s)
                routeBlock(saved: s.saved)
                RunSummaryNotes(summary: s, problem: runs.problem)
                actionButton(s, canDiscard: canDiscard)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scenePadding(.horizontal)
            .opacity(dimmed ? Self.dimmedOpacity : 1)
        }
        .safeAreaInset(edge: .bottom) {
            doneBar
        }
        .alert(WatchRunText.discardSavedAsk, isPresented: $asksDiscard) {
            Button(WatchRunText.discardSavedYes, role: .destructive) {
                confirmDiscard()
            }
            Button(WatchRunText.cancelTitle, role: .cancel) { }
        }
    }

    /// 路線小圖（不到 2 點整塊不出現）；手腕放下換一句字（同樣高度）
    @ViewBuilder
    private func routeBlock(saved: Bool) -> some View {
        if runs.resultShape.count >= 2 {
            if dimmed {
                RunRouteHiddenText(saved: saved)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Self.routeHeight)
            } else {
                RunRouteShapeView(points: runs.resultShape)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.routeHeight)
                    .padding(.vertical, 2)
            }
        }
    }

    /// 沒存好〔再存一次〕；存好了〔不存這一趟〕
    @ViewBuilder
    private func actionButton(_ s: WatchRunSummary, canDiscard: Bool) -> some View {
        if !s.saved {
            Button {
                runs.retrySave()
            } label: {
                Text(WatchRunText.retryTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(runs.busy || dimmed)
            .padding(.top, 4)
        } else if canDiscard {
            Button {
                asksDiscard = true
            } label: {
                Text(WatchRunText.discardSavedTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(runs.busy || dimmed)
            .padding(.top, 4)
        }
    }

    /// 〔完成〕：最下面固定（捲上去的字從後面過，底色純黑擋住）
    private var doneBar: some View {
        Button {
            runs.finishSummary()
        } label: {
            Text(WatchRunText.doneTitle)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(WatchStyle.go)
        .disabled(dimmed)
        .opacity(dimmed ? Self.dimmedOpacity : 1)
        .scenePadding(.horizontal)
        .padding(.top, 4)
        .background(Color.black)
    }

    // MARK: 動作

    /// 〔刪掉〕：提示框收起來之後（下一個 runloop）才刪（閉包不抓這個 View，直接叫 shared）
    private func confirmDiscard() {
        Task { @MainActor in
            WorkoutManager.shared.discardSaved()
        }
    }
}

// MARK: - 存檔中的轉圈（手腕放下拿掉轉圈：不留一秒好幾次的動畫，換靜止的沙漏）

private struct RunSavingMark: View {
    let dimmed: Bool

    var body: some View {
        if dimmed {
            Image(systemName: "hourglass")
                .font(.title3)
                .foregroundStyle(WatchStyle.small)
        } else {
            ProgressView()
        }
    }
}

// MARK: - 頁首「✓ 已存好」／「⚠︎ 還沒存進 Apple 健康」

private struct RunSummaryHead: View {
    let summary: WatchRunSummary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: icon)
            Text(summary.head)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(color)
    }

    private var icon: String {
        summary.saved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var color: Color {
        summary.saved ? WatchStyle.saved : WatchStyle.amber
    }
}

// MARK: - 晨跑／5.20 公里／32:04・配速 6'10"／♥ 平均 152・最高 171・340 大卡

private struct RunSummaryNumbers: View {
    let summary: WatchRunSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
            bigRow
            Text(summary.line)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            heartRow
        }
    }

    /// 「5.20 公里」：大字 38（41mm 34）heavy rounded 等寬
    private var bigRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(summary.big)
                .font(WatchStyle.heroFont(compact: WatchStyle.isCompact))
                .monospacedDigit()
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(WatchRunText.kmUnit)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// 「♥ 平均 152・最高 171・340 大卡」；都沒有不畫
    @ViewBuilder
    private var heartRow: some View {
        if let line = summary.heartLine {
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
}

// MARK: - 不到 1 分鐘那一頁的「0:42・配速 8'45"」

private struct RunSummaryShortLine: View {
    let summary: WatchRunSummary

    var body: some View {
        Text(summary.line)
            .font(.footnote)
            .foregroundStyle(WatchStyle.small)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

// MARK: - 每公里、暫停、存到哪、出錯那一句

private struct RunSummaryNotes: View {
    let summary: WatchRunSummary
    let problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let splits = summary.splitsLine {
                note(splits)
            }
            if let pauses = summary.pauseLine {
                note(pauses)
            }
            note(summary.note)
            problemText
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(WatchStyle.small)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 上一個動作失敗的那一句（WorkoutManager.problem；琥珀）
    @ViewBuilder
    private var problemText: some View {
        if let problem {
            Text(problem)
                .font(.footnote)
                .foregroundStyle(WatchStyle.amber)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 手腕放下：路線小圖換一句字

private struct RunRouteHiddenText: View {
    /// 存好了才寫「路線已存進 Apple 健康」；還沒存好留空白（同樣高度）
    let saved: Bool

    var body: some View {
        Text(WatchRunText.routeHidden)
            .font(.footnote)
            .foregroundStyle(WatchStyle.small)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(saved ? 1 : 0)
    }
}

// MARK: - 路線小圖（Canvas：同一段相鄰兩點一條線，顏色照後一點那一公里的配速等級）

private struct RunRouteShapeView: View {
    let points: [WatchRunShapePoint]

    static let lineWidth: CGFloat = 3
    /// 線寬一半＋一點：圓頭不被切掉
    static let inset: CGFloat = 3

    var body: some View {
        // 畫布的閉包只抓值（點、留白、筆）：不碰這個 View 的東西
        let shape = points
        let inset = Self.inset
        let style = StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round)
        return Canvas { context, size in
            let frame = RunRouteFrame(size: size, inset: inset)
            guard shape.count >= 2, frame.side > 0 else { return }
            for i in 1..<shape.count {
                let a = shape[i - 1]
                let b = shape[i]
                guard a.seg == b.seg else { continue }
                var path = Path()
                path.move(to: frame.point(a))
                path.addLine(to: frame.point(b))
                context.stroke(path, with: .color(WatchStyle.pace(b.level)), style: style)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 0～1 的點放進畫布正中間的正方形（等比例、北在上；WatchRunMath.routeShape 已經置中）
private struct RunRouteFrame {
    let side: CGFloat
    let originX: CGFloat
    let originY: CGFloat

    init(size: CGSize, inset: CGFloat) {
        let s = min(size.width, size.height) - inset * 2
        side = s
        originX = (size.width - s) / 2
        originY = (size.height - s) / 2
    }

    func point(_ p: WatchRunShapePoint) -> CGPoint {
        let x = originX + CGFloat(p.x) * side
        let y = originY + CGFloat(p.y) * side
        return CGPoint(x: x, y: y)
    }
}
