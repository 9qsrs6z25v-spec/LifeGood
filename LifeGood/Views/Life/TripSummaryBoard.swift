import SwiftUI
import MapKit
import UIKit
// .onReceive(NotificationCenter.default.publisher(for:)) 要用（TripTimelineCard 也是明著 import）
import Combine

// MARK: - 行程頁最上面的看板（v25.518，使用者的設計稿）
//
// 構圖照設計稿：
//
//   ╭──────────────────────────────────────────────────────╮
//   │ ✈ 10/3 (週六) 出發                  ( 車 開車 | ☰ 19/19 ) │ ← 行前準備（v25.451）
//   │ 15:10 → 14:30        Have                       ╱航廈╲│
//   │ 跨 7 天，10/9 (週五) 結束  a nice trip! - - ✈    │FUKUOKA│
//   │ ‿‿樓群‿⛩‿塔‿‿橋‿‿樓群‿‿    ══客機══               │▒▒▒▒▒▒│
//   │ [● 47 站 景點 ] [● 7 天 天數 ] [● 6 晚 住宿 (照片)]       │
//   │ [● 42 小時 20 分 停留] [● 18 小時 26 分 交通] [● 3218 km]  │
//   │ [● 293 張 相本 點開 › (照片疊)] [● NT$18.6萬 花費 48 筆・點開 ›] │
//   │ [✈ 行程進度 ━━━━━━━━━━✈━━━━   已完成 38 / 47 站  81%]  │
//   │ (開車 44 段)(飛機 2 段)(★ 必去 5 站)                      │
//   │ (● 現在在「福岡機場」 ›                ░這一站的照片░)     │
//   │ (● 第 1 天 10/3)(● 第 2 天 10/4)[● 第 6 天 10/8] → 橫捲    │
//   │ [! 有 1 站的指定抵達時間比推算的還早，照這個排法趕不上    ∨] │
//   ╰──────────────────────────────────────────────────────╯
//
// 規矩：
// 1. **要讀的字一律是 Text**；插畫（Canvas）只畫看得見、不用讀的東西：天空、雲、樓、
//    地標、客機、航廈。航廈招牌上的城市名是裝飾，可以畫；數字一個都不畫進 Canvas。
// 2. **能用使用者自己的資料畫，就不畫假的**：住宿格放過夜那一站的照片、相本格疊這趟的
//    真照片、距離格畫這趟真正的路線形狀、天數格是這幾天的小月曆（顏色跟時間軸同一套）、
//    場景跟著這趟實際用的交通方式（有飛機段才畫客機和航廈；開車環島畫的是公路）。
// 3. 深色模式是**另一套夜景**（星空、月牙、亮燈的窗與航廈、客機的航行燈），不是把白天調暗。
// 4. 這個檔案只吃 TripPlanDetailView 算好的資料（TripBoardData）和幾個動作閉包，
//    不碰 LifeStore／ExpenseStore；呼叫端在邊界抹成 AnyView（泛型太深會在 runtime demangle 爆棧）。
// 5. 不吃「英雄卡樣式」的漸層、KPI 與大字設定（那套是白字壓在漸層上，這張是淺色的天空），
//    只跟著那裡的「圓角」。設定頁有寫明。
// 6. 字級不照設計稿縮：設計稿是插畫比例，照比例縮到 375 寬的手機上標籤只剩 6.7pt。
//    字級固定、版面去適應（放不下的時長在「小時」後面斷成兩行，不硬縮）。

