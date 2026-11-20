import SwiftUI
import WidgetKit

// MARK: - 大方塊（systemLarge）共用（v25.631 large1）
//
// 只屬於「LifeGoodWidgets」target。規格見 scratchpad/radar/judge_largewidgets.md §C、
// scratchpad/radar/build/large1/brief.md（主控定案）；示意圖 scratchpad/largewidgets/{bills,vehicle,travel}.html。
// 總設計先做好的共用部分，G1（接下來要繳）、G2（我的車）、G3（旅行）只呼叫、不改這個檔。
//
// 這個檔提供：
//   • LargeWidgetFit        依可用高度算列數的共用純函式（參考高度、餘裕、候選去重補滿 4 個）
//   • LargeWeekBucket       「這週／下週／之後」日期分組（週的第一天照 Calendar.firstWeekday，台灣是週日）
//   • BillsLargeLayout／VehicleLargeLayout／TravelLargeLayout
//                           三張大方塊每一塊的固定高度與「放幾列」的純函式（sim_large1.py 一個函式一個函式對照）
//   • LargeWidgetTitleLine／LargeWidgetSectionLabel／LargeWidgetFooterLine／LargeWidgetCardBackground／
//     LargeWidgetTintBar／LargeWidgetBar／LargeWidgetRing
//                           表頭、區標、頁腳、列的底、色條、進度條、進度環
//
// 做法（judge_largewidgets.md「共用版型」）：
//   每一塊都用 .frame(height: XxxLargeLayout.某某Height) 固定高度，所以「放得下幾列」可以先算：
//   plan(available:) 從最多列往下試，第一個放得下的就是答案。候選＝四個參考高度各算一次、去重、補滿 4 個，
//   View 用 ViewThatFits(in: .vertical) 由上往下挑（字級不變、只砍列數；不巢狀 ViewThatFits）。
//   這裡**不用 GeometryReader 量高度**（LargeWidgetBar 自己有一個，所以外面不准再包 GeometryReader）。
//   不用 Swift Charts、Canvas、AnyView。View 裡不讀 UserDefaults、不呼叫 Date()。

// MARK: - 依可用高度算列數（共用）

enum LargeWidgetFit {
    /// 參考的內容高度（大方塊扣掉上下各 16pt 內距）：
    /// 6.7 吋 364×382 → 350、6.1 吋 338×354 → 322、SE 321×324 → 292、iPad mini 305.5×305.5 → 273.5
    static let referenceHeights: [CGFloat] = [350, 322, 292, 273.5]
    /// 留給字型、四捨五入的餘裕：total ≤ available − slack 才算放得下
    static let slack: CGFloat = 2
    /// ViewThatFits 固定 4 個候選（不夠的重複最後一個）
    static let candidateCount = 4

    static func fits(_ total: CGFloat, in available: CGFloat) -> Bool {
        total <= available - slack
    }

    /// n 列（列高 rowHeight、列距 spacing）疊起來多高；n ≤ 0 是 0
    static func stack(rows n: Int, rowHeight: CGFloat, spacing: CGFloat) -> CGFloat {
        guard n > 0 else { return 0 }
        let rows: CGFloat = CGFloat(n) * rowHeight
        let gaps: CGFloat = CGFloat(n - 1) * spacing
        return rows + gaps
    }

    /// 每個參考高度各算一次 plan，照順序去重，補滿 candidateCount 個
    static func candidates<P: Equatable>(_ plan: (CGFloat) -> P) -> [P] {
        var out: [P] = []
        for h in referenceHeights {
            let p: P = plan(h)
            if !out.contains(p) {
                out.append(p)
            }
        }
        return padded(out)
    }

    /// 補滿 candidateCount 個（重複最後一個）；多的砍掉；空陣列原樣回傳
    static func padded<P>(_ list: [P]) -> [P] {
        guard let last = list.last else { return list }
        var out: [P] = Array(list.prefix(candidateCount))
        while out.count < candidateCount {
            out.append(last)
        }
        return out
    }
}

// MARK: - 這週／下週／之後

/// 接下來要繳（大）的分組。只看日曆天，不算錢
enum LargeWeekBucket: Int {
    case thisWeek = 0
    case nextWeek = 1
    case later = 2

    /// 區標：「這週」「下週」「之後」
    var title: String {
        switch self {
        case .thisWeek: return "這週"
        case .nextWeek: return "下週"
        case .later:    return "之後"
        }
    }

