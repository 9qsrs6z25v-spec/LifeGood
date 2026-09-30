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

    /// key＝座標取到小數第 2 位（約 1 公里）。
    ///
    /// 同一個城市裡的二十個景點天氣幾乎一樣，一站一次請求既慢又浪費配額；
    /// 取到公里級之後，一趟市區行程通常只會打一兩次。
    @Published private(set) var cache: [String: [Date: TripDayWeather]] = [:]
    /// 問過但失敗的：key → 失敗原因。
    ///
    /// [v25.437] 原本只記一個「有沒有失敗」的布林值，畫面上就只能寫
    /// 「天氣暫時取不到」——使用者看不出是沒網路、是能力沒開、還是這個座標
    /// 本來就沒資料，我也沒辦法從回報裡判斷。錯誤訊息是唯一的線索，
    /// 吞掉它等於把唯一的線索丟了。
    @Published private(set) var failures: [String: String] = [:]
    /// 正在飛的請求，避免同一個 key 被二十個景點同時觸發
    private var inFlight: Set<String> = []

    private init() {}

    static func key(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.2f,%.2f", c.latitude, c.longitude)
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

    func hasFailed(at coordinate: CLLocationCoordinate2D) -> Bool {
        failures[Self.key(coordinate)] != nil
    }

    /// 失敗原因（已經翻成使用者看得懂的話）
    func failureReason(at coordinate: CLLocationCoordinate2D) -> String? {
        failures[Self.key(coordinate)]
    }

    /// 抓這個地點未來十天的每日預報。
    /// 一次抓完整段，因為 WeatherKit 本來就是一次回一整組，分天問只是多打幾次。
    @MainActor
    func load(_ coordinate: CLLocationCoordinate2D) async {
        let key = Self.key(coordinate)
        guard cache[key] == nil, !inFlight.contains(key), failures[key] == nil else { return }
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
                    precipitationChance: day.precipitationChance)
            }
            cache[key] = byDay
        } catch {
            // 失敗的原因多半是幾種：沒網路、App ID 還沒開 WeatherKit 能力、
            // 剛開好還沒生效、或這個座標落在海上。都不該重試到天荒地老，
            // 記下原因就算了——原因要留著，那是使用者回報時唯一的線索。
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
        if lowered.contains("auth") || lowered.contains("permission")
            || lowered.contains("entitle") || lowered.contains("unauthorized")
            || lowered.contains("token") || lowered.contains("denied") {
            return "天氣服務不讓這支 App 取用。兩種可能：Apple Developer 後台還沒替"
                + "這個 App ID 開啟 WeatherKit；或剛開好還沒生效（要等一段時間才會傳播開）。"
                + "（\(raw)）"
        }
        return raw
    }

    /// 重新再試一次（使用者按重試時用）
    @MainActor
    func retry(_ coordinate: CLLocationCoordinate2D) async {
        let key = Self.key(coordinate)
        failures[key] = nil
        cache[key] = nil
        await load(coordinate)
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

    let coordinate: CLLocationCoordinate2D?
    let date: Date
    /// 緊湊版給時間軸的膠囊列，寬版給景點卡的區塊
    var compact: Bool = true

    var body: some View {
        Group {
            if let coordinate, TripWeatherStore.isWithinForecastRange(date) {
                if let day = weather.forecast(at: coordinate, on: date) {
                    content(day)
                } else if weather.hasFailed(at: coordinate) {
                    failedLabel
                } else {
                    ProgressView().scaleEffect(compact ? 0.45 : 0.6)
                        .task { await weather.load(coordinate) }
                }
            }
        }
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
            HStack(spacing: 12) {
                Image(systemName: day.symbolName)
                    .font(.system(size: 26))
                    .symbolRenderingMode(.multicolor)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.conditionText)
                        .font(.subheadline.weight(.semibold))
                    Text(day.temperatureText
                         + (day.showsRain ? "　降雨機率 " + day.rainText : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

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
