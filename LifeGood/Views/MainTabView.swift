import SwiftUI

struct MainTabView: View {
    @AppStorage("appMode") private var appMode: String = AppMode.expense.rawValue
    @State private var selectedTab = 0

    private var currentMode: AppMode {
        AppMode(rawValue: appMode) ?? .expense
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            if currentMode == .expense {
                expenseTabs
            } else {
                financeTabs
            }
        }
        .tint(.green)
        .onChange(of: appMode) { _, _ in
            selectedTab = 0
        }
    }

    // MARK: - 記帳模式

    @ViewBuilder
    private var expenseTabs: some View {
        OverviewView()
            .tabItem { Label("總覽", systemImage: "house.fill") }
            .tag(0)

        VariableExpenseView()
            .tabItem { Label("變動支出", systemImage: "arrow.up.arrow.down.circle.fill") }
            .tag(1)

        FixedExpenseView()
            .tabItem { Label("固定支出", systemImage: "pin.circle.fill") }
            .tag(2)

        ChartView()
            .tabItem { Label("圖表", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(3)

        SettingsView()
            .tabItem { Label("設定", systemImage: "gearshape.fill") }
            .tag(4)
    }

    // MARK: - 理財模式

    @ViewBuilder
    private var financeTabs: some View {
        FinanceOverviewView()
            .tabItem { Label("總覽", systemImage: "house.fill") }
            .tag(0)

        SavingsInsuranceView()
            .tabItem { Label("儲蓄險", systemImage: "shield.fill") }
            .tag(1)

        StockView()
            .tabItem { Label("股票", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(2)

        RealEstateView()
            .tabItem { Label("房地產", systemImage: "building.2.fill") }
            .tag(3)

        FinanceChartView()
            .tabItem { Label("圖表", systemImage: "chart.pie.fill") }
            .tag(4)

        SettingsView()
            .tabItem { Label("設定", systemImage: "gearshape.fill") }
            .tag(5)
    }
}

#Preview {
    MainTabView()
        .environmentObject(ExpenseStore())
        .environmentObject(FinanceStore())
}
