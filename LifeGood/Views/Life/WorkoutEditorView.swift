import SwiftUI

// MARK: - 新增／編輯一次訓練（v25.351）
//
// 一次訓練底下可以掛多個動作；動作分「重量訓練」與「有氧」兩種欄位型態。
// 動作名稱可以從過去用過的名字直接挑，不用每次重打。
//
// [v25.551] 存檔改成先關畫面、下一個 runloop 才交給呼叫端寫 store；
// 改了開始時間（差 60 秒以上）或長度（差 1 分鐘以上）就清掉記錄器的真正結束時間 endedAt。
//
// [v25.552] 健康 v2（judge §5.3）：
// • 最上面先選運動（跑步／健走／騎車／登山／重訓／其他）；從健康頁「＋」選了哪一種就先選好（initialSport），
//   **不再預設一個空的重訓動作**（補記健走一打開就是一個健走項目）。
// • 沒填名字就用運動名（有氧「健走」、重訓「重量訓練」），不再默默丟掉沒名字的動作。
// • 時間可以打「35」或「35:20」（整場時間、有氧時間都是；WorkoutFormat.parseMinutes）；看不懂的紅字提示、不能存
//  （有氧時間欄也是：以前打「35:60」字變紅卻存得下去，存成打到一半還看得懂的 35:06）。
//   編輯 App 記的那一趟，整場時間顯示「32:10」，沒改就照原本的秒數存（以前砍成 32 分）。
// • 重訓動作切成有氧時清掉次數、組數、負荷（以前留著被算進動作統計）。
// • 配速一律 6'11"、騎車寫時速（以前「6.2 分/公里」）。
// • 存檔時用 MET 表估大卡存回（WorkoutFacts.applyKcalEstimate；健走 60 分鐘約 180，Apple 健康也寫這個）；
//   新增的記成手動補記（source = .manual）。

