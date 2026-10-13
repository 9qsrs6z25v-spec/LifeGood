import Foundation

// MARK: - 桌面小工具的快照（v25.545）
//
// 這個檔案同時屬於「主 App」與「LifeGoodWidgets」兩個 target。
//
// 分工跟靈動島一樣：App 把小工具要顯示的「字」與「數字」算好、格式化好，寫成 App Group 裡的
// 小檔案；小工具只讀這些檔、照著畫。**小工具裡不做任何金額計算與格式化**——「NT$4.6萬」
// 「每天 NT$2,402」「已花 62%」全部是 App 用自己那套函式（MoneyFormat／ntdWanString）組好的字。
//
// 換日不靠小工具算：App 寫快照時就把「今天、明天……」每一天要顯示的字各準備一份，
// 小工具只依現在時間挑對應的那一份。
//
// ⚠️ 這個檔案只准用 Foundation、TimelineStop／DayTimelineFormat／DayTimelineLink
//    （DayTimelineAttributes.swift）與同檔型別。不准引用 App 才有的型別
//    （ExpenseStore、AppMode、MoneyFormat、OverviewBoardData…）：Widget target 編不過，
//    而為了編過改寫字面字串，就會重演 v25.454（共用檔寫 "life"、rawValue 其實是「人生」，
//    點靈動島永遠跳錯頁）。網址一律用 WidgetLink（WidgetLink.swift）組。

// MARK: - 名字

enum WidgetShared {
    /// App Group。v25.544 已加到 LifeGood.entitlements 與 LifeGoodWidgets.entitlements，
    /// 使用者也已在 Apple Developer 後台註冊並掛到兩個 App ID。
    static let appGroupID = "group.com.lifegood.app"
    /// App Group 裡放快照的資料夾
    static let folderName = "Widgets"
}

/// WidgetKit 的 kind。小工具的 StaticConfiguration 與 App 的 reloadTimelines(ofKind:) 都用這裡的值，
/// 兩邊不准各寫一份字面字串。
enum WidgetKind {
    /// 還能花（systemSmall；StandBy 用同一個）
    static let moneyLeft = "LifeGoodMoneyLeft"
    /// 今天（systemSmall、systemMedium）
    static let today = "LifeGoodToday"
}

/// 快照檔名。分檔是為了只改了帳就只重寫 money、只重畫「還能花」。
enum WidgetSnapshotFile: String {
    case money = "money_v1.json"
    case life = "life_v1.json"
}

/// 時間門檻：兩邊用同一組數字
enum WidgetFreshness {
    /// 「還能花」快照超過這麼久沒更新，最下面一行改成「上次更新 10/11」（照樣換日顯示）
    static let moneyStaleAfter: TimeInterval = 2 * 24 * 3600
    /// 「今天」中型：快照超過這麼久沒更新，右下角寫「10:02 更新」
    static let lifeShowUpdatedAfter: TimeInterval = 3 * 3600
    /// 倒數字（「25 分後」）只在這麼多分鐘以內寫；更遠的只寫時間
    static let countdownMaxMinutes = 90
}

// MARK: - 快照的共同規矩

/// 每一份快照都要有的東西。
///
/// generatedAt 是「寫的當下」，**不算內容**：寫檔時拿掉它再比，內容沒變就不寫、不叫重畫
///（App 在背景叫重畫會吃掉小工具每天的額度）。所以快照裡**不准放由 generatedAt 推出來的字**
///（例如「10:02 更新」「上次更新 10/11」），那些由小工具用 WidgetDateText 從 generatedAt 組。
protocol WidgetSnapshotPayload: Codable, Equatable {
    static var file: WidgetSnapshotFile { get }
    /// 這一版的格式號。讀到的檔 schema 對不上就當作沒有快照（顯示「打開 LifeGood 一次」）。
    static var schemaVersion: Int { get }
    var schema: Int { get }
    var generatedAt: Date { get set }
}

// MARK: - 還能花（money_v1.json）

