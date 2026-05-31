import Foundation

// MARK: - 錯誤

enum EInvoiceError: LocalizedError {
    case missingAppID
    case missingCarrier
    case invalidResponse
    case apiError(code: Int, message: String)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .missingAppID:    return "尚未設定 appID。請至 https://www.einvoice.nat.gov.tw/ESCAPI/ 申請後填入。"
        case .missingCarrier:  return "尚未設定手機條碼或驗證碼。"
        case .invalidResponse: return "API 回應格式錯誤。"
        case .apiError(let c, let m): return "API 錯誤（\(c)）：\(m)"
        case .network(let e):  return "網路錯誤：\(e.localizedDescription)"
        }
    }
}

// MARK: - 客戶端

/// 財政部電子發票 B2C 載具 API 客戶端。
///
/// 重要：使用前需先至 https://www.einvoice.nat.gov.tw/ESCAPI/ 申請 appID，
/// 並把字串填入下方 `EInvoiceClient.appID`。
final class EInvoiceClient {

    /// ⚠️ 申請後填入此處（個人/公司皆可申請，免費）。
    static var appID: String = ""

    /// API 入口
    private let endpoint = URL(string: "https://api.einvoice.nat.gov.tw/PB2CAPIVAN/invServ/InvServ")!

    /// 裝置識別（一次產生後固定）
    private let deviceUUID: String = {
        if let saved = UserDefaults.standard.string(forKey: "einvoice_device_uuid") {
            return saved
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: "einvoice_device_uuid")
        return new
    }()

    private let session: URLSession = .shared

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.dateFormat = "yyyy/MM/dd"
        return f
    }()

    private static let twDateParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.dateFormat = "yyyy/MM/dd"
        return f
    }()

    // MARK: - 公開方法

    /// 查詢載具發票標頭（指定日期範圍）
    func fetchHeaders(carrier: EInvoiceCarrier, from start: Date, to end: Date) async throws -> [EInvoiceHeader] {
        try ensureConfigured(carrier: carrier)

        let body = baseFields(carrier: carrier, action: "carrierInvChk").merging([
            "startDate": Self.dateFormatter.string(from: start),
            "endDate": Self.dateFormatter.string(from: end),
            "onlyWinningInv": "N",
        ]) { $1 }

        let json = try await postForm(body)
        try checkAPISuccess(json)

        let detailsRaw = json["details"] as? [[String: Any]] ?? []
        return detailsRaw.compactMap(parseHeader(_:))
    }

    /// 查詢單張發票明細
    func fetchDetail(carrier: EInvoiceCarrier, header: EInvoiceHeader) async throws -> [EInvoiceItem] {
        try ensureConfigured(carrier: carrier)

        let body = baseFields(carrier: carrier, action: "qryInvDetail").merging([
            "invNum": header.invNum,
            "invDate": Self.dateFormatter.string(from: header.invDate),
            "sellerName": header.sellerName,
            "amount": String(format: "%.0f", header.amount),
        ]) { $1 }

        let json = try await postForm(body)
        try checkAPISuccess(json)

        let detailsRaw = json["details"] as? [[String: Any]] ?? []
        return detailsRaw.enumerated().compactMap { idx, raw in
            let row = (raw["rowNum"] as? Int) ?? Int((raw["rowNum"] as? String) ?? "") ?? (idx + 1)
            let desc = (raw["description"] as? String) ?? ""
            let qty = parseDouble(raw["quantity"]) ?? 1
            let unit = parseDouble(raw["unitPrice"]) ?? 0
            let amount = parseDouble(raw["amount"]) ?? 0
            return EInvoiceItem(invNum: header.invNum, rowNum: row,
                                description: desc, quantity: qty,
                                unitPrice: unit, amount: amount)
        }
    }

    // MARK: - 內部

    private func ensureConfigured(carrier: EInvoiceCarrier) throws {
        if Self.appID.isEmpty { throw EInvoiceError.missingAppID }
        if carrier.cardNo.isEmpty || carrier.cardEncrypt.isEmpty {
            throw EInvoiceError.missingCarrier
        }
    }

    private func baseFields(carrier: EInvoiceCarrier, action: String) -> [String: String] {
        [
            "version": "0.5",
            "cardType": EInvoiceCarrier.cardType,
            "cardNo": carrier.cardNo,
            "expTimeStamp": "2147483647",
            "action": action,
            "timeStamp": String(Int(Date().timeIntervalSince1970)),
            "uuid": deviceUUID,
            "appID": Self.appID,
            "cardEncrypt": carrier.cardEncrypt,
        ]
    }

    private func postForm(_ fields: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8",
                     forHTTPHeaderField: "Content-Type")
        req.setValue("LifeGood/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        req.httpBody = encodeForm(fields)

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw EInvoiceError.invalidResponse
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw EInvoiceError.invalidResponse
            }
            return json
        } catch let e as EInvoiceError {
            throw e
        } catch {
            throw EInvoiceError.network(error)
        }
    }

    private func encodeForm(_ fields: [String: String]) -> Data {
        let allowed: CharacterSet = {
            var s = CharacterSet.urlQueryAllowed
            s.remove(charactersIn: "+&=")
            return s
        }()
        let pairs = fields.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
            return "\(ek)=\(ev)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    private func checkAPISuccess(_ json: [String: Any]) throws {
        let code = (json["code"] as? Int) ?? Int((json["code"] as? String) ?? "0") ?? 0
        if code == 200 { return }
        let msg = (json["msg"] as? String) ?? "未知錯誤"
        throw EInvoiceError.apiError(code: code, message: msg)
    }

    private func parseHeader(_ raw: [String: Any]) -> EInvoiceHeader? {
        guard let invNum = raw["invNum"] as? String,
              let dateStr = raw["invDate"] as? String,
              let date = Self.twDateParser.date(from: dateStr) else { return nil }
        let seller = (raw["sellerName"] as? String) ?? ""
        let amount = parseDouble(raw["amount"]) ?? 0
        let status = (raw["invStatus"] as? String) ?? "開立"
        return EInvoiceHeader(invNum: invNum, invDate: date,
                              sellerName: seller, amount: amount, invStatus: status)
    }

    private func parseDouble(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let s = raw as? String { return Double(s) }
        if let i = raw as? Int { return Double(i) }
        return nil
    }
}
