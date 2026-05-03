import SwiftUI

/// 馬卡龍色調的精簡日期選擇器：第一行 5 顆相對日期按鈕，第二行 compact DatePicker。
struct MacaronDatePicker: View {
    @Binding var selectedDate: Date
    /// 是否允許選未來日期（行事曆需要、部屬總覽也允許）
    var allowFuture: Bool = true

    private let calendar = Calendar.current

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
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(relativeDays, id: \.offset) { item in
                    pillButton(label: item.label, offset: item.offset, color: item.color)
                }
            }
            DatePicker("選擇日期", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    private func pillButton(label: String, offset: Int, color: Color) -> some View {
        let target = calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date())
        let isSelected = calendar.isDate(selectedDate, inSameDayAs: target)
        let dateLabel: String = {
            let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: target)
        }()
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedDate = target }
        } label: {
            VStack(spacing: 2) {
                Text(label).font(.caption.weight(.semibold))
                Text(dateLabel).font(.system(size: 10)).opacity(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(isSelected ? 0.9 : 0.28))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(isSelected ? 0 : 0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
