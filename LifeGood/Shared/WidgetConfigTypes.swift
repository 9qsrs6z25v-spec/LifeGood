import Foundation
import AppIntents

// MARK: - 小工具長按設定、控制項設定用的選項（小工具 v3）
//
// 這個檔案同時屬於「主 App」與「LifeGoodWidgets」兩個 target（主控契約，三組都不准改）。
// 規格：scratchpad/widgets/v3/brief.md §3；judge.md §3.5（J:493-494）。
// [v4] 檔尾加股票（WidgetStockEntity）、車子（WidgetVehicleEntity）、金價匯率（WidgetRateEntity、WidgetRateLineEntity），
//      選單從 finance_v1.json 讀（scratchpad/widgets/v4/brief.md §3.2）。
// [v5] 檔尾加部屬今天的廠區（WidgetPlantAreaEntity）：「全部」＋life_v1.json 的 plantAreas
//      （scratchpad/widgets/v5/brief.md §3.4）。設定 intent（TeamConfigIntent）在 LifeGoodWidgets/TeamWidget.swift。
//
// • AppEnum（固定幾個選項，編譯時就知道）：
//     WidgetAmountOption（金額：跟著總開關／這個小工具一律隱藏）
//     WidgetBillScopeOption（接下來要繳的範圍：全部／只看記帳／只看理財）
//     WidgetBillDaysOption（接下來要繳的天數：30／7）
// • AppEntity＋EntityQuery（選項要從快照讀：分類、每台車的車子分類）：
//     WidgetDeskButtonEntity（記帳台按鈕 1／2／3：自動、說一句、新增收入、14 個變動分類、每台車的車子分類）
//     WidgetRecordTargetEntity（控制項「記到…」：14 個變動分類、每台車的車子分類）
//   選單一律從 money 快照讀（WidgetMoneySnapshot.recordTargets()），不寫死任何分類、車名。
//   id 的規則在 WidgetSnapshot.swift 的 WidgetDeskChoice；畫卡、組網址在 WidgetMoneySnapshot.deskTiles(choiceIDs:)。
//
// 為什麼分類／車子用 AppEntity 不用 AppEnum：AppEnum 的選項是編譯時寫死的，車子（Taycan）與它的車子分類
// 只有 App 知道、會變；AppEntity 的 EntityQuery 每次打開設定畫面都重讀快照。金額、範圍、天數這種固定的
// 選項用 AppEnum（最單純、Xcode 範本同款寫法）。
//
// 為什麼放共用檔、兩個 target 都編：記帳台（G2）與控制項（G3）兩組都要用、id 規則只能有一份；
// App 這邊目前沒用到（編進來無害，之後設定頁或 Siri 要用同一組選項時不用再搬）。
// 小工具的設定 intent 本身（WidgetConfigurationIntent／ControlConfigurationIntent）只在小工具 target：
// LifeGoodWidgets/WidgetConfigs.swift（G2）、LifeGoodWidgets/LifeGoodControls.swift（G3）。
//
// ⚠️ 只准用 Foundation／AppIntents 與共用檔的型別（WidgetSnapshotStore、WidgetMoneySnapshot、WidgetDeskChoice、
//    WidgetRecordTarget、WidgetBillScope）。不准引用 App 才有的型別（VariableCategory、Vehicle…）。
// ⚠️ 寫法照 Xcode 的 App Intent 小工具範本與 iOS 16 起的 AppEntity 文件：static var＋字串字面值、
//    DisplayRepresentation(title: "\(name)")；不用 image、subtitle、synonyms 這些沒把握的參數。
//    instance 屬性不取名 title／description（跟 AppIntent 的 static 同名容易混）——選單上的字叫 name。

// MARK: - 金額

/// 「金額」：跟著「隱藏金額」總開關（預設），或這個小工具一律隱藏（還能花、記帳台、接下來要繳）
enum WidgetAmountOption: String, AppEnum {
    case followMaster
    case alwaysHide

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "金額"
    static var caseDisplayRepresentations: [WidgetAmountOption: DisplayRepresentation] = [
        .followMaster: "跟著「隱藏金額」開關",
        .alwaysHide: "這個小工具一律隱藏"
    ]

    /// 這個小工具要不要遮金額。master＝「隱藏金額」總開關（WidgetHideAmounts.isOn，provider 讀一次）
    func hides(master: Bool) -> Bool {
        self == .alwaysHide || master
    }
}

// MARK: - 接下來要繳