struct WorkoutEditorView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let session: WorkoutSession?
    /// [v25.552] 健康頁「＋」選單選的運動（新增時表單先選好）；編輯時不用（照那一趟的主運動）。
    /// 一定是 var＋預設 nil、宣告在 session 與 onSave 中間：memberwise 是 (session:initialSport:onSave:)，舊寫法照樣編得過
    var initialSport: WorkoutSport? = nil
    let onSave: (WorkoutSession) -> Void

    @State private var date = Date()
    @State private var title = ""
    @State private var place = ""
    @State private var durationText = ""
    @State private var note = ""
    @State private var exercises: [WorkoutExercise] = []
    @State private var loaded = false
    /// [v25.552] 最上面選的運動
    @State private var sport: WorkoutSport = .run
    /// [v25.552] 一打開時整場時間的字；存檔時沒改就保留原本的分鐘數（不因 32:10 ↔ 32.1667 來回四捨五入改到）
    @State private var originalDurationText = ""
    /// [v25.552] 有氧「時間」欄打的字看不懂的那幾個項目（id）：儲存鈕跟著變灰
    @State private var unreadableCardioTimes: Set<UUID> = []

    private let accent = Color(red: 0.20, green: 0.78, blue: 0.45)

    private var bodyWeight: Double? { lifeStore.latestBodyWeightKg }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("運動", selection: sportBinding) {
                        ForEach(WorkoutSport.allCases) { s in
                            Label(s.pickerName, systemImage: s.icon).tag(s)
                        }
                    }
                    DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    TextField(titlePlaceholder, text: $title)
                    TextField("地點（選填）", text: $place)
                    HStack {
                        Text("整場時間")
                        Spacer()
                        TextField("分鐘或 分:秒", text: $durationText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                    }
                } footer: {
                    if durationUnreadable {
                        Text("看不懂，請打分鐘（35）或分:秒（35:20）").foregroundStyle(.red)
                    }
                }

                ForEach($exercises) { $e in
                    Section {
                        exerciseFields($e)
                    } header: {
                        HStack {
                            MarqueeText(headerName(e))
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
                        exercises.append(Self.cardioExercise(sport.isCardio ? sport : .other))
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
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }
                        .bold().foregroundStyle(accent)
                        .disabled(exercises.isEmpty || durationUnreadable || cardioTimeUnreadable)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let s = session {
                    date = s.date; title = s.title; place = s.place; note = s.note
                    sport = s.primarySport
                    // [v25.552] 32.17 分 →「32:10」（以前砍成 32）
                    let text = WorkoutFormat.minutesInput(s.durationMinutes)
                    durationText = text
                    originalDurationText = text
                    exercises = s.exercises
                } else {
                    // [v25.552] 從「＋」選的運動先選好；不再預設一個空的重訓動作
                    let chosen = initialSport ?? .run
                    sport = chosen
                    exercises = chosen == .strength ? [WorkoutExercise(kind: .strength)] : [Self.cardioExercise(chosen)]
                    originalDurationText = ""
                }
            }
        }
    }

    // MARK: 字（先組好再進 Text）

    private var navTitle: String {
        if session != nil { return "編輯訓練" }
        return sport == .strength ? "記一次重訓" : "補記一趟" + sport.displayName
    }

    private var titlePlaceholder: String {
        sport == .strength ? "這次訓練的名稱（例：胸推日）" : "名稱（選填，例：河濱晨跑）"
    }

    /// 整場時間打的字看不懂（空白算 0、看得懂）
    private var durationUnreadable: Bool {
        WorkoutFormat.parseMinutes(durationText) == nil
    }

    /// 還在表單上的有氧項目裡，有「時間」打得看不懂的（刪掉、切成重訓的不算）
    private var cardioTimeUnreadable: Bool {
        exercises.contains { $0.kind == .cardio && unreadableCardioTimes.contains($0.id) }
    }

    /// 給 CardioMinutesField：這個項目的時間欄看不懂（一樣的值不重寫，免得多一次畫面更新）
    private func cardioTimeInvalid(_ id: UUID) -> Binding<Bool> {
        Binding(get: { unreadableCardioTimes.contains(id) }, set: { bad in
            guard bad != unreadableCardioTimes.contains(id) else { return }
            if bad {
                unreadableCardioTimes.insert(id)
            } else {
                unreadableCardioTimes.remove(id)
            }
        })
    }

    private func headerName(_ e: WorkoutExercise) -> String {
        let n = e.name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { return n }
        return e.kind == .cardio ? defaultName(e) : "動作"
    }

    /// 名字欄的提示：有氧寫「沒填就叫「健走」」
    private func namePlaceholder(_ e: WorkoutExercise) -> String {
        if e.kind == .strength { return "動作（例：伏地挺身）" }
        return "名稱（選填，沒填就叫「" + defaultName(e) + "」）"
    }

    /// 沒填名字時存的名字：有氧＝這個項目的運動（沒有就用最上面選的）；重訓＝「重量訓練」
    private func defaultName(_ e: WorkoutExercise) -> String {
        if e.kind == .strength { return "重量訓練" }
        return (e.sport ?? (sport.isCardio ? sport : .other)).displayName
    }

    /// 配速列：騎車寫「時速 21.5 公里/時」，其他「配速 6'11"」；算不出來不顯示
    private func paceRow(_ e: WorkoutExercise) -> (label: String, value: String)? {
        guard e.kind == .cardio else { return nil }
        if e.resolvedSport == .bike {
            guard let v = WorkoutFormat.speedKmh(km: e.distanceKm, minutes: e.durationMinutes) else { return nil }
            return ("時速", WorkoutFormat.speed(v))
        }
        guard let p = e.paceMinPerKm else { return nil }
        return ("配速", WorkoutFormat.pace(p))
    }

    // MARK: 選運動（[v25.552]）

    private var sportBinding: Binding<WorkoutSport> {
        Binding(get: { sport }, set: { applySport($0) })
    }

    /// 換運動：有氧 → 第一個有氧動作改成這一種（名字是舊的運動名就清掉，存檔時補新的），沒有就在最前面加一個；
    /// 名字空白的預設重訓動作拿掉。重訓 → 沒填東西的有氧動作拿掉，沒有重訓動作就加一個空的。
    /// 這一趟的名稱是運動名（App 記的「跑步」）就跟著換成新的運動名
    private func applySport(_ new: WorkoutSport) {
        guard new != sport else { return }
        sport = new
        let t = title.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty, Self.isSportName(t) { title = new.displayName }
        if new == .strength {
            exercises.removeAll { $0.kind == .cardio && isBlankCardio($0) }
            if !exercises.contains(where: { $0.kind == .strength }) {
                exercises.append(WorkoutExercise(kind: .strength))
            }
        } else {
            exercises.removeAll { $0.kind == .strength && $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            if let i = exercises.firstIndex(where: { $0.kind == .cardio }) {
                exercises[i].sport = new
                if Self.isSportName(exercises[i].name) { exercises[i].name = "" }
            } else {
                exercises.insert(Self.cardioExercise(new), at: 0)
            }
        }
    }

    /// 什麼都沒填的有氧項目：名字空白（或只是運動名）、距離 0、時間 0、沒有路線
    private func isBlankCardio(_ e: WorkoutExercise) -> Bool {
        Self.isSportName(e.name) && e.distanceKm <= 0 && e.durationMinutes <= 0 && e.route.isEmpty
    }

    /// 名字是空白、或只是運動名（含手錶舊名「走路」「健行」）
    static func isSportName(_ n: String) -> Bool {
        let t = n.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t == "走路" || t == "健行" { return true }
        return WorkoutSport.allCases.contains { $0.displayName == t }
    }

    /// 一個空的有氧項目（名字空白：存檔時補運動名）
    static func cardioExercise(_ s: WorkoutSport) -> WorkoutExercise {
        WorkoutExercise(name: "", kind: .cardio, reps: 0, sets: 0, loadType: .none, sport: s)
    }

    /// 型態切換（U1 C13）：重訓切有氧時次數、組數、負荷清掉，運動種類用最上面選的；有氧切重訓拿掉運動種類
    private func kindBinding(_ e: Binding<WorkoutExercise>) -> Binding<WorkoutKind> {
        Binding(get: { e.wrappedValue.kind }, set: { new in
            var x = e.wrappedValue
            guard x.kind != new else { return }
            x.kind = new
            if new == .cardio {                       // 重訓切有氧：次數組數負荷清掉（以前留著被算進動作統計）
                x.reps = 0; x.sets = 0; x.loadType = .none; x.loadKg = 0
                x.sport = sport.isCardio ? sport : .other
            } else {
                x.sport = nil
            }
            e.wrappedValue = x
        })
    }

    // MARK: 動作欄位

    @ViewBuilder
    private func exerciseFields(_ e: Binding<WorkoutExercise>) -> some View {
        Picker("型態", selection: kindBinding(e)) {
            ForEach(WorkoutKind.allCases) { k in Text(k.rawValue).tag(k) }
        }
        .pickerStyle(.segmented)

        TextField(namePlaceholder(e.wrappedValue), text: e.name)

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
                // [v25.552] 可以打「35」或「35:20」
                CardioMinutesField(minutes: e.durationMinutes, invalid: cardioTimeInvalid(e.wrappedValue.id))
            }
            if let row = paceRow(e.wrappedValue) {
                HStack {
                    Text(row.label)
                    Spacer()
                    Text(row.value).foregroundStyle(.secondary)
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
        var s = session ?? WorkoutSession()
        s.date = date
        s.title = title.trimmingCharacters(in: .whitespaces)
        s.place = place.trimmingCharacters(in: .whitespaces)
        // [v25.552] 時間可以是「35」「35:20」「1:05:12」；編輯時沒動這一欄就保留原本的分鐘數（含秒）
        if session == nil || durationText != originalDurationText {
            s.durationMinutes = WorkoutFormat.parseMinutes(durationText) ?? 0
        }
        // [v25.551] 改了開始時間或長度，記錄器的「真正結束時間」就對不上了，清掉（寫 Apple 健康時改用開始＋時間）。
        // 差不到 1 分鐘不算改過。
        if let old = session, old.endedAt != nil,
           abs(old.date.timeIntervalSince(date)) >= 60 || abs(old.durationMinutes - s.durationMinutes) >= 1 {
            s.endedAt = nil
        }
        s.note = note
        // [v25.552] 沒名字的動作不再丟掉：用運動名（有氧）或「重量訓練」；最上面選的有氧寫進第一個有氧動作
        let firstCardioId = exercises.first(where: { $0.kind == .cardio })?.id
        let chosen = sport
        s.exercises = exercises.map { e in
            var x = e
            if x.kind == .cardio, chosen.isCardio, x.id == firstCardioId { x.sport = chosen }
            x.name = x.name.trimmingCharacters(in: .whitespaces)
            if x.name.isEmpty { x.name = defaultName(x) }
            return x
        }
        if session == nil { s.source = .manual }   // 編輯的不改（nil 就留 nil）
        // [v25.552] 大卡：沒量到的用 MET 表估好存回（健走 60 分鐘約 180；以前寫 Apple 健康時一律 8 MET＝576）
        WorkoutFacts.applyKcalEstimate(&s, bodyWeightKg: bodyWeight)
        guard !s.exercises.isEmpty else { dismiss(); return }
        // [v25.551] 先關 sheet、下一個 runloop 才寫 store（呼叫端在 onSave 裡改 @Published 的 lifeStore）：
        // 避免在關閉 sheet 的畫面更新裡同步改被觀察的狀態（同型見 VehicleEditors 的 save）
        let handOff = onSave
        let saved = s
        dismiss()
        DispatchQueue.main.async { handOff(saved) }
    }
}

// MARK: - 有氧時間欄（[v25.552]）

/// 有氧時間：可以打「35」或「35:20」；打不懂的先不改數字（字變紅、表單的儲存鈕變灰）
private struct CardioMinutesField: View {
    @Binding var minutes: Double
    /// 打的字看不懂（WorkoutEditorView 的儲存鈕跟著變灰）
    @Binding var invalid: Bool
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        TextField("分鐘或 分:秒", text: $text)
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.trailing)
            .foregroundStyle(unreadable ? Color.red : Color.primary)
            .frame(width: 110)
            .onAppear {
                guard !loaded else { return }
                loaded = true
                text = WorkoutFormat.minutesInput(minutes)
                invalid = false                            // 一打開填的字一定看得懂（切成重訓再切回來時清掉舊的）
            }
            .onChange(of: text) { _, new in
                let parsed = WorkoutFormat.parseMinutes(new)
                invalid = parsed == nil
                guard let m = parsed else { return }
                // 只差不到一秒不寫回：一打開把「32:10」填進來時，不要把 App 記的 32.1694 分改成 32.1667
                if WorkoutFormat.wholeSeconds(m * 60) != WorkoutFormat.wholeSeconds(minutes * 60) {
                    minutes = m
                }
            }
    }

    private var unreadable: Bool { WorkoutFormat.parseMinutes(text) == nil }
}
