import SwiftUI

// MARK: - 閃卡標準模板
// 從 StockDetailView／VehicleDetailView／RealEstateDetailView 三張同型手刻閃卡
// 收斂而成（歷史上大字防截斷、金額量級、散景、光澤、進場動畫都要逐檔手動同步，
// 多次出現「補齊姊妹閃卡落差」的維護工）。模板統一：
//   1. 版面骨架：稀有度標籤列 → 名稱＋副標槽 → 52pt 估值大字 → 中段槽 → 三欄資訊列
//   2. 殼層：稀有度漸層背景＋三顆散景圓＋玻璃光澤＋自訂背景層（如股票日線）、
//      圓角裁切、AngularGradient 稀有度邊框、陰影、售出印章、進場動畫
//   3. 可調參數（設定 > 進階設定 > 閃卡樣式）：圓角、邊框粗細倍率、大字字級、
//      散景亮度、光澤強度、陰影強度、進場動畫開關——@AppStorage 即時生效
// CardRarity 與 SoldStamp 一併移入本檔（原在 VehicleDetailView.swift）。

// MARK: 稀有度

enum CardRarity {
    case common
    case uncommon
    case rare
    case epic
    case legendary

    /// 汽車分級：0~50萬 / 51~100萬 / 101~200萬 / 201萬以上
    init(price: Double) {
        let wan = price / 10000
        switch wan {
        case ..<51: self = .common
        case ..<101: self = .uncommon
        case ..<201: self = .rare
        default: self = .legendary
        }
    }

    /// 房地產分級：0~600萬 / 601~1000萬 / 1001~1500萬 / 1501~2000萬 / 2001萬以上
    static func realEstate(price: Double) -> CardRarity {
        let wan = price / 10000
        switch wan {
        case ..<601: return .common
        case ..<1001: return .uncommon
        case ..<1501: return .rare
        case ..<2001: return .epic
        default: return .legendary
        }
    }

    /// 股票分級：以市值或成本（萬元）分級
    /// 0~10萬 / 11~50萬 / 51~100萬 / 101~300萬 / 301萬以上
    static func stock(value: Double) -> CardRarity {
        let wan = value / 10000
        switch wan {
        case ..<11:  return .common
        case ..<51:  return .uncommon
        case ..<101: return .rare
        case ..<301: return .epic
        default:     return .legendary
        }
    }

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

    // MARK: 模板配色輔助（深色傳說卡 vs 淺色其他卡）

    /// 主要內文色（名稱大字等）
    var primaryTextColor: Color { self == .legendary ? .white : .primary }
    /// 次要內文色（副標等）
    var secondaryTextColor: Color { self == .legendary ? .white.opacity(0.7) : .secondary }
    /// 說明字色（大字下方單位等）
    var captionTextColor: Color { self == .legendary ? .white.opacity(0.6) : .secondary }
    /// 資訊欄標籤色
    var columnLabelColor: Color {
        self == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel)
    }
    /// 資訊欄數值色
    var columnValueColor: Color { self == .legendary ? Color.white.opacity(0.8) : Color.primary }
}

// MARK: - 售出印章

struct SoldStamp: View {
    var size: CGFloat = 18

    var body: some View {
        Text("售出")
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .tracking(2)
            .foregroundStyle(.red)
            .padding(.horizontal, size * 0.55)
            .padding(.vertical, size * 0.2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.red, lineWidth: size * 0.14)
            )
            .rotationEffect(.degrees(-15))
            .shadow(color: .black.opacity(0.3), radius: size * 0.18, x: size * 0.08, y: size * 0.15)
    }
}

// MARK: - 閃卡模板

/// 底部資訊欄（label 上、value 下；valueColor nil 時依稀有度預設）
struct FlashCardInfoColumn: Identifiable {
    let label: String
    let value: String
    var valueColor: Color?
    var id: String { label }

    init(_ label: String, _ value: String, valueColor: Color? = nil) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
    }
}

