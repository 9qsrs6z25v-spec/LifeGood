import SwiftUI
import Charts

// MARK: - 運動的項目卡、卡面路線、每週公里卡（v25.553，健康 v3；health/judge.md §5.1、§3.6）
//
// 跟記帳、理財、車子同一張卡（MoneyItemCard）、同一組圖表卡（MoneyChartCard）：這個檔只決定「一趟要寫什麼字、卡面畫什麼」，
// 長相全是共用零件（使用者說過「質感差很多，這個好亂」：不另做一套）。
//
// • MoneyItem.workout(_:bodyWeightKg:)：一趟 → 項目卡要寫的字。數字一律讀 WorkoutFacts／WorkoutFormat（不寫第二套）：
//   名稱 WorkoutFacts.title（App 記的「跑步」顯示成「晨跑」）、大數字一位小數「5.2 公里」（重訓「2,160 kg」或「45 分鐘」）、
//   分類列「● 跑步・32:10」、膠囊依序：路線沒存到 → 配速 6'11"（騎車時速 21.5）→ 爬升 18 m／平路 → 約 340 大卡 → 手錶；
//   一列放不下 MoneyItemCard 自己從後面少放。卡面左上「10/15 06:05」、左下手寫 Run／MORNING（週末騎車 WEEKEND）。
//   id 一定是那一趟的 id（健康頁、全部紀錄靠它對回去）。VoiceOver 唸一整句（accessibilityText）。
// • WorkoutRoutePanel：卡面（左 108pt）畫這一趟路線的形狀——淡米色紙底＋很淡的格線（深色深藍底，同 K 線卡面）、
//   白邊＋運動色 3pt 線、暫停斷開、起點白圈（深藍細邊）、終點實心運動色點＋白邊；照 shape.aspect 等比例放進
//   切線左邊、左上膠囊下面、左下手寫字上面那一塊。Canvas、Equatable：不打任何地圖請求（清單每筆一張 Map 會卡，U1 D2）。
//   compact＝緊湊模式 46pt 小方塊（只畫線）。深淺色用 dark 參數傳進來（Equatable 的 View 不放 @Environment）。
// • WorkoutWeeklyCard：⑤ 每週公里（MoneyChartCard，主題 workoutTrends「Trends／WEEKLY」）：膠囊選運動（＋全部）、
//   一週一根（全部時依運動疊起來，由下往上跑、走、騎、登山）、這週那根淡一點、單一運動有目標畫「目標 20」虛線、
//   按住一根看那週「10/5–10/11・跑 13.3 公里（3 趟）」（沒按時寫這週）、圖例 12 週合計＋近 4 週平均。

// MARK: - 項目卡

extension MoneyItem {
    /// 一趟運動的項目卡（不 async、不綁 actor：HealthPageData.build、全部紀錄都在主執行緒呼叫）
    static func workout(_ s: WorkoutSession, bodyWeightKg: Double?) -> MoneyItem {
        let sport = s.primarySport
        let text = WorkoutItemText.make(s, sport: sport, bodyWeightKg: bodyWeightKg)
        var item = MoneyItem(id: s.id,
                             theme: MoneyArtTheme.of(sport),
                             seed: MoneyItem.seed(s.id),
                             title: WorkoutFacts.title(s),
                             amount: text.amount,
                             unit: text.unit,
                             category: sport.displayName)
        item.detail = text.detail
        item.badge = WorkoutFormat.monthDay(s.date) + " " + WorkoutFormat.time(s.date)
        item.chips = text.chips
        item.scriptCaps = WorkoutFacts.scriptCaps(s)
        item.route = s.firstRouteExercise.flatMap { WorkoutFacts.routeShape($0.route) }
        item.accessibilityText = text.spoken
        return item
    }
}

/// 一張運動卡的字（MoneyItem.workout 用）。純值；數字全讀 WorkoutFacts／WorkoutFormat
private struct WorkoutItemText {
    var amount = ""
    var unit: String? = nil
    var detail: String? = nil
    var chips: [MoneyItemChip] = []
    /// VoiceOver 一整句
    var spoken = ""