// [v25.519] 拿掉 fileprivate：時間軸卡片的天空色票（TripCardSky，在 TripTimelineCard.swift）
// 也用這一支寫色值，不再寫第二支 hex 轉換。模組裡另一支 hex 初始化是 init?(heroHex:)，不撞名。
extension Color {
    /// 0xRRGGBB（sRGB）
    init(tb hex: UInt32, _ alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

// MARK: - 資料

/// 看板的場景：跟著這趟**實際**用的交通方式走（開車環島的行程畫客機就是假的）。
enum TripBoardScene: Equatable {
    case flight, drive, rail, walk

    /// 有任何一段是飛機 → 機場；否則取段數最多的方式（平手偏向行程預設）。
    ///
    /// 看每一段實際的方式（Slot.mode），不看 modeSegmentCounts：機場還沒選位置時，
    /// 那一段算不出路線時間，modeSegmentCounts 會數不到它。
    static func pick(legModes: [TripTravelMode], fallback: TripTravelMode) -> TripBoardScene {
        if legModes.contains(.plane) { return .flight }
        var counts: [TripTravelMode: Int] = [:]
        for m in legModes { counts[m, default: 0] += 1 }
        var best = fallback
        var bestCount = counts[fallback] ?? 0
        for m in [TripTravelMode.driving, .transit, .walking] where (counts[m] ?? 0) > bestCount {
            best = m
            bestCount = counts[m] ?? 0
        }
        return of(best)
    }

    static func of(_ mode: TripTravelMode) -> TripBoardScene {
        switch mode {
        case .plane: return .flight
        case .driving: return .drive
        case .transit: return .rail
        case .walking: return .walk
        }
    }

    /// 進度條頭上、航線尾端的小圖示
    var icon: String {
        switch self {
        case .flight: return "airplane"
        case .drive: return "car.fill"
        case .rail: return "tram.fill"
        case .walk: return "figure.walk"
        }
    }
}

/// 一段「數字＋單位」。數字大、單位小，中間不放空白字元、改用 2pt 間距。
struct TripBoardValuePart: Hashable {
    let number: String
    let unit: String
}

enum TripBoardValue {
    /// 「42 小時 20 分」→ [42 小時][20 分]。從秒數直接算（規則同 TripRouter.durationText：
    /// 四捨五入到分），不去拆 durationText 的字串。0 → 「—」
    static func duration(_ seconds: Double) -> [TripBoardValuePart] {
        guard seconds > 0 else { return [TripBoardValuePart(number: "—", unit: "")] }
        let mins = Int((seconds / 60).rounded())
        if mins < 60 { return [TripBoardValuePart(number: "\(mins)", unit: "分")] }
        let h = mins / 60
        let m = mins % 60
        if m == 0 { return [TripBoardValuePart(number: "\(h)", unit: "小時")] }
        return [TripBoardValuePart(number: "\(h)", unit: "小時"),
                TripBoardValuePart(number: "\(m)", unit: "分")]
    }

    /// 距離。看板上 100 km 以上不寫小數（「3217.5 km」在 375 寬的格子放不下一行）。
    /// 只在看板這樣寫，共用的 TripRouter.distanceText 不動。
    static func distance(_ meters: Double) -> [TripBoardValuePart] {
        guard meters > 0 else { return [TripBoardValuePart(number: "—", unit: "")] }
        if meters < 1000 {
            return [TripBoardValuePart(number: String(format: "%.0f", meters), unit: "m")]
        }
        let km = meters / 1000
        let text = km >= 100 ? String(format: "%.0f", km) : String(format: "%.1f", km)
        return [TripBoardValuePart(number: text, unit: "km")]
    }

    /// 「NT$18.6萬」→ [NT$18.6][萬]
    static func money(_ text: String) -> [TripBoardValuePart] {
        if let last = text.last, last == "萬" || last == "億" {
            return [TripBoardValuePart(number: String(text.dropLast()), unit: String(last))]
        }
        return [TripBoardValuePart(number: text, unit: "")]
    }

    static func count(_ n: Int, _ unit: String) -> [TripBoardValuePart] {
        [TripBoardValuePart(number: "\(n)", unit: unit)]
    }

    /// VoiceOver 唸的
    static func spoken(_ parts: [TripBoardValuePart]) -> String {
        parts.map { $0.unit.isEmpty ? $0.number : $0.number + " " + $0.unit }
            .joined(separator: " ")
    }
}

/// 圖示圓的色系
enum TripBoardTint {
    case pink, blue, purple, green, orange, azure, violet, mint
}

/// 數字格子的一格
struct TripBoardStat: Identifiable {
    enum Kind: String {
        case stops, days, nights, dwell, travel, distance

        /// 第一列（行程的樣貌）還是第二列（時間與距離）
        var isShape: Bool { self == .stops || self == .days || self == .nights }
        /// 時長放不下一行時在「小時」後面斷；距離不斷
        var canBreak: Bool { self == .dwell || self == .travel }

        var icon: String {
            switch self {
            case .stops: return "mappin"
            case .days: return "calendar"
            case .nights: return "bed.double.fill"
            case .dwell: return "clock"
            case .travel: return "arrow.turn.up.right"
            case .distance: return "speedometer"
            }
        }

        var tint: TripBoardTint {
            switch self {
            case .stops: return .pink
            case .days: return .blue
            case .nights: return .purple
            case .dwell: return .green
            case .travel: return .orange
            case .distance: return .azure
            }
        }
    }

    let kind: Kind
    let parts: [TripBoardValuePart]
    let label: String
    var id: String { kind.rawValue }
}

struct TripBoardAlbum {
    let count: Int
    /// 疊在格子右邊的真照片（最多 3 張，新的在前）
    let previews: [URL]
}

struct TripBoardSpend {
    let parts: [TripBoardValuePart]
    /// 「48 筆・點開」或「還有 N 筆待確認」（v25.480 起就有，不能拿掉）
    let hint: String
    let isWaiting: Bool
    /// 收據插圖上畫幾條線（看得到、不給讀）
    let receiptLines: Int
    let spoken: String
}

struct TripBoardProgress {
    let done: Int
    let total: Int
}

struct TripBoardChip: Identifiable {
    enum Tone {
        case mode(TripTravelMode)
        case must
    }
    let id: String
    let icon: String
    let text: String
    let tone: Tone
}

struct TripBoardCurrent {
    let stopId: UUID
    let name: String
    /// 這一站的代表照片（＝封面，TripStop.coverPhotoURL）。強制用衛星空照的站是 nil
    let photoURL: URL?
    /// [v25.519] 使用者**明確指定**了哪一張當封面：那就連機場也放那張照片，不畫航廈
    let coverIsChosen: Bool
    let isAirport: Bool
    let place: TripPlaceName.Place?
    let latitude: Double?
    let longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct TripBoardDay: Identifiable {
    let index: Int
    /// 「第 1 天」
    let title: String
    /// 「10/3 (週六)」
    let date: String
    var id: Int { index }
}

/// 「趕不上」展開後的一列
struct TripBoardLate: Identifiable {
    let stopId: UUID
    /// 「第 5 站「太宰府天滿宮」」
    let title: String
    /// 「推算 13:25 才到，差 20 分」
    let detail: String
    var id: UUID { stopId }
}

struct TripBoardNotices {
    var isRouting = false
    var unroutedLegs = 0
    var retryableLegs = 0
    var late: [TripBoardLate] = []
    var idleText: String? = nil
    var weatherText: String? = nil

    var isEmpty: Bool {
        !isRouting && unroutedLegs == 0 && retryableLegs == 0 && late.isEmpty
            && idleText == nil && weatherText == nil
    }
}

/// 距離格的路線：依時間軸順序、有座標的站
struct TripBoardRoutePoint: Equatable {
    let lat: Double
    let lon: Double
    /// 從上一個點過來的路上（含中間沒座標、被跳過的站）有搭飛機
    let byPlane: Bool

    static func from(_ slots: [TripPlan.Slot]) -> [TripBoardRoutePoint] {
        var out: [TripBoardRoutePoint] = []
        var flew = false
        for slot in slots {
            if slot.index > 0 && slot.mode == .plane { flew = true }
            guard let c = slot.stop.coordinate else { continue }
            out.append(TripBoardRoutePoint(lat: c.latitude, lon: c.longitude,
                                           byPlane: flew && !out.isEmpty))
            flew = false
        }
        return out
    }
}

/// 格子右下角插圖要用的資料（全部是這趟自己的）
struct TripBoardArt: Equatable {
    var landmark: TripLandmark? = nil
    var dayCount = 1
    var todayIndex: Int? = nil
    /// 前幾天已經過完（淡掉）
    var pastDays = 0
    var stayPhotoURL: URL? = nil
    /// 停留 ÷（停留＋交通）
    var dwellRatio = 0.0
    var modesUsed: [TripTravelMode] = []
    var route: [TripBoardRoutePoint] = []
    var receiptLines = 0
    var hasWaiting = false
}

/// 整趟的目的地（航廈招牌、路標、地標用）
struct TripBoardCity: Equatable {
    let place: TripPlaceName.Place?
    let latitude: Double?
    let longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// .task(id:) 用：城市換了才重查
    var taskKey: String {
        if let place { return place.key }
        guard let latitude, let longitude else { return "-" }
        return String(format: "geo|%.2f,%.2f", latitude, longitude)
    }

    /// 同一座城在地址寫「臺北市」和「台北市」會切成兩個 key，計票前要先統一
    static func cityKey(_ place: TripPlaceName.Place) -> String {
        place.key.replacingOccurrences(of: "臺", with: "台")
    }

    struct Tally {
        let place: TripPlaceName.Place?
        let first: Int
        var nights = 0
        var stops = 0
        var nightCoordinate: CLLocationCoordinate2D? = nil
        var coordinates: [CLLocationCoordinate2D] = []

        /// 拿來問 Apple 的那一點：第一個過夜的站，沒有就中間那一站
        var anchor: CLLocationCoordinate2D? {
            nightCoordinate ?? (coordinates.isEmpty ? nil : coordinates[coordinates.count / 2])
        }
    }

    /// 目的地 ＝ 過夜最多的城市；平手比站數，再平手取最早出現的。
    ///
    /// 一晚都沒住（一日遊）時先排除出發的城市（第一個切得出城市的站）再比站數，
    /// 只剩出發城市才用它。不用「第一晚住哪」（先在機場旅館住一晚就選錯）、
    /// 不用「站最多」（住大阪、玩京都會選成京都）、不用「降落的機場在哪」
    /// （關西機場的地址會切成「田尻」）。原型跑過 6 個案例（scratchpad/v518/art_proto.py）。
    ///
    /// 地址切不出城市的站（韓國、泰國…）算成同一個「不知道」的城市一起比；
    /// 它贏的話用座標去問 Apple，問不到招牌就不寫字，不猜。
    static func pick(slots: [TripPlan.Slot], places: [TripPlaceName.Place?]) -> TripBoardCity? {
        var tally: [String: Tally] = [:]
        var order: [String] = []
        for slot in slots {
            let i = slot.index
            let place: TripPlaceName.Place? = places.indices.contains(i) ? places[i] : nil
            let key = place.map { cityKey($0) } ?? "?"
            if tally[key] == nil {
                tally[key] = Tally(place: place, first: i)
                order.append(key)
            }
            guard var t = tally[key] else { continue }
            t.stops += 1
            if let c = slot.stop.coordinate {
                t.coordinates.append(c)
                if slot.stop.isOvernight && t.nightCoordinate == nil { t.nightCoordinate = c }
            }
            if slot.stop.isOvernight { t.nights += 1 }
            tally[key] = t
        }
        let all = order.compactMap { tally[$0] }
        guard !all.isEmpty else { return nil }
        let useNights = all.contains { $0.nights > 0 }
        var pool = all
        if !useNights, let departure = order.first(where: { $0 != "?" }) {
            let others = order.filter { $0 != departure }.compactMap { tally[$0] }
            if !others.isEmpty { pool = others }
        }
        func rank(_ t: Tally) -> (Int, Int, Int) {
            (useNights ? t.nights : 0, t.stops, -t.first)
        }
        var best = pool[0]
        for t in pool.dropFirst() where rank(t) > rank(best) { best = t }
        if best.place == nil && best.anchor == nil { return nil }
        let c = best.place == nil ? best.anchor : (best.nightCoordinate ?? best.coordinates.first)
        return TripBoardCity(place: best.place, latitude: c?.latitude, longitude: c?.longitude)
    }
}

/// 看板要畫的東西。TripPlanDetailView 一次算好（值型別），看板本身不碰任何 Store。
struct TripBoardData {
    // 標頭
    var seed = 0
    var departText = ""
    var timeStart: String? = nil
    var timeEnd: String? = nil
    var spanText: String? = nil
    var travelMode: TripTravelMode = .driving
    var checklistDone = 0
    var checklistTotal = 0
    var scene: TripBoardScene = .drive
    var city: TripBoardCity? = nil
    var landmarks: [TripLandmark] = []
    // 格子
    var stats: [TripBoardStat] = []
    var art = TripBoardArt()
    var album: TripBoardAlbum? = nil
    var spend: TripBoardSpend? = nil
    // 下方
    var progress: TripBoardProgress? = nil
    var chips: [TripBoardChip] = []
    var current: TripBoardCurrent? = nil
    var days: [TripBoardDay] = []
    var todayIndex: Int? = nil
    var notices = TripBoardNotices()
}

/// 看板上可以按的東西
struct TripBoardActions {
    let openChecklist: () -> Void
    let openAlbum: () -> Void
    let openExpenses: () -> Void
    let openStop: (UUID) -> Void
    let jumpToDay: (Int) -> Void
    let retryRouting: () -> Void
}

// MARK: - 顏色

/// 淺色取自設計稿再修過對比；深色是夜景版（不是同一組色調暗）。
/// 主要文字的對比：白天 8～14.6:1，夜晚 11～16.9:1（scratchpad/v518/wcag.py）。
struct TripBoardPalette {
    let dark: Bool

    init(_ scheme: ColorScheme) { dark = scheme == .dark }

    // 字
    var ink: Color { dark ? Color(tb: 0xF3F6FF) : Color(tb: 0x0B1B45) }
    var inkDate: Color { dark ? Color(tb: 0xB9C7EE) : Color(tb: 0x1D3A7A) }
    var label: Color { dark ? Color(tb: 0xA3B2D9) : Color(tb: 0x4A5B8C) }
    var hint: Color { dark ? Color(tb: 0x8DB7FF) : Color(tb: 0x2F5BB7) }
    var waiting: Color { dark ? Color(tb: 0xFFC46B) : Color(tb: 0xA15C00) }
    // 卡
    var boardTop: Color { dark ? Color(tb: 0x121B38) : Color(tb: 0xEAF4FD) }
    var boardBottom: Color { dark ? Color(tb: 0x0E1428) : Color(tb: 0xF4F8FD) }
    var cardStroke: Color { dark ? Color.white.opacity(0.08) : Color.white.opacity(0.8) }
    var cardShadow: Color { dark ? Color.black.opacity(0.4) : Color(tb: 0x3B6FB6, 0.12) }
    // 格子
    var cellFill: Color { dark ? Color(tb: 0x1C2646, 0.86) : Color.white.opacity(0.78) }
    var cellStroke: Color { dark ? Color.white.opacity(0.10) : Color.white.opacity(0.75) }
    var cellShadow: Color { dark ? Color.black.opacity(0.25) : Color(tb: 0x1E3A6E, 0.08) }
    // 行前準備膠囊
    var capsuleFill: Color { dark ? Color.white.opacity(0.12) : Color.white.opacity(0.65) }
    var capsuleStroke: Color { dark ? Color.white.opacity(0.18) : Color.white.opacity(0.9) }
    var capsuleText: Color { dark ? Color(tb: 0xE6ECFF) : Color(tb: 0x163A87) }
    // 進度
    var progressColors: [Color] {
        dark ? [Color(tb: 0x3D86FF), Color(tb: 0x58D3FF)] : [Color(tb: 0x3A8DFF), Color(tb: 0x7EE6FF)]
    }
    var progressTrack: Color { dark ? Color.white.opacity(0.10) : Color(tb: 0xE3ECF8) }
    var progressInk: Color { dark ? Color(tb: 0x7FC0FF) : Color(tb: 0x0055C6) }
    /// 條頭圖示的光暈：把圖示從條上挖出來。白天是白的；夜裡用格子的底色，不發白光
    var progressHalo: Color { dark ? Color(tb: 0x1C2646) : Color.white.opacity(0.9) }
    // 現在在
    var currentFill: Color { dark ? Color(tb: 0x1E2848) : Color.white.opacity(0.88) }
    var pin: Color { dark ? Color(tb: 0xFF5A6E) : Color(tb: 0xE0344F) }

    struct Pair {
        let fill: Color
        let text: Color
    }

    /// 膠囊（6.5～9.3:1）
    func chip(_ tone: TripBoardChip.Tone) -> Pair {
        switch tone {
        case .must:
            return dark ? Pair(fill: Color(tb: 0x3B2F12), text: Color(tb: 0xFFD37A))
                        : Pair(fill: Color(tb: 0xFFF3D6), text: Color(tb: 0x7A4E00))
        case .mode(let m):
            switch m {
            case .driving:
                return dark ? Pair(fill: Color(tb: 0x17325E), text: Color(tb: 0xA9CCFF))
                            : Pair(fill: Color(tb: 0xE3F2FE), text: Color(tb: 0x0B3AA8))
            case .plane:
                return dark ? Pair(fill: Color(tb: 0x2A2266), text: Color(tb: 0xC9BDFF))
                            : Pair(fill: Color(tb: 0xECE8FF), text: Color(tb: 0x3A1FB8))
            case .transit:
                return dark ? Pair(fill: Color(tb: 0x123A3A), text: Color(tb: 0x8FE3D8))
                            : Pair(fill: Color(tb: 0xDDF5F2), text: Color(tb: 0x0B5C55))
            case .walking:
                return dark ? Pair(fill: Color(tb: 0x1E3A1E), text: Color(tb: 0xB5E8A0))
                            : Pair(fill: Color(tb: 0xE5F6E1), text: Color(tb: 0x2C5E1E))
            }
        }
    }

    struct DayChip {
        let fill: Color
        let text: Color
        let secondary: Color
        let stroke: Color
    }

    /// 日期膠囊。今天那一顆加框（不是「選取」：點了是捲過去，不會換框）
    func dayChip(today: Bool) -> DayChip {
        if dark {
            return today
                ? DayChip(fill: Color(tb: 0x1D3A6E), text: Color(tb: 0xE6ECFF),
                          secondary: Color(tb: 0xB9C7EE), stroke: Color(tb: 0x4D8DFF))
                : DayChip(fill: Color.white.opacity(0.08), text: Color(tb: 0xC9D5F2),
                          secondary: Color(tb: 0xA3B2D9), stroke: .clear)
        }
        return today
            ? DayChip(fill: Color(tb: 0xDDEDFE), text: Color(tb: 0x0B2A66),
                      secondary: Color(tb: 0x1D3B78), stroke: Color(tb: 0x8DBBF7))
            : DayChip(fill: Color.white.opacity(0.70), text: Color(tb: 0x1D3B78),
                      secondary: Color(tb: 0x4A5B8C), stroke: .clear)
    }

    enum NoticeTone {
        case late, info, gray, idle
    }

    struct Notice {
        let fill: Color
        let stroke: Color
        let text: Color
        let icon: Color
        /// 「重新計算」那顆的底（白字壓上去）
        let button: Color
    }

    func notice(_ tone: NoticeTone) -> Notice {
        switch tone {
        case .late:
            return dark
                ? Notice(fill: Color(tb: 0x3A2A0F), stroke: Color(tb: 0x6A4A14), text: Color(tb: 0xFFDDA6),
                         icon: Color(tb: 0xFFB020), button: Color(tb: 0xB86E00))
                : Notice(fill: Color(tb: 0xFFF4DC), stroke: Color(tb: 0xFBE3AE), text: Color(tb: 0x5A3000),
                         icon: Color(tb: 0xF59E0B), button: Color(tb: 0xB86E00))
        case .info:
            return dark
                ? Notice(fill: Color(tb: 0x172C55), stroke: Color(tb: 0x2C4A86), text: Color(tb: 0xBFD6FF),
                         icon: Color(tb: 0x8DB7FF), button: Color(tb: 0x2F63C8))
                : Notice(fill: Color(tb: 0xE6F0FE), stroke: Color(tb: 0xC9DCFB), text: Color(tb: 0x0B3AA8),
                         icon: Color(tb: 0x2F6BD8), button: Color(tb: 0x2F63C8))
        case .gray:
            return dark
                ? Notice(fill: Color.white.opacity(0.06), stroke: Color.white.opacity(0.10),
                         text: Color(tb: 0xC2CCE6), icon: Color(tb: 0x8E9BBF), button: Color(tb: 0x4A5B8C))
                : Notice(fill: Color.white.opacity(0.6), stroke: Color(tb: 0xDCE6F2),
                         text: Color(tb: 0x3E4C6B), icon: Color(tb: 0x6B7A99), button: Color(tb: 0x4A5B8C))
        case .idle:
            return dark
                ? Notice(fill: Color(tb: 0x182647), stroke: Color(tb: 0x2A3D6B),
                         text: Color(tb: 0xC4D2F2), icon: Color(tb: 0x8FA8DA), button: Color(tb: 0x4A5B8C))
                : Notice(fill: Color(tb: 0xEEF3FB), stroke: Color(tb: 0xD6E1F1),
                         text: Color(tb: 0x2E3F66), icon: Color(tb: 0x5B6FA0), button: Color(tb: 0x4A5B8C))
        }
    }

    /// 圖示圓的漸層（上→下），上面壓白色圖示。設計稿原本的橘 #FEA70A、綠 #3ABE74
    /// 配白只有 1.95／2.39:1，所以底色壓深了（3.06～5.5:1）。深色模式同色相再壓暗。
    func badge(_ tint: TripBoardTint) -> [Color] {
        switch tint {
        case .pink:
            return dark ? [Color(tb: 0xE0457A), Color(tb: 0xC93766)] : [Color(tb: 0xFF6F97), Color(tb: 0xE0457A)]
        case .blue, .azure:
            return dark ? [Color(tb: 0x2F7FE8), Color(tb: 0x1C62C9)] : [Color(tb: 0x4FA6FF), Color(tb: 0x1F6FE0)]
        case .purple:
            return dark ? [Color(tb: 0x8B5CF6), Color(tb: 0x7547E0)] : [Color(tb: 0xB38BFF), Color(tb: 0x8B5CF6)]
        case .green, .mint:
            return dark ? [Color(tb: 0x22A862), Color(tb: 0x1A8A4C)] : [Color(tb: 0x4CD08A), Color(tb: 0x1F9D57)]
        case .orange:
            return dark ? [Color(tb: 0xE08A10), Color(tb: 0xC96A00)] : [Color(tb: 0xFFB020), Color(tb: 0xE07800)]
        case .violet:
            return dark ? [Color(tb: 0x7A4EF0), Color(tb: 0x6438D6)] : [Color(tb: 0x9B6BFF), Color(tb: 0x7444F0)]
        }
    }
}

// MARK: - 看板本體

struct TripSummaryBoard: View {
    let data: TripBoardData
    let actions: TripBoardActions

    @Environment(\.colorScheme) private var scheme
    /// 招牌上的城市拼音查到了要重畫
    @ObservedObject private var names = TripPlaceNameStore.shared
    /// 只讀「圓角」（看板不吃英雄卡的漸層與 KPI 樣式，見檔頭）
    @ObservedObject private var heroStyle = HeroStyleStore.shared
    /// 卡寬（iPhone 是螢幕寬 − 32）。量一次，格子的排法要用。
    /// 量的是標頭（寬度跟著外面給的走），不是看板本身：看板的寬會被格子撐開，
    /// 拿它回頭算格子寬的話，第一次用的退回值一旦太寬（iPad 的 sheet 比螢幕窄）就修不回來。
    @State private var boardWidth: CGFloat = 0
    /// 「趕不上」那一列展開了沒
    @State private var lateOpen = false
    /// 日期膠囊列捲到哪一顆（進來時捲到今天）
    @State private var dayScrollID: Int?

    init(data: TripBoardData, actions: TripBoardActions) {
        self.data = data
        self.actions = actions
    }

    private var cardWidth: CGFloat {
        boardWidth > 0 ? boardWidth : UIScreen.main.bounds.width - 32
    }

    private var corner: CGFloat { CGFloat(heroStyle.value(.corner, .tripPlan)) }

    /// 航廈招牌／路標上的城市名（大寫）。查不到就 nil：招牌不寫字，不猜。
    private var citySign: String? {
        guard let c = data.city,
              let r = names.resolved(place: c.place, coordinate: c.coordinate) else { return nil }
        return r.romaji.uppercased()
    }

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            TripBoardHeader(data: data, sign: citySign, openChecklist: actions.openChecklist)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                // 標頭是 .frame(maxWidth: .infinity)：量到的就是外面給的寬
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { w in
                    if abs(w - boardWidth) > 0.5 { boardWidth = w }
                }
            VStack(alignment: .leading, spacing: 8) {
                TripBoardGrid(stats: data.stats, art: data.art, album: data.album, spend: data.spend,
                              cardWidth: cardWidth,
                              openAlbum: actions.openAlbum, openExpenses: actions.openExpenses)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                if let progress = data.progress {
                    progressCard(progress, pal: pal)
                }
                if !data.chips.isEmpty {
                    // 會自動換行的版面，擠不下時不會被切掉或折字
                    ChipFlowLayout(spacing: 6) {
                        ForEach(data.chips) { chip in chipView(chip, pal: pal) }
                    }
                }
                if let current = data.current {
                    currentPill(current, pal: pal)
                }
                if data.days.count > 1 {
                    dayStrip(pal: pal)
                }
                if !data.notices.isEmpty {
                    noticeStack(pal: pal)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
        }
        .background(LinearGradient(colors: [pal.boardTop, pal.boardBottom],
                                   startPoint: .top, endPoint: .bottom))
        .clipShape(shape)
        .overlay { shape.stroke(pal.cardStroke, lineWidth: pal.dark ? 0.5 : 0.8) }
        // 陰影掛在裁切外面（裁切會把陰影一起切掉）
        .background {
            shape.fill(pal.boardBottom)
                .shadow(color: pal.cardShadow, radius: pal.dark ? 16 : 18, x: 0, y: pal.dark ? 6 : 8)
        }
        // 招牌的城市拼音：內建表查得到就不連網；查不到才問 Apple（走 TripHeroGate，一次一個）
        .task(id: data.city?.taskKey ?? "-") {
            guard let c = data.city else { return }
            await names.resolveIfNeeded(place: c.place, coordinate: c.coordinate)
        }
        .task(id: data.current?.stopId) {
            guard let c = data.current, c.isAirport else { return }
            await names.resolveIfNeeded(place: c.place, coordinate: c.coordinate)
        }
    }

    // MARK: 行程進度

    /// [v25.518 新增] 開始打卡之後才出現。原本膠囊列的「已完成 38/47 站」搬到這裡，
    /// 膠囊列那一顆拿掉（同一個數字在同一張卡上寫兩次是雜訊）。
    private func progressCard(_ pr: TripBoardProgress, pal: TripBoardPalette) -> some View {
        let fraction = pr.total > 0 ? min(1, Double(pr.done) / Double(pr.total)) : 0
        let percent = Int((fraction * 100).rounded())
        let countText = "已完成 \(pr.done) / \(pr.total) 站"
        let percentText = "\(percent)%"
        let a11y = "行程進度，" + countText + "，" + percentText
        return VStack(alignment: .leading, spacing: 7) {
            // 字放很大時（375／393 寬約從輔助第 1 級起）標題和站數排不下一列：
            // 站數換到下一行，不截掉總站數（原本這是一顆會換行的膠囊，從來不會被截斷）
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    progressTitle(pal)
                    Spacer(minLength: 4)
                    progressCount(countText, pal: pal)
                }
                VStack(alignment: .leading, spacing: 2) {
                    progressTitle(pal)
                    progressCount(countText, pal: pal)
                }
            }
            HStack(spacing: 10) {
                TripBoardProgressBar(fraction: fraction, icon: data.scene.icon,
                                     colors: pal.progressColors, track: pal.progressTrack,
                                     iconColor: pal.progressInk, halo: pal.progressHalo)
                    .frame(height: 16)
                Text(percentText)
                    .font(.system(.footnote, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(pal.progressInk)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .modifier(TripBoardCellChrome(pal: pal))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }

    private func progressTitle(_ pal: TripBoardPalette) -> some View {
        HStack(spacing: 6) {
            Image(systemName: data.scene.icon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(pal.progressInk)
            Text("行程進度")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(pal.ink)
                .lineLimit(1)
        }
    }

    private func progressCount(_ text: String, pal: TripBoardPalette) -> some View {
        Text(text)
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(pal.label)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    // MARK: 膠囊

    private func chipView(_ chip: TripBoardChip, pal: TripBoardPalette) -> some View {
        let c = pal.chip(chip.tone)
        return HStack(spacing: 5) {
            Image(systemName: chip.icon).font(.caption2.weight(.bold))
            Text(chip.text).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(c.text)
        .padding(.horizontal, 10)
        .frame(minHeight: 24)
        .background(c.fill, in: Capsule())
    }

    // MARK: 現在在

    /// 原本是一顆點了沒反應的膠囊。現在點了打開那一站的景點卡；右半邊是那一站
    /// 自己的照片（往左淡出），機場就畫小一號的航廈，都沒有就不畫（不放假的機場照片）。
    private func currentPill(_ c: TripBoardCurrent, pal: TripBoardPalette) -> some View {
        let text = "現在在「" + c.name + "」"
        let pillWidth = max(200, cardWidth - 20)
        let artWidth = (pillWidth * 0.46).rounded()
        // 字可以伸進插圖淡出的那一段，但不壓到看得清楚的那一半
        let textMax = pillWidth - artWidth * 0.55 - 12
        let shape = Capsule()
        return Button {
            actions.openStop(c.stopId)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pal.pin)
                // 放得下就是一般的一行字、› 緊跟在後；放不下才跑馬燈（名字不折行，v25.517）
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        Text(text)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
                        currentChevron(pal)
                    }
                    HStack(spacing: 4) {
                        TripMarqueeText(text: text, font: .subheadline.weight(.semibold))
                        currentChevron(pal)
                    }
                }
                .foregroundStyle(pal.ink)
            }
            .frame(maxWidth: textMax, alignment: .leading)
            .padding(.leading, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(alignment: .trailing) {
                currentArt(c, pal: pal)
                    .frame(width: artWidth)
                    .frame(maxHeight: .infinity)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                                 .init(color: .black, location: 0.5)],
                                         startPoint: .leading, endPoint: .trailing))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .clipShape(shape)
            .background {
                shape.fill(pal.currentFill)
                    .shadow(color: pal.cellShadow, radius: 8, x: 0, y: 3)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityHint("點兩下打開這一站的景點卡")
        .accessibilityAddTraits(.isButton)
    }

    private func currentChevron(_ pal: TripBoardPalette) -> some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(pal.label)
    }

    /// [v25.519] 跟封面的規則一致：明確指定的照片最優先（連機場也是）；自動的時候機場照舊畫航廈；
    /// 強制用衛星空照的站沒有代表照片（photoURL 是 nil），機場畫航廈、其他留白。
    @ViewBuilder
    private func currentArt(_ c: TripBoardCurrent, pal: TripBoardPalette) -> some View {
        if c.coverIsChosen, let url = c.photoURL {
            TripBoardPhoto(url: url)
        } else if c.isAirport {
            TripBoardAirportArt(dark: pal.dark, sign: airportSign(c))
                .equatable()
        } else if let url = c.photoURL {
            TripBoardPhoto(url: url)
        } else {
            Color.clear
        }
    }

    /// 「FUKUOKA AIRPORT」。機場自己的城市查不到就只寫 AIRPORT
    private func airportSign(_ c: TripBoardCurrent) -> String {
        guard let r = names.resolved(place: c.place, coordinate: c.coordinate) else { return "AIRPORT" }
        return r.romaji.uppercased() + " AIRPORT"
    }

    // MARK: 日期膠囊

    /// 每一天一顆，點了捲到時間軸上的那一天並展開它（原本只是圖例，點了沒反應）。
    /// 圓點是時間軸同一套當天色（TripDayPalette），不照設計稿的藍綠橘——要對得上。
    /// 今天那一顆加框；進來時自己橫捲到今天（七天的行程走到第六天，不捲就看不到它）。
    private func dayStrip(pal: TripBoardPalette) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(data.days) { day in
                    dayChip(day, pal: pal)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 2)
            .padding(.horizontal, 1)
        }
        // 用 scrollPosition 而不是 ScrollViewReader：scrollTo 有可能連外層的整頁一起捲
        .scrollPosition(id: $dayScrollID, anchor: .center)
        .scrollEdgeFade(width: 14)
        .onAppear {
            if dayScrollID == nil, let t = data.todayIndex { dayScrollID = t }
        }
    }

    private func dayChip(_ day: TripBoardDay, pal: TripBoardPalette) -> some View {
        let isToday = day.index == data.todayIndex
        let c = pal.dayChip(today: isToday)
        // 字串在 ViewBuilder 外組好（長串 + 塞進三元會讓型別檢查逾時）
        var a11y = day.title + " " + day.date
        if isToday { a11y += "，今天" }
        return Button {
            actions.jumpToDay(day.index)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(TripDayPalette.color(day.index))
                    .frame(width: 8, height: 8)
                Text(day.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(c.text)
                Text(day.date)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(c.secondary)
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(c.fill, in: Capsule())
            .overlay {
                if isToday { Capsule().strokeBorder(c.stroke, lineWidth: 1.5) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11y)
        .accessibilityHint("點兩下捲到時間軸上的這一天")
    }

    // MARK: 提醒

    /// 原本的六種提醒一個都沒拿掉，排成同一種「圖示＋一段字」的列、只換顏色：
    /// 趕不上（橘、可展開）→ 重算路線（藍、可按）→ 計算中／還沒算出（灰）→ 空檔 → 天氣太遠。
    private func noticeStack(pal: TripBoardPalette) -> some View {
        let n = data.notices
        return VStack(alignment: .leading, spacing: 6) {
            if !n.late.isEmpty {
                lateNotice(n.late, pal: pal)
            }
            if n.retryableLegs > 0 {
                retryNotice(n.retryableLegs, pal: pal)
            }
            if n.isRouting {
                noticeRow(icon: nil, text: "正在計算路線…", tone: .gray, pal: pal, spinner: true)
            } else if n.unroutedLegs > 0 {
                noticeRow(icon: "hourglass", text: "有 \(n.unroutedLegs) 段還沒算出路線",
                          tone: .gray, pal: pal)
            }
            if let idle = n.idleText {
                noticeRow(icon: "hourglass.bottomhalf.filled", text: idle, tone: .idle, pal: pal)
            }
            if let weather = n.weatherText {
                noticeRow(icon: "calendar.badge.clock", text: weather, tone: .gray, pal: pal)
            }
        }
    }

    private func noticeRow(icon: String?, text: String, tone: TripBoardPalette.NoticeTone,
                           pal: TripBoardPalette, spinner: Bool = false) -> some View {
        let c = pal.notice(tone)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return HStack(alignment: .center, spacing: 8) {
            if spinner {
                ProgressView()
                    .controlSize(.small)
                    .tint(c.icon)
                    .frame(width: 18, height: 18)
            } else if let icon {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(c.icon)
                    .frame(width: 18, height: 18)
            }
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(c.text)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(c.fill, in: shape)
        .overlay { shape.stroke(c.stroke, lineWidth: 0.75) }
    }

    /// 重算路線：獨立一列、整列可按（不收進折疊——它是動作，不是說明）
    private func retryNotice(_ count: Int, pal: TripBoardPalette) -> some View {
        let c = pal.notice(.info)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let text = "有 \(count) 段沒拿到真實路線"
        return Button(action: actions.retryRouting) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(c.icon)
                    .frame(width: 18, height: 18)
                Text(text)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(c.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("重新計算")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(c.button, in: Capsule())
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(c.fill, in: shape)
            .overlay { shape.stroke(c.stroke, lineWidth: 0.75) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityHint("點兩下重新計算路線")
        .accessibilityAddTraits(.isButton)
    }

    /// 趕不上：設計稿那一條橘色、右邊有 ∨ 的列。點開列出是哪幾站，點一站打開它的景點卡
    /// （景點卡是 sheet，那一天在時間軸上收合著也打得開）。
    private func lateNotice(_ late: [TripBoardLate], pal: TripBoardPalette) -> some View {
        let c = pal.notice(.late)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let headline = "有 \(late.count) 站的指定抵達時間比推算的還早，照這個排法趕不上"
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { lateOpen.toggle() }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(c.icon)
                        .frame(width: 18, height: 18)
                    Text(headline)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(c.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(c.text)
                        .rotationEffect(.degrees(lateOpen ? 180 : 0))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(pal.dark ? 0.10 : 0.7)))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(headline)
            .accessibilityHint(lateOpen ? "點兩下收起" : "點兩下列出是哪幾站")
            .accessibilityAddTraits(.isButton)
            if lateOpen {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(late) { item in
                        lateRow(item, c: c)
                    }
                }
                .padding(.leading, 26)
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(c.fill, in: shape)
        .overlay { shape.stroke(c.stroke, lineWidth: 0.75) }
    }

    private func lateRow(_ item: TripBoardLate, c: TripBoardPalette.Notice) -> some View {
        let a11y = item.title + "，" + item.detail
        return VStack(spacing: 0) {
            Rectangle().fill(c.stroke).frame(height: 0.75)
            Button {
                actions.openStop(item.stopId)
            } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(c.text)
                            .lineLimit(1)
                        Text(item.detail)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(c.text.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(c.icon)
                }
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11y)
            .accessibilityHint("點兩下打開這一站的景點卡")
            .accessibilityAddTraits(.isButton)
        }
    }
}

/// 格子、進度卡共用的外框：半透明的底、細框、淡淡的陰影（陰影掛在裁切外面）
struct TripBoardCellChrome: ViewModifier {
    let pal: TripBoardPalette
    var radius: CGFloat = 14

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .clipShape(shape)
            .background {
                shape.fill(pal.cellFill)
                    .shadow(color: pal.cellShadow, radius: pal.dark ? 6 : 10, x: 0, y: 3)
            }
            .overlay { shape.stroke(pal.cellStroke, lineWidth: pal.dark ? 0.5 : 0.75) }
    }
}

/// 進度條：漸層的條、頭上一個跟著場景走的小圖示（飛機／車／電車／行人）
struct TripBoardProgressBar: View {
    let fraction: Double
    let icon: String
    let colors: [Color]
    let track: Color
    let iconColor: Color
    let halo: Color

    var body: some View {
        GeometryReader { geo in
            bar(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }

    private func bar(width w: CGFloat, height h: CGFloat) -> some View {
        let head = max(7, min(w - 7, w * CGFloat(fraction)))
        return ZStack(alignment: .leading) {
            Capsule().fill(track).frame(height: 8)
            Capsule()
                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .frame(width: max(8, head), height: 8)
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(iconColor)
                .shadow(color: halo, radius: 1.5)
                .position(x: head, y: h / 2)
        }
        .frame(width: w, height: h)
    }
}

// MARK: - 標頭

/// 量到的文字範圍。插畫照它讓位：手寫字、客機、航廈、月亮都不壓到字。
struct TripBoardTextRects: Equatable {
    var date: CGRect = .zero
    var capsule: CGRect = .zero
    var time: CGRect = .zero
    var span: CGRect = .zero
}

/// 標頭裡幾段字的位置，傳給背後的天空（做法同 TripChipRowAnchorKey）
struct TripBoardAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 標頭：出發日、大字時間、跨天，背後是天空插畫。
struct TripBoardHeader: View {
    let data: TripBoardData
    let sign: String?
    let openChecklist: () -> Void
    @Environment(\.colorScheme) private var scheme

    init(data: TripBoardData, sign: String?, openChecklist: @escaping () -> Void) {
        self.data = data
        self.sign = sign
        self.openChecklist = openChecklist
    }

    /// 天際線那一條的高度。樓與地標只畫在這一條裡，**不長到上面那幾行字的後面**
    static let band: CGFloat = 30

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 0) {
            // 字放很大時日期與行前準備膠囊排不下一列，膠囊改到日期下面
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 0) {
                    departLabel(pal)
                        .fixedSize()
                        .anchorPreference(key: TripBoardAnchorKey.self, value: .bounds) { ["date": $0] }
                    Spacer(minLength: 8)
                    checklistButton(pal)
                        .anchorPreference(key: TripBoardAnchorKey.self, value: .bounds) { ["capsule": $0] }
                }
                VStack(alignment: .leading, spacing: 0) {
                    departLabel(pal)
                        .anchorPreference(key: TripBoardAnchorKey.self, value: .bounds) { ["date": $0] }
                    checklistButton(pal)
                        .anchorPreference(key: TripBoardAnchorKey.self, value: .bounds) { ["capsule": $0] }
                }
            }
            bigTime(pal)
                .anchorPreference(key: TripBoardAnchorKey.self, value: .bounds) { ["time": $0] }
                .padding(.top, 2)
            // 只寫 14:40 → 15:29 的話，跨天行程看起來像當天來回
            if let span = data.spanText {
                Text(span)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(pal.inkDate)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .anchorPreference(key: TripBoardAnchorKey.self, value: .bounds) { ["span": $0] }
            }
            Color.clear.frame(height: Self.band)
        }
        .padding(.top, 10)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .backgroundPreferenceValue(TripBoardAnchorKey.self) { anchors in
            GeometryReader { geo in
                sky(geo: geo, anchors: anchors, dark: pal.dark)
            }
        }
    }

    private func sky(geo: GeometryProxy, anchors: [String: Anchor<CGRect>], dark: Bool) -> some View {
        var rects = TripBoardTextRects()
        if let a = anchors["date"] { rects.date = geo[a] }
        if let a = anchors["capsule"] { rects.capsule = geo[a] }
        if let a = anchors["time"] { rects.time = geo[a] }
        if let a = anchors["span"] { rects.span = geo[a] }
        return TripBoardSkyArt(dark: dark, scene: data.scene, landmarks: data.landmarks,
                               sign: sign, seed: data.seed, rects: rects, band: Self.band)
            .equatable()
    }

    /// 「✈ 10/3 (週六) 出發」。有飛機段才畫起飛的飛機（開車環島畫飛機是假的），
    /// 其他用出發的旗子（跟第一站的「出發」膠囊同一個圖示）。
    private func departLabel(_ pal: TripBoardPalette) -> some View {
        HStack(spacing: 6) {
            Image(systemName: data.scene == .flight ? "airplane.departure" : "flag.fill")
                .font(.footnote.weight(.bold))
            Text(data.departText)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(pal.inkDate)
        .accessibilityElement(children: .combine)
    }

    /// 行前準備（v25.451）：左邊是預設交通方式、右邊是清單進度，整顆可按。
    /// 外觀 28 高，上下各多 4pt 的點擊範圍。
    private func checklistButton(_ pal: TripBoardPalette) -> some View {
        let total = data.checklistTotal
        let progress = "\(data.checklistDone)/\(total)"
        var a11y = "行前準備，交通方式" + data.travelMode.rawValue
        if total > 0 { a11y += "，清單 " + progress }
        return Button(action: openChecklist) {
            HStack(spacing: 6) {
                Image(systemName: data.travelMode.icon)
                    .font(.caption.weight(.bold))
                Text(data.travelMode.rawValue)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Rectangle()
                    .fill(pal.capsuleText.opacity(0.3))
                    .frame(width: 0.75, height: 12)
                Image(systemName: "checklist")
                    .font(.caption.weight(.bold))
                if total > 0 {
                    Text(progress)
                        .font(.caption.weight(.bold).monospacedDigit())
                }
            }
            .fixedSize()
            .foregroundStyle(pal.capsuleText)
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .background(pal.capsuleFill, in: Capsule())
            .overlay { Capsule().stroke(pal.capsuleStroke, lineWidth: 0.75) }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
        .accessibilityHint("點兩下打開行前準備清單")
        .accessibilityAddTraits(.isButton)
    }

    /// 大字「15:10 → 14:30」。箭頭不是破折號（設計稿）。字級固定 40、不跟著系統字級放大：
    /// 行前準備膠囊搬到日期那一列之後，三種寬度的手機都不用縮。
    @ViewBuilder
    private func bigTime(_ pal: TripBoardPalette) -> some View {
        if let start = data.timeStart, let end = data.timeEnd {
            let a11y = start + " 出發，" + end + " 結束"
            HStack(alignment: .center, spacing: 6) {
                Text(start)
                Image(systemName: "arrow.right")
                    .font(.system(size: 20, weight: .bold))
                Text(end)
            }
            .font(.system(size: 40, weight: .heavy, design: .rounded))
            .foregroundStyle(pal.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11y)
        } else {
            Text("尚未加入景點")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(pal.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - 標頭的天空插畫

/// 天空、雲、天際線（含地標）、場景（客機＋航廈／公路／高架鐵道／步道）、手寫字。
///
/// Equatable＋.equatable()：Canvas 的閉包比不出有沒有變，不擋的話行程頁每次重算
/// （橫幅、正在計算路線…）都會重畫一次帶模糊的雲。輸入都是值，相同就不重畫。
struct TripBoardSkyArt: View, Equatable {
    let dark: Bool
    let scene: TripBoardScene
    let landmarks: [TripLandmark]
    let sign: String?
    let seed: Int
    let rects: TripBoardTextRects
    let band: CGFloat

    var body: some View {
        Canvas { ctx, size in
            Self.paint(&ctx, size: size, art: self)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 航廈的骨架。屋頂往右升高（近大遠小：左邊是遠的那一端）
struct TripBoardTerminalFrame {
    let x0: CGFloat
    let x1: CGFloat
    /// 左端（遠端）牆高
    let leftHeight: CGFloat
    /// 屋頂每往右 1pt 升高多少
    let slope: CGFloat
    /// 屋簷那一條深色帶的厚度（招牌寫在這裡）
    let eave: CGFloat

    func roofY(_ x: CGFloat, ground: CGFloat) -> CGFloat {
        ground - leftHeight - (x - x0) * slope
    }

    /// 屋簷帶的左端：比牆往左出挑 8pt
    var eaveLeft: CGFloat { x0 - 8 }

    /// 航廈讓出來的界線：屋簷左端再往左 4pt。近排的樓、客機的機頭都停在這條線左邊。
    var clearLeft: CGFloat { eaveLeft - 4 }
}

/// [v25.519] 天際線（遠排＋近排的樓）的色票。
///
/// 原本 paintFarRow／paintNearRow 用 dark: Bool 寫死兩組顏色；時間軸卡片的底帶要照
/// 「那一站的時段」換樓的顏色（清晨、傍晚、深夜各一組），畫法跟看板同一支，所以把顏色抽出來。
/// 看板傳 .boardDay／.boardNight，值跟原本一模一樣；亂數的取用次數也跟原本一樣
/// （遠排的燈看 farLight、近排的窗看 lit，跟原本看 dark 的分支一一對應），所以看板一筆都不會變。
struct TripSkylineInk: Equatable {
    /// 夜裡亮著的窗：每一格以 rate 的機率亮，亮的裡面 warmShare 是暖色、其餘冷色
    struct Lit: Equatable {
        let rate: Double
        let warm: Color
        let cool: Color
        let warmShare: Double
    }

    /// 遠排：淡、矮、密
    let far: Color
    /// 遠排偶爾一兩顆燈（夜裡）。nil＝不點燈
    let farLight: Color?
    /// 近排的樓色，依序輪流（夜裡兩色交替，白天一色）
    let near: [Color]
    /// 白天每棟左邊那條亮邊（玻璃反光，寬 25%）。nil＝不畫
    let glint: Color?
    /// 白天的窗線（短虛線）。nil＝不畫
    let windowLine: Color?
    /// 夜裡亮燈的窗。有值就走夜裡的畫法（亮窗），沒有就走白天的（亮邊＋窗線）
    let lit: Lit?

    /// 看板白天（＝原本 dark == false 的顏色）
    static let boardDay = TripSkylineInk(
        far: Color(tb: 0xB4CCE6, 0.75), farLight: nil,
        near: [Color(tb: 0x87A9D1, 0.95)],
        glint: Color.white.opacity(0.35), windowLine: Color.white.opacity(0.28),
        lit: nil)

    /// 看板夜裡（＝原本 dark == true 的顏色）
    static let boardNight = TripSkylineInk(
        far: Color(tb: 0x1A2550), farLight: Color(tb: 0xFFCF7A, 0.55),
        near: [Color(tb: 0x0E1730), Color(tb: 0x16234A)],
        glint: nil, windowLine: nil,
        lit: Lit(rate: 0.3, warm: Color(tb: 0xFFC56B), cool: Color(tb: 0x9ED8FF), warmShare: 0.72))

    static func board(dark: Bool) -> TripSkylineInk { dark ? .boardNight : .boardDay }
}

extension TripBoardSkyArt {
    static func paint(_ ctx: inout GraphicsContext, size: CGSize, art a: TripBoardSkyArt) {
        let w = size.width
        let ground = size.height
        guard w > 160, ground > 70 else { return }
        let r = a.rects
        let bandTop = ground - a.band
        /// 日期列（含膠囊）的底
        let headTop = max(r.date.maxY, r.capsule.maxY)
        let avoid = [r.date, r.capsule, r.time, r.span]
            .filter { !$0.isEmpty }
            .map { $0.insetBy(dx: -4, dy: -3) }

        paintSky(&ctx, size: size, dark: a.dark)
        if a.dark {
            paintStars(&ctx, width: w, bottom: bandTop - 6, avoid: avoid, seed: a.seed)
            paintMoon(&ctx, rects: r)
        }
        paintClouds(&ctx, width: w, ground: ground, bandTop: bandTop, dark: a.dark)

        // 右邊的場景先佔位置，近排的樓讓開
        let term: TripBoardTerminalFrame? = a.scene == .flight
            ? terminalFrame(width: w, ground: ground, band: a.band, headTop: headTop)
            : nil
        let skyline = TripSkylineInk.board(dark: a.dark)
        paintFarRow(&ctx, width: w, ground: ground, band: a.band, ink: skyline, seed: a.seed)
        let landmarkLimit = min(term.map { $0.x0 - 10 } ?? w, w * 0.62)
        var reserved = paintLandmarks(&ctx, marks: a.landmarks, width: w, ground: ground,
                                      band: a.band, limit: landmarkLimit, dark: a.dark, seed: a.seed)
        if let term {
            reserved.append(term.clearLeft...(w + 4))
        } else if a.scene == .drive {
            reserved.append((w * 0.56)...(w + 4))
        }
        paintNearRow(&ctx, width: w, ground: ground, band: a.band, ink: skyline,
                     seed: a.seed, reserved: reserved)
        paintTrees(&ctx, width: w, ground: ground, dark: a.dark, seed: a.seed, reserved: reserved)

        switch a.scene {
        case .flight:
            if let term {
                terminal(&ctx, frame: term, ground: ground, sign: a.sign, signSize: 9, dark: a.dark)
                // 機頭停在航廈左邊，不伸進航廈（v25.519）。原本伸進航廈四成寬，機頭剛好蓋住
                // 招牌開頭的兩三個字（「FUKUOKA」只讀得到「KUOKA」）。招牌最寬是屋簷的 82%、
                // 置中，左緣不會比 x0 − 2.1 更左；機頭停在 x0 − 12，離招牌字至少 9pt，
                // 不用量字、什麼城市名都一樣。
                paintAirliner(&ctx, width: w, ground: ground, rects: r,
                              rightLimit: term.clearLeft, dark: a.dark)
            }
        case .drive:
            paintRoad(&ctx, width: w, ground: ground, band: a.band, rects: r, sign: a.sign, dark: a.dark)
        case .rail:
            paintRail(&ctx, width: w, ground: ground, band: a.band, rects: r, sign: a.sign, dark: a.dark)
        case .walk:
            paintWalk(&ctx, width: w, ground: ground, band: a.band, rects: r, sign: a.sign, dark: a.dark)
        }

        // 手寫字：大字時間的右邊、日期列的下面；有航廈時不壓到屋頂
        let left = r.time.isEmpty ? w * 0.55 : r.time.maxX + 10
        let bottom = r.time.isEmpty ? bandTop - 4 : r.time.maxY
        var right = w - 10
        if let term {
            let roofAtStart = term.roofY(term.x0, ground: ground)
            if roofAtStart <= bottom + 2 {
                right = min(right, term.x0 - 6)
            } else if term.slope > 0 {
                right = min(right, term.x0 + (roofAtStart - bottom - 2) / term.slope)
            }
        }
        let region = CGRect(x: left, y: headTop + 2, width: max(0, right - left),
                            height: max(0, bottom - headTop - 2))
        // 航線尾端的小圖示：右上角，膠囊下面、屋頂上面
        var target: CGPoint? = CGPoint(x: min(w - 22, region.maxX + 18), y: headTop + 10)
        if let t = target {
            if r.capsule.insetBy(dx: -6, dy: -4).contains(t) { target = nil }
            if let term, t.y > term.roofY(t.x + 12, ground: ground) - 8 { target = nil }
        }
        paintScript(&ctx, region: region, target: target, dark: a.dark, icon: a.scene.icon)
    }

    // MARK: 天空

    // [v25.519] 天空的幾個色抽成具名常數：時間軸卡片「下午」的天空、深色模式「晚上」的夜空、
    // 夜裡底帶的地平線暖光直接拿這幾個色，不另外抄一份 hex。
    /// 白天天空的中段（設計稿的晴藍）
    static let dayHigh = Color(tb: 0xBEE4FF)
    /// 白天天空靠近地平線那一段
    static let dayLow = Color(tb: 0xE1F1FE)
    /// 夜空的天頂
    static let nightZenith = Color(tb: 0x0A1433)
    /// 夜裡城市的燈把地平線染開的暖色
    static let horizonGlow = Color(tb: 0xFF9A4D)

    static func paintSky(_ ctx: inout GraphicsContext, size: CGSize, dark: Bool) {
        let stops: [Gradient.Stop]
        if dark {
            stops = [Gradient.Stop(color: nightZenith, location: 0),
                     Gradient.Stop(color: Color(tb: 0x13224A), location: 0.5),
                     Gradient.Stop(color: Color(tb: 0x18264E), location: 0.82),
                     Gradient.Stop(color: Color(tb: 0x121B38), location: 1)]
        } else {
            stops = [Gradient.Stop(color: Color(tb: 0x8FD3FF), location: 0),
                     Gradient.Stop(color: dayHigh, location: 0.45),
                     Gradient.Stop(color: dayLow, location: 0.82),
                     Gradient.Stop(color: Color(tb: 0xEAF4FD), location: 1)]
        }
        let rect = Path(CGRect(origin: .zero, size: size))
        ctx.fill(rect, with: .linearGradient(Gradient(stops: stops), startPoint: .zero,
                                             endPoint: CGPoint(x: 0, y: size.height)))
        if dark {
            // 地平線一層暖光：城市的燈把下緣染開
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 14))
                layer.fill(Path(CGRect(x: 0, y: size.height - 26, width: size.width, height: 26)),
                           with: .color(horizonGlow.opacity(0.16)))
            }
        } else {
            // 右上的日光（不畫太陽：太陽會變成一個要看的東西）
            ctx.fill(rect, with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0)]),
                center: CGPoint(x: size.width * 0.80, y: 0),
                startRadius: 0, endRadius: size.width * 0.6))
        }
    }

    /// count：撒幾顆（落在 avoid 裡的那幾顆直接跳過，所以畫出來的會少一點）。
    /// [v25.519] 時間軸夜晚的卡片也用這一支，只撒 8～12 顆；看板維持 34。
    static func paintStars(_ ctx: inout GraphicsContext, width w: CGFloat, bottom: CGFloat,
                           avoid: [CGRect], seed: Int, count: Int = 34) {
        guard bottom > 10, count > 0 else { return }
        var r = InkRandom(seed &* 31 &+ 7)
        for i in 0..<count {
            let p = CGPoint(x: CGFloat(r.next()) * w, y: 3 + CGFloat(r.next()) * (bottom - 3))
            let radius = CGFloat(0.4 + r.next() * 0.7)
            let alpha = 0.35 + r.next() * 0.55
            if avoid.contains(where: { $0.contains(p) }) { continue }
            if i % 12 == 0 {
                // 幾顆四芒星
                let s = radius * 3.2
                var spark = Path()
                spark.move(to: CGPoint(x: p.x, y: p.y - s))
                spark.addLine(to: CGPoint(x: p.x + s * 0.22, y: p.y - s * 0.22))
                spark.addLine(to: CGPoint(x: p.x + s, y: p.y))
                spark.addLine(to: CGPoint(x: p.x + s * 0.22, y: p.y + s * 0.22))
                spark.addLine(to: CGPoint(x: p.x, y: p.y + s))
                spark.addLine(to: CGPoint(x: p.x - s * 0.22, y: p.y + s * 0.22))
                spark.addLine(to: CGPoint(x: p.x - s, y: p.y))
                spark.addLine(to: CGPoint(x: p.x - s * 0.22, y: p.y - s * 0.22))
                spark.closeSubpath()
                ctx.fill(spark, with: .color(Color.white.opacity(alpha)))
            } else {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius,
                                                width: radius * 2, height: radius * 2)),
                         with: .color(Color.white.opacity(alpha)))
            }
        }
    }

    /// 月牙：放在日期與膠囊之間的空檔。空檔不夠就不畫（不壓到字）
    static func paintMoon(_ ctx: inout GraphicsContext, rects r: TripBoardTextRects) {
        guard !r.date.isEmpty, !r.capsule.isEmpty, r.capsule.minY < r.date.maxY else { return }
        let gapL = r.date.maxX + 14
        let gapR = r.capsule.minX - 14
        guard gapR - gapL >= 18 else { return }
        let c = CGPoint(x: (gapL + gapR) / 2, y: r.date.midY)
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            layer.fill(Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18)),
                       with: .color(Color(tb: 0xF4EBC8, 0.35)))
        }
        var moon = ctx.resolve(Image(systemName: "moon.fill"))
        moon.shading = .color(Color(tb: 0xF4EBC8))
        ctx.draw(moon, in: CGRect(x: c.x - 6.5, y: c.y - 6.5, width: 13, height: 13))
    }

    // MARK: 雲

    /// 一朵雲：扁圓角矩形當雲底，上面四顆圓（同方向的路徑，填色就是聯集）。底是平的。
    static func cloud(center c: CGPoint, width w: CGFloat) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: c.x - w * 0.5, y: c.y - w * 0.02, width: w, height: w * 0.14),
                         cornerSize: CGSize(width: w * 0.07, height: w * 0.07))
        let bumps: [(CGFloat, CGFloat)] = [(-0.28, 0.13), (-0.06, 0.2), (0.17, 0.16), (0.34, 0.1)]
        for (dx, k) in bumps {
            let rr = w * k
            p.addEllipse(in: CGRect(x: c.x + w * dx - rr, y: c.y + w * 0.12 - rr * 2,
                                    width: rr * 2, height: rr * 2))
        }
        return p
    }

    static func paintClouds(_ ctx: inout GraphicsContext, width w: CGFloat, ground: CGFloat,
                            bandTop: CGFloat, dark: Bool) {
        let fill = dark ? Color(tb: 0x2A3A66, 0.5) : Color.white.opacity(0.92)
        // 遠的兩朵：貼在地平線上、糊開、淡
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            layer.opacity = 0.6
            layer.fill(cloud(center: CGPoint(x: w * 0.24, y: bandTop - 2), width: w * 0.34), with: .color(fill))
            layer.fill(cloud(center: CGPoint(x: w * 0.66, y: bandTop - 8), width: w * 0.26), with: .color(fill))
        }
        // 近的兩朵：上方中間、航廈上面
        let near: [(CGPoint, CGFloat)] = [
            (CGPoint(x: w * 0.47, y: ground * 0.14), w * 0.18),
            (CGPoint(x: w * 0.93, y: ground * 0.40), w * 0.15)
        ]
        for (c, cw) in near {
            let path = cloud(center: c, width: cw)
            ctx.fill(path, with: .color(fill))
            if !dark {
                // 雲的下緣一層淡藍的影子
                ctx.fill(path, with: .linearGradient(
                    Gradient(colors: [Color(tb: 0xC9DDF0, 0), Color(tb: 0xC9DDF0, 0.55)]),
                    startPoint: CGPoint(x: 0, y: c.y - cw * 0.1),
                    endPoint: CGPoint(x: 0, y: c.y + cw * 0.12)))
            }
        }
    }

    // MARK: 天際線

    /// 遠排：淡、矮、密
    ///
    /// [v25.519] 顏色改吃 TripSkylineInk（時間軸卡片的底帶也用這一支）。
    /// ⚠️ 亂數的取用順序不能動：夜裡點燈那一步原本是 `dark && r.next() > 0.6`（白天短路、不取亂數），
    ///    現在是 `farLight != nil` 才取——看板的 .boardDay 沒有 farLight、.boardNight 有，一一對應。
    static func paintFarRow(_ ctx: inout GraphicsContext, width w: CGFloat, ground: CGFloat,
                            band: CGFloat, ink: TripSkylineInk, seed: Int) {
        var r = InkRandom(seed &* 7 &+ 3)
        let fill = ink.far
        var x: CGFloat = -4
        while x < w + 4 {
            let bw = CGFloat(5 + r.next() * 10)
            let roll = r.next()
            let tall: CGFloat = roll > 0.82 ? 1 : (roll > 0.45 ? 0.6 : 0.35)
            let h = min(band * 0.75, 6 + tall * CGFloat(r.next()) * band * 0.6)
            let rect = CGRect(x: x, y: ground - h, width: bw, height: h)
            ctx.fill(Path(rect), with: .color(fill))
            if let light = ink.farLight, r.next() > 0.6 {
                // 遠處只點一兩顆燈
                let wy = rect.minY + 2 + CGFloat(r.next()) * max(1, h - 5)
                ctx.fill(Path(CGRect(x: rect.minX + bw * 0.4, y: wy, width: 1.2, height: 1.4)),
                         with: .color(light))
            }
            x += bw + CGFloat(r.next() * 3)
        }
    }

    /// 近排：深、高、疏。白天每棟左邊一條亮邊（玻璃反光）；夜裡窗戶亮燈
    /// （七成琥珀、三成冷藍，跟原本霓虹城市的窗是同一個比例）
    ///
    /// [v25.519] 顏色改吃 TripSkylineInk。⚠️ 走哪一個分支看 `ink.lit`（原本看 dark）：
    ///    夜裡的分支每一格窗都取一次亂數、白天的分支不取，分支一換亂數序列就整個不一樣。
    static func paintNearRow(_ ctx: inout GraphicsContext, width w: CGFloat, ground: CGFloat,
                             band: CGFloat, ink: TripSkylineInk, seed: Int,
                             reserved: [ClosedRange<CGFloat>]) {
        var r = InkRandom(seed &* 13 &+ 5)
        var x: CGFloat = -2
        var i = 0
        let palette = ink.near.isEmpty ? [ink.far] : ink.near
        while x < w {
            let bw = CGFloat(7 + r.next() * 12)
            if reserved.contains(where: { $0.overlaps(x...(x + bw)) }) {
                x += bw + 2
                continue
            }
            let roll = r.next()
            let tall: CGFloat = roll > 0.8 ? 1 : (roll > 0.42 ? 0.62 : 0.34)
            let h = min(band - 3, 8 + tall * CGFloat(r.next()) * (band - 6))
            let rect = CGRect(x: x, y: ground - h, width: bw, height: h)
            ctx.fill(Path(rect), with: .color(palette[i % palette.count]))
            if let lit = ink.lit {
                var wy = rect.minY + 2.5
                while wy < ground - 2.5 {
                    var wx = rect.minX + 1.8
                    while wx < rect.maxX - 2.4 {
                        if r.next() < lit.rate {
                            let warm = r.next() < lit.warmShare
                            let alpha = 0.5 + r.next() * 0.4
                            ctx.fill(Path(CGRect(x: wx, y: wy, width: 1.4, height: 1.8)),
                                     with: .color((warm ? lit.warm : lit.cool).opacity(alpha)))
                        }
                        wx += 3.2
                    }
                    wy += 3.6
                }
            } else {
                if let glint = ink.glint {
                    ctx.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: bw * 0.25, height: h)),
                             with: .color(glint))
                }
                if let windowLine = ink.windowLine {
                    var wy = rect.minY + 3
                    while wy < ground - 3 {
                        var line = Path()
                        line.move(to: CGPoint(x: rect.minX + 2, y: wy))
                        line.addLine(to: CGPoint(x: rect.maxX - 2, y: wy))
                        ctx.stroke(line, with: .color(windowLine),
                                   style: StrokeStyle(lineWidth: 0.6, dash: [1.4, 1.6]))
                        wy += 4
                    }
                }
            }
            x += bw + CGFloat(1 + r.next() * 4)
            i += 1
        }
    }

    /// 目的地的地標（鳥居、福岡塔、斜張橋、101…），在左邊 16～22% 起排。回傳佔掉的範圍
    static func paintLandmarks(_ ctx: inout GraphicsContext, marks: [TripLandmark], width w: CGFloat,
                               ground: CGFloat, band: CGFloat, limit: CGFloat, dark: Bool,
                               seed: Int) -> [ClosedRange<CGFloat>] {
        var reserved: [ClosedRange<CGFloat>] = []
        var r = InkRandom(seed &+ 101)
        var lx = w * CGFloat(0.16 + r.next() * 0.06)
        for m in marks {
            let span = m.span
            if lx + span > limit { break }
            // 頂端比天際線那一條的上緣低 2pt：不長到「跨 N 天」那一行後面
            let path = m.outline(x: lx, ground: ground, height: band + 2)
            if m.isSolid {
                ctx.fill(path, with: .color(landmarkFill(m, dark: dark)))
                if dark && m != .torii {
                    ctx.stroke(path, with: .color(Color(tb: 0x7FD3FF, 0.55)), lineWidth: 0.6)
                }
            } else {
                ctx.stroke(path, with: .color(dark ? Color(tb: 0x7FD3FF, 0.75) : Color(tb: 0x5F7FB0, 0.9)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            }
            if dark && m == .torii {
                // 鳥居下一盞燈籠
                let c = CGPoint(x: lx + 10, y: ground - band * 0.3)
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 3))
                    layer.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)),
                               with: .color(Color(tb: 0xFFB45E, 0.6)))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 1.6, y: c.y - 2, width: 3.2, height: 4)),
                         with: .color(Color(tb: 0xFFB45E)))
            }
            reserved.append((lx - 3)...(lx + span + 3))
            lx += span + CGFloat(14 + r.next() * 16)
        }
        return reserved
    }

    static func landmarkFill(_ m: TripLandmark, dark: Bool) -> Color {
        if m == .torii { return dark ? Color(tb: 0xB23A2E) : Color(tb: 0xE0483A) }
        return dark ? Color(tb: 0x24356A) : Color(tb: 0x6F8FBF)
    }

    static func paintTrees(_ ctx: inout GraphicsContext, width w: CGFloat, ground: CGFloat,
                           dark: Bool, seed: Int, reserved: [ClosedRange<CGFloat>]) {
        var r = InkRandom(seed &+ 211)
        let color = dark ? Color(tb: 0x0F2A2A) : Color(tb: 0x7FB37A)
        for _ in 0..<5 {
            let x = w * CGFloat(0.02 + r.next() * 0.5)
            let s = CGFloat(3 + r.next() * 2.5)
            if reserved.contains(where: { $0.contains(x) }) { continue }
            var p = Path()
            p.addEllipse(in: CGRect(x: x - s, y: ground - s * 1.6, width: s * 2, height: s * 1.7))
            p.addEllipse(in: CGRect(x: x - s * 1.8, y: ground - s * 1.1, width: s * 1.6, height: s * 1.1))
            p.addEllipse(in: CGRect(x: x + s * 0.3, y: ground - s * 1.2, width: s * 1.6, height: s * 1.2))
            ctx.fill(p, with: .color(color))
        }
    }

    // MARK: 手寫字

    /// 「Have / a nice trip!」轉 −8°，底下一道收筆線，再從「Have」的尾巴拉一條虛線航線
    /// 到右上的小圖示。字級從 20 試到 13，放得下的最大那一級；13 還放不下（375 寬、
    /// 又有航廈時）就不寫——不硬縮成看不清楚的字。
    /// 440 寬的手機上，大字時間右邊只有約 104×48pt（下面是客機、右邊是航廈），
    /// 實際大概落在 15pt；設計稿上那一句本來就是小字。
    static func paintScript(_ ctx: inout GraphicsContext, region: CGRect, target: CGPoint?,
                            dark: Bool, icon: String) {
        guard region.width >= 60, region.height >= 26 else { return }
        let color = dark ? Color(tb: 0xCFE0FF, 0.8) : Color.white.opacity(0.92)
        let angle = -8.0
        let rad = angle * Double.pi / 180
        let cosA = CGFloat(cos(rad))
        let sinA = CGFloat(sin(rad))
        let measureBox = CGSize(width: 600, height: 200)
        for size: CGFloat in [20, 18, 16, 15, 14, 13] {
            let l1 = ctx.resolve(Text("Have").font(TripScriptFont.greeting(size)).foregroundStyle(color))
            let l2 = ctx.resolve(Text("a nice trip!").font(TripScriptFont.greeting(size)).foregroundStyle(color))
            let m1 = l1.measure(in: measureBox)
            let m2 = l2.measure(in: measureBox)
            let indent = size * 0.6
            let lineGap = size * 0.78
            let bw = max(m1.width, indent + m2.width)
            let bh = lineGap + m2.height + size * 0.25
            let outerW = bw * abs(cosA) + bh * abs(sinA)
            let outerH = bw * abs(sinA) + bh * abs(cosA)
            guard outerW <= region.width, outerH <= region.height else { continue }
            let cx = region.minX + outerW / 2 + 2
            let cy = region.midY
            let x0 = -bw / 2
            let y0 = -bh / 2
            var g = ctx
            g.translateBy(x: cx, y: cy)
            g.rotate(by: .degrees(angle))
            g.drawLayer { layer in
                layer.addFilter(.shadow(color: Color(tb: 0x0B1B45, dark ? 0.6 : 0.35),
                                        radius: 1.5, x: 0, y: 0.5))
                layer.draw(l1, at: CGPoint(x: x0, y: y0), anchor: .topLeading)
                layer.draw(l2, at: CGPoint(x: x0 + indent, y: y0 + lineGap), anchor: .topLeading)
                var swash = Path()
                let sy = y0 + lineGap + m2.height * 0.92
                swash.move(to: CGPoint(x: x0 + indent * 0.6, y: sy + 1))
                swash.addQuadCurve(to: CGPoint(x: x0 + bw, y: sy - size * 0.2),
                                   control: CGPoint(x: x0 + bw * 0.5, y: sy + size * 0.35))
                layer.stroke(swash, with: .color(color),
                             style: StrokeStyle(lineWidth: max(1, size * 0.06), lineCap: .round))
            }
            if let target {
                let lx = x0 + m1.width + 4
                let ly = y0 + m1.height * 0.55
                let start = CGPoint(x: cx + lx * cosA - ly * sinA, y: cy + lx * sinA + ly * cosA)
                if target.x > start.x + 12 {
                    TripCardSkyline.drawTrail(
                        &ctx, from: start, to: target,
                        control: CGPoint(x: (start.x + target.x) / 2, y: min(start.y, target.y) - 8),
                        color: color.opacity(0.85), lineWidth: 1,
                        icon: icon, iconColor: dark ? Color(tb: 0xCFE0FF) : Color(tb: 0x1D3A7A, 0.85),
                        iconSize: 13, iconAngle: icon == "airplane" ? -20 : 0)
                }
            }
            return
        }
    }
}

