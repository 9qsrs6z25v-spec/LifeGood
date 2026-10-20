import Foundation
import Security
import CryptoKit
import LocalAuthentication

// MARK: - 信用卡敏感欄位保管室（v25.368）
//
// 為什麼不直接把完整卡號存進 LifeMilestone 的一般欄位：
// 那個結構會整包序列化成 kv_life_milestones，跟著 iCloud 同步、寫進完整備份 JSON，
// 桌面唯讀網頁版登入後也會把整包讀進瀏覽器。完整卡號與檢核碼不該出現在那些地方。
//
// 所以這裡把「明碼」與「金鑰」拆開存：
//   - 密文（AES-GCM）存在 LifeMilestone 裡，跟著同步走，但沒有金鑰就只是亂碼。
//   - 金鑰存在 Keychain，設為可同步，走 iCloud 鑰匙圈的端對端加密，
//     不會進 App 的資料庫、不會進備份檔、網頁版也讀不到。
//     （與 AIKeychainStore 存 API Key 的做法同一套思路。）
//
// 要看明碼一定要先過 Face ID／Touch ID／裝置密碼。
//
// MARK: - [v25.568] 規矩（財富 v7；wealth/judge.md §7、build/v7/brief.md §1）—— 改這個檔、叫這個檔之前先讀
//
// 1. 一把金鑰：service／account 不變（com.lifegood.cardvault／card.aeskey.v1），可同步鑰匙圈（AfterFirstUnlock）。
//    卡號、安全碼、完整帳號、有效期限、保單號碼、票證號全部用這一把。
// 2. 只有「整份資料裡一筆密文都沒有」的時候，seal 才可以產生新金鑰（第一台裝置第一次存號碼）。
//    有密文、這台卻沒有金鑰＝在別台存的、iCloud 鑰匙圈還沒同步過來：這時產生新金鑰會蓋掉別台那把，別台存的號碼全部解不開。
//    所以 seal 會擋下（回 nil）；表單存新號碼前先看 keyMissingHere，擋下並說明「這台還沒同步到金鑰」（keyMissingMessage），
//    原本的密文原封留著——絕不因為這台解不開就洗掉別台的密文。「有沒有密文」由 LifeStore 告訴這裡（cipherProbe）。
// 3. open 永遠不產生金鑰（v3 以前會，v25.564 起畫面先看 hasKey 擋著；v7 起這裡本身就不會）。
// 4. 任何分享、匯出、CSV、小工具、鎖定畫面、通知、網頁版（life_wealth_facts_v1）都不准呼叫 open；
//    明碼只活在畫面的 @State 和記憶體（看完 30 秒收回），不寫進任何 Codable 結構、UserDefaults、log、錯誤回報。
//    例外只有一個：App 裡的行事曆「卡片到期」、要確認 #12、通知要知道有效期限是哪個月（judge §7.1 行事曆「只有卡片到期那天」）：
//    LifeStore.cardExpiryMonths 在這台有金鑰時解開、只取年月、只放記憶體。
// 5. 新的密文欄位只放兩種地方：舊版認得、存檔會照寫回去的欄位（LifeMilestone.cardNumberCipher／cardSecurityCipher、
//    財富帳本 accounts[id].accountNumberCipher），或舊版不認得、不會碰的同步鍵（WealthVaultBook，life_wealth_vault_v1）。
//    不要加在舊版認得的那一包的新欄位上：還沒更新的 iPad 存一次就把它洗掉，明碼又已經清了＝號碼永遠不見。
// 6. 完整備份、「記帳理財」匯出只帶密文（金鑰不在備份裡：換一台同一個 Apple ID 的裝置，鑰匙圈同步過來才解得開）。

enum CardVault {

    // MARK: - 金鑰

    private static let service = "com.lifegood.cardvault"
    private static let account = "card.aeskey.v1"
    /// 解完一次就留著，避免每次顯示都去敲 Keychain
    private static var cachedKey: SymmetricKey?