    static func make(_ s: WorkoutSession, sport: WorkoutSport, bodyWeightKg: Double?) -> WorkoutItemText {
        var t = WorkoutItemText()
        var said: [String] = [spokenWhen(s.date), WorkoutFacts.title(s)]
        if sport == .strength {
            fillStrength(&t, said: &said, s: s, bodyWeightKg: bodyWeightKg)
        } else {
            fillCardio(&t, said: &said, s: s, sport: sport, bodyWeightKg: bodyWeightKg)
        }
        t.spoken = said.joined(separator: "，")
        return t
    }

    // MARK: 有氧

    private static func fillCardio(_ t: inout WorkoutItemText, said: inout [String], s: WorkoutSession,
                                   sport: WorkoutSport, bodyWeightKg: Double?) {
        let km = s.totalDistanceKm
        let hasKm = km.isFinite && km >= 0.05
        let moving = WorkoutFacts.movingMinutes(s)
        let hasTime = moving.isFinite && moving > 0
        // 大數字：有距離「5.2 公里」；沒距離寫時間「38:40」（分類列就不再重複寫時間）
        if hasKm {
            t.amount = WorkoutFormat.kmNumber(km)
            t.unit = "公里"
            t.detail = hasTime ? WorkoutFormat.clock(minutes: moving) : nil
            said.append(sport.displayName + " " + WorkoutFormat.km(km))
        } else {
            t.amount = hasTime ? WorkoutFormat.clock(minutes: moving) : "—"
            said.append(sport.displayName)
        }
        if hasTime { said.append(spokenClock(minutes: moving)) }
        // 膠囊 1：舊版沒存到路線（灰的，第一顆）
        if s.isLegacyRouteMissing {
            t.chips.append(MoneyItemChip(icon: "map", text: "路線沒存到"))
            said.append("路線沒存到")
        }
        // 膠囊 2：配速（跑、走、登山）／時速（騎車）；其他有氧不寫
        if hasKm, hasTime {
            if sport == .bike {
                if let v = WorkoutFormat.speedKmh(km: km, minutes: moving) {
                    t.chips.append(MoneyItemChip(icon: "speedometer", text: "時速 " + WorkoutFormat.speedNumber(v)))
                    said.append("時速 " + WorkoutFormat.speedNumber(v) + " 公里")
                }
            } else if sport != .other {
                let pace = WorkoutFormat.pace(km: km, minutes: moving)
                if pace != "—" {
                    t.chips.append(MoneyItemChip(icon: "speedometer", text: "配速 " + pace))
                    if let p = spokenPace(km: km, minutes: moving) { said.append("配速每公里 " + p) }
                }
            }
        }
        // 膠囊 3：爬升（知道才寫：App 記、有路線的；不到 10 公尺寫「平路」）
        if let e = s.firstRouteExercise, let m = WorkoutFacts.climb(e, in: s) {
            let text = m >= 10 ? "爬升 " + WorkoutFormat.climb(m) : "平路"
            t.chips.append(MoneyItemChip(icon: "mountain.2.fill", text: text))
            said.append(m >= 10 ? "爬升 \(WorkoutFormat.wholeSeconds(m)) 公尺" : "平路")
        }
        // 膠囊 4：大卡（估的「約 340 大卡」、手錶量的「402 大卡」）
        if let k = WorkoutFacts.kcal(s, bodyWeightKg: bodyWeightKg) {
            let text = WorkoutFormat.kcal(k.kcal, estimated: k.estimated)
            t.chips.append(MoneyItemChip(icon: "flame.fill", text: text))
            said.append(text)
        }
        // 膠囊 5：手錶記的（最後一顆）
        if WorkoutFacts.source(of: s) == .watch {
            t.chips.append(MoneyItemChip(icon: "applewatch", text: "手錶"))
            said.append("Apple Watch 記的")
        }
    }

    // MARK: 重訓

