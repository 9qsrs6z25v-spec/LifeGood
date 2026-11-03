//
//  VehicleCardData.swift
//  LifeGood
//
//  [v25.540] 載具卡片上每一個字、每一個數字，都在 VehicleCardData.build 一次算好（照 HouseCardData）。
//  畫面（VehicleCardViews）只排版、上色；外殼（VehicleDetailView）只管點了要做什麼。
//  - 數字一律讀 VehicleFacts（v25.539），這裡不另算一份；facts 沒有的（帳本、要確認、圓標、照片張數）
//    用 VehicleLinks.make 重取這台車的記帳名單再算，同一筆支出只算給 linkedVehicleId 那一台。
//  - 日期一律西曆＋zh_TW（FinanceFormat＝HouseCardFormat）；build 的 calendar 預設西曆（房屋是 .current，不要照抄）。
//  - 要加起來等於合計的數字（帳本格子、長條、篩選小計、年份小計、每月養車各段、實際花了的三個加數）
//    用最大餘數法分尾數，畫面上相加才會剛好等於那個合計。
//  這裡只放值型別，不放 View、不用 Color（顏色由畫面依 kind／mark／bucket 對照）；import SwiftUI 只為了 MoneyBoardChip／MoneyTone。
//

import SwiftUI

// MARK: - 通用值型別（FinanceCardKit 與房屋共用；房屋那邊不用改）

/// [v25.540] 房屋卡的一句話、格式、分尾數、進度格其實是通用的：車子和 FinanceCardKit 用 Finance 開頭的名字，
/// 值型別本身不改名（HouseCardData.swift 一行都不用動，房屋上百個呼叫點不受影響）
typealias FinanceRun = HouseRun
typealias FinanceLine = HouseLine
typealias FinanceFormat = HouseCardFormat
typealias FinanceRound = HouseRound
typealias FinanceProgressData = HouseProgressData

/// 卡片內可以捲到的位置（ScrollViewReader 的 id）。放資料檔是為了 VehicleTap 能引用；C、D 照用。
enum VehicleAnchor: String, Hashable { case top, checks, monthly, upcoming, loan, energy, ledger, info, photos }

/// 格子、圖例、提示列點了要做什麼（C 的 handle(_:) 轉成 VehicleCardActions）
enum VehicleTap: Equatable {
    case none
    case scrollTo(VehicleAnchor)
    case ledgerFilter(VehicleLedgerFilter)      // 先切篩選、再捲到帳本
    case edit(VehicleEditFocus)                 // 付費：編輯頁捲到那一欄
    case openExpense(UUID)                      // 付費：AddExpenseView 編輯那一筆
    case openAnalytics                          // 免費：充電與里程分析
}

/// 3×2 的一格（格子裡不寫 NT$）
struct VehicleTile: Identifiable, Equatable {
    let label: String
    let value: String
    var valueTone: MoneyTone? = nil
    var sub: String = ""
    var subTone: MoneyTone? = nil
    var tap: VehicleTap = .none
    var id: String { label }
}

extension VehiclePowerType {
    /// 「油車」「電車」「油電」「機車」「電動機車」（rawValue 的「混合動力」太長，看板、資料卡、分享都用這個）
    var shortName: String {
        switch self {
        case .gasoline: return "油車"
        case .electric: return "電車"
        case .hybrid: return "油電"
        case .motorcycle: return "機車"
        case .electricMotorcycle: return "電動機車"
        }
    }
}

extension VehicleScriptName {
    /// 決定 20：車名像車牌（規則見本版定案 5）。照台灣車牌的樣子比：「ABC-1234」「AB1234」「1234-AB」「6A-1234」，
    /// 不分大小寫，而且要同時有字母和數字。比「英數 5–8 碼」嚴：Taycan、Model3、RAV4、EV6 不會被當成車牌
    static func looksLikePlate(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard s.count >= 4, s.count <= 9 else { return false }
        let patterns = ["^[A-Z]{2,3}-?[0-9]{3,4}$", "^[0-9]{3,4}-?[A-Z]{2,3}$", "^[A-Z0-9]{2,4}-[A-Z0-9]{2,4}$"]
        guard patterns.contains(where: { s.range(of: $0, options: .regularExpression) != nil }) else { return false }
        let hasLetter = s.unicodeScalars.contains { (65...90).contains($0.value) }
        let hasDigit = s.unicodeScalars.contains { (48...57).contains($0.value) }
        return hasLetter && hasDigit
    }

    /// 分享頁首、檔名、手寫問候、名牌用：像車牌就寫「品牌 動力」（品牌空白只寫動力），否則車名（空白「未命名車輛」）
    static func shareName(_ v: Vehicle) -> String {
        let name = v.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikePlate(name) else { return name.isEmpty ? "未命名車輛" : name }
        let brand = v.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let power = v.powerType.shortName
        return brand.isEmpty ? power : "\(brand) \(power)"
    }
}

enum VehicleValuation {
    /// 一般行情：purchase × 0.85^(持有天數 ÷ 365)，四捨五入到 1,000；purchase ≤ 0 或天數 < 0 回 nil。
    /// [v25.540] 車輛資料的行情參考和編輯頁「照每年 15% 估（帶入）」共用這一支，兩處數字一定一樣
    static func marketEstimate(purchase: Double, from: Date, to: Date) -> Double? {
        guard purchase > 0, purchase.isFinite else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.day], from: cal.startOfDay(for: from), to: cal.startOfDay(for: to))
        guard let days = comps.day, days >= 0 else { return nil }
        let raw = purchase * pow(0.85, Double(days) / 365)
        return (raw / 1_000).rounded() * 1_000
    }
}

// MARK: - 看板

struct VehicleCardBoardData: Equatable {          // 名字不能叫 VehicleBoardData（列表看板已用）
    var date = ""                   // 「Porsche・電車」；品牌空白「電車」；已售出「Porsche・已售出」
    var dateIcon = "car.fill"       // powerType.icon；已售出 checkmark.seal.fill
    var capsule: String? = nil      // 「折舊 ▼27%」「增值 ▲5%」「持平」；已售出「持有 3 年 2 個月」；算不出 nil
    var capsuleIcon: String? = nil
    var capsuleTone: MoneyTone = .neutral   // 只有增值是 .up（畫面 .neutral 時傳 capsuleTint nil）
    var label = "車輛估值"           // 「車輛估值（還沒填，先用購入價）」；已售「賣出價差」「賣出價差（用估值當賣價）」
    var big = ""                    // 「NT$260萬」；已售「-NT$178萬」
    var bigTone: MoneyTone? = nil   // 已售賺 .up；其他 nil
    var line = FinanceLine()        // 一句話（金額段 bold＋tone）
    var greeting: [String] = []     // 「Drive safe,」／「Ride safe,」／「So long,」＋第二行
    var accessibilityText = ""
}

/// 看板下取代進度格的一行
struct VehicleProgressNote: Equatable {
    enum Kind: Equatable { case paidOff, termMissing }
    let kind: Kind                  // paidOff：checkmark.seal.fill／good；termMissing：exclamationmark.triangle.fill／warn，點了捲到 .checks
    let text: String                // 「車貸 2029/9 全部繳完」「車貸每月 NT$3.5萬・沒填年限，算不出還要繳多久」
}

// MARK: - 要確認

struct VehicleCheck: Identifiable, Equatable {
    enum Kind: String {
        // [v25.541] insuranceAsOther：記成「其他」的車險（排第二，緊接在賣了還在扣後面）
        case soldStillCharging, insuranceAsOther, termMissing, principalMissing, belowPrincipal, rateTooHigh,
             orphans, legacyFixed, unassigned, downPayment, valueMissing, soldInFuture,
             odometerRegression, homeKeyword, foreign, energyGap
    }
    enum Fix: Equatable {
        case stopAtSale(expenseIds: [UUID], soldDate: Date)   // VehicleFixes.stopAtSale
        case convertToInsurance(expenseIds: [UUID])           // [v25.541] VehicleFixes.convertToInsurance＋拿掉鏡像
        case openExpense(UUID)                                // 去填／去看；里程倒退、漏記開那一筆
        case removeMirrors([UUID])                            // 孤兒、連到別台：只從這台移掉這些鏡像 id
        case backfillFixed(mirrorId: UUID)                    // 補建（一次一筆：第一筆）
        case assign(expenseIds: [UUID])                       // 都算這台
        case markValueZero                                    // 就是 0（報廢）
        case edit(VehicleEditFocus)                           // 去改：售出日、家充、估值
    }
    struct Action: Identifiable, Equatable {
        let title: String           // 「在賣出日停止」「去填」「就是 0（報廢）」…
        let confirm: String?        // nil＝直接做（只開頁面）
        var confirmTitle: String = ""   // 確認框標題（「停止扣款？」「移除這些支出？」…）；confirm nil 時不用
        var destructive = false     // 移除類 true
        let fix: Fix
        var id: String { title }
    }
    let kind: Kind
    let message: String
    let actions: [Action]           // 1～2 顆（估值 0 有「去填」「就是 0（報廢）」）
    var icon: String = "exclamationmark.triangle.fill"
    var id: String { kind.rawValue }
    var accessibilityLabel: String { (actions.first?.title ?? "") + "：" + message }
}

// MARK: - 每月養車

enum VehicleEnergyFlavor: Equatable { case electric, fuel, mixed }   // 能源段顏色：電綠、油橘、混合青綠

struct VehicleMonthlyData: Equatable {
    enum Kind: String, Equatable { case interest, principal, loan, fixed, energy, care, other }
    struct Part: Identifiable, Equatable {
        let kind: Kind
        let label: String           // 「車貸利息」「還本金」「車貸」「定期」「充電／加油／油電／換電・充電」「保養・維修」「停車・洗車・其他」
        let value: Double           // 已分到百位（各段相加＝total）
        let valueText: String       // 「NT$5,000」「NT$2.9萬」
        let tap: VehicleTap         // 車貸三種 .scrollTo(.loan)（沒有車貸區時 .scrollTo(.checks)）；定期 .ledgerFilter(.fixed)；能源 .scrollTo(.energy)；保養 .ledgerFilter(.care)；其他 .ledgerFilter(.other)
        var id: String { kind.rawValue }
        var legend: String { label + " " + valueText }
    }
    var trailing = ""               // 「近 12 個月平均」「近 7 個月平均」
    var total: Double = 0           // ＝round(facts.monthly, 100)
    var headline = ""               // 「約 NT$5,200」（FinanceText.about100）
    var parts: [Part] = []          // 只放 > 0 的段
    var energyFlavor: VehicleEnergyFlavor = .electric
    var realLine: FinanceLine? = nil        // ①「真正花掉的是 約 NT$1.1萬；NT$2.9萬 是在還車貸本金，減少欠銀行的錢。」
    var perKmLine: String? = nil            // ②
    var depreciationLine: FinanceLine? = nil// ③
    var insuranceHint: String? = nil        // 「這台車還沒有連到任何保險，每月養車會偏低。」（旁邊「＋ 記保險 →」= addLedger(.insurance)）；記成其他的車險見下兩欄
    /// [v25.541] 保險提示旁邊的連結字（畫面接「 →」）和點了去哪（nil＝addLedger(.insurance)）。
    /// 有記成「其他」的車險時錢已經算在定期裡，再記一筆會重複：改成「去改」、捲到「要確認」
    var insuranceHintAction = "＋ 記保險"
    var insuranceHintTap: VehicleTap? = nil
    var firstYearHint: String? = nil
    var lateStartHint: String? = nil
    var splitHint: String? = nil            // 「在車貸那筆填上總貸款金額，就能分出利息和本金 →」
    var splitTap: VehicleTap = .none        // .openExpense(那筆) 或 .scrollTo(.checks)
    var footnote = "定期支出照它自己的週期換算成每月（季繳 ÷ 3、年繳 ÷ 12）；其他用近 12 個月的實際紀錄平均。買車的錢不算在這裡，請看「我的帳本」。"
    var accessibilityText = ""              // 「平均每月約 5,200 元：定期 5,000，充電 100，停車洗車其他 100」
}

// MARK: - 接下來

struct VehicleUpcomingData: Equatable {
    struct Row: Identifiable, Equatable {
        let id: String              // VehicleUpcoming.id
        let dayText: String         // 日期塊大字「05」；保養估計「約」
        let monthText: String       // 日期塊小字「2026/11」
        let mark: VehicleLedgerMark
        let title: String           // 「停車月租」「車貸」「保養（估計）」
        let detail: String          // VehicleUpcoming.detail
        let amountText: String      // 「NT$4,999」「約 NT$8,000」；沒有金額 ""
        let overdueText: String?    // 「已經超過 40 天沒保養」（warn）
        let tap: VehicleTap         // 定期／車貸 .openExpense(id)；保養 .ledgerFilter(.care)
        let expenseId: UUID?        // 長按「編輯」「停止扣款」用；保養 nil（沒有長按選單）
        let accessibilityText: String
    }
    var trailing = ""               // 「一年內 1 件」
    var rows: [Row] = []            // 全部，依日期；畫面先列 5 件
    var maintenanceNote: String? = nil  // 「上次保養 2025/9/20（照片紀錄），再記一次就能估下一次」
    var taxHint: String? = nil      // 「自用小客車的使用牌照稅每年 4 月、汽車燃料使用費每年 7 月開徵；…」（＋ 記稅費 = addLedger(.tax)）
}

// MARK: - 車貸

struct VehicleLoanSectionData: Equatable {
    enum Status: Equatable { case paying, notStarted, done, stopped, soldSettled, unlinked }
    struct Row: Identifiable, Equatable {
        enum Source: Equatable { case expense(UUID), legacy(UUID) }   // legacy＝沒連到記帳的舊車貸鏡像（點了捲到要確認）
        let id: UUID
        let source: Source
        let index: Int
        let status: Status
        let badge: String           // 「1」「停」；繳完 ""（畫勾）
        let title: String           // displayTitle（「車貸」「第 1 筆」或你取的名字）
        let range: String           // 「2024/10 – 2029/9・60 期」
        let amount: String          // 「NT$3.5萬/月」（/季、/年）
        let statusText: String      // 「第 25／60 期」「2026/12 開始」「已繳完」「已停止 2027/5」「賣出時結清」
        let progress: Double?       // 繳款中才有
        let nextText: String?       // 「下次 11/5 扣款」
        let isUnlinked: Bool
        let termMissing: Bool
        let canStop: Bool           // 繳款中、還沒開始才有「停止扣款」
        let deleteMessage: String   // 「會刪掉記帳裡這筆每月車貸（已繳的 25 期也會從帳本和淨資產走勢消失）和銀行的扣款紀錄，不能復原。只是不想再扣，請按「停止扣款」。」
        let accessibilityText: String
    }
    var trailing = ""               // 「1 筆・2029/9 繳完」「已繳完」「1 筆・2027/11 賣出」
    var soldNote: String? = nil     // 「車子 2027/11 賣掉了，車貸算到那天」
    var tiles: [VehicleTile] = []   // 六格／三格／繳完三格
    var principalHint: String? = nil// 「在車貸那筆填上總貸款金額，就能算出還欠多少本金、付了多少利息 →」
    var principalHintTap: VehicleTap = .none
    var sellLine: FinanceLine? = nil    // ①
    var totalLine: FinanceLine? = nil   // ②
    var rows: [Row] = []
    var footnote: String? = nil
}

// MARK: - 充電／加油／油電

struct VehicleEnergyData: Equatable {
    enum Collapsed: Equatable {
        case addFirst(text: String, kind: VehicleLedgerAddKind)   // 「＋ 記第一次充電（…）」→ addLedger(kind)
        case missingKwh(text: String, expenseId: UUID?)           // 「記了 4 筆電費，都沒填度數；…→」→ openExpense
    }
    struct Point: Identifiable, Equatable {
        let id: UUID                // 支出 id
        let date: Date
        let price: Double           // 每度電價
        let isHome: Bool
        let caption: String         // 「10/3・特斯拉超充 內湖・32 度・NT$9.5/度」
    }
    struct Chart: Equatable {
        var points: [Point] = []
        var average: Double = 0
        var hasHomeKeyword = false  // true：家充藍圓、外面橘三角
        var caption = "每一點是一次充電"
        var accessibilityText = ""  // 「6 次充電，每度 3.1 到 13.3 元，平均 7.9 元」
    }
    struct Block: Equatable {
        var heading: String? = nil  // 油電才有「充電」「加油」
        var tiles: [VehicleTile] = []
        var latestLine: String? = nil
        var hint: String? = nil     // 「還有 2 筆電費沒填度數，沒算進每度電價 →」「加油時多記公升數和里程錶（選填）…→」
        var hintTap: VehicleTap = .none
        var note: String? = nil     // 「還沒有家充紀錄：…」（不能點）
        var chart: Chart? = nil     // ≥ VehicleChargeAnalytics.minTrend 次才有
        var chartPending: String? = nil   // 「再記 N 次就畫每度電價圖」
    }
    var title = "充電"              // 「充電」「加油」「油電」
    var trailing = ""               // 「全部 6 次・2025/11 起」
    var collapsed: Collapsed? = nil // 有值時整區只畫這一行
    var blocks: [Block] = []
    var showsAnalytics = false      // 「充電與里程分析 ›」
    var footnote: String? = nil     // 電車：「度數是充電樁計的，…」
}

// MARK: - 我的帳本

enum VehicleLedgerBucket: String, Hashable, CaseIterable {
    case purchase, loan, fixed, energy, care, other

    /// 「買車」「車貸」「定期」「油電」「保養・維修」「停車・洗車・其他」（帳本的能源類一律叫「油電」，不隨動力改字）
    var title: String {
        switch self {
        case .purchase: return "買車"
        case .loan: return "車貸"
        case .fixed: return "定期"
        case .energy: return "油電"
        case .care: return "保養・維修"
        case .other: return "停車・洗車・其他"
        }
    }
}

enum VehicleLedgerFilter: Hashable, CaseIterable {
    case all, purchase, loan, fixed, energy, care, other

    /// 「全部」「買車」「車貸」「定期」「油電」「保養・維修」「停車・其他」（膠囊上的字比較短）
    var title: String {
        switch self {
        case .all: return "全部"
        case .other: return "停車・其他"
        default: return bucket?.title ?? "全部"
        }
    }

    var bucket: VehicleLedgerBucket? {
        switch self {
        case .all: return nil
        case .purchase: return .purchase
        case .loan: return .loan
        case .fixed: return .fixed
        case .energy: return .energy
        case .care: return .care
        case .other: return .other
        }
    }
}

/// 32pt 分類色圓裡的字
enum VehicleLedgerMark: String, Equatable {
    case purchase = "購", loan = "貸", insurance = "險", tax = "稅", subscription = "訂", rent = "租", fixedOther = "固",
         fuel = "油", charge = "充", parking = "停", maintenance = "保", repair = "修", wash = "洗", other = "其"

    var glyph: String { rawValue }

    /// 變動照子分類；固定：.rent 租、保險 險、.subscription 訂、貸款 貸、.other 每年扣「稅」否則「固」
    static func of(_ ex: Expense) -> VehicleLedgerMark {
        switch ex.expenseType {
        case .variable:
            return VehicleCardText.mark(ex.vehicleExpenseCategory)
        case .fixed:
            switch ex.fixedCategory {
            case .rent?: return .rent
            case .insurance?: return .insurance
            case .subscription?: return .subscription
            case .loan?: return .loan
            case .other?: return ex.recurrence == .yearly ? .tax : .fixedOther
            default: return .fixedOther
            }
        }
    }
}

/// 「＋ 記一筆」選單（順序＝選單順序，J378）
enum VehicleLedgerAddKind: String, CaseIterable, Identifiable {
    case charge, fuel, parking, maintenance, repair, wash, other, insurance, tax, parkingRent, subscription, carLoan, photo

    var id: String { rawValue }

    /// 「充電」「加油」「停車」「保養」「維修」「洗車」「其他」「保險」「稅費」「車位月租」「訂閱」「車貸」「照片紀錄」
    var title: String {
        switch self {
        case .charge: return "充電"
        case .fuel: return "加油"
        case .parking: return "停車"
        case .maintenance: return "保養"
        case .repair: return "維修"
        case .wash: return "洗車"
        case .other: return "其他"
        case .insurance: return "保險"
        case .tax: return "稅費"
        case .parkingRent: return "車位月租"
        case .subscription: return "訂閱"
        case .carLoan: return "車貸"
        case .photo: return "照片紀錄"
        }
    }

