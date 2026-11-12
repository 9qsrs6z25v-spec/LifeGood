import Foundation
import CoreGraphics
import ImageIO
import Vision

// [v25.624] 水電 v5a：繳費表單〔從照片讀數字〕的辨識（judge_utility C20 Q1；寫法照 BusinessCardOCR.recognizeText、
// WealthVault.recognizeLines，research §4.2）。規則（標籤、民國年、去年同期、指數核對、只填空欄）全在 Models/UtilityBillOCR.swift。
// - 手機上的 Vision（VNRecognizeTextRequest .accurate、zh-Hant／zh-Hans／en-US、不做語言校正：數字不要被改成字），不上網、不送 AI。
// - 只在使用者按〔從照片讀數字〕時叫（表單的按鈕動作），不在 onAppear／body／.task 自動跑。
// - 背景執行緒（DispatchQueue.global）；大圖先用 ImageIO 縮到長邊 ≤ 2000 像素（不整張解碼）。
// - continuation 每條路都 resume 剛好一次：縮圖失敗、perform 拋錯都 resume 空的（BusinessCardOCR v24.21 修過的坑）。
// - 讀到的字只在記憶體：不 print、不寫 log、不存檔、不寫 UserDefaults；解析完只回驗過的幾個數字（UtilityBillReading）。
// - 取消（Task.cancel）就不再讀下一張、回 nil；表單收到時如果已經取消就不改畫面。
// 只進 App target。

enum UtilityBillPhotoReader {
    /// 照片檔名 → 檔案位置（UtilityPayment 的收據資料夾）；PDF 跳過、從最新往前最多 3 張
    static func urls(for names: [String]) -> [URL] {
        var out: [URL] = []
        for n in UtilityBillOCR.readableNames(names) {
            out.append(UtilityPayment.photosDirectory.appendingPathComponent(n))
        }
        return out
    }

    /// 一張一張讀（從新到舊），第一張讀到度數或期間的就停（[review flow-1] 只有金額的超商收據不停，繼續讀舊的帳單）；
    /// 挑哪一張照 UtilityBillOCR.pick；什麼都沒有、或被取消 → nil
    static func read(urls: [URL], paidOn: Date, type: UtilityType) async -> UtilityBillReading? {
        var results: [UtilityBillReading] = []
        for url in urls {
            if Task.isCancelled { return nil }
            let boxes: [UtilityOCRBox] = await recognize(url: url)
            if Task.isCancelled { return nil }
            let lines: [String] = UtilityBillOCR.rows(from: boxes)
            let r: UtilityBillReading = UtilityBillOCR.parse(lines: lines, paidOn: paidOn, type: type)
            results.append(r)
            if r.hasUsageOrPeriod { break }
        }
        return UtilityBillOCR.pick(results)
    }

    /// 一張照片 → 每一塊字和位置（背景執行緒）。讀不到、壞檔、拋錯一律空的
    static func recognize(url: URL) async -> [UtilityOCRBox] {
        await withCheckedContinuation { (cont: CheckedContinuation<[UtilityOCRBox], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let boxes: [UtilityOCRBox] = autoreleasepool { Self.recognizeNow(url: url) }
                cont.resume(returning: boxes)
            }
        }
    }

    /// 同步版（只在背景執行緒叫）：縮圖 → Vision → 每一塊字和位置
    private static func recognizeNow(url: URL) -> [UtilityOCRBox] {
        guard let image = Self.downsampled(url: url) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // 數字不要被「改正」成字（照 WealthVault.recognizeLines）
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let observations: [VNRecognizedTextObservation] = request.results ?? []
        // [review parse-1] 橫的座標乘上寬高比（跟直的同一個單位），四個角才算得出真的斜度
        let aspect: Double = image.height > 0 ? Double(image.width) / Double(image.height) : 1
        var out: [UtilityOCRBox] = []
        for o in observations {
            guard let text = o.topCandidates(1).first?.string else { continue }
            let b: CGRect = o.boundingBox
            let tl: CGPoint = o.topLeft
            let tr: CGPoint = o.topRight
            let bl: CGPoint = o.bottomLeft
            out.append(UtilityOCRBox(text: text, minX: Double(b.minX) * aspect, minY: Double(b.minY),
                                     maxX: Double(b.maxX) * aspect, maxY: Double(b.maxY),
                                     dirX: Double(tr.x - tl.x) * aspect, dirY: Double(tr.y - tl.y),
                                     upX: Double(tl.x - bl.x) * aspect, upY: Double(tl.y - bl.y)))
        }
        return out
    }

    /// ImageIO 縮圖（長邊 ≤ 2000、照 EXIF 轉正；照 ThumbnailCache.downsample）
    private static func downsampled(url: URL) -> CGImage? {
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, srcOpts) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(UtilityBillOCR.maxPixel)
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}
