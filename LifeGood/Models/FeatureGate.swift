import Foundation

/// 統一定義免費 / 付費功能範圍。
/// 免費：所有記帳模式 + 理財模式的「股票」
/// 付費（僅供閱覽，不可新增/編輯）：理財其餘 + 全部人生模式 + 管理 / 家庭子功能
enum FeatureGate {

    // MARK: - 免費功能

    /// 收支模式所有子功能皆免費
    static func isFree(_ feature: ExpenseFeature) -> Bool {
        _ = feature
        return true
    }

    /// 理財模式僅「股票」免費
    static func isFree(_ feature: FinanceFeature) -> Bool {
        feature == .stock
    }

    /// 人生模式全部需訂閱
    static func isFree(_ feature: LifeFeature) -> Bool {
        _ = feature
        return false
    }

    /// 管理子功能皆需訂閱
    static func isFree(_ feature: ManagementFeature) -> Bool {
        _ = feature
        return false
    }

    /// 配偶 / 兒女子功能皆需訂閱
    static func isFree(_ feature: FamilyMgmtFeature) -> Bool {
        _ = feature
        return false
    }

    // MARK: - 訊息

    /// 付費功能在未訂閱時於頁面顯示的提示文字
    static let viewOnlyMessage: String = "訂閱功能僅供閱覽"

    /// 在使用者於付費頁試圖新增 / 編輯時顯示的詳細訊息
    static let viewOnlyDetail: String = "此功能需訂閱「LifeGood Premium」才能新增與編輯。目前可繼續閱覽既有資料。"
}
