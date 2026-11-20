import Foundation
import Vision

// MARK: - [v25.568] 財富 v7：號碼加密（wealth/judge.md §7、§8 v7；build/v7/brief.md §1、§2）
//
// 使用者原話：「6. 我要存　9. 全留　其他照你的建議，幫我一次做到好」。第 6 題：安全碼照樣加密存、Face ID 後 30 秒看得到。
// 這一版把剩下的明碼號碼也改成密文（CardVault 同一把金鑰；規矩寫在 CardVault.swift 開頭）：
// • 完整帳號（銀行、證券戶）：密文在財富帳本 accounts[id].accountNumberCipher（v25.564 起就有的欄位，25.564 以後的 iPad
//   認得、存帳本時照寫回去，不會洗掉）；里程碑的 accountNumber 只留後 4 碼（還沒更新的 iPad、網頁版只看得到後 4 碼：待決定 7）。
// • 有效期限、保單號碼、悠遊卡／一卡通／Happy Go 卡號：密文放這一包（WealthVaultBook，同步鍵 life_wealth_vault_v1）。
//   另開一個鍵：舊版不認得、不會碰它（同 v25.557 請假週、v25.566 定存那一招）。放進財富帳本的話，25.564–25.567 的 iPad 存一次
//   帳本就會用它自己的 CodingKeys 重寫整包、把不認得的密文洗掉，明碼又已經清了＝號碼永遠不見。
//   里程碑上：保單號碼、票證號只留後 4 碼（卡片頁「•••• 3388」、網頁版照讀）；有效期限清掉（日期沒辦法只留一半）。
// • 舊的明碼在新版第一次打開時搬（LifeStore.migrateWealthSecrets：讀檔、從 iCloud 拉到新資料、打開財富頁、匯入備份之後）。
//   這台封不了（有密文、這台還沒同步到金鑰）那一筆整筆不動，照舊留明碼，等金鑰同步過來下次再搬——絕不產生新金鑰蓋掉別台那把。
// • 還沒更新的 iPad 又寫回明碼（在舊版表單打了完整號碼）：新版下次打開照樣再搬一次（明碼一定比密文新：新版從不寫明碼）。
// • 有效期限 App 裡照樣用（行事曆「卡片到期」、要確認 #12、通知）：LifeStore.cardExpiryMonths 在這台有金鑰時解開，只取年月，
//   只在記憶體；網頁版那一包（WealthWebFacts）、匯出、CSV 都不放有效期限。
// • 照片拍到完整卡號（16 位數字）時提醒：WealthPhotoScan 只用手機內建的 Vision 文字辨識，不上網，只提醒不擋。
// 全部欄位 Optional＋decodeIfPresent（合成編碼，只認 CodingKeys：新欄位一定要在 CodingKeys 加，不然存不進去、也不會有編譯錯）。
// sim_v7.py 照這裡一行一行寫過、跑過（build/v7/sim_v7_output.txt）。

/// 號碼密文那一包（同步鍵 life_wealth_vault_v1；跟 iCloud 同步、進完整備份與「記帳理財」匯出——裡面只有密文）
struct WealthVaultBook: Codable, Equatable {
    /// key＝那筆財富里程碑（信用卡、保單）的 id.uuidString
    var entries: [String: WealthVaultEntry]?

    /// 同步鍵（CloudSyncManager.syncKeys、LifeStore.ownedKeys、save／load 都用這個字）
    static let syncKey = "life_wealth_vault_v1"

    init(entries: [String: WealthVaultEntry]? = nil) {
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try? c.decodeIfPresent([String: WealthVaultEntry].self, forKey: .entries)
    }

    private enum CodingKeys: String, CodingKey {
        case entries
    }

    var isEmpty: Bool { (entries ?? [:]).isEmpty }

    /// 有沒有任何一筆密文（CardVault 決定能不能產生新金鑰：LifeStore.hasAnyWealthCipher）
    var hasAnyCipher: Bool {
        (entries ?? [:]).values.contains { (e: WealthVaultEntry) -> Bool in !e.isEmpty }
    }

