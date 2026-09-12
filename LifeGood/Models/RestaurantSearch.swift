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
    }

    // MARK: - MKLocalSearchCompleterDelegate

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async { [weak self] in
            self?.results = completer.results
            self?.isSearching = false
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
