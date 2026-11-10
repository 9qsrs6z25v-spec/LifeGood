import SwiftUI

// MARK: - 左滑刪除標準模板
// List 的列用系統 .swipeActions（allowsFullSwipe: false，全 App 既定規格）；
// 但 ScrollView / LazyVStack 裡的卡片列（股票卡等）沒有系統左滑可用，
// 此模板補上同等體驗：左滑露出紅色刪除鈕、放開自動吸附開/關、
// 開啟狀態下點內容自動收合；不支援全滑直接刪（比照使用者要求移除
// List 全滑刪除的既定決策，避免誤刪）。
//
// 用法：
//   SwipeDeleteRow(onDelete: { delete(item) }) { cardView(item) }
// 注意 onTapGesture / contextMenu 掛在內容上（模板內部），開啟狀態的
// 點擊會被攔下來收合、不會誤觸開卡片。
//
// [v25.613] 左滑改用 UIKit 的 pan（HorizontalSwipeGesture.swift 的 HorizontalSwipePan）：
// 以前的 SwiftUI DragGesture（就算是 simultaneous）在 iOS 18 會跟捲動搶，快速上下甩常常整頁不動
//（使用者：「上下滑太快反而不會動，緩緩地反而能上下滑」）。現在偏垂直的拖曳這一列根本不開始，
// 整段交給捲動；明顯偏水平才由這一列接手。判斷與位移規則在 SwipeDeleteRule，數字跟以前一樣。

struct SwipeDeleteRow<Content: View>: View {
    /// 刪除鈕寬度
    var deleteWidth: CGFloat = 72
    let onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offsetX: CGFloat = 0
    @State private var isOpen = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // 底層：紅色刪除鈕（收合時隱藏，避免圓角卡片縫隙透色）
            if offsetX < -1 {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        offsetX = 0
                        isOpen = false
                    }
                    onDelete()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("刪除")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: deleteWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            content()
                .offset(x: offsetX)
                // 開啟狀態：點內容先收合（不觸發內容自身的 onTapGesture 開卡）
                .overlay {
                    if isOpen {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                    }
                }
                // [v25.613] UIKit 的 pan：偏垂直的不開始（交給捲動），明顯偏水平才接（規則見 SwipeDeleteRule）
                .gesture(swipePan)
        }
    }

    /// 這一列的左滑手勢。isOpen 每次重畫都帶進去（開著的列左右都接，收著只接往左）
    private var swipePan: HorizontalSwipePan {
        HorizontalSwipePan(
            isOpen: isOpen,
            onChanged: { dx in
                offsetX = SwipeDeleteRule.dragOffset(translation: dx, isOpen: isOpen, deleteWidth: deleteWidth)
            },
            onEnded: { _ in settle() }
        )
    }

    /// 放開（或被系統打斷）：拉過刪除鈕一半就吸到開，不然收回
    private func settle() {
        let shouldOpen = SwipeDeleteRule.shouldOpen(offset: offsetX, deleteWidth: deleteWidth)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            offsetX = shouldOpen ? SwipeDeleteRule.openOffset(deleteWidth: deleteWidth) : 0
            isOpen = shouldOpen
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            offsetX = 0
            isOpen = false
        }
    }
}