    var icon: String {
        if let cat = variableCategory { return cat.icon }
        switch self {
        case .insurance: return "shield.lefthalf.filled"
        case .tax: return "doc.text.fill"
        case .parkingRent: return "parkingsign"
        case .subscription: return "creditcard.fill"
        case .carLoan: return "banknote.fill"
        default: return "camera.fill"
        }
    }

    /// charge→.electricity、fuel→.fuel…；固定類與照片 nil
    var variableCategory: VehicleVariableCategory? {
        switch self {
        case .charge: return .electricity
        case .fuel: return .fuel
        case .parking: return .parking
        case .maintenance: return .maintenance
        case .repair: return .repair
        case .wash: return .wash
        case .other: return .other
        default: return nil
        }
    }

    /// insurance／tax／parkingRent／subscription／carLoan（AddVehicleView.makeFixedPreset 用）
    var fixedKind: AddVehicleView.FixedPresetKind? {
        switch self {
        case .insurance: return .insurance
        case .tax: return .tax
        case .parkingRent: return .parkingRent
        case .subscription: return .subscription
        case .carLoan: return .carLoan
        default: return nil
        }
    }

    /// 電車：charge…；油車／機車：fuel…；油電兩個都有
    static func menu(for power: VehiclePowerType) -> [VehicleLedgerAddKind] {
        let tail: [VehicleLedgerAddKind] = [.parking, .maintenance, .repair, .wash, .other,
                                            .insurance, .tax, .parkingRent, .subscription, .carLoan, .photo]
        switch power {
        case .electric, .electricMotorcycle: return [.charge] + tail
        case .gasoline, .motorcycle: return [.fuel] + tail
        case .hybrid: return [.charge, .fuel] + tail
        }
    }
}

struct VehicleLedgerEvent: Identifiable, Equatable {
    enum Source: Equatable {
        case expense(UUID)          // 記帳列（點→AddExpenseView）
        case purchase               // 買車列（點→編輯頁購入價）
        case loanYear(UUID, Int)    // 車貸年列（點→捲到車貸）
        case fixedYear(UUID, Int)   // 定期年列（點→那筆固定支出）
        case legacy(UUID)           // 沒連到記帳的舊變動鏡像（鏡像 id；點→說明框 補建／移除）
    }
    let id: String
    let date: Date
    let bucket: VehicleLedgerBucket
    let title: String               // VehicleFacts.label；買車「買下 Taycan」；年列「車貸 1–10 月・10 期」「停車月租・10 期」
    let detail: String              // 「32.0 度・20% → 80%・12,345 公里」「40.2 公升・每公升 NT$29.1」「20,100 公里・備註」
    let amount: Double
    let source: Source
    let mark: VehicleLedgerMark
    let year: Int
    let dayText: String             // 「03」
    let monthText: String           // 「2026/10」
    let amountText: String          // MoneyFormat.short
    let photoFileNames: [String]    // 收據膠囊（只有圖片；空＝不放膠囊）
    let isUnlinked: Bool            // 灰色小標「沒連到記帳」
    let warnTag: String?            // 注意色小標「自備款不知道」
    let countsInTotal: Bool         // 買車列算不出自備款時 false（不進合計、不進年份小計）
    let expenseId: UUID?
    let canDelete: Bool             // 只有 .expense 是 true
    let shareTitle: String          // 分享用：分類名（「充電」「加油」「車位租金」…；買車列「買下 <shareName>」）
    let shareDetail: String         // 分享用：拿掉里程、備註
    let accessibilityText: String

    /// 車貸年列、定期年列（不是一筆真正的記帳）
    var isYearRow: Bool {
        switch source {
        case .loanYear, .fixedYear: return true
        default: return false
        }
    }
}

struct VehicleLedgerYear: Identifiable, Equatable {
    let year: Int
    let events: [VehicleLedgerEvent]
    let recordCount: Int
    let total: Double
    let title: String
    let isCurrent: Bool
    var id: Int { year }
}

struct VehicleLedgerFilterChip: Identifiable, Equatable {
    let filter: VehicleLedgerFilter
    let amount: Double
    let text: String
    let rowCount: Int
    var id: VehicleLedgerFilter { filter }
}

struct VehicleLedgerPart: Identifiable, Equatable {
    let bucket: VehicleLedgerBucket
    let value: Double
    let legend: String
    var id: VehicleLedgerBucket { bucket }
}

struct VehicleLedger {
    var events: [VehicleLedgerEvent] = []       // 新到舊（含買車列、年列）；匯出逐筆也照這個順序
    var recordCount = 0                          // 記帳列＋舊鏡像列（不含買車列、年列）
    var recordsTitle = "紀錄"                    // 「紀錄・38 筆」
    /// 除了買車列一列都沒有
    var isEmpty: Bool { events.allSatisfy { $0.source == .purchase } }
    var headerTrailing = ""                      // 「從 2024/9 買下」
    var unit: Double = 1
    var total: Double = 0
    var rawTotals: [VehicleLedgerBucket: Double] = [:]
    var totals: [VehicleLedgerBucket: Double] = [:]
    var downPayment: Double? = nil               // D；算不出 nil
    var tiles: [VehicleTile] = []                // 沒紀錄時只有「買車」「估值」
    /// [v25.540] 分享圖用的格子：跟 tiles 一樣，只是「定期」小字的名稱改寫分類名（「車位租金・26 期」）。
    /// 你自己取的支出名稱可能寫了地址或人名，分享一律不輸出（J494）
    var shareTiles: [VehicleTile] = []
    var totalLabel = "到今天總共付了"            // 已售「到賣出那天總共付了」
    var totalText = ""
    var parts: [VehicleLedgerPart] = []
    var spentLine: FinanceLine? = nil            // 「照估值今天賣掉拿回 …；這台車到今天實際花了你 約 …：折舊 …＋養車 …。」
    var spent: Double? = nil                     // 實際花了 Y（已售出膠囊「實際花了」「連折舊每月」用同一個數）
    var emptyHint: String? = nil                 // J433
    var filters: [VehicleLedgerFilterChip] = []
    var yearsByFilter: [VehicleLedgerFilter: [VehicleLedgerYear]] = [:]
    var addKinds: [VehicleLedgerAddKind] = []    // VehicleLedgerAddKind.menu(for:)

    func years(for filter: VehicleLedgerFilter) -> [VehicleLedgerYear] {
        yearsByFilter[filter] ?? []
    }

    func amount(_ bucket: VehicleLedgerBucket) -> Double {
        totals[bucket] ?? 0
    }
}

// MARK: - 車輛資料、照片

struct VehicleInfoData: Equatable {
    enum RowKind: Equatable { case plain, warning, note }
    struct Row: Identifiable, Equatable {
        let id: String              // car、power、purchase、value、valueStale、odometer、home、owner、sold、note
        let label: String           // 寬 84；warning 列 ""
        let value: String
        var kind: RowKind = .plain
        var tap: VehicleTap = .none // 估值 .edit(.value)、動力（電池）.edit(.battery)、家充 .edit(.homeCharge)、售出 .edit(.sold)
        var detail: String? = nil   // 估值列下的灰字「一般每年折 15% 估：約 NT$254.5萬，差不多」
        var detailAction: String? = nil  // 「更新估值 ›」（點了同 tap）
    }
    var trailing = ""               // 「電車」
    var rows: [Row] = []
    var hint: String? = nil         // 「補上品牌、車主、電池容量 → 編輯」（點→edit(.brand)）
}

struct VehicleMediaData: Equatable {
    struct Item: Identifiable, Equatable {
        enum Source: Equatable { case record(UUID), expense(UUID) }
        let id: String              // 「record-<uuid>」「expense-<uuid>」
        let source: Source
        let title: String           // 照片紀錄 title 空→分類名；支出→VehicleFacts.label
        let date: Date
        let dateText: String        // FinanceFormat.shortDate(date, now:)
        let category: VehiclePhotoCategory?   // nil＝支出（徽章「支出」）
        let fileNames: [String]     // 只有圖片（PDF 不算）；照片紀錄可能是空的（點了開編輯）
        let note: String
        let isCover: Bool
    }
    var photoCount = 0
    var trailing: String? = nil     // 「12 張」
    var items: [Item] = []          // 封面先，其他新到舊
    var isEmpty: Bool { items.isEmpty }
}

// MARK: - 整張卡

struct VehicleCardData {
    let vehicleId: UUID
    let name: String                // 車名 trim，空白「未命名車輛」（工具列、VoiceOver）
    let shareName: String           // VehicleScriptName.shareName(v)
    let vehicle: Vehicle
    let facts: VehicleFacts
    let scene: FinDriveScene
    let ledger: VehicleLedger
    let checks: [VehicleCheck]      // 已排好：賣了還在扣第一、記成其他的車險第二，其他照 J141–154 順序

    var seed = 0                    // MoneyItem.seed(v.id)
    var isSold = false
    var asOf = Date()
    var isBlank = false             // 沒車貸、帳本除了買車列沒有任何列
    var powerWord = ""              // powerType.shortName
    var board = VehicleCardBoardData()
    var progress: FinanceProgressData? = nil      // title「車貸進度」；沒車貸／已售／全部繳完／沒填年限時 nil
    var progressNote: VehicleProgressNote? = nil
    var chips: [MoneyBoardChip] = []              // 最多 6 顆
    var checksTrailing: String? = nil             // 「2 件」
    var monthly: VehicleMonthlyData? = nil        // 合計 < 1 或已售出 nil
    var upcoming: VehicleUpcomingData? = nil      // 已售出或一列都沒有且沒提示 nil
    var loan: VehicleLoanSectionData? = nil       // 沒有任何車貸（含舊鏡像）nil
    var energy: VehicleEnergyData? = nil          // 電動機車沒度數 nil
    var info = VehicleInfoData()
    var media = VehicleMediaData()
    var shareHeader = ""                          // 「🚗 載具｜<shareName>」
    var shareFileBase = ""                        // 「車輛卡片_<shareName>」（D 再 sanitize＋時間戳）

    static func build(_ v: Vehicle, vehicles: [Vehicle], expense: ExpenseStore, now: Date = Date()) -> VehicleCardData {
        build(v, vehicles: vehicles, expenses: expense.expenses, ntd: { expense.ntdValue(of: $0) }, now: now)
    }

    static func build(_ v: Vehicle, vehicles: [Vehicle], expenses: [Expense], ntd: (Expense) -> Double,
                      now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> VehicleCardData {
        let facts = VehicleFacts.build(v, expenses: expenses, ntd: ntd, now: now, calendar: calendar)
        let links = VehicleLinks.make(v, expenses: expenses)
        let money = Dictionary(expenses.map { ($0.id, ntd($0)) }, uniquingKeysWith: { a, _ in a })
        let c = VehicleCardContext.make(v, vehicles: vehicles, facts: facts, links: links, expenses: expenses,
                                        money: money, now: now, calendar: calendar)
        let ledger = VehicleLedger.build(c)
        let checks = VehicleCheck.build(c)
        let scene = sceneData(c)

        var d = VehicleCardData(vehicleId: v.id, name: c.name, shareName: c.shareName, vehicle: v, facts: facts,
                                scene: scene, ledger: ledger, checks: checks)
        d.seed = MoneyItem.seed(v.id)
        d.isSold = facts.isSold
        d.asOf = facts.asOf
        d.isBlank = !c.hasAnyLoan && ledger.isEmpty
        d.powerWord = v.powerType.shortName
        d.checksTrailing = checks.isEmpty ? nil : "\(checks.count) 件"
        d.loan = loanSectionData(c)
        d.energy = energyData(c)
        d.monthly = monthlyData(c, hasLoanSection: d.loan != nil, hasEnergySection: d.energy != nil)
        d.upcoming = upcomingData(c)
        let kind = lineKind(c, isBlank: d.isBlank)
        d.board = boardData(c, kind: kind)
        let prog = progressData(c)
        d.progress = prog.data
        d.progressNote = prog.note
        d.chips = chipsData(c, ledger: ledger, kind: kind)
        d.info = infoData(c)
        d.media = mediaData(c)
        d.shareHeader = "🚗 載具｜\(c.shareName)"
        d.shareFileBase = "車輛卡片_\(c.shareName)"
        return d
    }

    /// 換車列膠囊（本版定案 9）：只讀車子欄位、不建 facts。V 的規則跟 VehicleFacts.build 一樣
    ///（已售出有成交價→成交價；估值 0 又沒更新日→購入價；否則估值）。持有「260萬」、已售「賣 110萬」，一律中性色
    static func switcherTrailing(_ v: Vehicle, now: Date = Date()) -> (text: String, tone: MoneyTone)? {
        let sold = v.isSold(asOf: now)
        let value: Double
        if sold, let sp = v.soldPrice, sp > 0 {
            value = sp
        } else if v.currentValue <= 0, v.valueUpdatedAt == nil, v.purchasePrice > 0 {
            value = v.purchasePrice
        } else {
            value = max(0, v.currentValue)
        }
        guard value > 0 else { return nil }
        let text = sold ? "賣 \(MoneyFormat.compact(value))" : MoneyFormat.compact(value)
        return (text: text, tone: MoneyTone.neutral)
    }
}

// MARK: - 建資料時共用的東西

private struct VehicleCardContext {
    let v: Vehicle
    let vehicles: [Vehicle]
    let facts: VehicleFacts
    let links: VehicleLinks
    /// 全部的記帳（「沒指定車」要看別的支出）
    let expenses: [Expense]
    let byId: [UUID: Expense]
    /// 每筆支出的台幣金額（ExpenseStore.ntdValue）
    let money: [UUID: Double]
    let now: Date
    /// 今天；已售出＝賣出日（facts.asOf）
    let asOf: Date
    let cal: Calendar
    let name: String
    let shareName: String
    /// 沒連到記帳的舊車貸鏡像（含記帳找不到的孤兒）
    let legacyLoans: [VehicleFixedExpense]
    /// [v25.541] 這台車記成「其他」的車險（要確認、每月養車的保險提示都讀這一份，依日期）
    let insuranceAsOther: [Expense]

    var isSold: Bool { facts.isSold }
    var today: Date { cal.startOfDay(for: now) }
    var thisMonth: Date { VehicleFacts.monthStart(asOf, cal) }
    /// 有任何車貸（記帳的車貸或舊車貸鏡像）
    var hasAnyLoan: Bool { !facts.loans.isEmpty || !legacyLoans.isEmpty }

    func amount(_ ex: Expense) -> Double { money[ex.id] ?? ex.amount }

    func onOrBeforeAsOf(_ d: Date) -> Bool {
        cal.startOfDay(for: d) <= cal.startOfDay(for: asOf)
    }

    /// [v25.541] 每月養車的期間內（facts.periodStart～asOf）有扣到款，算法同 VehicleFacts 的 missingInsurance：
    /// 記成「其他」的車險改成保險之後，期間內有扣款的才會讓「沒連到保險」消失
    func debitedInPeriod(_ ex: Expense) -> Bool {
        let start = cal.startOfDay(for: facts.periodStart)
        if ex.isRecurringFixed {
            let dayBefore = cal.date(byAdding: .day, value: -1, to: start) ?? start
            return ex.fixedPeriodCount(until: asOf, calendar: cal) - ex.fixedPeriodCount(until: dayBefore, calendar: cal) > 0
        }
        let day = cal.startOfDay(for: ex.date)
        return day >= start && day <= cal.startOfDay(for: asOf)
    }

    static func make(_ v: Vehicle, vehicles: [Vehicle], facts: VehicleFacts, links: VehicleLinks, expenses: [Expense],
                     money: [UUID: Double], now: Date, calendar: Calendar) -> VehicleCardContext {
        let byId = Dictionary(expenses.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let trimmed = v.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyLoans = links.legacyFixed.filter { $0.category == .carLoan }
        let asOther = links.expenses.filter { VehicleFixes.isInsuranceAsOther($0) }
        return VehicleCardContext(v: v, vehicles: vehicles, facts: facts, links: links, expenses: expenses, byId: byId,
                                  money: money, now: now, asOf: facts.asOf, cal: calendar,
                                  name: trimmed.isEmpty ? "未命名車輛" : trimmed,
                                  shareName: VehicleScriptName.shareName(v), legacyLoans: legacyLoans,
                                  insuranceAsOther: asOther)
    }
}

/// 看板那一句是哪一型（膠囊「每月養車」只在那一句沒寫每月養車時放）
private enum VehicleCardLineKind: Equatable {
    /// 剛建好的空車
    case blank
    /// 沒車貸、車貸全部繳完或停掉：「每月養車 約 …・折舊每月 約 …」
    case plain
    /// 有在扣但沒填年限、也沒有別筆算得出的車貸（定案 12）
    case termMissing
    /// 車貸還沒開始扣
    case notStarted
    /// 算不出本金：「車貸還要繳 …（含利息）」
    case scheduled
    /// 算得出本金：「扣掉車貸本金，真正是你的 約 …」
    case equity
    case sold
}

/// 卡片上的小字（一位小數、千分位、公里、唸給 VoiceOver 的金額）
private enum VehicleCardText {
    /// 每度、每公升、每公里一律一位小數（7.94 → 7.9；整數不寫 .0）
    static func n1(_ v: Double) -> String { FinanceItemText.number(v, digits: 1) }

    /// 帳本細字的度數、公升固定一位小數（「32.0 度」）
    static func fixed1(_ v: Double) -> String { String(format: "%.1f", v) }

    /// 公里數取整數加千分位（「12,345」）
    static func grouped(_ v: Double) -> String { FinanceItemText.number(v.rounded(), digits: 0) }

    /// 累計度數、公升：1000 以上不寫小數
    static func amount1(_ v: Double) -> String { v >= 1_000 ? grouped(v) : n1(v) }

    /// 「20%」
    static func pct(_ v: Double) -> String {
        guard v.isFinite else { return "" }
        return "\(Int(v.rounded()))%"
    }

    /// 一年約開：≥ 1 萬「1.2萬 公里」，未滿 1 萬取到百位「900 公里」
    static func kmText(_ km: Double) -> String {
        if km >= 10_000 {
            let w = (km / 1_000).rounded() / 10
            let t = w == w.rounded() ? String(format: "%.0f", w) : String(format: "%.1f", w)
            return "\(t)萬 公里"
        }
        return "\(grouped((km / 100).rounded() * 100)) 公里"
    }

    /// 唸給 VoiceOver：1 萬以上「260 萬」，以下「5,200 元」
    static func spokenMoney(_ v: Double) -> String {
        let s = FinanceFormat.spoken(v)
        return abs(v) >= 10_000 ? s : "\(s) 元"
    }

    /// 「2029 年 9 月」
    static func spokenYM(_ d: Date) -> String {
        let c = FinanceFormat.calendar.dateComponents([.year, .month], from: d)
        return "\(c.year ?? 0) 年 \(c.month ?? 0) 月"
    }

    /// 備註第一行（空的回 nil）
    static func firstLine(_ s: String) -> String? {
        let memo = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = memo.split(separator: "\n").first else { return nil }
        let line = String(first).trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : line
    }

    /// 「「停車月租」「訂閱」」；超過 3 個寫「「a」「b」「c」等 5 筆」
    static func quotedNames(_ names: [String]) -> String {
        var unique: [String] = []
        for n in names where !unique.contains(n) { unique.append(n) }
        let head = unique.prefix(3).map { "「\($0)」" }.joined()
        return unique.count > 3 ? "\(head)等 \(unique.count) 筆" : head
    }

    /// 「/月」「/季」「/年」
    static func periodUnit(_ months: Int) -> String {
        switch months {
        case 3: return "/季"
        case 12: return "/年"
        default: return "/月"
        }
    }

    /// 「每月」「每季」「每年」
    static func periodWord(_ months: Int) -> String {
        switch months {
        case 3: return "每季"
        case 12: return "每年"
        default: return "每月"
        }
    }

    /// 變動支出子分類 → 分類圓的字
    static func mark(_ c: VehicleVariableCategory?) -> VehicleLedgerMark {
        switch c {
        case .fuel?: return .fuel
        case .electricity?: return .charge
        case .parking?: return .parking
        case .maintenance?: return .maintenance
        case .repair?: return .repair
        case .wash?: return .wash
        case .other?, nil: return .other
        }
    }

    /// 分享圖的列標題：只寫分類（自己取的名字、地點可能有地址或人名，一律不輸出）
    static func shareCategory(_ c: VehicleVariableCategory?) -> String {
        switch c {
        case .fuel?: return "加油"
        case .electricity?: return "充電"
        case .parking?: return "停車"
        case .maintenance?: return "保養"
        case .repair?: return "維修"
        case .wash?: return "洗車"
        case .other?, nil: return "其他"
        }
    }

