import Foundation
import SwiftUI
import UIKit
import MapKit
import CoreLocation
import ImageIO

// MARK: - 時間軸卡片的主圖與城市名（v25.517）
//
// 卡片左邊那張滿高的照片從哪裡來、照片上手寫的「Fukuoka」從哪裡來。
//
// 主圖的順序：
//   1. 使用者自己替這一站加的照片（本機檔，零網路）。[v25.519] 是哪一張由「封面」決定
//      （TripStop.coverPhotoURL：指定的那張，或自動的第一張）；封面指定成衛星空照時跳過這一層
//   2. 這一站座標的**衛星**快照（MKMapSnapshotter；有座標就一定拿得到）
//   3. 沒有座標：當天色的街角線稿（畫面上自己畫，不是假照片）
//
// Look Around 實景**這一版刻意不用**：用座標建的場景沒有方向，Apple 也沒有
// 任何方法設定快照的朝向，拍到的常常是對街一面不相干的牆。用 POI 建的場景
// 要先把 MKMapItem 的 identifier 存進 TripStop，而且要實機確認鏡頭真的對著
// 那棟建築才值得開。見規格「第二階段」。
//
// ⚠️ 所有打 Apple 伺服器的事（地圖快照、逆地理編碼）排同一條隊、一次一個。
//    時間軸是非 lazy 的 VStack，展開的那幾天所有卡一次建好；各自打出去就是
//    三、四十個請求同時飛，會被節流到全部失敗（RestaurantSearch 的距離解析、
//    TripRouter 的路線補算都踩過同一個坑）。另外，請求只在卡片**捲進畫面**
//    時才排隊（onScrollVisibilityChange），捲出去就撤掉還沒開始的那些。

// MARK: - 排隊

/// 一次只放一個請求過去的閘門。後進先做：使用者一路滑到底時，
/// 眼前那幾張先出圖，滑過去的那些反正已經看不到了。
///
/// 等待中的工作所屬的 Task 被取消（卡片捲出畫面）就直接離隊，不佔位置。
/// 已經在飛的那一個讓它跑完，結果照樣進快取。
@MainActor
final class TripHeroGate {
    static let shared = TripHeroGate()

    private var busy = false
    private var waiters: [(id: UUID, resume: CheckedContinuation<Bool, Never>)] = []
    /// 被 Apple 節流之後整條隊伍停到這個時間
    private var pausedUntil: Date?

    private init() {}

    /// 排隊。回 false＝排的時候被取消了（呼叫端直接放棄，不要 release）。
    func acquire() async -> Bool {
        if Task.isCancelled { return false }
        if !busy {
            busy = true
            return true
        }
        let id = UUID()
        let granted = await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                waiters.append((id: id, resume: cont))
            }
        } onCancel: {
            Task { @MainActor in TripHeroGate.shared.leave(id) }
        }
        // 輪到了，但在輪到之前就已經被取消：把位置讓給下一個
        if granted && Task.isCancelled {
            release()
            return false
        }
        return granted
    }

    /// 用完一定要還（acquire 回 true 之後，用 defer 呼叫）
    func release() {
        if let next = waiters.popLast() {
            // busy 維持 true：位置直接交給下一個
            next.resume.resume(returning: true)
        } else {
            busy = false
        }
    }

    private func leave(_ id: UUID) {
        guard let i = waiters.firstIndex(where: { $0.id == id }) else { return }
        let w = waiters.remove(at: i)
        w.resume.resume(returning: false)
    }

    /// 被節流了：整條隊伍停一下再說
    func pause(seconds: TimeInterval) {
        pausedUntil = Date().addingTimeInterval(seconds)
    }

    /// 拿到位置之後、真的打出去之前呼叫。回 false＝等的時候被取消了。
    func waitIfPaused() async -> Bool {
        if let until = pausedUntil {
            let wait = until.timeIntervalSinceNow
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            } else {
                pausedUntil = nil
            }
        }
        return !Task.isCancelled
    }
}

// MARK: - 主圖

/// ⚠️ 類別本身刻意**不**標 @MainActor（理由同 TripWeatherStore）：只在會動到
///    狀態的方法上標。
final class TripHeroStore {
    static let shared = TripHeroStore()

