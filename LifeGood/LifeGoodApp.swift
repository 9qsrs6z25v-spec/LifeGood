import SwiftUI

@main
struct LifeGoodApp: App {
    @StateObject private var expenseStore = ExpenseStore()
    @StateObject private var financeStore = FinanceStore()
    @StateObject private var lifeStore = LifeStore()
    @StateObject private var cloudSync = CloudSyncManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(expenseStore)
                .environmentObject(financeStore)
                .environmentObject(lifeStore)
                .environmentObject(cloudSync)
                .onAppear {
                    BackupManager.shared.createSnapshotIfNeeded(
                        expense: expenseStore, finance: financeStore, life: lifeStore
                    )
                    cloudSync.syncNow()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        BackupManager.shared.createSnapshotIfNeeded(
                            expense: expenseStore, finance: financeStore, life: lifeStore
                        )
                    } else if phase == .active {
                        cloudSync.syncNow()
                    }
                }
        }
    }
}
