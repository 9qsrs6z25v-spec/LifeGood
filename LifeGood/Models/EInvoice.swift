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

    init(invNum: String, invDate: Date, sellerName: String, amount: Double,
         expenseIds: [UUID], assignedCategory: VariableCategory) {
        self.id = UUID()
        self.invNum = invNum
        self.invDate = invDate
        self.sellerName = sellerName
        self.amount = amount
        self.importedAt = Date()
        self.expenseIds = expenseIds
        self.assignedCategory = assignedCategory
    }
}

// MARK: - 同步結果

struct EInvoiceSyncResult {
    let importedCount: Int
    let skippedCount: Int      // 已存在
    let failedCount: Int
    let errors: [String]
    let timestamp: Date

    var summary: String {
        if failedCount > 0 {
            return "匯入 \(importedCount) 筆、略過 \(skippedCount) 筆、失敗 \(failedCount) 筆"
        }
        return "匯入 \(importedCount) 筆、略過 \(skippedCount) 筆"
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
