import Foundation

class FinanceStore: ObservableObject {
    @Published var insurances: [SavingsInsurance] = [] { didSet { if !isLoading { saveInsurances() } } }
    @Published var stocks: [Stock] = [] { didSet { if !isLoading { saveStocks() } } }
    @Published var vehicles: [Vehicle] = [] { didSet { if !isLoading { saveVehicles() } } }
    @Published var realEstates: [RealEstate] = [] { didSet { if !isLoading { saveRealEstates() } } }

    private let insKey = "lifegood_insurances"
    private let stockKey = "lifegood_stocks"
    private let vehicleKey = "lifegood_vehicles"
    private let reKey = "lifegood_realestates"
    private var isLoading = false

    init() {
        load()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadFromCloud),
            name: .cloudSyncDidPullChanges,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func reloadFromCloud() {
        load()
    }

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

    // MARK: - 汽車 CRUD

    func add(_ item: Vehicle) { vehicles.append(item) }
    func update(_ item: Vehicle) {
        if let i = vehicles.firstIndex(where: { $0.id == item.id }) { vehicles[i] = item }
    }
    func deleteVehicle(at offsets: IndexSet) { vehicles.remove(atOffsets: offsets) }
    func deleteVehicle(_ item: Vehicle) { vehicles.removeAll { $0.id == item.id } }

    // MARK: - 房地產 CRUD

    func add(_ item: RealEstate) { realEstates.append(item) }
    func update(_ item: RealEstate) {
        if let i = realEstates.firstIndex(where: { $0.id == item.id }) { realEstates[i] = item }
    }
    func deleteRealEstate(at offsets: IndexSet) { realEstates.remove(atOffsets: offsets) }
    func deleteRealEstate(_ item: RealEstate) { realEstates.removeAll { $0.id == item.id } }

    // MARK: - 統計

    var totalInsuranceValue: Double { insurances.reduce(0) { $0 + $1.currentValue } }
    var totalStockValue: Double { stocks.filter { !$0.isSold }.reduce(0) { $0 + $1.marketValue } }
    var totalVehicleValue: Double { vehicles.reduce(0) { $0 + $1.currentValue } }
    var totalRealEstateValue: Double { realEstates.filter { !$0.isSold }.reduce(0) { $0 + $1.currentValue } }
    var totalAssets: Double { totalInsuranceValue + totalStockValue + totalVehicleValue + totalRealEstateValue }

    var totalStockCost: Double { stocks.reduce(0) { $0 + $1.totalCost } }
    var totalStockProfitLoss: Double { stocks.reduce(0) { $0 + $1.profitLoss } }

    var monthlyRentalIncome: Double { realEstates.filter { !$0.isSold }.reduce(0) { $0 + $1.monthlyRental } }
    var monthlyMortgagePayment: Double { realEstates.filter { !$0.isSold }.reduce(0) { $0 + $1.monthlyMortgage } }
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
        if totalVehicleValue > 0 {
            result.append(AssetAllocation(type: .vehicle, value: totalVehicleValue, percentage: totalVehicleValue / total * 100))
        }
        if totalRealEstateValue > 0 {
            result.append(AssetAllocation(type: .realEstate, value: totalRealEstateValue, percentage: totalRealEstateValue / total * 100))
        }
        return result.sorted { $0.value > $1.value }
    }

    // MARK: - 持久化

    private func saveInsurances() {
        if let d = try? JSONEncoder().encode(insurances) { UserDefaults.standard.set(d, forKey: insKey) }
        CloudSyncManager.shared.push(key: insKey)
    }

    private func saveStocks() {
        if let d = try? JSONEncoder().encode(stocks) { UserDefaults.standard.set(d, forKey: stockKey) }
        CloudSyncManager.shared.push(key: stockKey)
    }

    private func saveVehicles() {
        if let d = try? JSONEncoder().encode(vehicles) { UserDefaults.standard.set(d, forKey: vehicleKey) }
        CloudSyncManager.shared.push(key: vehicleKey)
    }

    private func saveRealEstates() {
        if let d = try? JSONEncoder().encode(realEstates) { UserDefaults.standard.set(d, forKey: reKey) }
        CloudSyncManager.shared.push(key: reKey)
    }

    private func load() {
        isLoading = true
        let decoder = JSONDecoder()
        if let d = UserDefaults.standard.data(forKey: insKey),
           let v = try? decoder.decode([SavingsInsurance].self, from: d) { insurances = v }
        if let d = UserDefaults.standard.data(forKey: stockKey),
           let v = try? decoder.decode([Stock].self, from: d) { stocks = v }
        if let d = UserDefaults.standard.data(forKey: vehicleKey),
           let v = try? decoder.decode([Vehicle].self, from: d) { vehicles = v }
        if let d = UserDefaults.standard.data(forKey: reKey),
           let v = try? decoder.decode([RealEstate].self, from: d) { realEstates = v }
        isLoading = false
    }

    func clearAll() {
        isLoading = true
        insurances.removeAll()
        stocks.removeAll()
        vehicles.removeAll()
        realEstates.removeAll()
        isLoading = false
        saveInsurances()
        saveStocks()
        saveVehicles()
        saveRealEstates()
    }
}
