import Foundation
import SwiftUI
import WeatherKit
import CoreLocation

// MARK: - 行程天氣預報（v25.435）
//
// 排行程時最想先知道的一件事就是「那天會不會下雨」。資料來源用 Apple 的
// WeatherKit：不必在這個公開的專案裡放任何 API 金鑰（走的是 App 自己的
// entitlement），而且中文在地化與圖示都是系統給的。
//
// ⚠️ 三件必須誠實面對的限制，畫面上都要講出來而不是含糊帶過：
//
//   1. **只有未來十天**。WeatherKit 的每日預報大約十天，三個月後的行程
//      拿不到任何東西。這種時候寧可什麼都不顯示並說明原因，也不要給一個
//      看起來很像預報的東西——排行程的人會真的照著它決定帶不帶雨具。
//   2. **要有座標**。沒選到地點的景點連問都不能問。
//   3. **要在 Apple Developer 後台替 App ID 開啟 WeatherKit 能力**，
//      並保留 entitlement。沒開的話這裡會安靜地拿不到資料（不會崩），
//      畫面上會顯示「天氣暫時取不到」。
//
// 另外，Apple 規定使用 WeatherKit 必須標示出處並附上法律連結，
// 所以有天氣顯示的地方一定要一起顯示 TripWeatherStore.attributionURL。

/// 某個地點某一天的預報，只留畫面上真的會用到的欄位
struct TripDayWeather: Equatable {
    /// SF Symbol 名稱，系統給的（sun.max、cloud.rain…）
    let symbolName: String
    /// 中文描述（晴、多雲時陰、短暫陣雨…）
    let conditionText: String
    /// 攝氏高低溫
    let highC: Double
    let lowC: Double
    /// 降雨機率 0…1
    let precipitationChance: Double

    /// 「28°／21°」。溫度一律取整數——預報精確到小數點是假的精準。
    var temperatureText: String {
        "\(Int(highC.rounded()))°／\(Int(lowC.rounded()))°"
    }

    /// 要不要提醒帶傘。30% 以下講出來只是雜訊，那是「可能會飄一下」的等級。
    var showsRain: Bool { precipitationChance >= 0.3 }

    var rainText: String { "\(Int((precipitationChance * 100).rounded()))%" }

    // MARK: [v25.448] 排行程真正用得到的那幾項

    /// 紫外線指數與分級。夏天的戶外行程，這比「晴」有用得多
    let uvIndex: Int
    let uvLabel: String
    /// 風速（km/h）與風向
    let windKmh: Double
    let windDirection: String
    /// 日出日落。排行程最實際的一件事就是「幾點天黑」——
    /// 看夜景要等天黑，逛古蹟要趕在天黑前
    let sunrise: Date?
    let sunset: Date?

    var dayNightGap: Int { Int((highC - lowC).rounded()) }

    /// 依數字算出來的提醒。
    ///
    /// ⚠️ 全部是門檻判斷，沒有一句是憑空生出來的建議：
    ///    有數字才有那一句，數字不到門檻就不出現。寧可少講，
    ///    也不要讓人以為 App 有什麼它其實沒有的洞察。
    var tips: [(icon: String, text: String)] {
        var out: [(String, String)] = []
        if precipitationChance >= 0.6 {
            out.append(("umbrella.fill", "降雨機率 \(rainText)，傘直接帶著"))
        } else if precipitationChance >= 0.3 {
            out.append(("umbrella", "有 \(rainText) 的機會下雨，摺傘放包裡"))
        }
        if lowC <= 15 {
            out.append(("thermometer.snowflake", "早晚只有 \(Int(lowC.rounded()))°，外套要帶"))
        } else if dayNightGap >= 10 {
            out.append(("thermometer", "日夜溫差 \(dayNightGap)°，洋蔥式穿法"))
        }
        if highC >= 32 {
            out.append(("drop.fill", "白天 \(Int(highC.rounded()))°，水帶夠"))
        }
        if uvIndex >= 8 {
            out.append(("sun.max.fill",
                        "紫外線 \(uvIndex)（\(uvLabel)），防曬帽子別省"))
        } else if uvIndex >= 6 {
            out.append(("sun.max.fill", "紫外線 \(uvIndex)（\(uvLabel)），記得防曬"))
        }
        if windKmh >= 40 {
            out.append(("wind", "風很大（\(Int(windKmh.rounded())) km/h），海邊與高處要留意"))
        }
        return out.map { (icon: $0.0, text: $0.1) }
    }
}

