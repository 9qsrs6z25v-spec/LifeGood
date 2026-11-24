// 只編進 LifeGoodMac；只寫白名單鍵、寫前重抓、條件寫入
// [v25.640 mac1] Mac App 進入點（brief.md §G2-1、judge_mac.md §O2-1、§F1、§F11）。
//
// • 單一 Window（不用 WindowGroup）：同一筆不會在兩個視窗同時編輯。
// • MacAppModel 持有全部 store；sheet、詳情、選單一律 .macStores(app)（Mac 沒有 AppStores／.appStores()）。
// • 重新整理只從這裡（啟動的下一個 runloop、60 秒計時器、iCloud 帳號換了）、MacShell 的 scenePhase、⌘R、⟳ 觸發；
//   不在 body、.task 裡寫 store。

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
            MacAppCommands(model: model, ui: model.ui)
            MacEditCommands(edit: model.edit, ui: model.ui)
        }
    }
}

// MARK: - 頁

enum MacPage: String, Hashable, CaseIterable {
    case overview, income, variable, fixed, chart, source

    var title: String {
        switch self {
        case .overview: return "總覽"
        case .income: return "收入"
        case .variable: return "變動支出"
        case .fixed: return "固定支出"
        case .chart: return "圖表"
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
        case .source: return "icloud"
        }
    }

    /// 開放的頁（其他頁側欄反灰、標「下一版」、不能選）。[v25.641 mac2] 加收入
    var isOpen: Bool { self == .overview || self == .income || self == .source }

    /// [v25.642 mac3] 這一頁有搜尋框（⌘F 反灰用）。總設計先放：G2 改成含 .variable
    var hasSearch: Bool { self == .income }

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
        case .variable, .fixed, .chart, .source:
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
            }
        }
    }
    @Published var selection: MacEntryRef? = nil
    @Published var showInspector: Bool = true
    /// [v25.641 mac2] ⌘F 每按一次 +1；收入頁 .onChange 看到就把焦點放進搜尋框（總設計先放：G1 選單寫、G2 頁面讀）
    @Published var searchRequest: Int = 0
    /// [v25.641 mac2] 搜尋框有焦點（收入頁 .onChange 寫）；有焦點時 ⌘E、⌘⌫ 反灰，⌘⌫ 留給文字框（G1 選單讀）
    @Published var searchFieldFocused: Bool = false

    init() {
        let raw = UserDefaults.standard.string(forKey: "mac.sidebar.selection") ?? ""
        let saved = MacPage(rawValue: raw) ?? .overview
        page = saved.isOpen ? saved : .overview
    }
}

// MARK: - App 模型

@MainActor
final class MacAppModel: ObservableObject {
    let money: MacMoneyStore
    let ui: MacUIState
    let journal: MacJournal
    let edit: MacEditCenter
    private var bag: Set<AnyCancellable> = []

    init() {
        let money = MacMoneyStore()
        let ui = MacUIState()
        let journal = MacJournal()
        self.money = money
        self.ui = ui
        self.journal = journal
        self.edit = MacEditCenter(money: money, journal: journal, ui: ui)
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
@MainActor
struct MacAppCommands: Commands {
    let model: MacAppModel
    @ObservedObject var ui: MacUIState

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
            Button("資料來源") { ui.page = .source }
            Divider()
            Button("搜尋") { ui.searchRequest += 1 }
                .keyboardShortcut("f")
                .disabled(ui.page != .income)
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
    }
}
