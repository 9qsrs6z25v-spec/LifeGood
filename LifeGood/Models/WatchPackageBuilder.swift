import Foundation

// MARK: - 組手錶包（手錶 v1，v25.574；只屬於主 App；watch/judge.md §5.2、§6.2、§1.4-5；watch/build/v1/brief.md §2）
//
// **只讀檔案**：iPhone App Group 裡現成的小工具快照（life_v1.json、money_v1.json、bills_v1.json）＋
// 手錶附加資料快取（watch_extras_v1.json，WatchExtrasWriter）＋App Group 的設定。
// 不碰 AppStores／ExpenseStore／FinanceStore／LifeStore、不算任何數字——App 開著時、被手錶叫醒的冷啟動時，
// 組出來的都是同一包（judge §5.4、§7.8-6）。一律讀**最新的那幾份**，不只用「這次剛算的」（§1.4-5）。
//
// ⚠️ 白名單（judge §6.2-1）：外層一律用 WatchPackage.swift 的型別、一欄一欄抄。這裡**不准**放進：
//    任何號碼、CardVault.open、存摺數字、淨資產、收入（incomeText、會領回的帳單）、部屬請假與名單（team）、
//    廠區、家人倒數（countdowns）、家庭待辦內容、運動那一行、車子卡與車子選單、finance_v1.json 整份。
//    消毒規則跟 scratchpad/watch/build/v1/sim_v1.py 的 build_package 一模一樣（改了兩邊一起改）：
//    • 每天的 greeting 清空（中型小工具手寫問候會寫家人的英文名字）
//    • 財富全天（卡費截止、交割…）的 title／shortTitle 換 lockTitle（「卡費」）
//    • 部屬會議 stop.owner：「會議細節裡的部屬名字」關著＝""（連送都不送）
//    • 每天的 incomeText＝nil
//    • 帳單：會領回的（isIncome）整列不放；財富（卡費、交割）title＝lockedTitle、amountText＝""、detail＝nil；
//      每一列 link＝""；卡費自己繳（needsAction）看快取的 manualCardBillKeys
//    • 「送到手錶：錢」關著：money、bills 都不放
//
// [手錶 v2] v25.576（watch/judge.md §2.6～§2.8、§5.2；watch/build/v2/brief.md §2；sim_v2.py 的 build_package_v2）：
//    • money 多記帳台：templates → WatchTemplate、categories → WatchCategory（一欄一欄抄）、topCategoryKeys；
//      手錶上不給的分類（WatchCategoryRule：股票、房地產、稅費、節稅）三樣都拿掉
//    • recentAmounts、titleHints、todayRecords 從快取抄（「錢」關著不放：手錶上不能記帳、沒有今天記的帳）
//    • includedIds（快取）、queuedIds（收件匣資料夾的檔，QuickRecordInbox.watchIds）：「錢」關著也放（手錶待送盒收尾要用）
//    • carrierBarcode：iPhone 設定「手機條碼」打開、而且格式對（「/」＋7 碼 0-9 A-Z . + -）才放；
//      只讀 UserDefaults 的手機條碼那一個鍵，**驗證碼在鑰匙圈，這裡碰都不碰**
//
// [手錶 v6] v25.578（watch/judge.md §2.14、§2.16、§5.2、§6.3；watch/build/v6/brief.md §2；sim_v6.py 的 build_package_v6）：
//    • timeZoneId：快取裡 App 寫快照那一刻的時區（不是組包這一刻的：冷啟動時 iPhone 可能已經換了時區、快照還是舊的）
//    • tripToday／tripTomorrow：快取原樣抄（WatchExtrasWriter 已經只放白名單那幾欄）；iPhone 設定「旅行」關掉時不放，
//      而且 life.trips 也拿掉（手錶上沒有旅行那一頁、也不寫出發倒數）。「錢」關掉不影響旅行（記外幣跟著「錢」走，在手錶那邊擋）
//
// [手錶 v4] v25.580（watch/judge.md §2.9、§5.7；watch/build/v4/brief.md §2；sim_v4.py 的 build_package_v4）：
//    • runWeek：快取原樣抄（WatchRunWeekBuilder 已經只放數字與 Apple 健康編號）。沒有開關（不是隱私資料：公里、次數、天數，
//      judge §6.1「跑步距離、時間、次數、連續週數」可以上鎖定畫面）
//
// [手錶 v7b] v25.584（watch/judge.md §3.2、§2.16、§6.1、§6.3；watch/build/v7b/brief.md §2；sim_v7b.py 的 build_cards）：
//    • relevanceCards（智慧型堆疊卡）：設定「智慧型堆疊卡」總開關打開才放（沒設定過＝開）；關掉＝nil（手錶不浮任何卡、
//      你自己加的「下一場」「已花」「這週跑步」也不自己往上排）。卡**從這一包已經消毒過的欄位組**（WatchRelevancePlan.cards：
//      life 的部屬名字照設定清掉、財富只剩類別字；bills 卡費沒有金額卡名；旅行照「旅行」開關）——所以一定放在最後組。
//      每一種卡各自一個開關（WatchPhoneSettings.stackKinds）；「平常跑步的時間」打開才帶快取的 runSlots（只有時段與時段名）

