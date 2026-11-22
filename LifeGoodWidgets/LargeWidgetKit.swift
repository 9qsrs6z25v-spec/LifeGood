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

// MARK: - [v25.632 large2] 第二版共用：股票（6 檔）、淨資產、記帳台
//
// 規格見 scratchpad/radar/build/large2/brief.md（主控定案）；示意圖 scratchpad/largewidgets/{stocks,networth,ledgerdesk}.html。
// **上面第一版的部分一個字都不改**（keycheck_large2 檢查 d6cfab9 的這個檔是現在這個檔的開頭）。
// 總設計先做好，G1（股票）、G2（淨資產）、G3（記帳台）只呼叫、不改。sim_large2.py 一個函式一個函式對照。
//
// 這一段提供：
//   • StocksLargeLayout／StocksLargePick／StocksLargeText   股票・大的高度與「放幾列、兩行還是一行」、挑 6 檔、表頭字
//   • NetWorthLargeLayout                                      淨資產・大的高度與「兩欄各放幾類、列高」
//   • LargeWidgetBandPart／LargeWidgetBandMath／LargeWidgetBand 組成色帶（照占比分段；著色模式留 2pt、畫外框）
//   • LargeWidgetSwatch                                        兩欄每一列前面的小色塊
//   • LedgerDeskLargeLayout                                    記帳台・大的高度與「卡片多高、畫不畫頁腳」

// MARK: 股票（大）的高度

/// 表頭（「股票　台股盤中・10:42」＋右上 ↻）→ 6 列（每列兩行；放不下改一行，再放不下少幾列）→ 頁腳「今年股利 …」
enum StocksLargeLayout {
    /// 表頭（↻ 是 36pt 的圓）
    static let headerHeight: CGFloat = 36
    /// 表頭下面空多少
    static let listTopGap: CGFloat = 6
    /// 一列兩行：「2330 台積電｜1,085」／「比均價 +18%・2 張・NT$217萬｜▲13（+1.2%）」
    static let twoLineRowHeight: CGFloat = 38
    /// 一列一行：「2330 台積電｜1,085｜▲1.2%」
    static let oneLineRowHeight: CGFloat = 28
    static let rowSpacing: CGFloat = 4
    /// 頁腳：至少空 6＋一行 16；沒有股利那一行不畫
    static let footerHeight: CGFloat = 22
    /// ↻ 的圓
    static let refreshSize: CGFloat = 36
    /// 大型最多幾檔（上網多抓的上限：6 檔、每批 4 個＝2 批）
    static let maxRows = 6

    struct Plan: Equatable {
        /// 畫前幾檔
        let rows: Int
        /// 每列兩行（false＝一行）
        let twoLine: Bool
    }

    static func height(_ plan: Plan, hasFooter: Bool) -> CGFloat {
        let row: CGFloat = plan.twoLine ? twoLineRowHeight : oneLineRowHeight
        let list: CGFloat = LargeWidgetFit.stack(rows: max(0, plan.rows), rowHeight: row, spacing: rowSpacing)
        let footer: CGFloat = hasFooter ? footerHeight : 0
        return headerHeight + listTopGap + list + footer
    }

    /// 先試全部兩行、再試全部一行；都放不下才少一列（每一個列數先兩行再一行）
    static func plan(available: CGFloat, count: Int, hasFooter: Bool) -> Plan {
        let top: Int = min(maxRows, max(0, count))
        guard top > 0 else { return Plan(rows: 0, twoLine: false) }
        let fullTwo = Plan(rows: top, twoLine: true)
        if LargeWidgetFit.fits(height(fullTwo, hasFooter: hasFooter), in: available) { return fullTwo }
        let fullOne = Plan(rows: top, twoLine: false)
        if LargeWidgetFit.fits(height(fullOne, hasFooter: hasFooter), in: available) { return fullOne }
        for n in stride(from: top - 1, through: 1, by: -1) {
            let two = Plan(rows: n, twoLine: true)
            if LargeWidgetFit.fits(height(two, hasFooter: hasFooter), in: available) { return two }
            let one = Plan(rows: n, twoLine: false)
            if LargeWidgetFit.fits(height(one, hasFooter: hasFooter), in: available) { return one }
        }
        return Plan(rows: 1, twoLine: false)
    }

    /// ViewThatFits 的 4 個候選（大到小）
    static func candidates(count: Int, hasFooter: Bool) -> [Plan] {
        LargeWidgetFit.candidates { (h: CGFloat) -> Plan in
            plan(available: h, count: count, hasFooter: hasFooter)
        }
    }
}

// MARK: 股票（大）挑哪幾檔

enum StocksLargePick {
    /// 前面照長按設定的第 1／2／3 檔（跳過找不到的與重複的），不夠的照 App 的市值大到小（items 的順序）補到 count 檔。
    /// count 是 3 時跟 WidgetFinanceSnapshot.threeStocks(ids:) 一模一樣（中型不改，sim 逐筆比）
    static func pick(_ all: [WidgetFinanceStock], ids: [String?], count: Int) -> [WidgetFinanceStock] {
        let limit: Int = max(0, count)
        var out: [WidgetFinanceStock] = []
        var seen = Set<UUID>()
        for raw in ids {
            guard let raw, let hit = all.first(where: { $0.id.uuidString == raw }) else { continue }
            if seen.insert(hit.id).inserted {
                out.append(hit)
            }
        }
        for s in all where out.count < limit {
            if seen.insert(s.id).inserted {
                out.append(s)
            }
        }
        return Array(out.prefix(limit))
    }
}

// MARK: 股票（大）表頭的字

enum StocksLargeText {
    /// 這個價是小工具今天盤中抓的：不是 App 的價、沒有日期、不是收盤、有時間
    static func isLive(_ f: WidgetStockFigures) -> Bool {
        if f.fromApp || f.datePrefix != nil || f.timeText.isEmpty { return false }
        return !f.timeText.hasSuffix("收盤")
    }

    /// 表頭右邊：表頭用的那一檔（第一個有時間的）是台股、今天盤中抓的、現在台股盤中（台北平日 09:00–13:35）
    /// →「台股盤中・10:42」；美股同理「美股盤中・23:55」；其他只寫時間「13:30 收盤」「10/13 收盤」「App 的價」；沒有時間 ""
    static func header(time: String, isLive: Bool, isUS: Bool, now: Date) -> String {
        guard !time.isEmpty else { return "" }
        guard isLive else { return time }
        if !isUS && WidgetQuoteSchedule.isTWSession(now) { return "台股盤中・" + time }
        if isUS && WidgetQuoteSchedule.isUSSession(now) { return "美股盤中・" + time }
        return time
    }

