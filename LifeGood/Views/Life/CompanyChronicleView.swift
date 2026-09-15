import SwiftUI
import UIKit
import ImageIO

// MARK: - 廠區編年史（v25.363）
//
// 把「廠區據點 + 掛在它底下的重大決議」畫成一張編年史圖，直式或橫式都可以。
// 純 SwiftUI 繪製（漸層、形狀、SF Symbols），不依賴任何圖片素材，
// 交給 ImageRenderer 出圖就能分享。
//
// 直式：左側一條時間軸，由上往下一個廠一段，決議列在各自那段底下。
// 橫式：由左至右一個廠一欄，適合廠多、每廠決議少的情況。

struct ChronicleEntry: Identifiable {
    let site: CompanySite
    /// 這個廠的期間結束（＝下一個廠啟用）；nil＝至今
    let eraEnd: Date?
    let resolutions: [SideRoleResolution]
    var id: UUID { site.id }
}

struct CompanyChronicleView: View {
    enum Orientation { case vertical, horizontal }

    let title: String
    let subtitle: String
    let entries: [ChronicleEntry]
    let orientation: Orientation
    /// 每個廠最多畫幾則決議，超過的只寫「還有 N 則」，避免圖爆長
    var maxResolutionsPerSite = 10

    private let ink = Color(red: 0.16, green: 0.13, blue: 0.11)
    private let accent = Color(red: 0.45, green: 0.31, blue: 0.20)   // 棕
    private let paper = Color(red: 0.99, green: 0.98, blue: 0.96)

    private let columnWidth: CGFloat = 278
    private let columnGap: CGFloat = 22
    private let pagePadding: CGFloat = 44

