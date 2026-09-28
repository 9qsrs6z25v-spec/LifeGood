import SwiftUI
import MapKit
import UIKit

// MARK: - 旅遊規劃的圖片分享（v25.409）
//
// 兩種圖：單段路線卡、整份行程（可分頁）。
//
// ⚠️ ImageRenderer 畫不出 SwiftUI 的 Map——那是包在 UIViewRepresentable 裡的
//    UIKit 元件，出圖時會變成一塊空白。所以圖片裡的地圖一律走 MKMapSnapshotter
//    先做成 UIImage，路線與大頭針再用 Core Graphics 自己疊上去。
//
// ⚠️ 版面裡不能有「沒有邊界的 Spacer / maxHeight: .infinity」：ImageRenderer 的
//    proposedSize 是 .unspecified，量到的理想高度會變成無限大，uiImage 直接回 nil，
//    出圖會安靜地失敗（教訓見 CompanyChronicleView 的註解）。

// MARK: - 地圖快照

enum TripMapSnapshot {

    struct Marker {
        let coordinate: CLLocationCoordinate2D
        let text: String
        let color: UIColor
        /// 住宿用床的符號取代數字
        let isLodging: Bool
        let isMustVisit: Bool
    }

    /// 畫一張帶路線與大頭針的地圖圖片。
    ///
    /// - Parameters:
    ///   - polylines: 真實路徑（畫實線）。沒有的段落放進 straights 畫虛線。
    static func image(coordinates: [CLLocationCoordinate2D],
                      polylines: [(MKPolyline, UIColor)],
                      straights: [([CLLocationCoordinate2D], UIColor)],
                      markers: [Marker],
                      size: CGSize,
                      scale: CGFloat) async -> UIImage? {
        guard let region = region(for: coordinates, polylines: polylines.map(\.0)) else {
            return nil
        }
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = scale
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll
        // 分享出去的圖固定用淺色：對方可能在任何模式下看，深色底圖配白卡片很難看
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            snapshot.image.draw(at: .zero)

            for (polyline, color) in polylines {
                let path = bezier(for: coords(of: polyline), snapshot: snapshot)
                path.lineWidth = 7
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                color.setStroke()
                path.stroke()
            }
            for (line, color) in straights {
                let path = bezier(for: line, snapshot: snapshot)
                path.lineWidth = 5
                path.lineCapStyle = .round
                path.setLineDash([14, 10], count: 2, phase: 0)
                color.withAlphaComponent(0.65).setStroke()
                path.stroke()
            }
            for marker in markers {
                draw(marker, snapshot: snapshot, size: size)
            }
        }
    }

    private static func coords(of polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        var out = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(),
                                           count: polyline.pointCount)
        polyline.getCoordinates(&out, range: NSRange(location: 0, length: polyline.pointCount))
        return out
    }

    private static func bezier(for line: [CLLocationCoordinate2D],
                               snapshot: MKMapSnapshotter.Snapshot) -> UIBezierPath {
        let path = UIBezierPath()
        for (i, c) in line.enumerated() {
            let p = snapshot.point(for: c)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    private static func draw(_ marker: Marker,
                             snapshot: MKMapSnapshotter.Snapshot,
                             size: CGSize) {
        let center = snapshot.point(for: marker.coordinate)
        // 超出畫面的點不畫：MKMapSnapshotter 的 region 會被地圖自己微調，
        // 邊緣的點有可能落在圖外，硬畫會在邊上留下半顆殘影
        guard center.x > -40, center.y > -40,
              center.x < size.width + 40, center.y < size.height + 40 else { return }

        let radius: CGFloat = 17
        let rect = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
        UIColor.white.setFill()
        UIBezierPath(ovalIn: rect.insetBy(dx: -2.5, dy: -2.5)).fill()
        marker.color.setFill()
        UIBezierPath(ovalIn: rect).fill()

        let label = marker.isLodging ? "宿" : marker.text
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: marker.isLodging ? 15 : 17, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let string = NSAttributedString(string: label, attributes: attributes)
        let textSize = string.size()
        string.draw(at: CGPoint(x: center.x - textSize.width / 2,
                                y: center.y - textSize.height / 2))

        if marker.isMustVisit {
            let starRect = CGRect(x: center.x + radius - 9, y: center.y - radius - 9,
                                  width: 20, height: 20)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: starRect).fill()
            let star = NSAttributedString(string: "★", attributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: UIColor.systemOrange
            ])
            let s = star.size()
            star.draw(at: CGPoint(x: starRect.midX - s.width / 2,
                                  y: starRect.midY - s.height / 2))
        }
    }

    /// 把所有點與路線框進來，四周留一點邊。
    private static func region(for coordinates: [CLLocationCoordinate2D],
                               polylines: [MKPolyline]) -> MKCoordinateRegion? {
        var all = coordinates
        for polyline in polylines { all.append(contentsOf: coords(of: polyline)) }
        let lats = all.map(\.latitude), lons = all.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.004, (maxLat - minLat) * 1.45),
                                   longitudeDelta: max(0.004, (maxLon - minLon) * 1.45)))
    }
}

