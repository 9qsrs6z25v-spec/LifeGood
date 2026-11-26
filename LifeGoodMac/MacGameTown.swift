// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.648 mac7 G3] 記帳小鎮第三批：小鎮畫面（judge_mac.md §U5-1、§U5-2）。只畫、不算新規則、不存任何東西。
//
// • MacGameTownPlan.make 是純函式（level＝snapshot.level、lights＝snapshot.lights）；sim 編號 game#50～#54。
// • 全 LifeGoodMac 第三個 Canvas：只 fill／stroke 形狀；不准 ctx.resolve(、ctx.draw(（不畫字）、TimelineView、動畫。
// • 沒有金額、名字；沒有紅、粉；外層 .accessibilityElement(children: .ignore)、.allowsHitTesting(false)。
// • 主控骨架（C0）：型別與簽名定案（§U7-6）；make 回空 pieces、畫面 Color.clear、兩個放置處 EmptyView()。G3 換內容。

import SwiftUI

/// 小鎮的一塊（座標、大小都是 0…1 的比例）
struct MacGameTownPiece: Equatable {
    let kind: MacGameTownKind
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    let lit: Bool
}

enum MacGameTownKind: Equatable {
    case lot, sapling, house, garden, tree, shop, alley, stall, hall, river, boat, tower, sparkle, window
}

/// 照等級蓋的小鎮（只升不降；這週的燈 → 亮窗、樹）
struct MacGameTownPlan: Equatable {
    let level: Int
    let pieces: [MacGameTownPiece]
    /// 本週 .lamp＋.checked 的數量（≤ 7）
    let lamps: Int
    /// 本週 .leaf＋.checked 的數量（≤ 7）
    let trees: Int

    // sim7: game#50～#54（G3 換內容）
    static func make(level: Int, lights: [MacGameLight]) -> MacGameTownPlan {
        MacGameTownPlan(level: level, pieces: [], lamps: 0, trees: 0)
    }
}

/// 小鎮圖（View＋Equatable：plan 一樣不重畫）
struct MacGameTownView: View, Equatable {
    let plan: MacGameTownPlan
    let dark: Bool

    var body: some View {
        Color.clear
    }
}

enum MacGameTownArt {
    /// 只 fill／stroke 形狀，不畫字
    static func paint(_ ctx: inout GraphicsContext, rect: CGRect, plan: MacGameTownPlan, dark: Bool) {
    }
}

/// 徽章 popover 最上面那張（高 120）
struct MacGameTownBanner: View {
    let snap: MacGameSnapshot

    var body: some View {
        EmptyView()
    }
}

/// 遊戲列第一行那張小的（理想寬 150、高 32；窄視窗自己縮）
struct MacGameTownStrip: View {
    let snap: MacGameSnapshot

    var body: some View {
        EmptyView()
    }
}