    /// [v25.568] 這台已經有的金鑰（快取或鑰匙圈；不是 32 位元組的當沒有）。**從不產生新的**（規矩 3）
    private static func existingKey() -> SymmetricKey? {
        if let cachedKey { return cachedKey }
        guard let data = readKeyData(), data.count == 32 else { return nil }
        let k = SymmetricKey(data: data)
        cachedKey = k
        return k
    }

    /// [v25.568] 封密文用的金鑰：這台有就用；沒有、而且整份資料裡一筆密文都沒有，才產生一把新的寫進可同步的鑰匙圈（規矩 2）。
    /// 有密文、這台沒有金鑰＝還沒同步過來：回 nil（不產生，免得蓋掉別台那把）。金鑰寫不進 Keychain 也回 nil——
    /// 此時寧可不存，也不要退而求其次存明碼。
    private static func keyForSealing() -> SymmetricKey? {
        if let k = existingKey() { return k }
        guard !anyCipherExists else { return nil }
        let fresh = SymmetricKey(size: .bits256)
        let data = fresh.withUnsafeBytes { Data($0) }
        guard writeKeyData(data) else { return nil }
        cachedKey = fresh
        return fresh
    }

    /// [v25.568] 整份資料裡有沒有任何號碼密文（LifeStore 在 init 一開始掛上：LifeStore.hasAnyWealthCipher）。
    /// 還沒掛上（理論上不會）一律當「有」：寧可擋下不存，也不要產生新金鑰蓋掉別台那把
    static var cipherProbe: (() -> Bool)? = nil

