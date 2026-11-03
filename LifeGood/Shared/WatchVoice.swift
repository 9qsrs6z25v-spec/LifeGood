import Foundation

// MARK: - 說一句（手錶 v7a，v25.585；watch/judge.md §2.6、§2.17、§4.1「說一句」那一列、§5.4、§5.5、§6.1、§6.7、附錄 B；
//         §評論回覆 🔴11；watch/build/v7a/brief.md §2）
//
// 這個檔屬於兩個 target：iPhone App（LifeGood）、手錶 App（LifeGoodWatch）。手錶小格、iPhone 小工具不編。
// 只准用 Foundation 與 WatchPackage.swift（WatchCurrency、WatchLink）、WidgetSnapshot.swift（WidgetSnapshotStore 的編碼器）的型別。
// scratchpad/watch/build/v7a/sim_v7a.py 跟這個檔的規則與字一模一樣（同名函式），改了兩邊一起改、重跑 sim。
//
// 手錶「說一句」：記帳台第 4 格「🎤 說一句」→ 系統聽寫（TextFieldLink）打成一句「晚餐 320 刷 CUBE」→ WatchVoice →
// 跟記一筆同一套送法（手錶待送盒 VoiceOutbox：transferUserInfo＋iPhone 在旁邊再 sendMessage；iPhone 不在旁邊排隊、回來補送）→
// iPhone 的 AI（AIExpenseCommitter，跟 iPhone 說一句同一支）解析、記帳 → 回手錶一份 WatchVoiceSaid（只有名稱、分類、台幣、
// 付款**類別**）→ 手錶寫「已記一筆：晚餐／飲食・NT$320・刷卡」。
//
// ⚠️ 隱私（judge §6.1、§6.7、評論 🔴11）：
//   • 回給手錶的 WatchVoiceSaid **沒有**卡名、銀行名、末四碼、帳號、同行者、備註、地點的欄位；付款只有 card／cash／transfer 三種字
//     （手錶寫「刷卡／現金／轉帳」，抬手也不寫卡名）。名稱（AI 給的 title）iPhone 先拿掉卡名、銀行名、末四碼（WatchVoiceRule.scrub）
//   • 你講的原文（WatchVoice.text）只在送到 iPhone 之前留在手錶待送盒，iPhone 收到（回話、transferUserInfo 送完）就清掉；
//     iPhone 不回傳原文。手錶畫面上原文只在「講完那一下」抬手看得到，手腕放下不畫
//   • 一句的編號＝那筆支出的編號：兩條路都到、手錶重送，iPhone 只記一次（WatchVoiceLog＋帳本裡已經有這個編號）
// 時間一律是講完那一刻（WatchVoice.saidAt），不是送到、也不是 iPhone 打開才解析的時間。

/// 手錶 → iPhone：說一句。transferUserInfo 與 sendMessage 帶同一份 ["voice": JSON]（WatchVoiceCodec）
struct WatchVoice: Codable, Equatable, Identifiable {
    /// 這一句的編號＝iPhone 那筆支出的編號（兩條路都到只記一次）
    var id: UUID
    /// 系統聽寫打出來的那一句（去頭尾空白、最多 200 字）。手錶待送盒在 iPhone 收到之後清成 ""
    var text: String
    /// 講完那一刻（iPhone 那筆支出的時間）
    var saidAt: Date
    /// [旅途中] 記到哪一趟、哪一站（照 v6 記一筆的預設那一站；不在旅途中兩個都是 nil；stopId nil＝整趟）
    var tripPlanId: UUID? = nil
    var tripStopId: UUID? = nil
    /// [旅途中外幣] 手錶上這一刻的幣別與匯率（照 v6：AI 聽到的數字是那一國的錢，台幣用這個匯率換，iPhone 晚解析也不重算）。
    /// 國內、沒有匯率的是 nil（照台幣記）
    var currency: WatchCurrency? = nil
}

/// 說一句的 JSON（不壓縮；兩邊同一組編碼器）
enum WatchVoiceCodec {
    static func encode(_ voice: WatchVoice) -> Data? {
        try? WidgetSnapshotStore.makeEncoder().encode(voice)
    }

    static func decode(_ data: Data) -> WatchVoice? {
        try? WidgetSnapshotStore.makeDecoder().decode(WatchVoice.self, from: data)
    }
}

