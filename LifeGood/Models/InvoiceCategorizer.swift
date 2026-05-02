import Foundation

/// 將電子發票（商家 + 品項）對應到 LifeGood 變動支出分類。
final class InvoiceCategorizer: ObservableObject {
    static let shared = InvoiceCategorizer()

    @Published private(set) var rules: [CategoryRule] = []

    private let storageURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir,
                                                     withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("category_rules.json")
    }()

    private init() {
        load()
        if rules.isEmpty {
            rules = Self.defaultRules
            persist()
        }
    }

    // MARK: - 對外 API

    /// 依 header / items 推斷分類；找不到回 .other
    func categorize(seller: String, items: [EInvoiceItem]) -> VariableCategory {
        // 1. 優先比對商家
        for rule in rules where rule.matchSeller && !rule.keyword.isEmpty {
            if seller.localizedCaseInsensitiveContains(rule.keyword) {
                return rule.category
            }
        }
        // 2. 再比對品項
        for item in items {
            for rule in rules where rule.matchItem && !rule.keyword.isEmpty {
                if item.description.localizedCaseInsensitiveContains(rule.keyword) {
                    return rule.category
                }
            }
        }
        return .other
    }

    func addRule(_ rule: CategoryRule) {
        rules.append(rule)
        persist()
    }

    func updateRule(_ rule: CategoryRule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
            persist()
        }
    }

    func deleteRule(_ rule: CategoryRule) {
        rules.removeAll { $0.id == rule.id }
        persist()
    }

    func resetToDefaults() {
        rules = Self.defaultRules
        persist()
    }

    // MARK: - 持久化

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([CategoryRule].self, from: data) else { return }
        rules = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    // MARK: - 預設規則

    static let defaultRules: [CategoryRule] = [
        // 飲食 - 便利商店
        .init(keyword: "7-ELEVEN", category: .food),
        .init(keyword: "統一超商", category: .food),
        .init(keyword: "全家便利", category: .food),
        .init(keyword: "萊爾富", category: .food),
        .init(keyword: "OK便利", category: .food),
        // 飲食 - 連鎖餐飲
        .init(keyword: "麥當勞", category: .food),
        .init(keyword: "肯德基", category: .food),
        .init(keyword: "摩斯", category: .food),
        .init(keyword: "頂呱呱", category: .food),
        .init(keyword: "繼光香香雞", category: .food),
        .init(keyword: "鼎泰豐", category: .food),
        .init(keyword: "王品", category: .food),
        .init(keyword: "瓦城", category: .food),
        .init(keyword: "饗食天堂", category: .food),
        // 飲食 - 飲料
        .init(keyword: "星巴克", category: .food),
        .init(keyword: "路易莎", category: .food),
        .init(keyword: "85度C", category: .food),
        .init(keyword: "CAMA", category: .food),
        // 飲食 - 品項
        .init(keyword: "咖啡", category: .food, matchSeller: false),
        .init(keyword: "拿鐵", category: .food, matchSeller: false),
        .init(keyword: "便當", category: .food, matchSeller: false),
        .init(keyword: "飯糰", category: .food, matchSeller: false),
        .init(keyword: "麵包", category: .food, matchSeller: false),

        // 交通 - 大眾運輸（特別處理悠遊卡儲值不算消費，標記不匯入）
        .init(keyword: "台灣高鐵", category: .transportation),
        .init(keyword: "台灣鐵路", category: .transportation),
        .init(keyword: "捷運", category: .transportation),
        .init(keyword: "客運", category: .transportation),
        .init(keyword: "計程車", category: .transportation),
        .init(keyword: "Uber", category: .transportation),
        .init(keyword: "悠遊卡", category: .transportation),
        .init(keyword: "一卡通", category: .transportation),
        // 交通 - 加油
        .init(keyword: "中油", category: .transportation),
        .init(keyword: "台塑石油", category: .transportation),
        .init(keyword: "全國加油", category: .transportation),
        .init(keyword: "加油站", category: .transportation),
        // 交通 - 停車 / 高速公路
        .init(keyword: "停車", category: .transportation),
        .init(keyword: "ETC", category: .transportation),
        .init(keyword: "高速公路局", category: .transportation),

        // 汽車 - 保養維修
        .init(keyword: "汽車保養", category: .vehicle),
        .init(keyword: "汽車美容", category: .vehicle),
        .init(keyword: "輪胎", category: .vehicle, matchSeller: false),
        .init(keyword: "機油", category: .vehicle, matchSeller: false),

        // 醫療
        .init(keyword: "診所", category: .medical),
        .init(keyword: "醫院", category: .medical),
        .init(keyword: "藥局", category: .medical),
        .init(keyword: "醫美", category: .medical),

        // 日用 / 採購
        .init(keyword: "屈臣氏", category: .dailyNecessities),
        .init(keyword: "康是美", category: .dailyNecessities),
        .init(keyword: "寶雅", category: .dailyNecessities),
        .init(keyword: "美廉社", category: .dailyNecessities),
        .init(keyword: "全聯", category: .dailyNecessities),
        .init(keyword: "家樂福", category: .dailyNecessities),
        .init(keyword: "大潤發", category: .dailyNecessities),
        .init(keyword: "好市多", category: .dailyNecessities),
        .init(keyword: "COSTCO", category: .dailyNecessities),
        .init(keyword: "IKEA", category: .dailyNecessities),
        .init(keyword: "宜得利", category: .dailyNecessities),
        .init(keyword: "特力屋", category: .dailyNecessities),

        // 娛樂
        .init(keyword: "電影", category: .entertainment),
        .init(keyword: "威秀", category: .entertainment),
        .init(keyword: "影城", category: .entertainment),
        .init(keyword: "KTV", category: .entertainment),
        .init(keyword: "錢櫃", category: .entertainment),
        .init(keyword: "好樂迪", category: .entertainment),
        .init(keyword: "劍湖山", category: .entertainment),
        .init(keyword: "六福村", category: .entertainment),

        // 購物
        .init(keyword: "UNIQLO", category: .shopping),
        .init(keyword: "ZARA", category: .shopping),
        .init(keyword: "H&M", category: .shopping),
        .init(keyword: "百貨", category: .shopping),
        .init(keyword: "新光三越", category: .shopping),
        .init(keyword: "SOGO", category: .shopping),
        .init(keyword: "微風", category: .shopping),
        .init(keyword: "PChome", category: .shopping),
        .init(keyword: "蝦皮", category: .shopping),
        .init(keyword: "momo", category: .shopping),

        // 教育
        .init(keyword: "誠品", category: .education),
        .init(keyword: "金石堂", category: .education),
        .init(keyword: "博客來", category: .education),
        .init(keyword: "書店", category: .education),
        .init(keyword: "補習", category: .education),

        // 社交
        .init(keyword: "酒吧", category: .social),
        .init(keyword: "夜店", category: .social),
        .init(keyword: "餐酒館", category: .social),
    ]
}
