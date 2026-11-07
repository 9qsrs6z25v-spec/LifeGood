import Foundation
import AppIntents

// MARK: - 捷徑動作「記一筆支出」＋ App Shortcuts（v25.608 wallet）
//
// 只屬於「LifeGood」target（不放 Shared）：perform 要叫 App 才有的 WalletIntake／QuickRecordImporter，
// 小工具 target 用不到它；放 App target，系統會在 App 的行程裡（必要時在背景把 App 叫起來）跑 perform，不打開 App。
// 規格：scratchpad/radar/judge_wallet.md §C1；分工：scratchpad/radar/build/wallet/brief.md（G1）。
//
// 用法（設定 → 進階設定 →「Apple Pay 自動記帳」的「怎麼設定」是同一份字，brief 第 6 節定稿）：
//   1. 打開「捷徑」App，點下面的「自動化」。
//   2. 新增一個自動化（右上角的 ＋），在清單裡選「交易」。
//   3. 選要自動記帳的卡片（可以全選），選「立即執行」，按下一步。
//   4. 建立新的空白捷徑，加入動作：搜尋「LifeGood」，選「記一筆支出」。
//   5. 「金額」點一下選「捷徑輸入」，再點它選「金額」；「商家」選「捷徑輸入」的商家；「卡片」選「捷徑輸入」的卡片（名稱可能是「卡片或票卡」）。
//   6. 按「完成」。下一次用 Apple Pay 付款，LifeGood 就會在背景記一筆，捷徑只回「已記一筆」。
//   （小字：第一次執行時，系統可能會問要不要允許 LifeGood 執行，選允許。如果不想每次跳出執行提示，可以在那個自動化裡把通知關掉。）
//   捷徑 App 的介面字只寫 iOS 18 繁中有把握的（捷徑、自動化、交易、立即執行、捷徑輸入、完成），沒把握的按鈕寫描述；App 名一律寫「捷徑」（不用簡體中文介面的叫法）。
//
// iOS 18 API 核對（G1）：
// • AppIntent：static title（LocalizedStringResource）／description（IntentDescription）／openAppWhenRun（iOS 16+）。
//   openAppWhenRun 在 iOS 26 SDK 改推 supportedModes（iOS 26 才有、static 屬性擋不了 #available），所以照用 openAppWhenRun；
//   最多是一個「已過時」警告，不是錯誤（小工具的 QuickRecordIntent 等同樣寫法）。
// • @Parameter(title:) 接 String（必填）與 String?（選填）；parameterSummary 用 Summary("… \(\.$參數)") { \.$其他參數 }（iOS 16+）。
// • perform 標 @MainActor（WalletIntake 是 @MainActor、同步）；兩個 return 都是 .result(dialog:)，同一個具體型別；不 throw。
// • AppShortcutsProvider.appShortcuts 的 @AppShortcutsBuilder 從協定推得到（Apple 範例同寫法）；
//   AppShortcut(intent:phrases:shortTitle:systemImageName:) iOS 16.4+；片語用 \(.applicationName)（AppShortcutPhraseToken）。
//
// • 參數都用 String：交易的金額接成文字會是「NT$65」「$12.50」「1,280」這類，App 自己解析（WalletAutoRecord.parseAmount）。
//   沒用 IntentCurrencyAmount：沒把握 iOS 18 捷徑能把交易的金額變數直接接上它（judge §C1）
// • 回覆（dialog）只准兩句：「已記一筆」／「沒有記到，打開 LifeGood 看看」——不帶金額、商家、卡名（鎖定畫面也可能看得到）
// • 不發通知、不碰小工具、不連網

struct WalletRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "記一筆支出"
    static var description = IntentDescription("用 Apple Pay 付款時，把金額、商家、卡片記成 LifeGood 的一筆變動支出（在背景記，不打開 App）")
    /// 不開 App：在背景寫進待入帳就結束（App 開著就當場收進帳本）
    static var openAppWhenRun: Bool = false

    /// 交易的金額（文字）：「NT$65」「$12.50」「1,280」
    @Parameter(title: "金額")
    var amountText: String

    /// 交易的商家 → 支出名稱（空的寫「Apple Pay」）
    @Parameter(title: "商家")
    var merchant: String?

    /// 交易的卡片名稱 → 連到財富裡的信用卡或銀行帳戶（設定頁對應）
    @Parameter(title: "卡片")
    var card: String?

    static var parameterSummary: some ParameterSummary {
        Summary("記一筆支出 \(\.$amountText)") {
            \.$merchant
            \.$card
        }
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = WalletIntake.record(amountText: amountText, merchant: merchant, card: card, now: Date())
        if result.recorded {
            return .result(dialog: "已記一筆")
        }
        return .result(dialog: "沒有記到，打開 LifeGood 看看")
    }
}

/// App 唯一的一個 AppShortcutsProvider（repo 之前沒有）：讓「記一筆支出」出現在捷徑 App 的 LifeGood 動作與 Siri／Spotlight。
/// 片語一定要含 \(.applicationName)
struct LifeGoodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WalletRecordIntent(),
            phrases: [
                "用 \(.applicationName) 記一筆支出",
                "在 \(.applicationName) 記一筆支出"
            ],
            shortTitle: "記一筆支出",
            systemImageName: "creditcard"
        )
    }
}
