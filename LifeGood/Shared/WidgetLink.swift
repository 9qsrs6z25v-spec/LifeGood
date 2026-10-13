import Foundation

// MARK: - 小工具網址（v25.545）
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

/// 點小工具要去哪
enum WidgetDestination: Equatable {
    /// 收支「總覽」
    case expenseOverview
    /// 我的行事曆；帶場次 id 就打開那一場（id 格式見 DayTimelineController／TodayAgenda 的 stopId）
    case today(stopId: String?)
}

/// 解析結果：去哪＋是不是從小工具點進來的
struct WidgetRoute: Equatable {
    var destination: WidgetDestination
    /// 網址帶 src=widget。v1 只解析、不使用；v2 起拿來跳過開場動畫與「本次更新」視窗。
    /// 今天的網址沿用靈動島的格式、不帶 src，所以從「今天」小工具點進來這裡是 false。
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

    /// 組不出網址時的退路（不會發生：全部是固定的 ASCII 字）
    private static let fallback = URL(string: "lifegood://today")!

    // MARK: 組

    /// 組網址。fromWidget 只影響收支這類新網址；today 一律沿用靈動島的格式。
    static func url(for destination: WidgetDestination, fromWidget: Bool = true) -> URL {
        var comps = URLComponents()
        comps.scheme = scheme
        var items: [URLQueryItem] = []
        switch destination {
        case .expenseOverview:
            comps.host = expenseHost
            comps.path = overviewPath
            if fromWidget {
                items.append(URLQueryItem(name: sourceKey, value: sourceWidget))
            }
        case .today(let stopId):
            // 跟 DayTimelineLink.url(for:) 同一個格式：lifegood://today?stop=<id>
            comps.host = todayHost
            if let stopId, !stopId.isEmpty {
                items.append(URLQueryItem(name: stopKey, value: stopId))
            }
        }
        if !items.isEmpty { comps.queryItems = items }
        return comps.url ?? fallback
    }

    /// 「還能花」整塊：lifegood://expense/overview?src=widget
    static var expenseOverview: URL { url(for: .expenseOverview) }

    /// 「今天」：有場次就開那一場，nil 就只開我的行事曆（lifegood://today）
    static func today(_ stop: TimelineStop?) -> URL {
        url(for: .today(stopId: stop?.id))
    }

    // MARK: 解析

    /// 認得的網址回 WidgetRoute；別的（不是 lifegood://、不認得的頁）回 nil。
    static func parse(_ url: URL) -> WidgetRoute? {
        guard url.scheme == scheme,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = comps.queryItems ?? []
        let fromWidget = items.contains { $0.name == sourceKey && $0.value == sourceWidget }
        let host = comps.host ?? ""
        let path = comps.path
        if host == todayHost {
            // 場次 id 的取法跟靈動島同一支（空字串當作沒帶）
            return WidgetRoute(destination: .today(stopId: DayTimelineLink.stopId(from: url)),
                               fromWidget: fromWidget)
        }
        if host == expenseHost, path == overviewPath || path.isEmpty || path == "/" {
            return WidgetRoute(destination: .expenseOverview, fromWidget: fromWidget)
        }
        return nil
    }
}
