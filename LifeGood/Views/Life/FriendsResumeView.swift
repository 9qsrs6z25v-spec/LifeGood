import SwiftUI

// [v25.636] 朋友履歷：家庭第 5 顆「朋友履歷」的列表（peoplehub2 G1；judge_peoplehub §C6、§C10-b）
//
// - 最上面「常一起吃、還沒存的人」建議卡（PersonLedger.unknownCompanions；沒有候選人就不出現）：每位〔存成朋友〕；
//   左滑「不要再提」只記這台（FriendSuggestMemory，UserDefaults.standard）。
// - 分段：朋友、同事、客戶、其他（FriendBook.sections；舊資料分在「家人」的放「其他」、列上小字「建議放到家人履歷」）。
// - 每列：名字、生日、「一起吃飯 6 頓・最近 11/18」、有欠款時灰色小字「還欠 NT$375」（.task 一次算好字典）。
// - 右上〔＋〕新增朋友；點一列 sheet(item:) 開 FriendDetailView（FriendDetailView.swift）＋.appStores()。
// - 看不擋、動手才擋（照家庭其他履歷：新增、存成朋友要訂閱）。沒有分享鈕。寫 store 一律在 action 的下一個 runloop。
// - 每一列是 fileprivate struct（純值＋closure）、清單包 AnyView（25.618 閃退教訓）。
