import SwiftUI

// MARK: - 手機條碼（手錶 v2，v25.576；watch/judge.md §2.8、§2.17、§2.18；watch/build/v2/brief.md G4-3）
//
// 只屬於 LifeGoodWatch。② 錢左上 🧾 推進來（WatchRoute.barcode）；iPhone 設定打開「手機條碼」才有（WatchModel.barcode，
// 只有「/ABC1234」；發票驗證碼永遠不送）。不放錶面、不放智慧型堆疊。這一頁沒有任何金額、人名。
//   • 白底全螢幕 Code 39：Code39.bars(for:) 算好每一條黑條（單位＝窄條），這裡用 Canvas 一條一條畫（手錶沒有 Core Image）。
//     兩邊各留白 10 個窄條（Code39.quietZone）；下面黑字等寬的號碼（店員掃不到可以自己打）
//   • 橫的（46mm 預設）：1 單位＝1 點＝2 畫素 → 164 點寬、條高 90（放不下就矮一點，最矮 40）
//   • 〔轉 90° 放大〕：條碼轉直的、沿螢幕長邊（可用的高）放大：1 單位＝可用的高 ÷ 164（至少 1 點）；
//     〔轉回來〕放在右邊一欄（放在下面會吃掉長邊，41mm 就放大不了）
//   • 41mm／40mm（WatchStyle.isCompact，寬 < 190 點）一打開就是直的（164 點離 176 點寬太近）；在 onAppear 設一次，不在屬性預設值讀螢幕
//   • 第一次打開才出現「掃不到請到手錶「設定 › 螢幕顯示與亮度」調亮」（App 不能調手錶亮度；手錶 App Group 鍵
//     watch_barcode_tip_shown），跟條碼同一張卡片一起轉
//   • 手腕放下：整頁關掉、回 ② 錢（WatchModel.closeBarcode；關之前那一瞬間也不畫條碼、底色換黑）；
//     系統要遮（redactionReasons 含 .privacy，沒解鎖時的快照）也不畫條碼
// ⚠️ 條紋表在 Code39.swift（主控）；scratchpad/watch/build/v2/code39_check.py 驗過表與「/ABC1234」讀得回來。

struct BarcodePage: View {
    @ObservedObject private var model = WatchModel.shared
    @Environment(\.isLuminanceReduced) private var dimmed
    /// 系統要遮（沒解鎖時的畫面快照）：條碼也不畫
    @Environment(\.redactionReasons) private var reasons

    /// 直的（轉 90°）
    @State private var rotated = false
    /// onAppear 只設一次（41mm 預設直的、第一次的提示）
    @State private var didSetup = false
    /// 這一次打開要不要寫「掃不到請到…調亮」
    @State private var showTip = false

    static let offText = "iPhone 設定沒有打開「手機條碼」"
    static let badText = "這個手機條碼畫不出來，請在 iPhone 上出示"
    static let tipText = "掃不到請到手錶「設定 › 螢幕顯示與亮度」調亮"
    /// 手錶 App Group：提示出現過了
    static let tipKey = "watch_barcode_tip_shown"
    static let rotateTitle = "轉 90° 放大"
    static let rotateBackTitle = "轉回來"
    static let stripLabel = "手機條碼"

    // 版面（點）
    /// 橫的：1 單位＝1 點（46mm 164 點寬）
    static let flatUnit: CGFloat = 1
    /// 橫的條高
    static let flatBarHeight: CGFloat = 90
    /// 條高最矮
    static let minBarHeight: CGFloat = 40
    /// 直的條高最高（轉過去之後的寬）
    static let maxTurnedBarHeight: CGFloat = 120
    /// 號碼那一行
    static let codeHeight: CGFloat = 20
    /// 第一次的提示（兩行 Footnote）
    static let tipHeight: CGFloat = 36
    static let gap: CGFloat = 4
    /// 橫的時〔轉 90° 放大〕那一列
    static let buttonRowHeight: CGFloat = 34
    /// 直的時〔轉回來〕那一欄
    static let sideColumnWidth: CGFloat = 46
    static let sideButtonHeight: CGFloat = 64

    var body: some View {
        page
            .onAppear {
                setUp()
            }
            .onChange(of: dimmed) { _, isDimmed in
                if isDimmed {
                    model.closeBarcode()
                }
            }
            .containerBackground(pageColor, for: .navigation)
    }

    /// 白底；手腕放下那一瞬間（關掉之前）換黑
    private var pageColor: Color {
        dimmed ? Color.black : Color.white
    }

    /// 手腕放下（關掉之前那一瞬間）、系統要遮：不畫條碼
    private var hidesCode: Bool {
        dimmed || reasons.contains(.privacy)
    }

    /// 第一次出現：41mm／40mm 預設直的；提示只在第一次有條碼時出現
    private func setUp() {
        guard !didSetup else { return }
        didSetup = true
        rotated = WatchStyle.isCompact
        if model.barcode != nil && !Self.tipWasShown {
            showTip = true
            WidgetShared.defaults?.set(true, forKey: Self.tipKey)
        }
    }

    private static var tipWasShown: Bool {
        WidgetShared.defaults?.bool(forKey: tipKey) ?? false
    }

    private var tipLine: String? {
        showTip ? Self.tipText : nil
    }

    // MARK: 內容

