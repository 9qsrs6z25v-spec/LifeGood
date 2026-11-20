import SwiftUI
import WatchKit
import MapKit

// MARK: - 這一站、天氣資料出處（手錶 v6，v25.578；watch/judge.md §2.14、§2.17；watch/build/v6/brief.md G3-2）
//
// 只屬於 LifeGoodWatch。④ 旅行點大字那一塊、錶面「下一場」旅途中那一種推進來的第二層；純黑底、可以捲。
// 字全部是 WatchTripText.stopDetail 組好的（WatchTripStopDetail）；手腕放下換哪個字（過夜那一站「住宿」、不寫飯店地址）
// 由 WatchTripText 依 privacy.hidesPersonal 換好：
//   標題「弘大」／「第 3／5 站・14:00 到」／「預計停留 90 分」／「✓ 14:12 到了」／📍 地址（兩行）／
//   〔導航〕（有座標：MKMapItem.openInMaps，手錶的地圖）／「+82 2-3142-0000」〔電話〕（WKApplication.openSystemURL(tel:)）／
//   ☁︎ 18°／11° 短暫陣雨 40%／天氣兩句／ Weather ›（TripWeatherLines：天氣一定緊接著出處；沒有天氣字整塊不畫）
// 這一頁不放〔到了〕〔離開〕（④ 那一頁有）。包裡找不到這一站（iPhone 改過、刪了）：「這一站在 iPhone 上改過了」。
// 手錶的 import 只多 MapKit（judge §7.8-1：只為〔導航〕；座標型別 CLLocationCoordinate2D 經 MapKit 帶進來，不另外引入 CoreLocation 模組）。
//
// 天氣資料出處（TripWeatherSourcePage；「 Weather ›」點進來）：「天氣資料： Weather」／出處網址（包裡帶的
// WatchTripDay.weatherSource，沒有用 WatchTripText.sourceDefaultURL）／〔打開〕（Link）／打不開的話去 iPhone 旅行頁看。

struct TripStopDetail: View {
    /// TripStop.id（WatchRoute.tripStop）
    let stopId: UUID

    @ObservedObject private var model = WatchModel.shared
    @ObservedObject private var checkIns = TripCheckIns.shared
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.redactionReasons) private var reasons

    static let missingText = "這一站在 iPhone 上改過了"
    static let missingTitle = "旅行"
    /// 手腕放下時字調暗
    static let dimmedOpacity: Double = 0.75

    init(stopId: UUID) {
        self.stopId = stopId
    }

    private var privacy: WatchPrivacy {
        model.privacy(dimmed: dimmed, redacted: reasons.contains(.privacy))
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            page(now: context.date)
        }
        .containerBackground(Color.black, for: .navigation)
    }

    /// 包裡今天、明天那一份找這一站（補上手錶上按過、iPhone 還沒寫回包裡的打卡）
    private func detail(now: Date) -> WatchTripStopDetail? {
        WatchTripText.stopDetail(package: model.package, stopId: stopId, now: now, pending: checkIns.items,
                                 dimmed: privacy.hidesPersonal)
    }

    @ViewBuilder
    private func page(now: Date) -> some View {
        if let d = detail(now: now) {
            TripStopDetailBody(detail: d, dimmed: dimmed)
                .opacity(dimmed ? Self.dimmedOpacity : 1)
                .navigationTitle(d.title)
        } else {
            missing
                .navigationTitle(Self.missingTitle)
        }
    }

    private var missing: some View {
        Text(Self.missingText)
            .font(.body)
            .foregroundStyle(WatchStyle.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .scenePadding(.horizontal)
    }
}

// MARK: - 這一站本體（可以捲）

