import SwiftUI
import WatchKit

// MARK: - ④ 旅行（手錶 v6，v25.578；watch/judge.md §2.14、§2.17、§2.18；watch/build/v6/brief.md G3-1）
//
// 只屬於 LifeGoodWatch。旅途中排第一頁（④①②）、出發前 7 天排最後（①②④）；放不放、排第幾看 WatchModel.tripKind（RootView）。
// 字全部是 WatchTripText.page 組好的（WatchTripPage）；這裡只排版。手腕放下換哪個字（過夜那一站「住宿」）由
// WatchTripText 依 privacy.hidesPersonal 換好，View 不拼「第 3／5 站」、不算時間。
//   旅途中（11/7 13:35）：左上「⋯」／換時區那一行（只有第一頁才畫）／✈︎ 韓國三日遊・第 2 天／下一站・25 分後・第 3／5 站／
//     大字 14:00／弘大／☁︎ 18°／11° 短暫陣雨 40%／ Weather ›／進度條（飛機在第 2、3 站中間）／〔✓ 到了〕／打卡那一行
//   按了〔到了〕：現在・第 3／5 站／大字 弘大／✓ 14:12 到了／下一站 17:30 明洞／天氣／ Weather ›／進度條／〔離開〕／正在送到 iPhone…
//   出發前 7 天：✈︎ 韓國三日遊／11/6（五）08:40 出發／大字 還有 7 天／行李 8／15（沒有按鈕、沒有進度條）
//   包裡沒有今天那一份：琥珀「打開 iPhone 上的 LifeGood 一次，才有今天的站」＋〔再試一次〕
// 點大字那一塊（大字＋下一行）→ 這一站（WatchRoute.tripStop）；「 Weather ›」→ 天氣資料出處（WatchRoute.weatherSource）。
// **天氣一定緊接著出處**（WeatherKit 規定，judge §2.14、評論 🔴3）：TripWeatherLines 一起畫，沒有天氣字連出處都不畫（這一站也用它）。
// 〔到了〕〔離開〕一律經 TripCheckIns.shared（時間＝按下去那一刻）。按下去 1.5 秒內按鈕暫時不能按：〔到了〕會原地換成〔離開〕，
// 連點兩下不會變成「到了又馬上離開」。〔離開〕之後焦點換到下一站，剛離開那一站的打卡那一行再留 5 分鐘。
// 這一頁不捲（judge §2.14：〔到了〕〔離開〕這一頁不捲，不包捲動容器）。41mm 換時區那一行或打卡那一行有字時不畫進度條（brief G3-1）；
// 還是放不下（字放大、40mm）一層一層收（ViewThatFits）：進度條 → 下一站那一行 → 天氣＋出處一起收（這一站頁看得到），
// 按鈕永遠留在畫面上。按鈕高 41mm 40、46mm 44。字一行接一行不另外留空（樣稿①-6；行距留了 41mm 就擠掉天氣）。
// 手腕放下：背景純黑、字調暗（0.75）、按鈕變暗暫時不能按（不拿掉、版面不跳）；站名、時間、天氣、出處照顯示。