/// 「還能花」的三種狀態（跟收支總覽頭部同一套判斷）
enum WidgetMoneyState: String, Codable {
    /// 有收入基準、還沒超支：本月還能花
    case normal
    /// 有收入基準、已經超支：本月已超支（紅）
    case over
    /// 一筆收入紀錄都沒有：本月支出
    case noIncome
}

/// 「這個月的錢」橫條（跟總覽同一條縮短；不畫斜線預估）。
/// 三個值都是 0…1，以 max(收入基準, 本月支出, 1) 為整條的長度，App 已經夾好範圍。
struct WidgetMoneyBar: Codable, Equatable {
    /// 固定支出（紫）從 0 畫到這裡
    var fixed: Double
    /// 變動支出（藍）接在固定後面，長度是這個值（fixed + variable ≤ 1）
    var variable: Double
    /// 收入基準那一道直線的位置；沒有收入紀錄是 nil（不畫線）。
    /// fixed + variable 超過它的那一截＝超支，小工具畫成紅色。
    var income: Double?
}

/// 某一天「還能花」要顯示的全部字。小工具不改字、不拼字（除了把它們放進版面）。
///
/// 例（10/13 週二 10:05，正常）：
///   dateText「10/13 週二」 title「本月還能花」 hero「NT$4.6萬」
///   line「每天 NT$2,402」 footer「已花 62%・還有 19 天」
/// 已超支：title「本月已超支」 hero「NT$3,200」 line「每天 已超支」 footer「已花 103%・還有 19 天」
/// 沒有收入：title「本月支出」 hero「NT$7.4萬」 line「記一筆收入，才算得出還能花」
///          footer「今天 NT$1,240・3 筆」（今天還沒記帳：「今天 還沒花錢」）
struct WidgetMoneyDay: Codable, Equatable, Identifiable {
    /// 「2026-10-13」（WidgetDateText.dayKey）
    var dayKey: String
    /// 這一天的 00:00 與隔天 00:00（App 用 Calendar.current 算的絕對時間）
    var dayStart: Date
    var dayEnd: Date
    /// 左上角日期「10/13 週二」（WidgetDateText.dayLabel）
    var dateText: String
    var state: WidgetMoneyState
    /// 小標
    var title: String
    /// 大字
    var hero: String
    /// 第二行
    var line: String
    /// 最下面一行（快照太舊時小工具改寫成「上次更新 10/11」，見 WidgetMoneySnapshot.isStale）
    var footer: String
    /// 本月支出 ÷ 收入基準（0.62＝62%、1.03＝103%，不夾上限）；沒有收入紀錄是 0。
    /// footer 裡的「62%」就是它；這個數字留給之後的進度環（v2 鎖定畫面）。
    var spentRatio: Double
    /// 今天起還剩幾天（含今天）
    var remainingDays: Int
    var bar: WidgetMoneyBar

    var id: String { dayKey }
    /// 超支旗標（大字、小標、第二行用紅色；著色模式靠「已超支」三個字）
    var isOver: Bool { state == .over }

    func contains(_ date: Date) -> Bool { dayStart <= date && date < dayEnd }
}

struct WidgetMoneySnapshot: Codable, Equatable, WidgetSnapshotPayload {
    static let file = WidgetSnapshotFile.money
    static let schemaVersion = 1

    var schema: Int = WidgetMoneySnapshot.schemaVersion
    var generatedAt: Date
    /// 寫的當下是哪一天「2026-10-13」
    var dataDay: String
    /// 寫的當下是幾月（1…12）
    var month: Int
    /// 從今天到這個月最後一天，每天一份，依日期排序（至少今天一份）。
    /// 明天以後的那幾份是 App 用同一套規則推的：今天花的歸零、剩餘天數減一、每天還能花重算；
    /// 本月支出、收入基準照今天的（還沒記的帳 App 不知道，打開 App 就會重寫）。
    var days: [WidgetMoneyDay]
}

extension WidgetMoneySnapshot {
    /// 這個時間點要顯示哪一天。比第一天還早（時鐘往回調、時區往回）就用第一天；
    /// 過了最後一天（跨月）回 nil，改顯示「11 月開始了」（hasEnded）。
    func day(at date: Date) -> WidgetMoneyDay? {
        if let hit = days.first(where: { $0.contains(date) }) { return hit }
        if let first = days.first, date < first.dayStart { return first }
        return nil
    }

