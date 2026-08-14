import SwiftUI

// MARK: - 英雄卡標準套件（殼層 + KPI 小格 + 超支提示）
// 版型元件住這裡；參數目錄與三層解析器住 HeroStyleKit.swift。
//   1. heroCardShell：漸層底＋三顆散景圓＋玻璃光澤＋自訂背景層（趨勢曲線）＋
//      圓角裁切＋主色光暈陰影——歷史上「三圓規格／glass shine 對齊」都是逐檔手動同步。
//   2. HeroKpiCell：英雄卡 KPI 橫列小格（原本 7+ 個檔案各刻一份完全相同的實作）。
//   3. HeroOverspendHint：卡片下方的超支 emoji 小字提示（門檻的單一真相來源）。
// 樣式全部經 HeroStyleStore 三層解析（單卡覆寫 → 全域 → 出廠），
// 由「設定 > 進階設定 > 卡片設定 > 英雄卡樣式」調整、即時生效。

// MARK: 殼層

private struct HeroCardShellModifier<ExtraBackground: View>: ViewModifier {
    let card: HeroCard
    /// 呼叫端硬指定的顏色（遷移期舊多載用）；nil 代表吃 card 的出廠／覆寫色
    let explicitColors: [Color]?
    let explicitShadowTint: Color?
    @ViewBuilder let extraBackground: () -> ExtraBackground

    @ObservedObject private var store = HeroStyleStore.shared

    func body(content: Content) -> some View {
        let s = store.style(for: card)
        let colors = explicitColors ?? s.gradient
        let shadowTint = explicitShadowTint ?? (explicitColors?.last ?? s.shadowTint)
        return content
            .background(
                ZStack {
                    LinearGradient(colors: colors,
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    extraBackground()
                    // 三顆散景裝飾圓（統一規格；亮度與尺寸倍率可調）
                    Circle()
                        .fill(s.bokehTint.opacity(0.12 * s.bokehScale))
                        .frame(width: 130 * s.bokehSize, height: 130 * s.bokehSize)
                        .offset(x: 90, y: -55)
                        .blur(radius: 14)
                    Circle()
                        .fill(s.bokehTint.opacity(0.07 * s.bokehScale))
                        .frame(width: 80 * s.bokehSize, height: 80 * s.bokehSize)
                        .offset(x: -70, y: 50)
                        .blur(radius: 10)
                    Circle()
                        .fill(s.bokehTint.opacity(0.06 * s.bokehScale))
                        .frame(width: 55 * s.bokehSize, height: 55 * s.bokehSize)
                        .offset(x: 30, y: 28)
                        .blur(radius: 8)
                    // 頂部玻璃光澤（強度可調）
                    LinearGradient(colors: [.white.opacity(s.shine), .clear],
                                   startPoint: .top, endPoint: .center)
                }
                .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: s.corner))
            .shadow(color: shadowTint.opacity(0.42 * s.shadowScale),
                    radius: s.shadowRadius, x: 0, y: s.shadowRadius / 2)
            .environment(\.heroCard, card)
    }
}

extension View {
    /// 英雄卡殼層（標準用法）：顏色由卡片身分決定，可在進階設定逐卡覆寫。
    func heroCardShell<B: View>(card: HeroCard,
                                @ViewBuilder extraBackground: @escaping () -> B) -> some View {
        modifier(HeroCardShellModifier(card: card, explicitColors: nil,
                                       explicitShadowTint: nil, extraBackground: extraBackground))
    }

    /// 無額外背景層的簡便版
    func heroCardShell(card: HeroCard) -> some View {
        modifier(HeroCardShellModifier(card: card, explicitColors: nil,
                                       explicitShadowTint: nil, extraBackground: { EmptyView() }))
    }

    /// 遷移期舊多載：顏色仍由呼叫端硬指定，身分為 .legacy（只吃全域層）。
    /// 行為與遷移前完全一致；剩餘呼叫點清空後即可刪除。
    @available(*, deprecated, message: "改用 heroCardShell(card:)，顏色搬進 HeroCard.factoryGradient")
    func heroCardShell<B: View>(colors: [Color], shadowTint: Color? = nil,
                                @ViewBuilder extraBackground: @escaping () -> B) -> some View {
        modifier(HeroCardShellModifier(card: .legacy, explicitColors: colors,
                                       explicitShadowTint: shadowTint, extraBackground: extraBackground))
    }