// MARK: - 場景：航廈與客機

extension TripBoardSkyArt {
    /// 航廈貼在卡片右緣、超出卡外的部分讓卡片自己裁掉。
    /// 右端屋頂不高過日期列（不壓到行前準備膠囊）。
    static func terminalFrame(width w: CGFloat, ground: CGFloat, band: CGFloat,
                              headTop: CGFloat) -> TripBoardTerminalFrame {
        let tw = min(78, max(56, w * 0.17))
        let left = band + 6
        let rise = max(0, ground - left - (headTop + 8))
        return TripBoardTerminalFrame(x0: w - tw, x1: w + 2, leftHeight: left,
                                      slope: min(0.45, rise / tw), eave: 13)
    }

    /// 玻璃帷幕航廈：深色屋簷帶（招牌寫在這裡）＋玻璃牆＋越遠越密的豎框。
    ///
    /// 招牌**不寫在玻璃上**：白字直接壓在淺藍玻璃上只有 1.85～2.53:1，讀不太到；
    /// 壓在屋簷的深色帶上是 7.85:1。字是裝飾（城市名），可以畫進 Canvas。
    /// 夜裡玻璃是亮著燈的暖色，豎框變深色，招牌帶一圈暖光。
    static func terminal(_ ctx: inout GraphicsContext, frame f: TripBoardTerminalFrame,
                         ground: CGFloat, sign: String?, signSize: CGFloat, dark: Bool) {
        let width = f.x1 - f.x0
        guard width > 20 else { return }
        let eaveL = CGPoint(x: f.eaveLeft, y: f.roofY(f.eaveLeft, ground: ground))
        let eaveR = CGPoint(x: f.x1, y: f.roofY(f.x1, ground: ground))
        let wallL = f.roofY(f.x0, ground: ground) + f.eave
        let wallR = eaveR.y + f.eave

        // 玻璃牆
        var glass = Path()
        glass.move(to: CGPoint(x: f.x0, y: wallL))
        glass.addLine(to: CGPoint(x: f.x1, y: wallR))
        glass.addLine(to: CGPoint(x: f.x1, y: ground))
        glass.addLine(to: CGPoint(x: f.x0, y: ground))
        glass.closeSubpath()
        let glassColors = dark
            ? [Color(tb: 0xFFD58A, 0.85), Color(tb: 0xE39A3E, 0.85)]
            : [Color(tb: 0xA9CDEE), Color(tb: 0x5F8DBB)]
        ctx.fill(glass, with: .linearGradient(Gradient(colors: glassColors),
                                              startPoint: CGPoint(x: 0, y: wallR),
                                              endPoint: CGPoint(x: 0, y: ground)))
        if dark {
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 6))
                layer.fill(Path(CGRect(x: f.x0 - 6, y: ground - 6, width: width + 6, height: 6)),
                           with: .color(Color(tb: 0xFFD58A, 0.35)))
            }
        } else {
            // 一道斜的反光（裁進玻璃牆）
            var g = ctx
            g.clip(to: glass)
            var shine = Path()
            shine.move(to: CGPoint(x: f.x0 + width * 0.10, y: ground))
            shine.addLine(to: CGPoint(x: f.x0 + width * 0.26, y: ground))
            shine.addLine(to: CGPoint(x: f.x0 + width * 0.62, y: wallR - 4))
            shine.addLine(to: CGPoint(x: f.x0 + width * 0.46, y: wallR - 4))
            shine.closeSubpath()
            g.fill(shine, with: .color(Color.white.opacity(0.22)))
        }

        // 豎框：越往左（越遠）越密
        let mullion = dark ? Color(tb: 0x0E1730, 0.75) : Color.white.opacity(0.5)
        let denom = 1 - pow(0.86, 9.0)
        for i in 1..<9 {
            let t = CGFloat((1 - pow(0.86, Double(i))) / denom)
            let x = f.x1 - width * t
            var m = Path()
            m.move(to: CGPoint(x: x, y: f.roofY(x, ground: ground) + f.eave))
            m.addLine(to: CGPoint(x: x, y: ground))
            ctx.stroke(m, with: .color(mullion), lineWidth: dark ? 0.9 : 0.8)
        }
        // 樓板線，跟著透視
        for t: CGFloat in [0.38, 0.70] {
            var floor = Path()
            floor.move(to: CGPoint(x: f.x0, y: wallL + (ground - wallL) * t))
            floor.addLine(to: CGPoint(x: f.x1, y: wallR + (ground - wallR) * t))
            ctx.stroke(floor, with: .color(mullion), lineWidth: 0.7)
        }
        // 入口雨庇
        ctx.fill(Path(CGRect(x: f.x0 + width * 0.18, y: ground - 7, width: width * 0.3, height: 1.6)),
                 with: .color(dark ? Color(tb: 0x1B2440) : Color(tb: 0x3E5370)))

        // 屋簷帶（往左出挑 8pt）
        var eave = Path()
        eave.move(to: eaveL)
        eave.addLine(to: eaveR)
        eave.addLine(to: CGPoint(x: eaveR.x, y: eaveR.y + f.eave))
        eave.addLine(to: CGPoint(x: eaveL.x, y: eaveL.y + f.eave))
        eave.closeSubpath()
        ctx.fill(eave, with: .color(dark ? Color(tb: 0x1B2440) : Color(tb: 0x3E5370)))

        // 招牌：量寬度、縮到屋簷帶的 82% 以內；縮到 0.55 倍還放不下就不寫
        guard let sign, !sign.isEmpty else { return }
        let text = ctx.resolve(Text(sign)
            .font(.system(size: signSize, weight: .heavy))
            .tracking(signSize * 0.08)
            .foregroundStyle(Color.white))
        let m = text.measure(in: CGSize(width: 1000, height: 100))
        let scale = min(1, (width + 8) * 0.82 / max(1, m.width))
        guard scale >= 0.55 else { return }
        let cx = eaveL.x + (eaveR.x - eaveL.x) * 0.5
        var g = ctx
        g.translateBy(x: cx, y: f.roofY(cx, ground: ground) + f.eave / 2)
        // 斜率跟屋頂一樣：字的底線順著屋簷往右升
        g.concatenate(CGAffineTransform(a: 1, b: -f.slope, c: 0, d: 1, tx: 0, ty: 0))
        g.scaleBy(x: scale, y: scale)
        if dark {
            let glow = ctx.resolve(Text(sign)
                .font(.system(size: signSize, weight: .heavy))
                .tracking(signSize * 0.08)
                .foregroundStyle(Color(tb: 0xFFD58A)))
            g.drawLayer { layer in
                layer.addFilter(.blur(radius: 2.5))
                layer.draw(glow, at: .zero, anchor: .center)
            }
        }
        g.draw(text, at: .zero, anchor: .center)
    }

    /// 客機的位置：大字時間下面、「跨 N 天」那一行的右邊，機頭朝右上起飛。
    /// 機尾那一端如果落在大字時間的範圍裡，整架往下放，不壓到字。
    /// 機頭尖端就在 rightLimit（差不到 1pt），右邊不會再有機身；夜裡的落地燈光錐會往右照出去。
    static func paintAirliner(_ ctx: inout GraphicsContext, width w: CGFloat, ground: CGFloat,
                              rects r: TripBoardTextRects, rightLimit: CGFloat, dark: Bool) {
        let textBottom = r.time.isEmpty ? ground * 0.5 : r.time.maxY
        let leftLimit = max(w * 0.40, r.span.isEmpty ? 0 : r.span.maxX + 12)
        let room = ground - 1 - (textBottom - 2)
        let length = min(120, rightLimit - leftLimit, room / 42 * 120)
        guard length >= 54 else { return }
        let k = length / 120
        let lo = textBottom - 2 + 17 * k
        let hi = ground - 1 - 25 * k
        let centerY = min(hi, max(lo, (textBottom + ground) / 2 + 2))
        drawAirliner(&ctx, center: CGPoint(x: rightLimit - length / 2, y: centerY),
                     length: length, angle: -13, moving: true, dark: dark)
    }

    /// 側面的客機（機頭朝右，局部座標全長 120）。不仿任何真實航空公司的塗裝。
    /// 夜裡：月光下的機身、亮著的窗、近側翼尖綠燈（機頭朝右時面對我們的是右側）、
    /// 遠側翼尖紅燈、機尾白燈，起飛時機頭前方一道落地燈的光錐。
    static func drawAirliner(_ ctx: inout GraphicsContext, center: CGPoint, length: CGFloat,
                             angle: Double, moving: Bool, dark: Bool) {
        let k = length / 120
        var g = ctx
        g.translateBy(x: center.x, y: center.y)
        g.rotate(by: .degrees(angle))
        g.scaleBy(x: k, y: k)
        g.translateBy(x: -60, y: -7)

        if moving {
            // 速度線（機尾後面）
            for i in 0..<3 {
                var s = Path()
                let y = CGFloat(-1 + i * 6)
                s.move(to: CGPoint(x: -6, y: y))
                s.addLine(to: CGPoint(x: -26 - CGFloat(i) * 9, y: y))
                g.stroke(s, with: .color(Color.white.opacity(dark ? 0.14 : 0.32)),
                         style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        }
        if dark && moving {
            var cone = Path()
            cone.move(to: CGPoint(x: 100, y: 15))
            cone.addLine(to: CGPoint(x: 190, y: 34))
            cone.addLine(to: CGPoint(x: 176, y: 54))
            cone.closeSubpath()
            g.fill(cone, with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0)]),
                startPoint: CGPoint(x: 100, y: 15), endPoint: CGPoint(x: 185, y: 44)))
        }

        // 遠側主翼（在機身後面）
        var farWing = Path()
        farWing.move(to: CGPoint(x: 52, y: 8))
        farWing.addLine(to: CGPoint(x: 40, y: -1))
        farWing.addLine(to: CGPoint(x: 45, y: -1.5))
        farWing.addLine(to: CGPoint(x: 66, y: 8))
        farWing.closeSubpath()
        g.fill(farWing, with: .color(dark ? Color(tb: 0x6E7FA6) : Color(tb: 0xC9D4E2)))

        // 垂直尾翼
        var fin = Path()
        fin.move(to: CGPoint(x: 6, y: 6.5))
        fin.addLine(to: CGPoint(x: -2, y: -15))
        fin.addLine(to: CGPoint(x: 6, y: -15))
        fin.addLine(to: CGPoint(x: 26, y: 6))
        fin.closeSubpath()
        g.fill(fin, with: .color(dark ? Color(tb: 0x3A4F86) : Color(tb: 0x2F6BD8)))

        // 機身
        var body = Path()
        body.move(to: CGPoint(x: 10, y: 6))
        body.addLine(to: CGPoint(x: 98, y: 5))
        body.addCurve(to: CGPoint(x: 120, y: 10.5),
                      control1: CGPoint(x: 110, y: 5), control2: CGPoint(x: 119, y: 7))
        body.addCurve(to: CGPoint(x: 100, y: 16),
                      control1: CGPoint(x: 119, y: 13.5), control2: CGPoint(x: 112, y: 16))
        body.addLine(to: CGPoint(x: 18, y: 16))
        body.addCurve(to: CGPoint(x: 0, y: 7.5),
                      control1: CGPoint(x: 10, y: 16), control2: CGPoint(x: 4, y: 13))
        body.addLine(to: CGPoint(x: 4, y: 6.5))
        body.closeSubpath()
        let skin = dark ? [Color(tb: 0xC9D3E6), Color(tb: 0x6E7FA6)] : [Color.white, Color(tb: 0xDCE4EE)]
        g.fill(body, with: .linearGradient(Gradient(colors: skin),
                                           startPoint: CGPoint(x: 0, y: 5), endPoint: CGPoint(x: 0, y: 16)))
        g.stroke(body, with: .color(dark ? Color(tb: 0x55648A) : Color(tb: 0xB9C6D6)), lineWidth: 0.5)

        // 機腰一條色帶
        var cheat = Path()
        cheat.move(to: CGPoint(x: 14, y: 12.2))
        cheat.addLine(to: CGPoint(x: 100, y: 12))
        g.stroke(cheat, with: .color(dark ? Color(tb: 0x3A4F86, 0.9) : Color(tb: 0x2F6BD8, 0.8)), lineWidth: 0.9)

        // 窗列（夜裡是亮的）
        var windows = Path()
        windows.move(to: CGPoint(x: 30, y: 9))
        windows.addLine(to: CGPoint(x: 95, y: 8.3))
        g.stroke(windows, with: .color(dark ? Color(tb: 0xFFD58A) : Color(tb: 0x33415C)),
                 style: StrokeStyle(lineWidth: 1.6, dash: [1.4, 1.8]))

        // 駕駛艙
        var cockpit = Path()
        cockpit.move(to: CGPoint(x: 104, y: 8))
        cockpit.addLine(to: CGPoint(x: 110, y: 8.2))
        cockpit.addLine(to: CGPoint(x: 112.5, y: 10))
        cockpit.addLine(to: CGPoint(x: 105, y: 10))
        cockpit.closeSubpath()
        g.fill(cockpit, with: .color(Color(tb: 0x22304A)))

        // 水平尾翼
        var stab = Path()
        stab.move(to: CGPoint(x: 8, y: 10))
        stab.addLine(to: CGPoint(x: -3, y: 13.5))
        stab.addLine(to: CGPoint(x: 3, y: 14))
        stab.addLine(to: CGPoint(x: 20, y: 11))
        stab.closeSubpath()
        g.fill(stab, with: .color(dark ? Color(tb: 0x8C9AC0) : Color(tb: 0xDCE4EE)))

        // 近側主翼與發動機
        var wing = Path()
        wing.move(to: CGPoint(x: 46, y: 12))
        wing.addLine(to: CGPoint(x: 30, y: 27))
        wing.addLine(to: CGPoint(x: 38, y: 28))
        wing.addLine(to: CGPoint(x: 70, y: 13))
        wing.closeSubpath()
        g.fill(wing, with: .color(dark ? Color(tb: 0x8C9AC0) : Color(tb: 0xE8EEF5)))
        g.stroke(wing, with: .color(dark ? Color(tb: 0x55648A) : Color(tb: 0xB9C6D6)), lineWidth: 0.5)
        let engine = Path(roundedRect: CGRect(x: 40, y: 17, width: 18, height: 7), cornerRadius: 3.5)
        g.fill(engine, with: .color(dark ? Color(tb: 0x7A88AE) : Color(tb: 0xD5DCE6)))
        g.fill(Path(ellipseIn: CGRect(x: 55.5, y: 17.5, width: 3, height: 6)),
               with: .color(dark ? Color(tb: 0x3A4566) : Color(tb: 0x8A97AA)))

        // 起落架
        var gear = Path()
        gear.move(to: CGPoint(x: 54, y: 16))
        gear.addLine(to: CGPoint(x: 54, y: 21))
        gear.move(to: CGPoint(x: 84, y: 16))
        gear.addLine(to: CGPoint(x: 84, y: 20))
        g.stroke(gear, with: .color(Color(tb: 0x4A5568)), lineWidth: 1)
        g.fill(Path(ellipseIn: CGRect(x: 52.4, y: 20.4, width: 3.2, height: 3.2)), with: .color(Color(tb: 0x2A3142)))
        g.fill(Path(ellipseIn: CGRect(x: 82.4, y: 19.4, width: 3.2, height: 3.2)), with: .color(Color(tb: 0x2A3142)))

        if dark {
            let lights: [(CGPoint, CGFloat, Color)] = [
                (CGPoint(x: 31, y: 27.5), 1.6, Color(tb: 0x34C759)),
                (CGPoint(x: 41, y: -1.2), 1.2, Color(tb: 0xFF3B30)),
                (CGPoint(x: -1.5, y: -14.5), 1.2, Color.white)
            ]
            for (p, radius, color) in lights {
                g.drawLayer { layer in
                    layer.addFilter(.blur(radius: 2))
                    layer.fill(Path(ellipseIn: CGRect(x: p.x - radius * 2.5, y: p.y - radius * 2.5,
                                                      width: radius * 5, height: radius * 5)),
                               with: .color(color.opacity(0.6)))
                }
                g.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius,
                                              width: radius * 2, height: radius * 2)),
                       with: .color(color))
            }
        }
    }

    // MARK: 場景：公路（開車）

    /// 往天際線收的透視公路、中線虛線、一台車，右邊一座門架綠色路標「→ 城市」
    /// （日本和台灣的高速公路路標都是綠底白字）。夜裡：車燈、暖黃的中線。
    static func paintRoad(_ ctx: inout GraphicsContext, width w: CGFloat, ground: CGFloat,
                          band: CGFloat, rects r: TripBoardTextRects, sign: String?, dark: Bool) {
        let horizon = ground - band * 0.62
        let vx = w * 0.80
        var road = Path()
        road.move(to: CGPoint(x: w * 0.54, y: ground))
        road.addLine(to: CGPoint(x: w * 1.06, y: ground))
        road.addLine(to: CGPoint(x: vx + 5, y: horizon))
        road.addLine(to: CGPoint(x: vx - 5, y: horizon))
        road.closeSubpath()
        let asphalt = dark ? [Color(tb: 0x2A3352), Color(tb: 0x1A2140)] : [Color(tb: 0xC2CCD8), Color(tb: 0x96A4B6)]
        ctx.fill(road, with: .linearGradient(Gradient(colors: asphalt),
                                             startPoint: CGPoint(x: 0, y: horizon),
                                             endPoint: CGPoint(x: 0, y: ground)))
        var edges = Path()
        edges.move(to: CGPoint(x: w * 0.54, y: ground))
        edges.addLine(to: CGPoint(x: vx - 5, y: horizon))
        edges.move(to: CGPoint(x: w * 1.06, y: ground))
        edges.addLine(to: CGPoint(x: vx + 5, y: horizon))
        ctx.stroke(edges, with: .color(Color.white.opacity(dark ? 0.35 : 0.6)), lineWidth: 1)
        var mid = Path()
        mid.move(to: CGPoint(x: vx, y: ground))
        mid.addLine(to: CGPoint(x: vx, y: horizon))
        ctx.stroke(mid, with: .color(dark ? Color(tb: 0xFFD36B, 0.85) : Color.white.opacity(0.9)),
                   style: StrokeStyle(lineWidth: 1.2, dash: [4, 3.5]))

        // 車（迎面開來）
        let car = CGRect(x: w * 0.66, y: ground - 13, width: 15, height: 12)
        if dark {
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.fill(Path(ellipseIn: CGRect(x: car.minX - 2, y: car.maxY - 5, width: car.width + 4, height: 6)),
                           with: .color(Color(tb: 0xFFE7A3, 0.7)))
            }
        }
        var carImage = ctx.resolve(Image(systemName: "car.fill"))
        carImage.shading = .color(dark ? Color(tb: 0xC9D3E6) : Color(tb: 0x2F6BD8))
        ctx.draw(carImage, in: car)

        // 門架路標
        let signW = min(86, w * 0.27)
        let signH: CGFloat = 16
        let top = max(r.time.maxY + 3, r.capsule.maxY + 4)
        guard top + signH <= ground - 8 else { return }
        let sx = min(w - signW / 2 - 8, max(w * 0.80, r.time.maxX + 8 + signW / 2))
        let board = CGRect(x: sx - signW / 2, y: top, width: signW, height: signH)
        let post = dark ? Color(tb: 0x3A4566) : Color(tb: 0x6B7A90)
        ctx.fill(Path(CGRect(x: board.minX - 2, y: top, width: 1.6, height: ground - top)), with: .color(post))
        ctx.fill(Path(CGRect(x: board.maxX + 0.4, y: top, width: 1.6, height: ground - top)), with: .color(post))
        let plate = Path(roundedRect: board, cornerRadius: 2)
        ctx.fill(plate, with: .color(dark ? Color(tb: 0x23905A) : Color(tb: 0x1E7A46)))
        ctx.stroke(plate, with: .color(Color.white.opacity(0.8)), lineWidth: 0.8)
        let label = sign.map { "→ " + $0 } ?? "→"
        drawSignText(&ctx, label, in: board.insetBy(dx: 3, dy: 1), size: 8.5, color: .white)
    }

    // MARK: 場景：高架鐵道（大眾運輸）

    /// 天際線底下一排高架，上面一列電車（圓鼻、窗帶），右邊一塊白底站名牌。
    /// 夜裡車窗亮著。
    static func paintRail(_ ctx: inout GraphicsContext, width w: CGFloat, ground: CGFloat,
                          band: CGFloat, rects r: TripBoardTextRects, sign: String?, dark: Bool) {
        let deckY = ground - band * 0.42
        let startX = w * 0.44
        let concrete = dark ? Color(tb: 0x2A3560) : Color(tb: 0x8FA6C4)
        ctx.fill(Path(CGRect(x: startX, y: deckY, width: w - startX + 4, height: 3)), with: .color(concrete))
        var px = startX + 6
        while px < w {
            ctx.fill(Path(CGRect(x: px, y: deckY + 3, width: 2.4, height: ground - deckY - 3)),
                     with: .color(concrete.opacity(0.85)))
            px += 16
        }
        // 站名牌在右端，電車停在它左邊
        let bw = min(60, w * 0.18)
        let bh: CGFloat = 15
        let bx = w - bw - 8
        let by = max(deckY - bh - 9, r.capsule.maxY + 4)
        let trainLeft = startX + 6
        let trainRight = bx - 6
        let length = min(120, trainRight - trainLeft)
        if length > 30 {
            let tx = trainRight - length
            let top = deckY - 11
            var train = Path()
            train.move(to: CGPoint(x: tx + 8, y: top))
            train.addLine(to: CGPoint(x: tx + length, y: top))
            train.addLine(to: CGPoint(x: tx + length, y: deckY - 0.5))
            train.addLine(to: CGPoint(x: tx, y: deckY - 0.5))
            train.addQuadCurve(to: CGPoint(x: tx + 8, y: top), control: CGPoint(x: tx, y: top + 1))
            train.closeSubpath()
            ctx.fill(train, with: .color(dark ? Color(tb: 0x9AA6C6) : Color(tb: 0xF4F7FB)))
            ctx.stroke(train, with: .color(dark ? Color(tb: 0x55648A) : Color(tb: 0x9AAFC8)), lineWidth: 0.6)
            ctx.fill(Path(CGRect(x: tx + 4, y: deckY - 4, width: length - 4, height: 1.6)),
                     with: .color(Color(tb: 0x2F6BD8)))
            var windows = Path()
            windows.move(to: CGPoint(x: tx + 10, y: top + 3.5))
            windows.addLine(to: CGPoint(x: tx + length - 3, y: top + 3.5))
            ctx.stroke(windows, with: .color(dark ? Color(tb: 0xFFD58A) : Color(tb: 0x33415C)),
                       style: StrokeStyle(lineWidth: 2.6, dash: [3.5, 1.8]))
        }
        guard by + bh <= deckY else { return }
        let post = dark ? Color(tb: 0x3A4566) : Color(tb: 0x6B7A90)
        ctx.fill(Path(CGRect(x: bx + 6, y: by + bh, width: 1.4, height: deckY - by - bh)), with: .color(post))
        ctx.fill(Path(CGRect(x: bx + bw - 7.4, y: by + bh, width: 1.4, height: deckY - by - bh)), with: .color(post))
        let board = CGRect(x: bx, y: by, width: bw, height: bh)
        let plate = Path(roundedRect: board, cornerRadius: 1.5)
        ctx.fill(plate, with: .color(dark ? Color(tb: 0xF2EEDC) : Color.white))
        ctx.stroke(plate, with: .color(Color(tb: 0x22304A)), lineWidth: 0.8)
        ctx.fill(Path(CGRect(x: bx + 1, y: by + bh - 3, width: bw - 2, height: 1.5)), with: .color(Color(tb: 0x2F6BD8)))
        if let sign {
            drawSignText(&ctx, sign, in: CGRect(x: bx + 2, y: by + 1, width: bw - 4, height: bh - 4),
                         size: 7.5, color: Color(tb: 0x22304A))
        }
    }

    // MARK: 場景：步道（步行）

    /// 點狀的步道、一根指路牌（寫城市名）、一盞路燈。夜裡路燈亮著。
    static func paintWalk(_ ctx: inout GraphicsContext, width w: CGFloat, ground: CGFloat,
                          band: CGFloat, rects r: TripBoardTextRects, sign: String?, dark: Bool) {
        var path = Path()
        path.move(to: CGPoint(x: w * 0.58, y: ground))
        path.addQuadCurve(to: CGPoint(x: w * 0.84, y: ground - band * 0.55),
                          control: CGPoint(x: w * 0.9, y: ground - 2))
        ctx.stroke(path, with: .color(dark ? Color(tb: 0x4A5A86) : Color(tb: 0x8FA3BE)),
                   style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [0.1, 3.5]))
        var walker = ctx.resolve(Image(systemName: "figure.walk"))
        walker.shading = .color(dark ? Color(tb: 0xC9D3E6) : Color(tb: 0x4A5B8C))
        ctx.draw(walker, in: CGRect(x: w * 0.66, y: ground - 15, width: 10, height: 13))

        // 路燈
        let lx = w - 10
        let lampTop = ground - min(44, band + 14)
        let pole = dark ? Color(tb: 0x3A4566) : Color(tb: 0x5B6B85)
        ctx.fill(Path(CGRect(x: lx - 0.8, y: lampTop, width: 1.6, height: ground - lampTop)), with: .color(pole))
        if dark {
            ctx.fill(Path(CGRect(origin: .zero, size: CGSize(width: w, height: ground))),
                     with: .radialGradient(Gradient(colors: [Color(tb: 0xFFD58A, 0.45), Color(tb: 0xFFD58A, 0)]),
                                           center: CGPoint(x: lx - 3, y: lampTop + 2),
                                           startRadius: 0, endRadius: 16))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: lx - 6, y: lampTop - 1, width: 6, height: 4)),
                 with: .color(dark ? Color(tb: 0xFFE7A3) : Color(tb: 0x5B6B85)))

        // 指路牌（指向左邊、往城市的方向）
        let bw: CGFloat = min(64, w * 0.2)
        let px = max(w * 0.86, r.time.maxX + bw + 6)
        let top = max(r.time.maxY + 2, r.capsule.maxY + 4)
        guard px < w - 14, top + 16 <= ground - 8 else { return }
        let wood = dark ? Color(tb: 0x6B4A2A) : Color(tb: 0xB07A45)
        ctx.fill(Path(CGRect(x: px - 1, y: top, width: 2, height: ground - top)), with: .color(wood.opacity(0.9)))
        var board = Path()
        board.move(to: CGPoint(x: px + 4, y: top + 2))
        board.addLine(to: CGPoint(x: px - bw + 6, y: top + 2))
        board.addLine(to: CGPoint(x: px - bw, y: top + 9))
        board.addLine(to: CGPoint(x: px - bw + 6, y: top + 16))
        board.addLine(to: CGPoint(x: px + 4, y: top + 16))
        board.closeSubpath()
        ctx.fill(board, with: .color(wood))
        if let sign {
            drawSignText(&ctx, sign, in: CGRect(x: px - bw + 6, y: top + 3, width: bw - 8, height: 12),
                         size: 7.5, color: .white)
        }
    }

    /// 招牌上的字：量寬度、縮進框裡；縮到 0.55 倍還放不下就不寫
    static func drawSignText(_ ctx: inout GraphicsContext, _ s: String, in rect: CGRect,
                             size: CGFloat, color: Color) {
        let text = ctx.resolve(Text(s).font(.system(size: size, weight: .bold)).foregroundStyle(color))
        let m = text.measure(in: CGSize(width: 1000, height: 100))
        let scale = min(1, rect.width / max(1, m.width), rect.height / max(1, m.height))
        guard scale >= 0.55 else { return }
        var g = ctx
        g.translateBy(x: rect.midX, y: rect.midY)
        g.scaleBy(x: scale, y: scale)
        g.draw(text, at: .zero, anchor: .center)
    }
}

