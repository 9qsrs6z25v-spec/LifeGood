import Foundation
import Security
import Speech
import AVFoundation
import SwiftUI
import CoreLocation

// MARK: - Keychain 儲存 API Key

/// 用 iOS Keychain 儲存第三方 AI 服務的 API Key（比 UserDefaults 安全）。
enum AIKeychainStore {
    @discardableResult
    static func set(_ value: String?, for key: String) -> Bool {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(baseQuery as CFDictionary)
        guard let value, !value.isEmpty,
              let data = value.data(using: .utf8) else { return true }
        var add = baseQuery
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}

// MARK: - AI 供應商

enum AIProvider: String, CaseIterable, Identifiable {
    case anthropic
    case openai
    case gemini

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic Claude"
        case .openai:    return "OpenAI ChatGPT"
        case .gemini:    return "Google Gemini"
        }
    }
    var icon: String {
        switch self {
        case .anthropic: return "sparkles"
        case .openai:    return "bubble.left.and.bubble.right.fill"
        case .gemini:    return "wand.and.stars"
        }
    }
    fileprivate var keychainKey: String { "LifeGood.ai.key.\(rawValue)" }
    var consoleURL: String {
        switch self {
        case .anthropic: return "https://console.anthropic.com/"
        case .openai:    return "https://platform.openai.com/api-keys"
        case .gemini:    return "https://aistudio.google.com/app/apikey"
        }
    }
    var helpText: String {
        switch self {
        case .anthropic:
            return "到 console.anthropic.com 開帳號 → API Keys → 生 sk-ant- 開頭的 key。需自行儲值，記帳每次解析約 0.003 USD（1000 筆約 3 USD）。"
        case .openai:
            return "到 platform.openai.com/api-keys 生 sk- 開頭的 key。需自行儲值，使用 gpt-4o-mini 每次解析約 0.0005 USD（1000 筆約 0.5 USD）。"
        case .gemini:
            return "到 aistudio.google.com 取得 key（AIza 開頭）。Free tier 每分鐘 15 次請求免費，個人使用通常足夠。"
        }
    }
}

// MARK: - 設定 Store

@MainActor
final class AISettingsStore: ObservableObject {
    static let shared = AISettingsStore()

    @Published var activeProvider: AIProvider? {
        didSet {
            UserDefaults.standard.set(activeProvider?.rawValue ?? "", forKey: "LifeGood.ai.activeProvider")
        }
    }
    /// 觸發 view 重新讀 keychain 用
    @Published private(set) var keyChangeStamp: Int = 0

    private init() {
        let raw = UserDefaults.standard.string(forKey: "LifeGood.ai.activeProvider") ?? ""
        self.activeProvider = AIProvider(rawValue: raw)
    }

    func key(for p: AIProvider) -> String {
        _ = keyChangeStamp
        return AIKeychainStore.get(p.keychainKey) ?? ""
    }

    func setKey(_ value: String, for p: AIProvider) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        AIKeychainStore.set(trimmed, for: p.keychainKey)
        keyChangeStamp += 1
    }

    /// 是否有任何 provider 已設定 key
    var hasAnyKey: Bool {
        AIProvider.allCases.contains { !key(for: $0).isEmpty }
    }

    /// 當前 active provider 是否可用（有 key）
    var isReady: Bool {
        guard let p = activeProvider else { return false }
        return !key(for: p).isEmpty
    }
}

// MARK: - 解析結果

struct ParsedAIExpense {
    var amount: Double?
    /// 從 AI 拿到的中文分類字串（飲食 / 娛樂 / 購物…）
    var categoryRaw: String?
    var title: String?
    var note: String?
    var diningMember: String?
    /// AI 從帳戶清單挑出的扣款帳戶顯示名稱（呼叫端用此字串對回 LifeMilestone）
    var paymentAccount: String?
    /// AI 從房地產清單挑出的物件顯示名稱（呼叫端對回 RealEstate UUID）
    var realEstate: String?
    /// 房地產變動支出子分類（房屋價金 / 裝修 / 維修 / 家具 / 清潔 / 水電瓦斯 / 稅費 / 保險 / 其他）
    var realEstateSubCategory: String?
    /// 原始辨識到的語音文字（保底放到備註用）
    var originalText: String?
}

