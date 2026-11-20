import Foundation
import AppIntents
import WidgetKit

// MARK: - 手錶控制項打開手錶 App、遮住金額改了要重畫（手錶 v7b，v25.584；watch/judge.md §3.4；watch/build/v7b/brief.md §1、§2）
//
// 這個檔只屬於**手錶兩個 target**（手錶 App LifeGoodWatch、手錶小格 LifeGoodWatchWidgets）；iPhone 兩個 target 不編。
// 照 iPhone 已經上架的做法（LifeGood/Shared/WidgetActions.swift 的 LifeGoodOpenIntent／WidgetOpenAppHandoff）：
//
// 1. WatchOpenIntent：控制項「＋ 記一筆」「▶ 開始跑步」按了打開手錶 App 到那一頁。
//    openAppWhenRun = true，而且**兩個手錶 target 都有這個型別**——Apple〈Creating controls to perform actions across
//    the system〉：「要打開 App，intent 的 Target Membership 一定要同時是 App 與 widget extension」（build/v7b/doc/）。
//    perform 碰不到手錶 App 的型別（WatchModel），所以只把網址交給 WatchOpenHandoff，由手錶 App 回前景時登記的處理者
//    走跟錶面小格點進來（onOpenURL）同一個總入口 WatchModel.open：
//      • lifegood://add/expense?src=widget → 記一筆第一步（記帳台）
//      • lifegood://life/health/run?src=widget → ③ 跑步＋準備頁（**不自己倒數**；Ultra 動作按鈕照 v5 StartRunIntent 那條，一按就開始）
//    保險：萬一系統在小工具的行程裡跑了 perform（沒有登記的處理者），網址先存進手錶 App Group 的 UserDefaults，
//    手錶 App 回前景時 register → consumeStored 撿起來（20 秒內的才算）。
//    watchOS 26 SDK 會說 openAppWhenRun 是舊寫法（新的是 supportedModes，watchOS 26 才有），最低 watchOS 11 照用，只多一個警告
//    （v5 StartRunIntent 同一個警告，已經上架）。
// 2. WatchControlRefresh：手錶「遮住金額」改了（手錶設定頁、控制項都叫）——小格全部重畫；watchOS 26 起控制中心那顆也重畫。
//
// ⚠️ 這裡只准 Foundation／AppIntents／WidgetKit 與共用檔的型別（WidgetLink、WidgetShared、WatchWidgetKind）。
//    「遮住金額」控制項的 SetValueIntent 只在手錶小格裡跑、不開 App，放在 LifeGoodWatchWidgets/WatchControls.swift。

// MARK: - 打開手錶 App

struct WatchOpenIntent: AppIntent {
    static var title: LocalizedStringResource = "打開 LifeGood 手錶版"
    static var description = IntentDescription("打開手錶上的 LifeGood 到指定的頁面")
    /// 要開 App（控制項按了就到記帳台／準備頁）
    static var openAppWhenRun: Bool = true

    /// 目的地網址（WidgetLink 組好的 absoluteString）。用字串不用 URL：參數型別越單純越不會出事（同 iPhone）
    @Parameter(title: "網址")
    var link: String

    init() {}

    init(url: URL) {
        self.link = url.absoluteString
    }

    func perform() async throws -> some IntentResult {
        let url = URL(string: link) ?? WidgetLink.addExpense()
        await MainActor.run {
            WatchOpenHandoff.deliver(url)
        }
        return .result()
    }
}

/// WatchOpenIntent → 手錶 App 的交接。手錶 App 每次回前景（WatchModel.scenePhaseChanged(.active)）登記處理者
///（處理者呼叫 WatchModel.open，跟 onOpenURL 同一條路），登記時順手撿存著的網址
@MainActor
enum WatchOpenHandoff {
    /// 手錶 App Group UserDefaults 的鍵：還沒交出去的網址與存的時間
    static let urlKey = "watch_open_url"
    static let timeKey = "watch_open_url_at"
    /// 存著的網址多久以內還算數（太舊的是上次沒交出去的，不要突然跳頁）
    static let maxAge: TimeInterval = 20

    private static var handler: ((URL) -> Void)?

    /// 手錶 App 登記（只有手錶 App 會呼叫；換掉舊的）。登記完馬上看有沒有存著的網址
    static func register(_ newHandler: @escaping (URL) -> Void) {
        handler = newHandler
        consumeStored()
    }

    /// WatchOpenIntent.perform 呼叫：有處理者（在手錶 App 的行程裡）就直接交；
    /// 沒有（手錶 App 還沒回前景、或在小工具的行程裡跑）就先存進 App Group
    static func deliver(_ url: URL) {
        if let h = handler {
            h(url)
            return
        }
        guard let d = WidgetShared.defaults else { return }
        d.set(url.absoluteString, forKey: urlKey)
        d.set(Date().timeIntervalSince1970, forKey: timeKey)
    }

    /// 有 maxAge 秒內存的網址就交給處理者，不管有沒有交都清掉
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

// MARK: - 遮住金額改了

enum WatchControlRefresh {
    /// 手錶「遮住金額」改了（手錶設定頁 WatchModel.setWatchHidesAmounts、控制項 SetWatchHideAmountsIntent）：
    /// 錶面小格全部重畫（不用等下一包，judge §2.15）；watchOS 26 起控制中心「遮住金額（手錶）」那顆也重畫
    static func afterHideAmountsChanged() {
        WidgetCenter.shared.reloadAllTimelines()
        if #available(watchOS 26, *) {
            ControlCenter.shared.reloadControls(ofKind: WatchWidgetKind.controlHide)
        }
    }
}