/// 「範圍」：全部（預設）／只看記帳的固定支出／只看理財
enum WidgetBillScopeOption: String, AppEnum {
    case all
    case ledger
    case finance

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "範圍"
    static var caseDisplayRepresentations: [WidgetBillScopeOption: DisplayRepresentation] = [
        .all: "全部",
        .ledger: "只看記帳的固定支出",
        .finance: "只看理財"
    ]

    /// 給 WidgetBillsSnapshot.upcoming(at:days:scope:)／next(at:scope:)
    var scope: WidgetBillScope {
        switch self {
        case .all:     return .all
        case .ledger:  return .ledger
        case .finance: return .finance
        }
    }
}

/// 「天數」：30 天（預設）／7 天
enum WidgetBillDaysOption: String, AppEnum {
    case days30
    case days7

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "天數"
    static var caseDisplayRepresentations: [WidgetBillDaysOption: DisplayRepresentation] = [
        .days30: "30 天",
        .days7: "7 天"
    ]

    /// 給 WidgetBillsSnapshot.upcoming(at:days:scope:)；標題「接下來 \(days) 天」
    var days: Int {
        switch self {
        case .days30: return 30
        case .days7:  return 7
        }
    }
}

// MARK: - 記帳台的按鈕

/// 記帳台按鈕 1／2／3 的一個選項。id 照 WidgetDeskChoice 的規則
///（"auto"、"voice"、"income"、"cat:<分類>"、"car:<車 UUID>:<車子分類>"）。
/// 設定 intent 的參數寫成 optional：nil、"auto"、快照裡找不到的 id 一律當「自動」（WidgetMoneySnapshot.deskTiles(choiceIDs:)）。
struct WidgetDeskButtonEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "記帳台按鈕"
    static var defaultQuery = WidgetDeskButtonQuery()

    var id: String
    /// 選單上的字（「自動（照最常記的挑）」「說一句」「飲食」「Taycan 電費」）
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    static let auto = WidgetDeskButtonEntity(id: WidgetDeskChoice.autoID, name: "自動（照最常記的挑）")
    static let voice = WidgetDeskButtonEntity(id: WidgetDeskChoice.voiceID, name: "說一句")
    static let income = WidgetDeskButtonEntity(id: WidgetDeskChoice.incomeID, name: "新增收入")

    /// 全部選項：自動、說一句、新增收入，再接 money 快照的「記到哪裡」（14 個變動分類、每台車的車子分類）。
    /// 還沒打開過新版 App（沒快照）時只有前三個
    static func all() -> [WidgetDeskButtonEntity] {
        var out: [WidgetDeskButtonEntity] = [auto, voice, income]
        let targets: [WidgetRecordTarget] = WidgetSnapshotStore.read(WidgetMoneySnapshot.self)?.recordTargets() ?? []
        for t in targets {
            out.append(WidgetDeskButtonEntity(id: t.id, name: t.title))
        }
        return out
    }
}

struct WidgetDeskButtonQuery: EntityQuery {
    init() {}

    /// 設定存的 id → 選項。找不到的（車子賣掉、刪掉）就不回，參數變 nil＝自動
    func entities(for identifiers: [WidgetDeskButtonEntity.ID]) async throws -> [WidgetDeskButtonEntity] {
        let all = WidgetDeskButtonEntity.all()
        return identifiers.compactMap { id in all.first(where: { $0.id == id }) }
    }

    /// 設定畫面的選單
    func suggestedEntities() async throws -> [WidgetDeskButtonEntity] {
        WidgetDeskButtonEntity.all()
    }

    /// 參數的預設值：自動（系統不採用的話參數是 nil，一樣當自動）
    func defaultResult() async -> WidgetDeskButtonEntity? {
        WidgetDeskButtonEntity.auto
    }
}

// MARK: - 控制項「記到…」

/// 控制項「記到…」的一個選項：一個變動分類，或一台車＋車子分類（id 同 WidgetRecordTarget.id）。
/// 控制項畫面要的網址、圖示，按的當下用 id 回 money 快照查（WidgetMoneySnapshot.recordTarget(id:)），
/// 車改名了也會跟著變；查不到（車賣掉、刪掉）退回空白的新增支出。
struct WidgetRecordTargetEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "記到"
    static var defaultQuery = WidgetRecordTargetQuery()

    var id: String
    /// 「飲食」「Taycan 電費」
    var name: String
    /// SF Symbol（「fork.knife」「bolt.fill」「parkingsign.circle」）
    var icon: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String, icon: String) {
        self.id = id
        self.name = name
        self.icon = icon
    }

    init(target t: WidgetRecordTarget) {
        self.init(id: t.id, name: t.title, icon: t.icon)
    }

    /// 全部選項（money 快照的「記到哪裡」）；沒快照是空陣列
    static func all() -> [WidgetRecordTargetEntity] {
        let targets: [WidgetRecordTarget] = WidgetSnapshotStore.read(WidgetMoneySnapshot.self)?.recordTargets() ?? []
        return targets.map { WidgetRecordTargetEntity(target: $0) }
    }
}