    /// 衛星快照的尺寸（點）。直式，蓋得住 375～440 寬的照片欄（103～133pt）
    /// 與一般卡片高度（150～260pt）；更高的卡 scaledToFill 稍微放大，看不出來。
    static let snapshotSize = CGSize(width: 140, height: 240)

    /// 快照底部**可能**帶著 Apple 地圖的標誌與法律聲明。照片左下的膠囊與購物車
    /// 要讓開這麼多，不能蓋住它（地圖的使用條款）。
    /// ⚠️ 實機確認：快照上如果沒有那行字，這裡改成 0。
    static let mapAttributionInset: CGFloat = 16

    private let memory = NSCache<NSString, UIImage>()
    /// 失敗過的 key → 什麼時候失敗的。冷卻時間內不重拍——不自動重試到天荒地老；
    /// 冷卻過後，卡片捲出再捲回來（.task 重跑）才會再試一次。
    ///
    /// 不能是「這次開 App 不再試」（審查抓到）：離線（飛航模式、出國沒開漫遊）打開
    /// 行程頁時，畫面上每一站都會被記成失敗，網路恢復後在整個 App 存活期間都只剩
    /// 線稿，而主圖沒有天氣膠囊那種「重試」的入口。iOS 的 App 常常一放好幾天。
    private var failedAt: [String: Date] = [:]
    private static let retryCooldown: TimeInterval = 300

    private init() {
        // 非 lazy 的時間軸不會銷毀列；記憶體上限由這裡控制，不靠列自己
        memory.countLimit = 32
        memory.totalCostLimit = 48 * 1024 * 1024
    }

    /// Caches/TripHero/。系統可以清掉、不進備份；清掉了重拍就好。
    /// ⚠️ 絕對不能放 Documents/TripStopPhotos：那個資料夾會被 PhotoCloudSync
    ///    上傳到 iCloud，快照不是使用者的照片。
    static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("TripHero", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 使用者自己的照片（降採樣到主圖大小）。檔案還沒從 iCloud 下來就回 nil，
    /// 呼叫端退到下一層。
    @MainActor
    func photo(_ url: URL, maxPixel: CGFloat = 720) async -> UIImage? {
        let key = "photo#" + url.lastPathComponent + "#\(Int(maxPixel))"
        if let hit = memory.object(forKey: key as NSString) { return hit }
        guard let img = await Self.decode(url, maxPixel: maxPixel) else { return nil }
        memory.setObject(img, forKey: key as NSString, cost: Self.cost(img))
        return img
    }

    /// 這個座標的衛星快照，中間偏左上畫一顆不帶號碼的針（號碼已經在左上角）。
    @MainActor
    func satellite(_ c: CLLocationCoordinate2D, pin: UIColor, pinKey: Int,
                   scale: CGFloat) async -> UIImage? {
        let s = max(1, min(3, scale.rounded()))
        let key = "sat_v1_" + String(format: "%.4f_%.4f", c.latitude, c.longitude)
            + "_\(Int(Self.snapshotSize.width))x\(Int(Self.snapshotSize.height))"
            + "@\(Int(s))_c\(pinKey)"
        if let hit = memory.object(forKey: key as NSString) { return hit }
        let file = Self.directory.appendingPathComponent(key + ".jpg")
        if let img = await diskHit(file, key: key) { return img }
        if let t = failedAt[key], Date().timeIntervalSince(t) < Self.retryCooldown { return nil }

        let gate = TripHeroGate.shared
        guard await gate.acquire() else { return nil }
        defer { gate.release() }
        guard await gate.waitIfPaused() else { return nil }
        // 排隊的時候，別張卡（同一個座標的另一站）可能已經拍好了
        if let img = await diskHit(file, key: key) { return img }

        do {
            let snap = try await MKMapSnapshotter(options: Self.options(c, scale: s)).start()
            let img = Self.drawPin(snap, at: c, color: pin, scale: s)
            memory.setObject(img, forKey: key as NSString, cost: Self.cost(img))
            await Self.writeJPEG(img, to: file)
            return img
        } catch {
            // 被取消不算失敗（捲出畫面而已，下次捲回來再拍）
            if Task.isCancelled { return nil }
            if let mk = error as? MKError, mk.code == .loadingThrottled {
                gate.pause(seconds: 45)
            } else {
                failedAt[key] = Date()
            }
            return nil
        }
    }

    // MARK: 內部

    @MainActor
    private func diskHit(_ file: URL, key: String) async -> UIImage? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let px = max(Self.snapshotSize.width, Self.snapshotSize.height) * 3
        guard let img = await Self.decode(file, maxPixel: px) else { return nil }
        memory.setObject(img, forKey: key as NSString, cost: Self.cost(img))
        return img
    }

