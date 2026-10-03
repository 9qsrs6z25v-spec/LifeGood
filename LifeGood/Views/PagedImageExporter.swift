import SwiftUI
import UIKit

// MARK: - 出圖的尺寸上限

/// 全 App 出圖共用的倍率保險。
///
/// [v25.426] 為什麼需要它：ImageRenderer 畫的是 CALayer，而圖層光柵化在任一邊
/// 超過 16384 像素時會**整張變空白**——不會丟錯誤、不會回 nil，只會安靜地
/// 給你一張空圖。全 App 的出圖都寫死 scale ≥ 3，所以只要內容高度超過大約
/// 5400 點就會踩到。使用者遇到的「評分加總 23 人匯出全部，每張圖都 6KB
/// 一片空白」就是這個。
///
/// 正解仍然是**出圖前先分頁**（見本檔的 PagedImageExporter）；這裡是最後一道
/// 保險：分頁沒切夠細時寧可降倍率出一張看得到的圖，也不要出一張空白的。
enum ImageExportLimits {

    /// 在不超過光柵化上限的前提下能用的最大倍率。
    /// 保底 1 倍——再大就只能靠分頁，不是降倍率能解決的。
    static func safeScale(for size: CGSize, want: CGFloat? = nil) -> CGFloat {
        let target = want ?? max(UIScreen.main.scale, 3)
        guard size.width > 0, size.height > 0 else { return target }
        let maxSidePx: CGFloat = 12_000            // 離 16384 留餘裕
        let maxPixels: CGFloat = 40_000_000        // 約 160MB 的 RGBA，再大就開始吃記憶體
        let bySide = maxSidePx / max(size.width, size.height)
        let byArea = (maxPixels / (size.width * size.height)).squareRoot()
        return max(1, min(target, bySide, byArea))
    }

    /// 呼叫端的慣用寫法（刻意不包成一個吃 ImageRenderer 的函式：
    /// ImageRenderer 是 @MainActor 的型別，包起來會把隔離要求帶到每一個呼叫端）：
    ///
    ///     var measured = CGSize.zero
    ///     renderer.render { size, _ in measured = size }
    ///     renderer.scale = ImageExportLimits.safeScale(for: measured)
    ///
    /// render 的閉包裡不畫，所以這一次只跑版面計算，不會讓出圖時間變兩倍。

    /// 這張圖是不是整片同一個顏色（＝空白）。
    /// 縮到 12×12 再比，成本固定，不隨原圖大小增加。
    static func isBlank(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let side = 12
        var buf = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &buf, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        let first = Array(buf[0..<4])
        for i in stride(from: 4, to: buf.count, by: 4) {
            if Array(buf[i..<(i + 4)]) != first { return false }
        }
        return true
    }
}

// MARK: - 分頁產圖標準模組
//
// 舊做法（整張長圖 sliceTallImage 硬切）有兩個問題：第二頁起沒有抬頭、
// 只剩項目列，跟第一頁對照有割裂感；切點以像素高度計，可能落在列中間。
// 此模組改以「項目」為單位分頁：
//   • 每一頁都重複 header（抬頭＋來源/起始資訊），單頁轉傳也看得懂脈絡
//   • 每頁項目數由呼叫端傳入——匯出前先讓使用者選（見 ExportPageSizeDialog）
//   • 頁尾自帶「第 N 頁／共 M 頁 · 匯出時間」戳記
// 規格對齊全 App 匯出慣例：寬 430、scale ≥3、JPG 0.95、檔名 _N之M 頁碼。
//
// 用法：
//   let urls = PagedImageExporter.export(
//       baseName: "行事曆搜尋_xxx",
//       itemsPerPage: perPage,
//       header: AnyView(headerView),
//       items: hits.map { AnyView(row($0)) },
//       decorate: { AnyView($0.environmentObject(lifeStore)) })   // 環境物件由呼叫端補

/// 分頁匯出的內容單位：多區塊匯出（部屬總覽／家庭／兼任工作區）用。
/// sectionHeader 不計入每頁項目數；跨頁切在區塊中段時，下一頁開頭自動重複該區塊標題。
enum PagedExportItem {
    case sectionHeader(AnyView)
    case row(AnyView)
}