    /// due 落在哪一區：今天所在那一週（週的第一天照 calendar.firstWeekday；台灣地區是週日）＝這週、
    /// 再下一個 7 天＝下週、其他＝之後。due 是扣款日那天 00:00（比今天早的不會進來，進來也算這週）
    static func of(_ due: Date, now: Date, calendar: Calendar = Calendar.current) -> LargeWeekBucket {
        let fallback: Date = calendar.startOfDay(for: now)
        let weekStart: Date = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? fallback
        guard let next = calendar.date(byAdding: .day, value: 7, to: weekStart),
              let afterNext = calendar.date(byAdding: .day, value: 14, to: weekStart) else {
            return .later
        }
        if due < next { return .thisWeek }
        if due < afterNext { return .nextWeek }
        return .later
    }
}

// MARK: - 接下來要繳（大）的高度

/// 表頭「接下來 30 天／9 件」→（區標「這週」→ 列…）…→ 頁腳「再來 12/15 Spotify 等 4 件」。
/// 有區標的版本最少要放得下 labeledMinRows 列（或全部），不然改成不畫區標、多放幾列
enum BillsLargeLayout {
    /// 表頭（「接下來 30 天」12pt＋「9 件」28pt）
    static let headerHeight: CGFloat = 52
    /// 區標一塊：上面空 7＋「這週」10.5pt＋下面空 3
    static let sectionHeaderHeight: CGFloat = 24
    static let sectionLabelBottomGap: CGFloat = 3
    /// 不畫區標時表頭下面空多少
    static let compactTopGap: CGFloat = 7
    /// 一列（名稱 12.5pt＋小字 10pt，兩行）
    static let rowHeight: CGFloat = 38
    static let rowSpacing: CGFloat = 4
    /// 左邊色條高
    static let tintBarHeight: CGFloat = 26
    /// 頁腳（至少空 6＋一行 10pt）；全部列完了不畫
    static let footerHeight: CGFloat = 20
    static let maxRows = 7
    static let labeledMinRows = 4

    struct Plan: Equatable {
        /// 畫前幾列
        let rows: Int
        /// 畫不畫「這週／下週／之後」區標
        let showsSections: Bool
    }

    /// 前 n 列跨了幾區（buckets 已照日期排好，同一區連在一起）
    static func sectionCount(_ buckets: [Int], rows n: Int) -> Int {
        var count = 0
        var last: Int? = nil
        for b in buckets.prefix(max(0, n)) {
            if b != last {
                count += 1
                last = b
            }
        }
        return count
    }

    /// buckets：每一列（全部，照日期）屬於哪一區（LargeWeekBucket.rawValue）
    static func height(_ plan: Plan, buckets: [Int]) -> CGFloat {
        let n: Int = min(max(0, plan.rows), buckets.count)
        let footer: CGFloat = n < buckets.count ? footerHeight : 0
        let rows: CGFloat = CGFloat(n) * rowHeight
        if plan.showsSections {
            let s: Int = sectionCount(buckets, rows: n)
            let labels: CGFloat = CGFloat(s) * sectionHeaderHeight
            let gaps: CGFloat = CGFloat(max(0, n - s)) * rowSpacing
            return headerHeight + labels + rows + gaps + footer
        }
        let stack: CGFloat = LargeWidgetFit.stack(rows: n, rowHeight: rowHeight, spacing: rowSpacing)
        return headerHeight + compactTopGap + stack + footer
    }

    /// 放得下的最多列：先試有區標（maxRows → labeledMinRows），再試沒區標（→ 1 列）
    static func plan(available: CGFloat, buckets: [Int]) -> Plan {
        let top: Int = min(maxRows, buckets.count)
        guard top > 0 else { return Plan(rows: 0, showsSections: false) }
        let low: Int = min(top, labeledMinRows)
        for n in stride(from: top, through: low, by: -1) {
            let p = Plan(rows: n, showsSections: true)
            if LargeWidgetFit.fits(height(p, buckets: buckets), in: available) { return p }
        }
        for n in stride(from: top, through: 1, by: -1) {
            let p = Plan(rows: n, showsSections: false)
            if LargeWidgetFit.fits(height(p, buckets: buckets), in: available) { return p }
        }
        return Plan(rows: 1, showsSections: false)
    }

    /// ViewThatFits 的 4 個候選（大到小）
    static func candidates(buckets: [Int]) -> [Plan] {
        LargeWidgetFit.candidates { (h: CGFloat) -> Plan in
            plan(available: h, buckets: buckets)
        }
    }
}

