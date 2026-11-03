import SwiftUI
import WatchKit

// MARK: - ① 今天（judge §2.1；brief G3-1）（手錶 v1，v25.574）
//
// 只屬於 LifeGoodWatch。垂直翻頁的第一頁（RootView 的 TabView），夜空底；手腕放下純黑、字調暗、版面不動。
// 字全部是 WatchText.today 組好的（WatchToday）；這裡只排版、挑手腕放下用哪一個字，不拼金額、不讀部屬名字。
//   • 左上「⋯」＝設定（model.sheet = .settings）
//   • 列：最近過去 1 件（灰）＋現在或下一件（亮、多一行）＋接下來 2 件；點一列 → 那一件的細節（WatchRoute.stop）
//   • 「還有 N 件 ›」→ 今天全部（WatchRoute.dayList）
//   • 一句話（都結束了、今天沒排、沒資料、過期）；沒資料、過期多一顆〔再試一次〕（跟 iPhone 要一份）
//   • 今天要留意（最多 2 行）：手腕放下或沒解鎖（hidesPersonal）寫 lockText「家人生日」；
//     點卡費 → 接下來要繳、點生日 → 今天全部（WatchModel.go）
//   • 最下面資料多舊（FreshnessFooter；過期那一句已經寫在上面，不重複）
// 沒有列的時候（今天沒排、沒資料、過期）日期當大字（judge §2.0「① 大字 10/22 週四」；大字＝WatchStyle.heroFont
// 34／38 heavy rounded 等寬、可縮到 0.6，跟 ② 錢的大字同一種，judge §2.0「字」、§2.18）。
// 字放到 xxLarge 以上、或 40mm（螢幕高不到 200 點）：只畫現在或下一件＋「還有 N 件」，今天要留意也收起來
// （judge §2.1、§2.18 表「40mm：現在或下一件＋還有 N 件」）。
// 收起來的件數加回「還有 N 件」。不加 ScrollView（轉錶冠翻到 ② 錢）。倒數字每分鐘重畫（TimelineView(.everyMinute)）。
// [手錶 v6] v25.578（watch/judge.md §2.14「第一頁最上面寫一行」、§5.6；watch/build/v6/brief.md G3-3）：
//   ① 是第一頁時（不是旅途中；旅途中第一頁是 ④ 旅行，那一行 TripPage 自己畫），手錶的時差跟 iPhone 算包的時區不一樣
//   （WatchTripText.timeZoneHint）→ 最上面琥珀一行「換時區了：打開 iPhone 上的 LifeGood 一次，日期才會對」（兩行、可縮 0.8）；
//   41mm 版面預算：這一行出現時「今天要留意」收起來。v1 的字一個沒改。

