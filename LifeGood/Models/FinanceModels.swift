import Foundation

// MARK: - 幣別

enum Currency: String, Codable, CaseIterable {
    case twd = "TWD"
    case usd = "USD"

    var symbol: String {
        switch self {
        case .twd: return "NT$"
        case .usd: return "US$"
        }
    }
}

// MARK: - 自訂匯率

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

// MARK: - 儲蓄險

struct SavingsInsurance: Identifiable, Codable {
    let id: UUID
    var name: String
    var company: String
    var currencyCode: String        // 例：NT$、美金、日圓（取代原 Currency 列舉）
    var premiumAmount: Double
    var paymentPeriod: Recurrence
    var annualRate: Double          // 複利年利率（百分比，如 2.5 表示 2.5%）
    var startDate: Date
    var maturityDate: Date
    var expectedReturn: Double      // 由複利公式自動計算後儲存
    var currentValue: Double        // 由複利公式自動計算後儲存
    var linkedExpenseId: UUID?      // 連結記帳模式的固定支出 ID
    var note: String

    init(
        id: UUID = UUID(),
        name: String,
        company: String = "",
        currencyCode: String = "NT$",
        premiumAmount: Double,
        paymentPeriod: Recurrence = .yearly,
        annualRate: Double = 0,
        startDate: Date = Date(),
        maturityDate: Date = Date(),
        expectedReturn: Double = 0,
        currentValue: Double = 0,
        linkedExpenseId: UUID? = nil,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.company = company
        self.currencyCode = currencyCode
        self.premiumAmount = premiumAmount
        self.paymentPeriod = paymentPeriod
        self.annualRate = annualRate
        self.startDate = startDate
        self.maturityDate = maturityDate
        self.expectedReturn = expectedReturn
        self.currentValue = currentValue
        self.linkedExpenseId = linkedExpenseId
        self.note = note
    }

