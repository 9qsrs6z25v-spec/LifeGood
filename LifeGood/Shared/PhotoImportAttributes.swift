import Foundation
import ActivityKit

// MARK: - 照片匯入 · Live Activity 資料（v25.483）
//
// 這個檔案同時屬於「主 App」與「LifeGoodWidgets」兩個 target：
// 主 App 負責更新進度，Widget Extension 負責在靈動島／鎖定畫面畫出來。
//
// 為什麼需要：從 iCloud 相簿選的照片要先把原圖整張下載回來，幾十張就要等上
// 好幾分鐘。使用者離開 App 去做別的事時，進度就完全看不到了——靈動島是
// iOS 上唯一能在別的 App 畫面上持續顯示自己進度的地方。

struct PhotoImportAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 已完成張數
        var done: Int
        /// 總張數
        var total: Int
        /// 這批照片要存到哪裡（例「景點照片」）
        var label: String
        /// 全部存完了（畫面改寫「完成」，過幾秒自己收掉）
        var finished: Bool

        var fraction: Double {
            guard total > 0 else { return 0 }
            return min(1, max(0, Double(done) / Double(total)))
        }

        /// 「73%」。靈動島收合時只剩這麼小的空間，所以百分比是主角。
        var percentText: String {
            "\(Int((fraction * 100).rounded()))%"
        }

        /// 「40 / 41 張」
        var countText: String {
            "\(min(done, total)) / \(total) 張"
        }
    }

    /// 這批是什麼時候開始的
    var startedAt: Date
}
