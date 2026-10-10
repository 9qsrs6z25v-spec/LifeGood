import SwiftUI
import UIKit
import CoreLocation
// .onReceive(NotificationCenter.default.publisher(for:)) 要用（TripTimelineCard 也是明著 import）
import Combine

// MARK: - 收支項目的卡面（v25.524）
//
// 使用者：「我覺得項目的藝術感跟質感都差太多了，你再好好規劃一次」（拿旅遊項目的卡片比），
// 看過樣稿後：「變高可以，加緊湊也可以」「好用英文」「好直接五個項目做一做」。
//
// 每一筆收支是一張卡，左邊一塊「卡面」，右緣是行程卡那條波浪切線。卡面放什麼，依序：
//   1. 使用者替這筆支出附的照片（餐點、收據）
//   2. 有店家座標 → 衛星空照＋手寫城市名（Fukuoka／JAPAN），跟行程卡同一套
//      （TripHeroStore.satellite、TripPlaceNameStore）
//   3. 都沒有 → 分類插畫：分類色兩色漸層＋一層紋理＋裁出畫面的大圖示＋右上一顆小圖示
//      ＋左下手寫英文字（Dining）與字距拉開的小字（FOOD & DRINK）
//
// 插畫一共 27 張：變動支出 14 類、固定支出 8 類、收入 5 類。全部同一套構圖，
// 只換顏色、圖示、紋理、字——一整組看起來是同一個系列，不是 27 張各畫各的。
// 圖示一律是系統的 SF Symbols。
//
// 規矩（跟行程看板一樣）：卡面是「看得到、不給讀」的裝飾；要讀的字（名稱、金額、分類）
// 一律在右邊的 Text 裡，卡面整塊 accessibilityHidden。

// MARK: - 主題

/// 卡面上那一層紋理
enum MoneyArtPattern: Int {
    case dots, stripes, metro, sparkles, road, skyline, grid, waves, confetti, pulse, ruled, leaves
}

struct MoneyArtTheme: Equatable {
    /// 主題編號：衛星快照的快取 key（針的顏色）與紋理的種子
    let id: Int
    /// 漸層左上（亮）與右下（暗）
    let top: UInt32
    let bottom: UInt32
    /// 分類色：卡片右邊那層淡淡的底、分類名前面的點、進度條
    let tint: UInt32
    /// 裁出畫面的大圖示
    let hero: String
    /// 右上那顆實心小圖示
    let accent: String?
    let pattern: MoneyArtPattern
    /// 左下的手寫英文字（手寫字型沒有中文字形，使用者指定用英文）
    let word: String
    /// 手寫字下面字距拉開的小字
    let caps: String

    var topColor: Color { Color(tb: top) }
    var bottomColor: Color { Color(tb: bottom) }
    var tintColor: Color { Color(tb: tint) }
    /// 中間色（比例彩帶、圖表的扇形用）
    var midColor: Color { topColor.mix(with: bottomColor, by: 0.55) }

    /// 寫字用的分類色：淺色壓暗、深色提亮（分類色直接寫在白底上只有 2～3:1）
    func ink(_ scheme: ColorScheme) -> Color { TripInk.text(tintColor, scheme) }
}

