import Foundation
import EventKit

// MARK: - 某一天的全天的事（v25.545，只屬於主 App）
//
// 生日、結婚紀念日、兼任職務的重要日期與卸任日、里程碑、全日事件。
// 資料來源與判斷照「我的行事曆」MyCalendarView.eventsOn（同一組 id 前綴），
// 輸出共用檔的 WidgetAllDayItem，給「今天」小工具用。
//
// ⚠️ 規則同 MyCalendarView.eventsOn／annualOccurrence（MyCalendarView.swift:424-556），
//    改一邊要改另一邊。這一版刻意不動 MyCalendarView（2,700 多行、型別檢查敏感），
//    所以兩份是「同資料來源、同判斷」的平行寫法，不是同一支函式。
//    差別只有：這裡只收「全天的」（有時間的個人事件、系統行事曆事件在 TodayAgenda 的時間軸上）。
//    [健康 v7b] 我的行事曆多列那一天的運動（eventsOn 的 .workout，有開始時間、不是全天的事），這裡照規則不收；
//    「今天（大）」的運動另外一行（life 快照的 workout，WorkoutFacts.widgetWorkoutDays）。
//    [v25.565 財富 v4] 跟我的行事曆一起多收財富的日子（WealthDates.items(on:facts:)，Models/WealthReminders.swift）：
//    卡費截止／扣款（每張卡接下來 2 期）、交割、卡片到期，kind .wealth（priority 同里程碑）。
//    **主畫面不寫金額**（widgetTitle「CUBE 卡費截止」「元大證券 交割」），鎖定畫面／StandBy 只寫類別字（lockTitle「卡費」「交割」
//    「卡片到期」；judge §7.1）；財富帳戶的開戶日也改 kind .wealth、lockTitle「財富」（不當里程碑）。不送 Apple 行事曆。
//    規則同 MyCalendarView.eventsOn 的財富那兩段，改一邊改另一邊。
//
// 規格見 scratchpad/widgets/v1/brief.md 的 G1。

/// @MainActor：AppleCalendarBridge 是 @MainActor（AppleCalendarBridge.swift:8）
@MainActor
enum CalendarDayItems {

    /// 那一天的全天的事，已依 WidgetAllDayKind.priority 排好（同優先序保持原本順序）。
    /// 原本順序＝eventsOn 收集的順序：家人（生日、結婚紀念日）→ 里程碑 → [財富 v4] 財富的日子 → 兼任職務 → 系統行事曆 → 個人事件。
    static func allDay(on day: Date, store: LifeStore, calendar cal: Calendar = .current) -> [WidgetAllDayItem] {
        var items: [WidgetAllDayItem] = []
        let year = cal.component(.year, from: day)

        // 家庭生日（每年同一天）、配偶的結婚紀念日
        for member in store.familyMembers {
            if let item = birthdayItem(member, on: day, year: year, calendar: cal) {
                items.append(item)
            }
            if let item = anniversaryItem(member, on: day, year: year, calendar: cal) {
                items.append(item)
            }
        }

        // 人生里程碑（精準日期）
        for ms in store.milestones where cal.isDate(ms.date, inSameDayAs: day) {
            let raw = ms.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if WealthDates.isWealthAccount(ms) {
                // [財富 v4] 財富帳戶的開戶日／核卡日：照舊列（第 9 題），但當「財富」不當里程碑；鎖定畫面只寫「財富」。
                // 圖示照子分類（跟我的行事曆那一列同一個：creditcard.fill、building.columns.fill…）
                let wealthTitle = raw.isEmpty ? "財富" : ms.title
                let wealthIcon: String = ms.financeSubCategory?.icon ?? "banknote.fill"
                items.append(WidgetAllDayItem(id: "ms-\(ms.id.uuidString)",
                                              kind: .wealth,
                                              title: wealthTitle,
                                              shortTitle: wealthTitle,
                                              lockTitle: "財富",
                                              icon: wealthIcon))
                continue
            }
            // 我的行事曆照樣寫 ms.title；這裡多一層：標題空白時退到分類，膠囊才不會是空的
            let title = raw.isEmpty ? ms.category.rawValue : ms.title
            items.append(WidgetAllDayItem(id: "ms-\(ms.id.uuidString)",
                                          kind: .milestone,
                                          title: title,
                                          shortTitle: title,
                                          lockTitle: "里程碑",
                                          icon: "flag.fill"))
        }

        // [財富 v4] 財富的日子：卡費截止／扣款（每張卡 2 期）、交割、卡片到期（WealthDates，只讀 wealthFacts 那一份）。
        // 主畫面寫 widgetTitle（卡名＋類別，**不寫金額**）；鎖定畫面／StandBy 寫 lockTitle（類別字）
        items.append(contentsOf: wealthItems(on: day, store: store))

        // 兼任職務的「重要日期」（尾牙的場勘日、彩排日等）與卸任日
        items.append(contentsOf: sideRoleItems(on: day, store: store, calendar: cal))

        // Apple 系統行事曆的全日事件 — 排除已從 LifeGood 同步出去的事件，避免重複
        items.append(contentsOf: appleAllDayItems(on: day, store: store, calendar: cal))

        // 個人行事曆事件裡的全日事件（durationMinutes == 0，含重複展開）
        let dayStamp = cal.startOfDay(for: day).timeIntervalSince1970
        for pe in store.personalEvents where pe.occurs(on: day, calendar: cal) {
            guard pe.durationMinutes == 0 else { continue }   // 有時間的在 TodayAgenda 的軸上
            let title = pe.title.isEmpty ? pe.kind.rawValue : pe.title
            items.append(WidgetAllDayItem(id: "pe-\(pe.id.uuidString)-\(dayStamp)",
                                          kind: .personal,
                                          title: title,
                                          shortTitle: title,
                                          lockTitle: pe.kind.rawValue,
                                          icon: "calendar"))
        }

        return ranked(items)
    }