    /// 整張圖的寬度一定要算得出來。ImageRenderer 的 proposedSize 是 .unspecified，
    /// 版面裡只要有 Spacer 或 maxWidth/maxHeight: .infinity 落在沒有邊界的容器裡，
    /// 量到的理想尺寸就會變成無限大，uiImage 直接回 nil——出圖會安靜地失敗。
    private var canvasWidth: CGFloat {
        switch orientation {
        case .vertical:
            return 900
        case .horizontal:
            let cols = max(1, CGFloat(entries.count))
            return max(900, cols * (columnWidth + columnGap) + pagePadding * 2)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(accent.opacity(0.25)).frame(height: 2)
                .padding(.bottom, orientation == .vertical ? 22 : 26)
            if entries.isEmpty {
                Text("還沒有廠區據點")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.4))
                    .padding(.vertical, 60)
            } else if orientation == .vertical {
                verticalBody
            } else {
                horizontalBody
            }
            footer
        }
        .padding(pagePadding)
        .frame(width: canvasWidth, alignment: .topLeading)
        .background(paper)
    }

    // MARK: 頁首頁尾

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 34, weight: .black, design: .serif))
                    .foregroundStyle(ink)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ink.opacity(0.55))
            }
            Spacer(minLength: 20)
            VStack(alignment: .trailing, spacing: 3) {
                Text("編年史").font(.system(size: 13, weight: .bold, design: .serif))
                    .tracking(4)
                    .foregroundStyle(accent)
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(accent.opacity(0.75))
            }
        }
        .padding(.bottom, 14)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "leaf.fill").font(.system(size: 10))
            Text("美好人生").font(.system(size: 11, weight: .semibold))
            Spacer()
            Text(Self.stamp.string(from: Date()) + " 匯出")
                .font(.system(size: 11))
        }
        .foregroundStyle(ink.opacity(0.38))
        .padding(.top, 26)
    }

    // MARK: 直式

    private var verticalBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                let isLast = idx == entries.count - 1
                HStack(alignment: .top, spacing: 18) {
                    dot
                    VStack(alignment: .leading, spacing: 10) {
                        siteHeading(entry)
                        resolutionList(entry)
                    }
                    .padding(.bottom, isLast ? 0 : 30)
                }
                // 連接線畫在背景：background 拿得到父層的實際高度，
                // 不需要 maxHeight: .infinity 去撐（那會讓量測變成無限大）
                .background(alignment: .topLeading) {
                    if !isLast {
                        Rectangle()
                            .fill(accent.opacity(0.28))
                            .frame(width: 2)
                            .padding(.leading, 8)
                            .padding(.top, 18)
                    }
                }
            }
        }
    }

    /// 時間軸上的圓點（連接線由外層的 background 負責）
    private var dot: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [accent, accent.opacity(0.65)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 18, height: 18)
            Circle().fill(paper).frame(width: 7, height: 7)
        }
        .frame(width: 18)
    }

    private func siteHeading(_ entry: ChronicleEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eraText(entry))
                .font(.system(size: 15, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(accent)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.site.name.isEmpty ? entry.site.displayName : entry.site.name)
                    .font(.system(size: 23, weight: .bold, design: .serif))
                    .foregroundStyle(ink)
                if !entry.site.company.isEmpty {
                    Text(entry.site.company)
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(accent.opacity(0.12), in: Capsule())
                        .foregroundStyle(accent)
                }
                if !entry.site.isActive {
                    Text("已結束")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(ink.opacity(0.08), in: Capsule())
                        .foregroundStyle(ink.opacity(0.45))
                }
            }
            HStack(spacing: 10) {
                if !entry.site.location.isEmpty {
                    label("mappin", entry.site.location)
                }
                label("doc.text", "\(entry.resolutions.count) 則決議")
                if let y = entry.site.years, y >= 0.1 {
                    label("clock", String(format: "%.1f 年", y))
                }
            }
        }
    }

    private func label(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(ink.opacity(0.5))
    }

    private func resolutionList(_ entry: ChronicleEntry) -> some View {
        let shown = Array(entry.resolutions.prefix(maxResolutionsPerSite))
        let rest = entry.resolutions.count - shown.count
        return VStack(alignment: .leading, spacing: 7) {
            ForEach(shown) { r in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(accent.opacity(0.45))
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(SideRoleFormat.date(r.date))
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundStyle(accent.opacity(0.85))
                            if !r.serialLabel.isEmpty {
                                Text(r.serialLabel)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(ink.opacity(0.35))
                            }
                            Text(r.title.isEmpty ? "（未填標題）" : r.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !r.categories.isEmpty || !r.initiator.isEmpty {
                            Text(metaText(r))
                                .font(.system(size: 10))
                                .foregroundStyle(ink.opacity(0.42))
                        }
                    }
                }
            }
            if rest > 0 {
                Text("還有 \(rest) 則決議")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.35))
                    .padding(.leading, 13)
            }
            if entry.resolutions.isEmpty {
                Text("這段期間沒有記錄決議")
                    .font(.system(size: 11))
                    .foregroundStyle(ink.opacity(0.3))
                    .padding(.leading, 13)
            }
        }
    }

    // MARK: 橫式

    private var horizontalBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 上方一條貫穿的時間軸
            HStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { idx, _ in
                    HStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [accent, accent.opacity(0.65)],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(width: 16, height: 16)
                            Circle().fill(paper).frame(width: 6, height: 6)
                        }
                        if idx != entries.count - 1 {
                            Rectangle().fill(accent.opacity(0.28)).frame(height: 2)
                        }
                    }
                    .frame(width: columnWidth + columnGap, alignment: .leading)
                }
            }
            .padding(.bottom, 14)

            HStack(alignment: .top, spacing: 0) {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        siteHeading(entry)
                        resolutionList(entry)
                    }
                    .frame(width: columnWidth, alignment: .topLeading)
                    .padding(.trailing, columnGap)
                }
            }
        }
    }

    // MARK: 文字

    private func eraText(_ entry: ChronicleEntry) -> String {
        guard entry.site.startYear > 0 else { return "未填年月" }
        guard let end = entry.eraEnd else { return entry.site.startText + " ─ 至今" }
        let c = Calendar.current.dateComponents([.year, .month], from: end)
        return entry.site.startText + " ─ " + String(format: "%d/%02d", c.year ?? 0, c.month ?? 1)
    }

    private func metaText(_ r: SideRoleResolution) -> String {
        var parts: [String] = []
        if !r.categories.isEmpty { parts.append(r.categories.joined(separator: "、")) }
        if !r.initiator.isEmpty { parts.append("發起 " + r.initiator) }
        if !r.site.isEmpty { parts.append(r.site) }
        return parts.joined(separator: "・")
    }

    static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()
}

