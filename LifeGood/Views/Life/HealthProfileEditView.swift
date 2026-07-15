import SwiftUI

// MARK: - 健康檔案編輯
// 編輯 LifeStore.healthProfile：基本資料（血型/身高）、過敏、用藥、量測（體重/血壓/心率）、健檢。
// 以草稿（draft）編輯，按「儲存」才寫回 store，避免每次鍵入都觸發 iCloud 上傳。

// MARK: - 美化紀錄（HealthProfileEditView）2026-07
// [2026-07] 首次美化方向：
//   1. 新增 healthSectionHeader(title:icon:color:count:) 輔助函式：4pt 漸層 Capsule 色條 +
//      彩色圖示 + .subheadline.semibold + 計數膠囊（附細邊框），對齊全 App Form 型編輯頁
//      設計語言（AddVehicleView.vehicleSectionHeader / AddSavingsInsuranceView 規格）。
//      七個 Section 各配獨立主題色：基本資料(teal)／病史(indigo)／過敏(orange)／
//      用藥(blue)／量測(pink)／健檢(purple)／備註(secondary)，提升可掃視性。
//   2. 過敏／用藥／健檢列行：加入 36pt 主題色漸層圓形圖示（LinearGradient 0.22→0.09 +
//      shadow opacity 0.18），對齊 AddVehicleView.fixedExpenseSection 列行圖示規格。
//   3. 量測列行：日期改用 calendar 圖示 + Capsule 徽章；體重/血壓/心率改為獨立彩色
//      metric chip（各自底色 12% + 細邊框），取代原本純文字串接，對齊
//      OverviewView.categoryRow 徽章化數值呈現規格。
//   4. 病史／過敏／用藥／量測／健檢五個列表新增輕量空狀態列（secondary caption + 圖示），
//      對齊 SubordinateRosterView / LifeRealEstateView 空狀態列規格。
//   5. BMI 數值：字級升級為 .title3.bold + minimumScaleFactor(0.7) 避免大字級裝置被截斷；
//      分類膠囊加入對應色系圖示，維持在可辨識最小字級以上。
//   6. 保留原有 toolbar 佈局（取消固定左側／儲存固定右側，符合全 App 一致慣例），
//      未變動任何草稿寫回、刪除、upsert 等既有商業邏輯。
// [2026-07 v2] 修正病史列與同頁其他小節不一致：
//   7. conditionsSection 先前直接輸出裸 Text(c)，是全頁唯一沒有 rowIcon 圖示圓的清單列，
//      與過敏／用藥／健檢三個小節（皆有 36pt 主題色漸層圖示圓）形成明顯落差；
//      新增 conditionRow(_:) 補上 indigo 主題圖示圓，對齊 healthSectionHeader 同色系。
// [2026-07 v3] 補齊四個子編輯 sheet 的視覺規格：
//   8. AllergyEditor／MedicationEditor／MeasurementEditor／CheckupEditor 先前皆為裸 Form
//      （欄位直接平鋪、無任何 Section 分組與標題），與外層清單「4pt 漸層色條 + 圖示 + 標題」
//      的 healthSectionHeader 規格落差最大。新增共用 healthEditorSectionHeader(_:icon:color:)
//      （與 healthSectionHeader 同款式，僅省略計數膠囊），四個 sheet 各自比照外層對應小節的
//      主題色分組：過敏(orange)／用藥(blue)／量測(pink)／健檢(purple)，備註欄一律歸入獨立的
//      secondary 色「備註」小節，與外層 noteSection 呼應。
//   9. MeasurementEditor 原本用純字串 Section("血壓") 當標題，改為與其餘小節一致的色條樣式；
//      並將「日期」「體重 / 心率」「血壓」拆為三個獨立小節，取代原本欄位全部平鋪一排的排法。
//   10. 純版面調整，未變動任何草稿欄位、儲存/取消 callback 或 upsert 商業邏輯。
//   下次美化方向：本檔案七大 Section 與四個子編輯 sheet 已完成規格對齊；可留意
//   AllergySeverity Picker 目前仍是系統預設樣式，未來如需可考慮改為分段色塊選擇器。

