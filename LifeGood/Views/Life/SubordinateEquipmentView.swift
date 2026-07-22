import SwiftUI

// MARK: - 部屬「執掌」分頁：設備清單 + PM／警報時間軸
//
// 讓使用者記錄部屬管理的設備、每台設備的預防保養（PM）時間與警報事件，
// 頁面下方以單一時間軸並列 PM（綠）與警報（紅），一眼看出兩者的相關性；
// 警報條目並標示「距該設備上次 PM N 天」輔助判讀。

// MARK: 設備清單章節

struct SubordinateEquipmentSection: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    let subordinateId: UUID

    @State private var addingEquipment = false
    @State private var editingEquipment: ManagedEquipment?
    @State private var showPremiumAlert = false

    private let accent = Color.teal

    private var subordinate: Subordinate {
        lifeStore.subordinates.first { $0.id == subordinateId } ?? Subordinate(name: "")
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 段落標題（對齊本頁其他章節規格：漸層側條 + 圖示 + 標題 + 計數 + 新增鈕）
            HStack(spacing: 10) {
                Capsule()
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 18)
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(accent)
                Text("執掌設備").font(.subheadline.weight(.semibold))
                if !subordinate.equipments.isEmpty {
                    Text("\(subordinate.equipments.count) 台")
                        .font(.caption2.weight(.semibold)).foregroundStyle(accent)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(accent.opacity(0.12)).clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
                }
                Spacer()
                Button {
                    if subscription.isPremium { addingEquipment = true }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)

            if subordinate.equipments.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 26)).foregroundStyle(accent.opacity(0.4))
                        Text("尚未新增設備").font(.caption).foregroundStyle(.secondary)
                        Text("記錄部屬管理的設備、PM 保養與警報").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 18)
            } else {
                ForEach(Array(subordinate.equipments.enumerated()), id: \.element.id) { idx, eq in
                    equipmentRow(eq)
                    if idx < subordinate.equipments.count - 1 {
                        Rectangle().fill(Color(.separator).opacity(0.20))
                            .frame(height: 0.5).padding(.leading, 56)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.08), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
        .premiumLockAlert(isPresented: $showPremiumAlert)
        .sheet(isPresented: $addingEquipment) {
            EquipmentEditorSheet(subordinateId: subordinateId, editing: nil)
        }
        .sheet(item: $editingEquipment) { eq in
            EquipmentEditorSheet(subordinateId: subordinateId, editing: eq)
        }
    }

    @ViewBuilder
    private func equipmentRow(_ eq: ManagedEquipment) -> some View {
        let lastPM = eq.pmRecords.map(\.date).max()
        let recentAlarms = eq.alarms.filter {
            $0.date > (Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date())
        }.count
        Button {
            if subscription.isPremium { editingEquipment = eq }
            else { showPremiumAlert = true }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.09)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                    Circle().stroke(accent.opacity(0.22), lineWidth: 1).frame(width: 36, height: 36)
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(eq.name.isEmpty ? "未命名設備" : eq.name)
                        .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Label("PM \(eq.pmRecords.count)", systemImage: "wrench.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green)
                        Label("警報 \(eq.alarms.count)", systemImage: "bell.badge.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(eq.alarms.isEmpty ? Color.secondary : Color.red)
                        if recentAlarms > 0 {
                            Text("30天內 \(recentAlarms) 次")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1.5)
                                .background(Color.red.opacity(0.12)).foregroundStyle(.red)
                                .clipShape(Capsule())
                        }
                    }
                    if !eq.note.isEmpty {
                        Text(eq.note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    if let last = lastPM {
                        Text("上次 PM").font(.system(size: 9)).foregroundStyle(.tertiary)
                        Text(Self.dateFmt.string(from: last)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PM／警報時間軸章節

struct SubordinateEquipmentTimelineSection: View {
    @EnvironmentObject var lifeStore: LifeStore
    let subordinateId: UUID

    private var subordinate: Subordinate {
        lifeStore.subordinates.first { $0.id == subordinateId } ?? Subordinate(name: "")
    }

    private enum EntryKind { case pm, alarm }
    private struct TimelineEntry: Identifiable {
        let id: UUID
        let kind: EntryKind
        let date: Date
        let equipmentName: String
        let text: String
        /// 警報：距同設備上一次 PM 的天數（無 PM 紀錄則 nil）
        let daysSincePM: Int?
    }

    private var entries: [TimelineEntry] {
        var result: [TimelineEntry] = []
        for eq in subordinate.equipments {
            let name = eq.name.isEmpty ? "未命名設備" : eq.name
            let pmDates = eq.pmRecords.map(\.date).sorted()
            for pm in eq.pmRecords {
                result.append(TimelineEntry(id: pm.id, kind: .pm, date: pm.date,
                                            equipmentName: name, text: pm.note, daysSincePM: nil))
            }
            for al in eq.alarms {
                // 該設備在警報發生前最近的一次 PM
                let prior = pmDates.last(where: { $0 <= al.date })
                let days = prior.flatMap {
                    Calendar.current.dateComponents([.day], from: $0, to: al.date).day
                }
                result.append(TimelineEntry(id: al.id, kind: .alarm, date: al.date,
                                            equipmentName: name, text: al.content, daysSincePM: days))
            }
        }
        return result.sorted { $0.date > $1.date }
    }

    private static let dateTimeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d HH:mm"; return f
    }()
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d"; return f
    }()
    private func fmt(_ e: TimelineEntry) -> String {
        e.kind == .alarm ? Self.dateTimeFmt.string(from: e.date) : Self.dateFmt.string(from: e.date)
    }

    var body: some View {
        let all = entries
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Capsule()
                        .fill(LinearGradient(colors: [.indigo, Color.indigo.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 4, height: 18)
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.indigo)
                    Text("PM／警報時間軸").font(.subheadline.weight(.semibold))
                    Spacer()
                    // 圖例
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Circle().fill(Color.green).frame(width: 7, height: 7)
                            Text("PM").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 3) {
                            Circle().fill(Color.red).frame(width: 7, height: 7)
                            Text("警報").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

                ForEach(Array(all.enumerated()), id: \.element.id) { idx, e in
                    timelineRow(e, isLast: idx == all.count - 1)
                }
                .padding(.bottom, 6)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.indigo.opacity(0.08), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func timelineRow(_ e: TimelineEntry, isLast: Bool) -> some View {
        let color: Color = e.kind == .pm ? .green : .red
        HStack(alignment: .top, spacing: 12) {
            // 左側：節點 + 連接線
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 22, height: 22)
                    Image(systemName: e.kind == .pm ? "wrench.fill" : "bell.fill")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(color)
                }
                if !isLast {
                    Rectangle().fill(Color(.separator).opacity(0.35))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(e.equipmentName)
                        .font(.caption.weight(.semibold)).foregroundStyle(.primary)
                    Text(e.kind == .pm ? "PM 保養" : "警報")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(color.opacity(0.12)).foregroundStyle(color)
                        .clipShape(Capsule())
                    if e.kind == .alarm, let days = e.daysSincePM {
                        Text("PM 後 \(days) 天")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Color.orange.opacity(0.12)).foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text(fmt(e)).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                if !e.text.isEmpty {
                    Text(e.text).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(.bottom, isLast ? 4 : 12)
        }
        .padding(.horizontal, 14)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 設備編輯 Sheet

struct EquipmentEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let subordinateId: UUID
    var editing: ManagedEquipment?

    @State private var name = ""
    @State private var note = ""
    @State private var pmRecords: [EquipmentPMRecord] = []
    @State private var alarms: [EquipmentAlarm] = []

    /// 統一 Section 標題（對齊 MeetingEditorSheet.editorSectionHeader 規格）
    private func editorSectionHeader(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [tint, tint.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            Text(title).font(.subheadline.weight(.bold))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("設備名稱（如：CVD-01）", text: $name)
                    TextField("備註（位置、型號等，選填）", text: $note)
                } header: {
                    editorSectionHeader("設備資訊", icon: "gearshape.2.fill", tint: .teal)
                }

                Section {
                    if pmRecords.isEmpty {
                        HStack {
                            Spacer()
                            Text("尚未新增 PM 記錄").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    ForEach($pmRecords) { $pm in
                        VStack(spacing: 6) {
                            if pmRecords.first?.id != pm.id { Divider() }
                            HStack {
                                DatePicker("保養日期", selection: $pm.date, displayedComponents: .date)
                                Button(role: .destructive) {
                                    pmRecords.removeAll { $0.id == pm.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            TextField("保養內容（選填）", text: $pm.note)
                        }
                    }
                    Button {
                        pmRecords.append(EquipmentPMRecord())
                    } label: {
                        Label("新增 PM 記錄", systemImage: "plus.circle").foregroundStyle(.green)
                    }
                } header: {
                    editorSectionHeader("預防保養（PM）", icon: "wrench.fill", tint: .green)
                }

                Section {
                    if alarms.isEmpty {
                        HStack {
                            Spacer()
                            Text("尚未新增警報").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    ForEach($alarms) { $al in
                        VStack(spacing: 6) {
                            if alarms.first?.id != al.id { Divider() }
                            HStack {
                                DatePicker("發生時間", selection: $al.date, displayedComponents: [.date, .hourAndMinute])
                                Button(role: .destructive) {
                                    alarms.removeAll { $0.id == al.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            TextField("警報內容（如：高溫警報、壓力異常）", text: $al.content)
                        }
                    }
                    Button {
                        alarms.append(EquipmentAlarm())
                    } label: {
                        Label("新增警報", systemImage: "plus.circle").foregroundStyle(.red)
                    }
                } header: {
                    editorSectionHeader("警報記錄", icon: "bell.badge.fill", tint: .red)
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) { deleteEquipment() } label: {
                            Label("刪除此設備", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯設備" : "新增設備")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let e = editing {
                    name = e.name; note = e.note
                    pmRecords = e.pmRecords.sorted { $0.date > $1.date }
                    alarms = e.alarms.sorted { $0.date > $1.date }
                }
            }
        }
    }

    private func save() {
        guard var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
        let eq = ManagedEquipment(
            id: editing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            note: note.trimmingCharacters(in: .whitespaces),
            pmRecords: pmRecords,
            alarms: alarms
        )
        if let idx = sub.equipments.firstIndex(where: { $0.id == eq.id }) { sub.equipments[idx] = eq }
        else { sub.equipments.append(eq) }
        lifeStore.update(sub)
        dismiss()
    }

    private func deleteEquipment() {
        guard let e = editing, var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
        sub.equipments.removeAll { $0.id == e.id }
        lifeStore.update(sub)
        dismiss()
    }
}
