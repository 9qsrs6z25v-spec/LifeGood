import SwiftUI

// MARK: - 跑馬燈（v25.520，全 App 共用）
//
// 標題放不下就跑馬燈（使用者指定：「幫我整個軟體標題檢查一下，套用標題如果過長就變成跑馬燈」）。
// 原本是 v25.517 為時間軸卡片寫的 TripMarqueeText，這一版搬出來給整個 App 用。
//
// 用法跟 Text 一樣，字型、粗細、顏色都可以從外面掛：
//
//     MarqueeText(item.title)
//         .font(.headline)
//         .foregroundStyle(.primary)
//
// 導覽列（inline）的標題用 .marqueeNavigationTitle(_:)。

/// 一行放不下的字用跑馬燈，不折行、不切成「…」。
///
/// 放得下就是一般的一行字，不會動。放不下才捲：停 2 秒讓人先讀開頭，
/// 再以每秒 32pt 往左捲，字尾後面隔一段空白接著第二份，捲到第二份的開頭
/// 剛好回到原位——那一格跟第一格長得一模一樣，所以接回去看不出跳動。
///
/// ⚠️ 用 TimelineView 從「現在幾點」算出位移，不用 withAnimation(.repeatForever)。
///    repeatForever 一旦開始就很難停、寬度一變（轉向、字級）就會從錯的位置繼續捲。
///    用時間算的話，暫停就是 paused: true，寬度變了下一格自己就對。
///
/// ⚠️ 只在捲進畫面時才捲（捲動視圖裡）：一整頁同時在動是雜訊，也耗電。
///    「看不到」是要被明確回報才算——onScrollVisibilityChange 萬一沒回報初始狀態
///    （或根本不在捲動視圖裡，例如導覽列），寧可多捲，也不要讓眼前那一行永遠不動。
///
/// ⚠️ 「減少動態效果」打開時不捲，退回一般的尾端省略（…）。VoiceOver 一律唸全名。
///
/// ⚠️ 字型：font 參數是 nil（預設）時吃外面掛的 .font(...)——量寬度的那兩份字
///    跟畫出來的字都從同一個環境拿，所以量的跟畫的一定一樣大。
///
/// ⚠️ 版面跟 `Text(...).lineLimit(1)` 一模一樣：寬度貼著字（不會自己撐滿整列），
///    擠不下時被壓縮——差別只在被壓縮之後是捲動而不是「…」。所以可以直接取代原本的
///    Text，後面緊跟著的徽章、箭頭位置都不會變。要撐滿整列就在外面自己掛
///    `.frame(maxWidth: .infinity, alignment: .leading)`，跟原本的 Text 一樣。
struct MarqueeText: View {
    let text: String
    /// nil＝用外面掛的 .font(...)（環境字型）
    var font: Font? = nil
    /// VoiceOver 要唸的字；nil＝唸 text
    var accessibilityText: String? = nil

    init(_ text: String, font: Font? = nil, accessibilityText: String? = nil) {
        self.text = text
        self.font = font
        self.accessibilityText = accessibilityText
    }

    init(text: String, font: Font? = nil, accessibilityText: String? = nil) {
        self.init(text, font: font, accessibilityText: accessibilityText)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 這一行實際拿到的寬度
    @State private var boxWidth: CGFloat = 0
    /// 這串字一行排開的自然寬度
    @State private var textWidth: CGFloat = 0
    @State private var onScreen = true
    /// 這一輪從什麼時候開始算（捲回畫面、換字的時候重來，先停在開頭）
    @State private var cycleStart = Date()

    /// 兩份字之間的空白
    private static let gap: CGFloat = 36
    /// 每輪開頭停多久（秒）
    private static let hold: Double = 2.0
    /// 捲動速度（pt／秒）。再快就讀不到了
    private static let speed: Double = 32

    private var overflows: Bool { boxWidth > 0 && textWidth > boxWidth + 0.5 }

    /// 有指定字型就套，沒有就吃環境（Text.font(nil) 會蓋成預設字型，不是「繼承」，所以不能直接傳 nil）
    private func label() -> Text {
        let t = Text(text)
        if let font { return t.font(font) }
        return t
    }

    var body: some View {
        // 佔位：決定這一行的高度與寬度。它就是一個 lineLimit(1) 的 Text，所以在版面裡的
        // 行為（貼著字、擠不下時被壓縮）跟原本的 Text 完全一樣。本身不畫
        // （hidden 也會把它移出輔助使用的樹）。
        label()
            .lineLimit(1)
            .hidden()
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { w in
                boxWidth = w
            }
            // 量自然寬度：fixedSize 讓它照整串排開。掛在 background 裡不影響版面。
            .background(alignment: .leading) {
                label()
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { w in
                        textWidth = w
                    }
            }
            .overlay(alignment: .leading) { visible }
            .onScrollVisibilityChange(threshold: 0.2) { shown in
                if shown && !onScreen { cycleStart = Date() }
                onScreen = shown
            }
            .onChange(of: text) { _, _ in cycleStart = Date() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText ?? text)
    }

    @ViewBuilder
    private var visible: some View {
        if !overflows || reduceMotion {
            label()
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !onScreen)) { context in
                marquee(offset: Self.offset(at: context.date, since: cycleStart,
                                            distance: textWidth + Self.gap))
            }
        }
    }

    private func marquee(offset x: CGFloat) -> some View {
        HStack(spacing: Self.gap) {
            label().fixedSize()
            label().fixedSize()
        }
        .offset(x: x)
        .frame(width: boxWidth, alignment: .leading)
        .clipped()
        // clipped／mask 只裁畫面、不裁點擊範圍：移出框外看不見的字照樣會接住點擊，
        // 蓋住左邊的勾選鈕（點勾選變成點整列）。點擊範圍限定在看得到的這一格。
        .contentShape(Rectangle())
        // 右緣一律淡出（告訴人後面還有字）；左緣只在捲動中才淡出——
        // 停在開頭的時候淡左緣會把第一個字吃掉一半。
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: x < 0 ? 10 : 0)
                Rectangle()
                LinearGradient(colors: [.black, .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 14)
            }
        }
    }

    /// 這一刻該往左移多少。一輪＝停 hold 秒＋捲 distance。
    /// 捲到 −distance 時第二份字剛好在原位，下一輪從 0 開始看起來是同一格。
    static func offset(at now: Date, since start: Date, distance: CGFloat) -> CGFloat {
        guard distance > 0 else { return 0 }
        let travel = Double(distance) / speed
        let t = max(0, now.timeIntervalSince(start))
        let phase = t.truncatingRemainder(dividingBy: hold + travel)
        return phase < hold ? 0 : -CGFloat((phase - hold) * speed)
    }
}

// MARK: - 導覽列標題

extension View {
    /// 導覽列（inline）的標題：放不下就跑馬燈，放得下就跟系統標題一樣置中
    /// （跑馬燈的寬度貼著字，principal 位置會把它擺在中間）。
    ///
    /// .navigationTitle 照樣設：下一頁的返回鍵、App 切換器、VoiceOver 的畫面名稱
    /// 都是讀它。畫面上顯示的是 principal 位置的跑馬燈（有 principal 項目時系統
    /// 不畫自己的標題）。
    ///
    /// ⚠️ 只用在 .navigationBarTitleDisplayMode(.inline) 的畫面：大標題模式下，
    ///    principal 跟大標題會同時出現、寫兩次。
    /// ⚠️ 這個畫面如果自己已經有 placement: .principal 的 ToolbarItem，不要用——
    ///    兩個 principal 只會顯示一個。
    func marqueeNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    MarqueeText(title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}