    private static var anyCipherExists: Bool { cipherProbe?() ?? true }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // 可同步：同一個 Apple ID 的其他裝置才解得開這台裝置加密的卡號
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any
        ]
    }

    private static func readKeyData() -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }

    private static func writeKeyData(_ data: Data) -> Bool {
        SecItemDelete(baseQuery() as CFDictionary)
        var add = baseQuery()
        add[kSecValueData as String] = data
        // 可同步的項目不能用 ...ThisDeviceOnly
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// 這台裝置上到底有沒有金鑰。沒有金鑰又有密文＝在別台裝置存的、這台解不開。
    /// [v25.568] 改看 existingKey（鑰匙圈裡那筆不是 32 位元組的也當沒有：以前會被 key() 當成沒有、產生新的蓋掉）
    static var hasKey: Bool { existingKey() != nil }

    /// [v25.568] 這台還沒同步到金鑰：有密文、這台沒有金鑰。這時 seal 一律回 nil（規矩 2）；
    /// 表單要存「你剛打的新號碼」前先看這個，擋下並跳 keyMissingMessage（舊的明碼原封不動照舊留著，不擋）
    static var keyMissingHere: Bool { !hasKey && anyCipherExists }

    /// [v25.568] 這台還沒同步到金鑰時，表單存新號碼的說明（what：「卡號」「完整帳號」「有效期限」「保單號碼」「悠遊卡卡號」…）
    static func keyMissingMessage(_ what: String) -> String {
        "這台還沒同步到金鑰，剛打的" + what + "這次存不了：在這台產生新的金鑰，會蓋掉另一台裝置的金鑰，"
            + "原本存的號碼就再也解不開了。請確認「設定 → Apple ID → iCloud → 密碼與鑰匙圈」已開啟，等一下再存；"
            + "或先把剛打的" + what + "清掉，其他的照樣可以存。原本存的號碼都還在。"
    }

    // MARK: - 加解密

    /// 把明碼封成密文。空字串回 nil（等同「沒有這筆資料」）。
    /// [v25.568] 這台還沒同步到金鑰（keyMissingHere）也回 nil，而且不產生新金鑰（規矩 2）：呼叫端先看 keyMissingHere 分清楚
    static func seal(_ text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let key = keyForSealing(),
              let plain = trimmed.data(using: .utf8),
              let box = try? AES.GCM.seal(plain, using: key) else { return nil }
        return box.combined
    }

    /// 解出明碼。金鑰不在這台裝置、或密文壞掉時回 nil。
    /// [v25.568] 只用這台已經有的金鑰，從不產生新的（規矩 3）。分享、匯出、小工具、網頁版不准叫（規矩 4）
    static func open(_ data: Data?) -> String? {
        guard let data,
              let key = existingKey(),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    // MARK: - 卡號格式

    /// 卡號最多幾碼：Visa／MasterCard／JCB 16 碼，美國運通 15 碼，部分銀聯 19 碼。
    /// 一律以 4 碼為一組顯示，不特別為運通做 4-6-5 的排法。
    static let maxDigits = 19

    /// 只留數字並截到上限
    static func digits(_ raw: String, limit: Int = maxDigits) -> String {
        String(raw.filter(\.isNumber).prefix(limit))
    }

    /// 一卡通卡號固定 16 碼（悠遊卡是 9～10 碼，不適用四碼分組，所以沒有比照辦理）
    static let iPassDigits = 16

    /// 每四碼插一個「-」：1234567812345678 → 1234-5678-1234-5678
    static func grouped(_ raw: String, limit: Int = maxDigits) -> String {
        let d = digits(raw, limit: limit)
        guard !d.isEmpty else { return "" }
        var out = ""
        for (i, ch) in d.enumerated() {
            if i > 0, i % 4 == 0 { out.append("-") }
            out.append(ch)
        }
        return out
    }

    static func lastFour(_ raw: String) -> String {
        String(digits(raw).suffix(4))
    }

    /// 既有資料是不是「只有數字、分隔線與空白」——是的話重新分組不會弄丟任何字元，
    /// 可以安全地正規化；含其他字元（使用者自己加的註記）就原樣保留，不要自作主張。
    static func isSafeToRegroup(_ raw: String) -> Bool {
        raw.allSatisfy { $0.isNumber || $0 == "-" || $0 == " " }
    }

    /// 卡號長度看起來合理才算填完（13～19 碼涵蓋所有常見發卡組織）
    static func isPlausible(_ raw: String) -> Bool {
        (13...maxDigits).contains(digits(raw).count)
    }

    /// 遮罩顯示：•••• •••• •••• 1234
    static func masked(lastFour: String) -> String {
        let tail = lastFour.isEmpty ? "••••" : lastFour
        return "•••• •••• •••• " + tail
    }

    /// [v25.562] 帳號、保單號碼、票證號碼畫面上只露後 4 碼：「•••• 5678」。
    /// 有數字就取最後 4 個數字（「2061-1234-5678-90」→「•••• 7890」）；一個數字都沒有就取最後 4 個字。
    /// [v25.568] 存法 v7 起改密文：完整的封在密文裡，里程碑上那一欄只留 tail4（舊 iPad、網頁版、這裡照讀）
    static func maskedTail(_ raw: String) -> String {
        "•••• " + tail4(raw)
    }

    /// [v25.568] 後 4 碼（maskedTail 的那 4 個字；網頁版 maskTail 同一條規則）：有數字取最後 4 個數字，沒有數字取最後 4 個字
    static func tail4(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let digitsOnly = trimmed.filter(\.isNumber)
        return digitsOnly.isEmpty ? String(trimmed.suffix(4)) : String(digitsOnly.suffix(4))
    }

    /// 檢核碼遮罩（3 碼；美國運通是 4 碼，一樣照長度出點）
    static func maskedCode(length: Int = 3) -> String {
        String(repeating: "•", count: max(3, length))
    }

    // MARK: - 解鎖

    enum UnlockResult: Equatable {
        case ok
        /// 使用者取消或驗證失敗
        case denied
        /// 這台裝置沒辦法驗證（例如完全沒設定裝置密碼），附說明
        case unavailable(String)
    }

    /// Face ID／Touch ID 驗證；沒有生物辨識或辨識失敗時，系統會自動退回裝置密碼。
    /// （用 .deviceOwnerAuthentication 而不是 ...WithBiometrics 就是為了這個退路。）
    static func unlock(reason: String) async -> UnlockResult {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "取消"
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable(
                "這台裝置沒有設定密碼或 Face ID，沒辦法驗證身分。"
                + "請到「設定 → Face ID 與密碼」設定後再試——沒有鎖的裝置，卡號、帳號存在哪裡都不安全。"
            )
        }
        let granted: Bool = await withCheckedContinuation { cont in
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
                cont.resume(returning: ok)
            }
        }
        return granted ? .ok : .denied
    }
}