// MARK: - 出圖進度

/// 編年史出圖的階段。畫面上的進度條讀這個，不用知道任何出圖細節。
enum ChronicleExportStage: Equatable {
    case measuring
    /// 內容太長，自動把每個廠逐條列出的決議數降到 n 則（多的併成「還有 N 則決議」）
    case trimming(perSite: Int)
    case drawingPDF
    case drawingImage
    case encoding
    case writing
    case done

    /// 進度條的位置。階段數固定，所以直接給定值，不用另外算權重。
    var fraction: Double {
        switch self {
        case .measuring:     return 0.12
        case .trimming:      return 0.30
        case .drawingPDF:    return 0.55
        case .drawingImage:  return 0.55
        case .encoding:      return 0.80
        case .writing:       return 0.93
        case .done:          return 1.0
        }
    }

    var text: String {
        switch self {
        case .measuring:              return "量測版面尺寸…"
        case .trimming(let perSite):  return "內容太長，每個廠改列 \(perSite) 則決議…"
        case .drawingPDF:             return "繪製 PDF（向量，可無限放大）…"
        case .drawingImage:           return "繪製圖片…"
        case .encoding:               return "壓縮檔案（背景進行）…"
        case .writing:                return "存檔…"
        case .done:                   return "完成"
        }
    }

    /// 圖示圓的符號（沿用設定頁行動列 36pt 漸層圖示圓的視覺語言）
    var icon: String {
        switch self {
        case .measuring:                   return "ruler"
        case .trimming:                    return "scissors"
        case .drawingPDF:                  return "doc.richtext"
        case .drawingImage:                return "photo"
        case .encoding, .writing:          return "square.and.arrow.down"
        case .done:                        return "checkmark"
        }
    }
}

// MARK: - 出圖進度 HUD

/// 出圖進行中的浮層。視覺沿用 SettingsView.settingsActionRow 的
/// 「36pt 漸層圖示圓 ＋ 雙行文字」規格，底下多一條實際進度條。
struct ChronicleExportHUD: View {
    let stage: ChronicleExportStage
    let subtitle: String
    var accent: Color = .brown

    init(stage: ChronicleExportStage, subtitle: String, accent: Color = .brown) {
        self.stage = stage
        self.subtitle = subtitle
        self.accent = accent
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.22), accent.opacity(0.09)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Circle()
                        .stroke(accent.opacity(0.20), lineWidth: 1)
                        .frame(width: 36, height: 36)
                    Image(systemName: stage.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .shadow(color: accent.opacity(0.15), radius: 4, x: 0, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stage.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            ProgressView(value: stage.fraction)
                .tint(accent)
        }
        .padding(18)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
        .padding(24)
    }
}

// MARK: - 出圖

enum ChronicleExporter {
    /// 點陣圖的單邊／總像素預算。
    /// v25.364 固定用 2 倍出圖，據點一多就會做出上萬像素高的點陣圖：
    /// CGImage 畫得出來（uiImage 不是 nil），但編碼要再配置一份完整的未壓縮點陣＋
    /// 輸出緩衝，記憶體不夠時 pngData() **只是安靜地回 nil、不丟錯**，
    /// 使用者就看到「圖片編碼失敗」。所以尺寸必須在出圖前先壓進預算裡。
    private static let maxSide: CGFloat = 10_000
    private static let maxPixels: CGFloat = 24_000_000
    /// 點陣圖最高倍率（列印用 2 倍就夠）
    private static let maxScale: CGFloat = 2

