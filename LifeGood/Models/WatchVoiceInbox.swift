import Foundation
import UIKit

// MARK: - 手錶的說一句（手錶 v7a，v25.585；只屬於主 App；watch/judge.md §4.1「說一句」、§5.4、§5.5、§6.1、§6.7、附錄 B；
//         watch/build/v7a/brief.md §2；規則跟 scratchpad/watch/build/v7a/sim_v7a.py 同名函式一模一樣）
//
// 手錶送來一句 WatchVoice（Shared/WatchVoice.swift）。WatchBridge 收到（兩條路：sendMessage、transferUserInfo）：
//   ① WatchVoiceLog 有這個編號＝早就記過了（另一條路先到、手錶重送）→ 直接回那一份結果，不再記
//   ② 不然寫進 App Group 一個小檔 watch_voice_v1/<編號>.json（WatchVoiceInbox.add，只碰檔案）
//   ③ WatchVoiceApplier 準備好了（App 開著、或剛用過還活著：LifeGoodApp 的 .task 叫過 start）→ 叫它記，回「working」；
//      不是（被手錶叫醒的冷啟動，judge §5.4）→ 回「queued」，**不碰 AppStores、不叫 AI、不算數字**；
//      下次打開 LifeGood（.task、回前景，讀完訂閱之後）WatchVoiceApplier.applyPending 照講完的時間順序記
// WatchVoiceApplier 一句一句記（不交錯：AI 解析、地點查詢都是 await，同時兩句提示會亂，同 AIQuickVoice 的理由）：
//   帳本裡已經有這個編號（上次記到一半被關掉）→ 照那一筆回；沒字 → empty；沒訂閱（先讀一次訂閱）→ needsSubscription；
//   沒設好 AI → needsAI；都好 → AIExpenseCommitter.record（id＝這一句的編號、date＝講完那一刻、旅途中記到那一站，外幣照 v6）→
//   帳本裡有了＝recorded，沒有＝照提示字分 ownTransfer／noAmount／offline（網路錯誤）／notUnderstood。
//   每一句不管結果：記進 WatchVoiceLog、刪檔、回手錶（WatchBridge.sendSaid）；記好了的編號也記進 WatchImportedLog
//   （iPhone「今天記的帳」那一筆標 ⌚︎ 手錶記的）、馬上重寫 money 快照（手錶包跟著送）。
//
// ⚠️ 回手錶的 WatchVoiceSaid 只有名稱、分類、台幣、外幣字、付款類別（刷卡／現金／轉帳）：
//    **不碰 AIExpenseOutcome.detail**（那裡有卡名「CUBE 末1234」）；名稱先拿掉卡名、銀行名、末四碼（WatchVoiceRule.scrub）。
//    你講的原文 iPhone 不回傳；記好之後 watch_voice_v1 那個檔就刪了（原文只留在帳本那筆支出的 AI 解析結果裡，跟 iPhone 說一句一樣）。
// ⚠️ WatchVoiceInbox、WatchVoiceLog（檔案、UserDefaults 那兩支）會在被手錶叫醒的冷啟動跑：只准碰 App Group，
//    不准碰 AppStores、三份大資料、AI、訂閱（pkg_keys_check.py D8 擋）。WatchVoiceApplier 只在 start 拿到三份資料之後才記。

/// 排著還沒記的說一句（只有檔案；被手錶叫醒的冷啟動也能叫）
enum WatchVoiceInbox {
    /// <App Group>/Widgets/ 底下的資料夾（judge §5.4「說一句寫 watch_voice_v1 一個檔」）
    static let folderName = "watch_voice_v1"

