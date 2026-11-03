import Foundation

// MARK: - 載具設定（手機條碼 + 驗證碼）

struct EInvoiceCarrier: Codable, Equatable {
    /// 手機條碼，例：/ABC1234（含斜線）
    var cardNo: String
    /// 驗證碼（不存入 UserDefaults，存 Keychain）
    var cardEncrypt: String

    static let cardType = "3J0002" // 手機條碼固定值
}

// MARK: - 發票標頭（API 回應映射）

struct EInvoiceHeader: Codable, Identifiable {
    var id: String { invNum }
    let invNum: String          // 發票號碼，10 碼，例：AB12345678
    let invDate: Date           // 發票日期
    let sellerName: String      // 商家名稱
    let amount: Double          // 總金額
    let invStatus: String       // 開立狀態
}

// MARK: - 發票品項

struct EInvoiceItem: Codable, Identifiable {
    var id: String { "\(invNum)#\(rowNum)" }
    let invNum: String
    let rowNum: Int
    let description: String
    let quantity: Double
    let unitPrice: Double
    let amount: Double
}

// MARK: - 發票完整資料（標頭 + 明細）

struct EInvoiceFull: Codable {
    let header: EInvoiceHeader
    let items: [EInvoiceItem]
}

// MARK: - 匯入記錄（持久化，避免重複匯入）

struct EInvoiceImportRecord: Codable, Identifiable {
    let id: UUID
    let invNum: String
    let invDate: Date
    let sellerName: String
    let amount: Double
    let importedAt: Date
    /// 寫入 ExpenseStore 後對應的 Expense IDs（一張發票可能拆出多筆）
    let expenseIds: [UUID]
    /// 自動分類結果（預設規則匹配的分類）
    let assignedCategory: VariableCategory
    /// [v2] 「併入既有」：這張發票沒有另建支出，而是認領了一筆「一按就記」的支出
    ///（小工具記的同金額、同一天或前後一天那筆），發票號碼補進那筆的備註。
    /// 這種紀錄的 expenseIds 是空的；撤銷只拿掉那筆備註裡的發票資訊，不刪支出。
    /// 合成 Codable：舊檔沒有這個 key 解出來是 nil；nil 也不寫 key。
    let mergedExpenseId: UUID?

    /// [v2] 是不是「併入既有」的紀錄
    var isMerged: Bool { mergedExpenseId != nil }

    init(invNum: String, invDate: Date, sellerName: String, amount: Double,
         expenseIds: [UUID], assignedCategory: VariableCategory,
         mergedExpenseId: UUID? = nil) {
        self.id = UUID()
        self.invNum = invNum
        self.invDate = invDate
        self.sellerName = sellerName
        self.amount = amount
        self.importedAt = Date()
        self.expenseIds = expenseIds
        self.assignedCategory = assignedCategory
        self.mergedExpenseId = mergedExpenseId
    }
}

// MARK: - 同步結果

struct EInvoiceSyncResult {
    let importedCount: Int
    let skippedCount: Int      // 已存在
    let failedCount: Int
    let errors: [String]
    let timestamp: Date
    /// [v2] 併入既有（認領了「一按就記」的支出、沒有另建）的張數。有預設值，舊的建法不用改
    var mergedCount: Int = 0

    /// 「匯入 3 筆、略過 2 筆」；有併入既有才多一段「併入既有 1 筆」，有失敗才多「失敗 N 筆」
    var summary: String {
        var parts: [String] = ["匯入 \(importedCount) 筆"]
        if mergedCount > 0 {
            parts.append("併入既有 \(mergedCount) 筆")
        }
        parts.append("略過 \(skippedCount) 筆")
        if failedCount > 0 {
            parts.append("失敗 \(failedCount) 筆")
        }
        return parts.joined(separator: "、")
    }
}

// MARK: - 自動分類規則

struct CategoryRule: Codable, Identifiable {
    var id: UUID
    var keyword: String                // 商家或品項關鍵字（不分大小寫）
    var category: VariableCategory
    var matchSeller: Bool              // 是否比對商家名稱
    var matchItem: Bool                // 是否比對品項描述
    var isUserDefined: Bool            // 使用者新增的規則

    init(id: UUID = UUID(), keyword: String, category: VariableCategory,
         matchSeller: Bool = true, matchItem: Bool = true, isUserDefined: Bool = false) {
        self.id = id
        self.keyword = keyword
        self.category = category
        self.matchSeller = matchSeller
        self.matchItem = matchItem
        self.isUserDefined = isUserDefined
    }
}
