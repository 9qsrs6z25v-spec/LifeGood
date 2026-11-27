// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.646 mac6 G3c] 固定支出時間軸的站牌與色（judge_mac.md §T5-2）：紫色站牌、淡紫軌道、今天一台小電車。
//
// • 只畫、不收滑鼠：格子裡不准 Button、onTapGesture、onHover、動畫；不用 Canvas。
// • MacRailTint 主控已填最終值（照抄出處，組員不改值）；3 個 Stop 是 §T5-2 的樣子（G3c）。
// • 站牌由 MacFixedPage 的 MacFixedRailDot 挑一種、往上 9pt 放（圓心在軌上方 9pt）；這檔只管一顆站牌長什麼樣。
// • 參考答案：build/mac6/sim6_rail.py（sim_mac6 的 rail6）。

import SwiftUI

/// 時間軸的色（MacFixedRail 用 @Environment(\.colorScheme) 算一次往下傳）
/// sim6: rail6#1 四個色、深淺兩套（值照抄 MoneyBoardScenes；電車＝固定支出頁的深藍）
struct MacRailTint {
    /// 軌道：照抄 MoneyBoardScenes.swift:528（258fea0）rail
    let track: Color
    /// 站牌：照抄 MoneyBoardScenes.swift:509-511（258fea0）purple
    let station: Color
    /// 站牌外框：淺白／深 0x121B38（MacPalette.boardTop 深色那一格）
    let ring: Color
    /// 今天那台電車
    let train: Color

    init(_ scheme: ColorScheme) {
        let dark = scheme == .dark
        track = dark ? MacTheme.hex(0x5A6FA8) : MacTheme.hex(0x9DB4D3)
        station = dark ? MacTheme.hex(0xA98BFF) : MacTheme.hex(0x8B5CF6)
        ring = dark ? MacTheme.hex(0x121B38) : Color.white
        train = MacPageTheme.blue.bottom
    }
}

/// 下一站（G3c：12pt 實心 station＋1.5pt ring 框）
/// sim6: rail6#2 下一站：12pt 實心站牌紫、框 1.5pt（淺色白、深色＝看板深底色），比其他站大一號
struct MacRailStopNext: View {
    let tint: MacRailTint

    var body: some View {
        Circle()
            .fill(tint.station)
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(tint.ring, lineWidth: 1.5))
    }
}

/// 扣過的站（G3c：9pt station@0.4＋白勾 checkmark 5pt heavy）
/// sim6: rail6#3 扣過的：9pt 淡紫（站牌紫 40%）＋白色小勾（checkmark 5pt heavy）
struct MacRailStopPast: View {
    let tint: MacRailTint

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.station.opacity(0.4))
            Image(systemName: "checkmark")
                .font(.system(size: 5, weight: .heavy))
                .foregroundStyle(Color.white)
        }
        .frame(width: 9, height: 9)
    }
}

/// 之後的站（G3c：9pt 實心＋ring 框）
/// sim6: rail6#4 之後的：9pt 實心站牌紫＋ring 框（跟下一站同一種框，只是小一號）
struct MacRailStopLater: View {
    let tint: MacRailTint

    var body: some View {
        Circle()
            .fill(tint.station)
            .frame(width: 9, height: 9)
            .overlay(Circle().strokeBorder(tint.ring, lineWidth: 1.5))
    }
}
