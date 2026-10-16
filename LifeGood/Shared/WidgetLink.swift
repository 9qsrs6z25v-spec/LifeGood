import Foundation

// MARK: - 小工具網址（v25.545；v2 擴充）
//
// 這個檔案同時屬於「主 App」與「LifeGoodWidgets」兩個 target：
// 小工具用它組 widgetURL／Link 的網址，App 用它解析 onOpenURL 收到的網址，
// 兩邊永遠是同一份字串，不會一邊寫 "overview"、一邊寫 "總覽"。
//
// ⚠️ 只准用 Foundation 與 DayTimelineLink／TimelineStop（DayTimelineAttributes.swift）。
//    「解析完要切到哪一頁」碰得到 AppMode／ExpenseFeature，那段在 App 側
//    （DeepLinkRouter.swift 的 extension WidgetLink），不寫在這裡——v25.454 的教訓。
//
// 網址：
//   lifegood://expense/overview?src=widget   → 收支「總覽」
//   lifegood://today                         → 我的行事曆（靈動島既有，格式不變）
//   lifegood://today?stop=<場次 id>           → 那一場的卡片；旅遊景點開那一趟（靈動島既有）
//   [v2] 小工具點的 today 網址多帶 &src=widget（靈動島用 DayTimelineLink.url(for:)，不帶，不受影響）
//   [v2] lifegood://add/expense?src=widget                          → 新增支出（空白、數字鍵盤跳出）
//   [v2] lifegood://add/expense?cat=<分類>&src=widget                → 新增支出、分類帶好
//   [v2] lifegood://add/expense?vehicle=<車 UUID>&vcat=<車子分類>&src=widget → 例 Taycan 電費
//   [v2] lifegood://expense/fixed?src=widget、…/fixed?id=<支出 UUID>&src=widget → 固定支出頁（那一筆）
//   [v2] lifegood://finance/house?id=<房子 UUID>&src=widget            → 那一間房
//   [v2] lifegood://finance/vehicle?id=<車 UUID>&src=widget            → 那一台車
//   [v2] lifegood://finance/insurance?id=<保單 UUID>&src=widget        → 那一張保單
//   [v3] lifegood://add/expense?voice=1&src=widget                    → 說一句：不切頁，在哪一頁都直接開始聽
//                                                                       （voice=1 優先；同一個網址帶的 cat／vehicle 不看）
//   [v3] lifegood://add/income?src=widget                             → 新增收入（記帳台的「新增收入」按鈕）
//   [v3] lifegood://life/trip?id=<行程 UUID>&src=widget                → 旅遊地圖、打開那一份行程（旅行小工具）；
//                                                                       不帶 id＝只切到旅遊地圖
//   [v4] lifegood://finance/stock?id=<股票 UUID>&src=widget              → 理財「股票」、打開那一檔（股票今天小工具）
//   [v4] lifegood://finance/overview?src=widget                         → 理財「總覽」（淨資產小工具）
//   [v4] lifegood://settings/currency?src=widget                        → 設定、展開「自訂幣別匯率」（金價匯率小工具）
//   [v5] lifegood://life/team?src=widget                                → 部屬總覽（部屬今天小工具、今天（大）的部屬那幾行）
//   [v5] lifegood://life/team/task?sub=<部屬 UUID>&task=<任務 UUID>&src=widget → 部屬總覽、打開那件任務的預覽卡片
//                                                                       （SubordinateItemCard；兩個 id 少一個就只開部屬總覽）
//   [v5] lifegood://life/birthdays?src=widget                           → 部屬總覽、打開生日名單（BirthdayOverviewSheet）
//   [v5] lifegood://life/family/tasks?src=widget                        → 人生「家庭」（家庭待辦在這一頁）
//
// 分類、車子分類的值是 App 寫進快照的 rawValue（VariableCategory／VehicleVariableCategory），
// 小工具原樣帶回；URLComponents 會自己做百分比編碼，中文沒問題。