    private static func options(_ c: CLLocationCoordinate2D,
                                scale: CGFloat) -> MKMapSnapshotter.Options {
        let size = snapshotSize
        // 縱向 420 公尺：看得出街廓與河道，又不會小到只剩一片屋頂
        let spanLat: CLLocationDistance = 420
        let spanLon = spanLat * Double(size.width / size.height)
        // 針放在照片 (45%, 38%) 的位置：右緣是波浪切線、左下有城市名與膠囊，
        // 擺正中間會被擋住。所以中心點往東、往南偏。
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = max(1, 111_320.0 * cos(c.latitude * .pi / 180))
        let center = CLLocationCoordinate2D(
            latitude: c.latitude - (0.5 - 0.38) * spanLat / metersPerDegLat,
            longitude: c.longitude + (0.5 - 0.45) * spanLon / metersPerDegLon)
        let o = MKMapSnapshotter.Options()
        o.region = MKCoordinateRegion(center: center,
                                      latitudinalMeters: spanLat,
                                      longitudinalMeters: spanLon)
        o.size = size
        o.scale = scale
        // 衛星：照片質感、色調偏暗，白字讀得到；沒有任何文字（「可以被看見，
        // 不可以被讀」）；不分深淺色模式，一個座標一份快取就夠
        // 舊屬性 pointOfInterestFilter 要設在 preferredConfiguration **前面**：它是被
        // preferredConfiguration 取代的舊介面，事後再設有可能把設定蓋回標準地圖。
        // （衛星圖本來就沒有 POI，這行只是保險）
        o.pointOfInterestFilter = .excludingAll
        o.preferredConfiguration = MKImageryMapConfiguration()
        return o
    }

    private static func drawPin(_ snap: MKMapSnapshotter.Snapshot,
                                at c: CLLocationCoordinate2D,
                                color: UIColor, scale: CGFloat) -> UIImage {
        let size = snap.image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            snap.image.draw(at: .zero)
            let p = snap.point(for: c)
            guard p.x > -20, p.y > -20,
                  p.x < size.width + 20, p.y < size.height + 20 else { return }
            let cg = ctx.cgContext
            cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                         color: UIColor.black.withAlphaComponent(0.45).cgColor)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)).fill()
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)).fill()
        }
    }

    private static func writeJPEG(_ image: UIImage, to url: URL) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                if let data = image.jpegData(compressionQuality: 0.82) {
                    try? data.write(to: url, options: .atomic)
                }
                cont.resume()
            }
        }
    }

    private static func decode(_ url: URL, maxPixel: CGFloat) async -> UIImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: downsample(url, maxPixel: maxPixel))
            }
        }
    }

    /// 同 ThumbnailCache.downsample（那支是 private）：ImageIO 降採樣、套 EXIF 轉向
    private static func downsample(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, srcOpts) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(1, maxPixel))
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    private static func cost(_ img: UIImage) -> Int {
        Int(img.size.width * img.scale * img.size.height * img.scale * 4)
    }
}

// MARK: - 城市名

/// 從地址切出城市名（給天氣膠囊的「福岡・晴時多雲」），
/// 再查出羅馬拼音（給照片上手寫的「Fukuoka」）。
///
/// 切法的前提來自 TripAddress.tidy 的觀察：日文地址的縣市區町本來就是連著寫的，
/// 所以從開頭比對是可行的。切不出來就回 nil——**不顯示，不猜**。
/// Python 原型跑過 43 個案例全對（scratchpad/proto/city.py）。
enum TripPlaceName {
    struct Place: Hashable {
        /// "JP"／"TW"
        let country: String
        /// 顯示用的中文城市名（字形統一成繁中：廣島、鹿兒島）
        let zh: String
        /// 快取用的 key（"JP|福岡縣|福岡"）
        let key: String
    }

