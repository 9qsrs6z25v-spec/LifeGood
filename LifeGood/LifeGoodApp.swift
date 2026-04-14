import SwiftUI

@main
struct LifeGoodApp: App {
    @StateObject private var expenseStore = ExpenseStore()
    @StateObject private var financeStore = FinanceStore()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(expenseStore)
                .environmentObject(financeStore)
        }
    }
}
