import Foundation
import SwiftUI

// MARK: - 手機條碼（v25.628 barcodewidget；scratchpad/radar/judge_barcodewidget.md §C1、§C2、§C5、§C6）
//
// 這個檔案同時屬於「主 App」與「LifeGoodWidgets」兩個 target（手錶不編）。
// 條紋表與 bars(for:) 用手錶那一份 LifeGoodWatch/Code39.swift——那個檔這一版**原封不動**多登記進 App、小工具兩個
// target（同一個 fileRef，pbx A01B000001001673／1674），三邊畫出來的條碼保證是同一張表。
//
// 這裡放：
//   • CarrierBarcodeShared：格式驗證（跟 WatchPhoneSettings.validBarcode 同一條規則）、App Group 讀寫、寫完重畫兩個小工具
//   • CarrierBarcodeLayout：一個窄條幾點、每一條黑條／白條在第幾點（貼齊畫素，邊緣不糊）
//   • CarrierBarcodeBars／CarrierBarcodeStrip：用 Shape 畫（不用 Canvas：小工具裡 Shape 一定畫得出來）
//
// 顏色規則（掃描要對比）：
//   • fullColor（App、主畫面一般模式、StandBy）：白條＋黑條都畫，白底黑條
//   • 其他（鎖定畫面的單色半透明、主畫面染色）：只畫「白的部分」（留白＋條與條之間），黑條不畫、透出底下——
//     系統把白的部分變亮、黑條是底下的暗色，還是「亮底暗條」；黑條若畫成白色，條碼會變成反白，很多掃描器讀不到
//
// ⚠️ 只准用 Foundation／SwiftUI 與共用檔的型別（WidgetShared、WidgetKind、WidgetRefresh、Code39）。
//    驗證碼（鑰匙圈）這裡永遠不碰；也不讀 App 的 UserDefaults.standard（那是 App 側 EInvoiceSyncManager 的事）。

enum CarrierBarcodeShared {
    /// 小工具庫預覽、還在載入時（placeholder）畫的樣子。9 個字：手機條碼一定是 8 個字，所以這張不可能是任何人的載具
    static let sampleText = "/LIFEGOOD"

    /// 手機條碼格式：「/」開頭＋7 碼，每碼是 0-9、A-Z、「.」「+」「-」（都是 Code 39 有的字）。
    /// 先去頭尾空白、轉大寫；不對回 nil。跟 WatchPhoneSettings.validBarcode（WatchPackageBuilder.swift）同一條規則
    static func valid(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let chars = Array(text)
        guard chars.count == 8, chars[0] == "/" else { return nil }
        let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.+-")
        for c in chars.dropFirst() where !allowed.contains(c) {
            return nil
        }
        return text
    }

    /// 小工具讀：App Group 裡的手機條碼（沒有、格式不對回 nil）
    static var stored: String? {
        valid(WidgetShared.defaults?.string(forKey: WidgetShared.carrierBarcodeKey))
    }

    /// App 寫：驗過格式才寫；nil 或格式不對就刪掉。值跟現在一樣就什麼都不做。回傳有沒有改
    @discardableResult
    static func store(_ cardNo: String?, in defaults: UserDefaults? = WidgetShared.defaults) -> Bool {
        guard let d = defaults else { return false }
        let key = WidgetShared.carrierBarcodeKey
        let wanted: String? = valid(cardNo)
        let current: String? = d.string(forKey: key)
        if current == wanted { return false }
        if let wanted {
            d.set(wanted, forKey: key)
        } else {
            d.removeObject(forKey: key)
        }
        return true
    }

    /// App 連結、拿掉手機條碼、啟動時呼叫：寫進 App Group，有改才重畫中型與鎖定畫面兩個（控制項沒有值，不用重畫）。
    /// forceReload：啟動那一次值沒變也重畫一次（開機後還沒解鎖時小工具讀不到 App Group、畫成空的，值沒變不會再叫它重畫）
    static func syncWidgets(cardNo: String?, forceReload: Bool = false) {
        if store(cardNo) || forceReload {
            WidgetRefresh.reload(WidgetKind.carrierBarcodeKinds)
        }
    }
}

// MARK: - 版面（純計算，sim_barcodewidget.py 逐行對照）

/// 一段（黑條或白條）：從條碼最左邊（含留白）算起第幾點、多寬（點）
struct CarrierBarcodeRun: Equatable {
    var x: Double
    var width: Double
}