// MARK: - 我的車（大）的高度

/// 主卡（車圖＋名字＋車貸環）→ 三格數字（或收成一行）→「接下來」清單 → 兩顆按鈕
enum VehicleLargeLayout {
    /// 主卡：有車貸（環 62＋下面「2029/9 繳完」）
    static let mainHeight: CGFloat = 80
    /// 主卡：沒有車貸（只有車圖 60 和名字）
    static let mainHeightNoRing: CGFloat = 62
    static let artWidth: CGFloat = 84
    static let artHeight: CGFloat = 60
    static let ringSize: CGFloat = 62
    /// 三格數字：上面空 14＋格子 48
    static let tilesHeight: CGFloat = 62
    static let tilesTopGap: CGFloat = 14
    static let tileHeight: CGFloat = 48
    static let tileSpacing: CGFloat = 8
    /// 收成一行：上面空 10＋一行 16
    static let tilesLineHeight: CGFloat = 26
    /// 「接下來」小標：上面空 14＋小標 16
    static let listHeaderHeight: CGFloat = 30
    static let rowHeight: CGFloat = 27
    /// 按鈕一排：至少空 8＋按鈕 44
    static let buttonsHeight: CGFloat = 52
    static let buttonHeight: CGFloat = 44
    static let buttonSpacing: CGFloat = 8
    static let maxRows = 4
    static let fullTilesMinRows = 2

    struct Plan: Equatable {
        /// 「接下來」畫幾筆（0＝整個清單不畫；dueCount 是 0 時一律畫一列「45 天內沒有要扣的」）
        let rows: Int
        /// 三格數字收成一行
        let tilesInline: Bool
    }

    /// dueCount＝今天（含）以後還沒扣的幾筆
    static func height(_ plan: Plan, dueCount: Int, hasRing: Bool, hasButtons: Bool) -> CGFloat {
        let main: CGFloat = hasRing ? mainHeight : mainHeightNoRing
        let tiles: CGFloat = plan.tilesInline ? tilesLineHeight : tilesHeight
        let drawn: Int = dueCount <= 0 ? 1 : min(max(0, plan.rows), dueCount)
        let list: CGFloat = drawn > 0 ? listHeaderHeight + CGFloat(drawn) * rowHeight : 0
        let buttons: CGFloat = hasButtons ? buttonsHeight : 0
        return main + tiles + list + buttons
    }

    /// 先試三格（maxRows → fullTilesMinRows 筆），再試收成一行（→ 0 筆）
    static func plan(available: CGFloat, dueCount: Int, hasRing: Bool, hasButtons: Bool) -> Plan {
        let top: Int = min(maxRows, max(0, dueCount))
        let low: Int = min(top, fullTilesMinRows)
        for n in stride(from: top, through: low, by: -1) {
            let p = Plan(rows: n, tilesInline: false)
            let h: CGFloat = height(p, dueCount: dueCount, hasRing: hasRing, hasButtons: hasButtons)
            if LargeWidgetFit.fits(h, in: available) { return p }
        }
        for n in stride(from: low, through: 0, by: -1) {
            let p = Plan(rows: n, tilesInline: true)
            let h: CGFloat = height(p, dueCount: dueCount, hasRing: hasRing, hasButtons: hasButtons)
            if LargeWidgetFit.fits(h, in: available) { return p }
        }
        return Plan(rows: 0, tilesInline: true)
    }

    static func candidates(dueCount: Int, hasRing: Bool, hasButtons: Bool) -> [Plan] {
        LargeWidgetFit.candidates { (h: CGFloat) -> Plan in
            plan(available: h, dueCount: dueCount, hasRing: hasRing, hasButtons: hasButtons)
        }
    }
}

// MARK: - 旅行（大）的高度

/// 旅途中：表頭（✈ 行程名＋第 2 天／共 5 天）→ 天數條 → 「今天」每一站 → 明天第一站 → 行李。
/// 出發前：「✈ 下一趟旅行」→ 行程名 → 大字「12 天後出發」→ 日期 → 行李 → 「之後的旅行」
enum TravelLargeLayout {
    // 旅途中
    static let headerHeight: CGFloat = 28
    /// 天數條：上面空 10＋膠囊 9＋空 4＋日期 13
    static let dayStripHeight: CGFloat = 36
    static let dayCapsuleHeight: CGFloat = 9
    /// 7 天以內一天一個膠囊；超過改畫進度條
    static let maxDayCapsules = 7
    /// 「今天」區標：上面空 12＋小標＋下面空 4
    static let sectionHeaderHeight: CGFloat = 31
    static let rowHeight: CGFloat = 34
    static let rowSpacing: CGFloat = 5
    /// 「明天第一站 10:00 柳川遊船」：上面空 10＋一行 18
    static let tomorrowHeight: CGFloat = 28
    /// 「行李 15／15」：至少空 8＋一行 18
    static let packingHeight: CGFloat = 26
    static let maxStops = 5
    static let tomorrowMinStops = 3