    private static func fillStrength(_ t: inout WorkoutItemText, said: inout [String], s: WorkoutSession,
                                     bodyWeightKg: Double?) {
        let moving = WorkoutFacts.movingMinutes(s)
        let hasTime = moving.isFinite && moving >= 0.5
        let rawVolume = s.totalVolume(bodyWeightKg: bodyWeightKg) ?? 0
        let volume = rawVolume.isFinite ? rawVolume : 0
        let fromWatch = WorkoutFacts.source(of: s) == .watch
        var amountIsTime = false
        // 大數字：有訓練量「2,160 kg」；沒有寫時間「45 分鐘」
        if volume >= 0.5 {
            t.amount = Int(min(volume, 1_000_000_000).rounded()).formatted()
            t.unit = "kg"
            said.append("重訓 訓練量 " + t.amount + " 公斤")
        } else if hasTime {
            t.amount = "\(WorkoutFormat.wholeSeconds(moving * 60 + 30) / 60)"
            t.unit = "分鐘"
            amountIsTime = true
            said.append("重訓 " + WorkoutFormat.total(minutes: moving))
        } else if s.totalSets > 0 {
            t.amount = "\(s.totalSets)"
            t.unit = "組"
            said.append("重訓 \(s.totalSets) 組")
        } else {
            t.amount = "—"
            said.append("重訓")
        }
        // 分類列：自己記的「3 組」；手錶帶進來沒有組數「Apple Watch」
        // （舊資料沒存來源、有 Apple 健康編號的才當手錶；手動補記、App 記的寫進 Apple 健康也有編號，不算）
        if s.totalSets > 0 {
            t.detail = "\(s.totalSets) 組"
            if t.unit != "組" { said.append("\(s.totalSets) 組") }
        } else if fromWatch || (WorkoutFacts.source(of: s) == nil && s.healthKitUUID != nil) {
            t.detail = "Apple Watch"
        }
        if s.totalReps > 0 {
            t.chips.append(MoneyItemChip(icon: "repeat", text: "共 \(s.totalReps) 下"))
            said.append("共 \(s.totalReps) 下")
        }
        if hasTime, !amountIsTime {
            let text = WorkoutFormat.total(minutes: moving)
            t.chips.append(MoneyItemChip(icon: "stopwatch", text: text))
            said.append(text)
        }
        // 大卡只放量到的（手錶）；自己記的重訓估的大卡不放（樣稿③-C3）
        if let k = WorkoutFacts.kcal(s, bodyWeightKg: bodyWeightKg), !k.estimated {
            let text = WorkoutFormat.kcal(k.kcal, estimated: false)
            t.chips.append(MoneyItemChip(icon: "flame.fill", text: text))
            said.append(text)
        }
        if fromWatch {
            t.chips.append(MoneyItemChip(icon: "applewatch", text: "手錶"))
            said.append("Apple Watch 記的")
        }
    }

    // MARK: 唸的字

    /// 「10 月 15 日早上 6 點 05 分」（時段照 WorkoutFacts.dayPart；整點不唸分）
    static func spokenWhen(_ d: Date) -> String {
        let cal = WorkoutFacts.calendar
        let c = cal.dateComponents([.month, .day, .hour, .minute], from: d)
        let hour = c.hour ?? 0
        let minute = c.minute ?? 0
        var h12 = hour % 12
        if h12 == 0 && hour == 12 { h12 = 12 }
        let minuteText = minute == 0 ? "" : String(format: " %02d 分", minute)
        let date = "\(c.month ?? 1) 月 \(c.day ?? 1) 日"
        return date + partWord(WorkoutFacts.dayPart(d)) + " \(h12) 點" + minuteText
    }

    private static func partWord(_ p: WorkoutFacts.DayPart) -> String {
        switch p {
        case .morning: return "早上"
        case .noon: return "中午"
        case .afternoon: return "下午"
        case .evening: return "晚上"
        case .night: return "凌晨"
        }
    }

    /// 「32 分 10 秒」「1 小時 5 分 12 秒」
    static func spokenClock(minutes: Double) -> String {
        let total = WorkoutFormat.wholeSeconds(minutes * 60)
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) 小時") }
        if m > 0 { parts.append("\(m) 分") }
        if sec > 0 || parts.isEmpty { parts.append("\(sec) 秒") }
        return parts.joined(separator: " ")
    }

    /// 「6 分 11 秒」（跟 WorkoutFormat.pace 一樣秒數四捨五入）；算不出來或超過 60 分/公里回 nil
    static func spokenPace(km: Double, minutes: Double) -> String? {
        guard km > 0, minutes > 0 else { return nil }
        let p = minutes / km
        guard p.isFinite, p > 0, p < 60 else { return nil }
        let total = WorkoutFormat.wholeSeconds(p * 60)
        let sec = total % 60
        return sec == 0 ? "\(total / 60) 分" : "\(total / 60) 分 \(sec) 秒"
    }
}

