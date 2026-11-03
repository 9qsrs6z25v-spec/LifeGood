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
    /// [v25.600 v1a-2] 這一分的名字（§13：出廠沒有 → nil）：現在的名字「能教人」；當時的名字跟現在不一樣「當時：能教人」；
    /// 評分紀錄的唯讀雷達寫那一張存的名字
    let levelText: String?
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
    /// [v25.600 v1a-2] 這張卡自己的上一次「上一次 4/30」「上一次 12/15 之前」（沒有上一次 nil）
    let previousDayText: String?
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
    // [v25.600 v1a-2] 原本 SubordinateCompetencyTab 自己的小函式搬進來（sim 對照）
    /// 有任何一張卡有上一次（才出現「疊：上一次」）
    let hasAnyPrevious: Bool
    /// 疊的膠囊「上一次 4/30」；各張卡不是同一天「上一次」
    let overlayLabel: String
    /// 各張卡的上一次不是同一天時，膠囊下面一行「上一次：人格特質 10/30・Gas System 11/30」（同一天或沒有 nil）
    let previousDayText: String?
    /// 「不用學：（無）」「不用學：Gas System、Chemical System」
    let skippedLineText: String
    /// 評分紀錄（新的在前；同一天合成一列）
    let records: [CompetencyRecordRow]
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
    /// [v25.600 v1a-2] 改舊紀錄時才會有：現在已停用（或這個系統拿掉了）、但那一張有評的項目（標「已停用」）
    let archived: Bool
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
    /// [v25.600 v1a-2]「這次評」膠囊上的字（系統有短名寫短名；人格特質寫「人格特質」）
    let chipTitle: String
    /// [v25.600 v1a-2] 改舊紀錄時才會有：這個系統現在已停用（或這位不用學），但那一張有評
    let archived: Bool
}

/// 評分畫面底部那一行的數字
struct CompetencyFooterCounts: Equatable {
    let changed: Int
    let carried: Int
    let up: Int
    let down: Int
    let hasPrevious: Bool
    /// [v25.600 v1a-2] 打開的是已經有的那一張（跟打開時比：改了幾格、清掉幾格、沒動幾格）
    let editing: Bool
    /// 改那一張時：跟打開時一樣的格子
    let unchanged: Int
    /// 改那一張時：打開時有、現在清掉的格子
    let removed: Int
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

    /// ↔ card：axes＝這張卡的軸（照順序）；archivedIds＝其中已停用的項目（已轉出的卡片、評分紀錄的唯讀雷達才會帶）。
    /// [v25.600 v1a-2] scale＝這一組現在的等級表（每一分的名字；沒有就 nil）；snapshotDay 有值＝評分紀錄的唯讀雷達
    ///（sessions 只放那一張、range＝那一張的範圍：畫當時的樣子，不疊上一次、名字用那一張存的）
    static func chartModel(group: CompetencyGroup, axes: [CompetencyItem], archivedIds: Set<UUID>,
                           sessions: [CompetencySession], range: CompetencyRange,
                           scale: CompetencyScale? = nil, snapshotDay: String? = nil) -> CompetencyChartModel {
        let gid: UUID = group.id
        let n: Int = axes.count
        let style: CompetencyChartStyle = chartStyle(axisCount: n)
        let now: [CompetencyCellKey: CompetencyCellValue] = latestCells(sessions)
        let curCells: [CompetencyCellValue?] = axes.map { now[CompetencyCellKey(groupId: gid, itemId: $0.id)] }
        let latest: String? = curCells.compactMap { $0?.dayKey }.max()
        var prevCells: [CompetencyCellValue?] = Array(repeating: nil, count: n)
        if let d = latest, snapshotDay == nil {
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
            var lText: String? = nil
            if let cell = c {
                if snapshotDay == nil {
                    lText = levelText(cell, scale: scale, in: range)
                } else {
                    lText = snapshotLevelText(cell)
                }
            }
            let model = CompetencyAxisModel(id: item.id, name: item.displayName, label: label, state: state,
                                            t: c?.ratio, valueText: vText, originalText: oText, levelText: lText,
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
        if let snap = snapshotDay {
            dateLine = shortDay(snap)
        } else if let d = latest {
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
        let prevDayText: String? = legendPrev.map { "上一次 " + $0 }
        return CompetencyChartModel(
            id: gid, isTrait: group.isTrait, title: title, dateLine: dateLine, headline: headline,
            averageText: avgText, style: style, axes: axisModels, rings: ringList, range: range,
            ratedCount: rated, drawsPolygon: draws, hasPrevious: hasPrev, legendCurrent: legendNow,
            legendPrevious: legendPrev, note: note, carriedNote: carriedLine, accessibilityText: a11y,
            neverRated: latest == nil, averageRatio: avg, previousAverageRatio: prevAvg,
            filledCount: filled, axisCount: n, latestDay: latest, previousDayText: prevDayText)
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
                                    range: setup.range(forGroup: g.id), scale: setup.scaleFor(group: g.id)))
        }
        let skipped: Set<UUID> = setup.skippedGroupIds(subordinateId)
        let skippedNames: [String] = setup.activeSystems.filter { skipped.contains($0.id) }.map { $0.displayName }
        let lastDay: String? = sessions.filter { $0.isLive && !$0.liveScores.isEmpty }.map { $0.dayKey }.max()
        let summary = summaryModel(cards: cards, setup: setup, lastDay: lastDay, today: today)
        return CompetencyTabModel(configured: setup.isConfigured,
                                  readOnly: setup.isReadOnlyHere || ratings.isReadOnlyHere,
                                  summary: summary, cards: cards, skippedNames: skippedNames,
                                  neverRated: lastDay == nil,
                                  hasAnyPrevious: hasAnyPrevious(cards),
                                  overlayLabel: overlayLabel(cards),
                                  previousDayText: previousDayText(cards),
                                  skippedLineText: skippedLineText(skippedNames),
                                  records: recordRows(sessions: sessions, setup: setup))
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
    /// [v25.600 v1a-2] 改已經有的那一張時，那一張有評、但現在不在畫面上的組（已停用的系統、不用學的系統）
    /// 與項目（已停用、這個系統拿掉的）也列出來、標 archived（評分紀錄〔改分數〕用；editing＝nil 時跟 v1a-1 一模一樣）
    static func ratingPlan(setup: CompetencySetupBook, subordinateId: UUID, sessions: [CompetencySession],
                           dayKey: String, editing: CompetencySession?) -> [CompetencyRatingSection] {
        let shown: [CompetencyGroup] = visibleGroups(setup: setup, subordinateId: subordinateId,
                                                     archivedPerson: false, sessions: sessions)
        let editedCells: [CompetencyScore] = editing?.liveScores ?? []
        let editedGroupIds: Set<UUID> = Set(editedCells.map { $0.groupId })
        let shownIds: Set<UUID> = Set(shown.map { $0.id })
        var groups: [CompetencyGroup] = shown
        if !editedGroupIds.isEmpty {
            let extraGroups: [CompetencyGroup] = setup.allGroups.filter {
                $0.isLive && !shownIds.contains($0.id) && editedGroupIds.contains($0.id)
            }
            if !extraGroups.isEmpty { groups = CompetencySetupBook.sortedGroups(shown + extraGroups) }
        }
        let others: [CompetencySession] = sessions.filter { $0.id != editing?.id }
        let before: [CompetencyCellKey: CompetencyCellValue] = latestCells(others, before: dayKey)
        let everRated: Set<CompetencyCellKey> = Set(latestCells(others).keys)
        var out: [CompetencyRatingSection] = []
        for g in groups {
            let groupArchived: Bool = !shownIds.contains(g.id)
            let active: [CompetencyItem] = setup.axes(for: g.id)
            let activeIds: Set<UUID> = Set(active.map { $0.id })
            let ratedHere: Set<UUID> = Set(editedCells.filter { $0.groupId == g.id }.map { $0.itemId })
            let extraItems: [CompetencyItem] = CompetencySetupBook.sortedItems(setup.allItems.filter {
                $0.isLive && !activeIds.contains($0.id) && ratedHere.contains($0.id)
            })
            let archivedIds: Set<UUID> = Set(extraItems.map { $0.id })
            let axes: [CompetencyItem]
            if groupArchived {
                let ratedActive: [CompetencyItem] = active.filter { ratedHere.contains($0.id) }
                axes = ratedActive + extraItems
            } else {
                axes = active + extraItems
            }
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
                                               previousNearest: pNear, previousSameRange: sameOK, isNew: isNew,
                                               archived: groupArchived || archivedIds.contains(it.id))
                rows.append(row)
            }
            var blocked: String? = nil
            if !anySame, let o = otherRange {
                blocked = "範圍改過（\(o.text) → \(range.text)），這組要重新點"
            }
            out.append(CompetencyRatingSection(id: g.id, title: g.displayName, isTrait: g.isTrait, range: range,
                                               axes: rows, canCarry: anySame, carryBlockedNote: blocked,
                                               chipTitle: chipTitle(g), archived: groupArchived))
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
        footerCounts(draft: draft, sections: sections, baseline: nil)
    }