/// ⚠️ 類別本身刻意**不**標 @MainActor：那樣一來 `TripWeatherStore.shared`
///    就變成主執行緒隔離的靜態屬性，View 的 `@StateObject private var w = .shared`
///    這種屬性初始化在嚴格併發下會過不了。改成只在真的會動到 @Published 的
///    方法上標 @MainActor——那才是真正需要保護的地方
///    （寫法比照同專案的 LocationProvider.shared）。
final class TripWeatherStore: ObservableObject {
    static let shared = TripWeatherStore()

    /// Apple 規定要顯示的法律出處連結
    static let attributionURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    /// 每日預報大約只有這麼多天。用 10 而不是 API 回幾筆就算幾筆：
    /// 畫面上要先判斷「這一天在不在預報範圍內」才決定要不要發請求，
    /// 不然一趟三個月後的行程會對每一站都白打一次網路。
    static let forecastDays = 10

    /// [v25.473] 一份預報放多久就算舊。
    ///
    /// 每日預報一天之內不會變多少，所以不需要分鐘級的新鮮度；
    /// 但超過一天就不能再叫「預報」了——昨天讀的高低溫掛在今天的行程上，
    /// 旁邊那行「更新於 09:12」還讓人以為是剛剛讀的，比沒有天氣更糟。
    static let maxAge: TimeInterval = 24 * 3600

    /// key＝座標取到小數第 2 位（約 1 公里）。
    ///
    /// 同一個城市裡的二十個景點天氣幾乎一樣，一站一次請求既慢又浪費配額；
    /// 取到公里級之後，一趟市區行程通常只會打一兩次。
    @Published private(set) var cache: [String: [Date: TripDayWeather]] = [:]
    /// [v25.449] 每一份預報「是哪裡、什麼時候讀的」。
    ///
    /// 為什麼要留：快取的 key 是座標取到小數第 2 位（約 1 公里），
    /// 所以同一條街上的幾個景點會共用同一份預報——這是刻意省請求的取捨，
    /// 但使用者有權知道他看的這份是以哪一點查的。
    /// 另外 Apple 回的觀測點不一定就是你問的那一點（它有自己的網格），
    /// 差得遠的時候更應該講出來。
    @Published private(set) var sources: [String: SourceInfo] = [:]

    struct SourceInfo: Equatable {
        /// 這份預報實際是以哪一個座標查的（我們送出去的那一點）
        let requested: CLLocationCoordinate2D
        /// Apple 說這份資料對應的位置
        let resolved: CLLocationCoordinate2D
        /// 資料讀取時間
        let readAt: Date

        /// 問的點與 Apple 的觀測點差多遠（公尺）
        var offsetMeters: CLLocationDistance {
            CLLocation(latitude: requested.latitude, longitude: requested.longitude)
                .distance(from: CLLocation(latitude: resolved.latitude,
                                           longitude: resolved.longitude))
        }

        static func == (a: SourceInfo, b: SourceInfo) -> Bool {
            a.readAt == b.readAt
                && a.requested.latitude == b.requested.latitude
                && a.requested.longitude == b.requested.longitude
        }
    }
    /// 問過但失敗的：key → 失敗原因。
    ///
    /// [v25.437] 原本只記一個「有沒有失敗」的布林值，畫面上就只能寫
    /// 「天氣暫時取不到」——使用者看不出是沒網路、是能力沒開、還是這個座標
    /// 本來就沒資料，我也沒辦法從回報裡判斷。錯誤訊息是唯一的線索，
    /// 吞掉它等於把唯一的線索丟了。
    @Published private(set) var failures: [String: String] = [:]
    /// 正在飛的請求，避免同一個 key 被二十個景點同時觸發。
    ///
    /// [v25.473] 改成 @Published：手動更新那顆按鈕要能轉圈，
    /// 而「正在抓」只有這裡知道。
    @Published private(set) var inFlight: Set<String> = []

