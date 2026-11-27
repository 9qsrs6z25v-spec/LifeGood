// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] Expense.swift 用到的理財型別（Mac 不編 FinanceModels.swift，照抄這 3 個；brief.md §G2-3、judge_mac.md §C5）。
// 這 3 個型別只拿來解碼、顯示；case 與 rawValue 一字不差（rawValue 是存在 iCloud 的字），以後 iOS 改了這裡要跟著改。

import Foundation

// MARK: - 自訂匯率

// 照抄 FinanceModels.swift:105-115（25.639）
struct CurrencyRate: Identifiable, Codable {
    let id: UUID
    var code: String   // 例：美金
    var rate: Double   // 例：32（1 單位 = 32 NT$）

    init(id: UUID = UUID(), code: String = "", rate: Double = 0) {
        self.id = id
        self.code = code
        self.rate = rate
    }
}

// MARK: - 房地產變動支出

// 照抄 FinanceModels.swift:841-871（25.639）
enum RealEstateExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case housePayment = "房屋價金"
    // [v25.534] 仲介費、代書費、契稅、登記規費、印花稅：買房時付的、但不是房子本身的價錢。
    case purchaseCost = "買房費用"
    case renovation = "裝修"
    case repair = "維修"
    case furniture = "家具"
    case cleaning = "清潔"
    case utility = "水電瓦斯"
    case tax = "稅費"
    case insurance = "保險"
    case other = "其他"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .housePayment: return "banknote"
        case .purchaseCost: return "signature"
        case .renovation: return "paintbrush"
        case .repair: return "wrench"
        case .furniture: return "sofa"
        case .cleaning: return "sparkles"
        case .utility: return "bolt.fill"
        case .tax: return "doc.text"
        case .insurance: return "shield.fill"
        case .other: return "ellipsis.circle"
        }
    }
}

// MARK: - 汽車變動支出項目

// 照抄 FinanceModels.swift:1874-1902（25.639）；categories(for: VehiclePowerType) 不抄（Mac 沒有 VehiclePowerType）
enum VehicleVariableCategory: String, Codable, CaseIterable, Identifiable {
    case fuel = "油錢"
    case electricity = "電費"
    case parking = "停車"
    case maintenance = "保養"
    case wash = "洗車"
    case repair = "維修"
    case other = "其他"

    var id: String { rawValue }

    /// [v25.538] 認不得的值（以後新版加的分類）退回「其他」，不要讓整筆被 lossyArray 默默丟掉
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .other
    }

    var icon: String {
        switch self {
        case .fuel: return "fuelpump"
        case .electricity: return "bolt.fill"
        case .parking: return "parkingsign.circle"
        case .maintenance: return "wrench.and.screwdriver"
        case .wash: return "drop.circle"
        case .repair: return "hammer"
        case .other: return "ellipsis.circle"
        }
    }
}
