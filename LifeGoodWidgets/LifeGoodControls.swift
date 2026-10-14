import SwiftUI
import WidgetKit
import AppIntents

// MARK: - 控制項：記一筆（ControlWidgetButton）、隱藏金額（ControlWidgetToggle）（小工具 v2）
//
// 只屬於「LifeGoodWidgets」target。規格見 scratchpad/widgets/v2/brief.md 的 G3-7；
// 樣稿 mock_spec control-add-expense、control-hide-amounts（J:302-319）。
// 可以放在控制中心、鎖定畫面左下右下、動作按鈕（iOS 18）。控制項由系統畫，我們只給圖示和字。
//
// • 記一筆：action 是共用檔的 LifeGoodOpenIntent（WidgetActions.swift，兩個 target 都有、openAppWhenRun）。
//   系統把 App 叫到前景、在 App 的行程裡跑 perform，把網址交給 App（WidgetOpenAppHandoff），
//   App 走跟 onOpenURL 同一個總入口：新增支出、數字鍵盤跳出、不播開場（快速通道）。
//   **不要在小工具這邊再寫一個打開 App 的 intent**（只在小工具 target 的 intent 不會開 App 的行程）。
//   主控定案 7：不顯示「今天 3 筆」小字（ControlWidgetButton 的副標寫法沒把握），只有圖示＋「記一筆」。
//   備案（實機若 App 開了卻沒跳到新增支出）：action 換成 iOS 18 的 OpenURLIntent(WidgetLink.addExpense())，
//   網址走 onOpenURL，App 那邊不用改（brief §3.6）。
// • 隱藏金額：值從 App Group 的 UserDefaults 讀（HideAmountsControlProvider），按了跑
//   SetHideAmountsIntent（WidgetIntents.swift，只在小工具）：寫開關、重畫全部小工具＋這個控制項。不開 App。
//   主控定案 6：不設驗證（authenticationPolicy 在控制項上的行為沒把握）。
//
// 型別：AddExpenseControl、HideAmountsControl、HideAmountsControlProvider

struct AddExpenseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKind.controlAddExpense) {
            ControlWidgetButton(action: LifeGoodOpenIntent(url: WidgetLink.addExpense())) {
                Label("記一筆", systemImage: "plus.circle.fill")
            }
        }
        .displayName("記一筆")
        .description("打開 LifeGood 記一筆支出，數字鍵盤直接跳出")
    }
}

struct HideAmountsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKind.controlHideAmounts,
                                   provider: HideAmountsControlProvider()) { isOn in
            ControlWidgetToggle("隱藏金額", isOn: isOn, action: SetHideAmountsIntent()) { on in
                Label(on ? "金額 隱藏中" : "金額 顯示中", systemImage: on ? "eye.slash" : "eye")
            }
        }
        .displayName("隱藏金額")
        .description("一按把所有 LifeGood 小工具的金額遮起來")
    }
}

/// 「隱藏金額」開關現在的值（App Group 的 UserDefaults；App 設定頁是同一個開關）
struct HideAmountsControlProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        WidgetHideAmounts.isOn
    }
}