    static func parse(_ raw: String) -> Place? {
        var s = stripPostal(Array(raw.trimmingCharacters(in: .whitespacesAndNewlines)))
        for prefix in countryPrefixes {
            let p = Array(prefix)
            if s.starts(with: p) {
                s = Array(s.dropFirst(p.count))
                break
            }
        }
        s = stripPostal(s)
        guard !s.isEmpty else { return nil }
        let norm: [Character] = s.map { variants[$0] ?? $0 }

        // 台灣：第一級縣市就是答案（一律不往下取鄉鎮：22 筆的拼音可以全部內建）
        for name in taiwanTop {
            let n = Array(name)
            if norm.starts(with: n) {
                return Place(country: "TW", zh: String(n.dropLast()), key: "TW|" + name)
            }
        }
        // 日本：先比對都道府縣的完整名稱（「京都府」才不會被當成「京」＋「都」）
        for pref in japanPrefectures {
            let pc = Array(pref)
            guard norm.starts(with: pc) else { continue }
            let rest = Array(norm.dropFirst(pc.count))
            guard let city = japanCity(pref: pref, rest: rest) else { return nil }
            return Place(country: "JP", zh: city, key: "JP|" + pref + "|" + city)
        }
        return nil
    }

    /// 內建表查得到的羅馬拼音（大部分情況不必連網）
    static func romaji(_ place: Place) -> String? {
        switch place.country {
        case "TW": return taiwanRomaji[place.zh.replacingOccurrences(of: "臺", with: "台")]
        case "JP": return japanRomaji[place.zh]
        default: return nil
        }
    }

    /// "JP" → "JAPAN"。不用連網。
    static func countryName(_ code: String) -> String {
        (Locale(identifier: "en_US").localizedString(forRegionCode: code) ?? code).uppercased()
    }

    // MARK: 日本的市町村

    private static func japanCity(pref: String, rest: [Character]) -> String? {
        let n = rest.count
        guard n >= 2 else { return nil }
        /// 空的範圍不會當掉（lo > hi 時回空範圍）
        func span(_ lo: Int, _ hi: Int) -> Range<Int> { lo < hi ? lo..<hi : lo..<lo }

        // (a) 東京 23 區：「區」比「市」先出現（或根本沒有市）→ 東京
        if pref == "東京都" {
            let ku = span(0, min(8, n)).first { rest[$0] == "區" }
            let shi = span(0, min(8, n)).first { rest[$0] == "市" }
            if let ku, shi.map({ ku < $0 }) ?? true { return "東京" }
        }
        // (b) 郡：跳過郡名，取到町／村為止（恩納、箱根、本部）。
        //     郡名、町村名都不能含「市」——排除「大和郡山市」
        if let g = span(1, min(6, n)).first(where: { rest[$0] == "郡" }),
           !rest[0..<g].contains("市") {
            let after = Array(rest[(g + 1)...])
            if let k = span(1, min(7, after.count)).first(where: { after[$0] == "町" || after[$0] == "村" }),
               !after[0..<k].contains("市") {
                return String(after[0..<k])
            }
        }
        // (c) 市：從第 2 個字開始找（市川市、市原市）；「市市」吃到後一個（四日市市、廿日市市）
        for i in span(1, min(9, n)) where rest[i] == "市" {
            if i + 1 < n, rest[i + 1] == "市" { return String(rest[0...i]) }
            return String(rest[0..<i])
        }
        // (d) 沒有郡的町村（「神奈川縣箱根町」）
        if let k = span(1, min(8, n)).first(where: { rest[$0] == "町" || rest[$0] == "村" }) {
            return String(rest[0..<k])
        }
        // (e) 切不出來
        return nil
    }

    // MARK: 前處理

    /// 去掉開頭的〒、空白、郵遞區號。
    ///
    /// ⚠️ 只認 ASCII 0-9、全形０-９與連字號。**不能用 Character.isNumber**：
    ///    三、千、一、八、九、十在 Unicode 都有數值，「三重縣」「千葉縣」的
    ///    第一個字會被當成數字吃掉。
    private static func stripPostal(_ chars: [Character]) -> [Character] {
        var i = 0
        while i < chars.count, chars[i] == " " || chars[i] == "　" { i += 1 }
        if i < chars.count, chars[i] == "〒" {
            i += 1
            while i < chars.count, chars[i] == " " || chars[i] == "　" { i += 1 }
        }
        var j = i
        var digits = 0
        while j < chars.count, isPostalChar(chars[j]) {
            if chars[j] != "-" && chars[j] != "－" { digits += 1 }
            j += 1
        }
        if digits >= 3 {
            i = j
            while i < chars.count, chars[i] == " " || chars[i] == "　" { i += 1 }
        }
        return i < chars.count ? Array(chars[i...]) : []
    }