struct TodayPage: View {
    @ObservedObject private var model = WatchModel.shared
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.redactionReasons) private var reasons
    @Environment(\.dynamicTypeSize) private var typeSize

    static let settingsLabel = "設定"
    /// 手腕放下時字調暗
    static let dimmedOpacity: Double = 0.75
    /// 40mm（162×197 點）以下：列收成現在或下一件
    static let smallestHeight: CGFloat = 200

    private var privacy: WatchPrivacy {
        model.privacy(dimmed: dimmed, redacted: reasons.contains(.privacy))
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                settingsButton
            }
        }
        .containerBackground(for: .tabView) {
            pageBackground
        }
    }

    // MARK: 外框

    private var settingsButton: some View {
        Button {
            model.sheet = .settings
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(Text(Self.settingsLabel))
        .disabled(dimmed)
    }

    @ViewBuilder
    private var pageBackground: some View {
        if dimmed {
            Color.black
        } else {
            WatchStyle.sky
        }
    }

    /// 40mm（SE，162×197 點）
    private var isSmallest: Bool {
        WKInterfaceDevice.current().screenBounds.height < Self.smallestHeight
    }

    /// 字放到 xxLarge 以上、或 40mm：列只畫現在或下一件＋「還有 N 件」
    private var reduced: Bool {
        typeSize >= .xxLarge || isSmallest
    }

    /// 同上：今天要留意也收起來（judge §2.1、§2.18）
    private var hidesAttention: Bool {
        reduced
    }

    // MARK: 內容

    private func content(now: Date) -> some View {
        let today = WatchText.today(package: model.package, now: now, compact: WatchStyle.isCompact)
        let freshness: WatchFreshness? = today.mode == .expired
            ? nil
            : WatchText.lifeFreshness(package: model.package, now: now)
        // [v6] 換時區那一行：只有 ① 是第一頁時才畫（旅途中第一頁是 ④ 旅行，那一行由 TripPage 畫）
        let tzHint: String? = model.firstPage == .today
            ? WatchTripText.timeZoneHint(package: model.package, now: now)
            : nil
        return VStack(alignment: .leading, spacing: 3) {
            if let hint = tzHint {
                tzHintText(hint)
            }
            header(today)
            rowList(today)
            messageBlock(today)
            // [v6] 41mm 版面預算：換時區那一行出現時「今天要留意」收起來
            if tzHint == nil {
                attentionList(today)
            }
            FreshnessFooter(freshness: freshness)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scenePadding(.horizontal)
        .opacity(dimmed ? Self.dimmedOpacity : 1)
    }

    // MARK: [v6] 換時區（judge §2.14、§5.6）

    /// 「換時區了：打開 iPhone 上的 LifeGood 一次，日期才會對」（琥珀 Footnote、兩行、可縮 0.8；字是 WatchTripText 的）
    private func tzHintText(_ hint: String) -> some View {
        Text(hint)
            .font(.footnote)
            .foregroundStyle(WatchStyle.amber)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }

    // MARK: 最上面那一行

    private func header(_ t: WatchToday) -> some View {
        Text(t.header)
            .font(headerFont(t.mode))
            .foregroundStyle(headerColor(t.mode))
            .lineLimit(1)
            .minimumScaleFactor(headerMinScale(t.mode))
    }

    /// 沒有列的時候日期當大字
    private func isBigHeader(_ mode: WatchToday.Mode) -> Bool {
        switch mode {
        case .empty, .noPackage, .noLife, .expired:
            return true
        case .today, .allDone, .tomorrow:
            return false
        }
    }

    /// 大字＝② 錢的大字那一種（46mm 38、41mm 34 heavy rounded、數字等寬）；平常日期列 Footnote semibold
    private func headerFont(_ mode: WatchToday.Mode) -> Font {
        if isBigHeader(mode) {
            return WatchStyle.heroFont(compact: WatchStyle.isCompact).monospacedDigit()
        }
        return .footnote.weight(.semibold)
    }

    /// 大字可縮到 0.6（judge §2.18）；日期列 0.7
    private func headerMinScale(_ mode: WatchToday.Mode) -> CGFloat {
        isBigHeader(mode) ? 0.6 : 0.7
    }

    private func headerColor(_ mode: WatchToday.Mode) -> Color {
        isBigHeader(mode) ? WatchStyle.primary : WatchStyle.dateText
    }

    // MARK: 列

    @ViewBuilder
    private func rowList(_ t: WatchToday) -> some View {
        ForEach(shownRows(t)) { row in
            NavigationLink(value: WatchRoute.stop(row.id)) {
                WatchTodayRowView(row: row)
            }
            .buttonStyle(.plain)
            .disabled(dimmed)
        }
        if moreCount(t) > 0 {
            NavigationLink(value: WatchRoute.dayList) {
                WatchMoreLabel(count: moreCount(t))
            }
            .buttonStyle(.plain)
            .disabled(dimmed)
        }
    }

    /// 平常照 WatchText 給的列；收起來時只留現在或下一件（晚上換明天時是明天第一件）
    private func shownRows(_ t: WatchToday) -> [WatchTodayRow] {
        guard reduced else { return t.rows }
        if let focus = t.rows.first(where: { $0.state == .focus }) {
            return [focus]
        }
        return Array(t.rows.prefix(1))
    }

    /// 「還有 N 件」：收起來的「接下來」那幾列加回去（過去那一列不算）
    private func moreCount(_ t: WatchToday) -> Int {
        guard reduced else { return t.moreCount }
        let shownIds: Set<String> = Set(shownRows(t).map { $0.id })
        let hidden: Int = t.rows.filter { $0.state == .upcoming && !shownIds.contains($0.id) }.count
        return t.moreCount + hidden
    }

    // MARK: 一句話、再試一次

    @ViewBuilder
    private func messageBlock(_ t: WatchToday) -> some View {
        if let message = t.message {
            Text(message)
                .font(messageFont(t.mode))
                .foregroundStyle(messageColor(t.mode))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let next = t.nextLine {
            Text(next)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        if showsRetry(t.mode) {
            WatchRetryButton(asking: model.asking, failed: model.askFailed, dimmed: dimmed) {
                model.requestFromPhone()
            }
        }
    }

    /// 「今天的行程都結束了」「今天沒排行程」寫大一點；沒資料、過期的說明寫小字
    private func messageFont(_ mode: WatchToday.Mode) -> Font {
        switch mode {
        case .allDone, .empty:
            return .body
        case .noPackage, .noLife, .expired, .today, .tomorrow:
            return .footnote
        }
    }

    private func messageColor(_ mode: WatchToday.Mode) -> Color {
        switch mode {
        case .allDone, .empty:
            return WatchStyle.primary
        case .expired:
            return WatchStyle.amber
        case .noPackage, .noLife, .today, .tomorrow:
            return WatchStyle.small
        }
    }

    /// 手上沒有包、包裡沒有行程、過期：可以跟 iPhone 再要一次
    private func showsRetry(_ mode: WatchToday.Mode) -> Bool {
        switch mode {
        case .noPackage, .noLife, .expired:
            return true
        case .today, .allDone, .tomorrow, .empty:
            return false
        }
    }

    // MARK: 今天要留意

    @ViewBuilder
    private func attentionList(_ t: WatchToday) -> some View {
        if !hidesAttention {
            ForEach(t.attention) { item in
                attentionLine(item)
            }
        }
    }

    @ViewBuilder
    private func attentionLine(_ item: WatchAttention) -> some View {
        if let route = item.route {
            Button {
                model.go(route)
            } label: {
                WatchAttentionLine(attention: item, hidesPersonal: privacy.hidesPersonal)
            }
            .buttonStyle(.plain)
            .disabled(dimmed)
        } else {
            WatchAttentionLine(attention: item, hidesPersonal: privacy.hidesPersonal)
        }
    }
}

// MARK: - 一列（記號＋「09:30 部門會議」；現在或下一件多一行）

private struct WatchTodayRowView: View {
    let row: WatchTodayRow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: WatchText.markSymbol(row.kind))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(markColor)
                    .frame(width: 12)
                Text(line)
                    .font(titleFont)
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
            }
            if let detail = row.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(WatchStyle.countdown)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.leading, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isPast ? 0.5 : 1)
        .contentShape(Rectangle())
    }

    /// 「09:30 部門會議」（時間＋主題；不是金額）
    private var line: String {
        row.time + " " + row.title
    }

    private var isPast: Bool {
        row.state == .past
    }

    private var titleFont: Font {
        row.state == .focus ? .headline : .body
    }

    private var titleColor: Color {
        isPast ? WatchStyle.small : WatchStyle.primary
    }

    /// 種類色（● 部屬會議橘、○ 我的行事曆青、■ 系統行事曆綠）；過去那一列灰
    private var markColor: Color {
        isPast ? WatchStyle.small : WatchStyle.kindColor(row.kind)
    }
}