    /// 已經過了快照裡最後一天（＝跨月了，v1 只能請使用者打開 App）
    func hasEnded(at date: Date) -> Bool {
        guard let last = days.last else { return true }
        return date >= last.dayEnd
    }

    /// 超過兩天沒更新：最下面一行改成 WidgetDateText.lastUpdated(generatedAt)
    func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(generatedAt) > WidgetFreshness.moneyStaleAfter
    }
}

// MARK: - 今天（life_v1.json）

/// 時間軸上的一站＋小工具多要的兩樣東西。stop 原封不動是靈動島那一份（同一段程式挑的）。
struct WidgetStop: Codable, Equatable, Identifiable {
    var stop: TimelineStop
    /// 地點：個人事件、系統行事曆的地點，旅遊景點的地址；部屬會議沒有地點欄位，是空字串
    var location: String
    /// StandBy（背景被拿掉）時代替主題的字，不含任何人名：
    /// 部屬會議「部屬會議」、個人事件「會議／事務」、系統行事曆「系統行事曆」、
    /// 旅遊景點照樣寫站名（景點算低隱私），過夜那一站寫「住宿」
    var lockTitle: String

    var id: String { stop.id }
}

/// 全天的事的種類。宣告順序就是優先序（生日最優先）。
enum WidgetAllDayKind: String, Codable {
    case birthday
    case anniversary
    /// 兼任職務的重要日期（尾牙：場勘日）與卸任日
    case sideRole
    case milestone
    /// 我的行事曆裡的全日事件（durationMinutes == 0）
    case personal
    /// 系統行事曆的全日事件
    case appleCalendar

    /// 越小越優先：生日＞結婚紀念日＞兼任職務＞里程碑＞其他全日事件
    var priority: Int {
        switch self {
        case .birthday:      return 0
        case .anniversary:   return 1
        case .sideRole:      return 2
        case .milestone:     return 3
        case .personal:      return 4
        case .appleCalendar: return 5
        }
    }
}

/// 一件全天的事（生日、紀念日…）。App 已經依 priority 排好。
struct WidgetAllDayItem: Codable, Equatable, Identifiable {
    /// 跟我的行事曆同一套 id（「bd-<UUID>」「anniv-<UUID>」「ms-<UUID>」「srkd-<UUID>」…）
    var id: String
    var kind: WidgetAllDayKind
    /// 中型膠囊、小型「今天沒排行程」的第二行：「媽媽 62 歲生日」「尾牙：場勘日」
    var title: String
    /// 小型最下面一行（窄）：「媽媽生日」
    var shortTitle: String
    /// StandBy：不寫是誰——「家人生日」「結婚紀念日」「兼任職務」「里程碑」
    var lockTitle: String
    /// SF Symbol 名稱（生日 birthday.cake.fill、紀念日 heart.fill、兼任職務／里程碑 flag.fill…）
    var icon: String
}

struct WidgetLifeDay: Codable, Equatable, Identifiable {
    /// 「2026-10-13」
    var dayKey: String
    var dayStart: Date
    var dayEnd: Date
    /// 「10/13 週二」
    var dateText: String
    /// 「10/13」（今天沒排行程時的大字）
    var shortDateText: String
    /// 這一天全部有時間的行程，依開始時間排序。跟靈動島同一段程式挑的（TodayAgenda），
    /// 但不裁成 8 站。已經離開的旅遊景點不在裡面（跟靈動島一樣）。
    var stops: [WidgetStop]
    /// 全天的事，已依 WidgetAllDayKind.priority 排好；沒有是空陣列
    var allDay: [WidgetAllDayItem]
    /// 中型右上角手寫問候，兩行：["Have a nice", "Tuesday!"]。空陣列＝不寫
    var greeting: [String]
    /// 這一天是旅遊期間、部屬會議已經被藏起來（stops 裡本來就沒有，這裡只是告訴小工具）
    var hidesMeetings: Bool
    /// 隔天的第一場（「今天的行程結束了／明天 08:30／早會」用）；隔天沒有行程是 nil
    var nextDayFirstStop: WidgetStop?

