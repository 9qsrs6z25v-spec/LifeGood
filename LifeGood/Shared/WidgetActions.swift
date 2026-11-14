import Foundation
import AppIntents
import WidgetKit

// MARK: - 小工具與 App 兩邊都要的動作（v2）
//
// 這個檔案同時屬於「主 App」與「LifeGoodWidgets」兩個 target。
//
// 1. LifeGoodOpenIntent：打開 App 到指定頁（控制項「記一筆」用；[v3] 控制項「說一句」「記到…」、
//    還能花右上「⊕」的 Button(intent:) 也走它）。
//    openAppWhenRun = true，而且兩個 target 都有這個型別——系統會把 App 叫到前景，在 App 的行程裡
//    執行 perform（iOS 18 控制項打開 App 的標準寫法）。perform 碰不到 App 的型別（DeepLinkRouter、
//    AppMode…），所以只把網址交給 WidgetOpenAppHandoff，由 App 啟動時登記的處理者走跟 onOpenURL
//    同一個總入口（WidgetLink.apply，DeepLinkRouter.swift）。
//    iOS 26 SDK 會說 openAppWhenRun 是舊寫法（新的是 supportedModes），最低版本 iOS 18 照用，只多一個警告。
//
//    保險：萬一系統在小工具的行程裡跑了 perform（沒有登記的處理者），網址先存進 App Group 的
//    UserDefaults，App 啟動登記時、每次回前景時 consumeStored() 撿起來（20 秒內的才算）。
//    備案（實機若 App 開了卻沒跳頁）：控制項的 action 換成 iOS 18 的 OpenURLIntent(WidgetLink.addExpense())，
//    網址走 onOpenURL，App 這邊不用改。
//
// 2. WidgetRefresh：重畫小工具與控制項（隱藏金額開關改了、收件匣變了）。
//
// ⚠️ 這裡只准用 Foundation／AppIntents／WidgetKit 與共用檔的型別（WidgetLink、WidgetKind、WidgetShared）。
//    一按就記的按鈕（QuickRecordIntent、UndoQuickRecordIntent）與隱藏金額開關（SetHideAmountsIntent）
//    只在小工具裡跑、不用開 App，放在 LifeGoodWidgets/WidgetIntents.swift，**只屬於小工具 target**。

// MARK: - 打開 App

struct LifeGoodOpenIntent: AppIntent {
    static var title: LocalizedStringResource = "打開 LifeGood"
    static var description = IntentDescription("打開 LifeGood 到指定的頁面")
    /// 要開 App（控制項按了就到新增支出、數字鍵盤跳出）
    static var openAppWhenRun: Bool = true

    /// 目的地網址（WidgetLink 組好的 absoluteString）。用字串不用 URL：參數型別越單純越不會出事
    @Parameter(title: "網址")
    var link: String

    init() {}

    init(url: URL) {
        self.link = url.absoluteString
    }

    func perform() async throws -> some IntentResult {
        let url = URL(string: link) ?? WidgetLink.addExpense()
        await MainActor.run {
            WidgetOpenAppHandoff.deliver(url)
        }
        return .result()
    }
}

/// LifeGoodOpenIntent → App 的交接。App 在 LifeGoodApp.init() 登記處理者
///（處理者呼叫 WidgetLink.apply，跟 onOpenURL 同一條路），回前景時呼叫 consumeStored()。
@MainActor
enum WidgetOpenAppHandoff {
    /// App Group UserDefaults 的鍵：還沒交出去的網址與存的時間
    static let urlKey = "widget_open_url"
    static let timeKey = "widget_open_url_at"
    /// 存著的網址多久以內還算數（太舊的是上次沒交出去的，不要突然跳頁）
    static let maxAge: TimeInterval = 20

    private static var handler: ((URL) -> Void)?

    /// App 啟動時登記（只有 App 會呼叫）。登記完馬上看有沒有存著的網址
    static func register(_ newHandler: @escaping (URL) -> Void) {
        handler = newHandler
        consumeStored()
    }

    /// LifeGoodOpenIntent.perform 呼叫：有處理者（在 App 的行程裡）就直接交；
    /// 沒有（App 還沒登記、或在小工具的行程裡跑）就先存進 App Group
    static func deliver(_ url: URL) {
        if let h = handler {
            h(url)
            return
        }
        guard let d = WidgetShared.defaults else { return }
        d.set(url.absoluteString, forKey: urlKey)
        d.set(Date().timeIntervalSince1970, forKey: timeKey)
    }

    /// App 回前景時呼叫：有 maxAge 秒內存的網址就交給處理者，不管有沒有交都清掉
    static func consumeStored(now: Date = Date()) {
        guard let h = handler, let d = WidgetShared.defaults,
              let raw = d.string(forKey: urlKey) else { return }
        let storedAt = d.double(forKey: timeKey)
        d.removeObject(forKey: urlKey)
        d.removeObject(forKey: timeKey)
        guard now.timeIntervalSince1970 - storedAt <= maxAge,
              let url = URL(string: raw) else { return }
        h(url)
    }
}

// MARK: - 重畫

enum WidgetRefresh {
    /// 重畫這幾種小工具（WidgetKind.moneyKinds／lifeKinds／billsKinds）
    static func reload(_ kinds: [String]) {
        for kind in kinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }

    /// 隱藏金額開關改了（控制項、App 設定頁都呼叫這一支）：全部小工具＋「隱藏金額」控制項重畫
    static func afterHideAmountsChanged() {
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadControls(ofKind: WidgetKind.controlHideAmounts)
    }

    /// [v3] 重畫這幾個控制項（WidgetKind.moneyControlKinds：「記到…」的「Taycan 電費」從 money 快照讀，
    /// App 寫完 money 叫一次）
    static func reloadControls(_ kinds: [String]) {
        for kind in kinds {
            ControlCenter.shared.reloadControls(ofKind: kind)
        }
    }
}