enum AIParseError: LocalizedError {
    case noProvider
    case noKey
    case network(String)
    case http(Int, String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .noProvider:                return "尚未選擇 AI 供應商"
        case .noKey:                     return "尚未設定 API Key"
        case .network(let s):            return "網路錯誤：\(s)"
        case .http(let code, let msg):
            let snippet = msg.prefix(160)
            return "API 錯誤 (\(code))：\(snippet)"
        case .invalidResponse(let s):
            let snippet = s.prefix(160)
            return "回應格式錯誤：\(snippet)"
        }
    }
}

// MARK: - 解析服務（送 prompt + 解 JSON）

final class AIExpenseParserService {
    static let shared = AIExpenseParserService()

    private let systemPrompt = """
你是記帳助手。從使用者的口語句子中抽取「變動支出」資訊，**只回傳一個純 JSON 物件**，不要 markdown 圍欄、不要說明文字、不要任何前後綴。

如果使用者句子前面附帶 [使用者目前位置：XXX] 標籤，請用這個位置去推斷講到的店名指的是哪一家分店、或推斷常見的店家慣用名稱（例如「鬍鬚張」在不同城市仍是同一品牌）。

如果句子前面附帶 [可選同行者名稱：A、B、C] 標籤，diningMember 必須從這個清單中挑出最匹配的人名。比對規則：
- 句子裡出現「跟我太太」「和老婆」「跟太太」→ 在清單中找「太太」「老婆」「妻」字樣或對應的人名
- 「跟兒子」「跟我兒子」「帶兒子」→ 找清單中的兒子姓名
- 「跟爸爸 / 媽媽」→ 找清單中的父母
- 「跟同事 / 朋友」→ 沒有對應的家人姓名時，照原始字串填入
- 多人時用「、」分隔
- 完全無法對應就回原始字串（如「跟客戶」）

如果句子前面附帶 [可選信用卡：A、B、C] 或 [可選銀行帳戶：X、Y、Z] 標籤，請依下列規則決定 paymentAccount：
- 句子明確提到「刷卡」「刷 XX 卡」「用 XX 卡」「信用卡付」→ 從信用卡清單挑出最相近的整段字串，原樣回填到 paymentAccount
- 句子明確提到「用現金」「現金付」→ 不要填 paymentAccount
- 句子明確提到「從 XX 銀行扣」「XX 戶頭付」「轉帳」「匯款」「Apple Pay 直接扣銀行」→ 從銀行清單挑出最相近的整段字串，原樣回填
- 沒提到付款方式就不要填 paymentAccount
- 比對銀行 / 卡片名稱時忽略「銀行」「商業銀行」「股份有限公司」「信用卡」等通用詞，重點比對品牌字（玉山、國泰、中信、台新…）與末四碼
- paymentAccount 一定要與清單中的某一項完全相同，不要自己改寫

如果句子前面附帶 [可選房地產：A、B、C] 標籤，請依下列規則決定 realEstate 與 realEstateSubCategory：
- 句子提到房子的別名、地址關鍵字（信義店、新店、老家、出租屋…），或「我家／我的房子／房屋／物件／租屋處／管理費／房貸／房屋稅／地價稅／房屋保險」等與不動產有關的詞 → 從清單挑出最相近的整段字串原樣回填到 realEstate
- 沒有清單或完全沒提到房子就不要填 realEstate
- 一旦判斷有房地產關聯，請把 categoryRaw 設為「房地產」
- realEstateSubCategory 必須從這個清單擇一：房屋價金、裝修、維修、家具、清潔、水電瓦斯、稅費、保險、其他
  · 「裝潢／重新粉刷／木工／系統櫃」→ 裝修
  · 「修水管／換馬桶／抓漏」→ 維修
  · 「沙發／床／桌椅／冰箱／冷氣」→ 家具
  · 「打掃／清潔費／除蟲」→ 清潔
  · 「水費／電費／瓦斯／管理費」→ 水電瓦斯
  · 「房屋稅／地價稅／土增稅」→ 稅費
  · 「火險／地震險／房屋保險」→ 保險
  · 「頭期款／自備款／房屋價金」→ 房屋價金
  · 其他不確定的 → 其他

**必填欄位**（請務必每次回傳）：
- amount (number)：金額
- categoryRaw (string)：**必須**從這個清單擇一回傳，**不要回傳清單外的詞**：
  飲食、娛樂、購物、日用品、醫療、交通、教育、稅費、節稅、社交、汽車、股票、房地產、其他

**選填欄位**（有提到就一定要填）：
- title (string)：店家名 / 項目名稱（簡短；若位置標籤可以幫助補完，請補上區域，例如「鬍鬚張 信義店」）
- note (string)：備註細節
- paymentAccount (string)：扣款帳戶。**必須**從 [可選信用卡] 或 [可選銀行帳戶] 清單中原樣挑一個，沒有對應就不要填
- realEstate (string)：房地產物件。**必須**從 [可選房地產] 清單中原樣挑一個，沒提到房子就不要填
- realEstateSubCategory (string)：房地產支出子分類（房屋價金 / 裝修 / 維修 / 家具 / 清潔 / 水電瓦斯 / 稅費 / 保險 / 其他）；有設 realEstate 就要一併設這個
- diningMember (string)：同行者姓名 / 稱謂。判斷規則：
  · 句子裡只要出現「跟」「和」「同」「與」「陪」「帶」後接一個指人的詞，就要抽出
  · 常見指人詞：太太、老婆、先生、老公、女友、男友、女朋友、男朋友、家人、爸媽、爸爸、媽媽、孩子、兒子、女兒、小孩、朋友、同事、同學、客戶、廠商、長官、老闆、家裡人、家人們
  · 多人時用「、」分隔（例：「太太、兒子」）

**分類判斷示例**：
- 早午晚餐 / 餐廳 / 便當 / 飲料 / 咖啡 / 火鍋 / 燒烤 → 飲食
- 電影 / KTV / 演唱會 / 健身房 / 遊戲 / 書 / 玩具 → 娛樂
- 衣服 / 鞋子 / 包包 / 化妝品 / 3C → 購物
- 衛生紙 / 洗衣精 / 牙膏 / 廚房用品 → 日用品
- 看醫生 / 藥局 / 健檢 → 醫療
- 計程車 / 公車 / 高鐵 / 加油 / 停車 → 交通
- 學費 / 補習 / 課程 / 線上課 → 教育
- 報稅 / 牌照稅 / 房屋稅 → 稅費
- 捐款 / 結婚禮金 / 喪禮白包 → 社交

**範例輸入 1**：[使用者目前位置：台北市信義區] 使用者說的話：今天中午去鬍鬚張吃了 250
**範例輸出 1**：{"amount":250,"categoryRaw":"飲食","title":"鬍鬚張 信義店","note":"午餐"}

**範例輸入 2**：跟太太去看電影花了 600
**範例輸出 2**：{"amount":600,"categoryRaw":"娛樂","title":"電影","diningMember":"太太"}

**範例輸入 3**：剛剛叫了 uber 從家裡到公司花 350
**範例輸出 3**：{"amount":350,"categoryRaw":"交通","title":"Uber","note":"家裡到公司"}

**範例輸入 4**：和女兒在家樂福買了 1280 的日用品
**範例輸出 4**：{"amount":1280,"categoryRaw":"日用品","title":"家樂福","diningMember":"女兒"}

**範例輸入 5**：[可選信用卡：玉山 Pi 卡 末1234、國泰 Cube 卡 末5678] [可選銀行帳戶：玉山銀行、國泰世華銀行] 刷玉山卡買了 380 的咖啡
**範例輸出 5**：{"amount":380,"categoryRaw":"飲食","title":"咖啡","paymentAccount":"玉山 Pi 卡 末1234"}

**範例輸入 6**：[可選銀行帳戶：玉山銀行、國泰世華銀行] 從國泰扣 1500 給管理費
**範例輸出 6**：{"amount":1500,"categoryRaw":"其他","title":"管理費","paymentAccount":"國泰世華銀行"}

**範例輸入 7**：[可選房地產：信義小套房、新店透天] 幫信義那間房子繳了 3500 管理費
**範例輸出 7**：{"amount":3500,"categoryRaw":"房地產","title":"管理費","realEstate":"信義小套房","realEstateSubCategory":"水電瓦斯"}

**範例輸入 8**：[可選房地產：信義小套房] 房屋稅繳了 12000
**範例輸出 8**：{"amount":12000,"categoryRaw":"房地產","title":"房屋稅","realEstate":"信義小套房","realEstateSubCategory":"稅費"}
"""

