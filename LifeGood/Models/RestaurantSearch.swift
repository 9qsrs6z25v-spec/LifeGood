import Foundation
import MapKit
import CoreLocation
import Combine

// MARK: - 定位

/// 提供當下位置給 MKLocalSearchCompleter 用，作偏向附近結果用。
/// 對使用者僅要求「使用期間」權限。
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    private let manager = CLLocationManager()

    @Published var lastLocation: CLLocation?
    @Published var authorization: CLAuthorizationStatus = .notDetermined

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorization = manager.authorizationStatus
    }

    /// 請求權限並嘗試取得一次位置。沒有權限時會跳系統 prompt。
    func requestIfNeeded() {
        switch authorization {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    /// 估算的搜尋區域：以當前位置為中心 30 公里半徑（涵蓋鄰近縣市）；
    /// 無位置時回傳 nil，讓 completer 不偏向特定區域，避免錯誤地釘在台北。
    var searchRegion: MKCoordinateRegion? {
        if let loc = lastLocation {
            return MKCoordinateRegion(center: loc.coordinate,
                                      latitudinalMeters: 30000, longitudinalMeters: 30000)
        }
        return nil
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.authorization = manager.authorizationStatus
            if self.authorization == .authorizedWhenInUse || self.authorization == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        DispatchQueue.main.async { [weak self] in
            self?.lastLocation = loc
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 忽略，使用 fallback 區域
    }
}

// MARK: - 餐廳自動完成

/// 包裝 MKLocalSearchCompleter，過濾只剩餐飲類 POI。
final class RestaurantSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()

    @Published var results: [MKLocalSearchCompletion] = []
    @Published var isSearching: Bool = false

    /// 目前查詢字串
    var queryFragment: String {
        get { completer.queryFragment }
        set {
            completer.queryFragment = newValue
            isSearching = !newValue.isEmpty
        }
    }

    override init() {
        super.init()
        completer.delegate = self
        // POI only：避免路名 / 地址混入結果。Apple Maps 對台灣便當店、小吃店歸類不一定正確
        // 但仍是 POI；以使用者位置為偏向多半搜得到。
        completer.resultTypes = .pointOfInterest
    }

    /// 設定搜尋偏向區域（使用使用者位置）；nil 代表清除偏向（用全球範圍）。
    func setRegion(_ region: MKCoordinateRegion?) {
        completer.region = region ?? MKCoordinateRegion(MKMapRect.world)
    }

    /// [v25.431] 改變要搜尋哪幾種結果。
    ///
    /// 預設只搜 POI（店家、景點），這是飲食／就醫紀錄要的——那裡打的是店名。
    /// 但「在地圖上選位置」還要能打地名與地址（「湯布院」「博多站」「大名 115-30」），
    /// 所以那個畫面會自己加上 .address。改成可調而不是全域放寬：
    /// 在飲食紀錄裡讓一堆路名混進建議清單只會更難挑。
    func setResultTypes(_ types: MKLocalSearchCompleter.ResultType) {
        completer.resultTypes = types
    }

    /// 解析選擇的 completion，取得詳細的 MKMapItem（含座標、地址）。
    func resolve(_ completion: MKLocalSearchCompletion,
                 done: @escaping (MKMapItem?) -> Void) {
        let request = MKLocalSearch.Request(completion: completion)
        request.resultTypes = .pointOfInterest
        let search = MKLocalSearch(request: request)
        search.start { [search] response, _ in
            _ = search  // 防止 ARC 在回調完成前提前釋放 search，導致靜默搜尋失敗
            DispatchQueue.main.async {
                done(response?.mapItems.first)
            }
        }
    }

    func clear() {
        completer.queryFragment = ""
        results = []
        isSearching = false
        batch += 1
        pending?.cancel()
        pending = nil
        distances.removeAll()
    }

    // MARK: - 距離（v25.499）

    // 使用者回報：「每次都跑出地址沒有距離，導致我常常不知道要選哪個」。
    //
    // 問題的根在 MapKit：MKLocalSearchCompletion **只有 title 跟 subtitle**，
    // 沒有座標。所以搜「福岡事務所」跳出五筆長得幾乎一樣的地址時，
    // App 自己也不知道哪一筆比較近——不是忘了顯示，是手上根本沒有這個資料。
    //
    // 要拿到座標只有一條路：對每一筆建議各跑一次 MKLocalSearch。所以這裡
    // 做三件事讓它不要變成災難：
    //
    // 1. **只解看得到的那幾筆**（預設 6 筆，就是清單顯示的上限）。
    // 2. **一次只查一筆，查完才查下一筆。** 六筆同時打出去會被 MapKit 節流，
    //    結果是六筆全部沒有距離——那比慢一點糟得多。
    // 3. **查過的留著。** 使用者打字時建議清單會一直重算，同一家店不該重查。

    /// 距離是從這個點量的（使用者現在的位置）
    private var reference: CLLocation?
    /// title+subtitle → 公尺。@Published，所以算到一筆清單就更新一筆。
    @Published private(set) var distances: [String: CLLocationDistance] = [:]
    /// 解過的留著，跨查詢共用（參考點沒變就一直有效）
    private var resolvedCache: [String: CLLocationDistance] = [:]
    /// 這一批解析的識別碼。results 換掉就 +1，舊的回來也不寫入。
    private var batch = 0
    private var pending: MKLocalSearch?

    static func distanceKey(_ completion: MKLocalSearchCompletion) -> String {
        completion.title + "\u{1}" + completion.subtitle
    }

    /// 這一筆建議離使用者多遠。還沒解出來就是 nil。
    func distance(for completion: MKLocalSearchCompletion) -> CLLocationDistance? {
        distances[Self.distanceKey(completion)]
    }

    /// 設定量距離的參考點。通常就是 LocationProvider.shared.lastLocation。
    ///
    /// 走了超過 200 公尺才重算——定位每隔一下就跳幾公尺，
    /// 每跳一次就把所有距離作廢重查的話，清單會一直在閃。
    func setReference(_ location: CLLocation?) {
        if let old = reference, let new = location, old.distance(from: new) < 200 { return }
        reference = location
        resolvedCache.removeAll()
        distances.removeAll()
        resolveDistances()
    }

    /// 實際量距離的起點。
    ///
    /// 沒有特別指定就用使用者現在的位置——找餐廳、找診所，問的本來就是
    /// 「離我多遠」。但規劃福岡的行程時「離我 1200 公里」毫無用處，
    /// 那種畫面會把起點指定成這趟行程／上一站的座標，問的是「離那裡多遠」。
    private var measureFrom: CLLocation? {
        reference ?? LocationProvider.shared.lastLocation
    }

    private func resolveDistances(limit: Int = 6) {
        batch += 1
        pending?.cancel()
        pending = nil
        guard measureFrom != nil, !results.isEmpty else { return }
        resolveStep(Array(results.prefix(limit)), index: 0, token: batch)
    }

    private func resolveStep(_ targets: [MKLocalSearchCompletion],
                             index: Int, token: Int) {
        guard token == batch, index < targets.count, let origin = measureFrom else { return }
        let completion = targets[index]
        let key = Self.distanceKey(completion)
        if let cached = resolvedCache[key] {
            distances[key] = cached
            resolveStep(targets, index: index + 1, token: token)
            return
        }
        // 不能用 resolve()：那個方法把 resultTypes 限成 POI，
        // 拿它來解地址建議會回 nil（見上面那段註解），距離就永遠是空的。
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        pending = search
        search.start { [weak self] response, _ in
            DispatchQueue.main.async {
                guard let self, token == self.batch else { return }
                if let item = response?.mapItems.first {
                    let c = item.placemark.coordinate
                    let meters = CLLocation(latitude: c.latitude, longitude: c.longitude)
                        .distance(from: origin)
                    self.resolvedCache[key] = meters
                    self.distances[key] = meters
                }
                self.resolveStep(targets, index: index + 1, token: token)
            }
        }
    }

    /// 距離的寫法。
    ///
    /// 一公里內用公尺並且取整十，超過用公里一位小數——「1382 公尺」沒有人
    /// 這樣講話，而「0.08 公里」更糟。
    static func distanceText(_ meters: CLLocationDistance) -> String {
        if meters < 20 { return "就在這" }
        if meters < 1000 {
            return "\(Int((meters / 10).rounded()) * 10) 公尺"
        }
        if meters < 100_000 {
            return String(format: "%.1f 公里", meters / 1000)
        }
        return "\(Int((meters / 1000).rounded())) 公里"
    }

    // MARK: - MKLocalSearchCompleterDelegate

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.results = completer.results
            self.isSearching = false
            // 建議換了就去把這幾筆的距離解出來
            self.resolveDistances()
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.results = []
            self?.isSearching = false
        }
    }
}

// MARK: - 工具：把 MKMapItem 解析成可儲存的字串/座標

extension MKMapItem {
    /// 取得格式化地址，例如 "台北市信義區市府路 45 號"
    var formattedAddress: String {
        let p = placemark
        var parts: [String] = []
        if let area = p.administrativeArea, !area.isEmpty { parts.append(area) }
        if let sub = p.subAdministrativeArea, !sub.isEmpty, sub != p.administrativeArea {
            parts.append(sub)
        }
        if let locality = p.locality, !locality.isEmpty { parts.append(locality) }
        if let subLocality = p.subLocality, !subLocality.isEmpty { parts.append(subLocality) }
        if let thoroughfare = p.thoroughfare, !thoroughfare.isEmpty {
            if let subThoroughfare = p.subThoroughfare, !subThoroughfare.isEmpty {
                parts.append("\(thoroughfare) \(subThoroughfare)")
            } else {
                parts.append(thoroughfare)
            }
        }
        return parts.joined(separator: " ")
    }
}
