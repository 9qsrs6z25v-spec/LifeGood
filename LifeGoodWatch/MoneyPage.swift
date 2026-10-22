import SwiftUI

// MARK: - ② 錢（judge §2.4、§2.17；brief G3-4；§13-8）（手錶 v1，v25.574）
//
// 只屬於 LifeGoodWatch。垂直翻頁的第二頁，夜空底；iPhone 關掉「送到手錶：錢」整頁不出現（RootView 看 WatchModel.showsMoney）。
// 字全部是 WatchText.money 組好的（WatchMoneyView）＝iPhone 寫好的 WidgetMoneyDay.lines(hidden:)：手錶不加減、不拼金額。
//   抬手：「本月還能花・10/22 週四」／大字「2.4萬」那一句／「每天 …・還有 10 天」／細條／「今天 …・2 筆」／「💳 10/27（二）卡費・5 天後 ›」
//   遮住（手腕放下、沒解鎖、手錶「遮住金額」、iPhone「隱藏金額」任一個）：整組換隱藏版「本月已花／72%／還有 10 天／今天 2 筆」，
//   細條照畫（只透露比例，跟 72% 一樣），卡費那列本來就只有類別字＋日期（§13-8：沒有卡名、沒有金額）。
//   超支：大字紅（遮住時不紅）。41mm：大字 34、第二行不寫「還有 N 天」、卡費日期不寫星期（WatchText 依 compact 組好）。
// 點「💳 …」→ 接下來要繳（WatchRoute.bills）。v1 沒有〔＋ 記一筆〕、🧾 手機條碼、「今天 N 筆 ›」（v2）。
// 手上沒有包：大字「—」＋〔再試一次〕（judge §2.0）。最下面資料多舊（FreshnessFooter；過期那一句已經寫在第二行，不重複）。