extension MoneyArtTheme {
    // ── 變動支出 ──
    static let food = MoneyArtTheme(id: 1, top: 0xFFB45E, bottom: 0xEE5E3B, tint: 0xF07A3A,
                                    hero: "fork.knife", accent: "cup.and.saucer.fill", pattern: .dots,
                                    word: "Dining", caps: "FOOD & DRINK")
    static let transit = MoneyArtTheme(id: 2, top: 0x6CC8FF, bottom: 0x2C66DE, tint: 0x2F7FE8,
                                       hero: "tram.fill", accent: "airplane", pattern: .metro,
                                       word: "Transit", caps: "ON THE MOVE")
    static let drive = MoneyArtTheme(id: 3, top: 0x8DB3D6, bottom: 0x3C5A86, tint: 0x4A6FA5,
                                     hero: "car.fill", accent: "fuelpump.fill", pattern: .road,
                                     word: "Drive", caps: "CAR & FUEL")
    static let stock = MoneyArtTheme(id: 4, top: 0x4FD0A0, bottom: 0x168A5C, tint: 0x1F9D57,
                                     hero: "chart.line.uptrend.xyaxis", accent: "dollarsign.circle.fill",
                                     pattern: .grid, word: "Invest", caps: "STOCKS")
    static let property = MoneyArtTheme(id: 5, top: 0xA9BEDF, bottom: 0x4F6A99, tint: 0x4F6A99,
                                        hero: "building.2.fill", accent: "key.fill", pattern: .skyline,
                                        word: "Property", caps: "REAL ESTATE")
    static let tax = MoneyArtTheme(id: 6, top: 0xC2C6D2, bottom: 0x6E7487, tint: 0x5E6478,
                                   hero: "doc.text.fill", accent: "building.columns.fill", pattern: .ruled,
                                   word: "Tax", caps: "DUTIES & FEES")
    static let taxSaving = MoneyArtTheme(id: 7, top: 0x9BDDB2, bottom: 0x3E9A66, tint: 0x2F8A57,
                                         hero: "leaf.fill", accent: "lightbulb.fill", pattern: .leaves,
                                         word: "Relief", caps: "TAX SAVING")
    static let play = MoneyArtTheme(id: 8, top: 0xC49BFF, bottom: 0x6B3CE0, tint: 0x8B5CF6,
                                    hero: "gamecontroller.fill", accent: "ticket.fill", pattern: .sparkles,
                                    word: "Play", caps: "FUN & SHOWS")
    static let shopping = MoneyArtTheme(id: 9, top: 0xFF9CBB, bottom: 0xE0457A, tint: 0xE0457A,
                                        hero: "bag.fill", accent: "tag.fill", pattern: .stripes,
                                        word: "Shopping", caps: "BAGS & TREATS")
    static let daily = MoneyArtTheme(id: 10, top: 0x6FE3BC, bottom: 0x1E9C78, tint: 0x1F9D78,
                                     hero: "basket.fill", accent: "sparkles", pattern: .dots,
                                     word: "Daily", caps: "HOME GOODS")
    static let health = MoneyArtTheme(id: 11, top: 0xFF9AA2, bottom: 0xD93545, tint: 0xD93545,
                                      hero: "cross.case.fill", accent: "heart.fill", pattern: .pulse,
                                      word: "Health", caps: "CARE")
    static let learn = MoneyArtTheme(id: 12, top: 0x8FB2FF, bottom: 0x3A63D8, tint: 0x3A63D8,
                                     hero: "book.fill", accent: "graduationcap.fill", pattern: .ruled,
                                     word: "Learn", caps: "BOOKS & CLASSES")
    static let gifts = MoneyArtTheme(id: 13, top: 0xFFD36B, bottom: 0xF0A020, tint: 0xC77F0A,
                                     hero: "gift.fill", accent: "heart.fill", pattern: .confetti,
                                     word: "Gifts", caps: "FRIENDS & FAMILY")
    static let misc = MoneyArtTheme(id: 14, top: 0xC8CDD8, bottom: 0x7D8496, tint: 0x6B7285,
                                    hero: "square.grid.2x2.fill", accent: "sparkles", pattern: .dots,
                                    word: "Misc", caps: "EVERYTHING ELSE")

    // ── 固定支出 ──
    static let rent = MoneyArtTheme(id: 21, top: 0x8EC5FF, bottom: 0x3A6FD8, tint: 0x2F6BD0,
                                    hero: "key.fill", accent: "building.2.fill", pattern: .skyline,
                                    word: "Rent", caps: "HOME")
    static let utilities = MoneyArtTheme(id: 22, top: 0xFFD45E, bottom: 0xF08A1C, tint: 0xC76A0C,
                                         hero: "bolt.fill", accent: "drop.fill", pattern: .waves,
                                         word: "Utilities", caps: "POWER & WATER")
    static let insurance = MoneyArtTheme(id: 23, top: 0x7DDBA0, bottom: 0x25935B, tint: 0x1F8A55,
                                         hero: "checkmark.shield.fill", accent: "heart.fill", pattern: .waves,
                                         word: "Cover", caps: "INSURANCE")
    /// 訂閱服務：大圖示換成名稱的第一個字（Netflix 的 N），右上的小圖示是播放鍵
    static let subscription = MoneyArtTheme(id: 24, top: 0xA88BFF, bottom: 0x5B34D6, tint: 0x6B44E0,
                                            hero: "play.rectangle.fill", accent: nil, pattern: .waves,
                                            word: "Stream", caps: "SUBSCRIPTION")
    static let loan = MoneyArtTheme(id: 25, top: 0xFF9A8B, bottom: 0xC93A4A, tint: 0xC93A4A,
                                    hero: "house.fill", accent: "banknote.fill", pattern: .skyline,
                                    word: "Home", caps: "MORTGAGE & LOANS")
    static let telecom = MoneyArtTheme(id: 26, top: 0x7FE3F0, bottom: 0x1E8FB0, tint: 0x1A86A6,
                                       hero: "antenna.radiowaves.left.and.right", accent: "wifi",
                                       pattern: .waves, word: "Mobile", caps: "TELECOM")
    static let management = MoneyArtTheme(id: 27, top: 0xD9C2A6, bottom: 0x8C6B4E, tint: 0x7A5A3E,
                                          hero: "wrench.and.screwdriver.fill", accent: "building.2.fill",
                                          pattern: .grid, word: "Building", caps: "MANAGEMENT")
    static let recurring = MoneyArtTheme(id: 28, top: 0xC8CDD8, bottom: 0x7D8496, tint: 0x6B7285,
                                         hero: "repeat", accent: "calendar", pattern: .dots,
                                         word: "Fixed", caps: "RECURRING")

