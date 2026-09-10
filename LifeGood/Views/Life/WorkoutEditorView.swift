import SwiftUI

// MARK: - 新增／編輯一次訓練（v25.351）
//
// 一次訓練底下可以掛多個動作；動作分「重量訓練」與「有氧」兩種欄位型態。
// 動作名稱可以從過去用過的名字直接挑，不用每次重打。

struct WorkoutEditorView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let session: WorkoutSession?
    let onSave: (WorkoutSession) -> Void

    @State private var date = Date()
    @State private var title = ""
    @State private var place = ""
    @State private var durationText = ""
    @State private var note = ""
    @State private var exercises: [WorkoutExercise] = []
    @State private var loaded = false

    private let accent = Color(red: 0.20, green: 0.78, blue: 0.45)

    private var bodyWeight: Double? { lifeStore.latestBodyWeightKg }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    TextField("這次訓練的名稱（例：胸推日）", text: $title)
                    TextField("地點（選填）", text: $place)
                    HStack {
                        Text("整場時間")
                        Spacer()
                        TextField("分鐘", text: $durationText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("分鐘").foregroundStyle(.secondary)
                    }
                }

                ForEach($exercises) { $e in
                    Section {
                        exerciseFields($e)
                    } header: {
                        HStack {
                            Text(e.name.isEmpty ? "動作" : e.name)
                            Spacer()
                            Button(role: .destructive) {
                                exercises.removeAll { $0.id == e.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                        }
                    } footer: {
                        if e.kind == .strength {
                            Text(previewText(e))
                        }
                    }
                }

                Section {
                    Button {
                        exercises.append(WorkoutExercise(kind: .strength))
                    } label: {
                        Label("加一個重量訓練動作", systemImage: "dumbbell.fill")
                    }
                    Button {
                        exercises.append(WorkoutExercise(name: "", kind: .cardio,
                                                         reps: 0, sets: 0, loadType: .none))
                    } label: {
                        Label("加一個有氧項目", systemImage: "figure.run")
                    }
                }

                Section {
                    TextField("備註", text: $note, axis: .vertical).lineLimit(1...4)
                } footer: {
                    if bodyWeight == nil && exercises.contains(where: { $0.loadType == .bodyweight }) {
                        Text("健康檔案還沒有體重紀錄，「自身體重」的動作暫時只會計入總次數，不會算進總訓練量。到醫療地圖補一筆體重就會納入。")
                    }
                }
            }
            .navigationTitle(session == nil ? "新增訓練" : "編輯訓練")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }
                        .bold().foregroundStyle(accent)
                        .disabled(exercises.isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let s = session {
                    date = s.date; title = s.title; place = s.place; note = s.note
                    durationText = s.durationMinutes > 0 ? String(Int(s.durationMinutes)) : ""
                    exercises = s.exercises
                } else {
                    exercises = [WorkoutExercise(kind: .strength)]
                }
            }
        }
    }

    // MARK: 動作欄位

    @ViewBuilder
    private func exerciseFields(_ e: Binding<WorkoutExercise>) -> some View {
        Picker("型態", selection: e.kind) {
            ForEach(WorkoutKind.allCases) { k in Text(k.rawValue).tag(k) }
        }
        .pickerStyle(.segmented)

        TextField(e.wrappedValue.kind == .strength ? "動作（例：伏地挺身）" : "項目（例：跑步）",
                  text: e.name)

        let names = lifeStore.workoutExerciseNames(kind: e.wrappedValue.kind)
        if !names.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(names.prefix(12), id: \.self) { n in
                        Button {
                            e.name.wrappedValue = n
                        } label: {
                            Text(n)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }

        if e.wrappedValue.kind == .strength {
            Stepper(value: e.reps, in: 0...500) {
                HStack {
                    Text("每組次數")
                    Spacer()
                    Text("\(e.wrappedValue.reps) 下")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Stepper(value: e.sets, in: 0...50) {
                HStack {
                    Text("組數")
                    Spacer()
                    Text("\(e.wrappedValue.sets) 組")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Picker("負荷", selection: e.loadType) {
                ForEach(WorkoutLoadType.allCases) { t in Text(t.rawValue).tag(t) }
            }
            if e.wrappedValue.loadType == .weight {
                HStack {
                    Text("重量")
                    Spacer()
                    TextField("公斤", value: e.loadKg, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Text("kg").foregroundStyle(.secondary)
                }
            }
        } else {
            HStack {
                Text("距離")
                Spacer()
                TextField("公里", value: e.distanceKm, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                Text("公里").foregroundStyle(.secondary)
            }
            HStack {
                Text("時間")
                Spacer()
                TextField("分鐘", value: e.durationMinutes, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                Text("分鐘").foregroundStyle(.secondary)
            }
            if let p = e.wrappedValue.paceMinPerKm {
                HStack {
                    Text("配速")
                    Spacer()
                    Text(String(format: "%.1f 分/公里", p)).foregroundStyle(.secondary)
                }
            }
        }
        TextField("動作備註（選填）", text: e.note)
    }

    /// 這個動作會拿到多少訓練量，邊填邊看得到
    private func previewText(_ e: WorkoutExercise) -> String {
        guard e.totalReps > 0 else { return "填上次數與組數後會顯示訓練量" }
        guard let v = e.volume(bodyWeightKg: bodyWeight) else {
            return "共 \(e.totalReps) 下（沒有負荷，不計入總訓練量）"
        }
        return "共 \(e.totalReps) 下・訓練量 " + WorkoutExercise.kgText(v)
    }

    private func save() {
        let cleaned = exercises.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        var s = session ?? WorkoutSession()
        s.date = date
        s.title = title.trimmingCharacters(in: .whitespaces)
        s.place = place.trimmingCharacters(in: .whitespaces)
        s.durationMinutes = Double(durationText) ?? 0
        s.note = note
        s.exercises = cleaned.map { e in
            var x = e
            x.name = x.name.trimmingCharacters(in: .whitespaces)
            return x
        }
        guard !s.exercises.isEmpty else { dismiss(); return }
        onSave(s)
        dismiss()
    }
}