struct HealthProfileEditView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: HealthProfile

    @State private var editingAllergy: HealthAllergy?
    @State private var editingMedication: HealthMedication?
    @State private var editingMeasurement: HealthMeasurement?
    @State private var editingCheckup: HealthCheckup?
    @State private var newCondition: String = ""

    private let accent = Color.teal

    init(profile: HealthProfile) {
        _draft = State(initialValue: profile)
    }

    var body: some View {
        NavigationStack {
            Form {
                basicSection
                conditionsSection
                allergySection
                medicationSection
                measurementSection
                checkupSection
                noteSection
            }
            .navigationTitle("健康檔案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") {
                        lifeStore.updateHealthProfile(draft)
                        dismiss()
                    }.bold()
                }
            }
            .sheet(item: $editingAllergy) { item in
                AllergyEditor(allergy: item) { upsert($0, into: &draft.allergies) }
            }
            .sheet(item: $editingMedication) { item in
                MedicationEditor(medication: item) { upsert($0, into: &draft.medications) }
            }
            .sheet(item: $editingMeasurement) { item in
                MeasurementEditor(measurement: item) { upsert($0, into: &draft.measurements) }
            }
            .sheet(item: $editingCheckup) { item in
                CheckupEditor(checkup: item) { upsert($0, into: &draft.checkups) }
            }
        }
    }

    // MARK: - 基本資料

    private var basicSection: some View {
        Section {
            HStack {
                Text("血型")
                Spacer()
                TextField("例：O、A、AB+", text: $draft.bloodType)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("身高")
                Spacer()
                TextField("公分", value: $draft.heightCm, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                Text("cm").foregroundStyle(.secondary)
            }
            if let bmi = draft.bmi {
                HStack {
                    Text("BMI")
                    Spacer()
                    Text(String(format: "%.1f", bmi))
                        .font(.title3.bold())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .foregroundStyle(accent)
                    if let cat = draft.bmiCategory {
                        Label(cat, systemImage: "heart.text.square.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(accent.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                    }
                }
            }
        } header: {
            healthSectionHeader("基本資料", icon: "person.text.rectangle.fill", color: accent)
        }
    }

    // MARK: - 慢性病 / 病史

    private var conditionsSection: some View {
        Section {
            if draft.conditions.isEmpty {
                emptyRow(icon: "list.bullet.clipboard", text: "尚無慢性病 / 病史紀錄")
            }
            ForEach(Array(draft.conditions.enumerated()), id: \.offset) { idx, c in
                conditionRow(c)
            }
            .onDelete { draft.conditions.remove(atOffsets: $0) }
            HStack {
                TextField("新增病史（例：高血壓）", text: $newCondition)
                Button {
                    let t = newCondition.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    draft.conditions.append(t)
                    newCondition = ""
                } label: { Image(systemName: "plus.circle.fill").foregroundStyle(Color.indigo) }
                .disabled(newCondition.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            healthSectionHeader("慢性病 / 病史", icon: "list.bullet.clipboard.fill", color: .indigo, count: draft.conditions.count)
        }
    }

    // MARK: - 過敏

    private var allergySection: some View {
        Section {
            if draft.allergies.isEmpty {
                emptyRow(icon: "allergens", text: "尚無過敏紀錄")
            }
            ForEach(draft.allergies) { a in
                Button { editingAllergy = a } label: {
                    HStack(spacing: 12) {
                        rowIcon("allergens", color: .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(a.name.isEmpty ? "未命名過敏原" : a.name).foregroundStyle(.primary)
                                if let s = a.severity {
                                    Text(s.rawValue).font(.caption2)
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.12)).clipShape(Capsule())
                                        .overlay(Capsule().stroke(Color.orange.opacity(0.22), lineWidth: 0.6))
                                }
                            }
                            if !a.reaction.isEmpty {
                                Text(a.reaction).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
            .onDelete { draft.allergies.remove(atOffsets: $0) }
            Button { editingAllergy = HealthAllergy() } label: {
                Label("新增過敏原", systemImage: "plus.circle.fill")
            }
        } header: {
            healthSectionHeader("過敏", icon: "allergens", color: .orange, count: draft.allergies.count)
        }
    }

    // MARK: - 用藥

    private var medicationSection: some View {
        Section {
            if draft.medications.isEmpty {
                emptyRow(icon: "pills.fill", text: "尚無用藥紀錄")
            }
            ForEach(draft.medications) { m in
                Button { editingMedication = m } label: {
                    HStack(spacing: 12) {
                        rowIcon("pills.fill", color: .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.name.isEmpty ? "未命名藥物" : m.name).foregroundStyle(.primary)
                            if !m.dosage.isEmpty {
                                Text(m.dosage).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(m.isActive ? "服用中" : "已停用")
                            .font(.caption2)
                            .foregroundStyle(m.isActive ? .green : .secondary)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background((m.isActive ? Color.green : Color.gray).opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke((m.isActive ? Color.green : Color.gray).opacity(0.22), lineWidth: 0.6))
                    }
                    .contentShape(Rectangle())
                }
            }
            .onDelete { draft.medications.remove(atOffsets: $0) }
            Button { editingMedication = HealthMedication() } label: {
                Label("新增藥物", systemImage: "plus.circle.fill")
            }
        } header: {
            healthSectionHeader("用藥", icon: "pills.fill", color: .blue, count: draft.medications.count)
        }
    }

    // MARK: - 量測（體重 / 血壓 / 心率）

    private var measurementSection: some View {
        Section {
            if draft.measurements.isEmpty {
                emptyRow(icon: "waveform.path.ecg", text: "尚無量測紀錄")
            }
            ForEach(draft.measurements.sorted { $0.date > $1.date }) { m in
                let chips = measurementChips(m)
                Button { editingMeasurement = m } label: {
                    HStack {
                        Label {
                            Text(Self.dateFmt.string(from: m.date)).foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "calendar")
                                .font(.caption2)
                                .foregroundStyle(.pink)
                        }
                        Spacer()
                        if chips.isEmpty {
                            Text("—").font(.caption).foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 4) {
                                ForEach(chips, id: \.self) { chip in
                                    Text(chip)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.pink)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.pink.opacity(0.10))
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(Color.pink.opacity(0.20), lineWidth: 0.6))
                                }
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
            .onDelete { deleteMeasurements($0) }
            Button { editingMeasurement = HealthMeasurement() } label: {
                Label("新增量測", systemImage: "plus.circle.fill")
            }
        } header: {
            healthSectionHeader("量測（體重 / 血壓 / 心率）", icon: "waveform.path.ecg", color: .pink, count: draft.measurements.count)
        }
    }

    // MARK: - 健檢

    private var checkupSection: some View {
        Section {
            if draft.checkups.isEmpty {
                emptyRow(icon: "stethoscope", text: "尚無健檢紀錄")
            }
            ForEach(draft.checkups.sorted { $0.date > $1.date }) { c in
                Button { editingCheckup = c } label: {
                    HStack(spacing: 12) {
                        rowIcon("stethoscope", color: .purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.title.isEmpty ? "健檢" : c.title).foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                Text(Self.dateFmt.string(from: c.date))
                                if !c.place.isEmpty { Text("· \(c.place)") }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
            .onDelete { deleteCheckups($0) }
            Button { editingCheckup = HealthCheckup() } label: {
                Label("新增健檢", systemImage: "plus.circle.fill")
            }
        } header: {
            healthSectionHeader("健檢紀錄", icon: "stethoscope", color: .purple, count: draft.checkups.count)
        }
    }

    private var noteSection: some View {
        Section {
            TextField("其他健康備註", text: $draft.note, axis: .vertical).lineLimit(2...5)
        } header: {
            healthSectionHeader("備註", icon: "text.bubble.fill", color: .secondary)
        }
    }

    // MARK: - Helpers

    /// 病史列：補上與過敏／用藥／健檢一致的圖示圓，修正先前純文字列與其他小節不一致的問題
    private func conditionRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            rowIcon("list.bullet.clipboard.fill", color: .indigo)
            Text(text).foregroundStyle(.primary)
        }
    }

    /// 依主題色繪製 36pt 漸層圓形圖示，對齊 AddVehicleView 列行圖示規格
    @ViewBuilder
    private func rowIcon(_ systemName: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [color.opacity(0.22), color.opacity(0.09)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 36, height: 36)
                .shadow(color: color.opacity(0.18), radius: 5, x: 0, y: 2)
            Circle()
                .stroke(color.opacity(0.18), lineWidth: 1)
                .frame(width: 36, height: 36)
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    /// 輕量空狀態列：圖示 + 說明文字，對齊 SubordinateRosterView / LifeRealEstateView 空狀態列規格
    private func emptyRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// Section header：4pt 漸層 Capsule 色條 + 圖示 + 標題 + 計數膠囊，對齊
    /// AddVehicleView.vehicleSectionHeader 全 App Form 編輯頁設計語言
    @ViewBuilder
    private func healthSectionHeader(_ title: String, icon: String, color: Color, count: Int? = nil) -> some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.70)], startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 18)
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if let n = count, n > 0 {
                Text("\(n)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(color.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.6))
            }
        }
    }

    private func measurementChips(_ m: HealthMeasurement) -> [String] {
        var parts: [String] = []
        if let w = m.weightKg { parts.append(String(format: "%.1fkg", w)) }
        if let s = m.systolic, let d = m.diastolic { parts.append("\(s)/\(d)") }
        if let h = m.heartRate { parts.append("\(h)bpm") }
        return parts
    }

    /// 依 id 取代或新增
    private func upsert<T: Identifiable>(_ item: T, into arr: inout [T]) {
        if let i = arr.firstIndex(where: { $0.id == item.id }) { arr[i] = item }
        else { arr.append(item) }
    }

    private func deleteMeasurements(_ offsets: IndexSet) {
        let sorted = draft.measurements.sorted { $0.date > $1.date }
        let ids = offsets.map { sorted[$0].id }
        draft.measurements.removeAll { ids.contains($0.id) }
    }
    private func deleteCheckups(_ offsets: IndexSet) {
        let sorted = draft.checkups.sorted { $0.date > $1.date }
        let ids = offsets.map { sorted[$0].id }
        draft.checkups.removeAll { ids.contains($0.id) }
    }

    static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()
}

/// 子編輯 sheet 共用 Section header：4pt 漸層 Capsule 色條 + 圖示 + 標題，
/// 與 HealthProfileEditView.healthSectionHeader 同款式（省略計數膠囊）
@ViewBuilder
private func healthEditorSectionHeader(_ title: String, icon: String, color: Color) -> some View {
    HStack(spacing: 7) {
        Capsule()
            .fill(LinearGradient(colors: [color, color.opacity(0.70)], startPoint: .top, endPoint: .bottom))
            .frame(width: 4, height: 18)
        Image(systemName: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }
}

// MARK: - 過敏編輯

private struct AllergyEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HealthAllergy
    let onSave: (HealthAllergy) -> Void
    private let accent = Color.orange

    init(allergy: HealthAllergy, onSave: @escaping (HealthAllergy) -> Void) {
        _draft = State(initialValue: allergy); self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("過敏原（藥物 / 食物 / 環境）", text: $draft.name)
                    TextField("過敏反應", text: $draft.reaction)
                } header: {
                    healthEditorSectionHeader("過敏原資訊", icon: "allergens", color: accent)
                }
                Section {
                    Picker("嚴重度", selection: Binding(
                        get: { draft.severity ?? .mild },
                        set: { draft.severity = $0 })) {
                        ForEach(AllergySeverity.allCases) { s in Text(s.rawValue).tag(s) }
                    }
                } header: {
                    healthEditorSectionHeader("嚴重度", icon: "exclamationmark.triangle.fill", color: accent)
                }
            }
            .navigationTitle("過敏原")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Picker 的 get 用 ?? .mild 顯示預設值，但使用者若沒手動點過 Picker，
                // set 永遠不會被呼叫，draft.severity 會存成 nil，讓「畫面顯示輕度」
                // 與「實際存檔為未設定」互相矛盾（列表卡片因此不顯示嚴重度徽章）。
                // 開啟編輯畫面當下就把顯示的預設值寫回 draft，讓兩者一致。
                if draft.severity == nil { draft.severity = .mild }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { onSave(draft); dismiss() }.bold()
                }
            }
        }
    }
}

