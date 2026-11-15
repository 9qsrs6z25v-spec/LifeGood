import SwiftUI
import WidgetKit
import AppIntents

// MARK: - 手機條碼：主畫面中型、鎖定畫面長方形、控制中心按鈕（v25.628 barcodewidget）
//
// 只屬於「LifeGoodWidgets」target。規格：scratchpad/radar/judge_barcodewidget.md §C5–§C8；
// scratchpad/radar/build/barcodewidget/brief.md 的 G2（型別名稱、字、數字照那裡）。
// 讀 App Group 的手機條碼（CarrierBarcodeShared.stored，「/ABC1234」這 8 個字）；驗證碼永遠不在這裡。
//
// 型別（G2 實作）：CarrierBarcodeWidget、CarrierBarcodeLockWidget、CarrierBarcodeControl、LifeGoodBarcodeBundle、
//   CarrierBarcodeEntry、CarrierBarcodeProvider、CarrierBarcodeMediumView、CarrierBarcodeLockView
//
// • 中型、鎖定畫面共用 CarrierBarcodeProvider：一筆 entry、policy .never（值只在 App 連結／拿掉手機條碼、啟動補寫時變，
//   那時 CarrierBarcodeShared.syncWidgets 只重畫這兩個 kind；啟動那一次值沒變也重畫）。讀不到時 30 分鐘後再讀
//   （開機後還沒解鎖過，App Group 讀不到，不能一直空著）。
// • 顏色照 CarrierBarcodeShared.swift 檔頭「顏色規則」：fullColor 白底黑條；其他模式只畫白的部分（亮底暗條，不反白）。
// • 鎖定畫面（使用者自己選的例外）只有條碼與號碼；沒連結只有 barcode 圖示，一個字都沒有。
// • 控制項照 StartRunControl：LifeGoodOpenIntent（openAppWhenRun → WidgetOpenAppHandoff → WidgetLink.apply）。
// • 不加 privacySensitive（要給店員掃）；不用 Canvas（Shape 在小工具裡最穩）。

// MARK: - Timeline

struct CarrierBarcodeEntry: TimelineEntry {
    let date: Date
    /// 「/ABC1234」（驗過格式）；nil＝還沒連結手機條碼
    let text: String?
}

struct CarrierBarcodeProvider: TimelineProvider {
    func placeholder(in context: Context) -> CarrierBarcodeEntry {
        CarrierBarcodeEntry(date: Date(), text: CarrierBarcodeShared.sampleText)
    }

    func getSnapshot(in context: Context, completion: @escaping (CarrierBarcodeEntry) -> Void) {
        let text: String?
        if context.isPreview {
            // 小工具庫預覽：沒連結時畫樣本「/LIFEGOOD」（9 個字，不可能是任何人的載具）
            text = CarrierBarcodeShared.stored ?? CarrierBarcodeShared.sampleText
        } else {
            text = CarrierBarcodeShared.stored
        }
        completion(CarrierBarcodeEntry(date: Date(), text: text))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CarrierBarcodeEntry>) -> Void) {
        let entry = CarrierBarcodeEntry(date: Date(), text: CarrierBarcodeShared.stored)
        // 讀不到（還沒連結，或開機後還沒解鎖、App Group 讀不到）：30 分鐘後再讀一次；讀到了值只在 App 那邊變，.never
        let policy: TimelineReloadPolicy = entry.text == nil ? .after(Date().addingTimeInterval(30 * 60)) : .never
        completion(Timeline(entries: [entry], policy: policy))
    }
}

// MARK: - 主畫面中型

struct CarrierBarcodeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.carrierBarcode, provider: CarrierBarcodeProvider()) { entry in
            CarrierBarcodeMediumView(entry: entry)
        }
        .configurationDisplayName("手機條碼")
        .description("結帳時給店員掃。點一下會打開全螢幕條碼並調到最亮。")
        .supportedFamilies([.systemMedium])
    }
}

