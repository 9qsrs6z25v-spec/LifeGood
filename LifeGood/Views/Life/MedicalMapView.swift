import SwiftUI
import MapKit
import UIKit

// MARK: - 醫療地圖 ＋ 健康狀況總結
// 以健康檔案（HealthProfile）為核心做「健康狀況總結」，並結合：
//   • 醫療變動支出（就醫地點撒點於地圖、今年就診次數/花費、收據照片）
//   • 健康里程碑（MilestoneCategory.health）
//   • 醫療 / 意外保險（財富里程碑中 insuranceType 為醫療/意外者）
// 主題色為醫療青綠（teal）。

// MARK: - 美化紀錄（MedicalMapView）2026-07
// [2026-07] 首次美化方向：
//   1. 金額顯示改用共用 Double.ntdWanString（FinanceModels.swift），支援「萬 / 億」
//      量級自動切換（原本每個 struct 各自維護一份只到「萬」量級的 fmtShort/decimalFmt，
//      已移除重複程式碼），對齊全 App 金額顯示規格，避免醫療支出達億量級時顯示過長。
//   2. 新增 rowIcon(_:color:) 輔助函式：36pt 漸層圓形圖示（LinearGradient 0.22→0.09 +
//      shadow opacity 0.18 + 細邊框），套用到過敏／用藥／健檢／健康里程碑／醫療保障
//      列行，對齊 HealthProfileEditView.rowIcon 規格，取代原本純文字列，提升可掃視性；
//      各列主題色沿用 HealthProfileEditView 對照：過敏(orange)／用藥(blue)／
//      健檢(purple)／里程碑・保障(teal 主色)。
//   3. 量測趨勢列：日期加入 caption2 calendar 圖示（粉色），數值改為粉色 metric chip
//      （底色 10% + 細邊框），取代純文字串接，對齊 HealthProfileEditView 量測列規格。
//   4. 加了圖示的列行同步將 Divider 左內縮從 14pt 調整為 62pt（14 邊距 + 36 圖示 +
//      12 間距），使分隔線與文字對齊，非圖示列（服用中藥物無圖示時對齊需求不同）維持原值。
//   5. emptyHint 加入圖示參數，對齊 SubordinateRosterView / HealthProfileEditView 空
//      狀態列規格（圖示 + 說明文字），取代純文字提示。
//   6. BMI／今年醫療支出等大字數值補上 minimumScaleFactor，避免大字級裝置或億量級金額
//      被截斷，但不縮到無法辨識。
//   7. MedicalPlaceDetailSheet 小節標題（照片/收據、就診紀錄）改用 Label 加圖示並統一
//      teal 主題色；關閉按鈕維持 topBarLeading（左側），符合全 App 一致慣例。
//   8. 未變動任何地圖標註、資料聚合（placeAggregates／healthMilestones／
//      insuranceMilestones）、篩選或排序等既有商業邏輯。
//
// [2026-07 v2] MedicalPlaceDetailSheet.photoRow 縮圖載入：
//   9. 原本在 view body 內以 UIImage(contentsOfFile:) 同步讀檔（每次 ScrollView 重繪都可能
//      阻塞主執行緒，且無載入中狀態，與 v22.28 已修復的 MultiPhotoGallery 同型問題），
//      改共用 MultiPhotoGallery.AsyncThumbnailView（已從 private 開放為 internal）：
//      背景執行緒讀檔 + 載入中佔位（漸層底 + icloud 圖示 +「載入中」文字）+ cornerRadius 12
//      統一縮圖圓角，對齊 MultiPhotoGallery 縮圖規格。純顯示層調整，就診紀錄／花費加總等既有
//      邏輯未變動。（下次美化本檔案時，可比照同一模式接續處理其餘手刻縮圖畫面，如
//      FamilyMembersResumeView／TravelMapView／OrganizationView／FoodMapView／
//      BusinessCardView／RenovationPhotoEditor／RealEstateDetailView 內仍殘留的
//      UIImage(contentsOfFile:) 同步讀檔。）

// MARK: - 就醫地點聚合

struct MedicalPlaceAggregate: Identifiable {
    let id: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let visits: [Expense]
    var visitCount: Int { visits.count }
    var totalSpent: Double { visits.reduce(0) { $0 + $1.amount } }
    var lastVisit: Date? { visits.map(\.date).max() }
    var photoNames: [String] { visits.flatMap { $0.photoFileNames } }
}

// MARK: - 主畫面

struct MedicalMapView: View {
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore

    private let accent = Color.teal

    @State private var showEditProfile = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedPlace: MedicalPlaceAggregate?

    private var health: HealthProfile { lifeStore.healthProfile }