    func parse(
        _ text: String,
        availableMembers: [String] = [],
        availableCreditCards: [String] = [],
        availableBankAccounts: [String] = [],
        availableRealEstates: [String] = []
    ) async throws -> ParsedAIExpense {
        let settings = await AISettingsStore.shared
        guard let provider = await settings.activeProvider else { throw AIParseError.noProvider }
        let key = await settings.key(for: provider)
        guard !key.isEmpty else { throw AIParseError.noKey }

        // 取得使用者目前位置（reverse geocode 結果，5 分鐘 cache），讓 AI 判斷分店
        let locationContext = await LocationContextProvider.shared.currentContext()
        var contextParts: [String] = []
        if let ctx = locationContext, !ctx.isEmpty {
            contextParts.append("[使用者目前位置：\(ctx)]")
        }
        if !availableMembers.isEmpty {
            let list = availableMembers.joined(separator: "、")
            contextParts.append("[可選同行者名稱：\(list)]")
        }
        if !availableCreditCards.isEmpty {
            let list = availableCreditCards.joined(separator: "、")
            contextParts.append("[可選信用卡：\(list)]")
        }
        if !availableBankAccounts.isEmpty {
            let list = availableBankAccounts.joined(separator: "、")
            contextParts.append("[可選銀行帳戶：\(list)]")
        }
        if !availableRealEstates.isEmpty {
            let list = availableRealEstates.joined(separator: "、")
            contextParts.append("[可選房地產：\(list)]")
        }
        let prompt = contextParts.isEmpty
            ? text
            : "\(contextParts.joined()) 使用者說的話：\(text)"

        let raw: String
        switch provider {
        case .anthropic: raw = try await callAnthropic(prompt: prompt, apiKey: key)
        case .openai:    raw = try await callOpenAI(prompt: prompt, apiKey: key)
        case .gemini:    raw = try await callGemini(prompt: prompt, apiKey: key)
        }
        var result = try decodeJSON(raw)
        result.originalText = text
        return result
    }