    static func shareTitle(_ ex: Expense) -> String {
        ex.expenseType == .variable ? shareCategory(ex.vehicleExpenseCategory) : VehicleFacts.categoryLabel(ex)
    }

    /// 帳本細字的度數／公升（分享也會寫）：充電「32.0 度・20% → 80%」、加油「40.2 公升・每公升 NT$29.1」
    static func measures(_ ex: Expense, amount: Double) -> [String] {
        guard ex.expenseType == .variable else { return [] }
        var out: [String] = []
        switch ex.vehicleExpenseCategory {
        case .electricity?:
            if let k = ex.evKwh, k > 0 { out.append("\(fixed1(k)) 度") }
            if let a = ex.evFromPct, let b = ex.evToPct { out.append("\(pct(a)) → \(pct(b))") }
        case .fuel?:
            if let l = ex.fuelLiters, l > 0 {
                out.append("\(fixed1(l)) 公升")
                out.append("每公升 NT$\(n1(amount / l))")
            }
        default:
            break
        }
        return out
    }

    /// 里程錶「12,345 公里」（分享不寫）
    static func odometer(_ ex: Expense) -> String? {
        guard let km = ex.odometer, km > 0, km.isFinite else { return nil }
        return "\(grouped(km)) 公里"
    }

    /// 手寫問候第二行可以直接寫車名：英數字（可以有空白）、不超過 12 字
    static func isScriptFriendly(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 48...57, 65...90, 97...122, 32: return true
        default: return false
        }
    }
}

// MARK: - 看板

extension VehicleCardData {
    fileprivate static func lineKind(_ c: VehicleCardContext, isBlank: Bool) -> VehicleCardLineKind {
        let f = c.facts
        if c.isSold { return .sold }
        if isBlank { return .blank }
        let active = f.loans.filter { $0.status == .paying || $0.status == .notStarted }
        if active.isEmpty { return .plain }
        // 定案 12：有在扣但沒填年限（沒算進 owed）、又沒有別筆算得出的車貸，不能寫「真正是你的」
        if f.owedMissingTerm && !active.contains(where: { !$0.termIsGuess }) { return .termMissing }
        if !active.contains(where: { $0.status == .paying }) { return .notStarted }
        return f.owedIsScheduled ? .scheduled : .equity
    }

    fileprivate static func boardData(_ c: VehicleCardContext, kind: VehicleCardLineKind) -> VehicleCardBoardData {
        let v = c.v
        let f = c.facts
        var b = VehicleCardBoardData()
        let brand = v.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        b.greeting = [greetingFirst(c), greetingName(v)]
        if c.isSold {
            fillSoldBoard(&b, c: c, brand: brand)
            return b
        }
        b.date = brand.isEmpty ? v.powerType.shortName : "\(brand)・\(v.powerType.shortName)"
        b.dateIcon = v.powerType.icon
        let spokenCapsule = fillCapsule(&b, f: f)
        b.label = f.valueIsFallback ? "車輛估值（還沒填，先用購入價）" : "車輛估值"
        b.big = MoneyFormat.short(f.value)
        let spokenLine = fillLine(&b, c: c, kind: kind)
        var spoken = "\(c.name)，\(b.label) \(VehicleCardText.spokenMoney(f.value))"
        if !spokenCapsule.isEmpty { spoken += "，\(spokenCapsule)" }
        if !spokenLine.isEmpty { spoken += "，\(spokenLine)" }
        b.accessibilityText = spoken
        return b
    }

    /// 「Drive safe,」；機車、電動機車「Ride safe,」；已售出「So long,」
    fileprivate static func greetingFirst(_ c: VehicleCardContext) -> String {
        if c.isSold { return "So long," }
        switch c.v.powerType {
        case .motorcycle, .electricMotorcycle: return "Ride safe,"
        default: return "Drive safe,"
        }
    }

    /// 車名全是英數字、不超過 12 字、不像車牌就寫車名；否則品牌英文；都沒有「my ride!」（手寫字型沒有中文字形）
    fileprivate static func greetingName(_ v: Vehicle) -> String {
        let name = v.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let friendly = !name.isEmpty && name.count <= 12 && name.unicodeScalars.allSatisfy { VehicleCardText.isScriptFriendly($0) }
        if friendly && !VehicleScriptName.looksLikePlate(name) { return name }
        return VehicleScriptName.word(v) ?? "my ride!"
    }

    /// 右上膠囊：折舊中性 ▼、增值紅 ▲、差不到 0.5% 持平（決定 1）；估值還沒填不出。回傳給 VoiceOver 的字
    fileprivate static func fillCapsule(_ b: inout VehicleCardBoardData, f: VehicleFacts) -> String {
        guard let r = f.depreciationRate else { return "" }
        if abs(r) < 0.005 {
            b.capsule = "持平"
            b.capsuleIcon = "equal.circle.fill"
            return "跟買價持平"
        }
        if r < 0 {
            b.capsule = "折舊 ▼\(FinanceText.percent1(-r))"
            b.capsuleIcon = "arrow.down.right"
            return "折舊 \(FinanceText.percent1(-r))"
        }
        b.capsule = "增值 ▲\(FinanceText.percent1(r))"
        b.capsuleIcon = "arrow.up.right"
        b.capsuleTone = .up
        return "增值 \(FinanceText.percent1(r))"
    }

    /// 一句話（依狀態選一句，金額粗體）。回傳給 VoiceOver 的字
    fileprivate static func fillLine(_ b: inout VehicleCardBoardData, c: VehicleCardContext, kind: VehicleCardLineKind) -> String {
        let f = c.facts
        let active = f.loans.filter { $0.status == .paying || $0.status == .notStarted }
        switch kind {
        case .sold:
            return ""
        case .blank:
            let s = "還沒有養車紀錄，從下面「我的帳本」記第一筆"
            b.line = FinanceLine.text(s)
            return s
        case .plain:
            return fillPlainLine(&b, f: f)
        case .termMissing:
            let m = active.filter { $0.termIsGuess }.reduce(0.0) { $0 + $1.monthly }
            b.line = FinanceLine(runs: [
                FinanceRun(text: "車貸每月 "),
                FinanceRun(text: MoneyFormat.short(m), bold: true),
                FinanceRun(text: "・沒填年限，算不出還欠多少")
            ])
            return b.line.plain
        case .notStarted:
            let firstDue = active.map { $0.firstDue }.min() ?? c.asOf
            let month = VehicleFacts.monthStart(firstDue, c.cal)
            let m = active.filter { $0.isPaying(inMonth: month, calendar: c.cal) }.reduce(0.0) { $0 + $1.monthly }
            b.line = FinanceLine(runs: [
                FinanceRun(text: "車貸 \(FinanceFormat.ym(firstDue)) 開始・到時每月 "),
                FinanceRun(text: MoneyFormat.short(m), bold: true)
            ])
            return b.line.plain
        case .scheduled:
            let left = active.reduce(0.0) { $0 + $1.left }
            var tail = "（含利息）"
            if !active.contains(where: { $0.termIsGuess }), let payoff = active.compactMap({ $0.payoffDate }).max() {
                tail += "・\(FinanceFormat.ym(payoff)) 繳完"
            }
            b.line = FinanceLine(runs: [
                FinanceRun(text: "車貸還要繳 "),
                FinanceRun(text: MoneyFormat.short(left), bold: true),
                FinanceRun(text: tail)
            ])
            return b.line.plain
        case .equity:
            return fillEquityLine(&b, f: f)
        }
    }

    /// 沒車貸（或車貸繳完、停掉）：「每月養車 約 NT$5,200・折舊每月 約 NT$3.9萬」，兩個數分開寫、不相加（決定 3）
    fileprivate static func fillPlainLine(_ b: inout VehicleCardBoardData, f: VehicleFacts) -> String {
        var runs: [FinanceRun] = []
        var spoken: [String] = []
        if let m = FinanceText.about100(f.monthly) {
            runs.append(FinanceRun(text: "每月養車 "))
            runs.append(FinanceRun(text: m, bold: true))
            spoken.append("每月養車約 \(VehicleCardText.spokenMoney(FinanceRound.round(f.monthly, unit: 100)))")
        }
        if let d = f.depreciationMonthly, let dt = FinanceText.about100(d) {
            runs.append(FinanceRun(text: runs.isEmpty ? "折舊每月 " : "・折舊每月 "))
            runs.append(FinanceRun(text: dt, bold: true))
            spoken.append("折舊每月約 \(VehicleCardText.spokenMoney(FinanceRound.round(d, unit: 100)))")
        }
        guard !runs.isEmpty else {
            let s = "近 \(f.periodMonths) 個月沒有養車紀錄"
            b.line = FinanceLine.text(s)
            return s
        }
        b.line = FinanceLine(runs: runs)
        return spoken.joined(separator: "，")
    }

    /// 算得出本金：「扣掉車貸本金，真正是你的 約 NT$148.3萬（57%）」；本金是反推的，一律寫「約」（定案 12）
    fileprivate static func fillEquityLine(_ b: inout VehicleCardBoardData, f: VehicleFacts) -> String {
        let equity = f.equity
        let tone: MoneyTone = equity >= 0 ? .good : .bad
        let about = (!f.owedIsScheduled && f.owed > 0) ? "約 " : ""
        let share: Double = f.value > 0 ? max(0, equity) / f.value : 0
        let shareText = f.value > 0 ? "（\(MoneyFormat.percent(share))）" : ""
        b.line = FinanceLine(runs: [
            FinanceRun(text: "扣掉車貸本金，真正是你的 \(about)"),
            FinanceRun(text: MoneyFormat.short(equity), bold: true, tone: tone),
            FinanceRun(text: shareText)
        ])
        let aboutSpoken = about.isEmpty ? " " : "約 "
        var s = "扣掉車貸本金，真正是你的\(aboutSpoken)\(VehicleCardText.spokenMoney(equity))"
        if f.value > 0 { s += "，占 \(MoneyFormat.percent(share))" }
        return s
    }

    /// 已售出：日期列「Porsche・已售出」、膠囊「持有 3 年 2 個月」、大字賣出價差（ASCII「-」，虧損中性、賺 .up）
    fileprivate static func fillSoldBoard(_ b: inout VehicleCardBoardData, c: VehicleCardContext, brand: String) {
        let v = c.v
        let f = c.facts
        b.date = brand.isEmpty ? "已售出" : "\(brand)・已售出"
        b.dateIcon = "checkmark.seal.fill"
        let soldDay = v.soldDate ?? c.asOf
        if let held = FinanceFormat.lived(from: v.purchaseDate, to: soldDay) {
            b.capsule = "持有 \(held)"
            b.capsuleIcon = "clock.fill"
        }
        if f.saleUsesEstimate {
            // 成交價沒填用估值；估值也是 0 時 facts 退回購入價，不能寫成「用估值」
            b.label = f.valueIsFallback ? "賣出價差（成交價沒填，先用購入價）" : "賣出價差（用估值當賣價）"
        } else {
            b.label = "賣出價差"
        }
        let diff = f.value - f.purchase
        let diffText = FinanceText.signed(diff)
        b.big = diffText
        b.bigTone = diff >= 1 ? .up : nil
        let boughtAt = FinanceFormat.ym(v.purchaseDate)
        let soldAt = FinanceFormat.ym(soldDay)
        let boughtFor = MoneyFormat.short(f.purchase)
        let soldFor = MoneyFormat.short(f.value)
        let s = "\(boughtAt) 用 \(boughtFor) 買 → \(soldAt) 用 \(soldFor) 賣"
        b.line = FinanceLine.text(s)
        b.accessibilityText = "\(c.name)，已售出，賣出價差 \(diffText)，\(s)"
    }

    // MARK: 風景

    /// FinDriveScene：asOf 那個月往前 11 個月～往後 4 個月月初；位置一律換成 0…1，畫的地方不碰日期
    fileprivate static func sceneData(_ c: VehicleCardContext) -> FinDriveScene {
        let cal = c.cal
        let v = c.v
        let f = c.facts
        let m0 = VehicleFacts.monthStart(c.asOf, cal)
        let w0 = cal.date(byAdding: .month, value: -11, to: m0) ?? m0
        let w1 = cal.date(byAdding: .month, value: 4, to: m0) ?? m0
        let span = Double(max(1, cal.dateComponents([.day], from: w0, to: w1).day ?? 1))
        func t(_ d: Date) -> Double {
            let days = cal.dateComponents([.day], from: w0, to: cal.startOfDay(for: d)).day ?? 0
            return min(1, max(0, Double(days) / span))
        }

        var s = FinDriveScene()
        s.today = t(c.asOf)
        s.todayLabel = c.isSold ? "" : "今天"
        if c.isSold {
            let soldMonth = VehicleFacts.monthStart(v.soldDate ?? c.asOf, cal)
            let next = cal.date(byAdding: .month, value: 1, to: soldMonth) ?? soldMonth
            s.roadEnd = t(next)
        }
        let buy = cal.startOfDay(for: v.purchaseDate)
        if buy >= w0 && buy <= w1 { s.purchaseT = t(buy) }
        s.marks = sceneMarks(c, from: w0, position: t)
        s.signs = c.isSold ? [] : sceneSigns(c, until: w1, position: t)
        var ticks: [FinDriveScene.Tick] = []
        for i in 0...15 {
            guard let d = cal.date(byAdding: .month, value: i, to: w0) else { continue }
            ticks.append(FinDriveScene.Tick(t: t(d), label: tickLabel(d, cal: cal)))
        }
        s.ticks = ticks
        switch v.powerType {
        case .motorcycle, .electricMotorcycle: s.shape = .scooter
        default: s.shape = .car
        }
        switch v.powerType {
        case .electric, .electricMotorcycle: s.badge = .bolt
        case .hybrid: s.badge = .plug
        default: s.badge = .none
        }
        let theme = VehicleScriptName.theme(v)
        s.bodyTop = theme.top
        s.bodyBottom = theme.bottom
        // 車貸斜線：賣掉了、還沒開始扣（還不欠）都不畫
        let started = f.loans.contains { $0.status == .paying }
        if !c.isSold, f.owed > 0, f.value > 0, started {
            let fraction = min(1, f.owed / f.value)
            s.owedFraction = fraction
            let head = f.owedIsScheduled ? "還要繳" : "車貸"
            s.owedLabel = "\(head) \(MoneyFormat.percent(fraction))"
        }
        s.isSold = c.isSold
        s.name = MoneyBoardText.short(c.shareName, max: 8)
        return s
    }

    /// 刻度字：1 月寫年份「2027」、4／7／10 月寫「M月」，其他空字串（只畫刻度）
    fileprivate static func tickLabel(_ d: Date, cal: Calendar) -> String {
        let month = cal.component(.month, from: d)
        if month == 1 { return String(cal.component(.year, from: d)) }
        if month == 4 || month == 7 || month == 10 { return "\(month)月" }
        return ""
    }

    /// 圓標：W0…asOf 每個日曆月一顆（購入月之前不放），金額＝帳本裡那個月的變動支出（跟列表看板同一個條件），
    /// 種類照 FinRoadScene.Kind.of 取金額最大的那一類
    fileprivate static func sceneMarks(_ c: VehicleCardContext, from w0: Date, position t: (Date) -> Double) -> [FinDriveScene.Mark] {
        let cal = c.cal
        let asOfDay = cal.startOfDay(for: c.asOf)
        var totals: [Date: Double] = [:]
        var kinds: [Date: [FinRoadScene.Kind: Double]] = [:]
        func add(_ d: Date, _ kind: FinRoadScene.Kind, _ amount: Double) {
            let day = cal.startOfDay(for: d)
            guard amount > 0, day >= w0, day <= asOfDay else { return }
            let m = VehicleFacts.monthStart(d, cal)
            totals[m, default: 0] += amount
            kinds[m, default: [:]][kind, default: 0] += amount
        }
        for ex in c.links.expenses {
            guard ex.expenseType == .variable || (!ex.isRecurringFixed && ex.fixedCategory != .loan) else { continue }
            add(ex.date, FinRoadScene.Kind.of(ex.vehicleExpenseCategory ?? .other), c.amount(ex))
        }
        for m in c.links.legacyVariable {
            add(m.date, FinRoadScene.Kind.of(m.category), m.amount)
        }
        let purchaseMonth = VehicleFacts.monthStart(c.v.purchaseDate, cal)
        let order: [FinRoadScene.Kind] = [.fuel, .charge, .care, .park, .other]
        var out: [FinDriveScene.Mark] = []
        for m in totals.keys.sorted() where m >= purchaseMonth {
            let byKind = kinds[m] ?? [:]
            var kind = FinRoadScene.Kind.other
            var best = -1.0
            for k in order {
                let value = byKind[k] ?? 0
                if value > best {
                    best = value
                    kind = k
                }
            }
            // 那個日曆月的中點；asOf 那個月只算到今天，圓標才不會跑到車前面
            let next = cal.date(byAdding: .month, value: 1, to: m) ?? m
            let end = next > c.asOf ? c.asOf : next
            let mid = (t(m) + t(end)) / 2
            out.append(FinDriveScene.Mark(t: mid, kind: kind, amount: totals[m] ?? 0))
        }
        return out
    }

    /// 路牌：「接下來」裡今天到 W1 之間的前 3 件（每月扣的不放），字跟列表看板同一套；同字只放一塊。
    /// 超過預計日期的保養改成橘牌「該保養了」（插在今天）；車貸繳完日在範圍內插一塊「車貸繳完」
    fileprivate static func sceneSigns(_ c: VehicleCardContext, until w1: Date, position t: (Date) -> Double) -> [FinDriveScene.Sign] {
        let cal = c.cal
        let f = c.facts
        let today = c.today
        var picked: [(date: Date, sign: FinDriveScene.Sign)] = []
        func add(_ date: Date, _ sign: FinDriveScene.Sign) {
            guard !picked.contains(where: { $0.sign.label == sign.label }) else { return }
            picked.append((date: date, sign: sign))
        }
        for u in f.upcoming {
            if case .maintenance = u.kind, (u.overdueDays ?? 0) > 0 {
                add(today, FinDriveScene.Sign(t: t(today), label: "該保養了", isWarn: true))
                continue
            }
            let day = cal.startOfDay(for: u.date)
            guard day >= today, day < w1, !isMonthly(u, c: c) else { continue }
            add(day, FinDriveScene.Sign(t: t(day), label: VehicleBoardData.signLabel(u, byId: c.byId)))
        }
        let active = f.loans.filter { $0.status == .paying || $0.status == .notStarted }
        if !active.isEmpty, !active.contains(where: { $0.termIsGuess }),
           let payoff = active.compactMap({ $0.payoffDate }).max() {
            let day = cal.startOfDay(for: payoff)
            if day > today && day <= w1 {
                add(day, FinDriveScene.Sign(t: t(day), label: "車貸繳完"))
            }
        }
        let sorted = picked.sorted { a, b in a.date != b.date ? a.date < b.date : a.sign.label < b.sign.label }
        return sorted.prefix(3).map { $0.sign }
    }

    /// 每月扣的（停車月租、月繳車貸）不上路牌：每個月都一塊會把路牌擠滿
    fileprivate static func isMonthly(_ u: VehicleUpcoming, c: VehicleCardContext) -> Bool {
        switch u.kind {
        case .fixed(let id):
            return c.byId[id]?.recurrence == .monthly
        case .loan(let id):
            return c.facts.loans.first(where: { $0.id == id })?.periodMonths == 1
        case .maintenance:
            return false
        }
    }

    // MARK: 看板下的車貸進度