    /// 用「・」接起來，空字串跳過（「比均價 +18%」「2 張・NT$217萬」→「比均價 +18%・2 張・NT$217萬」）
    static func dotJoined(_ parts: [String]) -> String {
        let texts: [String] = parts.filter { !$0.isEmpty }
        return texts.joined(separator: "・")
    }
}

// MARK: 淨資產（大）的高度

/// 「淨資產　11 月」→ 大字＋膠囊「比上月 ↑2%」→ App 寫好的那一句 → 資產色帶（＋貸款色帶）→
/// 兩欄（資產最多 6 類｜貸款最多 4 類）→ 頁腳「股價 11/20 13:30」。12 個月走勢是第三版，這一版不畫、不留位置
enum NetWorthLargeLayout {
    /// 「淨資產　11 月」
    static let titleHeight: CGFloat = 18
    /// 大字 30pt＋膠囊
    static let heroHeight: CGFloat = 40
    /// 「總資產 NT$3795萬・貸款還欠 約 NT$2075萬」
    static let lineHeight: CGFloat = 18
    /// 色帶：上面空 10＋資產 12（＋空 4＋貸款 6）
    static let bandTopGap: CGFloat = 10
    static let assetBandHeight: CGFloat = 12
    static let debtBandGap: CGFloat = 4
    static let debtBandHeight: CGFloat = 6
    /// 段與段之間的縫（著色模式改 2pt、畫外框）；有占比的段至少多寬
    static let bandGap: CGFloat = 1.5
    static let bandGapMono: CGFloat = 2
    static let bandMinSegment: CGFloat = 3
    /// 兩欄：上面空 14＋欄標「資產」「貸款」18＋每列（高的 26、矮的 22）
    static let columnsTopGap: CGFloat = 14
    static let sectionLabelHeight: CGFloat = 18
    static let tallRowHeight: CGFloat = 26
    static let rowHeight: CGFloat = 22
    static let columnSpacing: CGFloat = 16
    static let swatchSize: CGFloat = 7
    /// 頁腳「股價 11/20 13:30」「11/19 的數字」：至少空 4＋一行 16；兩個都沒有不畫
    static let footHeight: CGFloat = 20
    static let maxAssets = 6
    static let maxDebts = 4

    /// 依序試的類別上限（資產、貸款）：(6／4)、(5／3)、(4／3)、(3／2)；每一組先試高的列再試矮的
    static let assetLimits: [Int] = [6, 5, 4, 3]
    static let debtLimits: [Int] = [4, 3, 3, 2]

    struct Plan: Equatable {
        let assetRows: Int
        let debtRows: Int
        let rowHeight: CGFloat
    }

    /// 色帶一塊多高（沒有貸款只有資產那一條）
    static func bandsHeight(hasDebtBand: Bool) -> CGFloat {
        let asset: CGFloat = bandTopGap + assetBandHeight
        return hasDebtBand ? asset + debtBandGap + debtBandHeight : asset
    }

    static func height(_ plan: Plan, hasDebtBand: Bool, hasFoot: Bool) -> CGFloat {
        let rows: Int = max(0, max(plan.assetRows, plan.debtRows))
        let columns: CGFloat = rows > 0 ? columnsTopGap + sectionLabelHeight + CGFloat(rows) * plan.rowHeight : 0
        let foot: CGFloat = hasFoot ? footHeight : 0
        let top: CGFloat = titleHeight + heroHeight + lineHeight + bandsHeight(hasDebtBand: hasDebtBand)
        return top + columns + foot
    }

    static func plan(available: CGFloat, assetCount: Int, debtCount: Int, hasFoot: Bool) -> Plan {
        let a0: Int = max(0, assetCount)
        let d0: Int = max(0, debtCount)
        let hasDebtBand: Bool = d0 > 0
        let heights: [CGFloat] = [tallRowHeight, rowHeight]
        for i in 0..<assetLimits.count {
            let a: Int = min(assetLimits[i], a0)
            let d: Int = min(debtLimits[i], d0)
            for rh in heights {
                let p = Plan(assetRows: a, debtRows: d, rowHeight: rh)
                if LargeWidgetFit.fits(height(p, hasDebtBand: hasDebtBand, hasFoot: hasFoot), in: available) {
                    return p
                }
            }
        }
        let lastA: Int = min(assetLimits[assetLimits.count - 1], a0)
        let lastD: Int = min(debtLimits[debtLimits.count - 1], d0)
        return Plan(assetRows: lastA, debtRows: lastD, rowHeight: rowHeight)
    }

    static func candidates(assetCount: Int, debtCount: Int, hasFoot: Bool) -> [Plan] {
        LargeWidgetFit.candidates { (h: CGFloat) -> Plan in
            plan(available: h, assetCount: assetCount, debtCount: debtCount, hasFoot: hasFoot)
        }
    }
}

// MARK: 色帶

/// 色帶的一段（淨資產的一類）：占多少、什麼顏色（App 給的兩個色碼）
struct LargeWidgetBandPart: Identifiable, Equatable {
    let id: String
    let share: Double
    let top: UInt32
    let bottom: UInt32
}

enum LargeWidgetBandMath {
    /// 每一段多寬：先塗 total × fraction，扣掉段與段之間的縫，照 share（加起來先當 1）分；
    /// 有占比的段至少 minWidth（不夠的從比 minWidth 寬的段照多出來的比例扣回來，總長不變）；
    /// 連每段 minWidth 都放不下就照比例。share 不是有限正數的段寬 0。回傳的總和＝塗的長度扣掉縫
    static func widths(shares: [Double], fraction: Double, total: CGFloat, gap: CGFloat,
                       minWidth: CGFloat) -> [CGFloat] {
        let n: Int = shares.count
        guard n > 0 else { return [] }
        let f: Double = fraction.isFinite ? min(1, max(0, fraction)) : 0
        let filled: CGFloat = max(0, total) * CGFloat(f)
        let gaps: CGFloat = max(0, gap) * CGFloat(n - 1)
        let usable: CGFloat = max(0, filled - gaps)
        let clean: [Double] = shares.map { ($0.isFinite && $0 > 0) ? $0 : 0 }
        let sum: Double = clean.reduce(0, +)
        guard usable > 0, sum > 0 else { return Array(repeating: 0, count: n) }
        var out: [CGFloat] = clean.map { usable * CGFloat($0 / sum) }
        let positive: Int = clean.filter { $0 > 0 }.count
        guard minWidth > 0, minWidth * CGFloat(positive) <= usable else { return out }
        var extra: CGFloat = 0
        for i in 0..<n where clean[i] > 0 && out[i] < minWidth {
            extra += minWidth - out[i]
            out[i] = minWidth
        }
        guard extra > 0 else { return out }
        var room: CGFloat = 0
        for w in out where w > minWidth {
            room += w - minWidth
        }
        guard room > 0 else { return out }
        let ratio: CGFloat = min(1, extra / room)
        for i in 0..<n where out[i] > minWidth {
            out[i] -= (out[i] - minWidth) * ratio
        }
        return out
    }
}