/// iPhone 設定頁「Apple Watch」段的開關（App Group 的 UserDefaults；WatchSettingsSection 與這裡同一組鍵）
enum WatchPhoneSettings {
    /// 送到手錶：錢（還能花、接下來要繳）。沒設定過＝開
    static let sendMoneyKey = "watch_send_money"
    /// 會議細節裡的部屬名字。沒設定過＝這支 iPhone 不是加入別人的共享就開（judge §6.6）
    static let showOwnerNamesKey = "watch_show_owner_names"
    /// [v2] 手機條碼送到手錶。沒設定過＝關（judge §2.8、§6.3）
    static let sendBarcodeKey = "watch_send_barcode"
    /// [v6] 送到手錶：旅行（出發前 7 天到回來那天：下一站、打卡、記外幣、天氣）。沒設定過＝開
    static let sendTripKey = "watch_send_trip"
    /// [v7b] 智慧型堆疊卡總開關（五種卡＋「下一場」「已花」「這週跑步」自己往上排）。沒設定過＝開。
    /// 每一種卡各自的鍵是 WatchRelevanceKind.settingsKey（「watch_stack_morning」…，沒設定過＝開）
    static let stackCardsKey = "watch_stack_cards"
    /// [v2] 手機條碼存在哪（**App 自己的** UserDefaults.standard；＝EInvoiceSyncManager.cardNoKey，那邊是 private，
    /// 改了兩邊一起改，pkg_keys_check E 段核對）。驗證碼在鑰匙圈，這裡不碰
    static let carrierCardNoKey = "einvoice_card_no"

    static var sendMoney: Bool {
        guard let d = WidgetShared.defaults, d.object(forKey: sendMoneyKey) != nil else { return true }
        return d.bool(forKey: sendMoneyKey)
    }

    static func showOwnerNames(isShareParticipant: Bool) -> Bool {
        guard let d = WidgetShared.defaults, d.object(forKey: showOwnerNamesKey) != nil else { return !isShareParticipant }
        return d.bool(forKey: showOwnerNamesKey)
    }

    static func setSendMoney(_ on: Bool) {
        WidgetShared.defaults?.set(on, forKey: sendMoneyKey)
    }

    static func setShowOwnerNames(_ on: Bool) {
        WidgetShared.defaults?.set(on, forKey: showOwnerNamesKey)
    }

    /// [v6] 旅行送不送（沒設定過＝送）
    static var sendTrip: Bool {
        guard let d = WidgetShared.defaults, d.object(forKey: sendTripKey) != nil else { return true }
        return d.bool(forKey: sendTripKey)
    }

    /// [v7b] 智慧型堆疊卡總開關（沒設定過＝開）
    static var stackCards: Bool {
        guard let d = WidgetShared.defaults, d.object(forKey: stackCardsKey) != nil else { return true }
        return d.bool(forKey: stackCardsKey)
    }

    /// [v7b] 打開的那幾種卡（每一種沒設定過＝開；總開關另外看 stackCards）
    static var stackKinds: Set<WatchRelevanceKind> {
        var out = Set<WatchRelevanceKind>()
        for kind in WatchRelevanceKind.allCases {
            if let d = WidgetShared.defaults, d.object(forKey: kind.settingsKey) != nil, !d.bool(forKey: kind.settingsKey) {
                continue
            }
            out.insert(kind)
        }
        return out
    }

