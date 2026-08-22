import SwiftUI
import UIKit

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

    @MainActor
    static func export(baseName: String,
                       width: CGFloat = 430,
                       itemsPerPage: Int,
                       header: AnyView,
                       items: [AnyView],
                       decorate: (AnyView) -> AnyView = { $0 }) -> [URL] {
        guard !items.isEmpty else { return [] }
        let per = max(1, min(itemsPerPage, items.count))
        let pageCount = (items.count + per - 1) / per
        let fileStamp = fileStampFmt.string(from: Date())
        let displayStamp = displayStampFmt.string(from: Date())
        let safeBase = sanitizeFileName(baseName)
        var urls: [URL] = []

        for p in 0..<pageCount {
            let range = (p * per)..<min(items.count, (p + 1) * per)
            let page = VStack(alignment: .leading, spacing: 12) {
                header
                VStack(spacing: 0) {
                    ForEach(Array(range), id: \.self) { i in
                        items[i]
                        if i < range.upperBound - 1 { Divider().padding(.leading, 58) }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
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
            renderer.scale = max(UIScreen.main.scale, 3)
            guard let ui = renderer.uiImage,
                  let data = ui.jpegData(compressionQuality: 0.95) else { continue }
            let suffix = pageCount > 1 ? "_\(p + 1)之\(pageCount)" : ""
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(safeBase)_\(fileStamp)\(suffix).jpg")
            do { try data.write(to: url); urls.append(url) } catch { }
        }
        return urls
    }
}

// MARK: - 每頁項目數選擇（匯出前詢問）

/// 匯出前的「每頁項目數」選擇：confirmationDialog 的標準包裝。
/// 上次的選擇以 @AppStorage 記住，下次對話框把它排最前面。
/// 用法：
///   .exportPageSizeDialog(isPresented: $askPageSize, itemCount: hits.count) { per in
///       runExport(perPage: per)
///   }
struct ExportPageSizeDialog: ViewModifier {
    @Binding var isPresented: Bool
    let itemCount: Int
    let onPick: (Int) -> Void
    @AppStorage("export_items_per_page") private var lastPick = 15

    private var options: [Int] {
        // 上次選的排最前，其餘依序；只列出小於總數的選項（等於/超過就直接「全部一頁」）
        var base = [lastPick, 10, 15, 20, 30]
        var seen = Set<Int>()
        base = base.filter { seen.insert($0).inserted && $0 < itemCount }
        return base
    }

    func body(content: Content) -> some View {
        content.confirmationDialog("每頁項目數（共 \(itemCount) 項）",
                                   isPresented: $isPresented, titleVisibility: .visible) {
            ForEach(options, id: \.self) { n in
                Button("每頁 \(n) 項（共 \((itemCount + n - 1) / n) 頁）") {
                    lastPick = n
                    onPick(n)
                }
            }
            Button("全部一頁") { onPick(itemCount) }
            Button("取消", role: .cancel) { }
        }
    }
}

extension View {
    func exportPageSizeDialog(isPresented: Binding<Bool>, itemCount: Int,
                              onPick: @escaping (Int) -> Void) -> some View {
        modifier(ExportPageSizeDialog(isPresented: isPresented, itemCount: itemCount, onPick: onPick))
    }
}
