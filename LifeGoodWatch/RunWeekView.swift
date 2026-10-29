import SwiftUI

// MARK: - 這週（手錶 v5，v25.582；watch/judge.md §2.13、§2.17、§2.18；watch/build/v5/brief.md G3-1）
//
// 只屬於 LifeGoodWatch。名字 RunWeekView() 不准改（RootView 的 WatchRoute.runWeek 在叫）。只 import SwiftUI。
// 第二層（點 ③ 看板推進來：WatchModel.openRunWeek；NavigationStack 那一層，背景純黑 .containerBackground(Color.black, for: .navigation)）：
//   7 根小柱（週一到週日；這週主角的運動色 WatchStyle.sport：跑 EB6834、走 1BAF7A、騎 2A78D6、登山 EDA100；
//     沒動那天一個 3 點小圓點；今天下面一個小點；柱高 40 點、寬 ≥ 2 點；整塊 56 點）
//   「連續 6 週・最快 5 公里 30:51（今天）」（Footnote semibold、B9C7EE、最多 2 行）
//   新到舊最多 5 列：28 點運動色圓（白圖示，深色組：跑 D95926、走 199E70、騎 2A78D6、登山 C98500）＋兩行（「河濱晨跑」／「今天 06:05・5.20 公里・⌚︎」）→ 點了 WatchModel.openRunDetail(row.id)
//   這週一趟都沒有：「這週還沒動，跑完會出現在這裡」；最下面灰字（「iPhone 還沒算這週」／「iPhone 10/21 22:10 更新」）
// 字全部是 WatchRunWeekText.weekPage 組好的（View 不加減公里、不拼字、不格式化時間）。
// 手腕放下（§2.17）：名字換 privateTitle（「晨跑」）、背景純黑、字 0.75、小柱換 1.5 點 40% 白外框線、
//   點列暫時不能按（不拿掉，版面不跳）；公里、時間、次數照顯示（§6.1）。
// 每分鐘重算一次（TimelineView）：過了午夜「今天」換天、手錶剛跑完的那一趟（WatchRunLog）馬上算進去。

struct RunWeekView: View {
    @ObservedObject private var model = WatchModel.shared
    @Environment(\.isLuminanceReduced) private var dimmed