/// 一段（GeometryReader 量到寬度之後算好）
private struct LargeWidgetBandItem: Identifiable {
    let id: String
    let width: CGFloat
    let top: UInt32
    let bottom: UInt32
}

/// 組成色帶：照 parts 的 share 分段、各自的漸層，塗 fraction 那麼長（沒有底）。
/// 著色模式（含 StandBy）段與段之間留 2pt、每段只畫外框。自己有一個 GeometryReader，外面不准再包
struct LargeWidgetBand: View {
    let parts: [LargeWidgetBandPart]
    let fraction: Double
    let height: CGFloat
    let palette: WidgetPalette

    private var gap: CGFloat {
        palette.isMono ? NetWorthLargeLayout.bandGapMono : NetWorthLargeLayout.bandGap
    }

    var body: some View {
        GeometryReader { geo in
            LargeWidgetBandRow(items: items(total: geo.size.width), gap: gap, height: height, palette: palette)
        }
        .frame(height: height)
    }

    private func items(total: CGFloat) -> [LargeWidgetBandItem] {
        let shares: [Double] = parts.map { $0.share }
        let widths: [CGFloat] = LargeWidgetBandMath.widths(shares: shares, fraction: fraction, total: total,
                                                           gap: gap, minWidth: NetWorthLargeLayout.bandMinSegment)
        var out: [LargeWidgetBandItem] = []
        for (part, w) in zip(parts, widths) {
            out.append(LargeWidgetBandItem(id: part.id, width: w, top: part.top, bottom: part.bottom))
        }
        return out
    }
}

/// 一排段（全彩：整排兩頭圓；著色：方的、外框）
private struct LargeWidgetBandRow: View {
    let items: [LargeWidgetBandItem]
    let gap: CGFloat
    let height: CGFloat
    let palette: WidgetPalette

    private var corner: CGFloat { palette.isMono ? 0 : height / 2 }