    /// 那一天生日的家人（照 familyMembers 的順序）。手寫問候「Happy birthday, …!」也用這支，
    /// 跟 allDay 的生日同一個判斷。
    static func birthdayMembers(on day: Date, store: LifeStore,
                                calendar cal: Calendar = .current) -> [FamilyMember] {
        let year = cal.component(.year, from: day)
        return store.familyMembers.filter { member in
            guard let bd = member.birthday else { return false }
            let occ = annualOccurrence(of: bd, year: year, calendar: cal)
            return cal.isDate(occ, inSameDayAs: day)
        }
    }

    // MARK: - 各種

    private static func birthdayItem(_ member: FamilyMember, on day: Date, year: Int,
                                     calendar cal: Calendar) -> WidgetAllDayItem? {
        guard let bd = member.birthday else { return nil }
        let occ = annualOccurrence(of: bd, year: year, calendar: cal)
        guard cal.isDate(occ, inSameDayAs: day) else { return nil }
        let name = displayName(member)
        let age = year - cal.component(.year, from: bd)
        let title = age > 0 ? "\(name) \(age) 歲生日" : "\(name) 生日"
        return WidgetAllDayItem(id: "bd-\(member.id.uuidString)",
                                kind: .birthday,
                                title: title,
                                shortTitle: name + "生日",
                                lockTitle: "家人生日",
                                icon: "birthday.cake.fill")
    }

    private static func anniversaryItem(_ member: FamilyMember, on day: Date, year: Int,
                                        calendar cal: Calendar) -> WidgetAllDayItem? {
        guard member.role == .spouse, let md = member.marriageDate else { return nil }
        let occ = annualOccurrence(of: md, year: year, calendar: cal)
        guard cal.isDate(occ, inSameDayAs: day) else { return nil }
        let years = year - cal.component(.year, from: md)
        return WidgetAllDayItem(id: "anniv-\(member.id.uuidString)",
                                kind: .anniversary,
                                title: years > 0 ? "結婚 \(years) 週年" : "結婚紀念日",
                                shortTitle: "結婚紀念日",
                                lockTitle: "結婚紀念日",
                                icon: "heart.fill")
    }

    private static func sideRoleItems(on day: Date, store: LifeStore,
                                      calendar cal: Calendar) -> [WidgetAllDayItem] {
        var out: [WidgetAllDayItem] = []
        for role in store.sideRoles {
            let roleName = SideRoleFormat.displayName(role)
            for kd in role.sideRoleKeyDates ?? [] where cal.isDate(kd.date, inSameDayAs: day) {
                let title = kd.title.isEmpty ? roleName : "\(roleName)：\(kd.title)"
                out.append(WidgetAllDayItem(id: "srkd-\(kd.id.uuidString)",
                                            kind: .sideRole,
                                            title: title,
                                            shortTitle: title,
                                            lockTitle: "兼任職務",
                                            icon: "flag.fill"))
            }
            if let end = role.sideRoleEndDate, cal.isDate(end, inSameDayAs: day) {
                let title = "\(roleName) 卸任"
                out.append(WidgetAllDayItem(id: "srend-\(role.id.uuidString)",
                                            kind: .sideRole,
                                            title: title,
                                            shortTitle: title,
                                            lockTitle: "兼任職務",
                                            icon: "flag.fill"))
            }
        }
        return out
    }