    /// 這一筆（沒有＝全部 nil）
    func entry(_ id: UUID) -> WealthVaultEntry {
        entries?[id.uuidString] ?? WealthVaultEntry()
    }

    /// 整筆換掉；空的就拿掉
    mutating func setEntry(_ e: WealthVaultEntry, for id: UUID) {
        var all = entries ?? [:]
        if e.isEmpty { all.removeValue(forKey: id.uuidString) } else { all[id.uuidString] = e }
        entries = all.isEmpty ? nil : all
    }

    /// 刪卡、刪保單時一起清（LifeStore.deleteFinanceMilestone）
    mutating func remove(_ id: UUID) {
        guard var all = entries else { return }
        all.removeValue(forKey: id.uuidString)
        entries = all.isEmpty ? nil : all
    }

    /// 合併匯入：本機有的留本機的、本機沒有的帶進來（同 WealthBook.merged）
    func merged(with other: WealthVaultBook) -> WealthVaultBook {
        var out = self
        var all = out.entries ?? [:]
        for (k, v) in other.entries ?? [:] where all[k] == nil { all[k] = v }
        out.entries = all.isEmpty ? nil : all
        return out
    }
}

/// 一筆財富里程碑的號碼密文（全部 CardVault.seal 出來的 AES-GCM combined；沒有＝nil）
struct WealthVaultEntry: Codable, Equatable {
    /// 有效期限（明碼「2027-03」：西曆年－月，WealthSecrets.expiryText）
    var expiryCipher: Data?
    /// 保單號碼（完整的；里程碑 policyNumber 只留後 4 碼）
    var policyCipher: Data?
    /// 悠遊卡、一卡通、Happy Go 卡號（完整的；里程碑那三欄只留後 4 碼）
    var easyCardCipher: Data?
    var iPassCipher: Data?
    var happyGoCipher: Data?

    init(expiryCipher: Data? = nil, policyCipher: Data? = nil, easyCardCipher: Data? = nil,
         iPassCipher: Data? = nil, happyGoCipher: Data? = nil) {
        self.expiryCipher = expiryCipher
        self.policyCipher = policyCipher
        self.easyCardCipher = easyCardCipher
        self.iPassCipher = iPassCipher
        self.happyGoCipher = happyGoCipher
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        expiryCipher = try? c.decodeIfPresent(Data.self, forKey: .expiryCipher)
        policyCipher = try? c.decodeIfPresent(Data.self, forKey: .policyCipher)
        easyCardCipher = try? c.decodeIfPresent(Data.self, forKey: .easyCardCipher)
        iPassCipher = try? c.decodeIfPresent(Data.self, forKey: .iPassCipher)
        happyGoCipher = try? c.decodeIfPresent(Data.self, forKey: .happyGoCipher)
    }

    private enum CodingKeys: String, CodingKey {
        case expiryCipher, policyCipher, easyCardCipher, iPassCipher, happyGoCipher
    }

    var isEmpty: Bool {
        expiryCipher == nil && policyCipher == nil && easyCardCipher == nil && iPassCipher == nil && happyGoCipher == nil
    }

    /// 這一種號碼的密文
    func cipher(_ f: WealthSecretField) -> Data? {
        switch f {
        case .expiry: return expiryCipher
        case .policy: return policyCipher
        case .easyCard: return easyCardCipher
        case .iPass: return iPassCipher
        case .happyGo: return happyGoCipher
        }
    }

    mutating func setCipher(_ d: Data?, for f: WealthSecretField) {
        switch f {
        case .expiry: expiryCipher = d
        case .policy: policyCipher = d
        case .easyCard: easyCardCipher = d
        case .iPass: iPassCipher = d
        case .happyGo: happyGoCipher = d
        }
    }

    /// 卡的票證號有沒有任何一個是密文（表單：有就鎖住，跟卡號同一顆 Face ID）
    var hasTicketCipher: Bool { easyCardCipher != nil || iPassCipher != nil || happyGoCipher != nil }
}

/// 這一包裡放的五種號碼（表單、卡片頁、搬家共用）
enum WealthSecretField: String, CaseIterable {
    case expiry, policy, easyCard, iPass, happyGo

