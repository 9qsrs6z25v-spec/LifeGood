import SwiftUI

// MARK: - 美化紀錄（MacaronDatePicker）
// [2026-06] 本次美化方向：
//   1. 容器卡片：補雙層陰影（主色 0.06 + 黑 0.03）+ 極細 overlay 邊框（separator 0.15），
//      對齊 OverviewView.todayCard / IncomeView.summaryHeader 卡片精緻感，深色模式相容
//   2. 快捷按鈕動畫：easeInOut(0.15) 升級為 .spring(response:0.30, dampingFraction:0.70)，
//      選中狀態加 scaleEffect(1.04)，對齊全 App 按鈕彈跳動畫規格
//   3. 選中快捷鍵：背景加對應色 0.22 光暈陰影（y:3），強化視覺回饋；
//      未選中狀態 opacity 從 0.28 → 0.22，讓選中對比更鮮明
//   4. 快捷鍵與 DatePicker 之間加入 0.5pt 分隔線（separator 0.20），提升視覺分層
//   5. DatePicker 左側加「自訂日期」小圖示 + 文字標籤（.caption2.foregroundStyle(.tertiary)），
//      引導使用者了解底部 compact picker 用途，對齊 IncomeView KPI 橫列輔助文字規格
//   6. 整體 padding 微調：pills 行垂直從 8 → 9，DatePicker 行垂直從 compact → 10，
//      呼吸感與其他表單卡片一致

/// 馬卡龍色調的精簡日期選擇器：第一行 5 顆相對日期按鈕，第二行 compact DatePicker。
struct MacaronDatePicker: View {
    @Binding var selectedDate: Date
    /// 是否允許選未來日期（行事曆需要、部屬總覽也允許）
    var allowFuture: Bool = true

    private let calendar = Calendar.current
    private static let mdFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()

    private var relativeDays: [(label: String, offset: Int, color: Color)] {
        [
            ("前天", -2, Color(red: 0.66, green: 0.86, blue: 0.74)),  // mint
            ("昨天", -1, Color(red: 0.78, green: 0.71, blue: 0.89)),  // lavender
            ("今天",  0, Color(red: 0.99, green: 0.80, blue: 0.65)),  // peach
            ("明天",  1, Color(red: 0.99, green: 0.92, blue: 0.65)),  // butter
            ("後天",  2, Color(red: 0.99, green: 0.74, blue: 0.80)),  // rose
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // 快捷日期膠囊列
            HStack(spacing: 6) {
                ForEach(relativeDays, id: \.offset) { item in
                    pillButton(label: item.label, offset: item.offset, color: item.color)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            // 分隔線：區分快捷按鈕與自訂日期選擇器
            Rectangle()
                .fill(Color(.separator).opacity(0.20))
                .frame(height: 0.5)

            // 自訂日期選擇器列
            HStack(spacing: 8) {
                // 引導標籤：讓使用者了解底部 picker 用途
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                    Text("自訂日期")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)

                Spacer()

                DatePicker("選擇日期", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator).opacity(0.15), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
        .padding(.horizontal)
    }

    private func pillButton(label: String, offset: Int, color: Color) -> some View {
        let target = calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date())
        let isSelected = calendar.isDate(selectedDate, inSameDayAs: target)
        let dateLabel = Self.mdFormatter.string(from: target)
        return Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.70)) {
                selectedDate = target
            }
        } label: {
            VStack(spacing: 2) {
                Text(label).font(.caption.weight(.semibold))
                Text(dateLabel).font(.system(size: 10)).opacity(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            // 選中時飽和度更高（0.90），未選中更淡（0.22），強化對比
            .background(color.opacity(isSelected ? 0.90 : 0.22))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(isSelected ? 0 : 0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            // 選中時輕微放大（對齊 MainTabView tabItemLabel scaleEffect 規格）
            .scaleEffect(isSelected ? 1.04 : 1.0)
            // 選中時加對應色光暈陰影，未選中時不影響佈局（無陰影）
            .shadow(
                color: isSelected ? color.opacity(0.30) : .clear,
                radius: 5, x: 0, y: 3
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.30, dampingFraction: 0.70), value: isSelected)
    }
}