// MARK: - 卡面：路線形狀

/// 卡面：這一趟路線的形狀（Equatable＋.equatable()：輸入一樣不重畫）
struct WorkoutRoutePanel: View, Equatable {
    let shape: WorkoutRouteShape
    let theme: MoneyArtTheme
    /// 深色（MoneyPanel／MoneyThumb 傳 scheme == .dark；Equatable 的 View 不放 @Environment）
    var dark: Bool = false
    /// 緊湊模式 46pt 小方塊：只畫線，不留左上膠囊、左下手寫字的位置
    var compact: Bool = false

    var body: some View {
        Canvas { ctx, size in
            Self.paint(&ctx, size: size, art: self)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 主題 61～66 對回運動（線用 WorkoutPalette 的運動色）；對不到 nil
    static func sportOf(_ theme: MoneyArtTheme) -> WorkoutSport? {
        switch theme.id {
        case 61: return .run
        case 62: return .walk
        case 63: return .bike
        case 64: return .hike
        case 65: return .strength
        case 66: return .other
        default: return nil
        }
    }

    private static func paint(_ ctx: inout GraphicsContext, size: CGSize, art: WorkoutRoutePanel) {
        guard size.width > 8, size.height > 8 else { return }
        paintPaper(&ctx, size: size, dark: art.dark, step: art.compact ? 7 : 11)
        let area = drawArea(size, compact: art.compact)
        guard area.width > 4, area.height > 4, art.shape.points.count >= 2 else { return }
        let pts = place(art.shape, in: area)
        guard let first = pts.first, let last = pts.last else { return }
        let line = linePath(pts, breaks: art.shape.breaks)
        let color = sportOf(art.theme).map { WorkoutPalette.sport($0, dark: art.dark) } ?? art.theme.tintColor
        let width: CGFloat = art.compact ? 2.4 : 3
        // 線外一圈白邊（樣稿：淺色、深色都是白邊；深藍的 casing 是給深色地圖用的，畫在深藍紙上看不到）
        let casing: Color = art.dark ? Color.white.opacity(0.85) : Color.white
        ctx.stroke(line, with: .color(casing),
                   style: StrokeStyle(lineWidth: width + 2, lineCap: .round, lineJoin: .round))
        ctx.stroke(line, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        paintEnds(&ctx, start: first, end: last, color: color, compact: art.compact)
    }

    /// 紙：淺色米紙 F7F1E3→EFE6D2、深色深藍 1B2A52→0B1430（同 K 線卡面），上面很淡的方格
    private static func paintPaper(_ ctx: inout GraphicsContext, size: CGSize, dark: Bool, step: CGFloat) {
        let colors: [Color] = dark ? [Color(tb: 0x1B2A52), Color(tb: 0x0B1430)]
                                   : [Color(tb: 0xF7F1E3), Color(tb: 0xEFE6D2)]
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: colors), startPoint: .zero,
                                       endPoint: CGPoint(x: size.width, y: size.height)))
        var grid = Path()
        var x = step
        while x < size.width {
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        var y = step
        while y < size.height {
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
            y += step
        }
        let ink: Color = dark ? Color.white.opacity(0.06) : Color(tb: 0xB89F6E, 0.16)
        ctx.stroke(grid, with: .color(ink), lineWidth: 0.5)
    }

    /// 畫線的範圍：一般卡面 x 8…寬×0.84−10（S 形切線左邊）、y 24…高−34（左上留給日期膠囊、左下留給手寫字）；
    /// 小方塊四邊各留 7
    private static func drawArea(_ size: CGSize, compact: Bool) -> CGRect {
        if compact {
            return CGRect(x: 7, y: 7, width: size.width - 14, height: size.height - 14)
        }
        let right = size.width * 0.84 - 10
        return CGRect(x: 8, y: 24, width: right - 8, height: size.height - 24 - 34)
    }

    /// 照長寬比（寬÷高，0.25～4）等比例放進範圍、置中
    private static func place(_ shape: WorkoutRouteShape, in area: CGRect) -> [CGPoint] {
        let raw = shape.aspect.isFinite && shape.aspect > 0 ? shape.aspect : 1
        let a = CGFloat(min(4, max(0.25, raw)))
        var bw = area.width
        var bh = bw / a
        if bh > area.height {
            bh = area.height
            bw = bh * a
        }
        let x0 = area.midX - bw / 2
        let y0 = area.midY - bh / 2
        return shape.points.map { p in
            CGPoint(x: x0 + p.x * bw, y: y0 + p.y * bh)
        }
    }

    /// 一條線；breaks（暫停後新的一段從第幾點開始）處斷開不相連
    private static func linePath(_ pts: [CGPoint], breaks: [Int]) -> Path {
        let cuts = Set(breaks)
        var p = Path()
        for (i, q) in pts.enumerated() {
            if i == 0 || cuts.contains(i) {
                p.move(to: q)
            } else {
                p.addLine(to: q)
            }
        }
        return p
    }

    /// 起點白圈（深藍細邊）、終點實心運動色點＋白邊（終點畫在上面：繞一圈回到起點時兩個都看得到一點）
    private static func paintEnds(_ ctx: inout GraphicsContext, start: CGPoint, end: CGPoint,
                                  color: Color, compact: Bool) {
        let r: CGFloat = compact ? 2.6 : 3.4
        let s = CGRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: s), with: .color(Color.white))
        ctx.stroke(Path(ellipseIn: s), with: .color(Color(tb: 0x0B1B45)), lineWidth: compact ? 1.2 : 1.5)
        let halo = r + (compact ? 1.0 : 1.3)
        ctx.fill(Path(ellipseIn: CGRect(x: end.x - halo, y: end.y - halo, width: halo * 2, height: halo * 2)),
                 with: .color(Color.white))
        ctx.fill(Path(ellipseIn: CGRect(x: end.x - r, y: end.y - r, width: r * 2, height: r * 2)),
                 with: .color(color))
    }
}

