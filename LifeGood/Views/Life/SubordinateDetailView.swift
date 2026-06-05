import SwiftUI
import UIKit

struct SubordinateDetailView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let subordinateId: UUID
    @State private var showEdit = false
    @State private var addingType: SubordinateRecordType?
    @State private var editingRecord: SubordinateRecord?
    @State private var addingMeeting = false
    @State private var editingMeeting: SubordinateMeeting?
    @State private var addingTask = false
    @State private var editingTask: SubordinateTask?
    @State private var showPremiumAlert = false

    enum DetailTab: String, CaseIterable { case daily = "日常"; case rating = "評分系統" }
    @State private var detailTab: DetailTab = .daily

    init(subordinate: Subordinate) { self.subordinateId = subordinate.id }

    private var subordinate: Subordinate {
        lifeStore.subordinates.first(where: { $0.id == subordinateId }) ?? Subordinate(name: "")
    }

    private var gradeTitleText: String {
        if let gt = lifeStore.gradeTitles.first(where: { $0.id == subordinate.gradeTitleId }) {
            return "\(gt.grade) — \(gt.title)"
        }
        return subordinate.jobTitle
    }

    private var departmentText: String {
        if let dept = lifeStore.departments.first(where: { $0.id == subordinate.departmentId }) {
            return dept.code.isEmpty ? dept.name : "\(dept.code) \(dept.name)"
        }
        return subordinate.department
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard

                    Picker("", selection: $detailTab) {
                        ForEach(DetailTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if detailTab == .daily {
                        meetingSection
                        taskSection
                        recordSection(.leave)
                    } else {
                        proConSection
                        recordSection(.achievement)
                        recordSection(.improvement)
                        recordSection(.fault)
                        recordSection(.missOperation)
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("部屬卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("編輯") {
                        if subscription.isPremium { showEdit = true }
                        else { showPremiumAlert = true }
                    }.foregroundStyle(.green)
                }
            }
            .sheet(isPresented: $showEdit) { AddSubordinateView(editing: subordinate) }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .sheet(item: $addingType) { type in
                RecordEditorSheet(subordinateId: subordinateId, type: type, editing: nil)
            }
            .sheet(item: $editingRecord) { rec in
                RecordEditorSheet(subordinateId: subordinateId, type: rec.type, editing: rec)
            }
            .sheet(isPresented: $addingMeeting) {
                MeetingEditorSheet(subordinateId: subordinateId, editing: nil)
            }
            .sheet(item: $editingMeeting) { m in
                MeetingEditorSheet(subordinateId: subordinateId, editing: m)
            }
            .sheet(isPresented: $addingTask) {
                TaskEditorSheet(subordinateId: subordinateId, editing: nil)
            }
            .sheet(item: $editingTask) { t in
                TaskEditorSheet(subordinateId: subordinateId, editing: t)
            }
        }
    }

    // MARK: - 頭部

    private var headerCard: some View {
        VStack(spacing: 8) {
            Text(subordinate.name).font(.title2.bold())
            if !gradeTitleText.isEmpty {
                Text(gradeTitleText).font(.subheadline).foregroundStyle(.secondary)
            }
            if !departmentText.isEmpty {
                Text(departmentText).font(.caption).foregroundStyle(.tertiary)
            }
            if let jd = subordinate.joinDate {
                HStack(spacing: 4) {
                    Image(systemName: "calendar").font(.caption2)
                    Text("入職 \(formatDate(jd))").font(.caption).foregroundStyle(.tertiary)
                }
            }
            HStack(spacing: 10) {
                statBadge(count: countFor([.pro]), label: "優點", color: .green)
                statBadge(count: countFor([.con]), label: "缺點", color: .red)
                statBadge(count: countFor([.achievement]), label: "成就", color: .orange)
                statBadge(count: countFor([.missOperation]), label: "Miss", color: .purple)
                statBadge(count: countFor([.leave]), label: "請假", color: .teal)
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func statBadge(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.headline).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func countFor(_ types: [SubordinateRecordType]) -> Int {
        subordinate.records.filter { types.contains($0.type) }.count
    }

    // MARK: - 會議章節

    private var meetingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("會議", icon: "person.3.fill", color: .indigo) {
                Button {
                    if subscription.isPremium { addingMeeting = true }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.indigo)
                }
            }
            let items = subordinate.meetings.sorted { $0.date > $1.date }
            if items.isEmpty {
                emptyHint
            } else {
                ForEach(items) { m in
                    Button {
                        if subscription.isPremium { editingMeeting = m }
                        else { showPremiumAlert = true }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "person.3.fill").font(.caption).foregroundStyle(.indigo).frame(width: 20)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(m.topic.isEmpty ? "未命名會議" : m.topic)
                                    .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                HStack(spacing: 6) {
                                    Text(formatDateTime(m.date)).font(.caption2).foregroundStyle(.tertiary)
                                    Text("\(m.durationMinutes) 分鐘").font(.caption2)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.indigo.opacity(0.12)).foregroundStyle(.indigo)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                    if let r = m.recurrence {
                                        Text(r.rawValue).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                if !m.items.isEmpty {
                                    Text("\(m.items.count) 個項目").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal).padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 任務章節

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("任務", icon: "checklist", color: .cyan) {
                Button {
                    if subscription.isPremium { addingTask = true }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.cyan)
                }
            }
            // 未完成在前、已完成在後；各自再依日期新到舊
            let items = subordinate.tasks.sorted {
                $0.isCompleted != $1.isCompleted ? (!$0.isCompleted && $1.isCompleted) : ($0.date > $1.date)
            }
            if items.isEmpty {
                emptyHint
            } else {
                ForEach(items) { t in
                    HStack(alignment: .top, spacing: 10) {
                        // 左側可點打勾圓圈：直接切換完成，不進編輯頁
                        Button {
                            lifeStore.toggleTaskCompletion(subordinateId: subordinateId, taskId: t.id)
                        } label: {
                            Image(systemName: t.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.body)
                                .foregroundStyle(t.isCompleted ? Color.green : Color.cyan)
                                .frame(width: 24)
                        }
                        .buttonStyle(.plain)

                        Button {
                            if subscription.isPremium { editingTask = t }
                            else { showPremiumAlert = true }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(t.topic.isEmpty ? "未命名任務" : t.topic)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(t.isCompleted ? .secondary : .primary)
                                        .strikethrough(t.isCompleted, color: .secondary)
                                    HStack(spacing: 6) {
                                        Text(formatDateTime(t.date)).font(.caption2).foregroundStyle(.tertiary)
                                        if let due = t.dueDate {
                                            Text("截止 \(formatDate(due))").font(.caption2)
                                                .padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(due < Date() && !t.isCompleted ? Color.red.opacity(0.12) : Color.cyan.opacity(0.12))
                                                .foregroundStyle(due < Date() && !t.isCompleted ? .red : .cyan)
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .opacity(t.isCompleted ? 0.6 : 1)
                    .padding(.horizontal).padding(.vertical, 8)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 優缺點

    private var proConSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("優缺點", icon: "hand.thumbsup.fill", color: .green) {
                Menu {
                    Button {
                        if subscription.isPremium { addingType = .pro }
                        else { showPremiumAlert = true }
                    } label: { Label("優點", systemImage: "hand.thumbsup.fill") }
                    Button {
                        if subscription.isPremium { addingType = .con }
                        else { showPremiumAlert = true }
                    } label: { Label("缺點", systemImage: "hand.thumbsdown.fill") }
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                }
            }
            let items = subordinate.records.filter { $0.type == .pro || $0.type == .con }.sorted { $0.date > $1.date }
            if items.isEmpty { emptyHint } else { ForEach(items) { recordRow($0) } }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 通用記錄章節

    private func recordSection(_ type: SubordinateRecordType) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(type.rawValue, icon: type.icon, color: colorFor(type)) {
                Button {
                    if subscription.isPremium { addingType = type }
                    else { showPremiumAlert = true }
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(colorFor(type))
                }
            }
            let items = subordinate.records.filter { $0.type == type }.sorted { $0.date > $1.date }
            if items.isEmpty { emptyHint } else { ForEach(items) { recordRow($0) } }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func sectionHeader<Action: View>(_ title: String, icon: String, color: Color, @ViewBuilder action: () -> Action) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color)
            Text(title).font(.headline)
            Spacer()
            action()
        }
        .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)
    }

    private func recordRow(_ rec: SubordinateRecord) -> some View {
        Button {
            if subscription.isPremium { editingRecord = rec }
            else { showPremiumAlert = true }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: rec.type.icon).font(.caption).foregroundStyle(colorFor(rec.type)).frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(rec.content).font(.subheadline).foregroundStyle(.primary)
                        if rec.type == .missOperation, let sev = rec.severity {
                            Text(sev.rawValue).font(.caption2.weight(.medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(severityColor(sev).opacity(0.15))
                                .foregroundStyle(severityColor(sev))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        if rec.type == .leave {
                            if let lt = rec.leaveType {
                                Text(lt.rawValue).font(.caption2.weight(.medium))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.teal.opacity(0.15)).foregroundStyle(.teal)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            if let h = rec.leaveHours, h > 0 {
                                Text(h.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(h))h" : String(format: "%.1fh", h))
                                    .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    HStack(spacing: 6) {
                        Text(formatDate(rec.date)).font(.caption2).foregroundStyle(.tertiary)
                        if !rec.note.isEmpty {
                            Text("·").foregroundStyle(.tertiary)
                            Text(rec.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal).padding(.vertical, 8).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyHint: some View {
        Text("尚無記錄").font(.caption).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal).padding(.bottom, 12)
    }

    private func colorFor(_ type: SubordinateRecordType) -> Color {
        switch type {
        case .pro: return .green; case .con: return .red
        case .achievement: return .orange; case .improvement: return .blue
        case .fault: return .pink; case .missOperation: return .purple
        case .leave: return .teal
        }
    }

    private func severityColor(_ s: MissOpSeverity) -> Color {
        switch s { case .minor: return .yellow; case .normal: return .orange; case .severe: return .red }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d HH:mm"; return f.string(from: date)
    }
}

// MARK: - 記錄編輯 Sheet

struct RecordEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let subordinateId: UUID
    let type: SubordinateRecordType
    var editing: SubordinateRecord?

    @State private var content = ""
    @State private var date = Date()
    @State private var endDate = Date()
    @State private var note = ""
    @State private var severity: MissOpSeverity = .normal
    @State private var leaveType: LeaveType = .personal

    private var canSave: Bool {
        !content.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var computedLeaveHours: Double {
        max(0, endDate.timeIntervalSince(date) / 3600)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("內容") {
                    TextField(placeholder, text: $content, axis: .vertical).lineLimit(2...5)
                }
                if type == .leave {
                    Section("請假資訊") {
                        Picker("假別", selection: $leaveType) {
                            ForEach(LeaveType.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                    Section("日期") {
                        DatePicker("開始時間", selection: $date)
                        DatePicker("結束時間", selection: $endDate, in: date...)
                        HStack {
                            Text("請假時數").foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f 小時", computedLeaveHours))
                                .foregroundStyle(.teal).bold()
                        }
                    }
                } else {
                    Section("日期") {
                        DatePicker("發生日期", selection: $date, displayedComponents: .date)
                    }
                }
                if type == .missOperation {
                    Section("嚴重度") {
                        Picker("嚴重度", selection: $severity) {
                            ForEach(MissOpSeverity.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section("備註") {
                    TextField("選填", text: $note, axis: .vertical).lineLimit(2...5)
                }
                if editing != nil {
                    Section {
                        Button(role: .destructive) { deleteRecord() } label: { Label("刪除此記錄", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯\(type.rawValue)" : "新增\(type.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }.bold().foregroundStyle(.green).disabled(!canSave)
                }
            }
            .onAppear { loadEditing() }
        }
    }

    private var placeholder: String {
        switch type {
        case .pro: return "描述優點（如：溝通能力強）"
        case .con: return "描述缺點（如：會議發言較少）"
        case .achievement: return "描述成就（如：完成 Q3 專案）"
        case .improvement: return "描述改善（如：文件撰寫變得清晰）"
        case .fault: return "描述缺失（如：忘記交付報告）"
        case .missOperation: return "描述事件（如：誤刪正式資料）"
        case .leave: return "請假事由（如：身體不適）"
        }
    }

    private func loadEditing() {
        guard let e = editing else { return }
        content = e.content; date = e.date; note = e.note
        endDate = e.endDate ?? Calendar.current.date(byAdding: .hour, value: 8, to: e.date) ?? e.date
        severity = e.severity ?? .normal
        leaveType = e.leaveType ?? .personal
    }

    private func save() {
        guard var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
        let rec = SubordinateRecord(
            id: editing?.id ?? UUID(), type: type,
            content: content.trimmingCharacters(in: .whitespaces),
            date: date, endDate: type == .leave ? endDate : nil,
            note: note.trimmingCharacters(in: .whitespaces),
            severity: type == .missOperation ? severity : nil,
            leaveType: type == .leave ? leaveType : nil,
            leaveHours: type == .leave ? computedLeaveHours : nil
        )
        if let idx = sub.records.firstIndex(where: { $0.id == rec.id }) { sub.records[idx] = rec }
        else { sub.records.append(rec) }
        lifeStore.update(sub); dismiss()
    }

    private func deleteRecord() {
        guard let e = editing, var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
        sub.records.removeAll { $0.id == e.id }
        lifeStore.update(sub); dismiss()
    }
}

// MARK: - 會議編輯 Sheet

struct MeetingEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let subordinateId: UUID
    var editing: SubordinateMeeting?

    @State private var topic = ""
    @State private var date = Date()
    @State private var durationText = "60"
    @State private var recurrence: MeetingRecurrence?
    @State private var hasRecurrence = false
    @State private var items: [MeetingItem] = []
    @State private var note = ""

    private var allSubordinates: [Subordinate] { lifeStore.subordinates }

    var body: some View {
        NavigationStack {
            Form {
                Section("會議資訊") {
                    TextField("會議主題", text: $topic)
                    HStack {
                        Text("日期時間")
                        Spacer()
                        FiveMinuteDateTimePicker(selection: $date).fixedSize()
                    }
                    HStack {
                        TextField("會議長度", text: $durationText).keyboardType(.numberPad)
                        Text("分鐘").foregroundStyle(.secondary)
                    }
                    Toggle("設定週期", isOn: $hasRecurrence)
                    if hasRecurrence {
                        Picker("週期", selection: $recurrence) {
                            Text("不重複").tag(nil as MeetingRecurrence?)
                            ForEach(MeetingRecurrence.allCases) { Text($0.rawValue).tag($0 as MeetingRecurrence?) }
                        }
                    }
                }

                Section {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, _ in
                        VStack(spacing: 8) {
                            if index > 0 { Divider() }
                            HStack {
                                TextField("項目內容", text: $items[index].content)
                                Button(role: .destructive) { items.remove(at: index) } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            Picker("負責人", selection: $items[index].assigneeId) {
                                Text("未指定").tag(nil as UUID?)
                                ForEach(allSubordinates) { s in Text(s.name).tag(s.id as UUID?) }
                            }
                            DatePicker("截止日", selection: Binding(
                                get: { items[index].dueDate ?? Date() },
                                set: { items[index].dueDate = $0 }
                            ), displayedComponents: .date)
                        }
                    }
                    Button { items.append(MeetingItem()) } label: {
                        Label("新增項目", systemImage: "plus.circle").foregroundStyle(.indigo)
                    }
                } header: { Text("會議項目") }

                Section("備註") {
                    TextField("選填", text: $note, axis: .vertical).lineLimit(2...5)
                }
                if editing != nil {
                    Section {
                        Button(role: .destructive) { deleteMeeting() } label: { Label("刪除會議", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯會議" : "新增會議")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let e = editing {
                    topic = e.topic; date = e.date
                    durationText = "\(e.durationMinutes)"
                    if let r = e.recurrence { hasRecurrence = true; recurrence = r }
                    items = e.items; note = e.note
                } else {
                    // 新會議：預設時間先對齊到 5 分鐘倍數，與選擇器一致
                    date = FiveMinuteDateTimePicker.roundedToFiveMinutes(Date())
                }
            }
        }
    }

    private func save() {
        guard var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
        let meeting = SubordinateMeeting(
            id: editing?.id ?? UUID(),
            topic: topic.trimmingCharacters(in: .whitespaces),
            date: date, durationMinutes: Int(durationText) ?? 60,
            recurrence: hasRecurrence ? recurrence : nil,
            items: items, note: note.trimmingCharacters(in: .whitespaces)
        )
        if let idx = sub.meetings.firstIndex(where: { $0.id == meeting.id }) { sub.meetings[idx] = meeting }
        else { sub.meetings.append(meeting) }
        lifeStore.update(sub); dismiss()
    }

    private func deleteMeeting() {
        guard let e = editing, var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
        sub.meetings.removeAll { $0.id == e.id }
        lifeStore.update(sub); dismiss()
    }
}

// MARK: - 任務編輯 Sheet

struct TaskEditorSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let subordinateId: UUID
    var editing: SubordinateTask?

    @State private var topic = ""
    @State private var content = ""
    @State private var date = Date()
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var note = ""
    @State private var isCompleted = false

    var body: some View {
        NavigationStack {
            Form {
                Section("任務資訊") {
                    TextField("任務主題", text: $topic)
                    TextField("任務內容", text: $content, axis: .vertical).lineLimit(2...5)
                    HStack {
                        Text("任務日期")
                        Spacer()
                        FiveMinuteDateTimePicker(selection: $date).fixedSize()
                    }
                    Toggle("設定截止日", isOn: $hasDueDate)
                    if hasDueDate {
                        HStack {
                            Text("截止日期")
                            Spacer()
                            FiveMinuteDateTimePicker(selection: $dueDate).fixedSize()
                        }
                    }
                }
                Section {
                    Toggle(isOn: $isCompleted) {
                        Label("標記為已完成", systemImage: isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isCompleted ? .green : .primary)
                    }
                    .tint(.green)
                }
                Section("備註") {
                    TextField("選填", text: $note, axis: .vertical).lineLimit(2...5)
                }
                if editing != nil {
                    Section {
                        Button(role: .destructive) { deleteTask() } label: { Label("刪除任務", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯任務" : "新增任務")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let e = editing {
                    topic = e.topic; content = e.content; date = e.date; note = e.note
                    isCompleted = e.isCompleted
                    if let d = e.dueDate { hasDueDate = true; dueDate = d }
                } else {
                    // 新任務：預設時間先對齊到 5 分鐘倍數，與選擇器一致
                    date = FiveMinuteDateTimePicker.roundedToFiveMinutes(Date())
                    dueDate = date
                }
            }
        }
    }

    private func save() {
        guard var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
        // 完成時間：原本未完成→改完成時記下現在；維持完成則沿用舊時間；取消完成則清空
        let completedAt: Date? = isCompleted ? (editing?.completedAt ?? Date()) : nil
        let task = SubordinateTask(
            id: editing?.id ?? UUID(),
            topic: topic.trimmingCharacters(in: .whitespaces),
            content: content.trimmingCharacters(in: .whitespaces),
            date: date, dueDate: hasDueDate ? dueDate : nil,
            note: note.trimmingCharacters(in: .whitespaces),
            isCompleted: isCompleted, completedAt: completedAt
        )
        if let idx = sub.tasks.firstIndex(where: { $0.id == task.id }) { sub.tasks[idx] = task }
        else { sub.tasks.append(task) }
        lifeStore.update(sub); dismiss()
    }

    private func deleteTask() {
        guard let e = editing, var sub = lifeStore.subordinates.first(where: { $0.id == subordinateId }) else { dismiss(); return }
        sub.tasks.removeAll { $0.id == e.id }
        lifeStore.update(sub); dismiss()
    }
}

// MARK: - 5 分鐘間隔 + 24 小時制日期時間選擇器

/// 包裝 UIDatePicker：分鐘只允許 5 的倍數，並強制 24 小時制（維持繁體中文）。
/// SwiftUI 原生 DatePicker 無法設定 minuteInterval，故以 UIViewRepresentable 實作。
struct FiveMinuteDateTimePicker: UIViewRepresentable {
    @Binding var selection: Date

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .compact
        picker.minuteInterval = 5
        picker.locale = Self.hour24Locale
        picker.date = selection
        picker.addTarget(context.coordinator,
                         action: #selector(Coordinator.valueChanged(_:)),
                         for: .valueChanged)
        picker.setContentHuggingPriority(.required, for: .horizontal)
        picker.setContentCompressionResistancePriority(.required, for: .horizontal)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        picker.minuteInterval = 5
        picker.locale = Self.hour24Locale
        if picker.date != selection { picker.date = selection }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        let parent: FiveMinuteDateTimePicker
        init(_ parent: FiveMinuteDateTimePicker) { self.parent = parent }
        @objc func valueChanged(_ sender: UIDatePicker) { parent.selection = sender.date }
    }

    /// 維持繁中、但強制 0–23 小時制
    private static var hour24Locale: Locale {
        var components = Locale.Components(locale: Locale(identifier: "zh_Hant_TW"))
        components.hourCycle = .zeroToTwentyThree
        return Locale(components: components)
    }

    /// 把時間對齊到最接近的 5 分鐘倍數（秒歸零）
    static func roundedToFiveMinutes(_ date: Date) -> Date {
        let cal = Calendar.current
        let minute = cal.component(.minute, from: date)
        let second = cal.component(.second, from: date)
        let target = Int((Double(minute) / 5.0).rounded()) * 5   // 0...60
        let base = cal.date(byAdding: .second, value: -second, to: date) ?? date
        return cal.date(byAdding: .minute, value: target - minute, to: base) ?? date
    }
}
