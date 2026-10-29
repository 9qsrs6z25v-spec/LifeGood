import SwiftUI

// MARK: - ③ 跑步（手錶 v4，v25.580；watch/judge.md §2.9、§2.17、§2.18；watch/build/v4/brief.md G3-1）
//
// 只屬於 LifeGoodWatch。**骨架（主控寫）：名字 RunHomePage() 不准改（RootView 在叫）；G3 填內容。**
// 垂直翻頁的 ③（② 錢之後、出發前那一頁 ④ 之前；旅途中 ④ 照樣排第一）。字全部是 WatchRunText.home 組好的
// （iPhone 包裡的 runWeek＋手錶自己記、seen 裡沒有的那幾趟；View 不加減公里、不拼字）。
//   抬手（46mm，05:50）：「🏃 這週第 4 天・連續 6 週」／「這週跑了」／大字「9.4 公里」／「2 次・目標 20 公里」／
//     「還差 10.6 公里・剩 4 天」（達標綠 5BD99A）／小風景條（河堤 7 段，有動那天插旗、今天下面一個小點；不放字）／
//     〔▶ 開始跑步〕（底部主鈕綠 1F9D57；寫上一次用的運動：上次騎車就是「開始騎車」）
//   41mm（WatchStyle.isCompact）：大字 34、不畫風景條、兩句併一行「2 次・還差 10.6 公里」（judge §2.18）
//   從來沒收過 iPhone 的資料：大字「—」＋「打開 iPhone 上的 LifeGood，就看得到這週的公里」，按鈕照樣能按
//   存不進 Apple 健康的那一趟還在手錶上（WorkoutManager.unsaved）：琥珀一行「有 1 趟還沒存進 Apple 健康 ›」→ 那一趟的摘要
//     〔再存一次〕。這一行出現時版面預算不夠：「這週跑了」那一行與風景條收起來（大字、公里、次數照寫）
//   手腕放下（§2.17）：背景純黑、字 0.75、風景條換 1.5 點 40% 白線＋旗子外框；公里、次數、天數照顯示（§6.1 可以上鎖定畫面）；
//     按鈕暫時不能按、綠色暗下來（不拿掉，版面不跳）
// 不加 ScrollView（轉錶冠翻頁）、不加 toolbar（設定在 ①）。
// [手錶 v5] v25.582（watch/build/v5/brief.md G3-3）：點看板（頁首到小風景條那一塊）推「這週」（WatchModel.openRunWeek → RunWeekView）；
//   同一組 View 只是包一層 .plain 的 Button（版面不變高）；手腕放下暫時不能按。琥珀那一行、〔▶ 開始跑步〕照舊在外面各自能按。
// 跑完回到這一頁：RootView 從跑步那一頁換回來時整頁重畫，WatchRunLog 多的那一趟馬上算進去（不用等下一分鐘）。

struct RunHomePage: View {
    @ObservedObject private var model = WatchModel.shared
    @ObservedObject private var runs = WorkoutManager.shared
    @Environment(\.isLuminanceReduced) private var dimmed