    // MARK: - 向下相容解碼
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        company = (try? c.decode(String.self, forKey: .company)) ?? ""
        if let code = try? c.decode(String.self, forKey: .currencyCode) {
            currencyCode = code
        } else if let legacy = try? c.decode(Currency.self, forKey: .currency) {
            currencyCode = legacy.symbol
        } else {
            currencyCode = "NT$"
        }
        premiumAmount = try c.decode(Double.self, forKey: .premiumAmount)
        paymentPeriod = try c.decode(Recurrence.self, forKey: .paymentPeriod)
        annualRate = (try? c.decode(Double.self, forKey: .annualRate)) ?? 0
        startDate = try c.decode(Date.self, forKey: .startDate)
        maturityDate = try c.decode(Date.self, forKey: .maturityDate)
        expectedReturn = (try? c.decode(Double.self, forKey: .expectedReturn)) ?? 0
        currentValue = (try? c.decode(Double.self, forKey: .currentValue)) ?? 0
        linkedExpenseId = try? c.decode(UUID.self, forKey: .linkedExpenseId)
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
    }
    private enum CodingKeys: String, CodingKey {
        case id, name, company, currency, currencyCode, premiumAmount, paymentPeriod, annualRate
        case startDate, maturityDate, expectedReturn, currentValue, linkedExpenseId, note
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(company, forKey: .company)
        try c.encode(currencyCode, forKey: .currencyCode)
        try c.encode(premiumAmount, forKey: .premiumAmount)
        try c.encode(paymentPeriod, forKey: .paymentPeriod)
        try c.encode(annualRate, forKey: .annualRate)
        try c.encode(startDate, forKey: .startDate)
        try c.encode(maturityDate, forKey: .maturityDate)
        try c.encode(expectedReturn, forKey: .expectedReturn)
        try c.encode(currentValue, forKey: .currentValue)
        try c.encodeIfPresent(linkedExpenseId, forKey: .linkedExpenseId)
        try c.encode(note, forKey: .note)
    }

    /// 每年繳費期數
    private var periodsPerYear: Double {
        switch paymentPeriod {
        case .monthly: return 12
        case .quarterly: return 4
        case .yearly: return 1
        }
    }

    /// 年繳保費
    var annualPremium: Double {
        premiumAmount * periodsPerYear
    }

    /// 複利終值（期初年金）
    /// FV = PMT * [((1+r)^n - 1) / r] * (1+r)，r=0 時 FV = PMT * n
    static func futureValue(payment: Double, ratePerPeriod: Double, periods: Int) -> Double {
        let n = Double(max(0, periods))
        guard ratePerPeriod > 0 else { return payment * n }
        let r = ratePerPeriod
        return payment * ((pow(1 + r, n) - 1) / r) * (1 + r)
    }

    /// 總繳費期數
    var totalPeriods: Int {
        let calendar = Calendar.current
        let totalMonths = calendar.dateComponents([.month], from: startDate, to: maturityDate).month ?? 0
        let monthsPerPeriod: Int = paymentPeriod == .monthly ? 1 : (paymentPeriod == .quarterly ? 3 : 12)
        return max(0, totalMonths / monthsPerPeriod)
    }

    /// 已繳期數（起始日即繳第一期，故 +1）
    var elapsedPeriods: Int {
        let calendar = Calendar.current
        let now = Date()
        guard now >= startDate else { return 0 }
        let elapsedMonths = calendar.dateComponents([.month], from: startDate, to: min(now, maturityDate)).month ?? 0
        let monthsPerPeriod: Int = paymentPeriod == .monthly ? 1 : (paymentPeriod == .quarterly ? 3 : 12)
        return min(elapsedMonths / monthsPerPeriod + 1, totalPeriods)
    }

    /// 計算到期預估領回
    var calculatedExpectedReturn: Double {
        let r = annualRate / 100.0 / periodsPerYear
        return Self.futureValue(payment: premiumAmount, ratePerPeriod: r, periods: totalPeriods)
    }

    /// 計算目前帳戶價值
    var calculatedCurrentValue: Double {
        let r = annualRate / 100.0 / periodsPerYear
        return Self.futureValue(payment: premiumAmount, ratePerPeriod: r, periods: elapsedPeriods)
    }

    /// 已繳總額
    var totalPaid: Double {
        premiumAmount * Double(elapsedPeriods)
    }

    /// 報酬率（以預估領回 vs 已繳總額）
    var returnRate: Double {
        guard totalPaid > 0 else { return 0 }
        return (expectedReturn - totalPaid) / totalPaid * 100
    }
}

// MARK: - 股票

struct Stock: Identifiable, Codable {
    let id: UUID
    var name: String
    var symbol: String
    var purchaseDate: Date
    var shares: Double
    var purchasePrice: Double
    var currentPrice: Double
    var note: String

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String = "",
        purchaseDate: Date = Date(),
        shares: Double = 0,
        purchasePrice: Double = 0,
        currentPrice: Double = 0,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.purchaseDate = purchaseDate
        self.shares = shares
        self.purchasePrice = purchasePrice
        self.currentPrice = currentPrice
        self.note = note
    }

    /// 投入成本
    var totalCost: Double { shares * purchasePrice }
    /// 目前市值
    var marketValue: Double { shares * currentPrice }
    /// 損益
    var profitLoss: Double { marketValue - totalCost }
    /// 報酬率
    var returnRate: Double {
        guard totalCost > 0 else { return 0 }
        return profitLoss / totalCost * 100
    }
}

// MARK: - 房地產貸款項目