struct TripPage: View {
    @ObservedObject private var model = WatchModel.shared
    @ObservedObject private var checkIns = TripCheckIns.shared
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.redactionReasons) private var reasons

    /// 剛按過的〔到了〕〔離開〕（哪一站、幾點）：冷卻計時、〔離開〕之後那一行還留著
    @State private var lastPress: TripPagePress?
    /// 按下去之後的 1.5 秒：按鈕暫時不能按
    @State private var coolingDown = false

    static let settingsLabel = "設定"
    /// 手腕放下時字調暗
    static let dimmedOpacity: Double = 0.75
    /// 按下去之後多久才能再按
    static let cooldownNanos: UInt64 = 1_500_000_000
    /// 〔離開〕之後（焦點換到下一站）剛離開那一站的打卡那一行留多久
    static let pressLineSeconds: TimeInterval = 5 * 60
    /// 底部主鈕高（41mm／46mm）
    static let compactButtonHeight: CGFloat = 40
    static let regularButtonHeight: CGFloat = 44
    /// 站名、不是時間的大字（Title2：46mm 30、41mm 28，U4 §5.2）
    static let regularNameSize: CGFloat = 30
    static let compactNameSize: CGFloat = 28
    /// 旅遊紫 BF5AF2
    static let tripColor = Color(watchHex: WatchPalette.trip)

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
        .task(id: lastPress) {
            await endCooldownLater()
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

    private var compact: Bool {
        WatchStyle.isCompact
    }

    private var buttonHeight: CGFloat {
        compact ? Self.compactButtonHeight : Self.regularButtonHeight
    }

    // MARK: 這一刻要畫什麼

    private func tripPage(now: Date) -> WatchTripPage? {
        WatchTripText.page(package: model.package, now: now, pending: checkIns.items,
                           dimmed: privacy.hidesPersonal, compact: compact)
    }

    /// 換時區那一行：只有 ④ 是第一頁（旅途中）才畫；出發前 ④ 排最後，那一行由 ① 今天畫
    private func timeZoneHint(now: Date) -> String? {
        guard model.firstPage == .trip else { return nil }
        return WatchTripText.timeZoneHint(package: model.package, now: now)
    }

    /// 打卡那一行：現在這一站（焦點）的；沒有就剛按過的那一站（5 分鐘內；〔離開〕之後焦點已經換到下一站）
    private func statusLine(_ page: WatchTripPage, now: Date) -> String? {
        if let id = page.focusStopId, let line = checkIns.line(for: id) {
            return line
        }
        guard let last = lastPress, last.stopId != page.focusStopId,
              now.timeIntervalSince(last.at) < Self.pressLineSeconds else { return nil }
        return checkIns.line(for: last.stopId)
    }

    /// 41mm：換時區那一行或打卡那一行有字時不畫進度條（brief G3-1 版面預算）
    private func hidesBar(timeZoneHint: String?, status: String?) -> Bool {
        compact && (timeZoneHint != nil || status != nil)
    }

    // MARK: 內容

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let page = tripPage(now: now) {
            fitted(page, timeZoneHint: timeZoneHint(now: now), status: statusLine(page, now: now))
        } else {
            missing
        }
    }

    /// 放得下照整頁（第一個）；放不下一層一層收（這一頁不捲，不包捲動容器）。字只算一次，四個版本畫同一份
    private func fitted(_ page: WatchTripPage, timeZoneHint: String?, status: String?) -> some View {
        ViewThatFits(in: .vertical) {
            layout(page, timeZoneHint: timeZoneHint, status: status, level: 0)
            layout(page, timeZoneHint: timeZoneHint, status: status, level: 1)
            layout(page, timeZoneHint: timeZoneHint, status: status, level: 2)
            layout(page, timeZoneHint: timeZoneHint, status: status, level: 3)
        }
    }

    /// level 0：整頁；1：不畫進度條；2：再收下一站那一行；3：再收天氣＋出處（一起收）、換時區與打卡那一行各一行。
    /// 上半（字）＋撐開＋下半（進度條貼著按鈕上緣、按鈕、打卡那一行）。
    /// 字一行接一行、中間不另外留空（judge §2.14 的 y 座標＝每行字高，41mm 約 212 才在 215 內；樣稿①-6）
    private func layout(_ page: WatchTripPage, timeZoneHint: String?, status: String?, level: Int) -> some View {
        let showsBar: Bool = level == 0 && !hidesBar(timeZoneHint: timeZoneHint, status: status)
        return VStack(alignment: .leading, spacing: 0) {
            topBlock(page, timeZoneHint: timeZoneHint, level: level)
            Spacer(minLength: 0)
            bottomBlock(page, status: status, showsBar: showsBar, tight: level >= 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scenePadding(.horizontal)
        .opacity(dimmed ? Self.dimmedOpacity : 1)
    }

    /// 換時區／頁首／第二行／〔再試一次〕／大字那一塊／下一站那一行／天氣＋出處
    private func topBlock(_ page: WatchTripPage, timeZoneHint: String?, level: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            timeZoneRow(timeZoneHint, tight: level >= 3)
            headerRow(page)
            line2Row(page)
            retryRow(page)
            bigBlock(page)
            line5Row(page, shown: level < 2)
            weatherRow(page, shown: level < 3)
        }
    }

    /// 進度條／〔到了〕〔離開〕／打卡那一行
    private func bottomBlock(_ page: WatchTripPage, status: String?, showsBar: Bool, tight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            progressRow(page, shown: showsBar)
            actionRow(page)
            statusRow(status, tight: tight)
        }
    }

    /// 不會發生（沒有這一頁時 RootView 不放）：照包太舊那一句
    private var missing: some View {
        Text(WatchTripText.staleText)
            .font(.footnote)
            .foregroundStyle(WatchStyle.amber)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .scenePadding(.horizontal)
            .opacity(dimmed ? Self.dimmedOpacity : 1)
    }

    // MARK: 換時區、頁首、第二行

    /// 「換時區了：打開 iPhone 上的 LifeGood 一次，日期才會對」（琥珀、兩行；最緊的時候一行）
    @ViewBuilder
    private func timeZoneRow(_ hint: String?, tight: Bool) -> some View {
        if let hint {
            Text(hint)
                .font(.footnote)
                .foregroundStyle(WatchStyle.amber)
                .lineLimit(tight ? 1 : 2)
                .minimumScaleFactor(0.8)
        }
    }

    /// 「✈︎ 韓國三日遊・第 2 天」（✈︎ 旅遊紫）
    private func headerRow(_ page: WatchTripPage) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "airplane")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Self.tripColor)
            Text(page.header)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchStyle.dateText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// 「下一站・25 分後・第 3／5 站」「現在・第 3／5 站」「11/6（五）08:40 出發」；包太舊那一句琥珀、最多三行
    private func line2Row(_ page: WatchTripPage) -> some View {
        Text(page.line2)
            .font(.footnote)
            .foregroundStyle(page.line2IsAmber ? WatchStyle.amber : WatchStyle.small)
            .lineLimit(page.line2IsAmber ? 3 : 1)
            .minimumScaleFactor(0.8)
    }

    /// 包裡沒有今天那一份：〔再試一次〕（跟 iPhone 要一份）
    @ViewBuilder
    private func retryRow(_ page: WatchTripPage) -> some View {
        if page.mode == .stale {
            WatchRetryButton(asking: model.asking, failed: model.askFailed, dimmed: dimmed) {
                model.requestFromPhone()
            }
        }
    }

    // MARK: 大字那一塊（點了 → 這一站）

    /// 大字＋下一行；有焦點那一站時整塊可以點。包太舊時不畫（大字只有「—」，留位置給那一句和〔再試一次〕）
    @ViewBuilder
    private func bigBlock(_ page: WatchTripPage) -> some View {
        if page.mode != .stale {
            if let id = page.focusStopId {
                Button {
                    model.path = [.tripStop(id)]
                } label: {
                    bigLabel(page)
                }
                .buttonStyle(.plain)
                .disabled(dimmed)
            } else {
                bigLabel(page)
            }
        }
    }

    private func bigLabel(_ page: WatchTripPage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(page.big)
                .font(bigFont(page))
                .foregroundStyle(WatchStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            line4View(page)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 時間「14:00」＝② 錢那種大字（46mm 38、41mm 34 heavy rounded、數字等寬）；站名、「還有 7 天」＝Title2 semibold
    private func bigFont(_ page: WatchTripPage) -> Font {
        if page.bigIsTime {
            return WatchStyle.heroFont(compact: compact).monospacedDigit()
        }
        return nameFont
    }

    private var nameFont: Font {
        .system(size: compact ? Self.compactNameSize : Self.regularNameSize, weight: .semibold)
    }

    /// 大字下面：下一站的站名（Title2）／「✓ 14:12 到了」（綠）／出發前「行李 8／15」（小字）
    @ViewBuilder
    private func line4View(_ page: WatchTripPage) -> some View {
        if let line4 = page.line4 {
            if page.bigIsTime {
                Text(line4)
                    .font(nameFont)
                    .foregroundStyle(WatchStyle.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else if page.line4IsArrived {
                TripArrivedLine(text: line4)
            } else {
                Text(line4)
                    .font(.footnote)
                    .foregroundStyle(WatchStyle.small)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// 「下一站 17:30 明洞」「明天 09:30 南山塔」（一行截尾）
    @ViewBuilder
    private func line5Row(_ page: WatchTripPage, shown: Bool) -> some View {
        if shown, let line5 = page.line5 {
            Text(line5)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: 天氣＋出處、進度條

    /// 天氣一行＋緊接著「 Weather ›」（TripWeatherLines；沒有天氣字整塊不畫）
    @ViewBuilder
    private func weatherRow(_ page: WatchTripPage, shown: Bool) -> some View {
        if shown {
            TripWeatherLines(text: page.weatherText, symbol: page.weatherSymbol, tips: [],
                             showsSource: page.showsSource, oneLine: true, dimmed: dimmed)
        }
    }

    @ViewBuilder
    private func progressRow(_ page: WatchTripPage, shown: Bool) -> some View {
        if shown, let plane = page.plane, !page.dots.isEmpty {
            TripProgressBar(dots: page.dots, plane: plane)
        }
    }

    // MARK: 〔到了〕〔離開〕

    @ViewBuilder
    private func actionRow(_ page: WatchTripPage) -> some View {
        if let action = page.action {
            switch action {
            case .arrive:
                arriveButton(page)
            case .depart:
                departButton(page)
            }
        }
    }

    /// 〔✓ 到了〕旅遊紫實心
    private func arriveButton(_ page: WatchTripPage) -> some View {
        Button {
            press(page, action: .arrive)
        } label: {
            Label(WatchTripText.arriveTitle, systemImage: "checkmark")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(arriveTint)
        .frame(height: buttonHeight)
        .disabled(dimmed || coolingDown)
    }

    /// 〔離開〕灰底
    private func departButton(_ page: WatchTripPage) -> some View {
        Button {
            press(page, action: .depart)
        } label: {
            Label(WatchTripText.departTitle, systemImage: "figure.walk")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .frame(height: buttonHeight)
        .disabled(dimmed || coolingDown)
    }

    /// 抬手旅遊紫；手腕放下暗下來（不留一大塊亮紫，同 ② 錢〔＋ 記一筆〕）
    private var arriveTint: Color {
        dimmed ? WatchStyle.small.opacity(0.25) : Self.tripColor
    }

    /// 「正在送到 iPhone…」「已寫進 iPhone 的行程」「還沒送到 iPhone，先存在手錶上」…（TripCheckIns 組好的）
    @ViewBuilder
    private func statusRow(_ status: String?, tight: Bool) -> some View {
        if let status {
            Text(status)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(tight ? 1 : 2)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: 按

    /// 時間＝按下去那一刻；〔離開〕帶手錶上看到的到達（iPhone 那邊沒有到達時補上）
    private func press(_ page: WatchTripPage, action: WatchTripPage.Action) {
        guard !coolingDown, !dimmed, let planId = page.planId, let stopId = page.focusStopId else { return }
        let now = Date()
        switch action {
        case .arrive:
            checkIns.arrive(planId: planId, stopId: stopId, now: now)
        case .depart:
            checkIns.depart(planId: planId, stopId: stopId, arrivedAt: page.focusArrivedAt, now: now)
        }
        coolingDown = true
        lastPress = TripPagePress(stopId: stopId, at: now)
        WKInterfaceDevice.current().play(.success)
    }

    /// 按下去 1.5 秒後按鈕恢復（.task(id: lastPress)：又按了一次就重新數；頁面翻走再翻回來也會收尾）
    private func endCooldownLater() async {
        guard coolingDown else { return }
        try? await Task.sleep(nanoseconds: Self.cooldownNanos)
        guard !Task.isCancelled else { return }
        coolingDown = false
    }
}

/// 剛按過的那一下
private struct TripPagePress: Equatable {
    var stopId: UUID
    var at: Date
}

// MARK: - 「✓ 14:12 到了」（綠；④ 旅行大字下面、這一站的狀態那一行）

struct TripArrivedLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(WatchStyle.green)
    }
}

// MARK: - 天氣＋緊接著「 Weather ›」（④ 旅行、這一站共用；judge §2.14、評論 🔴3）

/// 天氣字（圖示＋「18°／11° 短暫陣雨 40%」）、天氣兩句（這一站才有）、**緊接著**「 Weather ›」（點了 → 天氣資料出處）。
/// 沒有天氣字、或沒有出處（showsSource false）整塊不畫：天氣不准沒有出處單獨出現（WeatherKit 規定）。
/// 手腕放下照顯示（出處那一行不能省）；能點的那一行變暗、暫時不能按
struct TripWeatherLines: View {
    let text: String?
    let symbol: String?
    /// 天氣兩句（這一站才有；④ 那一頁傳 []）
    let tips: [String]
    let showsSource: Bool
    /// ④ 那一頁一行截尾「☁︎ 18°／11° 短暫陣…」；這一站最多兩行
    let oneLine: Bool
    let dimmed: Bool

    static let defaultSymbol = "cloud"

    var body: some View {
        if let text, showsSource {
            VStack(alignment: .leading, spacing: 1) {
                weatherLine(text)
                tipLines
                sourceLink
            }
        }
    }

    private func weatherLine(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol ?? Self.defaultSymbol)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.footnote)
                .lineLimit(oneLine ? 1 : 2)
                .truncationMode(.tail)
        }
        .foregroundStyle(WatchStyle.primary)
    }

    /// 「有 40% 的機會下雨，摺傘放包裡」一句一行（可以折行）
    @ViewBuilder
    private var tipLines: some View {
        ForEach(Array(tips.enumerated()), id: \.offset) { pair in
            Text(pair.element)
                .font(.footnote)
                .foregroundStyle(WatchStyle.small)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 「 Weather ›」（Caption2 灰）→ 天氣資料出處（WatchRoute.weatherSource）
    private var sourceLink: some View {
        NavigationLink(value: WatchRoute.weatherSource) {
            Text(sourceText)
                .font(.caption2)
                .foregroundStyle(WatchStyle.small)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
    }

    private var sourceText: String {
        WatchTripText.sourceLabel + " ›"
    }
}

// MARK: - 進度條（每一站一個點＋飛機；不寫字）

/// 軌道 3 點高（白 20%）、走過的那段旅遊紫、每一站一個 6 點圓（走過的紫、還沒到的白 40%）、飛機 12 點放在 plane 的位置；
/// 兩端各留半架飛機的寬，點與飛機都不會被切掉
private struct TripProgressBar: View {
    let dots: [Double]
    /// 0…1
    let plane: Double

    static let height: CGFloat = 12
    static let trackHeight: CGFloat = 3
    static let dotSize: CGFloat = 6
    static let planeSize: CGFloat = 12
    static let tint: Color = Color(watchHex: WatchPalette.trip)
    static let track: Color = Color.white.opacity(0.2)
    static let idle: Color = Color.white.opacity(0.4)

    var body: some View {
        GeometryReader { geo in
            bar(width: geo.size.width)
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat) -> some View {
        let inset: CGFloat = Self.planeSize / 2
        let usable: CGFloat = max(width - inset * 2, 0)
        return ZStack(alignment: .leading) {
            trackView(usable: usable, inset: inset)
            ForEach(Array(dots.enumerated()), id: \.offset) { pair in
                dotView(pair.element, usable: usable, inset: inset)
            }
            planeView(usable: usable, inset: inset)
        }
        .frame(width: width, height: Self.height, alignment: .leading)
    }

    /// 軌道＋走過的那段（0…plane）
    private func trackView(usable: CGFloat, inset: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Self.track)
                .frame(width: usable, height: Self.trackHeight)
            Capsule()
                .fill(Self.tint)
                .frame(width: usable * fraction(plane), height: Self.trackHeight)
        }
        .offset(x: inset)
    }

    private func dotView(_ position: Double, usable: CGFloat, inset: CGFloat) -> some View {
        Circle()
            .fill(position <= plane ? Self.tint : Self.idle)
            .frame(width: Self.dotSize, height: Self.dotSize)
            .offset(x: inset + usable * fraction(position) - Self.dotSize / 2)
    }

    private func planeView(usable: CGFloat, inset: CGFloat) -> some View {
        Image(systemName: "airplane")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(WatchStyle.primary)
            .frame(width: Self.planeSize, height: Self.planeSize)
            .offset(x: inset + usable * fraction(plane) - Self.planeSize / 2)
    }

    /// 夾在 0…1（不是有限數＝0）
    private func fraction(_ value: Double) -> CGFloat {
        guard value.isFinite else { return 0 }
        return CGFloat(min(max(value, 0), 1))
    }
}