struct CarrierBarcodeMediumView: View {
    let entry: CarrierBarcodeEntry

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.displayScale) private var scale

    private var fullColor: Bool { renderingMode == .fullColor }
    private var labelColor: Color { fullColor ? Color.black.opacity(0.55) : Color.secondary }
    private var numberColor: Color { fullColor ? Color.black : Color.primary }
    private var emptyColor: Color { fullColor ? Color.black.opacity(0.5) : Color.secondary }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                Color.white
            }
            .widgetURL(WidgetLink.carrierBarcode)
    }

    @ViewBuilder
    private var content: some View {
        if let text = entry.text {
            codeCard(text)
        } else {
            emptyText
        }
    }

    private func codeCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("手機條碼")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(labelColor)
            GeometryReader { geo in
                strip(text, size: geo.size)
            }
            Text(text)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(numberColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
    }

    /// 依可用寬度算窄條（留白 10、最多 3 點、貼齊畫素），條高約寬的 1/3，置中
    private func strip(_ text: String, size: CGSize) -> some View {
        let s = Double(scale)
        let quiet = CarrierBarcodeLayout.fullQuiet
        let unit = CarrierBarcodeLayout.unit(fitting: Double(size.width), text: text, quiet: quiet, scale: s, maxUnit: 3)
        let layout = CarrierBarcodeLayout.make(text: text, unit: unit, quiet: quiet, scale: s)
        let height: CGFloat = min(size.height, CGFloat(layout.totalWidth / 3))
        return CarrierBarcodeStrip(layout: layout, fullColor: fullColor)
            .frame(height: height)
            .frame(width: size.width, height: size.height)
    }

    private var emptyText: some View {
        Text("到 LifeGood 電子發票連結手機條碼")
            .font(.subheadline)
            .foregroundStyle(emptyColor)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 鎖定畫面長方形

struct CarrierBarcodeLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.carrierBarcodeLock, provider: CarrierBarcodeProvider()) { entry in
            CarrierBarcodeLockView(entry: entry)
        }
        .configurationDisplayName("手機條碼")
        .description("鎖定畫面的條碼是半透明的，掃不到時點一下打開全螢幕條碼")
        .supportedFamilies([.accessoryRectangular])
    }
}

/// 只有條碼與號碼（這個 struct 不准有任何字串常值的字）
struct CarrierBarcodeLockView: View {
    let entry: CarrierBarcodeEntry

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.displayScale) private var scale

    private var fullColor: Bool { renderingMode == .fullColor }
    private var lockBackground: Color { fullColor ? Color.white : Color.clear }
    private var numberColor: Color { fullColor ? Color.black : Color.primary }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                lockBackground
            }
            .widgetURL(WidgetLink.carrierBarcode)
    }

    @ViewBuilder
    private var content: some View {
        if let text = entry.text {
            GeometryReader { geo in
                code(text, size: geo.size)
            }
        } else {
            // fullColor 是白底：圖示跟號碼一樣用黑（不然深色環境的 primary 是白，白底上看不到）
            Image(systemName: "barcode")
                .font(.title2)
                .foregroundStyle(numberColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 留白 6 窄條、最多 2 點；條碼填滿、下面 10 點等寬號碼
    private func code(_ text: String, size: CGSize) -> some View {
        let s = Double(scale)
        let quiet = CarrierBarcodeLayout.lockQuiet
        let unit = CarrierBarcodeLayout.unit(fitting: Double(size.width), text: text, quiet: quiet, scale: s, maxUnit: 2)
        let layout = CarrierBarcodeLayout.make(text: text, unit: unit, quiet: quiet, scale: s)
        let barHeight: CGFloat = max(20, size.height - 13)
        return VStack(spacing: 1) {
            CarrierBarcodeStrip(layout: layout, fullColor: fullColor)
                .frame(height: barHeight)
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(numberColor)
                .lineLimit(1)
                .frame(height: 12)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - 控制中心

struct CarrierBarcodeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKind.controlCarrierBarcode) {
            ControlWidgetButton(action: LifeGoodOpenIntent(url: WidgetLink.carrierBarcode)) {
                Label("手機條碼", systemImage: "barcode")
            }
        }
        .displayName("手機條碼")
        .description("打開 LifeGood 的全螢幕手機條碼，螢幕會調到最亮")
    }
}

// MARK: - 子 bundle（掛在 LifeGoodLifeBundle；@WidgetBundleBuilder 一次最多 10 個，共 3 個）

struct LifeGoodBarcodeBundle: WidgetBundle {
    var body: some Widget {
        CarrierBarcodeWidget()
        CarrierBarcodeLockWidget()
        CarrierBarcodeControl()
    }
}
