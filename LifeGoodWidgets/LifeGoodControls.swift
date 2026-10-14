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
// [v3] 規格見 scratchpad/widgets/v3/brief.md 的 G3-1；樣稿 mock_spec control-voice、control-record-taycan（J:310-311）。
// • 說一句：ControlWidgetButton → LifeGoodOpenIntent(WidgetLink.voiceRecord)
//   （lifegood://add/expense?voice=1&src=widget）。App 不切頁、不關設定頁或 sheet，直接開始聽，
//   講完自動停、AI 解析存檔、跳「已記一筆：午餐」（App 端 AIQuickVoiceSession）。
// • 記到…：長按控制項選「記到哪裡」（RecordToControlConfigIntent 的 target，選單是共用檔的
//   WidgetRecordTargetEntity：money 快照的 14 個變動分類＋每台車的車子分類，小工具這邊沒有任何分類、車名的字面字串）。
//   顯示的字、圖示、網址按的當下用 id 回 money 快照查（WidgetMoneySnapshot.recordTarget(id:)）：車改名跟著變；
//   App 寫完 money 會 reloadControls(WidgetKind.moneyControlKinds)。查不到（車賣掉、刪掉）退回選的時候的字、開空白新增支出；
//   沒選（或 EntityQuery 查不到、參數變 nil）是「記到…」＋鉛筆，按了開空白新增支出。
//   主控定案 6：不用 .promptsForUserConfiguration()（沒把握）；跟 v2 一樣不設 tint、不加副標。
//
// 型別：AddExpenseControl、HideAmountsControl、HideAmountsControlProvider；
//      [v3] VoiceRecordControl、RecordToControl、RecordToControlConfigIntent、RecordToControlValue、RecordToControlProvider

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

// MARK: - [v3] 說一句

struct VoiceRecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKind.controlVoice) {
            ControlWidgetButton(action: LifeGoodOpenIntent(url: WidgetLink.voiceRecord)) {
                Label("說一句記帳", systemImage: "mic.fill")
            }
        }
        .displayName("說一句")
        .description("打開 LifeGood 直接開始聽，講完自動記一筆")
    }
}

// MARK: - [v3] 記到…

struct RecordToControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: WidgetKind.controlRecordTo,
                                      provider: RecordToControlProvider()) { value in
            ControlWidgetButton(action: LifeGoodOpenIntent(url: value.url)) {
                Label(value.title, systemImage: value.icon)
            }
        }
        .displayName("記到…")
        .description("選一個分類或一台車，按了直接開新增支出、分類帶好")
    }
}

/// 長按控制項的設定：記到哪裡（只在小工具 target；不寫 perform，照 Xcode 控制項範本）
struct RecordToControlConfigIntent: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "記到…"
    static var description = IntentDescription("選一個分類，或一台車的電費、停車…")

    /// 選單從 money 快照讀（WidgetRecordTargetQuery）；沒選、車賣掉查不到是 nil
    @Parameter(title: "記到")
    var target: WidgetRecordTargetEntity?

    init() {}
}

/// 控制項要畫的字、圖示，與按了要開的網址
struct RecordToControlValue: Sendable {
    /// 「Taycan 電費」「飲食」「記到…」
    var title: String
    /// SF Symbol（「bolt.fill」「parkingsign.circle」「fork.knife」；沒選「square.and.pencil」）
    var icon: String
    /// lifegood://add/expense?…&src=widget
    var url: URL

    /// 沒選：「記到…」＋鉛筆、空白新增支出
    static let unset = RecordToControlValue(title: "記到…", icon: "square.and.pencil", url: WidgetLink.addExpense())

    /// entity nil → unset；快照查得到那個 id → 快照的字、圖示、網址（車改名跟著變）；
    /// 查不到（車賣掉、刪掉、還沒快照）→ 選的時候的字與圖示、開空白新增支出
    static func make(entity: WidgetRecordTargetEntity?, snapshot: WidgetMoneySnapshot?) -> RecordToControlValue {
        guard let entity else { return unset }
        if let snap = snapshot, let target = snap.recordTarget(id: entity.id) {
            return RecordToControlValue(title: target.title, icon: target.icon, url: target.url)
        }
        return RecordToControlValue(title: entity.name, icon: entity.icon, url: WidgetLink.addExpense())
    }
}

struct RecordToControlProvider: AppIntentControlValueProvider {
    /// 控制項庫、加入時的預覽：不讀檔（選了就寫選的字，沒選寫「記到…」）
    func previewValue(configuration: RecordToControlConfigIntent) -> RecordToControlValue {
        RecordToControlValue.make(entity: configuration.target, snapshot: nil)
    }

    func currentValue(configuration: RecordToControlConfigIntent) async throws -> RecordToControlValue {
        let snapshot = WidgetSnapshotStore.read(WidgetMoneySnapshot.self)
        return RecordToControlValue.make(entity: configuration.target, snapshot: snapshot)
    }
}