    var body: some View {
        // 各自算一次後往下傳參數，避免 placeAggregates（Dictionary(grouping:)）與
        // healthMilestones / insuranceMilestones（filter+sort）在 body 內被多處重複呼叫。
        let medExpenses = medicalExpenses
        let places = placeAggregates(from: medExpenses)
        let healthMs = healthMilestones
        let insuranceMs = insuranceMilestones
        return NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    summaryCard(medExpenses)
                    if !places.isEmpty { clinicMapSection(places) }
                    measurementSection
                    if !health.allergies.isEmpty { allergySection }
                    if !health.activeMedications.isEmpty { medicationSection }
                    checkupSection
                    if !healthMs.isEmpty { milestoneSection(healthMs) }
                    if !insuranceMs.isEmpty { insuranceSection(insuranceMs) }
                }
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("醫療地圖")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEditProfile = true } label: {
                        Label("健康檔案", systemImage: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showEditProfile) {
                HealthProfileEditView(profile: health).environmentObject(lifeStore)
            }
            .sheet(item: $selectedPlace) { place in
                MedicalPlaceDetailSheet(place: place)
            }
        }
    }

    // MARK: - 健康狀況總結英雄卡

    private func summaryCard(_ medExpenses: [Expense]) -> some View {
        let thisYear = medExpenses.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .year) }
        let thisYearVisits = thisYear.count
        let thisYearSpend = thisYear.reduce(0) { $0 + $1.amount }
        return VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("健康狀況總結").font(.caption).foregroundStyle(.white.opacity(0.85))
                    if let bmi = health.bmi {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(String(format: "BMI %.1f", bmi))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            if let cat = health.bmiCategory {
                                Text(cat).font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.white.opacity(0.22)).clipShape(Capsule())
                            }
                        }
                    } else {
                        Text("尚未建立健康檔案")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                Spacer()
                if !health.bloodType.isEmpty {
                    VStack(spacing: 2) {
                        Text(health.bloodType).font(.headline).foregroundStyle(.white)
                        Text("血型").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.white.opacity(0.18)).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            HStack(spacing: 0) {
                summaryKpi(icon: "heart.fill", value: bpText, label: "最近血壓")
                divider
                summaryKpi(icon: "pills.fill", value: "\(health.activeMedications.count)", label: "服用中")
                divider
                summaryKpi(icon: "cross.case.fill", value: "\(thisYearVisits)", label: "今年就診")
                divider
                summaryKpi(icon: "calendar", value: nextDueText, label: "下次回診")
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack {
                Label("今年醫療支出", systemImage: "dollarsign.circle.fill")
                    .font(.caption).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(thisYearSpend.ntdWanString)
                    .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .padding(20)
        .background(
            ZStack {
                LinearGradient(colors: [Color(red: 0.10, green: 0.62, blue: 0.58),
                                        Color(red: 0.04, green: 0.44, blue: 0.52)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.10)).frame(width: 120, height: 120)
                    .offset(x: 90, y: -40).blur(radius: 12)
                LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center)
                    .allowsHitTesting(false)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.04, green: 0.44, blue: 0.52).opacity(0.35), radius: 14, x: 0, y: 7)
        .padding(.horizontal)
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 30)
    }

    private func summaryKpi(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(.white.opacity(0.9))
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.55)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 2)
    }

    // MARK: - 就醫地圖

    private func clinicMapSection(_ places: [MedicalPlaceAggregate]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("就醫地點", icon: "cross.case.fill", trailing: "\(places.count) 處")
            Map(position: $cameraPosition) {
                ForEach(places) { place in
                    Annotation(place.name, coordinate: place.coordinate) {
                        Button { selectedPlace = place } label: {
                            ZStack {
                                Circle().fill(accent).frame(width: 30, height: 30).shadow(radius: 2)
                                Image(systemName: "cross.fill").font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(Array(places.sorted { $0.visitCount > $1.visitCount }.enumerated()),
                        id: \.element.id) { idx, place in
                    Button { selectedPlace = place } label: { clinicRow(place) }
                        .buttonStyle(.plain)
                    if idx < places.count - 1 { Divider().padding(.leading, 62) }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func clinicRow(_ place: MedicalPlaceAggregate) -> some View {
        HStack(spacing: 12) {
            rowIcon("cross.case", color: accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name.isEmpty ? "就醫地點" : place.name)
                    .font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                Text("就診 \(place.visitCount) 次").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(place.totalSpent.ntdWanString)
                .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
    }

    // MARK: - 量測

    private var measurementSection: some View {
        let recent = health.measurements.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("量測趨勢", icon: "waveform.path.ecg", trailing: "\(recent.count) 筆")
            if recent.isEmpty {
                emptyHint("尚無量測；點右上『健康檔案』新增體重 / 血壓", icon: "waveform.path.ecg")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.prefix(6).enumerated()), id: \.element.id) { idx, m in
                        HStack(spacing: 8) {
                            Image(systemName: "calendar").font(.caption2).foregroundStyle(.pink)
                            Text(Self.dateFmt.string(from: m.date)).font(.subheadline)
                            Spacer()
                            Text(measurementSummary(m))
                                .font(.caption2.weight(.semibold)).foregroundStyle(.pink)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.pink.opacity(0.10)).clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.pink.opacity(0.20), lineWidth: 0.6))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        if idx < min(recent.count, 6) - 1 { Divider().padding(.leading, 14) }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 過敏

    private var allergySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("過敏", icon: "allergens", trailing: "\(health.allergies.count) 項")
            VStack(spacing: 0) {
                ForEach(Array(health.allergies.enumerated()), id: \.element.id) { idx, a in
                    HStack(spacing: 12) {
                        rowIcon("allergens", color: .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name.isEmpty ? "未命名" : a.name).font(.subheadline.weight(.medium))
                            if !a.reaction.isEmpty {
                                Text(a.reaction).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let s = a.severity {
                            Text(s.rawValue).font(.caption2).foregroundStyle(.orange)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.orange.opacity(0.12)).clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.orange.opacity(0.22), lineWidth: 0.6))
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    if idx < health.allergies.count - 1 { Divider().padding(.leading, 62) }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 用藥

    private var medicationSection: some View {
        let meds = health.activeMedications
        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("服用中藥物", icon: "pills.fill", trailing: "\(meds.count) 種")
            VStack(spacing: 0) {
                ForEach(Array(meds.enumerated()), id: \.element.id) { idx, m in
                    HStack(spacing: 12) {
                        rowIcon("pills.fill", color: .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.name.isEmpty ? "未命名藥物" : m.name).font(.subheadline.weight(.medium))
                            if !m.dosage.isEmpty {
                                Text(m.dosage).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    if idx < meds.count - 1 { Divider().padding(.leading, 62) }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 健檢

    private var checkupSection: some View {
        let checkups = health.checkups.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("健檢紀錄", icon: "stethoscope", trailing: "\(checkups.count) 筆")
            if let due = health.nextDue {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill").foregroundStyle(.orange)
                    Text("下次回診：\(Self.dateFmt.string(from: due.date))")
                        .font(.caption.weight(.medium))
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            if checkups.isEmpty {
                emptyHint("尚無健檢紀錄；點右上『健康檔案』新增", icon: "stethoscope")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(checkups.prefix(6).enumerated()), id: \.element.id) { idx, c in
                        HStack(alignment: .top, spacing: 12) {
                            rowIcon("stethoscope", color: .purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title.isEmpty ? "健檢" : c.title).font(.subheadline.weight(.medium))
                                HStack(spacing: 6) {
                                    Text(Self.dateFmt.string(from: c.date))
                                    if !c.place.isEmpty { Text("· \(c.place)") }
                                }.font(.caption).foregroundStyle(.secondary)
                                if !c.result.isEmpty {
                                    Text(c.result).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        if idx < min(checkups.count, 6) - 1 { Divider().padding(.leading, 62) }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 健康里程碑

    private func milestoneSection(_ items: [LifeMilestone]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("健康里程碑", icon: "cross.fill", trailing: "\(items.count) 筆")
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, ms in
                    HStack(alignment: .top, spacing: 12) {
                        rowIcon("cross.fill", color: accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ms.title.isEmpty ? "健康事件" : ms.title).font(.subheadline.weight(.medium))
                            Text(Self.dateFmt.string(from: ms.date)).font(.caption).foregroundStyle(.secondary)
                            if !ms.note.isEmpty {
                                Text(ms.note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    if idx < items.count - 1 { Divider().padding(.leading, 62) }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 醫療保障

    private func insuranceSection(_ items: [LifeMilestone]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("醫療保障", icon: "checkmark.shield.fill", trailing: "\(items.count) 張")
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, ms in
                    HStack(spacing: 12) {
                        rowIcon("checkmark.shield.fill", color: accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(insuranceTitle(ms)).font(.subheadline.weight(.medium))
                            if let company = ms.insuranceCompany, !company.isEmpty {
                                Text(company).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let t = ms.insuranceType {
                            Text(t.rawValue).font(.caption2).foregroundStyle(accent)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(accent.opacity(0.12)).clipShape(Capsule())
                                .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    if idx < items.count - 1 { Divider().padding(.leading, 62) }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 共用小元件

    private func sectionHeader(_ title: String, icon: String, trailing: String) -> some View {
        HStack(spacing: 10) {
            Capsule().fill(LinearGradient(colors: [accent, accent.opacity(0.55)],
                                          startPoint: .top, endPoint: .bottom)).frame(width: 4, height: 18)
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(accent)
            Text(title).font(.subheadline.weight(.bold))
            Spacer()
            Text(trailing).font(.caption2.weight(.semibold)).foregroundStyle(accent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(accent.opacity(0.10)).clipShape(Capsule())
                .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.75))
        }
        .padding(.horizontal)
    }

    private func emptyHint(_ text: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(.tertiary)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// 依主題色繪製 36pt 漸層圓形圖示，對齊 HealthProfileEditView.rowIcon 列行圖示規格
    private func rowIcon(_ systemName: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.09)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 36, height: 36)
                .shadow(color: color.opacity(0.18), radius: 5, x: 0, y: 2)
            Circle().stroke(color.opacity(0.18), lineWidth: 1).frame(width: 36, height: 36)
            Image(systemName: systemName).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
        }
    }

    // MARK: - 資料

    private var medicalExpenses: [Expense] {
        expenseStore.expenses.filter { $0.expenseType == .variable && $0.variableCategory == .medical }
    }

    private func placeAggregates(from medExpenses: [Expense]) -> [MedicalPlaceAggregate] {
        let located = medExpenses.filter { $0.placeLatitude != nil && $0.placeLongitude != nil }
        let groups = Dictionary(grouping: located) { "\($0.title)|\($0.placeAddress ?? "")" }
        return groups.compactMap { key, exps in
            guard let first = exps.first, let lat = first.placeLatitude, let lon = first.placeLongitude else { return nil }
            return MedicalPlaceAggregate(
                id: key, name: first.title, address: first.placeAddress ?? "",
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), visits: exps)
        }
    }

    private var healthMilestones: [LifeMilestone] {
        lifeStore.milestones.filter { $0.category == .health }.sorted { $0.date > $1.date }
    }

    private var insuranceMilestones: [LifeMilestone] {
        lifeStore.milestones.filter {
            $0.insuranceType == .health || $0.insuranceType == .accident
        }.sorted { $0.date > $1.date }
    }

    // MARK: - 文字

    private var bpText: String {
        if let bp = health.latestBloodPressure { return "\(bp.systolic)/\(bp.diastolic)" }
        return "—"
    }
    private var nextDueText: String {
        guard let due = health.nextDue else { return "—" }
        return Self.shortDateFmt.string(from: due.date)
    }

    private func insuranceTitle(_ ms: LifeMilestone) -> String {
        if !ms.title.isEmpty { return ms.title }
        if let t = ms.insuranceType { return t.rawValue + "險" }
        return "保單"
    }

    private func measurementSummary(_ m: HealthMeasurement) -> String {
        var parts: [String] = []
        if let w = m.weightKg { parts.append(String(format: "%.1fkg", w)) }
        if let s = m.systolic, let d = m.diastolic { parts.append("\(s)/\(d)") }
        if let h = m.heartRate { parts.append("\(h)bpm") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()
    static let shortDateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()
}

// MARK: - 就醫地點詳情 Sheet

struct MedicalPlaceDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let place: MedicalPlaceAggregate

    private let accent = Color.teal
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var viewingPhotoURL: IdentifiableURL?

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d (E)"; return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Map(position: $cameraPosition) {
                        Marker(place.name, coordinate: place.coordinate).tint(.teal)
                    }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    HStack(spacing: 0) {
                        kpi("就診", "\(place.visitCount) 次")
                        kpi("累計", place.totalSpent.ntdWanString)
                        if let last = place.lastVisit { kpi("最近", Self.dateFmt.string(from: last)) }
                    }
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    if !place.photoNames.isEmpty { photoRow }
                    visitsList
                }
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(place.name.isEmpty ? "就醫地點" : place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } } }
            .onAppear {
                cameraPosition = .region(MKCoordinateRegion(
                    center: place.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000))
            }
            .sheet(item: $viewingPhotoURL) { w in PhotoLightbox(url: w.url) }
        }
    }

    private func kpi(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private var photoRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("照片 / 收據", systemImage: "photo.on.rectangle.angled")
                .font(.subheadline.weight(.bold)).foregroundStyle(accent).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(place.photoNames, id: \.self) { name in
                        let url = Expense.photoURL(for: name)
                        Button { viewingPhotoURL = IdentifiableURL(url: url) } label: {
                            AsyncThumbnailView(url: url, size: CGSize(width: 110, height: 90))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var visitsList: some View {
        let sorted = place.visits.sorted { $0.date > $1.date }
        return VStack(alignment: .leading, spacing: 8) {
            Label("就診紀錄", systemImage: "list.bullet.clipboard")
                .font(.subheadline.weight(.bold)).foregroundStyle(accent).padding(.horizontal)
            VStack(spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, exp in
                    HStack(spacing: 8) {
                        Image(systemName: "calendar").font(.caption2).foregroundStyle(accent)
                        Text(Self.dateFmt.string(from: exp.date)).font(.subheadline)
                        Spacer()
                        Text(exp.amount.ntdWanString)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    if idx < sorted.count - 1 { Divider().padding(.leading, 14) }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}
