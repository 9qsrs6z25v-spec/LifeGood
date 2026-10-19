import SwiftUI

// MARK: - 財富卡片頁的字和數字（v25.564，財富 v3；wealth/judge.md §4.1、§4.2、§4.3、§4.4）
//
// 照 VehicleCardData／HouseCardData：卡片頁的每一段字、每一個數、風景的資料（WealthTideScene、WealthCycleScene）
// 都在這裡一次組好（WealthCardData.build，在主執行緒的 .task(id:) 叫一次，坑 #21、#22），body 只畫。
// 數字一律讀 WealthFacts（LifeStore.wealthFacts 的快取），不自己再算一份餘額、期別。
//
// 分工：G2 實作（這個檔＋Views/Life/WealthCardViews.swift）。主控只開檔。
