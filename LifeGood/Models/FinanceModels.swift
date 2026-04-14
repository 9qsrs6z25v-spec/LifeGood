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

// MARK: - 儲蓄險

struct SavingsInsurance: Identifiable, Codable {
    let id: UUID
    var name: String
    var company: String
    var currency: Currency
    var premiumAmount: Double
    var paymentPeriod: Recurrence
    var annualRate: Double          // 複利年利率（百分比，如 2.5 表示 2.5%）
    var startDate: Date
    var maturityDate: Date
    var expectedReturn: Double      // 由複利公式自動計算後儲存
    var currentValue: Double        // 由複利公式自動計算後儲存
    var note: String

    init(
        id: UUID = UUID(),
        name: String,
        company: String = "",
        currency: Currency = .twd,
        premiumAmount: Double,
        paymentPeriod: Recurrence = .yearly,
        annualRate: Double = 0,
        startDate: Date = Date(),
        maturityDate: Date = Date(),
        expectedReturn: Double = 0,
        currentValue: Double = 0,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.company = company
        self.currency = currency
        self.premiumAmount = premiumAmount
        self.paymentPeriod = paymentPeriod
        self.annualRate = annualRate
        self.startDate = startDate
        self.maturityDate = maturityDate
        self.expectedReturn = expectedReturn
        self.currentValue = currentValue
        self.note = note
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