struct RealEstateMortgageItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var amount: Double          // 每期繳款金額
    var totalPeriods: Int       // 總期數
    var startDate: Date         // 貸款起始日
    var linkedExpenseId: UUID?  // 連結記帳固定支出

    init(
        id: UUID = UUID(),
        title: String = "",
        amount: Double = 0,
        totalPeriods: Int = 240,
        startDate: Date = Date(),
        linkedExpenseId: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.totalPeriods = totalPeriods
        self.startDate = startDate
        self.linkedExpenseId = linkedExpenseId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        amount = (try? c.decode(Double.self, forKey: .amount)) ?? 0
        totalPeriods = (try? c.decode(Int.self, forKey: .totalPeriods)) ?? 240
        startDate = (try? c.decode(Date.self, forKey: .startDate)) ?? Date()
        linkedExpenseId = try? c.decode(UUID.self, forKey: .linkedExpenseId)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(amount, forKey: .amount)
        try c.encode(totalPeriods, forKey: .totalPeriods)
        try c.encode(startDate, forKey: .startDate)
        try c.encodeIfPresent(linkedExpenseId, forKey: .linkedExpenseId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, amount, totalPeriods, startDate, linkedExpenseId
    }

    /// 貸款總額
    var totalAmount: Double { amount * Double(totalPeriods) }

    /// 已繳期數（從起始日算到今天，每月一期）
    var elapsedPeriods: Int {
        let months = Calendar.current.dateComponents([.month], from: startDate, to: Date()).month ?? 0
        return min(max(0, months), totalPeriods)
    }

    /// 已繳貸款金額
    var paidAmount: Double { amount * Double(elapsedPeriods) }
}

// MARK: - 房地產已支出金額項目

struct RealEstatePaidItem: Identifiable, Codable {
    let id: UUID
    var title: String           // 例如 "頭期款", "簽約金"
    var amount: Double
    var date: Date
    var linkedExpenseId: UUID?

    init(
        id: UUID = UUID(),
        title: String = "",
        amount: Double = 0,
        date: Date = Date(),
        linkedExpenseId: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.date = date
        self.linkedExpenseId = linkedExpenseId
    }
}

// MARK: - 房地產變動支出

enum RealEstateExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case housePayment = "房屋價金"
    case renovation = "裝修"
    case repair = "維修"
    case furniture = "家具"
    case cleaning = "清潔"
    case tax = "稅費"
    case insurance = "保險"
    case other = "其他"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .housePayment: return "banknote"
        case .renovation: return "paintbrush"
        case .repair: return "wrench"
        case .furniture: return "sofa"
        case .cleaning: return "sparkles"
        case .tax: return "doc.text"
        case .insurance: return "shield.fill"
        case .other: return "ellipsis.circle"
        }
    }
}

struct RealEstateVariableExpense: Identifiable, Codable {
    let id: UUID
    var category: RealEstateExpenseCategory
    var name: String
    var amount: Double
    var date: Date
    var linkedExpenseId: UUID?

    init(
        id: UUID = UUID(),
        category: RealEstateExpenseCategory = .renovation,
        name: String = "",
        amount: Double = 0,
        date: Date = Date(),
        linkedExpenseId: UUID? = nil
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.amount = amount
        self.date = date
        self.linkedExpenseId = linkedExpenseId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        category = try c.decode(RealEstateExpenseCategory.self, forKey: .category)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        amount = try c.decode(Double.self, forKey: .amount)
        date = try c.decode(Date.self, forKey: .date)
        linkedExpenseId = try? c.decode(UUID.self, forKey: .linkedExpenseId)
    }
}

// MARK: - 建物類型

enum BuildingType: String, Codable, CaseIterable, Identifiable {
    case townhouse = "透天"
    case apartment = "大樓"
    var id: String { rawValue }
}

// MARK: - 樓層功能

enum FloorFunction: String, Codable, CaseIterable, Identifiable {
    case parking = "停車"
    case livingRoom = "客廳"
    case kitchen = "廚房"
    case masterBedroom = "主臥"
    case guestBedroom = "客臥"
    case musicRoom = "音樂室"
    case playroom = "遊樂室"
    case storage = "倉庫"

    var id: String { rawValue }
}

struct FloorInfo: Identifiable, Codable {
    let id: UUID
    var floorNumber: String
    var functions: [FloorFunction]

    init(id: UUID = UUID(), floorNumber: String = "", functions: [FloorFunction] = []) {
        self.id = id
        self.floorNumber = floorNumber
        self.functions = functions
    }
}

// MARK: - 房地產保險項目

struct RealEstateInsuranceItem: Identifiable, Codable {
    let id: UUID
    var policyNumber: String
    var amount: Double
    var linkedExpenseId: UUID?

    init(
        id: UUID = UUID(),
        policyNumber: String = "",
        amount: Double = 0,
        linkedExpenseId: UUID? = nil
    ) {
        self.id = id
        self.policyNumber = policyNumber
        self.amount = amount
        self.linkedExpenseId = linkedExpenseId
    }
}