    // MARK: Anthropic

    private func callAnthropic(prompt: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIParseError.invalidResponse("internal: malformed Anthropic URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 400,
            "system": systemPrompt,
            "messages": [["role": "user", "content": prompt]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await sendRequest(req)
        try ensureOK(data: data, resp: resp)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let block = content.first(where: { ($0["type"] as? String) == "text" }),
              let textOut = block["text"] as? String else {
            throw AIParseError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return textOut
    }

    // MARK: OpenAI

    private func callOpenAI(prompt: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AIParseError.invalidResponse("internal: malformed OpenAI URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "response_format": ["type": "json_object"],
            "max_tokens": 400
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await sendRequest(req)
        try ensureOK(data: data, resp: resp)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIParseError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return content
    }

    // MARK: Gemini

    private func callGemini(prompt: String, apiKey: String) async throws -> String {
        guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent") else {
            throw AIParseError.network("malformed Gemini base URL")
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw AIParseError.network("Invalid Gemini API key")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "maxOutputTokens": 400
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await sendRequest(req)
        try ensureOK(data: data, resp: resp)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let textOut = parts.first?["text"] as? String else {
            throw AIParseError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return textOut
    }

    // MARK: 共用

    private func sendRequest(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: req)
        } catch {
            throw AIParseError.network(error.localizedDescription)
        }
    }

    private func ensureOK(data: Data, resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw AIParseError.invalidResponse("無 HTTP 回應")
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw AIParseError.http(http.statusCode, msg)
        }
    }

    private func decodeJSON(_ raw: String) throws -> ParsedAIExpense {
        // 移除 markdown fence
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            let lines = cleaned.split(separator: "\n", omittingEmptySubsequences: false)
            let inner = lines.dropFirst()
            cleaned = (inner.last?.hasPrefix("```") == true ? inner.dropLast() : inner)
                .joined(separator: "\n")
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        // 嘗試找 { ... } 區塊；firstBrace 必須 <= lastBrace，否則逆向 range 會 crash
        if let firstBrace = cleaned.firstIndex(of: "{"),
           let lastBrace = cleaned.lastIndex(of: "}"),
           firstBrace <= lastBrace {
            cleaned = String(cleaned[firstBrace...lastBrace])
        }
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIParseError.invalidResponse(raw)
        }
        var p = ParsedAIExpense()
        if let n = json["amount"] as? Double { p.amount = n }
        else if let n = json["amount"] as? Int { p.amount = Double(n) }
        else if let s = json["amount"] as? String { p.amount = Double(s) }
        // categoryRaw / category 兩種命名都接受
        p.categoryRaw = ((json["categoryRaw"] as? String)
                         ?? (json["category"] as? String))?
                         .trimmingCharacters(in: .whitespaces)
        // title / name / item 都接受
        p.title = ((json["title"] as? String)
                   ?? (json["name"] as? String)
                   ?? (json["item"] as? String))?
                   .trimmingCharacters(in: .whitespaces)
        p.note = ((json["note"] as? String)
                  ?? (json["notes"] as? String)
                  ?? (json["description"] as? String))?
                  .trimmingCharacters(in: .whitespaces)
        // 同行者：可能字串或陣列，欄位命名也常變
        if let s = json["diningMember"] as? String {
            p.diningMember = s.trimmingCharacters(in: .whitespaces)
        } else if let arr = json["diningMembers"] as? [String] {
            p.diningMember = arr.joined(separator: "、")
        } else if let s = json["with"] as? String {
            p.diningMember = s.trimmingCharacters(in: .whitespaces)
        } else if let arr = json["with"] as? [String] {
            p.diningMember = arr.joined(separator: "、")
        } else if let s = json["companion"] as? String {
            p.diningMember = s.trimmingCharacters(in: .whitespaces)
        } else if let arr = json["companions"] as? [String] {
            p.diningMember = arr.joined(separator: "、")
        } else if let s = json["person"] as? String {
            p.diningMember = s.trimmingCharacters(in: .whitespaces)
        } else if let arr = json["people"] as? [String] {
            p.diningMember = arr.joined(separator: "、")
        }
        if let m = p.diningMember, m.isEmpty { p.diningMember = nil }
        if let acc = (json["paymentAccount"] as? String)
            ?? (json["account"] as? String)
            ?? (json["paymentMethod"] as? String) {
            let trimmed = acc.trimmingCharacters(in: .whitespaces)
            p.paymentAccount = trimmed.isEmpty ? nil : trimmed
        }
        if let re = (json["realEstate"] as? String)
            ?? (json["property"] as? String) {
            let trimmed = re.trimmingCharacters(in: .whitespaces)
            p.realEstate = trimmed.isEmpty ? nil : trimmed
        }
        if let sub = (json["realEstateSubCategory"] as? String)
            ?? (json["realEstateCategory"] as? String) {
            let trimmed = sub.trimmingCharacters(in: .whitespaces)
            p.realEstateSubCategory = trimmed.isEmpty ? nil : trimmed
        }
        return p
    }
}

// MARK: - 語音辨識

@MainActor
final class SpeechRecognizer: NSObject, ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// 請求語音辨識 + 麥克風權限
    func requestAccess() async -> Bool {
        let speechGranted: Bool = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechGranted else { return false }
        let micGranted: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        return micGranted
    }

