import SwiftUI

// MARK: - 財富的三幅看板風景＋信用卡卡面（v25.564，財富 v3；wealth/judge.md §3.2、§4.1、§4.2、§3.7、§3.16）
//
// A.「頂樓水塔」.towers(WealthTowerScene)：財富頁看板（band 118）。台灣頂樓家家戶戶都有的不鏽鋼水塔（圓柱＋四隻腳）。
//    一個沒收起來的銀行帳戶一座塔，左到右照財富頁的順序；最多 5 座，第 6 個起資料端併成一座小塔（badge「＋3」）。
//    塔裡的水位＝level（資料端已經算好 √(存摺上÷最大那座)，0 空塔）；水面上那一截斜線＝hatch（還沒扣÷存摺上，
//    同資產小鎮「斜線＝還欠」finHatch，卡費橘）；hatch ≥ 1 或 warn：斜線畫到塔底、塔框 warn 色。
//    kind：.live 藍水、.foreign 青水＋塔身小旗（badge「US$」）、.deposit 金水＋塔身鎖頭＋小牌（badge「3/15」）、
//    .empty 灰色空塔（只有卡沒有銀行：「還沒選從哪扣」）。dashed：新手三座虛線空塔。
//    [v25.566] 到期前 7 天鎖頭打開一半（lockOpen：鎖身不動，鎖環右腳往上提 2.5pt、整個往左上斜一點；不寫字）。
//    塔下白底小牌（finPill）寫 label（「薪轉」）；不寫帳號、不寫金額。
//    cards：每張沒停用的卡一張小卡片（卡面色 WealthCardPalette），站在 tower 那座塔腳下，短管直直接上去（不交叉）；
//    dashed（自己繳）管子是虛線；旁邊小牌 label（下次動錢的日子「11/10」）。
//    頂樓地面一條矮牆、遠處一排淡樓（TripBoardSkyArt.paintFarRow）；白天藍天雲（天空那層已經畫了）；
//    夜裡塔頂一盞小燈、遠樓亮窗、水面一道月光反光（不是調暗）。
// B.「水位」.tide(WealthTideScene)：銀行帳戶頁看板（band 132）。只畫這個帳戶，前 30 天到後 30 天（days 天）。
//    水面＝level[i]（0…1，資料端已經把最低到最高縮好；zeroLevel 有值＝0 元那條線的位置，存摺上變負的那幾天水面在它下面）。
//    今天以前實線、深一點；今天以後虛線、淡一點（預估）。每件動到存摺的事一塊白底小牌 events（≤ 4 個字：「GoGo」「薪」「交割」
//    「電信」「轉出」），往下的小牌下面一個 ▾、往上的 ▴；同一天資料端已經併成一塊。今天停一艘白色小紙船；anchorDay 那天水面一個小勾；
//    shortage 那幾天水面下一道 warn 細線（不寫字）。
// C.「帳單週期」.cardCycle(WealthCycleScene)：信用卡頁看板（band 132）。橫軸從上一期第一天到下一期截止日（days 天）。
//    一天一根細柱 bars（height 0…1，資料端開根號縮好）；billed＝已經結帳那期（卡面色），不然本期（淡一點）；今天以後點狀軌道。
//    marks：.close 結帳日一面白色小旗（小牌「結帳」）、.due 截止日一面卡面色旗（小牌「繳款」；paid＝旗上一個小勾）。
//    今天站一張小卡片（卡面色）。closingFrom...todayIndex 那段（結帳日前 3 天）底下淡淡一條（不寫字）。白天遠方淡樓、夜裡星空與旗子小燈。
// D. 卡面 WealthCardFacePanel（項目卡左邊 108pt、緊湊 46pt）：你選的卡面色漸層（WealthCardPalette）、晶片、
//    [wave.3.right] 感應圖示、「•••• 5678」只有末四碼（遮住時 last4＝「••••」）；disabled 整張灰。
//    **不畫完整卡號、不畫有效月、不畫銀行商標**。左上小膠囊、左下手寫字是 MoneyPanel 的 badge／scriptWord 疊上去的，這裡不畫。
//
// 規矩（U3 §5、坑 #4／#5／#15／#27）：數字一律在頭部的 Text 裡，風景上的字只是裝飾；只畫在 rect（band）裡；
// 開頭 guard r.width > 120, r.height > 60；小牌先排好位置、互相讓開（撞到就錯開或拿掉卡片日期），最後才畫
// （FinDriveScene／FinHouseScene 的切法）；淺深各一組顏色（DriveInk 的寫法）；資料端已經把位置換成 0…1 或天數，這裡不碰日期。
// 顏色照 judge §3.16：水 活存 3F7FE0／6FA8FF、外幣 168F8C／4FD0C0、定存 B07D0A／FFC14D；卡費斜線 D9631A／FFB45E。
//
// 分工：資料（下面四個 struct＋WealthCardPalette 的淺色值）主控寫好、G1（WealthPageData）／G2（WealthCardData）產生，
// 不要改欄位；畫法（三個 paint、WealthCardFacePanel 的 body）G4 實作。
//
// [v25.567] E.「踏腳石」.stones(WealthStonesScene)：保單頁看板（band 112；judge §4.4 風景）。一條小路，一年一塊石頭（count 塊），
//    繳過的（paid 塊）實心、還沒繳的空心；今天站著一個小人（standing：第幾塊，-1＝還沒生效站在路口）；路的盡頭一把傘
//   （保障到某年）或 ∞（lifelong：終身保障，畫在最右邊）；open＝沒填繳費年期：只畫到今天那一塊，盡頭不畫傘。
//    不寫任何字、不寫金額；淺深各一組顏色（保單主題 76：8FE0B0→23885A）；石頭多（> 20）時縮小、間距照 rect 寬平均。
//    資料主控寫好（WealthStonesScene）、G2（WealthCardData.buildPolicy）產生；畫法 paintStones G2 實作。
//    [G2] 畫好了：草坡上一條左低右高的沙色小路、扁橢圓石頭（> 20 塊縮小、最小 5pt）、圓頭兩筆身體的小人、綠傘（終身：路通到右邊＋線畫的 ∞；
//    open：最後一塊後面只剩虛線）。

/// 財富頁看板：頂樓水塔（一個銀行帳戶一座塔）
struct WealthTowerScene: Equatable {
    struct Tower: Equatable {
        enum Kind: Equatable {
            /// 台幣活存：藍水
            case live
            /// 外幣：青水＋塔身小旗（badge）
            case foreign
            /// 定存：金水＋塔身鎖頭＋小牌（badge「3/15」）
            case deposit
            /// 灰色空塔（只有卡、沒有銀行帳戶：卡站在它下面）
            case empty
        }
        /// 水位 0…1（√(存摺上÷最大那座)；負的、0 元＝0）
        var level: Double
        /// 水面上那一截斜線 0…1（還沒扣÷存摺上；比水還多＝1，斜線到塔底）
        var hatch: Double
        var kind: Kind
        /// 塔下小牌「薪轉」（暱稱，沒有寫銀行簡稱；併塔「其他」）
        var label: String
        /// 塔身小牌：外幣「US$」、定存「3/15」、併塔「＋3」；nil 不畫
        var badge: String?
        /// 負數、30 天內不夠扣：塔框 warn、斜線到塔底
        var warn: Bool
        /// 新手三座虛線空塔
        var dashed: Bool = false
        /// [v25.566] 定存 7 天內到期（含到期再決定、已經到期還沒決定）：鎖頭打開一半（judge §3.2；G1 畫）
        var lockOpen: Bool = false
    }
    struct Card: Equatable {
        /// 站在第幾座塔下（扣它卡費的那座；沒設＝那座 .empty 塔）
        var tower: Int
        /// 自己繳／每次問我：管子是虛線（接「通常從」那座）
        var dashed: Bool
        /// 卡面色 0–5（WealthCardPalette）
        var color: Int
        /// 旁邊小牌：下次動錢的日子「11/10」「10/27」
        var label: String
    }
    var towers: [Tower]
    var cards: [Card]

    /// 沒有東西可畫（保單頁 band 用不畫風景的天空時也用它，band 給小於 60 就什麼都不畫）
    static let empty = WealthTowerScene(towers: [], cards: [])
}

/// 銀行帳戶頁看板：這個帳戶前後 30 天的水位
struct WealthTideScene: Equatable {
    struct Event: Equatable {
        /// 第幾天（0＝最左邊那天）
        var day: Int
        /// ≤ 4 個字（「GoGo」「薪」「交割」「電信」「轉出」）
        var label: String
        /// 錢進來（▴）；false＝出去（▾）
        var up: Bool
    }
    /// 幾天（前 30＋今天＋後 30＝61）
    var days: Int
    /// 今天是第幾天（30）
    var todayIndex: Int
    /// 每天結束時的水面 0…1（count＝days；資料端用最低到最高縮好，留上下 8% 空間）
    var level: [Double]
    var events: [Event]
    /// 對存摺那天（水面一個小勾）；30 天內沒對過 nil
    var anchorDay: Int?
    /// 會不夠扣的那幾天（水面下一道 warn 細線）
    var shortage: [Int]
    /// 0 元那條線在 0…1 的哪裡（有負的才有；nil＝全部 ≥ 0）
    var zeroLevel: Double?
    /// 外幣帳戶（水是青色）
    var foreign: Bool
}

/// 信用卡頁看板：帳單週期（上一期第一天到下一期截止日）
struct WealthCycleScene: Equatable {
    struct Bar: Equatable {
        /// 第幾天
        var day: Int
        /// 0…1（那天刷多少，開根號縮好）
        var height: Double
        /// 已經結帳那期（卡面色）；false＝本期（淡一點）
        var billed: Bool
    }
    struct Mark: Equatable {
        enum Kind: Equatable {
            /// 結帳日：白色小旗＋小牌「結帳」
            case close
            /// 繳款截止日：卡面色旗＋小牌「繳款」
            case due
        }
        var day: Int
        var kind: Kind
        /// 已繳（截止日的旗上一個小勾）
        var paid: Bool
    }
    var days: Int
    var todayIndex: Int
    var bars: [Bar]
    var marks: [Mark]
    /// 卡面色 0–5
    var tint: Int
    /// 結帳日前 3 天那段的第一天（底下淡淡一條，到結帳日）；nil 不畫
    var closingFrom: Int?
    /// 結帳日前 3 天那段的最後一天（結帳日）
    var closingTo: Int?
}

/// [v25.567] 保單頁看板：踏腳石（一年一塊石頭；judge §4.4）
struct WealthStonesScene: Equatable {
    /// 石頭幾塊（繳費年期；沒填＝到今天為止的年數＋1；最多 40）
    var count: Int
    /// 繳過幾塊（實心；≤ count）
    var paid: Int
    /// 小人站在第幾塊（0 起；-1＝還沒生效，站在路口）
    var standing: Int
    /// 終身保障：路的盡頭畫 ∞（不畫傘）
    var lifelong: Bool
    /// 沒填繳費年期：只畫到今天那一塊，盡頭不畫傘、不畫 ∞
    var open: Bool
}

/// 信用卡卡面（項目卡左邊；judge §3.7「一張小卡片」）
struct WealthCardFace: Equatable {
    /// 卡面色 0–5（帳本 faceColor；WealthFacts.Card.faceColor）
    var color: Int
    /// 末四碼「5678」；遮住、沒填時「••••」
    var last4: String
    /// 停用：整張灰
    var disabled: Bool = false
}

/// 卡面 6 色（judge §3.16；淺色值主控照定案寫好，深色各壓暗一階由 G4 補在 bottom(_:dark:)）
enum WealthCardPalette {
    /// 表單的色點、名稱（紅橘、藍綠、綠、紫、黑金、粉）
    static let names = ["紅橘", "藍綠", "綠", "紫", "黑金", "粉"]
    private static let tops: [UInt32] = [0xFF8A5B, 0x4FC3D9, 0x7FDCB7, 0xB79CFF, 0x4A4A55, 0xFF9CBB]
    private static let bottoms: [UInt32] = [0xE0453A, 0x1F7A9C, 0x1B8F63, 0x6B4BE0, 0x1C1C24, 0xD63F72]
    /// [G4] 深色各壓暗一階（左上 ×0.84、右下 ×0.80）：白字對右下 5.9–18:1（淺色 4.07–16.9:1），黑金的金字對左上 5.4:1
    private static let topsDark: [UInt32] = [0xD6744C, 0x42A4B6, 0x6BB99A, 0x9A83D6, 0x3E3E47, 0xD6839D]
    private static let bottomsDark: [UInt32] = [0xB3372E, 0x19627D, 0x16724F, 0x563CB3, 0x16161D, 0xAB325B]

    private static func clamp(_ i: Int) -> Int { Swift.min(Swift.max(i, 0), 5) }

    /// 漸層左上
    static func top(_ i: Int, dark: Bool) -> Color { Color(tb: dark ? topsDark[clamp(i)] : tops[clamp(i)]) }
    /// 漸層右下
    static func bottom(_ i: Int, dark: Bool) -> Color { Color(tb: dark ? bottomsDark[clamp(i)] : bottoms[clamp(i)]) }
    /// 一個代表色（項目卡的色點、帳單週期的柱子、水塔下的小卡片）
    static func tint(_ i: Int) -> Color { Color(tb: bottoms[clamp(i)]) }
    /// 黑金卡的字是金色 D8B46A，其他白字
    static func ink(_ i: Int) -> Color { clamp(i) == 4 ? Color(tb: 0xD8B46A) : .white }
}