    var id: String { dayKey }

    func contains(_ date: Date) -> Bool { dayStart <= date && date < dayEnd }

    /// 進行中那一場（跟靈動島 currentStop 同一個判斷）
    func currentStop(at now: Date) -> WidgetStop? {
        stops.first { $0.stop.start <= now && now < $0.stop.end }
    }

    /// 下一場（還沒開始的第一場）
    func nextStop(at now: Date) -> WidgetStop? {
        stops.first { $0.stop.start > now }
    }

    /// 還沒結束的（進行中＋還沒開始），依開始時間
    func remainingStops(at now: Date) -> [WidgetStop] {
        stops.filter { $0.stop.end > now }
    }
}

struct WidgetLifeSnapshot: Codable, Equatable, WidgetSnapshotPayload {
    static let file = WidgetSnapshotFile.life
    static let schemaVersion = 1

    var schema: Int = WidgetLifeSnapshot.schemaVersion
    var generatedAt: Date
    var dataDay: String
    /// 過了這個時間（後天 00:00）整份不能用，顯示「打開 LifeGood 更新今天的行程」
    var validUntil: Date
    /// [0]＝今天、[1]＝明天
    var days: [WidgetLifeDay]
}

extension WidgetLifeSnapshot {
    /// 這個時間點要顯示哪一天；過期回 nil。比第一天還早就用第一天。
    func day(at date: Date) -> WidgetLifeDay? {
        guard date < validUntil else { return nil }
        if let hit = days.first(where: { $0.contains(date) }) { return hit }
        if let first = days.first, date < first.dayStart { return first }
        return nil
    }

    func isExpired(at date: Date) -> Bool { date >= validUntil }

    /// 中型右下角要不要寫「10:02 更新」
    func showsUpdatedAt(at date: Date) -> Bool {
        date.timeIntervalSince(generatedAt) > WidgetFreshness.lifeShowUpdatedAfter
    }
}

// MARK: - 日期與時間的字（兩邊共用，不含金額）

enum WidgetDateText {
    private static let dayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        // [v25.545] 跟著手機目前的時區走：App 一路活在背景、人飛到日本才打開時，
        // 快取的 formatter 不會還停在台灣時區，把「今天」寫成前一天
        f.timeZone = .autoupdatingCurrent
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d EEE"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        // [v25.545] 跟著手機目前的時區走：App 一路活在背景、人飛到日本才打開時，
        // 快取的 formatter 不會還停在台灣時區，把「今天」寫成前一天
        f.timeZone = .autoupdatingCurrent
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d"
        return f
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        // [v25.545] 跟著手機目前的時區走：App 一路活在背景、人飛到日本才打開時，
        // 快取的 formatter 不會還停在台灣時區，把「今天」寫成前一天
        f.timeZone = .autoupdatingCurrent
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 「10/13 週二」
    static func dayLabel(_ date: Date) -> String { dayLabelFormatter.string(from: date) }

    /// 「10/13」
    static func shortDate(_ date: Date) -> String { shortDateFormatter.string(from: date) }

    /// 「2026-10-13」（只拿來辨認是哪一天，不顯示）
    static func dayKey(_ date: Date) -> String { dayKeyFormatter.string(from: date) }

    /// 「上次更新 10/11」
    static func lastUpdated(_ generatedAt: Date) -> String {
        "上次更新 " + shortDate(generatedAt)
    }

    /// 「10:02 更新」；不是今天寫的寫「10/12 22:00 更新」（[v25.545] 隔天早上只寫 22:00 會看不懂是哪天）
    static func updatedAt(_ generatedAt: Date, now: Date = Date()) -> String {
        let time = DayTimelineFormat.time(generatedAt) + " 更新"
        if Calendar.current.isDate(generatedAt, inSameDayAs: now) { return time }
        return shortDate(generatedAt) + " " + time
    }

    /// 「11 月開始了」（快照的月份過完了、App 還沒打開）
    static func monthStarted(_ date: Date) -> String {
        let month = Calendar.current.component(.month, from: date)
        return "\(month) 月開始了"
    }