    /// [財富 v4] 那一天的財富日子（同 MyCalendarView.eventsOn 的財富那段；記帳、理財用 AppStores 那一份）
    private static func wealthItems(on day: Date, store: LifeStore) -> [WidgetAllDayItem] {
        let facts = store.wealthFacts(expense: AppStores.expense, finance: AppStores.finance)
        var out: [WidgetAllDayItem] = []
        for w in WealthDates.items(on: day, facts: facts) {
            out.append(WidgetAllDayItem(id: w.id,
                                        kind: .wealth,
                                        title: w.widgetTitle,
                                        shortTitle: w.widgetTitle,
                                        lockTitle: w.lockTitle,
                                        icon: w.icon))
        }
        return out
    }

    private static func appleAllDayItems(on day: Date, store: LifeStore,
                                         calendar cal: Calendar) -> [WidgetAllDayItem] {
        let appleCal = AppleCalendarBridge.shared
        guard appleCal.hasAccess else { return [] }
        let syncedIds = Set(store.personalEvents.compactMap { $0.ekEventIdentifier })
        let fallbackStart = cal.startOfDay(for: day)
        var out: [WidgetAllDayItem] = []
        for ev in appleCal.events(forDay: day, calendar: cal)
        where !syncedIds.contains(ev.eventIdentifier) {
            guard ev.isAllDay else { continue }   // 有時間的在 TodayAgenda 的軸上
            let start: Date = ev.startDate ?? fallbackStart
            let raw = ev.title ?? ""
            let title = raw.isEmpty ? "(無標題)" : raw
            out.append(WidgetAllDayItem(id: "ek-\(ev.calendarItemIdentifier)-\(start.timeIntervalSince1970)",
                                        kind: .appleCalendar,
                                        title: title,
                                        shortTitle: title,
                                        lockTitle: TimelineStopKind.appleCalendar.label,
                                        icon: "calendar"))
        }
        return out
    }

    // MARK: - 小工具

    /// 依 priority 排、同優先序保持原本位置（Swift 的 sort 不保證穩定，所以把位置也拿來比）
    private static func ranked(_ items: [WidgetAllDayItem]) -> [WidgetAllDayItem] {
        let indexed = Array(items.enumerated())
        let sorted = indexed.sorted { a, b in
            let pa = a.element.kind.priority
            let pb = b.element.kind.priority
            if pa != pb { return pa < pb }
            return a.offset < b.offset
        }
        return sorted.map { $0.element }
    }

    /// 我的行事曆寫 member.chineseName；空白的話退到角色（「媽媽」），不要出現「 62 歲生日」
    /// [v5] 拿掉 private：life 快照的倒數（WidgetLifeExtras.countdowns）用同一支
    static func displayName(_ member: FamilyMember) -> String {
        let n = member.chineseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? member.role.rawValue : n
    }

    /// 將生日／紀念日的「年份」對齊到當年（照抄 MyCalendarView.annualOccurrence）。
    /// Calendar.date(from:) 對不存在的日期（如非閏年 2/29）不回傳 nil，而是溢位到下個月（3/1），
    /// 所以先把 day 截到該年該月實際天數：2/29 在平年對到 2/28。
    /// [v5] 拿掉 private：部屬今天的生日、倒數的下一次（WidgetLifeExtras）用同一支，規則只有一份
    static func annualOccurrence(of date: Date, year: Int, calendar cal: Calendar) -> Date {
        var comp = cal.dateComponents([.month, .day], from: date)
        comp.year = year
        if let month = comp.month, let day = comp.day {
            let refDate = cal.date(from: DateComponents(year: year, month: month, day: 1)) ?? date
            let maxDay = cal.range(of: .day, in: .month, for: refDate)?.count ?? day
            if day > maxDay { comp.day = maxDay }
        }
        return cal.date(from: comp) ?? date
    }
}