// MARK: - 房屋附屬資產

struct RealEstatePropertyAsset: Identifiable, Codable {
    let id: UUID
    var category: RealEstateExpenseCategory
    var name: String
    var brand: String
    var floorLocation: String
    var amount: Double
    var linkedExpenseId: UUID?

    init(
        id: UUID = UUID(),
        category: RealEstateExpenseCategory = .furniture,
        name: String = "",
        brand: String = "",
        floorLocation: String = "",
        amount: Double = 0,
        linkedExpenseId: UUID? = nil
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.brand = brand
        self.floorLocation = floorLocation
        self.amount = amount
        self.linkedExpenseId = linkedExpenseId
    }
}

// MARK: - 房地產

struct RealEstate: Identifiable, Codable {
    let id: UUID
    var name: String
    var city: String                              // 台灣縣市
    var address: String
    var purchaseDate: Date
    var soldDate: Date?                            // 售出日期（nil 表示仍持有）
    var purchasePrice: Double
    var currentValue: Double
    var monthlyRental: Double
    var mortgageItems: [RealEstateMortgageItem]       // 貸款項目（多筆，各有期數）
    var paidItems: [RealEstatePaidItem]               // 已支出房屋金額（頭期款等）
    var variableExpenses: [RealEstateVariableExpense]  // 變動支出（裝修/維修/家具等）
    var linkedExpenseId: UUID?     // 向下相容（舊版單筆房貸連結）
    var note: String

    // MARK: 人生模式欄位
    var buildingType: BuildingType     // 透天/大樓
    var pingCount: Double              // 坪數
    var landOwner: String              // 所有權人
    var landSituation: String          // 座落
    var landNumber: String             // 地號
    var landArea: Double               // 面積
    var totalFloors: Int               // 有幾個樓層（向下相容，新版由 floors.count 覆寫）
    var fromFloor: Int                 // 從幾樓（向下相容）
    var toFloor: Int                   // 到幾樓（向下相容）
    var floors: [FloorInfo]            // 各樓層資訊
    var waterMeterNumber: String       // 水號
    var waterMeterOwner: String        // 水 所有權人
    var electricityMeterNumber: String // 電號
    var electricityMeterOwner: String  // 電 所有權人
    var gasMeterNumber: String         // 瓦斯表號
    var gasMeterOwner: String          // 瓦斯 所有權人
    var insuranceItems: [RealEstateInsuranceItem]      // 保險項目
    var propertyAssets: [RealEstatePropertyAsset]       // 房屋附屬資產

    init(
        id: UUID = UUID(),
        name: String,
        city: String = "",
        address: String = "",
        purchaseDate: Date = Date(),
        soldDate: Date? = nil,
        purchasePrice: Double = 0,
        currentValue: Double = 0,
        monthlyRental: Double = 0,
        mortgageItems: [RealEstateMortgageItem] = [],
        paidItems: [RealEstatePaidItem] = [],
        variableExpenses: [RealEstateVariableExpense] = [],
        linkedExpenseId: UUID? = nil,
        note: String = "",
        buildingType: BuildingType = .townhouse,
        pingCount: Double = 0,
        landOwner: String = "",
        landSituation: String = "",
        landNumber: String = "",
        landArea: Double = 0,
        totalFloors: Int = 0,
        fromFloor: Int = 0,
        toFloor: Int = 0,
        floors: [FloorInfo] = [],
        waterMeterNumber: String = "",
        waterMeterOwner: String = "",
        electricityMeterNumber: String = "",
        electricityMeterOwner: String = "",
        gasMeterNumber: String = "",
        gasMeterOwner: String = "",
        insuranceItems: [RealEstateInsuranceItem] = [],
        propertyAssets: [RealEstatePropertyAsset] = []
    ) {
        self.id = id
        self.name = name
        self.city = city
        self.address = address
        self.purchaseDate = purchaseDate
        self.soldDate = soldDate
        self.purchasePrice = purchasePrice
        self.currentValue = currentValue
        self.monthlyRental = monthlyRental
        self.mortgageItems = mortgageItems
        self.paidItems = paidItems
        self.variableExpenses = variableExpenses
        self.linkedExpenseId = linkedExpenseId
        self.note = note
        self.buildingType = buildingType
        self.pingCount = pingCount
        self.landOwner = landOwner
        self.landSituation = landSituation
        self.landNumber = landNumber
        self.landArea = landArea
        self.totalFloors = totalFloors
        self.fromFloor = fromFloor
        self.toFloor = toFloor
        self.floors = floors
        self.waterMeterNumber = waterMeterNumber
        self.waterMeterOwner = waterMeterOwner
        self.electricityMeterNumber = electricityMeterNumber
        self.electricityMeterOwner = electricityMeterOwner
        self.gasMeterNumber = gasMeterNumber
        self.gasMeterOwner = gasMeterOwner
        self.insuranceItems = insuranceItems
        self.propertyAssets = propertyAssets
    }