// MARK: - 畫法（G4，v25.564）
//
// 照 FinDriveScene／HealthBoardScenes 的切法：顏色一組 ink（淺深各一套）、尺寸一次算好（Geo）、
// 小牌先排位置（互相讓開，撞到就錯開，再撞就不畫那塊）、最後才畫。畫法照樣稿 wealth/mock/wealth.js
// （wTower、paintTowers、paintCycle、paintTide），JS Canvas 換成 GraphicsContext。
// 數字不畫進風景：小牌只有暱稱、日期、≤ 4 個字，看得到、不給讀（整張 Canvas 已經 accessibilityHidden）。

/// 三幅風景的顏色（judge §3.16；樣稿 wealth.js 的值）。深色是另一套夜景，不是把白天調暗
private struct WealthSceneInk {
    let dark: Bool
    // 水、卡費斜線、警告（MoneyTone.warn 的值）
    let waterLive: Color
    let waterForeign: Color
    let waterDeposit: Color
    let hatch: Color
    let warn: Color
    // 不鏽鋼塔
    let metal: [Gradient.Stop]
    let metalLine: Color
    let leg: Color
    let cap: Color
    let hoop: Color
    let shine: Color
    let ghostLine: Color      // 灰色空塔（只有卡）
    let newbieLine: Color     // 新手虛線塔
    let ghostFill: Color
    let foreignFlag: Color
    let flagPole: Color
    // 頂樓
    let roof: Color
    let roofSeam: Color
    let parapet: Color
    let parapetTop: Color
    // 小牌、管子
    let pillFill: Color
    let pillInk: Color
    let pillMuted: Color
    let pipe: Color
    // 水位
    let surface: Color
    let surfaceForeign: Color
    let leader: Color
    let tagFillFuture: Color
    let tagDash: Color
    let ripple: Color
    let boatStroke: Color
    // 帳單週期
    let closeFill: Color
    let closeStroke: Color
    let closeInk: Color
    let track: Color
    let trackDot: Color
    let today: Color
    // 錢進來 ▴、已繳的勾（綠）；錢出去 ▾（橘）
    let good: Color
    let down: Color
    let checkTick: Color

    static let lamp = Color(tb: 0xFFD98A)
    static let lampGlow = Color(tb: 0xFFC56B)
    static let lampStem = Color(tb: 0x8A96B8)
    static let moonGlint = Color(tb: 0xF4EBC8)
    static let chipGold = Color(tb: 0xF2D58A)
    static let checkGreen = Color(tb: 0x1F9D57)
    static let lockInkLight = Color(tb: 0xA86A00)
    static let lockInkDark = Color(tb: 0x8A5E00)
    /// 黑金卡在夜景裡改金色（黑色放夜空看不到）
    static let gold = Color(tb: 0xE2C485)
    static let goldDeep = Color(tb: 0xB08F4A)
    static let blackInk = Color(tb: 0x1C1C24)

    init(dark: Bool) {
        self.dark = dark
        waterLive = dark ? Color(tb: 0x6FA8FF) : Color(tb: 0x3F7FE0)
        waterForeign = dark ? Color(tb: 0x4FD0C0) : Color(tb: 0x168F8C)
        waterDeposit = dark ? Color(tb: 0xFFC14D) : Color(tb: 0xB07D0A)
        hatch = dark ? Color(tb: 0xFFB45E) : Color(tb: 0xD9631A)
        warn = dark ? Color(tb: 0xFFC14D) : Color(tb: 0xA65300)
        if dark {
            metal = [.init(color: Color(tb: 0x46516E), location: 0),
                     .init(color: Color(tb: 0x5C6678), location: 0.3),
                     .init(color: Color(tb: 0x3A4256), location: 0.75),
                     .init(color: Color(tb: 0x2B3247), location: 1)]
        } else {
            metal = [.init(color: Color(tb: 0xE3E9F1), location: 0),
                     .init(color: Color(tb: 0xFFFFFF), location: 0.3),
                     .init(color: Color(tb: 0xC9D3DF), location: 0.72),
                     .init(color: Color(tb: 0x9AA6B5), location: 1)]
        }
        metalLine = dark ? Color(tb: 0x8C9AC4, 0.9) : Color(tb: 0x8A9BB4, 0.95)
        leg = dark ? Color(tb: 0x7F8DB6) : Color(tb: 0x6E7F99)
        cap = dark ? Color(tb: 0x6B78A3) : Color(tb: 0x9AA8BD)
        hoop = dark ? Color.white.opacity(0.12) : Color(tb: 0x8A9BB4, 0.35)
        shine = Color.white.opacity(dark ? 0.1 : 0.55)
        ghostLine = dark ? Color(tb: 0xA3B2D9, 0.9) : Color(tb: 0x8A93A6)
        newbieLine = dark ? Color(tb: 0x8DB7FF, 0.8) : Color(tb: 0x6C8BD8)
        ghostFill = Color.white.opacity(dark ? 0.04 : 0.4)
        foreignFlag = dark ? Color(tb: 0x1F9C93) : Color(tb: 0x168F8C)
        flagPole = dark ? Color(tb: 0xCFE0FF) : Color(tb: 0x3E4A6E)
        roof = dark ? Color(tb: 0x141C3A) : Color(tb: 0xDDE6F0)
        roofSeam = dark ? Color.white.opacity(0.05) : Color(tb: 0xC6D3E2, 0.8)
        parapet = dark ? Color(tb: 0x222C55) : Color(tb: 0xC7D4E4)
        parapetTop = dark ? Color(tb: 0x3A4778) : Color.white.opacity(0.95)
        pillFill = dark ? Color(tb: 0x1C2646, 0.95) : Color.white.opacity(0.95)
        pillInk = dark ? Color(tb: 0xE6ECFF) : Color(tb: 0x0B1B45)
        pillMuted = dark ? Color(tb: 0xA3B2D9) : Color(tb: 0x6B7898)
        pipe = dark ? Color(tb: 0xA3B2D9) : Color(tb: 0x5E6F8A)
        surface = dark ? Color(tb: 0xCFE0FF) : Color(tb: 0x1D4FA8)
        surfaceForeign = dark ? Color(tb: 0xC8F5EE) : Color(tb: 0x0B6563)
        leader = dark ? Color.white.opacity(0.45) : Color(tb: 0x1D3A7A, 0.35)
        tagFillFuture = dark ? Color(tb: 0x1C2646, 0.8) : Color.white.opacity(0.82)
        tagDash = dark ? Color(tb: 0x8DB7FF, 0.6) : Color(tb: 0x6C8BD8, 0.7)
        ripple = Color.white.opacity(dark ? 0.25 : 0.55)
        boatStroke = dark ? Color(tb: 0x0B1B45, 0.4) : Color(tb: 0x1D3A7A, 0.55)
        closeFill = dark ? Color(tb: 0x1C2646) : Color.white
        closeStroke = dark ? Color(tb: 0x8DB7FF, 0.6) : Color(tb: 0x9AA8C8)
        closeInk = dark ? Color(tb: 0xE6ECFF) : Color(tb: 0x0B1B45)
        track = dark ? Color(tb: 0x8FA2D6) : Color(tb: 0x7D93B8)
        trackDot = dark ? Color(tb: 0x8FA2D6, 0.9) : Color(tb: 0x9DB0CF)
        today = dark ? Color(tb: 0x8DB7FF) : Color(tb: 0x2F6FE0)
        good = dark ? Color(tb: 0x5BD99A) : Color(tb: 0x1F9D57)
        down = dark ? Color(tb: 0xFFB45E) : Color(tb: 0xD9631A)
        checkTick = dark ? Color(tb: 0x0B1B45) : Color.white
    }

    func water(_ kind: WealthTowerScene.Tower.Kind) -> Color {
        switch kind {
        case .foreign: return waterForeign
        case .deposit: return waterDeposit
        case .live, .empty: return waterLive
        }
    }

    private static func isBlackGold(_ i: Int) -> Bool { Swift.min(Swift.max(i, 0), 5) == 4 }

    /// 風景裡的卡面色（帳單週期的柱子、繳款旗、水塔下的日期字）：照卡面淺色那組；深色的黑金卡改金色
    func cardTop(_ i: Int) -> Color {
        dark && Self.isBlackGold(i) ? Self.gold : WealthCardPalette.top(i, dark: false)
    }

    func cardBottom(_ i: Int) -> Color {
        dark && Self.isBlackGold(i) ? Self.goldDeep : WealthCardPalette.bottom(i, dark: false)
    }

    /// 繳款旗上的字（卡面色底）
    func cardFlagInk(_ i: Int) -> Color {
        dark && Self.isBlackGold(i) ? Self.blackInk : Color.white
    }

    /// 水塔下小牌的日期字：淺色用卡面深的那端，深色用亮的那端
    func cardLabelInk(_ i: Int) -> Color {
        dark ? cardTop(i) : cardBottom(i)
    }
}

/// 一塊小牌（先排好位置，最後才畫；照 DrivePill）
private struct WealthScenePill {
    let text: String
    var box: CGRect
    let fill: Color
    let ink: Color
    let size: CGFloat
    let weight: Font.Weight
    var rounded: Bool = false
    var shadow: Bool = false
}

/// 一座塔的尺寸（照 DriveGeometry：一次算好，畫每一塊都讀這裡）
private struct WealthTowerGeo {
    let index: Int
    let cx: CGFloat
    let bw: CGFloat
    /// 塔身上緣（圓頂底下那一條）
    let top: CGFloat
    /// 塔身下緣（腳的上端）
    let bodyBot: CGFloat
    /// 頂樓地面
    let floor: CGFloat

    var x: CGFloat { cx - bw / 2 }
    var bh: CGFloat { bodyBot - top }
    var bodyRect: CGRect { CGRect(x: x, y: top, width: bw, height: bh) }
    /// 塔身＋圓頂、腳（腳往外張到 ±0.432 塔寬）：別座塔的卡片日期要讓開
    var footprints: [CGRect] {
        [CGRect(x: x - 1, y: top - 9, width: bw + 2, height: bodyBot - top + 9),
         CGRect(x: cx - bw * 0.45, y: bodyBot, width: bw * 0.9, height: floor - bodyBot)]
    }
}

/// 塔腳下的一張小卡片
private struct WealthTowerCardSpot {
    let card: WealthTowerScene.Card
    let box: CGRect
    /// 管子接到塔身的哪一點；灰色空塔不接管子（nil）
    let pipeTop: CGPoint?
}

/// 整幅水塔排好的位置
private struct WealthTowerPlan {
    var floor: CGFloat = 0
    var towers: [WealthTowerGeo] = []
    var cards: [WealthTowerCardSpot] = []
    var labels: [WealthScenePill] = []
    var dates: [WealthScenePill] = []
}

/// 水位的尺寸
private struct WealthTideGeo {
    let rect: CGRect
    let count: Int
    let x0: CGFloat
    let dw: CGFloat
    let top: CGFloat
    let bot: CGFloat

    init(rect r: CGRect, count n: Int) {
        rect = r
        count = n
        x0 = r.minX + 12
        dw = (r.width - 24) / CGFloat(Swift.max(1, n - 1))
        top = r.minY + 36
        bot = r.maxY - 3
    }

    func x(_ i: Int) -> CGFloat { x0 + dw * CGFloat(i) }

    func y(_ level: Double) -> CGFloat {
        let f = CGFloat(Swift.min(1, Swift.max(0, level)))
        return bot - (bot - top) * f
    }
}

/// 水位上的一塊小牌（會動到存摺的事）
private struct WealthTideTag {
    let label: String
    let up: Bool
    let future: Bool
    /// 細線插在哪一天
    let x: CGFloat
    /// 細線往下接到水面的哪裡
    let surface: CGFloat
    let box: CGRect
    let textWidth: CGFloat
}

/// 帳單週期的尺寸
private struct WealthCycleGeo {
    let rect: CGRect
    let days: Int
    /// 軌道（地面）那一條
    let gy: CGFloat
    let x0: CGFloat
    let dw: CGFloat
    /// 柱子最高多高
    let barMax: CGFloat

    init(rect r: CGRect, days d: Int) {
        let ground = r.maxY - 26
        rect = r
        days = d
        gy = ground
        x0 = r.minX + 14
        dw = (r.width - 30) / CGFloat(Swift.max(1, d - 1))
        barMax = Swift.max(16, Swift.min(54, ground - r.minY - 40))
    }

    func x(_ i: Int) -> CGFloat { x0 + dw * CGFloat(i) }
}

/// 一面旗（結帳白旗／繳款卡面色旗）
private struct WealthCycleFlag {
    let x: CGFloat
    /// 旗桿頂
    let top: CGFloat
    let cloth: CGRect
    /// 靠右邊的旗往左飄（不被切掉）
    let flip: Bool
    let due: Bool
    let paid: Bool
    let future: Bool
    let label: String

