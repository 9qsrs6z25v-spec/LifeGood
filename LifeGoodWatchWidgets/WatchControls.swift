import SwiftUI
import WidgetKit
import AppIntents

// MARK: - 手錶的控制項（手錶 v7b，v25.584；watch/judge.md §3.4、§6.2-3、§6.3；watch/build/v7b/brief.md §1、§2）
//
// 只屬於 LifeGoodWatchWidgets（主控寫好，不准改）。watchOS 26 才有控制項（ControlWidget、StaticControlConfiguration、
// ControlWidgetButton、ControlWidgetToggle、ControlValueProvider、ControlCenter 都是 watchOS 26.0 起；build/v7b/doc/），
// 全部 @available(watchOS 26, *)，WidgetBundle 裡用 if #available 包（LifeGoodWatchWidgetsBundle.swift）；watchOS 11 的錶看不到、其他照常。
// 控制項跟小格一樣放在 widget extension（Apple〈Creating controls…〉：控制項由 widget extension 提供；手錶 App 不放）。
// iPhone 的「記一筆」「說一句」「記到…」「開始跑步」會把 iPhone App 叫到前景，**不會**出現在手錶（judge §3.4），所以手錶要自己的：
//   • ＋ 記一筆：WatchOpenIntent(lifegood://add/expense) → 手錶 App 記一筆第一步（記帳台）
//   • ▶ 開始跑步：WatchOpenIntent(lifegood://life/health/run) → ③ 跑步＋準備頁（**不自己倒數**；同 iPhone 控制項
//     LifeGoodControls.swift StartRunControl）。Ultra 動作按鈕照 v5 StartRunIntent 那條（一按就 3、2、1），這裡不動
//   • 遮住金額（手錶）：ControlWidgetToggle，值是手錶自己的 WatchHideAmounts（手錶 App Group）；按了跑 SetWatchHideAmountsIntent
//     （只在手錶小格、不開 App）：寫開關、錶面小格全部重畫。iPhone 的「隱藏金額」開著時照樣遮（任一邊開著就遮，judge §6.2-3）
// WatchOpenIntent 在共用檔 LifeGood/Shared/WatchOpenIntent.swift（手錶兩個 target 都有：要打開 App，intent 一定要兩邊都有）。
// 跟 iPhone 控制項一樣不設 tint、不加副標；控制項只畫圖示與字，沒有任何金額、行程、人名（鎖著也拉得下控制中心）。

@available(watchOS 26, *)
struct WatchAddRecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WatchWidgetKind.controlAdd) {
            ControlWidgetButton(action: WatchOpenIntent(url: WidgetLink.addExpense())) {
                Label("記一筆", systemImage: "plus.circle.fill")
            }
        }
        .displayName("記一筆")
        .description("打開手錶上的 LifeGood 記帳台，點一格就記好")
    }
}

@available(watchOS 26, *)
struct WatchStartRunControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WatchWidgetKind.controlRun) {
            ControlWidgetButton(action: WatchOpenIntent(url: WidgetLink.healthRun)) {
                Label("開始跑步", systemImage: "figure.run")
            }
        }
        .displayName("開始跑步")
        .description("打開手錶上的 LifeGood 跑步準備頁（不會自己開始倒數）")
    }
}

@available(watchOS 26, *)
struct WatchHideAmountsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WatchWidgetKind.controlHide,
                                   provider: WatchHideAmountsControlProvider()) { isOn in
            ControlWidgetToggle("遮住金額", isOn: isOn, action: SetWatchHideAmountsIntent()) { on in
                Label(on ? "金額 遮住中" : "金額 顯示中", systemImage: on ? "eye.slash" : "eye")
            }
        }
        .displayName("遮住金額（手錶）")
        .description("只遮這支手錶上 LifeGood 的金額；iPhone 的隱藏金額開著時照樣遮")
    }
}

/// 「遮住金額（手錶）」現在的值（手錶 App Group 的 UserDefaults；手錶設定頁是同一個開關）
@available(watchOS 26, *)
struct WatchHideAmountsControlProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        WatchHideAmounts.isOn
    }
}

/// 控制項按下去：系統把新的值放進 value（true＝遮起來）。只在手錶小格裡跑、不開 App（SetValueIntent 是 watchOS 11 起就有）
struct SetWatchHideAmountsIntent: SetValueIntent {
    static var title: LocalizedStringResource = "遮住金額（手錶）"
    static var description = IntentDescription("把這支手錶上 LifeGood 的金額遮起來或打開")

    @Parameter(title: "遮住金額")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        WatchHideAmounts.set(value)
        WatchControlRefresh.afterHideAmountsChanged()
        return .result()
    }
}