    // MARK: - 向下相容解碼
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        city = (try? c.decode(String.self, forKey: .city)) ?? ""
        address = (try? c.decode(String.self, forKey: .address)) ?? ""
        purchaseDate = (try? c.decode(Date.self, forKey: .purchaseDate)) ?? Date()
        soldDate = try? c.decode(Date.self, forKey: .soldDate)
        purchasePrice = (try? c.decode(Double.self, forKey: .purchasePrice)) ?? 0
        currentValue = (try? c.decode(Double.self, forKey: .currentValue)) ?? 0
        monthlyRental = (try? c.decode(Double.self, forKey: .monthlyRental)) ?? 0
        mortgageItems = (try? c.decode([RealEstateMortgageItem].self, forKey: .mortgageItems)) ?? []
        paidItems = (try? c.decode([RealEstatePaidItem].self, forKey: .paidItems)) ?? []
        variableExpenses = (try? c.decode([RealEstateVariableExpense].self, forKey: .variableExpenses)) ?? []
        linkedExpenseId = try? c.decode(UUID.self, forKey: .linkedExpenseId)
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        buildingType = (try? c.decode(BuildingType.self, forKey: .buildingType)) ?? .townhouse
        pingCount = (try? c.decode(Double.self, forKey: .pingCount)) ?? 0
        landOwner = (try? c.decode(String.self, forKey: .landOwner)) ?? ""
        landSituation = (try? c.decode(String.self, forKey: .landSituation)) ?? ""
        landNumber = (try? c.decode(String.self, forKey: .landNumber)) ?? ""
        landArea = (try? c.decode(Double.self, forKey: .landArea)) ?? 0
        totalFloors = (try? c.decode(Int.self, forKey: .totalFloors)) ?? 0
        fromFloor = (try? c.decode(Int.self, forKey: .fromFloor)) ?? 0
        toFloor = (try? c.decode(Int.self, forKey: .toFloor)) ?? 0
        floors = (try? c.decode([FloorInfo].self, forKey: .floors)) ?? []
        waterMeterNumber = (try? c.decode(String.self, forKey: .waterMeterNumber)) ?? ""
        waterMeterOwner = (try? c.decode(String.self, forKey: .waterMeterOwner)) ?? ""
        electricityMeterNumber = (try? c.decode(String.self, forKey: .electricityMeterNumber)) ?? ""
        electricityMeterOwner = (try? c.decode(String.self, forKey: .electricityMeterOwner)) ?? ""
        gasMeterNumber = (try? c.decode(String.self, forKey: .gasMeterNumber)) ?? ""
        gasMeterOwner = (try? c.decode(String.self, forKey: .gasMeterOwner)) ?? ""
        insuranceItems = (try? c.decode([RealEstateInsuranceItem].self, forKey: .insuranceItems)) ?? []
        propertyAssets = (try? c.decode([RealEstatePropertyAsset].self, forKey: .propertyAssets)) ?? []