    var body: some View {
        HStack(spacing: gap) {
            ForEach(items, id: \.id) { item in
                LargeWidgetBandSegment(top: item.top, bottom: item.bottom, palette: palette)
                    .frame(width: item.width, height: height)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

private struct LargeWidgetBandSegment: View {
    let top: UInt32
    let bottom: UInt32
    let palette: WidgetPalette

    private var gradient: LinearGradient {
        LinearGradient(colors: [Color(widgetHex: top), Color(widgetHex: bottom)],
                       startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        if palette.isMono {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(palette.ink, lineWidth: 1)
        } else {
            Rectangle()
                .fill(gradient)
        }
    }
}

/// 兩欄每一列前面的小色塊（深色用 top、淺色用 bottom；著色模式畫外框）
struct LargeWidgetSwatch: View {
    let top: UInt32
    let bottom: UInt32
    let palette: WidgetPalette
    var size: CGFloat = 7

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
    }

    private var color: Color {
        Color(widgetHex: palette.isDark ? top : bottom)
    }

    var body: some View {
        if palette.isMono {
            shape
                .strokeBorder(palette.ink, lineWidth: 1)
                .frame(width: size, height: size)
        } else {
            shape
                .fill(color)
                .frame(width: size, height: size)
        }
    }
}

// MARK: 記帳台（大）的高度

/// 上半：整寬的還能花（日期 → 小標 → 大字＋「每天 NT$2,402」→ 橫條 → 「今天 …」｜「收入 …」→「已花 62%・還有 10 天」），
/// 下半：2×2 大卡片。放不下時卡片變矮（76 → 68 → 60），再拿掉頁腳。「今天記的」是第三版
enum LedgerDeskLargeLayout {
    /// 「11 月・第 20 天」
    static let captionHeight: CGFloat = 16
    /// 「本月還能花」
    static let titleHeight: CGFloat = 18
    /// 大字 28pt＋「每天 NT$2,402」
    static let heroHeight: CGFloat = 36
    /// 橫條：上面空 6＋條 10
    static let barHeight: CGFloat = 16
    static let barTrackHeight: CGFloat = 10
    /// 兩欄小字：上面空 6＋一行 14
    static let twoColumnHeight: CGFloat = 20
    /// 頁腳「已花 62%・還有 10 天」：上面空 3＋一行 14
    static let footerHeight: CGFloat = 17
    /// 卡片：上面至少空 12，兩排之間 8
    static let gridTopGap: CGFloat = 12
    static let tileSpacing: CGFloat = 8
    static let tallTileHeight: CGFloat = 76
    static let tileHeight: CGFloat = 68
    static let compactTileHeight: CGFloat = 60
    static let maxTiles = 4

    struct Plan: Equatable {
        let tileHeight: CGFloat
        let showsFooter: Bool
    }

    /// 上半多高（頁腳畫不畫）
    static func panelHeight(showsFooter: Bool) -> CGFloat {
        let top: CGFloat = captionHeight + titleHeight + heroHeight + barHeight + twoColumnHeight
        return showsFooter ? top + footerHeight : top
    }

    /// 卡片排幾排（1、2 張一排；3、4 張兩排；0 張 0 排）
    static func tileRows(_ tileCount: Int) -> Int {
        let n: Int = min(maxTiles, max(0, tileCount))
        return (n + 1) / 2
    }

    static func height(_ plan: Plan, tileCount: Int) -> CGFloat {
        let rows: Int = tileRows(tileCount)
        let stack: CGFloat = LargeWidgetFit.stack(rows: rows, rowHeight: plan.tileHeight, spacing: tileSpacing)
        let grid: CGFloat = rows > 0 ? gridTopGap + stack : 0
        return panelHeight(showsFooter: plan.showsFooter) + grid
    }

    /// 有頁腳的字（hasFooter）時先試帶頁腳（卡片 76 → 60），再試不帶；沒有頁腳的字只試不帶
    static func plan(available: CGFloat, tileCount: Int, hasFooter: Bool) -> Plan {
        let heights: [CGFloat] = [tallTileHeight, tileHeight, compactTileHeight]
        let footers: [Bool] = hasFooter ? [true, false] : [false]
        for footer in footers {
            for h in heights {
                let p = Plan(tileHeight: h, showsFooter: footer)
                if LargeWidgetFit.fits(height(p, tileCount: tileCount), in: available) { return p }
            }
        }
        return Plan(tileHeight: compactTileHeight, showsFooter: false)
    }

    static func candidates(tileCount: Int, hasFooter: Bool) -> [Plan] {
        LargeWidgetFit.candidates { (h: CGFloat) -> Plan in
            plan(available: h, tileCount: tileCount, hasFooter: hasFooter)
        }
    }
}

// MARK: - [v25.637 large3] 第三版共用：還能花（大）、淨資產（大）走勢、記帳台（大）今天記的
//
// 規格見 scratchpad/radar/build/large3/brief.md（主控定案）；judge_largewidgets.md §C 第三版。
// **上面第一版、第二版的部分一個字都不改**（keycheck_large3 檢查 3f3d329 的這個檔是現在這個檔的開頭）。
// 總設計先做好，G1（還能花）、G2（淨資產）、G3（記帳台）只呼叫、不改。sim_large3.py 一個函式一個函式對照。
//
// 這一段提供：
//   • MoneyLeftLargeLayout        還能花・大的高度與「畫不畫近 7 天、花在哪放幾列」
//   • NetWorthTrendLayout         淨資產・大加走勢之後「兩欄各放幾類、列高、畫不畫走勢」（不畫走勢＝第二版的 NetWorthLargeLayout）
//   • LedgerDeskTodayLayout       記帳台・大加「今天記的」之後「卡片多高、畫不畫頁腳、今天記的放幾筆」（0 筆＝第二版）
//   • LargeWidgetTrendMath／LargeWidgetTrendShape／LargeWidgetTrendArea／LargeWidgetTrendLine
//                                 走勢折線（Shape 的 path(in:)；不用 Charts、Canvas、GeometryReader）
//   • LargeWidgetWeekBarMath      近 7 天柱子多高（比例 → pt）

// MARK: 還能花（大）的高度

/// ①「11/20 週五」→「本月還能花」→ 大字＋「每天 NT$2,402」（右上 ⊕ 疊在日期那兩行右邊）→ ② 橫條 →「已花 62%・還有 11 天」
/// → ③「近 7 天」區標（右邊「7 天 NT$9,860」）＋7 根柱子＋星期字 → ④「花在哪」區標＋最多 5 列。
/// 放不下照順序砍：④ 5 列 → 4 列 → 3 列 → 只有 ③ → 只有 ①②（字級不變）
enum MoneyLeftLargeLayout {
    /// 「11/20 週五」
    static let captionHeight: CGFloat = 16
    /// 「本月還能花」
    static let titleHeight: CGFloat = 18
    /// 大字 30pt＋「每天 NT$2,402」
    static let heroHeight: CGFloat = 38
    /// 橫條：上面空 8＋條 10
    static let barHeight: CGFloat = 18
    static let barTrackHeight: CGFloat = 10
    /// 「已花 62%・還有 11 天」：上面空 4＋一行 14
    static let progressHeight: CGFloat = 18
    /// 右上 ⊕（疊在日期、小標右邊，不佔版面）
    static let addButtonSize: CGFloat = 36
    /// ③ 區標（上面空 10＋字 14）
    static let weekLabelHeight: CGFloat = 24
    /// 柱子那一塊（最高的柱子＝這麼高；有花錢的柱子至少 barMinHeight；0 畫一條 2pt 的底）
    static let weekBarsHeight: CGFloat = 40
    static let weekBarSpacing: CGFloat = 6
    static let weekBarMinHeight: CGFloat = 4
    static let weekBarZeroHeight: CGFloat = 2
    /// 星期字（上面空 3＋字 12）
    static let weekdayHeight: CGFloat = 15
    /// ④ 區標（上面空 10＋字 14）＋每列
    static let categoryLabelHeight: CGFloat = 24
    static let categoryRowHeight: CGFloat = 22
    static let maxCategoryRows = 5
    /// 依序試的「花在哪」列數
    static let categoryLimits: [Int] = [5, 4, 3]

    struct Plan: Equatable {
        /// 畫不畫 ③ 近 7 天
        let showsWeek: Bool
        /// ④ 放幾列（0＝整塊不畫，連區標）
        let categoryRows: Int
    }

    /// ①② 一塊多高
    static var headHeight: CGFloat {
        captionHeight + titleHeight + heroHeight + barHeight + progressHeight
    }

    /// ③ 一塊多高
    static var weekHeight: CGFloat {
        weekLabelHeight + weekBarsHeight + weekdayHeight
    }

    /// ④ n 列一塊多高（0 列 0）
    static func categoryHeight(rows n: Int) -> CGFloat {
        guard n > 0 else { return 0 }
        return categoryLabelHeight + CGFloat(n) * categoryRowHeight
    }

    static func height(_ plan: Plan) -> CGFloat {
        let week: CGFloat = plan.showsWeek ? weekHeight : 0
        return headHeight + week + categoryHeight(rows: plan.categoryRows)
    }

    /// hasWeek：快照有這一天的近 7 天；categoryCount：這個月「花在哪」幾列（舊快照、跨月 0）
    static func plan(available: CGFloat, hasWeek: Bool, categoryCount: Int) -> Plan {
        let count: Int = min(maxCategoryRows, max(0, categoryCount))
        if count > 0 {
            for limit in categoryLimits {
                let p = Plan(showsWeek: hasWeek, categoryRows: min(limit, count))
                if LargeWidgetFit.fits(height(p), in: available) { return p }
            }
        }
        let weekOnly = Plan(showsWeek: hasWeek, categoryRows: 0)
        if hasWeek, LargeWidgetFit.fits(height(weekOnly), in: available) { return weekOnly }
        return Plan(showsWeek: false, categoryRows: 0)
    }

    static func candidates(hasWeek: Bool, categoryCount: Int) -> [Plan] {
        LargeWidgetFit.candidates { (h: CGFloat) -> Plan in
            plan(available: h, hasWeek: hasWeek, categoryCount: categoryCount)
        }
    }
}

/// 近 7 天柱子多高：比例 0…1 → pt。有花錢（> 0）至少 weekBarMinHeight；0 畫 weekBarZeroHeight 的底（看得出那天沒花）
enum LargeWidgetWeekBarMath {
    static func barHeight(_ fraction: Double) -> CGFloat {
        let f: Double = fraction.isFinite ? min(1, max(0, fraction)) : 0
        guard f > 0 else { return MoneyLeftLargeLayout.weekBarZeroHeight }
        let h: CGFloat = MoneyLeftLargeLayout.weekBarsHeight * CGFloat(f)
        return max(MoneyLeftLargeLayout.weekBarMinHeight, h)
    }
}

// MARK: 淨資產（大）加走勢的高度

/// 第二版那一欄（標題 → 大字 → 那一句 → 色帶 → 兩欄 → 頁腳），兩欄和頁腳中間多一塊「近 12 個月」：
/// 上面空 10＋區標 14＋折線 28＋頭尾月份 12。走勢只在兩欄至少放得下 (4／3) 類時才畫（類別比走勢重要），
/// 放不下就退回第二版（NetWorthLargeLayout.plan，不畫走勢）
enum NetWorthTrendLayout {
    static let trendTopGap: CGFloat = 10
    static let trendLabelHeight: CGFloat = 14
    static let trendChartHeight: CGFloat = 28
    static let trendMonthsHeight: CGFloat = 12
    /// 折線上下左右留的空（線的粗細＋最後一點的圓點）
    static let trendInset: CGFloat = 3
    static let trendLineWidth: CGFloat = 2
    static let trendDotSize: CGFloat = 5
    /// 有走勢時依序試的類別上限（資產、貸款）；每一組先試高的列再試矮的
    static let assetLimits: [Int] = [6, 5, 4]
    static let debtLimits: [Int] = [4, 3, 3]

    struct Plan: Equatable {
        let base: NetWorthLargeLayout.Plan
        let showsTrend: Bool
    }

    static var trendHeight: CGFloat {
        trendTopGap + trendLabelHeight + trendChartHeight + trendMonthsHeight
    }

    static func height(_ plan: Plan, hasDebtBand: Bool, hasFoot: Bool) -> CGFloat {
        let base: CGFloat = NetWorthLargeLayout.height(plan.base, hasDebtBand: hasDebtBand, hasFoot: hasFoot)
        return plan.showsTrend ? base + trendHeight : base
    }

    /// hasTrend：快照有走勢（至少 2 點）
    static func plan(available: CGFloat, assetCount: Int, debtCount: Int, hasFoot: Bool, hasTrend: Bool) -> Plan {
        let a0: Int = max(0, assetCount)
        let d0: Int = max(0, debtCount)
        let hasDebtBand: Bool = d0 > 0
        if hasTrend {
            let heights: [CGFloat] = [NetWorthLargeLayout.tallRowHeight, NetWorthLargeLayout.rowHeight]
            for i in 0..<assetLimits.count {
                let a: Int = min(assetLimits[i], a0)
                let d: Int = min(debtLimits[i], d0)
                for rh in heights {
                    let p = Plan(base: NetWorthLargeLayout.Plan(assetRows: a, debtRows: d, rowHeight: rh), showsTrend: true)
                    if LargeWidgetFit.fits(height(p, hasDebtBand: hasDebtBand, hasFoot: hasFoot), in: available) {
                        return p
                    }
                }
            }
        }
        let base = NetWorthLargeLayout.plan(available: available, assetCount: a0, debtCount: d0, hasFoot: hasFoot)
        return Plan(base: base, showsTrend: false)
    }

    static func candidates(assetCount: Int, debtCount: Int, hasFoot: Bool, hasTrend: Bool) -> [Plan] {
        LargeWidgetFit.candidates { (h: CGFloat) -> Plan in
            plan(available: h, assetCount: assetCount, debtCount: debtCount, hasFoot: hasFoot, hasTrend: hasTrend)
        }
    }
}

// MARK: 走勢折線

enum LargeWidgetTrendMath {
    /// 每一點在 width×height 裡的位置：x 從 inset 到 width − inset 平均分（只有 1 點放正中間），
    /// 高度 1 在最上面（y＝inset）、0 在最下面（y＝height − inset）。不是有限數當 0；寬或高 ≤ 0 回空陣列
    static func points(heights: [Double], width: CGFloat, height: CGFloat, inset: CGFloat) -> [CGPoint] {
        let n: Int = heights.count
        guard n > 0, width > 0, height > 0 else { return [] }
        let usableW: CGFloat = max(0, width - inset * 2)
        let usableH: CGFloat = max(0, height - inset * 2)
        var out: [CGPoint] = []
        for (i, h) in heights.enumerated() {
            let f: Double = h.isFinite ? min(1, max(0, h)) : 0
            let x: CGFloat = n == 1 ? width / 2 : inset + usableW * CGFloat(i) / CGFloat(n - 1)
            let y: CGFloat = inset + usableH * CGFloat(1 - f)
            out.append(CGPoint(x: x, y: y))
        }
        return out
    }
}

/// 折線（只有線）
struct LargeWidgetTrendShape: Shape {
    let heights: [Double]
    var inset: CGFloat = NetWorthTrendLayout.trendInset

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let pts: [CGPoint] = LargeWidgetTrendMath.points(heights: heights, width: rect.width, height: rect.height,
                                                          inset: inset)
        guard let first = pts.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x, y: rect.minY + first.y))
        for p in pts.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + p.x, y: rect.minY + p.y))
        }
        return path
    }
}

