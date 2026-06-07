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
    private let saveQueue = DispatchQueue(label: "com.lifegood.financestore.save", qos: .utility)

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
        let ins = totalInsuranceValue
        let stk = totalStockValue
        let veh = totalVehicleValue
        let re  = totalRealEstateValue
        let total = ins + stk + veh + re
        guard total > 0 else { return [] }
        var result: [AssetAllocation] = []
        if ins > 0 { result.append(AssetAllocation(type: .savingsInsurance, value: ins, percentage: ins / total * 100)) }
        if stk > 0 { result.append(AssetAllocation(type: .stock,            value: stk, percentage: stk / total * 100)) }
        if veh > 0 { result.append(AssetAllocation(type: .vehicle,          value: veh, percentage: veh / total * 100)) }
        if re  > 0 { result.append(AssetAllocation(type: .realEstate,       value: re,  percentage: re  / total * 100)) }
        return result.sorted { $0.value > $1.value }
    }

    // MARK: - 持久化

    private func saveInsurances() {
        let snap = insurances; let key = insKey
        // 使用 pushAll() 統一走 2 秒防抖，避免連續編輯時繞過節流直接打 CloudKit
        saveQueue.async {
            if let d = try? JSONEncoder().encode(snap) { UserDefaults.standard.set(d, forKey: key) }
            CloudSyncManager.shared.pushAll()
        }
    }

    private func saveStocks() {
        let snap = stocks; let key = stockKey
        saveQueue.async {
            if let d = try? JSONEncoder().encode(snap) { UserDefaults.standard.set(d, forKey: key) }
            CloudSyncManager.shared.pushAll()
        }
    }

    private func saveVehicles() {
        let snap = vehicles; let key = vehicleKey
        saveQueue.async {
            if let d = try? JSONEncoder().encode(snap) { UserDefaults.standard.set(d, forKey: key) }
            CloudSyncManager.shared.pushAll()
        }
    }

    private func saveRealEstates() {
        let snap = realEstates; let key = reKey
        saveQueue.async {
            if let d = try? JSONEncoder().encode(snap) { UserDefaults.standard.set(d, forKey: key) }
            CloudSyncManager.shared.pushAll()
        }
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        let decoder = JSONDecoder()
        if let d = UserDefaults.standard.data(forKey: insKey),
           let v = try? decoder.decode([SavingsInsurance].self, from: d) { insurances = v }
        if let d = UserDefaults.standard.data(forKey: stockKey),
           let v = try? decoder.decode([Stock].self, from: d) { stocks = v }
        if let d = UserDefaults.standard.data(forKey: vehicleKey),
           let v = try? decoder.decode([Vehicle].self, from: d) { vehicles = v }
        if let d = UserDefaults.standard.data(forKey: reKey),
           let v = try? decoder.decode([RealEstate].self, from: d) { realEstates = v }
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