// MARK: - 「還有 N 件 ›」

private struct WatchMoreLabel: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WatchStyle.small)
        }
        .padding(.leading, 18)
        .contentShape(Rectangle())
    }

    private var text: String {
        "還有 \(count) 件"
    }
}

// MARK: - 今天要留意一行

private struct WatchAttentionLine: View {
    let attention: WatchAttention
    /// 手腕放下、沒解鎖：「媽媽 62 歲生日」→「家人生日」
    let hidesPersonal: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: attention.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 14)
            Text(text)
                .font(.footnote)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var text: String {
        hidesPersonal ? attention.lockText : attention.text
    }

    private var textColor: Color {
        attention.isAmber ? WatchStyle.amber : WatchStyle.primary
    }

    private var iconColor: Color {
        if attention.isAmber { return WatchStyle.amber }
        return attention.kind == .birthday ? WatchStyle.red : WatchStyle.small
    }
}

// MARK: - 〔再試一次〕（① 今天、② 錢沒有資料時；judge §2.0）

/// 〔再試一次〕＋一行小字（正在要「正在跟 iPhone 要…」；沒要到「iPhone 不在旁邊，或 LifeGood 沒打開」琥珀）。
/// action 由頁面給（WatchModel.requestFromPhone）。MoneyPage 也用這一個
struct WatchRetryButton: View {
    let asking: Bool
    let failed: Bool
    /// 手腕放下：變暗、暫時不能按（不拿掉）
    let dimmed: Bool
    let action: () -> Void

    static let title = "再試一次"
    static let askingText = "正在跟 iPhone 要…"
    static let failedText = "iPhone 不在旁邊，或 LifeGood 沒打開"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: action) {
                Label(Self.title, systemImage: "arrow.clockwise")
            }
            .disabled(asking || dimmed)
            if let note = noteText {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(noteColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noteText: String? {
        if asking { return Self.askingText }
        if failed { return Self.failedText }
        return nil
    }

    private var noteColor: Color {
        (failed && !asking) ? WatchStyle.amber : WatchStyle.small
    }
}