    /// 進度格照 HouseCardData.progressData 寫法，資料換成 facts.loans；全部繳完、沒填年限改成一行
    fileprivate static func progressData(_ c: VehicleCardContext) -> (data: FinanceProgressData?, note: VehicleProgressNote?) {
        let f = c.facts
        let loans = f.loans
        guard !c.isSold, !loans.isEmpty else { return (nil, nil) }
        let active = loans.filter { $0.status == .paying || $0.status == .notStarted }
        if active.isEmpty {
            guard loans.allSatisfy({ $0.status == .done }), let payoff = loans.compactMap({ $0.payoffDate }).max() else {
                return (nil, nil)
            }
            return (nil, VehicleProgressNote(kind: .paidOff, text: "車貸 \(FinanceFormat.ym(payoff)) 全部繳完"))
        }
        let guesses = active.filter { $0.termIsGuess }
        if !guesses.isEmpty {
            let m = guesses.reduce(0.0) { $0 + $1.monthly }
            return (nil, VehicleProgressNote(kind: .termMissing, text: "車貸每月 \(MoneyFormat.short(m))・沒填年限，算不出還要繳多久"))
        }
        let known = loans.filter { !$0.termIsGuess && $0.countedPeriods > 0 }
        guard let firstDue = known.map({ $0.firstDue }).min(),
              let payoff = known.compactMap({ $0.payoffDate }).max() else { return (nil, nil) }

        var p = FinanceProgressData()
        p.title = "車貸進度"
        let notStarted = known.allSatisfy { $0.paidPeriods == 0 }
        p.notStarted = notStarted
        p.range = "\(FinanceFormat.ym(firstDue)) → \(FinanceFormat.ym(payoff))"
        let totalMonths = max(1, FinanceFormat.monthsBetween(firstDue, payoff))
        if !notStarted {
            let gone = Double(FinanceFormat.monthsBetween(firstDue, c.asOf)) / Double(totalMonths)
            p.fraction = min(1, max(0, gone))
        }
        var seen = Set<String>()
        for l in known.dropFirst() {
            let label = FinanceFormat.ym(l.firstDue)
            let x = Double(FinanceFormat.monthsBetween(firstDue, l.firstDue)) / Double(totalMonths)
            guard x > 0, x < 1, seen.insert(label).inserted else { continue }
            p.ticks.append(FinanceProgressData.Tick(fraction: x, label: label))
        }
        p.dotPill = notStarted ? "還沒開始" : "今天"
        p.endPill = "\(FinanceFormat.ym(payoff)) 繳完"

        let thisMonth = c.thisMonth
        let paying = known.filter { $0.isPaying(inMonth: thisMonth, calendar: c.cal) }
        let paidN = known.reduce(0) { $0 + $1.paidPeriods }
        if notStarted {
            p.left = "第一期 \(FinanceFormat.ym(firstDue))"
        } else {
            p.left = "已繳 \(paidN) 期" + (paying.count >= 2 ? "（\(paying.count) 筆同時在繳）" : "")
        }
        let remaining = known.reduce(0) { $0 + max(0, $1.countedPeriods - $1.paidPeriods) }
        p.right = "還有 \(remaining) 期"
        if let span = FinanceFormat.span(months: FinanceFormat.monthsBetween(c.asOf, payoff)) {
            p.right += "（\(span)）"
        }

        // 每月只算這個月還在扣的各筆（不要用 facts.loanMonthly：它含舊車貸鏡像）
        if notStarted {
            let firstMonth = VehicleFacts.monthStart(firstDue, c.cal)
            let m = known.filter { $0.isPaying(inMonth: firstMonth, calendar: c.cal) }.reduce(0.0) { $0 + $1.monthly }
            p.note = "\(FinanceFormat.ym(firstDue)) 開始・每月 \(MoneyFormat.short(m))"
        } else {
            var pieces: [String] = []
            let monthly = paying.reduce(0.0) { $0 + $1.monthly }
            if monthly >= 1 { pieces.append("每月 \(MoneyFormat.short(monthly))") }
            let left = known.reduce(0.0) { $0 + $1.left }
            if left >= 1 { pieces.append("還要繳 \(MoneyFormat.short(left))（含利息）") }
            if let next = known.compactMap({ $0.nextDue }).min() {
                pieces.append("下次 \(FinanceFormat.shortDate(next, now: c.asOf))")
            }
            p.note = pieces.joined(separator: "・")
        }
        let head = notStarted ? "還沒開始，\(p.left)" : "已繳 \(paidN) 期"
        p.accessibilityText = "\(head)，還有 \(remaining) 期，\(VehicleCardText.spokenYM(payoff))繳完"
        return (p, nil)
    }

    // MARK: 看板下的膠囊

    /// 依序最多 6 顆、多的從後面拿掉；已售出改成付掉的利息、實際花了、連折舊每月
    fileprivate static func chipsData(_ c: VehicleCardContext, ledger: VehicleLedger, kind: VehicleCardLineKind) -> [MoneyBoardChip] {
        let f = c.facts
        if c.isSold { return soldChips(c, ledger: ledger) }
        var out: [MoneyBoardChip] = []
        if f.purchase > 0 {
            out.append(MoneyBoardChip(icon: "cart.fill", label: "購入", value: MoneyFormat.short(f.purchase)))
            let dep = f.depreciation
            if !f.valueIsFallback, abs(dep) >= 1 {
                if dep > 0 {
                    out.append(MoneyBoardChip(icon: "arrow.down.right", label: "折舊", value: MoneyFormat.short(dep)))
                } else {
                    out.append(MoneyBoardChip(icon: "arrow.up.right", label: "增值", value: MoneyFormat.short(-dep), tone: .up))
                }
            }
        }
        if let held = FinanceFormat.lived(from: c.v.purchaseDate, to: c.asOf) {
            out.append(MoneyBoardChip(icon: "clock.fill", label: "持有", value: held))
        }
        // 定案 13：看板那句沒寫每月養車（有車貸）時才放
        if kind != .plain, let m = FinanceText.about100(f.monthly) {
            out.append(MoneyBoardChip(icon: "car.fill", label: "每月養車", value: m))
        }
        if let p = f.perKwh {
            out.append(MoneyBoardChip(icon: "bolt.fill", label: "每度電", value: "NT$\(VehicleCardText.n1(p))"))
        }
        if let p = f.fuel?.perLiter {
            out.append(MoneyBoardChip(icon: "fuelpump.fill", label: "每公升", value: "NT$\(VehicleCardText.n1(p))"))
        } else if let fuel = f.fuelPerMonth, let text = FinanceText.about100(fuel) {
            out.append(MoneyBoardChip(icon: "fuelpump.fill", label: "油錢每月", value: text))
        }
        if let p = f.perKm {
            out.append(MoneyBoardChip(icon: "road.lanes", label: "每公里", value: "NT$\(VehicleCardText.n1(p))"))
        }
        return Array(out.prefix(6))
    }

    /// 已售出：「付掉的利息」（有車貸才放）、「實際花了」（帳本那一句的 Y）、「連折舊每月 約」（Y ÷ 持有月數）
    fileprivate static func soldChips(_ c: VehicleCardContext, ledger: VehicleLedger) -> [MoneyBoardChip] {
        let f = c.facts
        var out: [MoneyBoardChip] = []
        if !f.loans.isEmpty, f.loans.allSatisfy({ $0.interestPaid != nil }) {
            let interest = f.loans.reduce(0.0) { $0 + max(0, $1.interestPaid ?? 0) }
            if interest >= 1 {
                out.append(MoneyBoardChip(icon: "percent", label: "付掉的利息", value: MoneyFormat.short(interest)))
            }
        }
        if let y = ledger.spent, y >= 1 {
            out.append(MoneyBoardChip(icon: "banknote.fill", label: "實際花了", value: MoneyFormat.short(y)))
            if let z = FinanceText.about100(y / Double(max(1, f.heldMonths))) {
                out.append(MoneyBoardChip(icon: "calendar", label: "連折舊每月", value: z))
            }
        }
        return out
    }
}

// MARK: - 要確認

extension VehicleCheck {
    /// 把會讓數字算錯的資料問題攤出來（App 不在背景偷偷改）：賣了還在扣第一、記成其他的車險第二，其他照 J141–154 的順序
    fileprivate static func build(_ c: VehicleCardContext) -> [VehicleCheck] {
        var out: [VehicleCheck] = []
        if let x = checkSoldStillCharging(c) { out.append(x) }
        // [v25.541] 排第二：每月養車那句「還沒有連到任何保險」就是它造成的，點「去改」捲上來第一眼要看到
        if let x = checkInsuranceAsOther(c) { out.append(x) }
        out += checkLoans(c)
        if let x = checkOrphans(c) { out.append(x) }
        if let x = checkLegacyFixed(c) { out.append(x) }
        if let x = checkUnassigned(c) { out.append(x) }
        if let x = checkDownPayment(c) { out.append(x) }
        if let x = checkValueMissing(c) { out.append(x) }
        if let x = checkSoldInFuture(c) { out.append(x) }
        if let x = checkOdometer(c) { out.append(x) }
        if let x = checkHomeKeyword(c) { out.append(x) }
        if let x = checkForeign(c) { out.append(x) }
        if let x = checkEnergyGap(c) { out.append(x) }
        return out
    }

    /// 賣了還在扣：已售出、連到這台的週期固定支出結束日是空的或比賣出日晚（v25.539 之前賣的車，車貸保險稅費也可能還在扣）
    fileprivate static func checkSoldStillCharging(_ c: VehicleCardContext) -> VehicleCheck? {
        let f = c.facts
        guard f.isSold, let sold = c.v.soldDate, !f.soldStillPayingIds.isEmpty else { return nil }
        let labels = f.soldStillPayingIds.compactMap { c.byId[$0] }.map { VehicleFacts.label($0, vehicleName: c.v.name) }
        let names = VehicleCardText.quotedNames(labels)
        let n = f.soldStillPayingIds.count
        let date = FinanceFormat.ymd(sold)
        let these = n > 1 && n <= 3 ? "這 \(n) 筆" : ""
        let confirm = "把\(names)\(these)的最後扣款日設成 \(date)（賣出日），之後不再從銀行扣。"
        let action = Action(title: "在賣出日停止", confirm: confirm, confirmTitle: "停止扣款？",
                            fix: .stopAtSale(expenseIds: f.soldStillPayingIds, soldDate: sold))
        return VehicleCheck(kind: .soldStillCharging, message: "\(c.name) \(date) 賣掉了，但\(names)還在記帳裡扣",
                            actions: [action])
    }

    /// [v25.541] 記成「其他」的車險：舊版車輛編輯頁只能從「稅費」記保險，記帳那邊就成了「其他・每年」，
    /// 卡片照類別把它算成稅費，每月養車說「還沒有連到任何保險」、還叫你再記一筆（會重複算）。
    /// 一鍵改成保險；只有一筆時多一顆「打開這筆」讓你自己挑類別
    fileprivate static func checkInsuranceAsOther(_ c: VehicleCardContext) -> VehicleCheck? {
        let list = c.insuranceAsOther
        guard let first = list.first else { return nil }
        let names = insuranceAsOtherNames(list, c: c)
        let it = list.count > 1 ? "它們" : "它"
        // 卡片現在把它算成什麼（帳本列的分類名）：其他・每年「稅費」、其他・每月「其他固定」
        var counted: [String] = []
        for ex in list {
            let label = VehicleFacts.categoryLabel(ex)
            if !counted.contains(label) { counted.append(label) }
        }
        // 「所以找不到保險」只在改完真的找得到時寫：期間內沒連到保險，而且這幾筆期間內有扣款。
        // 另外有連到保險、或這幾筆早就停了（改完每月養車照樣說沒保險）時，只說沒算成保險
        let findable = list.contains { c.debitedInPeriod($0) }
        let tail = c.facts.missingInsurance && findable ? "所以找不到保險" : "沒算成保險"
        let message = "\(names)記成「其他」，卡片把\(it)算成\(counted.joined(separator: "、"))，\(tail)。"
        let confirm = "把\(names)改成保險（名稱有「強制」的改成強制險，其他改成綜合險），每月養車和帳本會把\(it)算成保險。類別不對的話，改完再打開那筆換。"
        var actions = [Action(title: "改成保險", confirm: confirm, confirmTitle: "改成保險？",
                              fix: .convertToInsurance(expenseIds: list.map { $0.id }))]
        if list.count == 1 {
            actions.append(Action(title: "打開這筆", confirm: nil, fix: .openExpense(first.id)))
        }
        return VehicleCheck(kind: .insuranceAsOther, message: message, actions: actions)
    }

    /// 「「Porsche Taycan 每年固定保險」」；多筆「「A」「B」等 3 筆」：名字跟帳本列標題同一套（VehicleFacts.label），
    /// 最多列 2 個、同名只列一次（要確認、每月養車的提示共用）。
    /// 名稱就只是「綜合險」這種分類字時，帳本列標題會退回「稅費」，訊息變成「「稅費」…算成稅費」看不懂：這時寫原本的名稱
    fileprivate static func insuranceAsOtherNames(_ list: [Expense], c: VehicleCardContext) -> String {
        var names: [String] = []
        for ex in list {
            let label = VehicleFacts.label(ex, vehicleName: c.v.name)
            let typed = FinanceFormat.cleanTitle(ex.title, estateName: c.v.name)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fellBack = label == VehicleFacts.categoryLabel(ex)
            let name = fellBack && !typed.isEmpty ? typed : label
            if !names.contains(name) { names.append(name) }
        }
        let head = names.prefix(2).map { "「\($0)」" }.joined()
        return list.count > 1 ? "\(head)等 \(list.count) 筆" : head
    }

    /// 車貸：年限沒填、總額沒填、可能有尾款、利率對不起來（都是「去填／去看」打開那一筆）
    fileprivate static func checkLoans(_ c: VehicleCardContext) -> [VehicleCheck] {
        let loans = c.facts.loans
        var out: [VehicleCheck] = []
        // 「年限沒填」看 termIsGuess：兩個都沒填時 rateIssue 是 .noPrincipal，不能拿它判斷
        let guesses = loans.filter { $0.termIsGuess }
        if let first = guesses.first {
            let head = guesses.count > 1 ? "\(guesses.count) 筆車貸" : "車貸"
            out.append(VehicleCheck(kind: .termMissing, message: "\(head)沒填年限，算不出還要繳多久",
                                    actions: [Action(title: "去填", confirm: nil, fix: .openExpense(first.id))]))
        }
        let noPrincipal = loans.filter { $0.principal == nil }
        if let first = noPrincipal.first {
            let head = noPrincipal.count > 1 ? "\(noPrincipal.count) 筆車貸" : "車貸"
            out.append(VehicleCheck(kind: .principalMissing,
                                    message: "\(head)沒填總貸款金額，算不出還欠多少本金，先用含利息的還要繳",
                                    actions: [Action(title: "去填", confirm: nil, fix: .openExpense(first.id))]))
        }
        if let l = loans.first(where: { $0.rateIssue == .belowPrincipal }), let p = l.principal {
            out.append(VehicleCheck(kind: .belowPrincipal,
                                    message: "車貸每期加起來比借的 \(MoneyFormat.short(p)) 還少，可能有期末尾款（目前沒算進去）",
                                    actions: [Action(title: "去看", confirm: nil, fix: .openExpense(l.id))]))
        }
        if let l = loans.first(where: { $0.rateIssue == .tooHigh }) {
            out.append(VehicleCheck(kind: .rateTooHigh,
                                    message: "車貸的借款本金跟每期金額對不起來（換算年利率超過 24%），先用含利息的還要繳",
                                    actions: [Action(title: "去看", confirm: nil, fix: .openExpense(l.id))]))
        }
        return out
    }

    /// 孤兒：鏡像的 linkedExpenseId 有值，記帳裡卻找不到
    fileprivate static func checkOrphans(_ c: VehicleCardContext) -> VehicleCheck? {
        let ids = c.facts.orphanMirrorIds
        guard !ids.isEmpty else { return nil }
        let n = ids.count
        let action = Action(title: "移除", confirm: "從車子這邊移掉 \(n) 筆已經不存在的支出（記帳裡已經沒有了）。",
                            confirmTitle: "移除這些支出？", destructive: true,
                            fix: .removeMirrors(ids.sorted { $0.uuidString < $1.uuidString }))
        return VehicleCheck(kind: .orphans, message: "\(n) 筆在記帳那邊已經刪掉，車子這邊還留著", actions: [action])
    }

    /// 舊定期：鏡像裡的定期支出沒連到記帳（沒有起始日，帳本算不進去）。補建一次一筆，確認框寫出原本的金額和週期讓你照打
    fileprivate static func checkLegacyFixed(_ c: VehicleCardContext) -> VehicleCheck? {
        let list = c.v.fixedExpenses.filter { $0.linkedExpenseId == nil }
        guard let first = list.first else { return nil }
        let n = list.count
        let period = first.period == .yearly ? "每年" : "每月"
        let original = "「\(first.category.rawValue)」\(period) \(MoneyFormat.short(first.amount))"
        let confirm = "會打開記帳頁，分類、週期和這台車都帶好了。原本這筆是\(original)，金額請照打，起始日填第一次扣款那天；存好之後，車子這邊舊的那筆會換成新的。"
        var message = "\(n) 筆舊的定期支出沒連到記帳，沒有起始日，帳本算不進去"
        if n > 1 { message += "（一次補一筆）" }
        let action = Action(title: "補建", confirm: confirm, confirmTitle: "補建定期支出", fix: .backfillFixed(mirrorId: first.id))
        return VehicleCheck(kind: .legacyFixed, message: message, actions: [action])
    }

    /// 沒指定車：記帳裡「汽車」支出沒指定車、也沒有子分類、日期在購入日之後。持有中的車剛好一台而且就是這台才檢查
    ///（好幾台時不猜；有子分類的是「只刪車子，記帳留著」解除連結的舊車支出，不能被撿回去）
    fileprivate static func checkUnassigned(_ c: VehicleCardContext) -> VehicleCheck? {
        let held = c.vehicles.filter { !$0.isSold(asOf: c.now) }
        guard held.count == 1, held[0].id == c.v.id else { return nil }
        let start = c.cal.startOfDay(for: c.v.purchaseDate)
        var ids: [UUID] = []
        for ex in c.expenses where ex.expenseType == .variable {
            guard ex.variableCategory == .vehicle, ex.linkedVehicleId == nil, ex.vehicleExpenseCategory == nil else { continue }
            guard c.cal.startOfDay(for: ex.date) >= start else { continue }
            ids.append(ex.id)
        }
        guard !ids.isEmpty else { return nil }
        let n = ids.count
        let action = Action(title: "都算這台", confirm: "把這 \(n) 筆「汽車」支出連到 \(c.name)，之後會算進這張卡和每月養車。",
                            confirmTitle: "都算這台？", fix: .assign(expenseIds: ids))
        return VehicleCheck(kind: .unassigned, message: "記帳裡有 \(n) 筆「汽車」支出沒指定是哪台車，沒算進這裡",
                            actions: [action])
    }

    /// 可能是頭款：購入日前後 30 天內、金額 ≥ 購入價 30% 的變動支出（帳本已經用購入價算過買車的錢）
    fileprivate static func checkDownPayment(_ c: VehicleCardContext) -> VehicleCheck? {
        let price = c.v.purchasePrice
        guard price > 0 else { return nil }
        let buy = c.cal.startOfDay(for: c.v.purchaseDate)
        for ex in c.links.expenses where ex.expenseType == .variable {
            let amount = c.amount(ex)
            guard amount >= price * 0.3 else { continue }
            let gap = c.cal.dateComponents([.day], from: buy, to: c.cal.startOfDay(for: ex.date)).day ?? 999
            guard abs(gap) <= 30 else { continue }
            let message = "\(FinanceFormat.ymd(ex.date)) 有一筆 \(MoneyFormat.short(amount)) 的汽車支出，可能是頭款；帳本已經用購入價算過買車的錢"
            return VehicleCheck(kind: .downPayment, message: message,
                                actions: [Action(title: "去看", confirm: nil, fix: .openExpense(ex.id))])
        }
        return nil
    }

    /// 估值 0 而且沒有更新日（還沒確認過真的是 0）：先用購入價算（決定 10）
    fileprivate static func checkValueMissing(_ c: VehicleCardContext) -> VehicleCheck? {
        guard c.facts.valueIsFallback, !c.isSold else { return nil }
        let fill = Action(title: "去填", confirm: nil, fix: .edit(.value))
        let zero = Action(title: "就是 0（報廢）", confirm: "之後 \(c.name) 的估值照 0 算，折舊會寫 100%。",
                          confirmTitle: "估值就是 0？", fix: .markValueZero)
        return VehicleCheck(kind: .valueMissing, message: "估值是 0，先用購入價算", actions: [fill, zero])
    }

    /// 售出日在未來（舊資料）：v25.539 起照持有中算（定案 11）
    fileprivate static func checkSoldInFuture(_ c: VehicleCardContext) -> VehicleCheck? {
        guard let sold = c.v.soldDate, c.cal.startOfDay(for: sold) > c.today else { return nil }
        return VehicleCheck(kind: .soldInFuture, message: "售出日 \(FinanceFormat.ymd(sold)) 還沒到，先照持有中算",
                            actions: [Action(title: "去改", confirm: nil, fix: .edit(.sold))])
    }