    func startRecording() throws {
        // 已在錄音中 → 直接略過，避免重複呼叫把 transcript 清空、重裝 audio tap
        if isRecording { return }
        // recognizer 為 nil 表示此裝置不支援 zh-TW 語音辨識；提前中止，
        // 避免音訊 session 啟動後麥克風佔用（及狀態列圖示）卻沒有實際轉錄。
        guard recognizer != nil else {
            errorMessage = "此裝置不支援中文語音辨識"
            return
        }
        transcript = ""
        errorMessage = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            req.addsPunctuation = false
        }
        request = req

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [req] buffer, _ in
            // 直接捕捉 req 物件，避免從音訊執行緒存取 @MainActor 隔離的 self.request 屬性
            req.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            // 先在背景執行緒提取值型別，避免對 @MainActor 隔離的 self 建立強引用
            let text = result?.bestTranscription.formattedString
            let errMsg = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text { self.transcript = text }
                if let errMsg { self.errorMessage = errMsg }
            }
        }
        isRecording = true
    }

    func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
    }
}

// MARK: - 位置 context（reverse geocode 給 AI 判斷店家分店用）

@MainActor
final class LocationContextProvider {
    static let shared = LocationContextProvider()

    private var cached: String?
    private var cachedAt: Date?

    /// 把 LocationProvider 提供的座標 reverse geocode 成「縣市 + 區」字串。
    /// 5 分鐘內回傳 cache，避免每次都打 CLGeocoder。
    /// 若沒有位置 / 權限被拒，回傳 nil。
    func currentContext() async -> String? {
        // 先觸發授權（若還沒）
        LocationProvider.shared.requestIfNeeded()

        if let cached, let cachedAt, Date().timeIntervalSince(cachedAt) < 300 {
            return cached
        }
        guard let loc = LocationProvider.shared.lastLocation else { return nil }

        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(loc)
            guard let p = placemarks.first else { return nil }
            var parts: [String] = []
            if let admin = p.administrativeArea, !admin.isEmpty {
                parts.append(admin)
            }
            if let sub = p.subAdministrativeArea, !sub.isEmpty, sub != p.administrativeArea {
                parts.append(sub)
            }
            if let locality = p.locality, !locality.isEmpty, !parts.contains(locality) {
                parts.append(locality)
            }
            if let subLocality = p.subLocality, !subLocality.isEmpty, !parts.contains(subLocality) {
                parts.append(subLocality)
            }
            let str = parts.joined()
            cached = str.isEmpty ? nil : str
            cachedAt = Date()
            return cached
        } catch {
            return nil
        }
    }
}

