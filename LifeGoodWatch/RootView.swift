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
// [手錶 v2] v25.576：彈出頁多「記一筆」（RecordSheet）；第二層多「今天記的帳」（TodayRecordsView）、「手機條碼」（BarcodePage）。
// [手錶 v6] v25.578（watch/build/v6/brief.md §2）：頁多 ④ 旅行（TripPage）——旅途中排第一（④①②）、出發前 7 天排最後（①②④）、
//   其他時候沒有（WatchModel.tripKind）；第二層多「這一站」（TripStopDetail）、「天氣資料出處」（TripWeatherSourcePage）。
//   換時區的那一行由第一頁自己畫（TripPage／TodayPage，WatchTripText.timeZoneHint）。
// [手錶 v4] v25.580（watch/judge.md §2.0、§2.9～§2.12；watch/build/v4/brief.md §2）：
//   • 頁多 ③ 跑步（RunHomePage）：② 錢之後、出發前那一頁 ④ 之前；旅途中照樣 ④ 排第一（④①②③）。
//   • 跑步（WorkoutManager.phase 不是 idle：準備、倒數、跑步中、存檔中、不到 1 分鐘、摘要）整個畫面換成 RunFlowView——
//     不是彈出頁，跑步中打開 App、手腕放下再抬起來、當機接回都直接回到跑步那一頁（judge §2.0「正在跑步→跑步中」）。
//     彈出頁、錶面點進來、scenePhase 照舊掛在最外層。
// [手錶 v5] v25.582（watch/build/v5/brief.md §2）：第二層多「這週」（RunWeekView）、「那一趟」（RunDetailView）。

struct RootView: View {
    @ObservedObject private var model = WatchModel.shared
    /// [v4] 跑步中：整個畫面換成跑步
    @ObservedObject private var runs = WorkoutManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .sheet(item: $model.sheet) { sheet in
                sheetContent(sheet)
            }
            .onOpenURL { url in
                model.open(url)
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                model.scenePhaseChanged(phase)
            }
    }

    /// [v4] 跑步中（WorkoutManager.showsRunFlow）＝跑步那一頁；不然照舊（翻頁＋第二層）
    @ViewBuilder
    private var content: some View {
        if runs.showsRunFlow {
            RunFlowView()
        } else {
            NavigationStack(path: $model.path) {
                pages
                    .navigationDestination(for: WatchRoute.self) { route in
                        destination(route)
                    }
            }
        }
    }

    /// 垂直翻頁的那幾頁（v1：① 今天、② 錢；v6：旅途中 ④ 旅行排第一、出發前 7 天排最後；v4：② 之後 ③ 跑步）
    private var pages: some View {
        TabView(selection: $model.selection) {
            if model.tripKind == .during {
                TripPage()
                    .tag(WatchPage.trip)
            }
            TodayPage()
                .tag(WatchPage.today)
            if model.showsMoney {
                MoneyPage()
                    .tag(WatchPage.money)
            }
            RunHomePage()
                .tag(WatchPage.run)
            if model.tripKind == .upcoming {
                TripPage()
                    .tag(WatchPage.trip)
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
        case .todayRecords:
            TodayRecordsView()
        case .barcode:
            BarcodePage()
        case .tripStop(let id):
            TripStopDetail(stopId: id)
        case .weatherSource:
            TripWeatherSourcePage()
        case .runWeek:
            RunWeekView()
        case .runDetail(let id):
            RunDetailView(runId: id)
        }
    }

    /// 彈出頁（⋯ 設定、[v2] 記一筆）
    @ViewBuilder
    private func sheetContent(_ sheet: WatchSheet) -> some View {
        switch sheet {
        case .settings:
            SettingsSheet()
        case .record:
            RecordSheet()
        }
    }
}

/// [v4] 跑步那一頁：照 WorkoutManager.phase 換（準備 → 倒數 → 跑步中 → 存檔中／不到 1 分鐘／摘要）
private struct RunFlowView: View {
    @ObservedObject private var runs = WorkoutManager.shared

    var body: some View {
        switch runs.phase {
        case .idle:
            Color.black
        case .preparing:
            RunPrepView()
        case .countdown:
            RunCountdownView()
        case .running, .paused:
            RunSessionView()
        case .ending, .askShort, .summary:
            RunSummaryView()
        }
    }
}
