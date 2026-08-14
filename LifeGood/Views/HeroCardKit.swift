import SwiftUI

// MARK: - 英雄卡標準套件（殼層 + KPI 小格）
// 從收入／變動支出／固定支出／股票／儲蓄險五張英雄卡收斂而成：
//   1. heroCardShell：漸層底＋三顆散景圓＋玻璃光澤＋自訂背景層（趨勢曲線）＋
//      圓角裁切＋主色光暈陰影——歷史上「三圓規格／glass shine 對齊」都是逐檔手動同步，
//      收斂後改一處全部生效。
//   2. HeroKpiCell：英雄卡 KPI 橫列小格（原本 7+ 個檔案各刻一份完全相同的實作）。
// 可調參數（設定 > 進階設定 > 英雄卡樣式）：圓角、散景亮度、玻璃光澤、陰影強度、
// KPI 數值字級——@AppStorage 即時生效。

// MARK: 殼層

private struct HeroCardShellModifier<ExtraBackground: View>: ViewModifier {
    let colors: [Color]
    let shadowTint: Color?
    @ViewBuilder let extraBackground: () -> ExtraBackground

    @AppStorage("hero_card_corner_radius") private var cornerRadius: Double = 20
    @AppStorage("hero_card_bokeh") private var bokehScale: Double = 1.0
    @AppStorage("hero_card_shine") private var shineIntensity: Double = 0.18
    @AppStorage("hero_card_shadow") private var shadowScale: Double = 1.0

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    LinearGradient(colors: colors,
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    extraBackground()
                    // 三顆散景裝飾圓（統一規格；亮度倍率可調）
                    Circle()
                        .fill(.white.opacity(0.12 * bokehScale))
                        .frame(width: 130, height: 130)
                        .offset(x: 90, y: -55)
                        .blur(radius: 14)
                    Circle()
                        .fill(.white.opacity(0.07 * bokehScale))
                        .frame(width: 80, height: 80)
                        .offset(x: -70, y: 50)
                        .blur(radius: 10)
                    Circle()
                        .fill(.white.opacity(0.06 * bokehScale))
                        .frame(width: 55, height: 55)
                        .offset(x: 30, y: 28)
                        .blur(radius: 8)
                    // 頂部玻璃光澤（強度可調）
                    LinearGradient(colors: [.white.opacity(shineIntensity), .clear],
                                   startPoint: .top, endPoint: .center)
                }
                .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: (shadowTint ?? colors.last ?? .black).opacity(0.42 * shadowScale),
                    radius: 16, x: 0, y: 8)
    }
}

extension View {
    /// 英雄卡殼層：漸層底＋散景圓＋玻璃光澤＋extraBackground（趨勢曲線等）＋圓角＋陰影。
    /// shadowTint 省略時用漸層最後一色（深色端）。
    func heroCardShell<B: View>(colors: [Color], shadowTint: Color? = nil,
                                @ViewBuilder extraBackground: @escaping () -> B) -> some View {
        modifier(HeroCardShellModifier(colors: colors, shadowTint: shadowTint,
                                       extraBackground: extraBackground))
    }

    /// 無額外背景層的簡便版
    func heroCardShell(colors: [Color], shadowTint: Color? = nil) -> some View {
        modifier(HeroCardShellModifier(colors: colors, shadowTint: shadowTint,
                                       extraBackground: { EmptyView() }))
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

/// 英雄卡 KPI 橫列小格（白字系；標籤 9pt＋數值粗體圓體，數值字級可由進階設定調整）
struct HeroKpiCell: View {
    let label: String
    let value: String

    @AppStorage("hero_card_kpi_value_size") private var valueSize: Double = 12

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            Text(value)
                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}