// MARK: - 中文分類字串 → VariableCategory

enum AIVariableCategoryMapper {
    /// 把 AI 給的中文分類字串映射到 app 的 VariableCategory。沒對到回 nil。
    static func map(_ raw: String?) -> VariableCategory? {
        guard let raw, !raw.isEmpty else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespaces)
        // 1) 直接用 rawValue 對映（VariableCategory 的 rawValue 已是中文）
        if let direct = VariableCategory(rawValue: normalized) { return direct }

        // 2) 中文 / 英文同義詞表（混在一起，含 lowercase 英文）
        let table: [String: VariableCategory] = [
            // 飲食
            "餐飲": .food, "吃飯": .food, "午餐": .food, "晚餐": .food, "早餐": .food,
            "宵夜": .food, "下午茶": .food, "點心": .food, "飲料": .food, "咖啡": .food,
            "food": .food, "dining": .food, "meal": .food, "restaurant": .food, "drink": .food,
            // 娛樂
            "娛樂": .entertainment, "休閒": .entertainment, "電影": .entertainment, "遊戲": .entertainment,
            "entertainment": .entertainment, "fun": .entertainment, "leisure": .entertainment, "movie": .entertainment,
            // 購物
            "購物": .shopping, "服飾": .shopping, "衣服": .shopping,
            "shopping": .shopping, "clothing": .shopping, "apparel": .shopping,
            // 日用品
            "日用品": .dailyNecessities, "日用": .dailyNecessities, "雜物": .dailyNecessities,
            "家用": .dailyNecessities, "生活用品": .dailyNecessities,
            "daily": .dailyNecessities, "necessities": .dailyNecessities, "household": .dailyNecessities,
            // 醫療
            "醫療": .medical, "看病": .medical, "藥": .medical, "藥品": .medical, "醫藥": .medical, "健保": .medical,
            "medical": .medical, "health": .medical, "doctor": .medical, "pharmacy": .medical,
            // 交通
            "交通": .transportation, "車費": .transportation, "油錢": .transportation, "停車": .transportation,
            "捷運": .transportation, "公車": .transportation, "高鐵": .transportation, "計程車": .transportation,
            "transport": .transportation, "transportation": .transportation, "travel": .transportation,
            "uber": .transportation, "taxi": .transportation, "gas": .transportation,
            // 教育
            "教育": .education, "學費": .education, "書": .education, "補習": .education, "課程": .education,
            "education": .education, "learning": .education, "course": .education, "tuition": .education, "book": .education,
            // 稅
            "稅費": .tax, "稅": .tax, "報稅": .tax,
            "tax": .tax, "taxes": .tax,
            // 節稅
            "節稅": .taxSaving,
            "taxsaving": .taxSaving, "tax-saving": .taxSaving, "tax saving": .taxSaving,
            // 社交
            "社交": .social, "禮金": .social, "紅包": .social, "白包": .social, "送禮": .social,
            "social": .social, "gift": .social, "donation": .social,
            // 沒有獨立分類，回退到既有最相近項目
            "寵物": .other, "pet": .other,
            "訂閱": .other, "subscription": .other,
            // 汽車（與交通區分，這指買車或養車項目）
            "汽車": .vehicle, "車輛": .vehicle,
            "vehicle": .vehicle, "car": .vehicle, "auto": .vehicle,
            // 股票
            "股票": .stock, "投資": .stock,
            "stock": .stock, "stocks": .stock, "investment": .stock,
            // 房地產
            "房地產": .realEstate, "房屋": .realEstate, "房子": .realEstate,
            "realestate": .realEstate, "real estate": .realEstate, "property": .realEstate, "house": .realEstate,
            // 其他
            "其他": .other,
            "other": .other, "misc": .other, "miscellaneous": .other
        ]

        // 3) 大小寫不敏感對映
        if let direct = table[normalized] { return direct }
        let lower = normalized.lowercased()
        if let lc = table[lower] { return lc }

        // 4) 部分包含（AI 可能回傳「飲食/餐飲」這樣的複合字）
        for (key, value) in table {
            if normalized.contains(key) || lower.contains(key) { return value }
        }
        return nil
    }
}