private struct TripStopDetailBody: View {
    let detail: WatchTripStopDetail
    /// 手腕放下：按鈕變暗、暫時不能按（不拿掉）
    let dimmed: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                timeRow
                dwellRow
                stateRow
                addressRow
                TripStopActions(detail: detail, dimmed: dimmed)
                weatherBlock
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scenePadding(.horizontal)
        }
    }

    /// 「第 3／5 站・14:00 到」
    private var timeRow: some View {
        Text(detail.timeLine)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(WatchStyle.dateText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// 「預計停留 90 分」「過夜」
    private var dwellRow: some View {
        Text(detail.dwellLine)
            .font(.footnote)
            .foregroundStyle(WatchStyle.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// 「✓ 14:12 到了」「✓ 14:12 到・15:40 離開」；還沒到不畫
    @ViewBuilder
    private var stateRow: some View {
        if let state = detail.stateLine {
            TripArrivedLine(text: state)
        }
    }

    /// 📍 地址（兩行；沒有、或手腕放下的過夜那一站不畫）
    @ViewBuilder
    private var addressRow: some View {
        if let address = detail.address {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "mappin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WatchStyle.small)
                    .frame(width: 14)
                Text(address)
                    .font(.footnote)
                    .foregroundStyle(WatchStyle.primary)
                    .lineLimit(2)
            }
        }
    }

    /// 天氣＋天氣兩句＋緊接著「 Weather ›」（TripWeatherLines；沒有天氣字整塊不畫）
    private var weatherBlock: some View {
        TripWeatherLines(text: detail.weatherText, symbol: detail.weatherSymbol, tips: detail.tips,
                         showsSource: detail.showsSource, oneLine: false, dimmed: dimmed)
    }
}

// MARK: - 〔導航〕〔電話〕

private struct TripStopActions: View {
    let detail: WatchTripStopDetail
    let dimmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            navigateButton
            phoneBlock
        }
    }

    /// 〔導航〕：有座標才有（Apple 地圖帶座標）
    @ViewBuilder
    private var navigateButton: some View {
        if let lat = detail.latitude, let lon = detail.longitude, TripStopLinks.isValidCoordinate(lat, lon) {
            Button {
                TripStopLinks.openMaps(latitude: lat, longitude: lon, name: detail.title)
            } label: {
                Label(WatchTripText.navigateTitle, systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(dimmed)
        }
    }

    /// 「+82 2-3142-0000」（小字）＋〔電話〕：有號碼才有
    @ViewBuilder
    private var phoneBlock: some View {
        if let dial = detail.phoneDial {
            if let text = detail.phoneText {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(WatchStyle.small)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Button {
                TripStopLinks.call(dial)
            } label: {
                Label(WatchTripText.callTitle, systemImage: "phone.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(dimmed)
        }
    }
}

/// 開地圖、撥電話（按鈕的動作，主執行緒）
private enum TripStopLinks {
    /// 緯度 −90…90、經度 −180…180、不是 (0, 0)（沒填的座標）
    static func isValidCoordinate(_ latitude: Double, _ longitude: Double) -> Bool {
        guard latitude.isFinite, longitude.isFinite else { return false }
        guard abs(latitude) <= 90, abs(longitude) <= 180 else { return false }
        return !(latitude == 0 && longitude == 0)
    }

    /// 手錶的地圖打開這一站（MKMapItem.openInMaps，watchOS 2 起；不帶 launchOptions）
    @MainActor
    static func openMaps(latitude: Double, longitude: Double, name: String) {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        _ = item.openInMaps(launchOptions: nil)
    }

    /// 撥這一站的電話（tel:＋只有數字與「+」的號碼；WKApplication.openSystemURL，watchOS 7 起）
    @MainActor
    static func call(_ dial: String) {
        guard let url = URL(string: "tel:" + dial) else { return }
        WKApplication.shared().openSystemURL(url)
    }
}

// MARK: - 天氣資料出處（WatchRoute.weatherSource）

/// 「天氣資料： Weather」／出處網址（可以多行）／〔打開〕（Link）／打不開的話去 iPhone 旅行頁點「資料來源」
struct TripWeatherSourcePage: View {
    @ObservedObject private var model = WatchModel.shared
    @Environment(\.isLuminanceReduced) private var dimmed

    static let pageTitle = "天氣資料"
    static let openTitle = "打開"
    /// 手腕放下時字調暗
    static let dimmedOpacity: Double = 0.75

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                titleText
                addressText
                openLink
                fallbackText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scenePadding(.horizontal)
        }
        .opacity(dimmed ? Self.dimmedOpacity : 1)
        .navigationTitle(Self.pageTitle)
        .containerBackground(Color.black, for: .navigation)
    }

    /// 包裡帶的出處網址（沒有用 WatchTripText.sourceDefaultURL）
    private var address: String {
        WatchTripText.weatherSourceURL(package: model.package)
    }

    private var titleText: some View {
        Text(WatchTripText.sourceTitle)
            .font(.headline)
            .foregroundStyle(WatchStyle.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var addressText: some View {
        Text(address)
            .font(.footnote)
            .foregroundStyle(WatchStyle.small)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 〔打開〕（手錶開網頁的樣子【實機】）
    @ViewBuilder
    private var openLink: some View {
        if let url = URL(string: address) {
            Link(destination: url) {
                Label(Self.openTitle, systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(dimmed)
        }
    }

    /// 「打不開的話，請在 iPhone 旅行頁點「資料來源」」
    private var fallbackText: some View {
        Text(WatchTripText.sourceFallback)
            .font(.footnote)
            .foregroundStyle(WatchStyle.small)
            .fixedSize(horizontal: false, vertical: true)
    }
}
