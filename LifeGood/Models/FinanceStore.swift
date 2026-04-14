import Foundation

class FinanceStore: ObservableObject {
    @Published var insurances: [SavingsInsurance] = [] { didSet { save() } }
    @Published var stocks: [Stock] = [] { didSet { save() } }
    @Published var realEstates: [RealEstate] = [] { didSet { save() } }

    private let insKey = "lifegood_insurances"
    private let stockKey = "lifegood_stocks"
    private let reKey = "lifegood_realestates"

    init() { load() }

    // MARK: - 儲蓄險 CRUD

    func add(_ item: SavingsInsurance) { insurances.append(item) }
    func update(_ item: SavingsInsurance) {
        if let i = insurances.firstIndex(where: { $0.id == item.id }) { insurances[i] = item }
    }
    func deleteInsurance(at offsets: IndexSet) { insurances.remove(atOffsets: offsets) }
    func deleteInsurance(_ item: SavingsInsurance) { insurances.removeAll { $0.id == item.id } }

    // MARK: - 股票 CRUD

    func add(_ item: Stock) { stocks.append(item) }
    func update(_ item: Stock) {
        if let i = stocks.firstIndex(where: { $0.id == item.id }) { stocks[i] = item }
    }
    func deleteStock(at offsets: IndexSet) { stocks.remove(atOffsets: offsets) }
    func deleteStock(_ item: Stock) { stocks.removeAll { $0.id == item.id } }

    // MARK: - 房地產 CRUD

    func add(_ item: RealEstate) { realEstates.append(item) }
    func update(_ item: RealEstate) {
        if let i = realEstates.firstIndex(where: { $0.id == item.id }) { realEstates[i] = item }
    }
    func deleteRealEstate(at offsets: IndexSet) { realEstates.remove(atOffsets: offsets) }
    func deleteRealEstate(_ item: RealEstate) { realEstates.removeAll { $0.id == item.id } }

    // MARK: - 統計

    var totalInsuranceValue: Double { insurances.reduce(0) { $0 + $1.currentValue } }
    var totalStockValue: Double { stocks.reduce(0) { $0 + $1.marketValue } }
    var totalRealEstateValue: Double { realEstates.reduce(0) { $0 + $1.currentValue } }
    var totalAssets: Double { totalInsuranceValue + totalStockValue + totalRealEstateValue }

    var totalStockCost: Double { stocks.reduce(0) { $0 + $1.totalCost } }
    var totalStockProfitLoss: Double { totalStockValue - totalStockCost }

    var monthlyRentalIncome: Double { realEstates.reduce(0) { $0 + $1.monthlyRental } }
    var monthlyMortgagePayment: Double { realEstates.reduce(0) { $0 + $1.monthlyMortgage } }
    var monthlyCashFlow: Double { monthlyRentalIncome - monthlyMortgagePayment }

    // MARK: - 資產配置

    var assetAllocations: [AssetAllocation] {
        let total = totalAssets
        guard total > 0 else { return [] }
        var result: [AssetAllocation] = []
        if totalInsuranceValue > 0 {
            result.append(AssetAllocation(type: .savingsInsurance, value: totalInsuranceValue, percentage: totalInsuranceValue / total * 100))
        }
        if totalStockValue > 0 {
            result.append(AssetAllocation(type: .stock, value: totalStockValue, percentage: totalStockValue / total * 100))
        }
        if totalRealEstateValue > 0 {
            result.append(AssetAllocation(type: .realEstate, value: totalRealEstateValue, percentage: totalRealEstateValue / total * 100))
        }
        return result.sorted { $0.value > $1.value }
    }

    // MARK: - 持久化

    private func save() {
        let encoder = JSONEncoder()
        if let d = try? encoder.encode(insurances) { UserDefaults.standard.set(d, forKey: insKey) }
        if let d = try? encoder.encode(stocks) { UserDefaults.standard.set(d, forKey: stockKey) }
        if let d = try? encoder.encode(realEstates) { UserDefaults.standard.set(d, forKey: reKey) }
    }

    private func load() {
        let decoder = JSONDecoder()
        if let d = UserDefaults.standard.data(forKey: insKey),
           let v = try? decoder.decode([SavingsInsurance].self, from: d) { insurances = v }
        if let d = UserDefaults.standard.data(forKey: stockKey),
           let v = try? decoder.decode([Stock].self, from: d) { stocks = v }
        if let d = UserDefaults.standard.data(forKey: reKey),
           let v = try? decoder.decode([RealEstate].self, from: d) { realEstates = v }
    }

    func clearAll() {
        insurances.removeAll()
        stocks.removeAll()
        realEstates.removeAll()
    }
}
