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

/// iPhone 設定頁「Apple Watch」段的開關（App Group 的 UserDefaults；WatchSettingsSection 與這裡同一組鍵）
enum WatchPhoneSettings {
    /// 送到手錶：錢（還能花、接下來要繳）。沒設定過＝開
    static let sendMoneyKey = "watch_send_money"
    /// 會議細節裡的部屬名字。沒設定過＝這支 iPhone 不是加入別人的共享就開（judge §6.6）
    static let showOwnerNamesKey = "watch_show_owner_names"

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
        }
        package.phoneHidesAmounts = WidgetHideAmounts.isOn
        package.showOwnerNames = showOwners
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
        return WatchMoney(generatedAt: s.generatedAt, dataDay: s.dataDay, month: s.month, days: days)
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