    /// 里程倒退：比前面最大值還小的讀數（沒採用），打開那一筆去改
    fileprivate static func checkOdometer(_ c: VehicleCardContext) -> VehicleCheck? {
        guard let regs = c.facts.odometer?.regressions, let r = regs.first else { return nil }
        let at = FinanceFormat.shortDate(r.reading.date, now: c.asOf)
        let before = FinanceFormat.shortDate(r.previous.date, now: c.asOf)
        let km = VehicleCardText.grouped(r.reading.km)
        let prevKm = VehicleCardText.grouped(r.previous.km)
        var message = "\(at) 的里程錶 \(km) 公里，比 \(before) 的 \(prevKm) 公里還少"
        if regs.count > 1 { message += "（還有 \(regs.count - 1) 筆）" }
        return VehicleCheck(kind: .odometerRegression, message: message,
                            actions: [Action(title: "去改", confirm: nil, fix: .openExpense(r.reading.expenseId))])
    }

    /// 家充關鍵字只有 1 個字（只認完全相等），而且有充電地點包含它、卻不等於它
    fileprivate static func checkHomeKeyword(_ c: VehicleCardContext) -> VehicleCheck? {
        let raw = (c.v.homeChargePlace ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let key = raw.filter { !$0.isWhitespace }.lowercased()
        guard c.v.hasBattery, key.count == 1, let sessions = c.facts.charge?.sessions else { return nil }
        var hits: [String] = []
        for s in sessions {
            let place = s.place.lowercased()
            guard place != key, place.contains(key), !hits.contains(s.place) else { continue }
            hits.append(s.place)
        }
        guard !hits.isEmpty else { return nil }
        let examples = hits.prefix(2).map { "「\($0)」" }.joined()
        return VehicleCheck(kind: .homeKeyword, message: "家充地點只填了「\(raw)」，\(examples)這類地點不會被算成家充",
                            actions: [Action(title: "去改", confirm: nil, fix: .edit(.homeCharge))])
    }

    /// 連到別台：鏡像指到的記帳 linkedVehicleId 是另一台還在的車（那筆只算那一台）；那台已經不在的本版不列（定案 22）
    fileprivate static func checkForeign(_ c: VehicleCardContext) -> VehicleCheck? {
        let ids = c.facts.foreignMirrorIds
        guard !ids.isEmpty else { return nil }
        var mirrors: [(id: UUID, link: UUID?)] = []
        for m in c.v.fixedExpenses where ids.contains(m.id) { mirrors.append((id: m.id, link: m.linkedExpenseId)) }
        for m in c.v.variableExpenses where ids.contains(m.id) { mirrors.append((id: m.id, link: m.linkedExpenseId)) }
        var kept: [UUID] = []
        var owners: [String] = []
        for m in mirrors {
            guard let eid = m.link, let owner = c.byId[eid]?.linkedVehicleId,
                  let other = c.vehicles.first(where: { $0.id == owner }) else { continue }
            kept.append(m.id)
            let name = other.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let shown = name.isEmpty ? "未命名車輛" : name
            if !owners.contains(shown) { owners.append(shown) }
        }
        guard !kept.isEmpty else { return nil }
        let who = owners.joined(separator: "、")
        let n = kept.count
        let action = Action(title: "移除", confirm: "從 \(c.name) 這邊移掉 \(n) 筆（記帳那邊照樣算在 \(who)）。",
                            confirmTitle: "移除這些支出？", destructive: true, fix: .removeMirrors(kept))
        return VehicleCheck(kind: .foreign, message: "\(n) 筆記帳連到 \(who)，\(c.name) 這邊還留著它們", actions: [action])
    }

    /// 漏記：相鄰兩筆的「每度跑」「每公升跑」不合理（中間一定有沒記到的），這段沒算進每公里
    fileprivate static func checkEnergyGap(_ c: VehicleCardContext) -> VehicleCheck? {
        let chargeGaps = c.facts.charge?.gaps ?? []
        let fuelGaps = c.facts.fuel?.gaps ?? []
        let all = chargeGaps + fuelGaps
        guard let g = all.first else { return nil }
        let isCharge = !chargeGaps.isEmpty
        let unit = isCharge ? "度電" : "公升"
        let what = isCharge ? "充電" : "加油"
        let from = FinanceFormat.shortDate(g.from, now: c.asOf)
        let to = FinanceFormat.shortDate(g.to, now: c.asOf)
        let km = VehicleCardText.grouped(g.km)
        let amount = VehicleCardText.n1(g.amount)
        var message = "\(from) 到 \(to) 開了 \(km) 公里只記到 \(amount) \(unit)，中間可能有沒記到的\(what)；這段沒算進每公里"
        if all.count > 1 { message += "（還有 \(all.count - 1) 段）" }
        return VehicleCheck(kind: .energyGap, message: message,
                            actions: [Action(title: "去看", confirm: nil, fix: .openExpense(g.id))])
    }
}

// MARK: - 每月養車、接下來

extension VehicleCardData {
    /// 每月養車：段用 facts.parts，合計＝round(facts.monthly, 100)，各段 > 0.5 才放、最大餘數分到百位（各段相加＝合計）
    fileprivate static func monthlyData(_ c: VehicleCardContext, hasLoanSection: Bool, hasEnergySection: Bool) -> VehicleMonthlyData? {
        let f = c.facts
        guard !c.isSold, f.monthly >= 1 else { return nil }
        let p = f.parts
        let loanTap: VehicleTap = hasLoanSection ? .scrollTo(.loan) : .scrollTo(.checks)
        let energyTap: VehicleTap = hasEnergySection ? .scrollTo(.energy) : .ledgerFilter(.energy)
        var raw: [(kind: VehicleMonthlyData.Kind, label: String, value: Double, tap: VehicleTap)] = []
        if let interest = p.loanInterest, let principal = p.loanPrincipal {
            raw.append((kind: .interest, label: "車貸利息", value: interest, tap: loanTap))
            raw.append((kind: .principal, label: "還本金", value: principal, tap: loanTap))
        } else {
            raw.append((kind: .loan, label: "車貸", value: p.loan, tap: loanTap))
        }
        raw.append((kind: .fixed, label: "定期", value: p.fixed, tap: .ledgerFilter(.fixed)))
        raw.append((kind: .energy, label: p.energyLabel, value: p.energy, tap: energyTap))
        raw.append((kind: .care, label: "保養・維修", value: p.care, tap: .ledgerFilter(.care)))
        raw.append((kind: .other, label: "停車・洗車・其他", value: p.other, tap: .ledgerFilter(.other)))
        raw = raw.filter { $0.value > 0.5 }
        guard !raw.isEmpty else { return nil }

        var m = VehicleMonthlyData()
        let total = FinanceRound.round(f.monthly, unit: 100)
        let shares = FinanceRound.largestRemainder(raw.map { $0.value }, total: total, unit: 100)
        m.total = total
        m.trailing = "近 \(f.periodMonths) 個月平均"
        m.headline = FinanceText.about100(f.monthly) ?? ""
        for (i, item) in raw.enumerated() where shares[i] > 0 {
            m.parts.append(VehicleMonthlyData.Part(kind: item.kind, label: item.label, value: shares[i],
                                                   valueText: MoneyFormat.short(shares[i]), tap: item.tap))
        }
        switch p.energyLabel {
        case "加油": m.energyFlavor = .fuel
        case "油電": m.energyFlavor = .mixed
        default: m.energyFlavor = .electric
        }
        m.realLine = monthlyRealLine(m)
        m.perKmLine = monthlyPerKmLine(f)
        if let d = f.depreciationMonthly, let dt = FinanceText.about100(d) {
            m.depreciationLine = FinanceLine(runs: [
                FinanceRun(text: "另外，照你填的估值，車子每月平均折掉 "),
                FinanceRun(text: dt, bold: true),
                FinanceRun(text: "；這不是付出去的錢，賣車時才會算到。")
            ])
        }
        if f.missingInsurance { fillInsuranceHint(&m, c: c) }
        if f.firstYearNoTax { m.firstYearHint = "買車還不到一年，稅費、保養可能還沒輪到，這裡會先偏低。" }
        if let late = f.energyStartedLate {
            let word = p.energyLabel
            m.lateStartHint = "\(word)是 \(FinanceFormat.ym(late)) 才開始記的，之前的沒算到，\(word)這段會偏低。"
        }
        if p.loan > 0, p.loanInterest == nil { fillSplitHint(&m, c: c) }
        var spoken: [String] = []
        for part in m.parts {
            let label = part.label.replacingOccurrences(of: "・", with: "")
            spoken.append("\(label) \(FinanceFormat.spoken(part.value))")
        }
        m.accessibilityText = "平均每月約 \(VehicleCardText.spokenMoney(total))：\(spoken.joined(separator: "，"))"
        return m
    }

    /// ①「真正花掉的是 約 NT$1.1萬；NT$2.9萬 是在還車貸本金，減少欠銀行的錢。」（拆得出利息時才有）
    fileprivate static func monthlyRealLine(_ m: VehicleMonthlyData) -> FinanceLine? {
        guard let principal = m.parts.first(where: { $0.kind == .principal })?.value, principal > 0 else { return nil }
        let spent = m.total - principal
        return FinanceLine(runs: [
            FinanceRun(text: "真正花掉的是 約 "),
            FinanceRun(text: MoneyFormat.short(spent), bold: true),
            FinanceRun(text: "；"),
            FinanceRun(text: MoneyFormat.short(principal), bold: true),
            FinanceRun(text: " 是在還車貸本金，減少欠銀行的錢。")
        ])
    }

    /// ②「每月養車平均下來，每公里約 NT$70.9（一年約開 900 公里；不含車貸和折舊）。」算得出年里程才寫
    fileprivate static func monthlyPerKmLine(_ f: VehicleFacts) -> String? {
        guard let annual = f.odometer?.annualKm, annual > 0 else { return nil }
        let upkeep = f.monthly - f.parts.loan
        guard upkeep > 0 else { return nil }
        let perKm = upkeep * 12 / annual
        return "每月養車平均下來，每公里約 NT$\(VehicleCardText.n1(perKm))（一年約開 \(VehicleCardText.kmText(annual))；不含車貸和折舊）。"
    }

    /// 期間內沒有保險扣款：一般寫「還沒有連到任何保險」＋「＋ 記保險」。
    /// [v25.541] 有記成「其他」的車險、而且這個月還算在「定期」裡時，錢其實已經算進來了，再記一筆會重複：
    /// 改說它記成「其他」，連結字「去改」捲到「要確認」（那裡有「改成保險」）。早就停掉的那種不算（定期裡沒有它）
    fileprivate static func fillInsuranceHint(_ m: inout VehicleMonthlyData, c: VehicleCardContext) {
        let inFixed = c.insuranceAsOther.filter { ex in
            guard ex.isRecurringFixed, c.onOrBeforeAsOf(ex.date) else { return false }
            guard let end = ex.endDate else { return true }
            return c.cal.startOfDay(for: end) >= c.thisMonth
        }
        guard !inFixed.isEmpty else {
            m.insuranceHint = "這台車還沒有連到任何保險，每月養車會偏低。"
            return
        }
        let names = VehicleCheck.insuranceAsOtherNames(inFixed, c: c)
        m.insuranceHint = "\(names)記成「其他」，所以這裡看不到保險（錢已經算在定期裡）。"
        m.insuranceHintAction = "去改"
        m.insuranceHintTap = .scrollTo(.checks)
    }

    /// 車貸分不出利息和本金：缺總貸款金額時打開那一筆；舊車貸鏡像、利率對不起來捲到「要確認」
    fileprivate static func fillSplitHint(_ m: inout VehicleMonthlyData, c: VehicleCardContext) {
        let month = c.thisMonth
        let paying = c.facts.loans.filter { $0.isPaying(inMonth: month, calendar: c.cal) }
        if let l = paying.first(where: { $0.principal == nil }) {
            m.splitHint = "在車貸那筆填上總貸款金額，就能分出利息和本金 →"
            m.splitTap = .openExpense(l.id)
        } else if let l = paying.first(where: { $0.termIsGuess }) {
            m.splitHint = "在車貸那筆填上年限，就能分出利息和本金 →"
            m.splitTap = .openExpense(l.id)
        } else if !c.legacyLoans.isEmpty {
            m.splitHint = "舊的車貸沒連到記帳，分不出利息和本金 →"
            m.splitTap = .scrollTo(.checks)
        } else {
            m.splitHint = "車貸的借款本金跟每期金額對不起來，分不出利息和本金 →"
            m.splitTap = .scrollTo(.checks)
        }
    }

    /// 接下來：rows 由 facts.upcoming 轉；保養只有 1 次、或估不出下一次時一行灰字；油車油電沒記稅費時提示
    fileprivate static func upcomingData(_ c: VehicleCardContext) -> VehicleUpcomingData? {
        guard !c.isSold else { return nil }
        let f = c.facts
        var u = VehicleUpcomingData()
        u.rows = f.upcoming.map { upcomingRow($0, c: c) }
        u.trailing = u.rows.isEmpty ? "" : "一年內 \(u.rows.count) 件"
        let m = f.maintenance
        if let last = m.last {
            if m.count == 1 {
                let photo = m.lastIsPhotoOnly ? "（照片紀錄）" : ""
                u.maintenanceNote = "上次保養 \(FinanceFormat.ymd(last))\(photo)，再記一次就能估下一次"
            } else if m.next == nil {
                // 定案 24：保養 ≥ 2 次但間隔都 < 14 天、又沒里程
                u.maintenanceNote = "上次保養 \(FinanceFormat.ymd(last))，間隔太短，估不出下一次"
            }
        }
        if f.needsTaxReminder {
            u.taxHint = "自用小客車的使用牌照稅每年 4 月、汽車燃料使用費每年 7 月開徵；記一筆每年的稅費，這裡就會提前提醒你。"
        }
        if u.rows.isEmpty && u.maintenanceNote == nil && u.taxHint == nil { return nil }
        return u
    }

    fileprivate static func upcomingRow(_ item: VehicleUpcoming, c: VehicleCardContext) -> VehicleUpcomingData.Row {
        let mark: VehicleLedgerMark
        let tap: VehicleTap
        var expenseId: UUID? = nil
        var amountText = item.amount >= 1 ? MoneyFormat.short(item.amount) : ""
        var overdue: String? = nil
        switch item.kind {
        case .fixed(let id):
            mark = c.byId[id].map { VehicleLedgerMark.of($0) } ?? .fixedOther
            tap = .openExpense(id)
            expenseId = id
        case .loan(let id):
            mark = .loan
            tap = .openExpense(id)
            expenseId = id
        case .maintenance:
            mark = .maintenance
            tap = .ledgerFilter(.care)
            if item.amount >= 1 { amountText = "約 \(MoneyFormat.short(item.amount))" }
            if let d = item.overdueDays, d > 0 { overdue = "已經超過 \(d) 天沒保養" }
        }
        let dayText = item.isEstimate ? "約" : FinanceFormat.day(item.date)
        let when = item.isEstimate ? "約 \(FinanceFormat.ym(item.date))" : FinanceFormat.ymd(item.date)
        var spoken = "\(when)，\(item.title)"
        if !item.detail.isEmpty { spoken += "，\(item.detail)" }
        if !amountText.isEmpty { spoken += "，\(amountText)" }
        if let o = overdue { spoken += "，\(o)" }
        return VehicleUpcomingData.Row(id: item.id, dayText: dayText, monthText: FinanceFormat.ym(item.date), mark: mark,
                                       title: item.title, detail: item.detail, amountText: amountText,
                                       overdueText: overdue, tap: tap, expenseId: expenseId, accessibilityText: spoken)
    }
}

// MARK: - 車貸區

extension VehicleCardData {
    /// 「車貸」區：facts.loans（依起始日）＋沒連到記帳的舊車貸鏡像；沒有任何車貸時 nil
    fileprivate static func loanSectionData(_ c: VehicleCardContext) -> VehicleLoanSectionData? {
        let f = c.facts
        let loans = f.loans
        guard c.hasAnyLoan else { return nil }
        var s = VehicleLoanSectionData()
        let n = loans.count + c.legacyLoans.count
        if c.isSold {
            let soldDay = c.v.soldDate ?? c.asOf
            s.trailing = "\(n) 筆・\(FinanceFormat.ym(soldDay)) 賣出"
            s.soldNote = "車子 \(FinanceFormat.ym(soldDay)) 賣掉了，車貸算到那天"
        } else if !loans.isEmpty, c.legacyLoans.isEmpty, loans.allSatisfy({ $0.status == .done }) {
            s.trailing = "已繳完"
        } else if !loans.contains(where: { $0.termIsGuess }), let payoff = loans.compactMap({ $0.payoffDate }).max() {
            s.trailing = "\(n) 筆・\(FinanceFormat.ym(payoff)) 繳完"
        } else {
            s.trailing = "\(n) 筆"
        }
        s.tiles = c.isSold ? soldLoanTiles(loans) : loanTiles(c)
        if !c.isSold {
            fillPrincipalHint(&s, c: c)
            s.sellLine = loanSellLine(c)
            s.totalLine = loanTotalLine(loans)
            if loans.contains(where: { $0.hasBalance }) {
                s.footnote = "本金和利息是用總貸款金額和每期金額反推的（等於一個平均利率），跟銀行對帳單會差一點；有期末尾款的車貸，這裡會算不準。"
            }
        }
        var rows: [VehicleLoanSectionData.Row] = []
        for (i, l) in loans.enumerated() { rows.append(loanRow(l, index: i + 1, c: c)) }
        for (i, m) in c.legacyLoans.enumerated() { rows.append(legacyLoanRow(m, index: loans.count + i + 1)) }
        s.rows = rows
        return s
    }

    /// 六格（算得出本金和利率）／三格（任一筆算不出）／繳完三格；還沒開始扣只放借款本金、還要繳、繳完
    fileprivate static func loanTiles(_ c: VehicleCardContext) -> [VehicleTile] {
        let loans = c.facts.loans
        guard !loans.isEmpty else { return [] }
        var principalTap = VehicleTap.none
        if loans.count == 1 { principalTap = .openExpense(loans[0].id) }
        let principals = loans.compactMap { $0.principal }
        let fullPrincipal = principals.count == loans.count
        let principalTile = VehicleTile(label: "借款本金", value: MoneyFormat.compact(principals.reduce(0, +)),
                                        sub: "記帳填的", tap: principalTap)
        let allDone = loans.allSatisfy { $0.status == .done }
        var payoffTile: VehicleTile? = nil
        if !loans.contains(where: { $0.termIsGuess }), let payoff = loans.compactMap({ $0.payoffDate }).max() {
            let span = FinanceFormat.span(months: FinanceFormat.monthsBetween(c.asOf, payoff)).map { "還有 \($0)" } ?? ""
            payoffTile = VehicleTile(label: "繳完", value: FinanceFormat.ym(payoff), sub: allDone ? "已全部繳完" : span)
        }
        let paid = loans.reduce(0.0) { $0 + $1.paid }
        let paidN = loans.reduce(0) { $0 + $1.paidPeriods }
        let paidTile = VehicleTile(label: "已繳", value: MoneyFormat.compact(paid), sub: "\(paidN) 期")
        let left = loans.reduce(0.0) { $0 + $1.left }
        let leftTile = VehicleTile(label: "還要繳", value: MoneyFormat.compact(left), sub: "含利息")
        let interestKnown = loans.allSatisfy { $0.interestPaid != nil }
        let interest = loans.reduce(0.0) { $0 + ($1.interestPaid ?? 0) }
        let repaid = loans.reduce(0.0) { $0 + ($1.principalRepaid ?? 0) }
        let interestTile = VehicleTile(label: "已付利息", value: MoneyFormat.compact(interest),
                                       sub: "本金還了 \(MoneyFormat.compact(repaid))")
        var out: [VehicleTile] = []
        if allDone {
            if fullPrincipal { out.append(principalTile) }
            out.append(interestKnown ? interestTile : paidTile)
        } else if fullPrincipal && loans.allSatisfy({ $0.hasBalance }) {
            if !loans.contains(where: { $0.paidPeriods > 0 }) {
                out = [principalTile, leftTile]
            } else {
                let owed = loans.reduce(0.0) { $0 + ($1.balance ?? 0) }
                let owedTile = VehicleTile(label: "還欠本金", value: MoneyFormat.compact(owed), sub: "到今天")
                out = [principalTile, owedTile, interestTile, paidTile, leftTile]
            }
        } else {
            out = [paidTile, leftTile]
        }
        if let t = payoffTile { out.append(t) }
        return out
    }