    /// 信用卡綁的票證（照表單、卡片頁的順序）
    static let tickets: [WealthSecretField] = [.easyCard, .iPass, .happyGo]

    /// 說明、錯誤訊息裡的名字（CardVault.keyMissingMessage(what)）
    var title: String {
        switch self {
        case .expiry: return "有效期限"
        case .policy: return "保單號碼"
        case .easyCard: return "悠遊卡卡號"
        case .iPass: return "一卡通卡號"
        case .happyGo: return "Happy Go 卡號"
        }
    }
}

// MARK: - 號碼的規則（搬家、表單、卡片頁共用；sim_v7.py 一行一行照寫）

enum WealthSecrets {
    /// 號碼是不是完整的（要封成密文）：去掉前後空白超過 4 個字。4 個字以內＝本來就只是後 4 碼，照存明碼
    static func isFull(_ raw: String?) -> Bool {
        guard let t = trimmed(raw) else { return false }
        return t.count > 4
    }

    /// 里程碑上留的後 4 碼（同 CardVault.maskedTail 露出來的那 4 個字；網頁版 maskTail 同一條規則）
    static func tail(_ raw: String) -> String { CardVault.tail4(raw) }

    /// 帳本 accountLast4：只取半形數字的最後 4 個（同表單 WealthAccountForm.accountTail）；沒有數字＝nil
    static func digitsTail(_ raw: String) -> String? {
        let d = raw.filter { (ch: Character) -> Bool in ch.isASCII && ch.isNumber }
        return d.isEmpty ? nil : String(d.suffix(4))
    }

    /// 有效期限的明碼：西曆「2027-03」（只記到月；同 WealthCal.monthKey）
    static func expiryText(_ d: Date) -> String { WealthCal.monthKey(d) }