    private static let asciiDigits: ClosedRange<Character> = "0"..."9"
    private static let wideDigits: ClosedRange<Character> = "０"..."９"

    private static func isPostalChar(_ c: Character) -> Bool {
        asciiDigits.contains(c) || wideDigits.contains(c) || c == "-" || c == "－"
    }

    private static let countryPrefixes = ["日本國", "日本", "臺灣", "台灣", "中華民國"]

    /// 日文字形 → 繁中字形（只收縣名與常見地名會撞到的）
    private static let variants: [Character: Character] = [
        "県": "縣", "区": "區", "広": "廣", "児": "兒", "静": "靜", "徳": "德",
        "縄": "繩", "沢": "澤", "浜": "濱", "横": "橫", "戸": "戶", "覇": "霸",
        "渋": "澁", "国": "國", "竜": "龍", "瀬": "瀨", "辺": "邊", "斎": "齋",
        "帯": "帶", "軽": "輕", "姫": "姬", "関": "關", "湾": "灣", "栄": "榮",
        "黒": "黑"
    ]

    private static let taiwanTop: [String] = [
        "台北市", "臺北市", "新北市", "桃園市", "台中市", "臺中市", "台南市", "臺南市",
        "高雄市", "基隆市", "新竹市", "嘉義市", "新竹縣", "苗栗縣", "彰化縣", "南投縣",
        "雲林縣", "嘉義縣", "屏東縣", "宜蘭縣", "花蓮縣", "台東縣", "臺東縣", "澎湖縣",
        "金門縣", "連江縣"
    ]

    private static let japanPrefectures: [String] = [
        "北海道", "青森縣", "岩手縣", "宮城縣", "秋田縣", "山形縣", "福島縣", "茨城縣",
        "栃木縣", "群馬縣", "埼玉縣", "千葉縣", "東京都", "神奈川縣", "新潟縣", "富山縣",
        "石川縣", "福井縣", "山梨縣", "長野縣", "岐阜縣", "靜岡縣", "愛知縣", "三重縣",
        "滋賀縣", "京都府", "大阪府", "兵庫縣", "奈良縣", "和歌山縣", "鳥取縣", "島根縣",
        "岡山縣", "廣島縣", "山口縣", "德島縣", "香川縣", "愛媛縣", "高知縣", "福岡縣",
        "佐賀縣", "長崎縣", "熊本縣", "大分縣", "宮崎縣", "鹿兒島縣", "沖繩縣"
    ]

    private static let taiwanRomaji: [String: String] = [
        "台北": "Taipei", "新北": "New Taipei", "桃園": "Taoyuan", "台中": "Taichung",
        "台南": "Tainan", "高雄": "Kaohsiung", "基隆": "Keelung", "新竹": "Hsinchu",
        "嘉義": "Chiayi", "苗栗": "Miaoli", "彰化": "Changhua", "南投": "Nantou",
        "雲林": "Yunlin", "屏東": "Pingtung", "宜蘭": "Yilan", "花蓮": "Hualien",
        "台東": "Taitung", "澎湖": "Penghu", "金門": "Kinmen", "連江": "Matsu"
    ]

