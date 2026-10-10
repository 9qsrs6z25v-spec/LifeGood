import Foundation
import MapKit
import UIKit

// MARK: - 旅遊規劃的分享與地圖跳轉
//
// [v25.407] 把「組文字」與「組地圖連結」從畫面裡抽出來：
// 這些是純函式，跟 SwiftUI 無關，放在這裡才好一眼看完格式、也不會再把
// TripPlanView 撐長。
//
// 連結一律用 Apple 地圖的通用連結（https://maps.apple.com/…）而不是自訂 scheme：
// 在 iPhone / Mac 上會直接開 Apple 地圖，傳給沒有 Apple 裝置的人也還是一個
// 打得開的網頁，不會變成一串點不動的文字。

enum TripShare {

    // MARK: - 地圖連結

    /// 單一地點的連結。有座標就用座標（最準），只有地址就用地址查。
    static func placeURL(name: String, address: String,
                         latitude: Double?, longitude: Double?) -> URL? {
        var items: [URLQueryItem] = []
        let q = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? address.trimmingCharacters(in: .whitespaces)
            : name.trimmingCharacters(in: .whitespaces)
        if let latitude, let longitude {
            items.append(URLQueryItem(name: "ll", value: String(format: "%.6f,%.6f",
                                                                latitude, longitude)))
            if !q.isEmpty { items.append(URLQueryItem(name: "q", value: q)) }
        } else {
            let address = address.trimmingCharacters(in: .whitespaces)
            guard !address.isEmpty || !q.isEmpty else { return nil }
            items.append(URLQueryItem(name: "address",
                                      value: address.isEmpty ? q : address))
        }
        var comps = URLComponents(string: "https://maps.apple.com/")
        comps?.queryItems = items
        return comps?.url
    }

    static func placeURL(_ stop: TripStop) -> URL? {
        placeURL(name: stop.name, address: stop.address,
                 latitude: stop.latitude, longitude: stop.longitude)
    }

    /// 兩點之間的導航連結。
    /// dirflg：d＝開車、w＝步行、r＝大眾運輸。飛機沒有對應的模式，用開車帶過去
    ///（到了 Apple 地圖裡本來就要自己改，總比連結打不開好）。
    static func directionsURL(from: TripStop, to: TripStop,
                              mode: TripTravelMode) -> URL? {
        func point(_ s: TripStop) -> String? {
            if let la = s.latitude, let lo = s.longitude {
                return String(format: "%.6f,%.6f", la, lo)
            }
            let a = s.address.trimmingCharacters(in: .whitespaces)
            let n = s.name.trimmingCharacters(in: .whitespaces)
            let t = a.isEmpty ? n : a
            return t.isEmpty ? nil : t
        }
        guard let a = point(from), let b = point(to) else { return nil }
        var comps = URLComponents(string: "https://maps.apple.com/")
        comps?.queryItems = [
            URLQueryItem(name: "saddr", value: a),
            URLQueryItem(name: "daddr", value: b),
            URLQueryItem(name: "dirflg", value: dirFlag(mode))
        ]
        return comps?.url
    }

    private static func dirFlag(_ mode: TripTravelMode) -> String {
        switch mode {
        case .walking: return "w"
        case .transit: return "r"
        case .driving, .plane: return "d"
        }
    }

    // MARK: - 直接開 Apple 地圖

    static func openPlaceInMaps(_ stop: TripStop) {
        if let c = stop.coordinate {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
            item.name = stop.displayName
            item.openInMaps()
        } else if let url = placeURL(stop) {
            UIApplication.shared.open(url)
        }
    }