    // ── 收入 ──
    static let salary = MoneyArtTheme(id: 31, top: 0x5FD69A, bottom: 0x167A55, tint: 0x177A44,
                                      hero: "briefcase.fill", accent: "dollarsign.circle.fill",
                                      pattern: .skyline, word: "Salary", caps: "PAYDAY")
    static let bonus = MoneyArtTheme(id: 32, top: 0xFFD36B, bottom: 0xE89A12, tint: 0xB87500,
                                     hero: "star.fill", accent: "sparkles", pattern: .confetti,
                                     word: "Bonus", caps: "WELL DONE")
    static let gift = MoneyArtTheme(id: 33, top: 0xFF9CBB, bottom: 0xE0457A, tint: 0xD0396C,
                                    hero: "gift.fill", accent: "heart.fill", pattern: .confetti,
                                    word: "Gift", caps: "WITH LOVE")
    static let luck = MoneyArtTheme(id: 34, top: 0xC49BFF, bottom: 0x7A4BE8, tint: 0x7547E0,
                                    hero: "sparkles", accent: "star.fill", pattern: .sparkles,
                                    word: "Lucky", caps: "SMALL JOYS")
    static let dividend = MoneyArtTheme(id: 35, top: 0x4FD0C0, bottom: 0x137F86, tint: 0x138A8A,
                                        hero: "chart.line.uptrend.xyaxis", accent: "dollarsign.circle.fill",
                                        pattern: .grid, word: "Dividend", caps: "RETURNS")

    // ── 圖表頁（每張圖一張卡，上方橫幅用）──
    static let chartTrend = MoneyArtTheme(id: 41, top: 0x7FB8FF, bottom: 0x3550D8, tint: 0x2F5BD8,
                                          hero: "chart.bar.fill", accent: "calendar", pattern: .grid,
                                          word: "Trends", caps: "OVER TIME")
    static let chartVariable = MoneyArtTheme(id: 42, top: 0xFFB45E, bottom: 0xE0457A, tint: 0xE0573A,
                                             hero: "chart.pie.fill", accent: "cart.fill", pattern: .dots,
                                             word: "Spending", caps: "BY CATEGORY")
    static let chartFixed = MoneyArtTheme(id: 43, top: 0xA88BFF, bottom: 0x3A63D8, tint: 0x5B4BE0,
                                          hero: "chart.pie.fill", accent: "repeat", pattern: .waves,
                                          word: "Recurring", caps: "BY CATEGORY")
    static let chartMix = MoneyArtTheme(id: 44, top: 0x6CC8FF, bottom: 0x7547E0, tint: 0x5B5FE0,
                                        hero: "square.split.2x1.fill", accent: "scalemass.fill",
                                        pattern: .stripes, word: "Balance", caps: "FIXED VS VARIABLE")

    // ── 理財（v25.527）：資產類別的明信片、項目卡、看板的建築都用這幾個顏色 ──
    // 顏色沿用理財頁原本的分類色：房地產紫、儲蓄險藍、股票橘、載具青。
    static let finHome = MoneyArtTheme(id: 51, top: 0xB79CFF, bottom: 0x6B4BE0, tint: 0x6B4BE0,
                                       hero: "house.fill", accent: "key.fill", pattern: .skyline,
                                       word: "Home", caps: "REAL ESTATE")
    static let finSavings = MoneyArtTheme(id: 52, top: 0x8EC5FF, bottom: 0x3A6FE0, tint: 0x2F5BD8,
                                          hero: "shield.lefthalf.filled", accent: "dollarsign.circle.fill",
                                          pattern: .waves, word: "Savings", caps: "INSURANCE")
    static let finStock = MoneyArtTheme(id: 53, top: 0xFFB45E, bottom: 0xF07A2A, tint: 0xD9650F,
                                        hero: "chart.line.uptrend.xyaxis", accent: "dollarsign.circle.fill",
                                        pattern: .grid, word: "Stocks", caps: "MARKET")
    static let finDrive = MoneyArtTheme(id: 54, top: 0x7FE3D0, bottom: 0x1A9C8C, tint: 0x138A7E,
                                        hero: "car.fill", accent: "fuelpump.fill", pattern: .road,
                                        word: "Drive", caps: "ON THE ROAD")
    static let finElectric = MoneyArtTheme(id: 55, top: 0x7FE3D0, bottom: 0x1A9C8C, tint: 0x138A7E,
                                           hero: "car.fill", accent: "bolt.fill", pattern: .road,
                                           word: "Electric", caps: "CHARGE UP")
    static let finScooter = MoneyArtTheme(id: 56, top: 0x8DB3D6, bottom: 0x3C5A86, tint: 0x4A6FA5,
                                          hero: "scooter", accent: "bolt.fill", pattern: .road,
                                          word: "Ride", caps: "SCOOTER")
    /// 燃油機車（電動機車用上面那張：右上是閃電）
    static let finMoto = MoneyArtTheme(id: 57, top: 0x8DB3D6, bottom: 0x3C5A86, tint: 0x4A6FA5,
                                       hero: "scooter", accent: "fuelpump.fill", pattern: .road,
                                       word: "Ride", caps: "MOTORCYCLE")