/// 一句的結果是哪一種（WatchVoiceSaid.kind 存 rawValue 字串：以後多一種，舊的手錶解得開、照「沒聽懂」寫）
enum WatchVoiceOutcome: String {
    /// 記好了
    case recorded
    /// AI 找不到金額
    case noAmount
    /// AI 回的看不懂、API 錯誤（金鑰錯…）
    case notUnderstood
    /// iPhone 連不上網路（AI 要上網）
    case offline
    /// 沒訂閱
    case needsSubscription
    /// iPhone 沒設定 AI 語音助手（沒選服務、沒填金鑰）
    case needsAI
    /// AI 認出是轉到自己的帳戶（定期轉帳 v1b）：不記成支出
    case ownTransfer
    /// 沒有字
    case empty
}

/// 付款類別（回給手錶只有這三種；judge §2.17「付款一律只寫刷卡／現金／轉帳」）
enum WatchVoicePay: String {
    /// 連了信用卡
    case card
    /// 沒連任何帳戶（AI 的規則：「用現金」不填付款帳戶）
    case cash
    /// 從銀行帳戶扣
    case transfer
}

/// iPhone → 手錶：一句的結果。transferUserInfo（保證送到）＋手錶在旁邊再 sendMessage，鍵 "said"（WatchVoiceSaidCodec）；
/// 手錶重送已經記過的那一句，sendMessage 的回話直接帶它（["ok": "done", "said": Data]）。
/// ⚠️ 只有這幾欄：沒有卡名、銀行名、末四碼、帳號、同行者、備註、地點、你講的原文（pkg_keys_check 白名單）
struct WatchVoiceSaid: Codable, Equatable, Identifiable {
    /// ＝WatchVoice.id
    var id: UUID
    /// WatchVoiceOutcome.rawValue
    var kind: String
    /// 「晚餐」（AI 給的名稱，iPhone 已經拿掉卡名、銀行名、末四碼；記好了才有）
    var title: String? = nil
    /// 「飲食」（VariableCategory.rawValue；記好了才有）
    var categoryTitle: String? = nil
    /// 台幣（那筆支出存的金額；記好了才有）
    var amountTWD: Double? = nil
    /// 旅途中外幣：「₩18,000」（AI 聽到的原幣；國內是 nil）
    var foreignText: String? = nil
    /// WatchVoicePay.rawValue（card／cash／transfer；記好了才有）
    var pay: String? = nil

    var outcome: WatchVoiceOutcome? { WatchVoiceOutcome(rawValue: kind) }
    var isRecorded: Bool { kind == WatchVoiceOutcome.recorded.rawValue }
}

/// 結果的 JSON（不壓縮；兩邊同一組編碼器）
enum WatchVoiceSaidCodec {
    static func encode(_ said: WatchVoiceSaid) -> Data? {
        try? WidgetSnapshotStore.makeEncoder().encode(said)
    }

    static func decode(_ data: Data) -> WatchVoiceSaid? {
        try? WidgetSnapshotStore.makeDecoder().decode(WatchVoiceSaid.self, from: data)
    }
}

// MARK: - 傳話的鍵（附錄 B 說一句那一列）

extension WatchLink {
    /// 手錶 → iPhone：["voice": Data(WatchVoiceCodec)]（transferUserInfo；iPhone 在旁邊再 sendMessage 一次）。
    /// iPhone 回 ["ok": "working" | "queued" | "done" | "failed", "said": Data（done 才有）]
    static let voiceKey = "voice"
    /// iPhone → 手錶：["said": Data(WatchVoiceSaidCodec)]（transferUserInfo＋手錶在旁邊再 sendMessage；回話 done 時也帶）
    static let saidKey = "said"
    /// iPhone 的 LifeGood 開著，正在記（AI 要幾秒；記好了另外送 said 回來）
    static let okWorking = "working"
}

// MARK: - 規則（iPhone、手錶同一份；sim_v7a.py 同名函式）

enum WatchVoiceRule {
    /// 一句最多幾個字（系統聽寫一次講太長的，後面不要）
    static let maxTextLength = 200
    /// 講完的時間比現在晚這麼多（手錶時鐘不準）就用現在（同 WatchRecordInbox.futureSlack）
    static let futureSlack: TimeInterval = 5 * 60
    /// 換成台幣的上限（同 WatchTripText.maxTWD、iPhone 收件匣的上限）
    static let maxTWD: Double = 9_999_999
    /// 名稱裡要拿掉的字至少幾個字（一個字的不拿：會把「飲」這種字也拿掉）
    static let minScrubLength = 2

