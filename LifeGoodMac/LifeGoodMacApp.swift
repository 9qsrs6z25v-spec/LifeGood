// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] Mac App 進入點（brief.md §G2-1、judge_mac.md §O2-1、§F1、§F11）。
//
// • 單一 Window（不用 WindowGroup）：同一筆不會在兩個視窗同時編輯。
// • MacAppModel 持有全部 store；sheet、詳情、選單一律 .macStores(app)（Mac 沒有 AppStores／.appStores()）。
// • 重新整理只從這裡（啟動的下一個 runloop、60 秒計時器、iCloud 帳號換了）、MacShell 的 scenePhase、⌘R、⟳ 觸發；
//   不在 body、.task 裡寫 store。
// • [v25.645 mac5] 圖表頁 ⌘5（MacPage.shows：圖表頁支出 true）；記帳小鎮 MacGameModel（只存這台 Mac 的 mac.game.*）掛進 .macStores，
//   選單「顯示 › 遊戲元素」開關（judge_mac.md §S7-1）。
// • [v25.646 mac6] 誰還欠我頁 MacPage.owed（不綁 ⌘6；isOpen 由 G2 加）；記帳小鎮 MacGameModel 多收 MacJournal（只讀 kind、key、at）
//   （judge_mac.md §T7-2）。

import SwiftUI
import AppKit
import Combine
import CloudKit

@main
struct LifeGoodMacApp: App {
    @StateObject private var model = MacAppModel()

    var body: some Scene {
        Window("LifeGood", id: "main") {
            MacShell()
                .macStores(model)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            MacAppCommands(model: model, ui: model.ui, money: model.money, game: model.game)
            MacEditCommands(edit: model.edit, ui: model.ui)
        }
    }
}

// MARK: - 頁

enum MacPage: String, Hashable, CaseIterable {
    case overview, income, variable, fixed, chart, owed, source

    var title: String {
        switch self {
        case .overview: return "總覽"
        case .income: return "收入"
        case .variable: return "變動支出"
        case .fixed: return "固定支出"
        case .chart: return "圖表"
        case .owed: return "誰還欠我"
        case .source: return "資料來源"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .income: return "arrow.down.circle"
        case .variable: return "cart"
        case .fixed: return "calendar"
        case .chart: return "chart.pie"
        case .owed: return "person.2"
        case .source: return "icloud"
        }
    }

    /// 開放的頁（其他頁側欄反灰、標「下一版」、不能選）。[v25.641 mac2] 加收入；[v25.642 mac3] 加變動支出；[v25.644 mac4] 加固定支出；[v25.645 mac5] 加圖表
    var isOpen: Bool { self == .overview || self == .income || self == .variable || self == .fixed || self == .source || self == .chart }

    /// [v25.642 mac3] 這一頁有搜尋框（⌘F 反灰用）：收入、變動支出
    var hasSearch: Bool { self == .income || self == .variable }

    /// [v25.641 mac2] 視窗標題（總覽「收支總覽」；其他頁＝title）。總設計先放：G2 的 MacShell 用
    var navTitle: String {
        switch self {
        case .overview: return "收支總覽"
        default: return title
        }
    }

    /// [v25.641 mac2] 這一頁看得到這一筆嗎（存完自動選取、換頁清選取用；sim2: sel#4）。總設計先放：G1 用
    func shows(_ ref: MacEntryRef) -> Bool {
        switch self {
        case .overview:
            return true
        case .income:
            if case .income = ref { return true }
            return false
        case .variable:
            // [v25.642 mac3] 變動支出頁：支出 true、收入 false（sim3 page_shows）
            if case .expense = ref { return true }
            return false
        // [v25.644 mac4] 固定支出頁：支出 true（選到變動支出由 MacFixedSelectionGuard 清掉）、收入 false
        case .fixed:
            if case .expense = ref { return true }
            return false
        // [v25.645 mac5] 圖表頁：支出 true、收入 false（看門狗〔看一下〕不跳頁直接選）— sim5: page5#1
        case .chart:
            if case .expense = ref { return true }
            return false
        // [v25.646 mac6] 誰還欠我頁：支出 true、收入 false（詳情欄看那頓）— sim6: page6#1
        case .owed:
            if case .expense = ref { return true }
            return false
        case .source:
            return false
        }
    }
}

// MARK: - 畫面狀態（目前頁、選到哪一筆、詳情開不開）

