import SwiftUI

// MARK: - 手錶 App 的根（手錶 v1，v25.574；watch/judge.md §2.0；watch/build/v1/brief.md G2-4）
//
// 只屬於 LifeGoodWatch。
//   • 頁：TabView(selection:)＋.verticalPage（watchOS 10 起），轉錶冠一頁一頁翻。v1：① 今天（第一頁，§13-5）、
//     ② 錢（iPhone 關掉「錢」整頁不出現，WatchModel.showsMoney）。每頁自己畫夜空底（.containerBackground(for: .tabView)）。
//   • 第二層：NavigationStack(path: model.path)＋navigationDestination(for: WatchRoute.self)
//     （今天全部、一件事的細節、接下來要繳）。最多兩層。
//   • 彈出頁：sheet(item: model.sheet)（① 左上「⋯」設定）。手錶沒有 AppStores，不用 .appStores()。
//   • 錶面小格點進來：onOpenURL → WatchModel.open（WidgetLink.parse，同一套網址）。
//   • scenePhase：WatchModel.scenePhaseChanged（進背景收回第一頁；回前景重讀包、太舊就跟 iPhone 要）。
// 字、遮不遮都不在這裡：每一頁自己讀 WatchModel、叫 WatchText。

struct RootView: View {
    @ObservedObject private var model = WatchModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $model.path) {
            pages
                .navigationDestination(for: WatchRoute.self) { route in
                    destination(route)
                }
        }
        .sheet(item: $model.sheet) { _ in
            SettingsSheet()
        }
        .onOpenURL { url in
            model.open(url)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.scenePhaseChanged(phase)
        }
    }

    /// 垂直翻頁的那幾頁（v1：① 今天、② 錢）
    private var pages: some View {
        TabView(selection: $model.selection) {
            TodayPage()
                .tag(WatchPage.today)
            if model.showsMoney {
                MoneyPage()
                    .tag(WatchPage.money)
            }
        }
        .tabViewStyle(.verticalPage)
    }

    /// 推進去的第二層
    @ViewBuilder
    private func destination(_ route: WatchRoute) -> some View {
        switch route {
        case .dayList:
            DayListView()
        case .stop(let id):
            StopDetailView(stopId: id)
        case .bills:
            BillsList()
        }
    }
}