    /// 說一句能不能用（WatchExtrasWriter 寫進手錶包 voiceReady）：訂閱而且 AI 設好了
    static func ready(premium: Bool, aiReady: Bool) -> Bool {
        premium && aiReady
    }

    /// 系統聽寫打出來的字：去頭尾空白與換行、最多 200 字
    static func cleanText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxTextLength else { return trimmed }
        return String(trimmed.prefix(maxTextLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 那筆支出的時間：講完那一刻；比現在晚 5 分鐘以上（手錶時鐘不準）用現在
    static func recordDate(saidAt: Date, now: Date) -> Date {
        saidAt.timeIntervalSince(now) > futureSlack ? now : saidAt
    }

    /// 外幣換台幣（照 v6 WatchTripText.twdAmount：四捨五入到元、> 0 至少 1 元、上限 9,999,999）。
    /// 金額或匯率不是正的有限數字回 nil
    static func twdAmount(foreign: Double, rate: Double) -> Double? {
        guard foreign.isFinite, foreign > 0, rate.isFinite, rate > 0 else { return nil }
        let v = (foreign * rate).rounded()
        if v < 1 { return 1 }
        if v > maxTWD { return maxTWD }
        return v
    }

    /// AI 聽到的數字 → 那筆支出存的金額與幣別。旅途中外幣（code 不是空的、匯率是正的）：台幣用手錶上的匯率換、幣別＝那一國；
    /// 其他（iPhone 自己的說一句、國內、沒有匯率）：原樣、"NT$"（AIExpenseCommitter 以前的行為一模一樣）
    static func recorded(spoken: Double, code: String?, rate: Double?) -> (amount: Double, currencyCode: String) {
        let trimmed = (code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let rate, let twd = twdAmount(foreign: spoken, rate: rate) else {
            return (amount: spoken, currencyCode: "NT$")
        }
        return (amount: twd, currencyCode: trimmed)
    }

    /// 付款類別：連了信用卡＝刷卡；連了銀行帳戶（沒連卡）＝轉帳；都沒有＝現金
    static func pay(card: Bool, bank: Bool) -> WatchVoicePay {
        if card { return .card }
        if bank { return .transfer }
        return .cash
    }

    /// 名稱拿掉卡名、銀行名、末四碼（words：iPhone 的信用卡、銀行帳戶的名稱、暱稱、「末1234」、末四碼）。
    /// 大小寫不分；兩個字以上的才拿；拿完頭尾的空白、標點也拿掉。拿完是空的回 ""（呼叫的人改用分類名）
    static func scrub(_ title: String, words: [String]) -> String {
        var out = title
        let list = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= minScrubLength }
            .sorted { a, b in a.count > b.count }
        for w in list {
            while let r = out.range(of: w, options: [.caseInsensitive]) {
                out.removeSubrange(r)
            }
        }
        while out.contains("  ") {
            out = out.replacingOccurrences(of: "  ", with: " ")
        }
        let edges = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "・-—_／/,，、。:：()（）"))
        return out.trimmingCharacters(in: edges)
    }
}

// MARK: - 字（手錶畫面；iPhone 不畫，但同一份方便 sim 核對）

/// 一句送到哪了（手錶「說一句」那一頁、記帳台最下面那一行）
enum WatchVoiceStatus: Equatable {
    /// 送出了，等 iPhone 回話（最多 5 秒）
    case sending
    /// 還沒送到 iPhone（不在旁邊、LifeGood 被滑掉、還沒啟動好——手錶分不出是哪一種）：先存在手錶上（count＝還沒送到的句數，含這句）
    case offline(count: Int)
    /// iPhone 收到了（transferUserInfo 送完），還沒回話
    case delivered
    /// iPhone 的 LifeGood 開著，正在記（AI 要幾秒）
    case working
    /// iPhone 收到了，但上面的 LifeGood 沒開：打開才記
    case queued
    /// 有結果了
    case done(WatchVoiceSaid)

    /// 「說一句」那一頁要不要 2.5 秒後自己收起來：記好了、在 iPhone 等著記、還沒送到、已送到——之後的結果寫在記帳台最下面那一行。
    /// 沒記成（要你知道為什麼）、正在送、正在記：不自己收，按〔完成〕
    var closesAutomatically: Bool {
        switch self {
        case .sending, .working: return false
        case .offline, .delivered, .queued: return true
        case .done(let s): return s.isRecorded
        }
    }