    /// <App Group>/Widgets/watch_voice_v1/。create 為 true 時順手建（保護等級跟收件匣一樣）
    static func folderURL(create: Bool) -> URL? {
        guard let base = WidgetSnapshotStore.folderURL(create: create) else { return nil }
        let folder = base.appendingPathComponent(folderName, isDirectory: true)
        if create {
            let attributes: [FileAttributeKey: Any] = [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: attributes)
            } catch {
                return nil
            }
        }
        return folder
    }

    private static func fileURL(_ id: UUID, in folder: URL) -> URL {
        folder.appendingPathComponent(id.uuidString + ".json", isDirectory: false)
    }

    /// 排一句（原子寫入；同一個編號覆寫同一個檔＝兩條路都到也只有一個檔）。寫不進去回 false
    @discardableResult
    static func add(_ voice: WatchVoice) -> Bool {
        guard let folder = folderURL(create: true), let data = WatchVoiceCodec.encode(voice) else { return false }
        do {
            try data.write(to: fileURL(voice.id, in: folder),
                           options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    /// 排著的全部，依講完的時間由舊到新（同一刻編號字串小的先）。解不開的壞檔刪掉（不然每次都卡在那裡）
    static func pending() -> [WatchVoice] {
        guard let folder = folderURL(create: false) else { return [] }
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [WatchVoice] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let voice = WatchVoiceCodec.decode(data) {
                out.append(voice)
            } else {
                try? fm.removeItem(at: url)
            }
        }
        return out.sorted { a, b in
            if a.saidAt != b.saidAt { return a.saidAt < b.saidAt }
            return a.id.uuidString < b.id.uuidString
        }
    }

    static func remove(_ id: UUID) {
        guard let folder = folderURL(create: false) else { return }
        try? FileManager.default.removeItem(at: fileURL(id, in: folder))
    }
}

/// 記過的說一句（App Group UserDefaults「watch_voice_done_v1」：WatchVoiceSaid 的 JSON 陣列，新的在後、最多 200 句）。
/// 同一句從另一條路再到、手錶重送：直接回這一份，不再記。只碰 UserDefaults（冷啟動也能讀）
enum WatchVoiceLog {
    static let key = "watch_voice_done_v1"
    static let maxCount = 200

    static func all() -> [WatchVoiceSaid] {
        guard let data = WidgetShared.defaults?.data(forKey: key),
              let list = try? WidgetSnapshotStore.makeDecoder().decode([WatchVoiceSaid].self, from: data) else { return [] }
        return list
    }

    static func said(for id: UUID) -> WatchVoiceSaid? {
        all().last(where: { $0.id == id })
    }

    /// 記一句（主執行緒，WatchVoiceApplier）
    static func note(_ said: WatchVoiceSaid) {
        let list = noted(all(), said, max: maxCount)
        guard let data = try? WidgetSnapshotStore.makeEncoder().encode(list) else { return }
        WidgetShared.defaults?.set(data, forKey: key)
    }

    /// 同一個編號的拿掉、加在最後、只留最後 max 句（sim_v7a.py voice_log_noted）
    static func noted(_ list: [WatchVoiceSaid], _ said: WatchVoiceSaid, max: Int) -> [WatchVoiceSaid] {
        var out = list.filter { $0.id != said.id }
        out.append(said)
        if out.count > max {
            out.removeFirst(out.count - max)
        }
        return out
    }
}

/// 回手錶的那一份（只有名稱、分類、台幣、外幣字、付款類別；sim_v7a.py said_recorded／said_outcome）
@MainActor
enum WatchVoiceSaidBuilder {
    /// AIParseError.network 的提示字開頭（AIService.swift「網路錯誤：…」）：AI 連不上＝iPhone 沒網路
    static let networkPrefix = "網路錯誤"

    static func failure(_ id: UUID, _ outcome: WatchVoiceOutcome) -> WatchVoiceSaid {
        WatchVoiceSaid(id: id, kind: outcome.rawValue)
    }

    /// 帳本裡那一筆 → 回手錶的字。名稱拿掉卡名、銀行名、末四碼（拿完是空的用分類名）；付款只寫類別；
    /// 旅途中外幣（那一筆存的幣別＝手錶那一句的幣別、有 AI 聽到的數字）帶「₩18,000」
    static func recorded(_ e: Expense, voice: WatchVoice, spokenAmount: Double?, accountWords: [String]) -> WatchVoiceSaid {
        let category: String = e.variableCategory?.rawValue ?? ""
        let cleaned = WatchVoiceRule.scrub(e.title, words: accountWords)
        let title: String = cleaned.isEmpty ? category : cleaned
        let pay = WatchVoiceRule.pay(card: e.linkedCreditCardMilestoneId != nil, bank: e.linkedBankMilestoneId != nil)
        var foreign: String? = nil
        if let c = voice.currency, let spoken = spokenAmount, e.currencyCode == c.code {
            foreign = WatchVoiceText.foreignText(spoken, currency: c)
        }
        return WatchVoiceSaid(id: voice.id, kind: WatchVoiceOutcome.recorded.rawValue,
                              title: title, categoryTitle: category.isEmpty ? nil : category,
                              amountTWD: e.amount, foreignText: foreign, pay: pay.rawValue)
    }

    /// 沒記成的是哪一種：照 AIExpenseCommitter 的提示字（字是常數）；「AI 解析失敗」再看是不是網路錯誤
    static func outcome(of o: AIExpenseOutcome) -> WatchVoiceOutcome {
        if o.title == AIExpenseCommitter.ownTransferTitle { return .ownTransfer }
        if o.title == AIExpenseCommitter.noAmountTitle { return .noAmount }
        if o.title == AIExpenseCommitter.failedTitle && o.detail.hasPrefix(networkPrefix) { return .offline }
        return .notUnderstood
    }

    /// 名稱裡要拿掉的字：信用卡的卡名、名稱、末四碼（「末1234」「1234」），銀行帳戶的銀行名、名稱、帳號末四碼
    static func accountWords(life: LifeStore) -> [String] {
        var out: [String] = []
        for ms in life.milestones where ms.category == .achievement {
            if ms.financeSubCategory == .creditCard {
                out.append(ms.title)
                if let name = ms.cardName { out.append(name) }
                if let last4 = ms.cardLastFour, !last4.isEmpty {
                    out.append("末" + last4)
                    out.append(last4)
                }
            } else if ms.financeSubCategory == .bank {
                out.append(ms.title)
                if let name = ms.bankName { out.append(name) }
                if let number = ms.accountNumber {
                    let digits = number.filter { $0.isNumber }
                    if digits.count >= 4 {
                        let last4 = String(digits.suffix(4))
                        out.append("末" + last4)
                        out.append(last4)
                    }
                }
            }
        }
        return out
    }
}

/// 把手錶的說一句記進帳本（主執行緒；LifeGoodApp 的 .task 叫過 start 才會記）
@MainActor
final class WatchVoiceApplier {
    static let shared = WatchVoiceApplier()

    private weak var expenseStore: ExpenseStore?
    private weak var financeStore: FinanceStore?
    private weak var lifeStore: LifeStore?
    /// 正在一句一句記（同時只跑一輪）
    private var running = false
    /// 跑的時候又來了新的：這一輪做完再看一次資料夾
    private var again = false
    /// 被手錶叫醒、或剛進背景時撐的背景時間（AI 要上網，幾秒到十幾秒；做完再多撐 saveGraceSeconds 才收）
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// 第幾輪做完（做完多撐的那幾秒裡又開了新的一輪：舊的那一次不收，新的那一輪做完自己收）
    private var holdGeneration = 0
    /// 做完之後多撐幾秒才收背景時間：ExpenseStore／LifeStore 的存檔丟到背景佇列寫（同 QuickRecordImporter.finishDelay 2 秒、
    /// WatchBridge.recordHoldSeconds 3 秒）——一收 App 就可能被暫停，存檔停在一半，之後被系統關掉那筆就沒存到
    /// （WatchVoiceLog 卻已經寫了「已記一筆」、檔也刪了）
    private static let saveGraceSeconds: UInt64 = 3

    private init() {}

    /// start 叫過、三份資料都還在（App 開著、或剛用過還活著）。WatchBridge 看這個決定「馬上記」還是「只排檔」
    var isReady: Bool { expenseStore != nil && financeStore != nil && lifeStore != nil }

    /// LifeGoodApp 的 .task 叫一次（重複呼叫無害）：記住三份資料。排著的由呼叫的人在讀完訂閱之後叫 applyPending
    func start(expense: ExpenseStore, finance: FinanceStore, life: LifeStore) {
        expenseStore = expense
        financeStore = finance
        lifeStore = life
    }

    /// 記 watch_voice_v1 排著的（照講完的時間由舊到新）。還沒 start 什麼都不做；正在記就等這一輪做完再看一次
    func applyPending() {
        guard isReady else { return }
        if running {
            again = true
            return
        }
        running = true
        holdBackground()
        Task { @MainActor in
            await self.runLoop()
        }
    }

    private func runLoop() async {
        repeat {
            again = false
            for voice in WatchVoiceInbox.pending() {
                guard let expense = expenseStore, let finance = financeStore, let life = lifeStore else { break }
                let said = await process(voice, expense: expense, finance: finance, life: life)
                finish(said)
            }
        } while again && isReady
        running = false
        // 存檔還在背景佇列寫：多撐 3 秒再收（這 3 秒裡又開了新的一輪就不收，那一輪做完自己收）
        holdGeneration += 1
        let generation = holdGeneration
        try? await Task.sleep(nanoseconds: Self.saveGraceSeconds * 1_000_000_000)
        guard !running, generation == holdGeneration else { return }
        endBackground()
    }

    /// 一句 → 結果（sim_v7a.py applier_process 的順序）
    private func process(_ voice: WatchVoice, expense: ExpenseStore, finance: FinanceStore,
                         life: LifeStore) async -> WatchVoiceSaid {
        if let done = WatchVoiceLog.said(for: voice.id) {
            return done
        }
        if let e = expense.expenses.first(where: { $0.id == voice.id }) {
            // 上次記好了、還沒來得及刪檔回話就被關掉：照帳本那一筆回（不再叫 AI、不再記一次）
            return WatchVoiceSaidBuilder.recorded(e, voice: voice, spokenAmount: nil,
                                                  accountWords: WatchVoiceSaidBuilder.accountWords(life: life))
        }
        let text = WatchVoiceRule.cleanText(voice.text)
        guard !text.isEmpty else {
            return WatchVoiceSaidBuilder.failure(voice.id, .empty)
        }
        // 訂閱：剛打開時付費訂閱的到期日可能還沒讀進來，先讀一次（同 AIQuickVoice.prepare）
        let sub = SubscriptionManager.shared
        if !sub.isPremium {
            await sub.refreshStatus()
        }
        guard sub.isPremium else {
            return WatchVoiceSaidBuilder.failure(voice.id, .needsSubscription)
        }
        guard AISettingsStore.shared.isReady else {
            return WatchVoiceSaidBuilder.failure(voice.id, .needsAI)
        }
        var trip: AIExpenseTripLink? = nil
        if let planId = voice.tripPlanId {
            trip = AIExpenseTripLink(planId: planId, stopId: voice.tripStopId,
                                     currencyCode: voice.currency?.code, rateToTWD: voice.currency?.rateToTWD)
        }
        let date = WatchVoiceRule.recordDate(saidAt: voice.saidAt, now: Date())
        let outcome = await AIExpenseCommitter.record(text: text, expense: expense, life: life, finance: finance,
                                                      id: voice.id, date: date, trip: trip)
        if let e = expense.expenses.first(where: { $0.id == voice.id }) {
            return WatchVoiceSaidBuilder.recorded(e, voice: voice, spokenAmount: outcome.spokenAmount,
                                                  accountWords: WatchVoiceSaidBuilder.accountWords(life: life))
        }
        return WatchVoiceSaidBuilder.failure(voice.id, WatchVoiceSaidBuilder.outcome(of: outcome))
    }

    /// 一句做完（不管結果）：記進 WatchVoiceLog、刪檔、回手錶；記好了的再記進 WatchImportedLog、重寫 money 快照
    private func finish(_ said: WatchVoiceSaid) {
        WatchVoiceLog.note(said)
        WatchVoiceInbox.remove(said.id)
        if said.isRecorded {
            WatchImportedLog.note([said.id], at: Date())
            WidgetSnapshotWriter.shared.writeNow([.money])
        }
        WatchBridge.shared.sendSaid(said)
    }

    // MARK: 背景時間（照 WatchBridge.holdForRecord 的寫法）

    private func holdBackground() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "watch.voice") { [weak self] in
            self?.endBackground()
        }
    }

    private func endBackground() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