struct WidgetRecordTargetQuery: EntityQuery {
    init() {}

    func entities(for identifiers: [WidgetRecordTargetEntity.ID]) async throws -> [WidgetRecordTargetEntity] {
        let all = WidgetRecordTargetEntity.all()
        return identifiers.compactMap { id in all.first(where: { $0.id == id }) }
    }

    func suggestedEntities() async throws -> [WidgetRecordTargetEntity] {
        WidgetRecordTargetEntity.all()
    }
}

// MARK: - [v4] 股票今天、金價匯率、我的車（選單都從 finance_v1.json 讀）
//
// 設定 intent 本身只在小工具 target：股票、金價（G2）寫在 StockWidget.swift／RatesWidget.swift，
// 我的車、淨資產（G3）寫在 VehicleWidget.swift／NetWorthWidget.swift。參數一律 optional：
// nil＝預設（市值最大那一檔／市值前三／黃金每克／美金／第一台沒賣掉的車），選的東西賣掉、刪掉了（查不到）也當預設。

/// 股票小工具選哪一檔（小＝一檔；中＝第 1／2／3 檔）。id＝股票 UUID 字串
struct WidgetStockEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "股票"
    static var defaultQuery = WidgetStockQuery()

    var id: String
    /// 「2330 台積電」（WidgetFinanceStock.menuTitle）
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// 持有中的股票（finance 快照，市值大到小）；沒快照是空陣列
    static func all() -> [WidgetStockEntity] {
        let items: [WidgetFinanceStock] = WidgetSnapshotStore.read(WidgetFinanceSnapshot.self)?.stocks.items ?? []
        return items.map { WidgetStockEntity(id: $0.id.uuidString, name: $0.menuTitle) }
    }
}

struct WidgetStockQuery: EntityQuery {
    init() {}

    /// 找不到的（賣掉、刪掉）不回，參數變 nil＝預設
    func entities(for identifiers: [WidgetStockEntity.ID]) async throws -> [WidgetStockEntity] {
        let all = WidgetStockEntity.all()
        return identifiers.compactMap { id in all.first(where: { $0.id == id }) }
    }

    func suggestedEntities() async throws -> [WidgetStockEntity] {
        WidgetStockEntity.all()
    }
}

/// 我的車選哪一台。id＝車子 UUID 字串
struct WidgetVehicleEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "車子"
    static var defaultQuery = WidgetVehicleQuery()

    var id: String
    /// 「Taycan」；賣掉但還在扣的「Taycan（已售出）」
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// finance 快照裡的車（沒賣掉的在前）；沒快照是空陣列
    static func all() -> [WidgetVehicleEntity] {
        let cars: [WidgetFinanceVehicle] = WidgetSnapshotStore.read(WidgetFinanceSnapshot.self)?.vehicles ?? []
        return cars.map { car in
            WidgetVehicleEntity(id: car.id.uuidString, name: car.isSold ? car.name + "（已售出）" : car.name)
        }
    }
}

struct WidgetVehicleQuery: EntityQuery {
    init() {}

    func entities(for identifiers: [WidgetVehicleEntity.ID]) async throws -> [WidgetVehicleEntity] {
        let all = WidgetVehicleEntity.all()
        return identifiers.compactMap { id in all.first(where: { $0.id == id }) }
    }

    func suggestedEntities() async throws -> [WidgetVehicleEntity] {
        WidgetVehicleEntity.all()
    }
}

/// 金價匯率的大字顯示哪一個。id＝FXRateService 的代碼（「XAU」「XAU(錢)」「USD」…）
struct WidgetRateEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "金價匯率"
    static var defaultQuery = WidgetRateQuery()

    var id: String
    /// 「黃金 每克」「黃金 每台錢」「美金」
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// 黃金每克、黃金每台錢，再接設定「自訂幣別匯率」裡 App 認得的幣別（WidgetRatesBlock.choices()）。
    /// 沒快照只有兩種黃金
    static func all() -> [WidgetRateEntity] {
        let choices: [WidgetRateChoice] = WidgetSnapshotStore.read(WidgetFinanceSnapshot.self)?.rates.choices()
            ?? WidgetRatesBlock.goldChoices
        return choices.map { WidgetRateEntity(id: $0.code, name: $0.title) }
    }
}

struct WidgetRateQuery: EntityQuery {
    init() {}

