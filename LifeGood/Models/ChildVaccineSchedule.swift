import Foundation

// MARK: - 兒童疫苗接種時程（台灣常規疫苗）
//
// 依衛福部疾管署現行「兒童常規疫苗接種時程」整理的靜態清單，
// 搭配孩子的出生日期即可推算每一劑的「建議接種日」，作為施打規劃參考。
// 實際完成與否由使用者填入「施打日期」決定（有日期＝已完成、無日期＝尚未施打）。

/// 單一疫苗劑次（靜態時程資料，不隨使用者資料變動）。
struct VaccineScheduleItem: Identifiable {
    /// 穩定字串識別碼（供 VaccineDose 對應，改名/改版都不影響對應）。
    let id: String
    /// 疫苗名稱，如「五合一」。
    let name: String
    /// 劑次，如「第 1 劑」「追加」。
    let dose: String
    /// 建議接種月齡（0 = 出生）。
    let ageMonths: Int
    /// 月齡顯示標籤，如「出生 24 小時內」「滿 2 個月」。
    let ageLabel: String
    /// 分期標題（供分組顯示）。
    let stage: String
    /// 自費疫苗（非公費常規）。
    let optional: Bool
    /// 每年接種（如流感），此類不做逾期提醒。
    let recurring: Bool
    /// 補充說明。
    let note: String

    init(id: String, name: String, dose: String, ageMonths: Int, ageLabel: String,
         stage: String, optional: Bool = false, recurring: Bool = false, note: String = "") {
        self.id = id; self.name = name; self.dose = dose
        self.ageMonths = ageMonths; self.ageLabel = ageLabel; self.stage = stage
        self.optional = optional; self.recurring = recurring; self.note = note
    }

    /// 依出生日期推算建議接種日；未設生日則回 nil。
    func recommendedDate(birthday: Date?, calendar: Calendar = .current) -> Date? {
        guard let birthday else { return nil }
        return calendar.date(byAdding: .month, value: ageMonths, to: birthday)
    }
}