    /// 倒數字：「25 分後」「1 小時後」「1 小時 20 分後」。
    /// 分鐘無條件進位（10:05:00 到 10:30 是 25 分；10:05:30 也還是 25 分）。
    /// 已經到了、或超過 WidgetFreshness.countdownMaxMinutes 回 nil（不寫倒數，只寫時間）。
    /// 「40 分後結束」＝這個字＋「結束」。
    static func countdown(to target: Date, from now: Date) -> String? {
        let seconds = target.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        let minutes = Int((seconds / 60).rounded(.up))
        guard minutes <= WidgetFreshness.countdownMaxMinutes else { return nil }
        if minutes < 60 { return "\(minutes) 分後" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) 小時後" : "\(hours) 小時 \(rest) 分後"
    }
}

// MARK: - 讀寫

/// 快照的讀與寫。小工具只呼叫 read；App 只呼叫 write（WidgetSnapshotWriter）。
enum WidgetSnapshotStore {

    /// App Group 的根目錄；entitlements 沒生效時是 nil（這時 read 一律 nil、write 一律 false）
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetShared.appGroupID)
    }

    /// <App Group>/Widgets/。create 為 true 時順手建資料夾（已經有就沒事）。
    static func folderURL(create: Bool) -> URL? {
        guard let base = containerURL else { return nil }
        let folder = base.appendingPathComponent(WidgetShared.folderName, isDirectory: true)
        if create {
            // 不能用最嚴格的 complete：手機鎖著時 StandBy／鎖定畫面的小工具會讀不到
            let attributes: [FileAttributeKey: Any] = [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
            do {
                try FileManager.default.createDirectory(at: folder,
                                                        withIntermediateDirectories: true,
                                                        attributes: attributes)
            } catch {
                return nil
            }
        }
        return folder
    }

    static func fileURL(_ file: WidgetSnapshotFile, create: Bool = false) -> URL? {
        folderURL(create: create)?.appendingPathComponent(file.rawValue, isDirectory: false)
    }

    /// 小工具用：讀不到、解不開、schema 對不上都回 nil（＝還沒打開過新版 App）
    static func read<T: WidgetSnapshotPayload>(_ type: T.Type) -> T? {
        guard let url = fileURL(T.file),
              let data = try? Data(contentsOf: url),
              let value = try? makeDecoder().decode(T.self, from: data),
              value.schema == T.schemaVersion else { return nil }
        return value
    }

    /// App 用：整檔一次換掉（原子寫入），保護等級「開機後第一次解鎖就能讀」。
    ///
    /// 跟舊檔比：拿掉 generatedAt 之後內容一模一樣就**不寫**、回 false——呼叫端看到 false
    /// 就不要叫 WidgetCenter 重畫。真的寫了才回 true。寫失敗也回 false。
    @discardableResult
    static func write<T: WidgetSnapshotPayload>(_ snapshot: T) -> Bool {
        guard let url = fileURL(T.file, create: true) else { return false }
        let encoder = makeEncoder()
        guard let newData = try? encoder.encode(snapshot) else { return false }
        if let oldData = try? Data(contentsOf: url),
           let old = try? makeDecoder().decode(T.self, from: oldData) {
            // 用舊檔的 generatedAt 重新編一次：編出來跟舊檔一個位元組都不差＝內容沒變
            var probe = snapshot
            probe.generatedAt = old.generatedAt
            if let probeData = try? encoder.encode(probe), probeData == oldData {
                return false
            }
        }
        do {
            try newData.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    /// 兩邊同一組設定。sortedKeys 讓同樣的內容永遠編出同樣的位元組（write 的比對靠它）；
    /// 日期用預設的 deferredToDate（Date 自己的秒數原樣進出，不會因為換算差一點點）。
    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .deferredToDate
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf",
                                                                 negativeInfinity: "-inf",
                                                                 nan: "nan")
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .deferredToDate
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf",
                                                                   negativeInfinity: "-inf",
                                                                   nan: "nan")
        return d
    }
}