    /// 手腕放下時字調暗
    static let dimmedOpacity: Double = 0.75

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .navigationTitle(WatchRunWeekText.weekTitle)
        .containerBackground(Color.black, for: .navigation)
    }

    // MARK: 內容

    private func content(now: Date) -> some View {
        let page = WatchRunWeekText.weekPage(package: model.package, own: WatchRunLog.all(), now: now,
                                             lastSport: WatchRunPrefs.lastSport)
        return ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                RunWeekBarsView(bars: page.bars, sport: page.sport, dimmed: dimmed)
                lineText(page.line)
                rowList(page.rows)
                notes(page)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scenePadding(.horizontal)
            .opacity(dimmed ? Self.dimmedOpacity : 1)
        }
    }

    /// 「連續 6 週・最快 5 公里 30:51（今天）」；都沒有不畫
    @ViewBuilder
    private func lineText(_ line: String?) -> some View {
        if let line {
            Text(line)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchStyle.dateText)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 新到舊最多 5 列（WatchRunWeekText.maxRows）
    private func rowList(_ rows: [WatchRunRow]) -> some View {
        ForEach(rows) { row in
            rowButton(row)
        }
    }

    /// 一列 → 那一趟
    private func rowButton(_ row: WatchRunRow) -> some View {
        Button {
            model.openRunDetail(row.id)
        } label: {
            RunWeekRowLabel(row: row, dimmed: dimmed)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
    }

    /// 「這週還沒動，跑完會出現在這裡」、「iPhone 10/21 22:10 更新」
    @ViewBuilder
    private func notes(_ page: WatchRunWeekPage) -> some View {
        if let empty = page.empty {
            RunWeekNote(text: empty)
        }
        if let foot = page.footnote {
            RunWeekNote(text: foot)
                .padding(.top, 2)
        }
    }
}

// MARK: - 7 根小柱（週一到週日；高 56：柱 40＋字 11＋今天的小點 3）

private struct RunWeekBarsView: View {
    let bars: [WatchRunBar]
    let sport: WatchSport
    let dimmed: Bool

    /// 柱最高（judge §2.13「7 根小柱高 40 點」）
    static let barArea: CGFloat = 40
    /// 柱最矮（有公里但很少的那天也看得到）
    static let barMin: CGFloat = 3
    static let barWidth: CGFloat = 10
    static let corner: CGFloat = 2
    /// 沒動那天的小圓點、今天下面的小點
    static let dotSize: CGFloat = 3
    static let labelSize: CGFloat = 10
    static let labelHeight: CGFloat = 11
    static let spacing: CGFloat = 1
    /// 手腕放下的外框線（judge §2.17：1.5 點 40% 白）
    static let dimLine: CGFloat = 1.5

    /// 整塊的高（56）
    static var height: CGFloat {
        barArea + labelHeight + dotSize + spacing * 2
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(bars) { bar in
                column(bar)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func column(_ bar: WatchRunBar) -> some View {
        VStack(spacing: Self.spacing) {
            barMark(bar)
                .frame(height: Self.barArea, alignment: .bottom)
            Text(bar.label)
                .font(.system(size: Self.labelSize))
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
                .frame(height: Self.labelHeight)
            todayDot(bar.isToday)
        }
        .frame(maxWidth: .infinity)
    }

    /// 有公里：圓角柱（高＝那天 ÷ 這週最多那天）；0：3 點小圓點
    @ViewBuilder
    private func barMark(_ bar: WatchRunBar) -> some View {
        if bar.km > 0 {
            filledBar
                .frame(width: Self.barWidth, height: barHeight(bar))
        } else {
            Circle()
                .fill(emptyColor)
                .frame(width: Self.dotSize, height: Self.dotSize)
        }
    }

    /// 抬手：運動色實心；手腕放下：1.5 點 40% 白外框線
    @ViewBuilder
    private var filledBar: some View {
        if dimmed {
            RoundedRectangle(cornerRadius: Self.corner)
                .strokeBorder(Color.white.opacity(0.4), lineWidth: Self.dimLine)
        } else {
            RoundedRectangle(cornerRadius: Self.corner)
                .fill(WatchStyle.sport(sport))
        }
    }

    /// 今天下面一個小點；其他天留同樣的位置（版面不跳）
    private func todayDot(_ isToday: Bool) -> some View {
        Circle()
            .fill(isToday ? WatchStyle.primary : Color.clear)
            .frame(width: Self.dotSize, height: Self.dotSize)
    }

    /// 0～1 → 3～40 點（NaN、超出範圍夾住）
    private func barHeight(_ bar: WatchRunBar) -> CGFloat {
        let h = bar.height.isFinite ? min(max(bar.height, 0), 1) : 0
        return max(Self.barMin, Self.barArea * CGFloat(h))
    }

    private var emptyColor: Color {
        dimmed ? Color.white.opacity(0.4) : WatchStyle.small.opacity(0.6)
    }
}

// MARK: - 一列（28 點運動色圓＋「河濱晨跑」／「今天 06:05・5.20 公里・⌚︎」）

private struct RunWeekRowLabel: View {
    let row: WatchRunRow
    let dimmed: Bool

    /// 圖示圓直徑
    static let iconSize: CGFloat = 28

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            iconCircle
            texts
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var iconCircle: some View {
        Image(systemName: row.sport.icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: Self.iconSize, height: Self.iconSize)
            .background(Circle().fill(circleFill))
    }

    /// 白圖示的實心圓用深色組（judge §2.13「28 點運動色圓（深色組 D95926）」、U4 §4.3 第 14 條：白圖示對色塊要 3:1；
    /// 亮色組 EB6834 等是線和字用的，走 1BAF7A、登山 EDA100 配白圖示不到 3:1）
    private var circleFill: Color {
        Color(watchHex: Self.circleHex(row.sport))
    }

    /// 跑 D95926、走 199E70、騎 2A78D6、登山 C98500
    static func circleHex(_ sport: WatchSport) -> UInt32 {
        switch sport {
        case .run: return 0xD95926
        case .walk: return 0x199E70
        case .bike: return 0x2A78D6
        case .hike: return 0xC98500
        }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(row.line)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// 抬手「河濱晨跑」；手腕放下「晨跑」（不寫地名，judge §2.17）
    private var title: String {
        dimmed ? row.privateTitle : row.title
    }
}

// MARK: - 灰字（「這週還沒動…」「iPhone 10/21 22:10 更新」）

private struct RunWeekNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(WatchStyle.small)
            .fixedSize(horizontal: false, vertical: true)
    }
}