    /// 開 Apple 地圖的路線規劃。
    ///
    /// 大眾運輸特別值得走這條：App 內算不出大眾運輸路線（Apple 不開放），
    /// 但 Apple 地圖自己做得到——這正是官方留給我們的那條路。
    static func openDirectionsInMaps(from: TripStop, to: TripStop,
                                     mode: TripTravelMode) {
        guard let a = from.coordinate, let b = to.coordinate else {
            // 沒座標就退回用連結（帶地址），總比什麼都不做好
            if let url = directionsURL(from: from, to: to, mode: mode) {
                UIApplication.shared.open(url)
            }
            return
        }
        let src = MKMapItem(placemark: MKPlacemark(coordinate: a))
        src.name = from.displayName
        let dst = MKMapItem(placemark: MKPlacemark(coordinate: b))
        dst.name = to.displayName
        let modeKey: String
        switch mode {
        case .walking: modeKey = MKLaunchOptionsDirectionsModeWalking
        case .transit: modeKey = MKLaunchOptionsDirectionsModeTransit
        case .driving, .plane: modeKey = MKLaunchOptionsDirectionsModeDriving
        }
        MKMapItem.openMaps(with: [src, dst],
                           launchOptions: [MKLaunchOptionsDirectionsModeKey: modeKey])
    }