    /// 「2027-03」→ 那個月 1 號 00:00（WealthCal.calendar）；認不得 nil
    static func expiryDate(_ text: String) -> Date? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]), y > 1900, (1...12).contains(m) else {
            return nil
        }
        var c = DateComponents()
        c.year = y
        c.month = m
        c.day = 1
        return WealthCal.calendar.date(from: c)
    }

    /// 卡片頁〔顯示〕後的有效期限：「03/27」
    static func expiryDisplay(_ d: Date) -> String {
        let c = WealthCal.calendar.dateComponents([.year, .month], from: d)
        return String(format: "%02ld/%02ld", c.month ?? 0, (c.year ?? 0) % 100)
    }

    /// 里程碑上那一欄的明碼（保單號碼、三種票證；有效期限不是字串，回 nil）
    static func plainField(_ f: WealthSecretField, of m: LifeMilestone) -> String? {
        switch f {
        case .expiry: return nil
        case .policy: return m.policyNumber
        case .easyCard: return m.easyCardNumber
        case .iPass: return m.iPassNumber
        case .happyGo: return m.happyGoNumber
        }
    }

    static func setPlainField(_ f: WealthSecretField, _ v: String?, on m: inout LifeMilestone) {
        switch f {
        case .expiry: break
        case .policy: m.policyNumber = v
        case .easyCard: m.easyCardNumber = v
        case .iPass: m.iPassNumber = v
        case .happyGo: m.happyGoNumber = v
        }
    }

    /// 這筆財富里程碑還有沒有沒搬的明碼（完整帳號、有效期限、保單號碼、票證號）
    static func needsMigration(_ m: LifeMilestone) -> Bool {
        switch m.financeSubCategory {
        case .bank?, .securities?:
            return isFull(m.accountNumber)
        case .creditCard?:
            if m.expiryDate != nil { return true }
            return WealthSecretField.tickets.contains { (f: WealthSecretField) -> Bool in isFull(plainField(f, of: m)) }
        case .insurance?:
            return isFull(m.policyNumber)
        case nil:
            return false
        }
    }

    /// 搬完的一筆：里程碑（只留後 4 碼、有效期限清掉）、帳本的帳戶設定（完整帳號的密文）、密文那一包的這一筆
    struct Migrated {
        var milestone: LifeMilestone
        var prefs: WealthAccountPrefs
        var entry: WealthVaultEntry
    }

    /// 搬一筆。全部封得了才搬；有一個封不了（seal 回 nil：這台還沒同步到金鑰、鑰匙圈寫不進去）＝nil，整筆照舊、下次再搬。
    /// 沒有要搬的也是 nil。seal＝CardVault.seal（模擬時換成假的）。明碼一定比密文新（新版從不寫明碼）：已經有密文也照樣換掉
    static func migrate(_ m: LifeMilestone, prefs: WealthAccountPrefs, entry: WealthVaultEntry,
                        seal: (String) -> Data?) -> Migrated? {
        var out = Migrated(milestone: m, prefs: prefs, entry: entry)
        var did = false
        switch m.financeSubCategory {
        case .bank?, .securities?:
            guard let raw = trimmed(m.accountNumber), raw.count > 4 else { return nil }
            guard let c = seal(raw) else { return nil }
            out.prefs.accountNumberCipher = c
            if let d = digitsTail(raw) { out.prefs.accountLast4 = d }
            out.milestone.accountNumber = tail(raw)
            did = true
        case .creditCard?:
            if let e = m.expiryDate {
                guard let c = seal(expiryText(e)) else { return nil }
                out.entry.expiryCipher = c
                out.milestone.expiryDate = nil
                did = true
            }
            for f in WealthSecretField.tickets {
                guard let raw = trimmed(plainField(f, of: m)), raw.count > 4 else { continue }
                guard let c = seal(raw) else { return nil }
                out.entry.setCipher(c, for: f)
                setPlainField(f, tail(raw), on: &out.milestone)
                did = true
            }
        case .insurance?:
            guard let raw = trimmed(m.policyNumber), raw.count > 4 else { return nil }
            guard let c = seal(raw) else { return nil }
            out.entry.policyCipher = c
            out.milestone.policyNumber = tail(raw)
            did = true
        case nil:
            return nil
        }
        return did ? out : nil
    }

    // MARK: 看（卡片頁〔顯示〕、表單解鎖；Face ID 過了才叫，open＝CardVault.open）

    /// 有效期限：還沒搬的明碼（比密文新）→ 密文那一包。missingKey＝有密文但這台解不開（說明「金鑰不在這台」）
    static func expiry(milestone m: LifeMilestone, entry: WealthVaultEntry,
                       open: (Data) -> String?) -> (date: Date?, missingKey: Bool) {
        if let d = m.expiryDate { return (WealthCal.startOfMonth(d), false) }
        guard let c = entry.expiryCipher else { return (nil, false) }
        guard let t = open(c), let d = expiryDate(t) else { return (nil, true) }
        return (d, false)
    }

    /// 一個號碼要顯示的完整字（有效期限是「03/27」）。規則：
    /// • 里程碑那一欄是「有沒有」：空的＝沒有這個號碼（還沒更新的 iPad 清掉了，密文不算數）
    /// • 那一欄是完整的（還沒搬的明碼，比密文新）＝用它
    /// • 有密文：解得開、解出來的後 4 碼跟那一欄一樣才用密文（舊 iPad 把那一欄改成別的 4 碼以內的字，就以那一欄為準）；
    ///   解不開＝(nil, missingKey: true)
    /// • 沒有密文＝那一欄本來就只有 4 碼以內：照顯示
    static func reveal(_ f: WealthSecretField, milestone m: LifeMilestone, entry: WealthVaultEntry,
                       open: (Data) -> String?) -> (value: String?, missingKey: Bool) {
        if f == .expiry {
            let e = expiry(milestone: m, entry: entry, open: open)
            return (e.date.map { expiryDisplay($0) }, e.missingKey)
        }
        guard let shown = trimmed(plainField(f, of: m)) else { return (nil, false) }
        if shown.count > 4 { return (shown, false) }
        guard let c = entry.cipher(f) else { return (shown, false) }
        guard let full = open(c) else { return (nil, true) }
        return (tail(full) == tail(shown) ? full : shown, false)
    }

    /// 完整帳號（銀行、證券戶）：里程碑上還是完整的明碼（還沒搬）＝用它；帳本的密文解得開＝用它；
    /// 只有後 4 碼、沒有密文＝nil（〔顯示〕也只是同 4 個數字，卡片頁不給按鈕）；有密文解不開＝(nil, missingKey: true)
    static func revealAccount(milestone m: LifeMilestone, prefs: WealthAccountPrefs,
                              open: (Data) -> String?) -> (value: String?, missingKey: Bool) {
        if let s = trimmed(m.accountNumber), s.count > 4 { return (s, false) }
        guard let c = prefs.accountNumberCipher else { return (nil, false) }
        guard let full = open(c) else { return (nil, true) }
        return (full, false)
    }

    // MARK: 存（表單 WealthEditors.sealVault；一個號碼一個 plan）

    /// 表單存檔時一個號碼怎麼存
    enum SealPlan: Equatable {
        /// 封成密文；里程碑那一欄只留後 4 碼（tail）
        case sealed(Data, tail: String)
        /// 照存明碼：4 個字以內（本來就不是完整號碼）、或這台還沒同步到金鑰時原封不動的舊明碼（下次有金鑰自動搬）；nil＝清掉
        case plain(String?)
        /// 密文、里程碑那一欄都照原本的（解鎖了但這台解不開、你也沒重打）
        case keep
        /// 這台還沒同步到金鑰，你新打的這個存不了：整張表單擋下，跳 CardVault.keyMissingMessage(欄位名)，什麼都不改
        case blocked
        /// 鑰匙圈寫不進金鑰：整張表單擋下，跳加密失敗（寧可不存也不存明碼）
        case failed
    }

    /// typed：表單上這一欄現在的字（有效期限傳 expiryText，沒填傳 ""）；original：打開表單時里程碑那一欄的字
    /// （有效期限傳 expiryText(明碼的日期)；沒有 nil）；lost：解鎖了但這台解不開、欄位是空的；keyMissing＝CardVault.keyMissingHere
    static func sealPlan(typed: String, original: String?, lost: Bool, keyMissing: Bool,
                         seal: (String) -> Data?) -> SealPlan {
        guard let t = trimmed(typed) else { return lost ? .keep : .plain(nil) }
        guard t.count > 4 else { return .plain(t) }
        if keyMissing {
            return t == trimmed(original) ? .plain(t) : .blocked
        }
        guard let c = seal(t) else { return .failed }
        return .sealed(c, tail: tail(t))
    }

    /// 財富頁打開時說一次（LifeStore.wealthVaultNotice；judge §8 v7【待確認】、待決定 7）
    static let vaultNoticeTitle: String = "號碼改成加密存了"
    static let vaultNoticeMessage: String =
        "完整帳號、信用卡的有效期限、保單號碼、悠遊卡／一卡通／Happy Go 卡號，現在都跟卡號、安全碼一樣加密後才存，要看得先過 Face ID。"
        + "\n\n列表、選單、卡片上照樣露後 4 碼。家裡還沒更新的 iPad 只看得到後 4 碼、看不到有效期限，請把 iPad 也更新到 25.568 以上。"
        + "\n\n桌面網頁版改讀 App 算好的數字（跟這裡一樣），只露後 4 碼、沒有卡片到期日。"

    /// 去掉前後空白；空的＝nil
    static func trimmed(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}

