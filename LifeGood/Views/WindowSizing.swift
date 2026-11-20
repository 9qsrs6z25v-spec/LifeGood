import SwiftUI
import UIKit

// MARK: - 視窗大小（v25.521）
//
// 使用者：「電腦板打開的話那個介面有點小，幫我改善這個問題，有機會做接近滿版畫面的嗎？
// 我不想全畫面，但是至少要能橫向拉伸」。
//
// 電腦版是 Mac 上跑的 iPad 版。原本專案設了「需要全螢幕」、iPad 只准直向，
// 這兩個設定讓 Mac 只能給一個固定大小的視窗——拉不寬。v25.521 把兩個都打開
// （見 project.pbxproj 的 INFOPLIST_KEY_UIRequiresFullScreen 與
// INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad），視窗就可以自由拉伸。
//
// 視窗變大之後，iPad／Mac 上的 sheet 照系統預設還是一張約 540×620 的小卡
// 浮在中間——行程頁就是在那張小卡裡（使用者截圖）。所以「一整頁」的 sheet
// （行程、景點卡、相本…）另外撐到接近視窗大小，四周留一點邊，看得出它是
// 疊在主畫面上的一層，不是全螢幕。小的 sheet（選日期、選一個項目）照舊。

private struct AppWindowSizeKey: EnvironmentKey {
    static let defaultValue: CGSize = .zero
}

extension EnvironmentValues {
    /// 整個 App 主畫面的大小（iPad／Mac 上就是視窗大小，會跟著拉伸變）。
    /// 還沒量到之前是 .zero。
    var appWindowSize: CGSize {
        get { self[AppWindowSizeKey.self] }
        set { self[AppWindowSizeKey.self] = newValue }
    }
}

enum AppDevice {
    /// iPad，或 Mac 上跑的 iPad 版。App 執行期間不會變，所以拿它分支不會讓畫面重建。
    static let isPadLike: Bool = UIDevice.current.userInterfaceIdiom == .pad
}

extension View {
    /// 掛在 App 最外層（LifeGoodApp）：量主畫面大小、放進環境。
    func measuresAppWindow() -> some View {
        modifier(AppWindowMeasurer())
    }

    /// 掛在「一整頁」sheet 的 body 最後面：iPad／Mac 上把這張 sheet 撐到接近視窗大小；
    /// iPhone 上什麼都不做（iPhone 的 sheet 本來就是整個寬）。
    ///
    /// ⚠️ 只掛在「一整頁」的 sheet。選日期、選一個項目那種小 sheet 不要掛——
    ///    在 Mac 的大視窗裡撐成一整面只會更難用。
    func windowSizedPage() -> some View {
        modifier(WindowSizedPage())
    }
}

private struct AppWindowMeasurer: ViewModifier {
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                size = newSize
            }
            .environment(\.appWindowSize, size)
    }
}

private struct WindowSizedPage: ViewModifier {
    @Environment(\.appWindowSize) private var window

    /// 視窗四周各留這麼多（使用者：「我不想全畫面」——看得出底下還有主畫面）
    private static let margin: CGFloat = 40

    func body(content: Content) -> some View {
        // isPadLike 是常數：分支永遠走同一邊，不會因為視窗拉伸讓 sheet 裡的狀態重來
        if AppDevice.isPadLike {
            content
                // .fitted＝照內容的「理想大小」開 sheet；理想大小就是視窗扣掉四周的邊。
                // 系統會再夾在可用範圍內，所以給大了也不會超出視窗。
                .frame(idealWidth: Self.side(window.width, minimum: 540, fallback: 900),
                       idealHeight: Self.side(window.height, minimum: 620, fallback: 1000))
                .presentationSizing(.fitted)
        } else {
            content
        }
    }

    /// 還沒量到視窗大小（0）時給一個寬鬆的預設值；量到之後扣掉四周的邊，但不小於系統原本的 sheet。
    private static func side(_ v: CGFloat, minimum: CGFloat, fallback: CGFloat) -> CGFloat {
        guard v > 0 else { return fallback }
        return max(minimum, v - margin * 2)
    }
}
