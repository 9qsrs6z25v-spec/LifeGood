import SwiftUI

// MARK: - 快速選取膠囊列（標準模板）
//
// 「你記過的資料就是最好的選項」：把歷史輸入彙整成可點選的膠囊列——
// 點一下帶入欄位、再點同一顆取消；橫向捲動、最近使用優先、去重、上限 8 個。
// 起源於喝奶記錄的奶粉品牌快速選取（v25.171），抽成模板後供全 App 使用：
//   • 兒女喝奶品牌／食物名稱（ChildDetailView.DailyRecordEditorSheet）
//   • 兒女就醫/疫苗院所（ChildRecordEditorSheet）
//   • 變動支出同分類品名（AddExpenseView，用餐/醫療/娛樂等全分類）
// 呼叫端以 QuickPickOptions.recent(...) 從歷史紀錄組出選項；選項為空時整列不佔位。

struct QuickPickCapsuleRow: View {
    let options: [String]
    @Binding var selection: String
    var accent: Color = .blue

    var body: some View {
        if !options.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            // 再點同一顆取消帶入，回到手動輸入
                            selection = (selection == option) ? "" : option
                        } label: {
                            Text(option)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(selection == option ? .white : accent)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(selection == option ? accent : accent.opacity(0.10))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

enum QuickPickOptions {
    /// 從（值, 日期）歷史序列組出快速選項：去空白、去重、最近使用優先、上限 limit。
    static func recent(_ history: [(value: String?, date: Date)], limit: Int = 8) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in history.sorted(by: { $0.date > $1.date }) {
            guard let v = item.value?.trimmingCharacters(in: .whitespaces),
                  !v.isEmpty, !seen.contains(v) else { continue }
            seen.insert(v)
            out.append(v)
            if out.count >= limit { break }
        }
        return out
    }
}