/// 折線下面那一塊（收到底邊；全彩模式淡淡填色用）
struct LargeWidgetTrendArea: Shape {
    let heights: [Double]
    var inset: CGFloat = NetWorthTrendLayout.trendInset

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let pts: [CGPoint] = LargeWidgetTrendMath.points(heights: heights, width: rect.width, height: rect.height,
                                                          inset: inset)
        guard let first = pts.first, let last = pts.last, pts.count >= 2 else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x, y: rect.maxY))
        for p in pts {
            path.addLine(to: CGPoint(x: rect.minX + p.x, y: rect.minY + p.y))
        }
        path.addLine(to: CGPoint(x: rect.minX + last.x, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 走勢：全彩＝淡填色＋藍線；著色模式＝只有線（ink＋重點色）。不標金額軸。外面給高度（trendChartHeight）
struct LargeWidgetTrendLine: View {
    let heights: [Double]
    let palette: WidgetPalette

    private var lineColor: Color {
        palette.isMono ? palette.ink : palette.variableTop
    }

    private var fill: LinearGradient {
        LinearGradient(colors: [palette.variableTop.opacity(0.30), palette.variableTop.opacity(0)],
                       startPoint: .top, endPoint: .bottom)
    }

    private var lineStyle: StrokeStyle {
        StrokeStyle(lineWidth: NetWorthTrendLayout.trendLineWidth, lineCap: .round, lineJoin: .round)
    }

    var body: some View {
        ZStack {
            area
            LargeWidgetTrendShape(heights: heights)
                .stroke(lineColor, style: lineStyle)
                .widgetAccentable()
        }
    }

    @ViewBuilder
    private var area: some View {
        if !palette.isMono {
            LargeWidgetTrendArea(heights: heights)
                .fill(fill)
        }
    }
}

// MARK: 記帳台（大）加「今天記的」的高度

/// 第二版那一欄（整寬還能花 → 2×2 卡片）下面多一塊「今天記的」：區標 20（上面空 8＋字 12）＋每筆 17。
/// 依序試：筆數 4 → 3 → 2 → 1；同一個筆數先試帶頁腳、再不帶；卡片 76 → 68 → 60。都放不下＝第二版（0 筆）
enum LedgerDeskTodayLayout {
    static let sectionHeight: CGFloat = 20
    static let rowHeight: CGFloat = 17
    static let maxRows = 4
    static let rowLimits: [Int] = [4, 3, 2, 1]

    struct Plan: Equatable {
        let tileHeight: CGFloat
        let showsFooter: Bool
        /// 今天記的放幾筆（0＝整塊不畫，連區標；版面同第二版）
        let todayRows: Int
    }

    static func todayHeight(rows n: Int) -> CGFloat {
        guard n > 0 else { return 0 }
        return sectionHeight + CGFloat(n) * rowHeight
    }

    static func height(_ plan: Plan, tileCount: Int) -> CGFloat {
        let base = LedgerDeskLargeLayout.Plan(tileHeight: plan.tileHeight, showsFooter: plan.showsFooter)
        return LedgerDeskLargeLayout.height(base, tileCount: tileCount) + todayHeight(rows: plan.todayRows)
    }

    /// entryCount：快照有幾筆今天記的（舊快照、過了午夜 0）
    static func plan(available: CGFloat, tileCount: Int, hasFooter: Bool, entryCount: Int) -> Plan {
        let count: Int = min(maxRows, max(0, entryCount))
        let tiles: [CGFloat] = [LedgerDeskLargeLayout.tallTileHeight, LedgerDeskLargeLayout.tileHeight,
                                LedgerDeskLargeLayout.compactTileHeight]
        let footers: [Bool] = hasFooter ? [true, false] : [false]
        if count > 0 {
            var tried: [Int] = []
            for limit in rowLimits {
                let rows: Int = min(limit, count)
                if tried.contains(rows) { continue }
                tried.append(rows)
                for footer in footers {
                    for t in tiles {
                        let p = Plan(tileHeight: t, showsFooter: footer, todayRows: rows)
                        if LargeWidgetFit.fits(height(p, tileCount: tileCount), in: available) { return p }
                    }
                }
            }
        }
        let base = LedgerDeskLargeLayout.plan(available: available, tileCount: tileCount, hasFooter: hasFooter)
        return Plan(tileHeight: base.tileHeight, showsFooter: base.showsFooter, todayRows: 0)
    }

    static func candidates(tileCount: Int, hasFooter: Bool, entryCount: Int) -> [Plan] {
        LargeWidgetFit.candidates { (h: CGFloat) -> Plan in
            plan(available: h, tileCount: tileCount, hasFooter: hasFooter, entryCount: entryCount)
        }
    }
}

// MARK: - [v25.638 large4] 第四版共用：一按就記（大）、部屬今天（大，只放數字）
//
// 規格見 scratchpad/radar/build/large4/brief.md（主控定案）；judge_largewidgets.md §C 第四版。
// **上面第一、二、三版的部分一個字都不改**（keycheck_large4 檢查 a306017 的這個檔是現在這個檔的開頭）。
// 總設計先做好，G1（一按就記）、G2（部屬今天）只呼叫、不改。sim_large4.py 一個函式一個函式對照。
//
// 這一段提供：
//   • QuickRecordLargeLayout   一按就記・大：畫幾個範本（最多 8）、最後一格「＋ 記一筆」、幾排、按鈕多高、頁腳畫不畫
//   • TeamLargeLayout          部屬今天・大：明天那一行畫不畫、各廠區表放幾列
//   • TeamLargeCell／TeamLargePlantRow／TeamLargeModel
//                              部屬今天・大要畫的東西：**只有數字**（人數、件數）與 App 寫的班別字、日期字、廠區字。
//                              沒有任何名字、假別、事由、生日、分數、評價、任務主題；不讀「顯示名字」「顯示假別」
//                              （make 根本不拿設定，只拿快照、時間、廠區）

// MARK: 一按就記（大）的格子與高度

/// ① 表頭（「一按就記」＋右邊「待入帳 2 筆」；剛記完換成既有的「✓ 已記…・復原」）→ ② 2×4 範本按鈕
///（範本不滿 8 個時最後一格「＋ 記一筆」，其餘格子不畫）→ ③ 頁腳「打開 LifeGood 就會記進帳本」。
/// 放不下照順序砍：按鈕 60 → 52 → 46pt（都 ≥ 44pt）、先帶頁腳再不帶。字級不變、格數不變
enum QuickRecordLargeLayout {
    /// 表頭一行（字 12pt；剛記完的橫幅也在這一行）
    static let headerHeight: CGFloat = 28
    /// 表頭和第一排按鈕之間
    static let gridTopGap: CGFloat = 8
    /// 按鈕左右、上下的間距
    static let tileSpacing: CGFloat = 8
    /// 一排幾格
    static let columns = 2
    /// 最多幾格（App 最多寫 8 個範本：WidgetMoneyExtras.templateMaxCount）
    static let maxTiles = 8
    /// 按鈕高（依序試）；最矮的也 ≥ 44pt
    static let tallTileHeight: CGFloat = 60
    static let tileHeight: CGFloat = 52
    static let compactTileHeight: CGFloat = 46
    /// 頁腳（LargeWidgetFooterLine：字貼底）
    static let footerHeight: CGFloat = 20

    struct Plan: Equatable {
        let tileHeight: CGFloat
        let showsFooter: Bool
    }

    /// 畫幾個範本（大型最多 8；小型、中型照舊只畫前 4 個，不經過這裡）
    static func templateLimit(_ templateCount: Int) -> Int {
        min(maxTiles, max(0, templateCount))
    }

    /// 最後一格放不放「＋ 記一筆」：有範本、而且不滿 8 個（0 個範本畫一句說明，不畫格子）
    static func showsAddTile(templateCount: Int) -> Bool {
        let n: Int = templateLimit(templateCount)
        return n > 0 && n < maxTiles
    }

    /// 一共幾格（範本＋「＋ 記一筆」）：0 → 0、1 → 2、4 → 5、7 → 8、8 → 8、9 → 8
    static func cellCount(templateCount: Int) -> Int {
        let n: Int = templateLimit(templateCount)
        return showsAddTile(templateCount: n) ? n + 1 : n
    }

    /// 幾排（一排 2 格；最多 4 排）
    static func rows(cellCount: Int) -> Int {
        let n: Int = min(maxTiles, max(0, cellCount))
        return (n + columns - 1) / columns
    }

    /// 照 2 格一排切（最多 8 格）；最後一排只有 1 格時右邊由畫面補空白（按鈕大小不變）
    static func chunked<T>(_ cells: [T]) -> [[T]] {
        let n: Int = min(maxTiles, cells.count)
        var out: [[T]] = []
        var i: Int = 0
        while i < n {
            let end: Int = min(i + columns, n)
            out.append(Array(cells[i..<end]))
            i = end
        }
        return out
    }

    static func height(_ plan: Plan, rows: Int) -> CGFloat {
        let stack: CGFloat = LargeWidgetFit.stack(rows: rows, rowHeight: plan.tileHeight, spacing: tileSpacing)
        let grid: CGFloat = rows > 0 ? gridTopGap + stack : 0
        let footer: CGFloat = plan.showsFooter ? footerHeight : 0
        return headerHeight + grid + footer
    }

    /// 先帶頁腳試按鈕 60 → 52 → 46，再不帶頁腳試一次；都放不下＝46、不帶頁腳
    static func plan(available: CGFloat, rows: Int) -> Plan {
        let heights: [CGFloat] = [tallTileHeight, tileHeight, compactTileHeight]
        let footers: [Bool] = [true, false]
        for footer in footers {
            for h in heights {
                let p = Plan(tileHeight: h, showsFooter: footer)
                if LargeWidgetFit.fits(height(p, rows: rows), in: available) { return p }
            }
        }
        return Plan(tileHeight: compactTileHeight, showsFooter: false)
    }

    static func candidates(rows: Int) -> [Plan] {
        LargeWidgetFit.candidates { (h: CGFloat) -> Plan in
            plan(available: h, rows: rows)
        }
    }
}

// MARK: 部屬今天（大）的高度

/// ① 表頭「部屬」（選了廠區「部屬 A」）＋右邊「10/13 週二」→ ② 今天三格（請假一定第一格）→ ③「明天 10/14 週三
/// 請假 1・大夜 3・小夜 2」→ ④「任務」區標＋四格件數（逾期、今天到期、未完成、週報逾期）→ ⑤「各廠區」表（2 個以上廠區才畫）。
/// 放不下照順序砍：⑤ 6 → 5 → 4 → 3 → 2 列（超過的併成「其他 N 區」）→ 不畫 ⑤ → 不畫 ③。字級不變
enum TeamLargeLayout {
    static let headerHeight: CGFloat = 28
    /// ② 上面空 8＋格子 60（班別字 12pt＋大數字 28pt）
    static let cellsTopGap: CGFloat = 8
    static let cellHeight: CGFloat = 60
    static let cellSpacing: CGFloat = 8
    /// ③ 上面空 8＋一行 18
    static let tomorrowHeight: CGFloat = 26
    /// ④ 區標（上面空 10＋字 14）＋四格
    static let taskLabelHeight: CGFloat = 24
    static let taskTileHeight: CGFloat = 46
    static let taskTileSpacing: CGFloat = 6
    /// ⑤ 區標那一行（「各廠區」＋欄名「逾期 今天到期 未完成 週報逾期」）＋每列
    static let plantLabelHeight: CGFloat = 24
    static let plantRowHeight: CGFloat = 20
    /// ⑤ 每個數字欄的寬（廠區字吃剩下的寬）
    static let plantColumnWidth: CGFloat = 46
    static let maxPlantRows = 6
    /// 依序試的廠區列數（少於 2 列不畫表）
    static let plantLimits: [Int] = [6, 5, 4, 3, 2]

    struct Plan: Equatable {
        /// 畫不畫 ③ 明天那一行
        let showsTomorrow: Bool
        /// ⑤ 放幾列（0＝整塊不畫，連區標）
        let plantRows: Int
    }

    /// ①②④ 一定有的那幾塊多高
    static var fixedHeight: CGFloat {
        headerHeight + cellsTopGap + cellHeight + taskLabelHeight + taskTileHeight
    }

    /// ⑤ n 列多高（少於 2 列 0）
    static func plantHeight(rows n: Int) -> CGFloat {
        guard n >= 2 else { return 0 }
        return plantLabelHeight + CGFloat(n) * plantRowHeight
    }

    static func height(_ plan: Plan) -> CGFloat {
        let tomorrow: CGFloat = plan.showsTomorrow ? tomorrowHeight : 0
        return fixedHeight + tomorrow + plantHeight(rows: plan.plantRows)
    }

    /// hasTomorrow：快照有明天那一份；plantCount：要列的廠區數（選了廠區、只有一個廠區時 0）
    static func plan(available: CGFloat, hasTomorrow: Bool, plantCount: Int) -> Plan {
        let count: Int = min(maxPlantRows, max(0, plantCount))
        if count >= 2 {
            var tried: [Int] = []
            for limit in plantLimits {
                let rows: Int = min(limit, count)
                if tried.contains(rows) { continue }
                tried.append(rows)
                let p = Plan(showsTomorrow: hasTomorrow, plantRows: rows)
                if LargeWidgetFit.fits(height(p), in: available) { return p }
            }
        }
        let noTable = Plan(showsTomorrow: hasTomorrow, plantRows: 0)
        if LargeWidgetFit.fits(height(noTable), in: available) { return noTable }
        return Plan(showsTomorrow: false, plantRows: 0)
    }

    static func candidates(hasTomorrow: Bool, plantCount: Int) -> [Plan] {
        LargeWidgetFit.candidates { (h: CGFloat) -> Plan in
            plan(available: h, hasTomorrow: hasTomorrow, plantCount: plantCount)
        }
    }
}

// MARK: 部屬今天（大）要畫的東西（只有數字）

/// 今天的一格：班別字（App 寫的「請假」「大夜」）＋人數。**沒有名字**
struct TeamLargeCell: Equatable, Identifiable {
    /// 「leave」「shift-大夜」（WidgetTeamCell.id）
    let id: String
    let label: String
    let count: Int
}

/// 各廠區表的一列：廠區字＋四個件數。**沒有名字**
struct TeamLargePlantRow: Equatable, Identifiable {
    /// 「p:A」；未分廠區「p:」；併起來的那一列「more」
    let id: String
    /// 「A」「未分廠區」「其他 3 區」
    let area: String
    let overdue: Int
    let dueToday: Int
    let open: Int
    let reports: Int
}

/// 部屬今天・大。make 只拿快照、時間、廠區（**不拿「顯示名字」「顯示假別」**），
/// 只抄人數、件數、App 寫的班別字與日期字；名字、假別、事由、生日、任務主題一個都不存
struct TeamLargeModel: Equatable {
    /// 「未分廠區」（廠區是空字串的那一筆）
    static let unassignedText = "未分廠區"

    /// 沒快照、沒有部屬、過期：只寫一句話
    var isMessage = true
    var message = ""
    var hint = ""
    /// 「部屬」；選了廠區「部屬 A」
    var title = ""
    /// 「10/13 週二」
    var dateText = ""
    /// 今天最多三格：請假一定第一格（0 人也有），再來人數多的班別（同中型 WidgetTeamSummary.cells）
    var cells: [TeamLargeCell] = []
    /// 今天有沒有排班（只有請假那一格時右邊寫「今天沒有排班」）
    var hasShifts = false
    /// 「10/14 週三」；沒有明天那一份（過了午夜 App 沒開）是空字串
    var tomorrowDate = ""
    /// 「請假 1・大夜 3・小夜 2」；沒有明天那一份是空字串
    var tomorrowLine = ""
    var overdueTasks = 0
    var dueTodayTasks = 0
    var openTasks = 0
    var overdueReports = 0
    /// 四個件數都是 0（區標右邊寫「都完成了」）
    var allDone = false
    /// 各廠區（App 的順序：廠區清單排好、未分廠區最後）；2 個以上才有，選了廠區時空的
    var plants: [TeamLargePlantRow] = []

    var hasTomorrow: Bool { !tomorrowLine.isEmpty }

    static func make(snapshot: WidgetLifeSnapshot?, date: Date, plantArea: String?) -> TeamLargeModel {
        var m = TeamLargeModel()
        guard let snap = snapshot else {
            m.message = "打開 LifeGood 一次，這裡就會出現部屬今天"
            return m
        }
        guard snap.hasTeam == true else {
            m.message = "還沒有部屬資料"
            m.hint = "在 App 的部屬管理加入"
            return m
        }
        guard !snap.isExpired(at: date), let day = snap.teamDay(at: date) else {
            m.message = "打開 LifeGood 更新"
            return m
        }
        m.isMessage = false
        fillToday(&m, day: day, plantArea: plantArea)
        fillTomorrow(&m, snap: snap, today: day, plantArea: plantArea)
        m.plants = plantList(day.counts, plantArea: plantArea)
        return m
    }

    /// 標題、三格、四個件數（只抄 label 與人數；cells 的 people 不碰名字）
    private static func fillToday(_ m: inout TeamLargeModel, day: WidgetTeamDay, plantArea: String?) {
        let summary: WidgetTeamSummary = day.summary(plantArea: plantArea)
        if let plant = plantArea, !plant.isEmpty {
            m.title = "部屬 " + plant
        } else {
            m.title = "部屬"
        }
        m.dateText = summary.dateText
        m.cells = summary.cells.map { (c: WidgetTeamCell) -> TeamLargeCell in
            TeamLargeCell(id: c.id, label: c.label, count: c.count)
        }
        m.hasShifts = summary.cells.contains { (c: WidgetTeamCell) -> Bool in !c.isLeave }
        m.overdueTasks = summary.overdueTasks
        m.dueTodayTasks = summary.dueTodayTasks
        m.openTasks = summary.openTasks
        m.overdueReports = summary.overdueReports
        m.allDone = summary.overdueTasks == 0 && summary.dueTodayTasks == 0
            && summary.openTasks == 0 && summary.overdueReports == 0
    }

    /// 明天那一份（今天那一份結束那一刻的那一份）；沒有、或跟今天是同一份就不畫
    private static func fillTomorrow(_ m: inout TeamLargeModel, snap: WidgetLifeSnapshot, today: WidgetTeamDay,
                                     plantArea: String?) {
        guard let next = snap.teamDay(at: today.dayEnd), next.dayKey != today.dayKey else { return }
        let summary: WidgetTeamSummary = next.summary(plantArea: plantArea)
        m.tomorrowDate = next.dateText
        m.tomorrowLine = summary.countsLine()
    }

    /// 各廠區：選了廠區、或只有一個廠區（含只有未分廠區）時空的
    private static func plantList(_ counts: [WidgetTeamCounts], plantArea: String?) -> [TeamLargePlantRow] {
        if let plant = plantArea, !plant.isEmpty { return [] }
        guard counts.count >= 2 else { return [] }
        return counts.map { (c: WidgetTeamCounts) -> TeamLargePlantRow in
            let area: String = c.plantArea.isEmpty ? unassignedText : c.plantArea
            return TeamLargePlantRow(id: "p:" + c.plantArea, area: area, overdue: c.overdueTasks,
                                     dueToday: c.dueTodayTasks, open: c.openTasks, reports: c.overdueReports)
        }
    }

    /// 表上要畫的列：放得下就全部；放不下時前 limit − 1 個廠區＋「其他 N 區」（四個件數加起來）。limit < 2 回空的
    func plantRows(limit: Int) -> [TeamLargePlantRow] {
        guard limit >= 2, plants.count >= 2 else { return [] }
        if plants.count <= limit { return plants }
        let shown: [TeamLargePlantRow] = Array(plants.prefix(limit - 1))
        let rest: [TeamLargePlantRow] = Array(plants.dropFirst(limit - 1))
        var overdue: Int = 0
        var dueToday: Int = 0
        var open: Int = 0
        var reports: Int = 0
        for p in rest {
            overdue += p.overdue
            dueToday += p.dueToday
            open += p.open
            reports += p.reports
        }
        let more = TeamLargePlantRow(id: "more", area: "其他 " + String(rest.count) + " 區", overdue: overdue,
                                     dueToday: dueToday, open: open, reports: reports)
        return shown + [more]
    }
}
