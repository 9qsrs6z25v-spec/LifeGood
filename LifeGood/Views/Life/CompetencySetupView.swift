import SwiftUI

// MARK: - [v25.599 職能雷達 v1a-1] 設定「職能項目」（G4 負責；radar/judge.md §4.4、§3.3、§3.4、§3.5、§6、§13；radar/build/v1a-1/brief.md §4 G4）
//
// • 人格特質（範圍、項目新增／改名／排序／停用／恢復）、本職學能（範圍）、共用學習項目（新增／改名／停用）、系統（新增／改名／排序／停用）。
// • 範圍 0…100、low < high 由畫面擋；改範圍先跳說明框（CompetencyMath.rangeChangeText）。§13：每一分不預設名字（名字頁在 v1a-2）。
// • 打開看不擋；〔用範例開始〕、新增、改、停用要訂閱。寫入只走 LifeStore 的職能那幾支（每支一個 batched）。
// 骨架（主控）：型別名與 init 參數是跨組契約，不准改；body 由 G4 換成真的。

struct CompetencySetupView: View {
    /// 從〔職能〕分頁用 sheet 打開時右上多一顆〔完成〕（從設定頁推進來時不用）
    var showsDoneButton: Bool = false

    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Text("人格特質、系統與學習項目、分數範圍")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("職能項目")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}
