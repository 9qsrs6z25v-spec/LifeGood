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

enum CardVault {

    // MARK: - 金鑰

    private static let service = "com.lifegood.cardvault"
    private static let account = "card.aeskey.v1"
    /// 解完一次就留著，避免每次顯示都去敲 Keychain
    private static var cachedKey: SymmetricKey?

    /// 取得（必要時產生）卡號加密金鑰。金鑰寫不進 Keychain 時回 nil——
    /// 此時寧可不存，也不要退而求其次存明碼。
    private static func key() -> SymmetricKey? {
        if let cachedKey { return cachedKey }
        if let data = readKeyData(), data.count == 32 {
            let k = SymmetricKey(data: data)
            cachedKey = k
            return k
        }
        let fresh = SymmetricKey(size: .bits256)
        let data = fresh.withUnsafeBytes { Data($0) }
        guard writeKeyData(data) else { return nil }
        cachedKey = fresh
        return fresh
    }

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
    static var hasKey: Bool { cachedKey != nil || readKeyData() != nil }

    // MARK: - 加解密

    /// 把明碼封成密文。空字串回 nil（等同「沒有這筆資料」）。
    static func seal(_ text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let key = key(),
              let plain = trimmed.data(using: .utf8),
              let box = try? AES.GCM.seal(plain, using: key) else { return nil }
        return box.combined
    }

    /// 解出明碼。金鑰不在這台裝置、或密文壞掉時回 nil。
    static func open(_ data: Data?) -> String? {
        guard let data,
              let key = key(),
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
                + "請到「設定 → Face ID 與密碼」設定後再試——沒有鎖的裝置，卡號存在哪裡都不安全。"
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