    static func of(_ c: VariableCategory?) -> MoneyArtTheme {
        switch c {
        case .food: return .food
        case .transportation: return .transit
        case .vehicle: return .drive
        case .stock: return .stock
        case .realEstate: return .property
        case .tax: return .tax
        case .taxSaving: return .taxSaving
        case .entertainment: return .play
        case .shopping: return .shopping
        case .dailyNecessities: return .daily
        case .medical: return .health
        case .education: return .learn
        case .social: return .gifts
        case .other, nil: return .misc
        }
    }

    static func of(_ c: FixedCategory?) -> MoneyArtTheme {
        switch c {
        case .rent: return .rent
        case .utilities: return .utilities
        case .insurance: return .insurance
        case .subscription: return .subscription
        case .loan: return .loan
        case .telecom: return .telecom
        case .management: return .management
        case .other, nil: return .recurring
        }
    }

    static func of(_ c: IncomeCategory) -> MoneyArtTheme {
        switch c {
        case .salary: return .salary
        case .bonus: return .bonus
        case .gift: return .gift
        case .luck: return .luck
        case .investment: return .dividend
        }
    }

    static func of(_ e: Expense) -> MoneyArtTheme {
        e.expenseType == .fixed ? of(e.fixedCategory) : of(e.variableCategory)
    }
}

// MARK: - 形狀

/// 卡面的右緣：上面窄一點、往下一個 S 彎鼓出去（行程卡照片切線的簡化版）。
/// 左邊、上下貼齊卡片，卡片本身的圓角負責左邊兩個角。
struct MoneyPanelShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let tw = w * 0.84
        let y0 = min(h * 0.30, 40)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x, y: rect.minY + y) }
        var p = Path()
        p.move(to: pt(0, 0))
        p.addLine(to: pt(tw - 10, 0))
        p.addQuadCurve(to: pt(tw, 10), control: pt(tw, 0))
        p.addLine(to: pt(tw, y0))
        p.addCurve(to: pt(w, y0 + 22), control1: pt(tw, y0 + 14), control2: pt(w, y0 + 6))
        p.addLine(to: pt(w, h - 10))
        p.addQuadCurve(to: pt(w - 10, h), control: pt(w, h))
        p.addLine(to: pt(0, h))
        p.closeSubpath()
        return p
    }
}

/// 明信片上方那塊插畫的底邊：一道波浪（跟卡面的切線同一個意思，橫著放）
struct MoneyBannerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x, y: rect.minY + y) }
        var p = Path()
        p.move(to: pt(0, 0))
        p.addLine(to: pt(w, 0))
        p.addLine(to: pt(w, h - 12))
        p.addCurve(to: pt(w * 0.30, h - 10), control1: pt(w * 0.75, h - 2), control2: pt(w * 0.55, h - 20))
        p.addCurve(to: pt(0, h - 9), control1: pt(w * 0.18, h - 5), control2: pt(w * 0.08, h - 6))
        p.closeSubpath()
        return p
    }
}

// MARK: - 紋理

/// 卡面上那一層白色、很淡的紋理。Equatable：一長串卡片捲動時不重畫。
struct MoneyArtPatternLayer: View, Equatable {
    let pattern: MoneyArtPattern
    let seed: Int

