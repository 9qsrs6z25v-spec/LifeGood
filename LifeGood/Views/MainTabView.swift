import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewView()
                .tabItem {
                    Label("總覽", systemImage: "house.fill")
                }
                .tag(0)

            VariableExpenseView()
                .tabItem {
                    Label("變動支出", systemImage: "arrow.up.arrow.down.circle.fill")
                }
                .tag(1)

            FixedExpenseView()
                .tabItem {
                    Label("固定支出", systemImage: "pin.circle.fill")
                }
                .tag(2)

            ChartView()
                .tabItem {
                    Label("圖表", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .tint(.green)
    }
}

#Preview {
    MainTabView()
        .environmentObject(ExpenseStore())
}