// MARK: - 照片拍到完整卡號時提醒（judge §7.2、§8 v7：手機內建的 Vision 文字辨識，不上網；只提醒，不擋你存）

/// 一張像拍到完整卡號的照片（表單的提醒框用：.alert(_:isPresented:presenting:)）
struct WealthPhotoHit: Identifiable, Equatable {
    /// 照片檔名（LifeMilestone.photoURL(for:)）
    let name: String
    /// 那串數字的最後 4 碼
    let tail: String

    var id: String { name }

    static let title = "這張照片好像拍到完整卡號"

    var message: String {
        "照片裡有一串像卡號的數字（結尾 \(tail)）。照片不會加密：會跟著 iCloud 同步、放進完整備份。"
            + "建議刪掉這張，改拍沒有號碼的那一面，或把號碼遮起來再拍。"
    }
}

enum WealthPhotoScan {
    /// 數字之間可以夾的字（空白、各種連字號）；其他字元就斷開
    private static let separators: Set<Character> = [" ", "-", "‐", "–", "—", "－", "\u{00A0}"]
    /// 數字之間最多夾幾個分隔字
    private static let maxGap = 3

    /// 幾行字裡第一串像卡號的數字的最後 4 碼；沒有 nil（sim_v7.py card_number_tail 照寫）
    static func cardNumberTail(in lines: [String]) -> String? {
        for line in lines {
            for run in digitRuns(line) where isCardLike(run) {
                return String(run.suffix(4))
            }
        }
        return nil
    }

