import Foundation

// MARK: - 健康檔案（本人）
// 單一物件（比照 UserProfile）存於 LifeStore.healthProfile，UserDefaults key "life_health_profile"。
// 內含靜態欄位（血型 / 身高 / 過敏 / 病史 / 用藥）＋時間序列量測（體重 / 血壓 / 心率）＋健檢紀錄。
// 為醫療地圖「健康狀況總結」的資料基礎（階段 2/3）。
//
// 所有型別皆採「逐欄位容錯解碼」（decodeIfPresent + 預設值），避免日後新增欄位時，
// 舊版 JSON 少欄位造成整個 healthProfile 解碼失敗、被當空物件覆蓋雲端資料。

// MARK: - 過敏紀錄

struct HealthAllergy: Identifiable, Codable {
    let id: UUID
    var name: String                 // 過敏原（藥物 / 食物 / 環境…）
    var reaction: String             // 過敏反應描述
    var severity: AllergySeverity?   // 重用既有 輕度 / 中度 / 重度

    init(id: UUID = UUID(), name: String = "", reaction: String = "", severity: AllergySeverity? = nil) {
        self.id = id; self.name = name; self.reaction = reaction; self.severity = severity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        reaction = (try? c.decode(String.self, forKey: .reaction)) ?? ""
        severity = try? c.decodeIfPresent(AllergySeverity.self, forKey: .severity)
    }
    private enum CodingKeys: String, CodingKey { case id, name, reaction, severity }
}

// MARK: - 用藥紀錄

struct HealthMedication: Identifiable, Codable {
    let id: UUID
    var name: String        // 藥名
    var dosage: String      // 劑量 / 頻率（例：500mg 每日兩次）
    var note: String
    var isActive: Bool      // 是否仍在服用

    init(id: UUID = UUID(), name: String = "", dosage: String = "", note: String = "", isActive: Bool = true) {
        self.id = id; self.name = name; self.dosage = dosage; self.note = note; self.isActive = isActive
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        dosage = (try? c.decode(String.self, forKey: .dosage)) ?? ""
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        isActive = (try? c.decode(Bool.self, forKey: .isActive)) ?? true
    }
    private enum CodingKeys: String, CodingKey { case id, name, dosage, note, isActive }
}

// MARK: - 量測紀錄（時間序列：體重 / 血壓 / 心率）

struct HealthMeasurement: Identifiable, Codable {
    let id: UUID
    var date: Date
    var weightKg: Double?    // 體重（公斤）
    var systolic: Int?       // 收縮壓
    var diastolic: Int?      // 舒張壓
    var heartRate: Int?      // 心率（bpm）
    var note: String

    init(id: UUID = UUID(), date: Date = Date(), weightKg: Double? = nil,
         systolic: Int? = nil, diastolic: Int? = nil, heartRate: Int? = nil, note: String = "") {
        self.id = id; self.date = date; self.weightKg = weightKg
        self.systolic = systolic; self.diastolic = diastolic; self.heartRate = heartRate; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        date = (try? c.decode(Date.self, forKey: .date)) ?? Date()
        weightKg = try? c.decodeIfPresent(Double.self, forKey: .weightKg)
        systolic = try? c.decodeIfPresent(Int.self, forKey: .systolic)
        diastolic = try? c.decodeIfPresent(Int.self, forKey: .diastolic)
        heartRate = try? c.decodeIfPresent(Int.self, forKey: .heartRate)
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
    }
    private enum CodingKeys: String, CodingKey { case id, date, weightKg, systolic, diastolic, heartRate, note }

    /// 是否含有血壓資料
    var hasBloodPressure: Bool { systolic != nil && diastolic != nil }
}

// MARK: - 健檢紀錄

struct HealthCheckup: Identifiable, Codable {
    let id: UUID
    var date: Date
    var title: String        // 健檢名稱 / 項目（例：年度健檢、抽血）
    var place: String        // 院所
    var result: String       // 結果摘要 / 結論
    var note: String
    var nextDueDate: Date?    // 下次建議回診 / 追蹤日

    init(id: UUID = UUID(), date: Date = Date(), title: String = "", place: String = "",
         result: String = "", note: String = "", nextDueDate: Date? = nil) {
        self.id = id; self.date = date; self.title = title; self.place = place
        self.result = result; self.note = note; self.nextDueDate = nextDueDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        date = (try? c.decode(Date.self, forKey: .date)) ?? Date()
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        place = (try? c.decode(String.self, forKey: .place)) ?? ""
        result = (try? c.decode(String.self, forKey: .result)) ?? ""
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        nextDueDate = try? c.decodeIfPresent(Date.self, forKey: .nextDueDate)
    }
    private enum CodingKeys: String, CodingKey { case id, date, title, place, result, note, nextDueDate }
}