    /// 已繳的小勾：旗面外側
    var checkCenter: CGPoint { CGPoint(x: flip ? cloth.minX - 6 : cloth.maxX + 6, y: cloth.midY) }

    /// 旗面＋小勾（別面旗要讓開）
    var box: CGRect {
        guard paid else { return cloth }
        let c = checkCenter
        return cloth.union(CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10))
    }
}

extension MoneyBoardSky {
    // MARK: 共用：量字、小牌、小卡片

    private static func wealthTextWidth(_ ctx: GraphicsContext, _ s: String, size: CGFloat, weight: Font.Weight,
                                        rounded: Bool = false) -> CGFloat {
        let design: Font.Design = rounded ? .rounded : .default
        let font = Font.system(size: size, weight: weight, design: design)
        let t = ctx.resolve(Text(s).font(font))
        return t.measure(in: CGSize(width: 400, height: 40)).width
    }

    /// 放不下就從後面一個字一個字拿掉、補「…」
    private static func wealthFit(_ ctx: GraphicsContext, _ s: String, size: CGFloat, weight: Font.Weight,
                                  maxWidth: CGFloat) -> String {
        if wealthTextWidth(ctx, s, size: size, weight: weight) <= maxWidth { return s }
        var chars = Array(s)
        while chars.count > 1 {
            chars.removeLast()
            let candidate = String(chars) + "…"
            if wealthTextWidth(ctx, candidate, size: size, weight: weight) <= maxWidth { return candidate }
        }
        return String(chars)
    }

