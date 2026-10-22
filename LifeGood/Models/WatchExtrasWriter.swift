import Foundation

// MARK: - 手錶附加資料快取（手錶 v1，v25.574；只屬於主 App；watch/judge.md §5.2、§8 v1；watch/build/v1/brief.md §2）
//
// 手錶包裡有幾樣東西要碰帳本才算得出來（v1 只有「哪幾期卡費是自己繳」）。被手錶叫醒的冷啟動不准碰帳本，
// 所以 App 開著時（WidgetSnapshotWriter.writeNow 寫 bills 的時候）先把它們寫成 App Group 的一個小檔，
// WatchPackageBuilder 組包時只讀這個檔。v2 起再加最近金額、今天記的帳…（一律選填）。
//
// ⚠️ 這個檔只放「手錶包要的、已經消毒過的」東西：卡費只放帳單的來源 key（「c-<卡 UUID>-<期>」），
//    沒有卡名、金額、號碼。

/// watch_extras_v1.json（只在 iPhone；不會送到手錶）
struct WatchExtrasCache: Codable, Equatable, WidgetSnapshotPayload {
    static let file = WidgetSnapshotFile.watchExtras
    static let schemaVersion = 1

    var schema: Int = WatchExtrasCache.schemaVersion
    var generatedAt: Date
    /// 自己繳（WealthCardDue.isManual）的那幾期卡費：「c-<卡 UUID>-<帳單 key>」（＝FinanceUpcoming 卡費那一列的 id，
    /// 也是 WidgetBill.id「@」前面那一段），排好
    var manualCardBillKeys: [String]
    /// 這支 iPhone 是加入別人的共享（CloudKitManager.isShareParticipant）：「會議細節裡的部屬名字」預設關（judge §6.6）
    var isShareParticipant: Bool
}

@MainActor
enum WatchExtrasWriter {
    /// WidgetSnapshotWriter.writeNow 寫 bills 時叫（App 開著、三份資料都在）。內容沒變不寫
    static func write(expense: ExpenseStore, finance: FinanceStore, life: LifeStore, now: Date) {
        let facts = life.wealthFacts(expense: expense, finance: finance, now: now)
        var keys: [String] = []
        for card in facts.cards {
            for due in card.dues where due.isManual {
                keys.append("c-" + card.id.uuidString + "-" + due.key)
            }
        }
        keys.sort()
        let cache = WatchExtrasCache(generatedAt: now,
                                     manualCardBillKeys: keys,
                                     isShareParticipant: CloudKitManager.shared.isShareParticipant)
        WidgetSnapshotStore.write(cache)
    }
}
