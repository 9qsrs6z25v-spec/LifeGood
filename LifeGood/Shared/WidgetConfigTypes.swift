import Foundation
import AppIntents

// MARK: - 小工具長按設定、控制項設定用的選項（小工具 v3）
//
// 這個檔案同時屬於「主 App」與「LifeGoodWidgets」兩個 target（主控契約，三組都不准改）。
// 規格：scratchpad/widgets/v3/brief.md §3；judge.md §3.5（J:493-494）。
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