    var body: some View {
        Canvas { ctx, size in
            Self.paint(&ctx, size: size, pattern: pattern, seed: seed)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 四角星（sparkles 紋理、Lucky 卡面）
    static func star(center c: CGPoint, radius r: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + r * 0.12, y: c.y - r * 0.12))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + r * 0.12, y: c.y + r * 0.12))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - r * 0.12, y: c.y + r * 0.12))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - r * 0.12, y: c.y - r * 0.12))
        p.closeSubpath()
        return p
    }

    static func paint(_ ctx: inout GraphicsContext, size: CGSize, pattern: MoneyArtPattern, seed: Int) {
        let w = size.width
        let h = size.height
        guard w > 4, h > 4 else { return }
        var r = InkRandom(9091 + seed * 37)
        func white(_ a: Double) -> GraphicsContext.Shading { .color(Color.white.opacity(a)) }

        switch pattern {
        case .dots:
            var y: CGFloat = 6
            var row = 0
            while y < h {
                var x: CGFloat = 6 + CGFloat(row % 2) * 4.5
                while x < w {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2)), with: white(0.16))
                    x += 9
                }
                y += 9
                row += 1
            }

        case .stripes:
            var k = -h
            while k < w {
                var p = Path()
                p.move(to: CGPoint(x: k, y: h))
                p.addLine(to: CGPoint(x: k + h, y: 0))
                ctx.stroke(p, with: white(0.12), lineWidth: 3)
                k += 11
            }

        case .metro:
            // 三條地鐵線，各兩站
            let lines: [(CGFloat, CGFloat, Double, CGFloat)] = [(0.25, 0.55, 0.30, 3.2), (0.62, 0.35, 0.22, 2.6), (0.85, 0.70, 0.18, 2.0)]
            for (a, b, alpha, lw) in lines {
                let p0 = CGPoint(x: -4, y: h * a)
                let p3 = CGPoint(x: w + 4, y: h * b)
                let c1 = CGPoint(x: w * 0.35, y: h * a)
                let c2 = CGPoint(x: w * 0.45, y: h * b)
                var p = Path()
                p.move(to: p0)
                p.addCurve(to: p3, control1: c1, control2: c2)
                ctx.stroke(p, with: white(alpha), style: StrokeStyle(lineWidth: lw, lineCap: .round))
                for t in [0.22, 0.58] {
                    let u = CGFloat(1 - t)
                    let tt = CGFloat(t)
                    let x = u * u * u * p0.x + 3 * u * u * tt * c1.x + 3 * u * tt * tt * c2.x + tt * tt * tt * p3.x
                    let y = u * u * u * p0.y + 3 * u * u * tt * c1.y + 3 * u * tt * tt * c2.y + tt * tt * tt * p3.y
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 2.6, y: y - 2.6, width: 5.2, height: 5.2)),
                             with: white(min(0.8, alpha + 0.25)))
                }
            }

        case .sparkles:
            for _ in 0..<9 {
                let c = CGPoint(x: 4 + CGFloat(r.next()) * (w - 8), y: 4 + CGFloat(r.next()) * max(4, h - 24))
                let rad = CGFloat(2 + r.next() * 2.5)
                ctx.fill(star(center: c, radius: rad), with: white(0.18 + r.next() * 0.27))
            }

        case .road:
            var road = Path()
            road.move(to: CGPoint(x: w * 0.15, y: h))
            road.addLine(to: CGPoint(x: w * 0.55, y: h * 0.18))
            road.addLine(to: CGPoint(x: w * 0.72, y: h * 0.18))
            road.addLine(to: CGPoint(x: w * 0.98, y: h))
            road.closeSubpath()
            ctx.fill(road, with: white(0.10))
            var lane = Path()
            lane.move(to: CGPoint(x: w * 0.565, y: h))
            lane.addLine(to: CGPoint(x: w * 0.635, y: h * 0.2))
            ctx.stroke(lane, with: white(0.38), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))

        case .skyline:
            var x: CGFloat = -2
            while x < w {
                let bw = CGFloat(8 + r.next() * 8)
                let bh = h * CGFloat(0.18 + r.next() * 0.24)
                ctx.fill(Path(CGRect(x: x, y: h - bh, width: bw, height: bh + 2)), with: white(0.13))
                if bh > h * 0.3 {
                    var wy = h - bh + 4
                    while wy < h - 3 {
                        ctx.fill(Path(CGRect(x: x + 2, y: wy, width: max(1, bw - 4), height: 1)), with: white(0.12))
                        wy += 4
                    }
                }
                x += bw + CGFloat(1 + r.next() * 2)
            }

        case .grid:
            var gx: CGFloat = 0
            while gx < w {
                var p = Path()
                p.move(to: CGPoint(x: gx, y: 0))
                p.addLine(to: CGPoint(x: gx, y: h))
                ctx.stroke(p, with: white(0.10), lineWidth: 0.75)
                gx += 12
            }
            var gy: CGFloat = 0
            while gy < h {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: gy))
                p.addLine(to: CGPoint(x: w, y: gy))
                ctx.stroke(p, with: white(0.10), lineWidth: 0.75)
                gy += 12
            }
            var line = Path()
            for i in 0...7 {
                let x = w * CGFloat(i) / 7
                let y = h * CGFloat(0.78 - 0.07 * Double(i) + (r.next() - 0.5) * 0.12)
                if i == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(line, with: white(0.38), style: StrokeStyle(lineWidth: 2, lineJoin: .round))

        case .waves:
            for i in 0..<5 {
                let y0 = h * CGFloat(0.2 + Double(i) * 0.17)
                var p = Path()
                p.move(to: CGPoint(x: -4, y: y0))
                var x: CGFloat = -4
                let seg = max(12, w / 4)
                var up = true
                while x < w + 4 {
                    p.addQuadCurve(to: CGPoint(x: x + seg, y: y0),
                                   control: CGPoint(x: x + seg / 2, y: y0 + (up ? -6 : 6)))
                    x += seg
                    up.toggle()
                }
                ctx.stroke(p, with: white(0.14), lineWidth: 1.6)
            }

        case .confetti:
            for i in 0..<14 {
                let x = CGFloat(r.next()) * w
                let y = CGFloat(r.next()) * h * 0.85
                let a = 0.18 + r.next() * 0.2
                if i % 3 == 0 {
                    let d = CGFloat(2.5 + r.next() * 2)
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)), with: white(a))
                } else {
                    var g = ctx
                    g.translateBy(x: x, y: y)
                    g.rotate(by: .degrees(r.next() * 180))
                    g.fill(Path(roundedRect: CGRect(x: -3.5, y: -1.2, width: 7, height: 2.4), cornerRadius: 1),
                           with: white(a))
                }
            }

        case .pulse:
            var gy: CGFloat = 8
            while gy < h {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: gy))
                p.addLine(to: CGPoint(x: w, y: gy))
                ctx.stroke(p, with: white(0.07), lineWidth: 0.75)
                gy += 10
            }
            let base = h * 0.42
            var beat = Path()
            beat.move(to: CGPoint(x: 0, y: base))
            beat.addLine(to: CGPoint(x: w * 0.28, y: base))
            beat.addLine(to: CGPoint(x: w * 0.34, y: base - h * 0.16))
            beat.addLine(to: CGPoint(x: w * 0.40, y: base + h * 0.14))
            beat.addLine(to: CGPoint(x: w * 0.46, y: base - h * 0.06))
            beat.addLine(to: CGPoint(x: w * 0.52, y: base))
            beat.addLine(to: CGPoint(x: w, y: base))
            ctx.stroke(beat, with: white(0.34), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

        case .ruled:
            var gy: CGFloat = 10
            while gy < h {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: gy))
                p.addLine(to: CGPoint(x: w, y: gy))
                ctx.stroke(p, with: white(0.13), lineWidth: 0.9)
                gy += 10
            }
            var margin = Path()
            margin.move(to: CGPoint(x: 14, y: 0))
            margin.addLine(to: CGPoint(x: 14, y: h))
            ctx.stroke(margin, with: white(0.22), lineWidth: 1)

        case .leaves:
            for _ in 0..<8 {
                let x = CGFloat(r.next()) * w
                let y = CGFloat(r.next()) * h * 0.8
                var g = ctx
                g.translateBy(x: x, y: y)
                g.rotate(by: .degrees(r.next() * 360))
                g.fill(Path(ellipseIn: CGRect(x: -5, y: -2.2, width: 10, height: 4.4)), with: white(0.14 + r.next() * 0.1))
            }
        }
    }
}

