import SwiftUI

// MARK: - 兒童疫苗接種時程卡片
//
// 依台灣常規疫苗時程（VaccineSchedule.taiwan）列出所有應接種的疫苗劑次，
// 以孩子的出生日期推算每一劑的「建議接種日」。使用者只需填入實際施打日期：
// 有日期＝已完成、無日期＝尚未施打；逾期未打會自動標示「需盡快施打」。

// MARK: - 美化紀錄（ChildVaccineScheduleView）
// [2026-07 v1] 本次美化方向：
//   1. header → 新增整體接種進度條（Capsule 雙層：底軌 + 漸層填色 + glow overlay），
//      對齊 CareerView.subCategoryBreakdown / FinanceOverviewView.allocationSection
//      進度條規格，doneCount/total 比例變動時以 spring 動畫平滑過渡；
//      count 膠囊補上 minimumScaleFactor(0.7) + lineLimit(1) 防止大字級截斷
//   2. stageHeader → 補上每期已完成／應接種劑數膠囊（如「2/3」），對齊
//      FixedExpenseView.categoryHeader 計數膠囊規格，讓使用者不必逐列數算
//      即可掌握各接種期完成度
//   3. row 列表 + legacyRecordsSection 列 → 交錯淡入 + 向上進場動畫
//      （rowsAppeared，以單一 onAppear 觸發、onDisappear 重置，不使用
//      asyncAfter，避免重建/切頁造成動畫殘留閃爍，對齊 StockView.cardsAppeared 寫法）
//   4. row 疫苗名稱 → 補上 lineLimit(1) + minimumScaleFactor(0.85)，避免大字級
//      輔助模式下長疫苗名稱換行擠壓版面
//   5. birthdayHint → 提示圖示改為漸層圓底 + 外框，對齊全 App 空狀態／提示區塊
//      圖示錨點規格，取代原本無底色的裸圖示
// [2026-07 v2] 補齊 VaccineDoseEditorSheet（施打編輯 Sheet）：
//   6. 該 sheet 先前是裸 Form + 系統預設 Label 標頭（灰階圖示、無色條），與外層清單／
//      HealthProfileEditView 四個子編輯 sheet 已統一的「4pt 漸層 Capsule 色條 + 主題色圖示 +
//      .subheadline.semibold」標頭規格不一致，是本檔案最後一處未對齊的裸元件；新增同款式
//      vaccineEditorSectionHeader(_:icon:color:)，三個 Section 一律改用，備註沿用全 App
//      慣例採 secondary 色，其餘沿用外層藍色主題（accent）。
//   7. Toggle「已完成施打」補上 .tint(accent)，避免系統預設綠色與本頁藍色主題色衝突；
//      疫苗名稱／劑次文字補 lineLimit(2) + minimumScaleFactor(0.85)，避免長疫苗名稱在
//      大字級輔助模式下被裁切。
//   8. 純視覺調整，未變動任何接種狀態判斷、日期推算、草稿寫回或存檔邏輯。
//   （下次美化本檔案時：主列表與編輯 sheet 皆已完成規格對齊，可轉往其他仍留有待辦的畫面）

