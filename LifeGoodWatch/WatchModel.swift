import Foundation
import SwiftUI
import WidgetKit

// MARK: - 手錶 App 的狀態（手錶 v1，v25.574；watch/judge.md §2.0、§5.3、§5.6；watch/build/v1/brief.md §2、G2）
//
// 只屬於 LifeGoodWatch。手上那一包（手錶 App Group 的 watch_v1.json）、現在在哪一頁、推進去哪一層、
// 彈出頁、手錶自己的「遮住金額」。每一頁要畫的字不在這裡算：View 拿 package 叫 WatchText（Shared/WatchText.swift）。
// WatchSync（WCSessionDelegate，背景執行緒）收到包、寫好檔之後，一律 Task { @MainActor in } 叫這裡的 packageReceived()。
//
// 打開落在哪（judge §2.0）：一律第一頁（今天）；進背景時就把頁、層、彈出頁收回來，
// 錶面小格、通知點進來（onOpenURL、〔看議程〕）再開到那一頁那一件。
//
// [手錶 v2] v25.576（watch/build/v2/brief.md §2）：
//   • 彈出頁多「記一筆」（WatchSheet.record：② 錢〔＋ 記一筆〕、錶面「＋」lifegood://add/expense）
//   • 第二層多「今天記的帳」（WatchRoute.todayRecords：② 錢「今天 N 筆 ›」）、「手機條碼」（WatchRoute.barcode：② 錢左上 🧾）
//   • 待送盒（RecordOutbox）跟著畫面走：回前景重讀、把到期沒送的補送；手腕放下（inactive）、退到背景＝還在 10 秒內的馬上送
//     （judge §2.6「你點完成、翻走、或手腕放下時立刻送」）；收到新包重讀、補送

/// 垂直翻頁的頁（v1：① 今天、② 錢）
enum WatchPage: Hashable {
    case today
    case money
}

/// 推進去的第二層（NavigationStack(path:)）
enum WatchRoute: Hashable {
    /// 今天全部（judge §2.2）
    case dayList
    /// 一件事的細節（場次 id；judge §2.3）
    case stop(String)
    /// 接下來要繳（judge §2.5）
    case bills
    /// [v2] 今天記的帳（judge §2.7）
    case todayRecords
    /// [v2] 手機條碼（全螢幕白底，judge §2.8）
    case barcode
}

/// 彈出頁（sheet(item:)）
enum WatchSheet: String, Identifiable {
    /// ① 左上「⋯」設定（judge §2.15）
    case settings
    /// [v2] 記一筆（judge §2.6：記帳台 → 選分類 → 金額 → 記好了）
    case record

    var id: String { rawValue }
}

@MainActor
final class WatchModel: ObservableObject {
    static let shared = WatchModel()

    /// 手上那一包；還沒收過是 nil（① 寫「還沒收到 iPhone 的資料」〔再試一次〕）
    @Published private(set) var package: WatchPackage?
    @Published var selection: WatchPage = .today
    @Published var path: [WatchRoute] = []
    @Published var sheet: WatchSheet?
    /// 手錶自己的「遮住金額」（WatchHideAmounts，手錶 App Group）
    @Published private(set) var watchHidesAmounts: Bool
    /// 上次收到 iPhone 的包（內容沒變也算；設定頁「iPhone 14:02 更新」）
    @Published private(set) var lastReceivedAt: Date?
    /// 正在跟 iPhone 要（〔再試一次〕〔現在更新〕按下去到回話）
    @Published private(set) var asking = false
    /// 上一次要沒要到（iPhone 不在旁邊、LifeGood 被滑掉…）
    @Published private(set) var askFailed = false
    /// 畫面在前景（含手腕放下的永遠顯示）：收到新包時 4 種小格全部重畫（judge §3.1「更新額度」）
    private(set) var isActive = false

    /// 打開 App 時包超過這麼久沒收到新的、iPhone 在旁邊，就跟 iPhone 要一份（judge §5.8）
    static let refreshAfter: TimeInterval = 5 * 60

    private init() {
        // ⚠️ 順序不准換：watchHidesAmounts 沒有預設值，一定要第一個設。package、lastReceivedAt 是 Optional，
        // @Published 會先自動給 nil，之後再設就是走 setter（要用到 self）；self 還有屬性沒設好時走 setter 編不過
        // （'self' used in property access before all stored properties are initialized）。
        // iPhone 這邊的前例（CloudSyncManager、EInvoiceSyncManager、SubscriptionManager）也都是先設沒預設值的。
        watchHidesAmounts = WatchHideAmounts.isOn
        package = WidgetSnapshotStore.read(WatchPackage.self)
        lastReceivedAt = WatchReceiveLog.lastReceivedAt
    }

    /// ② 錢出不出現：還沒收過包（畫「—」的空版面）或包裡有錢才出現；iPhone 關掉「錢」就整頁不出現
    var showsMoney: Bool { package == nil || package?.money != nil }

    /// [v2] 手機條碼（iPhone 設定打開才有；② 錢左上 🧾 出不出現看這個）
    var barcode: String? { package?.carrierBarcode }

    /// 重讀手上那一包（WatchSync 寫好檔之後、回前景時）
    func reload() {
        package = WidgetSnapshotStore.read(WatchPackage.self)
        lastReceivedAt = WatchReceiveLog.lastReceivedAt
        watchHidesAmounts = WatchHideAmounts.isOn
        if selection == .money && !showsMoney {
            selection = .today
        }
    }

