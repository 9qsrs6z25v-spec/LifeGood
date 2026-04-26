import SwiftUI

@main
struct LifeGoodWatchApp: App {
    @StateObject private var store = WatchExpenseStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchAddExpenseView()
                    .environmentObject(store)
                    .onAppear { store.refreshFromCloud() }
            }
        }
    }
}