    /// 這一行要不要琥珀色（還沒送到、沒記成）
    var isWarning: Bool {
        switch self {
        case .offline: return true
        case .done(let s): return !s.isRecorded
        case .sending, .delivered, .working, .queued: return false
        }
    }
}

enum WatchVoiceText {
    // MARK: 記帳台第 4 格

    /// 記帳台那一格的編號、字、圖示、顏色（紫＝iPhone 說一句的顏色 8C59F2，WidgetDeskTile.voice）
    static let tileId = "voice"
    static let tileTitle = "說一句"
    static let tileIcon = "mic.fill"
    static let tileTint: UInt32 = 0x8C59F2
    /// 系統輸入畫面上的提示（例子只寫付款類別，不寫卡名）
    static let prompt = "例：晚餐 320 刷卡"
    /// 「說一句」那一頁的標題
    static let pageTitle = "說一句"
    /// 「說一句」那一頁你講的那一句：「「晚餐 320 刷 CUBE」」（只在抬手、講完那一下；judge §6.1）
    static func quoted(_ text: String) -> String {
        "「" + text + "」"
    }
    /// 手腕放下、沒解鎖時那一行換成這個（版面不跳、原文不畫）
    static let quoteHidden = "你說的那一句（抬手才看得到）"
    /// 「說一句」那一頁：結果還沒來時（手錶上已經沒有這一句）
    static let statusUnknown = "已送出"
    /// 不能用那一頁打開之後 iPhone 剛好好了
    static let nowReady = "說一句可以用了，回記帳台按「說一句」"

    /// 不能用時「說一句」那一頁寫的（voiceReady：true＝能用回 nil；false＝沒訂閱或沒設 AI；nil＝iPhone 還沒送過這個欄位）
    static func blockedReason(voiceReady: Bool?) -> String? {
        guard let ready = voiceReady else {
            return "打開 iPhone 上的 LifeGood 一次（25.585 以後），說一句才能用"
        }
        if ready { return nil }
        return "說一句要訂閱 LifeGood，並在 iPhone「設定 › 進階設定 › 語音 AI 助手」選好服務、填好金鑰"
    }

    /// 不能用時記帳台最下面那一行（短）
    static func blockedShort(voiceReady: Bool?) -> String? {
        guard let ready = voiceReady else { return "說一句：先打開 iPhone 上的 LifeGood 一次" }
        if ready { return nil }
        return "說一句：要訂閱、在 iPhone 設好 AI 才能用"
    }

    /// 不能用那一頁最下面（怎麼換回來）
    static let blockedFooter = "可以先用其他三格，或「選分類、自己打數字」記。不想放這一格：手錶設定 › 記帳台第 4 格，換回常記的那一筆"

    // MARK: 送到哪了

    static func statusLine(_ s: WatchVoiceStatus, masked: Bool) -> String {
        switch s {
        case .sending: return "送到 iPhone…"
        case .offline(let n): return "還沒送到 iPhone，先存在手錶上（\(n) 句）"
        case .delivered: return "已送到 iPhone，記好會告訴你"
        case .working: return "iPhone 正在記…"
        case .queued: return "已收到，打開 iPhone 上的 LifeGood 後記帳"
        case .done(let said): return saidLine(said, masked: masked)
        }
    }

    /// 狀態下面那一行小字；沒有回 nil
    static func statusNote(_ s: WatchVoiceStatus) -> String? {
        switch s {
        case .sending, .working: return nil
        case .offline: return "iPhone 在旁邊時自己補送"
        case .delivered: return "iPhone 上的 LifeGood 沒開的話，打開後才記"
        case .queued: return "記好了會寫在記帳台最下面"
        case .done(let said): return said.isRecorded ? "錶面的「已花」幾分鐘內跟上" : "這一句沒有記帳"
        }
    }

    // MARK: 結果那一行（judge §2.6、§2.17、附錄 B：「已記一筆：晚餐／飲食・NT$320・刷卡」）

    /// 付款類別的字；不認得回 nil（不寫）
    static func payWord(_ raw: String?) -> String? {
        guard let raw, let p = WatchVoicePay(rawValue: raw) else { return nil }
        switch p {
        case .card: return "刷卡"
        case .cash: return "現金"
        case .transfer: return "轉帳"
        }
    }