/// 點小工具要去哪
enum WidgetDestination: Equatable {
    /// 收支「總覽」
    case expenseOverview
    /// 我的行事曆；帶場次 id 就打開那一場（id 格式見 DayTimelineController／TodayAgenda 的 stopId）
    case today(stopId: String?)
    /// [v2] 新增支出（變動）。三個都 nil＝空白表單；categoryKey＝VariableCategory.rawValue；
    /// vehicleId＋vehicleCategoryKey（VehicleVariableCategory.rawValue）＝從車子記（例 Taycan 電費）
    case addExpense(categoryKey: String?, vehicleId: UUID?, vehicleCategoryKey: String?)
    /// [v2] 收支「固定支出」；帶 id 就打開那一筆
    case fixedExpense(id: UUID?)
    /// [v2] 理財「房地產」；帶 id 就打開那一間
    case financeHouse(id: UUID?)
    /// [v2] 理財「載具」；帶 id 就打開那一台
    case financeVehicle(id: UUID?)
    /// [v2] 理財「儲蓄險」；帶 id 就打開那一張
    case financeInsurance(id: UUID?)
    /// [v3] 說一句：不切頁，在目前這一頁直接開始聽（按一下開始、講完自動停），聽完 AI 解析、存檔、跳「已記一筆」
    case voiceRecord
    /// [v3] 新增收入（記帳台按鈕）
    case addIncome
    /// [v3] 人生「旅遊地圖」；帶 id 就打開那一份行程（旅行小工具）
    case trip(id: UUID?)
    /// [v4] 理財「股票」；帶 id 就打開那一檔的股票卡片（StockDetailView）
    case financeStock(id: UUID?)
    /// [v4] 理財「總覽」
    case financeOverview
    /// [v4] 設定頁、展開「自訂幣別匯率」（不換 routeToken：不能先把設定頁關掉）
    case settingsCurrency
    /// [v5] 人生 › 職涯 › 部屬總覽
    case team
    /// [v5] 部屬總覽、打開那件任務的預覽卡片（SubordinateItemCard）
    case teamTask(subId: UUID, taskId: UUID)
    /// [v5] 部屬總覽、打開生日名單（BirthdayOverviewSheet：部屬＋組織人員）
    case birthdays
    /// [v5] 人生「家庭」（FamilyView：家庭待辦在這一頁）
    case familyTasks
}

/// 解析結果：去哪＋是不是從小工具點進來的
struct WidgetRoute: Equatable {
    var destination: WidgetDestination
    /// 網址帶 src=widget（[v2] 拿來跳過開場動畫與「本次更新」視窗，新增支出的金額欄自動聚焦）。
    /// 靈動島的 today 網址不帶 src，是 false。
    var fromWidget: Bool
}

enum WidgetLink {
    static let scheme = "lifegood"
    static let sourceKey = "src"
    static let sourceWidget = "widget"

    private static let expenseHost = "expense"
    private static let overviewPath = "/overview"
    private static let todayHost = "today"
    private static let stopKey = "stop"
    // [v2]
    private static let addHost = "add"
    private static let expensePath = "/expense"
    private static let fixedPath = "/fixed"
    private static let financeHost = "finance"
    private static let housePath = "/house"
    private static let vehiclePath = "/vehicle"
    private static let insurancePath = "/insurance"
    private static let idKey = "id"
    private static let categoryKey = "cat"
    private static let vehicleKey = "vehicle"
    private static let vehicleCategoryKey = "vcat"
    // [v3]
    private static let voiceKey = "voice"
    private static let voiceOn = "1"
    private static let incomePath = "/income"
    private static let lifeHost = "life"
    private static let tripPath = "/trip"
    // [v4]
    private static let stockPath = "/stock"
    private static let settingsHost = "settings"
    private static let currencyPath = "/currency"
    // [v5]
    private static let teamPath = "/team"
    private static let teamTaskPath = "/team/task"
    private static let birthdaysPath = "/birthdays"
    private static let familyTasksPath = "/family/tasks"
    private static let subKey = "sub"
    private static let taskKey = "task"

    /// 組不出網址時的退路（不會發生：全部是固定的 ASCII 字）
    private static let fallback = URL(string: "lifegood://today")!

    // MARK: 組

