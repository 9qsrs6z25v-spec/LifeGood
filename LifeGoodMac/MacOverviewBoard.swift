// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.648 mac7 G2] 總覽看板的資料與字（judge_mac.md §U3-2 ①～⑮；只 import Foundation，不碰 Color、不寫任何東西）。
//
// • 每支照抄 iOS（d070244）：OverviewBoard.swift（OB）、OverviewView.swift（OV）、MoneyBoardKit.swift（MBK）、MoneyBoards.swift（MBS）；
//   上一行寫「照抄 檔:行（d070244）」；一律照 iOS、不修 iPhone 的怪規則（§U3-2 最後一段）；sim 編號 ov7#N。
// • 全部收 now:、calendar:；頁面一次算完傳同一個 now、Calendar.current。金額字一律 MacText.short、百分比 WidgetMoneyFormat.percent。
// • 主控骨架（C0）：型別、欄位、推導（② 已照抄 OB:38-99）與簽名定案（§U7-6，組內不准改）；build 回空的、categoryStats 回 []、
//   字回 ""／nil。G2 換內容。

import Foundation

// MARK: - ① 未來幾天要扣的一筆固定支出

// 照抄 OverviewBoard.swift:28-36（d070244）OverviewUpcomingBill（名字）
struct MacOverviewBill: Identifiable, Equatable {
    let id: UUID
    let title: String
    let icon: String
    let amount: Double
    let date: Date
    /// 0＝今天、1＝明天…
    let daysAway: Int
}

// MARK: - ② 看板的資料

// 照抄 OverviewBoard.swift:38-99（d070244）OverviewBoardData（dues: [MoneyFixedDue] → [MacFixedDue]、upcoming → [MacOverviewBill]）
struct MacOverviewBoardData: Equatable {
    var month = 1
    var day = 1
    var daysInMonth = 30
    /// 本月已入帳
    var income: Double = 0
    /// 近 6 個月收入中位數（MacMoneyStore.estimatedMonthlyIncome）
    var incomeMedian: Double = 0
    /// 拿來算「還能花」的收入：本月已入帳與近 6 個月中位數取大
    var base: Double = 0
    var baseIsEstimate = false
    /// 本月變動支出
    var variable: Double = 0
    /// 本月固定支出（月等值）
    var fixed: Double = 0
    /// 上個月到同一天為止的支出（變動＋固定月等值）；沒有資料是 nil
    var lastMonthSameDay: Double? = nil
    var todayVariable: Double = 0
    var todayCount = 0
    /// 近 3 個月的變動支出日均（有花錢的月份才算）
    var prev3DailyAvg: Double? = nil
    /// 本月 1 號到今天，每天的變動支出
    var daily: [Double] = []
    /// 這個月從哪一天開始有記帳
    var firstDay = 1
    /// 這個月每一筆固定支出的扣款日
    var dues: [MacFixedDue] = []
    var upcoming: [MacOverviewBill] = []

    // MARK: 推導

    var spending: Double { variable + fixed }
    var hasBase: Bool { base > 0 }
    var monthProgress: Double { Double(day) / Double(max(daysInMonth, 1)) }
    /// 今天起還剩幾天（含今天）
    var remainingDays: Int { max(1, daysInMonth - day + 1) }
    /// 本月還能花（負的＝已經超支）
    var left: Double { base - spending }
    /// 今天起每天還能花多少（負的＝已經超支）
    var allowancePerDay: Double { left / Double(remainingDays) }
    var variableDailyAvg: Double { variable / Double(max(day, 1)) }

    /// 剩下的日子每天大概花多少：有前 3 個月的紀錄就用那個（「平常的花法」），沒有才用這個月到目前的日均
    var typicalDaily: Double { prev3DailyAvg ?? variableDailyAvg }
    var usesTypicalDaily: Bool { prev3DailyAvg != nil }
    /// 月底預估的總支出＝已經花的＋剩下的日子照平常的花法
    var projectedSpending: Double { spending + typicalDaily * Double(max(0, daysInMonth - day)) }

    /// 日預算：收入扣掉固定支出，平均到這個月的每一天；固定支出就超過收入、或沒有收入紀錄時不畫
    var dailyBudget: Double? {
        guard hasBase, base > fixed else { return nil }
        return (base - fixed) / Double(max(daysInMonth, 1))
    }
}

// MARK: - ③ 一次算完

extension MacOverviewBoardData {
    // 照抄 OverviewBoard.swift:101-186（d070244）OverviewBoardData.build（替換表見 judge_mac.md §U3-2 ③）— G2 換內容（ov7#3）
    @MainActor
    static func build(money: MacMoneyStore, now: Date, calendar cal: Calendar) -> MacOverviewBoardData {
        MacOverviewBoardData()
    }
}

// MARK: - ④ 本月花在哪裡

// 照抄 OverviewView.swift:179-186（d070244）CategoryStat
struct MacOverviewCategoryStat: Identifiable, Equatable {
    let category: VariableCategory
    let amount: Double
    let count: Int
    /// 上個月到同一天為止
    let lastMonth: Double
    var id: String { category.rawValue }
}

enum MacOverviewStats {
    // 照抄 OverviewView.swift:188-212（d070244）buildCategoryStats（store → money、Calendar.current → 參數）— G2 換內容（ov7#4）
    @MainActor
    static func categoryStats(money: MacMoneyStore, now: Date, calendar cal: Calendar) -> [MacOverviewCategoryStat] {
        []
    }
}

// MARK: - ⑤ 語氣（畫面那邊對到 MacTone；這檔不碰 Color）

// 照抄 MoneyBoardKit.swift:48（d070244）MoneyTone 的前四種（Mac 新名字）
enum MacOverviewTone: Equatable {
    case good, warn, bad, neutral
}

