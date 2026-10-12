import SwiftUI

// MARK: - 稀有度配色（人生頁「履歷」的 ProfileFlashCard 在用）
//
// [v25.540] 檔名沿用（專案檔不動），內容只剩 CardRarity：
// 股票（v25.528）、房地產（v25.534）、載具（v25.540）三張卡片都換成看板＋各區小卡，
// 閃卡模板 FlashCardView、底部資訊欄 FlashCardInfoColumn、售出印章 SoldStamp、
// 設定頁「閃卡樣式」與它的 7 個 flash_card_* 設定都已經拿掉（決定 16）。
// 留下的只有履歷頁 ProfileFlashCard 用的 .legendary 配色：標籤字、字色、背景漸層、邊框、陰影。

// MARK: 稀有度

enum CardRarity {
    case common
    case uncommon
    case rare
    case epic
    case legendary

    var label: String {
        switch self {
        case .common: return "COMMON"
        case .uncommon: return "UNCOMMON"
        case .rare: return "RARE"
        case .epic: return "EPIC"
        case .legendary: return "LEGENDARY"
        }
    }

    var borderGradient: [Color] {
        switch self {
        case .common: return [.gray.opacity(0.4), .gray.opacity(0.2)]
        case .uncommon: return [.cyan, .blue.opacity(0.6), .cyan]
        case .rare: return [.yellow, .orange, .yellow]
        case .epic: return [.purple, .pink, .purple, .indigo, .purple]
        case .legendary: return [.purple, .pink, .orange, .yellow, .green, .cyan, .blue, .purple]
        }
    }

    var bgGradient: [Color] {
        switch self {
        case .common: return [Color(.systemBackground), Color(.systemGray6)]
        case .uncommon: return [Color(.systemBackground), Color.cyan.opacity(0.05)]
        case .rare: return [Color(.systemBackground), Color.orange.opacity(0.08)]
        case .epic: return [Color(.systemBackground), Color.purple.opacity(0.10)]
        case .legendary: return [Color.black.opacity(0.9), Color.purple.opacity(0.15), Color.black.opacity(0.9)]
        }
    }

    var borderWidth: CGFloat {
        switch self {
        case .common: return 1
        case .uncommon: return 2
        case .rare: return 2.5
        case .epic: return 2.8
        case .legendary: return 3
        }
    }

    var textColor: Color {
        switch self {
        case .common: return .primary
        case .uncommon: return .cyan
        case .rare: return .orange
        case .epic: return .purple
        case .legendary: return .yellow
        }
    }

    var shadowColor: Color {
        switch self {
        case .common: return .clear
        case .uncommon: return .cyan.opacity(0.3)
        case .rare: return .orange.opacity(0.4)
        case .epic: return .purple.opacity(0.45)
        case .legendary: return .purple.opacity(0.5)
        }
    }
}
