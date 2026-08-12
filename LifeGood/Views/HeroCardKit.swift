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