    /// 縣名（去掉縣府都）、20 個政令市、常見觀光地。赫本式、不帶長音符號
    /// （Snell Roundhand 不一定有 ō 這些字形）。
    private static let japanRomaji: [String: String] = [
        // 都道府縣
        "北海道": "Hokkaido", "青森": "Aomori", "岩手": "Iwate", "宮城": "Miyagi",
        "秋田": "Akita", "山形": "Yamagata", "福島": "Fukushima", "茨城": "Ibaraki",
        "栃木": "Tochigi", "群馬": "Gunma", "埼玉": "Saitama", "千葉": "Chiba",
        "東京": "Tokyo", "神奈川": "Kanagawa", "新潟": "Niigata", "富山": "Toyama",
        "石川": "Ishikawa", "福井": "Fukui", "山梨": "Yamanashi", "長野": "Nagano",
        "岐阜": "Gifu", "靜岡": "Shizuoka", "愛知": "Aichi", "三重": "Mie",
        "滋賀": "Shiga", "京都": "Kyoto", "大阪": "Osaka", "兵庫": "Hyogo",
        "奈良": "Nara", "和歌山": "Wakayama", "鳥取": "Tottori", "島根": "Shimane",
        "岡山": "Okayama", "廣島": "Hiroshima", "山口": "Yamaguchi", "德島": "Tokushima",
        "香川": "Kagawa", "愛媛": "Ehime", "高知": "Kochi", "福岡": "Fukuoka",
        "佐賀": "Saga", "長崎": "Nagasaki", "熊本": "Kumamoto", "大分": "Oita",
        "宮崎": "Miyazaki", "鹿兒島": "Kagoshima", "沖繩": "Okinawa",
        // 政令市（與縣名重複的已在上面）
        "札幌": "Sapporo", "仙台": "Sendai", "川崎": "Kawasaki", "橫濱": "Yokohama",
        "相模原": "Sagamihara", "濱松": "Hamamatsu", "名古屋": "Nagoya", "堺": "Sakai",
        "神戶": "Kobe", "北九州": "Kitakyushu",
        // 常見觀光地
        "函館": "Hakodate", "小樽": "Otaru", "旭川": "Asahikawa", "富良野": "Furano",
        "美瑛": "Biei", "釧路": "Kushiro", "帶廣": "Obihiro", "登別": "Noboribetsu",
        "弘前": "Hirosaki", "盛岡": "Morioka", "日光": "Nikko", "宇都宮": "Utsunomiya",
        "草津": "Kusatsu", "川越": "Kawagoe", "秩父": "Chichibu", "成田": "Narita",
        "浦安": "Urayasu", "鎌倉": "Kamakura", "箱根": "Hakone", "橫須賀": "Yokosuka",
        "熱海": "Atami", "伊東": "Ito", "下田": "Shimoda", "沼津": "Numazu",
        "御殿場": "Gotemba", "富士河口湖": "Fujikawaguchiko", "輕井澤": "Karuizawa",
        "松本": "Matsumoto", "金澤": "Kanazawa", "高山": "Takayama", "白川": "Shirakawa",
        "下呂": "Gero", "伊勢": "Ise", "鳥羽": "Toba", "宇治": "Uji", "姬路": "Himeji",
        "白濱": "Shirahama", "倉敷": "Kurashiki", "尾道": "Onomichi", "廿日市": "Hatsukaichi",
        "出雲": "Izumo", "松江": "Matsue", "下關": "Shimonoseki", "萩": "Hagi",
        "岩國": "Iwakuni", "高松": "Takamatsu", "松山": "Matsuyama", "太宰府": "Dazaifu",
        "糸島": "Itoshima", "久留米": "Kurume", "柳川": "Yanagawa", "宗像": "Munakata",
        "別府": "Beppu", "由布": "Yufu", "佐世保": "Sasebo", "嬉野": "Ureshino",
        "唐津": "Karatsu", "阿蘇": "Aso", "指宿": "Ibusuki", "霧島": "Kirishima",
        "那霸": "Naha", "恩納": "Onna", "本部": "Motobu", "北谷": "Chatan",
        "宜野灣": "Ginowan", "名護": "Nago", "石垣": "Ishigaki", "宮古島": "Miyakojima"
    ]
}

/// 內建表查不到的城市，用逆地理編碼（en_US）補羅馬拼音。
///
/// 去重的 key 用「切出來的城市」，整趟福岡行程扣掉表裡查得到的，大概只剩 0～3 次
/// 請求；地址切不出來才退回座標 %.2f（約 1 公里——0.1° 太粗：福岡市、春日、
/// 太宰府彼此只隔 10 公里左右，台北和新北的邊界就在市區裡）。
///
/// 成功的結果寫進 Caches/TripHero/places.json，城市名不會變，一直留著；
/// 失敗只記在記憶體：查到了但沒有可用的名字＝這次開 App 不再查（再查也一樣）；
/// 網路錯誤＝冷卻 5 分鐘（離線時打開行程頁，網路回來後才補得回來）。
///
/// ⚠️ 類別不標 @MainActor（View 用 @StateObject 指向 .shared，理由同 TripWeatherStore）。
/// ⚠️ CLGeocoder 在 iOS 26 SDK 標成已淘汰：這是警告不是錯誤，部署目標 18.0，
///    18～25 只有它可用。換 MKReverseGeocodingRequest 要用 Xcode 26 實測 async 寫法，
///    這一版不動。
final class TripPlaceNameStore: ObservableObject {
    static let shared = TripPlaceNameStore()