        // 向下相容：舊版有 monthlyMortgage 欄位，轉為 mortgageItems
        if mortgageItems.isEmpty,
           let oldMortgage = try? c.decode(Double.self, forKey: .monthlyMortgage),
           oldMortgage > 0 {
            mortgageItems = [RealEstateMortgageItem(title: "房貸", amount: oldMortgage)]
        }
    }
    private enum CodingKeys: String, CodingKey {
        case id, name, city, address, purchaseDate, soldDate, purchasePrice, currentValue, monthlyRental
        case mortgageItems, paidItems, variableExpenses, linkedExpenseId, note
        case buildingType, pingCount, landOwner, landSituation, landNumber, landArea
        case totalFloors, fromFloor, toFloor, floors
        case waterMeterNumber, waterMeterOwner, electricityMeterNumber, electricityMeterOwner
        case gasMeterNumber, gasMeterOwner, insuranceItems, propertyAssets
        case monthlyMortgage // 舊版欄位，僅用於解碼
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(city, forKey: .city)
        try c.encode(address, forKey: .address)
        try c.encode(purchaseDate, forKey: .purchaseDate)
        try c.encodeIfPresent(soldDate, forKey: .soldDate)
        try c.encode(purchasePrice, forKey: .purchasePrice)
        try c.encode(currentValue, forKey: .currentValue)
        try c.encode(monthlyRental, forKey: .monthlyRental)
        try c.encode(mortgageItems, forKey: .mortgageItems)
        try c.encode(paidItems, forKey: .paidItems)
        try c.encode(variableExpenses, forKey: .variableExpenses)
        try c.encodeIfPresent(linkedExpenseId, forKey: .linkedExpenseId)
        try c.encode(note, forKey: .note)
        try c.encode(buildingType, forKey: .buildingType)
        try c.encode(pingCount, forKey: .pingCount)
        try c.encode(landOwner, forKey: .landOwner)
        try c.encode(landSituation, forKey: .landSituation)
        try c.encode(landNumber, forKey: .landNumber)
        try c.encode(landArea, forKey: .landArea)
        try c.encode(totalFloors, forKey: .totalFloors)
        try c.encode(fromFloor, forKey: .fromFloor)
        try c.encode(toFloor, forKey: .toFloor)
        try c.encode(floors, forKey: .floors)
        try c.encode(waterMeterNumber, forKey: .waterMeterNumber)
        try c.encode(waterMeterOwner, forKey: .waterMeterOwner)
        try c.encode(electricityMeterNumber, forKey: .electricityMeterNumber)
        try c.encode(electricityMeterOwner, forKey: .electricityMeterOwner)
        try c.encode(gasMeterNumber, forKey: .gasMeterNumber)
        try c.encode(gasMeterOwner, forKey: .gasMeterOwner)
        try c.encode(insuranceItems, forKey: .insuranceItems)
        try c.encode(propertyAssets, forKey: .propertyAssets)
    }

    /// 顯示用的完整地點（縣市 + 地址）
    var fullAddress: String {
        let parts = [city, address].filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    /// 是否已售出
    var isSold: Bool { soldDate != nil }

    /// 每月房貸合計
    var monthlyMortgage: Double { mortgageItems.reduce(0) { $0 + $1.amount } }
    /// 貸款總額
    var totalMortgageAmount: Double { mortgageItems.reduce(0) { $0 + $1.totalAmount } }
    /// 已繳貸款金額合計
    var totalMortgagePaid: Double { mortgageItems.reduce(0) { $0 + $1.paidAmount } }
    /// 已支出房屋金額合計（頭期款等）
    var totalPaid: Double { paidItems.reduce(0) { $0 + $1.amount } }
    /// 房屋總已支出（已支出 + 已繳貸款）
    var totalAllPaid: Double { totalPaid + totalMortgagePaid }
    /// 房產增值
    var appreciation: Double { currentValue - purchasePrice }
    /// 增值率
    var appreciationRate: Double {
        guard purchasePrice > 0 else { return 0 }
        return appreciation / purchasePrice * 100
    }
    /// 變動支出合計
    var variableTotal: Double { variableExpenses.reduce(0) { $0 + $1.amount } }
    /// 每月淨現金流（租金 - 房貸）
    var monthlyCashFlow: Double { monthlyRental - monthlyMortgage }
    /// 年租金報酬率
    var rentalYield: Double {
        guard currentValue > 0 else { return 0 }
        return (monthlyRental * 12) / currentValue * 100
    }
}