// MARK: - 用藥編輯

private struct MedicationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HealthMedication
    let onSave: (HealthMedication) -> Void
    private let accent = Color.blue

    init(medication: HealthMedication, onSave: @escaping (HealthMedication) -> Void) {
        _draft = State(initialValue: medication); self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("藥名", text: $draft.name)
                    TextField("劑量 / 頻率（例：500mg 每日兩次）", text: $draft.dosage)
                    Toggle("服用中", isOn: $draft.isActive)
                } header: {
                    healthEditorSectionHeader("藥物資訊", icon: "pills.fill", color: accent)
                }
                Section {
                    TextField("備註", text: $draft.note, axis: .vertical).lineLimit(1...4)
                } header: {
                    healthEditorSectionHeader("備註", icon: "text.bubble.fill", color: .secondary)
                }
            }
            .navigationTitle("藥物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { onSave(draft); dismiss() }.bold()
                }
            }
        }
    }
}

// MARK: - 量測編輯

private struct MeasurementEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var weight: Double
    @State private var systolic: Int
    @State private var diastolic: Int
    @State private var heartRate: Int
    @State private var note: String
    private let id: UUID
    let onSave: (HealthMeasurement) -> Void
    private let accent = Color.pink

    init(measurement: HealthMeasurement, onSave: @escaping (HealthMeasurement) -> Void) {
        id = measurement.id
        _date = State(initialValue: measurement.date)
        _weight = State(initialValue: measurement.weightKg ?? 0)
        _systolic = State(initialValue: measurement.systolic ?? 0)
        _diastolic = State(initialValue: measurement.diastolic ?? 0)
        _heartRate = State(initialValue: measurement.heartRate ?? 0)
        _note = State(initialValue: measurement.note)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                } header: {
                    healthEditorSectionHeader("日期", icon: "calendar", color: accent)
                }
                Section {
                    numberRow("體重", value: $weight, unit: "kg")
                    intRow("心率", value: $heartRate, unit: "bpm")
                } header: {
                    healthEditorSectionHeader("體重 / 心率", icon: "waveform.path.ecg", color: accent)
                }
                Section {
                    intRow("收縮壓", value: $systolic, unit: "mmHg")
                    intRow("舒張壓", value: $diastolic, unit: "mmHg")
                } header: {
                    healthEditorSectionHeader("血壓", icon: "heart.text.square.fill", color: accent)
                }
                Section {
                    TextField("備註", text: $note, axis: .vertical).lineLimit(1...4)
                } header: {
                    healthEditorSectionHeader("備註", icon: "text.bubble.fill", color: .secondary)
                }
            }
            .navigationTitle("量測")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        let m = HealthMeasurement(
                            id: id, date: date,
                            weightKg: weight > 0 ? weight : nil,
                            systolic: systolic > 0 ? systolic : nil,
                            diastolic: diastolic > 0 ? diastolic : nil,
                            heartRate: heartRate > 0 ? heartRate : nil,
                            note: note)
                        onSave(m); dismiss()
                    }.bold()
                }
            }
        }
    }

    private func numberRow(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label); Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }
    private func intRow(_ label: String, value: Binding<Int>, unit: String) -> some View {
        HStack {
            Text(label); Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 健檢編輯

private struct CheckupEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HealthCheckup
    @State private var hasNextDue: Bool
    @State private var nextDue: Date
    let onSave: (HealthCheckup) -> Void
    private let accent = Color.purple

    init(checkup: HealthCheckup, onSave: @escaping (HealthCheckup) -> Void) {
        _draft = State(initialValue: checkup)
        _hasNextDue = State(initialValue: checkup.nextDueDate != nil)
        _nextDue = State(initialValue: checkup.nextDueDate ?? Date())
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("項目（例：年度健檢、抽血）", text: $draft.title)
                    DatePicker("日期", selection: $draft.date, displayedComponents: .date)
                    TextField("院所", text: $draft.place)
                } header: {
                    healthEditorSectionHeader("健檢資訊", icon: "stethoscope", color: accent)
                }
                Section {
                    TextField("結果摘要", text: $draft.result, axis: .vertical).lineLimit(1...4)
                } header: {
                    healthEditorSectionHeader("結果", icon: "doc.text.fill", color: accent)
                }
                Section {
                    Toggle("設定下次回診 / 追蹤日", isOn: $hasNextDue)
                    if hasNextDue {
                        DatePicker("下次日期", selection: $nextDue, displayedComponents: .date)
                    }
                } header: {
                    healthEditorSectionHeader("追蹤提醒", icon: "bell.badge.fill", color: accent)
                }
                Section {
                    TextField("備註", text: $draft.note, axis: .vertical).lineLimit(1...4)
                } header: {
                    healthEditorSectionHeader("備註", icon: "text.bubble.fill", color: .secondary)
                }
            }
            .navigationTitle("健檢")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        draft.nextDueDate = hasNextDue ? nextDue : nil
                        onSave(draft); dismiss()
                    }.bold()
                }
            }
        }
    }
}