    /// 組網址。fromWidget 為 true 時帶 src=widget（today 也帶；靈動島不走這裡）。
    static func url(for destination: WidgetDestination, fromWidget: Bool = true) -> URL {
        var comps = URLComponents()
        comps.scheme = scheme
        var items: [URLQueryItem] = []
        switch destination {
        case .expenseOverview:
            comps.host = expenseHost
            comps.path = overviewPath
        case .today(let stopId):
            // 跟 DayTimelineLink.url(for:) 同一個格式：lifegood://today?stop=<id>
            comps.host = todayHost
            if let stopId, !stopId.isEmpty {
                items.append(URLQueryItem(name: stopKey, value: stopId))
            }
        case .addExpense(let cat, let vehicleId, let vcat):
            comps.host = addHost
            comps.path = expensePath
            if let cat, !cat.isEmpty {
                items.append(URLQueryItem(name: categoryKey, value: cat))
            }
            if let vehicleId {
                items.append(URLQueryItem(name: vehicleKey, value: vehicleId.uuidString))
            }
            if let vcat, !vcat.isEmpty {
                items.append(URLQueryItem(name: vehicleCategoryKey, value: vcat))
            }
        case .fixedExpense(let id):
            comps.host = expenseHost
            comps.path = fixedPath
            appendId(id, to: &items)
        case .financeHouse(let id):
            comps.host = financeHost
            comps.path = housePath
            appendId(id, to: &items)
        case .financeVehicle(let id):
            comps.host = financeHost
            comps.path = vehiclePath
            appendId(id, to: &items)
        case .financeInsurance(let id):
            comps.host = financeHost
            comps.path = insurancePath
            appendId(id, to: &items)
        case .voiceRecord:
            comps.host = addHost
            comps.path = expensePath
            items.append(URLQueryItem(name: voiceKey, value: voiceOn))
        case .addIncome:
            comps.host = addHost
            comps.path = incomePath
        case .trip(let id):
            comps.host = lifeHost
            comps.path = tripPath
            appendId(id, to: &items)
        case .financeStock(let id):
            comps.host = financeHost
            comps.path = stockPath
            appendId(id, to: &items)
        case .financeOverview:
            comps.host = financeHost
            comps.path = overviewPath
        case .settingsCurrency:
            comps.host = settingsHost
            comps.path = currencyPath
        case .team:
            comps.host = lifeHost
            comps.path = teamPath
        case .teamTask(let subId, let taskId):
            comps.host = lifeHost
            comps.path = teamTaskPath
            items.append(URLQueryItem(name: subKey, value: subId.uuidString))
            items.append(URLQueryItem(name: taskKey, value: taskId.uuidString))
        case .birthdays:
            comps.host = lifeHost
            comps.path = birthdaysPath
        case .familyTasks:
            comps.host = lifeHost
            comps.path = familyTasksPath
        }
        if fromWidget {
            items.append(URLQueryItem(name: sourceKey, value: sourceWidget))
        }
        if !items.isEmpty { comps.queryItems = items }
        return comps.url ?? fallback
    }

    private static func appendId(_ id: UUID?, to items: inout [URLQueryItem]) {
        if let id {
            items.append(URLQueryItem(name: idKey, value: id.uuidString))
        }
    }

    /// 「還能花」整塊：lifegood://expense/overview?src=widget
    static var expenseOverview: URL { url(for: .expenseOverview) }

    /// 「今天」：有場次就開那一場，nil 就只開我的行事曆（lifegood://today?src=widget）
    static func today(_ stop: TimelineStop?) -> URL {
        url(for: .today(stopId: stop?.id))
    }

    /// [v2] 新增支出。全部不帶＝空白表單（控制項「記一筆」、記帳台「＋ 記一筆」）
    static func addExpense(categoryKey: String? = nil, vehicleId: UUID? = nil,
                           vehicleCategoryKey: String? = nil) -> URL {
        url(for: .addExpense(categoryKey: categoryKey, vehicleId: vehicleId,
                             vehicleCategoryKey: vehicleCategoryKey))
    }

    /// [v2] 固定支出頁（接下來要繳的標題那一行）
    static var fixedExpenses: URL { url(for: .fixedExpense(id: nil)) }

    /// [v2] 固定支出頁、打開那一筆
    static func fixedExpense(_ id: UUID) -> URL { url(for: .fixedExpense(id: id)) }

    /// [v2] 那一間房／那一台車／那一張保單
    static func financeHouse(_ id: UUID) -> URL { url(for: .financeHouse(id: id)) }
    static func financeVehicle(_ id: UUID) -> URL { url(for: .financeVehicle(id: id)) }
    static func financeInsurance(_ id: UUID) -> URL { url(for: .financeInsurance(id: id)) }

    /// [v3] 說一句：lifegood://add/expense?voice=1&src=widget（控制項「說一句」、記帳台「🎤 說一句」）
    static var voiceRecord: URL { url(for: .voiceRecord) }

    /// [v3] 新增收入：lifegood://add/income?src=widget
    static var addIncome: URL { url(for: .addIncome) }

    /// [v3] 那一趟旅行：lifegood://life/trip?id=<UUID>&src=widget；nil＝只切到旅遊地圖
    static func trip(_ id: UUID?) -> URL { url(for: .trip(id: id)) }

    /// [v4] 那一檔股票：lifegood://finance/stock?id=<UUID>&src=widget
    static func financeStock(_ id: UUID) -> URL { url(for: .financeStock(id: id)) }

