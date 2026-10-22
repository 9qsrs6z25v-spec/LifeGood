import SwiftUI
import WatchKit

// MARK: - 手錶 App 的樣子（手錶 v1，v25.574；watch/judge.md §2.0 字與底色、U4 §4.3 色碼）
//
// 只屬於 LifeGoodWatch（手錶小格有自己的一份，不能編這個檔）。色碼數字在 WatchPalette（Shared/WatchText.swift）。
// 看板頁（① 今天、② 錢）：.containerBackground(WatchStyle.sky, for: .tabView)；
// 推進去的清單、細節：.containerBackground(Color.black, for: .navigation)。手腕放下全部純黑（View 自己判斷 dimmed）。

extension Color {
    /// 0xRRGGBB
    init(watchHex hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

enum WatchStyle {
    /// 41／42／44mm 以下（寬 < 190 點）：大字 34、錢頁第二行不寫「・還有 N 天」、卡費日期不寫星期（judge §2.18）
    @MainActor
    static var isCompact: Bool {
        WKInterfaceDevice.current().screenBounds.width < 190
    }

    /// 夜空：121B38（頂）→ 0E1428（45%）→ 黑（底）
    static var sky: LinearGradient {
        LinearGradient(stops: [
            Gradient.Stop(color: Color(watchHex: WatchPalette.skyTop), location: 0),
            Gradient.Stop(color: Color(watchHex: WatchPalette.skyMid), location: 0.45),
            Gradient.Stop(color: Color.black, location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    static let dateText = Color(watchHex: WatchPalette.dateText)
    static let small = Color(watchHex: WatchPalette.small)
    static let primary = Color(watchHex: WatchPalette.primary)
    static let countdown = Color(watchHex: WatchPalette.countdown)
    static let amber = Color(watchHex: WatchPalette.amber)
    static let red = Color(watchHex: WatchPalette.red)
    static let fixedBar = Color(watchHex: WatchPalette.fixedBar)
    static let variableBar = Color(watchHex: WatchPalette.variableBar)
    static let green = Color(watchHex: WatchPalette.green)

    static func kindColor(_ kind: TimelineStopKind) -> Color {
        Color(watchHex: WatchPalette.kind(kind))
    }

    /// 大字（錢頁 hero）：46mm 38、41mm 34，heavy rounded（數字等寬另外 .monospacedDigit()）
    static func heroFont(compact: Bool) -> Font {
        .system(size: compact ? 34 : 38, weight: .heavy, design: .rounded)
    }
}
