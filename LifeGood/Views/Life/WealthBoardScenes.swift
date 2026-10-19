import SwiftUI

// MARK: - 財富的三幅看板風景＋信用卡卡面（v25.564，財富 v3；wealth/judge.md §3.2、§4.1、§4.2、§3.7、§3.16）
//
// A.「頂樓水塔」.towers(WealthTowerScene)：財富頁看板（band 118）。台灣頂樓家家戶戶都有的不鏽鋼水塔（圓柱＋四隻腳）。
//    一個沒收起來的銀行帳戶一座塔，左到右照財富頁的順序；最多 5 座，第 6 個起資料端併成一座小塔（badge「＋3」）。
//    塔裡的水位＝level（資料端已經算好 √(存摺上÷最大那座)，0 空塔）；水面上那一截斜線＝hatch（還沒扣÷存摺上，
//    同資產小鎮「斜線＝還欠」finHatch，卡費橘）；hatch ≥ 1 或 warn：斜線畫到塔底、塔框 warn 色。
//    kind：.live 藍水、.foreign 青水＋塔身小旗（badge「US$」）、.deposit 金水＋塔身鎖頭＋小牌（badge「3/15」）、
//    .empty 灰色空塔（只有卡沒有銀行：「還沒選從哪扣」）。dashed：新手三座虛線空塔。
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

    private static func clamp(_ i: Int) -> Int { Swift.min(Swift.max(i, 0), 5) }

    /// 漸層左上
    static func top(_ i: Int, dark: Bool) -> Color { Color(tb: tops[clamp(i)]) }
    /// 漸層右下
    static func bottom(_ i: Int, dark: Bool) -> Color { Color(tb: bottoms[clamp(i)]) }
    /// 一個代表色（項目卡的色點、帳單週期的柱子、水塔下的小卡片）
    static func tint(_ i: Int) -> Color { Color(tb: bottoms[clamp(i)]) }
    /// 黑金卡的字是金色 D8B46A，其他白字
    static func ink(_ i: Int) -> Color { clamp(i) == 4 ? Color(tb: 0xD8B46A) : .white }
}

// MARK: - 畫法（G4 實作；主控先放能編譯的空殼）

extension MoneyBoardSky {
    static func paintTowers(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: WealthTowerScene,
                            dark: Bool, seed: Int) {
        guard r.width > 120, r.height > 60, !s.towers.isEmpty else { return }
        // G4：照檔頭 A 畫
    }

    static func paintTide(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: WealthTideScene,
                          dark: Bool, seed: Int) {
        guard r.width > 120, r.height > 60, s.days > 1 else { return }
        // G4：照檔頭 B 畫
    }

    static func paintCardCycle(_ ctx: inout GraphicsContext, rect r: CGRect, scene s: WealthCycleScene,
                               dark: Bool, seed: Int) {
        guard r.width > 120, r.height > 60, s.days > 1 else { return }
        // G4：照檔頭 C 畫
    }
}

/// 信用卡卡面（Equatable＋.equatable()：輸入一樣不重畫；MoneyPanel／MoneyThumb 已經接好）
struct WealthCardFacePanel: View, Equatable {
    let face: WealthCardFace
    let dark: Bool
    /// 緊湊模式 46pt 小方塊
    var compact: Bool = false

    var body: some View {
        // G4：照檔頭 D 畫（Canvas）；主控先放漸層
        LinearGradient(colors: [WealthCardPalette.top(face.color, dark: dark),
                                WealthCardPalette.bottom(face.color, dark: dark)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .accessibilityHidden(true)
    }
}