    /// [v4] 理財「股票」頁（沒有持股時股票小工具點了去這裡）：lifegood://finance/stock?src=widget
    static var financeStocks: URL { url(for: .financeStock(id: nil)) }

    /// [v4] 理財總覽：lifegood://finance/overview?src=widget
    static var financeOverview: URL { url(for: .financeOverview) }

    /// [v4] 理財「載具」頁（沒有車時我的車小工具點了去這裡）：lifegood://finance/vehicle?src=widget
    static var financeVehicles: URL { url(for: .financeVehicle(id: nil)) }

    /// [v4] 設定 › 自訂幣別匯率：lifegood://settings/currency?src=widget
    static var settingsCurrency: URL { url(for: .settingsCurrency) }

    /// [v5] 部屬總覽：lifegood://life/team?src=widget
    static var team: URL { url(for: .team) }

    /// [v5] 部屬總覽、打開那件任務：lifegood://life/team/task?sub=<UUID>&task=<UUID>&src=widget
    static func teamTask(subId: UUID, taskId: UUID) -> URL {
        url(for: .teamTask(subId: subId, taskId: taskId))
    }

    /// [v5] 生日名單：lifegood://life/birthdays?src=widget
    static var birthdays: URL { url(for: .birthdays) }

    /// [v5] 家庭（家庭待辦）：lifegood://life/family/tasks?src=widget
    static var familyTasks: URL { url(for: .familyTasks) }

    // MARK: 解析

    /// 認得的網址回 WidgetRoute；別的（不是 lifegood://、不認得的頁）回 nil。
    static func parse(_ url: URL) -> WidgetRoute? {
        guard url.scheme == scheme,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = comps.queryItems ?? []
        let fromWidget = items.contains { $0.name == sourceKey && $0.value == sourceWidget }
        let host = comps.host ?? ""
        let path = comps.path
        guard let dest = resolveDestination(host: host, path: path, items: items, url: url) else {
            return nil
        }
        return WidgetRoute(destination: dest, fromWidget: fromWidget)
    }

    private static func resolveDestination(host: String, path: String, items: [URLQueryItem],
                                           url: URL) -> WidgetDestination? {
        switch host {
        case todayHost:
            // 場次 id 的取法跟靈動島同一支（空字串當作沒帶）
            return .today(stopId: DayTimelineLink.stopId(from: url))
        case expenseHost:
            if path == overviewPath || path.isEmpty || path == "/" { return .expenseOverview }
            if path == fixedPath { return .fixedExpense(id: uuidValue(idKey, in: items)) }
            return nil
        case addHost:
            if path == incomePath { return .addIncome }
            guard path == expensePath else { return nil }
            if textValue(voiceKey, in: items) == voiceOn { return .voiceRecord }
            return .addExpense(categoryKey: textValue(categoryKey, in: items),
                               vehicleId: uuidValue(vehicleKey, in: items),
                               vehicleCategoryKey: textValue(vehicleCategoryKey, in: items))
        case financeHost:
            let id = uuidValue(idKey, in: items)
            if path == housePath { return .financeHouse(id: id) }
            if path == vehiclePath { return .financeVehicle(id: id) }
            if path == insurancePath { return .financeInsurance(id: id) }
            if path == stockPath { return .financeStock(id: id) }
            if path == overviewPath { return .financeOverview }
            return nil
        case settingsHost:
            if path == currencyPath { return .settingsCurrency }
            return nil
        case lifeHost:
            if path == tripPath { return .trip(id: uuidValue(idKey, in: items)) }
            if path == teamPath { return .team }
            if path == teamTaskPath {
                // 兩個 id 少一個（網址被截斷、舊版）：只開部屬總覽
                guard let sub = uuidValue(subKey, in: items),
                      let task = uuidValue(taskKey, in: items) else { return .team }
                return .teamTask(subId: sub, taskId: task)
            }
            if path == birthdaysPath { return .birthdays }
            if path == familyTasksPath { return .familyTasks }
            return nil
        default:
            return nil
        }
    }

    /// 查詢字串裡的值；沒帶或空字串回 nil
    private static func textValue(_ name: String, in items: [URLQueryItem]) -> String? {
        let raw = items.first { $0.name == name }?.value ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 查詢字串裡的 UUID；沒帶或不是 UUID 回 nil
    private static func uuidValue(_ name: String, in items: [URLQueryItem]) -> UUID? {
        guard let raw = textValue(name, in: items) else { return nil }
        return UUID(uuidString: raw)
    }
}