    // MARK: - 文字

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d (E)"; return f
    }()
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "HH:mm"; return f
    }()

    /// 整份行程。排成純文字而不是檔案：貼到 LINE／訊息／郵件都直接看得懂，
    /// 對方不用裝這個 App 也不用開附件。
    static func planText(_ plan: TripPlan) -> String {
        var out: [String] = [plan.displayTitle]
        out.append(dayFmt.string(from: plan.startDate) + " "
                   + timeFmt.string(from: plan.startDate)
                   + " → " + dayFmt.string(from: plan.endDate) + " "
                   + timeFmt.string(from: plan.endDate))
        var meta = ["\(plan.stops.count) 站"]
        if plan.dayCount > 1 { meta.append("\(plan.dayCount) 天") }
        if plan.overnightCount > 0 { meta.append("住宿 \(plan.overnightCount) 晚") }
        if plan.totalTravelSeconds > 0 {
            meta.append("交通 " + TripRouter.durationText(plan.totalTravelSeconds))
        }
        if plan.totalMeters > 0 { meta.append(TripRouter.distanceText(plan.totalMeters)) }
        out.append(meta.joined(separator: "・"))

        let note = plan.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { out.append(note) }

        let slots = plan.timeline
        var lastDay = -1
        for slot in slots {
            if slot.dayIndex != lastDay {
                lastDay = slot.dayIndex
                let date = Calendar.current.date(byAdding: .day, value: slot.dayIndex,
                                                 to: plan.startDate) ?? plan.startDate
                out.append("")
                out.append("── 第 \(slot.dayIndex + 1) 天 " + dayFmt.string(from: date) + " ──")
                // 住宿的地方是前一天的最後一站，也是這一天的第一站，這裡補一行說明
                if slot.index > 0, slots[slot.index - 1].stop.isOvernight {
                    out.append(timeFmt.string(from: slots[slot.index - 1].departure)
                               + "  從「" + slots[slot.index - 1].stop.displayName + "」出發")
                }
            }
            if slot.index > 0 {
                out.append("   ↓ " + legLine(slot))
            }
            out.append(contentsOf: stopLines(slot))
        }
        return out.joined(separator: "\n")
    }

    /// 單一景點。給「把這個地方傳給朋友」用，所以連結一定要在。
    static func stopText(_ stop: TripStop, in plan: TripPlan) -> String {
        var out: [String] = []
        var title = stop.displayName
        if stop.isMustVisit { title += "（必去）" }
        if stop.isOvernight { title += "（住宿）" }
        out.append(title)
        if let slot = plan.timeline.first(where: { $0.stop.id == stop.id }) {
            let date = Calendar.current.date(byAdding: .day, value: slot.dayIndex,
                                             to: plan.startDate) ?? plan.startDate
            out.append(dayFmt.string(from: date) + " "
                       + timeFmt.string(from: slot.arrival)
                       + "–" + timeFmt.string(from: slot.departure)
                       + (stop.isOvernight ? "" : "・停留 \(stop.dwellMinutes) 分"))
        }
        let address = stop.displayAddress
        if !address.isEmpty { out.append(address) }
        // [v25.500] 電話跟著一起分享。分享行程最常見的情境就是傳給開車的那個人，
        // 而在日本他要輸進車機的正是這一串數字。
        if let raw = stop.phone, !raw.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append("☎ " + TripPhone.navDigits(raw))
        }
        if !stop.subSpots.isEmpty {
            out.append("子地點：" + stop.subSpots.map { s in
                let n = s.name.trimmingCharacters(in: .whitespaces)
                return (n.isEmpty ? "未命名" : n) + (s.minutes > 0 ? "（\(s.minutes) 分）" : "")
            }.joined(separator: "、"))
        }
        let note = stop.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { out.append(note) }
        if let url = placeURL(stop) { out.append(url.absoluteString) }
        out.append("—— 來自「\(plan.displayTitle)」")
        return out.joined(separator: "\n")
    }

    /// 單一段路。
    static func legText(_ plan: TripPlan, index: Int) -> String {
        let slots = plan.timeline
        guard slots.indices.contains(index), index > 0 else { return "" }
        let from = slots[index - 1], to = slots[index]
        var out = [from.stop.displayName + " → " + to.stop.displayName]
        out.append(timeFmt.string(from: from.departure) + " 出發，"
                   + timeFmt.string(from: to.arrival) + " 抵達")
        out.append(legLine(to))
        if let url = directionsURL(from: from.stop, to: to.stop, mode: to.mode) {
            out.append(url.absoluteString)
        }
        out.append("—— 來自「\(plan.displayTitle)」")
        return out.joined(separator: "\n")
    }

    // MARK: 內部

    private static func legLine(_ slot: TripPlan.Slot) -> String {
        var t = slot.mode.rawValue + " "
        if let s = slot.travelSeconds {
            t += TripRouter.durationText(s)
            if let m = slot.travelMeters { t += "・" + TripRouter.distanceText(m) }
            if slot.isEstimated { t += "（估）" }
        } else {
            t += "未計算路線"
        }
        if slot.shortfallSeconds > 60 {
            t += "　⚠️ 比指定抵達時間晚 " + TripRouter.durationText(slot.shortfallSeconds)
        } else if slot.index > 0 && slot.idleSeconds > 300 {
            t += "　等 " + TripRouter.durationText(slot.idleSeconds)
        }
        return t
    }

    private static func stopLines(_ slot: TripPlan.Slot) -> [String] {
        var head = timeFmt.string(from: slot.arrival) + "  " + slot.stop.displayName
        if slot.stop.isMustVisit { head += " ★" }
        if slot.isFixedArrival { head += "（指定抵達）" }
        var lines = [head]
        if slot.stop.isOvernight {
            lines.append("       住宿・隔天 " + timeFmt.string(from: slot.departure) + " 出發")
        } else if slot.stop.dwellMinutes > 0 {
            lines.append("       停留 \(slot.stop.dwellMinutes) 分，"
                         + timeFmt.string(from: slot.departure) + " 離開")
        }
        let address = slot.stop.displayAddress
        if !address.isEmpty { lines.append("       " + address) }
        if let raw = slot.stop.phone, !raw.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("       ☎ " + TripPhone.navDigits(raw))
        }
        if !slot.stop.subSpots.isEmpty {
            lines.append("       ・" + slot.stop.subSpots.map { s in
                let n = s.name.trimmingCharacters(in: .whitespaces)
                return (n.isEmpty ? "未命名" : n) + (s.minutes > 0 ? "（\(s.minutes) 分）" : "")
            }.joined(separator: "、"))
        }
        let note = slot.stop.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            // 備註可能好幾行，每一行都要對齊，不然貼出去會參差不齊
            lines.append(contentsOf: note.split(separator: "\n", omittingEmptySubsequences: false)
                .map { "       " + $0 })
        }
        if let url = placeURL(slot.stop) { lines.append("       " + url.absoluteString) }
        return lines
    }
}