struct ChildVaccineScheduleView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    let childId: UUID

    @State private var editingItem: VaccineScheduleItem?
    @State private var editingLegacy: ChildRecord?
    @State private var showPremiumAlert = false
    @State private var headerAppeared = false
    @State private var rowsAppeared = false

    private let accent = Color.blue

    private var child: FamilyMember {
        lifeStore.familyMembers.first { $0.id == childId } ?? FamilyMember(role: .son)
    }

    private func dose(for id: String) -> VaccineDose? {
        child.vaccinations.first { $0.scheduleId == id }
    }

    private enum VStatus { case done, overdue, soon, upcoming, unknown }

    private func status(for item: VaccineScheduleItem) -> VStatus {
        if let d = dose(for: item.id), d.isDone { return .done }
        guard let rec = item.recommendedDate(birthday: child.birthday) else { return .unknown }
        if item.recurring { return .upcoming }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let recDay = cal.startOfDay(for: rec)
        if recDay < today { return .overdue }
        if let in30 = cal.date(byAdding: .day, value: 30, to: today), recDay <= in30 { return .soon }
        return .upcoming
    }

    private var doneCount: Int {
        VaccineSchedule.taiwan.filter { if let d = dose(for: $0.id) { return d.isDone } else { return false } }.count
    }
    private var overdueCount: Int {
        VaccineSchedule.taiwan.filter { status(for: $0) == .overdue }.count
    }
    private var total: Int { VaccineSchedule.taiwan.count }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d"; return f
    }()
    private func fmt(_ d: Date) -> String { Self.dateFmt.string(from: d) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if child.birthday == nil {
                birthdayHint
            }
            let allItems = VaccineSchedule.taiwan
            ForEach(VaccineSchedule.groupedByStage, id: \.stage) { group in
                stageHeader(group.stage, items: group.items)
                ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, item in
                    let globalIdx = (allItems.firstIndex(where: { $0.id == item.id }) ?? idx)
                    row(item)
                        .opacity(rowsAppeared ? 1 : 0)
                        .offset(y: rowsAppeared ? 0 : 10)
                        .animation(
                            .spring(response: 0.42, dampingFraction: 0.84)
                                .delay(min(0.02 * Double(globalIdx), 0.4)),
                            value: rowsAppeared
                        )
                    if idx < group.items.count - 1 {
                        Rectangle().fill(Color(.separator).opacity(0.18))
                            .frame(height: 0.5).padding(.leading, 56)
                    }
                }
            }
            .padding(.bottom, 4)

            legacyRecordsSection
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.08), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
        .premiumLockAlert(isPresented: $showPremiumAlert)
        .sheet(item: $editingItem) { item in
            VaccineDoseEditorSheet(childId: childId, item: item)
        }
        .sheet(item: $editingLegacy) { rec in
            ChildRecordEditorSheet(childId: childId, type: .vaccination, editing: rec)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { headerAppeared = true }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) { rowsAppeared = true }
        }
        .onDisappear {
            headerAppeared = false
            rowsAppeared = false
        }
    }

    // MARK: 標頭 + 進度

    private var completionRatio: Double {
        total > 0 ? Double(doneCount) / Double(total) : 0
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 18)
                Image(systemName: "syringe.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(accent)
                Text("疫苗接種時程")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(doneCount)/\(total)")
                    .font(.caption2.weight(.bold)).foregroundStyle(accent)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(accent.opacity(0.12)).clipShape(Capsule())
                    .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
            }

            // 整體接種進度條：底軌 + 漸層填色 + glow overlay，對齊
            // CareerView.subCategoryBreakdown mini 進度條規格
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemFill)).frame(height: 5)
                    Capsule()
                        .fill(LinearGradient(colors: [accent, accent.opacity(0.6)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * (headerAppeared ? completionRatio : 0), height: 5)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: headerAppeared)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: completionRatio)
                    Capsule()
                        .fill(LinearGradient(colors: [.white.opacity(0.28), .clear, .black.opacity(0.06)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: geo.size.width * (headerAppeared ? completionRatio : 0), height: 5)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: headerAppeared)
                }
            }
            .frame(height: 5)

            if overdueCount > 0 {
                Label("\(overdueCount) 劑逾期，需盡快施打", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)
        .opacity(headerAppeared ? 1 : 0)
        .offset(y: headerAppeared ? 0 : 8)
    }

    /// 舊版以自由文字新增的疫苗紀錄（ChildRecord type == .vaccination）仍保留顯示，避免資料被隱藏。
    @ViewBuilder
    private var legacyRecordsSection: some View {
        let legacy = child.childRecords.filter { $0.type == .vaccination }.sorted { $0.date > $1.date }
        if !legacy.isEmpty {
            stageHeader("其他疫苗紀錄")
            ForEach(Array(legacy.enumerated()), id: \.element.id) { idx, rec in
                Button {
                    if subscription.isPremium { editingLegacy = rec }
                    else { showPremiumAlert = true }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "syringe")
                            .font(.system(size: 13)).foregroundStyle(accent.opacity(0.7))
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(rec.title.isEmpty ? "疫苗" : rec.title).font(.subheadline).foregroundStyle(.primary)
                                    .lineLimit(1).minimumScaleFactor(0.85)
                                if let dose = rec.dose, !dose.isEmpty {
                                    Text(dose).font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                                        .background(accent.opacity(0.10)).foregroundStyle(accent.opacity(0.9))
                                        .clipShape(Capsule())
                                }
                            }
                            if !rec.note.isEmpty {
                                Text(rec.note).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 4)
                        Text(fmt(rec.date)).font(.caption2).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(rowsAppeared ? 1 : 0)
                .offset(y: rowsAppeared ? 0 : 10)
                .animation(
                    .spring(response: 0.42, dampingFraction: 0.84).delay(min(0.02 * Double(idx), 0.3)),
                    value: rowsAppeared
                )
            }
            Text("以上為舊版手動新增的紀錄，點擊可編輯或刪除")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, 14).padding(.bottom, 8)
        }
    }

    private var birthdayHint: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.orange.opacity(0.22), .orange.opacity(0.09)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                Circle().stroke(Color.orange.opacity(0.22), lineWidth: 1).frame(width: 26, height: 26)
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
            }
            Text("設定孩子的生日後，可自動推算每一劑的建議接種日")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func stageHeader(_ stage: String) -> some View {
        Text(stage)
            .font(.caption.weight(.bold)).foregroundStyle(accent.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
    }

    /// 疫苗接種期分組標頭，附上該期已完成／應接種劑數膠囊（對齊 FixedExpenseView.categoryHeader 計數膠囊規格）。
    private func stageHeader(_ stage: String, items: [VaccineScheduleItem]) -> some View {
        let doneInStage = items.filter { dose(for: $0.id)?.isDone == true }.count
        return HStack(spacing: 6) {
            Text(stage)
                .font(.caption.weight(.bold)).foregroundStyle(accent.opacity(0.85))
            Spacer(minLength: 4)
            Text("\(doneInStage)/\(items.count)")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(accent.opacity(0.75))
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 6).padding(.vertical, 1.5)
                .background(accent.opacity(0.10)).clipShape(Capsule())
                .overlay(Capsule().stroke(accent.opacity(0.18), lineWidth: 0.5))
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
    }

    // MARK: 單列

    @ViewBuilder
    private func row(_ item: VaccineScheduleItem) -> some View {
        let st = status(for: item)
        let d = dose(for: item.id)
        Button {
            if subscription.isPremium { editingItem = item }
            else { showPremiumAlert = true }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                statusIcon(st)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                            .lineLimit(1).minimumScaleFactor(0.85)
                        Text(item.dose)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background(accent.opacity(0.10)).foregroundStyle(accent.opacity(0.9))
                            .clipShape(Capsule())
                        if item.optional {
                            Text("自費").font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1.5)
                                .background(Color.orange.opacity(0.12)).foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    subline(item: item, status: st, dose: d)
                    if let note = d?.note, !note.isEmpty {
                        Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                trailing(item: item, status: st, dose: d)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusIcon(_ st: VStatus) -> some View {
        let (icon, color): (String, Color) = {
            switch st {
            case .done: return ("checkmark.circle.fill", .green)
            case .overdue: return ("exclamationmark.circle.fill", .red)
            case .soon: return ("clock.fill", .orange)
            case .upcoming: return ("circle", accent.opacity(0.5))
            case .unknown: return ("circle.dashed", .gray)
            }
        }()
        return ZStack {
            Circle()
                .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.09)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 36, height: 36)
            Circle().stroke(color.opacity(0.22), lineWidth: 1).frame(width: 36, height: 36)
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
        }
    }

    @ViewBuilder
    private func subline(item: VaccineScheduleItem, status st: VStatus, dose d: VaccineDose?) -> some View {
        HStack(spacing: 6) {
            Text(item.ageLabel).font(.caption2).foregroundStyle(.secondary)
            if let rec = item.recommendedDate(birthday: child.birthday), st != .done {
                Text("建議 \(fmt(rec))").font(.caption2).foregroundStyle(.secondary.opacity(0.8))
            }
            switch st {
            case .overdue:
                Text("需盡快施打").font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                    .background(Color.red.opacity(0.14)).foregroundStyle(.red).clipShape(Capsule())
            case .soon:
                Text("即將接種").font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                    .background(Color.orange.opacity(0.14)).foregroundStyle(.orange).clipShape(Capsule())
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func trailing(item: VaccineScheduleItem, status st: VStatus, dose d: VaccineDose?) -> some View {
        if st == .done, let date = d?.administeredDate {
            VStack(alignment: .trailing, spacing: 2) {
                Text("已施打").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)
                Text(fmt(date)).font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - 疫苗施打編輯 Sheet

struct VaccineDoseEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let childId: UUID
    let item: VaccineScheduleItem

    @State private var hasDate = false
    @State private var date = Date()
    @State private var note = ""

    // [v2] 沿用外層 ChildVaccineScheduleView 的藍色主題色，讓 Sheet 與觸發它的清單視覺一致
    private let accent = Color.blue

    private var child: FamilyMember? { lifeStore.familyMembers.first { $0.id == childId } }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d"; return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("疫苗").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(item.name)．\(item.dose)").fontWeight(.medium)
                            .lineLimit(2).minimumScaleFactor(0.85).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("建議接種").foregroundStyle(.secondary)
                        Spacer()
                        if let rec = item.recommendedDate(birthday: child?.birthday) {
                            Text("\(item.ageLabel)（\(Self.dateFmt.string(from: rec))）")
                        } else {
                            Text(item.ageLabel)
                        }
                    }
                    if !item.note.isEmpty {
                        Text(item.note).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    vaccineEditorSectionHeader("疫苗資訊", icon: "syringe.fill", color: accent)
                }

                Section {
                    Toggle("已完成施打", isOn: $hasDate.animation(.spring(response: 0.3, dampingFraction: 0.85)))
                        .tint(accent)
                    if hasDate {
                        DatePicker("施打日期", selection: $date, displayedComponents: .date)
                    } else {
                        Text("未填施打日期＝尚未施打")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    vaccineEditorSectionHeader("施打狀態", icon: "checkmark.seal.fill", color: accent)
                }

                Section {
                    TextField("備註（接種院所、反應、提醒等）", text: $note, axis: .vertical).lineLimit(2...5)
                } header: {
                    vaccineEditorSectionHeader("備註", icon: "note.text", color: .secondary)
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }.bold().foregroundStyle(.green)
                }
            }
            .onAppear {
                if let d = child?.vaccinations.first(where: { $0.scheduleId == item.id }) {
                    if let ad = d.administeredDate { hasDate = true; date = ad }
                    note = d.note
                } else if let rec = item.recommendedDate(birthday: child?.birthday) {
                    date = rec   // 預設帶入建議接種日，方便直接確認
                }
            }
        }
    }

    private func save() {
        guard var member = child else { dismiss(); return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let administered: Date? = hasDate ? date : nil
        // 既無施打日期又無備註 → 視為未互動，移除該筆狀態避免累積空資料
        if administered == nil && trimmedNote.isEmpty {
            member.vaccinations.removeAll { $0.scheduleId == item.id }
        } else if let idx = member.vaccinations.firstIndex(where: { $0.scheduleId == item.id }) {
            member.vaccinations[idx].administeredDate = administered
            member.vaccinations[idx].note = trimmedNote
        } else {
            member.vaccinations.append(
                VaccineDose(scheduleId: item.id, administeredDate: administered, note: trimmedNote)
            )
        }
        lifeStore.update(member)
        dismiss()
    }
}

/// VaccineDoseEditorSheet 專用 Section 標頭：4pt 漸層 Capsule 色條 + 圖示 + 標題，
/// 與 HealthProfileEditView.healthEditorSectionHeader 同款式，讓裸 Form 標頭升級為
/// 與全 App 其他編輯 Sheet 一致的視覺語言（見 v2 美化紀錄）。
@ViewBuilder
private func vaccineEditorSectionHeader(_ title: String, icon: String, color: Color) -> some View {
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