// MARK: - 版面共用

/// 分享圖固定用淺色配色，不跟著系統的深色模式跑：
/// 收到圖的人不會知道你當時開的是哪個模式，圖本身要自己成立。
enum TripCardStyle {
    static let paper = Color(red: 0.99, green: 0.99, blue: 1.00)
    static let card = Color.white
    static let ink = Color(red: 0.11, green: 0.10, blue: 0.16)
    static let subInk = Color(red: 0.42, green: 0.42, blue: 0.50)
    static let hairline = Color(red: 0.88, green: 0.88, blue: 0.92)

    /// 整張圖的外框寬度
    static let pageWidth: CGFloat = 900
    static let legWidth: CGFloat = 820
    /// 四邊留白。
    ///
    /// 圖片滿版到角落時，在 iPhone 上用相片 App 或訊息預覽都會被圓角螢幕吃掉四個角，
    /// 標題與頁碼剛好都在那裡。留一圈邊之後角落是底色，切到也無所謂。
    static let pageMargin: CGFloat = 26
    /// 卡片本體的寬度（外框扣掉左右留白）
    static var cardWidth: CGFloat { pageWidth - pageMargin * 2 }
    static var legCardWidth: CGFloat { legWidth - pageMargin * 2 }
}

// MARK: - 單段路線卡

/// 「這一段」的分享圖。版面刻意對著 App 裡那張詳情卡做，
/// 使用者說好看的就是那個樣子。
struct TripLegShareCard: View {
    let plan: TripPlan
    let index: Int
    /// 事先做好的地圖圖片（nil＝沒有座標或做不出來，版面會省略地圖）
    let mapImage: UIImage?