    private init() {}

    static func key(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.2f,%.2f", c.latitude, c.longitude)
    }

    /// 紫外線分級的中文。自己對照而不是用系統的 description：
    /// 那個字串是跟著系統語言走的，而這個 App 的介面一律是繁中。
    static func uvLabel(_ category: UVIndex.ExposureCategory) -> String {
        switch category {
        case .low: return "低"
        case .moderate: return "中等"
        case .high: return "高"
        case .veryHigh: return "很高"
        case .extreme: return "極高"
        @unknown default: return "—"
        }
    }

    /// 這一天有沒有可能拿得到預報（不看網路，只看日期）
    static func isWithinForecastRange(_ date: Date) -> Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let day = cal.startOfDay(for: date)
        guard let diff = cal.dateComponents([.day], from: today, to: day).day else { return false }
        // 過去的日子也沒有預報可看（已經發生了，看行程上的實際打卡比較準）
        return diff >= 0 && diff < forecastDays
    }

    /// 取某地某日的預報。沒有就回 nil——呼叫端負責決定要不要發請求。
    func forecast(at coordinate: CLLocationCoordinate2D, on date: Date) -> TripDayWeather? {
        cache[Self.key(coordinate)]?[Calendar.current.startOfDay(for: date)]
    }

    func source(at coordinate: CLLocationCoordinate2D) -> SourceInfo? {
        sources[Self.key(coordinate)]
    }

    func hasFailed(at coordinate: CLLocationCoordinate2D) -> Bool {
        failures[Self.key(coordinate)] != nil
    }

    /// 失敗原因（已經翻成使用者看得懂的話）
    func failureReason(at coordinate: CLLocationCoordinate2D) -> String? {
        failures[Self.key(coordinate)]
    }

    /// [v25.473] 手上這份預報是不是已經超過一天沒更新。
    ///
    /// 為什麼需要：`load` 原本的第一個條件是「快取裡沒有才抓」，
    /// 所以一份預報一旦進了快取就永遠不會再更新——App 擺在背景過一夜，
    /// 隔天打開看到的還是昨天那份。
    func isStale(at coordinate: CLLocationCoordinate2D) -> Bool {
        isStale(key: Self.key(coordinate))
    }

    private func isStale(key: String) -> Bool {
        // 還沒有資料不叫「舊」，那是「還沒抓」，兩件事的處理方式不一樣
        guard cache[key] != nil else { return false }
        // 有資料卻不知道什麼時候讀的，當成舊的——寧可多打一次請求
        guard let readAt = sources[key]?.readAt else { return true }
        return Date().timeIntervalSince(readAt) > Self.maxAge
    }

    /// 這個座標正在抓（畫面上要轉圈、按鈕要擋住連按）
    func isLoading(at coordinate: CLLocationCoordinate2D) -> Bool {
        inFlight.contains(Self.key(coordinate))
    }

    /// 抓這個地點未來十天的每日預報。
    /// 一次抓完整段，因為 WeatherKit 本來就是一次回一整組，分天問只是多打幾次。
    ///
    /// [v25.473] 三個條件分開寫，因為擋的是三件不一樣的事：
    ///   • 正在飛的不要再打一次（同一個 key 可能被二十個景點同時觸發）
    ///   • 已經有資料、而且還新的，不用再打
    ///   • 失敗過的不要自動重試到天荒地老——要使用者按「更新／重試」才再試
    /// `force` 就是那顆按鈕：三個條件裡只有「正在飛」仍然成立。
    @MainActor
    func load(_ coordinate: CLLocationCoordinate2D, force: Bool = false) async {
        let key = Self.key(coordinate)
        guard !inFlight.contains(key) else { return }
        if !force {
            guard failures[key] == nil else { return }
            guard cache[key] == nil || isStale(key: key) else { return }
        }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let daily = try await WeatherService.shared.weather(for: location, including: .daily)
            var byDay: [Date: TripDayWeather] = [:]
            let cal = Calendar.current
            for day in daily {
                byDay[cal.startOfDay(for: day.date)] = TripDayWeather(
                    symbolName: day.symbolName,
                    conditionText: day.condition.description,
                    highC: day.highTemperature.converted(to: .celsius).value,
                    lowC: day.lowTemperature.converted(to: .celsius).value,
                    precipitationChance: day.precipitationChance,
                    uvIndex: day.uvIndex.value,
                    uvLabel: Self.uvLabel(day.uvIndex.category),
                    windKmh: day.wind.speed.converted(to: .kilometersPerHour).value,
                    windDirection: day.wind.compassDirection.abbreviation,
                    sunrise: day.sun.sunrise,
                    sunset: day.sun.sunset)
            }
            cache[key] = byDay
            sources[key] = SourceInfo(
                requested: coordinate,
                resolved: daily.metadata.location.coordinate,
                readAt: daily.metadata.date)
            // 抓到了就把上一次的失敗記錄清掉，不然畫面會一直掛著
            // 一句已經不成立的錯誤訊息
            failures[key] = nil
        } catch {
            // 失敗的原因多半是幾種：沒網路、App ID 還沒開 WeatherKit 能力、
            // 剛開好還沒生效、或這個座標落在海上。都不該重試到天荒地老，
            // 記下原因就算了——原因要留著，那是使用者回報時唯一的線索。
            //
            // [v25.473] 注意這裡**不動 cache**：過期自動更新失敗時，
            // 手上那份舊預報仍然比一片空白有用（一天前的高低溫還是對的），
            // 畫面另外寫一行「更新失敗，顯示的是上次讀到的」講清楚就好。
            failures[key] = Self.describe(error)
        }
    }

    // [v25.442] 這裡本來想在執行期問「這支 App 有沒有把 WeatherKit 的授權簽進去」，
    // 用的是 SecTaskCreateFromSelf / SecTaskCopyValueForEntitlement——**那是 macOS 專屬的**，
    // iOS 上根本沒有這兩個符號，整包編不過。已經拿掉。
    //
    // iOS 沒有乾淨的方法讀自己的 entitlement：讀 embedded.mobileprovision 只在
    // 開發／TestFlight 版存在（上架版沒有這個檔），而且要解 CMS，代價遠高於價值。
    // 所以退回「看錯誤訊息判斷」——訊息裡帶授權字樣就往那個方向指，其餘照實顯示原文。

    /// 把錯誤翻成使用者看得懂的一句話，後面附上系統原文。
    ///
    /// 原文一定要留：翻譯是我猜的，原文才是事實。猜錯的時候，
    /// 使用者截圖給我看的那一行原文才救得了他。
    static func describe(_ error: Error) -> String {
        let raw = (error as NSError).localizedDescription
        let ns = error as NSError
        // 沒網路是最常見也最容易自己解決的一種，單獨挑出來講
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "看起來是沒有網路。天氣要連線才拿得到。"
            case NSURLErrorTimedOut:
                return "連線逾時，等一下再試。"
            default:
                return "連線出了問題：" + raw
            }
        }
        let lowered = raw.lowercased()
        // [v25.447] WeatherKit 拿不到授權權杖時固定回這一個。
        //
        // WDSJWTAuthenticatorServiceListener 是 WeatherKit 的 JWT 認證器；
        // 錯誤 2 ＝「這支 App 的 App ID 沒有被授權使用天氣服務」。訊息本身只有
        // 一串類別名稱與編號，對使用者等於沒說——這是 WeatherKit 最常見的一種
        // 失敗，值得單獨翻成一句看得懂、而且講得出下一步的話。
        if raw.contains("WDSJWT") || raw.contains("WeatherDaemon") {
            return "這支 App 還沒拿到天氣服務的授權（WeatherKit 的認證權杖要不到）。"
                + "要到 Apple Developer 後台替這個 App ID 開啟 WeatherKit，"
                + "開好之後還要重新簽章再建置一次；剛開好的話 Apple 那邊要一段時間"
                + "才會生效，等一下再按重試。"
        }
        if lowered.contains("auth") || lowered.contains("permission")
            || lowered.contains("entitle") || lowered.contains("unauthorized")
            || lowered.contains("token") || lowered.contains("denied") {
            return "天氣服務不讓這支 App 取用。兩種可能：Apple Developer 後台還沒替"
                + "這個 App ID 開啟 WeatherKit；或剛開好還沒生效（要等一段時間才會傳播開）。"
                + "（\(raw)）"
        }
        return raw
    }

    /// [v25.450] 出圖前先把需要的預報抓齊。
    ///
    /// 分享圖是用 ImageRenderer 同步畫出來的，畫的當下只讀得到快取——
    /// 快取裡沒有就是一片空白，而且不會有任何提示。所以出圖前要先 await
    /// 一次。座標會先去重（1 公里內本來就共用一份），一趟市區行程通常
    /// 只會多打一兩次請求。
    @MainActor
    func preload(_ coordinates: [CLLocationCoordinate2D]) async {
        var seen = Set<String>()
        for c in coordinates {
            let k = Self.key(c)
            guard !seen.contains(k) else { continue }
            seen.insert(k)
            await load(c)
        }
    }

    /// 重新抓一次（使用者按「更新」／「重試」時用）。
    ///
    /// [v25.473] 不再先把舊資料清掉：清了之後萬一這次也失敗（最常見的就是
    /// 當下沒網路），畫面會從「昨天的天氣」變成一片空白——使用者按一下
    /// 「更新」反而失去原本看得到的東西。舊的留著，抓到新的才覆蓋。
    @MainActor
    func refresh(_ coordinate: CLLocationCoordinate2D) async {
        failures[Self.key(coordinate)] = nil
        await load(coordinate, force: true)
    }

    @MainActor
    func retry(_ coordinate: CLLocationCoordinate2D) async {
        await refresh(coordinate)
    }

    /// 整趟一起更新（行程頁那顆「更新天氣」）。
    /// 座標先去重——1 公里內本來就共用一份，一趟市區行程通常只會打一兩次。
    @MainActor
    func refreshAll(_ coordinates: [CLLocationCoordinate2D]) async {
        var seen = Set<String>()
        for c in coordinates {
            let k = Self.key(c)
            guard !seen.contains(k) else { continue }
            seen.insert(k)
            await refresh(c)
        }
    }
}