    /// 已售出：借款本金、到賣出那天付掉的利息、已繳（賣出時結清，沒有還要繳、繳完）
    fileprivate static func soldLoanTiles(_ loans: [VehicleLoan]) -> [VehicleTile] {
        guard !loans.isEmpty else { return [] }
        var out: [VehicleTile] = []
        let principals = loans.compactMap { $0.principal }
        if principals.count == loans.count {
            out.append(VehicleTile(label: "借款本金", value: MoneyFormat.compact(principals.reduce(0, +)), sub: "記帳填的"))
        }
        if loans.allSatisfy({ $0.interestPaid != nil }) {
            let interest = loans.reduce(0.0) { $0 + ($1.interestPaid ?? 0) }
            out.append(VehicleTile(label: "已付利息", value: MoneyFormat.compact(interest), sub: "到賣出那天"))
        }
        let paid = loans.reduce(0.0) { $0 + $1.paid }
        let paidN = loans.reduce(0) { $0 + $1.paidPeriods }
        out.append(VehicleTile(label: "已繳", value: MoneyFormat.compact(paid), sub: "\(paidN) 期"))
        return out
    }

    /// 格子下一行可點的提示：缺總貸款金額、缺年限打開那一筆；利率對不起來、舊鏡像捲到「要確認」
    fileprivate static func fillPrincipalHint(_ s: inout VehicleLoanSectionData, c: VehicleCardContext) {
        let loans = c.facts.loans
        if let l = loans.first(where: { $0.principal == nil }) {
            s.principalHint = "在車貸那筆填上總貸款金額，就能算出還欠多少本金、付了多少利息 →"
            s.principalHintTap = .openExpense(l.id)
        } else if let l = loans.first(where: { $0.termIsGuess }) {
            s.principalHint = "在車貸那筆填上年限，就能算出還要繳多久、還欠多少本金 →"
            s.principalHintTap = .openExpense(l.id)
        } else if loans.contains(where: { !$0.hasBalance && $0.status != .done }) {
            s.principalHint = "車貸的借款本金跟每期金額對不起來，先只算含利息的數字 →"
            s.principalHintTap = .scrollTo(.checks)
        } else if loans.isEmpty {
            s.principalHint = "舊的車貸沒連到記帳，沒有起始日，算不出期數和本金 →"
            s.principalHintTap = .scrollTo(.checks)
        }
    }

    /// ①「照估值今天賣掉，先還清本金 約 NT$111.7萬，拿回 約 NT$148.3萬。」只在算得出本金時寫；不夠還寫「還差」
    fileprivate static func loanSellLine(_ c: VehicleCardContext) -> FinanceLine? {
        let f = c.facts
        guard !f.loans.isEmpty, !f.owedIsScheduled, !f.owedMissingTerm, f.owed >= 1 else { return nil }
        let back = f.value - f.owed
        var runs = [FinanceRun(text: "照估值今天賣掉，先還清本金 約 \(MoneyFormat.short(f.owed))，")]
        if back >= 0 {
            runs.append(FinanceRun(text: "拿回 約 "))
            runs.append(FinanceRun(text: MoneyFormat.short(back), bold: true, tone: .good))
        } else {
            runs.append(FinanceRun(text: "還差 "))
            runs.append(FinanceRun(text: MoneyFormat.short(-back), bold: true, tone: .bad))
        }
        runs.append(FinanceRun(text: "。"))
        return FinanceLine(runs: runs)
    }

    /// ②「全部繳完總共 NT$210萬，其中利息 NT$30萬・換算年利率約 6.2%。」零利率改句；兩筆以上寫本金加權的平均年利率（定案 25）
    fileprivate static func loanTotalLine(_ loans: [VehicleLoan]) -> FinanceLine? {
        let known = loans.filter { !$0.termIsGuess }
        let total = known.reduce(0.0) { $0 + $1.scheduledTotal }
        guard !known.isEmpty, total >= 1 else { return nil }
        let head = FinanceRun(text: "全部繳完總共 ")
        let totalRun = FinanceRun(text: MoneyFormat.short(total), bold: true)
        let rated = known.filter { $0.principal != nil && $0.monthlyRate != nil }
        guard rated.count == known.count else {
            return FinanceLine(runs: [head, totalRun, FinanceRun(text: "（含利息）。")])
        }
        if rated.allSatisfy({ ($0.monthlyRate ?? 0) == 0 }) {
            return FinanceLine(runs: [head, totalRun, FinanceRun(text: "，月付加起來剛好等於借款，是零利率。")])
        }
        var principal = 0.0
        var weighted = 0.0
        var interest = 0.0
        for l in rated {
            guard let p = l.principal, let r = l.monthlyRate else { continue }
            principal += p
            weighted += p * r
            interest += l.interestTotal ?? 0
        }
        let annual = principal > 0 ? weighted / principal * 12 : 0
        let rateWord = rated.count > 1 ? "平均年利率約" : "換算年利率約"
        return FinanceLine(runs: [
            head, totalRun,
            FinanceRun(text: "，其中利息 "),
            FinanceRun(text: MoneyFormat.short(interest), bold: true),
            FinanceRun(text: "・\(rateWord) \(FinanceText.percent1(annual))。")
        ])
    }

    fileprivate static func loanRow(_ l: VehicleLoan, index: Int, c: VehicleCardContext) -> VehicleLoanSectionData.Row {
        var status = sectionStatus(l.status)
        // 已售出：賣出那天還在扣、還沒開始的一律寫「賣出時結清」（J300、J548），不給「停止扣款」：
        // 還沒停在賣出日的那幾筆由「要確認」的「在賣出日停止」處理，停在今天會多算賣掉之後的期數
        if c.isSold && (status == .paying || status == .notStarted) { status = .soldSettled }
        var badge = "\(index)"
        var statusText = ""
        var progress: Double? = nil
        var nextText: String? = nil
        switch status {
        case .paying:
            statusText = l.termIsGuess ? "第 \(l.paidPeriods) 期" : "第 \(l.paidPeriods)／\(l.countedPeriods) 期"
            if !l.termIsGuess, l.countedPeriods > 0 { progress = Double(l.paidPeriods) / Double(l.countedPeriods) }
            if let next = l.nextDue { nextText = "下次 \(FinanceFormat.shortDate(next, now: c.asOf)) 扣款" }
        case .notStarted:
            statusText = "\(FinanceFormat.ym(l.firstDue)) 開始"
        case .done:
            badge = ""
            statusText = "已繳完"
        case .stopped:
            badge = "停"
            statusText = "已停止 \(FinanceFormat.ym(l.endDate ?? l.payoffDate ?? l.firstDue))"
        case .soldSettled, .unlinked:
            statusText = "賣出時結清"
        }
        var range = FinanceFormat.ym(l.firstDue)
        if l.termIsGuess {
            range += " 起"
        } else {
            if let last = l.payoffDate, l.countedPeriods > 1 { range += " – \(FinanceFormat.ym(last))" }
            range += "・\(l.countedPeriods) 期"
        }
        let amount = MoneyFormat.short(l.perPeriod) + VehicleCardText.periodUnit(l.periodMonths)
        let canStop = status == .paying || status == .notStarted
        var delete = "會刪掉記帳裡這筆\(VehicleCardText.periodWord(l.periodMonths))車貸"
        if l.paidPeriods > 0 { delete += "（已繳的 \(l.paidPeriods) 期也會從帳本和淨資產走勢消失）" }
        delete += "和銀行的扣款紀錄，不能復原。"
        if canStop { delete += "只是不想再扣，請按「停止扣款」。" }
        var spoken = "\(l.displayTitle)，\(range)，\(amount)，\(statusText)"
        if let nextText { spoken += "，\(nextText)" }
        if l.termIsGuess { spoken += "，期數沒填" }
        return VehicleLoanSectionData.Row(id: l.id, source: .expense(l.id), index: index, status: status, badge: badge,
                                          title: l.displayTitle, range: range, amount: amount, statusText: statusText,
                                          progress: progress, nextText: nextText, isUnlinked: false,
                                          termMissing: l.termIsGuess, canStop: canStop, deleteMessage: delete,
                                          accessibilityText: spoken)
    }

    /// 沒連到記帳的舊車貸鏡像：沒有起始日、算不出期數（點了捲到「要確認」；不能停、不能刪）
    fileprivate static func legacyLoanRow(_ m: VehicleFixedExpense, index: Int) -> VehicleLoanSectionData.Row {
        let unit = m.period == .yearly ? "/年" : "/月"
        let amount = MoneyFormat.short(m.amount) + unit
        return VehicleLoanSectionData.Row(id: m.id, source: .legacy(m.id), index: index, status: .unlinked, badge: "\(index)",
                                          title: "車貸", range: "沒有起始日", amount: amount, statusText: "沒連到記帳",
                                          progress: nil, nextText: nil, isUnlinked: true, termMissing: false,
                                          canStop: false, deleteMessage: "",
                                          accessibilityText: "車貸，沒有起始日，\(amount)，沒連到記帳")
    }

    fileprivate static func sectionStatus(_ s: VehicleLoan.Status) -> VehicleLoanSectionData.Status {
        switch s {
        case .paying: return .paying
        case .notStarted: return .notStarted
        case .done: return .done
        case .stopped: return .stopped
        case .soldSettled: return .soldSettled
        }
    }
}

// MARK: - 充電／加油／油電

extension VehicleCardData {
    /// 電車讀 facts.charge、油車讀 facts.fuel、油電兩排；完全沒紀錄縮成一行；電動機車沒度數整區不出現
    fileprivate static func energyData(_ c: VehicleCardContext) -> VehicleEnergyData? {
        let v = c.v
        let f = c.facts
        let power = v.powerType
        let usesFuel = power == .gasoline || power == .motorcycle || power == .hybrid
        let ch: VehicleChargeSummary? = v.hasBattery ? f.charge : nil
        let fu: VehicleFuelAnalytics? = usesFuel ? f.fuel : nil
        let chargeCount = ch?.count ?? 0
        let missing = ch?.missingKwhCount ?? 0
        let fuelCount = fu?.fills ?? 0
        if power == .electricMotorcycle && chargeCount == 0 { return nil }

        var e = VehicleEnergyData()
        switch power {
        case .electric, .electricMotorcycle: e.title = "充電"
        case .gasoline, .motorcycle: e.title = "加油"
        case .hybrid: e.title = "油電"
        }
        let missingText = "記了 \(missing) 筆電費，都沒填度數；填了就能算每度電價 →"
        if chargeCount == 0 && fuelCount == 0 {
            if missing > 0 {
                e.collapsed = .missingKwh(text: missingText, expenseId: latestMissingKwhId(c))
            } else if power == .electric {
                e.collapsed = .addFirst(text: "＋ 記第一次充電（記下度數和里程錶，就能算每度電價和每公里）", kind: .charge)
            } else {
                e.collapsed = .addFirst(text: "＋ 記第一次加油（記下公升數和里程錶，就能算油耗和每公里）", kind: .fuel)
            }
            return e
        }

        let isHybrid = power == .hybrid
        if let ch = ch, chargeCount > 0 {
            e.blocks.append(chargeBlock(ch, c: c, compact: isHybrid))
        } else if isHybrid, missing > 0 {
            var b = VehicleEnergyData.Block()
            b.heading = "充電"
            b.hint = missingText
            if let id = latestMissingKwhId(c) { b.hintTap = .openExpense(id) }
            e.blocks.append(b)
        }
        if let fu = fu, fuelCount > 0 {
            e.blocks.append(fuelBlock(fu, c: c, compact: isHybrid))
        }
        var firsts: [Date] = []
        if chargeCount > 0, let d = ch?.firstDate { firsts.append(d) }
        if fuelCount > 0, let d = fu?.firstDate { firsts.append(d) }
        if let first = firsts.min() {
            e.trailing = "全部 \(chargeCount + fuelCount) 次・\(FinanceFormat.ym(first)) 起"
        }
        e.showsAnalytics = chargeCount > 0
        if chargeCount > 0 {
            e.footnote = isHybrid
                ? "度數是充電樁計的，包含充電損耗。"
                : "度數是充電樁計的，包含充電損耗；電池健康只跟這台車自己剛開始的時候比，要 10 次充 15% 以上的紀錄。"
        }
        return e
    }

    /// 這台車電費、沒填度數、≤ asOf 的最後一筆（「沒填度數 →」打開它）
    fileprivate static func latestMissingKwhId(_ c: VehicleCardContext) -> UUID? {
        for ex in c.links.expenses.reversed() {
            guard ex.vehicleExpenseCategory == .electricity, (ex.evKwh ?? 0) <= 0, c.onOrBeforeAsOf(ex.date) else { continue }
            return ex.id
        }
        return nil
    }

    /// 充電那一排：電車六格；油電只放每度電、平均每次、累計三格
    fileprivate static func chargeBlock(_ a: VehicleChargeSummary, c: VehicleCardContext, compact: Bool) -> VehicleEnergyData.Block {
        var b = VehicleEnergyData.Block()
        if compact { b.heading = "充電" }
        let toLedger = VehicleTap.ledgerFilter(.energy)
        var tiles: [VehicleTile] = []
        if let p = a.avgPricePerKwh {
            var sub = "全部 \(a.count) 次"
            if a.hasHomeKeyword, a.homeCount > 0, a.awayCount > 0, let h = a.homePricePerKwh, let w = a.awayPricePerKwh {
                sub = "家充 \(VehicleCardText.n1(h))・外面 \(VehicleCardText.n1(w))"
            }
            tiles.append(VehicleTile(label: "每度電", value: "\(VehicleCardText.n1(p)) 元", sub: sub, tap: toLedger))
        }
        if !compact, let k = a.avgCostPerKm {
            let sub = "\(a.intervalCount) 段・\(VehicleCardText.grouped(a.trackedKm)) 公里"
            tiles.append(VehicleTile(label: "每公里電費", value: "\(VehicleCardText.n1(k)) 元", sub: sub, tap: .openAnalytics))
        }
        if !compact, let r = a.kmPerKwh {
            tiles.append(VehicleTile(label: "每度跑", value: "\(VehicleCardText.n1(r)) 公里", sub: "越多越省", tap: .openAnalytics))
        }
        if let avg = a.avgKwhPerSession {
            let cost = a.avgCostPerSession.map { "約 \(MoneyFormat.short($0))" } ?? ""
            tiles.append(VehicleTile(label: "平均每次", value: "\(VehicleCardText.n1(avg)) 度", sub: cost, tap: toLedger))
        }
        tiles.append(VehicleTile(label: "累計", value: "\(VehicleCardText.amount1(a.totalKwh)) 度", sub: "\(a.count) 次", tap: toLedger))
        if !compact {
            if let change = a.sohChange {
                let scope = a.sohScope ?? "全部充電"
                tiles.append(VehicleTile(label: "電池", value: FinanceText.signedPercent(change), sub: "跟最初比・\(scope)", tap: .openAnalytics))
            } else {
                // 定案 23：有家充關鍵字時只用一組，可能 ≥ 10 筆仍算不出，最少寫「再 1 次」
                let more = max(1, 10 - a.capacityPointCount)
                tiles.append(VehicleTile(label: "電池", value: "還在累積", sub: "再 \(more) 次", tap: .openAnalytics))
            }
        }
        b.tiles = tiles
        if let s = a.latest {
            var line = "最近一次 \(FinanceFormat.shortDate(s.date, now: c.asOf))"
            if s.place != "未填地點" { line += " 在 \(s.place)" }
            line += " 充了 \(VehicleCardText.n1(s.kwh)) 度"
            if let from = s.fromPct, let to = s.toPct { line += "（\(VehicleCardText.pct(from)) → \(VehicleCardText.pct(to))）" }
            if s.kwh > 0 { line += "，每度 NT$\(VehicleCardText.n1(s.cost / s.kwh))" }
            b.latestLine = line
        }
        if a.missingKwhCount > 0 {
            b.hint = "還有 \(a.missingKwhCount) 筆電費沒填度數，沒算進每度電價 →"
            if let id = latestMissingKwhId(c) { b.hintTap = .openExpense(id) }
        }
        if a.hasHomeKeyword && a.homeCount == 0 {
            b.note = "還沒有家充紀錄：家裡充的電如果算在家裡電費，這裡的充電花費會偏低。"
        }
        let minN = VehicleChargeAnalytics.minTrend
        if a.count >= minN {
            b.chart = chargeChart(a, c: c)
        } else {
            b.chartPending = "再記 \(minN - a.count) 次就畫每度電價圖"
        }
        return b
    }

    /// 每度電價點圖：每次充電一點（說明「10/3・特斯拉超充 內湖・32 度・NT$9.5/度」，地點沒填就省掉那段）
    fileprivate static func chargeChart(_ a: VehicleChargeSummary, c: VehicleCardContext) -> VehicleEnergyData.Chart {
        var chart = VehicleEnergyData.Chart()
        var points: [VehicleEnergyData.Point] = []
        for s in a.sessions where s.kwh > 0 {
            guard let id = s.expenseId else { continue }
            let price = s.cost / s.kwh
            var pieces = [FinanceFormat.shortDate(s.date, now: c.asOf)]
            if s.place != "未填地點" { pieces.append(s.place) }
            pieces.append("\(VehicleCardText.n1(s.kwh)) 度")
            pieces.append("NT$\(VehicleCardText.n1(price))/度")
            points.append(VehicleEnergyData.Point(id: id, date: s.date, price: price, isHome: s.isHome,
                                                  caption: pieces.joined(separator: "・")))
        }
        chart.points = points
        chart.average = a.avgPricePerKwh ?? 0
        chart.hasHomeKeyword = a.hasHomeKeyword
        let prices = points.map { $0.price }
        if let lo = prices.min(), let hi = prices.max() {
            let avg = VehicleCardText.n1(chart.average)
            chart.accessibilityText = "\(points.count) 次充電，每度 \(VehicleCardText.n1(lo)) 到 \(VehicleCardText.n1(hi)) 元，平均 \(avg) 元"
        }
        return chart
    }

