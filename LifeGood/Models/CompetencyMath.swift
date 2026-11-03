import Foundation

// MARK: - [v25.599 職能雷達 v1a-1] 職能雷達的數學與畫面要用的字（純函式，不碰 SwiftUI）
//（radar/judge.md §3.2 雷達怎麼畫、§3.3 範圍與換算、§3.7 一次評分、§3.8 目前／上一次／平均、§4.3、§4.5、§5、§13；
//  radar/build/v1a-1/sim_v1a-1.py 一個函式一個函式對照，函式名後面的 ↔ 是 sim 裡的名字）
//
// • 一律先換成比例 t＝(分數−最低)÷(最高−最低)；半徑＝R×(0.12＋0.88t)（最低分畫在小洞邊上，不會縮成一點）。
// • 原始分數永遠不改：範圍改了，畫圖、平均時才換算；顯示時整數寫整數，不是整數寫「≈」＋一位小數。
// • 沒評 ≠ 0 分 ≠ 不適用：沒評、不適用的軸不畫頂點、不算平均；有分數的軸少於 3 個只畫點。
// • 「上一次」＝這張卡最新那次評分日 D 之前、每一格最後一筆（時間點重建，灰線永遠完整）。
// • 四捨五入一律 .rounded()（遠離零的四捨五入；sim 用 decimal ROUND_HALF_UP）。
// • 日子一律「2026-10-30」字串；星期幾、差幾天用整數算（不靠時區）；只有「今天是哪一天」看這台的時區。
// • body 裡不寫長運算式：畫面要的字、座標、狀態全部在這裡算好（CompetencyChartModel、CompetencySummaryModel、CompetencyRatingSection）。
// • 字不用「他／她」。0–100 只給 v3 縱軸（〔職能〕分頁不顯示）。

// MARK: - 畫面要的資料（純 struct）

/// 雷達上的一個點（圓心為 (0,0)，y 向下）
struct RadarPoint: Equatable {
    var x: Double
    var y: Double
}

/// 有分數的那幾個頂點（index＝第幾軸）
struct RadarVertex: Equatable {
    let index: Int
    let x: Double
    let y: Double
}

/// 多邊形的一條邊（from／to 是 vertices 陣列的位置）；skipped＝中間跳過沒評的軸 → 畫虛線
struct RadarEdge: Equatable {
    let from: Int
    let to: Int
    let skipped: Bool
}

/// 一張卡用哪種畫法（judge §3.2 表）
enum CompetencyChartStyle: Equatable {
    /// 0 項
    case empty
    /// 1～2 項、13 項以上：橫條
    case bars
    /// 3～8 項：雷達、軸上寫完整名字
    case radar
    /// 9～12 項：雷達放全寬、軸上寫短名（沒填寫 ①～⑫）
    case radarShort
}

/// 一格「目前」或「上一次」的值
struct CompetencyCellValue: Equatable {
    /// 原始分數（不適用時 nil）
    let value: Int?
    let na: Bool
    /// 那一張的範圍
    let range: CompetencyRange
    let dayKey: String
    let sessionId: UUID
    /// 這一格最後改的時間（同一天兩張時比這個）
    let stamp: Date
    let comment: String?
    let levelName: String?

    /// 比例 t（不適用回 nil）
    var ratio: Double? {
        guard let v = value, !na else { return nil }
        return CompetencyMath.ratio(v, range)
    }
}

/// 一根軸的狀態
enum CompetencyAxisState: Equatable {
    case rated
    case unrated
    case na
}

/// 雷達一根軸＋下面橫條那一列
struct CompetencyAxisModel: Equatable, Identifiable {
    /// 項目 id
    let id: UUID
    /// 完整名字（橫條、VoiceOver 用）
    let name: String
    /// 軸上寫的字（完整名字、短名或 ①）
    let label: String
    let state: CompetencyAxisState
    /// 這次的比例（沒評、不適用 nil）
    let t: Double?
    /// 「4」「≈7.8」；沒評 nil
    let valueText: String?
    /// 換算過時「原 1–5 的 4」
    let originalText: String?
    /// 上一次的比例（沒有 nil）
    let previousT: Double?
    let previousText: String?
    /// 「↑2」「↓1」「↑（換算後）」；沒變或沒有上一次 nil
    let deltaText: String?
    /// 這次沒評、沿用以前的：「4/30」
    let carriedFrom: String?
    /// 項目已停用（已轉出的卡片才會出現）
    let archived: Bool
}

/// 格線一圈
struct CompetencyRing: Equatable {
    /// 比例 t（0＝小洞邊、1＝最外圈）
    let t: Double
    /// 淡一點畫（超過 6 級隔一圈）
    let faint: Bool
    /// 圈旁小字（≤ 11 級只有最外圈寫最高分；> 11 級四圈都寫換算後的分數）
    let label: String?
}

/// 一張雷達卡要的全部東西（CompetencyRadar.swift 只照這個畫）
struct CompetencyChartModel: Equatable, Identifiable {
    /// 組 id
    let id: UUID
    let isTrait: Bool
    /// 「Gas System」
    let title: String
    /// 「10/30 比 4/30」「12/15 比之前」「第一次評分」「還沒評過」
    let dateLine: String
    /// 「Gas System・10/30 比 4/30」
    let headline: String
    /// 「平均 4.3」；沒有分數 nil
    let averageText: String?
    let style: CompetencyChartStyle
    let axes: [CompetencyAxisModel]
    let rings: [CompetencyRing]
    let range: CompetencyRange
    /// 有分數的軸（不算不適用）
    let ratedCount: Int
    /// 有分數的軸 ≥ 3 才畫多邊形
    let drawsPolygon: Bool
    /// 有上一次可以疊
    let hasPrevious: Bool
    /// 圖例「━ 10/30」「┅ 4/30」「┅ 12/15 之前」
    let legendCurrent: String?
    let legendPrevious: String?
    /// 卡片角落小字：「項目少於 3 個，改用橫條」「評了 2 項，還畫不成雷達」「超過 12 項，改用橫條」
    let note: String?
    /// 「值班技能沿用 4/30」
    let carriedNote: String?
    /// 一句完整的 VoiceOver 說明
    let accessibilityText: String
    /// 這位這一組一格都沒評過
    let neverRated: Bool
    /// 平均（比例；摘要卡用）
    let averageRatio: Double?
    let previousAverageRatio: Double?
    /// 有評的格子（含不適用）／這一組幾格（摘要卡覆蓋率用）
    let filledCount: Int
    let axisCount: Int
    /// 這一組最新的評分日（D）
    let latestDay: String?
}

