//
//  VehicleEditors.swift
//  LifeGood
//
//  [v25.540] 載具卡片的編輯器（照 RealEstateEditors.swift 的分法）：照片紀錄編輯器從 VehicleDetailView.swift 原封搬過來，
//  只多一個「類別」參數——卡片「照片與單據」的「＋」選單（加車輛照片、加保養單、加保險・稅費文件、加事故照片）
//  打開時類別先帶好。付費由呼叫端擋（這頁本身不擋）。
//

import SwiftUI

// MARK: - 車輛照片紀錄編輯器（支援多張照片，結構比照 RenovationPhotoEditor）

struct VehiclePhotoEditor: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss

    let vehicleId: UUID
    let editing: VehiclePhotoRecord?
    /// [v25.540] 新增時先帶好的類別（卡片「＋」選單選的那一項）；編輯既有紀錄時照紀錄自己的
    let presetCategory: VehiclePhotoCategory

    @State private var date: Date = Date()
    @State private var category: VehiclePhotoCategory = .maintenance
    @State private var title: String = ""
    @State private var note: String = ""
    @State private var photoFileNames: [String] = []
    @State private var showDeleteConfirm: Bool = false
    // 防止「儲存」連點：save() 把寫回 store 延後到下個 runloop，連點兩下會讀到同一份
    // vehicle 快照、各自 append，後寫者蓋掉前者（同型防護見 RenovationPhotoEditor.isSaving）
    @State private var isSaving: Bool = false
    /// [v25.538] setupInitial 只跑一次：相機、文件掃描是 fullScreenCover，關掉時會再觸發這頁的
    /// onAppear，以前會把 photoFileNames 蓋回進來時的樣子，剛拍的照片從畫面消失、檔案卻已經上傳
    @State private var didSetup: Bool = false

    /// [v25.538] 有沒有還沒存的東西。照片在選的當下就已經寫檔（新加的）或刪檔（原本的），
    /// 下滑關掉不會經過 cancel() 收拾，會留下孤兒檔或指向已刪檔案的紀錄，所以有變更時擋住下滑
    private var hasUnsavedChanges: Bool {
        guard didSetup else { return false }
        if photoFileNames != (editing?.photoFileNames ?? []) { return true }
        if let e = editing {
            return date != e.date || category != e.category || title != e.title || note != e.note
        }
        return !title.isEmpty || !note.isEmpty
    }

    /// [v25.540] 顯式 init（照 RenovationPhotoEditor）：多一個類別參數，預設保養維修（跟以前新增時一樣）。
    /// 類別的初值在這裡就放好，打開時不會先閃一下「保養維修」再換
    init(vehicleId: UUID, editing: VehiclePhotoRecord?, category: VehiclePhotoCategory = .maintenance) {
        self.vehicleId = vehicleId
        self.editing = editing
        self.presetCategory = category
        _category = State(initialValue: editing?.category ?? category)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    Picker("類別", selection: $category) {
                        ForEach(VehiclePhotoCategory.allCases) { c in
                            Label(c.rawValue, systemImage: c.icon).tag(c)
                        }
                    }
                    TextField("標題（例：五萬公里保養、牌照稅）", text: $title)
                } header: {
                    vehSectionHeader("基本資訊", icon: "calendar.circle.fill",
                                     gradient: [Color.teal, Color.teal.opacity(0.55)])
                }

                Section {
                    MultiPhotoGallery(
                        fileNames: $photoFileNames,
                        urlFor: { VehiclePhotoRecord.photoURL(for: $0) },
                        onSaveImage: { data in
                            VehiclePhotoRecord.savePhoto(data, id: UUID())
                        },
                        onDeleteFile: { name in
                            VehiclePhotoRecord.deletePhoto(name)
                        },
                        title: "照片"
                    )
                    .padding(.vertical, 4)
                } header: {
                    // 純文字標題：裝飾（標題／計數）由 MultiPhotoGallery 內建 header 負責，
                    // 這裡疊加會重複顯示（同型取捨見 RenovationPhotoEditor 照片 Section 註解）
                    Text("照片")
                } footer: {
                    Text("可拍照或從相簿一次選多張：保養單據、稅費收據、保險文件、事故照片等。")
                }

                Section {
                    TextField("選填備註（例：保養廠、金額、里程數）", text: $note, axis: .vertical).lineLimit(3)
                } header: {
                    vehSectionHeader("備註", icon: "note.text",
                                     gradient: [Color(.systemGray2), Color(.systemGray3)])
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("刪除此筆", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "新增照片紀錄" : "編輯照片紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { cancel() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(photoFileNames.isEmpty || isSaving)
                }
            }
            .alert("確定刪除？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) { deleteRecord() }
                Button("取消", role: .cancel) {}
            }
            .onAppear { setupInitial() }
        }
        // 有變更時只能按「取消」（清掉這次新加的照片檔、收斂已刪的檔名）或「儲存」
        .interactiveDismissDisabled(hasUnsavedChanges)
    }

    /// 統一 Section header（4pt Capsule 漸層色條 + 彩色圖示 + .subheadline.bold）
    private func vehSectionHeader(_ title: String, icon: String, gradient: [Color]) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(gradient.first ?? Color(.systemGray))
            Text(title)
                .font(.subheadline.weight(.bold))
        }
    }

    private func setupInitial() {
        guard !didSetup else { return }
        didSetup = true
        if let e = editing {
            date = e.date
            category = e.category
            title = e.title
            note = e.note
            photoFileNames = e.photoFileNames
        } else {
            // [v25.540] 新增：套用呼叫端帶的類別（加車輛照片→車輛照片、加保養單→保養維修…）
            category = presetCategory
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard var vehicle = store.vehicles.first(where: { $0.id == vehicleId }) else { return }
        isSaving = true
        let recordId = editing?.id ?? UUID()

        let record = VehiclePhotoRecord(
            id: recordId,
            date: date,
            category: category,
            title: title.trimmingCharacters(in: .whitespaces),
            photoFileNames: photoFileNames,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        if let idx = vehicle.photoRecords.firstIndex(where: { $0.id == recordId }) {
            vehicle.photoRecords[idx] = record
        } else {
            vehicle.photoRecords.append(record)
        }
        // 先關 sheet、下個 runloop 才改 @Published store：避免在關閉 sheet 的
        // view-update 交易裡同步改 observed state 造成真機閃退（同型見 RenovationPhotoEditor.save）
        let financeStore = store
        dismiss()
        DispatchQueue.main.async { financeStore.update(vehicle) }
    }

    /// 取消：清掉本次 session 新增、尚未存檔的照片檔；編輯模式下若刪了原有照片，
    /// 回寫 store 收斂檔名，避免孤兒引用（完整理由見 RenovationPhotoEditor.cancel 註解）
    private func cancel() {
        let original = Set(editing?.photoFileNames ?? [])
        for name in photoFileNames where !original.contains(name) {
            VehiclePhotoRecord.deletePhoto(name)
        }
        let remaining = photoFileNames.filter { original.contains($0) }
        if let e = editing, Set(remaining) != original,
           var vehicle = store.vehicles.first(where: { $0.id == vehicleId }),
           let idx = vehicle.photoRecords.firstIndex(where: { $0.id == e.id }) {
            vehicle.photoRecords[idx].photoFileNames = remaining
            let financeStore = store
            dismiss()
            DispatchQueue.main.async { financeStore.update(vehicle) }
            return
        }
        dismiss()
    }

    private func deleteRecord() {
        guard var vehicle = store.vehicles.first(where: { $0.id == vehicleId }),
              let e = editing else { return }
        // 刪畫面上即時的 photoFileNames 而非進場快照，避免漏刪編輯中新增的照片
        //（同型理由見 RenovationPhotoEditor.deleteRecord 註解）
        for name in photoFileNames {
            VehiclePhotoRecord.deletePhoto(name)
        }
        vehicle.photoRecords.removeAll { $0.id == e.id }
        let financeStore = store
        dismiss()
        DispatchQueue.main.async { financeStore.update(vehicle) }
    }
}
