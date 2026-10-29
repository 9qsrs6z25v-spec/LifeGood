import SwiftUI

// MARK: - 一件事的細節（judge §2.3；brief G3-3；§13-7）（手錶 v1，v25.574）
//
// 只屬於 LifeGoodWatch。① 今天點一列、今天全部點一列、錶面「下一場」、通知〔看議程〕推進來的第二層；純黑底、可以捲。
// 字全部是 WatchText.stopDetail 組好的（WatchStopDetail），這裡不讀部屬名字那一欄：
//   部屬會議（10:40 抬手）：「11:00–11:30・30 分鐘」「20 分後開始」「和 王小明」「議程 3 項」「・良率」「・人力」「・PM 排程」
//   手腕放下、沒解鎖、iPhone 沒送名字：「部屬會議」「議程 3 項」（議程三行不畫）
//   我的行事曆、系統行事曆：時間、狀態、地點、備註摘要（手腕放下「備註 1 則」）
// 錶面、通知、手腕放下都不寫部屬名字（§13-7）；名字只在這一頁抬手出現。
// 沒有任何按鈕（議程打勾、改時間都在 iPhone）。包裡找不到這一件（iPhone 改過、刪了）：「這一件在 iPhone 上改過了」。
// 「20 分後開始」每分鐘重畫。

struct StopDetailView: View {
    /// 場次 id（WatchRoute.stop(id)）
    let stopId: String

    @ObservedObject private var model = WatchModel.shared
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.redactionReasons) private var reasons

    static let missingText = "這一件在 iPhone 上改過了"
    static let missingTitle = "今天"
    /// 手腕放下時字調暗
    static let dimmedOpacity: Double = 0.75

    init(stopId: String) {
        self.stopId = stopId
    }

    private var privacy: WatchPrivacy {
        model.privacy(dimmed: dimmed, redacted: reasons.contains(.privacy))
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            page(now: context.date)
        }
        .containerBackground(Color.black, for: .navigation)
    }

    @ViewBuilder
    private func page(now: Date) -> some View {
        if let stop = WatchText.findStop(id: stopId, in: model.package) {
            WatchStopDetailBody(detail: WatchText.stopDetail(stop, now: now, hidesPersonal: privacy.hidesPersonal))
                .opacity(dimmed ? Self.dimmedOpacity : 1)
                .navigationTitle(WatchText.stopTitle(stop))
        } else {
            missing
                .navigationTitle(Self.missingTitle)
        }
    }

    private var missing: some View {
        Text(Self.missingText)
            .font(.body)
            .foregroundStyle(WatchStyle.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .scenePadding(.horizontal)
    }
}

// MARK: - 細節本體（可以捲）

private struct WatchStopDetailBody: View {
    let detail: WatchStopDetail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                timeRow
                statusRow
                iconRow(symbol: "person.fill", text: detail.who)
                iconRow(symbol: "mappin", text: detail.place)
                agendaBlock
                noteRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scenePadding(.horizontal)
        }
    }

    /// 「● 11:00–11:30・30 分鐘」（記號＝種類色）
    private var timeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: WatchText.markSymbol(detail.kind))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WatchStyle.kindColor(detail.kind))
                .frame(width: 12)
            Text(detail.timeLine)
                .font(.headline)
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// 「20 分後開始」「進行中・11:30 結束」「已經結束」；更遠不寫
    @ViewBuilder
    private var statusRow: some View {
        if let status = detail.status {
            Text(status)
                .font(.footnote)
                .foregroundStyle(WatchStyle.countdown)
                .lineLimit(1)
        }
    }

    /// 「和 王小明」／「部屬會議」（person.fill）、地點（mappin）；nil 不畫
    @ViewBuilder
    private func iconRow(symbol: String, text: String?) -> some View {
        if let text {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WatchStyle.small)
                    .frame(width: 14)
                Text(text)
                    .font(.body)
                    .foregroundStyle(WatchStyle.primary)
                    .lineLimit(2)
            }
        }
    }

    /// 「議程 3 項」＋一項一行「・良率」（一行放不下截尾）；手腕放下只剩「議程 3 項」
    @ViewBuilder
    private var agendaBlock: some View {
        if let title = detail.agendaTitle {
            Text(title)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .padding(.top, 2)
        }
        ForEach(Array(detail.agendaItems.enumerated()), id: \.offset) { pair in
            Text(agendaLine(pair.element))
                .font(.body)
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func agendaLine(_ item: String) -> String {
        "・" + item
    }

    /// 備註摘要（我的行事曆、系統行事曆）；手腕放下「備註 1 則」
    @ViewBuilder
    private var noteRow: some View {
        if let note = detail.note {
            Text(note)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(4)
                .padding(.top, 2)
        }
    }
}