struct FlashCardView<Subtitle: View, MiddleExtra: View, ExtraBackground: View>: View {
    let rarity: CardRarity
    /// 右上角類別標籤（例：股票／房地產／油車）
    let categoryLabel: String
    let categoryIcon: String
    /// 名稱大字
    let title: String
    /// 估值大字（splitWan 的數字部分）與其下說明（例：「萬元」「目前市值（萬元）」）
    let bigNumber: String
    let bigCaption: String
    /// 底部三欄資訊
    let columns: [FlashCardInfoColumn]
    var isSold: Bool = false
    /// 進場動畫開關：ImageRenderer 匯出圖片時傳 false——
    /// 離屏渲染不觸發 onAppear，動畫初始態（透明）會讓輸出變成空白卡
    var animated: Bool = true
    /// 名稱下方副標槽（股票代號膠囊／品牌／地址；不需要時傳 EmptyView）
    @ViewBuilder var subtitle: () -> Subtitle
    /// 大字下方中段槽（股票損益膠囊；不需要時傳 EmptyView）
    @ViewBuilder var middleExtra: () -> MiddleExtra
    /// 殼層額外背景（股票日線；不需要時傳 EmptyView）
    @ViewBuilder var extraBackground: () -> ExtraBackground

    // 進階設定可調參數（設定 > 進階設定 > 閃卡樣式）
    @AppStorage("flash_card_corner_radius") private var cornerRadius: Double = 16
    @AppStorage("flash_card_border_scale") private var borderScale: Double = 1.0
    @AppStorage("flash_card_value_size") private var valueFontSize: Double = 52
    @AppStorage("flash_card_bokeh") private var bokehScale: Double = 1.0
    @AppStorage("flash_card_shine") private var shineIntensity: Double = 0.18
    @AppStorage("flash_card_shadow") private var shadowScale: Double = 1.0
    @AppStorage("flash_card_animation") private var appearAnimation: Bool = true

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            // 頂部稀有度標籤列
            HStack {
                Text(rarity.label)
                    .font(.caption2.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(rarity.textColor)
                Spacer()
                Label(categoryLabel, systemImage: categoryIcon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(rarity == .legendary ? .yellow : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // 名稱 + 副標槽
            VStack(spacing: 6) {
                Text(title)
                    .font(.title.weight(.bold))
                    .foregroundStyle(rarity.primaryTextColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                subtitle()
            }
            .padding(.top, 16)
            .padding(.horizontal, 24)

            // 估值大字
            VStack(spacing: 4) {
                Text(bigNumber)
                    .font(.system(size: valueFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(rarity.textColor)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(bigCaption)
                    .font(.subheadline)
                    .foregroundStyle(rarity.captionTextColor)
            }
            .padding(.vertical, 20)

            // 中段槽（損益膠囊等）
            middleExtra()

            // 底部資訊列
            HStack {
                ForEach(Array(columns.enumerated()), id: \.element.id) { idx, col in
                    if idx > 0 { Spacer() }
                    VStack(spacing: 2) {
                        Text(col.label)
                            .font(.caption2)
                            .foregroundStyle(rarity.columnLabelColor)
                        Text(col.value)
                            .font(.caption.bold())
                            .foregroundStyle(col.valueColor ?? rarity.columnValueColor)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background {
            ZStack {
                LinearGradient(colors: rarity.bgGradient,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                extraBackground()
                // 三顆散景裝飾圓（亮度倍率可調；取三卡中最精緻的 Stock v3 模糊版規格）
                Circle()
                    .fill(Color.white.opacity(0.07 * bokehScale))
                    .frame(width: 95, height: 95)
                    .blur(radius: 15)
                    .offset(x: 65, y: -35)
                Circle()
                    .fill(Color.white.opacity(0.05 * bokehScale))
                    .frame(width: 70, height: 70)
                    .blur(radius: 12)
                    .offset(x: -60, y: 25)
                Circle()
                    .fill(Color.white.opacity(0.04 * bokehScale))
                    .frame(width: 55, height: 55)
                    .blur(radius: 9)
                    .offset(x: 55, y: 45)
                // 頂部玻璃光澤（強度可調）
                LinearGradient(
                    colors: [.white.opacity(shineIntensity), .clear],
                    startPoint: .top, endPoint: .center
                )
            }
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    AngularGradient(colors: rarity.borderGradient, center: .center),
                    lineWidth: rarity.borderWidth * borderScale
                )
        )
        .shadow(color: rarity.shadowColor,
                radius: (rarity == .legendary ? 15 : 8) * shadowScale, y: 4)
        .overlay(alignment: .topLeading) {
            if isSold {
                SoldStamp(size: 32)
                    .offset(x: -10, y: -14)
            }
        }
        // 進場動畫（可由進階設定關閉；匯出圖的靜態渲染由 animated 參數關閉）
        .opacity(!animated || !appearAnimation || appeared ? 1 : 0)
        .offset(y: !animated || !appearAnimation || appeared ? 0 : 14)
        .animation(.spring(response: 0.50, dampingFraction: 0.78).delay(0.04), value: appeared)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }
}