@MainActor
final class MacUIState: ObservableObject {
    /// 目前頁記在這台（"mac.sidebar.selection"：mac. 開頭，只存這台；judge_mac.md §F1）
    @Published var page: MacPage = .overview {
        didSet {
            // sim2: sel#1 換頁清選取（上一頁選到的那筆這一頁不一定看得到）、搜尋框焦點跟著清
            if page != oldValue {
                UserDefaults.standard.set(page.rawValue, forKey: "mac.sidebar.selection")
                selection = nil
                searchFieldFocused = false
                // [v25.642 mac3] 換頁「搜全部月份」歸零（月份留著）
                variableSearchAll = false
            }
        }
    }
    @Published var selection: MacEntryRef? = nil
    @Published var showInspector: Bool = true
    /// [v25.641 mac2] ⌘F 每按一次 +1；收入頁 .onChange 看到就把焦點放進搜尋框（總設計先放：G1 選單寫、G2 頁面讀）
    @Published var searchRequest: Int = 0
    /// [v25.641 mac2] 搜尋框有焦點（收入頁 .onChange 寫）；有焦點時 ⌘E、⌘⌫ 反灰，⌘⌫ 留給文字框（G1 選單讀）
    @Published var searchFieldFocused: Bool = false
    /// [v25.642 mac3] 變動支出頁看哪個月：nil＝跟著本月（過午夜跨月自己跟上）；有值＝那個月 1 號 00:00。不存 UserDefaults
    @Published var variableMonth: Date? = nil
    /// [v25.642 mac3] 變動支出頁「搜全部月份」（有搜尋字才出現；搜尋字清空、換頁歸零）
    @Published var variableSearchAll: Bool = false

    init() {
        let raw = UserDefaults.standard.string(forKey: "mac.sidebar.selection") ?? ""
        let saved = MacPage(rawValue: raw) ?? .overview
        page = saved.isOpen ? saved : .overview
    }

    // MARK: [v25.642 mac3] 變動支出的月份（iPhone 變動頁沒有月份切換，這是電腦版自己的；judge_mac §Q8-2）

    /// sim3: month#1　下限＝最早那筆變動支出的月初；上限＝max(本月月初, 最晚那筆的月初)；沒有變動支出 → nil（三顆反灰）
    func variableMonthBounds(money: MacMoneyStore, now: Date, calendar: Calendar) -> (lower: Date, upper: Date)? {
        var earliest: Date? = nil
        var latest: Date? = nil
        for e in money.expenses where e.expenseType == .variable {
            if earliest.map({ d in e.date < d }) ?? true { earliest = e.date }
            if latest.map({ d in e.date > d }) ?? true { latest = e.date }
        }
        guard let first = earliest, let last = latest else { return nil }
        let lower = MacVariableMonth.start(of: first, calendar: calendar)
        let upper = max(MacVariableMonth.start(of: now, calendar: calendar), MacVariableMonth.start(of: last, calendar: calendar))
        return (lower, upper)
    }

    /// sim3: month#2　走 n 個月之後的 variableMonth：日曆算術、到界線不動（回原值）、走到本月＝nil
    func steppedVariableMonth(_ n: Int, money: MacMoneyStore, now: Date, calendar: Calendar) -> Date? {
        guard let bounds = variableMonthBounds(money: money, now: now, calendar: calendar) else { return variableMonth }
        let current = MacVariableMonth.start(of: now, calendar: calendar)
        let shown = variableMonth ?? current
        guard let moved = calendar.date(byAdding: .month, value: n, to: shown) else { return variableMonth }
        let target = MacVariableMonth.start(of: moved, calendar: calendar)
        if target < bounds.lower || target > bounds.upper { return variableMonth }
        return target == current ? nil : target
    }

    /// sim3: month#2　⌘[、⌘]、工具列〔‹〕〔›〕
    func stepVariableMonth(_ n: Int, money: MacMoneyStore, now: Date, calendar: Calendar) {
        let target = steppedVariableMonth(n, money: money, now: now, calendar: calendar)
        if target != variableMonth { variableMonth = target }
    }

    /// ⌘[、⌘] 反灰：不在變動支出頁、勾著搜全部月份、沒有變動支出、到界線
    func canStepVariableMonth(_ n: Int, money: MacMoneyStore, now: Date, calendar: Calendar) -> Bool {
        guard page == .variable, !variableSearchAll,
              variableMonthBounds(money: money, now: now, calendar: calendar) != nil else { return false }
        return steppedVariableMonth(n, money: money, now: now, calendar: calendar) != variableMonth
    }

    /// ⌘T 反灰：不在變動支出頁、勾著搜全部月份、沒有變動支出、已是本月
    func canReturnVariableMonth(money: MacMoneyStore, now: Date, calendar: Calendar) -> Bool {
        guard page == .variable, !variableSearchAll,
              variableMonthBounds(money: money, now: now, calendar: calendar) != nil,
              let m = variableMonth else { return false }
        return m != MacVariableMonth.start(of: now, calendar: calendar)
    }
}

// MARK: - App 模型

@MainActor
final class MacAppModel: ObservableObject {
    let money: MacMoneyStore
    let ui: MacUIState
    let journal: MacJournal
    let edit: MacEditCenter
    /// [v25.645 mac5] 記帳小鎮（不收 MacJournal、MacEditCenter）
    /// [v25.646 mac6] 多收 MacJournal（只讀 kind、key、at：第一次在電腦記帳那枚徽章）；仍不收 MacEditCenter
    let game: MacGameModel
    private var bag: Set<AnyCancellable> = []