/// 摘要卡（judge §4.3①；不寫 0–100）
struct CompetencySummaryModel: Equatable {
    /// 「上次評分 10/30（3 天前）」；還沒評過「還沒評過」
    let lastLine: String
    /// 超過 6 個月：字變橘「該重評了」
    let stale: Bool
    /// 人格特質那一格（人格 0 項 → nil，整格不出現）
    let traitValueText: String?
    let traitDeltaText: String?
    /// 本職學能那一格（沒有要學的系統 → nil）
    let skillValueText: String?
    let skillDeltaText: String?
    /// 覆蓋不到一半：本職學能數字變灰、小字「只評了 1／9 格」
    let skillLowCoverage: Bool
    let skillCoverageText: String?
    /// 「12／12 格」
    let filledText: String
    /// 「本職 9／9」
    let skillFilledText: String?
}

/// 〔職能〕分頁整頁（SubordinateCompetencyTab.swift 只照這個排）
struct CompetencyTabModel: Equatable {
    let configured: Bool
    let readOnly: Bool
    let summary: CompetencySummaryModel
    let cards: [CompetencyChartModel]
    /// 不用學的系統名字（最下面一行「不用學：（無）〔改〕」）
    let skippedNames: [String]
    /// 這位一張都沒評過
    let neverRated: Bool
}

/// 評分畫面一格的草稿
struct CompetencyDraftCell: Equatable {
    /// nil＝沒評
    var value: Int?
    var na: Bool = false
    var comment: String?
    /// 照上次帶進來、還沒改（淡框）
    var carried: Bool = false

    var isSet: Bool { value != nil || na }
}

/// 評分畫面一格
struct CompetencyRatingAxis: Equatable, Identifiable {
    /// 項目 id
    let id: UUID
    let name: String
    /// 上一次（這張評分日之前、每一格最後一筆）
    let previous: CompetencyCellValue?
    /// 「上次 2（4/30）」「上次 ≈7.8（原 1–5 的 4）」「上次 不適用（4/30）」
    let previousText: String?
    /// 灰點畫在哪一顆按鈕下面（換算後最接近的那一級）
    let previousNearest: Int?
    /// 上一次跟這一張同一個範圍（才能照上次）
    let previousSameRange: Bool
    /// 這位這一格從來沒評過（新增的項目：標「新」）
    let isNew: Bool
}

/// 評分畫面一區（一組）
struct CompetencyRatingSection: Equatable, Identifiable {
    /// 組 id
    let id: UUID
    let title: String
    let isTrait: Bool
    /// 這一張用的範圍（打開評分時的；改舊紀錄用那一張自己的）
    let range: CompetencyRange
    let axes: [CompetencyRatingAxis]
    /// 〔這組照上次〕按得下去
    let canCarry: Bool
    /// 「範圍改過（1–5 → 1–10），這組要重新點」
    let carryBlockedNote: String?
}

/// 評分畫面底部那一行的數字
struct CompetencyFooterCounts: Equatable {
    let changed: Int
    let carried: Int
    let up: Int
    let down: Int
    let hasPrevious: Bool
}

// MARK: - 數學

enum CompetencyMath {
    /// 圓心小洞（12%）
    static let innerHole: Double = 0.12

    // MARK: 比例與換算（judge §3.3）

    /// ↔ ratio：t＝(v−low)÷(high−low)，夾在 0…1
    static func ratio(_ v: Int, _ range: CompetencyRange) -> Double {
        guard range.high > range.low else { return 0 }
        let t: Double = Double(v - range.low) / Double(range.high - range.low)
        return min(max(t, 0), 1)
    }

    /// ↔ from_ratio：比例 → 某個範圍的分數（可能是小數）
    static func value(atRatio t: Double, _ range: CompetencyRange) -> Double {
        Double(range.low) + t * Double(range.high - range.low)
    }

    /// ↔ conv：舊範圍的 v 換成新範圍（1–5 的 4 → 1–10 的 7.75）
    static func convert(_ v: Int, from: CompetencyRange, to: CompetencyRange) -> Double {
        value(atRatio: ratio(v, from), to)
    }

    /// ↔ rad：半徑比例 0.12＋0.88t
    static func radiusFraction(_ t: Double) -> Double {
        innerHole + (1 - innerHole) * t
    }

    /// ↔ rh：四捨五入（遠離零；62.5 → 63）
    static func roundHalfUp(_ x: Double) -> Int {
        Int(x.rounded())
    }

    /// ↔ r1：四捨五入到一位小數
    static func round1(_ x: Double) -> Double {
        (x * 10).rounded() / 10
    }

    /// ↔ one_decimal：「4.3」「4.0」「-0.2」（不靠 String(format:) 與地區設定）
    static func oneDecimalText(_ x: Double) -> String {
        let tenths: Int = Int((abs(x) * 10).rounded())
        let s = "\(tenths / 10).\(tenths % 10)"
        return (x < 0 && tenths != 0) ? "-" + s : s
    }

    /// ↔ is_whole
    static func isWhole(_ x: Double) -> Bool {
        abs(x - x.rounded()) < 1e-9
    }

    /// ↔ number_text：整數寫整數，不是整數寫「≈」＋一位小數（7.75 →「≈7.8」）
    static func numberText(_ x: Double) -> String {
        if isWhole(x) { return "\(Int(x.rounded()))" }
        return "≈" + oneDecimalText(x)
    }

    /// ↔ plain_number：格線旁小字（整數寫整數，不是整數寫一位小數、不加 ≈）
    static func plainNumberText(_ x: Double) -> String {
        if isWhole(x) { return "\(Int(x.rounded()))" }
        return oneDecimalText(x)
    }

    /// ↔ cell_text：一格在現在範圍下怎麼寫（同範圍「4」；不同範圍「≈7.8」）
    static func cellText(_ c: CompetencyCellValue, in range: CompetencyRange) -> String {
        if c.na { return "不適用" }
        guard let v = c.value else { return "未評" }
        if c.range == range { return "\(v)" }
        return numberText(convert(v, from: c.range, to: range))
    }

    /// ↔ original_text：換算過才有「原 1–5 的 4」
    static func originalText(_ c: CompetencyCellValue, in range: CompetencyRange) -> String? {
        guard let v = c.value, !c.na, c.range != range else { return nil }
        return "原 \(c.range.text) 的 \(v)"
    }