struct CarrierBarcodeLayout: Equatable {
    /// 一個窄條幾點
    var unit: Double
    /// 整張多寬（點；含兩邊留白）
    var totalWidth: Double
    /// 黑條
    var bars: [CarrierBarcodeRun]
    /// 白的部分：左邊留白、條與條之間、右邊留白（跟 bars 一起剛好鋪滿 0…totalWidth，不重疊、沒有縫）
    var spaces: [CarrierBarcodeRun]

    static let empty = CarrierBarcodeLayout(unit: 0, totalWidth: 0, bars: [], spaces: [])

    /// App 全螢幕、主畫面中型的留白（窄條數）＝標準 10 個（Code39.quietZone）
    static let fullQuiet: Double = Code39.quietZone
    /// 鎖定畫面的留白：6 個窄條（160 點寬放不下 164 個窄條；鎖定畫面掃不到時點一下開全螢幕）
    static let lockQuiet: Double = 6

    /// 條碼加兩邊留白一共幾個窄條（「/ABC1234」、留白 10＝164；留白 6＝156）。編不了回 0
    static func units(text: String, quiet: Double) -> Double {
        let w = Code39.width(for: text)
        return w > 0 ? w + 2 * quiet : 0
    }

    /// 放得下的窄條寬：可用寬度 ÷ 窄條數，往下取到整數個畫素（每一條窄條一樣粗），至少 1 個畫素，最多 maxUnit 點。編不了回 0
    static func unit(fitting width: Double, text: String, quiet: Double, scale: Double, maxUnit: Double) -> Double {
        let n = units(text: text, quiet: quiet)
        guard n > 0, width > 0 else { return 0 }
        let s = scale > 0 ? scale : 1
        let pixels = max(1, (width / n * s).rounded(.down))
        return min(maxUnit, pixels / s)
    }

    /// 貼齊畫素（四捨五入；都是正數，跟 ROUND_HALF_UP 一樣）
    static func snap(_ value: Double, scale: Double) -> Double {
        let s = scale > 0 ? scale : 1
        return (value * s).rounded(.toNearestOrAwayFromZero) / s
    }

    /// 每一條黑條、白條的位置（點）。編不了、unit ≤ 0 回 empty
    static func make(text: String, unit: Double, quiet: Double, scale: Double) -> CarrierBarcodeLayout {
        let raw: [Code39.Bar] = Code39.bars(for: text)
        guard !raw.isEmpty, unit > 0 else { return empty }
        let s = scale > 0 ? scale : 1
        let onePixel = 1 / s
        let total = snap(units(text: text, quiet: quiet) * unit, scale: s)
        var bars: [CarrierBarcodeRun] = []
        var spaces: [CarrierBarcodeRun] = []
        var cursor: Double = 0
        for bar in raw {
            let left = snap((quiet + bar.x) * unit, scale: s)
            var right = snap((quiet + bar.x + bar.width) * unit, scale: s)
            if right <= left { right = left + onePixel }
            if left > cursor {
                spaces.append(CarrierBarcodeRun(x: cursor, width: left - cursor))
            }
            bars.append(CarrierBarcodeRun(x: left, width: right - left))
            cursor = right
        }
        if total > cursor {
            spaces.append(CarrierBarcodeRun(x: cursor, width: total - cursor))
        }
        return CarrierBarcodeLayout(unit: unit, totalWidth: max(total, cursor), bars: bars, spaces: spaces)
    }
}

// MARK: - 畫

/// 一組長方形（黑條或白條），每一條從上畫到下
struct CarrierBarcodeBars: Shape {
    let runs: [CarrierBarcodeRun]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for r in runs {
            p.addRect(CGRect(x: rect.minX + CGFloat(r.x), y: rect.minY,
                             width: CGFloat(r.width), height: rect.height))
        }
        return p
    }
}

/// 條碼本身（含兩邊留白）。寬＝layout.totalWidth，高由外面給（.frame(height:)）。
/// fullColor：白底黑條；不是：只畫白的部分（見檔頭「顏色規則」）
struct CarrierBarcodeStrip: View {
    let layout: CarrierBarcodeLayout
    let fullColor: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            CarrierBarcodeBars(runs: layout.spaces)
                .fill(Color.white)
            if fullColor {
                CarrierBarcodeBars(runs: layout.bars)
                    .fill(Color.black)
            }
        }
        .frame(width: CGFloat(layout.totalWidth))
        .accessibilityElement()
        .accessibilityLabel(Text("手機條碼"))
    }
}