    /// [v2] 手機條碼送不送（沒設定過＝不送）
    static var sendBarcode: Bool {
        WidgetShared.defaults?.bool(forKey: sendBarcodeKey) ?? false
    }

    /// [v2] 已經連結的手機條碼（格式不對、沒連結是 nil）
    static var carrierBarcode: String? {
        guard let raw = UserDefaults.standard.string(forKey: carrierCardNoKey) else { return nil }
        return validBarcode(raw)
    }

    /// [v2] 手機條碼格式：「/」開頭＋7 碼，每碼是 0-9、A-Z、「.」「+」「-」（都是 Code 39 有的字）。
    /// 先去頭尾空白、轉大寫；不對回 nil（不送，手錶上就沒有 🧾）
    static func validBarcode(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let chars = Array(text)
        guard chars.count == 8, chars[0] == "/" else { return nil }
        let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.+-")
        for c in chars.dropFirst() where !allowed.contains(c) {
            return nil
        }
        return text
    }
}

enum WatchPackageBuilder {

    /// 讀 App Group 的檔組一包。三份小工具快照一份都沒有（iPhone 的 LifeGood 從來沒打開過新版）回 nil
    static func build(now: Date) -> WatchPackage? {
        let life = WidgetSnapshotStore.read(WidgetLifeSnapshot.self)
        let money = WidgetSnapshotStore.read(WidgetMoneySnapshot.self)
        let bills = WidgetSnapshotStore.read(WidgetBillsSnapshot.self)
        guard life != nil || money != nil || bills != nil else { return nil }
        let extras = WidgetSnapshotStore.read(WatchExtrasCache.self)
        let showOwners = WatchPhoneSettings.showOwnerNames(isShareParticipant: extras?.isShareParticipant ?? false)
        let sendMoney = WatchPhoneSettings.sendMoney
        let manual = Set(extras?.manualCardBillKeys ?? [])

        var package = WatchPackage(generatedAt: now)
        package.life = life.map { watchLife($0, showOwnerNames: showOwners) }
        if sendMoney {
            package.money = money.map { watchMoney($0) }
            package.bills = bills.map { watchBills($0, manualKeys: manual) }
            // [v2] 記一筆、今天記的帳（「錢」關著＝手錶上不能記帳，這三樣都不放）
            package.recentAmounts = extras?.recentAmounts
            package.titleHints = extras?.titleHints
            package.todayRecords = extras?.todayRecords
        }
        package.phoneHidesAmounts = WidgetHideAmounts.isOn
        package.showOwnerNames = showOwners
        // [v2] 待送盒收尾要的兩張名單（只有編號）
        package.includedIds = extras?.includedIds
        package.queuedIds = QuickRecordInbox.watchIds()
        // [v2] 手機條碼：設定打開才送（預設關）
        package.carrierBarcode = WatchPhoneSettings.sendBarcode ? WatchPhoneSettings.carrierBarcode : nil
        // [v6] 每一天的起訖是用哪個時區算的（App 寫快照那一刻的；手錶看它決定要不要寫「換時區了」）
        package.timeZoneId = extras?.timeZoneId
        // [v6] 旅行：設定打開才送；關掉時出發倒數（life.trips）也拿掉
        if WatchPhoneSettings.sendTrip {
            package.tripToday = extras?.tripToday
            package.tripTomorrow = extras?.tripTomorrow
        } else {
            package.life?.trips = nil
        }
        // [v4] 這週跑步（數字與 Apple 健康編號；③ 跑步、手錶自己記的那幾趟要不要自己加看 seen）
        package.runWeek = extras?.runWeek
        // [v7b] 智慧型堆疊卡：一定最後組（從上面已經消毒過的 package 欄位組；總開關關掉＝nil）
        if WatchPhoneSettings.stackCards {
            let kinds = WatchPhoneSettings.stackKinds
            let slots = kinds.contains(.usualRun) ? (extras?.runSlots ?? []) : []
            package.relevanceCards = WatchRelevanceCards(cards: WatchRelevancePlan.cards(package: package, kinds: kinds),
                                                         runSlots: slots)
        }
        return package
    }

    // MARK: 今天

