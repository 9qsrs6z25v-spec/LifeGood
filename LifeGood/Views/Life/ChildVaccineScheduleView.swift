import SwiftUI

// MARK: - 兒童疫苗接種時程卡片
//
// 依台灣常規疫苗時程（VaccineSchedule.taiwan）列出所有應接種的疫苗劑次，
// 以孩子的出生日期推算每一劑的「建議接種日」。使用者只需填入實際施打日期：
// 有日期＝已完成、無日期＝尚未施打；逾期未打會自動標示「需盡快施打」。

struct ChildVaccineScheduleView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    let childId: UUID

    @State private var editingItem: VaccineScheduleItem?
    @State private var editingLegacy: ChildRecord?
    @State private var showPremiumAlert = false

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
            ForEach(VaccineSchedule.groupedByStage, id: \.stage) { group in
                stageHeader(group.stage)
                ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, item in
                    row(item)
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
    }

    // MARK: 標頭 + 進度

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(accent.opacity(0.12)).clipShape(Capsule())
                    .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
            }
            if overdueCount > 0 {
                Label("\(overdueCount) 劑逾期，需盡快施打", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)
    }

    /// 舊版以自由文字新增的疫苗紀錄（ChildRecord type == .vaccination）仍保留顯示，避免資料被隱藏。
    @ViewBuilder
    private var legacyRecordsSection: some View {
        let legacy = child.childRecords.filter { $0.type == .vaccination }.sorted { $0.date > $1.date }
        if !legacy.isEmpty {
            stageHeader("其他疫苗紀錄")
            ForEach(legacy) { rec in
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
            }
            Text("以上為舊版手動新增的紀錄，點擊可編輯或刪除")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, 14).padding(.bottom, 8)
        }
    }

    private var birthdayHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(.orange)
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
                    Label("疫苗資訊", systemImage: "syringe.fill")
                }

                Section {
                    Toggle("已完成施打", isOn: $hasDate.animation(.spring(response: 0.3, dampingFraction: 0.85)))
                    if hasDate {
                        DatePicker("施打日期", selection: $date, displayedComponents: .date)
                    } else {
                        Text("未填施打日期＝尚未施打")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Label("施打狀態", systemImage: "checkmark.seal")
                }

                Section {
                    TextField("備註（接種院所、反應、提醒等）", text: $note, axis: .vertical).lineLimit(2...5)
                } header: {
                    Label("備註", systemImage: "note.text")
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