// MARK: - 插畫

/// 一張卡面插畫：漸層＋紋理＋左上一道光＋裁出畫面的大圖示（或訂閱服務的字母）
/// ＋右上一顆實心小圖示＋底部壓暗（手寫字讀得到）。
///
/// 三種版型：卡片左邊的「卡面」、明信片上方的「橫幅」、緊湊模式的小方塊。
struct MoneyArtwork: View, Equatable {
    enum Layout: Equatable { case panel, banner, thumb }

    let theme: MoneyArtTheme
    let seed: Int
    var monogram: String? = nil
    let layout: Layout

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [theme.topColor, theme.bottomColor],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                MoneyArtPatternLayer(pattern: theme.pattern, seed: seed + theme.id)
                    .equatable()
                RadialGradient(colors: [Color.white.opacity(0.38), Color.white.opacity(0)],
                               center: UnitPoint(x: 0.18, y: 0.05),
                               startRadius: 0, endRadius: max(w, h) * 0.9)
                hero(w: w, h: h)
                accent(w: w, h: h)
                if layout != .thumb {
                    LinearGradient(stops: [.init(color: Color.black.opacity(0), location: 0.45),
                                           .init(color: Color.black.opacity(0.34), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func hero(w: CGFloat, h: CGFloat) -> some View {
        switch layout {
        case .thumb:
            // 小方塊：圖示擺正中間、實心白，像 App 圖示
            Image(systemName: theme.hero)
                .font(.system(size: min(w, h) * 0.44, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.22), radius: 1.5, x: 0, y: 1)
                .position(x: w / 2, y: h / 2)
        case .panel, .banner:
            let size = layout == .panel ? h * 1.0 : h * 1.15
            let center = layout == .panel
                ? CGPoint(x: w - h * 0.13, y: h * 0.71)
                : CGPoint(x: w - h * 0.42, y: h * 0.66)
            if let monogram {
                Text(monogram)
                    .font(.system(size: size * 0.95, weight: .black, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.22))
                    .lineLimit(1)
                    .fixedSize()
                    .position(center)
            } else {
                Image(systemName: theme.hero)
                    .font(.system(size: size * 0.72, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.20))
                    .rotationEffect(.degrees(-14))
                    .position(center)
            }
        }
    }

    @ViewBuilder
    private func accent(w: CGFloat, h: CGFloat) -> some View {
        // 訂閱服務：大字母之外，右上放它自己的圖示（播放鍵）
        let name: String? = monogram != nil ? theme.hero : theme.accent
        if layout != .thumb, let name {
            let s = min(20, h * 0.22)
            let x = layout == .panel ? w * 0.84 - 10 - s / 2 : w - 14 - s / 2
            Image(systemName: name)
                .font(.system(size: s, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.28), radius: 1.5, x: 0, y: 1.5)
                .position(x: x, y: 10 + s / 2)
        }
    }
}

// MARK: - 手寫字

/// 卡面左下的手寫字：城市名（Fukuoka／JAPAN）或分類的英文字（Dining／FOOD & DRINK）。
/// 一律 fixedSize 的字級：壓在固定大小的卡面上，不跟動態字級放大（會被切）。
struct MoneyArtScript: View {
    let word: String
    let caps: String
    let maxWidth: CGFloat
    var size: CGFloat = 21

    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(word)
                .font(TripScriptFont.city(size))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // Snell 的收筆會超出字框，留一點不讓切線切掉
                .padding(.trailing, 4)
            Text(caps)
                .font(.system(size: 6.5, weight: .bold))
                .tracking(2.4)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.leading, 5)
        }
        .foregroundStyle(.white)
        .shadow(color: Color.black.opacity(0.45), radius: 2, x: 0, y: 1)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 卡面（照片／衛星／插畫）

/// 卡片左邊那一塊。照片與衛星圖照行程卡的規則載入：捲進畫面才載、捲出去就放掉，
/// 所有打 Apple 伺服器的事排同一條隊（TripHeroGate）。
struct MoneyPanel: View {
    let theme: MoneyArtTheme
    let seed: Int
    let monogram: String?
    let badge: String?
    let photoURL: URL?
    let latitude: Double?
    let longitude: Double?
    let place: TripPlaceName.Place?
    /// [v25.527] 股票：卡面畫近期的 K 線（取代分類插畫）
    var candles: [MoneyCandle]? = nil
    /// [v25.527] 左下手寫字（沒給就用分類的英文字）
    var scriptWord: String? = nil
    var scriptCaps: String? = nil
    let width: CGFloat

    @Environment(\.displayScale) private var displayScale
    @ObservedObject private var names = TripPlaceNameStore.shared
    @State private var image: UIImage?
    @State private var isSatellite = false
    @State private var showingUserPhoto = false
    @State private var isVisible = false
    @State private var reloadToken = 0

    /// 收支卡的衛星快照：近正方形（卡面 108 寬、106～140 高），針在上面三分之一
    static let satelliteSize = CGSize(width: 120, height: 132)
    static let satellitePin = CGPoint(x: 0.5, y: 0.34)

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var taskKey: String {
        let source = photoURL?.lastPathComponent
            ?? coordinate.map { String(format: "%.4f,%.4f", $0.latitude, $0.longitude) }
            ?? "-"
        return "\(isVisible)|\(source)|\(theme.id)|\(reloadToken)"
    }

    var body: some View {
        let city = coordinate == nil && place == nil ? nil : names.resolved(place: place, coordinate: coordinate)
        Color.clear
            .overlay {
                ZStack {
                    if let candles, candles.count >= 2 {
                        MoneyCandlePanel(candles: candles)
                            .equatable()
                    } else {
                        MoneyArtwork(theme: theme, seed: seed, monogram: monogram, layout: .panel)
                            .equatable()
                    }
                    if let image {
                        // 衛星圖貼齊下緣：快照左下角可能有 Apple 地圖的標誌，不能切掉
                        Color.clear
                            .overlay(alignment: isSatellite ? .bottom : .center) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            }
                            .clipped()
                            .transition(.opacity)
                        // 上下各壓一層暗：左上的小膠囊、左下的手寫字是白的
                        LinearGradient(colors: [Color.black.opacity(0.26), .clear],
                                       startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3))
                        LinearGradient(colors: [.clear, Color.black.opacity(0.5)],
                                       startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: .bottom)
                    }
                }
            }
            .clipped()
            .overlay(alignment: .topLeading) {
                if let badge {
                    MoneyPanelBadge(text: badge)
                        .padding(.leading, 7)
                        .padding(.top, 7)
                }
            }
            .overlay(alignment: .bottomLeading) {
                // 城市名查得到就寫城市（衛星圖、或使用者的照片拍在有地址的地方），不然寫分類
                let word = city?.romaji ?? scriptWord ?? theme.word
                let caps = city?.country ?? scriptCaps ?? theme.caps
                MoneyArtScript(word: word, caps: caps, maxWidth: width * 0.84 - 8)
                    .padding(.leading, 8)
                    // 衛星圖左下角讓出 Apple 地圖的標誌（TripHeroStore.mapAttributionInset）
                    .padding(.bottom, image != nil && isSatellite ? TripHeroStore.mapAttributionInset + 2 : 7)
            }
            .contentShape(Rectangle())
            .onScrollVisibilityChange(threshold: 0.01) { isVisible = $0 }
            .task(id: taskKey) { await load() }
            .task(id: isVisible) {
                guard isVisible, coordinate != nil || place != nil else { return }
                await names.resolveIfNeeded(place: place, coordinate: coordinate)
            }
            .onReceive(NotificationCenter.default.publisher(for: .cloudSyncPhotosDidUpdate)) { _ in
                if isVisible, photoURL != nil, !showingUserPhoto { reloadToken += 1 }
            }
            .accessibilityHidden(true)
    }

    @MainActor
    private func load() async {
        guard isVisible else {
            image = nil
            isSatellite = false
            showingUserPhoto = false
            return
        }
        let store = TripHeroStore.shared
        if let url = photoURL, let img = await store.photo(url, maxPixel: 420) {
            show(img, satellite: false, userPhoto: true)
            return
        }
        guard !Task.isCancelled else { return }
        guard let c = coordinate else {
            image = nil
            isSatellite = false
            showingUserPhoto = false
            return
        }
        if let img = await store.satellite(c, pin: UIColor(theme.tintColor), pinKey: 100 + theme.id,
                                           scale: displayScale, size: Self.satelliteSize,
                                           pinAt: Self.satellitePin) {
            show(img, satellite: true, userPhoto: false)
        } else if !Task.isCancelled {
            image = nil
            isSatellite = false
        }
    }

    @MainActor
    private func show(_ img: UIImage, satellite: Bool, userPhoto: Bool) {
        guard !Task.isCancelled else { return }
        isSatellite = satellite
        showingUserPhoto = userPhoto
        withAnimation(.easeOut(duration: 0.2)) { image = img }
    }
}

/// 股票的卡面：深藍底、淡格線、近期的 K 棒（紅漲綠跌）＋一條 5 日均線（v25.527）。
/// 只畫在卡面切線左邊（寬 84%），下面三分之一留給手寫字。
struct MoneyCandlePanel: View, Equatable {
    let candles: [MoneyCandle]

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(tb: 0x1B2A52), Color(tb: 0x0B1430)]),
                startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
            var grid = Path()
            var gy: CGFloat = 14
            while gy < h {
                grid.move(to: CGPoint(x: 0, y: gy))
                grid.addLine(to: CGPoint(x: w, y: gy))
                gy += 14
            }
            ctx.stroke(grid, with: .color(Color.white.opacity(0.06)), lineWidth: 0.5)
            let list = Array(candles.suffix(14))
            let lo = list.map(\.low).min() ?? 0
            let hi = list.map(\.high).max() ?? 1
            let span = max(hi - lo, max(abs(hi) * 0.002, 0.0001))
            let top = h * 0.16
            let bottom = h * 0.6
            func y(_ v: Double) -> CGFloat { bottom - (bottom - top) * CGFloat((v - lo) / span) }
            let left: CGFloat = 6
            let usable = w * 0.84 - 10 - left
            let step = usable / CGFloat(list.count)
            let bodyW = max(2, step * 0.62)
            var closes: [CGPoint] = []
            for (i, c) in list.enumerated() {
                let cx = left + step * (CGFloat(i) + 0.5)
                let up = c.close >= c.open
                let color = up ? Color(tb: 0xFF5A5F) : Color(tb: 0x2FBF71)
                var wick = Path()
                wick.move(to: CGPoint(x: cx, y: y(c.high)))
                wick.addLine(to: CGPoint(x: cx, y: y(c.low)))
                ctx.stroke(wick, with: .color(color), lineWidth: 1)
                let y0 = y(max(c.open, c.close))
                let y1 = y(min(c.open, c.close))
                ctx.fill(Path(CGRect(x: cx - bodyW / 2, y: y0, width: bodyW, height: max(1.2, y1 - y0))),
                         with: .color(color))
                closes.append(CGPoint(x: cx, y: y(c.close)))
            }
            // 5 日均線
            if list.count >= 5 {
                var ma = Path()
                for i in 4..<list.count {
                    let avg = list[(i - 4)...i].reduce(0) { $0 + $1.close } / 5
                    let p = CGPoint(x: closes[i].x, y: y(avg))
                    if i == 4 { ma.move(to: p) } else { ma.addLine(to: p) }
                }
                ctx.stroke(ma, with: .color(Color(tb: 0xFFB45E, 0.9)),
                           style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 卡面左上的小膠囊（時間、日期、週期）
struct MoneyPanelBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6.5)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.40), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.55), lineWidth: 0.75))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// 緊湊模式左邊的小方塊：有照片放照片，沒有就是分類插畫的小方塊版
struct MoneyThumb: View {
    let theme: MoneyArtTheme
    let seed: Int
    let photoURL: URL?

    @State private var image: UIImage?
    @State private var isVisible = false

    var body: some View {
        ZStack {
            MoneyArtwork(theme: theme, seed: seed, layout: .thumb)
                .equatable()
            if let image {
                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onScrollVisibilityChange(threshold: 0.01) { isVisible = $0 }
        .task(id: "\(isVisible)|\(photoURL?.lastPathComponent ?? "-")") {
            guard isVisible, let url = photoURL else {
                image = nil
                return
            }
            if let img = await TripHeroStore.shared.photo(url, maxPixel: 160), !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.2)) { image = img }
            }
        }
        .accessibilityHidden(true)
    }
}
