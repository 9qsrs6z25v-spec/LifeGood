import SwiftUI

// MARK: - 接下來要繳（judge §2.5；brief G3-5；§13-8）（手錶 v1，v25.574）
//
// 只屬於 LifeGoodWatch。② 錢「💳 … ›」、① 今天要留意的卡費推進來的第二層；系統清單、純黑底。
// 字全部是 WatchText.bills 組好的（WatchBillList，30 天內、最多 5 列）：
//   「10/27（二）卡費」／「5 天後・要自己繳」（財富那幾列 iPhone 送之前就只剩類別字、沒有卡名、沒有金額）
//   「11/5（四）苗栗的家 房貸」／金額・14 天後（遮住時金額換成遮住的寫法，WatchText 換好）
// 先列 3 列，超過 3 列多一顆〔再看 N 筆 ›〕展開到 5 列。
// 每一列都**不能點**、**沒有「標成已繳」**（judge §4.5、§13-8：手錶不做標成已繳）。
// 30 天內沒有要繳的：「30 天內沒有要繳的」。最下面資料多舊（FreshnessFooter，錢那一套）。

struct BillsList: View {
    @ObservedObject private var model = WatchModel.shared
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.redactionReasons) private var reasons
    /// 〔再看 N 筆〕按過了沒（展開到 5 列）
    @State private var showAll = false

    static let title = "接下來要繳"
    static let emptyText = "30 天內沒有要繳的"
    /// 一開始先列幾列
    static let firstRows = 3
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
    }

    private func list(now: Date) -> some View {
        let bills = WatchText.bills(package: model.package, now: now,
                                    masked: privacy.masksAmounts, compact: WatchStyle.isCompact)
        let freshness = WatchText.moneyFreshness(package: model.package, now: now)
        return List {
            rowsSection(bills)
            footerSection(freshness)
        }
        .opacity(dimmed ? Self.dimmedOpacity : 1)
    }

    // MARK: 列

    @ViewBuilder
    private func rowsSection(_ bills: WatchBillList) -> some View {
        Section {
            if bills.rows.isEmpty {
                Text(Self.emptyText)
                    .font(.footnote)
                    .foregroundStyle(WatchStyle.small)
            } else {
                ForEach(shownRows(bills)) { row in
                    WatchBillRowView(row: row)
                }
                if hiddenCount(bills) > 0 {
                    Button {
                        showAll = true
                    } label: {
                        moreLabel(hiddenCount(bills))
                    }
                    .disabled(dimmed)
                }
            }
        }
    }

    /// 還沒展開：前 3 列；展開：全部（WatchText 已經裁到 5 列）
    private func shownRows(_ bills: WatchBillList) -> [WatchBillRow] {
        showAll ? bills.rows : Array(bills.rows.prefix(Self.firstRows))
    }

    /// 〔再看 N 筆〕的 N（＝min(總共, 5) − 3）；展開了是 0
    private func hiddenCount(_ bills: WatchBillList) -> Int {
        showAll ? 0 : max(0, bills.rows.count - Self.firstRows)
    }

    private func moreLabel(_ count: Int) -> some View {
        HStack(spacing: 4) {
            Text(moreTitle(count))
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WatchStyle.small)
        }
    }

    private func moreTitle(_ count: Int) -> String {
        "再看 \(count) 筆"
    }

    // MARK: 資料多舊

    @ViewBuilder
    private func footerSection(_ freshness: WatchFreshness?) -> some View {
        if freshness != nil {
            Section {
                FreshnessFooter(freshness: freshness)
                    .listRowBackground(Color.clear)
            }
        }
    }
}

// MARK: - 一列（圖示＋「10/27（二）卡費」／「5 天後・要自己繳」；不能點）

private struct WatchBillRowView: View {
    let row: WatchBillRow

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: row.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WatchStyle.small)
                .frame(width: 16)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.body)
                    .foregroundStyle(WatchStyle.primary)
                    .lineLimit(1)
                Text(row.detail)
                    .font(.footnote)
                    .foregroundStyle(WatchStyle.small)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}