    @ViewBuilder
    private var page: some View {
        if hidesCode {
            Color.clear
        } else if let text = model.barcode {
            if Code39.canEncode(text) {
                barcodeLayout(text)
            } else {
                message(Self.badText)
            }
        } else {
            message(Self.offText)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Color.black)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func barcodeLayout(_ text: String) -> some View {
        GeometryReader { geo in
            if rotated {
                turnedLayout(text, size: geo.size)
            } else {
                flatLayout(text, size: geo.size)
            }
        }
    }

    // MARK: 橫的

    /// 條碼 164 點寬、條高 90（放不下就矮一點）；下面〔轉 90° 放大〕
    private func flatLayout(_ text: String, size: CGSize) -> some View {
        let barHeight = flatStripHeight(for: size)
        return VStack(spacing: Self.gap) {
            BarcodeCard(text: text, unit: Self.flatUnit, barHeight: barHeight, tip: tipLine)
            rotateButton
        }
        .frame(width: size.width, height: size.height)
    }

    /// 橫的條高：扣掉號碼、按鈕那一列（和提示），夾在 40～90（名字不跟 static flatBarHeight 同名，免得 Self.flatBarHeight 兩個都對得上）
    private func flatStripHeight(for size: CGSize) -> CGFloat {
        let tip: CGFloat = showTip ? Self.tipHeight + Self.gap : 0
        let room: CGFloat = size.height - Self.buttonRowHeight - Self.gap - Self.codeHeight - Self.gap - tip
        return min(Self.flatBarHeight, max(Self.minBarHeight, room))
    }

    private var rotateButton: some View {
        Button {
            rotated.toggle()
        } label: {
            Label(Self.rotateTitle, systemImage: "rotate.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 12)
                .frame(height: Self.buttonRowHeight)
                .background(Capsule().fill(Color.black.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    // MARK: 直的（轉 90°）

    /// 卡片（條碼＋號碼＋第一次的提示）先排成「長＝可用的高、寬＝轉過去之後的寬」，轉 90° 之後外面再給轉過的框；
    /// 一個單位＝可用的高 ÷ 164（至少 1 點）。〔轉回來〕在右邊一欄
    private func turnedLayout(_ text: String, size: CGSize) -> some View {
        let length: CGFloat = size.height
        let total: CGFloat = max(1, CGFloat(Code39.totalWidth(for: text)))
        let unit: CGFloat = max(Self.flatUnit, length / total)
        let cardHeight: CGFloat = max(Self.minBarHeight, size.width - Self.sideColumnWidth - Self.gap)
        let barHeight = turnedBarHeight(cardHeight: cardHeight)
        return HStack(spacing: Self.gap) {
            BarcodeCard(text: text, unit: unit, barHeight: barHeight, tip: tipLine)
                .frame(width: length, height: cardHeight)
                .rotationEffect(.degrees(90))
                .frame(width: cardHeight, height: length)
            rotateBackButton
        }
        .frame(width: size.width, height: size.height)
    }

    /// 轉過去之後的寬扣掉號碼（和提示），夾在 40～120
    private func turnedBarHeight(cardHeight: CGFloat) -> CGFloat {
        let tip: CGFloat = showTip ? Self.tipHeight + Self.gap : 0
        let room: CGFloat = cardHeight - Self.codeHeight - Self.gap - tip
        return min(Self.maxTurnedBarHeight, max(Self.minBarHeight, room))
    }

    private var rotateBackButton: some View {
        Button {
            rotated.toggle()
        } label: {
            rotateBackLabel
        }
        .buttonStyle(.plain)
    }

    private var rotateBackLabel: some View {
        VStack(spacing: 2) {
            Image(systemName: "rotate.left")
                .font(.system(size: 17, weight: .semibold))
            Text(Self.rotateBackTitle)
                .font(.footnote)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.black)
        .frame(width: Self.sideColumnWidth, height: Self.sideButtonHeight)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.08)))
    }
}

// MARK: - 一張卡片（條碼＋號碼＋第一次的提示；橫的直接放，直的整張轉 90°）

private struct BarcodeCard: View {
    let text: String
    /// 1 個窄條幾點
    let unit: CGFloat
    let barHeight: CGFloat
    /// 第一次打開才有的那一句；nil＝不畫
    let tip: String?

    var body: some View {
        VStack(spacing: BarcodePage.gap) {
            Code39Strip(text: text, unit: unit)
                .frame(height: barHeight)
            codeText
            tipText
        }
    }

    /// 「/ABC1234」黑字等寬
    private var codeText: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.black)
            .lineLimit(1)
            .frame(height: BarcodePage.codeHeight)
    }

    @ViewBuilder
    private var tipText: some View {
        if let tip {
            Text(tip)
                .font(.footnote)
                .foregroundStyle(Color.black.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(height: BarcodePage.tipHeight)
        }
    }
}

// MARK: - 條碼本身（Canvas 照 Code39.bars 畫黑條；寬＝Code39.totalWidth × unit，含兩邊留白）

private struct Code39Strip: View {
    let text: String
    /// 1 個窄條幾點
    let unit: CGFloat

    var body: some View {
        let bars: [Code39.Bar] = Code39.bars(for: text)
        let quiet = CGFloat(Code39.quietZone)
        let u = unit
        return Canvas { context, size in
            for bar in bars {
                let x: CGFloat = (quiet + CGFloat(bar.x)) * u
                let rect = CGRect(x: x, y: 0, width: CGFloat(bar.width) * u, height: size.height)
                context.fill(Path(rect), with: .color(Color.black))
            }
        }
        .frame(width: CGFloat(Code39.totalWidth(for: text)) * u)
        .accessibilityLabel(Text(BarcodePage.stripLabel))
    }
}
