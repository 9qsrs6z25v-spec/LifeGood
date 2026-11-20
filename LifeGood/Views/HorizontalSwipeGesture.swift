import SwiftUI
import UIKit

// MARK: - 左滑刪除的手勢（v25.613）
//
// 使用者回報（25.612 之後）：「上下滑太快反而不會動，緩緩地反而能上下滑」——股票清單。
//
// 以前 SwipeDeleteRow 在每一列掛 SwiftUI 的 DragGesture（.simultaneousGesture，minimumDistance 18）。
// iOS 18 起 SwiftUI 的手勢底下也是 UIKit 的手勢辨識器，捲動視圖裡只要列上有 DragGesture，
// 快速一甩（手指在螢幕上很短的時間就離開）常常是列的手勢先接住、捲動的 pan 沒起來 → 頁面不動；
// 慢慢拖的時候捲動先贏，所以一定會動。以前改成 simultaneous 減輕過一次，但沒有根治。
//
// 這一版改成 UIKit 的 UIPanGestureRecognizer（iOS 18 的 UIGestureRecognizerRepresentable 包起來），
// 在 gestureRecognizerShouldBegin「要不要開始」那一刻就決定：
//   - 偏垂直的拖曳 → 這一列根本不開始，整段交給捲動（捲動的 pan 照常起、照常有慣性）；
//   - 明顯偏水平 → 這一列接手（左滑露出刪除鈕），捲動那一下不動。
// 判斷規則全部在 SwipeDeleteRule（純函式；scratchpad 的 sim_scroll.py 一個函式一個函式對照）。

/// 左滑刪除的判斷與位移規則（SwipeDeleteRow 用）。數字跟 25.612 的 SwipeDeleteRow 一樣。
enum SwipeDeleteRule {
    /// 甩得多快才算「快」（pt／秒）：快的時候速度方向也要偏水平才接
    static let fastSpeed: CGFloat = 120
    /// 水平要大於垂直幾倍才算水平（2 倍＝偏離垂直約 63° 以上；25.612 起的規則）
    static let horizontalRatio: CGFloat = 2

    /// 開著的時候內容停在哪（刪除鈕寬＋8 的間隔）
    static func openOffset(deleteWidth: CGFloat) -> CGFloat {
        -(deleteWidth + 8)
    }

    /// 最多拉到哪（刪除鈕寬＋28 的橡皮筋）
    static func minOffset(deleteWidth: CGFloat) -> CGFloat {
        -(deleteWidth + 28)
    }

    /// 這一下拖曳要不要由這一列接手。UIKit 判定「開始拖曳」的那一刻問一次，之後不改判。
    /// - dx, dy：從手指按下到現在的位移（pt；往左、往上是負的）
    /// - vx, vy：現在的速度（pt／秒）
    /// - isOpen：這一列現在開著嗎
    ///
    /// 1. 方向用位移判斷（位移幾乎是 0 的時候改用速度）：水平要大於垂直的 2 倍。
    /// 2. 甩得快（速度 > fastSpeed）時速度也要偏水平 2 倍：快速往上甩，頭幾點可能歪一邊，看速度才準。
    /// 3. 收著的時候只接往左（往右滑本來就不會動，讓給別的手勢）；開著的時候左右都接。
    static func shouldBegin(dx: CGFloat, dy: CGFloat, vx: CGFloat, vy: CGFloat, isOpen: Bool) -> Bool {
        let useTranslation = abs(dx) + abs(dy) >= 1
        let hx = useTranslation ? dx : vx
        let hy = useTranslation ? dy : vy
        guard abs(hx) > abs(hy) * horizontalRatio else { return false }
        let speedSquared = vx * vx + vy * vy
        if speedSquared > fastSpeed * fastSpeed, !(abs(vx) > abs(vy) * horizontalRatio) {
            return false
        }
        if !isOpen && hx >= 0 { return false }
        return true
    }

    /// 拖曳中內容的 x 位移：開著的從開的位置算起；右界 0、左界 minOffset
    static func dragOffset(translation dx: CGFloat, isOpen: Bool, deleteWidth: CGFloat) -> CGFloat {
        let base: CGFloat = isOpen ? openOffset(deleteWidth: deleteWidth) : 0
        return min(0, max(base + dx, minOffset(deleteWidth: deleteWidth)))
    }

    /// 放開時要吸到開還是關：拉過刪除鈕的一半就開
    static func shouldOpen(offset: CGFloat, deleteWidth: CGFloat) -> Bool {
        offset < -(deleteWidth * 0.5)
    }
}

/// 只接「明顯偏水平」拖曳的 pan 手勢。偏垂直的在開始之前就放掉，交給外面的捲動。
///
/// 用法（SwipeDeleteRow 裡）：
///
///     content
///         .gesture(HorizontalSwipePan(isOpen: isOpen,
///                                     onChanged: { dx in … },
///                                     onEnded: { dx in … }))
struct HorizontalSwipePan: UIGestureRecognizerRepresentable {
    /// 這一列現在開著嗎（收著只接往左）
    var isOpen: Bool
    /// 拖曳中：從按下到現在的 x 位移（pt，往左是負的）
    var onChanged: (CGFloat) -> Void
    /// 放開、或被系統打斷：最後的 x 位移
    var onEnded: (CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        context.coordinator.isOpen = isOpen
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.isOpen = isOpen
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let dx = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            onChanged(dx)
        case .ended, .cancelled, .failed:
            onEnded(dx)
        default:
            break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// 由 updateUIGestureRecognizer 帶進來（開著的列左右都接）
        var isOpen = false

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let t = pan.translation(in: pan.view)
            let v = pan.velocity(in: pan.view)
            return SwipeDeleteRule.shouldBegin(dx: t.x, dy: t.y, vx: v.x, vy: v.y, isOpen: isOpen)
        }

        /// 不跟別的手勢同時辨識：水平那一下捲動不跟著動；垂直的這裡根本沒開始，捲動不受影響
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
    }
}