// MARK: - 畫面

/// 一顆天氣膠囊。時間軸的每一站與景點卡都用它，所以只有一份樣式。
///
/// 三種狀態各自長什麼樣，是刻意分開的：
///   • 拿到了      → 圖示＋高低溫（＋降雨機率，只在 30% 以上才出現）
///   • 還在抓      → 一顆小轉圈，不要先佔位再跳動
///   • 超過預報範圍 → **什麼都不顯示**。一趟三個月後的行程，每一站都掛一句
///                   「太遠了」只是噪音；那句話在整趟的摘要講一次就夠。
struct TripWeatherChip: View {
    @StateObject private var weather = TripWeatherStore.shared
    @Environment(\.scenePhase) private var scenePhase

    let coordinate: CLLocationCoordinate2D?
    let date: Date
    /// 緊湊版給時間軸的膠囊列，寬版給景點卡的區塊
    var compact: Bool = true
    /// [v25.449] 這一份預報掛在哪個地點上（寬版會寫出來）
    var placeName: String? = nil

    var body: some View {
        Group {
            if let coordinate, TripWeatherStore.isWithinForecastRange(date) {
                if let day = weather.forecast(at: coordinate, on: date) {
                    content(day)
                } else if weather.hasFailed(at: coordinate) {
                    failedLabel
                } else {
                    ProgressView().scaleEffect(compact ? 0.45 : 0.6)
                }
            }
        }
        // [v25.473] 這個 .task 掛在整塊上，而不是掛在「還沒有資料」那個
        // 分支裡。掛在分支裡的話，一旦抓到資料那段 View 就不存在了，
        // 也就永遠不會再觸發；現在 load 自己會判斷「超過一天就重抓」，
        // 所以同一個進場動作既負責第一次抓，也負責過期自動更新。
        .task(id: taskKey) {
            guard let coordinate,
                  TripWeatherStore.isWithinForecastRange(date) else { return }
            await weather.load(coordinate)
        }
        // 回到前景再確認一次。擺在背景過了一夜的話，View 沒有重建、
        // .task 不會再跑，但手上那份預報已經是昨天的了。
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let coordinate,
                  TripWeatherStore.isWithinForecastRange(date) else { return }
            Task { await weather.load(coordinate) }
        }
    }

    /// 換站、換日期就重新判斷一次（同一顆膠囊被重用時也要）
    private var taskKey: String {
        (coordinate.map { TripWeatherStore.key($0) } ?? "-")
            + "|" + String(Int(date.timeIntervalSince1970))
    }

    @ViewBuilder
    private func content(_ day: TripDayWeather) -> some View {
        if compact {
            HStack(spacing: 4) {
                Image(systemName: day.symbolName)
                    .font(.system(size: 9))
                    .symbolRenderingMode(.multicolor)
                Text(day.temperatureText)
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                if day.showsRain {
                    Text("☂" + day.rainText)
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.blue)
                }
            }
            .fixedSize()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color(.tertiarySystemFill), in: Capsule())
        } else {
            wide(day)
        }
    }

    /// [v25.448] 景點卡上的完整版。
    ///
    /// 原本只有圖示＋天氣＋高低溫＋降雨機率，排行程時看完等於只知道「會不會下雨」。
    /// WeatherKit 的每日預報本來就一起回了紫外線、風、日出日落——那幾項對
    /// 「這天要怎麼安排」比「多雲」有用得多：幾點天黑決定夜景排得進去嗎，
    /// 紫外線決定要不要帶帽子，風決定海邊那一站要不要改期。
    private func wide(_ day: TripDayWeather) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 第一排：大圖示 + 天氣 + 溫度
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: day.symbolName)
                    .font(.system(size: 38))
                    .symbolRenderingMode(.multicolor)
                    .frame(width: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(day.conditionText)
                        .font(.title3.weight(.bold))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(day.highC.rounded()))°")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                        Text("／")
                            .font(.caption).foregroundStyle(.tertiary)
                        Text("\(Int(day.lowC.rounded()))°")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.blue)
                        if day.dayNightGap >= 8 {
                            Text("溫差 \(day.dayNightGap)°")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            // 第二排：那幾個真正會影響安排的數字
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                statCell("umbrella.fill", "降雨機率", day.rainText,
                         tint: day.showsRain ? .blue : .secondary)
                statCell("sun.max.fill", "紫外線", "\(day.uvIndex)・\(day.uvLabel)",
                         tint: day.uvIndex >= 6 ? .orange : .secondary)
                statCell("wind", "風", "\(Int(day.windKmh.rounded())) km/h \(day.windDirection)",
                         tint: day.windKmh >= 40 ? .teal : .secondary)
                if let sunrise = day.sunrise {
                    statCell("sunrise.fill", "日出", Self.clock.string(from: sunrise), tint: .orange)
                }
                if let sunset = day.sunset {
                    statCell("sunset.fill", "日落", Self.clock.string(from: sunset), tint: .purple)
                }
            }

            // 第三排：提醒。沒有符合門檻的就整段不出現，不硬湊
            let tips = day.tips
            if !tips.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: tip.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(tip.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.top, 2)
            }

            sourceLine
        }
    }

    /// [v25.449] 這份預報到底是哪裡的。
    ///
    /// 不寫出來的話有兩件事會讓人誤會：
    ///   1. 1 公里內的景點共用同一份（省請求的取捨），所以你在 B 看到的
    ///      可能是以 A 的座標查的。
    ///   2. Apple 有自己的觀測網格，回來的位置不一定就是你問的那一點。
    ///      差在一兩百公尺無所謂，差好幾公里就該講。
    @ViewBuilder
    private var sourceLine: some View {
        if let coordinate, let info = weather.source(at: coordinate) {
            let offset = info.offsetMeters
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill").font(.system(size: 8))
                    Text(placeName.map { "以「" + $0 + "」的座標查詢" } ?? "以這一站的座標查詢")
                    Text("・更新於 " + Self.stampText(info.readAt))
                    Spacer(minLength: 6)
                    refreshButton(coordinate)
                }
                // [v25.473] 更新失敗時，上面那份資料是舊的——這件事一定要講。
                // 不講的話畫面看起來跟成功更新一模一樣。
                if let reason = weather.failureReason(at: coordinate) {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 8))
                        Text("更新失敗，上面顯示的是上次讀到的：" + reason)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if weather.isStale(at: coordinate),
                          !weather.isLoading(at: coordinate) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 8))
                        Text("這份超過一天了，可以按「更新」重新抓")
                    }
                }
                // 1 公里以內就是同一個地方，講出來只是雜訊
                if offset >= 1000 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 8))
                        Text("Apple 的觀測點在 \(Int((offset / 1000).rounded())) 公里外，"
                             + "山區或海邊可能跟實際有落差")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
        }
    }

    /// [v25.473] 手動更新。自動更新只在「進場」與「回到前景」時判斷，
    /// 使用者想當下重新抓一次（剛下飛機、天氣突然變了）要有得按。
    private func refreshButton(_ coordinate: CLLocationCoordinate2D) -> some View {
        let busy = weather.isLoading(at: coordinate)
        return Button {
            Task { await weather.refresh(coordinate) }
        } label: {
            HStack(spacing: 3) {
                if busy {
                    ProgressView().scaleEffect(0.45).frame(width: 10, height: 10)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .semibold))
                }
                Text(busy ? "更新中" : "更新")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .disabled(busy)
    }

    /// 讀取時間。今天讀的只寫時刻，不是今天的把日期也寫出來——
    /// 只寫「更新於 09:12」會讓昨天讀的那份看起來像剛剛才讀的。
    private static func stampText(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? clock.string(from: date)
            : dayClock.string(from: date)
    }

    private static let dayClock: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d HH:mm"; return f
    }()

    private func statCell(_ icon: String, _ label: String, _ value: String,
                          tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color(.tertiarySystemFill).opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 9))
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "HH:mm"; return f
    }()

    @ViewBuilder
    private var failedLabel: some View {
        if compact {
            Image(systemName: "cloud.slash")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
        } else {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "cloud.slash")
                    .font(.system(size: 15)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("天氣暫時取不到")
                        .font(.caption).foregroundStyle(.secondary)
                    if let coordinate,
                       let reason = weather.failureReason(at: coordinate) {
                        // 原因一定要寫出來。只說「取不到」的話，沒網路、
                        // 服務沒開、座標在海上這三種完全不同的狀況長得一模一樣，
                        // 使用者不知道該怎麼辦，我也無從判斷。
                        Text(reason)
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if let coordinate {
                    Button("重試") {
                        Task { await weather.retry(coordinate) }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
    }
}

/// Apple 規定：只要顯示 WeatherKit 的資料，就必須標示出處並附上法律連結。
/// 這不是可選的裝飾，所以做成一個元件，有天氣的地方直接擺一個。
struct WeatherAttributionRow: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "apple.logo").font(.system(size: 8))
            Text("天氣")
            Link("資料來源", destination: TripWeatherStore.attributionURL)
                .underline()
        }
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
    }
}
