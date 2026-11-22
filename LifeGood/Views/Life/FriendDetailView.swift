import SwiftUI

// [v25.636] 朋友履歷頁、朋友編輯器（peoplehub2 G2；judge_peoplehub §C7、§C8、§C12）
//
// - FriendDetailView(relationshipId:)：照 PetDetailView 一張卡一段 AnyView。頭卡（名字、分組、生日、紀念日、電話）→
//   往來（PersonLedgerSlot.swift）→ 送過的禮（PersonLedger.gifts；沒有就不出現）→ 互動紀錄 → 備註 → 同名名片。
//   用 id 找不到這位＝關頁（不強制解包）。沒有分享鈕。
// - FriendEditor(target:)：新增（預設朋友）／編輯；名字過 FriendBook.nameState；分組不提供「家人」（原本就是家人的才多列）；
//   改名提醒寫出會對不上幾頓；存檔先 dismiss、下一個 runloop 才 FriendActions.upsert；刪除要確認、只刪朋友資料。
// - 所有 sheet 一律 sheet(item:)＋.appStores()；看不擋、動手才擋（編輯、記一筆、刪除要訂閱）。