/// 「現在在」膠囊右半邊：站名是機場時畫小一號的航廈＋停在前面的客機（跟看板頂端同一支畫法）
struct TripBoardAirportArt: View, Equatable {
    let dark: Bool
    let sign: String

    var body: some View {
        Canvas { ctx, size in
            Self.paint(&ctx, size: size, dark: dark, sign: sign)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func paint(_ ctx: inout GraphicsContext, size: CGSize, dark: Bool, sign: String) {
        let w = size.width
        let h = size.height
        guard w > 60, h > 20 else { return }
        let ground = h - 5
        // 停機坪
        ctx.fill(Path(CGRect(x: 0, y: ground, width: w, height: h - ground)),
                 with: .color(dark ? Color(tb: 0x1A2342) : Color(tb: 0xD5E0EC)))
        let left = h * 0.36
        let frame = TripBoardTerminalFrame(x0: w * 0.34, x1: w + 2, leftHeight: left,
                                           slope: min(0.35, left / (w * 0.66)), eave: 9)
        TripBoardSkyArt.terminal(&ctx, frame: frame, ground: ground, sign: sign, signSize: 6.5, dark: dark)
        TripBoardSkyArt.drawAirliner(&ctx, center: CGPoint(x: w * 0.36, y: ground - 8),
                                     length: min(64, w * 0.44), angle: 0, moving: false, dark: dark)
    }
}

// MARK: - 數字格子

/// 一列的字要縮多少、時長要不要斷成兩行（同一列的格子用同一個比例）
struct TripBoardFit {
    let scale: CGFloat
    let twoLines: Bool
}

/// 3×2 的數字格子＋相本／花費兩格寬的入口。
///
/// 格數會變（單日沒有「天數」、沒過夜沒有「住宿」、沒照片沒有「相本」、沒花費沒有「花費」），
/// 照語意分列，不留空格占位：
///   第一列「行程樣貌」：景點、天數?、住宿?（3 格排 3 欄；2 格各佔半寬）
///   第二列「時間與距離」：停留、交通、距離
///   只有景點一格（單日、沒過夜）：四格排成 2×2
///   入口：相本、花費各半寬；只有一個就佔滿整列
/// 字放很大時（375／393 寬從 xxLarge、440 寬從輔助第 1 級）改成每列 2 格、入口每列 1 格。
///
/// ⚠️ 放不放得下一行**用 UIFont 量**，不用 ViewThatFits：ViewThatFits 看的是沒縮放前的寬度，
///    440 寬的「42 小時 20 分」（自然寬 75、可用 71）會被它判成放不下而斷行。
struct TripBoardGrid: View {
    let stats: [TripBoardStat]
    let art: TripBoardArt
    let album: TripBoardAlbum?
    let spend: TripBoardSpend?
    let cardWidth: CGFloat
    let openAlbum: () -> Void
    let openExpenses: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    // 數字跟著 .title3、單位跟著 .footnote 放大（外面夾在 xxxLarge 以內）。
    // 要宣告在這個 struct 裡：夾字級的 .dynamicTypeSize 掛在這一層外面，
    // 寫在 TripPlanDetailView 上的話讀到的是沒被夾的那一層。
    @ScaledMetric(relativeTo: .title3) private var vShort: CGFloat = 17
    @ScaledMetric(relativeTo: .title3) private var vLong: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var uShort: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote) private var uLong: CGFloat = 11

    init(stats: [TripBoardStat], art: TripBoardArt, album: TripBoardAlbum?, spend: TripBoardSpend?,
         cardWidth: CGFloat, openAlbum: @escaping () -> Void, openExpenses: @escaping () -> Void) {
        self.stats = stats
        self.art = art
        self.album = album
        self.spend = spend
        self.cardWidth = cardWidth
        self.openAlbum = openAlbum
        self.openExpenses = openExpenses
    }

    private static let gap: CGFloat = 6

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let cw = max(240, cardWidth - 20)
        let limit: DynamicTypeSize = cw >= 380 ? .accessibility1 : .xxLarge
        let threeUp = typeSize < limit
        let rows = Self.rows(stats, threeUp: threeUp)
        VStack(spacing: Self.gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                statRow(row, cw: cw, pal: pal)
            }
            if album != nil || spend != nil {
                entryRows(cw: cw, threeUp: threeUp, pal: pal)
            }
        }
    }

    static func rows(_ stats: [TripBoardStat], threeUp: Bool) -> [[TripBoardStat]] {
        func pairs(_ list: [TripBoardStat]) -> [[TripBoardStat]] {
            stride(from: 0, to: list.count, by: 2).map { Array(list[$0..<min($0 + 2, list.count)]) }
        }
        guard threeUp else { return pairs(stats) }
        let shape = stats.filter { $0.kind.isShape }
        let time = stats.filter { !$0.kind.isShape }
        if shape.count <= 1 { return pairs(shape + time) }
        return [shape, time].filter { !$0.isEmpty }
    }

    /// 小格的圖示圓：375 寬 26、393 寬 28、440 寬 30
    private static func iconSize(_ cw: CGFloat) -> CGFloat {
        cw < 330 ? 26 : (cw < 365 ? 28 : 30)
    }

    private func sizes(_ kind: TripBoardStat.Kind) -> (v: CGFloat, u: CGFloat) {
        kind.isShape ? (v: vShort, u: uShort) : (v: vLong, u: uLong)
    }

    private func statRow(_ row: [TripBoardStat], cw: CGFloat, pal: TripBoardPalette) -> some View {
        let n = CGFloat(max(1, row.count))
        let width = (cw - Self.gap * (n - 1)) / n
        let icon: CGFloat = row.count >= 3 ? Self.iconSize(cw) : 34
        let textWidth = width - 10 - icon - 8 - 6
        let fit = fitRow(row, textWidth: textWidth)
        return HStack(spacing: Self.gap) {
            ForEach(row) { stat in
                statCell(stat, width: width, icon: icon, fit: fit, pal: pal)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 一行放得下就不縮；差一點（≥ 0.92 倍）整列一起縮；再放不下，時長在「小時」後面斷成兩行。
    private func fitRow(_ row: [TripBoardStat], textWidth: CGFloat) -> TripBoardFit {
        let avail = max(20, textWidth) * 0.97
        let one = row.map { width($0.parts, kind: $0.kind) }.max() ?? 0
        if one <= avail { return TripBoardFit(scale: 1, twoLines: false) }
        if one * 0.92 <= avail { return TripBoardFit(scale: avail / one, twoLines: false) }
        let two = row.map { s -> CGFloat in
            if s.kind.canBreak && s.parts.count == 2 {
                return max(width([s.parts[0]], kind: s.kind), width([s.parts[1]], kind: s.kind))
            }
            return width(s.parts, kind: s.kind)
        }.max() ?? 0
        return TripBoardFit(scale: min(1, avail / max(1, two)), twoLines: true)
    }

    private func width(_ parts: [TripBoardValuePart], kind: TripBoardStat.Kind) -> CGFloat {
        let s = sizes(kind)
        return Self.measure(parts, v: s.v, u: s.u)
    }

    /// 數字 SF Rounded Bold、單位 Semibold，中間 2pt。中文字型的退回由系統處理。
    static func measure(_ parts: [TripBoardValuePart], v: CGFloat, u: CGFloat) -> CGFloat {
        let base = UIFont.systemFont(ofSize: v, weight: .bold)
        let numberFont = base.fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: v) } ?? base
        let unitFont = UIFont.systemFont(ofSize: u, weight: .semibold)
        var total: CGFloat = 0
        var tokens = 0
        for p in parts {
            total += (p.number as NSString).size(withAttributes: [.font: numberFont]).width
            tokens += 1
            if !p.unit.isEmpty {
                total += (p.unit as NSString).size(withAttributes: [.font: unitFont]).width
                tokens += 1
            }
        }
        return ceil(total + CGFloat(max(0, tokens - 1)) * 2)
    }

    private func statCell(_ s: TripBoardStat, width: CGFloat, icon: CGFloat, fit: TripBoardFit,
                          pal: TripBoardPalette) -> some View {
        let size = sizes(s.kind)
        let v = size.v * fit.scale
        let u = size.u * fit.scale
        let lines: [[TripBoardValuePart]] = (fit.twoLines && s.kind.canBreak && s.parts.count == 2)
            ? [[s.parts[0]], [s.parts[1]]]
            : [s.parts]
        let a11y = s.label + " " + TripBoardValue.spoken(s.parts)
        return HStack(spacing: 8) {
            TripBoardIconBadge(icon: s.kind.icon, colors: pal.badge(s.kind.tint),
                               diameter: icon, dark: pal.dark)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    TripBoardValueText(parts: line, v: v, u: u, color: pal.ink)
                }
                Text(s.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(pal.label)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        // 寬度交給 HStack 分（同一列一樣寬）；width 只拿來算縮放與插圖框。
        // 釘死成 width 的話，width 一算錯（iPad 第一次排版）格子就會把看板撐得比 sheet 還寬
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 54, maxHeight: .infinity)
        .background(alignment: .bottomTrailing) {
            cellArt(s.kind, width: width, pal: pal)
        }
        .modifier(TripBoardCellChrome(pal: pal))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }

    /// 右下角那一小塊插圖（看得到、不給讀；數字一律是上面的 Text）
    @ViewBuilder
    private func cellArt(_ kind: TripBoardStat.Kind, width: CGFloat, pal: TripBoardPalette) -> some View {
        if kind == .nights, let url = art.stayPhotoURL {
            // 住宿：過夜那一站自己的照片（跟時間軸主圖同一個快取，不會再解碼一次）。
            // 檔名有、檔案讀不到（還在 iCloud、這台裝置上沒有）就退回向量的床，不留一塊空白；
            // 左邊的淡出只套在照片上，床跟沒有照片時畫得一模一樣
            TripBoardPhoto(url: url, fade: 0.6, fallback: AnyView(cellInk(kind, width: width, pal: pal)))
                .frame(width: (width * 0.42).rounded())
                .frame(maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            cellInk(kind, width: width, pal: pal)
        }
    }

    private func cellInk(_ kind: TripBoardStat.Kind, width: CGFloat, pal: TripBoardPalette) -> some View {
        let box = Self.artBox(cellWidth: width)
        return TripBoardCellInk(kind: kind, art: art, dark: pal.dark)
            .frame(width: box.width, height: box.height)
            .opacity(pal.dark ? 0.6 : 0.8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// 小格 44～52 × 38～40；半寬以上的格子 56～70 × 50
    static func artBox(cellWidth w: CGFloat) -> CGSize {
        if w > 150 { return CGSize(width: min(70, (w * 0.36).rounded()), height: 50) }
        return CGSize(width: w < 108 ? 44 : (w < 118 ? 46 : 52), height: w < 118 ? 38 : 40)
    }

    // MARK: 相本／花費

    @ViewBuilder
    private func entryRows(cw: CGFloat, threeUp: Bool, pal: TripBoardPalette) -> some View {
        if let album, let spend, threeUp {
            let half = (cw - Self.gap) / 2
            HStack(spacing: Self.gap) {
                albumCell(album, width: half, pal: pal)
                spendCell(spend, width: half, pal: pal)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: Self.gap) {
                if let album { albumCell(album, width: cw, pal: pal) }
                if let spend { spendCell(spend, width: cw, pal: pal) }
            }
        }
    }

    /// 相本（v25.480 起可以點開）：右邊疊這趟的真照片（拍立得的樣子）
    private func albumCell(_ a: TripBoardAlbum, width: CGFloat, pal: TripBoardPalette) -> some View {
        let parts = TripBoardValue.count(a.count, "張")
        // 字那一欄至少要放得下「293 張」與「點開 ›」，剩下的給照片
        let textNeed = max(Self.measure(parts, v: vShort, u: uShort), 44) + 6
        let photoWidth: CGFloat = a.previews.isEmpty
            ? 0 : min(84, max(40, width - 10 - 34 - 10 - 6 - textNeed))
        let side = max(22, min(34, photoWidth * 0.62))
        let a11y = "相本，\(a.count) 張照片"
        return Button(action: openAlbum) {
            HStack(spacing: 10) {
                TripBoardIconBadge(icon: "photo.fill", colors: pal.badge(.violet), diameter: 34, dark: pal.dark)
                VStack(alignment: .leading, spacing: 1) {
                    TripBoardValueText(parts: parts, v: vShort, u: uShort, color: pal.ink)
                    Text("相本")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(pal.label)
                        .lineLimit(1)
                    entryHint("點開", color: pal.hint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if photoWidth > 0 {
                    TripBoardPolaroids(urls: a.previews, side: side)
                        .frame(width: photoWidth, height: 50)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 9)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 66, maxHeight: .infinity)
            .modifier(TripBoardCellChrome(pal: pal))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
        .accessibilityHint("點兩下打開相本")
        .accessibilityAddTraits(.isButton)
    }

    /// 花費（v25.480 起可以點開）。有待確認的支出時提示寫「還有 N 筆待確認」（橘）。
    /// 插圖是一張收據加一枚硬幣：設計稿的行李箱比較像右上角的行前準備，不是錢。
    private func spendCell(_ s: TripBoardSpend, width: CGFloat, pal: TripBoardPalette) -> some View {
        let box = Self.artBox(cellWidth: width)
        let a11y = "花費，" + s.spoken + "，" + s.hint
        var receipt = art
        receipt.receiptLines = s.receiptLines
        receipt.hasWaiting = s.isWaiting
        return Button(action: openExpenses) {
            HStack(spacing: 10) {
                TripBoardIconBadge(icon: "creditcard.fill", colors: pal.badge(.mint), diameter: 34, dark: pal.dark)
                VStack(alignment: .leading, spacing: 1) {
                    TripBoardValueText(parts: s.parts, v: vShort, u: uShort, color: pal.ink)
                    Text("花費")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(pal.label)
                        .lineLimit(1)
                    entryHint(s.hint, color: s.isWaiting ? pal.waiting : pal.hint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 9)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 66, maxHeight: .infinity)
            .background(alignment: .bottomTrailing) {
                TripBoardCellInk(kind: nil, art: receipt, dark: pal.dark)
                    .frame(width: box.width, height: box.height)
                    .opacity(pal.dark ? 0.55 : 0.75)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .modifier(TripBoardCellChrome(pal: pal))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
        .accessibilityHint("點兩下打開這趟的花費")
        .accessibilityAddTraits(.isButton)
    }

    private func entryHint(_ text: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(text)
            Image(systemName: "chevron.right")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// 「42 小時 20 分」：數字大、單位小，基線對齊
struct TripBoardValueText: View {
    let parts: [TripBoardValuePart]
    let v: CGFloat
    let u: CGFloat
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                Text(p.number)
                    .font(.system(size: v, weight: .bold, design: .rounded))
                if !p.unit.isEmpty {
                    Text(p.unit)
                        .font(.system(size: u, weight: .semibold))
                }
            }
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// 彩色的圖示圓，白色圖示
struct TripBoardIconBadge: View {
    let icon: String
    let colors: [Color]
    let diameter: CGFloat
    let dark: Bool

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            if dark {
                Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            }
            Image(systemName: icon)
                .font(.system(size: diameter * 0.44, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: (colors.last ?? .clear).opacity(dark ? 0 : 0.3), radius: 3, x: 0, y: 2)
        .accessibilityHidden(true)
    }
}

/// 使用者自己的照片（住宿格、「現在在」膠囊）。走 TripHeroStore.photo 的預設尺寸：
/// 跟時間軸卡片的主圖是同一個快取 key，捲過時間軸之後這裡直接命中。
///
/// fade：照片左邊從透明淡入，到這個位置（0～1）全不透明；nil 不淡。
/// fallback：讀過一次、讀不到（檔案還在 iCloud、這台裝置上沒有）時畫它，貼右下角、不套淡出；
/// nil 就留空。讀到照片之後 fallback 就收掉。
struct TripBoardPhoto: View {
    let url: URL
    let fade: CGFloat?
    let fallback: AnyView?
    @State private var image: UIImage?
    /// 讀過一次了沒。還沒讀完之前不畫 fallback：有照片的時候才不會先閃一下床
    @State private var tried = false
    /// iCloud 照片晚到時 +1，讓 .task 重跑
    @State private var reloadToken = 0

    init(url: URL, fade: CGFloat? = nil, fallback: AnyView? = nil) {
        self.url = url
        self.fade = fade
        self.fallback = fallback
    }

    var body: some View {
        picture
            .overlay(alignment: .bottomTrailing) {
                if image == nil, tried, let fallback {
                    fallback
                }
            }
            .task(id: url.lastPathComponent + "#\(reloadToken)") {
                let img = await TripHeroStore.shared.photo(url)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    image = img
                    tried = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cloudSyncPhotosDidUpdate)) { _ in
                if image == nil { reloadToken += 1 }
            }
    }

    /// 給多大就多大的框，照片疊上去再裁掉（scaledToFill 的圖回報的尺寸比框大）
    @ViewBuilder
    private var picture: some View {
        let base = Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
        if let fade {
            base.mask {
                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: .black, location: fade)],
                               startPoint: .leading, endPoint: .trailing)
            }
        } else {
            base
        }
    }
}

/// 相本格右邊那疊照片：最多三張，拍立得的白邊、各自轉一點角度，新的那張在最上面
struct TripBoardPolaroids: View {
    let urls: [URL]
    let side: CGFloat

    init(urls: [URL], side: CGFloat) {
        self.urls = urls
        self.side = side
    }

    private static let angles: [Double] = [-9, 4, 11]
    private static let offsets: [CGSize] = [CGSize(width: -6, height: 2),
                                            CGSize(width: 4, height: -4),
                                            CGSize(width: 10, height: 3)]

    var body: some View {
        let n = min(3, urls.count)
        ZStack {
            ForEach(Array((0..<n).reversed()), id: \.self) { i in
                TripBoardPolaroidPhoto(url: urls[i])
                    .frame(width: side, height: side)
                    .clipped()
                    .padding(2.5)
                    .padding(.bottom, 3)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
                    .rotationEffect(.degrees(Self.angles[i]))
                    .offset(Self.offsets[i])
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 拍立得裡的一張。每張自己記有沒有讀到：iCloud 照片晚到時只重讀還沒讀到的那張。
/// （原本整疊掛 .id(reloadToken)，App 裡任何照片同步下來，三張都拆掉重建、一起閃一下灰底。）
/// 換了照片時舊的那張先留著，新的讀到才換（不閃灰底）。
struct TripBoardPolaroidPhoto: View {
    let url: URL
    @State private var image: UIImage?
    /// iCloud 照片晚到時 +1，讓 .task 重跑
    @State private var reloadToken = 0

    init(url: URL) {
        self.url = url
    }

    var body: some View {
        Color(.tertiarySystemFill)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task(id: url.path + "#\(reloadToken)") {
                let img = await ThumbnailCache.shared.thumbnail(for: url, maxPixel: 180)
                guard !Task.isCancelled else { return }
                image = img
            }
            .onReceive(NotificationCenter.default.publisher(for: .cloudSyncPhotosDidUpdate)) { _ in
                if image == nil { reloadToken += 1 }
            }
    }
}

// MARK: - 格子右下角的插圖

/// 每一格右下角那一小塊。全部用這趟自己的資料畫；數字一個都不畫（規矩：「可以被看見，不可以被讀」）。
/// kind == nil 是花費格的收據。
struct TripBoardCellInk: View {
    let kind: TripBoardStat.Kind?
    let art: TripBoardArt
    let dark: Bool

    init(kind: TripBoardStat.Kind?, art: TripBoardArt, dark: Bool) {
        self.kind = kind
        self.art = art
        self.dark = dark
    }

    var body: some View {
        Canvas { ctx, size in
            Self.paint(&ctx, size: size, kind: kind, art: art, dark: dark)
        }
    }

    static func paint(_ ctx: inout GraphicsContext, size: CGSize, kind: TripBoardStat.Kind?,
                      art: TripBoardArt, dark: Bool) {
        guard size.width > 10, size.height > 10 else { return }
        guard let kind else {
            receipt(&ctx, size: size, lines: art.receiptLines, waiting: art.hasWaiting, dark: dark)
            return
        }
        switch kind {
        case .stops:
            landmark(&ctx, size: size, mark: art.landmark, dark: dark)
        case .days:
            calendar(&ctx, size: size, days: art.dayCount, today: art.todayIndex,
                     past: art.pastDays, dark: dark)
        case .nights:
            bed(&ctx, size: size, dark: dark)
        case .dwell:
            clock(&ctx, size: size, ratio: art.dwellRatio, dark: dark)
        case .travel:
            pins(&ctx, size: size, modes: art.modesUsed, dark: dark)
        case .distance:
            route(&ctx, size: size, points: art.route, dark: dark)
        }
    }

    // MARK: 景點：目的地的地標站在山稜線上

    static func landmark(_ ctx: inout GraphicsContext, size: CGSize, mark: TripLandmark?, dark: Bool) {
        let w = size.width
        let h = size.height
        var back = Path()
        back.move(to: CGPoint(x: 0, y: h * 0.72))
        back.addQuadCurve(to: CGPoint(x: w * 0.58, y: h * 0.50), control: CGPoint(x: w * 0.28, y: h * 0.44))
        back.addQuadCurve(to: CGPoint(x: w, y: h * 0.62), control: CGPoint(x: w * 0.84, y: h * 0.46))
        back.addLine(to: CGPoint(x: w, y: h))
        back.addLine(to: CGPoint(x: 0, y: h))
        back.closeSubpath()
        ctx.fill(back, with: .color(dark ? Color(tb: 0x2A3A66) : Color(tb: 0xCFE3F7)))
        var front = Path()
        front.move(to: CGPoint(x: 0, y: h * 0.9))
        front.addQuadCurve(to: CGPoint(x: w, y: h * 0.82), control: CGPoint(x: w * 0.5, y: h * 0.7))
        front.addLine(to: CGPoint(x: w, y: h))
        front.addLine(to: CGPoint(x: 0, y: h))
        front.closeSubpath()
        ctx.fill(front, with: .color(dark ? Color(tb: 0x223058) : Color(tb: 0xB5D3EE)))

        guard let mark else {
            // 目的地切不出來（或沒有對應的地標）：一根圖釘插在山上
            pin(&ctx, tip: CGPoint(x: w * 0.6, y: h * 0.78), color: Color(tb: 0xE0457A, 0.8), size: 11)
            return
        }
        let k = min(1, (w - 6) / mark.span)
        var g = ctx
        g.translateBy(x: (w - mark.span * k) / 2 + w * 0.06, y: 0)
        g.scaleBy(x: k, y: k)
        let path = mark.outline(x: 0, ground: (h * 0.86) / k, height: (h * 0.8) / k)
        if mark.isSolid {
            g.fill(path, with: .color(TripBoardSkyArt.landmarkFill(mark, dark: dark)))
        } else {
            g.stroke(path, with: .color(dark ? Color(tb: 0x7FB2FF) : Color(tb: 0x5F7FB0)),
                     style: StrokeStyle(lineWidth: 1.2 / k, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: 天數：小月曆，格子是每天的顏色（跟時間軸同一套），今天加框、過完的淡掉

    static func calendar(_ ctx: inout GraphicsContext, size: CGSize, days: Int, today: Int?,
                         past: Int, dark: Bool) {
        let n = max(1, min(14, days))
        let rows = n > 7 ? 2 : 1
        let cardW = min(size.width - 2, 42)
        let cardH = min(size.height - 3, rows == 1 ? 24 : 32)
        let x0 = size.width - cardW - 1
        let y0 = size.height - cardH - 1
        let card = Path(roundedRect: CGRect(x: x0, y: y0, width: cardW, height: cardH), cornerRadius: 4)
        ctx.fill(card, with: .color(dark ? Color(tb: 0x2A3560) : Color.white.opacity(0.95)))
        ctx.stroke(card, with: .color(dark ? Color.white.opacity(0.15) : Color(tb: 0xC9D7EA)), lineWidth: 0.6)
        // 上緣一條色帶＋兩個吊環
        var g = ctx
        g.clip(to: card)
        g.fill(Path(CGRect(x: x0, y: y0, width: cardW, height: 5)),
               with: .color(dark ? Color(tb: 0x2F7FE8, 0.8) : Color(tb: 0x4FA6FF, 0.85)))
        for rx in [x0 + cardW * 0.28, x0 + cardW * 0.72] {
            ctx.fill(Path(roundedRect: CGRect(x: rx - 1, y: y0 - 2, width: 2, height: 4.5), cornerRadius: 1),
                     with: .color(dark ? Color(tb: 0x8E9BBF) : Color(tb: 0x6B7A99)))
        }
        let gap: CGFloat = 1.2
        let cell = max(2, min((cardW - 6 - gap * 6) / 7,
                              (cardH - 10 - CGFloat(rows - 1) * gap) / CGFloat(rows)))
        for d in 0..<n {
            let rect = CGRect(x: x0 + 3 + CGFloat(d % 7) * (cell + gap),
                              y: y0 + 7.5 + CGFloat(d / 7) * (cell + gap),
                              width: cell, height: cell)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 1),
                     with: .color(TripDayPalette.color(d).opacity(d < past ? 0.3 : 0.85)))
            if d == today {
                ctx.stroke(Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: 1.5),
                           with: .color(dark ? Color.white : Color(tb: 0x0B1B45)), lineWidth: 1)
            }
        }
    }

    // MARK: 住宿（沒有照片時）：床、枕頭、被子，旁邊一彎月亮

    static func bed(_ ctx: inout GraphicsContext, size: CGSize, dark: Bool) {
        let w = size.width
        let base = size.height - 4
        let x0 = w * 0.18
        let x1 = w - 3
        let frame = dark ? Color(tb: 0x8D7AD6) : Color(tb: 0xA98BEA)
        let sheet = dark ? Color(tb: 0x6B58B8) : Color(tb: 0xC9B6F5)
        ctx.fill(Path(roundedRect: CGRect(x: x0, y: base - 20, width: 4, height: 20), cornerRadius: 1.5),
                 with: .color(frame))
        ctx.fill(Path(roundedRect: CGRect(x: x0 + 2, y: base - 9, width: x1 - x0 - 2, height: 6), cornerRadius: 2),
                 with: .color(sheet))
        ctx.fill(Path(CGRect(x: x1 - 2, y: base - 4, width: 1.6, height: 4)), with: .color(frame))
        ctx.fill(Path(roundedRect: CGRect(x: x0 + 5, y: base - 13.5, width: 9, height: 4.5), cornerRadius: 2),
                 with: .color(Color.white.opacity(dark ? 0.7 : 0.95)))
        ctx.fill(Path(roundedRect: CGRect(x: x0 + 15, y: base - 12, width: x1 - x0 - 15, height: 4), cornerRadius: 1.5),
                 with: .color(frame.opacity(0.8)))
        var moon = ctx.resolve(Image(systemName: "moon.fill"))
        moon.shading = .color(dark ? Color(tb: 0xF4EBC8) : Color(tb: 0xB9A2F0))
        ctx.draw(moon, in: CGRect(x: w * 0.30, y: 2, width: 10, height: 10))
        var star = ctx.resolve(Image(systemName: "sparkle"))
        star.shading = .color(dark ? Color(tb: 0xF4EBC8, 0.8) : Color(tb: 0xB9A2F0, 0.8))
        ctx.draw(star, in: CGRect(x: w * 0.52, y: 4, width: 6, height: 6))
    }

    // MARK: 停留：時鐘，從 12 點順時針填一塊扇形＝停留占（停留＋交通）的比例

    static func clock(_ ctx: inout GraphicsContext, size: CGSize, ratio: Double, dark: Bool) {
        let r = min(size.width, size.height) * 0.42
        let c = CGPoint(x: size.width - r - 3, y: size.height - r - 3)
        let face = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.fill(face, with: .color(dark ? Color(tb: 0x2A3560) : Color.white.opacity(0.95)))
        if ratio > 0 {
            var sector = Path()
            sector.move(to: c)
            sector.addArc(center: c, radius: r - 1.5, startAngle: .degrees(-90),
                          endAngle: .degrees(-90 + 360 * min(1, ratio)), clockwise: false)
            sector.closeSubpath()
            ctx.fill(sector, with: .color(dark ? Color(tb: 0x2FBF71, 0.45) : Color(tb: 0x4CD08A, 0.45)))
        }
        ctx.stroke(face, with: .color(dark ? Color(tb: 0x2F8F5C) : Color(tb: 0x9FD7B5)), lineWidth: 1.2)
        let tick = dark ? Color.white.opacity(0.5) : Color(tb: 0x6B7A99, 0.6)
        for i in 0..<12 {
            let a = Double(i) * Double.pi / 6
            let p1 = CGPoint(x: c.x + (r - 1.5) * CGFloat(cos(a)), y: c.y + (r - 1.5) * CGFloat(sin(a)))
            let p2 = CGPoint(x: c.x + (r - 3.5) * CGFloat(cos(a)), y: c.y + (r - 3.5) * CGFloat(sin(a)))
            var t = Path()
            t.move(to: p1)
            t.addLine(to: p2)
            ctx.stroke(t, with: .color(tick), lineWidth: 0.7)
        }
        // 指針固定在 10:10（這不是要讀的時間）
        let hand = dark ? Color(tb: 0xE6ECFF) : Color(tb: 0x2E3F66)
        let hourA = 210.0 * Double.pi / 180
        let minA = -30.0 * Double.pi / 180
        var hands = Path()
        hands.move(to: c)
        hands.addLine(to: CGPoint(x: c.x + r * 0.45 * CGFloat(cos(hourA)), y: c.y + r * 0.45 * CGFloat(sin(hourA))))
        hands.move(to: c)
        hands.addLine(to: CGPoint(x: c.x + r * 0.7 * CGFloat(cos(minA)), y: c.y + r * 0.7 * CGFloat(sin(minA))))
        ctx.stroke(hands, with: .color(hand), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 1.3, y: c.y - 1.3, width: 2.6, height: 2.6)), with: .color(hand))
    }

    // MARK: 交通：兩根圖釘、一條 S 形虛線，線上放這趟用到的交通方式

    static func pins(_ ctx: inout GraphicsContext, size: CGSize, modes: [TripTravelMode], dark: Bool) {
        let w = size.width
        let h = size.height
        let a = CGPoint(x: w * 0.16, y: h * 0.86)
        let b = CGPoint(x: w * 0.84, y: h * 0.38)
        let c1 = CGPoint(x: w * 0.62, y: h * 1.02)
        let c2 = CGPoint(x: w * 0.38, y: h * 0.14)
        var curve = Path()
        curve.move(to: a)
        curve.addCurve(to: b, control1: c1, control2: c2)
        ctx.stroke(curve, with: .color(dark ? Color(tb: 0xFFB45E, 0.8) : Color(tb: 0xE07800, 0.7)),
                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2.5, 2.5]))
        pin(&ctx, tip: a, color: dark ? Color(tb: 0xFF6F97) : Color(tb: 0xE0457A), size: 8)
        pin(&ctx, tip: b, color: dark ? Color(tb: 0xFFB020) : Color(tb: 0xE07800), size: 8)
        let spots: [Double] = [0.5, 0.3, 0.7]
        for (i, mode) in modes.prefix(3).enumerated() {
            let p = bezier(a, c1, c2, b, t: spots[i])
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5.5, y: p.y - 5.5, width: 11, height: 11)),
                     with: .color(dark ? Color(tb: 0x2A3560) : Color.white))
            var icon = ctx.resolve(Image(systemName: mode.icon))
            icon.shading = .color(dark ? Color(tb: 0xC9D3E6) : Color(tb: 0x4A5B8C))
            ctx.draw(icon, in: CGRect(x: p.x - 3.6, y: p.y - 3.6, width: 7.2, height: 7.2))
        }
    }

    static func bezier(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, t: Double) -> CGPoint {
        let u = 1 - t
        let a = u * u * u
        let b = 3 * u * u * t
        let c = 3 * u * t * t
        let d = t * t * t
        let x = a * Double(p0.x) + b * Double(p1.x) + c * Double(p2.x) + d * Double(p3.x)
        let y = a * Double(p0.y) + b * Double(p1.y) + c * Double(p2.y) + d * Double(p3.y)
        return CGPoint(x: x, y: y)
    }

    /// 圖釘：圓頭＋往下收的尖，tip 是尖端
    static func pin(_ ctx: inout GraphicsContext, tip p: CGPoint, color: Color, size s: CGFloat) {
        var path = Path()
        path.addEllipse(in: CGRect(x: p.x - s / 2, y: p.y - s * 1.35, width: s, height: s))
        path.move(to: CGPoint(x: p.x - s * 0.36, y: p.y - s * 0.62))
        path.addLine(to: CGPoint(x: p.x, y: p.y))
        path.addLine(to: CGPoint(x: p.x + s * 0.36, y: p.y - s * 0.62))
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.18, y: p.y - s * 1.03, width: s * 0.36, height: s * 0.36)),
                 with: .color(Color.white))
    }

    // MARK: 距離：這趟真正的路線形狀

    /// 依時間軸順序把有座標的站連起來（等距圓柱投影，經度乘 cos 緯度）。
    /// 遇到飛機段就切開：縮放範圍用點數最多的那一段地面路線（例：九州那一圈），
    /// 飛機段畫成虛線弧，飛出格子的部分讓 Canvas 自己裁掉——看得出「從格子外飛進來」。
    /// 不打任何地圖請求。
    static func route(_ ctx: inout GraphicsContext, size: CGSize, points: [TripBoardRoutePoint], dark: Bool) {
        let line = dark ? Color(tb: 0x7FB2FF) : Color(tb: 0x3E7BEA)
        guard !points.isEmpty else {
            // 沒有任何座標：一條淡淡的虛線
            var p = Path()
            p.move(to: CGPoint(x: 4, y: size.height - 6))
            p.addQuadCurve(to: CGPoint(x: size.width - 4, y: size.height * 0.4),
                           control: CGPoint(x: size.width * 0.5, y: size.height))
            ctx.stroke(p, with: .color(line.opacity(0.5)), style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2.5]))
            return
        }
        var segments: [[TripBoardRoutePoint]] = []
        var current: [TripBoardRoutePoint] = []
        for p in points {
            if p.byPlane && !current.isEmpty {
                segments.append(current)
                current = []
            }
            current.append(p)
        }
        if !current.isEmpty { segments.append(current) }
        var main = segments[0]
        for s in segments where s.count > main.count { main = s }

        let lats = main.map(\.lat)
        let lons = main.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        let kx = max(0.2, cos((minLat + maxLat) / 2 * Double.pi / 180))
        // 兩邊至少 0.02°（約 2 公里），免得把 GPS 抖動放大成一團
        let spanX = max((maxLon - minLon) * kx, 0.02)
        let spanY = max(maxLat - minLat, 0.02)
        let w = Double(size.width)
        let h = Double(size.height)
        let scale = min((w - 8) / spanX, (h - 8) / spanY)
        let ox = (w - (maxLon - minLon) * kx * scale) / 2
        let oy = (h - (maxLat - minLat) * scale) / 2
        func project(_ p: TripBoardRoutePoint) -> CGPoint {
            CGPoint(x: ox + (p.lon - minLon) * kx * scale, y: oy + (maxLat - p.lat) * scale)
        }

        // 飛機段：上一段的最後一站 → 下一段的第一站，虛線弧
        if segments.count > 1 {
            for i in 1..<segments.count {
                guard let from = segments[i - 1].last, let to = segments[i].first else { continue }
                let a = project(from)
                let b = project(to)
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let dx = b.x - a.x
                let dy = b.y - a.y
                // 往上拱：法線方向取 y 往上的那一邊
                var nx = -dy * 0.25
                var ny = dx * 0.25
                if ny > 0 { nx = -nx; ny = -ny }
                var arc = Path()
                arc.move(to: a)
                arc.addQuadCurve(to: b, control: CGPoint(x: mid.x + nx, y: mid.y + ny))
                ctx.stroke(arc, with: .color(line.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2.5, 2.5]))
            }
        }
        // 地面段
        for seg in segments {
            let pts = thin(seg.map { project($0) })
            guard pts.count >= 2 else { continue }
            var path = Path()
            path.move(to: pts[0])
            for q in pts.dropFirst() { path.addLine(to: q) }
            ctx.stroke(path, with: .color(line.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        // 起點一個小白圈，終點一根圖釘
        let start = project(points[0])
        ctx.fill(Path(ellipseIn: CGRect(x: start.x - 2.4, y: start.y - 2.4, width: 4.8, height: 4.8)),
                 with: .color(Color.white))
        ctx.stroke(Path(ellipseIn: CGRect(x: start.x - 2.4, y: start.y - 2.4, width: 4.8, height: 4.8)),
                   with: .color(line), lineWidth: 1)
        if let last = points.last, points.count > 1 {
            pin(&ctx, tip: project(last), color: dark ? Color(tb: 0x7FB2FF) : Color(tb: 0x1F6FE0), size: 7)
        }
    }

    /// 換算後相距不到 1pt 的相鄰點合併；超過 120 點就等距抽樣（保留頭尾）
    static func thin(_ pts: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        for p in pts {
            if let l = out.last, abs(l.x - p.x) < 1, abs(l.y - p.y) < 1 { continue }
            out.append(p)
        }
        guard out.count > 120 else { return out }
        let step = Double(out.count - 1) / 119
        return (0..<120).map { out[min(out.count - 1, Int((Double($0) * step).rounded()))] }
    }

    // MARK: 花費：一張鋸齒下緣的收據＋一枚硬幣；有待確認的支出時夾一根橘色迴紋針

    static func receipt(_ ctx: inout GraphicsContext, size: CGSize, lines: Int, waiting: Bool, dark: Bool) {
        let rw = min(30, size.width * 0.5)
        let rh = min(size.height - 4, 40)
        let x0 = size.width - rw - 4
        let y0 = size.height - rh - 2
        var paper = Path()
        paper.move(to: CGPoint(x: x0, y: y0 + 2))
        paper.addQuadCurve(to: CGPoint(x: x0 + 2, y: y0), control: CGPoint(x: x0, y: y0))
        paper.addLine(to: CGPoint(x: x0 + rw - 2, y: y0))
        paper.addQuadCurve(to: CGPoint(x: x0 + rw, y: y0 + 2), control: CGPoint(x: x0 + rw, y: y0))
        paper.addLine(to: CGPoint(x: x0 + rw, y: y0 + rh))
        let teeth = 6
        let tw = rw / CGFloat(teeth)
        for i in 0..<teeth {
            let xr = x0 + rw - CGFloat(i) * tw
            paper.addLine(to: CGPoint(x: xr - tw / 2, y: y0 + rh - 2.5))
            paper.addLine(to: CGPoint(x: xr - tw, y: y0 + rh))
        }
        paper.closeSubpath()
        ctx.fill(paper, with: .color(dark ? Color(tb: 0x2A3560) : Color.white.opacity(0.95)))
        ctx.stroke(paper, with: .color(dark ? Color.white.opacity(0.15) : Color(tb: 0xC9D7EA)), lineWidth: 0.6)
        let ink = dark ? Color.white.opacity(0.3) : Color(tb: 0x9AAFC8)
        for i in 0..<max(1, min(6, lines)) {
            let y = y0 + 6 + CGFloat(i) * 4.2
            if y > y0 + rh - 7 { break }
            var l = Path()
            l.move(to: CGPoint(x: x0 + 4, y: y))
            l.addLine(to: CGPoint(x: x0 + 4 + (rw - 8) * (i % 3 == 2 ? 0.5 : 0.85), y: y))
            ctx.stroke(l, with: .color(ink), lineWidth: 1)
        }
        // 硬幣（只畫圈，不寫幣別符號）
        let coin = CGRect(x: x0 - 9, y: y0 + rh - 15, width: 14, height: 14)
        ctx.fill(Path(ellipseIn: coin), with: .linearGradient(
            Gradient(colors: dark ? [Color(tb: 0xC9952B), Color(tb: 0x9C6F12)] : [Color(tb: 0xF6C453), Color(tb: 0xE0A21B)]),
            startPoint: CGPoint(x: coin.minX, y: coin.minY), endPoint: CGPoint(x: coin.maxX, y: coin.maxY)))
        ctx.stroke(Path(ellipseIn: coin.insetBy(dx: 2.5, dy: 2.5)),
                   with: .color(Color.white.opacity(dark ? 0.3 : 0.6)), lineWidth: 0.8)
        if waiting {
            var clip = Path()
            let cx = x0 + rw - 7
            clip.move(to: CGPoint(x: cx, y: y0 + 8))
            clip.addLine(to: CGPoint(x: cx, y: y0 - 3))
            clip.addQuadCurve(to: CGPoint(x: cx + 4, y: y0 - 3), control: CGPoint(x: cx + 2, y: y0 - 6))
            clip.addLine(to: CGPoint(x: cx + 4, y: y0 + 6))
            clip.addQuadCurve(to: CGPoint(x: cx + 1.6, y: y0 + 6), control: CGPoint(x: cx + 2.8, y: y0 + 8))
            clip.addLine(to: CGPoint(x: cx + 1.6, y: y0 - 1))
            ctx.stroke(clip, with: .color(dark ? Color(tb: 0xFFB020) : Color(tb: 0xF59E0B)),
                       style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
        }
    }
}