    /// 小牌的框：量好字寬、置中在 center、整塊夾在 bounds 裡（照 healthPillBox；位置取整數，坑 #5）
    private static func wealthPillBox(_ ctx: GraphicsContext, _ s: String, center c: CGPoint, size: CGFloat,
                                      weight: Font.Weight, rounded: Bool, height h: CGFloat, pad: CGFloat,
                                      bounds r: CGRect) -> CGRect {
        let tw = wealthTextWidth(ctx, s, size: size, weight: weight, rounded: rounded)
        let w = Swift.max(h, (tw + pad).rounded(.up))
        let x = Swift.min(Swift.max(r.minX + 2, (c.x - w / 2).rounded()), r.maxX - w - 2)
        let y = Swift.min(Swift.max(r.minY + 1, (c.y - h / 2).rounded()), r.maxY - h - 1)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private static func wealthDrawPill(_ ctx: inout GraphicsContext, _ p: WealthScenePill) {
        let shape = Path(roundedRect: p.box, cornerRadius: p.box.height / 2)
        if p.shadow {
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: Color.black.opacity(0.18), radius: 1.2, x: 0, y: 0.6))
                layer.fill(shape, with: .color(p.fill))
            }
        } else {
            ctx.fill(shape, with: .color(p.fill))
        }
        let design: Font.Design = p.rounded ? .rounded : .default
        let font = Font.system(size: p.size, weight: p.weight, design: design)
        let t = ctx.resolve(Text(p.text).font(font).foregroundStyle(p.ink))
        ctx.draw(t, at: CGPoint(x: p.box.midX, y: p.box.midY), anchor: .center)
    }

    private static func wealthHits(_ box: CGRect, _ list: [CGRect]) -> Bool {
        list.contains { $0.intersects(box) }
    }

    /// 風景裡的一張小卡片：你選的卡面色、晶片、一條磁條（照樣稿 wMiniCard）
    private static func wealthMiniCard(_ ctx: inout GraphicsContext, _ b: CGRect, color i: Int, dark: Bool) {
        let shape = Path(roundedRect: b, cornerRadius: 2.4)
        let face = Gradient(colors: [WealthCardPalette.top(i, dark: dark), WealthCardPalette.bottom(i, dark: dark)])
        let shading = GraphicsContext.Shading.linearGradient(face, startPoint: CGPoint(x: b.minX, y: b.minY),
                                                             endPoint: CGPoint(x: b.maxX, y: b.maxY))
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: Color.black.opacity(0.22), radius: 1.2, x: 0, y: 0.8))
            layer.fill(shape, with: shading)
        }
        ctx.stroke(shape, with: .color(Color.white.opacity(dark ? 0.35 : 0.8)), lineWidth: 0.7)
        let chip = CGRect(x: b.minX + b.width * 0.16, y: b.minY + b.height * 0.3,
                          width: b.width * 0.24, height: b.height * 0.3)
        ctx.fill(Path(roundedRect: chip, cornerRadius: 0.8), with: .color(WealthSceneInk.chipGold))
        let stripe = CGRect(x: b.minX + b.width * 0.16, y: b.minY + b.height * 0.74, width: b.width * 0.56, height: 0.9)
        ctx.fill(Path(stripe), with: .color(Color.white.opacity(0.7)))
    }

    // MARK: A. 頂樓水塔（財富頁看板）

    static func paintTowers(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: WealthTowerScene,
                            dark: Bool, seed: Int) {
        guard r.width > 120, r.height > 60, !s.towers.isEmpty else { return }
        let ink = WealthSceneInk(dark: dark)
        // 只畫在 band 裡：剪在副本上（呼叫端之後還要用 ctx 畫手寫問候，不能剪到它）
        var band = ctx
        band.clip(to: Path(r))
        let plan = wealthTowerLayout(band, rect: r, scene: s, ink: ink)
        wealthRooftop(&band, rect: r, floor: plan.floor, ink: ink, seed: seed)
        for g in plan.towers {
            wealthTowerBody(&band, g, tower: s.towers[g.index], rect: r, ink: ink)
        }
        for c in plan.cards {
            wealthTowerCard(&band, c, ink: ink)
        }
        for p in plan.labels {
            wealthDrawPill(&band, p)
        }
        for p in plan.dates {
            wealthDrawPill(&band, p)
        }
    }

    /// 排版：塔寬依座數縮放、間距平均（最多 6 座）；有卡的時候塔往左靠一點，右邊留給卡片的日期小牌
    private static func wealthTowerLayout(_ ctx: GraphicsContext, rect r: CGRect, scene s: WealthTowerScene,
                                          ink: WealthSceneInk) -> WealthTowerPlan {
        var plan = WealthTowerPlan()
        let n = s.towers.count
        let floor = (r.maxY - 22).rounded()
        let legH: CGFloat = 20
        let bodyBot = floor - legH
        let bh = Swift.max(24, Swift.min(54, bodyBot - r.minY - 26))
        let top = bodyBot - bh
        let slot = (r.width - 24) / CGFloat(Swift.max(n, 1))
        let bw = Swift.min(40, Swift.max(24, (slot * 0.42).rounded()))
        let offset: CGFloat = s.cards.isEmpty ? 0.5 : 0.42
        plan.floor = floor
        for (i, t) in s.towers.enumerated() {
            let spread = r.minX + 12 + slot * (CGFloat(i) + offset)
            let cx = n == 1 ? r.midX : spread
            // 灰色空塔（只有卡）寬一點：兩張卡站得下
            let wide = t.kind == .empty && !t.dashed
            let width = wide ? Swift.min(slot * 0.8, bw + 8) : bw
            plan.towers.append(WealthTowerGeo(index: i, cx: cx.rounded(), bw: width.rounded(), top: top,
                                              bodyBot: bodyBot, floor: floor))
        }
        plan.labels = wealthTowerLabels(ctx, plan.towers, scene: s, slot: slot, rect: r, ink: ink)
        plan.cards = wealthTowerCardSpots(plan.towers, scene: s, slot: slot, rect: r)
        plan.dates = wealthTowerDates(ctx, plan, rect: r, ink: ink)
        return plan
    }

    /// 塔下白底小牌（暱稱）：寬度不超過一格，放不下就截短補「…」
    private static func wealthTowerLabels(_ ctx: GraphicsContext, _ towers: [WealthTowerGeo],
                                          scene s: WealthTowerScene, slot: CGFloat, rect r: CGRect,
                                          ink: WealthSceneInk) -> [WealthScenePill] {
        var out: [WealthScenePill] = []
        let maxW = towers.count == 1 ? r.width - 8 : slot - 4
        for g in towers {
            let t = s.towers[g.index]
            let raw = t.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            let text = wealthFit(ctx, raw, size: 8.5, weight: .heavy, maxWidth: maxW - 10)
            let box = wealthPillBox(ctx, text, center: CGPoint(x: g.cx, y: g.floor + 10), size: 8.5, weight: .heavy,
                                    rounded: false, height: 13, pad: 10, bounds: r)
            let inkColor = t.kind == .empty ? ink.pillMuted : ink.pillInk
            out.append(WealthScenePill(text: text, box: box, fill: ink.pillFill, ink: inkColor, size: 8.5,
                                       weight: .heavy))
        }
        return out
    }

    /// 卡：站在那座塔腳下，同一座塔的卡左右錯開；管子直直往上接塔身（灰色空塔不接）
    /// 卡很多（同一個帳戶扣 5、6 張卡）時間距縮小、疊成一疊，整疊不超過一格，也不畫出 band
    private static func wealthTowerCardSpots(_ towers: [WealthTowerGeo], scene s: WealthTowerScene,
                                             slot: CGFloat, rect r: CGRect) -> [WealthTowerCardSpot] {
        var out: [WealthTowerCardSpot] = []
        let cw: CGFloat = 20
        let ch: CGFloat = 13
        let lo = r.minX + 2 + cw / 2
        let hi = r.maxX - 2 - cw / 2
        for g in towers {
            let list = s.cards.filter { $0.tower == g.index }
            guard !list.isEmpty else { continue }
            let kind = s.towers[g.index].kind
            let room = Swift.max(cw, Swift.min(slot, r.width) - 6 - cw)
            let gap = list.count > 1 ? Swift.min(24, room / CGFloat(list.count - 1)) : 0
            let mid = CGFloat(list.count - 1) / 2
            for (k, c) in list.enumerated() {
                let spread = g.cx + (CGFloat(k) - mid) * gap
                let ccx = Swift.min(Swift.max(spread, lo), hi).rounded()
                let box = CGRect(x: ccx - cw / 2, y: g.floor - ch - 1.5, width: cw, height: ch)
                var pipeTop: CGPoint? = nil
                if kind != .empty {
                    let px = Swift.min(Swift.max(ccx, g.x + 3), g.x + g.bw - 3)
                    pipeTop = CGPoint(x: px, y: g.bodyBot)
                }
                out.append(WealthTowerCardSpot(card: c, box: box, pipeTop: pipeTop))
            }
        }
        return out
    }

    /// 卡片旁邊的日期小牌：先試右邊、再試左邊；撞到別張卡、別的日期、別座塔就拿掉（坑 #27）
    private static func wealthTowerDates(_ ctx: GraphicsContext, _ plan: WealthTowerPlan, rect r: CGRect,
                                         ink: WealthSceneInk) -> [WealthScenePill] {
        var out: [WealthScenePill] = []
        var blockers: [CGRect] = plan.cards.map { $0.box.insetBy(dx: -1, dy: 0) }
        let h: CGFloat = 12
        let size: CGFloat = 8
        for spot in plan.cards {
            let text = spot.card.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let tw = wealthTextWidth(ctx, text, size: size, weight: .black, rounded: true)
            let w = (tw + 7).rounded(.up)
            let y = (spot.box.midY - 1 - h / 2).rounded()
            // 自己那座塔的腳可以壓（樣稿就是這樣），別座塔的塔身和腳要讓開
            let others = plan.towers.filter { $0.index != spot.card.tower }.flatMap { $0.footprints }
            let tries = [CGRect(x: spot.box.maxX + 3, y: y, width: w, height: h),
                         CGRect(x: spot.box.minX - 3 - w, y: y, width: w, height: h)]
            for box in tries {
                guard box.minX >= r.minX + 2, box.maxX <= r.maxX - 2 else { continue }
                if wealthHits(box, blockers) || wealthHits(box, others) { continue }
                blockers.append(box.insetBy(dx: -1, dy: 0))
                out.append(WealthScenePill(text: text, box: box, fill: ink.pillFill,
                                           ink: ink.cardLabelInk(spot.card.color), size: size, weight: .black,
                                           rounded: true, shadow: true))
                break
            }
        }
        return out
    }

    /// 遠處一排淡樓（夜裡亮窗）＋頂樓地面（磁磚縫）＋一道矮牆
    private static func wealthRooftop(_ ctx: inout GraphicsContext, rect r: CGRect, floor fy: CGFloat,
                                      ink: WealthSceneInk, seed: Int) {
        TripBoardSkyArt.paintFarRow(&ctx, width: r.width, ground: fy - 3, band: 44, ink: farInk(dark: ink.dark),
                                    seed: seed)
        ctx.fill(Path(CGRect(x: r.minX, y: fy, width: r.width, height: r.maxY - fy)), with: .color(ink.roof))
        var seams = Path()
        var sx = r.minX + 10
        while sx < r.maxX {
            seams.addRect(CGRect(x: sx, y: fy + 1, width: 0.8, height: r.maxY - fy - 1))
            sx += 24
        }
        ctx.fill(seams, with: .color(ink.roofSeam))
        ctx.fill(Path(CGRect(x: r.minX, y: fy - 4, width: r.width, height: 4)), with: .color(ink.parapet))
        ctx.fill(Path(CGRect(x: r.minX, y: fy - 4, width: r.width, height: 1)), with: .color(ink.parapetTop))
    }

    /// 一座塔：腳 → 塔身（不鏽鋼）→ 水（＋卡費斜線）→ 箍與反光 → 塔框（warn）→ 蓋子 → 夜裡的燈 → 小旗／鎖頭／併塔小牌
    private static func wealthTowerBody(_ ctx: inout GraphicsContext, _ g: WealthTowerGeo,
                                        tower t: WealthTowerScene.Tower, rect r: CGRect, ink: WealthSceneInk) {
        let ghost = t.dashed || t.kind == .empty
        wealthTowerLegs(&ctx, g, ghost: ghost, dashedLine: t.dashed, ink: ink)
        let body = Path(roundedRect: g.bodyRect, cornerRadius: 3.5)
        let dome = wealthTowerDome(g)
        if ghost {
            let line = t.dashed ? ink.newbieLine : ink.ghostLine
            let style = StrokeStyle(lineWidth: 1.2, dash: [3, 2.5])
            ctx.fill(body, with: .color(ink.ghostFill))
            ctx.stroke(body, with: .color(line), style: style)
            ctx.stroke(dome, with: .color(line), style: style)
            return
        }
        let metal = GraphicsContext.Shading.linearGradient(Gradient(stops: ink.metal),
                                                           startPoint: CGPoint(x: g.x, y: 0),
                                                           endPoint: CGPoint(x: g.x + g.bw, y: 0))
        ctx.fill(body, with: metal)
        ctx.fill(dome, with: metal)
        wealthTowerWater(&ctx, g, tower: t, ink: ink)
        wealthTowerHoops(&ctx, g, ink: ink)
        // 負的、不夠扣、還沒扣的比水還多：塔框 warn（檔頭 A：hatch ≥ 1 或 warn）
        if t.warn || t.hatch >= 1 {
            ctx.stroke(body, with: .color(ink.warn), lineWidth: 1.8)
        } else {
            ctx.stroke(body, with: .color(ink.metalLine), lineWidth: 0.8)
        }
        ctx.stroke(dome, with: .color(ink.metalLine), lineWidth: 0.8)
        let capRect = CGRect(x: g.cx - 3.5, y: g.top - 7.5, width: 7, height: 3)
        ctx.fill(Path(roundedRect: capRect, cornerRadius: 1.2), with: .color(ink.cap))
        if ink.dark {
            wealthTowerLamp(&ctx, g)
        }
        switch t.kind {
        case .foreign:
            if let b = t.badge, !b.isEmpty {
                wealthTowerFlag(&ctx, g, text: b, rect: r, ink: ink)
            }
        case .deposit:
            wealthTowerLock(&ctx, g, badge: t.badge, open: t.lockOpen, ink: ink)
        case .live:
            if let b = t.badge, !b.isEmpty {
                wealthTowerBadge(&ctx, g, text: b, rect: r, ink: ink)
            }
        case .empty:
            break
        }
    }

    /// 圓頂（塔身上面那一片弧）
    private static func wealthTowerDome(_ g: WealthTowerGeo) -> Path {
        var dome = Path()
        dome.move(to: CGPoint(x: g.x + 1, y: g.top + 1))
        dome.addQuadCurve(to: CGPoint(x: g.x + g.bw - 1, y: g.top + 1), control: CGPoint(x: g.cx, y: g.top - 12))
        dome.closeSubpath()
        return dome
    }

    /// 四隻腳（前面兩隻＋後面兩隻淡一點）＋交叉斜撐；空塔是虛線
    private static func wealthTowerLegs(_ ctx: inout GraphicsContext, _ g: WealthTowerGeo, ghost: Bool,
                                        dashedLine: Bool, ink: WealthSceneInk) {
        var front = Path()
        for k: CGFloat in [-0.4, 0.4] {
            front.move(to: CGPoint(x: g.cx + g.bw * k, y: g.bodyBot))
            front.addLine(to: CGPoint(x: g.cx + g.bw * k * 1.08, y: g.floor))
        }
        var brace = Path()
        brace.move(to: CGPoint(x: g.cx - g.bw * 0.4, y: g.bodyBot + 2))
        brace.addLine(to: CGPoint(x: g.cx + g.bw * 0.42, y: g.floor - 2))
        brace.move(to: CGPoint(x: g.cx + g.bw * 0.4, y: g.bodyBot + 2))
        brace.addLine(to: CGPoint(x: g.cx - g.bw * 0.42, y: g.floor - 2))
        if ghost {
            let line = dashedLine ? ink.newbieLine : ink.ghostLine
            ctx.stroke(front, with: .color(line), style: StrokeStyle(lineWidth: 1.4, dash: [2, 2]))
            ctx.stroke(brace, with: .color(line), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
            return
        }
        var back = Path()
        for k: CGFloat in [-0.17, 0.17] {
            back.move(to: CGPoint(x: g.cx + g.bw * k, y: g.bodyBot))
            back.addLine(to: CGPoint(x: g.cx + g.bw * k * 1.1, y: g.floor - 1))
        }
        ctx.stroke(back, with: .color(ink.leg.opacity(0.45)), lineWidth: 1.2)
        ctx.stroke(front, with: .color(ink.leg), lineWidth: 1.6)
        ctx.stroke(brace, with: .color(ink.leg), lineWidth: 0.8)
    }

    /// 塔裡的水（水位＝level）＋水面亮線；夜裡水面下一道月光反光；負的空塔塔底一道 warn
    private static func wealthTowerWater(_ ctx: inout GraphicsContext, _ g: WealthTowerGeo,
                                         tower t: WealthTowerScene.Tower, ink: WealthSceneInk) {
        let window = CGRect(x: g.x + 3, y: g.top + 4, width: g.bw - 6, height: g.bh - 7)
        guard window.width > 2, window.height > 2 else { return }
        let lv = CGFloat(Swift.min(1, Swift.max(0, t.level)))
        let wh = (window.height * lv).rounded()
        var inner = ctx
        inner.clip(to: Path(roundedRect: window, cornerRadius: 2))
        guard wh >= 1 else {
            if t.warn {
                let base = CGRect(x: window.minX, y: window.maxY - 2, width: window.width, height: 2)
                inner.fill(Path(base), with: .color(ink.warn))
            }
            return
        }
        let water = CGRect(x: window.minX, y: window.maxY - wh, width: window.width, height: wh)
        let col = ink.water(t.kind)
        let fade = Gradient(colors: [col.opacity(ink.dark ? 0.95 : 0.78), col])
        inner.fill(Path(water), with: .linearGradient(fade, startPoint: CGPoint(x: 0, y: water.minY),
                                                      endPoint: CGPoint(x: 0, y: water.maxY)))
        wealthTowerHatch(&inner, water: water, tower: t, ink: ink)
        let edge = CGRect(x: water.minX, y: water.minY, width: water.width, height: 1.2)
        inner.fill(Path(edge), with: .color(Color.white.opacity(ink.dark ? 0.75 : 0.85)))
        if ink.dark && wh > 7 {
            let glint = CGRect(x: water.minX + water.width * 0.2, y: water.minY + 3,
                               width: water.width * 0.32, height: 1.4)
            inner.fill(Path(roundedRect: glint, cornerRadius: 0.7), with: .color(WealthSceneInk.moonGlint.opacity(0.55)))
        }
    }

    /// 水面上那一截斜線（快被扣走的：卡費＋交割）；比水還多或 warn＝斜線到塔底（同資產小鎮 finHatch）
    private static func wealthTowerHatch(_ ctx: inout GraphicsContext, water: CGRect, tower t: WealthTowerScene.Tower,
                                         ink: WealthSceneInk) {
        let full = t.warn || t.hatch >= 1
        let f: CGFloat = full ? 1 : CGFloat(Swift.max(0, t.hatch))
        guard f > 0 else { return }
        let hh = Swift.min(water.height, Swift.max(2, (water.height * f).rounded()))
        let zone = CGRect(x: water.minX, y: water.minY, width: water.width, height: hh)
        ctx.fill(Path(zone), with: .color(ink.hatch.opacity(ink.dark ? 0.28 : 0.22)))
        finHatch(&ctx, zone, color: ink.hatch.opacity(0.95), gap: 3.6)
        if !full {
            let line = CGRect(x: zone.minX, y: zone.maxY - 0.6, width: zone.width, height: 1.2)
            ctx.fill(Path(line), with: .color(ink.hatch.opacity(0.9)))
        }
    }

    /// 塔身兩道箍＋左邊一道光
    private static func wealthTowerHoops(_ ctx: inout GraphicsContext, _ g: WealthTowerGeo, ink: WealthSceneInk) {
        var hoops = Path()
        for k: CGFloat in [0.34, 0.68] {
            hoops.addRect(CGRect(x: g.x + 0.5, y: (g.top + g.bh * k).rounded(), width: g.bw - 1, height: 1))
        }
        ctx.fill(hoops, with: .color(ink.hoop))
        let shine = CGRect(x: g.x + g.bw * 0.16, y: g.top + 3, width: 2.2, height: Swift.max(0, g.bh - 6))
        ctx.fill(Path(shine), with: .color(ink.shine))
    }

    /// 夜裡塔頂一盞小燈（暖光暈）
    private static func wealthTowerLamp(_ ctx: inout GraphicsContext, _ g: WealthTowerGeo) {
        let lx = g.cx + g.bw * 0.28
        let ly = g.top - 9
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            layer.fill(Path(ellipseIn: CGRect(x: lx - 6, y: ly - 5, width: 12, height: 10)),
                       with: .color(WealthSceneInk.lampGlow.opacity(0.55)))
        }
        ctx.fill(Path(CGRect(x: lx - 0.4, y: ly + 1.5, width: 0.8, height: 3)), with: .color(WealthSceneInk.lampStem))
        ctx.fill(Path(ellipseIn: CGRect(x: lx - 1.8, y: ly - 1.8, width: 3.6, height: 3.6)),
                 with: .color(WealthSceneInk.lamp))
    }

    /// 外幣：塔身右上一面小旗（「US$」）；最右邊那座放不下就往左飄
    private static func wealthTowerFlag(_ ctx: inout GraphicsContext, _ g: WealthTowerGeo, text: String,
                                        rect r: CGRect, ink: WealthSceneInk) {
        let font = Font.system(size: 6.5, weight: .black, design: .rounded)
        let t = ctx.resolve(Text(text).font(font).foregroundStyle(Color.white))
        let tw = t.measure(in: CGSize(width: 200, height: 40)).width
        let fw = Swift.max(18, (tw + 10).rounded(.up))
        let fh: CGFloat = 9
        let py = g.top + 4
        let flip = g.x + g.bw - 2 + fw > r.maxX - 2
        let px = flip ? g.x + 2 : g.x + g.bw - 2
        let s: CGFloat = flip ? -1 : 1
        ctx.fill(Path(CGRect(x: px - 0.55, y: py - 1, width: 1.1, height: 17)), with: .color(ink.flagPole))
        var cloth = Path()
        cloth.move(to: CGPoint(x: px + s, y: py))
        cloth.addLine(to: CGPoint(x: px + fw * s, y: py))
        cloth.addLine(to: CGPoint(x: px + (fw - 3) * s, y: py + fh / 2))
        cloth.addLine(to: CGPoint(x: px + fw * s, y: py + fh))
        cloth.addLine(to: CGPoint(x: px + s, y: py + fh))
        cloth.closeSubpath()
        ctx.fill(cloth, with: .color(ink.foreignFlag))
        let textX = px + s * (fw - 2) / 2
        ctx.draw(t, at: CGPoint(x: textX.rounded(), y: py + fh / 2), anchor: .center)
    }

    /// 定存：塔身一個鎖頭（白圓底）＋到期小牌（「3/15」，有才畫）。
    /// [v25.566] open：到期前 7 天（含到期再決定已經到期）鎖頭打開一半——鎖身照畫，鎖環右腳離開鎖身往上提 2.5pt、
    /// 整個鎖環往左上斜一點（最高點仍在白圓裡）
    private static func wealthTowerLock(_ ctx: inout GraphicsContext, _ g: WealthTowerGeo, badge: String?, open: Bool,
                                        ink: WealthSceneInk) {
        let cy = (g.top + g.bh * 0.32).rounded()
        ctx.fill(Path(ellipseIn: CGRect(x: g.cx - 7.5, y: cy - 7.5, width: 15, height: 15)),
                 with: .color(Color.white.opacity(0.94)))
        let lockInk = ink.dark ? WealthSceneInk.lockInkDark : WealthSceneInk.lockInkLight
        ctx.fill(Path(roundedRect: CGRect(x: g.cx - 3.4, y: cy - 0.8, width: 6.8, height: 5.2), cornerRadius: 1.2),
                 with: .color(lockInk))
        let shackle = open ? wealthLockShackleOpen(cx: g.cx, cy: cy) : wealthLockShackleClosed(cx: g.cx, cy: cy)
        ctx.stroke(shackle, with: .color(lockInk), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        guard let badge, !badge.isEmpty else { return }
        let area = g.bodyRect.insetBy(dx: -8, dy: 0)
        let box = wealthPillBox(ctx, badge, center: CGPoint(x: g.cx, y: g.top + g.bh * 0.66), size: 7.5,
                                weight: .black, rounded: true, height: 11, pad: 7, bounds: area)
        wealthDrawPill(&ctx, WealthScenePill(text: badge, box: box, fill: Color.white.opacity(0.94),
                                             ink: WealthSceneInk.lockInkDark, size: 7.5, weight: .black,
                                             rounded: true))
    }

    /// 鎖環（關著）：兩隻腳都插進鎖身（鎖身上緣 cy − 0.8）
    private static func wealthLockShackleClosed(cx: CGFloat, cy: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: cx - 2.3, y: cy - 0.6))
        p.addLine(to: CGPoint(x: cx - 2.3, y: cy - 2.2))
        p.addQuadCurve(to: CGPoint(x: cx + 2.3, y: cy - 2.2), control: CGPoint(x: cx, y: cy - 6.4))
        p.addLine(to: CGPoint(x: cx + 2.3, y: cy - 0.6))
        return p
    }

    /// [v25.566] 鎖環（打開一半）：左腳照樣插在鎖身裡、往外斜一點；右腳離開鎖身往上提 2.5pt（腳尖 cy − 3.1，
    /// 圓頭到 cy − 2.4，跟鎖身上緣隔 1.6pt）；最高點約 cy − 5.5（加線寬一半 0.7 仍在白圓 7.5 裡）
    private static func wealthLockShackleOpen(cx: CGFloat, cy: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: cx - 2.3, y: cy - 0.6))
        p.addLine(to: CGPoint(x: cx - 2.6, y: cy - 2.8))
        p.addQuadCurve(to: CGPoint(x: cx + 2.0, y: cy - 3.9), control: CGPoint(x: cx - 0.6, y: cy - 7.6))
        p.addLine(to: CGPoint(x: cx + 2.0, y: cy - 3.1))
        return p
    }

    /// 併塔：塔身上一塊小牌「＋3」
    private static func wealthTowerBadge(_ ctx: inout GraphicsContext, _ g: WealthTowerGeo, text: String,
                                         rect r: CGRect, ink: WealthSceneInk) {
        let box = wealthPillBox(ctx, text, center: CGPoint(x: g.cx, y: g.top + g.bh * 0.3), size: 8, weight: .black,
                                rounded: true, height: 12, pad: 8, bounds: r)
        wealthDrawPill(&ctx, WealthScenePill(text: text, box: box, fill: ink.pillFill, ink: ink.pillInk, size: 8,
                                             weight: .black, rounded: true))
    }

    /// 塔腳下的小卡片＋管子（自己繳／每次問我是虛線）
    private static func wealthTowerCard(_ ctx: inout GraphicsContext, _ c: WealthTowerCardSpot, ink: WealthSceneInk) {
        if let top = c.pipeTop {
            var pipe = Path()
            pipe.move(to: CGPoint(x: c.box.midX, y: c.box.minY))
            pipe.addLine(to: top)
            if c.card.dashed {
                ctx.stroke(pipe, with: .color(ink.pipe), style: StrokeStyle(lineWidth: 2, dash: [2, 1.6]))
            } else {
                ctx.stroke(pipe, with: .color(ink.pipe), lineWidth: 2)
            }
        }
        wealthMiniCard(&ctx, c.box, color: c.card.color, dark: ink.dark)
    }

    // MARK: B. 水位（銀行帳戶頁看板）

    static func paintTide(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: WealthTideScene,
                          dark: Bool, seed: Int) {
        guard r.width > 120, r.height > 60, s.days > 1 else { return }
        let n = Swift.min(s.days, s.level.count)
        guard n > 1 else { return }
        let ink = WealthSceneInk(dark: dark)
        let g = WealthTideGeo(rect: r, count: n)
        let ti = Swift.min(Swift.max(0, s.todayIndex), n - 1)
        let levels = Array(s.level.prefix(n))
        // 只畫在 band 裡（剪在副本上）
        var band = ctx
        band.clip(to: Path(r))
        TripBoardSkyArt.paintFarRow(&band, width: r.width, ground: r.minY + 62, band: 34, ink: farInk(dark: dark),
                                    seed: seed)
        wealthTideWater(&band, g, levels: levels, today: ti, foreign: s.foreign, ink: ink)
        wealthTideRipples(&band, g, levels: levels, today: ti, ink: ink, seed: seed)
        if let z = s.zeroLevel {
            wealthTideZero(&band, g, level: z, ink: ink)
        }
        wealthTideShortage(&band, g, levels: levels, days: s.shortage, ink: ink)
        let boat = CGPoint(x: g.x(ti).rounded(), y: g.y(levels[ti]).rounded())
        let check = wealthTideCheckSpot(g, levels: levels, anchor: s.anchorDay, boat: boat)
        var avoid: [CGRect] = [CGRect(x: boat.x - 9, y: boat.y - 14, width: 18, height: 16)]
        if let c = check {
            avoid.append(CGRect(x: c.x - 6.5, y: c.y - 6.5, width: 13, height: 13))
        }
        let tags = wealthTideTags(band, g, levels: levels, events: s.events, today: ti, avoid: avoid)
        for t in tags {
            wealthTideDrawTag(&band, t, ink: ink)
        }
        if let c = check {
            wealthTideCheck(&band, center: c, ink: ink)
        }
        wealthTideBoat(&band, at: boat, ink: ink)
        wealthTideToday(&band, g, levels: levels, today: ti, boat: boat)
    }

    /// 水：一天一階；今天以前實心深一點、以後淡（預估）；水面線過去實線、未來虛線
    private static func wealthTideWater(_ ctx: inout GraphicsContext, _ g: WealthTideGeo, levels: [Double],
                                        today ti: Int, foreign: Bool, ink: WealthSceneInk) {
        let r = g.rect
        let col = foreign ? ink.waterForeign : ink.waterLive
        let shape = wealthTideShape(g, levels: levels)
        let cut = g.x(ti) + g.dw / 2
        let from = CGPoint(x: 0, y: g.top)
        let to = CGPoint(x: 0, y: r.maxY)
        let pastFade = Gradient(colors: [col.opacity(ink.dark ? 0.85 : 0.75), col])
        let futureFade = Gradient(colors: [col.opacity(ink.dark ? 0.32 : 0.26), col.opacity(ink.dark ? 0.5 : 0.42)])
        var past = ctx
        past.clip(to: Path(CGRect(x: r.minX, y: r.minY, width: Swift.max(0, cut - r.minX), height: r.height)))
        past.fill(shape, with: .linearGradient(pastFade, startPoint: from, endPoint: to))
        var future = ctx
        future.clip(to: Path(CGRect(x: cut, y: r.minY, width: Swift.max(0, r.maxX - cut), height: r.height)))
        future.fill(shape, with: .linearGradient(futureFade, startPoint: from, endPoint: to))
        let line = foreign ? ink.surfaceForeign : ink.surface
        ctx.stroke(wealthTidePastLine(g, levels: levels, today: ti), with: .color(line), lineWidth: 1.4)
        if ti < g.count - 1 {
            ctx.stroke(wealthTideFutureLine(g, levels: levels, today: ti),
                       with: .color(line.opacity(ink.dark ? 0.8 : 0.7)),
                       style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5]))
        }
    }

    private static func wealthTideShape(_ g: WealthTideGeo, levels: [Double]) -> Path {
        var p = Path()
        let half = g.dw / 2
        p.move(to: CGPoint(x: g.x(0) - half, y: g.rect.maxY))
        for i in 0..<g.count {
            let y = g.y(levels[i])
            p.addLine(to: CGPoint(x: g.x(i) - half, y: y))
            p.addLine(to: CGPoint(x: g.x(i) + half, y: y))
        }
        p.addLine(to: CGPoint(x: g.x(g.count - 1) + half, y: g.rect.maxY))
        p.closeSubpath()
        return p
    }

    private static func wealthTidePastLine(_ g: WealthTideGeo, levels: [Double], today ti: Int) -> Path {
        var p = Path()
        let half = g.dw / 2
        for i in 0...ti {
            let y = g.y(levels[i])
            let left = CGPoint(x: g.x(i) - half, y: y)
            if i == 0 {
                p.move(to: left)
            } else {
                p.addLine(to: left)
            }
            p.addLine(to: CGPoint(x: g.x(i) + half, y: y))
        }
        return p
    }

    private static func wealthTideFutureLine(_ g: WealthTideGeo, levels: [Double], today ti: Int) -> Path {
        var p = Path()
        let half = g.dw / 2
        p.move(to: CGPoint(x: g.x(ti) + half, y: g.y(levels[ti])))
        guard ti + 1 < g.count else { return p }
        for i in (ti + 1)..<g.count {
            let y = g.y(levels[i])
            p.addLine(to: CGPoint(x: g.x(i) - half, y: y))
            p.addLine(to: CGPoint(x: g.x(i) + half, y: y))
        }
        return p
    }

    /// 過去那段水裡幾道白色波紋
    private static func wealthTideRipples(_ ctx: inout GraphicsContext, _ g: WealthTideGeo, levels: [Double],
                                          today ti: Int, ink: WealthSceneInk, seed: Int) {
        guard ti > 0 else { return }
        var rnd = InkRandom(seed &* 3 &+ 5)
        var p = Path()
        for _ in 0..<10 {
            let i = Swift.min(ti, Int(rnd.next() * Double(ti)))
            let x = g.x(i)
            let y = g.y(levels[i]) + 6 + CGFloat(rnd.next()) * 14
            if y > g.rect.maxY - 4 { continue }
            p.move(to: CGPoint(x: x, y: y))
            p.addQuadCurve(to: CGPoint(x: x + 8, y: y), control: CGPoint(x: x + 4, y: y - 1.2))
        }
        ctx.stroke(p, with: .color(ink.ripple), lineWidth: 0.9)
    }

    /// 0 元那條線（有負的才有）：warn 色細虛線，水面掉到它下面＝存摺上變負的
    private static func wealthTideZero(_ ctx: inout GraphicsContext, _ g: WealthTideGeo, level: Double,
                                       ink: WealthSceneInk) {
        let y = g.y(level).rounded() + 0.5
        var p = Path()
        p.move(to: CGPoint(x: g.x(0) - g.dw / 2, y: y))
        p.addLine(to: CGPoint(x: g.x(g.count - 1) + g.dw / 2, y: y))
        ctx.stroke(p, with: .color(ink.warn.opacity(0.75)), style: StrokeStyle(lineWidth: 0.9, dash: [3, 2]))
    }

    /// 會不夠扣的那幾天：水面下一道 warn 細線（不寫字）
    private static func wealthTideShortage(_ ctx: inout GraphicsContext, _ g: WealthTideGeo, levels: [Double],
                                           days: [Int], ink: WealthSceneInk) {
        var p = Path()
        for i in days where i >= 0 && i < g.count {
            // 水很淺時不畫到 band 外
            let y = Swift.min(g.y(levels[i]) + 2.4, g.bot - 1.8)
            p.addRect(CGRect(x: g.x(i) - g.dw / 2, y: y, width: g.dw, height: 1.8))
        }
        guard !p.isEmpty else { return }
        ctx.fill(p, with: .color(ink.warn))
    }

    /// 對存摺那天的小勾（水面上方）；剛好是今天就移到紙船左邊
    private static func wealthTideCheckSpot(_ g: WealthTideGeo, levels: [Double], anchor: Int?,
                                            boat: CGPoint) -> CGPoint? {
        guard let a = anchor, a >= 0, a < g.count else { return nil }
        var x = g.x(a)
        if abs(x - boat.x) < 14 {
            // 今天在最左邊時往右讓（不切到 band 外）
            x = boat.x - 14 >= g.rect.minX + 7 ? boat.x - 14 : boat.x + 14
        }
        let y = g.y(levels[a]) - 7.5
        return CGPoint(x: x.rounded(), y: y.rounded())
    }

    /// 小牌：會動到存摺的事（往下 ▾、往上 ▴）。撞到就往上錯開（最多 4 次），還是撞就不畫那塊（坑 #27）
    private static func wealthTideTags(_ ctx: GraphicsContext, _ g: WealthTideGeo, levels: [Double],
                                       events: [WealthTideScene.Event], today ti: Int,
                                       avoid: [CGRect]) -> [WealthTideTag] {
        let r = g.rect
        let ph: CGFloat = 13
        var placed: [CGRect] = []
        var out: [WealthTideTag] = []
        for e in events where e.day >= 0 && e.day < g.count {
            let label = String(e.label.prefix(4))
            guard !label.isEmpty else { continue }
            let tw = wealthTextWidth(ctx, label, size: 8, weight: .heavy)
            let pw = (tw + 17).rounded(.up)
            let x = g.x(e.day)
            let prev = levels[Swift.max(0, e.day - 1)]
            let yb = Swift.min(g.y(prev), g.y(levels[e.day]))
            let px = Swift.min(Swift.max(r.minX + 3, (x - pw / 2).rounded()), r.maxX - pw - 3)
            var box = CGRect(x: px, y: (yb - 10 - ph).rounded(), width: pw, height: ph)
            var tries = 0
            while tries < 4, wealthHits(box.insetBy(dx: -2, dy: -1), placed + avoid) {
                box.origin.y -= ph + 2
                tries += 1
            }
            box.origin.y = Swift.max(r.minY + 2, box.origin.y)
            if wealthHits(box.insetBy(dx: -2, dy: -1), placed + avoid) { continue }
            placed.append(box)
            out.append(WealthTideTag(label: label, up: e.up, future: e.day > ti, x: x, surface: yb, box: box,
                                     textWidth: tw))
        }
        return out
    }

    private static func wealthTideDrawTag(_ ctx: inout GraphicsContext, _ t: WealthTideTag, ink: WealthSceneInk) {
        let b = t.box
        if t.surface - 1 > b.maxY {
            var leader = Path()
            leader.move(to: CGPoint(x: t.x, y: b.maxY))
            leader.addLine(to: CGPoint(x: t.x, y: t.surface - 1))
            ctx.stroke(leader, with: .color(ink.leader), lineWidth: 0.8)
        }
        let shape = Path(roundedRect: b, cornerRadius: b.height / 2)
        ctx.fill(shape, with: .color(t.future ? ink.tagFillFuture : ink.pillFill))
        if t.future {
            ctx.stroke(shape, with: .color(ink.tagDash), style: StrokeStyle(lineWidth: 0.8, dash: [2, 1.5]))
        }
        let text = ctx.resolve(Text(t.label).font(.system(size: 8, weight: .heavy)).foregroundStyle(ink.pillInk))
        ctx.draw(text, at: CGPoint(x: b.minX + 5, y: b.midY), anchor: .leading)
        let tx = b.minX + 5 + t.textWidth + 6
        let cy = b.midY
        var tri = Path()
        if t.up {
            tri.move(to: CGPoint(x: tx - 3, y: cy + 1.8))
            tri.addLine(to: CGPoint(x: tx + 3, y: cy + 1.8))
            tri.addLine(to: CGPoint(x: tx, y: cy - 2.4))
        } else {
            tri.move(to: CGPoint(x: tx - 3, y: cy - 1.8))
            tri.addLine(to: CGPoint(x: tx + 3, y: cy - 1.8))
            tri.addLine(to: CGPoint(x: tx, y: cy + 2.4))
        }
        tri.closeSubpath()
        ctx.fill(tri, with: .color(t.up ? ink.good : ink.down))
    }

    /// 對存摺：白圓＋綠勾
    private static func wealthTideCheck(_ ctx: inout GraphicsContext, center c: CGPoint, ink: WealthSceneInk) {
        let dot = Path(ellipseIn: CGRect(x: c.x - 5.5, y: c.y - 5.5, width: 11, height: 11))
        ctx.fill(dot, with: .color(Color.white))
        ctx.stroke(dot, with: .color(ink.good), lineWidth: 1)
        var tick = Path()
        tick.move(to: CGPoint(x: c.x - 2.6, y: c.y - 0.1))
        tick.addLine(to: CGPoint(x: c.x - 0.7, y: c.y + 1.9))
        tick.addLine(to: CGPoint(x: c.x + 2.8, y: c.y - 2.1))
        ctx.stroke(tick, with: .color(WealthSceneInk.checkGreen),
                   style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
    }

    /// 今天：一艘白色小紙船停在水面
    private static func wealthTideBoat(_ ctx: inout GraphicsContext, at p: CGPoint, ink: WealthSceneInk) {
        var hull = Path()
        hull.move(to: CGPoint(x: p.x - 8, y: p.y - 4))
        hull.addLine(to: CGPoint(x: p.x + 8, y: p.y - 4))
        hull.addLine(to: CGPoint(x: p.x + 5, y: p.y + 1))
        hull.addLine(to: CGPoint(x: p.x - 5, y: p.y + 1))
        hull.closeSubpath()
        var sail = Path()
        sail.move(to: CGPoint(x: p.x - 1, y: p.y - 4))
        sail.addLine(to: CGPoint(x: p.x - 1, y: p.y - 13))
        sail.addLine(to: CGPoint(x: p.x + 6, y: p.y - 5))
        sail.closeSubpath()
        for part in [hull, sail] {
            ctx.fill(part, with: .color(Color.white))
            ctx.stroke(part, with: .color(ink.boatStroke), lineWidth: 0.8)
        }
    }

    /// 「今天」寫在紙船底下的水底，靠今天那一階的右緣往左寫（整個字落在實心的過去水裡；右邊淡淡的預估水上白字讀不到）。
    /// 水太淺寫不下就不寫，紙船本身就是今天
    /// 字蓋到的每一天（今天往左兩三階）水都要夠深，不然白字會浮在天空上
    private static func wealthTideToday(_ ctx: inout GraphicsContext, _ g: WealthTideGeo, levels: [Double],
                                        today ti: Int, boat: CGPoint) {
        let t = ctx.resolve(Text("今天").font(.system(size: 8, weight: .heavy)).foregroundStyle(Color.white))
        let size = t.measure(in: CGSize(width: 100, height: 30))
        let right = (boat.x + g.dw / 2 - 2).rounded()
        let at = CGPoint(x: Swift.max(g.rect.minX + size.width + 2, right), y: g.rect.maxY - 3)
        let need = at.y - size.height - 2
        var i = ti
        while i >= 0 {
            if g.x(i) + g.dw / 2 <= at.x - size.width { break }
            if g.y(levels[i]) > need { return }
            i -= 1
        }
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: Color(tb: 0x0B1B45, 0.45), radius: 1, x: 0, y: 0.5))
            layer.draw(t, at: at, anchor: .bottomTrailing)
        }
    }

    // MARK: E. [v25.567] 踏腳石（保單頁看板；G2 實作畫法，主控先放空的：什麼都不畫也編得過）

    static func paintStones(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: WealthStonesScene,
                            dark: Bool, seed: Int) {
        guard r.width > 120, r.height > 60, s.count > 0 else { return }
        let n = Swift.min(s.count, 60)
        let paid = Swift.min(Swift.max(0, s.paid), n)
        // 顏色（保單主題 76：8FE0B0→23885A；深色是夜裡的草坡，另一組，不是調暗）
        let hillTop = dark ? Color(tb: 0x1B4A40) : Color(tb: 0xD3EEDB)
        let hillBottom = dark ? Color(tb: 0x0F2A26) : Color(tb: 0xA9DCB9)
        let road = dark ? Color(tb: 0x34466E) : Color(tb: 0xF3E9D2)
        let roadEdge = dark ? Color(tb: 0x4A5E8F) : Color(tb: 0xD9C7A0)
        let stoneTop = dark ? Color(tb: 0x9BEBC0) : Color(tb: 0x8FE0B0)
        let stoneBottom = dark ? Color(tb: 0x2FA36B) : Color(tb: 0x23885A)
        let stoneLine = dark ? Color(tb: 0x7FD9A6, 0.9) : Color(tb: 0x23885A, 0.8)
        let hollowFill = dark ? Color(tb: 0x0E1530, 0.55) : Color.white.opacity(0.78)
        let tuftInk = dark ? Color(tb: 0x2E6B57) : Color(tb: 0x6DBE86)
        let personInk = dark ? Color(tb: 0xE6ECFF) : Color(tb: 0x0B1B45)
        let markInk = dark ? stoneTop : stoneBottom
        let shadow = Color.black.opacity(dark ? 0.3 : 0.13)

        // 只畫在 band 裡（剪在副本上；呼叫端之後還要用 ctx 畫手寫問候）
        var band = ctx
        band.clip(to: Path(r))

        // 小路：左低右高一條緩坡，帶一點起伏（每塊石頭、小人、傘的高度都讀這一支）
        let yLeft = r.maxY - 20
        let yRight = r.maxY - Swift.min(40, r.height * 0.36)
        let phase = Double(Swift.abs(seed % 7)) * 0.45
        func roadY(_ x: CGFloat) -> CGFloat {
            let t = Double(Swift.min(1, Swift.max(0, (x - r.minX) / r.width)))
            let ease = t * t * (3 - 2 * t)
            let wave = sin(t * Double.pi * 1.6 + phase) * 2.2
            return yLeft + (yRight - yLeft) * CGFloat(ease) + CGFloat(wave)
        }

        // 石頭排在 rect 寬 8%～88%（一塊的時候在中間）；> 20 塊縮小，最小 5pt
        let x0 = r.minX + r.width * 0.08
        let x1 = r.minX + r.width * 0.88
        let gap: CGFloat = n > 1 ? (x1 - x0) / CGFloat(n - 1) : (x1 - x0)
        let shrink: CGFloat = n > 20 ? 0.62 : 0.72
        let stoneW = Swift.min(20, Swift.max(5, gap * shrink))
        let stoneH = Swift.max(3, stoneW * 0.5)
        let roadW = Swift.min(14, Swift.max(9, stoneH * 2.2))
        func stoneX(_ i: Int) -> CGFloat {
            n > 1 ? x0 + gap * CGFloat(i) : (x0 + x1) / 2
        }
        let firstX = stoneX(0)
        let lastX = stoneX(n - 1)
        // 一塊的時候不用整段寬當間距（傘、路口、小人往前站都照一步 36pt）
        let step: CGFloat = n > 1 ? gap : 36
        // 盡頭：傘在最後一塊後面一點；終身的 ∞ 靠最右邊（路一直通過去）
        let umbrellaX = Swift.min(r.maxX - 16, lastX + Swift.max(16, step * 0.8))
        let infinityX = Swift.min(r.maxX - 12, Swift.max(r.maxX - 20, lastX + 14))
        let markX: CGFloat = s.lifelong ? infinityX : umbrellaX
        let roadEnd: CGFloat
        if s.open {
            roadEnd = lastX + Swift.max(10, step * 0.5)
        } else if s.lifelong {
            roadEnd = r.maxX + 6
        } else {
            roadEnd = umbrellaX + 4
        }

        // 草坡（跟著路起伏，再自己慢慢彎一點）
        var hill = Path()
        hill.move(to: CGPoint(x: r.minX, y: r.maxY))
        var hx = r.minX
        while hx < r.maxX + 6 {
            let wobble = CGFloat(sin(Double(hx) / 41 + phase * 2)) * 3
            hill.addLine(to: CGPoint(x: hx, y: roadY(hx) - roadW / 2 - 8 + wobble))
            hx += 6
        }
        hill.addLine(to: CGPoint(x: r.maxX + 6, y: r.maxY))
        hill.closeSubpath()
        let hillGradient = Gradient(colors: [hillTop, hillBottom])
        band.fill(hill, with: .linearGradient(hillGradient, startPoint: CGPoint(x: r.midX, y: yRight - roadW - 14),
                                              endPoint: CGPoint(x: r.midX, y: r.maxY)))

        // 路下面幾叢小草（seed 固定位置）
        var rnd = InkRandom(seed &* 5 &+ 11)
        var tufts = Path()
        for _ in 0..<9 {
            let tx = r.minX + 6 + (r.width - 12) * CGFloat(rnd.next())
            let ty = roadY(tx) + roadW / 2 + 4 + CGFloat(rnd.next()) * 8
            guard ty < r.maxY - 2 else { continue }
            tufts.move(to: CGPoint(x: tx - 2, y: ty))
            tufts.addLine(to: CGPoint(x: tx - 2.8, y: ty - 3))
            tufts.move(to: CGPoint(x: tx, y: ty))
            tufts.addLine(to: CGPoint(x: tx, y: ty - 4))
            tufts.move(to: CGPoint(x: tx + 2, y: ty))
            tufts.addLine(to: CGPoint(x: tx + 2.8, y: ty - 3))
        }
        band.stroke(tufts, with: .color(tuftInk), style: StrokeStyle(lineWidth: 1, lineCap: .round))

        // 小路（沙色、兩側一道邊）；open：最後一塊後面只剩虛線（還不知道要繳幾年）
        var roadPath = Path()
        var rx = r.minX - 4
        roadPath.move(to: CGPoint(x: rx, y: roadY(rx)))
        while rx < roadEnd {
            rx = Swift.min(roadEnd, rx + 4)
            roadPath.addLine(to: CGPoint(x: rx, y: roadY(rx)))
        }
        band.stroke(roadPath, with: .color(roadEdge),
                    style: StrokeStyle(lineWidth: roadW + 2, lineCap: .round, lineJoin: .round))
        band.stroke(roadPath, with: .color(road), style: StrokeStyle(lineWidth: roadW, lineCap: .round, lineJoin: .round))
        if s.open && roadEnd < r.maxX - 10 {
            var dots = Path()
            var dx = roadEnd + 6
            dots.move(to: CGPoint(x: dx, y: roadY(dx)))
            while dx < r.maxX - 6 {
                dx = Swift.min(r.maxX - 6, dx + 4)
                dots.addLine(to: CGPoint(x: dx, y: roadY(dx)))
            }
            band.stroke(dots, with: .color(roadEdge.opacity(0.8)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1.5, 4.5]))
        }

        // 石頭：繳過的實心（保單綠漸層＋一點反光），還沒繳的白底描邊
        let stoneGradient = Gradient(colors: [stoneTop, stoneBottom])
        for i in 0..<n {
            let cx = stoneX(i)
            let cy = roadY(cx)
            let box = CGRect(x: cx - stoneW / 2, y: cy - stoneH / 2, width: stoneW, height: stoneH)
            let shape = Path(ellipseIn: box)
            if i < paid {
                band.fill(Path(ellipseIn: box.offsetBy(dx: 0, dy: 1.2)), with: .color(shadow))
                band.fill(shape, with: .linearGradient(stoneGradient, startPoint: CGPoint(x: cx, y: box.minY),
                                                       endPoint: CGPoint(x: cx, y: box.maxY)))
                band.stroke(shape, with: .color(stoneBottom.opacity(0.6)), lineWidth: 0.6)
                if stoneW >= 8 {
                    let glint = CGRect(x: box.minX + stoneW * 0.2, y: box.minY + stoneH * 0.18,
                                       width: stoneW * 0.32, height: stoneH * 0.28)
                    band.fill(Path(ellipseIn: glint), with: .color(Color.white.opacity(dark ? 0.35 : 0.55)))
                }
            } else {
                band.fill(shape, with: .color(hollowFill))
                band.stroke(shape, with: .color(stoneLine), lineWidth: stoneW >= 8 ? 1.1 : 0.8)
            }
        }

        // 盡頭：傘（保障到某年）或 ∞（終身）；open（沒填繳費年期）不畫
        if !s.open {
            let baseY = roadY(markX)
            if s.lifelong {
                // ∞：雙紐線（線畫的，不是字）
                let a: CGFloat = 9
                let c = CGPoint(x: markX, y: baseY - 15)
                var loop = Path()
                let steps = 48
                for k in 0...steps {
                    let t = Double(k) / Double(steps) * 2 * Double.pi
                    let sn = sin(t)
                    let d = 1 + sn * sn
                    let p = CGPoint(x: c.x + a * CGFloat(cos(t) / d), y: c.y + a * CGFloat(sn * cos(t) / d))
                    if k == 0 {
                        loop.move(to: p)
                    } else {
                        loop.addLine(to: p)
                    }
                }
                loop.closeSubpath()
                band.stroke(loop, with: .color(markInk), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            } else {
                let R: CGFloat = 11
                let cy = baseY - 22
                // 傘柄（底下彎一個鉤）＋傘尖
                var handle = Path()
                handle.move(to: CGPoint(x: markX, y: cy - R - 2.5))
                handle.addLine(to: CGPoint(x: markX, y: baseY - 4))
                handle.addQuadCurve(to: CGPoint(x: markX - 4, y: baseY - 4), control: CGPoint(x: markX - 2, y: baseY))
                band.stroke(handle, with: .color(personInk),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                // 傘面：上半圓（兩段三次曲線）＋下緣三個往上凹的小弧
                let k: CGFloat = 0.5523 * R
                var canopy = Path()
                canopy.move(to: CGPoint(x: markX - R, y: cy))
                canopy.addCurve(to: CGPoint(x: markX, y: cy - R), control1: CGPoint(x: markX - R, y: cy - k),
                                control2: CGPoint(x: markX - k, y: cy - R))
                canopy.addCurve(to: CGPoint(x: markX + R, y: cy), control1: CGPoint(x: markX + k, y: cy - R),
                                control2: CGPoint(x: markX + R, y: cy - k))
                let seg = 2 * R / 3
                for j in 0..<3 {
                    let xr = markX + R - seg * CGFloat(j)
                    canopy.addQuadCurve(to: CGPoint(x: xr - seg, y: cy), control: CGPoint(x: xr - seg / 2, y: cy - R * 0.24))
                }
                canopy.closeSubpath()
                band.fill(canopy, with: .linearGradient(stoneGradient, startPoint: CGPoint(x: markX, y: cy - R),
                                                        endPoint: CGPoint(x: markX, y: cy)))
                band.stroke(canopy, with: .color(stoneBottom.opacity(0.7)), lineWidth: 0.6)
                // 傘骨兩條
                var ribs = Path()
                ribs.move(to: CGPoint(x: markX, y: cy - R))
                ribs.addQuadCurve(to: CGPoint(x: markX - R / 3, y: cy - R * 0.2),
                                  control: CGPoint(x: markX - R * 0.42, y: cy - R * 0.72))
                ribs.move(to: CGPoint(x: markX, y: cy - R))
                ribs.addQuadCurve(to: CGPoint(x: markX + R / 3, y: cy - R * 0.2),
                                  control: CGPoint(x: markX + R * 0.42, y: cy - R * 0.72))
                band.stroke(ribs, with: .color(Color.white.opacity(dark ? 0.45 : 0.7)), lineWidth: 0.8)
            }
        }

        // 小人：站在第 standing 塊上（-1 還沒生效站在路口；繳完了站在最後一塊後面、傘前面）
        let px: CGFloat
        let feetY: CGFloat
        if s.standing < 0 {
            px = Swift.max(r.minX + 8, firstX - Swift.max(10, step * 0.6))
            feetY = roadY(px)
        } else if s.standing >= n {
            let ahead = lastX + Swift.max(9, step * 0.5)
            let limit: CGFloat = s.open ? r.maxX - 8 : markX - 12
            px = Swift.max(lastX + 4, Swift.min(ahead, limit))
            feetY = roadY(px)
        } else {
            px = stoneX(s.standing)
            feetY = roadY(px) - stoneH / 2 + 0.5
        }
        band.fill(Path(ellipseIn: CGRect(x: px - 4, y: feetY - 1, width: 8, height: 2.2)), with: .color(shadow))
        let hip = CGPoint(x: px, y: feetY - 6)
        let neck = CGPoint(x: px, y: feetY - 11.5)
        var legs = Path()
        legs.move(to: CGPoint(x: px - 2.6, y: feetY))
        legs.addLine(to: hip)
        legs.addLine(to: CGPoint(x: px + 2.6, y: feetY))
        var torso = Path()
        torso.move(to: hip)
        torso.addLine(to: neck)
        let limb = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
        band.stroke(legs, with: .color(personInk), style: limb)
        band.stroke(torso, with: .color(personInk), style: limb)
        let headR: CGFloat = 2.9
        band.fill(Path(ellipseIn: CGRect(x: px - headR, y: neck.y - 1 - headR * 2, width: headR * 2, height: headR * 2)),
                  with: .color(personInk))
    }

    // MARK: C. 帳單週期（信用卡頁看板）

    static func paintCardCycle(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: WealthCycleScene,
                               dark: Bool, seed: Int) {
        guard r.width > 120, r.height > 60, s.days > 1 else { return }
        let ink = WealthSceneInk(dark: dark)
        let g = WealthCycleGeo(rect: r, days: s.days)
        let ti = Swift.min(Swift.max(0, s.todayIndex), s.days - 1)
        // 只畫在 band 裡（剪在副本上）
        var band = ctx
        band.clip(to: Path(r))
        let flags = wealthCycleFlags(band, g, scene: s, today: ti)
        TripBoardSkyArt.paintFarRow(&band, width: r.width, ground: g.gy - 2, band: 44, ink: farInk(dark: dark),
                                    seed: seed)
        band.fill(Path(CGRect(x: r.minX, y: g.gy, width: r.width, height: r.maxY - g.gy)),
                  with: .color(groundFill(dark: dark)))
        wealthCycleClosing(&band, g, scene: s, ink: ink)
        wealthCycleBars(&band, g, scene: s, ink: ink)
        wealthCycleTrack(&band, g, today: ti, ink: ink)
        for f in flags {
            wealthCycleDrawFlag(&band, f, g: g, tint: s.tint, ink: ink)
        }
        wealthCycleTodayCard(&band, g, today: ti, tint: s.tint, dark: dark)
        wealthCycleTodayLabel(&band, g, today: ti, ink: ink)
    }

    /// 旗子先排位置：已經結帳那期（含還沒到的這期截止日）高、實線；下一期（還沒結帳）的矮一截、虛線（預估）；
    /// 兩面旗撞到就把後面那面放低（最多 3 次）
    /// 照樣稿②：10/27 繳款雖然在今天以後，是這期要繳的，旗子照樣高、實線；11/12 結帳、11/27 繳款才是預估
    private static func wealthCycleFlags(_ ctx: GraphicsContext, _ g: WealthCycleGeo, scene s: WealthCycleScene,
                                         today ti: Int) -> [WealthCycleFlag] {
        let r = g.rect
        let marks = s.marks.filter { $0.day >= 0 && $0.day < g.days }.sorted { $0.day < $1.day }
        let tall = Swift.max(24, Swift.min(58, g.gy - r.minY - 14))
        // 下一次結帳日（今天以後第一面結帳旗）；它和它後面的旗才是「還沒結帳的下一期」
        let nextClose: Int = marks.first(where: { $0.kind == .close && $0.day > ti })?.day ?? 0
        var out: [WealthCycleFlag] = []
        for m in marks {
            let due = m.kind == .due
            let label = due ? "繳款" : "結帳"
            let future = m.day > ti && m.day >= nextClose
            let x = g.x(m.day).rounded()
            let tw = wealthTextWidth(ctx, label, size: 7.5, weight: .black)
            let fw = (tw + 9).rounded(.up)
            let extra: CGFloat = m.paid ? 14 : 0
            let flip = x + fw + extra > r.maxX - 4
            var h = future ? tall - 12 : tall
            var flag = wealthCycleMakeFlag(x: x, height: h, ground: g.gy, clothWidth: fw, flip: flip, due: due,
                                           paid: m.paid, future: future, label: label)
            var tries = 0
            while tries < 3, out.contains(where: { $0.box.insetBy(dx: -2, dy: -1).intersects(flag.box) }) {
                h = Swift.max(20, h - 14)
                flag = wealthCycleMakeFlag(x: x, height: h, ground: g.gy, clothWidth: fw, flip: flip, due: due,
                                           paid: m.paid, future: future, label: label)
                tries += 1
            }
            out.append(flag)
        }
        return out
    }

    private static func wealthCycleMakeFlag(x: CGFloat, height h: CGFloat, ground gy: CGFloat, clothWidth fw: CGFloat,
                                            flip: Bool, due: Bool, paid: Bool, future: Bool,
                                            label: String) -> WealthCycleFlag {
        let top = (gy - h).rounded()
        let cloth = CGRect(x: flip ? x - fw : x, y: top, width: fw, height: 11)
        return WealthCycleFlag(x: x, top: top, cloth: cloth, flip: flip, due: due, paid: paid, future: future,
                               label: label)
    }

    /// 結帳日前 3 天：軌道底下淡淡一條（不寫字）
    private static func wealthCycleClosing(_ ctx: inout GraphicsContext, _ g: WealthCycleGeo, scene s: WealthCycleScene,
                                           ink: WealthSceneInk) {
        guard let a = s.closingFrom, let b = s.closingTo, a >= 0, a <= b, b < g.days else { return }
        let x0 = g.x(a) - g.dw / 2
        let x1 = g.x(b) + g.dw / 2
        let band = CGRect(x: x0, y: g.gy + 3, width: Swift.max(3, x1 - x0), height: 3)
        ctx.fill(Path(roundedRect: band, cornerRadius: 1.5),
                 with: .color(ink.cardBottom(s.tint).opacity(ink.dark ? 0.45 : 0.3)))
    }

    /// 一天一根細柱：已結帳那期卡面色漸層、本期淡一點
    private static func wealthCycleBars(_ ctx: inout GraphicsContext, _ g: WealthCycleGeo, scene s: WealthCycleScene,
                                        ink: WealthSceneInk) {
        let bw = Swift.max(1.6, g.dw * 0.62)
        let radius = Swift.min(1.2, bw / 2)
        let topColor = ink.cardTop(s.tint)
        let bottomColor = ink.cardBottom(s.tint)
        let soft = topColor.opacity(ink.dark ? 0.55 : 0.5)
        let billedFill = Gradient(colors: [topColor, bottomColor])
        for b in s.bars where b.day >= 0 && b.day < g.days {
            let f = CGFloat(Swift.min(1, Swift.max(0, b.height)))
            let h = (3 + g.barMax * f).rounded()
            let rect = CGRect(x: g.x(b.day) - bw / 2, y: g.gy - h, width: bw, height: h)
            let shape = Path(roundedRect: rect, cornerRadius: radius)
            if b.billed {
                ctx.fill(shape, with: .linearGradient(billedFill, startPoint: CGPoint(x: 0, y: rect.minY),
                                                      endPoint: CGPoint(x: 0, y: rect.maxY)))
            } else {
                ctx.fill(shape, with: .color(soft))
            }
        }
    }

    /// 軌道：今天以前實線，之後點狀
    private static func wealthCycleTrack(_ ctx: inout GraphicsContext, _ g: WealthCycleGeo, today ti: Int,
                                         ink: WealthSceneInk) {
        var line = Path()
        line.move(to: CGPoint(x: g.x(0) - 2, y: g.gy + 0.5))
        line.addLine(to: CGPoint(x: g.x(ti), y: g.gy + 0.5))
        ctx.stroke(line, with: .color(ink.track), lineWidth: 1.6)
        var dots = Path()
        var x = g.x(ti) + 4
        let end = g.x(g.days - 1) + 2
        while x < end {
            dots.addEllipse(in: CGRect(x: x - 1, y: g.gy - 0.5, width: 2, height: 2))
            x += 4.5
        }
        ctx.fill(dots, with: .color(ink.trackDot))
    }

    /// 一面旗：旗桿（以後的虛線、淡）→ 旗面 → 已繳小勾 → 夜裡旗桿頂一盞小燈
    private static func wealthCycleDrawFlag(_ ctx: inout GraphicsContext, _ f: WealthCycleFlag, g: WealthCycleGeo,
                                            tint: Int, ink: WealthSceneInk) {
        var pole = Path()
        pole.move(to: CGPoint(x: f.x, y: g.gy))
        pole.addLine(to: CGPoint(x: f.x, y: f.top))
        if f.future {
            ctx.stroke(pole, with: .color(ink.flagPole.opacity(0.7)), style: StrokeStyle(lineWidth: 1.1, dash: [2, 2]))
        } else {
            ctx.stroke(pole, with: .color(ink.flagPole), lineWidth: 1.1)
        }
        var cloth = ctx
        if f.future {
            cloth.opacity = 0.72
        }
        wealthCycleCloth(&cloth, f, tint: tint, ink: ink)
        if f.paid {
            wealthCycleCheck(&ctx, at: f.checkCenter, ink: ink)
        }
        if ink.dark && !f.future {
            wealthCycleLamp(&ctx, x: f.x, top: f.top)
        }
    }

    /// 旗面（燕尾）：結帳白旗、繳款卡面色旗
    private static func wealthCycleCloth(_ ctx: inout GraphicsContext, _ f: WealthCycleFlag, tint: Int,
                                         ink: WealthSceneInk) {
        let c = f.cloth
        let s: CGFloat = f.flip ? -1 : 1
        let fw = c.width
        var cloth = Path()
        cloth.move(to: CGPoint(x: f.x + 0.5 * s, y: c.minY))
        cloth.addLine(to: CGPoint(x: f.x + fw * s, y: c.minY))
        cloth.addLine(to: CGPoint(x: f.x + (fw - 3) * s, y: c.midY))
        cloth.addLine(to: CGPoint(x: f.x + fw * s, y: c.maxY))
        cloth.addLine(to: CGPoint(x: f.x + 0.5 * s, y: c.maxY))
        cloth.closeSubpath()
        let fill = f.due ? ink.cardBottom(tint) : ink.closeFill
        let stroke = f.due ? ink.cardBottom(tint) : ink.closeStroke
        let textInk = f.due ? ink.cardFlagInk(tint) : ink.closeInk
        ctx.fill(cloth, with: .color(fill))
        ctx.stroke(cloth, with: .color(stroke), lineWidth: 0.7)
        let t = ctx.resolve(Text(f.label).font(.system(size: 7.5, weight: .black)).foregroundStyle(textInk))
        let cx = f.x + s * (fw - 3) / 2
        ctx.draw(t, at: CGPoint(x: cx.rounded(), y: c.midY), anchor: .center)
    }

    private static func wealthCycleCheck(_ ctx: inout GraphicsContext, at c: CGPoint, ink: WealthSceneInk) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(ink.good))
        var tick = Path()
        tick.move(to: CGPoint(x: c.x - 2.4, y: c.y))
        tick.addLine(to: CGPoint(x: c.x - 0.6, y: c.y + 1.8))
        tick.addLine(to: CGPoint(x: c.x + 2.6, y: c.y - 1.8))
        ctx.stroke(tick, with: .color(ink.checkTick),
                   style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
    }

    private static func wealthCycleLamp(_ ctx: inout GraphicsContext, x: CGFloat, top: CGFloat) {
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            layer.fill(Path(ellipseIn: CGRect(x: x - 5, y: top - 7, width: 10, height: 8)),
                       with: .color(WealthSceneInk.lampGlow.opacity(0.5)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: top - 4, width: 3, height: 3)), with: .color(WealthSceneInk.lamp))
    }

    /// 今天：軌道上站一張小卡片（卡面色，微微斜）
    private static func wealthCycleTodayCard(_ ctx: inout GraphicsContext, _ g: WealthCycleGeo, today ti: Int,
                                             tint: Int, dark: Bool) {
        var card = ctx
        card.translateBy(x: g.x(ti), y: g.gy - 1)
        card.rotate(by: .radians(-0.08))
        wealthMiniCard(&card, CGRect(x: -9, y: -12, width: 18, height: 12), color: tint, dark: dark)
    }

    /// 軌道下面寫「今天」（日期在上面的字裡，風景不寫日期）
    private static func wealthCycleTodayLabel(_ ctx: inout GraphicsContext, _ g: WealthCycleGeo, today ti: Int,
                                              ink: WealthSceneInk) {
        let t = ctx.resolve(Text("今天").font(.system(size: 8, weight: .heavy)).foregroundStyle(ink.today))
        let m = t.measure(in: CGSize(width: 100, height: 30))
        let lo = g.rect.minX + 2 + m.width / 2
        let hi = g.rect.maxX - 2 - m.width / 2
        let x = Swift.min(Swift.max(lo, g.x(ti)), hi)
        ctx.draw(t, at: CGPoint(x: x.rounded(), y: g.gy + 8), anchor: .top)
    }
}