    /// 手腕放下時字調暗
    static let dimmedOpacity: Double = 0.75
    /// 底部主鈕的圖示
    static let startIcon = "play.fill"

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .containerBackground(for: .tabView) {
            pageBackground
        }
    }

    // MARK: 外框

    @ViewBuilder
    private var pageBackground: some View {
        if dimmed {
            Color.black
        } else {
            WatchStyle.sky
        }
    }

    // MARK: 內容

    private func content(now: Date) -> some View {
        let home = WatchRunText.home(package: model.package, own: WatchRunLog.all(), now: now,
                                     lastSport: WatchRunPrefs.lastSport)
        let compact = WatchStyle.isCompact
        // 有沒存成的那一趟：多一行琥珀，收起「這週跑了」與風景條（46mm 約 250 點放不下 240）
        let reduced = runs.unsaved != nil
        return VStack(alignment: .leading, spacing: 2) {
            board(home, compact: compact, reduced: reduced)
            unsavedRow
            Spacer(minLength: 4)
            startButton(home)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scenePadding(.horizontal)
        .opacity(dimmed ? Self.dimmedOpacity : 1)
    }

    /// [v5] 看板（頁首、這週跑了、大字、那兩句、小風景條）：點了推「這週」（judge §2.9「看板 → 這週」）。
    /// 跟 v4 同一組 View、同樣的間距，只是包一層 .plain 的 Button（版面不變高）；手腕放下暫時不能按（不拿掉）
    private func board(_ home: WatchRunHome, compact: Bool, reduced: Bool) -> some View {
        Button {
            model.openRunWeek()
        } label: {
            boardContent(home, compact: compact, reduced: reduced)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
    }

    private func boardContent(_ home: WatchRunHome, compact: Bool, reduced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            RunHomeHeader(home: home)
            if !reduced {
                verbText(home)
            }
            RunHomeBig(home: home, compact: compact)
            RunHomeLines(home: home, compact: compact)
            if !compact && !reduced {
                RunWeekStrip(flags: home.flags, todayIndex: home.todayIndex, sport: home.sport, dimmed: dimmed)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 「這週跑了」「這週騎了」
    private func verbText(_ home: WatchRunHome) -> some View {
        Text(home.verbLine)
            .font(.footnote)
            .foregroundStyle(WatchStyle.small)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// 「⚠︎ 有 1 趟還沒存進 Apple 健康 ›」→ 那一趟的摘要（saved＝false，〔再存一次〕）；沒有就不畫
    @ViewBuilder
    private var unsavedRow: some View {
        if runs.unsaved != nil {
            Button {
                runs.showUnsaved()
            } label: {
                RunUnsavedLabel()
            }
            .buttonStyle(.plain)
            .disabled(dimmed)
        }
    }

    /// 〔▶ 開始跑步〕（上一次用的運動；沒有＝這週主角）→ 準備頁
    private func startButton(_ home: WatchRunHome) -> some View {
        Button {
            runs.openPrep(sport: home.startSport)
        } label: {
            Label(home.startSport.startTitle, systemImage: Self.startIcon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(startTint)
        .disabled(dimmed)
    }

    /// 抬手綠 1F9D57；手腕放下暗下來（不留一大塊亮綠，同 ② 錢〔＋ 記一筆〕）、暫時不能按，版面不動
    private var startTint: Color {
        dimmed ? WatchStyle.small.opacity(0.25) : WatchStyle.go
    }
}

// MARK: - 頁首「🏃 這週第 4 天・連續 6 週」

private struct RunHomeHeader: View {
    let home: WatchRunHome

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: home.sport.icon)
                .foregroundStyle(WatchStyle.sport(home.sport))
            Text(home.header)
                .foregroundStyle(WatchStyle.dateText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.footnote.weight(.semibold))
    }
}

// MARK: - 大字「9.4 公里」（從來沒收過「—」、不寫公里）

private struct RunHomeBig: View {
    let home: WatchRunHome
    let compact: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(home.big)
                .font(WatchStyle.heroFont(compact: compact))
                .monospacedDigit()
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if home.showsUnit {
                Text(WatchRunText.kmUnit)
                    .font(.footnote)
                    .foregroundStyle(WatchStyle.primary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - 大字下面的一句（46mm 兩行、41mm 併一行）

private struct RunHomeLines: View {
    let home: WatchRunHome
    let compact: Bool

    /// 從來沒收過時那一句很長（「打開 iPhone 上的 LifeGood，就看得到這週的公里」）：46mm 兩行、41mm 三行
    private var sentenceLines: Int {
        compact ? 3 : 2
    }

    var body: some View {
        if compact {
            compactText
        } else {
            VStack(alignment: .leading, spacing: 2) {
                line3Text
                line4Text
            }
        }
    }

    /// 41mm「2 次・還差 10.6 公里」
    @ViewBuilder
    private var compactText: some View {
        if let line = home.compactLine {
            Text(line)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(home.showsUnit ? 1 : sentenceLines)
                .minimumScaleFactor(0.8)
        }
    }

    /// 「2 次・目標 20 公里」
    @ViewBuilder
    private var line3Text: some View {
        if let line = home.line3 {
            Text(line)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(home.showsUnit ? 1 : sentenceLines)
                .minimumScaleFactor(0.8)
        }
    }

    /// 「還差 10.6 公里・剩 4 天」；達標「已達標・多 0.6 公里」綠
    @ViewBuilder
    private var line4Text: some View {
        if let line = home.line4 {
            Text(line)
                .font(.footnote)
                .foregroundStyle(home.line4IsGreen ? WatchStyle.saved : WatchStyle.small)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - 「⚠︎ 有 1 趟還沒存進 Apple 健康 ›」

private struct RunUnsavedLabel: View {
    static let icon = "exclamationmark.triangle.fill"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: Self.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(WatchRunText.unsavedRow)
                .font(.footnote)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 2)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(WatchStyle.amber)
        .contentShape(Rectangle())
    }
}

// MARK: - 小風景條（46mm 才畫；高 32：河堤 7 段，有動那天插旗、今天下面一個小點；不放字）

private struct RunWeekStrip: View {
    let flags: [Bool]
    let todayIndex: Int
    let sport: WatchSport
    let dimmed: Bool

    static let height: CGFloat = 32
    static let days = 7
    /// 地平線的高度（上面插旗、下面今天的小點）
    static let lineY: CGFloat = 21
    static let flagSize: CGFloat = 10
    static let flagLift: CGFloat = 9
    static let dotSize: CGFloat = 3
    static let dotDrop: CGFloat = 6
    /// 每一段之間留的縫
    static let gap: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            strip(width: geo.size.width)
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }

    private func strip(width: CGFloat) -> some View {
        let seg: CGFloat = max(width, 0) / CGFloat(Self.days)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<Self.days, id: \.self) { i in
                daySegment(i, seg: seg)
            }
        }
        .frame(width: max(width, 0), height: Self.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func daySegment(_ i: Int, seg: CGFloat) -> some View {
        Capsule()
            .fill(lineColor)
            .frame(width: max(seg - Self.gap, 1), height: lineWidth)
            .position(x: midX(i, seg: seg), y: Self.lineY)
        if hasFlag(i) {
            Image(systemName: dimmed ? "flag" : "flag.fill")
                .font(.system(size: Self.flagSize, weight: .semibold))
                .foregroundStyle(WatchStyle.sport(sport))
                .position(x: midX(i, seg: seg), y: Self.lineY - Self.flagLift)
        }
        if i == todayIndex {
            Circle()
                .fill(WatchStyle.primary)
                .frame(width: Self.dotSize, height: Self.dotSize)
                .position(x: midX(i, seg: seg), y: Self.lineY + Self.dotDrop)
        }
    }

    private func midX(_ i: Int, seg: CGFloat) -> CGFloat {
        seg * (CGFloat(i) + 0.5)
    }

    private func hasFlag(_ i: Int) -> Bool {
        i >= 0 && i < flags.count && flags[i]
    }

    /// 抬手 2 點；手腕放下 1.5 點（judge §2.9「線 ≥2 點」、§2.17「風景條變 1.5 點 40% 外框線」）
    private var lineWidth: CGFloat {
        dimmed ? 1.5 : 2
    }

    private var lineColor: Color {
        dimmed ? Color.white.opacity(0.4) : WatchStyle.small.opacity(0.6)
    }
}