    init() {
        let money = MacMoneyStore()
        let ui = MacUIState()
        let journal = MacJournal()
        self.money = money
        self.ui = ui
        self.journal = journal
        self.edit = MacEditCenter(money: money, journal: journal, ui: ui)
        // [v25.645 mac5] 一定在 [weak self] 閉包（下面的 Timer、CKAccountChanged）之前：stored property 要先都有值
        self.game = MacGameModel(money: money, journal: journal)
        // 60 秒：App 在前景才抓（judge_mac.md §O3-1：前景每 60 秒）
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.timerTick() }
            .store(in: &bag)
        // iCloud 帳號換了：清空再讀（換帳號的本機資料夾由 MacJournal 看 accountHash 處理）
        NotificationCenter.default.publisher(for: .CKAccountChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.accountDidChange() }
            .store(in: &bag)
        // 第一次讀放到下一個 runloop（不在 init、body 裡同步寫 store）
        DispatchQueue.main.async { Task { @MainActor in await self.money.refresh() } }
    }

    /// ⌘R、⟳、空白狀態的〔重新讀取〕
    func requestRefresh() {
        Task { await money.refresh() }
    }

    private func timerTick() {
        guard NSApplication.shared.isActive else { return }
        Task { await money.refresh() }
    }

    private func accountDidChange() {
        ui.selection = nil
        Task { await money.accountChanged() }
    }
}

// MARK: - 選單「顯示」

/// [v25.641 mac2] ⌘2 收入、⌘F 搜尋（只在收入頁）；系統「尋找」「拼字」那一組（.textEditing）整組拿掉，⌘F 不撞鍵
/// [v25.642 mac3] ⌘3 變動支出；⌘F 收入、變動支出兩頁；⌘[ ⌘] ⌘T 切月份（只在變動支出頁；⌥←／⌥→ 不綁，留給文字框跳字）
/// [v25.644 mac4] ⌘4 固定支出（全 Mac 只綁這一次）；這頁 ⌘F（hasSearch 不含）、⌘[ ⌘] ⌘T（不是變動支出頁）反灰
/// [v25.645 mac5] ⌘5 圖表（全 Mac 只綁這一次）；〔詳情〕上面「遊戲元素」開關（不綁快捷鍵）
@MainActor
struct MacAppCommands: Commands {
    let model: MacAppModel
    @ObservedObject var ui: MacUIState
    /// [v25.642 mac3] 月份上下限跟著帳本（資料到了選單反灰要跟著更新）
    @ObservedObject var money: MacMoneyStore
    /// [v25.645 mac5] 記帳小鎮開關（打勾跟著 enabled）
    @ObservedObject var game: MacGameModel

    var body: some Commands {
        CommandMenu("顯示") {
            Button("重新整理") { model.requestRefresh() }
                .keyboardShortcut("r")
            Divider()
            Button("總覽") { ui.page = .overview }
                .keyboardShortcut("1")
            Button("收入") { ui.page = .income }
                .keyboardShortcut("2")
                .disabled(!MacPage.income.isOpen)
            Button("變動支出") { ui.page = .variable }
                .keyboardShortcut("3")
                .disabled(!MacPage.variable.isOpen)
            // [v25.646 mac6] 誰還欠我（不綁鍵；isOpen 由 G2 加，之前反灰）
            Button("誰還欠我") { ui.page = .owed }
                .disabled(!MacPage.owed.isOpen)
            Button("固定支出") { ui.page = .fixed }
                .keyboardShortcut("4")
                .disabled(!MacPage.fixed.isOpen)
            Button("圖表") { ui.page = .chart }
                .keyboardShortcut("5")
                .disabled(!MacPage.chart.isOpen)
            Button("資料來源") { ui.page = .source }
            Divider()
            Button("搜尋") { ui.searchRequest += 1 }
                .keyboardShortcut("f")
                .disabled(!ui.page.hasSearch)
            Divider()
            Button("上個月") { ui.stepVariableMonth(-1, money: money, now: Date(), calendar: .current) }
                .keyboardShortcut("[")
                .disabled(!ui.canStepVariableMonth(-1, money: money, now: Date(), calendar: .current))
            Button("下個月") { ui.stepVariableMonth(1, money: money, now: Date(), calendar: .current) }
                .keyboardShortcut("]")
                .disabled(!ui.canStepVariableMonth(1, money: money, now: Date(), calendar: .current))
            Button("回到本月") { ui.variableMonth = nil }
                .keyboardShortcut("t")
                .disabled(!ui.canReturnVariableMonth(money: money, now: Date(), calendar: .current))
            Divider()
            Toggle("遊戲元素", isOn: Binding(get: { game.enabled }, set: { on in game.setEnabled(on) }))
            Divider()
            Button("詳情") { ui.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
        CommandGroup(replacing: .textEditing) { EmptyView() }
    }
}

// MARK: - 環境物件（取代 iOS 的 .appStores()）

extension View {
    /// 一次掛上 Mac 全部的 store。sheet 一律 sheet(item:)＋.macStores(app)
    @MainActor
    func macStores(_ app: MacAppModel) -> some View {
        self
            .environmentObject(app)
            .environmentObject(app.money)
            .environmentObject(app.ui)
            .environmentObject(app.journal)
            .environmentObject(app.edit)
            .environmentObject(app.game)
    }
}