    /// 記好了：「已記一筆：晚餐／飲食・NT$320・刷卡」；外幣「已記一筆：韓國炸雞／飲食・₩18,000 ≈ NT$412・刷卡」；
    /// 遮住（手腕放下、沒解鎖、遮住金額）金額換「NT$ ••••」，名稱、分類、付款類別照寫。
    /// 沒記成：一句話說為什麼、這句沒記到（「iPhone 沒聽懂，請到 iPhone 補記」「說一句要訂閱，這句沒有記帳」）
    static func saidLine(_ said: WatchVoiceSaid, masked: Bool) -> String {
        guard let outcome = said.outcome else { return failureText(.notUnderstood) }
        guard outcome == .recorded else { return failureText(outcome) }
        var parts: [String] = [nameText(said), amountText(said, masked: masked)]
        if let p = payWord(said.pay) {
            parts.append(p)
        }
        return "已記一筆：" + parts.joined(separator: "・")
    }

    /// 沒記成的那幾種
    static func failureText(_ o: WatchVoiceOutcome) -> String {
        switch o {
        case .recorded: return "已記一筆"
        case .noAmount: return "iPhone 沒聽到金額，請到 iPhone 補記"
        case .notUnderstood: return "iPhone 沒聽懂，請到 iPhone 補記"
        case .offline: return "iPhone 連不上網路，請到 iPhone 補記"
        case .needsSubscription: return "說一句要訂閱，這句沒有記帳"
        case .needsAI: return "iPhone 還沒設定 AI 語音助手，這句沒有記帳"
        case .ownTransfer: return "這是轉帳，沒有記成支出"
        case .empty: return "沒聽到內容，這句沒有記帳"
        }
    }

    /// 「晚餐／飲食」；名稱跟分類一樣、或沒有名稱時只寫一個（「飲食」）
    static func nameText(_ said: WatchVoiceSaid) -> String {
        let title = (said.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let category = (said.categoryTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return category.isEmpty ? "一筆" : category }
        if category.isEmpty || category == title { return title }
        return title + "／" + category
    }

    /// 「NT$320」；外幣「₩18,000 ≈ NT$412」；遮住「NT$ ••••」
    static func amountText(_ said: WatchVoiceSaid, masked: Bool) -> String {
        if masked { return "NT$ ••••" }
        let twd = "NT$" + grouped(wholeTWD(said.amountTWD))
        guard let foreign = said.foreignText, !foreign.isEmpty else { return twd }
        return foreign + " ≈ " + twd
    }

    /// 台幣取整數：先在 Double 上夾 0…9,999,999 再轉 Int（舊錶 arm64_32 的 Int 是 32 位）
    static func wholeTWD(_ v: Double?) -> Int {
        guard let v, v.isFinite else { return 0 }
        return Int(min(max(v, 0), WatchVoiceRule.maxTWD).rounded())
    }

    /// 外幣的字（iPhone 組 WatchVoiceSaid.foreignText 用）：「₩18,000」「US$12.5」；沒有符號「韓元 18,000」。
    /// 整數照每三位一個逗號；有小數的最多兩位、去掉尾巴的 0
    static func foreignText(_ amount: Double, currency c: WatchCurrency) -> String {
        let number = foreignNumber(amount)
        return c.symbol.isEmpty ? c.label + " " + number : c.symbol + number
    }

    static func foreignNumber(_ amount: Double) -> String {
        guard amount.isFinite, amount > 0 else { return "0" }
        let clamped = min(amount, 999_999_999)
        let rounded = clamped.rounded()
        if abs(clamped - rounded) < 0.005 {
            return grouped(Int(rounded))
        }
        let whole = Int(clamped.rounded(.down))
        var cents = Int(((clamped - Double(whole)) * 100).rounded())
        var head = whole
        if cents >= 100 {
            head += 1
            cents -= 100
        }
        var tail = cents < 10 ? "0" + String(cents) : String(cents)
        while tail.hasSuffix("0") {
            tail.removeLast()
        }
        return tail.isEmpty ? grouped(head) : grouped(head) + "." + tail
    }

    /// 「1,200」（每三位一個逗號；不靠語系；同 RecordText.grouped、WatchTripText.grouped）
    static func grouped(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 {
                out += ","
            }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }
}