// MARK: - D. 信用卡卡面

/// 信用卡卡面（Equatable＋.equatable()：輸入一樣不重畫；MoneyPanel／MoneyThumb 已經接好）
///
/// 照樣稿①「CUBE 卡」：卡面色漸層（左上亮、右下深）＋左上一道光、右邊兩個淡圓；晶片（淡金、兩條線）旁邊是感應圖示
/// （wave.3.right 的樣子，手畫三道弧）；中下「•••• 5678」只有末四碼。左上小膠囊、左下手寫字是 MoneyPanel 疊的，這裡不畫，
/// 位置讓開它們（晶片 y ≥ 28、末四碼在手寫字上面）。停用：灰色卡面、透明 0.6 疊在灰底上（不透出後面的白卡）。
struct WealthCardFacePanel: View, Equatable {
    let face: WealthCardFace
    let dark: Bool
    /// 緊湊模式 46pt 小方塊
    var compact: Bool = false

    var body: some View {
        Canvas { ctx, size in
            Self.paint(&ctx, size: size, panel: self)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func paint(_ ctx: inout GraphicsContext, size: CGSize, panel p: WealthCardFacePanel) {
        guard size.width > 8, size.height > 8 else { return }
        guard p.face.disabled else {
            paintFace(&ctx, size: size, panel: p)
            return
        }
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(disabledBase(dark: p.dark)))
        ctx.drawLayer { layer in
            layer.opacity = 0.6
            Self.paintFace(&layer, size: size, panel: p)
        }
    }

    private static func paintFace(_ ctx: inout GraphicsContext, size: CGSize, panel p: WealthCardFacePanel) {
        let w = size.width
        let h = size.height
        let full = CGRect(origin: .zero, size: size)
        ctx.fill(Path(full), with: .linearGradient(Gradient(colors: faceColors(p)), startPoint: .zero,
                                                   endPoint: CGPoint(x: w, y: h)))
        paintSheen(&ctx, width: w, height: h, dark: p.dark)
        let ink = inkColor(p)
        if p.compact {
            let cw = Swift.max(8, (w * 0.26).rounded())
            let chip = CGRect(x: 6, y: 7, width: cw, height: (cw * 0.75).rounded())
            paintChip(&ctx, chip)
            paintNumber(&ctx, p.face.last4, at: CGPoint(x: 7, y: (h - 10).rounded()), maxWidth: w - 10,
                        sizes: [8, 7], color: ink)
            return
        }
        // 底部壓暗一點：左下的手寫字讀得到
        let shade = Gradient(stops: [.init(color: Color.black.opacity(0), location: 0.5),
                                     .init(color: Color.black.opacity(0.28), location: 1)])
        ctx.fill(Path(full), with: .linearGradient(shade, startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        let chipY = Swift.max(28, (h * 0.355).rounded())
        let chip = CGRect(x: 12, y: chipY, width: 16, height: 12)
        paintChip(&ctx, chip)
        paintContactless(&ctx, left: chip.maxX + 4, midY: chip.midY, color: ink.opacity(0.9))
        let numY = Swift.max(chip.maxY + 9, Swift.min((h * 0.58).rounded(), h - 46))
        paintNumber(&ctx, "•••• " + p.face.last4, at: CGPoint(x: 12, y: numY), maxWidth: w - 18,
                    sizes: [9.5, 8.5, 7.5], color: ink)
    }

    private static func faceColors(_ p: WealthCardFacePanel) -> [Color] {
        if p.face.disabled {
            return p.dark ? [Color(tb: 0x6B7386), Color(tb: 0x3F4656)] : [Color(tb: 0xC6CCD8), Color(tb: 0x8E97AA)]
        }
        return [WealthCardPalette.top(p.face.color, dark: p.dark), WealthCardPalette.bottom(p.face.color, dark: p.dark)]
    }

    /// 末四碼、感應圖示的顏色：黑金卡金字，其他白字；停用白字
    private static func inkColor(_ p: WealthCardFacePanel) -> Color {
        p.face.disabled ? Color.white : WealthCardPalette.ink(p.face.color)
    }

    private static func disabledBase(dark: Bool) -> Color {
        dark ? Color(tb: 0x2E3443) : Color(tb: 0x9AA2B2)
    }

    /// 左上一道光＋右邊兩個淡圓（卡片的光澤）
    private static func paintSheen(_ ctx: inout GraphicsContext, width w: CGFloat, height h: CGFloat, dark: Bool) {
        let glow = Gradient(colors: [Color.white.opacity(dark ? 0.2 : 0.34), Color.white.opacity(0)])
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: .radialGradient(glow, center: CGPoint(x: w * 0.18, y: h * 0.05), startRadius: 0,
                                       endRadius: Swift.max(w, h) * 0.9))
        let d1 = w * 0.95
        ctx.fill(Path(ellipseIn: CGRect(x: w * 0.48, y: -d1 * 0.42, width: d1, height: d1)),
                 with: .color(Color.white.opacity(dark ? 0.06 : 0.1)))
        let d2 = w * 1.2
        ctx.fill(Path(ellipseIn: CGRect(x: w * 0.3, y: h * 0.62, width: d2, height: d2)),
                 with: .color(Color.white.opacity(dark ? 0.04 : 0.07)))
    }

    /// 晶片：淡金漸層圓角矩形＋兩條線
    private static func paintChip(_ ctx: inout GraphicsContext, _ c: CGRect) {
        let shape = Path(roundedRect: c, cornerRadius: Swift.min(2.5, c.height * 0.22))
        let gold = Gradient(colors: [Color(tb: 0xF8E7A8), Color(tb: 0xD6B25C)])
        ctx.fill(shape, with: .linearGradient(gold, startPoint: CGPoint(x: c.minX, y: c.minY),
                                              endPoint: CGPoint(x: c.maxX, y: c.maxY)))
        var lines = Path()
        lines.move(to: CGPoint(x: c.minX + 1, y: c.midY))
        lines.addLine(to: CGPoint(x: c.maxX - 1, y: c.midY))
        lines.move(to: CGPoint(x: c.midX, y: c.minY + 1))
        lines.addLine(to: CGPoint(x: c.midX, y: c.maxY - 1))
        ctx.stroke(lines, with: .color(Color(tb: 0xA9853A, 0.65)), lineWidth: 0.6)
        ctx.stroke(shape, with: .color(Color(tb: 0xA9853A, 0.45)), lineWidth: 0.5)
    }

    /// 感應圖示（wave.3.right 的樣子）：三道往右鼓的弧
    private static func paintContactless(_ ctx: inout GraphicsContext, left x: CGFloat, midY y: CGFloat,
                                         color: Color) {
        var waves = Path()
        for k in 0..<3 {
            let dx = 1.6 + CGFloat(k) * 2.3
            let half = 1.6 + CGFloat(k) * 1.6
            waves.move(to: CGPoint(x: x + dx, y: y - half))
            waves.addQuadCurve(to: CGPoint(x: x + dx, y: y + half), control: CGPoint(x: x + dx + half * 0.9, y: y))
        }
        ctx.stroke(waves, with: .color(color), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
    }

    /// 末四碼（遮住時 face.last4 已經是「••••」）：一層淡影子讓淺色卡面上的白字讀得到；太寬就縮字
    private static func paintNumber(_ ctx: inout GraphicsContext, _ s: String, at p: CGPoint, maxWidth: CGFloat,
                                    sizes: [CGFloat], color: Color) {
        var resolved: GraphicsContext.ResolvedText? = nil
        for size in sizes {
            let font = Font.system(size: size, weight: .heavy, design: .rounded)
            let t = ctx.resolve(Text(s).font(font).monospacedDigit().tracking(size * 0.12).foregroundStyle(color))
            resolved = t
            if t.measure(in: CGSize(width: 400, height: 40)).width <= maxWidth { break }
        }
        guard let t = resolved else { return }
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: Color.black.opacity(0.35), radius: 1.2, x: 0, y: 0.6))
            layer.draw(t, at: p, anchor: .leading)
        }
    }
}