    struct Resolved: Codable, Equatable {
        let romaji: String
        let country: String
    }

    @Published private(set) var geocoded: [String: Resolved] = [:]
    private var inFlight: Set<String> = []
    /// 失敗過的 key → 什麼時候才可以再查（Date.distantFuture＝這次開 App 不再查）
    private var retryAfter: [String: Date] = [:]

    private init() {
        geocoded = Self.loadFromDisk()
    }

    /// 這一站要手寫什麼。nil＝不寫（不猜）。
    func resolved(place: TripPlaceName.Place?,
                  coordinate: CLLocationCoordinate2D?) -> Resolved? {
        if let place, let r = TripPlaceName.romaji(place) {
            return Resolved(romaji: r, country: TripPlaceName.countryName(place.country))
        }
        guard let key = Self.key(place: place, coordinate: coordinate) else { return nil }
        return geocoded[key]
    }

    /// 卡片捲進畫面時呼叫。內建表查得到、已經查過、正在查、失敗後還在冷卻，都直接返回。
    @MainActor
    func resolveIfNeeded(place: TripPlaceName.Place?,
                         coordinate: CLLocationCoordinate2D?) async {
        if let place, TripPlaceName.romaji(place) != nil { return }
        guard let coordinate,
              let key = Self.key(place: place, coordinate: coordinate),
              geocoded[key] == nil, !inFlight.contains(key),
              (retryAfter[key] ?? Date.distantPast) <= Date()
        else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        let gate = TripHeroGate.shared
        guard await gate.acquire() else { return }
        defer { gate.release() }
        guard await gate.waitIfPaused() else { return }

        do {
            let marks = try await CLGeocoder().reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                preferredLocale: Locale(identifier: "en_US"))
            guard let mark = marks.first,
                  let name = Self.cleanRomaji(mark.locality
                                              ?? mark.subAdministrativeArea
                                              ?? mark.administrativeArea),
                  let iso = mark.isoCountryCode
            else {
                // 查到了、但切不出能寫的名字：再查也是同一個答案
                retryAfter[key] = Date.distantFuture
                return
            }
            geocoded[key] = Resolved(romaji: name, country: TripPlaceName.countryName(iso))
            saveToDisk()
        } catch {
            if Task.isCancelled { return }
            // 網路錯誤（含離線）：冷卻 5 分鐘，之後卡片捲回畫面時再查
            retryAfter[key] = Date().addingTimeInterval(300)
            // CLError.network 也是「超過速率」的那個錯誤：整條隊伍停一分鐘
            if let cl = error as? CLError, cl.code == .network { gate.pause(seconds: 60) }
        }
    }

    private static func key(place: TripPlaceName.Place?,
                            coordinate: CLLocationCoordinate2D?) -> String? {
        if let place { return place.key }
        guard let c = coordinate else { return nil }
        return "geo|" + String(format: "%.2f,%.2f", c.latitude, c.longitude)
    }

    /// "Fukuoka-shi" → "Fukuoka"、"Ōita" → "Oita"。不是純 ASCII 就丟掉。
    static func cleanRomaji(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        let suffixes = [" City", "-shi", " Shi", " Ward", "-ku", " Town", "-machi", "-cho",
                        " Village", "-mura", " Township", " District", " County", "-gun"]
        for suffix in suffixes where s.hasSuffix(suffix) && s.count > suffix.count + 1 {
            s = String(s.dropLast(suffix.count))
            break
        }
        s = s.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US"))
        let ok = s.unicodeScalars.allSatisfy { u in
            (u.value >= 65 && u.value <= 90) || (u.value >= 97 && u.value <= 122)
                || u == " " || u == "-" || u == "'"
        }
        return ok ? s : nil
    }

    private static var fileURL: URL {
        TripHeroStore.directory.appendingPathComponent("places.json")
    }

    private static func loadFromDisk() -> [String: Resolved] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: Resolved].self, from: data)
        else { return [:] }
        return dict
    }

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(geocoded) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