    /// 加油那一排：有公升數或里程時六格（算不出的不放），都沒有時三格加一行提示；油電只放三格
    fileprivate static func fuelBlock(_ u: VehicleFuelAnalytics, c: VehicleCardContext, compact: Bool) -> VehicleEnergyData.Block {
        var b = VehicleEnergyData.Block()
        if compact { b.heading = "加油" }
        let toLedger = VehicleTap.ledgerFilter(.energy)
        let monthTap: VehicleTap = c.isSold ? .none : .scrollTo(.monthly)
        var monthTile: VehicleTile? = nil
        if let pm = c.facts.fuelPerMonth {
            monthTile = VehicleTile(label: "每月油錢", value: MoneyFormat.compact(FinanceRound.round(pm, unit: 100)),
                                    sub: "近 \(c.facts.periodMonths) 個月平均", tap: monthTap)
        }
        var avgTile: VehicleTile? = nil
        if let avg = u.avgCost {
            avgTile = VehicleTile(label: "平均每次", value: MoneyFormat.compact(avg), sub: "全部 \(u.fills) 次", tap: toLedger)
        }
        var countSub = ""
        if let first = u.firstDate { countSub = "\(FinanceFormat.ym(first)) 起" }
        let countTile = VehicleTile(label: "次數", value: "\(u.fills)", sub: countSub, tap: toLedger)
        var literTile: VehicleTile? = nil
        if let pl = u.perLiter {
            literTile = VehicleTile(label: "每公升", value: "\(VehicleCardText.n1(pl)) 元", sub: "有記公升的 \(u.litersFills) 次", tap: toLedger)
        }
        var list: [VehicleTile?] = []
        if compact && literTile != nil {
            list = [literTile, monthTile, avgTile]
        } else if compact {
            list = [monthTile, avgTile, countTile]
        } else if u.perLiter != nil || u.perKm != nil {
            var economy: VehicleTile? = nil
            if let k = u.kmPerLiter {
                economy = VehicleTile(label: "油耗", value: "\(VehicleCardText.n1(k)) 公里／公升", sub: "越高越省")
            }
            var perKm: VehicleTile? = nil
            if let pk = u.perKm {
                let sub = "\(u.intervalCount) 段・\(VehicleCardText.grouped(u.trackedKm)) 公里"
                perKm = VehicleTile(label: "每公里油錢", value: "\(VehicleCardText.n1(pk)) 元", sub: sub)
            }
            var total: VehicleTile? = nil
            if u.liters > 0 {
                total = VehicleTile(label: "累計", value: "\(VehicleCardText.amount1(u.liters)) 公升",
                                    sub: "有記公升的 \(u.litersFills) 次", tap: toLedger)
            }
            list = [literTile, economy, perKm, avgTile, total, monthTile]
        } else {
            list = [monthTile, avgTile, countTile]
        }
        b.tiles = list.compactMap { $0 }
        if let s = u.latest {
            var line = "最近一次 \(FinanceFormat.shortDate(s.date, now: c.asOf))"
            if !s.place.isEmpty { line += " 在 \(s.place)" }
            line += " 加了 \(MoneyFormat.short(s.cost))"
            if let l = s.liters { line += "（\(VehicleCardText.n1(l)) 公升）" }
            b.latestLine = line
        }
        var hint: String?
        switch (u.perLiter != nil, u.perKm != nil) {
        case (false, false): hint = "加油時多記公升數和里程錶（選填），就能算油耗、每公升和每公里油錢 →"
        case (true, false): hint = "加油時多記里程錶（選填），就能算油耗和每公里油錢 →"
        case (false, true): hint = "加油時多記公升數（選填），就能算每公升和油耗 →"
        case (true, true): hint = nil
        }
        // 油電那一排只放三格（不放油耗、每公里）：只提醒記公升數，不叫你記算了也看不到的里程
        if compact { hint = u.perLiter == nil ? "加油時多記公升數（選填），就能算每公升 →" : nil }
        if let h = hint, let latest = u.latest {
            b.hint = h
            b.hintTap = .openExpense(latest.id)
        }
        return b
    }
}

// MARK: - 我的帳本

extension VehicleLedger {
    /// 以記帳為準：VehicleLinks 的支出（≤ asOf）＋沒連到記帳的舊變動鏡像＋買車列＋車貸年列＋定期年列。
    /// T 用原始金額加完才四捨五入一次，格子、長條、篩選小計、年份小計都用最大餘數法分（Σ年份＝Σ篩選＝T）
    fileprivate static func build(_ c: VehicleCardContext) -> VehicleLedger {
        let down = computeDownPayment(c)
        var events: [VehicleLedgerEvent] = []
        if let p = purchaseEvent(c, down: down) { events.append(p) }
        for ex in c.links.expenses where c.onOrBeforeAsOf(ex.date) && !ex.isRecurringFixed {
            events.append(expenseEvent(ex, c: c))
        }
        events += legacyEvents(c)
        events += loanYearEvents(c)
        events += fixedYearEvents(c)
        events.sort { a, b in a.date != b.date ? a.date > b.date : a.id > b.id }

        var l = VehicleLedger()
        l.events = events
        l.recordCount = events.filter { isRecord($0) }.count
        l.recordsTitle = l.recordCount > 0 ? "紀錄・\(l.recordCount) 筆" : "紀錄"
        l.headerTrailing = "從 \(FinanceFormat.ym(c.v.purchaseDate)) 買下"
        l.downPayment = down

        var raw: [VehicleLedgerBucket: Double] = [:]
        for e in events where e.countsInTotal { raw[e.bucket, default: 0] += e.amount }
        l.rawTotals = raw
        let order = VehicleLedgerBucket.allCases
        let rawParts = order.map { raw[$0] ?? 0 }
        let rawTotal = rawParts.reduce(0, +)
        l.unit = FinanceRound.ledgerUnit(rawTotal)
        l.total = FinanceRound.round(rawTotal, unit: l.unit)
        let shares = FinanceRound.largestRemainder(rawParts, total: l.total, unit: l.unit)
        for (i, b) in order.enumerated() { l.totals[b] = shares[i] }

        for filter in VehicleLedgerFilter.allCases {
            let amount = filter.bucket.map { l.amount($0) } ?? l.total
            let rows = filter.bucket.map { b in events.filter { $0.bucket == b } } ?? events
            let text = amount != 0 ? "\(filter.title) \(MoneyFormat.short(amount))" : filter.title
            l.filters.append(VehicleLedgerFilterChip(filter: filter, amount: amount, text: text, rowCount: rows.count))
            l.yearsByFilter[filter] = yearGroups(rows, total: amount, unit: l.unit, asOf: c.asOf)
        }
        l.addKinds = VehicleLedgerAddKind.menu(for: c.v.powerType)
        fillSummary(&l, c: c)
        return l
    }

    /// 記帳列和舊鏡像列才算「筆」（買車列、年列不算）
    fileprivate static func isRecord(_ e: VehicleLedgerEvent) -> Bool {
        switch e.source {
        case .expense, .legacy: return true
        default: return false
        }
    }

    /// 自備款 D：沒車貸＝購入價；有車貸且每筆都填了總貸款金額＝購入價 − ΣP；缺 P、舊車貸鏡像、或借的比車價多 → nil
    fileprivate static func computeDownPayment(_ c: VehicleCardContext) -> Double? {
        let price = c.v.purchasePrice
        guard price > 0 else { return nil }
        guard c.hasAnyLoan else { return price }
        guard c.legacyLoans.isEmpty else { return nil }
        var borrowed = 0.0
        for loan in c.facts.loans {
            guard let p = loan.principal else { return nil }
            borrowed += p
        }
        let d = price - borrowed
        return d > 0 ? d : nil
    }

    /// 「買下 Taycan」：一次付清寫「購入」；有車貸寫自備款；算不出自備款照寫購入價、標「自備款不知道」、不進合計
    fileprivate static func purchaseEvent(_ c: VehicleCardContext, down: Double?) -> VehicleLedgerEvent? {
        let v = c.v
        let price = v.purchasePrice
        guard price > 0 else { return nil }
        let detail: String
        var warn: String? = nil
        if let d = down, d < price {
            detail = "自備款（購入 \(MoneyFormat.short(price)) − 車貸 \(MoneyFormat.short(price - d))）"
        } else if down != nil {
            detail = "購入"
        } else {
            detail = "購入 \(MoneyFormat.short(price))"
            warn = "自備款不知道"
        }
        return VehicleLedgerEvent(id: "purchase", date: v.purchaseDate, bucket: .purchase, title: "買下 \(c.name)",
                                  detail: detail, amount: down ?? price, source: .purchase, mark: .purchase,
                                  warnTag: warn, countsInTotal: down != nil,
                                  shareTitle: "買下 \(c.shareName)", shareDetail: detail)
    }

    /// 帳本的類別：不是週期的固定支出（含貸款）一律進「停車・洗車・其他」；電動機車的訂閱（換電資費）算油電
    fileprivate static func bucketOf(_ ex: Expense, power: VehiclePowerType) -> VehicleLedgerBucket {
        switch ex.expenseType {
        case .fixed:
            guard ex.isRecurringFixed else { return .other }
            if ex.fixedCategory == .loan { return .loan }
            if power == .electricMotorcycle && ex.fixedCategory == .subscription { return .energy }
            return .fixed
        case .variable:
            return legacyBucket(ex.vehicleExpenseCategory)
        }
    }

    fileprivate static func legacyBucket(_ cat: VehicleVariableCategory?) -> VehicleLedgerBucket {
        switch cat {
        case .fuel?, .electricity?: return .energy
        case .maintenance?, .repair?: return .care
        default: return .other
        }
    }

    /// 一筆記帳變成一列：標題地點 → 你取的名 → 備註第一行 → 分類名；細字度數／公升、里程、備註（都沒有才寫分類名）
    fileprivate static func expenseEvent(_ ex: Expense, c: VehicleCardContext) -> VehicleLedgerEvent {
        let amount = c.amount(ex)
        let title = VehicleFacts.label(ex, vehicleName: c.v.name)
        let measures = VehicleCardText.measures(ex, amount: amount)
        var shown = measures
        if let km = VehicleCardText.odometer(ex) { shown.append(km) }
        if let memo = VehicleCardText.firstLine(ex.note), memo != title { shown.append(memo) }
        let category = VehicleFacts.categoryLabel(ex)
        if shown.isEmpty && category != title { shown.append(category) }
        let photos = ex.photoFileNames.filter { FinanceFormat.isImage($0) }
        return VehicleLedgerEvent(id: "e-\(ex.id.uuidString)", date: ex.date, bucket: bucketOf(ex, power: c.v.powerType),
                                  title: title, detail: shown.joined(separator: "・"), amount: amount,
                                  source: .expense(ex.id), mark: VehicleLedgerMark.of(ex), photoFileNames: photos,
                                  expenseId: ex.id, shareTitle: VehicleCardText.shareTitle(ex),
                                  shareDetail: measures.joined(separator: "・"))
    }

    /// 沒連到記帳（或記帳裡找不到）的舊變動鏡像：用自己的金額和日期、標「沒連到記帳」
    fileprivate static func legacyEvents(_ c: VehicleCardContext) -> [VehicleLedgerEvent] {
        var out: [VehicleLedgerEvent] = []
        for m in c.links.legacyVariable where m.amount > 0 && c.onOrBeforeAsOf(m.date) {
            out.append(VehicleLedgerEvent(id: "l-\(m.id.uuidString)", date: m.date, bucket: legacyBucket(m.category),
                                          title: m.category.rawValue, detail: "", amount: m.amount, source: .legacy(m.id),
                                          mark: VehicleCardText.mark(m.category), isUnlinked: true,
                                          shareTitle: VehicleCardText.shareCategory(m.category), shareDetail: ""))
        }
        return out
    }

    /// 車貸每筆每年一列「車貸 1–10 月・10 期」：期數用 paidCount 前後相減，細字用 split 拆利息／本金（算得出才寫）
    fileprivate static func loanYearEvents(_ c: VehicleCardContext) -> [VehicleLedgerEvent] {
        let cal = c.cal
        let endYear = cal.component(.year, from: c.asOf)
        var out: [VehicleLedgerEvent] = []
        for l in c.facts.loans where l.paidPeriods > 0 {
            let startYear = cal.component(.year, from: l.firstDue)
            guard startYear <= endYear else { continue }
            var before = 0
            for y in startYear...endYear {
                guard let dec31 = cal.date(from: DateComponents(year: y, month: 12, day: 31)),
                      let prevDec31 = cal.date(from: DateComponents(year: y - 1, month: 12, day: 31)) else { continue }
                let through = min(dec31, c.asOf)
                let total = l.paidCount(onOrBefore: through, calendar: cal)
                let k = total - before
                let firstK = before + 1
                before = total
                guard k > 0 else { continue }
                let firstDay = l.due(firstK, calendar: cal)
                let lastDay = l.due(total, calendar: cal)
                let m1 = cal.component(.month, from: firstDay)
                let m2 = cal.component(.month, from: lastDay)
                let months = m1 == m2 ? "\(m1) 月" : "\(m1)–\(m2) 月"
                var detail = "含利息"
                if let split = l.split(after: prevDec31, through: through, calendar: cal) {
                    detail = "利息約 \(MoneyFormat.compact(split.interest))・本金約 \(MoneyFormat.compact(split.principal))"
                }
                out.append(VehicleLedgerEvent(id: "loan-\(l.id.uuidString)-\(y)", date: lastDay, bucket: .loan,
                                              title: "\(l.displayTitle) \(months)・\(k) 期", detail: detail,
                                              amount: Double(k) * l.perPeriod, source: .loanYear(l.id, y), mark: .loan,
                                              expenseId: l.id, shareTitle: "車貸 \(months)・\(k) 期", shareDetail: detail))
            }
        }
        return out
    }

    /// 定期（不是貸款的週期固定支出）每筆每年一列「停車月租・10 期」：期數照 fixedPeriodCount 數到 asOf（明確傳西曆）
    fileprivate static func fixedYearEvents(_ c: VehicleCardContext) -> [VehicleLedgerEvent] {
        let cal = c.cal
        let endYear = cal.component(.year, from: c.asOf)
        var out: [VehicleLedgerEvent] = []
        for ex in c.links.expenses where ex.isRecurringFixed && ex.fixedCategory != .loan {
            guard let rec = ex.recurrence, c.onOrBeforeAsOf(ex.date) else { continue }
            let (component, step) = rec.componentValue
            let per = c.amount(ex)
            let startYear = cal.component(.year, from: ex.date)
            guard startYear <= endYear else { continue }
            let name = VehicleFacts.label(ex, vehicleName: c.v.name)
            let shareName = VehicleCardText.shareTitle(ex)
            let detail = "\(rec.rawValue) \(MoneyFormat.short(per))"
            let bucket = bucketOf(ex, power: c.v.powerType)
            let mark = VehicleLedgerMark.of(ex)
            var before = 0
            for y in startYear...min(endYear, startYear + 120) {
                guard let dec31 = cal.date(from: DateComponents(year: y, month: 12, day: 31)) else { continue }
                let until = min(dec31, c.asOf)
                let total = ex.fixedPeriodCount(until: until, calendar: cal)
                let k = total - before
                before = total
                guard k > 0 else { continue }
                let lastDue = cal.date(byAdding: component, value: step * (total - 1), to: ex.date) ?? until
                out.append(VehicleLedgerEvent(id: "fixed-\(ex.id.uuidString)-\(y)", date: lastDue, bucket: bucket,
                                              title: "\(name)・\(k) 期", detail: detail, amount: Double(k) * per,
                                              source: .fixedYear(ex.id, y), mark: mark, expenseId: ex.id,
                                              shareTitle: "\(shareName)・\(k) 期", shareDetail: detail))
            }
        }
        return out
    }

    /// 年份分組：各年小計再用最大餘數分一次（加起來＝那個篩選的小計）；不算進合計的買車列不算進年份小計
    fileprivate static func yearGroups(_ rows: [VehicleLedgerEvent], total: Double, unit: Double, asOf: Date) -> [VehicleLedgerYear] {
        guard !rows.isEmpty else { return [] }
        var byYear: [Int: [VehicleLedgerEvent]] = [:]
        for e in rows { byYear[e.year, default: []].append(e) }
        let years = byYear.keys.sorted(by: >)
        var raw: [Double] = []
        for y in years {
            let list = byYear[y] ?? []
            raw.append(list.filter { $0.countsInTotal }.reduce(0.0) { $0 + $1.amount })
        }
        let shares = FinanceRound.largestRemainder(raw, total: total, unit: unit)
        let current = FinanceFormat.year(asOf)
        var out: [VehicleLedgerYear] = []
        for (i, y) in years.enumerated() {
            let list = byYear[y] ?? []
            let count = list.filter { isRecord($0) }.count
            var title = "\(y) 年"
            if count > 0 { title += "・\(count) 筆" }
            if list.contains(where: { $0.countsInTotal }) { title += "・\(MoneyFormat.short(shares[i]))" }
            out.append(VehicleLedgerYear(year: y, events: list, recordCount: count, total: shares[i], title: title,
                                         isCurrent: y == current))
        }
        return out
    }

    /// 卡 1：六格、合計、長條、那一句；沒紀錄時只有「買車」「估值」兩格加空狀態那句話
    fileprivate static func fillSummary(_ l: inout VehicleLedger, c: VehicleCardContext) {
        let f = c.facts
        l.totalLabel = c.isSold ? "到賣出那天總共付了" : "到今天總共付了"
        l.totalText = MoneyFormat.short(l.total)
        var tiles: [VehicleTile] = [purchaseTile(l, c: c)]
        guard !l.isEmpty else {
            tiles.append(valueTile(c))
            l.tiles = tiles
            l.shareTiles = tiles
            l.emptyHint = "加油、充電、保險、稅費、保養、車貸都可以記在這裡，記了之後上面會算出這台車實際花了你多少。"
            return
        }
        if f.loans.isEmpty {
            tiles.append(valueTile(c))
        } else {
            let paid = l.amount(.loan)
            let paidN = f.loans.reduce(0) { $0 + $1.paidPeriods }
            let tap: VehicleTap = paid != 0 ? .scrollTo(.loan) : .none
            tiles.append(VehicleTile(label: "已繳車貸", value: MoneyFormat.compact(paid), sub: "\(paidN) 期", tap: tap))
        }
        tiles.append(fixedTile(l, c: c))
        tiles.append(countTile(l, bucket: .energy, label: "油電", sub: energySub(l)))
        tiles.append(countTile(l, bucket: .care, label: "保養・維修", sub: nil))
        tiles.append(countTile(l, bucket: .other, label: "停車・洗車・其他", sub: nil))
        l.tiles = tiles
        let shareFixed = fixedTile(l, c: c, forShare: true)
        l.shareTiles = tiles.map { $0.label == shareFixed.label ? shareFixed : $0 }
        var parts: [VehicleLedgerPart] = []
        for b in VehicleLedgerBucket.allCases {
            let v = l.amount(b)
            guard v != 0 else { continue }
            parts.append(VehicleLedgerPart(bucket: b, value: v, legend: "\(b.title) \(MoneyFormat.compact(v))"))
        }
        l.parts = parts
        fillSpentLine(&l, c: c)
    }

    /// 「買車」格：自備款（一次付清寫購入日；有車貸寫「購入 − 車貸」）；算不出寫「—」加注意色「自備款不知道」
    fileprivate static func purchaseTile(_ l: VehicleLedger, c: VehicleCardContext) -> VehicleTile {
        let price = c.v.purchasePrice
        let day = FinanceFormat.ymd(c.v.purchaseDate)
        guard price > 0 else { return VehicleTile(label: "買車", value: "—", sub: day, tap: .edit(.purchase)) }
        guard let down = l.downPayment else {
            return VehicleTile(label: "買車", value: "—", sub: "自備款不知道", subTone: .warn, tap: .edit(.purchase))
        }
        let shown = MoneyFormat.compact(l.amount(.purchase))
        if down < price {
            let sub = "購入 \(MoneyFormat.compact(price)) − 車貸 \(MoneyFormat.compact(price - down))"
            return VehicleTile(label: "買車", value: shown, sub: sub, tap: .edit(.purchase))
        }
        return VehicleTile(label: "買車", value: shown, sub: "\(day)・一次付清", tap: .edit(.purchase))
    }

    /// 「估值」格（已售出寫「成交價」）：小字「折舊 98萬」中性、「增值 X」紅（跟看板下的膠囊同一個數）
    fileprivate static func valueTile(_ c: VehicleCardContext) -> VehicleTile {
        let f = c.facts
        let label = c.isSold ? "成交價" : "估值"
        let focus: VehicleEditFocus = c.isSold ? .soldPrice : .value
        let value = MoneyFormat.compact(f.value)
        if f.valueIsFallback {
            return VehicleTile(label: label, value: value, sub: "還沒填", subTone: .warn, tap: .edit(focus))
        }
        let dep = f.depreciation
        guard f.purchase > 0, abs(dep) >= 1 else {
            return VehicleTile(label: label, value: value, sub: f.purchase > 0 ? "持平" : "", tap: .edit(focus))
        }
        if dep > 0 {
            return VehicleTile(label: label, value: value, sub: "折舊 \(MoneyFormat.compact(dep))", tap: .edit(focus))
        }
        return VehicleTile(label: label, value: value, sub: "增值 \(MoneyFormat.compact(-dep))", subTone: .up, tap: .edit(focus))
    }

    /// 「定期」格：小字寫錢最多的那筆「停車月租・26 期」；兩筆以上「停車月租 等 3 筆」。
    /// forShare：分享圖用分類名（「車位租金・26 期」），不輸出你自己取的名稱
    fileprivate static func fixedTile(_ l: VehicleLedger, c: VehicleCardContext, forShare: Bool = false) -> VehicleTile {
        var top: (name: String, periods: Int, amount: Double)? = nil
        var count = 0
        for ex in c.links.expenses where ex.isRecurringFixed && ex.fixedCategory != .loan {
            guard bucketOf(ex, power: c.v.powerType) == .fixed else { continue }
            let n = ex.fixedPeriodCount(until: c.asOf, calendar: c.cal)
            guard n > 0 else { continue }
            count += 1
            let amount = Double(n) * c.amount(ex)
            if let t = top, t.amount >= amount { continue }
            let name = forShare ? VehicleCardText.shareTitle(ex) : VehicleFacts.label(ex, vehicleName: c.v.name)
            top = (name: name, periods: n, amount: amount)
        }
        let value = l.amount(.fixed)
        guard let t = top else {
            return VehicleTile(label: "定期", value: value != 0 ? MoneyFormat.compact(value) : "—", sub: "還沒有紀錄")
        }
        let sub = count > 1 ? "\(t.name) 等 \(count) 筆" : "\(t.name)・\(t.periods) 期"
        return VehicleTile(label: "定期", value: MoneyFormat.compact(value), sub: sub, tap: .ledgerFilter(.fixed))
    }