enum VaccineSchedule {
    /// 台灣兒童常規疫苗接種時程（含少數常見自費項目，以 optional 標示）。
    static let taiwan: [VaccineScheduleItem] = [
        // 出生
        .init(id: "hepb-1", name: "B 型肝炎", dose: "第 1 劑", ageMonths: 0, ageLabel: "出生 24 小時內", stage: "出生"),
        // 1 個月
        .init(id: "hepb-2", name: "B 型肝炎", dose: "第 2 劑", ageMonths: 1, ageLabel: "滿 1 個月", stage: "1 個月"),
        // 2 個月
        .init(id: "five-1", name: "五合一", dose: "第 1 劑", ageMonths: 2, ageLabel: "滿 2 個月", stage: "2 個月",
              note: "白喉、破傷風、百日咳、b 型嗜血桿菌、小兒麻痺"),
        .init(id: "pcv-1", name: "13 價肺炎鏈球菌", dose: "第 1 劑", ageMonths: 2, ageLabel: "滿 2 個月", stage: "2 個月"),
        .init(id: "rota-1", name: "輪狀病毒", dose: "第 1 劑", ageMonths: 2, ageLabel: "滿 2 個月", stage: "2 個月",
              optional: true, note: "口服、自費；視廠牌為 2 或 3 劑"),
        // 4 個月
        .init(id: "five-2", name: "五合一", dose: "第 2 劑", ageMonths: 4, ageLabel: "滿 4 個月", stage: "4 個月"),
        .init(id: "pcv-2", name: "13 價肺炎鏈球菌", dose: "第 2 劑", ageMonths: 4, ageLabel: "滿 4 個月", stage: "4 個月"),
        .init(id: "rota-2", name: "輪狀病毒", dose: "第 2 劑", ageMonths: 4, ageLabel: "滿 4 個月", stage: "4 個月",
              optional: true, note: "口服、自費"),
        // 5 個月
        .init(id: "bcg", name: "卡介苗", dose: "單劑", ageMonths: 5, ageLabel: "滿 5 個月（5–8 個月）", stage: "5 個月",
              note: "預防結核病"),
        // 6 個月
        .init(id: "hepb-3", name: "B 型肝炎", dose: "第 3 劑", ageMonths: 6, ageLabel: "滿 6 個月", stage: "6 個月"),
        .init(id: "five-3", name: "五合一", dose: "第 3 劑", ageMonths: 6, ageLabel: "滿 6 個月", stage: "6 個月"),
        .init(id: "flu", name: "流感疫苗", dose: "每年", ageMonths: 6, ageLabel: "滿 6 個月起", stage: "6 個月",
              recurring: true, note: "滿 6 個月起，每年接種一次"),
        // 12 個月
        .init(id: "pcv-3", name: "13 價肺炎鏈球菌", dose: "第 3 劑", ageMonths: 12, ageLabel: "滿 12 個月", stage: "12 個月"),
        .init(id: "mmr-1", name: "MMR", dose: "第 1 劑", ageMonths: 12, ageLabel: "滿 12 個月", stage: "12 個月",
              note: "麻疹、腮腺炎、德國麻疹"),
        .init(id: "varicella", name: "水痘", dose: "單劑", ageMonths: 12, ageLabel: "滿 12 個月", stage: "12 個月"),
        .init(id: "hepa-1", name: "A 型肝炎", dose: "第 1 劑", ageMonths: 12, ageLabel: "滿 12 個月", stage: "12 個月"),
        // 15 個月
        .init(id: "je-1", name: "日本腦炎", dose: "第 1 劑", ageMonths: 15, ageLabel: "滿 15 個月", stage: "15 個月",
              note: "細胞培養不活化疫苗"),
        // 18 個月
        .init(id: "five-4", name: "五合一", dose: "第 4 劑", ageMonths: 18, ageLabel: "滿 18 個月", stage: "18 個月"),
        .init(id: "hepa-2", name: "A 型肝炎", dose: "第 2 劑", ageMonths: 18, ageLabel: "滿 18 個月", stage: "18 個月",
              note: "與第 1 劑間隔 6 個月以上"),
        // 27 個月
        .init(id: "je-2", name: "日本腦炎", dose: "第 2 劑", ageMonths: 27, ageLabel: "滿 2 歲 3 個月", stage: "27 個月",
              note: "與第 1 劑間隔 12 個月"),
        // 滿 5 歲至入小學前
        .init(id: "dtap-ipv", name: "四合一", dose: "追加", ageMonths: 60, ageLabel: "滿 5 歲至入小學前", stage: "滿 5 歲–入學前",
              note: "白喉、破傷風、百日咳、小兒麻痺"),
        .init(id: "mmr-2", name: "MMR", dose: "第 2 劑", ageMonths: 60, ageLabel: "滿 5 歲至入小學前", stage: "滿 5 歲–入學前"),
        .init(id: "je-3", name: "日本腦炎", dose: "第 3 劑", ageMonths: 60, ageLabel: "滿 5 歲至入小學前", stage: "滿 5 歲–入學前")
    ]

    /// 依 stage 分組（保持 taiwan 陣列的原始順序）。
    static var groupedByStage: [(stage: String, items: [VaccineScheduleItem])] {
        var order: [String] = []
        var map: [String: [VaccineScheduleItem]] = [:]
        for item in taiwan {
            if map[item.stage] == nil { order.append(item.stage) }
            map[item.stage, default: []].append(item)
        }
        return order.map { ($0, map[$0] ?? []) }
    }
}

// MARK: - 疫苗施打狀態（使用者資料）

/// 記錄某一劑疫苗的施打狀態；administeredDate 有值＝已施打，nil＝尚未施打。
struct VaccineDose: Identifiable, Codable {
    let id: UUID
    /// 對應 VaccineScheduleItem.id。
    var scheduleId: String
    /// 施打日期；nil = 尚未施打。
    var administeredDate: Date?
    /// 備註（如接種院所、反應、提醒等）。
    var note: String

    init(id: UUID = UUID(), scheduleId: String, administeredDate: Date? = nil, note: String = "") {
        self.id = id
        self.scheduleId = scheduleId
        self.administeredDate = administeredDate
        self.note = note
    }

    var isDone: Bool { administeredDate != nil }
}