// MARK: - 健康檔案（彙整）

struct HealthProfile: Codable {
    var bloodType: String                    // 血型（例：A、O、AB+）
    var heightCm: Double                     // 身高（公分）；0 表示未填
    var allergies: [HealthAllergy]
    var conditions: [String]                 // 慢性病 / 病史（自由文字）
    var medications: [HealthMedication]
    var measurements: [HealthMeasurement]    // 體重 / 血壓等時間序列
    var checkups: [HealthCheckup]
    var note: String                         // 備註

    init(bloodType: String = "", heightCm: Double = 0,
         allergies: [HealthAllergy] = [], conditions: [String] = [],
         medications: [HealthMedication] = [], measurements: [HealthMeasurement] = [],
         checkups: [HealthCheckup] = [], note: String = "") {
        self.bloodType = bloodType; self.heightCm = heightCm
        self.allergies = allergies; self.conditions = conditions
        self.medications = medications; self.measurements = measurements
        self.checkups = checkups; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bloodType = (try? c.decode(String.self, forKey: .bloodType)) ?? ""
        heightCm = (try? c.decode(Double.self, forKey: .heightCm)) ?? 0
        allergies = (try? c.decodeIfPresent([HealthAllergy].self, forKey: .allergies)) ?? []
        conditions = (try? c.decodeIfPresent([String].self, forKey: .conditions)) ?? []
        medications = (try? c.decodeIfPresent([HealthMedication].self, forKey: .medications)) ?? []
        measurements = (try? c.decodeIfPresent([HealthMeasurement].self, forKey: .measurements)) ?? []
        checkups = (try? c.decodeIfPresent([HealthCheckup].self, forKey: .checkups)) ?? []
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
    }
    private enum CodingKeys: String, CodingKey {
        case bloodType, heightCm, allergies, conditions, medications, measurements, checkups, note
    }

    // MARK: - 衍生摘要（供「健康狀況總結」使用）

    /// 是否完全空白（決定是否顯示醫療地圖的健康摘要、以及合併匯入時是否覆蓋）
    var isEmpty: Bool {
        bloodType.isEmpty && heightCm == 0 && allergies.isEmpty && conditions.isEmpty
        && medications.isEmpty && measurements.isEmpty && checkups.isEmpty && note.isEmpty
    }

    /// 最近一次含體重的量測
    var latestWeight: (date: Date, kg: Double)? {
        measurements.filter { $0.weightKg != nil }
            .max(by: { $0.date < $1.date })
            .flatMap { m in m.weightKg.map { (m.date, $0) } }
    }

    /// 最近一次血壓
    var latestBloodPressure: (date: Date, systolic: Int, diastolic: Int)? {
        measurements.filter { $0.hasBloodPressure }
            .max(by: { $0.date < $1.date })
            .flatMap { m in
                guard let s = m.systolic, let d = m.diastolic else { return nil }
                return (m.date, s, d)
            }
    }

    /// BMI＝體重(kg) / 身高(m)²；需身高與最近體重皆有值
    var bmi: Double? {
        guard heightCm > 0, let w = latestWeight?.kg else { return nil }
        let m = heightCm / 100
        return w / (m * m)
    }

    /// BMI 分級（台灣標準）
    var bmiCategory: String? {
        guard let b = bmi else { return nil }
        switch b {
        case ..<18.5: return "過輕"
        case 18.5..<24: return "正常"
        case 24..<27: return "過重"
        default: return "肥胖"
        }
    }

    /// 仍在服用的藥物
    var activeMedications: [HealthMedication] { medications.filter { $0.isActive } }

    /// 最近一次健檢
    var lastCheckup: HealthCheckup? { checkups.max(by: { $0.date < $1.date }) }

    /// 下一個尚未到期的回診 / 追蹤日
    var nextDue: (checkup: HealthCheckup, date: Date)? {
        let now = Date()
        return checkups.compactMap { c in c.nextDueDate.map { (c, $0) } }
            .filter { $0.1 >= now }
            .min(by: { $0.1 < $1.1 })
            .map { (checkup: $0.0, date: $0.1) }
    }
}
