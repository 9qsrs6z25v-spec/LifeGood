import SwiftUI
import MapKit

// MARK: - 地點選擇 Sheet（共用）

/// 變動支出輸入「店名 / 地點」時用的選擇器：上方搜尋框、下方兩 section
/// （之前去過 / Apple Maps）。POI-only，過濾掉純路名。
struct PlacePickerSheet: View {
    @EnvironmentObject var expenseStore: ExpenseStore
    @StateObject private var completer = RestaurantSearchCompleter()
    @ObservedObject private var locationProvider = LocationProvider.shared
    @Environment(\.dismiss) private var dismiss

    let category: VariableCategory
    let initialQuery: String
    /// 選擇結果（name / address / lat / lon），name 不為空，其他可選
    let onPick: (String, String?, Double?, Double?) -> Void

    @State private var query: String

    init(category: VariableCategory,
         initialQuery: String,
         onPick: @escaping (String, String?, Double?, Double?) -> Void) {
        self.category = category
        self.initialQuery = initialQuery
        self.onPick = onPick
        _query = State(initialValue: initialQuery)
    }

    /// 過去輸入過、含地點且名稱含 query 關鍵字的紀錄，依名稱去重
    private var pastPlaces: [PastPlace] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var seen: Set<String> = []
        var result: [PastPlace] = []
        for exp in expenseStore.expenses
            where exp.expenseType == .variable
                && exp.variableCategory == category
                && exp.placeLatitude != nil
                && exp.placeLongitude != nil
                && !exp.title.trimmingCharacters(in: .whitespaces).isEmpty {
            let key = "\(exp.title)|\(exp.placeAddress ?? "")"
            if seen.contains(key) { continue }
            if !q.isEmpty && !exp.title.lowercased().contains(q) { continue }
            seen.insert(key)
            result.append(PastPlace(
                name: exp.title,
                address: exp.placeAddress,
                latitude: exp.placeLatitude!,
                longitude: exp.placeLongitude!
            ))
            if result.count >= 30 { break }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                if !pastPlaces.isEmpty {
                    Section("之前去過") {
                        ForEach(pastPlaces) { p in
                            Button { pick(name: p.name, address: p.address, lat: p.latitude, lon: p.longitude) } label: {
                                placeRow(name: p.name, subtitle: p.address ?? "", icon: "clock.arrow.circlepath", color: .green)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !completer.results.isEmpty {
                    Section("Apple Maps") {
                        ForEach(Array(completer.results.enumerated()), id: \.offset) { _, c in
                            Button {
                                resolveAndPick(c)
                            } label: {
                                placeRow(name: c.title, subtitle: c.subtitle, icon: "mappin", color: .orange)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if pastPlaces.isEmpty && completer.results.isEmpty {
                    Section {
                        emptyHint
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: searchPrompt)
            .navigationTitle("選擇地點")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("用此名稱") {
                            pick(name: query.trimmingCharacters(in: .whitespaces),
                                 address: nil, lat: nil, lon: nil)
                        }
                        .foregroundStyle(.green)
                        .bold()
                    }
                }
            }
            .onAppear {
                LocationProvider.shared.requestIfNeeded()
                completer.setRegion(LocationProvider.shared.searchRegion)
                if !query.isEmpty { completer.queryFragment = query }
            }
            .onChange(of: query) { _, newValue in
                completer.queryFragment = newValue
            }
            .onChange(of: locationProvider.lastLocation) { _, _ in
                completer.setRegion(LocationProvider.shared.searchRegion)
                if !query.isEmpty { completer.queryFragment = query }
            }
        }
    }

    private var searchPrompt: String {
        switch category {
        case .food: return "店名 / 餐廳"
        case .entertainment: return "電影院 / KTV / 場館"
        case .shopping: return "百貨 / 商家"
        case .dailyNecessities: return "賣場 / 超市"
        case .medical: return "醫院 / 診所 / 藥局"
        default: return "搜尋地點"
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(query.isEmpty ? "輸入店名／關鍵字搜尋" : "找不到符合的地點")
                .font(.subheadline).foregroundStyle(.secondary)
            if !query.isEmpty {
                Text("可按右上角「用此名稱」直接套用。")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if locationProvider.authorization == .denied || locationProvider.authorization == .restricted {
                Text("提示：開啟「定位」權限可優先列出附近結果。")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
    }

    private func placeRow(name: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 32, height: 32)
                Image(systemName: icon).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func pick(name: String, address: String?, lat: Double?, lon: Double?) {
        onPick(name, address, lat, lon)
        dismiss()
    }

    private func resolveAndPick(_ c: MKLocalSearchCompletion) {
        // 先用 subtitle 帶過去，避免解析期間延遲
        let fallbackAddress = c.subtitle.isEmpty ? nil : c.subtitle
        completer.resolve(c) { item in
            let lat = item?.placemark.coordinate.latitude
            let lon = item?.placemark.coordinate.longitude
            let resolved = item?.formattedAddress ?? ""
            let address = resolved.isEmpty ? fallbackAddress : resolved
            self.pick(name: c.title, address: address, lat: lat, lon: lon)
        }
    }
}

private struct PastPlace: Identifiable {
    let name: String
    let address: String?
    let latitude: Double
    let longitude: Double
    var id: String { "\(name)|\(address ?? "")" }
}