    /// ↔ footer（baseline）：[v25.600 v1a-2] baseline＝打開已經有的那一張時的樣子（CompetencyMath.draft(from:)）。
    /// 有 baseline：跟打開時一樣的格子算「沒動」、不一樣（或新點的）算「改了」、打開時有現在清掉的算「清掉」；
    /// 照上次帶進原本空著的格子算「照上次」。進步／退步照舊跟上一次比（用比例 t）。沒有 baseline＝v1a-1 一模一樣
    static func footerCounts(draft: [CompetencyCellKey: CompetencyDraftCell], sections: [CompetencyRatingSection],
                             baseline: [CompetencyCellKey: CompetencyDraftCell]?) -> CompetencyFooterCounts {
        var changed = 0
        var carried = 0
        var up = 0
        var down = 0
        var unchanged = 0
        var removed = 0
        var hasPrev = false
        for sec in sections {
            for ax in sec.axes {
                if ax.previous != nil { hasPrev = true }
                let key = CompetencyCellKey(groupId: sec.id, itemId: ax.id)
                let b: CompetencyDraftCell? = baseline?[key]
                let bSet: Bool = b?.isSet == true
                guard let d = draft[key], d.isSet else {
                    if bSet { removed += 1 }
                    continue
                }
                if let b0 = b, bSet, sameCell(d, b0) {
                    unchanged += 1
                } else if d.carried && !bSet {
                    carried += 1
                } else {
                    changed += 1
                }
                guard let v = d.value, !d.na, let p = ax.previous, let tp = p.ratio else { continue }
                let tc: Double = ratio(v, sec.range)
                if tc > tp + 1e-9 { up += 1 }
                if tc < tp - 1e-9 { down += 1 }
            }
        }
        return CompetencyFooterCounts(changed: changed, carried: carried, up: up, down: down, hasPrevious: hasPrev,
                                      editing: baseline != nil, unchanged: unchanged, removed: removed)
    }

    /// ↔ same_cell：兩格一樣（分數、不適用；評語不算——§13 不做每一格的評語，別台寫的照留）
    static func sameCell(_ a: CompetencyDraftCell, _ b: CompetencyDraftCell) -> Bool {
        a.isSet == b.isSet && a.na == b.na && (a.na || a.value == b.value)
    }