    struct DuringPlan: Equatable {
        /// 今天畫幾站（stopCount 是 0 時畫一列一句話）
        let rows: Int
        let showsTomorrow: Bool
    }

    static func duringHeight(_ plan: DuringPlan, stopCount: Int, hasPacking: Bool) -> CGFloat {
        let drawn: Int = stopCount <= 0 ? 1 : min(max(1, plan.rows), stopCount)
        let stack: CGFloat = LargeWidgetFit.stack(rows: drawn, rowHeight: rowHeight, spacing: rowSpacing)
        let tomorrow: CGFloat = plan.showsTomorrow ? tomorrowHeight : 0
        let packing: CGFloat = hasPacking ? packingHeight : 0
        let top: CGFloat = headerHeight + dayStripHeight + sectionHeaderHeight
        return top + stack + tomorrow + packing
    }

    /// 先試帶「明天第一站」（maxStops → tomorrowMinStops 站），再試不帶（→ 1 站）
    static func duringPlan(available: CGFloat, stopCount: Int, hasTomorrow: Bool, hasPacking: Bool) -> DuringPlan {
        let top: Int = min(maxStops, max(1, stopCount))
        if hasTomorrow {
            let low: Int = min(top, tomorrowMinStops)
            for n in stride(from: top, through: low, by: -1) {
                let p = DuringPlan(rows: n, showsTomorrow: true)
                let h: CGFloat = duringHeight(p, stopCount: stopCount, hasPacking: hasPacking)
                if LargeWidgetFit.fits(h, in: available) { return p }
            }
        }
        for n in stride(from: top, through: 1, by: -1) {
            let p = DuringPlan(rows: n, showsTomorrow: false)
            let h: CGFloat = duringHeight(p, stopCount: stopCount, hasPacking: hasPacking)
            if LargeWidgetFit.fits(h, in: available) { return p }
        }
        return DuringPlan(rows: 1, showsTomorrow: false)
    }

    static func duringCandidates(stopCount: Int, hasTomorrow: Bool, hasPacking: Bool) -> [DuringPlan] {
        LargeWidgetFit.candidates { (h: CGFloat) -> DuringPlan in
            duringPlan(available: h, stopCount: stopCount, hasTomorrow: hasTomorrow, hasPacking: hasPacking)
        }
    }

    // 出發前
    /// 「✈ 下一趟旅行」
    static let upLabelHeight: CGFloat = 18
    /// 行程名 19pt
    static let upTitleHeight: CGFloat = 28
    /// 上面空 6＋大字 48pt「12」＋「天後出發」
    static let upHeroHeight: CGFloat = 64
    /// 「12/2 (週三) 出發・共 5 天」
    static let upDateHeight: CGFloat = 20
    /// 行李：上面空 12＋一行 18
    static let upPackingHeight: CGFloat = 30
    /// 「之後的旅行」區標
    static let laterHeaderHeight: CGFloat = 31
    static let laterRowHeight: CGFloat = 28
    static let laterRowSpacing: CGFloat = 4
    static let maxLaterTrips = 2

    static func upcomingHeight(laterRows: Int, hasPacking: Bool) -> CGFloat {
        let n: Int = max(0, laterRows)
        let packing: CGFloat = hasPacking ? upPackingHeight : 0
        let stack: CGFloat = LargeWidgetFit.stack(rows: n, rowHeight: laterRowHeight, spacing: laterRowSpacing)
        let later: CGFloat = n > 0 ? laterHeaderHeight + stack : 0
        let top: CGFloat = upLabelHeight + upTitleHeight + upHeroHeight + upDateHeight
        return top + packing + later
    }

    /// 「之後的旅行」放幾列（maxLaterTrips → 0）
    static func upcomingPlan(available: CGFloat, laterCount: Int, hasPacking: Bool) -> Int {
        let top: Int = min(maxLaterTrips, max(0, laterCount))
        for n in stride(from: top, through: 0, by: -1) {
            if LargeWidgetFit.fits(upcomingHeight(laterRows: n, hasPacking: hasPacking), in: available) {
                return n
            }
        }
        return 0
    }