    @available(*, deprecated, message: "改用 heroCardShell(card:)")
    func heroCardShell(colors: [Color], shadowTint: Color? = nil) -> some View {
        modifier(HeroCardShellModifier(card: .legacy, explicitColors: colors,
                                       explicitShadowTint: shadowTint, extraBackground: { EmptyView() }))
    }
}

// MARK: 超支警示（卡片下方小字提示）

/// 超支警示：以 emoji 小字提示掛在英雄卡「下方」（使用者指定），正常時不顯示。
///
/// 兩個門檻在此收斂為**單一真相來源**——先前 IncomeView / VariableExpenseView /
/// OverviewView 三處各寫死一份 `+ 0.08` 與 `> 0.9`，改一個必漏兩個。
/// 刻意不做成進階設定項：它們是「理財行為門檻」不是視覺參數，
/// 放進卡片樣式頁，日後找「超支警示怎麼調」不會往那裡找。
struct HeroOverspendHint: View {
    /// 已用比例（支出 ÷ 可用額度或均值；不夾住，可 > 1）
    let ratio: Double
    /// 月進度 0~1
    let monthProgress: Double
    /// 提示裡的名詞（「支出」「變動支出」）
    var noun: String = "支出"

    /// 提前警示：支出進度領先月進度這麼多即示警
    static let warnLead: Double = 0.08
    /// 危險門檻：用掉這個比例即轉為紅字
    static let dangerRatio: Double = 0.9

    private enum Level { case none, warn, danger, over }

    private var level: Level {
        guard ratio > 0 else { return .none }
        if ratio > 1.0 { return .over }
        if ratio > Self.dangerRatio { return .danger }
        if ratio > monthProgress + Self.warnLead { return .warn }
        return .none
    }

    var body: some View {
        if level != .none {
            HStack(spacing: 6) {
                Text(emoji)
                    .font(.system(size: 12))
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tint.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.20), lineWidth: 0.6))
            .padding(.horizontal, 20)
            .padding(.top, 6)
        }
    }

    private var emoji: String {
        switch level {
        case .over:   return "🔥"
        case .danger: return "🚨"
        case .warn:   return "⚠️"
        case .none:   return ""
        }
    }

    private var tint: Color {
        switch level {
        case .over, .danger: return Color(red: 0.86, green: 0.24, blue: 0.30)
        case .warn:          return Color(red: 0.80, green: 0.50, blue: 0.05)
        case .none:          return .secondary
        }
    }

    private var message: String {
        let pct = Int((ratio * 100).rounded())
        switch level {
        case .over:
            return "本月\(noun)已超出 \(pct - 100)%，該踩煞車了"
        case .danger:
            return "本月\(noun)已用掉 \(pct)%，額度快見底"
        case .warn:
            let lead = Int(((ratio - monthProgress) * 100).rounded())
            return "\(noun)進度領先月進度 \(lead)%，留意節奏"
        case .none:
            return ""
        }
    }
}

// MARK: KPI 小格

/// 英雄卡 KPI 橫列小格。排法／字級／圖示圓由 HeroStyleStore 三層解析
/// （單卡覆寫 → 全域 → 出廠），卡片身分自 .heroCardShell 經環境傳下來。
struct HeroKpiCell: View {
    let label: String
    let value: String
    /// 「圖示在上」排法用；未提供時該排法退回「數值在上」
    var icon: String? = nil

    @Environment(\.heroCard) private var card
    @ObservedObject private var store = HeroStyleStore.shared

    var body: some View {
        let s = store.style(for: card)
        VStack(spacing: 3) {
            switch s.kpiLayout {
            case .labelTop:
                labelText(s)
                valueText(s)
            case .valueTop:
                valueText(s)
                labelText(s)
            case .iconTop:
                if let icon {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.20))
                            .frame(width: s.kpiIconSize, height: s.kpiIconSize)
                        Image(systemName: icon)
                            .font(.system(size: s.kpiIconSize * 0.45, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    valueText(s)
                    labelText(s)
                } else {
                    valueText(s)
                    labelText(s)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private func labelText(_ s: HeroStyle) -> some View {
        Text(label)
            .font(.system(size: s.kpiLabelSize, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
    }

    private func valueText(_ s: HeroStyle) -> some View {
        Text(value)
            .font(.system(size: s.kpiValueSize, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
    }
}

// MARK: KPI 豎分隔線（高度隨排法推導 × 全域倍率）

/// 收斂 28／32／36／48 四種寫死高度
struct HeroKpiDivider: View {
    @Environment(\.heroCard) private var card
    @ObservedObject private var store = HeroStyleStore.shared

    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.25))
            .frame(width: 0.5, height: store.style(for: card).kpiDividerHeight)
    }
}