    /// 「油電」格小字：「6 次充電」「26 次加油」「6 次充電・3 次加油」；都沒有（電動機車換電月租）nil
    fileprivate static func energySub(_ l: VehicleLedger) -> String? {
        var charges = 0
        var fills = 0
        for e in l.events where e.bucket == .energy && isRecord(e) {
            if e.mark == .charge { charges += 1 }
            if e.mark == .fuel { fills += 1 }
        }
        var parts: [String] = []
        if charges > 0 { parts.append("\(charges) 次充電") }
        if fills > 0 { parts.append("\(fills) 次加油") }
        return parts.isEmpty ? nil : parts.joined(separator: "・")
    }

    /// 油電、保養・維修、停車・洗車・其他：沒有任何列時寫「—」「還沒有紀錄」、不能點；小字預設「N 筆」
    fileprivate static func countTile(_ l: VehicleLedger, bucket: VehicleLedgerBucket, label: String, sub: String?) -> VehicleTile {
        let rows = l.events.filter { $0.bucket == bucket }
        guard !rows.isEmpty else { return VehicleTile(label: label, value: "—", sub: "還沒有紀錄") }
        let n = rows.filter { isRecord($0) }.count
        let text = sub ?? (n > 0 ? "\(n) 筆" : "")
        let filter: VehicleLedgerFilter
        switch bucket {
        case .energy: filter = .energy
        case .care: filter = .care
        default: filter = .other
        }
        return VehicleTile(label: label, value: MoneyFormat.compact(l.amount(bucket)), sub: text, tap: .ledgerFilter(filter))
    }

    /// 那一句：Y＝畫面上的 T − 畫面上的拿回；折舊＋已付利息＋養車三個加數用最大餘數分到 Y。
    /// 有車貸但算不出本金、或自備款算不出時不寫
    fileprivate static func fillSpentLine(_ l: inout VehicleLedger, c: VehicleCardContext) {
        let f = c.facts
        guard l.downPayment != nil, c.legacyLoans.isEmpty, f.purchase > 0 else { return }
        var interest = 0.0
        for loan in f.loans {
            guard let i = loan.interestPaid else { return }
            interest += i
        }
        let hasLoans = !f.loans.isEmpty
        let back = FinanceRound.round(f.value - f.owed, unit: l.unit)
        let y = l.total - back
        l.spent = y
        let upkeepBuckets: [VehicleLedgerBucket] = [.fixed, .energy, .care, .other]
        let upkeep = upkeepBuckets.reduce(0.0) { $0 + (l.rawTotals[$1] ?? 0) }
        let raw: [Double] = hasLoans ? [f.depreciation, interest, upkeep] : [f.depreciation, upkeep]
        let names: [String] = hasLoans ? ["折舊", "已付利息", "養車"] : ["折舊", "養車"]
        let shares = FinanceRound.largestRemainder(raw, total: y, unit: l.unit)

        var runs: [FinanceRun] = []
        let owing = hasLoans && f.owed >= 1
        if owing {
            let head = c.isSold ? "賣掉時還掉車貸本金 約 " : "照估值今天賣掉，還掉車貸本金 約 "
            runs.append(FinanceRun(text: "\(head)\(MoneyFormat.short(f.owed))，"))
            if back >= 0 {
                runs.append(FinanceRun(text: "拿回 約 "))
                runs.append(FinanceRun(text: MoneyFormat.short(back), bold: true, tone: .good))
            } else {
                runs.append(FinanceRun(text: "還差 "))
                runs.append(FinanceRun(text: MoneyFormat.short(-back), bold: true, tone: .bad))
            }
        } else {
            runs.append(FinanceRun(text: c.isSold ? "賣掉拿回 " : "照估值今天賣掉拿回 "))
            runs.append(FinanceRun(text: MoneyFormat.short(back), bold: true))
        }
        let until = c.isSold ? "到賣出那天" : "到今天"
        if y > 0 {
            runs.append(FinanceRun(text: owing ? "；\(until)實際花了你 約 " : "；這台車\(until)實際花了你 約 "))
            runs.append(FinanceRun(text: MoneyFormat.short(y), bold: true))
            var pieces: [String] = []
            for (i, s) in shares.enumerated() where s != 0 { pieces.append("\(names[i]) \(MoneyFormat.short(s))") }
            if f.depreciation >= 0 && !pieces.isEmpty {
                runs.append(FinanceRun(text: "：\(pieces.joined(separator: "＋"))。"))
            } else {
                runs.append(FinanceRun(text: "。"))
            }
        } else {
            runs.append(FinanceRun(text: "，比\(until)付出去的還多 "))
            runs.append(FinanceRun(text: MoneyFormat.short(-y), bold: true, tone: .good))
            runs.append(FinanceRun(text: "。"))
        }
        l.spentLine = FinanceLine(runs: runs)
    }
}

extension VehicleLedgerEvent {
    /// 帳本一列：年、日期塊、金額字、VoiceOver 句子在這裡一次算好
    fileprivate init(id: String, date: Date, bucket: VehicleLedgerBucket, title: String, detail: String, amount: Double,
                     source: Source, mark: VehicleLedgerMark, photoFileNames: [String] = [], isUnlinked: Bool = false,
                     warnTag: String? = nil, countsInTotal: Bool = true, expenseId: UUID? = nil,
                     shareTitle: String, shareDetail: String) {
        self.id = id
        self.date = date
        self.bucket = bucket
        self.title = title
        self.detail = detail
        self.amount = amount
        self.source = source
        self.mark = mark
        self.year = FinanceFormat.year(date)
        self.dayText = FinanceFormat.day(date)
        self.monthText = FinanceFormat.ym(date)
        let money = MoneyFormat.short(amount)
        self.amountText = money
        self.photoFileNames = photoFileNames
        self.isUnlinked = isUnlinked
        self.warnTag = warnTag
        self.countsInTotal = countsInTotal
        self.expenseId = expenseId
        if case .expense = source {
            self.canDelete = true
        } else {
            self.canDelete = false
        }
        self.shareTitle = shareTitle
        self.shareDetail = shareDetail
        var spoken = "\(FinanceFormat.ymd(date))，\(title)"
        if !detail.isEmpty { spoken += "，\(detail)" }
        spoken += "，\(money)"
        if isUnlinked { spoken += "，沒連到記帳" }
        if let w = warnTag { spoken += "，\(w)" }
        if !photoFileNames.isEmpty { spoken += "，\(photoFileNames.count) 張收據" }
        self.accessibilityText = spoken
    }
}

// MARK: - 車輛資料、照片

extension VehicleCardData {
    /// 車輛資料：沒有值的列不出現；只剩車子、購入、估值時加一行「補上品牌、車主、電池容量 → 編輯」
    fileprivate static func infoData(_ c: VehicleCardContext) -> VehicleInfoData {
        let v = c.v
        var info = VehicleInfoData()
        info.trailing = v.powerType.shortName
        var rows: [VehicleInfoData.Row] = []
        let brand = v.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = v.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let car = [brand, model].filter { !$0.isEmpty }.joined(separator: " ")
        rows.append(.init(id: "car", label: "車子", value: car.isEmpty ? c.name : car))
        if v.hasBattery, let cap = v.batteryCapacityKWh, cap > 0 {
            rows.append(.init(id: "power", label: "動力", value: "\(v.powerType.shortName)・原廠電池 \(VehicleCardText.n1(cap)) 度",
                              tap: .edit(.battery)))
        }
        var bought = FinanceFormat.ymd(v.purchaseDate)
        if v.purchasePrice > 0 { bought += "・\(MoneyFormat.short(v.purchasePrice))" }
        rows.append(.init(id: "purchase", label: "購入", value: bought))
        rows += valueRows(c)
        if let odo = c.facts.odometer, let km = odo.latestKm, let at = odo.latestDate {
            var text = "\(VehicleCardText.grouped(km)) 公里（\(FinanceFormat.ymd(at))）"
            if let annual = odo.annualKm, annual > 0 { text += "・一年約開 \(VehicleCardText.kmText(annual))" }
            rows.append(.init(id: "odometer", label: "里程", value: text))
        }
        let home = (v.homeChargePlace ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if v.hasBattery, !home.isEmpty {
            rows.append(.init(id: "home", label: "家充地點", value: home, tap: .edit(.homeCharge)))
        }
        let owner = v.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !owner.isEmpty { rows.append(.init(id: "owner", label: "車主", value: owner)) }
        if let sold = v.soldDate {
            var text = FinanceFormat.ymd(sold)
            if let sp = v.soldPrice, sp > 0 {
                text += "・成交 \(MoneyFormat.short(sp))"
            } else {
                text += "（沒填成交價，用估值算）"
            }
            rows.append(.init(id: "sold", label: "售出", value: text, tap: .edit(.sold)))
        }
        let note = v.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { rows.append(.init(id: "note", label: "備註", value: note, kind: .note)) }
        info.rows = rows
        let basic: Set<String> = ["car", "purchase", "value", "valueStale"]
        if rows.allSatisfy({ basic.contains($0.id) }) { info.hint = "補上品牌、車主、電池容量 → 編輯" }
        return info
    }

    /// 估值列（下面一行一般行情參考）＋超過 12 個月沒更新的注意列；已售出只寫賣出前的估值
    fileprivate static func valueRows(_ c: VehicleCardContext) -> [VehicleInfoData.Row] {
        let v = c.v
        let f = c.facts
        var rows: [VehicleInfoData.Row] = []
        if c.isSold {
            guard v.currentValue > 0 else { return rows }
            var text = MoneyFormat.short(v.currentValue)
            if let at = v.valueUpdatedAt { text += "・\(FinanceFormat.ym(at)) 更新" }
            rows.append(.init(id: "value", label: "估值", value: text, tap: .edit(.value)))
            return rows
        }
        if f.valueIsFallback {
            let text = "還沒填（先用購入價 \(MoneyFormat.short(f.value))）"
            rows.append(.init(id: "value", label: "估值", value: text, tap: .edit(.value)))
            return rows
        }
        var text = MoneyFormat.short(f.value)
        if let at = v.valueUpdatedAt { text += "・\(FinanceFormat.ym(at)) 更新" }
        let market = marketLine(c)
        let action: String? = market == nil ? nil : "更新估值 ›"
        rows.append(.init(id: "value", label: "估值", value: text, tap: .edit(.value), detail: market, detailAction: action))
        if let at = v.valueUpdatedAt, let limit = c.cal.date(byAdding: .month, value: 12, to: at), limit < c.now {
            rows.append(.init(id: "valueStale", label: "", value: "估值一年沒更新了", kind: .warning, tap: .edit(.value)))
        }
        return rows
    }

    /// 「一般每年折 15% 估：約 NT$254.5萬，差不多」：持有滿 3 個月、有購入價、沒有售出、估值有填才寫
    fileprivate static func marketLine(_ c: VehicleCardContext) -> String? {
        let f = c.facts
        guard !c.isSold, !f.valueIsFallback, f.purchase > 0, f.heldMonths >= 3,
              let ref = VehicleValuation.marketEstimate(purchase: f.purchase, from: c.v.purchaseDate, to: c.asOf),
              ref > 0 else { return nil }
        let head = "一般每年折 15% 估：約 \(MoneyFormat.short(ref))"
        let diff = f.value - ref
        if abs(diff) <= ref * 0.1 { return "\(head)，差不多" }
        let word = diff > 0 ? "高" : "低"
        return "\(head)，比一般行情\(word) \(MoneyFormat.short(abs(diff)))"
    }

    /// 照片與單據：照片紀錄＋帳本那批支出的收據（只算圖片、用支出 id 去重、不截 asOf）；
    /// 封面＝最新一筆有照片的「車輛照片」（沒有就最新一筆有照片的紀錄，跟列表項目卡同一張），排最前面，其他新到舊
    fileprivate static func mediaData(_ c: VehicleCardContext) -> VehicleMediaData {
        let records = c.v.photoRecords
        let withPhotos = records.filter { rec in !rec.photoFileNames.filter { FinanceFormat.isImage($0) }.isEmpty }
        let cover = withPhotos.filter { $0.category == .appearance }.max { $0.date < $1.date }
            ?? withPhotos.max { $0.date < $1.date }
        var items: [VehicleMediaData.Item] = []
        var count = 0
        for r in records {
            let files = r.photoFileNames.filter { FinanceFormat.isImage($0) }
            count += files.count
            let t = r.title.trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(VehicleMediaData.Item(id: "record-\(r.id.uuidString)", source: .record(r.id),
                                               title: t.isEmpty ? r.category.rawValue : t, date: r.date,
                                               dateText: FinanceFormat.shortDate(r.date, now: c.now),
                                               category: r.category, fileNames: files, note: r.note,
                                               isCover: r.id == cover?.id))
        }
        for ex in c.links.expenses {
            let files = ex.photoFileNames.filter { FinanceFormat.isImage($0) }
            guard !files.isEmpty else { continue }
            count += files.count
            items.append(VehicleMediaData.Item(id: "expense-\(ex.id.uuidString)", source: .expense(ex.id),
                                               title: VehicleFacts.label(ex, vehicleName: c.v.name), date: ex.date,
                                               dateText: FinanceFormat.shortDate(ex.date, now: c.now),
                                               category: nil, fileNames: files, note: ex.note, isCover: false))
        }
        items.sort { a, b in
            if a.isCover != b.isCover { return a.isCover }
            return a.date != b.date ? a.date > b.date : a.id < b.id
        }
        var m = VehicleMediaData()
        m.photoCount = count
        m.trailing = count > 0 ? "\(count) 張" : nil
        m.items = items
        return m
    }
}

// MARK: - 修正（純函式：只改傳進來的陣列／車子，呼叫端一次寫回 store）

enum VehicleFixes {
    /// 在賣出日停止：先 VehicleSale.syncStops 停車貸／保險／稅費，其餘（月租、訂閱）endDate＝soldDate、endReason＝.assetSold
    @discardableResult static func stopAtSale(_ ids: [UUID], soldDate: Date, vehicle: Vehicle,
                                             in expenses: inout [Expense], calendar: Calendar) -> Bool {
        var changed = VehicleSale.syncStops(of: vehicle, soldDate: soldDate, in: &expenses, calendar: calendar)
        let wanted = Set(ids)
        let soldDay = calendar.startOfDay(for: soldDate)
        for i in expenses.indices where wanted.contains(expenses[i].id) && expenses[i].isRecurringFixed {
            if let end = expenses[i].endDate, calendar.startOfDay(for: end) <= soldDay { continue }
            expenses[i].endDate = soldDate
            expenses[i].endReason = .assetSold
            changed = true
        }
        return changed
    }

    /// 停止扣款：endDate＝day（西曆當天 0 點）；endReason 車貸 .other（主控裁定 7：不要冒充繳清，狀態寫「已停止」）、其他 .cancelled
    @discardableResult static func stop(_ id: UUID, on day: Date, in expenses: inout [Expense]) -> Bool {
        guard let i = expenses.firstIndex(where: { $0.id == id }), expenses[i].isRecurringFixed else { return false }
        let cal = Calendar(identifier: .gregorian)
        expenses[i].endDate = cal.startOfDay(for: day)
        let isLoan = expenses[i].fixedCategory == .loan
        expenses[i].endReason = isLoan ? FixedEndReason.other : FixedEndReason.cancelled
        return true
    }

    /// [v25.541] 名稱或備註裡有這些字，就看得出是車險
    static let insuranceWords = ["保險", "車險", "強制險", "綜合險", "乙式", "丙式", "甲式", "第三人責任", "竊盜險", "車體險"]

    /// [v25.541] 記成「其他」的車險：週期固定支出、類別「其他」（或沒有類別）、名稱或備註看得出是車險。
    /// 舊版車輛編輯頁只能從「稅費」記保險，記帳那邊就成了「其他・每年」
    static func isInsuranceAsOther(_ ex: Expense) -> Bool {
        guard ex.expenseType == .fixed, ex.isRecurringFixed else { return false }
        guard ex.fixedCategory == .other || ex.fixedCategory == nil else { return false }
        let text = ex.title + "\n" + ex.note
        return insuranceWords.contains { text.contains($0) }
    }

    /// [v25.541] 改成保險：類別保險、子分類照名稱或備註（有「強制」→ 強制險，其他 → 綜合險）、linkedVehicleId＝這台
    ///（只靠鏡像連過來的也接上：車險只認 linkedVehicleId，呼叫端接著拿掉鏡像）。
    /// 名稱、金額、週期、起訖、節稅覆寫都不動，帳本和每月養車的錢不變，只是改算成保險
    @discardableResult static func convertToInsurance(_ ids: [UUID], vehicleId: UUID, in expenses: inout [Expense]) -> Bool {
        let wanted = Set(ids)
        var changed = false
        for i in expenses.indices where wanted.contains(expenses[i].id) && expenses[i].expenseType == .fixed {
            let text = expenses[i].title + "\n" + expenses[i].note
            let sub: InsuranceSubCategory = text.contains("強制") ? .compulsory : .comprehensive
            expenses[i].fixedCategory = .insurance
            expenses[i].insuranceSubCategory = sub
            expenses[i].linkedVehicleId = vehicleId
            changed = true
        }
        return changed
    }

    /// 都算這台：linkedVehicleId＝vehicleId（子分類留 nil、不寫鏡像；已經連到別台的不動）
    @discardableResult static func assign(_ ids: [UUID], to vehicleId: UUID, in expenses: inout [Expense]) -> Bool {
        let wanted = Set(ids)
        var changed = false
        for i in expenses.indices where wanted.contains(expenses[i].id) && expenses[i].linkedVehicleId == nil {
            expenses[i].linkedVehicleId = vehicleId
            changed = true
        }
        return changed
    }

    /// 只從這台移掉鏡像（孤兒、連到別台、舊變動鏡像「移除」）；不動記帳
    static func removeMirrors(_ mirrorIds: Set<UUID>, from v: inout Vehicle) {
        v.fixedExpenses.removeAll { mirrorIds.contains($0.id) }
        v.variableExpenses.removeAll { mirrorIds.contains($0.id) }
    }

    /// 就是 0（報廢）：currentValue＝0、valueUpdatedAt＝today（有更新日的 0 才照 0 算，決定 10）
    static func markValueZero(_ v: inout Vehicle, today: Date) {
        v.currentValue = 0
        v.valueUpdatedAt = today
    }

    /// 舊變動鏡像補建記帳：回傳新 Expense（.variable、.vehicle、子分類、金額、日期、linkedVehicleId），並把鏡像 linkedExpenseId 接上。
    /// 變動鏡像有日期，照房屋 backfillSegment 直接建，不開表單；名稱用記帳頁連到車子時的預設「車名-分類名」
    static func backfillVariable(_ mirrorId: UUID, of v: inout Vehicle) -> Expense? {
        guard let i = v.variableExpenses.firstIndex(where: { $0.id == mirrorId }) else { return nil }
        let m = v.variableExpenses[i]
        guard m.amount > 0 else { return nil }
        let ex = Expense(title: "\(v.name)-\(m.category.rawValue)", amount: m.amount, date: m.date, expenseType: .variable,
                         variableCategory: .vehicle, linkedVehicleId: v.id, vehicleExpenseCategory: m.category)
        v.variableExpenses[i].linkedExpenseId = ex.id
        return ex
    }

    /// 舊定期鏡像補建：開 AddExpenseView 用的預設（carLoan→.carLoan、tax→.tax、subscription→.subscription；recurrence 照鏡像週期）。
    /// AddExpensePreset 沒有金額欄位：確認框寫出原本的金額讓你照打（定案 18）。
    /// @MainActor：makeFixedPreset 是 AddVehicleView（View，主執行緒）的 static func；呼叫端是卡片外殼，本來就在主執行緒
    @MainActor static func backfillPreset(for mirror: VehicleFixedExpense, vehicleId: UUID) -> AddExpensePreset {
        let kind: AddVehicleView.FixedPresetKind
        switch mirror.category {
        case .carLoan: kind = .carLoan
        case .tax: kind = .tax
        case .subscription: kind = .subscription
        }
        var preset = AddVehicleView.makeFixedPreset(for: kind, vehicleId: vehicleId)
        preset.recurrence = mirror.period == .yearly ? .yearly : .monthly
        return preset
    }
}