    func entities(for identifiers: [WidgetRateEntity.ID]) async throws -> [WidgetRateEntity] {
        let all = WidgetRateEntity.all()
        return identifiers.compactMap { id in all.first(where: { $0.id == id }) }
    }

    func suggestedEntities() async throws -> [WidgetRateEntity] {
        WidgetRateEntity.all()
    }

    /// 預設：黃金每克（系統不採用的話參數是 nil，小工具一樣當黃金每克）
    func defaultResult() async -> WidgetRateEntity? {
        WidgetRateEntity.all().first { $0.id == WidgetRatesBlock.goldGramCode }
    }
}

/// 金價匯率下面那一行（小型「美金 32.15」、鎖定畫面長方形第二行）：不顯示，或一個幣別／黃金
struct WidgetRateLineEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "下面那一行"
    static var defaultQuery = WidgetRateLineQuery()

    /// 「不顯示」的 id（不叫 none：跟 Optional.none 撞名）
    static let offID = "off"
    static let off = WidgetRateLineEntity(id: offID, name: "不顯示")

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// 不顯示，再接 WidgetRateEntity.all() 同一份
    static func all() -> [WidgetRateLineEntity] {
        var out: [WidgetRateLineEntity] = [off]
        for e in WidgetRateEntity.all() {
            out.append(WidgetRateLineEntity(id: e.id, name: e.name))
        }
        return out
    }
}

struct WidgetRateLineQuery: EntityQuery {
    init() {}

    func entities(for identifiers: [WidgetRateLineEntity.ID]) async throws -> [WidgetRateLineEntity] {
        let all = WidgetRateLineEntity.all()
        return identifiers.compactMap { id in all.first(where: { $0.id == id }) }
    }

    func suggestedEntities() async throws -> [WidgetRateLineEntity] {
        WidgetRateLineEntity.all()
    }

    /// 預設：美金（自訂幣別匯率裡有才有）；沒有美金就不顯示。系統不採用的話參數是 nil，小工具照同一條規則
    func defaultResult() async -> WidgetRateLineEntity? {
        WidgetRateLineEntity.all().first { $0.id == WidgetRatesBlock.usdCode } ?? WidgetRateLineEntity.off
    }
}

// MARK: - [v5] 部屬今天的廠區（選單從 life_v1.json 的 plantAreas 讀）

/// 部屬今天看哪個廠區。id＝廠區字（Subordinate.plantArea 去頭尾空白）；「全部廠區」的 id 是 allID。
/// 設定 intent（TeamConfigIntent，TeamWidget.swift）的參數寫成 optional：nil、「全部廠區」、
/// 快照裡找不到的廠區（改名、刪掉）一律當全部
struct WidgetPlantAreaEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "廠區"
    static var defaultQuery = WidgetPlantAreaQuery()

    /// 「全部廠區」的 id（廠區是使用者自己打的字，不會剛好是這一串）
    static let allID = "__all__"
    static let allPlants = WidgetPlantAreaEntity(id: allID, name: "全部廠區")

    var id: String
    /// 選單上的字：「全部廠區」「A」「P1」
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// 給 WidgetLifeSnapshot.teamSummary(at:plantArea:)：全部廠區是 nil
    var plantFilter: String? {
        id == Self.allID ? nil : id
    }

    /// 全部廠區，再接快照的廠區清單；沒快照、舊檔、沒有任何廠區時只有「全部廠區」
    static func choices() -> [WidgetPlantAreaEntity] {
        var out: [WidgetPlantAreaEntity] = [allPlants]
        let areas: [String] = WidgetSnapshotStore.read(WidgetLifeSnapshot.self)?.plantAreas ?? []
        for area in areas {
            out.append(WidgetPlantAreaEntity(id: area, name: area))
        }
        return out
    }
}

struct WidgetPlantAreaQuery: EntityQuery {
    init() {}

    /// 找不到的（廠區改名、刪掉）不回，參數變 nil＝全部廠區
    func entities(for identifiers: [WidgetPlantAreaEntity.ID]) async throws -> [WidgetPlantAreaEntity] {
        let all = WidgetPlantAreaEntity.choices()
        return identifiers.compactMap { id in all.first(where: { $0.id == id }) }
    }

    func suggestedEntities() async throws -> [WidgetPlantAreaEntity] {
        WidgetPlantAreaEntity.choices()
    }

    /// 預設：全部廠區（系統不採用的話參數是 nil，小工具一樣當全部）
    func defaultResult() async -> WidgetPlantAreaEntity? {
        WidgetPlantAreaEntity.allPlants
    }
}
