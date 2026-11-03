import SwiftUI

// MARK: - 今天記的帳（手錶 v2，v25.576；watch/judge.md §2.7、§2.17；watch/build/v2/brief.md G4-2）
//
// 只屬於 LifeGoodWatch。② 錢「今天 N 筆 ›」推進來（WatchRoute.todayRecords）；系統清單、純黑底。
// 字全部是 RecordText.todayList 組好的（RecordTodayList）：
//   段頭「今天 …・3 筆」（遮住「今天 3 筆」）
//   每列：圖示圓＋「午餐」／「12:10・…180 ⌚︎」（遮住時金額換成遮住的寫法；名稱、時間照顯示，judge §2.17）
//   iPhone 帳本裡今天的（包的 todayRecords：只有名稱、金額字、時間、圖示、是不是手錶記的——不帶備註、照片、同行者、付款卡）
//   ＋手錶待送盒裡今天記、還不在那一份裡的（第三行灰字「等著送」「在 iPhone 等著入帳」「在 iPhone 上被刪掉了」，整列淡一點）；新到舊
//   一列都沒有：「今天還沒記帳」；最下面「要改、要刪，請到 iPhone」
// **只看**：點一列不做事（不包 NavigationLink、不加按鈕；手錶不改、不刪已入帳的帳，judge §4.5）。
// 圖示圓的顏色：包裡同一個圖示的分類（找不到看範本）的顏色，只是配色；找不到用淡灰。
// 手腕放下：版面不動、字調暗，金額 RecordText 已經換成遮住的寫法。

struct TodayRecordsView: View {
    @ObservedObject private var model = WatchModel.shared
    @ObservedObject private var outbox = RecordOutbox.shared
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.redactionReasons) private var reasons

    static let title = "今天記的帳"
    /// 手腕放下時字調暗
    static let dimmedOpacity: Double = 0.75

    private var privacy: WatchPrivacy {
        model.privacy(dimmed: dimmed, redacted: reasons.contains(.privacy))
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            list(now: context.date)
        }
        .navigationTitle(Self.title)
        .containerBackground(Color.black, for: .navigation)
        .onAppear {
            outbox.reload()
        }
    }

    private func list(now: Date) -> some View {
        let today = RecordText.todayList(package: model.package, items: outbox.items, now: now,
                                         calendar: Calendar.current, masked: privacy.masksAmounts)
        return List {
            recordsSection(today)
        }
        .opacity(dimmed ? Self.dimmedOpacity : 1)
    }

    // MARK: 段

    private func recordsSection(_ t: RecordTodayList) -> some View {
        Section {
            rows(t)
        } header: {
            header(t)
        } footer: {
            footer
        }
    }

    @ViewBuilder
    private func rows(_ t: RecordTodayList) -> some View {
        if let empty = t.empty {
            Text(empty)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
        } else {
            ForEach(t.rows) { row in
                TodayRecordRowView(row: row, tint: tint(for: row))
            }
        }
    }

    /// 「今天 …・3 筆」（遮住「今天 3 筆」）；包裡沒有錢的快照時沒有段頭
    @ViewBuilder
    private func header(_ t: RecordTodayList) -> some View {
        if let text = t.header {
            Text(text)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// 「要改、要刪，請到 iPhone」
    private var footer: some View {
        Text(RecordText.todayFooter)
            .font(.footnote)
            .foregroundStyle(WatchStyle.small)
    }

    // MARK: 配色

    /// 包裡同一個圖示的分類（找不到看範本）的顏色；都找不到用淡灰
    private func tint(for row: RecordTodayRow) -> Color {
        let money = model.package?.money
        if let c = money?.categories?.first(where: { $0.icon == row.icon }) {
            return Color(watchHex: c.tint)
        }
        if let t = money?.templates?.first(where: { $0.icon == row.icon }) {
            return Color(watchHex: t.tint)
        }
        return Color.white.opacity(0.2)
    }
}

// MARK: - 一列（圖示圓＋「午餐」／「12:10・…180 ⌚︎」／待送盒的灰字；不能點）

private struct TodayRecordRowView: View {
    let row: RecordTodayRow
    let tint: Color

    /// 圖示圓直徑
    static let iconSize: CGFloat = 28
    /// 還在待送盒的那幾列整列淡一點
    static let pendingOpacity: Double = 0.6
    static let fromWatchLabel = "手錶記的"

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            iconCircle
            texts
            Spacer(minLength: 0)
        }
        .opacity(row.pendingNote == nil ? 1 : Self.pendingOpacity)
        .accessibilityElement(children: .combine)
    }

    private var iconCircle: some View {
        Image(systemName: row.icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: Self.iconSize, height: Self.iconSize)
            .background(Circle().fill(tint))
            .padding(.top, 2)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(row.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
            detailLine
            pendingLine
        }
    }

    /// 「12:10・…180」（RecordText.rowDetail 組好）＋手錶記的 ⌚︎
    private var detailLine: some View {
        HStack(spacing: 4) {
            Text(row.detail)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            watchMark
        }
    }

    @ViewBuilder
    private var watchMark: some View {
        if row.fromWatch {
            Image(systemName: "applewatch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WatchStyle.small)
                .accessibilityLabel(Text(Self.fromWatchLabel))
        }
    }

    /// 「等著送」「在 iPhone 等著入帳」「在 iPhone 上被刪掉了」
    @ViewBuilder
    private var pendingLine: some View {
        if let note = row.pendingNote {
            Text(note)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