struct MoneyPage: View {
    @ObservedObject private var model = WatchModel.shared
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.redactionReasons) private var reasons

    /// 手腕放下時字調暗
    static let dimmedOpacity: Double = 0.75
    /// 要繳那一列的圖示（WatchText 沒給時）
    static let defaultBillIcon = "creditcard.fill"

    private var privacy: WatchPrivacy {
        model.privacy(dimmed: dimmed, redacted: reasons.contains(.privacy))
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .containerBackground(for: .tabView) {
            pageBackground
        }
    }

    @ViewBuilder
    private var pageBackground: some View {
        if dimmed {
            Color.black
        } else {
            WatchStyle.sky
        }
    }

    private func content(now: Date) -> some View {
        let money = WatchText.money(package: model.package, now: now,
                                    masked: privacy.masksAmounts, compact: WatchStyle.isCompact)
        let freshness: WatchFreshness? = money.mode == .normal
            ? WatchText.moneyFreshness(package: model.package, now: now)
            : nil
        return VStack(alignment: .leading, spacing: 3) {
            titleText(money)
            heroText(money)
            lineText(money)
            barView(money)
            todayText(money)
            billRow(money)
            retryRow(money)
            FreshnessFooter(freshness: freshness)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scenePadding(.horizontal)
        .opacity(dimmed ? Self.dimmedOpacity : 1)
    }

    // MARK: 字

    /// 「本月還能花・10/22 週四」／遮住「本月已花・10/22 週四」
    private func titleText(_ m: WatchMoneyView) -> some View {
        Text(m.title)
            .font(.footnote)
            .foregroundStyle(WatchStyle.small)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// 大字（iPhone 寫好的 hero；遮住「72%」）；超支紅
    private func heroText(_ m: WatchMoneyView) -> some View {
        Text(m.hero)
            .font(WatchStyle.heroFont(compact: WatchStyle.isCompact))
            .monospacedDigit()
            .foregroundStyle(m.heroIsRed ? WatchStyle.red : WatchStyle.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    /// 「每天 …・還有 10 天」／遮住「還有 10 天」
    private func lineText(_ m: WatchMoneyView) -> some View {
        Text(m.line)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(WatchStyle.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private func barView(_ m: WatchMoneyView) -> some View {
        if let bar = m.bar {
            WatchMoneyBarView(bar: bar)
                .frame(height: WatchMoneyBarView.height)
                .padding(.vertical, 2)
        }
    }

    /// 「今天 …・2 筆」／遮住「今天 2 筆」（v1 不能點）
    @ViewBuilder
    private func todayText(_ m: WatchMoneyView) -> some View {
        if let today = m.today {
            Text(today)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// 「💳 10/27（二）卡費・5 天後 ›」→ 接下來要繳
    @ViewBuilder
    private func billRow(_ m: WatchMoneyView) -> some View {
        if let bill = m.bill {
            NavigationLink(value: WatchRoute.bills) {
                WatchMoneyBillLabel(icon: m.billIcon ?? Self.defaultBillIcon, text: bill)
            }
            .buttonStyle(.plain)
            .disabled(dimmed)
        }
    }

    /// 手上沒有包：〔再試一次〕
    @ViewBuilder
    private func retryRow(_ m: WatchMoneyView) -> some View {
        if m.mode == .noPackage {
            WatchRetryButton(asking: model.asking, failed: model.askFailed, dimmed: dimmed) {
                model.requestFromPhone()
            }
        }
    }
}

// MARK: - 要繳那一列

private struct WatchMoneyBillLabel: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WatchStyle.small)
                .frame(width: 14)
            Text(text)
                .font(.footnote)
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WatchStyle.small)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 細條（6 點高；固定紫＋變動藍，收入那一道 1 點白線，超過收入那一截紅）

/// 照 iPhone 小工具 MoneyLeftBar 的算法（LifeGoodWidgets/MoneyLeftWidget.swift）：比例都夾在 0…1，
/// 變動接在固定後面、不超過剩下的長度；收入線有值才畫、超過它的那一截畫紅。手腕放下只跟著整頁降透明度
private struct WatchMoneyBarView: View {
    let bar: WidgetMoneyBar

    /// 整格高（收入線的高度）；橫條本身 6 點
    static let height: CGFloat = 10
    static let trackHeight: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            layers(width: geo.size.width, height: geo.size.height)
        }
    }

    private func layers(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            fills(width: width)
                .frame(width: width, height: Self.trackHeight)
                .clipShape(Capsule())
            incomeTick(width: width, height: height)
        }
        .frame(width: width, height: height, alignment: .leading)
    }

    private func fills(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.15))
            Rectangle()
                .fill(WatchStyle.fixedBar)
                .frame(width: fixedWidth(width))
            Rectangle()
                .fill(WatchStyle.variableBar)
                .frame(width: variableWidth(width))
                .offset(x: fixedWidth(width))
            overSegment(width: width)
        }
    }

    /// 超過收入的那一截（紅）
    @ViewBuilder
    private func overSegment(width: CGFloat) -> some View {
        if let span = overSpan() {
            Rectangle()
                .fill(WatchStyle.red)
                .frame(width: width * span.length)
                .offset(x: width * span.start)
        }
    }

    /// 收入那一道 1 點白線（比橫條高一點）
    @ViewBuilder
    private func incomeTick(width: CGFloat, height: CGFloat) -> some View {
        if let income = bar.income {
            Rectangle()
                .fill(Color.white)
                .frame(width: 1, height: height)
                .offset(x: tickX(income: income, width: width))
        }
    }

    // 比例 → 寬度

    private func clamp(_ value: Double) -> CGFloat {
        guard value.isFinite else { return 0 }
        return CGFloat(min(max(value, 0), 1))
    }

    private func fixedWidth(_ width: CGFloat) -> CGFloat {
        width * clamp(bar.fixed)
    }

    private func variableWidth(_ width: CGFloat) -> CGFloat {
        let room: CGFloat = 1 - clamp(bar.fixed)
        let part: CGFloat = min(clamp(bar.variable), room)
        return width * part
    }

    /// (起點, 長度)，都是 0…1；沒超過收入是 nil
    private func overSpan() -> (start: CGFloat, length: CGFloat)? {
        guard let income = bar.income else { return nil }
        let line: CGFloat = clamp(income)
        let fixed: CGFloat = clamp(bar.fixed)
        let used: CGFloat = min(fixed + min(clamp(bar.variable), 1 - fixed), 1)
        guard used > line else { return nil }
        return (start: line, length: used - line)
    }

    private func tickX(income: Double, width: CGFloat) -> CGFloat {
        let x: CGFloat = width * clamp(income) - 0.5
        let maxX: CGFloat = max(width - 1, 0)
        return min(max(x, 0), maxX)
    }
}