    static func upcomingCandidates(laterCount: Int, hasPacking: Bool) -> [Int] {
        LargeWidgetFit.candidates { (h: CGFloat) -> Int in
            upcomingPlan(available: h, laterCount: laterCount, hasPacking: hasPacking)
        }
    }
}

// MARK: - 共用的版型小元件

/// 表頭一行：左邊圖示＋標題（粗、重點色），右邊小字（「第 2 天／共 5 天」）。固定高度
struct LargeWidgetTitleLine: View {
    /// SF Symbol；空字串不畫
    let icon: String
    let iconColor: Color
    let title: String
    /// 右邊小字；空字串不畫
    let trailing: String
    let trailingColor: Color
    let palette: WidgetPalette
    var titleSize: CGFloat = 19
    var height: CGFloat = 28

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            LargeWidgetIcon(name: icon, size: titleSize - 2, color: iconColor)
            titleText
            Spacer(minLength: 6)
            trailingText
        }
        .frame(height: height)
    }

    private var titleText: some View {
        Text(title)
            .font(.system(size: titleSize, weight: .bold))
            .foregroundStyle(palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .widgetAccentable()
    }

    @ViewBuilder
    private var trailingText: some View {
        if !trailing.isEmpty {
            Text(trailing)
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(trailingColor)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// 圖示（空字串不畫；著色模式染重點色）
private struct LargeWidgetIcon: View {
    let name: String
    let size: CGFloat
    let color: Color

    var body: some View {
        if !name.isEmpty {
            Image(systemName: name)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(color)
                .widgetAccentable()
        }
    }
}

/// 區標「這週」「接下來」「今天」：整塊固定高度 height（含上面的空），字貼底、下面空 bottomGap
struct LargeWidgetSectionLabel: View {
    let title: String
    let height: CGFloat
    let palette: WidgetPalette
    var bottomGap: CGFloat = 3

    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(palette.label)
            .lineLimit(1)
            .padding(.bottom, bottomGap)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .bottomLeading)
    }
}

/// 頁腳一行（「再來 12/15 Spotify 等 4 件」）：整塊固定高度 height（含上面的空），字貼底
struct LargeWidgetFooterLine: View {
    let text: String
    let palette: WidgetPalette
    var height: CGFloat = 20

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(palette.label)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .bottomLeading)
    }
}

/// 一列的底（rowFill 圓角）；highlight 不是 nil 時多畫一圈外框（旅行「進行中」那一站）
struct LargeWidgetCardBackground: View {
    let palette: WidgetPalette
    var cornerRadius: CGFloat = 9
    var highlight: Color? = nil

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            shape.fill(palette.rowFill)
            highlightStroke
        }
    }

    @ViewBuilder
    private var highlightStroke: some View {
        if let color = highlight {
            shape.strokeBorder(color, lineWidth: 1.5)
        }
    }
}

/// 列左邊的色條（接下來要繳：palette.billBar(tint:tintDark:)）
struct LargeWidgetTintBar: View {
    let color: Color
    var width: CGFloat = 3.5
    var height: CGFloat = 26

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: height)
    }
}

/// 進度條：淡底＋顏色（著色模式染重點色）。自己有一個 GeometryReader，外面不准再包 GeometryReader
struct LargeWidgetBar: View {
    let fraction: Double
    let fill: Color
    let track: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: filledWidth(geo.size.width))
                    .widgetAccentable()
            }
        }
        .frame(height: height)
    }

    /// 塗多長：有進度就至少一個圓頭那麼長，0 不塗
    private func filledWidth(_ total: CGFloat) -> CGFloat {
        let f: Double = fraction.isFinite ? min(1, max(0, fraction)) : 0
        guard f > 0 else { return 0 }
        return max(height, total * CGFloat(f))
    }
}

/// 進度環（我的車的車貸）：淡底環＋圓頭線，從 12 點鐘方向順時針（Circle().trim，不用 Gauge）
struct LargeWidgetRing: View {
    let fraction: Double
    let fill: Color
    let track: Color
    var lineWidth: CGFloat = 6

    private var progress: CGFloat {
        CGFloat(fraction.isFinite ? min(1, max(0, fraction)) : 0)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(fill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        .padding(lineWidth / 2)
    }
}
