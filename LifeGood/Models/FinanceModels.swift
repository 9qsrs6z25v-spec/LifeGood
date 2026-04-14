import Foundation

// MARK: - 儲蓄險

struct SavingsInsurance: Identifiable, Codable {
    let id: UUID
    var name: String
    var company: String
    var premiumAmount: Double
    var paymentPeriod: Recurrence
    var startDate: Date
    var maturityDate: Date
    var expectedReturn: Double
    var currentValue: Double
    var note: String

    init(
        id: UUID = UUID(),
        name: String,
        company: String = "",
        premiumAmount: Double,
        paymentPeriod: Recurrence = .yearly,
        startDate: Date = Date(),
        maturityDate: Date = Date(),
        expectedReturn: Double = 0,
        currentValue: Double = 0,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.company = company
        self.premiumAmount = premiumAmount
        self.paymentPeriod = paymentPeriod
        self.startDate = startDate
        self.maturityDate = maturityDate
        self.expectedReturn = expectedReturn
        self.currentValue = currentValue
        self.note = note
    }

    /// 年繳保費
    var annualPremium: Double {
        switch paymentPeriod {
        case .monthly: return premiumAmount * 12
        case .quarterly: return premiumAmount * 4
        case .yearly: return premiumAmount
        }
    }

    /// 已繳總額
    var totalPaid: Double {
        let calendar = Calendar.current
        let now = Date()
        let months = calendar.dateComponents([.month], from: startDate, to: min(now, maturityDate)).month ?? 0
        switch paymentPeriod {
        case .monthly: return premiumAmount * Double(max(0, months))
        case .quarterly: return premiumAmount * Double(max(0, months / 3))
        case .yearly: return premiumAmount * Double(max(0, months / 12))
        }
    }

    /// 報酬率
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

// MARK: - 房地產

struct RealEstate: Identifiable, Codable {
    let id: UUID
    var name: String
    var address: String
    var purchaseDate: Date
    var purchasePrice: Double
    var currentValue: Double
    var monthlyRental: Double
    var monthlyMortgage: Double
    var note: String

    init(
        id: UUID = UUID(),
        name: String,
        address: String = "",
        purchaseDate: Date = Date(),
        purchasePrice: Double = 0,
        currentValue: Double = 0,
        monthlyRental: Double = 0,
        monthlyMortgage: Double = 0,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.purchaseDate = purchaseDate
        self.purchasePrice = purchasePrice
        self.currentValue = currentValue
        self.monthlyRental = monthlyRental
        self.monthlyMortgage = monthlyMortgage
        self.note = note
    }

    /// 房產增值
    var appreciation: Double { currentValue - purchasePrice }
    /// 增值率
    var appreciationRate: Double {
        guard purchasePrice > 0 else { return 0 }
        return appreciation / purchasePrice * 100
    }
    /// 每月淨現金流（租金 - 房貸）
    var monthlyCashFlow: Double { monthlyRental - monthlyMortgage }
    /// 年租金報酬率
    var rentalYield: Double {
        guard currentValue > 0 else { return 0 }
        return (monthlyRental * 12) / currentValue * 100
    }
}

// MARK: - 資產類別（圖表用）

enum AssetType: String, CaseIterable {
    case savingsInsurance = "儲蓄險"
    case stock = "股票"
    case realEstate = "房地產"
}

// MARK: - 資產配置資料點

struct AssetAllocation: Identifiable {
    let id = UUID()
    let type: AssetType
    let value: Double
    let percentage: Double
}