    static func watchLife(_ s: WidgetLifeSnapshot, showOwnerNames: Bool) -> WatchLife {
        var due: [String: Int] = [:]
        for f in s.familyTasks ?? [] {
            due[f.dayKey] = f.dueTodayCount
        }
        return WatchLife(generatedAt: s.generatedAt,
                         dataDay: s.dataDay,
                         validUntil: s.validUntil,
                         days: s.days.map { watchDay($0, showOwnerNames: showOwnerNames) },
                         trips: s.trips,
                         familyDue: due)
    }

    static func watchDay(_ d: WidgetLifeDay, showOwnerNames: Bool) -> WidgetLifeDay {
        var out = d
        out.greeting = []
        out.stops = d.stops.map { watchStop($0, showOwnerNames: showOwnerNames) }
        out.allDay = d.allDay.map { watchAllDay($0) }
        out.nextDayFirstStop = d.nextDayFirstStop.map { watchStop($0, showOwnerNames: showOwnerNames) }
        out.nextDayFirstStops = d.nextDayFirstStops.map { list in
            list.map { watchStop($0, showOwnerNames: showOwnerNames) }
        }
        return out
    }

    /// 部屬會議的部屬名字：關著就不送
    static func watchStop(_ s: WidgetStop, showOwnerNames: Bool) -> WidgetStop {
        guard s.stop.kind == .meeting, !showOwnerNames else { return s }
        var out = s
        out.stop.owner = ""
        return out
    }

    /// 財富全天（「CUBE 卡費截止」）只留類別字（「卡費」）
    static func watchAllDay(_ item: WidgetAllDayItem) -> WidgetAllDayItem {
        guard item.kind == .wealth else { return item }
        var out = item
        out.title = item.lockTitle
        out.shortTitle = item.lockTitle
        return out
    }

    // MARK: 錢

    static func watchMoney(_ s: WidgetMoneySnapshot) -> WatchMoney {
        let days: [WidgetMoneyDay] = s.days.map { d in
            var out = d
            out.incomeText = nil
            return out
        }
        var m = WatchMoney(generatedAt: s.generatedAt, dataDay: s.dataDay, month: s.month, days: days)
        // [v2] 記帳台：一欄一欄抄，手錶上不給的分類拿掉
        m.templates = s.templates.map { list in
            list.filter { WatchCategoryRule.isAllowed($0.categoryKey) }.map { watchTemplate($0) }
        }
        m.topCategoryKeys = s.topCategoryKeys.map { keys in
            keys.filter { WatchCategoryRule.isAllowed($0) }
        }
        m.categories = s.categories.map { list in
            list.filter { WatchCategoryRule.isAllowed($0.key) }.map { watchCategory($0) }
        }
        return m
    }

    /// [v2] 一按就記的範本：沒有 top／bottom 漸層、沒有次數（手錶只要分類色）
    static func watchTemplate(_ t: WidgetQuickTemplate) -> WatchTemplate {
        WatchTemplate(id: t.id, title: t.title, amount: t.amount, amountText: t.amountText,
                      categoryKey: t.categoryKey, vehicleId: t.vehicleId, vehicleCategoryKey: t.vehicleCategoryKey,
                      icon: t.icon, tint: t.tint)
    }

    /// [v2] 分類：名稱、圖示、分類色
    static func watchCategory(_ c: WidgetCategory) -> WatchCategory {
        WatchCategory(key: c.key, title: c.title, icon: c.icon, tint: c.tint)
    }

    // MARK: 要繳

    static func watchBills(_ s: WidgetBillsSnapshot, manualKeys: Set<String>) -> [WatchBill] {
        var out: [WatchBill] = []
        for b in s.items where !b.isIncome {
            var bill = b
            bill.link = ""
            if b.kind.isWealth {
                bill.title = b.lockedTitle
                bill.amountText = ""
                bill.detail = nil
            }
            let needs = b.kind == .cardBill && manualKeys.contains(sourceKey(b.id))
            out.append(WatchBill(bill: bill, needsAction: needs))
        }
        return out
    }

    /// 帳單 id「<來源 id>@<yyyy-MM-dd>」的來源那一段（卡費「c-<卡 UUID>-<期>」，WidgetBillsBuilder／FinanceUpcoming）
    static func sourceKey(_ billId: String) -> String {
        guard let at = billId.firstIndex(of: "@") else { return billId }
        return String(billId[..<at])
    }
}
