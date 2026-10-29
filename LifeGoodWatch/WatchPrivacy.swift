import Foundation

// MARK: - 手錶 App 的遮（手錶 v1，v25.574；watch/judge.md §6.2、§2.17）
//
// 只屬於 LifeGoodWatch。規則在 WatchPrivacyRule（Shared/WatchText.swift，手錶小格也用同一支）；
// 這裡是手錶 App 每一頁拿來問「這一刻要不要遮」的那一份（WatchModel.privacy(dimmed:redacted:) 組好）。
// 每一頁：@Environment(\.isLuminanceReduced)（手腕放下）、@Environment(\.redactionReasons) 含 .privacy（沒解鎖）
// 讀出來交給 WatchModel；**不靠系統的 privacySensitive()**（使用者設定預設「顯示」，等於什麼都不遮，U3 §5.1）。

struct WatchPrivacy: Equatable {
    /// 手腕放下（永遠顯示的暗畫面）：背景純黑、字調暗、能按的變暗不拿掉
    var dimmed: Bool
    var redacted: Bool
    var watchHides: Bool
    var phoneHides: Bool

    /// 金額換成「NT$ ••••」／錢頁整組換隱藏版四行（lines(hidden: true)）
    var masksAmounts: Bool {
        WatchPrivacyRule.masksAmounts(dimmed: dimmed, redacted: redacted, watchHides: watchHides, phoneHides: phoneHides)
    }

    /// 「和 王小明」→「部屬會議」、議程三行 →「議程 3 項」、備註 →「備註 1 則」、「媽媽 62 歲生日」→「家人生日」
    var hidesPersonal: Bool {
        WatchPrivacyRule.hidesPersonal(dimmed: dimmed, redacted: redacted)
    }
}