    /// 超過「螢幕長邊 × 這個倍數」就改出 PDF。
    /// 這種尺寸的點陣圖本來就不適合用看圖程式開，PDF 是向量、沒有像素上限，
    /// 放大、列印、分頁都交給看檔案的人決定。
    private static let pdfScreenMultiple: CGFloat = 1.5

    /// Core Graphics 的 PDF mediaBox 上限是 200×200 英吋（14400pt），
    /// 超過會做出看圖程式打不開或內容被裁掉的檔案，所以自己先守住。
    private static let maxPDFSide: CGFloat = 14_000

    enum ExportError: LocalizedError {
        case renderFailed
        case tooLarge(width: Int, height: Int)
        case encodeFailed(width: Int, height: Int)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .renderFailed:
                return "畫面量不出尺寸，轉檔失敗了。試試另一個方向（直式／橫式），或先減少據點數量。"
            case .tooLarge(let w, let h):
                return "內容太長了：\(w)×\(h) 點，超過 PDF 單頁的上限（14400 點）。"
                    + "已經把每個廠的決議縮到最少仍然放不下，請改用橫式，或先減少據點數量。"
            case .encodeFailed(let w, let h):
                return "圖片編碼失敗：這張圖是 \(w)×\(h) 像素，超過這台裝置能編碼的大小。"
                    + "請改用另一個方向（直式／橫式）試試。"
            case .writeFailed(let msg):
                return "檔案存檔失敗：\(msg)"
            }
        }
    }

    /// 出圖主流程。量完尺寸才決定要出 PDF 還是 PNG：
    /// 超過螢幕長邊 1.5 倍 → PDF（向量，沒有點陣上限）；否則 → PNG。
    ///
    /// 繪製本身綁在主執行緒（ImageRenderer 是 @MainActor），但每個階段之間會
    /// `Task.yield()` 讓進度條畫得出來；真正耗時又吃記憶體的「壓成檔案」則丟到
    /// 背景執行緒，而且直接串流寫進檔案，不在記憶體裡先組一份完整的 Data。
    @MainActor
    static func export(
        _ view: CompanyChronicleView,
        name: String,
        onProgress: @MainActor (ChronicleExportStage) -> Void
    ) async throws -> URL {
        onProgress(.measuring)
        await Task.yield()

        var source = view
        var size = measure(source)
        guard size.width > 0, size.height > 0 else { throw ExportError.renderFailed }

        let screen = screenSize
        let pdfThreshold = max(screen.width, screen.height) * pdfScreenMultiple
        let wantsPDF = max(size.width, size.height) > pdfThreshold

        if wantsPDF {
            // PDF 單頁有 14400pt 的硬上限。超過就逐步減少每個廠逐條列出的決議數，
            // 版面本來就會把多的寫成「還有 N 則決議」，是不漏資訊的降級。
            var perSite = source.maxResolutionsPerSite
            while max(size.width, size.height) > maxPDFSide, perSite > 1 {
                perSite = max(1, perSite / 2)
                source.maxResolutionsPerSite = perSite
                onProgress(.trimming(perSite: perSite))
                await Task.yield()
                size = measure(source)
            }
            guard max(size.width, size.height) <= maxPDFSide else {
                throw ExportError.tooLarge(width: Int(size.width.rounded()),
                                           height: Int(size.height.rounded()))
            }
            onProgress(.drawingPDF)
            await Task.yield()
            let url = tempURL(name: name, ext: "pdf")
            try renderPDF(source, to: url)
            onProgress(.done)
            return url
        }

        // 點陣圖路徑：尺寸已經在一個半螢幕以內，挑得起的最高倍率一定編得出來
        let scale = fittingScale(for: size)
        onProgress(.drawingImage)
        await Task.yield()
        guard let image = render(source, scale: scale), let cgImage = image.cgImage else {
            throw ExportError.renderFailed
        }
        let pixelWidth = Int((size.width * scale).rounded())
        let pixelHeight = Int((size.height * scale).rounded())

        onProgress(.encoding)
        await Task.yield()
        // 編碼丟到背景：CGImageDestination 直接寫檔，不像 pngData() 要先在
        // 記憶體裡組出一整份完整的壓縮結果
        let box = CGImageBox(cgImage)
        let pngURL = tempURL(name: name, ext: "png")
        let jpgURL = tempURL(name: name, ext: "jpg")
        let written = await Task.detached(priority: .userInitiated) { () -> URL? in
            if writeImage(box.image, to: pngURL, type: "public.png", quality: nil) {
                return pngURL
            }
            // PNG 編不出來時，JPEG 需要的記憶體低很多，當作退路
            if writeImage(box.image, to: jpgURL, type: "public.jpeg", quality: 0.92) {
                return jpgURL
            }
            return nil
        }.value

        guard let written else {
            throw ExportError.encodeFailed(width: pixelWidth, height: pixelHeight)
        }
        onProgress(.writing)
        await Task.yield()
        onProgress(.done)
        return written
    }

    // MARK: 尺寸

    /// 只量尺寸、不畫任何點陣：render 的第二個參數才是「真的去畫」，不呼叫它就只拿到 size。
    /// 先前是先用 1 倍 render 出一張完整 UIImage 來量，長圖光是量測就要配置上百 MB。
    @MainActor
    private static func measure(_ view: CompanyChronicleView) -> CGSize {
        var out: CGSize = .zero
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = .unspecified
        renderer.render { size, _ in out = size }
        return out
    }

    /// 讓 點尺寸 × 倍率 同時滿足「單邊 <= maxSide」與「總像素 <= maxPixels」的最高倍率
    private static func fittingScale(for pointSize: CGSize) -> CGFloat {
        let longest = max(pointSize.width, pointSize.height)
        let area = pointSize.width * pointSize.height
        guard longest > 0, area > 0 else { return 1 }
        let bySide = maxSide / longest
        let byArea = (maxPixels / area).squareRoot()
        return max(1, min(maxScale, min(bySide, byArea)))
    }

    @MainActor
    private static var screenSize: CGSize {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let size = scene?.screen.bounds.size, size.width > 0, size.height > 0 else {
            return CGSize(width: 390, height: 844)
        }
        return size
    }

    // MARK: 繪製

    @MainActor
    private static func render(_ view: CompanyChronicleView, scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = .unspecified
        renderer.scale = scale
        return renderer.uiImage
    }

    /// 向量 PDF：直接寫進檔案，不經過任何點陣緩衝，所以多長都不會爆記憶體。
    /// 寫法比照本專案既有的組織圖 PDF 匯出（OrganizationView.generatePDFURL）。
    @MainActor
    private static func renderPDF(_ view: CompanyChronicleView, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = .unspecified
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw ExportError.writeFailed("無法建立 PDF 檔案")
        }
        var box = CGRect(x: 0, y: 0, width: 1200, height: 1600)
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw ExportError.writeFailed("無法建立 PDF 繪圖環境")
        }
        var drew = false
        renderer.render { size, draw in
            let pageBox = CGRect(origin: .zero, size: size)
            let pageInfo = [kCGPDFContextMediaBox as String: NSValue(cgRect: pageBox)]
            pdfContext.beginPDFPage(pageInfo as CFDictionary)
            draw(pdfContext)
            pdfContext.endPDFPage()
            drew = true
        }
        pdfContext.closePDF()
        guard drew else { throw ExportError.renderFailed }
    }

    // MARK: 檔案

    private static func tempURL(name: String, ext: String) -> URL {
        let safe = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safe).\(ext)")
    }

    /// CGImage 本身不是 Sendable，用一個明確的盒子把它交給背景工作，
    /// 而不是讓編譯器在每個呼叫點各自抱怨一次。
    private final class CGImageBox: @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    /// 直接把 CGImage 串流寫進檔案。成功回 true。
    private nonisolated static func writeImage(
        _ image: CGImage, to url: URL, type: String, quality: Double?
    ) -> Bool {
        try? FileManager.default.removeItem(at: url)
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, type as CFString, 1, nil
        ) else { return false }
        var options: [CFString: Any] = [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }
}