    private var slots: [TripPlan.Slot] { plan.timeline }
    private var to: TripPlan.Slot? {
        slots.indices.contains(index) && index > 0 ? slots[index] : nil
    }
    private var from: TripPlan.Slot? {
        slots.indices.contains(index - 1) ? slots[index - 1] : nil
    }
    private var dayColor: Color { TripDayPalette.color(to?.dayIndex ?? 0) }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "HH:mm"; return f
    }()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d (E)"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let from, let to {
                header(from: from, to: to)
                if let mapImage {
                    Image(uiImage: mapImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: TripCardStyle.legCardWidth, height: 380)
                        .clipped()
                }
                facts(from: from, to: to)
            } else {
                Text("這一段找不到資料")
                    .font(.system(size: 20)).foregroundStyle(TripCardStyle.subInk)
                    .padding(40)
            }
            footer
        }
        .frame(width: TripCardStyle.legCardWidth)
        .background(TripCardStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(TripCardStyle.pageMargin)
        .background(TripCardStyle.paper)
    }

    private func header(from: TripPlan.Slot, to: TripPlan.Slot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: to.mode.icon)
                    .font(.system(size: 17, weight: .bold))
                Text(to.mode.rawValue)
                    .font(.system(size: 17, weight: .bold))
                if to.isEstimated {
                    Text("估算")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.white.opacity(0.22), in: Capsule())
                }
                Spacer(minLength: 0)
                Text(Self.dayFmt.string(from: to.arrival))
                    .font(.system(size: 15, weight: .semibold))
                    .opacity(0.9)
            }
            .foregroundStyle(.white)

            Text(from.stop.displayName + "  →  " + to.stop.displayName)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 22) {
                headerMetric(Self.timeFmt.string(from: from.departure)
                             + " – " + Self.timeFmt.string(from: to.arrival), "時間")
                if let s = to.travelSeconds {
                    headerMetric(TripRouter.durationText(s), "交通")
                }
                if let m = to.travelMeters {
                    headerMetric(TripRouter.distanceText(m), "距離")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(28)
        .frame(width: TripCardStyle.legCardWidth, alignment: .leading)
        .background(
            LinearGradient(colors: [dayColor, dayColor.opacity(0.62)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private func headerMetric(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(title).font(.system(size: 12)).opacity(0.85)
        }
        .foregroundStyle(.white)
    }

    private func facts(from: TripPlan.Slot, to: TripPlan.Slot) -> some View {
        VStack(spacing: 0) {
            endpointRow(label: "從", slot: from, time: from.departure)
            Rectangle().fill(TripCardStyle.hairline).frame(height: 1)
            endpointRow(label: "到", slot: to, time: to.arrival)
            if !noteText(to).isEmpty {
                Rectangle().fill(TripCardStyle.hairline).frame(height: 1)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 15)).foregroundStyle(TripCardStyle.subInk)
                    Text(noteText(to))
                        .font(.system(size: 14))
                        .foregroundStyle(TripCardStyle.subInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 28).padding(.vertical, 16)
            }
        }
    }

    private func endpointRow(label: String, slot: TripPlan.Slot, time: Date) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(TripDayPalette.color(slot.dayIndex)))
            VStack(alignment: .leading, spacing: 4) {
                Text(slot.stop.displayName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(TripCardStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
                let address = slot.stop.address.trimmingCharacters(in: .whitespaces)
                if !address.isEmpty {
                    Text(address)
                        .font(.system(size: 14))
                        .foregroundStyle(TripCardStyle.subInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Text(Self.timeFmt.string(from: time))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(TripDayPalette.color(slot.dayIndex))
        }
        .padding(.horizontal, 28).padding(.vertical, 18)
    }

    /// 字串在 ViewBuilder 外組好
    private func noteText(_ slot: TripPlan.Slot) -> String {
        var parts: [String] = []
        if slot.isEstimated {
            if !slot.mode.supportsRouting {
                parts.append("\(slot.mode.rawValue)沒有路線服務可問，距離與時間是用直線估算的。")
            } else if slot.canRetryRouting {
                parts.append("這一段暫時沒拿到真實路線，距離與時間是用直線估算的。")
            } else {
                parts.append("地圖服務找不到這兩點之間的路，距離與時間是用直線估算的。")
            }
            if slot.mode.fixedOverheadMinutes > 0 {
                parts.append("已含 \(slot.mode.fixedOverheadMinutes) 分鐘報到與登機等固定耗時，不含去機場的路程。")
            }
        } else {
            parts.append("實際道路距離與行駛時間（依一般路況估算）。")
        }
        if slot.shortfallSeconds > 60 {
            parts.append("⚠️ 比指定抵達時間晚 " + TripRouter.durationText(slot.shortfallSeconds) + "。")
        } else if slot.idleSeconds > 300 {
            parts.append("抵達後到下一個指定時間之間空 " + TripRouter.durationText(slot.idleSeconds) + "。")
        }
        return parts.joined(separator: "")
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "map.fill")
                .font(.system(size: 12)).foregroundStyle(dayColor)
            Text(plan.displayTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TripCardStyle.subInk)
            Spacer(minLength: 0)
            Text("LifeGood 美好人生")
                .font(.system(size: 12)).foregroundStyle(TripCardStyle.subInk.opacity(0.7))
        }
        .padding(.horizontal, 28).padding(.vertical, 16)
        .frame(width: TripCardStyle.legCardWidth)
        .background(TripCardStyle.paper)
    }
}

// MARK: - 整份行程（單頁）

/// 行程分享圖的一頁。slots 是這一頁要畫的那幾站。
struct TripPlanShareCard: View {
    let plan: TripPlan
    let slots: [TripPlan.Slot]
    let pageIndex: Int
    let pageCount: Int
    /// 只有第一頁會帶地圖
    let mapImage: UIImage?

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "HH:mm"; return f
    }()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d (E)"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let mapImage {
                Image(uiImage: mapImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: TripCardStyle.cardWidth, height: 420)
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(slots.enumerated()), id: \.element.id) { offset, slot in
                    if needsDayHeader(at: offset) {
                        dayHeader(slot)
                    }
                    if slot.index > 0 {
                        legLine(slot)
                    }
                    stopBlock(slot)
                }
            }
            .padding(.vertical, 18)
            footer
        }
        .frame(width: TripCardStyle.cardWidth)
        .background(TripCardStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(TripCardStyle.pageMargin)
        .background(TripCardStyle.paper)
    }

    // MARK: 標頭

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(plan.displayTitle)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if pageCount > 1 {
                    Text("\(pageIndex + 1) / \(pageCount)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Color.white.opacity(0.2), in: Capsule())
                }
            }
            Text(Self.dayFmt.string(from: plan.startDate) + " "
                 + Self.timeFmt.string(from: plan.startDate)
                 + "  →  " + Self.dayFmt.string(from: plan.endDate) + " "
                 + Self.timeFmt.string(from: plan.endDate))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
            HStack(spacing: 26) {
                metric("\(plan.stops.count)", "站")
                if plan.dayCount > 1 { metric("\(plan.dayCount)", "天") }
                if plan.overnightCount > 0 { metric("\(plan.overnightCount)", "晚住宿") }
                if plan.totalTravelSeconds > 0 {
                    metric(TripRouter.durationText(plan.totalTravelSeconds), "交通")
                }
                if plan.totalMeters > 0 {
                    metric(TripRouter.distanceText(plan.totalMeters), "距離")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(30)
        .frame(width: TripCardStyle.cardWidth, alignment: .leading)
        .background(
            LinearGradient(colors: [TripDayPalette.color(0), TripDayPalette.color(0).opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private func metric(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded))
            Text(title).font(.system(size: 12)).opacity(0.85)
        }
        .foregroundStyle(.white)
    }

    // MARK: 內容

    private func needsDayHeader(at offset: Int) -> Bool {
        guard slots.indices.contains(offset) else { return false }
        // 每一頁開頭一定重畫日期，不然翻到第二張圖不知道是哪一天
        if offset == 0 { return true }
        return slots[offset].dayIndex != slots[offset - 1].dayIndex
    }

    private func dayHeader(_ slot: TripPlan.Slot) -> some View {
        let color = TripDayPalette.color(slot.dayIndex)
        let date = Calendar.current.date(byAdding: .day, value: slot.dayIndex,
                                         to: plan.startDate) ?? plan.startDate
        return HStack(spacing: 10) {
            Text("第 \(slot.dayIndex + 1) 天")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11).padding(.vertical, 4)
                .background(color, in: Capsule())
            Text(Self.dayFmt.string(from: date))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
            Rectangle().fill(color.opacity(0.25)).frame(height: 1)
        }
        .padding(.horizontal, 30)
        .padding(.top, 16).padding(.bottom, 10)
    }

    private func legLine(_ slot: TripPlan.Slot) -> some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 74, height: 1)
            Rectangle().fill(TripDayPalette.color(slot.dayIndex).opacity(0.3))
                .frame(width: 2, height: 22)
            Image(systemName: slot.mode.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(TripCardStyle.subInk)
            Text(legText(slot))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TripCardStyle.subInk)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 3)
    }

    /// 字串在 ViewBuilder 外組好
    private func legText(_ slot: TripPlan.Slot) -> String {
        var t = slot.mode.rawValue + "　"
        if let s = slot.travelSeconds {
            t += TripRouter.durationText(s)
            if let m = slot.travelMeters { t += "・" + TripRouter.distanceText(m) }
            if slot.isEstimated { t += "（估）" }
        } else {
            t += "未計算路線"
        }
        if slot.shortfallSeconds > 60 {
            t += "　⚠️ 差 " + TripRouter.durationText(slot.shortfallSeconds) + " 趕不上"
        } else if slot.idleSeconds > 300 {
            t += "　等 " + TripRouter.durationText(slot.idleSeconds)
        }
        return t
    }

    private func stopBlock(_ slot: TripPlan.Slot) -> some View {
        let color = TripDayPalette.color(slot.dayIndex)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.timeFmt.string(from: slot.arrival))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(slot.shortfallSeconds > 60 ? Color.red : color)
                Text(departureText(slot))
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(TripCardStyle.subInk.opacity(0.8))
            }
            .frame(width: 74, alignment: .trailing)

            ZStack(alignment: .topTrailing) {
                Circle().fill(color).frame(width: 30, height: 30)
                    .overlay(
                        Text("\(slot.index + 1)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    )
                if slot.stop.isMustVisit {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .padding(2)
                        .background(Circle().fill(Color.white))
                        .offset(x: 6, y: -6)
                }
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 5) {
                Text(slot.stop.displayName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(TripCardStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !chipTexts(slot).isEmpty {
                    HStack(spacing: 6) {
                        ForEach(chipTexts(slot), id: \.self) { text in
                            Text(text)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(color)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(color.opacity(0.12), in: Capsule())
                        }
                        Spacer(minLength: 0)
                    }
                }
                let address = slot.stop.address.trimmingCharacters(in: .whitespaces)
                if !address.isEmpty {
                    Text(address)
                        .font(.system(size: 14))
                        .foregroundStyle(TripCardStyle.subInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !slot.stop.subSpots.isEmpty {
                    Text("・" + slot.stop.subSpots.map { s in
                        let n = s.name.trimmingCharacters(in: .whitespaces)
                        return (n.isEmpty ? "未命名" : n) + (s.minutes > 0 ? "（\(s.minutes) 分）" : "")
                    }.joined(separator: "、"))
                        .font(.system(size: 13))
                        .foregroundStyle(TripCardStyle.subInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let note = slot.stop.note.trimmingCharacters(in: .whitespacesAndNewlines)
                if !note.isEmpty {
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(TripCardStyle.subInk.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 9)
    }

    private func departureText(_ slot: TripPlan.Slot) -> String {
        let t = Self.timeFmt.string(from: slot.departure)
        return Calendar.current.isDate(slot.departure, inSameDayAs: slot.arrival)
            ? t : "翌 " + t
    }

    private func chipTexts(_ slot: TripPlan.Slot) -> [String] {
        var out: [String] = []
        if slot.stop.isMustVisit { out.append("必去") }
        if slot.stop.isOvernight {
            out.append("過夜・隔天 " + Self.timeFmt.string(from: slot.departure) + " 出發")
        } else if slot.stop.dwellMinutes > 0 {
            out.append("停留 \(slot.stop.dwellMinutes) 分")
        }
        if slot.isFixedArrival { out.append("指定抵達") }
        return out
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "map.fill")
                .font(.system(size: 12)).foregroundStyle(TripDayPalette.color(0))
            Text(pageCount > 1
                 ? "\(plan.displayTitle)　第 \(pageIndex + 1) / \(pageCount) 頁"
                 : plan.displayTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TripCardStyle.subInk)
            Spacer(minLength: 0)
            Text("LifeGood 美好人生")
                .font(.system(size: 12)).foregroundStyle(TripCardStyle.subInk.opacity(0.7))
        }
        .padding(.horizontal, 30).padding(.vertical, 16)
        .frame(width: TripCardStyle.cardWidth)
        .background(TripCardStyle.paper)
    }
}

// MARK: - 出圖

enum TripImageExporter {

    /// 點陣圖的尺寸預算。超過的話 pngData()／jpegData() 會**安靜地回 nil**
    ///（記憶體不足時不丟錯），使用者只看到「出圖失敗」。所以先把倍率壓進預算。
    private static let maxSide: CGFloat = 10_000
    private static let maxPixels: CGFloat = 24_000_000
    private static let maxScale: CGFloat = 3

    @MainActor
    static func render<V: View>(_ view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = .unspecified
        var size: CGSize = .zero
        renderer.render { measured, _ in size = measured }
        guard size.width > 0, size.height > 0 else { return nil }
        renderer.scale = fittingScale(for: size)
        return renderer.uiImage
    }

    private static func fittingScale(for size: CGSize) -> CGFloat {
        let longest = max(size.width, size.height)
        let area = size.width * size.height
        guard longest > 0, area > 0 else { return 1 }
        return max(1, min(maxScale, min(maxSide / longest, (maxPixels / area).squareRoot())))
    }

    @MainActor
    static func writeJPG<V: View>(_ view: V, name: String) -> URL? {
        guard let image = render(view),
              let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(sanitized(name) + ".jpg")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// 檔名不能帶 /、: 這些字元，行程名稱是使用者自由輸入的
    private static func sanitized(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: bad).joined(separator: "_")
        return cleaned.isEmpty ? "行程" : String(cleaned.prefix(60))
    }

    static let stampFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmm"; return f
    }()

    // MARK: 地圖素材

    /// 單段路線的地圖圖片
    static func legMapImage(plan: TripPlan, index: Int,
                            polyline: MKPolyline?) async -> UIImage? {
        let slots = plan.timeline
        guard slots.indices.contains(index), index > 0,
              let a = slots[index - 1].stop.coordinate,
              let b = slots[index].stop.coordinate else { return nil }
        let color = UIColor(TripDayPalette.color(slots[index].dayIndex))
        let markers = [
            TripMapSnapshot.Marker(coordinate: a, text: "\(index)",
                                   color: UIColor(TripDayPalette.color(slots[index - 1].dayIndex)),
                                   isLodging: slots[index - 1].stop.isOvernight,
                                   isMustVisit: slots[index - 1].stop.isMustVisit),
            TripMapSnapshot.Marker(coordinate: b, text: "\(index + 1)", color: color,
                                   isLodging: slots[index].stop.isOvernight,
                                   isMustVisit: slots[index].stop.isMustVisit)
        ]
        return await TripMapSnapshot.image(
            coordinates: [a, b],
            polylines: polyline.map { [($0, color)] } ?? [],
            straights: polyline == nil ? [([a, b], color)] : [],
            markers: markers,
            size: CGSize(width: TripCardStyle.legCardWidth, height: 380),
            scale: 2)
    }

    /// 整份行程的總覽地圖（只放在第一頁）
    static func planMapImage(plan: TripPlan) async -> UIImage? {
        let slots = plan.timeline
        let pinned = slots.filter { $0.stop.coordinate != nil }
        guard pinned.count >= 2 else { return nil }

        var straights: [([CLLocationCoordinate2D], UIColor)] = []
        for i in 1..<slots.count {
            guard let a = slots[i - 1].stop.coordinate,
                  let b = slots[i].stop.coordinate else { continue }
            let color = UIColor(TripDayPalette.color(slots[i].dayIndex))
            // 總覽圖逐段去要真實路徑會打幾十次網路，而且縮到這個比例根本看不出差別，
            // 所以整張圖一律畫直線；要看真實路線請開 App 裡的行程路線地圖。
            straights.append(([a, b], color))
        }
        let markers = pinned.map { slot in
            TripMapSnapshot.Marker(
                coordinate: slot.stop.coordinate ?? CLLocationCoordinate2D(),
                text: "\(slot.index + 1)",
                color: UIColor(TripDayPalette.color(slot.dayIndex)),
                isLodging: slot.stop.isOvernight,
                isMustVisit: slot.stop.isMustVisit)
        }
        return await TripMapSnapshot.image(
            coordinates: pinned.compactMap { $0.stop.coordinate },
            polylines: [],
            straights: straights,
            markers: markers,
            size: CGSize(width: TripCardStyle.cardWidth, height: 420),
            scale: 2)
    }

    // MARK: 分頁

    enum PageMode: Hashable, Identifiable {
        case single
        case byDay
        case count(Int)

        var id: String {
            switch self {
            case .single: return "1"
            case .byDay: return "day"
            case .count(let n): return "n\(n)"
            }
        }

        var label: String {
            switch self {
            case .single: return "一整張"
            case .byDay: return "一天一張"
            case .count(let n): return "\(n) 張"
            }
        }
    }

    /// 把時間軸切成幾頁。
    ///
    /// 依天切時，過夜的那一站會同時出現在前一天的結尾與隔天的開頭——它本來就是
    /// 兩天共用的那一站，只出現在其中一頁的話，另一頁會冒出一段不知從哪來的路。
    static func paginate(_ slots: [TripPlan.Slot], mode: PageMode) -> [[TripPlan.Slot]] {
        guard !slots.isEmpty else { return [] }
        switch mode {
        case .single:
            return [slots]
        case .byDay:
            var pages: [[TripPlan.Slot]] = []
            var current: [TripPlan.Slot] = []
            for slot in slots {
                if let last = current.last, last.dayIndex != slot.dayIndex {
                    pages.append(current)
                    // 換日：前一站如果是住宿，這一頁也從它開始，路才接得起來
                    current = last.stop.isOvernight ? [last, slot] : [slot]
                } else {
                    current.append(slot)
                }
            }
            if !current.isEmpty { pages.append(current) }
            return pages
        case .count(let n):
            let pages = max(1, min(n, slots.count))
            let per = Int((Double(slots.count) / Double(pages)).rounded(.up))
            return stride(from: 0, to: slots.count, by: max(1, per)).map { start in
                Array(slots[start..<min(start + per, slots.count)])
            }
        }
    }
}

// MARK: - 行程圖片匯出畫面

/// 選要切成幾張、要不要帶地圖，看一眼預覽再分享。
struct TripPlanImageExportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let plan: TripPlan

    @State private var mode: TripImageExporter.PageMode = .single
    @State private var includeMap = true
    @State private var previewImage: UIImage?
    @State private var isPreviewing = false
    @State private var isExporting = false
    @State private var previewTask: Task<Void, Never>?
    @State private var mapImage: UIImage?
    @State private var mapLoaded = false
    @State private var shareURLs: ShareURLs?
    @State private var failed = false

    private struct ShareURLs: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    private let accent = TripDayPalette.color(0)

    private var slots: [TripPlan.Slot] { plan.timeline }

    private var modes: [TripImageExporter.PageMode] {
        var out: [TripImageExporter.PageMode] = [.single]
        if plan.dayCount > 1 { out.append(.byDay) }
        // 站數不夠就不要給一堆只有一兩站的分頁選項
        for n in [2, 3, 4, 6] where n < slots.count { out.append(.count(n)) }
        return out
    }

    private var pages: [[TripPlan.Slot]] {
        TripImageExporter.paginate(slots, mode: mode)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    optionCard
                    previewCard
                    exportButton
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("分享成圖片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
            }
            .task { await loadMap() }
            .onChange(of: mode) { _, _ in schedulePreview() }
            .onChange(of: includeMap) { _, _ in schedulePreview() }
            .onDisappear { previewTask?.cancel() }
            .sheet(item: $shareURLs) { item in
                ShareSheet(items: item.urls)
            }
            .alert("出圖失敗", isPresented: $failed) {
                Button("好", role: .cancel) {}
            } message: {
                Text("這份行程太長，圖片做不出來。試試切成更多張，或關掉地圖再試一次。")
            }
        }
    }

    // MARK: 選項

    private var optionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("要切成幾張")
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(modes) { option in
                        Button {
                            mode = option
                        } label: {
                            Text(option.label)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(option == mode ? accent : Color(.tertiarySystemFill),
                                            in: Capsule())
                                .foregroundStyle(option == mode ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
            Toggle(isOn: $includeMap) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("第一張帶路線地圖").font(.subheadline)
                    Text("把所有景點畫在地圖上，依天分色")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(accent)
            .disabled(mapImage == nil && mapLoaded)
            Text(summaryText)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    /// 字串在 ViewBuilder 外組好
    private var summaryText: String {
        let counts = pages.map(\.count)
        var t = "會產生 \(pages.count) 張圖片"
        if pages.count > 1, let least = counts.min(), let most = counts.max() {
            t += least == most ? "，每張 \(most) 站" : "，每張 \(least)～\(most) 站"
        } else if let first = counts.first {
            t += "，共 \(first) 站"
        }
        if mode == .byDay && plan.overnightCount > 0 {
            t += "。住宿的那一站會同時出現在前一天的結尾與隔天的開頭——它本來就是兩天共用的。"
        }
        if mapImage == nil && mapLoaded {
            t += "\n（這份行程有座標的景點不到兩個，做不出地圖）"
        }
        return t
    }

    // MARK: 預覽

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("預覽").font(.subheadline.weight(.semibold))
                if pages.count > 1 {
                    Text("第 1 張").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if isPreviewing { ProgressView().scaleEffect(0.6) }
            }
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.separator).opacity(0.2), lineWidth: 0.75))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 220)
                    .overlay(
                        Text(isPreviewing ? "正在產生預覽…" : "預覽產生失敗")
                            .font(.caption).foregroundStyle(.secondary)
                    )
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var exportButton: some View {
        Button {
            Task { await export() }
        } label: {
            HStack(spacing: 6) {
                if isExporting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
                Text(isExporting ? "正在產生…" : "產生並分享 \(pages.count) 張")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(LinearGradient(colors: [accent, accent.opacity(0.75)],
                                       startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isExporting || pages.isEmpty)
        .padding(.horizontal)
    }

    // MARK: 產生

    @MainActor
    private func loadMap() async {
        guard !mapLoaded else { return }
        mapImage = await TripImageExporter.planMapImage(plan: plan)
        mapLoaded = true
        schedulePreview()
    }

    private func schedulePreview() {
        previewTask?.cancel()
        isPreviewing = true
        previewTask = Task {
            // 選項連按時不要每按一次就畫一張大圖
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                previewImage = TripImageExporter.render(card(at: 0))
                isPreviewing = false
            }
        }
    }

    @MainActor
    private func card(at index: Int) -> TripPlanShareCard {
        let all = pages
        return TripPlanShareCard(
            plan: plan,
            slots: all.indices.contains(index) ? all[index] : [],
            pageIndex: index,
            pageCount: all.count,
            mapImage: (index == 0 && includeMap) ? mapImage : nil)
    }

    @MainActor
    private func export() async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }

        let stamp = TripImageExporter.stampFormatter.string(from: Date())
        var urls: [URL] = []
        for index in pages.indices {
            // 每張之間讓一下，長行程出圖時畫面才不會整個凍住
            await Task.yield()
            let suffix = pages.count > 1 ? "_\(index + 1)" : ""
            guard let url = TripImageExporter.writeJPG(
                card(at: index),
                name: "\(plan.displayTitle)_\(stamp)\(suffix)") else { continue }
            urls.append(url)
        }
        guard !urls.isEmpty else { failed = true; return }
        shareURLs = ShareURLs(urls: urls)
    }
}