// MARK: - ⑤ 每週公里

/// ⑤ 每週公里（近 12 週）。MoneyChartCard 自己帶 .padding(.horizontal)：外面不要再加
struct WorkoutWeeklyCard: View {
    let series: HealthWeeklySeries

    /// 選的運動；nil＝全部（只有一種運動時沒有「全部」）
    @State private var selected: WorkoutSport?
    /// 手指按住的那一週（軸上的字「10/5」；放開變回 nil）
    @State private var picked: String?
    @Environment(\.colorScheme) private var scheme

    init(series: HealthWeeklySeries) {
        self.series = series
        _selected = State(initialValue: series.initial)
    }

    var body: some View {
        MoneyChartCard(theme: .workoutTrends, title: "每週公里", trailing: "近 12 週",
                       content: AnyView(cardBody))
    }

    private var pal: TripBoardPalette { TripBoardPalette(scheme) }
    private var dark: Bool { scheme == .dark }

    /// 現在看哪一種：選的那種還有資料就照選的；選「全部」而且不只一種 → nil；其他退回一打開的那一種
    private var current: WorkoutSport? {
        if let s = selected, series.sports.contains(s) { return s }
        if selected == nil, series.sports.count > 1 { return nil }
        return series.sports.contains(series.initial) ? series.initial : series.sports.first
    }

