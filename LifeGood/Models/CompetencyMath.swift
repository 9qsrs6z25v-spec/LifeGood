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
    // [v25.601 職能雷達 v1b] 目標（照職等；judge §3.8 達標、§3.2 目標點線）。沒有目標全部 nil。要退回這一件：刪這五行
    /// 目標的比例（畫點線、橫條刻線）
    var targetT: Double? = nil
    /// 目標換到現在範圍「3」「≈5.5」
    var targetValueText: String? = nil
    /// 橫條下面「目標 3 ✓」「目標 3・差 1」「目標 3・未評」（不適用 nil）
    var targetText: String? = nil
    /// 達標了沒（沒評 false；不適用 nil）
    var targetMet: Bool? = nil
    /// 差幾級（現在範圍；達標 0；沒評、不適用 nil）
    var targetGap: Double? = nil
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
    // [v25.601 職能雷達 v1b] 目標、指定日期。要退回這一件：刪這幾行
    /// 有任何一軸有目標（畫點線）
    var hasTarget: Bool = false
    /// 圖例「目標 E2」
    var legendTarget: String? = nil
    /// 這張卡有目標、不是不適用的格子；其中達標的；其中沒評的
    var targetTotal: Int = 0
    var targetAchieved: Int = 0
    var targetUnrated: Int = 0
    /// 疊指定日期（評分紀錄明細〔跟現在比〕）：灰虛線＝那一天的樣子（previousT 就是那一天的）
    var compareDay: String? = nil
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
    /// [v25.601 職能雷達 v1b] 職等目標（整個設定一個目標都沒有 nil：什麼都不出現）。要退回這一件：刪這一行
    var targets: CompetencyTargetSummary? = nil
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
    /// [v25.601 v1b] targets 有值＝疊這個職等的目標（點線、橫條刻線、達標）；compareDay 有值＝灰虛線改成「那一天的樣子」
    ///（評分紀錄明細〔跟現在比〕；不疊上一次）。兩個都是 nil＝跟 v1a-2 一模一樣
    static func chartModel(group: CompetencyGroup, axes: [CompetencyItem], archivedIds: Set<UUID>,
                           sessions: [CompetencySession], range: CompetencyRange,
                           scale: CompetencyScale? = nil, snapshotDay: String? = nil,
                           targets: CompetencyChartTargets? = nil, compareDay: String? = nil) -> CompetencyChartModel {
        let gid: UUID = group.id
        let n: Int = axes.count
        let style: CompetencyChartStyle = chartStyle(axisCount: n)
        let now: [CompetencyCellKey: CompetencyCellValue] = latestCells(sessions)
        let curCells: [CompetencyCellValue?] = axes.map { now[CompetencyCellKey(groupId: gid, itemId: $0.id)] }
        let latest: String? = curCells.compactMap { $0?.dayKey }.max()
        var prevCells: [CompetencyCellValue?] = Array(repeating: nil, count: n)
        let compare: String? = snapshotDay == nil ? compareDay : nil
        if let cd = compare {
            // [v25.601 v1b] 跟指定日期比：那一天（含）之前每一格最後一筆
            let asOf = latestCells(sessions, through: cd)
            prevCells = axes.map { asOf[CompetencyCellKey(groupId: gid, itemId: $0.id)] }
        } else if let d = latest, snapshotDay == nil {
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
            var model = CompetencyAxisModel(id: item.id, name: item.displayName, label: label, state: state,
                                            t: c?.ratio, valueText: vText, originalText: oText, levelText: lText,
                                            previousT: p?.ratio, previousText: pText, deltaText: dText,
                                            carriedFrom: carriedFrom, archived: isArchived)
            // [v25.601 v1b] 這一格的目標（那一格 → 那個系統 → 這一區每項；已停用的軸不疊）
            if let tg = targets, !isArchived,
               let rt = resolveTarget(tg.table, gradeId: tg.grade.id, groupId: gid, itemId: item.id, fallback: range) {
                applyTarget(&model, rt, cell: c, range: range)
            }
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
        } else if let cd = compare {
            dateLine = latest.map { shortDay($0) + " 比 " + shortDay(cd) } ?? "還沒評過"
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
        if let cd = compare {
            legendPrev = hasPrev ? shortDay(cd) : nil
        } else if let d = latest, hasPrev {
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
        var a11y: String = accessibilityText(title: title, axes: axisModels, average: avg, range: range)
        // [v25.601 v1b] 目標：數幾格達標（不適用、已停用不算）
        let tAxes: [CompetencyAxisModel] = axisModels.filter { $0.targetT != nil && $0.state != .na && !$0.archived }
        let tAchieved: Int = tAxes.filter { $0.targetMet == true }.count
        let tUnrated: Int = tAxes.filter { $0.state == .unrated }.count
        let hasTarget: Bool = axisModels.contains { $0.targetT != nil }
        let legendTarget: String? = (hasTarget && targets != nil) ? "目標 " + (targets?.grade.short ?? "") : nil
        if let lt = legendTarget, !tAxes.isEmpty {
            a11y += lt + "：達標 \(tAchieved)／\(tAxes.count)。"
        }
        let headline: String = title + "・" + dateLine
        let ringList: [CompetencyRing] = rings(range)
        let isRadar: Bool = style == .radar || style == .radarShort
        let draws: Bool = rated >= 3 && isRadar
        let legendNow: String? = latest.map { shortDay($0) }
        let carriedLine: String? = carried.isEmpty ? nil : carried.joined(separator: "、")
        let prevDayText: String? = legendPrev.map { (compare == nil ? "上一次 " : "比 ") + $0 }
        var out = CompetencyChartModel(
            id: gid, isTrait: group.isTrait, title: title, dateLine: dateLine, headline: headline,
            averageText: avgText, style: style, axes: axisModels, rings: ringList, range: range,
            ratedCount: rated, drawsPolygon: draws, hasPrevious: hasPrev, legendCurrent: legendNow,
            legendPrevious: legendPrev, note: note, carriedNote: carriedLine, accessibilityText: a11y,
            neverRated: latest == nil, averageRatio: avg, previousAverageRatio: prevAvg,
            filledCount: filled, axisCount: n, latestDay: latest, previousDayText: prevDayText)
        out.hasTarget = hasTarget
        out.legendTarget = legendTarget
        out.targetTotal = tAxes.count
        out.targetAchieved = tAchieved
        out.targetUnrated = tUnrated
        out.compareDay = compare
        return out
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
            // [v25.601 v1b] 目標差（VoiceOver 一句話；不用 accessibilityChartDescriptor，brief 寫明）
            if ax.state != .na, let tv = ax.targetValueText {
                if ax.targetMet == true {
                    p += "，目標 " + tv + "，達標"
                } else if let g = ax.targetGap {
                    p += "，目標 " + tv + "，差 " + numberText(g)
                } else {
                    p += "，目標 " + tv
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
        tabModel(setup: setup, ratings: ratings, subordinateId: subordinateId, archivedPerson: archivedPerson,
                 sessions: sessions, today: today, grades: CompetencyGradeContext.empty, mode: .off)
    }

    /// ↔ tab（v1b）：[v25.601 v1b] grades＝職等表＋這位現在的職等；mode＝疊目前職等／下一個職等／不疊（摘要卡的選單，這台記住）。
    /// grades 空、mode .off＝跟 v1a-2 一模一樣（targets nil）
    static func tabModel(setup: CompetencySetupBook, ratings: CompetencyRatingBook, subordinateId: UUID,
                         archivedPerson: Bool, sessions: [CompetencySession], today: String,
                         grades: CompetencyGradeContext, mode: CompetencyTargetMode) -> CompetencyTabModel {
        let groups: [CompetencyGroup] = visibleGroups(setup: setup, subordinateId: subordinateId,
                                                      archivedPerson: archivedPerson, sessions: sessions)
        let table: [CompetencyTargetKey: CompetencyTarget] = targetTable(setup)
        let pick: CompetencyGradeRef? = targetGrade(grades, mode: mode, table: table)
        let chartTargets: CompetencyChartTargets? = pick.map { CompetencyChartTargets(grade: $0, table: table) }
        var cards: [CompetencyChartModel] = []
        for g in groups {
            let ax = cardAxes(group: g, setup: setup, archivedPerson: archivedPerson, sessions: sessions)
            cards.append(chartModel(group: g, axes: ax.axes, archivedIds: ax.archived, sessions: sessions,
                                    range: setup.range(forGroup: g.id), scale: setup.scaleFor(group: g.id),
                                    targets: chartTargets))
        }
        let skipped: Set<UUID> = setup.skippedGroupIds(subordinateId)
        let skippedNames: [String] = setup.activeSystems.filter { skipped.contains($0.id) }.map { $0.displayName }
        let lastDay: String? = sessions.filter { $0.isLive && !$0.liveScores.isEmpty }.map { $0.dayKey }.max()
        let summary = summaryModel(cards: cards, setup: setup, lastDay: lastDay, today: today)
        let hasContext: Bool = !grades.grades.isEmpty || grades.currentId != nil
        let records: [CompetencyRecordRow] = hasContext
            ? recordRows(sessions: sessions, setup: setup, currentGradeId: grades.currentId)
            : recordRows(sessions: sessions, setup: setup)
        var m = CompetencyTabModel(configured: setup.isConfigured,
                                   readOnly: setup.isReadOnlyHere || ratings.isReadOnlyHere,
                                   summary: summary, cards: cards, skippedNames: skippedNames,
                                   neverRated: lastDay == nil,
                                   hasAnyPrevious: hasAnyPrevious(cards),
                                   overlayLabel: overlayLabel(cards),
                                   previousDayText: previousDayText(cards),
                                   skippedLineText: skippedLineText(skippedNames),
                                   records: records)
        if hasContext {
            m.targets = targetSummary(cards: cards, table: table, grades: grades, mode: mode, pick: pick,
                                      setup: setup, sessions: sessions)
        }
        return m
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
    /// [v25.601 v1b] 那一張的職等跟現在不一樣：「那時 E2 工程師」（一樣、沒有 nil）
    var gradeNote: String? = nil
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
    /// [v25.601 v1b] 這一分的說明（項目自己的蓋過等級表的；沒有 nil）
    var detail: String? = nil
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
    // [v25.601 v1b] 要退回這一件：刪這兩行
    /// 「E2 目標 3（差 1）」「E2 目標 3 ✓」（沒設職等、沒目標 nil）
    var targetLine: String? = nil
    /// 三次以上才有：小折線（Swift Charts LineMark；舊範圍的點換算後空心）
    var trend: CompetencyTrendModel? = nil
}

/// 每一分的名字範本（〔套用範本 ▾〕；§13：出廠不套，使用者自己選）
struct CompetencyLevelTemplate: Equatable, Identifiable {
    let id: String
    /// 「OJT 五級」
    let title: String
    let names: [String]
    /// [v25.601 v1b] 每一分的說明（〔套用範本〕才填；§13 出廠空）
    var details: [String] = []

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
        CompetencyLevelTemplate(id: "ojt", title: "OJT 五級", names: ["看過", "指導下做", "能獨立", "能教人", "專家"],
                                details: ["看過別人做，知道在做什麼", "有人在旁邊指導可以做", "自己做得來，常見狀況會處理",
                                          "能帶新人演練、當帶訓者", "能處理異常、訂標準"]),
        CompetencyLevelTemplate(id: "trait5", title: "人格五級", names: ["很少", "偶爾", "穩定", "主動", "帶動"],
                                details: ["很少表現出來", "偶爾表現出來", "大多時候做得到", "會主動做、不用提醒",
                                          "能帶動身邊的人一起做"]),
        CompetencyLevelTemplate(id: "iluo", title: "ILUO 四級", names: ["在訓練", "能獨立", "能帶人", "訂標準"],
                                details: ["還在學，要有人帶", "可以自己做", "會處理異常、能教別人", "能訂標準、改流程"])
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
    /// [v25.601 v1b 裁定修] 只寫了說明、沒有名字也要問（不然 1–5 的說明原樣套在 1–10 的同一個數字上）。
    /// 要退回這一件：拿掉 `|| hasLevelDetails(scale, in: old)`
    static func shouldAskNames(scale: CompetencyScale?, from old: CompetencyRange, to new: CompetencyRange) -> Bool {
        old != new && (hasLevelNames(scale, in: old) || hasLevelDetails(scale, in: old)) && namesAllowed(new)
    }

    /// ↔ has_level_details：[v25.601 v1b 裁定修] 等級表在這個範圍裡有沒有任何一分寫了說明（> 11 級一律沒有）
    static func hasLevelDetails(_ scale: CompetencyScale?, in r: CompetencyRange) -> Bool {
        !currentLevelDetails(scale?.levels, range: r).isEmpty
    }

    /// ↔ names_question（[v25.601 v1b 裁定修] withDetails＝舊範圍有說明時寫「名字、說明」；預設跟 v1a-2 一樣）
    static func namesQuestionText(from old: CompetencyRange, to new: CompetencyRange, withDetails: Bool = false) -> String {
        let what: String = withDetails ? "每一分的名字、說明" : "每一分的名字"
        return what + "是照 " + old.text + " 設的。改成 " + new.text + " 後要重新設嗎？"
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

// MARK: - [v25.601 職能雷達 v1b] 職等目標、每一分的說明、走勢、跟指定日期比、重名合併、日子轉 Date
//（radar/judge.md §7 分版表 v1b、§3.3 目標換算、§3.6 目標照職等、§3.8 達標與差距、§4.4 職等目標與重名偵測、§4.5、§4.6、§5、§13；
//  radar/build/v1b/brief.md §2；sim_v1b.py 一個函式一個函式對照，↔ 後面是 sim 的名字）
// • 目標掛 GradeTitle.id（使用者自己的職等）；App 不自動寫目標（更新後兩台各寫一份會互蓋）：只有使用者按〔用建議值〕、Stepper 才寫。
// • 一格的目標：那一格 → 那個系統 → 這一區每項（人格特質沒有「系統」那一層，照樣查得到）。同一層兩筆（兩台各訂一次）取後改的。
// • 目標存「設目標當時的範圍」；改範圍後照比例換算顯示（≈5.5），使用者選了才換成新範圍的整數。原始分數一個字都不動。
// • 職等沒設：不畫目標，一行〔設定職等〕；職等被刪（人身上還是舊 id）：顯示快照字、不套用。
// • 每一分的說明：項目自己的（levelDetails）蓋過等級表的；跟名字一樣只在 ≤ 11 級、範圍跟等級表一樣時才有（§13）。
// • 沒有新的同步鍵、Competency.swift 一行都沒動。通知、小工具、手錶、鎖定畫面一個字都不碰。

/// 職等（照職等表順序：職等字數字感知排序，跟 GradeTitleView 一樣；同字再照職稱、代號）
struct CompetencyGradeRef: Equatable, Identifiable {
    let id: UUID
    /// 「E2」（職等字空的時候＝label）
    let short: String
    /// 「E2 工程師」
    let label: String
    /// 職等字（比對 E2／E3 用；沒有空字串）
    let grade: String
}

/// 一位同仁的職等（目標用）
struct CompetencyGradeContext: Equatable {
    /// 職等表（照順序）
    let grades: [CompetencyGradeRef]
    /// 這位現在的職等（nil＝沒設；可能是已經刪掉的 id——刪職等時 id 照舊留在人身上）
    let currentId: UUID?

    static let empty = CompetencyGradeContext(grades: [], currentId: nil)
}

/// 摘要卡「疊：目標」的選單（這台記住：@AppStorage("competency.targetMode")）
enum CompetencyTargetMode: String, Equatable {
    /// 目前職等
    case current
    /// 下一個職等（升等前看差距）
    case next
    /// 不疊
    case off
}

/// 目標的一層（職等 × 區 × 組 × 項目）：組、項目都 nil＝這一區每項；只有組＝那個系統每項；都有＝那一格
struct CompetencyTargetKey: Hashable {
    let gradeId: UUID
    /// "trait"／"skill"
    let scope: String
    let groupId: UUID?
    let itemId: UUID?
}

/// 一格查到的目標
struct CompetencyResolvedTarget: Equatable {
    let target: CompetencyTarget
    /// 目標分（照設目標當時的範圍）
    let level: Int
    /// 設目標當時的範圍
    let range: CompetencyRange
    /// "cell"／"group"／"area"
    let layer: String

    var ratio: Double { CompetencyMath.ratio(level, range) }
}

/// 一張卡要疊的目標（chartModel 用）
struct CompetencyChartTargets: Equatable {
    let grade: CompetencyGradeRef
    let table: [CompetencyTargetKey: CompetencyTarget]
}

/// 差距清單一列（由大到小）
struct CompetencyGapRow: Equatable, Identifiable {
    /// 「組 id|項目 id」
    let id: String
    let groupId: UUID
    let itemId: UUID
    /// 「Chemical System・緊急應變」
    let title: String
    /// 「2 → 3（差 1）」
    let detail: String
    /// 差幾級（現在範圍）
    let gap: Double
}

/// 〔職能〕分頁的職等目標（摘要卡、差距清單）
struct CompetencyTargetSummary: Equatable {
    let mode: CompetencyTargetMode
    /// 這次對照的職等（沒有職等、職等被刪 nil）
    let grade: CompetencyGradeRef?
    /// 疊的膠囊「目標 E2」（沒有職等、職等被刪 nil：膠囊不出現）
    let chipTitle: String?
    /// 選單兩項「目前職等 E2」「下一個職等 E3」（沒有下一個 nil）
    let currentOptionTitle: String?
    let nextOptionTitle: String?
    /// 「E2 達標 10／12」（不疊、這個職等沒訂目標 nil）
    let achievedText: String?
    /// 「離 E3 還差 7 格（差 8 級）」「E2 全部達標」
    let gapCountText: String?
    /// 「未評 2 格」
    let unratedText: String?
    /// 差距清單（由大到小；沒評的不列）
    let gapRows: [CompetencyGapRow]
    /// 沒設職等：「設定職等後才有目標」（畫面配〔設定職等〕）
    let noGradeLine: String?
    /// 職等被刪：「職等「E2 工程師」已經刪掉，目標不套用」
    let deletedGradeLine: String?
    /// 這個職等還沒訂目標：「E3 還沒訂目標（設定 → 職能項目 → 職等目標）」
    let noTargetLine: String?
}

/// 評分畫面一格的目標（換到這一張的範圍）
struct CompetencyTargetMark: Equatable {
    /// 最接近的那一級（按鈕下面標小三角形用）
    let level: Int
    /// 換到這一張範圍的目標（可能是小數）
    let value: Double
    let ratio: Double
    /// 「E2」
    let gradeShort: String
    /// 「E2 目標 3」
    let text: String
}

/// 〔用建議值〕一個職等（照範圍換算：1–5 的 E2＝3、E3＝4）
struct CompetencySuggestedTarget: Equatable, Identifiable {
    /// 職等 id
    let id: UUID
    let label: String
    let short: String
    let traitLevel: Int
    let skillLevel: Int
}

/// 設定「職等目標」一節的一列
struct CompetencyGradeTargetRow: Equatable, Identifiable {
    /// 職等 id
    let id: UUID
    /// 「E2 工程師」；已刪除「E2 工程師（已刪除）」
    let title: String
    /// 「人格 3｜本職 3」「人格 3｜本職 3・另外 1 項不同」「還沒訂目標」
    let summary: String
    /// 職等表裡已經沒有（只顯示、不套用；可以〔刪掉這組目標〕）
    let deleted: Bool
    let hasTargets: Bool
}

/// 職等目標編輯頁的一列
struct CompetencyTargetEditRow: Equatable, Identifiable {
    /// 「scope|組|項目」
    let id: String
    let scope: String
    let groupId: UUID?
    let itemId: UUID?
    /// 「每項」「Gas System 每項」「緊急應變」
    let title: String
    /// 這一層自己訂的（換到現在範圍、四捨五入；nil＝跟上一層）
    let ownLevel: Int?
    /// 現在套用的「3」「≈5.5」「—」（沒有任何一層 —）
    let effectiveText: String
    /// 跟上一層不同（藍字）
    let overridden: Bool
    /// Stepper 從哪裡開始（現在套用的那一級；都沒有＝範圍中間）
    let startLevel: Int
    /// 現在的範圍
    let range: CompetencyRange
    /// 0＝這一區、1＝系統、2＝項目
    let depth: Int
}

/// 職等目標編輯頁的一節
struct CompetencyTargetEditSection: Equatable, Identifiable {
    /// "trait"／"skill"／系統 id
    let id: String
    let title: String
    let rows: [CompetencyTargetEditRow]
}

/// 改範圍時「目標要一起換嗎」的一個選項
struct CompetencyRetargetChoice: Equatable, Identifiable {
    /// "up"／"down"／"exact"／"keep"
    let id: String
    /// 「改，目標換成 6、8（進位）」
    let title: String
    /// 目標 id → 新範圍的整數（keep 空）
    let levels: [UUID: Int]
}

/// 改範圍時有目標才有
struct CompetencyRetargetPlan: Equatable {
    /// 「目標：E2 3 → ≈5.5、E3 4 → ≈7.8」
    let message: String
    let choices: [CompetencyRetargetChoice]
}

/// 點一格的小折線一點
struct CompetencyTrendPoint: Equatable, Identifiable {
    /// 評分 id
    let id: UUID
    let dayKey: String
    /// 日子的整數（橫軸）
    let x: Double
    /// 換到現在範圍的分數（縱軸）
    let y: Double
    /// 那一張的範圍跟現在一樣（實心）；不一樣＝換算過（空心）
    let sameRange: Bool
}

/// 點一格的小折線（三次以上才有；只在 App 裡）
struct CompetencyTrendModel: Equatable {
    /// 舊的在前
    let points: [CompetencyTrendPoint]
    let low: Double
    let high: Double
    /// 目標（換到現在範圍；沒有 nil）
    let targetY: Double?
    /// 「4/30」「11/30」
    let firstDayText: String
    let lastDayText: String
    /// 有換算過的點：圖下一行「空心＝舊範圍換算」
    let hasConverted: Bool
    /// 「走勢：4/30 2 分、10/30 4 分、11/30 5 分」
    let accessibilityText: String
}

/// 重名偵測（兩台各自加的同名系統或同名項目；judge §4.4）
struct CompetencyDuplicate: Equatable, Identifiable {
    /// 「system|gas system」「shared|sop」「own|<系統 id>|研磨液濃度」
    let id: String
    /// "system"／"trait"／"shared"／"own"
    let kind: String
    /// own：哪個系統
    let groupId: UUID?
    let name: String
    /// 留下的（建得最早的；一樣早照代號）：兩台各按〔合併〕留的是同一個
    let keeperId: UUID
    let otherIds: [UUID]
    /// 「有兩個 Gas System」
    let text: String
    /// 「合併兩個「Gas System」？」
    let confirmTitle: String
    let confirmMessage: String
}

extension CompetencyMath {

    // MARK: 日子 → Date（DatePicker 用；v1a-2 兩個檔各一份的 compRatingDate／compHistNoonDate 搬來這裡）

    /// ↔ noon_date：「2026-10-30」→ 那一天中午 12 點（避開日光節約換日；這台的時區）
    static func noonDate(_ key: String, calendar: Calendar = .current) -> Date? {
        guard let p = parseDay(key) else { return nil }
        var c = DateComponents()
        c.year = p.y
        c.month = p.m
        c.day = p.d
        c.hour = 12
        return calendar.date(from: c)
    }

    // MARK: 指定日期（評分紀錄明細〔跟現在比〕）

    /// ↔ cur_through：那一天（含）之前每一格最後一筆
    static func latestCells(_ sessions: [CompetencySession], through day: String) -> [CompetencyCellKey: CompetencyCellValue] {
        latestCells(sessions.filter { $0.dayKey <= day })
    }

    /// ↔ compare_cards：現在的卡片、灰虛線＝那一天的樣子（「10/30 比 4/30」、圖例「┅ 4/30」）
    static func compareCards(setup: CompetencySetupBook, subordinateId: UUID, archivedPerson: Bool,
                             sessions: [CompetencySession], compareDay: String) -> [CompetencyChartModel] {
        let groups: [CompetencyGroup] = visibleGroups(setup: setup, subordinateId: subordinateId,
                                                      archivedPerson: archivedPerson, sessions: sessions)
        var out: [CompetencyChartModel] = []
        for g in groups {
            let ax = cardAxes(group: g, setup: setup, archivedPerson: archivedPerson, sessions: sessions)
            out.append(chartModel(group: g, axes: ax.axes, archivedIds: ax.archived, sessions: sessions,
                                  range: setup.range(forGroup: g.id), scale: setup.scaleFor(group: g.id),
                                  compareDay: compareDay))
        }
        return out
    }

    // MARK: 職等

    static let traitScope: String = "trait"
    static let skillScope: String = "skill"
    /// 〔用建議值〕：E2＝範圍中間（1–5 的 3）、E3＝四分之三（1–5 的 4）
    static let suggestE2Ratio: Double = 0.5
    static let suggestE3Ratio: Double = 0.75

    /// ↔ norm_grade：去空白、全形英數換半形、大寫（「ｅ２」→「E2」）
    static func normalizedGrade(_ s: String) -> String {
        var out = ""
        for u in s.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars {
            if u.value >= 0xFF01 && u.value <= 0xFF5E, let h = Unicode.Scalar(u.value - 0xFEE0) {
                out.unicodeScalars.append(h)
            } else {
                out.unicodeScalars.append(u)
            }
        }
        return out.uppercased()
    }

    /// ↔ grade_refs：職等表順序（職等字數字感知排序，跟 GradeTitleView 一樣）
    static func gradeRefs(_ titles: [GradeTitle]) -> [CompetencyGradeRef] {
        let sorted: [GradeTitle] = titles.sorted { a, b in
            let c: ComparisonResult = a.grade.localizedStandardCompare(b.grade)
            if c != .orderedSame { return c == .orderedAscending }
            let d: ComparisonResult = a.title.localizedStandardCompare(b.title)
            if d != .orderedSame { return d == .orderedAscending }
            return a.id.uuidString < b.id.uuidString
        }
        return sorted.map { g in
            let grade: String = g.grade.trimmingCharacters(in: .whitespacesAndNewlines)
            let raw: String = g.displayLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            let label: String = raw.isEmpty ? "未命名職等" : raw
            return CompetencyGradeRef(id: g.id, short: grade.isEmpty ? label : grade, label: label, grade: grade)
        }
    }

    /// ↔ target_grade：這次對照哪個職等（不疊、沒設、被刪 nil；下一個沒有時用目前的）
    static func targetGrade(_ ctx: CompetencyGradeContext, mode: CompetencyTargetMode,
                            table: [CompetencyTargetKey: CompetencyTarget]) -> CompetencyGradeRef? {
        guard mode != .off, let cid = ctx.currentId,
              let i = ctx.grades.firstIndex(where: { $0.id == cid }) else { return nil }
        var pick: CompetencyGradeRef = ctx.grades[i]
        if mode == .next && i + 1 < ctx.grades.count { pick = ctx.grades[i + 1] }
        let has: Bool = table.keys.contains { $0.gradeId == pick.id }
        return has ? pick : nil
    }

    /// ↔ deleted_grade_label：職等表裡已經沒有的那個職等叫什麼（目標的快照、評分的快照；都沒有「這個職等」）
    static func deletedGradeLabel(_ id: UUID, setup: CompetencySetupBook, sessions: [CompetencySession]) -> String {
        for t in setup.allTargets where t.gradeTitleId == id {
            let s: String = (t.gradeLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
        }
        let byDay: [CompetencySession] = sessions.sorted { a, b in a.dayKey > b.dayKey }
        for s in byDay where s.gradeTitleId == id {
            let l: String = (s.gradeLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !l.isEmpty { return l }
        }
        return "這個職等"
    }

    // MARK: 目標表（judge §3.6：那一格 → 那個系統 → 這一區每項）

    /// ↔ scope_of
    static func targetScope(groupId: UUID?) -> String {
        groupId == CompetencySetupBook.traitGroupId ? traitScope : skillScope
    }

    /// ↔ target_key：沒有職等的不算；有組的照組判斷人格／本職；沒有組的照 scope（不是 "trait" 都當本職）
    static func targetKey(_ t: CompetencyTarget) -> CompetencyTargetKey? {
        guard let g = t.gradeTitleId else { return nil }
        let scope: String
        if let gid = t.groupId {
            scope = targetScope(groupId: gid)
        } else {
            scope = t.scope == traitScope ? traitScope : skillScope
        }
        let itemId: UUID? = t.groupId == nil ? nil : t.itemId
        return CompetencyTargetKey(gradeId: g, scope: scope, groupId: t.groupId, itemId: itemId)
    }

    /// ↔ target_table：沒刪、有目標分的；同一層兩筆（兩台各訂一次）取後改的，一樣新照代號大的
    static func targetTable(_ setup: CompetencySetupBook) -> [CompetencyTargetKey: CompetencyTarget] {
        var out: [CompetencyTargetKey: CompetencyTarget] = [:]
        for t in setup.allTargets where t.deletedAt == nil && t.level != nil {
            guard let k = targetKey(t) else { continue }
            if let old = out[k] {
                if old.stamp > t.stamp { continue }
                if old.stamp == t.stamp && old.id.uuidString > t.id.uuidString { continue }
            }
            out[k] = t
        }
        return out
    }

    /// ↔ target_range：設目標當時的範圍（沒存、壞掉＝fallback）
    static func targetRange(_ t: CompetencyTarget, fallback: CompetencyRange) -> CompetencyRange {
        guard let lo = t.low, let hi = t.high, CompetencyRange.isValid(low: lo, high: hi) else { return fallback }
        return CompetencyRange(low: lo, high: hi)
    }

    /// ↔ resolve_target：一格的目標（那一格 → 那個系統 → 這一區每項）
    static func resolveTarget(_ table: [CompetencyTargetKey: CompetencyTarget], gradeId: UUID, groupId: UUID,
                              itemId: UUID, fallback: CompetencyRange) -> CompetencyResolvedTarget? {
        let scope: String = targetScope(groupId: groupId)
        let cell = CompetencyTargetKey(gradeId: gradeId, scope: scope, groupId: groupId, itemId: itemId)
        let group = CompetencyTargetKey(gradeId: gradeId, scope: scope, groupId: groupId, itemId: nil)
        let area = CompetencyTargetKey(gradeId: gradeId, scope: scope, groupId: nil, itemId: nil)
        let order: [(key: CompetencyTargetKey, layer: String)] = [(cell, "cell"), (group, "group"), (area, "area")]
        for step in order {
            guard let t = table[step.key], let lv = t.level else { continue }
            let r: CompetencyRange = targetRange(t, fallback: fallback)
            return CompetencyResolvedTarget(target: t, level: r.clamp(lv), range: r, layer: step.layer)
        }
        return nil
    }

    /// ↔ target_value：目標換到現在範圍（可能是小數）
    static func targetValue(_ rt: CompetencyResolvedTarget, in range: CompetencyRange) -> Double {
        if rt.range == range { return Double(rt.level) }
        return value(atRatio: rt.ratio, range)
    }

    /// ↔ target_value_text：「3」「≈5.5」
    static func targetValueText(_ rt: CompetencyResolvedTarget, in range: CompetencyRange) -> String {
        if rt.range == range { return "\(rt.level)" }
        return numberText(targetValue(rt, in: range))
    }

    /// ↔ apply_target：一軸的目標字（達標 ✓、差幾級、沒評；不適用只畫點線不寫字、不算）
    static func applyTarget(_ m: inout CompetencyAxisModel, _ rt: CompetencyResolvedTarget, cell c: CompetencyCellValue?,
                            range: CompetencyRange) {
        let tt: Double = rt.ratio
        let tText: String = targetValueText(rt, in: range)
        m.targetT = tt
        m.targetValueText = tText
        if let n = c, n.na { return }
        guard let cell = c, let tc = cell.ratio else {
            m.targetMet = false
            m.targetText = "目標 " + tText + "・未評"
            return
        }
        if tc >= tt - 1e-9 {
            m.targetMet = true
            m.targetGap = 0
            m.targetText = "目標 " + tText + " ✓"
        } else {
            let gap: Double = (tt - tc) * Double(range.high - range.low)
            m.targetMet = false
            m.targetGap = gap
            m.targetText = "目標 " + tText + "・差 " + numberText(gap)
        }
    }

    // MARK: 〔職能〕分頁的目標摘要（judge §3.8 達標、差距由大到小；§5 職等沒設／升等／被刪）

    /// ↔ target_summary：整個設定一個目標都沒有 → nil（什麼都不出現）
    static func targetSummary(cards: [CompetencyChartModel], table: [CompetencyTargetKey: CompetencyTarget],
                              grades: CompetencyGradeContext, mode: CompetencyTargetMode, pick: CompetencyGradeRef?,
                              setup: CompetencySetupBook, sessions: [CompetencySession]) -> CompetencyTargetSummary? {
        guard !table.isEmpty else { return nil }
        guard let cid = grades.currentId else {
            return CompetencyTargetSummary(mode: mode, grade: nil, chipTitle: nil, currentOptionTitle: nil,
                                           nextOptionTitle: nil, achievedText: nil, gapCountText: nil, unratedText: nil,
                                           gapRows: [], noGradeLine: "設定職等後才有目標", deletedGradeLine: nil,
                                           noTargetLine: nil)
        }
        guard let i = grades.grades.firstIndex(where: { $0.id == cid }) else {
            let label: String = deletedGradeLabel(cid, setup: setup, sessions: sessions)
            return CompetencyTargetSummary(mode: mode, grade: nil, chipTitle: nil, currentOptionTitle: nil,
                                           nextOptionTitle: nil, achievedText: nil, gapCountText: nil, unratedText: nil,
                                           gapRows: [],
                                           noGradeLine: nil,
                                           deletedGradeLine: "職等「" + label + "」已經刪掉，目標不套用",
                                           noTargetLine: nil)
        }
        let cur: CompetencyGradeRef = grades.grades[i]
        let next: CompetencyGradeRef? = i + 1 < grades.grades.count ? grades.grades[i + 1] : nil
        let wanted: CompetencyGradeRef = (mode == .next ? next : nil) ?? cur
        let curTitle: String = "目前職等 " + cur.short
        let nextTitle: String? = next.map { "下一個職等 " + $0.short }
        let chip: String = "目標 " + wanted.short
        guard mode != .off else {
            return CompetencyTargetSummary(mode: mode, grade: wanted, chipTitle: chip, currentOptionTitle: curTitle,
                                           nextOptionTitle: nextTitle, achievedText: nil, gapCountText: nil,
                                           unratedText: nil, gapRows: [], noGradeLine: nil, deletedGradeLine: nil,
                                           noTargetLine: nil)
        }
        guard let g = pick else {
            return CompetencyTargetSummary(mode: mode, grade: wanted, chipTitle: chip, currentOptionTitle: curTitle,
                                           nextOptionTitle: nextTitle, achievedText: nil, gapCountText: nil,
                                           unratedText: nil, gapRows: [], noGradeLine: nil, deletedGradeLine: nil,
                                           noTargetLine: wanted.short + " 還沒訂目標（設定 → 職能項目 → 職等目標）")
        }
        var total = 0
        var achieved = 0
        var unrated = 0
        var levels: Double = 0
        var rows: [(row: CompetencyGapRow, order: Int)] = []
        var order = 0
        for card in cards {
            for ax in card.axes {
                order += 1
                guard ax.targetT != nil, ax.state != .na, !ax.archived else { continue }
                total += 1
                if ax.targetMet == true { achieved += 1 }
                if ax.state == .unrated { unrated += 1 }
                guard let gap = ax.targetGap, gap > 1e-9 else { continue }
                levels += gap
                let detail: String = (ax.valueText ?? "") + " → " + (ax.targetValueText ?? "") + "（差 " + numberText(gap) + "）"
                let row = CompetencyGapRow(id: card.id.uuidString + "|" + ax.id.uuidString, groupId: card.id, itemId: ax.id,
                                           title: card.title + "・" + ax.name, detail: detail, gap: gap)
                rows.append((row, order))
            }
        }
        let sortedRows: [CompetencyGapRow] = rows.sorted { a, b in
            if abs(a.row.gap - b.row.gap) > 1e-9 { return a.row.gap > b.row.gap }
            return a.order < b.order
        }.map { $0.row }
        let notMet: Int = total - achieved
        var gapText: String = g.short + " 全部達標"
        if notMet > 0 {
            gapText = "離 " + g.short + " 還差 \(notMet) 格"
            if levels > 1e-9 { gapText += "（差 " + numberText(levels) + " 級）" }
        }
        return CompetencyTargetSummary(mode: mode, grade: g, chipTitle: chip, currentOptionTitle: curTitle,
                                       nextOptionTitle: nextTitle,
                                       achievedText: total > 0 ? g.short + " 達標 \(achieved)／\(total)" : nil,
                                       gapCountText: total > 0 ? gapText : nil,
                                       unratedText: unrated > 0 ? "未評 \(unrated) 格" : nil,
                                       gapRows: sortedRows, noGradeLine: nil, deletedGradeLine: nil, noTargetLine: nil)
    }

    /// ↔ record_rows（v1b）：同 recordRows，那一張的職等跟現在不一樣時多「那時 E2 工程師」
    static func recordRows(sessions: [CompetencySession], setup: CompetencySetupBook,
                           currentGradeId: UUID?) -> [CompetencyRecordRow] {
        let base: [CompetencyRecordRow] = recordRows(sessions: sessions, setup: setup)
        var byId: [UUID: CompetencySession] = [:]
        for s in sessions { byId[s.id] = s }
        return base.map { (row: CompetencyRecordRow) -> CompetencyRecordRow in
            var r = row
            guard let first = row.sessionIds.first, let s = byId[first], let gid = s.gradeTitleId,
                  gid != currentGradeId else { return r }
            let label: String = (s.gradeLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty { r.gradeNote = "那時 " + label }
            return r
        }
    }

    // MARK: 評分畫面的目標（judge §4.5「E2 目標 3」、底部「E2 達標 10／12」）

    /// ↔ rating_marks：每一格的目標，換到這一張的範圍（沒有職等、沒有目標回空）
    static func ratingTargetMarks(setup: CompetencySetupBook, grade: CompetencyGradeRef?,
                                  sections: [CompetencyRatingSection]) -> [CompetencyCellKey: CompetencyTargetMark] {
        guard let g = grade else { return [:] }
        let table: [CompetencyTargetKey: CompetencyTarget] = targetTable(setup)
        guard !table.isEmpty else { return [:] }
        var out: [CompetencyCellKey: CompetencyTargetMark] = [:]
        for sec in sections {
            for ax in sec.axes where !ax.archived {
                guard let rt = resolveTarget(table, gradeId: g.id, groupId: sec.id, itemId: ax.id,
                                             fallback: sec.range) else { continue }
                let v: Double = targetValue(rt, in: sec.range)
                let lv: Int = sec.range.clamp(roundHalfUp(v))
                let text: String = g.short + " 目標 " + numberText(v)
                out[CompetencyCellKey(groupId: sec.id, itemId: ax.id)] =
                    CompetencyTargetMark(level: lv, value: v, ratio: rt.ratio, gradeShort: g.short, text: text)
            }
        }
        return out
    }

    /// ↔ rating_mark_text：那一格下面「E2 目標 3 ✓」「E2 目標 3・差 1」「E2 目標 3」（沒評、不適用）
    static func ratingTargetRowText(_ m: CompetencyTargetMark, value: Int?, na: Bool, range: CompetencyRange) -> String {
        guard !na, let v = value else { return m.text }
        let t: Double = ratio(v, range)
        if t >= m.ratio - 1e-9 { return m.text + " ✓" }
        return m.text + "・差 " + numberText(m.value - Double(v))
    }

    /// ↔ rating_target_line：底部「E2 達標 10／12」：草稿有的格子照草稿、沒動的照上一次；不適用不算；
    /// 都沒有的算「未評」（「・未評 2 格」）。沒有目標 nil
    static func ratingTargetLine(marks: [CompetencyCellKey: CompetencyTargetMark], sections: [CompetencyRatingSection],
                                 draft: [CompetencyCellKey: CompetencyDraftCell]) -> String? {
        var total = 0
        var met = 0
        var unrated = 0
        var short = ""
        for sec in sections {
            for ax in sec.axes {
                let key = CompetencyCellKey(groupId: sec.id, itemId: ax.id)
                guard let m = marks[key] else { continue }
                short = m.gradeShort
                if let d = draft[key], d.isSet {
                    if d.na { continue }
                    total += 1
                    if let v = d.value, ratio(v, sec.range) >= m.ratio - 1e-9 { met += 1 }
                } else if let p = ax.previous {
                    if p.na { continue }
                    total += 1
                    if let tp = p.ratio, tp >= m.ratio - 1e-9 { met += 1 }
                } else {
                    total += 1
                    unrated += 1
                }
            }
        }
        guard total > 0 else { return nil }
        var s: String = short + " 達標 \(met)／\(total)"
        if unrated > 0 { s += "・未評 \(unrated) 格" }
        return s
    }

    // MARK: 〔用建議值〕（主控定案：E2＝範圍中間、E3＝四分之三；職等字對不到 E2／E3 時照職等表順序給第 2、3 個）

    /// ↔ suggest_level：low＋四捨五入(t×(high−low))（1–5：3、4；1–10：6、8；0–100：50、75）
    static func suggestLevel(_ t: Double, _ r: CompetencyRange) -> Int {
        r.clamp(r.low + roundHalfUp(t * Double(r.high - r.low)))
    }

    /// ↔ suggested：職等字＝E2／E3（去空白、全形換半形、不分大小寫）的才給；一個都對不到 → 職等表第 2 個給 E2 的值、第 3 個給 E3 的值
    ///（只有 1 個職等：那一個給 E2 的值）
    static func suggestedTargets(grades: [CompetencyGradeRef], traitRange: CompetencyRange,
                                 skillRange: CompetencyRange) -> [CompetencySuggestedTarget] {
        var picks: [(ref: CompetencyGradeRef, t: Double)] = []
        for g in grades {
            let n: String = normalizedGrade(g.grade)
            if n == "E2" { picks.append((g, suggestE2Ratio)) }
            if n == "E3" { picks.append((g, suggestE3Ratio)) }
        }
        if picks.isEmpty {
            if grades.count == 1 {
                picks.append((grades[0], suggestE2Ratio))
            } else {
                if grades.count >= 2 { picks.append((grades[1], suggestE2Ratio)) }
                if grades.count >= 3 { picks.append((grades[2], suggestE3Ratio)) }
            }
        }
        return picks.map { p in
            CompetencySuggestedTarget(id: p.ref.id, label: p.ref.label, short: p.ref.short,
                                      traitLevel: suggestLevel(p.t, traitRange), skillLevel: suggestLevel(p.t, skillRange))
        }
    }

    /// ↔ suggestion_text：「E2 每項 3、E3 每項 4」（人格、本職範圍不一樣：「E2 人格 3｜本職 6」）
    static func suggestionText(_ list: [CompetencySuggestedTarget]) -> String {
        let parts: [String] = list.map { s in
            s.traitLevel == s.skillLevel ? s.short + " 每項 \(s.traitLevel)"
                : s.short + " 人格 \(s.traitLevel)｜本職 \(s.skillLevel)"
        }
        return parts.joined(separator: "、")
    }

    /// ↔ suggest_offer：〔用建議值〕要不要出現：有職等、有建議、現在的職等一個目標都還沒訂
    static func shouldOfferSuggestion(setup: CompetencySetupBook, grades: [CompetencyGradeRef]) -> Bool {
        guard !grades.isEmpty else { return false }
        let live: Set<UUID> = Set(grades.map { $0.id })
        let table: [CompetencyTargetKey: CompetencyTarget] = targetTable(setup)
        if table.keys.contains(where: { live.contains($0.gradeId) }) { return false }
        return !suggestedTargets(grades: grades, traitRange: setup.traitRange, skillRange: setup.skillRange).isEmpty
    }

    // MARK: 設定「職等目標」一節（judge §4.4：「E2　人格 3｜本職 3 ›」）

    /// ↔ grade_target_rows：職等表每一個＋（目標還在、職等表裡已經沒有的）已刪除的
    static func gradeTargetRows(setup: CompetencySetupBook, grades: [CompetencyGradeRef]) -> [CompetencyGradeTargetRow] {
        let table: [CompetencyTargetKey: CompetencyTarget] = targetTable(setup)
        var out: [CompetencyGradeTargetRow] = []
        for g in grades {
            out.append(gradeTargetRow(id: g.id, title: g.label, deleted: false, table: table, setup: setup))
        }
        let live: Set<UUID> = Set(grades.map { $0.id })
        var seen: [UUID] = []
        for k in table.keys where !live.contains(k.gradeId) && !seen.contains(k.gradeId) {
            seen.append(k.gradeId)
        }
        let ordered: [UUID] = seen.sorted { $0.uuidString < $1.uuidString }
        for gid in ordered {
            let label: String = deletedGradeLabel(gid, setup: setup, sessions: [])
            out.append(gradeTargetRow(id: gid, title: label + "（已刪除）", deleted: true, table: table, setup: setup))
        }
        return out
    }

    /// 一列的字
    static func gradeTargetRow(id: UUID, title: String, deleted: Bool, table: [CompetencyTargetKey: CompetencyTarget],
                               setup: CompetencySetupBook) -> CompetencyGradeTargetRow {
        let mine: [CompetencyTargetKey] = table.keys.filter { $0.gradeId == id }
        guard !mine.isEmpty else {
            return CompetencyGradeTargetRow(id: id, title: title, summary: "還沒訂目標", deleted: deleted, hasTargets: false)
        }
        let tKey = CompetencyTargetKey(gradeId: id, scope: traitScope, groupId: nil, itemId: nil)
        let sKey = CompetencyTargetKey(gradeId: id, scope: skillScope, groupId: nil, itemId: nil)
        let tText: String = areaText(table[tKey], range: setup.traitRange)
        let sText: String = areaText(table[sKey], range: setup.skillRange)
        var summary: String = "人格 " + tText + "｜本職 " + sText
        let others: Int = mine.filter { $0.groupId != nil }.count
        if others > 0 { summary += "・另外 \(others) 項不同" }
        return CompetencyGradeTargetRow(id: id, title: title, summary: summary, deleted: deleted, hasTargets: true)
    }

    /// 「3」「≈5.5」「—」
    static func areaText(_ t: CompetencyTarget?, range: CompetencyRange) -> String {
        guard let x = t, let lv = x.level else { return "—" }
        let r: CompetencyRange = targetRange(x, fallback: range)
        let rt = CompetencyResolvedTarget(target: x, level: r.clamp(lv), range: r, layer: "area")
        return targetValueText(rt, in: range)
    }

    // MARK: 職等目標編輯頁（整區兩個 Stepper＋〔逐項調整〕：系統、每一格；跟上一層不同的標藍字）

    /// ↔ target_editor
    static func targetEditor(setup: CompetencySetupBook, gradeId: UUID) -> [CompetencyTargetEditSection] {
        let table: [CompetencyTargetKey: CompetencyTarget] = targetTable(setup)
        var out: [CompetencyTargetEditSection] = []
        let tr: CompetencyRange = setup.traitRange
        let sr: CompetencyRange = setup.skillRange
        // 人格特質：這一區每項＋每一項
        var traitRows: [CompetencyTargetEditRow] = []
        let tArea: CompetencyTarget? = table[CompetencyTargetKey(gradeId: gradeId, scope: traitScope, groupId: nil, itemId: nil)]
        traitRows.append(editRow(scope: traitScope, groupId: nil, itemId: nil, title: "每項", own: tArea,
                                 inherited: nil, range: tr, depth: 0))
        if setup.traitGroup != nil {
            let tg: UUID = CompetencySetupBook.traitGroupId
            let tGroup: CompetencyTarget? = table[CompetencyTargetKey(gradeId: gradeId, scope: traitScope, groupId: tg, itemId: nil)]
            let tParent: CompetencyTarget? = tGroup ?? tArea
            for it in setup.traitItems {
                let own: CompetencyTarget? = table[CompetencyTargetKey(gradeId: gradeId, scope: traitScope, groupId: tg, itemId: it.id)]
                traitRows.append(editRow(scope: traitScope, groupId: tg, itemId: it.id, title: it.displayName, own: own,
                                         inherited: tParent, range: tr, depth: 2))
            }
        }
        out.append(CompetencyTargetEditSection(id: traitScope, title: "人格特質", rows: traitRows))
        // 本職學能：這一區每項
        let sArea: CompetencyTarget? = table[CompetencyTargetKey(gradeId: gradeId, scope: skillScope, groupId: nil, itemId: nil)]
        out.append(CompetencyTargetEditSection(id: skillScope, title: "本職學能",
                                               rows: [editRow(scope: skillScope, groupId: nil, itemId: nil, title: "每項",
                                                              own: sArea, inherited: nil, range: sr, depth: 0)]))
        // 每個系統：這個系統每項＋每一格
        for g in setup.activeSystems {
            var rows: [CompetencyTargetEditRow] = []
            let gOwn: CompetencyTarget? = table[CompetencyTargetKey(gradeId: gradeId, scope: skillScope, groupId: g.id, itemId: nil)]
            rows.append(editRow(scope: skillScope, groupId: g.id, itemId: nil, title: g.displayName + " 每項", own: gOwn,
                                inherited: sArea, range: sr, depth: 1))
            let parent: CompetencyTarget? = gOwn ?? sArea
            for it in setup.axes(for: g.id) {
                let own: CompetencyTarget? = table[CompetencyTargetKey(gradeId: gradeId, scope: skillScope, groupId: g.id, itemId: it.id)]
                rows.append(editRow(scope: skillScope, groupId: g.id, itemId: it.id, title: it.displayName, own: own,
                                    inherited: parent, range: sr, depth: 2))
            }
            out.append(CompetencyTargetEditSection(id: g.id.uuidString, title: g.displayName, rows: rows))
        }
        return out
    }

    /// 編輯頁一列
    static func editRow(scope: String, groupId: UUID?, itemId: UUID?, title: String, own: CompetencyTarget?,
                        inherited: CompetencyTarget?, range: CompetencyRange, depth: Int) -> CompetencyTargetEditRow {
        let effective: CompetencyTarget? = own ?? inherited
        let effText: String = areaText(effective, range: range)
        var ownLevel: Int? = nil
        if let o = own, let lv = o.level {
            let r: CompetencyRange = targetRange(o, fallback: range)
            ownLevel = range.clamp(roundHalfUp(convert(r.clamp(lv), from: r, to: range)))
        }
        var start: Int = sliderPlaceholder(range)
        if let e = effective, let lv = e.level {
            let r: CompetencyRange = targetRange(e, fallback: range)
            start = range.clamp(roundHalfUp(convert(r.clamp(lv), from: r, to: range)))
        }
        let gPart: String = groupId?.uuidString ?? "-"
        let iPart: String = itemId?.uuidString ?? "-"
        let overridden: Bool = own != nil && depth > 0 && areaText(own, range: range) != areaText(inherited, range: range)
        return CompetencyTargetEditRow(id: scope + "|" + gPart + "|" + iPart, scope: scope, groupId: groupId, itemId: itemId,
                                       title: title, ownLevel: ownLevel, effectiveText: effText, overridden: overridden,
                                       startLevel: start, range: range, depth: depth)
    }

    /// ↔ set_target：寫一層（level nil＝拿掉這一層、跟上一層）。同一層的其他筆（兩台各訂一次）蓋墓碑。範圍＝現在的
    static func settingTarget(_ book: CompetencySetupBook, gradeId: UUID, gradeLabel: String?, scope: String,
                              groupId: UUID?, itemId: UUID?, level: Int?, newId: UUID, now: Date) -> CompetencySetupBook {
        var b = book
        let key = CompetencyTargetKey(gradeId: gradeId, scope: scope, groupId: groupId, itemId: groupId == nil ? nil : itemId)
        let r: CompetencyRange = scope == traitScope ? b.traitRange : b.skillRange
        let table: [CompetencyTargetKey: CompetencyTarget] = targetTable(b)
        let keepId: UUID? = level == nil ? nil : table[key]?.id
        var list: [CompetencyTarget] = b.allTargets
        var changed = false
        for i in list.indices where list[i].deletedAt == nil && targetKey(list[i]) == key && list[i].id != keepId {
            list[i].deletedAt = now
            list[i].updatedAt = now
            changed = true
        }
        if let lv = level {
            let v: Int = r.clamp(lv)
            if let kid = keepId, let i = list.firstIndex(where: { $0.id == kid }) {
                if list[i].level != v || list[i].low != r.low || list[i].high != r.high || list[i].gradeLabel != gradeLabel {
                    list[i].level = v
                    list[i].low = r.low
                    list[i].high = r.high
                    if gradeLabel != nil { list[i].gradeLabel = gradeLabel }
                    list[i].updatedAt = now
                    changed = true
                }
            } else {
                list.append(CompetencyTarget(id: newId, gradeTitleId: gradeId, gradeLabel: gradeLabel, scope: scope,
                                             groupId: groupId, itemId: groupId == nil ? nil : itemId, level: v,
                                             low: r.low, high: r.high, updatedAt: now))
                changed = true
            }
        }
        if changed { b.targets = list }
        return b
    }

    // MARK: 改範圍時目標要不要一起換（judge §3.3：「3 會變 5.5，要 5 還是 6？」；只有目標可以重存整數，分數不行）

    /// ↔ retarget_plan：這一區有目標、而且設目標時的範圍跟新範圍不一樣才有。choices：換算剛好是整數「改，目標一起換成 1–10」；
    /// 不是整數「改，目標換成 6、8（進位）」「改，目標換成 5、7（捨去）」；最後都有「改，目標照比例畫」
    static func retargetPlan(setup: CompetencySetupBook, scaleId: String, to new: CompetencyRange,
                             grades: [CompetencyGradeRef]) -> CompetencyRetargetPlan? {
        let scope: String = scaleId == CompetencySetupBook.traitScaleId ? traitScope : skillScope
        let current: CompetencyRange = scope == traitScope ? setup.traitRange : setup.skillRange
        var ups: [UUID: Int] = [:]
        var downs: [UUID: Int] = [:]
        var lines: [String] = []
        var allWhole = true
        let live: [CompetencyTarget] = setup.allTargets.filter { t in
            t.deletedAt == nil && t.level != nil && (targetKey(t)?.scope ?? "") == scope
        }
        for t in live {
            guard let lv = t.level else { continue }
            let r: CompetencyRange = targetRange(t, fallback: current)
            if r == new { continue }
            let x: Double = convert(r.clamp(lv), from: r, to: new)
            let up: Int = new.clamp(Int((x - 1e-9).rounded(.up)))
            let down: Int = new.clamp(Int((x + 1e-9).rounded(.down)))
            ups[t.id] = up
            downs[t.id] = down
            if up != down { allWhole = false }
            let short: String = grades.first(where: { $0.id == t.gradeTitleId })?.short
                ?? (t.gradeLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let line: String = (short.isEmpty ? "" : short + " ") + "\(r.clamp(lv)) → " + numberText(x)
            if !lines.contains(line) { lines.append(line) }
        }
        guard !ups.isEmpty else { return nil }
        let shown: [String] = Array(lines.prefix(4))
        var message: String = "目標：" + shown.joined(separator: "、")
        if lines.count > 4 { message += "…" }
        var choices: [CompetencyRetargetChoice] = []
        if allWhole {
            choices.append(CompetencyRetargetChoice(id: "exact", title: "改，目標一起換成 " + new.text, levels: ups))
        } else {
            let upVals: [Int] = Array(Set(ups.values)).sorted()
            let downVals: [Int] = Array(Set(downs.values)).sorted()
            let upText: String = upVals.map { "\($0)" }.joined(separator: "、")
            let downText: String = downVals.map { "\($0)" }.joined(separator: "、")
            choices.append(CompetencyRetargetChoice(id: "up", title: "改，目標換成 " + upText + "（進位）", levels: ups))
            choices.append(CompetencyRetargetChoice(id: "down", title: "改，目標換成 " + downText + "（捨去）", levels: downs))
        }
        choices.append(CompetencyRetargetChoice(id: "keep", title: "改，目標照比例畫", levels: [:]))
        return CompetencyRetargetPlan(message: message, choices: choices)
    }

    /// ↔ apply_retarget：把選好的整數寫回目標（範圍＝新範圍）
    static func applyingRetarget(_ book: CompetencySetupBook, levels: [UUID: Int], range: CompetencyRange,
                                 now: Date) -> CompetencySetupBook {
        guard !levels.isEmpty else { return book }
        var b = book
        var list: [CompetencyTarget] = b.allTargets
        var changed = false
        for i in list.indices {
            guard list[i].deletedAt == nil, let v = levels[list[i].id] else { continue }
            list[i].level = range.clamp(v)
            list[i].low = range.low
            list[i].high = range.high
            list[i].updatedAt = now
            changed = true
        }
        if changed { b.targets = list }
        return b
    }

    // MARK: 每一分的說明（judge §2.1 levels.detail、items.levelDetails；§13：出廠空、≤ 11 級才有、範本自己選）

    /// 每一分的說明最多 30 字（評分按鈕下面一行）
    static let levelDetailMax: Int = 30

    /// ↔ level_detail：那一分的說明（項目自己的蓋過等級表的）；範圍跟等級表不一樣、超過 11 級 nil
    static func levelDetail(scale: CompetencyScale?, item: CompetencyItem?, value v: Int, range r: CompetencyRange) -> String? {
        guard namesAllowed(r), let sc = scale, sc.range == r else { return nil }
        // [v25.602 職能雷達 v2] 項目自己的說明標了別的範圍（改範圍前寫的）→ 先不用，照通用說明。要退回這一件：拿掉 `itemDetailsUsable(item, range: r),`
        if itemDetailsUsable(item, range: r), let own = item?.levelDetails?.first(where: { $0.value == v })?.detail {
            let t: String = own.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        if let gen = sc.levels?.first(where: { $0.value == v })?.detail {
            let t: String = gen.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return nil
    }

    /// ↔ level_detail_line：選中那顆下面一行「能教人：能帶新人演練、當帶訓者」；沒有名字「4 分：…」
    static func levelDetailLine(value v: Int, name: String?, detail: String) -> String {
        let n: String = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (n.isEmpty ? "\(v) 分" : n) + "：" + detail
    }

    /// ↔ current_details：說明頁打開時的草稿（這個範圍裡每一分現在的說明）
    static func currentLevelDetails(_ levels: [CompetencyLevel]?, range r: CompetencyRange) -> [Int: String] {
        var out: [Int: String] = [:]
        guard namesAllowed(r) else { return out }
        for lv in levels ?? [] {
            guard let v = lv.value, r.contains(v) else { continue }
            let t: String = (lv.detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out[v] = t }
        }
        return out
    }

    /// ↔ merged_details：把說明的草稿寫回（範圍裡的照草稿；範圍外的、名字、別台的欄位原樣留著）。全部空的回 nil
    static func mergedDetails(existing: [CompetencyLevel]?, details: [Int: String], range r: CompetencyRange) -> [CompetencyLevel]? {
        var out: [CompetencyLevel] = []
        var used: Set<Int> = []
        for lv in existing ?? [] {
            guard let v = lv.value, r.contains(v) else {
                out.append(lv)
                continue
            }
            used.insert(v)
            var x = lv
            x.detail = cleanShortName(details[v], max: levelDetailMax)
            let name: String = (x.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if x.detail == nil && name.isEmpty && x.extra == nil { continue }
            out.append(x)
        }
        for v in r.low...r.high where !used.contains(v) {
            if let d = cleanShortName(details[v], max: levelDetailMax) {
                out.append(CompetencyLevel(value: v, detail: d))
            }
        }
        out.sort { a, b in (a.value ?? Int.max) < (b.value ?? Int.max) }
        return out.isEmpty ? nil : out
    }

    /// ↔ apply_template_details：範本的說明（從最低分往上一級一句）
    static func applyTemplateDetails(_ t: CompetencyLevelTemplate, to r: CompetencyRange) -> [Int: String] {
        var out: [Int: String] = [:]
        let n: Int = min(t.details.count, r.levelCount)
        for i in 0..<n { out[r.low + i] = t.details[i] }
        return out
    }

    /// ↔ item_detail_count：項目自己的說明寫了幾分（說明頁那一列「寫了 2 分」）
    static func itemDetailCountText(_ it: CompetencyItem, range r: CompetencyRange) -> String {
        // [v25.602 職能雷達 v2] 標了別的範圍：「照 1–5 寫的，先不顯示」。要退回這一件：刪這一行
        if let old = itemDetailsOldRange(it, range: r) { return "照 " + old.text + " 寫的，先不顯示" }
        let n: Int = currentLevelDetails(it.levelDetails, range: r).count
        return n == 0 ? "照通用說明" : "寫了 \(n) 分"
    }

    // MARK: 點一格（v1b：每一分的說明、目標、小折線）

    /// ↔ cell_history（v1b）：同 v1a-2，多每一分的說明（等級表的＋項目自己的）、「E2 目標 3（差 1）」、三次以上的小折線
    static func cellHistory(groupId: UUID, itemId: UUID, setup: CompetencySetupBook, subordinateId: UUID,
                            sessions: [CompetencySession], grade: CompetencyGradeRef?) -> CompetencyCellHistoryModel {
        let base: CompetencyCellHistoryModel = cellHistory(groupId: groupId, itemId: itemId, setup: setup,
                                                           subordinateId: subordinateId, sessions: sessions)
        let key = CompetencyCellKey(groupId: groupId, itemId: itemId)
        let range: CompetencyRange = setup.range(forGroup: groupId)
        let scale: CompetencyScale? = setup.scaleFor(group: groupId)
        let item: CompetencyItem? = setup.item(itemId)
        let now: CompetencyCellValue? = latestCells(sessions)[key]
        var levels: [CompetencyLevelRow] = base.levels
        if namesAllowed(range) {
            var rows: [CompetencyLevelRow] = []
            var any = false
            for v in range.low...range.high {
                let name: String = scale?.levelName(v) ?? ""
                let detail: String? = levelDetail(scale: scale, item: item, value: v, range: range)
                if !name.isEmpty || detail != nil { any = true }
                let cur: Bool = now.map { !$0.na && $0.range == range && $0.value == v } ?? false
                rows.append(CompetencyLevelRow(id: v, name: name, isCurrent: cur, detail: detail))
            }
            levels = any ? rows : []
        }
        var m = CompetencyCellHistoryModel(title: base.title, nowLine: base.nowLine, levels: levels, rows: base.rows,
                                           otherLine: base.otherLine, archivedNote: base.archivedNote)
        var target: CompetencyResolvedTarget? = nil
        if let g = grade {
            target = resolveTarget(targetTable(setup), gradeId: g.id, groupId: groupId, itemId: itemId, fallback: range)
            if let rt = target {
                var line: String = g.short + " 目標 " + targetValueText(rt, in: range)
                if let c = now, let tc = c.ratio {
                    if tc >= rt.ratio - 1e-9 {
                        line += " ✓"
                    } else {
                        line += "（差 " + numberText((rt.ratio - tc) * Double(range.high - range.low)) + "）"
                    }
                }
                m.targetLine = line
            }
        }
        m.trend = cellTrend(key: key, range: range, sessions: sessions, target: target)
        return m
    }

    /// ↔ cell_trend：我評的、沒刪的、這一格有分數的（不適用不算），舊的在前；三次以上才有
    static func cellTrend(key: CompetencyCellKey, range: CompetencyRange, sessions: [CompetencySession],
                          target: CompetencyResolvedTarget?) -> CompetencyTrendModel? {
        let ordered: [CompetencySession] = sessions.filter { $0.isLive && $0.isByMe }.sorted { a, b in
            if a.dayKey != b.dayKey { return a.dayKey < b.dayKey }
            return a.stamp < b.stamp
        }
        var pts: [CompetencyTrendPoint] = []
        for s in ordered {
            guard let sc = s.score(key), sc.isLive, !sc.isNA, let v = sc.value else { continue }
            let r: CompetencyRange = s.range(forGroup: key.groupId)
            let y: Double = r == range ? Double(v) : convert(v, from: r, to: range)
            let x: Double = Double(dayNumber(s.dayKey) ?? 0)
            pts.append(CompetencyTrendPoint(id: s.id, dayKey: s.dayKey, x: x, y: y, sameRange: r == range))
        }
        guard pts.count >= 3, let first = pts.first, let last = pts.last else { return nil }
        let spoken: [String] = pts.map { shortDay($0.dayKey) + " " + numberText($0.y) + " 分" }
        let ty: Double? = target.map { targetValue($0, in: range) }
        return CompetencyTrendModel(points: pts, low: Double(range.low), high: Double(range.high), targetY: ty,
                                    firstDayText: shortDay(first.dayKey), lastDayText: shortDay(last.dayKey),
                                    hasConverted: pts.contains { !$0.sameRange },
                                    accessibilityText: "走勢：" + spoken.joined(separator: "、"))
    }

    // MARK: 重名偵測〔合併〕（judge §4.4、critic #13：兩台離線各自加了同名的系統或項目）

    /// ↔ dup_key：去頭尾空白、中間連續空白算一個、不分大小寫（「Gas  system」＝「Gas System」）
    static func duplicateKey(_ name: String) -> String {
        let parts: [String] = name.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    /// ↔ count_word：「兩個」「3 個」
    static func countWord(_ n: Int) -> String {
        n == 2 ? "兩個" : "\(n) 個"
    }

    /// ↔ duplicates：啟用中的系統、人格特質、共用學習項目、每個系統自己的項目，各自那一份清單裡同名的
    static func duplicates(setup: CompetencySetupBook) -> [CompetencyDuplicate] {
        var out: [CompetencyDuplicate] = []
        let systems: [(id: UUID, name: String, created: Date?)] = setup.activeSystems.map { (id: $0.id, name: $0.displayName, created: $0.createdAt) }
        out += duplicateList(systems, kind: "system", groupId: nil, prefix: "system")
        let traits: [(id: UUID, name: String, created: Date?)] = setup.traitItems.map { (id: $0.id, name: $0.displayName, created: $0.createdAt) }
        out += duplicateList(traits, kind: "trait", groupId: nil, prefix: "trait")
        let shared: [(id: UUID, name: String, created: Date?)] = setup.sharedItems.map { (id: $0.id, name: $0.displayName, created: $0.createdAt) }
        out += duplicateList(shared, kind: "shared", groupId: nil, prefix: "shared")
        for g in setup.activeSystems {
            let own: [(id: UUID, name: String, created: Date?)] = setup.ownItems(g.id).map { (id: $0.id, name: $0.displayName, created: $0.createdAt) }
            out += duplicateList(own, kind: "own", groupId: g.id, prefix: "own|" + g.id.uuidString)
        }
        return out
    }

    /// 一份清單裡同名的（照第一次出現的順序）
    static func duplicateList(_ list: [(id: UUID, name: String, created: Date?)], kind: String, groupId: UUID?,
                              prefix: String) -> [CompetencyDuplicate] {
        var keys: [String] = []
        var byKey: [String: [(id: UUID, name: String, created: Date?)]] = [:]
        for x in list {
            let k: String = duplicateKey(x.name)
            if k.isEmpty { continue }
            if byKey[k] == nil { keys.append(k) }
            byKey[k, default: []].append(x)
        }
        var out: [CompetencyDuplicate] = []
        for k in keys {
            let same = byKey[k] ?? []
            guard same.count >= 2 else { continue }
            let sorted = same.sorted { a, b in
                let ca: Date = a.created ?? Date.distantPast
                let cb: Date = b.created ?? Date.distantPast
                if ca != cb { return ca < cb }
                return a.id.uuidString < b.id.uuidString
            }
            let keeper = sorted[0]
            let others: [UUID] = sorted.dropFirst().map { $0.id }
            let word: String = countWord(same.count)
            let what: String = kind == "system" ? "以前的分數會搬到同一個系統" : "以前的分數會搬到同一項"
            let msg: String = what + "（同一次評分兩邊都有的格子留後改的），另一個停用、可以在 已停用 找到。"
            out.append(CompetencyDuplicate(id: prefix + "|" + k, kind: kind, groupId: groupId, name: keeper.name,
                                           keeperId: keeper.id, otherIds: others,
                                           text: "有" + word + " " + keeper.name,
                                           confirmTitle: "合併" + word + "「" + keeper.name + "」？",
                                           confirmMessage: msg))
        }
        return out
    }

    /// ↔ merge_dup：〔合併〕。系統：另一個的分數搬到留下的（自己的項目搬過去、不用學的系統跟著換、目標跟著換）、另一個停用；
    /// 項目：每一張評分裡那一格搬到留下的那一項、目標跟著換、另一項停用。同一張評分同一格兩邊都有 → 留後改的；
    /// 搬過去的那一格蓋新時間、原本那一格蓋格子的墓碑（兩台各按一次〔合併〕、或只有一台按，合併後都只剩一個）
    static func mergingDuplicate(_ d: CompetencyDuplicate, setup: CompetencySetupBook, ratings: CompetencyRatingBook,
                                 now: Date) -> (setup: CompetencySetupBook, ratings: CompetencyRatingBook) {
        var b = setup
        let losers: Set<UUID> = Set(d.otherIds)
        let keep: UUID = d.keeperId
        guard !losers.isEmpty, !losers.contains(keep) else { return (setup, ratings) }
        let isSystem: Bool = d.kind == "system"
        if isSystem {
            for it in b.allItems where it.isLive {
                guard let gid = it.groupId, losers.contains(gid) else { continue }
                var x = it
                x.groupId = keep
                x.updatedAt = now
                b.upsertItem(x)
            }
            for g in b.allGroups where losers.contains(g.id) && g.isLive {
                var x = g
                if x.archivedAt == nil { x.archivedAt = now }
                x.updatedAt = now
                b.upsertGroup(x)
            }
            for a in b.allAssignments where a.deletedAt == nil {
                let sk: [UUID] = a.skippedGroupIds ?? []
                guard sk.contains(where: { losers.contains($0) }) else { continue }
                var x = a
                var list: [UUID] = sk.filter { !losers.contains($0) }
                if !list.contains(keep) { list.append(keep) }
                x.skippedGroupIds = list
                x.updatedAt = now
                b.upsertAssignment(x)
            }
        } else {
            var keeper: CompetencyItem? = b.item(keep)
            for it in b.allItems where losers.contains(it.id) && it.isLive {
                var x = it
                if x.archivedAt == nil { x.archivedAt = now }
                x.updatedAt = now
                b.upsertItem(x)
                if var k = keeper {
                    var touched = false
                    if k.shortName == nil, let s = it.shortName { k.shortName = s; touched = true }
                    if k.levelDetails == nil, let l = it.levelDetails { k.levelDetails = l; touched = true }
                    if touched { k.updatedAt = now; keeper = k }
                }
            }
            if let k = keeper, k != b.item(keep) { b.upsertItem(k) }
        }
        // [v25.601 v1b 驗證修] 「這個系統拿掉的共用學習項目」合併後取聯集（任一邊有評的系統，留下的那一個也評）：
        // 不然一台加 SOP 時沒勾 Chemical、另一台有勾，合併後 Chemical 的 SOP 分數搬過去了卻看不到。要退回這一件：刪這一行與 reconcilingHiddenShared
        b = reconcilingHiddenShared(b, kind: d.kind, keep: keep, losers: losers, now: now)
        // 目標跟著換（留下的那一個已經有同一層 → 另一個的蓋墓碑）
        let table: [CompetencyTargetKey: CompetencyTarget] = targetTable(b)
        var tlist: [CompetencyTarget] = b.allTargets
        var tChanged = false
        for i in tlist.indices where tlist[i].deletedAt == nil {
            var moved = tlist[i]
            if isSystem {
                guard let gid = moved.groupId, losers.contains(gid) else { continue }
                moved.groupId = keep
            } else {
                guard let iid = moved.itemId, losers.contains(iid) else { continue }
                moved.itemId = keep
            }
            if let k = targetKey(moved), let has = table[k], has.id != moved.id {
                tlist[i].deletedAt = now
            } else {
                tlist[i] = moved
            }
            tlist[i].updatedAt = now
            tChanged = true
        }
        if tChanged { b.targets = tlist }
        // 評分：每一張裡搬格子
        let r: CompetencyRatingBook = movingCells(ratings, setup: b, now: now) { k in
            if isSystem {
                return losers.contains(k.groupId) ? CompetencyCellKey(groupId: keep, itemId: k.itemId) : nil
            }
            return losers.contains(k.itemId) ? CompetencyCellKey(groupId: k.groupId, itemId: keep) : nil
        }
        return (b, r)
    }

    /// ↔ reconcile_hidden_shared：[v25.601 v1b 驗證修] 合併後共用學習項目在哪些系統評取聯集。
    /// 共用項目重名（kind "shared"）：留下的那一項在某個系統被拿掉、但另一項在那個系統有評 → 那個系統把留下的那一項勾回來。
    /// 系統重名（kind "system"）：留下的那個系統拿掉的共用項目，只有在另一個系統也拿掉時才照樣拿掉。
    /// 兩台各按一次〔合併〕算出來一樣（只看合併前就同步好的清單）
    static func reconcilingHiddenShared(_ book: CompetencySetupBook, kind: String, keep: UUID, losers: Set<UUID>,
                                        now: Date) -> CompetencySetupBook {
        var b = book
        if kind == "shared" {
            for g in b.allGroups where g.isLive && !g.isTrait {
                let hidden: [UUID] = g.hiddenSharedItemIds ?? []
                guard hidden.contains(keep) else { continue }
                let loserShown: Bool = losers.contains { !hidden.contains($0) }
                guard loserShown else { continue }
                var x = g
                x.hiddenSharedItemIds = hidden.filter { $0 != keep }
                x.updatedAt = now
                b.upsertGroup(x)
            }
        } else if kind == "system" {
            guard let kg = b.group(keep), kg.isLive else { return b }
            let hidden: [UUID] = kg.hiddenSharedItemIds ?? []
            guard !hidden.isEmpty else { return b }
            let loserGroups: [CompetencyGroup] = b.allGroups.filter { losers.contains($0.id) && $0.isLive }
            let still: [UUID] = hidden.filter { id in
                loserGroups.allSatisfy { ($0.hiddenSharedItemIds ?? []).contains(id) }
            }
            guard still.count != hidden.count else { return b }
            var x = kg
            x.hiddenSharedItemIds = still
            x.updatedAt = now
            b.upsertGroup(x)
        }
        return b
    }

    /// ↔ move_cells：把符合的格子搬到新的（組, 項目）。那一張那一格已經有、而且比較新 → 留著（搬的那一格只清掉）；
    /// 搬過去的那一格蓋 now、名字快照換成現在的；原本那一格蓋格子的墓碑。碰到的那幾張 updatedAt＝now
    static func movingCells(_ book: CompetencyRatingBook, setup: CompetencySetupBook, now: Date,
                            map: (CompetencyCellKey) -> CompetencyCellKey?) -> CompetencyRatingBook {
        var b = book
        var list: [CompetencySession] = b.allSessions
        var changed = false
        for i in list.indices where list[i].isLive {
            var cells: [CompetencyScore] = list[i].allScores
            var hit = false
            for j in cells.indices {
                let src: CompetencyScore = cells[j]
                guard src.isLive, let dest = map(src.key), dest != src.key else { continue }
                let existing: Int? = cells.firstIndex(where: { $0.key == dest })
                var movedWins = true
                if let e = existing, cells[e].isLive, cells[e].stamp >= src.stamp { movedWins = false }
                if movedWins {
                    var x = src
                    x.groupId = dest.groupId
                    x.itemId = dest.itemId
                    x.groupName = setup.group(dest.groupId)?.displayName ?? src.groupName
                    x.itemName = setup.item(dest.itemId)?.displayName ?? src.itemName
                    x.updatedAt = now
                    x.clearedAt = nil
                    if let e = existing { cells[e] = x } else { cells.append(x) }
                }
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
}

// MARK: - [v25.602 職能雷達 v2] 課的總覽（熱力表、能獨立／能教人、單點風險、找人、課平均雷達、兩人疊圖、一次評全課）、
//   「能獨立／能教人是第幾級」、項目自己的說明標成舊範圍
//（radar/judge.md §7 分版表 v2、§4.7、§2.1 independentLevel／trainerLevel、§3.3 第 2 輪 #6、§3.8 課平均與人數、§4.4、§5、§6、§13；
//  radar/build/v2/brief.md §2；sim_v2.py 一個函式一個函式對照，↔ 後面是 sim 的名字）
// • 「能獨立」「能教人」是兩條門檻的名字，不是每一分的名字（§13 每一分不預設名字）：還沒設＝nil＝比例 0.5／0.75 最接近的那一級
//  （四捨五入；1–5 是 3、4，1–10 是 6、8，0–100 是 50、75）。設過的存在 CompetencyScale.independentLevel／trainerLevel（v1a 就宣告了），
//   設的時候的範圍放 extra「thresholdLow／thresholdHigh」（Competency.swift 一行都沒動；別台改了範圍也換算得回來）。
// • 能獨立 ≤ 能教人（相等可以：1–2、1–3 這種級數少的範圍照比例本來就會一樣）。改範圍時設過的照比例換到最接近的一級；App 不在更新後自己寫。
// • 課平均：只算要學、有分數、沒轉出的人（不適用、未評、不用學都不算分母）；能獨立／能教人人數：再扣掉暫時離開中（借調、支援、留停）。
// • 項目自己的說明（levelDetails）改範圍時標成舊範圍（extra「levelDetailsLow／levelDetailsHigh」）：照新範圍不顯示，改回原來的範圍就回來。
// • 只在 App 裡：通知、小工具、手錶、鎖定畫面、靈動島一個字都不碰；沒有新的同步鍵、沒有新的模型欄位。

/// 能獨立／能教人是第幾級（現在的範圍）
struct CompetencyThresholds: Equatable {
    let independent: Int
    let trainer: Int
    /// 使用者自己設過（false＝照比例）
    let independentSet: Bool
    let trainerSet: Bool
    let range: CompetencyRange
}

/// 熱力表的一位同仁（畫面照轉組織現有的判斷函式算好傳進來：OrgMoveIndex.isArchived、awayNow＋OrgMovePlan.awayText）
struct CompetencyTeamPerson: Equatable, Identifiable {
    let id: UUID
    /// 名字（空白＝「這位同仁」）
    let name: String
    let gradeTitleId: UUID?
    /// 已轉出
    let archived: Bool
    /// 今天暫時離開中「借調中・到 1/29」（沒有 nil）
    let awayText: String?
}

/// 熱力表看哪一區
enum CompetencyTeamArea: String, Equatable, CaseIterable, Identifiable {
    case skill
    case trait

    var id: String { rawValue }
    var title: String { self == .skill ? "本職學能" : "人格特質" }
}

/// 一格是什麼
enum CompetencyTeamCellKind: Equatable {
    /// 有分數
    case value
    /// 不用學「—」
    case notRequired
    /// 未評「·」
    case unrated
    /// 不適用「／」
    case na
}

/// 熱力表一格
struct CompetencyTeamCell: Equatable, Identifiable {
    /// 「人 id|組 id|項目 id」
    let id: String
    let personId: UUID
    let groupId: UUID
    let itemId: UUID
    let kind: CompetencyTeamCellKind
    /// 「4」「≈7.8」「75」「—」「·」「／」
    let text: String
    /// 比例（有分數才有）
    let t: Double?
    /// 底色五階 0…4（有分數才有；t 0–0.2、0.2–0.4…）
    let tier: Int?
    /// ◤ 有分數、沒達到這位現在職等的目標
    let belowTarget: Bool
    /// VoiceOver：「王小明，Chemical System・緊急應變，2 分，未達目標 3」
    let spoken: String
}

/// 熱力表一列（一位同仁）
struct CompetencyTeamRow: Equatable, Identifiable {
    let id: UUID
    let name: String
    /// 「E2」（沒設、職等被刪 nil）
    let gradeShort: String?
    /// 「借調中・到 1/29」
    let awayText: String?
    let archived: Bool
    /// 跟 columns 同順序
    let cells: [CompetencyTeamCell]
}

/// 熱力表一欄（一組 × 一項）
struct CompetencyTeamColumn: Equatable, Identifiable {
    /// 「組 id|項目 id」
    let id: String
    let groupId: UUID
    let itemId: UUID
    /// 欄頭第二行：項目短名，沒有寫名字（「緊急應變」）
    let itemTitle: String
    /// 「Chemical System・緊急應變」
    let fullTitle: String
    /// 要學、沒轉出（含暫時離開中）的人數；0＝能獨立、能教人寫「—」、不畫框
    let requiredCount: Int
    let independentCount: Int
    let trainerCount: Int
    /// 能獨立／能教人兩列的字（「3」「—」）
    let independentText: String
    let trainerText: String
    /// 課平均（比例；沒有人有分數 nil）
    let averageT: Double?
    /// 「4.33」「4.0」「—」
    let averageText: String
    /// 課平均算了幾位
    let averageCount: Int
    /// 紅框＝能獨立 ≤ 1；橘框＝能教人 ≤ 1、而且不是紅框
    let red: Bool
    let orange: Bool
}

/// 欄頭第一行（一組佔幾欄）
struct CompetencyTeamGroupHeader: Equatable, Identifiable {
    let id: UUID
    /// 短名或名字「Gas」
    let title: String
    let fullTitle: String
    let isTrait: Bool
    /// 從 columns 第幾欄開始、佔幾欄
    let start: Int
    let count: Int
}

/// 最上面四張卡
struct CompetencyTeamCard: Equatable, Identifiable {
    /// "independent"／"trainer"／"target"／"stale"
    let id: String
    /// 「只剩一人能獨立」
    let title: String
    let value: Int
    /// 「1」「3 格」「0 位」「—」
    let valueText: String
    /// 下面小字（「Chemical・緊急應變」「還沒評過 1 位」「還沒訂職等目標」）；沒有 nil
    let note: String?
    /// value > 0：卡片用紅／橘
    let alert: Bool
}

/// 單點風險（點卡片後的那一段字）
struct CompetencyRiskEntry: Equatable, Identifiable {
    /// 「independent|欄 id」
    let id: String
    /// "independent"／"trainer"
    let kind: String
    let columnId: String
    /// 「Chemical System・緊急應變」
    let title: String
    /// 「Chemical System・緊急應變：能獨立的只有陳怡君。陳怡君請假或借調時，沒有第二位能獨立處理。最接近：林志豪 2、王小明 2（都差 1 級）」
    let text: String
    /// 〔看林志豪〕打開那位的〔職能〕分頁（沒有最接近的人 nil）
    let focusPersonId: UUID?
    let buttonTitle: String?
}

/// 課的總覽整頁（CompetencyTeamView 只照這個排）
struct CompetencyTeamModel: Equatable {
    let area: CompetencyTeamArea
    let range: CompetencyRange
    let thresholds: CompetencyThresholds
    let groups: [CompetencyTeamGroupHeader]
    let columns: [CompetencyTeamColumn]
    /// 在職的在前（照名單順序）、已轉出的在後（〔含已轉出〕才有）
    let rows: [CompetencyTeamRow]
    /// 四張卡（只剩一人能獨立、只剩一人能教人、未達目標、超過 6 個月沒評）
    let cards: [CompetencyTeamCard]
    /// 紅框的欄在前、橘框的在後（欄的順序）
    let risks: [CompetencyRiskEntry]
    /// 課平均雷達（每組一張「平均 3 位」；沒有人評過的組不畫）
    let averageCards: [CompetencyChartModel]
    /// 「能獨立（≥ 3）」「能教人（≥ 4）」
    let independentLabel: String
    let trainerLabel: String
    /// 「— 不用學・· 未評・／ 不適用・◤ 未達目標」
    let legend: String
    /// 還沒設定、這一區沒有項目時的一行（有東西 nil）
    let emptyText: String?
    /// 有任何一位有目標（◤ 才有意義）
    let hasTargets: Bool
}

/// 〔找人〕的結果
struct CompetencyFindResult: Equatable {
    let personIds: [UUID]
    /// 「陳怡君 4」「林志豪 4（借調中・到 1/29）」
    let names: [String]
    /// 「陳怡君 4、林志豪 4」「沒有人 ≥ 5」
    let text: String
}

/// 〔一次評全課〕可以選的組
struct CompetencyBatchChoice: Equatable, Identifiable {
    let id: UUID
    let title: String
    let isTrait: Bool
}

/// 〔一次評全課〕的一頁（CompetencyRatingRequest.batch；nil＝照舊一位一張）
struct CompetencyRatingBatch: Equatable {
    /// 最上面「2／3　陳怡君」
    let positionText: String
    /// 「這次評」預設只勾這幾組（跟這一張的組取交集；交集空的照舊全部勾）
    let groupIds: Set<UUID>
    /// 後面還有人（右上〔下一位 ›〕）
    let hasNext: Bool
}

extension CompetencyMath {

    // MARK: extra 裡的範圍（Competency.swift 不加欄位：設定的範圍放 extra）

    /// 能獨立／能教人設的時候的範圍（CompetencyScale.extra）
    static let thresholdLowKey: String = "thresholdLow"
    static let thresholdHighKey: String = "thresholdHigh"
    /// 項目自己的說明寫的時候的範圍（CompetencyItem.extra）
    static let detailsLowKey: String = "levelDetailsLow"
    static let detailsHighKey: String = "levelDetailsHigh"
    /// 還沒設時照這兩個比例（judge §2.1：出廠 3、4）
    static let independentRatio: Double = 0.5
    static let trainerRatio: Double = 0.75

    /// ↔ extra_int：extra 裡的整數（不是數字、不是有限值 nil）
    static func extraInt(_ extra: [String: JSONValue]?, _ key: String) -> Int? {
        guard let v = extra?[key], case .number(let d) = v, d.isFinite, abs(d) < 1_000_000 else { return nil }
        return Int(d.rounded())
    }

    /// ↔ extra_range：extra 裡存的範圍（兩個都有、合理才算）
    static func extraRange(_ extra: [String: JSONValue]?, lowKey: String, highKey: String) -> CompetencyRange? {
        guard let lo = extraInt(extra, lowKey), let hi = extraInt(extra, highKey),
              CompetencyRange.isValid(low: lo, high: hi) else { return nil }
        return CompetencyRange(low: lo, high: hi)
    }

    /// ↔ set_extra_range：寫（r nil＝拿掉）；其他鍵原樣留著；全空回 nil
    static func settingExtraRange(_ extra: [String: JSONValue]?, _ r: CompetencyRange?,
                                  lowKey: String, highKey: String) -> [String: JSONValue]? {
        var e: [String: JSONValue] = extra ?? [:]
        if let r {
            e[lowKey] = JSONValue.number(Double(r.low))
            e[highKey] = JSONValue.number(Double(r.high))
        } else {
            e.removeValue(forKey: lowKey)
            e.removeValue(forKey: highKey)
        }
        return e.isEmpty ? nil : e
    }

    // MARK: 能獨立／能教人是第幾級（judge §2.1、§3.3 第 2 輪 #6、§4.4「v2 等級表多兩個選單」）

    /// ↔ convert_level：一級換到另一個範圍最接近的那一級（四捨五入；1–5 的 3 → 1–10 的 6、4 → 8）
    static func convertLevel(_ v: Int, from: CompetencyRange, to: CompetencyRange) -> Int {
        if from == to { return to.clamp(v) }
        return to.clamp(roundHalfUp(convert(from.clamp(v), from: from, to: to)))
    }

    /// ↔ thresholds：現在的範圍下能獨立、能教人是第幾級。沒設＝比例 0.5／0.75 最接近的一級；
    /// 設過的照設的時候的範圍換算（別台改了範圍也對得上）；能教人不會比能獨立低
    static func thresholds(_ scale: CompetencyScale?, range r: CompetencyRange) -> CompetencyThresholds {
        let stored: CompetencyRange = extraRange(scale?.extra, lowKey: thresholdLowKey, highKey: thresholdHighKey) ?? r
        var ind: Int = suggestLevel(independentRatio, r)
        var tr: Int = suggestLevel(trainerRatio, r)
        if let v = scale?.independentLevel { ind = convertLevel(v, from: stored, to: r) }
        if let v = scale?.trainerLevel { tr = convertLevel(v, from: stored, to: r) }
        if tr < ind { tr = ind }
        return CompetencyThresholds(independent: ind, trainer: tr, independentSet: scale?.independentLevel != nil,
                                    trainerSet: scale?.trainerLevel != nil, range: r)
    }

    /// ↔ threshold_options：選單能選的級（能獨立：最低…能教人；能教人：能獨立…最高）
    static func thresholdOptions(_ th: CompetencyThresholds, trainer: Bool) -> [Int] {
        let lo: Int = trainer ? th.independent : th.range.low
        let hi: Int = trainer ? th.range.high : th.trainer
        guard lo <= hi else { return [] }
        return Array(lo...hi)
    }

    /// ↔ threshold_option_text：選單一項「3 能獨立」（那一分有名字）／「3」
    static func thresholdOptionText(_ v: Int, scale: CompetencyScale?, range r: CompetencyRange) -> String {
        if let n = currentLevelNames(scale, range: r)[v] { return "\(v) " + n }
        return "\(v)"
    }

    /// ↔ threshold_footer：設定頁那兩列下面的小字
    static func thresholdFooter(_ th: CompetencyThresholds) -> String {
        if !th.independentSet && !th.trainerSet {
            return "還沒設：照範圍的一半、四分之三（\(th.range.text) 是 \(th.independent)、\(th.trainer)）。熱力表的能獨立、能教人人數、紅框橘框照這兩條算。"
        }
        return "熱力表的能獨立、能教人人數、紅框橘框照這兩條算；改了馬上重算，以前的分數不動。"
    }

    /// ↔ setting_threshold：設一條（trainer＝能教人；level nil＝改回照比例）。另一條設過的照現在範圍重寫一次（一起標現在的範圍）。
    /// 不在範圍裡、能獨立 > 能教人 → nil（不寫）
    static func settingThreshold(_ book: CompetencySetupBook, scaleId: String, trainer: Bool, level: Int?,
                                 now: Date) -> CompetencySetupBook? {
        let r: CompetencyRange = scaleId == CompetencySetupBook.traitScaleId ? book.traitRange : book.skillRange
        var sc: CompetencyScale = book.scale(scaleId) ?? CompetencyScale(id: scaleId, low: r.low, high: r.high)
        let th: CompetencyThresholds = thresholds(sc, range: r)
        var ind: Int? = sc.independentLevel == nil ? nil : th.independent
        var tr: Int? = sc.trainerLevel == nil ? nil : th.trainer
        if trainer { tr = level } else { ind = level }
        if let v = level, !r.contains(v) { return nil }
        let effInd: Int = ind ?? suggestLevel(independentRatio, r)
        let effTr: Int = tr ?? suggestLevel(trainerRatio, r)
        if effInd > effTr { return nil }
        let any: Bool = ind != nil || tr != nil
        let newExtra: [String: JSONValue]? = settingExtraRange(sc.extra, any ? r : nil,
                                                              lowKey: thresholdLowKey, highKey: thresholdHighKey)
        if sc.independentLevel == ind && sc.trainerLevel == tr && sc.extra == newExtra { return book }
        sc.independentLevel = ind
        sc.trainerLevel = tr
        sc.extra = newExtra
        sc.updatedAt = now
        var b: CompetencySetupBook = book
        b.upsertScale(sc)
        return b
    }

    /// ↔ threshold_range_line：改範圍的說明框多一行（設過才有）「能獨立 3 → 6、能教人 4 → 8（照比例換，改完可以在下面改）」
    static func thresholdRangeLine(scale: CompetencyScale?, from old: CompetencyRange, to new: CompetencyRange) -> String? {
        guard old != new, let sc = scale, sc.independentLevel != nil || sc.trainerLevel != nil else { return nil }
        let a: CompetencyThresholds = thresholds(sc, range: old)
        var parts: [String] = []
        if sc.independentLevel != nil {
            parts.append("能獨立 \(a.independent) → \(convertLevel(a.independent, from: old, to: new))")
        }
        if sc.trainerLevel != nil {
            let ni: Int = convertLevel(a.independent, from: old, to: new)
            let nt: Int = max(convertLevel(a.trainer, from: old, to: new), sc.independentLevel != nil ? ni : 0)
            parts.append("能教人 \(a.trainer) → \(nt)")
        }
        return parts.joined(separator: "、") + "（照比例換，改完可以在下面改）"
    }

    /// ↔ apply_range_change：改範圍那一次一起做（setCompetencyRange 兩支都叫它；old＝改之前的範圍）：
    /// ① 設過的能獨立／能教人照比例換到新範圍最接近的一級、標新範圍（沒設的本來就照比例，不寫）；
    /// ② 這一區的項目自己的說明還沒標範圍的，標成舊範圍（照新範圍不顯示；改回原來的範圍就回來）
    static func applyingRangeChange(_ book: CompetencySetupBook, scaleId: String, from old: CompetencyRange,
                                    to new: CompetencyRange, now: Date) -> CompetencySetupBook {
        guard old != new else { return book }
        var b: CompetencySetupBook = book
        if var sc = b.scale(scaleId), sc.independentLevel != nil || sc.trainerLevel != nil {
            let th: CompetencyThresholds = thresholds(sc, range: old)
            var ni: Int? = nil
            var nt: Int? = nil
            if sc.independentLevel != nil { ni = convertLevel(th.independent, from: old, to: new) }
            if sc.trainerLevel != nil { nt = convertLevel(th.trainer, from: old, to: new) }
            if let i = ni, let t = nt, t < i { nt = i }
            sc.independentLevel = ni
            sc.trainerLevel = nt
            sc.extra = settingExtraRange(sc.extra, new, lowKey: thresholdLowKey, highKey: thresholdHighKey)
            sc.updatedAt = now
            b.upsertScale(sc)
        }
        let isTrait: Bool = scaleId == CompetencySetupBook.traitScaleId
        var items: [CompetencyItem] = b.allItems
        var changed = false
        for i in items.indices {
            let it: CompetencyItem = items[i]
            guard it.isLive, (it.groupId == CompetencySetupBook.traitGroupId) == isTrait else { continue }
            guard !(it.levelDetails ?? []).isEmpty,
                  extraRange(it.extra, lowKey: detailsLowKey, highKey: detailsHighKey) == nil else { continue }
            items[i].extra = settingExtraRange(it.extra, old, lowKey: detailsLowKey, highKey: detailsHighKey)
            items[i].updatedAt = now
            changed = true
        }
        if changed { b.items = items }
        return b
    }

    // MARK: 項目自己的說明標成舊範圍（v1b adjudicate 留下的第 1 件）

    /// ↔ item_details_usable：這一項自己的說明能不能用在這個範圍（沒標＝當成現在的範圍寫的）
    static func itemDetailsUsable(_ it: CompetencyItem?, range r: CompetencyRange) -> Bool {
        guard let it else { return false }
        guard let mr = extraRange(it.extra, lowKey: detailsLowKey, highKey: detailsHighKey) else { return true }
        return mr == r
    }

    /// ↔ item_details_old_range：標的範圍跟現在不一樣才有（說明頁頂上一行「這些說明是照 1–5 寫的…」）
    static func itemDetailsOldRange(_ it: CompetencyItem, range r: CompetencyRange) -> CompetencyRange? {
        guard !(it.levelDetails ?? []).isEmpty,
              let mr = extraRange(it.extra, lowKey: detailsLowKey, highKey: detailsHighKey), mr != r else { return nil }
        return mr
    }

    /// ↔ item_details_old_text：「這些說明是照 1–5 寫的，現在是 1–10，評分時先不顯示。改回 1–5 就會再出現；改一句就照 1–10 用。」
    static func itemDetailsOldText(_ old: CompetencyRange, now r: CompetencyRange) -> String {
        "這些說明是照 " + old.text + " 寫的，現在是 " + r.text + "，評分時先不顯示。改回 " + old.text
            + " 就會再出現；改一句就照 " + r.text + " 用。"
    }

    /// ↔ hidden_item_details_note：改範圍後設定頁的小提示（這一區有幾項自己的說明先收起來）；沒有 nil
    static func hiddenItemDetailsNote(_ book: CompetencySetupBook, scaleId: String) -> String? {
        let isTrait: Bool = scaleId == CompetencySetupBook.traitScaleId
        let r: CompetencyRange = isTrait ? book.traitRange : book.skillRange
        var n = 0
        var oldText: String = ""
        for it in book.allItems where it.isActive && (it.groupId == CompetencySetupBook.traitGroupId) == isTrait {
            if let o = itemDetailsOldRange(it, range: r) {
                n += 1
                oldText = o.text
            }
        }
        guard n > 0 else { return nil }
        return "\(n) 項自己的說明是照 " + oldText + " 寫的，評分時先不顯示（改回 " + oldText + " 就會再出現）。"
    }

    // MARK: 課的總覽（judge §4.7）

    /// ↔ team_tier：底色五階（t 0–0.2 → 0、…、0.8–1 → 4；1–5 的 1～5 剛好一級一階）
    static func teamTier(_ t: Double) -> Int {
        let x: Double = (t * 5 + 1e-9).rounded(.down)
        return min(4, max(0, Int(x)))
    }

    /// ↔ team_avg_text：課平均最多兩位小數（4.3333 →「4.33」、4 →「4.0」、3.5 →「3.5」）
    static func teamAverageText(_ x: Double) -> String {
        let h: Int = Int((abs(x) * 100).rounded())
        let whole: Int = h / 100
        let frac: Int = h % 100
        var s: String
        if frac == 0 {
            s = "\(whole).0"
        } else if frac % 10 == 0 {
            s = "\(whole).\(frac / 10)"
        } else {
            s = "\(whole)." + (frac < 10 ? "0\(frac)" : "\(frac)")
        }
        if x < 0 && h != 0 { s = "-" + s }
        return s
    }

    /// ↔ team_groups：這一區要畫的組（人格：有項目才有；本職：啟用中的系統）＋軸（0 項的組不畫）
    static func teamGroups(setup: CompetencySetupBook, area: CompetencyTeamArea) -> [(group: CompetencyGroup, axes: [CompetencyItem])] {
        var out: [(group: CompetencyGroup, axes: [CompetencyItem])] = []
        if area == .trait {
            if let tg = setup.traitGroup {
                let ax: [CompetencyItem] = setup.axes(for: tg.id)
                if !ax.isEmpty { out.append((group: tg, axes: ax)) }
            }
            return out
        }
        for g in setup.activeSystems {
            let ax: [CompetencyItem] = setup.axes(for: g.id)
            if !ax.isEmpty { out.append((group: g, axes: ax)) }
        }
        return out
    }

    /// ↔ team_required：這位要不要學這一組（人格特質人人都評；系統：沒勾不用學）
    static func teamRequired(_ g: CompetencyGroup, personId: UUID, setup: CompetencySetupBook) -> Bool {
        g.isTrait || !setup.skippedGroupIds(personId).contains(g.id)
    }

    /// ↔ team_last_day：這位最後一次評分（有格子的、沒刪的）
    static func teamLastDay(_ sessions: [CompetencySession]) -> String? {
        sessions.filter { $0.isLive && $0.isByMe && !$0.liveScores.isEmpty }.map { $0.dayKey }.max()
    }

    /// ↔ team：課的總覽整頁。people＝現在名單（部門篩選後；〔含已轉出〕關著時就沒有已轉出的人）；sessions＝每位的評分；
    /// grades＝職等表（◤ 照這位現在的職等，v1b 的 resolveTarget）
    static func teamModel(setup: CompetencySetupBook, people: [CompetencyTeamPerson], sessions: [UUID: [CompetencySession]],
                          grades: [CompetencyGradeRef], area: CompetencyTeamArea, today: String) -> CompetencyTeamModel {
        let isTrait: Bool = area == .trait
        let range: CompetencyRange = isTrait ? setup.traitRange : setup.skillRange
        let scale: CompetencyScale? = setup.scale(isTrait ? CompetencySetupBook.traitScaleId : CompetencySetupBook.skillScaleId)
        let th: CompetencyThresholds = thresholds(scale, range: range)
        let indT: Double = ratio(th.independent, range)
        let trT: Double = ratio(th.trainer, range)
        let table: [CompetencyTargetKey: CompetencyTarget] = targetTable(setup)
        let ordered: [CompetencyTeamPerson] = people.filter { !$0.archived } + people.filter { $0.archived }
        var cellsOf: [UUID: [CompetencyCellKey: CompetencyCellValue]] = [:]
        for p in ordered { cellsOf[p.id] = latestCells(sessions[p.id] ?? []) }
        let gradeOf: [UUID: CompetencyGradeRef] = Dictionary(grades.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // 要畫的組：有人要學、或有人有分數
        var groups: [(group: CompetencyGroup, axes: [CompetencyItem])] = []
        for ga in teamGroups(setup: setup, area: area) {
            let gid: UUID = ga.group.id
            let needed: Bool = ordered.contains { p in
                if teamRequired(ga.group, personId: p.id, setup: setup) { return true }
                return (cellsOf[p.id] ?? [:]).keys.contains { $0.groupId == gid }
            }
            if needed { groups.append(ga) }
        }

        var headers: [CompetencyTeamGroupHeader] = []
        var columns: [CompetencyTeamColumn] = []
        var rowCells: [UUID: [CompetencyTeamCell]] = [:]
        var averageCards: [CompetencyChartModel] = []
        var belowCount = 0
        var hasTargets = false
        for ga in groups {
            let g: CompetencyGroup = ga.group
            headers.append(CompetencyTeamGroupHeader(id: g.id, title: chipTitle(g), fullTitle: g.displayName, isTrait: g.isTrait,
                                                     start: columns.count, count: ga.axes.count))
            var raters: Set<UUID> = []
            var avgTs: [Double?] = []
            var avgTexts: [String?] = []
            for item in ga.axes {
                let key = CompetencyCellKey(groupId: g.id, itemId: item.id)
                let full: String = g.displayName + "・" + item.displayName
                var required = 0
                var ind = 0
                var tr = 0
                var ts: [Double] = []
                for p in ordered {
                    let req: Bool = teamRequired(g, personId: p.id, setup: setup)
                    let cell: CompetencyCellValue? = cellsOf[p.id]?[key]
                    let eligible: Bool = req && !p.archived
                    var kind: CompetencyTeamCellKind = .unrated
                    var text: String = "·"
                    var t: Double? = nil
                    var below = false
                    var spoken: String = p.name + "，" + full + "，"
                    if !req {
                        kind = .notRequired
                        text = "—"
                        spoken += "不用學"
                    } else if let c = cell {
                        if c.na {
                            kind = .na
                            text = "／"
                            spoken += "不適用"
                        } else if let ct = c.ratio {
                            kind = .value
                            text = cellText(c, in: range)
                            t = ct
                            spoken += text + " 分"
                        }
                    } else {
                        spoken += "未評"
                    }
                    if !p.archived, let gidGrade = p.gradeTitleId, gradeOf[gidGrade] != nil,
                       let rt = resolveTarget(table, gradeId: gidGrade, groupId: g.id, itemId: item.id, fallback: range), req {
                        hasTargets = true
                        if let ct = t, ct < rt.ratio - 1e-9 {
                            below = true
                            belowCount += 1
                            spoken += "，未達目標 " + targetValueText(rt, in: range)
                        }
                    }
                    if eligible {
                        required += 1
                        if let ct = t {
                            ts.append(ct)
                            raters.insert(p.id)
                            if p.awayText == nil {
                                if ct >= indT - 1e-9 { ind += 1 }
                                if ct >= trT - 1e-9 { tr += 1 }
                            }
                        }
                    }
                    let tier: Int? = t.map { teamTier($0) }
                    let cellId: String = p.id.uuidString + "|" + g.id.uuidString + "|" + item.id.uuidString
                    let tc = CompetencyTeamCell(id: cellId, personId: p.id, groupId: g.id, itemId: item.id, kind: kind,
                                                text: text, t: t, tier: tier, belowTarget: below, spoken: spoken)
                    rowCells[p.id, default: []].append(tc)
                }
                let avg: Double? = ts.isEmpty ? nil : ts.reduce(0, +) / Double(ts.count)
                let avgText: String = avg.map { teamAverageText(value(atRatio: $0, range)) } ?? "—"
                let has: Bool = required > 0
                let red: Bool = has && ind <= 1
                let orange: Bool = has && !red && tr <= 1
                let itemTitle: String = cleanShortName(item.shortName, max: itemShortMax) ?? item.displayName
                columns.append(CompetencyTeamColumn(
                    id: g.id.uuidString + "|" + item.id.uuidString, groupId: g.id, itemId: item.id, itemTitle: itemTitle,
                    fullTitle: full, requiredCount: required, independentCount: ind, trainerCount: tr,
                    independentText: has ? "\(ind)" : "—", trainerText: has ? "\(tr)" : "—",
                    averageT: avg, averageText: avgText, averageCount: ts.count, red: red, orange: orange))
                avgTs.append(avg)
                avgTexts.append(avg == nil ? nil : avgText)
            }
            if !raters.isEmpty {
                averageCards.append(teamAverageCard(group: g, axes: ga.axes, ts: avgTs, texts: avgTexts, count: raters.count,
                                                    range: range))
            }
        }

        var rows: [CompetencyTeamRow] = []
        for p in ordered {
            var short: String? = nil
            if let gid = p.gradeTitleId, let gr = gradeOf[gid] { short = gr.short }
            rows.append(CompetencyTeamRow(id: p.id, name: p.name, gradeShort: short, awayText: p.awayText,
                                          archived: p.archived, cells: rowCells[p.id] ?? []))
        }

        let risks: [CompetencyRiskEntry] = teamRisks(columns: columns, rows: rows, people: ordered, range: range, th: th)
        let cards: [CompetencyTeamCard] = teamCards(columns: columns, people: ordered, sessions: sessions,
                                                    belowCount: belowCount, hasTargets: hasTargets, today: today)
        var legend: String = "— 不用學・· 未評・／ 不適用"
        if hasTargets { legend += "・◤ 未達目標" }
        var empty: String? = nil
        if !setup.isConfigured {
            empty = "還沒設定職能項目（設定 → 進階設定 → 部屬評分 → 職能項目）"
        } else if columns.isEmpty {
            empty = isTrait ? "人格特質還沒有項目" : "還沒有要學的系統項目"
        }
        return CompetencyTeamModel(area: area, range: range, thresholds: th, groups: headers, columns: columns, rows: rows,
                                   cards: cards, risks: risks, averageCards: averageCards,
                                   independentLabel: "能獨立（≥ \(th.independent)）",
                                   trainerLabel: "能教人（≥ \(th.trainer)）",
                                   legend: legend, emptyText: empty, hasTargets: hasTargets)
    }

    /// ↔ team_cards：最上面四張卡（在職的人才算；已轉出不算）
    static func teamCards(columns: [CompetencyTeamColumn], people: [CompetencyTeamPerson],
                          sessions: [UUID: [CompetencySession]], belowCount: Int, hasTargets: Bool,
                          today: String) -> [CompetencyTeamCard] {
        let reds: [CompetencyTeamColumn] = columns.filter { $0.red }
        let oranges: [CompetencyTeamColumn] = columns.filter { $0.orange }
        var stale = 0
        var never = 0
        for p in people where !p.archived {
            if let d = teamLastDay(sessions[p.id] ?? []) {
                if isStale(lastDay: d, today: today) { stale += 1 }
            } else {
                never += 1
            }
        }
        let c1 = CompetencyTeamCard(id: "independent", title: "只剩一人能獨立", value: reds.count, valueText: "\(reds.count)",
                                    note: teamColumnsNote(reds), alert: !reds.isEmpty)
        let c2 = CompetencyTeamCard(id: "trainer", title: "只剩一人能教人", value: oranges.count, valueText: "\(oranges.count)",
                                    note: teamColumnsNote(oranges), alert: !oranges.isEmpty)
        let c3 = CompetencyTeamCard(id: "target", title: "未達目標", value: belowCount,
                                    valueText: hasTargets ? "\(belowCount) 格" : "—",
                                    note: hasTargets ? nil : "還沒訂職等目標", alert: belowCount > 0)
        let c4 = CompetencyTeamCard(id: "stale", title: "超過 6 個月沒評", value: stale, valueText: "\(stale) 位",
                                    note: never > 0 ? "還沒評過 \(never) 位" : nil, alert: stale > 0)
        return [c1, c2, c3, c4]
    }

    /// ↔ team_cols_note：卡片下面小字「Chemical・緊急應變」「Chemical・P&ID 等 2 項」
    static func teamColumnsNote(_ cols: [CompetencyTeamColumn]) -> String? {
        guard let f = cols.first else { return nil }
        if cols.count == 1 { return f.fullTitle }
        return f.fullTitle + " 等 \(cols.count) 項"
    }

    /// ↔ team_risks：紅框的欄（能獨立）在前、橘框（能教人）在後；每一段字照 §4.7
    static func teamRisks(columns: [CompetencyTeamColumn], rows: [CompetencyTeamRow], people: [CompetencyTeamPerson],
                          range: CompetencyRange, th: CompetencyThresholds) -> [CompetencyRiskEntry] {
        var out: [CompetencyRiskEntry] = []
        for (ci, col) in columns.enumerated() where col.red {
            out.append(teamRisk(col: col, index: ci, rows: rows, people: people, range: range, level: th.independent,
                                trainer: false))
        }
        for (ci, col) in columns.enumerated() where col.orange {
            out.append(teamRisk(col: col, index: ci, rows: rows, people: people, range: range, level: th.trainer,
                                trainer: true))
        }
        return out
    }

    /// ↔ team_risk：一段字。holder＝要學、在職、不是暫時離開、到那一級的人；最接近＝要學、在職、不是暫時離開、有分數、還沒到的人，
    /// 差最少級的在前（同分照名字），最多兩位
    static func teamRisk(col: CompetencyTeamColumn, index ci: Int, rows: [CompetencyTeamRow], people: [CompetencyTeamPerson],
                         range: CompetencyRange, level: Int, trainer: Bool) -> CompetencyRiskEntry {
        let word: String = trainer ? "能教人" : "能獨立"
        let lt: Double = ratio(level, range)
        let span: Double = Double(range.high - range.low)
        var holders: [String] = []
        var awayHolders: [String] = []
        var near: [(name: String, id: UUID, gap: Double, text: String)] = []
        for r in rows where !r.archived && ci < r.cells.count {
            let c: CompetencyTeamCell = r.cells[ci]
            guard c.kind != .notRequired, let t = c.t else { continue }
            if t >= lt - 1e-9 {
                if let a = r.awayText {
                    awayHolders.append(r.name + a)
                } else {
                    holders.append(r.name)
                }
            } else if r.awayText == nil {
                near.append((name: r.name, id: r.id, gap: (lt - t) * span, text: c.text))
            }
        }
        near.sort { a, b in
            if abs(a.gap - b.gap) > 1e-9 { return a.gap < b.gap }
            return a.name < b.name
        }
        let top = Array(near.prefix(2))
        var s: String = col.fullTitle + "："
        if holders.count == 1 {
            let h: String = holders[0]
            let tail: String = trainer ? "能教人。" : "能獨立處理。"
            s += word + "的只有" + h + "。"
            s += h + "請假或借調時，沒有第二位" + tail
        } else {
            s += "現在沒有人" + word
            s += awayHolders.isEmpty ? "。" : "（" + awayHolders.joined(separator: "、") + "）。"
        }
        if top.isEmpty {
            s += "最接近：沒有（別的同仁還沒評或不用學）。"
        } else {
            // [v25.602 v2 裁定] map 寫明回傳 String、拆成區域變數，型別檢查才不會太久（字一樣）
            let nearTexts: [String] = top.map { (p) -> String in p.name + " " + p.text }
            s += "最接近：" + nearTexts.joined(separator: "、")
            let same: Bool = top.count == 1 || abs(top[0].gap - top[top.count - 1].gap) < 1e-9
            if top.count == 1 {
                s += "（差 " + numberText(top[0].gap) + " 級）"
            } else if same {
                s += "（都差 " + numberText(top[0].gap) + " 級）"
            } else {
                let gapTexts: [String] = top.map { (p) -> String in p.name + "差 " + numberText(p.gap) + " 級" }
                s += "（" + gapTexts.joined(separator: "、") + "）"
            }
        }
        let focus: UUID? = top.first?.id
        let button: String? = top.first.map { "看" + $0.name }
        return CompetencyRiskEntry(id: (trainer ? "trainer|" : "independent|") + col.id, kind: trainer ? "trainer" : "independent",
                                   columnId: col.id, title: col.fullTitle, text: s, focusPersonId: focus, buttonTitle: button)
    }

    /// ↔ team_avg_card：課平均雷達一張（「Gas System・平均 3 位」；不疊上一次、不疊目標）
    static func teamAverageCard(group: CompetencyGroup, axes: [CompetencyItem], ts: [Double?], texts: [String?],
                                count: Int, range: CompetencyRange) -> CompetencyChartModel {
        let n: Int = axes.count
        let style: CompetencyChartStyle = chartStyle(axisCount: n)
        var models: [CompetencyAxisModel] = []
        for (i, item) in axes.enumerated() {
            let t: Double? = i < ts.count ? ts[i] : nil
            let tx: String? = i < texts.count ? texts[i] : nil
            models.append(CompetencyAxisModel(id: item.id, name: item.displayName, label: axisLabel(item, index: i, style: style),
                                              state: t == nil ? .unrated : .rated, t: t, valueText: tx, originalText: nil,
                                              levelText: nil, previousT: nil, previousText: nil, deltaText: nil,
                                              carriedFrom: nil, archived: false))
        }
        let rated: [Double] = ts.compactMap { $0 }
        let avg: Double? = rated.isEmpty ? nil : rated.reduce(0, +) / Double(rated.count)
        let dateLine: String = "平均 \(count) 位"
        let title: String = group.displayName
        let isRadar: Bool = style == .radar || style == .radarShort
        var spoken: String = title + "，課平均 \(count) 位，\(n) 項。"
        var parts: [String] = []
        for m in models {
            let vt: String = m.valueText.map { $0 + " 分" } ?? "還沒有人評"
            parts.append(m.name + " " + vt)
        }
        if !parts.isEmpty { spoken += parts.joined(separator: "；") + "。" }
        var note: String? = nil
        if style == .bars {
            note = n <= 2 ? "項目少於 3 個，改用橫條" : "超過 12 項，改用橫條"
        } else if style != .empty && rated.count > 0 && rated.count < 3 {
            note = "評了 \(rated.count) 項，還畫不成雷達"
        }
        let avgText: String? = avg.map { "平均 " + oneDecimalText(round1(value(atRatio: $0, range))) }
        return CompetencyChartModel(
            id: group.id, isTrait: group.isTrait, title: title, dateLine: dateLine, headline: title + "・" + dateLine,
            averageText: avgText, style: style, axes: models, rings: rings(range), range: range,
            ratedCount: rated.count, drawsPolygon: rated.count >= 3 && isRadar, hasPrevious: false,
            legendCurrent: "課平均", legendPrevious: nil, note: note, carriedNote: nil, accessibilityText: spoken,
            neverRated: rated.isEmpty, averageRatio: avg, previousAverageRatio: nil, filledCount: rated.count,
            axisCount: n, latestDay: nil, previousDayText: nil)
    }

    /// ↔ team_pair：兩人疊圖（a＝實線、b＝灰色虛線，線型跟「上一次」一樣：色弱分得出）；這一區每組一張，兩位都不用學的組不畫
    static func teamPairCards(setup: CompetencySetupBook, area: CompetencyTeamArea, a: CompetencyTeamPerson,
                              aSessions: [CompetencySession], b: CompetencyTeamPerson,
                              bSessions: [CompetencySession]) -> [CompetencyChartModel] {
        let range: CompetencyRange = area == .trait ? setup.traitRange : setup.skillRange
        let ca: [CompetencyCellKey: CompetencyCellValue] = latestCells(aSessions)
        let cb: [CompetencyCellKey: CompetencyCellValue] = latestCells(bSessions)
        var out: [CompetencyChartModel] = []
        for ga in teamGroups(setup: setup, area: area) {
            let g: CompetencyGroup = ga.group
            let ra: Bool = teamRequired(g, personId: a.id, setup: setup)
            let rb: Bool = teamRequired(g, personId: b.id, setup: setup)
            guard ra || rb else { continue }
            out.append(teamPairCard(group: g, axes: ga.axes, a: a, cellsA: ra ? ca : [:], b: b, cellsB: rb ? cb : [:],
                                    requiredB: rb, range: range))
        }
        return out
    }

    /// ↔ team_pair_card：一張（橫條那一列「4　陳怡君 5」）
    static func teamPairCard(group g: CompetencyGroup, axes: [CompetencyItem], a: CompetencyTeamPerson,
                             cellsA: [CompetencyCellKey: CompetencyCellValue], b: CompetencyTeamPerson,
                             cellsB: [CompetencyCellKey: CompetencyCellValue], requiredB: Bool,
                             range: CompetencyRange) -> CompetencyChartModel {
        let n: Int = axes.count
        let style: CompetencyChartStyle = chartStyle(axisCount: n)
        var models: [CompetencyAxisModel] = []
        var aCells: [CompetencyCellValue?] = []
        var bCells: [CompetencyCellValue?] = []
        var parts: [String] = []
        for (i, item) in axes.enumerated() {
            let key = CompetencyCellKey(groupId: g.id, itemId: item.id)
            let x: CompetencyCellValue? = cellsA[key]
            let y: CompetencyCellValue? = cellsB[key]
            aCells.append(x)
            bCells.append(y)
            let state: CompetencyAxisState = x == nil ? .unrated : (x?.na == true ? .na : .rated)
            let at: String = x.map { cellText($0, in: range) } ?? "未評"
            let bt: String = requiredB ? (y.map { cellText($0, in: range) } ?? "未評") : "不用學"
            models.append(CompetencyAxisModel(id: item.id, name: item.displayName, label: axisLabel(item, index: i, style: style),
                                              state: state, t: x?.ratio, valueText: x.map { cellText($0, in: range) },
                                              originalText: nil, levelText: b.name + " " + bt, previousT: y?.ratio,
                                              previousText: y.map { cellText($0, in: range) }, deltaText: nil,
                                              carriedFrom: nil, archived: false))
            // [v25.602 v2 裁定] 8 段相加拆成兩段（型別檢查；字一樣）
            let aPart: String = item.displayName + " " + a.name + " " + at
            let bPart: String = b.name + " " + bt
            parts.append(aPart + "、" + bPart)
        }
        let rated: Int = models.filter { $0.t != nil }.count
        let hasB: Bool = models.contains { $0.previousT != nil }
        let avg: Double? = averageRatio(aCells)
        let title: String = g.displayName
        let dateLine: String = a.name + " 比 " + b.name
        let isRadar: Bool = style == .radar || style == .radarShort
        var note: String? = nil
        if style == .bars {
            note = n <= 2 ? "項目少於 3 個，改用橫條" : "超過 12 項，改用橫條"
        } else if style != .empty && rated > 0 && rated < 3 {
            note = "評了 \(rated) 項，還畫不成雷達"
        }
        let who: String = a.name + "實線、" + b.name + "灰色虛線。"
        let spoken: String = title + "，" + who + parts.joined(separator: "；") + "。"
        let avgText: String? = avg.map { "平均 " + oneDecimalText(round1(value(atRatio: $0, range))) }
        return CompetencyChartModel(
            id: g.id, isTrait: g.isTrait, title: title, dateLine: dateLine, headline: title + "・" + dateLine,
            averageText: avgText, style: style, axes: models, rings: rings(range), range: range, ratedCount: rated,
            drawsPolygon: rated >= 3 && isRadar, hasPrevious: hasB, legendCurrent: a.name,
            legendPrevious: hasB ? b.name : nil, note: note, carriedNote: nil, accessibilityText: spoken,
            neverRated: rated == 0, averageRatio: avg, previousAverageRatio: averageRatio(bCells),
            filledCount: aCells.compactMap { $0 }.count, axisCount: n, latestDay: nil, previousDayText: nil)
    }

    /// ↔ team_sorted：點欄頭照這一欄排（有分數的照分數，同分照原來的順序；沒分數的照原來順序排在後面；已轉出永遠在最後）
    static func teamSortedRows(_ rows: [CompetencyTeamRow], column ci: Int, descending: Bool) -> [CompetencyTeamRow] {
        func part(_ list: [CompetencyTeamRow]) -> [CompetencyTeamRow] {
            let indexed: [(i: Int, row: CompetencyTeamRow)] = list.enumerated().map { (i: $0.offset, row: $0.element) }
            let scored = indexed.filter { ci < $0.row.cells.count && $0.row.cells[ci].t != nil }
            let rest = indexed.filter { !(ci < $0.row.cells.count && $0.row.cells[ci].t != nil) }
            let sorted = scored.sorted { x, y in
                let tx: Double = x.row.cells[ci].t ?? 0
                let ty: Double = y.row.cells[ci].t ?? 0
                if abs(tx - ty) > 1e-9 { return descending ? tx > ty : tx < ty }
                return x.i < y.i
            }
            return sorted.map { $0.row } + rest.map { $0.row }
        }
        return part(rows.filter { !$0.archived }) + part(rows.filter { $0.archived })
    }

    // MARK: 〔找人〕（judge §4.7「[Slurry System ▾] [緊急應變 ▾] ≥ [4 能教人 ▾]」）

    /// ↔ find：這一欄 ≥ 那一級的人（在職的、照名單順序；暫時離開的也列、名字後面寫「（借調中・到 1/29）」；已轉出不列）
    static func findPeople(_ m: CompetencyTeamModel, columnId: String, atLeast v: Int) -> CompetencyFindResult {
        guard let ci = m.columns.firstIndex(where: { $0.id == columnId }) else {
            return CompetencyFindResult(personIds: [], names: [], text: "沒有這一項")
        }
        let lt: Double = ratio(m.range.clamp(v), m.range)
        var ids: [UUID] = []
        var names: [String] = []
        for r in m.rows where !r.archived && ci < r.cells.count {
            let c: CompetencyTeamCell = r.cells[ci]
            guard c.kind == .value, let t = c.t, t >= lt - 1e-9 else { continue }
            ids.append(r.id)
            let awayPart: String = r.awayText.map { "（" + $0 + "）" } ?? ""
            names.append(r.name + " " + c.text + awayPart)
        }
        let text: String = names.isEmpty ? "沒有人 ≥ \(m.range.clamp(v))" : names.joined(separator: "、")
        return CompetencyFindResult(personIds: ids, names: names, text: text)
    }

    // MARK: 〔一次評全課〕（judge §4.7；擋訂閱）

    /// ↔ batch_choices：可以選的組（人格特質有項目才有、啟用中有項目的系統）
    static func batchChoices(setup: CompetencySetupBook) -> [CompetencyBatchChoice] {
        var out: [CompetencyBatchChoice] = []
        for area in [CompetencyTeamArea.trait, CompetencyTeamArea.skill] {
            for ga in teamGroups(setup: setup, area: area) {
                out.append(CompetencyBatchChoice(id: ga.group.id, title: chipTitle(ga.group), isTrait: ga.group.isTrait))
            }
        }
        return out
    }

    /// ↔ batch_queue：照名單一位一頁：在職（沒轉出；暫時離開的也評）、選的組裡至少一組要學的人
    static func batchQueue(setup: CompetencySetupBook, people: [CompetencyTeamPerson],
                           groupIds: Set<UUID>) -> [CompetencyTeamPerson] {
        let groups: [CompetencyGroup] = batchChoices(setup: setup).filter { groupIds.contains($0.id) }.compactMap { setup.group($0.id) }
        return people.filter { p in
            !p.archived && groups.contains { teamRequired($0, personId: p.id, setup: setup) }
        }
    }

    /// ↔ batch_position：「2／3　陳怡君」
    static func batchPositionText(index: Int, total: Int, name: String) -> String {
        "\(index + 1)／\(total)　" + name
    }

    /// ↔ batch_done：關掉後的小提示「評好 2／3 位」「3 位都評好了」「這次沒有評」
    static func batchDoneText(saved: Int, total: Int) -> String {
        if saved == 0 { return "這次沒有評" }
        if saved >= total { return "\(total) 位都評好了" }
        return "評好 \(saved)／\(total) 位"
    }
}