// MARK: - 汽車定期支出項目

enum VehicleFixedCategory: String, Codable, CaseIterable, Identifiable {
    case carLoan = "車貸"
    case tax = "稅費"
    case subscription = "訂閱"

    var id: String { rawValue }
}

enum VehicleExpensePeriod: String, Codable, CaseIterable, Identifiable {
    case monthly = "月"
    case yearly = "年"

    var id: String { rawValue }

    /// 換算為每月金額
    func toMonthly(_ amount: Double) -> Double {
        switch self {
        case .monthly: return amount
        case .yearly: return amount / 12.0
        }
    }
}

struct VehicleFixedExpense: Identifiable, Codable {
    let id: UUID
    var category: VehicleFixedCategory
    var amount: Double
    var period: VehicleExpensePeriod
    var linkedExpenseId: UUID?       // 連結記帳模式的固定支出 ID

    init(
        id: UUID = UUID(),
        category: VehicleFixedCategory = .carLoan,
        amount: Double = 0,
        period: VehicleExpensePeriod = .monthly,
        linkedExpenseId: UUID? = nil
    ) {
        self.id = id
        self.category = category
        self.amount = amount
        self.period = period
        self.linkedExpenseId = linkedExpenseId
    }

    /// 每月等效金額
    var monthlyAmount: Double { period.toMonthly(amount) }
}

// MARK: - 汽車動力類型

enum VehiclePowerType: String, Codable, CaseIterable, Identifiable {
    case gasoline = "油車"
    case electric = "電車"
    case hybrid = "混合動力"
    case motorcycle = "機車"
    case electricMotorcycle = "電動機車"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .gasoline: return "fuelpump.fill"
        case .electric: return "bolt.car.fill"
        case .hybrid: return "arrow.triangle.2.circlepath"
        case .motorcycle: return "scooter"
        case .electricMotorcycle: return "bolt.fill"
        }
    }
}

// MARK: - 汽車變動支出項目

enum VehicleVariableCategory: String, Codable, CaseIterable, Identifiable {
    case fuel = "油錢"
    case electricity = "電費"
    case parking = "停車"
    case maintenance = "保養"
    case wash = "洗車"
    case repair = "維修"
    case other = "其他"

    var id: String { rawValue }

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

    /// 根據動力類型篩選可用的變動支出分類
    static func categories(for powerType: VehiclePowerType) -> [VehicleVariableCategory] {
        switch powerType {
        case .gasoline:
            return [.fuel, .parking, .maintenance, .wash, .repair, .other]
        case .electric:
            return [.electricity, .parking, .maintenance, .wash, .repair, .other]
        case .hybrid:
            return [.fuel, .electricity, .parking, .maintenance, .wash, .repair, .other]
        case .motorcycle:
            return [.fuel, .parking, .maintenance, .wash, .repair, .other]
        case .electricMotorcycle:
            return [.electricity, .parking, .maintenance, .wash, .repair, .other]
        }
    }
}

struct VehicleVariableExpense: Identifiable, Codable {
    let id: UUID
    var category: VehicleVariableCategory
    var amount: Double
    var date: Date
    var linkedExpenseId: UUID?       // 連結記帳模式的變動支出 ID

    init(
        id: UUID = UUID(),
        category: VehicleVariableCategory = .fuel,
        amount: Double = 0,
        date: Date = Date(),
        linkedExpenseId: UUID? = nil
    ) {
        self.id = id
        self.category = category
        self.amount = amount
        self.date = date
        self.linkedExpenseId = linkedExpenseId
    }
}

// MARK: - 汽車

struct Vehicle: Identifiable, Codable {
    let id: UUID
    var name: String
    var brand: String
    var ownerName: String
    var powerType: VehiclePowerType
    var purchaseDate: Date
    var soldDate: Date?                            // 售出日期（nil 表示仍持有）
    var purchasePrice: Double
    var currentValue: Double
    var fixedExpenses: [VehicleFixedExpense]       // 定期支出（車貸/稅費/訂閱）
    var variableExpenses: [VehicleVariableExpense]  // 變動支出（依動力類型：油錢或電費等）
    var note: String

