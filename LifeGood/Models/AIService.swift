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
你是記帳助手。從使用者的口語句子中抽取「變動支出」資訊，回傳純 JSON 物件（不要 markdown 圍欄、不要說明文字、不要任何前後綴）。

如果使用者句子前面附帶 [使用者目前位置：XXX] 標籤，請用這個位置去推斷講到的店名指的是哪一家分店、或推斷常見的店家慣用名稱（例如「鬍鬚張」在不同城市仍是同一品牌）。

欄位：
- amount (number)：金額，正整數或小數
- categoryRaw (string)：必須是這些之一：飲食、娛樂、購物、日用品、醫療、交通、教育、稅費、節稅、社交、汽車、股票、房地產、其他
- title (string)：店家名 / 項目名稱（簡短；若位置標籤可以幫助補完店家名稱，請補上區域）
- note (string)：備註細節，沒講則省略
- diningMember (string)：同行者，沒講則省略

範例輸入：[使用者目前位置：台北市信義區] 使用者說的話：今天午餐去鬍鬚張吃了 250
範例輸出：{"amount":250,"categoryRaw":"飲食","title":"鬍鬚張 信義店","note":"午餐"}

範例輸入：跟太太去看電影花了 600
範例輸出：{"amount":600,"categoryRaw":"娛樂","title":"電影","diningMember":"太太"}
"""

    func parse(_ text: String) async throws -> ParsedAIExpense {
        let settings = await AISettingsStore.shared
        guard let provider = await settings.activeProvider else { throw AIParseError.noProvider }
        let key = await settings.key(for: provider)
        guard !key.isEmpty else { throw AIParseError.noKey }

        // 取得使用者目前位置（reverse geocode 結果，5 分鐘 cache），讓 AI 判斷分店
        let locationContext = await LocationContextProvider.shared.currentContext()
        let prompt: String
        if let ctx = locationContext, !ctx.isEmpty {
            prompt = "[使用者目前位置：\(ctx)] 使用者說的話：\(text)"
        } else {
            prompt = text
        }

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
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
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
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
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
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(apiKey)")!
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
            cleaned = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        // 嘗試找 { ... } 區塊
        if let firstBrace = cleaned.firstIndex(of: "{"),
           let lastBrace = cleaned.lastIndex(of: "}") {
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
        p.categoryRaw = (json["categoryRaw"] as? String)?.trimmingCharacters(in: .whitespaces)
        p.title = (json["title"] as? String)?.trimmingCharacters(in: .whitespaces)
        p.note = (json["note"] as? String)?.trimmingCharacters(in: .whitespaces)
        p.diningMember = (json["diningMember"] as? String)?.trimmingCharacters(in: .whitespaces)
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
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in self.transcript = result.bestTranscription.formattedString }
            }
            if let error {
                Task { @MainActor in self.errorMessage = error.localizedDescription }
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
        // 先嘗試直接用 rawValue 對映（VariableCategory 的 rawValue 已是中文）
        if let direct = VariableCategory(rawValue: normalized) { return direct }
        // 同義詞表
        let table: [String: VariableCategory] = [
            "餐飲": .food, "吃飯": .food, "午餐": .food, "晚餐": .food, "早餐": .food,
            "娛樂": .entertainment, "休閒": .entertainment,
            "購物": .shopping,
            "日用品": .dailyNecessities, "日用": .dailyNecessities, "雜物": .dailyNecessities,
            "醫療": .medical, "看病": .medical, "藥": .medical,
            "交通": .transportation, "車費": .transportation, "油錢": .transportation,
            "教育": .education, "學費": .education, "書": .education,
            "稅費": .tax, "稅": .tax,
            "節稅": .taxSaving,
            "社交": .social, "禮金": .social,
            // 沒有獨立分類，回退到既有最相近項目
            "寵物": .other,
            "訂閱": .other,
            "汽車": .vehicle, "車輛": .vehicle,
            "股票": .stock,
            "房地產": .realEstate, "房屋": .realEstate,
            "其他": .other
        ]
        return table[normalized]
    }
}