    /// ↔ nearest_level：換算後最接近的那一級（灰點放哪顆按鈕下面）
    static func nearestLevel(_ c: CompetencyCellValue, in range: CompetencyRange) -> Int? {
        guard let v = c.value, !c.na else { return nil }
        if c.range == range { return v }
        return range.clamp(roundHalfUp(convert(v, from: c.range, to: range)))
    }

    // MARK: 範圍：按鈕、滑桿、格線（§13）

    /// ↔ button_rows：high ≤ 10 用按鈕；≤ 6 級一排，7～11 級兩排（0–10 → 0…5／6…10）。high > 10 回空（用滑桿）
    static func buttonRows(_ range: CompetencyRange) -> [[Int]] {
        guard range.usesButtons else { return [] }
        let all: [Int] = Array(range.low...range.high)
        if all.count <= 6 { return [all] }
        let first: Int = (all.count + 1) / 2
        return [Array(all[0..<first]), Array(all[first..<all.count])]
    }

    /// ↔ slider_placeholder：滑桿還沒評時停在中間（淡色、不算評了）
    static func sliderPlaceholder(_ range: CompetencyRange) -> Int {
        range.low + (range.high - range.low) / 2
    }

    /// ↔ parse_input：數字欄打的字 → 分數（全形數字也認）；超出範圍夾回並回 clamped＝true；不是數字回 nil
    static func parseInput(_ text: String, _ range: CompetencyRange) -> (value: Int, clamped: Bool)? {
        let fullWidth: [Character: Character] = ["０": "0", "１": "1", "２": "2", "３": "3", "４": "4",
                                                 "５": "5", "６": "6", "７": "7", "８": "8", "９": "9", "－": "-"]
        var s = ""
        for ch in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            s.append(fullWidth[ch] ?? ch)
        }
        guard let v = Int(s) else { return nil }
        let c = range.clamp(v)
        return (c, c != v)
    }

    /// ↔ ring_list：格線。級數 ≤ 11：一級一圈（含小洞邊）、超過 6 級隔一圈淡、只有最外圈寫最高分；
    /// 級數 > 11：只畫 4 圈（25%、50%、75%、100%），四圈都寫換算後的分數（0–100：25／50／75／100）
    static func rings(_ range: CompetencyRange) -> [CompetencyRing] {
        let n: Int = range.levelCount
        if n > 11 {
            let ts: [Double] = [0.25, 0.5, 0.75, 1.0]
            return ts.map { t in
                CompetencyRing(t: t, faint: false, label: plainNumberText(value(atRatio: t, range)))
            }
        }
        var out: [CompetencyRing] = []
        for i in 0..<n {
            let t: Double = n > 1 ? Double(i) / Double(n - 1) : 1
            let last: Bool = i == n - 1
            let faint: Bool = n > 6 && !last && i % 2 == 1
            out.append(CompetencyRing(t: t, faint: faint, label: last ? "\(range.high)" : nil))
        }
        return out
    }

    /// ↔ range_change_text：改範圍時先跳的說明（例子用舊範圍中間那一分）
    static func rangeChangeText(from old: CompetencyRange, to new: CompetencyRange) -> String {
        let sample: Int = old.low + (old.high - old.low) / 2
        let shown: String = plainNumberText(convert(sample, from: old, to: new))
        return "以前評的分數不會改。畫圖時會換算：\(old.text) 的 \(sample) 分，在 \(new.text) 會畫成 \(shown)。"
    }

    /// ↔ two_level_warning：只有兩級時提醒
    static func twoLevelWarning(_ range: CompetencyRange) -> String? {
        range.levelCount == 2 ? "只有兩級時雷達看不出差別，建議至少 3 級。" : nil
    }

    // MARK: 雷達幾何（judge §3.2）

    /// ↔ angle：第 i 軸角度（第一軸正上方、順時針；螢幕座標 y 向下）
    static func angle(_ i: Int, _ n: Int) -> Double {
        -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(max(n, 1))
    }

    /// ↔ point：比例 t 在第 i 軸的位置
    static func point(t: Double, index i: Int, count n: Int, radius r: Double) -> RadarPoint {
        let a: Double = angle(i, n)
        let rr: Double = r * radiusFraction(t)
        return RadarPoint(x: rr * cos(a), y: rr * sin(a))
    }

    /// ↔ ring_point：格線那一圈在第 i 軸的位置
    static func ringPoint(t: Double, index i: Int, count n: Int, radius r: Double) -> RadarPoint {
        point(t: t, index: i, count: n, radius: r)
    }

    /// ↔ verts：有分數的軸才有頂點（沒評、不適用跳過）
    static func vertices(_ ts: [Double?], radius r: Double) -> [RadarVertex] {
        let n = ts.count
        var out: [RadarVertex] = []
        for (i, t) in ts.enumerated() {
            guard let t else { continue }
            let p = point(t: t, index: i, count: n, radius: r)
            out.append(RadarVertex(index: i, x: p.x, y: p.y))
        }
        return out
    }

    /// ↔ edges：頂點 ≥ 3 才有邊；中間跳過軸的那幾條 skipped＝true（畫虛線）
    static func edges(_ verts: [RadarVertex], count n: Int) -> [RadarEdge] {
        guard verts.count >= 3, n > 0 else { return [] }
        var out: [RadarEdge] = []
        for k in 0..<verts.count {
            let next: Int = (k + 1) % verts.count
            let gap: Int = ((verts[next].index - verts[k].index) % n + n) % n
            out.append(RadarEdge(from: k, to: next, skipped: gap != 1))
        }
        return out
    }

    /// ↔ radar_radius：卡片內寬 W（螢幕寬 − 外距 32 − 卡片內距 32）→ R＝min(⌊0.35W⌋, 140)
    static func radarRadius(cardWidth w: Double) -> Double {
        min((0.35 * w).rounded(.down), 140)
    }

    /// ↔ label_widths：每一軸標籤最大寬：正上正下（|cosθ| ≤ 0.1）＝0.6W；左右＝W/2 −(R＋8)|cosθ| − 4
    static func labelWidths(cardWidth w: Double, radius r: Double, count n: Int) -> [Double] {
        var out: [Double] = []
        for i in 0..<max(n, 0) {
            let c: Double = abs(cos(angle(i, n)))
            out.append(c <= 0.1 ? w * 0.6 : w / 2 - (r + 8) * c - 4)
        }
        return out
    }

    /// ↔ label_align：cosθ > 0.1 靠左（標籤往右長）＝1、< −0.1 靠右＝−1、其他置中＝0
    static func labelAlignment(_ i: Int, _ n: Int) -> Int {
        let c: Double = cos(angle(i, n))
        if c > 0.1 { return 1 }
        if c < -0.1 { return -1 }
        return 0
    }

    /// ↔ vertical_extent：頂點在圓心上面、下面各佔幾個 R（奇數軸照頂點上下置中：三角形 1／0.5、五邊形 1／0.81）
    static func verticalExtent(count n: Int) -> (up: Double, down: Double) {
        guard n >= 3 else { return (1, 1) }
        var up: Double = 0
        var down: Double = 0
        for i in 0..<n {
            let s: Double = sin(angle(i, n))
            up = max(up, -s)
            down = max(down, s)
        }
        return (up, down)
    }

    /// ↔ chart_style：0／1–2／3–8／9–12／13+（judge §3.2）
    static func chartStyle(axisCount n: Int) -> CompetencyChartStyle {
        if n <= 0 { return .empty }
        if n <= 2 { return .bars }
        if n <= 8 { return .radar }
        if n <= 12 { return .radarShort }
        return .bars
    }

    /// ①～⑫（9～12 項沒填短名時軸上寫這個）
    static let circledNumbers: [String] = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩", "⑪", "⑫"]

    /// ↔ axis_label
    static func axisLabel(_ item: CompetencyItem, index i: Int, style: CompetencyChartStyle) -> String {
        guard style == .radarShort else { return item.displayName }
        let s = (item.shortName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty { return s }
        return i < circledNumbers.count ? circledNumbers[i] : "\(i + 1)"
    }

    // MARK: 日子（字串；judge §7.1-9）

    /// 這台現在的「今天」（看這台的時區）
    static func dayKey(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        let y: Int = c.year ?? 0
        let m: Int = c.month ?? 0
        let dd: Int = c.day ?? 0
        let ms: String = m < 10 ? "0\(m)" : "\(m)"
        let ds: String = dd < 10 ? "0\(dd)" : "\(dd)"
        return "\(y)-\(ms)-\(ds)"
    }

    /// 「2026-10-30」→ (2026, 10, 30)
    static func parseDay(_ key: String) -> (y: Int, m: Int, d: Int)? {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              m >= 1, m <= 12, d >= 1, d <= 31 else { return nil }
        return (y, m, d)
    }

    /// ↔ day_number：1970-01-01 起第幾天（Howard Hinnant days_from_civil；整數算、不靠時區）
    static func dayNumber(_ key: String) -> Int? {
        guard let p = parseDay(key) else { return nil }
        let y: Int = p.m <= 2 ? p.y - 1 : p.y
        let era: Int = (y >= 0 ? y : y - 399) / 400
        let yoe: Int = y - era * 400
        let mp: Int = p.m > 2 ? p.m - 3 : p.m + 9
        let doy: Int = (153 * mp + 2) / 5 + p.d - 1
        let doe: Int = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// ↔ days_between：b − a 幾天
    static func daysBetween(_ a: String, _ b: String) -> Int? {
        guard let x = dayNumber(a), let y = dayNumber(b) else { return nil }
        return y - x
    }

    static let weekdayChars: [String] = ["一", "二", "三", "四", "五", "六", "日"]

    /// ↔ wd：星期幾（1970-01-01 是星期四）
    static func weekdayChar(_ key: String) -> String {
        guard let z = dayNumber(key) else { return "" }
        let i: Int = ((z + 3) % 7 + 7) % 7
        return weekdayChars[i]
    }

    /// ↔ short_day：「10/30」
    static func shortDay(_ key: String) -> String {
        guard let p = parseDay(key) else { return key }
        return "\(p.m)/\(p.d)"
    }

    /// ↔ day_text：「10/30（五）」
    static func dayText(_ key: String) -> String {
        guard parseDay(key) != nil else { return key }
        return shortDay(key) + "（" + weekdayChar(key) + "）"
    }

    /// ↔ long_day_text：「2026/10/30（五）」（評分畫面日期那一行）
    static func longDayText(_ key: String) -> String {
        guard let p = parseDay(key) else { return key }
        return "\(p.y)/\(p.m)/\(p.d)（" + weekdayChar(key) + "）"
    }

    /// ↔ add_months：加幾個月（31 號遇到小月夾到月底）
    static func addMonths(_ key: String, _ n: Int) -> String {
        guard let p = parseDay(key) else { return key }
        let total: Int = p.y * 12 + (p.m - 1) + n
        let y: Int = total / 12
        let m: Int = total % 12 + 1
        let leap: Bool = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        let lens: [Int] = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        let d: Int = min(p.d, lens[m - 1])
        let ms: String = m < 10 ? "0\(m)" : "\(m)"
        let ds: String = d < 10 ? "0\(d)" : "\(d)"
        return "\(y)-\(ms)-\(ds)"
    }

    /// ↔ is_stale：上次評分滿 6 個月（字變橘「該重評了」；只在 App 裡，不發通知）
    static func isStale(lastDay: String, today: String) -> Bool {
        today >= addMonths(lastDay, 6)
    }

    /// ↔ ago_text：「今天」「3 天前」「2 個月前」
    static func agoText(lastDay: String, today: String) -> String {
        guard let d = daysBetween(lastDay, today) else { return "" }
        if d <= 0 { return "今天" }
        if d < 31 { return "\(d) 天前" }
        var months = 0
        while today >= addMonths(lastDay, months + 1) { months += 1 }
        return "\(max(months, 1)) 個月前"
    }

    // MARK: 評分查表（judge §2.7、§3.8）

    /// ↔ cell_range：這一張某一組的範圍
    static func sessionRange(_ s: CompetencySession, groupId: UUID) -> CompetencyRange {
        s.range(forGroup: groupId)
    }

    /// ↔ cur_at：每一格最新的一筆（before 有值＝只看 dayKey < before 的）。我評的、整張沒墓碑、這一格沒被清掉；
    /// 新的日子勝；同一天比這一格的 updatedAt
    static func latestCells(_ sessions: [CompetencySession], before: String? = nil) -> [CompetencyCellKey: CompetencyCellValue] {
        var out: [CompetencyCellKey: CompetencyCellValue] = [:]
        for s in sessions where s.isLive && s.isByMe {
            if let b = before, !(s.dayKey < b) { continue }
            for sc in s.allScores where sc.isLive {
                let cell = CompetencyCellValue(value: sc.isNA ? nil : sc.value, na: sc.isNA,
                                               range: s.range(forGroup: sc.groupId), dayKey: s.dayKey,
                                               sessionId: s.id, stamp: sc.updatedAt ?? s.stamp,
                                               comment: sc.comment, levelName: sc.levelName)
                if let old = out[sc.key] {
                    if old.dayKey > cell.dayKey { continue }
                    if old.dayKey == cell.dayKey && old.stamp >= cell.stamp { continue }
                }
                out[sc.key] = cell
            }
        }
        return out
    }

    /// ↔ group_avg：這組有分數的格子先換 t 再平均（不適用、沒評不算）
    static func averageRatio(_ cells: [CompetencyCellValue?]) -> Double? {
        let ts: [Double] = cells.compactMap { $0?.ratio }
        guard !ts.isEmpty else { return nil }
        return ts.reduce(0, +) / Double(ts.count)
    }

    /// ↔ delta_text：一格比上一次（同範圍寫整數差「↑2」；不同範圍用 t 比「↑（換算後）」；沒變 nil）
    static func deltaText(current: CompetencyCellValue?, previous: CompetencyCellValue?) -> String? {
        guard let c = current, let p = previous, let tc = c.ratio, let tp = p.ratio else { return nil }
        if c.range == p.range, let a = c.value, let b = p.value {
            if a > b { return "↑\(a - b)" }
            if a < b { return "↓\(b - a)" }
            return nil
        }
        if tc > tp + 1e-9 { return "↑（換算後）" }
        if tc < tp - 1e-9 { return "↓（換算後）" }
        return nil
    }

    /// ↔ avg_delta_text：平均比上一次「↑0.3」「↓0.2」（四捨五入到一位後是 0 → nil）
    static func averageDeltaText(current: Double?, previous: Double?) -> String? {
        guard let c = current, let p = previous else { return nil }
        let d: Double = c - p
        let tenths: Int = Int((abs(d) * 10).rounded())
        if tenths == 0 { return nil }
        return (d > 0 ? "↑" : "↓") + oneDecimalText(abs(d))
    }

    // MARK: 一張卡（judge §3.2、§3.8、§4.3）

    /// ↔ card：axes＝這張卡的軸（照順序）；archivedIds＝其中已停用的項目（已轉出的卡片才會帶）
    static func chartModel(group: CompetencyGroup, axes: [CompetencyItem], archivedIds: Set<UUID>,
                           sessions: [CompetencySession], range: CompetencyRange) -> CompetencyChartModel {
        let gid: UUID = group.id
        let n: Int = axes.count
        let style: CompetencyChartStyle = chartStyle(axisCount: n)
        let now: [CompetencyCellKey: CompetencyCellValue] = latestCells(sessions)
        let curCells: [CompetencyCellValue?] = axes.map { now[CompetencyCellKey(groupId: gid, itemId: $0.id)] }
        let latest: String? = curCells.compactMap { $0?.dayKey }.max()
        var prevCells: [CompetencyCellValue?] = Array(repeating: nil, count: n)
        if let d = latest {
            let before = latestCells(sessions, before: d)
            prevCells = axes.map { before[CompetencyCellKey(groupId: gid, itemId: $0.id)] }
        }
        let prevDays: [String] = Array(Set(prevCells.compactMap { $0?.dayKey })).sorted()
        let hasPrev: Bool = !prevDays.isEmpty

        var axisModels: [CompetencyAxisModel] = []
        var carried: [String] = []
        for (i, item) in axes.enumerated() {
            let c: CompetencyCellValue? = curCells[i]
            let p: CompetencyCellValue? = prevCells[i]
            let state: CompetencyAxisState = c == nil ? .unrated : (c?.na == true ? .na : .rated)
            var carriedFrom: String? = nil
            if let c, let d = latest, c.dayKey < d {
                carriedFrom = shortDay(c.dayKey)
                carried.append(item.displayName + "沿用 " + shortDay(c.dayKey))
            }
            let label: String = axisLabel(item, index: i, style: style)
            let vText: String? = c.map { cellText($0, in: range) }
            let oText: String? = c.flatMap { originalText($0, in: range) }
            let pText: String? = p.map { cellText($0, in: range) }
            let dText: String? = deltaText(current: c, previous: p)
            let isArchived: Bool = archivedIds.contains(item.id)
            let model = CompetencyAxisModel(id: item.id, name: item.displayName, label: label, state: state,
                                            t: c?.ratio, valueText: vText, originalText: oText,
                                            previousT: p?.ratio, previousText: pText, deltaText: dText,
                                            carriedFrom: carriedFrom, archived: isArchived)
            axisModels.append(model)
        }

        let rated: Int = axisModels.filter { $0.t != nil }.count
        let filled: Int = curCells.compactMap { $0 }.count
        let avg: Double? = averageRatio(curCells)
        let prevAvg: Double? = averageRatio(prevCells)
        let title: String = group.displayName

        let dateLine: String
        if let d = latest {
            if !hasPrev {
                dateLine = "第一次評分"
            } else if prevDays.count == 1 {
                dateLine = shortDay(d) + " 比 " + shortDay(prevDays[0])
            } else {
                dateLine = shortDay(d) + " 比之前"
            }
        } else {
            dateLine = "還沒評過"
        }
        let legendPrev: String?
        if let d = latest, hasPrev {
            legendPrev = prevDays.count == 1 ? shortDay(prevDays[0]) : shortDay(d) + " 之前"
        } else {
            legendPrev = nil
        }

        var note: String? = nil
        if style == .bars {
            note = n <= 2 ? "項目少於 3 個，改用橫條" : "超過 12 項，改用橫條"
        } else if style != .empty && rated > 0 && rated < 3 {
            note = "評了 \(rated) 項，還畫不成雷達"
        }

        var avgText: String? = nil
        if let a = avg { avgText = "平均 " + oneDecimalText(round1(value(atRatio: a, range))) }
        let a11y: String = accessibilityText(title: title, axes: axisModels, average: avg, range: range)
        let headline: String = title + "・" + dateLine
        let ringList: [CompetencyRing] = rings(range)
        let isRadar: Bool = style == .radar || style == .radarShort
        let draws: Bool = rated >= 3 && isRadar
        let legendNow: String? = latest.map { shortDay($0) }
        let carriedLine: String? = carried.isEmpty ? nil : carried.joined(separator: "、")
        return CompetencyChartModel(
            id: gid, isTrait: group.isTrait, title: title, dateLine: dateLine, headline: headline,
            averageText: avgText, style: style, axes: axisModels, rings: ringList, range: range,
            ratedCount: rated, drawsPolygon: draws, hasPrevious: hasPrev, legendCurrent: legendNow,
            legendPrevious: legendPrev, note: note, carriedNote: carriedLine, accessibilityText: a11y,
            neverRated: latest == nil, averageRatio: avg, previousAverageRatio: prevAvg,
            filledCount: filled, axisCount: n, latestDay: latest)
    }

    /// ↔ a11y：「Gas System，3 項，平均 4 分。P&ID 4 分，跟上次一樣；緊急應變 4 分，上次 2 分；值班技能 4 分，上次 3 分。」
    static func accessibilityText(title: String, axes: [CompetencyAxisModel], average: Double?, range: CompetencyRange) -> String {
        var s: String = title + "，\(axes.count) 項"
        if let a = average {
            let v: Double = round1(value(atRatio: a, range))
            s += "，平均 " + plainNumberText(v) + " 分"
        }
        s += "。"
        var parts: [String] = []
        for ax in axes {
            var p: String = ax.name + " "
            switch ax.state {
            case .unrated: p += "未評"
            case .na: p += "不適用"
            case .rated:
                p += (ax.valueText ?? "") + " 分"
                if let pt = ax.previousText {
                    let same: Bool = pt == (ax.valueText ?? "")
                    p += same ? "，跟上次一樣" : ("，上次 " + pt + " 分")
                }
            }
            parts.append(p)
        }
        if !parts.isEmpty { s += parts.joined(separator: "；") + "。" }
        return s
    }

    // MARK: 這位同仁要畫哪幾張卡（judge §3.4、§3.6、§4.3）

    /// ↔ visible_groups：在職：人格（有項目才有）＋啟用、要學的系統；已轉出：凡是有分數的組都畫（含已停用的系統）
    static func visibleGroups(setup: CompetencySetupBook, subordinateId: UUID, archivedPerson: Bool,
                              sessions: [CompetencySession]) -> [CompetencyGroup] {
        let skipped: Set<UUID> = setup.skippedGroupIds(subordinateId)
        let ratedGroups: Set<UUID> = Set(latestCells(sessions).keys.map { $0.groupId })
        var out: [CompetencyGroup] = []
        if let tg = setup.traitGroup {
            if !setup.traitItems.isEmpty || (archivedPerson && ratedGroups.contains(tg.id)) { out.append(tg) }
        }
        if archivedPerson {
            let all = CompetencySetupBook.sortedGroups(setup.allGroups.filter { $0.isLive && !$0.isTrait })
            for g in all where ratedGroups.contains(g.id) || (g.isActive && !skipped.contains(g.id)) {
                out.append(g)
            }
        } else {
            for g in setup.activeSystems where !skipped.contains(g.id) { out.append(g) }
        }
        return out
    }

    /// ↔ card_axes：這張卡的軸＋其中已停用的（已轉出：啟用的軸＋有分數的已停用項目接在後面）
    static func cardAxes(group: CompetencyGroup, setup: CompetencySetupBook, archivedPerson: Bool,
                         sessions: [CompetencySession]) -> (axes: [CompetencyItem], archived: Set<UUID>) {
        let active: [CompetencyItem] = setup.axes(for: group.id)
        guard archivedPerson else { return (active, []) }
        let have: Set<UUID> = Set(active.map { $0.id })
        let rated: Set<UUID> = Set(latestCells(sessions).keys.filter { $0.groupId == group.id }.map { $0.itemId })
        let extraItems: [CompetencyItem] = CompetencySetupBook.sortedItems(
            setup.allItems.filter { $0.isLive && !have.contains($0.id) && rated.contains($0.id) })
        return (active + extraItems, Set(extraItems.map { $0.id }))
    }

    /// ↔ tab：〔職能〕分頁整頁
    static func tabModel(setup: CompetencySetupBook, ratings: CompetencyRatingBook, subordinateId: UUID,
                         archivedPerson: Bool, sessions: [CompetencySession], today: String) -> CompetencyTabModel {
        let groups: [CompetencyGroup] = visibleGroups(setup: setup, subordinateId: subordinateId,
                                                      archivedPerson: archivedPerson, sessions: sessions)
        var cards: [CompetencyChartModel] = []
        for g in groups {
            let ax = cardAxes(group: g, setup: setup, archivedPerson: archivedPerson, sessions: sessions)
            cards.append(chartModel(group: g, axes: ax.axes, archivedIds: ax.archived, sessions: sessions,
                                    range: setup.range(forGroup: g.id)))
        }
        let skipped: Set<UUID> = setup.skippedGroupIds(subordinateId)
        let skippedNames: [String] = setup.activeSystems.filter { skipped.contains($0.id) }.map { $0.displayName }
        let lastDay: String? = sessions.filter { $0.isLive && !$0.liveScores.isEmpty }.map { $0.dayKey }.max()
        let summary = summaryModel(cards: cards, setup: setup, lastDay: lastDay, today: today)
        return CompetencyTabModel(configured: setup.isConfigured,
                                  readOnly: setup.isReadOnlyHere || ratings.isReadOnlyHere,
                                  summary: summary, cards: cards, skippedNames: skippedNames,
                                  neverRated: lastDay == nil)
    }

    /// ↔ summary：人格特質＝人格那張卡的平均；本職學能＝要學的、啟用的、至少評過一格的系統，每個系統一樣重；覆蓋率一定配著
    static func summaryModel(cards: [CompetencyChartModel], setup: CompetencySetupBook, lastDay: String?,
                             today: String) -> CompetencySummaryModel {
        let trait: CompetencyChartModel? = cards.first { $0.isTrait }
        let systems: [CompetencyChartModel] = cards.filter { !$0.isTrait }
        let tr: CompetencyRange = setup.traitRange
        let sr: CompetencyRange = setup.skillRange

        var traitText: String? = nil
        var traitDelta: String? = nil
        if let t = trait, t.axisCount > 0 {
            if let a = t.averageRatio {
                traitText = oneDecimalText(round1(value(atRatio: a, tr))) + "／\(tr.high)"
                let pv: Double? = t.previousAverageRatio.map { value(atRatio: $0, tr) }
                traitDelta = averageDeltaText(current: value(atRatio: a, tr), previous: pv)
            } else {
                traitText = "—"
            }
        }

        var skillText: String? = nil
        var skillDelta: String? = nil
        var lowCoverage = false
        var coverageText: String? = nil
        var skillFilledText: String? = nil
        if !systems.isEmpty {
            let nowTs: [Double] = systems.compactMap { $0.averageRatio }
            let prevTs: [Double] = systems.compactMap { $0.previousAverageRatio }
            let sFilled: Int = systems.map { $0.filledCount }.reduce(0, +)
            let sTotal: Int = systems.map { $0.axisCount }.reduce(0, +)
            if !nowTs.isEmpty {
                let m: Double = nowTs.reduce(0, +) / Double(nowTs.count)
                skillText = oneDecimalText(round1(value(atRatio: m, sr))) + "／\(sr.high)"
                if !prevTs.isEmpty {
                    let pm: Double = prevTs.reduce(0, +) / Double(prevTs.count)
                    skillDelta = averageDeltaText(current: value(atRatio: m, sr), previous: value(atRatio: pm, sr))
                }
            } else {
                skillText = "—"
            }
            skillFilledText = "本職 \(sFilled)／\(sTotal)"
            if sTotal > 0 && sFilled > 0 && sFilled * 2 < sTotal {
                lowCoverage = true
                coverageText = "只評了 \(sFilled)／\(sTotal) 格"
            }
        }
        let filled: Int = cards.map { $0.filledCount }.reduce(0, +)
        let total: Int = cards.map { $0.axisCount }.reduce(0, +)

        let lastLine: String
        var stale = false
        if let d = lastDay {
            stale = isStale(lastDay: d, today: today)
            lastLine = "上次評分 " + shortDay(d) + "（" + agoText(lastDay: d, today: today) + "）" + (stale ? "・該重評了" : "")
        } else {
            lastLine = "還沒評過"
        }
        return CompetencySummaryModel(lastLine: lastLine, stale: stale, traitValueText: traitText,
                                      traitDeltaText: traitDelta, skillValueText: skillText, skillDeltaText: skillDelta,
                                      skillLowCoverage: lowCoverage, skillCoverageText: coverageText,
                                      filledText: "\(filled)／\(total) 格", skillFilledText: skillFilledText)
    }

    // MARK: 評分畫面（judge §3.7、§4.5）

    /// ↔ session_on：這一天已經有的那一張（兩台各開一張時取後改的）
    static func sessionOn(_ dayKey: String, sessions: [CompetencySession]) -> CompetencySession? {
        let same = sessions.filter { $0.isLive && $0.isByMe && $0.dayKey == dayKey }
        return same.max { a, b in a.stamp < b.stamp }
    }

    /// ↔ rating_plan：評分畫面的每一區。editing＝這一天已經有的那一張（用它自己的範圍）；沒有＝用現在的範圍。
    /// 上一次＝這張評分日之前、每一格最後一筆（不含這一張）。範圍跟這一張不一樣的格子不能照上次（§3.3）
    static func ratingPlan(setup: CompetencySetupBook, subordinateId: UUID, sessions: [CompetencySession],
                           dayKey: String, editing: CompetencySession?) -> [CompetencyRatingSection] {
        let groups: [CompetencyGroup] = visibleGroups(setup: setup, subordinateId: subordinateId,
                                                      archivedPerson: false, sessions: sessions)
        let others: [CompetencySession] = sessions.filter { $0.id != editing?.id }
        let before: [CompetencyCellKey: CompetencyCellValue] = latestCells(others, before: dayKey)
        let everRated: Set<CompetencyCellKey> = Set(latestCells(others).keys)
        var out: [CompetencyRatingSection] = []
        for g in groups {
            let axes: [CompetencyItem] = setup.axes(for: g.id)
            if axes.isEmpty { continue }
            let range: CompetencyRange = editing?.range(forGroup: g.id) ?? setup.range(forGroup: g.id)
            var rows: [CompetencyRatingAxis] = []
            var anySame = false
            var otherRange: CompetencyRange? = nil
            for it in axes {
                let key = CompetencyCellKey(groupId: g.id, itemId: it.id)
                let p: CompetencyCellValue? = before[key]
                let same: Bool = p?.range == range
                if p != nil && same { anySame = true }
                if let p, !same { otherRange = p.range }
                let pText: String? = p.map { previousText($0, in: range) }
                let pNear: Int? = p.flatMap { nearestLevel($0, in: range) }
                let sameOK: Bool = p != nil && same
                let isNew: Bool = !everRated.contains(key) && !others.isEmpty
                let row = CompetencyRatingAxis(id: it.id, name: it.displayName, previous: p, previousText: pText,
                                               previousNearest: pNear, previousSameRange: sameOK, isNew: isNew)
                rows.append(row)
            }
            var blocked: String? = nil
            if !anySame, let o = otherRange {
                blocked = "範圍改過（\(o.text) → \(range.text)），這組要重新點"
            }
            out.append(CompetencyRatingSection(id: g.id, title: g.displayName, isTrait: g.isTrait, range: range,
                                               axes: rows, canCarry: anySame, carryBlockedNote: blocked))
        }
        return out
    }

    /// ↔ prev_text：「上次 2（4/30）」「上次 ≈7.8（原 1–5 的 4）」「上次 不適用（4/30）」
    static func previousText(_ c: CompetencyCellValue, in range: CompetencyRange) -> String {
        if c.na { return "上次 不適用（" + shortDay(c.dayKey) + "）" }
        if let o = originalText(c, in: range) { return "上次 " + cellText(c, in: range) + "（" + o + "）" }
        return "上次 " + cellText(c, in: range) + "（" + shortDay(c.dayKey) + "）"
    }

    /// ↔ carry：〔全部照上次〕／〔這組照上次〕帶進來的格子（只帶範圍一樣的；淡框 carried＝true）
    static func carriedCells(_ sections: [CompetencyRatingSection]) -> [CompetencyCellKey: CompetencyDraftCell] {
        var out: [CompetencyCellKey: CompetencyDraftCell] = [:]
        for sec in sections where sec.canCarry {
            for ax in sec.axes where ax.previousSameRange {
                guard let p = ax.previous else { continue }
                out[CompetencyCellKey(groupId: sec.id, itemId: ax.id)] =
                    CompetencyDraftCell(value: p.na ? nil : p.value, na: p.na, comment: nil, carried: true)
            }
        }
        return out
    }

    /// ↔ draft_from：打開已經有的那一張時，把它的格子變成草稿（都是實心、不是照上次）
    static func draft(from s: CompetencySession) -> [CompetencyCellKey: CompetencyDraftCell] {
        var out: [CompetencyCellKey: CompetencyDraftCell] = [:]
        for sc in s.allScores where sc.isLive {
            out[sc.key] = CompetencyDraftCell(value: sc.isNA ? nil : sc.value, na: sc.isNA, comment: sc.comment, carried: false)
        }
        return out
    }

    /// ↔ footer：改了幾格、照上次幾格、進步幾格、退步幾格（跟上一次比，用比例 t）
    static func footerCounts(draft: [CompetencyCellKey: CompetencyDraftCell],
                             sections: [CompetencyRatingSection]) -> CompetencyFooterCounts {
        var changed = 0
        var carried = 0
        var up = 0
        var down = 0
        var hasPrev = false
        for sec in sections {
            for ax in sec.axes {
                if ax.previous != nil { hasPrev = true }
                guard let d = draft[CompetencyCellKey(groupId: sec.id, itemId: ax.id)], d.isSet else { continue }
                if d.carried { carried += 1 } else { changed += 1 }
                guard let v = d.value, !d.na, let p = ax.previous, let tp = p.ratio else { continue }
                let tc: Double = ratio(v, sec.range)
                if tc > tp + 1e-9 { up += 1 }
                if tc < tp - 1e-9 { down += 1 }
            }
        }
        return CompetencyFooterCounts(changed: changed, carried: carried, up: up, down: down, hasPrevious: hasPrev)
    }

    /// ↔ footer_text：「改了 8 格・照上次 4 格・進步 8・退步 0」；第一次「評了 12 格」；什麼都沒評「還沒評任何一格」
    static func footerText(_ c: CompetencyFooterCounts) -> String {
        let total: Int = c.changed + c.carried
        if total == 0 { return "還沒評任何一格" }
        if !c.hasPrevious { return "評了 \(total) 格" }
        return "改了 \(c.changed) 格・照上次 \(c.carried) 格・進步 \(c.up)・退步 \(c.down)"
    }

    /// ↔ saved_toast：「已儲存 10/30 的評分（12 格）」
    static func savedToast(_ s: CompetencySession) -> String {
        "已儲存 " + shortDay(s.dayKey) + " 的評分（\(s.liveScores.count) 格）"
    }

    /// ↔ build_session：把草稿存成一張評分。existing＝這一天已經有的那一張（逐格改：沒變的格子時間不動、
    /// 改了的蓋新時間、草稿裡空掉的蓋 clearedAt）；沒有＝新的一張（範圍＝打開評分時的 traitRange／skillRange）。
    /// 名字快照、那一分的名字（§13：出廠沒有 → nil）照 setup
    static func buildSession(existing: CompetencySession?, newId: UUID, subordinateId: UUID, dayKey: String,
                             traitRange: CompetencyRange, skillRange: CompetencyRange,
                             draft: [CompetencyCellKey: CompetencyDraftCell], sections: [CompetencyRatingSection],
                             setup: CompetencySetupBook, note: String?, gradeTitleId: UUID?, gradeLabel: String?,
                             now: Date) -> CompetencySession {
        var s: CompetencySession
        if let e = existing {
            s = e
        } else {
            s = CompetencySession(id: newId, subordinateId: subordinateId, dayKey: dayKey,
                                  raterKind: CompetencySession.raterMe, raterId: PerformanceBallot.selfRaterId,
                                  gradeTitleId: gradeTitleId, gradeLabel: gradeLabel,
                                  traitLow: traitRange.low, traitHigh: traitRange.high,
                                  skillLow: skillRange.low, skillHigh: skillRange.high,
                                  scores: [], createdAt: now)
        }
        var cells: [CompetencyScore] = s.allScores
        var index: [CompetencyCellKey: Int] = [:]
        for (i, sc) in cells.enumerated() { index[sc.key] = i }
        var orderedKeys: [CompetencyCellKey] = []
        for sec in sections {
            for ax in sec.axes { orderedKeys.append(CompetencyCellKey(groupId: sec.id, itemId: ax.id)) }
        }
        for key in draft.keys where !orderedKeys.contains(key) { orderedKeys.append(key) }
        for key in orderedKeys {
            guard let d = draft[key], d.isSet else { continue }
            let comment: String? = {
                let t = (d.comment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }()
            if let i = index[key], cells[i].isLive {
                let old = cells[i]
                if old.value == (d.na ? nil : d.value) && old.isNA == d.na && old.comment == comment { continue }
            }
            let gName: String? = setup.group(key.groupId)?.displayName
            let iName: String? = setup.item(key.itemId)?.displayName
            let lName: String? = d.na ? nil : d.value.flatMap { setup.scaleFor(group: key.groupId)?.levelName($0) }
            var sc = CompetencyScore(groupId: key.groupId, itemId: key.itemId, value: d.na ? nil : d.value,
                                     na: d.na ? true : nil, comment: comment, groupName: gName, itemName: iName,
                                     levelName: lName, updatedAt: now)
            if let i = index[key] {
                sc.showToPerson = cells[i].showToPerson
                sc.evidenceRecordIds = cells[i].evidenceRecordIds
                sc.extra = cells[i].extra
                cells[i] = sc
            } else {
                index[key] = cells.count
                cells.append(sc)
            }
        }
        // 草稿裡空掉的（原本有評、這次清掉）：蓋 clearedAt（格子的墓碑，合併時不會被帶回來）
        for i in cells.indices where cells[i].isLive {
            let d = draft[cells[i].key]
            if d == nil || d?.isSet == false { cells[i].clearedAt = now }
        }
        s.scores = cells
        let t = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        s.note = t.isEmpty ? nil : t
        s.updatedAt = now
        if s.createdAt == nil { s.createdAt = now }
        return s
    }

    // MARK: 0–100（只給 v3 縱軸；〔職能〕分頁不顯示）

    /// ↔ idx：本職學能＝各系統 t 平均的平均 ×100；人格＝人格那組 t 平均 ×100，四捨五入
    static func index0to100(cards: [CompetencyChartModel], trait: Bool) -> Int? {
        let ts: [Double] = cards.filter { $0.isTrait == trait }.compactMap { $0.averageRatio }
        guard !ts.isEmpty else { return nil }
        return roundHalfUp(ts.reduce(0, +) / Double(ts.count) * 100)
    }
}
