import SwiftUI

// MARK: - 今天全部（judge §2.2；brief G3-2）（手錶 v1，v25.574）
//
// 只屬於 LifeGoodWatch。① 今天「還有 N 件 ›」、今天要留意的生日推進來的第二層；系統清單、純黑底。
// 字全部是 WatchText.dayList 組好的（WatchDayList）：
//   現在・接下來：每列「09:30 部門會議」／「5 分後・12F 大會議室・30 分鐘」；進行中那一列第二行用倒數的藍；點一列 → 那一件的細節
//   全天：「媽媽 62 歲生日」（手腕放下、沒解鎖「家人生日」）
//   明天：「明天 10/23 週五・3 件」／「08:30 早會 起」（不能點）
//   已經過了：收在最後〔已經過了（N）〕點了才展開（不用 DisclosureGroup，用 @State 自己收放）
//   最下面資料多舊（FreshnessFooter）
// 手腕放下：版面不動、字調暗、能按的變暗不拿掉。倒數字每分鐘重畫。

struct DayListView: View {
    @ObservedObject private var model = WatchModel.shared
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.redactionReasons) private var reasons
    /// 「已經過了（N）」展開了沒
    @State private var showPast = false

    static let title = "今天"
    static let nowHeader = "現在・接下來"
    static let allDayHeader = "全天"
    static let noPackageText = "還沒收到 iPhone 的資料"
    static let noDayText = "沒有今天的資料"
    static let noStopsText = "今天沒排行程"
    static let allDoneText = "今天的行程都結束了"
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
        let day = WatchText.dayList(package: model.package, now: now)
        let freshness = WatchText.lifeFreshness(package: model.package, now: now)
        return List {
            nowSection(day, now: now)
            allDaySection(day)
            tomorrowSection(day)
            pastSection(day)
            footerSection(freshness)
        }
        .opacity(dimmed ? Self.dimmedOpacity : 1)
    }

    // MARK: 現在・接下來

    @ViewBuilder
    private func nowSection(_ day: WatchDayList, now: Date) -> some View {
        Section {
            if day.rows.isEmpty {
                Text(emptyText(now: now))
                    .font(.footnote)
                    .foregroundStyle(WatchStyle.small)
            } else {
                ForEach(day.rows) { row in
                    stopLink(row)
                }
            }
        } header: {
            Text(Self.nowHeader)
        }
    }

    /// 「現在・接下來」是空的時候寫哪一句（沒資料、過期、今天沒排、都結束了）
    private func emptyText(now: Date) -> String {
        guard let life = model.package?.life else { return Self.noPackageText }
        guard let today = life.day(at: now) else { return Self.noDayText }
        return today.stops.isEmpty ? Self.noStopsText : Self.allDoneText
    }

    private func stopLink(_ row: WatchListRow) -> some View {
        NavigationLink(value: WatchRoute.stop(row.id)) {
            WatchDayListRow(row: row)
        }
        .disabled(dimmed)
    }

    // MARK: 全天

    @ViewBuilder
    private func allDaySection(_ day: WatchDayList) -> some View {
        if !day.allDay.isEmpty {
            Section {
                ForEach(day.allDay) { item in
                    allDayLine(item)
                }
            } header: {
                Text(Self.allDayHeader)
            }
        }
    }

    private func allDayLine(_ item: WatchAllDayRow) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WatchStyle.dateText)
                .frame(width: 16)
            Text(privacy.hidesPersonal ? item.lockText : item.text)
                .font(.body)
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(2)
        }
    }

    // MARK: 明天

    @ViewBuilder
    private func tomorrowSection(_ day: WatchDayList) -> some View {
        if let header = day.tomorrowHeader {
            Section {
                if let first = day.tomorrowFirst {
                    Text(first)
                        .font(.body)
                        .foregroundStyle(WatchStyle.primary)
                        .lineLimit(1)
                }
            } header: {
                Text(header)
            }
        }
    }

    // MARK: 已經過了（收在最後）

    @ViewBuilder
    private func pastSection(_ day: WatchDayList) -> some View {
        if !day.past.isEmpty {
            Section {
                Button {
                    showPast.toggle()
                } label: {
                    pastToggleLabel(count: day.past.count)
                }
                .disabled(dimmed)
                if showPast {
                    ForEach(day.past) { row in
                        stopLink(row)
                            .opacity(0.6)
                    }
                }
            }
        }
    }

    private func pastToggleLabel(count: Int) -> some View {
        HStack(spacing: 4) {
            Text(pastTitle(count))
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
            Spacer(minLength: 4)
            Image(systemName: showPast ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WatchStyle.small)
        }
    }

    private func pastTitle(_ count: Int) -> String {
        "已經過了（\(count)）"
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

// MARK: - 一列（記號＋「09:30 部門會議」／第二行）

private struct WatchDayListRow: View {
    let row: WatchListRow

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: WatchText.markSymbol(row.kind))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WatchStyle.kindColor(row.kind))
                .frame(width: 12)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WatchStyle.primary)
                    .lineLimit(1)
                Text(row.detail)
                    .font(.footnote)
                    .foregroundStyle(detailColor)
                    .lineLimit(2)
            }
        }
    }

    /// 進行中那一列第二行用倒數的藍
    private var detailColor: Color {
        row.isCurrent ? WatchStyle.countdown : WatchStyle.small
    }
}