    /// WatchSync 收到新包、寫好檔之後（主執行緒）
    func packageReceived() {
        reload()
        askFinished(ok: true)
        // [v2] 待送盒已經對新包收尾（WatchSync 在背景做完）：重讀、把到期沒送的補送
        RecordOutbox.shared.packageApplied()
        // [v2] 手機條碼被關掉了：條碼那一頁收起來
        if barcode == nil {
            closeBarcode()
        }
    }

    /// RootView 的 scenePhase 一變就叫
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            isActive = true
            reload()
            // 正在要（例：還在等 activate）就不再送一次；手腕放下再抬起來（inactive → active）也不會重複要
            if shouldAsk(now: Date()) && !asking {
                requestFromPhone()
            }
            // [v2] 待送盒：重讀、到期沒送的補送（App 被系統暫停時沒送成的）
            RecordOutbox.shared.reload()
            RecordOutbox.shared.sendDue()
        case .inactive:
            isActive = true
            // [v2] 手腕放下：還在 10 秒內的馬上送（judge §2.6）
            RecordOutbox.shared.sendHoldingNow()
        case .background:
            // [v2] 翻走、退到背景：還在 10 秒內的馬上送
            RecordOutbox.shared.sendHoldingNow()
            // 真的從前景退到背景才收回（這個行程之前到過 active／inactive）。被 WatchConnectivity 在背景叫醒、
            // 或冷啟動時第一個回報的是 .background：本來就在第一頁，而且錶面／〔看議程〕可能剛用
            // onOpenURL／openMeeting 開好那一件，不能在這裡被清掉
            let wasForeground = isActive
            isActive = false
            if wasForeground {
                // 下次打開一律第一頁（不記上次停哪）；錶面、通知點進來的會在 onOpenURL／通知回呼裡再開
                selection = .today
                path = []
                sheet = nil
            }
        @unknown default:
            break
        }
        // WatchSync 在背景執行緒收包時看這個決定重畫幾種小格（前景＝全部，judge §3.1）
        WatchSync.shared.appActive = isActive
    }

    /// 手上沒有包、或超過 5 分鐘沒收到新的：跟 iPhone 要
    func shouldAsk(now: Date) -> Bool {
        guard package != nil, let last = lastReceivedAt else { return true }
        return now.timeIntervalSince(last) > Self.refreshAfter
    }

    /// 〔再試一次〕〔現在更新〕、打開 App 時自動要（sendMessage(["want": "pkg"])，會把 iPhone 在背景叫醒）
    func requestFromPhone() {
        asking = true
        askFailed = false
        WatchSync.shared.requestPackage()
    }

    /// WatchSync 要的結果回來（主執行緒）。ok＝收到包（內容沒變也算）
    func askFinished(ok: Bool) {
        asking = false
        askFailed = !ok
    }

    /// 手錶設定「遮住金額」：存起來、馬上叫錶面跟著遮或跟著露（judge §2.15）
    func setWatchHidesAmounts(_ on: Bool) {
        WatchHideAmounts.set(on)
        watchHidesAmounts = on
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 這一刻要不要遮（View 讀 isLuminanceReduced、redactionReasons 之後問這裡）
    func privacy(dimmed: Bool, redacted: Bool) -> WatchPrivacy {
        WatchPrivacy(dimmed: dimmed, redacted: redacted,
                     watchHides: watchHidesAmounts, phoneHides: package?.phoneHidesAmounts ?? false)
    }

    // MARK: 開到哪裡

    /// 錶面小格點進來（widgetURL；同一套網址，WidgetLink.parse）：
    /// 下一場 lifegood://today?stop=<id> → ① 今天、推進去那一件；已花 lifegood://expense/overview → ② 錢
    func open(_ url: URL) {
        guard let route = WidgetLink.parse(url) else { return }
        reload()
        sheet = nil
        switch route.destination {
        case .today(let stopId):
            selection = .today
            if let id = stopId, WatchText.findStop(id: id, in: package) != nil {
                path = [.stop(id)]
            } else {
                path = []
            }
        case .expenseOverview:
            selection = showsMoney ? .money : .today
            path = []
        case .addExpense:
            // [v2] 錶面「＋」：記帳台（關掉記一筆回到 ② 錢；iPhone 關掉「錢」時記一筆那一頁自己寫不能記帳）
            selection = showsMoney ? .money : .today
            path = []
            sheet = .record
        default:
            selection = .today
            path = []
        }
    }

    /// 部屬會議通知〔看議程〕（WatchNotificationDelegate）：那一場的細節；包裡找不到就停在 ① 今天
    func openMeeting(meetingId: String) {
        reload()
        sheet = nil
        selection = .today
        if let id = WatchText.meetingStopId(meetingId: meetingId, in: package, now: Date()) {
            path = [.stop(id)]
        } else {
            path = []
        }
    }

    // MARK: [v2] 記一筆、手機條碼

    /// ② 錢〔＋ 記一筆〕
    func openRecord() {
        sheet = .record
    }

    /// 記一筆收起來（記好了 2.5 秒後、〔完成〕）：回 ② 錢（iPhone 關掉「錢」時留在原頁）
    func closeRecord() {
        sheet = nil
        if showsMoney {
            selection = .money
        }
    }

    /// 手機條碼那一頁收起來（手腕放下、條碼被關掉）
    func closeBarcode() {
        if path.last == .barcode {
            path.removeLast()
        }
    }

    /// 頁面上點一列（「還有 N 件 ›」、「今天要留意」的卡費、生日）
    func go(_ route: WatchTextRoute) {
        switch route {
        case .dayList:
            path = [.dayList]
        case .bills:
            path = [.bills]
        }
    }
}