enum PagedImageExporter {
    private static let fileStampFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmm"; return f
    }()
    private static let displayStampFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "yyyy/M/d HH:mm"; return f
    }()

    /// 檔名非法字元消毒（「/」會被當目錄層級、寫檔直接失敗）
    static func sanitizeFileName(_ s: String) -> String {
        s.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
    }

    /// 單一清單版：全部都是項目列（行事曆搜尋等）
    @MainActor
    static func export(baseName: String,
                       width: CGFloat = 430,
                       itemsPerPage: Int,
                       header: AnyView,
                       items: [AnyView],
                       decorate: (AnyView) -> AnyView = { $0 }) -> [URL] {
        exportSections(baseName: baseName, width: width, itemsPerPage: itemsPerPage,
                       header: header, items: items.map { PagedExportItem.row($0) },
                       decorate: decorate)
    }

    /// 多區塊版：sectionHeader＋row 混排。分頁只數 row；
    /// 切頁落在區塊中段時，下一頁開頭自動重複該區塊標題（不會沒頭沒尾）；
    /// 懸在頁底、後面沒有列的區塊標題會搬到下一頁開頭。
    @MainActor
    static func exportSections(baseName: String,
                               width: CGFloat = 430,
                               itemsPerPage: Int,
                               header: AnyView,
                               items: [PagedExportItem],
                               decorate: (AnyView) -> AnyView = { $0 }) -> [URL] {
        let rowTotal = items.reduce(0) { if case .row = $1 { return $0 + 1 }; return $0 }
        guard rowTotal > 0 else { return [] }
        let per = max(1, min(itemsPerPage, rowTotal))

        // 分頁
        var pages: [[PagedExportItem]] = []
        var current: [PagedExportItem] = []
        var rowsInPage = 0
        var currentSection: AnyView?
        for item in items {
            switch item {
            case .sectionHeader(let v):
                currentSection = v
                current.append(item)
            case .row:
                if rowsInPage >= per {
                    // 頁底懸空的區塊標題（後面沒有列）搬到下一頁開頭
                    var carried: [PagedExportItem] = []
                    while case .some(.sectionHeader) = current.last {
                        carried.append(current.removeLast())
                    }
                    pages.append(current)
                    current = carried.reversed()
                    if carried.isEmpty, let cs = currentSection {
                        current = [.sectionHeader(cs)]   // 區塊中段換頁：重複標題維持脈絡
                    }
                    rowsInPage = 0
                }
                current.append(item)
                rowsInPage += 1
            }
        }
        if !current.isEmpty { pages.append(current) }

        // 逐頁渲染
        let fileStamp = fileStampFmt.string(from: Date())
        let displayStamp = displayStampFmt.string(from: Date())
        let safeBase = sanitizeFileName(baseName)
        let pageCount = pages.count
        var urls: [URL] = []
        for (p, pageItems) in pages.enumerated() {
            let page = VStack(alignment: .leading, spacing: 12) {
                header
                pageBody(pageItems)
                HStack {
                    Spacer()
                    Text(pageCount > 1
                         ? "第 \(p + 1) 頁／共 \(pageCount) 頁 · 美好人生 \(displayStamp) 匯出"
                         : "美好人生 · \(displayStamp) 匯出")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
            }
            .frame(width: width)
            .padding(.vertical, 20)
            .background(Color(.systemGroupedBackground))

            let renderer = ImageRenderer(content: decorate(AnyView(page)))
            var measured = CGSize.zero
            renderer.render { size, _ in measured = size }
            renderer.scale = ImageExportLimits.safeScale(for: measured)
            guard let ui = renderer.uiImage, !ImageExportLimits.isBlank(ui),
                  let data = ui.jpegData(compressionQuality: 0.95) else { continue }
            let suffix = pageCount > 1 ? "_\(p + 1)之\(pageCount)" : ""
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(safeBase)_\(fileStamp)\(suffix).jpg")
            do { try data.write(to: url); urls.append(url) } catch { }
        }
        return urls
    }

    /// 一頁的內容：連續的 row 聚成一張白卡（列間分隔線），sectionHeader 獨立成行
    @ViewBuilder
    private static func pageBody(_ items: [PagedExportItem]) -> some View {
        let blocks = makeBlocks(items)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .header(let v):
                    v.padding(.horizontal, 20)
                case .rows(let rows):
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                            r
                            if i < rows.count - 1 { Divider().padding(.leading, 58) }
                        }
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private enum Block {
        case header(AnyView)
        case rows([AnyView])
    }

    private static func makeBlocks(_ items: [PagedExportItem]) -> [Block] {
        var out: [Block] = []
        var pendingRows: [AnyView] = []
        for item in items {
            switch item {
            case .sectionHeader(let v):
                if !pendingRows.isEmpty { out.append(.rows(pendingRows)); pendingRows = [] }
                out.append(.header(v))
            case .row(let v):
                pendingRows.append(v)
            }
        }
        if !pendingRows.isEmpty { out.append(.rows(pendingRows)) }
        return out
    }
}

// MARK: - 每頁項目數選擇（匯出前詢問）

/// 匯出前的「每頁項目數」選擇：兩個選項——自行輸入數字、或全部一頁
///（使用者需求 v25.285：不用預設清單挑，直接打數字最快）。
/// 上次輸入的數字以 @AppStorage 記住並預填。
/// 用法：
///   .exportPageSizeDialog(isPresented: $askPageSize, itemCount: hits.count) { per in
///       runExport(perPage: per)
///   }
struct ExportPageSizeDialog: ViewModifier {
    @Binding var isPresented: Bool
    let itemCount: Int
    let onPick: (Int) -> Void
    @AppStorage("export_items_per_page") private var lastPick = 15
    @State private var countText = ""

    func body(content: Content) -> some View {
        content
            .alert("每頁項目數（共 \(itemCount) 項）", isPresented: $isPresented) {
                TextField("每頁項目數", text: $countText)
                    .keyboardType(.numberPad)
                Button("產生分頁") {
                    let entered = Int(countText.trimmingCharacters(in: .whitespaces)) ?? lastPick
                    let n = min(max(1, entered), max(1, itemCount))
                    lastPick = n
                    onPick(n)
                }
                Button("全部一頁") { onPick(max(1, itemCount)) }
                Button("取消", role: .cancel) { }
            } message: {
                Text("輸入每頁要放幾個項目（上次：\(lastPick)），或選擇全部一頁。")
            }
            .onChange(of: isPresented) { _, showing in
                if showing { countText = "\(lastPick)" }   // 開框預填上次的數字
            }
    }
}

extension View {
    func exportPageSizeDialog(isPresented: Binding<Bool>, itemCount: Int,
                              onPick: @escaping (Int) -> Void) -> some View {
        modifier(ExportPageSizeDialog(isPresented: isPresented, itemCount: itemCount, onPick: onPick))
    }
}