// MARK: - ⑨ ⑫ ⑭ 畫面要的字與格子

/// ⑨ 看板頭部（OB:210-240）
struct MacOverviewHead: Equatable {
    /// 「11 月・第 26 天／共 30 天」
    let date: String
    /// 「已花 79%」（沒有收入＝nil）
    let capsule: String?
    /// 「本月支出」「本月還能花」「本月已超支」
    let label: String
    let big: String
    /// 超支＝.bad；其餘 nil（ink）
    let bigTone: MacOverviewTone?
    /// 「Have a nice November!」
    let greeting: String
}

/// ⑫ 四格的一格（OB:347-419）
struct MacOverviewTileText: Identifiable, Equatable {
    let label: String
    let icon: String
    let value: String
    let valueTone: MacOverviewTone?
    let detail: String?
    let accent: String?
    let accentTone: MacOverviewTone
    /// 點了切到哪一頁（收入 .income、支出與今天 .variable、每天還能花 nil）
    let target: MacPage?

    var id: String { label }
}

/// ⑭ 每日長條那天的站牌（stations 對到那天；沒有扣款＝.none）
enum MacOverviewStation: Equatable {
    case none, past, next, later
}

/// ⑭ 每日長條的一天（Mac 自己的；1…daysInMonth 每天一根）
struct MacOverviewDay: Identifiable, Equatable {
    let day: Int
    /// "\(day)"
    let label: String
    /// d.daily[day − 1]（今天以後 0）
    let amount: Double
    /// dailyBudget.map { min(amount, $0) } ?? amount
    let under: Double
    /// max(0, amount − (dailyBudget ?? amount))
    let over: Double
    let station: MacOverviewStation
    let isToday: Bool

    var id: Int { day }
}

// MARK: - ⑥ ⑦ ⑧ ⑨～⑮ 字

enum MacOverviewBoardText {
    // ⑥ 照抄 MoneyBoardKit.swift:36-41（d070244）MoneyFormat.change（percent → WidgetMoneyFormat.percent）— G2 換內容
    /// 「↑12%」「↓8%」；差不到 1% 就說「持平」
    static func change(_ now: Double, vs before: Double) -> String? {
        nil
    }

    // ⑥ 照抄 MoneyBoardKit.swift:72-77（d070244）MoneyTone.spendingChange（MoneyTone → MacOverviewTone）— G2 換內容
    static func spendingTone(_ now: Double, vs before: Double) -> MacOverviewTone {
        .neutral
    }

    // ⑦ 照抄 MoneyBoards.swift:99-107（d070244）MoneyBoardText.months／month（逐字，月份英文表）— G2 換內容
    static func month(_ m: Int) -> String {
        ""
    }

    // ⑦ 照抄 MoneyBoards.swift:109-112（d070244）MoneyBoardText.short — G2 換內容
    static func short(_ s: String, max n: Int = 8) -> String {
        ""
    }

    // ⑧ 照抄 MoneyBoards.swift:165-170（d070244）MoneyFixedSchedule.label（next／when 叫 MacFixedSchedule）— G2 換內容
    /// 「明天扣 壽險」「11/28 扣 3 筆」
    static func nextLabel(_ d: MacOverviewBoardData) -> String? {
        nil
    }

    // ⑨ 照抄 OverviewBoard.swift:210-240（d070244）header — G2 換內容
    static func header(_ d: MacOverviewBoardData) -> MacOverviewHead {
        MacOverviewHead(date: "", capsule: nil, label: "", big: "", bigTone: nil, greeting: "")
    }

    // ⑩ 照抄 OverviewBoard.swift:242-266（d070244）verdict（Text → 三段字；neutral 時畫面用 ink）— G2 換內容
    static func verdict(_ d: MacOverviewBoardData) -> (lead: String, amount: String, tone: MacOverviewTone) {
        ("", "", .neutral)
    }

    // ⑪ 照抄 OverviewBoard.swift:290-292（d070244）moneyCell 的 trailing 字 — G2 換內容
    static func moneyTrailing(_ d: MacOverviewBoardData) -> String {
        ""
    }

    // ⑪ 照抄 OverviewBoard.swift:319-344（d070244）legend 的字與 over 判斷 — G2 換內容
    static func legend(_ d: MacOverviewBoardData) -> (fixed: String, variable: String, month: String, over: Bool) {
        ("", "", "", false)
    }

    // ⑫ 照抄 OverviewBoard.swift:347-419（d070244）四格（action → target）— G2 換內容
    static func tiles(_ d: MacOverviewBoardData) -> [MacOverviewTileText] {
        []
    }

    // ⑬ 照抄 OverviewBoard.swift:580-585（d070244）row 的 when — G2 換內容
    /// 「今天扣款」「明天扣款」「11/28 (週五)・2 天後」
    static func when(_ b: MacOverviewBill) -> String {
        ""
    }

    // ⑬ 照抄 OverviewBoard.swift:586（d070244）soon
    static func soon(_ b: MacOverviewBill) -> Bool {
        b.daysAway <= 1
    }

    // ⑬ 照抄 OverviewBoard.swift:515-520（d070244）dueFmt
    static let dueFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d (E)"
        return f
    }()

    // ⑭ Mac 新：每日長條（1…daysInMonth 每天一根；sim ov7#14 驗 under＋over＝amount）— G2 換內容
    static func daily(_ d: MacOverviewBoardData) -> [MacOverviewDay] {
        []
    }

    // ⑮ 照抄 OverviewBoard.swift:278（d070244）budgetLabel（"日預算 " + MacText.short）— G2 換內容
    static func budgetText(_ d: MacOverviewBoardData) -> String? {
        nil
    }
}