    /// 畫哪幾種（全部＝有資料的跑、走、騎、登山，疊起來由下往上）
    private var shownSports: [WorkoutSport] {
        if let s = current { return [s] }
        return series.sports
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            chipRow
            readout
            WorkoutWeeklyChart(bars: bars, axisLabels: axisLabels, currentLabel: currentLabel,
                               goal: goalKm, yTop: yTop, ruleColor: pal.label,
                               summary: chartSummary, picked: $picked)
            legend
        }
        .padding(.horizontal, 16)
    }

    // MARK: 膠囊

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(series.sports) { s in
                    FinanceFilterChip(text: s.displayName, on: current == s, pal: pal) { choose(s) }
                }
                if series.sports.count > 1 {
                    FinanceFilterChip(text: "全部", on: current == nil, pal: pal) { choose(nil) }
                }
            }
        }
    }

    private func choose(_ s: WorkoutSport?) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selected = s
            picked = nil
        }
    }

    // MARK: 圖上方那一行

    private var readout: some View {
        Text(readoutText)
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(pal.label)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }

    /// 按住一根：「10/5–10/11・跑 13.3 公里（3 趟）」；沒按：「這週（到今天）・跑 14.6 公里（3 趟）」
    private var readoutText: String {
        let hit = picked.flatMap { p in series.weeks.first { $0.label == p } }
        guard let w = hit ?? series.weeks.last else { return "" }
        let head = w.isCurrent ? "這週（到今天）" : w.rangeLabel
        return head + "・" + weekSummary(w)
    }

    private func weekSummary(_ w: HealthWeeklySeries.Week) -> String {
        if let s = current {
            let km = w.km[s] ?? 0
            guard km >= 0.05 else { return "沒有" + s.displayName }
            let trips = w.trips[s] ?? 0
            return WorkoutFacts.verb(s) + " " + WorkoutFormat.kmNumber(km) + " 公里（\(trips) 趟）"
        }
        var parts: [String] = []
        for s in series.sports {
            let km = w.km[s] ?? 0
            if km >= 0.05 { parts.append(WorkoutFacts.verb(s) + " " + WorkoutFormat.kmNumber(km)) }
        }
        return parts.isEmpty ? "沒有運動" : parts.joined(separator: "・") + " 公里"
    }

    // MARK: 圖的資料（先排好，圖裡只畫）

    private var bars: [WorkoutWeeklyBar] {
        let sports = shownSports
        var out: [WorkoutWeeklyBar] = []
        out.reserveCapacity(series.weeks.count * sports.count)
        for w in series.weeks {
            // 沒有資料的週也放一根 0：字串軸才會留那一格（出差那週是空的，不是不見）
            for s in sports {
                out.append(WorkoutWeeklyBar(label: w.label, sport: s, km: w.km[s] ?? 0,
                                            color: WorkoutPalette.sport(s, dark: dark),
                                            isCurrent: w.isCurrent))
            }
        }
        return out
    }

    /// 軸上只標每 4 根一個（7/27、8/24、9/21）＋這週
    private var axisLabels: [String] {
        let ws = series.weeks
        var out: [String] = []
        for (i, w) in ws.enumerated() {
            let isLast = i == ws.count - 1
            if isLast || (i % 4 == 0 && i <= ws.count - 3) { out.append(w.label) }
        }
        return out
    }

    private var currentLabel: String? {
        series.weeks.last { $0.isCurrent }?.label
    }

    /// 只有單一運動、有設每週目標才畫虛線
    private var goalKm: Double? {
        guard let s = current else { return nil }
        return series.goalKm[s]
    }

    /// y 軸上限：最高那一週（全部時疊起來的總和）和目標取大的，上面留一點給「目標 20」
    private var yTop: Double {
        let sports = shownSports
        var top = 0.0
        for w in series.weeks {
            var sum = 0.0
            for s in sports { sum += w.km[s] ?? 0 }
            top = max(top, sum)
        }
        top = max(top, goalKm ?? 0, 1)
        return top * 1.18
    }

    /// 近 4 週平均：這週之前 4 週（這週還沒過完不算）
    private func recentAverage(_ s: WorkoutSport) -> Double? {
        let prior = series.weeks.filter { !$0.isCurrent }.suffix(4)
        guard !prior.isEmpty else { return nil }
        let sum = prior.reduce(0.0) { $0 + ($1.km[s] ?? 0) }
        return sum / Double(prior.count)
    }

    private var chartSummary: String {
        if let s = current {
            let thisWeek = series.weeks.last.map { $0.km[s] ?? 0 } ?? 0
            var parts = ["近 12 週每週" + s.displayName + "公里",
                         "這週到今天 " + WorkoutFormat.km(thisWeek),
                         "12 週合計 " + WorkoutFormat.km(series.total(s))]
            if let avg = recentAverage(s) { parts.append("近 4 週平均 " + WorkoutFormat.km(avg)) }
            if let g = goalKm { parts.append("每週目標 " + HealthPageData.goalKmText(g)) }
            return parts.joined(separator: "，")
        }
        var parts = ["近 12 週每週公里，依運動疊起來"]
        for s in series.sports {
            parts.append(s.displayName + "合計 " + WorkoutFormat.km(series.total(s)))
        }
        return parts.joined(separator: "，")
    }

    // MARK: 圖例

    @ViewBuilder
    private var legend: some View {
        if let s = current {
            HStack(alignment: .center, spacing: 12) {
                legendItem(s)
                if let avg = recentAverage(s) {
                    averageText(avg)
                }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    allLegend
                }
                VStack(alignment: .leading, spacing: 2) {
                    allLegend
                }
            }
        }
    }

    private var allLegend: some View {
        ForEach(series.sports) { s in
            legendItem(s)
        }
    }

    /// 「■ 跑步 154.9 公里」（不能點）
    private func legendItem(_ s: WorkoutSport) -> some View {
        let total = WorkoutFormat.kmNumber(series.total(s))
        return FinanceLegendButton(color: WorkoutPalette.sport(s, dark: dark), label: s.displayName,
                                   valueText: total + " 公里",
                                   accessibilityLabel: "近 12 週" + s.displayName + "合計 " + total + " 公里",
                                   hint: "", pal: pal, action: nil)
    }

    /// 灰字「近 4 週平均」＋粗體「14.8」
    private func averageText(_ avg: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("近 4 週平均")
                .foregroundStyle(pal.label)
            Text(WorkoutFormat.kmNumber(avg))
                .fontWeight(.heavy)
                .monospacedDigit()
                .foregroundStyle(pal.ink)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// 一週一種運動一根（全部時同一週的幾根疊起來）
private struct WorkoutWeeklyBar: Identifiable {
    let label: String
    let sport: WorkoutSport
    let km: Double
    let color: Color
    let isCurrent: Bool
    var id: String { label + "|" + sport.rawValue }
}

/// 每週公里的圖（Swift Charts，高 168）。整張圖一個 VoiceOver 元素，唸卡片組好的摘要
private struct WorkoutWeeklyChart: View {
    let bars: [WorkoutWeeklyBar]
    let axisLabels: [String]
    let currentLabel: String?
    let goal: Double?
    let yTop: Double
    let ruleColor: Color
    let summary: String
    @Binding var picked: String?

    var body: some View {
        plot
            .chartXSelection(value: $picked)
            .frame(height: 168)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
    }

    private var plot: some View {
        Chart {
            ForEach(bars) { b in
                bar(b)
            }
            if let goal {
                goalRule(goal)
            }
        }
        .chartYScale(domain: 0...yTop)
        .chartXAxis {
            AxisMarks(values: axisLabels) { value in
                AxisValueLabel {
                    if let s = value.as(String.self) {
                        Text(axisText(s))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel()
            }
        }
    }

    @ChartContentBuilder
    private func bar(_ b: WorkoutWeeklyBar) -> some ChartContent {
        BarMark(x: .value("週", b.label), y: .value("公里", b.km), width: .ratio(0.6))
            .foregroundStyle(b.color.opacity(barOpacity(b)))
            .cornerRadius(2)
    }

    private func goalRule(_ g: Double) -> some ChartContent {
        RuleMark(y: .value("目標", g))
            .foregroundStyle(ruleColor)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .annotation(position: .top, alignment: .leading, spacing: 2) {
                Text("目標 " + goalText(g))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ruleColor)
            }
    }

    /// 這週那根淡一點；按住一根時其他的再淡一點
    private func barOpacity(_ b: WorkoutWeeklyBar) -> Double {
        let base = b.isCurrent ? 0.45 : 1.0
        guard let p = picked else { return base }
        return p == b.label ? base : base * 0.4
    }

    private func axisText(_ label: String) -> String {
        label == currentLabel ? "這週" : label
    }

    /// 「20」；不是整數「12.5」
    private func goalText(_ g: Double) -> String {
        guard g.isFinite, g > 0 else { return "0" }
        if abs(g - g.rounded()) < 0.05 { return "\(Int(min(g, 100_000).rounded()))" }
        return WorkoutFormat.kmNumber(g)
    }
}
