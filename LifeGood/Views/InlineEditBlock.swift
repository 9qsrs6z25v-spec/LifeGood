import SwiftUI

// MARK: - 就地編輯文字區塊標準模板
//
// 檢視卡片（任務／會議／報告／紀錄詳情、機台詳情等）裡的多行文字欄位——
// 備註、內容、處理措施、回復結果——常常只想改一小段字，卻得進完整編輯頁。
// 此模板在顯示區塊右上放一顆鉛筆鈕：點下去原地變成多行輸入框＋儲存/取消，
// 儲存呼叫 onSave 交回新字串，由呼叫端寫回 store；取消原樣退回，都不離開卡片。
//
// 用法：
//   InlineEditBlock(title: "備註", text: item.note) { new in
//       lifeStore.mutate...(...) { $0.note = new }
//   }
// 顯示樣式對齊 SubordinateItemCard.richBlock（padding + secondarySystemGroupedBackground
// + 圓角 12 + 細邊框）；內容為空時顯示淡色佔位提示，一樣可以點鉛筆直接補。
// 需要 @ 標註連結顯示時，用 displayText 參數帶自訂渲染（見 SubordinateItemCard 用法）。

struct InlineEditBlock: View {
    let title: String
    let text: String
    /// 空內容時的佔位提示（顯示模式）；編輯模式亦作為輸入框 placeholder
    var emptyHint: String = "（未填，點筆直接補）"
    /// 鉛筆與儲存鈕的主色
    var accent: Color = .blue
    /// 顯示模式的文字渲染（預設純文字；可帶 MentionText.attributed 之類的自訂渲染）
    var displayText: (String) -> Text = { Text($0) }
    let onSave: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !isEditing {
                    Button {
                        draft = text
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            isEditing = true
                        }
                        focused = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 19))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            if isEditing {
                TextField(emptyHint, text: $draft, axis: .vertical)
                    .lineLimit(2...10)
                    .font(.subheadline)
                    .focused($focused)
                    .padding(8)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 12) {
                    Spacer()
                    Button("取消") {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            isEditing = false
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.borderless)
                    Button {
                        onSave(draft.trimmingCharacters(in: .whitespacesAndNewlines))
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            isEditing = false
                        }
                    } label: {
                        Text("儲存")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16).padding(.vertical, 5)
                            .background(accent, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderless)
                }
            } else if text.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(emptyHint)
                    .font(.subheadline).italic()
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                displayText(text)
                    .font(.subheadline).foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tint(.blue)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
    }
}
