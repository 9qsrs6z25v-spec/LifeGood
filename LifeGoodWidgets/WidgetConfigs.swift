import SwiftUI
import WidgetKit
import AppIntents

// MARK: - 小工具的長按設定（小工具 v3）
//
// 只屬於「LifeGoodWidgets」target。由 G2 實作，規格見 scratchpad/widgets/v3/brief.md 的 G2-1。
//
// 每個可設定的小工具一個 WidgetConfigurationIntent（AppIntentConfiguration 用），選項型別在共用檔
// LifeGood/Shared/WidgetConfigTypes.swift（WidgetAmountOption、WidgetBillScopeOption、WidgetBillDaysOption、
// WidgetDeskButtonEntity）。預設值＝v2 現在的外觀（升級後已經放好的小工具長得一樣）。
//
// 型別：MoneyLeftConfigIntent、TodayConfigIntent、LedgerDeskConfigIntent、BillsConfigIntent、
//       LockNextStopConfigIntent、LockNextBillConfigIntent
//
// 寫法照 Xcode 的 App Intent 小工具範本：static var title／description＋@Parameter(title:default:)，
// 不寫 perform（WidgetConfigurationIntent 只拿來存設定）。instance 參數不取名 title／description。
// 設定值只在 provider 讀（configuration.xxx），View 裡不碰 intent。

// MARK: - 還能花

/// 「還能花」（小）：金額要不要一律隱藏。右上「⊕」不用設定（StandBy 不放）
struct MoneyLeftConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "還能花"
    static var description = IntentDescription("選金額要不要一律隱藏")

    /// 預設跟著「隱藏金額」總開關（＝v2）
    @Parameter(title: "金額", default: .followMaster)
    var amount: WidgetAmountOption

    init() {}
}

// MARK: - 今天

/// 「今天」（小、中）：顯示哪幾種行程、StandBy 要不要寫主題。
/// 預設四種全開、StandBy 寫主題（主控定案 1：v2 已經是寫主題，升級後要一樣）
struct TodayConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "今天"
    static var description = IntentDescription("選要看哪幾種行程")

    @Parameter(title: "部屬會議", default: true)
    var showMeetings: Bool

    @Parameter(title: "我的行事曆", default: true)
    var showPersonal: Bool

    @Parameter(title: "系統行事曆", default: true)
    var showAppleCalendar: Bool

    @Parameter(title: "旅遊", default: true)
    var showTrip: Bool

    /// 關掉＝StandBy 回到 v1 的類別字（「部屬會議」「會議」「系統行事曆」；旅遊照樣寫站名）
    @Parameter(title: "鎖著時（StandBy）顯示主題", default: true)
    var standBySubject: Bool

    init() {}

    /// 開著的那幾種（給 WidgetLifeSnapshot.filtered(kinds:)；四種都開＝原樣）
    var kinds: Set<TimelineStopKind> {
        var out = Set<TimelineStopKind>()
        if showMeetings { out.insert(.meeting) }
        if showPersonal { out.insert(.personal) }
        if showAppleCalendar { out.insert(.appleCalendar) }
        if showTrip { out.insert(.trip) }
        return out
    }
}

// MARK: - 記帳台

/// 「記帳台」（中）：右邊按鈕 1／2／3、金額。
/// 按鈕沒選（nil）、選「自動」、選的車賣掉了（查不到）一律當自動（WidgetMoneySnapshot.deskTiles(choiceIDs:)）
struct LedgerDeskConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "記帳台"
    static var description = IntentDescription("換右邊的三顆按鈕、金額要不要隱藏")

    @Parameter(title: "按鈕 1")
    var button1: WidgetDeskButtonEntity?

    @Parameter(title: "按鈕 2")
    var button2: WidgetDeskButtonEntity?

    @Parameter(title: "按鈕 3")
    var button3: WidgetDeskButtonEntity?

    /// 一律隱藏時左半改「本月已花／62%／還有 19 天／今天 3 筆」（App 寫好的隱藏版）
    @Parameter(title: "金額", default: .followMaster)
    var amount: WidgetAmountOption

    init() {}

    /// 三格存的 id（WidgetDeskChoice 的規則；nil＝自動）
    var choiceIDs: [String?] {
        [button1?.id, button2?.id, button3?.id]
    }
}

// MARK: - 接下來要繳

/// 「接下來要繳」（中）：範圍、天數、金額。預設全部／30 天／跟著總開關（＝v2）
struct BillsConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "接下來要繳"
    static var description = IntentDescription("選範圍、天數、金額要不要隱藏")

    @Parameter(title: "範圍", default: .all)
    var scope: WidgetBillScopeOption

    @Parameter(title: "天數", default: .days30)
    var days: WidgetBillDaysOption

    @Parameter(title: "金額", default: .followMaster)
    var amount: WidgetAmountOption

    init() {}
}

// MARK: - 鎖定畫面

/// 鎖定畫面「下一場」：要不要寫主題。關掉＝類別字（「部屬會議」「會議」；旅遊照樣寫站名）
struct LockNextStopConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "下一場"
    static var description = IntentDescription("選鎖定畫面要不要顯示行程主題")

    @Parameter(title: "顯示主題", default: true)
    var showTitle: Bool

    init() {}
}

/// 鎖定畫面「下一筆要繳」：要不要寫名稱。關掉＝類別字（「訂閱服務」「房貸」「車貸」）
struct LockNextBillConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "下一筆要繳"
    static var description = IntentDescription("選鎖定畫面要不要顯示名稱")

    @Parameter(title: "顯示名稱", default: true)
    var showName: Bool

    init() {}
}
