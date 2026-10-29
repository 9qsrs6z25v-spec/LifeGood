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
            HStack(spacing: 8) {
                // [v25.433] 數量擺在最左邊、**不跟著捲**：
                // 一列膠囊看得到的永遠只有前三四顆，右邊還有多少要捲了才知道。
                // 先給一個數字，使用者才決定要不要捲。
                Text("\(options.count)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(accent)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(accent.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                    .fixedSize()

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
                // 兩側淡出，跟 App 其他橫捲的地方同一套（ItemChipBar、照片列、日期圖例）
                .scrollEdgeFade(width: 12)
            }
        }
    }
}

enum QuickPickOptions {
    /// 預設顯示幾顆。
    ///
    /// [v25.433] 原本寫死 8 顆。8 顆對「喝哪個牌子的奶粉」剛好，但對
    /// 「這個月去過哪些餐廳」太少了——常去的店根本排不進前 8 名。
    /// 改成使用者可調（設定 › 進階設定 › 快速選取膠囊），預設 20。
    static let defaultLimit = 20
    /// 上限 200：再多就不是「快速選取」而是一份清單了，捲到手痠還不如直接打字。
    static let maxLimit = 200
    static let storageKey = "quickpick_capsule_limit"

    /// 目前設定的上限。讀 UserDefaults 而不是 @AppStorage：
    /// 這是個純函式的工具型別，不是 View，沒有屬性包裝器可以用。
    static var limit: Int {
        let stored = UserDefaults.standard.integer(forKey: storageKey)
        // integer(forKey:) 對沒設過的鍵回 0，那就是「還沒調過」＝用預設值
        guard stored > 0 else { return defaultLimit }
        return min(maxLimit, stored)
    }

    /// 從（值, 日期）歷史序列組出快速選項：去空白、去重、最近使用優先、上限 limit。
    /// 不傳 limit 就用使用者在進階設定裡調的那個值。
    static func recent(_ history: [(value: String?, date: Date)],
                       limit: Int? = nil) -> [String] {
        let cap = limit ?? Self.limit
        var seen = Set<String>()
        var out: [String] = []
        for item in history.sorted(by: { $0.date > $1.date }) {
            guard let v = item.value?.trimmingCharacters(in: .whitespaces),
                  !v.isEmpty, !seen.contains(v) else { continue }
            seen.insert(v)
            out.append(v)
            if out.count >= cap { break }
        }
        return out
    }
}
