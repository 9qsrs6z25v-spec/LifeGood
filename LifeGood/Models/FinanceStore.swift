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
    /// 記錄每個 key 上次成功套用到 @Published 屬性的原始 Data，供 load() 判斷是否真的有變更，
    /// 避免雲端這輪只改了其中一個 key 時，其餘資料仍用「完全相同」的內容重新賦值造成無謂重繪。
    private var lastLoadedRawData: [String: Data] = [:]

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

    @objc private func reloadFromCloud(_ note: Notification) {
        // cloudSyncDidPullChanges 由 CloudSyncManager.handleKVChanges 在 main thread 上 post，
        // 與 LifeStore / ExpenseStore 保持一致：直接呼叫 load()，消除多一個 run-loop 的空窗期，
        // 避免該期間使用者操作觸發 save() 後被雲端資料覆蓋。
        // userInfo["keys"] 有帶入且與本 Store 無關時（例如只有 ExpenseStore/LifeStore 的資料
        // 變更）跳過重載，避免不相關畫面無謂重繪；未帶 keys（首次同步覆蓋／合併）維持全量重載。
        if let keys = note.userInfo?["keys"] as? [String],
           Set(keys).isDisjoint(with: [insKey, stockKey, vehicleKey, reKey]) {
            return
        }
        load()
    }

    // MARK: - 儲蓄險 CRUD

    func add(_ item: SavingsInsurance) { insurances.append(item) }
    func update(_ item: SavingsInsurance) {
        if let i = insurances.firstIndex(where: { $0.id == item.id }) { insurances[i] = item }
    }
    func deleteInsurance(_ item: SavingsInsurance) { insurances.removeAll { $0.id == item.id } }

    // MARK: - 股票 CRUD

    func add(_ item: Stock) { stocks.append(item) }
    func update(_ item: Stock) {
        if let i = stocks.firstIndex(where: { $0.id == item.id }) { stocks[i] = item }
    }
    func deleteStock(_ item: Stock) { stocks.removeAll { $0.id == item.id } }

    /// 批次更新多筆股票現價：單次 @Published 觸發（一次重繪、一次 JSON 序列化、一次 CloudKit 推送），
    /// 避免逐筆 stocks[idx].currentPrice = price 造成 N 次串聯重繪。
    func batchUpdateStockPrices(_ updates: [UUID: Double]) {
        guard !updates.isEmpty else { return }
        var updated = stocks
        var changed = false
        for idx in updated.indices {
            if let price = updates[updated[idx].id], updated[idx].currentPrice != price {
                updated[idx].currentPrice = price
                changed = true
            }
        }
        // 報價與現有值完全相同時（例如休市或 API 回傳同一收盤價）跳過賦值，
        // 避免觸發不必要的 @Published 重繪與 CloudKit 推送。
        guard changed else { return }
        stocks = updated
    }

    // MARK: - 汽車 CRUD

    func add(_ item: Vehicle) { vehicles.append(item) }
    func update(_ item: Vehicle) {
        if let i = vehicles.firstIndex(where: { $0.id == item.id }) { vehicles[i] = item }
    }
    func deleteVehicle(_ item: Vehicle) {
        // 連同照片紀錄的實體檔案與雲端記錄一併刪除（同型寫法見 deleteRealEstate 裝潢照片清理）
        for pr in item.photoRecords {
            for name in pr.photoFileNames { VehiclePhotoRecord.deletePhoto(name) }
        }
        vehicles.removeAll { $0.id == item.id }
    }

    // MARK: - 房地產 CRUD

    func add(_ item: RealEstate) { realEstates.append(item) }
    func update(_ item: RealEstate) {
        if let i = realEstates.firstIndex(where: { $0.id == item.id }) { realEstates[i] = item }
    }
    func deleteRealEstate(_ item: RealEstate) {
        Self.cleanupRealEstateFiles(item)
        realEstates.removeAll { $0.id == item.id }
    }

    /// 刪除房地產時一併清掉電梯保養/水電繳費/裝潢照片/文件檔案，
    /// 否則檔案會永久留在磁碟並被 CloudKitManager.uploadAllLocalPhotos() 當成
    /// 「未上傳的本機照片」反覆重傳（對齊 UnifiedImporter.applyUnified 的清理方式）。
    private static func cleanupRealEstateFiles(_ item: RealEstate) {
        for up in item.utilityPayments {
            for name in up.photoFileNames { UtilityPayment.deletePhoto(name) }
        }
        for rp in item.renovationPhotos {
            for name in rp.photoFileNames { RenovationPhoto.deletePhoto(name) }
        }
        for em in item.elevatorMaintenances {
            if let name = em.photoFileName { ElevatorMaintenance.deletePhoto(name) }
        }
        for doc in item.documents {
            RealEstateDocument.deleteDocument(doc.fileName)
        }
    }

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
        // 各集合改用「逐筆容錯」解碼：單一筆損壞（例如舊資料/壞的 CloudKit 合併）
        // 不會讓整批保單/股票/車輛/房地產資料整批消失（對齊 LifeStore.lossyDecodeArray 的作法）
        if let v = lossyDecodeArray([SavingsInsurance].self, key: insKey, decoder: decoder) { insurances = v }
        if let v = lossyDecodeArray([Stock].self, key: stockKey, decoder: decoder) { stocks = v }
        if let v = lossyDecodeArray([Vehicle].self, key: vehicleKey, decoder: decoder) { vehicles = v }
        if let v = lossyDecodeArray([RealEstate].self, key: reKey, decoder: decoder) { realEstates = v }
    }

    /// 讀取 key 目前在 UserDefaults 的原始 Data；若與上次成功套用的內容完全相同則回傳 nil，
    /// 讓呼叫端略過解碼／賦值，避免同一批資料重複觸發 @Published 造成無謂重繪。
    private func rawDataIfChanged(_ key: String) -> Data? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        if lastLoadedRawData[key] == data { return nil }
        lastLoadedRawData[key] = data
        return data
    }

    /// 逐筆容錯解碼：先試整批，失敗再逐筆解、跳過損壞的元素，保留其餘資料。
    /// key 不存在、或與上次套用的內容相同 → 回傳 nil（不覆蓋現有值）；存在且有變更但全空 → 回傳 []。
    private func lossyDecodeArray<Element: Decodable>(
        _ type: [Element].Type, key: String, decoder: JSONDecoder
    ) -> [Element]? {
        guard let data = rawDataIfChanged(key) else { return nil }
        if let items = try? decoder.decode([Element].self, from: data) { return items }
        if let raw = try? decoder.decode([FailableDecodable<Element>].self, from: data) {
            return raw.compactMap { $0.value }
        }
        return nil
    }

    /// 包裝單一元素，解碼失敗時不丟錯、回傳 nil
    private struct FailableDecodable<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    func clearAll() {
        isLoading = true
        for item in realEstates { Self.cleanupRealEstateFiles(item) }
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
