import SwiftUI

// MARK: - [v25.597 轉組織 v4] 接收清單（轉進來那張交接單；judge §3.7、§7 v4；orgmove/build/v4/brief.md G2-4）
//
// 主控放的骨架（已登記 project.pbxproj，只進 App target）；G2 照 brief 填內容。
// 規則與字都在 OrgMoveTemp.swift（intakeUnownedEquipment／parseIntakeText／intakeOneOnOneSlot…），寫入只叫 LifeStore：
// addOrgMoveIntakeItems／claimOrgMoveIntakeEquipment／addOrgMoveIntakeOneOnOne／removeOrgMoveIntakeLine（都要訂閱；
// sheet 關掉之後寫 store 放到下一個 runloop）。

/// 轉進來那張單的接收清單（OrgMoveSheetView 在 move.isIntake 時放這一段）
struct OrgMoveReceiveSection: View {
    let moveId: UUID
    @EnvironmentObject var lifeStore: LifeStore

    var body: some View {
        EmptyView()
    }
}