    /// 像卡號：剛好 16 位；15、17、18、19 位（美國運通、銀聯）要通過 Luhn 檢查。14 位以下（多半是銀行帳號、電話）、20 位以上（發票、訂單）不算
    static func isCardLike(_ digits: String) -> Bool {
        let n = digits.count
        if n == 16 { return true }
        guard (15...19).contains(n) else { return false }
        return luhn(digits)
    }

    /// 一行裡的每一串數字（數字之間最多夾 maxGap 個分隔字；全形數字換成半形）
    static func digitRuns(_ line: String) -> [String] {
        var runs: [String] = []
        var cur = ""
        var gap = 0
        for ch in line {
            if let d = asciiDigit(ch) {
                cur.append(d)
                gap = 0
            } else if separators.contains(ch), !cur.isEmpty, gap < maxGap {
                gap += 1
            } else {
                if !cur.isEmpty { runs.append(cur) }
                cur = ""
                gap = 0
            }
        }
        if !cur.isEmpty { runs.append(cur) }
        return runs
    }

    /// 半形 0–9 照用；全形０–９換成半形；其他（圈圈數字、其他文字的數字）不算
    private static func asciiDigit(_ ch: Character) -> Character? {
        let scalars = ch.unicodeScalars
        guard scalars.count == 1, let s = scalars.first else { return nil }
        let v = s.value
        if v >= 0x30 && v <= 0x39 { return ch }
        if v >= 0xFF10 && v <= 0xFF19, let u = Unicode.Scalar(v - 0xFF10 + 0x30) { return Character(u) }
        return nil
    }

    /// Luhn 檢查碼（信用卡號的最後一碼）
    static func luhn(_ digits: String) -> Bool {
        var sum = 0
        var double = false
        for ch in digits.reversed() {
            guard let v = ch.wholeNumberValue else { return false }
            var x = v
            if double {
                x *= 2
                if x > 9 { x -= 9 }
            }
            sum += x
            double.toggle()
        }
        return sum % 10 == 0
    }

    /// 讀一張照片上的字（背景執行緒、手機內建的 Vision，不上網）；讀不到、不是圖片＝空的
    static func recognizeLines(url: URL) async -> [String] {
        await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                // 數字不要被「改正」成字
                request.usesLanguageCorrection = false
                let handler = VNImageRequestHandler(url: url, options: [:])
                do {
                    try handler.perform([request])
                    let observations: [VNRecognizedTextObservation] = request.results ?? []
                    let lines: [String] = observations.compactMap { (o: VNRecognizedTextObservation) -> String? in
                        o.topCandidates(1).first?.string
                    }
                    cont.resume(returning: lines)
                } catch {
                    cont.resume(returning: [])
                }
            }
        }
    }

    /// 這幾張照片裡第一張像拍到完整卡號的；PDF 跳過；都沒有 nil。表單加了照片之後叫（.onChange(of: 照片)），在背景跑完再回主執行緒
    static func firstHit(_ photos: [(name: String, url: URL)]) async -> WealthPhotoHit? {
        for p in photos where p.url.pathExtension.lowercased() != "pdf" {
            let lines = await recognizeLines(url: p.url)
            if let t = cardNumberTail(in: lines) {
                return WealthPhotoHit(name: p.name, tail: t)
            }
        }
        return nil
    }
}
