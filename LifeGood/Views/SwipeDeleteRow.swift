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

struct SwipeDeleteRow<Content: View>: View {
    /// 刪除鈕寬度
    var deleteWidth: CGFloat = 72
    let onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offsetX: CGFloat = 0
    @State private var isOpen = false
    /// 這次拖曳的方向鎖：nil＝未判定、true＝水平（本列處理）、false＝垂直（整段交給捲動）。
    /// 在第一次 onChanged（約 18pt）就判定並鎖住，避免捲動中途軌跡偏水平時列跟著抖動。
    @State private var dragLockHorizontal: Bool?

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
                // simultaneousGesture 而非 .gesture：.gesture 會與外層 ScrollView 的捲動
                // 手勢「競爭」——快速垂直滑動落在列上時，列的 DragGesture 先搶到觸控、
                // onChanged 又因偏垂直而不處理，整個觸控被吃掉 → 頁面不捲動；
                // 慢慢拖曳則是 ScrollView 先贏所以一定會動（使用者回報的症狀）。
                // 改成 simultaneous 讓兩者同時辨識：垂直滑動由 ScrollView 捲動、
                // 列的手勢靠下方「明顯偏水平才處理」的守衛不動作；水平左滑則照常開刪除鈕。
                .simultaneousGesture(
                    DragGesture(minimumDistance: 18)
                        .onChanged { value in
                            // 只吃「明顯偏水平」的拖曳，垂直捲動交還給 ScrollView
                            if dragLockHorizontal == nil {
                                dragLockHorizontal =
                                    abs(value.translation.width) > abs(value.translation.height)
                            }
                            guard dragLockHorizontal == true else { return }
                            let base: CGFloat = isOpen ? -(deleteWidth + 8) : 0
                            let proposed = base + value.translation.width
                            // 左界：刪除鈕寬 + 一點橡皮筋；右界 0
                            offsetX = min(0, max(proposed, -(deleteWidth + 28)))
                        }
                        .onEnded { value in
                            let wasHorizontal = dragLockHorizontal == true
                            dragLockHorizontal = nil
                            guard wasHorizontal else { return }
                            let shouldOpen = offsetX < -(deleteWidth * 0.5)
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                offsetX = shouldOpen ? -(deleteWidth + 8) : 0
                                isOpen = shouldOpen
                            }
                        }
                )
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            offsetX = 0
            isOpen = false
        }
    }
}