    /// ↔ footer_text：「改了 8 格・照上次 4 格・進步 8・退步 0」；第一次「評了 12 格」；什麼都沒評「還沒評任何一格」。
    /// [v25.600 v1a-2] 改已經有的那一張：沒改「沒有改動（這一張 12 格）」；有改「改了 2 格・沒動 10 格・進步 1・退步 0」
    ///（照上次、清掉有才寫）
    static func footerText(_ c: CompetencyFooterCounts) -> String {
        if c.editing {
            if c.changed + c.carried + c.removed == 0 { return "沒有改動（這一張 \(c.unchanged) 格）" }
            var parts: [String] = ["改了 \(c.changed) 格"]
            if c.carried > 0 { parts.append("照上次 \(c.carried) 格") }
            if c.removed > 0 { parts.append("清掉 \(c.removed) 格") }
            parts.append("沒動 \(c.unchanged) 格")
            if c.hasPrevious { parts.append("進步 \(c.up)・退步 \(c.down)") }
            return parts.joined(separator: "・")
        }
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
            // [v25.600 v1a-2] 那一分的名字只在「這一張的範圍＝現在等級表的範圍」時存（改舊紀錄用舊範圍時不存現在的名字）
            let lvScale: CompetencyScale? = setup.scaleFor(group: key.groupId)
            // [v25.600 v1a-2 驗證修] 超過 11 級（例 0–100）不設名字（§13）：1–5 時設的名字在 0–100 裡還留著（1～5 在範圍裡），
            // 不擋的話 0–100 評 4 會存「能教人」、雷達寫「當時：能教人」。要退回這一件：拿掉 && namesAllowed(...)
            let fitRange: CompetencyRange = s.range(forGroup: key.groupId)
            let namesFit: Bool = lvScale?.range == fitRange && namesAllowed(fitRange)
            let lName: String? = (d.na || !namesFit) ? nil : d.value.flatMap { lvScale?.levelName($0) }
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

// MARK: - [v25.600 職能雷達 v1a-2] 評分紀錄、點一格的歷史、每一分的名字、系統頁、設定預覽、已停用、清理、數字欄
//（radar/judge.md §7 分版表 v1a-2、§3.3、§3.4、§3.5、§3.7-10、§4.3④、§4.4、§1.4-8、§13（每一格的評語不做）；
//  radar/build/v1a-2/brief.md §2；sim_v1a-2.py 一個函式一個函式對照，↔ 後面是 sim 的名字）
// • §13 追加：每一格的評語不做——這裡組的字一個都不放評語（CompetencyScore.comment 照留、別台寫的原樣存回去）。
// • 一次評分的總評（CompetencySession.note）照 v1a-1 留著（評分紀錄明細照樣寫）。

/// 評分紀錄一列（同一天兩台各評一張時合成一列「10/30（五）・2 次」）
struct CompetencyRecordRow: Equatable, Identifiable {
    /// ＝dayKey
    let id: String
    let dayKey: String
    /// 「10/30（五）」
    let dayText: String
    /// 「2 次」（只有一張 nil）
    let countText: String?
    /// 「評了 人格・Gas System・Slurry System・Chemical System」（系統有短名寫短名）；一格都沒有「沒有分數」
    let groupsText: String
    /// 「12 格」
    let cellCountText: String
    /// 這一天的評分（後改的在前）
    let sessionIds: [UUID]
    /// VoiceOver 一句
    let accessibilityText: String
}

/// 一次評分的明細（唯讀雷達畫當時的樣子）
struct CompetencySessionDetailModel: Equatable, Identifiable {
    /// 評分 id
    let id: UUID
    let dayKey: String
    /// 「2026/10/30（五）的評分」
    let title: String
    /// 「評了 12 格」「那時：E2 工程師」「人格特質 1–5・本職學能 1–5」
    let infoLines: [String]
    /// 總評（沒寫 nil）
    let note: String?
    /// 每一組一張唯讀雷達（那一張有評的組；含已停用的項目／系統，標「已停用」；名字用那一張存的快照）
    let cards: [CompetencyChartModel]
    /// 刪除確認框
    let deleteTitle: String
    let deleteMessage: String
}

/// 點一格的歷史：一列
struct CompetencyHistoryRow: Equatable, Identifiable {
    /// 評分 id
    let id: UUID
    let dayKey: String
    /// 「10/30（五）」
    let dayText: String
    /// 「4」「≈7.8」「不適用」（換成現在的範圍）
    let valueText: String
    /// 「原 1–5 的 4（當時：能教人）」「能教人」；沒有 nil
    let detailText: String?
}

/// 點一格的歷史：每一分的名字那一排（有名字才有）
struct CompetencyLevelRow: Equatable, Identifiable {
    /// ＝分數
    let id: Int
    /// 「能教人」（這一分沒名字＝空字串）
    let name: String
    /// 現在是這一分
    let isCurrent: Bool
}

/// 點一格的歷史 sheet（.medium；§13：沒有評語）
struct CompetencyCellHistoryModel: Equatable {
    /// 「Gas System・緊急應變」
    let title: String
    /// 「現在 4（10/30）」「現在 4 能教人（10/30）」「現在 不適用（10/30）」「還沒評過」
    let nowLine: String
    /// 每一分的名字（等級表有名字、而且 ≤ 11 級才有；不然空）
    let levels: [CompetencyLevelRow]
    /// 歷史（新的在前）
    let rows: [CompetencyHistoryRow]
    /// 共用學習項目才有：「在其他系統：Slurry System 3、Chemical System 2」
    let otherLine: String?
    /// 「這一項已停用（分數留著）」「這個系統拿掉了這一項（分數留著）」
    let archivedNote: String?
}

/// 每一分的名字範本（〔套用範本 ▾〕；§13：出廠不套，使用者自己選）
struct CompetencyLevelTemplate: Equatable, Identifiable {
    let id: String
    /// 「OJT 五級」
    let title: String
    let names: [String]

    /// 選單上的字「OJT 五級（看過…專家）」
    var menuTitle: String {
        guard let a = names.first, let b = names.last else { return title }
        return title + "（" + a + "…" + b + "）"
    }
}

/// 設定預覽一格（空殼小雷達＋「3 項 → 三角形」）
struct CompetencyPreviewRow: Equatable, Identifiable {
    /// 組 id
    let id: UUID
    let title: String
    let isTrait: Bool
    let axisCount: Int
    let style: CompetencyChartStyle
    /// 「3 項 → 三角形」「2 項 → 橫條」「12 項 → 雷達（軸上寫短名）」「還沒有項目」
    let text: String
    /// 9 項起「超過 8 項雷達會很擠，建議拆成兩個系統」
    let warning: String?
}

/// 已停用清單一列（〔恢復〕〔永久刪除〕）
struct CompetencyArchivedRow: Equatable, Identifiable {
    let id: UUID
    /// true＝系統；false＝項目
    let isGroup: Bool
    let title: String
    /// 「系統」「人格特質」「共用學習項目」「Slurry System 自己的項目」
    let kindText: String
    /// 這一項（這個系統）有幾格評分
    let cellCount: Int
    /// 「8 格評分」「沒有評分」
    let countText: String
    /// 永久刪除的第二次確認
    let deleteTitle: String
    let deleteMessage: String
}

/// 〔清理已刪除同仁的評分〕（只算 life_subordinates 裡已經沒有這個人的；judge §1.4-8）
struct CompetencyOrphanSummary: Equatable {
    let personCount: Int
    let sessionCount: Int
    let sessionIds: [UUID]
    let assignmentIds: [UUID]
    /// 「清理已刪除同仁的評分（1 位、1 次）」
    let buttonText: String
    let confirmTitle: String
    /// 「這 1 位已經不在部屬名單。如果是家裡還沒更新的 iPad 還沒同步到，先別清。」
    let confirmMessage: String
    /// 清完的小提示「已清理 1 位、1 次評分」
    let doneText: String
}

/// 數字欄打的字（§13：high > 10）
enum CompetencyInputCheck: Equatable {
    /// 空白（不改）
    case empty
    /// 跟現在一樣（不算改，關掉不用問）
    case same
    /// 會改成這個數字（超出範圍已經夾回）
    case changed(Int)
    /// 不是數字（儲存按鈕灰、欄位下面紅字）
    case invalid
}

extension CompetencyMath {

    // MARK: 〔職能〕分頁的小函式（v1a-1 G1 的 private 搬過來）

    /// ↔ has_any_previous
    static func hasAnyPrevious(_ cards: [CompetencyChartModel]) -> Bool {
        cards.contains { $0.hasPrevious }
    }

    /// ↔ overlay_label：疊的膠囊「上一次 4/30」；各張卡的上一次不是同一天（或沒有）只寫「上一次」
    static func overlayLabel(_ cards: [CompetencyChartModel]) -> String {
        let days: Set<String> = Set(cards.filter { $0.hasPrevious }.compactMap { $0.legendPrevious })
        guard days.count == 1, let d = days.first else { return "上一次" }
        return "上一次 " + d
    }

    /// ↔ previous_day_text：各張卡的上一次不是同一天時，每張卡寫自己的「上一次：人格特質 4/30・Gas System 11/30」；同一天 nil
    static func previousDayText(_ cards: [CompetencyChartModel]) -> String? {
        let withPrev: [CompetencyChartModel] = cards.filter { $0.hasPrevious && $0.legendPrevious != nil }
        let days: Set<String> = Set(withPrev.compactMap { $0.legendPrevious })
        guard days.count > 1 else { return nil }
        let parts: [String] = withPrev.map { $0.title + " " + ($0.legendPrevious ?? "") }
        return "上一次：" + parts.joined(separator: "・")
    }

    /// ↔ skipped_line_text：「不用學：（無）」「不用學：Gas System、Chemical System」
    static func skippedLineText(_ names: [String]) -> String {
        if names.isEmpty { return "不用學：（無）" }
        return "不用學：" + names.joined(separator: "、")
    }

    /// ↔ delta_direction：「↑…」1、「↓…」−1、其他 0（畫面照這個上色：↑ 綠、↓ 橘、其他灰）
    static func deltaDirection(_ text: String?) -> Int {
        guard let t = text else { return 0 }
        if t.hasPrefix("↑") { return 1 }
        if t.hasPrefix("↓") { return -1 }
        return 0
    }

    // MARK: 名字、短名

    /// 系統短名最多 10 字、項目短名最多 4 字、每一分的名字最多 4 字（judge §2.1、§4.4）
    static let groupShortMax: Int = 10
    static let itemShortMax: Int = 4
    static let levelNameMax: Int = 4

    /// ↔ clean_short：去空白、超過截掉、空的回 nil
    static func cleanShortName(_ s: String?, max n: Int) -> String? {
        let t: String = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        return String(t.prefix(n))
    }

    /// ↔ chip_title：「這次評」膠囊、紀錄那一列用的組名（系統有短名寫短名）
    static func chipTitle(_ g: CompetencyGroup) -> String {
        if g.isTrait { return g.displayName }
        return cleanShortName(g.shortName, max: groupShortMax) ?? g.displayName
    }

    /// ↔ record_group_name：紀錄那一列（人格特質寫「人格」）
    static func recordGroupName(_ g: CompetencyGroup) -> String {
        g.isTrait ? "人格" : chipTitle(g)
    }

    /// ↔ level_text：一格旁邊寫的那一分的名字。範圍跟現在一樣才有「現在的名字」；那一張存的名字跟現在不一樣寫「當時：能教人」
    static func levelText(_ c: CompetencyCellValue, scale: CompetencyScale?, in range: CompetencyRange) -> String? {
        guard !c.na, let v = c.value else { return nil }
        let current: String? = (c.range == range && namesAllowed(range)) ? scale?.levelName(v) : nil
        if let snap = snapshotLevelText(c) {
            if snap == current { return current }
            return "當時：" + snap
        }
        return current
    }

    /// ↔ snap_level：那一張存的那一分的名字（空的 nil）
    static func snapshotLevelText(_ c: CompetencyCellValue) -> String? {
        guard !c.na else { return nil }
        let t: String = (c.levelName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    // MARK: 評分紀錄（judge §4.3④、§3.7-10）

    /// 一格 → 畫面用的值（照那一張的範圍）
    static func cellValue(_ sc: CompetencyScore, in s: CompetencySession) -> CompetencyCellValue {
        CompetencyCellValue(value: sc.isNA ? nil : sc.value, na: sc.isNA, range: s.range(forGroup: sc.groupId),
                            dayKey: s.dayKey, sessionId: s.id, stamp: sc.updatedAt ?? s.stamp,
                            comment: sc.comment, levelName: sc.levelName)
    }

    /// ↔ ordered_groups：組照設定的順序（人格特質在前）；設定裡找不到的接在後面（照出現的順序）
    static func orderedGroupIds(_ ids: [UUID], setup: CompetencySetupBook) -> [UUID] {
        var seen: [UUID] = []
        for id in ids where !seen.contains(id) { seen.append(id) }
        let known: [CompetencyGroup] = CompetencySetupBook.sortedGroups(setup.allGroups.filter { seen.contains($0.id) })
        let knownIds: [UUID] = known.map { $0.id }
        return knownIds + seen.filter { !knownIds.contains($0) }
    }

    /// 一組的名字（設定裡找不到＝用那一張存的快照）
    static func groupTitle(_ gid: UUID, setup: CompetencySetupBook, sessions: [CompetencySession], short: Bool) -> String {
        if let g = setup.group(gid) { return short ? recordGroupName(g) : g.displayName }
        if gid == CompetencySetupBook.traitGroupId { return short ? "人格" : "人格特質" }
        for s in sessions {
            if let n = s.allScores.first(where: { $0.groupId == gid })?.groupName,
               !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return n }
        }
        return "已刪除的系統"
    }

    /// ↔ record_rows：評分紀錄（我評的、沒刪的；新的日子在前；同一天合成一列）
    static func recordRows(sessions: [CompetencySession], setup: CompetencySetupBook) -> [CompetencyRecordRow] {
        let live: [CompetencySession] = sessions.filter { $0.isLive && $0.isByMe }
        var byDay: [String: [CompetencySession]] = [:]
        for s in live { byDay[s.dayKey, default: []].append(s) }
        let days: [String] = byDay.keys.sorted(by: >)
        var out: [CompetencyRecordRow] = []
        for d in days {
            let list: [CompetencySession] = (byDay[d] ?? []).sorted { a, b in a.stamp > b.stamp }
            var gids: [UUID] = []
            var keys: Set<CompetencyCellKey> = []
            for s in list {
                for sc in s.liveScores {
                    gids.append(sc.groupId)
                    keys.insert(sc.key)
                }
            }
            let ordered: [UUID] = orderedGroupIds(gids, setup: setup)
            let names: [String] = ordered.map { groupTitle($0, setup: setup, sessions: list, short: true) }
            let groupsText: String = names.isEmpty ? "沒有分數" : "評了 " + names.joined(separator: "・")
            let countText: String? = list.count > 1 ? "\(list.count) 次" : nil
            let cellText: String = "\(keys.count) 格"
            var a11y: String = dayText(d)
            if let c = countText { a11y += "，" + c }
            a11y += "，" + groupsText + "，" + cellText
            out.append(CompetencyRecordRow(id: d, dayKey: d, dayText: dayText(d), countText: countText,
                                           groupsText: groupsText, cellCountText: cellText,
                                           sessionIds: list.map { $0.id }, accessibilityText: a11y))
        }
        return out
    }

    /// ↔ session_cards：一次評分的唯讀雷達（畫當時的樣子）：那一張有評的組、有評的格子；
    /// 軸＝現在的順序裡有評的 → 已停用／這個系統拿掉的（標已停用）→ 設定裡找不到的（用快照名字、標已停用）；
    /// 範圍＝那一張的範圍；名字＝那一張存的快照；不疊上一次
    static func sessionCards(_ s: CompetencySession, setup: CompetencySetupBook) -> [CompetencyChartModel] {
        let cells: [CompetencyScore] = s.liveScores
        let gids: [UUID] = orderedGroupIds(cells.map { $0.groupId }, setup: setup)
        var out: [CompetencyChartModel] = []
        for gid in gids {
            let mine: [CompetencyScore] = cells.filter { $0.groupId == gid }
            let ratedIds: [UUID] = mine.map { $0.itemId }
            let ratedSet: Set<UUID> = Set(ratedIds)
            let current: [CompetencyItem] = setup.axes(for: gid).filter { ratedSet.contains($0.id) }
            let currentIds: Set<UUID> = Set(current.map { $0.id })
            let others: [CompetencyItem] = CompetencySetupBook.sortedItems(setup.allItems.filter {
                $0.isLive && ratedSet.contains($0.id) && !currentIds.contains($0.id)
            })
            let knownIds: Set<UUID> = currentIds.union(others.map { $0.id })
            var unknown: [CompetencyItem] = []
            for id in ratedIds where !knownIds.contains(id) {
                let raw: String = (mine.first(where: { $0.itemId == id })?.itemName ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                unknown.append(CompetencyItem(id: id, groupId: gid, name: raw.isEmpty ? "已刪除的項目" : raw))
            }
            let axes: [CompetencyItem] = current + others + unknown
            let archivedIds: Set<UUID> = Set(others.map { $0.id }).union(unknown.map { $0.id })
            var g: CompetencyGroup
            if let found = setup.group(gid), found.isLive {
                g = found
                if !found.isTrait && !found.isActive { g.name = found.displayName + "（已停用）" }
            } else {
                let isTrait: Bool = gid == CompetencySetupBook.traitGroupId
                g = CompetencyGroup(id: gid, kind: isTrait ? CompetencyGroup.kindTrait : CompetencyGroup.kindSystem,
                                    name: groupTitle(gid, setup: setup, sessions: [s], short: false))
            }
            out.append(chartModel(group: g, axes: axes, archivedIds: archivedIds, sessions: [s],
                                  range: s.range(forGroup: gid), scale: nil, snapshotDay: s.dayKey))
        }
        return out
    }

    /// ↔ session_detail：明細頁
    static func sessionDetail(_ s: CompetencySession, setup: CompetencySetupBook) -> CompetencySessionDetailModel {
        let cards: [CompetencyChartModel] = sessionCards(s, setup: setup)
        let live: [CompetencyScore] = s.liveScores
        var info: [String] = ["評了 \(live.count) 格"]
        let grade: String = (s.gradeLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !grade.isEmpty { info.append("那時：" + grade) }
        var ranges: [String] = []
        if live.contains(where: { $0.groupId == CompetencySetupBook.traitGroupId }) {
            ranges.append("人格特質 " + s.traitRange.text)
        }
        if live.contains(where: { $0.groupId != CompetencySetupBook.traitGroupId }) {
            ranges.append("本職學能 " + s.skillRange.text)
        }
        if !ranges.isEmpty { info.append(ranges.joined(separator: "・")) }
        let n: String = (s.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let del = deleteSessionConfirm(s)
        return CompetencySessionDetailModel(id: s.id, dayKey: s.dayKey, title: longDayText(s.dayKey) + "的評分",
                                            infoLines: info, note: n.isEmpty ? nil : n, cards: cards,
                                            deleteTitle: del.title, deleteMessage: del.message)
    }

    /// ↔ session_details：這一天的每一張（後改的在前；通常只有一張）
    static func sessionDetails(dayKey: String, sessions: [CompetencySession],
                               setup: CompetencySetupBook) -> [CompetencySessionDetailModel] {
        let list: [CompetencySession] = sessions.filter { $0.isLive && $0.isByMe && $0.dayKey == dayKey }
        return list.sorted { a, b in a.stamp > b.stamp }.map { sessionDetail($0, setup: setup) }
    }

    /// ↔ delete_session_confirm：「刪掉 10/30 的評分？」「這一次的 12 格會一起刪，不能復原。」
    static func deleteSessionConfirm(_ s: CompetencySession) -> (title: String, message: String) {
        let n: Int = s.liveScores.count
        let title: String = "刪掉 " + shortDay(s.dayKey) + " 的評分？"
        let msg: String = n > 0 ? "這一次的 \(n) 格會一起刪，不能復原。" : "這一次的評分會刪掉，不能復原。"
        return (title, msg)
    }

    /// ↔ move_problem：改評分日期能不能改（nil＝可以；同一天也是 nil、什麼都不做）
    static func moveSessionProblem(_ s: CompetencySession, to day: String, sessions: [CompetencySession],
                                   today: String) -> String? {
        guard parseDay(day) != nil else { return "日子不對" }
        if day == s.dayKey { return nil }
        if day > today { return "不能晚於今天" }
        let clash: Bool = sessions.contains { $0.id != s.id && $0.isLive && $0.isByMe && $0.dayKey == day }
        if clash { return shortDay(day) + " 已經有一張評分，先改或刪那一張。" }
        return nil
    }

    // MARK: 點一格的歷史（judge §4.3「點雷達頂點、軸名或橫條那一列」；§13：沒有評語）

    /// ↔ cell_history
    static func cellHistory(groupId: UUID, itemId: UUID, setup: CompetencySetupBook, subordinateId: UUID,
                            sessions: [CompetencySession]) -> CompetencyCellHistoryModel {
        let key = CompetencyCellKey(groupId: groupId, itemId: itemId)
        let range: CompetencyRange = setup.range(forGroup: groupId)
        let scale: CompetencyScale? = setup.scaleFor(group: groupId)
        let gName: String = groupTitle(groupId, setup: setup, sessions: sessions, short: false)
        var iName: String = setup.item(itemId)?.displayName ?? ""
        if iName.isEmpty {
            for s in sessions {
                if let n = s.score(key)?.itemName, !n.isEmpty { iName = n; break }
            }
        }
        if iName.isEmpty { iName = "已刪除的項目" }
        let latest: [CompetencyCellKey: CompetencyCellValue] = latestCells(sessions)
        let now: CompetencyCellValue? = latest[key]

        var nowLine: String = "還沒評過"
        if let c = now {
            var v: String = cellText(c, in: range)
            if !c.na, let n = c.value, c.range == range, namesAllowed(range), let ln = scale?.levelName(n) {
                v += " " + ln
            }
            nowLine = "現在 " + v + "（" + shortDay(c.dayKey) + "）"
        }

        var levels: [CompetencyLevelRow] = []
        if let sc = scale, namesAllowed(range), hasLevelNames(sc, in: range) {
            for v in range.low...range.high {
                let cur: Bool = now.map { !$0.na && $0.range == range && $0.value == v } ?? false
                levels.append(CompetencyLevelRow(id: v, name: sc.levelName(v) ?? "", isCurrent: cur))
            }
        }

        var rows: [CompetencyHistoryRow] = []
        let ordered: [CompetencySession] = sessions.filter { $0.isLive && $0.isByMe }.sorted { a, b in
            if a.dayKey != b.dayKey { return a.dayKey > b.dayKey }
            return a.stamp > b.stamp
        }
        for s in ordered {
            guard let sc = s.score(key), sc.isLive else { continue }
            let c: CompetencyCellValue = cellValue(sc, in: s)
            let o: String? = originalText(c, in: range)
            let l: String? = levelText(c, scale: scale, in: range)
            let detail: String?
            if let o, let l {
                detail = o + "（" + l + "）"
            } else {
                detail = o ?? l
            }
            rows.append(CompetencyHistoryRow(id: s.id, dayKey: s.dayKey, dayText: dayText(s.dayKey),
                                             valueText: cellText(c, in: range), detailText: detail))
        }

        var otherLine: String? = nil
        if setup.item(itemId)?.isShared == true && groupId != CompetencySetupBook.traitGroupId {
            let groups: [CompetencyGroup] = visibleGroups(setup: setup, subordinateId: subordinateId,
                                                          archivedPerson: false, sessions: sessions)
            var parts: [String] = []
            for g in groups where !g.isTrait && g.id != groupId {
                guard setup.axes(for: g.id).contains(where: { $0.id == itemId }) else { continue }
                let c: CompetencyCellValue? = latest[CompetencyCellKey(groupId: g.id, itemId: itemId)]
                let t: String = c.map { cellText($0, in: setup.skillRange) } ?? "未評"
                parts.append(chipTitle(g) + " " + t)
            }
            if !parts.isEmpty { otherLine = "在其他系統：" + parts.joined(separator: "、") }
        }

        var archivedNote: String? = nil
        if let g = setup.group(groupId), g.isLive, !g.isTrait, g.archivedAt != nil {
            archivedNote = "這個系統已停用（分數留著）"
        } else if let it = setup.item(itemId), it.isLive, it.archivedAt != nil {
            archivedNote = "這一項已停用（分數留著）"
        } else if (setup.group(groupId)?.hiddenSharedItemIds ?? []).contains(itemId) {
            archivedNote = "這個系統拿掉了這一項（分數留著）"
        }
        return CompetencyCellHistoryModel(title: gName + "・" + iName, nowLine: nowLine, levels: levels,
                                          rows: rows, otherLine: otherLine, archivedNote: archivedNote)
    }

    // MARK: 每一分的名字（§13：出廠空、範本自己選、改範圍時已經有名字才問）

    /// ↔ templates
    static let levelTemplates: [CompetencyLevelTemplate] = [
        CompetencyLevelTemplate(id: "ojt", title: "OJT 五級", names: ["看過", "指導下做", "能獨立", "能教人", "專家"]),
        CompetencyLevelTemplate(id: "trait5", title: "人格五級", names: ["很少", "偶爾", "穩定", "主動", "帶動"]),
        CompetencyLevelTemplate(id: "iluo", title: "ILUO 四級", names: ["在訓練", "能獨立", "能帶人", "訂標準"])
    ]

    /// ↔ names_allowed：≤ 11 級才設每一分的名字（0–100 這種只用數字）
    static func namesAllowed(_ r: CompetencyRange) -> Bool {
        r.levelCount <= 11
    }

    /// ↔ names_not_allowed_text
    static func namesNotAllowedText(_ r: CompetencyRange) -> String {
        "現在是 " + r.text + "，超過 11 級不設每一分的名字，只用數字。"
    }

    /// ↔ has_names_in：這個範圍裡有沒有任何一分有名字
    static func hasLevelNames(_ scale: CompetencyScale?, in r: CompetencyRange) -> Bool {
        guard let sc = scale, namesAllowed(r) else { return false }
        for v in r.low...r.high where sc.levelName(v) != nil { return true }
        return false
    }

    /// ↔ names_summary：設定頁那一列「看過・指導下做・能獨立・能教人・專家」；沒有「只用數字」
    static func levelNamesSummary(_ scale: CompetencyScale?, range r: CompetencyRange) -> String {
        guard let sc = scale, namesAllowed(r) else { return "只用數字" }
        var names: [String] = []
        for v in r.low...r.high {
            if let n = sc.levelName(v) { names.append(n) }
        }
        return names.isEmpty ? "只用數字" : names.joined(separator: "・")
    }

    /// ↔ current_names：名字頁打開時的草稿（這個範圍裡每一分現在的名字）
    static func currentLevelNames(_ scale: CompetencyScale?, range r: CompetencyRange) -> [Int: String] {
        var out: [Int: String] = [:]
        guard let sc = scale, namesAllowed(r) else { return out }
        for v in r.low...r.high {
            if let n = sc.levelName(v) { out[v] = n }
        }
        return out
    }

    /// ↔ apply_template：範本從最低分往上一級一個名字；級數不一樣寫一句
    static func applyTemplate(_ t: CompetencyLevelTemplate, to r: CompetencyRange) -> (names: [Int: String], note: String?) {
        var out: [Int: String] = [:]
        let n: Int = min(t.names.count, r.levelCount)
        for i in 0..<n { out[r.low + i] = t.names[i] }
        var note: String? = nil
        if t.names.count < r.levelCount {
            let first: Int = r.low + t.names.count
            let gap: String = first == r.high ? "\(r.high)" : "\(first)～\(r.high)"
            note = "範本只有 \(t.names.count) 級：" + gap + " 沒有名字，可以自己補。"
        } else if t.names.count > r.levelCount {
            note = "現在只有 \(r.levelCount) 級（" + r.text + "）：只用範本前 \(r.levelCount) 個。"
        }
        return (out, note)
    }

    /// ↔ merged_levels：把名字頁的草稿寫回等級表（範圍裡的照草稿；範圍外的原樣留著——改回原來的範圍名字還在；
    /// 每一分的說明 detail、別台的 extra 原樣留著）。全部空的回 nil
    static func mergedLevels(existing: [CompetencyLevel]?, names: [Int: String], range r: CompetencyRange) -> [CompetencyLevel]? {
        var out: [CompetencyLevel] = []
        var used: Set<Int> = []
        for lv in existing ?? [] {
            guard let v = lv.value, r.contains(v) else {
                out.append(lv)
                continue
            }
            used.insert(v)
            var x = lv
            x.name = cleanShortName(names[v], max: levelNameMax)
            let detail: String = (x.detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if x.name == nil && detail.isEmpty && x.extra == nil { continue }
            out.append(x)
        }
        for v in r.low...r.high where !used.contains(v) {
            if let n = cleanShortName(names[v], max: levelNameMax) {
                out.append(CompetencyLevel(value: v, name: n))
            }
        }
        out.sort { a, b in (a.value ?? Int.max) < (b.value ?? Int.max) }
        return out.isEmpty ? nil : out
    }

    /// ↔ should_ask_names：改範圍按〔改〕之後要不要接著問「每一分的名字要重新設嗎？」（舊範圍裡已經有名字、新範圍 ≤ 11 級才問）
    static func shouldAskNames(scale: CompetencyScale?, from old: CompetencyRange, to new: CompetencyRange) -> Bool {
        old != new && hasLevelNames(scale, in: old) && namesAllowed(new)
    }

    /// ↔ names_question
    static func namesQuestionText(from old: CompetencyRange, to new: CompetencyRange) -> String {
        "每一分的名字是照 " + old.text + " 設的。改成 " + new.text + " 後要重新設嗎？"
    }

    // MARK: 系統頁（judge §3.5、§4.4）

    /// ↔ hide_warning：系統拿掉一個共用項目的那一刻
    static func hideSharedWarning(systemName: String) -> String {
        systemName + " 會少一軸，雷達形狀跟其他系統不能直接比。"
    }

    /// ↔ copy_name：「Gas System（複製）」「Gas System（複製 2）」
    static func copyName(_ name: String, taken: [String]) -> String {
        let base: String = name + "（複製）"
        if !taken.contains(base) { return base }
        var i: Int = 2
        while taken.contains(name + "（複製 \(i)）") { i += 1 }
        return name + "（複製 \(i)）"
    }

    /// ↔ axes_line：「3 項：P&ID・緊急應變・值班技能」「還沒有學習項目」
    static func axesLine(setup: CompetencySetupBook, groupId: UUID) -> String {
        let names: [String] = setup.axes(for: groupId).map { $0.displayName }
        if names.isEmpty { return "還沒有學習項目" }
        return "\(names.count) 項：" + names.joined(separator: "・")
    }

    // MARK: 設定預覽（judge §4.4 預覽：改任何東西馬上跟著變）

    static let crowdedWarning: String = "超過 8 項雷達會很擠，建議拆成兩個系統"

    /// ↔ shape_name
    static func shapeName(_ n: Int) -> String {
        switch n {
        case ...0: return "還沒有項目"
        case 1, 2: return "橫條"
        case 3: return "三角形"
        case 4: return "四邊形"
        case 5: return "五邊形"
        case 6: return "六邊形"
        case 7: return "七邊形"
        case 8: return "八邊形"
        case 9...12: return "雷達（軸上寫短名）"
        default: return "橫條（超過 12 項）"
        }
    }

    /// ↔ preview_rows：人格特質（有那一組才有）＋啟用中的系統
    static func previewRows(setup: CompetencySetupBook) -> [CompetencyPreviewRow] {
        var out: [CompetencyPreviewRow] = []
        if let tg = setup.traitGroup {
            let n: Int = setup.traitItems.count
            let text: String = n == 0 ? "沒有項目，不顯示" : "\(n) 項 → " + shapeName(n)
            out.append(CompetencyPreviewRow(id: tg.id, title: tg.displayName, isTrait: true, axisCount: n,
                                            style: chartStyle(axisCount: n), text: text,
                                            warning: n > 8 ? crowdedWarning : nil))
        }
        for g in setup.activeSystems {
            let n: Int = setup.axes(for: g.id).count
            let text: String = n == 0 ? "還沒有項目" : "\(n) 項 → " + shapeName(n)
            out.append(CompetencyPreviewRow(id: g.id, title: g.displayName, isTrait: false, axisCount: n,
                                            style: chartStyle(axisCount: n), text: text,
                                            warning: n > 8 ? crowdedWarning : nil))
        }
        return out
    }

    // MARK: 已停用清單、永久刪除（judge §3.1-2、§3.4）

    /// ↔ cell_count_item：這一項在所有評分裡有幾格（沒刪的評分、沒清掉的格子；共用項目算所有系統）
    static func cellCount(itemId: UUID, ratings: CompetencyRatingBook) -> Int {
        var n: Int = 0
        for s in ratings.allSessions where s.isLive {
            n += s.liveScores.filter { $0.itemId == itemId }.count
        }
        return n
    }

    /// ↔ cell_count_group
    static func cellCount(groupId: UUID, ratings: CompetencyRatingBook) -> Int {
        var n: Int = 0
        for s in ratings.allSessions where s.isLive {
            n += s.liveScores.filter { $0.groupId == groupId }.count
        }
        return n
    }

    /// ↔ archived_kind：已停用的項目屬於哪裡
    static func archivedKindText(_ it: CompetencyItem, setup: CompetencySetupBook) -> String {
        if it.groupId == CompetencySetupBook.traitGroupId { return "人格特質" }
        guard let gid = it.groupId else { return "共用學習項目" }
        let gname: String = setup.group(gid)?.displayName ?? "系統"
        return gname + " 自己的項目"
    }

    /// ↔ archived_rows：已停用的系統在前、項目在後；每一列有幾格評分＋永久刪除的確認字
    static func archivedRows(setup: CompetencySetupBook, ratings: CompetencyRatingBook) -> [CompetencyArchivedRow] {
        var out: [CompetencyArchivedRow] = []
        for g in setup.archivedSystems {
            let n: Int = cellCount(groupId: g.id, ratings: ratings)
            let own: Int = setup.allItems.filter { $0.isLive && $0.groupId == g.id }.count
            var msg: String = n > 0 ? "會一起刪掉 \(n) 格評分" : "沒有評分"
            if own > 0 { msg += "，這個系統自己的 \(own) 個項目也會一起刪" }
            msg += "。不能復原。"
            out.append(CompetencyArchivedRow(id: g.id, isGroup: true, title: g.displayName, kindText: "系統",
                                             cellCount: n, countText: n > 0 ? "\(n) 格評分" : "沒有評分",
                                             deleteTitle: "永久刪除「" + g.displayName + "」？", deleteMessage: msg))
        }
        for it in setup.archivedItems {
            let n: Int = cellCount(itemId: it.id, ratings: ratings)
            let msg: String = n > 0 ? "會一起刪掉 \(n) 格評分（每一張評分裡這一格都拿掉）。不能復原。" : "沒有評分。刪掉不能復原。"
            out.append(CompetencyArchivedRow(id: it.id, isGroup: false, title: it.displayName,
                                             kindText: archivedKindText(it, setup: setup), cellCount: n,
                                             countText: n > 0 ? "\(n) 格評分" : "沒有評分",
                                             deleteTitle: "永久刪除「" + it.displayName + "」？", deleteMessage: msg))
        }
        return out
    }

    /// ↔ clearing_cells：把符合的格子蓋格子的墓碑（clearedAt＝now，分數、名字快照拿掉；兩台合併時不會被舊的帶回來）。
    /// 碰到的那幾張 updatedAt＝now。永久刪除項目／系統用
    static func clearingCells(_ book: CompetencyRatingBook, now: Date,
                              match: (CompetencyScore) -> Bool) -> CompetencyRatingBook {
        var b = book
        var list: [CompetencySession] = b.allSessions
        var changed = false
        for i in list.indices {
            var cells: [CompetencyScore] = list[i].allScores
            var hit = false
            for j in cells.indices where cells[j].isLive && match(cells[j]) {
                cells[j].value = nil
                cells[j].na = nil
                cells[j].comment = nil
                cells[j].levelName = nil
                cells[j].clearedAt = now
                hit = true
            }
            if hit {
                list[i].scores = cells
                list[i].updatedAt = now
                changed = true
            }
        }
        if changed { b.sessions = list }
        return b
    }

    // MARK: 〔清理已刪除同仁的評分〕（judge §1.4-8、§4.4）

    /// ↔ orphans：knownIds＝life_subordinates 裡現在有的人（含已轉出）。部屬名單是空的時候不提供（可能還沒載入）
    static func orphanSummary(setup: CompetencySetupBook, ratings: CompetencyRatingBook,
                              knownIds: Set<UUID>) -> CompetencyOrphanSummary? {
        guard !knownIds.isEmpty else { return nil }
        let sess: [CompetencySession] = ratings.allSessions.filter { $0.isLive && !knownIds.contains($0.subordinateId) }
        let asg: [CompetencyAssignment] = setup.allAssignments.filter { $0.deletedAt == nil && !knownIds.contains($0.id) }
        var people: Set<UUID> = Set(sess.map { $0.subordinateId })
        people.formUnion(asg.map { $0.id })
        guard !people.isEmpty else { return nil }
        let p: Int = people.count
        let n: Int = sess.count
        let button: String = n > 0 ? "清理已刪除同仁的評分（\(p) 位、\(n) 次）" : "清理已刪除同仁的評分（\(p) 位）"
        let msg: String = "這 \(p) 位已經不在部屬名單。如果是家裡還沒更新的 iPad 還沒同步到，先別清。"
        let done: String = n > 0 ? "已清理 \(p) 位、\(n) 次評分" : "已清理 \(p) 位"
        return CompetencyOrphanSummary(personCount: p, sessionCount: n, sessionIds: sess.map { $0.id },
                                       assignmentIds: asg.map { $0.id }, buttonText: button,
                                       confirmTitle: "清理已刪除同仁的評分？", confirmMessage: msg, doneText: done)
    }

    // MARK: 數字欄、儲存按鈕（v1a-1 adjudicate 留下的三件）

    /// ↔ check_input：current＝這一格現在的分數（沒評 nil）
    static func checkInput(_ text: String, current: Int?, range: CompetencyRange) -> CompetencyInputCheck {
        let t: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return .empty }
        guard let p = parseInput(t, range) else { return .invalid }
        return p.value == current ? .same : .changed(p.value)
    }

    /// ↔ invalid_text：「請打 0～100 的整數」
    static func invalidInputText(_ r: CompetencyRange) -> String {
        "請打 \(r.low)～\(r.high) 的整數"
    }

    /// ↔ can_save：打了不是數字 → 灰；改已經有的那一張 → 有改格子或總評才亮；新的一張 → 有評 1 格以上（或數字欄打了會改的數字）
    static func canSave(counts c: CompetencyFooterCounts, noteChanged: Bool, pendingChange: Bool,
                        invalidInput: Bool) -> Bool {
        if invalidInput { return false }
        if c.editing { return c.changed + c.carried + c.removed > 0 || noteChanged || pendingChange }
        return c.changed + c.carried > 0 || pendingChange
    }
}