    init(
        id: UUID = UUID(),
        name: String,
        brand: String = "",
        ownerName: String = "",
        powerType: VehiclePowerType = .gasoline,
        purchaseDate: Date = Date(),
        soldDate: Date? = nil,
        purchasePrice: Double = 0,
        currentValue: Double = 0,
        fixedExpenses: [VehicleFixedExpense] = [],
        variableExpenses: [VehicleVariableExpense] = [],
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.ownerName = ownerName
        self.powerType = powerType
        self.purchaseDate = purchaseDate
        self.soldDate = soldDate
        self.purchasePrice = purchasePrice
        self.currentValue = currentValue
        self.fixedExpenses = fixedExpenses
        self.variableExpenses = variableExpenses
        self.note = note
    }

    // MARK: - 向下相容解碼
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        brand = (try? c.decode(String.self, forKey: .brand)) ?? ""
        ownerName = (try? c.decode(String.self, forKey: .ownerName)) ?? ""
        powerType = (try? c.decode(VehiclePowerType.self, forKey: .powerType)) ?? .gasoline
        purchaseDate = (try? c.decode(Date.self, forKey: .purchaseDate)) ?? Date()
        soldDate = try? c.decode(Date.self, forKey: .soldDate)
        purchasePrice = (try? c.decode(Double.self, forKey: .purchasePrice)) ?? 0
        currentValue = (try? c.decode(Double.self, forKey: .currentValue)) ?? 0
        fixedExpenses = (try? c.decode([VehicleFixedExpense].self, forKey: .fixedExpenses)) ?? []
        variableExpenses = (try? c.decode([VehicleVariableExpense].self, forKey: .variableExpenses)) ?? []
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(brand, forKey: .brand)
        try c.encode(ownerName, forKey: .ownerName)
        try c.encode(powerType, forKey: .powerType)
        try c.encode(purchaseDate, forKey: .purchaseDate)
        try c.encodeIfPresent(soldDate, forKey: .soldDate)
        try c.encode(purchasePrice, forKey: .purchasePrice)
        try c.encode(currentValue, forKey: .currentValue)
        try c.encode(fixedExpenses, forKey: .fixedExpenses)
        try c.encode(variableExpenses, forKey: .variableExpenses)
        try c.encode(note, forKey: .note)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, brand, ownerName, powerType, purchaseDate, soldDate, purchasePrice, currentValue
        case fixedExpenses, variableExpenses, note
    }

    /// 是否已售出
    var isSold: Bool { soldDate != nil }
    /// 每月定期支出合計
    var monthlyFixedTotal: Double {
        fixedExpenses.reduce(0) { $0 + $1.monthlyAmount }
    }
    /// 變動支出合計
    var variableTotal: Double {
        variableExpenses.reduce(0) { $0 + $1.amount }
    }
    /// 每月總支出（定期 + 變動 — 變動為實際累計非月均）
    var monthlyExpense: Double { monthlyFixedTotal }
    /// 折舊金額
    var depreciation: Double { purchasePrice - currentValue }
    /// 折舊率
    var depreciationRate: Double {
        guard purchasePrice > 0 else { return 0 }
        return depreciation / purchasePrice * 100
    }
    /// 持有年數（若已售出則使用售出日期計算）
    var yearsOwned: Double {
        let endDate = soldDate ?? Date()
        let days = Calendar.current.dateComponents([.day], from: purchaseDate, to: endDate).day ?? 0
        return Double(max(0, days)) / 365.0
    }
    /// 年均折舊
    var annualDepreciation: Double {
        guard yearsOwned > 0 else { return 0 }
        return depreciation / yearsOwned
    }
}

// MARK: - 資產類別（圖表用）

enum AssetType: String, CaseIterable {
    case savingsInsurance = "儲蓄險"
    case stock = "股票"
    case vehicle = "汽車"
    case realEstate = "房地產"
}

// MARK: - 資產配置資料點

struct AssetAllocation: Identifiable {
    let id = UUID()
    let type: AssetType
    let value: Double
    let percentage: Double
}
